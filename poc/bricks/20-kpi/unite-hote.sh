#!/usr/bin/env bash
# Brique 20, étape 4 : kpi.service à sec, sur l'hôte, sans sudo ni ssh ; rien n'est posé. Zot en lecture anonyme.
#   1. directives comparées à entrees-scan.service (modèle, en service), systemd-analyze verify et security hors ligne ;
#   2. exportateur lancé dans une unité transitoire du gestionnaire utilisateur (systemd-run --user), durcissement lu dans kpi.service, avec
#      /usr/bin/python3 puis Python 3.13 (mise) : même sortie que sans durcissement ;
#   3. sondes : ce que le durcissement doit refuser l'est vraiment (sinon le point 2 ne prouverait rien).
# Retirés de l'unité transitoire : User, Group (gestionnaire utilisateur) ; IPAddressDeny et IPAddressAllow (BPF, root). Chemins : le dossier
# de travail est monté sur /srv (ProtectHome masque le dossier personnel), Python 3.13 sur /mnt. Le noyau, systemd et Python de l'hôte ne
# sont pas ceux de sc-stockage.
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/20-kpi/unite-hote.sh   (journal : resultats/e4-unite-hote<SUFFIXE>.log)
set -uo pipefail
export LC_ALL=C.UTF-8
centiemes() { tr -d . < /proc/uptime | cut -d" " -f1; }   # horloge monotone ; le date de l'hôte (uutils) rend %3N sans zéro de tête
here=$(cd "$(dirname "$0")" && pwd)
LOG=$here/resultats/e4-unite-hote${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
T=$HOME/.cache/supply-chain-poc/20/unite-hote   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/unite-hote ] || find ~/.cache/supply-chain-poc/20/unite-hote -delete
trap 'find ~/.cache/supply-chain-poc/20/unite-hote -delete 2> /dev/null' EXIT
mkdir -p "$T/cles"
B=$here/.. U=$here/systemd/kpi.service M=$here/../07a-sbom-grype/systemd/entrees-scan.service
X=$here/../../../tools/metrics-exporter/metrics_exporter.py
P=$(python3 -c 'import sys; print(sys.base_prefix)')
cp "$X" "$T/metrics_exporter.py"; cp "$here/releve/dates-git.tsv" "$T/"; cp ~/.cache/supply-chain-poc/08/pki/ca-poc.crt "$T/ca.crt"
cp "$B/08-trust-plane/resultats/chains-cle-publique.pem" "$T/cles/chains.pub"
cp "$B/07a-sbom-grype/resultats/scanner-cle-publique.pem" "$T/cles/scanner.pub"
cp "$B/07a-sbom-grype/resultats/vex-cle-publique.pem" "$T/cles/vex.pub"
cp "$B/10-independent-replay/resultats/vsa-cle-publique.pem" "$T/cles/vsa.pub"
cp "$B/08-trust-plane/resultats/tsa-chaine.pem" "$T/cles/tsa.pem"
python3 -I -c 'import runpy, sys; sys.stdout.buffer.write(runpy.run_path(sys.argv[1])["VECTEUR_PUB"])' "$X" > "$T/cles/vecteur.pub"
for f in libre durci py313; do : > "$T/$f.prom"; done
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
durcissement() { sed -n '/^\[Service\]/,$p' "$1" | grep -E '^[A-Z][A-Za-z]+=' | grep -vE '^(Type|User|Group|Environment|ExecStart|TimeoutStartSec|StateDirectory|StateDirectoryMode|ReadWritePaths|SupplementaryGroups|LoadCredential|UMask)='; }
export REG=192.168.161.13:5000 PRODUITS="sample-app sample-app-deb sample-app-rpm" SIGNATURES=verifiees
unite() { # fichier de sortie (nom) ou -, commande : unité transitoire durcie
  local o=$1 p=(); shift
  while read -r d; do p+=(-p "$d"); done < <(durcissement "$U" | grep -vE '^IPAddress')
  [ "$o" = - ] || p+=(-p "ReadWritePaths=/srv/$o.prom")
  systemd-run --user --wait --pipe --collect -q "${p[@]}" -p "BindPaths=$T:/srv" -p "ReadOnlyPaths=/srv" -p "BindReadOnlyPaths=$P:/mnt" \
    -E REG="$REG" -E PRODUITS="$PRODUITS" -E SIGNATURES=verifiees -E CA=/srv/ca.crt -E CLES=/srv/cles -E RELEVE=/srv/dates-git.tsv \
    -E SORTIE="/srv/$o.prom" "$@" 2>&1
}
{
echo "# unite-hote.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), exportateur $(sha256sum < "$X" | cut -c1-16), $(systemctl --version | head -1 | cut -d' ' -f1,2)"
echo "## 1. unité"
attendu "durcissement : lignes différentes de entrees-scan.service" "$(diff <(durcissement "$M" | sort) <(durcissement "$U" | sort) | grep -c '^[<>]')" 0
J=$here/systemd/kpi-journal.service
attendu "durcissement du lecteur : lignes différentes de entrees-scan.service" "$(diff <(durcissement "$M" | sort) <(durcissement "$J" | sort) | grep -c '^[<>]')" 0
# copie rendue : l'exécutable n'est pas posé sur l'hôte, verify le signalerait
sed 's#^ExecStart=.*#ExecStart=/usr/bin/true#' "$U" > "$T/kpi.service"; cp "$here/systemd/kpi.timer" "$T/"
sed 's#^ExecStart=.*#ExecStart=/usr/bin/true#' "$J" > "$T/kpi-journal.service"
attendu "systemd-analyze verify, lignes sur kpi" "$(systemd-analyze verify "$T/kpi.service" "$T/kpi-journal.service" "$T/kpi.timer" 2>&1 | grep -cE 'kpi(-journal)?\.(service|timer)')" 0
note() { systemd-analyze security --offline=true --no-pager "$1" 2> /dev/null | sed -nE 's/.*Overall exposure level for [^:]+: ([0-9.]+) .*/\1/p'; }
# SupplementaryGroups (kpi lit le journal, groupe kpi-journal) coûte 0,1 à kpi.service ; le lecteur garde la note du modèle
attendu "systemd-analyze security, notes hors ligne : modèle, kpi, kpi-journal" "$(note "$M") $(note "$U") $(note "$J")" "2.9 3.0 2.9"
echo "## 2. exportateur sans durcissement, puis durci"
CA=$T/ca.crt CLES=$T/cles RELEVE=$T/dates-git.tsv SORTIE=$T/libre.prom /usr/bin/python3 -I "$T/metrics_exporter.py"; rc=$?
attendu "sans durcissement : code" "$rc" 0
t0=$(centiemes)
unite durci /usr/bin/python3 -I /srv/metrics_exporter.py; rc=$?
echo "durée : $(( ($(centiemes) - t0) * 10 )) ms"
attendu "durci, $(/usr/bin/python3 --version) : code" "$rc" 0
unite py313 /usr/bin/env /mnt/bin/python3 -I /srv/metrics_exporter.py; rc=$?
attendu "durci, $(python3 --version) : code" "$rc" 0
for f in durci py313; do
  attendu "$f : séries différentes de la sortie sans durcissement" "$(diff <(grep -v '^kpi_exportateur_' "$T/libre.prom") <(grep -v '^kpi_exportateur_' "$T/$f.prom") | grep -c '^[<>]')" 0
  attendu "$f : séries" "$(wc -l < "$T/$f.prom")" "$(wc -l < "$T/libre.prom")"
done
attendu "signatures vérifiées et refusées, durci" "$(awk '/^kpi_signatures_verifiees/{v += $2} /^kpi_signatures_refusees/{r += $2} END {print v, r}' "$T/durci.prom")" "41 0"
# ProtectHome=true masque aussi /run/user, où le gestionnaire utilisateur met les identifiants ; un service système les a dans
# /run/credentials (base-grype.service, en service, a LoadCredential et ProtectHome=true). Retiré ici seulement, donc non exercé.
echo "## 2 bis. lecteur durci (sans ProtectHome), mot de passe de l'auditeur remis par LoadCredential (chemin seul en argument), vrai Grafana"
: > "$T/lignes"; cp "$here/../../../tools/metrics-exporter/lecteur_loki.py" "$T/"
p=(); while read -r d; do p+=(-p "$d"); done < <(durcissement "$J" | grep -vE '^IPAddress')
systemd-run --user --wait --pipe --collect -q "${p[@]}" -p ProtectHome=false -p UMask=0027 -p "BindPaths=$T:/srv" -p ReadOnlyPaths=/srv -p ReadWritePaths=/srv/lignes \
  -p "LoadCredential=mdp:$HOME/.cache/supply-chain-poc/08/secrets/grafana-auditeur.password" -E GRAFANA=https://192.168.161.13:3001 -E CA=/srv/ca.crt \
  -E UTILISATEUR=auditeur -E SORTIE=/srv/lignes /bin/sh -c 'MDP=$CREDENTIALS_DIRECTORY/mdp exec /usr/bin/python3 -I /srv/lecteur_loki.py' 2>&1; rc=$?
attendu "lecteur durci : code" "$rc" 0
attendu "lecteur durci : résumés lus" "$([ "$(grep -c 'liste émise' "$T/lignes")" -gt 0 ] && echo oui || echo non)" oui
: > "$T/journal.prom"
unite journal /usr/bin/env JOURNAL=/srv/lignes /usr/bin/python3 -I /srv/metrics_exporter.py; rc=$?
attendu "exportateur durci avec ce journal : code, illisible" "$rc $(sed -n 's/^kpi_exportateur_journal_illisible //p' "$T/journal.prom")" "0 0"
echo "## 3. sondes : permises sans durcissement (témoin), refusées dans l'unité"
sonde() { # nom, expression Python ; SRV remplacé par le dossier de travail (témoin) ou par /srv (unité)
  local prog="import os, socket, mmap
try:
    $2
    print('permis')
except OSError:
    print('refusé')"
  attendu "témoin, $1" "$(/usr/bin/python3 -I -c "${prog//SRV/$T}" 2>&1)" permis
  attendu "unité, $1" "$(unite - /usr/bin/python3 -I -c "${prog//SRV//srv}")" refusé
}
sonde "écrire un autre fichier du dossier" "open('SRV/libre.prom', 'a')"
sonde "lister le dossier personnel" "os.listdir('$HOME')"
sonde "socket IPv6" "socket.socket(socket.AF_INET6)"
sonde "socket netlink" "socket.socket(socket.AF_NETLINK, socket.SOCK_RAW)"
sonde "nouvel espace de noms" "os.unshare(os.CLONE_NEWUSER)"
sonde "mémoire à la fois écrite et exécutable" "mmap.mmap(-1, 4096, prot=mmap.PROT_WRITE | mmap.PROT_EXEC)"
echo "## bilan : $N cas, $KO écart(s)"
[ "$KO" = 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
