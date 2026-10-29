# Brique 08 : plan de confiance sur k3s

Seuil (README, brique 08) : Tekton + HMAC, Chains (stockage prouvé), OpenBao, job TSA (chemin de vérification choisi), Trusted Resources, Kyverno, Conforma, RBAC, nœuds dédiés, posture des pipelines ; **les 8 tests négatifs du doc 01 échouent comme attendu**, chacun avec une trace.

On termine aussi le banc C : contrôle 9 (horodatage RFC 3161), C-2 (parité entre CLI et admission), et bibliothèque Conforma `slsa3` / `trusted_task` sur une vraie provenance Chains.

**Effort estimé : 5,5 pw.** Une décision avec le propriétaire est déclenchée à 11 pw. Le temps passé est relevé jalon par jalon dans `resultats/chrono.tsv`, ouvert à l'accord.

**Statut (29/10/2026) : protocole proposé, en attente de l'accord du propriétaire.** Rien n'est créé ni téléchargé.

## Topologie

Trois VM libvirt avec k3s (topologie T2, profil nominal, [`poc/infra`](../../infra/README.md)) :

| VM | Rôle k3s | vCPU | RAM | Disque | IP |
|---|---|---|---|---|---|
| `sc-confiance` | server : contrôleurs Tekton, Chains, Triggers, OpenBao, Kyverno, TSA | 4 | 8 Gi | 15 Go | 192.168.161.11 |
| `sc-build` | agent, taint `zone=build:NoSchedule` : TaskRuns, Kata imbriqué | 6 | 10 Gi | 30 Go | 192.168.161.12 |
| `sc-stockage` | agent : Forgejo, Zot | 2 | 6 Gi | 20 Go | 192.168.161.13 |
| **Total** | | **12** | **24 Gi** | **65 Go** | |

- **Disque ramené de 70 à 65 Go.** `/` a 88 Go libres au 29/10/2026, et la règle « disques provisionnés < espace libre − 20 Go » plafonne le total à 68 Go. On retire 5 Go à `sc-stockage`, ce qui suffit pour Forgejo et Zot à l'échelle du PoC. Prometheus et Grafana viendront à la brique 19, avec un nouveau calcul.
- **RAM** : 30 Gi disponibles au 29/10/2026. Les 24 Gi du profil nominal laissent donc 6 Gi à la session de bureau.
- **CPU** : modèle `Haswell-v4` avec `check='partial'` sur les trois VM, et `vmx` exigé sur `sc-build`. Le modèle XML est celui du banc A2 : [`sc-obs.xml`](../../benchmarks/obs/libvirt/sc-obs.xml).
- **Réseau** : NAT dédié `supply-chain-poc` (pont `virbr-scpoc`, 192.168.161.0/24), repris du banc A2 ([`reseau.xml`](../../benchmarks/obs/libvirt/reseau.xml)), sans démarrage automatique.
- **Pool** : `supply-chain-poc` dans `/var/lib/libvirt/supply-chain-poc`.
- **Images** : image cloud officielle et graine cloud-init NoCloud construite avec `genisoimage`, présent sur l'hôte.
- **Accès** : `KUBECONFIG` dédié, `~/.kube/supply-chain-poc.yaml`, jamais fusionné dans `~/.kube/config` ; clé SSH dédiée dans `~/.cache/supply-chain-poc/08/`.

## Versions proposées et vérification

Relevé du 29/10/2026. Le choix de la version de k3s et celui de l'image des VM sont soumis au propriétaire.

