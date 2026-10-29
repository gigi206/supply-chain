# A2 : Open Build Service (packaging rpm/deb)

**But** : noter OBS sur la grille A restreinte au packaging (critères A-1 sur B1, B4, B5 et B8, puis A-3, A-5 et A-6). Seuil : rpm **et** deb bit-identiques sur 2 builds.

**Prérequis** : VM ou serveur avec KVM (workers OBS), image OBS appliance ou paquets openSUSE.

## Protocole (≤ 3 jours)

1. Installer OBS (appliance) et un worker KVM. Mesurer le temps et la RAM.
2. Configurer les dépôts cibles : Debian 13 et Rocky 9, en **dépôts téléchargés à la demande** (DoD) pointant vers des miroirs figés.
3. Construire `poc/packaging` (spec et debian/) pour rocky-9 et debian-13.
4. Reconstruire sans changement (`rebuild`) et comparer les sha256 : rpm et deb.
5. Exporter la provenance OBS (format SLSA v0.2) et évaluer sa conversion en SLSA v1, ou sa signature par notre plateforme.
6. Tester le fonctionnement **hors ligne** : worker sans egress, dépôts locaux.
7. Évaluer la signature (signd) face à notre service OpenPGP (brique 09).

## Mesures à archiver dans `resultats/`

- Versions ; ressources ; journaux de build ; sha256 des deux builds ; provenance produite.

## Décisions du propriétaire (29/10/2026)

### Version évaluée : appliance « Unstable », épinglée

La dernière release, **2.10.34** (tag du 10/08/2026, appliance sur Leap 16.0), **ne produit aucune provenance**. Ni le tag ni la branche `2.10` ne contiennent `BSRepServer/SLSA.pm`, `BSRekor.pm` ou `Reproduciblecheck.pm`, et « slsa » n'apparaît dans aucun des fichiers suivants de 2.10.34 : `bs_worker`, `bs_repserver`, `bs_signer`, `bs_sched`, `BSConfig.pm.template`. La provenance SLSA v0.2 (« Alpha », activée projet par projet par `$slsaprovenance`) n'existe **que sur master**, depuis 2022. C'est master qui tourne sur build.opensuse.org : `/about` répond `2.11~alpha.20261026T130906`.

Le propriétaire a retenu l'appliance du projet `OBS:Server:Unstable`, construite depuis master :
- fichier : `obs-server.x86_64-2.10.51-oem-Build53.24.raw.xz` ;
- contenu : `obs-server 2.11~alpha.20261029T112345.58021baee2` ;
- épinglage : sha256 et signature, puis archivage local au téléchargement, car le fichier amont est écrasé à chaque build.

Ce choix a un coût : adopter OBS reviendrait à suivre master, puisqu'aucune release ne contient la provenance.

### Lecture de la grille restreinte

La grille n'est pas modifiée ; ce qui suit précise seulement comment l'appliquer. Lecture validée avant toute mesure.

- **Score de référence restreint** aux critères A-1, A-3, A-5 et A-6, avec les notes du §2.3 : (2×25 + 3×15 + 4×10 + 3×10) / 3 = **55**. Il faut donc **au moins 65** pour adopter OBS.
- **A-1 sur 4 besoins** (B1, B4, B5, B8) : les ancres 12/14 et 4/14 sont ramenées à l'échelle de 4. Cela donne 4/4 → 5, 3/4 → 4, 2/4 → 2, ≤ 1 → 0 (interpolation linéaire, arrondi comme au banc A1).
- **A-3 sur rpm et deb seulement** : l'image sort du périmètre « packaging seul ». 2/2 → 5, 1/2 → 3 (2,5 arrondi), 0/2 → 0.
- **Méthode de comparaison** (B1) :
  - comparer d'abord les NEVRA (rpm) et les versions (deb), qui doivent être identiques, sinon la comparaison n'a pas de sens ;
  - comparer ensuite les sha256 **hors signature** : rpm non signés, ou signature retirée d'une copie ;
  - vérifier dans chaque journal de build que le worker a utilisé **KVM**, pas le chroot.

### Changements sur l'hôte (validés, à remettre en état à la fin)

| Changement | Détail |
|---|---|
| Téléchargement | Appliance oem (1,53 Go), `.sha256`, `.sha256.asc`, SBOM ; vérification de la clé `660F D3F9 F166 02A3 722A BF6D E842 0AB8 C5C2 19E7` sur trois canaux : download.opensuse.org, build.opensuse.org et la clé embarquée dans `config.sh` de l'appliance |
| Pool libvirt | `supply-chain-poc` dans `/var/lib/libvirt/supply-chain-poc` (sur `/`), créé par libvirtd |
| Réseau | NAT `supply-chain-poc`, pont `virbr-scpoc`, 192.168.161.0/24, sans démarrage automatique ; règles du pare-feu de l'hôte inchangées |
| VM | `sc-obs` : 6 vCPU (Haswell-v4, `vmx` exigé), 8 Gi, disque qcow2 **plafonné à 40 Go**, console série sur socket ; sans démarrage automatique |

