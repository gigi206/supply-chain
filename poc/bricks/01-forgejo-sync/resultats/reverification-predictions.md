# Porte de la 01 revérifiée après les builds imprévus, prédictions écrites avant toute exécution (2026-11-02T20:15:21Z)

Accord du propriétaire (« 1 oui »). Depuis la mesure de S5 (15:18 UTC, [`declencheur-porte.log`](declencheur-porte.log)), trois builds de `custom/*` du fork ont produit la même image `builds/sample-app-sync@3a7ca1b1…` :

- 18:38, `e209907f` (`custom/n20261102T183831Z/b`, étape `niveaux`), signé : deux enveloppes de plus dans le tag `.att` ;
- 19:40, `902ce252`, et 20:00, troisième passage de A2 de la brique 19, tous deux sur `custom/s5` pendant le scellement d'OpenBao : échec en ouvert de Chains, aucune enveloppe.

Le journal de 15:18 est gardé : nouvelle étape `reverification`, journal `declencheur-reverification.log`. L'étape `porte` n'est ni modifiée ni relancée.

1. **Tag `.att`** : 4 enveloppes, dont 2 provenances de PipelineRun, `1599e311` (15:17) et `e209907f` (18:38). La plus récente, la seule que juge la porte (08, test 7), est celle de `e209907f`. Aucune enveloppe pour `902ce252` ni pour le commit de 20:00.
2. **Source `workspace/sample-app-sync@1599e311`** (celle de S5) : **refusée**, `slsa_source_correlated.expected_source_code_reference` seule. La porte ne juge plus la provenance de S5 : le verdict de S5 n'est plus reproductible tel quel.
3. **Source `workspace/sample-app-sync@e209907f`** : **admise**, horodatage `ok`, 4/4 enveloppes couvertes (le CronJob tournait à 18:39, avant le scellement de A1).
4. **Source = tête actuelle de `custom/s5`** (commit du troisième passage de A2, sans provenance) : **refusée**, même motif. Une image construite pendant l'échec en ouvert n'est pas admise avec sa vraie source, et elle l'est avec celle d'un build antérieur du même digest (point 3) : la porte vérifie la provenance du digest, pas celle du build demandé.
5. **Non-interférence** : `builds/sample-app@3a7ca1b1` jugée avec la tête de `main` de `workspace/sample-app` : **admise**, 6/6 enveloppes couvertes, comme à 15:18 (aucun build de ce dépôt depuis).
6. Avertissement `trusted_task.tagged` dans tous les verdicts, comme à 15:18. Durée : environ 3 min (4 Jobs de la porte).
