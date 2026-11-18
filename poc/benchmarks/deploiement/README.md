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

### Corrections et compléments datés (18/11/2026, écrits à 23:16:06 UTC, après relecture par le conseiller)

Journal : [`lecture-2.log`](resultats/lecture-2.log), de 23:14:56 à 23:15:17 UTC.

**1. La raison de l'option (b) et de D1 départage.**
- L'option (b) du 01/11/2026 a été rejouée et mesurée : « aucune liaison vers `cluster-admin` dont un sujet est un compte de service » (README de la 08, l. 647). Le même filtre trouvait `helm-kube-system-cilium` sous le HelmChart.
- D1 de la 08b, l. 57, retient l'installation depuis l'hôte par Helm, « aucun compte `helm-*` ». Elle écarte les HelmChart de RKE2, qui donneraient des « comptes `helm-*` à `cluster-admin` probables ».
- **Argo CD et Flux réintroduiraient précisément un compte de service lié à des droits de type `cluster-admin`.** Ils rouvrent donc deux décisions déjà prises. « Pousser », par les scripts actuels ou par helmfile, les prolonge.

**2. Couverture de l'existant.**
- Aucun des trois ne déploie les services systemd hors cluster (Zot, Forgejo, Alloy sur `sc-stockage`). Ces services restent aux scripts.
- Pour les manifestes rendus (kustomize), helmfile les transforme en chart local et appelle `kustomize build` (`advanced-features.md`, l. 196 et 209). **Le binaire `kustomize` est donc à auditer en plus**, avec `helm-diff`.

**3. Argo CD : la variante d'installation compte.**
- Redis, Dex et `argocd-server` valent pour `install.yaml`.
- `core-install.yaml` n'a ni Dex ni `argocd-server`. Il garde Redis, et le ClusterRole `*` sur `*` de l'`application-controller`.
- `namespace-install.yaml` n'a **aucun ClusterRole ni ClusterRoleBinding** : il n'a que des Roles, mais il embarque Dex et Redis. Ses droits sur les autres espaces ne sont pas lus.
- G1 et G2 sont donc « non tenus **par défaut** ». Une installation par espace les borne, avec une portée non lue.

**4. Flux : bornage et symétrie.**
- Une `Kustomization` ou une `HelmRelease` peut emprunter un compte de service (`.spec.serviceAccountName` ; `kustomizations.md`, l. 543 ; `helmreleases.md`, l. 428). Le drapeau `--no-cross-namespace-refs` existe (l. 146).
- Les contrôleurs gardent pourtant leur liaison à `cluster-admin`, nécessaire pour emprunter. G1 et G2 sont « non tenus par défaut, bornables par emprunt ». Ce n'est pas mesuré.
- Ses contrôleurs rendent eux aussi des manifestes (kustomize et Helm), comme le repo-server d'Argo CD.
- Le manifeste par défaut contient deux contrôleurs d'images (`image-automation`, `image-reflector`) et `source-watcher`, dont la plateforme n'a pas besoin.
- Les sept images portent une attestation au tag (`cosign tree`), sans `cosign verify` d'identité.
- L'OpenPGP est archivé : `gitrepositories.md`, l. 634 et 694 à 700.

