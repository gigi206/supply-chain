#!/usr/bin/env bash
# Brique 08 : Fulcio et Rekor sont-ils utiles au PoC ? Évaluation à sec demandée par le propriétaire le 08/11/2026 (« On ne peut pas
# faire des évaluations sur ces outils tout de suite ? »). Lecture publique seulement (API GitHub, API Scorecard) : rien d'installé,
# rien d'écrit chez les projets tiers, rien lu ni écrit dans le cluster, Zot ou les VM. Sources lues, jamais exécutées.
#   kyverno   état des tickets des deux défauts de Kyverno 1.19.2 mesurés en J5 (#17109, #18054, correctifs #17217 et #16048) ;
#             SHA de blob des fichiers de vérification par tag (v1.19.2, v1.20.0-rc.1, main) ; lignes clés extraites
#   sources   ce qu'exigerait une vérification avec journal : initialisation TUF de Kyverno, options par défaut du client TUF de
#             sigstore-go, client de transparence de Chains v0.29.9 et rangement de la preuve dans l'attestation
#   releves   santé de sigstore/rekor, sigstore/rekor-tiles et sigstore/fulcio selon les critères du doc 04 (§1), même méthode que
#             poc/bricks/05-rpm-mock/sante.sh ; fichiers de signature et de provenance des dernières releases
#
# Usage (racine du dépôt) : poc/bricks/08-trust-plane/sante-sigstore.sh <étape>…   (journal : resultats/sante-sigstore-<étape>.log)
set -uo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
R=$here/resultats
T=$HOME/.cache/supply-chain-poc/08/sante-sigstore
DEPUIS=2026-08-10T00:00:00Z   # 90 jours avant le relevé du 08/11/2026
UN_AN=2025-11-08
GH=$(command -v gh)
gh() { env -u GITHUB_TOKEN "$GH" "$@" </dev/null; }
brut() { gh api "repos/$1/contents/$2?ref=$3" -H 'Accept: application/vnd.github.raw'; }   # $1 dépôt, $2 chemin, $3 réf
mkdir -p "$R" "$T"

etape_kyverno() {
  local n t f d=pkg/image/verifiers/ivpol/cosign
  echo "## tickets (relevé à $(date -u +%H:%M:%S) UTC)"
  for n in 17109 18054 17217 16048; do
    gh api "repos/kyverno/kyverno/issues/$n" --jq '"#\(.number) \(if .pull_request then "PR" else "issue" end) \(.state), fusionnée \(.pull_request.merged_at // "non"), mise à jour \(.updated_at) : \(.title)"'
  done
  gh api repos/kyverno/kyverno/pulls/17217 --jq '"PR #17217 : base \(.base.ref), brouillon \(.draft), mergeable_state \(.mergeable_state), tête \(.head.sha[0:12])"'
  echo "## releases (relevé à $(date -u +%H:%M:%S) UTC)"
  gh api repos/kyverno/kyverno/releases --jq '.[0:4][] | "\(.tag_name) du \(.published_at[0:10]), préversion \(.prerelease)"'
  echo "## SHA de blob sous $d"
  for t in v1.19.2 v1.20.0-rc.1 main; do
    echo "### $t (relevé à $(date -u +%H:%M:%S) UTC)"
    gh api "repos/kyverno/kyverno/contents/$d?ref=$t" --jq '.[] | select(.name | test("^(opts|verifier|timestamp)\\.go$")) | "  \(.sha) \(.name)"'
    mkdir -p "$T/kyverno-$t"
    for f in opts.go verifier.go; do brut kyverno/kyverno "$d/$f" "$t" > "$T/kyverno-$t/$f"; done
  done
  for t in v1.19.2 v1.20.0-rc.1 main; do
    echo "## lignes clés, $t"
    echo "- raccourci sans infrastructure Sigstore (clé et insecureIgnoreTlog) :"
    grep -n -E 'skipSigstoreInfra :?= ' "$T/kyverno-$t/opts.go" | sed 's/^/    opts.go:/'
    echo "- chaîne TSA ajoutée seulement si un matériel de confiance existe (défaut du plantage, J5) :"
    grep -n -E 'if opts\.TrustedMaterial != nil && len\(roots\) > 0' "$T/kyverno-$t/opts.go" | sed 's/^/    opts.go:/'
    echo "- chemin des attestations : lecture de insecureIgnoreTlog dans VerifyAttestationSignature (#17109) :"
    awk '/^func \(v \*Verifier\) VerifyAttestationSignature/{f=1} f && /^}/{f=0} f' "$T/kyverno-$t/verifier.go" > "$T/attestation.go"
    echo "    longueur de la fonction : $(wc -l < "$T/attestation.go") lignes ; mentions de IgnoreTlog : $(grep -c -E 'IgnoreTlog|ignoreTlog' "$T/attestation.go" || true)"
    grep -n -E 'cosign\.VerifyImageAttestations' "$T/attestation.go" | sed 's/^/    dans la fonction, ligne /'
  done
  echo "## non évalué"
  echo "- v1.20.0-rc.1 ajoute timestamp.go (tri des attestations par horodatage signé) : touche le constat « Kyverno ne choisit pas la provenance jugée », non lu ici"
}

