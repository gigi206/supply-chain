#!/usr/bin/env bash
# Brique 08 : promo-tools (kpromo) et Macaron sont-ils pertinents pour le PoC ? Question du propriétaire du 08/11/2026 (« Et
# https://github.com/kubernetes-sigs/promo-tools et https://github.com/oracle/macaron seraient des solutions pertinentes? ») ;
# archivage accordé (« Oui » à « J'archive ce relevé (journal + additifs datés au doc 00 et au doc 04 […]) : oui ou pas
# maintenant ? »). Lecture publique seulement (API GitHub, API Scorecard) : rien d'installé, rien d'écrit chez les projets
# tiers, rien lu ni écrit dans le cluster, Zot ou les VM. Sources et documents lus, jamais exécutés.
#   releves    santé selon les critères du doc 04 (§1), même méthode que sante-sigstore.sh : Scorecard, releases et fichiers
#              attachés, commits sur 90 jours (humains et robots), commits par mois sur un an, auteurs ET fusionneurs des 100
#              dernières PR fusionnées, PR ouvertes de dependabot, SECURITY.md, avis publiés, OWNERS (promo-tools)
#   documents  lignes de la documentation qui décident de la pertinence, à un commit fixé de la branche par défaut : registres
#              acceptés par le promoteur, dépendances cloud du go.mod, identités de signature, mode d'installation (promo-tools) ;
#              capacités, écosystèmes et mentions de l'API GitHub dans la documentation (Macaron)
#
# Usage (racine du dépôt) : poc/bricks/08-trust-plane/sante-veille.sh <étape>…   (journal : resultats/sante-veille-<étape>.log)
set -uo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
R=$here/resultats
T=$HOME/.cache/supply-chain-poc/08/sante-veille
DEPUIS=2026-08-10T00:00:00Z   # 90 jours avant le relevé du 08/11/2026
UN_AN=2025-11-08
PROJETS=(kubernetes-sigs/promo-tools oracle/macaron)
GH=$(command -v gh)
gh() { env -u GITHUB_TOKEN "$GH" "$@" </dev/null; }
brut() { gh api "repos/$1/contents/$2?ref=$3" -H 'Accept: application/vnd.github.raw'; }   # $1 dépôt, $2 chemin, $3 réf
mkdir -p "$R" "$T"

