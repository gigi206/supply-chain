# C : Kyverno comme moteur de politique unique

**But** : noter « Kyverno seul » (CLI pour la porte de release + admission) sur la grille C de l'ADR 0000, face à la référence Conforma (release) + Kyverno (admission).

## Banc d'essai local (sans cluster)

1. Lancer un **registre Zot local** (binaire épinglé, sur localhost).
2. Pousser une image de test et des attestations **signées avec une clé locale** (cosign) :
   - provenance SLSA v1 au format Chains (`slsa/v2alpha4`), avec cas valides et invalides : builder inattendu, dépendance non épinglée, tâche non autorisée ;
   - VSA de replay (`PASSED` / `FAILED`) ;
   - résultat de scan (KEV sans VEX) ;
   - verdict de licences ;
   - bundle avec et sans horodatage.
3. Écrire les **10 contrôles de release** de l'ADR 0000 :
   - en **Kyverno** (`ImageValidatingPolicy`, évalué en CLI) ;
   - en **Conforma** (`ec validate image` + règles, dont la collection `slsa3` et `trusted_task`).
4. Pour chaque cas, comparer le résultat attendu et obtenu, le temps d'évaluation et le nombre de lignes de règles (C-1, C-4, C-6).
5. Vérifier le support des bundles Sigstore, des referrers et de l'horodatage (C-3).

**Parité avec l'admission (C-2)** : à faire sur le cluster du PoC (mêmes politiques appliquées à l'admission).
