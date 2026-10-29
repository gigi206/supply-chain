#!/usr/bin/env bash
# Banc A2 : builds de sample-app dans OBS (projet poc, dépôts rocky_9 et debian_13).
#   envoyer <libellé>      : sources de poc/packaging (packaging:sources) commitées dans poc/sample-app,
#                            attente des résultats, collecte ;
#   reconstruire <libellé> : « osc rebuild » sans changement de source, attente, collecte.
# Collecte par dépôt : binaires et fichiers annexes (_buildenv, _statistics, provenance SLSA)
# dans ~/.cache/supply-chain-poc/obs/builds/<libellé>/<dépôt>/ ; journal de build, liste des
# fichiers et sha256 dans resultats/<libellé>/<dépôt>/ (les binaires ne sont pas versionnés).
#
# Usage (racine du dépôt) : mise run obs:construire -- envoyer build-1
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
O=${OBS_DIR:-$HOME/.cache/supply-chain-poc/obs}
SRC=${PACKAGING_DIR:-$HOME/.cache/supply-chain-poc/packaging}
DEPOTS=(rocky_9 debian_13)
action=${1:?usage : $0 envoyer|reconstruire <libellé>}
lib=${2:?libellé manquant (build-1, build-2…)}
s() { "$here/ssh-obs.sh" "$@"; }
mkdir -p "$R/$lib"
exec > >(sed -u "s#$HOME#~#g" | tee "$R/$lib/construire.log") 2>&1
echo "# construire.sh $action $lib, $(date -u +%Y-%m-%dT%H:%M:%SZ)"

etat() { s "osc api '/build/poc/_result?package=sample-app'" | grep -o '<status package="sample-app" code="[a-z]*"' | sed 's/.*code="//; s/"$//' | paste -sd' '; }
attendre() {
  local e debut=$SECONDS
  sleep 20
  while :; do
    e=$(s "osc api '/build/poc/_result?package=sample-app'" | tr -d '\n' | grep -o '<result [^>]*repository="[a-z_0-9]*"[^>]*>\s*<status package="sample-app" code="[a-z]*"' \
          | sed -E 's/.*repository="([a-z_0-9]+)".*code="([a-z]+)"/\1=\2/' | sort | paste -sd' ')
    echo "$(date -u +%H:%M:%S) $e"
    [[ $e =~ ^(debian_13|rocky_9)=(succeeded|failed|unresolvable|broken|disabled|excluded)\ (debian_13|rocky_9)=(succeeded|failed|unresolvable|broken|disabled|excluded)$ ]] && break
    (( SECONDS - debut < 5400 )) || { echo "ÉCHEC : délai dépassé"; exit 1; }
    sleep 30
  done
}

case $action in
  envoyer)
    (cd "$SRC" && sha256sum -c --quiet SHA256SUMS)
    s 'set -e; rm -rf /root/banc-a2/sources && mkdir -p /root/banc-a2/sources'
    SSH_OBS_SCP=1 "$here/ssh-obs.sh" "$SRC"/sample-app-1.0.0.tar.gz "$SRC"/sample-app_1.0.0.orig.tar.gz \
      "$SRC"/sample-app_1.0.0-1.dsc "$SRC"/sample-app_1.0.0-1.debian.tar.xz "$SRC"/sample-app.spec \
      root@192.168.161.10:/root/banc-a2/sources/
    s 'set -e; cd /root/banc-a2
       osc meta pkg poc sample-app >/dev/null 2>&1 || printf "<package name=\"sample-app\" project=\"poc\"><title>sample-app</title><description/></package>\n" | osc meta pkg -F - poc sample-app
       rm -rf poc && osc -q co poc sample-app && cd poc/sample-app
       find . -maxdepth 1 -type f ! -name ".*" -delete
       cp /root/banc-a2/sources/* . && osc -q addremove && osc -q ci -m "sample-app 1.0.0 (poc/packaging)" || true
       osc ls -l poc sample-app | sed "s/^/  /"; echo "srcmd5 : $(osc api /source/poc/sample-app | grep -o "srcmd5=\"[0-9a-f]*\"")"'
    ;;
  reconstruire)
    echo "état avant : $(etat)"
    s 'osc rebuild poc sample-app'
    ;;
  *) echo "action inconnue : $action" >&2; exit 2 ;;
esac

echo "## Attente des résultats"
attendre
printf '%s. %s : %s\t%s\t\n' "$(( $(wc -l < "$R/chrono.tsv") ))" "$lib" "$(etat)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$R/chrono.tsv"

echo "## Collecte"
for d in "${DEPOTS[@]}"; do
  B=$O/builds/$lib/$d
  rm -rf "$B"; mkdir -p "$B" "$R/$lib/$d"
  s "osc remotebuildlog poc sample-app $d x86_64" > "$R/$lib/$d/build.log" 2>&1 || true
  s "rm -rf /root/banc-a2/bin/$d && mkdir -p /root/banc-a2/bin/$d && cd /root/banc-a2/bin/$d && osc getbinaries -q --sources poc sample-app $d x86_64 -d . && osc ls -b -l poc sample-app -r $d -a x86_64" \
    > "$R/$lib/$d/binaires.txt" 2>&1 || true
  for f in _buildenv _statistics _slsa_provenance.json; do
    s "osc api /build/poc/$d/x86_64/sample-app/$f" > "$B/$f" 2>/dev/null || rm -f "$B/$f"
  done
  SSH_OBS_SCP=1 "$here/ssh-obs.sh" -r "root@192.168.161.10:/root/banc-a2/bin/$d/." "$B/" 2>/dev/null || true
  (cd "$B" && find . -type f ! -name '_*' -printf '%P\n' | sort | xargs -r sha256sum) > "$R/$lib/$d/sha256.txt"
  for f in _buildenv _statistics _slsa_provenance.json; do [[ -s $B/$f ]] && cp "$B/$f" "$R/$lib/$d/"; done
  echo "$d : $(wc -l < "$R/$lib/$d/sha256.txt") fichiers ; type de VM : $(grep -m1 -o -E 'Doing (kvm|qemu|chroot|[a-z]+) build' "$R/$lib/$d/build.log" | paste -sd' ')"
  sed 's/^/  /' "$R/$lib/$d/sha256.txt"
done
