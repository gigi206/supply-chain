#!/usr/bin/env bash
# Brique 20, étape 4 : pose de l'exportateur des KPI et de son lecteur sur sc-stockage. Posé le 24/11/2026.
# Étapes :
#   sec      hôte seulement, sans ssh : relevé des dates à jour, fichiers à poser présents, empreintes. Sans accord.
#   compte   ACCORD DU PROPRIÉTAIRE : mot de passe généré sur l'hôte (0600, s'il est absent), compte Grafana kpi-journal (Viewer) créé par
#            l'administrateur ; le rôle est relu.
#   pose     ACCORD DU PROPRIÉTAIRE (sudo sur sc-stockage) : refus si le relevé est périmé ou si le proxy de Grafana mène encore à Loki
#            (défaut de la 19b, constat du 24/11) ; comptes système kpi et kpi-journal, fichiers, unités, un premier passage, contrôles.
#   verif    lecture seule, par l'auditeur dans Grafana : séries dans Prometheus.
#   pose_rejeu  seulement depuis rejeu.sh (REJEU=<libellé>, décision du 24/11/2026 « Pose au rejeu, sans dates (Recommandé) ») : relevé des dates
#            recalculé et écrit dans l'arbre, puis pose. Le rejeu réécrit des clés publiques sans les commiter : leur date est celle d'un commit
#            à venir, donc exactement autant de clés sans date que de clés différentes de HEAD, et aucun pin sans ligne. Après relecture et
#            commit des clés : « releve-dates.py ecrire », commit, puis « pose ». PAS ENCORE REJOUÉ.
#   sec_rejeu   hôte seulement, sans ssh : les mêmes contrôles, et un passage de l'exportateur sur l'hôte (Zot en anonyme, journal vide).
#   retrait  ACCORD DU PROPRIÉTAIRE (sudo) : unités, fichiers et comptes système retirés ; le compte Grafana est retiré à part (compte_retrait).
# Usage (racine du dépôt) : mise exec -- bash poc/bricks/20-kpi/kpi-pose.sh <étape> > <journal>
set -uo pipefail
export LC_ALL=C.UTF-8
here=$(cd "$(dirname "$0")" && pwd)
RACINE=$(cd "$here/../../.." && pwd)
O8=$HOME/.cache/supply-chain-poc/08
CA=$O8/pki/ca-poc.crt GRAF=https://192.168.161.13:3001
MDP=$HOME/.cache/supply-chain-poc/20/secrets/grafana-kpi-journal.password
SSH_OPTS=(-i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
sur() { env -u SSH_AUTH_SOCK ssh "${SSH_OPTS[@]}" poc@192.168.161.13 "$@"; }
ko=0
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }
masque() { sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]'; }
T=$HOME/.cache/supply-chain-poc/20/kpi-pose   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/20/kpi-pose ] || find ~/.cache/supply-chain-poc/20/kpi-pose -delete
(umask 077; mkdir -p "$T/pose/cles")
trap 'find ~/.cache/supply-chain-poc/20/kpi-pose -delete' EXIT
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ), étape ${1:-?}, dépôt $(git -C "$here" rev-parse --short=8 HEAD)"

