#!/usr/bin/env bash
# Banc hors réseau du correctif extras de la brique 05 (s1-extras.patch : extras sur vault 9.7, décision du propriétaire
# « Extras sur vault »), écrit le 16/11/2026 avant tout passage. Ni cluster, ni Zot, ni réseau. Données sous ~/.cache.
# A : diff entre le s1.sh du dépôt et la copie modifiée : seules les lignes voulues changent.
# B : MOCK_CFG de chaque fichier, développé par bash, exécuté par python3 sur le dnf.conf de rocky-9.tpl, lu (jamais exécuté)
#     dans l'archive de mock 6.9-1 gardée par m2.sh releve (sha256 contrôlé) ; dépôts actifs et leurs URL listés.
# C : ligne de garde de la sonde (n=$(grep …)), extraite telle quelle de chaque fichier et lancée par sh, sur le dnf.conf du
#     modèle avant et après remplacement, en texte et en forme repr (\n littéraux, comme un affichage Python).
# D : boucle vault 9.7 de l'étape hote, extraite de la copie, lancée avec curl, gpgv et attendu simulés : URL demandées.
# E : bash -n et shellcheck.
# Non couvert : vrai mock --debug-config (format réel de l'affichage), vrai dnf, vraie signature d'extras de vault 9.7
#     (mesurée par releve7, Y3), contenu réel du buildroot.
# Usage : banc-extras.sh <racine du dépôt> <copie modifiée de s1.sh> <dossier de travail, vidé>
set -uo pipefail
export LC_ALL=C
D=$1; S1N=$2; B=$3
S1A=$D/poc/bricks/05-rpm-mock/s1.sh
ARCHIVE=$HOME/.cache/supply-chain-poc/05/m2/mock.tar.gz
ARCHIVE_SHA=$(sed -n 's/^ARCHIVE_SHA=\([0-9a-f]\{64\}\) .*/\1/p' "$D/poc/bricks/05-rpm-mock/m2.sh")
rm -rf -- "${B:?}"; mkdir -p "$B"
echo "# banc-extras.sh, $(date -u +%Y-%m-%dT%H:%M:%SZ), python3 $(python3 -I -c 'import sys; print(sys.version.split()[0])')"
echo "# s1.sh du dépôt $(sha256sum < "$S1A" | cut -c1-64) ; copie modifiée $(sha256sum < "$S1N" | cut -c1-64)"
ko=0
ok() { echo "OK   $*"; }
nok() { echo "KO   $*"; ko=1; }
egal() { if [ "$2" = "$3" ]; then ok "$1 : $2"; else nok "$1 : $2 (attendu : $3)"; fi; }

echo "## A : lignes changées"
diff "$S1A" "$S1N" > "$B/diff.txt"
egal "lignes retirées" "$(grep -c '^<' "$B/diff.txt")" 5
egal "lignes ajoutées" "$(grep -c '^>' "$B/diff.txt")" 9
grep '^[<>]' "$B/diff.txt" | cut -c1-200

echo "## B : MOCK_CFG exécuté sur le dnf.conf de rocky-9.tpl"
egal "sha256 de l'archive de mock gardée" "$(sha256sum < "$ARCHIVE" | cut -c1-64)" "$ARCHIVE_SHA"
mkdir -p "$B/mock-src"; tar -xzf "$ARCHIVE" -C "$B/mock-src" --strip-components=1
TPL=$(find "$B/mock-src" -path '*/templates/rocky-9.tpl' | sort)
egal "rocky-9.tpl dans l'archive" "$(printf '%s\n' "$TPL" | grep -c .)" 1
cfg() { # fichier s1.sh : MOCK_CFG développé comme bash le fait dans s1.sh (CFG, BOOT et VAULT97 lus dans le fichier)
  bash -c 'set -u; eval "$(grep -hE "^REG=" "$2"; grep -E "^(VAULT97|CFG|DEPOT_AMONT|BOOT_DIGEST|BOOT)=" "$1" | sed "s/[[:space:]]*#.*//")"
           eval "$(awk "/^MOCK_CFG=\"/,/^\"\$/" "$1")"; printf "%s" "$MOCK_CFG"' _ "$1" "$D/poc/bricks/08-trust-plane/commun.sh" 2>"$B/cfg.err" || cat "$B/cfg.err"
}
cfg "$S1A" > "$B/avant.cfg"; cfg "$S1N" > "$B/apres.cfg"
egal "MOCK_CFG : lignes qui diffèrent entre avant et après" "$(diff "$B/avant.cfg" "$B/apres.cfg" | grep -c '^[<>]')" 2
VAULT=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$S1N")
for x in avant apres; do
  echo "### $x"
  python3 -I - "$TPL" "$B/$x.cfg" "$B/$x.dnf.conf" "$VAULT" <<'PY'
