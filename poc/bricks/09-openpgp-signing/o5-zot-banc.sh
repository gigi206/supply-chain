#!/usr/bin/env bash
# Brique 09, banc hors réseau d'o5-zot-controle.py (contrôle des données tirées de Zot) : layouts OCI et enveloppes fabriqués
# sur l'hôte, un cas nominal et des témoins. Ne couvre pas oras ni cosign (réseau), seulement le contrôle qui juge leurs sorties.
# Usage : poc/bricks/09-openpgp-signing/o5-zot-banc.sh   (journal : resultats/o5-zot-banc.log ; dossier effacé à la main)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
B=$HOME/.cache/supply-chain-poc/09/o5-zot-banc
PY=$here/o5-zot-controle.py
[ ! -e "$B" ] || { echo "KO   $B existe déjà" >&2; exit 1; }
mkdir -p "$B"
# Fabrique : python hors du dossier des données, chemins en arguments
python3 -I - "$B" <<'PY'
import base64, hashlib, io, json, os, sys, tarfile
B = sys.argv[1]
contenu = b"contenu du fichier non signe du banc\n" * 100
def sha(b): return hashlib.sha256(b).hexdigest()
def layout(nom, membres, couche_type="application/vnd.oci.image.layer.v1.tar", diff_faux=False, alterer_manifeste=False, lien=False):
    d = os.path.join(B, nom); os.makedirs(os.path.join(d, "blobs", "sha256"))
    def ecrire(b):
        open(os.path.join(d, "blobs", "sha256", sha(b)), "wb").write(b); return "sha256:" + sha(b)
    t = io.BytesIO()
    with tarfile.open(fileobj=t, mode="w", format=tarfile.USTAR_FORMAT) as tf:
        for n, c in membres:
            i = tarfile.TarInfo(n); i.mtime = 0
            if lien:
                i.type = tarfile.SYMTYPE; i.linkname = "/etc/passwd"; tf.addfile(i)
            else:
                i.size = len(c); tf.addfile(i, io.BytesIO(c))
    couche = t.getvalue(); dc = ecrire(couche)
    cfg = json.dumps({"architecture": "amd64", "os": "linux", "rootfs": {"type": "layers", "diff_ids": ["sha256:" + "0" * 64 if diff_faux else dc]}}).encode()
    dcfg = ecrire(cfg)
    man = json.dumps({"schemaVersion": 2, "mediaType": "application/vnd.oci.image.manifest.v1+json",
                      "config": {"mediaType": "application/vnd.oci.image.config.v1+json", "digest": dcfg, "size": len(cfg)},
                      "layers": [{"mediaType": couche_type, "digest": dc, "size": len(couche)}]}).encode()
    dm = ecrire(man)
    if alterer_manifeste:
        p = os.path.join(d, "blobs", "sha256", dm.split(":")[1]); open(p, "wb").write(man + b" ")   # un octet de plus, digest de l'index inchangé
    json.dump({"schemaVersion": 2, "manifests": [{"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": dm, "size": len(man)}]},
              open(os.path.join(d, "index.json"), "w"))
    open(os.path.join(d, "digest"), "w").write(dm)
open(os.path.join(B, "attendu"), "w").write(sha(contenu))
layout("nominal", [("fichier.bin", contenu)])
layout("autre-contenu", [("fichier.bin", contenu + b"x")])
layout("deux-membres", [("fichier.bin", contenu), ("autre.bin", b"y")])
layout("autre-nom", [("autre.bin", contenu)])
layout("gzip", [("fichier.bin", contenu)], couche_type="application/vnd.oci.image.layer.v1.tar+gzip")
layout("diff-ids", [("fichier.bin", contenu)], diff_faux=True)
layout("manifeste-altere", [("fichier.bin", contenu)], alterer_manifeste=True)
layout("lien-symbolique", [("fichier.bin", b"")], lien=True)
dm = open(os.path.join(B, "nominal", "digest")).read()
def env(sujet, ptype="https://slsa.dev/provenance/v1", n=1):
    st = {"_type": "https://in-toto.io/Statement/v1", "predicateType": ptype,
          "subject": [{"name": "r", "digest": {"sha256": s}} for s in sujet],
          "predicate": {"buildDefinition": {"buildType": "https://tekton.dev/chains/v2/slsa"},
                        "runDetails": {"builder": {"id": "https://tekton.dev/chains/v2"}, "metadata": {"invocationId": f"inv-{n}"}}}}
    return json.dumps({"payloadType": "application/vnd.in-toto+json", "payload": base64.b64encode(json.dumps(st).encode()).decode(), "signatures": [{"sig": "x"}]})
