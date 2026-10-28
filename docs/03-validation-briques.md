# Validation des briques

Résultats des briques et des bancs de l'ADR 0000, puis liste de ce qui reste à valider **sur l'infra du PoC (laptop)**. L'environnement de développement actuel n'a ni KVM, ni Docker, ni cluster (4 CPU, 15 Gi) : on y valide la logique, les formats et les tests négatifs qui n'ont pas besoin de Kubernetes.

Légende : **Validé (local)** = seuil atteint pour la partie testable ici ; **À compléter** = le reste du seuil demande l'infra du PoC.

## Bancs de l'ADR 0000

| Banc | Statut | Résultat | Détail |
|---|---|---|---|
| **B. Nix ou Hermeto** | Partie locale faite | **74 / 74** (provisoire) : Nix reste en veille. Constat : l'environnement de `hermeto generate-env` laisse passer un zip Go altéré | [résultats](../poc/benchmarks/nix/resultats/README.md) |
| **C. Kyverno seul ou Conforma + Kyverno** | Partie locale faite | **76 / 63** (provisoire), décision suspendue (TSA, parité à l'admission). Constat : confusion signature / attestation de cosign v3 | [résultats](../poc/benchmarks/kyverno-seul/resultats/README.md) |
| A1. Konflux, A2. OBS | **Laptop** | — | [protocoles](../poc/benchmarks/README.md) |

## Briques

| # | Brique | Statut | Résultat local | Détail |
|---|---|---|---|---|
| 01 | forgejo-sync | **Validé (local)**, à compléter | Force-push et tag déplacé détectés (code 2) et archivés sous `refs/archive/<horodatage>` ; bundles incrémentaux exportés, rattrapage après échec ; restauration identique ; 10 tests unitaires réussis | [README](../poc/bricks/01-forgejo-sync/README.md) |
| 02 | artefact-store + index | **Validé (local)**, à compléter | `tools/index` sur 10 000 artefacts + 17 images cosign (referrers et tags `.att`) : **`built-with` en 1 ms, `attestations` d'un fichier brut en < 1 ms** (seuil 1 min), résultats exacts ; reconstruction complète en 58 s ; 5 tests unitaires | [README](../poc/bricks/02-artefact-index/README.md) |
| 03 | deps-closure | **Validé (local)**, à compléter | oras v1.3.5 → v1.3.6 : **92,9 % des octets partagés** (seuil 50 %), registre +0,68 Mo pour 6,4 Mo ; restauration par digest et build hors réseau identiques (oras, sample-app gomod + npm) ; blob altéré et pull par tag refusés | [README](../poc/bricks/03-deps-closure/README.md) |
| 07a | sbom-grype | **Validé (local)**, à compléter | Base Grype officielle archivée dans Zot (empreinte vérifiée), restaurée par digest et importée **sans réseau** ; SBOM Hermeto + Syft fusionné ; **porte : cas ok PASS, cas KEV (log4j 2.14.1) FAIL** dans Conforma et Kyverno | [README](../poc/bricks/07a-sbom-grype/README.md) |
| 13a | licences déclarées + REUSE | **Validé (local)**, à compléter | oras v1.3.6 et sample-app : **0 ERROR, 0 NOASSERTION, 100 % d'expressions SPDX valides** ; négatifs refusés (GPL, expression invalide, licences non recherchées, source manquante) ; **bundle de sources en referrer** (rétention P10Y) ; sample-app conforme REUSE ; 9 tests unitaires | [README](../poc/bricks/13a-licences/README.md) |

## À faire sur le laptop (infra du PoC)

Prérequis : décider l'infra du PoC (ADR 0001) et nommer le deuxième administrateur du domaine de replay. **Décision également attendue : la licence du dépôt `supply-chain`**, préalable à sa conformité REUSE.

| Sujet | Ce qui reste | Brique ou banc |
|---|---|---|
| Konflux | Installation, premier build signé, grille A | A1 |
| OBS | rpm et deb bit-identiques sur 2 builds, grille A restreinte | A2 |
| Nix | B-1 sur 2 hôtes à ≥ 1 h d'écart ; B-5 (sandbox Nix en pod userns sous Tekton + Chains) | B |
| Kyverno seul | Contrôle 9 (horodatage RFC 3161) ; parité CLI / admission ; bibliothèque Conforma `slsa3` / `trusted_task` sur une vraie provenance Chains | C, 08 |
| Plan de confiance | k3s, Tekton, Chains (mode `dsse` tant que tektoncd/chains#2096 n'est pas publiée), OpenBao, job TSA, Trusted Resources, Kyverno, Conforma, intercepteur HMAC ; **les 8 tests négatifs** | 08 |
| Synchronisation | Vrai Forgejo (`mirror/` réservé au compte de sync, fork `workspace/`), **build d'une branche custom**, CronJob, métrique « dernière sync », mesure sur Traefik | 01, 19 |
| Fermetures | Tâches prefetch et build Tekton (chemins fixes, fermeture en lecture seule, digest dans `resolvedDependencies`) ; Traefik (gomod + yarn berry) et tests d'altération yarn | 03, 04 |
| Scan | Import quotidien de la base Grype (CronJob) vers un volume en lecture seule ; scan en tâche de confiance signé par la clé du scanner ; images et rpm/deb (`distro=`) | 07a |
| Licences | Tâche de confiance signée ; rpm/deb : licences des métadonnées de distro en SPDX, SRPM et `.dsc` en referrer | 13a, 05, 06 |
| Images | BuildKit (démon éphémère, `rewrite-timestamp`) : image bit-identique | 04 |
| Packaging | mock (rocky-9) et sbuild (debian-13) bit-identiques, isolation user namespace, gVisor ou Kata | 05, 06 |
| Replay | Domaine d'administration distinct, clé de VSA séparée, ≥ 24 h d'écart | 10 |
| Observabilité | Prometheus, Alertmanager, Grafana ; 5 alertes critiques sur incident simulé | 19 |
