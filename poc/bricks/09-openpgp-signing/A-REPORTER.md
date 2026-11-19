# Brique 09 : ajouts proposés aux fichiers partagés

Rédigé par la session de préparation à sec de la brique 09 (branche `claude/brique-09-sec-fdb4c6`, jamais poussée), le 19/11/2026. **Cette session ne modifie aucun de ces fichiers** : la session principale les intègre, mot pour mot ou après relecture. Les verdicts sont des **propositions** ; toute pondération revient au propriétaire.

Sources : [relevé](resultats/releve-amont.log), compléments [1](resultats/releve-complements.log), [2](resultats/releve-complements-2.log), [3](resultats/releve-complements-3.log), [banc O0](resultats/banc-depot-deb.log), [README de la brique](README.md). Les chemins ci-dessous sont écrits depuis l'emplacement de chaque fichier cible.

---

## 1. `docs/04-sante-projets.md`

### 1.1 §2, tableau du relevé Scorecard : lignes à ajouter (à la fin du tableau, avant les lignes « hors GitHub »)

```
| obs-sign (ajouté le 19/11/2026, brique 09, non retenu) | openSUSE/obs-sign | signature | non | n/d | — | — | — | — | — |
| SoftHSMv2 (ajouté le 19/11/2026, brique 09, non retenu) | softhsm/SoftHSMv2 | signature | non | n/d | — | — | — | — | — |
| gnupg-pkcs11-scd (ajouté le 19/11/2026, brique 09, non retenu) | alonbl/gnupg-pkcs11-scd | signature | non | n/d | — | — | — | — | — |
| siguldry (ajouté le 19/11/2026, brique 09, non retenu) | fedora-infra/siguldry | signature | non | n/d | — | — | — | — | — |
| vault-gpg-plugin (ajouté le 19/11/2026, brique 09, non retenu) | LeSuisse/vault-gpg-plugin | signature | non | n/d | — | — | — | — | — |
| GnuPG (ajouté le 19/11/2026, brique 09) | hors GitHub | signature | oui | n/a | — | — | — | — | — |
| apt (apt-ftparchive ; ajouté le 19/11/2026, brique 09) | hors GitHub | signature | oui | n/a | — | — | — | — | — |
| devscripts (debsign ; ajouté le 19/11/2026, brique 09, selon la décision D1) | hors GitHub | signature | non | n/a | — | — | — | — | — |
| Sequoia (sqv, bibliothèque openpgp ; ajouté le 19/11/2026, brique 09) | hors GitHub | signature | non | n/a | — | — | — | — | — |
```

« n/d » : l'API publique de Scorecard répond 404 pour ces cinq dépôts le 19/11/2026 ([relevé](../poc/bricks/09-openpgp-signing/resultats/releve-amont.log), §2).

### 1.2 §3, tableau des verdicts : trois lignes à ajouter

Avant la ligne « **Risqué → interdit** » :

