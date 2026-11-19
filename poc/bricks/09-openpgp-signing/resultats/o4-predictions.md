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
