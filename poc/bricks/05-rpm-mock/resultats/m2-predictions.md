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

### Correction du 12/11/2026, écrite à partir de 15:14:22 UTC, après relecture du conseiller, avant tout accord

Le texte au-dessus n'est pas réécrit.

- **Q2 :** `pull_digest` ne sert pas qu'à nommer le dossier. `mock-hermetic-repo.py:141` et `:142` l'ajoutent aussi à la référence tirée : il choisit le manifeste copié. Pour la voie 2, la copie se ferait donc par le `pull_digest` du verrou, et s'arrêterait s'il diffère de `BOOT_DIGEST` (`s1.sh:46`).
- **Q4 :** `config.py:845` ajoute `"@" + pull_digest`. Le dossier attendu s'écrit donc `<dépôt hors ligne>/sc-stockage.poc.test@<pull_digest>`. Que `pull_digest` porte le préfixe `sha256:` sera lu dans le verrou réel.
- **`releve3` corrigée à sec** (même heure, en-tête daté dans `m2.sh`) : `mock.py:811` à `:819` retire le préfixe `bootstrap_` des options du bootstrap. Le code qui compare le digest ou décide du repli peut donc lire `image_assert_digest`, `image_fallback` et `image_skip_pull`. L'étape cherche maintenant ces formes sans préfixe, qui couvrent aussi les formes préfixées. Elle garde 6 lignes de contexte après chaque `image_assert_digest`, pour R4r. `bash -n` et shellcheck passent ; les filtres ont été réessayés sur une entrée synthétique sans préfixe.

## Résultat de `releve3`, le 12/11/2026 à 15:14:59 UTC (chrono.tsv : début et fin dans la même seconde ; accord « Oui, lance releve3 »)

Code 0, 0 KO, [journal](m2-releve3.log) de 371 lignes. Résultat écrit à partir de 15:15:26 UTC. **Tout est lu dans le code, rien n'est mesuré.**

| # | Verdict |
|---|---|
| R1r | **Tenue** : sha256 identique, moins d'une seconde. L'étape ne contient aucune commande réseau. |
| R2r | **Tenue en partie.** `podman_get_oci_digest` (`podman.py:21` à `:59`) prend la sortie de `podman image inspect`, n'en garde que les sections `RootFS` et `Config`, les sérialise en JSON à clés triées et en tire un sha256. Ce n'est donc pas « les couches seules », comme le dit son commentaire : la configuration de l'image (variables, commande, étiquettes…) y entre aussi. Une copie qui garde les couches non compressées et le blob de configuration reproduit `image_digest` ; la compression ou le manifeste n'y entrent pas. |
| R3r | **Tenue, pour ce qui dépend de mock.** Une image `dir:` est chargée par le même `podman pull` que les autres (`podman.py:116` à `:144`), puis étiquetée `mock-bootstrap-<uuid>` (`:146` à `:161`) ; le digest est lu sur cette étiquette (`:207` à `:210`). Que le transport `dir:` de podman n'ouvre aucune connexion relève de podman, pas de mock : non lu ici. |
| R4r | **Tenue.** `image_assert_digest` n'est comparé qu'à un seul endroit, `buildroot.py:289` à `:295`, et un écart lève `BootstrapError`. Le mode hermétique pose `bootstrap_image_fallback = False` (`config.py:868`), alors que la valeur par défaut est `True` (`config.py:110`). Le traitement de l'exception autour de `buildroot.py:268` n'est lu qu'à la ligne près : que l'erreur arrête bien le build sans repli reste à voir en M3. |
| R5r | **Tenue, d'après les lignes seules.** Les trois autres `split(':')` du code Python (`util.py:1167`, `buildroot.py:660`, `config.py:586`) semblent porter, d'après leurs noms de variables, sur des lignes de fichier ou sur l'option `--plugin-option`, pas sur une référence d'image. Les deux coupures de référence restent `config.py:844` et `mock-hermetic-repo.py:138`. |

**Conséquences pour la voie 2, sans décision** :
- La copie de l'image doit garder à l'identique le blob de configuration et les couches. `skopeo copy --preserve-digests` par le `pull_digest` du verrou le fait par construction ; la mesure le confirmera, puisque mock arrête le build si le digest diffère.
- Le contrôle du digest de l'image reste donc fait par mock en M3. Celui des rpm reste à notre charge (`rpm -K`).
- Le calcul passe par la sortie JSON de `podman image inspect`. Le verrou et le build devraient donc tourner avec le même podman, ce que donnerait l'image de S1 si M3 la réutilise.

**Non prévu, lu** :
- `pull_image` ajoute `--platform` si `oci_platform_map` connaît l'architecture visée (`podman.py:121` à `:125`). Avec un manifeste amd64 unique comme `ee90dc0e…`, sans effet attendu.
- `podman_check_native_image_architecture` (`podman.py:62` à `:91`) compare l'architecture de l'image à celle de l'hôte.

## Décision du 12/11/2026, notée à 15:42:38 UTC : embranchement 1 tranché

Question posée : « Pour D3 (a), on retient la résolution dans un pod Kata lancé à la main ? » ; réponse du propriétaire : « Oui, Kata à la main ».
- La lecture proposée à l'embranchement 1 est retenue : la résolution de M2 tourne dans un pod Kata lancé à la main, comme S1, puis dans Tekton en M4. Rien n'est installé sur l'hôte.
- L'embranchement 4 s'applique tel quel : ce pod porte le label `prefetch-rpm-sortie`.
- Les embranchements 2 (image prête) et 3 (reprise de S1) restent ouverts, de même que le choix de la voie pour la référence du bootstrap.

## Décision du 12/11/2026, notée à 15:48:34 UTC : voie 2 retenue

Question posée : « Quelle voie pour la référence du bootstrap ? » ; réponse du propriétaire : « Voie 2 ».
- M2 suivra les quatre gestes de « Ce que la voie 2 demanderait », plus haut, à la place de `mock-hermetic-repo`. La copie de l'image se fera par le `pull_digest` du verrou, et s'arrêtera s'il diffère de `BOOT_DIGEST` (Q2 de la correction de `releve3`).
- Les voies 1, 3 et 4 ne sont pas essayées.
- Rien n'est mesuré : la tenue de la voie se verra en M3, où mock compare le digest de l'image (R4r).
- L'embranchement 2 (image prête) reste ouvert.

**Note du 12/11/2026, écrite à partir de 16:07:55 UTC, après l'audit `voie2` de `sante.sh`** : l'image d'outillage sur Rocky 9.8 porterait `createrepo_c-0.20.1-4.el9` (liste non signée de `pub/rocky/9.8/AppStream`), et non la 1.2.6 de l'amont. Le geste 3 de la voie 2, `createrepo_c --compatibility`, reprend l'appel lu dans le code de mock 6.9. Que la 0.20.1 accepte cette option **n'est pas vérifié**. À contrôler en M2, par `createrepo_c --help` dans l'image, avant le premier dépôt construit. Rien n'est lancé.

## Additif du 12/11/2026, à partir de 16:17:36 UTC : étape `releve4` préparée à sec (après « continue », sur relecture du conseiller), NON LANCÉE

