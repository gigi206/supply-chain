# Brique 05, carte de M4c, préparée à sec (18/11/2026, écrite à 13:48:17 UTC)

**Interprétation** : le « Continue » reçu après le `/compact` (heure non relevée) vaut permission de préparer à sec, sous l'accord permanent du 18/11. Rien n'a été lancé ni écrit dans Zot, le cluster ou les VM. Aucune tâche, aucun script, aucune prédiction. Découpage décidé : [carte de M4](m4-carte.md), note « Oui, ce découpage ». Plan relu par le conseiller avant l'écriture.

**Objet de M4c** : la pipeline `sample-app-rpm`, lancée depuis l'hôte comme S4d1 de la 06. Elle enchaîne `preparer-rpm` (runc), `construire-rpm` (Kata) et `publier-image` (inchangée), et Chains en signe la provenance. **Preuve de M4** (tableau des jalons) : sujet rpm signé (le manifeste OCI qui porte le rpm, sous `builds/sample-app-rpm`), digest de la fermeture dans `resolvedDependencies`.

## Effort

- Brique 05 : 167 commits, **21,93 h** (date d'auteur, écarts d'au plus 1 h) à `bdbe204`, relevé à 13:47:13 UTC ([relevé](temps-05-1211.log)). La méthode retrouve les 18,83 h archivées à `312efce`.
- Estimation : 2,5 pw ; décision avec le propriétaire à 5 pw. Les heures ne sont pas converties en pw.
- Comparable : S4d1 de la 06, 2,10 h ([relevé](m4-projection-06.log)).

## Entrées, toutes fixées par digest dans la pipeline signée

| Entrée | Référence | Origine |
|---|---|---|
| commit | `6391fd43…`, `https://sc-stockage.poc.test:3000/workspace/sample-app.git` (arbre `30e808ff…` = `poc/sample-app`) | `s4d.sh` de la 06, vérifié dans le dépôt |
| fermeture rpm | `builds/fermetures/sample-app-rpm@sha256:2a9e2ea7…` | M4b |
| fermeture applicative | `builds/fermetures/sample-app-sources@sha256:50dc73f7…` | S4b de la 06 |
| packaging rpm | `entrees/sample-app/packaging-rpm@sha256:41c639b7…` : `sample-app.spec` (`918a83f5…`, égal au dépôt) et `verrou-rpm.json` (`b6d0f8f1…`) | M4a |
| images | `plateforme/outils-prefetch@sha256:68e0ae70…` (git, go, python3), `plateforme/outils-horodatage@sha256:c7bebae2…` (oras, busybox), `essais-05/mock-rocky9@sha256:99790c13…` | `preparer-deb` de la 06 ; « Option 1 » |
| `publier-image` | `tekton/tasks/publier-image@sha256:d21931f3…` | liste revue |

## Points de la carte

Chaque point est marqué « vérifié dans le dépôt », « mesuré » (journal archivé), « (lecture) » ou « à mesurer ».

1. **Deux tâches neuves, une inchangée.**
   - `construire-rpm` doit porter ce nom : `construction-rpm-sans-sortie`, posée depuis M3, la sélectionne par `tekton.dev/task` (vérifié dans le dépôt).
   - `preparer-rpm` et `construire-rpm` sont neuves : signature, bundles, et une **revue de `taches.yml`** à demander. `publier-image` reste inchangée, comme pour le deb.
2. **`preparer-rpm`, sur le modèle de `preparer-deb`.**
   - Les pas `sources` (clone de Forgejo, `git archive`) et `assemblage` (`vendor/` sans réseau, `marked` contrôlé par le lockfile) sont repris tels quels. Ainsi, l'égalité mesurée en S4d1 entre `entrees/src` et l'arbre de l'archive de `sources.sh` se transporte. Vérifié dans le dépôt pour le deb ; pour le rpm, à mesurer.
   - Le pas `entrees` tire par digest la fermeture rpm, la fermeture applicative et l'artefact de packaging (`oras`), puis copie le spec et le verrou. Il déclare `CHAINS-GIT_URL`, `CHAINS-GIT_COMMIT` et un `*_ARTIFACT_INPUTS` par artefact. Il ne reprend pas la confrontation du deb (point 3).
   - **Réseau** : aucune politique du dépôt ne nomme `preparer-deb`, qui joint Forgejo et Zot sous `builds-sans-internet` (refus des adresses publiques, `NotIn` à `prefetch-gomod`, `prefetch-deb` et `prefetch-rpm`). Vérifié dans le dépôt. `preparer-rpm`, absent de ce `NotIn`, recevrait le même traitement (lecture). **Aucun changement du cluster prévu** ; à mesurer par le pod d'essai.
   - `oras pull` de la fermeture rpm par l'image d'outils, sur les chemins à « : » et « @ » du dossier `dir:` : à mesurer. L'étape `comparaison` de M4b l'a tirée sur l'hôte, avec l'`oras` de `mise`.
