#!/usr/bin/env bash
# Porte Conforma (ec validate image) sur les attestations signées par Chains v0.29.9 et v0.30.0 : banc de signature (main.go,
# mode signer) sur les vrais objets de j7-sample-app, registre en mémoire, clé jetable, puis ec v0.10.42 (même binaire que l'image
# de la porte, empreinte du verrou) avec la politique en service : bibliothèque conforma/policy ebd3fbd2 (arbre vérifié, sans les
# tests, comme l'image), porte.rego et taches.yml du dépôt, policy.yaml du dépôt aux chemins près. Le nom du registre est remplacé
# par celui du banc dans les objets (main.go) et dans porte.rego et taches.yml (ici), à l'identique pour les deux versions.
# Bundles de tâches et fermetures absents du registre du banc : refus dus au banc, les mêmes pour les deux versions ; la mesure
# est l'écart entre les deux ensembles de codes. Témoin : v0.30.0 jugée avec une autre clé publique.
# Tout tourne dans un espace réseau neuf (unshare -rn, boucle locale seule) : aucun appel ne peut sortir de l'hôte.
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/porte.sh
set -uo pipefail
export LC_ALL=C.UTF-8
[ -n "${BANC_ISOLE:-}" ] || exec unshare -rn env BANC_ISOLE=1 bash "$0" "$@"
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
P08=$depot/poc/bricks/08-trust-plane
LOG=$P08/resultats/chains-v0300-porte${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
T=$C/porte/travail   # effacé au début, gardé à la fin pour relecture
[ ! -e ~/.cache/supply-chain-poc/chains-v0300/porte/travail ] || find ~/.cache/supply-chain-poc/chains-v0300/porte/travail -delete
mkdir -p "$T/cle" "$T/autre" "$T/biblio" "$T/politique/regles" "$T/politique/donnees"
chmod 700 "$T/cle" "$T/autre"
SERVE=
trap '[ -z "$SERVE" ] || kill "$SERVE" 2> /dev/null' EXIT
HOTE=sc-stockage.poc.test:5000
O=$C/objets
CAS=j7-sample-app
PR=$O/pr-$CAS.json
mapfile -t TRS < <(jq -r '.status.childReferences[].name' "$PR" | sed "s#^#$O/tr-#; s#\$#.json#")
ANCIEN=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$PR")
CPOL=$HOME/.cache/supply-chain-poc/08/telechargements/conforma-policy
CPOL_COMMIT=$(sed -n 's/^CPOL_COMMIT=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
CPOL_ARBRE=$(sed -n 's/^CPOL_ARBRE=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
EC_BIN=$(sed -n 's/^EC_BIN=\([0-9a-f]*\).*/\1/p' "$P08/politique.sh")
# Codes que le banc à sec (chains-v0300-lecteurs-3.log, P5) a vus refuser l'énoncé neuf seul et pas l'ancien
ECART='porte.taches_vues slsa_build_scripted_build.build_task_image_results_found slsa_build_scripted_build.image_built_by_trusted_task tasks.pipeline_has_tasks'
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
codes() { # sortie json d'ec : codes des violations, triés, uniques, un par ligne
  jq -r '[.components[].violations[]?.metadata.code] | unique[]' "$1"
}
juger() { # nom image clé : ec validate image, comme le Job de la porte (--strict=false, --ignore-rekor, clé publique)
  SIGSTORE_REKOR_PUBLIC_KEY=$3 ec validate image --image "$2" --public-key "$3" --policy "$T/politique/policy.yaml" \
    --ignore-rekor --info --show-successes --output "json=$T/ec-$1.json" --strict=false > "$T/ec-$1.out" 2> "$T/ec-$1.err"
}
{
  echo "# porte.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), main.go $(sha256sum < "$here/main.go" | cut -c1-16)"
  ip link set lo up
  attendu "réseau du banc : interfaces" "$(ip -o link | wc -l)" 1
  attendu "réseau du banc : routes de la table principale" "$(ip route show table main | wc -l)" 0
  attendu "ec : empreinte du verrou (politique.sh)" "$(sha256sum < "$(command -v ec)" | cut -c1-64)" "$EC_BIN"
  echo "ec : $(ec version 2>&1 | sed -n 's/^Version *//p') ; cosign : $(cosign version 2>&1 | sed -n 's/^GitVersion: *//p')"
  for v in 29 30; do
    cmp -s "$here/main.go" "$C/src$v/cmd/banc-signature/main.go" && echo "src$v : commit $(git -C "$C/src$v" rev-parse HEAD), main.go identique, binaire $(sha256sum < "$C/sig/banc-signature$v" | cut -c1-16)" \
      || { echo "KO   src$v : main.go différent de celui du dépôt"; ko=$((ko + 1)); }
  done
  attendu "bibliothèque : arbre de $CPOL_COMMIT" "$(git -C "$CPOL" rev-parse "$CPOL_COMMIT^{tree}")" "$CPOL_ARBRE"
  git -C "$CPOL" archive "$CPOL_COMMIT" policy/release policy/lib | tar -x -C "$T/biblio"
  find "$T/biblio" -name '*_test.rego' -delete
  echo "bibliothèque : $(find "$T/biblio" -name '*.rego' | wc -l) fichiers Rego (sans les tests, comme l'image de la porte)"
  echo "cas : $CAS, ${#TRS[@]} TaskRuns, digest d'origine ${ANCIEN:0:19}…"
  "$C/sig/banc-signature30" cle "$T/cle"; "$C/sig/banc-signature30" cle "$T/autre"
  attendu "deux clés jetables" "$(cmp -s "$T/cle/cosign.pub" "$T/autre/cosign.pub" && echo identiques || echo distinctes)" distinctes
  "$C/sig/banc-signature30" serve "$T/port" & SERVE=$!
  for _ in $(seq 50); do [ -s "$T/port" ] && break; read -rt 0.1 < /dev/zero || true; done
  REG=127.0.0.1:$(cat "$T/port")
  # politique : fichiers du dépôt, nom du registre remplacé par celui du banc ; policy.yaml aux chemins du banc
  sed "s#$HOTE#$REG#g" "$P08/politique/porte/porte.rego" > "$T/politique/regles/porte.rego"
  sed "s#$HOTE#$REG#g" "$P08/politique/porte/taches.yml" > "$T/politique/donnees/taches.yml"
  sed "s#/politique/policy/#$T/biblio/policy/#; s#/etc/porte/#$T/politique/#" "$P08/politique/porte/policy.yaml" > "$T/politique/policy.yaml"
  attendu "noms remplacés dans porte.rego et taches.yml" "$(diff "$P08/politique/porte/porte.rego" "$T/politique/regles/porte.rego" | grep -c '^>') $(diff "$P08/politique/porte/taches.yml" "$T/politique/donnees/taches.yml" | grep -c '^>')" "1 15"
  attendu "policy.yaml : seuls les chemins changent" "$(diff <(grep -v '^ *#' "$P08/politique/porte/policy.yaml") <(grep -v '^ *#' "$T/politique/policy.yaml") | grep -c '^>')" 4
  grep -v '^ *#' "$T/politique/policy.yaml" | sed "s#$T#TRAVAIL#g; s/^/  /"
  for v in 29 30; do
    echo "## v$v : signature"
    B=$C/sig/banc-signature$v
    D=$("$B" image "$REG" builds/sample-app); echo "image du banc : ${D:0:19}…"; echo "$D" > "$T/digest-$v"
    "$B" signer "$REG" "$T/cle" "$HOTE" "$ANCIEN" "$D" "$PR" "${TRS[@]}" > "$T/sign-$v.json" 2> "$T/zap-$v.log"; attendu "v$v signer, code" "$?" 0
    attendu "v$v erreurs de Sign" "$(jq '[.sign[] | select(. != "")] | length' "$T/sign-$v.json")" 0
    cosign verify-attestation --key "$T/cle/cosign.pub" --insecure-ignore-tlog=true --type slsaprovenance1 "$REG/builds/sample-app@$D" > "$T/att-$v.json" 2> "$T/att-$v.err"
    attendu "v$v cosign verify-attestation, attestations" "$(grep -c . "$T/att-$v.json")" 2
  done
  for v in 29 30; do
    echo "## v$v : porte"
    juger "$v" "$REG/builds/sample-app@$(cat "$T/digest-$v")" "$T/cle/cosign.pub"; attendu "v$v ec, code (--strict=false)" "$?" 0
    echo "succès : $(jq '.success' "$T/ec-$v.json") ; violations $(jq '[.components[].violations[]?] | length' "$T/ec-$v.json"), avertissements $(jq '[.components[].warnings[]?] | length' "$T/ec-$v.json"), réussites $(jq '[.components[].successes[]?] | length' "$T/ec-$v.json"), attestations lues $(jq '[.components[].attestations[]?] | length' "$T/ec-$v.json")"
    codes "$T/ec-$v.json" > "$T/codes-$v.txt"
    echo "codes refusés :"; sed 's/^/  /' "$T/codes-$v.txt"
    jq -r '.components[].violations[]? | "  " + .metadata.code + " : " + (.msg | .[0:200])' "$T/ec-$v.json" | sed "s#$REG#REGISTRE#g; s#sha256:\([0-9a-f]\{12\}\)[0-9a-f]\{52\}#sha256:\1…#g" | sort | uniq -c
    echo "erreurs d'ec : $(grep -c . "$T/ec-$v.err")"; sed "s#$REG#REGISTRE#g" "$T/ec-$v.err" | cut -c1-240 | sort | uniq -c | head -20
  done
  echo "## écart"
  echo "v30 seul : $(comm -13 "$T/codes-29.txt" "$T/codes-30.txt" | tr '\n' ' ')"
  echo "v29 seul : $(comm -23 "$T/codes-29.txt" "$T/codes-30.txt" | tr '\n' ' ')"
  attendu "codes refusés pour v0.29.9 et pas pour v0.30.0" "$(comm -23 "$T/codes-29.txt" "$T/codes-30.txt" | grep -c .)" 0
  attendu "porte.taches_vues dans l'écart" "$(comm -13 "$T/codes-29.txt" "$T/codes-30.txt" | grep -cx porte.taches_vues)" 1
  attendu "écart contenu dans celui du banc à sec" "$(comm -13 "$T/codes-29.txt" "$T/codes-30.txt" | grep -cvxF -f <(tr ' ' '\n' <<< "$ECART"))" 0
  attendu "v29 : porte.taches_vues absent" "$(grep -cx porte.taches_vues "$T/codes-29.txt")" 0
  echo "## témoin : v0.30.0 jugée avec une autre clé publique"
  juger temoin "$REG/builds/sample-app@$(cat "$T/digest-30")" "$T/autre/cosign.pub"; attendu "témoin ec, code (--strict=false)" "$?" 0
  attendu "témoin succès" "$(jq '.success' "$T/ec-temoin.json")" false
  codes "$T/ec-temoin.json" > "$T/codes-temoin.txt"
  echo "codes refusés :"; sed 's/^/  /' "$T/codes-temoin.txt"
  echo "témoin : attestations lues $(jq '[.components[].attestations[]?] | length' "$T/ec-temoin.json")"
  attendu "témoin : porte.taches_vues absent (rien de lu)" "$(grep -cx porte.taches_vues "$T/codes-temoin.txt")" 0
  echo "erreurs d'ec : $(grep -c . "$T/ec-temoin.err")"; sed "s#$REG#REGISTRE#g" "$T/ec-temoin.err" | cut -c1-240 | sort | uniq -c | head -20
  kill "$SERVE"; wait "$SERVE" 2> /dev/null; SERVE=
  echo "## bilan : $ko KO, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
