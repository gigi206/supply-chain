# Brique 05, M2 : protocole et prédictions du relevé (écrits le 12/11/2026 à partir de 14:37:18 UTC, avant toute exécution)

Sur « Oui, prépare M2 ». **Rien n'a été lancé, et rien n'a été lu sur le réseau pour M2.** M2 n'est pas un script fini.
- Ses étapes dans le cluster dépendent de ce que S1 mesurera après S5b : l'isolation (P9), le stockage de podman (P8) et mock en root (P12).
- La syntaxe du mode hermétique de mock n'est pas encore relevée. Aucune option n'est écrite de mémoire.

Seule l'étape `releve` de [`m2.sh`](../m2.sh) est écrite. Elle attend un accord.

## Objet de M2 (README)

M2 versionne la configuration de mock, calcule le verrou et vérifie les signatures des rpm. Il pousse ensuite la fermeture dans Zot sous `deps/sample-app/mock-buildroot-lock`, avec le rpm de mock et l'image de bootstrap. Preuves attendues : fermeture restaurable par digest, et déduplication mesurée.

Le rangement suit celui de la 06. Sa fermeture manuelle de S2 est sous `deps/sample-app/deb-buildinfo`, celle de Tekton (S4b) sous `builds/fermetures/sample-app-deb`, la seule que lise la porte. M2 est manuel, donc `deps/` ; M4 passera par `builds/fermetures/sample-app-rpm`.

## Faits déjà établis, sans réseau

Source : le primary d'EPEL vérifié par `s1.sh hote` le 12/11 (`~/.cache/…/travail/s1-05/epel9.primary.xml`).

- **mock 6.9-1.el9 livre** `/usr/bin/mock-hermetic-repo` et `/etc/mock/hermetic-build.cfg`.
- **Il exige** createrepo_c, systemd-container, usermode, python3-pyroute2, pigz et tar, entre autres. Cela confirme la part de P5 sur systemd-container.
- **Il recommande seulement** podman, skopeo, buildah, fuse-overlayfs, dnf-utils et python3-dnf-plugins-core. Avec `install_weak_deps=0`, podman et skopeo ne viennent que parce que S1 les épingle.
- **mock-core-configs 45.2-1.el9 exige** `(python3-libdnf5 or (python3-dnf and python3-hawkey))`, `distribution-gpg-keys` et `system-release`.

## Étape `releve` (hôte seul, sur accord)

Elle lit les sources de mock au tag `mock-6.9-1` (codeload de GitHub), comme `sante.sh` le 05/11. Elle archive au journal les lignes qui fixent la syntaxe et le comportement du mode hermétique :
- options de `mock.py` et de la page de manuel ;
- arguments et commandes de `mock-hermetic-repo` ;
- contenu de `hermetic-build.cfg` ;
- clés du verrou ;
- traitement de `bootstrap_image_ready` ;
- documentation.

Puis elle efface les sources.

| # | Prédiction | Confiance |
|---|---|---|
| M1r | L'archive du tag donne `Version: 6.9` dans `mock.spec` | Haute |
| M2r | `mock.py` déclare `--calculate-build-dependencies` et `--hermetic-build` ; `--hermetic-build` prend un verrou et un dépôt local | Moyenne : les noms viennent du relevé amont du 05/11 (documentation, ligne 9), pas la forme des arguments |
| M3r | `mock-hermetic-repo` prend un verrou et un répertoire de sortie, télécharge les rpm, lance `createrepo_c` et tire l'image de bootstrap par `skopeo sync` vers un répertoire | Moyenne : `skopeo sync … --dest dir` est au journal de l'audit du 05/11 ; le reste est déduit |
| M4r | Le verrou enregistre le digest de l'image de bootstrap (`image_digest`, d'après `buildroot_lock.py` lu le 05/11) et, pour chaque rpm, son NEVRA, son URL et sa somme | Moyenne |
| M5r | Le mode hermétique impose `bootstrap_image_ready = True` et `use_bootstrap_image = True`. Dans ce cas, l'image doit déjà contenir dnf et ses greffons | Moyenne : la documentation l'exigeait le 05/11 ; ce qu'elle doit contenir n'est pas lu |
| M6r | Archive de moins de 2 Mo, étape de moins de 30 s | Faible |

