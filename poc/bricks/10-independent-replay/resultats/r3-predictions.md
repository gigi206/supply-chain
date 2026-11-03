# R3, préchargement : prédictions (écrites le 03/11/2026 vers 10:15 UTC, avant toute exécution)

Accord du propriétaire : « Oui, lancer R3 ». Aucun build et aucun push : R4, le rebuild, ne commence pas avant le **03/11/2026 à 13:59:30 UTC**.

## Étapes (`JALON=r3 mise run replay -- transporter verifier_entrees`)

1. **`transporter`**, sur l'hôte, qui n'est qu'un transport non fiable : rien de ce qu'il apporte n'est cru sans vérification dans la VM.
   - Copie anonyme (oras) dans un layout OCI : l'image `builds/sample-app@3a7ca1b1…`, son tag `.att`, les bundles horodatés `horodatage/bundles:3a7ca1b1…-*`, et les quatre entrées déclarées (`construire-image`, fermeture, `web-dist`, `builder-go-voie-d`). Les digests sont lus dans la provenance non vérifiée, ce qui suffit pour un transport.
   - Bundle git de `main`, cloné sans compte depuis Forgejo.
   - Ancres de confiance prises dans ce dépôt : `chains-cle-publique.pem` et `tsa-chaine.pem`.
   - Le tout est copié dans la VM, `~/r3`.
2. **`verifier_entrees`**, **dans la VM**, hors de tout accès à Zot et à Forgejo :
   1. Racine de confiance de la TSA construite dans la VM (`cosign trusted-root create`), à partir de `tsa-chaine.pem`.
   2. Chaque bundle horodaté est vérifié hors réseau (`cosign verify-blob-attestation --new-bundle-format --key chains.pub --use-signed-timestamps --trusted-root …`) : signature de Chains, sujet égal au digest de l'image, jeton RFC 3161. La provenance du PipelineRun `d9006af7…` est **extraite d'un bundle vérifié**, jamais du transport.
   3. Contrôles de la politique, section 1 : `_type`, `predicateType`, `builder.id`, `buildType`, et les entrées requises.
   4. Digest de chaque entrée transportée recalculé et comparé au digest déclaré ; commit du bundle git comparé au `sha1` déclaré.
   5. Recette extraite du bundle `construire-image` : le Dockerfile, contrôlé par le sha256 que la tâche contient, et les options de `buildctl`.
   6. Version de Go relue dans l'entrée `builder-go-voie-d` vérifiée.
   7. Heure du build : `finishedOn` signé, et heure du jeton de la TSA.

## Prédictions

1. **Transport** : toutes les copies réussissent en lecture anonyme, et rien n'est écrit dans Zot ni dans Forgejo.
2. **Bundles** : il y a **six** bundles horodatés pour `3a7ca1b1`, un par enveloppe du tag `.att`. Chacun se vérifie hors réseau ; **un seul** contient la provenance `d9006af7…`.
3. **Politique, section 1** : tous les contrôles passent. `builder.id` vaut `https://supply-chain.example/builders/tekton-chains@v1`, et `buildType` vaut `https://tekton.dev/chains/v2/slsa-tekton`.
4. **Digests** : les quatre entrées concordent avec leur digest déclaré, et le commit vaut `6391fd437f26696847041be3226bbbf633f55a2f`.
5. **Recette** : le sha256 du Dockerfile est égal à celui que la tâche contrôle. Ce Dockerfile est celui de la brique 04, avec un seul `RUN`, en `--network=none`.
6. **Go** : `go1.26.10`, égal à la toolchain installée dans la VM en R2.
7. **Heures** : `finishedOn` = `2026-11-02T13:59:30Z`. Le jeton de la TSA date de **peu après**, au passage suivant du CronJob d'horodatage. Le rebuild de R4 pourra commencer à 13:59:30 UTC le 03/11.

## Limites

- Les ancres de confiance (clé de Chains, chaîne de la TSA) viennent de ce dépôt, administré par la même personne (D1 b).
- La TSA est celle du plan de confiance, que la même personne administre. Le jeton corrobore l'heure, sans la garantir face à cet administrateur.

## Additif du 03/11/2026, après l'exécution (10:18 à 10:20 UTC)

Premier passage de `verifier_entrees` archivé ([`r3-verifier_entrees-premier-passage.log`](r3-verifier_entrees-premier-passage.log)) : 3 KO, tous dus au script, aucun aux données.
- **Bundle git** : il ne porte que `refs/heads/main`, sans `HEAD`. Le clone n'a donc pas d'arbre extrait, et `git bundle verify` doit tourner dans un dépôt.
- **Tâche** : elle est stockée en **JSON** dans le bundle Tekton, et non en YAML. La recherche du Dockerfile doit se faire dans `spec.steps[].script`.
- **Heure** : `signedTimestamp` contient la **réponse complète** de la TSA (`TimeStampResp`), pas seulement le jeton. `openssl ts -reply` se lit donc sans `-token_in`.

Le script est corrigé, et le second passage donne **0 KO**.

1. **Transport** : conforme. Lectures anonymes seulement ; 77 Mo dans la VM.
2. **Bundles** : **écart**. Il y a **43** bundles horodatés pour `3a7ca1b1`, et non 6. Le tag `.att` ne garde que 6 enveloppes, mais les builds successifs donnent le même digest, et l'horodatage a gardé un bundle par enveloppe rencontrée. Les 43 se vérifient hors réseau, et un seul contient `d9006af7…`.
3. **Politique, section 1** : conforme.
4. **Digests et commit** : conforme. Les quatre entrées concordent, et `main` vaut `6391fd43…`, avec un arbre propre.
5. **Recette** : conforme. Le sha256 du Dockerfile, `d56985c1…`, est égal à celui que la tâche contrôle **et** à celui de `poc/bricks/04-hermetic-repro/Dockerfile`. Il contient un seul `RUN`, en `--network=none`.
6. **Go** : conforme, `go1.26.10` des deux côtés.
7. **Heures** : conforme. `finishedOn` = `2026-11-02T13:59:30Z`, et le jeton de la TSA date du **02/11 14:00:05 GMT**, soit 35 s plus tard.

**Pour R4** : le contexte de build n'est pas le dépôt brut. La tâche `preparer-entrees`, déclarée dans la provenance (`sha256:2070d601…`), produit ce contexte :
- `git archive HEAD` dans `src` ;
- la fermeture dans `deps` ;
- `web-dist` dans `src/web/dist`.

R4 devra extraire cette recette de son bundle, au même titre que `construire-image`.
