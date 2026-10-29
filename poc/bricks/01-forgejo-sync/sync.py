#!/usr/bin/env python3
"""Brique 01 : synchronise un dépôt amont vers son miroir sans jamais rien perdre.

Modèle de refs du miroir (dépôt nu) :
  refs/upstream/heads/*, refs/upstream/tags/*  vue courante de l'amont ;
  refs/archive/<horodatage>/{heads,tags}/*     anciennes valeurs réécrites ou supprimées ;
  refs/sync/incoming/*                         zone de transit, vidée à chaque run ;
  refs/sync/bundled/<ref>                      valeur de <ref> déjà mise en bundle.
Les autres refs (branches custom, par exemple) ne sont jamais touchées.

Chaque run écrit un rapport JSON (événements + état complet des refs) et, s'il y a
de nouveaux objets, un bundle git incrémental. Les deux partent en archive WORM :
rejouer les bundles dans l'ordre puis appliquer les refs du dernier rapport
reconstruit le miroir (voir --restore). Un bundle raté est rattrapé au run suivant.

Codes de sortie : 0 = rien d'anormal ; 2 = réécriture amont détectée (force-push
sur une branche protégée, tag déplacé ou supprimé) ; 1 = erreur.
"""
import argparse
import datetime
import fnmatch
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

UPSTREAM = "refs/upstream/"
INCOMING = "refs/sync/incoming/"
BUNDLED = "refs/sync/bundled/"
ARCHIVE = "refs/archive/"
SCHEMA = "https://supply-chain.example/sync-report/v1"
CRITICAL = {"force-push", "tag-moved", "tag-deleted"}


class GitError(Exception):
    pass


def git(repo, *args, stdin=None, check=True):
    # Pas de hooks, objets vérifiés à la réception (fsck), protocoles limités par
    # GIT_ALLOW_PROTOCOL (posé par main) : pas de transport `ext::` ni de `file` en production.
    # LC_ALL=C : les messages de git sont analysés (« empty bundle ») et ne doivent pas être traduits.
    cmd = ["git", "-C", str(repo), "-c", "core.hooksPath=/dev/null",
           "-c", "transfer.fsckObjects=true", *args]
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"})
    if check and r.returncode != 0:
        raise GitError(f"{' '.join(args[:2])} : {r.stderr.strip()}")
    return r


def refs(repo, prefix):
    out = git(repo, "for-each-ref", "--format=%(refname) %(objectname)", prefix).stdout
    return {name[len(prefix):]: sha for name, sha in (line.split() for line in out.splitlines())}


def is_ancestor(repo, old, new):
    return git(repo, "merge-base", "--is-ancestor", old, new, check=False).returncode == 0


def classify(repo, name, old, new, protected):
    """Type d'événement pour une ref `heads/x` ou `tags/x` qui a changé."""
    tag = name.startswith("tags/")
    if old is None:
        return "tag-created" if tag else "branch-created"
    if new is None:
        return "tag-deleted" if tag else "branch-deleted"
    if tag:
        return "tag-moved"
    if is_ancestor(repo, old, new):
        return "fast-forward"
    branch = name[len("heads/"):]
    if any(fnmatch.fnmatchcase(branch, p) for p in protected):
        return "force-push"
    return "force-push-unprotected"


def init_mirror(mirror):
    if not (mirror / "HEAD").exists():
        mirror.mkdir(parents=True, exist_ok=True)
        git(mirror, "init", "--quiet", "--bare")
        # Journal de toutes les mises à jour de refs, en plus des rapports.
        git(mirror, "config", "core.logAllRefUpdates", "always")


def sync(mirror, url, stamp, protected, bundle_dir, push_url=None):
    """Un run de synchronisation. Renvoie le rapport (dict)."""
    report = {"schema": SCHEMA, "upstream": url, "stamp": stamp, "events": [],
              "refs": {}, "bundle": None, "status": "ok", "error": None}
    init_mirror(mirror)
    # --prune ne s'applique qu'à la zone de transit : rien n'est supprimé ailleurs.
    git(mirror, "fetch", "--quiet", "--prune", "--no-tags", "--no-write-fetch-head", url,
        f"+refs/heads/*:{INCOMING}heads/*", f"+refs/tags/*:{INCOMING}tags/*")
    old, new = refs(mirror, UPSTREAM), refs(mirror, INCOMING)

    tx = []
    for name in sorted(old.keys() | new.keys()):
        o, n = old.get(name), new.get(name)
        if o == n:
            continue
        kind = classify(mirror, name, o, n, protected)
        event = {"type": kind, "ref": name, "old": o, "new": n, "archive": None}
        if o is not None and kind != "fast-forward":
            # Toute valeur écrasée ou supprimée est conservée sous refs/archive.
            event["archive"] = f"{ARCHIVE}{stamp}/{name}"
            tx.append(f"create {event['archive']} {o}")
        if n is None:
            tx.append(f"delete {UPSTREAM}{name} {o}")
        else:
            # La valeur attendue (o, ou zéro pour une création) protège des runs concurrents.
            tx.append(f"update {UPSTREAM}{name} {n} {o or '0' * len(n)}")
        report["events"].append(event)
    tx += [f"delete {INCOMING}{name} {sha}" for name, sha in new.items()]

    if tx:
        git(mirror, "update-ref", "--stdin", stdin="\n".join(tx) + "\n")
    report["refs"] = {f"{UPSTREAM}{k}": v for k, v in refs(mirror, UPSTREAM).items()}
    report["refs"].update({f"{ARCHIVE}{k}": v for k, v in refs(mirror, ARCHIVE).items()})
    if any(e["type"] in CRITICAL for e in report["events"]):
        report["status"] = "rewrite-detected"

    try:
        report["bundle"] = write_bundle(mirror, stamp, report["refs"], bundle_dir)
        if push_url:
            push(mirror, push_url)
    except (GitError, OSError) as e:
        # Les refs sont déjà à jour : le rapport garde les événements, et le run
        # suivant reprend le bundle et la publication.
        report["status"], report["error"] = "error", str(e)
    return report


