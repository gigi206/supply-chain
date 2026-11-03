# Politique du replay indépendant (brique 10)

C'est la politique que le domaine de replay applique. La VSA la cite dans `policy.uri`, avec son digest : le sha256 de ce fichier au commit qui la fige, avant R5. `policy.uri` est l'URL GitHub du fichier à ce commit (choix du propriétaire du 03/11/2026).

Le domaine est administré par le propriétaire, par écart documenté (D1 b). Il est hébergé dans la VM `sc-replay`, sur le même hyperviseur que le plan de confiance (D2 a). L'indépendance est donc technique, pas organisationnelle.

## 1. Provenance acceptée

Chaque condition est éliminatoire : un échec arrête le replay avant tout build.

1. L'enveloppe DSSE est tirée du tag `.att` de l'image, en lecture anonyme. Sa signature est vérifiée avec la clé publique de Chains, [`chains-cle-publique.pem`](../08-trust-plane/resultats/chains-cle-publique.pem), prise hors bande dans ce dépôt.
2. `_type` vaut `https://in-toto.io/Statement/v1` et `predicateType` vaut `https://slsa.dev/provenance/v1`.
3. `runDetails.builder.id` vaut `https://supply-chain.example/builders/tekton-chains@v1`, et `buildDefinition.buildType` vaut `https://tekton.dev/chains/v2/slsa-tekton`.
4. Le sujet est l'image rejouée, et son digest est celui comparé au point 4.
5. `resolvedDependencies` déclare :
   - le commit (`git+https://…/workspace/sample-app.git`, `sha1`) ;
   - la fermeture (`entrees/sample-app/fermeture`) ;
   - `web/dist` (`entrees/sample-app/web-dist`) ;
   - l'image de build ;
   - le bundle de la tâche `preparer-entrees` (préparation du contexte) ;
   - le bundle de la tâche `construire-image` (construction).

   Chacune de ces entrées a un digest.

## 2. Entrées et recette

- **Commit** : cloné depuis Forgejo, puis comparé au `sha1` déclaré.
- **Fermeture et `web/dist`** : tirés par digest dans Zot, puis digest recalculé.
- **Recette** : extraite du bundle `construire-image`, par le digest déclaré.
  - Le Dockerfile y est intégré, et la tâche le contrôle par son sha256.
  - Les options de `buildctl` sont reprises telles quelles : `--no-cache`, `SOURCE_DATE_EPOCH=0`, contextes `builder` et `deps`, sortie OCI avec `rewrite-timestamp=true`.
  - Aucune option n'est prise dans ce dépôt. Une option absente du bundle est un constat sur la complétude de la provenance.
- **Contexte de build** : il est reproduit d'après le script du bundle `preparer-entrees`, dont le digest est comparé à la provenance :
  - `git archive` du commit dans `src` ;
  - la fermeture dans `deps` ;
  - `web-dist` dans `src/web/dist`.

  Si l'une de ces trois opérations manque au script, le replay est refusé.
- **Image de build déclarée** : elle sert seulement à lire la version de Go (`usr/local/go/VERSION`) et son environnement (`config.Env`). Son contenu n'est ni exécuté ni réutilisé.

## 3. Indépendance du build

- **Image de build reconstruite dans le domaine** :
  - toolchain Go officielle de go.dev, de la même version, vérifiée par le sha256 publié ;
  - busybox du paquet Debian `busybox-static` ;
  - **exactement l'`Env` de l'image de build déclarée**, lu dans son blob de configuration vérifié.
- **Seul écart volontaire à la recette signée** : le digest de l'image de build (`context:builder=oci-layout://…@<digest>`), qui est celui de l'image du domaine. Toute autre différence est consignée comme un constat.

  Son digest est consigné, pas comparé : la brique 04 a mesuré qu'il varie d'un hôte à l'autre alors que l'image produite ne change pas.
