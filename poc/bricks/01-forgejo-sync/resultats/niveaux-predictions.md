# Refs propres à plusieurs niveaux côté Forgejo, prédictions écrites avant toute exécution (2026-11-02T18:38:26Z)

Décision (a) du propriétaire (02/11/2026, 18:36 UTC environ) : motif `custom/**` côté Forgejo, mesuré. Étapes : `forgejo.sh protections niveaux`.

1. **`protections`** : règles `custom/**` et `paquet/**` créées, puis `custom/*` et `paquet/*` retirées par l'API (`DELETE …/branch_protections/<nom encodé>`). Prédiction faible sur le retrait : un nom contenant `/`, encodé en `%2F`, peut ne pas être reconnu par le routeur de Forgejo (404). Ce serait un KO après la pose des nouvelles règles : le fork reste protégé.
2. **`niveaux`**, branches : création refusée à `poc-sync` pour `custom/<n>/b`, `custom/<n>-3/b/c`, `paquet/<n>/deb` et `custom/<n>` (un niveau, non régressé) ; acceptée pour `poc-dev` (liste blanche) ; branche hors motif `essais/<n>/b` acceptée pour `poc-sync` (`**` ne déborde pas du préfixe).
3. **Tag `custom-<n>/x` par `poc-sync`** : refusé. Prédiction faible : d'après ma lecture, Forgejo compile le motif des tags sans séparateur, `custom-*` traverserait déjà les `/`.
4. Refs d'essai supprimées ; `custom/essai` inchangée.

## Retrait des deux branches à plusieurs niveaux restantes (décision du propriétaire « 3 i » ; écrit le 2026-11-02T20:18:58Z, avant l'exécution)

Étape `retrait` de [`forgejo.sh`](../forgejo.sh) : règle `custom/**` retirée par `poc-admin`, `custom/a/b` (S2) et `custom/n20261102T183831Z/b` (premier passage de `niveaux`) supprimées par l'API, puis règles remises par l'étape `protections`, même en cas d'échec (`trap`).

1. Sans la règle, la suppression par l'API réussit pour les deux branches (204) ; avec la règle, elle était refusée (premier passage de `niveaux`).
2. **Aucun build** : le webhook du fork ne s'abonne qu'à `push` ; une suppression de branche par l'API n'émet pas d'événement `push` dans Forgejo (lecture du comportement de Gitea, non vérifiée dans le code de Forgejo 15 : prédiction faible). Mesure : nombre de PipelineRuns `sample-app-sync-*` inchangé (2) une minute après, et aucune ligne de l'EventListener `forgejo-sync` dans cette minute.
3. Règles après remise : `custom/**` et `paquet/**`, liste blanche `poc-dev`, `apply_to_admins` ; tag `custom-*` inchangé. Fenêtre sans `custom/**` de quelques secondes.
4. Refus remis en place, vérifié : création de `custom/<n>/b` par `poc-sync` refusée (comme `niveaux`). Plus aucune ref à plusieurs niveaux sous `custom/` ; `custom/essai` et `custom/s5` inchangées.