etape_releves() {
  local r v
  printf 'promo-tools (kpromo)\tkubernetes-sigs/promo-tools\tdistribution\tnon\nMacaron\toracle/macaron\tanalyse SLSA\tnon\n' > "$T/projets.tsv"
  "$repo/tools/health/scorecard.sh" "$T/projets.tsv"
  for r in "${PROJETS[@]}"; do
    echo "## $r (relevé à $(date -u +%H:%M:%S) UTC)"
    echo "API Scorecard : HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://api.securityscorecards.dev/projects/github.com/$r")"
    gh api "repos/$r" --jq '"nom final \(.full_name), archivé \(.archived), licence \(.license.spdx_id), dernier push \(.pushed_at[0:10]), branche \(.default_branch)"'
    v=$(gh api "repos/$r/releases/latest" --jq '"\(.tag_name) du \(.published_at[0:10]), \(.assets | length) fichiers attachés"' 2>/dev/null) || v=aucune
    echo "dernière release : $v"
    echo "releases depuis le $UN_AN : $(gh api "repos/$r/releases?per_page=30" --jq "[.[] | select(.published_at > \"$UN_AN\") | \"\(.tag_name) (\(.published_at[0:10]), \(.assets | length) fichiers)\"] | join(\", \")")"
    echo "fichiers de la dernière release liés aux signatures et à la provenance :"
    gh api "repos/$r/releases/latest" --jq '[.assets[].name | select(test("\\.(sig|pem|crt|bundle|sigstore(\\.json)?|intoto\\.jsonl|att)$|provenance|checksums|sha256|sbom"; "i"))] | if length == 0 then "  aucun" else .[] | "  " + . end' 2>/dev/null || echo "  aucune release"
    gh api "repos/$r/commits?since=$DEPUIS&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), (.commit.author.email | split("@")[1]), (.author.type // "-")] | @tsv' > "$T/commits.tsv"
    echo "commits depuis $DEPUIS : $(wc -l < "$T/commits.tsv"), dont robots $(awk -F'\t' '$3 == "Bot" || $1 ~ /bot/' "$T/commits.tsv" | wc -l) ; auteurs humains (compte, domaine de l'adresse) :"
    awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1 "\t" $2}' "$T/commits.tsv" | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
    gh api "repos/$r/commits?since=${UN_AN}T00:00:00Z&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), .commit.author.date[0:7], (.author.type // "-")] | @tsv' > "$T/an.tsv"
    echo "commits par mois depuis le $UN_AN (tous auteurs) : $(cut -f2 "$T/an.tsv" | sort | uniq -c | awk '{printf "%s %s, ", $2, $1}')"
    echo "auteurs humains sur un an : $(awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1}' "$T/an.tsv" | sort | uniq -c | sort -rn | head -8 | awk '{printf "%s %s, ", $2, $1}')"
    echo "dernier commit de chaque auteur humain principal sur un an :"
    awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1}' "$T/an.tsv" | sort | uniq -c | sort -rn | head -3 | while read -r _ v; do
      echo "  $v : $(awk -F'\t' -v a="$v" '$1 == a {print $2; exit}' "$T/an.tsv")"
    done
    gh pr list --repo "$r" --state merged --limit 100 --json author,mergedBy,mergedAt > "$T/pr.json"
    echo "100 dernières PR fusionnées, du $(jq -r '.[-1].mergedAt[0:10]' "$T/pr.json") au $(jq -r '.[0].mergedAt[0:10]' "$T/pr.json") :"
    echo "  auteurs : $(jq -r '[.[] | .author.login] | group_by(.) | map("\(.[0]) \(length)") | sort_by(-(split(" ")[1] | tonumber)) | join(", ")' "$T/pr.json")"
    echo "  fusionneurs : $(jq -r '[.[] | (.mergedBy.login // "-")] | group_by(.) | map("\(.[0]) \(length)") | sort_by(-(split(" ")[1] | tonumber)) | join(", ")' "$T/pr.json")"
    echo "PR ouvertes : $(gh pr list --repo "$r" --state open --limit 200 --json number --jq length), dont dependabot $(gh pr list --repo "$r" --state open --limit 200 --author 'app/dependabot' --json number --jq length) (la plus ancienne de dependabot : $(gh pr list --repo "$r" --state open --limit 200 --author 'app/dependabot' --json createdAt --jq 'map(.createdAt[0:10]) | min // "-"'))"
    echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null | grep -x SECURITY.md || echo "absent du dépôt")"
    echo "avis publiés : $(gh api "repos/$r/security-advisories?per_page=100" --jq 'length') ; depuis un an : $(gh api "repos/$r/security-advisories?per_page=100" --jq "[.[] | select(.published_at > \"$UN_AN\")] | length")"
  done
  echo "## kubernetes-sigs/promo-tools : OWNERS (approbateurs et relecteurs, alias de SIG Release)"
  brut kubernetes-sigs/promo-tools OWNERS HEAD | grep -E '^\s*-|^[a-z]+:' | sed 's/^/  /'
  echo "## kubernetes-sigs/promo-tools : politique de sécurité de l'organisation kubernetes-sigs"
  gh api repos/kubernetes-sigs/.github/contents/SECURITY.md --jq '"SECURITY.md de kubernetes-sigs/.github : présent, \(.size) octets"' 2>/dev/null || echo "SECURITY.md de kubernetes-sigs/.github : absent"
  echo "## limites"
  echo "- employeurs non vérifiés (domaines des adresses seulement) ; signatures des fichiers attachés aux releases non vérifiées"
}

