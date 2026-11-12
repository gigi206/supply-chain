# Brique 05, S1 : prédictions (écrites le 12/11/2026 à partir de 14:16:03 UTC, avant toute exécution)

Le script est [`s1.sh`](../s1.sh). Le jalon S1 est le M1 du [README](../README.md), renommé comme dans la brique 06. **Rien n'a encore été lu ni écrit dans le cluster, Zot ou les VM, et aucune ressource réseau n'a été lue pour ce jalon.** Les faits cités viennent des journaux déjà archivés de la 05 (relevé amont et audit du 05/11/2026) et du dépôt.

## Accord et calendrier

« Oui, prépare-le » (12/11/2026) vaut pour la préparation à sec seulement. Chaque étape attend un accord nommé.

**Après S5b seulement.** S5b remet Zot à zéro le 13/11 au plus tôt. Une copie faite avant serait effacée, et la règle de sortie touche `builds-sans-internet`, que S5b rejoue.

**Effets prévus**
- **Préalable, hors du script (décision du propriétaire, question 1)** : la politique [`politiques/prefetch-rpm-sortie.yaml`](../politiques/prefetch-rpm-sortie.yaml), puis `prefetch-rpm` ajouté au `NotIn` de `builds-sans-internet` (08c).
- **prealables**, en lecture seule :
  - lecture des politiques de `builds` et des arguments de kube-apiserver ;
  - une spec de pod en dry-run serveur ;
  - lecture des ressources de sc-build et de la place libre de Zot ;
  - lectures publiques depuis l'hôte : clés de Rocky et d'EPEL, page de sécurité de Fedora, repomd et primary de Rocky 9.8, d'EPEL 9 et de vault 9.7.
- **amorce** : écritures **définitives** dans Zot, `amont/rockylinux/rockylinux@sha256:ed654c69…` (9.8) et `@sha256:ee90dc0e…` (9.7).
- **racine** : un pod Kata privilégié root dans `builds`, avec une sortie vers dl.rockylinux.org et dl.fedoraproject.org en 443 ; archive rapatriée sur l'hôte, sous `~/.cache` (`$W/s1-05`).
- **image** : écriture **définitive** dans Zot, `essais-05/mock-rocky9:s1`.
- **essais** :
  - un pod Kata privilégié root, avec une sortie en 443 vers vault 9.7 et, si le modèle les garde, vers les miroirs de Rocky pour les dépôts non remplacés ;
  - tirage de l'image de bootstrap depuis Zot, en 5000 ;
  - journaux de mock archivés dans `resultats/s1-essais-mock.log`, lignes `jeton|token` retirées.

`builders/mock-rocky9` reste réservé à S2, comme `builders/sbuild-debian13` pour la 06.

## Périmètre

- **Risque visé** : podman imbriqué dans un pod Kata (prédiction 4 du README), puis l'isolation `nspawn` contre `simple` (prédiction 3).
  - Le build de sample-app n'est **pas hermétique** : mock résout et télécharge depuis vault 9.7 pendant l'essai.
  - Le verrou, `mock-hermetic-repo` et `--hermetic-build` sont l'objet de M2.
  - S1 ne conclut rien sur le caractère bit-identique.
- **Image de bootstrap non « prête »** (`bootstrap_image_ready = False`) : mock y installe dnf depuis vault 9.7. Le mode hermétique exige une image prête : c'est M2 qui le traitera.
- **mock tourne en root**, dans l'invité Kata (D1 a).
- **Replis non lancés** par ce script : stockage `vfs` pour podman, mock non root, bootstrap sans image. Chacun demandera sa prédiction et un accord.
- **Dépôts de debug et de sources** : ceux du modèle `rocky-9.tpl` gardent leur `mirrorlist`, mais ne sont pas remplacés. Le script s'arrête avant mock s'il reste un `mirrorlist` actif pour BaseOS, AppStream ou CRB.

## Prédictions