## Embranchements de M2, à trancher après S1 et le relevé

1. **Lieu de la résolution (D3 a).**
   - La décision dit : « résolution sur l'hôte d'abord, comme le prefetch de la 03, puis dans Tekton en M4 ». Or l'hôte n'a ni mock ni dnf, et l'installer sur l'hôte demanderait ton accord.
   - Lecture proposée : « hors Tekton d'abord », c'est-à-dire `--calculate-build-dependencies` dans un pod Kata à la main, comme S1, puis dans Tekton en M4.
   - **Cette lecture s'écarte du texte de D3 (a) : c'est une question au propriétaire.**
2. **Image de bootstrap prête.**
   - S1 tire `rockylinux:9.7` brut et laisse mock y installer dnf (`bootstrap_image_ready = False`).
   - Si M5r se confirme et que l'image brute ne suffit pas, il faudra une image de bootstrap construite par notre chaîne, par digest, avec dnf et ses greffons. Ce serait un jalon et une décision de plus.
   - Si l'image brute suffit, M2 la range telle quelle dans la fermeture.
3. **Isolation, stockage de podman, utilisateur** : repris de S1 (P8, P9, P12). Un échec de S1 sur l'un d'eux arrête M2 avant son écriture.
4. **Sortie réseau** : `prefetch-rpm-sortie` sert à la résolution et au téléchargement par `mock-hermetic-repo`. `--hermetic-build` tournera dans un pod sans ce label, donc sous `builds-sans-internet`. Ce sera le premier pas vers M3, sans réseau.

## Limites

- L'archive de codeload n'est pas signée. Seul son sha256 est journalisé. Le rpm de mock, lui, est signé par EPEL et contrôlé en S1.
- Le relevé lit le code du tag, pas le rpm installé. Un écart entre les deux sera visible en S1, où la sonde affiche les versions.

## Résultat du relevé, le 12/11/2026 à 14:41:49 UTC (chrono.tsv : début et fin dans la même seconde ; accord « Oui, lance releve »)

Journal : [`m2-releve.log`](m2-releve.log). Code 0, 0 KO. Archive du tag : 460 102 octets, sha256 `3c034916…3e4d88`, 887 fichiers lus et jamais exécutés, puis effacés.

| # | Résultat |
|---|---|
| M1r | **Tenue** : `Version: 6.9`. |
| M2r | **Tenue, avec deux contraintes non prévues.**<br>- `--calculate-build-dependencies` existe (`mock.py:120`) ; `--hermetic-build` prend deux arguments, le verrou puis le dépôt (`mock.py:421`).<br>- `--hermetic-build` exige le mode `--rebuild` (`mock.py:442`).<br>- Il refuse tout `-r` autre que le défaut : la configuration est imposée, c'est `hermetic-build.cfg` (`mock.py:436`, `mock.py:700`). |
| M3r | **Tenue.** `mock-hermetic-repo --lockfile … --output-repo …` (`mock-hermetic-repo.py:106`, `:112`) tire l'image de bootstrap par `skopeo sync --src docker --dest dir` (`:135`) et crée le dépôt avec `createrepo_c --compatibility` (`:199`). |
| M4r | **En partie.**<br>- Le verrou est au format `1.1.0` (`buildroot_lock.py:72`, schémas 1.0.0 et 1.1.0 dans `mock/docs`).<br>- Il enregistre le digest de l'image de bootstrap (`:110`, `:111`) et une partie de la configuration (`data["config"]`, `:100`).<br>- Les champs par paquet sont coupés au journal (`name`, `arch`, `license`, `version`, `release`…). On ne sait pas encore lesquelles des options de configuration sont recopiées. |
| M5r | **Tenue.** `--hermetic-build` refuse un verrou qui n'a pas enregistré `bootstrap_image_ready=True` (`config.py:824`). |
| M6r | **Tenue** : 460 Ko, moins d'une seconde. |