etape_sources() {
  local d=pkg/image/verifiers/ivpol/cosign v
  mkdir -p "$T/src"
  echo "## Kyverno v1.19.2 : vérification avec journal (relevé à $(date -u +%H:%M:%S) UTC)"
  brut kyverno/kyverno "$d/opts.go" v1.19.2 > "$T/src/opts.go"
  echo "- initialisation TUF appelée hors du raccourci, avant la racine de confiance en ligne (resolveTrustedMaterial) :"
  grep -n -E 'if !skipSigstoreInfra \{|trust, err = initTUFAndFetch|resolveTrustedMaterial\(att, trust\.trustedRoot\)|mirror := tuf\.DefaultRemoteRoot|tufInitializeFn\(ctx, mirror, rootBytes\)|opts := sigstoreTuf\.DefaultOptions\(\)\.WithContext\(ctx\)|client\.GetTarget\("trusted_root\.json"\)' "$T/src/opts.go" | sed 's/^/    opts.go:/'
  echo "- clé publique d'un Rekor auto-hébergé acceptée sans TUF (getRekor) :"
  grep -n -E 'rekor URL must be provided|ctlog\.RekorPubKey == ""|AddTransparencyLogPubKey\(\[\]byte\(ctlog\.RekorPubKey\)' "$T/src/opts.go" | sed 's/^/    opts.go:/'
  v=$(brut kyverno/kyverno go.mod v1.19.2 | awk '$1 == "github.com/sigstore/sigstore-go" {print $2}')
  echo "## sigstore-go $v (go.mod de Kyverno v1.19.2) : options par défaut du client TUF"
  brut sigstore/sigstore-go pkg/tuf/options.go "$v" > "$T/src/options.go"
  brut sigstore/sigstore-go pkg/tuf/client.go "$v" > "$T/src/client.go"
  grep -n -E 'DefaultMirror = |CacheValidity int|ForceCache bool' "$T/src/options.go" | sed 's/^/    options.go:/'
  awk '/^func DefaultOptions/{f=1} f; f && /^}/{exit}' "$T/src/options.go" | grep -n -E 'CacheValidity|ForceCache|RepositoryBaseURL' | sed 's/^/    dans DefaultOptions, ligne /'
  echo "- mise à jour en ligne sauf cache forcé ou encore valide :"
  grep -n -E 'if c\.opts\.ForceCache|else if c\.opts\.CacheValidity > 0|return c\.Refresh\(\)' "$T/src/client.go" | sed 's/^/    client.go:/'
  echo "## Tekton Chains v0.29.9 : client de transparence"
  brut tektoncd/chains go.mod v0.29.9 | grep -E '^\s*github\.com/sigstore/(rekor|rekor-tiles|cosign/v[23]|sigstore-go) ' | sed 's/^/    go.mod :/'
  brut tektoncd/chains pkg/chains/rekor.go v0.29.9 > "$T/src/rekor.go"
  grep -n -E '"github\.com/sigstore/rekor[^"]*"|func \(r \*rekor\) UploadTlog' "$T/src/rekor.go" | sed 's/^/    rekor.go:/'
  echo "- preuve rangée dans l'attestation (.att en dsse, entrée intégrée en sigstore-bundle) :"
  brut tektoncd/chains pkg/chains/storage/oci/attestation.go v0.29.9 > "$T/src/attestation.go"
  grep -n -E 'static\.WithBundle\(req\.Bundle\.RekorBundle\)|MakeNewBundle\(pubKey, req\.Bundle\.RekorEntry' "$T/src/attestation.go" | sed 's/^/    attestation.go:/'
}

