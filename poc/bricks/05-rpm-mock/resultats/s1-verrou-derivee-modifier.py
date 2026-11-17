"""Copie modifiée de s1.sh : étape verrou_derivee (verrou avec l'image de bootstrap dérivée), insertions seules. Assertions.
Usage : python3 -I modifier.py <s1.sh du dépôt> <copie à écrire>"""
import hashlib, sys
src, dst = sys.argv[1:3]
s = open(src, encoding='utf-8').read()
assert hashlib.sha256(s.encode()).hexdigest() == '2b0a3b7b9bdd0252a6700e084095006077d0f98f8fa9c2436af6908434d153e9'
assert 'verrou_derivee' not in s and 'CFG_DERIVE' not in s and 'SONDE_CFG_DERIVEE' not in s and 'SONDE_REPLI' not in s
ancre = "# Les replis (stockage vfs, mock non root, bootstrap sans image) ne sont pas lancés ici"
assert s.count(ancre) == 1
entete = (
"#   verrou_derivee (../s1-verrou-derivee.patch, préparé à sec le 17/11/2026 à partir de 15:03:48 UTC, NON APPLIQUÉ ; image de\n"
"#               bootstrap dérivée de boot_image) : comme verrou_brut, mais configuration $CFG_DERIVE générée sur l'hôte à partir\n"
"#               de MOCK_CFG et livrée dans le pod (bootstrap_image = essais-05/rocky9-bootstrap@<digest de boot_image>,\n"
"#               bootstrap_image_ready=True) ; podman pull de l'image dérivée par le pod avant mock ; lignes de repli sans image\n"
"#               comptées ; bootstrap de mock comparé à l'image dérivée (SONDE_BOOT) ; verrou archivé\n"
"#               (resultats/s1-verrou_derivee.json), comparé à celui de verrou_brut ; rien poussé\n")
s = s.replace(ancre, entete + ancre)
fin = 'lancer "$PREFIXE" "05 S1" "$@"\n'
assert s.endswith(fin) and s.count(fin) == 1
# Ancres : chaque motif que les sed de l'étape remplacent doit être dans la variable visée, au nombre de fois attendu.
def corps(nom, q="'", f="\ntrue'\n"):
    assert s.count(nom + '=' + q) == 1, nom
    i = s.index(nom + '=' + q); j = s.index(f, i)
    return s[i:j]
mc, sv, sb = corps('MOCK_CFG', '"', '\n"\n'), corps('SONDE_VERROU'), corps('SONDE_BOOT')
for v, motif, n in [(mc, "'root'] = '$CFG'", 1), (mc, "'bootstrap_image'] = '$BOOT'", 1), (mc, "'bootstrap_image_ready'] = False", 1),
                    (sv, "(image prête)", 1), (sv, "--resultdir=/w/res-verrou --calculate-build-dependencies ", 1),
                    (sv, "@CFG_PRET@", 4), (sb, "de rockylinux:9.7 brut", 1), (sb, "dans rockylinux:9.7 brut", 1),
                    (sb, "rockylinux:9.7 brut lu", 1), (sb, "rockylinux:9.7 brut", 5), (sb, "-brut.", 4)]:
    assert v.count(motif) == n, (motif, v.count(motif))
