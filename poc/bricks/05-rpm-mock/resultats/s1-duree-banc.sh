#!/usr/bin/env bash
# Banc hors réseau du correctif de durée de vie et de place de la brique 05 (s1-duree.patch : sleep 43200 au lieu de 10800,
# décision « Oui, 12 h » ; df -k /w en tête de SONDE, décision « Oui, ajoute df »), écrit le 17/11/2026 avant tout passage.
# Ni cluster, ni Zot, ni réseau.
# A : diff entre le s1.sh du dépôt et la copie modifiée : seules les lignes voulues changent.
# B : pod_spec de chaque fichier, extraite et lancée par bash avec ses variables : le JSON ne diffère que par la commande.
# C : MOCK_CFG et STOCKAGE, etape_image, SONDE_N34, SONDE_VERROU, etape_essais et etape_verrou identiques octet pour octet ;
#     SONDE identique une fois la ligne df retirée, ligne placée juste après la ligne des montages.
# D : couche de configuration de l'image rejouée depuis la copie (banc-config.py, garde de sha256 adaptée) : même tar f5710d47.
# E : bash -n, et shellcheck avec le même nombre de remarques dans les deux fichiers.
# F : ligne df extraite de la SONDE de la copie, lancée par sh sur le tmpfs /dev/shm de l'hôte à la place de /w : sortie
#     comparée à df -k de ce même dossier.
# Non couvert : vrai pod (sleep réel, fin du conteneur, df de l'invité Kata), vrai kubectl.
# Usage : banc-duree.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier de travail, vidé>
set -uo pipefail
export LC_ALL=C
D=$1; S1N=$2; B=$3
S1A=$D/poc/bricks/05-rpm-mock/s1.sh
rm -rf -- "${B:?}"; mkdir -p "$B"
echo "# banc-duree.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), $(jq --version)"
echo "# s1.sh du dépôt $(sha256sum < "$S1A" | cut -c1-64) ; copie modifiée $(sha256sum < "$S1N" | cut -c1-64)"
ko=0
DF='df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"'
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
egal() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else nok "$1 : $2 (attendu : $3)"; fi; }

echo "## A : lignes changées"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées" "$(grep -c '^<' "$B/diff.txt")" 1
egal "lignes ajoutées" "$(grep -c '^>' "$B/diff.txt")" 6
egal "ligne retirée" "$(grep '^<' "$B/diff.txt" | grep -c 'command: \["sleep", "10800"\]')" 1
egal "ligne ajoutée hors en-tête" "$(grep '^>' "$B/diff.txt" | grep -v '^> #' | grep -c 'command: \["sleep", "43200"\]')" 1
egal "lignes ajoutées en commentaire" "$(grep -c '^> #' "$B/diff.txt")" 4
egal "ligne df ajoutée" "$(grep -c -F "> $DF" "$B/diff.txt")" 1
egal "occurrences de 10800 hors commentaires dans la copie" "$(grep -v '^[[:space:]]*#' "$S1N" | grep -c 10800)" 0

echo "## B : pod_spec"
spec() { # fichier sortie : pod_spec extraite et lancée (nom s1-05-essais, image fictive)
  local f=$1 o=$2
  mkdir -p "$o"
  { grep -E "^(LIMITES|TMPFS|LABEL|PRIVILEGIE)=" "$f"; echo "T=$o"
    sed -n '/^pod_spec() {/,/^}/p' "$f"; echo 'pod_spec s1-05-essais exemple.test/image@sha256:0'; } > "$o/spec.sh"
  bash -euo pipefail "$o/spec.sh" && jq -S . "$o/s1-05-essais.json" > "$o/spec.json"
}
spec "$S1A" "$B/avant" && spec "$S1N" "$B/apres" || nok "pod_spec non rejouée"
egal "commande avant" "$(jq -c '.spec.containers[0].command' "$B/avant/spec.json")" '["sleep","10800"]'
egal "commande après" "$(jq -c '.spec.containers[0].command' "$B/apres/spec.json")" '["sleep","43200"]'
egal "reste du pod identique" "$(jq -S 'del(.spec.containers[0].command)' "$B/avant/spec.json" | sha256sum | cut -c1-64)" \
  "$(jq -S 'del(.spec.containers[0].command)' "$B/apres/spec.json" | sha256sum | cut -c1-64)"
egal "restartPolicy après" "$(jq -r .spec.restartPolicy "$B/apres/spec.json")" Never
egal "volume /w après" "$(jq -c '.spec.volumes' "$B/apres/spec.json")" '[{"emptyDir":{"medium":"Memory","sizeLimit":"4Gi"},"name":"w"}]'

