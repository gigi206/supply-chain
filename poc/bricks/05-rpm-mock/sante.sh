#!/usr/bin/env bash
# Briques 05 et 06 : santé de podman, skopeo et des images de base Rocky et Debian, selon les critères du doc 04 (§1), sans rien
# installer. Préalable aux jalons M1 et S1. Preuves des lignes de ces projets au doc 04 (§2, §3, §5, §6).
#   releves     Scorecard (API publique, tools/health/scorecard.sh), dernière release, commits sur 90 jours, auteurs et domaines
#               des adresses (hors robots), fusionneurs des 100 dernières PR, SECURITY.md, avis publiés ; dépôt des images Rocky
#               sur git.resf.org ; versions de podman, skopeo et buildah dans les dépôts de Rocky 9.7
#   signatures  digest, date, plateformes et signatures cherchées sur les images (cosign tree) ; attestations des images Debian ;
#               manifeste de l'image Debian comparé à l'OCI publié dans Git par debuerreotype ; mainteneurs déclarés ; repomd.xml
#               de Rocky 9.7 vérifié avec la clé de Rocky, dans un trousseau temporaire, avec un témoin altéré
#   podman      toutes les occurrences de podman et skopeo sous mock/ au tag (sources lues, jamais exécutées) ; pour Rocky 9.7 (vault) et 9.8 (pub) : repomd.xml vérifié, other.xml.gz
#               comparé à repomd.xml, changelog des paquets cherché pour les CVE des avis de podman de l'année
#
# Usage (racine du dépôt) : mise exec -- poc/bricks/05-rpm-mock/sante.sh <étape>…   (journal : resultats/sante-<étape>.log)
set -uo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
R=$here/resultats
T=$HOME/.cache/supply-chain-poc/05/sante
DEPUIS=2026-08-07T00:00:00Z   # 90 jours avant le relevé du 05/11/2026, comme la 08b
ROCKY=9.7
VAULT=https://dl.rockylinux.org/vault/rocky/$ROCKY
ROCKY_IMAGE=quay.io/rockylinux/rockylinux:$ROCKY
DEBIAN_IMAGE=docker.io/library/debian:trixie-20261104-slim
ARTEFACTS=https://raw.githubusercontent.com/debuerreotype/docker-debian-artifacts/dist-amd64
MOCK_TAG=mock-6.9-1
ROCKY_CVE="CVE-2026-94603 CVE-2026-57231 CVE-2026-55686 CVE-2026-33414 CVE-2026-19730"
RESF=https://git.resf.org/api/v1/repos/sig_core/rocky-kiwi-descriptions
GH=$(command -v gh)
gh() { env -u GITHUB_TOKEN "$GH" "$@"; }
mkdir -p "$R" "$T"

