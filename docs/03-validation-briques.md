# Validation des briques

Résultats des briques et des bancs de l'ADR 0000, puis liste de ce qui reste à valider **sur l'infra du PoC (laptop)**. Les parties locales ont été validées dans un environnement cloud sans KVM, ni Docker, ni cluster (4 CPU, 15 Gi) : la logique, les formats et les tests négatifs qui n'ont pas besoin de Kubernetes. L'infra du PoC est un laptop bare metal avec KVM et virtualisation imbriquée ([inventaire et dimensionnement proposé](../poc/infra/README.md)).

Légende : **Validé (local)** = seuil atteint pour la partie testable ici ; **À compléter** = le reste du seuil demande l'infra du PoC.

## Bancs de l'ADR 0000

| Banc | Statut | Résultat | Détail |
|---|---|---|---|
| **B. Nix ou Hermeto** | Partie locale faite ; **B-1 de la référence mesuré sur 2 hôtes** | **Nix 74, référence 91**, banc clos le 29/10/2026 (B-1 = 5 de la référence validé) : binaire `99ddc97c` et image `3a7ca1b1` retrouvés sur le laptop, > 10 h après le cloud. Nix reste en veille. Constat : l'environnement de `hermeto generate-env` laisse passer un zip Go altéré | [résultats](../poc/benchmarks/nix/resultats/README.md) |
| **C. Kyverno seul ou Conforma + Kyverno** | Partie locale faite, **rejouée sur le laptop** (17/17, médianes 1 030 et 330 ms) | **76 / 63** (provisoire), décision suspendue (TSA, parité à l'admission). Constat : confusion signature / attestation de cosign v3 | [résultats](../poc/benchmarks/kyverno-seul/resultats/README.md) |
| **A1. Konflux** | **Fait sur le laptop** (29/10/2026, kind) | **17/57, non adopté** ; **éliminé** (critère 1, confirmé le 29/10/2026 : une PR lit la clé de Chains sur le nœud). Installation 7 min, premier build signé 1 h 24, image reproductible ; 3/8 tests négatifs bloqués ; constat : `tpa-scan`, exigée par la politique par défaut, envoie le SBOM à un service Red Hat | [résultats](../poc/benchmarks/konflux/resultats/README.md) |
| A2. OBS | **Fait sur le laptop** (29/10/2026, appliance master en VM KVM) | **42/55, non adopté** (grille restreinte ; lecture de A-1 et non-adoption validées le 29/10/2026). rpm et deb bit-identiques sur 2 builds, rebuild hors ligne identique, provenance DSSE non falsifiable (3 tentatives de falsification, 3 contrôles d'isolement). Constats : provenance seulement sur master (pas de release depuis 2019), snapshot.debian.org rejeté par le DoD d'OBS, initrd de l'appliance inutilisable pour les VM de build | [résultats](../poc/benchmarks/obs/resultats/README.md) |

## Briques

| # | Brique | Statut | Résultat local | Détail |
|---|---|---|---|---|
| 01 | forgejo-sync | **Validé (local)**, à compléter | Force-push et tag déplacé détectés (code 2) et archivés sous `refs/archive/<horodatage>` ; bundles incrémentaux exportés, rattrapage après échec ; restauration identique ; 10 tests unitaires réussis | [README](../poc/bricks/01-forgejo-sync/README.md) |
| 02 | artefact-store + index | **Validé (local)**, à compléter | `tools/index` sur 10 000 artefacts + 17 images cosign (referrers et tags `.att`) : **`built-with` en 1 ms, `attestations` d'un fichier brut en < 1 ms** (seuil 1 min), résultats exacts ; reconstruction complète en 58 s ; 5 tests unitaires | [README](../poc/bricks/02-artefact-index/README.md) |
| 03 | deps-closure | **Validé (local)**, à compléter | oras v1.3.5 → v1.3.6 : **92,9 % des octets partagés** (seuil 50 %), registre +0,68 Mo pour 6,4 Mo ; restauration par digest et build hors réseau identiques (oras, sample-app gomod + npm) ; blob altéré et pull par tag refusés | [README](../poc/bricks/03-deps-closure/README.md) |
| 04 | hermetic-repro | **Validé (local)**, à compléter | BuildKit éphémère sans Docker : image de build et **image sample-app identiques sur 2 builds sans cache et 2 chemins** ; binaire identique à celui compilé hors BuildKit ; négatifs refusés (sans fermeture, sortie réseau en `--network=none`) | [README](../poc/bricks/04-hermetic-repro/README.md) |
| 07a | sbom-grype | **Validé (local)**, à compléter | Base Grype officielle archivée dans Zot (empreinte vérifiée), restaurée par digest et importée **sans réseau** ; SBOM Hermeto + Syft fusionné ; **porte : cas ok PASS, cas KEV (log4j 2.14.1) FAIL** dans Conforma et Kyverno | [README](../poc/bricks/07a-sbom-grype/README.md) |
| 13a | licences déclarées + REUSE | **Validé (local)**, à compléter | oras v1.3.6 et sample-app : **0 ERROR, 0 NOASSERTION, 100 % d'expressions SPDX valides** ; négatifs refusés (GPL, expression invalide, licences non recherchées, source manquante) ; **bundle de sources en referrer** (rétention P10Y) ; dépôt et sample-app conformes REUSE ; 9 tests unitaires | [README](../poc/bricks/13a-licences/README.md) |

## Rejeu sur le laptop (29/10/2026)

Outils déclarés dans [`mise.toml`](../mise.toml) aux versions du cloud, sommes et signatures vérifiées ([`poc/infra`](../poc/infra/README.md)) ; registre Zot local ; BuildKit **rootless**.

| Brique ou banc | Résultat sur le laptop | Écart avec le cloud |
|---|---|---|
| `make test` | 24 tests sur 24 | **Corrigé** : `sync.py` (brique 01) lisait les messages de git, traduits sous `fr_FR.UTF-8` → git lancé avec `LC_ALL=C` |
| B (`hermeto.sh`) | Binaire `99ddc97c` et `web/dist` identiques ; T1 à T3 comme attendu | Aucun |
| Rejeu complet (`mise run bancs`) | Deux passages successifs : mêmes empreintes | Seuls varient le digest de la fermeture 03 (tuiles `sumdb`) et l'image de test de 13a |
| C | 17/17, mêmes motifs | Temps mesurés désormais avec une horloge monotone |
| 02 | Requêtes exactes, reconstruction en 23 s | Aucun sur les résultats |
| 03 | sample-app `e3749c68`, oras `cc397d5e` identiques ; dédup 92,9 % | Digest de fermeture différent (tuiles `sumdb` datées), attendu |
| 04 | **Image `3a7ca1b1` identique**, en rootless, avec le BuildKit du nixpkgs comme avec la release amont | Image **de build** différente : entrées non archivées par digest dans le cloud (enseignement pour la brique 11) |
| 07a | Mêmes vulnérabilités, porte PASS / FAIL | Base du jour |
| 13a | Sortie identique | **Corrigé** : le SBOM de Syft dépendait d'un `go` dans le `PATH` (module principal ajouté sans licence) |

**B-1 de la référence mesuré** : binaire et image identiques sur 2 hôtes à plus de 10 h d'écart (ADR 0000).

## À faire sur le laptop (infra du PoC)

Prérequis :
- infra du PoC : **ce laptop**, bare metal vérifié le 29/10/2026 (ADR 0001) ; dimensionnement **validé** le 29/10/2026 : kind jetable pour A1, trois VM libvirt + k3s pour 08 ([`poc/infra`](../poc/infra/README.md)) ;
- deuxième administrateur du domaine de replay : **à nommer** ;
- licence du dépôt : décidée, **Apache-2.0** (dépôt conforme REUSE 3.3).

| Sujet | Ce qui reste | Brique ou banc |
|---|---|---|
| Konflux | ~~Installation, premier build signé, grille A~~ (fait le 29/10/2026) ; cluster kind supprimé et Forgejo arrêté le 29/10/2026 (données de Forgejo conservées dans `~/.cache/supply-chain-poc/forgejo`) ; ~~confirmation de l'élimination~~ (confirmée le 29/10/2026) | A1 |
| OBS | ~~rpm et deb bit-identiques sur 2 builds, grille A restreinte~~ (fait le 29/10/2026) ; VM, pool, réseau et cache (appliance comprise) supprimés le 29/10/2026, sur décision du propriétaire : le banc n'est plus rejouable à l'identique ; ~~lecture de A-1 et non-adoption~~ (validées le 29/10/2026) ; ~~critère 5~~ (jugé non éliminatoire le 29/10/2026) | A2 |
| Nix | ~~B-1 de la référence~~ (fait le 29/10/2026) ; ~~B-1 de Nix sur un second hôte, B-5~~ : abandonnés, banc clos le 29/10/2026 (Nix en veille) | B |
| Kyverno seul | Contrôle 9 (horodatage RFC 3161) ; parité CLI / admission ; bibliothèque Conforma `slsa3` / `trusted_task` sur une vraie provenance Chains | C, 08 |
| Plan de confiance | k3s, Tekton, Chains (mode `dsse` tant que tektoncd/chains#2096 n'est pas publiée), OpenBao, job TSA, Trusted Resources, Kyverno, Conforma, intercepteur HMAC ; **les 8 tests négatifs**. [Protocole](../poc/bricks/08-trust-plane/README.md) validé le 29/10/2026 (k3s v1.35.9, plage testée par Kyverno 1.19 ; VM Debian 13, image sans signature publiée ; 65 Go). **J1 fait** : 3 VM et 3 nœuds k3s `Ready`, 63 s depuis zéro (téléchargements en cache) ; x86-64-v3 sans v4, `/dev/kvm` dans `sc-build`, taint de zone build, audit de l'API, jeton du server confiné au nœud de confiance (agents joints par un jeton agent qui épingle la CA). Constat : l'image Debian 13 exige une carte VGA pour démarrer. **J2 fait** : CA du PoC à contraintes de nom (un certificat hors du PoC est refusé) ; Zot et Forgejo en services systemd durcis sur `sc-stockage`, binaires de `mise.toml` revérifiés dans la VM ; Zot en lecture anonyme et écriture par un seul compte sans suppression ; push et pull par digest (hôte, puis pod de `sc-build` avec la CA déclarée à containerd) ; refus 401, 403 et x509 tracés ; dépôt `workspace/sample-app` (commit déterministe `6391fd43`) ; git par apt sur `sc-stockage` (accord) ; kubectl 1.35.10 dans `mise.toml` ; aucun des 9 secrets dans les journaux des VM (contrôle `fuites.sh` avec témoin positif, à rejouer à chaque jalon) ; **rejeu de J1 et J2 depuis zéro : 109 s**. Constats : `zot verify` ne valide presque rien ; course SIGPIPE corrigée dans `k3s.sh`. **J3 fait** : OpenBao 2.7.2 (image vérifiée par identité exacte, copiée dans Zot et revérifiée) sur `sc-confiance`, durci (non root, Pod Security restricted, NetworkPolicy), audit actif avant toute configuration ; clé Transit `chains` non exportable ; authentification JWT réservée au compte de service de Chains (audience `openbao`, jetons batch de 5 min) ; signature vérifiée par openssl ; refus tracés (autre compte, autre audience, export, réseau depuis `sc-build` en NFLOG) ; Chains vérifié dans son code : `oidc.token-path` sans SPIRE, signataire recréé à chaque signature ; **rejeu de J1 à J3 depuis zéro : 219 s**. Limites : la clé reste rendable exportable par l'administrateur ; `bound_subject` seul, RBAC et Kyverno à poser en J6. Suite : J4 (Tekton, Chains, Triggers), sur accord et après décision sur les images non vérifiables | 08 |
| Synchronisation | Vrai Forgejo (`mirror/` réservé au compte de sync, fork `workspace/`), **build d'une branche custom**, CronJob, métrique « dernière sync », mesure sur Traefik | 01, 19 |
| Fermetures | Tâches prefetch et build Tekton (chemins fixes, fermeture en lecture seule, digest dans `resolvedDependencies`) ; Traefik (gomod + yarn berry) et tests d'altération yarn | 03, 04 |
| Scan | Import quotidien de la base Grype (CronJob) vers un volume en lecture seule ; scan en tâche de confiance signé par la clé du scanner ; images et rpm/deb (`distro=`) | 07a |
| Licences | Tâche de confiance signée ; rpm/deb : licences des métadonnées de distro en SPDX, SRPM et `.dsc` en referrer | 13a, 05, 06 |
| Images | BuildKit **en pod** (rootless avec seccomp/AppArmor, ou Kata), push en tâche séparée, NetworkPolicy deny-all ; ~~2 hôtes à ≥ 1 h d'écart~~ (fait le 29/10/2026, BuildKit rootless hors pod) ; entrées de l'image de build archivées par digest (brique 11) | 04, B |
| Packaging | mock (rocky-9) et sbuild (debian-13) bit-identiques, isolation user namespace, gVisor ou Kata | 05, 06 |
| Replay | Domaine d'administration distinct, clé de VSA séparée, ≥ 24 h d'écart | 10 |
| Observabilité | Prometheus, Alertmanager, Grafana ; 5 alertes critiques sur incident simulé | 19 |
