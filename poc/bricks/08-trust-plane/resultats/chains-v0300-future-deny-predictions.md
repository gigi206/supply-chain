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

## Résultat (passage 1, 2026-11-26T10:16:42Z à 10:16:52Z, 3 KO)

Journal : [`chains-v0300-future-deny.log`](chains-v0300-future-deny.log). F1, F2, F3 et F5 tiennent : contrôles initiaux,
4 et 8 lignes ajoutées à `policy.yaml`, bundle de `publier` lu dans l'énoncé signé des deux versions, codes de la base des
témoins sous `service`, aucun code changé sous `regles`, rien de changé pour v0.30.0.

**F4 n'est pas tenue** : sous `futur`, v0.29.9 n'a aucun code ajouté, et `future_deny_rule` reste en succès. Le banc l'a jugée
sans sa donnée d'entrée. Chaque jugement v0.29.9 écrit 9 lignes d'erreur d'ec : `failed to fetch image` par
`ec.oci.image_manifest`, pour les trois bundles (`NAME_UNKNOWN` : le registre du banc ne les contient pas). La règle
appelle `future_deny_rules_for_task(task, _manifests)`, avec `_manifests := ec.oci.image_manifests(lib.pipelinerun_bundle_refs)`.
Cause probable, pas encore mesurée : `_manifests` est indéfini quand la récupération échoue, et le corps de la règle échoue
avec lui. v0.30.0 n'écrit aucune erreur : elle ne lit aucune tâche, donc aucune référence de bundle.

Conséquence pour F3, lue et non mesurée : tout le nouveau système passe par `_manifests` (`untrusted_task_refs_rules`,
`_trust_errors_rules`). Le succès de `trusted_task.trusted` sous `regles` peut donc être un succès à vide, et non le fait de
l'`allow`.

Conséquence pour les bancs précédents, mesurée dans leurs dossiers de travail gardés : tous les jugements v0.29.9 de
`porte.sh` et de `temoins.sh` ont les mêmes 9 lignes d'erreur (6 erreurs de récupération pour le témoin `epingle`). Aucun de
ces bancs ne contrôlait la sortie d'erreur d'ec. Dans l'ancien système, `_manifests` ne sert qu'à `_trusted_build_digests`,
qui alimente `trusted_parameters` : les digests de résultats des tâches de construction n'y sont pas entrés, seuls ceux du
snapshot l'ont été. En service, Zot répond et `_manifests` est défini. Ce que ce trou change aux résultats de ces bancs
n'est pas mesuré.

## Cause mesurée et corrections (sondes hors mesure, 2026-11-26T10:20:57Z à 10:21:39Z)

Les deux sondes sont faites par `ec opa eval`, dans un espace réseau neuf, sur l'énoncé signé v0.29.9 du passage 1, avec
`rule_data__configuration__` posé à la main.
- **`_manifests` n'est pas indéfini.** `ec.oci.image_manifests` rend `{}` quand le registre ne répond pas : `count` à 0,
  une ligne d'erreur, code 0. La cause probable écrite plus haut est donc fausse.
- **La donnée est lue, mais le système est éteint par défaut.** Avec la donnée du cas `futur`, `future_deny_rules` compte
  1 règle et les clés des trois tâches sont bien `oci://<registre>/tekton/tasks/<nom>`. Pourtant,
  `missing_trusted_task_rules_data` vaut `true`. Les défauts de la bibliothèque (`policy/lib/rule_data/rule_data.rego`,
  ligne 152) contiennent `"trusted_task_rules_enabled": false`, que `trusted.rego` traite comme une donnée manquante. Avec
  `trusted_task_rules_enabled: true`, la règle avertit avec le message prédit en F4, `_manifests` valant toujours `{}`.

Corrections du passage 1 :
- le passage 1 a mesuré ceci : sans `trusted_task_rules_enabled`, poser `trusted_task_rules` ne change rien ; F3 ne disait
  donc rien de l'`allow` ;
- les deux paragraphes « Conséquence » sont faux. Le nouveau système ne se tait pas faute de manifestes : sans champ
  `versions`, une règle ne les lit pas, et `_manifests` vaut `{}`. L'ancien système appelle `is_trusted_task(task, _)`, qui
  ignore les manifestes. Les 9 lignes d'erreur des bancs `porte.sh` et `temoins.sh` restent un fait mesuré, mais aucun effet
  sur leurs résultats n'est établi ;
- je n'avais pas lu les défauts de `rule_data` avant la prédiction.

## Prédiction du passage -2 (2026-11-26T10:22:30Z)

