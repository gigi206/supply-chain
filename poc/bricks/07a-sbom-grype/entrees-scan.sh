#!/usr/bin/env bash
# Brique 07b, tranche 1, étape 3 : pose de entrees-scan sur sc-stockage (décision « Les deux » du 21/11/2026 : comptes dans
# Prometheus, liste dans Loki une fois par scan). Calqué sur etape_g8_metriques de plateforme.sh.
# Étapes :
#   sec      lecture seule : SCANS relu dans l'unité fraicheur-scan en place (mêmes artefacts), unité rendue dans $T, comparée
#            au modèle, aucune écriture sur la VM. Sans accord.
#   pose     ACCORD DU PROPRIÉTAIRE (sudo sur sc-stockage) : compte système, script, fichier .prom vide, unité, timer ; un premier
#            passage lancé ; contrôles sur la VM (empreinte, résultat, résumé du journal, séries, score systemd-analyze).
#   verif    lecture seule, par l'auditeur dans Grafana : séries dans Prometheus égales à jq sur les énoncés relus en anonyme ;
#            lignes de la liste dans Loki, en comptes seulement (aucune ligne brute archivée) ; clé « scanne » égale à la série.
#   retrait  ACCORD DU PROPRIÉTAIRE (sudo) : timer et service arrêtés, fichiers, état et compte retirés.
# Aucune écriture dans Zot ; G7 n'est pas touché (GET anonymes seulement). Pas de tableau de bord : le PoC n'en a aucun, la
# consultation passe par l'exploration de Grafana, comme G8.
# Usage (racine du dépôt) : mise exec -- poc/bricks/07a-sbom-grype/entrees-scan.sh <étape> > <journal>
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
O=$HOME/.cache/supply-chain-poc
O8=$O/08
CA=$O8/pki/ca-poc.crt
REG=192.168.161.13:5000
GRAF=https://192.168.161.13:3001
SSH_OPTS=(-i "$O8/ssh/id_ed25519" -o UserKnownHostsFile="$O8/ssh/known_hosts" -o StrictHostKeyChecking=yes -o BatchMode=yes)
sur() { env -u SSH_AUTH_SOCK ssh "${SSH_OPTS[@]}" poc@192.168.161.13 "$@"; }   # sc-stockage
ko=0
ok() { echo "OK   $1"; }
attendu() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }
masque() { sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]'; }
T=$O/07a/entrees-scan   # chemin écrit en entier : effacé à la sortie
[ ! -e ~/.cache/supply-chain-poc/07a/entrees-scan ] || find ~/.cache/supply-chain-poc/07a/entrees-scan -delete
mkdir -p "$T"
trap 'find ~/.cache/supply-chain-poc/07a/entrees-scan -delete' EXIT
echo "début : $(date -u +%Y-%m-%dT%H:%M:%SZ), étape ${1:-?}, entrees-scan.py $(sha256sum < "$here/systemd/entrees-scan.py" | cut -c1-16)…"

scans_en_place() { # SCANS de l'unité fraicheur-scan en place (drop-in s6a-deb.conf) : deux « dépôt@sha256:… »
  sur "systemctl show -p Environment --value fraicheur-scan.service" | tr ' ' '\n' | tr -d '"' | sed 's/^SCANS=//' \
    | grep -E '^builds/scan/[a-z-]+@sha256:[0-9a-f]{64}$' | paste -sd' '
}
rendre() { # unité rendue dans $T ; remplacement par bash, pas par sed (SCANS contient des /)
  local m
  m=$(cat "$here/systemd/entrees-scan.service")
  printf '%s\n' "${m//@SCANS@/$1}" > "$T/entrees-scan.service"
}
graf() { # source requête instant(true|false) : réponse JSON de /api/ds/query, lue par l'auditeur ; mot de passe par l'entrée standard
  local t body
  t=$(date -u +%s)000
  if [ "$1" = loki ]; then
    body=$(jq -nc --arg q "$2" --arg t "$t" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"loki"},expr:$q,queryType:"instant",maxLines:1}]}')
  else
    body=$(jq -nc --arg q "$2" --arg t "$t" '{from:$t,to:$t,queries:[{refId:"A",datasource:{uid:"prometheus"},expr:$q,instant:true,range:false}]}')
  fi
  printf 'user = "auditeur:%s"\n' "$(cat "$O8/secrets/grafana-auditeur.password")" \
    | curl -sS -K - --cacert "$CA" -H 'Content-Type: application/json' -X POST "$GRAF/api/ds/query" -d "$body"
}
valeurs() { jq -r '[.results.A.frames[]? | select((.data.values | length) > 1) | "\(.schema.fields[1].labels // {} | del(.__name__) | tojson) \(.data.values[1][0])"] | sort[]'; }

