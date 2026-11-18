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

Note écrite à 23:11:29 UTC, le 18/11/2026 (le 19/11 à Paris). Journaux : [`sante.log`](resultats/sante.log) (23:08:32 à 23:09:03 UTC) et [`lecture.log`](resultats/lecture.log) (fin à 23:10:23 UTC). Versions lues : **Argo CD v3.6.2** (18/11/2026), **Flux v2.10.0** (26/10/2026 ; contrôleurs source v1.10.1, kustomize v1.10.1, helm v1.7.1), **helmfile v1.8.4** (13/11/2026).

| Critère | Argo CD v3.6.2 | Flux v2.10.0 | helmfile v1.8.4 |
|---|---|---|---|
| **G1, G2** : droits par défaut | **Non tenu** : `application-controller` a `*` sur `*` dans tout le cluster ; `argocd-server` a `get`, `patch` et `delete` sur `*`, Secrets compris | **Non tenu** : `kustomize-controller` et `helm-controller` sont liés à `cluster-admin` (`cluster-reconciler`) | Sans objet dans le cluster : aucun composant ; les droits sont ceux du `KUBECONFIG` du lanceur, comme aujourd'hui |
| **G3** : digests | Charts OCI par tag ou par digest (`oci.md`, l. 50) | `OCIRepository` par `.spec.ref.digest` | **Non établi** : la doc de configuration ne mentionne pas d'épinglage par digest |
| **G4** : commits signés | **GnuPG seulement** (seule méthode de `source-integrity.md`) ; **pas de SSH** | **OpenPGP et SSH** (`gitrepositories.md`, l. 710) | Rien côté git (fichiers locaux) |
| **G4** : sources OCI signées | Rien dans `oci.md` | **cosign et Notation** (`ocirepositories.md`, l. 615) | Champ `verify: true` (doc de configuration), passé à Helm d'après la doc ; non lu dans le code |
| **G6** : santé | Scorecard 8,9. 40 releases en 6 mois. Commit du tag signé. Provenance in-toto de la CLI. Image principale avec attestation (`cosign tree`). 182 auteurs sur 90 jours, plusieurs entreprises. **60 avis, dont 5 critiques en 2026**, presque tous dans le repo-server (Kustomize, Jsonnet), corrigés en 3.3.15, 3.4.10, 3.5.4 et 3.6.0-rc2 | Scorecard 9,4 (contrôleurs : 8,0 à 8,8). 9 releases en 6 mois. Tag et commit signés. `provenance.intoto.jsonl` et sommes signées par sigstore. Images des contrôleurs avec attestation. 23 auteurs sur 90 jours : **8 adresses gmail font 131 commits sur 164**, employeurs non vérifiables. SECURITY.md de l'organisation. 7 avis | Scorecard **n/d**. 15 releases en 6 mois. Commit du tag signé. `packslip.sigstore.json` dans la release (non vérifié). 26 auteurs, dont 73 commits de robots ; adresses noreply surtout. SECURITY.md présent. 0 avis |
| **G7** : amorçage | Cilium d'abord depuis l'hôte, puis Argo CD depuis l'hôte (lecture logique, non mesurée) | Pareil | Tout depuis l'hôte, Cilium compris : le chemin d'aujourd'hui |
| **G8** : composants à auditer en plus | Redis (`public.ecr.aws`) et Dex (`ghcr.io`) : **aucune signature ni attestation** vue par `cosign tree`. Le repo-server rend les manifestes, plugins compris | Sept contrôleurs, tous `ghcr.io/fluxcd` ; aucun service externe dans le manifeste | Greffon **`helm-diff`** exigé (`helmfile init`), à auditer. Helm 3 et 4 pris en charge, et Helm 4.3.1 est déjà dans `mise.toml` |
| **G5** : journaux | Pods dans le cluster. Collecte par Alloy des journaux de pods **non relue** pour cette note | Pareil | Audit de l'API (19b, J3, sous k3s). La sortie du lanceur n'est collectée que si on la prévoit |
| **Décrits sans être jugés** | Réconciliation continue, dérive corrigée, interface web | Réconciliation continue, dérive corrigée, pas d'interface | Lancement ponctuel, aucune correction de dérive entre deux lancements |

**Prédictions** :
- **tenues** : DP1, DP3 (à la lecture), DP6 (à la lecture), DP8 ;
- **tenue en partie** : DP2. Pour Argo CD, GnuPG seulement, comme prévu. La vérification SSH, laissée incertaine pour les deux, existe chez Flux ;
- **non tenue pour helmfile** : DP4 (pas d'épinglage par digest trouvé) ;
- **DP5** :
  - Argo CD « Sain » : inchangé ;
  - Flux « Sain » **non établi** : la diversité des employeurs n'est pas vérifiable ;
  - helmfile au moins « À surveiller » : tenue (Scorecard n/d, employeurs non vérifiés) ;
- **DP7 : non vérifiée.**

**Ce qui départage, et revient au propriétaire.** Aucune exigence écrite ne demande une réconciliation continue.
- **Si elle est voulue (modèle « tirer »)** :
  - Argo CD et Flux ont tous deux des droits de type `cluster-admin`, donc G1 et G2 ne tiennent pour aucun ;
  - Flux couvre mieux nos exigences de source : commits signés **SSH**, c'est la menace B de docs/01, et artefacts OCI vérifiés par **cosign**, c'est la chaîne Zot et cosign du PoC ;
  - Flux a moins de composants à auditer ;
  - Argo CD ne vérifie que le GnuPG, embarque Redis et Dex sans signature, et a eu 5 avis critiques en 2026 dans le repo-server ;
  - pour Flux, la diversité des employeurs n'est pas établie.
- **Sinon (modèle « pousser », celui d'aujourd'hui)** :
  - helmfile ajoute une déclaration ordonnée au-dessus de Helm, déjà utilisé, sans aucun droit dans le cluster ;
  - il faut auditer `helm-diff` ;
  - l'épinglage par digest n'est pas établi, et rien ne vérifie les sources git ;
  - les scripts actuels restent la référence.

**Portée.** Tout est lu, rien n'est installé ni exécuté. Les signatures d'image sont relevées par `cosign tree` au tag, sans `cosign verify` d'identité. Aucune décision, aucune recommandation à ce stade. La note « Phase 4 » de docs/00 et le minimum 3.5.4 de docs/04 restent tels qu'ils sont écrits.
