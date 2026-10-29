# Brique 08 : plan de confiance sur k3s

Seuil (README, brique 08) : Tekton + HMAC, Chains (stockage prouvé), OpenBao, job TSA (chemin de vérification choisi), Trusted Resources, Kyverno, Conforma, RBAC, nœuds dédiés, posture des pipelines ; **les 8 tests négatifs du doc 01 échouent comme attendu**, chacun avec une trace.

On termine aussi le banc C : contrôle 9 (horodatage RFC 3161), C-2 (parité entre CLI et admission), et bibliothèque Conforma `slsa3` / `trusted_task` sur une vraie provenance Chains.

**Effort estimé : 5,5 pw.** Une décision avec le propriétaire est déclenchée à 11 pw. Le temps passé est relevé jalon par jalon dans `resultats/chrono.tsv`, ouvert à l'accord.

**Statut (29/10/2026) : J1 à J4 faits** (3 VM et k3s v1.35.9 ; Zot et Forgejo sur `sc-stockage`, CA du PoC ; OpenBao, clé Transit de Chains ; Tekton Pipelines, Chains et Triggers installés depuis Zot, chaîne de signature éprouvée, webhook Forgejo signé et anti-rejeu ; voir plus bas). La construction de sample-app dans un pod passe en J7, avec Kata (décision du propriétaire). J5 (horodatage) attend l'accord du propriétaire.

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
| J4 | Orchestration | Tekton Pipelines, Chains (`slsa/v2alpha4`, `dsse`, KMS `hashivault://`), Triggers et intercepteur HMAC Forgejo avec anti-rejeu | Premier PipelineRun de sample-app : provenance signée dans Zot, vérifiée par cosign ; **contrôle modifié le 29/10/2026 (option C du propriétaire)** : chaîne de signature prouvée par un essai et PipelineRun déclenché par un webhook Forgejo signé, sans construction, qui passe en J7 |
| J5 | Horodatage | timestamp-authority (clé séparée), job TSA hors des pods de build, **choix du chemin de vérification** : bundle réémis (`tsaCertChain` de Kyverno) ou `tools/verify-ts` | Jeton valide accepté ; jeton absent ou falsifié refusé |
| J6 | Politique | Trusted Resources (bundles de tâches signés), Kyverno (admission), Conforma (porte), RBAC, posture des pipelines (tekton-lint) | Politiques du banc C chargées à l'admission |
| J7 | Isolation | Kata 4.3.1 sur `sc-build` (RuntimeClass), avec CPU des invités vérifié ; **construction de sample-app** (BuildKit rootless dans un pod Kata, reportée de J4 le 29/10/2026) | Pod Kata en x86-64-v3 ; pod privilégié hors Kata refusé ; PipelineRun de sample-app qui construit l'image depuis Forgejo, provenance signée vérifiée par cosign, digest comparé à `3a7ca1b1…` |
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

- ~~**Signature des webhooks de Forgejo** et anti-rejeu~~ : **vérifié en J4**. Forgejo v15.0.11 envoie `X-Hub-Signature-256: sha256=<hmac>` (HMAC-SHA256 du corps), que l'intercepteur GitHub de Triggers v0.37.2 exige ; les en-têtes de livraison ne sont pas signés. Anti-rejeu sans intercepteur maison : le nom du PipelineRun dérive du commit signé (voir « Jalon J4 »).
- ~~**Authentification de Chains auprès d'OpenBao** par le jeton du compte de service (méthode JWT d'OpenBao, avec la clé publique de l'émetteur de comptes de service de k3s)~~ : **vérifié en J3** dans le code de Chains v0.29.9. `signers.kms.auth.oidc.path`, `.role` et `.token-path` suffisent, sans SPIRE, et le signataire KMS est recréé à chaque signature (voir « Jalon J3 »).
- **`internalParameters`** (`hermetic`, `isolation`, `cpuModel`) inscrits **par la plateforme**, pas par le code de build (doc 02 §3).
- **Sujet non-image** (rpm via ORAS, `isBuildArtifact: true`) : déduit du code de Chains (doc 00), à tester.
- **Vérification d'un jeton RFC 3161 séparé par Kyverno** (non documentée) et support des bundles Sigstore par Conforma (doc 00).
- Visibilité des pods Kata pour la NetworkPolicy et pour la trace NFLOG (Kata imbriqué).

