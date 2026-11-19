# Brique 09, O4 : prédictions (dépôt apt signé, vérifié par apt de Debian 13)

Écrites le 19/11/2026 à 18:29:27 UTC, avant tout lancement de `repetition` ou de `signer`, après relecture du conseiller. Scripts : `o4.sh` `cc7e6665…`, `o4-interne.sh` `c50ff7c5…`. Le journal de `prealables` cite `b66c18e9…`, une version antérieure au jugement OK ou ÉCART de P5 ; `prealables` n'exécute pas `o4-interne.sh`.

`prealables` est une lecture locale. Elle est passée à 18:29:24 UTC, code 0 ([journal](o4-prealables.log)). Un premier passage, à 18:24:01 UTC, disait `sqv`, `gpgv` et `default-sequoia.config` absents de la couche ([journal](o4-prealables-premier-passage.log)). C'était un défaut du script : un `grep -q` dans un tube, sous `pipefail`, faisait échouer `tar -t`. La liste est désormais lue en entier avant la recherche. Le passage retenu donne :
- la copie locale du deb est égale à `f66bbeb2…` (1 953 492 octets) ;
- la racine Debian a apt et apt-utils 3.0.3, gnupg 2.4.7-21+deb13u1, gpg et gpgv 2.4.7-21+deb13u1+b5, sqv 1.3.0-3+b2, gzip 1.13-1+deb13u1, et l'utilisateur `_apt` ;
- `libapt-pkg.so.7.0` de la racine contient une fois chacune des chaînes `/usr/bin/sqv`, `/usr/bin/gpgv`, `APT::Key::GPGVCommand`, `Debug::Acquire::gpgv` et `Preparing to exec: ` ;
- dans l'amorce Debian 13 (`7378260c…`, couche `37fb86c2…`, 3 271 entrées), `usr/bin/sqv` et `usr/share/apt/default-sequoia.config` sont présents ; **`usr/bin/gpgv` et `usr/bin/gpg` sont absents** ; `etc/apt/apt.conf.d/docker-clean` est présent.

**`docker-clean`** est le fichier de l'image officielle. Il vide `/var/cache/apt/archives` et `/var/cache/apt/*.bin` après dpkg et après `update`, et met `Dir::Cache::pkgcache` à vide. Chaque cas d'O4 a son propre `Dir::Cache` sous `/var/cache/apt/o4/<cas>`, et `apt-get download` écrit dans un dossier de `/root/o4`. Le fichier est donc laissé en place, sans effet attendu sur la mesure.

**Méthode.** Le dépôt est construit et signé dans la racine Debian 13 : gpg 2.4.7, `apt-ftparchive` 3.0.3, clé importée dans un GNUPGHOME sur tmpfs, sans réseau. Le deb n'est pas modifié (D1 a). Le contrôle du lien se fait sur l'hôte par `python3 -I`, en suivant Release, puis Packages, puis le deb.

Le choix du vérificateur se mesure en deux endroits :
- **dans la racine Debian**, où sqv et gpgv sont présents tous les deux : `apt-get update` du seul dépôt signé, sans les secrets, avec les listes et le cache dans un dossier jetable. C'est là que la prédiction 5 du README se tranche ;
- **dans l'amorce**, sur le passage V1 lui-même. gpgv y est absent : sqv y est employé par construction, et ce relevé ne départage rien.

Dans les deux cas, la mesure passe par `Debug::Acquire::gpgv=true` : les lignes « Preparing to exec » sont citées entières.

La vérification se fait dans une amorce Debian 13 **extraite à neuf** de `7378260c…`, après contrôle par sha256, sans réseau, avec `Signed-By: /o2/t/cle-publique.asc` (clé armurée). Chaque cas a ses propres sources, listes et cache d'apt. `repetition` fait tourner la chaîne avec une clé jetable créée dans la racine Debian, puis tout est effacé. `signer` utilise la clé du PoC : `o4.sh` lie `09/secrets` en lecture seule dans la racine Debian, comme `o3.sh` dans la racine Rocky, et la session ne lit ni ne liste ce dossier. Le dépôt signé reste dans `o4/signer/` pour O5.