etape_releves() {
  local r v
  printf 'Rekor (v1)\tsigstore/rekor\tsignature\tnon\nRekor v2 (rekor-tiles)\tsigstore/rekor-tiles\tsignature\tnon\nFulcio\tsigstore/fulcio\tsignature\tnon\n' > "$T/projets.tsv"
  "$repo/tools/health/scorecard.sh" "$T/projets.tsv"
  for r in sigstore/rekor sigstore/rekor-tiles sigstore/fulcio; do
    echo "## $r (relevé à $(date -u +%H:%M:%S) UTC)"
    gh api "repos/$r" --jq '"nom final \(.full_name), archivé \(.archived), licence \(.license.spdx_id), dernier push \(.pushed_at[0:10])"'
    v=$(gh api "repos/$r/releases/latest" --jq '"\(.tag_name) du \(.published_at[0:10])"' 2>/dev/null) || v=aucune
    echo "dernière release : $v"
    echo "releases récentes : $(gh api "repos/$r/releases?per_page=6" --jq '[.[] | "\(.tag_name) (\(.published_at[0:10]))"] | join(", ")')"
    echo "fichiers de la dernière release liés aux signatures et à la provenance :"
    gh api "repos/$r/releases/latest" --jq '[.assets[].name | select(test("\\.(sig|pem|crt|bundle|sigstore(\\.json)?|intoto\\.jsonl|att)$|provenance|checksums|sbom"; "i"))] | if length == 0 then "  aucun" else .[] | "  " + . end' 2>/dev/null || echo "  aucune release"
    gh api "repos/$r/commits?since=$DEPUIS&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), (.commit.author.email | split("@")[1]), (.author.type // "-")] | @tsv' > "$T/commits.tsv"
    echo "commits depuis $DEPUIS : $(wc -l < "$T/commits.tsv") ; auteurs humains les plus actifs (compte, domaine de l'adresse) :"
    awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1 "\t" $2}' "$T/commits.tsv" | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
    echo "fusionneurs des 100 dernières PR : $(gh pr list --repo "$r" --state merged --limit 100 --json mergedBy --jq '[.[] | .mergedBy.login] | group_by(.) | map("\(.[0]) \(length)") | join(", ")')"
    echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null | grep -x SECURITY.md || echo "absent du dépôt (politique de l'organisation sigstore non relue)")"
    echo "avis publiés : $(gh api "repos/$r/security-advisories?per_page=100" --jq 'length') ; depuis un an : $(gh api "repos/$r/security-advisories?per_page=100" --jq "[.[] | select(.published_at > \"$UN_AN\")] | length")"
    gh api "repos/$r/security-advisories?per_page=100" --jq '.[0:4][] | "  \(.ghsa_id) \(.published_at[0:10]) \(.severity) \(.summary)"'
  done
}

