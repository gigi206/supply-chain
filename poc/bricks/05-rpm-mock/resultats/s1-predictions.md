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

**Accord du 12/11/2026, noté à 15:32:22 UTC** : « Oui, valide-la ». La correction de la sonde de l'étape `verrou` et l'ajout joint (commit 870ba1d) sont validés. L'étape elle-même n'est pas lancée : elle tournera après S5b, sur accord nommé.

## Second passage de l'étape `hote`, prédictions HB1 à HB8 (note du 2026-11-16, écrit à 2026-11-16T22:10:53Z ; rien n'est réécrit), NON LANCÉ

**Pourquoi.** S5b est fait depuis le 13/11/2026. L'en-tête de `s1.sh` dit `hote` « à rejouer avant racine, pub/9.8 et EPEL bougent ».
Ce passage la rejoue d'abord, seule, comme sonde d'épinglage : si un paquet épinglé a bougé, `s1.sh` change avant tout geste
dans le cluster. Il ne remplace pas le passage d'avant `racine`, qui compare les repomd lus par dnf à ceux de l'hôte.

**Commande prévue**, sur accord nommé : `PREFIXE=s1-2 DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh hote`. `PREFIXE` ne sert
dans cette étape qu'au nom du journal (`resultats/s1-2-hote.log`) : le journal du 12/11 (`s1-hote.log`) et ses liens restent
intacts. Les étapes suivantes ne lisent de `hote` que `$T/hote` (clés) et `$T/fp-epel`, hors du dépôt ; elles garderont le
préfixe par défaut (étiquette `:s1` de Zot). Hôte seul, réseau, ni cluster ni Zot.

| # | Prédiction | Confiance |
|---|---|---|
| HB1 | Sources : `sample-app-1.0.0.tar.gz` et `sample-app.spec` « OK » contre le `SHA256SUMS` du cache (repassé par N1 : `07521c1e…` et `918a83f5…`) | Haute |
| HB2 | Clés : sha256 égaux au 12/11 (Rocky `3a66e521…`, EPEL `fcf0eab4…`) ; empreinte de Rocky égale à `FP_ROCKY` ; empreinte d'EPEL `FF8AD134…` présente sur la page publiée | Haute |
| HB3 | vault 9.7 : BaseOS, AppStream et CRB signés par la clé de Rocky, repomd.xml aux mêmes sha256 que le 12/11 (`fa6d5054…`, `06f01d40…`, `3936113e…`) | Haute (dépôt figé) |
| HB4 | pub 9.8, BaseOS et AppStream : repomd.xml signés par la clé de Rocky ; sha256 relevés, non prédits | Haute pour la signature |
| HB5 | EPEL 9 : `repomd.xml.asc` absent, primary contrôlé par repomd ; sha256 relevé, non prédit | Haute |
| HB6 | `podman 5.8.2-8.el9_8` et `skopeo 1.22.2-9.el9_8` toujours dans AppStream 9.8, aux mêmes sha256 (`561d6e4d…`, `c6cca7fe…`) | Moyenne-haute : garde des anciennes constructions d'une mineure non mesurée |
| HB7 | `mock 6.9-1.el9` et `mock-core-configs 45.2-1.el9` toujours dans EPEL 9, aux mêmes sha256 (`a5043350…`, `84f19c05…`) | Moyenne : EPEL ne garde en général que la dernière construction |
| HB8 | Code 0, aucune ligne KO | Moyenne (produit de HB6 et HB7) |

**Si une prédiction tombe :**
- un épinglage absent (KO du lecteur, code 1) : arrêt ; les épinglages ne sont pas touchés sans décision du propriétaire. Pour mock,
  toutes les lectures de M2 sont au tag `mock-6.9-1` : changer de version est une décision, pas un correctif ;
- un échec sans ligne KO (`curl -f`, `set -e`) sur `pub/rocky/9.8` : si 9.8 n'est plus la mineure courante et a rejoint le vault,
  D4 (a) est à revoir avec le propriétaire ;
- vault 9.7 différent du 12/11 : arrêt, à comprendre avant tout autre geste.

**Lu à sec pour la suite (pas pour ce passage).** `etape_essais` affiche le nom et le sha256 du src.rpm et du rpm, et archive
la fin de `build.log` et `root.log` ; elle ne rapatrie pas le rpm et ne lit pas son en-tête. N2 s'y lit (nom du src.rpm), N5
peut-être dans la fin du `build.log` ; N3 (fichiers de licence, bit 128, sha256) et N4 (`x11-fichiers` sur le binaire) demandent
un ajout à `s1.sh`, donc un banc à sec et un accord, avant `essais`. La relecture de `etape_prealables` et des attentes R3 à R6
contre les journaux d'après S5b reste à faire avant `rpm_appliquer` et `prealables`.

## Résultat du second passage de `hote` (note du 2026-11-16, écrit à 2026-11-16T22:13:46Z ; rien n'est réécrit)

Lancement accordé le 16/11/2026 (question « Je lance s1.sh hote (PREFIXE=s1-2) ? », réponse « Oui, lance hote »), de 22:12:52 à
22:13:11 UTC (`chrono.tsv`), HEAD 1dd8ec5, commande `PREFIXE=s1-2 DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh hote` :
code 0, 14 lignes OK, aucune KO ([journal](s1-2-hote.log)). **HB1 à HB8 tenues.**
- Toutes les lignes du journal sont égales à celles du 12/11 ([`s1-hote.log`](s1-hote.log)), sauf l'en-tête et deux lignes d'EPEL :
  repomd.xml `454b0238…` → `73fd2581…`, primary `22a1bc17…` → `ccc17999…` (HB5 ne prédisait pas ces sommes).
- Non prédit : les repomd.xml de pub 9.8 (BaseOS `abac8b17…`, AppStream `a3ca4230…`) sont aussi les mêmes que le 12/11 ;
  ils n'ont pas bougé en quatre jours. Cela ne dit rien de leur état au passage d'avant `racine`.
- Les quatre épinglages tiennent, aux mêmes sha256 : mock 6.9-1.el9, mock-core-configs 45.2-1.el9 (EPEL), podman 5.8.2-8.el9_8,
  skopeo 1.22.2-9.el9_8 (AppStream 9.8). `s1.sh` n'a pas à changer pour eux.
- HB1 : les sources contrôlées sont celles du passage N1 (spec `918a83f5…`).
Rien n'a touché le cluster ni Zot. Restent avant `essais` : le correctif de sortie rpm et ses étapes, la relecture de
`prealables` et de R3 à R6 contre les journaux d'après S5b, l'ajout à `s1.sh` pour N3 et N4, la décision `extras` avant `image` ;
chacun sur accord.

## Relecture à sec de `prealables` d'après S5b (note du 2026-11-16, écrit à 2026-11-16T22:23:08Z ; rien n'est réécrit), NON LANCÉ

P1 est inchangée. Base relue sans lecture du cluster :
- **Exemption Pod Security de kata** : relue pendant S5b (`--admission-control-config-file=/etc/rancher/rke2/pod-security.yaml`,
  `08-trust-plane/resultats/rejeu-s5b-plateforme-ctl.log`).
- **Admission.** Les règles `pods-isolation` et `zone-build` (`08-trust-plane/politique/admission.yaml`) et celles de
  `08c-durcissement/politiques/kyverno/durcissement.yaml` n'ont pas changé depuis la préparation de `s1.sh` (12/11). Lues en
  entier, elles sont satisfaites par la spec `s1-05-racine` :
  - runtimeClass `kata`, qui admet le conteneur privilégié ;
  - `emptyDir` en mémoire, sans `hostPath` ;
  - `nodeSelector` `zone=build` et `automountServiceAccountToken: false` ;
  - limites de CPU et de mémoire ;
  - image de `sc-stockage.poc.test:5000` par digest.
- **Précédent de même forme** : `s1-racine` de la 06 (Kata, uid 0, privilégié, mêmes limites, label `prefetch-deb`) a été admis
  le 13/11/2026 à 14:17:00 UTC, après S5b ([`06/resultats/s1r-prealables.log`](../../06-deb-sbuild/resultats/s1r-prealables.log)).
- **Sortie rpm** : `prealables` exige `prefetch-rpm` dans le `NotIn`, donc `rpm_appliquer` avant elle. R3 à R6 sont relues dans
  [`s1-sortie-predictions.md`](s1-sortie-predictions.md).

## Résultat de `prealables`, le 16/11/2026 de 22:49:55 à 22:49:56 UTC (note écrite à 2026-11-16T22:50:26Z ; rien n'est réécrit)

Question : « Je lance prealables ? ». Réponse : « Oui, lance prealables ».

- Commande : `DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh prealables </dev/null`, sur `84b100f`. `date -u` : 22:49:55
  avant, 22:49:56 UTC après ; `chrono.tsv` : idem. Code 0, 0 KO. Premier passage de l'étape.
- Journal : [`s1-prealables.log`](s1-prealables.log) (sha256 `8cd39d73…`).
- **P1 tenue** : `prefetch-rpm-sortie` présente ; `NotIn` à `prefetch-deb,prefetch-gomod,prefetch-rpm` ; kube-apiserver lit
  `/etc/rancher/rke2/pod-security.yaml` (exemption de kata) ; `s1-05-racine` admis en dry-run serveur, rien créé.
- Lectures sans seuil prédit :
  - sc-build : 6 CPU et 10189584Ki de mémoire allouables ; aucun conteneur en cours avec une demande de mémoire.
  - Zot : 5551 Mo libres sous `/` (où se trouve `/var/lib/zot`). À rapprocher de P7 (archive de la racine entre 400 et 900 Mo),
    sans seuil fixé ici.
- Rien n'est posé dans le cluster ni écrit dans Zot.

Suite, chaque point sur accord nommé : ajout à `s1.sh` pour N3 et N4 (banc à sec) ; décision `extras` ; `amorce`, `hote` de nouveau,
`racine`, `image`, `essais`, `verrou`.

## Ajout N3 et N4 à `essais`, préparé à sec (note du 2026-11-17, écrite à 2026-11-16T23:02:29Z ; rien n'est réécrit ; NON APPLIQUÉ)

Préparé après « continue », sur relecture du conseiller (approche, puis points de vigilance), sans toucher au cluster ni à Zot.

**Ce que fait l'ajout** ([`s1-n34.patch`](../s1-n34.patch), sha256 `2da76de2…`, et [`n34-binaire.py`](../n34-binaire.py),
`b88ce099…`). `SONDE` reste inchangée, donc P9 à P11 et les durées gardent leur sens. Après les journaux de mock, et avant le
retrait du pod, `etape_essais` :
1. rapatrie le rpm binaire de sample-app de chaque isolation sous `$T/rpm-<isolation>` (`kubectl exec … cat`), et compare son
   sha256 à la ligne « rpm <isolation> » de la sonde. Si une lecture dans le pod échoue, N3 et N4 restent faisables sans rebuild ;
2. livre `n34-binaire.py` sous `/w/n34`, hors de `/w/src` que `mock --sources` lit ;
3. lance `SONDE_N34` dans le pod. Pour chaque isolation : `FILEDIGESTALGO` ; les fichiers de l'en-tête sous
   `/usr/share/licenses/` (drapeaux, bit 128, empreinte) par `rpm -qp --qf` ; `BUILDTIME` et `CHANGELOGTIME` ; le nombre de
   mtime distincts, avec min et max ; puis `rpm2cpio` et `n34-binaire.py`, qui isole `usr/bin/sample-app` avant de chercher les
   noms de fichiers source. L'isolement est nécessaire : `golang-NOTICES` contient la chaîne `runtime/memmove_amd64.s`.

Sorties brutes : rien n'arrête l'étape, le contrôle se fait dans les notes contre les prédictions ci-dessous.

**Banc hors réseau** ([script](s1-n34-banc.sh), [journal](s1-n34-banc.log)), le 16/11/2026 de 23:01:07 à 23:01:09 UTC :
35 OK, 0 KO.
- `n34-binaire.py`, sur une archive newc du cpio de l'hôte autour du binaire du deb 1.0.0-1 de la 06 (sha256 épinglé) : sortie
  égale aux lignes de [`x11-fichiers.log`](../../13a-licences/resultats/x11-fichiers.log) de la 13a, noms avec et sans `./`.
  Refus vérifiés : archive tronquée, membre absent, magie fausse, membre vide (lien dur). L'isolement est vérifié : un faux
  binaire à côté de `golang-NOTICES` donne `memmove_amd64.s` absent.
- `SONDE_N34` sous bash avec `rpm` et `rpm2cpio` simulés : code 0 dans tous les cas, y compris aucun rpm, deux rpm, une ligne
  d'en-tête illisible et `rpm2cpio` en échec.
- `rapatrier_rpms` sous `set -euo pipefail` avec `kubectl` simulé : égalité et écart signalés, debuginfo ignoré, pod absent sans
  arrêt.
- Deux défauts trouvés par le banc avant tout passage et corrigés dans la copie :
  - GNU cpio 2.15 écrit les noms sans `./` : le premier cas « noms en ./ » ne l'était pas, une archive réécrite le couvre
    désormais ;
  - un répertoire n'a pas d'empreinte, donc le champ vide décalait la lecture : l'ordre est maintenant drapeaux, nom,
    empreinte.
- `bash -n` passe sur la copie modifiée. shellcheck 0.11.0 ne relève aucun avertissement ; au niveau info, il ajoute une
  remarque SC2016 (5 → 6), celle de `SONDE_N34`.
- **Non couvert** : un vrai rpm (forme réelle de `--qf`, nom des membres écrits par `rpm2cpio`, charge zstd) ; le python3 3.9
  du pod (seulement `ast` en version 3.9) ; un vrai `kubectl exec`.

**Précondition, non vérifiée.** mock requiert `python3`, `python3-rpm` et `tar` (primary d'EPEL relu), et `rpm2cpio` est dans
le paquet `rpm` de BaseOS 9.8. Que `rpm` lui-même soit dans la racine n'est pas vérifié : à lire dans la liste des rpm du journal
de `racine`, avant `image`. S'il manque, `SONDE_N34` affiche « not found » sans s'arrêter. N3 reste alors faisable sur le rpm
rapatrié, avec le lecteur d'en-tête de `releve9` ; pour N4, le repli serait à décider.

**Prédictions** (écrites avant tout passage ; précisent N3 à N5 de [`m2-predictions.md`](m2-predictions.md)) :

| | Prédiction | Confiance |
|---|---|---|
| A1 | Pour chaque isolation dont le `--rebuild` passe : « OK   rpm <isolation> rapatrié », sha256 égal à la sonde | Haute |
| A2 | `FILEDIGESTALGO` vaut 8 (sha256) | Haute |
| A3 (N3) | Six fichiers sous `/usr/share/licenses/sample-app/`, bit 128 à 1, empreintes : `golang-LICENSE` `911f8f57…`, `golang-PATENTS` `96f408bf…`, `golang-NOTICES` `b55ad0c8…` (calculées sur les blocs du spec), `Apache-2.0.txt` `074e6e32…`, `LICENSE` `a2d51b75…` (chi), `LICENSE.md` `8e3a3f82…` (marked) (archive des sources) ; plus la ligne du répertoire, sans empreinte | Haute pour les empreintes ; moyenne pour les noms (copie sous le nom de base, non relue dans rpm) |
| A4 (N4) | `memmove_amd64.s` PRÉSENT sous la forme `runtime/memmove_amd64.s` ; témoin `asm_amd64.s` présent, `asm_arm.s` absent ; les huit autres motifs X11 absents ; `n34-binaire.py : rc 0` | Moyenne-haute (Go 1.25.9 au lieu de 1.24 du deb) |
| A5 (N5) | `BUILDTIME` = `CHANGELOGTIME` = 1794830400 (16/11/2026 à 12:00 UTC, date du changelog à midi) ; mtime max 1794830400, valeurs distinctes parmi 1793229566 (archive des sources) et 1794830400 : le clamp joue, l'heure du build tombant après | Moyenne pour l'égalité ; faible pour midi et le fuseau du chroot |
| A6 | Les lignes de N3 et N5 sont les mêmes pour nspawn et simple, si les deux construisent | Moyenne |
| A7 | L'ajout ne prend pas plus d'une minute de l'étape | Moyenne |

**Où se lit chaque N.**
- N2 : ligne « src.rpm <isolation> » de la sonde existante.
- N3 et N5 : lignes « licence », « dates » et « mtime » de `essais-n34`.
- N4 : sortie de `n34-binaire.py` dans `essais-n34`.
- **N6 est hors de cet ajout.** `verrou` ne lit pas l'en-tête du rpm `golang` : la comparaison de sa `LICENSE` à `911f8f57…`
  reste à placer, sur accord à part.

Suite, chaque point sur accord nommé : appliquer l'ajout (une ligne datée à l'en-tête de `s1.sh`) et le commiter ; décision
`extras` ; `amorce`, `hote` de nouveau, `racine` (lire `rpm` dans sa liste), `image`, `essais`, `verrou`.