**Écart, même nature qu'en O3.** L'image `7378260c…` a déjà servi en O2, avec une extraction distincte pour `debian_amorce`. Son apt et son sqv ne sont contrôlés que par le sha256 de la couche, et non par un `Packages` vérifié. Le texte proposé pour l'ADR (§4 ter d'`A-REPORTER.md`) dit que chaque amorce ne sert qu'une fois. Ici, elle sert à vérifier, sans aucune clé privée. Un vérificateur contrôlé paquet par paquet demanderait le réseau, que K1 refuse tant que la clé existe sur l'hôte. Cet écart ira dans le rapport final.

**Cas de vérification.** Deux cas doivent être acceptés :
- `depot` ;
- `sans-inrelease` : Release et Release.gpg seulement.

Six témoins portent chacun un défaut :
- `autre-cle` : Release signé par une clé jetable RSA 3072 ;
- `release-modifie` : Label changé dans Release et dans InRelease après signature ;
- `packages-modifie` : une ligne ajoutée à Packages, et Packages.gz refait à partir de ce Packages modifié, sous un Release signé intact ;
- `deb-modifie` : un octet ajouté au deb, index et signatures intacts ;
- `sha1` : Release signé par la clé du dépôt en SHA-1 ;
- `sans-signed-by` : le dépôt signé, déclaré sans `Signed-By`.

**Gardes de construction.** Pour `autre-cle` et `sha1`, Release.gpg et InRelease doivent exister et être des signatures v4 RSA de la clé attendue, avec le condensat attendu : `digest algo 10` pour `autre-cle`, `digest algo 2` pour `sha1`. Sinon la ligne est KO, et un témoin non signé ne passe jamais pour un refus réussi.

**Refus jugés sur le motif du cas.** Toutes les lignes qui portent le motif sont citées, pas seulement la dernière :
- `packages-modifie` (V4) et `deb-modifie` (V7) ne valent que sur un motif d'empreinte ou de taille : `hash|mismatch|unexpected size|size` ;
- les autres refus ne valent que sur un motif de signature : `gpg|signature|signed|pubkey|missing key|sqv`.

Pour `sha1`, le refus est attribuable au condensat si la construction tient, car le cas ne diffère du dépôt accepté que par lui : même clé, même Release. Le nombre de lignes qui citent SHA-1 est relevé à part. Avant `signer`, les libellés d'apt et de sqv sont relus dans le journal de la `repetition`, pour vérifier qu'ils diffèrent d'un témoin à l'autre.

