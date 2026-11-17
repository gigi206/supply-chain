# Brique 05, carte de M4, préparée à sec (17/11/2026, à partir de 20:41:35 UTC)

**Interprétation** : le « Continue » reçu après le `/compact` (heure non relevée) est consigné comme une permission de préparer à sec, pas comme un accord, comme pour la carte de S4 de la 06 (10/11/2026, 21:19 UTC). Rien n'a été écrit dans Zot, ni dans le cluster, ni sur les VM. Aucune tâche, aucun script, aucune prédiction.

## Effort

- Brique 05 : 119 commits, 16,71 h (écarts d'au plus 1 h) à HEAD `8b30c95` ([relevé](temps-05-1211.log)), pour 2,5 pw estimées ; décision avec le propriétaire à 5 pw. Les heures ne sont pas converties en pw.
- La méthode ne compte que les commits de `poc/bricks/05-rpm-mock`. Sur les jalons de S4 de la 06, compter aussi la 08 et la 08c, ou tout le dépôt, donne les mêmes heures ([relevé](m4-projection-06.log)). Le travail de M4 dans la 08 sera relevé de la même façon.
- Durées comparables ([relevé](m4-projection-06.log)), en heures de commits, sans l'attente des passages :

| Comparable | Heures | Commits (06 seule) |
|---|---|---|
| S4a de la 06 (pipeline `builders/`) | 1,01 | 21 |
| S4c de la 06 (artefact de packaging et verrou) | 0,16 | 6 |
| S4b de la 06 (`prefetch-deb`) | 0,87 | 12 |
| S4d1 de la 06 (pipeline `sample-app-deb`) | 2,10 | 14 |
| S4d2 et S4d3 de la 06 (porte, déclencheur, rattrapage) | 0,95 | 13 |
| Brique 05, de `boot_racine` préparée à M3 tenu | 4,79 | 34 (05 seule) |

## Carte

Chaque point est marqué « vérifié dans le dépôt », « mesuré » (journal archivé), « (lecture) » ou « à vérifier ».

1. **Preuve attendue** (tableau des jalons) : « Sujet rpm signé, digest de la fermeture dans `resolvedDependencies` ». Vérifié dans le dépôt.
2. **Coupure réseau de la construction** : `construction-rpm-sans-sortie`, posée dans le cluster depuis M3 (17/11/2026, 20:07:12 UTC), sélectionne `tekton.dev/task=construire-rpm`. La tâche de construction doit porter ce nom. Vérifié dans le dépôt.
3. **Sortie du prefetch** : `prefetch-rpm-sortie`, posée dans le cluster le 16/11/2026 (22:31:59 à 22:32:02 UTC), sélectionne `tekton.dev/task=prefetch-rpm` : DNS, adresses publiques en 443, Zot. La tâche de prefetch doit porter ce nom. Vérifié dans le dépôt.
4. **Publication de la fermeture**
   - `publier-fermeture` (08) envoie chaque fichier sauf `bom.json`, trié, sous la forme `chemin:type`, comme `closure.sh` (03), qui a envoyé `f235a98b…`. Vérifié dans le dépôt.
   - Le banc de la fermeture a mesuré les chemins à « : » et « @ » du dossier `dir:` avec `closure.sh` et oras 1.3.6, pas avec `publier-fermeture`. Son usage tel quel pour les 235 fichiers est à vérifier.
   - Elle écrit sous `builds/fermetures/**`, pas sous `deps/sample-app/mock-buildroot-lock`. Le contenu et le digest de la fermeture de la plateforme sont à mesurer ; ce que `createrepo_c` date dans `repodata` n'est pas lu.
5. **Fermeture dans `resolvedDependencies`** : `preparer-deb` déclare un `*_ARTIFACT_INPUTS` par fermeture (vérifié dans le dépôt), et D15 de S4d1 de la 06 les a retrouvés dans la provenance (mesuré, `06-deb-sbuild/resultats/s4d-predictions.md`). La même forme convient à une préparation rpm (lecture).
6. **Sources**
   - `preparer-deb` reconstitue l'arbre de l'archive de `sources.sh` : commit de Forgejo, `vendor/` depuis la fermeture applicative, `marked` contrôlé par le lockfile. Vérifié dans le dépôt.
   - `sample-app.spec` (Release 2) prend cette archive en `Source0` et lance `node build.mjs` ; `nodejs` est en `BuildRequires`. Vérifié dans le dépôt. Une préparation rpm peut reprendre ce chemin (lecture).
   - L'égalité octet à octet de la `Source0` avec l'archive de `sources.sh` n'est pas établie : le rpm de M4 peut différer de `864d55f4…`. À mesurer.
7. **Mock dans un pas de Tekton** : il n'a tourné que dans des pods lancés à la main et alimentés par `kubectl exec`. Dans Tekton, la fermeture arrive par un workspace. À mesurer, après un pod d'essai (levier du 10/11/2026 : pod d'essai avant toute tâche neuve).
8. **Porte** : `_attendues` (`porte.rego`, ligne 124) ne connaît que `preparer-entrees` et `preparer-deb` (vérifié dans le dépôt). Le commentaire des lignes 87 et 88 laisse hors du jugement l'artefact de packaging du deb et la provenance de son image de build (lecture).
9. **Admission des images** : un pod Kata privilégié de `builds`, label `construire-rpm`, image `essais-05/mock-rocky9@sha256:99790c13…`, a été admis (dry-run serveur, puis prêt) le 17/11/2026 à 20:09 UTC (mesuré, `s1-m3_build1.log`). Un pod créé par une TaskRun n'a pas été essayé.
10. **Réserve C (Kyverno)** : dans le dépôt, les ImageValidatingPolicy de la 08 visent des globs nommés (`bench/*`, `builds/essai-signature*`) et, pour certaines, des namespaces listés (lecture de `kyverno-admission.sh` et de `reserve-c/ivpol.tmpl.yaml`). Aucune ne vise `essais-05` ni `builders/` dans le dépôt. L'état en service est à relever (point 11). Kyverno reste en 1.19.2.
11. **Relevé de l'état en service**, avant toute prédiction : ConfigMap `porte`, gabarits, déclencheurs, politiques d'admission et de réseau de `builds`, comparés au dépôt champ par champ (leçon de S4d2a de la 06). Lecture seule ; à lancer sur un accord nommé.

## Trois points qui ne se transposent pas de la 06

**A. Conflit avec D3 (a).**
- D3 (a), décidée le 10/11/2026, et sa lecture du 12/11/2026 (« Oui, Kata à la main ») placent la résolution, `--calculate-build-dependencies`, « dans Tekton en M4 ». Vérifié dans le dépôt.
- Le modèle du deb (verrou versionné avec le packaging, publié par l'hôte, S4c) la laisserait hors de Tekton.
- Lue à la lettre, D3 (a) met dans la liste revue une tâche qui lance mock (pod Kata privilégié, D1 a) et lit vault 9.7 sur Internet. Le levier refusé le 10/11/2026 (« pas d'image d'outils construite avec le réseau ») visait déjà ce cas : une tâche privilégiée ouverte sur Internet dans `trusted_tasks` (lecture).
- Question au propriétaire, posée plus tard.

**B. Les images.** C'est le point dont dépend le reste.
- Le verrou fixe l'image de bootstrap par `pull_digest` (manifeste `f0ccf105…`) et par `image_digest` (`18d64b03…`), le digest que mock calcule et vérifie (« Checking image digest », journal de `hermetique`) ; la fermeture la porte en dossier `dir:`. Vérifié dans le dépôt.
- L'image d'outillage de M3 est `essais-05/mock-rocky9@sha256:99790c13…`.
- Les deux images ont été construites par l'hôte depuis des racines installées dans un pod Kata **avec réseau** : 5694 s d'installation pour l'outillage (`racine`), 761 s pour le bootstrap (`boot_racine`), causes inconnues. Chaque racine n'a été construite qu'une fois (`chrono.tsv`). Seul le passage de l'archive à l'image a été répété, avec le même digest (`image` contre son banc, `boot_image` contre son passage local).
- **Rejeu de zéro (M5)** : Zot vidé, les deux images d'essai disparaissent. Les racines refaites n'ont jamais été comparées : un bootstrap refait peut changer `image_digest`, donc le verrou et la fermeture, quelle que soit l'option.
- **Changer d'option plus tard** coûte, à chaque nouveau digest d'image : de nouveaux bundles signés pour les tâches qui la citent, une nouvelle revue de `taches.yml` et de nouvelles écritures définitives dans Zot.
- Quelle que soit l'option, la pipeline construit depuis une nouvelle fermeture, publiée par la plateforme (point 4).
- Options :
  1. **Les deux images d'essai par digest, telles quelles, dans la pipeline signée.** Ce sont les deux images de M2 et de M3. Leurs racines ont été installées avec réseau, ce qui relève du levier refusé le 10/11/2026 ; la lecture est au propriétaire. Leur provenance n'est pas celle de la plateforme ; la porte ne juge déjà pas l'image de build du deb (point 8). Comparables : S4c, S4b et S4d1 de la 06, 3,13 h, sans le point A.
  2. **Image d'outillage reconstruite par une pipeline `builders/` sans réseau**, sur le modèle de S4a (décision 4 de la 06) ; bootstrap d'essai gardé par digest. M3 aura été mesuré sur une autre image d'outillage. Il faut en plus un prefetch des rpm d'outillage (Rocky 9.8 et EPEL), sans comparable. Comparables : option 1 et S4a, 4,14 h. S4a a demandé 11 accords, dont 6 que le pod d'essai aurait évités (README de la 06, additif de 23:52 UTC le 10/11/2026).
  3. **Les deux images reconstruites par la plateforme.** Le digest du bootstrap change : verrou, fermeture et builds de M3 sont à refaire. Si D3 (a) est lue à la lettre (point A), le verrou est de toute façon calculé dans Tekton, et ce coût-là n'en est plus un. Comparables : option 2 et la brique 05 de `boot_racine` à M3, 8,93 h, plus le prefetch d'outillage.
- Pour le deb, le propriétaire a choisi la construction par la plateforme (décision 4 du 10/11/2026, 22:12 UTC), contre ma recommandation d'alors.
- **Recommandation, sous condition** : l'option 1 pour M4, comme le chemin le plus court vers sa preuve, si le propriétaire lit son refus du 10/11/2026 comme visant une tâche ouverte sur Internet dans la liste revue, et non des images construites hors de la plateforme. Sinon, l'option 3, la seule cohérente avec ce refus, au coût le plus haut. L'option 2 paie S4a sans lever le point : le bootstrap y reste construit avec réseau. Dans les trois cas, le rejeu de zéro reste à régler avant M5.

**C. Portée.** La porte étendue à la voie rpm, le déclencheur et le rattrapage (S4d2 et S4d3 de la 06, 0,95 h) dépassent la preuve de M4. Les « Limites connues » de ce README disent que ce travail n'est pas chiffré ici. Proposé : une extension à part, comptée dans la règle des 2×.

## Transpositions directes, à confirmer plus tard

- Pipeline `sample-app-rpm` à part, comme `sample-app-deb`.
- Sujet : le manifeste OCI qui porte le rpm, publié par `publier-image` inchangée sous `builds/sample-app-rpm`, avec le compte existant (modèle : `builds/sample-app-deb`, `s4d.sh` ligne 56).

## Question posée

Les images (point B). Le conflit D3 (point A), la portée (point C), les transpositions et le relevé de l'état en service (point 11) viendront après.
