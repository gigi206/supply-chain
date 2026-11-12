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
