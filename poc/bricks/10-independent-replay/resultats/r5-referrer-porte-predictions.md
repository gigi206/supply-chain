# R5, mesure préalable : effet d'une VSA en referrer sur la porte de la 08 (prédictions écrites le 03/11/2026 à 11:16 UTC, avant toute exécution)

## Question

La politique (section 6) et D5 rangent la VSA en referrer OCI 1.1 de `builds/sample-app@sha256:3a7ca1b1…`, au format bundle Sigstore v0.3. Aujourd'hui, l'image n'a **aucun referrer** : la requête `referrers` du Zot du PoC rend un index vide, relevé à 11:15 UTC. La porte de la 08 juge les images par leurs tags `.sig` et `.att` (Chains en `dsse`).

La 08 a écarté ce rangement pour ses propres bundles. Le commentaire de `tsa/horodater.sh` dit que Kyverno « n'y lirait plus que les bundles et ignorerait .sig et .att ». La VSA pourrait donc changer ce que la porte charge pour l'image réelle. Ce rangement est mesuré avant tout push.

## Banc (aucune écriture dans le Zot du PoC ni dans le cluster)

- **Copie de l'image** :
  - l'image `3a7ca1b1`, son tag `.sig` (`925a1ff8…`, 626 octets) et son tag `.att` (`e7045fa8…`, 1 888 octets) sont copiés du Zot du PoC, en lecture anonyme, dans un layout OCI local ;
  - ils sont ensuite poussés dans un **Zot jetable** v2.1.22 (même version que `sc-stockage`, `mise.lock`), dans un espace de noms réseau vide ;
  - les digests sont vérifiés égaux à ceux du PoC après la copie.
- **Outils** :
  - **ec v0.10.42**, même empreinte que l'image de la porte (`895c6f7e…`) ;
  - même `policy.yaml`, chemins réécrits vers des copies locales : bibliothèque `conforma/policy` au commit `ebd3fbd2`, `porte.rego`, `taches.yml`, clé de Chains ;
  - mêmes options que le Job de la porte : `--image`, `--ignore-rekor`, `--info`, `--show-successes`, `--strict=false`.
- **Referrer** : créé comme en R5, par `oras attach`, avec l'artifactType bundle v0.3 et les annotations `dev.sigstore.bundle.*`. Il contient un énoncé VSA signé par `cosign attest-blob` avec une **clé jetable** (pas la clé du domaine).
- **Mesures, avant puis après l'ajout du referrer** :
  - sortie JSON de ec : nombre de signatures d'image et d'attestations, leurs `keyid` et `predicateType`, succès, violations (dont `porte.image_signature` et `builtin.*`) ;
  - `cosign verify --key chains.pub` et `cosign verify-attestation --key chains.pub --type slsaprovenance1` (cosign 3.1.4, sans drapeau de format), comme dans `preuves.sh`.
- **Hors banc, lu seulement** :
  - le contrôle 9 de la porte (`horodatage.sh`) lit les bundles de `horodatage/bundles` (`COSIGN_REPOSITORY`), pas les referrers de l'image ;
  - le replay (`entrees.py`) lit le tag `.att` par son nom ;
  - aucune `ImageValidatingPolicy` ne porte sur `builds/**` : seule `bench-release` est en service, relevé à 11:13 UTC.

## Prédictions

1. **Avant le referrer** : ec charge 1 signature d'image et 6 attestations, qui sont les 6 enveloppes du tag `.att` relevées en D5. La porte admet : `success` vrai, avec l'avertissement `trusted_task.tagged` du test 7. cosign vérifie la signature et les attestations.
2. **Après le referrer** :
   - je n'ai **pas lu** le code de ec v0.10.42 ni celui de cosign 3.1.4 sur ce choix ;
   - faits connus :
     - au test 8, ec a trouvé des attestations et une signature d'image rangées **seulement** en referrers ;
     - en R5 (`signature_hors_registre`), `cosign verify-attestation` sans drapeau a trouvé un bundle en referrer ;
     - la 08 décrit une bascule de Kyverno vers les seuls bundles ;
   - **hypothèse principale** : ec et cosign détectent les bundles en referrer et **ne lisent plus `.sig` ni `.att`** :
     - ec ne voit plus que le bundle VSA, signé par une autre clé ;
     - **la porte refuse l'image réelle** : `porte.image_signature` (0 signature) et un échec de vérification des attestations ;
     - cosign refuse aussi (`no matching attestations` ou `no signatures found`) ;
   - **hypothèse concurrente** : les deux formats sont fusionnés, et rien ne change ; la VSA, signée par une autre clé, est écartée.
