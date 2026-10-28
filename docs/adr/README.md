# Architecture Decision Records

| ADR | Sujet | Statut | Décision attendue |
|---|---|---|---|
| 0000 | Adopter (Konflux, OBS) ou assembler ; challengers Nix (build) et Kyverno seul (politique) | À rédiger | Fin de la phase 2a, avec une grille pondérée **fixée avant** les benchmarks |
| [0001](0001-runtime-isolation.md) | Runtime, isolation des builds, infrastructure du PoC | **Proposé (provisoire)** | Définitif en phase 3 |
| 0002 | Fermeture des dépendances et snapshots de distros (Pulp ou aptly) | À rédiger | Fin de 2c (brique 14) |
| 0003 | Clés, signature (OpenBao, OpenPGP), horodatage, TUF | À rédiger | Phase 3 |
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