**5. Corrections du tableau.**
- **« 5 avis critiques en 2026 dans le repo-server »** est faux. Trois sur cinq le sont (Kustomize Helm, Kustomize remote, Jsonnet), plus un sur les AppProject, tous corrigés en 3.3.15, 3.4.10, 3.5.4 et 3.6.0-rc2. Le cinquième (extraction de Secrets par ServerSideDiff) est corrigé en 3.3.9 et 3.2.11.
- **« Redis et Dex sans signature »** : c'est ce que montre `cosign tree` au tag, et rien d'autre.
- **helmfile `verify`** : le champ est porté par un dépôt de charts, avec un `keyring` GPG (`configuration.md`, l. 59 et 60). C'est la provenance de Helm. Qu'il soit transmis à Helm n'est pas lu dans le code.
- **G5, DP7** : en 19b (L4, le 02/11/2026, sous k3s), les témoins J2 (journaux de pods) et J3 (audit de l'API) ont été lus dans Grafana (README de la 19b, l. 312). Les contrôleurs d'Argo CD et de Flux seraient donc collectés comme tout pod, et le lanceur de helmfile serait tracé par l'audit de l'API. Ce n'est pas remesuré sous RKE2. **DP7 est tenue à la lecture.**
- **Adoption** (docs/04 la fait peser, et je l'avais omise) : Flux se dit « graduated » à la CNCF dans son README. Le README d'Argo CD ne cite que le code de conduite de la CNCF, donc son statut n'est pas établi par cette lecture. helmfile ne mentionne pas la CNCF. Les verdicts ne changent pas.
- **Dates** : la demande est du 18/11/2026, 23:0x UTC (le 19/11 à Paris). Le titre du cadre (« 19/11/2026, heure de Paris ») et la ligne d'index sont ramenés à l'UTC.

**6. L'argument écrit pour Argo CD vaut aussi pour Flux.** docs/00, l. 73, donne « releases SLSA L3 ». Flux publie lui aussi `provenance.intoto.jsonl`, des sommes signées par sigstore et des images attestées. Il couvre en plus les commits signés SSH et les artefacts OCI signés par cosign.

### Recommandation (18/11/2026, écrite à 23:20:33 UTC, produite par le conseiller à la demande du propriétaire : « que recommande l'advisor ? »)

- **Pousser depuis l'hôte, avec les scripts actuels et Helm, sans adopter helmfile maintenant.** Si le propriétaire veut un jour tirer : **Flux plutôt qu'Argo CD**.
- **Appuis, tous archivés** :
  - pousser prolonge l'option (b) du 01/11 et D1 de la 08b, mesurées sans compte de service à `cluster-admin` ;
  - aucune exigence écrite ne demande la réconciliation continue, et la phase 4 n'est définie nulle part ;
  - helmfile apporte peu aujourd'hui : Helm ne sert que pour trois charts (Cilium, CoreDNS, metrics-server), le reste est en manifestes rendus et en services systemd. helmfile ajoute `helm-diff` et `kustomize` à auditer, son Scorecard est n/d, l'épinglage par digest n'est pas établi, et il changerait un chemin de rejeu déjà mesuré ;
  - Flux plutôt qu'Argo CD : commits signés SSH, artefacts OCI vérifiés par cosign, moins de composants.
- **Ce qui la renverserait** : une exigence de correction continue des dérives, ou une phase 4 à plusieurs clusters. Ce serait alors Flux avec emprunt de compte : un banc, et l'option (b) rouverte explicitement.
- **Limites** : tout est lu, rien n'est mesuré. helmfile n'a pas été exercé avec Helm 4.3.1. Le bornage des droits de Flux et d'Argo CD n'est pas mesuré.
- **Correction** : mon message précédent disait de helmfile qu'il « prolonge nos décisions ». C'est le fait de pousser qui les prolonge, par les scripts actuels ; helmfile n'est pas en service.
- **Besoin ouvert lié, non tranché** : « Opérateur Kubernetes » (transmis le 06/11/2026, à définir avec le propriétaire). Pour cette note de besoin, c'est « pas maintenant ; à réexaminer avec le multi-projets ». Elle cite « Helm ou Kustomize avec GitOps » parmi les alternatives non évaluées.

### Décision du propriétaire (2026-11-18T23:21:11Z) : « Garder les scripts »

En réponse à « Quel modèle de déploiement retiens-tu ? », après la recommandation du conseiller. La plateforme continue d'être poussée depuis l'hôte, par les scripts de brique et Helm, ce qui prolonge l'option (b) et D1 de la 08b. Ni Argo CD, ni Flux, ni helmfile ne sont retenus. Si une correction continue des dérives est exigée un jour, la question se rouvrira (Flux, banc, option (b) rouverte explicitement). La ligne « Phase 4 » d'Argo CD dans docs/00 et son minimum 3.5.4 dans docs/04 sont caducs pour le PoC, et rien n'est effacé.
