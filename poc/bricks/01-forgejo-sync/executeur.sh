#!/usr/bin/env bash
# Brique 01, jalon S3 : la synchro en timer systemd sur sc-stockage (D1 (a), décision du propriétaire du 02/11/2026).
#   installer   python3 et git de la VM relevés (aucun paquet ajouté) ; compte système synchro ; sync.py, synchro.sh, unités,
#               refs-propres.json, CA du PoC et /etc/synchro/sample-app-sync.env ; jeton de poc-sync en root 0600, remis
#               au seul service par LoadCredential ; durcissement relevé (systemd-analyze security)
#   essai       un run à la main (systemctl start) : code, rapport, métrique, journal de l'unité sans jeton
#   planifie    timer activé, période ramenée à 2 min le temps de la mesure (drop-in retiré ensuite) : deux runs planifiés
#               successifs sans intervention, métrique cohérente avec le dernier rapport
#   refspec     essai-refspec-negatif.sh dans la VM (git 2.47.3), à comparer à la mesure de S1 (git 2.53.0)
#   fuites      fuites.sh de la 08 sur les trois VM (jetons de S2 compris), journal déplacé dans resultats/ de la 01
# Prérequis : forgejo.sh comptes organisations amont miroir fork protections (S2). Aucun secret en argument de commande.
#
# Usage (racine du dépôt) : poc/bricks/01-forgejo-sync/executeur.sh <étape>…   (journal : resultats/executeur-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
PROJET=sample-app-sync
U=synchro@$PROJET
trap 'rm -rf "$W/refus.out"' EXIT

etat() { # dernier rapport et métrique du projet, lus dans la VM (jq sur l'hôte)
  local f
  f=$(sur sc-stockage "sudo sh -c 'ls -1 /var/lib/synchro/$PROJET/rapports/*.json | tail -1'")
  echo "rapport ${f##*/}"
  sur sc-stockage "sudo cat $f" | jq -c '{status, events: [.events[] | {type, ref}], bundle: (.bundle.file // null)}'
  sur sc-stockage "sudo cat /var/lib/synchro/$PROJET/$PROJET.prom" | grep -v '^#'
}

etape_installer() {
  sur sc-stockage "python3 --version; git --version"
  copier sc-stockage /tmp/synchro-installation "$here/sync.py" "$here/refs-propres.json" "$here/systemd/synchro.sh" \
    "$here/systemd/synchro@.service" "$here/systemd/synchro@.timer" "$here/systemd/$PROJET.env" "$P/ca-poc.crt" \
    "$S/forgejo-poc-sync.token"
  sur sc-stockage "sudo bash -s" <<EOF
set -euo pipefail
cd /tmp/synchro-installation
id synchro >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/synchro --no-create-home --shell /usr/sbin/nologin synchro
install -d -m 0755 /usr/local/lib/synchro /etc/synchro
install -d -m 0700 /etc/synchro/secrets
install -m 0644 sync.py /usr/local/lib/synchro/sync.py
install -m 0755 synchro.sh /usr/local/lib/synchro/synchro.sh
install -m 0644 refs-propres.json ca-poc.crt $PROJET.env /etc/synchro/
install -m 0600 forgejo-poc-sync.token /etc/synchro/secrets/poc-sync.token
install -m 0644 synchro@.service synchro@.timer /etc/systemd/system/
cd / && rm -rf /tmp/synchro-installation
systemctl daemon-reload
EOF
  # Continuité de l'état : le miroir local, les rapports et les bundles de S2 (hôte) passent dans la VM, qui en devient le
  # seul propriétaire. Un miroir neuf pousserait refs/archive/* avec --prune et retirerait de mirror/ les archives de S2.
  if sur sc-stockage "sudo test -d /var/lib/synchro/$PROJET/miroir.git"; then echo "état de la VM existant : gardé"; else
    D1=${SYNCHRO_DIR:-$HOME/.cache/supply-chain-poc/01}
    tar -C "$D1" -cf - "miroirs/$PROJET.git" "rapports/$PROJET" "bundles/$PROJET" \
      | sur sc-stockage "sudo sh -c 'set -e; t=\$(mktemp -d); tar -C \$t -xf -; install -d -m 0750 -o synchro -g synchro /var/lib/synchro /var/lib/synchro/$PROJET; \
          mv \$t/miroirs/$PROJET.git /var/lib/synchro/$PROJET/miroir.git; mv \$t/rapports/$PROJET /var/lib/synchro/$PROJET/rapports; \
          mv \$t/bundles/$PROJET /var/lib/synchro/$PROJET/bundles; rm -rf \$t; chown -R synchro:synchro /var/lib/synchro/$PROJET'"
    mv "$D1/miroirs/$PROJET.git" "$D1/miroirs/$PROJET.git.passe-a-la-vm-$(date -u +%Y%m%dT%H%M%SZ)"
    echo "état de S2 (hôte) copié dans la VM ; copie de l'hôte renommée, plus jamais synchronisée"
  fi
  sur sc-stockage "sudo ls -l /usr/local/lib/synchro /etc/synchro /etc/synchro/secrets /var/lib/synchro/$PROJET"
  [ "$(sur sc-stockage "sudo sha256sum /usr/local/lib/synchro/sync.py" | cut -d' ' -f1)" = "$(sha256sum "$here/sync.py" | cut -d' ' -f1)" ] \
    && echo "OK   sync.py installé identique à celui du dépôt" || { echo "KO   sync.py différent" >&2; exit 1; }
  sur sc-stockage "getent hosts sc-stockage.poc.test" && echo "OK   sc-stockage.poc.test résolu dans la VM" || { echo "KO   résolution de sc-stockage.poc.test" >&2; exit 1; }
  sur sc-stockage "systemd-analyze security $U.service 2>/dev/null | tail -1"
}

