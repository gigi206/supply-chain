# Brique 05, M4a : prédictions (17/11/2026, écrites à 21:05:37 UTC, avant tout lancement)

Script : [`../m4a.sh`](../m4a.sh) (`92f5e8c7…`). Découpage décidé le 17/11/2026 (« Oui, ce découpage ») ; verrou hors de la plateforme (« Hors plateforme ») ; images d'essai (« Option 1 ») ([carte](m4-carte.md)).

Rien n'est lancé. Accord demandé maintenant : `releve` seul (lecture seule).

**`verrou` et `publier` attendent la carte de M4b.** `verrou` fixe le digest de l'artefact, et son contenu n'est pas arrêté : le verrou porte `url` et `sigmd5`, ni sha256 ni taille, alors que `prefetch-deb` s'appuie sur un sha256 et une taille fixés par la pipeline ; la fermeture de M2 contient aussi des fichiers hors du verrou (rpm de mock, `repodata`). Ce que `prefetch-rpm` lira se décide dans la carte de M4b. La liste de la collecte de M2 (`s1-collecte.log`) est un candidat à joindre, non examiné.

## Vérifié à sec, hors cluster et hors Zot

- `bash -n` passe ; shellcheck 0.11.0 ne relève que SC2154 (variables de `commun.sh`) et SC2015 (`attendu`), mêmes types que `s4c.sh` de la 06.
- **Banc de `releve`** ([script](m4a-banc.sh), [journal](m4a-banc.log)) : la vraie étape, lancée par `lancer`, contre un faux `kubectl` et un faux `oras` ; 21 OK, 0 KO. Mesuré sur le banc : écart de valeur, champ en service seulement, objet absent et clé changée signalés ; aucune clé affichée (ni par chemin, ni par contenu) ; ConfigMap `porte` comparée clé par clé, fichiers de la 07a compris ; un refus de Zot (401) donne « NON CONCLUANT », seul un « not found » donne « absent » ; journal et `chrono.tsv` dans le banc.
- Non archivé : les onze sélections `yq` rendent chacune un seul document du bon type, nom et namespace ; le contrôle du verrou passe sur `s1-verrou_derivee.json` et refuse un `pull_digest` faux ; le gabarit de la `VerificationPolicy` est rendu avec une clé factice.
- Non archivé : la poussée de l'artefact dans deux layouts OCI locaux, faite dans un dossier d'essai du scratchpad avec les mêmes deux fichiers : même digest aux deux poussées, `sha256:41c639b7f0f283cb245c61b315cc6f7842a00dc5d7a6819d5b96d08b3db3a5b8` ; fichiers tirés égaux (`sample-app.spec` `918a83f5…`, verrou `b6d0f8f1…`). Cette valeur n'est pas archivée ailleurs que dans ce texte.

## `releve` (lecture seule)

| # | Prédiction | Confiance |
|---|---|---|
| R1 | `construction-rpm-sans-sortie` : « égal », 0 écart | Haute : posée depuis ce fichier à 20:07:12 UTC, `spec` sans valeur par défaut connue |
| R2 | `prefetch-rpm-sortie` et `builds-sans-internet` : « égal » | Moyenne : posées depuis le dépôt le 16/11 (`rpm_appliquer`) ; défauts éventuels de Cilium non lus |
| R3 | Les sept `ValidatingPolicy` (08 et 08c) : aucun écart « dans le dépôt seulement » ni de valeur ; des champs « en service seulement » sont possibles | Faible : défauts de Kyverno 1.19.2 non lus, aucun relevé champ par champ de ces objets archivé |
| R4 | `VerificationPolicy taches-plateforme` : « égal » | Moyenne : la fin de ligne de la clé rendue peut différer de celle posée |
| R5 | ConfigMap `porte` : les neuf clés tirées de fichiers de politique (08 et 07a) présentes et égales au dépôt | Moyenne : derniers commits de `porte.rego` et `taches.yml` le 11/11 ; mise à jour en service depuis non relevée |
| R6 | Aucune ImageValidatingPolicy ne vise `essais-05/*` | Moyenne : lecture du dépôt seulement |
| R7 | Zot, en anonyme : fermeture applicative `50dc73f7…` présente | Haute : `publier-fermeture` la relit en lecture anonyme |
| R8 | Zot, en anonyme : images `99790c13…` et `f0ccf105…` présentes | Faible : la lecture anonyme de `essais-05/` par l'hôte n'a jamais été mesurée (`s1.sh`) ; un refus donnerait « NON CONCLUANT », un résultat et non une panne |
| R9 | Zot : `entrees/sample-app/packaging-rpm:m4a` non lu (absent) | Haute |
| R10 | `config-defaults` égal à `tekton-defauts.yaml` (08c) ; `feature-flags` avec `trusted-resources-verification-no-match-policy=fail` | Moyenne : posés par la 08c et la 08 (lecture du dépôt seulement) |
| R11 | `releve` sort en code 0 et n'écrit rien dans le cluster ni dans Zot | Haute : uniquement des `get` et des `manifest fetch` |