bloc = r'''# Étape verrou_derivee (ajoutée à sec le 17/11/2026 à partir de 15:03:48 UTC, NON LANCÉE) : la sonde de verrou avec l'image de
# bootstrap dérivée (décision « Dix lignes », poussée par boot_image) marquée prête. L'image d'essai ne porte que $CFG et $CFG_PRET,
# tous deux sur rockylinux:9.7 brut : une troisième configuration, $CFG_DERIVE, est générée sur l'hôte à partir de MOCK_CFG
# (racine, bootstrap_image et bootstrap_image_ready changés, rien d'autre : six lignes de diff) et livrée sous /etc/mock ; le pod
# vérifie que sa configuration de base est bien MOCK_CFG, par sha256 (diff n'est pas dans l'image d'essai : tar -tf de racine.tar).
# Avec une image prête, mock ne doit rien installer dans le bootstrap (buildroot.py:590, lecture) : mesuré par SONDE_BOOT,
# bootstrap de mock (--no-cleanup-after) contre image dérivée montée. Avant mock, le pod tire lui-même l'image dérivée (lecture
# anonyme de essais-05/ jamais mesurée) : un échec arrête l'étape, car mock, bootstrap_image_fallback à True par défaut
# (config.py:110), installerait sinon le bootstrap sans image, et le calcul ne mesurerait plus l'image dérivée. Le repli est
# signalé par un avertissement (buildroot.py:307) du logger mockbuild.buildroot, enfant de mockbuild qui porte root.log
# (trace_decorator.py:18 à :29, buildroot.py:125 et :692, lecture) : SONDE_REPLI le cherche dans root.log et dans les deux
# sorties de mock. Le verrou est comparé à celui de verrou_brut (rpm du buildroot).
# Non mesuré ici : --hermetic-build (M2) ; config.py:844 coupe bootstrap_image au premier « : », à lire avant M2.
# SONDE_VERROU, SONDE_BOOT et les étapes existantes ne changent pas ; journaux distincts : s1-verrou_derivee*.
CFG_DERIVE=poc-rocky-9.7-derivee-x86_64   # étape verrou_derivee : livrée dans le pod, bootstrap = image dérivée, prête
SONDE_CFG_DERIVEE='set -u
echo "configuration de base, image du pod : sha256 $(sha256sum < /etc/mock/@CFG@.cfg | cut -c1-64)"
echo "configuration dérivée livrée : sha256 $(sha256sum < /etc/mock/@CFG_DERIVE@.cfg | cut -c1-64)"
mock -r @CFG_DERIVE@ --debug-config > /w/derivee-debug-config.log 2>&1; echo "mock --debug-config : rc $?"
grep -E "^config_opts\[.(root|bootstrap_image|bootstrap_image_ready|bootstrap_image_fallback|bootstrap_image_assert_digest).\]" \
  /w/derivee-debug-config.log | sed "s/^/configuration lue par mock : /"
t=$(date +%s); podman pull @DERIVEE@ > /w/pull-derivee.log 2>&1; r=$?
echo "podman pull, image dérivée : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || tail -n 5 /w/pull-derivee.log
podman image inspect --format "image dérivée, inspect : {{.Digest}} {{.Os}}/{{.Architecture}}" @DERIVEE@ 2>&1 | tail -n 1
true'
SONDE_REPLI='for f in /w/res-verrou/root.log /w/verrou-srpm.log /w/verrou-calc.log; do
  c=$(grep -c "falling back to chroot installation" "$f" 2>/dev/null); echo "${f#/w/} : ${c:-fichier absent} ligne(s) de repli sans image"
done
true'

etape_verrou_derivee() {
  local d bd img n=s1-05-verrou-derivee f c=$T/$CFG_DERIVE.cfg
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  bd=$(cat "$T/boot-image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape boot_image" >&2; exit 1; }
  [[ $bd =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "KO   digest de boot_image illisible : $bd" >&2; exit 1; }
  [ -s "$R/s1-verrou_brut.json" ] || { echo "KO   verrou de référence absent : resultats/s1-verrou_brut.json" >&2; exit 1; }
  img=$REG/$DEPOT_ESSAI@$d
  printf '%s' "$MOCK_CFG" > "$T/$CFG.cfg"
  printf '%s' "$MOCK_CFG" | sed -e "s|'root'\] = '$CFG'|'root'] = '$CFG_DERIVE'|" \
    -e "s|'bootstrap_image'\] = '$BOOT'|'bootstrap_image'] = '$REG/$DEPOT_DERIVE@$bd'|" \
    -e "s|'bootstrap_image_ready'\] = False|'bootstrap_image_ready'] = True|" > "$c"
  attendu "configuration dérivée : racine, bootstrap_image et bootstrap_image_ready changés, rien d'autre" \
    "$(diff "$T/$CFG.cfg" "$c" | grep -c '^[<>]')" 6
  { diff "$T/$CFG.cfg" "$c" || true; } | grep '^[<>]' | sed 's/^/écart prévu : /'
  echo "configuration dérivée : sha256 $(sha256sum < "$c" | cut -c1-64)"
  echo "image : $img ; isolation : $ISOLATION ; configuration : $CFG_DERIVE (bootstrap_image_ready=True)"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$n" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$n" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  livrer "$n" "/etc/mock/$CFG_DERIVE.cfg" "$c"
  sed -e "s|@CFG@|$CFG|g" -e "s|@CFG_DERIVE@|$CFG_DERIVE|g" -e "s|@DERIVEE@|$REG/$DEPOT_DERIVE@$bd|g" <<<"$SONDE_CFG_DERIVEE" \
    | dans "$n" verrou-derivee-cfg
  ( attendu "configuration de base du pod égale à MOCK_CFG de s1.sh" "$(champ verrou-derivee-cfg 'configuration de base, image du pod')" \
      "sha256 $(sha256sum < "$T/$CFG.cfg" | cut -c1-64)"
    attendu "configuration dérivée livrée dans le pod" "$(champ verrou-derivee-cfg 'configuration dérivée livrée')" \
      "sha256 $(sha256sum < "$c" | cut -c1-64)"
    attendu "podman pull de l'image dérivée par le pod" "$(champ verrou-derivee-cfg 'podman pull, image dérivée' | cut -d' ' -f1-2)" "rc 0" ) \
    || { pod_retirer "$n"; exit 1; }
  sed -e "s|@CFG_PRET@|$CFG_DERIVE|g" -e "s|@ISO@|$ISOLATION|g" -e "s|(image prête)|(image dérivée)|" \
    -e "s|--resultdir=/w/res-verrou --calculate-build-dependencies |--resultdir=/w/res-verrou --calculate-build-dependencies --no-cleanup-after |" \
    <<<"$SONDE_VERROU" | dans "$n" verrou-derivee
  dans "$n" verrou-derivee-repli <<<"$SONDE_REPLI"
  sed -e "s|@CFG@|$CFG_DERIVE|g" -e "s|@BOOT@|$REG/$DEPOT_DERIVE@$bd|g" -e "s|de rockylinux:9\.7 brut|de l'image dérivée|g" \
    -e "s|dans rockylinux:9\.7 brut|dans l'image dérivée|g" -e "s|rockylinux:9\.7 brut lu|image dérivée lue|g" \
    -e "s|rockylinux:9\.7 brut|image dérivée|g" -e "s|-brut\.|-derivee.|g" <<<"$SONDE_BOOT" | dans "$n" verrou-derivee-boot
  kubectl exec -n builds "$n" -- sh -c 'for f in /w/res-verrou/root.log /w/res-verrou/build.log; do [ -e "$f" ] && { echo "### $f"; tail -n 400 "$f"; }; done
    for f in /w/verrou-srpm.log /w/verrou-calc.log; do [ -e "$f" ] && { echo "### $f"; tail -n 60 "$f"; }; done; true' \
    </dev/null 2>&1 | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-verrou_derivee-mock.log" || true
  echo "journaux de mock : $(wc -l < "$R/$PREFIXE-verrou_derivee-mock.log") lignes, resultats/$PREFIXE-verrou_derivee-mock.log"
  f=$(kubectl exec -n builds "$n" -- sh -c 'ls /w/res-verrou/*.json 2>/dev/null | head -1' </dev/null || true)
  if [ -n "$f" ]; then
    kubectl exec -n builds "$n" -- cat "$f" </dev/null | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-verrou_derivee.json" \
      || echo "copie du verrou : code non nul"
    python3 -I - "$R/$PREFIXE-verrou_derivee.json" <<'PY' || echo "résumé du verrou en échec : rc $?"
import json, sys
from urllib.parse import urlsplit
d = json.load(open(sys.argv[1], encoding='utf-8'))
c = d.get('config', {})
print('version du verrou :', d.get('version'))
print('options de configuration recopiées :', ', '.join(sorted(c)))
print('bootstrap_image enregistré :', c.get('bootstrap_image'))
print('bootstrap_image_ready enregistré :', c.get('bootstrap_image_ready'))
print('macros recopiées :', 'oui' if any('macro' in k for k in c) else 'non')
bs = d.get('bootstrap', {})
print('bootstrap, champs :', ', '.join(sorted(bs)) if bs else 'aucun (PodmanError attrapée, ou use_bootstrap_image faux)')
print('bootstrap, pull_digest (digest du manifeste tiré) :', bs.get('pull_digest'))
print('bootstrap, image_digest (sha256 de RootFS et Config, podman.py:21) :', bs.get('image_digest'))
print('bootstrap, architecture :', bs.get('architecture'))
b = d.get('buildroot', {}).get('rpms', [])
print('rpm du buildroot :', len(b), '; champs :', ', '.join(sorted(b[0])) if b else '-')
u = [r.get('url') for r in b]
print('rpm avec url :', sum(1 for x in u if x), 'sur', len(b))
print('préfixes des url :', ', '.join(sorted({urlsplit(x).netloc + urlsplit(x).path.rsplit('/', 1)[0] for x in u if x})) or '-')
g = sorted({str(r.get('signature')) for r in b})
print('valeurs distinctes de signature :', len(g), ';', ', '.join(g[:5]))
PY
    python3 -I - "$R/$PREFIXE-verrou_derivee.json" "$R/s1-verrou_brut.json" "$bd" <<'PY' || echo "comparaison avec verrou_brut en échec : rc $?"
import json, sys
a, b = (json.load(open(f, encoding='utf-8')) for f in sys.argv[1:3])
p = a.get('bootstrap', {}).get('pull_digest')
print('bootstrap, pull_digest égal au digest de boot_image :', 'oui' if p == sys.argv[3] else 'non (%s)' % p)
ca, cb = a.get('config', {}), b.get('config', {})
print('options de configuration différentes de verrou_brut :', ', '.join(sorted(k for k in set(ca) | set(cb) if ca.get(k) != cb.get(k))) or 'aucune')
k = lambda r: (r.get('name'), r.get('epoch'), r.get('version'), r.get('release'), r.get('arch'), r.get('sigmd5'), r.get('url'))
la, lb = a.get('buildroot', {}).get('rpms', []), b.get('buildroot', {}).get('rpms', [])
ra, rb = {k(r) for r in la}, {k(r) for r in lb}
print(f'rpm du buildroot (nom, epoch, version, release, arch, sigmd5, url) : ici {len(la)}, verrou_brut {len(lb)} ; communs {len(ra & rb)} ;'
      f' seulement ici {len(ra - rb)} ; seulement dans verrou_brut {len(rb - ra)}')
for x in sorted(ra - rb, key=str)[:10]: print('seulement ici :', x)
for x in sorted(rb - ra, key=str)[:10]: print('seulement dans verrou_brut :', x)
PY
  else echo "aucun verrou produit"; fi
  pod_retirer "$n"
}

'''
s = s[:-len(fin)] + bloc + fin
open(dst, 'w', encoding='utf-8').write(s)
print('copie :', hashlib.sha256(s.encode()).hexdigest())
