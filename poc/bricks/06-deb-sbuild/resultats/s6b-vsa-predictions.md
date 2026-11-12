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