# Ajout du 08/11/2026 vers 15:00 UTC, après les trois premiers journaux, sur relecture du conseiller : trous de preuve comblés dans un
# journal à part (les trois premiers ne sont pas réécrits).
etape_complements() {
  local t r d=pkg/image/verifiers/ivpol/cosign
  mkdir -p "$T/comp"
  for t in v1.19.2 v1.20.0-rc.1; do
    echo "## Kyverno $t : ordre des appels dans checkOptions (relevé à $(date -u +%H:%M:%S) UTC)"
    brut kyverno/kyverno "$d/opts.go" "$t" > "$T/comp/opts.go"
    awk '/^func checkOptions/{f=1} f && /^}/{exit} f' "$T/comp/opts.go" > "$T/comp/check.go"
    echo "  checkOptions : $(wc -l < "$T/comp/check.go") lignes ; lignes relatives au début de la fonction :"
    grep -n -E 'if !skipSigstoreInfra \{|trust, err = initTUFAndFetch|return nil, err$|getRekor\(ctx, att\.CTLog|resolveTrustedMaterial\(att' "$T/comp/check.go" | head -8 | sed 's/^/    /'
    brut kyverno/kyverno "$d/verifier.go" "$t" > "$T/comp/verifier.go"
    for f in VerifyImageSignature VerifyAttestationSignature; do
      awk -v f="$f" '$0 ~ "^func \\(v \\*Verifier\\) " f "\\(" {g=1} g && /^}/{g=0} g' "$T/comp/verifier.go" > "$T/comp/f.go"
      echo "  $f : $(wc -l < "$T/comp/f.go") lignes, mentions de IgnoreTlog ou ignoreTlog : $(grep -c -E 'IgnoreTlog|ignoreTlog' "$T/comp/f.go" || true)"
    done
  done
  echo "## politique de sécurité de l'organisation sigstore (relevé à $(date -u +%H:%M:%S) UTC)"
  gh api repos/sigstore/.github/contents/SECURITY.md --jq '"SECURITY.md de sigstore/.github : présent, \(.size) octets"' 2>/dev/null || echo "SECURITY.md de sigstore/.github : absent"
  brut sigstore/.github SECURITY.md HEAD 2>/dev/null | grep -i -E 'report|disclos|security@|advisor|embargo|days' | head -6 | cut -c1-200 | sed 's/^/  /'
  echo "## commits depuis $DEPUIS, humains et robots séparés"
  for r in sigstore/rekor sigstore/rekor-tiles sigstore/fulcio google/trillian; do
    gh api "repos/$r/commits?since=$DEPUIS&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), (.author.type // "-")] | @tsv' > "$T/comp/c.tsv"
    echo "  $r : $(wc -l < "$T/comp/c.tsv") commits, dont robots $(awk -F'\t' '$2 == "Bot" || $1 ~ /bot/' "$T/comp/c.tsv" | wc -l), humains $(awk -F'\t' '!($2 == "Bot" || $1 ~ /bot/)' "$T/comp/c.tsv" | wc -l)"
  done
  echo "## Rekor v1 : état annoncé et dépendances du serveur (relevé à $(date -u +%H:%M:%S) UTC)"
  gh api repos/sigstore/rekor/readme -H 'Accept: application/vnd.github.raw' > "$T/comp/README.md"
  grep -n -i -E 'maintenance mode|rekor-tiles codebase|Trillian-Tessera' "$T/comp/README.md" | cut -c1-200 | sed 's/^/  README.md:/'
  brut sigstore/rekor go.mod HEAD | grep -n -E 'google/trillian |go-sql-driver/mysql |redis/go-redis/v9 ' | sed 's/^/  go.mod:/'
  echo "## Chains : client de transparence sur main (relevé à $(date -u +%H:%M:%S) UTC)"
  brut tektoncd/chains go.mod main | grep -E '^\s*github\.com/sigstore/(rekor|rekor-tiles) ' | sed 's/^/  go.mod (main) :/'
  echo "## google/trillian (dépendance du serveur Rekor v1, relevé à $(date -u +%H:%M:%S) UTC)"
  printf 'Trillian\tgoogle/trillian\tsignature\tnon\n' > "$T/comp/projets.tsv"
  "$repo/tools/health/scorecard.sh" "$T/comp/projets.tsv" | tail -1
  gh api repos/google/trillian --jq '"archivé \(.archived), licence \(.license.spdx_id), dernier push \(.pushed_at[0:10])"'
  echo "dernière release : $(gh api repos/google/trillian/releases/latest --jq '"\(.tag_name) du \(.published_at[0:10])"' 2>/dev/null || echo aucune)"
  echo "fusionneurs des 100 dernières PR : $(gh pr list --repo google/trillian --state merged --limit 100 --json mergedBy --jq '[.[] | .mergedBy.login] | group_by(.) | map("\(.[0]) \(length)") | join(", ")')"
  gh api repos/google/trillian/readme -H 'Accept: application/vnd.github.raw' | grep -n -i -E 'maintenance|tessera|deprecat' | head -5 | cut -c1-200 | sed 's/^/  README.md:/'
  echo "## limites"
  echo "- fichiers .sigstore.json des releases : présence relevée, signatures non vérifiées ; images des projets non relues"
  echo "- passage obligatoire par le TUF lu en v1.19.2 et v1.20.0-rc.1 seulement ; employeurs des fusionneurs non établis (adresses noreply)"
}

