# Prépare, sur des copies (scratchpad/archive-vsa/b), les changements du commit qui archivera la VSA de f5e6bcb0 (après R5).
# Chaque remplacement doit trouver exactement une occurrence, sinon arrêt.
import sys
from pathlib import Path

base = Path(sys.argv[1])

def remplacer(chemin, avant, apres):
    p = base / chemin
    t = p.read_text()
    n = t.count(avant)
    if n != 1:
        sys.exit(f"KO {chemin} : {n} occurrence(s) de {avant[:60]!r}")
    p.write_text(t.replace(avant, apres))
    print(f"OK {chemin} : {avant[:60]!r}")

rp = "poc/bricks/10-independent-replay/replay.sh"
remplacer(rp,
    "# passent par l'environnement ; les défauts restent ceux de 3a7ca1b1 / c4242a11 (rejeu.sh re-pousse cette VSA avec POUSSER_VSA=1)\n"
    "# jusqu'au commit qui archive la VSA de f5e6bcb0.",
    "# passent par l'environnement. Commit d'archive de la VSA de f5e6bcb0 (@DATE@) : les défauts sont ceux de f5e6bcb0 / 9539952b ;\n"
    "# ceux de 3a7ca1b1 / c4242a11 restent en commentaire.")
# défaut des journaux aligné sur les défauts de l'image : sans cela, un lancement sans environnement écrirait (et, lancer ne
# refusant que si RESULTATS_REPLAY est défini, réécrirait) les journaux de la clôture de la 10 dans resultats/ (relecture du conseiller)
remplacer(rp,
    "RJ=$(realpath -m \"${RESULTATS_REPLAY:-$R}\")",
    "RESULTATS_REPLAY=${RESULTATS_REPLAY:-$R/f5e6bcb0}   # défaut : dossier de f5e6bcb0 ; toujours défini, donc un journal existant est toujours refusé\n"
    "RJ=$(realpath -m \"$RESULTATS_REPLAY\")")
remplacer(rp,
    "IMAGE=${IMAGE:-builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5}   # sujet de la provenance\n",
    "# IMAGE=builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5   # Go 1.26.10 (VSA du 04/11/2026)\n"
    "IMAGE=${IMAGE:-builds/sample-app@sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7}   # sujet de la provenance (07c, Go 1.26.11)\n")
remplacer(rp,
    "INVOCATION=${INVOCATION:-c4242a11-18f6-439f-b947-7fe3d4319078}   # J7 du rejeu complet de la 08, 03/11/2026, 21:25:30 à 21:26:27 UTC (fermeture F2)\n",
    "# INVOCATION=c4242a11-18f6-439f-b947-7fe3d4319078   # J7 du rejeu complet de la 08, 03/11/2026, 21:25:30 à 21:26:27 UTC (fermeture F2)\n"
    "INVOCATION=${INVOCATION:-9539952b-07a7-4a0b-a6e1-084304d0e8af}   # PipelineRun de f5e6bcb0 (07c, étape 7), fin 2026-11-24T13:27:42Z\n")
remplacer(rp,
    "${GO_SHA256:-ccfe7ae822d2c2f41f4fe7c956199967a4dac22d0ee0d2b2bfdb440aab3b20c5}  ${GO_ARCHIVE:=go1.26.10.linux-amd64.tar.gz}\"",
    "${GO_SHA256:-9849f4e04ee35303714e34fbc3ac8ab44ea3e448a95aa182f91e3b9b79c710ec}  ${GO_ARCHIVE:=go1.26.11.linux-amd64.tar.gz}\"\n"
    "# Go 1.26.10 (3a7ca1b1) : ccfe7ae822d2c2f41f4fe7c956199967a4dac22d0ee0d2b2bfdb440aab3b20c5  go1.26.10.linux-amd64.tar.gz")
remplacer(rp,
    "FIN_BUILD=${FIN_BUILD:-2026-11-03T21:26:27Z}   # finishedOn de c4242a11, lu sans vérification le 03/11/2026 (23:13 UTC) ; R3 le revérifie\n",
    "# FIN_BUILD=2026-11-03T21:26:27Z   # finishedOn de c4242a11, lu sans vérification le 03/11/2026 (23:13 UTC) ; R3 le revérifie\n"
    "FIN_BUILD=${FIN_BUILD:-2026-11-24T13:27:42Z}   # finishedOn de 9539952b, vérifié en R3 le 24/11/2026 (07c)\n")
# le rejeu re-pousse la même VSA : son manifeste (même bundle, même sujet) est comparé à l'archive au lieu de la réécrire
remplacer(rp,
    "  cp \"$x/manifeste.json\" \"$RJ/r5-vsa-manifeste.json\"\n",
    "  if [ -e \"$RJ/r5-vsa-manifeste.json\" ]; then   # re-push (rejeu.sh) : l'archive n'est jamais réécrite, le manifeste doit être le même\n"
    "    cmp -s \"$x/manifeste.json\" \"$RJ/r5-vsa-manifeste.json\" || { echo \"REFUS : manifeste différent de resultats/r5-vsa-manifeste.json\"; exit 1; }\n"
    "    echo \"manifeste identique à l'archive : $m\"\n"
    "  else\n"
    "    cp \"$x/manifeste.json\" \"$RJ/r5-vsa-manifeste.json\"\n"
    "  fi\n")

rj = "poc/bricks/08-trust-plane/rejeu.sh"
remplacer(rj,
    "  # 07c, étape 7 (24/11/2026) : J7 construit désormais f5e6bcb0 ; cette VSA ne la couvre pas, le contrôle 6 refuserait l'image\n"
    "  # réelle tant que la brique 10 n'a pas produit de VSA de f5e6bcb0 (déduit du code, non mesuré). Ne pas lancer avec POUSSER_VSA=1 avant.\n"
    "  etape \"10 (VSA)\" env JALON=r5 mise run replay -- pousser_vsa\n",
    "  # 07c, commit d'archive (@DATE@) : VSA de f5e6bcb0 (resultats/f5e6bcb0 de la 10), défauts de replay.sh portés à f5e6bcb0.\n"
    "  # Jalon propre au rejeu : le journal r5-pousser_vsa.log de f5e6bcb0 existe et n'est jamais réécrit ; le manifeste est comparé à\n"
    "  # l'archive (même bundle, même sujet). PAS ENCORE REJOUÉ.\n"
    "  etape \"10 (VSA)\" env JALON=\"rejeu-$lib-r5\" RESULTATS_REPLAY=\"$here/../10-independent-replay/resultats/f5e6bcb0\" mise run replay -- pousser_vsa\n")
remplacer(rj,
    "  # VSA de la brique 10 (bundle versionné, lié au seul digest 3a7ca1b1, que J7 vérifie) re-poussée, puis contrôle 6 de la porte\n",
    "  # VSA de la brique 10 (bundle versionné, lié au seul digest f5e6bcb0, que J7 construit) re-poussée, puis contrôle 6 de la porte\n")
