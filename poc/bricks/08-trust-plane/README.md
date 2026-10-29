# Brique 08 : plan de confiance sur k3s

Seuil (README, brique 08) : Tekton + HMAC, Chains (stockage prouvé), OpenBao, job TSA (chemin de vérification choisi), Trusted Resources, Kyverno, Conforma, RBAC, nœuds dédiés, posture des pipelines ; **les 8 tests négatifs du doc 01 échouent comme attendu**, chacun avec une trace.

On termine aussi le banc C : contrôle 9 (horodatage RFC 3161), C-2 (parité entre CLI et admission), et bibliothèque Conforma `slsa3` / `trusted_task` sur une vraie provenance Chains.

**Effort estimé : 5,5 pw.** Une décision avec le propriétaire est déclenchée à 11 pw. Le temps passé est relevé jalon par jalon dans `resultats/chrono.tsv`, ouvert à l'accord.

**Statut (29/10/2026) : J1, J2 et J3 faits** (3 VM et k3s v1.35.9 ; Zot et Forgejo sur `sc-stockage`, CA du PoC ; OpenBao, clé Transit de Chains ; voir plus bas). J4 (Tekton, Chains, Triggers) attend l'accord du propriétaire et la décision sur les images non vérifiables.

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
- **RAM au repos** (6 min après l'installation, [`controles-j1-repos.log`](resultats/controles-j1-repos.log)) : RSS QEMU de 2,5 Go (`sc-confiance`), 1,8 Go (`sc-build`) et 1,6 Go (`sc-stockage`), soit **6,0 Go** au total ; mémoire vue par k3s : 593, 250 et 234 Mi ; 25,6 Gi restent disponibles sur l'hôte.

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

Rejeu (après J1) : `mise run confiance:stockage -- pki zot registre containerd forgejo depot`. Journaux : `resultats/stockage-<étape>.log` ([pki](resultats/stockage-pki.log), [zot](resultats/stockage-zot.log), [registre](resultats/stockage-registre.log), [containerd](resultats/stockage-containerd.log), [forgejo](resultats/stockage-forgejo.log), [depot](resultats/stockage-depot.log)) ; configuration dans [`stockage/`](stockage/).

**Rejeu complet de J1 et J2 depuis zéro** (`detruire`, `creer`, `k3s`, puis les six étapes ; téléchargements et CA en cache) : **109 s**, dont 1 s de démontage, 23 s de VM, 39 s de k3s et **46 s pour J2** ([`rejeu-j1-j2.log`](resultats/rejeu-j1-j2.log), horodatages epoch ; durées par étape dans `chrono.tsv`). Il a fallu trois rejeux : les deux premiers ont révélé les défauts décrits dans les constats, et leurs journaux n'ont pas été archivés (écrasés par le rejeu suivant).

| Étape | Durée | Résultat |
|---|---|---|
| `pki` | < 1 s | CA ECDSA P-256, 365 jours, `pathlen:0`, **contraintes de nom** : `poc.test`, `svc.cluster.local` (services du cluster, pour J3 à J5), 192.168.161.0/24 et 10.43.0.0/16 ([`pki.cnf`](stockage/pki.cnf)). Empreinte sha256 `D6:8A:15:A3:…:37:72:0A`. Un certificat et une clé par service (Zot, Forgejo), 180 jours, SAN `sc-stockage.poc.test` et 192.168.161.13. **Un certificat pour `registre.exemple.org` signé par la CA est refusé** à la vérification (« permitted subtree violation ») |
| `zot` | 5 s | Binaire de `mise.toml` **revérifié dans la VM** (sha256 de `mise.lock`) ; compte système `zot` ; unité durcie (`systemd-analyze security` : 3.0, « OK ») ; TLS sur 192.168.161.13:5000 ; **lecture anonyme, écriture par le seul compte `poc-ecriture`** (htpasswd bcrypt, coût 12, calculé par `mkpasswd` sur l'entrée standard), **sans droit de suppression** ; ramasse-miettes désactivé (`gc: false`, comme la brique 03) : un manifeste poussé par digest, sans tag, ne doit pas disparaître ; journal d'audit des écritures |
| `registre` | 8 s | **Push par digest** de l'image sample-app `3a7ca1b1` de la brique 04 depuis l'hôte, relecture anonyme du manifeste, **pull anonyme par digest aux blobs identiques**. Refus : ouverture d'un envoi sans identifiants (HTTP 401), push anonyme, push avec un mauvais mot de passe (401), **suppression par `poc-ecriture` (403)**, lecture sans la CA du PoC (x509). Les refus 401 et 403 figurent dans le journal de Zot, `Authorization` masqué |
| `containerd` | 18 s | **Pull refusé sur `sc-build` sans la CA** (x509). Puis CA et [`registries.yaml`](stockage/registries.yaml) sur les trois nœuds, sans identifiant, redémarrés un par un (`Ready` vérifié entre chaque) ; `hosts.toml` régénéré par k3s. **Pull par digest dans un pod de `sc-build`** (toleration du taint de zone) : `imageID` = `sc-stockage.poc.test:5000/workspace/sample-app@sha256:3a7ca1b1…`, 362 ms. `sc-stockage.poc.test` résolu **depuis un pod** (CoreDNS, puis dnsmasq du réseau libvirt) |
| `forgejo` | 11 s | **git 2.47.3 et 9 dépendances par apt** (versions épinglées, dépôts Debian signés ; accord du propriétaire du 29/10/2026). Binaire Forgejo de `mise.toml` (GPG vérifié sur l'hôte) **revérifié dans la VM** ; compte système `forgejo` ; unité durcie (3.0, « OK ») ; HTTPS sur 192.168.161.13:3000, sqlite, ni SSH, ni inscription (« Registration is disabled »), ni Actions, ni paquets, ni OAuth2 ; webhooks limités à 192.168.161.0/24. **`app.ini` sans secret** ([`forgejo.ini`](stockage/forgejo.ini)) : les trois secrets sont générés dans la VM et lus par `*_URI = file:` ; Forgejo ne modifie pas `app.ini` (sha256 identique au fichier versionné). Administrateur `poc-admin` créé avec `--random-password`, mot de passe capté dans un fichier 0600 de l'hôte sans affichage ; jeton limité à `write:organization` et `write:repository` |
| `depot` | 4 s | Organisation `workspace`, dépôt public **`workspace/sample-app`** : sources de `poc/sample-app` à HEAD, commit à auteur et date fixes, **`6391fd43…` à chaque rejeu** ; arbre `30e808ff…` = `poc/sample-app` à HEAD. Création d'organisation sans jeton : 401 ; **push sans jeton : 401** (journal de Forgejo). Lecture anonyme depuis l'hôte, et **depuis `sc-build`** par le nom DNS et la CA déclarée aux nœuds : même commit |

**RAM au repos après J2** (6 min après le rejeu, [`controles-j2-repos.log`](resultats/controles-j2-repos.log)) : RSS QEMU de 2,4 Go (`sc-confiance`), 1,9 Go (`sc-build`) et **2,7 Go (`sc-stockage`, contre 1,6 Go en J1)**, soit **7,0 Go** au total (6,0 Go en J1). Dans `sc-stockage`, 669 Mi sont utilisés et 1,6 Gi servent de cache de pages (paquets apt, image poussée, dépôt git) : le RSS QEMU compte ce cache une fois qu'il a été touché. Mémoire vue par k3s : 547, 250 et 388 Mi ; 24,6 Gi restent disponibles sur l'hôte. Les autres contrôles de J1 restent valables : x86-64-v3 sans v4, aucun AVX-512, `vmx` sur les 6 vCPU de `sc-build`, sortie NAT, 33 règles `KUBE-ROUTER`.

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

Rejeu (après J2) : `mise run confiance:openbao -- image deployer initialiser configurer essais` ; après un redémarrage du pod ou de la VM : `-- deverrouiller`. **Rejeu complet de J1 à J3** : `mise run confiance:rejeu`. Journaux : `resultats/openbao-<étape>.log` ([image](resultats/openbao-image.log), [deployer](resultats/openbao-deployer.log), [initialiser](resultats/openbao-initialiser.log), [configurer](resultats/openbao-configurer.log), [essais](resultats/openbao-essais.log)) ; configuration dans [`openbao/`](openbao/) ; fonctions communes aux jalons dans [`commun.sh`](commun.sh).

**Vérification préalable : comment Chains s'authentifie.** Le protocole prévoyait l'authentification JWT par le jeton du compte de service, sans l'avoir vérifiée. Le code de Chains v0.29.9 (tag `89219ea5`, `pkg/chains/signing/kms/kms.go`) le confirme :
- `signers.kms.auth.oidc.path`, `.role` et `.token-path` suffisent, **sans SPIRE**. Sans `token-path`, Chains lit le jeton du compte de service monté dans le pod ;
- `allSigners()` recrée le signataire KMS **à chaque `Sign()`** : le jeton est relu et la connexion JWT refaite pour chaque objet signé. La rotation des jetons projetés ne pose donc pas de problème, et chaque signature consomme un jeton batch ;
- le client hashivault de sigstore v1.10.9 n'utilise que `auth/<chemin>/login`, `transit/keys/<clé>` (lecture de la clé publique) et `transit/sign/<clé>/<hash>` avec `prehashed`. La politique se limite à ces chemins.

**Rejeu complet depuis zéro** ([`rejeu-j1-j3.log`](resultats/rejeu-j1-j3.log)) : **219 s**, dont 17 s de VM, 38 s de k3s, 47 s pour J2 et **115 s pour J3** ; puis contrôle des fuites.

| Étape | Durée | Résultat |
|---|---|---|
| `image` | 42 s | Index `ghcr.io/openbao/openbao@sha256:5046911…` (tag 2.7.2, 6 plateformes ; linux/amd64 `a78eb12a…`). **Signature sans clé vérifiée par identité exacte** : `release-images.yml@refs/tags/v2.7.2`, commit `9e0a0d3c` (celui du tag), déclencheur `release`, présence dans Rekor. **Une identité voisine (tag v2.7.1) est refusée.** Copie dans Zot avec ses referrers (`oras cp -r` : 4 bundles sigstore), puis **signature revérifiée sur la copie de Zot** ; les pods tirent l'image de Zot par digest |
| `deployer` | 8 s | StatefulSet d'un réplica sur `sc-confiance`. Pod non root (uid 100), sans capability, racine en lecture seule, Pod Security « restricted », **aucun jeton Kubernetes monté**. Raft sur un PVC local-path. TLS 1.3 avec un certificat de la CA du PoC pour `openbao.openbao.svc.cluster.local` : la forme courte `openbao.openbao.svc` sortirait des contraintes de nom de la CA. Sonde de disponibilité `bao status`, sans sonde de vie : un OpenBao scellé n'est pas redémarré en boucle. **NetworkPolicy** : entrée sur 8200 depuis l'espace `tekton-chains` seulement, aucune sortie. `bao version` affiche le commit du tag |
| `initialiser` | 17 s | État lu dans OpenBao (`sys/init`, `sys/seal-status`), pas dans les fichiers de l'hôte. Une part de descellement ; jeton root et clé de descellement en 0600 sur l'hôte, un secret par fichier, jamais affichés. Descellement par l'entrée standard de `kubectl exec` (`sys/unseal key=-`). **Audit `fichier/` actif dès le descellement**, vérifié avant toute configuration (déclaré dans [`config.hcl`](openbao/config.hcl)) |
| `configurer` | 2 s | **Transit : clé `chains` ecdsa-p256, `exportable=false`, `allow_plaintext_backup=false`, `deletion_allowed=false`.** Politique [`chains-signature`](openbao/chains-signature.hcl) (3 chemins). Méthode JWT : clé publique tirée de `service.key` de k3s, **`kid` recalculé égal à celui du JWKS** (une seule clé), émetteur `https://kubernetes.default.svc.cluster.local`. Rôle `tekton-chains` : audience `openbao`, sujet `system:serviceaccount:tekton-chains:tekton-chains-controller`, jetons batch de 5 min, **sans politique par défaut** |
| `essais` | 46 s | Voir ci-dessous |

**Essais** ([`openbao-essais.log`](resultats/openbao-essais.log)). Les pods utilisent l'image OpenBao vérifiée comme client `bao`. Le jeton du compte de service est projeté avec l'audience `openbao`, comme il le sera pour Chains en J4.
- **Signature par le compte de service de Chains**, depuis un pod de `sc-confiance` : connexion JWT acceptée (politique `chains-signature` seule, jeton batch de 300 s). Signature Transit `sha2-256` avec `prehashed`, comme le client hashivault de Chains, **vérifiée sur l'hôte par openssl** avec la clé publique lue dans Transit (P-256). La même signature est refusée sur un message modifié.
- **Refus pour le jeton de Chains (403, `permission denied`)** : export de la clé, **clé rendue exportable**, sauvegarde en clair, création d'une autre clé, liste des moteurs, lecture de son propre jeton.
- **Autres identités refusées (400)** : autre compte de service du même espace (« invalid subject (sub) claim ») ; compte de service de Chains muni de son jeton par défaut, d'audience API (« invalid audience (aud) claim »).
- **Réseau** : un pod de `sc-build` ne joint pas OpenBao (15 essais sur 15 s, `connection refused`). kube-router **journalise les SYN refusés en NFLOG** (groupe 100), et `tcpdump -i nflog:100` les lit sur `sc-confiance` : c'est la trace prévue pour le test 6.
- **Jeton root** : l'export (« private key material is not exportable ») et la sauvegarde en clair (« exporting is disallowed on the policy ») sont refusés.
- **Audit d'OpenBao** : chaque connexion, signature et refus y figure, avec le compte (`jwt-system:serviceaccount:…`) et la politique. Les valeurs sensibles (JWT, messages d'erreur de `response.data`) y sont en HMAC.

**Redémarrage** ([`openbao-deverrouiller.log`](resultats/openbao-deverrouiller.log)) : le pod supprimé revient **scellé et non prêt** (le Service n'a plus d'endpoint). `deverrouiller` le descelle, et la clé `chains` est intacte (version 1, non exportable), conservée par raft sur le PVC.

**Contrôle des fuites** ([`fuites-j1-j3.log`](resultats/fuites-j1-j3.log)) : 13 secrets, **0 occurrence** dans les journaux des trois VM, journaux des pods et **journal d'audit d'OpenBao** compris (lu sur le volume local-path) ; témoins retrouvés.

**Limites et constats.**
- **J3 prouve l'identité, la politique et la clé, pas encore le chemin de Chains lui-même.** Il sera validé en J4 : `signers.kms.kmsref: hashivault://chains`, `signers.kms.auth.address`, `oidc.path: jwt`, `oidc.role: tekton-chains`, `oidc.token-path` vers un jeton projeté d'audience `openbao`, CA du PoC (`VAULT_CACERT`), contrôleur sur `sc-confiance`.
- **`exportable=true` est irréversible et reste à la portée de l'administrateur** : quiconque détient le jeton root, ou la clé de descellement (qui permet d'en régénérer un), peut rendre la clé exportable. La garantie vaut contre tout le monde, sauf l'administrateur. Les essais ne demandent jamais cette modification avec le jeton root. Le jeton root reste sur l'hôte. Durcissement possible : le révoquer après la configuration et le régénérer au besoin (`operator generate-root`).
- **`bound_subject` seul** : tout pod qui tourne sous le compte de service de Chains, et quiconque peut créer `serviceaccounts/token` pour lui, obtient des signatures. La NetworkPolicy admet de même tout pod de l'espace `tekton-chains`. **À traiter en J6** : RBAC sur la création de pods, `exec`, `portforward` et `serviceaccounts/token` dans `tekton-chains` et `openbao` ; règle Kyverno qui garde les pods de `tekton-chains` en zone confiance. C'est le mécanisme du test 1.
- **kube-router applique la NetworkPolicy à un pod neuf avec un délai** : sa première connexion est rejetée (REJECT, donc `connection refused`, pas un délai dépassé) pendant environ 1 s, le temps que kube-router ajoute son IP. Les scripts d'essai attendent. Pour Chains, à vérifier en J4 : une première signature juste après le démarrage du contrôleur peut échouer et doit être réessayée.
- tcpdump ne sait pas filtrer l'interface NFLOG (« link-layer type filtering not implemented ») : on filtre après la capture.
- Le volume local-path est en 0777 sur le nœud ; les données d'OpenBao y sont chiffrées par la barrière, et `audit.log` est en 0600.
