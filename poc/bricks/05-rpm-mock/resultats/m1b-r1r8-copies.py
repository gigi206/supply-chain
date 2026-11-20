"""Brique 05, cascade de M1b (décision « Rejouer les huit » du 20/11/2026) : m1b-r1r8.sh est produit à partir de m5.sh, qui
n'est pas touché, par des remplacements listés et comptés. Chaque remplacement (a, b, n) exige exactement n occurrences de a.
Usage : python3 -I m1b-r1r8-copies.py assembler <m5.sh> <sortie, absente>
        python3 -I m1b-r1r8-copies.py verifier <m5.sh> <m1b-r1r8.sh>   (code 1 si le fichier diffère du produit)
        python3 -I m1b-r1r8-copies.py compter                           (nombre de contrôles)"""
import os, sys

ENTETE_M5 = """# Brique 05, jalon M5a (carte de M5 et décision « Ok » du 18/11/2026) : tests négatifs de la voie rpm, chacun avec son témoin,
# par des TaskRuns isolés des tâches déjà signées et revues (règle tekton-references de la 08 : bundle de tekton/tasks par
# digest, compte build, workspaces emptyDir ou PVC) et par des pods d'essai. Aucune tâche neuve, aucune signature, aucune
# écriture dans Zot. Le rejeu de zéro est M5b, jalon à part. Modèle : s5.sh de la 06. Prédictions : resultats/m5-predictions.md,
# commitées avant tout lancement. Préparé à sec sous l'accord permanent du 18/11.
"""
ENTETE_M1B = """# Brique 05, cascade de M1b (décision « Rejouer les huit » du 20/11/2026) : les huit refus de M5a (R1 à R8) rejoués sur le
# bundle de la cascade, construire-rpm@ca03f189 (image d'outillage 70f8c412 de M1b), avec les entrées de la pipeline
# sample-app-rpm@7d361cb1 (fermeture 09838980 de M4b refait, artefact de packaging 333b7322 au verrou c544599a).
# Produit à partir de m5.sh, qui n'est pas touché, par les remplacements comptés de resultats/m1b-r1r8-copies.py. Sont changés :
# les références, la source de l'hôte et son empreinte, le rootfs de l'outillage, la tâche signée lue (.m1b.signee.yaml), le
# nombre d'enveloppes de l'artefact (8 depuis M4c refait), les PipelineRuns gardés (ceux de M4c et de M4c refait), le préfixe
# des journaux (celui des objets) et une garde contre l'écrasement d'un journal. Le reste est le texte de m5.sh, dont les
# descriptions d'étapes ci-dessous. Aucune tâche neuve, aucune signature, aucune écriture dans Zot.
# Texte de m5.sh :
# Jalon M5a (carte de M5 et décision « Ok » du 18/11/2026) : tests négatifs de la voie rpm, chacun avec son témoin,
# par des TaskRuns isolés des tâches déjà signées et revues (règle tekton-references de la 08 : bundle de tekton/tasks par
# digest, compte build, workspaces emptyDir ou PVC) et par des pods d'essai. Aucune tâche neuve, aucune signature, aucune
# écriture dans Zot. Le rejeu de zéro est M5b, jalon à part. Modèle : s5.sh de la 06. Prédictions : resultats/m1b-predictions.md
# pour ce rejeu, commitées avant tout lancement. Préparé à sec sous l'accord permanent du 18/11.
"""
T_LIST = [
    (ENTETE_M5, ENTETE_M1B, 1),
    ("# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/m5.sh <étape>… (journal : resultats/m5-<étape>.log)\n",
     "# Usage (racine du dépôt) : DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/m1b-r1r8.sh <étape>… (journal :\n"
     "# resultats/$N-<étape>.log ; un journal présent arrête le script avant toute étape)\n", 1),
    ('N=${PREFIXE:-m5}\ncase $N in \'\'|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac\n',
     'N=${PREFIXE:-m1b-r1r8}\ncase $N in \'\'|*[!a-z0-9-]*) echo "PREFIXE invalide : $N" >&2; exit 2 ;; esac\n'
     'case $N in m5|m5banc1|m4c|m1b|m1bt*|m1b-construction|m1b-refus*) echo "PREFIXE refusé (déjà pris par un jalon) : $N" >&2; exit 2 ;; esac\n', 1),
    ("# Références épinglées (m4c.sh, vérifiées dans le dépôt)\n",
     "# Références épinglées (m1b-construction.sh, vérifiées dans le dépôt par le banc)\n", 1),
    ("PIPELINE_REF=$REG/tekton/pipelines/sample-app-rpm@sha256:ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be   # a56a85b\n",
     "PIPELINE_REF=$REG/tekton/pipelines/sample-app-rpm@sha256:7d361cb1d5ea9b7994727f839bc4365a29e4ebdc7948fceff4176b4a371abd6a   # M4c refait\n", 1),
    ("CONSTRUIRE_REF=$REG/tekton/tasks/construire-rpm@sha256:d7f01398f188931c124273c8b5fb60e2a66c22e9d0a2dfcd229ecadee1e62164   # liste revue (1d5e27d)\n",
     "CONSTRUIRE_REF=$REG/tekton/tasks/construire-rpm@sha256:ca03f18908d0b5e73edc57ecf9610513e2907267ce1da2d9f41fd36b969289c5   # cascade, liste revue (e2f15c1b)\n", 1),
    ("IMAGE_OUTILLAGE=$REG/essais-05/mock-rocky9@sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771       # « Option 1 »\n",
     "IMAGE_OUTILLAGE=$REG/builds/builders/mock-rocky9@sha256:70f8c41245321494bb48ebc423514c72659dfb0f6cbeb8f6d797a41ebaf472ae   # M1b\n", 1),
    ("FERMETURE_RPM=$REG/builds/fermetures/sample-app-rpm@sha256:2a9e2ea738e7e1b51ae441960502d3c1598bbd04bc7a66fa90423c7512169f0c    # M4b\n",
     "FERMETURE_RPM=$REG/builds/fermetures/sample-app-rpm@sha256:0983898054a9b96e51f54a2c13ad5919f999e6bccf61ecade0eb8cab5a30e28f    # M4b refait\n", 1),
    ("PACKAGING=$REG/entrees/sample-app/packaging-rpm@sha256:41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8      # M4a\n",
     "PACKAGING=$REG/entrees/sample-app/packaging-rpm@sha256:333b7322290ab5edd85989908fa2e181a48a72facfd4043e181a2962d2bcfe48      # cascade\n", 1),
    ("PVC_TAILLE=2Gi   # entrees/ : 305 Mio ; copies par liens durs, fichiers neufs : R4 (92 187 o), R5, R6 (97 742 593 o)\n",
     "PVC_TAILLE=2Gi   # entrees/ : 462 848 602 o ; copies par liens durs, fichiers neufs : R1, R4, R5, R6 (241 981 440 o, couche non compressée)\n", 1),
    ("# Hôte : arbre entrees/ de m4c.sh prealables (fermeture tirée par comparaison de M4b), rootfs de l'image d'outillage (m5-sigmd5.sh)\n"
     "SOURCE_HOTE=$W/m4c-05/prealables/ws/entrees\n"
     "SOURCE_EMPREINTE=d3a610bbd9e1ba6fa56abaaaec4e54addf7a4669d3c9e252b0f6ff65041be8e7   # m5-alterer.py empreinte, 273 fichiers (18/11)\n"
     "RACINE=$HOME/.cache/supply-chain-poc/05/m5-sigmd5/racine\n",
     "# Hôte : arbre entrees/ de m1b-construction.sh local (égal à celui du pod d'essai, EP1), rootfs de l'image d'outillage de M1b\n"
     "# (crane export par digest, déballé sous unshare -r, 20/11)\n"
     "SOURCE_HOTE=$W/m1b-construction-05/local/ws/entrees\n"
     "SOURCE_EMPREINTE=7153c8064cad6aababf65b22369cfe88be892e463e20d5f4722cab9f9abfc43b   # m5-alterer.py empreinte, 273 fichiers (20/11)\n"
     "RACINE=$HOME/.cache/supply-chain-poc/05/m1b-refus-racine/racine\n", 1),
    ('"$h05/construction/construire-rpm.signee.yaml"', '"$h05/construction/construire-rpm.m1b.signee.yaml"', 3),
    ('attendu "rpm du rootfs de l\'image d\'outillage (m5-sigmd5.sh)"', 'attendu "rpm du rootfs de l\'image d\'outillage de M1b"', 1),
    ('"$(enveloppes)" 4', '"$(enveloppes)" 8', 3),
    ("kubectl get pipelinerun -n builds m4c-rpm-1 m4c-rpm-2 -o name", "kubectl get pipelinerun -n builds m4c-rpm-1 m4c-rpm-2 m1b-construction-1 m1b-construction-2 -o name", 3),
    ("PipelineRuns de M4c gardés", "PipelineRuns de M4c et de M4c refait gardés", 3),
    ('-o name < /dev/null | wc -l)" 2', '-o name < /dev/null | wc -l)" 4', 2),
    ("! grep -q 'm4c-rpm' <<< \"$o\" || echec \"un objet de M4c porte le label du jalon\"",
     "! grep -q 'm4c-rpm\\|m1b-construction' <<< \"$o\" || echec \"un objet de M4c ou de M4c refait porte le label du jalon\"", 1),
    ('lancer m5 "05 M5a" "$@"\n',
     'for e in "$@"; do [ ! -e "$R/$N-$e.log" ] || { echo "journal déjà présent : resultats/$N-$e.log (relancer sous un autre PREFIXE)" >&2; exit 2; }; done\n'
     'lancer "$N" "05 M1b R1-R8" "$@"\n', 1),
]


def produire(src):
    t = open(src, encoding="utf-8").read()
    for a, b, n in T_LIST:
        k = t.count(a)
        assert k == n, (k, n, a[:80])
        t = t.replace(a, b)
    for a, b, n in T_LIST:   # aucun texte remplacé ne subsiste (sauf s'il est contenu dans son remplaçant)
        assert a in b or t.count(a) == 0, a[:80]
    return t


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "compter":
        print(sum(n for _, _, n in T_LIST) + len(T_LIST))
    elif mode == "assembler":
        assert not os.path.exists(sys.argv[3]), sys.argv[3]
        open(sys.argv[3], "w", encoding="utf-8").write(produire(sys.argv[2]))
        os.chmod(sys.argv[3], 0o755)
        print("assemblé", len(T_LIST), "remplacements")
    elif mode == "verifier":
        ok = produire(sys.argv[2]) == open(sys.argv[3], encoding="utf-8").read()
        print(("OK  " if ok else "KO  ") + f" m1b-r1r8.sh égal au produit de m5.sh ({len(T_LIST)} remplacements, {sum(n for _, _, n in T_LIST)} occurrences)")
        sys.exit(0 if ok else 1)
    else:
        sys.exit("mode inconnu : " + mode)