| # | Prédiction | Confiance |
|---|---|---|
| P1 | `prealables` s'arrête au premier contrôle tant que `prefetch-rpm-sortie` n'est pas posée. Une fois posée, et `prefetch-rpm` dans le `NotIn`, tous les contrôles passent | Haute pour l'arrêt ; moyenne pour le reste |
| P2 | Clé de Rocky : empreinte `21CB256A…350D275D`. Les cinq repomd de Rocky (9.8 : BaseOS, AppStream ; 9.7 : BaseOS, AppStream, CRB) sont signés par cette clé | Haute : mesuré le 05/11 pour 9.7 et 9.8 |
| P3 | EPEL 9 ne publie pas de `repomd.xml.asc` : son intégrité repose sur les rpm signés et sur TLS. L'empreinte de sa clé figure sur la page de sécurité de Fedora | Moyenne pour les deux points : rien n'a été lu |
| P4 | Les quatre paquets épinglés ont chacun un seul candidat : mock `6.9-1.el9` et mock-core-configs `45.2-1.el9` (noarch, EPEL), podman `5.8.2-8.el9_8` et skopeo `1.22.2-9.el9_8` (x86_64, AppStream 9.8). Le primary d'EPEL est en zstd, ceux de Rocky en gzip | Moyenne : 9.8 et EPEL bougent depuis le 05/11 ; compression non lue |
| P5 | `racine` : dnf installe les quatre paquets et leurs dépendances. Les repomd lus par dnf sont égaux à ceux de l'hôte. 100 % des rpm sont conformes aux primary et `rpm -K` est OK. systemd-container est tiré par mock | Moyenne : la dépendance de mock à systemd-container n'est pas lue |
| P6 | Le cache de dnf se trouve dans la racine (`/w/racine/w/cache`) et non sous `/w/cache`, à cause de `--installroot` | Faible : le script lit les deux |
| P7 | Archive de la racine entre 400 et 900 Mo ; rapatriement par `kubectl exec` (sortie) sans blocage | Faible pour la taille ; moyenne pour le rapatriement (`egress-selector-mode: disabled` est dans `08b-rke2/config/sc-confiance.yaml`, rejoué par S5b) |
| P8 | `essais`, podman imbriqué : stockage `overlay` sous `/w` (tmpfs) accepté ; `podman pull` du bootstrap depuis Zot et `image mount` réussis | **Faible** : c'est le risque principal. Si overlay échoue, le repli `vfs` demandera un accord |
| P9 | `nspawn` échoue dans le pod Kata, `simple` passe | Faible : prédiction 3 du README, non documentée |
| P10 | Avec `simple`, le src.rpm et le rpm de sample-app sont produits, golang et nodejs venant de vault 9.7. `rpm --rebuild` dure moins de 5 minutes | Moyenne pour le build ; faible pour la durée |
| P11 | La place occupée sous `/w` reste sous 3,5 Gio, pour 4 Gio de tmpfs | Faible : aucune mesure |
| P12 | mock accepte de tourner en root, avec au plus un avertissement | Faible : non lu dans le code |

## Ce qui reste non vérifié avant l'exécution

- Le comportement de `dnf --installroot` avec `-c`, `cachedir` et `reposdir` (P6). Le script lit les deux emplacements possibles du cache.
- La présence d'un `fedoraproject.org/security/` lisible sans JavaScript (P3). Si la page ne l'est pas, l'étape `prealables` s'arrête en KO, sans repli.
- La clé que vise `gpgkey` dans `rocky-9.tpl` : la sonde affiche l'empreinte des clés `distribution-gpg-keys/rocky`, sans l'imposer.

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

## Résultat de l'étape `hote`, le 12/11/2026 de 14:23:42 à 14:23:58 UTC (chrono.tsv), accord « Oui, lance hote »

Le journal est [`s1-hote.log`](s1-hote.log) : 0 KO. Lectures publiques depuis l'hôte seulement, sans cluster ni Zot.

- **P2 tenue.**
  - La clé de Rocky a l'empreinte `21CB256A…350D275D`.
  - Les cinq repomd sont signés par elle : 9.8 BaseOS et AppStream, 9.7 BaseOS, AppStream et CRB.
  - Les repomd de vault 9.7 ont les mêmes sha256 que le 05/11 (`fa6d5054…`, `06f01d40…`, `3936113e…`) : le dépôt est bien figé.
- **P3 tenue.**
  - EPEL 9 ne publie pas de `repomd.xml.asc`.
  - L'empreinte de sa clé, `FF8AD134…3228467C`, figure sur fedoraproject.org/security/.
- **P4 : épinglages tenus, détail de compression faux.** Les quatre paquets ont chacun un seul candidat :
  - `mock-0:6.9-1.el9.noarch` et `mock-core-configs-0:45.2-1.el9.noarch` (EPEL) ;
  - `podman-6:5.8.2-8.el9_8.x86_64` et `skopeo-2:1.22.2-9.el9_8.x86_64` (AppStream 9.8).
  - Le primary d'EPEL est en **xz**, pas en zstd comme prédit ; ceux de Rocky sont bien en gzip.
  - Époques relevées : 6 pour podman, 2 pour skopeo.