## Changements sur l'hôte

J1 validé et fait le 29/10/2026 (téléchargements, pool, réseau, VM, k3s). Les jalons suivants restent soumis à accord.

| Changement | Détail |
|---|---|
| Téléchargements | Image Debian (439 Mo), `SHA512SUMS` et manifeste ; k3s et ses images airgap (272 Mo) ; puis, jalon par jalon, les manifestes et images listés plus haut. Tout va dans `~/.cache/supply-chain-poc/08/` |
| Pool libvirt | `supply-chain-poc`, `/var/lib/libvirt/supply-chain-poc` (sur `/`) |
| Réseau libvirt | NAT `supply-chain-poc`, `virbr-scpoc`, 192.168.161.0/24, sans démarrage automatique |
| VM | `sc-confiance`, `sc-build`, `sc-stockage` (12 vCPU, 24 Gi, 65 Go), sans démarrage automatique |
| Dans les VM | k3s, puis les composants des jalons J2 à J7. Kata (J7) est soumis à un accord séparé. J2 : sur `sc-stockage`, **git et 9 dépendances par apt** (versions épinglées, accord du propriétaire du 29/10/2026), Zot et Forgejo en services systemd (comptes système `zot` et `forgejo`) ; sur les trois nœuds, `registries.yaml` et la CA du PoC dans `/etc/rancher/k3s` |
| Outils de l'hôte (`mise.toml`) | J2 : kubectl 1.35.10 à la place de 1.37.2 |
| Cache de l'hôte | J2 : `~/.cache/supply-chain-poc/08/pki` (certificats publics) ; dans `…/08/secrets` (0600) : clés de la CA et des services, mot de passe du compte d'écriture de Zot, mot de passe et jeton de l'administrateur de Forgejo |
| J4 | Dans le cluster : Tekton Pipelines, Triggers (espaces `tekton-pipelines`, `tekton-pipelines-resolvers`) et Chains (`tekton-chains`), espace `builds` ; dans Zot : manifestes linux/amd64 des 13 images Tekton et du busybox sous `amont/`, dépôt d'essai `builds/essai-signature` ; dans `…/08/secrets` : mot de passe du compte Zot `poc-build` ; `~/.cache/supply-chain-poc/08/telechargements/tekton` : release.yaml des deux sources |
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
- **Trois VM** (`mise run confiance:redemarrer`, [`redemarrage-vm.log`](resultats/redemarrage-vm.log)), comme après un redémarrage du laptop. Arrêt propre en 4 s, démarrage jusqu'à SSH en 9 s, trois nœuds réenregistrés (nouveau `bootID`) en 14 s. Zot et Forgejo repartent seuls (unités `enable`) et restent lisibles (manifeste sample-app par digest, branche `main`). OpenBao revient scellé ; `deverrouiller` le descelle, et le témoin se vérifie avec la même clé. Constat : juste après le démarrage, l'API garde l'état d'avant (nœuds `Ready`, pods prêts) tant que les kubelets ne se sont pas réenregistrés. Le script attend donc un nouveau `bootID` ; un premier essai, qui ne l'attendait pas, avait lu cet état périmé.

**RAM au repos après J3** (6 min après le rejeu, [`controles-j3-repos.log`](resultats/controles-j3-repos.log)) : RSS QEMU de 2,7 Go (`sc-confiance`, OpenBao compris), 2,1 Go (`sc-build`) et 3,1 Go (`sc-stockage`), soit **7,8 Go** au total (7,0 Go après J2, 6,0 Go après J1). Mémoire vue par k3s : 663, 255 et 393 Mi ; 23,2 Gi (23 779 Mi) restent disponibles sur l'hôte. Dans `sc-stockage`, 2,0 Gi sont du cache de pages (la copie multi-plateforme de l'image OpenBao s'y ajoute).

