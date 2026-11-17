#!/usr/bin/env bash
# Brique 08 : Kyverno v1.20.0 change-t-il le choix de la provenance jugée (réserve de la décision C, ADR 0000, mesurée en J8 sur
# Kyverno 1.19.2) ? Relevé demandé par le propriétaire le 17/11/2026 (« Je parlais du problème vs conforma », puis « Oui,
# archive-le »). Lecture publique seulement (API GitHub) : rien d'installé, rien d'écrit chez les projets tiers, rien lu ni écrit
# dans le cluster, Zot ou les VM. Sources téléchargées dans le cache, lues par grep, jamais exécutées.
# Ce relevé est une LECTURE du code : il ne mesure aucun verdict de Kyverno (les 6 cas de sélection ne sont pas rejoués).
#
# Premier passage (17/11/2026, 19:06:29 UTC) : deux défauts du script, pas de la lecture (404 recopié par blob ; motif cherché
# sur une ligne alors que le commentaire en tient deux) ; archivé sous resultats/kyverno-120-selection-passage1.log.
#
# Usage (racine du dépôt) : poc/bricks/08-trust-plane/kyverno-120-selection.sh   (journal : resultats/kyverno-120-selection.log)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
J=poc/bricks/08-trust-plane/resultats/kyverno-120-selection.log
C=$HOME/.cache/supply-chain-poc/08/kyverno-120-selection
R=repos/kyverno/kyverno
CI=pkg/image/verifiers/ivpol/cosign
N18049=edd8b239e393            # « fix(imageverify): extract newest attestation for ImageValidatingPolicy »
export GH_PAGER=
rm -rf -- "${C:?}" && mkdir -p "$C" || exit 1
ko=0
ok() { echo "OK   $*"; }
kof() { echo "KO   $*"; ko=1; }
attendu() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else kof "$1 : obtenu « $2 », attendu « $3 »"; fi; }
source_de() { # dépôt chemin ref fichier-local : contenu décodé, ou fichier absent si 404
  gh api "repos/$1/contents/$2?ref=$3" --jq .content 2>/dev/null | base64 -d > "$4" 2>/dev/null || rm -f -- "$4"
  [ -s "$4" ] || rm -f -- "$4"
}
blob() { local x; x=$(gh api "$R/contents/$1?ref=$2" --jq .sha 2>/dev/null) && [[ $x =~ ^[0-9a-f]{40}$ ]] && echo "$x" || echo absent; }
contient() { if [[ -f $2 && $(<"$2") == *"$3"* ]]; then ok "$1"; else kof "$1 (motif absent : $3)"; fi; }
compte() { grep -c -E -- "$2" "$1" 2>/dev/null || true; }
inclus() { gh api "$R/compare/$1...$2" --jq .status 2>/dev/null || echo illisible; }   # behind/identical : $2 est dans $1

