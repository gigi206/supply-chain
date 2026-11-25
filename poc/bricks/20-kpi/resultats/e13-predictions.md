# Brique 20 : genre() et les noms de Chains v0.30.0, prédictions (2026-11-25T21:23:14Z)

Origine : [banc à sec de Chains v0.30.0](../../08-trust-plane/resultats/chains-v0300-predictions.md), P10. L'exportateur **et** le recalcul classent `pipelineTask/<tâche>` en `image`, d'accord entre eux : leur accord ne prouve rien. La preuve est un attendu écrit à la main.

Deux correctifs, **non appliqués au dépôt** (précédent : `alertes-kpi.patch`) : `genre-temoins.patch` (quatre dépendances neuves dans `banc-pins`, attendus, et un contrôle du genre lu par le recalcul, que rien ne regardait au banc) et `genre-chains-v0300.patch` (exportateur et recalcul, deux écritures séparées). L'exportateur du dépôt (`98f917ab…`) reste celui de sc-stockage : `kpi-pose.sh` les compare. Rien n'est posé.

**Choix** : `tache` si le nom est `pipelineTask`, ou `pipelineTask/` suivi d'au moins un caractère (tâche, ou tâche et TaskRun pour une matrice, forme lue dans la source, jamais produite ici). `pipelineTask/` vide, `pipelineTaskX` et tout autre nom : `genre()` inchangé. Portée : étiquette `genre` des dates de pins, seule.

| N° | Mesure (`banc-genre.sh`) | Prédiction |
|---|---|---|
| G1 | `banc`, témoins sans correctif | code 1 ; 5 bilans ; comparaison 25 cas, **2 écarts** : « vérifiées : dates des pins de banc-pins » et « recalcul : genre, nom et pin… », `t-neuf` et `t-matrice` en `image` ; aucun autre KO (« comptées » inchangé : la provenance la plus récente y est la forgée) |
| G2 | `banc`, témoins et correctif | code 0 ; 25 cas, 0 écart |
| G3 | `banc`, sept mutants | chacun refusé par **un seul** cas : « vérifiées » pour 1, 3, 5, 6 (exportateur), « recalcul » pour 2, 4, 7 |
| G4 | `sorties`, vraies sorties de v0.29.9 et v0.30.0, 5 PipelineRuns | tâches : 13 avec v0.29.9 avant et après ; avec v0.30.0, 0 avant, 13 après (2, 3, 3, 2, 3) ; après, genres égaux dans l'ordre entre les deux formats ; v0.29.9 inchangé par le correctif |
| G5 | `sorties`, 16 noms écrits à la main et l'absence de nom | exportateur et recalcul égaux à l'attendu |
| G6 | `zot`, vrai Zot, avant puis après | codes 0 ; plus de 200 lignes `KPI` et `PROM`, **0 différente**, dates de passage et de journal exclues |

**Réfuté si** une ligne diffère. **G6 non valable si** un scan ou un énoncé arrive dans Zot entre les deux passages.

**Ne dit pas** que la montée en v0.30.0 est possible : la porte, `ivpol` (réserve C) et les scripts des 03, 05, 06 et 08 comparent toujours le nom exact.