**Contrôle des fuites** ([`fuites-j1-j3.log`](resultats/fuites-j1-j3.log)) : 13 secrets, **0 occurrence** dans les journaux des trois VM, journaux des pods et **journal d'audit d'OpenBao** compris (lu sur le volume local-path) ; témoins retrouvés.

**Limites et constats.**
- **J3 prouve l'identité, la politique et la clé, pas encore le chemin de Chains lui-même.** Il sera validé en J4 : `signers.kms.kmsref: hashivault://chains`, `signers.kms.auth.address`, `oidc.path: jwt`, `oidc.role: tekton-chains`, `oidc.token-path` vers un jeton projeté d'audience `openbao`, CA du PoC (`VAULT_CACERT`), contrôleur sur `sc-confiance`.
- **`exportable=true` est irréversible et reste à la portée de l'administrateur** : quiconque détient le jeton root, ou la clé de descellement (qui permet d'en régénérer un), peut rendre la clé exportable. La garantie vaut contre tout le monde, sauf l'administrateur. Les essais ne demandent jamais cette modification avec le jeton root. Le jeton root reste sur l'hôte. Durcissement possible : le révoquer après la configuration et le régénérer au besoin (`operator generate-root`).
- **`bound_subject` seul** : tout pod qui tourne sous le compte de service de Chains, et quiconque peut créer `serviceaccounts/token` pour lui, obtient des signatures. La NetworkPolicy admet de même tout pod de l'espace `tekton-chains`. **À traiter en J6** : RBAC sur la création de pods, `exec`, `portforward` et `serviceaccounts/token` dans `tekton-chains` et `openbao` ; règle Kyverno qui garde les pods de `tekton-chains` en zone confiance. C'est le mécanisme du test 1.
- **La NetworkPolicy ne protège pas d'un accès depuis le nœud** : la chaîne de kube-router du pod `openbao-0` accepte, avant la politique, tout trafic dont la source est le nœud local (`--src-type LOCAL -j ACCEPT`). Un pod en `hostNetwork` placé sur `sc-confiance`, ou tout processus de ce nœud, joint donc OpenBao, quel que soit son espace de noms. Il lui faut encore un jeton accepté par le rôle JWT, mais la barrière réseau ne joue pas. **À traiter en J6** : la règle Kyverno du test 4 interdit aussi `hostNetwork` (et `hostPID`, `hostIPC`) hors des espaces système.
- **kube-router applique la NetworkPolicy à un pod neuf avec un délai** : sa première connexion est rejetée (REJECT, donc `connection refused`, pas un délai dépassé) pendant environ 1 s, le temps que kube-router ajoute son IP. Les scripts d'essai attendent. Pour Chains, à vérifier en J4 : une première signature juste après le démarrage du contrôleur peut échouer et doit être réessayée.
- tcpdump ne sait pas filtrer l'interface NFLOG (« link-layer type filtering not implemented ») : on filtre après la capture.
- Le volume local-path est en 0777 sur le nœud ; les données d'OpenBao y sont chiffrées par la barrière, et `audit.log` est en 0600.

## Jalon J4 : Tekton, Chains, Triggers (29/10/2026)