{
echo "# kyverno-120-selection.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "## releases (lecture publique)"
gh api "$R/releases" --jq '.[0:3][] | "\(.tag_name) publiée \(.published_at), préversion \(.prerelease)"'
attendu "v1.20.0 préversion" "$(gh api "$R/releases/tags/v1.20.0" --jq .prerelease)" false
echo "épinglé au dépôt : $(grep -E '^"aqua:kyverno/kyverno"' mise.toml)"

echo "## commit $N18049 (sélection de l'attestation la plus récente pour l'ImageValidatingPolicy)"
echo "titre : $(gh api "$R/commits/$N18049" --jq '.commit.message | split("\n")[0]')"
attendu "présent dans v1.20.0 (compare v1.20.0...$N18049)" "$(inclus v1.20.0 $N18049)" behind
attendu "absent de v1.19.2 (compare v1.19.2...$N18049)" "$(inclus v1.19.2 $N18049)" diverged

echo "## $CI/timestamp.go"
attendu "timestamp.go à v1.19.2" "$(blob $CI/timestamp.go v1.19.2)" absent
echo "blob à v1.20.0 : $(blob $CI/timestamp.go v1.20.0)"
source_de kyverno/kyverno "$CI/timestamp.go" v1.20.0 "$C/timestamp-v1.20.0.go"
T=$C/timestamp-v1.20.0.go
if [ -f "$T" ]; then
  contient "fonction selectNewestAttestation" "$T" 'func selectNewestAttestation(candidates []verifiedCandidate, predicateType string)'
  contient "1. date vérifiée du bundle, si tous les candidats en ont une" "$T" 'if allHaveBundle {'
  contient "2. sinon date de l'énoncé signé, si tous en ont une" "$T" 'if allHaveStatement {'
  contient "3. sinon refus (« unable to determine newest »)" "$T" 'unable to determine newest'
  contient "à date égale : départage par les octets du contenu" "$T" 'return bytes.Compare(candidates[i].payload, candidates[j].payload) > 0'
  contient "clés de date de l'énoncé : finishedOn" "$T" '"finishedOn",'
  contient "clés lues aussi sous runDetails.metadata" "$T" 'predicate["runDetails"].(map[string]any)'
  contient "date RFC 3161 du bundle seulement avec un TrustedMaterial" "$T" 'if !hasBundleTS && cOpts.TrustedMaterial != nil {'
  attendu "mentions de PipelineRun (aucun filtre par type d'exécution)" "$(compte "$T" '[Pp]ipeline[Rr]un')" 0
else kof "timestamp.go illisible à v1.20.0"; fi

echo "## $CI/verifier.go"
for v in v1.19.2 v1.20.0; do
  echo "blob à $v : $(blob $CI/verifier.go $v)"
  source_de kyverno/kyverno "$CI/verifier.go" $v "$C/verifier-$v.go"
done
attendu "appels de selectNewestAttestation à v1.19.2" "$(compte "$C/verifier-v1.19.2.go" 'selectNewestAttestation\(')" 0
attendu "appels de selectNewestAttestation à v1.20.0 (par attestor, puis entre attestors)" "$(compte "$C/verifier-v1.20.0.go" 'selectNewestAttestation\(')" 2
contient "TrustedMaterial nil sur le chemin rapide des attestors à clé (commentaire du code)" "$C/verifier-v1.20.0.go" 'skipSigstoreInfra fast path for key/cert attestors'

contient "un seul candidat : retenu tel quel" "$T" 'if len(candidates) == 1 {'
attendu "dossier cosign : même arbre à v1.20.0 et au main du 14/11 (b2e65e2, reproduction du plantage TSA)" \
  "$(gh api "$R/contents/pkg/image/verifiers/ivpol?ref=v1.20.0" --jq '.[]|select(.name=="cosign")|.sha')" \
  "$(gh api "$R/contents/pkg/image/verifiers/ivpol?ref=b2e65e2fa88f8ff8bfb0a6351712433d6b14796d" --jq '.[]|select(.name=="cosign")|.sha')"

echo "## dates vérifiées remontées par cosign et sigstore-go (versions du go.mod de v1.20.0)"
source_de kyverno/kyverno go.mod v1.20.0 "$C/go.mod-v1.20.0"
vc=$(awk '$1=="github.com/sigstore/cosign/v3"{print $2}' "$C/go.mod-v1.20.0"); vs=$(awk '$1=="github.com/sigstore/sigstore-go"{print $2}' "$C/go.mod-v1.20.0")
echo "cosign $vc ; sigstore-go $vs"
source_de sigstore/cosign pkg/cosign/verify.go "$vc" "$C/cosign-verify.go"
contient "cosign : sans journal ni horodatage signé, une clé (SigVerifier) prend WithNoObserverTimestamps, pas WithCurrentTime" "$C/cosign-verify.go" \
  "$(printf '%s\n' '	if co.IgnoreTlog && !co.UseSignedTimestamps {' '		if co.SigVerifier == nil {' '			verifierOptions = append(verifierOptions, verify.WithCurrentTime())' '		} else {' '			verifierOptions = append(verifierOptions, verify.WithNoObserverTimestamps())')"
source_de sigstore/sigstore-go pkg/verify/signed_entity.go "$vs" "$C/sigstore-go-signed_entity.go"
contient "sigstore-go : date « CurrentTime » ajoutée seulement sous WithCurrentTime" "$C/sigstore-go-signed_entity.go" \
  "$(printf '%s\n' '	if v.config.useCurrentTime {' '		// use current time to verify certificate if no signed timestamps are provided' '		verifiedTimestamps = append(verifiedTimestamps, TimestampVerificationResult{Type: "CurrentTime", URI: "", Timestamp: time.Now()})')"

echo "## fonctions CEL de l'ImageValidatingPolicy (pkg/cel/libs/imageverify/lib.go)"
for v in v1.19.2 v1.20.0; do
  source_de kyverno/kyverno pkg/cel/libs/imageverify/lib.go $v "$C/lib-$v.go"
  echo "$v : $(grep -o -E '"(verifyImageSignatures|verifyAttestationSignatures|getImageData|extractPayload)"' "$C/lib-$v.go" | sort -u | tr -d '"' | tr '\n' ' ')"
done
attendu "extractPayload à v1.20.0 : (image, attestation) → une valeur" "$(grep -A2 -F '"extractPayload",' "$C/lib-v1.20.0.go" | sed -n 2p | tr -d '\t')" '[]*cel.Type{cel.StringType, cel.StringType},'

echo "## sdk (imagedataloader) : une provenance par type de prédicat"
for v in v1.19.2 v1.20.0; do
  source_de kyverno/kyverno go.mod $v "$C/go.mod-$v"
  s=$(awk '$1=="github.com/kyverno/sdk"{print $2}' "$C/go.mod-$v"); c=${s##*-}
  source_de kyverno/sdk extensions/imagedataloader/loader.go "$c" "$C/loader-$c.go"
  echo "$v : github.com/kyverno/sdk $s"
  attendu "$v : AddVerifiedIntotoPayloads écrase par type" "$(compte "$C/loader-$c.go" 'i\.verifiedIntotoPayloads\[predicateType\] = data')" 1
done

L=$C/loader-$c.go
contient "v1.20.0 : branche Referrer de GetPayload, une seule donnée (descs[0])" "$L" 'b, _, err = i.FetchReferrerData(descs[0])'
contient "politique reserve_c : attestation in-toto de provenance SLSA v1" poc/bricks/08-trust-plane/politique/reserve-c/ivpol.tmpl.yaml \
  "$(printf '%s\n' '      intoto:' '        type: https://slsa.dev/provenance/v1')"

echo "## PR 18010 (même idée, autre moteur)"
f=$(gh api "$R/pulls/18010/files" --jq '.[].filename' | sort | tr '\n' ' ')
echo "fichiers : $f"
attendu "fichiers hors de pkg/engine/" "$(tr ' ' '\n' <<<"$f" | grep -v -c -E '^(pkg/engine/|$)')" 0
m=$(gh api "$R/pulls/18010" --jq .merge_commit_sha)
attendu "fusion de 18010 dans v1.20.0" "$(inclus v1.20.0 "$m")" behind
attendu "fusion de 18010 absente de v1.19.2" "$(inclus v1.19.2 "$m")" diverged

echo "## nos politiques (dépôt)"
attendu "déclarations ClusterPolicy dans la 08 et le banc kyverno-seul" \
  "$(grep -rh -E '^kind: ClusterPolicy$' poc/bricks/08-trust-plane poc/benchmarks/kyverno-seul 2>/dev/null | wc -l)" 0
echo "ImageValidatingPolicy : $(grep -rh -E '^kind: ImageValidatingPolicy$' poc/bricks/08-trust-plane poc/benchmarks/kyverno-seul 2>/dev/null | wc -l) déclarations"
echo "## bilan : $([ $ko = 0 ] && echo tenu || echo 'KO présent')"
[ "$ko" = 0 ]
} 2>&1 | tee "$J"
exit "${PIPESTATUS[0]}"
