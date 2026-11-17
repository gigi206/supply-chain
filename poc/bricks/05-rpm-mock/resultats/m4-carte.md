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

## Note datée du 17/11/2026, 20:47:02 UTC : décision « Option 1 », correction d'une citation, et question sur D3 (a)

**Décision du propriétaire** (réponse reçue avant 20:43:53 UTC, heure exacte non relevée) : « Option 1 ». Ce n'est un accord pour aucune mesure ni aucune écriture.
- M4 prend les deux images d'essai par digest, telles quelles : `essais-05/mock-rocky9@sha256:99790c13…` pour l'outillage, `essais-05/rocky9-bootstrap@sha256:f0ccf105…` pour le bootstrap (`image_digest` `18d64b03…`).
- **Dettes inscrites** : provenance des deux images hors de la plateforme ; racines installées avec réseau ; rejeu de zéro non réglé, à trancher avant M5.

**Correction : le refus du 10/11/2026 a été cité au-delà de son texte.** Le texte commité (README de la 06, additif de 23:52 UTC le 10/11/2026) dit seulement : « (c) est refusé : pas d'image d'outils construite avec le réseau ». Le point A de cette carte lui prête un objet, « une tâche privilégiée ouverte sur Internet dans `trusted_tasks` », et la recommandation du point B pose sa condition sur cette lecture. Cet objet venait de mes notes de travail, pas du dépôt. Le texte commité au-dessus n'est pas réécrit.
- Conséquence : le choix « Option 1 » est consigné tel quel. Il retient des images dont les racines ont été installées avec réseau, ce que la carte indiquait (option 1 : « relève du levier refusé »). La réponse ne dit pas comment le refus du 10/11/2026 se lit désormais ; je ne le tranche pas.

**`prefetch-rpm` : runtime à décider.** Rien dans la réponse ne le fixe.
- Précédents vérifiés dans le dépôt : `prefetch-gomod` et `prefetch-deb` (signée, en service depuis S4a de la 06) tournent sous runc, conformes à Pod Security `restricted`, `runAsNonRoot`, UID 65532 pour `prefetch-deb`, avec une sortie vers des adresses publiques. Les tâches privilégiées de la liste revue (`construire-image`, `construire-builder`, `construire-deb`) n'ont aucune sortie réseau : aucune n'est à la fois privilégiée et ouverte sur Internet (vérifié dans les commentaires de `taches.yml`).
- En S1 et en M2, les gestes de la voie 2 (téléchargement, `rpm -K`, `createrepo_c`, `skopeo copy`) ont tourné en pod Kata privilégié, root. Les faire tourner sous runc, sans root, avec l'image d'outillage est à mesurer dans un pod d'essai.

**Question suivante : le point A, conflit avec D3 (a).** D3 (a) place la résolution, `--calculate-build-dependencies`, dans Tekton en M4. Mock y a toujours tourné en pod Kata privilégié (D1 a), et la résolution lit vault 9.7 sur Internet.
- **Option 1, verrou résolu hors de la plateforme** :
  - le verrou archivé (`b6d0f8f1…`, 222 rpm, calculé par `verrou_derivee`) est repris tel quel, sans nouvelle résolution ;
  - il est publié par l'hôte avec `sample-app.spec`, dans un artefact de packaging rpm sous `entrees/`, sur le modèle de `packaging-deb` (S4c de la 06). C'est une écriture définitive dans Zot, et l'artefact reste hors du jugement de la porte, comme `packaging-deb` ;
  - la configuration de mock n'y entre pas a priori : `--hermetic-build` impose sa propre configuration et relit les options du verrou (relevés du 12/11/2026, lecture) ;
  - transport de la liste vers `prefetch-rpm` à concevoir ; précédent : décision A de S4b de la 06, la liste inscrite par l'hôte dans le gabarit de la pipeline avant signature ;
  - D3 (a) se lirait « résolution hors de Tekton, récupération dans Tekton ». Limite : mettre le verrou à jour demande un passage hors de la plateforme, comme `go.sum`.
