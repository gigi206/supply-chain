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

- La brique 08 ne démarre qu'une fois l'infrastructure fixée. L'administrateur du replay doit être nommé **avant la brique 10** : la brique 08 ne touche ni au domaine de replay ni à la clé de VSA (verrou levé par le propriétaire le 29/10/2026).
- Un test négatif vérifie qu'**aucun pod privilégié ne tourne sur l'hôte** (Kyverno + brique 05).
- Le modèle CPU et le mode d'isolation sont inscrits dans la provenance (`internalParameters`). Mesuré en brique 08 (J6) : Chains v0.29.9 ne les y inscrit que depuis des labels ou annotations du PipelineRun, déclarations qu'il ne vérifie pas ; choix du canal reporté à J7 par le propriétaire (30/10/2026) ([doc 02 §3](../02-architecture.md)).
- **Services de stockage hors des pods** (brique 08, J2, choix du propriétaire du 29/10/2026) : Forgejo et Zot tournent en services systemd durcis sur le nœud de stockage, à partir des binaires vérifiés de `mise.toml` (GPG pour Forgejo, sha256 pour Zot). Les images Forgejo et Zot ne sont pas signées. TLS par une CA du PoC à contraintes de nom, déclarée à containerd ([résultats](../../poc/bricks/08-trust-plane/README.md#jalon-j2--stockage-29102026)).
- **Fenêtre de démarrage des NetworkPolicy de sortie** (brique 08, J6, mesuré sur kube-router embarqué dans k3s v1.35.9 : [sonde](../../poc/bricks/08-trust-plane/resultats/politique-rattrapage-sonde-fenetre.log)) : une sortie interdite passe pendant la première seconde d'un conteneur, avant que la règle ne soit posée. L'« egress = 0 » de la zone build ne peut donc pas reposer sur une NetworkPolicy seule : entrée à mesurer en J7, avec Kata (réseau de la VM invitée) ou un filtrage posé avant le lancement du conteneur.
- **Pod Security et builds privilégiés sous Kata** (brique 08, J6, [résultats](../../poc/bricks/08-trust-plane/README.md#jalon-j6--politique-29-et-30102026)) : les pods de build actuels respectent `restricted`, et l'espace `builds` est en `enforce: restricted` (décision du propriétaire du 30/10/2026). Dès le niveau `baseline`, Pod Security refuse un conteneur privilégié et un profil seccomp `Unconfined` ; un build Kata privilégié (`privileged_without_host_devices`) y serait donc refusé sous `enforce`. Voie retenue par le propriétaire : exemption des pods Kata par RuntimeClass dans la configuration de Pod Security du server k3s, en J7, sur accord séparé au moment de modifier k3s. Correction (J7, 30/10/2026) : k3s v1.35.9 n'a pas d'option `--pod-security-admission-config-file`, qui est une option de RKE2 ; la configuration passe par `kube-apiserver-arg: admission-control-config-file=…` (aide de `k3s server`, arguments de kube-apiserver relus dans le journal de k3s). **Exemption posée le 30/10/2026 (accord du propriétaire)** ([journal](../../poc/bricks/08-trust-plane/resultats/kata-exemption.log)) : fichier d'admission sur `sc-confiance`, passé par un fichier d'appoint de `config.yaml.d` ; redémarrage du server sans arrêt de conteneur (`KillMode=process`) ; pod Kata privilégié admis dans `builds`, pod runc privilégié toujours refusé ; Kyverno reste la garde des pods Kata (`hostPath` et zone de confiance refusés). Un pod exempté reste soumis à la règle Kyverno `pods-isolation` (ni `hostNetwork`, `hostPID`, `hostIPC`, ni `hostPath`).
- **Installation de Kata** (brique 08, J7, [vérification](../../poc/bricks/08-trust-plane/resultats/kata-verifier.log), [essais](../../poc/bricks/08-trust-plane/resultats/kata-essais.log)) : l'image `kata-deploy` 4.3.1 n'est pas vérifiable (ses jobs de publication n'ont pas `id-token` : ni signature, ni attestation) ; l'archive `kata-static` l'est, par l'attestation de release GitHub. En 4.x, elle ne contient plus que le shim Rust (`qemu-runtime-rs` par défaut). **Décision du propriétaire (30/10/2026) : installation depuis l'archive attestée**, avec les seuls fichiers lus par le shim, un manifeste sha256, un fichier d'appoint de containerd sans transmission des annotations de pod et une RuntimeClass `kata` réservée à la zone build. Mesuré : l'invité est en x86-64-v3 sans v4, sur son propre noyau (6.18.56) ; QEMU est lancé en `-cpu host,pmu=off` (relevé sur le nœud), donc le modèle de CPU de l'invité est celui du nœud, pas un choix du pod. **Seccomp absent dans l'invité** (`disable_guest_seccomp = true`, `Seccomp: 0` mesuré malgré `RuntimeDefault`) : sous Kata, la frontière est la VM, et la conformité d'un pod à `restricted` ne dit rien de son confinement seccomp dans l'invité.
- **BuildKit et Pod Security** (brique 08, J7, [image](../../poc/bricks/08-trust-plane/resultats/buildkit-image.log), [essais](../../poc/bricks/08-trust-plane/resultats/buildkit-essais.log), [après l'exemption](../../poc/bricks/08-trust-plane/resultats/buildkit-exempte.log)) : en `restricted`, BuildKit rootless ne peut exécuter aucune étape `RUN`, ni sous runc (seccomp refuse le user namespace) ni sous Kata (avec un seul UID, sans `newuidmap`, le montage de `devpts` en `gid=5` échoue). L'exemption Pod Security de la RuntimeClass `kata`, posée le 30/10/2026, est nécessaire mais ne suffit pas au mode rootless : sous Kata, `newuidmap` échoue même dans un pod privilégié, car virtiofsd est lancé sans `--xattr` (`disable_guest_selinux = true`) et les capacités de fichier ne sont pas visibles dans l'invité (mesuré : attribut étendu refusé sur la racine `virtiofs`, accepté sur un tmpfs). Une première attribution de cet échec à `no_new_privs` a été démentie. BuildKit en root dans un pod Kata privilégié construit, avec le bac à sable des processus (la VM est la frontière) ; garder le rootless exigerait `--xattr` dans la configuration de Kata. **Voie D**, mesurée à la demande du propriétaire ([compilation](../../poc/bricks/08-trust-plane/resultats/voie-d-compiler.log), [assemblage](../../poc/bricks/08-trust-plane/resultats/voie-d-assembler.log)) : sans conteneur imbriqué, la compilation tourne dans le conteneur du pod Kata, au contexte de `restricted` (sans exemption), le réseau coupé par `unshare -U -r -n` créé sans privilège, et donne le même binaire que BuildKit ; l'image s'assemble sans rien exécuter (tar GNU, crane), reproductible, mais d'un digest différent de celui de BuildKit (en-tête tar, `created`, compression). Elle dépend de Kata (sous runc, `unshare` est refusé), ne couvre que Go et les images sans `RUN` de paquets, et ne retire pas le privilège de la plateforme (mock). **Voie A sur sample-app** ([journal](../../poc/bricks/08-trust-plane/resultats/buildkit-sample_app.log)) : BuildKit v0.34.1 en root dans un pod Kata privilégié redonne `3a7ca1b1`, le digest de la brique 04 (0.25.2), à condition de placer son état sur un tmpfs de l'invité (sur virtio-fs sans `--xattr`, le `COPY --from` échoue) ; 1,7 Go de tmpfs après deux constructions. **Décision du propriétaire (30/10/2026) : voie A**, BuildKit en root dans un pod Kata privilégié, état sur tmpfs de l'invité ; l'exemption reste en place, la voie D reste archivée comme alternative sans privilège pour les images Go. Les limites du pod fixent la taille de la VM (mesuré : 2 CPU et 3 Gi donnent `-smp 3` et `-m 3104M`).

## Questions ouvertes (propriétaire)

- [x] Infrastructure disponible : **bare metal** (laptop, KVM, virtualisation imbriquée active), vérifié le 29/10/2026.
- [x] Dimensionnement et topologie sur le laptop : **validés le 29/10/2026** (kind pour A1, trois VM libvirt + k3s pour 08 ; [`poc/infra`](../../poc/infra/README.md)).
- [ ] Nom de l'administrateur du domaine de replay (avant la brique 10).
- [ ] Hébergement du domaine de replay : autre site ou autre hyperviseur ?