- Les sha256 des quatre rpm sont au journal. Pub/9.8 et EPEL bougent : l'étape sera rejouée avant `racine`.

Rien d'autre n'a tourné. P1 et P5 à P12 attendent S5b et la décision sur la sortie réseau des pods rpm.

## Additif du 12/11/2026, à partir de 14:43:15 UTC : étape `verrou` ajoutée à sec (« Oui, ajoute-le »), NON LANCÉE

Le relevé de M2 montre que `--hermetic-build` refuse un verrou calculé sans `bootstrap_image_ready=True` (mock 6.9, `config.py:824`). L'étape `verrou` de `s1.sh` mesure dès S1 si `rockylinux:9.7` brut suffit comme image « prête ».

- **Image** : elle porte désormais deux configurations de mock. La seconde, `poc-rocky-9.7-pret-x86_64`, ne diffère de la première que par la racine et `bootstrap_image_ready = True`. L'étape `image` le contrôle (4 lignes de diff, ni plus ni moins).
  - Ce contrôle a été vérifié sur l'hôte, sur la configuration rendue : 4 lignes, syntaxe Python valide.
- **Déroulement** :
  - pod Kata privilégié, root, label `prefetch-rpm` ;
  - `mock --buildsrpm`, puis `mock --calculate-build-dependencies` sur le src.rpm, avec l'isolation `ISOLATION` (`simple` par défaut, d'après P9) ;
  - le verrou produit est archivé dans `resultats/s1-verrou.json`, lignes `jeton|token` retirées, puis résumé. Rien n'est poussé dans Zot.
