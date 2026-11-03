# D5, compte Zot `poc-replay` : prédictions (écrites le 03/11/2026 vers 10:40 UTC, avant toute exécution)

Accord du propriétaire : « Oui, appliquer D5 ». Ce passage modifie la 08 : `stockage/zot.json`, l'étape `zot` de `stockage.sh`, puis un rejeu ciblé `mise run confiance:stockage -- zot`, qui redémarre Zot.

## Étapes

1. **`JALON=d5 mise run replay -- compte_zot`** (brique 10, sur l'hôte) :
   - mot de passe aléatoire dans `~/.cache/supply-chain-poc/10/secrets/zot-poc-replay.password` (0600) ;
   - ligne `poc-replay:<bcrypt coût 12>` dans `zot-poc-replay.htpasswd` (0600).
2. **Modifications de la 08** :
   - `zot.json`, dépôts `builds/**` : `poc-replay` en `read`, et en `create` sous la condition `req.referenceType != "tag"` ;
   - `stockage.sh`, étape `zot` : la ligne de `poc-replay` est lue dans le fichier `htpasswd` du domaine, sans le mot de passe.
3. **`mise run confiance:stockage -- zot`** : Zot réinstallé avec la même empreinte binaire et redémarré.
4. **`JALON=d5 mise run replay -- droits_zot`** : essais du compte sur un dépôt jetable, `builds/essai-replay`.

## Prédictions

1. Le hash est un bcrypt de coût 12 (`$2b$12$`), et le mot de passe n'apparaît dans aucun journal.
2. Zot redémarre et répond 200 sur `/v2/` en moins de 30 s. Les autres comptes sont inchangés ; leurs mots de passe ne sont pas régénérés.
3. Avec `poc-replay` :
   - **acceptés** : push d'une image jetable par digest dans `builds/essai-replay`, puis d'un referrer, par `oras attach` (manifeste par digest) ;
   - **refusés** : push par tag dans `builds/essai-replay` ; push par digest dans `workspace/essai`, hors de `builds/**` ; suppression.
4. Le referrer apparaît dans `GET /v2/builds/essai-replay/referrers/<digest>`, en lecture anonyme.
5. L'audit de Zot trace les actions de `poc-replay`, et Alloy les envoie dans Loki (source J6).
6. Les builds ne sont pas touchés : `builds/sample-app` garde son tag `.att` et ses 6 enveloppes.

## Résidu prévu

Le dépôt `builds/essai-replay` (image et referrer jetables) reste dans Zot, puisque Zot n'autorise pas la suppression, comme pour `essais-19b/temoin`.

## Additif du 03/11/2026, après l'exécution (10:40 à 10:42 UTC)

1. **Hash** : conforme. bcrypt de coût 12 ; mot de passe et ligne `htpasswd` en 0600 dans le dossier du domaine. Le mot de passe n'apparaît dans aucun journal (`tools/secrets-depot.sh` le cherchera avant le commit).
2. **Zot** : conforme. Il répond 200 sur `/v2/` juste après le redémarrage ; les six comptes, dont `poc-replay` « hash fourni par la brique 10 », ont des mots de passe inchangés ; `systemd-analyze security` vaut 3.0, comme avant.
3. **Droits** : conforme. Push par digest et referrer acceptés ; tag, dépôt hors de `builds/**` et suppression refusés, tous par le **contrôleur d'accès** (`denied`). Pour le tag, le message est celui de la condition CEL de `poc-replay` ([`d5-droits_zot-refus.log`](d5-droits_zot-refus.log)).
   - Premier essai du complément raté côté client : oras était introuvable hors du dépôt, et seule la suppression avait été tentée, refusée elle aussi. Rejoué avec le chemin absolu d'oras.
4. **Referrer** : conforme. Il est visible en lecture anonyme (`application/vnd.dev.sigstore.bundle.v0.3+json`), et `builds/essai-replay` n'a aucun tag.
5. **Audit** : **en partie**. Les écritures réussies de `poc-replay` (POST 202, PUT 201) sont dans l'audit de Zot et dans Loki (`{noeud="sc-stockage", source="audit-zot"}`). Les **refus n'y figurent pas** : l'audit de Zot ne trace que les écritures abouties, et je ne les ai pas trouvés non plus dans son journal.
6. **Builds** : conforme. `builds/sample-app` a toujours 6 enveloppes dans son tag `.att`.

**Risque pour R5, à mesurer avant de pousser la VSA sur `builds/sample-app`** : la porte de la 08 lit les attestations au format bundle rangées en referrer (test 8). Une VSA en referrer de l'image, signée par une autre clé que celle de Chains, pourrait changer son verdict. Il faudra rejouer la porte sur l'image, avec la VSA, ou d'abord sur un dépôt jetable.