etape_releves() {
  local r v
  printf 'podman\tcontainers/podman\tconstruction\toui\nskopeo\tcontainers/skopeo\tconstruction\toui\nmock\trpm-software-management/mock\tpackaging\toui\nimages Rocky\trocky-linux/sig-cloud-instance-images\timage de base\toui\nimages Debian\tdebuerreotype/docker-debian-artifacts\timage de base\toui\ndebuerreotype\tdebuerreotype/debuerreotype\timage de base\toui\n' > "$T/projets.tsv"
  "$repo/tools/health/scorecard.sh" "$T/projets.tsv"
  for r in containers/podman containers/skopeo rocky-linux/sig-cloud-instance-images debuerreotype/docker-debian-artifacts debuerreotype/debuerreotype; do
    echo "## $r"
    gh api "repos/$r" --jq '"nom final \(.full_name), archivé \(.archived), licence \(.license.spdx_id), dernier push \(.pushed_at[0:10])"'
    v=$(gh api "repos/$r/releases/latest" --jq '"\(.tag_name) du \(.published_at[0:10])"' 2>/dev/null) || v=aucune
    echo "dernière release : $v"
    gh api "repos/$r/commits?since=$DEPUIS&per_page=100" --paginate --jq '.[] | [(.author.login // "-"), (.commit.author.email | split("@")[1]), (.author.type // "-")] | @tsv' > "$T/commits.tsv"
    echo "commits depuis $DEPUIS : $(wc -l < "$T/commits.tsv") ; auteurs humains les plus actifs (compte, domaine de l'adresse) :"
    awk -F'\t' '$3 != "Bot" && $1 !~ /bot/ {print $1 "\t" $2}' "$T/commits.tsv" | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
    echo "fusionneurs des 100 dernières PR : $(gh pr list --repo "$r" --state merged --limit 100 --json mergedBy --jq '[.[] | .mergedBy.login] | group_by(.) | map("\(.[0]) \(length)") | join(", ")')"
    echo "SECURITY.md : $(gh api "repos/$r/contents/SECURITY.md" --jq .name 2>/dev/null | grep -x SECURITY.md || echo absent)"
    echo "avis publiés : $(gh api "repos/$r/security-advisories?per_page=100" --jq 'length') ; depuis un an : $(gh api "repos/$r/security-advisories?per_page=100" --jq '[.[] | select(.published_at > "2025-11-05")] | length')"
    gh api "repos/$r/security-advisories?per_page=100" --jq '.[0:4][] | "  \(.ghsa_id) \(.published_at[0:10]) \(.severity) \(.summary)"'
  done
  echo "## mock : dernière release"
  gh api repos/rpm-software-management/mock/releases/latest --jq '"\(.tag_name) du \(.published_at[0:10])"'
  echo "## git.resf.org, sig_core/rocky-kiwi-descriptions (source déclarée par l'image Rocky)"
  curl -fsSL --max-time 30 "$RESF" | jq -r '"archivé \(.archived), branche \(.default_branch), mis à jour \(.updated_at[0:10])"'
  curl -fsSL --max-time 30 "$RESF/commits?sha=r9&limit=50&stat=false" | jq -r '.[] | [.commit.author.date[0:10], .commit.author.name] | @tsv' > "$T/resf.tsv"
  echo "derniers commits de r9 : plus récent $(head -1 "$T/resf.tsv" | cut -f1), sur 50 lus :"
  cut -f2 "$T/resf.tsv" | sort | uniq -c | sort -rn | sed 's/^/  /'
  echo "## processus de sécurité de Rocky"
  echo "security.txt : $(curl -fsSL --max-time 30 https://rockylinux.org/.well-known/security.txt | grep -E '^(Contact|Expires):' | tr '\n' ' ')"
  echo "errata : HTTP $(curl -sS -o /dev/null -L --max-time 30 -w '%{http_code}' https://errata.rockylinux.org/)"
  echo "## paquets dans vault/rocky/$ROCKY (les rpm que mock installerait)"
  for p in p:podman s:skopeo b:buildah s:systemd-container; do
    curl -sSL --max-time 60 "$VAULT/AppStream/x86_64/os/Packages/${p%%:*}/" \
      | grep -oE "\"${p##*:}-[0-9][^\"]*\.x86_64\.rpm\"" | tr -d '"' | sort -uV | tail -2 | sed 's/^/  AppStream : /'
  done
  curl -sSL --max-time 60 "$VAULT/BaseOS/x86_64/os/Packages/s/" | grep -oE '"systemd-container-[0-9][^"]*\.x86_64\.rpm"' | tr -d '"' | sort -uV | tail -2 | sed 's/^/  BaseOS : /'
}

image() { # $1 = référence
  local rc=0
  echo "### $1"
  echo "digest : $(crane digest "$1")"
  crane manifest "$1" > "$T/index.json"
  echo "plateformes : $(jq -r '[.manifests[] | select(.platform.os == "linux") | .platform.architecture] | join(" ")' "$T/index.json")"
  echo "manifestes d'attestation : $(jq '[.manifests[] | select(.annotations["vnd.docker.reference.type"] == "attestation-manifest")] | length' "$T/index.json")"
  echo "amd64 : $(crane digest --platform linux/amd64 "$1"), créée le $(crane config --platform linux/amd64 "$1" | jq -r '.created[0:10]')"
  cosign tree "$1" > "$T/tree.txt" 2>&1 || rc=$?
  echo "cosign tree : rc $rc ; $(grep -c -E 'Signatures|Attestations|SBOMs|https://' "$T/tree.txt") entrée(s)"; sed 's/^/  /' "$T/tree.txt" | head -8; echo
}

