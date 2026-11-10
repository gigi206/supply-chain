#!/usr/bin/env bash
# Brique 07a : quelles données de la base Grype servent à juger un rpm de Rocky, d'AlmaLinux
# ou un deb de Debian 13 ? Essai sur l'hôte seul, hors réseau (unshare -rn), avec Grype 0.104.1
# de mise et la base du 04/11/2026 déjà importée en G0. Aucun téléchargement, rien écrit hors
# de ~/.cache/supply-chain-poc/07a/rpmdeb. Entrées : des PURL synthétiques (qualificatif distro=),
# pas de vrais paquets ; versions choisies dans la base (openssl, CVE-2026-9076 et voisines).
# Lancement : mise exec -- ./rpm-deb-hors-ligne.sh ; journal : resultats/rpm-deb-hors-ligne.log
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
G0="$HOME/.cache/supply-chain-poc/07a/g0"
W="$HOME/.cache/supply-chain-poc/07a/rpmdeb"
LOG="$here/resultats/rpm-deb-hors-ligne.log"
offline() { unshare -rn env GRYPE_DB_CACHE_DIR="$G0/dbcache" GRYPE_DB_AUTO_UPDATE=false GRYPE_DB_VALIDATE_AGE=false \
  GRYPE_CHECK_FOR_APP_UPDATE=false "$@"; }

rm -rf "$W"; mkdir -p "$W"
CAS=(
  "rocky-vieux|pkg:rpm/rocky/openssl@3.5.5-3.el9?arch=x86_64&epoch=1&distro=rocky-9.7"
  "rocky-corrige|pkg:rpm/rocky/openssl@3.5.8-2.el9_8?arch=x86_64&epoch=1&distro=rocky-9.7"
  "alma-vieux|pkg:rpm/almalinux/openssl@3.5.5-3.el9?arch=x86_64&epoch=1&distro=almalinux-9.7"
  "debian-vieux|pkg:deb/debian/openssl@3.5.6-1~deb13u1?arch=amd64&distro=debian-13"
  "rocky-sans-distro|pkg:rpm/rocky/openssl@3.5.5-3.el9?arch=x86_64&epoch=1"
)
{
  echo "# rpm-deb-hors-ligne.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "## grype $(grype version 2>/dev/null | sed -n 's/^Version: *//p'), base $(offline grype db status 2>/dev/null | grep -E 'Built' | tr -s ' ')"
  for c in "${CAS[@]}"; do
    nom=${c%%|*}; purl=${c#*|}
    printf '%s\n' "$purl" > "$W/$nom.purl"
    echo "## $nom : $purl"
    if offline grype "purl:$W/$nom.purl" -o json --file "$W/$nom.json" -q 2> "$W/$nom.err"; then
      python3 -I - "$W/$nom.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = d.get('matches', [])
print(f'correspondances : {len(m)} ; distro vue par grype : {json.dumps(d.get("distro"))}')
lignes = set()
for x in m:
    v = x['vulnerability']
    for md in x.get('matchDetails', []):
        sb = md.get('searchedBy') or {}
        lignes.add((v['id'], v.get('namespace'), md.get('type'), json.dumps(sb.get('distro')), sb.get('namespace')))
for l in sorted(lignes)[:12]:
    print('  ', ' | '.join(str(i) for i in l))
if len(lignes) > 12: print(f'   … {len(lignes) - 12} autres')
print('CVE-2026-9076 :', 'présente' if any(x['vulnerability']['id'] == 'CVE-2026-9076' or any(r.get('id') == 'CVE-2026-9076' for r in x.get('relatedVulnerabilities', [])) for x in m) else 'absente')
PY
    else
      echo "code non nul ; erreur :"; sed -n '1,5p' "$W/$nom.err"
    fi
  done
} 2>&1 | tee "$LOG"
