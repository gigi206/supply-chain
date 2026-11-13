#!/usr/bin/env bash
# Brique 03 : santé de Nix, de nixpkgs et de Hydra (constructeur de cache.nixos.org) selon les critères du doc 04 (§1), sans rien
# installer. Préparé le 13/11/2026 sur la décision du propriétaire « Oui, les deux » (régulariser Nix pour l'image outils-prefetch
# de F2, et instruire l'option Debian par un banc) : preuve du verdict de Nix et de nixpkgs au doc 04, absent jusqu'ici.
#   releves     Scorecard (API publique, tools/health/scorecard.sh) ; par dépôt : archivé, licence, dernière release, commits sur
#               90 jours (nixpkgs : compte plafonné, signalé), auteurs et domaines des adresses (hors robots), fusionneurs des 100
#               dernières PR, SECURITY.md, avis publiés
#   cache       ce que l'hôte fait confiance : substituts et clés de nix.conf, nix-cache-info et clé publiée de cache.nixos.org ;
#               verrou du flake du banc B (tarball de releases.nixos.org, narHash) ; liste du canal (fichiers .sha256 publiés)
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/03-deps-closure/sante-nix.sh <étape>…   (journal : resultats/sante-nix-<étape>.log)
set -uo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
R=$here/resultats
T=$HOME/.cache/supply-chain-poc/03/sante-nix
DEPUIS=$(date -u -d '90 days ago' +%Y-%m-%dT00:00:00Z)
UN_AN=$(date -u -d '1 year ago' +%Y-%m-%d)
PLAFOND=10   # pages de 100 commits au plus par dépôt (nixpkgs dépasse : compte signalé « au moins »)
CANAL=https://releases.nixos.org/nixos/25.11/nixos-25.11.12484.b6018f87da91
GH=$(command -v gh)
gh() { env -u GITHUB_TOKEN "$GH" "$@"; }
mkdir -p "$R" "$T"

releve_depot() { # $1 = dépôt GitHub
  local r=$1 v n p
  echo "## $r"
  gh api "repos/$r" --jq '"nom final \(.full_name), archivé \(.archived), licence \(.license.spdx_id), dernier push \(.pushed_at[0:10])"'
  v=$(gh api "repos/$r/releases/latest" --jq '"\(.tag_name) du \(.published_at[0:10])"' 2>/dev/null) || v=aucune
  echo "dernière release GitHub : $v"
  echo "derniers tags : $(gh api "repos/$r/tags?per_page=5" --jq '[.[].name] | join(", ")')"
  : > "$T/commits.tsv"
  for p in $(seq "$PLAFOND"); do
    gh api "repos/$r/commits?since=$DEPUIS&per_page=100&page=$p" --jq '.[] | [(.author.login // "-"), ((.commit.author.email // "-") | split("@") | last), (.author.type // "-")] | @tsv' > "$T/page.tsv" || break
    cat "$T/page.tsv" >> "$T/commits.tsv"
    [ "$(wc -l < "$T/page.tsv")" = 100 ] || break
  done
  n=$(wc -l < "$T/commits.tsv")
  if [ "$n" -ge $((PLAFOND * 100)) ]; then echo "commits depuis $DEPUIS : au moins $n (plafond de $PLAFOND pages atteint)"; else echo "commits depuis $DEPUIS : $n"; fi
  echo "auteurs humains les plus actifs (compte, domaine de l'adresse), sur ces commits :"
  awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1 "\t" $2}' "$T/commits.tsv" | sort | uniq -c | sort -rn | awk 'NR <= 10' | sed 's/^/  /'
  echo "auteurs humains distincts sur ces commits : $(awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1}' "$T/commits.tsv" | sort -u | wc -l)"
  echo "fusionneurs des 100 dernières PR : $(gh pr list --repo "$r" --state merged --limit 100 --json mergedBy --jq '[.[] | .mergedBy.login] | group_by(.) | map("\(.[0]) \(length)") | join(", ")')"
  echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null | grep -x SECURITY.md || echo absent)"
  echo "avis publiés (GitHub) : $(gh api "repos/$r/security-advisories?per_page=100" --jq 'length') ; depuis $UN_AN : $(gh api "repos/$r/security-advisories?per_page=100" --jq '[.[] | select(.published_at > "'"$UN_AN"'")] | length')"
  gh api "repos/$r/security-advisories?per_page=100" --jq '.[0:5][] | "  \(.ghsa_id) \(.published_at[0:10]) \(.severity) \(.summary)"'
}

etape_releves() {
  local r
  printf 'Nix\tNixOS/nix\tconstruction\toui\nnixpkgs\tNixOS/nixpkgs\tconstruction\toui\nHydra\tNixOS/hydra\tconstruction\toui\n' > "$T/projets.tsv"
  "$repo/tools/health/scorecard.sh" "$T/projets.tsv"
  for r in NixOS/nix NixOS/nixpkgs NixOS/hydra; do releve_depot "$r"; done
}

etape_cache() {
  echo "## configuration de Nix sur l'hôte (clés publiques et réglages, aucun secret)"
  nix --version
  nix config show </dev/null 2>/dev/null | awk -F' = ' '$1 ~ /^(substituters|trusted-substituters|trusted-public-keys|require-sigs|extra-substituters)$/'
  echo "## cache.nixos.org"
  curl -fsS --max-time 30 https://cache.nixos.org/nix-cache-info | sed 's/^/  /'
  echo "## verrou du flake du banc B"
  jq -r '.nodes.nixpkgs.locked | "type \(.type), url \(.url), narHash \(.narHash)"' "$repo/poc/benchmarks/nix/flake.lock"
  echo "dernier commit de poc/benchmarks/nix : $(git -C "$repo" log -1 --format='%h %cs' -- poc/benchmarks/nix </dev/null)"
  echo "## canal publié ($CANAL)"
  echo "nixexprs.tar.xz.sha256 : HTTP $(curl -sS -o "$T/nixexprs.sha256" -w '%{http_code}' --max-time 30 "$CANAL/nixexprs.tar.xz.sha256") ; $(head -c 64 "$T/nixexprs.sha256" 2>/dev/null)"
  echo "signature détachée cherchée (nixexprs.tar.xz.asc, .sig) : $(for s in asc sig; do printf '%s HTTP %s ; ' "$s" "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "$CANAL/nixexprs.tar.xz.$s")"; done)"
  echo "git-revision : $(curl -fsS --max-time 30 "$CANAL/git-revision" 2>/dev/null || echo absent)"
}

[ $# -gt 0 ] || { echo "usage : $0 releves|cache…" >&2; exit 2; }
for e in "$@"; do
  case $e in
    releves|cache) "etape_$e" 2>&1 | grep -v -i -E 'jeton|token' | tee "$R/sante-nix-$e.log" ;;
    *) echo "étape inconnue : $e" >&2; exit 2 ;;
  esac
done