## Conséquences pour M2 et M3, sans décision

- **Image de bootstrap prête, obligatoire** (M5r) : `--calculate-build-dependencies` devra tourner avec `bootstrap_image_ready = True`. La configuration de S1 (`False`) ne convient pas à M2.
  - Que `rockylinux:9.7` brut suffise ou non n'est pas lu.
  - Un essai de plus dans S1, avec `True`, le dirait à moindre coût. Ce serait une modification de `s1.sh`, sur accord.
- **Configuration imposée en mode hermétique** : `hermetic-build.cfg` met `gpgcheck=0` sur le dépôt hors ligne. **La vérification des signatures des rpm (M2 du README) devra donc être faite par nous**, avec `rpm -K` sur le dépôt produit par `mock-hermetic-repo`, avant tout build.
- **Macros d'OBS** : `-r` est refusé en mode hermétique. Les macros ne passeront que si le verrou les recopie dans `data["config"]` (`buildroot_lock.py:100`). C'est à vérifier dans un verrou réel en M2. Sinon, il faudra les porter par le spec ou par une autre voie, et la prédiction 1 du README est en jeu.
- `config.py:862` porte le commentaire « With hermetic builds, we always assert that we are reproducing the build ». Sa portée n'est pas lue au-delà de cette ligne.

## Additif du 12/11/2026, à partir de 14:52:04 UTC : étape `releve2` préparée à sec, NON LANCÉE

Après « continue », sur recommandation du conseiller. `releve` a laissé des points ouverts, alors qu'ils pèsent sur deux décisions à venir (lecture de D3, image de bootstrap prête) et sur l'étape `verrou` de S1 (V1 à V5). `releve2` les lit avant S5b plutôt qu'après un passage dans le cluster.

**Ce que fait l'étape** ([`m2.sh`](../m2.sh)) :
- hôte seul, **sans réseau** : elle relit l'archive gardée par `releve`, après contrôle de son sha256 (`3c034916…3e4d88`) ;
- sources extraites dans un dossier neuf, lues, jamais exécutées, puis effacées ;
- plages entières de lignes au journal, et non plus des lignes isolées coupées à 170 caractères :
  - `buildroot_lock.py` en entier (lignes 1 à 140) ;
  - propriétés déclarées et exigées du schéma 1.1.0 (par jq) ;
  - `buildroot.py` lignes 1150 à 1205, et les fonctions `inspect_hermetic_metadata` et `get_oci_digest` de `podman.py` ;
  - `site-defaults.cfg` lignes 740 à 790 et `config.py` lignes 805 à 875 ;
  - `mock-hermetic-repo.py` lignes 1 à 210 ;
  - lignes de la documentation qui citent le bootstrap, les signatures ou les sommes.

Une étape nouvelle : **accord nommé nécessaire avant de la lancer**. Les filtres awk et jq ont été essayés sur des entrées synthétiques ; `bash -n` passe, et shellcheck ne relève aucun avertissement.

| # | Prédiction | Confiance | Si elle tombe |
|---|---|---|---|
| N1r | sha256 identique, étape de moins de 5 s, aucun accès réseau | Haute | Arrêt : archive changée sous `~/.cache` |
| N2r | La liste des options recopiées dans `data["config"]` est une liste fixe du plugin. Elle contient `bootstrap_image` et `bootstrap_image_ready`, mais **pas** `macros` | Moyenne pour la liste fixe, faible pour `macros` | Si `macros` y est, les macros d'OBS passeraient par le verrou : V4 tombe, et la prédiction 1 du README n'est plus en jeu |
| N3r | Chaque rpm du verrou porte au moins son nom, sa version, sa release, son arch et son URL de téléchargement ; une somme ou un `sigmd5` est présent | Faible | Sans somme, l'intégrité des rpm téléchargés ne reposerait que sur leur signature, contrôlée par nous (`rpm -K`) |
| N4r | « Prête » veut dire que mock n'installe rien dans le bootstrap. Le code n'y vérifie pas d'outil : un manque (par exemple le greffon `builddep`) n'apparaît qu'à l'usage | Faible | Si le code exige un outil précis, V2 se précise et l'on saura avant S1 si `rockylinux:9.7` brut peut passer |
| N5r | Le mode hermétique impose le bootstrap du verrou par son digest, le dépôt hors ligne monté en `/hermetic_repo`, et l'architecture du verrou. Il ne vérifie pas lui-même les signatures des rpm | Moyenne pour le montage (lu par `releve`, ligne 855), faible pour le reste | Si les signatures sont vérifiées par mock, notre `rpm -K` devient une seconde ligne, pas la seule |
| N6r | `mock-hermetic-repo` télécharge chaque URL du verrou sans vérifier de signature GPG. Il contrôle au plus une somme, si le verrou en porte une | Faible | Si GPG est vérifié, la chaîne de M2 se raccourcit d'un contrôle |

