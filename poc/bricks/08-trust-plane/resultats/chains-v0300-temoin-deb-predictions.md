# Témoin deb de preparation_appariee : prédictions et résultats

Banc : `essais/chains-v0300-signature/temoin-deb.sh`. `porte.preparation_appariee` est la seule règle de la porte restée
sans témoin au [banc des témoins](chains-v0300-temoins-predictions.md) : elle ne vise que la voie deb (`construire-deb` doit
venir avec `preparer-deb`), absente de j7. Le PipelineRun deb `sample-app-deb-6391fd43…` a été capturé le 25/11 avec ses trois
TaskRuns.

Le banc ne signe rien. Les énoncés viennent du banc à sec du 25/11 (`banc29`, `banc30` : le format slsa/v2alpha4 de v0.29.9 et
de v0.30.0 appelé sur les objets capturés, empreintes contrôlées contre `chains-v0300-provenances.log`), plus l'énoncé signé en
service (v0.29.9), que P1 a trouvé égal à la sortie de `banc29`. Les règles du paquet `porte` sont évaluées par `ec opa eval`
(porte.rego du dépôt, bibliothèque épinglée), dans un espace réseau neuf où seule `lo` existe.

Le témoin désigne le TaskRun `preparer` comme `preparer-entrees` (la préparation de la voie image) : paramètres `name` et
`bundle` de sa `taskRef`, même digest de bundle. `_tache` reconnaît une tâche par l'un ou l'autre, il faut donc changer les
deux. C'est le cas que la règle doit refuser : une construction deb préparée par une autre préparation.

Sonde préalable, hors mesure (09:54:07Z) : la porte entière évaluée sans réseau sur l'entrée j7 déjà mesurée rend en moins
d'une seconde, sans sortie d'erreur, avec `porte.fermeture_plateforme` seul (la vérification des fermetures ne joint pas le
registre). Les règles de fermeture se déclenchent donc ici, et leurs messages sont prédits.

## Prédiction (2026-11-26T09:55:47Z)

- **D1** : contrôles initiaux tenus (ec, bibliothèque, `banc29`, `banc30`, `lo` seule ; sujet de l'énoncé signé égal à
  l'`IMAGE_DIGEST` du PipelineRun capturé ; 3 TaskRuns sur 3). Le témoin ne change qu'un fichier (`preparer`), et deux valeurs
  (`spec.taskRef.params[0].value` et `[1].value`). Chaque énoncé est produit sans erreur, et la `taskRef` de `preparer` y est
  lue telle qu'attendue (`preparer-deb` en base, `preparer-entrees` au témoin), sous `pipelineTask` pour v0.29.9 et sous
  `pipelineTask/preparer` pour v0.30.0. Un silence en v0.30.0 ne sera donc pas une mutation perdue.
- **D2** (`signe-29`, `base-29`) : une attestation de PipelineRun, 3 tâches vues, `construire-deb` et `preparer-deb`
  reconnues. C'est le contrôle de base : la règle voit les deux tâches qu'elle apparie. Seul code refusé :
  `porte.fermeture_plateforme`, avec deux messages, un par fermeture de `preparer-deb` (deb et sources), faute de registre.
  Aucun `preparation_appariee`. Les deux cas rendent les mêmes valeurs.
- **D3** (`temoin-29`) : `construire-deb` et `preparer-entrees` reconnues. `porte.preparation_appariee` refuse, avec le message
  « construire-deb sans preparer-deb dans la même provenance ». `porte.fermeture_plateforme` change aussi de messages, ce qui
  est prédit et non un effet de bord ignoré : `preparer-entrees` attend `FERMETURE_ARTIFACT_INPUTS`, absent des résultats de
  la préparation deb, d'où « construction sans fermeture lisible dans les résultats de sa préparation » et « préparation
  preparer-entrees sans fermeture lisible dans le résultat FERMETURE_ARTIFACT_INPUTS ».
- **D4** (`base-30`, `temoin-30`) : une attestation, 0 tâche vue, 0 tâche reconnue. Seul code : `porte.taches_vues`. Pas de
  `preparation_appariee` au témoin : la règle est à vide en v0.30.0, comme les autres, et seule `taches_vues` refuse.
- **D5** : aucune requête n'écrit d'erreur ; 0 KO.

Réserves écrites avant le lancement :
- énoncés non signés, sauf `signe-29` (signé en service, non vérifié ici) ;
- l'égalité entre énoncé signé et sortie à sec est mesurée pour le deb en v0.29.9 seulement (P1) ; pour v0.30.0, elle l'a été
  sur j7 ([banc de signature](chains-v0300-signature-predictions.md)), pas sur le deb ;
- règles jugées par `ec opa eval`, pas par `ec validate image` : `image_signature` (qui lit `input.image`) et `trusted_task`
  (hors du paquet `porte`) ne sont pas jugées ;
- fermetures non vérifiées faute de registre : leurs messages ne disent rien de la preuve des fermetures ;
- un seul PipelineRun deb.

## Résultat (passage 1, 2026-11-26T09:56:12Z à 09:56:21Z, 4 KO)

Journal : [`chains-v0300-temoin-deb.log`](chains-v0300-temoin-deb.log). D1, D2, D4 et D5 tiennent : contrôles initiaux,
mutation lue dans l'énoncé des deux versions, `construire-deb` et `preparer-deb` reconnues en base (énoncé signé et sortie à
sec rendent les mêmes valeurs), v0.30.0 à 0 tâche vue avec `porte.taches_vues` seul, aucune erreur d'évaluation, six requêtes
en moins de 2 s par cas.