3. **Confrontation de la fermeture au verrou : dans `construire-rpm`, avant mock.**
   - Le verrou est du JSON (`url` et `sigmd5` par rpm), et les images de `preparer-deb` n'ont pas de `jq` (busybox). La boucle `read` de `preparer-deb` ne se transpose pas.
   - L'image `mock-rocky9` porte `python3` (3.9.25) et `rpm` (4.16.1.3), mais ni `jq`, ni `git`, ni `oras`. Vérifié dans les journaux de `racine`.
   - Contrôles prévus, par `python3 -I` et `rpm -qp` :
     - les 222 noms du verrou (dernier segment des `url`) forment exactement l'ensemble des rpm sous `depot/` ;
     - le `sigmd5` de chaque rpm est égal à celui du verrou ;
     - le `manifest.json` du dossier `dir:` est égal au `pull_digest` du verrou (`f0ccf105…`) ;
     - aucun autre fichier hors de `repodata/` et du dossier `dir:`.
   - **Portée** : le `sigmd5` est un MD5. Le sha256 de chaque rpm n'est pas ancré par le verrou : il l'est par la liste revue, paramètre de la pipeline de la fermeture, relue dans la provenance de `2a9e2ea7…` (PV7 de M4b, mesuré).
4. **Sources : date de `Source0` (vrai choix, question suivante).**
   - `sources.sh` date l'archive `sample-app-1.0.0.tar.gz` (`07521c1e…`, celle de M3) par le dernier commit de `poc/sample-app` du dépôt principal, soit 1793229566 (`3da431db`, 28/10/2026 23:19:26 UTC). Vérifié dans le dépôt.
   - Le commit de Forgejo `6391fd43…` a été créé par `stockage.sh` avec une date de commit fixée au 29/10/2026 00:00:00 UTC, soit 2434 s plus tard. Vérifié dans le dépôt.
   - Une tâche qui ne voit que le commit de Forgejo ne peut donc pas retrouver `07521c1e…` par la date du commit. Le src.rpm différerait alors de celui de M3 (`c802e60a…`). Pour le rpm binaire (`864d55f4…`), rien n'est établi : à mesurer.
   - Options :
     - (i) époque fixée dans la pipeline signée, égale à celle de `sources.sh` : M3 reste la référence, mais la date ne suit pas le commit ;
     - (ii) date du commit construit : la tâche est autonome, mais M3 n'est plus comparable ;
     - (iii) date du `%changelog` du spec, comme l'orig du deb (option 1 du 14/11/2026) : M3 n'est plus comparable non plus.
   - **Lieu** : l'archive serait faite dans `construire-rpm`, comme l'orig dans `construire-deb`, avec le `tar` 1.34 et le `gzip` 1.12 de Rocky (vérifié dans les journaux de `racine`). L'égalité de leur sortie avec celle de l'hôte est à mesurer, dans le pod d'essai.
5. **`construire-rpm` : mock dans un pas de Tekton.**
   - Pod Kata privilégié, root, `--isolation=simple`, limites 2 CPU et 6 Gi, comme les builds de M3 (`s1.sh`, vérifié dans le dépôt ; M3 mesuré : uid 0, 3 vCPU).
   - Le `podTemplate` du PipelineRun pose `runAsNonRoot` et l'uid 65532 au niveau du pod (`pr_json` de `s4d.sh`). Le pas de mock les surcharge au niveau du conteneur (lecture). L'admission d'un pod root, privilégié, sous Kata et au label `construire-rpm` est mesurée en M3 (pod à la main) ; par une TaskRun, elle est à mesurer.
   - Le PipelineRun de `m4c.sh` ne porte **aucun `env`** dans son `podTemplate` : cet `env` primerait sur celui des pas des tâches signées (réserve de M4b, lecture).
   - Entrées sur un workspace en lecture seule, fermeture recopiée sous `/w` (tmpfs), comme `construire-deb` copie la sienne. M3 mesuré (build 1) : `/w` utilisé à 312 268 kB avant mock et 1 456 500 kB après, pour une capacité vue de 3 059 832 kB (tmpfs demandé de 4 Gi ; Kata ignore `sizeLimit`, mesure de la 06).
   - Avant mock, les témoins réseau de `construire-deb` (DNS public, Zot, Forgejo, une adresse publique), qui doivent échouer.
   - Mock lisant le dépôt et le dossier `dir:` recopiés depuis un workspace : à mesurer dans le pod d'essai.
   - Layout OCI écrit à la main, comme `construire-deb`. `tar`, `sha256sum` et `stat` sont dans l'image (coreutils 8.32, vérifié dans les journaux de `racine`).
