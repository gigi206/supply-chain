# Brique 08 : plan de confiance sur k3s

Seuil (README, brique 08) : Tekton + HMAC, Chains (stockage prouvé), OpenBao, job TSA (chemin de vérification choisi), Trusted Resources, Kyverno, Conforma, RBAC, nœuds dédiés, posture des pipelines ; **les 8 tests négatifs du doc 01 échouent comme attendu**, chacun avec une trace.

On termine aussi le banc C : contrôle 9 (horodatage RFC 3161), C-2 (parité entre CLI et admission), et bibliothèque Conforma `slsa3` / `trusted_task` sur une vraie provenance Chains.

**Effort estimé : 5,5 pw.** Une décision avec le propriétaire est déclenchée à 11 pw. Le temps passé est relevé jalon par jalon dans `resultats/chrono.tsv`, ouvert à l'accord.

**Statut (30/10/2026) : J1 à J6 faits, J7 en cours** (Kata installé depuis l'archive attestée, décision du propriétaire ; invité en x86-64-v3, seccomp absent dans l'invité ; BuildKit v0.34.1 vérifié et copié dans Zot, mais aucun `RUN` possible en `restricted`, ni sous runc ni sous Kata : exemption Pod Security de la RuntimeClass `kata` posée (accord du propriétaire), server k3s redémarré sans arrêter de conteneur ; BuildKit rootless impossible sous Kata même exempté (virtiofsd sans `--xattr` : capacités de fichier de `newuidmap` invisibles dans l'invité), BuildKit en root dans un pod Kata privilégié redonne `3a7ca1b1` sur sample-app (racine de BuildKit sur tmpfs) ; voie D mesurée (compilation dans le pod Kata sans privilège ni exemption, réseau coupé par `unshare -n`, binaire `e3749c68` identique, image assemblée sans exécution, reproductible mais de digest différent de `3a7ca1b1`) ; **voie A retenue par le propriétaire** ; **sample-app construite dans un PipelineRun depuis Forgejo : image `3a7ca1b1`, provenance signée vérifiée par cosign** (BuildKit en root dans un pod Kata privilégié, push par une tâche runc séparée avec le compte Zot `poc-images`, création par digest seulement ; commit, fermeture, `web/dist` et image de build dans `resolvedDependencies`) ; réseau des pods Kata mesuré : la NetworkPolicy s'applique, Kata ne ferme pas la fenêtre de démarrage, et **un pod Kata privilégié contourne la politique par usurpation d'adresse source, sans trace** (décision du propriétaire avant J8) ; **construction sans sortie réseau** (option 3, choix du propriétaire) : entrées préparées par une tâche runc, image de build en layout OCI, NetworkPolicy `construction-sans-sortie` sur les pods de `construire-image`, même image `3a7ca1b1` ; **cluster recréé sous Cilium 1.20.4** (option 1b, accord du propriétaire) et J1 à J7 rejoués : aucune fenêtre de démarrage, usurpation d'adresse refusée (`INVALID_SOURCE_IP`), refus tracés par Hubble ; 3 VM et k3s v1.35.9 ; Zot et Forgejo sur `sc-stockage`, CA du PoC ; OpenBao, clé Transit de Chains ; Tekton Pipelines, Chains et Triggers installés depuis Zot, chaîne de signature éprouvée, webhook Forgejo signé et anti-rejeu ; TSA avec sa propre clé Transit, job d'horodatage, chemins de vérification mesurés ; voir plus bas). La construction de sample-app dans un pod passe en J7, avec Kata (décision du propriétaire). Chemin de vérification de J5 retenu par le propriétaire : bundle réémis, vérifié par cosign. **J6 fait** (accord du 29/10/2026) : Kyverno à l'admission, C-2 mesuré ; Trusted Resources ; règles d'admission ; EventListener et secrets sortis de la zone build, RBAC réduit, test 5 rejoué sous politique ; horodatage automatique par réconciliation périodique ; rattrapage des webhooks perdus ; porte de release (Conforma et sa bibliothèque) dans un pod de la zone de confiance ; pods de build conformes à Pod Security `restricted`, `builds` en `enforce` ; Chains en buildType `slsa-tekton` et liste revue des tâches approuvées (décisions du propriétaire du 30/10/2026). **Rejeu complet de J1 à J6 depuis zéro réussi** (30/10/2026 : 1784 s, 276 contrôles OK), puis redémarrage des trois VM avec les contrôles de J6 ; posture des pipelines par tekton-lint 1.2.4, installé avec un verrou npm (accord du 30/10/2026).

## Décisions du propriétaire (29/10/2026)

- **k3s v1.35.9+k3s1**, dans la plage testée par Kyverno 1.19 (voir plus bas).
- **Debian 13 generic** (`20261026-2643`) pour les VM, plutôt qu'Ubuntu 24.04. Debian ne publie **aucune signature** pour ses images cloud : le SHA512 est vérifié contre `SHA512SUMS` et contre le manifeste JSON de l'image, deux documents de cloud.debian.org, puis épinglé dans les scripts. C'est une limite assumée.
- **Verrou de l'ADR 0001 levé** : la brique 08 ne dépend pas de l'administrateur du replay, qui doit être nommé avant la brique 10.
- **Feu vert pour J1 seulement** : chaque jalon suivant est soumis à accord.

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

Relevé du 29/10/2026. Versions de k3s et image des VM : décidées par le propriétaire (plus haut).

| Composant | Version | Où | Vérification disponible |
|---|---|---|---|
| Image des VM (non retenue) | Ubuntu 24.04 LTS, `release-20261017` | 3 VM | `SHA256SUMS` signé (`SHA256SUMS.gpg`) par la clé `D2EB 4462 6FDD C30B 513D 5BB7 1A5D 6C4C 7DB8 7C81` ; cette clé figure aussi dans `/usr/share/keyrings/ubuntu-cloudimage-keyring.gpg` sur l'hôte, ce qui fait un 2e canal |
| **Image des VM (retenue)** | **Debian 13 generic, `20261026-2643`** (noyau 6.12.113, cloud-init 25.1.4) | 3 VM | `SHA512SUMS` **sans signature** (ni `.sign` ni `.asc` dans le répertoire daté) ; SHA512 `5bd891c6…` identique dans `SHA512SUMS` et dans le manifeste JSON |
| k3s | **v1.35.9+k3s1** (recommandée) | 3 VM | **sha256 seulement** : `sha256sum-amd64.txt` ; ni `.sig`, ni `.pem`, ni bundle, ni attestation GitHub, ni attestation de release. Binaire `897acb21…`. Images système via `k3s-airgap-images-amd64.tar.zst`, sur la même somme |
| Tekton Pipelines | v1.15.5 (LTS, fin de vie 31/07/2027) | confiance | **Non vérifiable** (doc 04 §5) : `release.yaml` non signé ; images signées par une clé qui ne correspond pas à la clé documentée |
| Tekton Chains | v0.29.9, mode **`dsse`** (chains#2096 toujours ouverte au 29/10/2026) | confiance | Non vérifiable (doc 04 §5) |
| Tekton Triggers | v0.37.2 | confiance | Non vérifiable (même processus de release) |
| OpenBao | 2.7.2 | confiance | Image signée sans clé (GitHub OIDC), vérifiée en doc 04 |
| timestamp-authority | v2.2.0 | confiance | **Attestation de release GitHub vérifiée** (`gh release verify`, tag `1110890…`) et provenance SLSA v1 du workflow `release.yaml@refs/tags/v2.2.0` ; binaire `327980b4…`. J5 : **image `timestamp-server` vérifiée** (attestation GitHub du workflow `build_container.yml` au tag, commit `526e9de7…` du tag signé), index `77c615f0…`, revérifiée depuis sa copie dans Zot ; `timestamp-cli` `18ee91ff…` (attestation GitHub de release) |
| cosign (image du job d'horodatage) | v3.1.4-dev | confiance | **Signature sans clé vérifiée** : identité `keyless@projectsigstore.iam.gserviceaccount.com` (émetteur `https://accounts.google.com`), documentée par Sigstore ; elle ne lie pas l'image à un tag. Index `8af1a2cf…`, manifeste amd64 `c142f6bc…` (base busybox) |
| oras (image du job d'horodatage) | 1.3.6 | confiance | **GPG** : `oras_1.3.6_checksums.txt` signé par la clé de release `C6FC42F0…EF37` (fichier `KEYS` du dépôt, empreinte recoupée sur oras.land) ; archive `66fb0ad7…` (= `mise.lock`). L'image officielle d'oras n'est pas signée |
| Kyverno | v1.19.2 | confiance | **J6 : 5 images vérifiées** par identité exacte (`release.yaml@refs/tags/v1.19.2`, commit du tag `e63308f1…`, déclencheur `push`), signatures dans `ghcr.io/kyverno/signatures` ; même digest d'index sur `reg.kyverno.io` et `ghcr.io` ; copiées dans Zot avec leurs bundles et revérifiées. `install.yaml` **non signé** (absent de `checksums.txt`), mais identique au manifeste `config/install-latest-testing.yaml` du commit du tag (signature vérifiée par GitHub), à la version près ; empreinte `4f785937…` épinglée |
| tkn (CLI Tekton) | v0.46.2 | hôte (mise) | **sha256 seulement** : `checksums.txt` de la release, sans signature ni attestation GitHub ; empreinte identique dans `mise.lock`, `checksums.txt` et l'archive téléchargée (`f6d86bc7…`) ; installé avec l'accord du propriétaire (J6). Lié à pipeline v1.14.1 : il **ne signe correctement que des tâches v1beta1** (tektoncd/cli#2894) |
| Conforma `ec` | v0.10.42 (celle du banc C) | hôte (mise) ; **J6 : image de la porte** (zone confiance) | sha256 seulement (doc 04) : empreinte du verrou `mise.lock` (`895c6f7e…`), revérifiée à chaque assemblage de l'image de la porte |
| Bibliothèque de Conforma (`conforma/policy`) | v1.0.28 (26/08/2026) | image de la porte | **Tag annoté non signé** (créé par une GitHub Action), aucune archive de release ; le commit du tag `ebd3fbd2…` est signé par GitHub (fusion de PR), et son arbre `0fd26021…`, lu dans le contenu signé, est contrôlé après récupération par git. Verdict doc 04 : à surveiller (chemin critique) |
| Kata Containers | 4.3.1 (archive attestée, décision du propriétaire du 30/10/2026) | build | **Attestation de release GitHub vérifiée** (`gh release verify`, tag léger vers le commit signé `03cf2ec…`, release immuable) : `kata-deploy-4.3.1.tgz` `c2507741…`, `kata-static-4.3.1-amd64.tar.zst` `1463a2b8…`, revérifiés en J7 sur les fichiers téléchargés (`gh release verify-asset`) ; pas d'attestation de build de ces fichiers. **J7 : image `kata-deploy` non vérifiable** : ni signature, ni referrer, ni attestation ; les jobs qui la publient n'ont pas `id-token` |
| BuildKit (image `moby/buildkit:v0.34.1-rootless`) | v0.34.1 (20/10/2026 ; runc 1.5.2, rootlesskit 3.2.0) | build | **J7 : signature sigstore du manifeste d'attestation** (référent OCI 1.1), qui désigne le manifeste amd64 `ace6811c…` comme sujet ; l'image elle-même n'est pas signée. Vérifiée par cosign (workflow réutilisable `docker/github-builder` épinglé, appelé par `moby/buildkit` au tag signé `f5b59a1f…`, déclencheur `push`) et par `gh attestation verify` ; copiée dans Zot et revérifiée. La v0.25.2 de la brique 04 n'est pas signée |
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
| J4 | Orchestration | Tekton Pipelines, Chains (`slsa/v2alpha4`, `dsse`, KMS `hashivault://`), Triggers et intercepteur HMAC Forgejo avec anti-rejeu | Premier PipelineRun de sample-app : provenance signée dans Zot, vérifiée par cosign ; **contrôle modifié le 29/10/2026 (option C du propriétaire)** : chaîne de signature prouvée par un essai et PipelineRun déclenché par un webhook Forgejo signé, sans construction, qui passe en J7 |
| J5 | Horodatage | timestamp-authority (clé séparée), job TSA hors des pods de build, **choix du chemin de vérification** : bundle réémis (`tsaCertChain` de Kyverno) ou `tools/verify-ts` | Jeton valide accepté ; jeton absent ou falsifié refusé |
| J6 | Politique | Trusted Resources (bundles de tâches signés), Kyverno (admission), Conforma (porte), RBAC, posture des pipelines (tekton-lint) | Politiques du banc C chargées à l'admission |
| J7 | Isolation | Kata 4.3.1 sur `sc-build` (RuntimeClass), avec CPU des invités vérifié ; **construction de sample-app** (reportée de J4 le 29/10/2026 ; BuildKit en root dans un pod Kata privilégié, voie A retenue le 30/10/2026) | Pod Kata en x86-64-v3 ; pod privilégié hors Kata refusé ; PipelineRun de sample-app qui construit l'image depuis Forgejo, provenance signée vérifiée par cosign, digest comparé à `3a7ca1b1…` |
| J8 | Preuves | Les 8 tests négatifs ; fin du banc C | 8/8 refusés avec trace ; notes C mises à jour dans l'ADR 0000 |

## Les 8 tests négatifs (doc 01) et leur trace

| # | Tentative | Mécanisme attendu | Trace |
|---|---|---|---|
| 1 | Lire le jeton ou la clé OpenBao depuis une tâche de build | Clé non exportable dans Transit ; authentification réservée au compte de service de Chains ; OpenBao sur un nœud de confiance | Journal d'audit d'OpenBao (refus) ; journal de la tâche |
| 2 | TaskRun avec `taskSpec` inline | Kyverno à l'admission et Trusted Resources | Événement de refus de Kyverno |
| 3 | Modifier le `status` ou les résultats d'un TaskRun terminé | RBAC (aucun droit sur `taskruns/status`) ; Chains ne re-signe pas | Refus de l'API ; journal d'audit de k3s |
| 4 | Pod privilégié hors Kata, ou montage `hostPath` | Kyverno | Événement de refus de Kyverno |
| 5 | Webhook Forgejo non signé, ou webhook valide rejoué | Intercepteur HMAC et anti-rejeu | Journal de l'EventListener |
| 6 | Connexion sortante pendant l'étape de build | NetworkPolicy deny-all (contrôleur kube-router intégré à k3s). **Mesuré en J7** : fenêtre de démarrage ouverte sous Kata ; contournée sans trace depuis le root de l'invité par usurpation d'adresse source. Option 3 retenue par le propriétaire et faite : politique `construction-sans-sortie`, ni entrée ni sortie pour les pods de `construire-image`, dont les entrées sont préparées par une tâche runc. **Sous Cilium** (option 1b, mesuré) : aucune fenêtre, usurpation refusée (`INVALID_SOURCE_IP`), refus tracés par Hubble sans plafond. Choix du contrôleur réseau : décision du propriétaire | **Paquets refusés journalisés en NFLOG, groupe 100** (règle de kube-router, limitée à 10 par minute), lus sur `sc-build` par `tcpdump -i nflog:100` ; journal de la tâche |
| 7 | Publier ou admettre un artefact non signé, y compris un artefact qui ne porte que des attestations signées | Type `https://sigstore.dev/cosign/sign/v1` exigé (banc C) | Refus de Kyverno et de Conforma |
| 8 | Attestation avec un jeton d'horodatage absent ou falsifié | Bundle réémis dans un dépôt séparé, vérifié par cosign v3.1.4 dans la porte (`tools/verify-ts`), chemin retenu en J5 | Refus de `tools/verify-ts` (mesuré en J5 : absent, altéré, autre signature, TSA étrangère), puis de Conforma |

## Points à vérifier en cours de brique (non supposés)

- ~~**Signature des webhooks de Forgejo** et anti-rejeu~~ : **vérifié en J4**. Forgejo v15.0.11 envoie `X-Hub-Signature-256: sha256=<hmac>` (HMAC-SHA256 du corps), que l'intercepteur GitHub de Triggers v0.37.2 exige ; les en-têtes de livraison ne sont pas signés. Anti-rejeu sans intercepteur maison : le nom du PipelineRun dérive du commit signé (voir « Jalon J4 »).
- ~~**Authentification de Chains auprès d'OpenBao** par le jeton du compte de service (méthode JWT d'OpenBao, avec la clé publique de l'émetteur de comptes de service de k3s)~~ : **vérifié en J3** dans le code de Chains v0.29.9. `signers.kms.auth.oidc.path`, `.role` et `.token-path` suffisent, sans SPIRE, et le signataire KMS est recréé à chaque signature (voir « Jalon J3 »).
- **`internalParameters`** (`hermetic`, `isolation`, `cpuModel`) inscrits **par la plateforme**, pas par le code de build (doc 02 §3). Mesuré en J6 : Chains ne les y inscrit que depuis des labels ou annotations du PipelineRun ; choix du canal reporté à J7 par le propriétaire (J6, `internalParameters` en `slsa-tekton`). J7 : la provenance de la construction signe `runtimeClassName: kata` dans ses paramètres externes et dans le TaskRun en contenu (option (c)) ; canal à trancher.
- **Sujet non-image** (rpm via ORAS, `isBuildArtifact: true`) : déduit du code de Chains (doc 00), à tester.
- ~~**Vérification d'un jeton RFC 3161 séparé par Kyverno** (non documentée)~~ : **mesurée en J5**. Kyverno 1.19.2 ne lit l'horodatage que dans un bundle et plante sur un jeton valide avec un attestor à clé sans journal (voir « Jalon J5 »). Support des bundles Sigstore par Conforma (doc 00) : à mesurer en J8.
- ~~Visibilité des pods Kata pour la NetworkPolicy et pour la trace NFLOG (Kata imbriqué)~~ : **mesurée en J7**. La politique s'applique à un pod Kata et ses refus figurent dans NFLOG avec son IP, mais Kata ne ferme pas la fenêtre de démarrage, et un pod Kata privilégié contourne la politique par usurpation d'adresse, sans trace (voir « Réseau des pods Kata »). Sous Cilium (option 1b), plus de fenêtre, et l'usurpation est refusée (voir « Mesure de Cilium »).

## Changements sur l'hôte

J1 validé et fait le 29/10/2026 (téléchargements, pool, réseau, VM, k3s). Les jalons suivants restent soumis à accord.

| Changement | Détail |
|---|---|
| Téléchargements | Image Debian (439 Mo), `SHA512SUMS` et manifeste ; k3s et ses images airgap (272 Mo) ; puis, jalon par jalon, les manifestes et images listés plus haut. Tout va dans `~/.cache/supply-chain-poc/08/` ; depuis J5, les images amont copiées dans Zot y sont gardées en cache OCI (`telechargements/oci`) |
| Pool libvirt | `supply-chain-poc`, `/var/lib/libvirt/supply-chain-poc` (sur `/`) |
| Réseau libvirt | NAT `supply-chain-poc`, `virbr-scpoc`, 192.168.161.0/24, sans démarrage automatique |
| VM | `sc-confiance`, `sc-build`, `sc-stockage` (12 vCPU, 24 Gi, 65 Go), sans démarrage automatique |
| Dans les VM | k3s, puis les composants des jalons J2 à J7. Kata (J7) est soumis à un accord séparé. J2 : sur `sc-stockage`, **git et 9 dépendances par apt** (versions épinglées, accord du propriétaire du 29/10/2026), Zot et Forgejo en services systemd (comptes système `zot` et `forgejo`) ; sur les trois nœuds, `registries.yaml` et la CA du PoC dans `/etc/rancher/k3s` |
| Outils de l'hôte (`mise.toml`) | J2 : kubectl 1.35.10 à la place de 1.37.2 |
| Cache de l'hôte | J2 : `~/.cache/supply-chain-poc/08/pki` (certificats publics) ; dans `…/08/secrets` (0600) : clés de la CA et des services, mot de passe du compte d'écriture de Zot, mot de passe et jeton de l'administrateur de Forgejo |
| J4 | Dans le cluster : Tekton Pipelines, Triggers (espaces `tekton-pipelines`, `tekton-pipelines-resolvers`) et Chains (`tekton-chains`), espace `builds` ; dans Zot : manifestes linux/amd64 des 13 images Tekton et du busybox sous `amont/`, dépôt d'essai `builds/essai-signature` ; dans `…/08/secrets` : mot de passe du compte Zot `poc-build` ; `~/.cache/supply-chain-poc/08/telechargements/tekton` : release.yaml des deux sources |
| J5 | Dans le cluster : TSA (espace `tsa`), espace `horodatage` du job ; dans OpenBao : clé Transit `tsa`, politique `tsa-signature`, rôle JWT `tsa`, NetworkPolicy ouverte à l'espace `tsa` ; dans Zot : compte `poc-horodatage` (`horodatage/**` seulement), copies de `timestamp-server` (index et attestations) et de cosign v3.1.4-dev (amd64) sous `amont/sigstore/`, image d'outils `plateforme/outils-horodatage`, bundles dans `horodatage/bundles`, cas d'essai dans `essais-j5/*` ; dans `…/08/secrets` (0600) : clé de la racine TSA, mot de passe de `poc-horodatage` ; dans `…/08/pki` : racine, feuille et chaîne du TSA, racine de confiance de cosign ; `…/08/telechargements/tsa` : `timestamp-cli`, archive, sommes et signature d'oras, fichier `KEYS` et page de vérification d'oras.land |
| J6 | Dans le cluster : Kyverno (espace `kyverno`, 4 contrôleurs sur `sc-confiance`), politique `bench-release` du banc C, 4 politiques d'admission (`tekton-references`, `pods-isolation`, `zone-confiance`, `stepactions-interdites`), espace `bancc` (pods d'essai jamais créés : dry-run) ; Tekton : `trusted-resources-verification-no-match-policy: fail`, `disable-inline-spec`, résolveur `bundles` seul, VerificationPolicy `taches-plateforme` dans `builds`, CA du PoC pour le résolveur ; dans Zot : `compat: docker2s2` (manifestes Docker v2 des bundles de tkn), index des 5 images Kyverno et leurs bundles de signature sous `amont/kyverno/`, 17 cas du banc C sous `bench/`, bundles d'essai sous `tekton/tasks/` et `essais-j6/` ; sur l'hôte : tkn v0.46.2 (`mise.toml`), clé des tâches dans `…/08/secrets` (0600), clé publique dans `…/08/pki` ; `…/08/telechargements/kyverno` : `install.yaml`. Puis : règle d'admission `zone-build` ; espace `declencheurs` (Pod Security `restricted`) avec l'EventListener `forgejo`, son compte `el-forgejo`, ses rôles réduits et le secret `forgejo-webhook` ; objets de J4 retirés de `builds` (EventListener, gabarit, tâche et pipeline locales, compte, liaisons, secrets `forgejo-webhook` et `zot-build`) ; secret `zot-chains` dans `tekton-chains` et correctif `DOCKER_CONFIG` du Deployment de Chains (`kubectl patch`) ; compte `build` sans `imagePullSecrets` ni jeton monté ; rôle `operateur-builds` lié au groupe `operateurs` ; dans Zot : bundles `tekton/tasks/publier-essai`, `tekton/pipelines/sample-app-essai` et `tekton/pipelines/essai-modifiee` ; webhook Forgejo rebranché sur le NodePort de `declencheurs`. Puis : CronJob `horodatage` (espace `horodatage`) et trois témoins `builds/essai-j6-*` posés par `poc-ecriture` ; CronJob `rattrapage` dans `declencheurs`, avec son compte, ses rôles, sa NetworkPolicy, sa ConfigMap et l'image `plateforme/rattrapage` ; dans Forgejo, deux commits d'essai poussés sur `main`, puis `main` remise à `6391fd43`. Puis : espace `porte` (Pod Security `restricted`, ajouté à la règle `zone-confiance`) avec son compte, sa NetworkPolicy et sa ConfigMap ; dans Zot : image `plateforme/porte`, bundles `tekton/tasks/publier-hors-liste` et `tekton/pipelines/porte-*` (étiquettes `porte-<cas>`), images `builds/essai-porte` ; effets du prototype de la porte, lus par rien : étiquette `tekton/tasks/publier-essai:essai` déplacée vers une variante du prototype (l'étape `declencheurs` la repousse), étiquettes `:essai` de `tekton/tasks/publier-hors-liste` et `tekton/pipelines/porte-*`, image `plateforme/porte:proto` (même digest que `v1`) ; sur l'hôte : `…/08/telechargements/conforma-policy` (dépôt git nu, un commit). Puis : `set-security-context: "true"` dans `feature-flags` de Pipelines (`kubectl patch`) ; labels Pod Security `warn`, `audit` et `enforce` (`restricted`) sur `builds`, posés par l'étape et absents de `tekton/builds.yaml` ; Chains en buildType `slsa-tekton` (`tekton/chains/chains-config.yaml`, et `kubectl patch` sur le cluster en place) ; tâche en service et tâche d'essai republiées avec leur `stepTemplate` ; dans Zot : bundles `tekton/tasks/publier-sans-restriction` et `tekton/pipelines/sans-restriction` (étiquette `restreint`) ; enveloppe incohérente du constat d'adoption, dans le tag `.att` de `builds/essai-webhook` et horodatée dans `horodatage/bundles` (masquée pour la porte par des provenances plus récentes). Puis, sur l'hôte : tekton-lint 1.2.4 et ses 88 dépendances dans `…/08/outils/tekton-lint` (`npm ci --ignore-scripts` depuis le verrou versionné `politique/posture/package-lock.json`, hors du dépôt ; retrait : supprimer ce répertoire) ; dans `~/.npm`, partagé avec les autres usages de npm : 337 fichiers ajoutés au cache `_cacache` (existant), journaux dans `_logs`, et `_tuf` créé par `npm audit signatures` (métadonnées TUF de Sigstore) ; aucun cache dans `~/.tekton-lint` (`TL_CACHE_DIR` dans le répertoire de travail ; un essai initial sans lui l'avait créé, vide, retiré) |
| J7 | Sur l'hôte : `…/08/telechargements/kata` (archive `kata-static` 4.3.1, 1,02 Go ; chart `kata-deploy`, 141 Ko), extraction dans `…/08/travail/kata/charge` (394 Mo). Sur `sc-build` (accord du propriétaire du 30/10/2026, archive attestée) : `/opt/kata` (23 fichiers et 2 liens, root) et `/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d/kata.toml` ; `k3s-agent` redémarré. Dans le cluster : RuntimeClass `kata` ; règle `pods-isolation` restreinte à `kata`. Voie D : dans Zot, `plateforme/builder-go-voie-d` (étiquettes `a`, `b`) et `essais-j7/sample-app-voie-d` (`a`, `b`) ; sur l'hôte, `…/08/travail/voie-d` (957 Mo : deux arbres de l'image de build et leurs tars). BuildKit : manifeste amd64 et manifeste d'attestation (avec son bundle de signature) de `moby/buildkit:v0.34.1-rootless` dans Zot (`amont/moby/buildkit`), en cache OCI dans `…/08/telechargements/oci/amont/moby/buildkit` ; pods d'essai `j7-*` supprimés après chaque mesure. Sur `sc-confiance` (accord du propriétaire du 30/10/2026, exemption Pod Security de la RuntimeClass `kata`) : `/etc/rancher/k3s/pod-security.yaml` et `/etc/rancher/k3s/config.yaml.d/pod-security.yaml` (0600), server `k3s` redémarré ; retrait : supprimer ces deux fichiers et redémarrer `k3s`. Retrait de Kata : supprimer `/opt/kata` et le fichier d'appoint, redémarrer `k3s-agent`, supprimer la RuntimeClass. Construction (accord du propriétaire du 30/10/2026 pour Zot) : sur `sc-stockage`, compte Zot `poc-images` (`/etc/zot/config.json` avec une condition CEL, `/etc/zot/htpasswd`), Zot redémarré par `stockage.sh zot` ; dans `…/08/secrets` (0600) : mot de passe de `poc-images` ; dans `builds` : secret `zot-images`, ConfigMap `ca-poc`, PipelineRuns `j7-sample-app` et `j7-sample-app-sans-kata` (TaskRuns, pods terminés et PVC de 1 Gi, supprimés avec eux) ; dans Zot : `entrees/sample-app/fermeture` et `entrees/sample-app/web-dist` (étiquette `b03`), `builds/essai-images` et `builds/sample-app` (par digest, avec `.sig` et `.att`), bundles `tekton/tasks/construire-image`, `tekton/tasks/publier-image` et `tekton/pipelines/sample-app` (étiquette `j7`, plus les digests intermédiaires des premiers passages), bundles d'horodatage des nouvelles enveloppes ; pods d'essai `j7-cm-*` supprimés après la mesure ; NetworkPolicy `sonde-reseau-j7` et pods `j7-reseau-*` de `kata.sh reseau`, retirés en fin d'étape ; NetworkPolicy `construction-sans-sortie` dans `builds` (option 3, permanente) ; dans Zot, bundles `tekton/tasks/preparer-entrees`, nouvelle `construire-image`, étiquette `j7-ancienne` (témoin, ancienne tâche et ancienne pipeline) ; sur l'hôte, pour vérification seulement : layout OCI de l'image de build (`…/08/travail/buildkit/layout`, 73 Mo), archive `kube-router_2.11.2_linux_amd64.tar.gz` et `checksums.txt` (`…/08/travail/sante-reseau/release`, 40 Mo). Cilium (option 1b, accord du propriétaire du 30/10/2026) : cluster recréé de zéro (démontage et recréation des trois VM) ; sur l'hôte, `…/08/telechargements/cilium` (chart, archives OCI amd64 de `cilium` et `operator-generic`, HelmChart, 280 Mo) ; dans les VM, k3s sans flannel ni kube-router (`config.yaml.d/reseau.yaml` sur `sc-confiance`), archives dans les images airgap, HelmChart `cilium` dans les manifestes du server, Cilium (eBPF, `cilium_host`, `cilium_net`, CNI dans `/opt/cni/bin` et `/etc/cni/net.d`), DaemonSet privilégié dans `kube-system`, opérateur sur `sc-confiance`. Retrait : supprimer la NetworkPolicy `construction-sans-sortie` ; pour Cilium, rejouer avec `RESEAU=flannel` ; supprimer le secret et la ConfigMap, retirer `poc-images` de `stockage/zot.json` et rejouer `stockage.sh zot` |
| J3 | Dans le cluster : OpenBao (espace `openbao`, PVC de 1 Gi sur `sc-confiance`), espace et compte de service `tekton-chains` créés avant Chains ; dans Zot : copie de l'image OpenBao (`amont/openbao/openbao`, 6 plateformes et 4 bundles de signature) ; dans `…/08/secrets` (0600) : jeton root, clé de descellement (b64 et hex), clé TLS d'OpenBao |

Démontage complet en fin de phase, comme au banc A2. Le cluster sert aussi aux étapes 4e (briques 01, 03 et 19, puis 2b-2) : on ne démonte qu'à la fin de 4e, sauf avis contraire.

## Jalon J1 : infra et k3s (29/10/2026)

Rejeu : `mise run confiance:preparer`, puis `confiance:vm -- creer`, `confiance:k3s` et `confiance:controles -- j1`. Démontage : `mise run confiance:vm -- detruire`. Accès : `poc/bricks/08-trust-plane/ssh.sh <vm>`. Journaux : [`preparer.log`](resultats/preparer.log), [`k3s.log`](resultats/k3s.log), [`controles-j1.log`](resultats/controles-j1.log) ; temps : [`chrono.tsv`](resultats/chrono.tsv).

| Étape | Durée | Résultat |
|---|---|---|
| Téléchargements vérifiés | 28 s | Image Debian (439 Mo), k3s (78 Mo) et images système (194 Mo) ; toutes les empreintes concordent sur leurs deux sources |
| Pool, réseau, 3 VM | 25 s jusqu'à SSH, volumes compris (après correctif, voir plus bas) | cloud-init `done` sans erreur ; partition agrandie (15, 30 et 20 Go) ; **clés d'hôte SSH générées sur l'hôte** et injectées par la graine : `known_hosts` écrit d'avance, vérification stricte dès le premier contact |
| k3s (server puis 2 agents) | 38 s | 3 nœuds `Ready`, v1.35.9+k3s1, containerd 2.2.7 ; binaire et images système vérifiés par sha256 **dans chaque VM** ; unité systemd versionnée, sans `install.sh` ; **jeton du server confiné à `sc-confiance`**, agents joints par un jeton agent distinct au format sécurisé (voir plus bas) |

**Rejeu complet depuis zéro** (`detruire`, puis `creer` et `k3s`, téléchargements en cache) : **63 s**. Le démontage par `detruire` a été vérifié : ni VM, ni pool, ni réseau, ni répertoire ne restent.

**Contrôles** ([`controles.sh`](controles.sh)) :
- **x86-64-v3 supporté, x86-64-v4 non supporté, aucun drapeau AVX-512** dans les trois VM (`ld.so --help`) ;
- `vmx` sur les 6 vCPU de `sc-build`, absent de `sc-confiance` et `sc-stockage` ; **`/dev/kvm` présent et `kvm_intel` chargé dans `sc-build`** ;
- sortie par le NAT libvirt dans les trois VM (`deb.debian.org` répond 200) ;
- zones : labels `zone=confiance|build|stockage`, **taint `zone=build:NoSchedule`** sur `sc-build` ;
- contrôleur de NetworkPolicy de k3s (kube-router) actif : 33 règles `KUBE-ROUTER` ;
- journal d'audit de l'API activé (politique [`audit-policy.yaml`](k3s/audit-policy.yaml)), secrets chiffrés au repos (`secrets-encryption`) ;
- composants k3s (CoreDNS, local-path, metrics-server) placés sur `sc-confiance`, qui n'a pas de taint ; Traefik et ServiceLB désactivés ;
- RAM juste après l'installation : 2,5, 2,0 et 1,7 Go de RSS QEMU sur l'hôte (6,3 Go au total) ; 25 Gi restent disponibles sur l'hôte ;
- **RAM au repos** (6 min après l'installation, [`controles-j1-repos.log`](resultats/controles-j1-repos.log)) : RSS QEMU de 2,5 Go (`sc-confiance`), 1,8 Go (`sc-build`) et 1,6 Go (`sc-stockage`), soit **6,0 Go** au total ; mémoire vue par k3s : 593, 250 et 234 Mi ; 25,0 Gi (25 647 Mi) restent disponibles sur l'hôte (corrigé : 25,6 Gi avait été écrit par erreur de conversion).

**Constat : sans carte vidéo, l'image Debian 13 ne démarre pas.** GRUB affiche « Booting `Debian GNU/Linux' » puis la VM redémarre aussitôt, environ trois fois par seconde, sans aucun message du noyau. Diagnostic, chaque fois avec un seul changement :
- CPU `host-model` au lieu de Haswell-v4 : même boucle ;
- image d'origine lancée avec QEMU (q35, Haswell-v4) : démarre, y compris avec 6 Go de RAM ou avec un CD-ROM SATA ;
- volume du pool comparé à une copie qui démarre (`qemu-img compare`) : identique ;
- même copie avec **`-vga none`** : boucle reproduite.

Correctif : une carte VGA sans affichage (ni VNC ni SPICE) dans les trois définitions libvirt. L'appliance OBS du banc A2 démarrait sans carte vidéo ; le défaut est donc propre au GRUB de cette image Debian. Temps perdu : environ 10 minutes.

**Jetons de k3s** ([doc k3s, « Tokens »](https://docs.k3s.io/cli/token)). La première version de `k3s.sh` donnait aux agents **le jeton du server au format court**. Or le jeton du server permet de joindre un nouveau server, ce qui donne « essentially full administrator access », et au format court l'agent fait confiance sans vérification à la CA présentée. C'était inacceptable pour `sc-build`, la zone hostile du modèle de menace. Correctif :
- `sc-confiance` reçoit deux jetons aléatoires distincts : `token-file` et `agent-token-file` ;
- les agents ne reçoivent que le jeton agent **au format sécurisé**, `K10<sha256 de la CA du server>::…`. `k3s.sh` vérifie que cette empreinte est celle de `server-ca.crt` et que le jeton agent ne contient pas le jeton du server ;
- l'agent vérifie la CA avant de s'authentifier, sans confiance au premier contact, comme pour SSH.

**Erreur de vérification corrigée.** Pour m'assurer que le jeton du server n'était pas sur les agents, je l'ai passé en argument de `sudo grep` : sudo journalise ses lignes de commande, et le jeton s'est retrouvé dans le journal des deux agents (une entrée chacun). Le cluster étant neuf, tout a été recréé avec une nouvelle CA et des jetons neufs ; aucune entrée de ce type ne subsiste. **Règle pour la suite : aucun secret en argument de commande** (sudo, ssh, kubectl), seulement des fichiers 0600 ou l'entrée standard.

**kubectl (point fermé en J2).** Le kubectl de `mise.toml` (1.37.2) sortait de la tolérance de version de Kubernetes face à un serveur 1.35 (une version mineure d'écart au plus) : les commandes de J1 passaient par `k3s kubectl` dans `sc-confiance`. Depuis J2, `mise.toml` épingle **kubectl 1.35.10**, vérifié comme les autres outils (sha256 contre `mise.lock` et contre la source amont, signature sigstore de `krel-staging@k8s-releng-prod.iam.gserviceaccount.com` : [`outils.txt`](../../infra/resultats/outils.txt)).

## J2 : stockage (choix validés par le propriétaire le 29/10/2026)

Vérifications du 29/10/2026 :
- **images Forgejo** (`codeberg.org/forgejo/forgejo:15.0.11-rootless`, index `3cd6bc2b…`) : aucune signature cosign (pas de tag `.sig` ni `.att`), seulement un manifeste d'attestation BuildKit **non signé** dans l'index ;
- **Zot** : ni l'image ni les binaires ne sont signés (doc 04) ;
- les **binaires** Forgejo 15.0.11 (GPG, clé principale comparée à forgejo.org) et Zot 2.1.22 (sha256 contre le fichier de sommes amont) sont déjà déclarés dans `mise.toml` et vérifiés par `poc/infra/verifier-outils.sh` depuis 4b.

Retenu et fait (voir « Jalon J2 » plus bas) :
1. **Forgejo et Zot en services systemd sur `sc-stockage`**, à partir de ces binaires vérifiés, plutôt qu'en pods sur des images non signées. Ils restent dans la zone stockage ; le cluster les joint par 192.168.161.13.
2. **TLS** par une petite CA du PoC (clé en 0600 dans `~/.cache/supply-chain-poc/08/secrets`), qui délivre les certificats de Zot et de Forgejo. La CA est déclarée à containerd (`registries.yaml` de k3s) et, plus tard, à Chains.
3. **kubectl 1.35** dans `mise.toml` à la place du 1.37.2 (le banc A1 est démonté), vérifié comme les autres outils (signature sigstore).

## Jalon J2 : stockage (29/10/2026)

Rejeu (après J1) : `mise run confiance:stockage -- pki zot registre containerd forgejo depot`. Journaux : `resultats/stockage-<étape>.log`, régénérés par le dernier rejeu complet (J1 à J3, mêmes résultats ; pull dans le pod en 310 ms) ; les durées et chiffres du tableau ci-dessous viennent du rejeu de J2 ([pki](resultats/stockage-pki.log), [zot](resultats/stockage-zot.log), [registre](resultats/stockage-registre.log), [containerd](resultats/stockage-containerd.log), [forgejo](resultats/stockage-forgejo.log), [depot](resultats/stockage-depot.log)) ; configuration dans [`stockage/`](stockage/).

**Rejeu complet de J1 et J2 depuis zéro** (`detruire`, `creer`, `k3s`, puis les six étapes ; téléchargements et CA en cache) : **109 s**, dont 1 s de démontage, 23 s de VM, 39 s de k3s et **46 s pour J2** ([`rejeu-j1-j2.log`](resultats/rejeu-j1-j2.log), horodatages epoch ; durées par étape dans `chrono.tsv`). Il a fallu trois rejeux : les deux premiers ont révélé les défauts décrits dans les constats, et leurs journaux n'ont pas été archivés (écrasés par le rejeu suivant).

| Étape | Durée | Résultat |
|---|---|---|
| `pki` | < 1 s | CA ECDSA P-256, 365 jours, `pathlen:0`, **contraintes de nom** : `poc.test`, `svc.cluster.local` (services du cluster, pour J3 à J5), 192.168.161.0/24 et 10.43.0.0/16 ([`pki.cnf`](stockage/pki.cnf)). Empreinte sha256 `D6:8A:15:A3:…:37:72:0A`. Un certificat et une clé par service (Zot, Forgejo), 180 jours, SAN `sc-stockage.poc.test` et 192.168.161.13. **Un certificat pour `registre.exemple.org` signé par la CA est refusé** à la vérification (« permitted subtree violation ») |
| `zot` | 5 s | Binaire de `mise.toml` **revérifié dans la VM** (sha256 de `mise.lock`) ; compte système `zot` ; unité durcie (`systemd-analyze security` : 3.0, « OK ») ; TLS sur 192.168.161.13:5000 ; **lecture anonyme, écriture par le seul compte `poc-ecriture`** (htpasswd bcrypt, coût 12, calculé par `mkpasswd` sur l'entrée standard), **sans droit de suppression** ; ramasse-miettes désactivé (`gc: false`, comme la brique 03) : un manifeste poussé par digest, sans tag, ne doit pas disparaître ; journal d'audit des écritures |
| `registre` | 8 s | **Push par digest** de l'image sample-app `3a7ca1b1` de la brique 04 depuis l'hôte, relecture anonyme du manifeste, **pull anonyme par digest aux blobs identiques**. Refus : ouverture d'un envoi sans identifiants (HTTP 401), push anonyme, push avec un mauvais mot de passe (401), **suppression par `poc-ecriture` (403)**, lecture sans la CA du PoC (x509). Les refus 401 et 403 figurent dans le journal de Zot, `Authorization` masqué |
| `containerd` | 18 s | **Pull refusé sur `sc-build` sans la CA** (x509). Puis CA et [`registries.yaml`](stockage/registries.yaml) sur les trois nœuds, sans identifiant, redémarrés un par un (`Ready` vérifié entre chaque) ; `hosts.toml` régénéré par k3s. **Pull par digest dans un pod de `sc-build`** (toleration du taint de zone) : `imageID` = `sc-stockage.poc.test:5000/workspace/sample-app@sha256:3a7ca1b1…`, 362 ms. `sc-stockage.poc.test` résolu **depuis un pod** (CoreDNS, puis dnsmasq du réseau libvirt) |
| `forgejo` | 11 s | **git 2.47.3 et 9 dépendances par apt** (versions épinglées, dépôts Debian signés ; accord du propriétaire du 29/10/2026). Binaire Forgejo de `mise.toml` (GPG vérifié sur l'hôte) **revérifié dans la VM** ; compte système `forgejo` ; unité durcie (3.0, « OK ») ; HTTPS sur 192.168.161.13:3000, sqlite, ni SSH, ni inscription (« Registration is disabled »), ni Actions, ni paquets, ni OAuth2 ; webhooks limités à 192.168.161.0/24. **`app.ini` sans secret** ([`forgejo.ini`](stockage/forgejo.ini)) : les trois secrets sont générés dans la VM et lus par `*_URI = file:` ; Forgejo ne modifie pas `app.ini` (sha256 identique au fichier versionné). Administrateur `poc-admin` créé avec `--random-password`, mot de passe capté dans un fichier 0600 de l'hôte sans affichage ; jeton limité à `write:organization` et `write:repository` |
| `depot` | 4 s | Organisation `workspace`, dépôt public **`workspace/sample-app`** : sources de `poc/sample-app` à HEAD, commit à auteur et date fixes, **`6391fd43…` à chaque rejeu** ; arbre `30e808ff…` = `poc/sample-app` à HEAD. Création d'organisation sans jeton : 401 ; **push sans jeton : 401** (journal de Forgejo). Lecture anonyme depuis l'hôte, et **depuis `sc-build`** par le nom DNS et la CA déclarée aux nœuds : même commit |

**RAM au repos après J2** (6 min après le rejeu, [`controles-j2-repos.log`](resultats/controles-j2-repos.log)) : RSS QEMU de 2,4 Go (`sc-confiance`), 1,9 Go (`sc-build`) et **2,7 Go (`sc-stockage`, contre 1,6 Go en J1)**, soit **7,0 Go** au total (6,0 Go en J1). Dans `sc-stockage`, 669 Mi sont utilisés et 1,6 Gi servent de cache de pages (paquets apt, image poussée, dépôt git) : le RSS QEMU compte ce cache une fois qu'il a été touché. Mémoire vue par k3s : 547, 250 et 388 Mi ; 24,1 Gi (24 645 Mi) restent disponibles sur l'hôte (corrigé : 24,6 Gi avait été écrit par erreur de conversion). Les autres contrôles de J1 restent valables : x86-64-v3 sans v4, aucun AVX-512, `vmx` sur les 6 vCPU de `sc-build`, sortie NAT, 33 règles `KUBE-ROUTER`.

**Aucun secret dans les journaux ni en argument de commande** : mots de passe et jetons passent par des fichiers 0600 ou l'entrée standard (`mkpasswd -s`, `curl -H @fichier`, `GIT_CONFIG_VALUE_0` pour l'en-tête de git). Contrôles :
- `resultats/` ne contient aucun mot de passe, jeton ni hash ;
- **dans les trois VM** ([`fuites.sh`](fuites.sh), [`fuites-j2.log`](resultats/fuites-j2.log)) : journal systemd complet (sudo compris), `/var/log/**/*.log` et journal d'audit de l'API, rapatriés sur l'hôte puis cherchés avec chacun des 9 secrets de `…/08/secrets` comme motif (`grep -F -f`, corps base64 pour les clés PEM) : **0 occurrence partout**. Un témoin aléatoire écrit par `logger` dans chaque VM est bien retrouvé, ce qui montre que le contrôle voit ces journaux. C'est le contrôle qui aurait détecté la fuite de J1 ; il sera rejoué à chaque jalon ;
- les copies de secrets de travail (`…/08/travail`) sont supprimées en fin d'exécution, y compris en cas d'échec (`trap`).

**Constats.**
- **`zot verify` ne vérifie presque rien** : il accepte une action inconnue (`"supprimer"`) et des chemins inexistants. La configuration de Zot n'est donc validée que par les essais de comportement de l'étape `registre`.
- **Course SIGPIPE dans `k3s.sh` (J1)**, révélée par le premier rejeu de J2 : la dernière commande distante, `k3s --version | head -1`, sortait en 141 sous `pipefail` quand `head` se fermait avant que k3s écrive sa deuxième ligne. Corrigé (`sed -n 1p`). Les `grep -q` en fin de pipeline des scripts de la brique ont été remplacés par des lectures complètes : une fermeture précoce aurait pu faire échouer la commande en amont (`curl` sur une page HTML, par exemple).
- **Forgejo enregistre la branche de façon asynchrone** : juste après le premier push dans un dépôt neuf, l'API `branches/main` répond 404 pendant 2 à 3 s. L'étape `depot` attend, avec une borne de 30 s.
- `/etc/rancher/k3s` est en 0700 : lire la CA sur un nœud demande `sudo`.
- Les certificats de Zot et de Forgejo ont le même SAN (`sc-stockage.poc.test`, 192.168.161.13) : les clés sont séparées par usage, mais chaque clé peut présenter un certificat valable pour l'autre service sur le même nom. C'est acceptable tant que les deux services partagent la VM ; un nom par service (`zot.poc.test`, `forgejo.poc.test`) lèverait cette ambiguïté.
- `hosts.toml` déclare la capacité `push` pour Zot (valeur par défaut de containerd) ; elle est sans effet, puisque les nœuds n'ont aucun identifiant d'écriture.

**Décision à prendre avant J4** (inchangée) : épinglage par digest, après revue, des images non vérifiables (Tekton Pipelines, Chains, Triggers).

## Jalon J3 : OpenBao (29/10/2026)

Rejeu (après J2) : `mise run confiance:openbao -- image deployer initialiser configurer essais redemarrage` ; après un redémarrage du pod ou des VM : `-- deverrouiller` (redémarrage complet des VM avec contrôles : `mise run confiance:redemarrer`). **Rejeu complet de J1 à J3** : `mise run confiance:rejeu`. Journaux : `resultats/openbao-<étape>.log` ([image](resultats/openbao-image.log), [deployer](resultats/openbao-deployer.log), [initialiser](resultats/openbao-initialiser.log), [configurer](resultats/openbao-configurer.log), [essais](resultats/openbao-essais.log)) ; configuration dans [`openbao/`](openbao/) ; fonctions communes aux jalons dans [`commun.sh`](commun.sh).

**Vérification préalable : comment Chains s'authentifie.** Le protocole prévoyait l'authentification JWT par le jeton du compte de service, sans l'avoir vérifiée. Le code de Chains v0.29.9 (tag `89219ea5`, `pkg/chains/signing/kms/kms.go`) le confirme :
- `signers.kms.auth.oidc.path`, `.role` et `.token-path` suffisent, **sans SPIRE**. Sans `token-path`, Chains lit le jeton du compte de service monté dans le pod ;
- `allSigners()` recrée le signataire KMS **à chaque `Sign()`** : le jeton est relu et la connexion JWT refaite pour chaque objet signé. La rotation des jetons projetés ne pose donc pas de problème, et chaque signature consomme un jeton batch ;
- le client hashivault de sigstore v1.10.9 n'utilise que `auth/<chemin>/login`, `transit/keys/<clé>` (lecture de la clé publique) et `transit/sign/<clé>/<hash>` avec `prehashed`. La politique se limite à ces chemins.

**Rejeu complet depuis zéro** ([`rejeu-j1-j3.log`](resultats/rejeu-j1-j3.log)) : **233 s**, dont 21 s de VM, 39 s de k3s, 46 s pour J2 et **124 s pour J3** (redémarrage du pod compris) ; puis contrôle des fuites. Un premier rejeu, sans l'étape `redemarrage`, avait pris 219 s.

| Étape | Durée | Résultat |
|---|---|---|
| `image` | 41 s | Index `ghcr.io/openbao/openbao@sha256:5046911…` (tag 2.7.2, 6 plateformes ; linux/amd64 `a78eb12a…`). **Signature sans clé vérifiée par identité exacte** : `release-images.yml@refs/tags/v2.7.2`, commit `9e0a0d3c` (celui du tag), déclencheur `release`, présence dans Rekor. **Une identité voisine (tag v2.7.1) est refusée.** Copie dans Zot avec ses referrers (`oras cp -r` : 4 bundles sigstore), puis **signature revérifiée sur la copie de Zot** ; les pods tirent l'image de Zot par digest |
| `deployer` | 7 s | StatefulSet d'un réplica sur `sc-confiance`. Pod non root (uid 100), sans capability, racine en lecture seule, Pod Security « restricted », **aucun jeton Kubernetes monté**. Raft sur un PVC local-path. TLS 1.3 avec un certificat de la CA du PoC pour `openbao.openbao.svc.cluster.local` : la forme courte `openbao.openbao.svc` sortirait des contraintes de nom de la CA. Sonde de disponibilité `bao status`, sans sonde de vie : un OpenBao scellé n'est pas redémarré en boucle. **NetworkPolicy** : entrée sur 8200 depuis l'espace `tekton-chains` seulement, aucune sortie. `bao version` affiche le commit du tag |
| `initialiser` | 12 s | État lu dans OpenBao (`sys/init`, `sys/seal-status`), pas dans les fichiers de l'hôte. Une part de descellement ; jeton root et clé de descellement en 0600 sur l'hôte, un secret par fichier, jamais affichés. Descellement par l'entrée standard de `kubectl exec` (`sys/unseal key=-`). **Audit `fichier/` actif dès le descellement**, vérifié avant toute configuration (déclaré dans [`config.hcl`](openbao/config.hcl)) |
| `configurer` | 2 s | **Transit : clé `chains` ecdsa-p256, `exportable=false`, `allow_plaintext_backup=false`, `deletion_allowed=false`.** Politique [`chains-signature`](openbao/chains-signature.hcl) (3 chemins). Méthode JWT : clé publique tirée de `service.key` de k3s, **`kid` recalculé égal à celui du JWKS** (une seule clé), émetteur `https://kubernetes.default.svc.cluster.local`. Rôle `tekton-chains` : audience `openbao`, sujet `system:serviceaccount:tekton-chains:tekton-chains-controller`, jetons batch de 5 min, **sans politique par défaut** |
| `essais` | 45 s | Voir ci-dessous |
| `redemarrage` | 16 s | Voir « Redémarrages » |

**Essais** ([`openbao-essais.log`](resultats/openbao-essais.log)). Les pods utilisent l'image OpenBao vérifiée comme client `bao`. Le jeton du compte de service est projeté avec l'audience `openbao`, comme il le sera pour Chains en J4.
- **Signature par le compte de service de Chains**, depuis un pod de `sc-confiance` : connexion JWT acceptée (politique `chains-signature` seule, jeton batch de 300 s). Signature Transit `sha2-256` avec `prehashed`, comme le client hashivault de Chains, **vérifiée sur l'hôte par openssl** avec la clé publique lue dans Transit (P-256). La même signature est refusée sur un message modifié.
- **Refus pour le jeton de Chains (403, `permission denied`)** : export de la clé, **clé rendue exportable**, sauvegarde en clair, création d'une autre clé, liste des moteurs, lecture de son propre jeton.
- **Autres identités refusées (400)** : autre compte de service du même espace (« invalid subject (sub) claim ») ; compte de service de Chains muni de son jeton par défaut, d'audience API (« invalid audience (aud) claim »).
- **Réseau** : un pod de `sc-build` ne joint pas OpenBao (15 essais sur 15 s, `connection refused`). kube-router **journalise les SYN refusés en NFLOG** (groupe 100), et `tcpdump -i nflog:100` les lit sur `sc-confiance` : c'est la trace prévue pour le test 6.
- **Jeton root** : l'export (« private key material is not exportable ») et la sauvegarde en clair (« exporting is disallowed on the policy ») sont refusés.
- **Audit d'OpenBao** : chaque connexion, signature et refus y figure, avec le compte (`jwt-system:serviceaccount:…`) et la politique. Les valeurs sensibles (JWT, messages d'erreur de `response.data`) y sont en HMAC.

**Redémarrages.**
- **Pod** (étape `redemarrage`, dans le rejeu complet, [`openbao-redemarrage.log`](resultats/openbao-redemarrage.log)). Avant, un message témoin est signé par la clé `chains`, et on relève l'empreinte de la clé publique complète. Après la suppression du pod, OpenBao revient **scellé, non prêt et retiré du Service** (0 endpoint prêt). Une fois descellé, il présente la **même clé publique** (version 1, non exportable), et **la signature témoin d'avant se vérifie avec la clé relue après** : la clé privée est bien conservée par raft sur le PVC.
- **Trois VM** (`mise run confiance:redemarrer`, [`redemarrage-vm.log`](resultats/redemarrage-vm.log)), comme après un redémarrage du laptop. Arrêt propre en 4 s, démarrage jusqu'à SSH en 9 s, trois nœuds réenregistrés (nouveau `bootID`) en 14 s (journal réécrit en J5, avec le TSA : 6, 9 et 14 s ; puis en J6, avec Kyverno, Tekton et les CronJobs : 13, 8 et 15 s). Zot et Forgejo repartent seuls (unités `enable`) et restent lisibles (manifeste sample-app par digest, branche `main`). OpenBao revient scellé ; `deverrouiller` le descelle, et le témoin se vérifie avec la même clé. Constat : juste après le démarrage, l'API garde l'état d'avant (nœuds `Ready`, pods prêts) tant que les kubelets ne se sont pas réenregistrés. Le script attend donc un nouveau `bootID` ; un premier essai, qui ne l'attendait pas, avait lu cet état périmé.

**RAM au repos après J3** (6 min après le rejeu, [`controles-j3-repos.log`](resultats/controles-j3-repos.log)) : RSS QEMU de 2,7 Go (`sc-confiance`, OpenBao compris), 2,1 Go (`sc-build`) et 3,1 Go (`sc-stockage`), soit **7,8 Go** au total (7,0 Go après J2, 6,0 Go après J1). Mémoire vue par k3s : 663, 255 et 393 Mi ; 23,2 Gi (23 779 Mi) restent disponibles sur l'hôte. Dans `sc-stockage`, 2,0 Gi sont du cache de pages (la copie multi-plateforme de l'image OpenBao s'y ajoute).

**Contrôle des fuites** ([`fuites-j1-j3.log`](resultats/fuites-j1-j3.log)) : 13 secrets, **0 occurrence** dans les journaux des trois VM, journaux des pods et **journal d'audit d'OpenBao** compris (lu sur le volume local-path) ; témoins retrouvés.

**Limites et constats.**
- **J3 prouve l'identité, la politique et la clé, pas encore le chemin de Chains lui-même.** Il est validé en J4 (voir « Jalon J4 ») : `signers.kms.kmsref: hashivault://chains`, `signers.kms.auth.address`, `oidc.path: jwt`, `oidc.role: tekton-chains`, `oidc.token-path` vers un jeton projeté d'audience `openbao`, CA du PoC (`VAULT_CACERT`), contrôleur sur `sc-confiance`.
- **`exportable=true` est irréversible et reste à la portée de l'administrateur** : quiconque détient le jeton root, ou la clé de descellement (qui permet d'en régénérer un), peut rendre la clé exportable. La garantie vaut contre tout le monde, sauf l'administrateur. Les essais ne demandent jamais cette modification avec le jeton root. Le jeton root reste sur l'hôte. Durcissement possible : le révoquer après la configuration et le régénérer au besoin (`operator generate-root`).
- **`bound_subject` seul** : tout pod qui tourne sous le compte de service de Chains, et quiconque peut créer `serviceaccounts/token` pour lui, obtient des signatures. La NetworkPolicy admet de même tout pod de l'espace `tekton-chains`. **À traiter en J6** : RBAC sur la création de pods, `exec`, `portforward` et `serviceaccounts/token` dans `tekton-chains` et `openbao` ; règle Kyverno qui garde les pods de `tekton-chains` en zone confiance. C'est le mécanisme du test 1.
- **La NetworkPolicy ne protège pas d'un accès depuis le nœud** : la chaîne de kube-router du pod `openbao-0` accepte, avant la politique, tout trafic dont la source est le nœud local (`--src-type LOCAL -j ACCEPT`). Un pod en `hostNetwork` placé sur `sc-confiance`, ou tout processus de ce nœud, joint donc OpenBao, quel que soit son espace de noms. Il lui faut encore un jeton accepté par le rôle JWT, mais la barrière réseau ne joue pas. **À traiter en J6** : la règle Kyverno du test 4 interdit aussi `hostNetwork` (et `hostPID`, `hostIPC`) hors des espaces système.
- **kube-router applique la NetworkPolicy à un pod neuf avec un délai** : sa première connexion est rejetée (REJECT, donc `connection refused`, pas un délai dépassé) pendant environ 1 s, le temps que kube-router ajoute son IP. Les scripts d'essai attendent. Pour Chains : **non observé en J4**, car le contrôleur, démarré bien avant ses premières signatures, n'a pas subi ce refus ; la reprise d'une signature refusée n'est pas testée.
- tcpdump ne sait pas filtrer l'interface NFLOG (« link-layer type filtering not implemented ») : on filtre après la capture.
- Le volume local-path est en 0777 sur le nœud ; les données d'OpenBao y sont chiffrées par la barrière, et `audit.log` est en 0600.

## Jalon J4 : Tekton, Chains, Triggers (29/10/2026)

**Décisions du propriétaire (29/10/2026)** :
- les `release.yaml` et les images de Tekton Pipelines, Chains et Triggers, non vérifiables (doc 04 §5), sont **épinglés par digest après revue**. La reconstruction depuis les tags relève de la brique 11 ;
- **option C pour la construction de sample-app** : J4 se clôt avec la chaîne de signature prouvée par un essai, Triggers et le webhook Forgejo ; la vraie construction passe en **J7**, avec BuildKit rootless dans un pod Kata sur `sc-build`, sans relâcher seccomp ni AppArmor, en visant le digest `3a7ca1b1…` de la brique 04. Les options écartées : BuildKit en pod dès J4 (seccomp et AppArmor relâchés jusqu'à J7), ou une construction sans démon avec un outillage maison.

Rejeu : `mise run confiance:tekton -- revue miroir installer signature verifier webhook essais_webhook`.

**Rejeu complet de J1 à J4 depuis zéro** (`mise run confiance:rejeu`, [`rejeu-j1-j4.log`](resultats/rejeu-j1-j4.log)) : **479 s**, dont 24 s de VM, 40 s de k3s, 81 s pour J2, 126 s pour J3 et **205 s pour J4** (durées par étape ci-dessous) ; 74 contrôles OK, aucun secret dans les journaux des trois VM ([`fuites-j1-j4.log`](resultats/fuites-j1-j4.log)). Il a fallu quatre rejeux : les trois premiers ont révélé l'ordre d'installation de Triggers, l'attestation écrasée et une course sur le compte de service `default` d'un espace neuf (voir les constats). Journaux : `resultats/tekton-<étape>.log` ([revue](resultats/tekton-revue.log), [miroir](resultats/tekton-miroir.log), [installer](resultats/tekton-installer.log), [signature](resultats/tekton-signature.log), [verifier](resultats/tekton-verifier.log)) ; images : [`tekton-images.tsv`](resultats/tekton-images.tsv) ; correctifs dans [`tekton/`](tekton/).

| Étape | Durée | Résultat |
|---|---|---|
| `revue` | 18 s | **Les quatre `release.yaml`** (Pipelines v1.15.5, Chains v0.29.9, Triggers v0.37.2 et ses intercepteurs) sont **identiques sur GitHub et sur infra.tekton.dev**, et égaux aux digests des assets publiés par GitHub ; leurs sha256 sont épinglés dans [`tekton.sh`](tekton.sh). **Les 13 images Tekton** y sont déjà référencées par tag et digest : chaque digest est **celui du tag dans le registre**, et le manifeste linux/amd64 est listé dans l'index épinglé. Deux images tierces : l'image shell `cgr.dev/chainguard/busybox` (signée, mais par une identité `distroless/busybox` que seule la lecture du certificat révèle) est **remplacée par le busybox 1.37.0 des images airgap de k3s** (digest d'index `101b4afd…` identique sur le nœud et sur docker.io) ; `powershell:nanoserver` ne sert qu'aux nœuds Windows. Revue des droits et des webhooks : voir plus bas |
| `miroir` | 64 s | 14 manifestes linux/amd64 copiés dans Zot sous `amont/` et relus par digest. On ne copie pas les index complets : `entrypoint` et `nop` contiennent des couches Windows |
| `installer` | 34 s | Manifestes **réécrits vers Zot**, puis contrôleurs, webhooks et résolveurs **placés sur `sc-confiance`** (kustomize). Il ne reste dans les manifestes rendus aucune référence d'image externe, hormis `powershell` et un texte de documentation d'une CRD. **Les 8 images réellement tirées viennent toutes de `sc-stockage.poc.test:5000/amont/`** (`imageID` des conteneurs). Chains : `slsa/v2alpha4`, signataire KMS `hashivault://chains`, `oidc.token-path` vers un jeton projeté d'audience `openbao`, `VAULT_CACERT` et `SSL_CERT_FILE` sur la CA du PoC, stockage OCI en `dsse` (tags `.sig`/`.att`), sans transparence publique ; `builder.id` et `buildType` sont ceux des politiques du banc C |
| `signature` | 12 s | **Essai de la chaîne de signature, pas un build.** Un TaskRun sur `sc-build` publie seulement `IMAGE_URL`/`IMAGE_DIGEST` d'une image poussée depuis l'hôte (sample-app de la brique 04, dans `builds/essai-signature`). Chains signe via OpenBao, pousse `.sig` et `.att` dans Zot avec le compte `poc-build`, et annote le TaskRun `chains.tekton.dev/signed=true` ; aucune erreur dans le journal de Chains |
| `verifier` | 1 s | Sur l'hôte, avec la clé publique de Transit (`chains-cle-publique.pem`) : **signature de l'image vérifiée** (`cosign container image signature`, digest `3a7ca1b1…`) ; **attestation SLSA v1 vérifiée** (`verify-attestation --type slsaprovenance1`) ; **une autre clé est refusée**. Audit d'OpenBao : connexion JWT de `tekton-chains-controller`, lecture de la clé, deux signatures, sous la seule politique `chains-signature` |
| `webhook` | 44 s | Secret HMAC aléatoire (0600 sur l'hôte, secret Kubernetes `forgejo-webhook`). Task `publier-essai` et Pipeline `sample-app-essai` (objets, pas de spec en ligne), TriggerTemplate, EventListener `forgejo` sur `sc-confiance` (NodePort, joignable depuis Forgejo car 192.168.161.0/24 est autorisé), intercepteurs GitHub (HMAC, événement `push`) puis CEL (branche `main`, dépôt `workspace/sample-app`, commit de 40 caractères hexadécimaux). Webhook Forgejo créé par l'API, secret passé par fichier |
| `essais_webhook` | 32 s | Test 5, voir ci-dessous |

**Test 5 : webhook non signé ou rejoué** ([`tekton-essais_webhook.log`](resultats/tekton-essais_webhook.log)). L'EventListener répond toujours HTTP 202, car il traite les événements de façon asynchrone. Le résultat se lit donc aux PipelineRuns créés et aux journaux. Chaque essai refusable utilise un commit dont l'acceptation se verrait :
| Essai | Résultat | Trace |
|---|---|---|
| A. Livraison réelle de Forgejo (test du webhook, commit `6391fd43…`) | **Acceptée** : PipelineRun `sample-app-6391fd43…` terminé, signé par Chains | — |
| B. Corps non signé (commit `1111…`) | **Refusé** | intercepteurs : `no X-Hub-Signature-256 header set` |
| C. Signature calculée avec un autre secret | **Refusé** | `payload signature check failed` |
| D. Corps modifié sous une signature valide (corps du commit `1111…`, signature du corps du commit `2222…`) | **Refusé** | `payload signature check failed` |
| E. Contrôle positif : livraison signée ici avec le secret du webhook (commit `2222…`) | **Acceptée** : la signature calculée hors de Forgejo est valide, donc les refus ne viennent pas d'un défaut du calcul | — |
| F. **Rejeu à l'identique de E** | **Sans effet** : un seul PipelineRun pour `2222…` | EventListener : `pipelineruns.tekton.dev "sample-app-2222…" already exists` |
| G. Nouvelle livraison de Forgejo pour le même commit | **Sans effet** : un seul PipelineRun pour `6391fd43…` | `already exists` |

Aucun PipelineRun pour `1111…`. La provenance signée du PipelineRun déclenché par Forgejo, vérifiée par cosign avec la clé de Transit, porte le pipeline `sample-app-essai`, le commit `6391fd43…` et le dépôt.

**Constat majeur : une attestation peut être perdue sans erreur** ([`constat-att-ecrasee.log`](resultats/constat-att-ecrasee.log), rejeu en échec [`rejeu-j1-j4-ecart.log`](resultats/rejeu-j1-j4-ecart.log)). Au premier rejeu complet de J1 à J4, la provenance du PipelineRun du commit `6391fd43…` manquait dans Zot, alors que Chains avait annoté ce PipelineRun `signed=true` et journalisé « Successfully uploaded attestation ».
- Cause : en mode `dsse` (tags), chaque ajout d'attestation **lit le tag `.att` du digest, y ajoute une enveloppe, puis le réécrit**, sans verrou ni condition.
- Ici, deux envois vers le même digest se sont chevauchés : le PipelineRun de `6391fd43…` (début 19 h 21 min 40,7 s, écriture à 43,4 s) et le TaskRun de `2222…` (début 41,7 s, écriture à 44,7 s). Le second a réécrit le tag à partir de l'état lu avant l'écriture du premier.
- L'audit de Zot montre 4 écritures du tag par `poc-build`, et il ne reste que 3 enveloppes.
- **Ce n'est pas une falsification**, mais une preuve disparaît silencieusement, et des builds reproductibles produisent justement le même digest.
- Les tags `.sig` subissent la même réécriture non atomique. L'impact est moindre : une seule signature restante suffit à la vérification.
- Pistes, à trancher avant J8 : le mode `sigstore-bundle` (une enveloppe par manifeste referrer, sans réécriture), bloqué tant que chains#2096 n'est pas publiée ; ou un stockage complémentaire de Chains (`tekton`, docdb) ; ou un contrôle qui compare les exécutions signées aux enveloppes présentes.
- Aucun ticket amont trouvé ; aucun n'a été ouvert (accord du propriétaire requis).
- Les essais sérialisent désormais les exécutions qui visent la même image, et vérifient qu'il y a **une enveloppe par exécution signée** (4 sur 4).
- **Récidive en J6** ([`constat-att-ecrasee-j6.log`](resultats/constat-att-ecrasee-j6.log)) : l'étape `restreint` ne sérialisait pas ses deux exécutions vers ce digest (`j6-sans-restriction`, puis `j6-restreint` quelques secondes plus tard).
  - Le journal de Chains compte 63 envois réussis depuis le démarrage du contrôleur ; 58 enveloppes en subsistent. **5 sont perdues**, toutes de `j6-sans-restriction`, sur trois exécutions de l'étape. Aucun envoi d'attestation n'a été dédupliqué : les 48 « already exists » du journal concernent des signatures.
  - Chaque envoi dure désormais **8 à 12 s, contre 2 à 3 s en J4**. La fenêtre de course s'élargit à mesure que les enveloppes s'accumulent sur un même digest, ce que font justement des builds reproductibles.
  - L'une des enveloppes perdues avait été horodatée pendant les 6 s où elle figurait dans le tag. Son bundle, dans `horodatage/bundles`, est le seul témoin restant de cette provenance : 64 bundles pour 63 enveloppes, relevé par l'étape `rattrapage`. C'est un argument concret pour la piste du stockage complémentaire.
  - Déduit, non mesuré : si la provenance la plus récente d'un digest est perdue, la porte, qui ne juge que la plus récente, juge celle d'un build plus ancien du même digest.
  - Correctifs : `restreint` attend la signature de Chains entre ses exécutions et exige deux enveloppes par exécution (62 → 64 → 66). L'invariant d'horodatage apparie enveloppes et bundles par la signature de l'enveloppe : une enveloppe sans bundle est fatale ; les bundles orphelins sont listés, et leur nombre ne doit pas augmenter pendant l'étape.

**Constat de rejeu : compte de service d'un espace neuf.** Le compte `default` d'un espace de noms tout juste créé apparaît de façon asynchrone, et plus tard encore quand le contrôleur vient de redémarrer, comme après l'étape `containerd` de J2 qui relance k3s. Un pod créé trop tôt est refusé (« serviceaccount "default" not found »). Les essais attendent désormais ce compte (`attendre_sa`).

**Constat d'installation** : le contrôleur et le webhook de Triggers s'arrêtent au démarrage sans la ConfigMap `config-triggers-core-interceptors`, définie dans `interceptors.yaml`. La première installation était passée par hasard : l'attente avait vu un pod encore en vie. Sur un cluster neuf, ils bouclaient en erreur. `installer` applique désormais les deux manifestes avant d'attendre.

**Limites du webhook** :
- **les secrets `forgejo-webhook` et `zot-build` sont dans l'espace `builds`, où tournent les TaskRuns** (**traité en J6** : EventListener et secret du webhook dans l'espace de confiance `declencheurs`, identifiants de Chains dans `tekton-chains`, aucun secret dans `builds` ; depuis J7, sauf `zot-images`, choix du propriétaire du 30/10/2026) : quiconque peut y créer un TaskRun peut les monter (workspace, `podTemplate`) sans aucun droit RBAC sur les secrets. Avec le secret HMAC, il forge des webhooks et fait signer des provenances pour des commits arbitraires ; avec `zot-build`, il écrase les `.sig` et `.att`. **À traiter en J6** : EventListener et secret du webhook dans un espace de confiance, PipelineRuns créés dans `builds` par la TriggerTemplate, et identifiants de Chains hors de la portée des tâches ;
- **le nom de PipelineRun déterministe empêche aussi un nouveau build légitime du même commit** (après un échec, par exemple) tant que l'ancien PipelineRun existe ;
- **l'anti-rejeu dure tant que le PipelineRun existe** : un nettoyage des PipelineRuns rouvre la possibilité de rejouer une livraison. Il n'y a pas d'horodatage signé dans les événements `push` ;
- **le commit n'est pas encore confronté à Forgejo** : quiconque détient le secret du webhook fait signer par Chains une provenance pour un commit arbitraire (essai E : commit `2222…` inexistant). La construction de J7 récupérera les sources par ce commit depuis Forgejo, ce qui fera échouer un commit inexistant ;
- l'EventListener écoute en HTTP (le HMAC protège l'intégrité, pas la confidentialité du contenu, qui n'est pas secret) ; il tourne dans l'espace `builds`, et son compte de service lit les `secrets` du cluster (`tekton-triggers-eventlistener-clusterroles`). **Traité en J6** : espace `declencheurs`, rôles sur mesure, aucun accès aux secrets.

**Revue des droits** (ClusterRoles des `release.yaml`, toutes liées au niveau du cluster) :
- les contrôleurs de **Pipelines et de Chains lisent tous les `secrets` du cluster** (`tenant-access`), et Chains peut aussi créer et supprimer des pods. Chains en a besoin pour lire les identifiants de registre des TaskRuns ; c'est un point à garder en tête : un Chains compromis lit tous les secrets ;
- le résolveur de Pipelines lit tous les `secrets` ; les intercepteurs de Triggers aussi, et ne peuvent modifier que leur propre secret de certificat (`resourceNames`) ;
- `tekton-triggers-eventlistener-roles` (droit `impersonate` sur les comptes de service) n'est lié à rien par les releases : il le sera par les EventListeners ;
- les six webhooks d'admission sont en `failurePolicy: Fail` et sans effet de bord.

**Constats sur la provenance de l'essai** ([`tekton-verifier.log`](resultats/tekton-verifier.log)) :
- **`resolvedDependencies` attribue l'image d'étape à `docker.io`** (`oci://docker.io/rancher/mirrored-library-busybox`, digest d'index `101b4afd…`) alors qu'elle a été tirée de Zot (manifeste amd64 `ad9fa4d0…`). Ce busybox existait déjà sur le nœud par les images airgap de k3s, et containerd rapporte le nom et le digest de son magasin local. **L'origine inscrite dans la provenance dépend de ce que le nœud contient déjà** : le contrôle « dépendances depuis Zot » du banc C doit en tenir compte, et les images d'étape de la plateforme ne doivent exister que dans Zot ;
- **`internalParameters` ne contient que les drapeaux de Tekton** (`enforceNonfalsifiability: none`, `verificationNoMatchPolicy: ignore`, etc.). Les paramètres de plateforme prévus (`hermetic`, `isolation`, `cpuModel`) restent à inscrire (point à vérifier, doc 02 §3 ; J6 : `internalParameters` en `slsa-tekton`) ;
- **chaque exécution d'un TaskRun de même sujet ajoute une enveloppe** sous le même tag `.att` (deux enveloppes après deux exécutions au premier passage ; le journal archivé, issu du rejeu complet, n'en compte qu'une, pour une seule exécution) ;
- le compte `poc-build`, utilisé par Chains pour pousser, a le droit `update` : il peut **écraser les tags `.sig` et `.att`**. Ce n'est pas une falsification, la vérification échouerait, mais c'est une suppression de preuve. À traiter avant J8.

**Pour J6** : les cinq résolveurs sont actifs (`bundles`, `cluster`, `git`, `http`, `hub`) et peuvent chercher des définitions de tâches hors de la plateforme ; l'essai utilise un `taskSpec` en ligne, que le test 2 doit refuser.

## Jalon J7 : isolation par Kata (en cours, 30/10/2026)

**Vérification, sans rien installer** ([`kata-verifier.log`](resultats/kata-verifier.log), [`kata.sh`](kata.sh) `verifier`) :
- **Release 4.3.1** : tag léger vers le commit `03cf2ec0…` (signé, vérifié par GitHub), release immuable, attestation de release vérifiée (`gh release verify`).
- **Archive `kata-static-4.3.1-amd64.tar.zst`** (1,02 Go, `1463a2b8…`) : couverte par l'attestation de release (`gh release verify-asset`). Pas d'attestation de build (404) : le workflow atteste chaque composant poussé sur ghcr.io, pas l'archive fusionnée. 171 entrées, 2,50 Go décompressés, toutes sous `/opt/kata`.
  - **Le runtime Go n'y est plus** : en 4.x, `kata-static` ne contient que le shim Rust (`runtime-rs`), et le runtime Go est publié à part (`kata-go-static`, 1,3 Go). Le shim par défaut de kata-deploy est `qemu-runtime-rs`.
  - Les fichiers que lit sa configuration (shim, QEMU, noyau 6.18.56, image Ubuntu, virtiofsd, micrologiciels de QEMU) font **394 Mo** sur 2,50 Go. Le reste : autres hyperviseurs (openvmm seul : 436 Mo), variantes GPU, confidentielles et de débogage.
  - **Configuration lue** :
    - `disable_guest_seccomp = true` : le profil seccomp déclaré dans un pod Kata n'est pas appliqué dans l'invité ;
    - `enable_annotations` laisse un pod changer `kernel_params`, `default_vcpus` et `default_memory`, si containerd lui transmet ces annotations (`pod_annotations` de la section du runtime) ;
    - invité de 1 vCPU et 2 Gio par défaut ;
    - aucun modèle de CPU imposé (`cpu_features = "pmu=off"` seulement) : le niveau x86-64 de l'invité reste à mesurer.
- **Image `kata-deploy:4.3.1` : non vérifiable par construction.**
  - Les jobs qui la publient (`kata-deploy` de `release-amd64.yaml`, `publish-multi-arch-images` de `release.yaml`) n'ont pas la permission `id-token` : ni signature sans clé, ni attestation possible.
  - Mesuré : aucun tag `sha256-*`, aucun referrer, `gh attestation verify` en 404 sur l'index et sur le manifeste amd64.
  - quay.io et ghcr.io servent deux index différents pour le même tag, avec la même config amd64. La seule couche qui diffère contient le même `etc/nsswitch.conf` : même contenu décompressé, seul l'octet « système » de l'en-tête gzip change (`ff` contre `03`).
  - 1,89 Go compressés. Le chart désigne ses images par tag : `kata-deploy` au tag de la version, `kubectl` au tag `latest`.
- **containerd de k3s v1.35.9** : le `config.toml` généré importe `config-v3.toml.d/*.toml` (lu sur `sc-build`). Un runtime s'y déclare par un seul fichier, sans gabarit. k3s ne détecte pas Kata de lui-même (`runtimes.go` : crun, nvidia et wasm seulement). kata-deploy écrit lui aussi un fichier d'appoint, mais depuis un pod privilégié qui écrit sur le nœud et redémarre lui-même k3s par systemd (lu dans `manager.rs`).
- **`sc-build`** : 27 Go libres, 10 Gio de mémoire, 6 vCPU, `kvm_intel.nested=Y`, `/dev/kvm` et `/dev/vhost-vsock` présents, containerd 2.2.7-k3s1.
- La règle `pods-isolation` reconnaît Kata au nom de la RuntimeClass (`kata` ou `kata-qemu`), pas au handler.

**Méthode d'installation : archive attestée (décision et accord d'installation du propriétaire, 30/10/2026)**, au lieu de `kata-deploy` prévu au protocole, dont l'image ne se vérifie pas. Sur `sc-build` : les fichiers que lit `qemu-runtime-rs`, extraits sur l'hôte de l'archive vérifiée et contrôlés sur place par un manifeste sha256 ; un fichier d'appoint de containerd ; un redémarrage de `k3s-agent`. Dans le cluster : la RuntimeClass `kata`. L'exemption Pod Security par RuntimeClass (configuration du server k3s) reste soumise à un accord séparé.

**Installation** ([`kata-installer.log`](resultats/kata-installer.log), [`kata-manifeste.txt`](resultats/kata-manifeste.txt), [`kata/`](kata/)) :
- 23 fichiers et 2 liens (394,2 Mo), extraits sur l'hôte de l'archive revérifiée. Copiés dans `/opt/kata` de `sc-build` (root, 755) et contrôlés sur place : sha256 de chaque fichier, liens, aucun fichier en trop. `zstd` est présent dans la VM, mais l'extraction reste sur l'hôte : seul ce qui est lu est transféré, avec son manifeste.
- Fichier d'appoint `config-v3.toml.d/kata.toml` ([`containerd-kata.toml`](kata/containerd-kata.toml)) : handler `kata`, shim `runtime-rs`, `privileged_without_host_devices = true` et **`pod_annotations = []`**, alors que kata-deploy y recopie les annotations d'`enable_annotations`. Après redémarrage, la section relue dans `crictl info` est conforme.
- `k3s-agent` redémarré sur `sc-build`, avec le rattrapage suspendu, aucun PipelineRun actif et aucun pod en cours sur le nœud.
- RuntimeClass `kata` ([`runtimeclass.yaml`](kata/runtimeclass.yaml)) : placement en zone build (label et taint relus dans le cluster), surcoût de 320 Mi et 250 m (valeur du chart pour `qemu-runtime-rs`). k3s crée de lui-même dix autres RuntimeClasses (crun, nvidia, wasm…), sans runtime derrière sur `sc-build` : containerd n'y connaît que `kata`, `runc` et `runhcs-wcow-process` (relevé dans `crictl info`).

**Essais** ([`kata-essais.log`](resultats/kata-essais.log), prédiction écrite avant) : trois pods de `builds` conformes à `restricted`, avec la même image busybox glibc tirée de Zot.

| Mesure | runc | Kata |
|---|---|---|
| Noyau | 6.12.113 (`sc-build`) | **6.18.56** (invité) |
| vCPU, mémoire | 6, 10 Gio | 1, 1,9 Gio (défaut de 2048 Mio) |
| Niveau x86-64 (`ld.so --help`) | v3 pris en charge, v4 non, aucun drapeau avx512 | **identique** |
| Seccomp (`/proc/self/status`) | 2 (filtré) | **0** |
| `NoNewPrivs`, `CapEff` | 1, 0 | 1, 0 |
| Conteneur lancé après la création | 0 s | 3 à 5 s |

- **Contrôle « pod Kata en x86-64-v3 » : atteint.** QEMU est lancé avec `-cpu host,pmu=off` (relevé sur `sc-build` pendant la vie d'un pod ; conforme au code de runtime-rs 4.3.1), avec `-smp 1` et `-m 2G`. L'invité voit donc le même modèle que la VM, « Intel Core Processor (Haswell, no TSX, IBRS) » : c'est le modèle nommé `Haswell-v4` de J1, sans AVX-512. Le niveau de l'invité dépend du nœud, pas du pod : c'est sur ce fait que reposera le canal de `cpuModel`.
- **Constat : pas de seccomp dans l'invité.** Avec `disable_guest_seccomp = true`, le pod déclare `RuntimeDefault` et Pod Security l'admet en `restricted`, mais aucun filtre n'est posé dans l'invité. La frontière est la VM, pas seccomp. Pour la décision sur l'exemption : un pod Kata conforme à `restricted` n'est pas mieux confiné par seccomp qu'un pod exempté. Deux éléments pour le propriétaire, à trancher au moment de la mesure de BuildKit :
  - côté nœud, `seccomp_sandbox = ""` : QEMU lui-même tourne sans bac à sable seccomp sur `sc-build` (lu dans la configuration, non mesuré) ;
  - côté invité, le seccomp peut être réactivé en surchargeant `disable_guest_seccomp` par un fichier d'un répertoire `config.d/` voisin de la configuration, que runtime-rs fusionne (lu dans `drop_in.rs` de la 4.3.1, non essayé). Avec un seccomp effectif, BuildKit rootless risque d'exiger `Unconfined`, donc l'exemption.
- **Annotation `default_memory=4096`** : sans effet (même mémoire), comme prédit avec `pod_annotations = []`. Sans témoin positif, la cause n'est pas isolée : la même annotation n'a pas été mesurée avec `pod_annotations` ouvert.
- **Pod Kata privilégié dans `builds`** (avant l'exemption) : refusé par Pod Security (`enforce: restricted`), avant Kyverno. La construction ne pourra être privilégiée qu'avec l'exemption. Depuis l'exemption, `kata.sh essais` attend l'admission de ce pod : rejoué après l'exemption le 30/10/2026, pod admis, autres contrôles inchangés ; le journal d'avant l'exemption (refus) reste au commit `e16fe8d`.
- **Qui peut toucher une RuntimeClass.** `pods-isolation` reconnaît Kata au nom de la RuntimeClass. Parmi les 72 comptes de service et l'opérateur :
  - aucun ne peut en créer ;
  - le ramasse-miettes peut les modifier et les supprimer ;
  - le contrôleur des espaces de noms peut les supprimer.

  La première prédiction (ramasse-miettes seul) a été démentie ; elle est archivée ([`kata-essais-premiere-prediction.log`](resultats/kata-essais-premiere-prediction.log)). Supprimer `kata` ne contourne rien : l'API refuse un pod qui désigne une RuntimeClass absente.

**Admission** ([`politique-admission.log`](resultats/politique-admission.log)) : `pods-isolation` ne reconnaît plus que `kata` ; `kata-qemu`, qui n'existe pas, est retiré.
- Le cas « privilégié sous Kata » est évalué à l'admission dès que la RuntimeClass existe. Avant J7, par exemple au rejeu jusqu'à J6, il reste en CLI seul.
- Nouveau cas témoin : un pod privilégié sous `crun`, RuntimeClass créée par k3s, est refusé.
- **38 cas, parité 38/38, tous conformes**, 31 événements `PolicyViolation` pour 31 refus.

**Redémarrage des trois VM** ([`redemarrage-vm.log`](resultats/redemarrage-vm.log), [`kata-temoin.log`](resultats/kata-temoin.log)) : tous les contrôles de J1 à J6 repassent (arrêt 7 s, démarrage 9 s, nœuds prêts en 19 s). Après le retour de `sc-build`, containerd recharge le runtime `kata` à partir du fichier d'appoint, et un pod Kata démarre sur le noyau de l'invité (6.18.56) 5 s après sa création (`kata.sh temoin`, désormais rejoué par `redemarrer.sh`). Aucun secret dans les journaux des VM ([`fuites-j7.log`](resultats/fuites-j7.log)).

**Journaux réécrits par le rejeu sous Cilium** (30/10/2026) : presque tous les journaux de J1 à J7 (`stockage-*`, `openbao-*`, `tekton-*`, `tsa-*`, `politique-*`, `kata-*`, `buildkit-*`, `voie-d-*`, `construction-*`) montrent désormais ce rejeu. Les versions sous kube-router, auxquelles renvoient les chiffres des sections J2 à J7 écrits avant la mesure de Cilium, restent dans le commit `8f05b2c`. Celles que les blocs récents citent directement sont archivées sous le suffixe `-kube-router`.

**Journaux réécrits par J7** : `construction-taches.log`, `construction-construire.log` et `construction-provenance.log` montrent la construction sans sortie réseau (première version archivée : `construction-*-premiere-version.log`) ; `kata-reseau.log` montre le quatrième passage (troisième archivé : `kata-reseau-troisieme-passage.log`) ; `stockage-zot.log` (quatre comptes depuis `poc-images`), `fuites-j7.log`, `redemarrage-vm.log`, `politique-admission.log` et `.tsv`, `openbao-controle.log`, `openbao-deverrouiller.log`, `openbao-temoin.log` et `tsa-temoin.log` montrent désormais les passages de J7. Ceux de J6, auxquels renvoient les chiffres de la section J6 (redémarrage : arrêt 13 s, démarrage 8 s, nœuds en 15 s ; admission : 37 cas, parité 36/36), restent dans le commit `6973403`.

**BuildKit rootless dans un pod Kata** ([`buildkit.sh`](buildkit.sh), [`buildkit-image.log`](resultats/buildkit-image.log), [`buildkit-essais.log`](resultats/buildkit-essais.log)) :
- **Image `moby/buildkit:v0.34.1-rootless`** (version courante, publiée le 20/10/2026) :
  - tag annoté signé, vérifié par GitHub (commit `f5b59a1f…`) ; index `f68752a5…`, manifeste amd64 `ace6811c…` ;
  - **seul le manifeste d'attestation (`163cf53e…`) est signé**, par un bundle sigstore en référent OCI 1.1, produit par le workflow réutilisable `docker/github-builder` (`bake.yml`, épinglé par l'appelant à `58cb9f5b…`) appelé par `moby/buildkit` au tag. Ce manifeste désigne l'image amd64 comme sujet, comme la provenance SLSA v1 qu'il porte : l'image n'est couverte qu'à travers lui ;
  - signature vérifiée par cosign (identité exacte, dépôt appelant, ref et commit du tag, déclencheur `push`) et par `gh attestation verify` (workflow appelant, exécuteur hébergé par GitHub) ; identité voisine (tag v0.34.0) refusée ; copie dans Zot avec le référent, signature revérifiée sur la copie ;
  - `newuidmap` et `newgidmap` n'ont pas de bit setuid, mais des capacités de fichier (`CAP_SETUID`, `CAP_SETGID`, lues dans la couche).
- **Version** : la v0.25.2 de la brique 04 n'a aucune signature (aucun référent, provenance v0.2 non signée), d'où la v0.34.1, qui embarque runc 1.5.2 et rootlesskit 3.2.0. Si le digest de sample-app diffère de `3a7ca1b1…`, une contre-épreuve hors Kata avec la v0.34.1 sera nécessaire avant d'imputer l'écart à Kata.
- **Essais en `restricted`** (pods de `builds` ; prédiction : résultats de l'essai exploratoire du 30/10/2026, rejoués par le script) :

| Mesure | runc | Kata |
|---|---|---|
| Bounding set, `NoNewPrivs`, `Seccomp` | 0, 1, 2 | 0, 1, **0** |
| Étiquette AppArmor (`/proc/self/attr/current`) | `cri-containerd.apparmor.d` (enforce) | illisible (`Invalid argument`) ; la présence d'AppArmor dans l'invité n'est pas mesurée |
| `unshare -U -r -m` (user namespace sans privilège) | **refusé** (`Operation not permitted`) | **réussi** : bounding set complet dans le nouvel espace, tmpfs monté |
| rootlesskit de l'image | (non essayé) | **échec** : `newuidmap … Could not set caps` |
| buildkitd sous `unshare -U -r` (un seul UID, sans `newuidmap`) | (non essayé) | démon démarré (`no-sandbox`, `native`) ; **aucun `RUN`** : `lchown` d'un fichier à l'UID 65534 (busybox de Zot), puis, sur une base où tout appartient à l'UID 0, montage de `devpts` refusé (`gid=5` hors correspondance) |

- **Pourquoi** : rootlesskit 3.2.0 n'a pas de repli quand `newuidmap` échoue (lu dans `parent.go`). Ce paragraphe attribuait d'abord l'échec de `newuidmap` sous Kata à `no_new_privs` (`allowPrivilegeEscalation: false`, exigé par `restricted`) : c'est démenti, car il échoue de la même façon dans un pod Kata privilégié (`NoNewPrivs` à 0, bounding set complet). La cause mesurée est que ses capacités de fichier ne sont pas visibles dans l'invité (voir « BuildKit après l'exemption » plus bas). Sans `newuidmap`, un processus ne peut faire correspondre que son propre UID et son propre GID. BuildKit 0.34.1 corrige certaines options de montage en rootless (`FixUpOCI`), mais pas le `gid=5` de `devpts`.
- **Constat : en `restricted`, BuildKit ne peut exécuter aucun `RUN`, ni sous runc ni sous Kata.** Contourner par un runc ou un BuildKit modifiés relèverait de l'outillage maison écarté en J4. La mesure exige donc un relâchement de Pod Security pour le pod de construction.
- **Taille de l'invité avec des limites** (2 CPU, 3 Gi, demandes égales aux limites) :
  - prédit par `initial_size.rs` (`static_sandbox_resource_mgmt`) : ceil(0,2 + 2) = 3 vCPU et 32 + 3072 = 3104 Mio ; le surcoût de la RuntimeClass est exclu par kubelet (`calculateSandboxResources`, `ExcludeOverhead`) ;
  - mesuré : QEMU en `-smp 3` et `-m 3104M` (relevé sur `sc-build` pendant la vie du pod), invité de 3 vCPU et MemTotal 2,89 Gio.

  Les limites du pod fixent donc la taille de la VM.

**Relâchement : voie déjà retenue par le propriétaire en J6** (ADR 0001) : exempter de Pod Security les pods de la RuntimeClass `kata`, sur accord séparé au moment de modifier k3s.
- **Mise en œuvre relevée** : k3s v1.35.9 n'a pas d'option `--pod-security-admission-config-file`, qui est une option de RKE2 (aide de `k3s server`). L'ADR 0001 la citait à tort. kube-apiserver ne reçoit aujourd'hui que `--enable-admission-plugins=NodeRestriction`, sans fichier de configuration d'admission (lu dans le journal de k3s). La voie est donc `kube-apiserver-arg: admission-control-config-file=…` (finalement par un fichier d'appoint de `config.yaml.d`, voir plus bas, plutôt que dans `k3s/sc-confiance.yaml`), avec un fichier `AdmissionConfiguration` : niveaux par défaut `privileged`, inchangés, et `exemptions.runtimeClasses: [kata]`. Elle exige un redémarrage de k3s sur `sc-confiance`.
- **Portée** : tout pod de la RuntimeClass `kata` échappe à Pod Security, dans tous les espaces, conteneurs d'init de Tekton compris. `builds` reste en `restricted` pour les pods runc. Les pods Kata restent soumis à la règle Kyverno `pods-isolation` : ni `hostNetwork`, ni `hostPID`, ni `hostIPC`, ni `hostPath`, pour tous les pods. La RuntimeClass ne place ses pods que sur `sc-build`.
- **Prédictions pour la mesure qui suivra l'exemption** (écrites le 30/10/2026, avant l'accord), dans `builds`, image rootless, UID 1000 :
  - **pod Kata privilégié** (`privileged_without_host_devices`) : rootlesskit réussit ; les deux constructions réussissent **avec** le bac à sable des processus (sans `--oci-worker-no-process-sandbox`, car un conteneur privilégié n'a pas de chemins masqués dans `/proc`) ; une étape ne voit pas le démon ; un `RUN --network=none` n'atteint pas Zot, un `RUN` sans cette option l'atteint ;
  - **pod Kata non privilégié** avec `allowPrivilegeEscalation` et les capacités par défaut de containerd (ce que `baseline` permettrait), à titre de comparaison :
    - rootlesskit réussit (`CAP_SETUID` et `CAP_SETGID` dans le bounding set, `no_new_privs` à 0) ;
    - sans `--oci-worker-no-process-sandbox`, l'étape échoue au montage de `/proc` (chemins masqués) ;
    - avec cette option, les deux constructions réussissent, mais une étape voit le démon : elle peut lui envoyer un signal et lire `/proc/<pid>/root` (même UID, même espace de PID).
  - **Démenties pour les deux pods** : rootlesskit échoue dans les deux (voir « BuildKit après l'exemption » plus bas).

**Exemption posée (accord du propriétaire du 30/10/2026)** ([`kata-exemption.log`](resultats/kata-exemption.log), [`k3s/pod-security.yaml`](k3s/pod-security.yaml), [`k3s/sc-confiance-pod-security.yaml`](k3s/sc-confiance-pod-security.yaml)) :
- **Pose** (`kata.sh exemption`, après `essais`) :
  - sur `sc-confiance`, en 0600 : `/etc/rancher/k3s/pod-security.yaml` (niveaux par défaut `privileged` et `latest`, ceux de Kubernetes sans fichier ; `exemptions.runtimeClasses: [kata]`) et le fichier d'appoint `/etc/rancher/k3s/config.yaml.d/pod-security.yaml`, dont la clé `kube-apiserver-arg+` s'ajoute à la liste de `config.yaml` (fusion lue dans `pkg/configfilearg` de k3s v1.35.9) ;
  - la pose suit `essais` : faite dès J1, elle ferait mentir le refus du pod Kata privilégié que `essais` mesure.
- **Redémarrage du server k3s**, rattrapage suspendu et aucun PipelineRun actif, prédiction écrite avant :
  - API prête et nœuds `Ready` 6 s après ; `kube-apiserver` reçoit `--admission-control-config-file` (journal de k3s) ;
  - **mêmes 19 conteneurs** sur `sc-confiance`, mêmes identifiants (`crictl`) : l'unité k3s est en `KillMode=process`, rien n'est arrêté ;
  - OpenBao reste descellé, même clé (signature témoin d'avant vérifiée après) ; Kyverno répond ; témoin TSA vérifié ; un passage réussi de chaque CronJob après le redémarrage.
- **Admission** (dry-run serveur, prédiction écrite avant) :
  - dans `builds`, un pod Kata privilégié est admis, ainsi qu'un pod Kata non privilégié avec `allowPrivilegeEscalation` et les capacités par défaut ;
  - un pod runc privilégié reste refusé par Pod Security ;
  - **Kyverno reste la garde des pods Kata** : un pod Kata privilégié avec `hostPath` est refusé (`pods-isolation`), et un pod Kata privilégié dans `tsa`, sans nodeSelector, aussi (`zone-confiance` : la RuntimeClass lui ajoute le nodeSelector et la tolérance de la zone build).
- Témoin Kata repassé ; `kata.sh temoin` indique désormais si l'exemption est lue par kube-apiserver.
- **Prédiction pour `politique admission`, rejoué après l'exemption** (écrite avant) : mêmes résultats qu'avant (38 cas, parité 38/38, 31 événements pour 31 refus). Les pods des cas sont dans `bancc`, sans label Pod Security, donc au niveau par défaut `privileged`, inchangé par le fichier. **Mesuré** ([`politique-admission.log`](resultats/politique-admission.log)) : 38 cas, parité 38/38, tous conformes, 31 événements ; mêmes verdicts qu'avant l'exemption.

**BuildKit après l'exemption** ([`buildkit-exempte.log`](resultats/buildkit-exempte.log)) :
- **Premier passage : prédiction démentie** ([`buildkit-exempte-premiere-prediction.log`](resultats/buildkit-exempte-premiere-prediction.log)). Dans le pod Kata privilégié, `NoNewPrivs` vaut 0 et le bounding set est complet, et `newuidmap` échoue toujours (« Could not set caps »). L'étape n'avait pas archivé la sortie du pod, sorti en échec sur un `kill` final : cette sortie a été ajoutée à la main au journal. L'étape archive désormais la sortie de chaque pod avant tout jugement.
- **Cause mesurée** (prédiction corrigée, écrite avant le second passage) :
  - virtiofsd est lancé sans `--xattr` pour le pod Kata (relevé sur `sc-build`). runtime-rs 4.3.1 n'ajoute `--xattr` que si `disable_guest_selinux` est faux (`share_virtio_fs_standalone.rs`), et la configuration installée le met à vrai ;
  - dans l'invité, la racine du conteneur est en `virtiofs` et refuse un attribut étendu (`setfattr` : « Operation not supported »). Un tmpfs de l'invité l'accepte (témoin positif), comme la racine `overlay` sous runc ;
  - les capacités de fichier de `newuidmap` (attribut `security.capability`) ne sont donc pas visibles dans l'invité : rootlesskit échoue, dans un pod privilégié comme dans un pod non privilégié avec `allowPrivilegeEscalation`.
- **BuildKit en root dans un pod Kata privilégié**, mesuré comme option (même image vérifiée ; `buildkitd` et `buildkit-runc` de l'image, sans rootlesskit) :
  - démon en `process-mode: sandbox`, réseau `host` (mode `auto` sans configuration CNI : repli sur l'hôte, lu dans `netproviders`) ;
  - trois constructions réussies, dont une sur busybox de Zot ; une étape ne voit pas le démon (espace de PID propre) ;
  - depuis une étape, Zot est joignable par le réseau par défaut et injoignable en `--network=none`.
- **Constat : sous Kata, avec cette configuration, BuildKit rootless est impossible, même exempté et privilégié.** L'exemption est nécessaire mais ne suffit pas pour le mode rootless. BuildKit en root dans un pod Kata privilégié construit, avec le bac à sable des processus ; la frontière avec le nœud est alors la VM.
- **Voie A sur sample-app** ([`buildkit-sample_app.log`](resultats/buildkit-sample_app.log)) : BuildKit v0.34.1 en root dans un pod Kata privilégié (2 CPU, 6 Gi), mêmes entrées que la voie D (tar épinglé, livré par `kubectl exec`, sha256 vérifié dans le pod), image de build de la voie D (`d50ae575…`) en contexte nommé, Dockerfile et options de la brique 04, deux constructions depuis deux chemins :
  - **premier passage en échec** ([`buildkit-sample_app-premier-passage.log`](resultats/buildkit-sample_app-premier-passage.log)) : avec la racine de BuildKit sur la racine du conteneur (virtio-fs), le `COPY --from=build` échoue, car BuildKit calcule l'empreinte du fichier avec ses attributs étendus (« failed to create hash for /out/sample-app: operation not supported »). Les constructions d'essai n'avaient pas ce cas. La voie A demande donc, elle aussi, un système de fichiers de l'invité pour l'état de BuildKit (ou `--xattr`) ;
  - **racine de BuildKit sur un tmpfs de l'invité** (`emptyDir` en mémoire) : **les deux constructions donnent `3a7ca1b1…`**, le digest de la brique 04 (BuildKit 0.25.2, cloud en root et laptop en rootless), avec le binaire `e3749c68…`, en 26 s puis 18 s. Le passage de la v0.25.2 à la v0.34.1 et l'exécution sous Kata ne changent pas l'image : le critère de J7 tient avec la voie A ;
  - coût : le tmpfs de BuildKit atteint 1,1 Go après une construction et 1,7 Go après deux (snapshotter `native`, copies complètes de l'image de build), compté dans la mémoire du pod et donc de la VM.
- **Voies soumises au propriétaire** (décision de J4 : « BuildKit rootless dans un pod Kata ») : A et B ci-dessous ; la voie D, sans conteneur imbriqué, est mesurée plus bas :
  - **A. BuildKit en root dans un pod Kata privilégié** : mesuré ci-dessus, sans nouveau changement système. C'est le modèle de base de l'ADR 0001 (Kata avec `privileged_without_host_devices` pour les images). Dans l'invité, les étapes tournent en root, isolées du démon par le bac à sable des processus. Une étape root dans l'invité fait face à QEMU et à virtiofsd sur le nœud ; s'y ajoutent les deux éléments déjà consignés, `seccomp_sandbox` vide (lu, non mesuré) et pas de seccomp dans l'invité. Le critère du digest n'est pas menacé par le mode root lui-même : la brique 04 a mesuré `3a7ca1b1` identique en root (cloud) et en rootless (laptop), avec la v0.25.2. Pour la construction de sample-app (lu, non essayé) : le test 2 n'interdit pas `runtimeClassName` dans le `podTemplate` d'un PipelineRun, et le contexte privilégié des étapes devra venir de la tâche signée (`stepTemplate`) ;
  - **B. Garder le rootless en ajoutant `--xattr` à virtiofsd**, par un fichier `config.d/` voisin de la configuration de `qemu-runtime-rs` sur `sc-build` (nouvel accord). La fusion de `drop_in.rs` remplace un tableau au lieu de le compléter : le fichier devrait répéter `virtio_fs_extra_args` en entier. `--xattr` active les attributs étendus entre l'invité et les fichiers partagés de l'hôte ; `--xattrmap` permet des règles de traduction (aide de virtiofsd 1.14.0), dont l'effet sur les capacités de fichier n'est ni lu ni mesuré. Non essayé. B ne ramène pas à `restricted` : `newuidmap` exige `NoNewPrivs` à 0, donc le pod resterait exempté, soit privilégié (bac à sable des processus attendu), soit non privilégié avec `allowPrivilegeEscalation`, où il faudrait `--oci-worker-no-process-sandbox` et où une étape verrait le démon (prédit ; l'échec du montage de `/proc` sans cette option n'a jamais été mesuré, rootlesskit échouant avant). Le fichier `config.d/` irait dans `/opt/kata`, que `kata.sh installer` contrôle par un nombre de fichiers égal au manifeste (`conforme_vm`) : le contrôle devrait l'admettre explicitement. Que le shim relise sa configuration à chaque sandbox ou qu'il faille redémarrer `k3s-agent` n'est pas lu.

**Voie D : construire sans conteneur imbriqué** (mesure demandée par le propriétaire le 30/10/2026 ; [`voie-d.sh`](voie-d.sh), [`voie-d-image.log`](resultats/voie-d-image.log), [`voie-d-compiler.log`](resultats/voie-d-compiler.log), [`voie-d-assembler.log`](resultats/voie-d-assembler.log)). Un `RUN` est un conteneur dans le conteneur, d'où le besoin de root ou de plusieurs UID dans l'invité, quel que soit l'outil Dockerfile (BuildKit ; Buildah, dont la documentation exige `cap_setuid` et `cap_setgid` dans un pod ; kaniko, archivé, interdit par le doc 04). La voie D compile dans le conteneur du pod lui-même, puis assemble l'image sans rien exécuter. Ni BuildKit ni conteneur imbriqué :
- **Image de build assemblée sans exécution** (tar GNU déterministe, puis `crane append` et `crane mutate` de `mise.toml`, v0.20.6) :
  - entrées inventoriées : toolchain Go 1.26.10 (module `h1:5VAGHlY8…` = sum.golang.org, arbre extrait `4d51374d…`), busybox statique 1.36.1 du nixpkgs épinglé (`49227c02…`) et ses 395 liens d'applets, `/tmp` ; environnement du `Dockerfile.builder` de la brique 04, sans son `RUN` ;
  - deux assemblages depuis deux répertoires : même couche et **même image `d50ae575…`**, poussée dans Zot (`plateforme/builder-go-voie-d`). crane n'ajoute aucune date (historique à valeur nulle, lu dans `mutate` de go-containerregistry).
- **Compilation dans un pod Kata de `builds`**, sans privilège ni exemption (prédiction écrite avant, toutes vérifiées) :
  - contexte de `restricted`, limites de 2 CPU et 3 Gi : `NoNewPrivs` 1, aucune capacité, `Seccomp` 0 (invité) ; la même spec sans `runtimeClassName` est admise par Pod Security `restricted` (dry-run serveur). La voie D ne dépend donc pas de l'exemption, mais elle dépend de Kata : sous runc, `unshare` est refusé par seccomp (`buildkit-essais.log`) ;
  - entrées (arbre de la brique 04 : `canon/source` sans `.git`, plus `web/dist` ; fermeture Hermeto) livrées par `kubectl exec`, tar vérifié par sha256 sur l'hôte et dans le pod. C'est le canal de l'opérateur, pas celui du pipeline : la récupération depuis Forgejo et Zot relève de la construction de sample-app. Écart connu : le dépôt Forgejo de J2 (`poc/sample-app`) diffère de cet arbre par `web/package.json` et `web/package-lock.json` ;
  - `go build` (options de la brique 04) sous `unshare -U -r -n`, créé sans privilège : le processus n'a que `lo` ; Zot est joignable depuis le pod (témoin positif), injoignable dans l'espace réseau. La coupure est posée avant la compilation : elle ne dépend pas de la fenêtre de kube-router relevée en J6 ;
  - **binaire `e3749c68…` en 27 s, identique à celui de la brique 03 et de l'image `3a7ca1b1`** ; fermeture vide : `github.com/go-chi/chi/v5@v5.2.3` introuvable ; proxy réseau (Zot) : `network is unreachable`.
- **Image sample-app assemblée sans exécution** (tar GNU en `ustar`, `crane`), deux fois depuis deux répertoires : **même image `c9244139…`**. Face à `3a7ca1b1` :
  - même binaire, même taille de tar ; 18 octets diffèrent, tous dans l'en-tête du fichier : `devmajor` et `devminor` (vides chez GNU tar, zéros octaux chez BuildKit, écart relevé en exploratoire avant la prédiction) et la somme de contrôle qui en découle. D'où un `diff_id` différent ;
  - configuration identique, hors `created` et historique : `User`, `Env`, `Entrypoint`, `WorkingDir` et la plateforme ont été fixés comme la référence ; `created` vaut `0001-01-01` chez crane (date nulle de Go, que crane 0.20.6 ne permet pas de fixer) et `1970-01-01` chez BuildKit. **Premier passage démenti sur ce point** ([`voie-d-assembler-premiere-prediction.log`](resultats/voie-d-assembler-premiere-prediction.log)), prédiction corrigée ;
  - compression : niveau rapide chez crane (octet XFL `04`), niveau par défaut chez BuildKit (`00`) ;
  - **digest différent** : l'image est reproductible par elle-même, mais pas identique à celle de BuildKit. Un replay (brique 10) devra utiliser le même assembleur, ou comparer contenus et `diff_id`.
- **Ce que coûterait la voie D** :
  - santé des outils : crane (go-containerregistry) est absent du doc 04, et ko y est « à surveiller, hors chemin critique ». Les adopter les ferait passer sur le chemin critique, ce qui demande d'abord un verdict du doc 04 ;
  - portée : Go seulement, et des images sans `RUN` qui installe des paquets ; chaque écosystème demanderait son assemblage ; aucun Dockerfile ;
  - code de plateforme : le tar déterministe, les appels à crane et l'enveloppe `unshare` deviennent du code maintenu par la plateforme ;
  - le privilège ne disparaît pas de la plateforme : mock exige root, et l'ADR 0001 prévoit Kata privilégié pour mock, sbuild et les images. La voie D réduit le privilège des images Go, elle ne le supprime pas ;
  - elle remet en cause l'issue de la grille B de l'ADR 0000 (Hermeto + BuildKit), figée : décision du propriétaire.

**Décision du propriétaire (30/10/2026) : voie A**, après la mesure des voies A et D sur sample-app. Les images se construisent avec BuildKit en root dans un pod Kata privilégié, la VM servant de frontière avec le nœud (modèle de base de l'ADR 0001). Elle remplace « BuildKit rootless dans un pod Kata » (option C de J4), impossible sous Kata avec cette configuration. Conséquences :
- l'exemption Pod Security de la RuntimeClass `kata` reste en place ; Kyverno (`pods-isolation`, zones) reste la garde des pods Kata ;
- l'état de BuildKit va sur un tmpfs de l'invité (`emptyDir` en mémoire), compté dans la mémoire du pod et de la VM : 1,7 Go après deux constructions de sample-app ;
- le critère de J7 reste le digest `3a7ca1b1` ;
- la voie B (`--xattr`) n'est pas poursuivie ; les mesures de la voie D restent archivées comme alternative sans privilège pour les images Go.

**Construction de sample-app dans un PipelineRun, par la voie A** ([`construction.sh`](construction.sh), tâches [`construire-image`](politique/taches/construire-image.yaml) et [`publier-image`](politique/taches/publier-image.yaml), pipeline [`sample-app`](politique/taches/sample-app.yaml)). Cette première version de `construire-image`, qui tirait ses entrées elle-même, est remplacée par la construction sans sortie réseau (option 3, plus bas). Choix du propriétaire du 30/10/2026, sur trois questions :
- **tâche de push séparée** : la tâche Kata privilégiée écrit l'image en tar OCI dans un workspace (PVC), et une tâche runc restreinte la pousse. L'identifiant d'écriture n'entre jamais dans la VM où s'exécutent les `RUN` ;
- **compte Zot `poc-images`**, accord pour modifier Zot : création seulement, par digest, dans `builds/**`, sous une condition CEL de Zot v2.1.22 (`req.referenceType != "tag"`, lue dans `pkg/api/authz.go`). Le compte ne peut écrire ni tag, donc ni `.sig` ni `.att`, ni mise à jour, ni suppression. C'est le point « si Zot le permet » laissé ouvert en J6. Son mot de passe vit dans un secret `zot-images` de `builds`, que seule monte la tâche signée `publier-image`. Kyverno refuse déjà un secret en `podTemplate` ou en workspace (test 2), et l'opérateur ne peut pas créer de pod dans `builds` ;
- **`web/dist` tiré de Zot par digest** : c'est la sortie de la brique 03. Node reste hors de la chaîne, comme en brique 04 (2c, brique 11).

| Étape | Mesure |
|---|---|
| `compte` ([journal](resultats/construction-compte.log)) | `stockage.sh zot` rejoué avec le 4e compte, Zot redémarré, politique relue dans son journal. `poc-images` écrit par digest dans `builds/essai-images` (deux fois, puis par `PUT` direct : 201). Refus 403 avec le motif de la condition : tag, tag `sha256-….att`, digest avec `?tag=`. Refus 403 aussi hors de `builds/` et pour une suppression. Secret `zot-images` et ConfigMap `ca-poc` (CA publique) appliqués dans `builds` |
| `entrees` ([journal](resultats/construction-entrees.log)) | Arbres de la brique 03 conformes aux empreintes de `voie-d.sh`. Fermeture poussée par `closure.sh` (brique 03 : un fichier par couche, 8 couches) et `web/dist` (même format, 2 couches), chacune deux fois : **même digest** (`0ab5a507…`, `47f72275…`, épinglés). Relues en lecture anonyme : mêmes chemins et contenus |
| `taches` ([journal de la première version](resultats/construction-taches-premiere-version.log)) | Les deux tâches sont signées une fois et versionnées (`*.signee.yaml`), et leurs digests sont ajoutés à la liste revue. tkn v0.46.2 conserve les résultats objets, les volumes (dont l'`emptyDir` en mémoire) et le contexte privilégié. La pipeline est signée à chaque passage : elle désigne ses tâches, la fermeture, `web/dist` et le dépôt d'image par digest, que le créateur du PipelineRun ne peut pas changer. Bundles reproductibles (même digest d'une poussée à l'autre) |
| `constat_cm` ([journal](resultats/construction-constat_cm.log)) | Voir le constat ci-dessous |
| `construire` ([journal de la première version](resultats/construction-construire-premiere-version.log)) | PipelineRun du gabarit en service : pipeline remplacée, commit `6391fd43` de `main`, workspace en PVC, `runtimeClassName: kata` pour la seule tâche `construire` (`taskRunSpecs`, gabarit de pod recopié). **Réussi en 65 s** (construire 59 s, dont 30 s de BuildKit ; publier 6 s). Trusted Resources vérifie la pipeline et les deux tâches. Pod affinity assistant admis (`restricted`, zone build). Pod de construction sous Kata sur `sc-build`, QEMU en `-smp 3 -m 6176M` (limites de la seule étape `construire`, prédit). Étapes `sources` et `entrees` en UID 65532, `construire` privilégiée. Arbre du commit `30e808ff…` (celui de J2). **Image `3a7ca1b1…`**, la même qu'en brique 04 et que `buildkit.sh sample_app` : l'écart `web/package*.json` du dépôt ne touche pas l'image, qui ne contient que le binaire. tmpfs de BuildKit : 1,1 Go. Push par `poc-images` (201 dans l'audit de Zot), puis deux `.att` par `poc-build` (TaskRun `publier` et PipelineRun). Chains signe les deux TaskRuns et le PipelineRun. **Même PipelineRun sans `runtimeClassName`** : pod de construction refusé (`PodAdmissionFailed`, Pod Security `restricted` : `privileged`), `publier` jamais lancé, aucune écriture de `poc-images` |
| `provenance` ([journal de la première version](resultats/construction-provenance-premiere-version.log)) | La provenance du PipelineRun est vérifiée par cosign avec la clé de Chains, retrouvée par son `invocationId`, et une autre clé est refusée. Contenu : buildType `slsa-tekton`, sujet `builds/sample-app@3a7ca1b1`. **`resolvedDependencies`** : pipeline et deux tâches (bundles par digest, TaskRuns en contenu), images d'étape (BuildKit, outils), `git+https://…/workspace/sample-app.git` en `sha1:6391fd43…`, fermeture, `web/dist` et image de build par digest. Elles sont déclarées par `CHAINS-GIT_URL`/`CHAINS-GIT_COMMIT` et par des résultats objets `*ARTIFACT_INPUTS`, noms lus dans le code de Chains v0.29.9. L'affirmation de la brique 03 (« ce digest entre dans `resolvedDependencies` ») est prouvée sur une vraie provenance. **`runtimeClassName: kata` est signé deux fois** : dans les paramètres externes (`taskRunSpecs`) et dans le TaskRun `construire` en contenu. C'est une donnée pour l'option (c) des `internalParameters` |

- **Constat : sous Kata 4.3.1 (runtime-rs), une ConfigMap partagée entre conteneurs disparaît dès que l'un d'eux se termine.**
  - Mesure : deux conteneurs d'un pod Kata montent la même ConfigMap. Quand le premier sort, le second ne la lit plus (lien `ca.crt` orphelin). Témoin : il la lit si le premier reste en vie. Un `emptyDir` sur disque survit.
  - Portée pour Tekton : les étapes se terminent l'une après l'autre, si bien qu'une ConfigMap partagée entre étapes n'est lisible que par la première. Le cas d'un secret partagé entre étapes n'est pas mesuré.
  - Contournement : la CA n'est montée que dans la première étape, qui la recopie dans l'`emptyDir` partagé.
  - Rien de trouvé dans les issues de kata-containers (recherche du 30/10/2026). Aucune issue amont sans accord du propriétaire.
- **Premiers passages** ([archive](resultats/construction-construire-premiers-passages.log)) :
  - shebang `/bin/sh` absent de l'image d'outils (`sh` est dans `/busybox`) ;
  - CA perdue après la première étape (constat ci-dessus) ;
  - construction réussie (`3a7ca1b1`), mais contrôle de QEMU mal découpé (`-m 6176M,slots=10,maxmem=9950M`). L'étape a été relancée entière.

  À chaque correction d'une tâche, nouvelle signature et liste revue mise à jour : les digests intermédiaires restent dans Zot, hors de la liste.
- **Limites et garde-fous** :
  - le privilège ne s'obtient que sous Kata : sans `runtimeClassName`, Pod Security refuse le pod, et Kyverno (`pods-isolation`) le refuserait aussi (cas d'admission de J6) ;
  - la RuntimeClass est un choix du créateur du PipelineRun, signé dans la provenance mais pas imposé par la pipeline : la porte devra l'exiger (option (c) des `internalParameters`) ;
  - `poc-images` peut créer n'importe quel manifeste par digest dans `builds/**`, y compris un référent OCI 1.1. Non mesuré : la porte devrait le refuser, faute de provenance signée par Chains ; elle n'a pas été rejouée sur `builds/sample-app` (J8) ;
  - les deux `.att` (TaskRun `publier` et PipelineRun) sont écrits à 3 s d'intervalle, ce qui reproduit la situation du constat majeur de J4 : une écriture concurrente du tag peut perdre une enveloppe. Ici, aucune ne l'a été (4 enveloppes sur deux passages). L'étape `provenance` exige l'enveloppe du PipelineRun, et un rejeu qui rencontre la course échouerait ;
  - le Dockerfile vient de la plateforme (brique 04), écrit dans le script de la tâche signée, et son empreinte est contrôlée dans le pod ;
  - le dépôt n'en fournit pas. Les `RUN` d'un Dockerfile d'application tourneraient en root dans l'invité, isolés par le bac à sable de BuildKit, et la VM reste la frontière.
- **Contrôles de J6 adaptés** :
  - `politique.sh declencheurs` exige « aucun secret dans `builds` hors `zot-images` » ;
  - `couverture` (horodatage) lit aussi `builds/sample-app`, qui porte le même digest `3a7ca1b1`. Mesuré : 27 enveloppes, 27 bundles, aucun orphelin.

  `bundle`, `signe`, `listee` et `arbre` sont passées dans `commun.sh`, sans changement.
- **Non fait, décision séparée** : le gabarit en service (`declencheurs`) désigne toujours la pipeline d'essai de J6. Le basculer vers `sample-app` changerait les attentes de `declencheurs`, de la porte et du rattrapage.

**Réseau des pods Kata : NetworkPolicy de kube-router** ([`kata.sh`](kata.sh) `reseau`, [`kata-reseau-kube-router.log`](resultats/kata-reseau-kube-router.log), politique de mesure [`kata/sonde-reseau.yaml`](kata/sonde-reseau.yaml)). Suite de J7 : la fenêtre de démarrage relevée en J6 et la trace du test 6, mesurées sur des pods Kata. La prédiction est écrite avant chaque passage. La politique ne sélectionne que les pods de mesure de `builds`, avec une seule sortie, Forgejo, par adresse. Elle est retirée en fin d'étape, règles de kube-router comprises.
- **État de départ** : aucune NetworkPolicy dans `builds` au moment de la mesure. Le mécanisme du test 6 n'existait pas encore pour les constructions ; depuis, l'option 3 a posé `construction-sans-sortie` (voir « Construction sans sortie réseau »).
- **Fenêtre de démarrage sur `sc-build`** (sonde de J6, trois essais runc et trois essais Kata, alternés ; quatre passages : [premier](resultats/kata-reseau-premiere-prediction.log), [deuxième](resultats/kata-reseau-deuxieme-passage.log), [troisième](resultats/kata-reseau-troisieme-passage.log), [quatrième](resultats/kata-reseau-kube-router.log), ce dernier une fois `construction-sans-sortie` posée) : prédiction conforme, **Kata ne ferme pas la fenêtre**.
  - runc : Zot (interdit) joignable à la première tentative, de 0 à 10 ms après le lancement du conteneur, puis fermé à 500 ms, dans 11 essais sur 12 ; dans le douzième (quatrième passage), joignable deux fois, jusqu'à 500 ms, comme en J6 sur `sc-confiance` (510 ms une fois) ;
  - Kata : Zot joignable deux fois, jusqu'à 540 à 570 ms, puis fermé vers 1,1 s, dans les 12 essais. Le conteneur démarre 3 à 4 s après la création du pod, contre 0 à 1 s sous runc.
  - La VM retarde le conteneur, pas la règle : kube-router ne pose celle-ci qu'une fois l'IP du pod publiée.
- **Une fois la règle posée**, sous runc comme sous Kata :
  - Forgejo seul est ouvert ;
  - Zot, le SSH de `sc-stockage`, l'API (nœud et service), le kubelet local et celui de `sc-confiance` sont fermés.

  La sortie de l'invité passe par la veth du pod sur `sc-build`, où kube-router filtre.
- **Trace NFLOG** (groupe 100, lue sur `sc-build`) : chaque SYN refusé y figure avec l'IP du pod, sous Kata comme sous runc. Il y figure **deux fois** :
  - par la règle de journalisation de la chaîne de la politique (préfixe `DROP by policy builds/sonde-reseau-j7`) ;
  - puis par celle de la chaîne du pod, avant le `REJECT`.

  La première prédiction (une ligne par SYN) est démentie et archivée ([`kata-reseau-premiere-prediction.log`](resultats/kata-reseau-premiere-prediction.log)). Chaque règle a son propre plafond (10 par minute, rafale de 10), mais celle de la politique, qui porte le préfixe, est commune à tous les pods qu'elle sélectionne : seule celle du pod lui est propre. Avec plusieurs pods de build sous une même politique, un pod peut donc épuiser la trace nommée des autres. La trace d'une tentative répétée est partielle.
- **Constat majeur : un pod Kata privilégié contourne la NetworkPolicy en usurpant une adresse source.**
  - **Essai** : le pod de mesure a la posture de la tâche `construire` (privilégié, root, donc `NET_ADMIN` dans l'invité). Il ajoute à son `eth0` une adresse inutilisée du sous-réseau des pods de `sc-build` (`10.42.1.250`). Il a été contrôlé avant que cette adresse n'est ni réservée par l'IPAM ni portée par un pod.
  - **Résultat** : avec cette adresse, Zot, le SSH de `sc-stockage`, l'API et le kubelet local sont joignables. Une requête en clair à Zot obtient la réponse de son serveur TLS (`HTTP/1.0 400 Bad Request`) : l'échange passe dans les deux sens.
  - **Témoin** : dans le même pod, avec son IP, Zot reste refusé, avant comme après, et le refus est journalisé.
  - **Cause relevée** : kube-router (k3s v1.35.9) ne rattache un paquet à la chaîne d'un pod que par l'IP de ce pod (`-s <IP>/32` dans `KUBE-ROUTER-FORWARD` et `KUBE-ROUTER-INPUT`, soit 10 règles pour ce pod). Aucune règle ne mentionne l'adresse usurpée : elle ne passe par aucune politique.
  - **Rien d'autre ne l'arrête** : `rp_filter` vaut 2 (mode lâche) sur `cni0`, et aucun filtre ne contrôle l'adresse source sur le pont. L'invité répond à l'ARP de `cni0` pour l'adresse ajoutée, et la réponse revient (SYN-ACK capturés sur la veth du pod).
  - **Aucune trace** : ni dans NFLOG, ni dans les règles. Le test 6 tel qu'il est prévu, qui repose sur NFLOG, ne verrait rien.
  - **Sous Cilium** (option 1b, mesuré le 30/10/2026) : la même usurpation est refusée, motif `INVALID_SOURCE_IP` dans Hubble (voir « Mesure de Cilium »).
  - **Témoins sans `NET_ADMIN`** : un pod Kata restreint (posture de la voie D) et un pod runc restreint (posture de `publier`) ne peuvent ni ajouter l'adresse (`Operation not permitted`), ni y lier une connexion (`Cannot assign requested address`). Le contournement tient au privilège dans l'invité, pas à Kata.
  - **Portée** : dans la voie A, le root de l'invité, ce sont le script de la tâche signée et `buildkitd`.
    - Les `RUN` d'un Dockerfile tournent dans le bac à sable de BuildKit, avec ses capacités par défaut, qui n'ont pas été mesurées ici.
    - Lecture, non mesurée : la voie A fait de la VM la frontière, donc tout code qui sort du bac à sable atteint le root de l'invité, et avec lui ce contournement.
  - **Recherche amont** (30/10/2026) : aucun avis ni aucune issue ne décrit ce contournement. Ont été lus :
    - les avis de sécurité de kube-router, de k3s et de flannel ;
    - les issues de kube-router et de k3s, cherchées avec « spoof », « source IP », « anti-spoofing », « NET_ADMIN » et « ip spoofing » ;
    - celles de flannel, cherchées avec « spoof », « ip spoofing » et « source address ». La n° 961 porte sur le tunnel IPIP depuis des hôtes distants, pas sur les pods.

    Aucune issue n'est ouverte sans accord.
- **Conséquences pour le test 6 (J8)**, constats :
  - une NetworkPolicy s'applique à un pod, pas à une étape, et les étapes d'une tâche partagent le réseau du pod. Or `construire` tire ses sources de Forgejo et ses entrées de Zot, et BuildKit tire l'image de build de Zot pendant l'étape de construction elle-même. « Egress = 0 pendant l'étape de build » n'est donc pas exprimable par une NetworkPolicy sur ce pod ;
  - la fenêtre de démarrage reste ouverte sous Kata ;
  - depuis le root de l'invité, l'usurpation contourne la politique sans trace.

  Options soumises au propriétaire avant J8 : voir le bloc suivant (anti-usurpation côté nœud, voie D pour les images Go, tâche de construction sans sortie).

**Contrôle de sortie de la zone build : options soumises au propriétaire** (30/10/2026, après la mesure du réseau des pods Kata ; rien n'est modifié sur `sc-build`).

Faits sur lesquels elles reposent :
- **Seule sortie pendant la construction** : l'unique `RUN` du Dockerfile de la brique 04 est déclaré `--network=none` (lu dans le Dockerfile). La chaîne d'outils Go qui compile l'application (`go build`) n'a donc pas de réseau dans BuildKit. Aucun code de l'application ne s'exécute pendant la construction. Ce confinement n'est pas mesuré ici. Pendant l'étape `construire`, la seule sortie est celle de `buildkitd`, qui tire l'image de build depuis Zot, et c'est du code de la plateforme.
- **Qui peut usurper** : l'usurpation exige `NET_ADMIN` dans l'espace réseau du pod, dans l'invité (mesuré : refusée sans). En voie A, elle est à la portée du root de l'invité : le script de la tâche, `buildkitd`, ou un code qui sortirait du bac à sable de BuildKit.
- **Pas de seccomp dans l'invité** (mesuré en J7) : un code non privilégié y fait face à tout le noyau de l'invité. Lecture, non mesurée : une élévation au root de l'invité y est plus facile qu'avec seccomp.
- **Le privilège reste nécessaire ailleurs** : mock exige root, et l'ADR 0001 prévoit Kata privilégié pour mock, sbuild et les images. La voie D ne couvre que les images Go.
- **Aucune NetworkPolicy dans `builds`** au moment de la mesure. Depuis, l'option 3 a posé `construction-sans-sortie`.

Options :
1. **Voie A avec anti-usurpation côté nœud.** Elle traite l'usurpation pour toute la zone build, mock et sbuild compris.
   - **1a. kube-router amont, v2.10.0 ou plus, en seul contrôleur de politiques, flannel conservé.**
     - **Versions** : k3s v1.35.9 embarque kube-router v2.6.3-k3s1 (lu dans son `go.mod`), et c'est encore le cas en v1.36.5 et en v1.37.1. La dernière version amont est la v2.11.2 du 22/10/2026.
     - **Le mécanisme** : la v2.10.0 ajoute `--netpol-default-deny` (notes de version, guide et page de dépannage, lus au tag v2.11.2). Des REJECT de rattrapage, dans `KUBE-NWPLCY-TAIL`, refusent tout trafic depuis ou vers le CIDR des pods du nœud quand l'IP en cause n'est pas dans l'ipset des pods déjà programmés.
     - **Condition** : le `podCIDRs` du nœud doit être renseigné. Relu : `10.42.1.0/24` pour `sc-build`.
     - **Annoncé par la documentation** : la fenêtre de démarrage se ferme (échec fermé au lieu d'ouvert).
     - **Lecture du mécanisme, non mesurée** : une adresse inutilisée du CIDR local (`10.42.1.250`) serait refusée, puisqu'elle est absente de l'ipset. En revanche, ne seraient pas couverts :
       - l'IP d'un autre pod du nœud, dont la chaîne s'appliquerait ;
       - une source hors du CIDR local (autre nœud, adresse externe), que `rp_filter` en mode lâche laisse sortir, en sens unique puisque la réponse ne revient pas. Passer `rp_filter` en strict sur `cni0` serait un changement système, à mesurer.
     - **Coûts** :
       - **doc 04** (évaluation du 30/10/2026, mêmes journaux que Cilium) : « À surveiller ». Bus factor de 2 : deux fusionneurs font 96 des 100 dernières fusions, et les employeurs ne sont pas vérifiables, hormis Mirantis. L'image est signée sans clé et vérifiée, avec une identité relevée dans le workflow au tag. La provenance SLSA v1 des binaires est vérifiée, mais l'image, celle qu'on déploierait, n'a **aucune provenance**, comme celles de Cilium ;
       - k3s avec `--disable-network-policy`, plus un DaemonSet kube-router en pare-feu seul (`daemonset/kube-router-firewall-daemonset.yaml` dans son dépôt), dont l'image est copiée dans Zot et vérifiée ;
       - réglages du server k3s modifiés, puis rejeu de J1 à J7 ;
       - le comportement de NFLOG est à revérifier sur la version amont, et la piste à mesurer avec `kata.sh reseau`.
   - **1b. Contrôleur réseau qui vérifie l'adresse source.**
     - **Cilium** ([documentation stable, annotations de pod](https://docs.cilium.io/en/stable/network/pod-annotations/)) : par défaut, Cilium vérifie que les paquets d'un pod portent l'IP du pod comme source, ce qui empêche l'usurpation. Le désactiver demande deux annotations : une sur l'espace de noms, posée par un administrateur, puis une sur le pod. Son [guide Kata](https://docs.cilium.io/en/stable/network/kubernetes/kata/) signale des limites de MTU et demande `socketLB.hostNamespaceOnly=true`. Deux fonctions documentées serviraient le test 6 :
       - le filtrage de sortie par nom (`toFQDNs`), avec une règle DNS et le proxy DNS de l'agent ([doc](https://docs.cilium.io/en/stable/security/dns/)) ;
       - les flux refusés et leur motif dans Hubble (`hubble observe --verdict DROPPED`, « Policy denied », [doc](https://docs.cilium.io/en/stable/observability/hubble/hubble-cli/)).
     - **Calico** ([référence de FelixConfiguration, 3.33](https://docs.tigera.io/calico/latest/reference/resources/felixconfig)) : `workloadSourceSpoofing` décide si un pod peut envoyer depuis une autre adresse grâce à l'annotation `allowedSourcePrefixes`. Il vaut `Disabled` par défaut. Le refus par défaut d'une source usurpée n'est écrit explicitement que dans une page en projet ([tigera/docs#2613](https://github.com/tigera/docs/pull/2613)).
     - **Santé** :
       - **Cilium**, évalué au doc 04 le 30/10/2026 ([`sante-reseau.sh`](sante-reseau.sh), [relevés](resultats/sante-reseau-releves.log), [signatures](resultats/sante-reseau-signatures.log)) : « À surveiller, chemin critique ».
         - Manquent : toute provenance pour les images, et un Scorecard de 6,0, exactement au seuil. Isovalent (Cisco) est l'éditeur dominant.
         - Images `cilium` et `operator-generic` v1.20.4 signées sans clé et vérifiées par cosign avec l'identité documentée ; l'identité d'un autre tag est refusée (témoin).
         - Activité : 1 685 commits en 90 jours, 16 fusionneurs, DCO, 44 avis publiés.
       - **Calico** n'est pas évalué. Relevé préliminaire, qui n'est pas un verdict : Scorecard 6,2, Signed-Releases 0, v3.33.0 du 01/10/2026.
       - **flannel**, qu'embarque k3s v1.35.9 (v0.28.4), n'est pas évalué non plus (Scorecard 8,7).
     - **Coûts** :
       - plan de sortie inscrit au doc 04 (§6), le projet étant « À surveiller » sur le chemin critique ;
       - k3s avec `--flannel-backend=none` et `--disable-network-policy` (documentation de k3s), donc réinstallation du réseau du cluster et rejeu de J1 à J7 ;
       - à mesurer avec le même essai (`kata.sh reseau`) : la compatibilité avec le réseau de Kata et le refus de l'usurpation depuis un invité ;
       - la trace du test 6 change (journaux de flux du contrôleur au lieu de NFLOG).
   - **1c. Règle maison sur le nœud** : n'accepter sur la veth d'un pod que l'adresse de ce pod (nftables ou iptables sur `sc-build`), tenue à jour par un contrôleur à écrire. C'est de l'outillage maison, comme celui écarté en J4, et un changement système sur `sc-build`.
2. **Voie D pour les images Go.**
   - **Mesuré** : sans `NET_ADMIN`, l'usurpation est refusée (pod Kata restreint), et la compilation tourne sous `unshare -n`, sans réseau.
   - **Reste**, en lecture non mesurée : une élévation dans l'invité, qui n'a pas de seccomp, rouvrirait l'usurpation.
   - **Coûts déjà consignés** (voir « Ce que coûterait la voie D ») :
     - crane est hors du doc 04 ;
     - Go seulement, et du code de plateforme à maintenir ;
     - elle remet en cause l'issue de la grille B de l'ADR 0000, qui est figée ;
     - le digest diffère de `3a7ca1b1` (`c9244139`), donc le critère de J7 serait à changer.
   - **Limite** : elle ne règle rien pour mock et sbuild, qui restent privilégiés. L'option 1 resterait nécessaire pour eux.
3. **Tâche de construction sans sortie, dans les deux cas**, pour que le test 6 porte sur quelque chose. **Retenue par le propriétaire (30/10/2026) et faite** : voir « Construction sans sortie réseau ».
   - **Principe** : une tâche runc restreinte tire dans le workspace les sources, la fermeture, `web/dist` et l'image de build (en layout OCI). La tâche `construire` n'a alors plus aucune sortie, et une NetworkPolicy deny-all peut viser ses seuls pods. Le label à sélectionner était à vérifier : c'est `tekton.dev/task`, fixé par le contrôleur au nom de la tâche signée (mesuré).
   - **Ce que dit la documentation** : BuildKit v0.34.1 accepte une image de build fournie en layout OCI local (`--oci-layout builder=<répertoire>` et `--opt context:builder=oci-layout://builder@sha256:…`, lu dans `docs/reference/buildctl.md` au tag).
   - **Mesuré** : le digest reste `3a7ca1b1`, comme prédit (l'image finale part de `scratch` et ne contient que le binaire).
   - **Fenêtre de démarrage** : relevé, l'étape `construire` démarre 2 s après le premier conteneur du pod (horodatages à la seconde, donc entre 1 et 3 s, face à une fenêtre qui se ferme vers 1,1 s : non tranché).
   - **Coûts** : aucun changement système, seulement les tâches resignées, la liste revue et la pipeline. La trace du test 6 reste NFLOG (deux lignes par refus, plafond partagé par politique).
   - **Limite** : seule, elle ne suffit pas en voie A, car une politique deny-all reste contournable par usurpation depuis le root de l'invité.

**Construction sans sortie réseau** (option 3 du contrôle de sortie, choix du propriétaire du 30/10/2026). Fichiers : politique [`construction-sans-sortie.yaml`](politique/construction-sans-sortie.yaml), tâches [`preparer-entrees`](politique/taches/preparer-entrees.yaml) et [`construire-image`](politique/taches/construire-image.yaml), pipeline [`sample-app`](politique/taches/sample-app.yaml). Journaux, sous kube-router : [`buildkit-sans_reseau-kube-router.log`](resultats/buildkit-sans_reseau-kube-router.log), [`construction-taches-kube-router.log`](resultats/construction-taches-kube-router.log), [`construction-construire-kube-router.log`](resultats/construction-construire-kube-router.log), [`construction-provenance-kube-router.log`](resultats/construction-provenance-kube-router.log). Les journaux sans suffixe montrent le rejeu sous Cilium. Prédictions écrites avant, toutes conformes.
- **Mesure autonome** (`buildkit.sh sans_reseau`), dans des pods Kata privilégiés, sous la vraie politique :
  - **témoins**, sortie testée 4 s après le lancement : sans le label, Zot et Forgejo sont joignables ; avec `tekton.dev/task=construire-image`, les deux sont refusés ;
  - **layout OCI de l'image de build**, produit par `oras cp --to-oci-layout` : index qui désigne `d50ae575`, 3 blobs, 73 Mo, sha256 de chaque blob contrôlé dans le pod ;
  - **image de build tirée de Zot** (`docker-image://`) : échec, la résolution DNS étant refusée (la politique coupe aussi le DNS) ;
  - **image de build en layout OCI** (`oci-layout://`) : réussite en 29 s, image **`3a7ca1b1`**, binaire `e3749c68`.
- **Mise en œuvre** :
  - **`preparer-entrees`** (pod runc restreint) : elle tire dans le workspace les sources de Forgejo, la fermeture, `web/dist` et l'image de build en layout OCI, puis déclare ces entrées à Chains.
  - **`construire-image`** (pod Kata privilégié) : aucune de ses étapes ne joint le réseau. Elle contrôle l'index du layout et le sha256 de chaque blob, et BuildKit n'a aucune configuration de registre.
  - **`publier-image`** : inchangée (`d21931f3`).
  - **Liste revue** : `construire-image` `403ccbd8` remplace `c7e8b275`, qui en est retirée ; `preparer-entrees` `2070d601` y entre. Une première signature par `SIGNER=1` avait aussi resigné `publier-image`, dont le gabarit n'a pas changé ; sa signature versionnée est restaurée.
- **Sélection des pods** :
  - La politique sélectionne le label `tekton.dev/task`. Le contrôleur de Tekton v1.15.5 le réécrit au nom de la tâche résolue, celui du bundle signé : c'est lu dans `taskrun.go`, puis mesuré.
    - Le créateur impose `tekton.dev/task: autre` par `taskRunSpecs[].metadata` : le pod garde `construire-image`.
    - Un autre label du créateur, lui, arrive bien jusqu'au pod.
  - À l'inverse, `taskRunSpecs[].metadata` l'emporte sur `tekton.dev/pipelineTask` (lu dans `pipelinerun.go`, non mesuré) : ce label n'est pas un sélecteur sûr.
  - **Invariant d'union**, contrôlé par `construction.sh` : une seule politique sélectionne les pods de `construire-image`, et aucune politique de `builds` n'autorise de trafic. Les NetworkPolicy s'additionnent : une règle permissive sur un label que le créateur peut poser rouvrirait la sortie.
- **Résultats** du PipelineRun (gabarit en service, commit `6391fd43`) : réussi.
  - Trusted Resources vérifie la pipeline et les trois tâches ; Chains les signe.
  - QEMU tourne en `-smp 3 -m 6176M`.
  - L'image est **`3a7ca1b1`**, l'arbre `30e808ff`, et le push est fait par `poc-images`.
  - L'étape `construire` démarre 2 s après le premier conteneur du pod. Les horodatages étant à la seconde, l'écart réel est compris entre 1 et 3 s, alors que la fenêtre mesurée se ferme vers 1,1 s : la mesure ne permet pas de conclure que l'étape démarre après la fenêtre (prédiction non tranchée). Les premiers conteneurs du pod exécutent le code de Tekton.
- **Témoins** :
  - **Ancienne pipeline** : `construire-image` `c7e8b275` est relue dans l'historique git au commit `b77ff6b`, et son bundle est identique. Elle échoue fermée à l'étape `sources` (« Could not resolve host ») ; `publier` n'est jamais lancée et `poc-images` n'écrit rien.
  - **Sans Kata** : `preparer` réussit, le pod de construction est refusé par Pod Security, et rien n'est poussé.
- **Provenance** : 8 enveloppes valides, aucune perdue sur le tag `.att`, dont une pour le PipelineRun.
  - `resolvedDependencies` contient le commit, la fermeture, `web/dist` et l'image de build, désormais déclarés par `preparer-entrees`, ainsi que les trois tâches.
  - `runtimeClassName: kata` est signé, et une autre clé est refusée.
- **Limites** :
  - **Usurpation** : la politique ne tient pas face à l'usurpation d'adresse depuis le root de l'invité (mesuré, « Réseau des pods Kata »). Or `construire` reste privilégiée. L'option 1 (anti-usurpation côté nœud) reste donc ouverte.
  - **Confiance dans le workspace** (PVC local-path, en 0777 sur `sc-build`, constat de J3) : il est écrit par la tâche signée du même PipelineRun. La construction contrôle le layout de l'image de build, pas les sources ni la fermeture, que git et oras ont vérifiées à l'entrée.
  - **Sorties des autres tâches** : `preparer-entrees` et `publier-image` gardent leurs sorties, car aucune politique ne les sélectionne.
  - **Nom dans le journal** : BuildKit y désigne l'image de build comme `docker.io/library/builder@sha256:…`. C'est le nom local du contexte, sans effet sur l'image.
  - **Enveloppes accumulées et liste revue** :
    - `builds/sample-app@3a7ca1b1` porte 8 enveloppes, dont les 4 premières citent `construire-image` `c7e8b275`, retirée de la liste revue. La construction étant reproductible, chaque version de tâche ajoute ses enveloppes au même digest, et Zot interdit leur suppression.
    - **Lu dans Conforma v1.0.28** (`policy/release/lib/attestations.rego` au commit `ebd3fbd2` de la porte) : les règles, `trusted_task` comprise, n'évaluent que la dernière attestation de PipelineRun en SLSA v1, choisie par sa date de fin. Il faut en outre que toutes ces attestations portent une date. Les anciennes enveloppes ne devraient donc pas faire refuser `3a7ca1b1` tant que la plus récente vient de la version en service.
    - Non mesuré : la porte n'a pas été rejouée sur `builds/sample-app` (J8).

**Option 1b : plan de mesure de Cilium** (préparé le 30/10/2026 à la demande du propriétaire, puis accordé et mesuré le même jour : voir « Mesure de Cilium » ; les écarts au plan y sont consignés).

Vérifié pour préparer le plan, sans rien installer :
- **Chart** : `quay.io/cilium/charts/cilium:1.20.4` en OCI (manifeste `712e1f65`). Sa couche `505abff8` est le digest publié dans `helm.cilium.io/index.yaml`. Il est signé sans clé et vérifié par cosign avec l'identité relevée, `cilium/cilium/.github/workflows/release.yaml@refs/heads/main`. Ce workflow est lancé depuis `main` et non depuis le tag : l'identité est moins liée à la version que celle des images.
- **Images**, épinglées par digest dans le chart (`useDigest: true`) :
  - `cilium` `20fe92e4` (amd64 `fa56fecd`, 256 Mo compressés) et `operator-generic` `7a7a3489` (amd64 `77a9b437`, 36 Mo) : signatures vérifiées au doc 04 ;
  - `cilium-envoy` `547ab45f` (amd64 `401bc8f7`, 78 Mo) : signée par `cilium/proxy/.github/workflows/build-envoy-images-release-base.yaml@refs/heads/v1.39`, identité relevée par un refus volontaire. Elle vient du dépôt `cilium/proxy`, que le doc 04 n'évalue pas ;
  - ces digests sont ceux des **index** multi-plateformes (amd64 et arm64), et le chart y fait référence (`…:v1.20.4@sha256:20fe92e4…`). Une archive qui ne contient que le manifeste amd64 ne satisfait donc pas cette référence ;
  - Hubble relay et UI, clustermesh et certgen ne servent pas.
- **k3s** : le server doit être lancé avec `--flannel-backend=none` et `--disable-network-policy` (guide Cilium pour k3s, documentation de k3s).
  - Chemins CNI de k3s, relevés sur `sc-build` : `/var/lib/rancher/k3s/data/cni` et `/var/lib/rancher/k3s/agent/etc/cni/net.d`. Ils diffèrent des défauts du chart (`/opt/cni/bin`, `/etc/cni/net.d`).
  - Le bpffs est monté, et le noyau est en 6.12.113.
  - Le contrôleur Helm de k3s documente `chartContent` (chart en base64) et `bootstrap: true` (chart nécessaire au démarrage). L'image `klipper-helm` v0.13.3 fait partie des images airgap de k3s.
- **IPAM `kubernetes`** : Cilium reprend les `podCIDRs` alloués par k3s (documentation). Les adresses ne changent pas (`10.42.1.0/24` pour `sc-build`), et les scripts en dépendent.
- **Kyverno** : le webhook des ressources exclut `kube-system` (`NotIn ["kube-system"]`, relu dans le cluster), et `resourceFilters` aussi. Les pods de Cilium (privilégiés, `hostNetwork`, `hostPath`) ne passent donc pas par `pods-isolation`, et leur recréation après J6 ne sera pas refusée. Corollaire : tout pod privilégié de `kube-system` échappe à Kyverno, et seul le RBAC de J6 garde cet espace.
- **`toFQDNs` exige le proxy L7** : le proxy DNS ne démarre pas si `EnableL7Proxy` est faux (`pkg/fqdn/bootstrap/dns_proxy.go` au tag v1.20.4).

Choix proposés (valeurs du chart) :
- **Adresses et API** :
  - `ipam.mode=kubernetes` ;
  - `k8sServiceHost=192.168.161.11` et `k8sServicePort=6443`, pour joindre l'API sans dépendre du service.
- **kube-proxy de k3s conservé** (`kubeProxyReplacement=false`). `socketLB` reste désactivé, comme par défaut, donc la limite que signale le guide Kata ne s'applique pas.
- **Routage natif** : `routingMode=native`, `autoDirectNodeRoutes=true`, `ipv4NativeRoutingCIDR=10.42.0.0/16`. Les trois VM sont sur un même segment L2. Sans tunnel, la MTU de route n'est pas réduite ; or c'est cette MTU que le guide Kata dit ignorée dans l'invité.
- **CNI** : `cni.binPath` et `cni.confPath` pointent sur les chemins de k3s.
- **Application des politiques** : `policyEnforcementMode=default`. Comme avec kube-router, un pod qu'aucune politique ne sélectionne n'est pas filtré.
- **Placement** :
  - `operator.replicas=1`, en zone de confiance ;
  - l'agent et Envoy en DaemonSet sur les trois nœuds (tolérances par défaut).
- **Traces** : Hubble activé dans l'agent, sans relais ni interface. `hubble observe --verdict DROPPED` remplace NFLOG.
- **L7 coupé pour la mesure** : `l7Proxy=false` et `envoy.enabled=false`. Il n'y a alors ni Envoy, ni `toFQDNs` (lu dans le code), et les politiques restent par adresse, ce qui suffit au test 6. Les garder exigerait d'abord d'évaluer `cilium/proxy` au doc 04 (règle du propriétaire). Ce serait une étape à part, sur sa décision.
- **Digests** : les valeurs surchargent les digests d'index par ceux des manifestes amd64 (`image.digest`, `operator.image.genericDigest`). La signature est vérifiée sur l'index, qui liste ces manifestes.

Installation dès J1, avant que les nœuds soient prêts :
- **Sur l'hôte** :
  - le chart et les images amd64 sont téléchargés par digest ;
  - leurs signatures sont vérifiées par cosign, avec les identités relevées et des témoins ;
  - les images amd64 (`cilium`, `operator-generic`, soit 292 Mo compressés) sont mises en archives OCI, qui conservent le digest du manifeste amd64, celui que référencent les valeurs.
- **Sur chaque nœud** : les archives vont dans `/var/lib/rancher/k3s/agent/images`, comme les images airgap de k3s.
- **Sur `sc-confiance`** :
  - un HelmChart `cilium` dans `/var/lib/rancher/k3s/server/manifests` : chart en base64, valeurs versionnées, `bootstrap: true` ;
  - les options du server dans `k3s/sc-confiance.yaml`.
- **À mesurer au point d'arrêt après J1** : que le containerd de k3s importe l'archive OCI en gardant le digest du manifeste. Repli : tirer les images d'un miroir dans Zot après J2, en déplaçant le contrôle « nœuds prêts ».

Changements système soumis à accord :
1. **Rejeu complet depuis zéro** (`rejeu.sh` : `vm.sh detruire` puis `creer`, comme le rejeu de J1 à J6 du 30/10/2026), avec le réseau Cilium. Il fait aussi le « rejeu complet avec J7 » en attente. Il réapplique les changements déjà accordés de J1 à J7 (installation de Kata depuis l'archive attestée, exemption Pod Security, compte `poc-images`, etc.).
2. **Dans les VM** :
   - k3s tourne sans flannel ni contrôleur de NetworkPolicy ;
   - Cilium installe ses programmes eBPF, les interfaces `cilium_host` et `cilium_net`, des règles iptables de masquage et son binaire CNI ;
   - des DaemonSets privilégiés tournent dans `kube-system` sur les trois nœuds, zone de confiance comprise, et l'opérateur sur `sc-confiance`.
3. **Sur l'hôte** : environ 300 Mo téléchargés (images amd64 compressées et chart) dans `…/08/telechargements/cilium`.

Déroulement :
- **Préalable sur l'hôte, avant tout démontage** : téléchargement, signatures et archives. Une archive mal formée doit apparaître avant la destruction des VM.
- **Point d'arrêt après J1** : `rejeu.sh` gagne une option pour s'arrêter après une étape et reprendre à une autre. On rejoue jusqu'à `k3s`, puis on contrôle Cilium : nœuds prêts, digests importés, binaire `hubble` présent dans l'image de l'agent, adresses des pods. Ensuite seulement, on reprend à J2. Un échec de Cilium coûte ainsi J1, pas J1 à J7.

**Retour arrière** : un rejeu avec le réseau actuel, dont le choix reste possible par une variable. Compter environ une heure.

Adaptations des scripts, avant le rejeu. Une variable `RESEAU` (`flannel` ou `cilium`) est ajoutée à `commun.sh` ; elle vaut `flannel` tant que la mesure n'est pas faite.
- `k3s.sh` : options du server, archives et HelmChart, attente que Cilium soit prêt ;
- `controles.sh` : état de Cilium au lieu du nombre de règles KUBE-ROUTER ;
- `openbao.sh` (J3) : trace du refus vers OpenBao par Hubble au lieu de NFLOG ;
- `politique.sh` (J6, rattrapage) : la fenêtre est mesurée et rapportée, au lieu d'être affirmée ;
- `kata.sh reseau` : Hubble au lieu de NFLOG et des règles iptables, `cni0` remplacé, même essai d'usurpation. L'adresse inutilisée se contrôle dans les endpoints de Cilium, plus dans `/var/lib/cni/networks/cbr0` (IPAM host-local de flannel) ;
- `commun.sh` : commentaire sur le délai d'entrée de kube-router.

Mesures, prédictions écrites avant :
- **J1** :
  - nœuds prêts et Cilium prêt sur les trois nœuds ;
  - pods de `sc-build` en `10.42.1.0/24` ;
  - mémoire des agents relevée.
- **J2 à J7** : tous les contrôles repassent, construction sans sortie comprise.
- **`kata.sh reseau`** :
  - la politique s'applique aux pods Kata, et les refus apparaissent dans Hubble avec l'IP du pod et le motif ;
  - **l'usurpation de `10.42.1.250` est refusée** par la vérification de l'adresse source, avec son motif dans Hubble ;
  - témoin : avec l'IP du pod, Zot est refusé ;
  - fenêtre de démarrage : la prédiction sera écrite après lecture du code de `cilium-cni`. L'attente de la première régénération n'est attestée que par une source secondaire.
- **Risques** : la MTU et la compatibilité sous Kata (guide officiel). Si l'usurpation passe, ce sera un constat.

**Durée estimée** : une demi-journée d'adaptations, environ une heure de rejeu (1 784 s pour J1 à J6, plus J7), une demi-journée de mesures. Le budget de la brique reste loin du seuil de 11 pw.

**Mesure de Cilium** (option 1b, plan accordé par le propriétaire le 30/10/2026). Fichiers : [`cilium.sh`](cilium.sh), [`cilium/valeurs.yaml`](cilium/valeurs.yaml). Journaux : [`cilium-telecharger.log`](resultats/cilium-telecharger.log), [`cilium-verifier.log`](resultats/cilium-verifier.log), [`cilium-appliquer.log`](resultats/cilium-appliquer.log), rejeu en cinq morceaux (`rejeu-j1-j7-cilium*.log`). Le cluster a été recréé de zéro avec Cilium 1.20.4 à la place de flannel et de kube-router, et J1 à J7 ont été rejoués : c'est aussi le premier rejeu complet avec J7. Prédictions écrites avant.
- **Préalable sur l'hôte**, conforme : chart vérifié (témoin refusé), images vérifiées sur leur index (témoin refusé), archives OCI amd64 (245 et 36 Mo), HelmChart rendu.
- **J1, point d'arrêt** :
  - **Premier passage en échec**, archivé ([diagnostic](resultats/cilium-premier-passage-diagnostic.log)) : nœud `NotReady`, « cni plugin not initialized ». Avec `flannel-backend: none`, k3s n'écrit aucune section CNI dans la configuration de containerd, qui lit alors ses chemins par défaut. Les chemins de k3s, relevés sur le cluster flannel et passés au chart, étaient donc faux ; les défauts du chart conviennent.
  - **Second passage**, prédiction conforme :
    - démontage, VM et k3s en 117 s ; trois nœuds prêts ;
    - agents 3/3, opérateur sur `sc-confiance` ;
    - images aux digests amd64, importées des archives, sans aucun tirage ;
    - `podCIDRs` repris de k3s, `cilium-dbg status` OK, ni flannel ni kube-router ;
    - `hubble` v1.20.4 dans l'agent, 185 à 191 Mo de RSS par agent.
- **J2 à J7** : tous les contrôles repassent, après quatre ajustements, chacun mesuré et archivé.
  - **J3** : sous Cilium, un refus est une perte de paquet et non un REJECT. Chaque essai du pod réseau attendait le délai du client d'OpenBao, et le pod ne finissait pas en 120 s. Le délai du client est borné à 2 s. OpenBao reste injoignable, et les refus sont visibles dans Hubble (`POLICY_DENIED INGRESS`).
  - **J5, constat** : par défaut, les sélecteurs CIDR de Cilium ne désignent ni les pods ni les nœuds (`Documentation/security/policy/layer3.rst` au tag). Or Zot et Forgejo tournent sur l'hôte de `sc-stockage`, si bien que la NetworkPolicy du job d'horodatage refusait Zot ([journal](resultats/tsa-horodater-cilium-sans-cidr-nodes.log)). Le réglage `policyCIDRMatchMode: nodes`, marqué bêta, a été appliqué au cluster par `cilium.sh appliquer`, et J5 repasse.
  - **J7, Kata** : l'agent Cilium, pod de DaemonSet, bloquait le contrôle « aucun pod sur `sc-build` » avant le redémarrage de k3s-agent. Les pods de DaemonSet en sont désormais exclus.
  - **J7, exemption** : juste après le redémarrage du server, le kubelet ne servait pas encore `exec`, et l'état vide d'OpenBao passait pour « scellé » ([premier passage](resultats/kata-exemption-cilium-premier-passage.log)). L'exemption a été retirée puis reposée, avec une attente de `exec`, qui a répondu au troisième essai.
- **Résultats** :
  - **Fenêtre de démarrage : aucune.** En J6 (rattrapage), Zot n'est jamais joignable ; dans `kata.sh reseau`, pas une fois sur les 6 essais, runc et Kata ([journal](resultats/kata-reseau.log)). La prédiction, écrite d'après le code, est conforme : le CNI attend la première régénération de l'endpoint, labels du pod compris.
  - **Usurpation refusée** : avec `10.42.1.250`, Zot, SSH, l'API et le kubelet sont injoignables, sans aucune réponse. Hubble donne `INVALID_SOURCE_IP` pour les 15 SYN, et la capture ne montre aucun SYN-ACK. Témoin : avec l'IP du pod, Zot est refusé.
  - **Trace du test 6** : Hubble donne chaque refus avec l'IP du pod, le port, le motif (`POLICY_DENIED`) et le sens, sans plafond. Chaque SYN refusé par la politique y figure deux fois au même instant ; la cause n'en est pas établie.
  - **Adresses de service** : l'API jointe par son adresse de service est autorisée, comme par l'adresse du nœud. Cilium traduit donc l'adresse de service avant d'appliquer la politique.
  - **Construction sans sortie** : même image `3a7ca1b1` et mêmes témoins. Sous Cilium, l'ancienne tâche échoue sur un délai DNS dépassé plutôt que sur un refus.
  - **Durées** : J1 117 s, J2 51 s, J4 146 s, J6 1 484 s, et 945 s pour J7 après Kata. J3, J5 et le début de J7 ont été rejoués à la main après ajustement.
- **Limites et points ouverts** :
  - `policyCIDRMatchMode: nodes` est une fonction bêta ;
  - le L7 est coupé : ni `toFQDNs` ni politique L7, qui exigeraient d'évaluer `cilium/proxy` au doc 04 ;
  - Cilium reste « À surveiller » au doc 04 : aucune provenance pour ses images, Scorecard au seuil ;
  - les agents Cilium, privilégiés et en `hostNetwork`, tournent dans `kube-system`, que Kyverno ne contrôle pas (constat déjà consigné) ;
  - une perte de paquet allonge les délais des clients refusés (J3) ;
  - la mesure est ponctuelle : ni tenue dans la durée, ni redémarrage des VM sous Cilium (`redemarrer.sh` non rejoué) ;
  - `RESEAU` vaut toujours `flannel` par défaut dans `k3s.sh` et `rejeu.sh`, alors que le cluster actuel tourne sous Cilium. Garder Cilium ou revenir à flannel est une décision du propriétaire.

**Rejeu** : J7 est branché dans `rejeu.sh` (vérification, installation, essais, exemption, puis cas d'admission rejoués ; BuildKit : image, essais et mesure après l'exemption ; voies D et A ; construction ; réseau) et rejoué sous Cilium le 30/10/2026, en cinq morceaux (voir « Mesure de Cilium »). `sonde_kyverno` et `passage_ok` sont passées de `redemarrer.sh` à `commun.sh` pour servir à `kata.sh exemption`, qui les a exercées ; `redemarrer.sh` a été rejoué ensuite (30/10/2026, [`redemarrage-vm.log`](resultats/redemarrage-vm.log)) : arrêt 6 s, démarrage 9 s, nœuds prêts en 17 s, tous les contrôles de J1 à J7 repassent, et l'exemption est relue par kube-apiserver après le redémarrage des VM.

**Suites de J7** :
- ~~fenêtre de kube-router et trace NFLOG, sur un pod Kata~~ : mesurées (voir « Réseau des pods Kata ») ; ouvertes à la place : le contrôle de sortie de la zone build face à l'usurpation d'adresse et la conception du test 6, trois options soumises au propriétaire (voir « Contrôle de sortie de la zone build »). L'option 3 est faite (voir « Construction sans sortie réseau »). Pour l'option 1, Cilium et kube-router amont ont été évalués au doc 04 le 30/10/2026, « À surveiller » tous deux. Cilium a ensuite été mesuré sur accord du propriétaire (voir « Mesure de Cilium ») : aucune fenêtre, usurpation refusée. Garder Cilium ou revenir à flannel est sa décision ;
- canal des `internalParameters`, avec la mesure de la construction : `runtimeClassName` signé dans la provenance (option (c)) ;
- bascule du gabarit en service vers la pipeline `sample-app` (décision du propriétaire) ;
- ~~rejeu complet avec J7~~ : fait sous Cilium le 30/10/2026, en cinq morceaux et avec quatre ajustements (voir « Mesure de Cilium ») ; pas encore rejoué d'un seul tenant.

## Jalon J6 : politique (29 et 30/10/2026)

Accord du propriétaire : « continue », après le compactage demandé avant J6 (29/10/2026). Installations validées sur l'hôte : `tkn` v0.46.2 (Trusted Resources) et tekton-lint 1.2.4 avec un verrou npm. Rejeu : `mise run confiance:politique -- image installer parite taches admission chains declencheurs restreint horodatage`, puis le test 5 (`EL_NS=declencheurs JOURNAL=politique JALON=J6 mise run confiance:tekton -- essais_webhook`), puis `mise run confiance:politique -- porte rattrapage droits posture` (`rattrapage` juge à la porte la provenance de chacun de ses deux chemins : la porte doit être installée). Le test 5 suspend le CronJob de rattrapage pendant l'essai, s'il existe : sinon, celui-ci recréerait le PipelineRun de la tête de `main` après la purge, avant la livraison réelle du cas A. Journaux : `resultats/politique-<étape>.log`. Rejeu complet de J1 à J6 : `mise run confiance:rejeu` (voir après le tableau).

| Étape | Durée | Résultat |
|---|---|---|
| `image` | 87 s (copie depuis le cache OCI) | Tag v1.19.2 → commit `e63308f1…`, signature du commit vérifiée par GitHub. **5 index multi-plateformes** (kyverno, kyvernopre, background-, cleanup-, reports-controller) : même digest sur `reg.kyverno.io` et `ghcr.io` ; **signature sans clé vérifiée par identité exacte** (workflow `release.yaml` au tag, commit du tag, déclencheur `push`, dépôt `kyverno/kyverno`) ; une identité voisine (tag v1.19.1) est refusée. Index et **bundles de signature** (dépôt séparé `ghcr.io/kyverno/signatures`, étiquette de repli `sha256-<digest>`) copiés dans Zot, puis **signatures revérifiées sur la copie de Zot**, sans dépôt séparé |
| `installer` | 17 s en première installation, jusqu'aux 4 contrôleurs prêts (rejeu de J1 à J6) ; 5 s en réapplication | `install.yaml` épinglé (`4f785937…`) : **identique à `config/install-latest-testing.yaml` du commit du tag**, `latest` remplacé par `v1.19.2` (63 étiquettes de version, 5 images). Réécrit vers Zot par digest, 4 contrôleurs sur `sc-confiance`, CA du PoC seule (`SSL_CERT_FILE`) ; **5 images, toutes tirées de Zot** (`imageID`). Webhooks de ressources en `failurePolicy: Fail` (la règle d'une `ImageValidatingPolicy` y est servie : `ivpol.validate.kyverno.svc-fail`) ; webhooks `verify` (mutation) et `ttl` en `Ignore` |
| `parite` | 216 s (dont la préparation des 17 cas du banc : images, signatures et attestations poussées dans Zot) | C-2, voir ci-dessous |
| `taches` | 29 s ; rejouée en 25 s après l'ajout du `stepTemplate`, sous les règles d'admission ([`politique-taches-sous-admission.log`](resultats/politique-taches-sous-admission.log)) | Trusted Resources, voir ci-dessous |
| `admission` | 28 s, puis 29 s avec l'espace `porte` (37 cas), puis 28 s avec `builds` en `warn` et `audit` | Règles d'admission de Kyverno, voir ci-dessous |
| `chains` | 2 s | Identifiants Zot de Chains sortis de `builds`, voir ci-dessous |
| `declencheurs` | 27 s, puis 26 s (tâche avec `stepTemplate`), puis 26 s (tâche signée versionnée) | Tâche et pipeline de J4 en bundles signés ; EventListener dans `declencheurs`, voir ci-dessous |
| `restreint` | 41 s (dont cinq exécutions d'essai), puis 42 s deux fois de suite avec `enforce` permanent, puis 75 s sérialisée (signature de Chains attendue après chaque exécution) | Pod Security `restricted` des pods de build, voir ci-dessous |
| `horodatage` | 152 s, puis 193 s à la seconde exécution (trois passages du CronJob, un par minute), puis 141 s avec l'invariant apparié par signature (un premier passage arrêté par SIGPIPE, voir les constats) | Horodatage automatique par réconciliation périodique, voir ci-dessous |
| `rattrapage` | 491 s (dont 150 s d'attente imposée, cinq passages du CronJob de rattrapage et un de l'horodatage, un par minute), puis 474 s en `slsa-tekton` avec deux jugements de la porte (un premier passage arrêté sur l'invariant d'horodatage : enveloppe perdue, voir J4) | Rattrapage des webhooks perdus, voir ci-dessous |
| `essais_webhook` (de `tekton.sh`) | 38 s, puis 42 s rejoué avant `rattrapage`, puis 51 s après `restreint` (un premier passage arrêté, voir le constat d'adoption), puis 50 s en `slsa-tekton` | Test 5 rejoué sous politique, voir ci-dessous |
| `porte` | 82 s (dont trois PipelineRuns d'essai et sept jugements), puis 87 s après `restreint` (7/7), puis 105 s en `slsa-tekton` avec la liste revue (7/7), puis 114 s avec le contrôle des listes de tâches requises (7/7) | Porte de release, voir ci-dessous |
| `droits` | 5 s, puis 4 s, puis 4 s (75 droits), puis 4 s (89 droits), puis 11 s avec le relevé des 72 comptes de service |
| `posture` | 4 s (jouée seule après le rejeu de J1 à J6, puis ajoutée à `rejeu.sh`) | Posture des pipelines (tekton-lint), voir ci-dessous |

**Rejeu complet de J1 à J6 depuis zéro** (30/10/2026, `mise run confiance:rejeu`, [`rejeu-j1-j6.log`](resultats/rejeu-j1-j6.log)) : **1784 s**, dont 17 s de VM, 39 s de k3s, 54 s pour J2, 124 s pour J3, 140 s pour J4, 168 s pour J5 et **1240 s pour J6** (631 s jusqu'à `horodatage`, 36 s de test 5, 573 s pour `porte`, `rattrapage` et `droits`) ; 276 contrôles OK, aucun KO ; aucun des 18 secrets dans les journaux des trois VM ([`fuites-j1-j6.log`](resultats/fuites-j1-j6.log)). Étapes de J6 : `image` 72 s, `installer` 17 s, `parite` 227 s, `taches` 30 s, `admission` 29 s, `chains` 2 s, `declencheurs` 21 s, `restreint` 52 s, `horodatage` 181 s, test 5 35 s, `porte` 109 s, `rattrapage` 452 s, `droits` 11 s. Les journaux des étapes de J2 à J6 viennent de ce rejeu, sauf `politique-droits.log`, rejoué ensuite (comparaison d'horodatages corrigée, voir les constats). J4 et J5 y tournent pour la première fois en `slsa-tekton`, avec les mêmes résultats. Les chiffres des exécutions antérieures cités dans cette section ont été mesurés sur le cluster de J5, enrichi au fil de J6 ; leurs journaux restent dans l'historique git (dernier état avant le rejeu : commit `ae47114` ; passages plus anciens dans les commits précédents de J6, par exemple `bcc5efe` pour les deux premières exécutions d'`horodatage` ; durées : `chrono.tsv`). Mesures du rejeu, sur un cluster neuf :
- `restreint` : 6 → 8 → 10 enveloppes, deux par exécution ;
- `horodatage` : 11 enveloppes et 5 bundles au départ (les 5 bundles de J5 ; 6 enveloppes sans bundle, celles de `declencheurs` et de `restreint`), 6 horodatées au premier passage, 6 requêtes de jeton ; à la fin, 13 enveloppes, 13 bundles, **0 orphelin** ; chemin de la porte : 13 attestations vérifiées ;
- test 5 : quatre exécutions, quatre enveloppes ; le TaskRun de A et celui de E appartiennent à leur PipelineRun (garde `non_repris`, voir le constat de reprise) ;
- `porte` : 7/7 verdicts ; 9 provenances de PipelineRun sur `builds/essai-webhook` (6 avec la tâche listée, 1 avec une tâche non listée, celle de `j6-sans-restriction`, et 2 sans tâche, celles de J4) ;
- `rattrapage` : mêmes résultats aux mêmes essais ; à la fin, 21 enveloppes, 21 bundles, 0 orphelin ;
- `droits` : 89 sur 89 ; parmi les 72 comptes de service, les trois mêmes contrôleurs ; `el-forgejo` : 3 créations (A, E, c2) et 3 refus en 409 (F, G, remise à zéro de `main`).

Il a fallu trois rejeux. Les deux premiers ont révélé deux défauts, corrigés (journaux [`rejeu-j1-j6-ecart-1.log`](resultats/rejeu-j1-j6-ecart-1.log) et [`rejeu-j1-j6-ecart-2.log`](resultats/rejeu-j1-j6-ecart-2.log)) :
- **J4 en `slsa-tekton`** : le PipelineRun de J4 référence sa pipeline et sa tâche par leur nom, sans bundle. Sa provenance porte une entrée `pipelineTask` avec le TaskRun en ligne, mais sans `uri` ni digest. Le décompte des provenances de la porte appliquait `sub` à cette `uri` nulle et s'arrêtait, après les 7 verdicts, tous conformes. Il ne lit plus que les entrées qui ont une `uri`. `tekton.sh` affiche désormais une telle entrée comme une référence locale (et non plus `null@sha256:null`) ;
- **suppression au premier plan sans effet** sur un PipelineRun signé par Chains : voir le constat de reprise, plus bas.

**Redémarrage des trois VM après le rejeu** (`mise run confiance:redemarrer`, [`redemarrage-vm.log`](resultats/redemarrage-vm.log), réécrit en J7 ; journal de J6 au commit `6973403`) : arrêt 13 s, démarrage 8 s, trois nœuds prêts en 15 s. [`redemarrer.sh`](redemarrer.sh) attend désormais Kyverno avant OpenBao et le TSA. Ses webhooks sont en `failurePolicy: Fail`, et le pod du TSA, recréé après le descellement, passe par eux. Résultats :
- Kyverno : 4 pods prêts depuis le redémarrage. Une sonde est refusée par `zone-confiance` dès le premier essai, et non par une erreur d'appel du webhook. La sonde est un pod de `tsa` sans `nodeSelector`, conforme à `restricted` (Pod Security passe avant les webhooks), créé à blanc côté serveur ;
- OpenBao : scellé, puis descellé, avec la même clé ;
- TSA : jeton témoin vérifié ;
- Tekton et EventListener : pods prêts depuis le redémarrage (6 dans `tekton-pipelines`, 1 dans chacun des espaces `tekton-pipelines-resolvers`, `tekton-chains` et `declencheurs`) ;
- un passage réussi de chaque CronJob, créé après le retour du TSA. Horodatage : 29 enveloppes déjà horodatées, 2 témoins refusés et 1 anomalie. Rattrapage : tête de `main` présente.
- aucun des 18 secrets dans les journaux des trois VM après le redémarrage ([`fuites-j6.log`](resultats/fuites-j6.log)) . Matrice des droits et audit de l'API, voir ci-dessous |

**C-2 : parité entre le CLI et l'admission** ([`politique-parite.log`](resultats/politique-parite.log), [`politique-parite.tsv`](resultats/politique-parite.tsv)) :
- **même fichier de politique** des deux côtés : le modèle `ImageValidatingPolicy` du banc C, clés injectées comme dans son `run.sh` ; seul le glob change (`localhost:5000/*` → `192.168.161.13:5000/bench/*`). **Mêmes pods**, présentés à l'admission par `kubectl create --dry-run=server` (rien n'est créé) ;
- **preuve préalable** que l'admission évalue en dry-run : `c1-unsigned` est refusé par l'API (« Policy bench-release failed: C1… ») ;
- **17 cas du banc C**, repoussés dans le Zot du cluster par le `setup.sh` du banc : **17/17 décisions et motifs identiques**, conformes à l'attendu ;
- **8 cas d'horodatage de J5**, une politique par variante, pour ne pas partager le cache de vérification :

| Cas (attendu) | CLI 1.19.2 | Admission |
|---|---|---|
| Témoin : bundle valide, sans `tsaCertChain` (PASS) | PASS (code 0) | Admis |
| Bundle valide avec `tsaCertChain` (PASS) | `error` (code 1) : « nil pointer dereference » | **Refusé**, même erreur interne |
| Bundle sans jeton (FAIL) | FAIL | Refusé |
| Aucun bundle (FAIL) | FAIL | Refusé |
| Jeton altéré, jeton d'une autre signature, TSA étrangère (FAIL) | `error` (code 1), même erreur | **Refusé**, même erreur |
| Attestation `.att` historique, sans `tsaCertChain` (PASS) | FAIL : « cosign bundle verification failed » | Refusé (même défaut, kyverno/kyverno#17109) |

- **parité des décisions : 25/25** (admis si et seulement si `pass`, code 0 du CLI) ; parité des libellés : 21/25. **L'admission échoue fermé** : l'erreur interne de J5 donne un refus, jamais une admission ;
- durée moyenne par cas : 406 ms en CLI (lancement du binaire compris), 144 ms à l'admission (aller-retour de `kubectl` compris) ;
- **décision du propriétaire (29/10/2026)** : C-2 = 5 pour Kyverno seul (score 83 contre 70) ; **décision C reportée à J8**, Conforma reste la porte en J6.

**Trusted Resources** ([`politique-taches.log`](resultats/politique-taches.log)). Vérifications préalables, dans le code de Pipelines v1.15.5 :
- **seules les tâches et pipelines tirés par un résolveur sont vérifiés** (`GetTaskFunc`, `taskref.go`) : une référence locale ou une spec en ligne échappe aux VerificationPolicies. D'où les règles d'admission plus bas ;
- le motif d'une VerificationPolicy est ancré (`^(?:…)$`) : CVE-2026-25542 est corrigée dans cette version ;
- la source comparée au motif est le **dépôt du bundle, sans digest** (`imgRef.Context().Name()`, résolveur `bundles`) ;
- **les StepActions ne sont pas vérifiées** (aucun appel aux VerificationPolicies), et `enable-step-actions` est sans effet (fonction stable). La plateforme n'en utilise pas ; leur création est refusée à l'admission.

Mise en place : clé ECDSA P-256 **dédiée aux tâches**, distincte de celles de Chains et du TSA (0600 sur l'hôte) ; tâche signée par `tkn task sign`, publiée par `tkn bundle push` dans `tekton/tasks/` ; Tekton en `trusted-resources-verification-no-match-policy: fail` et `disable-inline-spec: pipeline,pipelinerun,taskrun`, résolveur `bundles` seul ; VerificationPolicy `taches-plateforme` (mode `enforce`, motif `sc-stockage\.poc\.test:5000/tekton/(tasks|pipelines)/[a-z0-9-]+`, clé publique en clair : le contrôleur n'a pas à joindre OpenBao). Essais, chacun par un TaskRun dans `builds` :

| Essai | Résultat |
|---|---|
| Tâche signée, bundle de `tekton/tasks` | **Exécutée**, `TrustedResourcesVerified=True` |
| Tâche non signée ; modifiée après signature (une ligne) ; signée par une autre clé | **Refusées** : `ResourceVerificationFailed` |
| Tâche signée, bundle hors de `tekton/` (`essais-j6/`) | **Refusée** : aucune politique ne correspond, `no-match-policy: fail` |
| Résolveurs `git`, `http`, `hub` et `cluster` | **Refusés** : « enable-…-resolver feature flag not true » |
| `taskSpec` en ligne | **Refusé à l'admission** par le webhook de Tekton (« must not set the field(s): spec.taskSpec ») |
| Tâche **v1** signée par tkn | **Refusée** (constat ci-dessous) |

**Constats.**
- **tkn v0.46.2 signe toute tâche comme une v1beta1** (`pkg/cmd/task/sign.go` : `v1beta1.Task`, même code sur la branche principale), puis réécrit le fichier depuis cette structure. Une tâche v1 signée porte alors `resources: {}` dans ses étapes, que Pipelines v1.15.5 rejette au décodage strict (`TaskRunResolutionFailed`). Défaut connu : tektoncd/cli#2894, ouvert. **Décision du propriétaire (29/10/2026)** : tâches et pipelines de la plateforme écrits en v1beta1 (dépréciée, servie par la LTS v1.15 jusqu'au 31/07/2027) ; le contrôleur vérifie la v1beta1 telle que signée, puis la convertit. Une tâche v1beta1 signée passe l'aller-retour : exécutée, et refusée dès qu'une ligne change.
- **Zot refusait les bundles de tkn** (`MANIFEST_INVALID`) : tkn pousse des manifestes Docker v2 schéma 2, et Zot n'accepte par défaut que l'OCI. Zot 2.1.22 a une option de compatibilité : `http.compat: ["docker2s2"]` (configuration de J2), plutôt qu'un assembleur de bundles maison.
- Le résolveur `bundles` reçoit la CA du PoC (`SSL_CERT_FILE`, configuration de J4) pour lire Zot.
- La configuration de Tekton posée par J6 (drapeaux, résolveurs) passe par `kubectl patch` : un nouveau `tekton.sh installer` la remet aux valeurs des `release.yaml` (mesuré en dry-run serveur : résolveurs tous actifs, `no-match-policy: ignore`, `disable-inline-spec` vide ; `set-security-context: "false"` dans le `release.yaml` de Pipelines v1.15.5), et J6 doit alors être rejoué.

**Règles d'admission de Kyverno** ([`politique/admission.yaml`](politique/admission.yaml), [`politique-admission.log`](resultats/politique-admission.log), [`politique-admission.tsv`](resultats/politique-admission.tsv), réécrits en J7 ; journaux de J6 au commit `6973403`). Cinq `ValidatingPolicy` en CEL (17 validations), chargées à l'admission et évaluées en CLI sur les mêmes fichiers :
- **`tekton-references` (test 2)** : TaskRun et PipelineRun seulement dans `builds`, sans spec en ligne, référencés par le résolveur `bundles` vers `tekton/tasks` ou `tekton/pipelines` **épinglés par digest** ; compte de service `build` seul (y compris `taskRunSpecs`) ; `podTemplate` sans volume, `hostNetwork`, `hostUsers`, `imagePullSecrets` ni jeton de compte de service ; aucun workspace `secret`, `projected` ou `csi`. Une mise à jour qui ne change pas la spec (annotation de Chains, retrait d'un finaliseur) n'est pas réévaluée ;
- **`pods-isolation` (test 4)** : ni `hostNetwork`, `hostPID`, `hostIPC`, ni `hostPath`, ni conteneur privilégié ou capacité ajoutée (sauf `NET_BIND_SERVICE`) hors Kata (`runtimeClassName` `kata` ou `kata-qemu`), conteneurs d'initialisation et éphémères compris ;
- **`zone-confiance`** (J3 : `bound_subject` seul) : dans `openbao`, `tekton-chains`, `tekton-pipelines`, `tekton-pipelines-resolvers`, `tsa`, `horodatage`, `declencheurs` et `porte`, `nodeSelector` `zone=confiance` obligatoire, aucune tolérance du taint de zone (ni tolérance universelle), pas de `nodeName` hors de `sc-confiance` ;
- **`zone-build`** (après le départ de l'EventListener) : dans `builds`, `nodeSelector` `zone=build` obligatoire, pas de `nodeName` hors de `sc-build`, **aucun volume de jeton de compte de service**. À l'admission, la règle voit les volumes ajoutés par l'API (contrôleur `ServiceAccount`) ; le CLI ne voit que le fichier présenté, d'où un `automountServiceAccountToken: false` explicite dans les cas d'essai ;
- **`stepactions-interdites`** : création de StepAction refusée.

Avant le chargement, aucun pod existant hors des espaces système ne les enfreignait. **37 cas** générés par [`cas-admission.py`](politique/cas-admission.py) : **tous conformes à l'attendu**, **parité CLI / admission 36/36** (le cas « privilégié sous Kata » n'est évalué qu'en CLI : la RuntimeClass n'existe qu'en J7). Refus par Kyverno pour 28 cas ; pour deux specs en ligne, le webhook de Tekton refuse le premier, Kyverno aussi. **Trace** : un événement `PolicyViolation` par refus, émis par Kyverno même en dry-run (30 événements pour 30 refus). Le 37e cas (« pod de `porte` en zone build ») est venu avec la porte de release. En J7, avec la RuntimeClass `kata` : 38 cas, parité 38/38 (voir « Jalon J7 »).

**Constat de mesure** : à la première passe des cas de J6, le cas « pod de `declencheurs` sans `nodeSelector` » était refusé parce que l'espace n'existait pas encore (`namespaces "declencheurs" not found`), et non par Kyverno. Il était compté conforme. Une réponse de l'API qui n'est pas un refus de webhook (« denied the request ») est désormais classée `ERREUR`, jamais `FAIL`, et l'étape crée l'espace avant les cas. Les 50 autres refus archivés (parité C-2 comprise) étaient bien des refus d'admission.

**Défense en profondeur, mesurée** ([`politique-taches-sous-admission.log`](resultats/politique-taches-sous-admission.log)) : l'étape `taches` rejouée **après** le chargement des règles d'admission donne les mêmes issues, mais cinq refus changent d'auteur. Ce journal est celui du dernier passage (30/10/2026), après l'ajout du `stepTemplate` à la tâche d'essai : mêmes issues, et la tâche v1 est refusée sur `spec.stepTemplate.resources` en plus de `spec.steps[0].resources` (même défaut de tkn). La tâche hors de `tekton/` et les résolveurs `git`, `http`, `hub` et `cluster` sont refusés **à la création** par Kyverno (`tekton-references`), avant que Tekton ne les voie. Les tâches non signée, modifiée ou signée par une autre clé, qui passent la règle (bundle de `tekton/tasks` épinglé), restent refusées par Trusted Resources. Le journal `politique-taches.log` reste celui de l'ordre du rejeu (`taches` avant `admission`), qui mesure Trusted Resources seul.

**Identifiants de Chains sortis de `builds`** ([`politique-chains.log`](resultats/politique-chains.log), [`politique/chains-zot.yaml`](politique/chains-zot.yaml)). Vérifié dans le code avant le changement :
- Chains v0.29.9 s'authentifie auprès du registre par `k8schain` (`pkg/chains/storage/oci/legacy.go`) : d'abord les `imagePullSecrets` du compte du TaskRun, puis `authn.DefaultKeychain` de go-containerregistry v0.21.9 ;
- ce dernier lit `$DOCKER_CONFIG/config.json` quand `$HOME/.docker/config.json` n'existe pas.

Mise en place :
- secret `zot-chains` (compte `poc-build`, clé `config.json`) dans `tekton-chains`, monté dans le contrôleur, désigné par `DOCKER_CONFIG` ;
- compte `build` **sans `imagePullSecrets` ni jeton monté** (`automountServiceAccountToken: false`) ; `zot-build` supprimé. Les nœuds tirent les images de Zot en lecture anonyme (J2).

**Preuve par l'audit de Zot** (étape `declencheurs`) : après le changement, les écritures `.att` sur `builds/essai-webhook` sont faites par `poc-build` (HTTP 201). Le tag `.sig` n'est pas réécrit : Chains saute une signature dont le contenu existe déjà (« already exists, skipping »). L'écriture `.att` prouve donc à elle seule que l'authentification fonctionne.

**Tâche et pipeline de J4 en bundles signés** ([`politique-declencheurs.log`](resultats/politique-declencheurs.log)) :
- `publier-essai` (tâche) et `sample-app-essai` (pipeline) réécrites en v1beta1, signées avec la clé des tâches (`tkn task sign`, `tkn pipeline sign` : ce dernier décode aussi en v1beta1, vérifié dans le code de tkn v0.46.2), publiées dans `tekton/tasks` et `tekton/pipelines` ;
- la pipeline désigne sa tâche **par bundle et digest** : sa signature couvre aussi le choix de la tâche ;
- vérifié dans le code de Pipelines v1.15.5 (`pipelinerun.go`, `resolveTask`) : le TaskRun enfant reçoit la `taskRef` complète (résolveur et bundle), donc il passe la règle `tekton-references` et sa tâche est vérifiée à nouveau.

| Essai (PipelineRun dans `builds`, gabarit de la TriggerTemplate) | Résultat |
|---|---|
| Pipeline signée | **Exécutée**, `TrustedResourcesVerified=True` pour le PipelineRun et pour le TaskRun enfant ; les deux sont signés par Chains |
| Pipeline modifiée après signature (sa tâche remplacée par une autre tâche signée, une ligne) | **Refusée** : `ResourceVerificationFailed` |

**EventListener dans l'espace de confiance `declencheurs`** ([`politique/declencheurs.yaml`](politique/declencheurs.yaml)). L'EventListener `forgejo`, son compte `el-forgejo`, la TriggerTemplate et le secret `forgejo-webhook` y vivent. L'espace applique Pod Security `restricted`, que le pod de l'EventListener respecte, et la règle `zone-confiance`. La TriggerTemplate crée le PipelineRun dans `builds` (`metadata.namespace` du gabarit, lu dans le code de Triggers v0.37.2 : `pkg/resources/create.go`). Droits du compte, lus dans le code de Triggers v0.37.2 au lieu des deux ClusterRoles de la release :
- informateurs limités à son espace (`cmd/eventlistenersink` : `WithNamespaceScope`) : lecture des objets de Triggers et des ConfigMaps de `declencheurs` ; création d'événements ;
- lecture de `clusterinterceptors` et `clustertriggerbindings`, ressources de cluster ;
- **aucun secret** : le secret HMAC est lu par le service des intercepteurs, avec son propre compte, dans l'espace du trigger (`pkg/interceptors/secret_getter.go`) ; **aucune impersonation** ;
- dans `builds` : création de PipelineRuns, et rien d'autre.

Les objets de J4 sont supprimés de `builds`, puis contrôlés : aucun secret (depuis J7 : sauf `zot-images`), ni EventListener, ni gabarit, ni tâche ou pipeline locale ; les ClusterRoles `tekton-triggers-eventlistener-*` ne sont plus liées à rien. Le webhook Forgejo est rebranché sur le NodePort de `declencheurs`, après la sonde `/live` depuis `sc-stockage` (code commun à J4 et J6 : `brancher_forgejo`).

**Test 5 rejoué sous politique** ([`politique-essais_webhook.log`](resultats/politique-essais_webhook.log)) : même script qu'en J4 (`tekton.sh essais_webhook`, espace de l'EventListener et préfixe du journal en paramètres), avec les règles d'admission, Trusted Resources et les droits réduits :
- livraison réelle de Forgejo et livraison valide (E) : PipelineRun créé, terminé et signé ;
- non signé (B), mauvaise signature (C), corps modifié (D) : **refusés par les intercepteurs**, aucun PipelineRun ;
- rejeux F et G : **sans effet** (`already exists`) ;
- 4 exécutions signées, 4 enveloppes dans Zot ;
- rejoué le 30/10/2026 avant l'étape `rattrapage`, avec les mêmes résultats : le CronJob de rattrapage est suspendu pendant l'essai, et le PipelineRun du cas A est vérifié comme créé par l'EventListener (label `triggers.tekton.dev/eventlistener`) ;
- rejoué après l'étape `restreint` (tâche en service avec son `stepTemplate`, `builds` en `warn` et `audit` `restricted`) : mêmes résultats au second passage, et aucune violation de `restricted` dans l'audit de l'API pour les pods de A et de E. Le premier passage s'est arrêté sur le constat ci-dessous ;
- **gain de provenance** : `externalParameters` désigne le bundle de la pipeline par digest, et `resolvedDependencies` porte la pipeline et sa tâche par digest (`pipeline`, `pipelineTask`). Dans les enveloppes de J4, encore présentes sous le même tag `.att`, `externalParameters` ne nomme que la pipeline et la tâche locales, et `resolvedDependencies` ne contient que l'image d'étape.

**Constat d'affichage, corrigé** : le tag `.att` accumule les enveloppes de toutes les exécutions d'un même sujet. Au premier passage de J6, l'affichage de la provenance a pris la première enveloppe du commit réel, celle de J4. Il ne retient plus que les enveloppes de l'essai en cours (`startedOn`).

**Constat : un PipelineRun recréé sous le même nom reprend le TaskRun de l'ancien, sans rien exécuter** ([`politique-essais_webhook-adoption.log`](resultats/politique-essais_webhook-adoption.log)). Mesuré au premier passage du test 5 après l'étape `restreint`, qui s'est arrêté faute d'enveloppe neuve pour le cas A :
- la purge du test supprimait les PipelineRuns en arrière-plan (`kubectl delete --all --wait`) : leurs TaskRuns restent jusqu'au passage du ramasse-miettes. L'audit de l'API donne la séquence : purge de `sample-app-6391fd43` à 09:12:43.408 ; le même nom recréé par l'EventListener (livraison réelle de Forgejo) à 09:12:44.681 ; statut « Succeeded » écrit à 09:12:44.714 ; ancien TaskRun supprimé par le ramasse-miettes à 09:12:44.777 seulement. **Aucun TaskRun ni pod n'a été créé** pour le nouveau PipelineRun ;
- lu dans le code de Pipelines v1.15.5 : le nom d'un TaskRun enfant est déterministe (`<PipelineRun>-<tâche>`), et la résolution le cherche **par nom, sans vérifier son propriétaire** (`getTaskRunFunc`, `pipelinerun.go`). Le filtre par propriétaire n'intervient qu'ensuite, sur le statut (`filterTaskRunsForPipelineRunStatus`). Côté TaskRun, le pod est bien vérifié par propriétaire (`IsControlledBy`) ;
- **Chains a signé pour ce PipelineRun une provenance incohérente** : la pipeline en service (`cd7bc914…`, qui désigne la tâche `836cd080…`), mais en `pipelineTask` l'ancienne tâche `fb41bcfc…`, avec `startedOn` à 00:49:09, l'heure de l'exécution précédente ;
- **la chaîne en aval ne le voit pas** : le CronJob d'horodatage a horodaté cette enveloppe à 09:13:10 (étiquette `…-5bb8a6a7e3ee6f68` de `horodatage/bundles`). Ses contrôles (clé de Chains, sujet, prédicat) passent, et aucun ne compare la pipeline à la tâche. L'enveloppe reste dans le tag `.att` de `builds/essai-webhook` ; des provenances plus récentes la masquent pour la porte, qui ne juge que la plus récente ;
- portée : il faut supprimer un PipelineRun puis le faire recréer sous le même nom avant le ramasse-miettes (1,4 s ici, après une purge de toutes les exécutions de `builds`). Dans le PoC, c'est un geste d'administrateur : `can-i` refuse la suppression de PipelineRuns de `builds` à l'opérateur, à l'EventListener, au rattrapage et au compte `build`. En production, un élagage des exécutions (pruner, TTL) supprime des PipelineRuns sans administrateur, et le rattrapage recrée celui de la tête de `main` au passage suivant : la course y devient possible sans action humaine (non mesuré) ;
- **premier correctif, insuffisant** : les suppressions suivies d'une recréation passaient au premier plan (`--cascade=foreground`), pour que les TaskRuns partent avant le PipelineRun. Second passage du test 5 : réussi, quatre exécutions et quatre enveloppes. Mais le second rejeu de J1 à J6 a reproduit la reprise (11:46:06) ;
- **la suppression au premier plan ne bloque pas un PipelineRun signé par Chains** ([`constat-foreground-chains.log`](resultats/constat-foreground-chains.log)). Dans l'audit, la seule écriture entre la suppression du PipelineRun et sa disparition est le retrait par Chains v0.29.9 de sa propre finalisation, par application côté serveur (`fieldManager=tekton-chains-controller/finalizers`). Le ramasse-miettes n'écrit pas sur ce PipelineRun, et son TaskRun est supprimé après la recréation. Expérience avec témoin : une ConfigMap supprimée au premier plan reste en `foregroundDeletion` tant que sa dépendante, retenue par une finalisation, existe, et le ramasse-miettes ne la libère que 3 ms après la dépendante ; un PipelineRun dans la même situation disparaît en moins de 3 s. Lu dans le réconciliateur généré, vendu dans Chains : pour retirer sa finalisation, Chains applique une liste vide. Pourquoi `foregroundDeletion` tombe avec elle n'est pas établi ;
- **corrigé dans les scripts** : `purger_pr` ([`commun.sh`](commun.sh)) supprime les PipelineRuns, puis leurs TaskRuns par le label `tekton.dev/pipelineRun`, et attend leur disparition, aux cinq endroits qui recréent un PipelineRun sous le même nom. Le test 5 vérifie en plus que les TaskRuns de A et de E appartiennent à leur PipelineRun (`non_repris`) : ses contrôles laissaient passer la reprise, et c'est la lecture de la provenance qui l'arrêtait. Troisième rejeu : réussi ;
- **pistes pour la plateforme** (non mesurées) : le rattrapage vérifie, avant de créer un PipelineRun, qu'aucun TaskRun de ce nom ne subsiste ; ou une règle d'admission refuse un PipelineRun dont un TaskRun enfant existe déjà. Aucun ticket trouvé chez tektoncd/pipeline (recherche du 30/10/2026) ; **décision du propriétaire (30/10/2026) : pas de ticket amont**. Pas de ticket non plus chez tektoncd/chains sur la suppression au premier plan (décision du propriétaire du 30/10/2026).

**Pod Security `restricted` des pods de build** ([`politique-restreint.log`](resultats/politique-restreint.log)). État de départ : `builds` sans label Pod Security, donc au niveau `privileged`. Le contexte de pod vient du gabarit depuis J4 (`runAsNonRoot`, `runAsUser: 65532`, `seccompProfile: RuntimeDefault`). Les 10 pods présents enfreignaient `restricted` sur deux points seulement, propres aux conteneurs : `allowPrivilegeEscalation` et `capabilities.drop` (label `enforce` en dry-run serveur).

Lu dans le code de Pipelines v1.15.5 :
- le drapeau `set-security-context` pose un contexte restreint (`allowPrivilegeEscalation: false`, `drop: [ALL]`, `runAsNonRoot`, `seccompProfile: RuntimeDefault`) sur les conteneurs ajoutés par Tekton : `prepare`, `place-scripts`, `working-dir-initializer`, le sidecar des résultats et l'affinity assistant (`pkg/pod/security_context_config.go`). **Pas sur les étapes** ;
- un TaskRun ne peut surcharger que les ressources d'une étape (`TaskRunStepSpec`), et le `podTemplate` ne porte qu'un contexte de pod. Le contexte des étapes vient donc de la tâche : `stepTemplate.securityContext`, couvert par sa signature ;
- un pod refusé par Pod Security fait échouer le TaskRun avec la raison `PodAdmissionFailed` (`isPodAdmissionFailed`, `taskrun.go`).

Mise en place :
- `set-security-context: "true"` (`kubectl patch`) ;
- `stepTemplate.securityContext` dans les deux tâches signées ([`publier-essai.yaml`](politique/taches/publier-essai.yaml), [`essai-confiance.yaml`](politique/taches/essai-confiance.yaml)), republiées par `taches` et `declencheurs` ; nouveau digest de la tâche en service : `836cd080…` ;
- labels `warn`, `audit` et `enforce` `restricted` sur `builds`, posés par l'étape (`enforce` : décision du propriétaire, ci-dessous). Ils ne sont pas dans `tekton/builds.yaml` : les tâches de J4 (`tekton/webhook.yaml`, `tekton/essai-signature.yaml`) n'ont pas de `stepTemplate`, et le rejeu de J4 serait touché. `tekton.sh signature`, qui réapplique ce fichier, conserve les labels (apply côté serveur, mesuré en dry-run).

| Essai | Résultat |
|---|---|
| Tâche en service signée **sans** son `stepTemplate`, sous `warn` et `audit` | Exécutée ; création du pod tracée dans l'audit de l'API (« would violate PodSecurity "restricted:latest" »), conteneur `step-publier` seul |
| Sous `enforce` : tâche en service (pipeline du gabarit) | **Exécutée** ; `prepare`, `place-scripts` et `step-publier` avec `allowPrivilegeEscalation: false` et `drop: [ALL]` ; aucune violation dans l'audit |
| Tâche d'essai de Trusted Resources (TaskRun) | **Exécutée** |
| Tâche signée sans `stepTemplate` | **Refusée** : `PodAdmissionFailed`, « violates PodSecurity », conteneur `step-publier` seul |
| Drapeau désactivé, tâche en service | **Refusée** : `PodAdmissionFailed`, conteneurs `prepare` et `place-scripts` seuls |

Pour le premier cas, l'étape lève `enforce`, puis le repose ; son piège le repose aussi en cas d'échec. Elle a été jouée deux fois de suite avec `enforce` permanent, avec les mêmes résultats. Ses deux exécutions vers l'image d'essai se suivaient sans attendre Chains : elles ont perdu 5 enveloppes en trois passages (récidive du constat majeur de J4, voir J4). Rejouée sérialisée (75 s) : signature de Chains attendue après chaque exécution, deux enveloppes exigées à chaque fois (62 → 64 → 66), mêmes résultats ; au rejeu de J1 à J6, 6 → 8 → 10. Les pods déjà présents ne sont pas expulsés : Pod Security ne juge qu'à l'admission (trois pods hors `restricted` au second passage, dont celui de J4). Après l'étape, les pods du test 5, des variantes de la porte et les cas de `builds` présentés à l'admission ne montrent aucune violation dans l'audit. Les règles d'admission rejouées ensuite donnent les mêmes décisions (37 cas, parité 36/36, 30 événements `PolicyViolation`).

**Décision du propriétaire (30/10/2026) : `enforce: restricted` sur `builds` dès J6 ; en J7, exemption des pods Kata par RuntimeClass**, qui passe par la configuration de k3s et demandera un accord séparé à ce moment-là.
- **Le conflit avec J7** : dès le niveau `baseline`, Pod Security refuse un conteneur privilégié et tout profil seccomp autre que `RuntimeDefault` ou `Localhost` (lu dans `pod-security-admission` de Kubernetes v1.35.0 : `check_privileged.go`, `check_seccompProfile_baseline.go`). Or J7 prévoit la construction dans un pod Kata, que l'ADR 0001 envisage en `privileged_without_host_devices` et que la règle `pods-isolation` admet en privilégié. Si la construction de J7 demande un conteneur privilégié ou un profil seccomp `Unconfined` (à mesurer en J7), `enforce` la refusera dans `builds`.
- **L'exemption** : `exemptions.runtimeClasses` de la configuration de Pod Security (vérifié dans le type `PodSecurityExemptions` de v1.35.0), par le drapeau `--pod-security-admission-config-file` du server k3s (correction de J7 : ce drapeau n'existe que dans RKE2 ; pour k3s v1.35.9, `kube-apiserver-arg: admission-control-config-file=…`). Un pod exempté échappe à tout Pod Security ; la règle Kyverno `pods-isolation` lui interdit toujours `hostNetwork`, `hostPID`, `hostIPC` et `hostPath`.
- **Options écartées** : `warn` et `audit` avec les contrôles de `restricted` portés par Kyverno (une seule barrière, par webhook) ; `warn` et `audit` seuls (un pod non conforme n'est que tracé).

**Horodatage automatique, par réconciliation périodique** ([`politique-horodatage.log`](resultats/politique-horodatage.log), [`politique/horodatage-cronjob.yaml`](politique/horodatage-cronjob.yaml), [`tsa/horodater.sh`](tsa/horodater.sh)). Le job de J5 devient un CronJob de l'espace `horodatage`. Chaque minute, un passage parcourt les dépôts de `builds/` dans Zot ; chaque tag `sha256-<digest>.att` y désigne une image attestée par Chains.
- **Source : Zot, pas l'API.** Le plan noté avant l'étape lisait les TaskRuns et PipelineRuns signés de `builds` par l'API. Il fallait pour cela un jeton dans `horodatage`, un rôle de lecture dans `builds`, une sortie vers l'API et une image avec kubectl à vérifier. Et les résultats `IMAGE_URL` et `IMAGE_DIGEST` viennent du pod de build, en zone hostile. Le passage lit Zot en anonyme, sans jeton (aucun volume de jeton dans le pod), avec la NetworkPolicy de J5 (DNS, TSA, Zot). Une exécution purgée de l'API reste horodatée (mesuré, voir plus bas). Un passage interrompu est repris par le suivant, par construction : chaque passage relit tout l'état de Zot (non mesuré).
- **Vérification avant le TSA.** Lu dans le code de cosign v3.1.4 (`AssembleNewBundleFromPayload`, appelé par `cosign bundle create`) : la clé n'y sert qu'à calculer son empreinte (`hint`), rien n'est vérifié. Le job de J5 aurait horodaté n'importe quelle enveloppe d'un tag `.att`, alors que `poc-ecriture` écrit dans `builds/**`. Le compte d'écriture des images de J7 y écrira aussi, et pourra écrire les tags `.att` si Zot ne permet pas de les lui interdire (voir les suites). Chaque enveloppe passe donc d'abord par `cosign verify-blob-attestation`, sur un bundle sans jeton : signature de la clé de Chains, sujet égal au digest de l'image (tiré du nom du tag), prédicat `https://slsa.dev/provenance/v1`. Mesuré sur l'hôte avant l'écriture du script, sans réseau ni cache TUF : enveloppe authentique acceptée ; autre digest, autre clé, autre prédicat refusés. Une enveloppe refusée est écartée (`REFUSEE` : ni jeton, ni bundle) sans arrêter le parcours, car Zot ne permet pas de la supprimer.
- **Tag `.att` illisible** : sonde faite hors de `builds/` ([`politique-horodatage-sonde-att.log`](resultats/politique-horodatage-sonde-att.log)). `cosign download attestation` échoue (code 1) sur un tag `.att` qui désigne un index OCI, ou dont la couche n'est pas du JSON. Une couche JSON qui n'est pas une enveloppe passe, puis elle est refusée. Zot refuse d'emblée un manifeste dont une couche manque. Avec `set -e`, le premier script aurait fait échouer chaque passage, indéfiniment. Ces échecs, comme celui de la liste des tags d'un dépôt, sont désormais comptés en anomalies (`ATTESTATIONS_ILLISIBLES`, `TAGS_ILLISIBLES`), et le parcours continue.
- **Vérification après le TSA** : avant sa publication, le bundle horodaté est revérifié de bout en bout (jeton exigé, racine de confiance du TSA ajoutée à la ConfigMap).
- `concurrencyPolicy: Forbid` (deux passages simultanés publieraient deux bundles pour une même enveloppe) ; `startingDeadlineSeconds: 120` ; `activeDeadlineSeconds: 300` (avec `Forbid`, un passage bloqué retiendrait les suivants).

**Témoins**, posés dans `builds` par `poc-ecriture` (le compte d'écriture général) et laissés en place, puisque Zot ne permet pas de les supprimer :
- `builds/essai-j6-autre-cle` : la provenance de Chains, réécrite pour l'image témoin et signée en DSSE par une clé jetable. Sur l'hôte, sa propre clé la vérifie, celle de Chains la refuse ;
- `builds/essai-j6-autre-sujet` : une enveloppe authentique de Chains, posée sur l'image témoin. Sur l'hôte, elle est acceptée pour le digest de l'image d'essai et refusée pour celui du témoin ;
- `builds/essai-j6-att-illisible` : un tag `.att` dont la couche n'est pas du JSON. Sur l'hôte, `cosign download attestation` échoue.

**Mesures**, en deux exécutions de l'étape. La prédiction est écrite par l'étape avant le premier passage, à partir des enveloppes et des bundles comptés dans Zot.
- **Première exécution** ([`politique-horodatage-rattrapage.log`](resultats/politique-horodatage-rattrapage.log)) : deux témoins, script d'avant la protection des tags `.att` illisibles ;
- **seconde exécution** ([`politique-horodatage.log`](resultats/politique-horodatage.log)) : avec le témoin illisible, et le PipelineRun supprimé de l'API (TaskRun compris) entre sa signature par Chains et le passage.

| Passage | Prédiction | Mesure | Requêtes de jeton reçues par le TSA |
|---|---|---|---|
| 1re exécution, rattrapage (31 s) | 10 horodatées, 5 déjà, 2 refusées | **10 horodatées** (enveloppes des exécutions de J6), 5 déjà (J5), 2 refusées | **10**, toutes du pod du passage |
| 1re exécution, après une exécution signée (9 s) | les nouvelles enveloppes | **2 horodatées** (TaskRun et PipelineRun `j6-horodatage`), 15 déjà, 2 refusées | **2** |
| 1re exécution, sans nouveauté (5 s) | aucune | 0 horodatée, 17 déjà, 2 refusées ; étiquettes de `horodatage/bundles` inchangées | **0** |
| 2e exécution, premier passage (4 s) | 0 horodatée, 17 déjà, 2 refusées, 1 anomalie | conforme ; le témoin illisible, parcouru en premier, est compté en anomalie | **0** |
| 2e exécution, après une exécution signée **puis supprimée de l'API** (9 s) | les nouvelles enveloppes | **2 horodatées**, 17 déjà, 2 refusées, 1 anomalie | **2** |
| 2e exécution, sans nouveauté (4 s) | aucune | 0 horodatée, 19 déjà, 2 refusées, 1 anomalie ; étiquettes inchangées | **0** |

- à chaque passage, les témoins sont traités avant `builds/essai-webhook` (ordre du catalogue). Les deux premiers sont refusés pour leur motif : « accepted signatures do not match threshold » (autre clé), « provided artifact digest does not match any digest in statement » (autre sujet). Le troisième est compté en anomalie (`ATTESTATIONS_ILLISIBLES`). Le TSA ne reçoit aucune requête pour eux, et le parcours continue ;
- **latence mesurée : 18 s puis 46 s**, entre la dernière écriture `.att` de Chains (audit de Zot) et le jeton. La borne est la période (60 s) plus la durée du passage, environ 3 s par enveloppe à horodater ;
- **une exécution purgée de l'API reste horodatée** : à la seconde exécution, PipelineRun et TaskRun étaient supprimés avant le passage, seul Zot gardait leurs enveloppes ;
- **un bundle par enveloppe** : 19 bundles pour 19 enveloppes de Chains (`essai-signature` et `essai-webhook`, même digest), aucun pour les trois images témoins ;
- **invariant apparié par signature** (30/10/2026, après la récidive du constat majeur de J4) : l'égalité des nombres ne tient plus, car une enveloppe horodatée a ensuite été perdue du tag `.att` (64 bundles pour 63 enveloppes). Enveloppes et bundles sont désormais appariés par la signature de l'enveloppe : une enveloppe sans bundle est fatale, les bundles orphelins sont listés, et leur nombre ne doit pas augmenter pendant l'étape. La prédiction du premier passage devient le nombre d'enveloppes sans bundle. Troisième exécution, 141 s : 67 enveloppes, 68 bundles, 0 sans bundle, 1 orphelin (le `TaskRun` de `j6-sans-restriction` du 30/10/2026 à 09:48:49), prédiction de 0 horodatée tenue ; à la fin, 69 enveloppes, 70 bundles, aucun nouvel orphelin ; au rejeu de J1 à J6, sur un cluster neuf : 0 orphelin ;
- **constat de mesure, corrigé** : la première tentative de cette troisième exécution s'est arrêtée dès la pose des témoins, code 141. Le script lisait la première enveloppe par `cosign download attestation … | head -1` : `head` fermait le tube avant la fin de l'écriture de cosign, arrêté par SIGPIPE, ce que `pipefail` rend fatal. Le tag porte désormais 66 enveloppes (376 ko). La sortie passe par un fichier. Revue de tous les tubes fermés tôt des scripts (`| head`, `| grep -q`) : trois autres sont exposés quand journaux et bundles grossissent, tous dans `tsa.sh` (`referrers | jq | head -2`, déjà plus de 4 ko pour 72 bundles ; `kubectl logs | grep -q` sur le conteneur de renouvellement ; journaux du serveur TSA `| head -5`). Ils passent aussi par un fichier ; rejoués sans arrêt par le rejeu de J1 à J6 (`tsa.sh deployer` et `chemins`). Les autres lisent des sorties de quelques lignes : le risque reste possible si l'écrivain écrit en plusieurs fois, mais il n'a jamais été observé ;
- **chemin de la porte** (cosign v3.1.4, bundles de `horodatage/bundles`, jeton exigé, racine du TSA) : 19 attestations vérifiées ;
- pod du passage sur `sc-confiance`, compte `horodatage`, sans volume de jeton ; entre les deux exécutions, le CronJob a tourné seul, en passages de 4 à 5 s, tous réussis ;
- **mode « une image » de J5 conservé** ([`politique-horodatage-mode-image.log`](resultats/politique-horodatage-mode-image.log)), avec le script protégé : un job de `tsa/horodatage-job.yaml`, lancé à la main, réussit sur `essai-signature` (déjà horodatée) ; il échoue sur le témoin `autre-cle` (refusé) et sur le témoin illisible (anomalie). `tsa.sh horodater` n'avait pas été rejoué, pour ne pas écraser le journal de J5 ; le rejeu de J1 à J6 l'a rejoué : 5 enveloppes horodatées, un bundle par enveloppe, reprise sans nouvel horodatage ([`tsa-horodater.log`](resultats/tsa-horodater.log)).

**Rattrapage des webhooks perdus** ([`politique-rattrapage.log`](resultats/politique-rattrapage.log), [`politique/rattrapage.yaml`](politique/rattrapage.yaml), [`politique/rattrapage/main.go`](politique/rattrapage/main.go)). Ce point traite le constat du premier rejeu de J1 à J5 : un push perdu quand l'EventListener est injoignable.
- **Lu dans le code de Forgejo v15.0.11** :
  - `Deliver` (`services/webhook/deliver.go`) marque la tâche livrée (`MarkTaskDelivered`) **avant** l'envoi. Un échec reste donc « livré », avec `IsSucceed=false`, et n'est jamais retenté. Au démarrage, `populateWebhookSendingQueue` ne remet en file que les tâches jamais tentées.
  - Le « replay » (`ReplayHookTask`) n'existe que par la route web `/settings/hooks/{id}/replay/{uuid}`. Il faut une session : les authentifications Basic et OAuth2 ne sont pas tentées hors de l'API (`services/auth/method/basic.go`, `oauth2.go`). Il faut aussi l'UUID de la tâche, qu'aucune route de l'API n'expose.
  - L'API n'offre que `POST hooks/{id}/tests`, réservé à un administrateur du dépôt.
  - Forgejo signe chaque livraison à l'envoi, avec le secret du webhook (`AddDefaultHeaders`).
- **Décision du propriétaire (30/10/2026)**. Trois options lui ont été présentées :
  - relivraison par `hooks/{id}/tests`, qui place dans la zone de confiance un jeton Forgejo d'administrateur du dépôt, capable de pousser du code ;
  - livraison signée avec le secret HMAC, monté dans un second pod ;
  - PipelineRun créé directement.

  Option retenue : **PipelineRun direct**. Le rattrapage n'utilise ni le secret HMAC ni un jeton Forgejo.
- **Réconciliateur.** Le CronJob `rattrapage` de `declencheurs` passe chaque minute (`Forbid`, `startingDeadlineSeconds: 120`, `activeDeadlineSeconds: 120`).
  - Il lit la tête de `main` dans Forgejo, en lecture anonyme avec la CA du PoC.
  - Si `sample-app-<commit>` manque dans `builds`, il crée ce PipelineRun depuis la TriggerTemplate en service, comme Triggers v0.37.2 (`pkg/template/resource.go` : remplacement textuel de `$(tt.params.…)`, `$(` doublé, `$(uid)`).
  - Il reprend les contrôles du filtre CEL, que ce chemin contourne : dépôt, branche, commit de 40 caractères hexadécimaux.
  - Il vérifie le gabarit rendu : un seul PipelineRun `tekton.dev/v1`, dans `builds`, nommé `sample-app-<commit>` (anti-rejeu de J4), sans variable restante.
  - Il pose le label `poc.test/declencheur: rattrapage` à la place des labels de Triggers.
  - Sur ce chemin, le commit est confronté à Forgejo, ce que la livraison ne fait pas avant J7.
- **Code maison dans la zone de confiance** : 246 lignes de Go, bibliothèque standard seule.
  - Compilé avec le Go 1.26.10 de `mise.toml`, vérifié par sum.golang.org. Deux compilations indépendantes, cache vide compris, donnent le même binaire `f6d7dcc6…`.
  - Image d'une seule couche sur base vide, sans shell : `linux/amd64`, utilisateur 65532, même digest `c3992728…` à chaque assemblage.
  - Écartés : le busybox de l'image d'outils, dont le `wget` ne vérifie pas les certificats TLS ; kubectl comme client HTTPS de Forgejo, qui demande un nom d'utilisateur faute d'identité.
- **Droits.**
  - Jeton projeté de 10 min, envoyé à l'API seulement : deux clients HTTP, aucune redirection suivie. Un jeton monté d'office demande 3607 s, mais l'API lui en accorde 365 jours (mesuré : [`politique-rattrapage-sonde-jeton.log`](resultats/politique-rattrapage-sonde-jeton.log) ; aucun drapeau `--service-account-*-token-expiration` dans les arguments de l'API de k3s, valeur par défaut).
  - Lecture du seul gabarit `sample-app` ; lecture et création de PipelineRuns dans `builds`.
  - NetworkPolicy limitée aux pods du rattrapage : DNS, Forgejo :3000, API :6443. Elle n'est pas en vigueur pendant la première seconde du conteneur (voir les constats), soit presque toute la durée d'un passage.

**Mesures** (septième exécution de l'étape, après le test 5 rejoué ; [`chrono.tsv`](resultats/chrono.tsv)). Les six précédentes : chaîne Go de `mise` mal choisie (le `GOROOT` de Go 1.24.7 exporté par `mise`), digest de l'image pas encore épinglé, fenêtre de démarrage et libellé mal découpé dans l'essai réseau, erreur `pipefail`, passage de rattrapage manqué à la seconde près (voir les constats), puis une réussite qui comparait c1 au PipelineRun du test 5 (cette comparaison supposait l'ordre du rejeu : elle se fait désormais entre c1 et c2, créés dans l'étape). Rejouée en `slsa-tekton` le 30/10/2026 ([`politique-rattrapage.log`](resultats/politique-rattrapage.log), 474 s) : mêmes résultats aux mêmes essais (c1 rattrapé dans la seconde de la réactivation), plus les lignes `internalParameters` et « porte » du tableau. Un premier passage s'était arrêté sur l'invariant d'horodatage : 64 bundles pour 63 enveloppes, une enveloppe perdue avant l'étape (récidive du constat majeur de J4). Rejouée par le rejeu de J1 à J6 (452 s) : mêmes résultats ; à la fin, 21 enveloppes, 21 bundles, 0 orphelin.

| Essai | Mesure |
|---|---|
| Premier passage. Prédiction : `PRESENT` pour `6391fd43…` | **Conforme** : `PRESENT`, rien n'est créé. Forgejo et l'API répondent au premier essai, sans doute avant que la NetworkPolicy ne soit posée (fenêtre de démarrage). Pod sur `sc-confiance`, sans jeton monté d'office, jeton projeté de 600 s |
| Sorties d'un pod au même label | Une fois la règle posée : **Forgejo, l'API (nœud et service) et le DNS seulement**. Fermés : Zot, SSH de `sc-stockage`, kubelet de `sc-build`, pod de l'EventListener, TSA, OpenBao. Fenêtre de démarrage : voir les constats |
| Webhook perdu : EventListener à 0 réplique, puis push d'un nouveau commit c1 (`e537a1db…`) | Forgejo fait **une seule tentative**, en échec (« connect: connection refused », journal de Forgejo) |
| EventListener rétabli et joignable, puis 150 s d'attente | **Aucune relivraison** : un seul échec dans le journal, aucun PipelineRun pour c1, aucune création demandée à l'API (audit) |
| Rattrapage : CronJob réactivé | `CREE` : PipelineRun de c1 créé **1 s après la réactivation** (push à 00:51:48, réactivation à 00:54:25, création à 00:54:26), une seule création (201, compte `rattrapage`). Exécuté, `TrustedResourcesVerified=True`, signé par Chains |
| Passage suivant | `PRESENT` : aucune création |
| Horodatage | L'exécution rattrapée a été horodatée par le CronJob d'horodatage dès le passage suivant sa signature : 31 bundles pour 31 enveloppes |
| Course : EventListener et rattrapage actifs, push de c2 (`1e290e1d…`) | Un seul PipelineRun, créé par l'EventListener (201), signé par Chains ; le passage suivant du rattrapage voit `PRESENT`. Deux créations simultanées donneraient un 409, que le réconciliateur traite (`DEJA`) ; ce cas n'a pas été mesuré |
| Comparaison des deux chemins : c1 (rattrapage) et c2 (EventListener) | **Spec identique**, commit excepté : `depot` octet pour octet, pipeline signée, gabarit de pod, compte. Les provenances de Chains, retrouvées par l'UID de chaque PipelineRun (`invocationId`), ont le **même `runSpec`** (paramètres externes), commit excepté. Elles ne sont pas identiques pour autant en `slsa-tekton` : voir la ligne suivante |
| `internalParameters` signés (`slsa-tekton`). Prédiction : seuls les labels de chaque créateur diffèrent | **Conforme.** Drapeaux de Pipelines et annotations identiques, au niveau du PipelineRun comme du TaskRun de l'entrée `pipelineTask`. Labels : `poc.test/declencheur: rattrapage` pour c1 ; `triggers.tekton.dev/eventlistener: forgejo`, `trigger: sample-app-push` et `triggers-eventid` (propre à chaque livraison) pour c2. Le TaskRun diffère en plus par le nom et l'UID de son PipelineRun. Chains signe ces labels sans les vérifier : ce sont des déclarations du créateur |
| Porte sur la provenance de chaque chemin, jugée juste après sa signature (la porte ne juge que la plus récente d'un digest ; vérifié avant chaque jugement) | **Même verdict** que la tâche en service : règles de source seules en échec (attendu jusqu'à J7), `trusted_task.trusted` parmi les succès. L'écart des labels est sans effet sur la porte |
| `main` remise à `6391fd43…` (force-push) | Tête servie par Forgejo. Livraison acceptée, puis refusée à la création (409, anti-rejeu). `PRESENT` pour le rattrapage ; PipelineRun du test 5 inchangé (créé à 00:49:09) |

**Constats.**
- **Fenêtre de démarrage des NetworkPolicy de sortie (kube-router de k3s)** ([`politique-rattrapage-sonde-fenetre.log`](resultats/politique-rattrapage-sonde-fenetre.log)).
  - La troisième exécution de l'étape, la première à atteindre l'essai réseau, enchaînait les connexions dès le lancement du conteneur : elle a joint Zot et le SSH de `sc-stockage`. Une contre-épreuve sur un pod gardé en vie les montre fermés.
  - Sonde (trois pods, une tentative vers Zot toutes les 0,5 s) : Zot est joignable à 0 ms, et jusqu'à 510 ms une fois, puis fermé avant 1 s.
  - **Une sortie interdite passe donc pendant la première seconde d'un conteneur**, le temps que kube-router pose la règle. C'est l'envers du délai d'entrée de J5.
  - L'étape mesure désormais la fenêtre, puis la matrice des sorties une fois la règle posée.
  - **Pour J7** : la zone build (« egress = 0 ») ne peut pas compter sur une NetworkPolicy seule pendant cette seconde. Un pod de build hostile aurait le temps d'exfiltrer. À traiter avec Kata et la mesure de J7. **Mesuré en J7** : Kata ne ferme pas la fenêtre (Zot joignable jusqu'à 540 à 570 ms après le lancement du conteneur dans les 12 essais, contre 0 à 10 ms sous runc dans 11 essais sur 12, et 500 ms une fois), et un pod Kata privilégié contourne la politique par usurpation d'adresse (voir « Réseau des pods Kata »).
- **Réactivation d'un CronJob** : le contrôleur lance aussitôt le passage manqué, dans la limite de `startingDeadlineSeconds`, parfois dans la seconde même. À la cinquième exécution, ce passage a créé le PipelineRun de c1 (201 dans l'audit). Mais l'étape attendait un passage créé strictement après l'instant de réactivation, à la seconde près : elle a lu le passage suivant (`PRESENT`) et conclu à tort à un échec. L'instant de référence est désormais pris une seconde plus tôt, et après la tête servie par Forgejo pour la course et la remise à zéro.
- **Erreurs du script, corrigées** : à la troisième exécution, le libellé « API(point d'accès) », découpé sur son espace, a fait tester un hôte nommé « d'accès) » ; à la quatrième, `n=$(kubectl get … | wc -l)` sur un PipelineRun absent a arrêté l'étape (`pipefail` et `set -e`), sans message, après le retour de l'EventListener.

**Porte de release (Conforma)** ([`politique-porte.log`](resultats/politique-porte.log), [`politique/porte.yaml`](politique/porte.yaml), [`politique/porte-job.yaml`](politique/porte-job.yaml), [`politique/porte/`](politique/porte/)). Ce point mesure la réserve de la décision C : la bibliothèque de Conforma (`slsa3`, `trusted_task`) appliquée à une vraie provenance de Chains.

Lu dans le code de la bibliothèque v1.0.28 et de Chains v0.29.9 :
- la bibliothèque ne lit les tâches d'une provenance SLSA v1 que dans le **contenu** des entrées `pipelineTask` de `resolvedDependencies`, un TaskRun encodé en base64 (`lib/tekton/task.rego`) ;
- Chains n'écrit ce contenu qu'en buildType `https://tekton.dev/chains/v2/slsa-tekton` (`AddTektonTaskDescriptor`). En `…/v2/slsa`, configuré en J4, il n'écrit que l'URI et le digest de la tâche (`AddSLSATaskDescriptor`). Le buildType `slsa-tekton` ajoute aussi les labels et annotations du PipelineRun à `internalParameters` ;
- la bibliothèque ne juge que la provenance de PipelineRun **la plus récente** d'un digest (maximum de `finishedOn`, `release/lib/attestations.rego`) ;
- `trusted_task` épingle par digest avec l'ancien format de données (`trusted_tasks`). Le nouveau format (`trusted_task_rules`) est désactivé par défaut et ne compare que des motifs de dépôt.

Mise en place :
- **où** : depuis l'hôte, `ec` reste bloqué au moins 5 min sur la lecture du bundle de la tâche, sans verdict ([`politique-porte-sonde-hote.log`](resultats/politique-porte-sonde-hote.log), sonde du prototype arrêtée par son propre `timeout 300`, code 124 ; l'issue de `ec` seul n'est pas mesurée). La provenance nomme ce bundle en `sc-stockage.poc.test`, que l'hôte ne résout pas. La porte tourne donc dans un Job de l'espace de confiance `porte` : Pod Security `restricted`, règle `zone-confiance`, compte sans jeton ni droit, NetworkPolicy limitée au DNS et à Zot ;
- **image** : une couche sur base vide. Elle contient `ec`, à l'empreinte du verrou, et `policy/release` et `policy/lib` de la bibliothèque sans les tests (76 fichiers Rego). Digest reproductible `e77994c2…` ;
- **politique** ([`politique/porte/policy.yaml`](politique/porte/policy.yaml)) :
  - collection `slsa3` et règles `trusted_task` ;
  - règles du PoC ([`porte.rego`](politique/porte/porte.rego)) : témoin « tâches vues », et signature d'image explicite, reprise du banc C ;
  - `allowed_builder_ids` remplacé par le builder du PoC (défaut de la bibliothèque : `https://tekton.dev/chains/v2`) ;
  - **liste revue des tâches approuvées** ([`politique/porte/taches.yml`](politique/porte/taches.yml)), au format `trusted_tasks` (dépôt et digest), versionnée et jamais écrite par les scripts ; elle ne contient que la tâche en service (`836cd080…`) ;
- **essais** : une image par cas, avec un label propre, donc un digest distinct, puisque la bibliothèque ne juge que la provenance la plus récente d'un digest. Ces PipelineRuns utilisent des tâches signées par la clé des tâches, des bundles de `tekton/` et le gabarit de `declencheurs`. Premier passage (buildType `slsa` en service) : Chains basculé en `slsa-tekton` le temps des essais. Depuis la décision (`slsa-tekton` en service), c'est l'inverse pour le cas `slsa`, et le cas positif est l'exécution réelle de la tâche en service : la provenance jugée, la plus récente de `builds/essai-webhook`, doit commencer après le début du cas et désigner la tâche du TaskRun créé par ce PipelineRun (garde contre le défaut d'adoption).

| Cas | Prédiction (règles en violation) | Verdict |
|---|---|---|
| Provenance en buildType `slsa` (aucune tâche lisible) | témoin, `tasks.pipeline_has_tasks`, `slsa_build_scripted_build.build_task_image_results_found`, règles de source | **Conforme** : refus |
| Même provenance, règles `trusted_task` seules | admise | **Admise** : `trusted_task.trusted` passe à vide |
| Tâche en service, dans la liste revue (`slsa-tekton`) | règles de source seulement | **Conforme** : `trusted_task.trusted` et le témoin parmi les succès ; avertissement `trusted_task.tagged` (bundle épinglé sans tag) |
| Tâche signée par la clé des tâches, publiée dans `tekton/tasks/publier-hors-liste`, absente de la liste | règles de source et `trusted_task.trusted` | **Conforme** : « uses an untrusted task reference » |
| Autre version de la tâche en service (même dépôt, digest non listé) | règles de source et `trusted_task.trusted` | **Conforme** |
| Image jamais présentée à Chains | `builtin.image.signature_check`, `builtin.attestation.signature_check` | **Conforme** |
| Témoin `essai-j6-autre-cle` (attestation signée par une autre clé) | les mêmes | **Conforme** |

Sept verdicts sur sept conformes à la prédiction, en 0 à 1 s par jugement (durée du conteneur `ec`). Les règles de source (`slsa_source_correlated.*`, `slsa_source_version_controlled.materials_format_okay`) échouent sur tous les essais. La tâche d'essai n'émet pas de source git (`CHAINS-GIT_*`), et la porte ne reçoit pas de source attendue. **Échec attendu jusqu'à J7** ; ces règles restent incluses. La provenance d'un PipelineRun pèse 2 513 à 2 519 octets en `slsa`, et 11 929 à 11 987 octets en `slsa-tekton`. Rejouée après la décision : sept verdicts sur sept, mêmes prédictions.

**Constats.**
- **Succès à vide de `trusted_task`** avec le buildType de J4 : aucune tâche n'est lue, donc aucune n'est refusée, et `trusted_task.trusted` figure parmi les succès. Seuls `tasks.pipeline_has_tasks` (collection `slsa3`) et le témoin du PoC refusent. Avec les règles `trusted_task` seules, l'image est **admise**.
- **Seule la provenance la plus récente compte.** Au premier passage, l'image approuvée portait trois provenances de PipelineRun ; les deux plus anciennes désignaient des versions de tâche non listées, puisque chaque signature de tâche est neuve. Après la décision, `builds/essai-webhook` porte 29 provenances de PipelineRun : 12 avec la tâche listée, 15 avec une tâche non listée (exécutions antérieures), 2 sans tâche (J4). `trusted_task.trusted` passe sur la plus récente. Au rejeu de J1 à J6 : 9 provenances (6 listées, 1 non listée, 2 sans tâche : celles de J4, dont l'entrée `pipelineTask` n'a ni `uri` ni digest en `slsa-tekton`). Lu dans la règle, non mesuré : une construction ultérieure du même digest par une tâche non listée ferait refuser une image déjà publiée.
- **Contrôle 9 hors de la porte.** `ec validate image` n'a pas d'option d'horodatage. Le contrôle 9 reste vérifié par cosign, sur le chemin retenu en J5. Il sera joint à la porte en J8 (test 8).

**Décision du propriétaire (30/10/2026) : buildType `slsa-tekton`.** Les règles `trusted_task` et `tasks` de la bibliothèque opèrent sur la provenance en service.
- **Liste revue** : la tâche en service est signée une fois, et le fichier signé est versionné ([`politique/taches/publier-essai.signee.yaml`](politique/taches/publier-essai.signee.yaml)). Mesuré : le même fichier signé, poussé deux fois, donne le même digest (`836cd080…`) ; le même contenu signé de nouveau en donne un autre (`f9be3b6a…`), les deux fichiers ne différant que par l'annotation de signature. `declencheurs` refuse de déployer si le fichier versionné ne correspond plus au gabarit rendu (signature exceptée), ou si son digest manque à la liste. `SIGNER=1` refait la signature dans le dépôt, puis la liste est à revoir. La revue, c'est la relecture du commit par le propriétaire avant tout push.
- **Suites** : les labels et annotations du PipelineRun entrent dans les `internalParameters` signés. Traité ci-dessous (`internalParameters` en `slsa-tekton`).
- **Effet sur le rejeu** : `tekton/chains/chains-config.yaml` passe en `slsa-tekton`. Au prochain rejeu, J4 et J5 produiront donc des provenances `slsa-tekton`, alors que leurs mesures datent du mode `slsa`. Aucune politique ne compare le buildType (vérifié dans les fichiers : la politique du banc C juge le builder, la source et les dépendances ; le contrôle 9 de J5, la seule signature de l'attestation). L'horodatage de provenances `slsa-tekton` est déjà observé dans les journaux du CronJob (`builds/essai-porte`, `DEJA_HORODATEE`). **Mesuré au rejeu de J1 à J6** : J4 et J5 donnent les mêmes résultats en `slsa-tekton`. Seul écart : l'entrée `pipelineTask` sans `uri` du PipelineRun de J4 (référence locale), qui arrêtait le décompte de la porte (corrigé).

**`internalParameters` en `slsa-tekton`** ([`politique-rattrapage.log`](resultats/politique-rattrapage.log), [`politique-porte.log`](resultats/politique-porte.log), [`politique-droits.log`](resultats/politique-droits.log)).

Lu dans le code :
- **Chains v0.29.9** : en `slsa-tekton`, `internalParameters` contient les drapeaux de Pipelines, puis **tous les labels et annotations du PipelineRun** (ou du TaskRun), tels qu'au moment de la signature (`TektonInternalParameters`, `internal_parameters.go`). En `slsa`, seulement les drapeaux. Aucune clé de configuration ne permet d'y ajouter une valeur : la configuration n'offre que `builder.id` et `builddefinition.buildtype` pour la provenance (`pkg/config/config.go`). Le TaskRun complet de l'entrée `pipelineTask` est sérialisé tel quel, métadonnées comprises (`managedFields` aussi).
- **Pipelines v1.15.5** : les labels et annotations de la Pipeline résolue sont recopiés sur le PipelineRun, **sans écraser ceux du PipelineRun** (`storePipelineSpecAndMergeMeta`) ; de même de la Task vers le TaskRun (`taskrun.go`). Ceux du PipelineRun sont propagés à ses TaskRuns.
- **Bibliothèque de Conforma v1.0.28** : la liste des tâches requises est choisie par un label, `build.appstudio.redhat.com/build_type` du TaskRun, à défaut `pipelines.openshift.io/runtime` des `internalParameters` (`lib/tekton/pipeline.rego`). La porte ne fournit aucune liste (`required-tasks`, `pipeline-required-tasks`) ; l'étape `porte` le vérifie désormais. Si elle en fournissait plusieurs, le créateur du PipelineRun choisirait la sienne par un label (lu, non mesuré).

Mesuré :
- **Deux chemins de création, même verdict** (étape `rattrapage`, tableau ci-dessus) : seuls les labels posés par chaque créateur diffèrent, aux deux niveaux. La porte rend le même verdict sur la provenance de chacun.
- **Qui peut écrire ces labels.** À la création : l'EventListener, le rattrapage et les administrateurs, dans `builds`. Ensuite, ni l'EventListener, ni l'opérateur, ni les comptes `build`, `horodatage`, `porte` et `rattrapage` (14 vérifications ajoutées à la matrice, 89 sur 89). Parmi les **72 comptes de service du cluster**, trois seulement peuvent modifier un PipelineRun de `builds` : les contrôleurs de Pipelines et de Chains, et le ramasse-miettes de Kubernetes (`kube-system:generic-garbage-collector`, qui gère propriétaires et finaliseurs). S'y ajoutent les administrateurs du cluster. Ni Kyverno, ni les résolveurs, ni Triggers. La première prédiction, tirée de la matrice, avait oublié le ramasse-miettes ([`politique-droits-premiere-prediction.log`](resultats/politique-droits-premiere-prediction.log)). L'admission ne juge pas une modification qui ne touche que les métadonnées (`matchConditions` de `tekton-references`, lu). Chains lit les labels à la signature, après l'exécution.
- **Constat** : dans le TaskRun signé, l'annotation `tekton.dev/signature` est celle de la **pipeline** en service (`MEUCIA+mcZrw…`, lue dans son bundle), pas celle de la tâche (`MEUCIGnBv80D…`). Les annotations du PipelineRun, reçues de la Pipeline, sont propagées au TaskRun et priment sur celles de la Task. Aucune politique ne la lit, et `trusted_task` épingle la tâche par digest ; un vérificateur qui la lirait attribuerait à la tâche la signature de la pipeline.

**Conséquence pour le doc 02 §3** : `hermetic`, `isolation` et `cpuModel` ne peuvent pas être inscrits « par la configuration Chains ». Le seul canal vers `internalParameters` est un label ou une annotation du PipelineRun, déclaration de son créateur ou de la Pipeline signée, que Chains signe sans la vérifier. **Décision du propriétaire (30/10/2026) : choix reporté à J7**, une fois `runtimeClassName`, réseau et nœud mesurés sous Kata ; aucune valeur de plateforme n'est inscrite d'ici là. Options présentées, avec ce que chacune couvre :
- (a) labels posés par les créateurs de confiance (gabarit de `declencheurs`, rattrapage) : les trois valeurs, comme déclarations. Leur vérité repose sur des règles Kyverno à écrire : labels exigés à la création, cohérence avec le gabarit de pod, modification refusée sauf aux contrôleurs (la règle actuelle ignore les changements de métadonnées). Après la création, les contrôleurs de Pipelines et de Chains, le ramasse-miettes et les administrateurs peuvent les changer ;
- (b) labels de la Pipeline signée, le PipelineRun n'ayant pas le droit de poser ces clés (règle Kyverno) : les trois valeurs, comme déclarations signées par la plateforme, mais une valeur par pipeline, pas par exécution ; même fenêtre de modification ;
- (c) rien dans `internalParameters`, la porte juge des faits du TaskRun signé : `isolation` par `runtimeClassName`, seulement s'il est écrit dans la spec (pas s'il vient d'un `default-pod-template` ou d'une mutation) ; `hermetic` et `cpuModel` ne sont pas des champs du pod et demandent une autre réponse (`cpuModel` par un `nodeSelector` du gabarit, à mesurer). Le doc 02 et l'ADR 0001 changeraient.

**Droits** ([`politique-droits.log`](resultats/politique-droits.log), [`politique-droits.tsv`](resultats/politique-droits.tsv), [`politique/droits.txt`](politique/droits.txt), [`politique/droits.yaml`](politique/droits.yaml)) :
- rôle sur mesure `operateur-builds` (groupe `operateurs`), **en lecture seule** : PipelineRuns, TaskRuns, pods, journaux et événements de `builds`. Les rôles agrégés `edit` et `admin` (`tekton-aggregate-edit`) ne conviennent pas : ils donneraient `pods/exec` et la lecture des secrets de l'espace ;
- **89 vérifications `kubectl auth can-i`, toutes conformes** (deux ajoutées avec le constat d'adoption : suppression de PipelineRuns refusée à l'EventListener et au compte `build`, comme à l'opérateur et au rattrapage ; quatorze avec les `internalParameters` : modification des PipelineRuns de `builds` refusée à l'EventListener, à l'opérateur et aux comptes `build`, `horodatage` et `porte`, accordée aux seuls contrôleurs de Pipelines et de Chains). Compte `porte` : aucun droit (ni PipelineRuns, ni ConfigMaps, ni secrets, ni pods, ni Jobs). Compte `rattrapage` : lecture du seul gabarit `sample-app` (ni un autre gabarit, ni la liste, ni sa modification), lecture et création de PipelineRuns dans `builds` ; ni modification ni suppression de PipelineRuns, ni TaskRun, ni PipelineRun hors de `builds`, ni secrets, ni pods, ni CronJobs. Compte `horodatage` du CronJob : aucun droit sur l'API, ni lecture des TaskRuns et PipelineRuns de `builds`, ni secrets, ni création de pods. Compte `build` : aucun droit, et `can-i --list` ne montre que les droits de découverte communs à tout compte. EventListener : seulement ses lectures et la création de PipelineRuns dans `builds`. Opérateur : ni `taskruns/status` ni `pipelineruns/status` (test 3), ni modification des TaskRuns, ni `exec`, `attach`, `portforward` ou conteneur éphémère, ni secrets, ni `serviceaccounts/token` dans `tekton-chains`, `openbao` et `tsa`, ni création de pods dans la zone de confiance ;
- `can-i` ne juge que le RBAC : un droit accordé reste soumis à l'admission (Kyverno, webhooks de Tekton) ;
- **audit de l'API depuis le dernier test 5** : le compte `el-forgejo` n'écrit que des `create pipelineruns` dans `builds`, **aucun refus 403**. Au passage du 30/10/2026 à 08:50, le dernier test 5 précédait l'étape `rattrapage` : 3 en 201 (A, E, c2) et 3 rejeux en 409 (F, G, remise à zéro de `main`). Au passage de 09:25, après le test 5 rejoué : 2 en 201 (A, E) et 2 en 409 (F, G). Aucun « forbidden » dans le journal de l'EventListener. **Portée corrigée** (rejeu de J1 à J6) : ce contrôle ne lit que le pod en cours, et l'étape `rattrapage` le recrée (EventListener à 0 réplique, puis 1). Le journal du test 5 n'existait donc déjà plus. Le contrôle lit désormais les conteneurs précédent et en cours du pod, et affiche la fenêtre lue : au rejeu, le pod créé à 12:16:55 par `rattrapage`, 8 lignes de 12:21 à 12:22, aucun « forbidden ». Pour le test 5, seules les écritures sont prouvées par l'audit ; un pod neuf démarre ses informateurs avec les mêmes droits. Le compte `rattrapage` n'écrit qu'une création de PipelineRun dans `builds` (201, c1), sans refus. L'audit ne journalise pas les lectures (politique de J1) : leur suffisance se lit au fonctionnement de l'EventListener et à son journal.
- **Constat de mesure, corrigé** : le journal d'audit de l'API tourne à 100 Mo (`audit-log-maxsize=100`, 10 fichiers gardés). Avec deux CronJobs à la minute, il a tourné en quelques heures (03:17). Le passage suivant de `droits` ne lisait que `audit.log` : il n'a plus trouvé les écritures de l'EventListener, et la section de l'EventListener a quand même conclu « OK », sur une sortie vide. Les lectures de l'audit passent désormais par `audit_api` (fichiers tournés compris, filtrés sur la VM), et les deux sections exigent au moins une écriture. `creations()`, la fonction de l'étape `rattrapage`, passe aussi par `audit_api` ; rejouée par le rejeu de J1 à J6.
- **Constat de mesure, corrigé** (rejeu de J1 à J6) : `droits` comptait 2 créations réussies de `el-forgejo` au lieu de 3. La création de A (12:13:08.741) tombait dans la seconde du début du test 5 (`12:13:08Z`) ; en comparaison de chaînes, « 08.741 » précède « 08Z » (« . » avant « Z »), et l'écriture était exclue. Un refus dans cette seconde aurait échappé au contrôle de la même façon. Même défaut à onze endroits des scripts : audit de l'API, audits d'OpenBao et de Zot, et événements, tous horodatés avec des fractions de seconde. Les horodatages des objets Kubernetes n'en ont pas. Comparaison faite désormais sur les 19 premiers caractères, seconde de début comprise. `droits` a été rejoué : 3 créations et 3 refus en 409. Les autres endroits (`restreint`, `horodatage`, `rattrapage`, J3 à J5) ne sont pas rejoués ; leurs contrôles ont passé au rejeu.

**Posture des pipelines (tekton-lint)** ([`politique-posture.log`](resultats/politique-posture.log), [`politique/posture/`](politique/posture/)). Accord du propriétaire (30/10/2026) : tekton-lint 1.2.4 avec un verrou npm. Projet « à surveiller » (Scorecard 5,8, doc 04), sans attestation de provenance npm ; la sécurité des références reste à Kyverno.
- **Verrou** (`package-lock.json`, généré le 30/10/2026 sans rien installer) : tekton-lint épinglé exactement, 90 paquets, tous servis par `registry.npmjs.org` avec leur intégrité sha512. L'intégrité de tekton-lint est celle relevée le 29/10/2026 (`sha512-7539…`, contrôlée à chaque passage). Un seul script d'installation, celui de `fsevents` (macOS, optionnel, non installé). Le verrou fige l'état du registre au 30/10/2026 ; node 22.22.0 satisfait `engines` (≥ 22).
- **Installation** hors du dépôt (`…/08/outils/tekton-lint`), par `npm ci --ignore-scripts` à chaque passage : 89 paquets. Le rejeu contacte donc `registry.npmjs.org` à chaque passage de `posture` (installation et signatures), comme il contacte les registres amont pour les vérifications de signature ; une indisponibilité du registre arrêterait l'étape. `npm audit signatures` : **89 signatures du registre vérifiées**, aucune invalide ni absente. Deux paquets ont aussi une attestation (`chokidar`, `fastq`), mais pas tekton-lint.
- **Configuration versionnée** ([`.tektonlintrc.yaml`](politique/posture/.tektonlintrc.yaml)) : les sévérités par défaut du paquet, sans tâches externes (`external-tasks` fait un `git clone` à chaque lancement) ni règles en JavaScript. Seul écart : `no-missing-resource` désactivée (ci-dessous). Cache dans le répertoire de travail : par défaut, l'outil crée `~/.tekton-lint` à chaque lancement.
- **Lu dans le code** : aucune règle ne porte sur les StepActions (`steps[].ref`), les specs en ligne ni les références par digest. Ces contrôles restent à Kyverno (`tekton-references`, `stepactions-interdites`). Les règles croisées entre pipeline et tâche (`no-extra-param`, `no-missing-param`, `no-undefined-result`) cherchent la tâche par son nom : une référence par résolveur, sans nom, est sautée.
- **Ressources jugées** : celles qui tournent, soit la TriggerTemplate `sample-app` (lue dans le cluster, définition seule), sa pipeline et sa tâche (lues dans leurs bundles de Zot, par digest) et la tâche d'essai `essai-confiance`. **Aucun signalement**, comme prédit après correction.
- **Première prédiction démentie** ([`politique-posture-premiere-prediction.log`](resultats/politique-posture-premiere-prediction.log), sortie brute comprise) :
  - `no-resourceversion` sur la TriggerTemplate lue dans le cluster, à cause du `resourceVersion` posé par le serveur. C'est un artefact de lecture : seule la définition est jugée désormais ;
  - `no-missing-resource`, deux fois : la règle signale comme introuvable toute référence par résolveur (« references task 'undefined' »), puis son rapporteur plante sur la clé `name` absente. L'erreur est rattrapée, mais le journal interne s'écrit sur la sortie standard, à la suite du JSON. **tekton-lint 1.2.4 ne lit pas les références par résolveur**, alors que le PoC les impose. La règle est désactivée ; on perd la détection d'une référence par nom vers une ressource absente, refusée de toute façon à l'admission (toute référence par nom l'est : cas `tr-locale` et `pr-locale`). **Décision du propriétaire (30/10/2026) : règle gardée désactivée.** À chaque nouvelle version de tekton-lint, on rejoue la ressource en service avec la règle active ; on la réactive le jour où elle lit les références par résolveur. Toute ligne hors du JSON compte désormais comme une erreur interne (KO).
- **Témoins** ([`politique/posture/cas/`](politique/posture/cas/), prédiction en tête de chaque fichier), 9 sur 9 :
  - chaque règle visée se déclenche : `no-latest-image`, `no-undefined-param`, `no-unused-param` (tâche et TriggerTemplate), `no-duplicate-param`, `no-missing-hashbang`, `no-extra-param` (tâche référencée par nom) ;
  - deux limites mesurées : le même paramètre en trop vers une tâche référencée par bundle n'est pas signalé, et une tâche absente référencée par nom non plus (règle désactivée).
- **Portée** : tekton-lint juge la cohérence des définitions (paramètres, résultats, images, scripts), pas leur sûreté. Sur une plateforme à bundles, ses règles croisées ne voient pas la tâche d'une pipeline. Il reste un contrôle de qualité avant signature, pas une barrière.

**Droits résiduels, consignés** : les contrôleurs de Pipelines et de Chains, le résolveur et **les intercepteurs de Triggers lisent tous les secrets du cluster**. Pour les intercepteurs, c'est vérifié dans le code : leur informateur de secrets porte sur tout le cluster (`cmd/interceptors` sans `WithNamespaceScope`). Les restreindre à un espace casserait l'informateur. Ces composants tournent tous en zone confiance, sous la règle `zone-confiance`.

**Limites et suites** :
- `builds` est en `enforce: restricted` : une tâche de la plateforme sans `stepTemplate` restreint est refusée à la création de son pod. La construction de J7 sous Kata demandera l'exemption par RuntimeClass (configuration de k3s, accord séparé) ;
- un PipelineRun recréé sous le même nom avant le passage du ramasse-miettes reprend le TaskRun de l'ancien sans rien exécuter, et Chains signe une provenance incohérente (constat de J6, ci-dessus). La suppression au premier plan ne l'empêche pas (Chains la défait) : les scripts suppriment explicitement les TaskRuns et le test 5 détecte une reprise ; la plateforme n'a pas encore de garde ;
- l'identifiant `poc-build` de Chains peut toujours écraser `.sig` et `.att` (constat de J4), mais il n'est plus monté que dans la zone de confiance ;
- `internalParameters` : aucune valeur de plateforme (`hermetic`, `isolation`, `cpuModel`) n'est inscrite. Chains ne les accepte que sous forme de labels ou d'annotations du PipelineRun, qu'il signe sans les vérifier ; choix du canal reporté à J7 (décision du propriétaire du 30/10/2026) ;
- horodatage automatique :
  - chaque passage relit toutes les enveloppes de `builds/` (catalogue, tags, téléchargements) : le coût croît avec leur nombre (4 à 5 s pour une vingtaine d'enveloppes). En production, il faudrait mémoriser le digest du tag `.att` déjà traité, ou lire les bundles en referrers quand Chains les publiera (tektoncd/chains#2096) ;
  - un refus n'est visible que dans le journal du passage : ni alerte, ni événement, puisque le compte n'a pas accès à l'API. À brancher sur la supervision ;
  - relancer `tsa.sh horodater` pendant que le CronJob tourne peut publier deux bundles pour une même enveloppe (deux écrivains sur une étiquette). Le rejeu lance J5 avant de créer le CronJob ;
  - une enveloppe perdue par la course du tag `.att` (constat de J4) n'est jamais horodatée, puisqu'elle n'existe plus dans Zot. Perdue après son horodatage, elle ne survit que dans `horodatage/bundles` (un bundle orphelin sur le cluster de J6, aucun au rejeu de J1 à J6) ;
  - une enveloppe est sautée dès que son étiquette existe dans `horodatage/bundles`. Une étiquette occupée d'avance par `poc-ecriture` ou `poc-horodatage` ferait donc sauter en silence une enveloppe authentique. Le contrôle de l'étape (chaque enveloppe a son bundle, apparié par signature) le verrait, mais pas le CronJob ;
  - un tag `.att` aux couches énormes dépasserait le volume de travail du pod (64 Mi) et ferait échouer chaque passage (non mesuré) ;
- rattrapage des webhooks :
  - seule la tête de `main` est rattrapée. Les commits poussés pendant une panne, puis recouverts par un push suivant, ne sont jamais construits ; c'est déjà le cas avec la livraison, qui ne construit que `after` ;
  - l'anti-rejeu repose sur l'objet PipelineRun (limite de J4). Un PipelineRun de la tête supprimé de l'API est recréé au passage suivant, avec une nouvelle provenance ;
  - un second chemin de création contourne les intercepteurs de l'EventListener (HMAC, filtre CEL). Le réconciliateur en reprend les contrôles et lit le commit dans Forgejo, mais un compte qui peut créer des PipelineRuns dans `builds` le peut aussi sans lui (même pouvoir qu'`el-forgejo`). Les règles de Kyverno et Trusted Resources s'appliquent aux deux chemins ;
  - délai de rattrapage borné par la période (60 s) et la durée d'un passage (3 s) ;
  - le réconciliateur est du code maison à maintenir (246 lignes). Il ne rend compte que dans le journal de ses passages, sans alerte ;
- porte de release :
  - elle est lancée à la main, image par image, et n'est pas encore reliée à une demande de release. Son verdict n'est ni attesté ni publié dans Zot (doc 02 : « verdict de la porte (attestation) ») ;
  - la VSA de replay, le scan et les licences ne sont pas encore produits : leurs contrôles attendront le domaine de replay et l'analyse ;
  - la liste des tâches approuvées est un fichier versionné et revu (relecture du commit), mais pas signé. Toute nouvelle signature d'une tâche change son digest et impose une nouvelle revue. Une clé des tâches perdue ou refaite invalide la signature versionnée ;
  - `ec` est le binaire de la release, vérifié par son empreinte seulement ; sa reconstruction relève de la brique 11 ;
- NetworkPolicy de sortie des jobs courts : celles du rattrapage et de l'horodatage (« DNS, TSA, Zot ») ne s'appliquent qu'après la première seconde du conteneur (kube-router, constat de J6). Un passage de 3 à 5 s n'est donc filtré qu'en partie ;
- le compte `el-forgejo`, qui crée des PipelineRuns dans `builds`, monte un jeton d'office (3607 s demandés, donc 365 jours accordés). Un jeton exfiltré du pod de l'EventListener resterait valable un an. Piste : un volume projeté de courte durée, comme pour le rattrapage, si Triggers le permet ;
- la construction de J7 devra pousser l'image depuis la zone build : il faudra un compte d'écriture distinct, limité aux images, sans accès aux tags `.sig` et `.att`, si Zot le permet (**traité en J7** : compte `poc-images`, création par digest seulement, condition CEL de Zot v2.1.22 ; voir « Construction de sample-app dans un PipelineRun ») ;
- le correctif de Chains et le compte `build` passent par `kubectl patch`. Mesuré en dry-run serveur : un nouveau `tekton.sh installer` **conserve** le correctif de Chains (`DOCKER_CONFIG`, volume `zot-chains` : l'apply côté serveur ne retire pas les champs posés par un autre gestionnaire). En revanche, `tekton.sh signature` réapplique `tekton/builds.yaml` : `imagePullSecrets: zot-build` revient sur le compte `build` (le jeton reste désactivé), et le secret `zot-build` est recréé dans `builds`. Il faut alors rejouer `politique.sh chains`.


## Jalon J5 : horodatage RFC 3161 (29/10/2026)

Rejeu : `mise run confiance:tsa -- image pki openbao deployer essais horodater chemins`. Après un redémarrage des VM, [`redemarrer.sh`](redemarrer.sh) recrée le pod du TSA une fois OpenBao descellé, puis rejoue `temoin`.

**Architecture** ([`tsa/`](tsa/)) :
- **TSA** : timestamp-authority v2.2.0 sur `sc-confiance`, espace `tsa` (Pod Security restricted, non root, racine en lecture seule, aucun jeton Kubernetes monté).
  - Signataire `kms` sur la **clé Transit `tsa`** d'OpenBao (ecdsa-p256, non exportable, sans sauvegarde en clair), distincte de la clé `chains`.
  - Le client hashivault de sigstore v1.11.1, utilisé par le serveur, ne sait pas se connecter seul (`kms.Get` sans options d'authentification) : il lit un jeton OpenBao dans `~/.vault-token`, une seule fois. Un conteneur d'initialisation l'obtient avec le jeton projeté du compte de service `tsa:timestamp-authority` (rôle JWT `tsa`, audience `openbao`). Un conteneur voisin renouvelle ce jeton périodique (1 h) toutes les 15 min.
  - Politique `tsa-signature` : lecture de la clé `tsa`, signature, renouvellement de son propre jeton.
- **Racine TSA dédiée**, distincte de la CA TLS du PoC (clés séparées par usage), clé en 0600 sur l'hôte. La **feuille porte la clé publique de Transit** (`openssl x509 -new -force_pubkey`), avec l'EKU `timeStamping` seul et critique ; sa clé publique est recoupée avec Transit, et le serveur contrôle la chaîne au démarrage.
- **Réseau** : entrée réservée à l'espace `horodatage` (port 3000, en HTTP : le jeton est signé, sa valeur ne dépend pas du transport) ; sortie vers DNS et OpenBao seulement. Sans sortie, la surveillance NTP du serveur est désactivée.
- **Job d'horodatage** ([`horodater.sh`](tsa/horodater.sh)), dans l'espace `horodatage`, sur le nœud de confiance, hors des pods de build. Pour chaque enveloppe DSSE du tag `.att` de l'image :
  - jeton du TSA sur les **octets bruts de la signature**, ce que vérifient sigstore-go et cosign pour un bundle ;
  - bundle Sigstore v0.3 (`cosign bundle create`), publié en referrer de l'image **dans un dépôt séparé, `horodatage/bundles`**, avec le compte Zot `poc-horodatage` (`horodatage/**` seulement). Pourquoi un dépôt séparé : dès qu'un bundle est rattaché à l'image, Kyverno ne lit plus que les bundles et ignore `.sig` et `.att` (`buildCheckOptsWithBundleDetection`, Kyverno 1.19.2), alors que Chains en `dsse` ne produit pas de signature d'image au format bundle. Zot accepte un referrer dont le sujet est dans un autre dépôt et le liste dans l'API referrers ;
  - rejouable : le manifeste est étiqueté par le digest de l'image et l'empreinte de la signature, une enveloppe déjà horodatée est sautée.
- **Image d'outils du job**, assemblée sans Docker (`crane append`) : base cosign v3.1.4-dev (signée), `oras` (GPG) et `timestamp-cli` (attestation GitHub). La couche est reproductible : même digest `c7bebae2…` à chaque assemblage. L'image elle-même n'est pas signée ; sa reconstruction relève de la brique 11.

**Rejeu complet de J1 à J5 depuis zéro** (`mise run confiance:rejeu`, [`rejeu-j1-j5.log`](resultats/rejeu-j1-j5.log)) : **533 s**, dont **151 s pour J5** (VM 22 s, k3s 41 s, J2 53 s, J3 122 s, J4 141 s) ; 106 contrôles OK ; aucun des 17 secrets dans les journaux des trois VM ([`fuites-j1-j5.log`](resultats/fuites-j1-j5.log)). Journaux : `resultats/tsa-<étape>.log` ; ceux des étapes de J2 à J4 viennent aussi de ce rejeu. Il a fallu quatre rejeux. Le premier a révélé le délai de l'EventListener, le second une coupure de Zot sur un registre amont lent. Le quatrième a suivi la correction du renouvellement du jeton du TSA (voir les constats), et il est suivi d'un redémarrage des trois VM : arrêt en 6 s, TSA relancé avec un nouveau jeton, jeton témoin vérifié ([`redemarrage-vm.log`](resultats/redemarrage-vm.log)).

| Étape | Durée | Résultat |
|---|---|---|
| `image` | 42 s | **timestamp-server** : le tag annoté v2.2.0, signé et vérifié par GitHub, désigne le commit `526e9de7…` ; index `77c615f0…` = digest du tag ; attestation GitHub (workflow `build_container.yml` au tag, commit du tag, déclencheur `push`) vérifiée sur ghcr.io **puis sur la copie de Zot** (`--bundle-from-oci`). **cosign v3.1.4-dev** : signature vérifiée, identité voisine refusée. **timestamp-cli** : sommes et attestation GitHub de release. **oras** : empreinte de la clé publiée sur oras.land, signature GPG des sommes, archive identique à `mise.lock`. Image d'outils assemblée, même digest que l'image épinglée |
| `pki` | < 1 s | Racine TSA ECDSA P-256, 10 ans, `pathlen:0` (réutilisée d'un rejeu à l'autre, comme la CA du PoC) |
| `openbao` | 1 s | Clé `tsa`, politique, rôle (`token_period` 1 h, sans politique par défaut). Feuille émise pour la nouvelle clé Transit, vérifiée (`timestampsign`), clé publique = Transit. Chaîne publiée ([`tsa-chaine.pem`](resultats/tsa-chaine.pem)) et racine de confiance de cosign (TSA seule, sans Rekor, Fulcio ni CT) |
| `deployer` | 5 s | NetworkPolicy d'OpenBao seule appliquée, sans toucher au StatefulSet (un redémarrage le rescellerait). TSA prêt, jeton OpenBao obtenu puis renouvelé (« jeton renouvelé : 3600 s »), images tirées de Zot |
| `essais` | 51 s | Voir ci-dessous |
| `horodater` | 32 s | **5 bundles pour 5 enveloppes** (1 pour `essai-signature`, 4 pour `essai-webhook`, même digest) ; la reprise ne refait rien ; aucun referrer dans les dépôts des images |
| `chemins` | 19 s | Voir ci-dessous |

**Essais du TSA** ([`tsa-essais.log`](resultats/tsa-essais.log)) :
- **jeton témoin** demandé depuis l'espace `horodatage` : vérifié par `timestamp-cli` dans le pod et **par openssl sur l'hôte** avec la racine TSA (politique `1.3.6.1.4.1.57264.2`, sha256, précision 1 s, nonce, TSA « TSA du PoC ») ; refusé sur un autre contenu (« message imprint mismatch ») et avec la CA TLS du PoC ; la chaîne servie est la chaîne émise ;
- **TSA injoignable** depuis un autre espace (15 essais) ;
- **OpenBao** : le rôle `tsa` signe avec la clé `tsa` et renouvelle son jeton. **7 refus** : clé `chains` (signature, lecture) ; clé `tsa` (export, passage en exportable, sauvegarde en clair) ; lecture de son propre jeton ; clé `tsa` avec le rôle `tekton-chains`. **2 connexions croisées refusées** (« invalid subject (sub) claim »). Chaque appel figure dans l'audit avec son compte ;
- **Zot** : `poc-horodatage` écrit dans `horodatage/`, et il est refusé dans `builds/` et `amont/` ; écriture anonyme refusée (401).

**Contrôle de J5 et test 8 : mesure des chemins de vérification** ([`tsa-chemins.log`](resultats/tsa-chemins.log)). Les cas falsifiés sont construits à partir des bundles du job et publiés dans `essais-j5/*` :

| Cas | cosign v3.1.4 : bundle en dépôt séparé, `--use-signed-timestamps`, racine de confiance du TSA | Kyverno 1.19.2 en CLI : attestor à clé, `insecureIgnoreTlog`, `tsaCertChain` |
|---|---|---|
| Jeton valide | **Accepté** | **`error`** : « nil pointer dereference ». Sans `tsaCertChain`, le même bundle passe (témoin) |
| Aucun bundle | Refusé | Refusé |
| Bundle sans jeton | Refusé : 0 jeton vérifié pour 1 exigé | Refusé |
| Jeton altéré (dernier octet de la signature du TSA) | Refusé : `x509: ECDSA verification failure` | Non mesuré : le cas valide échoue déjà |
| Jeton valide d'une autre signature de Chains | Refusé : `hashed messages don't match` | Non mesuré |
| Jeton d'une TSA étrangère (même forme, même CN) | Refusé : le certificat du jeton n'est pas celui du TSA | Non mesuré |
| **Chemin historique** : `.att` de Chains, sans jeton | **Accepté**, malgré `--use-signed-timestamps` | Refusé, même sans `tsaCertChain` : « cosign bundle verification failed » |

**Constats** :
- **cosign, chemin historique** : sur une attestation `.att`, `--use-signed-timestamps` n'exige pas de jeton (`VerifyRFC3161Timestamp` renvoie `nil, nil` quand il manque). Y ajouter un jeton réécrirait en plus le tag `.att`, donc rouvrirait la course du constat de J4. **Écarté.**
- **Kyverno 1.19.2 renvoie une erreur interne sur un jeton valide**, avec un attestor à clé sans journal. Une erreur interne n'est pas une décision : **Kyverno ne peut pas assurer le contrôle 9** dans cette configuration. Le CLI et l'admission partagent ce code (`pkg/image/verifiers/ivpol/cosign`) ; la parité se mesure en J6. **Cause, lue dans le code** (à la demande du propriétaire) :
  - avec une clé et `insecureIgnoreTlog`, Kyverno ne construit pas de matériel de confiance (`TrustedMaterial` nil), et il n'y ajoute la chaîne TSA que si ce matériel existe (`opts.go` l. 176) ;
  - cosign v3.1.4 enveloppe ce `TrustedMaterial` nil dans `verifyTrustedMaterial` (`pkg/cosign/verify.go`) ;
  - sigstore-go v1.3.0 n'appelle `TimestampingAuthorities()` que pour un jeton présent dans le bundle (`pkg/verify/tsa.go` l. 93). L'appel sur l'interface nil explique le plantage sur un jeton valide, et le refus propre d'un bundle sans jeton ;
  - cosign en CLI ne plante pas, car `--trusted-root` lui donne ce matériel ;
  - **aucun ticket trouvé chez Kyverno pour ce cas.** Le correctif en brouillon kyverno/kyverno#16048 ne couvre que le chemin keyless (matériel issu du TUF). Pas de ticket ouvert : décision du propriétaire.
- **Kyverno 1.19.2 ne vérifie aucune attestation au format historique sans journal** : `verifyAttestationSignatures` exige une preuve d'inclusion dans un journal, alors que `verifyImageSignatures` s'en passe avec `insecureIgnoreTlog` (`verifier.go`). **Défaut connu** : tickets kyverno/kyverno#17109 et #18054, correctif #17217 ouvert, non fusionné au 29/10/2026 ; même code sur la branche principale. **Pour J6**, la provenance de Chains (`dsse`) n'est lisible par Kyverno qu'à travers les bundles réémis (témoin : `pass`) : le job d'horodatage sert aussi de pont entre Chains et Kyverno.
- **kube-router, côté entrée** : le TSA a d'abord refusé (« connection refused ») un job neuf, car sa NetworkPolicy ne connaissait pas encore l'IP du pod. Le job attend désormais Zot et le TSA.
- **Même délai pour l'EventListener de J4.** Au premier rejeu de J1 à J5, Forgejo a reçu « connection refused » sur le NodePort de l'EventListener, à la seconde où celui-ci devenait disponible. Forgejo n'a pas relivré : l'EventListener n'a reçu aucune requête dans les 2 min suivantes, et le test 5 a échoué faute de PipelineRun. Le rejeu précédent n'avait rien montré : l'étape avait duré 44 s, contre 5 s cette fois. `tekton.sh webhook` attend désormais que la sonde `/live` réponde depuis `sc-stockage`. En production, la même course ferait perdre un push : **traité en J6** par un rattrapage périodique (Forgejo ne relivre jamais, lu dans son code ; voir « Rattrapage des webhooks perdus »).
- **Renouvellement du jeton du TSA : deux défauts corrigés après le rejeu.**
  - Au redémarrage des VM, l'arrêt a pris 93 s au lieu de 4 s. systemd a dû tuer le conteneur de renouvellement au bout de son délai de 90 s : `sh`, PID 1 du conteneur, ignorait SIGTERM pendant son `sleep`. Le script gère désormais SIGTERM, et le pod se supprime en 2 s.
  - En relisant ce conteneur, il est apparu que sa commande (`bao token renew -field=…`) était invalide, comme l'essai l'avait montré à part. **Le TSA aurait cessé de signer au bout d'1 h.** Le conteneur renouvelle désormais dès son démarrage, et `deployer` exige la trace « jeton renouvelé : 3600 s ».
- **Débit amont et cache OCI** : au second rejeu de J1 à J5, Zot a coupé un envoi de l'image OpenBao (« i/o timeout ») pendant une copie en flux de ghcr.io vers Zot, alors que le débit de ghcr.io était tombé à 0,7 Mo/s (76 Mo en 102 s). Les copies des images amont (OpenBao, Tekton, TSA, cosign) passent désormais par un **cache OCI local** (`…/08/telechargements/oci`, fonction `miroir` de [`commun.sh`](commun.sh)) : téléchargement une seule fois, par digest, puis envoi à Zot sur le réseau local. Le rejeu ne dépend plus du registre amont, sauf pour les vérifications de signature, qui restent faites en ligne puis sur la copie de Zot.
- **Zot** : oras n'écrit pas un blob déjà présent, et l'opération réussit même sans droit d'écriture. Les essais de refus utilisent donc un contenu neuf, plus un contrôle direct en HTTP 401.
- **Conforma v0.10.42** : aucune option d'horodatage dans `ec validate image` ; non mesuré, à reprendre en J8.

**Choix du chemin de vérification : décision du propriétaire (29/10/2026), sur ces mesures.** Retenu :
- **stockage** : bundle réémis dans un dépôt séparé. C'est le format natif de Sigstore, sans réécriture de `.att` ;
- **contrôle 9** : vérifié par cosign v3.1.4 dans la porte de release. `tools/verify-ts` se réduit alors à un appel de cosign, sans code cryptographique maison ;
- **à l'admission** : Kyverno vérifie la signature des bundles, mais pas leur horodatage tant que l'erreur n'est pas corrigée ; aucun ticket amont (décision du propriétaire).

Le propriétaire a aussi tranché la lecture de C-1 pour la décision C : un contrôle 9 vérifié hors du moteur de politique compte (notes du banc C mises à jour, voir l'ADR 0000). Écarté : un `tools/verify-ts` écrit en Go, qui n'apporte rien de mesuré sur cosign, et l'attente d'un correctif de Kyverno.

**Limites** :
- l'heure des jetons est celle de la VM ;
- jeton OpenBao périodique d'1 h : si OpenBao reste scellé plus d'1 h, le TSA ne signe plus jusqu'à la recréation de son pod ;
- le job n'est pas déclenché automatiquement après Chains : **traité en J6** (réconciliation périodique) ;
- un bundle porte sur un digest : il couvre toutes les images de même digest ;
- `poc-horodatage` peut ajouter des bundles et réétiqueter les siens, mais pas en supprimer ; un faux bundle échoue à la vérification (signature de Chains et jeton) ;
- l'image d'outils n'est pas signée, et la signature de sa base ne la lie pas à un tag ;
- la clé de la racine TSA est sur l'hôte, comme celle de la CA du PoC ; en production, elle serait hors ligne ou dans un HSM ;
- une seule instance du TSA, en HTTP ;
- cas non mesuré, à reprendre en J8 : un bundle valide d'un **autre digest** rattaché à l'image par `poc-horodatage`. sigstore-go devrait le refuser (le digest du sujet est imposé à la vérification), mais aucun essai ne le prouve encore.
