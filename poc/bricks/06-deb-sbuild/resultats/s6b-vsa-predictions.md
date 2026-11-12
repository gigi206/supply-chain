# Brique 06, S6b : VSA du deb, prédictions (12/11/2026, rédigées à partir de 10:50:07 UTC, avant toute mesure)

Préparées après « Oui, prépare-la », sur le modèle de R5 de la brique 10. L'heure est celle du `date -u` du début de la rédaction ; l'heure du commit fait foi.

**Rien n'est lancé, rien n'est signé, rien n'est poussé.**

## Ce qui est préparé

- **[`rejeu/politique-replay-deb.md`](../rejeu/politique-replay-deb.md)** est un **projet, à ta relecture**. La politique de la 10 est écrite pour l'image : `preparer-entrees`, `construire-image`, BuildKit, Dockerfile. Ce projet la reprend et ne change que ce qui tient au deb :
  - les entrées déclarées ;
  - les 15 lignes clés des recettes ;
  - le chroot reconstruit, qui doit donner la couche de l'image de build déclarée ;
  - sbuild et mmdebstrap de Debian, aux versions de la plateforme ;
  - le critère : le manifeste reconstruit est égal au sujet.

  Il propose de ranger la VSA dans `builds/vsa/sample-app-deb`. La VSA citera ce fichier par son URL GitHub, à un commit poussé, et par son sha256.
- **[`rejeu/vsa_deb.py`](../rejeu/vsa_deb.py)**, adapté de `vsa.py`. Il exige :
  - `ko=0` dans `verifie.txt`, puis `PASSED`, le manifeste égal au sujet et la sortie à 0 dans `resultat.txt` ;
  - **la porteuse à 0 au départ et à la fin** : c'est nouveau par rapport à la 10, et c'est ce qui exclut un résultat de répétition ;
  - le bundle horodaté de `454728c5`, revérifié et identique à la provenance vérifiée ;
  - la section 1 ;
  - au moins 24 h entre `finishedOn` et `fin_deb`.

  `verifier.version` porte sbuild, mmdebstrap, dpkg-dev et Go, et le sha256 des trois outils. Sans KO, il écrit `enonce.json` ; sinon il n'écrit rien et rend 1.
- **Deux étapes de [`s6b.sh`](../s6b.sh)** :
  - **`vsa_essai`** (levier e), **rien de signé**. Il copie la politique de l'arbre de travail et `vsa_deb.py` dans `/home/replay/s6b/r5`, puis lance `vsa_deb.py` sous `unshare -rn` sur le résultat de la répétition. Il réussit seulement si le refus porte sur **exactement trois** conditions : lien établi au départ, lien établi à la fin, délai de 24 h. Et aucun énoncé ne doit être écrit.
  - **`vsa`** : comme `etape_vsa` de la 10. Elle refuse sans `POLITIQUE_COMMIT` poussé, avec un `vsa_deb.py` modifié hors commit ou un HEAD non poussé, ou sans les deux `OK` et le `bilan : PASSED` de `s6b-rebuild.log`. Puis elle écrit l'énoncé et le signe par la clé du domaine (`attest-blob --statement`, configuration sans service, `unshare -rn`). Elle vérifie la signature, et archive l'énoncé et le bundle dans `resultats/`. **Rien n'est poussé dans Zot.**

**Contrôle fait sur l'hôte** : appliquée au vrai résultat de la répétition, la lecture de `vsa_deb.py` donne `PASSED`, `code 0` et le manifeste `039949f9`. La porteuse vaut 1 au départ et à la fin, donc la condition est refusée ; dans une variante fabriquée avec la porteuse à 0, elle est acceptée. `bash -n`, `shellcheck -S warning` et l'analyse Python ne signalent rien.

## Ordre et accords

1. **`vsa_essai`**, possible tout de suite.
2. **Ta relecture de `politique-replay-deb.md`**, puis un commit qui la fige.
3. **Un push**, avec ton « oui ». `vsa` exige que ce commit et HEAD soient sur la branche distante. Le push porterait aussi les 44 commits en attente.
4. **`rebuild`**, lien coupé, à partir de 21:03:37 UTC.
5. **`vsa`**, puis le push de la VSA dans Zot après S5b (ordre c), avec un accord par push. Ce push n'est pas préparé.