**Ce que les résultats changeraient, sans décision** :
- **sur V1 et V2** : N4r dirait si `rockylinux:9.7` brut a une chance, ou s'il faut proposer tout de suite une image de bootstrap construite par notre chaîne (décision du propriétaire) ;
- **sur V3 et V4** : N2r et N3r fixeraient la forme du verrou attendu ;
- **sur la configuration de l'étape `essais`** : rien, tant que S1 reste en mode non hermétique.

## Résultat de `releve2`, le 12/11/2026 à 14:54:25 UTC (chrono.tsv : début et fin dans la même seconde ; accord « Oui, lance releve2 »)

Journal : [`m2-releve2.log`](m2-releve2.log), 580 lignes. Code 0, 0 KO. sha256 de l'archive identique (`3c034916…3e4d88`). Sources lues, jamais exécutées, puis effacées. Résultats écrits à partir de 14:55:26 UTC.

| # | Résultat |
|---|---|
| N1r | **Tenue** : sha256 identique, moins d'une seconde. L'étape ne contient aucune commande réseau. |
| N2r | **Tombée sur `macros`.**<br>- La liste est bien fixe (`buildroot_lock.py:82` à `:98`) : `target_arch`, `legal_host_arches`, `dist`, `package_manager`, `bootstrap_image`, `bootstrap_image_ready` et **`macros`** (commentaire de `:95` : garder par exemple `%vendor`).<br>- En mode hermétique, `config.py:830` réapplique au build toute la section `config` du verrou (`update_config_from_dict`).<br>- Les macros d'OBS de notre configuration passeraient donc par le verrou. C'est à vérifier sur un verrou réel. |
| N3r | **Tenue.** Champs par rpm, tous exigés par le schéma 1.1.0 : `name`, `arch`, `license`, `version`, `release`, `epoch`, `sigmd5`, `signature` et `url`. Champs exigés du bootstrap : `image_digest`, `pull_digest`, `architecture` et `id`. |
| N4r | **Tenue.**<br>- Le code ne vérifie aucun outil dans une image « prête » : `buildroot.py:1170` porte un TODO, faute d'heuristique. Le commentaire de `:1179` cite des images ubi8, qui ont `dnf builddep` d'origine.<br>- **Non prévu :** une image marquée prête est quand même traitée comme non prête si l'une de ces options est posée : `module_enable`, `module_install`, `module_setup_commands` ou `chroot_additional_packages` (`:1182` à `:1191`). Le message est alors seulement écrit dans `root.log`.<br>- Le verrou recopie la valeur configurée (`buildroot_lock.py:99`, `:100`), et non l'état effectif. |
| N5r | **Tenue.** Ce que fait le mode hermétique, ligne par ligne de `config.py` :<br>- `:830` : il reprend la configuration du verrou ;<br>- `:837` : il exige `repodata` dans le dépôt hors ligne ;<br>- `:844` à `:847` : il prend le bootstrap dans ce dépôt, sous `dir:` et par `pull_digest` ;<br>- `:855` : il le monte en `/hermetic_repo` ;<br>- `:860` : il installe tout le dépôt (`install *`) ;<br>- `:864` : il impose le digest `image_digest` à l'image (portée de la ligne 862) ;<br>- `:868` : il interdit tout repli sur l'installation de dnf.<br>Il ne vérifie aucune signature. L'architecture vient de `target_arch`, recopiée depuis le verrou. |
| N6r | **Tenue, et plus fort que prévu.** `mock-hermetic-repo` écrit le fichier dès que le code HTTP vaut 200 (`:78` à `:83`). Il ne vérifie ni GPG, ni somme, ni le `sigmd5` ou la `signature` que porte le verrou. |

