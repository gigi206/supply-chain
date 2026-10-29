# Infra du PoC : le laptop

Hôte de toutes les mesures qui demandent KVM, un cluster ou des VM ([ADR 0001](../../docs/adr/0001-runtime-isolation.md)). Les parties « locales » des briques et des bancs ont été validées auparavant dans un environnement cloud sans KVM, sans Docker et sans cluster.

## Inventaire du 29/10/2026

[`inventaire.sh`](inventaire.sh) ne fait que lire : aucune installation, aucun `sudo`. Son seul test actif est `unshare`, sans effet de bord. Le nom d'hôte, le nom d'utilisateur, les adresses MAC et IP, les numéros de série et les UUID sont masqués. Parmi les ports, seuls ceux que le PoC utilisera sont relevés. Sortie : [`resultats/inventaire-laptop.txt`](resultats/inventaire-laptop.txt).

| Point | Constat | Conséquence |
|---|---|---|
| Machine | Dell XPS 15 9510 (châssis portable), UEFI. `systemd-detect-virt` répond `none` et le drapeau `hypervisor` est absent | **Bare metal vérifié** |
| CPU | Intel Core i7-11800H (Tiger Lake), 8 cœurs et 16 threads, non hybride ; VT-x et EPT. glibc : **x86-64-v4 supporté** (AVX-512) | Il faut fixer dans les VM un modèle **sans AVX-512** pour respecter la contrainte x86-64-v3 (voir plus bas) |
| KVM | `/dev/kvm` accessible (utilisateur dans les groupes `kvm` et `libvirt`). `vhost_vsock` chargé. **`kvm_intel.nested=Y`**. `virt-host-validate qemu` : PASS, sauf deux WARN sans effet ici (contrôleur `devices`, absent en cgroup v2 ; pas de SEV ni de TDX) | Prérequis de Kata réunis, **à l'hôte comme dans une VM**. Kata n'est pas installé |
| Mémoire | **61 Gi, sans swap.** Au relevé : **21 Gi disponibles**. La session de bureau en consomme une grande partie (navigateur ≈ 10 Gi, IDE, et **12 Gi de fichiers dans `/tmp`, monté en tmpfs, donc en RAM**) | C'est la contrainte principale |
| Disque | NVMe 1 To. **`/` (ext4) : 90 Go libres** ; c'est là que se trouvent `/var/lib` et `/var/lib/docker`. **`/home` (ext4) : 79 Go libres, occupé à 86 %** ; le pool libvirt `default` pointe sur `/home/kvm/vms` | Budget disque serré. `/home` est à protéger |
| Système | Ubuntu 26.04.1 LTS, noyau 7.0.0-31, systemd 259, cgroup v2, AppArmor et Landlock, BTF présent | Compatible k3s, Kata et, plus tard, Tetragon |
| User namespaces | `apparmor_restrict_unprivileged_userns=0`, plage subuid/subgid de 65 536, `newuidmap` présent ; `unshare -rn`, `-rmn` et `--map-auto` réussissent | **Aucun réglage nécessaire** pour `hermeto.sh`, les bancs 03 et 07a, BuildKit rootless et sbuild unshare |
| Existant | Docker 28.4 (8 ponts), containerd 1.7.27, Podman 5.7, libvirt 12.0 + QEMU 10.2.1 (2 VM définies, arrêtées), LXD 5.21.8, kind 0.33, kubectl 1.37.2, helm 4.3.1, **Nix 2.34.5 (démon actif)**, ufw actif. `~/.kube/config` contient déjà des contextes | k3s directement sur l'hôte cohabiterait avec les règles iptables de Docker, ufw et LXD. On ne touche pas à l'existant |
| Outils de VM | `virt-install` **inutilisable** (module Python `gi` manquant). `genisoimage`, `xorriso` et `qemu-img` présents. **Vagrant 2.4.1 est sous BUSL 1.1** (`/opt/vagrant/embedded/gems/gems/vagrant-2.4.1/LICENSE`) | VM créées avec `virsh` (XML versionné), une image cloud officielle et une graine cloud-init. **Vagrant est exclu** : il n'est pas open source |
| Réseau | Pas de proxy ni de CA ajoutée ; NTP synchronisé (Europe/Paris). Ports 80, 443, 3000, 5000, 6443, 8080, 8200, 9090, 9093 et 10250 libres ; **8443 occupé** | Le piège du proxy TLS (banc B) ne s'applique pas ici. Vérifier le port 8443 dans la doc d'installation de Konflux avant A1 |
| Alimentation | Secteur branché, profil de plateforme `performance` (intel_pstate, EPP `performance`) | Mesures de temps à faire sur secteur |
| Outils des bancs | Présents : python3 3.15.2, git, make, Node 26.12.1, jq, curl, gpg, runc 1.2.5. **Absents** : Go, Hermeto, oras, crane, cosign, Zot, BuildKit, Syft, Grype, Conforma (`ec`), Kyverno, reuse, diffoscope | Liste d'installation de 4b, soumise à part. Pour retrouver les empreintes du cloud, il faut les **mêmes versions** : Node 22.22.0 et pas le 26 de l'hôte, Go 1.24.7 et 1.26.10, BuildKit 0.25.2 et runc 1.3.3 du nixpkgs épinglé |