graf() { # compte méthode chemin [fichier du corps] : code HTTP, réponse dans $T/r.json ; mot de passe par l'entrée de configuration
  local d=() f="$O8/secrets/grafana-$1.password"; [ "$1" != kpi-journal ] || f=$MDP
  [ -z "${4:-}" ] || d=(-d "@$4")
  printf 'user = "%s:%s"\n' "$1" "$(cat "$f")" | curl -sS -K - --cacert "$CA" -o "$T/r.json" -w '%{http_code}' -X "$2" -H 'Content-Type: application/json' "${d[@]}" "$GRAF$3"
}
preparer() { # fichiers à poser, rassemblés dans $T/pose
  local x=$RACINE/tools/metrics-exporter b=$here/..
  cp "$x/metrics_exporter.py" "$x/lecteur_loki.py" "$here/systemd/kpi.service" "$here/systemd/kpi.timer" "$here/systemd/kpi-journal.service" \
    "$here/releve/dates-git.tsv" "$T/pose/" || return 1
  cp "$b/08-trust-plane/resultats/chains-cle-publique.pem" "$T/pose/cles/chains.pub" || return 1
  cp "$b/07a-sbom-grype/resultats/scanner-cle-publique.pem" "$T/pose/cles/scanner.pub" || return 1
  cp "$b/07a-sbom-grype/resultats/vex-cle-publique.pem" "$T/pose/cles/vex.pub" || return 1
  cp "$b/10-independent-replay/resultats/vsa-cle-publique.pem" "$T/pose/cles/vsa.pub" || return 1
  cp "$b/08-trust-plane/resultats/tsa-chaine.pem" "$T/pose/cles/tsa.pem" || return 1
  python3 -I -c 'import runpy, sys; sys.stdout.buffer.write(runpy.run_path(sys.argv[1])["VECTEUR_PUB"])' "$x/metrics_exporter.py" > "$T/pose/cles/vecteur.pub"
}
cles_changees() { # nombre de clés publiques de l'arbre qui ne sont pas celles de HEAD
  local n=0 f c
  for f in 08-trust-plane/resultats/chains-cle-publique.pem 07a-sbom-grype/resultats/scanner-cle-publique.pem 07a-sbom-grype/resultats/vex-cle-publique.pem \
    10-independent-replay/resultats/vsa-cle-publique.pem 08-trust-plane/resultats/tsa-chaine.pem; do
    git -C "$RACINE" diff --quiet HEAD -- "poc/bricks/$f"; c=$?
    [ "$c" -le 1 ] || return 1
    n=$((n + c))
  done
  echo "$n"
}
controle_prom() { # $T/kpi.prom : signatures, dates manquantes
  attendu "signatures refusées" "$(awk '/^kpi_signatures_refusees/{s += $2; n++} END {print s + 0, (n > 0) ? "présentes" : "absentes"}' "$T/kpi.prom")" "0 présentes"
  attendu "signatures vérifiées" "$(awk '/^kpi_signatures_verifiees/{s += $2} END {print (s > 0) ? "oui" : "non"}' "$T/kpi.prom")" oui
  attendu "clés sans date" "$(awk '$1 == "kpi_cles_non_relevees" {print $2}' "$T/kpi.prom")" "${SANS_DATE:-0}"
  attendu "pins sans date, journal illisible" "$(awk '/^kpi_(pins_non_releves|exportateur_journal_illisible)/{s += $2; n++} END {print s + 0, (n > 1) ? "présentes" : "absentes"}' "$T/kpi.prom")" "0 présentes"
}
au_rejeu() { # SANS_DATE et relevé, pour les étapes du rejeu
  SANS_DATE=$(cles_changees) || { echo "KO   git diff des clés publiques"; return 1; }
  echo "clés publiques réécrites, pas encore commitées : $SANS_DATE"
  python3 -I "$here/releve-dates.py" ecrire || return 1
}
controles_hote() {
  # le relevé lit les clés dans HEAD, preparer les copie depuis l'arbre : une clé changée sans commit est refusée ici, sauf au rejeu
  [ -n "${SANS_DATE:-}" ] || attendu "clés publiques de l'arbre différentes de HEAD" "$(cles_changees)" 0
  attendu "relevé des dates de git" "$(python3 -I "$here/releve-dates.py" verifier > /dev/null 2>&1 && echo "à jour" || echo périmé)" "à jour"
  preparer; attendu "fichiers à poser" "$(find "$T/pose" -type f | wc -l)" 12
  attendu "aucune clé privée parmi eux" "$(grep -rl 'PRIVATE KEY' "$T/pose" | wc -l)" 0
}

etape_sec() {
  controles_hote
  (cd "$T/pose" && find . -type f | sort | xargs sha256sum | cut -c1-16,65-)
  echo "mot de passe de kpi-journal : $([ -s "$MDP" ] && echo présent || echo absent)"
  return $ko
}

etape_compte() { # ACCORD DU PROPRIÉTAIRE
  local c
  if [ ! -s "$MDP" ]; then
    (umask 077; mkdir -p ~/.cache/supply-chain-poc/20/secrets; openssl rand -hex 24 | tr -d '\n' > "$MDP") || return 1
  fi
  attendu "mot de passe, droits" "$(stat -c %a "$MDP")" 600
  c=$(graf admin GET "/api/users/lookup?loginOrEmail=kpi-journal")
  if [ "$c" = 200 ]; then echo "compte kpi-journal existant"; else
    (umask 077; jq -n --rawfile p "$MDP" '{name: "kpi-journal", login: "kpi-journal", email: "kpi-journal@poc.test", password: $p, OrgId: 1}' > "$T/compte.json")
    attendu "création du compte" "$(graf admin POST /api/admin/users "$T/compte.json")" 200
    find ~/.cache/supply-chain-poc/20/kpi-pose/compte.json -delete
  fi
  attendu "liste des comptes" "$(graf admin GET /api/orgs/1/users)" 200
  attendu "rôle de kpi-journal" "$(jq -r '.[] | select(.login == "kpi-journal") | .role' "$T/r.json")" Viewer
  attendu "connexion de kpi-journal" "$(graf kpi-journal GET /api/user) $(jq -r .login "$T/r.json")" "200 kpi-journal"
  return $ko
}

