#!/usr/bin/env bash
# Brique 08 : étape B de la validation du correctif Kyverno (plantage de ctlog.tsaCertChain, voir README, « Correctif du plantage »).
# Le CLI corrigé juge les vrais bundles de J5, dont le jeton embarque le certificat de notre TSA (cas que les tests unitaires
# ne couvrent pas). Préparé à sec le 08/11/2026 sur accord du propriétaire (« Oui » à « Je prépare l'étape B maintenant
# (préparation à sec seulement), ou on attend la fin de W8 ? ») ; prédictions dans resultats/kyverno-correctif-b-predictions.md.
#   construire  CLI kubectl-kyverno depuis les clones du cache (main 2be1bc3fe3b4 et v1.19.2 e63308f1e16c), correctif v2 appliqué
#               (vérifié contre kyverno-correctif/correctif-v2-final.patch) ; local seulement, rien lu ni écrit dans Zot
#   cli         lecture seule de Zot (anonyme) : présence des dépôts de J5, puis les 8 cas de J6 (même politique ivpol, même pod)
#               jugés par le CLI officiel 1.19.2 (témoin du jour), le CLI main corrigé et le CLI v1.19.2 corrigé ; ne réécrit rien
#               dans Zot (contrairement à tsa.sh chemins), ne touche ni au cluster ni aux VM. Accord à part.
# Usage (racine du dépôt) : poc/bricks/08-trust-plane/kyverno-correctif.sh <étape>   (journal : resultats/kyverno-correctif-<étape>.log)
set -uo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
. "$here/commun.sh"
APP_DIGEST=sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # images d'essai signées en J4
K=$O/kyverno-correctif
B=$K/bin
T=$W/kyverno-correctif
PATCH=$here/kyverno-correctif/correctif-v2-final.patch
mkdir -p "$B" "$T"

go_env() { # version : environnement Go de l'étape A (chaîne du cache, modules vérifiés, go.mod en lecture seule)
  local g=$HOME/.cache/supply-chain-poc/outils/gomodcache/golang.org/toolchain@v0.0.1-$1.linux-amd64
  export GOROOT=$g PATH=$g/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org \
    GOMODCACHE=$K/gomodcache GOCACHE=$K/gocache GOPATH=$K/gopath GOENV=off GOTELEMETRY=off CGO_ENABLED=0
}

etape_construire() {
  local v g h
  for v in main:go1.27.3:2be1bc3fe3b4150501caac2c95ee58039824cdce v1.19.2:go1.26.10:e63308f1e16c05cd009ac4864be6ec25c66b49be; do
    IFS=: read -r v g h <<< "$v"
    echo "## $v ($g)"
    ( go_env "$g"; cd "$K/$v" || exit 1
      [ "$(git rev-parse HEAD)" = "$h" ] && echo "OK   tête $h" || { echo "KO   tête $(git rev-parse HEAD), attendu $h"; exit 1; }
      git apply -R --check "$PATCH" 2>/dev/null && echo "OK   correctif v2 présent (patch final applicable à l'envers)" \
        || { echo "KO   correctif v2 absent ou différent"; exit 1; }
      go build -trimpath -o "$B/kyverno-$v-v2" ./cmd/cli/kubectl-kyverno && echo "OK   construit : $B/kyverno-$v-v2"
      echo "sha256 $(sha256sum "$B/kyverno-$v-v2" | cut -c1-64)"
      "$B/kyverno-$v-v2" version 2>&1 | head -3 | sed 's/^/  /' )
  done
}

cli() { # binaire politique pod : décision (PASS, FAIL, ERREUR), code de sortie et motif (même analyse que politique.sh)
  local c=0
  SSL_CERT_FILE=$P/ca-poc.crt "$1" apply "$2" --resource "$3" --policy-report --output-format json > "$T/cli.json" 2> "$T/cli.err" || c=$?
  python3 -I -c 'import json,re,sys
t = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1]).read())
i = t.find("{")
d = json.loads(t[i:]) if i >= 0 else {}
s = d.get("summary", {})
res = "ERREUR" if s.get("error") else ("FAIL" if s.get("fail") else ("PASS" if s.get("pass") else "INDÉTERMINÉ"))
msg = "; ".join((r.get("message") or "").replace("\n", " ") for r in d.get("results", []) if r.get("result") != "pass")
print(res + "\t" + msg[:160])' "$T/cli.json" "$c"
}

