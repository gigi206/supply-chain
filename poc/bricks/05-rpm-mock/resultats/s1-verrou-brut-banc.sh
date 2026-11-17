#!/usr/bin/env bash
# Banc hors réseau de l'étape verrou_brut (s1-verrou-brut.patch, décision « Mesurer d'abord »), écrit le 17/11/2026 avant tout
# passage. Ni cluster, ni Zot, ni réseau.
# A : insertions seules ; la copie, blocs insérés retirés, redonne le s1.sh du dépôt octet pour octet.
# B : bash -n ; shellcheck : remarques de la copie comparées à celles du dépôt.
# C : sonde de verrou_brut rendue par les lignes sed de la copie : comparée au rendu de verrou avec la même configuration, seules
#     les lignes de --buildsrpm (libellé) et de --calculate-build-dependencies (--no-cleanup-after) changent ; sh -n.
# D : SONDE_BOOT rendue, /w remplacé par un dossier du banc, rpm et podman remplacés par des doublures : sortie de comm contrôlée.
# E : résumé Python du verrou lancé sur deux verrous fictifs (avec et sans bootstrap).
# Non couvert : vrai pod, vrai mock, vrai rpm, vrai podman, kubectl.
# Usage : banc-brut.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier de travail, vidé>
set -uo pipefail
export LC_ALL=C
D=$1; S1N=$2; B=$3
S1A=$D/poc/bricks/05-rpm-mock/s1.sh
rm -rf -- "${B:?}"; mkdir -p "$B"
echo "# banc-brut.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# s1.sh du dépôt $(sha256sum < "$S1A" | cut -c1-64) ; copie modifiée $(sha256sum < "$S1N" | cut -c1-64)"
ko=0
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
egal() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else nok "$1 : $2 (attendu : $3)"; fi; }

echo "## A : insertions seules"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées" "$(grep -c '^<' "$B/diff.txt")" 0
egal "blocs insérés" "$(grep -c -E '^[0-9]+a[0-9]+(,[0-9]+)?$' "$B/diff.txt")" 2
python3 -I - "$S1A" "$S1N" <<'PY' || ko=1
import sys
a, n = (open(f, encoding='utf-8').read() for f in sys.argv[1:3])
d = n.index('#   verrou_brut '); f = n.index('# Les replis (stockage vfs')
e = n.index('# Étape verrou_brut '); g = n.index('lancer "$PREFIXE" "05 S1" "$@"\n')
r = n[:d] + n[f:e] + n[g:]
print('OK   copie sans les blocs insérés égale au dépôt' if r == a else 'KO   copie sans les blocs insérés différente du dépôt')
print('     en-tête inséré :', n[d:f].count('\n'), 'lignes ; bloc inséré :', n[e:g].count('\n'), 'lignes')
sys.exit(0 if r == a else 1)
PY

echo "## B : syntaxe et shellcheck"
bash -n "$S1N" && ok "bash -n de la copie" || nok "bash -n de la copie"
shellcheck -f gcc "$S1A" 2>/dev/null | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort | uniq -c > "$B/sc-avant.txt"
shellcheck -f gcc "$S1N" 2>/dev/null | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort | uniq -c > "$B/sc-apres.txt"
echo "     remarques shellcheck : dépôt $(awk '{s+=$1} END {print s+0}' "$B/sc-avant.txt"), copie $(awk '{s+=$1} END {print s+0}' "$B/sc-apres.txt")"
diff "$B/sc-avant.txt" "$B/sc-apres.txt" | sed 's/^/     diff shellcheck : /'
egal "remarques shellcheck SC1112 (guillemet typographique) dans la copie" "$(grep -c SC1112 "$B/sc-apres.txt")" 0
egal "remarques shellcheck de niveau error dans la copie" "$(shellcheck -S error -f gcc "$S1N" 2>/dev/null | wc -l)" 0

