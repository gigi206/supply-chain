#!/usr/bin/env bash
# Brique 09, O2 : second relevé, lecture publique, sans écriture sur disque hors du journal. Modes de mmdebstrap dans la page de
# manuel de trixie (mmdebstrap 1.5.7-1+deb13u1, version épinglée par la 06), pour l'option (a) côté Debian : la 06 a lancé
# mmdebstrap --mode=root en root dans un pod Kata, jamais dans un espace de noms utilisateur sur l'hôte.
# Journal : resultats/o2-releve-2.log.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd "$HOME/.cache/supply-chain-poc/09"
{
  echo "second relevé O2 commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "## page https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap.1.en.gz (servie en texte roff) : lignes sur les modes"
  curl -fsSL --max-time 60 https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap.1.en.gz \
    | python3 -I -c 'import re, sys
t = sys.stdin.read()
t = re.sub(r"\\f[BIRP]|\\&", "", t).replace("\\-", "-")
lignes = t.splitlines()
for i, l in enumerate(lignes):
    if re.search(r"--mode|^\.IP \"?(auto|sudo|root|unshare|fakeroot|fakechroot|chrootless)|user namespace|subuid|newuidmap|CAP_SYS_ADMIN", l):
        print("  " + l.strip()[:200])' | head -60
  echo "second relevé O2 fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g' | tee "$here/resultats/o2-releve-2.log"
