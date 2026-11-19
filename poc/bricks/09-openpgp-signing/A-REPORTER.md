# Brique 09 : ajouts proposés aux fichiers partagés

Rédigé par la session de préparation à sec de la brique 09 (branche `claude/brique-09-sec-fdb4c6`, jamais poussée), le 19/11/2026 ; **corrigé en place après la relecture finale du conseiller, avant toute intégration** (SHA-1 et politique d'apt bornés, version de `gpgv`, source du verdict de debsigs, consigne du §1.1). **Cette session ne modifie aucun de ces fichiers** : la session principale les intègre, mot pour mot ou après relecture. Les verdicts sont des **propositions** ; toute pondération revient au propriétaire.

Sources : [relevé](resultats/releve-amont.log), compléments [1](resultats/releve-complements.log), [2](resultats/releve-complements-2.log), [3](resultats/releve-complements-3.log), [banc O0](resultats/banc-depot-deb.log), [README de la brique](README.md). Les chemins ci-dessous sont écrits depuis l'emplacement de chaque fichier cible.

---

## 1. `docs/04-sante-projets.md`

*Note datée du 19/11/2026, 18:00:59 UTC* : les trois lignes GnuPG de docs/04 (§3, §4, §6) sont déjà écrites par la session principale, au commit `5d0e7868` de `claude/focused-fermi-ul5y20` (non poussé). Ce commit est vu dans le dépôt local : trois lignes ajoutées qui contiennent « GnuPG ». Elles reprennent le verdict « À surveiller, chemin critique » d'après les relevés `74e7b94c` et `96b7e6f7`, et la brique 05 y ajoute une mesure à elle : aucun erratum de Rocky 9.8 ne porte un gnupg2 plus récent. Pour l'intégration de ce fichier : **sauter** la ligne GnuPG du §1.3 et celle du §1.4. Au §1.2, **retirer GnuPG** de la ligne « À surveiller, chemin critique » et garder apt, rpm-sign et createrepo_c. Le reste ne change pas (§1.1, apt, devscripts, Sequoia, lignes « non retenus »).

### 1.1 §2, tableau du relevé Scorecard : lignes à ajouter (les cinq premières avant les lignes « hors GitHub » existantes, à partir de Forgejo ; les quatre dernières parmi ces lignes « hors GitHub »)

```
| obs-sign (ajouté le 19/11/2026, brique 09, non retenu) | openSUSE/obs-sign | signature | non | n/d | — | — | — | — | — |
| SoftHSMv2 (ajouté le 19/11/2026, brique 09, non retenu) | softhsm/SoftHSMv2 | signature | non | n/d | — | — | — | — | — |
| gnupg-pkcs11-scd (ajouté le 19/11/2026, brique 09, non retenu) | alonbl/gnupg-pkcs11-scd | signature | non | n/d | — | — | — | — | — |
| siguldry (ajouté le 19/11/2026, brique 09, non retenu) | fedora-infra/siguldry | signature | non | n/d | — | — | — | — | — |
| vault-gpg-plugin (ajouté le 19/11/2026, brique 09, non retenu) | LeSuisse/vault-gpg-plugin | signature | non | n/d | — | — | — | — | — |
| GnuPG (ajouté le 19/11/2026, brique 09) | hors GitHub | signature | oui | n/a | — | — | — | — | — |
| apt (apt-ftparchive ; ajouté le 19/11/2026, brique 09) | hors GitHub | signature | oui | n/a | — | — | — | — | — |
| devscripts (debsign ; ajouté le 19/11/2026, brique 09, non employé après la décision D1 (a)) | hors GitHub | signature | non | n/a | — | — | — | — | — |
| Sequoia (sqv, bibliothèque openpgp ; ajouté le 19/11/2026, brique 09) | hors GitHub | signature | non | n/a | — | — | — | — | — |
```

« n/d » : l'API publique de Scorecard répond 404 pour ces cinq dépôts le 19/11/2026 ([relevé](../poc/bricks/09-openpgp-signing/resultats/releve-amont.log), §2).

### 1.2 §3, tableau des verdicts : trois lignes à ajouter

Avant la ligne « **Risqué → interdit** » :

```
| **À surveiller, chemin critique, ajoutés le 19/11/2026 (brique 09, signature OpenPGP, [relevé](../poc/bricks/09-openpgp-signing/resultats/releve-amont.log), [compléments](../poc/bricks/09-openpgp-signing/resultats/releve-complements.log), [fin de vie](../poc/bricks/09-openpgp-signing/resultats/releve-complements-3.log))** | **GnuPG** et **apt** (`apt-ftparchive`) : détail au §4. **rpm-sign** relève du projet rpm (ligne du 12/11/2026 ci-dessus, inchangée) ; la version employée serait `rpm-sign` 4.16.1.3-40.el9 de Rocky 9.8 (construit le 28/12/2025), dont `rpm-sign-libs` exige `/usr/bin/gpg2`. **createrepo_c** : ligne du 12/11/2026, inchangée. |
| **À surveiller, hors chemin critique, ajoutés le 19/11/2026 (brique 09, mêmes journaux)** | **devscripts** (`debsign`, non employé : décision D1 (a) du 19/11/2026, la pipeline ne publiant ni `.changes` ni `.buildinfo`) et **Sequoia** (`sqv`, vérificateur d'apt de Debian 13, retenu pour contrôler nos signatures côté consommateur) : détail au §4. **Non retenus** : **obs-sign** (tag 2.8.5 du 05/02/2026, aucune release GitHub ; 10 commits en 90 jours, tous d'auteurs à adresse suse.de ; absent de Debian 13, EPEL 9 en 2.5.10 de 2021 ; moteurs `signd_pkcs11` et `signd_tpm` présents sur master seulement, absents du tag 2.8.5 ; pas de SECURITY.md ; Scorecard n/d) ; **siguldry** (0.9.1 du 13/11/2026, 0.x ; 60 commits en 90 jours, 4 auteurs, 38 commits d'auteurs à adresse microsoft.com ; licence non détectée par l'API ; « not currently deployed within the Fedora infrastructure » d'après la documentation de Fedora ; interface PKCS#11 utilisable par Sequoia ; veille) ; **SoftHSMv2** (2.7.0 du 20/01/2026, plus de 6 mois ; 11 commits en 90 jours, 8 auteurs ; pas de SECURITY.md ; Debian 13 2.6.1-3, Rocky 9.8 `softhsm` 2.6.1-11.el9 ; sans usage, faute de pont publié entre gpg et PKCS#11). Employeurs mesurés par les domaines des adresses d'auteur seulement. |
```

À la fin de la cellule « Projets » de la ligne « **Risqué → interdit** », ajouter :

```
 ; **ajoutés le 19/11/2026 (brique 09, [relevé](../poc/bricks/09-openpgp-signing/resultats/releve-amont.log), [compléments](../poc/bricks/09-openpgp-signing/resultats/releve-complements.log)), remplissent à la lettre « aucune release depuis plus de 12 mois » au 19/11/2026, non retenus** : **sigul** (aucun tag après `v1.4` d'après `git ls-remote` ; le paquet d'EPEL 9 note « Update to v1.4 » le 22/04/2025, donc une release au plus tard à cette date, borne et non date lue ; Fedora l'emploie encore, avec des clés protégées par des jetons PKCS#11, et prépare siguldry), **gnupg-pkcs11-scd** (0.11.0 du 27/10/2024 ; 0 commit en 90 jours ; Debian 13 0.10.0-5), **vault-gpg-plugin** (v0.6.3 du 02/01/2025 ; un seul auteur ; extension de HashiCorp Vault, compatibilité avec OpenBao non vérifiée), **debsigs** (tags du seul dépôt salsa `debian/debsigs` : tag amont `release/0.2.2` du 22/11/2024 ; Debian 13 0.2.2-1 ; le tag d'empaquetage `debian/0.2.2-2` du 07/01/2026 n'est pas une release amont, lecture identique à celle de GnuPG). **dpkg-sig** : absent de Debian 13 (madison), non audité.
```

### 1.3 §4, projets hors GitHub : quatre lignes à ajouter

```
| **GnuPG** (ajouté le 19/11/2026, brique 09, [relevé](../poc/bricks/09-openpgp-signing/resultats/releve-amont.log), [fin de vie](../poc/bricks/09-openpgp-signing/resultats/releve-complements-3.log), [failles de Debian](../poc/bricks/09-openpgp-signing/resultats/releve-complements-2.log)) | GPL-3.0. `swdb.lst` **vérifié par gpgv** avec la clé `6DAA6E64A76D2840571B4902528897B826403ADA`, l'une des 6 empreintes de `signature_key.asc` (4 personnes et 2 clés « GnuPG.com »), recoupées avec `signature_key.html` du même site : 2.5.24 du 23/09/2026 (série 2.6 en préparation, tag `gnupg-2.6-base`), 2.4.9 du 30/12/2025. Tableau de fin de vie : **2.4 au 30/06/2026**, 2.5 et 2.6 « tba », **aucune ligne 2.3** ; libgcrypt 1.10 au 30/06/2026. Miroir `gpg/gnupg` (« Maintainers are not tracking this mirror ») : 90 commits en 90 jours, 4 auteurs, 60 commits d'auteurs à adresse gnupg.org, 24 fsij.org, 4 gentoo.org, 2 gnupg.com ; employeurs non établis (domaines seulement), un éditeur dominant probable. Contact de sécurité publié (« report it by mail to security at gnupg ») ; pas de SECURITY.md. Scorecard du miroir 3,5 (Code-Review 0), **non représentatif** du projet. Délai de correction des CVE non mesuré. **Versions employées** (paquets des distributions, branches amont hors maintenance) : Debian 13 `gnupg` 2.4.7-21+deb13u1 et `gpgv` 2.4.7-21+deb13u1+b5, 4 failles « Open issues » pour trixie, toutes « vulnerable (no DSA) » (CVE-2026-105712, CVE-2026-57062, CVE-2026-24882, CVE-2025-68972, cette dernière sur les messages signés en clair) et CVE-2022-3219 en « Open unimportant issues » ; Rocky 9.8 `gnupg2` 2.3.3-5.el9_7 (construit le 19/01/2026), maintenance de la distribution seulement ; c'est la **seule révision** de `gnupg2` dans le `primary` vérifié de BaseOS 9.8, et celle qu'exécutent déjà l'amorce `rockylinux:9.8` (`ed654c69…`) et l'image de `prefetch-rpm` (`99790c13…`) d'après [`m1b-curl-amorce.log`](../poc/bricks/05-rpm-mock/resultats/m1b-curl-amorce.log), l. 5 et 13 (brique 05, 19/11/2026) : aucun retard de révision ; errata de Rocky et avis de GnuPG touchant 2.3.3 non lus. Hôte du PoC : 2.4.8 (Ubuntu 26.04) | À surveiller, chemin critique. Aucun critère « Risqué » à la lettre. Vérifier `Release` + `Release.gpg`, ou le texte sorti de la vérification, jamais un `InRelease` brut (CVE-2025-68972). Plan de sortie au §6 |
| **apt** (`apt-ftparchive`, `apt-utils` ; ajouté le 19/11/2026, brique 09, mêmes journaux) | Salsa (`apt-team/apt`) : tag 3.3.8 du 16/11/2026 ; au moins 100 commits en 90 jours, 9 auteurs, **79 commits sur 100 d'un même auteur** ; domaines debian.org 82, gmail.com 10, canonical.com 6 ; employeurs non établis. Processus de sécurité de Debian. Debian 13 : 3.0.3 (3.0.4 en proposed-updates). `debian/control` au tag 3.0.3 : `sqv (>= 1.3.0) … \| gpgv` ; politique `default-sequoia.config` : DSA au 01/02/2024, RSA 2048 au 01/02/2030, `sha1.second_preimage_resistance` et `sha224` au 01/02/2026, signatures v3 au 01/02/2026 ; d'après Sequoia, la résistance à la seconde préimage vise surtout les autosignatures, et le seuil de SHA-1 pour les signatures de données n'est pas lu ([complément 4](../poc/bricks/09-openpgp-signing/resultats/releve-complements-4.log)). Méthode effectivement employée (sqv ou gpgv) non lue | À surveiller, chemin critique (concentration sur un auteur) |
| **devscripts** (`debsign` ; ajouté le 19/11/2026, brique 09 ; non employé après D1 (a)) | Salsa (`debian/devscripts`) : tag v2.26.15 du 07/11/2026 ; 39 commits en 90 jours, 16 auteurs ; domaines debian.org 22, layer-acht.org 10, canonical.com 5. Debian 13 : 2.25.15+deb13u1. `debsign` signe le `.dsc`, le `.buildinfo` et le `.changes` (page de manuel de trixie), **pas le `.deb`** | À surveiller (employeurs non établis, Scorecard n/a), hors chemin critique |
| **Sequoia** (`sqv`, `sequoia-openpgp` ; ajouté le 19/11/2026, brique 09) | gitlab.com : `sequoia-sqv` v1.5.0 du 03/07/2026, 0 commit en 90 jours sur ce dépôt ; bibliothèque `openpgp/v2.4.2` du 14/10/2026, 27 commits en 90 jours, 5 auteurs (sequoia-pgp.org 16). Debian 13 : `sqv` 1.3.0-3+b2, `sq` 1.3.1-2+b2. Sert d'abord au **consommateur** (apt de Debian 13) ; retenu pour vérifier nos dépôts comme apt les vérifiera | À surveiller, hors chemin de signature ; plan de sortie côté deb pour GnuPG (non mesuré) |
```

### 1.4 §6, plans de sortie : une ligne à ajouter

```
| GnuPG (ajouté le 19/11/2026, brique 09) | Branches amont des versions employées hors maintenance (2.4 depuis le 30/06/2026 ; 2.3 absente du tableau de fin de vie) ; 4 failles ouvertes sans DSA dans Debian 13 ; un éditeur dominant probable | Côté deb : Sequoia (`sq` pour signer, `sqv` déjà employé par apt d'après sa dépendance), relevé, non mesuré. Côté rpm : **aucune sortie mesurée**, `rpm-sign` 4.16 de Rocky 9.8 appelant gpg (`%__gpg_sign_cmd`) ; GnuPG 2.5 construit depuis l'archive amont signée reste possible, mais écarté par la décision D4 (a) du propriétaire du 19/11/2026 (paquets des distributions) |
```

---

## 2. `docs/03-validation-briques.md`, tableau « Briques » : une ligne à ajouter

```
| 09 | openpgp-signing | **Préparé à sec** (19/11/2026, branche `claude/brique-09-sec-fdb4c6`) ; banc O0 sur l'hôte tenu, rien installé, cluster et Zot intacts | Dépôt apt signé autour d'une copie de D (`f66bbeb2…`) : `Release.gpg` et `InRelease` vérifiés par gpgv 2.4.8, chaîne `Release` → `Packages` → deb tenue, 5 témoins refusés ou détectés ; gpgv 2.4.8 accepte une signature SHA-1 de `Release` (refus par apt de Debian 13 non établi) ; `apt-ftparchive` 3.2.1 ignore `SOURCE_DATE_EPOCH` pour `Date`. Ni rpm, ni `createrepo_c`, ni sqv, ni le gpg des distributions cibles mesurés | [README](../poc/bricks/09-openpgp-signing/README.md), [banc](../poc/bricks/09-openpgp-signing/resultats/banc-depot-deb-predictions.md) ; décisions D1 à D4 prises le 19/11/2026, toutes en (a) ; O2 préparé à sec ([carte](../poc/bricks/09-openpgp-signing/resultats/o2-carte.md)) : relevé et banc des gardes de la clé tenus (gpg de l'hôte, clé jetable), construction des racines et clé du PoC non lancées |
```

*Note datée du 19/11/2026, 18:37:49 UTC* : la ligne ci-dessus décrit l'état d'avant O2. À l'intégration, **la remplacer par celle-ci** :

```
| 09 | openpgp-signing | **En cours, hors cluster** (19/11/2026, branche `claude/brique-09-sec-fdb4c6`) ; O0, O2, O3 et O4 tenus sur l'hôte, sans réseau pour toute étape qui touche la clé, rien installé, cluster et Zot intacts ; O5 (attestation de lien) en attente d'accords | Clé du PoC RSA 4096 v4 `29BA1C48…BCF03A86`, sans phrase de passe (décision du propriétaire), créée par gpg 2.4.7 dans une racine Debian 13 sans réseau. rpm signé dans une racine Rocky 9.8 (gpg 2.3.3, rpm-sign 4.16) : en-tête principal et charge utile inchangés (B1), accepté par rpmkeys et dnf d'une amorce Rocky 9.8 (`gpgcheck=1`, `repo_gpgcheck=1`), 3 témoins refusés. Dépôt apt signé (`InRelease`, `Release.gpg` armuré, SHA-512), deb inchangé (`f66bbeb2…`), accepté par apt 3.0.3 et 3.0.4 avec `Signed-By`, 7 témoins refusés. apt de Debian 13 vérifie par sqv même quand gpgv est installé ; il refuse une signature SHA-1 de `Release` et un `Release.gpg` binaire. `apt-ftparchive` 3.0.3 ignore `SOURCE_DATE_EPOCH`. `rpmsign --delsign` ne rend pas le rpm d'origine | [README](../poc/bricks/09-openpgp-signing/README.md), prédictions et résultats [O2](../poc/bricks/09-openpgp-signing/resultats/o2-predictions.md), [O3](../poc/bricks/09-openpgp-signing/resultats/o3-predictions.md), [O4](../poc/bricks/09-openpgp-signing/resultats/o4-predictions.md) ; décisions D1 à D4 du 19/11/2026, toutes en (a) ; écart : amorces de vérification réutilisées depuis O2, contrôlées par le sha256 de leur couche seulement |
```

*Correction datée du 19/11/2026, 18:41:53 UTC* : dans la ligne de remplacement ci-dessus, « rien installé » est trop fort depuis O2. Lire : « **rien installé au niveau système** ; racines de signature et amorces sous `~/.cache/supply-chain-poc/09`, hors du dépôt ».

---

*Note datée du 19/11/2026, 18:56:05 UTC* : dans la ligne de remplacement ci-dessus, lire « O5 (attestation de lien) en attente d'accords » ainsi : « **O5 : banc hôte à sec tenu** (clés cosign jetables, sans réseau ; cosign et contrôle indépendant de B1 tous deux nécessaires) ; **O5 réel** (clé Transit `lien`, referrer dans Zot) **en attente d'accords** ».

## 3. `README.md` racine, ligne 33

Remplacer « **Signature OpenPGP (09)** : non commencée. » par :

```
**Signature OpenPGP (09)** : préparée à sec le 19/11/2026 (branche à part, non fusionnée) ; banc O0 sur l'hôte tenu ; D1 à D4 décidées le 19/11/2026 (« deb signé » = dépôt apt signé, `.deb` intact ; clé OpenPGP en fichier sur l'hôte d'administration, pour le PoC seulement ; attestation de lien signée par la clé Transit `lien` après vérification de la provenance de Chains ; GnuPG des distributions) ; O2 préparé à sec (racines sur l'hôte depuis les dépôts signés, décision du 19/11/2026), construction et clé non lancées.
```

*Note datée du 19/11/2026, 18:37:57 UTC* : texte ci-dessus d'avant O2. À l'intégration, **le remplacer par celui-ci** :

```
**Signature OpenPGP (09)** : en cours hors cluster depuis le 19/11/2026 (branche à part, non fusionnée) ; D1 à D4 décidées le 19/11/2026 (« deb signé » = dépôt apt signé, `.deb` intact ; clé OpenPGP en fichier sur l'hôte d'administration, sans phrase de passe, pour le PoC seulement ; attestation de lien signée par la clé Transit `lien` après vérification de la provenance de Chains ; GnuPG des distributions) ; rpm signé et dépôt rpm signé vérifiés par dnf de Rocky 9.8, dépôt apt signé vérifié par apt de Debian 13 (sqv) ; reste l'attestation de lien (O5)
```

*Note datée du 19/11/2026, 18:58:46 UTC* : dans le texte de remplacement ci-dessus, lire « reste l'attestation de lien (O5) » ainsi : « attestation de lien éprouvée sur un banc hôte à clés cosign jetables ; reste O5 réel (clé Transit `lien`, referrer et lecture de Zot) ».

---

## 4. `docs/adr/README.md`, ligne de l'ADR 0003

À la fin de la cellule « Décision attendue », ajouter :

```
 ; **brique 09 (préparée à sec le 19/11/2026)** : décision du propriétaire D1 (a) du 19/11/2026, « deb signé » = dépôt apt signé (`Release.gpg`, `InRelease`), `.deb` bit-identique et lien par identité d'empreinte ; aucun chemin publié et maintenu de gpg vers un HSM PKCS#11 (gnupg-pkcs11-scd « Risqué » à la lettre ; moteurs PKCS#11 et TPM d'obs-sign non publiés) ; **décision du propriétaire D2 (a) du 19/11/2026, pour le PoC seulement** : clé OpenPGP en fichier 0600 sur l'hôte d'administration, hors du cluster, comme la clé des tâches de J6 ; **écart de production à écrire dans l'ADR** (texte au §4 bis de `poc/bricks/09-openpgp-signing/A-REPORTER.md`) ; **décision du propriétaire D3 (a) du 19/11/2026** : attestation de lien (énoncé in-toto) émise par le service de signature après vérification de la provenance de Chains sur le manifeste non signé, signée par cosign avec une clé Transit `lien` distincte (provenance, `tsa`, tâches) ; l'hôte d'administration détient un jeton OpenBao borné à `lien` et un accès en lecture à Zot ; **décision du propriétaire D4 (a) du 19/11/2026** : GnuPG des distributions (`gnupg2` 2.3.3-5.el9_7 de Rocky 9.8 pour rpm, `gnupg` 2.4.7-21+deb13u1 de Debian 13 pour deb), branches amont hors maintenance, failles à suivre au ré-audit ; clé RSA 4096 v4 et SHA-512, non bornées par `default-sequoia.config` d'apt de Debian 13 (lecture du fichier ; sqv non mesuré ; banc O0 sous gpgv 2.4.8 seulement) ; expiration et certificat de révocation à part
```

---

## 4 bis. ADR 0003 (à rédiger) : section à reprendre telle quelle, décision D2 du propriétaire

L'ADR 0003 n'existe pas encore (« À rédiger »). Le propriétaire demande que cet écart et cette recherche y soient écrits. Texte proposé, tiré mot pour mot de sa décision du 19/11/2026 (consignée au [README de la brique](README.md#décision-du-propriétaire-du-19112026--d2-a-pour-le-poc-seulement-consignée-à-152858-utc)) :

```
### Clé OpenPGP des rpm, des deb et des dépôts : écart du PoC et recherche pour la production

Décision du propriétaire du 19/11/2026 (brique 09, D2) :

Pour le PoC, la clé OpenPGP des rpm, des deb et des dépôts est un fichier de clé (0600)
sur l'hôte d'administration, hors du cluster, comme la clé des tâches de J6. Le cluster
ne voit jamais la clé privée. OpenBao sert seulement à l'attestation de lien (clé Transit
« lien », D3), parce que Transit ne fait pas d'OpenPGP.

Ce choix ne vaut que pour le PoC. Il n'est pas acceptable en production :
- la clé est copiable : root sur l'hôte ou une sauvegarde suffit pour la récupérer ;
- l'hôte d'administration porte déjà d'autres secrets (clé des tâches, accès au cluster) ;
- aucun journal de signature ne vit à l'abri du signataire, et il n'y a ni quorum
  ni limite d'usage ;
- c'est un écart avec le doc 02, qui place le service de signature dans la zone Confiance.

Pour la production, une vraie solution reste à trouver. Elle doit garder la clé dans un
matériel dont elle ne sort pas, et passer par un service de signature isolé et journalisé.
Aucune voie actuelle n'est à la fois maintenue et compatible avec notre chaîne :
- un jeton matériel OpenPGP (YubiKey, Nitrokey) sur un hôte dédié marche avec gpg et
  rpmsign, mais il n'a pas été mesuré ;
- un HSM réseau en PKCS#11 n'a aucun pont maintenu vers gpg ;
- les services tout faits (sigul, debusine) sont écartés aujourd'hui.

Cet écart et cette recherche sont à reprendre avant toute mise en production.

Mesures d'appui (brique 09, relevé du 19/11/2026) : gnupg-pkcs11-scd 0.11.0 du 27/10/2024,
« Risqué » à la lettre ; moteurs signd_pkcs11 et signd_tpm d'obs-sign présents sur master
seulement, absents du tag 2.8.5 ; sigul sans tag après v1.4 (au plus tard le 22/04/2025) ;
debusine : clés OpenPGP sur HSM non faites (ticket 1099 ouvert) ; jeton matériel non mesuré.
```

## 4 ter. ADR 0003 (à rédiger) : racines de signature et phrase de passe (O2 de la brique 09)

À ajouter sous la section du 4 bis :

```
Racines de signature (décision du propriétaire du 19/11/2026, « racines (a) », pour le PoC) :
l'outillage OpenPGP (gpg, rpm-sign, createrepo_c, apt-ftparchive, sqv) tourne sur l'hôte
d'administration, dans deux racines neuves construites depuis les dépôts signés figés
(vault/rocky/9.8 ; instantané Debian 20261105T000000Z), chaque image d'amorce ne servant
qu'une fois. Cible de production : racines produites par la plateforme, sans réseau, avec
leur provenance (même voie que la décision « C » de la brique 05, M1b).

Phrase de passe de la clé du PoC (proposée, à confirmer dans l'accord de l'étape « cle ») :
aucune. Compromis : une sauvegarde de l'hôte emporte une clé utilisable ; une phrase gardée
hors de l'hôte couvrirait ce cas, mais chaque signature la demanderait, et root sur l'hôte
pendant une signature la lirait quand même.
```

*Note datée du 19/11/2026, 17:18:33 UTC* : la phrase de passe est confirmée par le propriétaire : « Sans phrase de passe ». Le texte ci-dessus est à reprendre tel quel, sans « (proposée, à confirmer dans l'accord de l'étape « cle ») ».

---

## 4 quater. `tools/secrets-depot.sh` et règles de lecture des sessions

`tools/secrets-depot.sh` ne lit aujourd'hui que `08/secrets` et `10/secrets` ([relevé d'O2](resultats/o2-releve.log), §4), et n'a aucun motif « BEGIN PGP ». Deux ajouts proposés, à faire **avant** l'étape `cle` d'O2 :
- ajouter à la boucle de la ligne 8 **seulement** `"$HOME"/.cache/supply-chain-poc/09/secrets/cle-openpgp.asc` et `…/09/secrets/revocation.asc`, pas tout le dossier. La boucle fait de chaque ligne de chaque fichier un motif (ligne 11), puis refuse tout fichier modifié qui en contient un (lignes 22 à 25). Si la clé publique (`cle-publique.asc`, même dossier) était lue, ses lignes deviendraient des motifs et tout commit de la clé publique échouerait. La clé privée est exportée armurée : chacune de ses lignes devient un motif ;
- refuser tout fichier modifié ou nouveau qui contient la ligne `-----BEGIN PGP PRIVATE KEY BLOCK-----`. Ce contrôle vaut aussi pour une clé d'une autre origine.

Règles de lecture des sessions : ajouter `~/.cache/supply-chain-poc/09/secrets/` aux chemins à ne jamais lire ni lister.

*Correction datée du 19/11/2026, 16:48:49 UTC (brique 09, relecture avant `cle`)* : le second ajout ci-dessus, pris à la lettre, bloquerait la brique elle-même. `git grep -n 'BEGIN PGP'` trouve la ligne d'en-tête complète dans deux fichiers suivis : ce fichier (ligne 148, entre accents graves) et `o2-interne.sh` (ligne 58, argument de `grep -qx`). Dans les deux cas, l'en-tête n'est pas seul sur sa ligne. Le motif proposé devient donc : une ligne qui est **exactement** l'en-tête, du début à la fin de la ligne (`grep -x -F`). Deux points de plus, lus dans le script le même jour :
- `secrets-depot.sh` commence par `cd "$(dirname "$0")/.."` : chaque arbre de travail lance **sa propre copie**. Un ajout sur la branche principale ne protège les commits de la branche de la brique 09 qu'après fusion ou reprise du commit dans cette branche ;
- la boucle de la ligne 8 ignore un fichier absent (`[ -f "$f" ] || continue`). Tant que `09/secrets` n'existe pas, l'ajout ne change rien. Après `cle`, il n'est pas encore vérifié que chaque ligne de l'export armuré fait au moins quelques caractères : une ligne très courte (fin du bloc base64, ou ligne de somme si l'export en porte une) deviendrait un motif très court, cause de faux refus. À relever sur l'export réel, sans l'afficher : nombre de lignes et longueur minimale seulement.

*Seconde correction datée du 19/11/2026, 17:13:47 UTC (brique 09, [répétition de `cle`](resultats/o2-repetition.log), RP3)* : mesure faite avec une clé jetable de même forme que celle de `cle` (RSA 4096, exports de `o2-interne.sh creer`). Si la boucle de la ligne 8 lit `cle-openpgp.asc` sans autre filtre que celui de la ligne 11, elle produit 53 motifs ; le plus court fait 5 caractères. Pour `revocation.asc`, elle produit 30 motifs, le plus court de 5 caractères. Un motif de 5 caractères cherché par `grep -F` peut se trouver dans un fichier sans rapport, d'où de faux refus. Ajout proposé à la ligne 11 : ne garder comme motifs que les lignes d'**au moins 16 caractères** (`awk 'length($0) >= 16'` après le `grep -v`), dans la boucle des secrets de 09 au moins. Autre constat : l'en-tête de `revocation.asc` est un en-tête de clé **publique** précédé de deux-points. Le second ajout de ce paragraphe (en-tête de clé privée) ne protège donc pas le certificat de révocation : seul le premier ajout (motifs tirés du fichier) le couvre.

*Note datée du 19/11/2026, 18:56:05 UTC (brique 09, banc d'O5)* : **ni `garde-cle-privee.sh` ni `tools/secrets-depot.sh` ne voient une clé privée cosign.**
- La clé privée créée par `cosign generate-key-pair` (3.1.4) commence par une ligne « BEGIN ENCRYPTED SIGSTORE PRIVATE KEY » entre cinq tirets. Le motif de la garde n'y trouve aucune ligne ([o5-banc.log](resultats/o5-banc.log)), et `secrets-depot.sh` n'a aucun motif `PRIVATE`.
- Le banc garde ses clés jetables hors du dépôt et les efface après archivage.
- Pour O5 réel, la clé `lien` reste dans Transit et n'existe pas comme fichier.
- Proposition, sans urgence : étendre le refus à toute ligne qui commence par cinq tirets suivis de « BEGIN » et se termine par « PRIVATE KEY » puis cinq tirets, ancrée en début de ligne. La relecture du 16:48:49 UTC vaut aussi ici : avant l'ajout, chercher les fichiers suivis qui citent la ligne entière.

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
