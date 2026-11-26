# Chains v0.30.0 : lecteurs du nom `pipelineTask` (relevé à sec)

Relevé du 2026-11-25T10:44:25Z, dépôt `13d0f1f3`, **par lecture seule** : rien téléchargé, rien compilé, rien lancé. C'est un inventaire, pas une recommandation. Décision du propriétaire (24/11/2026) : **« Banc à sec après R5 »**. En service : v0.29.9.

**Rappel de la source** (lue le 24/11, non mesurée, voir [docs/04](../../../docs/04-sante-projets.md)) : #2041 renomme, en `slsa/v2alpha4`, la dépendance `pipelineTask` en `pipelineTask/<nom>`. [chains-config.yaml](tekton/chains/chains-config.yaml) demande bien `slsa/v2alpha4` pour TaskRun et PipelineRun : le PoC est concerné.

## Ce qui n'est pas concerné

Le label `tekton.dev/pipelineTask` et le champ `pipelineTaskName` viennent de Tekton Pipelines, pas de Chains. Seules comptent les comparaisons du champ `name` de `resolvedDependencies`.

## Lecteurs qui comparent le nom exact

| Lecteur | Où | Effet attendu si le nom change (déduit, à mesurer) |
|---|---|---|
| Porte, bibliothèque Conforma (commit `ebd3fbd2`) | `policy/lib/tekton/task.rego:88`, `dep.name == "pipelineTask"` | 0 tâche vue ; `trusted_task` n'a plus rien à juger. Mesuré le 2026-11-26T09:35:19Z : six règles qui lisent les tâches ont un témoin refusé (ou averti) pour v0.29.9. Pour v0.30.0, cinq réussissent à vide et `successful_pipeline_tasks` est absente, le champ fautif étant dans l'énoncé signé. Trois règles sans témoin possible sur j7 (voie deb, témoin fait depuis sur le PipelineRun deb : refus pour v0.29.9, à vide pour v0.30.0, [banc](resultats/chains-v0300-temoin-deb-predictions.md) ; format de la liste, `build_script_used` muette en v1, cause mesurée : `build_task.name` indéfini, [banc](resultats/chains-v0300-cause-build-script-predictions.md)) ([banc des témoins](resultats/chains-v0300-temoins-predictions.md)) |
| Porte, règle maison | [porte.rego](politique/porte/porte.rego), `porte.taches_vues` | **refus** (« aucune tâche vue ») : le témoin devrait fermer la porte au lieu d'une acceptation à vide. `construction_kata`, seule, accepterait à vide |
| Test de la porte | `politique/porte/porte_test.rego:49` | le jeu d'essai garde l'ancien nom : il resterait vert et ne prouverait rien |
| Politique d'image Kyverno (réserve C) | `politique/reserve-c/ivpol.tmpl.yaml:89` | `taches_pr` vide : refus mesuré par le CLI le 2026-11-26T09:06:50Z (`build_task_image_results_found`, `pipeline_has_tasks` ; `trusted_task.trusted` à vide), [banc ivpol](resultats/chains-v0300-ivpol-predictions.md) ; `subject_build_task_matches`, `successful_pipeline_tasks`, `trusted_parameters`, `valid_trusted_artifact_inputs` et `pinned` à vide aussi, avec témoins ([banc des témoins](resultats/chains-v0300-temoins-predictions.md)) |
| Exportateur et recalcul de la 20 | `genre()` de `tools/metrics-exporter/metrics_exporter.py` et de `20-kpi/recalcul.py` | la tâche deviendrait une `image`. **Les deux ont le même défaut : le seuil (0 écart) ne le verrait pas** ; correctif éprouvé à sec le 25/11, [non appliqué](../20-kpi/resultats/e13-predictions.md) |
| Scripts de preuve | 05 (`m1b-construction` 2, `m1b-fermeture` 1, `m1b-provenance` 2, `m4b` 1, `m4c` 2), 06 (`s4a` 1, `s4b` 4, `s4d` 2, `s4d2` 4), 03 (`bascule` 3, `prefetch` 1), 08 (`construction` 1, `politique` 6, `preuves` 7, `tekton` 1) : lignes contenant `pipelineTask"` hors label, commentaires et textes compris | sélections vides ; une sélection vide comparée à une liste attendue échoue, mais un mutant appliqué à une sélection vide ne mute rien (`s4d2.sh`, `preuves.sh`) |
| Banc des témoins de la 20 | `20-kpi/banc_temoins.py:174` | jeu d'essai à l'ancien nom |

La branche `claude/argo-l3` (porte Kyverno, enveloppe Go) n'est pas couverte par ce relevé.

## Ce que le banc devra établir (après R5, sur accord pour les téléchargements)

1. La forme exacte écrite par v0.30.0, sur une vraie provenance de banc, et les autres changements de #2041 (non relus ici).
2. Pour chaque lecteur : refus, acceptation ou vide, avec l'ancien nom, le nouveau, et un mélange des deux dans un même digest (une image en service aurait les deux pendant la transition).
3. Un témoin qui échoue si le jeu d'essai garde l'ancien nom.
4. Les deux correctifs attendus (`b1c0af9`, #2096), et le cas « aucun signataire », toujours sans `recordError`.

Local : les deux clones de Chains ont v0.29.9 seulement ; le Go de l'hôte est 1.24.7. Le banc demandera donc un téléchargement et une chaîne Go récente, à demander.

**Correctif et résultat (2026-11-25T20:38:13Z)** : Go 1.27.3 était déjà local (`chains-correctif/go-dl`) ; seule la source de v0.30.0 a été prise, sur accord. Le banc est passé : [résultat](resultats/chains-v0300-predictions.md). Points 1, 2 et 3 établis (politique Kyverno de la réserve C et enveloppe Go exceptées) ; **point 4 non mesuré**. La porte refuse l'énoncé neuf (`porte.taches_vues`) ; les `byproducts` sont renommés aussi, et aucun lecteur du dépôt ni de la bibliothèque ne les lit (`git grep`).
