# Origine de la quatrième demande de manifeste (G7 de future-deny), prédictions (2026-11-26T12:11:33Z)

Après « continue », sans accord nouveau : passage unique, borné.

## Pourquoi cette mesure

G7 de [future-deny](chains-v0300-future-deny-predictions.md) a été relue sur les sorties gardées
([relevé](chains-v0300-future-deny-g7.log)). Toutes les lignes viennent de `ec.oci.image_manifest`, avec un compte par
bundle :
- 3 lignes sous `service` et `eteint` ;
- 4 lignes sous `regles`, `futur` et `immediat`.

Un point reste déduit : que la demande en plus vienne du nouveau système `trusted_task_rules`. La mesure ne change aucun
verdict. Les 3 KO de G7 viennent d'un attendu faux (9), et les bundles sont absents du registre du banc.

## Ce qui a été lu (bibliothèque `ebd3fbd2`, hors tests)

- Trois paquets demandent les manifestes des bundles du PipelineRun, par `ec.oci.image_manifests(lib.pipelinerun_bundle_refs)` :
  - `tasks` (ligne 37) ;
  - `trusted_task` (ligne 23) ;
  - `slsa_build_scripted_build` (ligne 24).
- `tasks` et `slsa_build_scripted_build` font partie de `@slsa3`. `trusted_task` est inclus à part dans `policy.yaml`.
- `porte.rego` n'appelle aucune fonction `ec.oci`.
- `lib/intoto/trust.rego:87` appelle aussi `image_manifests`. Cet appel passe par les referrers et `verify_attestation`, pas
  par `trusted_task_rules_enabled`. Il n'est pas candidat.
- Le lien entre l'appel au pluriel lu dans le code et le nom au singulier des lignes est déduit.

## Méthode

Script : [origine-g7.sh](../essais/chains-v0300-signature/origine-g7.sh).
- `ec opa eval` (binaire du verrou), dans `unshare -rn` (boucle locale seule), sans signature ni registre.
- Entrée : les deux énoncés v0.29.9 gardés du passage -2 (`future-deny/travail/env-29.jsonl`, lu sans écriture). Les
  bundles y pointent vers le registre du banc, éteint : chaque demande échoue.
- Données :
  - `taches.yml` gardé du même passage ;
  - `rule_data__configuration__` de `service` (constructeurs admis), et de `regles` (plus `trusted_task_rules_enabled: true` et
    la règle `allow` du passage -2).
- Un processus par paquet et par politique : `deny` et `warn` du paquet seul. Puis un processus « ensemble » qui évalue les
  quatre paquets (`tasks`, `trusted_task`, `slsa_build_scripted_build`, `porte`) d'un coup.
- Compte des lignes de la sortie d'erreur par bundle et par fonction.

Limite écrite avant : la forme d'évaluation diffère d'`ec validate image`, qui n'évalue pas les paquets un par un. La seule
garde est le compte « ensemble », qui doit redonner 3 et 4.

## Prédictions (v0.29.9)

| N° | Mesure | Prédiction |
|---|---|---|
| O1 | garde de données | `trusted_task_rules_enabled` vaut `false` sous `service`, `true` sous `regles` ; `missing_trusted_task_rules_data` vaut `true` sous `service`, `false` sous `regles` |
| O2 | `service`, par paquet, lignes par bundle | `tasks` 1, `trusted_task` 1, `slsa_build_scripted_build` 1, `porte` 0 |
| O3 | `regles`, par paquet, somme par bundle | 4 ; un seul paquet passe à 2. Hypothèse non tranchée : `trusted_task` (le seul qui passe `_manifests` à `future_deny_rules_for_task`, ligne 132) |
| O4 | « ensemble » | 3 lignes par bundle sous `service`, 4 sous `regles` |
| O5 | fonction nommée | `ec.oci.image_manifest` seule, aucune autre |
| O6 | témoin v0.30.0, « ensemble » | 0 ligne sous les deux politiques (comme G7) |

Critère : si les comptes par paquet ne redonnent pas 3 et 4, ou si « ensemble » ne redonne pas 3 et 4, la note dira « non
expliqué » et rien ne sera relancé. Si aucune ligne n'apparaît du tout, `ec opa eval` ne journalise pas ces échecs comme
`ec validate image` : même conclusion.
