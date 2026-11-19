# Brique 09, O2 : carte (préparée à sec, rien lancé hors du relevé)

## Résultat du relevé préalable (19/11/2026, 15:42:34 à 15:42:52 UTC, code 0)

Journal : [`o2-releve.log`](o2-releve.log) ; prédictions : [`o2-predictions.md`](o2-predictions.md) (commit `e1395ec8`, avant lancement). 9 fichiers téléchargés, 9 854 940 octets, dont `Packages.xz` de l'instantané (9 678 380 octets), listés dans [la liste des téléchargements](releve-amont-telechargements.tsv) ; aucun `primary` retéléchargé.

- **RL1 tenue** : amorce `rockylinux:9.8` (`ed654c69…`, créée le 25/05/2026), sha256 égaux ; `rpm`, `rpmkeys`, `dnf-3`, `RPM-GPG-KEY-Rocky-9` présents ; `rpmsign`, `createrepo_c` absents ; aucun greffon dnf.
- **RL2 (relevé)** : l'amorce Rocky porte déjà `gpg`, `gpg2`, `gpgv`, `gpg-agent`, `gpgconf`. Leur version n'est pas lue (base rpm non ouverte).
- **RL3 en partie non tenue** : amorce `debian:trixie-20261104-slim` (`7378260c…`) : `apt-get`, `dpkg`, `debian-archive-keyring.gpg` présents ; `gpg`, `gpg-agent`, `apt-ftparchive` absents comme prédit ; mais **`gpgv` absent et `sqv` présent**. La méthode réellement employée par apt reste non lue.
- **RL4 tenue** : `InRelease` de l'instantané `20261105T000000Z` signé par les 3 clés de la 06 (trixie 13.7, du 12/09/2026) ; `Packages.xz` contrôlé ; `gnupg` 2.4.7-21+deb13u1, `gpg`, `gpgv`, `gpg-agent`, `gpgconf` 2.4.7-21+deb13u1+b5, `apt-utils` 3.0.3, `sqv` 1.3.0-3+b2. Mêmes versions que D4 : aucun conflit.
- **RL5 tenue** : `repomd.xml` de `vault/rocky/9.8` vérifiés, égaux à ceux de `pub/9.8` du 19/11 ; `gnupg2` 2.3.3-5.el9_7, `rpm-sign` et `rpm-sign-libs` 4.16.1.3-40.el9, `createrepo_c` et `createrepo_c-libs` 0.20.1-4.el9, `python3-dnf-plugins-core` 4.3.0-26.el9 présents.
- **RL6 tenue** : `unshare --map-auto --map-root-user -n` fonctionne ; `secrets-depot.sh` ne lit que `08/secrets` et `10/secrets`, sans motif « BEGIN PGP ». podman 5.7.0 (`5.7.0+ds2-3build1`) : 0 ligne du changelog local ne cite l'avis GHSA-2cvf-wqm6-wr9g ni 5.8.8. Exposition non établie ; podman n'est pas sur le chemin proposé.

## Mécanisme proposé, quelle que soit la réponse à la question ci-dessous

Celui de la 05 (`m1b-amorce-lecture.sh`) : une racine dans un dossier de l'hôte, sous `unshare --map-auto --map-root-user`, avec `chroot`. Pas de podman.

Invariants de la clé (gardes du script et prédictions d'O2) :
- **K1** : la clé ne coexiste jamais avec le réseau. La construction des racines se fait sans clé. La signature se fait sous `unshare -n`.
- **K2** : la clé n'entre jamais dans une racine archivée. Le homedir de gpg est éphémère (tmpfs dans l'espace de noms), monté seulement pour la signature.
- **K3** : export **armuré** de la clé privée et du certificat de révocation par `-o` sous `umask 077`, jamais sur la sortie standard. Aucun **journal** ne contient « BEGIN PGP » (contrôle du script). L'export armuré permet à `secrets-depot.sh` d'en tirer des motifs ligne à ligne, si son dossier est ajouté à la liste (proposé dans `A-REPORTER.md`).
- **K4** : l'étape `cle` refuse d'écraser une clé existante.
- **K5** : la clé créée par le gpg 2.4.7 de Debian s'importe dans le gpg 2.3.3 de Rocky et y signe. Confiance moyenne : clé RSA v4, jamais mesuré. Raison du sens choisi : la clé publique part vers les consommateurs Debian (vérifiée par sqv) et rpm ; la version la plus récente crée, la plus ancienne doit seulement l'accepter. **K5b** : le sens inverse (2.3.3 crée, 2.4.7 importe) est mesuré aussi, sur une clé jetable, pour savoir si un repli est possible.

