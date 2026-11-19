#!/usr/bin/env bash
# Brique 09, O2 : contrôle complémentaire de debian_racine, local, sans réseau ni relance. Les .deb des 59 paquets essentiels
# n'étaient plus en cache au moment du crochet (seuls 47 .deb sur 106 paquets ont été contrôlés). Ce script compare, pour les
# 106 paquets installés (lignes « paquet » du journal de mmdebstrap), le couple nom et version au Packages.xz vérifié du relevé.
# Il ne prouve pas le contenu des fichiers (apt l'a contrôlé par les sommes de Packages) : seulement que chaque version installée
# figure dans l'index signé de l'instantané. Journal : resultats/o2-controle-versions.log.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
J=$HOME/.cache/supply-chain-poc/09/o2/debian-mmdebstrap.log
P2=$HOME/.cache/supply-chain-poc/09/o2-releve-20261119T154234Z/Packages.xz
cd "$HOME/.cache/supply-chain-poc/09"
{
  echo "contrôle des versions commencé : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ; journal de mmdebstrap sha256 $(sha256sum < "$J" | cut -c1-16)… ; Packages.xz sha256 $(sha256sum < "$P2" | cut -c1-16)…"
  python3 -I - "$P2" "$J" <<'PY'
import lzma, sys
pk = set()
for para in lzma.open(sys.argv[1]).read().decode("utf-8", "replace").split("\n\n"):
    d = dict(l.split(": ", 1) for l in para.split("\n") if ": " in l and not l.startswith(" "))
    if "Package" in d: pk.add((d["Package"], d["Version"]))
inst, debs = {}, set()
for l in open(sys.argv[2], encoding="utf-8", errors="replace"):
    c = l.split()
    if len(c) == 3 and c[0] == "paquet": inst[c[1]] = c[2]
    if len(c) == 4 and c[0] == "deb": debs.add(c[2].split("_")[0])
ko = [f"{p} {v}" for p, v in sorted(inst.items()) if (p, v) not in pk]
print(f"paquets installés : {len(inst)} ; dont .deb contrôlé par sha256 (debian_racine) : {len(set(inst) & debs)} ; sans .deb contrôlé : {len(set(inst) - debs)}")
print(("OK   " if inst and not ko else "KO   ") + f"versions installées présentes dans le Packages.xz vérifié : {len(inst) - len(ko)} sur {len(inst)}")
for k in ko[:20]: print("     écart : " + k)
PY
  echo "contrôle des versions fini : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} 2>&1 | tee "$here/resultats/o2-controle-versions.log"