## Prédictions

**`vsa_essai`**
- **E1.** Le transport copie deux fichiers, dont les sha256 sont égaux côté hôte et côté VM.
- **E2.** `vsa_deb.py` :
  - `OK` sur `verifie.txt`, le verdict, le manifeste, la sortie, la racine de la TSA, le bundle unique de `454728c5`, sa signature et son jeton, l'égalité avec `provenance.json` et la section 1 ;
  - **trois `KO`** : porteuse au départ (`{'porteuse_enp1s0': '1'}`), porteuse à la fin, et `timeVerified 2026-11-12T10:44:05Z` à moins de 24 h de `2026-11-11T21:03:37Z` ;
  - « REFUS : 3 condition(s) manquante(s) », code 1, aucun énoncé.

  Confiance haute pour les trois KO, qui viennent du résultat même. Confiance moyenne-haute pour les OK cosign : `verifier_deb.py` les a déjà obtenus, mais pas sous `unshare -rn`, comme le fait la VSA de la 10.
- **E3.** `bilan : refus attendu`, code 0. Rien de signé, rien d'écrit hors de `/home/replay/s6b/r5`.

**`vsa`** (après `rebuild`, relecture et push)
- **S1.** Mêmes `OK`, aucun `KO`. L'énoncé porte :
  - le sujet `sc-stockage.poc.test:5000/builds/sample-app-deb` (`039949f9`) ;
  - `timeVerified` = `fin_deb` de `rebuild` ;
  - `policy` (URL au commit, et sha256) ;
  - `inputAttestations` (manifeste du bundle `bundle-21edfa0ca581bad6`) ;
  - `verifier.version` : sbuild `0.89.3+deb13u4`, mmdebstrap `1.5.7-1+deb13u1`, dpkg-dev `1.22.22`, `go1.26.10` et les trois sha256.
- **S2.** Signature : `attest-blob` code 0, vérification par la clé du domaine code 0, sans tlog ni horodatage, énoncé identique.

## Note datée du 12/11/2026 (rédigée à partir de 10:56:18 UTC, après relecture du conseiller), avant tout lancement

Les prédictions ci-dessus ont été commitées dans `1b36f83`, à 10:50:25 UTC.

**Ordre corrigé.** `vsa` exige que HEAD soit poussé. Un push fait avant `rebuild` serait dépassé par le commit des résultats de `rebuild`, et il faudrait un second « oui ». L'ordre devient :
1. `vsa_essai` ;
2. ta relecture de la politique et ta réponse sur `SLSA_BUILD_LEVEL_3`, puis le commit qui la fige ;
3. `rebuild` ce soir ; je propose `ATTENTE_HORS_LIGNE=300`, puisque la répétition a duré 72 s ;
4. le commit des résultats, puis **un seul push**, avec ton « oui » ;
5. `POLITIQUE_COMMIT=<commit qui fige> mise exec -- poc/bricks/06-deb-sbuild/s6b.sh vsa`.

**Corrections, avant tout lancement**
- **`vsa_deb.py` construit l'énoncé avant le test des KO**, et ne l'écrit que sans KO. L'essai exerce ainsi toutes les lectures de l'énoncé : versions par `dpkg-query`, sha256 des trois outils, politique, `inputAttestations`.
- **`vsa_essai` vérifie la présence des fichiers de la clé du domaine** : `cosign.key`, `cosign.pub` et `mot-de-passe`, par `test -s`, sans les lire.
- **`vsa` refuse une politique qui porte encore une mention de projet** (« non figé », « projet du », « à décider », « question au propriétaire »).
- **Rangement** : fixé par la porte (`builds/vsa/sample-app-deb`). Ce n'est pas une question.