motif() { # binaire politique pod : motif de vérification d'image relevé en mode verbeux (affiché, non jugé)
  SSL_CERT_FILE=$P/ca-poc.crt "$1" apply "$2" --resource "$3" -v 6 > "$T/v6.out" 2>&1 || true
  sed 's/\x1b\[[0-9;]*m//g' "$T/v6.out" | grep -o -E '(image verification failed|evaluation returned an internal error)[^"]*error="[^"]*"' | sort -u | head -2 | cut -c1-260
  echo "nil pointer dans la sortie verbeuse : $(grep -c 'nil pointer' "$T/v6.out")"
}

etape_cli() {
  local d n c e r v ko=0 x a
  echo "## préalables (lecture anonyme de Zot)"
  for d in "$DEPOT_BUNDLES" essais-j5/sans-jeton essais-j5/jeton-altere essais-j5/autre-signature essais-j5/tsa-etrangere essais-j5/aucun; do
    n=$(curl -fsS --cacert "$P/ca-poc.crt" "https://$REG_HOTE/v2/$d/referrers/$APP_DIGEST" 2>/dev/null | jq '.manifests | length' 2>/dev/null) || n="illisible"
    echo "$d : ${n:-illisible} referrer(s)"
    case "$d" in essais-j5/aucun) ;; *) [ "$n" != illisible ] && [ "$n" -ge 1 ] 2>/dev/null || { echo "NON JUGÉ : $d sans bundle, rien évalué"; exit 3; } ;; esac
  done
  for x in "$R/chains-cle-publique.pem" "$P/tsa-chaine.pem" "$P/ca-poc.crt"; do [ -s "$x" ] || { echo "NON JUGÉ : $x absent"; exit 3; }; done
  cat > "$T/pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata: {name: essai-j5, namespace: default}
spec:
  containers:
    - name: app
      image: $REG_HOTE/builds/essai-signature@$APP_DIGEST
EOF
  # cas|dépôt|chaîne|attendu CLI officiel 1.19.2|attendu CLI corrigés (prédictions, resultats/kyverno-correctif-b-predictions.md)
  printf '%s\n' "j5-temoin|horodatage/bundles||PASS|PASS" "j5-jeton-valide|horodatage/bundles|$P/tsa-chaine.pem|ERREUR|PASS" \
    "j5-sans-jeton|essais-j5/sans-jeton|$P/tsa-chaine.pem|FAIL|FAIL" "j5-aucun-bundle|essais-j5/aucun|$P/tsa-chaine.pem|FAIL|FAIL" \
    "j5-jeton-altere|essais-j5/jeton-altere|$P/tsa-chaine.pem|ERREUR|FAIL" "j5-autre-signature|essais-j5/autre-signature|$P/tsa-chaine.pem|ERREUR|FAIL" \
    "j5-tsa-etrangere|essais-j5/tsa-etrangere|$P/tsa-chaine.pem|ERREUR|FAIL" "j5-att-historique|||FAIL|FAIL" > "$T/cas.txt"
  for a in "officiel 1.19.2|$(mise which kyverno 2>/dev/null || command -v kyverno)|4" "main corrigé|$B/kyverno-main-v2|5" "v1.19.2 corrigé|$B/kyverno-v1.19.2-v2|5"; do
    IFS='|' read -r n x c <<< "$a"
    echo "## CLI $n : $x (sha256 $(sha256sum "$x" | cut -c1-16), $("$x" version 2>/dev/null | grep -m1 'Git commit' | cut -c1-40))"
    while IFS='|' read -r d r v e1 e2; do
      e=$([ "$c" = 4 ] && echo "$e1" || echo "$e2")
      ivpol "$r" "$v" "$d" > "$T/$d.yaml"
      r=$(cli "$x" "$T/$d.yaml" "$T/pod.yaml")
      if [ "${r%%$'\t'*}" = "$e" ]; then echo "OK   $d : ${r%%$'\t'*}"; else echo "KO   $d : ${r%%$'\t'*}, attendu $e (${r#*$'\t'})"; ko=1; fi
      motif "$x" "$T/$d.yaml" "$T/pod.yaml" | sed 's/^/     /'
    done < "$T/cas.txt"
  done
  [ "$ko" = 0 ] && echo "bilan : OK" || echo "bilan : KO"
  return "$ko"
}

e=${1:?usage : $0 construire|cli}
L=$R/kyverno-correctif-$e.log
[ ! -e "$L" ] || { echo "$L existe déjà, rien lancé"; exit 2; }
{ date -u "+# kyverno-correctif.sh $e, %Y-%m-%dT%H:%M:%SZ"; "etape_$e"; } 2>&1 | sed -u "s#$HOME#~#g" | tee "$L"
exit "${PIPESTATUS[0]}"