- **Option 2, D3 (a) à la lettre** : une tâche de résolution dans la pipeline, Kata privilégié, avec une sortie vers vault 9.7 et Zot.
  - Ce serait la première tâche de la liste revue à la fois privilégiée et ouverte sur Internet (vérifié, voir ci-dessus).
  - `prefetch-rpm-sortie` sélectionne par nom de tâche : la tâche de résolution porte ce nom, ou il faut une sortie de plus et une modification du `NotIn` de `builds-sans-internet` (08c), c'est-à-dire deux changements du cluster.
  - Elle demande un pod d'essai et un cycle de signature de plus.
- **Recommandation** : l'option 1. Elle tient la preuve de M4 (sujet rpm signé, fermeture dans `resolvedDependencies`) au moindre coût, sans résolution neuve ni changement du cluster, et garde la liste revue sans tâche privilégiée ouverte sur Internet. Ce dernier argument est le mien : le refus du 10/11/2026 ne le dit pas. Le prix est une lecture de D3 (a) moins stricte que son texte, et un verrou mis à jour hors de la plateforme.

## Note datée du 17/11/2026, 20:54:54 UTC : décision « Hors plateforme » sur D3 (a), et découpage proposé de M4

**Décision du propriétaire** (réponse reçue avant 20:50:59 UTC, heure exacte non relevée) : « Hors plateforme ». Elle tranche le point A. Ce n'est un accord pour aucune mesure ni aucune écriture.
- Le verrou archivé `b6d0f8f1…` (222 rpm, `verrou_derivee`) est repris tel quel, sans nouvelle résolution. Il sera publié par l'hôte avec `sample-app.spec` dans un artefact de packaging rpm sous `entrees/`, sur le modèle de `packaging-deb`.
- D3 (a) se lit désormais « résolution hors de Tekton, récupération dans Tekton ». Le texte de D3 (a) du 10/11/2026 et sa lecture du 12/11/2026 ne sont pas réécrits ; cette décision les précise.
- Limite inscrite : mettre le verrou à jour demande un passage hors de la plateforme, comme `go.sum`.
- Avant la réponse, j'ai relayé au propriétaire, à sa demande, l'avis du conseiller : même recommandation, avec ses conditions.

**Découpage proposé de M4**, sur le modèle de S4 de la 06. Aucune prédiction, aucun script. Les heures sont celles des commits des comparables ([relevé](m4-projection-06.log)).

| Jalon | Contenu | Écrit dans | Accords | Comparable |
|---|---|---|---|---|
| M4a | Relevé de l'état en service (point 11, avec la présence dans Zot de `builds/fermetures/sample-app-sources@sha256:50dc73f7…`), lecture seule ; puis artefact de packaging rpm `entrees/sample-app/packaging-rpm` : `sample-app.spec` et verrou `b6d0f8f1…`, publié par l'hôte | Zot (une écriture définitive) | un pour le jalon (relevé), un pour l'écriture | S4c : 0,16 h |
| M4b | Pod d'essai de `prefetch-rpm` (runtime) ; tâche `prefetch-rpm` **neuve**, écrite, essayée et signée ; pipeline de la fermeture rpm : liste inscrite par l'hôte dans le gabarit (précédent A de S4b), `publier-fermeture` inchangée si le point 4 tient ; fermeture sous `builds/fermetures/` | Zot (bundles, fermeture), `taches.yml` | pod d'essai, revue de `taches.yml`, chaque écriture | S4b : 0,87 h, plus l'écriture et la signature d'une tâche neuve (dans S4a pour `prefetch-deb`, S4a entier : 1,01 h) |
| M4c | Pod d'essai de `construire-rpm` sous Tekton (point 7) ; pipeline `sample-app-rpm`, lancée depuis l'hôte comme S4d1 : `preparer-rpm` (runc ; commit, fermeture rpm, fermeture applicative `50dc73f7…` de la 06, artefact de packaging), `construire-rpm` (Kata, `essais-05/mock-rocky9@sha256:99790c13…`, `--hermetic-build`), `publier-image` inchangée ; provenance de Chains | Zot (bundles, artefact), `taches.yml` | pods d'essai, revue de `taches.yml`, chaque écriture | S4d1 : 2,10 h |
| Hors M4 | Porte étendue à la voie rpm, déclencheur, rattrapage (point C) ; `tools/index`, cité par les « Limites connues » | cluster, Zot | à décider à l'ouverture | S4d2 et S4d3 : 0,95 h |