## `verrou` (hôte, hors ligne ; attend la carte de M4b)

| # | Prédiction | Confiance |
|---|---|---|
| V1 | sha256 du verrou `b6d0f8f1…` | Haute |
| V2 | 222 rpm, 222 nom.arch distincts, aucune URL hors de vault 9.7, `pull_digest` `f0ccf105…`, `image_digest` `18d64b03…`, `bootstrap_image_ready` vrai | Haute (essayé à sec) |
| V3 | `poc/packaging/verrou-rpm.json` écrit, sha256 `b6d0f8f1…` | Haute |
| V4 | Deux poussées locales au même digest, `sha256:41c639b7…` | Haute (essayé à sec, mêmes fichiers) |

## `publier` (Zot, accord à part ; attend la carte de M4b)

| # | Prédiction | Confiance |
|---|---|---|
| P0 | Verrou du dépôt inchangé depuis `verrou` | Haute |
| P1 | Deux poussées dans Zot au même digest, égal à V4 | Haute : même forme que `packaging-deb` (C5 de S4c) |
| P2 | Fichiers tirés par digest égaux au dépôt | Haute |

## Résultat de `releve` (17/11/2026, de 21:06:25 à 21:06:27 UTC, « Oui, lance-le » ; note écrite à 21:07:29 UTC)

Code 0 ([journal](m4a-releve.log), `890f96c8…`). Rien écrit dans le cluster ni dans Zot (R11 : lecture du script, que des `get` et des `manifest fetch`). La liste des ValidatingPolicy en service contient le motif masqué : elle est lue sous masque, et décomptée sans afficher le nom en cause.

| # | Résultat |
|---|---|
| R1 | **Tenue.** `construction-rpm-sans-sortie` égale, 0 écart. |
| R2 | **Tenue.** `prefetch-rpm-sortie` et `builds-sans-internet` égales, 0 écart. |
| R3 | **Non tenue.** Les quatre ValidatingPolicy comparées de la 08 sont égales. Les trois de la 08c comparées diffèrent d'un écart de valeur chacune : `spec.validationActions[0]`, `Audit` dans le dépôt, `Deny` en service. Origine lue dans le dépôt : l'étape `h5_deny` de `durcissement.sh` (08c) pose ces règles en `Deny` par `sed` sur ce même fichier (`regles_deny`, ligne 375) ; le fichier du dépôt reste en `Audit`. Ce n'est pas une dérive : ces règles refusent en service. |
| R4 | **Tenue.** `VerificationPolicy taches-plateforme` égale, clé comprise (sha256 seul comparé). |
| R5 | **Tenue.** Les neuf clés tirées de fichiers de politique (08 et 07a) sont présentes et égales au dépôt. |
| R6 | **Tenue.** Aucune ligne ImageValidatingPolicy : aucune n'est en service (lecture du script : une erreur de `kubectl` aurait écrit « type absent »). |
| R7 | **Tenue.** Fermeture applicative `50dc73f7…` présente en lecture anonyme. |
| R8 | **Tenue.** Images `99790c13…` et `f0ccf105…` présentes en lecture anonyme : première mesure de cette lecture depuis l'hôte. |
| R9 | **Tenue.** `packaging-rpm:m4a` absent (« failed to find »). |
| R10 | **Tenue.** `config-defaults` égal à la 08c ; `trusted-resources-verification-no-match-policy=fail`. |
| R11 | **Tenue.** Code 0. |

