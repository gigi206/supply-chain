# supply-chain

Plateforme de **supply-chain logicielle** auto-hébergée. Elle vise à :
- rejouer un build **bit à bit** et le prouver ;
- archiver les artefacts et **toutes** les dépendances ;
- produire SBOM et provenance ;
- rejouer un build complet **offline** ;
- calculer un score de fiabilité (vulnérabilités, santé des projets amont) ;
- faire une **analyse de licences complète** ;
- synchroniser des dépôts git distants et y créer des **branches custom** ;
- produire des **rpm et deb** multi-distro (Debian, Ubuntu, Rocky, Alma, CentOS Stream) ;
- atteindre **SLSA Build L3**.

> **Statut : phase 1, étude.** Aucune brique n'est encore déployée.

## Existe-t-il un projet open source qui fait tout ça ?

**Non.** Le plus proche est **[Konflux](https://github.com/konflux-ci/konflux-ci)** (Red Hat : Tekton, Chains, Hermeto, Conforma), mais il n'a pas les deb, ni une intégration Forgejo solide, ni Dependency-Track, ni l'analyse de licences complète, ni la vérification de rebuild indépendante. **[OBS](https://github.com/openSUSE/open-build-service)** couvre très bien les rpm et deb, mais pas le reste.

**Tekton Chains** est aujourd'hui le seul composant open source auto-hébergeable qui signe la provenance **hors de portée du build**, l'exigence clé de L3. Les autres options plafonnent plus bas :
- Argo Workflows : L1 à L2 ;
- GitLab self-managed : L2 ;
- Forgejo Actions, Woodpecker, Jenkins : L2 ;
- Witness : L2.

La plateforme s'assemble donc autour de Tekton + Chains, avec des briques complémentaires. Ce « Konflux allégé » est l'hypothèse par défaut ; Konflux et OBS sont benchmarkés avant de trancher (ADR 0000), ainsi que deux challengers : **Nix** comme moteur de build et **Kyverno** comme moteur de politique unique.

Détails, alternatives et sources : [`docs/00-etude-existant.md`](docs/00-etude-existant.md).

## Documents

| Document | Contenu |
|---|---|
| [`docs/00-etude-existant.md`](docs/00-etude-existant.md) | Étude des alternatives par domaine, avec pour, contre et sources |
| [`docs/01-exigences.md`](docs/01-exigences.md) | Besoins et critères vérifiables, modèle de menace, exigences SLSA L3 → contrôles → **tests négatifs** |
| [`docs/02-architecture.md`](docs/02-architecture.md) | Architecture cible, flux de build, modèle de provenance, stockage, porte et score, clés, observabilité |
| [`docs/04-sante-projets.md`](docs/04-sante-projets.md) | Audit de santé des projets (Scorecard, activité, signatures), plans de sortie |
| [`docs/adr/`](docs/adr/README.md) | Décisions d'architecture (ADR 0001 provisoire) |
| [`tools/health/`](tools/health/) | Script de ré-audit trimestriel (`scorecard.sh`, `projects.tsv`) |

## Briques principales (hypothèse « Konflux allégé »)

| Domaine | Brique |
|---|---|
| Sources | Forgejo (miroir + fork `workspace/` à branches custom) + job de sync (pas de prune, détection des force-push, `git bundle`) |
| Orchestration et provenance | Tekton Pipelines LTS + Triggers (intercepteur HMAC Forgejo) + **Chains ≥ 0.29** (SLSA v1, `sigstore-bundle` en OCI referrers) |
| Dépendances | Hermeto (prefetch + SBOM), verrou natif mock, `.buildinfo` Debian ; snapshots Pulp en 2c |
| Construction | BuildKit avec démon éphémère par build (repli : Buildah), mock 6.x hermétique, sbuild unshare ; isolation Kata, gVisor ou user namespace |
| Stockage | Zot + ORAS (artefacts, fermetures, attestations) ; archive WORM en 2c |
| Signature | cosign + OpenBao Transit, horodatage RFC 3161, service OpenPGP isolé (HSM), TUF pour les clés publiques |
| Politique | Conforma (porte de release) + Kyverno ≥ 1.19.2 (admission) ; VSA émises par nous |
| SBOM et vulnérabilités | Syft, Grype (base datée), OSV, Dependency-Track v5 (projection), VEX (OpenVEX signé) |
| Licences | Syft + REUSE (2b), ORT + ScanCode (2c) |
| Vérification | Rebuild **dans un domaine d'administration distinct**, diffoscope, reprotest |
| Observabilité | Prometheus + Alertmanager + Grafana (exploitation, puis KPI supply-chain dérivés des attestations) |

## Phases et effort

Les efforts sont en personnes-semaines (pw), estimés. Une brique qui dépasse 2× son estimation déclenche une décision.

| Phase | Contenu | Effort |
|---|---|---|
| **1. Étude** (en cours) | Étude, exigences, architecture, audit de santé, ADR 0001 provisoire | ~2 pw |
| **2a. Adopter ou assembler** | Grille pondérée fixée d'avance ; benchmarks Konflux, OBS, Nix (build) et Kyverno seul (politique) → **ADR 0000** | ~2,5 pw |
| **2b-1. Cœur L3** (`make slice-1`) | Briques 01, 08, 19, 03, 04, 02, 07a, 10 | ~14 pw |
| **2b-2. Packaging** (`make slice-2`) | Briques 05, 06, 09, 13a | ~7 pw |
| **3. ADR** | ADR 0001 (définitif), 0003, 0004, 0005, puis **point de décision « go 2c »** | ~1 pw |
| **2c. Élargissement** | Briques 07b, 13b, 11, 14, 15, 16, 17, 20 ; ADR 0002 et 0006 | ~18,5 pw |
| **4. E2E** | Projet réel mirroré, matrice complète, sauvegarde/restauration (12) | ~4 pw |
| Option O8 | Radar amont et tableau de bord (18) | ~3 pw |
| **Total** | | **≈ 49 pw (≈ 52 avec O8)** |

## Briques et seuils

| # | Brique | Phase | pw | Seuil go/no-go |
|---|---|---|---|---|
| 01 | forgejo-sync | 2b-1 | 1 | Branche custom buildée ; force-push amont détecté et archivé ; `git bundle` exporté |
| 08 | trust-plane (k3s) | 2b-1 | 5,5 | Tekton + HMAC, Chains (stockage prouvé), OpenBao, job TSA (chemin de vérification choisi), Trusted Resources, Kyverno, Conforma, RBAC, nœuds dédiés, posture des pipelines ; **8 tests négatifs** échouent comme attendu |
| 19 | observabilité exploitation | 2b-1 | 0,5 | Les 5 alertes critiques se déclenchent sur incident simulé |
| 03 | deps-closure | 2b-1 | 1 | Fermetures restaurables par digest ; déduplication ≥ 50 % |
| 04 | hermetic-repro | 2b-1 | 1,5 | 0 connexion sortante ; 2 builds → même sha256 (binaire, image) |
| 02 | artefact-store + index | 2b-1 | 1,5 | Attestations récupérables ; `tools/index` répond en moins d'une minute |
| 07a | sbom-grype | 2b-1 | 1 | Sans egress ; la porte bloque un cas KEV |
| 10 | independent-replay | 2b-1 | 2 | Domaine distinct, clé de VSA séparée, ≥ 24 h : bit-identique + VSA |
| 05 | rpm-mock (rocky-9) | 2b-2 | 2,5 | Bit-identique ; 0 pod privilégié sur l'hôte |
| 06 | deb-sbuild (debian-13) | 2b-2 | 2 | Bit-identique ; 0 pod privilégié sur l'hôte |
| 09 | openpgp-signing | 2b-2 | 1,5 | rpm, deb et dépôt signés ; attestation de lien vérifiée |
| 13a | licences déclarées + REUSE | 2b-2 | 1 | 0 `NOASSERTION`, 0 violation ERROR, sources GPL attachées |
| 07b | DT v5 + VEX + OSV + score | 2c | 3 | Ré-ingest testé ; test négatif sur la correspondance des PURL dans les VEX |
| 13b | ORT + ScanCode | 2c | 3 | 0 egress hors plateforme ; précision et rappel ≥ 95 % (avec un référent juridique) |
| 11 | builder-bootstrap | 2c | 1,5 | Toolchain Go StageX reproduite ; images mock et sbuild reconstruites |
| 14 | snapshots-distro | 2c | 2 | Rebuild offline depuis un snapshot ; ADR 0002 |
| 15 | archive-worm | 2c | 2 | Suppression refusée ; ADR 0006 |
| 16 | matrice complète | 2c | 4 | debian-12, ubuntu-24.04, alma-9, centos-stream-10 ; EL8 documenté |
| 17 | hermeticity-trace | 2c | 1,5 | Trace Tetragon `runtime-trace` signée |
| 20 | KPI supply-chain | 2c | 1,5 | 0 écart avec le recalcul depuis les attestations |
| 12 | backup-restore | 4 | 2 | Restauration complète, puis replay d'un ancien build |
| 18 | radar (option O8) | 4 | 3 | Voir le plan |

## Principes

- **Les attestations signées sont la source de vérité.** Index, score, Dependency-Track et métriques en sont des projections reconstructibles.
- **Portes binaires** (Conforma, Kyverno) et **score informatif** (versionné) sont séparés.
- **Tout est épinglé par digest** et mis à jour par Renovate. Un projet « Risqué » n'est jamais utilisé.
- L3, reproductibilité et hermétisme sont **trois propriétés distinctes**, prouvées séparément.

## Ré-audit de santé

```bash
tools/health/scorecard.sh > /tmp/scorecard.md
```