## Outils des bancs (4b)

Les outils sont déclarés dans [`mise.toml`](../../mise.toml), à la racine du dépôt, aux versions des mesures du cloud. [`mise.lock`](../../mise.lock) fige les URL et les sha256 pour linux-x64. Rien n'est installé au niveau système.

```bash
mise install && mise run outils:verifier
```

- **Backends mise** : Go 1.24.7 (attention : il exporte `GOROOT`, à retirer avec `env -u GOROOT -u GOBIN` pour utiliser Go 1.26.10), Python 3.13.12, BuildKit 0.25.2, runc 1.3.3, rootlesskit 2.3.5, Zot 2.1.22, oras 1.3.6, crane 0.20.6, cosign 3.1.4, Kyverno 1.19.2, Syft 1.38.0, Grype 0.104.1 et Conforma `ec` 0.10.42.
- **Tâches `outils:*`**, pour ce qu'aucun backend ne fournit :
  - Hermeto 0.64.0, absent de PyPI : tag source vérifié, dépendances installées avec `--require-hashes` ;
  - Go 1.26.10 comme module `golang.org/toolchain`, comme dans le cloud ;
  - busybox statique, liste SPDX 3.27.0, reuse 6.2.0, **BuildKit 0.25.2 et runc 1.3.3**, tirés du nixpkgs épinglé du banc B pour obtenir les mêmes binaires que dans le cloud. Les binaires de référence de la brique 04 sont donc ceux du nixpkgs ; la release amont de BuildKit (mise) sert de mesure en plus.
- **Vérification** ([`verifier-outils.sh`](verifier-outils.sh), résultat : [`resultats/outils.txt`](resultats/outils.txt)) : **33 contrôles réussis, aucun échec**.
  - Les sha256 de `mise.lock` viennent du service tiers `mise-versions`. Ils ont été recoupés avec les fichiers de sommes publiés par chaque projet.
  - Les signatures sont vérifiées partout où elles existent :
    - sigstore (cosign, Kyverno, Syft, Grype), avec le cosign du nixpkgs épinglé, indépendant de mise ;
    - GPG (oras, runc, rootlesskit, Go) ;
    - attestation GitHub (Python) ;
    - sum.golang.org (Go 1.26.10) ;
    - cache.nixos.org (paquets Nix).
  - **Sans signature publiée** : Zot et Conforma (constat du doc 04), BuildKit (provenance amont non signée), crane (provenance SLSA non vérifiée : il faudrait slsa-verifier). Pour ces quatre outils, seul le sha256 est contrôlé, contre le fichier de sommes amont.
  - mise ne vérifie aucune signature à l'installation quand `mise.lock` contient déjà les sommes (« skipping provenance detection »). D'où ce script, à relancer à chaque changement de version.