Clé proposée (à confirmer dans l'accord de lancement, pas une question à part) :
- RSA 4096, v4, primaire de signature, sans sous-clé ;
- identité fictive sans adresse, « PoC supply-chain : signature des paquets et des dépôts » ;
- expiration à 1 an ;
- **phrase de passe : compromis à nommer dans l'accord.** Sans phrase, le fichier 0600 suffit à signer ; une sauvegarde de l'hôte emporte la clé utilisable, risque cité par D2. Avec une phrase gardée hors de l'hôte et hors des sauvegardes, la sauvegarde seule ne suffit plus. Mais chaque signature demande alors la phrase (saisie à la main, ou fichier présent au moment de signer), et root sur l'hôte pendant une signature la lit quand même. Proposé pour le PoC : sans phrase, compromis écrit dans l'ADR 0003 avec l'écart de D2 ;
- chemins proposés : `~/.cache/supply-chain-poc/09/secrets/` (0700), avec la clé privée exportée et le certificat de révocation dans deux fichiers 0600. Empreinte dans `resultats/`. **Clé publique dans le dépôt : à décider dans l'accord** (la règle « ne jamais afficher un certificat » peut s'y appliquer) ; à défaut, elle reste à côté de la clé, hors du dépôt.

## Question au propriétaire : d'où viennent les racines de signature ?

D2 met la clé et la signature sur l'hôte, mais ne dit pas où l'outillage (gpg, `rpm-sign`, `createrepo_c`, `apt-ftparchive`) est construit. Deux décisions existantes pèsent :
- « C » en 05 : images d'outillage construites par la plateforme, sans réseau ;
- D4 (a) en 06 : l'amorce Debian ne sert qu'une fois.
Les deux amorces ne sont pas signées, et l'image Debian dépend de debuerreotype, qui devient « Risqué » le 09/12/2026 sans nouvelle release.

- **(a) Racines refaites sur l'hôte depuis les dépôts signés, l'amorce ne servant qu'une fois.**
  - Rocky : `dnf --installroot` sous `unshare --map-auto --map-root-user`, mécanisme déjà mesuré sur l'hôte par le banc `m1b-repro` de la 05 (hors ligne, sur des rpm locaux). Ici, les rpm seraient téléchargés depuis `vault/rocky/9.8`, contrôlés par le `primary` vérifié, puis installés **hors ligne** avec `gpgcheck=1`.
  - Debian : mmdebstrap installé dans l'amorce, puis racine tirée de l'instantané vérifié. **Non mesuré sur l'hôte** : la 06 l'a lancé en root dans un pod Kata. D'après le manuel de trixie, les modes `sudo` et `root` exigent `CAP_SYS_ADMIN` pour monter ([relevé](o2-releve-2.log)), à obtenir dans l'espace de noms ; confiance faible à moyenne.
  - Archive de chaque racine par sha256 ; versions épinglées contrôlées après installation.
  - Précédent : l'outillage de signature de J6 tourne déjà sur l'hôte (`tkn` v0.46.2 et `ec` v0.10.42 par mise, sha256 seulement, README de la 08).
  - Limites : ce n'est pas la plateforme qui construit, et le réseau sert au téléchargement. Si O2 passe après le 09/12/2026, relever debuerreotype d'abord (l'amorce Debian sert encore une fois).
- **(b) Racines produites par la plateforme, sans réseau, tirées de Zot par digest.** Même voie que « C » en 05, que le propriétaire a retenue le 18/11/2026 contre la recommandation (A) : fermeture, tâches signées, provenance de Chains. **Dépend de M1b**, non terminé (rejeu de M5b pas avant le 28/11). Il faut aussi un accès de l'hôte à Zot.
- **(c) Amorces gardées comme base, paquets ajoutés.** Le plus court. Mais les deux images ne sont pas signées, l'échéance du 09/12/2026 s'applique, et le choix va, par analogie, contre D4 (a) de la 06 et « C » de la 05, qui visaient les images de la zone build.

**Recommandation (relue par le conseiller) : (a), pour le PoC seulement.** Ce qui décide est une dépendance, pas un effort : (b) attend M1b. (b) est proposée comme **cible de production**, à écrire dans l'ADR 0003 à côté de l'écart de D2.

Après la réponse : script `o2.sh` (étapes `telecharger`, `construire`, `cle`, `essai`), prédictions K1 à K5b et des racines, banc à sec. `construire` et `cle` restent NON LANCÉES sans accord nommé (installation de paquets dans une racine, création de la clé).

## Note datée du 19/11/2026, écrite à 15:48:31 UTC : version de gpg dans l'amorce Rocky (RL2 complété par une mesure de la session principale)

Message de la session principale, reçu vers 15:48 UTC. Mesure vérifiée ici dans son commit `9b0f5e9f` (branche `claude/focused-fermi-ul5y20`, non fusionnée dans cette branche), journal `poc/bricks/05-rpm-mock/resultats/m1b-curl-amorce.log`, lu par `git show` :
- l. 5 : l'amorce `rockylinux:9.8` (couche `99c753a880cc…`) porte `gnupg2-2.3.3-5.el9_7.x86_64`, construit le 19/01/2026 ;
- l. 13 : la racine de `99790c13` (image de `prefetch-rpm`) porte le même paquet.

Recoupement avec ce relevé : le `primary` vérifié de BaseOS 9.8 (vault égal à pub) ne liste **qu'une entrée `gnupg2`, 2.3.3-5.el9_7** ([relevé](releve-amont.log), l. 367 ; le script en imprimait jusqu'à deux par nom). Le gpg de l'amorce est donc la seule révision de Rocky 9.8 : **aucun retard de révision**, à la différence de curl (4 révisions de retard d'après la session principale, non vérifié ici). Les errata de Rocky pour `gnupg2` et les avis de GnuPG touchant 2.3.3 ne sont pas lus.

