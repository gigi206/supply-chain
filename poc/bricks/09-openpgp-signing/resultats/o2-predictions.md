# Brique 09, O2 : prédictions

O2 (README, « Jalons proposés ») : clé OpenPGP du PoC selon D2, environnements de signature Rocky 9.8 et Debian 13, paquets épinglés et vérifiés. Préparation à sec demandée par le propriétaire le 19/11/2026 (« Oui, prépare O2 »).

## Relevé préalable `o2-releve.sh` (lectures locales et publiques seulement)

Écrites le 19/11/2026 avant tout lancement du script (heure : celle du commit qui les porte).

| # | Prédiction | Confiance |
|---|---|---|
| RL1 | Amorce `rockylinux:9.8` (`ed654c69`) : manifeste, configuration et couche égaux à leur sha256 (comme le 18/11 en 05). `rpm`, `rpmkeys`, `dnf-3` et la clé `RPM-GPG-KEY-Rocky-9` présents ; `rpmsign` et `createrepo_c` absents ; **aucun greffon dnf** (`download.py` absent), comme mesuré en 9.7 | moyenne : rpm et dnf relevés le 18/11 ; gpg et greffons jamais relevés en 9.8 |
| RL2 | Présence de `usr/bin/gpg2` ou `usr/bin/gpg` dans l'amorce Rocky | **pas de prédiction** (relevé) |
| RL3 | Amorce `debian:trixie-20261104-slim` (`7378260c…`) : sha256 égaux ; `apt-get`, `dpkg`, `gpgv` et `debian-archive-keyring.gpg` présents ; `gpg`, `gpg-agent` et `apt-ftparchive` absents | moyenne : image `slim` ; contenu jamais listé |
| RL4 | Instantané `20261105T000000Z` : `InRelease` signé par les 3 clés de la 06 ; `Packages.xz` égal au sha256 de `InRelease` ; `gnupg` et `gpg` en **2.4.7-21+deb13u1**, `gpgv` en **2.4.7-21+deb13u1+b5** ou en 2.4.7-21+deb13u1 ; `apt-utils` en 3.0.3 | moyenne : madison lit la suite stable du 19/11, pas l'instantané du 05/11 ; un `+deb13u1` publié après le 05/11 donnerait un conflit avec D4 |
| RL5 | `repomd.xml` de `vault/rocky/9.8` (BaseOS, AppStream) vérifiés par la clé Rocky 9 et **égaux** à ceux de `pub/9.8` relevés le 19/11 ; versions du relevé retrouvées (`gnupg2` 2.3.3-5.el9_7, `rpm-sign` 4.16.1.3-40.el9, `createrepo_c` 0.20.1-4.el9) ; `python3-dnf-plugins-core` présent dans BaseOS | moyenne : la 05 a mesuré l'égalité de vault et de pub le 18/11 ; un 9.8 encore servi par pub peut avoir bougé |
| RL6 | Hôte : `unshare --map-auto --map-root-user -n` fonctionne (code 0) ; `secrets-depot.sh` ne lit que les dossiers `08/secrets` et `10/secrets` et n'a pas de motif « BEGIN PGP » ; podman non nécessaire au mécanisme retenu | haute : lu dans le script et employé en 05 |

Téléchargements attendus : 3 clés de ftp-master, `InRelease`, `Packages.xz` (environ 10 Mo, ordre de grandeur non mesuré), 4 fichiers `repomd` de vault ; aucun `primary` si RL5 tient.