# Ajout du 08/11/2026 vers 15:10 UTC, questions du propriétaire : « Il y a donc un soucis si chains se base sur quelque chose en
# maintenance mode » et « pour Fulcio, si on met par exemple un keycloak ou autre ? ».
etape_fulcio() {
  mkdir -p "$T/fulcio"
  echo "## dépendance de notre Chains à Rekor v1 (relevé à $(date -u +%H:%M:%S) UTC)"
  echo "- transparence dans la configuration du dépôt (non relue dans le cluster) :"
  grep -n -E 'transparency' "$here/tekton/chains/chains-config.yaml" | sed 's/^/    tekton\/chains\/chains-config.yaml:/'
  echo "- dernière valeur relevée dans un rejeu archivé :"
  grep -H -n -E '^transparency\.enabled' "$R"/rejeu-*.log | sed "s#^$R/#    resultats/#" | tail -1
  echo "- client Rekor v1 compilé dans Chains (go.mod, v0.29.9 et main) :"
  for t in v0.29.9 main; do brut tektoncd/chains go.mod "$t" | grep -E '^\s*github\.com/sigstore/rekor ' | sed "s/^/    $t :/"; done
  echo "## Fulcio v1.9.1 : options du serveur (relevé à $(date -u +%H:%M:%S) UTC)"
  brut sigstore/fulcio cmd/app/serve.go v1.9.1 > "$T/fulcio/serve.go"
  brut sigstore/fulcio pkg/config/config.go v1.9.1 > "$T/fulcio/config.go"
  grep -n -E 'Flags\(\)\.String\("(ca|ct-log-url|kms-resource)"|if logURL := viper\.GetString\("ct-log-url"\); logURL != ""' "$T/fulcio/serve.go" | cut -c1-200 | sed 's/^/    serve.go:/'
  echo "- types d'émetteurs OIDC acceptés :"
  grep -n -E '^\s*IssuerType[A-Za-z]+ += "' "$T/fulcio/config.go" | sed 's/^/    config.go:/'
  echo "## Chains v0.29.9 : signataire Fulcio"
  brut tektoncd/chains pkg/chains/signing/x509/x509.go v0.29.9 > "$T/fulcio/x509.go"
  grep -n -E 'if cfg\.Signers\.X509\.FulcioEnabled|if cfg\.IdentityTokenFile != ""|FilesystemTokenPath = cfg\.IdentityTokenFile|tok, err = p\.Provide' "$T/fulcio/x509.go" | sed 's/^/    x509.go:/'
  brut tektoncd/chains pkg/config/config.go v0.29.9 | grep -n -E '"signers\.x509\.(fulcio\.[a-z]+|identity\.token\.file|tuf\.mirror\.url)"' | sed 's/^/    config.go:/'
  echo "## limites"
  echo "- non lus : le besoin de Rekor ou d'un horodatage pour vérifier un certificat Fulcio de courte durée dans Chains, ec et Kyverno ; Keycloak non audité (doc 04)"
}

