# Résultats du banc B : Nix ou référence (28/10/2026, partie locale)

Grille : [ADR 0000 §3](../../../../docs/adr/0000-assembler-ou-adopter.md) (figée avant le banc). Banc d'essai : [`poc/sample-app`](../../../sample-app) (Go + interface npm embarquée).

## Environnement

| Élément | Détail |
|---|---|
| Hôte | 4 CPU, 15 Gi, sans KVM ni Docker ; Nix 2.34.6 mono-utilisateur, sandbox actif |
| nixpkgs | `nixos-25.11` révision `b6018f87da91`, archive immuable de releases.nixos.org figée par `flake.lock` (narHash) |
| Candidat Nix | [`flake.nix`](../flake.nix) : `buildNpmPackage` (interface), `buildGoModule` (binaire, Go 1.25.10), `dockerTools.buildLayeredImage` (image) |
| Référence | **Hermeto non exécuté** : son installation depuis les sources a été refusée par le garde-fou d'exécution de code externe de la session (pas de paquet PyPI ni nixpkgs, pas de Docker). On mesure la **solution de repli du plan**, le vendoring natif (`go mod vendor`, cache npm), avec Go 1.24.7 et Node de l'hôte. BuildKit n'est pas disponible (pas de démon) |

## Mesures

| Critère | Nix | Référence (vendoring natif) |
|---|---|---|
| **B-1** bit à bit | `nix build --rebuild` : interface, binaire et **image** identiques. Également identiques après reconstruction **dans un store vierge, sans réseau** (voir B-2) | Binaire et interface identiques entre 2 builds hors réseau, dans 2 chemins différents, cache Go vide. **Image non testée** (pas de BuildKit) |
| **B-2** rebuild offline depuis l'archive | **Réussi** : `nix copy` de la fermeture de build vers un cache `file://`, puis store Nix vierge, `unshare -n` (aucune interface réseau) : substitution puis `--rebuild` → identique. **Toolchains incluses** dans l'archive | Réussi pour le binaire, mais les **toolchains (Go, Node) viennent de l'hôte** et ne sont pas dans la fermeture : sur la plateforme, c'est le rôle de l'image de build archivée par digest |
| **B-3** taille et déduplication | Fermeture de build complète : **1 531 Mo** (457 Mo en zstd), toolchains comprises. Version suivante (1.0.1) : **+9,0 Mo** seulement (99,4 % partagés). Les dérivations de dépendances sont refaites car leur nom porte la version (≈ 200 Kio) | Fermeture des dépendances : **276 Kio** (vendor Go + cache npm), **hors toolchains** |
| **B-4** SBOM et PURL standards | **sbomnix 1.7.4** : uniquement des `pkg:nix` (3 à l'exécution ; 839 + 51 sans PURL au build), **0 % corrélable** par Grype ou DT. **Syft sur l'image** : 3 `pkg:golang` (application, chi v5.2.3, stdlib 1.25.10) + 4 `pkg:nix`, mais **`marked` (npm, embarqué) absent** | **Syft sur sources et lockfiles** : `pkg:golang/…/chi@v5.2.3` + `pkg:npm/marked@16.4.1` ; sur le binaire : chi + stdlib 1.24.7. 100 % des dépendances en PURL standards. Hermeto produirait aussi un SBOM CycloneDX standard |
| **B-5** Tekton + Chains, pod non privilégié | Non mesuré (il faut un cluster). Le sandbox Nix fonctionne ici en root ; en pod, il exige des user namespaces | Non mesuré |
| **B-6** coût d'adoption | Flake de 49 lignes ; ≈ 2 h, dont la résolution d'un **piège de TLS** : `fetchNpmDeps` utilise son propre bundle de CA tant que le hash est factice, donc échoue derrière un proxy TLS d'entreprise. Il faut calculer le hash hors sandbox (`prefetch-npm-deps`) | Commandes natives connues ; < 0,5 j |
| **B-7** santé | Nix/nixpkgs : À surveiller (forks, CVE de sandbox 2025-2026) | Hermeto, BuildKit : À surveiller (doc 04) |

## Notation provisoire (critères mesurés seulement : B-1, B-2, B-3, B-4, B-6, B-7 ; 85 points sur 100)

| Critère | Poids | Nix | Justification | Référence | Justification |
|---|---|---|---|---|---|
| B-1 | 25 | 4 | Binaire, interface et image identiques, y compris en store vierge hors réseau ; manque 2 hôtes à ≥ 1 h d'écart | 3 | Binaire et interface identiques ; image non testée |
| B-2 | 20 | 5 | Offline complet, toolchains incluses | 3 | Offline, mais toolchains hors fermeture (à archiver via l'image de build) |
| B-3 | 10 | 3 | Fermeture lourde (toolchains) mais déduplication excellente | 4 | Fermeture minime, mais hors toolchains |
| B-4 | 15 | 2 | SBOM natif inexploitable (`pkg:nix`) ; Syft ne décrit qu'en partie l'artefact réel | 5 | PURL standards complets |
| B-6 | 10 | 4 | Rapide, mais piège TLS et second écosystème | 5 | Outils connus |
| B-7 | 5 | 3 | À surveiller | 3 | À surveiller |
| **Score sur les critères mesurés** | 85 | **63 → 74/100** | | **63 → 74/100** | |

**Lecture provisoire** : **égalité (74 / 74)**. La règle de décision exige **+15 points** pour Nix : elle n'est pas atteinte, **Nix reste en veille** sauf si les mesures restantes le départagent nettement (B-1 sur 2 hôtes, B-5 en pod userns). Les deux approches ont des forces complémentaires :
- **Nix** l'emporte sur la reconstruction offline complète, toolchains et image incluses ;
- **la référence** l'emporte sur l'exploitabilité du SBOM et sur le coût.

**Enseignements utiles même si Nix n'est pas retenu :**
- La fermeture de référence doit **inclure les toolchains** : image de build archivée par digest, ou toolchains en artefacts OCI. Sinon le replay dans 10 ans n'est pas garanti.
- Le SBOM doit décrire **l'artefact réellement construit**. Un SBOM issu des seuls lockfiles rate les toolchains ; un SBOM d'image rate les dépendances embarquées (`marked`). Il faut **combiner** le SBOM de fermeture (Hermeto) et celui de l'artefact (Syft).
- Derrière un **proxy TLS d'entreprise**, les fetchers qui embarquent leur propre bundle de CA posent problème : c'est à prévoir pour Hermeto et les autres outils de prefetch.