Le passage -2 pose `trusted_task_rules_enabled: true` dans les cas `regles` et `futur`, et ajoute deux cas :
- `immediat` : `regles` plus la même règle `deny`, sans `effective_on`, donc effective. C'est le témoin de `regles` : sans
  lui, son silence ne prouve pas que l'`allow` a été jugé ;
- `eteint` : la donnée de `futur` sans l'activation, soit le passage 1 rejoué comme contrôle.

La sortie d'erreur d'ec est contrôlée à chaque jugement. Les bundles ne sont pas poussés dans le registre du banc : aucune
règle du banc n'a de champ `versions`.

- **G1** : F1, avec 5, 9, 8 et 8 lignes ajoutées et aucune retirée (`regles`, `futur`, `immediat`, `eteint`). `futur` et
  `immediat` contiennent `regles`, et `eteint` ne diffère de `futur` que par la ligne d'activation.
- **G2** : F2, inchangée.
- **G3** (`regles`) : F3, inchangée, mais le système est cette fois actif.
- **G4** (`futur`) : F4 et F5, inchangées.
- **G5** (`immediat`, v0.29.9) : face à `regles`, un seul code ajouté, `trusted_task.trusted` en refus. Son terme est
  `publier-image` et son message donne la raison `deny_rule`. `trusted_parameters` reste en succès : le paramètre `digest`
  de `publier` est le digest de l'image, présent dans le snapshot. Pour v0.30.0, rien ne change.
- **G6** (`eteint`) : aucun code ajouté ni retiré face à `service`, pour les deux versions.
- **G7** : chaque jugement v0.29.9 écrit 9 lignes d'erreur, toutes des échecs de récupération des manifestes. Les
  jugements v0.30.0 n'en écrivent aucune. 0 KO.

**Résultat du passage -2 (2026-11-26T10:22:52Z à 10:23:03Z, 63 OK, 3 KO, [journal](chains-v0300-future-deny-2.log))** :
G1 à G6 tenues. G7 n'est pas tenue, et c'est elle qui porte les 3 KO.

| Code `trusted_task.*` (v0.29.9) | `service` | `regles` | `futur` | `immediat` | `eteint` |
|---|---|---|---|---|---|
| `future_deny_rule` | succès | succès | **avertissement** | succès | succès |
| `trusted` | succès | succès | succès | **refus** | succès |
| `tagged` | avertissement | avertissement | avertissement | avertissement | avertissement |
| les six autres | succès | succès | succès | succès | succès |

- **v0.29.9**
  - `futur` ajoute le seul avertissement `future_deny_rule` : « Task "publier" will be denied by rule pattern
    "oci://REGISTRE/tekton/tasks/publier-image" starting on 2099-12-31T00:00:00Z. », de terme `publier-image`.
  - `immediat` ajoute le seul refus `trusted_task.trusted`, de terme `publier-image` et de raison `deny_rule`.
    `trusted_parameters` reste en succès. Ce témoin montre que, sous `regles`, l'`allow` est bien jugé.
  - `eteint` ne change rien face à `service` : sans activation, la donnée est ignorée, comme au passage 1.
- **v0.30.0** : rien ne change sous les cinq politiques. Les règles n'ont aucune tâche à juger, alors que le bundle de
  `publier` est dans l'énoncé signé, sous `pipelineTask/publier`.
- **G7** (sortie d'erreur d'ec)
  - `service` et `eteint` : 9 lignes pour v0.29.9, comme prédit.
  - `regles`, `futur` et `immediat` : 12 lignes, soit 4 échecs de récupération par bundle au lieu de 3. Le nouveau système,
    une fois actif, demande donc les manifestes une fois de plus. Mon compte ne tenait pas compte de ce changement.
  - v0.30.0 : 0 ligne partout.

Rien n'est relancé, pour ne pas corriger un compte après l'avoir vu.

`future_deny_rule` a désormais un témoin. Avec une liste au nouveau format, activée, elle avertit pour v0.29.9 et reste muette
pour v0.30.0, comme les autres règles de tâches. Dans la configuration en service, elle ne peut rien signaler pour deux
raisons, toutes deux mesurées : la liste revue est à l'ancien format, et le nouveau système est éteint par défaut
(`trusted_task_rules_enabled`, défaut `false`).

Réserves : celles écrites avant le lancement. La liste de règles est fabriquée. ec est seul juge, `reserve-c` n'ayant pas
d'équivalent. Il n'y a qu'un cas (j7). Les bundles sont absents du registre du banc, et aucune règle `versions` n'est
essayée. Rien n'est ouvert chez un tiers.
