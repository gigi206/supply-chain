#!/usr/bin/env bash
# Brique 05, M1b, banc de l'outillage : qui écrit etc/machine-id ? (18/11/2026)
#   1. Paquet(s) parmi les 199 rpm du miroir partiel dont la liste de fichiers cite /etc/machine-id : drapeaux, mode, taille.
#   2. Scriptlets et triggers des 199 rpm qui citent machine-id ou systemd-machine-id-setup (lignes seules, paquet et section).
#   3. etc/machine-id de i5, i6, i7 : taille et mtime (stat seul ; contenu non imprimé).
# Lecture seule. Les requêtes portent sur les fichiers rpm (rpm -qp), jamais sur la base des arbres i5, i6, i7, qui seront
# ré-archivés ensuite. Hors ligne (unshare -n) ; rien n'est installé.
# Usage (racine du dépôt) : bash poc/bricks/05-rpm-mock/resultats/m1b-machine-id.sh > poc/bricks/05-rpm-mock/resultats/m1b-machine-id.log 2>&1
set -euo pipefail
export LC_ALL=C
D=$HOME/.cache/supply-chain-poc/05/m1b-outil-20261118T205714Z
ns() { unshare --map-auto --map-root-user -n "$@"; }
q() { ns -m -p --fork bash -c 'mount --rbind /dev "$1/dev" && mount -t proc proc "$1/proc" || exit 97; export HOME=/root; exec chroot "$@"' _ "$D/outils" "$@"; }
masque() { sed -E 's/<[^>]*@[^>]*>/<adresse retirée>/g; /jeton|token/I c\[ligne masquée : motif jeton|token]'; }
echo "# m1b-machine-id.sh, début $(date -u +%FT%TZ)"
[ -d "$D/outils/m/i5" ] && [ -d "$D/outils/m/rpms" ] || { echo "KO   banc absent : $D" >&2; exit 1; }
echo "rpm dans le miroir partiel : $(ls "$D/outils/m/rpms" | grep -c '\.rpm$')"
echo "## 1. paquets dont la liste cite /etc/machine-id"
q bash -c 'for f in /m/rpms/*.rpm; do rpm -qp --qf "[%{FILENAMES} %{FILEFLAGS:fflags} %{FILEMODES:perms} %{FILESIZES}\n]" "$f" 2>/dev/null \
  | grep "^/etc/machine-id " | sed "s|^|$(rpm -qp --qf "%{NEVRA}" "$f" 2>/dev/null) : |"; done' | masque | sed 's/^/     /'
echo "## 2. scriptlets et triggers qui citent machine-id"
q rpm -qp --qf '@@ %{NEVRA}\n' --scripts --triggers --filetriggers /m/rpms/*.rpm 2>/dev/null | masque | awk '
  /^@@ / { p = $2; next }
  /scriptlet|trigger/ && /:$/ { s = $0; next }
  tolower($0) ~ /machine-id/ { n++; printf "     %s | %s | %s\n", p, s, $0 }
  END { print "lignes citant machine-id : " n + 0 }'
echo "## 3. etc/machine-id des arbres (stat seul)"
for i in 5 6 7; do echo "i$i : $(ns stat -c '%s octet(s), mode %a, mtime %Y' "$D/outils/m/i$i/etc/machine-id")"; done
echo "# fin $(date -u +%FT%TZ)"