etape_compte_retrait() { # ACCORD DU PROPRIÉTAIRE
  attendu "compte trouvé" "$(graf admin GET "/api/users/lookup?loginOrEmail=kpi-journal")" 200
  local i; i=$(jq -r .id "$T/r.json")
  attendu "compte retiré" "$(graf admin DELETE "/api/admin/users/$i")" 200
  return $ko
}

etape_pose() { # ACCORD DU PROPRIÉTAIRE
  controles_hote
  attendu "mot de passe de kpi-journal" "$([ -s "$MDP" ] && echo présent || echo absent)" présent
  # le proxy doit refuser Loki (liste posée, défaut de la 19b) : chemin de lecture sans effet, jamais un chemin qui agit
  attendu "proxy de Grafana vers Loki, auditeur, GET /loki/api/v1/status/buildinfo" "$(graf auditeur GET /api/datasources/proxy/uid/loki/loki/api/v1/status/buildinfo)" 403
  [ "$ko" = 0 ] || return 1
  (umask 077; cp "$MDP" "$T/pose/grafana.password")
  sur "if [ -e /tmp/kpi-installation ]; then find /tmp/kpi-installation -delete; fi; mkdir -m 0700 /tmp/kpi-installation" || return 1
  # le mot de passe ne doit rester dans /tmp sur aucun échec : le script sudo efface le dossier, l'hôte l'efface s'il n'a pas pu
  nettoyer() { sur "if [ -e /tmp/kpi-installation ]; then find /tmp/kpi-installation -delete; fi"; }
  env -u SSH_AUTH_SOCK scp -qr "${SSH_OPTS[@]}" "$T/pose/." poc@192.168.161.13:/tmp/kpi-installation/ < /dev/null || { nettoyer; return 1; }
  sur "sudo bash -s" <<'EOS'
set -euo pipefail
trap 'if [ -e /tmp/kpi-installation ]; then find /tmp/kpi-installation -delete; fi' EXIT
cd /tmp/kpi-installation
for u in kpi kpi-journal; do
  id "$u" > /dev/null 2>&1 || useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$u"
done
install -d -m 0755 /usr/local/lib/kpi /etc/kpi /etc/kpi/cles
install -m 0755 metrics_exporter.py lecteur_loki.py /usr/local/lib/kpi/
install -m 0644 cles/* /etc/kpi/cles/
install -m 0644 dates-git.tsv /etc/kpi/
install -d -m 0700 /etc/kpi-journal
install -m 0600 grafana.password /etc/kpi-journal/
install -d -m 0750 -o kpi-journal -g kpi-journal /var/lib/kpi-journal
[ -e /var/lib/kpi-journal/lignes ] || install -m 0640 -o kpi-journal -g kpi-journal /dev/null /var/lib/kpi-journal/lignes
[ -e /etc/fichiers-metriques/kpi.prom ] || install -m 0644 -o kpi -g kpi /dev/null /etc/fichiers-metriques/kpi.prom
install -m 0644 kpi.service kpi.timer kpi-journal.service /etc/systemd/system/
cd /
systemctl daemon-reload
systemctl start kpi.service
systemctl enable --now kpi.timer 2>&1
EOS
  [ "$?" = 0 ] || { nettoyer; return 1; }
  local f
  for f in metrics_exporter.py lecteur_loki.py; do
    attendu "$f installé identique" "$(sur "sha256sum /usr/local/lib/kpi/$f" | cut -c1-64)" "$(sha256sum < "$RACINE/tools/metrics-exporter/$f" | cut -c1-64)"
  done
  attendu "dossier d'installation effacé" "$(sur "test -e /tmp/kpi-installation && echo présent || echo effacé")" effacé
  for f in kpi-journal kpi; do attendu "résultat du premier passage, $f" "$(sur "systemctl show -p Result --value $f.service")" success; done
  attendu "timer" "$(sur "systemctl is-active kpi.timer")" active
  attendu "le compte kpi ne lit pas le mot de passe" "$(sur "sudo -u kpi test -r /etc/kpi-journal/grafana.password && echo lu || echo refusé")" refusé
  attendu "filtre réseau des deux unités" "$(sur "systemctl show -p IPAddressDeny --value kpi.service kpi-journal.service | grep -c '0.0.0.0/0'")" 2
  sur "cat /etc/fichiers-metriques/kpi.prom" > "$T/kpi.prom"
  masque < "$T/kpi.prom" | sed 's/^/  /'
  controle_prom
  sur "systemd-analyze security kpi.service kpi-journal.service entrees-scan.service 2> /dev/null" | masque | cut -c1-140
  return $ko
}

etape_pose_rejeu() {
  : "${REJEU:?étape réservée à rejeu.sh (REJEU=<libellé>)}"
  au_rejeu || return 1
  etape_pose
}

etape_sec_rejeu() {
  au_rejeu || return 1
  controles_hote
  : > "$T/journal"; : > "$T/kpi.prom"
  REG=192.168.161.13:5000 CA=$CA SIGNATURES=verifiees CLES=$T/pose/cles RELEVE=$T/pose/dates-git.tsv JOURNAL=$T/journal SORTIE=$T/kpi.prom \
    PRODUITS="sample-app sample-app-deb sample-app-rpm" /usr/bin/python3 -I "$T/pose/metrics_exporter.py"
  attendu "exportateur sur l'hôte, code" "$?" 0
  controle_prom
  return $ko
}

etape_verif() {
  local c
  jq -nc --arg t "$(date -u +%s)000" '{from: $t, to: $t, queries: [{refId: "A", datasource: {uid: "prometheus"}, expr: "{__name__=~\"kpi_.+\"}", instant: true, range: false}]}' > "$T/q.json"
  c=$(graf auditeur POST /api/ds/query "$T/q.json"); attendu "auditeur, Prometheus" "$c" 200
  jq -r '.results.A.frames[]? | select((.data.values | length) > 1) | "\(.schema.fields[1].labels.__name__) \(.data.values[1][0])"' "$T/r.json" > "$T/s"
  echo "séries kpi_* dans Prometheus : $(wc -l < "$T/s")"
  attendu "passage de moins de 20 min" "$(awk -v n="$(date -u +%s)" '$1 == "kpi_exportateur_passage_timestamp_seconds" {print (n - $2 < 1200) ? "oui" : "non"}' "$T/s")" oui
  attendu "lecture du journal de moins de 20 min" "$(awk -v n="$(date -u +%s)" '$1 == "kpi_exportateur_journal_timestamp_seconds" {print (n - $2 < 1200) ? "oui" : "non"}' "$T/s")" oui
  attendu "signatures refusées, sans date, illisible" "$(awk '/^kpi_(signatures_refusees|cles_non_relevees|pins_non_releves|exportateur_journal_illisible) /{s += $2; n++} END {print s + 0, (n > 3) ? "présentes" : "absentes"}' "$T/s")" "0 présentes"
  return $ko
}

etape_retrait() { # ACCORD DU PROPRIÉTAIRE
  sur "sudo bash -s" <<'EOS'
set -euo pipefail
systemctl disable --now kpi.timer 2>&1 || true
systemctl stop kpi.service kpi-journal.service 2>&1 || true
for f in /etc/systemd/system/kpi.service /etc/systemd/system/kpi.timer /etc/systemd/system/kpi-journal.service /etc/fichiers-metriques/kpi.prom \
  /usr/local/lib/kpi /etc/kpi /etc/kpi-journal /var/lib/kpi-journal; do if [ -e "$f" ]; then find "$f" -delete; fi; done
systemctl daemon-reload
for u in kpi kpi-journal; do id "$u" > /dev/null 2>&1 && userdel "$u" || true; done
EOS
  attendu "retrait" "$?" 0
  attendu "unités restantes" "$(sur "ls /etc/systemd/system/ | grep -c '^kpi'")" 0
  return $ko
}

case ${1:-} in
  sec|sec_rejeu|compte|compte_retrait|pose|pose_rejeu|verif|retrait) ;;
  *) echo "usage : $0 sec|sec_rejeu|compte|compte_retrait|pose|pose_rejeu|verif|retrait" >&2; exit 2 ;;
esac
rc=0
"etape_$1" || rc=$?
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ), bilan : $([ "$rc" = 0 ] && echo tenu || echo KO)"
exit "$rc"
