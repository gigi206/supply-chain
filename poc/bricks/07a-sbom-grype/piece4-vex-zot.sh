#!/usr/bin/env bash
# Brique 07b, pose, pièce 4 : dépôt builds/vex/** dans Zot, lecture anonyme, compte d'écriture poc-vex réservé au propriétaire et
# seul autorisé à y écrire (choix du propriétaire du 23/11/2026 : « Oui, compte seul »). Entrée builds/vex/** de
# 08-trust-plane/stockage/zot.json (motif le plus long, qui remplace builds/**), bloc htpasswd de poc-vex dans stockage.sh (calqué
# sur poc-lien).
#   compte  mot de passe de poc-vex (48 hexadécimaux, généré ici, mode 600) et ligne htpasswd (bcrypt, coût 12) dans 07a/secrets ;
#           refuse si l'un existe ; ni le mot de passe ni le hash ne sont affichés
#   sec     aucun accès au vrai Zot ni à la VM : Zot 2.1.22 jetable sur 127.0.0.1 (TLS jetable), avec le zot.json du dépôt (seuls les
#           chemins, l'adresse et le certificat changent) ; htpasswd : ligne réelle de poc-vex, comptes témoins à mots de passe
#           jetables ; publication d'un referrer comme publier de scanner.sh (blob push puis manifest push par digest) ;
#           contrôles : qui écrit et qui est refusé sous builds/vex/**, lecture anonyme, référents d'un dépôt absent (code HTTP),
#           non-régression de builds/** et de builds/scan/**
# Usage (racine du dépôt) : mise exec -- poc/bricks/07a-sbom-grype/piece4-vex-zot.sh compte | sec   (journal : resultats/piece4-<étape>.log)
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
R=$here/resultats
RACINE=$(git -C "$here" rev-parse --show-toplevel)
O=$HOME/.cache/supply-chain-poc
S7=$O/07a/secrets
ZOT_JSON=$RACINE/poc/bricks/08-trust-plane/stockage/zot.json
ZOT_SHA=33b9b5bfe05d6788c076de951a01920477dbd6395c330146e23cc2340073e52e   # mise.lock, zot v2.1.22 (stockage.sh)
e=${1:-}
case $e in compte|sec) ;; *) echo "usage : $0 compte | sec" >&2; exit 64 ;; esac
L=$R/piece4-$e.log
[ ! -e "$L" ] || { echo "journal déjà présent : $L (les journaux ne sont jamais réécrits)" >&2; exit 1; }
T=$O/07a/piece4-$e
ko=0
ok() { echo "OK   $*"; }
attendu() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else echo "KO   $1 : $2 (attendu : $3)"; ko=1; fi; }