etape_sec() {
  local s
  s=$(scans_en_place)
  echo "SCANS de fraicheur-scan en place : $(printf '%s\n' "$s" | sed -E 's/@sha256:([0-9a-f]{12})[0-9a-f]*/@sha256:\1…/g')"
  attendu "deux artefacts dans SCANS" "$(printf '%s\n' "$s" | wc -w)" 2
  rendre "$s"
  echo "## unité rendue, écart au modèle"
  diff "$here/systemd/entrees-scan.service" "$T/entrees-scan.service" | sed -E 's/@sha256:([0-9a-f]{12})[0-9a-f]*/@sha256:\1…/g' || true
  attendu "lignes changées par le rendu" "$(diff "$here/systemd/entrees-scan.service" "$T/entrees-scan.service" | grep -c '^>' || true)" 1
  attendu "plus aucun @SCANS@" "$(grep -c '@SCANS@' "$T/entrees-scan.service" || true)" 0
  echo "## état sur sc-stockage (lecture, sans sudo)"
  sur "python3 --version; id entrees-scan >/dev/null 2>&1 && echo 'compte entrees-scan : présent' || echo 'compte entrees-scan : absent';
       test -e /etc/fichiers-metriques/entrees-scan.prom && echo 'entrees-scan.prom : présent' || echo 'entrees-scan.prom : absent';
       systemctl is-enabled entrees-scan.timer 2>&1 | sed 's/^/entrees-scan.timer : /'" | masque
  return $ko
}

etape_pose() { # ACCORD DU PROPRIÉTAIRE
  local s
  s=$(scans_en_place)
  attendu "deux artefacts dans SCANS" "$(printf '%s\n' "$s" | wc -w)" 2
  [ "$ko" = 0 ] || return 1
  rendre "$s"
  # sous « etape || rc », set -e ne joue plus : chaque écriture s'arrête d'elle-même sur un échec
  sur "if [ -e /tmp/entrees-scan-installation ]; then find /tmp/entrees-scan-installation -delete; fi; mkdir -m 0700 /tmp/entrees-scan-installation" || return 1
  env -u SSH_AUTH_SOCK scp -q "${SSH_OPTS[@]}" "$here/systemd/entrees-scan.py" "$T/entrees-scan.service" "$here/systemd/entrees-scan.timer" \
    poc@192.168.161.13:/tmp/entrees-scan-installation/ < /dev/null || return 1
  sur "sudo bash -s" <<'EOF'
set -euo pipefail
cd /tmp/entrees-scan-installation
id entrees-scan >/dev/null 2>&1 || useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin entrees-scan
install -d -m 0755 /usr/local/lib/entrees-scan
install -m 0755 entrees-scan.py /usr/local/lib/entrees-scan/
[ -e /etc/fichiers-metriques/entrees-scan.prom ] || install -m 0644 -o entrees-scan -g entrees-scan /dev/null /etc/fichiers-metriques/entrees-scan.prom
install -m 0644 entrees-scan.service entrees-scan.timer /etc/systemd/system/
cd / && find /tmp/entrees-scan-installation -delete
systemctl daemon-reload
systemctl start entrees-scan.service
systemctl enable --now entrees-scan.timer 2>&1
EOF
  [ "$?" = 0 ] || return 1
  attendu "entrees-scan.py installé identique" "$(sur "sha256sum /usr/local/lib/entrees-scan/entrees-scan.py" | cut -c1-64)" \
    "$(sha256sum < "$here/systemd/entrees-scan.py" | cut -c1-64)"
  attendu "résultat du premier passage" "$(sur "systemctl show -p Result --value entrees-scan.service")" success
  attendu "timer actif" "$(sur "systemctl is-active entrees-scan.timer")" active
  echo "## premier passage : résumé et nombre de lignes d'entrée au journal (lignes elles-mêmes non archivées)"
  sur "sudo journalctl -u entrees-scan.service -o cat --no-pager | grep -v '^{' | tail -n 3; echo \"lignes d'entrée : \$(sudo journalctl -u entrees-scan.service -o cat --no-pager | grep -c '^{')\"" | masque
  echo "## séries écrites"
  sur "cat /etc/fichiers-metriques/entrees-scan.prom" | masque | sed 's/^/  /'
  attendu "séries écrites" "$(sur "wc -l < /etc/fichiers-metriques/entrees-scan.prom")" 20
  sur "systemd-analyze security entrees-scan.service 2>/dev/null | tail -n 1; systemd-analyze security fraicheur-scan.service 2>/dev/null | tail -n 1 | sed 's/^/fraicheur-scan, pour comparer : /'"
  return $ko
}