- **Moteur** : BuildKit 0.25.2 (archive vérifiée, `mise.lock`), et non la version de l'image de la tâche Tekton. Le moteur n'est pas celui du plan de confiance.
- **Caches froids** : VM neuve et `--no-cache`.
- **Sans réseau pendant le build** (D4) : le lien de la VM est coupé, et les compteurs de son interface sont relus depuis l'hôte, avant et après le build.
- **Délai** : `timeVerified` est au moins 24 h après `runDetails.metadata.finishedOn` de la provenance.

## 4. Verdict

- **`PASSED`** si toutes les conditions des sections 1 à 3 tiennent, et si **le digest de l'image reconstruite est égal au digest du sujet**.
- **`FAILED`** sinon. Un rapport diffoscope entre l'image reconstruite et l'image publiée est alors archivé.
- **Second moteur, consigné sans entrer dans le verdict** : le binaire extrait de l'image est comparé au binaire d'un `go build` direct, avec la même toolchain et les mêmes options.

## 4 bis. Code du domaine

- Le code qui vérifie et reconstruit est versionné dans ce dépôt : `outils/verifier_entrees.py` et `outils/rebuild.sh`. Il est copié dans la VM par l'hôte.
- Ce code n'est pas vérifié par le domaine lui-même. Son sha256 est journalisé à chaque passage et **inscrit dans la VSA** (`verifier.version`). N'importe qui peut ainsi confronter le code qui a produit la VSA à ce dépôt.
- Les données, elles, ne sont crues qu'après vérification : signatures, digests et commit.

## 5. Niveaux revendiqués (`verifiedLevels`)

- `SLSA_BUILD_LEVEL_3` : si la section 1 tient (signature de Chains, `builder.id` attendu). Ce niveau repose sur les mesures de la brique 08 (isolation, clé hors des nœuds de build). Le replay ne les refait pas.
- `POC_REPLAY_BIT_IDENTIQUE` : si le verdict est `PASSED`. C'est une valeur propre au PoC, sans le préfixe `SLSA_` réservé.
- `FAILED` : si le verdict est `FAILED`.

## 6. Signature et rangement de la VSA

- **`verifier.id`** : `https://supply-chain.example/verifiers/replay-poc-administrateur-unique@v1`. L'identifiant porte l'écart D1 (b) : domaine et plan de confiance ont le même administrateur.
- **`verifier.version`** : versions de BuildKit et de Go, et sha256 de `verifier_entrees.py` et de `rebuild.sh`.

- **Clé** : clé cosign du domaine, générée dans la VM (D6). Jamais celle de Chains, ni l'OpenBao du plan de confiance.
- **Signature** : `cosign attest --signing-config` avec une configuration sans aucun service, donc sans Fulcio, Rekor ni TSA. Mesuré en R1 : sans cette configuration, cosign 3.1.4 interroge le TUF public de Sigstore.
- **Rangement** : en referrer OCI 1.1 de l'image (format bundle Sigstore v0.3, sans tag `.att`), **dans le dépôt séparé `builds/vsa/sample-app`**, et non dans celui de l'image.
  - Le manifeste est fait main : son `subject` est le descripteur de l'image. Il est poussé par digest, sans étiquette, par le compte Zot `poc-replay` en création par digest seulement (D5).
  - Chaque push est soumis à l'accord du propriétaire.
  - **Raison, mesurée le 03/11/2026** : un referrer de type bundle dans le dépôt de l'image fait ignorer `.sig` et `.att` par ec et cosign, et la porte de la 08 refuserait l'image.
  - **Lecture** : `COSIGN_REPOSITORY=<registre>/builds/vsa/sample-app cosign verify-attestation --key <clé de la VSA> --type https://slsa.dev/verification_summary/v1 <image>`.

## Limites

- `web/dist` est pris par digest et n'est pas reconstruit : Node reste hors de la chaîne, par choix du propriétaire.
- Avec D1 (b) et D2 (a), le propriétaire, ou le root de l'hôte, peut forger à la fois la provenance et la VSA.
