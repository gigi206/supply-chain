# Benchmarks de la phase 2a

Protocoles des évaluations définies par l'[ADR 0000](../../docs/adr/0000-assembler-ou-adopter.md). La grille de notation y est **figée** : les protocoles ci-dessous disent *comment* mesurer, pas *comment noter*.

| Dossier | Évaluation | Durée max | Environnement |
|---|---|---|---|
| [`konflux/`](konflux/) | A1 : adopter Konflux comme cœur ? | 3 jours | Infra du PoC (ADR 0001) |
| [`obs/`](obs/) | A2 : adopter OBS pour le packaging ? | 3 jours | Hôte avec KVM |
| [`nix/`](nix/) | B : Nix comme moteur de build ? | 3 jours | Partiellement local, second hôte pour B-1 |
| [`kyverno-seul/`](kyverno-seul/) | C : Kyverno comme moteur de politique unique ? | 2 jours | Local (CLI) ; cluster pour la parité avec l'admission |

Règles :
- chaque mesure est archivée dans `<dossier>/resultats/` (commandes, journaux, sorties) ;
- les versions et digests des outils utilisés sont notés ;
- au-delà de la durée maximale, les critères restants sont « non démontrés ».
