# Brique 09, O3 : prédictions (rpm signé, dépôt rpm signé)

Écrites le 19/11/2026 à 17:53:09 UTC, avant tout lancement de `repetition` ou de `signer`. `prealables` est une lecture locale, passée de 17:52:34 à 17:52:34 UTC, code 0 ([journal](o3-prealables.log)). Elle donne :
- la copie locale du rpm est égale à `864d55f4…` (2 173 376 octets) ;
- la racine Rocky a `rpmsign`, `createrepo_c` et `gpg2`, mais ni `dnf` ni `python3` ;
- l'amorce Rocky 9.8 est dans le cache local ;
- `%_pkgverify_level digest` ;
- le rpm ne dépend que de `rpmlib(…)`.

**Méthode.** Le rpm est signé dans la racine Rocky : gpg 2.3.3, rpm-sign 4.16.1.3, clé importée dans un GNUPGHOME sur tmpfs, sans réseau. La vérification se fait dans une **amorce Rocky 9.8 neuve** (`ed654c69…`), extraite après contrôle par sha256 : c'est le « Rocky 9.8 vierge » du protocole, faute de `dnf` dans la racine de signature. Tout tourne sans réseau. `repetition` fait tourner la même chaîne avec une clé jetable, puis tout est effacé. `signer` utilise la clé du PoC, et le dépôt signé reste pour O5.

| N° | Prédiction (vaut pour `repetition` et pour `signer`) | Confiance |
|---|---|---|
| S1 | `rpmsign --addsign` (gpg2 lancé par rpm sans `--batch`, clé sans phrase de passe, SHA-512) : code 0 | moyenne : jamais mesuré ; gpg sans terminal |
| S2a | Le rpm signé porte `RSAHEADER` = RSA/SHA512 avec l'identifiant de la clé (16 derniers chiffres de l'empreinte) ; le rpm d'entrée n'en a pas | haute |
| S2b | `SIGPGP` (signature de l'en-tête et de la charge utile) reste absent : rpm 4.16 ne pose qu'une signature d'en-tête par défaut | moyenne : non lu dans le code |
| S2c | `SHA256HEADER` et `PAYLOADDIGEST` sont égaux entre l'entrée et le rpm signé | haute |
| B1 | Octets égaux à partir de l'en-tête principal (prédiction 1 du README) ; les 96 octets du lead sont égaux | moyenne-haute |
| S3 | `rpmsign --delsign` redonne exactement `864d55f4…` (prédiction 2 du README) | faible |
| S4, S5 | `createrepo_c` et la signature détachée armurée de `repomd.xml` : code 0 | haute |
| V1 | `rpmkeys --checksig` sur le rpm signé, sans la clé : NOKEY, code non nul | moyenne : code de NOKEY non lu |
| V2, V3 | Import de la clé publique, puis `rpmkeys --checksig` : signature V4 RSA/SHA512 OK, code 0 (prédiction 3 du README, côté rpm) | haute |
| V4 | rpm altéré d'un octet dans la charge utile : refusé, code non nul | haute |
| V5 | rpm d'origine non signé : code 0 (empreintes seules ; `-K` n'exige pas de signature). Code relevé, sans refus prédit | moyenne |
| V6 | dnf avec `gpgcheck=1` et `repo_gpgcheck=1` refuse les trois témoins : `repomd.xml` signé par une autre clé, `repomd.xml` modifié après signature, rpm non signé dans un dépôt signé. `sample-app` n'est installé après aucun d'eux | haute pour les deux premiers ; moyenne-haute pour le troisième |
| V7 | dnf installe `sample-app` depuis le dépôt signé : la clé de `gpgkey` est importée par `-y`, sans terminal ; code 0 ; le paquet installé porte `RSAHEADER` | moyenne-haute |
| K3 | Aucune ligne de bloc OpenPGP armuré dans le journal ; aucune ligne KO ; code final 0 | haute |

Le rpm signé n'est pas reproductible d'une signature à l'autre, car la signature porte sa date : la `repetition` et `signer` donneront deux sha256 différents. B1 compare toujours au même `864d55f4…`.

## Correction datée du 19/11/2026, 17:57:06 UTC, avant tout lancement, après relecture du conseiller