6. **Contenu de l'artefact signé (question posée ci-dessous).** Réservé à cette carte par la carte de M4.
7. **Porte, déclencheur, rattrapage.** M4c n'évalue pas la porte et ne lance ni déclencheur ni rattrapage (« Hors M4 », carte de M4). Correction de portée : la note de résultat de M4b (« à republier avant toute évaluation (M4c) ») plaçait cette republication dans M4c. Elle va avec l'extension de la porte, hors de M4. La note de M4b n'est pas réécrite.
8. **Écritures définitives prévues dans Zot**, chacune préparée à sec avec ses prédictions : `tekton/tasks/preparer-rpm`, `tekton/tasks/construire-rpm`, `tekton/pipelines/sample-app-rpm`, `builds/sample-app-rpm`. Le disque de Zot sera relevé avant toute écriture (PT7 de M4b non tenue : 4,49 Go libres ; `/` de sc-stockage grossit sans écriture attribuée à la brique).
9. **Étapes envisagées**, sur le modèle de `s4d.sh`. Les deux pods d'essai sont prévus d'emblée : la 06 a payé deux PipelineRuns en échec dans `preparer-deb` pour l'apprendre.
   - `prealables` : hôte et lecture seule.
   - `essai_preparer` : pod runc, pas de la tâche en initContainers.
   - `essai` : pod Kata, script de `construire-rpm`.
   - `taches` : signatures et bundles, puis revue de `taches.yml`.
   - `pipeline` : deux PipelineRuns.
   - `comparaison` : le rpm extrait de la couche, confronté à M3 selon le point 4.
   - `provenance`.

## Question posée

Le contenu de l'artefact signé (point 6) : le rpm seul, ou le rpm et le src.rpm.

**Recommandation** (relue par le conseiller) : **le rpm seul**, pour trois raisons :
- c'est la décision (a) du 11/11/2026 pour le deb ;
- `publier-image` reste inchangée ;
- le sujet signé ne dépend pas de `Source0` à l'octet près (point 4).

Le sha256 du src.rpm irait au journal du TaskRun.

**Question suivante** : la date de `Source0` (point 4). Ma recommandation, relue par le conseiller, sera l'option (i) pour M4c, par parité avec le deb, comparé à S3, et avec la limite inscrite.

## Note datée du 18/11/2026, écrite à 13:52:55 UTC : décision « rpm seul » sur le contenu de l'artefact (point 6)

**Décision du propriétaire** : « Ok » (réponse reçue avant 13:52:55 UTC, heure exacte non relevée). Elle répond à la question « Retenez-vous le rpm seul ? », posée après le rappel de l'avis du conseiller. Ce n'est un accord pour aucune mesure ni aucune écriture.
- L'artefact signé contient **le rpm binaire seul**, dans un manifeste d'image OCI écrit à la main (une couche tar non compressée), comme le deb (décision (a) du 11/11/2026). `publier-image` est inchangée.
- Le src.rpm n'est pas publié. Son sha256 et son NEVRA vont au journal du TaskRun de `construire-rpm`.
- Conséquence : le point 4 (date de `Source0`) ne pèse plus sur le sujet signé. Il ne pèse que sur la comparaison avec M3 : le src.rpm (`c802e60a…`) et, selon la mesure, le rpm (`864d55f4…`).

**Question suivante** : la date de `Source0` (point 4), options (i), (ii) et (iii).

## Note datée du 18/11/2026, écrite à 13:54:20 UTC : décision « option (i) » sur la date de `Source0` (point 4)

**Décision du propriétaire** : « Ok » (réponse reçue avant 13:54:20 UTC, heure exacte non relevée). Elle répond à la question « Retenez-vous l'option (i) ? », posée après le rappel de l'avis du conseiller. Ce n'est un accord pour aucune mesure ni aucune écriture.
- L'archive `Source0` est datée par une époque **fixée dans la pipeline signée**, égale à celle de `sources.sh` : 1793229566 (28/10/2026 23:19:26 UTC, dernier commit de `poc/sample-app` du dépôt principal, `3da431db`).
- **Limite inscrite** : la date ne suit pas le commit construit. Construire un autre commit demande une nouvelle pipeline, signée et revue.
- Ce que le conseiller a dit, et rien de plus : ne pas prédire l'égalité du rpm à M3 (`864d55f4…`) sans mesure. Le `tar` 1.34 et le `gzip` 1.12 de Rocky peuvent aussi produire une archive différente de celle de l'hôte (`07521c1e…`), ce qui est à mesurer dans le pod d'essai. L'option (iii) venait de moi ; il ne l'a pas commentée.
- Les deux vrais choix de la carte sont tranchés. La suite est la préparation à sec des tâches et de `m4c.sh` (accord permanent du 18/11), avec les prédictions commitées avant tout lancement.