| Composant | Version | Où | Vérification disponible |
|---|---|---|---|
| Image des VM | **Ubuntu 24.04 LTS**, `release-20261017` (recommandée) | 3 VM | `SHA256SUMS` signé (`SHA256SUMS.gpg`) par la clé `D2EB 4462 6FDD C30B 513D 5BB7 1A5D 6C4C 7DB8 7C81` ; cette clé figure aussi dans `/usr/share/keyrings/ubuntu-cloudimage-keyring.gpg` sur l'hôte, ce qui fait un 2e canal |
| (alternative) | Debian 13, `20261026-2643` | 3 VM | `SHA512SUMS` **sans signature** (ni `.sign` ni `.asc` dans le répertoire daté). Or `poc/infra` exige « empreinte et signature » |
| k3s | **v1.35.9+k3s1** (recommandée) | 3 VM | **sha256 seulement** : `sha256sum-amd64.txt` ; ni `.sig`, ni `.pem`, ni bundle, ni attestation GitHub, ni attestation de release. Binaire `897acb21…`. Images système via `k3s-airgap-images-amd64.tar.zst`, sur la même somme |
| Tekton Pipelines | v1.15.5 (LTS, fin de vie 31/07/2027) | confiance | **Non vérifiable** (doc 04 §5) : `release.yaml` non signé ; images signées par une clé qui ne correspond pas à la clé documentée |
| Tekton Chains | v0.29.9, mode **`dsse`** (chains#2096 toujours ouverte au 29/10/2026) | confiance | Non vérifiable (doc 04 §5) |
| Tekton Triggers | v0.37.2 | confiance | Non vérifiable (même processus de release) |
| OpenBao | 2.7.2 | confiance | Image signée sans clé (GitHub OIDC), vérifiée en doc 04 |
| timestamp-authority | v2.2.0 | confiance | **Attestation de release GitHub vérifiée** (`gh release verify`, tag `1110890…`) et provenance SLSA v1 du workflow `release.yaml@refs/tags/v2.2.0` ; binaire `327980b4…` |
| Kyverno | v1.19.2 | confiance | Image signée sans clé, signatures dans `ghcr.io/kyverno/signatures` (doc 04) |
| Conforma `ec` | v0.10.42 (celle du banc C) | hôte (mise) et tâche | sha256 seulement (doc 04) |
| Kata Containers | 4.3.1 (`kata-deploy`) | build | **Attestation de release GitHub vérifiée** (`gh release verify`, tag `03cf2ec…`) : `kata-deploy-4.3.1.tgz` `c2507741…`, `kata-static-4.3.1-amd64.tar.zst` `1463a2b8…`. L'image `kata-deploy` reste à vérifier au jalon J7 |
| Forgejo | v15.0.11 (LTS) | stockage | GPG, déjà vérifié au banc A1 (`mise.toml`) |
| Zot | v2.1.22 | stockage | sha256 seulement, **non signé** (doc 04) |

**Images d'outils non vérifiables** (Tekton Pipelines, Chains, Triggers, Zot ; Conforma s'il tourne en image) : leur reconstruction depuis les sources relève de la brique 11 (2c). Pour la brique 08, on propose de les **épingler par digest après revue documentée** : digests relevés, comparés entre `release.yaml` et le registre, et inscrits dans `resultats/`. C'est la voie que le doc 04 §5 prévoit « à défaut ». **Décision du propriétaire.**

### Pourquoi k3s v1.35.9 et non v1.37.1

| Version de k3s | Matrice documentée de Kyverno 1.19 | CI de Kyverno `release-1.19` | CI de Tekton v1.15 LTS | Fin de vie Kubernetes |
|---|---|---|---|---|
| **v1.35.9** (canal `v1.35`) | **Oui** (1.33 à 1.35) | Conformité : **oui** (1.35.1) ; sigstore : non (1.33 et 1.34 seulement) | Non (1.28 et 1.34 seulement) | 28/02/2027 (maintenance dès le 28/12/2026) |
| v1.36.5 (canal `stable`) | Non | Conformité : oui (1.36.1) ; sigstore : non | Non | 28/06/2027 |
| v1.37.1 (canal `latest`) | Non | **Non** | Non | 28/10/2027 |

Sources : `src/constants/version.ts` du site de Kyverno, `.github/workflows/tests-conformance.yaml` de Kyverno (branche `release-1.19`), `.github/e2e-matrix-full.json` de Tekton (branche `release-v1.15.x`), `data/releases/schedule.yaml` de kubernetes/website.

La v1.37 fonctionnera probablement. Mais le banc C mesure **Kyverno à l'admission** (C-2) sur ce cluster : hors de la plage testée par Kyverno, un écart serait ambigu (défaut de Kyverno ou version non supportée ?) et la mesure perdrait sa valeur. La v1.35 suffit pour la durée de la brique ; on montera de version avec Kyverno 1.20.

## Jalons

Chaque jalon se termine par un point de contrôle : mesures archivées, `docs/03` mis à jour et commit.

| # | Jalon | Contenu | Contrôle de fin |
|---|---|---|---|
| J1 | Infra | Pool, réseau, 3 VM (cloud-init), k3s (server + 2 agents, images système en airgap, sans Traefik ni ServiceLB), taint et labels de zone | `ld.so` en x86-64-v3 sans v4 dans les 3 VM ; `/dev/kvm` dans `sc-build` ; nœuds `Ready` ; RAM au repos |
| J2 | Stockage | Zot et Forgejo sur `sc-stockage` | Push/pull par digest ; dépôt `workspace/sample-app` |
| J3 | Clés | OpenBao (Transit, audit activé), clé de provenance non exportable ; authentification JWT liée au **seul** compte de service de Chains (`signers.kms.auth.oidc`, jeton du compte de service) | Signature Transit depuis Chains ; refus depuis un autre compte de service |
| J4 | Orchestration | Tekton Pipelines, Chains (`slsa/v2alpha4`, `dsse`, KMS `hashivault://`), Triggers et intercepteur HMAC Forgejo avec anti-rejeu | Premier PipelineRun de sample-app : provenance signée dans Zot, vérifiée par cosign |
| J5 | Horodatage | timestamp-authority (clé séparée), job TSA hors des pods de build, **choix du chemin de vérification** : bundle réémis (`tsaCertChain` de Kyverno) ou `tools/verify-ts` | Jeton valide accepté ; jeton absent ou falsifié refusé |
| J6 | Politique | Trusted Resources (bundles de tâches signés), Kyverno (admission), Conforma (porte), RBAC, posture des pipelines (tekton-lint) | Politiques du banc C chargées à l'admission |
| J7 | Isolation | Kata 4.3.1 sur `sc-build` (RuntimeClass), avec CPU des invités vérifié | Pod Kata en x86-64-v3 ; pod privilégié hors Kata refusé |
| J8 | Preuves | Les 8 tests négatifs ; fin du banc C | 8/8 refusés avec trace ; notes C mises à jour dans l'ADR 0000 |

