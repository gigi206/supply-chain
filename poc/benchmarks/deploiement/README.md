# Déploiement de la plateforme : Argo CD, Flux ou helmfile (hors ADR 0000)

**Demande du propriétaire (19/11/2026, heure de Paris)** : « Oui, évalue ». Sa question : pourquoi Argo CD, prévu en phase 4 à partir de la version 3.5.4 pour déployer la plateforme elle-même, et pas un autre outil comme helmfile ?

**Ce qui existe (cadre écrit à 23:07:49 UTC, avant tout relevé).**
- Argo CD n'a jamais été comparé à un autre outil. [docs/00](../../../docs/00-etude-existant.md), l. 73 (étude du 28/10/2026), le cite en une ligne : « GitOps de la plateforme ; releases SLSA L3 ». La faille du repo-server, corrigée en 3.5.4, fixe la version minimale. Le verdict est « Phase 4 ».
- [docs/04](../../../docs/04-sante-projets.md) le juge « Sain » (Scorecard 8,9). Flux et helmfile n'y figurent pas.
- **La phase 4 n'est définie nulle part** ailleurs que dans cette ligne. **Aucune exigence écrite ne porte sur le déploiement.**
- **Aujourd'hui, dans le PoC**, trois modes d'installation, orchestrés par des scripts de brique et des tâches `mise` :
  - presque tout en manifestes rendus (kustomize, `helm template`) puis appliqués par `kubectl apply` ;
  - Helm 4.3.1 depuis l'hôte pour Cilium, CoreDNS et metrics-server : option (b) du propriétaire du 01/11/2026, puis D1 de la 08b, sans HelmChart ;
  - des services systemd hors cluster (Zot, Forgejo et Alloy, sur `sc-stockage` notamment).

  Le contrôleur Helm de RKE2 ne se désactive pas (docs/04, l. 187). Helm est « À surveiller, hors chemin critique » : aucune provenance dans ses releases, et la diversité des employeurs n'est pas vérifiée (docs/04, l. 124). Cet existant sert de **référence**, ce n'est pas un candidat.
- **Prédictions non aveugles** : j'ai déjà dit de mémoire au propriétaire que Flux vérifierait les signatures de ses sources OCI et qu'helmfile ne corrige pas les dérives. Les prédictions ci-dessous servent à le confirmer ou à le corriger.

**Candidats** : Argo CD (dernière release, au moins 3.5.4), Flux (`flux2` et les contrôleurs qu'il déploie), helmfile. Fleet n'est pas évalué sans demande.

**Méthode.**
- À sec, sans note ni grille, tags épinglés. Lecture des manifestes de release et de la doc par l'API de GitHub. Pas de clone complet : `/home` est à 29 G, réservés aux relances du 19/11.
- **Rien n'est installé et aucun binaire n'est téléchargé.**
- Estimation : **0,5 pw**. Au-delà de 1 pw, décision avec le propriétaire.

**Critères, tirés de l'écrit seulement** :
- **G1** (ADR 0000, l. 145) : comptes de service sans lecture ni écriture des Secrets de tout le cluster. On relève les ClusterRoles par défaut ;
- **G2** (docs/02, « Séparation des zones ») : un composant dans le cluster qui écrit partout franchit les zones. Où tourne-t-il, avec quels droits ?
- **G3** (docs/02, « Tout est adressé par digest ») : sources et charts épinglables par digest ;
- **G4** (docs/01, menace B : commits signés SSH, gittuf) : vérification de signature des sources, git (SSH ou OpenPGP) et OCI (cosign) ;
- **G5** (exigence d'audit : tout dans Grafana) : où vont les journaux de l'outil. L'audit de l'API Kubernetes est collecté (19b, J3, mesuré sous k3s ; non relu sous RKE2) ;
- **G6** (docs/04) : santé, sans « Risqué », images et releases signées ;
- **G7** (rejeu de zéro) : amorçage. Cilium passe avant tout contrôleur, donc le chemin par l'hôte reste ;
- **G8** (docs/04, « tout outil est audité ») : dépendances et binaires annexes à auditer en plus.

**Décrits sans être jugés**, faute d'exigence : la réconciliation continue (détection et correction des dérives), le modèle tirer ou pousser, l'interface. **C'est la décision du propriétaire sur ces points qui départagera tirer et pousser.**

**Prédictions (avant tout relevé).**
- **DP1 (G1, G2)** : Argo CD (`application-controller`) et Flux (`kustomize-controller`, `helm-controller`) sont liés par défaut à des droits de type `cluster-admin`, Secrets compris. helmfile n'a aucun composant dans le cluster : ses droits sont ceux du `KUBECONFIG` du lanceur. Confiance haute pour Argo CD et Flux.
- **DP2 (G4, git)** : Argo CD et Flux vérifient les commits signés en OpenPGP. La vérification des signatures SSH est incertaine pour les deux. helmfile ne vérifie rien côté git. Confiance moyenne.
- **DP3 (G4, OCI)** : Flux vérifie nativement les artefacts OCI signés par cosign (`OCIRepository`, `verify`). Argo CD ne le fait pas nativement. helmfile s'appuie sur la vérification de Helm (fichiers `.prov` en OpenPGP). Confiance moyenne pour Flux, faible pour les deux autres.
- **DP4 (G3)** : les trois épinglent un commit git par SHA et un chart OCI par digest. Confiance faible pour helmfile.
- **DP5 (G6)** : Argo CD « Sain », comme dans docs/04, avec des releases à provenance SLSA. Flux « Sain ». helmfile au moins « À surveiller » : peu de mainteneurs, et releases signées non établies. Confiance moyenne.
- **DP6 (G7)** : Argo CD et Flux s'installent eux-mêmes depuis l'hôte, après Cilium. helmfile fait tout depuis l'hôte, Cilium compris. Confiance haute.
- **DP7 (G5)** : les journaux des contrôleurs d'Argo CD et de Flux arrivent dans Loki par Alloy, comme tout pod. helmfile ne laisse que l'audit de l'API, plus ce que le lanceur garde, s'il n'est pas collecté à part. Confiance moyenne.
- **DP8 (G8)** : Argo CD embarque Redis, Dex et le repo-server (qui rend les manifestes, avec des plugins possibles). helmfile exige le greffon `helm-diff` pour `diff` et `apply`, et Helm 4 est peut-être pris en charge. Flux ne dépend d'aucun service externe. Confiance moyenne.

## Résultats

À venir.