- **Refus jugés sur le motif, pas sur le code seul** : `o3-interne.sh` est corrigé. Un refus attendu (V4, V6) n'est compté OK que si la sortie porte un motif de signature. Le motif cherché, sans tenir compte de la casse, est `gpg|signature|signed|nokey|digest`, et la dernière ligne qui le porte est citée. Un code non nul sans motif donne KO (« refus sans motif de signature »). Sans cette correction, un `dnf-3` absent ou une erreur de cache auraient passé pour des refus.
- **V1 révisée** : seule la mention NOKEY est jugée, et le code est relevé. La prédiction sur le code est abandonnée : elle était de confiance moyenne, et un code 0 aurait compté KO sans défaut de la chaîne.
- **Amorce réutilisée** : le vérificateur est l'amorce Rocky 9.8 `ed654c69…`, que `rocky_telecharger` a déjà utilisée en O2. Le texte proposé pour l'ADR (§4 ter d'`A-REPORTER.md`) dit que chaque amorce ne sert qu'une fois. Ici, elle sert à vérifier, sans aucune clé privée. Son rpm et son dnf viennent de l'image amont, contrôlée seulement par le sha256 de sa couche, pas par le `primary` vérifié. Un vérificateur contrôlé avec dnf demanderait le réseau, que K1 refuse tant que la clé existe sur l'hôte. Cet écart ira dans le rapport final.
- **Installation** : rien n'est installé sur l'hôte. V7 installe `sample-app` par dnf **dans l'amorce de vérification**, qui est jetée ensuite.

## Note datée du 19/11/2026, 17:57:34 UTC : `repetition` passée, toutes les prédictions tenues sauf S3

Passée de 17:57:11 à 17:57:15 UTC, code 0 ([journal](o3-repetition.log)), avec une clé jetable `DDB39800…F32C3F99` (RSA 4096, créée par gpg 2.3.3). `o3-interne.sh` est celui de la correction (`326e3a9d…`).
- **S1 tenue** : code 0. rpm avertit « Could not set GPG_TTY to stdin », sans effet.
- **S2a, S2b et S2c tenues** : le rpm signé porte `RSAHEADER=RSA/SHA512`, avec la clé `5dc95deff32c3f99` ; `SIGPGP` reste `(none)` ; `SHA256HEADER` (`7d4d47e7…`) et `PAYLOADDIGEST` (`7042078a…`) sont égaux à ceux de l'entrée.
- **B1 tenue** : à partir de l'en-tête principal, les octets sont égaux, et le lead aussi. Le rpm signé a la même taille que l'entrée (2 173 376 octets). L'en-tête de signature passe de 7 à 8 entrées, mais l'en-tête principal reste à l'octet 4504 : le remplissage réservé de l'en-tête de signature absorbe la signature.
- **S3 non tenue** (confiance faible) : `rpmsign --delsign` donne `259b69b9…`, pas `864d55f4…`. Retirer la signature ne rend pas le fichier d'origine. Le second contrôle de B1 par `--delsign` est donc écarté ; B1 repose sur la comparaison d'octets.
- **S4 et S5 tenues** : code 0.
- **V1 tenue** : « Header V4 RSA/SHA512 Signature, key ID f32c3f99: NOKEY », code 1 relevé.
- **V2 et V3 tenues** : la signature est « OK » après import.
- **V4 tenue** : le rpm altéré d'un octet est refusé, code 1. « Payload SHA256 digest: BAD » ; la signature d'en-tête reste OK, puisque seule la charge utile change.
- **V5 tenue** : le rpm non signé passe `-K` avec le code 0, empreintes seules.
- **V6 tenue** pour les trois témoins, chacun avec le code 1, et `sample-app` n'est jamais installé :
  - autre clé : « repomd.xml GPG signature verification error: Bad GPG signature » ;
  - `repomd.xml` modifié : même message ;
  - rpm non signé : « Package sample-app-1.0.0-2.el9.x86_64.rpm is not signed » puis « Error: GPG check FAILED ».
- **V7 tenue** : dnf importe la clé de `gpgkey` avec `-y`, sans terminal, puis installe `sample-app`, code 0. Le paquet installé porte `RSAHEADER`.
- **K3 tenue**.

Les dossiers `o3/repetition`, `o3/repetition-secrets` et `o3/repetition-vierge` sont effacés après le commit de cette note. Suite : `signer` avec la clé du PoC, mêmes prédictions, sauf S3 désormais attendue non tenue.

## Note datée du 19/11/2026, 17:58:04 UTC : `signer` passée avec la clé du PoC, mêmes résultats que la répétition ; O3 terminé

Passée de 17:57:42 à 17:57:45 UTC, code 0 ([journal](o3-signer.log)), mêmes scripts que la répétition. Les résultats sont identiques à ceux de la `repetition`, avec la clé du PoC `29BA1C48…BCF03A86` (identifiant rpm `c0658591bcf03a86`). S1, S2a à S2c, B1, S4, S5, V1 à V7 et K3 sont tenues ; S3 n'est pas tenue, comme attendu : `--delsign` donne `259b69b9…`, la même valeur que dans la répétition.

**Produits gardés pour O5**, dans `~/.cache/supply-chain-poc/09/o3/signer/` (hors du dépôt) :
- rpm signé `depot/sample-app-1.0.0-2.el9.x86_64.rpm` : sha256 `9f71d578d3b13bc5c4a996a9cbacf60d1d5083d744ef2313054764fd9925567b`, 2 173 376 octets ;
- `repomd.xml` : `f1d1bc09…` ;
- `repomd.xml.asc` : `ce0f600e…` ;
- clé publique exportée.

Aucun fichier de ce dossier ne porte d'en-tête de clé privée. Compte fait sur l'hôte à l'écriture de cette note : 0 fichier. L'amorce de vérification `o3/signer-vierge` sera effacée après le commit.

**Jalon O3 tenu** (critère du README : rpm signé vérifié ; en-tête principal et charge utile inchangés ; dépôt accepté, témoins refusés). Prédictions du README : la 1 est tenue (B1) ; la 2 n'est pas tenue (`--delsign`) ; la 3 est tenue côté rpm (RSA 4096 v4 accepté par `rpmkeys` et dnf de Rocky 9.8), et reste à mesurer côté apt en O4.
