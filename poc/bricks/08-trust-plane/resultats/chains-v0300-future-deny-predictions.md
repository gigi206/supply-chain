# Témoin de future_deny_rule : prédictions et résultats

Banc : `essais/chains-v0300-signature/future-deny.sh`. `trusted_task.future_deny_rule` est la seule règle du paquet
`trusted_task` restée sans témoin au [banc des témoins](chains-v0300-temoins-predictions.md). Elle ne s'active qu'avec
`trusted_task_rules`, alors que la liste revue en service est à l'ancien format `trusted_tasks`. Ce n'est donc pas « sans
témoin possible » mais « sans témoin dans la configuration en service ».

Le banc signe les objets de j7 tels quels, par v0.29.9 et par v0.30.0, sur une image neuve (même banc de signature que les
témoins, clé jetable, registre en mémoire). Il les juge ensuite par `ec validate image` sous trois politiques, qui ne diffèrent
que par le `ruleData` de `policy.yaml` :
- `service` : la politique en service ;
- `regles` : `trusted_task_rules` ajouté, avec une seule règle `allow` de motif `oci://<registre>/tekton/tasks/*` ;
- `futur` : comme `regles`, plus une règle `deny` sur `oci://<registre>/tekton/tasks/publier-image`, avec `effective_on`
  au 2099-12-31T00:00:00Z.

`regles` est la base du témoin : poser `trusted_task_rules` fait passer toutes les règles `trusted_task.*` de l'ancien
système au nouveau (`trusted.rego`, priorité aux règles), et c'est ce changement qu'il faut isoler.

Lu avant la prédiction, dans la bibliothèque épinglée (`policy/release/trusted_task/trusted_task.rego`,
`policy/lib/tekton/trusted.rego`, `task.rego`, `lib/time`) :
- la règle rend un **avertissement** (`warn`), jamais un refus ;
- `trusted_task_rules` est lu par `lib.rule_data.get` (configuration, puis données). Le banc le pose dans le `ruleData` de
  la politique ; que ec l'y transmette est mesuré par F3 et F4, pas lu ;
- `effective_on` est comparé à `config.policy.when_ns` (heure d'évaluation d'ec), à défaut `time.now_ns()` ;
- le motif porte sur la clé de la référence : `oci://<dépôt>:<étiquette>`, ou `oci://<dépôt>` sans étiquette ;
- message : `Task %q will be denied by rule pattern %q starting on %s.`, avec le nom de tâche du pipeline (étiquette
  `tekton.dev/pipelineTask`), le motif et la date ; terme : nom de la tâche (`task_ref`, étiquette `tekton.dev/task`) ;
- sans champ `versions`, la règle ne lit pas les manifestes des bundles.

Sonde hors mesure (10:14:32Z, `ec opa eval`) : `glob.match` avec délimiteurs `null` fait couvrir à `*` les `/` et les `:`
(`oci://127.0.0.1:5555/tekton/tasks/*` couvre `…/publier-image`). Les références des bundles dans l'énoncé signé gardé par
les témoins n'ont pas d'étiquette (`<registre>/tekton/tasks/<nom>@sha256:…`) : leur clé est `oci://<registre>/tekton/tasks/<nom>`.

## Prédiction (2026-11-26T10:16:02Z)

- **F1** : contrôles initiaux tenus (`lo` seule, ec et bibliothèque à leurs empreintes, `main.go` identique dans src29 et src30,
  noms remplacés comme aux témoins). `regles` ajoute 4 lignes à `policy.yaml` et `futur` 8 lignes, sans en retirer.
  Chaque version signe sans erreur, l'image est signée et porte 2 attestations. Le bundle de `publier` est lu dans l'énoncé
  signé du PipelineRun, sous `pipelineTask` pour v0.29.9 et sous `pipelineTask/publier` pour v0.30.0.
- **F2** (`service`) : les codes refusés de la base des témoins, soit `porte.fermeture_plateforme` pour v0.29.9 et
  `porte.taches_vues`, `build_task_image_results_found`, `pipeline_has_tasks` pour v0.30.0.
- **F3** (`regles`) : aucun code ajouté ni retiré face à `service`, pour les deux versions. `trusted_task.trusted`,
  `data_format` et `future_deny_rule` sont en succès : l'`allow` couvre les trois bundles, la donnée est au bon format et aucun
  `deny` n'est posé.
- **F4** (`futur`, v0.29.9) : face à `regles`, un seul code ajouté, `trusted_task.future_deny_rule` en avertissement, avec le
  message « Task "publier" will be denied by rule pattern "oci://REGISTRE/tekton/tasks/publier-image" starting on
  2099-12-31T00:00:00Z. » et le terme `publier-image`. Aucun code retiré ; `trusted_task.trusted` reste en succès, la règle
  `deny` n'étant pas encore effective.
- **F5** (`futur`, v0.30.0) : rien ne change face à `regles`. `future_deny_rule` réussit à vide, comme les autres règles de
  tâches, alors que le bundle visé est dans l'énoncé signé (F1).
- **F6** : 0 KO.

Réserves écrites avant le lancement :
- la liste `trusted_task_rules` est fabriquée pour le banc : le résultat ne dit rien de la porte en service, qui ne l'a pas ;
- l'`allow` du banc porte sur le dépôt des bundles, pas sur leurs digests ; lu dans la bibliothèque, non mesuré ici : le
  nouveau système compare un motif à `oci://<dépôt>[:<étiquette>]`, sans le digest que l'ancienne liste revue épingle ;
- ec seul : `reserve-c` (Kyverno) n'est pas jugée. Elle n'a pas d'équivalent de `future_deny_rule` (`ivpol.tmpl.yaml`,
  ligne 5), et son générateur lit la liste revue à l'ancien format ;
- un seul cas (j7) ; KMS, contrôleur, Zot réel et admission restent hors du banc.