def write_bundle(mirror, stamp, current, bundle_dir):
    """Bundle incrémental des refs `upstream` et `archive` qui ont changé depuis le
    dernier bundle réussi ; les objets déjà mis en bundle sont exclus.

    git omet d'un bundle les refs dont l'objet est exclu (archive d'une tête déjà
    sauvegardée, retour en arrière) : c'est le rapport qui fait foi pour les refs.
    """
    bundled = refs(mirror, BUNDLED)
    todo = sorted(ref for ref, sha in current.items() if bundled.get(ref) != sha)
    known = sorted(set(bundled.values()))
    info = None
    if todo:
        bundle_dir.mkdir(parents=True, exist_ok=True)
        path = bundle_dir / f"{stamp}.bundle"
        r = git(mirror, "bundle", "create", "--quiet", str(path), "--stdin",
                stdin="\n".join(todo + [f"^{sha}" for sha in known]) + "\n", check=False)
        if r.returncode == 0:
            info = {"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "refs": todo, "prerequisites": known}
        elif "empty bundle" not in r.stderr:
            raise GitError(f"bundle create : {r.stderr.strip()}")
    tx = [f"update {BUNDLED}{ref} {current[ref]}" for ref in todo]
    tx += [f"delete {BUNDLED}{ref}" for ref in bundled if ref not in current]
    if tx:
        git(mirror, "update-ref", "--stdin", stdin="\n".join(tx) + "\n")
    return info


def push(mirror, push_url):
    """Publie la vue amont et les archives dans le dépôt miroir de Forgejo.

    Le dépôt Forgejo appartient au seul compte de synchronisation : le --force
    y est sans risque, car toute valeur écrasée est déjà sous refs/archive.
    """
    git(mirror, "push", "--quiet", "--force", "--prune", push_url,
        f"{UPSTREAM}heads/*:refs/heads/*", f"{UPSTREAM}tags/*:refs/tags/*",
        f"{ARCHIVE}*:{ARCHIVE}*")


def restore(target, bundles, report):
    """Reconstruit un miroir à partir des bundles (dans l'ordre) et du dernier rapport."""
    init_mirror(target)
    for b in bundles:
        git(target, "bundle", "verify", "--quiet", str(b))
        git(target, "fetch", "--quiet", "--no-write-fetch-head", str(b), "+refs/*:refs/sync/restore/*")
    expected = report["refs"]
    tx = [f"update {ref} {sha}" for ref, sha in sorted(expected.items())]
    tx += [f"delete refs/sync/restore/{r}" for r in refs(target, "refs/sync/restore/")]
    git(target, "update-ref", "--stdin", stdin="\n".join(tx) + "\n")
    git(target, "fsck", "--no-progress", "--no-dangling")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--mirror", type=Path, required=True, help="dépôt nu du miroir")
    p.add_argument("--upstream", help="URL de l'amont (https)")
    p.add_argument("--report-dir", type=Path, required=True)
    p.add_argument("--bundle-dir", type=Path, required=True)
    p.add_argument("--push", help="URL du dépôt miroir dans Forgejo")
    p.add_argument("--protected", nargs="*", default=["main", "master", "release*", "v*"],
                   help="branches dont un force-push est critique (motifs fnmatch)")
    p.add_argument("--stamp", help="horodatage du run (tests) ; par défaut maintenant, en UTC")
    p.add_argument("--allow-file", action="store_true", help="autorise le protocole file (tests)")
    p.add_argument("--restore", type=Path, help="reconstruit un miroir à partir des bundles et du dernier rapport")
    a = p.parse_args(argv)

    # La restauration lit des bundles locaux, d'où le protocole file.
    os.environ["GIT_ALLOW_PROTOCOL"] = "https:file" if a.allow_file or a.restore else "https"
    stamp = a.stamp or datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    if a.restore:
        reports = [json.loads(f.read_text()) for f in sorted(a.report_dir.glob("*.json"))]
        last = [rep for rep in reports if rep["status"] != "error"][-1]
        restore(a.restore, sorted(a.bundle_dir.glob("*.bundle")), last)
        return 0

    a.report_dir.mkdir(parents=True, exist_ok=True)
    try:
        report = sync(a.mirror, a.upstream, stamp, a.protected, a.bundle_dir, a.push)
    except GitError as e:
        report = {"schema": SCHEMA, "upstream": a.upstream, "stamp": stamp, "status": "error",
                  "error": str(e), "events": [], "refs": {}, "bundle": None}
    (a.report_dir / f"{stamp}.json").write_text(json.dumps(report, indent=2) + "\n")
    for e in report["events"]:
        print(f"{e['type']:24} {e['ref']}  {(e['old'] or '-')[:12]} -> {(e['new'] or '-')[:12]}")
    if report["status"] == "error":
        print(f"erreur : {report['error']}", file=sys.stderr)
        return 1
    return 2 if report["status"] == "rewrite-detected" else 0


if __name__ == "__main__":
    sys.exit(main())
