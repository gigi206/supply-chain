# Refs propres à plusieurs niveaux côté Forgejo, prédictions écrites avant toute exécution (2026-11-02T18:38:26Z)

Décision (a) du propriétaire (02/11/2026, 18:36 UTC environ) : motif `custom/**` côté Forgejo, mesuré. Étapes : `forgejo.sh protections niveaux`.

1. **`protections`** : règles `custom/**` et `paquet/**` créées, puis `custom/*` et `paquet/*` retirées par l'API (`DELETE …/branch_protections/<nom encodé>`). Prédiction faible sur le retrait : un nom contenant `/`, encodé en `%2F`, peut ne pas être reconnu par le routeur de Forgejo (404). Ce serait un KO après la pose des nouvelles règles : le fork reste protégé.
2. **`niveaux`**, branches : création refusée à `poc-sync` pour `custom/<n>/b`, `custom/<n>-3/b/c`, `paquet/<n>/deb` et `custom/<n>` (un niveau, non régressé) ; acceptée pour `poc-dev` (liste blanche) ; branche hors motif `essais/<n>/b` acceptée pour `poc-sync` (`**` ne déborde pas du préfixe).
3. **Tag `custom-<n>/x` par `poc-sync`** : refusé. Prédiction faible : d'après ma lecture, Forgejo compile le motif des tags sans séparateur, `custom-*` traverserait déjà les `/`.
4. Refs d'essai supprimées ; `custom/essai` inchangée.
