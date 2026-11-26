#!/usr/bin/env bash
# Politiques Kyverno (CLI 1.19.2, kyverno apply) sur les attestations signées par Chains v0.29.9 et v0.30.0 : banc de signature
# (main.go, mode signer) sur les vrais objets de j7-sample-app, registre en mémoire sur 127.0.0.1 (HTTP), clé jetable.
# Entrée de Kyverno comme en service : bundles Sigstore v0.3 en referrers de l'image dans un dépôt séparé (horodatage/bundles),
# fabriqués comme tsa/horodater.sh (cosign bundle create, vérifiés par cosign verify-blob-attestation : clé, sujet, prédicat),
# mais SANS jeton TSA (pas de TSA dans le banc) ; le registre du banc n'a pas l'API referrers : repli par étiquette (oras, Kyverno).
# Ordre de publication fixé : bundle du TaskRun d'abord, du PipelineRun ensuite (Kyverno garde la dernière provenance valide) ;
# chaque diagnostic contrôle que la provenance retenue est celle du PipelineRun (invocationId = uid du PipelineRun).
# Politiques :
#   reserve-c  politique/reserve-c/ivpol.tmpl.yaml rendue par generer.py (liste revue et builders de la porte, source de j7),
#              modes diagnostic (statut de chaque règle) et décision ; nom du registre remplacé dans taches.yml
#   c9         fonction ivpol de commun.sh (contrôle 9 : signature des bundles seulement), lue dans le fichier, sans tsaCertChain
# Témoins : liste revue sans le digest de publier-image (trusted_task.trusted) ; autre clé publique (reserve-c et c9).
# Tout tourne dans un espace réseau neuf (unshare -rn, boucle locale seule) : aucun appel ne peut sortir de l'hôte.
# Usage (racine du dépôt) : [SUFFIXE=-2] mise exec -- bash poc/bricks/08-trust-plane/essais/chains-v0300-signature/ivpol.sh
set -uo pipefail
export LC_ALL=C.UTF-8
[ -n "${BANC_ISOLE:-}" ] || exec unshare -rn env BANC_ISOLE=1 bash "$0" "$@"
here=$(cd "$(dirname "$0")" && pwd)
depot=$(git -C "$here" rev-parse --show-toplevel)
P08=$depot/poc/bricks/08-trust-plane
LOG=$P08/resultats/chains-v0300-ivpol${SUFFIXE:-}.log
[ ! -e "$LOG" ] || { echo "journal présent, jamais réécrit : $LOG" >&2; exit 2; }
C=$HOME/.cache/supply-chain-poc/chains-v0300
T=$C/ivpol/travail   # effacé au début, gardé à la fin pour relecture
[ ! -e ~/.cache/supply-chain-poc/chains-v0300/ivpol/travail ] || find ~/.cache/supply-chain-poc/chains-v0300/ivpol/travail -delete
mkdir -p "$T/cle" "$T/autre" "$T/c9" "$T/c9-autre"
chmod 700 "$T/cle" "$T/autre"
SERVE=
trap '[ -z "$SERVE" ] || kill "$SERVE" 2> /dev/null' EXIT
HOTE=sc-stockage.poc.test:5000
O=$C/objets
CAS=j7-sample-app
PR=$O/pr-$CAS.json
mapfile -t TRS < <(jq -r '.status.childReferences[].name' "$PR" | sed "s#^#$O/tr-#; s#\$#.json#")
ANCIEN=$(jq -r '.status.results[] | select(.name == "IMAGE_DIGEST") | .value' "$PR")
UID_PR=$(jq -r '.metadata.uid' "$PR")
URL=$(jq -r '.spec.params[] | select(.name == "depot") | .value' "$PR")
REV=$(jq -r '.spec.params[] | select(.name == "commit") | .value' "$PR")
PREDICAT=https://slsa.dev/provenance/v1
TYPE=application/vnd.dev.sigstore.bundle.v0.3+json
NUL=sha256:0000000000000000000000000000000000000000000000000000000000000000
ECART='slsa_build_scripted_build.build_task_image_results_found tasks.pipeline_has_tasks'
ko=0
attendu() { # libellé obtenu attendu
  if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "KO   $1 : obtenu « $2 », attendu « $3 »"; ko=$((ko + 1)); fi
}
publier() { # version digest : bundles sans jeton des attestations de l'image, vérifiés, en referrers dans horodatage/bundles
  local v=$1 D=$2 i=0 e W inv
  cosign download attestation "$REG/builds/sample-app@$D" > "$T/env-$v.jsonl" 2> "$T/env-$v.err"
  attendu "v$v attestations téléchargées" "$(grep -c . "$T/env-$v.jsonl")" 2
  oras manifest fetch --plain-http --descriptor "$REG/builds/sample-app@$D" > "$T/sujet-$v.json" 2> "$T/sujet-$v.err"
  : > "$T/ordre-$v"; : > "$T/ordre-$v.tr"
  while IFS= read -r e <&3; do
    i=$((i + 1)); W=$T/b-$v-$i; mkdir -p "$W"
    printf '%s' "$e" > "$W/env.json"
    jq -r '.signatures[0].sig' "$W/env.json" > "$W/sig.b64"; jq -r '.payload' "$W/env.json" | base64 -d > "$W/payload.json"
    inv=$(jq -r '.predicate.runDetails.metadata.invocationId' "$W/payload.json")
    cosign bundle create --artifact "$W/payload.json" --signature "$W/sig.b64" --attestation "$W/env.json" --key "$T/cle/cosign.pub" \
      --ignore-tlog --out "$W/bundle.json" > "$W/creation.out" 2>&1; attendu "v$v bundle $i créé" "$?" 0
    cosign verify-blob-attestation --bundle "$W/bundle.json" --new-bundle-format --key "$T/cle/cosign.pub" --insecure-ignore-tlog \
      --type "$PREDICAT" --digest "${D#sha256:}" --digestAlg sha256 > "$W/verif.out" 2>&1; attendu "v$v bundle $i vérifié (clé, sujet, prédicat)" "$?" 0
    if [ "$inv" = "$UID_PR" ]; then echo "$W pr" >> "$T/ordre-$v"; else echo "$W tr" >> "$T/ordre-$v.tr"; fi
  done 3< "$T/env-$v.jsonl"
  cat "$T/ordre-$v.tr" "$T/ordre-$v" > "$T/ordre-$v.tout"
  attendu "v$v ordre de publication" "$(cut -d' ' -f2 "$T/ordre-$v.tout" | tr '\n' ' ')" "tr pr "
  i=0
  while read -r W genre; do
    i=$((i + 1))
    oras blob push --plain-http "$REG/horodatage/bundles" "$W/bundle.json" > /dev/null 2> "$W/blob.err"
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"%s","config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:%s","size":2},"layers":[{"mediaType":"%s","digest":"sha256:%s","size":%s}],"subject":%s,"annotations":{"dev.sigstore.bundle.content":"dsse-envelope","dev.sigstore.bundle.predicateType":"%s"}}' \
      "$TYPE" "$(printf '{}' | sha256sum | cut -c1-64)" "$TYPE" "$(sha256sum < "$W/bundle.json" | cut -c1-64)" "$(wc -c < "$W/bundle.json")" \
      "$(cat "$T/sujet-$v.json")" "$PREDICAT" > "$W/manifeste.json"
    oras manifest push --plain-http "$REG/horodatage/bundles:${D#sha256:}-$i-$genre" "$W/manifeste.json" > "$W/manifeste.out" 2>&1
    attendu "v$v bundle $genre publié" "$?" 0
  done < "$T/ordre-$v.tout"
}
rendre() { # sortie clé taches.yml mode : reserve-c rendue
  python3 -I "$P08/politique/reserve-c/generer.py" "$P08/politique/reserve-c/ivpol.tmpl.yaml" "$2" "$3" "$P08/politique/porte/policy.yaml" \
    reserve-c "$REG/*" "$REG/horodatage/bundles" "$URL" "$REV" "$4" > "$1"
}
appliquer() { # nom politique image : kyverno apply ; $T/k-<nom>.res (résultat TAB message) ; KO si pas exactement un résultat
  printf 'apiVersion: v1\nkind: Pod\nmetadata: {name: banc, namespace: bancc}\nspec:\n  containers:\n    - name: app\n      image: %s\n' "$3" > "$T/pod-$1.yaml"
  kyverno apply "$2" --resource "$T/pod-$1.yaml" --policy-report --output-format json > "$T/k-$1.out" 2> "$T/k-$1.err"
  python3 -I -c 'import json,re,sys
t = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1]).read()); i = t.find("{"); d = json.loads(t[i:]) if i >= 0 else {}
r = d.get("results", [])
if len(r) != 1: print("absent\t%d résultats" % len(r)); sys.exit()
print(r[0].get("result", "?") + "\t" + (r[0].get("message") or "").replace("\n", " "))' "$T/k-$1.out" > "$T/k-$1.res"
  [ "$(cut -f1 "$T/k-$1.res")" != absent ] || { echo "KO   $1 : politique non évaluée ($(cut -f2 "$T/k-$1.res") ; $(head -c 200 "$T/k-$1.err"))"; ko=$((ko + 1)); }
  [ -s "$T/k-$1.err" ] && echo "  $1, erreurs du CLI : $(grep -c . "$T/k-$1.err")" && cut -c1-300 "$T/k-$1.err" | sed "s#$REG#REGISTRE#g" | sort | uniq -c | head -5
  return 0
}
diag() { # nom politique image : diagnostic ; $T/r-<nom> (code=statut, triés) ; $T/inv-<nom> : « DIAG invocationId retenu »
  appliquer "$@"
  cut -f2 "$T/k-$1.res" | tr ' ' '\n' | sed -n '3,$p' | sort > "$T/r-$1"
  cut -f2 "$T/k-$1.res" | cut -d' ' -f1-2 > "$T/inv-$1"
}
statut() { # nom code : statut(s) du code dans le diagnostic, uniques, ou absent
  local s; s=$(sed -n "s/^$2=//p" "$T/r-$1" | sort -u | paste -sd, -); echo "${s:-absent}"
}
{
  echo "# ivpol.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), dépôt $(git -C "$here" rev-parse --short=8 HEAD), script $(sha256sum < "$0" | cut -c1-16), main.go $(sha256sum < "$here/main.go" | cut -c1-16)"
  ip link set lo up
  attendu "réseau du banc : interfaces" "$(ip -o link | wc -l)" 1
  attendu "réseau du banc : routes de la table principale" "$(ip route show table main | wc -l)" 0
  attendu "kyverno : version (mise.toml)" "$(kyverno version 2> /dev/null | sed -n 's/^Version: //p')" 1.19.2
  echo "cosign : $(cosign version 2>&1 | sed -n 's/^GitVersion: *//p') ; oras : $(oras version 2>&1 | sed -n 's/^Version: *//p')"
  for v in 29 30; do
    cmp -s "$here/main.go" "$C/src$v/cmd/banc-signature/main.go" && echo "src$v : commit $(git -C "$C/src$v" rev-parse HEAD), main.go identique, binaire $(sha256sum < "$C/sig/banc-signature$v" | cut -c1-16)" \
      || { echo "KO   src$v : main.go différent de celui du dépôt"; ko=$((ko + 1)); }
  done
  echo "cas : $CAS, ${#TRS[@]} TaskRuns, PipelineRun ${UID_PR:0:8}… ; source attendue : $URL @ ${REV:0:12}…"
  "$C/sig/banc-signature30" cle "$T/cle"; "$C/sig/banc-signature30" cle "$T/autre"
  attendu "deux clés jetables" "$(cmp -s "$T/cle/cosign.pub" "$T/autre/cosign.pub" && echo identiques || echo distinctes)" distinctes
  "$C/sig/banc-signature30" serve "$T/port" & SERVE=$!
  for _ in $(seq 50); do [ -s "$T/port" ] && break; read -rt 0.1 < /dev/zero || true; done
  REG=127.0.0.1:$(cat "$T/port")
  printf '{}' > "$T/vide.json"; oras blob push --plain-http "$REG/horodatage/bundles" "$T/vide.json" > /dev/null 2>&1
  # politiques
  sed "s#$HOTE#$REG#g" "$P08/politique/porte/taches.yml" > "$T/taches.yml"
  sed "s#sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b#$NUL#" "$T/taches.yml" > "$T/taches-temoin.yml"
  attendu "noms remplacés dans taches.yml ; témoin : lignes changées" "$(diff "$P08/politique/porte/taches.yml" "$T/taches.yml" | grep -c '^>') $(diff "$T/taches.yml" "$T/taches-temoin.yml" | grep -c '^>')" "15 1"
  rendre "$T/rc-diag.yaml" "$T/cle/cosign.pub" "$T/taches.yml" diagnostic
  rendre "$T/rc-decision.yaml" "$T/cle/cosign.pub" "$T/taches.yml" decision
  rendre "$T/rc-temoin.yaml" "$T/cle/cosign.pub" "$T/taches-temoin.yml" diagnostic
  rendre "$T/rc-autre.yaml" "$T/autre/cosign.pub" "$T/taches.yml" diagnostic
  sed -n '/^ivpol() {/,/^}/p' "$P08/commun.sh" > "$T/c9-fonction.sh"
  attendu "contrôle 9 : fonction ivpol lue dans commun.sh" "$(head -1 "$T/c9-fonction.sh" | cut -c1-7) $(tail -1 "$T/c9-fonction.sh")" "ivpol() }"
  cp "$T/cle/cosign.pub" "$T/c9/chains-cle-publique.pem"; cp "$T/autre/cosign.pub" "$T/c9-autre/chains-cle-publique.pem"
  ( REG_HOTE=$REG R=$T/c9; . "$T/c9-fonction.sh"; ivpol horodatage/bundles "" c9 ) > "$T/c9.yaml"
  ( REG_HOTE=$REG R=$T/c9-autre; . "$T/c9-fonction.sh"; ivpol horodatage/bundles "" c9 ) > "$T/c9-autre.yaml"
  attendu "contrôle 9 : sans tsaCertChain, règle C9" "$(grep -c tsaCertChain "$T/c9.yaml") $(grep -c 'C9 :' "$T/c9.yaml")" "0 1"
  for v in 29 30; do
    echo "## v$v : signature et bundles"
    B=$C/sig/banc-signature$v
    D=$("$B" image "$REG" builds/sample-app); echo "image du banc : ${D:0:19}…"; echo "$D" > "$T/digest-$v"
    "$B" signer "$REG" "$T/cle" "$HOTE" "$ANCIEN" "$D" "$PR" "${TRS[@]}" > "$T/sign-$v.json" 2> "$T/zap-$v.log"; attendu "v$v signer, code" "$?" 0
    attendu "v$v erreurs de Sign" "$(jq '[.sign[] | select(. != "")] | length' "$T/sign-$v.json")" 0
    publier "$v" "$D"
  done
  for v in 29 30; do
    I=$REG/builds/sample-app@$(cat "$T/digest-$v")
    echo "## v$v : reserve-c"
    diag "rc-$v" "$T/rc-diag.yaml" "$I"; attendu "v$v diagnostic : provenance retenue" "$(cat "$T/inv-rc-$v")" "DIAG $UID_PR"
    echo "règles en échec : $(grep '=ko$' "$T/r-rc-$v" | sed 's/=ko$//' | sort -u | tr '\n' ' ')"
    echo "avertissements : $(grep -c '=avert$' "$T/r-rc-$v")"
    appliquer "rcd-$v" "$T/rc-decision.yaml" "$I"
    echo "décision : $(cut -c1-400 "$T/k-rcd-$v.res")"
    echo "## v$v : témoin trusted_task (digest de publier-image retiré de la liste revue)"
    diag "tt-$v" "$T/rc-temoin.yaml" "$I"; attendu "v$v témoin tt : provenance retenue" "$(cat "$T/inv-tt-$v")" "DIAG $UID_PR"
    echo "règles en échec : $(grep '=ko$' "$T/r-tt-$v" | sed 's/=ko$//' | sort -u | tr '\n' ' ')"
    echo "## v$v : témoin de clé (autre clé publique)"
    diag "autre-$v" "$T/rc-autre.yaml" "$I"; echo "provenance retenue : $(cat "$T/inv-autre-$v")"
    echo "## v$v : contrôle 9"
    appliquer "c9-$v" "$T/c9.yaml" "$I"; echo "c9 : $(cut -c1-200 "$T/k-c9-$v.res")"
    appliquer "c9a-$v" "$T/c9-autre.yaml" "$I"; echo "c9, autre clé : $(cut -c1-200 "$T/k-c9a-$v.res")"
  done
  echo "## état des règles de reserve-c (v29 | v30)"
  cut -d= -f1 "$T/r-rc-29" "$T/r-rc-30" | sort -u > "$T/regles"
  while read -r c; do printf '  %-62s %-8s | %s\n' "$c" "$(statut rc-29 "$c")" "$(statut rc-30 "$c")"; done < "$T/regles"
  echo "## contrôles"
  attendu "reserve-c v29 : règles en échec" "$(grep -c '=ko$' "$T/r-rc-29")" 0
  attendu "reserve-c v30 : règles en échec" "$(grep '=ko$' "$T/r-rc-30" | sed 's/=ko$//' | sort -u | tr '\n' ' ')" "$(tr ' ' '\n' <<< "$ECART" | sort | tr '\n' ' ')"
  attendu "reserve-c, décision (v29 | v30)" "$(cut -f1 "$T/k-rcd-29.res") | $(cut -f1 "$T/k-rcd-30.res")" "pass | fail"
  attendu "reserve-c v30, motif de la décision" "$(cut -f2 "$T/k-rcd-30.res" | sed 's/^reserve-c : //' | tr ' ' '\n' | sed 's/=ko$//' | sort -u | tr '\n' ' ')" "$(tr ' ' '\n' <<< "$ECART" | sort | tr '\n' ' ')"
  attendu "témoin tt : trusted_task.trusted (v29 | v30)" "$(statut tt-29 trusted_task.trusted) | $(statut tt-30 trusted_task.trusted)" "ko | ok"
  attendu "témoin tt v29 : seul code de plus" "$(comm -13 <(grep '=ko$' "$T/r-rc-29" | sort -u) <(grep '=ko$' "$T/r-tt-29" | sort -u) | tr '\n' ' ')" "trusted_task.trusted=ko "
  attendu "témoin tt v30 : mêmes échecs que reserve-c v30" "$(diff <(grep '=ko$' "$T/r-rc-30" | sort -u) <(grep '=ko$' "$T/r-tt-30" | sort -u) | grep -c '^[<>]')" 0
  for v in 29 30; do
    attendu "témoin de clé v$v : signatures (image | provenance)" "$(statut "autre-$v" builtin.image.signature_check) | $(statut "autre-$v" builtin.attestation.signature_check)" "ko | ko"
  done
  attendu "contrôle 9 (v29 | v30)" "$(cut -f1 "$T/k-c9-29.res") | $(cut -f1 "$T/k-c9-30.res")" "pass | pass"
  attendu "contrôle 9, autre clé (v29 | v30)" "$(cut -f1 "$T/k-c9a-29.res") | $(cut -f1 "$T/k-c9a-30.res")" "fail | fail"
  kill "$SERVE"; wait "$SERVE" 2> /dev/null; SERVE=
  echo "## bilan : $ko KO, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ "$ko" -eq 0 ]
} 2>&1 | sed -u "s#$HOME#~#g; /jeton\|token/I c\[ligne masquée : motif jeton|token]" | tee "$LOG"
exit "${PIPESTATUS[0]}"
