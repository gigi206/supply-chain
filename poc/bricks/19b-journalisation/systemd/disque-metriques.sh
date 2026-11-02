#!/bin/sh
# Brique 19b, L2 (D13 a) : occupation des systèmes de fichiers de sc-stockage, servie par fichiers-metriques (brique 19).
# Écriture atomique : fichier temporaire du même répertoire, puis renommage.
set -eu
f=/etc/fichiers-metriques/disque.prom
t=$(mktemp /etc/fichiers-metriques/.disque.XXXXXX)
{
  echo '# HELP disque_utilise_ratio Part utilisée du système de fichiers (df), entre 0 et 1.'
  echo '# TYPE disque_utilise_ratio gauge'
  df -P -B1 / /var/lib | awk 'NR > 1 && !vu[$6]++ { printf "disque_utilise_ratio{point=\"%s\"} %.4f\n", $6, $3 / $2 }'
} > "$t"
chmod 0644 "$t"
mv "$t" "$f"
