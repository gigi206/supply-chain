# Brique 09, banc O0 (dépôt apt signé sur l'hôte) : prédictions

Écrites le 19/11/2026 à partir de 14:57:27 UTC (`date -u`), **avant tout lancement** de [`banc-depot-deb.sh`](../banc-depot-deb.sh). Rien installé ; outils déjà présents sur l'hôte.

Portée : ce banc mesure la forme d'un dépôt apt signé par gpg 2.4.8 et vérifié par gpgv 2.4.8 (Ubuntu 26.04). Il ne mesure **ni** le gpg de Debian 13 (2.4.7) ni celui de Rocky 9.8 (2.3.3), **ni** le vérificateur réel d'apt de trixie (sqv ou gpgv, choix non lu), ni rpm, ni `createrepo_c`, ni `debsign`.

## Étape `prealables`

| # | Prédiction | Confiance |
|---|---|---|
| PR1 | Versions : gpg et gpgv 2.4.8 ; `apt-ftparchive`, `dpkg-deb` et python3 relevés, non prédits | haute pour gpg (relevé du 14:44 UTC) |
| PR2 | Outils absents : `rpm`, `rpmsign`, `rpmkeys`, `createrepo_c`, `debsign`, `sqv`, `sq`, `softhsm2-util`, `gnupg-pkcs11-scd` | haute : recensement fait à la main pendant l'orientation, journalisé ici pour la première fois |
| PR3 | Copie locale du deb égale à `f66bbeb2…` (attendu lu dans `s3-comparaison.log`) | haute : sha256 calculé à la main pendant l'orientation |
| PR4 | Copie rpm `banc-m4c-comparaison-copie/m3` égale à `864d55f4…` ; copie `banc-m3-2-1` différente (`1407b7ef…`), d'où la garde | haute : même raison |
| PR5 | `.changes` de S3 présent ; au moins une ligne porte le sha256 du deb | moyenne-haute : fichier vu dans le dossier, contenu jamais lu |

Code attendu : 0, 4 OK.

## Étape `banc`

| # | Prédiction | Confiance |
|---|---|---|
| BD1 | Garde tenue : copie égale au journal | haute |
| BD2 | Deux clés RSA 4096 créées en lot, sans invite, empreintes distinctes ; `pub algo 1 bits 4096`, usage de signature | haute |
| BD3 | `Packages` : une strophe `sample-app 1.0.0-2 amd64`, `Size 1953492`, `Filename pool/main/s/sample-app/sample-app_1.0.0-2_amd64.deb`, `SHA256 f66bbeb2…` | haute : `apt-ftparchive` lit le paquet sans le modifier |
| BD4 | `Release` liste `main/binary-amd64/Packages` et `Packages.gz` avec sha256 et tailles égales aux fichiers | haute |
| BD5 | Date de `Release` sous `SOURCE_DATE_EPOCH` ; deux sorties identiques ou non | **relevé, non prédit** |
| BD6 | `gpgv` vérifie `Release.gpg` sur `Release` : code 0, empreinte de la clé signataire dans la sortie | haute |
| BD7 | `gpgv --output` vérifie `InRelease` : code 0, et le texte sorti est égal à `Release` octet pour octet | moyenne-haute : aucune ligne de `Release` ne commence par un tiret ; fin de ligne finale non vérifiée |
| BD8 | Paquet de signature : version 4, algo 1 (RSA), digest algo 10 (SHA-512) | haute |
| BD9 | La chaîne tient aussi depuis le texte sorti de la vérification d'`InRelease` | haute : suit BD7 |
| BD10 | Témoins : N1 `Release` altéré et N2 `InRelease` altéré refusés par gpgv ; N3 clé étrangère refusée ; N4 `Packages` altéré et N5 deb altéré détectés par la chaîne | haute |
| BD11 | gpgv 2.4.8 **accepte** une signature SHA-1 (code 0), alors qu'apt de trixie la refuse depuis le 01/02/2026 d'après `default-sequoia.config` (non mesuré ici) | moyenne : gpgv n'a pas de politique de dates ; un avertissement possible n'est pas un refus |
| BD12 | Le deb du dépôt reste égal à `f66bbeb2…` à la fin | haute |

Code attendu : 0, 14 OK (BD1, BD2, BD3+BD4, BD6, BD7, BD8, BD9, cinq BD10, BD11, BD12). Durée : moins de 2 min (deux clés RSA 4096). Dossier neuf `~/.cache/supply-chain-poc/09/banc-depot-deb-<horodatage>`, à effacer après archivage du journal (aucun script ne le relit).