etape_essai() {
  local debut r
  debut=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'")
  r=0; sur sc-stockage "sudo systemctl start $U.service" || r=$?
  echo "systemctl start : code $r ; résultat de l'unité : $(sur sc-stockage "systemctl show -p Result -p ExecMainStatus --value $U.service" | paste -sd' ')"
  [ "$r" = 0 ] && echo "OK   run réussi (code 0 ou 2, SuccessExitStatus)" || { sur sc-stockage "sudo journalctl -u $U.service --since '$debut' -o cat" >&2; exit 1; }
  etat
  echo "## journal de l'unité"
  sur sc-stockage "sudo journalctl -u $U.service --since '$debut' -o cat"
  # Le jeton ne doit apparaître ni dans le journal de l'unité ni dans l'environnement exposé de systemd.
  if sur sc-stockage "sudo journalctl -u $U.service --since '$debut' -o cat" | grep -F -f "$S/forgejo-poc-sync.token" >/dev/null; then
    echo "KO   jeton dans le journal de l'unité" >&2; exit 1
  fi
  echo "OK   jeton absent du journal de l'unité"
}

etape_planifie() {
  local t0 n=0 runs
  sur sc-stockage "sudo bash -s" <<EOF
set -euo pipefail
install -d /etc/systemd/system/$U.timer.d
printf '[Timer]\nOnUnitActiveSec=\nOnUnitActiveSec=2min\nRandomizedDelaySec=0\nOnBootSec=\nOnActiveSec=10s\n' > /etc/systemd/system/$U.timer.d/mesure.conf
systemctl daemon-reload
systemctl enable --now $U.timer
EOF
  t0=$(sur sc-stockage "date '+%Y-%m-%d %H:%M:%S'")
  echo "timer activé à $t0 (période de mesure : 2 min)"
  for _ in $(seq 60); do
    runs=$(sur sc-stockage "sudo journalctl -u $U.service --since '$t0' -o cat" | grep -c '^Finished ' || true)
    n=$runs; [ "$n" -ge 2 ] && break
    sleep 10
  done
  sur sc-stockage "sudo journalctl -u $U.service --since '$t0' -o short-iso" | grep -E 'Starting|Finished|Deactivated|Failed' || true
  [ "$n" -ge 2 ] && echo "OK   deux runs planifiés sans intervention" || { echo "KO   $n run(s) planifié(s) en 10 min" >&2; exit 1; }
  etat
  sur sc-stockage "sudo sh -c 'rm -rf /etc/systemd/system/$U.timer.d && systemctl daemon-reload && systemctl restart $U.timer'"
  sur sc-stockage "systemctl list-timers $U.timer --no-pager | head -2"
  echo "drop-in de mesure retiré : période d'une heure rétablie"
}

etape_refspec() {
  copier sc-stockage /tmp/essai-refspec "$here/essai-refspec-negatif.sh"
  sur sc-stockage "bash /tmp/essai-refspec/essai-refspec-negatif.sh; rm -rf /tmp/essai-refspec"
}

etape_fuites() { # contrôle de fin de S3 : fuites.sh de la 08 (trois VM), qui cherche aussi les jetons de S2 (…/08/secrets)
  local f=$here/../08-trust-plane/resultats/fuites-synchro-s3.log
  "$here/../08-trust-plane/fuites.sh" synchro-s3 >/dev/null || true   # verdict lu dans son journal
  sleep 2   # fuites.sh écrit son journal par tee (substitution de processus) : fin d'écriture après sa sortie
  mv "$f" "$R/fuites-synchro-s3.log"
  grep -E '^(OK|KO)' "$R/fuites-synchro-s3.log"
  ! grep -q '^KO' "$R/fuites-synchro-s3.log" || exit 1
}

lancer executeur S3 "$@"