# Ajout du 08/11/2026 vers 15:20 UTC, demande du propriétaire : « Vérifie d'abord en détails le code source de kyverno pour notre bug
# voir si c'est réellement un bug ». Chemin complet du plantage de J5 (clé, insecureIgnoreTlog, tsaCertChain, bundle au nouveau format).
etape_bogue_tsa() {
  local K=pkg/image/verifiers/ivpol/cosign c sg
  mkdir -p "$T/bogue"
  sg=$(brut kyverno/kyverno go.mod v1.19.2 | awk '$1 == "github.com/sigstore/sigstore-go" {print $2}')
  c=$(brut kyverno/kyverno go.mod v1.19.2 | awk '$1 == "github.com/sigstore/cosign/v3" {print $2}')
  echo "versions embarquées par Kyverno v1.19.2 (go.mod) : cosign $c, sigstore-go $sg"
  brut kyverno/kyverno "$K/opts.go" v1.19.2 > "$T/bogue/opts.go"
  brut kyverno/kyverno "$K/verifier.go" v1.19.2 > "$T/bogue/verifier.go"
  brut kyverno/kyverno "$K/opts_test.go" v1.19.2 > "$T/bogue/opts_test.go"
  brut sigstore/cosign pkg/cosign/verify.go "$c" > "$T/bogue/verify.go"
  brut sigstore/cosign pkg/cosign/verify_bundle.go "$c" > "$T/bogue/verify_bundle.go"
  brut sigstore/sigstore-go pkg/verify/tsa.go "$sg" > "$T/bogue/tsa.go"
  brut sigstore/sigstore-go pkg/verify/signed_entity.go "$sg" > "$T/bogue/signed_entity.go"
  echo "## 1. Kyverno v1.19.2, opts.go : clé et insecureIgnoreTlog donnent un TrustedMaterial nil, la chaîne TSA va dans les champs historiques (relevé à $(date -u +%H:%M:%S) UTC)"
  grep -n -E 'skipSigstoreInfra :?= |if !skipSigstoreInfra \{|opts\.TrustedMaterial = trustedMaterial|opts\.TSACertificate = leaves\[0\]|opts\.TSARootCertificates = roots|opts\.UseSignedTimestamps = true|if opts\.TrustedMaterial != nil && len\(roots\) > 0' "$T/bogue/opts.go" | sed 's/^/    opts.go:/'
  echo "## 2. Kyverno v1.19.2, verifier.go : un bundle au nouveau format part vers cosign.VerifyNewBundle"
  grep -n -E 'cOpts\.NewBundleFormat = len\(bundles\) > 0|cosign\.VerifyNewBundle\(ctx, &coCopy' "$T/bogue/verifier.go" | sed 's/^/    verifier.go:/'
  echo "## 3. Kyverno v1.19.2, tests : ce cas est voulu (« AirGapped »), mais aucun test ne vérifie un jeton avec une clé"
  grep -n -E '^func Test(CheckOptions_KeyBased_AirGapped|CheckOptions_Keyless_TSACertChainTrustedMaterial)|name: +"TSACertChain provided enables UseSignedTimestamps"|assert\.Nil\(t, opts\.TrustedMaterial\)|require\.NotNil\(t, opts\.TrustedMaterial\)' "$T/bogue/opts_test.go" | sed 's/^/    opts_test.go:/'
  echo "## 4. cosign $c : TrustedMaterial exclut les champs TSA historiques ; le chemin du nouveau format ne lit que TrustedMaterial"
  grep -n -E 'TrustedMaterial contains trusted metadata.*exclusive with|^type verifyTrustedMaterial struct|^	root\.TrustedMaterial$|vTrustedMaterial := &verifyTrustedMaterial\{TrustedMaterial: co\.TrustedMaterial\}|verifierOptions = append\(verifierOptions, verify\.WithSignedTimestamps\(1\)\)' "$T/bogue/verify.go" | cut -c1-200 | sed 's/^/    verify.go:/'
  grep -n -E 'coCopy\.verificationOptions\(\)|verify\.NewVerifier\(trustedMaterial|verifier\.Verify\(bundle' "$T/bogue/verify_bundle.go" | sed 's/^/    verify_bundle.go:/'
  echo "- champs historiques lus seulement par la vérification des jetons du format historique :"
  grep -n -E 'case co\.TSARootCertificates == nil && co\.TrustedMaterial == nil|TSACertificate: co\.TSACertificate|Roots: +co\.TSARootCertificates' "$T/bogue/verify.go" | sed 's/^/    verify.go:/'
  echo "## 5. sigstore-go $sg : appel sur le TrustedMaterial nil, seulement si un jeton est présent"
  grep -n -E 'if v\.config\.requireSignedTimestamps \{|VerifySignedTimestampWithThreshold\(entity, v\.trustedMaterial' "$T/bogue/signed_entity.go" | sed 's/^/    signed_entity.go:/'
  grep -n -E 'for _, timestamp := range signedTimestamps \{|timestampAuthorities := trustedMaterial\.TimestampingAuthorities\(\)' "$T/bogue/tsa.go" | sed 's/^/    tsa.go:/'
  echo "## 6. état actuel"
  for c in v3.1.4; do
    echo "- cosign $c (dernière release) : verifyTrustedMaterial sans garde sur TimestampingAuthorities :"
    brut sigstore/cosign pkg/cosign/verify.go "$c" | grep -n -E '^type verifyTrustedMaterial struct|^func \(v \*verifyTrustedMaterial\) [A-Za-z]+' | sed 's/^/    verify.go:/'
  done
  echo "- PR #16048 (relevé à $(date -u +%H:%M:%S) UTC), fichiers :"
  gh api repos/kyverno/kyverno/pulls/16048/files --jq '.[] | "    \(.filename)"'
  echo "## 7. documentation (kyverno/website, branche par défaut)"
  gh api repos/kyverno/website/contents/src/content/docs/docs/policy-types/image-validating-policy.mdx -H 'Accept: application/vnd.github.raw' | grep -n -E 'tsaCertChain:|insecureIgnoreTlog: false' | sed 's/^/    image-validating-policy.mdx:/'
}