etape_verif() {
  local s d digest m l att obt n
  s=$(scans_en_place)
  echo "## Prometheus, lu par l'auditeur"
  graf prometheus 'scan_entrees or scan_entrees_kev or scan_entrees_avec_correctif or scan_entrees_scanne_timestamp_seconds' > "$T/p.json"
  attendu "séries scan_entrees* dans Prometheus" "$(valeurs < "$T/p.json" | wc -l)" 20
  for d in $s; do
    digest=${d#*@}; d=${d%@*}
    m=$(curl -fsS --cacert "$CA" "https://$REG/v2/$d/referrers/$digest" | jq -r '.manifests
      | map(select(.annotations["dev.sigstore.bundle.predicateType"] == "https://supply-chain.example/scan/v1"))
      | sort_by(.annotations["org.opencontainers.image.created"]) | .[-1].digest')
    l=$(curl -fsS --cacert "$CA" -H 'Accept: application/vnd.oci.image.manifest.v1+json' "https://$REG/v2/$d/manifests/$m" | jq -r '.layers[0].digest')
    curl -fsS --cacert "$CA" "https://$REG/v2/$d/blobs/$l" | jq -r '.dsseEnvelope.payload | @base64d' > "$T/e.json"
    att=$(jq -r --argjson t "$(date -ud "$(jq -r .predicate.scannedAt "$T/e.json")" +%s)" '.predicate.vulnerabilities as $v
      | (["Critical","High","Medium","Low","Negligible","Unknown","autre"] | map(. as $g | "g=\($g) \($v | map(select(.severity == $g)) | length)")[]),
        "kev \($v | map(select(.kev)) | length)", "correctif \($v | map(select((.fixedIn | length) > 0)) | length)", "scanne \($t)"' "$T/e.json")
    obt=$(jq -r --arg d "$d" '[.results.A.frames[]? | select((.data.values | length) > 1) | select(.schema.fields[1].labels.depot == $d)
      | {n: .schema.fields[1].labels.__name__, g: (.schema.fields[1].labels.gravite // ""), v: .data.values[1][0]}] as $s
      | (["Critical","High","Medium","Low","Negligible","Unknown","autre"][] as $g | $s[] | select(.n == "scan_entrees" and .g == $g) | "g=\($g) \(.v)"),
        ($s[] | select(.n == "scan_entrees_kev") | "kev \(.v)"), ($s[] | select(.n == "scan_entrees_avec_correctif") | "correctif \(.v)"),
        ($s[] | select(.n == "scan_entrees_scanne_timestamp_seconds") | "scanne \(.v)")' "$T/p.json")
    if [ "$att" = "$obt" ]; then ok "$d : séries de Prometheus = jq ($(printf '%s\n' "$att" | grep -v ' 0$' | paste -sd',' | sed 's/,/, /g'))"
    else echo "KO   $d : séries de Prometheus différentes de jq"; diff <(printf '%s\n' "$att") <(printf '%s\n' "$obt") || true; ko=1; fi
    echo "## Loki, lu par l'auditeur, en comptes : $d"
    n=$(jq '.predicate.vulnerabilities | length' "$T/e.json")
    graf loki "sum(count_over_time({source=\"journal\", unite=\"entrees-scan.service\"} | json | depot=\"$d\" | scanne=\"$(date -ud "$(jq -r .predicate.scannedAt "$T/e.json")" +%s)\" [24h]))" > "$T/l.json"
    attendu "lignes de $d dans Loki pour ce scan (clé scanne), sur 24 h" "$(valeurs < "$T/l.json" | sed 's/^{} //')" "$n"
  done
  graf loki 'sum(count_over_time({source="journal", unite="entrees-scan.service"} |= "entrées " [24h]))' > "$T/r.json"
  echo "lignes de résumé dans Loki sur 24 h : $(valeurs < "$T/r.json" | sed 's/^{} //')"
  return $ko
}

etape_retrait() { # ACCORD DU PROPRIÉTAIRE
  sur "sudo bash -s" <<'EOF'
set -euo pipefail
systemctl disable --now entrees-scan.timer 2>&1 || true
systemctl stop entrees-scan.service 2>&1 || true
rm -f /etc/systemd/system/entrees-scan.service /etc/systemd/system/entrees-scan.timer /etc/fichiers-metriques/entrees-scan.prom
for d in /usr/local/lib/entrees-scan /var/lib/entrees-scan; do if [ -e "$d" ]; then find "$d" -delete; fi; done
systemctl daemon-reload
id entrees-scan >/dev/null 2>&1 && userdel entrees-scan || true
EOF
  [ "$?" = 0 ] || return 1
  sur "test -e /etc/systemd/system/entrees-scan.service && echo 'unité : présente' || echo 'unité : absente'; id entrees-scan >/dev/null 2>&1 && echo 'compte : présent' || echo 'compte : absent'"
}

case ${1:-} in
  sec|pose|verif|retrait) ;;
  *) echo "usage : $0 sec|pose|verif|retrait" >&2; exit 2 ;;
esac
rc=0
"etape_$1" || rc=$?
echo "fin : $(date -u +%Y-%m-%dT%H:%M:%SZ), bilan : $([ "$rc" = 0 ] && echo tenu || echo KO)"
exit "$rc"
