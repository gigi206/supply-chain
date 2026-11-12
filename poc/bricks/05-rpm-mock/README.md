# Brique 05 : rpm hermétique avec mock (rocky-9), protocole proposé

Seuil (README, brique 05) : **bit-identique ; 0 pod privilégié sur l'hôte.** Effort estimé : **2,5 pw** ; décision avec le propriétaire à 5 pw.

Règles reprises : projets jugés par le doc 04, rien de « Risqué » (mock : « À surveiller », chemin critique) ; versions épinglées ; empreintes et signatures vérifiées ; prédictions datées et committées avant chaque mesure ; passages ratés archivés ; accord du propriétaire avant tout changement du cluster, de Zot ou d'un système.

## État

**Préparé à sec le 05/11/2026 à 22:21 UTC, rien installé, rien construit.** Seul [`releve-amont.sh`](releve-amont.sh) a tourné : il lit des métadonnées et des textes amont aux tags épinglés, et le seul paquet téléchargé, `uidmap`, est listé sans être extrait ni exécuté ([journal](resultats/releve-amont.log) ; passages incomplets archivés : [premier](resultats/releve-amont-premier-passage.log), [deuxième](resultats/releve-amont-deuxieme-passage.log)). Depuis, à 22:41 UTC, [`sante.sh`](sante.sh) a aussi tourné, en lecture seule : voir l'additif des préalables. Les décisions ci-dessous attendent le propriétaire. Les jalons M1 et suivants n'ont pas de place avant le rejeu RKE2 (08b) : tout ce qui serait posé avant serait effacé par lui.

La brique [06](../06-deb-sbuild/README.md) suit le même plan.

## Ce qui existe déjà

- **Recettes** : [`poc/packaging`](../../packaging/README.md) contient le spec et les sources de sample-app, reproductibles et vendorées (Go et `marked`).
- **Réglages rpm mesurés sur OBS** : [`poc.prjconf`](../../benchmarks/obs/projets/poc.prjconf) fixe `%_buildhost`, `%source_date_epoch_from_changelog`, `%use_source_date_epoch_as_buildtime` et `%clamp_mtime_to_source_date_epoch`. Ils ont donné un rpm identique sur 2 builds, hors signature ([résultats](../../benchmarks/obs/resultats/README.md)). OBS est démonté : le banc ne peut pas être rejoué.
- **Construction sans sortie** : la voie A de la brique 08 (pod Kata privilégié, tâche signée, `construction-sans-sortie`, anti-usurpation par Cilium) est en service pour BuildKit.
- **Fermetures** : la brique 03 archive dans Zot, par digest, et son prefetch tourne encore sur l'hôte.

## Relevé amont (05/11/2026, 22:26 UTC)

| Point | Mesuré | Conséquence |
|---|---|---|
| mock | **6.9-1** et `mock-core-configs` 45.2-1 dans EPEL 9 ; dernière release amont `mock-6.9-1` (01/10/2026) | L'index d'EPEL 9 n'a montré que ces versions : les rpm de mock retenus doivent être archivés, sinon l'image du constructeur ne se reconstruit plus |
| mock dans Debian stable | **Absent** du relevé | L'image du constructeur part d'un système EL, pas de Debian |
| Rocky | 9.8 dans `pub/`, **9.7 dans `vault/`** avec `repomd.xml` et `repomd.xml.asc` (HTTP 200) pour BaseOS, AppStream et CRB | 9.7 est la version du banc OBS ; empreintes des `repomd.xml` au journal |
| Configuration `rocky-9-x86_64`, tag `mock-core-configs-45.2-1` | `mirrorlist=` par défaut, `bootstrap_image=quay.io/rockylinux/rockylinux:9` (tag mobile) | À remplacer par des `baseurl` fixes et une image par digest |
| Documentation hermétique, tag `mock-6.9-1` | Déconseille les dépôts à miroirs pour le verrou ; dit que le mode hermétique ne donne pas à lui seul un build reproductible ; exige une image de bootstrap prête ; le verrou n'est garanti que pour **la même version de mock** | Version de mock identique entre résolution et build, et réglages de reproductibilité gardés |

Séquence amont : `mock --calculate-build-dependencies` (en ligne) produit `buildroot_lock.json`, `mock-hermetic-repo` télécharge les rpm et l'image de bootstrap, `mock --hermetic-build` construit sans réseau.

## Préalables au doc 04

Le protocole introduit des éléments que le doc 04 n'audite pas (recherche du 05/11/2026 sur `podman`, `rockylinux` et `rocky`, sans résultat utile). Rien ne sera utilisé avant leur audit, et un verdict « Risqué » arrêterait la voie concernée :
- **podman**, exigé de fait par l'image de bootstrap de mock ;
- **image `quay.io/rockylinux/rockylinux`**, par digest, avec sa signature si elle existe ;
- les versions exactes de mock et de `mock-core-configs`, déjà auditées comme projet, à repréciser.

**Additif du 05/11/2026, 22:37 UTC, audit fait, rien installé** ([`sante.sh`](sante.sh), journaux : [relevés](resultats/sante-releves.log), [signatures](resultats/sante-signatures.log), [podman](resultats/sante-podman.log) ; passages antérieurs archivés : [relevés](resultats/sante-releves-premier-passage.log), [signatures](resultats/sante-signatures-premier-passage.log), podman [premier](resultats/sante-podman-premier-passage.log) et [deuxième](resultats/sante-podman-deuxieme-passage.log)). **Aucun verdict « Risqué »** ; podman, skopeo et les images Rocky sont « À surveiller », chemin critique (doc 04, §2, §3, §5, §6).

