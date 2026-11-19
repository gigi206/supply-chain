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

## Note datée du 19/11/2026, écrite à 14:59:10 UTC : banc passé, toutes les prédictions tenues

Lancé après le commit des prédictions (`96b7e6f7`). Journaux : [prealables](banc-depot-deb-prealables.log) (14:58:01 UTC, code 0, 4 OK, 0 ÉCART) et [banc](banc-depot-deb.log) (14:58:04 à 14:58:06 UTC, code 0, 14 OK, 0 ÉCART).

- **PR1 tenue** : gpg et gpgv 2.4.8 (`2.4.8-4ubuntu3.1`). Relevés : `apt-ftparchive` est celui d'**apt 3.2.1** d'Ubuntu (`3.2.1ubuntu0.1`), pas le 3.0.3 de trixie ; `dpkg-deb` 1.23.7 ; python3 3.15.2 par le shim de mise dans `~/.cache/supply-chain-poc/09`.
- **PR2 à PR5 tenues** : neuf outils absents ; copie du deb égale à `f66bbeb2…` ; copie rpm `m3` égale à `864d55f4…`, copie `banc-m3-2-1` à `1407b7ef…` ; `.changes` de S3 de 1 323 octets (`32796934…`), une ligne porte le sha256 du deb. Son contenu n'est pas affiché.
- **BD1 à BD4 et BD6 à BD12 tenues** : clés `F8BD3922…B167` (signataire) et `DB423EAF…CE5A` (témoin), RSA 4096, usage `scSC`, expiration au 21/11/2026 ; une strophe `sample-app 1.0.0-2 amd64`, `SHA256 f66bbeb2…` ; `Release.gpg` et `InRelease` vérifiés par gpgv, texte sorti d'`InRelease` égal à `Release` octet pour octet ; signature v4, RSA, SHA-512 ; N1 et N2 refusés (code 1), N3 refusé (code 2), N4 et N5 détectés par la chaîne ; **gpgv 2.4.8 accepte une signature SHA-1** (code 0, aucun avertissement dans le journal) ; deb inchangé à la fin.
- **BD5 (relevé, non prédit)** : `apt-ftparchive` 3.2.1 **ignore `SOURCE_DATE_EPOCH`** pour le champ `Date` (date de l'exécution, 14:58:06 UTC, au lieu du 17/11/2025). Les deux sorties sont identiques parce qu'elles tombent dans la même seconde. Un `Release` reproductible demande donc une date passée par option (non lu, à lire avant O4).
- **Hors portée, rappel** : ni gpg 2.4.7 ni 2.3.3, ni sqv, ni rpm ne sont mesurés. BD11 montre seulement que gpgv ne reflète pas la politique d'apt de trixie.
- Dossier du banc effacé à 14:58:16 UTC (clé jetable comprise), après archivage des journaux ; aucun script ne le relit. Le `gpg-agent` de son `--homedir` a été arrêté par le script (`gpgconf --homedir … --kill all`).

## Incident du 19/11/2026, vers 14:58:29 UTC (après le banc, hors du script)

La première écriture de la note ci-dessus passait par une commande `bash -c "…"` lancée depuis zsh, avec des accents graves dans la chaîne, ce que les règles de la session interdisent. **zsh a exécuté le contenu de ces accents graves** comme des commandes. La note écrite était corrompue ; elle n'a jamais été commitée et a été réécrite avec l'outil d'écriture.

Commandes réellement exécutées par erreur, d'après la sortie de la commande :
- `dpkg-deb` sans argument (erreur d'usage, aucun effet) et `apt-ftparchive` sans argument (affichage de l'aide) ;
- `gpg-agent` sans option : il a répondu « gpg-agent running and available », donc il a trouvé l'agent du trousseau par défaut déjà lancé ;
- **`gpgconf --kill all` sans `--homedir`** : cette commande arrête les démons de GnuPG (agent, dirmngr, keyboxd, scdaemon) du **trousseau par défaut de l'utilisateur**. Ils redémarrent à la première demande. Aucune clé ni aucun fichier n'a été lu, écrit ou affiché ;
- les autres mots (empreintes, noms de fichiers) ont échoué en « command not found ».

Désormais, aucun texte ne passe par `bash -c` avec des accents graves : les notes sont écrites avec l'outil d'écriture.
