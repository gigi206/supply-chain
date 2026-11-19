#!/usr/bin/env bash
# Brique 09 : troisième complément au relevé amont, en lecture publique, écrit après relecture du conseiller (19/11/2026).
# 1. Tableau de fin de vie de GnuPG imprimé depuis gnupg-download.html du premier passage (relu, non retéléchargé) : la valeur
#    de fin de vie de 2.4 n'était pas journalisée en clair (fragments seulement dans releve-amont.log).
# 2. Comment apt 3.0.3 choisit sqv ou gpgv : fichiers de construction et de paquet lus au tag, sans téléchargement sur disque.
# Journal : resultats/releve-complements-3.log.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
P1=$HOME/.cache/supply-chain-poc/09/releve-20261119T144438Z
cd "$HOME/.cache/supply-chain-poc/09"
APT=https://salsa.debian.org/apt-team/apt/-/raw/3.0.3
{
  set +e
  echo "troisième complément commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; python3 $(python3 -I -c 'import sys; print(sys.version.split()[0])') (hors dépôt)"
  echo; echo "## 1. Tableau « End-of-life » de https://gnupg.org/download/index.html (fichier $P1/gnupg-download.html, sha256 $(sha256sum "$P1/gnupg-download.html" | cut -c1-64))"
  python3 -I - "$P1/gnupg-download.html" <<'PY'
import re, sys, html
t = html.unescape(open(sys.argv[1], encoding="utf-8", errors="replace").read())
i = t.find("End-of-life")
for row in re.findall(r"<tr>(.*?)</tr>", t[i:i + 4000], re.S):
    print("  " + " | ".join(re.sub(r"<[^>]+>|\s+", " ", c).strip() for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)))
vers = re.findall(r"<tr>\s*<td[^>]*>[^<]*</td>\s*<td[^>]*>([0-9.,\s]+)</td>", t[i:i + 4000])
print("  ligne 2.3 présente dans le tableau :", any(v.strip().startswith("2.3") for v in vers))
for n in re.findall(r"<p[^>]*>\s*\(?[0-9¹²³]\)?[^<]{0,200}</p>|[¹²³]\s*[^<]{5,160}", t[i:i + 8000])[:6]:
    print("  note : " + re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", n)).strip()[:200])
PY
  echo; echo "## 2. apt 3.0.3 : construction et installation des méthodes sqv et gpgv"
  echo "### methods/CMakeLists.txt (lignes 1 à 40)"
  curl -fsSL --max-time 30 "$APT/methods/CMakeLists.txt" | sed -n '1,40p' | sed 's/^/    /'
  for f in debian/apt.install debian/apt.links debian/rules CMakeLists.txt; do
    echo "### $f : lignes citant sqv ou gpgv"
    curl -fsSL --max-time 30 "$APT/$f" | grep -n -iE 'sqv|gpgv' | head -15 | sed 's/^/    /'
  done
  echo "### apt-pkg/acquire-item.cc : lignes citant le nom de méthode gpgv"
  curl -fsSL --max-time 30 "$APT/apt-pkg/acquire-item.cc" | grep -n -E '"gpgv"|gpgv:|Dir::Bin::Methods' | head -10 | sed 's/^/    /'
  echo "troisième complément fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g' | tee "$R/releve-complements-3.log"