**Ce que « Hors M4 » laisse ouvert dans la porte** (lecture).
- `_constructions` (`construire-image`, `construire-deb`), `_attendues` et `_appariement` ne nomment aucune tâche rpm (`porte.rego`, lignes 55, 122 à 125 et 214).
- Une provenance faite de `preparer-rpm` et de `construire-rpm` échapperait donc à `construction_kata` et à `fermeture_plateforme` sans rien refuser : c'est le « succès à vide » noté pour le deb (README de la 06, complément de 21:20 UTC le 10/11/2026, point 11 c), un trou et non une acceptation.
- D'où la condition du deb, reprise ici : **aucun déclencheur ni rattrapage pour le rpm avant que la porte soit étendue** (`taches.yml` : « elle sera étendue en S4d2, avant tout trigger »). Les pipelines de M4 sont lancées depuis l'hôte.
- Le rattachement de cette extension à la règle des 2× sera au propriétaire, à son ouverture : les « Limites connues » disent que ce travail n'est « pas chiffré ici ».

**Écarts avec la ligne M4 du tableau des jalons**
1. Dépôt de sortie : `builds/sample-app-rpm`, et non `artifacts/sample-app/rpm`. Raison lue dans la 06 (carte de S4, point 6) : sous `**`, seul `poc-ecriture` écrit ; `builds/**` a déjà un compte de création seule, celui de `publier-image`.
2. « Sujet rpm signé » : le sujet est le manifeste OCI qui porte le rpm. Le rpm est dans la couche de ce manifeste ; son sha256 se relit en extrayant la couche, comme pour le deb (`construire-deb.yaml`, layout OCI écrit à la main).

**Laissé à la carte de M4c** : le contenu de l'artefact signé, rpm seul ou rpm et src.rpm. Pour le deb, « deb seul » a été un choix explicite du propriétaire, et le src.rpm est l'un des deux fichiers comparés en M3.

**Points à relever en route**
- Le rpm de mock (`a5043350…`) est l'un des 235 fichiers de la fermeture de M2 ; il vient d'EPEL, qui ne garde en général que la dernière construction (HB7). À relever avant les prédictions de M4b.
- `preparer-deb` contrôle la fermeture applicative contre le commit construit (`go mod verify`, integrity du lockfile ; lecture de son en-tête). À vérifier pour le rpm.
- `construire-deb` écrit son layout OCI avec `tar`, `sha256sum` et `stat`. Ces outils sont à vérifier dans la liste des paquets de `mock-rocky9@99790c13…`, figée par « Option 1 ».
- **Repli de M4b** : si `prefetch-rpm` ne passe pas sous runc sans root avec cette image, rien n'est signé et la décision revient au propriétaire. Une tâche de prefetch privilégiée ouverte sur Internet irait contre l'argument donné pour « Hors plateforme », et pourrait rouvrir « Option 1 ».

**Ce que couvrirait un « oui »**
1. L'ordre M4a, M4b, M4c, avec le relevé de l'état en service en tête de M4a.
2. Les deux écarts avec la ligne M4 du tableau des jalons.
3. Porte, déclencheur et rattrapage hors de M4, avec la condition « aucun déclencheur ni rattrapage rpm avant la porte étendue ».
4. Pipeline `sample-app-rpm` à part, et `publier-fermeture` et `publier-image` inchangées tant que leurs points tiennent.

Il ne vaudrait accord pour aucune mesure ni aucune écriture : chaque jalon sera préparé à sec, avec ses prédictions commitées avant tout lancement.

**Recommandation** (relue par le conseiller) : ce découpage. Il suit l'ordre qui a tenu pour le deb (S4c, S4b, S4d1), chaque jalon ne dépend que du précédent, et la preuve de M4 tombe à la fin de M4c sans toucher à la porte ni au cluster.