import configparser, re, sys
tpl, cfg, sortie, vault = sys.argv[1:5]
txt = open(tpl, encoding="utf-8").read()
m = re.findall(r"config_opts\['dnf\.conf'\]\s*=\s*\"\"\"(.*?)\"\"\"", txt, re.S)
assert len(m) == 1 and "\\" not in m[0], "dnf.conf du modèle non extrait tel quel"
config_opts = {"dnf.conf": m[0], "macros": {}}
code = open(cfg, encoding="utf-8").read()
assert code.startswith("include('templates/rocky-9.tpl')\n")
exec(code.split("\n", 1)[1], {"config_opts": config_opts})
conf = config_opts["dnf.conf"]
open(sortie, "w", encoding="utf-8").write(conf)
p = configparser.ConfigParser(interpolation=None, strict=False, default_section="\x00")
p.read_string(conf)
actifs = [s for s in p.sections() if p[s].get("enabled", "1").strip() == "1" and s != "main"]
print(f"sections : {len(p.sections())} ; actives hors main : {actifs}")
for s in actifs:
    print(f"  {s} : baseurl {p[s].get('baseurl', '-')} ; mirrorlist {p[s].get('mirrorlist', '-')}")
dossier = {"baseos": "BaseOS", "appstream": "AppStream", "crb": "CRB", "extras": "extras"}
fixes = all("mirrorlist" not in p[s] and p[s].get("baseurl", "").strip() == f"{vault}/{dossier.get(s, '?')}/x86_64/os/"
            for s in actifs)
print(f"toutes les sections actives en baseurl fixe de vault 9.7 : {fixes}")
PY
done
python3 -I - "$B/avant.dnf.conf" "$B/apres.dnf.conf" <<'PY' > "$B/verdict-b.txt"
import configparser, sys
def lire(f):
    p = configparser.ConfigParser(interpolation=None, strict=False, default_section="\x00"); p.read(f, encoding="utf-8"); return p
a, n = lire(sys.argv[1]), lire(sys.argv[2])
act = lambda p: sorted(s for s in p.sections() if p[s].get("enabled", "1").strip() == "1" and s != "main")
print("actives", ",".join(act(a)), ",".join(act(n)))
print("mirrorlist-actifs", sum("mirrorlist" in a[s] for s in act(a)), sum("mirrorlist" in n[s] for s in act(n)))
diff = [s for s in a.sections() if dict(a[s]) != dict(n[s])]
print("sections-changees", ",".join(diff))
print("extras-debug-inchange", dict(a["extras-debug"]) == dict(n["extras-debug"]) if "extras-debug" in a else "absent")
PY
cat "$B/verdict-b.txt"
egal "sections actives, avant puis après" "$(sed -n 's/^actives //p' "$B/verdict-b.txt")" "appstream,baseos,crb,extras appstream,baseos,crb,extras"
egal "sections actives encore en mirrorlist, avant puis après" "$(sed -n 's/^mirrorlist-actifs //p' "$B/verdict-b.txt")" "1 0"
egal "sections changées par le correctif" "$(sed -n 's/^sections-changees //p' "$B/verdict-b.txt")" "extras"
egal "extras-debug inchangé" "$(sed -n 's/^extras-debug-inchange //p' "$B/verdict-b.txt")" "True"
egal "baseurl d'extras après" "$(grep -A3 '^\[extras\]' "$B/apres.dnf.conf" | sed -n 's/^baseurl=//p')" "$VAULT/extras/x86_64/os/"

