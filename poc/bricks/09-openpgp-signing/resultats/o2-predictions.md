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