3. **Digests** : identiques à ceux du PoC après la copie. Sinon, le banc n'est pas valable.

## Suites selon le résultat

- **Rien ne change** : le rangement de la section 6 tient, et R5 garde son plan.
- **Ce que ec ou cosign chargent change** : je m'arrête, et le rangement revient au propriétaire. Un dépôt séparé, sur le modèle de `horodatage/bundles`, toucherait aux droits de `poc-replay` (création par digest sous `builds/**`).
- **ec refuse le HTTP sur 127.0.0.1** : c'est un défaut du banc, pas un verdict. Passage en TLS avec une CA jetable, sans interpréter les sorties précédentes.

## Contraintes d'exécution

- Le script est **hors de `replay.sh`** jusqu'à la fin de R4 : R4 lit `replay.sh` à 14:00 UTC, et le sha256 du code du domaine entre dans la VSA. Il vit dans le dossier temporaire de la session et sera intégré à `replay.sh` après R4.
- Aucun push dans le Zot du PoC, aucune écriture dans le cluster.

## Additif du 03/11/2026 à 11:19 UTC, après le premier passage et avant le second

**Premier passage** (11:17 à 11:18 UTC), archivé dans [`r5-referrer_porte-premier-passage.log`](r5-referrer_porte-premier-passage.log). ec y est lancé par `--image`, comme en J6, sans source attendue.

- **Avant le referrer** :
  - 1 signature d'image et 6 attestations, toutes de la clé de Chains ;
  - 3 avertissements `trusted_task.tagged` ;
  - une violation, `slsa_source_correlated.source_code_reference_provided`.

  Ma prédiction 1 (« la porte admet ») était donc **fausse sur ce point** : sans source attendue, ec refuse. La porte n'admet l'image réelle qu'avec la source attendue (`--images`, tests 7 et 8). Je l'avais omise.
- **Après le referrer** :
  - 0 signature d'image et 0 attestation ;
  - violations `builtin.image.signature_check` et `builtin.attestation.signature_check` ;
  - `cosign verify` et `cosign verify-attestation` refusent avec la clé de Chains ;
  - la clé jetable de la VSA est acceptée.

  C'est l'hypothèse principale de la prédiction 2.
- **Défaut du banc** : ec tente 9 fois de lire les bundles de tâches (`ec.oci.image_manifest`) sur `sc-stockage.poc.test`, sans DNS ni réseau. Ces 9 lectures échouent.

  Ce défaut ne change pas ce que ec charge. Il peut changer des résultats de règles, et le verdict complet de la porte n'est donc pas reproduit à l'identique.

**Second passage** : ec est lancé deux fois par mesure, `--image` puis `--images` avec la source attendue des tests 7 et 8 (Forgejo `workspace/sample-app`, `6391fd43…`).

Prédictions :
- **avec la source, avant le referrer** : `success` vrai, avec les 3 avertissements `trusted_task.tagged` ;
- **après le referrer** : `success` faux, 0 signature, 0 attestation, dans les deux modes ;
- les 9 échecs de lecture se répètent.

## Résultat du second passage (11:19 à 11:21 UTC) : [`r5-referrer_porte.log`](r5-referrer_porte.log)