Résultat : [carte d'O2](o2-carte.md), section « Résultat du relevé préalable ».

## `o2.sh`, `o2-interne.sh` et `o2-banc.sh` (racines (a), décision du 19/11/2026)

Écrites le 19/11/2026 à partir de 16:02:15 UTC (`date -u`), **avant tout lancement** de ces trois scripts. `prealables` et le banc sont lancés à sec, juste après le commit qui porte ces prédictions. **`construire`, `cle` et `essai` ne sont PAS lancés** : ils attendent un accord nommé du propriétaire.

### `prealables` (lecture locale)

| # | Prédiction | Confiance |
|---|---|---|
| PA1 | Les deux amorces : manifeste, configuration et couche égaux à leur sha256 | haute (RL1, RL3) |
| PA2 | `RPM-GPG-KEY-Rocky-9` de l'amorce égale, en sha256, au fichier du relevé dont l'empreinte a été vérifiée | moyenne-haute : même fichier publié par Rocky, jamais comparé |
| PA3 | Place libre sous `~/.cache` supérieure à 3 000 Mo | haute (104 813 Mo à 15:58 UTC) |
| PA4 | Espace de noms : tmpfs monté (`tmpfs`), interfaces `[lo]` seulement | haute (RL6) |
| PA5 | `~/.cache/supply-chain-poc/09/o2` et `…/09/secrets` absents | haute |
| PA6 | `secrets-depot.sh` lit `08/secrets` et `10/secrets` seulement ; K3 tenue pour le journal | haute |

### Banc `o2-banc.sh` (gpg 2.4.8 de l'hôte, clé jetable, sans réseau)

| # | Prédiction | Confiance |
|---|---|---|
| BC5a | Garde réseau lancée sur l'hôte, avec réseau : refus (`KO … (K1)`, code 1) | haute |
| BC5b | Même garde dans l'espace de noms sans réseau : `OK`, code 0 | haute |
| BC1 | Création : code 0 ; RSA (algo 1), 4096 bits, expiration au 19/11/2027, usages `scSC` comme au banc O0 ; trois fichiers en 600, dossier en 700 ; clé privée armurée | haute |
| BC2 | Seconde création dans le même dossier : refus (K4), code 1 ; fichiers inchangés | haute |
| BC3 | Homedir sur disque : refus (K2), code 1 ; aucun fichier écrit | haute |
| BC4 | Import, signature SHA-512, vérification par gpgv : `OK` avec l'empreinte ; « sqv absent » | haute |
| BC6 | Clé jetable créée, importée dans un homedir neuf et utilisée pour signer | haute |
| BC8 | Signature du PoC vérifiée avec la clé jetable : ligne `KO   gpgv`, code 0 (la fonction rapporte sans échouer) | haute |
| BC7 | K3 : aucun « BEGIN PGP » et aucune ligne de la clé privée jetable dans le journal | haute |

Durée : moins d'une minute. Ne mesure ni gpg 2.4.7 ni 2.3.3.

### `construire` (NON LANCÉE : réseau et installation de paquets dans des racines neuves)

| # | Prédiction | Confiance |
|---|---|---|
| CR1 | Gardes : dossier des secrets absent (K1), dossier de travail absent | haute |
| CR2 | Rocky : `dnf-3 --installroot` depuis vault 9.8, code 0 ; `gnupg2-2.3.3-5.el9_7`, `rpm-sign-4.16.1.3-40.el9`, `createrepo_c-0.20.1-4.el9` installés ; tous les paquets signés par la clé `702d426d350d275d` (fin de l'empreinte Rocky 9) | moyenne : mécanisme mesuré en 05 hors ligne, jamais avec le réseau ni `repo_gpgcheck` |
| CR3 | Nombre et taille des rpm téléchargés | **relevé, non prédit** ; chacun journalisé et ajouté à la liste |
| CR4 | Debian : `apt-get update` dans l'amorce, code 0 ; `InRelease` lu par apt égal à `0584fba3…` ; mmdebstrap 1.5.7-1+deb13u1 installé | moyenne-haute : chemin de la 06, mais sur l'hôte, avec le DNS de l'hôte |
| CR5 | `mmdebstrap --mode=root` dans l'espace de noms utilisateur : code 0 | **faible** : jamais mesuré sur l'hôte ; montages de `/proc` et `/sys` dans la cible, et `sysfs` exige d'ordinaire son propre espace de noms réseau, que `construire` n'a pas |
| CR6 | Si CR5 tient : les sept versions épinglées installées (gnupg, gpg, gpgv, gpg-agent, gpgconf, apt-utils, sqv) | moyenne |
| CR7 | `gpg2 --version` donne 2.3.3 dans la racine Rocky, `gpg --version` 2.4.7 dans la racine Debian | haute si CR2 et CR5 tiennent |

### `cle` (NON LANCÉE : création de la clé du PoC)

| # | Prédiction | Confiance |
|---|---|---|
| CL1 | Clé créée par gpg 2.4.7 sous K1 et K2 : RSA 4096, v4, expiration au jour du lancement plus un an ; trois fichiers 600 dans `~/.cache/supply-chain-poc/09/secrets` (700) ; K3 tenue | moyenne-haute : mêmes commandes qu'au banc, autre version de gpg |

### `essai` (NON LANCÉE : sans réseau, avec la clé du PoC)

| # | Prédiction | Confiance |
|---|---|---|
| ES1 | E1 et E2 : signature dans la racine Debian, vérifiée par gpgv et par sqv | moyenne-haute : sqv accepte RSA 4096 et SHA-512 d'après `default-sequoia.config` (lu, non mesuré) |
| ES2 | E3 (K5) : la clé créée par 2.4.7 s'importe dans 2.3.3 et y signe | moyenne : jamais mesuré |
| ES3 | E4 et E5 : vérifications croisées acceptées (Rocky lit la signature Debian, Debian lit la signature Rocky) | moyenne : suit ES2 |
| ES4 | E6 à E8 (K5b) : clé jetable de 2.3.3 importée par 2.4.7, signature vérifiée par Rocky | moyenne-haute |
| ES5 | K3 tenue pour le journal | haute |

## Note datée du 19/11/2026, écrite à 16:03:45 UTC : `prealables` et banc passés, prédictions tenues

Lancés après le commit des prédictions (`9a086ae5`).

**`prealables`** ([journal](o2-prealables.log), 16:03:01 UTC, code 0) : **PA1 à PA6 tenues**.
- Amorces égales à leur sha256.
- Clé Rocky 9 de l'amorce égale à celle du relevé (`3a66e521…`).
- 104 811 Mo libres.
- Espace de noms avec tmpfs et `[lo]` seulement.
- `o2` et `secrets` absents ; K3 tenue.

**Banc** ([journal](o2-banc.log), 16:03:16 à 16:03:19 UTC, code 0) : **BC1 à BC8 tenues**.
- BC5a refuse sur l'hôte, car les interfaces de l'hôte sont visibles (leurs noms sont au journal) ; BC5b passe sans réseau.
- BC1 : RSA 4096, expiration au 19/11/2027, usages `scSC`, trois fichiers 600 dans un dossier 700, export armuré.
- BC2 : refus (K4), fichiers inchangés.
- BC3 : refus (K2) sur `ext2/ext3`, aucun fichier écrit.
- BC4 : signature SHA-512 vérifiée par gpgv, sqv absent.
- BC6 : clé jetable créée, importée et utilisée.
- BC8 : refus de gpgv avec une clé étrangère.
- BC7 : ni « BEGIN PGP » ni aucune ligne de la clé privée jetable dans le journal.

**Passage raté archivé** : [premier passage](o2-banc-premier-passage.log), arrêté après BC5a. `set -e` coupait la fonction au premier refus attendu. C'était un défaut du script, corrigé par `set +e` dans la fonction du banc. Le dossier du banc ne contenait encore aucun fichier ; il a été effacé avant la relance.

Le dossier du banc (clé jetable comprise) a été effacé à 16:03:25 UTC. Rien de ce banc ne mesure gpg 2.4.7 ni 2.3.3 : **K5 et K5b restent des prédictions** (ES2, ES4). `construire`, `cle` et `essai` ne sont pas lancées.

## Correction datée du 19/11/2026, écrite à 16:13:44 UTC : `o2.sh` restructuré après relecture du conseiller ; nouvelles prédictions

**Écart corrigé.** La version de `o2.sh` commitée en `9a086ae5` ne faisait pas ce que décrivait l'option (a) de la carte, approuvée par le propriétaire :
- côté Rocky, elle installait en ligne en une seule passe, sans contrôle des rpm contre le `primary` vérifié et sans installation hors ligne ;
- elle n'archivait que la racine Debian ;
- `construire` était tout ou rien : un échec de mmdebstrap (CR5, confiance faible) aurait bloqué la relance et jeté la racine Rocky.

Rien de cette version n'avait été lancé, hormis `prealables`. **Les prédictions CR1 à CR7 sont remplacées** par celles qui suivent ; CL1 et ES1 à ES5 restent valables.

**Nouvelle structure** : une étape à la fois, chacune refuse un dossier cible déjà présent. Les étapes avec réseau refusent si le dossier des secrets existe (K1). Le code de sortie est non nul dès qu'une ligne `KO` est journalisée. Si K3 échoue, le journal est vidé. Le sha256 des deux scripts est écrit en tête de chaque journal.

### `banc_chroot` (À SEC : sans réseau, sans installation, lancé après le commit de ces prédictions)

Interprétation de « sans rien installer » : l'amorce Rocky du cache local est extraite et son gpg déjà présent est exécuté sous `chroot`, comme en 05 (`m1b-amorce-lecture.sh`). Rien n'est ajouté à la racine.

| # | Prédiction | Confiance |
|---|---|---|
| BK0 | Amorce extraite ; `gpg --version` donne 2.3.3 ; `rpm -q gnupg2` donne `gnupg2-2.3.3-5.el9_7.x86_64` (mesure de la session principale) | haute |
| BK1 | Création d'une clé jetable par gpg 2.3.3 dans la même mécanique que `cle` (liens, tmpfs sous chroot, K1, K2) : code 0, RSA 4096, trois fichiers 600, export armuré | moyenne-haute : mêmes commandes qu'au banc O2, sous 2.3.3 et sous chroot pour la première fois |
| BK2 | Seconde création : refus (K4) | haute |
| BK3 | Programme d'essai (racine Rocky pour D et pour R) : E1, E3, E6, E7 signent ; E2, E4, E5, E8 vérifient par gpgv (sqv absent de l'amorce Rocky) | moyenne-haute |
| BK4 | E9 à E11 : clé jetable créée par le gpg 2.4.8 de l'hôte, importée dans 2.3.3 et utilisée pour signer, signature vérifiée par gpgv 2.3.3. C'est un indice pour K5 (création par 2.4.x, import par 2.3.3), pas sa mesure, puisque la version est 2.4.8 et non 2.4.7 | moyenne |
| BK5 | K3 tenue ; seuls les refus attendus de BK2 sont des lignes `KO` ; code 0 | moyenne-haute |

### Étapes avec accord, NON LANCÉES

| # | Prédiction | Confiance |
|---|---|---|
| RT1 | `rocky_telecharger` : `dnf-3 --installroot --downloadonly --downloaddir` du dnf 4.14 de l'amorce, depuis vault 9.8 (`repo_gpgcheck=1`) : code 0 ; les trois paquets épinglés téléchargés ; **tous les rpm égaux en sha256 au `primary` vérifié** | moyenne : `--downloaddir` avec `--downloadonly` est une option du cœur de dnf 4 (documentation, non relue au tag) ; jamais lancé dans ce PoC |
| RT2 | Nombre et taille des rpm | relevé, non prédit ; chacun journalisé |
| RI1 | `rocky_installer` : clé Rocky importée dans la racine vide, installation hors ligne avec `localpkg_gpgcheck` : code 0 ; paquets épinglés installés ; toutes les signatures par la clé `702d426d350d275d` ; gpg 2.3.3 dans la racine ; archive écrite | moyenne : mécanisme mesuré en 05 (`m1b-repro`), mais avec `localpkg_gpgcheck` pour la première fois |
| DA1 | `debian_amorce` : `apt-get update` puis mmdebstrap 1.5.7-1+deb13u1 installé, code 0 ; `InRelease` égal à `0584fba3…` ; **tous les `.deb` égaux au `Packages.xz` vérifié** | moyenne-haute : chemin de la 06, mais sur l'hôte |
| DR1 | `debian_racine` : `mmdebstrap --mode=root` dans l'espace de noms utilisateur : code 0 | **faible** (voir les replis de la carte) |
| DR2 | Si DR1 tient : `.deb` égaux au `Packages.xz` vérifié ; sept versions épinglées installées ; gpg 2.4.7 dans la racine | moyenne |

## Note datée du 19/11/2026, écrite à 16:15:24 UTC : `banc_chroot` passé, BK0 à BK5 tenues

Lancé après le commit des prédictions (`5f9076d2`). [Journal](o2-banc_chroot.log) : 16:14:50 à 16:14:55 UTC, code 0.

- **BK0 tenue** : amorce extraite ; gpg 2.3.3 ; `gnupg2-2.3.3-5.el9_7.x86_64`.
- **BK1 tenue** : gpg 2.3.3 crée la clé jetable dans la mécanique de `cle` (liens, tmpfs sous chroot, K1, K2) : RSA 4096, usages `scSC`, trois fichiers 600, export armuré.
- **BK2 tenue** : refus (K4), seule ligne `KO` du journal.
- **BK3 tenue** : le programme d'essai signe (E1, E3, E6, E7) et vérifie par gpgv (E2, E4, E5, E8) ; sqv absent de l'amorce Rocky.
- **BK4 tenue** : une clé jetable créée par le gpg **2.4.8** de l'hôte est importée par gpg **2.3.3**, qui signe ; gpgv 2.3.3 vérifie. Ce n'est qu'un indice pour K5, qui porte sur 2.4.7.
- **BK5 tenue** : K3 tenue ; code 0.

**Défaut du journal, corrigé après le passage** : l'en-tête n'a pas écrit le sha256 d'`o2.sh` (« No such file », ligne 346), parce que `$0` était relatif après le `cd`. Le calcul passe désormais par `$here/o2.sh`. Seule cette ligne d'en-tête change par rapport au script de `5f9076d2` qui a tourné. Le sha256 d'`o2-interne.sh` est au journal (`7c91e50f…`).

Dossier du banc effacé dans l'espace de noms, par un chemin littéral, à 16:15:03 UTC. **Restent non mesurés** : gpg 2.4.7 (K5 et K5b au sens strict), le téléchargement et l'installation des racines, mmdebstrap sur l'hôte (DR1).

**Signalé** : deux journaux commités plus tôt, `o2-banc.log` et `o2-banc-premier-passage.log`, nomment les interfaces réseau de l'hôte (BC5a). La garde ne fait désormais que les compter.

## Note datée du 19/11/2026, écrite à 16:18:00 UTC : `rocky_telecharger` passée, RT1 tenue, RT2 relevée

Lancée sur l'accord du propriétaire (« Oui, lance-la », en réponse à « Je lance rocky_telecharger (réseau vers vault 9.8, téléchargement seul) ? »), sur le commit `78f0d183`. [Journal](o2-rocky_telecharger.log) : 16:16:32 à 16:17:04 UTC, code 0 ; `o2.sh` `8205c78d…`, `o2-interne.sh` `7c91e50f…`.

- **RT1 tenue** : `dnf-3 --installroot --downloadonly --downloaddir` code 0 ; les trois paquets épinglés téléchargés ; **101 rpm sur 101 égaux en sha256 au `primary` vérifié**.
- **RT2 (relevé)** : **101 rpm, 38 746 077 octets**, chacun listé (nom, origine, taille, sha256) dans le journal et dans [la liste des téléchargements](releve-amont-telechargements.tsv). Ils sont rangés hors du dépôt, dans `~/.cache/supply-chain-poc/09/o2/rocky/o2/rpm`. Rien n'est installé.
- **Constat non prédit** : le journal de dnf, hors du dépôt, montre deux fois « Importing GPG key 0x350D275D » depuis `/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9`, puis « Key imported successfully ». dnf a donc déjà écrit la clé Rocky dans la base rpm de la racine (`racine/var/lib/rpm`). Il a aussi laissé dans la racine ses journaux (`var/log/dnf*`) et un reste de cache (`racine/o2/cache/expired_repos.json`, car `cachedir` est relatif à l'installroot).

**Adaptation de `rocky_installer` avant son lancement** (`o2.sh`, deux lignes) :
- l'import de la clé est sauté si `gpg-pubkey-350d275d` est déjà dans la base rpm de la racine ;
- `./o2` est exclu de l'archive.

**RI1 reste la prédiction** de cette étape. Elle s'y ajoute que le journal dira « clé Rocky 350d275d déjà dans la base rpm de la racine » (confiance haute : constat ci-dessus).

## Note datée du 19/11/2026, écrite à 16:22:39 UTC : `rocky_installer` passée, RI1 tenue

Lancée sur l'accord du propriétaire (« Oui, lance-la », en réponse à « Je lance rocky_installer (installation hors ligne des 101 rpm contrôlés) ? »), sur le commit `e5650282`. [Journal](o2-rocky_installer.log) : 16:21:44 à 16:22:01 UTC, code 0 ; `o2.sh` `fdae5389…`, `o2-interne.sh` `7c91e50f…`.

- **RI1 tenue** :
  - installation hors ligne (`dans_hors`), code 0 ;
  - racine de **102 paquets** : les 101 rpm contrôlés, plus `gpg-pubkey`, seule ligne « (none ») ; liste `8f2c435f…` ;
  - `gnupg2-2.3.3-5.el9_7`, `rpm-sign-4.16.1.3-40.el9` et `createrepo_c-0.20.1-4.el9` installés ;
  - **101 paquets sur 101 signés par la clé `702d426d350d275d`** ;
  - gpg 2.3.3 dans la racine ;
  - archive `rocky98-racine.tar` de 101 693 440 octets, sha256 `33dc2606…`, `./o2` exclu. Elle n'est pas reproductible, et ce n'était pas exigé.
- **Ajout à RI1 en partie tenu** : le message « clé Rocky 350d275d déjà dans la base rpm de la racine » est bien écrit, mais à la ligne 1 du journal de dnf (`~/.cache/supply-chain-poc/09/o2/rocky-installer-dnf.log`, hors du dépôt). Il n'est pas dans le journal de l'étape, contrairement à ce qu'annonçait la prédiction.
- **Limite** : le journal ne montre pas explicitement le contrôle des signatures à l'installation (`localpkg_gpgcheck=True`). Les 101 lignes « Verifying » de dnf sont la vérification d'après installation. Ce qui est établi : les 101 rpm sont égaux au `primary` vérifié (RT1), et chacun porte la signature de la clé Rocky (`RSAHEADER`, ci-dessus).
- **Rien n'est fait côté Debian. Aucune clé du PoC n'existe.**

## Note datée du 19/11/2026, écrite à 16:25:27 UTC : `debian_amorce` passée en partie, DA1 en partie non tenue ; correctif, relance préparée

Lancée sur l'accord du propriétaire (« Oui, lance-la », en réponse à « Je lance debian_amorce (réseau vers l'instantané, mmdebstrap dans l'amorce) ? »), sur le commit `02bbf040`. [Journal archivé](o2-debian_amorce-premier-passage.log) : 16:24:03 à 16:24:12 UTC, **code 1** (une ligne KO).

**Tenu** :
- apt dans l'amorce, code 0 ; mmdebstrap 1.5.7-1+deb13u1 installé ;
- `InRelease` lu par apt égal à `0584fba3…`, celui vérifié par le relevé.

**Non tenu** : « tous les `.deb` égaux au `Packages.xz` vérifié ». **Aucun `.deb` n'a été retrouvé** (« 0 sur 0 »). Le journal d'apt, hors du dépôt (gardé sous `~/.cache/supply-chain-poc/09/o2/debian-amorce-apt-premier-passage.log`), montre 20 paquets reçus (« Need to get 14.3 MB of archives »). Ils ont été installés, vérifiés par apt seulement.

**Cause mesurée** : l'amorce `debian:trixie-20261104-slim` contient `/etc/apt/apt.conf.d/docker-clean`. Ce fichier efface `/var/cache/apt/archives/*.deb` après chaque appel à dpkg (`DPkg::Post-Invoke`), et `APT::Keep-Downloaded-Packages=true` ne l'en empêche pas. Les lignes « Permission denied » viennent du sous-dossier `partial`, qui appartient au sous-UID de `_apt` ; elles sont sans effet sur le résultat. Les 20 téléchargements ne sont pas dans la liste des téléchargements : `signaler` n'a rien trouvé à lister.

**Correctif** (`o2.sh`) :
- `docker-clean` est mis de côté dans `o2/` avant apt ;
- `find` limité à une profondeur 1 pour les `.deb`, l'`InRelease` et `signaler`.

Le dossier de l'amorce a été effacé à 16:24:57 UTC, dans l'espace de noms et par un chemin littéral, pour que la relance reparte à neuf (garde « dossier absent »).

**Prédiction de la relance (DA2)**, en plus de DA1 :
- le journal dira « docker-clean mis de côté » ;
- environ 20 `.deb` seront retrouvés, signalés et égaux au `Packages.xz` vérifié ;
- code 0.

Confiance moyenne-haute : la cause est lue dans le fichier ; le nombre de `.deb` est celui du premier passage.

**Effet possible sur `debian_racine`** : la racine minbase de mmdebstrap ne vient pas de l'image Docker. Ce que mmdebstrap lit de la configuration d'apt de l'amorce n'est pas lu. Si des `.deb` y manquaient aussi, le contrôle le dirait (« 0 sur 0 », KO).

## Note datée du 19/11/2026, écrite à 16:26:26 UTC : relance de `debian_amorce` passée, DA1 et DA2 tenues

Relance sur l'accord du propriétaire (« Oui, relance-la », en réponse à « Je relance debian_amorce corrigée (réseau, mmdebstrap réinstallé) ? »), sur le commit `ea2bce94`. [Journal](o2-debian_amorce.log) : 16:25:53 à 16:26:00 UTC, code 0 ; `o2.sh` `9c817f68…`, `o2-interne.sh` `7c91e50f…`.

- **DA2 tenue** : « docker-clean mis de côté dans o2/ » ; **20 `.deb` sur 20 égaux au `Packages.xz` vérifié** ; code 0. Aucune ligne « Permission denied ».
- **DA1 tenue** : apt code 0 ; `InRelease` égal à `0584fba3…` ; mmdebstrap 1.5.7 installé.
- **Téléchargements** : 20 `.deb`, **14 298 692 octets**, listés avec leur sha256 dans le journal et dans [la liste des téléchargements](releve-amont-telechargements.tsv). Le premier passage avait reçu les mêmes 20 paquets (« 14.3 MB ») sans les garder ; ils ne sont pas listés.

## Note datée du 19/11/2026, écrite à 16:28:51 UTC : `debian_racine` passée, DR1 et DR2 tenues, contrôle des `.deb` partiel

Lancée sur l'accord du propriétaire (« Oui, lance-la », en réponse à « Je lance debian_racine (mmdebstrap sur l'hôte, réseau ; prédiction faible) ? »), sur le commit `e2036b92`. [Journal](o2-debian_racine.log) : 16:26:50 à 16:27:39 UTC, code 0 ; `o2.sh` `9c817f68…`.