{
echo "# piece4-vex-zot.sh $e, $(date -u +%Y-%m-%dT%H:%M:%SZ) ; dépôt $(git -C "$here" rev-parse --short=8 HEAD) ; zot.json $(sha256sum < "$ZOT_JSON" | cut -c1-16)"
case $e in
  compte)
    M=$S7/zot-poc-vex.password; H=$S7/zot-poc-vex.htpasswd
    [ -d "$S7" ] || { echo "KO   dossier 07a/secrets absent"; exit 1; }
    if [ -e "$M" ] || [ -e "$H" ]; then echo "KO   mot de passe ou ligne htpasswd de poc-vex déjà présent"; exit 1; fi
    (umask 077 && openssl rand -hex 24 | tr -d '\n' > "$M")
    (umask 077 && printf 'poc-vex:%s\n' "$(mkpasswd -m bcrypt -R 12 -s < "$M")" > "$H")
    attendu "mot de passe : 48 hexadécimaux, mode 600" "$(grep -cxE '[0-9a-f]{48}' "$M") $(stat -c %a "$M")" "1 600"
    attendu "ligne htpasswd : motif de stockage.sh, mode 600" "$(grep -cxE 'poc-vex:\$2b\$12\$[./A-Za-z0-9]{53}' "$H") $(stat -c %a "$H")" "1 600"
    attendu "hash vérifié indépendamment (mkpasswd avec le sel)" \
      "$([ "poc-vex:$(mkpasswd -m bcrypt -R 12 -S "$(cut -c16-37 "$H")" -s < "$M")" = "$(cat "$H")" ] && echo oui)" oui
    attendu "un autre mot de passe ne donne pas ce hash" \
      "$([ "poc-vex:$(printf autre | mkpasswd -m bcrypt -R 12 -S "$(cut -c16-37 "$H")" -s)" != "$(cat "$H")" ] && echo oui)" oui ;;
  sec)
    rm -rf -- "${T:?}" && (umask 077 && mkdir -p "$T/stockage" "$T/auth")
    trap 'kill "${zp:-0}" 2>/dev/null || true; wait "${zp:-0}" 2>/dev/null || true; rm -rf -- "$T"' EXIT
    z=$(type -P zot)
    attendu "binaire zot (mise.lock)" "$(sha256sum < "$z" | cut -c1-64)" "$ZOT_SHA"
    attendu "zot verify sur le zot.json du dépôt" "$(zot verify "$ZOT_JSON" 2>&1 | grep -c 'config file is valid')" 1
    attendu "entrée builds/vex/** du dépôt" "$(jq -c '.http.accessControl.repositories["builds/vex/**"] | [.anonymousPolicy, [.policies[] | [.users, .actions, (.conditions // [] | map(.expression))]]]' "$ZOT_JSON")" \
      '[["read"],[[["poc-vex"],["read"],[]],[["poc-vex"],["create"],["req.referenceType != \"tag\""]]]]'
    # TLS jetable (127.0.0.1)
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 \
      -keyout "$T/tls.key" -out "$T/tls.crt" 2> /dev/null
    CA=$T/tls.crt
    # htpasswd : ligne réelle de poc-vex ; témoins à mots de passe jetables
    grep -qxE 'poc-vex:\$2b\$12\$[./A-Za-z0-9]{53}' "$S7/zot-poc-vex.htpasswd" || { echo "KO   ligne htpasswd de poc-vex absente ou inattendue (étape compte)"; exit 1; }
    (umask 077 && cat "$S7/zot-poc-vex.htpasswd" > "$T/htpasswd")
    for c in poc-ecriture poc-build poc-images poc-scan; do
      (umask 077 && openssl rand -hex 24 | tr -d '\n' > "$T/auth/$c.password" && printf '%s:%s\n' "$c" "$(mkpasswd -m bcrypt -R 12 -s < "$T/auth/$c.password")" >> "$T/htpasswd")
    done
    (umask 077 && openssl rand -hex 24 | tr -d '\n' > "$T/auth/faux.password")
    cfg() { # compte fichier-de-mot-de-passe : configuration d'oras (format docker)
      (umask 077 && printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REGL" "$(printf '%s:%s' "$1" "$(cat "$2")" | base64 -w0)" > "$T/auth/$1-$(basename "$2" .password).json")
      echo "$T/auth/$1-$(basename "$2" .password).json"
    }
    port=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    REGL=127.0.0.1:$port
    jq --arg r "$T/stockage" --arg p "$port" --arg c "$T/tls.crt" --arg k "$T/tls.key" --arg h "$T/htpasswd" --arg l "$T/zot.log" --arg a "$T/audit.log" \
      '.storage.rootDirectory = $r | .http.address = "127.0.0.1" | .http.port = $p | .http.tls = {cert: $c, key: $k} | .http.auth.htpasswd.path = $h
       | .log.output = $l | (if .log.audit then .log.audit = $a else . end)' "$ZOT_JSON" > "$T/zot.json"
    echo "configuration jetable : zot.json du dépôt, seuls changent $(jq -cn --argjson a "$(cat "$ZOT_JSON")" --argjson b "$(cat "$T/zot.json")" \
      '[$b | paths(scalars)] | map(select(($a | getpath(.)) != ($b | getpath(.))) | map(tostring) | join(".")) | join(", ")')"
    attendu "accessControl jetable = dépôt" "$(jq -S -c .http.accessControl "$T/zot.json" | sha256sum | cut -c1-16)" "$(jq -S -c .http.accessControl "$ZOT_JSON" | sha256sum | cut -c1-16)"
    attendu "zot verify sur la configuration jetable" "$(zot verify "$T/zot.json" 2>&1 | grep -c 'config file is valid')" 1
    zot serve "$T/zot.json" > "$T/zot.out" 2>&1 & zp=$!
    c=000; for i in $(seq 1 100); do c=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" "https://$REGL/v2/" || true); [ "$c" = 200 ] && break; sleep 0.1; done
    attendu "Zot jetable : /v2/ en anonyme" "$c" 200
    code() { curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" "$@"; }
    V=$(cfg poc-vex "$S7/zot-poc-vex.password"); E=$(cfg poc-ecriture "$T/auth/poc-ecriture.password"); B=$(cfg poc-build "$T/auth/poc-build.password")
    I=$(cfg poc-images "$T/auth/poc-images.password"); SC=$(cfg poc-scan "$T/auth/poc-scan.password"); F=$(cfg poc-vex "$T/auth/faux.password")
    o() { local c=$1; shift; oras "$@" --ca-file "$CA" --registry-config "$c"; }
    # Sujet : un petit artefact dans builds/sample-app, poussé par poc-ecriture (comme une image de la plateforme)
    (cd "$T" && printf 'sujet\n' > sujet.txt && o "$E" push "$REGL/builds/sample-app:essai" sujet.txt:text/plain > /dev/null 2>&1) && ok "sujet poussé dans builds/sample-app (poc-ecriture)" || { echo "KO   sujet"; ko=1; }
    o "$E" manifest fetch --descriptor "$REGL/builds/sample-app:essai" > "$T/sujet.json" 2>/dev/null
    SUJ=$(jq -r .digest "$T/sujet.json"); echo "sujet : $SUJ"
    echo "  référents d'un dépôt absent : HTTP $(code "https://$REGL/v2/builds/vex/sample-app/referrers/$SUJ") ; liste des tags : HTTP $(code "https://$REGL/v2/builds/vex/sample-app/tags/list")"
    publier() { # config-oras dépôt n° : referrer comme publier de scanner.sh ; écrit « code-oras étape »
      local c=$1 d=$2 n=$3 f
      f=$T/pub-$(printf %s "$n" | tr -c "A-Za-z0-9-" _)
      mkdir -p "$f"; printf '{}' > "$f/config-vide.json"; printf '{"vex":"%s"}' "$n" > "$f/bundle.json"
      (cd "$f" && o "$c" blob push "$REGL/$d" config-vide.json > /dev/null 2> err) || { echo "refus blob $(grep -oE '403|401|denied|unauthorized|forbidden' "$f/err" | head -1)"; return 0; }
      (cd "$f" && o "$c" blob push "$REGL/$d" bundle.json > /dev/null 2> err) || { echo "refus blob $(grep -oE '403|401|denied|unauthorized|forbidden' "$f/err" | head -1)"; return 0; }
      printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","artifactType":"application/vnd.dev.sigstore.bundle.v0.3+json","config":{"mediaType":"application/vnd.oci.empty.v1+json","digest":"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","size":2},"layers":[{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json","digest":"sha256:%s","size":%s}],"subject":%s}' \
        "$(sha256sum < "$f/bundle.json" | cut -c1-64)" "$(wc -c < "$f/bundle.json")" "$(cat "$T/sujet.json")" > "$f/manifeste.json"
      local m=sha256:$(sha256sum < "$f/manifeste.json" | cut -c1-64)
      (cd "$f" && o "$c" manifest push "$REGL/$d@$m" manifeste.json > /dev/null 2> err) || { echo "refus manifeste $(grep -oE '403|401|denied|unauthorized|forbidden' "$f/err" | head -1)"; return 0; }
      echo "publié $m"
    }
    nref() { curl -s --cacert "$CA" "https://$REGL/v2/$1/referrers/$SUJ" | jq '.manifests | length'; }
    r=$(publier "$V" builds/vex/sample-app 1); echo "poc-vex, builds/vex/sample-app, par digest : $r"
    case $r in publié*) ok "poc-vex publie un referrer par digest dans builds/vex/sample-app" ;; *) echo "KO   poc-vex refusé dans builds/vex/sample-app"; ko=1 ;; esac
    attendu "anonyme : référents de builds/vex/sample-app après publication" "$(nref builds/vex/sample-app)" 1
    attendu "anonyme : manifeste du referrer lisible" "$(code "https://$REGL/v2/builds/vex/sample-app/manifests/${r#publié }")" 200
    for x in "poc-ecriture:$E" "poc-build:$B" "poc-images:$I" "poc-scan:$SC" "poc-vex, mauvais mot de passe:$F"; do
      r=$(publier "${x##*:}" builds/vex/sample-app "${x%%:*}"); case $r in refus*) ok "${x%%:*} refusé dans builds/vex/sample-app : $r" ;; *) echo "KO   ${x%%:*} accepté dans builds/vex/sample-app : $r"; ko=1 ;; esac
    done
    (umask 077 && echo '{}' > "$T/auth/anonyme.json")
    r=$(publier "$T/auth/anonyme.json" builds/vex/sample-app anonyme); case $r in refus*) ok "anonyme refusé dans builds/vex/sample-app : $r" ;; *) echo "KO   anonyme accepté : $r"; ko=1 ;; esac
    attendu "référents de builds/vex/sample-app après les refus" "$(nref builds/vex/sample-app)" 1
    (cd "$T" && printf 'tag\n' > tag.txt && o "$V" push "$REGL/builds/vex/sample-app:essai" tag.txt:text/plain > /dev/null 2> "$T/err-tag") \
      && { echo "KO   poc-vex pousse un tag dans builds/vex/sample-app"; ko=1; } || ok "poc-vex refusé pour un tag : $(grep -oE '403|denied|forbidden|tag' "$T/err-tag" | head -1)"
    for d in builds/scan/sample-app builds/autre signes/essai vulndb/grype; do
      r=$(publier "$V" "$d" "vex-$d"); case $r in refus*) ok "poc-vex refusé dans $d : $r" ;; *) echo "KO   poc-vex accepté dans $d : $r"; ko=1 ;; esac
    done
    attendu "poc-vex : suppression du referrer refusée (code HTTP)" "$(printf 'user = "poc-vex:%s"\n' "$(cat "$S7/zot-poc-vex.password")" | curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" -K - -X DELETE \
      "https://$REGL/v2/builds/vex/sample-app/manifests/$(curl -s --cacert "$CA" "https://$REGL/v2/builds/vex/sample-app/referrers/$SUJ" | jq -r '.manifests[0].digest')")" 403
    # Non-régression : builds/** et builds/scan/** inchangés pour leurs comptes
    r=$(publier "$B" builds/autre build); case $r in publié*) ok "poc-build publie toujours dans builds/autre" ;; *) echo "KO   poc-build refusé dans builds/autre : $r"; ko=1 ;; esac
    r=$(publier "$SC" builds/scan/sample-app scan); case $r in publié*) ok "poc-scan publie toujours dans builds/scan/sample-app" ;; *) echo "KO   poc-scan refusé dans builds/scan/sample-app : $r"; ko=1 ;; esac
    r=$(publier "$E" builds/autre ecriture); case $r in publié*) ok "poc-ecriture publie toujours dans builds/autre" ;; *) echo "KO   poc-ecriture refusé dans builds/autre : $r"; ko=1 ;; esac
    attendu "mot de passe de poc-vex absent des sorties de Zot" "$(grep -c -F -f "$S7/zot-poc-vex.password" "$T/zot.out" "$T/zot.log" 2>/dev/null | awk -F: '{s += $NF} END {print s + 0}')" 0 ;;
esac
echo "# fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$ko" = 0 ] && echo "bilan : tenue" || echo "bilan : KO"
exit "$ko"
} > "$L" 2>&1
k=$?
sed -i '/jeton\|token/I c\[ligne masquée : motif jeton|token]' "$L"
cat "$L"
exit "$k"
