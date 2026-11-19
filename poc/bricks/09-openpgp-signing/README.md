# Brique 09 : signature OpenPGP des rpm, des deb et des dépôts, protocole proposé

Seuil (README, brique 09) : **rpm, deb et dépôt signés ; attestation de lien vérifiée.** Effort estimé : **1,5 pw** ; décision avec le propriétaire à 3 pw.

Règles reprises : celles de la [brique 05](../05-rpm-mock/README.md) (projets jugés par le doc 04, rien de « Risqué » ; versions épinglées ; empreintes et signatures vérifiées ; prédictions datées et commitées avant chaque mesure ; passages ratés archivés ; accord du propriétaire avant tout changement du cluster, de Zot ou d'un système).

## État

**Préparé à sec le 19/11/2026 (squelette à 14:39:09 UTC, relevés de 14:44:38 à 14:53:01 UTC, protocole écrit à partir de 14:53:44 UTC), dans un worktree à part (branche `claude/brique-09-sec-fdb4c6`, jamais poussée). Rien installé, aucun `sudo`, rien lu ni écrit dans le cluster ou dans Zot.** Seuls ont tourné des relevés en lecture publique ([`releve-amont.sh`](releve-amont.sh) et trois compléments, journaux sous [`resultats/`](resultats/)) et, après les prédictions de ce README, un banc sur l'hôte avec les outils déjà présents (voir « Banc hors cluster »). Les jalons O2 et suivants attendent les décisions D1 à D4 et un accord pour chacun.

Les ajouts proposés aux fichiers partagés (doc 03, doc 04, README racine, ADR, et une correction datée du doc 00) sont dans [`A-REPORTER.md`](A-REPORTER.md). Cette session ne modifie pas ces fichiers.

## Ce qui existe déjà

- **Doc 00, l. 106** : signature OpenPGP « **Retenu** (brique 09) », service isolé et HSM (sigul, signd d'OBS, worker debusine cités) ; OpenBao Transit « ne fait pas d'OpenPGP » ; « `rpmsign`/`debsign` modifient l'artefact, d'où une attestation de lien ». **La moitié deb de cette phrase est inexacte** d'après la page de manuel de trixie : `debsign` signe le `.dsc`, le `.buildinfo` et le `.changes`, pas le `.deb` ([journal](resultats/releve-complements.log), §A). Correction datée proposée dans `A-REPORTER.md`.
- **Doc 02, l. 30** : nœud `PGP[Service OpenPGP + HSM]` dans la zone Confiance. **l. 217** : clé « OpenPGP dépôts et paquets », stockage « HSM du service de signature isolé », usages `rpmsign`, `debsign`, `Release`/`repomd`, rotation « expiration planifiée, révocation ».
- **Doc 01** : **B8** (« Signés en OpenPGP avec attestation de lien ») ; **B1** définit le bit-identique « contenu hors signature OpenPGP », ce qui fixe la propriété que l'attestation de lien doit porter ; ligne des clés (l. 105) : séparation par usage, rotation, révocation, ADR 0003 ; l. 41 : « clés OpenPGP (HSM) » ; menace G (l. 64) : « OpenPGP sur les dépôts ».
- **ADR 0003** : « À rédiger » ; entrées mesurées en brique 08 (J3 clé de provenance Transit, J5 clé `tsa`, J6 clé des tâches en fichier 0600 sur l'hôte d'administration).
- **Artefacts à signer, lus dans les journaux** (pas tirés de Zot) :
  - rpm : `sample-app-1.0.0-2.el9.x86_64.rpm`, 2 173 376 octets, sha256 `864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f`, seul membre de la couche du manifeste `sha256:07b7bd6feb489bff10aa92b7fd632a50a7958e84092ae1802f12b7c259e1d119` (`builds/sample-app-rpm`, M4c, [comparaison](../05-rpm-mock/resultats/m4c-comparaison.log), l. 6, 33, 34) ;
  - deb « D » : `sample-app_1.0.0-2_amd64.deb`, 1 953 492 octets, sha256 `f66bbeb2aba31e5220b332ff3941697dce7660259aa182047a58e77f4f51892b`, dans le manifeste `sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e` (`builds/sample-app-deb`, [S4d](../06-deb-sbuild/resultats/s4d-pipeline.log), l. 11 et 57 ; [S3](../06-deb-sbuild/resultats/s3-comparaison.log), l. 4).

## Relevé amont (19/11/2026, 14:44:38 à 14:53:01 UTC)

Journaux : [relevé](resultats/releve-amont.log), compléments [1](resultats/releve-complements.log), [2](resultats/releve-complements-2.log) et [3](resultats/releve-complements-3.log). **78 fichiers téléchargés, 50 462 785 octets** au total, dont `primary.xml.gz` de Rocky 9.8 BaseOS pour 45 549 029 octets ; nom, origine, taille et sha256 de chacun dans la [liste](resultats/releve-amont-telechargements.tsv). Dossiers neufs, sous `~/.cache/supply-chain-poc/09/` (`releve-20261119T144438Z`, `complements-20261119T144707Z`, et le `--homedir` de gpg `gnupg-releve-20261119T144438Z`), relus par `python3 -I` ou par `gpgv` ; à garder : deux scripts les relisent par chemin fixe.

| Point | Mesuré | Conséquence |
|---|---|---|
| GnuPG amont | `swdb.lst` **vérifié par gpgv** (clé `6DAA6E64…3ADA`, une des 6 empreintes de `signature_key.asc`, recoupées avec `signature_key.html` du même site) : `gnupg26_ver 2.5.24` du 23/09/2026, `gnupg24_ver 2.4.9` du 30/12/2025. Tableau de fin de vie : **2.4 au 30/06/2026**, 2.5 et 2.6 « tba », **aucune ligne 2.3** ; libgcrypt 1.10 au 30/06/2026 | La branche 2.4 est hors maintenance amont depuis 4 mois et demi |
| GnuPG de Debian 13 | `gnupg` et `gpgv` **2.4.7-21+deb13u1** ; tracker de sécurité : 4 failles « Open issues » pour trixie, toutes « vulnerable (no DSA) » (CVE-2026-105712 gpgtar, CVE-2026-57062 gpgsm, CVE-2026-24882 tpm2d, **CVE-2025-68972** messages signés en clair « through 2.4.8 »), et CVE-2022-3219 sous « Open unimportant issues » | CVE-2025-68972 touche la vérification de messages signés en clair, donc la forme `InRelease` vérifiée par gpgv : vérifier `Release` + `Release.gpg`, ou l'octet sorti de la vérification, jamais le fichier brut |
| GnuPG de Rocky 9.8 | `gnupg2` **2.3.3-5.el9_7** (construit le 19/01/2026), BaseOS vérifié par son `repomd.xml.asc` (clé `21CB256A…275D`, celle du doc 04) ; `rpm-sign-libs` 4.16.1.3-40.el9 **exige `/usr/bin/gpg2`** | La signature rpm passe par le gpg de Rocky, version d'une branche amont absente du tableau de fin de vie : maintenance de la distribution seulement |
| GnuPG de l'hôte | 2.4.8 (Ubuntu 26.04) | Le banc ne mesure ni 2.3.3 ni 2.4.7 |
| rpm de Rocky 9.8 | `rpm` et `rpm-sign` 4.16.1.3-40.el9 (28/12/2025) ; `rpm-libs` lié à `libcrypto.so.3` ; `rpm-sequoia` présent dans BaseOS, non requis par `rpm-libs` | Au tag amont `rpm-4.16.1.3` : `--addsign`, `--resign`, `--delsign` ; `%__gpg_sign_cmd` appelle gpg ; EdDSA cité 23 fois dans `digest_openssl.c` (compte d'occurrences, pas une mesure de Rocky) |
| apt de Debian 13 | **3.0.3** (3.0.4 en proposed-updates) ; `debian/control` : `sqv (>= 1.3.0) … | gpgv` ; `debian/default-sequoia.config` : DSA refusé depuis le 01/02/2024, RSA 2048 jusqu'au 01/02/2030, **SHA-1 et SHA-224 jusqu'au 01/02/2026**, signatures v3 jusqu'au 01/02/2026 ; `sqv` 1.3.0-3+b2 dans trixie | Clé RSA ≥ 3072 ou Ed25519, empreinte SHA-256 ou SHA-512, signatures v4. **Quelle méthode apt emploie réellement (sqv ou gpgv) n'est pas lu** : à mesurer en O4 |
| Outils deb | `apt-utils` (`apt-ftparchive`) 3.0.3 ; `devscripts` (`debsign`) 2.25.15+deb13u1 ; `reprepro` 5.4.6+really5.3.2-1+deb13u1 ; `debsigs` 0.2.2-1 et `debsig-verify` 0.33 ; **`dpkg-sig` et `obs-signd` absents de trixie** (madison) | Un dépôt signé se fait avec `apt-ftparchive` et gpg, sans outil de plus |
| Outils rpm | `createrepo_c` 0.20.1-4.el9 (AppStream 9.8, déjà audité au doc 04) ; `repomd.xml.asc` de Rocky : signature détachée armurée | Même forme pour notre dépôt |
| HSM logiciel | SoftHSMv2 **2.7.0** du 20/01/2026 (trixie 2.6.1-3, Rocky `softhsm` 2.6.1-11.el9) ; pont gpg vers PKCS#11 : **gnupg-pkcs11-scd 0.11.0 du 27/10/2024**, rien depuis ; obs-sign : moteurs `signd_pkcs11` et `signd_tpm` **sur master seulement**, absents du tag 2.8.5 | **Aucun chemin publié et maintenu de gpg vers PKCS#11** : la garde de la clé se réduit à un fichier dans un service isolé, ou à un jeton matériel (carte OpenPGP par `scdaemon`) |
| Services de signature | **sigul** 1.4 (EPEL 9 : 1.4-1 ; paquet « Update to v1.4 » le 22/04/2025 ; aucun tag plus récent) ; **siguldry** 0.9.1 du 13/11/2026, 0.x, « not currently deployed within the Fedora infrastructure » ; **obs-sign** 2.8.5 du 05/02/2026 ; **debusine** : clés OpenPGP sur HSM non faites (ticket 1099 « opened ») ; **vault-gpg-plugin** v0.6.3 du 02/01/2025 | Aucun service tout fait n'est retenable aujourd'hui (verdicts ci-dessous) |

## Trois niveaux d'identité et attestation de lien

Chains et la VSA ne connaissent que les **manifestes OCI** (`07b7bd6f…`, `60f25f5c…`). La couche porte le **fichier** (`864d55f4…`, `f66bbeb2…`). Signer un rpm crée un **troisième objet**, le fichier signé, publié sous un nouveau manifeste, sans provenance de Chains. L'attestation de lien doit relier ce nouvel objet au manifeste non signé, et la propriété de B1 (« contenu hors signature OpenPGP ») dit ce qu'elle affirme : même en-tête principal et même charge utile, seule l'en-tête de signature change.

- **rpm** : la signature s'écrit dans l'en-tête de signature. Vérification indépendante proposée : les octets à partir de l'en-tête principal sont identiques dans le rpm signé et dans `864d55f4…`, et `SHA256HEADER` et le digest de la charge utile sont égaux (`rpm -qp --qf`). `rpm --delsign` puis comparaison à `864d55f4…` est un second contrôle, d'issue incertaine.
- **deb** : avec D1 (a), le `.deb` n'est pas modifié. Le lien est une identité : l'entrée `Packages` du dépôt signé porte `f66bbeb2…`, et `Release` (signé) porte l'empreinte de `Packages`.
- **dépôts** : `Release`/`InRelease` et `repomd.xml.asc` signent des métadonnées neuves ; l'attestation énumère les fichiers couverts et leurs empreintes.

## Options étudiées (verdicts proposés, détail dans `A-REPORTER.md`)

| Option | Mesure qui décide | Verdict proposé | Retenue |
|---|---|---|---|
| GnuPG (gpg, gpg-agent, gpgv), paquets de la distribution | Releases et swdb signés ; 90 commits en 90 jours sur le miroir, 4 auteurs, 60 commits d'un même domaine ; branche 2.4 en fin de vie amont ; 4 failles ouvertes sans DSA dans trixie | **À surveiller, chemin critique** | Oui |
| rpm-sign (projet rpm) | Déjà au doc 04 (rpm « À surveiller ») ; exige gpg2 | Renvoi à la ligne rpm | Oui |
| createrepo_c | Déjà au doc 04 | Renvoi | Oui |
| apt (`apt-ftparchive`) | 3.3.8 du 16/11/2026 ; au moins 100 commits en 90 jours, 9 auteurs, **79 sur 100 d'un même auteur** | **À surveiller, chemin critique** | Oui |
| sqv (Sequoia), vérificateur de apt | sequoia-sqv v1.5.0 du 03/07/2026, 0 commit en 90 jours sur ce dépôt ; bibliothèque `openpgp/v2.4.2` du 14/10/2026, 27 commits, 5 auteurs | **À surveiller**, hors chemin de signature (côté consommateur, sert au contrôle O4) | Oui, pour vérifier |
| devscripts (`debsign`) | v2.26.15 du 07/11/2026 ; 39 commits, 16 auteurs | **À surveiller** (employeurs non établis, Scorecard n/a) | Selon D1 |
| sigul | Aucun tag après v1.4, publiée au plus tard le 22/04/2025 | **Remplit à la lettre « Risqué »** (borne : date du tag non lue) | Non |
| gnupg-pkcs11-scd | 0.11.0 du 27/10/2024, 0 commit en 90 jours | **Remplit à la lettre « Risqué »** | Non |
| vault-gpg-plugin | v0.6.3 du 02/01/2025, un seul auteur ; extension de Vault, OpenBao non vérifié | **Remplit à la lettre « Risqué »** | Non |
| debsigs | Tag amont `release/0.2.2` du 22/11/2024 ; trixie livre 0.2.2-1 ; tag d'empaquetage `debian/0.2.2-2` du 07/01/2026, sans nouvelle version amont | **Remplit à la lettre « Risqué »** (le tag Debian est un empaquetage, pas une release ; même lecture que pour GnuPG, où seule la release amont compte pour le critère) | Non |
| dpkg-sig | Absent de trixie (madison) | Non audité | Non |
| obs-sign | Tag 2.8.5 du 05/02/2026 ; 10 commits en 90 jours, tous du même domaine ; absent de trixie, EPEL 9 en 2.5.10 de 2021 ; PKCS#11 et TPM non publiés | **À surveiller** | Non (usage : à construire depuis les sources, sans HSM publié) |
| siguldry | 0.9.1, 0.x ; 60 commits, 4 auteurs, 38 d'un même domaine ; licence non détectée par l'API ; non déployé par Fedora | **À surveiller (0.x)** | Non, veille |
| SoftHSMv2 | 2.7.0 du 20/01/2026 (plus de 6 mois) ; 11 commits, 8 auteurs | **À surveiller** | Non (aucun pont gpg publié) |
| debusine (worker de signature) | Déjà au doc 04 « À surveiller (option) » ; OpenPGP sur HSM non fait | Inchangé | Non |

## Décisions à prendre

Recommandations soumises au conseiller avant d'être écrites ; les vrais choix reviennent au propriétaire, une question à la fois, dans l'ordre D1, D2, D3, D4.

**D1. Lecture de « deb signé ».** Recommandé : **(a)**.
- (a) Le `.deb` reste tel quel (bit-identique, `f66bbeb2…`). La signature porte sur le dépôt (`Release.gpg` et `InRelease`, vérifiés par apt), et, en option, sur le `.changes` et le `.buildinfo` par `debsign`. C'est la pratique de Debian. Le lien deb est une identité d'empreinte.
- (b) Signature intégrée au `.deb` (`debsigs`, membre `_gpg…`) : modifie l'artefact, n'est pas vérifiée par apt par défaut, et `debsigs` remplit à la lettre « Risqué ». Écartée sauf décision contraire.

**D2. Garde de la clé (sens de « HSM » dans le PoC).** Recommandé : **(a)**.
- (a) Fichier de clé (`private-keys-v1.d`, 0600, sans phrase de passe ou avec une phrase hors argument) dans un **service de signature isolé hors du cluster, sur l'hôte d'administration**, comme la clé des tâches de J6 ; aucun HSM, écart écrit dans l'ADR 0003. Le cluster ne voit jamais la clé privée.
- (b) Même fichier, dans un pod dédié de la zone Confiance (Secret monté) : plus proche du doc 02, mais la clé est lisible par quiconque lit les Secrets de cet espace, et il faut des tâches, des droits et une NetworkPolicy de plus.
- (c) Jeton matériel OpenPGP (`scdaemon`) : seule voie HSM mesurable sans logiciel « Risqué », mais achat, accès USB et règles udev sur l'hôte (installation système, à demander).

**D3. Émetteur et clé de l'attestation de lien.** Recommandé : **(a)**.
- (a) Le service de signature émet un énoncé in-toto (sujet : l'artefact signé ; prédicat : manifeste et fichier non signés, empreinte de la clé OpenPGP, versions des outils, contrôle de B1), signé par cosign avec une **clé Transit dédiée `lien`** dans OpenBao, distincte des clés de provenance, `tsa` et des tâches (séparation par usage, doc 01 l. 105). Avant de signer, le service vérifie la provenance de Chains sur le manifeste non signé, comme le job TSA de J6.
- (b) Même énoncé signé par la clé OpenPGP elle-même : une clé de moins, mais Kyverno et Conforma ne savent pas vérifier une signature OpenPGP.

**D4. Version de GnuPG.** Recommandé : **(a)**.
- (a) Paquets des distributions : `gnupg2` 2.3.3-5.el9_7 de Rocky 9.8 pour rpm (imposé par `rpm-sign-libs`), `gnupg` 2.4.7-21+deb13u1 de Debian 13 pour deb. Maintenance par les distributions, branches amont hors maintenance ; failles ouvertes à suivre.
- (b) GnuPG 2.5.24 construit depuis l'archive amont signée : version maintenue en amont, mais une construction de plus, et rien ne garantit que `rpm-sign` 4.16 l'accepte.

## Jalons proposés

Chaque jalon demande un accord ; « pod d'essai avant signature » de toute tâche neuve, comme en 05 et 06.

| Jalon | Contenu | Preuve attendue |
|---|---|---|
| O0 | **Banc hors cluster** (fait à sec, voir plus bas) : dépôt apt signé sur l'hôte autour d'une copie de D | Chaîne `Release.gpg` → `Release` → `Packages` → `f66bbeb2…` ; témoins refusés |
| O1 | Lignes du doc 04 intégrées par la session principale ; D1 à D4 décidées | Doc 04 à jour, décisions consignées |
| O2 | Clé OpenPGP du PoC (RSA 4096, v4, identité fictive, expiration, certificat de révocation à part) selon D2 ; images de signature construites par la plateforme : Rocky 9.8 (`rpm-sign`, `gnupg2`, `createrepo_c`) et Debian 13 (`gnupg`, `apt-utils`), paquets épinglés et vérifiés | Empreinte de la clé ; images par digest ; signatures des paquets d'origine vérifiées |
| O3 | rpm : `rpmsign --addsign` sur une copie de `864d55f4…` ; `rpmkeys --checksig` dans un Rocky 9.8 vierge ; contrôle de B1 ; dépôt par `createrepo_c` et `repomd.xml.asc` ; `dnf` avec `gpgcheck=1` et `repo_gpgcheck=1` | rpm signé vérifié ; en-tête principal et charge utile inchangés ; dépôt accepté, témoins refusés |
| O4 | deb : le dépôt du banc refait dans l'image Debian 13 ; `apt update` et `apt-get download` dans un Debian 13 vierge avec `signed-by` ; méthode réellement employée par apt relevée (sqv ou gpgv) | deb téléchargé égal à `f66bbeb2…` ; témoins refusés par apt |
| O5 | Attestation de lien (D3) pour le rpm, le deb et les deux dépôts, en referrer dans Zot ; vérification par cosign et par un contrôle indépendant de B1 | Attestations vérifiées ; refus : lien vers un autre digest, rpm à charge altérée, clé étrangère |
| O6 | Optionnel, à chiffrer après O5 : tâche signée dans la pipeline, ou contrôle par la porte (Conforma) | Hors de l'estimation de 1,5 pw |

## Prédictions de la brique (19/11/2026, avant tout lancement)

| # | Prédiction | Confiance |
|---|---|---|
| 1 | Le `rpmsign --addsign` de Rocky 9.8 laisse l'en-tête principal et la charge utile inchangés : octets égaux à `864d55f4…` à partir de l'en-tête principal | Moyenne-haute : la signature va dans l'en-tête de signature ; jamais mesuré dans ce PoC |
| 2 | `rpm --delsign` sur le rpm signé redonne exactement `864d55f4…` | Faible : remplissage de l'en-tête de signature non lu |
| 3 | Une clé RSA 4096 v4 est acceptée par `rpmkeys` de Rocky 9.8 et par apt de Debian 13 | Haute : la clé de Rocky est RSA ; RSA 4096 n'est pas borné par `default-sequoia.config` |
| 4 | Une clé Ed25519 v4 serait aussi acceptée par Rocky 9.8 | Faible : comptes d'occurrences au tag amont seulement ; non retenue pour le PoC |
| 5 | apt de Debian 13 vérifie par sqv, pas par gpgv | Moyenne : dépendance et méthode présentes, choix effectif non lu |
| 6 | Le deb servi par le dépôt signé est égal à `f66bbeb2…` | Haute : `apt-ftparchive` ne modifie pas les paquets |
| 7 | L'effort reste sous 1,5 pw si D2 (a) et D3 (a) sont retenues | Faible : la 05 et la 06 ont dépassé leur estimation ; O3 et O5 sont neufs |

Prédictions du banc : [`resultats/banc-depot-deb-predictions.md`](resultats/banc-depot-deb-predictions.md).

## Banc hors cluster

**Possible sans rien installer, pour le dépôt deb seulement**, avec les outils déjà sur l'hôte : `gpg` et `gpgv` 2.4.8, `apt-ftparchive`, `dpkg-deb`, `python3`. Script : [`banc-depot-deb.sh`](banc-depot-deb.sh), étapes `prealables` puis `banc`.

- Entrée : une copie locale de D (`~/.cache/supply-chain-poc/08/travail/s3-06/build-1/`), admise parce qu'elle n'est pas tirée de Zot (interprétation), et **refusée si son sha256 diffère** de celui de [`s3-comparaison.log`](../06-deb-sbuild/resultats/s3-comparaison.log). Rien n'est écrit dans les dossiers 05, 06 ou 08.
- Clé jetable RSA 4096, identité fictive sans adresse, `%no-protection` dans un fichier de paramètres (aucun secret en argument), `--homedir` neuf ; seules des empreintes sont journalisées.
- **Non faisable sur l'hôte sans installation** : `rpmsign` (rpm absent), `createrepo_c` (absent), `debsign` (devscripts absent), `sqv` (absent), tout HSM. Le banc ne mesure donc ni le gpg de Rocky (2.3.3) ni celui de Debian 13 (2.4.7), ni le vérificateur réel d'apt.

## Risques

- **GnuPG hors maintenance amont** dans les deux distributions (D4) ; failles ouvertes sans DSA. Plan de sortie relevé, non mesuré : Sequoia côté deb (`sq` 1.3.1 dans trixie) ; côté rpm, aucun, `rpm-sign` 4.16 appelant gpg.
- **Pas de HSM** (D2) : la clé du PoC est un fichier. Écart à écrire dans l'ADR 0003.
- **Un seul fusionneur ou presque** pour apt (79 commits sur 100) et pour les candidats écartés.
- **Nouveau manifeste sans provenance** pour le rpm signé : sans attestation de lien vérifiée à l'admission, Kyverno refuserait ou laisserait passer selon la règle ; à régler en O5.
- **Dépassement** : la 05 et la 06 ont dépassé leur estimation ; seuil de décision à 3 pw.

## Accords à demander avant tout passage dans le cluster

1. D1 à D4 (une question à la fois).
2. Création de la clé OpenPGP du PoC et son emplacement (D2), puis de la clé Transit `lien` dans OpenBao (D3).
3. Construction des deux images de signature par la plateforme et leur publication dans Zot.
4. Pods d'essai dans le cluster (O3, O4) et écritures dans Zot : rpm signé, dépôts signés, attestations de lien.
5. Toute modification de Kyverno, de la porte ou des NetworkPolicy (O5, O6).
6. Aucune installation sur l'hôte n'est prévue ; D2 (c) en demanderait une.

## Limites connues

- Les employeurs ne sont mesurés que par les domaines des adresses d'auteur.
- Le Scorecard de `gpg/gnupg` (3,5) est celui d'un miroir que les mainteneurs ne suivent pas, pas celui du projet : GnuPG est jugé au §4 du doc 04 (hors GitHub).
- Le délai de correction des CVE de GnuPG n'est pas mesuré.
- Les cibles 2c de B8 (alma-9, centos-stream-10, debian-12, ubuntu-24.04) ont leurs propres vérificateurs (rpm-sequoia, gpgv, apt 2.x), non relevés.

## Additif du 19/11/2026, écrit à 15:00:47 UTC : banc O0 passé, prédictions tenues

Banc lancé après le commit des prédictions (`96b7e6f7`) : `prealables` à 14:58:01 UTC (4 OK), `banc` de 14:58:04 à 14:58:06 UTC (14 OK, 0 ÉCART), code 0 pour les deux. Détail et lecture : [note datée](resultats/banc-depot-deb-predictions.md#note-datée-du-19112026-écrite-à-145910-utc--banc-passé-toutes-les-prédictions-tenues).

- Dépôt apt signé (RSA 4096, v4, SHA-512) autour d'une copie de D : `Release.gpg` et `InRelease` vérifiés par gpgv 2.4.8 ; chaîne `Release` → `Packages` → `f66bbeb2…` tenue, deb inchangé ; témoins refusés ou détectés (Release et InRelease altérés, clé étrangère, Packages et deb altérés).
- **gpgv 2.4.8 accepte une signature SHA-1**, que `default-sequoia.config` d'apt de Debian 13 refuse depuis le 01/02/2026 : un contrôle par gpgv ne remplace pas le vérificateur d'apt, d'où la mesure par apt en O4.
- **`apt-ftparchive` 3.2.1 (celui de l'hôte, pas le 3.0.3 de trixie) ignore `SOURCE_DATE_EPOCH`** pour le champ `Date` de `Release` (relevé non prédit) : la date de `Release` est à fixer autrement avant O4.
- Le dossier du banc, clé jetable comprise, a été effacé après archivage.
- **Incident** pendant l'écriture de la note (hors du banc) : des accents graves dans une commande `bash -c` ont été exécutés par zsh, dont `gpgconf --kill all` **sans `--homedir`**, qui a arrêté les démons de GnuPG du trousseau par défaut de l'utilisateur (ils redémarrent à la demande ; aucune clé lue ni affichée). Détail dans la [note du banc](resultats/banc-depot-deb-predictions.md#incident-du-19112026-vers-145829-utc-après-le-banc-hors-du-script).
- Ajouts proposés aux fichiers partagés : [`A-REPORTER.md`](A-REPORTER.md).

## Corrections datées du 19/11/2026, écrites à 15:04:40 UTC, après la relecture finale du conseiller

Les passages ci-dessus restent tels qu'écrits ; voici ce qui les corrige ou les borne. Source neuve : [quatrième complément](resultats/releve-complements-4.log) (15:04:01 à 15:04:04 UTC, lecture publique, rien écrit sur disque hors du journal).

1. **SHA-1 et apt, affirmation trop forte** (tableau du relevé, prédiction BD11, additif de 15:00:47 UTC). La ligne lue est exactement `sha1.second_preimage_resistance = 2026-02-01    # Extend the expiry for legacy repositories`. D'après les commentaires de `openpgp/src/policy.rs` de Sequoia (tag `openpgp/v2.4.2`), la résistance à la seconde préimage suffit à beaucoup d'autosignatures, et la résistance aux collisions est requise pour une signature sur des données qu'un attaquant a pu influencer. La ligne d'apt vise donc d'abord les autosignatures. Pour une signature de données comme `Release`, le seuil de SHA-1 est celui de la politique par défaut de Sequoia, **non lu**. « apt de Debian 13 refuse SHA-1 depuis le 01/02/2026 » **n'est pas établi** ; reste établi que gpgv 2.4.8 accepte une signature SHA-1 de données. La mesure par apt en O4 tranchera.
2. **« Recommandations soumises au conseiller avant d'être écrites »** (section « Décisions à prendre ») : inexact au moment du commit `96b7e6f7`. Seule l'orientation de D1 avait été relue. **D1 à D4 ont été relues par le conseiller après le commit `75437af4` (date d'auteur 15:00:58 UTC)** : accord sur les quatre, avec ces compléments :
   - **D1 (a)** : la pipeline S4d ne publie que le deb. Son journal imprime le `.buildinfo` mais ne cite aucun `.changes` (0 ligne), et la couche publiée (1 955 840 octets) n'y est pas listée membre par membre. **L'option `debsign` n'a donc aujourd'hui aucun artefact de la plateforme à signer** ; elle demanderait de publier le `.changes` et le `.buildinfo`.
   - **D2 (a)** a deux coûts à écrire : c'est un **écart avec le doc 02** (l. 30 : service dans la zone Confiance), et la signature n'est pas automatisée dans la pipeline. Avec D3 (a), l'hôte d'administration doit aussi détenir **un jeton OpenBao** pour la clé `lien` et **un accès en lecture à Zot**.
   - **D3 dépend de D2** : l'ordre des questions (D1, D2, D3, D4) tient.
3. **Versions** : `gpgv` de Debian 13 est en `2.4.7-21+deb13u1+b5` (madison), et non `2.4.7-21+deb13u1`, qui est la version de `gnupg`. Les versions de Rocky viennent de `pub/rocky/9.8`, dont le contenu bouge : l'épinglage d'O2 suivra la source figée décidée pour la brique 05.
4. **debsigs** : le verdict proposé repose sur les seuls tags du dépôt salsa `debian/debsigs`.
5. **Incident** : « aucune clé lue ni affichée » est plus fort que la mesure. Établi : rien n'a été affiché. La lecture de la configuration du trousseau par défaut par `gpg-agent` et `gpgconf` n'est pas exclue. Une note d'avertissement a été déposée dans le dossier partagé des sessions.
6. **Transparence** : pendant l'orientation, un `find` sur `~/.cache/supply-chain-poc` (profondeur 6 et 7, à la recherche des copies du rpm et du deb) a exclu les dossiers `auth`, `secrets` et `docker`, mais **pas `pac/banc/forgejo`**. Il n'a affiché que des chemins de fichiers `sample-app*.rpm` et `sample-app_1.0.0-2_amd64.deb`, aucun de ce dossier.

## Décision du propriétaire du 19/11/2026 : D1 (a) (consignée à 15:22:10 UTC)

Question posée dans le cadre de fin de tour : « Pour « deb signé » (D1), garder le .deb intact et signer le dépôt ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus : « Oui, option (a) ».

- **D1 (a) retenue** : le `.deb` reste tel quel (bit-identique, `f66bbeb2…`). « deb signé » se lit comme **dépôt apt signé** (`Release.gpg` et `InRelease`), vérifié par apt. Le lien deb est une identité d'empreinte : la strophe `Packages` porte le sha256 du fichier de la couche de `60f25f5c…`.
- **`debsign` n'est pas employé pour l'instant** : la pipeline S4d ne publie ni `.changes` ni `.buildinfo` (corrections datées ci-dessus, point 2). La ligne devscripts proposée au doc 04 reste donc sans usage.
- **D1 (b)**, signature intégrée au `.deb` par `debsigs`, est écartée.
- **Rien n'est lancé.** Question suivante : D2 (garde de la clé), puis D3 et D4.

## Décision du propriétaire du 19/11/2026 : D2 (a), pour le PoC seulement (consignée à 15:28:58 UTC)

Question posée dans le cadre de fin de tour : « Pour D2, garder la clé OpenPGP en fichier sur l'hôte d'administration, hors cluster ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus, recopiée telle quelle :

> Brique 09, D2 : garde de la clé OpenPGP (décision pour le PoC seulement)
>
> Pour le PoC, la clé OpenPGP des rpm, des deb et des dépôts est un fichier de clé (0600)
> sur l'hôte d'administration, hors du cluster, comme la clé des tâches de J6. Le cluster
> ne voit jamais la clé privée. OpenBao sert seulement à l'attestation de lien (clé Transit
> « lien », D3), parce que Transit ne fait pas d'OpenPGP.
>
> Ce choix ne vaut que pour le PoC. Il n'est pas acceptable en production :
> - la clé est copiable : root sur l'hôte ou une sauvegarde suffit pour la récupérer ;
> - l'hôte d'administration porte déjà d'autres secrets (clé des tâches, accès au cluster) ;
> - aucun journal de signature ne vit à l'abri du signataire, et il n'y a ni quorum
>   ni limite d'usage ;
> - c'est un écart avec le doc 02, qui place le service de signature dans la zone Confiance.
>
> Pour la production, une vraie solution reste à trouver. Elle doit garder la clé dans un
> matériel dont elle ne sort pas, et passer par un service de signature isolé et journalisé.
> Aucune voie actuelle n'est à la fois maintenue et compatible avec notre chaîne :
> - un jeton matériel OpenPGP (YubiKey, Nitrokey) sur un hôte dédié marche avec gpg et
>   rpmsign, mais il n'a pas été mesuré ;
> - un HSM réseau en PKCS#11 n'a aucun pont maintenu vers gpg ;
> - les services tout faits (sigul, debusine) sont écartés aujourd'hui.
>
> Cet écart et cette recherche sont à écrire dans l'ADR 0003, et à reprendre avant toute
> mise en production.

Conséquences pour le protocole :
- **D2 (a) retenue pour le PoC** : clé OpenPGP en fichier 0600 sur l'hôte d'administration, hors du cluster. D2 (b) et D2 (c) ne sont pas retenues pour le PoC.
- **D3 est orientée par cette réponse** : elle nomme la clé Transit « lien » pour l'attestation de lien. La question D3 reste à confirmer, pour l'émetteur et pour la vérification de la provenance de Chains avant signature.
- **Écart de production** à écrire dans l'ADR 0003 (texte proposé dans [`A-REPORTER.md`](A-REPORTER.md), §4). Il est à reprendre avant toute mise en production.
- Le jeton matériel OpenPGP reste **non mesuré** ; aucune mesure n'est prévue dans cette brique.
- **Rien n'est lancé.** Question suivante : D3, puis D4.

## Décision du propriétaire du 19/11/2026 : D3 (a) (consignée à 15:31:50 UTC)

Question posée dans le cadre de fin de tour : « Pour D3, le service de signature vérifie la provenance de Chains, puis signe le lien avec Transit « lien » ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus : « Oui, option (a) ».

- **D3 (a) retenue.** Le service de signature tourne sur l'hôte d'administration (D2). Il travaille en trois temps :
  1. il vérifie la provenance de Chains sur le manifeste non signé (`07b7bd6f…` pour le rpm, `60f25f5c…` pour le deb), avant toute signature, comme le job TSA de J6 ;
  2. il émet un énoncé in-toto. Sujet : l'artefact signé. Prédicat : manifeste et fichier non signés, empreinte de la clé OpenPGP, versions des outils, résultat du contrôle de B1 ;
  3. il signe cet énoncé par cosign avec une clé Transit **`lien`** d'OpenBao, distincte des clés de provenance, `tsa` et des tâches.
- **D3 (b)**, énoncé signé par la clé OpenPGP, est écartée.
- **Coûts déjà écrits, désormais engagés** : l'hôte d'administration détiendra un jeton OpenBao borné à la clé `lien` et un accès en lecture à Zot. Création de la clé `lien`, du jeton et de sa politique : **accord à demander** avant O5 (liste « Accords », point 2).
- La forme exacte du prédicat (type, champs) sera écrite avec les prédictions d'O5.
- **Rien n'est lancé.** Question suivante : D4 (version de GnuPG).

## Décision du propriétaire du 19/11/2026 : D4 (a) (consignée à 15:35:24 UTC)

Question posée dans le cadre de fin de tour : « Pour D4, signer avec le GnuPG des distributions (2.3.3 Rocky, 2.4.7 Debian) ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus : « Oui, option (a) ».

- **D4 (a) retenue** : la signature passe par les paquets des distributions.
  - rpm : `gnupg2` 2.3.3-5.el9_7 de Rocky 9.8, imposé par `rpm-sign-libs` (`/usr/bin/gpg2`).
  - deb : `gnupg` 2.4.7-21+deb13u1 et `gpgv` 2.4.7-21+deb13u1+b5 de Debian 13.
  - Versions relevées le 19/11/2026 ; l'épinglage d'O2 suivra la source figée décidée pour la brique 05.
- **D4 (b)**, GnuPG 2.5.24 construit depuis l'archive amont, est écartée.
- **À suivre** : branches amont hors maintenance (2.4 depuis le 30/06/2026, 2.3 absente du tableau de fin de vie) ; les 4 failles ouvertes sans DSA de Debian 13 sont à relever à chaque ré-audit. Les vérifications se font sur `Release` + `Release.gpg`, ou sur le texte sorti de la vérification, jamais sur un `InRelease` brut (CVE-2025-68972).
- **D1 à D4 sont décidées.** Selon D2, l'outillage de signature tourne sur l'hôte d'administration. Les « images de signature » du jalon O2 sont donc à relire : il faut un **environnement de signature** Rocky 9.8 et un Debian 13 qui tournent sur l'hôte, par exemple des conteneurs podman (podman est présent sur l'hôte). Leur forme n'est pas tranchée ici ; elle sera proposée, avec ses prédictions, avant O2.
- **Rien n'est lancé.** Prochaine étape : préparer O2 à sec. Elle demande les accords de la liste « Accords » : clé OpenPGP du PoC, puis clé `lien`, jeton OpenBao et accès à Zot avant O5.

## Additif du 19/11/2026, écrit à 16:04:07 UTC : O2 préparé à sec ; `construire`, `cle` et `essai` NON LANCÉES

Préparation demandée par le propriétaire (« Oui, prépare O2 »). Décision prise en route : « racines (a) », pour le PoC (« Oui, option (a) »). Détail : [carte d'O2](resultats/o2-carte.md), [prédictions et résultats](resultats/o2-predictions.md).

- **Relevé préalable** ([journal](resultats/o2-releve.log), [manuel de mmdebstrap](resultats/o2-releve-2.log)) : les versions de D4 sont confirmées dans les deux sources figées, l'instantané Debian `20261105T000000Z` et `vault/rocky/9.8` (dont les `repomd` sont égaux à ceux de pub). Les deux amorces sont dans le cache local de la 05.
- **Version de gpg de l'amorce Rocky** : `gnupg2-2.3.3-5.el9_7`, mesurée par la session principale (`9b0f5e9f`), vérifiée ici. C'est la seule révision de Rocky 9.8.
- **Décision « racines (a) »** : chaque amorce ne sert qu'une fois, pour produire une racine neuve depuis les dépôts signés. Les racines produites par la plateforme deviennent la cible de production (ADR 0003).
- **Scripts** : [`o2.sh`](o2.sh) (`prealables`, `construire`, `cle`, `essai`), [`o2-interne.sh`](o2-interne.sh) (gestes sur la clé, gardes K1 à K4), [`o2-banc.sh`](o2-banc.sh). Mécanisme de la 05 : `unshare --map-auto --map-root-user` puis `chroot`, sans podman.
- **Mesuré à sec** : `prealables` (PA1 à PA6) et le banc des gardes, avec le gpg 2.4.8 de l'hôte et une clé jetable (BC1 à BC8), tous tenus. Un premier passage du banc, raté sur un défaut du script, est archivé.
- **Non mesuré** :
  - l'import entre gpg 2.4.7 et 2.3.3 (K5, K5b) ;
  - `mmdebstrap --mode=root` dans un espace de noms utilisateur de l'hôte (CR5, confiance faible) ;
  - toute installation de paquets.

**Accord nommé à demander avant de lancer** :
- **`construire`** : réseau vers `vault/rocky/9.8` et `snapshot.debian.org`, téléchargement et installation de paquets épinglés dans deux racines neuves sous `~/.cache/supply-chain-poc/09/o2` ;
- **`cle`** : clé du PoC (RSA 4096, v4, 1 an, **sans phrase de passe**, compromis à écrire dans l'ADR 0003), dans `~/.cache/supply-chain-poc/09/secrets` (0700 ; clé privée, clé publique et certificat de révocation en 0600) ; **clé publique dans le dépôt ou non**, à décider ;
- **`essai`** : sans réseau, avec la clé du PoC.

## Correction datée du 19/11/2026, écrite à 16:15:45 UTC : O2 restructuré, banc dans la racine Rocky passé

- **Écart corrigé** (relu par le conseiller) : la version d'`o2.sh` décrite dans l'additif précédent ne suivait pas l'option (a) approuvée. Elle installait Rocky en ligne en une seule passe, sans contrôle des rpm contre le `primary` vérifié, et son étape `construire` était tout ou rien. Rien n'en avait été lancé, hormis `prealables`. Détail : [prédictions](resultats/o2-predictions.md), correction de 16:13:44 UTC.
- **Nouvelles étapes**, chacune avec son accord : `rocky_telecharger`, `rocky_installer` (hors ligne), `debian_amorce`, `debian_racine`, `cle`, `essai`. Les replis de mmdebstrap, les échecs et l'effacement sont dans la [carte](resultats/o2-carte.md).
- **`banc_chroot` passé à sec** (16:14:50 à 16:14:55 UTC, BK0 à BK5 tenues, [journal](resultats/o2-banc_chroot.log)). Il a tourné dans l'amorce Rocky du cache local, sans réseau ni installation, avec des clés jetables. Il mesure la mécanique de `cle` et `essai` sous gpg 2.3.3, et l'import dans 2.3.3 d'une clé créée par 2.4.8. gpg 2.4.7 n'est pas mesuré.
- **Accord à demander maintenant** : celui de la première étape seulement, `rocky_telecharger`. Il ouvre le réseau vers `vault/rocky/9.8` et télécharge les rpm de la racine Rocky dans `~/.cache/supply-chain-poc/09/o2/rocky`, avant tout contrôle contre le `primary` vérifié. Rien n'est installé à cette étape.

## Additif du 19/11/2026, écrit à 17:09:54 UTC : racines d'O2 prêtes ; garde locale contre une clé privée (« Garde locale d'abord »)

- **Racines prêtes** : les quatre étapes de construction ont passé, avec leurs accords. Résultats et notes datées dans les [prédictions d'O2](resultats/o2-predictions.md). Racine Rocky : 101 rpm conformes au `primary` vérifié, gpg 2.3.3. Racine Debian : 106 `.deb` sur 106 conformes au `Packages.xz` vérifié, gpg 2.4.7, après la relance avec `--skip=essential/unlink`. Aucune clé du PoC n'existe.
- **Constat avant `cle`** : `tools/secrets-depot.sh` ne connaît pas `09/secrets`, ni sur cette branche ni sur la branche principale. Chaque arbre de travail lance sa propre copie du script. Le second ajout du §4 quater d'`A-REPORTER.md` aurait bloqué la brique elle-même : correction datée de 16:48:49 UTC, commit `cb9b91da`.
- **Décision du propriétaire** : « Garde locale d'abord ». `garde-cle-privee.sh` refuse l'en-tête de clé privée seul sur sa ligne, dans l'index et dans l'arbre de travail. Elle n'affiche que des noms de fichiers.
- **Banc** : `garde-banc.sh`, avec une clé jetable sur tmpfs dans une copie de la branche. Passé de 17:09:24 à 17:09:27 UTC, GB0 à GB12 tenues ([prédictions et résultat](resultats/garde-predictions.md), [journal](resultats/garde-banc.log)).
- **Limites** : un export binaire, une clé sans en-tête et un fichier ignoré ne sont pas vus.
- **Routine de commit de la branche, désormais** : `mise exec -- make reuse`, `tools/secrets-depot.sh`, puis `poc/bricks/09-openpgp-signing/garde-cle-privee.sh`.
- **Prochaine question au propriétaire** : l'accord de `cle`, qui porte sur la phrase de passe et sur la clé publique dans le dépôt ou non.

*Note datée du 19/11/2026, 17:13:47 UTC* : la [répétition de `cle` et `essai`](resultats/o2-predictions.md) avec une clé jetable est passée sous gpg 2.4.7 et 2.3.3 (K5 et K5b mesurées sur une clé de même forme). La garde locale a une limite de plus : `revocation.asc` porte un en-tête public précédé de deux-points, qu'elle ne voit pas.

## Décision du propriétaire du 19/11/2026 : « Sans phrase de passe » (consignée à 17:18:33 UTC)

La clé OpenPGP du PoC est créée **sans phrase de passe**, pour le PoC seulement. Le compromis est déjà rédigé pour l'ADR 0003, au §4 ter d'`A-REPORTER.md` : une sauvegarde de l'hôte emporte une clé utilisable. Une phrase gardée hors de l'hôte couvrirait ce cas, mais chaque signature la demanderait, et root sur l'hôte la lirait quand même pendant une signature. Paramètres de l'étape `cle`, tels que préparés et répétés : RSA 4096, v4, 1 an, dans `~/.cache/supply-chain-poc/09/secrets` (0700, fichiers en 0600), créée sous gpg 2.4.7 dans la racine Debian, sans réseau. La présence de la clé publique dans le dépôt reste une question à part, posée plus tard. Après `cle`, aucune session ne lit ni ne liste `09/secrets` ; seuls les scripts d'O2 y accèdent. `tools/secrets-depot.sh` ne connaît pas encore ce dossier. La garde locale couvre la clé privée, mais pas `revocation.asc` (répétition, RP3c).

*Note datée du 19/11/2026, 17:58:04 UTC* : **O3 tenu.** Le rpm est signé avec la clé du PoC dans la racine Rocky. B1 est mesurée par comparaison d'octets : en-tête principal et charge utile inchangés, même taille. rpmkeys et dnf l'acceptent dans une amorce Rocky 9.8 neuve, avec `gpgcheck=1` et `repo_gpgcheck=1`. Les trois témoins sont refusés avec un motif de signature. `rpmsign --delsign` ne rend pas le rpm d'origine. Détail : [prédictions et notes d'O3](resultats/o3-predictions.md). Écart à reprendre dans le rapport : l'amorce Rocky `ed654c69…` sert une seconde fois, comme vérificateur, sans clé privée.

*Note datée du 19/11/2026, 18:30:22 UTC* : **O4 préparé, prédictions écrites avant tout lancement** ([prédictions](resultats/o4-predictions.md)). Scripts [`o4.sh`](o4.sh) et [`o4-interne.sh`](o4-interne.sh), même mécanisme qu'O3 (espace de noms sans réseau, chroot). Le dépôt apt est signé dans la racine Debian 13 (gpg 2.4.7, apt-ftparchive 3.0.3), sans modifier le deb (D1 a). apt 3.0.3 le vérifie dans une amorce Debian 13 extraite à neuf, avec `Signed-By`. Le vérificateur choisi par apt est relevé deux fois : dans la racine Debian, où sqv et gpgv sont présents tous les deux, et dans l'amorce, où gpgv est absent. `o4.sh signer` lie `09/secrets` en lecture seule dans la racine Debian, comme `o3.sh` dans la racine Rocky ; la session ne lit ni ne liste ce dossier. L'image de l'amorce `7378260c…` a déjà servi en O2 : même écart qu'en O3, consigné dans les prédictions.

*Note datée du 19/11/2026, 18:37:40 UTC* : **O4 tenu** ([prédictions et résultats](resultats/o4-predictions.md)). Le dépôt apt est signé avec la clé du PoC dans la racine Debian 13 : `InRelease` et `Release.gpg` armuré, SHA-512, deb inchangé (`f66bbeb2…`). apt l'accepte avec `Signed-By`, en 3.0.3 dans la racine et en 3.0.4 dans une amorce Debian 13 neuve. Les sept témoins sont refusés avec leur motif. Les deb téléchargés sont égaux à `f66bbeb2…`. **apt vérifie par sqv, même quand gpgv est installé** (prédiction 5 tenue). **apt refuse une signature SHA-1 de `Release`**, ce qui tranche la correction datée 1 ci-dessus. **apt refuse un `Release.gpg` binaire** : le banc O0 en produisait un, que gpgv acceptait. Une première `repetition`, à 18:30:34 UTC, a échoué sur ce point et sur un défaut de garde du script. Les deux sont consignés en notes datées avant la relance. Reste O5, l'attestation de lien, qui demande des accords.

*Correction datée du 19/11/2026, 18:41:53 UTC* : **CVE-2025-68972 et vérificateur d'apt.** Le tableau du relevé (ligne GnuPG de Debian 13) et la note de D4 rattachent la faille à « la forme `InRelease` vérifiée par gpgv ». O4 mesure qu'apt de Debian 13 (3.0.3 et 3.0.4) vérifie `InRelease` et `Release.gpg` par **sqv**, même avec gpgv installé ([prédictions d'O4](resultats/o4-predictions.md)). Ce qui est établi s'arrête là : le chemin de vérification d'apt n'est pas gpgv. Si la faille touche ou non sqv n'est pas lu ; aucune recommandation sur `InRelease` n'en est tirée. Reste mesuré qu'apt accepte un dépôt sans `InRelease` dont le `Release.gpg` est armuré.

*Note datée du 19/11/2026, 18:56:05 UTC* : **O5 : banc hôte à sec tenu, O5 réel non commencé** ([prédictions et résultats](resultats/o5-predictions.md)).
- **Outils** : [`o5.sh`](o5.sh) et [`o5-lien.py`](o5-lien.py) ; cosign 3.1.4, dont le sha256 est égal à `mise.lock`, dans un espace de noms sans réseau, avec deux clés cosign jetables.
- **Énoncés** : quatre énoncés in-toto (`Statement/v0.1`), de prédicat `https://supply-chain.example/lien-openpgp/v1`, couvrent le rpm signé, le deb, `repomd.xml` et `InRelease`. Ils sont vérifiés par cosign, puis par un contrôle indépendant qui relit les valeurs archivées, recalcule B1 sans rpm et refait les chaînes des deux dépôts.
- **Refus du protocole** : clé étrangère, refusée par cosign ; lien vers un autre digest et rpm à charge altérée, acceptés par cosign et refusés par le contrôle. **Les deux vérifications sont donc nécessaires.**
- **Premier passage** : code 1 (18:54:24 UTC). Mon contrôle exigeait `Statement/v1`. Une note datée a été commitée avant la relance.
- **Reste pour O5 réel**, avec les accords : clé Transit `lien` (cosign `hashivault://`), jeton OpenBao, accès à Zot (referrer, provenance de Chains du manifeste non signé). Il faut aussi relire le fichier `--signing-config`, car cosign déclare dépréciés les drapeaux hors ligne employés ici.

*Correction datée du 19/11/2026, 18:58:46 UTC* : dans la note précédente, « les deux vérifications sont donc nécessaires » est trop fort.
- **Mesuré** : le contrôle indépendant est nécessaire, puisque T2 et T3 passent chez cosign.
- **Par construction seulement** : cosign est nécessaire. Le contrôle ne lit pas la signature, mais il n'a pas tourné sur le bundle de la clé étrangère.
- **Relu, pas recalculé** : le lien manifeste ↔ fichier vient des journaux archivés des briques 05 et 06 ; aucune couche OCI n'est lue.

Voir la [correction datée](resultats/o5-predictions.md) des prédictions d'O5.

*Note datée du 19/11/2026, 19:39:00 UTC* : **O5 réel, premier accord (« Oui ») : clé Transit `lien` créée dans OpenBao** ([prédictions et résultats](resultats/o5-openbao-predictions.md)).
- **Création** : script [`o5-openbao.sh`](o5-openbao.sh), éprouvé d'abord sur un banc hors cluster (15 OK). La clé est `ecdsa-p256`, non exportable, sans sauvegarde en clair, non supprimable, version 1.
- **Clé publique** : [`resultats/lien-cle-publique.pem`](resultats/lien-cle-publique.pem), SPKI sha256 `42529342…`.
- **Rien d'autre n'a changé** : les clés `chains`, `scanner` et `tsa` sont inchangées.
- **Ce qui manque encore** : aucune politique ni aucun jeton ne permet de signer avec `lien`. Ce sont les deuxième et troisième accords : jeton OpenBao borné, puis lecture de Zot.

*Note datée du 19/11/2026, 19:50:00 UTC* : **O5 réel, deuxième accord (« Oui ») : accès borné à la clé `lien` créé** ([prédictions et résultats](resultats/o5-openbao-predictions.md)).
- **Politique** [`lien-signature`](politique/lien-signature.hcl) : lecture de la clé `lien`, signature, révocation de soi.
- **Jeton** : un jeton de service avec cette seule politique, sans `default`, orphelin, 72 h non renouvelables. Il expire au plus tard le 22/11/2026 à 19:49:36 UTC. Le script l'a écrit dans `09/secrets` ; sa valeur n'est jamais affichée.
- **Essais sur le vrai OpenBao** : avec ce jeton, lecture et signature `lien` acceptées, et la signature est vérifiée par OpenSSL avec la clé publique archivée. Les neuf autres essais sont refusés en 403 : autres clés, export, kv, politiques, jeton enfant, consultation de soi.
- **Mes choix**, à contester si besoin : durée, révocation de soi (non essayée), fichier en clair.
- **Reste pour O5 réel** : lecture de Zot (troisième accord) ; route de l'hôte vers OpenBao pour cosign `hashivault://` ; attestations réelles et referrers.

*Note datée du 19/11/2026, 19:58:28 UTC* : **O5 réel, troisième accord (« Oui, prépare-le ») : Zot lu en anonyme, sans aucune écriture** ([prédictions et résultats](resultats/o5-zot-predictions.md)). Script : [`o5-zot.sh`](o5-zot.sh) ; contrôle hors réseau : [`o5-zot-controle.py`](o5-zot-controle.py), banc 14 OK.
- **Lien manifeste → fichier recalculé.** Les manifestes non signés `07b7bd6f…` (rpm) et `60f25f5c…` (deb), tirés par digest, contiennent chacun une seule couche et un seul fichier : `864d55f4…` et `f66bbeb2…`.
- **Provenance de Chains vérifiée** par cosign avec la clé publique archivée : 4 enveloppes SLSA v1 côté rpm, 8 côté deb, chacune avec ce manifeste pour seul sujet. Avec une clé jetable, la vérification est refusée.
- **Reste pour O5 réel :**
  - les écritures dans Zot (rpm signé, dépôts signés, attestations de lien en referrers), point 4 de la liste « Accords » ;
  - la route de l'hôte vers OpenBao, pour que cosign signe par `hashivault://lien` ;
  - les jetons d'horodatage, non vérifiés ici.

*Note datée du 19/11/2026, 20:15:12 UTC* : **O5 réel, accord « Ok » : cosign signe avec la clé Transit `lien`** ([prédictions et résultats](resultats/o5-cosign-predictions.md)).
- **Route** : redirection de port sur `127.0.0.1` vers `openbao-0`, fermée à la fin de chaque étape.
- **Lecture** : `cosign public-key --key hashivault://lien` rend la clé archivée.
- **Signature** : un énoncé d'essai signé par `hashivault://lien` est vérifié hors réseau avec la clé archivée, et le témoin est refusé.
- **Mode banc** : le banc a révélé un défaut du script, une clé publique mal choisie en mode banc. Il est corrigé avant le vrai passage.
- **Décision « Oui, signes/** »** ; `compte_zot` est passée.
- **Reste pour O5** : application par la session principale (§4 quinquies d'`A-REPORTER.md`, redémarrage de Zot), `droits_zot`, publication et attestations réelles.

*Note datée du 19/11/2026, 20:47:51 UTC* : **O5 réel : publication dans `signes/**` et attestations de lien préparées à sec** ([prédictions](resultats/o5-signes-predictions.md)).
- **Script** [`o5-signes.sh`](o5-signes.sh), contrôle [`o5-signes.py`](o5-signes.py). Étapes : `construire` (hors réseau), `essai_attest` (clé jetable, `signes/essai-09-*`), `publier`, `attester` (clé `lien`), `verifier` (anonyme).
- **Banc** hors cluster ([o5-signes-banc.sh](o5-signes-banc.sh)) : 28 OK, 0 KO. Il simule Zot et OpenBao et ne prouve pas la vraie poussée de `cosign attest` sous `poc-lien` : `essai_attest` la mesure avant toute signature par `lien`.
- **Garde horaire** : aucune écriture dans Zot entre 23:30 et 08:00 UTC (mesure de M1b).

*Note datée du 19/11/2026, 20:50:43 UTC* : **O5 réel tenu** ([prédictions et résultats](resultats/o5-signes-predictions.md)).
- **Publié par `poc-lien`** dans `signes/**`, par digest, sans tag : le rpm signé, la copie du manifeste deb, les dépôts rpm et apt signés.
- **Attestations.** Chaque objet porte une attestation de lien, signée par `cosign attest --key hashivault://lien`.
- **Vérification.** En anonyme, cosign vérifie avec la clé archivée, puis le contrôle indépendant recalcule sur les octets tirés de Zot : B1 pour le rpm, l'identité du deb, la chaîne de chaque dépôt.
- **Témoins.** La clé jetable est refusée. Les témoins faux, dans `signes/essai-09-*`, sont refusés par le contrôle.
- **Réserves** : jetons d'horodatage non vérifiés ; porte et Kyverno (O6) non faits.

*Note datée du 19/11/2026, 21:10:59 UTC* : **O6 chiffré à sec** ([carte](resultats/o6-carte.md)).
- **Voies** :
  - **P**, contrôle du lien par la porte : 1 j pour les paquets, + 0,5 j pour les dépôts, + 1 j pour l'horodatage ;
  - **T**, tâche signée : au moins 3 j, contraire à D2 (a) ;
  - **N**, pas d'O6.
  - Ces estimations ne sont pas mesurées.
- **Mesure O6-M0** ([résultat](resultats/o6-porte-banc-predictions.md)) : la porte de la 08 telle quelle refuse les objets de `signes/**`. ec vérifie l'attestation de lien avec la clé `lien`.
- **En attente** : décision du propriétaire.

*Correction datée du 19/11/2026, 21:13:46 UTC (O6)* : la note précédente, et celles d'O5 qui disent « porte et Kyverno (O6) », vont trop loin.
- **Kyverno.** Les deux fichiers de politiques Kyverno du dépôt (08 `admission.yaml`, 08c `durcissement.yaml`) ne visent que des pods et des objets Tekton : aucune règle ne vise un rpm, un deb ou un dépôt. O6 ne touche que la porte.
- **Rpm.** La porte n'a jamais rendu de verdict archivé sur le rpm `builds/sample-app-rpm@07b7bd6f…` (réserve « Porte sans tâche rpm » de la 05). P1 est rechiffré en **P1-deb** (1 j, estimation) et **P1-rpm**, qui attend l'extension de la porte à la voie rpm, hors de la 09.
- **Question au propriétaire** : P1-deb ou N ([carte](resultats/o6-carte.md), correction datée).

*Note datée du 19/11/2026, 21:15:33 UTC (O6)* : le lien du deb relie la copie `signes/sample-app-deb` à son propre digest. La signature OpenPGP du deb est celle du dépôt apt. P1-deb seul n'a donc pas de substance, et la question devient **N (recommandé), ou la voie deb : P1-deb + P2-apt, 1,5 j estimé** ([carte](resultats/o6-carte.md), dernière note). Le secret `lien` ne sert à aucune des deux.

*Décision datée du 19/11/2026, consignée à 21:26:03 UTC (O6)* :
- **Réponse du propriétaire.** Elle est relayée par la session principale. Il a répondu « Oui » à « Elle recommande N, pas d'O6. L'alternative est la voie deb (P1-deb + P2-apt), estimée à 1,5 j. ».
- **Lecture.** Je lis ce « Oui » comme **N : pas d'O6 dans la 09**. Si ce n'est pas ce que le propriétaire voulait dire, une note datée corrigera cette lecture.
- **Réserve qui reste.** La porte ne juge pas l'attestation de lien.
- **Secret `lien`.** Il ne sert plus à rien et expire seul le 22/11/2026.
- **Clôture de la brique.** Elle revient au propriétaire ([carte](resultats/o6-carte.md), dernière note).