Premier accès : l'appliance n'a ni cloud-init ni combustion. Un script se connecte donc sur la console série avec le mot de passe root par défaut, qui est public. Il le remplace aussitôt par un mot de passe aléatoire, installe une clé SSH dédiée et fait de même pour le compte `Admin` de l'interface. Les secrets sont stockés en 0600 dans `~/.cache/supply-chain-poc/obs`. `osc` est fourni par l'appliance : rien n'est installé sur l'hôte.

Dépôts figés :
- Debian 13 : instantané `20261029T000000Z` de `snapshot.debian.org`, servi par `deb.debian.org` et épinglé par le sha256 de son `InRelease` (voir les constats plus bas) ;
- Rocky 9.7 : vault, figé depuis la sortie de la 9.8.

## Constats d'installation (29/10/2026)

- **Installation en 9 min 25 s** depuis l'accord. Ce temps couvre le téléchargement vérifié de l'appliance, la VM, le premier accès, puis le compte Admin, `osc` et le worker. Le premier démarrage arrive à l'invite de connexion en 15 s.
- **Paquets** : les 554 rpm de la VM correspondent exactement au SBOM CycloneDX publié pour la qcow2 du même build (ce SBOM recense aussi 434 modules Go, ceux d'`obs-gitea-bridge`).
- **Clé OBS dans la base rpm de l'appliance** : c'est une copie de 2013 de la clé `660F…19E7`, **expirée le 30/04/2015**. Elle est embarquée dans `config.sh` du kiwi, d'où une erreur à chaque `rpm -q`. La clé publiée sur download.opensuse.org et build.opensuse.org a la même empreinte et vaut jusqu'en 2028.
- **Worker** : par défaut, une instance par vCPU (6 ici), ce qui ne tient pas dans 8 Gi. Il est réglé à 1 instance de 4 jobs et 3 Gi, en type `kvm` imposé. Faute de paquet `kernel-obs-build`, la VM de build démarre sur le noyau de l'appliance (`build-vm-kvm`) ; ce paquet est fourni sur build.opensuse.org par `OBS:DefaultKernel`, absent de l'instance.
- **L'appliance ne construit pas telle quelle pour des cibles non SUSE.** L'initrd que kiwi a construit pour l'appliance ne contient ni pilote IDE ni ext4. La VM de build s'arrête donc sur `dracut: FATAL: Storage device did not appear`, le watchdog la tue au bout de 5 minutes et le job repart en boucle. Après plusieurs échecs, le dispatcher marque le worker « bad » (`waiting for 1 compliant workers (1 of them bad)`). Correctif :
  - générer `/boot/initrd.obs.guest` avec le dracut de l'appliance (`configurer.sh`), que `build-vm-kvm` préfère et associe à un disque virtio ;
  - puis vider l'état du dispatcher avec `bs_admin --drop-badhosts`.

  On perd environ 15 minutes.
- **VM de build** (journal de build) : `qemu-kvm -cpu host -net none -sandbox on -run-with user=qemu`. Elle n'a **aucune interface réseau**, et son CPU est celui de sc-obs, donc Haswell-v4.
- **Libvirt** : avec `check='full'`, QEMU refuse le modèle Haswell-v4, parce qu'il y ajoute des fonctions (f16c, rdrand, xsaveopt, sous-fonctions vmx). Le banc passe donc en `check='partial'`. Dans la VM, x86-64-v3 est supporté, x86-64-v4 ne l'est pas, AVX-512 est absent, et `/dev/kvm` est présent.
- **Réseau** : la VM sort par le NAT libvirt malgré la politique `FORWARD` de Docker sur l'hôte.

## Constats sur les dépôts téléchargés à la demande

- **Signatures vérifiées** : `bs_dodup` vérifie `Release.gpg` (deb) et `repomd.xml.asc` (rpm) avec les clés déclarées dans `<pubkey>`. `gpgv` exige que **toutes** les signatures soient vérifiables. Or le `Release` de trixie porte aussi la signature de la clé d'archive de Debian 12 : il faut donc la déclarer, comme le fait build.opensuse.org.
- **snapshot.debian.org inutilisable en DoD (bug d'OBS)** : l'instantané redirige chaque `.deb` vers une URL relative (`/file/<hash>/…`). Le téléchargement asynchrone du repserver (`BSWatcher::rpc_redirect`) transmet cet en-tête `Location` tel quel et le rejette (« bad uri »). Pourtant, `BSRPC`, qu'utilise `bs_dodup` pour les métadonnées, résout bien les URL relatives.
- **Contournement retenu** : le DoD pointe sur `deb.debian.org`, figé par épinglage. Son `InRelease` doit être identique, au sha256 près, à celui de l'instantané du 29/10/2026 (point release du 12/09/2026). Il est vérifié à l'installation et le sera de nouveau en fin de banc.
- **Volume téléchargé** pour le premier build : 466 rpm (Rocky) et 202 deb (Debian). Le vault Rocky est lent, environ 30 paquets par minute.
