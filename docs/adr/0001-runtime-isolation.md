# ADR 0001 : runtime, isolation des builds et infrastructure du PoC

- **Statut** : **Proposé (provisoire)**. Version définitive en phase 3, après les briques 05, 06 et 08.
- **Date** : 2026-10-28
- **Décideurs** : propriétaire du projet (à valider) et administrateur du domaine de replay (**à nommer**)

## Contexte

SLSA Build L3 (v1.2) exige :
- une provenance générée par un plan de contrôle hors de portée du build ;
- un environnement **éphémère** par build ;
- aucun accès des étapes utilisateur aux secrets de la plateforme ;
- aucun empoisonnement de cache entre builds.

Les outils de packaging (mock, sbuild unshare, Buildah, BuildKit rootless) demandent des privilèges ou des user namespaces. Un pod privilégié sur un nœud partagé casse l'isolation. L'infrastructure des nœuds de build n'est pas encore choisie, ce qui bloque la brique 08 (nœuds dédiés, modèle CPU x86-64-v3).

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
2. **Infrastructure du PoC** (à confirmer par le propriétaire) : **une VM ou un serveur avec KVM** (bare metal, ou virtualisation imbriquée activée), **CPU x86-64-v3** exposé, au minimum :

   | Rôle | vCPU | RAM | Disque |
   |---|---|---|---|
   | Nœud « confiance » (Chains, OpenBao, Kyverno, Conforma) | 4 | 8 Gi | 50 Go |
   | Nœud « build » (Kata) | 8 | 16 Gi | 150 Go |
   | Stockage (Forgejo, Zot) | 4 | 8 Gi | 300 Go |
   | **Domaine de replay** (hôte distinct, autre administrateur) | 8 | 16 Gi | 150 Go |

   Ce dimensionnement est estimé à **réviser après les benchmarks 2a** (Konflux demande au moins 12 Gi pour sa seule démo sur Kind).
3. **Isolation** : Kata si KVM est disponible ; sinon gVisor ou user namespace, selon les résultats de la brique 05.
4. **Domaine de replay** : hôte ou cluster distinct, **administré par une autre personne** (à nommer), avec sa propre clé de VSA. En 2b-1, ses images de build sont « indépendantes minimales » : toolchain Go officielle à checksum vérifié, image reconstruite dans ce domaine.

## Conséquences

- La brique 08 ne démarre qu'une fois l'infrastructure et l'administrateur du replay fixés.
- Un test négatif vérifie qu'**aucun pod privilégié ne tourne sur l'hôte** (Kyverno + brique 05).
- Le modèle CPU et le mode d'isolation sont inscrits dans la provenance (`internalParameters`).

## Questions ouvertes (propriétaire)

- [ ] Infrastructure disponible : bare metal, VM avec virtualisation imbriquée, ou VM sans ?
- [ ] Nom de l'administrateur du domaine de replay.
- [ ] Hébergement du domaine de replay : autre site ou autre hyperviseur ?