| N° | Prédiction (vaut pour `repetition` et pour `signer`) | Confiance |
|---|---|---|
| A1 | `apt-ftparchive packages` : code 0 ; une strophe `sample-app` 1.0.0-2 dont le SHA256 vaut `f66bbeb2…` | haute (banc O0, avec apt-ftparchive 3.2.1) |
| A2 | `apt-ftparchive release` : code 0 ; Release porte le SHA256 de Packages et de Packages.gz | haute |
| R1 | Relevé sans prédiction : champ `Date` de Release avec `SOURCE_DATE_EPOCH` sous `apt-ftparchive` 3.0.3. Le 3.2.1 de l'hôte l'ignorait (banc O0) | aucune |
| A3 | Release.gpg et InRelease : code 0 ; signature v4, RSA, de la clé du dépôt, condensat SHA-512 (`digest algo 10`), jugés OK ou KO | haute |
| L1 | Sur l'hôte : Packages et Packages.gz égaux à Release ; strophe unique portant `f66bbeb2…` ; fichier du dépôt égal à la strophe | haute |
| P5b | Dans la racine Debian (sqv et gpgv présents), `apt-get update` du dépôt signé : code 0, et les lignes « Preparing to exec » citent `/usr/bin/sqv`, jamais `/usr/bin/gpgv` (prédiction 5 du README) | moyenne : dépendance `sqv \| gpgv` et chaîne `/usr/bin/sqv` relevées ; règle de choix non lue dans le code |
| V1 | `apt-get update` sur `depot`, dans l'amorce : code 0. Une clé RSA 4096 v4, une signature SHA-512 et une clé armurée dans `Signed-By` sont acceptées par apt 3.0.3 (prédiction 3 du README, côté apt) | moyenne-haute : URI `file:`, bac à sable `_apt` et `.asc` sous sqv jamais mesurés ici |
| P5a | Dans l'amorce, le même passage cite `/usr/bin/sqv` | haute, par construction : gpgv est absent |
| V2 | `apt-get update` sur `sans-inrelease` : code 0, apt se rabat sur Release et Release.gpg | moyenne-haute |
| V3 | `apt-get update` sur `deb-modifie` : code 0, les index sont intacts | haute |
| V4 | `apt-get update` refusé, avec le motif du cas, pour `autre-cle`, `release-modifie`, `sans-signed-by` (signature) et `packages-modifie` (empreinte) ; `sample-app` reste ensuite inconnu d'`apt-cache` | haute ; moyenne-haute pour `packages-modifie` |
| V5 | `apt-get update` refusé pour `sha1`, avec un motif de signature | faible : le seuil de Sequoia pour SHA-1 sur une signature de données n'est pas lu (correction datée 1 du README) |
| V6 | `apt-get download sample-app` sur `depot` et `sans-inrelease` : code 0 ; le fichier écrit dans le dossier courant est égal à `f66bbeb2…`, relu dans l'amorce puis sur l'hôte (prédiction 6 du README) | moyenne-haute : copie depuis une source `file:` vers le dossier courant, non lue dans le code d'apt |
| V7 | `apt-get download` refusé pour `deb-modifie`, avec un motif d'empreinte ou de taille ; aucun deb dans le dossier de téléchargement | moyenne-haute |
| K3 | Aucune ligne de bloc OpenPGP dans le journal ; aucun fichier de `o4/<mode>` ne porte d'en-tête de clé privée ; deb du dépôt inchangé ; aucune ligne KO ; code final 0 | haute |

Les en-têtes publics « SIGNED MESSAGE » et « SIGNATURE » qu'apt pourrait recopier dans sa sortie sont remplacés à la journalisation. Sans cela, la garde K3 viderait le journal. Un en-tête de clé privée n'est pas remplacé et reste attrapé par K3.

P5a et P5b sont jugées par une ligne OK ou ÉCART, jamais KO : ce sont des prédictions sur un choix d'apt, pas des défauts de la chaîne. Le seul effet d'un écart à V5 (confiance faible) serait une ligne KO, et donc un code 1. Si la `repetition` n'échoue que sur V5, `signer` est lancée quand même ; l'écart est consigné. Tout autre KO arrête la suite et fait l'objet d'une note datée avant toute relance.

## Note datée du 19/11/2026, 18:31:26 UTC : premier passage de `repetition`, code 1 (6 lignes KO)

Passée de 18:30:34 à 18:30:38 UTC, code 1 ([journal](o4-repetition-premier-passage.log)), avec une clé jetable `46129DE4…65025E3C` (RSA 4096, créée par gpg 2.4.7). Scripts `o4.sh` `cc7e6665…` et `o4-interne.sh` `c50ff7c5…`.

**Tenues** :
- **A1, A2 et L1** : la strophe porte `f66bbeb2…` ; Packages (823 octets) et Packages.gz (571 octets) sont égaux à Release.
- **A3, pour le code et pour Release.gpg** : `algo 1, keyid 766B346B65025E3C`, `version 4`, `digest algo 10`.
- **V1** : `apt-get update` du dépôt signé, code 0, avec la clé armurée en `Signed-By`.
- **V3** : code 0.
- **V4**, pour les quatre témoins, code 100 chacun, et `sample-app` reste inconnu :
  - `autre-cle` : « Sub-process /usr/bin/sqv returned an error code (1), error message is: Missing key 7D9D75DB…, which is needed to verify signature » ;
  - `release-modifie` : « Message has been manipulated » ;
  - `packages-modifie` : « Hash Sum mismatch » sur Packages.gz (Filesize 571 attendu, 582 reçu) ;
  - `sans-signed-by` : « Missing key 46129DE4… ».
