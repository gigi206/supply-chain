#!/usr/bin/env bash
# Brique 07a, G7, point 3 révisé (resultats/g7-replanification.md, notes de 2026-11-20T19:09:44Z et 19:13:11Z) : lecture d'un
# balayage de Zot dans le journal de zot.service (sc-stockage), puis comptes des mêmes lignes dans Loki, à travers Grafana (compte
# auditeur). Écrit le 20/11/2026, lancé sur accord nommé (« Oui », 20/11, lecture de B20).
# Lecture seule : ssh -n, sudo journalctl et systemctl show sur la VM ; rien n'est écrit sur la VM, dans Zot, dans Loki ni dans le
# cluster. Aucun fichier temporaire : les sorties sont masquées (motif jeton|token) puis résumées par python, en mémoire.
# Rien de Grafana n'est archivé hors des comptes et des heures (ni ligne, ni réponse brute).
# Usage (racine du dépôt) : JOUR=2026-11-20 DE=15:00 A=19:00 mise exec -- poc/bricks/07a-sbom-grype/g7-balayage.sh
#   (heures UTC de la fenêtre ; journal resultats/g7-balayage-<JJ>-<MM>.log, refusé s'il existe)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"   # sur, S, P
JOUR=${JOUR:?JOUR=AAAA-MM-JJ}; DE=${DE:?DE=HH:MM}; A=${A:?A=HH:MM}
LOG=$here/resultats/g7-balayage-${JOUR:8:2}-${JOUR:5:2}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
MASQUE='/jeton\|token/I c\[ligne masquée : motif jeton|token]'

resume() { # lignes de zot.service (JSON de Zot, une par ligne) sur l'entrée standard, déjà masquées
  python3 -I -c '
import json, sys, collections
gc, dec, autres, masq, nonjson = [], [], collections.Counter(), 0, 0
TIRET, ABSENT = "-", "absent"
suivis = ("builds/scan/essai-07a", "builds/scan/essai-scan", "builds/scan/sample-app", "builds/scan/sample-app-deb", "vulndb/grype")
passage = {}
for l in sys.stdin:
    l = l.rstrip("\n")
    if l.startswith("[ligne masquée"): masq += 1; continue
    try: d = json.loads(l)
    except ValueError: nonjson += 1; continue
    m, t = d.get("message", ""), d.get("time", "")
    if m.startswith("executing gc of orphaned blobs for "):
        r = m.rsplit("/var/lib/zot/", 1)[-1]
        gc.append((t, r))
        if r in suivis: passage[r] = t
    elif "decision" in d:
        dec.append(d)
    else:
        autres[m[:60]] += 1
ts = sorted([t for t, _ in gc])
print(f"lignes : {sum(autres.values()) + len(gc) + len(dec)} JSON lues, {masq} masquée(s), {nonjson} non JSON")
print(f"« executing gc of orphaned blobs » : {len(gc)} ; premier {ts[0] if ts else TIRET} ; dernier {ts[-1] if ts else TIRET}")
for k, v in sorted(autres.items()): print(f"  autre message : {v} × « {k} »")
print("passage des dépôts suivis (début de « executing gc ») :")
for r in suivis: print(f"  {r:28} {passage.get(r, ABSENT)}")
print(f"décisions de rétention : {len(dec)}")
c = collections.Counter((d.get("repository"), d.get("decision"), d.get("reason")) for d in dec)
for (r, de, re_), n in sorted(c.items(), key=lambda x: str(x)): print(f"  {n} × {r} | {de} | {re_}")
for d in dec:
    if d.get("decision") != "keep":
        print("  non keep : " + " | ".join(f"{k}={d.get(k)}" for k in ("time", "repository", "tag", "reference", "digest", "pushTimestamp", "lastPullTimestamp", "dry-run") if k in d))
'
}

{
  echo "# g7-balayage.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16)"
  echo "# fenêtre : $JOUR $DE à $A UTC ; lecture seule (ssh -n, sudo journalctl, systemctl show ; Grafana en comptes)"
  echo "## 1. zot.service"
  sur sc-stockage 'date -u +%Y-%m-%dT%H:%M:%SZ; systemctl show zot.service -p ActiveState -p ActiveEnterTimestamp -p ExecMainStartTimestamp -p NRestarts' < /dev/null
  echo "## 2. profondeur du journal de zot.service"
  sur sc-stockage 'sudo journalctl -u zot.service -o short-iso-precise --no-pager | head -n 1 | cut -c1-32; sudo journalctl --disk-usage' < /dev/null
  echo "## 3. balayage dans le journal ($JOUR $DE à $A UTC ; lignes gc, garbage, retention, decision)"
  sur sc-stockage "sudo journalctl -u zot.service --since '$JOUR $DE:00 UTC' --until '$JOUR $A:00 UTC' -o cat --no-pager | grep -iE 'gc|garbage|retention|decision' || true" < /dev/null \
    | sed "$MASQUE" | resume
  echo "## 4. mêmes lignes dans Loki, à travers Grafana (auditeur ; comptes et heures seulement)"
  de=$(date -u -d "$JOUR $DE:00Z" +%s)000; a=$(date -u -d "$JOUR $A:00Z" +%s)000
  for e in '{noeud="sc-stockage", source="journal", unite="zot.service"} |= "executing gc of orphaned blobs"' \
           '{noeud="sc-stockage", source="journal", unite="zot.service"} |= "decision"'; do
    q=$(jq -nc --arg e "$e" --arg de "$de" --arg a "$a" \
      '{queries: [{refId: "A", datasource: {uid: "loki"}, expr: $e, queryType: "range", maxLines: 2000, direction: "forward"}], from: $de, to: $a}')
    printf 'user = "auditeur:%s"\n' "$(cat "$S/grafana-auditeur.password")" \
      | curl -sS -K - --cacert "$P/ca-poc.crt" -X POST -H 'Content-Type: application/json' "https://192.168.161.13:3001/api/ds/query" -d "$q" \
      | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
st = d.get("results", {}).get("A", {}).get("status")
fr = d.get("results", {}).get("A", {}).get("frames", []) or []
ts = sorted(v for f in fr for v in (f.get("data", {}).get("values", [[], []])[1] or []))
import datetime
h = lambda v: datetime.datetime.fromtimestamp(v / 1000, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
print(f"  {sys.argv[1]} : statut {st}, {len(ts)} ligne(s)" + (f", première {h(ts[0])}, dernière {h(ts[-1])}" if ts else ""))
' "$(printf '%s' "$e" | sed 's/.*|= //')"
  done
  echo "## fin, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} 2>&1 | sed -u "s#$HOME#~#g" | sed -u "$MASQUE" | tee "$LOG"
exit "${PIPESTATUS[0]}"