## Constat non prévu : la référence de l'image de bootstrap est coupée au premier « : »

Ce constat vient de la lecture du code. **Il n'est pas mesuré.**

- `config.py:844` et `mock-hermetic-repo.py:138` font tous deux `bootstrap_image.split(':')[0]`, puis ajoutent `@<pull_digest>`. Le but : retirer un tag.
- La référence de S1, `BOOT`, vaut `sc-stockage.poc.test:5000/amont/rockylinux/rockylinux@sha256:ee90dc0e…`.
- Coupée au premier « : », il en reste `sc-stockage.poc.test`. `skopeo sync` recevrait donc `sc-stockage.poc.test@sha256:…`, sans dépôt.
- Même sans port, une référence par digest (`…/rockylinux@sha256:…`) donnerait `…/rockylinux@sha256@sha256:…`.
- **Conséquence :** tant que notre registre est sur le port 5000, ou que l'image est désignée par son digest, `mock-hermetic-repo` (M2) et `--hermetic-build` (M3) échoueraient. Seule une référence de la forme `hôte/dépôt:tag`, sans port, passe.
- `--calculate-build-dependencies` n'est pas concerné : il tire l'image par podman, avec la référence entière. **L'étape `verrou` de S1 n'est donc pas bloquée** par ce constat.

## Conséquences pour S1, M2 et M3, sans décision

- **V4 de S1 devrait tomber.** Elle prédit que les macros ne sont pas recopiées. La prédiction reste telle qu'elle a été commitée ; le verrou réel tranchera.
- **V1 de S1 : sa mesure peut tromper.**
  - Si `rocky-9.tpl` (paquet mock-core-configs, absent de cette archive) pose l'une des quatre options de N4r, le calcul passera alors que l'image est jugée non prête. Le verrou enregistrera quand même `True`.
  - La sonde ne garde que les 200 dernières lignes de `root.log`, et le message de mock peut tomber avant.
  - Ajouter à l'étape `verrou` la recherche de « Not updating bootstrap chroot » et de « Package management in bootstrap » dans tout `root.log` le dirait. C'est une modification de `s1.sh` : elle attend un accord.
- **Signatures et sommes : entièrement à notre charge en M2.** Ni `mock-hermetic-repo` ni le mode hermétique ne les contrôlent. Il faudra, avant tout build :
  - `rpm -K` avec la clé Rocky `21CB256A…` sur chaque rpm téléchargé ;
  - une comparaison du `sigmd5` de chaque rpm avec celui du verrou.
- **Référence du bootstrap en M2 et M3 : quatre voies, à décider.**
  1. Servir l'image sans port, sous un tag. Cela touche Zot ou le réseau de la 08.
  2. Préparer nous-mêmes le dossier `dir:` attendu par `config.py:846`, avec `skopeo copy` par digest, au lieu de `prepare_image`. Le chemin serait celui que donne la coupure.
  3. Signaler le défaut chez mock. Action publique : ton accord est nécessaire.
  4. Corriger mock localement, ce qui écarte le rpm signé d'EPEL.
  Aucune voie n'est essayée.

## Correction du 12/11/2026, écrite à partir de 14:57:37 UTC, après relecture du conseiller

Deux affirmations du résultat ci-dessus sont fausses ou n'étaient pas vérifiées. Le texte au-dessus n'est pas réécrit.

Lecture complémentaire de l'archive en cache, sans réseau, sha256 inchangé : [`m2-releve2-complement.log`](m2-releve2-complement.log).