**Prédictions révisées de `vsa_essai`**
- **E2 bis.** Le prédicat s'affiche avant le refus, avec :
  - `"verificationResult": "PASSED"` ;
  - `timeVerified` `2026-11-12T10:44:05Z` ;
  - les versions sbuild `0.89.3+deb13u4`, mmdebstrap `1.5.7-1+deb13u1` et dpkg-dev `1.22.22`, et `go1.26.10` ;
  - le sha256 de `rebuild_deb.sh`, qui est celui de la copie de répétition (`1422b13d…`) ;
  - `policy.uri` `essai-non-figee` ;
  - `inputAttestations` sur le manifeste de `bundle-21edfa0ca581bad6`.
- **E4.** Les trois fichiers de la clé sont présents (`test -s`). Confiance haute : la VSA de l'image a été signée avec eux en R5.
- **E3 révisée.** Bilan : « refus attendu (3 KO …), énoncé construit mais non écrit, clé présente ».

## Résultats de `vsa_essai` (12/11/2026, 10:56:55 à 10:56:56 UTC, accord « Oui, lance-le »), code 0, rien de signé

Journal : `s6b-vsa_essai.log`. sha256 transportés, égaux côté hôte et côté VM : `vsa_deb.py` `2b353a7c…`, politique (projet) `4d5b4ec5…`.

| # | Résultat | Mesure |
|---|---|---|
| E1 | **Tenue** | Deux fichiers transportés, sha256 égaux |
| E2 | **Tenue** | `OK` : `verifie.txt`, verdict `PASSED`, manifeste `039949f9`, sortie 0, racine de la TSA, bundle unique de `454728c5` (`bundle-21edfa0ca581bad6`), signature de Chains et jeton de la TSA **sous `unshare -rn`**, énoncé identique à `provenance.json`, section 1. **Exactement trois `KO`** : porteuse à 1 au départ, porteuse à 1 à la fin, `timeVerified 2026-11-12T10:44:05Z` à moins de 24 h de `2026-11-11T21:03:37Z`. « REFUS : 3 condition(s) manquante(s), aucun énoncé écrit », code 1 ; aucun `enonce.json`. |
| E2 bis | **Tenue** | Prédicat construit : `PASSED` ; sbuild `0.89.3+deb13u4`, mmdebstrap `1.5.7-1+deb13u1`, dpkg-dev `1.22.22`, `go1.26.10` ; sha256 de `verifier_deb.py` (`7498fdad…`), de la copie de répétition de `rebuild_deb.sh` (`1422b13d…`) et de `vsa_deb.py` (`2b353a7c…`) ; `policy.uri` `essai-non-figee` ; `inputAttestations` : manifeste du bundle, `sha256:856a4270…` |
| E3 | **Tenue** | Bilan « refus attendu (3 KO …), énoncé construit mais non écrit, clé présente » ; rien n'est signé |
| E4 | **Tenue** | `cosign.key`, `cosign.pub` et `mot-de-passe` présents (`test -s`), non lus |

**Conséquence** : tout le chemin de `vsa_deb.py` a tourné dans la VM, hors réseau, sans rien écrire. Avec le résultat de `rebuild` lien coupé et après le délai, les trois conditions refusées ici doivent tenir. `vsa` n'aura plus qu'à signer.

## Note datée du 12/11/2026 (à partir de 10:59:06 UTC) : décision « Bit identique seul »