echo "## C : garde de la sonde"
garde() { # fichier s1.sh, texte : la ligne n=$(grep …) du fichier, lancée par sh sur le texte
  local l; l=$(grep -E '^n=\$\(grep -o -E "mirrorlist=' "$1"); printf '%s' "$2" > "$B/debug-config.log"
  sh -c "${l//\/w\/debug-config.log/$B/debug-config.log}; echo \$n"
}
egal "ligne de garde trouvée, dépôt puis copie" "$(grep -cE '^n=\$\(grep -o -E "mirrorlist=' "$S1A") $(grep -cE '^n=\$\(grep -o -E "mirrorlist=' "$S1N")" "1 1"
brut=$(python3 -I -c 'import re,sys; print(re.findall(r"config_opts\[.dnf\.conf.\]\s*=\s*\"\"\"(.*?)\"\"\"", open(sys.argv[1]).read(), re.S)[0])' "$TPL")
repr_() { python3 -I -c 'import sys; print(repr(open(sys.argv[1]).read()))' "$1"; }
printf '%s' "$brut" > "$B/brut.conf"
for forme in texte repr; do
  if [ $forme = texte ]; then t0=$(cat "$B/brut.conf"); ta=$(cat "$B/avant.dnf.conf"); tn=$(cat "$B/apres.dnf.conf")
  else t0=$(repr_ "$B/brut.conf"); ta=$(repr_ "$B/avant.dnf.conf"); tn=$(repr_ "$B/apres.dnf.conf"); fi
  egal "$forme, modèle brut : garde du dépôt puis de la copie" "$(garde "$S1A" "$t0") $(garde "$S1N" "$t0")" "3 4"
  egal "$forme, remplacement du dépôt (extras restant) : garde du dépôt puis de la copie" "$(garde "$S1A" "$ta") $(garde "$S1N" "$ta")" "0 1"
  egal "$forme, remplacement de la copie : garde de la copie" "$(garde "$S1N" "$tn")" 0
done
egal "le modèle brut a extras-debug et extras-source en mirrorlist (exclus par ([^-]|\$))" \
  "$(grep -c -E 'repo=extras-\$releasever-(debug|source)' "$B/brut.conf")" 2

echo "## D : boucle vault 9.7 de hote"
awk '/^  for n in BaseOS AppStream CRB extras; do$/,/^  done$/' "$S1N" > "$B/boucle.sh"
egal "boucle extraite (lignes)" "$(wc -l < "$B/boucle.sh")" 7
(
  set -euo pipefail
  d=$B/hote; mkdir -p "$d"; VAULT97=$VAULT; FP_ROCKY=FPROCKY
  : "$VAULT97" "$FP_ROCKY"   # lus par la boucle chargée plus bas
  curl() { local o=; while [ $# -gt 1 ]; do [ "$1" = -o ] && o=$2; shift; done; echo "$1" >> "$B/urls.txt"; echo x > "$o"; }
  gpgv() { echo "[GNUPG:] VALIDSIG X Y FPROCKY"; }
  attendu() { [ "$2" = "$3" ] && echo "OK   $1" || { echo "KO   $1"; exit 1; }; }
  # shellcheck disable=SC1090
  . "$B/boucle.sh"
) > "$B/boucle.out" 2>&1; egal "boucle simulée : code" $? 0
egal "repomd.xml signés (simulés)" "$(grep -c '^OK   vault 9.7 .* : signataire de repomd.xml$' "$B/boucle.out")" 4
egal "URL demandées" "$(sort -u "$B/urls.txt" | wc -l)" 8
egal "URL d'extras" "$(grep -c "^$VAULT/extras/x86_64/os/repodata/repomd.xml\(\.asc\)\?$" "$B/urls.txt")" 2

echo "## E : bash -n et shellcheck"
bash -n "$S1N"; egal "bash -n de la copie" $? 0
SC=/home/linuxbrew/.linuxbrew/bin/shellcheck
egal "version de shellcheck" "$($SC --version | sed -n 's/^version: //p')" 0.11.0
$SC -S warning "$S1N" > "$B/sc.txt" 2>&1; egal "shellcheck -S warning de la copie : code" $? 0
egal "remarques shellcheck (tous niveaux), dépôt puis copie" \
  "$($SC -f gcc "$S1A" | wc -l) $($SC -f gcc "$S1N" | wc -l)" "$($SC -f gcc "$S1A" | wc -l) $($SC -f gcc "$S1A" | wc -l)"

echo "# bilan : $([ $ko = 0 ] && echo tenu || echo 'NON TENU'), fin $(date -u +%Y-%m-%dT%H:%M:%SZ)"
exit $ko