**1. Les options qui rendent une image « non prête » portent le préfixe `bootstrap_`.**
- Le commentaire de `buildroot.py:1173` le disait déjà : ces options sont copiées depuis leur forme `bootstrap_`. `mock.py:811` à `:819` retire ce préfixe pour le bootstrap.
- `config.py:347` à `:350` les initialise à vide, pour que le bootstrap n'hérite pas des options du buildroot.
- Ce qui annule « prête » est donc `bootstrap_module_enable`, `bootstrap_module_install`, `bootstrap_module_setup_commands` ou `bootstrap_chroot_additional_packages`. Les options du buildroot de même nom n'y sont pour rien. N4r et sa partie « non prévu » sont corrigées en ce sens.

**2. `rocky-9.tpl` est bien dans l'archive, contrairement à ce qui était écrit.**
- mock-core-configs y est en version 45.2, celle épinglée par S1 (`45.2-1.el9`).
- `rocky-9.tpl` ne pose que `bootstrap_image` (remplacé par notre configuration), et `rocky-9-x86_64.cfg` aucune option du bootstrap.
- `s1.sh` ne pose aucune des quatre options : seulement `use_bootstrap_image`, `bootstrap_image` et `bootstrap_image_ready` (lignes 329 à 331).
- **Donc la mesure de V1 ne peut pas être trompée** par le gabarit ni par notre configuration. La phrase « V1 de S1 : sa mesure peut tromper » est retirée.

**L'ajout proposé à l'étape `verrou` reste utile, comme observation directe et toujours sur accord :**
- chercher « Not updating bootstrap chroot » et « Package management in bootstrap » dans tout `root.log` ;
- élargir le `--debug-config` de la sonde aux quatre options `bootstrap_*`.

**3. Trois précisions.**
- **N5r :** `config.py:855` monte le **dépôt hors ligne** en `/hermetic_repo`, et non le bootstrap.
- **Référence du bootstrap :** `hôte/dépôt`, sans tag et sans port, passe aussi, pas seulement `hôte/dépôt:tag`.
- **`sigmd5` :** c'est un MD5. Le comparer au verrou n'est qu'un contrôle de cohérence. **Le contrôle réel est `rpm -K` avec la clé Rocky `21CB256A…`**, et M2 sera conçu autour de lui.

## Additif du 12/11/2026, à partir de 15:11:15 UTC : faisabilité de la voie 2, lue dans les journaux archivés ; étape `releve3` préparée à sec, NON LANCÉE

Après « continue ». **Ce n'est pas une décision** : la voie reste à choisir par le propriétaire. Tout ce qui suit est lu dans [`m2-releve2.log`](m2-releve2.log) et [`sante-signatures.log`](sante-signatures.log) ; rien n'est mesuré, rien n'est essayé.

**Q1. `mock-hermetic-repo` peut-il servir sans son étape d'image ?** (`mock-hermetic-repo.py:177` à `:202`)
- `_main` télécharge d'abord tous les rpm, lance `createrepo_c`, puis appelle `prepare_image` en dernier, sans condition.
- Avec notre référence, le dépôt serait donc construit, puis l'outil finirait en erreur à l'étape d'image (`check_output`, exception non rattrapée).
- Cette erreur ne se distingue pas d'une autre par le code de sortie. Lancer l'outil en tolérant son échec n'est donc pas une voie sûre.
- Hypothèse, non vérifiée dans le source de skopeo : la référence coupée `sc-stockage.poc.test@sha256:…` n'a pas de `/`, et la règle de normalisation des noms Docker en ferait `docker.io/library/sc-stockage.poc.test`. skopeo tenterait alors de joindre Docker Hub.
- **Conséquence : la voie 2 remplace `mock-hermetic-repo` en entier**, pas seulement son étape d'image. L'outil se réduit à trois gestes, tous lus : télécharger chaque URL du verrou, `createrepo_c --compatibility`, copier l'image. M2 doit de toute façon ajouter `rpm -K` entre le premier et le deuxième.