**D3 n'est pas tenue, par faute du témoin.** Au témoin v0.29.9, `preparer-deb` **et** `preparer-entrees` sont reconnues, donc
`preparation_appariee` ne refuse pas. Les fermetures de `preparer-deb` restent jugées, et la ligne de `preparer-entrees` s'y
ajoute. Cause lue dans la bibliothèque (`policy/lib/tekton/refs.rego`, `_ref_name`) : le nom d'une tâche est pris d'abord
dans l'étiquette `tekton.dev/task` du TaskRun, que Tekton pose depuis la Task résolue, et le paramètre `name` de la
`taskRef` ne sert qu'en repli. L'étiquette est restée à `preparer-deb`. `_tache` reconnaît une tâche par le nom **ou** par le
dépôt du bundle : la tâche témoin était reconnue sous les deux noms. J'avais lu `_tache` avant la prédiction, pas `task_ref`.

Ce passage ne dit donc rien de la règle : le témoin n'était pas une construction deb sans `preparer-deb`.

## Prédiction du passage -2 (2026-11-26T09:57:11Z)

Le témoin écrit `preparer-entrees` aussi dans l'étiquette `tekton.dev/task`, comme Tekton le ferait en résolvant le bundle
de `preparer-entrees` : trois valeurs changées dans un seul TaskRun, l'identité de la tâche telle que Tekton l'écrit. Le
contrôle de l'énoncé lit aussi l'étiquette.

- **D6** : D1 à D5 telles qu'écrites plus haut, avec trois chemins changés (étiquette, `params[0]`, `params[1]`) et
  l'étiquette lue dans l'énoncé des deux versions. Au témoin v0.29.9, seule `preparer-entrees` est reconnue à côté de
  `construire-deb`, `preparation_appariee` refuse avec son message et les fermetures portent les deux messages prédits en D3.
  0 KO.

**Résultat du passage -2 (2026-11-26T09:57:19Z à 09:57:30Z, 48 OK, 0 KO, [journal](chains-v0300-temoin-deb-2.log))** :
D6 tenue.

| Cas | Tâches vues | Reconnues | Codes refusés (paquet `porte`) |
|---|---|---|---|
| `signe-29`, `base-29` | 3 | `construire-deb`, `preparer-deb` | `fermeture_plateforme` (2 fermetures non vérifiées, faute de registre) |
| `temoin-29` | 3 | `construire-deb`, `preparer-entrees` | `fermeture_plateforme`, **`preparation_appariee`** : « construire-deb sans preparer-deb dans la même provenance » |
| `base-30`, `temoin-30` | 0 | aucune | `taches_vues` seul |

`preparation_appariee` a désormais un témoin. Elle refuse pour v0.29.9 une construction deb préparée par `preparer-entrees`,
et l'énoncé signé en service rend les mêmes valeurs que la sortie à sec. Pour v0.30.0, elle réussit à vide comme les autres
règles de tâches, alors que le champ changé est dans l'énoncé, sous `pipelineTask/preparer`. Seule `taches_vues` refuse.

Lu en passant (passage 1) : la bibliothèque nomme une tâche d'abord par l'étiquette `tekton.dev/task` du TaskRun. `_tache`
la reconnaît par ce nom **ou** par le dépôt de son bundle, donc une tâche dont l'étiquette et le bundle divergent est reconnue
sous les deux noms. Tekton pose l'étiquette depuis la Task résolue dans le bundle : un écart demanderait un bundle qui
contient une Task d'un autre nom que son dépôt. Le banc ne l'a pas mesuré, et `trusted_task` (liste revue des bundles) n'est
pas jugé ici.

Réserves : celles écrites avant le lancement. Les règles sont jugées par `ec opa eval` ; les énoncés des témoins ne sont pas
signés ; l'égalité avec un énoncé signé n'est mesurée que pour v0.29.9 ; il n'y a qu'un PipelineRun deb. Rien n'est ouvert
chez un tiers.

## Corrections après relecture du conseiller (2026-11-26T09:59:51Z)

Rien n'est relancé, ces corrections ne touchent que le texte.
- **Le passage 1 a mesuré l'écart entre étiquette et bundle.** Son témoin portait l'étiquette `preparer-deb` et le bundle
  `preparer-entrees` : la tâche a été reconnue sous les deux noms, `_presente("preparer-deb")` était satisfaite et
  `preparation_appariee` s'est tue (sur une entrée non signée). La phrase « le banc ne l'a pas mesuré » du paragraphe
  « Lu en passant » est donc fausse pour cette entrée. Restent non mesurés : la possibilité qu'un tel TaskRun sorte de
  Tekton, et son refus par `trusted_task`.
- **L'origine de l'étiquette `tekton.dev/task` n'est pas vérifiée.** Elle vient d'un commentaire de la bibliothèque
  (`refs.rego`) qui dit seulement que le contrôleur de Tekton l'ajoute. Les trois TaskRuns deb ont une étiquette égale au
  paramètre `name`, ce qui ne permet pas de distinguer le nom de la Task résolue du nom demandé. Parmi les 81 TaskRuns
  capturés, seuls 5 (`essai-confiance`) n'ont pas l'étiquette, et le réconciliateur n'est pas dans le `vendor/` de la source.
  Dans le témoin du passage -2, « comme Tekton l'écrirait » est donc une hypothèse.
- **Portée.** `preparation_appariee` était la seule règle **du paquet `porte`** restée sans témoin. `future_deny_rule` reste
  sans témoin, et `build_script_used` n'a qu'une cause mesurée.
- **Réserve ajoutée.** L'énoncé signé en service (`sorties/<deb>.signe.json`, sha256 `5906e434…` au journal) n'est relié à
  P1 que par son nom : le journal du 25/11 n'écrit pas son empreinte.