# Ajout du 08/11/2026 vers 15:30 UTC, sur relecture du conseiller : compléments à bogue_tsa, journal à part (bogue_tsa n'est pas réécrit).
etape_bogue_tsa_complements() {
  local K=pkg/image/verifiers/ivpol/cosign t c sg f
  mkdir -p "$T/bogue2"
  echo "## 1. dépendances de Kyverno sur main et en v1.20.0-rc.1 (relevé à $(date -u +%H:%M:%S) UTC)"
  for t in v1.20.0-rc.1 main; do brut kyverno/kyverno go.mod "$t" | grep -E '^\s*github\.com/sigstore/(cosign/v3|sigstore-go) ' | sed "s/^/    $t :/"; done
  c=$(brut kyverno/kyverno go.mod main | awk '$1 == "github.com/sigstore/cosign/v3" {print $2}')
  sg=$(gh api repos/sigstore/sigstore-go/releases/latest --jq .tag_name)
  echo "- cosign $c (main de Kyverno) :"
  brut sigstore/cosign pkg/cosign/verify.go "$c" | grep -n -E '^type verifyTrustedMaterial struct|^	root\.TrustedMaterial$|^func \(v \*verifyTrustedMaterial\) [A-Za-z]+|vTrustedMaterial := &verifyTrustedMaterial\{TrustedMaterial: co\.TrustedMaterial\}' | sed 's/^/    verify.go:/'
  echo "- sigstore-go $sg (dernière release) :"
  brut sigstore/sigstore-go pkg/verify/tsa.go "$sg" | grep -n -E 'timestampAuthorities := trustedMaterial\.TimestampingAuthorities\(\)|trustedMaterial == nil' | sed 's/^/    tsa.go:/'
  echo "## 2. modèle du CLI cosign v3.1.2 : chaîne TSA refusée hors de --trusted-root pour un bundle au nouveau format"
  brut sigstore/cosign cmd/cosign/cli/verify/common.go v3.1.2 > "$T/bogue2/common.go"
  grep -n -E '"TSACertChainPath": +"TSA certificate chain path may only be provided using --trusted-root"|if co\.TrustedMaterial == nil && !verifyOfflineWithKey \{|return fmt\.Errorf\("trusted root is required when using new bundle format"\)|return \(keyRef != "" \|\| certRef != "" \|\| sk\) && co\.IgnoreTlog && !co\.UseSignedTimestamps' "$T/bogue2/common.go" | sed 's/^/    common.go:/'
  echo "## 3. admission (Kyverno v1.19.2) : une erreur de règle refuse sous Deny ; failurePolicy n'y est pas lu"
  brut kyverno/kyverno pkg/webhooks/resource/ivpol/handler.go v1.19.2 > "$T/bogue2/handler.go"
  brut kyverno/kyverno pkg/cel/policies/ivpol/engine/engine.go v1.19.2 > "$T/bogue2/engine.go"
  awk '/^func \(h \*handler\) validationResponse/{f=1} f; f && /^}/{exit}' "$T/bogue2/handler.go" > "$T/bogue2/vr.go"
  grep -n -E 'policy\.Actions\.Has\(admissionregistrationv1\.(Deny|Warn)\)|case engineapi\.RuleStatusError:|errs = append\(errs, fmt\.Errorf\("Policy %s error' "$T/bogue2/vr.go" | sed 's/^/    validationResponse, ligne /'
  echo "    mentions de failurePolicy : handler.go $(grep -c -i 'failurepolicy' "$T/bogue2/handler.go" || true), engine.go $(grep -c -i 'failurepolicy' "$T/bogue2/engine.go" || true) (commentaire seulement)"
  grep -n -E 'RuleError\("evaluation", engineapi\.ImageVerify, "failed to evaluate policy"' "$T/bogue2/engine.go" | sed 's/^/    engine.go:/'
  echo "- J6 (resultats/politique-parite.log) : refus à l'admission constaté, motif de Kyverno tronqué par l'avertissement PodSecurity affiché en tête :"
  grep -n -E '^ÉCART j5-' "$R/politique-parite.log" | cut -c1-120 | sed 's/^/    /'
  echo "## 4. historique : raccourci par clé (#16298) puis chaîne TSA fusionnée seulement pour le chemin avec racine (#16800)"
  for f in aa8aecbe3e85 a425f4f37c04; do
    echo "- $(gh api "repos/kyverno/kyverno/commits/$f" --jq '"\(.sha[0:12]) \(.commit.author.date[0:10]) \(.commit.message | split("\n")[0])"') :"
    gh api "repos/kyverno/kyverno/commits/$f" --jq '.files[] | select(.filename == "pkg/image/verifiers/ivpol/cosign/opts.go") | .patch' | grep -E '^\+.*(skipSigstoreInfra :?=|type tsaTrustedMaterial struct|if opts\.TrustedMaterial != nil && len\(roots\) > 0)' | sed 's/^/    /'
  done
  echo "- PR #16048 : $(gh api repos/kyverno/kyverno/pulls/16048 --jq '"\(.state), créée \(.created_at[0:10]), mergeable_state \(.mergeable_state)"') ; fusion de la chaîne TSA dans la racine issue du TUF :"
  gh api repos/kyverno/kyverno/pulls/16048/files --jq '.[] | select(.filename | endswith("cosign/opts.go")) | .patch' | grep -E '^\+.*mergeTSAIntoTrustedMaterial\(trustedRoot' | sed 's/^/    /'
  echo "## 5. autres tests de Kyverno v1.19.2 sous $K : chaîne TSA avec une clé"
  for f in bundle_verify_test.go verifier_test.go opts_integration_test.go; do
    brut kyverno/kyverno "$K/$f" v1.19.2 > "$T/bogue2/$f"
    echo "    $f : mentions de TSACertChain $(grep -c 'TSACertChain' "$T/bogue2/$f" || true), de UseSignedTimestamps $(grep -c 'UseSignedTimestamps' "$T/bogue2/$f" || true)"
  done
  echo "- tests chainsaw (recherche de code GitHub, branche par défaut seulement) :"
  gh api 'search/code?q=tsaCertChain+repo:kyverno/kyverno+path:test' --jq '.items[] | "    \(.path)"' 2>&1 | head -10
  echo "## limites"
  echo "- lu, non reproduit sur la rc.1 ni sur main ; reproduit en J5 et J6 sur la 1.19.2 seulement"
}

for e in "$@"; do
  echo "# sante-sigstore.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$R/sante-sigstore-$e.log"
  "etape_$e" 2>&1 | sed -u "s#$HOME#~#g" | tee -a "$R/sante-sigstore-$e.log"
done