- **DR1 tenue, contre une confiance faible** : `mmdebstrap --mode=root` réussit dans l'espace de noms utilisateur de l'hôte (« success in 47.1577 seconds »). Les replis de la carte sont sans objet.
- **DR2 tenue** :
  - archive `debian13.tar` de 205 667 840 octets, sha256 `45f376e6…` ;
  - les sept versions épinglées sont installées (gnupg 2.4.7-21+deb13u1 ; gpg, gpgv, gpg-agent, gpgconf 2.4.7-21+deb13u1+b5 ; apt-utils 3.0.3 ; sqv 1.3.0-3+b2) ;
  - gpg 2.4.7 dans la racine ;
  - **47 `.deb` sur 47 égaux au `Packages.xz` vérifié**.
- **Écart de couverture, non prédit** : la racine compte **106 paquets**, mais seuls 47 `.deb` étaient encore dans le cache au moment du crochet. Les `.deb` des **59 paquets essentiels** (`libc6`, `bash`, `dpkg`, `coreutils`, etc.) avaient déjà été retirés par mmdebstrap après leur installation. Ces 59 paquets n'ont été vérifiés que par apt (sommes de `Packages`, sous l'`InRelease` signé).
- **Contrôle complémentaire** ([`o2-controle-versions.sh`](../o2-controle-versions.sh), [journal](o2-controle-versions.log), 16:28:16 UTC, local, sans relance) : **106 versions installées sur 106 figurent dans le `Packages.xz` vérifié**. Il ne prouve pas le contenu des fichiers des 59 paquets essentiels.
- **Pour un contrôle complet** : garder les `.deb` essentiels, par une option de mmdebstrap (une option `--skip=essential/unlink` existerait, **non lue**), ou par un crochet `--essential-hook`. Cela demande une relance de `debian_racine`, avec son accord. La racine actuelle reste en place.
- **Téléchargements** : 47 `.deb` listés avec leur sha256 (taille non relevée par le crochet). Les 59 paquets essentiels téléchargés par mmdebstrap n'ont laissé aucune trace de fichier, et ne sont pas listés.

