# R5, VSA et contre-épreuves : prédictions (écrites le 03/11/2026, avant toute exécution)

## Mesure préalable sur l'hôte, signature hors registre (écrite vers 10:33 UTC)

La VM ne joint aucun registre (R2) : elle ne peut pas utiliser `cosign attest`, qui résout l'image dans un registre. La mesure se fait comme en R1, dans un espace de noms sans réseau, avec un Zot jetable, une image jetable et des clés jetables.

1. `cosign attest-blob --statement vsa-enonce.json --key … --signing-config <vide> --bundle vsa.bundle.json`, **sans registre**, produit un bundle Sigstore v0.3. Son enveloppe DSSE contient l'énoncé tel quel, dont `subject` = nom et digest de l'image, et non un nom de fichier.
   - Attente incertaine : `attest-blob` pourrait exiger un blob, ou réécrire le sujet.
2. Ce bundle, poussé par `oras` comme manifeste referrer (`artifactType application/vnd.dev.sigstore.bundle.v0.3+json`, `subject` = descripteur de l'image), sur le modèle de `horodater.sh` de la 08 :
   - apparaît dans l'API referrers de l'image ;
   - est trouvé et vérifié par `cosign verify-attestation --key <pub> --insecure-ignore-tlog --type https://slsa.dev/verification_summary/v1 <image>`, comme l'attestation de R1 rangée par cosign lui-même.

   C'est également incertain : cosign pourrait exiger des annotations précises.
3. Il est vérifié aussi par `cosign verify-blob-attestation --bundle … --new-bundle-format --key <pub> --insecure-ignore-tlog --digest <image> --digestAlg sha256`. Avec la clé de Chains au lieu de la clé de VSA, la vérification est **refusée**.

### Résultat (03/11/2026, 10:34 UTC) : [`r5-signature_hors_registre.log`](r5-signature_hors_registre.log)

1. **Conforme.** `attest-blob --statement` signe **sans registre** et produit un bundle `application/vnd.dev.sigstore.bundle.v0.3+json`. L'énoncé de l'enveloppe est **identique** au fichier fourni, sujet compris (nom et digest de l'image). Pas d'entrée de journal, pas d'horodatage.
2. **Conforme.** `oras attach` (`artifactType` bundle v0.3, annotations `dev.sigstore.bundle.*`) crée un referrer et aucun tag. `cosign verify-attestation` le **trouve sur l'image et le vérifie** avec la clé de VSA. Avec une autre clé, il le refuse (`no matching attestations … Found: 0, Expected 1`).
3. **Conforme.** `verify-blob-attestation --bundle` donne `Verified OK` avec la clé de VSA, et un refus avec une autre clé.

**Chemin retenu pour R5** :
- dans la VM : `cosign attest-blob --statement` avec la clé du domaine et la configuration vide ;
- par l'hôte : transport du bundle, puis `oras attach` avec le compte `poc-replay` (D5), après accord ;
- vérification par `cosign verify-attestation` sur l'image.

## Contre-épreuves (écrites le 03/11/2026 vers 10:36 UTC ; exécutées dans la VM, après R4)

Elles ne prouvent pas le « hors ligne » : seul le replay positif de R4 le porte. Elles tournent dans la VM, sur des **copies** des entrées vérifiées ; les originaux ne sont pas touchés.

- **N1, fermeture altérée** (un octet changé dans une copie d'un zip de module Go de `deps`) : le build est **refusé**, parce que Go contrôle le zip contre `go.sum` (`checksum mismatch` ou `SECURITY ERROR`). Il n'y a pas d'image, donc rien à comparer : verdict `FAILED`, VSA ni signée ni poussée.
- **N2, source altérée** (une chaîne changée dans une copie de `src`, par exemple `main.Version` dans le code) : le build **réussit**, avec un **digest différent** de `3a7ca1b1`. Verdict `FAILED`, VSA non poussée. Le rapport **diffoscope** entre l'image publiée et l'image reconstruite, archivé, montre une différence dans le binaire `sample-app` et nulle part ailleurs.
- **N3, clés croisées** : la VSA vérifiée avec la **clé de Chains** est refusée, et la provenance vérifiée avec la **clé de VSA** aussi.

## Additif du 03/11/2026 à 12:01 UTC : rangement révisé avant toute exécution de R5

- **Mesure préalable** : [`r5-referrer-porte-predictions.md`](r5-referrer-porte-predictions.md). Une VSA en referrer de `builds/sample-app` ferait refuser l'image réelle par la porte de la 08.
- **Choix du propriétaire** : « (a) Dépôt séparé ».
- **Conséquences pour les prédictions de R5** :
  - la VSA est poussée dans `builds/vsa/sample-app` par un manifeste fait main, poussé par digest, au lieu d'`oras attach` sur l'image ;
  - elle est lue par `COSIGN_REPOSITORY` ;
  - **ajout** : après le push, la porte de la 08 doit admettre l'image réelle, comme avant le push. C'est une nouvelle prédiction, à vérifier dans le cluster.

## Additif du 03/11/2026 à 13:13 UTC : prédictions précisées, avant toute exécution de R5 (et avant R4)

Préparation à sec : relecture de `main.go`, de la recette et du stockage des modules Go. Les lignes précédentes ne sont pas modifiées ; celles-ci les précisent.

- **N2, ce qui est altéré** : `main.Version` est imposée par `-ldflags -X` à la compilation, donc la changer dans le code ne changerait pas le binaire. N2 change le littéral compilé `":8080"` de `main.go` en `":8081"` (une seule occurrence, contrôlée avant).
- **N2, diffoscope** : « une différence dans le binaire `sample-app` et nulle part ailleurs » vaut pour le **contenu de la couche**. La configuration de l'image diffère aussi, par conséquence (`rootfs.diff_ids`). Le manifeste et l'index diffèrent par les digests et ne sont pas comparés.
- **N1, ce qui est altéré** : un octet du contenu d'un fichier `.go` du zip de `go-chi/chi/v5`, le zip étant réécrit et **resté valide** (`testzip` consigné). Seul le contrôle de Go contre `go.sum` peut donc le refuser. Motif attendu : `checksum mismatch` et `SECURITY ERROR`.
- **Porte de la 08, avant et après le push de la VSA** : le même verdict. `success` vrai, aucune violation, contrôle 9 `ok` avec le même nombre d'enveloppes couvertes. Mesure dans le cluster : un Job de la porte par passage.
- **CronJob d'horodatage** : aucune anomalie pour `builds/vsa/sample-app` au passage suivant le push. Attente **incertaine** : le précédent, `builds/essai-replay`, contenait une image, alors que `builds/vsa/sample-app` n'aura qu'un manifeste dont le sujet est absent du dépôt.
- **Accès au TUF public** : aucun pendant la signature et la vérification dans la VM, qui tournent sous `unshare -rn`. Que `unshare -rn` fonctionne pour l'utilisateur `replay` dans la VM n'est **pas mesuré**. Sur l'hôte, les `connect()` de cosign pendant la lecture de la VSA sont relevés par `strace`.

## Additif du 03/11/2026 à 14:56 UTC : intégration à `replay.sh`, défaut de `vsa.py` corrigé, prédictions de l'étape `vsa` (rien exécuté)

**Défaut trouvé avant toute exécution.**
- `outils/vsa.py` (commit `90043b6`) lisait les bundles et la racine de la TSA dans `~/r3/travail/`. Or `verifier_entrees.py` vide ce dossier à la fin de R3 : relevé en lecture seule dans la VM, il est vide.
- Lancé tel quel, `vsa.py` aurait refusé l'énoncé (« bundle de l'invocation : None »).
- **Correction** : `vsa.py` refait lui-même, dans `~/r5/travail`, la racine de la TSA (`cosign trusted-root create`, avec l'identifiant de la TSA en 5ᵉ argument) et le bundle. Il extrait le bundle du layout de R3 en lecture seule, avec `oras`, comme `verifier_entrees.py`.
- Il exige **un seul** bundle portant l'`invocationId`, et prend le digest de `inputAttestations` sur le manifeste extrait.
- `~/r3` et `~/r4` ne sont pas touchés, et `verifier_entrees.py` n'est pas relancé : il réécrirait `provenance.json` et `recette/`, que R4 a consommés.

**Intégration.** Les étapes `vsa`, `porte_avant`, `pousser_vsa`, `porte_apres`, `lire_vsa` et `negatifs` sont ajoutées à `replay.sh`, avec ces changements par rapport aux brouillons :
- `etape_vsa` refuse de partir dans trois cas :
  - `outils/vsa.py` diffère du commit ;
  - `HEAD` n'est pas poussé ;
  - le commit de la politique n'est pas poussé.

  Le sha256 de `vsa.py` entre dans `verifier.version` et doit pouvoir être confronté au dépôt.
- Les codes de sortie de `attest-blob` et de `verify-blob-attestation` sont lus et affichés (sans `set -e`). La vérification dans la VM se fait sans `--trusted-root`, comme V1 dans `r5-tuf.log`.
- **Porte** : deux étapes, `porte_avant` et `porte_apres`, pour deux journaux ; la seconde compare les lignes `VERDICT` sans la durée.
- **Sur l'hôte**, chaque commande cosign de `pousser_vsa` et de `lire_vsa` tourne sous `strace -e trace=connect`. C'est un **contrôle** : `KO` dès qu'une connexion vise autre chose que `192.168.161.13:5000`. L'extraction est celle de `essais/tuf-verification-cle.sh`.

**Prédictions de l'étape `vsa`** (valeurs connues d'avance, relevées dans la VM en lecture seule ou dans les journaux) :

1. Les trois gardes passent (commit `309644f` et `HEAD` poussés, `vsa.py` propre). Le sha256 de la politique au commit vaut `4f1cca93f20945ee5f168b4e3f42a189c4c6ecbbc6a401199d4c187b6c2f2450`.
2. `vsa.py`, sous `unshare -rn` :
   - `verdict de R4 : PASSED` et image reconstruite `3a7ca1b1…` ;
   - racine de la TSA construite ;
   - un seul bundle de l'invocation parmi 43 : `bundle-7af184de44b81e66` (celui de R3) ;
   - signature de Chains et jeton de la TSA vérifiés ;
   - énoncé identique à `~/r3/provenance.json` ;
   - les contrôles de la politique tous `OK` ;
   - délai : `timeVerified` `2026-11-03T14:27:05Z`, soit 24 h 27 min 35 s après `finishedOn` (`2026-11-02T13:59:30Z`).

   **Attente incertaine** : `cosign trusted-root create` et `verify-blob-attestation --use-signed-timestamps --trusted-root` n'ont tourné dans la VM qu'avec le réseau (R3), jamais sous `unshare -rn`. Un échec ici serait un refus de `vsa.py`, sans énoncé.
3. Énoncé :
   - `subject` = `sc-stockage.poc.test:5000/builds/sample-app`, sha256 `3a7ca1b1…` ;
   - `resourceUri` = `oci://sc-stockage.poc.test:5000/builds/sample-app@sha256:3a7ca1b1…` ;
   - `policy` = `https://github.com/gigi206/supply-chain/blob/309644f…/poc/bricks/10-independent-replay/politique-replay.md`, avec le digest `4f1cca93…` ;
   - `inputAttestations` = `oci://sc-stockage.poc.test:5000/horodatage/bundles@sha256:f5969ecfd00414058a49cf18af8f1adde2932860b0fc027cccbc53eed90860a8`, avec ce même digest ;
   - `verifier.version` :
     - `buildkit` = `buildkitd github.com/moby/buildkit v0.25.2 dcc0fe5e…` ;
     - `go` = `go1.26.10` ;
     - `verifier_entrees.py` = `66fa5cb4…` ;
     - `rebuild.sh` = `a1945ff2…` ;
     - `vsa.py` = `734fb1a8a372997208eed30137483d4e6030078611964ce65da332ee29c6d540` ;
   - `verificationResult` `PASSED`, `verifiedLevels` = `SLSA_BUILD_LEVEL_3` et `POC_REPLAY_BIT_IDENTIQUE`.
4. **Signature** :
   - `signing-config` sans service : code 0 ;
   - `attest-blob` : code 0 ;
   - `verify-blob-attestation` avec la clé du domaine, sans `--trusted-root` : code 0, `Verified OK` ;
   - bundle `application/vnd.dev.sigstore.bundle.v0.3+json`, sans entrée de journal ni horodatage, énoncé identique à `enonce.json` (comme en `r5-signature_hors_registre.log`).
5. **Sur l'hôte** (`pousser_vsa`, avant tout push) : le bundle archivé est vérifié avec `resultats/vsa-cle-publique.pem`, sans aucune connexion. `builds/vsa/sample-app` n'existe pas encore : relevé à 14:56 UTC, `tags/list` rend 404.
6. **`lire_vsa`** : les cinq commandes cosign ne se connectent qu'à `192.168.161.13:5000` (r5-tuf.log : aucune tentative vers le TUF public pour des vérifications par clé, réussies ou refusées).

### Résultat de l'étape `vsa` (03/11/2026, 14:57 UTC, choix du propriétaire : « Pousser et lancer vsa ») : [`r5-vsa.log`](r5-vsa.log)

`ad135ba` a été poussé avant le lancement. `POLITIQUE_COMMIT` a été passé en hash complet, `309644f4ef610383f6fd180e5c058846487ab016` : c'est lui que porte `policy.uri`.

1. **Conforme.** Les gardes passent. La politique au commit et sa copie dans la VM ont pour sha256 `4f1cca93…`, et `vsa.py` `734fb1a8…`, identique au fichier de `HEAD`.
2. **Conforme, attente incertaine levée.** Sous `unshare -rn`, `cosign trusted-root create` et la vérification horodatée du bundle réussissent sans réseau dans la VM.
   - `bundle-7af184de44b81e66` est le seul des 43 bundles à porter l'invocation.
   - L'énoncé est identique à celui de R3.
   - Tous les contrôles de la politique sont `OK`, délai compris.
3. **Conforme.** L'énoncé porte exactement les valeurs prédites :
   - `subject` et `resourceUri` ;
   - `policy` (URL au commit `309644f4…`, digest `4f1cca93…`) ;
   - `inputAttestations` `f5969ecf…` ;
   - `verifier.version` (BuildKit `v0.25.2 dcc0fe5e…`, `go1.26.10`, `66fa5cb4…`, `a1945ff2…`, `734fb1a8…`) ;
   - `PASSED`, `SLSA_BUILD_LEVEL_3` et `POC_REPLAY_BIT_IDENTIQUE`.

   Il porte aussi `slsaVersion` `1.2`, que la prédiction ne citait pas.
4. **Conforme.** Toute la signature passe sans réseau, dans la VM :
   - la configuration de signature n'a aucun service (`rekorTlogConfig` et `tsaConfig` vides) ;
   - `attest-blob` rend le code 0 ;
   - `verify-blob-attestation` avec la clé du domaine rend `Verified OK` ;
   - le bundle est en v0.3, sans entrée de journal ni horodatage, et son énoncé est identique à `enonce.json`.
5. et 6. Non mesurées : elles relèvent de `pousser_vsa` et `lire_vsa`.

Copies archivées : [`r5-vsa-enonce.json`](r5-vsa-enonce.json) (sha256 `c804d946…`) et [`r5-vsa.bundle.json`](r5-vsa.bundle.json) (sha256 `7b93e4b3…`), identiques aux fichiers de la VM. Rien n'a été poussé sur Zot.

## Additif du 03/11/2026 à 14:58 UTC : prédictions de `porte_avant` (avant exécution ; choix du propriétaire : « Lancer porte_avant »)

Relevé anonyme fait juste avant, à 14:58:35 :
- 6 enveloppes dans le tag `.att` de l'image ;
- 43 bundles horodatés de l'image dans `horodatage/bundles` ;
- 0 referrer de l'image dans `builds/sample-app` ;
- `builds/vsa/sample-app` absent (404 à 14:56).

Le précédent est le cas `reel` du test 8 (02/11) : `VERDICT|t8-reel|true||…|ok|2/2 enveloppe(s) couverte(s), 33 bundle(s) vérifié(s)`.

1. Referrers : `builds/sample-app 0` ; `builds/vsa/sample-app` « absent ou illisible ».
2. Enveloppes de Chains sur l'image : 6.
3. ec admet l'image réelle, sans aucune violation : `VERDICT|reelle-avant|true||…`.
4. Contrôle 9 `ok`, « 6/6 enveloppe(s) couverte(s), 43 bundle(s) vérifié(s) ». Le nombre de bundles est **incertain** : le CronJob d'horodatage peut en ajouter entre le relevé et le Job.