- **Digests** : identiques au PoC après la copie (image, `.sig`, `.att`). Le banc est valable.
- **Avant le referrer** :
  - avec la source attendue, `success` vrai : 33 succès, 0 violation, 3 avertissements `trusted_task.tagged` ;
  - sans la source, la seule violation est `source_code_reference_provided` ;
  - cosign vérifie la signature d'image et les 6 attestations.
  - **Conforme.**
- **Après le referrer**, dans les deux modes :
  - `success` faux : 0 signature, 0 attestation, `builtin.image.signature_check` et `builtin.attestation.signature_check` en violation ;
  - `cosign verify` et `cosign verify-attestation` refusent avec la clé de Chains (`Found: 0, Expected 1`) ;
  - la clé de la VSA est acceptée.
  - **Conforme à l'hypothèse principale.** La vérification de la signature d'image elle-même cherche dans le bundle et non plus dans `.sig`.
- **Les 9 échecs de lecture** se répètent avant le referrer, mais **pas après** : ec s'arrête aux vérifications de signature, avant les règles. J'avais prédit qu'ils se répéteraient : **faux**, sans effet sur la conclusion.

**Constat** : ranger la VSA en referrer de `builds/sample-app@3a7ca1b1`, comme le prévoient la section 6 et D5, ferait **refuser l'image réelle par la porte de la 08** et par `cosign verify` avec la clé de Chains. La 08 avait écarté ce rangement pour ses bundles d'horodatage pour cette raison, dite pour Kyverno dans `tsa/horodater.sh`. Elle est mesurée ici pour ec et cosign. **Rien n'est poussé.** Le rangement revient au propriétaire.

## Additif du 03/11/2026 à 11:21 UTC : mesure de l'alternative, avant toute exécution

Le modèle est celui de `horodatage/bundles` (08, `tsa/horodater.sh`) :
- un manifeste fait main dont le `subject` est le descripteur de l'image, rangé dans **un autre dépôt** ;
- poussé **par digest**, sans étiquette, comme le permettent les droits de `poc-replay` ;
- le nom de dépôt du banc, `builds/vsa/sample-app`, sert seulement d'illustration : le choix du nom revient au propriétaire.

Même banc (Zot jetable, copie de l'image, de `.sig` et de `.att`). Prédictions :
1. **Push sans étiquette** : Zot accepte le manifeste poussé par digest, alors que le sujet est absent de ce dépôt. L'API referrers du dépôt séparé le liste, et ce dépôt n'a aucune étiquette.
2. **Image réelle** : aucun referrer dans `builds/sample-app`. ec, avec la source attendue, rend `success` vrai, et cosign vérifie la signature et les 6 attestations, comme avant.
3. **Lecture de la VSA** : `COSIGN_REPOSITORY=…/builds/vsa/sample-app cosign verify-attestation --key <clé de la VSA> --type https://slsa.dev/verification_summary/v1` sur l'image l'accepte. La clé de Chains la refuse.

## Résultat de l'alternative (11:22 à 11:23 UTC) : [`r5-referrer_depot_separe.log`](r5-referrer_depot_separe.log)

1. **Conforme.**
   - Zot accepte le push par digest, sous le digest `d31dffa0…`.
   - L'API referrers de `builds/vsa/sample-app` le liste, et ce dépôt n'a aucune étiquette (`tags: []`).
   - `builds/sample-app` n'a aucun referrer.
2. **Conforme.** ec, avec la source attendue, rend `success` vrai : 1 signature, 6 attestations, 33 succès, 3 avertissements. cosign accepte la signature et les 6 attestations avec la clé de Chains.
3. **Conforme.** Par `COSIGN_REPOSITORY`, la clé de la VSA vérifie 1 attestation ; la clé de Chains est refusée (`Found: 0, Expected 1`).

**Complément, lecture seule du cluster** : le passage du job d'horodatage de 11:23:00 à 11:23:04 UTC compte 12 images et 54 enveloppes, avec 1 anomalie. Cette anomalie est le témoin connu `builds/essai-j6-att-illisible`. `builds/essai-replay` n'en produit aucune, alors qu'il est sans étiquette et porte un referrer depuis D5.