## Note datée du 19/11/2026, écrite à 16:32:42 UTC : décision « Refaire en entier » ; option de mmdebstrap lue ; relance NON préparée ni lancée

Décision du propriétaire : « Refaire en entier », en réponse à « Accepter ce contrôle partiel des paquets essentiels Debian, ou refaire debian_racine en les gardant ? ».

- **Option lue** ([`o2-releve-4.sh`](../o2-releve-4.sh), [journal](o2-releve-4.log), 16:32:16 UTC, local, dans le script de mmdebstrap installé dans l'amorce) : `--skip=essential/unlink` existe en 1.5.7. Aux lignes 3990 et 3991 du script, il est testé et annonce « skipping essential/unlink as requested ». Sans lui, les `.deb` sont retirés à la ligne 4002 (`unlink "$options->{root}/$deb"`). `--essential-hook` existe aussi (ligne 5743).
- Premier passage du relevé archivé ([journal](o2-releve-4-premier-passage.log)) : la page de manuel est absente de l'amorce `slim`.
- **Suite prévue, NON faite** :
  1. ajouter `--skip=essential/unlink` à `debian_racine` ;
  2. écrire la prédiction DR3 : 106 `.deb` environ, tous égaux au `Packages.xz` vérifié ;
  3. commiter ;
  4. effacer l'archive `debian13.tar` et la racine `o2/racine-debian13` dans l'espace de noms, par des chemins littéraux ;
  5. relancer `debian_racine` (accord donné par « Refaire en entier »).

## Prédictions de la relance de `debian_racine` (écrites à 16:34:29 UTC, avant tout lancement)

`o2.sh` modifié sur une ligne : `--skip=essential/unlink` est ajouté à l'appel de mmdebstrap. Le reste est inchangé, et la racine actuelle sera effacée avant la relance.

| # | Prédiction | Confiance |
|---|---|---|
| DR3 | Le journal de mmdebstrap dit « skipping essential/unlink as requested » ; **le crochet trouve un `.deb` par paquet installé (106 environ), tous égaux au `Packages.xz` vérifié** ; plus aucun paquet installé sans `.deb` contrôlé (`o2-controle-versions.sh` relancé : 0) | moyenne-haute : option lue dans le script ; le nombre exact dépend de la résolution, qui ne devrait pas changer (même instantané, mêmes paquets demandés) |
| DR4 | Les sept versions épinglées sont de nouveau installées, avec gpg 2.4.7 et un code 0 ; l'archive diffère de `45f376e6…`, sans que ce soit exigé | haute pour les versions ; l'empreinte de l'archive n'est pas prédite |

## Note datée du 19/11/2026, écrite à 16:36:26 UTC : relance de `debian_racine` passée, DR3 et DR4 tenues

Relance sur la décision « Refaire en entier », sur le commit `39ec389c`.
- **Effacé avant la relance** (à 16:35:01 UTC, dans l'espace de noms, par chemins littéraux) : l'ancienne archive `debian13.tar` et l'ancienne racine `o2/racine-debian13`.
- **Archivé** : le journal du premier passage ([journal](o2-debian_racine-premier-passage.log)), celui du contrôle des versions ([journal](o2-controle-versions-premier-passage.log)), et le journal de mmdebstrap de ce passage, hors du dépôt (`debian-mmdebstrap-premier-passage.log`).

[Journal de la relance](o2-debian_racine.log) : 16:35:05 à 16:35:49 UTC, code 0 ; `o2.sh` `b4a25981…`. [Contrôle des versions](o2-controle-versions.log) : 16:35:49 UTC, code 0.

- **DR3 tenue** :
  - « skipping essential/unlink » apparaît une fois dans le journal de mmdebstrap ;
  - **106 `.deb` sur 106 sont égaux au `Packages.xz` vérifié** ;
  - 106 paquets installés, dont 106 avec un `.deb` contrôlé par sha256, et 0 sans ;
  - 106 versions sur 106 figurent dans l'index signé.
- **DR4 tenue** :
  - les sept versions épinglées sont installées, gpg 2.4.7, code 0 ;
  - l'archive fait 205 667 840 octets (même taille qu'au premier passage), sha256 `015611d6…`, différent de `45f376e6…` comme prévu.
- **Téléchargements** : 106 `.deb` listés avec leur sha256 dans le journal et dans [la liste des téléchargements](releve-amont-telechargements.tsv). Le crochet ne relève pas les tailles.

**État d'O2** :
- les deux racines de signature sont prêtes, avec tous leurs paquets contrôlés ;
- Rocky : 101 rpm contre le `primary` vérifié ;
- Debian : 106 `.deb` contre le `Packages.xz` vérifié ;
- aucune clé du PoC n'existe ;
- restent `cle` et `essai`, chacune avec son accord.

## Prédictions de la répétition de `cle` et `essai` (écrites à 17:12:54 UTC, avant tout lancement)

Cette répétition est demandée par la relecture du conseiller avant l'accord de `cle`. Plusieurs choses ne sont pas mesurées :
- `creer` n'a jamais tourné sous gpg 2.4.7, alors que `cle` crée la clé dans la racine Debian ;
- K5 et K5b ne sont pas mesurées dans les racines construites (`banc_chroot` a tourné dans l'amorce Rocky) ;
- on ne sait pas si `garde-cle-privee.sh` couvre `revocation.asc`.

La nouvelle étape `o2.sh repetition` est à sec : pas de réseau, pas d'installation. Elle utilise une clé jetable (RSA 4096 de `creer`, identité fictive sans adresse, 2 jours). Ses sorties vont dans `~/.cache/supply-chain-poc/09/o2/repetition`, effacé après archivage. `09/secrets` n'est ni créé ni lu.

| N° | Prédiction | Confiance |
|---|---|---|
| RP0 | Les deux racines sont présentes ; journal d'en-tête avec les sha256 d'`o2.sh` et d'`o2-interne.sh` | haute |
| RP1 | `creer` sous gpg 2.4.7, dans la racine Debian : code 0, gardes K1 et K2 tenues. Trois fichiers en 600, dossier en 700 ; clé RSA 4096 ; usages « s » sur la clé primaire | moyenne-haute : même script que BK1 (2.3.3), 2.4.7 jamais mesuré |
| RP2 | Seconde création refusée (K4), code 1 | haute |
| RP3a | `cle-openpgp.asc` : un en-tête privé vu par la garde, aucun en-tête public | haute |
| RP3b | `cle-publique.asc` : un en-tête public, aucun en-tête privé | haute |
| RP3c | `revocation.asc` : **aucun** en-tête privé, donc la garde ne le voit pas ; un en-tête public préfixé par deux-points, gpg l'écrivant ainsi pour éviter un usage accidentel | moyenne : forme de gpg 2.1 et suivants, non relue dans ce fichier |
| RP3d | Les lignes de `revocation.asc` qui deviendraient des motifs de `secrets-depot.sh` comprennent des phrases d'explication et la ligne d'en-tête préfixée. Pour les exports, la ligne la plus courte fait moins de 16 caractères (fin du bloc base64 ou ligne de somme) | moyenne |
| RP4 | Programme d'essai E1 à E8, tous à code 0 : la signature Debian est vérifiée par gpgv et sqv (ES1) ; K5 (2.4.7 vers 2.3.3) tenue (ES2) ; vérifications croisées acceptées (ES3) ; K5b tenue (ES4) | moyenne : ES2 jamais mesurée |
| RP5 | K3 : aucun « BEGIN PGP » dans le journal ; seules les lignes KO de refus attendu sont présentes ; code final 0 | haute |

Si RP3c est tenue, une note datée ajoutera `revocation.asc` aux limites de la garde. Couvrir ce fichier par la garde serait un vrai choix, à poser à part. Si RP1 ou RP4 échoue, aucune clé du PoC n'est créée et `cle` reste en attente.

## Note datée du 19/11/2026, écrite à 17:13:47 UTC : répétition passée, RP0 et RP2 à RP5 tenues, RP1 tenue sauf un détail

Étape `repetition` passée de 17:12:57 à 17:13:02 UTC, code 0 ([journal](o2-repetition.log)), sur le commit `aece06a9` des prédictions (`o2.sh` `1a6f9cd0…`, `o2-interne.sh` `7c91e50f…`).
- **RP1, tenue sauf un détail** : `creer` fonctionne sous gpg 2.4.7 dans la racine Debian. Code 0, K1 et K2 tenues, RSA 4096, trois fichiers en 600 dans un dossier en 700.
  - Le détail non tenu : les usages valent `scSC`, pas « s » seul. gpg ajoute la certification à la clé primaire.
  - Le même `scSC` figurait déjà dans le [journal de `banc_chroot`](o2-banc_chroot.log) (l.10) ; la prédiction ne l'avait pas relu.
  - CL1 ne prédit pas les usages, et reste valable.
- **RP2** : la seconde création est refusée (K4), code 1.
- **RP3a à RP3c** :
  - la garde voit l'en-tête privé de `cle-openpgp.asc` (1) ;
  - `cle-publique.asc` porte un en-tête public seulement ;
  - `revocation.asc` ne porte **aucun** en-tête privé, mais un en-tête public préfixé par deux-points (1). **La garde locale ne couvre donc pas le certificat de révocation.**
- **RP3d, en partie** : la ligne la plus courte qui deviendrait un motif de `secrets-depot.sh` fait 5 caractères (clé privée, 53 lignes-motifs), 4 (clé publique, 27) et 5 (révocation, 30). La nature de ces lignes n'a pas été relue. La présence de phrases d'explication dans `revocation.asc` n'est pas mesurée, car le contenu n'est pas lu.
- **RP4** : E1 à E8 donnent tous le code 0.
  - ES1 : signature de la racine Debian vérifiée par gpgv et par sqv.
  - ES2 (K5) : la clé créée par 2.4.7 s'importe dans 2.3.3 et y signe.
  - ES3 : les vérifications croisées sont acceptées.
  - ES4 (K5b) : une clé de 2.3.3 s'importe dans 2.4.7 et y signe, et Rocky vérifie la signature.
  - Ces mesures portent sur une clé jetable de même forme (RSA 4096, SHA-512), pas sur la clé du PoC.
- **RP5** : K3 tenue, aucune ligne KO en dehors du refus attendu.

**Conséquences** :
- La garde a une limite de plus : `revocation.asc` n'est pas vu.
- Le §4 quater d'`A-REPORTER.md` reçoit une seconde correction datée sur la longueur des motifs.
- Le dossier `~/.cache/supply-chain-poc/09/o2/repetition` sera effacé après le commit de cette note.

## Prédictions de `cle` (écrites à 17:18:33 UTC, avant tout lancement, après la décision « Sans phrase de passe »)

CL1 reste valable. Elle porte sur une clé créée par gpg 2.4.7 sous K1 et K2 : RSA 4096, v4, expiration au jour du lancement plus un an, trois fichiers 600 dans `09/secrets` (700), K3 tenue. Sa confiance monte à haute : la répétition (RP1) a fait passer les mêmes commandes sous la même version. Trois prédictions s'ajoutent :

| N° | Prédiction | Confiance |
|---|---|---|
| CL2 | Usages de la clé primaire : `scSC`, comme en RP1. Identité : nom et commentaire par défaut d'`o2-interne.sh`, sans adresse | haute |
| CL3 | Chaque fichier est plus grand que son équivalent de la répétition, de moins de 200 octets : clé privée au-dessus de 3457, clé publique au-dessus de 1709, révocation au-dessus de 1848 octets. Cause attendue : l'identité par défaut est plus longue que celle de la clé jetable | moyenne |
| CL4 | Code 0, aucune ligne KO. Après `cle`, `garde-cle-privee.sh` passe sur l'arbre réel, car la clé est hors du dépôt | haute |

## Note datée du 19/11/2026, écrite à 17:19:02 UTC : `cle` passée, CL1, CL3 et CL4 tenues, CL2 en partie

Étape `cle` passée de 17:18:37 à 17:18:38 UTC, code 0 ([journal](o2-cle.log)), avec les mêmes scripts que la répétition (`o2.sh` `1a6f9cd0…`, `o2-interne.sh` `7c91e50f…`).

- **CL1 tenue** : clé créée par gpg 2.4.7, avec K1 et K2 tenues. RSA 4096, créée le 2026-11-19, expire le 2027-11-19. Les trois fichiers sont en 600 et le dossier des secrets en 700. K3 tenue.
- **CL2 en partie** : les usages valent `scSC`. L'identité n'est pas affichée par `decrire`, donc pas mesurée dans le journal.
- **CL3 tenue** : clé privée de 3498 octets (+41), clé publique de 1749 (+40), révocation de 1877 (+29).
- **CL4 tenue** : code 0, aucune ligne KO. `garde-cle-privee.sh` passe ensuite sur l'arbre réel (17:18:42 UTC, sortie non archivée en journal ; il repasse avant le commit de cette note).

**Empreinte de la clé du PoC** : `29BA1C48A39C099B7070DCD8C0658591BCF03A86`.

Désormais, les étapes avec réseau d'O2 refusent de tourner, puisque le dossier des secrets existe (K1). Aucune session ne lit ni ne liste ce dossier. Prochaine étape : `essai`, sans réseau, avec la clé du PoC (ES1 à ES5).

*Note datée du 19/11/2026, 17:19:02 UTC, avant le lancement d'`essai`* : ES1 à ES5 sont inchangées. Leur confiance devient haute : la répétition (RP4) a passé E1 à E8 avec une clé jetable de même forme. Ce qui est neuf avec `essai` : la clé du PoC elle-même, expirant dans un an.

## Note datée du 19/11/2026, 17:19:23 UTC : `essai` passée, ES1 à ES5 tenues ; O2 terminé

Étape `essai` passée de 17:19:11 à 17:19:12 UTC, code 0 ([journal](o2-essai.log)), avec la clé du PoC `29BA1C48…BCF03A86`. ES1 : la signature de la racine Debian est vérifiée par gpgv et sqv. ES2 (K5) : la clé importée dans 2.3.3 y signe. ES3 : les vérifications croisées sont acceptées (E4, E5). ES4 (K5b) : une clé jetable de 2.3.3 est importée par 2.4.7, et Rocky vérifie sa signature. ES5 : K3 tenue. **Le jalon O2 est terminé** : deux racines contrôlées, une clé du PoC, signature et vérification croisées sous les deux versions de gpg. Pas encore mesuré : rpmsign, createrepo_c, apt-ftparchive sur la vraie clé, et le vérificateur réel d'apt et de dnf (jalons suivants).