- **skopeo s'ajoute à podman** : `mock-hermetic-repo` télécharge l'image de bootstrap par `skopeo sync`. La liste ci-dessus l'avait omis.
- **Avis critique de podman** (GHSA-2cvf-wqm6-wr9g, plage amont v4.4.0 à v5.8.8 exclu) : Rocky livre 5.6.0-14 en 9.7 et 5.8.2-8 en 9.8, **tous deux dans cette plage**. Les changelogs signés ne citent ce CVE dans aucun des deux. **Cela ne prouve ni l'exposition ni un correctif** : l'absence d'une mention ne vaut pas mesure, et CVE-2026-33414, corrigé en amont en v5.8.2, n'y figure pas non plus. La faille vise `podman run`. Sur les 160 fichiers sous `mock/` au tag, les 133 occurrences de podman et skopeo sont au journal : le code n'appelle que `pull`, `image inspect`, `image mount`, `image umount`, `tag`, `rmi`, `version` et `skopeo sync`. `podman run` n'y apparaît que dans un commentaire et une ancienne entrée du changelog. Le chemin n'est donc pas employé par mock, d'après la lecture du code, sans essai d'exécution.
- **Seule différence mesurée entre 9.7 et 9.8 sur 5 CVE** : CVE-2026-57231 et CVE-2026-19730 figurent au changelog du podman de 9.8, aucun des 5 en 9.7. Le premier vise aussi `podman run`, le second `podman quadlet` ; mock n'emploie ni l'un ni l'autre.
- **9.7 et 9.8 ne jouent pas le même rôle** : le paragraphe D2 traite de la cible. L'image du constructeur, qui porte podman et skopeo, peut être en 9.8, plus récente, sans changer la cible en `vault/9.7`. D'où la décision D4.
- **Versions reprécisées** : mock 6.9-1 (dernière release, 01/10/2026 ; Scorecard 4,9 au 02/11/2026), `mock-core-configs` 45.2-1.
- **Passage raté** : le premier passage des signatures affiche « DIFFÉRENT » parce qu'il comparait l'empreinte d'un `rootfs.tar.xz` à une couche gzip. La méthode était inadaptée, ce n'était pas un écart ; le manifeste et la couche sont identiques au dépôt. Les signatures ont ensuite été rejouées deux fois (comparaison corrigée, puis Rocky 9.8), sans garder le passage intermédiaire.
- **Images non signées** : `rockylinux:9.7` (`sha256:53f4c6dc…`, 23/11/2025) et `:9.8` (`sha256:81019941…`, 25/05/2026). M1 contrôle les rpm de l'image : signatures et `rpm -Va`. Les `repomd.xml` de 9.7 sont vérifiés, clé `21CB 256A…275D`.

## Décisions à prendre

**D1. Lecture du seuil et isolation.** Recommandé : **(a)**.
- (a) mock tourne en pod Kata privilégié (voie A, comme BuildKit). « 0 pod privilégié sur l'hôte » se lit alors comme le test 4 de la 08 : aucun pod privilégié hors Kata. Le root reste celui de l'invité.
- (b) Exiger un pod non privilégié même sous Kata. Non documenté par mock ; il faudrait d'abord mesurer si c'est possible.

**D2. Source des rpm.** Recommandé : **(a)**.
- (a) `vault/rocky/9.7`, en `baseurl` fixes. Dépôt figé, signatures relevées, mêmes versions que le banc OBS. Il ne reçoit plus de correctifs : le scan le montrera.
- (b) `pub/rocky/9.8`. À jour, mais son contenu bouge ; la fermeture devient la seule référence.

**D3. Résolution.** Recommandé : **(a)**.
- (a) Sur l'hôte d'abord, comme le prefetch de la 03, puis dans Tekton en M4.
- (b) Dans Tekton dès le début : plus proche de la cible, mais une panne mêlerait mock, réseau et admission.

**D4. Base de l'image du constructeur** (ajoutée le 05/11/2026, 22:37 UTC, après l'audit). Recommandé : **(a)**.
- (a) Rocky 9.8 par digest pour l'outillage (mock, podman, skopeo), cible en `vault/9.7` selon D2. Podman 5.8.2 avec 2 CVE de plus au changelog, mais deux versions à suivre, et l'avis critique n'est pas démontré corrigé en 9.8.
- (b) Rocky 9.7 partout. Un seul jeu de rpm, mais un podman figé en 5.6.0, sans aucun des 5 CVE au changelog.

## Jalons proposés

Chaque jalon demande un accord. Une étape à la fois, pour qu'un échec soit attribuable.