```
| **À surveiller, chemin critique, ajoutés le 19/11/2026 (brique 09, signature OpenPGP, [relevé](../poc/bricks/09-openpgp-signing/resultats/releve-amont.log), [compléments](../poc/bricks/09-openpgp-signing/resultats/releve-complements.log), [fin de vie](../poc/bricks/09-openpgp-signing/resultats/releve-complements-3.log))** | **GnuPG** et **apt** (`apt-ftparchive`) : détail au §4. **rpm-sign** relève du projet rpm (ligne du 12/11/2026 ci-dessus, inchangée) ; la version employée serait `rpm-sign` 4.16.1.3-40.el9 de Rocky 9.8 (construit le 28/12/2025), dont `rpm-sign-libs` exige `/usr/bin/gpg2`. **createrepo_c** : ligne du 12/11/2026, inchangée. |
| **À surveiller, hors chemin critique, ajoutés le 19/11/2026 (brique 09, mêmes journaux)** | **devscripts** (`debsign`, retenu seulement selon la décision D1 de la brique 09) et **Sequoia** (`sqv`, vérificateur d'apt de Debian 13, retenu pour contrôler nos signatures côté consommateur) : détail au §4. **Non retenus** : **obs-sign** (tag 2.8.5 du 05/02/2026, aucune release GitHub ; 10 commits en 90 jours, tous d'auteurs à adresse suse.de ; absent de Debian 13, EPEL 9 en 2.5.10 de 2021 ; moteurs `signd_pkcs11` et `signd_tpm` présents sur master seulement, absents du tag 2.8.5 ; pas de SECURITY.md ; Scorecard n/d) ; **siguldry** (0.9.1 du 13/11/2026, 0.x ; 60 commits en 90 jours, 4 auteurs, 38 commits d'auteurs à adresse microsoft.com ; licence non détectée par l'API ; « not currently deployed within the Fedora infrastructure » d'après la documentation de Fedora ; interface PKCS#11 utilisable par Sequoia ; veille) ; **SoftHSMv2** (2.7.0 du 20/01/2026, plus de 6 mois ; 11 commits en 90 jours, 8 auteurs ; pas de SECURITY.md ; Debian 13 2.6.1-3, Rocky 9.8 `softhsm` 2.6.1-11.el9 ; sans usage, faute de pont publié entre gpg et PKCS#11). Employeurs mesurés par les domaines des adresses d'auteur seulement. |
```

À la fin de la cellule « Projets » de la ligne « **Risqué → interdit** », ajouter :

```
 ; **ajoutés le 19/11/2026 (brique 09, [relevé](../poc/bricks/09-openpgp-signing/resultats/releve-amont.log), [compléments](../poc/bricks/09-openpgp-signing/resultats/releve-complements.log)), remplissent à la lettre « aucune release depuis plus de 12 mois » au 19/11/2026, non retenus** : **sigul** (aucun tag après `v1.4` d'après `git ls-remote` ; le paquet d'EPEL 9 note « Update to v1.4 » le 22/04/2025, donc une release au plus tard à cette date, borne et non date lue ; Fedora l'emploie encore, avec des clés protégées par des jetons PKCS#11, et prépare siguldry), **gnupg-pkcs11-scd** (0.11.0 du 27/10/2024 ; 0 commit en 90 jours ; Debian 13 0.10.0-5), **vault-gpg-plugin** (v0.6.3 du 02/01/2025 ; un seul auteur ; extension de HashiCorp Vault, compatibilité avec OpenBao non vérifiée), **debsigs** (tag amont `release/0.2.2` du 22/11/2024 ; Debian 13 0.2.2-1 ; le tag d'empaquetage `debian/0.2.2-2` du 07/01/2026 n'est pas une release amont, lecture identique à celle de GnuPG). **dpkg-sig** : absent de Debian 13 (madison), non audité.
```

### 1.3 §4, projets hors GitHub : quatre lignes à ajouter