echo "## C : blocs inchangés"
python3 -I - "$S1A" "$S1N" "$DF" <<'PY'
import sys
a, n = (open(f, encoding='utf-8').read() for f in sys.argv[1:3])
DF = sys.argv[3]
def bloc(s, debut, fin):
    i = s.index(debut); j = s.index(fin, i) + len(fin)
    assert s.count(debut) == 1, debut
    return s[i:j]
for nom, debut, fin in (("MOCK_CFG et STOCKAGE", 'MOCK_CFG="include(', "\n'\n\netape_image"),
                        ("etape_image", 'etape_image() {\n', '\n}\n'),
                        ("SONDE_N34", "SONDE_N34='set -u\n", "\ntrue'\n"),
                        ("SONDE_VERROU", "SONDE_VERROU='set -u\n", "\ntrue'\n"),
                        ("etape_essais", 'etape_essais() {\n', '\n}\n'),
                        ("etape_verrou", 'etape_verrou() {\n', '\n}\n')):
    x, y = bloc(a, debut, fin), bloc(n, debut, fin)
    print(('OK   ' if x == y else 'KO   ') + f'{nom} identique : {len(x)} caractères')
m = 'awk "\\$2 == \\"/\\" || \\$2 == \\"/w\\" {print \\"montage \\" \\$2 \\" : \\" \\$3 \\" \\" \\$4}" /proc/mounts\n'
x, y = bloc(a, "SONDE='set -u\n", "\ntrue'\n"), bloc(n, "SONDE='set -u\n", "\ntrue'\n")
d = DF + '\n'
print(('OK   ' if y.count(d) == 1 and y.replace(d, '', 1) == x else 'KO   ') + f'SONDE identique hors la ligne df : {len(x)} caractères')
print(('OK   ' if y.count(m + d) == 1 else 'KO   ') + 'ligne df juste après la ligne des montages')
PY

echo "## D : couche de configuration de l'image"
PYC=$D/poc/bricks/05-rpm-mock/resultats/s1-image-banc-config.py
egal "garde de sha256 de banc-config.py" "$(grep -c "startswith('ad16fc99')" "$PYC")" 1
sed "s/startswith('ad16fc99')/startswith('$(sha256sum < "$S1N" | cut -c1-8)')/" "$PYC" > "$B/banc-config.py"
egal "banc-config.py adapté : une seule ligne change" "$(diff "$PYC" "$B/banc-config.py" | grep -c '^[<>]')" 2
mkdir -p "$B/config"
python3 -I "$B/banc-config.py" "$S1N" "$B/config" >/dev/null && bash "$B/config/banc-config.sh" </dev/null > "$B/config.out" 2>&1 \
  || nok "banc-config non rejoué"
egal "couche-config.tar rejouée depuis la copie" "$(sha256sum < "$B/config/couche-config.tar" | cut -c1-64)" \
  f5710d475bc0e83b67701a96b5aa3dbd01fe971d2d68f097358019c72ba52560

echo "## E : bash -n et shellcheck"
bash -n "$S1N" && ok "bash -n de la copie" || nok "bash -n de la copie"
SC=/home/linuxbrew/.linuxbrew/bin/shellcheck
egal "version de shellcheck" "$($SC --version | sed -n 's/^version: //p')" 0.11.0
$SC -S warning "$S1N" > "$B/sc.txt" 2>&1; egal "shellcheck -S warning de la copie : code" $? 0
egal "remarques shellcheck (tous niveaux), dépôt puis copie" "$($SC -f gcc "$S1A" 2>/dev/null | wc -l) $($SC -f gcc "$S1N" 2>/dev/null | wc -l)" \
  "$($SC -f gcc "$S1A" 2>/dev/null | wc -l) $($SC -f gcc "$S1A" 2>/dev/null | wc -l)"

echo "## F : ligne df sous sh"
grep -c -F -x "$DF" "$S1N" > "$B/df-n.txt"; egal "ligne df dans la copie" "$(cat "$B/df-n.txt")" 1
egal "/dev/shm est un tmpfs" "$(stat -f -c %T /dev/shm)" tmpfs
grep -F -x "$DF" "$S1N" | sed 's#^df -k /w |#df -k /dev/shm |#' > "$B/df.sh"
o=$(sh "$B/df.sh" </dev/null); echo "sortie : $o"
r=$(df -k /dev/shm | awk 'NR == 2 {print $2 " " $3}')
egal "sortie de la ligne df" "$o" "capacité de /w : ${r% *} kB ; utilisés : ${r#* } kB"

echo "# bilan : $([ $ko = 0 ] && echo tenu || echo 'NON TENU'), fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
exit $ko