**Décisions du propriétaire (29/10/2026)** :
- les `release.yaml` et les images de Tekton Pipelines, Chains et Triggers, non vérifiables (doc 04 §5), sont **épinglés par digest après revue**. La reconstruction depuis les tags relève de la brique 11 ;
- **option C pour la construction de sample-app** : J4 se clôt avec la chaîne de signature prouvée par un essai, Triggers et le webhook Forgejo ; la vraie construction passe en **J7**, avec BuildKit rootless dans un pod Kata sur `sc-build`, sans relâcher seccomp ni AppArmor, en visant le digest `3a7ca1b1…` de la brique 04. Les options écartées : BuildKit en pod dès J4 (seccomp et AppArmor relâchés jusqu'à J7), ou une construction sans démon avec un outillage maison.

Rejeu : `mise run confiance:tekton -- revue miroir installer signature verifier webhook essais_webhook`. Journaux : `resultats/tekton-<étape>.log` ([revue](resultats/tekton-revue.log), [miroir](resultats/tekton-miroir.log), [installer](resultats/tekton-installer.log), [signature](resultats/tekton-signature.log), [verifier](resultats/tekton-verifier.log)) ; images : [`tekton-images.tsv`](resultats/tekton-images.tsv) ; correctifs dans [`tekton/`](tekton/).

| Étape | Durée | Résultat |
|---|---|---|
| `revue` | 17 s | **Les quatre `release.yaml`** (Pipelines v1.15.5, Chains v0.29.9, Triggers v0.37.2 et ses intercepteurs) sont **identiques sur GitHub et sur infra.tekton.dev**, et égaux aux digests des assets publiés par GitHub ; leurs sha256 sont épinglés dans [`tekton.sh`](tekton.sh). **Les 13 images Tekton** y sont déjà référencées par tag et digest : chaque digest est **celui du tag dans le registre**, et le manifeste linux/amd64 est listé dans l'index épinglé. Deux images tierces : l'image shell `cgr.dev/chainguard/busybox` (signée, mais par une identité `distroless/busybox` que seule la lecture du certificat révèle) est **remplacée par le busybox 1.37.0 des images airgap de k3s** (digest d'index `101b4afd…` identique sur le nœud et sur docker.io) ; `powershell:nanoserver` ne sert qu'aux nœuds Windows. Revue des droits et des webhooks : voir plus bas |
| `miroir` | 64 s | 14 manifestes linux/amd64 copiés dans Zot sous `amont/` et relus par digest. On ne copie pas les index complets : `entrypoint` et `nop` contiennent des couches Windows |
| `installer` | 36 s | Manifestes **réécrits vers Zot**, puis contrôleurs, webhooks et résolveurs **placés sur `sc-confiance`** (kustomize). Il ne reste dans les manifestes rendus aucune référence d'image externe, hormis `powershell` et un texte de documentation d'une CRD. **Les 8 images réellement tirées viennent toutes de `sc-stockage.poc.test:5000/amont/`** (`imageID` des conteneurs). Chains : `slsa/v2alpha4`, signataire KMS `hashivault://chains`, `oidc.token-path` vers un jeton projeté d'audience `openbao`, `VAULT_CACERT` et `SSL_CERT_FILE` sur la CA du PoC, stockage OCI en `dsse` (tags `.sig`/`.att`), sans transparence publique ; `builder.id` et `buildType` sont ceux des politiques du banc C |
| `signature` | 10 s | **Essai de la chaîne de signature, pas un build.** Un TaskRun sur `sc-build` publie seulement `IMAGE_URL`/`IMAGE_DIGEST` d'une image poussée depuis l'hôte (sample-app de la brique 04, dans `builds/essai-signature`). Chains signe via OpenBao, pousse `.sig` et `.att` dans Zot avec le compte `poc-build`, et annote le TaskRun `chains.tekton.dev/signed=true`, sans erreur au premier essai |
| `verifier` | < 1 s | Sur l'hôte, avec la clé publique de Transit (`chains-cle-publique.pem`) : **signature de l'image vérifiée** (`cosign container image signature`, digest `3a7ca1b1…`) ; **attestation SLSA v1 vérifiée** (`verify-attestation --type slsaprovenance1`) ; **une autre clé est refusée**. Audit d'OpenBao : connexion JWT de `tekton-chains-controller`, lecture de la clé, deux signatures, sous la seule politique `chains-signature` |
| `webhook` | 4 s | Secret HMAC aléatoire (0600 sur l'hôte, secret Kubernetes `forgejo-webhook`). Task `publier-essai` et Pipeline `sample-app-essai` (objets, pas de spec en ligne), TriggerTemplate, EventListener `forgejo` sur `sc-confiance` (NodePort, joignable depuis Forgejo car 192.168.161.0/24 est autorisé), intercepteurs GitHub (HMAC, événement `push`) puis CEL (branche `main`, dépôt `workspace/sample-app`, commit de 40 caractères hexadécimaux). Webhook Forgejo créé par l'API, secret passé par fichier |
| `essais_webhook` | 20 s | Test 5, voir ci-dessous |

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

**Limites du webhook** :
- **l'anti-rejeu dure tant que le PipelineRun existe** : un nettoyage des PipelineRuns rouvre la possibilité de rejouer une livraison. Il n'y a pas d'horodatage signé dans les événements `push` ;
- **le commit n'est pas encore confronté à Forgejo** : quiconque détient le secret du webhook fait signer par Chains une provenance pour un commit arbitraire (essai E : commit `2222…` inexistant). La construction de J7 récupérera les sources par ce commit depuis Forgejo, ce qui fera échouer un commit inexistant ;
- l'EventListener écoute en HTTP (le HMAC protège l'intégrité, pas la confidentialité du contenu, qui n'est pas secret) ; il tourne dans l'espace `builds`, et son compte de service lit les `secrets` du cluster (`tekton-triggers-eventlistener-clusterroles`). RBAC à resserrer en J6.

**Revue des droits** (ClusterRoles des `release.yaml`, toutes liées au niveau du cluster) :
- les contrôleurs de **Pipelines et de Chains lisent tous les `secrets` du cluster** (`tenant-access`), et Chains peut aussi créer et supprimer des pods. Chains en a besoin pour lire les identifiants de registre des TaskRuns ; c'est un point à garder en tête : un Chains compromis lit tous les secrets ;
- le résolveur de Pipelines lit tous les `secrets` ; les intercepteurs de Triggers aussi, et ne peuvent modifier que leur propre secret de certificat (`resourceNames`) ;
- `tekton-triggers-eventlistener-roles` (droit `impersonate` sur les comptes de service) n'est lié à rien par les releases : il le sera par les EventListeners ;
- les six webhooks d'admission sont en `failurePolicy: Fail` et sans effet de bord.

**Constats sur la provenance de l'essai** ([`tekton-verifier.log`](resultats/tekton-verifier.log)) :
- **`resolvedDependencies` attribue l'image d'étape à `docker.io`** (`oci://docker.io/rancher/mirrored-library-busybox`, digest d'index `101b4afd…`) alors qu'elle a été tirée de Zot (manifeste amd64 `ad9fa4d0…`). Ce busybox existait déjà sur le nœud par les images airgap de k3s, et containerd rapporte le nom et le digest de son magasin local. **L'origine inscrite dans la provenance dépend de ce que le nœud contient déjà** : le contrôle « dépendances depuis Zot » du banc C doit en tenir compte, et les images d'étape de la plateforme ne doivent exister que dans Zot ;
- **`internalParameters` ne contient que les drapeaux de Tekton** (`enforceNonfalsifiability: none`, `verificationNoMatchPolicy: ignore`, etc.). Les paramètres de plateforme prévus (`hermetic`, `isolation`, `cpuModel`) restent à inscrire (point à vérifier, doc 02 §3) ;
- **chaque exécution d'un TaskRun de même sujet ajoute une enveloppe** sous le même tag `.att` (deux après deux essais) ;
- le compte `poc-build`, utilisé par Chains pour pousser, a le droit `update` : il peut **écraser les tags `.sig` et `.att`**. Ce n'est pas une falsification, la vérification échouerait, mais c'est une suppression de preuve. À traiter avant J8.

**Pour J6** : les cinq résolveurs sont actifs (`bundles`, `cluster`, `git`, `http`, `hub`) et peuvent chercher des définitions de tâches hors de la plateforme ; l'essai utilise un `taskSpec` en ligne, que le test 2 doit refuser.
