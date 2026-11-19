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
