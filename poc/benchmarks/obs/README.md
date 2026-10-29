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
- Debian 13 : `snapshot.debian.org`, instantané `20261029T000000Z` ;
- Rocky 9.7 : vault, figé depuis la sortie de la 9.8.
