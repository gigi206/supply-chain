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