```
| **GnuPG** (ajouté le 19/11/2026, brique 09, [relevé](../poc/bricks/09-openpgp-signing/resultats/releve-amont.log), [fin de vie](../poc/bricks/09-openpgp-signing/resultats/releve-complements-3.log), [failles de Debian](../poc/bricks/09-openpgp-signing/resultats/releve-complements-2.log)) | GPL-3.0. `swdb.lst` **vérifié par gpgv** avec la clé `6DAA6E64A76D2840571B4902528897B826403ADA`, l'une des 6 empreintes de `signature_key.asc` (4 personnes et 2 clés « GnuPG.com »), recoupées avec `signature_key.html` du même site : 2.5.24 du 23/09/2026 (série 2.6 en préparation, tag `gnupg-2.6-base`), 2.4.9 du 30/12/2025. Tableau de fin de vie : **2.4 au 30/06/2026**, 2.5 et 2.6 « tba », **aucune ligne 2.3** ; libgcrypt 1.10 au 30/06/2026. Miroir `gpg/gnupg` (« Maintainers are not tracking this mirror ») : 90 commits en 90 jours, 4 auteurs, 60 commits d'auteurs à adresse gnupg.org, 24 fsij.org, 4 gentoo.org, 2 gnupg.com ; employeurs non établis (domaines seulement), un éditeur dominant probable. Contact de sécurité publié (« report it by mail to security at gnupg ») ; pas de SECURITY.md. Scorecard du miroir 3,5 (Code-Review 0), **non représentatif** du projet. Délai de correction des CVE non mesuré. **Versions employées** (paquets des distributions, branches amont hors maintenance) : Debian 13 `gnupg` et `gpgv` 2.4.7-21+deb13u1, 4 failles « Open issues » pour trixie, toutes « vulnerable (no DSA) » (CVE-2026-105712, CVE-2026-57062, CVE-2026-24882, CVE-2025-68972, cette dernière sur les messages signés en clair) et CVE-2022-3219 en « Open unimportant issues » ; Rocky 9.8 `gnupg2` 2.3.3-5.el9_7 (construit le 19/01/2026), maintenance de la distribution seulement. Hôte du PoC : 2.4.8 (Ubuntu 26.04) | À surveiller, chemin critique. Aucun critère « Risqué » à la lettre. Vérifier `Release` + `Release.gpg`, ou le texte sorti de la vérification, jamais un `InRelease` brut (CVE-2025-68972). Plan de sortie au §6 |
| **apt** (`apt-ftparchive`, `apt-utils` ; ajouté le 19/11/2026, brique 09, mêmes journaux) | Salsa (`apt-team/apt`) : tag 3.3.8 du 16/11/2026 ; au moins 100 commits en 90 jours, 9 auteurs, **79 commits sur 100 d'un même auteur** ; domaines debian.org 82, gmail.com 10, canonical.com 6 ; employeurs non établis. Processus de sécurité de Debian. Debian 13 : 3.0.3 (3.0.4 en proposed-updates). `debian/control` au tag 3.0.3 : `sqv (>= 1.3.0) … \| gpgv` ; politique `default-sequoia.config` : DSA refusé depuis le 01/02/2024, RSA 2048 jusqu'au 01/02/2030, SHA-1 et SHA-224 jusqu'au 01/02/2026, signatures v3 jusqu'au 01/02/2026. Méthode effectivement employée (sqv ou gpgv) non lue | À surveiller, chemin critique (concentration sur un auteur) |
| **devscripts** (`debsign` ; ajouté le 19/11/2026, brique 09, selon D1) | Salsa (`debian/devscripts`) : tag v2.26.15 du 07/11/2026 ; 39 commits en 90 jours, 16 auteurs ; domaines debian.org 22, layer-acht.org 10, canonical.com 5. Debian 13 : 2.25.15+deb13u1. `debsign` signe le `.dsc`, le `.buildinfo` et le `.changes` (page de manuel de trixie), **pas le `.deb`** | À surveiller (employeurs non établis, Scorecard n/a), hors chemin critique |
| **Sequoia** (`sqv`, `sequoia-openpgp` ; ajouté le 19/11/2026, brique 09) | gitlab.com : `sequoia-sqv` v1.5.0 du 03/07/2026, 0 commit en 90 jours sur ce dépôt ; bibliothèque `openpgp/v2.4.2` du 14/10/2026, 27 commits en 90 jours, 5 auteurs (sequoia-pgp.org 16). Debian 13 : `sqv` 1.3.0-3+b2, `sq` 1.3.1-2+b2. Sert d'abord au **consommateur** (apt de Debian 13) ; retenu pour vérifier nos dépôts comme apt les vérifiera | À surveiller, hors chemin de signature ; plan de sortie côté deb pour GnuPG (non mesuré) |
```

### 1.4 §6, plans de sortie : une ligne à ajouter

```
| GnuPG (ajouté le 19/11/2026, brique 09) | Branches amont des versions employées hors maintenance (2.4 depuis le 30/06/2026 ; 2.3 absente du tableau de fin de vie) ; 4 failles ouvertes sans DSA dans Debian 13 ; un éditeur dominant probable | Côté deb : Sequoia (`sq` pour signer, `sqv` déjà employé par apt d'après sa dépendance), relevé, non mesuré. Côté rpm : **aucune sortie mesurée**, `rpm-sign` 4.16 de Rocky 9.8 appelant gpg (`%__gpg_sign_cmd`) ; GnuPG 2.5 construit depuis l'archive amont signée reste possible (décision D4 de la brique 09) |
```