etape_documents() {
  local r s
  r=kubernetes-sigs/promo-tools
  s=$(gh api "repos/$r/commits/main" --jq .sha)
  echo "## $r au commit $s (relevé à $(date -u +%H:%M:%S) UTC)"
  echo "- docs/image-promotion.md, registres acceptés :"
  brut "$r" docs/image-promotion.md "$s" | grep -n -E 'arbitrary OCI|pkg/v1/google|tags-list API|Google-specific' | sed 's/^/    /'
  echo "- docs/verification-summaries.md, identités de signature et prédicats :"
  brut "$r" docs/verification-summaries.md "$s" | grep -n -E 'iam\.gserviceaccount\.com|verification_summary/v1|promotion/v1' | cut -c1-200 | sed 's/^/    /'
  echo "- go.mod, dépendances cloud et Sigstore :"
  brut "$r" go.mod "$s" | grep -n -E 'cloud\.google\.com/go/(storage|iam|containeranalysis) |google\.golang\.org/api |aws-sdk-go-v2 |aws-sdk-go-v2/service/s3 |Azure/azure-sdk-for-go |sigstore/(cosign|sigstore-go)' | sed 's/^/    /'
  echo "- README.md, installation :"
  brut "$r" README.md "$s" | grep -n -E 'go install' | sed 's/^/    /'
  r=oracle/macaron
  s=$(gh api "repos/$r/commits/main" --jq .sha)
  echo "## $r au commit $s (relevé à $(date -u +%H:%M:%S) UTC)"
  echo "- README.md, capacités et outils de build :"
  brut "$r" README.md "$s" | grep -n -E '^- \*\*|^- \*\*(Java|Python|JavaScript)|^- \*\*Go|^- \*\*Docker|Verification Summary' | cut -c1-160 | sed 's/^/    /'
  echo "- docs/source/index.rst, mentions de l'API GitHub, d'un jeton ou du mode hors ligne (comptage, non interprété) :"
  brut "$r" docs/source/index.rst "$s" > "$T/index.rst"
  echo "    lignes : $(wc -l < "$T/index.rst") ; « GitHub API » : $(grep -c -i 'github api' "$T/index.rst" || true) ; « GITHUB_TOKEN » : $(grep -c 'GITHUB_TOKEN' "$T/index.rst" || true) ; « offline » : $(grep -c -i 'offline' "$T/index.rst" || true)"
  echo "## limites"
  echo "- lu, rien essayé : promo-tools n'a pas été lancé contre Zot ; le besoin de réseau de Macaron n'est pas établi au-delà de ces mentions"
}

