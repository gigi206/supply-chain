# Architecture Decision Records

| ADR | Sujet | Statut | Décision attendue |
|---|---|---|---|
| [0000](0000-assembler-ou-adopter.md) | Adopter (Konflux, OBS) ou assembler ; challengers Nix (build) et Kyverno seul (politique) | **Proposé, grille figée le 28/10/2026** | Fin de la phase 2a (résultats en annexe) |
| [0001](0001-runtime-isolation.md) | Runtime, isolation des builds, infrastructure du PoC | **Proposé (provisoire)** | Définitif en phase 3 |
| 0002 | Fermeture des dépendances et snapshots de distros (Pulp ou aptly). Exigence du propriétaire (30/10/2026) : si Pulp est retenu, écrire les plugins manquants, comme `pulp_go` (Go, écrit, travail en cours ; alternative à Athens) ; voir doc 00 §11 | À rédiger | Fin de 2c (brique 14) |
| 0003 | Clés, signature (OpenBao, OpenPGP), horodatage, TUF | À rédiger | Phase 3. Entrées mesurées : brique 08, J3 (clé de provenance Transit) et J5 (clé `tsa` séparée, racine TSA dédiée, jeton OpenBao périodique, chemin de vérification) et J6 (clé des tâches de Trusted Resources, distincte ; horodatage automatique, enveloppe vérifiée par la clé de Chains avant toute demande au TSA) |
| 0004 | Vulnérabilités et VEX (OpenVEX ou CSAF) | À rédiger | Phase 3 |
| 0005 | Licences (politique ORT et DT, curations) | À rédiger | Phase 3 |
| 0006 | Archive WORM (Ceph hors cluster ou S3 Object Lock compliance) | À rédiger | Fin de 2c (brique 15) |

## Gabarit

```markdown
# ADR NNNN : titre

- **Statut** : Proposé | Accepté | Remplacé par NNNN
- **Date** :
- **Décideurs** :

## Contexte
## Options (avec pour, contre et santé des projets ; voir docs/04)
## Décision
## Conséquences (y compris le plan de sortie)
```