- **Le résumé suppose des clés lues en partie** : `config` et `bootstrap.image_digest` viennent de `buildroot_lock.py:100-111`, mais `buildroot.rpms` est une hypothèse. Le JSON complet est archivé dans tous les cas.
- **Ordre** : après `essais`, avec l'isolation que `essais` aura vue passer.
- **Vérifié à sec** : `bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement.

| # | Prédiction | Confiance |
|---|---|---|
| V1 | `--buildsrpm` passe avec `bootstrap_image_ready = True` et `rockylinux:9.7` brut | Faible : ce que mock exige d'une image prête n'est pas lu |
| V2 | Si V1 échoue, c'est faute d'un outil dans l'image (dnf, `dnf-plugins-core` ou leurs équivalents), avec un message explicite de mock | Moyenne |
| V3 | `--calculate-build-dependencies` produit un seul fichier JSON dans le répertoire de résultat. Ce verrou est au format `1.1.0` et enregistre `bootstrap_image_ready: True` ainsi que le digest `ee90dc0e…` du bootstrap | Moyenne |
| V4 | Les macros d'OBS ne sont **pas** recopiées dans `config` du verrou | Faible : la liste des options recopiées n'est pas lue |
| V5 | Le verrou liste entre 150 et 400 rpm pour le buildroot de sample-app (golang, nodejs, `@buildsys-build`) | Faible |

## Note du 12/11/2026, écrite à partir de 15:18:25 UTC : lecture de V3 après `releve3` de M2

Le texte au-dessus n'est pas réécrit.
- `releve3` a montré que `bootstrap.image_digest` est un sha256 des sections `RootFS` et `Config` de `podman image inspect` (`podman.py:21` à `:59`). Il ne peut donc pas valoir `ee90dc0e…`, qui est le digest du manifeste dans le registre.
- La partie « digest `ee90dc0e…` » de V3 se lira sur `bootstrap.pull_digest`, le `.Digest` de `podman image inspect` (`podman.py:266`).
- Le résumé de l'étape `verrou` n'affichait qu'`image_digest`. Il est corrigé à sec à la même heure pour afficher aussi `pull_digest` et `architecture`. Le verrou complet était déjà archivé. **La modification de `s1.sh` demande un accord avant que `verrou` ne tourne.**

**Accord du 12/11/2026, noté à 15:19:53 UTC** : « Oui, valide-la ». La correction du résumé de l'étape `verrou` (commit c45d826) est validée. L'étape elle-même n'est pas lancée : elle tournera après S5b, sur accord nommé.

## Note du 12/11/2026 : sonde de l'étape `verrou` corrigée à sec à partir de 15:23:35 UTC, note écrite à partir de 15:24:22 UTC, ajout proposé (après « continue »), NON LANCÉE

Le texte au-dessus n'est pas réécrit. Lecture des sources de mock 6.9 en cache (archive `3c034916…3e4d88`, sha256 contrôlé), sans réseau. **Cette lecture n'est pas archivée**, contrairement à celles de `m2.sh` : les numéros de ligne cités ci-dessous se relisent dans cette archive.

**Défaut de la sonde commitée.**
- `mock --debug-config` écrit `config_opts['clé'] = valeur`, et seulement pour les clés qui diffèrent de leur valeur par défaut (`mock.py:605` à `:619`).
- L'ancien motif `bootstrap_image_ready.: (True|False)` ne trouve rien sur ce format : essayé sur la ligne `config_opts['bootstrap_image_ready'] = True`, grep rend le code 1. La ligne « configuration : » serait sortie vide, sans le signaler.
- La sonde garde maintenant la sortie entière dans le pod et relève la ligne `bootstrap_image_ready`. Si elle est absente, la sonde l'écrit : la valeur est alors celle par défaut, `False` (`config.py:109`). Si `--debug-config` échoue, la sonde l'écrit aussi, avec ses 5 dernières lignes, et ne conclut rien.
- Les quatre options `bootstrap_*` reçoivent leur valeur par défaut, une liste vide, dans `setup_default_config_opts()` (`config.py:54`, puis `:347` à `:350`). `--debug-config` ne les écrit donc que si elles sont posées.

**Ajout proposé après `releve2`, joint à la correction :**
- le nombre de lignes de `--debug-config` pour les quatre options `bootstrap_*` qui annulent « prête » (`buildroot.py:1182` à `:1185`), puis ces lignes elles-mêmes ;
- après `--buildsrpm`, puis après `--calculate-build-dependencies`, le nombre et le texte des lignes de tout `root.log` qui contiennent l'un des trois messages de `bootstrap_image_is_ready` (`buildroot.py:1176`, `:1188`, `:1193`). `root.log` est ouvert en ajout (`buildroot.py:699`) : le second relevé cumule les deux appels.

**Essai hors cluster, journal non archivé**, refait après relecture du conseiller, entre 15:24:22 et 15:26:21 UTC (heures des deux écritures de cette note) : faux `mock` qui écrit le format lu. Cinq cas, sous `sh` puis sous `bash`, soit dix passages :
- cas normal ;
- `bootstrap_module_enable` posée ;
- clé `bootstrap_image_ready` absente ;
- `--debug-config` en échec ;
- `--buildsrpm` en échec avant tout `root.log`.

Les dix passages donnent les lignes attendues. Le premier jet de la correction avait un repli muet : le `|| echo` portait sur le code de `sed`, toujours 0. Il est corrigé avant ce commit. Le pod, mock et Zot réels ne sont pas touchés. `bash -n` passe, et shellcheck `-S warning` ne relève rien.

| # | Prédiction | Confiance |
|---|---|---|
| V6 | La sonde écrit `configuration : config_opts['bootstrap_image_ready'] = True` | Haute : la clé diffère de sa valeur par défaut, et `image` la pose par `sed` |
| V7 | Aucune des quatre options `bootstrap_*` n'est posée (nombre 0) | Haute : ni `rocky-9.tpl` ni `rocky-9-x86_64.cfg` (mock-core-configs 45.2) ni `s1.sh` ne les posent ([complément](m2-releve2-complement.log)). Le `site-defaults.cfg` de mock-core-configs, dans la même archive, n'a aucune ligne active |
| V8 | `root.log` ne contient ni « Package management in bootstrap » ni « Bootstrap image not marked ready » | Haute si V6 et V7 tiennent |
| V9 | Après `--buildsrpm`, `root.log` contient au moins une ligne « Not updating bootstrap chroot, bootstrap_image_ready=True » | Moyenne : le message ne part que si l'initialisation du bootstrap appelle `_init_pkg_management` (`buildroot.py:356`, `:590`). Il faut aussi qu'il atteigne le `root.log` de `/w/res-verrou` par le journal `mockbuild` partagé (`buildroot.py:125`). L'ordre de ces étapes n'est pas lu |

Après `--calculate-build-dependencies`, l'accroissement du nombre n'est pas prédit : je n'ai pas lu si le bootstrap y est initialisé à nouveau.

**La modification de `s1.sh` demande un accord avant que `verrou` ne tourne.**
