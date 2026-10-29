#!/usr/bin/env bash
# Banc A2 : tests du critère 1 (provenance non falsifiable), de B4 et de la signature.
#   hostile  : paquet poc/hostile (hostile/hostile.spec, rocky_9 seulement) : réseau, signd,
#              clé, fausses provenances déposées par le build ; on examine ce qu'OBS publie ;
#   dsse     : enveloppe DSSE de chaque provenance de <libellé> vérifiée hors d'OBS
#              (PAE DSSEv1, clé publique du projet poc), sujets comparés aux sha256 des fichiers ;
#   materiau : un binaire cité dans resolvedDependencies récupéré par son URI et son digest (B4).
#
# Usage (racine du dépôt) : mise run obs:tests -- hostile|dsse <libellé>|materiau <libellé>
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}
s() { "$here/ssh-obs.sh" "$@"; }
action=${1:?usage : $0 hostile|dsse <libellé>|materiau <libellé>}

hostile() {
  exec > >(sed -u "s#$HOME#~#g" | tee "$R/tests-hostile.log") 2>&1
  echo "# tests.sh hostile, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  SSH_OBS_SCP=1 "$here/ssh-obs.sh" "$here/hostile/hostile.spec" root@192.168.161.10:/root/banc-a2/
  s 'set -e; cd /root/banc-a2
     printf "<package name=\"hostile\" project=\"poc\"><title>hostile</title><description/><build><disable repository=\"debian_13\"/></build></package>\n" | osc meta pkg -F - poc hostile
     rm -rf poc/hostile && osc -q co poc hostile -o poc/hostile && cp hostile.spec poc/hostile/
     cd poc/hostile && osc -q addremove && osc -q ci -m "spec hostile" || true'
  local e
  for _ in $(seq 120); do
    sleep 30
    e=$(s "osc results -r rocky_9 -a x86_64 poc hostile" | awk '{print $NF}')
    echo "$(date -u +%H:%M:%S) rocky_9 : $e"
    [[ $e =~ ^(succeeded|failed|unresolvable|broken)$ ]] && break
  done
  echo "## Journal de build (lignes des tests)"
  s "osc remotebuildlog poc hostile rocky_9 x86_64" > "$R/tests-hostile-build.log" 2>&1 || true
  grep -E '^(\[ *[0-9.]+\] )?(== |T-|/proc|BOOT_IMAGE|[0-9]+$|lo$|eth0$)' "$R/tests-hostile-build.log" | sed 's/^\[ *[0-9.]*\] //' | head -40
  grep -m3 -E 'booting kvm|Linux version|kvm' "$R/tests-hostile-build.log" | sed 's/^/  /'
  echo "## Binaires publiés"
  s "osc ls -b -l poc hostile -r rocky_9 -a x86_64"
  echo "## Provenances publiées"
  for f in _slsa_provenance.json hostile-1-1.x86_64.slsa_provenance.json; do
    s "osc api /build/poc/rocky_9/x86_64/hostile/$f" > "$O/hostile-$f" 2>/dev/null || { echo "$f : absent"; continue; }
    printf '%s : ' "$f"
    jq -r 'if .payload then (.payload | @base64d | fromjson | "DSSE ; sujets : \([.subject[] | "\(.name)=\(.digest.sha256[0:16])…"] | join(", ")) ; builder : \(.predicate.builder.id // .predicate.runDetails.id) ; buildType : \(.predicate.buildType // .predicate.buildDefinition.buildType)") else "NON SIGNÉE : \(.)" end' "$O/hostile-$f"
  done
  s "cd /root/banc-a2 && rm -rf hostile-bin && osc getbinaries -q poc hostile rocky_9 x86_64 -d hostile-bin && sha256sum hostile-bin/*.rpm"
}

dsse() {
  local lib=${1:?libellé}
  exec > >(sed -u "s#$HOME#~#g" | tee "$R/$lib/dsse.log") 2>&1
  echo "# tests.sh dsse $lib, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local G; G=$(mktemp -d); trap 'rm -rf -- "$G"' RETURN
  s 'osc signkey poc' > "$G/poc.asc"
  echo "clé du projet poc : $(gpg --show-keys --with-colons "$G/poc.asc" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')"
  GNUPGHOME=$G gpg --batch -q --import "$G/poc.asc" 2>/dev/null
  for d in rocky_9 debian_13; do
    B=$O/builds/$lib/$d
    for p in "$B"/_slsa_provenance.json "$B"/*.slsa_provenance.json; do
      [[ -s $p ]] || continue
      python3 -I - "$p" "$G" <<'PY'
import base64, json, sys
env = json.load(open(sys.argv[1]))
t, body = env["payloadType"], base64.b64decode(env["payload"])
pae = b"DSSEv1 %d %s %d %s" % (len(t), t.encode(), len(body), body)
open(sys.argv[2] + "/pae", "wb").write(pae)
open(sys.argv[2] + "/sig", "wb").write(base64.b64decode(env["signatures"][0]["sig"]))
open(sys.argv[2] + "/stmt.json", "wb").write(body)
PY
      if GNUPGHOME=$G gpg --batch --status-fd 1 --verify "$G/sig" "$G/pae" 2>/dev/null | grep -q '^\[GNUPG:\] VALIDSIG'; then v="signature DSSE valide"; else v="SIGNATURE DSSE INVALIDE"; fi
      echo "$d/$(basename "$p") : $v ; $(jq -r '"\(.predicateType) ; builder \(.predicate.builder.id // .predicate.runDetails.id) ; \((.predicate.materials // .predicate.buildDefinition.resolvedDependencies) | length) matériaux"' "$G/stmt.json")"
      jq -r '.subject[] | "\(.name) \(.digest.sha256)"' "$G/stmt.json" | while read -r n h; do
        if [[ -f $B/$n ]]; then
          [[ $(sha256sum < "$B/$n" | cut -d' ' -f1) == "$h" ]] && echo "  sujet $n : sha256 conforme" || echo "  sujet $n : SHA256 DIFFÉRENT"
        else
          echo "  sujet $n : fichier absent de la collecte"
        fi
      done
      cp "$G/stmt.json" "$R/$lib/$d/$(basename "$p" .json).statement.json"
    done
  done
}

materiau() {
  local lib=${1:?libellé}
  exec > >(sed -u "s#$HOME#~#g" | tee "$R/$lib/materiau.log") 2>&1
  echo "# tests.sh materiau $lib, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for d in rocky_9 debian_13; do
    st=$(ls "$R/$lib/$d"/*.statement.json 2>/dev/null | head -1) || true
    [[ -n $st ]] || { echo "$d : pas de provenance"; continue; }
    # URI du srcserver (port interne 5352), interrogée depuis l'appliance ; un binaire par dépôt d'origine
    jq -r '(.predicate.materials // .predicate.buildDefinition.resolvedDependencies)[] | select(.uri | test("/_?slsa/")) | "\(.uri) \(.digest.sha256)"' "$st" \
      | awk '{split($1, a, "/"); k = a[5] "/" a[6]; if (!(k in vu)) {vu[k] = 1; print}}' | while read -r u h; do
      got=$(s "curl -fsS '$u' | sha256sum" < /dev/null | cut -d' ' -f1)
      echo "$d : $u"
      [[ $got == "$h" ]] && echo "  récupéré par digest, sha256 conforme" || echo "  ÉCHEC : sha256 $got"
    done
  done
}

case $action in
  hostile) hostile ;;
  dsse) dsse "${2:-}" ;;
  materiau) materiau "${2:-}" ;;
  *) echo "action inconnue : $action" >&2; exit 2 ;;
esac