**Lacune du relevé : deux ValidatingPolicy en service n'ont pas été comparées.**
- En service, 9 ValidatingPolicy ; aucune ClusterPolicy ni Policy de Kyverno.
- Les 9 se rangent toutes dans le dépôt : 5 dans `admission.yaml` (08), 4 dans `durcissement.yaml` (08c).
- Le relevé n'en a comparé que 7. Manquent `stepactions-interdites` (08, `admission.yaml` ligne 178) et la quatrième de la 08c, dont le nom contient le motif masqué.
- Cause : ma liste venait de lectures tronquées (`head`) des deux fichiers. Les deux règles touchent les pods et les tâches de M4 : la première refuse toute StepAction (README de la 08).

**Autres constats**
- NetworkPolicy de `builds` : `builder-sans-sortie`, `construction-deb-sans-sortie`, `construction-rpm-sans-sortie`, `construction-sans-sortie`. CiliumNetworkPolicy : `builds-sans-internet`, `prefetch-deb-sortie`, `prefetch-rpm-sortie`, `prefetch-sortie`.
- ConfigMap `porte` : cinq autres clés, non comparées par construction (`ca-poc.crt`, `chains.pub`, `scanner.pub`, `tsa-racine-confiance.json`, `vsa.pub`).

## Étape `politiques`, complément de `releve` : préparée et prédite (17/11/2026, 21:09:27 UTC, « Oui, complète-le »)

