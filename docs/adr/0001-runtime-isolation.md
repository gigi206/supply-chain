# ADR 0001 : runtime, isolation des builds et infrastructure du PoC

- **Statut** : **Proposé (provisoire)**. Version définitive en phase 3, après les briques 05, 06 et 08.
- **Date** : 2026-10-28 ; infra du PoC inventoriée le 2026-10-29
- **Décideurs** : propriétaire du projet (à valider) et administrateur du domaine de replay (**à nommer**)

## Contexte

SLSA Build L3 (v1.2) exige :
- une provenance générée par un plan de contrôle hors de portée du build ;
- un environnement **éphémère** par build ;
- aucun accès des étapes utilisateur aux secrets de la plateforme ;
- aucun empoisonnement de cache entre builds.

Les outils de packaging (mock, sbuild unshare, Buildah, BuildKit rootless) demandent des privilèges ou des user namespaces. Un pod privilégié sur un nœud partagé casse l'isolation. L'infrastructure du PoC est maintenant connue : un laptop bare metal avec KVM ([inventaire](../../poc/infra/README.md)). Restent à fixer la topologie des nœuds dédiés et le modèle CPU x86-64-v3 des VM.

## Options

### Runtime

| Option | Niveau SLSA atteignable | Commentaire |
|---|---|---|
| **Kubernetes (k3s) + Tekton/Chains** | **L3** | Chains signe hors des pods ; RBAC, Kyverno, nœuds dédiés |
| docker compose seul | **L2** | La provenance est produite depuis le job. L3 seulement en écrivant soi-même un plan de contrôle et une isolation par VM |
| Les deux | L3 pour les builds | Les services de stockage (Forgejo, Zot, OpenBao, DT…) peuvent tourner en compose hors du cluster |

### Isolation (selon l'infrastructure)

| Infrastructure | Isolation recommandée | Prérequis |
|---|---|---|
| **Bare metal** | **Kata Containers** (`privileged_without_host_devices=true`) pour mock, sbuild et images ; pods en user namespace pour les builds Go | KVM |
| **VM avec virtualisation imbriquée** (Proxmox, VMware, cloud type AWS C8i/M8i/R8i) | Kata (pénalité de performance à mesurer), repli gVisor | `/dev/kvm` exposé dans la VM, CPU **x86-64-v3** exposé |
| **VM sans virtualisation imbriquée** | **gVisor** (plateforme systrap) ou **pods en user namespace** (K8s ≥ 1.36, noyau ≥ 6.3) ; mieux : une VM éphémère par build via l'API de l'hyperviseur | mock et sbuild sous gVisor ou en userns : **non documenté, à tester** (brique 05) |

À noter : **kind ne convient pas à Kata** (KVM imbriqué dans un nœud qui est lui-même un conteneur, noyau partagé), d'où **k3s**.

## Décision provisoire

1. **Runtime** : **k3s** pour le plan de build et de confiance, ce qui donne L3. Les services de stockage pourront sortir du cluster en compose (décision définitive en phase 3).
2. **Infrastructure du PoC** : **un laptop bare metal avec KVM** (inventaire du 29/10/2026, [`poc/infra`](../../poc/infra/README.md)) :
   - **bare metal vérifié** (`systemd-detect-virt` : `none`) ; Intel i7-11800H, 8 cœurs et 16 threads, x86-64-v4 (AVX-512), 61 Gi de RAM sans swap, NVMe 1 To ; Ubuntu 26.04.1, noyau 7.0, cgroup v2 ;
   - **prérequis de Kata présents** : `/dev/kvm` accessible, `vhost_vsock` chargé, **virtualisation imbriquée active** (`kvm_intel.nested=Y`). Kata n'est pas installé ;
   - user namespaces non privilégiés disponibles, sans restriction AppArmor ;
   - contraintes : environ 21 Gi de RAM et 90 Go de disque réellement disponibles au relevé, car l'hôte sert aussi de poste de travail.

   Dimensionnement minimal estimé en phase 1, pour un serveur ou une VM avec KVM et un CPU **x86-64-v3** exposé :

   | Rôle | vCPU | RAM | Disque |
   |---|---|---|---|
   | Nœud « confiance » (Chains, OpenBao, Kyverno, Conforma) | 4 | 8 Gi | 50 Go |
   | Nœud « build » (Kata) | 8 | 16 Gi | 150 Go |
   | Stockage (Forgejo, Zot) | 4 | 8 Gi | 300 Go |
   | **Domaine de replay** (hôte distinct, autre administrateur) | 8 | 16 Gi | 150 Go |

   Ce dimensionnement est estimé à **réviser après les benchmarks 2a** (Konflux demande au moins 12 Gi pour sa seule démo sur Kind). **Révision pour le laptop, validée par le propriétaire le 29/10/2026** ([`poc/infra/README.md`](../../poc/infra/README.md)) : une phase à la fois ; kind jetable pour le banc A1 ; pour la brique 08 et la suite, **trois VM libvirt avec k3s** (confiance 4 vCPU / 8 Gi, build 6 vCPU / 10 Gi avec Kata imbriqué, stockage 2 vCPU / 6 Gi ; 70 Go) et un modèle CPU nommé sans AVX-512 (`Haswell-v4` avec `vmx` exigé et `check='partial'`, vérifié au banc A2 le 29/10/2026 : x86-64-v3 sans v4, KVM imbriqué fonctionnel). kind est écarté pour la brique 08 : ses nœuds sont des conteneurs privilégiés qui partagent le noyau de l'hôte.
3. **Isolation** : Kata si KVM est disponible, ce qui est le cas sur le laptop (à installer et à mesurer, y compris en virtualisation imbriquée) ; sinon gVisor ou user namespace, selon les résultats de la brique 05.
4. **Domaine de replay** : hôte ou cluster distinct, **administré par une autre personne** (à nommer), avec sa propre clé de VSA. En 2b-1, ses images de build sont « indépendantes minimales » : toolchain Go officielle à checksum vérifié, image reconstruite dans ce domaine.

## Conséquences

- La brique 08 ne démarre qu'une fois l'infrastructure et l'administrateur du replay fixés.
- Un test négatif vérifie qu'**aucun pod privilégié ne tourne sur l'hôte** (Kyverno + brique 05).
- Le modèle CPU et le mode d'isolation sont inscrits dans la provenance (`internalParameters`).

## Questions ouvertes (propriétaire)

- [x] Infrastructure disponible : **bare metal** (laptop, KVM, virtualisation imbriquée active), vérifié le 29/10/2026.
- [x] Dimensionnement et topologie sur le laptop : **validés le 29/10/2026** (kind pour A1, trois VM libvirt + k3s pour 08 ; [`poc/infra`](../../poc/infra/README.md)).
- [ ] Nom de l'administrateur du domaine de replay.
- [ ] Hébergement du domaine de replay : autre site ou autre hyperviseur ?
