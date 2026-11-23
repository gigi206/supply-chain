#!/usr/bin/env bash
# Banc de secrets_ctrl_juge (preuves.sh, additif du 2026-11-23 après l'arrêt du rejeu un-trait-1 à « J8 (contrôleurs) ») : la
# fonction est lue dans preuves.sh (jamais recopiée). Cas 1 à 7 : lignes d'audit témoins, hors ligne. Cas 8 : vraies lignes d'audit
# des deux contrôleurs, relevées en lecture seule sur sc-confiance (même filtre qu'etape_controleurs), et démarrages de kube-apiserver.
# Usage (racine du dépôt) : DISTRO=rke2 bash <ce fichier> <journal>
set -uo pipefail
export LC_ALL=C DISTRO=${DISTRO:-rke2}
J=$1
test ! -e "$J" || { echo "existe déjà : $J"; exit 1; }
here=poc/bricks/08-trust-plane
. "$here/commun.sh"
eval "$(awk '/^secrets_ctrl_juge\(\) \{/,/^}/' "$here/preuves.sh")"
declare -F secrets_ctrl_juge > /dev/null || { echo "secrets_ctrl_juge introuvable dans preuves.sh"; exit 3; }
B=$(mktemp -d "$HOME/.cache/supply-chain-poc/banc-controleurs-juge.XXXXXX")
trap 'find "$B" -delete' EXIT
N=0; KO=0
attendu() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : $2 (attendu $3)"; KO=$((KO + 1)); fi; }
P=system:serviceaccount:tekton-pipelines:tekton-pipelines-controller
D0=2026-11-23T21:21:07Z
d0=$(date -u -d "$D0" +%s)
l() { # instant verbe espace code : une ligne d'audit témoin du contrôleur de Pipelines sur les Secrets
  jq -nc --arg t "$1" --arg v "$2" --arg n "$3" --argjson c "$4" --arg u "$P" '{requestReceivedTimestamp: $t, stage: "ResponseComplete", verb: $v,
    user: {username: $u}, impersonatedUser: null, objectRef: {resource: "secrets", namespace: $n}, responseStatus: {code: $c}}'
}
bilan() { secrets_ctrl_juge "$1" "$2" | sed -n 's/^BILAN|//p'; }
{
echo "# banc de secrets_ctrl_juge, $(date -u +%FT%TZ), $(git rev-parse --short=8 HEAD), preuves.sh $(sha256sum < "$here/preuves.sh" | cut -c1-16)"
echo "## cas témoins (démarrage $D0)"
{ l 2026-11-23T21:21:09.219027Z watch builds 403; l 2026-11-23T21:21:12.858406Z watch builds 200; } > "$B/c1"
attendu "1. watch 403 dans builds à +2 s, puis 200 : écarté, compté 0, témoin vrai" "$(bilan "$B/c1" "[$d0]")" "0|true"
attendu "1. ligne ECARTE affichée" "$(secrets_ctrl_juge "$B/c1" "[$d0]" | grep -c '^ECARTE|')" 1
{ l 2026-11-23T21:22:08.000000Z watch builds 403; l 2026-11-23T21:22:12.000000Z watch builds 200; } > "$B/c2"
attendu "2. watch 403 dans builds à +61 s : compté" "$(bilan "$B/c2" "[$d0]")" "1|true"
{ l 2026-11-23T21:21:09.000000Z get builds 403; l 2026-11-23T21:21:12.000000Z watch builds 200; } > "$B/c3"
attendu "3. get 403 dans builds dans la fenêtre : compté (seuls les watch)" "$(bilan "$B/c3" "[$d0]")" "1|true"
{ l 2026-11-23T21:21:09.000000Z watch kube-system 403; l 2026-11-23T21:21:12.000000Z watch builds 200; } > "$B/c4"
attendu "4. watch 403 hors de builds dans la fenêtre : compté" "$(bilan "$B/c4" "[$d0]")" "1|true"
{ l 2026-11-23T21:30:00.000000Z get kube-system 200; l 2026-11-23T21:21:12.000000Z watch builds 200; } > "$B/c5"
attendu "5. lecture 200 hors de builds : comptée" "$(bilan "$B/c5" "[$d0]")" "1|true"
{ l 2026-11-23T21:21:09.000000Z watch builds 403; l 2026-11-23T21:21:00.000000Z watch builds 200; } > "$B/c6"
attendu "6. watch écarté sans 200 après lui : témoin faux" "$(bilan "$B/c6" "[$d0]")" "0|false"
attendu "7. aucun démarrage connu ([], k3s) : le cas 1 est compté" "$(bilan "$B/c1" "[]")" "1|true"
attendu "7b. deux démarrages, refus dans la fenêtre du premier : écarté" "$(bilan "$B/c1" "[$((d0 - 3600)),$d0]")" "0|true"
echo "## cas 8 : vraies lignes d'audit (lecture seule, sc-confiance)"
{ audit_api tekton-pipelines-controller; audit_api tekton-chains-controller; } | jq -c 'select(.objectRef.resource == "secrets"
  and .impersonatedUser == null and (.user.username | test("^system:serviceaccount:tekton-(pipelines:tekton-pipelines|chains:tekton-chains)-controller$")))' \
  | sort -u > "$B/reel"
dem=$(kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -c '[.items[0].status.containerStatuses[0]
  | (.state.running.startedAt, .lastState.terminated.startedAt) | select(. != null) | fromdateiso8601]')
echo "lignes : $(wc -l < "$B/reel") ; démarrages : $dem"
secrets_ctrl_juge "$B/reel" "$dem" | sed 's/^/  /'
attendu "8. audit réel du rejeu : compté 0, témoin vrai" "$(bilan "$B/reel" "$dem")" "0|true"
attendu "8. audit réel : lignes écartées" "$(secrets_ctrl_juge "$B/reel" "$dem" | grep -c '^ECARTE|')" 2
attendu "8. audit réel, sans l'exception (ancien contrôle) : 2 comptées" \
  "$(jq -s '[.[] | select(.objectRef.namespace != "builds" or .responseStatus.code == 403)] | length' "$B/reel")" 2
echo "## bilan : $N cas, $KO écart(s)"
} > "$J" 2>&1
sed -i "s#$HOME#~#g" "$J"
cat "$J"
