# Brique 06, S4d3 : prédictions et résultats

Décision du propriétaire (11/11/2026, 20:35:01 UTC, « Oui, les deux ») :
- la forme de la carte de 20:33 UTC est retenue : un Trigger à part, sélectionné par label, avec ses propres intercepteurs ; un `labelSelector` sur l'EventListener dans `declencheurs.yaml` de la 08 ; un compte `rattrapage-deb` ; `main.go` et l'image du rattrapage inchangés ;
- le relevé en lecture seule est fait avant les prédictions.

La question 3 de la carte (limite des commits incompatibles, inscrite en dette) n'a pas reçu de réponse. J'applique ma recommandation : la dette est inscrite.

Prédictions écrites le 11/11/2026 entre 20:37 et 20:41 UTC, après le relevé et avant tout lancement. Fichiers :
- script : [`s4d3.sh`](../s4d3.sh) ;
- objets du deb : [`deb/declencheur.yaml`](../deb/declencheur.yaml) ;
- sélecteur : `politique/declencheurs.yaml` de la 08.

## Relevé de l'état déployé (20:36:05 à 20:36:28 UTC)

Journaux : [`s4d3-releve-1.log`](s4d3-releve-1.log) et [`s4d3-releve-2.log`](s4d3-releve-2.log).

Le premier passage contient de faux écarts, dus à ma commande de comparaison : les fichiers à plusieurs documents étaient lus sans `jq -s`. Le second passage refait les comparaisons au dépôt.

| Objet | État |
|---|---|
| TriggerTemplate `sample-app` | celle de la bascule de J8 (`gabarit-sample-app.yaml`), bundle `sample-app@02c05736…` ; identique au dépôt, bundle masqué |
| EventListener `forgejo` | identique à `declencheurs.yaml`, une fois retirés les défauts du serveur. Le conteneur du gabarit porte les ressources par défaut de Triggers (requêtes 10m et 32Mi, limites 250m et 128Mi) |
| Rattrapage | Role, Role de builds, CronJob (non suspendu) et image `c3992728…` identiques au dépôt. La NetworkPolicy aussi, au `ingress: []` près, que le serveur omet |
| Forgejo | tête de main `6391fd43…`, égale à `COMMIT` de `s4d.sh` et à `TETE_J2` ; le rattrapage répond PRESENT chaque minute |
| PipelineRuns | `sample-app-6391fd43…` présent (EventListener, 10/11/2026), aucun `sample-app-deb-*`, `s4d-deb-1` et `s4d-deb-2` réussis et signés, aucun en cours |
| Pipeline deb | `sample-app-deb@82c8373d…` présente dans Zot, même digest |
| sc-build | 6 CPU et environ 9,7 Gio allouables |

**Conséquences pour les prédictions** :
- `sample-app-6391fd43…` existe : au chemin 1, le trigger de l'image répond « already exists » et ne lance aucune construction. Il n'y aura donc qu'une construction Kata à la fois ;
- aucun objet Trigger n'existe : le `labelSelector` seul ne change rien.

## Prédictions

| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| T1 | `prealables` | Gabarit rendu sans variable restante : huit objets. Il satisfait `main.go` : paramètres `commit,depot`, une ressource, `tekton.dev/v1 PipelineRun builds/sample-app-deb-6391fd43…` | haute |
| T2 | `prealables` | Intercepteurs et liaisons du Trigger identiques à ceux de `sample-app-push` en service. CronJob identique à `rattrapage` hors nom, compte, `GABARIT` et suspension, image comprise | moyenne : la comparaison retire des défauts du serveur listés à la main |
| T3 | `prealables` | EventListener du dépôt égal à celui en service, au `labelSelector` près. Dépendances de la 08 présentes : ConfigMap `rattrapage`, secret `forgejo-webhook` (nom seul), NetworkPolicy `construction-deb-sans-sortie`. Aucun objet Trigger, pas de gabarit `sample-app-deb`. Bundle dans Zot ; ses trois tâches sont dans la liste revue | haute |
| T4 | `deployer` | `labelSelector` en service ; objets appliqués ; pod de l'EventListener inchangé (le sélecteur est lu par l'informateur, pas par le déploiement) ; `rattrapage-deb` suspendu, `rattrapage` non | moyenne : un conflit de champs à l'apply côté serveur arrêterait l'étape avant tout changement |
| T5 | `deployer` | Droits : `rattrapage-deb` lit `sample-app-deb` mais pas `sample-app`. Il crée des PipelineRuns dans builds, sans pouvoir les supprimer, et ne lit aucun secret. `rattrapage` ne lit pas `sample-app-deb` ; `el-forgejo` liste les Triggers | haute |
| T6 | `deployer` | PipelineRun du gabarit admis à blanc au nom de `el-forgejo` et de `rattrapage-deb` ; spec admise identique à celle de `s4d-deb-1` | moyenne : les défauts posés à l'admission doivent être les mêmes qu'à 19:41 UTC |
| T7 | `deployer` | Livraisons du commit fictif `1111…`, adressées directement à l'EventListener : sans signature, d'un autre secret, et à corps modifié. Six refus de l'intercepteur github, un par trigger et par livraison : deux « no X-Hub-Signature-256 header set » et quatre « payload signature check failed ». Aucun PipelineRun | moyenne : en J8, un seul trigger donnait trois refus ; le doublement suppose un appel d'intercepteur par trigger, lu dans le code |
| T8 | `chemins` | Chemin 1, livraison de Forgejo (HTTP 204) : `sample-app-deb-6391fd43…` créé une fois, par `declencheurs:el-forgejo` (audit de l'API, 201), labels de l'EventListener. Le PipelineRun réussit, avec la pipeline `sample-app-deb@82c8373d…` et une spec identique à celle de `s4d-deb-1`. Trois TaskRuns réussis ; pods sur sc-build, `construire` sous Kata. Résultats : `IMAGE_DIGEST` `039949f9…`, `IMAGE_URL` `builds/sample-app-deb`. Chains signe le PipelineRun. Le trigger de l'image répond « already exists » pour `sample-app-6391fd43…` | moyenne : première construction du deb lancée par un trigger |
| T9 | `chemins` | Noms des TaskRuns : `publier` garde `sample-app-deb-<commit>-publier` (63 caractères). `preparer` et `construire` dépasseraient 63 : Tekton raccourcit leurs noms | moyenne : la règle de troncature de knative (`kmeta.ChildName`) n'a pas été relue |
| T10 | `chemins` | Chemin 2, après la purge et la reprise de `rattrapage-deb` : une seule ligne CREE dans les passages ; création par `declencheurs:rattrapage-deb`, label `poc.test/declencheur=rattrapage`. Mêmes mesures qu'au chemin 1, même spec, autre UID. Le rattrapage de l'image répond PRESENT | moyenne |
| T11 | `chemins` | Rejeu de la livraison : deux refus « already exists », un par trigger, et même UID pour `sample-app-deb-6391fd43…` | haute |
| T12 | `chemins` | Enveloppes de Chains : `builds/sample-app-deb@039949f9` passe de 4 à 8 (TaskRun `publier` et PipelineRun, à chaque chemin). `builds/sample-app` est inchangé | moyenne |
| T13 | `porte` | Deb : la provenance jugée est celle du chemin 2. `ec` réussit sans violation, avec `trusted_task.tagged` en avertissement ; horodatage 8/8. Les cinq règles `porte.*` figurent parmi les succès. VSA et scan refusent, et le Job échoue, comme décidé | moyenne : la provenance d'un PipelineRun créé par un trigger porte d'autres labels et un autre nom que celle de S4d1 |
| T14 | `porte` | sample-app : verdict de `s4d2-reelle` (`true`, aucune violation, horodatage 28/28, VSA et scan admis) | haute |

## Ce que S4d3 ne couvre pas

- **Deux constructions Kata simultanées** sur sc-build, après un vrai push qui déclenche l'image et le deb : non mesurées.
- **Un commit qui n'est pas la tête de main** : les deux chemins ne construisent que `6391fd43…`.
- **Dette inscrite** : le trigger construit tout commit de main avec les fermetures et l'artefact de packaging épinglés dans la pipeline signée. Un commit qui change `go.mod` échoue dans `preparer-deb` (échec fermé). Un changement de `debian/` dans le dépôt n'est pas pris en compte.
- **Rejeux isolés de la 08** : après S4d3, une étape de la 08 qui pousse des commits d'essai (`politique.sh rattrapage` de J6) lance aussi la construction du deb pour ces commits. Pour l'éviter : `s4d3.sh retirer`, ou suspendre `rattrapage-deb`. Un rejeu depuis zéro n'est pas touché.
- **Contrôles 6 et 7 du deb** : jalon séparé, comme décidé le 11/11/2026 à 20:08:42 UTC.

## Résultats

(à remplir après les lancements)