Objet : vérifier dans l'amont, avant M2, les options des gestes 3 et 4 de la voie 2, aux versions que porterait l'image d'outillage :
- `createrepo_c --compatibility`, en 0.20.1 (`createrepo_c-0.20.1-4.el9`, [sante-voie2.log](sante-voie2.log)) ;
- `skopeo copy --preserve-digests`, en 1.22.2 (`skopeo-1.22.2-9.el9_8`, épinglé par `s1.sh`, [s1-hote.log](s1-hote.log)).

L'étape ([`m2.sh`](../m2.sh) `releve4`) tourne sur l'hôte seul, avec réseau, sans cluster ni Zot. Elle lit trois fichiers sur raw.githubusercontent.com, aux tags `0.20.1` et `v1.22.2` : `src/cmd_parser.c` et `src/createrepo_c.c` de createrepo_c, `cmd/skopeo/copy.go` de skopeo.
- Fichiers non signés ; taille et sha256 journalisés ; tout code HTTP autre que 200 donne un KO.
- Une option témoin, sûrement présente, doit être trouvée dans le même fichier (`"checksum"` pour createrepo_c, `"remove-signatures"` pour skopeo). Sinon, le fichier lu n'est pas celui où les options sont déclarées : KO, au lieu d'une fausse absence.
- Une option introuvable, témoin présent, est un résultat (`ABSENTE`), avec le code 0.
- Fichiers effacés à la fin.

| # | Prédiction | Confiance |
|---|---|---|
| L1 | Les trois fichiers sont lus en HTTP 200 : les tags `0.20.1` et `v1.22.2` existent sous ces noms | Moyenne : tag sans préfixe pour createrepo_c, comme `1.2.6` ([sante-voie2.log](sante-voie2.log)) ; préfixe `v` pour skopeo, d'après la convention du projet, non vérifiée |
| L2 | `--compatibility` est PRÉSENTE dans `cmd_parser.c` de createrepo_c 0.20.1, témoin trouvé | Moyenne : mock 6.9, construit par EPEL 9 pour el9, l'appelle (`mock-hermetic-repo.py:199`) ; jamais lu dans createrepo_c |
| L3 | Son texte d'aide la limite à la conservation des anciennes métadonnées, sans effet sur un dépôt créé de zéro | Faible : souvenir, jamais lu |
| L4 | `--preserve-digests` est PRÉSENTE dans `copy.go` de skopeo 1.22.2, témoin trouvé | Moyenne : `prepare_image` de mock l'emploie ; mais les options de copie ont pu être déplacées dans un autre fichier, et le témoin manquerait alors aussi (KO, autre fichier à lire) |

Banc hors réseau ([script](m2-releve4-essai-local.sh), [journal](m2-releve4-essai-local.log)), curl simulé :
- options trouvées : code 0, `PRÉSENTE` deux fois ;
- option absente, témoin présent : code 0, `ABSENTE` ;
- HTTP 404 sur `copy.go` : KO, fichier non lu, code 1 ;
- témoin absent : KO, code 1.

`bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement (`-S warning`).

**Limites.** Les tags amont ne sont pas les paquets de Rocky : les correctifs de `createrepo_c-0.20.1-4.el9` et de `skopeo-1.22.2-9.el9_8` ne sont pas lus. `createrepo_c --help` et `skopeo copy --help` dans l'image restent la mesure de M2. Le fichier de raw.githubusercontent.com n'est pas signé ; seul son sha256 est journalisé.

## Premier passage de `releve4`, le 12/11/2026 à 16:19:59 UTC (« Oui, lance releve4 »), arrêté en KO, code 1

[Journal archivé](m2-releve4-premier-passage.log). `chrono.tsv` porte le début (16:19:59 UTC) et pas de fin : l'étape s'est arrêtée sur le témoin de skopeo. Note écrite à partir de 16:21:19 UTC.

| # | Résultat |
|---|---|
| L1 | **Tenue.** Les trois fichiers sont lus en HTTP 200 aux tags `0.20.1` et `v1.22.2` |
| L2 | **Tenue.** `--compatibility` est déclarée dans `cmd_parser.c:177` de createrepo_c 0.20.1, témoin `"checksum"` trouvé. Texte d'aide : « Affects only: --retain-old-md » |
| L3 | **Non tranchée, contredite en apparence.** Le journal montre `createrepo_c.c:1291` : `if (cmd_options->compatibility && cmd_options->changelog_limit == DEFAULT_CHANGELOG_LIMIT )`. L'option agit donc aussi sur la limite des changelogs, malgré son texte d'aide ; la ligne qui suit n'est pas au journal |
| L4 | **Non tranchée.** Le témoin `"remove-signatures"` manque dans `copy.go` : KO, comme prévu par le risque de L4. Le garde a joué son rôle : pas de fausse absence |

**Lu après le KO, non archivé.** Les trois fichiers sont restés sous `~/.cache/supply-chain-poc/05/m2/releve4`, avec les sha256 du journal. On y lit :
- `copy.go:47` appelle `sharedCopyFlags()` : les options de copie sont déclarées ailleurs ;
- `createrepo_c.c:1292` donne `user_data.changelog_limit = -1` dans ce cas ; le sens de -1 n'est pas lu.

Le passage corrigé archivera ces lignes.

**Correction à sec, à partir de 16:20:56 UTC, NON RELANCÉE** ([`m2.sh`](../m2.sh)) :
- `copy.go` doit appeler `sharedCopyFlags()`, sinon KO ;
- `cmd/skopeo/utils.go` est lu, doit définir `func sharedCopyFlags(`, et porte les deux options (témoin et `preserve-digests`) ;
- les usages de `compatibility` sont archivés avec 3 lignes avant et 5 après.

Banc rejoué ([journal](m2-releve4-essai-local.log)), cinq cas, codes attendus : trouvées (0), absente (0), HTTP 404 sur `utils.go` (1), témoin absent de `utils.go` (1), `copy.go` sans appel à `sharedCopyFlags()` (1). `bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement (`-S warning`).

| # | Prédiction pour le passage corrigé | Confiance |
|---|---|---|
| L4b | `utils.go` de skopeo 1.22.2 définit `sharedCopyFlags` et déclare `--preserve-digests` et `--remove-signatures` | Moyenne : le nom de fichier est supposé, jamais lu |
| L3b | Le contexte archivé montre que `--compatibility` fixe la limite des changelogs à -1 quand l'utilisateur n'en donne pas : le dépôt construit n'est pas le même qu'avec la valeur par défaut | Haute pour la ligne (lue dans le fichier resté) ; le sens de -1 restera à lire |

**Note du 12/11/2026, écrite à partir de 16:23:16 UTC, sur relecture du conseiller (le texte ci-dessus n'est pas réécrit) :**
- **L4 est non tenue telle qu'écrite** : elle prédisait l'option et le témoin dans `copy.go`, et le témoin y manque. Seule l'existence de `--preserve-digests` dans skopeo 1.22.2 reste non tranchée.
- **« KO attendu »**, dans le README, `docs/03` et le message du commit 75bb8d2, se lit « KO prévu par le garde » : le déplacement des options était le risque noté de L4, pas sa prédiction.
- **Seconde correction à sec, à partir de 16:22:59 UTC, NON RELANCÉE** : l'option et le témoin sont cherchés dans le corps de `sharedCopyFlags` seul, archivé au journal, et non plus dans tout `utils.go`. Sinon, une option déclarée par une autre fonction du même fichier aurait été comptée. Banc rejoué ([journal](m2-releve4-essai-local.log)) : cas 1 à 5 aux mêmes codes ; cas 6, option hors de la fonction, `ABSENTE` avec le code 0. `bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement (`-S warning`).
- `utils.go` reste un nom supposé : un second KO est possible.
- Aucune conclusion pour M2 n'est tirée de `createrepo_c.c:1291` avant que son contexte soit archivé.

## Second passage de `releve4`, le 12/11/2026 à 16:24:13 UTC (« Oui, relance releve4 »), code 0

[Journal](m2-releve4.log). `chrono.tsv` porte le début et la fin dans la même seconde. Note écrite à partir de 16:24:37 UTC. Les sha256 de `cmd_parser.c`, `createrepo_c.c` et `copy.go` sont ceux du premier passage.

| # | Résultat |
|---|---|
| L1 | **Tenue.** Quatre fichiers lus en HTTP 200, `utils.go` compris |
| L2 | **Tenue.** `--compatibility` est déclarée dans `cmd_parser.c:177` de createrepo_c 0.20.1 |
| L3 | **Non tenue.** `createrepo_c.c:1291` à `:1295` : avec `--compatibility` et sans `--changelog-limit` donné (valeur par défaut), `changelog_limit` passe à -1. L'option change donc le dépôt construit de zéro, malgré son texte d'aide (« Affects only: --retain-old-md »). Son autre usage, `:2087`, choisit la rétention des anciennes métadonnées (`CR_RETENTION_COMPATIBILITY`) |
| L3b | **Tenue pour la ligne.** Le sens de -1 (sans limite, ou autre) n'est pas lu |
| L4 | Non tenue telle qu'écrite (voir la note précédente) |
| L4b | **Tenue.** `copy.go:47` appelle `sharedCopyFlags()`, et `utils.go:352`, dans le corps de `sharedCopyFlags` (lignes 342 à 354), déclare `--preserve-digests` : « Preserve digests of images and lists ». Le témoin `--remove-signatures` est à la ligne 345 |

**Conséquences pour M2, sans décision :**
- Les gestes 3 et 4 de la voie 2 sont possibles avec les versions de l'amont aux tags `0.20.1` et `v1.22.2`. Les paquets de Rocky ne sont pas lus : `--help` dans l'image reste la mesure.
- `--compatibility` reprend l'appel de mock 6.9, et change la limite des changelogs du dépôt. L'effet sur la construction n'est pas mesuré : le dépôt est relu par mock en M3, qui dira si les métadonnées comptent. Garder l'option rend le dépôt identique à celui que construirait `mock-hermetic-repo`.

**Précision du 12/11/2026, écrite à partir de 16:24:50 UTC (le texte ci-dessus n'est pas réécrit)** : « rend le dépôt identique à celui que construirait `mock-hermetic-repo` » va trop loin. Ce qui est établi, c'est le même appel : `subprocess.check_call(["createrepo_c", "--compatibility", options.output_repo])` ([m2-releve2.log](m2-releve2.log), ligne 199 de `mock-hermetic-repo.py`). L'identité des dépôts n'est pas mesurée (horodatages, ordre des fichiers).

## Additif du 12/11/2026, à partir de 16:34:20 UTC : cœur de la voie 2 écrit à sec dans `m2.sh`, NON BRANCHÉ

Après « continue », sur relecture du conseiller. **Ce n'est pas une étape** : aucune fonction `etape_` ne l'appelle, rien n'est lançable, aucun accord n'est demandé.

**Pourquoi maintenant.** L'en-tête de `m2.sh` renvoie les étapes de M2 dans le cluster après S1, parce qu'elles dépendent de l'isolation, du stockage de podman et de mock en root. Les quatre gestes de la voie 2 n'en dépendent pas : ils sont écrits seuls. Le pod, l'image, le label, la clé livrée et l'étape qui les branche attendent S1, `verrou` et les embranchements 2 et 3. Les aides de pod de `s1.sh` ne sont ni copiées ni chargées.

**Ce qui est écrit** ([`m2.sh`](../m2.sh), après `releve4`) :
- `voie2_preparer`, sur l'hôte : le verrou est mis à plat par `jq` en `liste.tsv` (nom, version, release, arch, sigmd5, URL ; champs du schéma 1.1.0, [m2-releve2.log](m2-releve2.log), N3r). Il s'arrête en KO sur :
  - une version de verrou autre que `1.1.0` ;
  - un `pull_digest` différent de `BOOT_DIGEST`, ou un `bootstrap_image` différent de la référence de S1 (`BOOT_DIGEST`, `VAULT97` et `DEPOT_AMONT` sont lus dans `s1.sh`, pas recopiés) ;
  - un champ manquant, un sigmd5 hors de 32 caractères hexadécimaux, une URL hors des baseurl fixes de vault 9.7 (BaseOS, AppStream, CRB), une URL avec un caractère hors de `[A-Za-z0-9:/._+-]` ou un segment « . » ou « .. » (curl les résout, ce qui sortirait du préfixe), un nom de fichier hors de `[A-Za-z0-9._+-]`, un doublon, un verrou vide.
- `VOIE2`, le script du pod (sh) :
  - vérifie que les outils sont présents ;
  - télécharge chaque URL, HTTP 200 exigé, avec « + » encodé comme `mock-hermetic-repo.py:58` ;
  - exige autant de fichiers que de paquets ;
  - lance `rpm -K` dans une rpmdb vide où seule la clé de Rocky livrée est importée, et exige « digests signatures OK » pour chaque fichier : même motif que l'étape `racine` de `s1.sh`, qui le compte sans s'arrêter ;
  - exige que nom, version, release, arch et `%{SIGMD5}` de chaque en-tête égalent le verrou ;
  - lance `createrepo_c --compatibility`, l'appel de `mock-hermetic-repo.py:199` ;
  - lance `skopeo copy --preserve-digests` vers `dir:<dépôt>/<référence coupée au premier « : »>@<pull_digest>` (Q4), et exige que le sha256 du manifeste copié égale le `pull_digest`.

**Banc hors réseau** ([script](m2-voie2-essai-local.sh), [journal](m2-voie2-essai-local.log), 16:39:28 UTC) : curl, rpm, createrepo_c et skopeo simulés, `s1.sh` copié avec un `BOOT_DIGEST` d'essai, script du pod lu sur l'entrée standard (`sh -s`), comme le fera `kubectl exec`. Les 18 cas rendent le code attendu :
- côté hôte : le nominal passe (code 0) ; version, `pull_digest`, `bootstrap_image`, champ manquant, sigmd5 mal formé, URL d'EPEL, nom `x;id.rpm`, remontée par « .. » sous le préfixe, doublon et verrou vide sont refusés (code 1) ;
- côté pod : le nominal passe (code 0, une URL avec « %2B », appel de skopeo conforme) ; HTTP 404, fichier manquant, signature non OK, en-tête différent, createrepo_c en échec et manifeste différent sont refusés (code 1).

**Ce que le banc ne prouve pas** : les sorties réelles de `rpm -K`, `rpm -qp`, `createrepo_c` et `skopeo` dans l'image ; le format réel de sigmd5 dans un verrou de mock ; le réseau, Zot et la sortie du pod ; l'absence d'un outil. Le script du pod a tourné sous dash sur l'hôte (`/bin/sh`), alors que le pod aura le `sh` de Rocky, non relevé dans l'image. `bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement (`-S warning`) sur `m2.sh` ni sur le banc.

*Note du 12/11/2026, à partir de 18:01:55 UTC (après « continue », sur relecture du conseiller)* : l'absence d'un outil est couverte depuis. Trois cas pod (`sans_rpm`, `sans_createrepo_c`, `sans_skopeo`) retirent le faux outil le temps du cas ; l'hôte n'a aucun des trois, avec ou sans mise. Le banc relancé à 18:02:13 UTC rend 21 cas, dont ces trois refusés (code 1, « KO <outil> absent de l image ») ; les 18 autres donnent la même sortie qu'à 16:39:28 UTC (seule la ligne d'en-tête du journal change). Le paragraphe ci-dessus n'est pas réécrit.

**Prédictions pour le premier passage réel**, après S1 et `verrou` :

| # | Prédiction | Confiance | Si elle tombe |
|---|---|---|---|
| V1 | Toutes les URL du verrou sont sous les baseurl fixes de vault 9.7 | Moyenne : `MOCK_CFG` les fixe ; `query_packages_location`, qui les produit, n'est pas lu | `voie2_preparer` s'arrête ; décision avec toi |
| V2 | Le verrou n'a aucune entrée `gpg-pubkey` | Faible : `query_packages` n'est pas lu | Sans URL, elles arrêtent `voie2_preparer` (« champ manquant ») ; les écarter demandera une décision |
| V3 | Le sigmd5 du verrou fait 32 caractères hexadécimaux minuscules, égaux à `%{SIGMD5}` de `rpm -qp` | Faible : la requête de mock (`installed_packages.py`) n'est pas lue | KO, pas de faux OK ; la comparaison sera à reprendre |
| V4 | `rpm -K` rend « digests signatures OK » pour chaque rpm, avec la seule clé de Rocky | Moyenne : les dépôts de `MOCK_CFG` sont ceux de Rocky 9.7 seuls | KO ; la clé ou le dépôt fautif est à identifier |
| V5 | Le manifeste copié a pour sha256 le `pull_digest` | Moyenne : copie par digest avec `--preserve-digests` ; jamais mesuré | KO avant M3 |

**Ce qui attend toujours** : `createrepo_c --help` et `skopeo copy --help` dans l'image, et la mesure de L3 (dépôt construit avec et sans `--compatibility`, nombre d'entrées de changelog comparé). Ils viennent avec l'étape qui branchera ce cœur, prédictions écrites avant.

**Écart à noter pour le branchement** : `mock-hermetic-repo` reprend 5 fois un téléchargement en échec (`request_with_retry`, `:29` à `:46`). Notre cœur ne reprend pas : une erreur passagère arrête l'étape, et la relancer demande un nouvel accord.

**Règle des 2×** : 2,38 h mesurées sur 32 commits ([temps-05-1211.log](temps-05-1211.log), écarts d'au plus 1 h entre commits, méthode de la 08c, mêmes limites), pour une estimation de 2,5 pw. La règle n'est pas atteinte.

## Additif du 12/11/2026, à partir de 16:42:30 UTC : étape `releve5` ajoutée à `m2.sh`, NON LANCÉE

Après « continue », sur relecture du conseiller. **Hôte seul, sans réseau, lecture seule** : l'étape relit l'archive du tag `mock-6.9-1` gardée par `releve`, après contrôle de son sha256, comme `releve2` et `releve3`.

**Pourquoi.** V1 à V3 reposent sur du code de mock jamais lu : le calcul des URL (`query_packages_location`), la requête des champs dont sigmd5 (`query_packages`), et le sort des entrées `gpg-pubkey`. `query_packages` et `query_packages_location` viennent de `mockbuild/installed_packages.py` (`buildroot_lock.py:11`, [m2-releve2.log](m2-releve2.log)). Les lire avant le premier verrou réel dira si le cœur de la voie 2 attend le bon format, sans rien lancer dans le cluster.

**Ce qui est archivé au journal** : `installed_packages.py` entier ; `mock/tests/test_buildroot_lock.py` entier, pour ses verrous d'exemple ; `docs/Plugin-BuildrootLock.md` entier ; les définitions de `sigmd5`, `url` et `signature` dans le schéma 1.1.0 ; toutes les lignes qui citent `gpg-pubkey`, `pubkey`, `SIGMD5` ou `sigmd5` dans `mock/py`, `mock/tests`, `docs` et `mock/docs`. Les sources sont ensuite effacées. Les noms de ces fichiers ont été pris dans la liste de l'archive (`tar -t`), sans en lire le contenu.

`bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement (`-S warning`). L'étape n'a pas de banc : elle ne fait que lire, avec le même contrôle d'archive que `releve2` et `releve3`. Accord nommé attendu.

| # | Prédiction | Confiance | Ce qu'elle change |
|---|---|---|---|
| W1 | `query_packages` lit les champs par `rpm -qa --qf`, avec un format construit à partir des noms de champs (`%{SIGMD5}` pour sigmd5) : le sigmd5 du verrou est la sortie brute de rpm | Moyenne : les noms de champs de `buildroot_lock.py:51` sont ceux des étiquettes de rpm | Tenue : V3 monte à moyenne, et la comparaison du cœur à `%{SIGMD5}` est la bonne |
| W2 | `query_packages_location` calcule les URL par une requête de dnf (`repoquery --location` ou équivalent), donc depuis les baseurl des dépôts configurés | Moyenne : le paramètre `dnf_cmd` (`buildroot_lock.py:63`) | Tenue : V1 tient à `MOCK_CFG` seul. Sinon, la provenance des URL est à relire |
| W3 | Les entrées `gpg-pubkey` sont écartées explicitement dans `installed_packages.py` | Faible : le plugin, archivé en entier par `releve2` (118 lignes), ne les cite pas, et aucun journal de M2 ne cite `pubkey` ; `installed_packages.py` n'est pas lu | Tenue : V2 monte. Non tenue : le verrou pourra en porter, sans URL, et `voie2_preparer` s'arrêtera (« champ manquant ») ; décision avec toi |
| W4 | Un verrou d'exemple (test ou documentation) porte un sigmd5 de 32 caractères hexadécimaux minuscules | Faible : `releve2` n'a archivé que les chemins des propriétés du schéma, pas leur format (`m2-releve2.log`, lignes 124 à 146) | Indice seulement : un exemple n'est pas un verrou de Rocky 9.7 |

**Ce que `releve5` ne tranchera pas** :
- le contenu d'un verrou réel. V1 à V5 restent à mesurer au premier passage, après S1 et `verrou` ;
- une ligne longue : `plage` coupe à 220 caractères et `lignes` à 170 (aides partagées avec `releve2` et `releve3`, non modifiées). Un verrou d'exemple écrit sur une seule ligne pourrait perdre son sigmd5 ou son URL au-delà de la coupe, et W4 resterait alors non tranchée ;
- une définition absente du chemin lu : si le schéma passe par un `$ref`, `jq` rend `null` pour le champ, avec le code 0. Un `null` se lira « définition non trouvée à ce chemin », pas « aucune contrainte ».

## Passage de `releve5`, le 12/11/2026 à 16:47:23 UTC (« Oui, lance releve5 »), code 0

[Journal](m2-releve5.log). `chrono.tsv` porte le début et la fin dans la même seconde. Note écrite à partir de 16:47:47 UTC. Précisée avant le commit, sur relecture du conseiller. sha256 de l'archive contrôlé (celui de `releve`). Aucune ligne du journal n'est coupée : la plus longue fait 178 caractères, sous la coupe de 220 de `plage` ; les lignes de `lignes` restent sous 170. Les définitions du schéma sont trouvées au chemin lu (aucun `null`).

| # | Résultat |
|---|---|
| W1 | **Tenue.** `query_packages` lance `rpm -qa --root <chroot> --qf`, avec un format construit des noms de champs : `%{name}`, …, `%{sigmd5}`, séparés par `\|/@` (`installed_packages.py:51` à `:68`). Le sigmd5 du verrou est la sortie brute de rpm. Seuls `signature` (`%{sigpgp:pgpsig}`, réduit aux 8 derniers caractères de l'identifiant de clé, `:77` à `:79`) et `epoch` (`(none)` devient `null`) sont retouchés |
| W2 | **Tenue.** `query_packages_location` lance un seul `dnf --installroot=<chroot> repoquery -q --location`, avec en arguments le `<nom>-<version>-<release>.<arch>` de tous les paquets (`:116` à `:131`). Une URL manquante arrête mock (`Can't get location for …`, `:148` à `:151`, test `:120` à `:135`) |
| W3 | **Tenue.** Les entrées `gpg-pubkey` sont écartées à la sortie de `query_packages` (`:88`), et le test l'affirme (« gpg-pubkey packages stay ignored », `test_buildroot_lock.py:16`, avec deux lignes `gpg-pubkey` en entrée, `:19` et `:20`) |
| W4 | **Tenue.** Le journal porte quatre valeurs de sigmd5 distinctes, toutes de 32 caractères hexadécimaux minuscules (mesuré par `grep -owE '[0-9a-f]{32}'` sur le journal) : `installed_packages.py:47`, et les sorties de rpm simulées de `test_buildroot_lock.py:21`, `:22` et `:27`, dont `:44` et `:55` sont les valeurs attendues dans le verrou. Le schéma 1.1.0 ne déclare que `"type": "string"` et la description « The SIGMD5 tag from the rpm header » : aucun motif |

**Conséquences pour les prédictions de la voie 2** (le tableau V1 à V5 n'est pas réécrit) :
- **V1** reste de confiance moyenne. Les URL viennent bien des dépôts que voit `dnf --installroot` dans le chroot. Quels dépôts il voit (configuration de mock ou `/etc/yum.repos.d` du chroot, que cite la docstring `:95`) n'est pas lu.
- **V2** monte à haute pour le code : mock 6.9 écarte `gpg-pubkey` avant d'écrire le verrou. Reste la mesure sur un verrou réel.
- **V3** monte à moyenne : sigmd5 est la sortie de rpm pour l'étiquette SIGMD5, en hexadécimal minuscule dans les exemples. Le cœur la relit par `%{SIGMD5}`, en capitales, mock par `%{sigmd5}` : que rpm lise les deux de même n'est pas mesuré ici. Un écart donnerait un KO, pas un faux OK.

**Ce que le relevé apprend en plus, sans décision :**
- **L'URL est cherchée par nom, version, release et arch, pas par contenu.** Dans le code lu (`installed_packages.py`, `buildroot_lock.py`, `mock-hermetic-repo.py`, parties de `config.py`), rien ne lie le fichier pointé par l'URL au paquet installé. Notre comparaison des en-têtes au verrou (sigmd5 compris) est ce lien ; `mock-hermetic-repo` ne la fait pas (N6r). Elle a une limite : `rpm -qp --qf %{SIGMD5}` lit une étiquette de l'en-tête, il ne recalcule rien. Le contenu n'est lié à cette étiquette que si `rpm -K` revérifie le condensat MD5 de l'en-tête et de la charge ; ce n'est pas mesuré dans l'image. `rpm -Kv` sur un fichier, qui détaille chaque contrôle, rejoint la liste de ce qui attend le branchement.
- **Une URL par `nom.arch`** : si `repoquery` rend deux lignes pour le même paquet (même NVRA dans deux dépôts), la dernière gagne (`:133` à `:138`). La comparaison du sigmd5 couvre ce cas.
- **Le champ `signature`** porte les 8 derniers caractères hexadécimaux de l'identifiant de la clé, ou `null` pour un paquet non signé. Le cœur ne le lit pas : `rpm -K` avec la seule clé de Rocky fait le contrôle. Le comparer aussi à la clé de Rocky, sur l'hôte, serait un garde de plus ; ce n'est pas écrit.

## Additif du 12/11/2026, à partir de 17:20:08 UTC : étape `releve6` ajoutée à `m2.sh`, NON LANCÉE

Après « continue », sur relecture du conseiller. **Hôte seul, sans réseau, lecture seule** : l'étape relit la même archive que `releve5`, après contrôle de son sha256.

**Pourquoi.** V1 reste de confiance moyenne. Les URL du verrou viennent d'un `dnf --installroot=<chroot> repoquery -q --location` construit à la main, sans autre option (`installed_packages.py:116` à `:131`, [m2-releve5.log](m2-releve5.log)). Quels dépôts voit cet appel n'est pas lu. Deux choses en décident :
- la configuration que mock écrit, et la façon dont il appelle dnf d'ordinaire ;
- les dépôts que le modèle `rocky-9.tpl` laisse actifs après le remplacement des mirrorlist par `s1.sh`. Ce remplacement ne vise que BaseOS, AppStream et CRB (`s1.sh:338` à `:341`), et la sonde de S1 ne refuse que les mirrorlist restants de ces trois dépôts (`s1.sh:385` à `:387`).

**Ce qui est archivé au journal** :
- `package_manager.py` entier ;
- les lignes de `config.py` qui citent `package_manager`, `releasever`, et les commandes ou options communes de dnf (`dnf[0-9]*_command` compris) ;
- `doOutChroot` de `buildroot.py`, avec ses définitions et appels dans `mock/py` ;
- `rocky-9.tpl` entier.

Puis, sur l'hôte, un script Python rejoue le remplacement de `s1.sh` sur le `dnf.conf` du modèle, par `str.replace` comme `MOCK_CFG`. Le modèle est lu comme du texte, jamais exécuté. Le script liste la section `[main]` et chaque dépôt (enabled, baseurl, mirrorlist, metalink). Si `configparser` ne lit pas le `dnf.conf` (une ligne jinja, par exemple), l'erreur est journalisée et la lecture se fait ligne à ligne : en-têtes de section et clés `enabled`, `baseurl`, `mirrorlist`, `metalink` et `reposdir`. Il compte enfin les dépôts actifs, ou sans `enabled`, qui ne pointent pas que sur des baseurl de vault 9.7. Il s'arrête en KO dans deux cas : les trois lignes du remplacement ne sont plus telles quelles dans `s1.sh`, ou le `dnf.conf` du modèle n'est pas une seule affectation `= """…"""`. Les chemins des fichiers ont été pris dans la liste de l'archive (`tar -t`), sans en lire le contenu.

`bash -n` passe, et shellcheck ne relève aucun avertissement (`-S warning`). Les deux pièces neuves ont un banc hors réseau, sur un modèle et un fichier Python synthétiques : [m2-releve6-essai-local.sh](m2-releve6-essai-local.sh) ([journal](m2-releve6-essai-local.log)). Ses sept cas rendent ce qui est attendu : pour le script Python, le cas nominal, `s1.sh` changé, une ligne hors INI (lue ligne à ligne, code 0) et deux affectations ; pour `fonction`, une définition trouvée, absente, et un fichier absent. Accord nommé attendu.

| # | Prédiction | Confiance | Ce qu'elle change |
|---|---|---|---|
| X1 | L'appel ordinaire de dnf par mock ne passe ni `-c` ni `--config` : il compte sur le `dnf.conf` écrit dans la racine | Faible : souvenir, non lu | Tenue : l'appel du verrou et la construction lisent la même configuration, si dnf lit celle de la racine. Non tenue : l'appel du verrou, qui n'a pas `-c`, peut lire une autre configuration que la construction ; V1 baisse |
| X2 | `package_manager.py` écrit `config_opts['dnf.conf']` en `etc/dnf/dnf.conf` sous la racine du buildroot | Moyenne : le verrou passe `make_chroot_path()` en `--installroot` (`buildroot_lock.py:43`, [m2-releve2.log](m2-releve2.log)) | Non tenue : la configuration de mock n'est pas là où `--installroot` la cherche ; V1 baisse |
| X3 | Avec une image de bootstrap, `doOutChroot` lance la commande dans le chroot du bootstrap, pas dans le système de fichiers du pod | Moyenne : le nom de la fonction | Dit quelle configuration serait le repli de dnf hors de la racine : celle de l'image de bootstrap |
| X4 | La section `[main]` du `dnf.conf` de `rocky-9.tpl` pose `reposdir=/dev/null` | Moyenne : souvenir des modèles de mock-core-configs | Non tenue : les fichiers `.repo` de la racine s'ajouteraient aux dépôts de mock ; V1 baisse, décision avec toi |
| X5 | Le remplacement de `s1.sh` touche une fois chacun BaseOS, AppStream et CRB | Moyenne : la sonde de S1 le contrôle aussi, dans l'image, mais n'a jamais tourné | Non tenue : un dépôt visé garde son mirrorlist, et D2 a (`vault/rocky/9.7` en baseurl fixes, [README](../README.md) ligne 56) ne lui est pas appliquée ; `s1.sh` à corriger, sur accord, après S5b |
| X6 | Au moins un autre dépôt reste actif avec un mirrorlist (extras, sans doute) | Faible : souvenir | Tenue : la construction de S1 voit un dépôt non figé, hors de vault 9.7, que D2 a ne nomme pas. Le verrou peut alors porter une URL de miroir, que `voie2_preparer` refuse (KO, pas de faux OK). Suite à décider avec toi, après S5b |

**Ce que `releve6` ne tranchera pas** :
- **le comportement de dnf lui-même** : lit-il le `dnf.conf` et le `reposdir` de la racine quand on lui passe `--installroot` sans `--config` ? Ce n'est pas dans l'archive de mock, et ce n'est pas écrit de mémoire. V1 peut monter au mieux « pour le code de mock » ; le premier verrou réel le mesurera ;
- quel binaire de dnf tourne dans notre bootstrap, si `package_manager.py` le choisit selon ce qui existe à l'exécution ;
- la valeur par défaut d'`enabled` quand un dépôt ne le pose pas, qui relève aussi de dnf. Un tel dépôt est compté avec les actifs, par prudence ;
- le rendu jinja que mock applique à la configuration : seuls les marqueurs `{{` et `{%` sont comptés ;
- la configuration effective dans l'image. Le remplacement est rejoué sur l'hôte, sur le texte du modèle extrait par une expression régulière ; la sonde de S1 (`mock --debug-config`) reste la mesure dans l'image ;
- une fonction coupée trop tôt. `fonction` s'arrête à la première ligne non vide de retrait égal ou moindre que le `def` : une chaîne sur plusieurs lignes collée à la marge la couperait. Le nombre de lignes est journalisé. Le décorateur, au-dessus du `def`, n'est pas repris.

## Passage de `releve6`, le 12/11/2026 à 17:26:47 UTC (« Oui » à « Je lance releve6 ? »), code 0

Résultats écrits à partir de 17:28:14 UTC. Journal : [m2-releve6.log](m2-releve6.log), 1125 lignes, sha256 de l'archive conforme. Deux lignes atteignent la coupe de 220 caractères : `rocky-9.tpl:1` (`chroot_setup_cmd`, dont la fin n'est pas lue) et le résumé `[main]` du script Python, que `rocky-9.tpl:10` à `:27` donne en entier.

| # | Résultat |
|---|---|
| X1 | **Tenue.** `build_invocation` (`package_manager.py:220` à `:251`) construit `[commande, --installroot <racine>, --releasever <releasever>, -C hors ligne, enable_disable_repos, options communes]`, sans `-c` ni `--config`. Les options communes (`package_manager.py:157` à `:164`) sont `dnf4_common_opts` (`config.py:378` : deux `--setopt` et `--allowerasing`), des `--disableplugin=` et `--forcearch` ; le seul `--config` du fichier est celui de yum (`:605`). L'appel du verrou (`installed_packages.py:121` à `:127`) n'a ni `--releasever` (`rocky-9.tpl:3` pose `'9'`), ni ces options communes, ni `-C` |
| X2 | **Tenue.** `Dnf.initialize_config` écrit `config_opts['dnf.conf']` en `<racine>/etc/dnf/dnf.conf` (`package_manager.py:700` à `:707`), après que la classe mère a effacé `<racine>/etc/yum.repos.d` (`:548` à `:550`, « configs we get from container image ») |
| X3 | **Tenue.** Avec un bootstrap, `doOutChroot` lance la commande par `bootstrap_buildroot.doChroot`, le buildroot monté dans le bootstrap (`buildroot.py:418` à `:421`) ; sur l'hôte seulement sans bootstrap (`:423`). La commande est celle du gestionnaire choisi : `/usr/bin/dnf-3` pour dnf4 (`Dnf.name = 'dnf4'`, `package_manager.py:684` ; `config.py:376`). Le choix se fait à l'exécution, selon ce qui existe dans le bootstrap (`fallbacks['dnf4'] = ['dnf4', 'dnf5', 'yum']`, `:21` à `:22` et `:55` à `:102`) : quel binaire tourne n'est pas mesuré |
| X4 | **Tenue.** `rocky-9.tpl:13` pose `reposdir=/dev/null` |
| X5 | **Tenue.** Le remplacement de `s1.sh` touche une fois chacun BaseOS, AppStream et CRB, tous trois `enabled=1` |
| X6 | **Tenue.** Seul `extras` reste actif hors de vault 9.7 : `mirrorlist=…repo=extras-$releasever`, `enabled=1`, `metadata_expire=6h` (`rocky-9.tpl:57` à `:64`). Le modèle compte 25 dépôts : 4 `enabled=1` (BaseOS, AppStream, CRB, `extras`) et 21 `enabled=0` (comptés au journal) |

**Conséquences pour V1** (le tableau V1 à V5 n'est pas réécrit) :
- **Dans le code de mock**, l'appel du verrou voit les dépôts du `dnf.conf` de mock, si dnf lit la configuration de la racine : BaseOS, AppStream et CRB sur vault 9.7, et `extras` par mirrorlist. Au moment du verrou, seul `reposdir=/dev/null` écarte les fichiers `.repo` de la racine, et seulement si dnf lit le `dnf.conf` de la racine. L'effacement de `yum.repos.d` (`package_manager.py:550`) a lieu à l'initialisation de la configuration ; quand, par rapport à `chroot_setup_cmd`, n'est pas lu, et ce dernier installe `redhat-release` (`rocky-9.tpl:1`), qui peut en reposer.
- **Une URL de miroir dans le verrou** n'apparaît que si un paquet du buildroot a son NVRA dans `extras`. `query_packages_location` garde alors la dernière ligne par `nom.arch` (`installed_packages.py:133` à `:138`), et `voie2_preparer` s'arrête (URL hors de vault 9.7) : KO, pas de faux OK.
- **V1 reste de confiance moyenne.** Deux inconnues restent : le comportement de dnf avec `--installroot` sans `--config` (non lu), et le contenu d'`extras`.
- **Sans `--releasever`**, dnf résout seul le `$releasever` du mirrorlist d'`extras`. Les trois baseurl de vault 9.7 n'ont pas de variable. Non mesuré.

**Pour S1, sans décision** :
- La construction de S1 voit `extras`, un dépôt non figé, servi par mirrorlist, hors de vault 9.7. D2 a (« Source des rpm » : `vault/rocky/9.7` en baseurl fixes, [README](../README.md) ligne 56) ne le nomme pas.
- La sonde de S1 le listera (`s1.sh:384`) sans s'arrêter : son contrôle ne porte que sur BaseOS, AppStream et CRB (`s1.sh:385` à `:387`).
- Que faire d'`extras` est à décider avec toi. Le `s1.sh` de la 05 ne change pas avant S5b.

## Additif du 12/11/2026, à partir de 17:46:28 UTC : étape `releve7` ajoutée à `m2.sh`, NON LANCÉE

Après « continue », sur relecture du conseiller. **Hôte seul, réseau, lecture seule** : ni cluster, ni Zot, ni `s1.sh` modifié. Elle demande ton accord nommé.

**Pourquoi.** `releve6` a montré qu'`extras` reste actif, par mirrorlist, hors de vault 9.7. Que faire d'`extras` est ta décision, après S5b. Deux faits non mesurés la conditionnent : un `extras` 9.7 existe-t-il dans vault, signé par la clé de Rocky ? Un paquet du buildroot peut-il en venir ? `releve7` mesure le premier et approche le second par des croisements de noms.

**Ce que fait l'étape** :
- lit `VAULT97`, `CLE_ROCKY` et `FP_ROCKY` dans `s1.sh`, une ligne chacune, sinon KO ;
- télécharge la clé de Rocky et exige l'empreinte `FP_ROCKY`, dans un trousseau temporaire ;
- relit `chroot_setup_cmd` dans le `rocky-9.tpl` de l'archive gardée (sha256 contrôlé, sans réseau) ;
- lit la réponse du mirrorlist d'`extras-9` (releasever 9, `rocky-9.tpl:3`). Elle journalise le code HTTP, le nombre d'URL et les segments « /<version>/<dépôt>/ » des chemins, hôte retiré. Les hôtes et les lignes de commentaire ne sont pas journalisés : ils situent le client. Un mirrorlist illisible donne un KO, la suite tourne et le code final est 1 ;
- liste les dossiers de `vault/rocky/9.7/` (liste HTML, non signée : un index, pas une preuve). Deux dossiers `extras/` à la casse près donnent un KO. Aucun : `repomd.xml` est cherché quand même sous `extras/` ;
- pour BaseOS, AppStream et CRB de vault 9.7, puis `extras` de vault 9.7, puis `pub/rocky/9/extras` (la baseurl commentée du modèle, `rocky-9.tpl:60`, avec releasever 9) : `repomd.xml` signé par `FP_ROCKY` (`gpgv`, ligne `VALIDSIG`, comme `s1.sh:185` à `:189`), `primary` égal à la somme de `repomd.xml`, paquets et provides mis à plat. Un `repomd.xml` d'`extras` en HTTP 404 donne ABSENT, code 0 ; pour BaseOS, AppStream ou CRB, un KO. Un témoin altéré (le `repomd.xml` de BaseOS plus une ligne) doit être refusé ;
- liste les paquets de chaque `extras` lu, puis les croise avec les noms de `chroot_setup_cmd` (par nom de paquet et par provides) et avec les noms de BaseOS, AppStream et CRB 9.7. Si les deux `extras` sont lus, les noms propres à chacun ;
- efface tout à la fin (clé, métadonnées, modèle extrait), sauf après un KO qui arrête l'étape : les fichiers restent alors sous `~/.cache` jusqu'au passage suivant, qui les efface en commençant. Le primary peut être en `.gz`, `.xz` ou `.bz2`, avec une somme sha256 exigée : Rocky 9.8 sert du `.gz` ([s1-hote.log](s1-hote.log)), vault 9.7 n'est pas lu. Les primary de BaseOS, AppStream et CRB sont téléchargés sous `~/.cache`, pas dans `/tmp` ; leur taille n'est pas connue avant le passage.

`bash -n` passe, et shellcheck ne relève aucun avertissement (`-S warning`). Banc hors réseau : [m2-releve7-essai-local.sh](m2-releve7-essai-local.sh) ([journal](m2-releve7-essai-local.log)). `curl` y est simulé ; `gpg` et `gpgv` sont les vrais, avec deux clés d'essai jetables, créées puis effacées par le banc. Le primary de `pub/rocky/9/extras` y est en `.xz`, les autres en `.gz`. Non couverts : `curl` lui-même en échec, un code HTTP autre que 200 et 404 sur le `repomd.xml` d'un `extras`, BaseOS, AppStream ou CRB absent, un primary en `.bz2`, et le vrai `lancer` (sous-shell d'un tube, journal, `chrono.tsv`). Un premier lancement, à 17:48:50 UTC, a échoué dans le banc lui-même : avec le HOME isolé, le relais `python3` de mise ne trouvait plus sa configuration approuvée. Le banc lie désormais l'interpréteur réel dans son dossier `bin/` ; le relancement de 17:49:05 UTC rend les huit cas attendus. Après relecture du conseiller, le primary peut aussi être en `.xz` ou `.bz2`, et celui de `pub/rocky/9/extras` est en `.xz` dans le banc ; relancé à 17:53:28 UTC, le banc rend les mêmes huit codes :
- nominal, code 0 ;
- `extras` absent de vault : ABSENT, code 0 ;
- signature d'`extras` fausse : KO, code 1 ;
- `primary` différent de `repomd.xml` : KO, code 1 ;
- croisement non vide (un nom de paquet commun avec BaseOS, un provides) : listé, code 0 ;
- mirrorlist en HTTP 500 : KO, la suite tourne, code 1 ;
- empreinte de clé différente : KO, code 1 ;
- deux dossiers `extras/` à la casse près : KO, code 1.

| # | Prédiction | Confiance | Ce qu'elle change |
|---|---|---|---|
| Y1 | La clé téléchargée a l'empreinte `FP_ROCKY`, et les `repomd.xml` de BaseOS, AppStream et CRB 9.7 sont signés par elle | Haute : même clé et même contrôle que l'étape `hote` de `s1.sh` ([s1-hote.log](s1-hote.log)) | Non tenue : KO, rien d'autre n'est lu |
| Y2 | Le mirrorlist d'`extras-9` répond HTTP 200, et ses chemins portent `/9.8/extras/` ou `/9/extras/`, jamais `/9.7/` | Moyenne : 9.8 est la version de pub que lit `s1.sh` ; le format de la réponse n'est pas lu | Tenue : la construction de S1 voit l'`extras` de la version courante, qui bouge avec elle, et non celui de 9.7 |
| Y3 | `vault/rocky/9.7/` a un dossier `extras/`, en minuscules, et son `repomd.xml` est signé par la clé de Rocky | Moyenne : souvenir de la structure de vault, non lu | Tenue : un `extras` figé sur vault 9.7, comme les trois autres dépôts, est possible. Non tenue (ABSENT) : cette option tombe |
| Y4 | L'`extras` de vault 9.7 compte moins de 100 paquets, surtout des paquets `*-release` de dépôts tiers ou de SIG | Faible : souvenir | Dit ce que la construction peut tirer d'`extras` |
| Y5 | Aucun nom de `chroot_setup_cmd` n'est un paquet ni un provides d'un des deux `extras` | Moyenne | Non tenue : un paquet installé directement peut venir d'`extras`, et une URL de miroir dans le verrou devient probable |
| Y6 | Aucun paquet d'`extras` n'a un nom présent dans BaseOS, AppStream ou CRB 9.7 | Faible | Non tenue : un même nom dans deux dépôts, où dnf peut prendre la version d'`extras` si elle est plus haute |
| Y7 | `pub/rocky/9/extras` existe, signé par la clé de Rocky, et ses noms diffèrent de ceux de l'`extras` de vault 9.7 | Faible pour la différence | Mesure l'écart entre ce que voit S1 aujourd'hui et un `extras` figé |

**Ce que `releve7` ne tranchera pas** :
- **si un paquet du buildroot vient d'`extras`.** Les croisements sont par nom, sur les seuls noms de `chroot_setup_cmd` : un croisement vide n'exclut pas une dépendance qu'`extras` serait seul à satisfaire. Le premier verrou réel, ou le `root.log` de la construction, le mesurera ;
- **le `$releasever` effectif de l'appel du verrou**, qui ne passe pas `--releasever` ([m2-releve6.log](m2-releve6.log)) : l'étape ne lit que `extras-9` ;
- **les miroirs eux-mêmes.** Seule l'origine `dl.rockylinux.org` est lue ; un miroir peut être en retard ;
- les groupes (comps) et les modules, non lus ;
- que faire d'`extras` : la décision reste la tienne, après S5b. Cette étape ne la prépare par aucune recommandation.

## Passage de `releve7`, le 12/11/2026 à 17:54:37 UTC (« Oui » à « Je lance releve7 ? »), code 0

Fin à 17:54:46 UTC (`chrono.tsv`). Résultats écrits à partir de 17:55:24 UTC. Journal : [m2-releve7.log](m2-releve7.log), 174 lignes, sha256 de l'archive conforme, témoin altéré refusé, fichiers effacés.

| # | Résultat |
|---|---|
| Y1 | **Tenue.** Clé de Rocky à l'empreinte `21CB256AE16FC54C6E652949702D426D350D275D`. Les `repomd.xml` de BaseOS, AppStream et CRB 9.7 sont signés par elle, et ces trois `repomd.xml` ont les mêmes sha256 que dans [s1-hote.log](s1-hote.log). Primary en `.gz` : BaseOS 2160 paquets (21 469 219 octets), AppStream 8708 (2 315 831 octets), CRB 2653 (657 804 octets) ; 7402 noms distincts. Chaque primary est égal à la somme de son `repomd.xml` signé ; l'écart de taille entre BaseOS et AppStream n'est pas expliqué |
| Y2 | **Tenue.** Le mirrorlist d'`extras-9` répond HTTP 200 avec 60 URL, toutes en `/9.8/extras/` ; aucune en `/9.7/` |
| Y3 | **Tenue.** `vault/rocky/9.7/` liste 18 entrées, `../` comprise, soit 17 dossiers, dont `extras/` en minuscules, une seule fois. Son `repomd.xml` est signé par la clé de Rocky ; primary conforme, en `.gz` |
| Y4 | **Tenue.** L'`extras` de vault 9.7 compte 58 paquets, 57 noms (`epel-release` en deux versions). 51 noms sont des `*-release` de dépôts tiers ou de SIG (`centos-release-*`, `rocky-release-*`, `epel-release`, `elrepo-release`, `rpmfusion-free-release*`). Les 6 autres : `anaconda-live`, `livesys-scripts`, `rocky-backgrounds-compat`, `rocky-backgrounds-kde`, `rpaste`, `update-motd` |
| Y5 | **Tenue.** Aucun des 21 noms de `chroot_setup_cmd` n'est un paquet ni un provides de l'un ou l'autre `extras` |
| Y6 | **Tenue.** Aucun paquet de l'un ou l'autre `extras` n'a un nom présent dans BaseOS, AppStream ou CRB 9.7 |
| Y7 | **Tenue.** `pub/rocky/9/extras` existe, signé par la clé de Rocky, 59 paquets. Il a deux noms de plus que l'`extras` de vault 9.7 (`rocky-release-storage-squid`, `rocky-release-storage-tentacle`) et aucun de moins. Des versions diffèrent aussi (`anaconda-live`, `rocky-backgrounds-*`), et `epel-release` n'y est qu'en une version |

**Ce que cela dit, sans décision** :
- **Ce que voit S1 aujourd'hui** : par le mirrorlist, l'`extras` de 9.8, qui bouge avec la version courante de Rocky, et non un dépôt figé.
- **Un `extras` figé existe** : `vault/rocky/9.7/extras`, signé par la même clé que les trois dépôts déjà épinglés.
- **Par nom**, aucun paquet que mock installe d'office ne vient d'`extras`, et aucun nom d'`extras` n'est aussi dans BaseOS, AppStream ou CRB 9.7. Une dépendance indirecte qu'`extras` serait seul à satisfaire n'est pas exclue : le premier verrou réel, ou le `root.log`, le dira.
- **`pub/rocky/9/extras` et les `/9.8/extras/` des miroirs ne sont pas comparés.** La liste de 59 paquets est celle de l'origine, sous `/9/` ; que les miroirs servent la même chose n'est pas mesuré.
- **V1 reste de confiance moyenne.** Le contenu d'`extras` est maintenant lu ; le comportement de dnf avec `--installroot` sans `--config`, le binaire de dnf choisi à l'exécution et le `$releasever` effectif de l'appel du verrou ne le sont pas.
- Que faire d'`extras` reste ta décision, après S5b ; `s1.sh` ne change pas d'ici là.