`m4a.sh` modifié (`fb23b869…`) : nouvelle étape `politiques`, lecture seule, journal à part (`m4a-politiques.log` ; celui de `releve` n'est pas réécrit).
- Les ValidatingPolicy de `admission.yaml` (08) et de `durcissement.yaml` (08c) sont énumérées par `yq` (sans séparateur de documents, option `-N`, essayée), et non plus écrites à la main : la lacune venait de là.
- Celles de la 08c sont comparées au fichier rendu comme par `h5_deny` (même `sed`, `Audit` remplacé par `Deny`), ce qui sépare la bascule connue d'une vraie dérive.
- L'ensemble des noms en service est confronté à celui du dépôt.
- Banc ([script](m4a-banc-politiques.sh), [journal](m4a-banc-politiques.log)), faux `kubectl` : 7 OK, 0 KO (5 et 4 politiques comparées, écart injecté signalé, 08c égale une fois rendue, nom intrus et nom absent signalés, aucun appel imprévu).
- `bash -n` passe ; shellcheck : SC2154 et SC2015 seulement, comme avant.

| # | Prédiction | Confiance |
|---|---|---|
| PO1 | Les cinq ValidatingPolicy de la 08 égales, `stepactions-interdites` comprise | Moyenne : quatre égales à `releve` ; `stepactions-interdites` jamais comparée |
| PO2 | Les quatre de la 08c égales au fichier rendu en `Deny` | Moyenne : trois égales à ce rendu près à `releve` ; la quatrième jamais comparée (`h5_deny` exige qu'aucune ne reste en `Audit`, lecture) |
| PO3 | Noms : 9 dans le dépôt, 9 en service, aucun en service hors du dépôt, aucun absent | Haute : mesuré à `releve` (9 noms, tous rangés dans le dépôt) |
| PO4 | Code 0, rien écrit dans le cluster ni dans Zot | Haute : uniquement des `get` |

## Résultat de `politiques` (17/11/2026, de 21:10:42 à 21:10:43 UTC, « Oui, lance-le » ; note écrite à 21:11:07 UTC)

Code 0 ([journal](m4a-politiques.log), `f38fc773…`), lecture seule. La ligne de la quatrième politique de la 08c contient le motif masqué : lue sous masque, elle commence par « égal » et compte 0 écart.

| # | Résultat |
|---|---|
| PO1 | **Tenue.** Les cinq ValidatingPolicy de la 08 sont égales au dépôt, `stepactions-interdites` comprise. |
| PO2 | **Tenue.** Les quatre de la 08c sont égales au fichier rendu comme par `h5_deny` : l'écart de R3 est exactement la bascule `Audit` vers `Deny`, et rien d'autre. |
| PO3 | **Tenue.** 9 noms dans le dépôt, 9 en service, aucun hors du dépôt, aucun absent. |
| PO4 | **Tenue.** Code 0. |

**Lacune de `releve` comblée.** Les neuf politiques d'admission de Kyverno en service sont celles du dépôt, celles de la 08c en `Deny`. Avec `releve`, l'état en service dont M4 dépend est relevé, sauf gabarits et déclencheurs (hors de M4). `verrou` et `publier` attendent la carte de M4b.

## Résultat de `verrou` (18/11/2026, à 09:19:18 UTC, « Oui » ; note écrite à 09:19:45 UTC)

Code 0, en moins d'une seconde ([journal](m4a-verrou.log)). `m4a.sh` = `fb23b869…` : seulement des ajouts depuis les prédictions (l'étape `politiques`), `etape_verrou` inchangée. Ordre consigné dans la [carte de M4b](m4b-carte.md) : après `essai_tache`, passée le même jour.

| # | Résultat |
|---|---|
| V1 | **Tenue.** Verrou de `verrou_derivee` `b6d0f8f1…`. |
| V2 | **Tenue.** Version 1.1.0, 222 rpm, 222 nom.arch distincts, aucune URL hors de vault 9.7, `pull_digest` `f0ccf105…`, `image_digest` `18d64b03…`, `bootstrap_image_ready` vrai. |
| V3 | **Tenue.** [`poc/packaging/verrou-rpm.json`](../../../packaging/verrou-rpm.json) écrit, sha256 `b6d0f8f1…`. |
| V4 | **Tenue.** Artefact : `sample-app.spec` (`918a83f5…`) et `verrou-rpm.json`. Deux poussées en layout local, même digest `sha256:41c639b7…`, celui de l'essai à sec. |

Rien écrit dans Zot ni dans le cluster (lecture du script : layouts locaux seulement). Reste `publier` (P0 à P2), qui écrit dans Zot ; accord à part.

**Relevé « avant » de `publier`** (note du 2026-11-18, écrite à 09:23:48 UTC ; lecture seule ; [relevé](m4a-publier-zot-avant.log)) :
- À 09:23:32 UTC, le dépôt `entrees/sample-app/packaging-rpm` n'existait pas : `crane ls` répond `NAME_UNKNOWN`, code 1.
- `crane catalog` compte 144 lignes (même méthode qu'au relevé de `boot_image`, `s1-boot-image-zot-avant.log`).
- `/` de sc-stockage, qui porte `/var/lib/zot` : 15 544 553 472 octets utilisés, 4 476 362 752 libres. C'est 5 963 776 octets de plus qu'à 09:10:08 UTC ([relevé](m4b-zot-fs.log)), sans écriture de la brique entre les deux ; l'origine n'est pas relevée.
- Aucune fonction du chemin de `publier` n'a changé depuis les prédictions : `etape_verrou`, `etape_publier`, `pousser`, `fichiers` sont au même texte qu'en `2bc295f`, et `commun.sh` de la 08, qui porte `auth_zot`, n'a aucun commit depuis.

Suite : accord d'écriture dans Zot (`publier`, `entrees/sample-app/packaging-rpm:m4a`, compte `poc-ecriture`, dépôt définitif), digest attendu `41c639b7…`.