etape_signatures() {
  local rc=0 d a s
  echo "## images"
  image "$ROCKY_IMAGE"
  image "${ROCKY_IMAGE%:*}:9.8"
  image "$DEBIAN_IMAGE"
  echo "## attestation de l'image Debian, amd64"
  crane manifest "$DEBIAN_IMAGE" > "$T/index.json"
  d=$(crane digest --platform linux/amd64 "$DEBIAN_IMAGE")
  a=$(jq -r --arg d "$d" '.manifests[] | select(.annotations["vnd.docker.reference.digest"] == $d) | .digest' "$T/index.json")
  echo "manifeste d'attestation : $a"
  crane manifest "${DEBIAN_IMAGE%%:*}@$a" | jq -r '.layers[] | [.mediaType, .annotations["in-toto.io/predicate-type"]] | @tsv' | sed 's/^/  /'
  echo "signatures de ce manifeste : $(cosign tree "${DEBIAN_IMAGE%%:*}@$a" 2>&1 | grep -c -E 'Signatures|https://') entrée(s)"
  echo "## image Debian et OCI publié dans Git par debuerreotype"
  echo "série publiée : $(curl -fsSL --max-time 30 "$ARTEFACTS/serial")"
  s=$(curl -fsSL --max-time 30 "$ARTEFACTS/trixie/slim/oci/index.json" | jq -r '.manifests[0].digest')
  echo "trixie/slim/oci/index.json : $s"
  echo "image amd64                : $d"
  if [ "$s" = "$d" ]; then echo "OK   manifeste identique à celui du dépôt"; else echo "KO   manifeste différent"; fi
  curl -fsSL --max-time 30 "$ARTEFACTS/trixie/slim/oci/manifest.json" | jq -r '.[0].Layers[]' | sed 's/^/  couche au dépôt : /'
  crane manifest --platform linux/amd64 "$DEBIAN_IMAGE" | jq -r '.layers[].digest' | sed 's/^/  couche de l image : /'
  echo "mainteneurs déclarés aux images officielles :"
  curl -fsSL --max-time 30 https://raw.githubusercontent.com/docker-library/official-images/master/library/debian | sed -n '/^Maintainers:/,/^GitRepo:/p' | grep -v '^GitRepo' | sed 's/^/  /'
  echo "## repomd.xml de Rocky $ROCKY et clé de Rocky"
  export GNUPGHOME=$T/gnupg
  rm -rf -- "${GNUPGHOME:?}"; mkdir -m 700 "$GNUPGHOME"
  curl -fsSL --max-time 30 "$VAULT/BaseOS/x86_64/os/RPM-GPG-KEY-Rocky-9" -o "$T/rocky.key" || curl -fsSL --max-time 30 https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 -o "$T/rocky.key"
  echo "sha256 de la clé : $(sha256sum "$T/rocky.key" | cut -c1-64)"
  echo "empreinte publiée sur rockylinux.org : $(curl -fsSL --max-time 30 https://rockylinux.org/resources/gpg-key-info | grep -oE '21CB 256A E16F C54C 6E65 2949 702D 426D 350D 275D' | sort -u)"
  gpg --batch --quiet --import "$T/rocky.key" 2>&1 | head -3
  gpg --batch --with-colons --fingerprint | awk -F: '$1 == "fpr" {print "empreinte : " $10} $1 == "uid" {print "identité : " $10}' | head -4
  for depot in BaseOS AppStream CRB; do
    curl -fsSL --max-time 30 "$VAULT/$depot/x86_64/os/repodata/repomd.xml" -o "$T/repomd.xml"
    curl -fsSL --max-time 30 "$VAULT/$depot/x86_64/os/repodata/repomd.xml.asc" -o "$T/repomd.xml.asc"
    rc=0; gpg --batch --verify "$T/repomd.xml.asc" "$T/repomd.xml" > "$T/gpg.txt" 2>&1 || rc=$?
    echo "$depot : rc $rc ; $(grep -E 'Good signature|BAD signature|Can.t check|No public key' "$T/gpg.txt" | head -1)"
  done
  echo x >> "$T/repomd.xml"
  rc=0; gpg --batch --verify "$T/repomd.xml.asc" "$T/repomd.xml" > "$T/gpg.txt" 2>&1 || rc=$?
  echo "témoin altéré : rc $rc (refus attendu) ; $(grep -E 'Good signature|BAD signature' "$T/gpg.txt" | head -1)"
  rm -rf -- "${GNUPGHOME:?}"
}