**Q2. Quel digest le mode hermétique affirme-t-il ?**
- `config.py:864` impose `bootstrap_image_assert_digest` = `image_digest` du verrou.
- `image_digest` vient de `get_oci_digest` (`podman.py:200` à `:214`). Son commentaire parle d'un digest des couches du RootFS, identique pour toute image aux mêmes couches dans le même ordre. Pour une image `dir:`, il est lu sur l'image chargée puis étiquetée (`_tagged_id`).
- Si c'est bien le cas, une copie qui garde les couches le reproduit. Mais le corps de `podman_get_oci_digest` et le chargement d'un dossier `dir:` ne sont pas dans les journaux : c'est l'objet de `releve3`.
- `pull_digest` est autre chose : le `.Digest` de `podman image inspect` (`podman.py:266`), digest du manifeste tiré. Il ne sert qu'à nommer le dossier.

**Q3. `ee90dc0e…` est-il un index ?** Non, d'après ce qui est déjà archivé.
- `sante-signatures.log` (05/11) : l'index de `rockylinux:9.7` est `53f4c6dc…`, et `ee90dc0e…` est son manifeste amd64.
- `s1.sh:218` et `:220` copient ce manifeste dans Zot par ce digest, et le vérifient.
- Une copie par `ee90dc0e…` ne passe donc par aucun index : `--override-arch` est sans objet. `--preserve-digests` reste à mettre, comme le fait `prepare_image`.
- Que le `pull_digest` du verrou vaille `ee90dc0e…` est une prédiction. L'étape `verrou` de S1 la tranchera.

**Q4. Quel dossier `config.py:846` attend-il ?**
- `<dépôt hors ligne>/sc-stockage.poc.test@sha256:<pull_digest>`, passé en `dir:`.
- `pull_digest` n'existe qu'une fois le verrou calculé par l'étape `verrou` de S1.

**Ce que la voie 2 demanderait** (rien n'est écrit) :
1. télécharger les rpm du verrou ;
2. `rpm -K` avec la clé Rocky, puis comparer les `sigmd5` au verrou ;
3. `createrepo_c --compatibility` ;
4. `skopeo copy --preserve-digests` de la référence entière vers le dossier de Q4.

Rien que S5b rejoue n'est touché, et mock reste le rpm signé d'EPEL. Le prix : un outil de mock remplacé par nos propres étapes, écart à documenter.

### Étape `releve3` ([`m2.sh`](../m2.sh)), accord nommé nécessaire avant de la lancer

- Hôte seul, sans réseau : même archive, sha256 contrôlé. Elle archive :
  - `podman.py` entier, avec son nombre de lignes ;
  - les usages de `bootstrap_image_assert_digest`, de `dir:` et `oci-archive`, de `bootstrap_image_fallback` et `bootstrap_image_skip_pull` ;
  - toutes les coupures `split(':')` et `split(":")` du code Python ;
  - tous les usages de `hermetic_build` et `offline_local_repository`.
- Puis elle efface les sources.
- Les filtres ont été essayés sur une entrée synthétique. `bash -n` passe, et shellcheck ne relève aucun avertissement (seulement les notes de niveau info déjà présentes).

| # | Prédiction | Confiance | Si elle tombe |
|---|---|---|---|
| R1r | sha256 identique, étape de moins de 5 s, aucune commande réseau | Haute | Arrêt : archive changée sous `~/.cache` |
| R2r | `podman_get_oci_digest` tire un sha256 des couches du RootFS : une copie qui garde les couches reproduit `image_digest` | Moyenne | Si le digest dépend du manifeste, la copie doit être exacte : `--preserve-digests` devient indispensable, et à vérifier par mesure |
| R3r | Une image `dir:` est chargée sans réseau, puis étiquetée | Moyenne | Si un accès réseau reste possible, la voie 2 doit le couper |
| R4r | `bootstrap_image_assert_digest` n'est comparé qu'à un seul endroit, et un écart arrête le build | Haute | Si l'écart est seulement journalisé, le contrôle du digest passe à notre charge |
| R5r | Aucune autre coupure `split(':')` d'une référence d'image que les deux déjà vues | Moyenne | Toute autre coupure sur le chemin de M3 s'ajoute aux obstacles de la voie 2 |