## Rejeu des bancs (4b)

```bash
mise run bancs
```

[`bancs-laptop.sh`](bancs-laptop.sh) rejoue les bancs dans l'ordre B, C, 02, 03, 04 (BuildKit du nixpkgs puis release amont), 07a et 13a, en environ 9 minutes. Le registre Zot et les démons BuildKit rootless sont éphémères, et les journaux vont dans `*/resultats/*-laptop.*`. Le script règle deux pièges propres au laptop :
- les shims de mise sont retirés du `PATH`, car Hermeto sonde chaque `go` qu'il y trouve ;
- `GOROOT` est retiré de l'environnement, car le Go 1.24.7 de mise l'exporte et Go 1.26.10 prendrait sinon sa bibliothèque standard.

Deux passages complets ont donné les mêmes empreintes. Les résultats sont dans [`docs/03`](../../docs/03-validation-briques.md#rejeu-sur-le-laptop-29102026).

## Dimensionnement

**Validé par le propriétaire le 29/10/2026** : pas de cluster pour 4b, **kind jetable pour A1**, **VM libvirt + k3s (topologie T2, profil nominal) pour la brique 08 et la suite**. Les changements sur l'hôte (pool, réseau, téléchargements) restent confirmés un par un au moment de les faire.

Après libération de mémoire le même jour (répertoires inutilisés de `/tmp`, en tmpfs), **31 Gi sont disponibles** : le profil nominal (24 Gi) laisse environ 7 Gi à la session de bureau.

### Principes

1. **Une phase à la fois** : 4b, puis A1, A2 et la brique 08 ne tournent **jamais en même temps**. Chacune est démontée avant la suivante.
2. **Ne pas toucher à l'existant** : ni aux VM libvirt personnelles, ni aux réseaux Docker, ni à LXD. Le PoC a son propre `KUBECONFIG` (`~/.kube/supply-chain-poc.yaml`), jamais fusionné dans `~/.kube/config`.
3. **Protéger `/home`** : les VM du PoC vont dans un pool dédié, **hors de `/home/kvm/vms`**. La somme des disques provisionnés reste **inférieure à l'espace libre moins 20 Go**.
4. Les répertoires de travail de 4b vont **sur disque** (`~/.cache/supply-chain-poc/`), pas dans le scratchpad de `/tmp`, qui est en RAM. Pour mémoire : base Grype importée de 3,2 Go, registre Zot, 10 000 artefacts du banc 02, états BuildKit.
5. Le domaine de replay **n'est pas dimensionné ici**. Le laptop n'est ni un hôte distinct, ni un hôte administré par une autre personne : la décision se prend à la brique 10.

### Par phase

| Phase | Forme | vCPU | RAM | Disque | Changement sur l'hôte |
|---|---|---|---|---|---|
| 4b, bancs locaux | Processus sur l'hôte : BuildKit éphémère, Zot sur localhost | — | ≤ 6 Gi (import Grype) | ≈ 15 Go dans `~/.cache/supply-chain-poc/`, plus le store Nix | Aucun ; outils via le nixpkgs épinglé et des binaires vérifiés, après accord |
| A1, Konflux | Kind (Docker déjà installé), cluster jetable | 8 | ≥ 16 Gi | ≤ 50 Go sur `/` (`/var/lib/docker`) | Aucun au niveau système |
| A2, OBS | VM appliance OBS, workers KVM imbriqués | 6 | 8 Gi | 40 Go dans le pool dédié | Pool dédié |
| 08, puis 01, 03, 19 et 2b-2 | 3 VM k3s (topologie T2) | 12 (sur 16 threads) | 24 Gi (nominal) | 70 Go dans le pool dédié | Pool et réseau dédiés |

### Topologie de la brique 08 : T2, tout en VM

| VM | Rôle | vCPU | RAM nominale | RAM compacte | Disque |
|---|---|---|---|---|---|
| `confiance` | k3s server, contrôleurs Tekton, Chains, Triggers, OpenBao, Kyverno, Conforma, job TSA | 4 | 8 Gi | 6 Gi | 15 Go |
| `build` | k3s agent, nœud de build avec taint, Kata imbriqué, BuildKit | 6 | 10 Gi | 8 Gi | 30 Go |
| `stockage` | k3s agent : Forgejo, Zot, Prometheus, Alertmanager, Grafana | 2 | 6 Gi | 5 Gi | 25 Go |
| **Total** | | **12** | **24 Gi** | **19 Gi** | **70 Go** |

Pourquoi T2 plutôt que k3s sur l'hôte (T1) ou un hybride (T3) :
- l'imbrication est active, donc Kata fonctionne dans la VM de build ;
- de vrais nœuds dédiés séparent la zone confiance de la zone build ;
- l'hôte n'est pas modifié (Docker, ufw et LXD restent intacts) ;
- démontage et instantanés sont simples.

Coût : le surcoût de Kata imbriqué, à mesurer, et environ 0,5 Gi de système par VM.

**RAM, deux options :**
- **nominale (24 Gi)** : il faut libérer environ 8 Gi pendant A1 et la brique 08 (contenu de `/tmp`, navigateur) pour garder au moins 5 Gi à la session de bureau ;
- **compacte (19 Gi)** : tient avec les 21 Gi disponibles aujourd'hui, mais ne laisse que ≈ 2 Gi de marge, **sans swap**, donc avec un risque d'OOM pour la session de bureau.

Activer un swap zram serait un réglage système : c'est au propriétaire d'en décider.

**Disque.** Le pool dédié irait sur `/`, avec 70 Go au plus pour 90 Go libres. A1 (Docker, aussi sur `/`) doit donc être démonté avant 08. Si de l'espace peut être libéré, on agrandit d'abord les disques de `build` et de `stockage`.

**Modèle de CPU (proposé, pas acquis).** On utilise **`Haswell-v4`**, utilisable sur cet hôte selon `virsh domcapabilities` : il couvre x86-64-v3 sans AVX-512. On écarte `host-passthrough`, qui exposerait x86-64-v4. Un modèle nommé n'expose pas `vmx` : la VM `build` devra l'exiger (`<feature policy='require' name='vmx'/>`). Le modèle retenu est inscrit dans `internalParameters.cpuModel`.

**Contrôles au premier démarrage** (résultats attendus) :
- dans chaque VM, `ld.so --help` affiche x86-64-v3 « supported » et pas x86-64-v4 ;
- dans `build`, `/dev/kvm` est présent et `kvm_intel` chargé ;
- les VM sortent sur le réseau par le NAT libvirt, malgré la politique `FORWARD` de Docker sur l'hôte ;
- à l'installation de Kata : les invités héritent bien du modèle de CPU de la VM `build` (à vérifier).

**Images des VM** : image cloud officielle (Debian ou Ubuntu, à choisir en brique 08), dont on vérifie l'empreinte et la signature, et graine cloud-init NoCloud construite avec `genisoimage`.

### Changements sur l'hôte à valider par le propriétaire

| Changement | Phase |
|---|---|
| Pool libvirt dédié au PoC sur `/` (répertoire à créer) | A2, 08 |
| Réseau libvirt NAT dédié au PoC (pont et sous-réseau propres, séparés des VM personnelles) | A2, 08 |
| Téléchargement de l'appliance OBS et des images cloud (empreinte et signature vérifiées) | A2, 08 |
| Installation des outils de 4b | 4b |
