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