# Ajout du 08/11/2026, écrit juste avant le passage de 19:59:10 UTC (heure d'abord écrite « vers 18:25 », par erreur), sur demande du propriétaire (« Et regarde https://github.com/google/oss-rebuild ») ; lecture
# publique seulement (API GitHub, API Scorecard, liste anonyme du bucket public des attestations) ; les étapes précédentes ne
# sont pas modifiées.
#   oss_rebuild  santé (mêmes lectures que releves) et lignes de documentation et de code qui décident de l'usage : écosystèmes
#                (README, pkg/rebuild, bucket public), installation, clés de vérification embarquées, hébergement (Terraform),
#                équivalence par stabilisation
etape_oss_rebuild() {
  local r=google/oss-rebuild s v
  printf 'OSS Rebuild\tgoogle/oss-rebuild\treproductibilité\tnon\n' > "$T/projets-oss.tsv"
  "$repo/tools/health/scorecard.sh" "$T/projets-oss.tsv"
  echo "## $r (relevé à $(date -u +%H:%M:%S) UTC)"
  echo "API Scorecard : HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://api.securityscorecards.dev/projects/github.com/$r")"
  gh api "repos/$r" --jq '"nom final \(.full_name), archivé \(.archived), licence \(.license.spdx_id), dernier push \(.pushed_at[0:10]), branche \(.default_branch)"'
  echo "releases : $(gh api "repos/$r/releases?per_page=100" --jq length) ; tags : $(gh api "repos/$r/tags?per_page=100" --jq length)"
  gh api "repos/$r/commits?since=$DEPUIS&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), (.commit.author.email | split("@")[1]), (.author.type // "-")] | @tsv' > "$T/commits.tsv"
  echo "commits depuis $DEPUIS : $(wc -l < "$T/commits.tsv"), dont robots $(awk -F'\t' '$3 == "Bot" || $1 ~ /bot/' "$T/commits.tsv" | wc -l) ; auteurs humains (compte, domaine de l'adresse) :"
  awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1 "\t" $2}' "$T/commits.tsv" | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
  gh api "repos/$r/commits?since=${UN_AN}T00:00:00Z&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), .commit.author.date[0:7], (.author.type // "-")] | @tsv' > "$T/an.tsv"
  echo "commits par mois depuis le $UN_AN (tous auteurs) : $(cut -f2 "$T/an.tsv" | sort | uniq -c | awk '{printf "%s %s, ", $2, $1}')"
  echo "auteurs humains sur un an : $(awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1}' "$T/an.tsv" | sort | uniq -c | sort -rn | head -8 | awk '{printf "%s %s, ", $2, $1}')"
  gh pr list --repo "$r" --state merged --limit 100 --json author,mergedBy,mergedAt > "$T/pr.json"
  echo "100 dernières PR fusionnées, du $(jq -r '.[-1].mergedAt[0:10]' "$T/pr.json") au $(jq -r '.[0].mergedAt[0:10]' "$T/pr.json") :"
  echo "  auteurs : $(jq -r '[.[] | .author.login] | group_by(.) | map("\(.[0]) \(length)") | sort_by(-(split(" ")[1] | tonumber)) | join(", ")' "$T/pr.json")"
  echo "  fusionneurs : $(jq -r '[.[] | (.mergedBy.login // "-")] | group_by(.) | map("\(.[0]) \(length)") | sort_by(-(split(" ")[1] | tonumber)) | join(", ")' "$T/pr.json")"
  echo "PR ouvertes : $(gh pr list --repo "$r" --state open --limit 200 --json number --jq length)"
  echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null | grep -x SECURITY.md || echo "absent du dépôt")"
  echo "avis publiés : $(gh api "repos/$r/security-advisories?per_page=100" --jq 'length')"
  s=$(gh api "repos/$r/commits/main" --jq .sha)
  echo "## documentation et code au commit $s (relevé à $(date -u +%H:%M:%S) UTC)"
  echo "- CONTRIBUTING.md, CLA :"
  brut "$r" CONTRIBUTING.md "$s" | grep -n -i -E 'contributor license agreement|cla\.developers' | head -3 | cut -c1-160 | sed 's/^/    /'
  echo "- README.md, écosystèmes, installation, couverture, authentification :"
  brut "$r" README.md "$s" | grep -n -E '^- (npm|PyPI|Crates)|@latest|most popular|ADC credential|Anonymous authentication|--verify=false' | cut -c1-160 | sed 's/^/    /'
  echo "- pkg/rebuild (répertoires) : $(gh api "repos/$r/contents/pkg/rebuild?ref=$s" --jq '[.[] | select(.type == "dir") | .name] | join(" ")')"
  echo "- bucket public gs://google-rebuild-attestations, préfixes de premier niveau (liste anonyme) : $(curl -s --max-time 20 'https://storage.googleapis.com/storage/v1/b/google-rebuild-attestations/o?delimiter=/&fields=prefixes' | jq -r '.prefixes // ["illisible"] | join(" ")')"
  echo "- docs/content/hosts/Google.md, stockage et clé :"
  brut "$r" docs/content/hosts/Google.md "$s" | grep -n -E 'storage URI|Signing key|CC0' | cut -c1-200 | sed 's/^/    /'
  echo "- docs/content/storage.md, accès et vérification :"
  brut "$r" docs/content/storage.md "$s" | grep -n -E 'rebuild\.intoto\.jsonl$|public and can be used without|builtin version' | cut -c1-200 | sed 's/^/    /'
  echo "- cmd/oss-rebuild/verify.go et main.go, clés embarquées et vérification en ligne :"
  brut "$r" cmd/oss-rebuild/verify.go "$s" | grep -n -E 'BEGIN PUBLIC KEY|EC_SIGN_P256_SHA256,|embeddedKeys|kms.NewKeyManagementClient' | sed 's/^/    verify.go:/'
  brut "$r" cmd/oss-rebuild/main.go "$s" | grep -n -E 'flag\.Bool\("verify|flag\.String\("verify-with' | cut -c1-200 | sed 's/^/    main.go:/'
  echo "- deployments (hébergement d'une instance) :"
  brut "$r" deployments/providers.tf "$s" | grep -n -E 'source *=|provider "' | sed 's/^/    providers.tf:/'
  brut "$r" deployments/README.md "$s" | grep -n -E 'terraform apply|OpenTofu|Cloud Run' | cut -c1-160 | sed 's/^/    README.md:/'
  echo "    ressources google_* dans services.tf et platform.tf : $(for f in services.tf platform.tf; do brut "$r" "deployments/$f" "$s"; done | grep -o -E 'resource "google_[a-z_]+"' | sort | uniq -c | sort -rn | head -8 | awk '{printf "%s %s, ", $3, $1}')"
  echo "- docs/content/stabilizers.md, équivalence :"
  brut "$r" docs/content/stabilizers.md "$s" | grep -n -E 'bit-for-bit|functional equivalence|zeroe timestamps' | cut -c1-200 | sed 's/^/    /'
  echo "## limites"
  echo "- lu, rien installé ni exécuté ; aucune attestation téléchargée ni vérifiée ; couverture réelle des paquets non mesurée ; employeurs non vérifiés"
}