h = dm.split(":")[1]
open(os.path.join(B, "env-nominal.json"), "w").write(env([h], n=1) + "\n" + env([h], n=2) + "\n")
open(os.path.join(B, "env-autre-sujet.json"), "w").write(env([h]) + "\n" + env(["1" * 64]) + "\n")
open(os.path.join(B, "env-deux-sujets.json"), "w").write(env([h, "2" * 64]) + "\n")
open(os.path.join(B, "env-v02.json"), "w").write(env([h], ptype="https://slsa.dev/provenance/v0.2") + "\n")
open(os.path.join(B, "env-vide.json"), "w").write("")
PY
n_ok=0; n_ko=0
cas() { # libellé code_attendu motif mode args… : lance le contrôle, juge le code et le motif de la ligne REFUS
  local l=$1 c=$2 m=$3 o r; shift 3
  o=$(python3 -I "$PY" "$@" 2>&1); r=$?
  if [ "$r" = "$c" ] && { [ -z "$m" ] || grep -q -E "^REFUS .*$m" <<<"$o"; }; then echo "OK   $l : code $r${m:+, motif « $m »}"; n_ok=$((n_ok + 1))
  else echo "KO   $l : code $r (attendu $c${m:+, motif « $m »})"; sed 's/^/     | /' <<<"$o"; n_ko=$((n_ko + 1)); fi
}
{
echo "banc commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; o5-zot-controle.py $(sha256sum < "$PY" | cut -c1-16)… ; o5-zot-banc.sh $(sha256sum < "$0" | cut -c1-16)…"
set +e
A=$(cat "$B/attendu"); D=$(cat "$B/nominal/digest")
echo "### layouts"
cas "nominal" 0 "" layout "$B/nominal" "$D" fichier.bin "$A"
python3 -I "$PY" layout "$B/nominal" "$D" fichier.bin "$A" | sed 's/^/     | /'
for c in autre-contenu:'fichier de la couche' deux-membres:'couche : membres' autre-nom:'couche : membres' gzip:'types' \
    diff-ids:'diff_ids' manifeste-altere:'sha256 des octets' lien-symbolique:'couche : membres'; do
  cas "${c%%:*}" 3 "${c#*:}" layout "$B/${c%%:*}" "$(cat "$B/${c%%:*}/digest")" fichier.bin "$A"
done
cas "nominal, autre digest demandé" 3 "index" layout "$B/nominal" "$(cat "$B/gzip/digest")" fichier.bin "$A"
echo "### enveloppes"
cas "enveloppes nominales" 0 "" enveloppes "$B/env-nominal.json" "$D"
python3 -I "$PY" enveloppes "$B/env-nominal.json" "$D" | sed 's/^/     | /'
cas "une enveloppe d'un autre sujet" 3 "sujet" enveloppes "$B/env-autre-sujet.json" "$D"
cas "deux sujets" 3 "sujet" enveloppes "$B/env-deux-sujets.json" "$D"
cas "SLSA v0.2" 3 "predicateType" enveloppes "$B/env-v02.json" "$D"
cas "aucune enveloppe" 3 "aucune enveloppe" enveloppes "$B/env-vide.json" "$D"
echo "bilan : $n_ok OK, $n_ko KO"
echo "banc fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "à effacer après archivage (chemin littéral) : $B"
[ "$n_ko" = 0 ]
} 2>&1 | tee "$here/resultats/o5-zot-banc.log"