| Jalon | Contenu | Preuve attendue |
|---|---|---|
| M1 | Après les préalables au doc 04 : image `builders/mock-rocky9` construite par notre chaîne, base Rocky par digest, mock 6.9 épinglé ; essai à la main dans un pod Kata : mock, podman imbriqué, isolation `nspawn` puis `simple` | Journal de chaque essai ; choix d'isolation motivé |
| M2 | Configuration de mock versionnée (D2, digest du bootstrap, macros d'OBS) ; verrou calculé ; signatures des rpm vérifiées ; fermeture poussée dans Zot sous `deps/sample-app/mock-buildroot-lock`, avec le rpm de mock et l'image de bootstrap | Fermeture restaurable par digest ; déduplication mesurée |
| M3 | Deux `--hermetic-build` sans réseau depuis la fermeture restaurée, dans deux répertoires différents | Mêmes NEVRA, même sha256 pour le rpm et le src.rpm ; sinon diffoscope |
| M4 | Tâches signées de prefetch et de build dans la pipeline ; rpm poussé par ORAS sous `artifacts/sample-app/rpm` ; provenance de Chains | Sujet rpm signé, digest de la fermeture dans `resolvedDependencies` |
| M5 | Tests négatifs : rpm de fermeture altéré, sortie réseau pendant le build, pod privilégié hors Kata ; un rejeu de zéro | Refus attendus, témoins acceptés |

## Prédictions (05/11/2026, 22:21 UTC, avant toute exécution)

| # | Prédiction | Confiance |
|---|---|---|
| 1 | M3 donne deux rpm identiques avec les macros d'OBS, sans autre réglage | Moyenne : OBS y arrive, mais avec un autre chemin d'installation du buildroot |
| 2 | Le rpm diffère de celui d'OBS (`57343ca6…`) | Haute : OBS écrit `DISTURL` (srcmd5 de ses sources), ce que mock ne fait pas de lui-même |
| 3 | `nspawn` échoue dans le pod Kata, `simple` passe | Faible : non documenté, à mesurer en M1 |
| 4 | Podman imbriqué est le premier point de blocage, car le mode hermétique dépend de l'image de bootstrap | Moyenne |
| 5 | Build hors ligne en moins de 5 min (rpm d'OBS : 51 s de build) | Moyenne |
| 6 | Fermeture de moins de 1,5 Go | Faible : aucune mesure, ordre de grandeur |
| 7 | `isBuildArtifact: true` suffit à Chains pour un sujet rpm | Faible : déduit du code, jamais testé |
| 8 | L'effort reste sous 2,5 pw grâce aux acquis de la 08 et de la 03 | Moyenne : le point 4 peut l'invalider |

## Limites connues

- **Hors du seuil** : scan et licences du rpm (07a, 13a), signature OpenPGP (09), replay dans le domaine séparé (10). `tools/index` et la porte devront connaître les sujets non-image ; ce travail n'est pas chiffré ici.
- **Root de l'invité** : comme mesuré en 03 F3, un volume `readOnly` peut être remonté en écriture depuis un pod Kata privilégié. L'intégrité des entrées repose sur les empreintes.
- **Rocky 9.7 figé** : choix de reproductibilité du PoC, pas une recommandation pour la plateforme finale.

## Additif du 10/11/2026, 12:14 UTC : D1 à D4 décidées, option (a) partout

Décision du propriétaire : « Briques 05 et 06 : je recommande (a) pour D1 à D4. Tu valides ? », réponse « oui ». Rien n'a été lu ni écrit dans le cluster, Zot ou les VM.
- **D1 (a)** : mock en pod Kata privilégié (voie A). « 0 pod privilégié sur l'hôte » se lit comme le test 4 de la 08 : aucun pod privilégié hors Kata.
- **D2 (a)** : rpm de `vault/rocky/9.7`, en `baseurl` fixes.
- **D3 (a)** : résolution sur l'hôte d'abord, puis dans Tekton en M4.
- **D4 (a)** : outillage sur Rocky 9.8 par digest (mock, podman, skopeo), cible en `vault/9.7`.

**Aucun jalon n'est lancé.** S1 et chaque jalon suivant demandent un accord à part.

## Additif du 12/11/2026, à partir de 14:12:09 UTC : S1 préparé à sec, NON LANCÉ

Sur « Oui, prépare-le ». S1 est le M1 du tableau des jalons, renommé comme dans la 06. Rien n'a été lu ni écrit dans le cluster, Zot ou les VM, et aucune ressource réseau n'a été lue pour ce jalon.

- **Script** : [`s1.sh`](s1.sh), étapes `prealables`, `amorce`, `racine`, `image` et `essais`.
  - **Risque visé** : podman imbriqué dans un pod Kata privilégié (D1 a), puis `nspawn` contre `simple`.
  - **Image** : outillage sur Rocky 9.8 par digest (D4 a), quatre paquets épinglés et contrôlés contre les primary vérifiés sur l'hôte.
  - **mock** : vault 9.7 en `baseurl` fixes (D2 a), image de bootstrap 9.7 tirée de Zot par digest, macros d'OBS.
  - Le build de sample-app n'y est pas hermétique : c'est l'objet de M2.
- **Prédictions** P1 à P12 : [`resultats/s1-predictions.md`](resultats/s1-predictions.md).
- **Vérifié à sec** :
  - `bash -n` passe ;
  - shellcheck 0.11.0 ne relève aucun avertissement, et ses remarques de style sont des mêmes types que pour `s1.sh` de la 06 ;
  - la spec de pod générée par jq est conforme : Kata, root, privilégié, label `prefetch-rpm` ;
  - la configuration de mock passe à Python. Sur un modèle factice, elle remplace les trois `mirrorlist` de BaseOS, AppStream et CRB et laisse ceux de debug.
- **Préalable du propriétaire** : une sortie réseau pour les pods rpm. Elle est proposée dans [`politiques/prefetch-rpm-sortie.yaml`](politiques/prefetch-rpm-sortie.yaml), sur le modèle de `prefetch-sortie` de la 08 :
  - DNS, adresses publiques en 443, et Zot seul parmi les adresses privées ;
  - plus `prefetch-rpm` dans le `NotIn` de `builds-sans-internet`, un fichier de la 08c rejoué par S5b.
  - Rien n'est appliqué, et `s1.sh prealables` s'arrête en KO tant que la politique manque.
- **Calendrier** : après S5b, qui efface Zot. Chaque étape demande un accord nommé.

## Note du 12/11/2026, à partir de 14:20:06 UTC (relecture du conseiller, avant tout lancement)

- **Correction** : « renommé comme dans la brique 06 » est inexact. Le tableau de la 06 nomme ses jalons S1 et S2 dès l'origine, alors que celui de la 05 les nomme M1 à M5. S1 désigne ici le M1 de la 05, pour suivre la numérotation de la 06.
- **Nouvelle étape `hote`**, séparée de `prealables`. Elle reprend les sources, les clés, les repomd, les primary et les quatre paquets épinglés, sans cluster ni Zot.
  - Elle peut tourner avant S5b, sur accord, et tranche alors P2 à P4.
  - Elle sera rejouée avant `racine`, puisque pub/9.8 et EPEL bougent.
  - `prealables` ne garde que le cluster et Zot, et P1 ne porte plus que sur elle.
- **Deux règles en vigueur reprises** :
  - un pod non prêt n'affiche plus ses Events : seulement sa phase et la raison de l'état de chaque conteneur ;
  - les `rm -rf` de l'hôte passent par `${x:?}`.
- **Coût de la règle de sortie rpm, lu dans `08c/sortie-builds.sh` et non préparé** : l'appliquer demande d'étendre ce script comme pour le deb :
  - étapes `rpm_sec`, `rpm_appliquer`, `rpm_temoins` et `rpm_retirer` ;
  - un invariant qui exige `prefetch-rpm-sortie` seule sur les pods `prefetch-rpm` ;
  - le `NotIn` attendu par `appliquer`, `rejeu` et les contre-épreuves de `deb_sec` ;
  - `builds-sans-internet.yaml`.

  Les invariants `SOUS_REFUS` et `EXCLUS_SANS_SORTIE` refuseraient la politique tant que le `NotIn` ne contient pas `prefetch-rpm`. Tous ces fichiers sont rejoués par S5b : rien n'est modifié avant lui.

**Additif du 12/11/2026, 14:23:42 à 14:23:58 UTC : étape `hote` de S1 lancée (« Oui, lance hote »), 0 KO** ([journal](resultats/s1-hote.log), [comparaison aux prédictions](resultats/s1-predictions.md)).
- P2 et P3 sont tenues : clés de Rocky et d'EPEL conformes aux empreintes publiées, cinq repomd de Rocky signés, vault 9.7 inchangé depuis le 05/11, EPEL sans repomd signé.
- P4 est tenue pour les quatre épinglages, mais fausse sur un détail : le primary d'EPEL est en xz, pas en zstd.
- Cluster et Zot non touchés.

**Additif du 12/11/2026, à partir de 14:26:16 UTC : sortie réseau des pods rpm retenue et son intégration préparée à sec (« Oui, prépare-la »), NON APPLIQUÉE.**
- **Choix** : DNS, adresses publiques en 443 et Zot ([`politiques/prefetch-rpm-sortie.yaml`](politiques/prefetch-rpm-sortie.yaml)).
- **Correctif** : [`s1-sortie-rpm.patch`](s1-sortie-rpm.patch), sur `sortie-builds.sh` et `builds-sans-internet.yaml` de la 08c.
  - Il ajoute `prefetch-rpm` au `NotIn` de `builds-sans-internet`, un invariant, et les étapes `rpm_sec`, `rpm_appliquer`, `rpm_temoins` et `rpm_retirer`.
  - Il intègre la sortie rpm à l'étape `rejeu`, donc au rejeu de zéro.
  - Il adapte la contre-épreuve de `deb_sec`.
- **Vérifié à sec** : `bash -n`, shellcheck sans avertissement, `git apply --check`.
- **Prédictions** R1 à R6 : [`resultats/s1-sortie-predictions.md`](resultats/s1-sortie-predictions.md).
- **Calendrier** : appliqué après S5b, qui rejoue ces fichiers, et chaque étape sur accord nommé.

**Additif du 12/11/2026, 14:34:14 à 14:34:15 UTC : `rpm_sec` et `deb_sec` tenus sur une copie détachée avec le correctif (« Oui, lance-les »), code 0, 0 KO.**
- R1 et R2 sont tenues : les invariants passent avec les cinq politiques, et les deux contre-épreuves de chaque étape signalent exactement ce qui était attendu ([journaux et comparaison](resultats/s1-sortie-predictions.md)).
- Rien n'a été lu ni écrit dans le cluster, et le correctif n'est pas appliqué au dépôt.

**Additif du 12/11/2026, à partir de 14:37:18 UTC : M2 cadré à sec (« Oui, prépare M2 »), NON LANCÉ.**
- M2 n'est pas un script fini. Ses étapes dans le cluster dépendent des mesures de S1, et la syntaxe du mode hermétique de mock n'est pas encore relevée.
- [`m2.sh`](m2.sh) ne contient que l'étape `releve` : sources de mock au tag `mock-6.9-1`, lues sur l'hôte et jamais exécutées. `bash -n` passe, et shellcheck ne relève aucun avertissement.
- Établi sans réseau, depuis le primary d'EPEL vérifié par `hote` :
  - mock 6.9-1 livre `mock-hermetic-repo` et `hermetic-build.cfg` ;
  - il exige systemd-container, createrepo_c et usermode ;
  - podman et skopeo ne sont que recommandés.
- Protocole, embranchements et prédictions M1r à M6r : [`resultats/m2-predictions.md`](resultats/m2-predictions.md).
- Deux points sont à décider :
  - la lecture de D3 (a), car l'hôte n'a ni mock ni dnf ;
  - une éventuelle image de bootstrap « prête », construite par notre chaîne.

**Additif du 12/11/2026, 14:41:49 UTC : relevé de M2 lancé (« Oui, lance releve »), 0 KO** ([journal](resultats/m2-releve.log), [comparaison](resultats/m2-predictions.md)).
- M1r, M2r, M3r, M5r et M6r sont tenues ; M4r l'est en partie.
- Trois contraintes nouvelles :
  - `--hermetic-build` exige `--rebuild` et impose sa propre configuration, sans `-r` ;
  - le verrou doit avoir été calculé avec `bootstrap_image_ready=True` ;
  - `hermetic-build.cfg` met `gpgcheck=0`, donc les signatures des rpm seront à vérifier par nous.
- Le passage des macros d'OBS par le verrou est à vérifier en M2.

**Additif du 12/11/2026, à partir de 14:43:15 UTC : étape `verrou` ajoutée à `s1.sh` (« Oui, ajoute-le »), NON LANCÉE.**
- Elle lance `--calculate-build-dependencies` avec une configuration jumelle en `bootstrap_image_ready = True`, pour mesurer dès S1 si `rockylinux:9.7` brut convient au mode hermétique.
- Le verrou est archivé, et rien n'est poussé.
- Prédictions V1 à V5 : [`resultats/s1-predictions.md`](resultats/s1-predictions.md).

**Additif du 12/11/2026, à partir de 14:52:04 UTC : étape `releve2` ajoutée à `m2.sh` (après « continue »), NON LANCÉE.**
- Hôte seul, sans réseau : elle relit l'archive de mock gardée par `releve`, sha256 contrôlé, et archive des plages entières de lignes.
- Elle tranche les points que `releve` a laissés ouverts : options recopiées dans le verrou (macros d'OBS), champs par paquet, exigences d'une image de bootstrap prête, contrôles de signature de `mock-hermetic-repo` et du mode hermétique.
- Prédictions N1r à N6r : [`resultats/m2-predictions.md`](resultats/m2-predictions.md). Elle attend un accord nommé.

**Résultat de `releve2`, le 12/11/2026 à 14:54:25 UTC (« Oui, lance releve2 »)** : code 0, 0 KO, archive inchangée ([journal](resultats/m2-releve2.log), [résultats](resultats/m2-predictions.md)).
- **N2r tombe** : le verrou recopie `macros` et le mode hermétique les réapplique. Les macros d'OBS passeraient donc. V4 de S1 devrait tomber.
- **Signatures et sommes des rpm** : ni `mock-hermetic-repo` ni le mode hermétique ne les contrôlent. En M2, `rpm -K` et la comparaison des `sigmd5` sont à notre charge.
- **Non prévu, lu et non mesuré** : la référence du bootstrap est coupée au premier « : » (`config.py:844`, `mock-hermetic-repo.py:138`). Notre `sc-stockage.poc.test:5000/…@sha256:…` ferait échouer M2 et M3. Quatre voies sont à décider. `--calculate-build-dependencies`, et donc S1, n'est pas concerné.
- **Non prévu, lu** : une image « prête » est traitée comme non prête si une option de modules ou `chroot_additional_packages` est posée, mais le verrou enregistre quand même `True`. La mesure de V1 peut donc tromper. Un ajout à l'étape `verrou` est proposé, sur accord.

**Correction du 12/11/2026, écrite à partir de 14:57:37 UTC, après relecture du conseiller** ([détail](resultats/m2-predictions.md), [journal](resultats/m2-releve2-complement.log)) :
- les options qui annulent « prête » sont les options `bootstrap_*` (`mock.py:811` à `:819`), pas celles du buildroot ;
- `rocky-9.tpl` (mock-core-configs 45.2, la version épinglée) est dans l'archive et n'en pose aucune, pas plus que `s1.sh`. **La mesure de V1 ne peut donc pas être trompée** : la phrase de l'additif précédent est retirée ;
- l'ajout à l'étape `verrou` reste proposé, comme observation directe ;
- le contrôle réel des rpm est `rpm -K` avec la clé Rocky. Le `sigmd5` n'est qu'un contrôle de cohérence.

**Additif du 12/11/2026, à partir de 15:11:15 UTC : faisabilité de la voie 2 lue, étape `releve3` ajoutée à `m2.sh` (après « continue »), NON LANCÉE.** C'est une lecture, pas un résultat ; aucune voie n'est choisie ([détail](resultats/m2-predictions.md)).
- `mock-hermetic-repo` construit le dépôt avant de copier l'image, puis échouerait sur notre référence : la voie 2 le remplacerait en entier (téléchargement, `rpm -K`, `createrepo_c`, `skopeo copy`).
- `ee90dc0e…` est le manifeste amd64, pas un index : une copie par ce digest n'a pas besoin de `--override-arch`.
- `releve3` lira, sans réseau, comment mock calcule le digest affirmé et charge une image `dir:`. Prédictions R1r à R5r ; elle attend un accord nommé.

**Résultat de `releve3`, le 12/11/2026 à 15:14:59 UTC (« Oui, lance releve3 »)** : code 0, 0 KO, archive inchangée ([journal](resultats/m2-releve3.log), [résultats](resultats/m2-predictions.md)). Lu, non mesuré.
- Le digest que vérifie le mode hermétique est un sha256 des sections `RootFS` et `Config` de `podman image inspect` : une copie fidèle des couches et de la configuration le reproduit, quelle que soit la compression. R2r n'est tenue qu'en partie : la configuration y entre aussi.
- Un écart de ce digest lève `BootstrapError`, et le mode hermétique interdit le repli. Il n'y a pas d'autre coupure de référence d'image que les deux déjà vues.
- Pour la voie 2 : la copie de l'image par `skopeo copy --preserve-digests` reste contrôlée par mock en M3 ; aucune voie n'est choisie.

**Additif du 12/11/2026, à partir de 15:23:35 UTC : sonde de l'étape `verrou` de S1 corrigée à sec, ajout proposé joint (après « continue »), NON LANCÉE** ([détail et prédictions V6 à V9](resultats/s1-predictions.md)).
- **Défaut** : `--debug-config` écrit `config_opts['clé'] = valeur`, et seulement les clés qui diffèrent de leur défaut (`mock.py:605` à `:619`). L'ancien motif de la sonde n'aurait rien trouvé, sans le signaler.
- **Ajout** : les quatre options `bootstrap_*` qui annulent « prête », et les messages de `bootstrap_image_is_ready` relevés dans tout `root.log` après chaque appel de mock.
- Essayé hors cluster avec un faux `mock`. La modification de `s1.sh` attend un accord ; l'étape tournera après S5b.

**Décision du 12/11/2026, notée à 15:42:38 UTC : lecture de D3 (a) tranchée.** Question posée : « Pour D3 (a), on retient la résolution dans un pod Kata lancé à la main ? » ; réponse du propriétaire : « Oui, Kata à la main ».
- D3 (a) se lit « hors Tekton d'abord » : en M2, `--calculate-build-dependencies` tourne dans un pod Kata lancé à la main, comme S1, puis dans Tekton en M4.
- Rien n'est installé sur l'hôte : ni mock ni dnf.
- Le texte de D3 (a) du 10/11 n'est pas réécrit ; cette lecture le précise.
- Restent à décider : la voie pour la référence du bootstrap, et l'image de bootstrap « prête », qui attend la mesure de l'étape `verrou`.
- Rien n'est lancé. M2 s'écrira après S1, elle-même après S5b.

**Décision du 12/11/2026, notée à 15:48:34 UTC : voie 2 retenue pour la référence du bootstrap.** Question posée : « Quelle voie pour la référence du bootstrap ? » ; réponse du propriétaire : « Voie 2 ».
- En M2, nos propres étapes remplacent `mock-hermetic-repo` en entier ([faisabilité lue](resultats/m2-predictions.md)) :
  1. télécharger les rpm du verrou ;
  2. `rpm -K` avec la clé Rocky, puis comparer les `sigmd5` au verrou ;
  3. `createrepo_c --compatibility` ;
  4. `skopeo copy --preserve-digests` de l'image, par le `pull_digest` du verrou, vers le dossier `dir:` qu'attend `config.py:846`.
- mock reste le rpm signé d'EPEL, et rien de ce que S5b rejoue n'est touché.
- Le remplacement d'un outil de mock par nos étapes est un écart à documenter.
- Tout est lu dans le code, rien n'est mesuré. Le chemin exact du dossier dépend du `pull_digest`, que seule l'étape `verrou` de S1 donnera.
- Reste à décider : l'image de bootstrap « prête », qui attend la mesure de l'étape `verrou`. Rien n'est lancé.

**Additif du 12/11/2026, à partir de 15:59:51 UTC : audit de `createrepo_c` et de `rpm` préparé à sec (après « continue », sur relecture du conseiller), NON LANCÉ.**
- **Écart relevé** : la voie 2 nous fait appeler `createrepo_c` et `rpm -K` nous-mêmes, alors que le doc 04 n'a aucun verdict pour `createrepo_c` (recherche du jour, sans résultat), ni pour `rpm`. Jusqu'ici, `createrepo_c` n'était qu'une dépendance de mock. Règle du propriétaire : rien de « Risqué », selon les verdicts du doc 04. C'est donc un préalable de M2, au même titre que podman et skopeo le 05/11.
- **Ajout** : étape `voie2` de [`sante.sh`](sante.sh), avec les mêmes relevés que `releves` :
  - Scorecard, release, commits sur 90 jours comptés à la date du lancement, auteurs, fusionneurs, SECURITY.md et avis de l'année ;
  - les fichiers de `createrepo_c` et `rpm` listés dans `pub/rocky/9.8`, d'où vient l'image d'outillage (D4 a). Cette liste n'est pas signée : elle donne un indice de version, pas un épinglage, qui passera par un primary vérifié en M2. Une liste vide est signalée.
- Lectures réseau seules (API GitHub et Scorecard, `dl.rockylinux.org`) : rien n'est installé, téléchargé pour être exécuté, ni écrit hors de `resultats/` et du cache de la brique. **Accord nommé attendu.**
- **Mise en fonction** : les relevés par dépôt de `releves` passent dans `releve_depot`, sans changement de commande.
- **Vérifié à sec** ([banc](resultats/sante-voie2-essai-local.sh), [journal](resultats/sante-voie2-essai-local.log), `gh`, `curl` et Scorecard simulés, HOME isolé) :
  - la sortie de `releves` est identique avant et après la mise en fonction (71 lignes, en-tête daté exclu) ;
  - `voie2` interroge les bons dépôts avec les bonnes dates de début ;
  - `-devel` et `rpmlint` sont écartés, et une liste vide est signalée.

  Le banc ne couvre pas les réponses réelles des services.
- **shellcheck** (`-S warning`) ne relève aucun avertissement, `bash -n` passe. Une remarque : l'alerte SC2034 d'avant, sur un `local f` inutilisé de `etape_podman`, n'apparaît plus, mais seulement parce que `f` est maintenant lu dans `voie2`. Ce `local` est inchangé.

| # | Prédiction | Confiance |
|---|---|---|
| A1 | `createrepo_c` : non archivé, release et commits sur 90 jours, aucun critère « Risqué » atteint | Moyenne : jamais relevé |
| A2 | `rpm` : non archivé, très actif, plusieurs auteurs, aucun critère « Risqué » | Haute |
| A3 | Le critère des 2 employeurs n'est prouvé ni pour l'un ni pour l'autre (fusions surtout par Red Hat), comme pour podman et skopeo | Moyenne |
| A4 | Dans `pub/rocky/9.8`, `createrepo_c` et `createrepo_c-libs` sont dans AppStream et absents de BaseOS ; `rpm`, `rpm-libs` et `rpm-sign-libs` sont dans BaseOS et absents d'AppStream | Moyenne : de mémoire, jamais relevé ici |

**Corrigé à sec le 12/11/2026 à partir de 16:03:42 UTC, avant tout accord, sur relecture du conseiller.**
- **Défaut** : `curl -sSL` sans `-f` rendait la page d'une erreur HTTP, et l'étape aurait écrit « aucun fichier ». A4 prédit justement des absences : une erreur l'aurait confirmée à tort. Le code HTTP est maintenant relevé, et une erreur donne `KO … liste non lue`, distinct d'une liste lue et vide. Chaque répertoire n'est plus lu qu'une fois.
- **Vérifié** : l'absence de verdict pour `rpm` au doc 04 (recherche de `rpm-software-management/rpm`, d'une ligne `rpm` et de « RPM », et dans `tools/health/projects.tsv`, où seul mock figure). La règle du §1 sur les outils de distro ne porte que sur SECURITY.md, pas sur l'absence de verdict.
- **Banc rejoué** ([journal](resultats/sante-voie2-essai-local.log)) : `releves` reste identique, 71 lignes, comparé à `sante.sh` du parent de ec849eb. Pour `voie2` :
  - les fichiers sont trouvés sur une liste lue, en HTTP 200 ;
  - « aucun fichier » est écrit sur une liste vide, en HTTP 200 ;
  - une 404 donne un KO, et sa page, piégée avec un nom de fichier, n'est pas lue.

  Non simulé : l'échec de curl lui-même (délai, DNS). `bash -n` passe, et shellcheck ne relève aucun avertissement.

**Résultat de `voie2`, le 12/11/2026 de 16:05:42 à 16:05:54 UTC (« Oui, lance voie2 »)** : code 0 ([journal](resultats/sante-voie2.log)). **Aucun verdict « Risqué »** : `createrepo_c` et `rpm` sont « À surveiller », chemin critique (doc 04, §3 et §6). Ils sont ajoutés à `tools/health/projects.tsv` pour le ré-audit du §7.

| # | Résultat |
|---|---|
| A1 | **Tenue.** `createrepo_c` n'est pas archivé. Release 1.2.6 du 27/10/2026, 14 commits sur 90 jours, aucun critère « Risqué ». Manquent : Scorecard (« n/d », non mesurée), SECURITY.md (non bloquant, outil de distro) |
| A2 | **Tenue.** `rpm` n'est pas archivé. 54 commits sur 90 jours, 10 auteurs, release rpm-6.1.0 du 20/08/2026, aucun critère « Risqué ». Non prédit : Scorecard 3,8, sous le seuil de 6 et sous mock (4,9) |
| A3 | **Tenue.** Pour `rpm`, les deux seuls fusionneurs des 100 dernières PR (dmnks 60, pmatilai 40) ont des adresses redhat.com. Pour `createrepo_c`, « surtout Red Hat » n'est pas établi : son premier fusionneur, kontura (49), n'est pas parmi les auteurs des 90 jours, et son employeur n'est pas relevé. Le critère des 2 employeurs n'est donc prouvé pour aucun des deux |
| A4 | **Tenue.** `createrepo_c-0.20.1-4.el9` et `createrepo_c-libs` sont dans AppStream seul, et `rpm`, `rpm-libs` et `rpm-sign-libs` (4.16.1.3-40.el9) dans BaseOS seul. Les quatre listes ont été lues en HTTP 200 |

- **Constat** : les versions employées ne sont pas celles du projet audité. Rocky 9.8 livre `createrepo_c` 0.20.1, contre 1.2.6 en amont, et `rpm` 4.16.1.3, contre 6.1.0. Leur maintenance relève donc de Rocky (errata, dépôts signés), comme pour podman et skopeo.
- **Limites** : les versions viennent d'une liste non signée, et la date de build n'est pas mesurée. Les avis publiés (0) ne couvrent que GitHub. L'épinglage passera par un primary vérifié en M2.
- **Point ouvert pour M2** : l'option `--compatibility` de `createrepo_c`, écrite dans la décision « Voie 2 », vient du code de mock 6.9. Son existence en 0.20.1 n'est pas vérifiée ([note](resultats/m2-predictions.md)).

**Additif du 12/11/2026, à partir de 16:17:36 UTC : étape `releve4` ajoutée à `m2.sh` (après « continue », sur relecture du conseiller), NON LANCÉE** ([détail et prédictions L1 à L4](resultats/m2-predictions.md)).
- Elle lit dans l'amont, aux tags des versions de Rocky 9.8, si `createrepo_c` 0.20.1 accepte `--compatibility` et si `skopeo copy` 1.22.2 accepte `--preserve-digests` (gestes 3 et 4 de la voie 2).
- Hôte seul, réseau, ni cluster ni Zot ; un témoin par fichier distingue une option absente d'un mauvais fichier.
- Banc hors réseau tenu ([journal](resultats/m2-releve4-essai-local.log)). Accord nommé attendu.

**Premier passage de `releve4`, le 12/11/2026 à 16:19:59 UTC (« Oui, lance releve4 »)** : KO attendu sur le témoin de skopeo, code 1 ([journal](resultats/m2-releve4-premier-passage.log), [résultats](resultats/m2-predictions.md)).
- L1 et L2 tenues : `--compatibility` existe dans createrepo_c 0.20.1 (`cmd_parser.c:177`).
- L3 contredite en apparence : l'option agit aussi sur la limite des changelogs (`createrepo_c.c:1291`), malgré son texte d'aide.
- L4 non tranchée : `copy.go` de skopeo ne déclare pas ses options de copie.
- Corrigé à sec à partir de 16:20:56 UTC (lecture de `utils.go`, contexte des usages archivé), banc rejoué ; NON RELANCÉ, accord nommé attendu.

**Note du 12/11/2026, écrite à partir de 16:23:16 UTC (relecture du conseiller)** : « KO attendu » ci-dessus se lit « KO prévu par le garde » ; L4 est non tenue telle qu'écrite ([détail](resultats/m2-predictions.md)). Seconde correction à sec à partir de 16:22:59 UTC : options de skopeo cherchées dans le corps de `sharedCopyFlags` seul ; banc rejoué, six cas. NON RELANCÉE, accord nommé attendu.

**Second passage de `releve4`, le 12/11/2026 à 16:24:13 UTC (« Oui, relance releve4 »)** : code 0 ([journal](resultats/m2-releve4.log), [résultats](resultats/m2-predictions.md)).
- `--compatibility` existe dans createrepo_c 0.20.1, mais elle fixe aussi la limite des changelogs à -1 quand aucune n'est donnée (`createrepo_c.c:1291`) : L3 non tenue. Le sens de -1 n'est pas lu.
- `--preserve-digests` existe dans skopeo 1.22.2 : `sharedCopyFlags`, `utils.go:352`, appelée par `copy.go:47` (L4b tenue).
- Lu dans l'amont aux tags, pas dans les paquets de Rocky : `--help` dans l'image reste la mesure de M2.

**Additif du 12/11/2026, à partir de 16:34:20 UTC : cœur de la voie 2 écrit à sec dans [`m2.sh`](m2.sh), NON BRANCHÉ** (après « continue », sur relecture du conseiller). Aucune étape ne l'appelle ; le pod, l'image et l'étape qui le branche attendent S1, `verrou` et les embranchements 2 et 3.
- Sur l'hôte, `voie2_preparer` met le verrou à plat. Il le refuse sur version, `pull_digest`, `bootstrap_image`, champ manquant, sigmd5, URL hors de vault 9.7 ou avec « .. », nom de fichier ou doublon.
- Dans le pod, `VOIE2` fait les quatre gestes, chacun gardé : HTTP 200, `rpm -K` avec la seule clé de Rocky, en-têtes égaux au verrou, `createrepo_c --compatibility`, puis `skopeo copy --preserve-digests` avec le sha256 du manifeste égal au `pull_digest`.
- Banc hors réseau, outils simulés, script du pod lu par `sh -s` : 18 cas au code attendu ([journal](resultats/m2-voie2-essai-local.log)). Prédictions V1 à V5 pour le premier passage réel ([détail](resultats/m2-predictions.md)).
- Temps passé : 2,38 h mesurées ([relevé](resultats/temps-05-1211.log)), pour 2,5 pw estimées.

**Additif du 12/11/2026, à partir de 16:42:30 UTC : étape `releve5` ajoutée à [`m2.sh`](m2.sh), NON LANCÉE** (après « continue », sur relecture du conseiller). Hôte seul, sans réseau : elle relit l'archive de mock gardée, sha256 contrôlé, et archive au journal `installed_packages.py`, les verrous d'exemple des tests et de la documentation, et les mentions de `gpg-pubkey` et de sigmd5. Elle sert à étayer V1 à V3 avant le premier verrou réel. Prédictions W1 à W4 ([détail](resultats/m2-predictions.md)). Accord nommé attendu.

**Passage de `releve5`, le 12/11/2026 à 16:47:23 UTC (« Oui, lance releve5 »)**, note précisée sur relecture du conseiller : code 0 ([journal](resultats/m2-releve5.log), [résultats](resultats/m2-predictions.md)). W1 à W4 tenues :
- le sigmd5 du verrou est la sortie brute de `rpm -qa --qf "%{sigmd5}"`, en hexadécimal minuscule dans les quatre valeurs d'exemple ; le schéma n'en fixe que le type ;
- les URL viennent de `dnf --installroot=<chroot> repoquery --location`, cherchées par nom, version, release et arch, pas par contenu ;
- mock 6.9 écarte les entrées `gpg-pubkey` du verrou.
- V2 monte à haute pour le code, V3 à moyenne ; V1 reste moyenne. Dans le code lu, la comparaison des en-têtes au verrou, dans le cœur, est le seul lien entre le fichier téléchargé et le paquet installé. Elle lit une étiquette sans la recalculer : que `rpm -K` revérifie le condensat MD5 n'est pas mesuré dans l'image (`rpm -Kv` attend le branchement).

**Additif du 12/11/2026, à partir de 17:20:08 UTC : étape `releve6` ajoutée à [`m2.sh`](m2.sh), NON LANCÉE** (après « continue », sur relecture du conseiller). Hôte seul, sans réseau : elle relit l'archive de mock gardée, sha256 contrôlé. Elle archive `package_manager.py`, `doOutChroot` et `rocky-9.tpl`, puis rejoue sur l'hôte le remplacement des mirrorlist de `s1.sh` et liste les dépôts qui restent actifs. Elle sert à étayer V1 : de quels dépôts `dnf repoquery` tire les URL du verrou. Prédictions X1 à X6 ([détail](resultats/m2-predictions.md)) ; banc hors réseau des pièces neuves ([journal](resultats/m2-releve6-essai-local.log)). Accord nommé attendu. Temps remesuré, même méthode : 2,80 h à HEAD 2f0bc7b ([relevé](resultats/temps-05-1211.log)).