- **V5**, confiance faible : le témoin SHA-1 est refusé, code 100, avec « Policy rejected non-revocation signature (Text) requiring collision resistance because: SHA1 is not considered secure since 2013-02-01T00:00:00Z ». **Cette mesure tranche la correction datée 1 du README** : apt de Debian 13, par sqv, refuse une signature SHA-1 de `Release`.
- **V6 pour `depot`** : code 0. Le deb est écrit dans le dossier courant, égal à `f66bbeb2…` (1 953 492 octets), relu dans l'amorce puis sur l'hôte.
- **V7** : « Hash Sum mismatch » (Filesize 1 953 492 attendu, 1 953 493 reçu), code 100, aucun deb écrit.
- **K3, sur son périmètre** : aucun bloc dans le journal, aucun en-tête de clé privée dans `o4/repetition`, deb du dépôt inchangé.

**Relevés** :
- **R1** : `apt-ftparchive` 3.0.3 ignore aussi `SOURCE_DATE_EPOCH`. Avec `SOURCE_DATE_EPOCH=1763337600`, la `Date` vaut « Thu, 19 Nov 2026 18:30:36 +0000 », l'heure du lancement ; les deux sorties sont identiques. La date est donc celle de l'exécution, non celle de `SOURCE_DATE_EPOCH`.
- **apt de l'amorce est en 3.0.4**, non en 3.0.3 comme dans la racine : l'image `7378260c…` est plus récente que l'instantané de la racine. Les prédictions disaient « apt 3.0.3 » pour le vérificateur ; c'est faux pour l'amorce.
- `apt-get download` avertit : « Download is performed unsandboxed as root as file '/root/o4/depot/…' couldn't be accessed by user '_apt' ». Le dossier courant est sous `/root`, en 700. La vérification des empreintes a quand même lieu, comme le montre V7.

**Non tenues ou non mesurées** :
- **V2 non tenue, et V6 pour `sans-inrelease` en conséquence** : apt refuse un `Release.gpg` **binaire**. Il répond « Detached signature file '…Release.gpg' is in unsupported binary format » (« got 'NODATA' »), code 100. Le banc O0 et ce script signent `Release.gpg` sans `--armor`, et gpgv 2.4.8 l'acceptait. apt 3.0.4 par sqv ne l'accepte pas. Le dépôt `depot` est accepté parce qu'apt prend `InRelease` d'abord. **Constat utile pour D1 et pour la recommandation du README** sur CVE-2025-68972 (« vérifier `Release` + `Release.gpg` ») : un `Release.gpg` doit être armuré pour apt de Debian 13. La ligne KO du contrôle sur l'hôte (« deb téléchargé (sans-inrelease) : absent ») en découle.
- **P5a et P5b non mesurées par la méthode prévue** : `Debug::Acquire::gpgv=true` n'a produit aucune ligne « Preparing to exec » (0 ligne, dans la racine comme dans l'amorce). Deux lignes ÉCART, comme prévu pour ce cas. Dans l'amorce, les messages de refus nomment le vérificateur : « Sub-process /usr/bin/sqv » pour `autre-cle`, `release-modifie`, `sha1` et `sans-signed-by`. **P5a est donc tenue**, mais par ces messages, pas par le relevé de débogage. **P5b reste non mesurée** : dans la racine, seul le dépôt accepté a été passé, sans message qui nomme le binaire.
- **Trois lignes KO viennent d'un défaut du script, pas de la chaîne** : la garde de construction (`sig_ok`) lit `InRelease` par `gpg --list-packets`. Sur un message signé en clair, gpg s'arrête au paquet de données littérales et n'affiche pas le paquet de signature. D'où « InRelease n'est pas une signature v4 RSA… » pour le dépôt (A3), `autre-cle` et `sha1`. Pour la même raison, la garde n'a pas jugé l'`InRelease` des témoins ; seul leur `Release.gpg` l'a été : `digest algo 10` avec la clé `23A69D77…` pour `autre-cle`, `digest algo 2` avec la clé du dépôt pour `sha1`. **Vérifié sur l'hôte avant cette note** (heure non relevée), avec un trousseau jetable dans `$XDG_RUNTIME_DIR`, effacé ensuite : `gpg --list-packets` sur le bloc de signature **extrait** de l'`InRelease` du dépôt donne `algo 1, keyid 766B346B65025E3C`, `version 4`, `digest algo 10` (sortie non archivée en journal).