Conséquence pour l'option (a) : côté Rocky, `gnupg2` n'est pas à installer ; seuls `rpm-sign`, `rpm-sign-libs`, `createrepo_c`, `createrepo_c-libs` et leurs dépendances le sont.

## Décision du propriétaire du 19/11/2026 : racines de signature (a), pour le PoC (consignée à 15:58:16 UTC)

Question posée dans le cadre de fin de tour : « Racines de signature d'O2 : refaites sur l'hôte depuis les dépôts signés, pour le PoC ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus : « Oui, option (a) ».

- **(a) retenue pour le PoC** : chaque amorce ne sert qu'une fois, pour produire une racine neuve depuis les dépôts signés (`vault/rocky/9.8`, instantané Debian `20261105T000000Z`). **(b)**, racines produites par la plateforme, devient la **cible de production**, à écrire dans l'ADR 0003 (proposé dans `A-REPORTER.md`). **(c)** est écartée.
- **Correction de la phrase précédente** (« `gnupg2` n'est pas à installer ») : elle valait pour un ajout de paquets dans l'amorce, c'est-à-dire l'option (c). Avec (a), la racine Rocky est neuve (`dnf --installroot`). `gnupg2` y est donc installé depuis vault, dans la même révision 2.3.3-5.el9_7 que celle de l'amorce.
- Suite : `o2.sh` et ses prédictions ; `construire` et `cle` attendent un accord nommé.

## Étapes d'O2, replis, échecs et effacement (ajouté le 19/11/2026 à 16:13:44 UTC, après relecture du conseiller)

`o2.sh` suit l'option (a) étape par étape. Chaque étape a son journal, refuse un dossier cible déjà présent et demande son accord :

| Étape | Réseau | Clé | Écrit |
|---|---|---|---|
| `prealables` | non | non | journal seulement (fait) |
| `banc_chroot` | non | jetable | `~/.cache/supply-chain-poc/09/o2-banc-chroot` (à sec, sans installation) |
| `rocky_telecharger` | oui | absente (K1) | `o2/rocky` (amorce extraite, rpm téléchargés et contrôlés contre le `primary` vérifié) |
| `rocky_installer` | non | absente | racine `o2/rocky/racine` (installation hors ligne, `localpkg_gpgcheck`) et `o2/rocky98-racine.tar` |
| `debian_amorce` | oui | absente (K1) | `o2/debian-amorce` (mmdebstrap installé ; `.deb` contrôlés contre le `Packages.xz` vérifié) |
| `debian_racine` | oui | absente (K1) | `o2/debian-amorce/o2/debian13.tar`, racine `o2/racine-debian13` |
| `cle` | non | créée | `~/.cache/supply-chain-poc/09/secrets` |
| `essai` | non | lue | journal seulement (tmpfs) |

Les contrôles relisent deux dossiers du relevé, qui sont donc gardés : `releve-20261119T144438Z` (`primary` de Rocky) et `o2-releve-20261119T154234Z` (`Packages.xz`).

**Replis de DR1** (`mmdebstrap --mode=root` dans l'espace de noms utilisateur, confiance faible), chacun avec sa prédiction et son accord, aucun lancé :
1. `--mode=unshare` lancé en root dans l'espace de noms. D'après le manuel de trixie, ce mode isole aussi les espaces de montage, de processus, uts et ipc ([relevé](o2-releve-3.log)). Ce qu'il fait exactement quand il est lancé en root n'est pas lu en entier (paragraphe tronqué à 1 800 caractères).
2. Espace de noms réseau propre à mmdebstrap, pour permettre le montage de `sysfs`, avec une sortie réseau à fournir. Ce n'est pas trivial sans privilège : à étudier.
3. Repli hors (a) : racine Debian produite dans un pod Kata, comme en 06. Ce serait une décision du propriétaire.

**Échecs** :
- un échec laisse son dossier cible, et l'étape refuse ensuite de repartir ;
- un échec de `cle` laisse `~/.cache/supply-chain-poc/09/secrets`, qui bloque à la fois `cle` et toutes les étapes avec réseau. L'effacement manuel est à décider : il détruit la clé partielle.

**Effacement** : les arbres extraits appartiennent à des sous-UID. Ils s'effacent dans l'espace de noms, par un chemin littéral, par exemple :

```bash
unshare --map-auto --map-root-user rm -r --one-file-system /home/gigi/.cache/supply-chain-poc/09/o2-banc-chroot
```
