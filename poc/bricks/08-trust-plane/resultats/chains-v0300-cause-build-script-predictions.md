# Cause du silence de build_script_used : prédictions et résultats

Banc : `essais/chains-v0300-signature/cause-build-script.sh`. La règle `slsa_build_scripted_build.build_script_used` de
conforma/policy (commit épinglé dans `politique.sh`) est évaluée directement par `ec opa eval`, sans signature ni registre,
sur l'énoncé signé du PipelineRun de j7 gardé par le passage -3 des témoins (`chains-v0300-temoins-3.log`). Elle réussit pour
v0.29.9 alors qu'aucun TaskRun v1 n'a de champ `steps` au premier niveau. Deux causes sont écrites jusqu'ici, aucune mesurée :
les étapes absentes (qui devraient faire refuser) et le terme `build_task.name` du message (absent d'un TaskRun, qui porte
`metadata.name` : s'il est indéfini, le corps de la règle échoue et rien n'est refusé).

Deux contrôles ne changent que l'entrée non signée : `nom` ajoute `name` (valeur de l'étiquette `tekton.dev/pipelineTask`) au
premier niveau de chaque TaskRun ; `nom-etapes` ajoute en plus une étape.

## Prédiction (2026-11-26T09:42:23Z)

- **Z1** (v0.29.9, énoncé signé) : une attestation de PipelineRun ; au moins une tâche de construction, `publier` comprise ;
  pour chacune, `name` absent et zéro étape lue ; `build_script_used` absente des refus.
- **Z2** (v0.29.9, `nom`) : `build_script_used` refuse, une fois par tâche de construction, avec son nom dans le message. C'est
  le contrôle positif : sans lui, l'absence de refus de Z1 ne prouverait rien.
- **Z3** (v0.29.9, `nom-etapes`) : `build_script_used` absente des refus.
- **Z4** (v0.30.0, les trois entrées) : zéro tâche vue, donc zéro tâche de construction ; `build_script_used` absente des refus,
  `build_task_image_results_found` présente (cause différente : aucune tâche lue).
- Aucune erreur d'évaluation, aucun appel réseau possible (seule `lo` dans l'espace).

Si Z1 à Z3 tiennent, le silence vient du terme `build_task.name` et non des étapes. La règle est alors fausse dans les deux
sens pour une provenance v1 : muette aujourd'hui, et elle refuserait toute provenance v1 si le nom était lu, puisque les
étapes d'un TaskRun v1 ne sont pas au premier niveau. Ce second point est déduit, pas mesuré sur une vraie correction.

## Résultat (passage 1, 2026-11-26T09:42:39Z à 09:42:48Z, 0 KO)

Journal : [`chains-v0300-cause-build-script.log`](chains-v0300-cause-build-script.log). ec à l'empreinte du verrou, arbre de
la bibliothèque contrôlé, seule `lo` dans l'espace, énoncés tirés des enveloppes gardées du passage -3 (empreintes au journal).

| Prédiction | Mesure |
|---|---|
| Z1 | **Tenue** : une attestation de PipelineRun, 3 tâches vues, une seule de construction (`publier`), `name` absent, 0 étape lue ; aucun refus de la règle |
| Z2 | **Tenue** : avec `name` ajouté, `build_script_used` refuse : `Build task "publier" does not contain any steps` |
| Z3 | **Tenue** : avec `name` et une étape, aucun refus |
| Z4 | **Tenue** : v0.30.0, 0 tâche vue pour les trois entrées ; seul refus `build_task_image_results_found` |

Le silence de `build_script_used` sur une provenance v1 vient du terme `build_task.name` du message, indéfini sur un TaskRun :
le corps de la règle échoue avant de rendre un refus. Les étapes absentes n'y sont pour rien : dès que le nom est lu, la règle
refuse la tâche `publier`, qui a pourtant une étape, dans `status.steps` et dans `status.taskSpec.steps`, pas au premier niveau (lu sur l'entrée
`entree-29-base.json` à 09:43Z, hors journal).
La règle est donc fausse dans les deux sens pour une provenance v1. Elle est muette dans la porte en service (v0.29.9), et une
correction du seul nom la ferait refuser toute provenance v1. Ce second sens est mesuré sur une entrée non signée modifiée,
pas sur une vraie correction de la bibliothèque.

Réserves : un seul cas (j7), une seule tâche de construction ; entrée non signée pour les deux contrôles, la signature n'étant
pas jugée par `ec opa eval`. Rien n'est ouvert chez le projet tiers.