echo "## C : sonde de verrou_brut"
python3 -I - "$S1N" "$B" <<'PY' || ko=1
import sys
n = open(sys.argv[1], encoding='utf-8').read(); B = sys.argv[2]
i = n.index("SONDE_VERROU='"); j = n.index("\ntrue'\n", i) + len("\ntrue'\n")
open(f'{B}/sonde-verrou.txt', 'w', encoding='utf-8').write(n[i + len("SONDE_VERROU='"):j - 2])
k = n.index('etape_verrou_brut() {'); deb = n.index('  sed -e "s|@CFG_PRET@|$CFG|g"', k); fin = n.index('<<<"$SONDE_VERROU" | dans "$n" verrou-brut\n', deb)
open(f'{B}/rendu-brut.sh', 'w', encoding='utf-8').write(n[deb:fin] + '<<<"$SONDE_VERROU"\n')
PY
for v in CFG CFG_PRET ISOLATION; do grep -E "^$v=" "$S1N" | head -1; done > "$B/vars.sh"
grep -c . "$B/vars.sh" | sed 's/^/     variables extraites : /'
( . "$B/vars.sh"; SONDE_VERROU=$(cat "$B/sonde-verrou.txt"); . "$B/rendu-brut.sh" ) > "$B/sonde-brut.txt"
( . "$B/vars.sh"; sed -e "s|@CFG_PRET@|$CFG|g" -e "s|@ISO@|$ISOLATION|g" <<<"$(cat "$B/sonde-verrou.txt")" ) > "$B/sonde-verrou-meme-cfg.txt"
egal "marqueurs @ restants" "$(grep -c '@[A-Z_]*@' "$B/sonde-brut.txt")" 0
egal "--no-cleanup-after" "$(grep -c -- '--no-cleanup-after' "$B/sonde-brut.txt")" 1
egal "ligne du calcul" "$(grep -c -- '^mock -r poc-rocky-9.7-x86_64 --isolation=simple --resultdir=/w/res-verrou --calculate-build-dependencies --no-cleanup-after "\$s" > /w/verrou-calc.log 2>&1$' "$B/sonde-brut.txt")" 1
egal "libellé image brute" "$(grep -c '(image brute)' "$B/sonde-brut.txt")" 1
egal "configuration prête absente" "$(grep -c 'pret' "$B/sonde-brut.txt")" 0
diff "$B/sonde-verrou-meme-cfg.txt" "$B/sonde-brut.txt" > "$B/diff-sonde.txt"
egal "lignes changées contre verrou (même configuration)" "$(grep -c '^[<>]' "$B/diff-sonde.txt")" 4
sed 's/^/     /' "$B/diff-sonde.txt"
sh -n "$B/sonde-brut.txt" && ok "sh -n de la sonde rendue" || nok "sh -n de la sonde rendue"

echo "## D : SONDE_BOOT avec doublures"
python3 -I - "$S1N" "$B" <<'PY' || ko=1
import sys
n = open(sys.argv[1], encoding='utf-8').read(); B = sys.argv[2]
i = n.index("SONDE_BOOT='"); j = n.index("\ntrue'\n", i) + len("\ntrue'\n")
open(f'{B}/sonde-boot.txt', 'w', encoding='utf-8').write(n[i + len("SONDE_BOOT='"):j - 2])
PY
mkdir -p "$B/w/mock/poc-rocky-9.7-x86_64-bootstrap/root" "$B/w/image" "$B/bin"
cat > "$B/bin/rpm" <<'R'
#!/bin/sh
case "$2" in
  *-bootstrap/root) printf 'rpm.x86_64 0:4.16.1.3-39.el9 RSA/SHA256, k 702d426d350d275d\npython3-dnf.noarch 0:4.14.0-31.el9 RSA/SHA256, k 702d426d350d275d\npython3-dnf-plugins-core.noarch 0:4.3.0-24.el9 RSA/SHA256, k 702d426d350d275d\n' ;;
  */image) printf 'python3-dnf.noarch 0:4.14.0-31.el9 RSA/SHA256, k 702d426d350d275d\nrpm.x86_64 0:4.16.1.3-39.el9 RSA/SHA256, k 702d426d350d275d\nyum.noarch 0:4.14.0-31.el9 RSA/SHA256, k 702d426d350d275d\n' ;;
esac
R
printf '#!/bin/sh\ncase "$1 $2" in "image mount") echo "%s/w/image" ;; esac\nexit 0\n' "$B" > "$B/bin/podman"
chmod +x "$B/bin/rpm" "$B/bin/podman"
sed -e "s|@CFG@|poc-rocky-9.7-x86_64|g" -e "s|@BOOT@|exemple.test/r@sha256:0|g" -e "s|/w/|$B/w/|g" -e "s|df -k /w |df -k $B/w |" "$B/sonde-boot.txt" > "$B/sonde-boot-rendue.txt"
egal "marqueurs @ restants (SONDE_BOOT)" "$(grep -c '@[A-Z_]*@' "$B/sonde-boot-rendue.txt")" 0
sh -n "$B/sonde-boot-rendue.txt" && ok "sh -n de SONDE_BOOT rendue" || nok "sh -n de SONDE_BOOT rendue"
PATH=$B/bin:$PATH sh "$B/sonde-boot-rendue.txt" > "$B/boot.out" 2>&1; egal "code de SONDE_BOOT" "$?" 0
sed 's/^/     /' "$B/boot.out"
egal "seulement dans le bootstrap" "$(grep -c '^seulement dans le bootstrap de mock : python3-dnf-plugins-core.noarch 0:4.3.0-24.el9 ' "$B/boot.out")" 1
egal "seulement dans rockylinux:9.7 brut" "$(grep -c '^seulement dans rockylinux:9.7 brut : yum.noarch ' "$B/boot.out")" 1
egal "lignes communes" "$(sed -n 's/^lignes communes : //p' "$B/boot.out")" 2
egal "chemin du bootstrap retenu" "$(grep -c '^bootstrap préparé par mock : 1 chemin(s) pour .* ; retenu : .*/w/mock/poc-rocky-9.7-x86_64-bootstrap/root$' "$B/boot.out")" 1
egal "ligne df en fin de SONDE_BOOT" "$(tail -n 1 "$B/boot.out" | grep -c '^capacité de /w : [0-9]* kB ; utilisés : [0-9]* kB$')" 1
rm -rf "$B/w/mock/poc-rocky-9.7-x86_64-bootstrap"
PATH=$B/bin:$PATH sh "$B/sonde-boot-rendue.txt" > "$B/boot-absent.out" 2>&1; egal "code sans bootstrap" "$?" 0
egal "bootstrap absent signalé" "$(grep -c 'bootstrap préparé par mock : .* absent$' "$B/boot-absent.out")" 1