---

## 2. `docs/03-validation-briques.md`, tableau « Briques » : une ligne à ajouter

```
| 09 | openpgp-signing | **Préparé à sec** (19/11/2026, branche `claude/brique-09-sec-fdb4c6`) ; banc O0 sur l'hôte tenu, rien installé, cluster et Zot intacts | Dépôt apt signé autour d'une copie de D (`f66bbeb2…`) : `Release.gpg` et `InRelease` vérifiés par gpgv 2.4.8, chaîne `Release` → `Packages` → deb tenue, 5 témoins refusés ou détectés ; gpgv accepte une signature SHA-1 que la politique d'apt de Debian 13 refuse ; `apt-ftparchive` 3.2.1 ignore `SOURCE_DATE_EPOCH` pour `Date`. Ni rpm, ni `createrepo_c`, ni sqv, ni le gpg des distributions cibles mesurés | [README](../poc/bricks/09-openpgp-signing/README.md), [banc](../poc/bricks/09-openpgp-signing/resultats/banc-depot-deb-predictions.md) ; décisions D1 à D4 attendues |
```

---

## 3. `README.md` racine, ligne 33

Remplacer « **Signature OpenPGP (09)** : non commencée. » par :

```
**Signature OpenPGP (09)** : préparée à sec le 19/11/2026 (branche à part, non fusionnée) ; banc O0 sur l'hôte tenu ; décisions D1 à D4 attendues avant tout passage dans le cluster.
```

---

## 4. `docs/adr/README.md`, ligne de l'ADR 0003

À la fin de la cellule « Décision attendue », ajouter :

```
 ; **brique 09 (préparée à sec le 19/11/2026)** : aucun chemin publié et maintenu de gpg vers un HSM PKCS#11 (gnupg-pkcs11-scd « Risqué » à la lettre ; moteurs PKCS#11 et TPM d'obs-sign non publiés) : la clé OpenPGP du PoC serait un fichier dans un service isolé (écart à écrire) ou sur un jeton matériel (décision D2) ; clé distincte pour l'attestation de lien, proposée en Transit (`lien`, décision D3) ; clé RSA 4096 v4 et SHA-512, compatibles avec `default-sequoia.config` d'apt de Debian 13 (banc O0 sous gpgv 2.4.8 seulement) ; expiration et certificat de révocation à part
```

---

## 5. `docs/00-etude-existant.md`, ligne 106 : correction datée

Après le tableau du §4 (sous la ligne « Sources : … »), ajouter :

```
*Correction datée du 19/11/2026 (brique 09, [page de manuel de debsign de trixie](../poc/bricks/09-openpgp-signing/resultats/releve-complements.log), §A)* : dans la ligne « Signature OpenPGP », « `rpmsign`/`debsign` modifient l'artefact » n'est exact que pour `rpmsign`. `debsign` signe le `.dsc`, le `.buildinfo` et le `.changes`, pas le `.deb` ; le deb reste bit-identique et sa signature passe par le dépôt (`Release.gpg`, `InRelease`). Une signature intégrée au `.deb` demanderait `debsigs`, qui remplit à la lettre « Risqué » (doc 04). L'attestation de lien reste nécessaire pour le rpm signé ; pour le deb, le lien est une identité d'empreinte.
```

---

## 6. Note pour la session principale

- Les verdicts « Risqué » proposés au §1.2 n'interdisent que des outils **non retenus** ; aucune voie de la brique n'en dépend.
- La ligne curl du doc 04 reste à la session principale ; la brique 09 a employé le curl de l'hôte pour ses lectures publiques.
- Environ 32 appels anonymes à l'API GitHub ont été consommés de 14:44 à 14:48 UTC ; le quota était revenu à 60 sur 60 lors du relevé de 14:52:27 UTC (note du dossier partagé des sessions).