Les dossiers `o4/repetition*` restent en place jusqu'à la correction ; ils seront effacés avant la relance.

## Correction datée du 19/11/2026, 18:35:46 UTC, avant la relance de `repetition`, après relecture du conseiller

**Deux phrases de la note de 18:31:26 UTC dépassent la mesure :**
- « apt 3.0.4 par sqv ne l'accepte pas » : le refus du `Release.gpg` binaire ne cite pas « Sub-process /usr/bin/sqv », contrairement aux quatre autres refus. **Ce qui est mesuré est qu'apt 3.0.4 le refuse** ; qui refuse, d'apt ou de sqv, n'est pas établi. De même, « un `Release.gpg` doit être armuré pour apt de Debian 13 » ne vaudra qu'une fois V2 passée avec un `Release.gpg` armuré.
- « l'image `7378260c…` est plus récente que l'instantané de la racine » est faux. Sa configuration (`596c6d80…`, lue localement après contrôle par sha256) porte `created` 2026-11-04T21:23:39Z, avant l'instantané `20261105T000000Z`. La racine a apt 3.0.3 parce qu'O2 épingle `apt-utils=3.0.3` (`DEB_PAQUETS` d'`o2.sh`, l. 43), qui tire `apt_3.0.3`. L'origine du 3.0.4 de l'image n'est pas établie.

**Scripts corrigés** (`o4.sh` `6a16c5a1…`, `o4-interne.sh` `f4f9e76b…`) :
- **Release.gpg armuré** (`--armor`) pour le dépôt et pour les témoins. Nouveau témoin `release-gpg-binaire` : Release.gpg binaire seul, sans InRelease, signé par la clé du dépôt.
- **Garde de construction** : pour InRelease, le bloc de signature est extrait par `sed` dans GNUPGHOME, puis lu par `gpg --list-packets`. La lecture est vérifiée sur l'hôte (note précédente). La garde juge désormais l'InRelease des témoins `autre-cle` et `sha1`, puisque c'est le fichier qu'apt lit en premier. A3 vérifie aussi que Release.gpg commence par l'en-tête armuré.
- **Motifs resserrés par témoin**, d'après les libellés mesurés au premier passage :

  | Témoin | Motif |
  |---|---|
  | `autre-cle` et `sans-signed-by` | `Missing key` |
  | `release-modifie` | `manipulated` |
  | `packages-modifie` et `deb-modifie` | `Hash Sum mismatch` |
  | `sha1` | `SHA1` |
  | `release-gpg-binaire` | `binary format` |

  Toutes les lignes qui portent le motif sont citées, séparées par « | » ; au premier passage, le séparateur non ASCII était coupé sous `LC_ALL=C`.
- **P5 lue dans le message de refus du témoin `autre-cle`**. La ligne est OK si « Sub-process /usr/bin/sqv » paraît, ÉCART sinon, avec les sous-processus cités. L'autre branche n'exige pas la chaîne `/usr/bin/gpgv`, car le libellé d'apt sous gpgv n'est pas connu. `Debug::Acquire::gpgv` et le jugement sur « Preparing to exec » sont retirés.
- **Tous les cas tournent deux fois** :
  - dans la **racine Debian** : apt 3.0.3, vérifié paquet par paquet en O2, avec sqv et gpgv présents. Listes, cache et téléchargements vont dans `o4/<mode>-racine-apt`, lié en écriture ; les secrets ne sont pas liés ;
  - dans l'**amorce** : apt 3.0.4, gpgv absent, dossiers sous `/var/tmp/o4`.
  Le passage dans la racine réduit l'écart « amorce contrôlée par le sha256 de sa couche seulement ». Le dossier de téléchargement de chaque cas est donné à `_apt` (`chown`), pour un téléchargement dans le bac à sable ; si le `chown` est refusé, la ligne le dit.

**Prédictions de la relance** (valent pour `repetition` et pour `signer`, dans la racine et dans l'amorce, sauf mention) :

| N° | Prédiction | Confiance |
|---|---|---|
| A1, A2, L1, R1 | Comme au premier passage : A1, A2 et L1 tenues ; `SOURCE_DATE_EPOCH` ignoré | haute |
| A3 | Code 0 ; Release.gpg armuré et InRelease, v4, RSA, clé du dépôt, `digest algo 10` | haute |
| G | Gardes de construction : `autre-cle` (`digest algo 10`, clé jetable) et `sha1` (`digest algo 2`) jugées sur Release.gpg et InRelease ; `release-gpg-binaire` a un Release.gpg binaire, sans InRelease | haute |
| V1, V3 | Code 0 | haute (tenues dans l'amorce au premier passage) |
| V2 | `sans-inrelease`, avec un Release.gpg **armuré** : code 0 | moyenne-haute : l'armure est la seule différence avec le refus mesuré |
| V4 | Refus, code 100 ; motifs `Missing key`, `manipulated`, `Hash Sum mismatch` ; `sample-app` inconnu ensuite | haute |
| V5 | `sha1` refusé, motif `SHA1` | haute dans l'amorce (mesuré) ; moyenne-haute dans la racine (sqv attendu, voir P5) |
| V6 | `depot` et `sans-inrelease` : code 0 ; deb égal à `f66bbeb2…`, relu dans la racine ou l'amorce puis sur l'hôte | haute pour `depot`, moyenne-haute pour `sans-inrelease` |
| V7 | `deb-modifie` refusé au téléchargement, motif `Hash Sum mismatch` ; aucun deb écrit | haute |
| V8 | `release-gpg-binaire` refusé, code 100, motif `binary format` | haute dans l'amorce (mesuré) ; moyenne dans la racine, où gpgv est présent |
| P5a | Amorce : le refus d'`autre-cle` nomme `/usr/bin/sqv` | haute (mesuré au premier passage) |
| P5b | Racine, avec sqv et gpgv : le refus d'`autre-cle` nomme `/usr/bin/sqv` (prédiction 5 du README) | moyenne |
| K3 | Comme avant ; code final 0 | haute |

Si la `repetition` n'échoue que sur une prédiction de confiance moyenne (P5b ou V8 dans la racine), `signer` est lancée quand même ; l'écart est consigné. Tout autre KO arrête la suite.

Avant la relance, les dossiers `o4/repetition`, `o4/repetition-vierge`, `o4/repetition-racine-apt` et `o4/repetition-secrets` du premier passage sont effacés, dans l'espace de noms, avec des chemins littéraux.

## Note datée du 19/11/2026, 18:36:34 UTC : relance de `repetition` passée, toutes les prédictions tenues

Passée de 18:36:18 à 18:36:22 UTC, code 0, aucune ligne KO ni ÉCART ([journal](o4-repetition.log)). Scripts `o4.sh` `6a16c5a1…` et `o4-interne.sh` `f4f9e76b…`, ceux de la correction. Clé jetable du dépôt : `3683E06D…D737850E` ; clé du témoin `autre-cle` : `599661F2…7CF44FC7`.

- **A1, A2, L1 et K3 tenues.** R1 de nouveau : `SOURCE_DATE_EPOCH` est ignoré.
- **A3 tenue** : Release.gpg est armuré, et InRelease aussi est signé. Les deux sont des signatures v4 RSA de la clé du dépôt, avec `digest algo 10`.
- **G tenue** : `autre-cle` est signé par la clé jetable avec `digest algo 10`, `sha1` avec `digest algo 2`, et cela sur Release.gpg comme sur InRelease. `release-gpg-binaire` n'a qu'un Release.gpg binaire.
- Dans la **racine** (apt 3.0.3, sqv et gpgv présents) **et** dans l'**amorce** (apt 3.0.4, gpgv absent), mêmes résultats :
  - **V1, V2 et V3** : code 0. **V2 passe avec un Release.gpg armuré**, quand le binaire avait été refusé au premier passage. Ce qui est établi : apt de Debian 13, en 3.0.3 et en 3.0.4, accepte un dépôt sans InRelease si son Release.gpg est armuré, et le refuse s'il est binaire (V8).
  - **V4** : code 100 pour les quatre témoins, avec le motif attendu, et `sample-app` reste inconnu ensuite.
  - **V5** : refus de `sha1`, code 100. **Le motif `SHA1` est faible**, puisqu'il trouve aussi le nom du témoin dans les chemins. Le message « SHA1 is not considered secure since 2013-02-01 » est donc compté à part : 6 lignes dans le journal.
  - **V6** : `depot` et `sans-inrelease` téléchargés, chacun égal à `f66bbeb2…` (1 953 492 octets). Quatre fichiers sont relus sur l'hôte.
  - **V7** : `Hash Sum mismatch`, et aucun deb n'est écrit.
  - **V8** : `release-gpg-binaire` est refusé, code 100, avec « Detached signature file … is in unsupported binary format ». Ce refus ne nomme aucun sous-processus ; qui refuse, d'apt ou de sqv, n'est pas établi.
- **P5a et P5b tenues : prédiction 5 du README tenue.** Le refus d'`autre-cle` nomme « Sub-process /usr/bin/sqv » dans la racine aussi, où gpgv est installé. Dans tout le journal, 34 lignes nomment `/usr/bin/sqv`, aucune `gpgv`.
- **Bac à sable** : le `chown _apt` du dossier de téléchargement a passé (aucune ligne de refus), et l'avertissement « unsandboxed » du premier passage n'apparaît plus (0 ligne).

Les dossiers `o4/repetition*` sont effacés après le commit de cette note. Suite : `signer` avec la clé du PoC, mêmes prédictions.

## Note datée du 19/11/2026, 18:37:40 UTC : `signer` passée avec la clé du PoC, mêmes résultats que la répétition ; O4 terminé

Passée de 18:36:57 à 18:36:59 UTC, code 0, aucune ligne KO ni ÉCART ([journal](o4-signer.log)), mêmes scripts que la relance de la répétition. Clé du PoC importée : `29BA1C48…BCF03A86`. Le dépôt est signé avec `algo 1, keyid C0658591BCF03A86`, `version 4`, `digest algo 10`, sur Release.gpg armuré comme sur InRelease. La clé du témoin `autre-cle` est `38ED2445…5D3A6A7B`.

Le journal compte 63 lignes OK. La répétition en comptait 66, dont 3 viennent de l'étape `creer` de sa clé jetable. Toutes les prédictions de la correction de 18:35:46 UTC sont tenues, dans la racine (apt 3.0.3) comme dans l'amorce (apt 3.0.4) :
- quatre deb téléchargés par apt, égaux à `f66bbeb2…` et relus sur l'hôte ;
- les sept témoins refusés avec leur motif ;
- 6 lignes « SHA1 is not considered secure since 2013-02-01 » ;
- 34 lignes « Sub-process /usr/bin/sqv » ; aucune ne nomme gpgv ;
- R1 de nouveau : `Date` « Thu, 19 Nov 2026 18:36:57 +0000 » malgré `SOURCE_DATE_EPOCH`.

**Produits gardés pour O5**, dans `~/.cache/supply-chain-poc/09/o4/signer/` (hors du dépôt) :
- `depot/dists/poc/InRelease` : `9113af02f3d78bf6250f1c5b3dd5360e3b9e06b22fa55499137ee09df2337a8e` ;
- `Release` : `b6f2617f73a79c5af2e73b6d2c69a23b46ae0698a0af7909a650164f4d7ab043` ;
- `Release.gpg` : `72b930effcbed24ad5d5250b7c6df8ddd86b3f9a19f23e5469332818ce08a417` ;
- deb inchangé `f66bbeb2…` ;
- clé publique exportée : `20bcaf43…`.

Aucun fichier de ce dossier ne porte d'en-tête de clé privée. Compte fait sur l'hôte avant cette note : 0 fichier. `o4/signer-vierge` et `o4/signer-racine-apt` seront effacés après le commit.

**Jalon O4 tenu.** Critère du README : deb téléchargé égal à `f66bbeb2…` ; témoins refusés par apt.
- **Prédiction 3 du README tenue côté apt** : une clé RSA 4096 v4 est acceptée par apt 3.0.3 et 3.0.4.
- **Prédiction 5 tenue** : apt vérifie par sqv, même avec gpgv installé.
- **Prédiction 6 tenue** : le deb servi est égal à `f66bbeb2…`.
- **Correction datée 1 du README tranchée** : apt de Debian 13 refuse une signature SHA-1 de `Release`. Le message de sqv est « Policy rejected non-revocation signature (Text) requiring collision resistance ».
- **Constats nouveaux** :
  - un `Release.gpg` binaire est refusé (« unsupported binary format ») ; le dépôt publié a donc un `Release.gpg` armuré, et un dépôt sans `InRelease` est accepté sous cette forme. Ce dernier point compte pour la recommandation du README sur CVE-2025-68972 ;
  - `apt-ftparchive` 3.0.3 ignore `SOURCE_DATE_EPOCH`, comme le 3.2.1 de l'hôte.
- **Écart consigné** : l'image de l'amorce `7378260c…` a déjà servi en O2, et son apt 3.0.4 n'est contrôlé que par le sha256 de sa couche. Il est atténué par le passage complet dans la racine Debian, dont l'apt 3.0.3 a été vérifié paquet par paquet en O2.

## Note datée du 19/11/2026, 18:41:38 UTC : deux valeurs archivées, date de Release non fixée

- **Valeurs archivées par un relevé local** ([`o4-releve.sh`](../o4-releve.sh), [journal](o4-releve.log), 18:41:19 UTC, code 0). Jusqu'ici, la correction de 18:35:46 UTC et la note de `signer` citaient sans journal :
  - le `created` de l'image `7378260c…`, désormais archivé : 2026-11-04T21:23:39Z, configuration `596c6d80…` contrôlée par sha256 ;
  - le sha256 de la clé publique exportée, désormais archivé : `20bcaf43…`. **Les clés publiques exportées en O3 (gpg 2.3.3, `o3/signer`) et en O4 (gpg 2.4.7, `o4/signer`) sont égales octet pour octet** à celle de l'étape `cle` d'O2 (`o2-cle.log`). Le dossier `09/secrets` n'est pas lu.
- **La date de `Release` n'est pas fixée.** Le README (banc O0) disait qu'elle serait « à fixer autrement avant O4 » ; ce n'est pas fait. `apt-ftparchive` 3.0.3 ignore `SOURCE_DATE_EPOCH` (R1), et la signature porte sa propre date. Chaque passage de `signer` donne donc un `Release`, un `InRelease` et un `Release.gpg` différents. O5 devra viser les empreintes du dépôt gardé dans `o4/signer` (note précédente). Refaire `signer` changerait ces empreintes.
- **Motif `SHA1` trop lâche** (relecture du conseiller) : il trouve aussi le nom du témoin dans les chemins. Le refus pour SHA-1 repose sur le message de politique, compté à part : 6 lignes dans chaque journal. `signer` n'est pas relancée pour ce motif, car le dépôt gardé pour O5 changerait d'empreintes.