echo "## E : résumé du verrou"
python3 -I - "$S1N" "$B" <<'PY' || ko=1
import sys
n = open(sys.argv[1], encoding='utf-8').read(); B = sys.argv[2]
k = n.index('etape_verrou_brut() {'); i = n.index('\n', n.index("<<'PY'", k)) + 1; j = n.index('\nPY\n', i) + 1
open(f'{B}/resume.py', 'w', encoding='utf-8').write(n[i:j])
PY
cat > "$B/v1.json" <<'J'
{"version": "1.1.0", "config": {"bootstrap_image": "r:5000/x@sha256:0", "bootstrap_image_ready": false, "macros": {}},
 "bootstrap": {"pull_digest": "sha256:1", "image_digest": "sha256:2", "architecture": "amd64"},
 "buildroot": {"rpms": [{"name": "a", "url": "https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os/Packages/a/a.rpm", "signature": "350d275d"},
                        {"name": "b", "url": null, "signature": null}]}}
J
echo '{"version": "1.1.0", "config": {}, "bootstrap": {}, "buildroot": {"rpms": []}}' > "$B/v2.json"
python3 -I "$B/resume.py" "$B/v1.json" > "$B/v1.out" 2>&1; egal "résumé, verrou 1" "$?" 0
sed 's/^/     /' "$B/v1.out"
egal "rpm avec url (verrou 1)" "$(grep -c '^rpm avec url : 1 sur 2$' "$B/v1.out")" 1
egal "préfixe (verrou 1)" "$(grep -c '^préfixes des url : dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os/Packages/a$' "$B/v1.out")" 1
python3 -I "$B/resume.py" "$B/v2.json" > "$B/v2.out" 2>&1; egal "résumé, verrou 2" "$?" 0
egal "bootstrap vide signalé (verrou 2)" "$(grep -c '^bootstrap, champs : aucun' "$B/v2.out")" 1

echo '{"version": ' > "$B/casse.json"
( set -e; python3 -I "$B/resume.py" "$B/casse.json" >/dev/null 2>&1 || echo "résumé du verrou en échec : rc $?" ) > "$B/casse.out"; egal "JSON cassé : sous-shell set -e" "$?" 0
egal "JSON cassé : échec signalé, étape poursuivie" "$(grep -c '^résumé du verrou en échec : rc 1$' "$B/casse.out")" 1
egal "résumé non fatal dans la copie" "$(grep -c "python3 -I - \"\$R/\$PREFIXE-verrou_brut.json\" <<'PY' || echo \"résumé du verrou en échec : rc \$?\"" "$S1N")" 1
python3 -I - "$S1N" <<'PY2' || ko=1
import sys
n = open(sys.argv[1], encoding='utf-8').read(); k = n.index('etape_verrou_brut() {')
o = [n.index(x, k) for x in ('dans "$n" verrou-brut\n', 'dans "$n" verrou-brut-boot', '-verrou_brut-mock.log" || true', "<<'PY' || echo", 'pod_retirer "$n"')]
print('OK   ordre : sonde, SONDE_BOOT, journaux, résumé, retrait' if o == sorted(o) else 'KO   ordre des blocs de etape_verrou_brut : %s' % o)
sys.exit(0 if o == sorted(o) else 1)
PY2
egal "fin de verrou-calc.log archivée" "$(grep -c 'tail -n 60 /w/verrou-calc.log' "$S1N")" 1
echo "## F : étape connue de lancer"
egal "fonction etape_verrou_brut" "$(grep -c '^etape_verrou_brut() {$' "$S1N")" 1
egal "nom du pod conforme (minuscules, chiffres, tirets)" "$(grep -o 'n=s1-05-verrou-brut ' "$S1N" | grep -c -E '^n=[a-z0-9-]+ $')" 1
if [ $ko = 0 ]; then echo "# bilan : tenu, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; else echo "# bilan : NON TENU, fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
exit $ko