changelogs() { # $1 = étiquette, $2 = URL du dépôt AppStream ; trousseau dans GNUPGHOME
  local d=$T/depot-$1 sha chemin rc=0
  rm -rf -- "${d:?}"; mkdir -p "$d"
  curl -fsSL --max-time 30 "$2/repodata/repomd.xml" -o "$d/repomd.xml"
  curl -fsSL --max-time 30 "$2/repodata/repomd.xml.asc" -o "$d/repomd.xml.asc"
  gpg --batch --verify "$d/repomd.xml.asc" "$d/repomd.xml" > "$d/gpg.txt" 2>&1 || rc=$?
  echo "### $1 : repomd.xml rc $rc ; $(grep -E 'Good signature|BAD signature' "$d/gpg.txt" | cut -c1-70)"
  [ "$rc" = 0 ] || return 1
  chemin=$(python3 -I - "$d/repomd.xml" <<'PY'
import sys, xml.etree.ElementTree as E
n = '{http://linux.duke.edu/metadata/repo}'
for x in E.parse(sys.argv[1]).getroot().findall(n + 'data'):
    if x.get('type') == 'other':
        print(x.find(n + 'location').get('href'), x.find(n + 'checksum').text)
PY
)
  sha=${chemin##* }; chemin=${chemin%% *}
  curl -fsSL --max-time 300 "$2/$chemin" -o "$d/other.xml.gz"
  [ "$(sha256sum "$d/other.xml.gz" | cut -c1-64)" = "$sha" ] && echo "OK   other.xml.gz conforme à repomd.xml" || { echo "KO   other.xml.gz"; return 1; }
  python3 -I - "$d/other.xml.gz" $ROCKY_CVE <<'PY'
import gzip, sys, xml.etree.ElementTree as E
n = '{http://linux.duke.edu/metadata/other}'
meilleur = {}
for _, x in E.iterparse(gzip.open(sys.argv[1]), events=('end',)):
    if x.tag != n + 'package':
        continue
    nom = x.get('name')
    if nom in ('podman', 'skopeo', 'buildah') and x.get('arch') == 'x86_64':
        v = x.find(n + 'version')
        rel = (tuple(int(c) if c.isdigit() else 0 for c in v.get('rel').replace('_', '.').split('.')), v.get('ver') + '-' + v.get('rel'))
        texte = ' '.join(c.text or '' for c in x.findall(n + 'changelog'))
        if nom not in meilleur or rel > meilleur[nom][0]:
            meilleur[nom] = (rel, texte)
    x.clear()
for nom, (rel, texte) in sorted(meilleur.items()):
    print(f'{nom} {rel[1]} :', ', '.join(f'{c} {"présente" if c in texte else "absente"}' for c in sys.argv[2:]))
PY
}

etape_podman() {
  local f
  echo "## appels de podman et skopeo dans mock, tag $MOCK_TAG"
  rm -rf -- "${T:?}/mock-src"; mkdir "$T/mock-src"
  curl -fsSL --max-time 120 "https://codeload.github.com/rpm-software-management/mock/tar.gz/refs/tags/$MOCK_TAG" | tar -xz -C "$T/mock-src" --strip-components=1
  echo "fichiers lus sous mock/ : $(find "$T/mock-src/mock" -type f | wc -l) (sources lues, jamais exécutées)"
  ( cd "$T/mock-src" && grep -rn -i -I -E 'podman|skopeo' mock ) > "$T/occurrences.txt"
  echo "occurrences de podman ou skopeo, quelle que soit la casse ou la forme des guillemets : $(wc -l < "$T/occurrences.txt"), par fichier :"
  cut -d: -f1 "$T/occurrences.txt" | sort | uniq -c | sort -rn | sed 's/^/  /'
  echo "occurrences contenant run, build, exec, create, load ou save comme mot :"
  grep -i -E "\b(run|build|exec|create|load|save)\b" "$T/occurrences.txt" | cut -c1-170 | sed 's/^/  /'
  echo "tous les appels écrits dans podman.py et mock-hermetic-repo.py :"
  ( cd "$T/mock-src/mock/py" && grep -n -E "(cmd[a-z_]*|check) *= *\[" mockbuild/podman.py mock-hermetic-repo.py ) | cut -c1-140 | sed 's/^/  /'
  echo "occurrences dans les autres fichiers de code de mock :"
  grep -E '^mock/py/' "$T/occurrences.txt" | grep -v -E '^mock/py/(mockbuild/podman\.py|mock-hermetic-repo\.py):' | cut -c1-170 | sed 's/^/  /'
  rm -rf -- "${T:?}/mock-src"
  echo "## changelogs des paquets, dépôts signés"
  export GNUPGHOME=$T/gnupg
  rm -rf -- "${GNUPGHOME:?}"; mkdir -m 700 "$GNUPGHOME"
  curl -fsSL --max-time 30 https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 -o "$T/rocky.key"
  gpg --batch --quiet --import "$T/rocky.key" 2>&1 | head -3
  echo "empreinte : $(gpg --batch --with-colons --fingerprint | awk -F: '$1 == "fpr" {print $10; exit}')"
  changelogs vault-9.7 "$VAULT/AppStream/x86_64/os"
  changelogs pub-9.8 https://dl.rockylinux.org/pub/rocky/9.8/AppStream/x86_64/os
  rm -rf -- "${GNUPGHOME:?}" "${T:?}"/depot-*
}

for e in "$@"; do
  echo "# sante.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$R/sante-$e.log"
  "etape_$e" 2>&1 | tee -a "$R/sante-$e.log"
done