## Les 8 tests négatifs (doc 01) et leur trace

| # | Tentative | Mécanisme attendu | Trace |
|---|---|---|---|
| 1 | Lire le jeton ou la clé OpenBao depuis une tâche de build | Clé non exportable dans Transit ; authentification réservée au compte de service de Chains ; OpenBao sur un nœud de confiance | Journal d'audit d'OpenBao (refus) ; journal de la tâche |
| 2 | TaskRun avec `taskSpec` inline | Kyverno à l'admission et Trusted Resources | Événement de refus de Kyverno |
| 3 | Modifier le `status` ou les résultats d'un TaskRun terminé | RBAC (aucun droit sur `taskruns/status`) ; Chains ne re-signe pas | Refus de l'API ; journal d'audit de k3s |
| 4 | Pod privilégié hors Kata, ou montage `hostPath` | Kyverno | Événement de refus de Kyverno |
| 5 | Webhook Forgejo non signé, ou webhook valide rejoué | Intercepteur HMAC et anti-rejeu | Journal de l'EventListener |
| 6 | Connexion sortante pendant l'étape de build | NetworkPolicy deny-all (contrôleur kube-router intégré à k3s) | **Paquets refusés journalisés en NFLOG, groupe 100** (règle de kube-router, limitée à 10 par minute), lus sur `sc-build` par `tcpdump -i nflog:100` ; journal de la tâche |
| 7 | Publier ou admettre un artefact non signé, y compris un artefact qui ne porte que des attestations signées | Type `https://sigstore.dev/cosign/sign/v1` exigé (banc C) | Refus de Kyverno et de Conforma |
| 8 | Attestation avec un jeton d'horodatage absent ou falsifié | Vérification TSA (chemin choisi en J5) | Refus de Kyverno ou de `tools/verify-ts`, puis de Conforma |

## Points à vérifier en cours de brique (non supposés)

- **Signature des webhooks de Forgejo** (en-tête et format du HMAC), puis **mécanisme d'anti-rejeu** : les intercepteurs livrés avec Triggers ne le fournissent peut-être pas, et un intercepteur maison (ClusterInterceptor) serait alors nécessaire.
- **Authentification de Chains auprès d'OpenBao** par le jeton du compte de service (méthode JWT d'OpenBao, avec la clé publique de l'émetteur de comptes de service de k3s).
- **`internalParameters`** (`hermetic`, `isolation`, `cpuModel`) inscrits **par la plateforme**, pas par le code de build (doc 02 §3).
- **Sujet non-image** (rpm via ORAS, `isBuildArtifact: true`) : déduit du code de Chains (doc 00), à tester.
- **Vérification d'un jeton RFC 3161 séparé par Kyverno** (non documentée) et support des bundles Sigstore par Conforma (doc 00).
- Visibilité des pods Kata pour la NetworkPolicy et pour la trace NFLOG (Kata imbriqué).

## Changements sur l'hôte à valider

| Changement | Détail |
|---|---|
| Téléchargements | Image cloud (≈ 600 Mo), sommes et signature ; k3s et ses images airgap ; puis, jalon par jalon, les manifestes et images listés plus haut. Tout va dans `~/.cache/supply-chain-poc/08/` |
| Pool libvirt | `supply-chain-poc`, `/var/lib/libvirt/supply-chain-poc` (sur `/`) |
| Réseau libvirt | NAT `supply-chain-poc`, `virbr-scpoc`, 192.168.161.0/24, sans démarrage automatique |
| VM | `sc-confiance`, `sc-build`, `sc-stockage` (12 vCPU, 24 Gi, 65 Go), sans démarrage automatique |
| Dans les VM | k3s, puis les composants des jalons J2 à J7. Kata (J7) est soumis à un accord séparé |

Démontage complet en fin de phase, comme au banc A2. Le cluster sert aussi aux étapes 4e (briques 01, 03 et 19, puis 2b-2) : on ne démonte qu'à la fin de 4e, sauf avis contraire.