- **`rejeu/vsa_deb.py` est modifié** : `verifiedLevels` vaut `["POC_REPLAY_BIT_IDENTIQUE"]` seul. Son sha256 passe de `2b353a7c…` (celui de l'essai) à `34799510…`. Aucune autre ligne ne change.
- **L'essai de 10:56:55 UTC portait sur la version précédente.** La différence n'est que la liste des niveaux, dans l'énoncé construit ; les contrôles ne changent pas. Le sha256 de `vsa_deb.py` entre dans `verifier.version`. `vsa` refuse un `vsa_deb.py` modifié hors commit, ou un HEAD non poussé : c'est donc la version commitée et poussée qui signera.
- **Prédiction S1 révisée** : l'énoncé de `vsa` porte `"verifiedLevels": ["POC_REPLAY_BIT_IDENTIQUE"]`.

## Note datée du 12/11/2026 (à partir de 11:04:06 UTC) : politique approuvée

`POLITIQUE_COMMIT=97ae561de9e9eccb296fcba09fbbc351988ecf1b`, d'après l'approbation du propriétaire (« Oui, je l'approuve »). Prédiction S1 précisée :
- `policy.uri` vaut `https://github.com/gigi206/supply-chain/blob/97ae561de9e9eccb296fcba09fbbc351988ecf1b/poc/bricks/06-deb-sbuild/rejeu/politique-replay-deb.md` ;
- `policy.digest.sha256` vaut `6cc94a50ea8ca34c90485cc3eccb72e3484aeedd45e308bf1593ead0c547804b`.


## Note datée du 12/11/2026 (à partir de 11:58:09 UTC) : `verifier.version` attendu, et push préparé à sec

**Prédiction S1 précisée.** Les sha256 de `verifier.version` sont ceux des fichiers de HEAD, lus par `git show` :
- `verifier_deb.py` : `7498fdad…`, celui que `transporter` a copié dans la VM et que `verifier` a journalisé ;
- `rebuild_deb.sh` : `55ebf681…`, le script entier que `rebuild` transportera, et non plus la copie de répétition (`1422b13d…`) ;
- `vsa_deb.py` : `34799510…`, la version « Bit identique seul ».

**Le push de la VSA dans Zot est préparé à sec** : étapes `pousser_vsa` et `lire_vsa` de `s6b.sh`, prédictions dans [`s6b-pousser-predictions.md`](s6b-pousser-predictions.md). Elles viennent après S5b. Les étapes `rebuild` et `vsa` ne changent pas : le diff de `s6b.sh` n'ajoute que deux fonctions, quatre constantes, trois fonctions d'appui (`hors_zot` et `connexions`, reprises de la 10, et `anon`, la lecture anonyme), l'en-tête et la ligne d'usage.

## Résultats de `vsa` (12/11/2026, 21:20:08 à 21:20:10 UTC), code 0

Accord : « Oui, lance vsa » à « Je lance vsa ? », lancement le 12/11/2026 à 21:20:08 UTC (`chrono.tsv`). Journal : `s6b-vsa.log`. HEAD `c66202e` ; politique figée à `97ae561`.

| # | Résultat | Mesure |
|---|---|---|
| S1 | **Tenue** | 15 `OK`, 0 `KO`. Énoncé : sujet `builds/sample-app-deb` (`039949f9…`), `timeVerified` `2026-11-12T21:06:14Z` (`fin_deb` de `rebuild` : `2026-11-12T21:06:14Z`), `policy` au commit `97ae561` (sha256 `6cc94a50…`), `inputAttestations` `856a4270…`, `verifiedLevels` `['POC_REPLAY_BIT_IDENTIQUE']` ; `verifier.version` : sbuild `0.89.3+deb13u4`, mmdebstrap `1.5.7-1+deb13u1`, dpkg-dev `1.22.22`, `go1.26.10` ; `verifier_deb.py` `7498fdad…`, `rebuild_deb.sh` `55ebf681…`, `vsa_deb.py` `34799510…`, égaux aux fichiers de HEAD `c66202e` |
| S2 | **Tenue** | `signing-config sans service : code 0 ; {'mediaType': 'application/vnd.dev.sigstore.signingconfig.v0.2+json', 'rekorTlogConfig': {}, 'tsaConfig': {}}` ; `attest-blob : code 0` ; `verify-blob-attestation, clé du domaine : code 0 ; Verified OK` ; tlog `None`, horodatage `None`, énoncé du bundle identique à `enonce.json` ; sha256 lus dans la VM égaux aux copies archivées : énoncé `80e58b43…`, bundle `0a427031…` (2607 octets ; bundle non affiché) |

**Conséquence** : la VSA du deb est signée par la clé du domaine, hors réseau, et archivée dans `resultats/` (`s6b-vsa-enonce.json`, `s6b-vsa.bundle.json`). Rien n'est poussé dans Zot. Suite : S5b le 13/11, puis `pousser_vsa` et `lire_vsa`, chacun sur accord.