# Ajout du 08/11/2026 vers 20:01 UTC, sur relecture du conseiller, après le journal oss_rebuild (non réécrit) : âge du dépôt (la
# règle « Risqué » du doc 04 compte en mois sans release), politique de sécurité de l'organisation google, choix entre clé
# embarquée et KMS dans le CLI.
etape_oss_rebuild_complements() {
  local r=google/oss-rebuild s
  echo "## $r (relevé à $(date -u +%H:%M:%S) UTC)"
  gh api "repos/$r" --jq '"créé le \(.created_at[0:10]), dernier push \(.pushed_at[0:10])"'
  echo "premier commit de la branche par défaut : $(gh api "repos/$r/commits?per_page=1&until=2024-12-31T23:59:59Z" --jq '.[0].commit.author.date[0:10] // "aucun avant 2025"') (le plus récent avant le 01/01/2025)"
  echo "SECURITY.md de google/.github : $(gh api repos/google/.github/contents/SECURITY.md --jq '"présent, \(.size) octets"' 2>/dev/null || echo "absent (politique de l'organisation non trouvée par ce chemin)")"
  s=$(gh api "repos/$r/commits/main" --jq .sha)
  echo "## cmd/oss-rebuild/main.go au commit $s, lignes 125 à 160 (choix entre clés embarquées et KMS)"
  brut "$r" cmd/oss-rebuild/main.go "$s" | sed -n '125,160p' | sed 's/^/    /'
}

# Ajout du 08/11/2026, écrit juste avant le passage de 20:06:50 UTC (heure d'abord écrite « vers 20:08 », par anticipation), sur question du propriétaire (« Mais peut être que dans chacun des projets écartés il y a
# des idées à retenir? ») : lignes de documentation qui portent les idées de conception, aux mêmes commits fixés que les étapes
# documents et oss_rebuild si la branche n'a pas bougé (commit relevé à nouveau). Lecture seule ; les journaux précédents ne sont
# pas réécrits.
etape_idees() {
  local r s
  r=kubernetes-sigs/promo-tools; s=$(gh api "repos/$r/commits/main" --jq .sha)
  echo "## $r au commit $s (relevé à $(date -u +%H:%M:%S) UTC)"
  echo "- README.md, contrôle et réparation a posteriori :"
  brut "$r" README.md "$s" | grep -n -E 'sigcheck' | cut -c1-200 | sed 's/^/    /'
  echo "- docs/image-promotion.md, séparation des droits dans les manifestes :"
  brut "$r" docs/image-promotion.md "$s" | grep -n -E 'thin manifests are preferred|more sensitive|handful of owners' | cut -c1-200 | sed 's/^/    /'
  echo "- docs/verification-summaries.md, politique avant copie, recopie filtrée, VSA unique pour l'utilisateur :"
  brut "$r" docs/verification-summaries.md "$s" | grep -n -E 'verify that one summary|copies the image by digest|attestations the policy accepted|evaluate the staging attestations' | cut -c1-200 | sed 's/^/    /'
  r=oracle/macaron; s=$(gh api "repos/$r/commits/main" --jq .sha)
  echo "## $r au commit $s (relevé à $(date -u +%H:%M:%S) UTC)"
  brut "$r" README.md "$s" | grep -n -E 'Accurate repository and commit detection|rebuilding packages from source|Verification Summary Attestations' | cut -c1-200 | sed 's/^/    /'
  r=google/oss-rebuild; s=$(gh api "repos/$r/commits/main" --jq .sha)
  echo "## $r au commit $s (relevé à $(date -u +%H:%M:%S) UTC)"
  echo "- deux attestations par artefact (docs/content/storage.md) :"
  brut "$r" docs/content/storage.md "$s" | grep -n -E 'rebuild attestation\]|artifact equivalence attestation\]|organized hierarchically' | cut -c1-200 | sed 's/^/    /'
  echo "- recette de reconstruction rejouable (README.md) :"
  brut "$r" README.md "$s" | grep -n -E 'output=dockerfile' | cut -c1-200 | sed 's/^/    /'
  echo "- stabilisateurs (docs/content/stabilizers.md) :"
  brut "$r" docs/content/stabilizers.md "$s" | grep -n -E 'pure function|composition of all configured|normalizing the lowest-risk' | cut -c1-200 | sed 's/^/    /'
  echo "- prédicats (docs/content/builds) :"
  for f in Rebuild@v0.1.md ArtifactEquivalence@v0.1.md; do
    brut "$r" "docs/content/builds/$f" "$s" | grep -n -i -E 'predicateType|^# |buildType' | head -4 | cut -c1-200 | sed "s/^/    $f:/"
  done
}

for e in "$@"; do
  echo "# sante-veille.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$R/sante-veille-$e.log"
  "etape_$e" 2>&1 | sed -u "s#$HOME#~#g" | tee -a "$R/sante-veille-$e.log"
done