*Correction de date (note écrite à 2026-11-16T23:02:44Z, rien n'est réécrit)* : l'en-tête de la section « Ajout N3 et N4 à `essais` » ci-dessus dit « note du 2026-11-17 ». C'est faux en UTC : la note est du 2026-11-16, écrite à 2026-11-16T23:02:29Z, comme l'indique son en-tête. « 2026-11-17 » a été tapé à la main d'après l'horloge locale, contre la règle « heure tirée de date -u ». Même erreur dans la note correspondante de `docs/03-validation-briques.md`, corrigée de même.

## Ajout N3 et N4 appliqué au dépôt (note du 2026-11-16, écrite à 2026-11-16T23:07:32Z ; rien n'est réécrit)

Question : « J'applique l'ajout N3 et N4 et je le commite ? ». Réponse : « Oui, applique-le ».

- `git apply` de [`s1-n34.patch`](../s1-n34.patch) le 16/11/2026 à 23:06:52 UTC (`date -u` de la commande), sur `92830e6`.
  `git apply -R --check` passe juste après. Le sha256 de `s1.sh` vaut alors `7a5ec25f…`, celui de la copie bancée
  ([`s1-n34-banc.log`](s1-n34-banc.log)).
- Une ligne datée est ensuite ajoutée à l'en-tête de `s1.sh`, sans rien réécrire. Après elle, `git apply --check` échoue dans
  les deux sens (ligne ajoutée dans le contexte) : le fichier du correctif reste comme trace. `s1.sh` vaut désormais `710f3904…`.
- **Banc repassé sur le `s1.sh` du dépôt**, le 16/11/2026 de 23:07:04 à 23:07:05 UTC : 35 OK, 0 KO
  ([`s1-n34-banc-applique.log`](s1-n34-banc-applique.log), son en-tête porte `710f3904…`). `bash -n` passe ; shellcheck
  0.11.0 sans avertissement (`-S warning`).
- Trois précisions sur la note de préparation, relues par le conseiller :
  - « Rien n'arrête l'étape » a une exception : le `livrer` de `n34-binaire.py` n'est pas gardé. Sous `set -e`, son échec sortirait
    avant `pod_retirer`, le pod restant en place ; les journaux de mock sont déjà archivés à ce moment. Le correctif n'est pas
    modifié pour cela.
  - Les deux passages du banc d'avant les corrections (22:59:55 UTC avec deux KO, puis 23:00:34 UTC) ont été écrasés dans le
    scratchpad et ne sont pas archivés : la phrase « deux défauts trouvés par le banc » n'a pas de journal derrière elle.
  - La précondition « `rpm` dans la racine » n'est pas propre à l'ajout : la sonde existante lance déjà `rpm -q`, et `rpm2cpio`
    est dans le même paquet. La lecture de la liste des rpm de `racine` couvre les deux.
- `-trimpath` est dans le `%build` du spec (`GOFLAGS`) : la forme `runtime/…` attendue par A4 tient.
- Rien n'est lancé : `essais` n'a pas tourné.

Suite, chaque point sur accord nommé : push ; décision `extras` ; `amorce`, `hote` de nouveau, `racine`, `image`, `essais`,
`verrou`.

## Décision `extras` et correctif préparé à sec (note du 2026-11-16, écrite à 2026-11-16T23:27:15Z ; rien n'est réécrit ; NON APPLIQUÉ)

Question : « Quel sort pour le dépôt extras de mock ? ». Réponse : « Extras sur vault ». La recommandation avait été relue par le
conseiller avant d'être présentée.

**Faits qui la fondent** (déjà archivés) :
- `releve6` (X6) : seul `extras` restait actif hors de vault 9.7, par mirrorlist ([m2-predictions.md](m2-predictions.md)).
- `releve7` (Y2 à Y7) : ce mirrorlist sert `/9.8/extras/`, une version qui bouge. `vault/rocky/9.7/extras` existe, signé par la clé
  de Rocky. Par nom et par provides, aucun paquet de `chroot_setup_cmd` n'en vient.
- Le banc OBS de référence n'avait que BaseOS et AppStream. `rocky_9` de
  [`poc.meta.xml`](../../../benchmarks/obs/projets/poc.meta.xml) renvoie à `Rocky:9.7/standard`, qui renvoie à `appstream` et
  `baseos` ([`Rocky-9.7.meta.xml`](../../../benchmarks/obs/projets/Rocky-9.7.meta.xml)). CRB n'y était pas non plus, et S1
  l'épingle déjà sur vault 9.7.
  - La règle que S1 applique de fait est donc : tous les dépôts que le modèle `rocky-9.tpl` active sont mis sur vault 9.7.
    Elle se déduit de D2 (a) et du choix de ce jour ; le propriétaire a choisi une option, il n'a pas énoncé cette règle.
  - L'écart de CRB avec la référence n'est pas décidé ici.

**Ce que fait le correctif** ([`s1-extras.patch`](../s1-extras.patch), sha256 `2d4ef595…`, sur `s1.sh` `710f3904…`) :
1. `MOCK_CFG` : `extras` est ajouté au remplacement des mirrorlist par les baseurl fixes de vault 9.7.
2. Garde de la sonde d'`essais` : `extras` est compté avec BaseOS, AppStream et CRB, et mock n'est pas lancé s'il reste un
   mirrorlist. `str.replace` ne dit rien quand il ne trouve rien : la garde est le seul contrôle qui voit un remplacement sans
   effet. `([^-]|$)` écarte toujours `extras-debug` et `extras-source`.
3. `hote` : le `repomd.xml` d'`extras` de vault 9.7 est vérifié par gpgv, comme les trois autres.
4. Quatre lignes d'en-tête décrivent l'ajout ; on y ajoutera une ligne datée s'il est appliqué.

Cela corrige deux phrases, sans les réécrire :
- le paragraphe « Passage de `releve6` » (12/11) du [README](../README.md) (« la sonde de S1 le listera sans s'arrêter ») ;
- la ligne « Dépôts de debug et de sources » de ce fichier (garde limitée à BaseOS, AppStream et CRB).
Une fois le correctif appliqué, la sonde s'arrête aussi pour `extras`.

**Banc hors réseau** ([script](s1-extras-banc.sh), [journal](s1-extras-banc.log)), le 16/11/2026 de 23:23:49 à 23:23:51 UTC :
27 OK, 0 KO.
- Diff : 5 lignes retirées, 9 ajoutées, rien d'autre.
- `MOCK_CFG` du dépôt et de la copie : chacun est développé par bash, puis exécuté par python3 sur le `dnf.conf` de `rocky-9.tpl`.
  Ce modèle est lu, jamais exécuté, dans l'archive de mock 6.9-1 gardée par `releve`, au sha256 `3c034916…` contrôlé.
  - Avant le correctif : 4 sections actives, dont `extras` en mirrorlist.
  - Après : les 4 sections sont en baseurl de vault 9.7, et celle d'`extras` vaut `…/vault/rocky/9.7/extras/x86_64/os/`. C'est
    le chemin dont `releve7` a vérifié la signature : dossier `extras/` retenu sous vault 9.7 et `repomd.xml` signé par la
    clé de Rocky ([m2-releve7.log](m2-releve7.log), lignes 19, 20 et 36), chemin composé par `m2.sh` en
    `$v/${x%/}/x86_64/os`.
  - Seule la section `extras` change ; `extras-debug` est inchangée.
- Garde : la ligne est lancée telle quelle par `sh`, sur le texte et sur sa forme repr. Les comptes sont donnés pour l'ancienne
  garde, puis pour la nouvelle :
  - modèle brut : 3, puis 4 ;
  - remplacement du dépôt actuel, où `extras` reste en mirrorlist : 0, puis 1. C'est ce que le correctif fait voir ;
  - remplacement de la copie : 0 avec la nouvelle garde.
- Boucle de `hote`, extraite de la copie, avec `curl`, `gpgv` et `attendu` simulés : 4 signatures et 8 URL, dont les 2 d'`extras`.
- `bash -n` passe. shellcheck 0.11.0 ne relève aucun avertissement et compte 13 remarques, avant comme après.
- Un premier passage du banc, le 16/11/2026 de 23:23:37 à 23:23:39 UTC, bilan tenu, a été écrasé dans le scratchpad et n'est
  pas archivé. Le script du banc a ensuite reçu une ligne, `: "$VAULT97" "$FP_ROCKY"`, pour un avertissement de shellcheck sur
  le banc lui-même. Le passage archivé est celui d'après.
- **Banc N3/N4 repassé sur la copie** ([journal](s1-extras-banc-n34.log)), le 16/11/2026 de 23:23:51 à 23:23:52 UTC : 35 OK, 0 KO.
- **Non couvert** :
  - le vrai affichage de `mock --debug-config` ;
  - un vrai dnf ;
  - la signature réelle d'`extras` aujourd'hui (Y3 date du 12/11) ;
  - le contenu réel du buildroot.

**Couplages hors de `s1.sh`, non modifiés** ([`m2.sh`](../m2.sh)) :
- `releve6` contrôle le texte exact de la boucle de `s1.sh`. S'il était rejoué, il s'arrêterait en KO (« releve6 à revoir »).
  C'est une mesure passée et archivée, dont le rejeu n'est pas prévu.
- `voie2_preparer` n'accepte que les URL sous BaseOS, AppStream et CRB de vault 9.7. Un paquet venu d'`extras` y serait refusé :
  KO, pas de faux OK. Cela ne se décide que si le cas se présente (voir EX2).

**Prédictions** (écrites avant tout passage ; elles complètent HB1 à HB8 pour le prochain `hote`, et P1 à P12 pour `essais`) :

| | Prédiction | Confiance |
|---|---|---|
| HX1 | `hote` : le `repomd.xml` d'`extras` de vault 9.7 est signé par la clé de Rocky (`VALIDSIG` `FP_ROCKY`) ; sha256 relevé, non prédit | Haute (Y3, dépôt figé) |
| HX2 | `hote` : 15 lignes OK au lieu de 14, dont 4 pour vault 9.7 au lieu de 3 ; aucune KO ; HB1 à HB8 inchangées | Moyenne-haute (HB6 et HB7 restent les points faibles) |
| EX1 | `essais` : la sonde affiche 4 baseurl de vault 9.7 (BaseOS, AppStream, CRB, `extras`) parmi les « dépôt de mock », et « mirrorlist restants pour BaseOS, AppStream, CRB et extras : 0 » ; les mirrorlist des dépôts inactifs restent listés | Moyenne (format réel de `--debug-config` non lu) |
| EX2 | `verrou` : aucune URL sous `/extras/` dans le verrou, donc aucun paquet du buildroot venu d'`extras`. Les journaux d'`essais` ne sont pas retenus comme lecture : qu'ils donnent le dépôt de chaque paquet n'est pas vérifié | Moyenne (Y5 et Y6 par nom ; une dépendance indirecte n'est pas exclue) |

Suite, chaque point sur accord nommé : appliquer le correctif (une ligne datée à l'en-tête de `s1.sh`) et le commiter ; `amorce`,
`hote` de nouveau (HB1 à HB8, HX1, HX2), `racine` (lire `rpm` dans sa liste), `image`, `essais`, `verrou`.

## Correctif `extras` appliqué au dépôt (note du 2026-11-16, écrite à 2026-11-16T23:28:57Z ; rien n'est réécrit)

Question : « J'applique le correctif extras et je le commite ? ». Réponse : « Oui, applique-le ».

- `git apply` de [`s1-extras.patch`](../s1-extras.patch) le 16/11/2026 à 23:28:10 UTC (`date -u` de la commande), sur `50aed81`.
  `s1.sh` passe de `710f3904…` à `ad9febc5…`, le sha256 de la copie bancée. `git apply -R --check` passe juste après.
- **Banc `extras` repassé sur le fichier du dépôt avant la ligne datée**, le 16/11/2026 de 23:28:16 à 23:28:18 UTC : 27 OK, 0 KO
  ([journal](s1-extras-banc-applique.log)). Hors des deux lignes d'en-tête et du bilan, son journal est identique à celui de la copie.
  - Le banc lit le `s1.sh` d'avant dans un dossier de base sous `~/.cache`, extrait de `50aed81` : c'est la ligne « s1.sh du
    dépôt `710f3904…` » de son en-tête. Le fichier du dépôt y figure comme « copie modifiée `ad9febc5…` ».
  - python3 y est en 3.13.12, contre 3.15.2 au banc de la copie : le banc a été lancé depuis la racine du dépôt, et non depuis le
    scratchpad, et le shim de mise choisit la version selon le dossier (vérifié après coup). Les deux passages donnent les
    mêmes lignes.
- Une ligne datée est ensuite ajoutée à l'en-tête de `s1.sh`, sans rien réécrire. `s1.sh` vaut désormais `ad16fc99…`. Le correctif
  ne s'applique donc plus dans un sens ni dans l'autre ; son fichier reste comme trace.
- **Sur le fichier final** :
  - `bash -n` passe ;
  - shellcheck 0.11.0 ne relève aucun avertissement et compte toujours 13 remarques ;
  - le banc N3/N4, le 16/11/2026 de 23:28:27 à 23:28:28 UTC, donne 35 OK, 0 KO ([journal](s1-extras-banc-n34-applique.log)).
- Rien n'est lancé : HX1, HX2, EX1 et EX2 attendent `hote`, `essais` et `verrou`.

Suite, chaque point sur accord nommé : push ; `amorce`, `hote` de nouveau (HB1 à HB8, HX1, HX2), `racine` (lire `rpm` dans sa
liste), `image`, `essais`, `verrou`.

## Étape `amorce` : prédictions (note du 2026-11-16, écrite à 2026-11-16T23:35:31Z, avant tout passage ; rien n'est réécrit)

L'étape copie par digest deux manifestes amd64 de `quay.io/rockylinux/rockylinux` dans Zot, sous `amont/rockylinux/rockylinux` :
`ed654c69…` (9.8, image de `racine`) et `ee90dc0e…` (9.7, bootstrap de mock). Elle relit ensuite chaque digest dans Zot. Ces
écritures sont **définitives** : Zot n'autorise pas la suppression. Journal prévu : `s1-amorce.log` (préfixe `s1` par défaut ; aucun
journal de ce nom n'existe encore).

**État vérifié par le script qui écrit cette note, à son écriture** (assertions, lecture seule) :
- Le cache OCI local `…/08/telechargements/oci/amont/rockylinux` n'existe pas. `miroir` lira donc chaque manifeste et ses blobs sur
  quay.io une première fois, puis les enverra à Zot depuis ce cache.
- `s1-amorce.log` n'existe pas encore. `s1.sh` crée `$T` (ligne 75) avant que l'étape y écrive son fichier d'authentification.
- `prealables` a relevé 5551 Mo libres pour Zot ([journal](s1-prealables.log)). La taille des deux images n'a pas été relevée.

**Signatures** : le 05/11, `cosign tree` n'a trouvé aucune entrée sur les tags `9.7` et `9.8`, et leurs index n'avaient aucun
manifeste d'attestation ([sante-signatures.log](sante-signatures.log)). Ce relevé ne vaut que pour cosign, sur les tags ; il n'a été
refait ni depuis, ni par digest, et `amorce` ne relit pas les signatures. L'intégrité de la copie tient au digest épinglé : d'après le
commentaire de `miroir` ([`commun.sh`](../../08-trust-plane/commun.sh)), oras relit et vérifie chaque blob par digest à chaque copie.

**En cas d'échec** : un KO après la première copie laisse dans Zot une écriture définitive. Un rejeu sous le même préfixe écraserait
`s1-amorce.log` ; il se fera donc sous un autre préfixe, ou l'écrasement sera noté.

| | Prédiction | Confiance |
|---|---|---|
| AM1 | Deux lignes « copié dans Zot : …/amont/rockylinux/rockylinux@sha256:… (cache telechargements/oci/amont/rockylinux/rockylinux) », d'abord `ed654c69…`, puis `ee90dc0e…` | Moyenne-haute (quay.io garde-t-il les deux manifestes par digest ? non relu depuis le 05/11) |
| AM2 | Deux lignes OK, « digest de l'amorce 9.8 dans Zot » et « digest du bootstrap 9.7 dans Zot », chacune égale au digest épinglé ; aucune KO | Haute si AM1 tient (copie par digest, manifeste recopié tel quel) |
| AM3 | Zot ne coupe pas l'envoi (pas de « i/o timeout ») : il reçoit les blobs du cache local | Moyenne-haute (même chemin `miroir` que les deux passages d'amorce de la 06, le 13/11 à 14:17:05 et 14:52:30 UTC : [s1r-amorce.log](../../06-deb-sbuild/resultats/s1r-amorce.log), [s1-amorce.log](../../06-deb-sbuild/resultats/s1-amorce.log)) |
| AM4 | L'étape dure moins de 5 minutes, de la ligne « 05 S1 amorce » à « 05 S1 amorce fait » de `chrono.tsv` | Faible (débit de quay.io non mesuré) |

**Lectures amont indépendantes, non modifiées** : [`sante.sh`](../sante.sh) (ligne 125) et [`releve-amont.sh`](../releve-amont.sh)
(lignes 32 et 58) ne listent que BaseOS, AppStream et CRB. Ce sont des relevés passés du 05/11, dont le rejeu n'est pas prévu ; le
correctif `extras` ne les touche pas.

Suite, chaque point sur accord nommé : `amorce` ; `hote` de nouveau sous un nouveau préfixe (HB1 à HB8, HX1, HX2), `racine` (lire
`rpm` dans sa liste), `image`, `essais`, `verrou`.

## Étape `amorce` : résultat (note du 2026-11-16, écrite à 2026-11-16T23:39:29Z ; rien n'est réécrit)

Question : « Je lance amorce ? ». Réponse : « Oui, lance amorce ». Lancée le 16/11/2026 à 23:37:36 UTC, finie à 23:37:48 UTC
(`date -u` autour de la commande, et `chrono.tsv`). Journal : [`s1-amorce.log`](s1-amorce.log), sha256 `8703ac81…`.

| | Mesure | Verdict |
|---|---|---|
| AM1 | Deux lignes « copié dans Zot », `ed654c69…` puis `ee90dc0e…`, cache `telechargements/oci/amont/rockylinux/rockylinux` | Tenue |
| AM2 | « digest de l'amorce 9.8 dans Zot » et « digest du bootstrap 9.7 dans Zot » : OK, égaux aux digests épinglés ; aucune KO | Tenue |
| AM3 | Aucun « i/o timeout » ; l'étape va au bout | Tenue |
| AM4 | 12 s entre « 05 S1 amorce » et « 05 S1 amorce fait » | Tenue |

- **Code de retour non affiché** : la commande lisait `PIPESTATUS` sous zsh, où cette variable n'existe pas. Le code se déduit
  de la structure du script : `s1.sh` tourne sous `set -euo pipefail`, et `lancer` n'écrit la ligne « fait » de `chrono.tsv` qu'après
  le pipeline de l'étape. Un KO aurait donc arrêté le script avant cette ligne, qui est présente.
- **Taille** : le cache OCI local occupe 167M selon `du -sh`, lu juste après le passage. Cette mesure n'est pas archivée (ni
  dans le journal ni dans les assertions de ce script). La place prise dans Zot n'a pas été relevée.
- **Signatures** : non relues par l'étape, comme prévu ; aucun nouveau relevé depuis le 05/11.
- Écritures définitives faites dans Zot : `amont/rockylinux/rockylinux@sha256:ed654c69…` et `@sha256:ee90dc0e…`.

Suite, chaque point sur accord nommé : `hote` de nouveau sous un nouveau préfixe (HB1 à HB8, HX1, HX2), `racine` (lire `rpm`
dans sa liste), `image`, `essais`, `verrou`.

## Troisième passage de `hote` : résultat (note du 2026-11-17, écrite à 2026-11-17T08:33:09Z ; rien n'est réécrit)

Question : « Je lance hote (PREFIXE=s1-3) ? ». Réponse : « Oui, lance hote ». Lancé le 17/11/2026 de 08:30:27 à 08:30:42 UTC
(`date -u` autour de la commande, et `chrono.tsv`), HEAD `d6d191f`, `s1.sh` `ad16fc99…`. Commande
`PREFIXE=s1-3 DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh hote`, dans `bash -c` : 15 lignes OK, aucune KO. Journal :
[`s1-3-hote.log`](s1-3-hote.log), sha256 `5f05bd72…`. **Code de retour 0**, lu par `PIPESTATUS` à l'écran, non archivé (le journal
ne le contient pas) ; il est corroboré par la ligne « 05 S1 hote fait » de `chrono.tsv`, que `lancer` n'écrit qu'après l'étape.

| | Mesure | Verdict |
|---|---|---|
| HB1 | `sample-app-1.0.0.tar.gz` et `sample-app.spec` : OK | Tenue |
| HB2 | Clés aux sha256 `3a66e521…` (Rocky) et `fcf0eab4…` (EPEL) ; empreinte de Rocky égale à `FP_ROCKY` ; `FF8AD134…` présente sur la page d'EPEL | Tenue |
| HB3 | vault 9.7 BaseOS, AppStream, CRB signés par la clé de Rocky ; repomd.xml `fa6d5054…`, `06f01d40…`, `3936113e…` | Tenue |
| HB4 | pub 9.8 BaseOS et AppStream signés par la clé de Rocky ; repomd.xml `abac8b17…` et `a3ca4230…` | Tenue |
| HB5 | EPEL 9 : `repomd.xml.asc` absent ; repomd.xml `8190707a…`, primary `b81a3880…` contrôlé par repomd | Tenue |
| HB6 | podman 5.8.2-8.el9_8 `561d6e4d…`, skopeo 1.22.2-9.el9_8 `c6cca7fe…`, dans AppStream 9.8 | Tenue |
| HB7 | mock 6.9-1.el9 `a5043350…`, mock-core-configs 45.2-1.el9 `84f19c05…`, dans EPEL 9 | Tenue |
| HB8 | Code 0, aucune KO | Tenue |
| HX1 | vault 9.7 `extras` : repomd.xml signé par `FP_ROCKY` ; sha256 `54ec0c53…` | Tenue |
| HX2 | 15 lignes OK, dont 4 pour vault 9.7 ; aucune KO ; HB1 à HB8 tenues | Tenue |

- **Écart avec le passage du 16/11** ([`s1-2-hote.log`](s1-2-hote.log)) : l'en-tête, les deux lignes d'EPEL (repomd.xml
  `73fd2581…` → `8190707a…`, primary `ccc17999…` → `b81a3880…`), et les deux lignes d'`extras`, ajoutées par le correctif. Toutes
  les autres lignes sont égales.
- **Non prédit** : le repomd.xml d'`extras` (`54ec0c53…`) est égal à celui du relevé `releve7` du 12/11/2026 à 17:54:37 UTC
  ([m2-releve7.log](m2-releve7.log), ligne 37). Les repomd.xml de pub 9.8 (`abac8b17…`, `a3ca4230…`) sont égaux à ceux des relevés
  du 12/11 ([`s1-hote.log`](s1-hote.log)) et du 16/11 : trois relevés égaux, rien n'est dit de l'entre-deux.
- **EPEL 9** : son repomd.xml a une somme différente à chacun des trois relevés : `454b0238…` le 12/11, `73fd2581…` le 16/11,
  `8190707a…` le 17/11.
- **Pour `racine`** (lecture du code, non exécuté) : `depot_hote` écrit dans `$T`, hors du dépôt, `<dépôt>.repomd.sha256` et
  `<dépôt>.primary.xml`. Les six fichiers de baseos98, appstream98 et epel9 sont non vides après ce passage, et les trois sommes valent
  celles du journal (vérifié par le script qui écrit cette note). `racine` compare, pour ces trois dépôts, le repomd lu par dnf dans le pod à ces sommes
  (`attendu`, lignes 324 à 326 de `s1.sh`, sous `set -euo pipefail`). Si pub 9.8 ou EPEL changent avant `racine`, ce contrôle
  devrait donc s'arrêter en KO, et `hote` serait à rejouer sous un préfixe neuf.
- Rien n'a touché le cluster ni Zot.

Suite, chaque point sur accord nommé : `racine` (lire `rpm` dans sa liste), `image`, `essais`, `verrou`.

## Étape `racine` : prédictions (note du 2026-11-17, écrite à 2026-11-17T08:40:44Z, avant tout passage ; rien n'est réécrit)

Elles complètent P5 à P7 (12/11), sans les remplacer. Commande prévue : `DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh racine`,
préfixe par défaut `s1`, donc journal `s1-racine.log` (il n'existe pas encore). Elle tourne en arrière-plan, sous `bash -c`, avec
`date -u` avant et après, et `PIPESTATUS`. Effets : un pod Kata privilégié root, `s1-05-racine`, dans `builds`. Une archive est
rapatriée sous `~/.cache`. Rien n'est écrit dans Zot.

**Ce que le code fait et ne contrôle pas** (lecture de `s1.sh` `ad16fc99…`, assertions du script qui écrit cette note) :
- Dans le pod, le script `RACINE` tourne sous `set -u` seulement. `dans` affiche le code de l'exec sans s'arrêter. Seules quatre
  choses arrêtent l'étape sur l'hôte : le pod non prêt ; un des trois `attendu` sur les repomd ; l'absence de la ligne d'archive ;
  un sha256 de l'archive rapatriée différent.
- `controle_rpms` ne bloque pas (`|| echo "ÉCART…"`). Le compte de `rpm -K` et les lignes « installé : … absent » ne sont
  contrôlés par rien. **Un code 0 et la ligne « fait » de `chrono.tsv` ne prouvent donc pas P5** : chaque verdict se lira sur les
  lignes du journal nommées ci-dessous.
- Le code de retour de `tar -cf` n'est pas lu. Si le tmpfs de 4 Gio se remplissait, une archive tronquée serait hachée, rapatriée,
  et son sha256 tiendrait. Contrôle prévu pour les notes du résultat, sur l'hôte : `tar -tf` sur `$T/racine.tar`, désigné par son
  nom, code 0 et nombre d'entrées. Il ne bloque pas `racine`, mais il conditionne `image`.
- Les repomd sont comparés **après** l'installation et l'archive. Si un `attendu` échoue, l'étape sort sans `pod_retirer` :
  `s1-05-racine` reste en place (`sleep 10800`, 2 CPU et 6 Gio demandés) jusqu'au `pod_demarrer` suivant, qui le supprime d'abord.
- L'occupation maximale de `/w` n'est pas mesurée par le script. Aucune prédiction n'est faite sur elle.

**Premières mesures réelles de cette étape** (jusqu'ici, dry-run ou pod témoin seulement) : admission réelle du pod Kata
privilégié sous le label `prefetch-rpm` ; tirage de l'amorce 9.8 depuis Zot par digest ; dnf joignant dl.rockylinux.org et
dl.fedoraproject.org par la sortie rpm ; `repo_gpgcheck=1` avec la clé de Rocky livrée, sous `--installroot`.

**Dépendances lues dans les primary vérifiés par `hote`** (fichiers de `$T` du 17/11 à 08:30:42 UTC, sans lecture réseau ;
assertions du script) :
- mock requiert directement `systemd-container`, ce qui lève le doute de P5.
- Il requiert aussi `python3-rpm`, qui requiert `rpm-libs(x86-64)`, qui requiert `rpm`, et `createrepo_c`, qui requiert `rpm`.
- BaseOS 9.8 n'offre qu'une version de `rpm` : 4.16.1.3-40.el9.

Il s'agit de métadonnées, pas d'une résolution par dnf.

| | Prédiction | Confiance |
|---|---|---|
| RC1 | « ### s1-05-racine (kata, uid 0, privilégié, label tekton.dev/task=prefetch-rpm) : prêt » | Haute (dry-run serveur du 16/11 ; précédent `s1-racine` de la 06, le 13/11) |
| RC2 | « makecache : rc 0 », et trois lignes « repomd <dépôt> : sha256 » non vides | Moyenne (`repo_gpgcheck` sous `--installroot`, avec une clé en `file://`, non lu). En cas d'échec, le symptôme serait une somme vide, puis un KO de l'`attendu` |
| RC3 | Deux OK « repomd baseos98 » et « repomd appstream98 … = repomd vérifié sur l'hôte » | Moyenne-haute (trois relevés égaux, les 12, 16 et 17/11 ; rien n'est dit de l'entre-deux) |
| RC4 | OK « repomd epel9 … = repomd vérifié sur l'hôte » | **Faible** (trois relevés, trois sommes : `454b0238…`, `73fd2581…`, `8190707a…`) |
| RC5 | « installation : rc 0 ». Cinq lignes « installé : » sans « absent » : mock-0:6.9-1.el9, mock-core-configs-0:45.2-1.el9, podman-6:5.8.2-8.el9_8, skopeo-2:1.22.2-9.el9_8, systemd-container | Moyenne-haute (épinglages relus par `hote` à 08:30) |
| RC6 | « OK   sha256 des rpm conformes aux primary vérifiés : N sur N », sans ligne « écart », et « rpm -K : N OK sur N », avec le même N | Haute si RC5 tient |
| RC7 | Une ligne « rpm baseos98 rpm-4.16.1.3-40.el9.x86_64.rpm … » : `rpm`, donc `rpm2cpio`, est dans la racine (précondition de N3 et N4) | Haute (lu dans les primary, ci-dessus) |
| RC8 | P6 : la ligne « caches : » ne nomme que `/w/racine/w/cache` | Faible, comme P6 |
| RC9 | P7 : « archive racine : » entre 400 et 900 Mo ; OK « archive racine rapatriée » ; puis `tar -tf` sur l'hôte, code 0 | Faible pour la taille ; moyenne-haute pour le rapatriement |

**En cas de KO sur un repomd** (RC3 ou RC4), chaque point se fait sur son accord : `hote` sous un préfixe neuf, puis `racine` sous un
préfixe neuf, pour ne pas écraser `s1-racine.log`. Le pod resté en place est supprimé par le `pod_demarrer` suivant.

Suite, chaque point sur accord nommé : `racine`, `image`, `essais`, `verrou`.

### Correctif des prédictions de `racine` (note du 2026-11-17, écrite à 2026-11-17T08:43:12Z, avant tout passage ; rien n'est réécrit)

Deux phrases de la section précédente sont corrigées. Les deux erreurs ont été relevées par le conseiller, à la relecture qui a
suivi le commit.

- **RC8 ne pouvait pas tenir telle qu'écrite.** `RACINE` crée `/w/cache` (`mkdir -p /w/aucun /w/racine /w/cache`) avant la ligne
  « caches : », qui ne teste que l'existence du dossier. `/w/cache` y figure donc dans tous les cas.
  - RC8 devient : P6 est soutenue si `/w/racine/w/cache` figure dans la ligne « caches : ».
  - Le journal ne dira pas si `/w/cache` est resté vide : les lignes « rpm <dépôt> … » ne donnent pas de chemin.
- **« Seules quatre choses arrêtent l'étape » est trop fort.** Sous `set -euo pipefail`, d'autres arrêts sont lus dans le code :
  - la garde d'entrée sur les fichiers de `$T` (« lancer d'abord l'étape hote ») ;
  - `kubectl delete` et `kubectl create` dans `pod_demarrer`, dont un refus réel d'admission (c'est la mesure de RC1) ;
  - chaque `livrer` ;
  - le `kubectl exec … cat /w/racine.tar` du rapatriement.

  Cette liste vient de la lecture du code ; elle n'est pas donnée comme exhaustive. La conclusion ne change pas : un code 0 ne
  prouve pas P5.
- **Le pod reste aussi en place** quand le rapatriement échoue ou que l'`attendu` sur l'archive échoue. Un `exec` qui échoue
  n'écrit pas de ligne « KO », seulement l'erreur de kubectl.
- **Lecture du journal :** les lignes venues du pod y sont décalées de cinq espaces par `dans`. La ligne « (code de l'exec : N) »
  sera relevée dans les notes du résultat.

## Étape `racine` : résultat (note du 2026-11-17, écrite à 2026-11-17T10:24:24Z ; rien n'est réécrit)

Question : « Je lance racine ? ». Réponse : « Oui, lance racine ». Commande : `DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh
racine </dev/null`, sur `942f72d`, en arrière-plan, sous `bash -c`. Elle a tourné du 17/11/2026 08:44:02 à 10:21:00 UTC (`date -u`
autour de la commande, et `chrono.tsv`). Journal : [`s1-racine.log`](s1-racine.log), sha256 `e79aa829…`, 225 lignes, aucune KO.
Le code de retour 0 a été lu par `PIPESTATUS` dans un fichier du scratchpad : il n'est pas archivé. La ligne « fait » de `chrono.tsv`
le corrobore. La sortie à l'écran est égale au journal.

| | Mesure (lignes du journal) | Verdict |
|---|---|---|
| RC1 | « ### s1-05-racine (kata, uid 0, privilégié, label tekton.dev/task=prefetch-rpm) : prêt » | Tenue |
| RC2 | « makecache : rc 0 en 56 s » ; trois sommes de repomd non vides | Tenue. Le journal montre seulement `makecache` rc 0 avec `repo_gpgcheck=1` configuré : `makecache.log` est perdu avec le pod |
| RC3 | OK pour baseos98 (`abac8b17…`) et appstream98 (`a3ca4230…`) | Tenue |
| RC4 | OK pour epel9 (`8190707a…`), le même repomd qu'à `hote` 08:30:27 | Tenue, malgré une confiance faible |
| RC5 | « installation : rc 0 en 5694 s » ; cinq lignes « installé : », aucune « absent » ; systemd-container `252-67.el9_8.6.rocky.0.1` | Tenue |
| RC6 | « OK   sha256 des rpm conformes aux primary vérifiés : 199 sur 199 » (baseos98 169, appstream98 21, epel9 9), sans écart ; « rpm -K : 199 OK sur 199 » | Tenue |
| RC7 | « rpm baseos98 rpm-4.16.1.3-40.el9.x86_64.rpm … » ; `./usr/bin/rpm` et `./usr/bin/rpm2cpio` dans l'archive | Tenue : la précondition de N3 et N4 est remplie |
| RC8 | « caches : /w/cache /w/racine/w/cache » | P6 soutenue (forme corrigée). Le journal ne dit pas si `/w/cache` est resté vide |
| RC9 / P7 | 361 758 720 octets (moins de 400 Mo comme de 400 Mio) ; OK « archive racine rapatriée », même sha256 `d7433a05…` | **Taille non tenue** (sous la fourchette) ; rapatriement tenu |

P5 est tenue sur ces lignes : les quatre paquets sont installés, avec leurs dépendances, et systemd-container est tiré.

**Relecture de l'archive sur l'hôte** ([`s1-racine-tar.log`](s1-racine-tar.log), le 17/11/2026 à 10:23:32 UTC) : `tar -tf` rc 0,
13 341 entrées. La taille est un multiple de 10 240 et les 1 024 derniers octets sont nuls. C'est compatible avec une archive close,
sans le prouver. Le sha256 est le même. `mock`, `podman`, `rpm` et `rpm2cpio` sont présents sous `./usr/bin/`.
- Deux passages précédents, à 10:21:13 puis 10:21:27 UTC, ont donné les mêmes nombres sans les deux contrôles de fin. Le premier
  n'a été qu'affiché, et le second a été écrasé : ni l'un ni l'autre n'est archivé.

**Non prédit** :
- **L'installation a duré 5694 s**, soit environ 1 h 35, sur 1 h 37 d'étape. La cause est inconnue : `install.log` a disparu avec le
  pod.
- **201 paquets sont installés pour 199 rpm téléchargés.** L'écart n'est pas expliqué ; `nevra.txt` n'a pas été rapatrié.
- Invité Kata : noyau 6.18.56, 3 vCPU, 6 119 664 kB ; dnf 4.14.0 ; rpm 4.16.1.3.

**Lectures hors du script pendant le passage** (après la question « ça en est où ? », vers 10:20 UTC) : un `kubectl get pod` et
deux `kubectl exec` en lecture seule dans `s1-05-racine`, sans rien modifier. Valeurs vues seulement à l'écran, **non archivées** :
- `/w` était un tmpfs de 3,0G, et non de 4 Gio ;
- 643M occupés avant l'archive ;
- `/w/cache` vide ;
- `install.log` finissait par « Complete! ».

**À traiter avant `essais`** (ne concerne pas `image`, qui ne lance pas de pod) :
- **P11** suppose 4 Gio de tmpfs (`TMPFS=4Gi`). La valeur vue à l'écran, non archivée, était de 3,0G. Une étape devra la mesurer
  avant que P11 soit corrigée.
- **Durée de vie des pods** : chaque pod attend `sleep 10800`. `racine` en a pris 5818 s, de 08:44:02 à 10:21:00. Si mock télécharge
  au même rythme, le pod d'`essais` peut s'arrêter en plein travail. C'est une décision du propriétaire.

Rien n'a été écrit dans Zot. Le pod est supprimé. L'archive est sous `~/.cache`.

Suite, chaque point sur accord nommé : `image`, `essais`, `verrou`.

## Étape `image` : prédictions (note du 2026-11-17, écrite à 2026-11-17T10:41:00Z, avant tout passage ; rien n'est réécrit)

L'étape assemble l'image d'essai sans rien exécuter. Elle écrit deux configurations de mock et `storage.conf` dans une couche, puis
`crane append` empile `racine.tar` et cette couche sur une base vide OCI, et `crane mutate` pose la plateforme et `Env`. Le tag est
`essais-05/mock-rocky9:s1` et le digest va dans `$T/image.digest`, qu'`essais` et `verrou` lisent. Ce qui est écrit dans Zot
ne peut pas être supprimé ; seul le tag peut être réécrit. L'étape ne lance aucun pod. Journal prévu : `s1-image.log`, absent à l'écriture de cette note.

**Ce que le code ne contrôle pas** (lecture de [`s1.sh`](../s1.sh), lignes 363 à 385) :
- La garde ne teste que la présence de `$T/racine.tar` (`-s`), pas son sha256. Le script qui écrit cette note l'a recalculé :
  `d7433a05…`, égal à celui de `racine`.
- `$T/docker/config.json`, écrit par `amorce`, existe : l'étape ne refait pas l'authentification et l'envoi se fait sous le compte
  écrit par `amorce` (`auth_zot`, compte `poc-ecriture` par défaut, lecture de code).
- Le journal ne montre ni la plateforme ni `Env`.

**Droit d'écriture**, lecture de code seulement : dans [`zot.json`](../../08-trust-plane/stockage/zot.json) du dépôt, `**` donne
`read`, `create` et `update` à `poc-ecriture`. Les autres motifs (`builds/**`, `builds/fermetures/**`, `builds/scan/**`,
`vulndb/**`, `horodatage/**`) ne couvrent pas `essais-05/`. La configuration déployée n'est pas relue. Le dépôt
`essais-05/mock-rocky9` n'existait pas le 17/11/2026 à 10:32:01 UTC ([relevé](s1-image-zot-avant.log), sortie brute : `date -u`,
`crane ls` en `NAME_UNKNOWN`, son code 1, le nombre de lignes de `crane catalog`, `date -u`).

**Banc local** ([journal](s1-image-essai-local.log), [script](s1-image-banc.sh), [extraction](s1-image-banc-config.py)), le 17/11/2026
de 10:36:14 à 10:36:21 UTC, sans Zot ni cluster :
- la couche de configuration est rejouée deux fois à partir du texte d'`etape_image` ; même sha256 `f5710d47…`, 10 240 octets ;
- `racine.tar` vaut `d7433a05…` ;
- `rocky-9.tpl` de la racine est égal à celui de l'archive amont de mock 6.9-1 gardée par M2 (`28c04ee8…`) ;
- les commandes `crane append` puis `crane mutate` d'`etape_image`, contre un `crane registry serve` en loopback (stockage sous
  `~/.cache`), donnent les valeurs reprises ci-dessous.

Les noms des fichiers archivés diffèrent de ceux du scratchpad : `banc-image.sh` devient `s1-image-banc.sh`, et `banc-config.py`
devient `s1-image-banc-config.py`. Le contenu n'est pas modifié ; dans le journal seul, `$HOME` est remplacé par `~`.

**Précédent de la 06** : mêmes commandes crane ([`s1.sh` de la 06](../../06-deb-sbuild/s1.sh), lignes 225 à 227). Deux passages à
trois jours d'écart ont donné le même digest d'image `d8041f9c…` ([s1b-image.log](../../06-deb-sbuild/resultats/s1b-image.log),
[s1r-image.log](../../06-deb-sbuild/resultats/s1r-image.log)). L'étape a duré 25, 19 et 25 s (`chrono.tsv` de la 06).

| | Prédiction | Confiance |
|---|---|---|
| IM1 | Le journal compte six lignes : l'en-tête ; « OK   configuration prête : racine et bootstrap_image_ready changés, rien d'autre : 4 » ; « configuration de mock : sha256 a8e5f2bc8d2b4a54f6b5fb7fea62ebd55628e3499abd8608014e38285bc6ea31 » ; deux lignes « couche » ; « image d'essai : sc-stockage.poc.test:5000/essais-05/mock-rocky9@sha256:… » | Haute pour les lignes 2 et 3 (banc) ; moyenne-haute pour le reste, qui suppose IM2 |
| IM2 | `crane append` et `crane mutate` passent contre Zot, sans « i/o timeout » ni refus d'accès | Moyenne-haute : précédent de la 06 (couches de 132 253 685 et 348 928 080 octets) ; droit lu dans le code, pas dans la configuration déployée |
| IM3 | Couches, dans cet ordre : `sha256:e48fc4d689daa5ec7af47350d996f93d76a138ff7267aed6972feefe3e4526bd` 140 611 406 octets (racine), puis `sha256:fd00cdb1ac39ed07d03836b05bd7c24cf435e68a2b29d63403e5dfc4610ac157` 825 octets (configuration) | Haute : même crane 0.20.6, mêmes entrées ; couche de la 06 identique d'un passage à l'autre |
| IM4 | Digest de l'image : `sha256:99790c13673de2e4b87e72207b4b29eff7ef95dc436d79d25c08e627027f6771`, le même que le banc ; `$T/image.digest` le contient | Moyenne-haute : la 06 montre un digest stable ; Zot est supposé garder le manifeste tel quel |
| IM5 | Moins de 60 s entre « 05 S1 image » et « 05 S1 image fait » dans `chrono.tsv` | Moyenne : 7 s au banc en loopback, 19 à 25 s pour la 06 vers Zot |

**Relecture sur l'hôte annoncée avant le passage**, archivée ensuite dans `s1-image-relecture.log`, en lecture seule :
- `crane digest` du tag `:s1` égal à IM4 ;
- `crane config` : `os` linux, `architecture` amd64, `Env` exactement `PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root`,
  `created` à `0001-01-01T00:00:00Z`, deux entrées d'`history`, comme au banc ;
- `crane manifest` : types de médias OCI, comme au banc ;
- contenu de `$T/image.digest`.

**En cas d'échec** :
- Si `append` échoue, des blobs peuvent rester dans Zot, sans tag.
- Si `append` passe et que `mutate` échoue, il reste un tag `:s1` sans les ajouts de `mutate`. Ce que `append` seul pose comme
  plateforme n'a pas été lu. Le dépôt ne peut pas être supprimé, mais le tag peut être réécrit.
- Dans les deux cas, l'étape s'arrête (`exit 1`) avant `image.digest`. Un rejeu sous le même préfixe réécrirait le tag (droit
  `update`) et écraserait `s1-image.log`. Il se fera donc sous un autre préfixe, ou l'écrasement sera noté.

**Place** : le banc occupe 135 Mo sous `~/.cache`. `prealables` a relevé 5551 Mo libres pour Zot ; l'étape ne mesure pas la place
prise dans Zot.

**Effort** : relevé refait par la même méthode, [`temps-05-1211.log`](temps-05-1211.log). La méthode lit la date d'auteur : le même
calcul borné à `05ac074` redonne 46 commits et 4,93 h. Jusqu'à `b70f384`, on compte 70 commits et 7,97 h de commits, pour 2,5 pw
estimées. Le seuil de décision est à 5 pw. Le temps des passages eux-mêmes n'est pas compté par cette méthode.

Suite, chaque point sur accord nommé : `image`, puis `essais` (avant lui : taille du tmpfs, durée de vie des pods), puis `verrou`.

## Étape `image` : résultat (note du 2026-11-17, écrite à 2026-11-17T10:45:04Z ; rien n'est réécrit)

Question : « Je lance image ? ». Réponse : « Oui, lance image ». Commande : `env -u PREFIXE DISTRO=rke2 mise exec --
poc/bricks/05-rpm-mock/s1.sh image </dev/null`, sur `02e51dd`, en arrière-plan, sous `bash -c`. Elle a tourné le 17/11/2026, de
10:43:08 à 10:43:19 UTC (`date -u` autour de la commande, et `chrono.tsv`). Journal : [`s1-image.log`](s1-image.log), sha256
`53edf4bf…`, six lignes, égal à la sortie écrite dans un fichier du scratchpad. Le code 0 a été lu par `PIPESTATUS` dans ce même
scratchpad, non archivé ; la ligne « fait » de `chrono.tsv` le corrobore.

| | Mesure | Verdict |
|---|---|---|
| IM1 | Six lignes ; « OK   configuration prête … : 4 » ; « configuration de mock : sha256 a8e5f2bc… » ; deux lignes « couche » ; « image d'essai : sc-stockage.poc.test:5000/essais-05/mock-rocky9@sha256:99790c13… » | Tenue |
| IM2 | Le journal ne contient que les six lignes attendues, dont les lignes « couche » et « image d'essai » écrites après `append` et `mutate` ; la ligne « fait » de `chrono.tsv` est présente | Tenue |
| IM3 | `e48fc4d6…` 140 611 406 octets, puis `fd00cdb1…` 825 octets, dans cet ordre | Tenue : digests et tailles égaux au banc |
| IM4 | Digest `99790c13…`, égal au banc ; `$T/image.digest` le contient (relecture) | Tenue |
| IM5 | 11 s entre « 05 S1 image » et « 05 S1 image fait » | Tenue |

**Relecture sur l'hôte**, annoncée avant le passage ([journal](s1-image-relecture.log), [script](s1-image-relecture.sh)), le
17/11/2026 de 10:43:30 à 10:43:32 UTC, en lecture seule, avec le fichier d'authentification d'`amorce` désigné par son nom :
- le tag `:s1` résout en `99790c13…`, et `$T/image.digest` contient la même valeur ;
- le manifeste est OCI, et sa config `d3002ab0…` est égale à celle du banc ;
- config : `os` linux, `architecture` amd64, `Env` `PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root`, `created` à
  `0001-01-01T00:00:00Z`, deux entrées d'`history`, comme au banc ;
- `:s1` est le seul tag du dépôt.

Le banc en loopback (10:36 UTC) et Zot (10:43 UTC) donnent le même digest d'image : deux registres, sept minutes d'écart, le même
crane 0.20.6 et la même `racine.tar`. Rien d'autre n'est mesuré.

Écrit dans Zot : dépôt `essais-05/mock-rocky9`, tag `:s1`. Le dépôt et ses blobs ne peuvent pas être supprimés ; le tag peut être
réécrit. Aucun pod lancé. La place prise dans Zot n'a pas été relevée.

Suite, chaque point sur accord nommé : avant `essais`, la taille du tmpfs (P11) et la durée de vie des pods (`sleep 10800`) ;
puis `essais`, puis `verrou`.

## Correctif durée de vie et place, préparé à sec (note du 2026-11-17, écrite à 2026-11-17T11:02:05Z ; rien n'est réécrit ; NON APPLIQUÉ)

Deux décisions du propriétaire, prises le 17/11/2026 :
- Question : « Je passe le sleep des pods de 10800 à 43200 s (12 h) ? ». Réponse : « Oui, 12 h ».
- Question : « J'ajoute aussi la ligne df -k /w en tête de SONDE, dans ce même correctif ? ». Réponse : « Oui, ajoute df ».

**Correctif** : [`../s1-duree.patch`](../s1-duree.patch), une ligne retirée et six ajoutées. Copie modifiée de `s1.sh` :
sha256 `a61fa50e…`, écrite par [`s1-duree-modifier.py`](s1-duree-modifier.py) à partir de `ad16fc99…`.
- `pod_spec` : `command: ["sleep", "43200"]` au lieu de `["sleep", "10800"]`, pour les pods de `racine`, `essais` et `verrou`.
- `SONDE`, juste après la ligne des montages : `df -k /w`, qui affiche « capacité de /w : … kB ; utilisés : … kB ».
- Quatre lignes d'en-tête, marquées NON APPLIQUÉ, citent les deux décisions.

**Pourquoi la durée de vie**
- Le pod est en `restartPolicy: "Never"` : c'est lu dans `s1.sh` et cela figure dans le JSON du banc. À la fin du `sleep`, le
  conteneur s'arrête sans être relancé, et le tmpfs `/w` de l'invité Kata disparaît avec lui. C'est le comportement attendu de
  Kubernetes, non mesuré ici.
- Seul rythme mesuré : `racine` a installé 199 rpm en 5694 s ([`s1-racine.log`](s1-racine.log)), soit 28,6 s par rpm, cause
  inconnue. À ce rythme, 10 800 s couvrent environ 377 rpm, et 43 200 s environ 1 509. Que mock suive ce rythme est une
  hypothèse. Le nombre de paquets du buildroot n'est mesuré nulle part.
- Une borne trop longue ne coûte que si le script est interrompu. Le pod resté en place demande alors 6 Gi, plus 320 Mi
  d'overhead de la RuntimeClass `kata`. L'allouable de `sc-build` est de 10 189 584 Ki, soit 9,72 Gio. Ces deux valeurs ont été
  lues par `kubectl` le 17/11, **non archivées**. Par le seul calcul sur les requêtes, un second pod ne serait pas planifié :
  `pod_demarrer` finirait en KO visible.

**Pourquoi la ligne `df`**
- Mesure archivée dans la 06 ([`s1-essais.log`](../../06-deb-sbuild/resultats/s1-essais.log), 10/11/2026, `aa0f54f6…`), avec la
  même spec de volume (`TMPFS=4Gi`, `sizeLimit: $t` dans le `s1.sh` de `15fd899`, relu le 17/11) :
  - sous Kata, deux pods montrent `/w` en « tmpfs rw,relatime », sans `size=` (lignes 10 et 34) ;
  - sous runc, le même volume montre « size=4194304k » (ligne 49).
- Le 3,0G vu à l'écran pendant `racine` est compatible avec la moitié des
  6 119 664 kB de `MemTotal` de l'invité ([`s1-racine.log`](s1-racine.log), ligne « invité »), soit 3 059 832 kB. C'est la taille
  par défaut d'un tmpfs d'après la documentation du noyau, non relue ici : c'est une **hypothèse**. Le 3,0G venait de
  `df -h /w`, lancé par `kubectl exec` (transcript de la session) ; sa sortie n'est pas archivée. Le `df` de coreutils est dans
  l'image : la ligne « rpm baseos98 coreutils-8.32-41.el9_8.1.x86_64.rpm … » figure dans [`s1-racine.log`](s1-racine.log).
- La ligne des montages de `SONDE` ne lit que les options de montage. Sous Kata, elle n'aurait donc pas donné la capacité.
- La ligne `df` est lue avant mock. P9 et P10, et les durées de mock, gardent leur sens. La phrase « `SONDE` reste inchangée » de
  la note N3/N4 ne vaut plus, une fois ce correctif appliqué, que pour ce qui suit cette ligne.

**Bancs, hors cluster, hors Zot et hors réseau**
- [`s1-duree-banc.sh`](s1-duree-banc.sh) sur la copie `a61fa50e…`, le 17/11/2026 de 10:57:45 à 10:57:47 UTC : **30 OK, 0 KO**
  ([journal](s1-duree-banc.log)) :
  - le diff ne change que les lignes voulues ;
  - le JSON de `pod_spec` ne diffère que par la commande ; `restartPolicy` reste `Never`, et le volume `/w` reste inchangé ;
  - `MOCK_CFG` et `STOCKAGE`, `etape_image`, `SONDE_N34`, `SONDE_VERROU`, `etape_essais` et `etape_verrou` sont identiques
    octet pour octet ; `SONDE` est identique une fois la ligne `df` retirée ;
  - la couche de configuration rejouée depuis la copie redonne `f5710d47…`. L'image `99790c13…` déjà dans Zot n'est donc pas à
    repousser ;
  - `bash -n` passe, et shellcheck 0.11.0 donne 13 remarques dans les deux fichiers ;
  - la ligne `df`, lancée par `sh` sur le tmpfs `/dev/shm` de l'hôte à la place de `/w`, affiche les mêmes nombres que `df -k`.
- Banc N3/N4 ([`s1-n34-banc.sh`](s1-n34-banc.sh)) sur la même copie, le 17/11/2026 à 10:57:58 UTC : **35 OK, 0 KO**
  ([journal](s1-duree-banc-n34.log)). Hors en-tête et bilan, le journal est identique à celui du 16/11 sur `ad16fc99…`
  ([`s1-extras-banc-n34-applique.log`](s1-extras-banc-n34-applique.log)).
- Le banc `extras` n'est pas repassé : son contrôle des lignes changées ne vise que le diff `extras`. Ce qu'il vérifie dans
  `MOCK_CFG` et `SONDE` est couvert par l'identité octet pour octet ci-dessus.
- **Passages antérieurs**, sur une première copie `54e68c47…` (sleep seul, avant « Oui, ajoute df ») :
  - premier passage du banc, à 10:55:57 UTC : 24 OK et un seul KO, dû au banc ([journal](s1-duree-banc-premier-passage.log)). Il comptait
    `10800` dans toute la copie, y compris dans la ligne d'en-tête « au lieu de 10800 ». Le contrôle ne porte désormais que sur
    les lignes hors commentaire. Ce journal a été produit par une version antérieure du banc, non archivée ;
  - les passages suivants sur cette copie (25 OK pour le banc de durée, 35 OK pour le banc N3/N4, à 10:56:12 UTC) ne sont pas
    archivés. Cette copie a été abandonnée.

**P11 corrigée** (l'ancienne ligne reste dans le tableau ; elle supposait 4 Gio de tmpfs) :

| # | Prédiction | Confiance |
|---|---|---|
| P11 (corrigée) | La ligne `df` donne une capacité de `/w` entre 3 040 871 et 3 145 728 kB (ce que `df -h` arrondit à « 3,0G »), probablement 3 059 832 kB, et non 4 194 304 kB | Moyenne : 3,0G vu à l'écran, non archivé ; la moitié de `MemTotal` est une hypothèse |
| P11b | `/w` ne se remplit pas : aucune ligne « No space left on device » dans `s1-essais.log` ni dans `s1-essais-mock.log`, et le code de l'exec de la sonde n'est pas 137 | Faible : aucune mesure du buildroot |
| P13 | La sonde finit sur « (code de l'exec : 0) », et la ligne « fait » d'`essais` est écrite dans `chrono.tsv` moins de 43 200 s après sa ligne de début | Moyenne : un seul rythme mesuré, celui de `racine` |

Chemin KO de P13, d'après la lecture du code : si le pod s'arrêtait avant la fin, la ligne des journaux de mock (484) finit par
`|| true` et ne bloque pas. Le premier `livrer` qui suit échouerait en revanche sous `set -euo pipefail`, et l'étape s'arrêterait
sans ligne « fait ».

Rien n'est appliqué à `s1.sh`. Rien n'est lancé.

Suite, chaque point sur accord nommé : appliquer le correctif (une ligne datée à l'en-tête de `s1.sh`) et le commiter ; puis
`essais`, puis `verrou`.

## Correctif durée de vie et place appliqué au dépôt (note du 2026-11-17, écrite à 2026-11-17T11:05:52Z ; rien n'est réécrit)

Question : « J'applique le correctif durée de vie et place à s1.sh et je le commite ? ». Réponse : « Oui, applique-le ».

- `git apply` de [`s1-duree.patch`](../s1-duree.patch) le 17/11/2026 à 11:04:44 UTC (`date -u` autour de la commande, la même
  seconde avant et après), sur `f6730b0`. `s1.sh` passe de `ad16fc99…` à `a61fa50e…`, le sha256 de la copie bancée.
  `git apply -R --check` passe juste après.
- **Banc de durée repassé sur le fichier du dépôt avant la ligne datée**, le 17/11/2026 de 11:04:51 à 11:04:53 UTC : 30 OK, 0 KO
  ([journal](s1-duree-banc-applique.log)). Hors des deux lignes d'en-tête et du bilan, son journal est identique à celui de la
  copie. Le banc lit le `s1.sh` d'avant (`ad16fc99…`) et `s1-image-banc-config.py` dans un dossier de base sous `~/.cache`,
  extraits de `f6730b0`.
- Une ligne datée est ensuite ajoutée à l'en-tête de `s1.sh` (deux lignes de commentaire), sans rien réécrire. `s1.sh` vaut
  désormais `5ccba38e…`. Le correctif ne s'applique donc plus dans un sens ni dans l'autre ; son fichier reste comme trace.
  - Elle portait d'abord 11:05:01, l'heure de l'édition, et non celle de `git apply`. Elle a été corrigée à 11:04:44 avant tout
    commit. Un banc N3/N4 passé sur ce premier état (`69c62726…`, 11:05:02 UTC) a donné 35 OK, 0 KO ; il n'est pas archivé.
- **Sur le fichier final** :
  - `bash -n` passe ;
  - shellcheck 0.11.0 ne relève aucun avertissement et compte toujours 13 remarques ;
  - le banc N3/N4, le 17/11/2026 de 11:05:15 à 11:05:16 UTC, donne 35 OK, 0 KO ([journal](s1-duree-banc-n34-applique.log)). Hors
    en-tête et bilan, le journal est identique à celui de la copie.
  - Par rapport à `ad16fc99…`, seules trois lignes hors commentaire changent : le `sleep` (retiré, puis ajouté) et la ligne `df`.
- Rien n'est lancé. Le pod de `racine` déjà passé avait `sleep 10800`. P11 (corrigée), P11b et P13 attendent `essais`.

Suite, chaque point sur accord nommé : push ; prédictions d'`essais` relues et complétées si besoin, puis `essais` ; `verrou`.

## Étape `essais` : prédictions complétées (note du 2026-11-17, écrite à 2026-11-17T11:49:12Z, avant tout passage ; rien n'est réécrit), NON LANCÉ

Relecture faite avant la question de lancement, sans toucher au cluster, à Zot ni au réseau. Elle complète P8 à P13, EX1 et A1 à
A7 ; aucune de ces lignes n'est réécrite. État : `s1.sh` vaut `5ccba38e…` ; `$T/image.digest` contient `sha256:99790c13…` ;
`s1-essais.log`, `s1-essais-mock.log` et `s1-verrou.json` n'existent pas encore.

**Lectures faites pour cette note.** C'est une lecture du code de mock 6.9, dans l'archive `m2` (sha256 `3c034916…`, celle du
banc de `image`), et de `racine.tar`, membre par membre :
- **Le code lu est celui installé dans l'image.** Dans `racine.tar`, `mockbuild/config.py` et `mockbuild/uid.py` sont égaux
  octet pour octet à ceux de l'archive. `./usr/libexec/mock/mock` ne diffère de `py/mock.py` que par la ligne 94
  (`_MOCK_NVR = "mock-6.9-1.el9"`), que le spec réécrit à l'installation (`mock.spec:267`). Les numéros de ligne cités valent pour
  les deux.
- **mock refuse root.** `rootcheck` (`mock.py:630` à `:636`, appelée en `:686`) lève une erreur si l'uid vaut 0 et qu'aucune de
  `SUDO_UID`, `USERHELPER_UID` ou `PKEXEC_UID` n'est posée.
  - Le spec construit mock sans polkit par défaut (`mock.spec:3`, `%bcond_with polkit`). `/usr/bin/mock` est alors un lien vers
    `consolehelper` (`mock.spec:217` à `:221`).
  - Dans `racine.tar`, `./usr/bin/mock` pointe vers `consolehelper`, et `./usr/sbin/userhelper` est setuid root.
  - `./etc/pam.d/mock` et `./etc/security/console.apps/mock` sont égaux octet pour octet à ceux de l'archive amont. La pile
    d'authentification PAM de mock commence par `auth sufficient pam_rootok.so`.
  - polkit n'est pas dans la liste de `racine`, usermode y est (`usermode-1.114-7.el9`).
- `groupcheck` (`mock.py:640` à `:654`) reçoit deux fois le même gid : `chrootgid`, le gid du groupe `mock` (`config.py:85` ;
  135 dans le `/etc/group` de la racine), repris par `reload_uidmanager` (`uid.py:54` à `:56`). La configuration de S1 ne fixe
  pas `chrootgid`. D'après cette lecture, ce contrôle ne devrait donc pas échouer.
- **Non lu** : que `userhelper`, appelé par root, pose `USERHELPER_UID`. Le source d'usermode n'a pas été relu. Le binaire
  `userhelper` de la racine contient bien la chaîne `USERHELPER_UID` ; c'est une lecture de binaire, qui ne prouve pas le cas
  root. C'est ce point qui décide P12.
- **Non lu non plus** : ce que mock fait ensuite avec un uid non privilégié qui vaut 0. `unprivUid` prend la valeur de
  `USERHELPER_UID` (`uid.py:36`), et `chrootuid` celle de `os.getuid()` (`config.py:83`). L'usage de ces valeurs dans le chroot
  n'est pas lu. « Au plus un avertissement » (P12) reste donc une prédiction.
- `bootstrap_image_fallback` vaut `True` par défaut (`config.py:110`). Si podman échoue, mock peut donc se rabattre sur un
  bootstrap installé depuis les dépôts. **P8 se lit sur les lignes podman de la sonde, et non sur le succès de mock.**
- `root_cache_enable` vaut `True` par défaut (`config.py:176`). mock écrit donc une archive pigz du buildroot sous
  `/w/mock-cache/<racine>/root_cache/` (`config.py:177` à `:181`), qui s'ajoute à la place prise sous `/w`. Le `dnf.conf` du
  modèle porte aussi `keepcache=1` (`rocky-9.tpl:11`) : les rpm téléchargés restent dans le cache, sous `/w/mock-cache`.
- Le modèle `rocky-9.tpl` installe d'abord 21 noms de paquets (`chroot_setup_cmd`). Le nombre de rpm du buildroot, dépendances
  comprises, n'est mesuré nulle part. Toutes ses `gpgkey` visent
  `file:///usr/share/distribution-gpg-keys/rocky/RPM-GPG-KEY-Rocky-9`.
- Zot : `08-trust-plane/stockage/zot.json` accorde la lecture anonyme (`anonymousPolicy` `read`) sur `**`. C'est le fichier du
  dépôt ; la configuration en service n'est pas relue. Le `podman pull` de la sonde n'a aucun identifiant et repose sur ce point.
- Mesure de la 06 sous Kata, sur un pod privilégié en uid 1000 (`06-deb-sbuild/resultats/s1-essais.log`, lignes 4 à 10,
  10/11/2026) : `CapEff` 0, `CapBnd` `000001ffffffffff`, `NoNewPrivs` 0, `Seccomp` 0, `/` en virtiofs, `/w` en tmpfs sans
  `size=`.
- Sources livrées : `sha256sum -c` des deux lignes de `SHA256SUMS` du cache de packaging donne deux OK sur l'hôte, ce jour (non
  archivé). Le changelog du spec est daté du « Mon Nov 16 2026 », pour la release `1.0.0-2`.

**Défaut de la sonde, relevé à la relecture et non corrigé.** La garde des mirrorlist ne lit pas le code de
`mock --debug-config`. Si cette commande échoue, son journal ne contient aucun `mirrorlist` : `n` vaut 0 et la sonde continue.
EX1 couvre ce cas par ses quatre baseurl de vault 9.7, et E4 l'exige aussi.

**Prédictions complémentaires.** Aucune ne remplace une ligne déjà écrite ; E5, E7 et E8 précisent P8, P12 et P10 :

| # | Prédiction | Confiance |
|---|---|---|
| E1 | En tête de la sonde : `uid : 0` ; `CapEff` égal à `CapBnd`, soit `000001ffffffffff` ; `NoNewPrivs` 0 ; `Seccomp` 0 ; `montage / : virtiofs …` ; `montage /w : tmpfs rw,relatime`, sans `size=` | Moyenne : mesuré dans la 06 en uid 1000 ; `CapEff` en uid 0 non mesuré |
| E2 | Six lignes « version : » : `mock-6.9-1.el9.noarch`, `mock-core-configs-45.2-1.el9.noarch`, `podman-5.8.2-8.el9_8.x86_64`, `skopeo-1.22.2-9.el9_8.x86_64`, `systemd-container-252-67.el9_8.6.rocky.0.1.x86_64`, `distribution-gpg-keys-1.123-1.el9.noarch` | Haute : liste de `racine`, même `racine.tar` dans l'image |
| E3 | Une seule ligne « gpgkey du modèle », vers `distribution-gpg-keys/rocky/RPM-GPG-KEY-Rocky-9` ; la ligne « clé RPM-GPG-KEY-Rocky-9 » donne `21CB256AE16FC54C6E652949702D426D350D275D` | Haute pour la gpgkey (modèle lu) ; moyenne pour l'empreinte (contenu de distribution-gpg-keys non lu) |
| E4 | `mock --debug-config : rc 0`, avec les quatre baseurl d'EX1 | Moyenne : dépend de E7 |
| E5 (P8 précisée) | `stockage : overlay sous /w/containers` ; `podman pull du bootstrap : rc 0`, en moins de 300 s ; `podman image mount : rc 0 ; os-release : VERSION_ID="9.7"` | Faible, comme P8 |
| E6 | `sources livrées : rc 0`, avec deux OK | Haute |
| E7 (P12 précisée) | mock passe l'entrée par consolehelper. La preuve positive est E4 (`rc 0`), et aucune ligne « mock will not run from the root account » n'apparaît. Chemin KO : E4 donne un rc non nul, puis les deux `--buildsrpm` échouent en quelques secondes. Un refus de mock afficherait ce message dans le `tail` de `mock-<isolation>-srpm.log` ; un échec de consolehelper ou de PAM ne l'afficherait pas | Moyenne : `userhelper` non lu ; la suite, avec un uid 0, non lue |
| E8 (P10 précisée, durées) | Pour `simple` : `--buildsrpm` entre 600 et 10 800 s, et `--rebuild` entre 300 et 3 600 s. La borne « moins de 5 minutes » de P10 n'est donc pas attendue. Pour `nspawn`, aucune borne : P9 le dit en échec | Faible : un seul rythme mesuré, celui de `racine` (28,6 s par rpm, cause inconnue) ; nombre de rpm du buildroot non mesuré |
| E9 | « place de /w après simple » entre 800 et 2 900 Mo. Elle est lue après le `--rebuild` et avant le scrub, et compte le buildroot, le cache de racine, les rpm gardés par `keepcache`, le bootstrap et le stockage de podman | Faible |
| E10 | `scrub <isolation> : rc 0` pour chaque isolation | Moyenne |
| E11 | Sonde complète : la ligne « scrub simple : rc … » est présente, avant « (code de l'exec : … ) ». `SONDE` finit par `true` : le code 0 de P13 ne suffit donc pas à dire que la sonde est allée au bout | Moyenne |

**Commande prévue** : `env -u PREFIXE DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh essais </dev/null`, sur le commit de
cette note. Elle tournera en arrière-plan sous `bash -c`, entre deux `date -u`, avec le code lu par `PIPESTATUS`. Journaux
attendus : `resultats/s1-essais.log` et `resultats/s1-essais-mock.log`.

**Aucun délai de garde dans `SONDE`.** Un nspawn qui pend n'est borné que par les 12 h du pod. Le lancement en arrière-plan ne
signale que sa fin : aucun réveil n'est prévu en cours de route. Pendant le passage, le suivi se fait à la demande, en lecture
seule, sur la sortie de la sonde (`$T/essais.log`, désigné par son nom) et sur `chrono.tsv`. Si une lecture montre que cette
sortie n'a pas bougé depuis plus de 4 h, au-delà de la borne haute d'E8, c'est rapporté au propriétaire. Rien n'est arrêté sans
son accord.

Suite, chaque point sur accord nommé : `essais` (« Je lance essais ? »), puis `verrou`, avec ses prédictions et son propre accord.

## Étape `essais` : résultat (note du 2026-11-17, écrite à 2026-11-17T12:13:50Z ; rien n'est réécrit)

Question : « Je lance essais ? ». Réponse : « Oui ». Commande : `env -u PREFIXE DISTRO=rke2 mise exec --
poc/bricks/05-rpm-mock/s1.sh essais </dev/null`, avec `KUBECONFIG` posé à `~/.kube/supply-chain-poc.yaml` dans la même
commande, sur `0c21d79`, en arrière-plan, sous `bash -c`. Elle a tourné le 17/11/2026 de 12:06:56 à 12:09:00 UTC, soit 124 s
(`date -u` autour de la commande, et `chrono.tsv`). Journaux : [`s1-essais.log`](s1-essais.log), sha256 `f1ffdae0…`, 175 lignes,
égal à la sortie écrite dans un fichier du scratchpad ; [`s1-essais-mock.log`](s1-essais-mock.log), `f2074b5c…`, 435 lignes
(les 200 dernières lignes de chaque `build.log` et `root.log`). Le code 0 a été lu par `PIPESTATUS`, dans un fichier du
scratchpad non archivé ; la ligne « fait » de `chrono.tsv` le corrobore.

**En bref.** podman imbriqué fonctionne dans le pod Kata (P8). `nspawn` échoue, `simple` construit le src.rpm et le rpm de
sample-app (P9, P10). N3 et N4 tiennent sur le rpm de `simple`. Deux prédictions ne tiennent pas : les durées d'E8, bien
plus courtes que prévu, et la date de A5.

| | Mesure | Verdict |
|---|---|---|
| P8, E5 | Lignes podman de la sonde : `stockage : overlay sous /w/containers` ; pull du bootstrap rc 0 en 7 s ; `image mount` rc 0, `VERSION_ID="9.7"`. Pour l'essai `nspawn`, la sortie de mock affichée dans `s1-essais.log` montre l'image tirée, montée par `podman image mount` et copiée dans le bootstrap. Pour `simple`, le début de `root.log` n'est pas archivé : que mock y ait employé l'image n'est pas lu | Tenues sur les lignes de la sonde ; emploi par mock lu pour `nspawn` seulement |
| P9 | `mock nspawn --buildsrpm : rc 30 en 5 s`, avec « Failed to open system bus: No such file or directory » ; `simple` passe | Tenue |
| P10 | src.rpm `sample-app-1.0.0-2.el9.src.rpm` (`c802e60a…`) et rpm `sample-app-1.0.0-2.el9.x86_64.rpm` (`864d55f4…`) produits ; `--rebuild` en 43 s, sous les 5 minutes. Le buildroot contient `golang-1.25.9-1.el9_7` et `nodejs-1:16.20.2-8.el9_4` ; le dépôt d'origine n'est pas dans les 200 lignes archivées de `root.log` | Tenue pour le build et la durée ; origine vault 9.7 compatible avec les versions, non lue |
| P11 (corrigée) | `capacité de /w : 3059832 kB` | Tenue, à la valeur probable |
| P11b | Aucune ligne « No space left on device » dans les deux journaux ; code de l'exec 0 | Tenue |
| P12, E7 | mock lancé en root est accepté : `--debug-config` rc 0, les deux étapes de `simple` en rc 0, aucune ligne « mock will not run from the root account » dans les journaux archivés. Le passage par consolehelper reste une lecture de code. La sortie console de mock pour `simple` (`/w/mock-simple-*.log`) n'est pas archivée : un éventuel avertissement de mock n'est pas lu. Ceux des journaux archivés viennent de rpmbuild (macro dans un commentaire du spec, build-id absent du binaire) | Tenues pour l'acceptation ; « au plus un avertissement » non lu |
| P13 | Sonde finie sur « (code de l'exec : 0) » ; ligne « fait » 124 s après le début | Tenue |
| EX1, E4 | `mock --debug-config : rc 0` ; quatre baseurl de vault 9.7 (BaseOS, AppStream, CRB, `extras`) ; « mirrorlist restants … : 0 » ; les mirrorlist des dépôts de debug, de sources et des autres dépôts restent listés. Quatre baseurl mouvantes (`http://dl.rockylinux.org/pub/rocky/$releasever/<dépôt>/$basearch/os/`) sont aussi listées pour ces quatre dépôts : dans `rocky-9.tpl` (archive `m2`, lignes 33, 42, 51 et 60), ce sont des lignes `#baseurl=`, commentées, que le `grep -o` de la sonde ne distingue pas | Tenues |
| E1 | `uid : 0` ; `CapEff` = `CapBnd` = `000001ffffffffff` ; `NoNewPrivs` 0 ; `Seccomp` 0 ; `/` en virtiofs ; `/w` en `tmpfs rw,relatime`, sans `size=` | Tenue |
| E2 | Les six versions attendues | Tenue |
| E3 | Une seule ligne « gpgkey du modèle » ; « clé RPM-GPG-KEY-Rocky-9 : 21CB256A…350D275D ». La sonde liste neuf clés sous `distribution-gpg-keys/rocky` | Tenue |
| E6 | `sources livrées : rc 0`, deux OK | Tenue |
| E8 | `simple --buildsrpm` en 53 s (borne basse prédite : 600 s) ; `--rebuild` en 43 s (borne basse : 300 s). Le `root.log` de `simple`, tronqué à ses 200 dernières lignes, liste au moins 137 paquets installés, d'une seule liste commencée avant la troncature | **Non tenue** : au rythme de `racine` (28,6 s par rpm), 137 paquets auraient pris environ 3 900 s ; mock en a mis 96 pour les deux étapes. La cause de la lenteur de `racine` reste inconnue |
| E9 | `place de /w après simple : 1034 Mo` | Tenue (800 à 2 900 Mo) |
| E10 | `scrub simple : rc 0`. Pour `nspawn`, aucune ligne : en cas d'échec, la sonde lance le scrub sans afficher son code (lecture de `SONDE`) | Tenue pour `simple` ; non mesurable pour `nspawn` |
| E11 | « scrub simple : rc 0 » juste avant « (code de l'exec : 0) » | Tenue |
| A1 | « OK   rpm simple rapatrié », sha256 égal à la sonde ; aucun rpm pour `nspawn` | Tenue pour `simple` |
| A2 | `FILEDIGESTALGO` 8 | Tenue |
| A3 (N3) | Six fichiers sous `/usr/share/licenses/sample-app/`, drapeaux 128 (bit 128 à 1), empreintes `074e6e32…`, `a2d51b75…`, `8e3a3f82…`, `911f8f57…`, `b55ad0c8…`, `96f408bf…`, toutes égales aux prédictions ; ligne du répertoire, drapeaux 0, sans empreinte | Tenue |
| A4 (N4) | `memmove_amd64.s` PRÉSENT sous la forme `runtime/memmove_amd64.s` ; témoin `asm_amd64.s` présent, `asm_arm.s` absent ; les huit autres motifs absents ; `n34-binaire.py : rc 0` | Tenue |
| A5 (N5) | `buildtime 1794787200` (16/11/2026 00:00:00 UTC) ; `changelogtime 1794830400` (16/11/2026 12:00:00 UTC) ; mtime : deux valeurs, 1793229566 (28/10/2026 23:19:26 UTC, archive des sources) et 1794787200. Le journal de mock porte quatre fois `setting SOURCE_DATE_EPOCH=1794787200` | **Non tenue** : `BUILDTIME` ≠ `CHANGELOGTIME`. `SOURCE_DATE_EPOCH` vaut minuit, pas midi ; `BUILDTIME` et le mtime max lui sont égaux, donc le clamp joue |
| A6 | `nspawn` n'a rien construit | Sans objet |
| A7 | Pas de mesure propre. Borne : l'étape entière a duré 124 s, dont 101 s de mock mesurées | Tenue par cette borne |

**Ce qui n'est pas mesuré.** Le nombre exact de rpm du buildroot (seul le `root.log` de `simple` atteint la troncature à 200
lignes ; le `build.log` de `simple` et le `root.log` de `nspawn` sont entiers) ; le dépôt
d'origine de golang et de nodejs ; la cause de l'échec de `nspawn` au-delà du message affiché ; la cause de la lenteur de
`racine`. Le rpm de `simple` est rapatrié sous `$T/rpm-simple`, hors du dépôt.

Retiré : le pod `s1-05-essais`. La suppression est demandée en fin d'étape (`--wait=false`) ; un `kubectl get pod` à 12:13:04 UTC
répond NotFound (vu à l'écran, non archivé). Rien n'est écrit dans Zot.

Suite, chaque point sur accord nommé : `verrou`, avec ses prédictions et son propre accord (`ISOLATION=simple`, d'après P9).

## Étape `verrou` : prédictions (note du 2026-11-17, écrite à 2026-11-17T12:46:55Z, avant tout passage ; rien n'est réécrit), NON LANCÉ

Relecture faite avant la question de lancement, sans toucher au cluster, à Zot ni au réseau. Elle complète V1 à V9 et EX2 ;
aucune de ces lignes n'est réécrite. État : `s1.sh` vaut `5ccba38e…` (inchangé depuis `essais`, donc pas d'accord de
modification) ; `$T/image.digest` contient `sha256:99790c13…` ; `s1-verrou.json`, `s1-verrou.log` et `s1-verrou-mock.log`
n'existent pas encore.

**Lectures faites pour cette note.** Code de mock 6.9 dans l'archive `m2` (sha256 `3c034916…`), extraite dans le scratchpad ;
`mock-core-configs` 45.2 de la même archive, version égale à celle de l'image (E2). Rien de ceci n'est exécuté.
- **dnf dans `rockylinux:9.7` brut : ligne du journal et lecture de code.** Dans `s1-essais.log` (ligne 97, essai
  `nspawn`), mock écrit « Package manager dnf4 detected and used (fallback) » juste après avoir copié l'image dans le
  bootstrap, et avant « Bootstrap image not marked ready ». D'après le code, `_init` charge l'image (`buildroot.py:325`)
  puis cherche le gestionnaire de paquets (`:338`, message écrit en `:183`). Cette recherche se fait dans l'image extraite
  quand `uses_bootstrap_image` est vrai (`package_manager.py:69` à `:71`), c'est-à-dire pour un bootstrap dont l'image n'a
  pas été abandonnée (`buildroot.py:1158`, `:308`). Le journal d'`essais` ne contient aucun « falling back ».
- **`--buildsrpm` n'appelle pas `builddep`** : `do_buildsrpm` (`rebuild.py:90` à `:99`) appelle `buildsrpm`
  (`backend.py:562`), lu jusqu'à `:600` ; au-delà, une recherche de motif seulement : de `:299` à `:703`, `backend.py` ne
  mentionne `Deps` ou `builddep` qu'en `:299` (mode `rebuild`) et `:703` (commentaire). `--calculate-build-dependencies` devient le mode
  `rebuild` (`mock.py:447`), qui reconstruit le src.rpm puis appelle `builddep` (`backend.py:299`, `:207`). Avec dnf4,
  l'absence du greffon donne « builddep command missing. Please install package dnf-plugins-core. »
  (`package_manager.py:717`), si une ligne de l'erreur contient « no such command: builddep » (`:716`). Avec `bootstrap_image_ready = True`, mock n'installe rien dans le bootstrap (V9).
- **Non lu : la présence du greffon `builddep` (python3-dnf-plugins-core) dans `rockylinux:9.7` brut.** En `essais`, image
  non prête, mock a demandé son installation (`s1-essais.log`, ligne 116). Le début du `root.log` de `simple` n'est pas
  archivé : on ne sait pas s'il était déjà là. C'est ce point qui décide V2 et la suite.
- **Le verrou** : fichier `buildroot_lock.json` (`buildroot_lock.py:37`), format `1.1.0` (`:72`), écrit au crochet
  `postdeps` (`backend.py:736`), donc après `builddep`. Options recopiées si présentes (`:85` à `:97`) : `target_arch`,
  `legal_host_arches`, `dist`, `package_manager`, `bootstrap_image`, `bootstrap_image_ready`, `macros`. `rocky-9.tpl` pose
  `dist` (ligne 2) et `package_manager` (ligne 4) ; la configuration de S1 pose les cinq autres. **`macros` est dans la
  liste** : `m2-predictions.md` l'a relevé le 12/11 (« V4 de S1 devrait tomber ») ; V4 reste telle qu'elle a été écrite.
- **Paquets du buildroot** : champs `name`, `arch`, `license`, `version`, `release`, `epoch`, `sigmd5`, `signature`
  (`buildroot_lock.py:51`, `:52`), plus `url` (`installed_packages.py:144`). `signature` garde les 8 derniers caractères
  hexadécimaux de l'identifiant de clé (`installed_packages.py:79`). Si un seul paquet n'a pas d'URL dans les dépôts
  configurés, mock s'arrête sur « Can't get location for … » (`:151`) et ne produit pas de verrou.
- **Nouveau chemin d'échec, non lu jusqu'au bout.** mock retire son étiquette temporaire du bootstrap après l'avoir copié
  (`buildroot.py:303`, `podman rmi`, `podman.py:244`). Le verrou interroge ensuite `podman image inspect` sur la référence
  par digest (`podman.py:268`), avec `check=True` (`:271`). Seule `PodmanError` est rattrapée (`buildroot_lock.py:112`) :
  si l'image a disparu du stockage de podman, l'erreur remonte, sans verrou. Contrairement à `essais`, `SONDE_VERROU` ne
  tire pas l'image elle-même. Que podman garde une image tirée par digest après ce `rmi` n'est pas lu.

| # | Prédiction | Confiance |
|---|---|---|
| V10 (V1 précisée) | `mock --debug-config : rc 0` ; `mock --buildsrpm (image prête) : rc 0` ; src.rpm `sample-app-1.0.0-2.el9.src.rpm` | Moyenne : dnf dans l'image (journal et code), `--buildsrpm` sans `builddep` (code) |
| V11 | Même sha256 du src.rpm qu'en `essais` : `c802e60a…` | Moyenne : même spec, même archive, `SOURCE_DATE_EPOCH` et clamp ; deux constructions seulement |
| V12 (V2 précisée) | **Pas de pari sur la branche.** Greffon présent : `--calculate-build-dependencies : rc 0` et un seul `.json`. Greffon absent : rc non nul, « builddep command missing » dans les 25 dernières lignes de `verrou-calc.log`, puis « aucun verrou produit ». Une autre cause d'échec est notée telle quelle | Moyenne sur le message : le texte exact de dnf et sa présence dans l'erreur de mock ne sont pas lus ; à défaut, la ligne brute de dnf est l'observable. La branche n'est pas prédite |
| V13 (V3 précisée) | Si un verrou est produit : un seul fichier, `buildroot_lock.json` ; « version du verrou : 1.1.0 » ; « options de configuration recopiées : bootstrap_image, bootstrap_image_ready, dist, legal_host_arches, macros, package_manager, target_arch » ; « bootstrap_image_ready enregistré : True » | Haute pour le nom et la version ; moyenne pour les sept options (objet de configuration lu par le greffon non suivi) |
| V14 | « macros recopiées : oui » : **V4 ne devrait pas tenir** | Haute (code lu) |
| V15 | Si un verrou est produit : `pull_digest` vaut `sha256:ee90dc0e…` ; architecture `amd64` ; `image_digest` est un autre sha256 (V3, note de 15:18:25 le 12/11). Autre branche possible, non prédite : rc non nul au crochet `postdeps` à cause du `podman image inspect` | Moyenne |
| V16 | « rpm du buildroot : N ; champs : arch, epoch, license, name, release, sigmd5, signature, url, version ». N entre 150 et 400 (V5, inchangée) | Haute pour les champs ; V5 garde sa confiance |
| V17 | Dans le JSON archivé : chaque `signature` vaut `350d275d` (clé Rocky 9 d'E3), chaque `url` commence par `https://dl.rockylinux.org/vault/rocky/9.7/`, aucune sous `/extras/` (EX2) | Moyenne : signature de chaque paquet non lue |
| V18 | Intégrité : `s1-verrou.json` a la taille et le sha256 de la ligne « verrou : buildroot_lock.json … » de la sonde (la copie passe par un `grep -v` ligne à ligne, puis le pod est supprimé) | Haute : aucun mot filtré attendu dans un verrou |
| V19 | Durées, ancrées sur `essais` (53 s et 43 s, même image, même type de pod) et non sur `racine` : `--buildsrpm` entre 20 et 300 s ; `--calculate-build-dependencies` entre 10 et 300 s | Moyenne |
| V20 | Sonde complète : des lignes « résultat : » puis « (code de l'exec : 0) ». La sonde finit par `true` : le code 0 seul ne prouve rien (comme E11). Aucune ligne « No space left on device » dans les deux journaux ; la sonde n'a pas de ligne `df` | Moyenne |

V6 à V9 restent telles qu'elles ont été écrites. Rien n'est écrit dans Zot ; le pod `s1-05-verrou` est supprimé en fin
d'étape, ce qu'un `kubectl get` vérifiera.

**Commande prévue** : `env -u PREFIXE ISOLATION=simple DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh verrou
</dev/null`, avec `KUBECONFIG` posé à `~/.kube/supply-chain-poc.yaml` dans la même commande, sur le commit de cette note.
`ISOLATION` est posée explicitement, pour qu'une variable héritée ne la change pas. Elle tournera en arrière-plan sous
`bash -c`, entre deux `date -u`, avec le code lu par `PIPESTATUS`. Journaux attendus : `resultats/s1-verrou.log`,
`resultats/s1-verrou-mock.log` et, si un verrou est produit, `resultats/s1-verrou.json`.

Suite, chaque point sur accord nommé : `verrou` (« Je lance verrou ? »).

## Étape `verrou` : résultat (note du 2026-11-17, écrite à 2026-11-17T12:52:25Z ; rien n'est réécrit)

Question : « Je lance verrou ? ». Réponse : « Oui, lance verrou ». Commande : `env -u PREFIXE ISOLATION=simple DISTRO=rke2
mise exec -- poc/bricks/05-rpm-mock/s1.sh verrou </dev/null`, avec `KUBECONFIG` posé à `~/.kube/supply-chain-poc.yaml` dans la
même commande, sur `a429f6f`, en arrière-plan, sous `bash -c`. Elle a tourné le 17/11/2026 de 12:47:47 à 12:48:49 UTC, soit
62 s (`date -u` autour de la commande, et `chrono.tsv`). Journaux : [`s1-verrou.log`](s1-verrou.log), sha256 `0f3ba64b…`,
74 lignes, égal à la sortie écrite dans un fichier du scratchpad ; [`s1-verrou-mock.log`](s1-verrou-mock.log), `d0577bfc…`,
217 lignes : 199 lignes de `root.log` (et non 200 comme en `essais` : le seul retrait de lignes de l'étape est le filtre
`jeton|token`, et la cause de l'écart n'est plus vérifiable, le pod étant supprimé), puis `build.log` entier (1 382 octets,
égal au `ls` de la sonde). Le code 0 a été lu par `PIPESTATUS`, dans un
fichier du scratchpad non archivé ; la ligne « fait » de `chrono.tsv` le corrobore. `s1-verrou.json` n'existe pas.

**En bref.** `rockylinux:9.7` brut ne suffit pas comme image de bootstrap « prête » : `--buildsrpm` passe, mais
`--calculate-build-dependencies` échoue en 6 s, faute de la commande `builddep` de dnf (greffon `dnf-plugins-core`). Aucun
verrou n'est produit. C'est la branche « greffon absent » de V12.

| | Mesure | Verdict |
|---|---|---|
| V6 | « configuration : config_opts['bootstrap_image_ready'] = True » | Tenue |
| V7 | « options bootstrap_* qui annulent « prête », posées : 0 » | Tenue |
| V8 | Ni « Package management in bootstrap » ni « Bootstrap image not marked ready », ni dans la sonde (qui lit tout `root.log`) ni dans les journaux archivés | Tenue |
| V9 | Après `--buildsrpm` : une ligne « Not updating bootstrap chroot, bootstrap_image_ready=True » (`buildroot.py:1193`) | Tenue |
| V1, V10 | `mock --debug-config : rc 0` ; `mock --buildsrpm (image prête) : rc 0 en 50 s` ; src.rpm `sample-app-1.0.0-2.el9.src.rpm` | Tenues |
| V11 | sha256 du src.rpm `c802e60a…`, égal à celui d'`essais` | Tenue : deux constructions du src.rpm, même empreinte |
| V2 | Telle qu'écrite (« si V1 échoue »), sans objet : V1 tient. Le manque d'outil qu'elle visait apparaît à l'étape suivante (V12) | Sans objet |
| V12 | Branche « greffon absent » : `--calculate-build-dependencies : rc 10 en 6 s` ; « ERROR: builddep command missing. » et « Please install package dnf-plugins-core. » dans la sortie de mock ; « aucun verrou produit ». Ligne brute de dnf, dans `s1-verrou-mock.log` (ligne 138) : « No such command: builddep. Please use /usr/bin/dnf-3 --help », pour `dnf-3 builddep --installroot /w/mock/poc-rocky-9.7-pret-x86_64/root/` | Tenue (branche non prédite, observables tenus) |
| V19 | `--buildsrpm` en 50 s (borne 20 à 300 s) ; `--calculate-build-dependencies` en 6 s (borne basse : 10 s) | Tenue pour `--buildsrpm` ; **non tenue** pour le calcul, arrêté avant toute installation de dépendances |
| V20 | Lignes « résultat : » (`build.log`, `hw_info.log`, `root.log`, le src.rpm, `state.log`), puis « (code de l'exec : 0) » ; aucune ligne « No space left on device » | Tenue |
| V3, V13, V15 à V18 | Aucun verrou : rien à lire. Le chemin `podman image inspect` après `podman rmi` (V15) n'est pas atteint | Sans objet |
| V4, V14, V5, EX2 | Aucun verrou | Non mesurées |

**Le `dnf-3` en échec est celui de l'image de bootstrap**, d'après trois éléments :
- mock écrit « Buildroot is handled by package management downloaded with a bootstrap image: » et liste
  `rpm-4.16.1.3-39.el9`, `python3-dnf-4.14.0-31.el9`, `yum-4.14.0-31.el9`. Que cette liste soit exhaustive n'est pas lu ;
- le buildroot est monté (`rbind`) sous la racine du bootstrap, dans `/w/mock/poc-rocky-9.7-pret-x86_64-bootstrap/root/w/mock/…`,
  avant l'appel à `dnf-3 builddep --installroot` ;
- l'image d'essai porte une autre version de dnf : la liste de `racine` donne `python3-dnf-4.14.0-34.el9_8.rocky.0.1`
  ([`s1-racine.log`](s1-racine.log), ligne 160), pas `4.14.0-31.el9`.

**Observé hors prédiction.**
- Pour le buildroot, mock écrit « Package manager dnf4 detected and used (direct choice) » (fin de `verrou-calc.log`).
- Le nombre cumulé de lignes « Not updating bootstrap chroot » reste 1 après `--calculate-build-dependencies`
  (accroissement non prédit dans la note du 12/11). Deux lectures possibles, non tranchées : le second appel n'écrit pas ce
  message, ou `root.log` n'est pas cumulé d'un appel à l'autre.
- `build.log` contient deux lignes « Wrote: … src.rpm », une par appel : en mode calcul, mock reconstruit le src.rpm avant
  d'appeler `builddep`. Le sha256 de la seconde construction n'est pas relevé.

**Ce que cela décide, et ce que cela ne décide pas.** Pour l'embranchement 2 de M2 (`m2-predictions.md`, « Image de
bootstrap prête »), c'est mesuré sur un passage : l'image brute ne suffit pas. Une image de bootstrap qui contient le
greffon `builddep` est donc nécessaire, mais pas suffisante : la recherche des URL des paquets (`installed_packages.py:151`)
et le `podman image inspect` après `podman rmi` (V15) n'ont pas été atteints. La façon de produire cette image (par
exemple une image construite par la chaîne, par digest) est une décision du propriétaire, non prise ici. Rien n'est
mesuré sur le contenu du verrou ni sur le mode hermétique.

Retiré : le pod `s1-05-verrou`. La suppression est demandée en fin d'étape (`--wait=false`) ; un `kubectl get pod` à
12:49:04 UTC répond NotFound (vu à l'écran, non archivé). Rien n'est écrit dans Zot.

Suite : l'image de bootstrap prête est une décision du propriétaire, avant toute nouvelle étape `verrou`.

## Image de bootstrap : décisions, et étape `verrou_brut` préparée à sec (note du 2026-11-17, écrite à 2026-11-17T13:16:28Z ; rien n'est réécrit ; NON APPLIQUÉ)

Deux décisions du propriétaire, prises le 17/11/2026 :
- Question : « D'où doit venir l'image de bootstrap prête pour M2 ? ». Options présentées : une image dérivée de
  `rockylinux:9.7` (`ee90dc0e…`) avec `python3-dnf-plugins-core` de vault 9.7 ; ou reporter M2. AlmaLinux a été écartée : aucun
  verdict dans docs/04. Pour mémoire, `almalinux-9.tpl:7` de mock-core-configs la déclare prête ; c'est une lecture de code, son
  contenu n'est pas mesuré. Réponse : « Image Rocky dérivée », lue avant 13:02:14 UTC (premier `date -u` qui la suit).
- Question : « Je mesure d'abord le verrou sur l'image brute, avant de dériver ? ». Réponse : « Mesurer d'abord », lue avant
  13:07:55 UTC (premier `date -u` qui la suit).

**Lecture de code** (mock 6.9, archive `3c034916…`), **non mesurée** :
- Le greffon `buildroot_lock` attache l'écriture du verrou au crochet `postdeps` (`buildroot_lock.py:28`). De `:30` à `:117`,
  `bootstrap_image_ready` est recopié (`:94`), jamais exigé. Le refus vient plus tard, de `--hermetic-build` (`config.py:824`).
  Avec `bootstrap_image_ready = False`, le calcul devrait donc écrire un verrou, inutilisable en mode hermétique.
- Avec `use_bootstrap_image` vrai (`:105`), le verrou interroge l'image par podman (`:110`), et seule `PodmanError` est
  attrapée (`:112`). D'après la lecture, c'est le même chemin qu'avec une image prête. La question de l'`inspect` après le
  `rmi` (note de `verrou`) s'y pose donc aussi.
- `cleanup_on_success` vaut `True` par défaut (`config.py:128`). `rebuild.py:32` à `:34` nettoie alors en fin de passage, et
  `--no-cleanup-after` le met à `False` (`config.py:658` à `:660`).
- Le champ `signature` du verrou vient de `%{sigpgp:pgpsig}` (`installed_packages.py:62` à `:64`).

**Correctif** : [`../s1-verrou-brut.patch`](../s1-verrou-brut.patch), insertions seules (4 lignes d'en-tête, 80 lignes avant
l'appel de `lancer`), sha256 `c29d5be7…`. Copie modifiée de `s1.sh` : sha256 `c86589c4…`, écrite par
[`s1-verrou-brut-modifier.py`](s1-verrou-brut-modifier.py) à partir de `5ccba38e…`. `SONDE_VERROU` et `etape_verrou` ne changent
pas. L'étape `verrou_brut` :
- démarre le même type de pod (`s1-05-verrou-brut`, image d'essai `99790c13…`) et livre les mêmes fichiers ;
- passe `SONDE_VERROU` avec `$CFG` (`bootstrap_image_ready = False`) au lieu de `$CFG_PRET`. Deux lignes seulement diffèrent
  du rendu de `verrou` avec la même configuration : le libellé « (image brute) », et `--no-cleanup-after` sur le calcul ;
- lance `SONDE_BOOT`. Elle cherche le bootstrap gardé par mock (motif `-bootstrap*/root`, chemin retenu affiché, car le chemin
  sans `uniqueext` n'est relevé dans aucun journal). Elle lit `rpm -qa` de ce bootstrap, puis de `rockylinux:9.7` brut, tiré par
  digest et monté. Elle affiche ensuite les lignes propres à chacun, avec deux étiquettes de signature (`sigpgp` et
  `rsaheader`), et finit par `df -k /w` ;
- archive les journaux : `root.log` et `build.log` (400 dernières lignes) et la fin de `verrou-calc.log`, masqués ;
- archive le verrou s'il existe, puis le résume. Le résumé dit si le champ `bootstrap` est vide et compte les `url`, avec leurs
  préfixes et les valeurs de `signature`. Il ne peut pas arrêter l'étape (`|| echo`), car cette branche n'a jamais tourné en vrai ;
- retire le pod. Journaux distincts : `s1-verrou_brut.log`, `s1-verrou_brut.json`, `s1-verrou_brut-mock.log`. Rien n'est
  écrit dans Zot.

**Bancs** (hors réseau, ni cluster ni Zot) :
- [`s1-verrou-brut-banc.sh`](s1-verrou-brut-banc.sh), quatre passages :
  - 13:11:05 UTC, copie `130069f6…` : non tenu, journal écrasé, **non archivé**. Deux KO venaient du banc (fin de ligne du rendu
    de comparaison, motif de la doublure `rpm`). Shellcheck a aussi relevé deux apostrophes typographiques dans le texte de la
    sonde (SC1112), remplacées.
  - 13:11:22 UTC, copie `937d3f0b…` : tenu ([journal](s1-verrou-brut-banc-passage2.log)). Le conseiller a ensuite demandé cinq
    corrections : résumé non fatal et placé après `SONDE_BOOT` et les journaux ; étiquette `rsaheader` en plus ; chemin du
    bootstrap par motif ; fin de `verrou-calc.log` archivée ; `df -k /w` en fin de `SONDE_BOOT`.
  - 13:14:07 UTC, copie `c86589c4…` : un KO venu du banc, la substitution de `/w` qui manquait `df -k /w`
    ([journal](s1-verrou-brut-banc-passage3.log)).
  - 13:14:15 UTC, même copie : tenu, 35 OK ([journal](s1-verrou-brut-banc.log)).
- Banc N3/N4 de la note N3/N4 ([`s1-n34-banc.sh`](s1-n34-banc.sh)) rejoué tel quel sur `c86589c4…` à 13:14:32 UTC : tenu, 35 OK
  ([journal](s1-verrou-brut-banc-n34.log)).
- Dans les journaux archivés, le dossier de travail du banc est remplacé par `<banc>`.
- Les versions et signatures des doublures (par exemple `python3-dnf-plugins-core` 4.3.0-24.el9) sont **inventées pour le
  banc** : aucune n'est une valeur relevée.
- Non couvert : vrai pod, vrai mock, vrai `rpm` (étiquettes de `--qf`), vrai podman, `kubectl`.

**Place sur `/w`, non mesurée pour cet état.** `essais` a mesuré une capacité de 3 059 832 kB, et 1034 Mo occupés après le build
`simple` avant son nettoyage ([`s1-essais.log`](s1-essais.log)). `verrou_brut` garde le buildroot et le bootstrap
(`--no-cleanup-after`), puis tire une seconde fois `rockylinux:9.7`. La ligne `df` finale le mesurera.

Suite : appliquer le correctif à `s1.sh` sur accord, puis écrire les prédictions de `verrou_brut`, puis demander l'accord de
lancement. Rien n'est lancé.

### Corrections de la note précédente, et deuxième version de `verrou_brut` (note du 2026-11-17, écrite à 2026-11-17T13:22:41Z ; rien n'est réécrit ; NON APPLIQUÉ)

Corrections de la note « Image de bootstrap : décisions, et étape `verrou_brut` préparée à sec » :
- **« Le chemin sans `uniqueext` n'est relevé dans aucun journal » est faux.** Mes deux recherches ne pouvaient pas le trouver.
  La première avait une classe de caractères sans `_`, la seconde était coupée par `head`. Le chemin figure 20 fois dans
  [`s1-verrou-mock.log`](s1-verrou-mock.log) et 9 fois dans [`s1-verrou.log`](s1-verrou.log), sous la forme
  `/w/mock/poc-rocky-9.7-pret-x86_64-bootstrap/root`. Pour `$CFG`, la forme attendue est donc, par analogie,
  `/w/mock/poc-rocky-9.7-x86_64-bootstrap/root`. Le motif `-bootstrap*/root` reste en place et affiche le chemin retenu.
- **Premier passage du banc (13:11:05 UTC)** : trois lignes KO, pour deux défauts du banc, et non « deux KO ».
- **Interpréteur des bancs.** Le banc N3/N4 de 13:14:32 UTC a tourné sous python3 3.15.2
  ([journal](s1-verrou-brut-banc-n34.log)), et non sous le 3.13.12 de ses passages précédents
  ([`s1-duree-banc-n34.log`](s1-duree-banc-n34.log)). Il avait été lancé depuis le dossier de travail, hors du dépôt, où mise
  fournit 3.13.12. « Tel quel » valait donc pour le script, pas pour l'interpréteur. Les quatre passages du banc de
  `verrou_brut` ont été lancés depuis le même dossier ; ce banc ne journalise pas la version de python.

**Deuxième version** : [`../s1-verrou-brut-2.patch`](../s1-verrou-brut-2.patch), sha256 `01fc4fc6…`. Elle remplace
[`../s1-verrou-brut.patch`](../s1-verrou-brut.patch), qui reste dans le dépôt et ne doit pas être appliqué. Toujours des
insertions seules : 4 lignes d'en-tête et 98 lignes. Copie modifiée `b7db829c…`, écrite par
[`s1-verrou-brut-2-modifier.py`](s1-verrou-brut-2-modifier.py) à partir de `5ccba38e…`. Seuls `SONDE_BOOT`, deux lignes de
commentaire et l'en-tête changent par rapport à `c86589c4…` :
- Chaque liste et le `df` valent seuls. Si le bootstrap est introuvable, si le pull échoue ou si une base est illisible, l'autre
  liste est quand même affichée, ainsi que le `df` final. La comparaison n'est faite que si les deux listes sont lues.
- La sortie d'erreur de `rpm` va dans un fichier à part, comptée et affichée (3 lignes au plus), jamais dans les listes.
- `rpm -qa` lit une copie de `var/lib/rpm` faite sous `/w` (`--dbpath`), pour le bootstrap comme pour l'image. Le montage de
  `podman image mount` n'est donc jamais écrit. `essais` n'y a lu que `os-release` ([`s1-essais.log`](s1-essais.log)) : qu'il
  soit en lecture seule ou non n'est pas vérifié ici.
- `LC_ALL=C` pour `sort` et `comm`.

**Bancs, lancés depuis le dépôt** (python3 3.13.12, d'après `python3 --version` du même dossier, non journalisé par ce banc) :
- [`s1-verrou-brut-2-banc.sh`](s1-verrou-brut-2-banc.sh). Sa section D joue `SONDE_BOOT` dans quatre cas : nominal, bootstrap
  absent, pull refusé, base rpm absente de l'image. Elle contrôle aussi que la doublure de `rpm` n'est jamais appelée sans
  `--dbpath`. Les versions de la doublure restent **inventées**.
  - 13:20:58 UTC, copie `393946ff…` : un KO venu du banc. Son contrôle « /w restant » comptait le libellé « capacité de /w »
    ([journal](s1-verrou-brut-2-banc-passage1.log)).
  - 13:21:22 UTC, copie `b7db829c…` (en-tête au nom du nouveau correctif) : tenu. La ligne du contrôle corrigé portait une
    commande inutile, retirée ensuite. Journal écrasé, **non archivé**.
  - 13:21:36 UTC, même copie : tenu, 52 OK ([journal](s1-verrou-brut-2-banc.log)).
- Banc N3/N4 rejoué sur `b7db829c…` à 13:21:37 UTC, sous python3 3.13.12 : tenu, 35 OK
  ([journal](s1-verrou-brut-2-banc-n34.log)).

**Pour les prédictions de `verrou_brut`** : il faudra comparer le sha256 du JSON archivé à la ligne « verrou : … sha256 » de la
sonde. C'est le seul moyen de voir si le filtre `jeton|token` a retiré une ligne.

Suite : appliquer `s1-verrou-brut-2.patch` à `s1.sh` sur accord. Rien n'est lancé.

## Étape `verrou_brut` appliquée au dépôt (note du 2026-11-17, écrite à 2026-11-17T13:24:29Z ; rien n'est réécrit)

Décision du propriétaire : question « J'applique s1-verrou-brut-2.patch (copie b7db829c) à s1.sh ? », réponse « Oui, applique-le ».

- `git apply` de [`../s1-verrou-brut-2.patch`](../s1-verrou-brut-2.patch) à 13:23:39 UTC (`date -u` avant et après, code 0).
  `s1.sh` passe de `5ccba38e…` à `b7db829c…`, la copie bancée.
- Le banc a été repassé sur le fichier du dépôt à 13:23:44 UTC : tenu, 52 OK
  ([journal](s1-verrou-brut-2-banc-applique.log)). Hors l'heure de fin, il ne diffère du journal de la copie
  ([`s1-verrou-brut-2-banc.log`](s1-verrou-brut-2-banc.log)) que par quatre lignes « utilisés » du `df` de la section D. Ce `df`
  porte sur le dossier du banc, sur l'hôte : la place occupée y varie d'un passage à l'autre.
- Deux lignes datées ont ensuite été ajoutées à l'en-tête, sous la description de `verrou_brut` :
  - « Correctif appliqué au dépôt le 17/11/2026 à 13:23:39 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
    (b7db829c…) ; non lancé. » ;
  - `s1.sh` vaut alors `139aab3c…`.
- Contrôles :
  - `bash -n` passe ;
  - shellcheck : 15 remarques, toutes de niveau note, aucune de niveau warning ou au-dessus ;
  - banc N3/N4 sur ce fichier à 13:24:01 UTC, sous python3 3.13.12 : tenu, 35 OK ([journal](s1-verrou-brut-2-banc-n34-applique.log)).
- Le premier correctif, [`../s1-verrou-brut.patch`](../s1-verrou-brut.patch), n'a pas été appliqué.

Suite : prédictions de `verrou_brut`, écrites et commitées avant tout passage, puis accord de lancement. Rien n'est lancé, rien
n'est écrit dans Zot.

## Étape `verrou_brut` : prédictions (note du 2026-11-17, écrite à 2026-11-17T13:32:29Z, avant tout passage ; rien n'est réécrit), NON LANCÉ

Commande prévue, depuis la racine du dépôt, sur accord nommé :
`env -u PREFIXE DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh verrou_brut`, avec `ISOLATION` non posée (`simple`,
la seule isolation qui a construit à `essais`). `s1.sh` vaut `139aab3c…`.

**Lecture de code utilisée** (mock 6.9, archive `3c034916…`), **non mesurée** :
- `buildroot.py:277` à `:303` : mock tire l'image, la copie dans le bootstrap, puis retire l'étiquette temporaire par
  `podman rmi` (`podman.py:239` à `:247`). Le commentaire de `untag` dit que l'image disparaît s'il n'en reste « aucune autre
  étiquette ». Que la référence par digest compte comme un nom, ou non, n'est pas lu. `essais` montre la ligne « Removing image
  mock-bootstrap-… » ([`s1-essais.log`](s1-essais.log), ligne 96), mais rien n'y a relu l'image ensuite.
- `buildroot_lock.py:105` à `:113` : si l'image a disparu, `inspect_hermetic_metadata` (`podman.py:262` à `:272`) lève
  `subprocess.CalledProcessError`, pas `PodmanError`. Seule `PodmanError` est attrapée (`:112`) : le crochet `postdeps`
  échouerait avant l'écriture du JSON (`:115` et `:116`). `call_hooks` n'attrape rien (`plugin.py:72` à `:81`). En tête de
  `mock.py`, une exception de ce type donne le code 1 et `log.exception` (`:1174` à `:1176`) ; le texte exact de la trace n'est
  pas lu. La sortie d'erreur de podman est capturée (`stderr=subprocess.PIPE`) sans être journalisée : en (b) ci-dessous, la
  cause de l'échec de podman ne sera pas archivée.
- `podman.py:267` écrit « Reading image … from … » juste avant cet `inspect` : c'est le repère qu'il a été atteint.
- `get_oci_digest` (`podman.py:200` à `:206`) interroge `self.image`, la référence, et non `image_id`, qui vaut `None` dans
  l'objet neuf du greffon.
- `installed_packages.py` : `gpg-pubkey` est exclu de la liste. Les adresses viennent de
  `dnf --installroot=<buildroot> repoquery -q --location`, et un paquet sans adresse fait lever « Can't get location for … »,
  une `mockbuild.exception.Error` que `mock.py` journalise par `log.error`. Les dépôts lus par ce dnf seraient ceux de la
  configuration de mock (baseurl de vault 9.7) : c'est une lecture, pas une mesure.
- Le champ `signature` du verrou garde les 8 derniers caractères de `%{sigpgp:pgpsig}`, ou `null` si la valeur est « (none) ».
- `buildroot_lock.py:38` : l'état s'appelle « Generating the buildroot lockfile: buildroot_lock.json ». mock affiche ses états
  en « Start: … » (lignes « Start: build setup … » de [`s1-verrou.log`](s1-verrou.log)).

| # | Prédiction | Confiance et raison |
|---|---|---|
| VB1 | Pod `s1-05-verrou-brut` prêt ; sources livrées, `rc 0` ; `mock --debug-config : rc 0` | Haute : mêmes gestes qu'`essais` et `verrou`, tenus |
| VB2 | « configuration : bootstrap_image_ready absent de --debug-config, donc valeur par défaut (False) » ; « options bootstrap_* qui annulent « prête », posées : 0 » | Moyenne : `--debug-config` n'écrit que les clés qui diffèrent du défaut (`mock.py:603` à `:620`), et `False` est le défaut |
| VB3 | `mock --buildsrpm (image brute) : rc 0` ; src.rpm `sample-app-1.0.0-2.el9.src.rpm`, sha256 `c802e60a…` (troisième fois) | Haute : tenu à `essais` en `simple` avec la même configuration, et à `verrou` |
| VB4 | Après `--buildsrpm`, `root.log` porte au moins une ligne « Bootstrap image not marked ready » et aucune « Not updating bootstrap chroot » | Haute : mesuré à `essais` avec la même configuration ([`s1-essais.log`](s1-essais.log), lignes 98 et 113 ; `buildroot.py:1176`). Le compte cumulé après le calcul n'est pas prédit (deux lectures possibles, note de `verrou`) |
| VB5 | Le calcul atteint l'écriture du verrou : une ligne « Start: Generating the buildroot lockfile: buildroot_lock.json » dans la fin de `verrou-calc.log` archivée (`s1-verrou_brut-mock.log`) ; aucune ligne « builddep command missing » | Moyenne. Preuve indirecte que `builddep` sera là : à `essais`, `simple` a fait `--rebuild : rc 0` (ligne 137), `rebuild` appelle `builddep` (lecture), et son absence a fait échouer `verrou`. La commande d'installation du greffon (ligne 116 d'`essais`) est celle du passage `nspawn`, qui a échoué : elle ne prouve pas l'installation |
| VB6 | **Pas de pari sur la branche finale du calcul.** (a) L'image survit au `rmi` : `rc 0`, un seul `buildroot_lock.json`. (b) Elle a disparu : `rc` non nul (1 d'après la lecture), « Reading image » présent, puis une trace dans la fin de `verrou-calc.log` ; la ligne brute fait foi, aucun texte n'est prédit. (c) Une adresse manque : `rc` non nul, une ligne « Can't get location for … », « Reading image » absent. Dans les trois cas, « aucun verrou produit » hors de (a). Une autre cause est notée telle quelle | Faible : le sort d'une image tirée par digest, après `podman rmi` de son étiquette, n'est ni lu ni mesuré ; (c) est jugée moins probable que (a) et (b), sans chiffre |
| VB7 | Branche (a) : « version du verrou : 1.1.0 » ; les sept options de V13 ; « bootstrap_image enregistré » égal à `$BOOT` (`sc-stockage.poc.test:5000/amont/rockylinux/rockylinux@sha256:ee90dc0e…`) ; « bootstrap_image_ready enregistré : False » ; « macros recopiées : oui » | Haute pour la version, `False` et les macros (code lu) ; moyenne pour la liste des sept |
| VB8 | Branche (a) : « bootstrap, champs : architecture, id, image_digest, pull_digest » ; `pull_digest` `sha256:ee90dc0e…` ; architecture `amd64` ; `image_digest` est un sha256 différent de `pull_digest` | Moyenne : clés de la requête de `podman.py:266` plus `image_digest` ; `.Digest` d'une image tirée par digest non mesuré |
| VB9 | Branche (a) : « rpm du buildroot : N », N entre 150 et 400 (V5) ; « rpm avec url : N sur N » ; préfixes des url sous `dl.rockylinux.org/vault/rocky/9.7/`, aucun sous `/extras/` | Moyenne : dépôts de la configuration lus, pas la requête réelle |
| VB10 | Branche (a) : signatures. **Pas de pari** entre `350d275d` partout et `None` partout : cela dépend de la présence de l'étiquette `SIGPGP` dans les rpm de Rocky, que `SONDE_BOOT` affiche à côté de `RSAHEADER`. Aucune autre valeur | Faible : type de signature des rpm de Rocky 9 non lu |
| VB11 | Branche (a) : intégrité. Le sha256 de `s1-verrou_brut.json` est égal à celui de la ligne « verrou : buildroot_lock.json … sha256 » de la sonde | Haute : aucun mot filtré attendu dans un verrou ; c'est le seul contrôle du filtre `jeton\|token` |
| VB12 | `SONDE_BOOT`, dans toutes les branches où le bootstrap existe : « 1 chemin(s) », chemin retenu `/w/mock/poc-rocky-9.7-x86_64-bootstrap/root` ; les deux listes lues, `rpm -qa rc 0`, « stderr 0 ligne(s) », chacune avec plus de 100 lignes ; podman pull `rc 0`. Elle suppose que `var/lib/rpm` est un vrai dossier dans les deux racines : un échec silencieux se verrait par « 0 ligne(s) » avec `rc 0` | Moyenne : chemin par analogie avec `…-pret-x86_64-bootstrap/root` (journaux de `verrou`) ; `--no-cleanup-after` lu dans le code, pas mesuré ; nombre de paquets d'une image Rocky non relevé, seuil de 100 choisi large |
| VB13 | « seulement dans le bootstrap de mock » : `python3-dnf-plugins-core.noarch` en fait partie, et au moins l'une de ses deux étiquettes de signature porte `Key ID 702d426d350d275d`. « seulement dans rockylinux:9.7 brut » : aucune ligne (rien de retiré ni de mis à jour) | Moyenne pour la présence du greffon ; faible pour « aucune ligne » : une mise à jour de `python3-dnf`, tirée par les dépendances, n'est pas exclue |
| VB14 | Durées : `--buildsrpm` entre 20 et 300 s (53 s à `essais`, 50 s à `verrou`) ; `--calculate-build-dependencies` entre 10 et 300 s (`--rebuild` de 43 s à `essais`) | Moyenne |
| VB15 | Place : « capacité de /w : 3059832 kB » (comme `essais`) ; « utilisés » entre 800 000 et 2 500 000 kB ; aucune ligne « No space left on device » | Moyenne : 1034 Mo mesurés par `du` à `essais` après un build complet ; ici sans build, mais avec un second pull ; `du` et `df` ne comptent pas pareil |
| VB16 | Sondes complètes : les deux `dans` finissent par « (code de l'exec : 0) » ; « journaux de mock : … lignes » ; « pod s1-05-verrou-brut supprimé ». Les sondes finissent par `true` : le code 0 seul ne prouve rien | Moyenne |

Observation sans prédiction : la durée du second `podman pull` de `SONDE_BOOT`, comparée aux 7 s d'`essais`, pourra indiquer si
l'image était encore là après le `rmi` de mock. Ce ne sera qu'un indice.

Ce que la mesure apportera pour la suite :
- La liste de `SONDE_BOOT` (VB12, VB13) sort dans toutes les branches où le bootstrap existe. Elle donne les paquets à épingler
  dans l'image dérivée.
- En (b) ou (c), l'image dérivée suivrait le même chemin de code ; elle ne suffirait donc pas non plus, d'après la lecture. La
  décision reviendrait au propriétaire.
- La coupure de la référence au port du registre (`config.py:844`) ne joue qu'en mode hermétique : elle reste hors de cette
  mesure.

## Étape `verrou_brut` : résultat (note du 2026-11-17, écrite à 2026-11-17T13:41:16Z ; rien n'est réécrit)

Passage sur accord « Oui, lance verrou_brut », le 17/11/2026 de 13:34:25 à 13:36:06 UTC (`date -u` du lancement et
[`chrono.tsv`](chrono.tsv)), code 0. Commande : `env -u PREFIXE -u ISOLATION DISTRO=rke2 KUBECONFIG=… mise exec --
poc/bricks/05-rpm-mock/s1.sh verrou_brut`, `s1.sh` à `139aab3c…`. Journaux : [`s1-verrou_brut.log`](s1-verrou_brut.log),
[`s1-verrou_brut-mock.log`](s1-verrou_brut-mock.log) (482 lignes) et le verrou [`s1-verrou_brut.json`](s1-verrou_brut.json).

**Le calcul a abouti : c'est la branche (a), un verrou écrit**, sur un passage. mock a installé lui-même `builddep` dans le
bootstrap, puis a écrit `buildroot_lock.json` (111 563 octets). Avec `bootstrap_image_ready = False`, ce verrou est
inutilisable par `--hermetic-build` (`config.py:824`, lecture) : il sert de référence pour la suite.

| # | Résultat |
|---|---|
| VB1 | **Tenue.** Pod prêt, sources `rc 0`, `--debug-config` `rc 0`. |
| VB2 | **Tenue.** `bootstrap_image_ready` absent de `--debug-config` (valeur par défaut, `False`) ; 0 option qui annule « prête ». |
| VB3 | **Tenue.** `--buildsrpm (image brute)` `rc 0` ; src.rpm `c802e60a…`, le même pour la troisième fois. |
| VB4 | **Tenue.** Après `--buildsrpm`, une ligne « Bootstrap image not marked ready » (`buildroot.py:1176`), aucune « Not updating bootstrap chroot ». Après le calcul, le compte cumulé reste 1, comme à `verrou`. |
| VB5 | **Tenue.** « Start: Generating the buildroot lockfile: buildroot_lock.json » puis « Finish: … » (lignes 473 et 477 du journal de mock) ; aucune ligne « builddep command missing ». La preuve que le greffon était là est maintenant directe : `python3-dnf-plugins-core` figure dans le bootstrap et pas dans l'image (VB13). |
| VB6 | **Branche (a), mesurée** (pas de pari) : `--calculate-build-dependencies` `rc 0` en 26 s, un seul `buildroot_lock.json`. « Reading image … » est présent (lignes 349 et 475) : l'`inspect` du greffon a réussi. Le `rmi` qui le précède est lu dans le code et vu à `essais`, pas dans ce passage (voir les observations) ; le pod est supprimé, ce point n'est plus vérifiable. Ni trace, ni « Can't get location ». |
| VB7 | **Tenue.** Version 1.1.0 ; les sept options de V13 ; `bootstrap_image` égal à `$BOOT` (`…@sha256:ee90dc0e…`) ; `bootstrap_image_ready` `False` ; macros recopiées (7 macros). |
| VB8 | **Tenue.** Champs `architecture, id, image_digest, pull_digest` ; `pull_digest` `sha256:ee90dc0e…` ; `amd64` ; `image_digest` `fdd27347…`, différent. L'`id` vaut `9e021fde…`, l'identifiant d'image démonté à `essais` ([`s1-essais.log`](s1-essais.log), ligne 95). |
| VB9 | **Tenue.** 222 rpm dans le buildroot (V5 : 150 à 400) ; 222 sur 222 avec une url, toutes sous `https://dl.rockylinux.org/vault/rocky/9.7/` : 129 dans BaseOS, 93 dans AppStream, aucune sous `/extras/`. |
| VB10 | **Branche « None partout », mesurée** (pas de pari) : les 222 `signature` valent `null`. Dans `SONDE_BOOT`, les 14 lignes affichées (ajouts et mises à jour) portent `sigpgp=(none)` et une signature `rsaheader` (clé `702d426d350d275d`) ; les 143 lignes communes ne sont pas affichées. Pour le buildroot, `null` vient de « (none) » d'après la lecture de `installed_packages.py` ; les lignes brutes de la requête de mock qui figurent dans les 400 dernières lignes archivées de `root.log` (93 lignes, par exemple les lignes 55 et 58) finissent toutes par `(none)`. Les rpm de Rocky lus ici n'ont donc qu'une signature d'en-tête, que le champ `signature` de mock ne lit pas. `sigmd5` est rempli pour les 222. |
| VB11 | **Tenue.** sha256 de `s1-verrou_brut.json` `57cb190f…`, égal à la ligne de la sonde ; 111 563 octets des deux côtés. Le filtre `jeton\|token` n'a rien retiré. |
| VB12 | **Tenue.** Un chemin, `/w/mock/poc-rocky-9.7-x86_64-bootstrap/root` ; listes de 153 (bootstrap) et 147 (image) lignes, `rc 0`, stderr 0 ligne ; pull `rc 0`. |
| VB13 | **Tenue pour le greffon, non tenue pour « aucune ligne ».** Voir le détail plus bas. |
| VB14 | **Tenue.** `--buildsrpm` 67 s (20 à 300) ; calcul 26 s (10 à 300). |
| VB15 | **Tenue.** Capacité 3 059 832 kB ; 1 850 684 kB utilisés en fin de `SONDE_BOOT` (800 000 à 2 500 000) ; aucun « No space left on device ». |
| VB16 | **Tenue.** Les deux sondes finissent par « (code de l'exec : 0) » ; « journaux de mock : 482 lignes » ; pod supprimé. |

**VB13 en détail : ce que mock ajoute à `rockylinux:9.7` brut** (base de l'épinglage de l'image dérivée). 143 lignes communes.
Six paquets ajoutés :
- `dbus-libs-1:1.12.20-8.el9.x86_64` ;
- `python3-dateutil-1:2.9.0.post0-1.el9_7.noarch` ;
- `python3-dbus-1.2.18-2.el9.0.1.x86_64` ;
- `python3-dnf-plugins-core-4.3.0-24.el9_7.noarch` ;
- `python3-six-1.15.0-9.el9.noarch` ;
- `python3-systemd-234-19.el9.x86_64`.

Quatre paquets mis à jour, de `4.14.0-31.el9` vers `4.14.0-31.el9.rocky.0.1` : `dnf`, `dnf-data`, `python3-dnf` et `yum`. C'est
ce qui fait tomber « aucune ligne ». Tous portent une signature d'en-tête de la clé `702d426d350d275d`. Le dépôt d'origine de
chacun n'est pas lu : les lignes d'installation du bootstrap sont hors des 400 dernières lignes de `root.log` archivées. La
version de la doublure du banc (4.3.0-24.el9) avait été écrite avant ce passage, sans source ; elle n'a servi à rien ici.

**Observations, sans prédiction :**
- Le second `podman pull` de `SONDE_BOOT` a pris 0 s, contre 7 s à `essais`. C'est un indice, et seulement un indice, que
  l'image était encore là après le `rmi` de mock. L'`inspect` réussi de VB6 va dans le même sens.
- La ligne « Removing image » de ce passage n'est pas dans les journaux archivés : on ne sait pas si mock a refait le pull et le
  `rmi` pour le calcul ou réutilisé le bootstrap de `--buildsrpm`.

**Ce que cela change pour la suite** (lecture et un seul passage) :
- **Ces dix lignes sont la référence pour l'image dérivée** : ce que mock applique, pas forcément ce qui est nécessaire. La
  cause des quatre mises à jour n'est pas lue : une exigence du greffon, ou la commande d'installation de mock, qui nomme aussi
  `python3-dnf` (`dnf4_install_command`, [`m2-releve9.log`](m2-releve9.log), ligne 39). La décision consignée disait
  « plus `python3-dnf-plugins-core` » : le choix entre les six ajouts seuls et les dix lignes reste ouvert, et revient au
  propriétaire.
- **Rien d'autre ne bloque, sur ce passage, avant l'écriture du verrou.** Le `podman image inspect` du greffon et les adresses
  des paquets ont réussi. La coupure de la référence au port du registre (`config.py:844`) ne joue qu'en mode hermétique : elle
  reste à mesurer.
- **Le verrou ne porte aucune clé de signature.** Le champ `signature` est vide pour tous les rpm de Rocky lus ici. M2 devait déjà
  vérifier les signatures par nous : `mock-hermetic-repo` ne vérifie ni GPG ni somme (N6r de `releve2`,
  [`m2-predictions.md`](m2-predictions.md)), et le mode hermétique met `gpgcheck=0`. Le verrou n'y aidera pas par ce champ ;
  `sigmd5` est présent.

Retiré : le pod `s1-05-verrou-brut`. La suppression est demandée en fin d'étape (`--wait=false`) ; un
`kubectl get pod` à 13:40:06 UTC répond NotFound (vu à l'écran, non archivé). Rien n'est écrit dans Zot.

**Prédictions de `verrou` restées sans mesure** (V4, V5, V14, V17, EX2) : ce passage, sous `$CFG` et non sous l'image prête,
montre des macros recopiées (V4 et V14), 222 rpm dans le buildroot (V5), aucune url sous `/extras/` (EX2), et des `signature`
à `null`, ce qui contredit V17 (`350d275d`) par le même mécanisme qu'en VB10. Elles ne sont pas déclarées tranchées pour
l'image prête.

**Commande** : elle diffère de la commande prévue par `-u ISOLATION`, qui écarte une variable héritée, et par
`KUBECONFIG=…`, posé comme au passage de `verrou`. L'isolation affichée est `simple`, la valeur par défaut prévue : aucun effet
visible.

Suite : la construction de l'image dérivée est une nouvelle étape, avec son correctif, ses prédictions et deux accords, l'un
pour la construction et l'autre pour l'écriture dans Zot.

## Image dérivée : décision « Dix lignes » (note du 2026-11-17, écrite à 2026-11-17T13:53:33Z ; rien n'est réécrit)

Décision du propriétaire : question « L'image dérivée reprend-elle les dix lignes mesurées ou les six ajouts seuls ? »,
réponse « Dix lignes », lue avant 13:53:33 UTC. Recommandation présentée : dix ; le conseiller, consulté, recommande aussi dix.

**Lectures de code faites avant la question** (mock 6.9, non mesurées) :
- Dans le bootstrap, mock lance une seule commande de paquets : `dnf4_install_command`, soit
  `install python3-dnf python3-dnf-plugins-core` (`config.py:379`, `buildroot.py:593` à `:595`). C'est la commande vue à
  `essais` ([`s1-essais.log`](s1-essais.log), ligne 116).
- `mock.py:777` met `update_before_build = False` pour le bootstrap. Le « Start: dnf4 update » de
  [`s1-verrou_brut-mock.log`](s1-verrou_brut-mock.log) (ligne 464) porte sur le buildroot : il suit « Start: chroot init »
  (ligne 449), sans « (bootstrap) ».
- Avec une image prête, `_init_pkg_management` sort tout de suite (`buildroot.py:590` et `:591`) : le dnf de l'image est
  celui qui tourne.

**Non lus** : la cause exacte des quatre mises à jour (dnf qui prend la version de vault en installant `python3-dnf`, ou une
exigence du greffon) ; les `Requires` de `python3-dnf-plugins-core` ; le dépôt d'origine de chacun des dix paquets.

**Pourquoi dix** : c'est le seul état où le calcul a abouti, sur un seul passage (`verrou_brut`). Les six ajouts seuls
associeraient le dnf d'origine (`4.14.0-31.el9`) au greffon, ce qui n'a jamais tourné. Les dix lignes sont la référence, pas
forcément le nécessaire. Aucun argument de sécurité n'est retenu pour `rocky.0.1` : son changelog n'est pas lu.

**L'image dérivée** : `rockylinux:9.7` (`sha256:ee90dc0e…`, depuis Zot) plus ces dix paquets, aux versions exactes de
[`s1-verrou_brut.log`](s1-verrou_brut.log), toutes signées en en-tête par la clé `702d426d350d275d` :
- six ajouts : `dbus-libs-1:1.12.20-8.el9.x86_64`, `python3-dateutil-1:2.9.0.post0-1.el9_7.noarch`,
  `python3-dbus-1.2.18-2.el9.0.1.x86_64`, `python3-dnf-plugins-core-4.3.0-24.el9_7.noarch`, `python3-six-1.15.0-9.el9.noarch`,
  `python3-systemd-234-19.el9.x86_64` ;
- quatre mises à jour vers `4.14.0-31.el9.rocky.0.1` : `dnf`, `dnf-data`, `python3-dnf`, `yum`.

**À porter dans l'étape de construction** (nouvelle étape, préparée à sec, avec correctif, banc, prédictions et deux accords) :
- épingler les dix versions exactes et vérifier leur signature d'en-tête ;
- prédire que la liste `rpm -qa` de l'image dérivée a les mêmes différences avec `rockylinux:9.7` brut que le bootstrap de
  `verrou_brut` (153 lignes, 143 communes) ;
- archiver `rpm -q --requires python3-dnf-plugins-core`, qui répondra à la question des `Requires` sans téléchargement à part.

Suite : préparation à sec de l'étape de construction. Rien n'est lancé, rien n'est écrit dans Zot.

## Image dérivée : trois étapes préparées à sec (note du 2026-11-17, écrite à 2026-11-17T14:18:41Z ; rien n'est réécrit), NON APPLIQUÉ

Décision du propriétaire : question « Je prépare à sec le correctif des trois étapes ? », réponse « Oui, prépare-le ».

**Correction de la note de décision précédente.** Elle annonçait une étape de construction « avec deux accords ». Il en faut
trois, un par lancement : `hote97` (hôte seul, téléchargement de métadonnées publiques de vault 9.7), `boot_racine` (pod, rien
poussé) et `boot_image` (écriture dans Zot). `hote97` est une étape à part et non un rejeu de `hote`, qui réécrirait les relevés
de 9.8 et d'EPEL liés à `racine.tar`.

**Correctif** : [`../s1-derivee.patch`](../s1-derivee.patch) (sha256 `cec93810…`), insertions seules (en-tête 10 lignes,
variables 7, étapes 206), produit par [`s1-derivee-modifier.py`](s1-derivee-modifier.py) ; copie bancée `ee611aac…`.
- `hote97` : clé de Rocky relue (empreinte), puis `depot_hote` pour BaseOS, AppStream, CRB et extras de vault 9.7 (repomd.xml
  vérifié par gpgv, primary contrôlé par repomd), comparés au relevé de `hote`. Pour chacun des dix paquets, dépôt et sha256 tirés
  du primary, avec arrêt si l'un manque ou porte deux empreintes ; `Requires` de `python3-dnf-plugins-core` affichés.
- `boot_racine` : pod de l'image d'essai ; racine de `rockylinux:9.7` copiée depuis `podman image mount` (le montage n'est jamais
  écrit) ; `dnf-3 --installroot` des dix NEVRA exacts, avec `--setopt=reposdir=/w/aucun` en ligne de commande et
  `dnf97.conf` (quatre dépôts de vault 9.7 en baseurl fixes, `gpgcheck=1`, `repo_gpgcheck=1`, `best=1`, `install_weak_deps=0`).
  Sont affichés : la transaction, les rpm téléchargés et leur sha256, `rpm -K`, `gpg-pubkey` avant et après, les listes
  `rpm -qa` complètes avant et après et leurs différences, et les `Requires` du greffon installé. Avant l'archive, la sonde ne
  retire que `/w` de la racine, seul dossier qu'elle y ajoute ; `var/cache/dnf` de l'image de base est gardé (base plus dix
  paquets) et son nombre d'entrées est affiché. Sur l'hôte, l'archive ne sort du pod que si les quatre repomd sont égaux à ceux de
  `hote97`, si `rpm -K` donne « 10 OK sur 10 » et si les rpm téléchargés sont exactement les dix de `hote97`, empreintes
  comprises. Le pod est retiré à chaque arrêt décidé après la sonde ; un échec de `pod_demarrer` ou de `livrer` sort sans retrait
  (`set -e`). Aucune archive d'un passage précédent ne survit : elle est effacée au début de l'étape.
- `boot_image` : vérifie que l'archive a le sha256 noté par `boot_racine`, puis `crane append` d'une couche pleine vers
  `essais-05/rocky9-bootstrap:<PREFIXE>`, `crane mutate` (plateforme `linux/amd64`, annotations
  `org.opencontainers.image.base.name` et `.base.digest` = `ee90dc0e…`). Le dépôt sera définitif : Zot n'autorise pas la
  suppression. Lecture anonyme : dans [`zot.json`](../../08-trust-plane/stockage/zot.json) du dépôt, le motif `**` porte
  `anonymousPolicy` `read`, qui couvre `essais-05/**` (lecture de la configuration commitée ; la configuration déployée n'est pas
  relue, et aucun podman de pod n'a encore tiré un dépôt `essais-05/`).

**Lu ou vérifié pendant la préparation, sans lancement** :
- L'image d'essai n'a pas `/usr/bin/dnf`, seulement `/usr/bin/dnf-3` (`tar -tf` de `racine.tar`, `d7433a05…`).
  [`s1-racine.log`](s1-racine.log) cite `python3-dnf-4.14.0-34.el9_8.rocky.0.1` et aucun rpm `dnf` ; que `dnf-3` vienne de
  `python3-dnf` est une déduction, non lue. La sonde appelle donc `dnf-3`, comme mock. La
  première copie (`99440237…`) appelait `dnf` : ce défaut du correctif a été vu à la relecture, pas par le banc, dont la
  doublure s'appelait alors `dnf`. Les autres commandes de la sonde sont toutes dans `/usr/bin` de `racine.tar` (section I).
- `rocky-9.tpl` complet de mock 6.9-1 (archive de M2, `3c034916…`) : pas de `tsflags` ; `best=1` et `install_weak_deps=0` ;
  dépôts actifs baseos, appstream, crb et extras. `dnf97.conf` reprend ces options et ces quatre dépôts.
- `crane` 0.20.6 : `mutate` accepte `-a, --annotation` (aide de la commande).

**Banc** [`s1-derivee-banc.sh`](s1-derivee-banc.sh), sections A à I, sans réseau extérieur (un registre crane en loopback pour G) :
- passage final le 17/11/2026 à 14:17:56 UTC sur la copie `ee611aac…`, python3 3.13.12 : tenu, 151 OK
  ([journal](s1-derivee-banc.log)) ; shellcheck : 15 remarques sur le dépôt, 17 sur la copie, aucune de niveau warning ou au-dessus ;
- N3/N4 ([`s1-n34-banc.sh`](s1-n34-banc.sh), inchangé) sur la même copie à 14:17:59 UTC : tenu, 35 OK
  ([journal](s1-derivee-banc-n34.log)) ;
- passages précédents, archivés :
  - 14:07:45 UTC, copie `99440237…` : NON TENU, 4 KO, tous des défauts du banc (lignes préfixées du journal de `verrou_brut` non
    lues, motif de fonction trop strict) ([journal](s1-derivee-banc-passage1.log)) ;
  - 14:07:58 UTC, même copie : tenu, 117 OK, sur la copie qui appelait encore `dnf` ([journal](s1-derivee-banc-passage2.log)) ;
  - 14:12:45 UTC, copie `05cc0086…`, banc étendu (G2, H, I) : NON TENU, 15 KO, tous des défauts du banc (motif `dnf` qui prenait
    un commentaire, catalogue vide de crane écrit `null` et non `[]`, sonde non chargée dans le harnais de H)
    ([journal](s1-derivee-banc-passage3.log)). Dans ce passage, un contrôle de H1 a passé à tort en comparant deux chaînes vides ;
    il a été resserré pour le passage suivant ;
  - 14:13:09 UTC, copie `05cc0086…` : tenu, 149 OK ([journal](s1-derivee-banc-passage4.log)), et N3/N4 à 14:13:26 UTC : tenu,
    35 OK ([journal](s1-derivee-banc-n34-passage1.log)). Cette copie retirait aussi `var/cache/dnf` de la racine ; la relecture a
    jugé que ce dossier pouvait venir de l'image de base : le retrait est abandonné, d'où la copie `ee611aac…`.
- Le banc et le modificateur archivés sont les versions finales ; les versions intermédiaires ne sont pas gardées.
- **Bornes** : 151 OK sur des doublures, sans vrai dnf, rpm ou podman, sans kubectl, sans vault 9.7 et sans Zot. G ne montre la
  plateforme et les annotations que sur une archive factice de 10 240 octets, en loopback. Le passage en loopback avec la vraie
  archive reste à faire entre `boot_racine` et l'accord d'écriture dans Zot.

**Non lus, à mesurer** : qu'un `dnf install` d'un NEVRA exact fasse la montée de version d'un paquet présent ; qu'un dnf de 9.8
en `--installroot` donne le même état que le dnf du bootstrap dans le chroot ; si dnf importe la clé dans la racine
(`gpg-pubkey`) ; les `Requires` réels du greffon (lus par `hote97`).

Suite : appliquer `s1-derivee.patch` à `s1.sh` sur accord. Rien n'est lancé, rien n'est écrit dans Zot.

## Image dérivée : `s1-derivee.patch` appliqué au dépôt (note du 2026-11-17, écrite à 2026-11-17T14:21:24Z ; rien n'est réécrit)

Décision du propriétaire : question « J'applique s1-derivee.patch (copie ee611aac) à s1.sh ? », réponse « Oui, applique-le ».

- `git apply` de [`../s1-derivee.patch`](../s1-derivee.patch) à 14:19:43 UTC (`date -u` avant et après, code 0). `s1.sh` passe de
  `139aab3c…` à `ee611aac…`, la copie bancée.
- Banc repassé sur le fichier du dépôt à 14:20:05 UTC : tenu, 151 OK ([journal](s1-derivee-banc-applique.log)). Le banc compare
  le fichier à l'ancien `s1.sh` (`139aab3c…`), placé dans un arbre de travail du scratchpad (`<avant>` dans le journal) avec une
  copie de `mise.toml` (même `crane` 0.20.6) et un lien vers `resultats/`. Hors des deux premières lignes, il diffère du journal
  de la copie ([`s1-derivee-banc.log`](s1-derivee-banc.log)) par 17 lignes, toutes attendues : 3 lignes « utilisés » du `df` de
  la section D (dossier du banc, sur l'hôte) ; 9 lignes d'empreintes des archives de D et H (la sonde lance `tar` sans
  `--mtime` sur des fichiers que le banc recrée à chaque passage : cause probable, non vérifiée) ; 4 lignes de G (empreinte de
  l'archive factice, couche et digest d'image ; cause probable, non vérifiée : heures des en-têtes `posix`) ; l'heure de fin.
- Deux lignes datées ajoutées ensuite à l'en-tête, sous la description de `boot_image` : « Correctif appliqué au dépôt le
  17/11/2026 à 14:19:43 UTC (« Oui, applique-le »), sha256 égal à la copie bancée (ee611aac…) ; non lancé. ». `s1.sh` vaut alors
  `2b0a3b7b…`.
- Contrôles sur ce fichier : `bash -n` passe ; shellcheck : 17 remarques, aucune de niveau warning ou au-dessus ; banc N3/N4 à
  14:20:21 UTC, python3 3.13.12 : tenu, 35 OK ([journal](s1-derivee-banc-n34-applique.log)).

Suite : prédictions des trois étapes, écrites et commitées avant tout passage, puis un accord par lancement (`hote97`, puis
`boot_racine`, puis `boot_image` après un passage en loopback avec la vraie archive). Rien n'est lancé, rien n'est écrit dans Zot.

## Image dérivée : prédictions de `hote97`, `boot_racine` et `boot_image` (note du 2026-11-17, écrite à 2026-11-17T14:29:22Z, avant tout passage ; rien n'est réécrit), NON LANCÉ

Commandes prévues, depuis la racine du dépôt, chacune sur son accord nommé :
`env -u PREFIXE -u ISOLATION DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/s1.sh hote97`, puis `… boot_racine`,
puis `… boot_image`. `s1.sh` vaut `2b0a3b7b…`. Journaux prévus : `s1-hote97.log`, `s1-boot_racine.log`, `s1-boot_image.log`.
`boot_image` ne sera proposé qu'après un passage en loopback avec la vraie archive ; le script de ce passage reste à écrire, avec
ses propres prédictions.

**Appuis** (mesures archivées) :
- `hote` du 17/11/2026 à 08:30:27 UTC ([`s1-3-hote.log`](s1-3-hote.log), lignes 23 à 30) : les quatre `repomd.xml` de vault 9.7
  sont signés par `21CB256A…350D275D` ; sha256 BaseOS `fa6d5054…`, AppStream `06f01d40…`, CRB `3936113e…`, extras `54ec0c53…`.
  L'étape entière a duré 15 s (`chrono.tsv`).
- `verrou_brut` ([`s1-verrou_brut.log`](s1-verrou_brut.log)) : `rockylinux:9.7` brut, 147 lignes `rpm -qa`, stderr 0 ; bootstrap
  de mock, 153 lignes ; 143 communes ; dix lignes seulement dans le bootstrap, quatre seulement dans l'image, aucune `gpg-pubkey`
  parmi elles ; `podman pull` et `podman image mount` de l'image brute `rc 0` ; « capacité de /w : 3059832 kB ». `--buildsrpm`,
  qui comprend l'installation de dnf et du greffon dans le bootstrap depuis vault 9.7, a pris 67 s.
- `racine` ([`s1-racine.log`](s1-racine.log)) : dans une racine neuve, `dnf --installroot` avec `gpgcheck=1`, puis
  `rpm --root … -K` : « 199 OK sur 199 » (ligne 210). Cela suppose la clé dans la base rpm de la racine : c'est une déduction.
  Installation de 201 paquets en 5694 s, cause inconnue (P7 non tenue).
- `image` ([`s1-image.log`](s1-image.log)) : image d'essai `99790c13…`, couche de la racine 140 611 406 octets ; 11 s entre
  « 05 S1 image » et « fait » (`chrono.tsv`).
- Banc de `s1-derivee.patch` ([`s1-derivee-banc-applique.log`](s1-derivee-banc-applique.log)) : `dnf-3` présent et `/usr/bin/dnf`
  absent dans `racine.tar` ; plateforme et annotations posées par `crane` 0.20.6 sur une archive factice.
- **Jamais exécuté** : le `dnf-3` de l'image d'essai (`python3-dnf-4.14.0-34.el9_8`). `racine` a lancé le dnf de l'amorce 9.8 ;
  à `essais`, mock lance `/usr/bin/dnf-3` dans le bootstrap (`systemd-nspawn -D …-bootstrap…`, [`s1-essais.log`](s1-essais.log),
  lignes 106 et 116), donc le dnf de `rockylinux:9.7`. `repo_gpgcheck=1` n'a donc jamais tourné dans cette image.
- Préalables relevés par leur nom le 17/11, avant cette note (`test -s`, sans lister `$T`) : clé de Rocky, trousseau, les quatre
  `v97-<dépôt>.repomd.xml` d'`hote` (sha256 égaux aux valeurs ci-dessus), `docker/config.json` et `image.digest` sont présents.

| # | Prédiction | Confiance et raison |
|---|---|---|
| DH1 | `hote97` : « OK   empreinte de la clé de Rocky (relevée par hote) : 21CB256AE16FC54C6E652949702D426D350D275D » | Haute : même fichier que `hote` du 17/11 |
| DH2 | Pour BaseOS, AppStream, CRB et extras : `repomd.xml` signé par la clé primaire, primary « contrôlé par repomd.xml », « repomd.xml égal au relevé de hote : oui » ; sha256 égaux à ceux d'`hote` ci-dessus | Haute : vault 9.7 est figé, relevé du matin même |
| DH3 | Dix lignes « OK » et aucune « KO » ; chaque paquet dans un seul dépôt, sans pari sur lequel ; `derivee.sha256` écrit, dix lignes | Moyenne à haute : mock les a installés depuis ces quatre dépôts, les seuls actifs de sa configuration (lecture) |
| DH4 | « requires de python3-dnf-plugins-core : N entrée(s) », N au moins 1, dont au moins une entrée `python3-dnf` ; pas de pari sur l'opérateur ni la version | Moyenne : le contenu des `Requires` n'est pas lu |
| DH5 | Moins de 120 s entre « 05 S1 hote97 » et « 05 S1 hote97 fait » | Moyenne : 15 s pour `hote` ; le primary d'AppStream est gros |
| DR1 | `boot_racine` : pod `s1-05-boot-racine` prêt, image `…/essais-05/mock-rocky9@sha256:99790c13…` ; trois livraisons sans erreur ; première ligne de la sonde « dnf-3 : 4.14.0 … » | Haute pour le pod (mêmes gestes que `verrou_brut`) ; moyenne pour la ligne de version, dont le format n'est pas relevé |
| DR2 | `podman pull` `rc 0`, `podman image mount` `rc 0` ; « copie de la racine de rockylinux:9.7 : rc 0 », taille entre 100 000 et 500 000 kB | Haute pour les codes (mêmes gestes que `SONDE_BOOT`) ; faible pour la taille, non relevée |
| DR3 | « dépôts de la racine, écartés » : au moins un fichier `.repo` ; « racine avant : rpm -qa 147 ligne(s), stderr 0 ligne(s) » | Haute : même image, même requête ; la base est lue par `--root` et non sur une copie par `--dbpath` |
| DR4 | `gpg-pubkey` avant et après : **pas de pari**. Après, la clé `350d275d` est là si dnf l'importe ou si l'image l'avait | `racine` suggère un import dans la racine (DR7) ; `verrou_brut` n'en montre aucun ajout dans le bootstrap de mock, mais les 143 lignes communes ne sont pas archivées |
| DR5 | « makecache : rc 0 » ; sur l'hôte, quatre lignes « OK   repomd … lu par dnf dans le pod = repomd vérifié sur l'hôte » | Moyenne : mêmes url, vault figé, contrôle tenu à `racine` ; mais le `dnf-3` de l'image d'essai et son `repo_gpgcheck=1` n'ont jamais tourné |
| DR6 | « installation : rc 0 » ; transaction : six paquets sous « Installing » et quatre sous « Upgrading », rien d'autre ; résumé « Install  6 Packages » et « Upgrade  4 Packages » | Moyenne : c'est ce qu'a fait mock, mais ici avec le dnf de 9.8 de l'image d'essai en `--installroot` et des NEVRA exacts (montée de version non lue) |
| DR7 | Dix lignes `rpm <fichier> <sha256>` ; « rpm -K : 10 OK sur 10 » ; sur l'hôte « OK   rpm téléchargés conformes aux dix de hote97 : 10 sur 10, 10 téléchargé(s) » | Moyenne : suit DR6 ; `rpm -K` dépend de la clé dans la racine (DR4), tenu à `racine` |
| DR8 | « seulement dans la racine dérivée » : exactement les dix lignes de `verrou_brut` (mêmes chaînes, `sigpgp=(none)`, clé d'en-tête `702d426d350d275d`), plus au plus une ligne `gpg-pubkey` ; « seulement dans rockylinux:9.7 brut » : exactement les quatre lignes de `verrou_brut` ; communes 143 ; liste après de 153 lignes, ou 154 avec `gpg-pubkey` | Moyenne : décision « Dix lignes » ; dépend de DR6 |
| DR9 | « requires du greffon installé » : au moins une ligne `python3-dnf`, cohérente avec DH4 | Moyenne |
| DR10 | « restes de /w dans la racine : 0 » ; nombre d'entrées de `var/cache/dnf` : pas de pari | Haute pour `/w` (banc, D1 et D2) |
| DR11 | « archive racine dérivée : rc 0 », taille entre 0,8 et 1,5 fois la copie de DR2 ; sur l'hôte « OK   archive racine dérivée rapatriée » ; `boot-racine.sha256` posé | Moyenne : `tar` et `du` ne comptent pas pareil |
| DR12 | Installation en moins de 300 s ; moins de 15 min entre « 05 S1 boot_racine » et « fait » | Faible : 67 s pour l'équivalent dans mock, mais 5694 s inexpliquées à `racine` |
| DR13 | « capacité de /w : 3059832 kB » ; « utilisés » sous 1 500 000 kB ; aucun « No space left on device » | Moyenne : capacité mesurée à `verrou_brut` ; image tirée, copie, cache et archive |
| DR14 | Sonde complète, « (code de l'exec : 0) » ; « pod s1-05-boot-racine supprimé » une fois | Haute. La sonde finit par `true` : le code 0 seul ne prouve rien |
| DI1 | `boot_image` : « OK   archive racine dérivée, sha256 égal à celui de boot_racine » | Haute |
| DI2 | `crane append` et `crane mutate` sans erreur vers Zot, sans nouvelle authentification (`$T/docker/config.json` existe) | Haute : mêmes commandes et même compte qu'`image` ; `**` donne `create` à `poc-ecriture` (lecture de la configuration commitée) |
| DI3 | Une couche, de taille inférieure à l'archive ; deux annotations, `base.name` = `sc-stockage.poc.test:5000/amont/rockylinux/rockylinux` et `base.digest` = `sha256:ee90dc0e…` ; « config : os linux ; architecture amd64 » | Haute : banc G, sur une archive factice |
| DI4 | Digest d'image non prédit ; égal à celui du passage en loopback avec la même archive | Moyenne : à `image`, le banc en loopback et Zot ont donné le même digest (`99790c13…`), sans `crane mutate -a`. Au banc, les digests de G ont différé d'un passage à l'autre, mais l'archive factice différait aussi : que `-a` redonne le même digest pour la même archive n'est pas mesuré, le passage en loopback le montrera |
| DI5 | Moins de 60 s entre « 05 S1 boot_image » et « fait » | Moyenne : 11 s pour `image` et 361 Mo |

**Ce que ferait un écart** :
- Si DR5 tient mal (makecache en échec, ou repomd différent), la sonde s'arrête ou l'hôte refuse : pas d'archive, pod retiré,
  accord dépensé ; la décision revient au propriétaire.
- Si DH3 tient mal (paquet absent, deux empreintes), `hote97` s'arrête : rien n'est construit, et la décision revient au propriétaire.
- Si DR6 ou DR7 tient mal (autre transaction, rpm en trop ou en moins), l'archive ne sort pas du pod : les journaux montrent la
  transaction, et la décision revient au propriétaire.
- DR8 n'arrête rien : la liste complète est archivée, et l'écart éventuel (`gpg-pubkey` compris) sera présenté avant l'accord
  d'écriture dans Zot.

**Relance** : `lancer` écrit le journal par `tee` et l'écrase. Une relance après échec prendra un autre `PREFIXE`, comme
`s1-3` pour `hote` ; ce `PREFIXE` est aussi le tag Zot de `boot_image`.

Suite : accord de lancement de `hote97`. Rien n'est lancé, rien n'est écrit dans Zot.

## Étape `hote97` : résultat (note du 2026-11-17, écrite à 2026-11-17T14:30:53Z ; rien n'est réécrit)

Passage sur accord « Oui, lance hote97 », le 17/11/2026 de 14:30:07 à 14:30:14 UTC (`date -u` du lancement et
[`chrono.tsv`](chrono.tsv)), code 0. Commande : `env -u PREFIXE -u ISOLATION DISTRO=rke2 KUBECONFIG=… mise exec --
poc/bricks/05-rpm-mock/s1.sh hote97`, `s1.sh` à `2b0a3b7b…`. Journal : [`s1-hote97.log`](s1-hote97.log).

| # | Résultat |
|---|---|
| DH1 | **Tenue.** Empreinte `21CB256A…350D275D`. |
| DH2 | **Tenue.** Quatre `repomd.xml` signés par la clé primaire, quatre primary contrôlés par leur `repomd.xml`, quatre « égal au relevé de hote : oui » ; sha256 `fa6d5054…`, `06f01d40…`, `3936113e…`, `54ec0c53…`, ceux d'`hote` à 08:30:27 UTC. |
| DH3 | **Tenue.** Dix lignes « OK », aucune « KO » ; les dix paquets sont tous dans `baseos97`, chacun une seule fois (aucun pari n'était fait sur le dépôt) ; `derivee.sha256` écrit, dix lignes. |
| DH4 | **Tenue.** Six entrées : `python(abi) = 3.9`, `python3-dateutil`, `python3-dbus`, `python3-dnf >= 4.11.0`, `python3-hawkey >= 0.64.0`, `python3-systemd`. |
| DH5 | **Tenue.** 7 s. |

**Ce que cela apprend** :
- **Les `Requires` du greffon sont lus.** Pour l'entrée `python3-dnf`, `>= 4.11.0` est satisfait par le `4.14.0-31.el9` de
  l'image brute. Cette entrée n'explique donc pas les quatre montées de version vues à `verrou_brut`. `python3-hawkey >= 0.64.0`
  n'est pas comparé : la version de `python3-hawkey` dans l'image n'est pas relevée. La cause des quatre montées reste non lue.
- Trois des six paquets ajoutés sont des `Requires` directs du greffon (`python3-dateutil`, `python3-dbus`, `python3-systemd`).
  Que `dbus-libs` et `python3-six` viennent par ces paquets est une hypothèse, non lue.
- Ce résultat ne change pas la décision « Dix lignes », prise sur l'état mesuré à `verrou_brut`.

Suite : accord de lancement de `boot_racine` (pod, rien poussé). Rien n'est écrit dans Zot.

## Étape `boot_racine` : résultat (note du 2026-11-17, écrite à 2026-11-17T14:46:52Z ; rien n'est réécrit)

Passage sur accord « Oui, lance boot_racine », le 17/11/2026 de 14:31:54 à 14:45:36 UTC (`date -u` du lancement et
[`chrono.tsv`](chrono.tsv)), code 0. Commande : `env -u PREFIXE -u ISOLATION DISTRO=rke2 KUBECONFIG=… mise exec --
poc/bricks/05-rpm-mock/s1.sh boot_racine`, `s1.sh` à `2b0a3b7b…`. Journal : [`s1-boot_racine.log`](s1-boot_racine.log).

**L'archive de la racine dérivée est construite et rapatriée** : 258 129 920 octets, sha256 `8ae17f92…`, dans `$T/boot-racine.tar`
(hors du dépôt), avec `boot-racine.sha256`. Rien n'est écrit dans Zot.

| # | Résultat |
|---|---|
| DR1 | **Tenue.** Pod prêt, image `99790c13…` ; « dnf-3 : 4.14.0 ». Premier passage du `dnf-3` de l'image d'essai. |
| DR2 | **Tenue.** Pull `rc 0` en 7 s, mount `rc 0`, copie `rc 0`, 243 672 kB. |
| DR3 | **Tenue.** Quatre `.repo` écartés (`rocky-addons`, `rocky-devel`, `rocky-extras`, `rocky`) ; 147 lignes avant, stderr 0. |
| DR4 | **Tranchée** (pas de pari) : `gpg-pubkey-350d275d-6279464b` est déjà dans l'image brute, avant comme après ; dnf n'ajoute pas de ligne. Elle fait partie des 143 lignes communes, ce qui explique aussi son absence des différences de `verrou_brut`. |
| DR5 | **Tenue.** `makecache` `rc 0` en 16 s ; quatre « OK   repomd … » sur l'hôte. `repo_gpgcheck=1` a tourné dans cette image pour la première fois. |
| DR6 | **Tenue.** `rc 0` ; six paquets sous « Installing » et quatre sous « Upgrading », tous depuis `baseos97`, rien d'autre ; « Install  6 Packages », « Upgrade  4 Packages ». Un `dnf install` d'un NEVRA exact fait donc la montée de version d'un paquet présent (mesuré une fois). |
| DR7 | **Tenue.** Dix rpm, conformes aux dix de `hote97` (fichiers et sha256) ; « rpm -K : 10 OK sur 10 ». |
| DR8 | **Tenue.** Les dix lignes « seulement dans la racine dérivée » et les quatre « seulement dans rockylinux:9.7 brut » sont, chaîne pour chaîne, celles de `verrou_brut` (signature d'en-tête comprise) ; 143 communes ; 153 lignes après, sans ligne `gpg-pubkey` de plus (DR4). La liste complète est archivée (153 lignes « racine dérivée, liste »). |
| DR9 | **Tenue.** `python3-dnf >= 4.11.0` dans les `Requires` du paquet installé, comme dans le primary (DH4), plus `config(…)` et cinq `rpmlib(…)` que le primary ne liste pas. |
| DR10 | **Tenue** pour `/w` : 0. `var/cache/dnf` : 0 entrée (pas de pari). |
| DR11 | **Tenue.** 258 129 920 octets, 1,03 fois la copie ; « OK   archive racine dérivée rapatriée ». |
| DR12 | **Non tenue pour l'installation** : 761 s, au-dessus des 300 s prédites. **Tenue pour l'étape** : 822 s, sous 15 min. |
| DR13 | **Tenue.** Capacité 3 059 832 kB ; 744 284 kB utilisés ; aucun « No space left on device ». |
| DR14 | **Tenue.** « (code de l'exec : 0) » ; pod supprimé une fois. |

**Observation, sans cause** : 761 s pour installer dix paquets (environ 2 Mo d'après la transaction), contre 16 s pour
`makecache`. À `racine`, 201 paquets avaient pris 5694 s, cause inconnue. Ici, la même lenteur se voit avec un autre dépôt
(vault 9.7) et peu de paquets ; qu'elle soit sans lien avec le volume téléchargé est une hypothèse. La cause n'est pas lue ;
le journal complet de dnf n'est pas archivé.

**Ce que cela apprend** : la racine dérivée est exactement « `rockylinux:9.7` plus les dix lignes » de la décision ; la question
`gpg-pubkey` ne se pose plus.

Suite : prédictions puis passage local de `boot_image` avec cette archive (registre crane en loopback, deux passages pour
comparer les digests), puis accord d'écriture dans Zot. Rien n'est écrit dans Zot.

## Passage local de `boot_image` : prédictions (note du 2026-11-17, écrite à 2026-11-17T14:50:14Z, avant tout passage ; rien n'est réécrit), NON LANCÉ

Script : [`s1-boot-image-banc.sh`](s1-boot-image-banc.sh), sha256 `233dca6e…`. Écrit à sec pendant `boot_racine` sous le nom
`banc-boot-image.sh`, il a été changé avant d'être archivé, après relecture : l'archive était liée par un lien symbolique, et le
`stat -c %s` de `etape_boot_image` aurait affiché la taille du lien (vérifié : 132 octets pour un lien vers un fichier de 5 000) ;
elle est maintenant liée par un lien dur (même système de fichiers, `/home`). S'y sont ajoutés trois arguments facultatifs
(dossier `T`, dossier du banc, adresse ; les défauts sont ceux du vrai passage) et une garde qui refuse une adresse déjà prise.
Le script extrait `etape_boot_image` de `s1.sh` (`2b0a3b7b…`) et la joue deux fois contre un `crane registry serve` en loopback
(`127.0.0.1:5907`, disque `~/.cache/supply-chain-poc/05/banc-boot-image`, absent avant), avec la vraie archive de `boot_racine`,
sans Zot, sans cluster, sans authentification. Rien n'est écrit dans les fichiers de `$T`.

**Répétition**, le 17/11/2026 à 14:49:29 UTC, sur une archive factice de 10 240 octets (dossier
`~/.cache/supply-chain-poc/05/repetition-boot-image`, adresse `127.0.0.1:5908`) : code 0, deux passages, même digest d'image avec
`mutate -a` (« égaux : oui »), manifeste et config OCI, « created 0001-01-01T00:00:00Z ; history 1 ; diff_ids 1 »
([journal](s1-boot-image-repetition.log)).

Commande prévue, depuis la racine du dépôt, sur accord nommé, `date -u` avant et après, code par `PIPESTATUS`, sortie dans un
fichier : `bash -c "date -u …; bash poc/bricks/05-rpm-mock/resultats/s1-boot-image-banc.sh $PWD </dev/null; echo code …; date -u …"`.
Journal prévu : `resultats/s1-boot-image-local.log` (`$HOME` remplacé par `~`). Relance après échec : autre dossier de banc et
autre nom de journal ; `banc-boot-image` n'est pas supprimé sans demande.

**Appuis** : répétition ci-dessus ; banc local de l'étape `image` ([`s1-image-essai-local.log`](s1-image-essai-local.log)) : `crane append` en 6 s pour
`racine.tar` (361 758 720 octets), couche compressée de 140 611 406 octets (rapport 0,39) ; manifeste et config OCI ; « created
0001-01-01T00:00:00Z » ; le même digest qu'ensuite dans Zot. Résultat de `boot_racine` : archive de 258 129 920 octets,
`8ae17f92…`. Banc G de `s1-derivee.patch` : annotations et plateforme posées sur une archive factice ; les digests de G ont
différé d'un passage à l'autre, mais l'archive factice aussi.

| # | Prédiction | Confiance et raison |
|---|---|---|
| LB1 | « OK   sha256 de s1.sh : 2b0a3b7b… » ; archive de 258 129 920 octets, sha256 attendu `8ae17f92…` ; « registre local : prêt (http) » | Haute |
| LB2 | Chacun des deux passages : « OK   archive racine dérivée, sha256 égal à celui de boot_racine : 8ae17f92… » ; « archive racine dérivée : 258129920 octets » ; une seule ligne « couche », de 60 à 140 Mo ; deux annotations, `base.digest` = `sha256:ee90dc0e…` et `base.name` = `sc-stockage.poc.test:5000/amont/rockylinux/rockylinux` ; « config : os linux ; architecture amd64 » ; une ligne « image de bootstrap dérivée : sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@sha256:… » | Haute pour la forme (banc G) ; faible pour la taille de la couche (rapport de 0,39 à `image`, contenu différent) |
| LB3 | « égaux : oui » : même digest d'image aux deux passages | Moyenne à haute : tenu à la répétition avec `mutate -a`, sur une archive factice de 10 240 octets ; `image` a donné le même digest en loopback et dans Zot |
| LB4 | Manifeste `application/vnd.oci.image.manifest.v1+json`, config `application/vnd.oci.image.config.v1+json`, couches `application/vnd.oci.image.layer.v1.tar+gzip` ; config : « created 0001-01-01T00:00:00Z », « history 1 », « diff_ids 1 » | Haute : valeurs de la répétition, mêmes types et même `created` qu'à `image` |
| LB5 | Chaque passage en moins de 60 s ; place du registre local entre 60 et 150 Mo (la couche n'est stockée qu'une fois) | Moyenne : 6 s pour 361 Mo à `image` ; dédoublonnage des blobs par digest non vérifié pour ce registre |
| LB6 | Le script finit sans « KO », code 0 ; aucun « auth_zot appelé » | Haute |

**Ce que ferait un écart** :
- Si LB3 donne « non », le digest dans Zot ne pourra pas être prédit par ce passage : je le dirai avant de demander l'accord
  d'écriture, et la cause sera cherchée par la comparaison des deux manifestes et des deux configs.
- LB2 ou LB4 en écart : pas d'accord d'écriture proposé avant explication.

Suite : accord de lancement du passage local, puis accord d'écriture dans Zot (`boot_image`). Rien n'est écrit dans Zot.

## Passage local de `boot_image` : résultat (note du 2026-11-17, écrite à 2026-11-17T14:51:32Z ; rien n'est réécrit)

Passage sur accord « Oui, lance-le », le 17/11/2026 de 14:50:42 à 14:50:49 UTC (`date -u`), code 0. Journal :
[`s1-boot-image-local.log`](s1-boot-image-local.log). Registre crane en loopback, disque `~/.cache/supply-chain-poc/05/banc-boot-image`
(94 Mo, laissé en place) ; rien dans Zot.

| # | Résultat |
|---|---|
| LB1 | **Tenue.** `s1.sh` `2b0a3b7b…` ; archive de 258 129 920 octets, `8ae17f92…` ; registre prêt. |
| LB2 | **Tenue.** Aux deux passages : sha256 de l'archive égal à celui de `boot_racine` ; une couche `22495746…` de 97 742 593 octets (dans la fourchette de 60 à 140 Mo) ; les deux annotations attendues ; `linux/amd64`. |
| LB3 | **Tenue.** Même digest d'image aux deux passages : `sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6`. |
| LB4 | **Tenue.** Manifeste, config et couche OCI ; « created 0001-01-01T00:00:00Z ; history 1 ; diff_ids 1 ». |
| LB5 | **Tenue.** 5 s puis 2 s ; registre local de 94 Mo. |
| LB6 | **Tenue.** Code 0, aucun « KO », aucun « auth_zot appelé ». |

**Prédiction pour l'écriture dans Zot** : avec la même archive et le même `crane`, le digest attendu est `f0ccf105…`, comme à
`image`, où le loopback et Zot ont donné le même digest. Ce n'est pas encore mesuré avec Zot.

Suite : relevé « avant » du dépôt `essais-05/rocky9-bootstrap` dans Zot (lecture seule), puis accord d'écriture (`boot_image`,
tag `:s1`). Rien n'est écrit dans Zot.

**Relevé « avant » dans Zot** (note du 2026-11-17, écrite à 2026-11-17T14:51:53Z ; lecture seule) : le dépôt `essais-05/rocky9-bootstrap`
n'existait pas le 17/11/2026 à 14:51:40 UTC ([relevé](s1-boot-image-zot-avant.log), sortie brute : `date -u`, `crane ls` en
`NAME_UNKNOWN`, son code 1, le nombre de lignes de `crane catalog`, `date -u`). `crane catalog` compte 142 lignes, contre 141 au
relevé d'`image` (10:32:01 UTC), avant que `essais-05/mock-rocky9` n'y soit écrit.

Suite : accord d'écriture dans Zot (`boot_image`, `essais-05/rocky9-bootstrap:s1`, dépôt définitif), digest attendu `f0ccf105…`.

## Étape `boot_image` : résultat (note du 2026-11-17, écrite à 2026-11-17T14:53:14Z ; rien n'est réécrit)

Passage sur accord « Oui, lance boot_image », le 17/11/2026 de 14:52:28 à 14:52:38 UTC (`date -u` du lancement et
[`chrono.tsv`](chrono.tsv)), code 0. Commande : `env -u PREFIXE -u ISOLATION DISTRO=rke2 KUBECONFIG=… mise exec --
poc/bricks/05-rpm-mock/s1.sh boot_image`, `s1.sh` à `2b0a3b7b…`. Journal : [`s1-boot_image.log`](s1-boot_image.log).

**L'image de bootstrap dérivée est dans Zot** : `sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@sha256:f0ccf10541c724f3ec87aa55bd6b0941391516f8eecf21d82f7367f73c20efb6`, tag `:s1`.
Ce dépôt est définitif.

| # | Résultat |
|---|---|
| DI1 | **Tenue.** sha256 de l'archive égal à celui de `boot_racine` (`8ae17f92…`). |
| DI2 | **Tenue.** `crane append` et `crane mutate` sans erreur, sans nouvelle authentification (aucune ligne d'`auth_zot` dans le journal). |
| DI3 | **Tenue.** Une couche `22495746…` de 97 742 593 octets ; les deux annotations attendues ; `linux/amd64`. |
| DI4 | **Tenue.** Digest égal à celui des deux passages en loopback ([`s1-boot-image-local.log`](s1-boot-image-local.log)). |
| DI5 | **Tenue.** 10 s. |

Non vérifié ici : la lecture de ce dépôt par le `podman` d'un pod. La configuration commitée de Zot donne la lecture anonyme sur
`**`, et aucun podman de pod n'a encore tiré un dépôt `essais-05/`.

Suite : préparer à sec l'étape qui reprend `verrou` avec cette image (configuration jumelle : `bootstrap_image` = ce digest,
`bootstrap_image_ready=True`), avec son correctif, son banc, ses prédictions et son accord.

## Étape `verrou_derivee` préparée à sec (note du 2026-11-17, écrite à 2026-11-17T15:16:53Z ; rien n'est réécrit), NON APPLIQUÉ

Préparation faite sur le message « continue » du propriétaire, qui suivait le message annonçant cette préparation comme
prochaine étape. Rien n'est appliqué à `s1.sh`, rien n'est lancé, ni dans le cluster ni dans Zot.

**Correctif** : [`../s1-verrou-derivee.patch`](../s1-verrou-derivee.patch) (sha256 `a0f1e66e…`), insertions seules (en-tête
6 lignes, bloc 119 lignes), produit par [`s1-verrou-derivee-modifier.py`](s1-verrou-derivee-modifier.py) à partir de
`s1.sh` `2b0a3b7b…` ; copie bancée `199b4ff2…`. Il ajoute une étape nouvelle, `verrou_derivee`. `verrou` n'est pas rejoué, car
il réécrirait `s1-verrou.log` et `s1-verrou-mock.log`, déjà commités.
- **Configuration** : l'image d'essai ne porte que `poc-rocky-9.7-x86_64` et `poc-rocky-9.7-pret-x86_64`, toutes deux sur
  `rockylinux:9.7` brut. L'étape génère sur l'hôte, à partir de `MOCK_CFG`, une troisième configuration,
  `poc-rocky-9.7-derivee-x86_64`. Trois lignes changent : la racine, `bootstrap_image` (`essais-05/rocky9-bootstrap@` suivi du
  digest lu dans `boot-image.digest`, sans digest écrit en dur) et `bootstrap_image_ready=True`. Un écart autre que six lignes de
  diff, compté sur l'hôte, arrête l'étape. La configuration est livrée sous `/etc/mock` du pod.
- **Contrôles avant mock** (sonde `SONDE_CFG_DERIVEE`) :
  - le pod affiche le sha256 de sa propre configuration de base et celui de la configuration livrée. Le contrôle se fait par
    sha256 et non par `diff`, absent de l'image d'essai (`tar -tf` de `racine.tar`, section H du banc) ;
  - il affiche les lignes `root` et `bootstrap_image*` de `mock --debug-config` ;
  - il tire lui-même l'image dérivée par `podman pull`, avec son code et sa durée.

  L'hôte arrête l'étape, et retire le pod, si la configuration de base diffère de `MOCK_CFG`, si la configuration livrée diffère
  de celle générée, ou si le pull échoue. Raison de ce dernier arrêt : `bootstrap_image_fallback` vaut `True` par défaut
  (`config.py:110`). Si le pull échouait, mock installerait le bootstrap sans image, et le calcul ne mesurerait plus l'image dérivée.
- **Verrou** : `SONDE_VERROU` rendue pour la configuration dérivée, avec le libellé « (image dérivée) » et `--no-cleanup-after`
  au calcul. Contre le rendu de `verrou`, cinq lignes changent. La sonde reste celle de `verrou`, inchangée dans `s1.sh`.
- **Repli** : `SONDE_REPLI` compte les lignes « falling back to chroot installation » dans `res-verrou/root.log`,
  `verrou-srpm.log` et `verrou-calc.log`.
- **Bootstrap** : `SONDE_BOOT` rendue pour la configuration dérivée et l'image dérivée. Elle compare le `rpm -qa` du bootstrap
  gardé par mock à celui de l'image dérivée montée. Les libellés « rockylinux:9.7 brut » y sont remplacés ; restent seulement
  les noms de fichiers internes `/w/$2.brut`, jamais affichés.
- **Archives** : journaux de mock, avec la fin de `verrou-srpm.log` en plus de celle de `verrou-calc.log`, dans
  `resultats/<PREFIXE>-verrou_derivee-mock.log` ; verrou dans `resultats/<PREFIXE>-verrou_derivee.json`, puis deux résumés non
  fatals :
  - celui de `verrou_brut`, repris tel quel ;
  - une comparaison avec [`s1-verrou_brut.json`](s1-verrou_brut.json) : `pull_digest` égal ou non au digest de `boot_image`,
    options de configuration différentes, et rpm du buildroot comparés sur le nom, l'epoch, la version, la release, l'arch, le
    `sigmd5` et l'url.

**Lu pendant la préparation, sans lancement** (code de mock 6.9, lecture ; aucune de ces lectures n'est une mesure) :
- avec une image prête, `_init_pkg_management` sort tout de suite (`buildroot.py:590-591`). « Prête » est annulée par
  `module_enable`, `module_install`, `module_setup_commands` et `chroot_additional_packages`, et sinon `root.log` reçoit « Not
  updating bootstrap chroot, bootstrap_image_ready=True » ;
- l'image passe par `podman pull`, puis `podman tag`, puis le contrôle de digest, fait seulement si
  `bootstrap_image_assert_digest` est posé (il ne l'est pas ici). Vient ensuite le contrôle d'architecture : `{{.OsArch}}` de
  `podman version` contre `{{.Os}}/{{.Architecture}}` de l'image (`podman.py:62-93`). La copie se fait enfin par `tar`
  depuis `podman image mount` (`buildroot.py:276-302`, `podman.py:224-238`). Rien n'est exécuté avec l'environnement de l'image ;
  mock pose son propre `PATH` (`config.py:280`). Que l'image dérivée n'ait pas d'`Env` est une déduction : son `crane mutate` n'a
  pas de `-e`. Sa config n'a pas été relue ;
- le message de repli est un avertissement (`buildroot.py:307`) du logger `mockbuild.buildroot` : `getLog()` sans nom prend le nom
  du module (`trace_decorator.py:18-29`). Ce logger est un enfant de `mockbuild`, qui reçoit le gestionnaire de `root.log`
  (`buildroot.py:125` et `:692`). Le message irait donc aussi dans `root.log`, si ce gestionnaire est déjà attaché à ce moment ;
  l'ordre des deux n'a pas été lu. D'où les trois fichiers de `SONDE_REPLI` ;
- mock appelle `/usr/bin/dnf-3` dans le bootstrap (`dnf4_command`, `config.py:376`), comme le montre
  [`s1-verrou_brut-mock.log`](s1-verrou_brut-mock.log). `./usr/bin/dnf-3` et
  `./usr/lib/python3.9/site-packages/dnf-plugins/builddep.py` sont dans `boot-racine.tar` (`8ae17f92…`) : lu par `tar -tf`,
  section H du banc ;
- `--hermetic-build` (M2) n'est pas en jeu ici. `config.py:844` coupe `bootstrap_image` au premier « : » ; sur une référence
  `hôte:5000/…@sha256:…`, ce point est à lire avant M2.

**Banc** [`s1-verrou-derivee-banc.sh`](s1-verrou-derivee-banc.sh), sections A à H, ni cluster, ni Zot, ni réseau ; H lit
`racine.tar` et `boot-racine.tar` par leur nom :
- passage final le 17/11/2026 à 15:15:32 UTC, sur la copie `199b4ff2…`, python3 3.13.12 : tenu, 71 OK
  ([journal](s1-verrou-derivee-banc.log)) ;
  - la configuration de base rendue par le banc a le même sha256 que celle de l'étape `image` (`a8e5f2bc…`,
    [`s1-image.log`](s1-image.log)) ;
  - la configuration dérivée est égale à un calcul indépendant ;
  - un pull refusé ou une configuration livrée altérée arrête l'étape, pod retiré ;
  - les lignes de repli sont comptées dans les trois fichiers ;
  - `SONDE_BOOT` ne donne aucun écart sur des listes égales ;
  - la comparaison donne 222 rpm communs sur `s1-verrou_brut.json` comparé à lui-même, et un écart de chaque côté sur une variante ;
  - les commandes des deux sondes neuves sont dans `/usr/bin` de l'image d'essai, sauf `diff`, qu'elles n'appellent pas.

  shellcheck : 17 remarques sur le dépôt, 20 sur la copie (trois `SC2016` de plus), aucune de niveau error ;
- N3/N4 ([`s1-n34-banc.sh`](s1-n34-banc.sh), inchangé) sur la même copie, à 15:15:35 UTC : tenu, 35 OK
  ([journal](s1-verrou-derivee-banc-n34.log)) ;
- passages précédents, archivés :
  - à 15:07:58 UTC, sur la copie `2df6ba31…`, NON TENU, 2 KO, tous deux des défauts du banc : le rendu de référence de `verrou`
    avait un saut de ligne final en moins, et le contrôle des libellés comptait les fichiers internes `/w/$2.brut`
    ([journal](s1-verrou-derivee-banc-passage1.log)) ;
  - à 15:08:16 UTC, même copie, banc corrigé : tenu, 65 OK ([journal](s1-verrou-derivee-banc-passage2.log)), et N3/N4 à
    15:08:33 UTC : tenu, 35 OK ([journal](s1-verrou-derivee-banc-n34-passage1.log)). Un commentaire de la copie citait
    `buildroot.py:306` au lieu de `:307` ; corrigé, d'où la copie `a37d833b…` ;
  - à 15:10:18 UTC, copie `a37d833b…` : tenu, 65 OK ([journal](s1-verrou-derivee-banc-passage3.log)), et N3/N4 à 15:10:20 UTC :
    tenu, 35 OK ([journal](s1-verrou-derivee-banc-n34-passage2.log)). La relecture a trouvé ensuite deux défauts de cette copie,
    que le banc ne voyait pas : la sonde appelait `diff`, absent de l'image d'essai, et le commentaire disait que mock ne
    signale le repli « que dans sa sortie », ce que la lecture de `trace_decorator.py` contredit. D'où la copie `199b4ff2…` et la
    section H du banc.
- Le banc et le modificateur archivés sont les versions finales ; les versions intermédiaires ne sont pas gardées.
- **Bornes** : sur des doublures, sans vrai mock, vrai podman ni vrai rpm, sans kubectl et sans Zot. Restent non mesurés : la
  lecture anonyme de `essais-05/` par le podman d'un pod, et le comportement de mock avec l'image prête.

Suite : appliquer `s1-verrou-derivee.patch` à `s1.sh` sur accord, puis écrire les prédictions et demander l'accord de lancement.
Rien n'est lancé.

## Étape `verrou_derivee` : `s1-verrou-derivee.patch` appliqué au dépôt (note du 2026-11-17, écrite à 2026-11-17T15:18:48Z ; rien n'est réécrit)

Décision du propriétaire : question « J'applique s1-verrou-derivee.patch à s1.sh ? », réponse « Oui, applique-le ».

- `git apply` de [`../s1-verrou-derivee.patch`](../s1-verrou-derivee.patch) à 15:18:00 UTC (`date -u` avant et après, code 0).
  `s1.sh` passe de `2b0a3b7b…` à `199b4ff2…`, la copie bancée.
- Banc repassé sur le fichier du dépôt à 15:18:06 UTC : tenu, 71 OK ([journal](s1-verrou-derivee-banc-applique.log)). Le banc
  compare le fichier à l'ancien `s1.sh` (`2b0a3b7b…`, tiré de `HEAD`), placé dans un arbre de travail du scratchpad (`<avant>`
  dans le journal) avec un lien vers `resultats/`. Hors des deux premières lignes, il diffère du journal de la copie
  ([`s1-verrou-derivee-banc.log`](s1-verrou-derivee-banc.log)) par 2 lignes : la ligne « utilisés » du `df` de la section E
  (dossier du banc, sur l'hôte) et l'heure de fin.
- Deux lignes datées ajoutées ensuite à l'en-tête, sous la description de `verrou_derivee` : « Correctif appliqué au dépôt le
  17/11/2026 à 15:18:00 UTC (« Oui, applique-le »), sha256 égal à la copie bancée (199b4ff2…) ; non lancé. ». `s1.sh` vaut alors
  `049fccad…`.
- Contrôles sur ce fichier : `bash -n` passe ; shellcheck : 20 remarques, aucune de niveau warning ou au-dessus ; banc N3/N4 à
  15:18:19 UTC, python3 3.13.12 : tenu, 35 OK ([journal](s1-verrou-derivee-banc-n34-applique.log)).

Suite : prédictions de `verrou_derivee`, écrites et commitées avant tout passage, puis accord de lancement. Rien n'est lancé.

## Étape `verrou_derivee` : prédictions (note du 2026-11-17, écrite à 2026-11-17T15:24:09Z, avant tout passage ; rien n'est réécrit), NON LANCÉ

Commande prévue, depuis la racine du dépôt, sur accord nommé, `date -u` avant et après, code par `PIPESTATUS`, sortie dans un
fichier : `env -u PREFIXE -u ISOLATION DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/s1.sh verrou_derivee
</dev/null` (isolation `simple`, la seule qui a construit à `essais`). `s1.sh` vaut `049fccad…`. Journaux attendus :
`s1-verrou_derivee.log`, `s1-verrou_derivee-mock.log`, `s1-verrou_derivee.json`. Relance après échec : autre `PREFIXE`, pour
que rien d'archivé ne soit réécrit.

Entrées vérifiées par leur nom avant d'écrire, sans lister le dossier de travail : `image.digest` (`99790c13…`),
`boot-image.digest` (`f0ccf105…`) et `SHA256SUMS.s1` sont présents, de même que les sources de `sample-app` (`test -s`).

**Appuis mesurés** :
- `verrou` ([`s1-verrou.log`](s1-verrou.log)) : la même sonde avec `rockylinux:9.7` brut marqué prêt. `--buildsrpm` `rc 0` en
  50 s ; « Not updating bootstrap chroot, bootstrap_image_ready=True » avec un compte cumulé de 1 après chaque appel ; le calcul
  échoue en 6 s sur « builddep command missing ». Le journal du calcul y liste encore `python3-dnf-4.14.0-31.el9` et
  `yum-4.14.0-31.el9`, alors que vault 9.7 offre `rocky.0.1` : indice, non preuve, que mock ne met pas à jour un bootstrap prêt.
- `verrou_brut` ([`s1-verrou_brut.log`](s1-verrou_brut.log)) : image brute non prête. `--buildsrpm` en 67 s, calcul `rc 0` en
  26 s ; verrou 1.1.0 avec 222 rpm, tous sous vault 9.7, signature `None` partout. Le bootstrap de mock a 153 paquets : les 147
  de l'image brute moins quatre, plus dix, soit exactement les dix lignes de l'image dérivée.
- `boot_racine` ([`s1-boot_racine.log`](s1-boot_racine.log)) : la racine dérivée a 153 paquets, les mêmes que ce bootstrap.
- Section H du banc : `dnf-3` et `builddep.py` sont dans l'image dérivée.
- `essais` : `podman pull` de l'image brute depuis Zot par un pod, `rc 0` en 7 s.

| # | Prédiction | Confiance et raison |
|---|---|---|
| VD1 | Sur l'hôte, avant le pod : « OK   configuration dérivée : … rien d'autre : 6 » ; six lignes « écart prévu » ; « configuration dérivée : sha256 78645df78c3d47b90fd9617844058105b752146402e5a5288aa0abc66e73d2d8 » | Haute : valeur calculée par le banc (section C) avec les mêmes entrées, y compris le digest de `boot_image` |
| VD2 | Pod `s1-05-verrou-derivee` prêt ; les cinq livraisons passent | Haute : mêmes gestes qu'à `verrou` et `verrou_brut` ; la livraison sous `/etc/mock` est neuve, mais le pod est root |
| VD3 | `SONDE_CFG_DERIVEE` : configuration de base `sha256 a8e5f2bc…`, configuration livrée `sha256 78645df7…`, puis les deux « OK » de l'hôte ; `mock --debug-config : rc 0` ; trois lignes « configuration lue par mock » (`root`, `bootstrap_image` sur `essais-05/rocky9-bootstrap@sha256:f0ccf105…`, `bootstrap_image_ready = True`), aucune pour `bootstrap_image_fallback` ni `bootstrap_image_assert_digest` | Haute pour les sha256 (banc C, `s1-image.log`) ; moyenne pour les trois lignes : `--debug-config` n'écrit que les clés différentes du défaut (lecture), et `root` n'a jamais été relevé |
| VD4 | « podman pull, image dérivée : rc 0 en N s », N inférieur à 60 ; « OK   podman pull de l'image dérivée par le pod : rc 0 » ; inspect : `sha256:f0ccf105…` et `linux/amd64` | Moyenne : lecture anonyme de `essais-05/` jamais mesurée ; la configuration commitée de Zot la donne sur `**`, la configuration déployée n'est pas relue. `.Digest` d'une image tirée par digest non mesuré |
| VD5 | `SONDE_VERROU` : sources `rc 0` ; « configuration : config_opts['bootstrap_image_ready'] = True » ; options qui annulent « prête » : 0 ; `mock --buildsrpm (image dérivée) : rc 0` ; src.rpm `sample-app-1.0.0-2.el9.src.rpm`, `c802e60a…` (quatrième fois) | Haute : tenu à `verrou` avec la même sonde et une image prête |
| VD6 | `root.log` : « Not updating bootstrap chroot, bootstrap_image_ready=True », compte cumulé de 1 après `--buildsrpm` comme après le calcul ; aucune ligne « Bootstrap image not marked ready » ni « Package management in bootstrap » | Haute : motif mesuré à `verrou` (`buildroot.py:1193`) |
| VD7 | `mock --calculate-build-dependencies : rc 0` ; un seul `buildroot_lock.json` ; aucune ligne « builddep command missing » | Moyenne à haute : `builddep.py` et `dnf-3` sont lus dans l'image dérivée (section H) ; le calcul n'a jamais tourné sur un bootstrap que mock n'a pas lui-même préparé |
| VD8 | La fin de `verrou-calc.log` archivée liste, sous « Buildroot is handled by package management downloaded with a bootstrap image », exactement `rpm-4.16.1.3-39.el9.x86_64`, `python3-dnf-4.14.0-31.el9.rocky.0.1.noarch`, `python3-dnf-plugins-core-4.3.0-24.el9_7.noarch` et `yum-4.14.0-31.el9.rocky.0.1.noarch`, la liste de `verrou_brut` ([`s1-verrou_brut-mock.log`](s1-verrou_brut-mock.log), lignes 459 à 463) | Moyenne à haute : mêmes versions dans l'image dérivée ; la façon dont mock établit cette liste n'est pas lue |
| VD9 | `SONDE_REPLI` : « 0 ligne(s) de repli sans image » pour `res-verrou/root.log`, `verrou-srpm.log` et `verrou-calc.log` | Moyenne à haute : le repli peut venir du pull, du contrôle d'architecture ou de la copie, qui passent par le même `_fallback` (`buildroot.py:276-302`, lecture) ; le pull du pod (VD4) et la ligne `linux/amd64` de l'inspect couvrent les deux premiers |
| VD10 | `SONDE_BOOT` : « 1 chemin(s) », chemin retenu `/w/mock/poc-rocky-9.7-derivee-x86_64-bootstrap/root` ; deux listes de 153 lignes, `rpm -qa rc 0`, « stderr 0 ligne(s) » ; aucune ligne « seulement dans … » ; « lignes communes : 153 » ; pull `rc 0` | Haute pour 153 (`boot_racine`) ; moyenne à haute pour l'absence d'écart : mock ne touche pas au bootstrap d'une image prête (`buildroot.py:590`, lecture) et ne fait pas de mise à jour du bootstrap (`mock.py:777`, lecture) ; indice mesuré à `verrou` (appuis). C'est la mesure principale de l'étape |
| VD11 | Résumé du verrou : version 1.1.0 ; les mêmes sept options recopiées ; `bootstrap_image` enregistré = `sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap@sha256:f0ccf105…` ; `bootstrap_image_ready` enregistré `True` ; macros recopiées ; champs du bootstrap `architecture, id, image_digest, pull_digest` ; architecture `amd64` | Haute : même greffon qu'à `verrou_brut`, seules les valeurs posées changent |
| VD12 | `image_digest` différent de celui de `verrou_brut` (`fdd27347…`). **Pas de pari sur sa valeur** : c'est un sha256 de RootFS et Config | Haute pour « différent » (couche et config différentes) ; valeur imprévisible |
| VD13 | Comparaison : « bootstrap, pull_digest égal au digest de boot_image : oui » ; « options de configuration différentes de verrou_brut : bootstrap_image, bootstrap_image_ready » ; « ici 222, verrou_brut 222 ; communs 222 ; seulement ici 0 ; seulement dans verrou_brut 0 » | Moyenne à haute : mêmes dépôts figés de vault 9.7, même spec et même dnf (les mêmes versions que dans le bootstrap de `verrou_brut`) ; une résolution différente n'est pas exclue par la lecture |
| VD14 | Résumé : « rpm avec url : 222 sur 222 », mêmes préfixes sous vault 9.7 ; « valeurs distinctes de signature : 1 ; None » | Haute si VD13 tient : mesuré à `verrou_brut` |
| VD15 | Fin : « journaux de mock : … lignes » ; « pod s1-05-verrou-derivee supprimé » ; code 0 ; capacité de `/w` à 3 059 832 kB ; durée totale de moins de 10 min (101 s pour `verrou_brut`) ; aucune écriture dans Zot, aucun appel à `auth_zot` | Moyenne pour la durée ; haute pour le reste (lecture de l'étape : seuls le pod et `resultats/` sont écrits) |

| VD16 | Place : « capacité de /w : 3059832 kB » ; « utilisés » entre 1 400 000 et 2 600 000 kB (1 850 684 kB à `verrou_brut`) ; aucune ligne « No space left on device » | Moyenne : l'image dérivée tirée est plus grosse que la brute, mais mock n'installe plus rien dans le bootstrap ; `df` compte aussi le stockage de podman |
| VD17 | Intégrité : le sha256 de `s1-verrou_derivee.json` est égal à celui de la ligne « verrou : buildroot_lock.json … sha256 » de la sonde | Haute : tenu à `verrou_brut` ; c'est le seul contrôle du filtre `jeton\|token` sur le verrou |

**Ce que ferait un écart** :
- VD4 non tenue : l'étape s'arrête avant mock. La cause est lue dans les cinq lignes du journal de pull, et aucun changement de
  la configuration de Zot n'est fait sans accord.
- VD7 non tenue : la fin de `verrou-calc.log` est lue avant toute relance ; pas de relance sans analyse.
- VD10 en écart (le bootstrap diffère de l'image) : l'image dérivée ne suffit pas à rendre mock passif. Décision avec le
  propriétaire avant M2.
- VD13 en écart : les dix premières différences sont dans le journal ; elles sont analysées avant M2.

Suite : accord de lancement (« verrou_derivee »). Rien n'est lancé.

## Étape `verrou_derivee` : résultat (note du 2026-11-17, écrite à 2026-11-17T15:29:03Z ; rien n'est réécrit)

Passage sur accord « Oui, lance-la », le 17/11/2026 de 15:26:17 à 15:27:52 UTC (`date -u` du lancement et
[`chrono.tsv`](chrono.tsv)), code 0. `s1.sh` à `049fccad…`. Journaux : [`s1-verrou_derivee.log`](s1-verrou_derivee.log),
[`s1-verrou_derivee-mock.log`](s1-verrou_derivee-mock.log) ; verrou : [`s1-verrou_derivee.json`](s1-verrou_derivee.json).

**Avec l'image dérivée marquée prête, mock n'a rien installé dans le bootstrap et a calculé le verrou.** Le bootstrap qu'il a
préparé a les mêmes 153 paquets que l'image dérivée, sans aucun écart (versions et étiquettes de signature comprises). Le
verrou a les mêmes 222 rpm que celui de `verrou_brut`, sur le nom, l'epoch, la version, la release, l'arch, le `sigmd5` et
l'url ; il enregistre `bootstrap_image_ready=True` et `pull_digest` = `f0ccf105…`.

| # | Résultat |
|---|---|
| VD1 | **Tenue.** Six lignes d'écart ; configuration dérivée `78645df7…`, la valeur du banc. |
| VD2 | **Tenue.** Pod prêt, livraisons faites. |
| VD3 | **Tenue.** Configuration de base `a8e5f2bc…`, configuration livrée `78645df7…` ; `--debug-config` `rc 0` ; trois lignes (`bootstrap_image`, `bootstrap_image_ready = True`, `root`), aucune pour `bootstrap_image_fallback` ni `bootstrap_image_assert_digest`. |
| VD4 | **Tenue.** `podman pull` de l'image dérivée par le pod : `rc 0` en 8 s ; inspect `f0ccf105…`, `linux/amd64`. La lecture de `essais-05/` par un pod est mesurée pour la première fois. |
| VD5 | **Tenue.** `--buildsrpm (image dérivée)` `rc 0` en 42 s ; src.rpm `c802e60a…` (quatrième fois). |
| VD6 | **Tenue.** « Not updating bootstrap chroot, bootstrap_image_ready=True », compte cumulé de 1 après chaque appel ; ni « not marked ready » ni « Package management in bootstrap ». |
| VD7 | **Tenue.** Calcul `rc 0` en 34 s ; un `buildroot_lock.json` de 111 561 octets ; pas de « builddep command missing ». |
| VD8 | **Tenue.** Liste exacte : `rpm-4.16.1.3-39.el9`, `python3-dnf-4.14.0-31.el9.rocky.0.1`, `python3-dnf-plugins-core-4.3.0-24.el9_7`, `yum-4.14.0-31.el9.rocky.0.1`. |
| VD9 | **Tenue.** 0 ligne de repli dans chacun des trois fichiers. |
| VD10 | **Tenue.** Un chemin, `…-derivee-x86_64-bootstrap/root` ; 153 lignes des deux côtés ; aucune ligne « seulement dans » ; 153 lignes communes. |
| VD11 | **Tenue.** Version 1.1.0, les sept options, `bootstrap_image` sur l'image dérivée, `True`, macros, quatre champs, `amd64`. |
| VD12 | **Tenue.** `image_digest` `18d64b03…`, différent de `fdd27347…`. |
| VD13 | **Tenue.** `pull_digest` égal au digest de `boot_image` ; seules `bootstrap_image` et `bootstrap_image_ready` diffèrent de `verrou_brut` ; 222 communs, 0 et 0. |
| VD14 | **Tenue.** 222 sur 222 avec url, mêmes préfixes que `verrou_brut`, signature `None`. |
| VD15 | **Tenue.** Pod supprimé, code 0, 95 s ; aucun appel à `auth_zot`. |
| VD16 | **Tenue.** Capacité 3 059 832 kB ; 1 767 372 kB utilisés ; aucun « No space left on device ». |
| VD17 | **Tenue.** sha256 du verrou archivé égal à celui de la sonde, `b6d0f8f1…`. |

Bornes : un seul passage ; isolation `simple` seulement ; le verrou n'a pas encore été donné à `--hermetic-build` (M2). La
ligne « Start: dnf4 update » reste dans le journal du calcul : elle porte sur le buildroot, d'après sa place après la liste du
bootstrap (lecture du journal, pas du code).

Suite : M2 (`--hermetic-build` avec ce verrou), à préparer à sec ; d'abord lire `config.py:844`, qui coupe `bootstrap_image` au
premier « : ». Rien n'est lancé.

## Étapes `voie2` et `hermetique` préparées à sec, début de M2 (note du 2026-11-17, écrite à 2026-11-17T16:00:56Z ; rien n'est réécrit), NON APPLIQUÉ

Préparation faite sur le message « continue » du propriétaire, qui suivait le message annonçant M2 comme prochaine étape à
préparer à sec. Rien n'est appliqué à `s1.sh`, et rien n'est lancé, ni dans le cluster ni dans Zot.

**Correctif** : [`../s1-m2.patch`](../s1-m2.patch) (sha256 `9684b495…`), insertions seules (en-tête 16 lignes, bloc 163 lignes)
dans `s1.sh` `049fccad…` ; copie bancée `8c60bca2…`. Le correctif fait foi : la copie vient d'un script du scratchpad, non
archivé ; la section A du banc montre qu'il n'y a que des insertions, et `git apply --check` passe.

**Périmètre** : première partie de M2 seulement.
- `voie2` joue la voie 2 décidée le 12/11 : rpm du verrou téléchargés, `rpm -K` avec la seule clé de Rocky, en-têtes égaux au
  verrou, `createrepo_c --compatibility`, `skopeo copy --preserve-digests` de l'image dérivée.
- `hermetique` lance `mock --hermetic-build` dans le même pod, **réseau présent** (label `prefetch-rpm`) : elle mesure le
  mécanisme, pas l'hermétisme, qui est l'objet de M3.
- La fermeture dans Zot, sa restauration par digest et la déduplication, preuves de M2 au README, restent à préparer, avec un
  accord à part (écriture dans Zot). Un passage réussi de ces deux étapes ne permettra pas d'écrire « M2 passé ».

**Lieu** : `s1.sh`, qui a les aides de pod (`pod_spec`, `pod_demarrer`, `dans`, `livrer`), le dossier de travail et les
digests mesurés.
- Le cœur de la voie 2 de `m2.sh` (NON BRANCHÉ, 12/11) y est recopié sous les noms `m2_preparer` et `VOIE2_M2`. `m2.sh` n'est
  pas modifié et ne fait plus foi pour ces étapes.
- Écarts déclarés, comparés par le banc (section C) : attendus tirés de `boot-image.digest` et de `DEPOT_DERIVE` au lieu de
  l'image brute ; `bootstrap_image_ready` et `image_digest` exigés ; verrou d'entrée épinglé (`b6d0f8f1…`) sur l'hôte et relu
  dans le pod ; `df` de `/w`.
- `chrono.tsv` portera « 05 S1 voie2 » et « 05 S1 hermetique », puisque `s1.sh` appelle `lancer` avec le jalon « 05 S1 ».

**Découpage** : deux étapes, un accord chacune, un même pod `s1-05-m2`, car le dépôt hors ligne est sur le tmpfs `/w`.
- `voie2` laisse le pod privilégié en place (sommeil de 12 h) si sa dernière ligne, « OK   manifeste copié », porte le digest de
  `boot_image` ; sinon elle le retire. `dans` ne rend pas le code du script : la porte est cette ligne, lue par l'hôte.
- `hermetique` ne recrée jamais le pod. Elle exige la porte de `voie2` et le pod en `Running`, puis relit dans le pod le sha256
  du verrou, celui de `repomd.xml` (égal à celui de `voie2`) et le manifeste du dossier `dir:`. Elle retire toujours le pod à la
  fin : toute relance refait donc `voie2`, sous un autre `PREFIXE`.

**Commande de mock** : `mock --hermetic-build /w/verrou.json /w/voie2/depot --isolation=simple --no-cleanup-after
--config-opts=basedir=/w/mock-h --config-opts=cache_topdir=/w/mock-h-cache --resultdir=/w/res-h --spec … --sources …`.
Raisons, lues dans le code de mock 6.9 (archive `3c034916…`) :
- `hermetic-build.cfg` ne pose ni `basedir` ni `cache_topdir` ([`m2-releve.log`](m2-releve.log)) ; `--config-opts` passe après
  `process_hermetic_build_config` et l'emporte (`config.py:468-499`) ;
- `-r` est refusé et le mode `rebuild` exigé (`mock.py:436-443`). Avec `--spec` et `--sources`, mock construit d'abord le src.rpm
  (`mock.py:994-1003`). Cette forme n'a jamais tourné ici (à `essais`, deux appels séparés), et la documentation donne un
  src.rpm : si elle échoue, le repli est un src.rpm rapatrié puis livré ;
- `--no-cleanup-after` garde le buildroot (`cleanup_on_success`, `config.py:128`), pour que le `df` final mesure le pic, comme à
  `verrou_derivee` ;
- `--debug-config` est un mode (`mock.py:130-131`), donc refusé avec `--hermetic-build`. À sa place, la sonde compte dans la
  sortie et dans `root.log` : les lignes INFO de `podman.py` (`:113`, `:119`, `:159`, `:29`, `:72`), « Checking image digest »
  (`buildroot.py:291`), le repli, « Not updating bootstrap chroot », `--installroot=/w/mock-h/` et « No space left on device ».
  Elle relève ensuite le sha256, le `BUILDHOST` et le `BUILDTIME` des rpm produits : c'est le passage des macros par le verrou,
  point ouvert du 12/11.

**Lu, non mesuré** :
- `config.py:844-847` : sur notre verrou, la coupure au premier « : » donne `sc-stockage.poc.test`. Le dossier `dir:` est donc
  `<dépôt>/sc-stockage.poc.test@sha256:f0ccf105…`, un seul composant de chemin, celui que `skopeo copy` remplit ;
- `config.py:864` et `:868` : le digest affirmé est l'`image_digest` du verrou (`18d64b03…`), sans repli. `podman.py:21-59`
  calcule ce digest sur `RootFS` et `Config` de l'image chargée depuis `dir:` (`:200-214`) ;
- `package_manager.py:509-530` : un dépôt `file:///` est monté dans le bootstrap ;
- `config.py:106` : `use_bootstrap_image` vaut `True` par défaut. `config.py:320` : `releasever` vaut `None`, et ni
  `hermetic-build.cfg` ni le verrou ne le posent ; dnf tourne alors sans `--releasever` (`package_manager.py:241-243`,
  [`m2-releve6.log`](m2-releve6.log)) ;
- skopeo lit le CA livré sous `/etc/containers/certs.d/` par la même bibliothèque que podman : lecture, pas mesure.

**Vérifié sur l'hôte** :
- verrou `s1-verrou_derivee.json` : 222 rpm, tous sous vault 9.7 BaseOS ou AppStream ; aucune entrée `gpg-pubkey`, aucun champ
  vide ; sigmd5 tous de 32 hexadécimaux ;
- place : les 222 rpm font 219 543 349 octets (somme des tailles dans les primary de vault 9.7 vérifiés par `hote97`, tous
  trouvés), et 749 249 076 octets installés. `verrou_derivee` a fini à 1 767 372 kB utilisés sur 3 059 832 kB ;
- image d'essai (`racine.tar` `d7433a05…`) : toutes les commandes des sondes sont dans `/usr/bin`, et `etc/mock/hermetic-build.cfg`
  est égal à celui du tag `mock-6.9-1` (section G du banc) ;
- le dossier `m2` de travail, vidé par `voie2`, n'existe pas encore (contrôle par son nom).

**Banc** [`s1-m2-banc.sh`](s1-m2-banc.sh), sections A à G, ni cluster, ni Zot, ni réseau :
- passage final le 17/11/2026 à 15:58:20 UTC, sur la copie `8c60bca2…`, python3 3.13.12 : tenu, 71 OK
  ([journal](s1-m2-banc.log)) ;
  - `m2_preparer` accepte le vrai verrou et en refuse douze altérés ;
  - `voie2.sh` est joué sur 222 rpm avec des outils simulés : le nominal passe ; cinq échecs et deux outils absents donnent
    chacun un KO ;
  - les portes des deux étapes sont rejouées avec les lignes de la copie ;
  - la sonde de mock est jouée sur un faux mock : arguments, comptes, rpm, échec.

  shellcheck : 20 remarques sur le dépôt, 25 sur la copie (quatre `SC2016` et un `SC2001` de plus, de niveau note), aucune de
  niveau warning ;
- N3/N4 ([`s1-n34-banc.sh`](s1-n34-banc.sh), inchangé) sur la même copie, lancé à 15:58:39 UTC : tenu, 35 OK
  ([journal](s1-m2-banc-n34.log)) ;
- passages précédents :
  - à 15:49:45 UTC, copie `2f56f6b6…` : NON TENU, 3 KO, tous des attendus du banc ([journal](s1-m2-banc-passage1.log)). Neuf
    fragments extraits et non huit ; longueurs des sondes devinées ; « ERROR » attendu deux fois, alors que le faux `root.log`
    est écrit avant l'erreur. Rejoué à l'identique juste après : sortie écrasée, non archivée ;
  - à 15:50:37 UTC, banc corrigé : tenu, 69 OK ([journal](s1-m2-banc-passage2.log)). Deux libellés du banc ont ensuite été
    renommés, car ils contenaient un mot que nos lectures masquent ; ils restent dans ces deux journaux. Rejoué : tenu, sortie
    écrasée, non archivée. N3/N4 sur `2f56f6b6…`, fini à 15:50:52 UTC : tenu, 35 OK, sortie écrasée, non archivée ;
  - la relecture a ensuite fait retoucher la sonde de mock : `--no-cleanup-after`, compte de `--installroot`, motif passé par
    `-e` (un motif qui commence par « -- » serait pris pour une option de grep), « No space left on device ». D'où la copie
    `8c60bca2…`.
- **Bornes** : doublures seulement ; ni vrai mock, ni vrai podman, ni vrais rpm, createrepo_c ou skopeo, ni kubectl, ni Zot, ni
  réseau.

Suite : appliquer `s1-m2.patch` à `s1.sh`, sur accord ; puis écrire et commiter les prédictions des deux étapes avant tout
lancement ; puis un accord par étape. Rien n'est lancé.

## `s1-m2.patch` appliqué à `s1.sh` (note du 2026-11-17, écrite à 2026-11-17T16:02:59Z ; rien n'est réécrit), NON LANCÉ

Décision du propriétaire : question « J'applique s1-m2.patch à s1.sh ? », réponse « Oui, applique-le ».
- `git apply` de [`../s1-m2.patch`](../s1-m2.patch) à 16:02:02 UTC (`date -u` avant et après, code 0) : `s1.sh` passe de
  `049fccad…` à `8c60bca2…`, la copie bancée.
- Banc repassé sur le fichier du dépôt, lancé à 16:02:09 UTC : tenu, 71 OK ([journal](s1-m2-banc-applique.log)). Il compare
  ce fichier à l'ancien `s1.sh` (`049fccad…`, tiré de `HEAD`), placé dans un arbre de travail du scratchpad (`<avant>` dans le
  journal). Écarts au journal de la copie : heures, durées et `df` de l'hôte seulement.
- Deux lignes datées ajoutées ensuite à l'en-tête de `s1.sh`, après l'entrée `hermetique` : « Correctif appliqué au dépôt le
  17/11/2026 à 16:02:02 UTC (« Oui, applique-le »), sha256 égal à la copie bancée (8c60bca2…) ; non lancé. ». `s1.sh` vaut alors
  `8554910f…`.
- N3/N4 ([`s1-n34-banc.sh`](s1-n34-banc.sh)) sur ce fichier final, lancé à 16:02:28 UTC, python3 3.13.12 : tenu, 35 OK
  ([journal](s1-m2-banc-n34-applique.log)).

Suite : prédictions de `voie2` et de `hermetique`, écrites et commitées avant tout passage, puis un accord par étape. Rien n'est
lancé.

## Étapes `voie2` et `hermetique` : prédictions (note du 2026-11-17, écrite à 2026-11-17T16:12:07Z, avant tout passage ; rien n'est réécrit), NON LANCÉ

Commandes prévues, depuis la racine du dépôt, une par accord nommé, `date -u` avant et après, code par `PIPESTATUS`, sortie dans
un fichier : `env -u PREFIXE -u ISOLATION DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/s1.sh voie2 </dev/null`,
puis la même avec `hermetique`, dans les 12 h (sommeil du pod). `s1.sh` vaut `8554910f…`. Journaux attendus : `s1-voie2.log`,
`s1-hermetique.log`, `s1-hermetique-mock.log`. **`voie2` laisse un pod privilégié en place** jusqu'à `hermetique`, ou jusqu'à 12 h.
Relance après échec : `voie2` d'abord, sous un autre `PREFIXE`, pour que rien d'archivé ne soit réécrit.

Ces deux étapes mesurent la voie 2 et le mécanisme de `--hermetic-build`, **réseau présent**. Elles ne prouvent pas
l'hermétisme (M3), et la fermeture dans Zot reste hors de cette partie : même toutes tenues, elles ne font pas « M2 passé ».

**Appuis mesurés** :
- `verrou_derivee` ([`s1-verrou_derivee.log`](s1-verrou_derivee.log)) : `podman pull` anonyme de l'image dérivée par un pod en
  8 s ; « Not updating bootstrap chroot, bootstrap_image_ready=True » dans `root.log` (`buildroot.py:1193`) ; `--buildsrpm` en
  42 s, src.rpm `c802e60a…` ; calcul en 34 s ; 1 767 372 kB utilisés sur 3 059 832 kB à la fin.
- `boot_racine` ([`s1-boot_racine.log`](s1-boot_racine.log)) : `rpm -K` avec la seule clé de Rocky, 10 OK sur 10, sur des rpm
  de vault 9.7.
- `essais` ([`s1-essais.log`](s1-essais.log)) : src.rpm `c802e60a…` ; un seul rpm binaire,
  `sample-app-1.0.0-2.el9.x86_64.rpm` `864d55f4…`.
- Hôte : 222 rpm dans le verrou, 219 543 349 octets au total et 749 249 076 octets installés, sommés dans les primary de vault
  9.7 vérifiés par `hote97` à 14:30, relus sans nouveau contrôle ([script](s1-m2-tailles.py), [journal](s1-m2-tailles.log)) ;
  couche ajoutée de l'image dérivée : 97 742 593 octets ([`s1-boot_image.log`](s1-boot_image.log)).
- Banc ([`s1-m2-banc-applique.log`](s1-m2-banc-applique.log)) : `m2_preparer` accepte le vrai verrou ; outils des sondes
  présents dans l'image d'essai ; `hermetic-build.cfg` de l'image égal à celui du tag.

| # | Prédiction | Confiance et raison |
|---|---|---|
| MV1 | Sur l'hôte : « OK » pour le sha256 du verrou d'entrée (`b6d0f8f1…`), l'empreinte de la clé (`21CB256A…`), puis les cinq « OK » de `m2_preparer` et « OK   verrou : 222 paquets » ; « bootstrap : docker://…/essais-05/rocky9-bootstrap@sha256:f0ccf105… vers dir:<dépôt>/sc-stockage.poc.test@sha256:f0ccf105… » | Haute : même fonction, même verrou au banc (section C) |
| MV2 | Pod `s1-05-m2` prêt ; les sept livraisons passent ; « verrou livré : sha256 b6d0f8f1… » | Haute : mêmes gestes qu'aux étapes précédentes |
| MV3 | 222 téléchargements en HTTP 200 ; « téléchargement : 222 fichiers en N s », N < 300 | Moyenne : vault 9.7 a servi les rpm de mock dans un pod au même label (`verrou_brut`), mais `curl` est sans `-L` : une redirection donnerait un KO (pas un faux OK) |
| MV4 | « rpm -K : rc 0, 222 OK sur 222 » | Moyenne à haute : 10 sur 10 à `boot_racine`, mêmes dépôts et même clé ; 222 rpm jamais contrôlés ainsi |
| MV5 | « OK   nom, version, release, arch et sigmd5 des 222 rpm égaux au verrou » | Moyenne à haute : le sigmd5 du verrou vient de `rpm -qa` du buildroot (`installed_packages.py`, lecture), l'en-tête du fichier est le même |
| MV6 | `createrepo_c --compatibility : rc 0` en moins de 60 s ; `repomd.xml` présent, sha256 affiché | Moyenne : l'option existe en 0.20.1 (lecture de l'amont, `releve4`) ; jamais lancé dans l'image |
| MV7 | `skopeo copy --preserve-digests : rc 0` ; « OK   manifeste copié : sha256:f0ccf105… » ; l'hôte le relit et laisse le pod | Moyenne : lecture anonyme mesurée pour podman, pas pour skopeo ; CA lu par la même bibliothèque (lecture) ; option lue dans l'amont |
| MV8 | `df` final de `voie2` : utilisés entre 300 000 et 600 000 kB | Moyenne : 214 400 kB de rpm, plus l'image copiée (la couche dérivée de 95 452 kB et la couche de base, non relevée) |
| MV9 | Code 0 ; « pod s1-05-m2 laissé pour l'étape hermetique » ; durée totale de moins de 10 min ; aucune écriture dans Zot | Moyenne pour la durée, haute pour le reste |
| MH1 | Sur l'hôte : porte de `voie2` OK, pod `Running` ; dans le pod : verrou `b6d0f8f1…`, `repomd.xml` égal à celui de `voie2`, manifeste du dossier `dir:` `f0ccf105…` | Haute si MV7 tient et si `hermetique` part dans les 12 h |
| MH2 | Sources `rc 0` ; `df` avant mock égal, à 2 000 kB près, à celui de la fin de `voie2` | Haute |
| MH3 | `mock --hermetic-build : rc 0` | Moyenne : jamais lancé ; inconnues lues mais non mesurées : `podman pull` d'un chemin `dir:` qui contient « : » et « @ », dépôt `file:///` monté dans le bootstrap (`package_manager.py:509`), dnf sans `--releasever`, forme `--spec`/`--sources` jamais jouée ici |
| MH4 | Au moins une ligne, dans la sortie ou dans `root.log`, pour « Using container image: dir: », « Pulling image: dir: », « Tagging container image as mock-bootstrap- », « Checking image digest: 18d64b03… », « Calculating … image OCI digest », l'architecture, « Not updating bootstrap chroot » et « --installroot=/w/mock-h/ ». **Pas de pari sur les nombres** : `rebuild_generic` passe deux fois (src.rpm, puis rebuild) | Moyenne à haute si MH3 ; le digest affirmé repose sur `RootFS` et `Config`, que la copie par digest garde (lecture) |
| MH5 | Zéro ligne « falling back to chroot installation », « Expected digest for image » et « No space left on device », dans les deux fichiers | Moyenne à haute : repli interdit en mode hermétique (`config.py:868`) ; un écart de digest arrêterait mock |
| MH6 | Résultats : `sample-app-1.0.0-2.el9.src.rpm` de sha256 `c802e60a…` (cinquième fois) et un seul rpm binaire, `sample-app-1.0.0-2.el9.x86_64.rpm` | Moyenne : ce n'est pas le fichier des quatre relevés précédents, pris juste après `--buildsrpm`. Le rebuild reconstruit le src.rpm (`backend.py:285`) et le recopie dans le même dossier de résultats (`:756-757`, `:762-771`), par-dessus le premier (lecture) : on mesure ce second fichier, jamais relevé. Même spec, mêmes sources, même rpm-build de vault 9.7 |
| MH7 | `BUILDHOST reproducible` pour les deux rpm ; même `BUILDTIME` pour les deux | Moyenne à haute : les macros sont recopiées par le verrou et réappliquées (`releve2`, lecture) |
| MH8 | Le rpm binaire a le sha256 de celui d'`essais`, `864d55f4…` | Moyenne à faible : mêmes 222 paquets, mêmes macros, même spec et mêmes sources ; la reproductibilité du rpm n'a jamais été mesurée (c'est M3) |
| MH9 | `df` après mock, buildroot gardé : utilisés entre 1 300 000 et 2 600 000 kB, sous la capacité de 3 059 832 kB | Moyenne : 1 767 372 kB à `verrou_derivee`, où l'image dérivée restait dans le stockage de podman (tirée par son nom avant mock). Ici, mock retire son tag après la copie (`buildroot.py:303`, `podman.py:239-247`) et rien d'autre ne la nomme : elle ne devrait plus compter (lecture). Moins aussi le cache de dnf ; plus le dépôt hors ligne (214 400 kB), l'image copiée et la construction |
| MH10 | Journaux de mock archivés ; « pod s1-05-m2 supprimé » ; code 0 ; durée de moins de 15 min ; aucune écriture dans Zot | Moyenne pour la durée, haute pour le reste |

**Pas de pari** : le nombre d'entrées de `/var/lib/mock` ; les nombres de lignes de MH4 ; la valeur de `BUILDTIME`.

**Ce que ferait un écart** :
- MV3 à MV7 non tenue : `voie2` s'arrête en KO et retire le pod. La cause est lue dans le journal ; aucune relance sans analyse.
- MV7 tenue mais MH1 non tenue : pod perdu ou dépôt changé ; `voie2` est à refaire, sous un autre `PREFIXE`.
- MH3 non tenue : les fins de `hermetique.log` et de `root.log` sont lues avant toute relance. Si la forme `--spec`/`--sources`
  est en cause, le repli est un src.rpm rapatrié puis livré, par un correctif à part.
- MH9 non tenue (place) : décision avec le propriétaire (mémoire du pod, nettoyage entre `voie2` et mock).

Suite : accord de lancement de `voie2`. Rien n'est lancé.

*Note du 2026-11-17, écrite à 2026-11-17T16:12:07Z* : les tailles citées dans la note de préparation de ces étapes (219 543 349 et 749 249 076
octets), vues alors seulement à l'écran, sont archivées depuis ce commit ([journal](s1-m2-tailles.log)) ; valeurs inchangées.

## Résultat de `voie2` (note du 2026-11-17, écrite à 2026-11-17T16:19:32Z ; rien n'est réécrit)

Accord du propriétaire : « Oui, lance voie2 ». Passage le 17/11/2026 de 16:17:55 à 16:18:52 UTC (`date -u` avant et après,
`chrono.tsv`), code 0 ([journal](s1-voie2.log)). **MV1 à MV9 tenues.** Le pod `s1-05-m2` est laissé en place pour `hermetique` :
`kubectl get pod` (non archivé) le donne en `Running`, démarré à 16:17:55 UTC ; son sommeil de 43 200 s le fait tenir jusqu'au
18/11/2026 vers 04:17 UTC.

| # | Résultat |
|---|---|
| MV1 | **Tenue.** Verrou d'entrée `b6d0f8f1…`, empreinte `21CB256A…`, les cinq « OK » de `m2_preparer`, 222 paquets ; dossier `dir:` `sc-stockage.poc.test@sha256:f0ccf105…`. |
| MV2 | **Tenue.** Pod prêt, sept livraisons passées ; « verrou livré : sha256 b6d0f8f1… ». |
| MV3 | **Tenue.** 222 fichiers téléchargés en 40 s, chacun en HTTP 200 (garde du script). |
| MV4 | **Tenue.** `rpm -K` : rc 0, 222 OK sur 222, avec la seule clé de Rocky. |
| MV5 | **Tenue.** Nom, version, release, arch et sigmd5 des 222 rpm égaux au verrou. |
| MV6 | **Tenue.** `createrepo_c --compatibility` : rc 0 en 1 s ; `repomd.xml` `86ddcef1…`. |
| MV7 | **Tenue.** `skopeo copy --preserve-digests` : rc 0 en 1 s ; manifeste copié `f0ccf105…`, relu par l'hôte ; lecture anonyme de `essais-05/` par skopeo dans un pod, CA livré. |
| MV8 | **Tenue.** 312 296 kB utilisés, dans la fourchette de 300 000 à 600 000 kB. Les rpm comptent pour 214 398 kB ; le reste, environ 98 000 kB, est proche de la seule couche de 97 742 593 octets. La composition du dossier `dir:` n'est pas relevée : c'est une déduction. |
| MV9 | **Tenue.** Code 0 ; pod laissé ; 57 s au total ; aucune écriture dans Zot (l'étape n'en fait aucune, lecture du code). |

Bornes : un seul passage ; réseau présent ; les signatures sont contrôlées avec la clé de Rocky livrée, vérifiée sur l'hôte, sans
la comparer au trousseau de l'image.

Suite : accord de lancement de `hermetique`, dans le pod laissé, avant le 18/11/2026 vers 04:17 UTC. Rien d'autre n'est lancé.

## Résultat de `hermetique` (note du 2026-11-17, écrite à 2026-11-17T16:24:29Z ; rien n'est réécrit)

Accord du propriétaire : « Oui, lance hermetique ». Passage le 17/11/2026 de 16:20:06 à 16:20:54 UTC (`date -u` avant et après,
`chrono.tsv`), code 0 ([journal](s1-hermetique.log), [journaux de mock](s1-hermetique-mock.log)). **`mock --hermetic-build` a
construit sample-app avec l'image `dir:`, réseau présent ; que les paquets viennent du dépôt hors ligne est une déduction** :
`hermetic-build.cfg` n'a que ce dépôt et `reposdir=/dev/null` (fichier égal au tag, section G du banc), et son montage
`hermetic_repo` est vu, mais aucune ligne archivée ne nomme le dépôt servi. MH4 n'est tenue qu'en partie, toutes les autres le
sont. Le pod est retiré (`kubectl get pod`, non archivé : plus rien à 16:21:35 UTC).

| # | Résultat |
|---|---|
| MH1 | **Tenue.** Porte de `voie2`, pod `Running` ; dans le pod : verrou `b6d0f8f1…`, `repomd.xml` `86ddcef1…` égal à celui de `voie2`, manifeste `f0ccf105…`. |
| MH2 | **Tenue.** Sources `rc 0` ; 312 300 kB avant mock, contre 312 296 kB à la fin de `voie2`. |
| MH3 | **Tenue.** `mock --hermetic-build` : rc 0 en 47 s (src.rpm en 26 s, puis rebuild en 18 s, d'après la sortie de mock). La forme `--spec`/`--sources` a donc tourné ; le chemin `dir:` à « : » et « @ » n'a rien arrêté ; pour le dépôt `file:///` et l'absence de `--releasever`, l'appel de dnf n'est pas archivé (lecture). |
| MH4 | **Tenue en partie.** Une ligne dans la sortie et une dans `root.log` pour chacune : « Using container image: dir: », « Pulling image: dir: », le tag `mock-bootstrap-`, « Checking image digest: 18d64b03… », le calcul du digest, l'architecture, « Not updating bootstrap chroot ». **Non tenue pour `--installroot=/w/mock-h/` : 0 ligne dans les deux fichiers.** Le buildroot et le bootstrap sont pourtant sous `/w/mock-h` d'après les lignes archivées de `root.log` (`kill orphans in chroot /w/mock-h/hermetic-build/root`, montage de `/w/mock-h/hermetic-build/root/hermetic_repo`), et `/var/lib/mock` est vide ou absent. **Le motif était mal choisi** (lecture) : la forme `--installroot=` vient du `repoquery --location` du greffon de verrou (`installed_packages.py:123`, ligne 116 de [`s1-verrou_brut-mock.log`](s1-verrou_brut-mock.log) et de [`s1-verrou_derivee-mock.log`](s1-verrou_derivee-mock.log)), qui ne tourne pas en mode hermétique ; l'installation passe `--installroot` et le chemin en deux arguments (`package_manager.py:238`, [`m2-releve9.log`](m2-releve9.log)). Un prochain correctif de sonde, sous un nouveau nom, cherchera `'--installroot', '/w/mock-h/`. |
| MH5 | **Tenue.** Zéro ligne de repli, d'écart de digest et de « No space left on device ». Le digest affirmé (`image_digest` du verrou) a été vérifié sur l'image chargée depuis `dir:`. |
| MH6 | **Tenue.** `sample-app-1.0.0-2.el9.src.rpm` `c802e60a…` et un seul rpm binaire. D'après la lecture de `backend.py` (`:285`, `:756-757`), le fichier mesuré est le src.rpm reconstruit au rebuild ; il a les mêmes octets que celui des quatre relevés précédents. Les dates de `ls` ne distinguent pas les deux fichiers. |
| MH7 | **Tenue.** `BUILDHOST reproducible` et `BUILDTIME 1794787200` pour les deux rpm ; `date -u -d @1794787200` (sur l'hôte, non archivé) donne le 16/11/2026 à 00:00 UTC, la date de la dernière entrée du `%changelog` du spec, et non l'heure du build. |
| MH8 | **Tenue** (pari de confiance moyenne à faible). Le rpm binaire a le sha256 de celui d'`essais`, `864d55f4…`. |
| MH9 | **Tenue.** 1 456 532 kB utilisés après mock, buildroot gardé, dans la fourchette de 1 300 000 à 2 600 000 kB. |
| MH10 | **Tenue.** 584 lignes de journaux de mock archivées ; pod supprimé ; code 0 ; 48 s au total ; aucune écriture dans Zot (lecture du code de l'étape). |

**Ce que cela établit, et ce que cela n'établit pas** :
- Établi : le mécanisme de `--hermetic-build` de mock 6.9 fonctionne dans notre pod Kata privilégié, isolation `simple`, avec
  notre voie 2 (dépôt construit par nous, `rpm -K` 222 OK, image de bootstrap copiée par digest). Que les paquets viennent du
  dépôt hors ligne est une déduction (voir plus haut). Les macros du verrou passent : `%_buildhost` directement
  (`BUILDHOST reproducible`), les macros d'époque par l'indice d'un `BUILDTIME` égal à la date du changelog.
- MH8 : deux constructions donnent le même rpm binaire, au même octet. Celle d'`essais` avait un bootstrap brut et des dépôts en
  ligne ; celle-ci a un bootstrap dérivé et le dépôt hors ligne. C'est un premier indice de reproductibilité, pas la preuve de M3,
  qui demande deux `--hermetic-build` sans réseau depuis la fermeture restaurée, dans deux répertoires différents.
- Non établi : l'hermétisme. Le réseau était ouvert (label `prefetch-rpm`) et aucune mesure ne dit si quelque chose l'a utilisé
  pendant le build. La fermeture dans Zot, sa restauration par digest et la déduplication restent à faire : **M2 n'est pas passé.**
- Bornes : un seul passage. Seules les fins de `root.log` (400 lignes) et de la sortie de mock (80 lignes) sont archivées, et le
  pod est retiré : l'appel de dnf, le dépôt servi et le nombre de paquets installés ne sont plus vérifiables.

Suite, sans décision : préparer à sec la fermeture de M2 (poussée dans Zot sous `deps/sample-app/mock-buildroot-lock`, avec le
rpm de mock et l'image de bootstrap, restauration par digest, déduplication), avec un accord à part pour l'écriture dans Zot.
Pour M3, la sonde devra archiver `root.log` entier, `installed_pkgs.log` et la sortie entière de mock. Rien n'est lancé.

## Fermeture de M2 : étapes `collecte`, `fermeture` et `restauration` préparées à sec (note du 2026-11-17, écrite à 2026-11-17T16:53:20Z ; rien n'est réécrit), NON APPLIQUÉ

Préparées sur « continue », après le push de `c836f9f`. Le conseiller a relu l'approche avant l'écriture, puis le correctif
avant ce commit ; trois corrections en sont venues (garde des tags, mesure de la place, compte des écarts du banc). Correctif
[`../s1-fermeture.patch`](../s1-fermeture.patch) (`dcfba247…`) : insertions seules dans `s1.sh` (`8554910f…`), copie
`7cd2edd0…`. Trois étapes, trois accords, comme la 06 S2.

- **`collecte`** (pod `s1-05-mf`, aucune écriture dans Zot). Le pod de `voie2` est retiré et `voie2` n'a archivé aucun sha256
  par rpm : rien ne relie des fichiers à pousser aux 222 « OK » de `rpm -K`. `collecte` rejoue donc `VOIE2_M2` tel quel, dans un
  autre pod et un autre dossier (`$T/mf`, journal `mf-voie2`) ; `m2-voie2.log` et `$T/m2` ne sont pas touchés.
  - Le rpm de mock 6.9-1 est retéléchargé d'EPEL. Sa porte est le sha256 épinglé `a5043350…`, relevé à `racine`. Le banc le
    retrouve dans le primary d'EPEL du dernier passage de `hote` (17/11, 08:30 UTC) (« rpm de mock dans le vrai primary d'EPEL
    du dernier hote », [journal](s1-fermeture-banc.log)) ; EPEL a pu bouger depuis, et un 404 serait un KO suivi d'une décision.
  - `rpm -K` du rpm de mock se fait avec la seule clé d'EPEL, dans une rpmdb à part : les 222 restent contrôlés par la seule clé
    de Rocky. Le rpm est rangé sous `outils/`, hors du dépôt que lit mock.
  - La fermeture est assemblée sous `/w/fermeture` : `depot/` (rpm du verrou, `repodata`, dossier `dir:` de l'image),
    `verrou.json` et `outils/`. Elle est listée avec les sha256 et tailles, puis rapatriée par tar.
  - Contrôles sur l'hôte : liste exacte des fichiers, ni plus ni moins ; sha256 et taille de chaque rpm égaux au primary de
    vault 9.7 vérifié par `hote97` ; fichiers de `repodata` égaux à `repomd.xml` ; blobs du dossier `dir:` égaux à leur nom ;
    manifeste égal au digest de `boot_image` ; verrou `b6d0f8f1…` ; liste du pod égale à l'arbre rapatrié. Le pod est retiré.
- **`fermeture`** (écriture dans Zot, **définitive**, compte `poc-ecriture`). Elle reprend celle de la 06 S2 : `closure.sh` de la
  03, un fichier par couche, deux envois sous `$PREFIXE` et `$PREFIXE-bis`, même digest attendu. Écarts :
  - fermeture recontrôlée avant l'envoi ;
  - garde des tags fondée sur une lecture réussie : catalogue de Zot lu, puis tags du dépôt s'il y figure ; une lecture en
    échec, ou un tag déjà présent, arrête l'étape avant tout envoi (lecture de `zot.json` versionné : `poc-ecriture` a le droit
    `update`, un tag existant serait donc déplacé) ;
  - digest écrit dès le premier envoi ; couches comparées avec leur taille ; config et couches de l'image relevées sous
    `essais-05/rocky9-bootstrap` ;
  - place utilisée de `/var/lib/zot` (`df` en octets sur `sc-stockage`, sans sudo) : deux lectures avant l'envoi, pour voir la
    dérive, puis une après chaque envoi ; sans seuil ; une lecture illisible après l'envoi s'affiche « illisible » sans arrêter
    l'étape ;
  - inode et nombre de liens de la config et des couches de l'image sous les deux dépôts (`stat` sans sudo) : relevé brut, sans
    pari. La disposition `/var/lib/zot/<dépôt>/blobs/sha256/<hex>` et le stockage par liens durs sont supposés, jamais relevés
    sur `sc-stockage` ; « illisible » couvre aussi bien un refus qu'un chemin absent.
- **`restauration`** : pull par digest dans un dossier vide ; liste, taille et sha256 de chaque fichier comparés à la liste de
  `collecte`. Elle relit les inodes et liens : ce relevé-là est rejouable, contrairement à la croissance de Zot au premier envoi.
- **Droits** : `deps/**` relève de la règle `**` de la configuration versionnée de Zot (`08-trust-plane/stockage/zot.json`) :
  lecture anonyme, `poc-ecriture` lit, crée et met à jour. C'est une lecture du fichier versionné ; la configuration déployée
  n'est pas relue.

**Bancs** :
- Banc ([script](s1-fermeture-banc.sh), `99b9cbd9…`, [journal](s1-fermeture-banc.log)), lancé à 16:48:18 UTC : tenu, 82 OK. Il
  tourne hors cluster et hors Zot, contre un registre crane local en loopback, avec le vrai `closure.sh` et le vrai oras 1.3.6.
  - Mesuré : les chemins du dossier `dir:`, qui contiennent « : » et « @ », passent l'envoi d'oras et reviennent à l'identique
    par `oras pull`.
  - Mesuré aussi : deux envois donnent le même digest. Sont refusés avant tout envoi : un tag déjà présent (dépôt lu), un
    catalogue illisible (registre injoignable) et une fermeture changée depuis `collecte`. Une place illisible après l'envoi
    s'affiche sans arrêter l'étape.
  - Les contrôles de l'hôte refusent treize écarts sur une doublure ; sur les vrais primary de vault 9.7, les 222 emplacements
    du verrou sont trouvés.
- Deux passages antérieurs, scripts non archivés :
  - à 16:39:16 UTC, non tenu, à cause de deux défauts du banc seul ([journal](s1-fermeture-banc-passage1.log)) : le dossier du
    registre local n'était pas créé, d'où toute la section E en échec, et le libellé « capacité de /w » était pris pour un
    chemin ;
  - à 16:40:09 UTC, tenu, 76 OK ([journal](s1-fermeture-banc-passage2.log)), sur la première copie (`bc252237…`), avant la
    relecture du correctif.
- N3/N4 ([`s1-n34-banc.sh`](s1-n34-banc.sh)) sur la copie finale, à 16:48:56 UTC : tenu, 35 OK ([journal](s1-fermeture-banc-n34.log)).
- Non couvert : vrai pod, vrais rpm et vrai `rpm -K`, `createrepo_c`, `skopeo`, kubectl, réseau, Zot (droits déployés,
  déduplication, droits de lecture et disposition des blobs sous `/var/lib/zot`) ; `oras repo ls` et `oras repo tags` n'ont
  jamais été joués contre Zot (un échec arrête l'étape avant tout envoi).

**Ce que le passage pourra établir, et pas plus** :
- Fermeture restaurable par digest : c'est la mesure de `restauration`.
- Déduplication : il n'existe qu'une fermeture, comme pour la 06 S2. On pourra mesurer :
  - au second envoi, le même digest et la croissance de Zot ;
  - le digest de chaque couche, égal au sha256 du fichier (et, pour les rpm, à celui du primary) ;
  - au premier envoi, la croissance de Zot comparée aux octets de la fermeture, dont ceux de l'image, déjà présents sous
    `essais-05/rocky9-bootstrap` ;
  - les inodes et liens des blobs de l'image sous les deux dépôts, si `stat` est permis sans sudo.

  Le `df` porte sur tout le système de fichiers : d'autres écritures ne sont pas exclues. Dire si cela suffit pour
  « déduplication mesurée », donc pour M2, revient au propriétaire.
- `repomd.xml` sera relevé sans pari d'égalité avec `86ddcef1…` : la fermeture poussée n'est pas, à l'octet près, le dépôt du
  build de 16:20. Construire depuis la fermeture restaurée relève de M3.
- `voie2` n'a relevé que `manifest.json` dans le dossier `dir:` : la liste exacte des fichiers écrits par skopeo n'est pas
  connue, ni le type de somme de `repomd.xml`. La liste « ni plus ni moins » peut donc donner un KO à `collecte`, avant toute
  écriture dans Zot.

Suite : appliquer `s1-fermeture.patch` à `s1.sh`, sur accord ; puis prédictions des trois étapes, commitées avant tout passage ;
puis un accord par étape. Rien n'est lancé.

## `s1-fermeture.patch` appliqué à `s1.sh` (note du 2026-11-17, écrite à 2026-11-17T17:09:53Z ; rien n'est réécrit), NON LANCÉ

Décision du propriétaire : question « J'applique s1-fermeture.patch à s1.sh ? », réponse « Oui, applique-le ».
- `git apply` de [`../s1-fermeture.patch`](../s1-fermeture.patch) à 17:08:38 UTC (`date -u` avant et après, code 0) : `s1.sh`
  passe de `8554910f…` à `7cd2edd0…`, la copie bancée.
- Banc repassé sur le fichier du dépôt, lancé à 17:08:51 UTC : tenu, 82 OK ([journal](s1-fermeture-banc-applique.log)). Il
  compare ce fichier à l'ancien `s1.sh` (`8554910f…`, tiré de `HEAD`), placé avec le verrou, `closure.sh` et `mise.toml` dans
  un arbre de travail du scratchpad (`<avant>` dans le journal). Écart au journal de la copie : heures et `df` de l'hôte
  seulement.
- Deux lignes datées ajoutées ensuite à l'en-tête de `s1.sh`, après l'entrée `restauration` : « Correctif appliqué au dépôt le
  17/11/2026 à 17:08:38 UTC (« Oui, applique-le »), sha256 égal à la copie bancée (7cd2edd0…) ; non lancé. ». `s1.sh` vaut
  alors `4c3adb53…`.
- N3/N4 ([`s1-n34-banc.sh`](s1-n34-banc.sh)) sur ce fichier final, lancé à 17:09:29 UTC, python3 3.13.12 : tenu, 35 OK
  ([journal](s1-fermeture-banc-n34-applique.log)).

Suite : prédictions de `collecte`, `fermeture` et `restauration`, écrites et commitées avant tout passage, puis un accord par
étape (`fermeture` écrit dans Zot, définitivement). Rien n'est lancé.

## Étapes `collecte`, `fermeture` et `restauration` : prédictions (note du 2026-11-17, écrite à 2026-11-17T17:16:20Z, avant tout passage ; rien n'est réécrit), NON LANCÉ

Commandes prévues, depuis la racine du dépôt, une par accord nommé, `date -u` avant et après, code par `PIPESTATUS`, sortie dans
un fichier : `env -u PREFIXE -u ISOLATION DISTRO=rke2 KUBECONFIG=… mise exec -- poc/bricks/05-rpm-mock/s1.sh collecte </dev/null`,
puis la même avec `fermeture`, puis avec `restauration`. `s1.sh` vaut `4c3adb53…`. Journaux attendus : `s1-collecte.log`,
`s1-fermeture.log`, `s1-restauration.log` (aucun n'existe). Tags de la fermeture : `s1` et `s1-bis`. **`fermeture` écrit dans
Zot de façon définitive** : Zot n'autorise pas la suppression.

**Appuis mesurés** :
- `voie2` ([`s1-voie2.log`](s1-voie2.log)) : 222 rpm téléchargés en 40 s, `rpm -K` 222 OK, `createrepo_c` en 1 s, `skopeo copy`
  en 1 s, manifeste `f0ccf105…` ; 312 296 kB utilisés sous `/w` à la fin.
- `boot_image` ([`s1-boot_image.log`](s1-boot_image.log)) et banc local ([`s1-boot-image-local.log`](s1-boot-image-local.log)) :
  une seule couche, de 97 742 593 octets.
- Tailles du verrou ([journal](s1-m2-tailles.log)) : 219 543 349 octets de rpm. Rpm de mock : 258 845 octets (primary d'EPEL
  du dernier `hote`, relu le 17/11 avant ce commit ; vu à l'écran, non archivé ailleurs que dans ce texte) ; verrou : 111 561 octets ([`s1-verrou_derivee.json`](s1-verrou_derivee.json), taille du fichier commité).
- Banc du dépôt ([`s1-fermeture-banc-applique.log`](s1-fermeture-banc-applique.log)) : 82 OK, dont l'envoi et la restauration
  des chemins à « : » et « @ » par le vrai `closure.sh` et oras 1.3.6, contre un registre local.
- Zot : 5 551 Mo libres sous `/` de `sc-stockage` à `prealables` ([`s1-prealables.log`](s1-prealables.log), 16/11, 22:49 UTC),
  avant `amorce`, `image` et `boot_image` ; `/var/lib/zot` est sous `/`. `dedupe: true` dans la configuration versionnée.

| # | Prédiction | Confiance et raison |
|---|---|---|
| C1 | Sur l'hôte : « OK » pour le sha256 du verrou, les empreintes des clés de Rocky et d'EPEL, et « rpm de mock dans le primary d'EPEL du dernier passage de hote : sha256 a5043350… » ; les cinq « OK » de `m2_preparer` | Haute : verrou, clé de Rocky et `m2_preparer` comme à `voie2` ; primary d'EPEL lu au banc ; l'empreinte d'EPEL comparée à `$T/fp-epel` n'a été jouée ni à `voie2` ni au banc, mais ce fichier existe et vaut l'empreinte que `gpg --show-keys` donne pour la clé livrée (`FF8AD134…`, relu le 17/11 avant ce commit) |
| C2 | Pod `s1-05-mf` prêt ; `mf-voie2` reproduit `voie2` : 222 téléchargements, `rpm -K` 222 OK, en-têtes égaux, `createrepo_c` rc 0, « OK   manifeste copié : sha256:f0ccf105… » | Haute : même script, mêmes dépôts figés (vault 9.7) |
| C3 | `mf-collecte` : rpm de mock en HTTP 200, sha256 `a5043350…`, « rpm -K du rpm de mock (seule clé d EPEL) : rc 0 ; digests signatures OK » | Moyenne : `racine` a tiré d'EPEL (`dl.fedoraproject.org`, `baseurl` de `EPEL9`) dans un pod au même label ; mais EPEL bouge, et 6.9-1 pourrait en avoir été retiré depuis 08:30. Un 404 ou une redirection (`curl` est sans `-L`) donnerait un KO, pas un faux OK |
| C4 | « autres entrées que fichiers et dossiers : 0 » ; « fichiers de la fermeture : N », N entre 230 et 240 (222 rpm, `repodata`, quatre fichiers d'image, verrou, rpm de mock) | Moyenne : le nombre de fichiers de `repodata` n'a jamais été relevé |
| C5 | Rapatriement par tar sans erreur ; pod retiré | Moyenne à haute : un rapatriement de 258 Mo a passé à `boot_racine` ; ici, environ 320 Mo |
| C6 | Sur l'hôte : « rpm du verrou trouvés dans les primary de vault 9.7 vérifiés par hote97 : 222 sur 222 », puis « OK   fermeture conforme » ; classe `image` : 4 fichiers (manifeste, `version`, config, couche) | Moyenne : la liste exacte des fichiers écrits par skopeo et le type de somme de `repomd.xml` n'ont jamais été relevés ; un écart donnerait un KO avant toute écriture dans Zot |
| C7 | Total de la fermeture entre 317 656 348 et 320 050 000 octets | Moyenne à haute. Borne basse : 219 543 349 (rpm) + 97 742 593 (couche) + 258 845 (rpm de mock) + 111 561 (verrou), sans la config, le manifeste, `version` ni `repodata`. Borne haute : `voie2` a mesuré 312 296 kB (319 791 104 octets) utilisés sous `/w`, qui contenaient déjà les rpm, `repodata`, l'image et le verrou, plus d'autres fichiers ; s'y ajoute le rpm de mock |
| C8 | Code 0 ; durée de moins de 15 min ; aucune écriture dans Zot | Moyenne pour la durée, haute pour le reste |
| F1 | « OK   arbre égal à la liste » avant l'envoi ; catalogue lu ; « deps/sample-app/mock-buildroot-lock absent » | Haute : aucune étape du dépôt git ne nomme ce dépôt avant celle-ci (lecture du dépôt git, pas de Zot) ; lecture de `oras repo ls` contre Zot jamais jouée (un échec arrêterait l'étape avant l'envoi) |
| F2 | « OK   blobs de l'image sous essais-05/rocky9-bootstrap = blobs du dossier dir: » | Haute : copie par digest (`--preserve-digests`) |
| F3 | Place libre de Zot au-dessus du double de la fermeture | Haute : 5 551 Mo le 16/11, moins les images poussées depuis |
| F4 | Deux envois en rc 0 ; même digest ; manifeste relu égal ; couches égales à la liste (titre, digest, taille) | Haute : mêmes gestes qu'au banc, et qu'à la 06 S2 |
| F5 | Croissance de `/var/lib/zot` au premier envoi entre 200 000 000 et 260 000 000 octets ; sans partage des blobs de l'image, elle serait d'au moins 317 656 348 octets (borne basse de C7) | Moyenne : les blobs de l'image sont déjà sous `essais-05` ; le partage entre dépôts par `dedupe` est lu, pas mesuré ; d'autres écritures sur `/` peuvent fausser le compte |
| F6 | Croissance au second envoi de moins de 5 000 000 octets | Moyenne à haute : mêmes blobs, seul le tag change ; même bruit possible |
| F7 | Durée de l'envoi 1 de moins de 5 min, de l'envoi 2 de moins de 1 min ; code 0 | Moyenne : `boot_image` a poussé 97 Mo en 10 s environ, mais par crane |
| F8 | Si `stat` est lisible et la disposition supposée exacte : même inode sous les deux dépôts et au moins deux liens, pour la config et la couche | Faible : partage par liens durs lu, jamais relevé ; « illisible » ne réfute rien |
| R1 | Pull par digest rc 0 ; « OK   arbre égal à la liste » pour tous les fichiers de la liste ; code 0 en moins de 5 min | Haute si F4 tient : mêmes gestes qu'au banc |

**Pas de pari** :
- la lisibilité de `stat` sans sudo sous `/var/lib/zot`, la disposition des blobs (supposée) et donc les inodes et liens ;
- le sha256 de `repomd.xml` (aucune égalité attendue avec `86ddcef1…`) ;
- le nombre de dépôts du catalogue et la dérive entre les deux lectures de place d'avant l'envoi.

**Ce que ferait un écart** :
- C3 à C6 non tenue : `collecte` s'arrête en KO, avant toute écriture dans Zot ; la cause est lue dans le journal, sans relance
  avant analyse. Un 404 sur le rpm de mock appelle une décision du propriétaire, sans source de rechange improvisée.
- F1 à F3 non tenue : rien n'est envoyé.
- Échec après un premier envoi réussi : `fermeture.digest` est déjà écrit ; la relance se fait sous un autre `PREFIXE`, car la
  garde refuserait le tag `s1`.
- Seconde lecture de place d'avant l'envoi illisible : la croissance du premier envoi s'affiche « illisible », même si la
  première lecture était bonne ; F5 est alors non mesurée.
- F5 hors bornes : aucune conclusion sur la déduplication sans relevé des liens ; la décision revient au propriétaire.
- Toute relance de `collecte` ou de `restauration` se fait sous un autre `PREFIXE`, pour ne réécrire aucun journal archivé.
- Une fois `fermeture` passée, `collecte` ne se relance plus : elle efface `$T/mf`, donc `fermeture.digest` et la liste
  attendue, et un nouveau `repodata` donnerait un autre digest.
- Les deux lectures de place d'avant l'envoi sont à une seconde d'écart environ : elles ne bornent pas la dérive de `/` sur la
  durée d'un envoi.

Ce que M2 demande, « fermeture restaurable par digest ; déduplication mesurée », sera jugé après R1. Dire si F5 et F6, sur une
seule fermeture, suffisent pour « déduplication mesurée » revient au propriétaire.

Suite : accord de lancement de `collecte`. Rien n'est lancé.

## Étape `collecte` passée (note du 2026-11-17, écrite à 2026-11-17T17:26:11Z ; rien n'est réécrit)

Décision du propriétaire : question « Je lance l'étape collecte ? », réponse « Oui, lance collecte ». Lancée le 17/11/2026 de
17:21:34 à 17:23:47 UTC (`date -u` avant et après, `chrono.tsv`), code 0, `s1.sh` `4c3adb53…`
([journal](s1-collecte.log)). Aucune écriture dans Zot (lecture du code : l'étape n'appelle ni oras, ni crane, ni
`closure.sh`) ; pod `s1-05-mf` retiré (absent à une relecture qui a suivi, vue à l'écran, non archivée).

| # | Tenue ? | Mesure |
|---|---|---|
| C1 | Oui | Verrou, clés de Rocky et d'EPEL (`FF8AD134…`, égale à `fp-epel`), rpm de mock dans le primary d'EPEL de `hote`, cinq « OK » de `m2_preparer` |
| C2 | Oui | 222 rpm en 61 s (40 s à `voie2`), `rpm -K` 222 OK, en-têtes égaux au verrou, `createrepo_c` rc 0 en 1 s, manifeste copié `f0ccf105…` |
| C3 | Oui | Rpm de mock téléchargé (le code HTTP n'est pas affiché : un code autre que 200 aurait donné un KO), sha256 `a5043350…`, `rpm -K` avec la seule clé d'EPEL : rc 0, « digests signatures OK » |
| C4 | Oui | 235 fichiers (222 rpm, 7 de `repodata`, 4 d'image, verrou, rpm de mock), aucune autre entrée |
| C5 | Oui | Rapatriement par tar : aucune ligne de succès propre, mais « liste du pod égale » dans la ligne « OK   fermeture conforme » ; pod retiré |
| C6 | Oui | 222 rpm sur 222 trouvés dans les primary de vault 9.7 et égaux : sha256 (mesuré) et taille (contrôle du code, non affiché) ; « OK   fermeture conforme » ; classe `image` : 4 fichiers (manifeste, `version`, config, couche) |
| C7 | Oui | 319 086 430 octets, entre 317 656 348 et 320 050 000 ; `repodata` : 1 429 178 octets ; image : 97 743 497 octets |
| C8 | Oui | Code 0 en 2 min 13 s ; aucune écriture dans Zot (lecture du code ; rien n'a été relu dans Zot) |

**Lecture** :
- `repomd.xml` vaut `108f954a…`, et non `86ddcef1…` comme à `voie2` : c'était sans pari. La fermeture n'est donc pas, à l'octet
  près, le dépôt du build `hermetique` de 16:20. Le manifeste de l'image (`f0ccf105…`) et le verrou (`b6d0f8f1…`) sont égaux des
  deux côtés. Pour les rpm, `voie2` n'a archivé aucun sha256 : sont mesurés des deux côtés `rpm -K` 222 OK, en-têtes et
  `sigmd5` égaux au verrou, mêmes URL de vault 9.7 ; l'égalité octet pour octet avec les rpm du build de 16:20 n'est pas mesurée.
- La fermeture est sur l'hôte, sous `$T/mf/fermeture`, avec sa liste attendue (235 lignes, sha256 `7c779f5d…`), que `fermeture`
  et `restauration` relisent.
- Repères pour lire F5 (pas une nouvelle prédiction ; les bornes de F5 ne changent pas) : fermeture hors config et couche de
  l'image, 221 343 594 octets ; config et couche, 97 742 836 octets ; total, 319 086 430 octets.
- Ce qui reste de M2 : l'écriture dans Zot (`fermeture`, définitive), puis `restauration`. **M2 n'est pas passé.**

Suite : accord de lancement de `fermeture`, qui écrit dans Zot de façon définitive ; l'additif de l'ADR 0001 pour la fermeture
viendra avec `restauration`. Rien n'est lancé.

## Étape `fermeture` passée (note du 2026-11-17, écrite à 2026-11-17T17:49:34Z ; rien n'est réécrit)

Décision du propriétaire : question « Je lance fermeture, qui écrit dans Zot définitivement ? », réponse « Oui ». Lancée le
17/11/2026 de 17:46:06 à 17:47:29 UTC (`date -u` avant et après ; `chrono.tsv` : 17:46:07 et 17:47:29), code 0, `s1.sh`
`4c3adb53…` ([journal](s1-fermeture.log)). **Écriture définitive dans Zot** : fermeture
`deps/sample-app/mock-buildroot-lock@sha256:f235a98b46d82b2d295cd39e869eb07344938e8896fc4f7465171687e9c48417`, envoyée sous les tags `s1` et `s1-bis` (deux envois en rc 0 ; tags non relus
ensuite). Le même digest est écrit sur l'hôte, dans
`$T/mf/fermeture.digest` (relu après le passage, vu à l'écran, non archivé).

| # | Tenue ? | Mesure |
|---|---|---|
| F1 | Oui | « OK   arbre égal à la liste » (235 fichiers, 319 086 430 octets) ; catalogue lu (143 dépôts ; par `oras repo ls`, lecture du code) ; dépôt absent |
| F2 | Oui | Config `7bf628be…` et couche `22495746…` sous `essais-05/rocky9-bootstrap` égales aux blobs du dossier `dir:` |
| F3 | Oui | 5 055 672 320 octets libres, au-dessus de 2 × 319 086 430 = 638 172 860 |
| F4 | Oui | Code 0 (un rc non nul d'un envoi aurait arrêté l'étape : lecture du code) ; même digest aux deux envois ; manifeste relu égal ; 235 couches, égales à la liste de collecte (titre, digest, taille) |
| F5 | Oui | 225 861 632 octets de plus au premier envoi, entre 200 000 000 et 260 000 000, et sous 317 656 348 |
| F6 | Oui | 253 952 octets de plus au second envoi, sous 5 000 000 |
| F7 | Oui | Envoi 1 en 80 s, envoi 2 en 1 s ; code 0 |
| F8 | Non mesurée | « illisible » pour les deux blobs sous les deux dépôts (refus de lecture ou chemin absent, non distingués) : ni confirmée ni réfutée |

**Lecture** :
- F5 : la croissance mesurée (225 861 632 octets) dépasse de 4 518 038 octets la part de la fermeture hors config et couche de
  l'image (221 343 594), et reste sous la taille de la fermeture entière (319 086 430). Elle est compatible avec une config et une
  couche de l'image non stockées une seconde fois. Ce n'est pas une preuve du mécanisme : `df` compte tout `/` de `sc-stockage`,
  d'autres écritures ne sont pas exclues pendant les 80 s de l'envoi, et F8 n'a rien relevé. L'écart de 4 518 038 octets n'est
  pas expliqué (arrondi aux blocs, métadonnées de Zot ou autres écritures : rien de mesuré).
- F6 : un second envoi des mêmes fichiers sous un autre tag a ajouté 253 952 octets.
- La place libre lue avant l'envoi (5 055 672 320 octets) est à lire avec la mesure du 16/11 à `prealables` (5 551 Mo), prise
  avant `amorce`, `image` et `boot_image` ; les unités des deux relevés ne sont pas comparées ici.
- Le catalogue compte 143 dépôts. Le relevé du 17/11 à 14:51:40 UTC, fait par crane, en comptait 142, avant que `boot_image`
  ne crée `essais-05/rocky9-bootstrap`. Les deux relevés sont compatibles, mais la liste des dépôts n'a pas été comparée.
- `oras repo tags` n'a toujours pas été joué contre Zot (dépôt absent au passage). Le dépôt existe désormais : une relance
  sous un autre `PREFIXE` jouerait cette branche de la garde pour la première fois.
- F8 reste le seul relevé prévu du mécanisme de partage ; un `stat` sous sudo, lancé par le propriétaire, pourrait le donner
  (non demandé, ne bloque pas R1).
- **M2 n'est pas passé** : il reste `restauration` (R1), un pull par digest dans un dossier vide. Dire si F5 et F6, sur une
  seule fermeture, suffisent pour « déduplication mesurée » revient au propriétaire.

Suite : accord de lancement de `restauration` (lecture seule dans Zot) ; l'additif de l'ADR 0001 viendra après R1. Rien n'est
lancé.

## Étape `restauration` passée (note du 2026-11-17, écrite à 2026-11-17T17:55:16Z ; rien n'est réécrit)

Décision du propriétaire : question « Je lance restauration (lecture seule dans Zot) ? », réponse « Oui ». Lancée le 17/11/2026
de 17:53:00 à 17:53:01 UTC (`date -u` avant et après, `chrono.tsv`), code 0, `s1.sh` `4c3adb53…`
([journal](s1-restauration.log)).

| # | Tenue ? | Mesure |
|---|---|---|
| R1 | Oui | `closure.sh pull` par digest (`sha256:f235a98b…`) dans un dossier vidé juste avant (`rm -rf`, lecture du code) ; « OK   arbre égal à la liste : 235 fichiers, 319 086 430 octets » (chaque fichier comparé à la liste de collecte : chemin, taille et sha256, lecture du code) ; code 0, en moins de 5 min |

**Lecture** :
- Durée de moins de 2 s pour 319 086 430 octets (deux `date -u`, à 17:53:00 et 17:53:01). `ORAS_CACHE` n'est pas défini
  dans l'environnement de `mise exec` et n'apparaît nulle part sous `poc/`, `tools/` ni dans `mise.toml` (relu après le
  passage, vu à l'écran, non archivé) : rien n'indique un cache local d'oras. Le débit n'est pas mesuré à part.
- Inodes et liens relus : toujours « illisible » (F8 reste non mesurée).
- Le dossier restauré est sur l'hôte, sous `$T/mf/restauree` (235 fichiers, 319 086 430 octets par `du -sb`, vu à l'écran, non
  archivé).

**Preuve de M2** (« fermeture restaurable par digest ; déduplication mesurée ») :
- Fermeture restaurable par digest : tenue (R1), pour une fermeture qui contient les rpm du verrou, leur `repodata`, le verrou,
  l'image de bootstrap dérivée en dossier `dir:` et le rpm de mock.
- Déduplication : F5 et F6 mesurées sur une seule fermeture (225 861 632 octets de plus au premier envoi, compatible avec une
  config et une couche de l'image non stockées une seconde fois ; 253 952 au second) ; mécanisme non relevé (F8).
  Dire si cela suffit pour « déduplication mesurée » revient au propriétaire.
- Le reste du contenu de M2 (configuration de mock versionnée, macros d'OBS) n'est pas réévalué dans cette note. **M2 n'est
  pas déclaré passé.**
- Aucun build n'a été fait à partir de la fermeture restaurée ; le build sans réseau reste à mesurer (M3).

Suite : décision du propriétaire sur la déduplication. Rien n'est lancé.

## Décision du propriétaire sur la déduplication ; M2 (note du 2026-11-17, écrite à 2026-11-17T18:18:04Z ; rien n'est réécrit)

Question « Pour la déduplication de M2 : F5 et F6 vous suffisent-elles ? » (choix proposés : « Oui, ça suffit » ou un relevé
`stat` sous sudo lancé par le propriétaire), réponse « Oui ». **Décision : F5 et F6, mesurées sur une seule fermeture, valent
« déduplication mesurée » pour M2.** Le mécanisme de partage reste non relevé (F8).

**Contenu de M2 relu** (README, table des jalons) :

| Élément | Où c'est | Nature |
|---|---|---|
| Configuration de mock versionnée, D2 (a) | `s1.sh` (dépôt git) : `baseurl` fixes sur vault 9.7 ; les 222 URL du verrou sont sous `vault/rocky/9.7/` | Lecture du dépôt et du verrou commité |
| Digest du bootstrap | Injecté au lancement dans la configuration `poc-rocky-9.7-derivee-x86_64`, depuis `$T/boot-image.digest`, hors dépôt (absent de `s1.sh` : lecture du code) ; versionné par le verrou commité : `bootstrap_image` = `essais-05/rocky9-bootstrap@sha256:f0ccf105…`, `bootstrap_image_ready` vrai | Mesuré à `verrou_derivee` (VD1 à VD17) |
| Macros d'OBS | Les quatre macros dans `s1.sh`, aux mêmes valeurs que dans [`poc.prjconf`](../../../benchmarks/obs/projets/poc.prjconf) du banc OBS, et recopiées dans le verrou ([`s1-verrou_derivee.json`](s1-verrou_derivee.json)) | Lecture ; leur effet sur le rpm relève de M3 |
| Verrou calculé | `verrou_derivee` : 222 rpm | Mesuré |
| Signatures des rpm vérifiées | `collecte` : `rpm -K` 222 OK (seule clé de Rocky ; « OK » compte les lignes terminées par « digests signatures OK » : lecture du code), rpm de mock vérifié par la seule clé d'EPEL | Mesuré |
| Fermeture dans Zot, avec le rpm de mock et l'image de bootstrap | `deps/sample-app/mock-buildroot-lock@sha256:f235a98b…` | Mesuré (`fermeture`, F1 à F7) |

**Preuve attendue de M2** : fermeture restaurable par digest (R1, tenue) ; déduplication mesurée (F5 et F6, retenues par le
propriétaire). Le propriétaire a tranché la déduplication, pas le jalon. **Conclusion tirée de cette relecture : M2 est tenu**,
avec trois réserves écrites :
- déduplication sur une seule fermeture, mécanisme de partage non relevé ;
- la « configuration versionnée » est un texte produit par `s1.sh`, pas un fichier `.cfg` à part ;
- le digest du bootstrap n'est pas écrit dans le dépôt de la configuration : il est injecté au lancement, et versionné seulement
  par le verrou commité et les journaux.

M1 n'est pas réévalué ici.

Suite : M3 (deux `--hermetic-build` sans réseau depuis la fermeture restaurée), à préparer à sec sur accord. Rien n'est lancé.
