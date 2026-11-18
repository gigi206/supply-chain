# PaC : Tekton Pipelines-as-Code face à Triggers et à l'intercepteur HMAC (hors ADR 0000)

**Demande du propriétaire (18/11/2026)** : « Oui, évalue PaC ». PaC n'avait été vu qu'à l'intérieur du banc Konflux (A1, 29/10/2026, PaC v0.50.0) et n'avait jamais été évalué comme déclencheur à part.

**But** : dire si PaC peut remplacer le déclencheur retenu (Tekton Triggers, EventListener et intercepteur HMAC Forgejo, avec rattrapage des webhooks perdus : [docs/02](../../../docs/02-architecture.md)). L'évaluation se fait **à sec** : santé selon les critères de [docs/04](../../../docs/04-sante-projets.md), puis lecture du code à un tag épinglé.

**Cadre (note écrite à 22:11:40 UTC, avant tout relevé et toute lecture du code).**
- **Pas de grille nouvelle ni de note chiffrée.** Les grilles de l'ADR 0000 sont figées, et PaC n'y a pas de ligne. Le verdict se donne exigence par exigence : tenue, non tenue ou non mesurée.
- **Rien dans le cluster.** Un banc réel serait une installation : il demandera l'accord du propriétaire, si la lecture ne suffit pas à trancher.
- **Version épinglée** : la dernière release de `tektoncd/pipelines-as-code` (dépôt déplacé depuis `openshift-pipelines/pipelines-as-code`), par tag et SHA complet. La signature du tag est vérifiée si elle existe. A1 portait sur PaC v0.50.0, embarqué par l'opérateur Tekton v0.81.1 de Konflux v0.2.2 ([résultats de A1](../konflux/resultats/README.md)).
- **Estimation : 0,5 pw.** Au-delà de 1 pw, la règle du 2× déclenche une décision avec le propriétaire.
- **Écritures** : chaque constat cite le fichier, la ligne et le SHA, dans un journal de `resultats/`. Dans les journaux, seuls les domaines des adresses e-mail apparaissent.

**Exigences confrontées.**
- **E1** ([docs/01](../../../docs/01-exigences.md), menace D) : webhook non signé **ou rejoué** refusé.
- **E2** (docs/02, « Aucun secret dans la zone build ») : ni le secret du webhook ni un identifiant git dans l'espace des builds.
- **E3** (brique 08, J6, Trusted Resources) : les tâches viennent de bundles signés par le résolveur `bundles` seul ; une spec en ligne est refusée.
- **E4** : rattrapage des webhooks perdus.
- **E5** : comptes de service sans lecture des Secrets de tout le cluster (suite de l'ADR 0000, l. 145).
- **E6** : support de Forgejo et son statut (stable ou aperçu).
- **E7** : santé selon docs/04, sans verdict « Risqué ».
- **E8** (lecture) : ce que PaC ajoute à la provenance de Chains.

**Prédictions (avant tout relevé et toute lecture du code).**
- **PA1 (E7)** : verdict « À surveiller » au moins, car PaC est en 0.x. Confiance haute pour ce minimum ; le reste des critères est inconnu.
- **PA2 (E1)** : signature contrôlée ; **aucune déduplication par identifiant de livraison** au tag épinglé, donc rejeu accepté. **Prédiction non aveugle** : A1 a mesuré ce rejeu sur v0.50.0. Confiance moyenne, car quatre versions mineures ont paru depuis.
- **PA3 (E3)** : PaC lit `.tekton/` dans le dépôt (A1 l'a vu sur une PR) et crée un PipelineRun dont la spec est **embarquée** : non compatible tel quel avec le refus des specs en ligne. Confiance moyenne : un `pipelineRef` vers un bundle est peut-être laissé tel quel.
- **PA4 (E2)** : PaC crée un secret git (`pac-gitauth-…`, vu dans la provenance de A1) dans l'espace du PipelineRun, donc dans la zone build. Confiance moyenne ; une option pour le désactiver existe peut-être.
- **PA5 (E4)** : pas de rattrapage des webhooks perdus. Confiance faible.
- **PA6 (E5)** : le contrôleur peut lire les Secrets de tout le cluster. Confiance moyenne.
- **PA7 (E6)** : Forgejo passe par le fournisseur « gitea », avec un statut d'aperçu. Confiance moyenne.
- **PA8 (E8)** : des annotations `pipelinesascode.tekton.dev/*` dans la provenance, comme dans A1 (Chains de Konflux, v0.29.1). Confiance haute.

## Résultats

Note écrite à 22:18:13 UTC, le 18/11/2026. Journaux : [`sante.log`](resultats/sante.log) (22:12:47 à 22:12:59 UTC) et [`lecture-code.log`](resultats/lecture-code.log) (22:15:17 UTC). Version lue : **v0.54.0** (12/11/2026), commit `bb2df3052556e2c7516eb1146a02e3ece5c4f252`. Le tag est léger, et GitHub ne trouve pas le commit signé. Le clone est à `~/.cache/supply-chain-poc/pac/depot-20261118T221251Z`, sans aucune modification.

### Santé (E7, PA1 tenue) : « À surveiller »

- **Scorecard** : 5,2 au relevé de l'API du 09/11/2026, sous l'ancien chemin `openshift-pipelines/pipelines-as-code`. Détail : Maintained 10, Signed-Releases 0, Code-Review 7. Le nouveau chemin `tektoncd/pipelines-as-code` rend « n/d ». Dans le journal, la ligne de l'ancien chemin porte « oui » en chemin critique : c'est une erreur du script, PaC n'est pas sur le chemin critique.
- **Releases** : v0.54.0 du 12/11/2026, et douze releases du 10/09 au 12/11/2026, sur plusieurs branches (0.27, 0.42, 0.48, 0.50 et la dernière).
- **Signatures** : la release est non signée et le commit du tag non plus. `cosign tree` de l'image du contrôleur ne montre qu'un SBOM, sans signature ni attestation.
- **Activité sur 90 jours** :
  - 103 commits, 16 adresses d'auteur et 16 commits de robots ;
  - redhat.com : 7 auteurs et 78 commits ;
  - adresses d'entreprise hors Red Hat : 2 commits sur 103 (fossa.io et bit.admin.ch) ;
  - le reste vient de gmail, hotmail et noreply de GitHub, dont l'employeur n'est pas vérifiable.

  Le critère « au moins 2 employeurs » n'est donc pas établi au-delà de Red Hat.
- **Processus de sécurité** : pas de SECURITY.md dans le dépôt, mais celui de l'organisation `tektoncd/.github` existe. Trois avis publiés en 2026 :
  - GHSA-8m5v-wh4r-5j96, élevé : élévation de privilège par la création d'un CR Repository ;
  - GHSA-f5f4-3hh4-f54m, élevé : GitHub App ;
  - GHSA-6f2p-296r-cc28, moyen : GitHub App.
- **CLA** : aucune mention.
- **Maturité** : 0.x.
- **Verdict selon les critères de docs/04** : « À surveiller », pour un Scorecard inférieur à 6, des releases non signées et la maturité 0.x. Rien ne relève de « Risqué ».

### Exigences

| Exigence | Verdict | Preuve |
|---|---|---|
| **E1** : rejeu refusé | **Non tenue** (PA2 tenue) | Lecture : la validation Forgejo ou Gitea est un HMAC du corps seul (`gitea.go` l. 236 à 266). L'identifiant de livraison ne sert qu'aux journaux (`adapter.go` l. 176 à 179 et 294 à 301), et la recherche ne trouve aucun anti-rejeu. Mesure : sur v0.50.0, le rejeu est accepté (A1, T5). Le rejeu n'a pas été remesuré sur v0.54.0. **Notre chaîne** refuse le rejeu à la création : un seul PipelineRun par commit, `AlreadyExists` mesuré le 13/11 ([`tekton-essais_webhook.log`](../../bricks/08-trust-plane/resultats/tekton-essais_webhook.log), cas F et G) |
| **E2** : aucun secret dans la zone build | **Non tenue par défaut** (PA4 tenue en partie). Une configuration est possible à la lecture, **non mesurée** | Le PipelineRun est créé dans l'espace du CR Repository (`pipelineascode.go` l. 384). `secret-auto-create` vaut `true` par défaut (`config.go` l. 82) : un secret git est alors créé dans ce même espace (l. 330 à 346). Le secret du webhook et le jeton du fournisseur viennent de l'espace du Repository, ou de celui du **Repository global** par héritage (`inherit.go` l. 24 à 34, `secret.go` l. 78 à 100). Repository global et `secret-auto-create: false` tiendraient donc E2 sur le papier. Le clone devrait alors se passer d'identifiant |
| **E3** : tâches par bundles signés, pas de spec en ligne | **Compatible à la lecture, non mesurée** (PA3 **non tenue**) | PaC n'embarque une tâche ou un pipeline que si `resolver` est vide (`resolve.go` l. 142 à 165, `remote.go` l. 215 à 231). Un `pipelineRef` avec `resolver: bundles` est laissé à Tekton et à Trusted Resources. **Mais le PipelineRun lui-même vient de `.tekton/` dans le dépôt** : commit de l'événement par défaut, ou branche par défaut avec `pipelinerun_provenance: default_branch` (`types.go` l. 111 à 117, `gitea.go` l. 509 à 518). Ses champs (paramètres, `podTemplate`, compte de service) sont alors choisis par le dépôt. Chez nous, la forme du PipelineRun est fixée par le gabarit de Triggers, dans la zone Confiance. Rappel de la brique 05 ([`m4b-predictions.md`](../../bricks/05-rpm-mock/resultats/m4b-predictions.md), l. 514, d'après la doc de Tekton v1.15.5) : l'`env` du `podTemplate` l'emporte sur celui des pas des tâches signées |
| **E4** : rattrapage des webhooks perdus | **Non tenue à la lecture**, confiance faible (PA5 tenue) | La recherche par mots-clés ne trouve que `kubeinteraction/wait.go`, qui ne sert pas à ça. Une absence trouvée par recherche n'est pas une preuve forte |
| **E5** : pas de lecture des Secrets de tout le cluster | **Non tenue** (PA6 tenue) | Le contrôleur et le watcher ont, par ClusterRoleBinding, `get`, `create`, `update` et `delete` sur tous les Secrets du cluster (`201-controller-role.yaml`, `202-watcher-role.yaml`). **Notre chaîne ne la tient pas non plus** : les intercepteurs de Triggers lisent encore les Secrets de tout le cluster (ADR 0000, l. 145) |
| **E6** : Forgejo | Support en **Tech Preview** (PA7 tenue) | La doc de PaC dit que Forgejo n'est pas recommandé en production (`requirements.md` l. 189) |
| **E8** : ce que PaC ajoute à la provenance | Lecture de A1, **non remesurée** (PA8 tenue) | Annotations `pipelinesascode.tekton.dev/*` (branche, expression CEL, expéditeur, nom du secret git, etc.) dans la provenance de A1, avec le Chains de Konflux v0.29.1 ([`provenance-3aa51998d84c.json`](../konflux/resultats/provenance-3aa51998d84c.json)) |

**Bilan des prédictions** : PA1, PA2, PA5, PA6, PA7 et PA8 tenues ; PA4 tenue en partie ; PA3 non tenue.

**Portée.** Tout est lu, sauf E1 (mesuré sur v0.50.0 en A1) et E8 (A1). Rien n'a été installé ni exécuté. La lecture porte sur le seul fournisseur Forgejo ou Gitea, au tag v0.54.0. **Aucune recommandation ni décision** à ce stade. Effort : 18/11/2026, de 22:11:40 (cadre) à 22:18:13 UTC, pour 0,5 pw estimé.

### Corrections datées du 18/11/2026, écrites à 22:21:36 UTC (après relecture par le conseiller)

Journal : [`lecture-complement.log`](resultats/lecture-complement.log), 22:21:00 à 22:21:05 UTC.

- **Cadre, « avant tout relevé »** : c'est trop fort. Avant le cadre, j'avais déjà lu deux choses par l'API de GitHub : les huit dernières releases (v0.54.0 du 12/11/2026 en tête) et la liste des fichiers de la racine du dépôt (SECURITY.md n'y figure pas). Les prédictions PA1 et PA7 ne sont donc pas tout à fait aveugles.
- **E1, recherche d'un anti-rejeu.** Les 35 occurrences de `lecture-code.log` (l. 53 à 89) sont sans rapport avec un rejeu de webhook : déduplication des OWNERS, des fichiers modifiés et des dépendances de groupes, commentaires de GitHub, nouvel essai HTTP vers la forge. **Deux lectures complètent E1** :
  - Le contrôleur résout les PipelineRuns avec `GenerateName: true` (`match.go` l. 409). Le `name` d'un PipelineRun de `.tekton/` est alors remplacé par un `generateName` (`remote.go` l. 252 à 254). **Notre parade, un nom par commit et `AlreadyExists` au rejeu, n'est donc pas disponible avec PaC**.
  - Le filtre des PipelineRuns existants pour un même SHA ne vaut que pour `/retest` et `/ok-to-test` (`annotation_matcher.go` l. 482 à 487), et ne retient que les runs réussis.

  E1 reste **non tenue**, et n'est pas tenable par un nom de PipelineRun. Non remesuré sur v0.54.0.
- **E3, « champs choisis par le dépôt »** : `types.go` dit d'où vient le fichier, pas que ses champs passent. La preuve que les champs passent est la **mesure de A1**, sur PaC v0.50.0 sous Konflux : une PR a déclaré dans `.tekton/` un PipelineRun hostile, avec un `taskSpec` en ligne (test 2) et une étape privilégiée, uid 0, `hostPath: /` (test 4). PaC l'a créé, et rien ne l'a refusé à l'admission ([résultats de A1](../konflux/resultats/README.md), tests 2 et 4). Chez nous, Kyverno refuserait ces deux formes, ce qui n'est pas mesuré avec PaC. Rien ne borne en revanche l'`env` du `podTemplate`.
- **PA5** : « **non contredite** », et non « tenue ». L'absence n'a été cherchée qu'avec trois mots-clés.
- **Santé** :
  - le délai de correction des CVE **n'a pas été relevé** ;
  - « sans signature ni attestation » ne vaut que pour ce que `cosign tree` montre, au tag, des **trois** images de `release.yaml` (contrôleur, watcher, webhook) : un SBOM seulement, ni signature ni attestation. Les attestations de GitHub (`gh attestation`) n'ont pas été relevées.
- **docs/00, correction du §2** :
  - « le code donne la même chose » devient « à la lecture, non remesuré » ;
  - « cette phrase date d'avant A1 » est vérifié : elle a été introduite par le commit `9d530a0` du 28/10/2026, la veille de A1.
- **docs/00, ligne PaC du §3** : « statuts et commentaires dans la forge » ne repose sur aucun journal archivé. Ce n'est pas relevé.
- **Verdict « À surveiller »** : c'est l'application littérale des critères de docs/04, pas une décision du propriétaire.
- **Non touchés** : docs/03, qui valide les briques, et les ADR. PaC n'est ni une brique ni une évaluation de l'ADR 0000, dont les grilles sont figées, et aucune ADR ne porte sur le déclencheur.

### Note datée du 18/11/2026, écrite à 22:26:26 UTC : adoption par Konflux (remarque du propriétaire, « konflux adopte pac par defaut »)

- **Fait.** Dans A1, PaC était le déclencheur de Konflux v0.2.2. L'opérateur Tekton l'installe, et le build-service crée le webhook vers le contrôleur PaC ([résultats de A1](../konflux/resultats/README.md), point 4 des adaptations ; [README de A1](../konflux/README.md), « PaC en mode Forgejo »).
- **Oubli de la note de 22:18:13 UTC.** Selon docs/04, l'adoption pondère le verdict de santé, et je ne l'ai pas prise en compte. Le verdict reste pourtant « À surveiller » : la règle le donne dès qu'un critère manque, et il en manque trois (Scorecard inférieur à 6, releases non signées, maturité 0.x). L'adoption par Konflux plaide en revanche pour un projet suivi, ce que confirment les 103 commits sur 90 jours.
- **Ce que l'adoption ne dit pas pour nos exigences.** Dans Konflux, la forme du PipelineRun vient du dépôt (`.tekton/`). Ce qui protège vient ensuite, à la porte de release : les règles Conforma `required_tasks` et `trusted_task`, citées dans A1. Avant la porte, A1 a mesuré qu'une PR fait tourner une étape privilégiée avec `hostPath: /` (test 4). A1 a aussi mesuré que Konflux accepte le rejeu (test 5, même PaC). Notre architecture fixe la forme du PipelineRun dans la zone Confiance, avant l'admission. **E1, E3 et E6 restent donc tels qu'ils sont écrits.** Le choix de Konflux répond à un autre modèle de menace : la protection se fait à la release, et Forgejo n'y est pris en charge qu'en partie ([docs/00](../../../docs/00-etude-existant.md), §2).

## Banc en cluster : protocole et prédictions (à sec, note écrite à 22:35:25 UTC, le 18/11/2026)

**Décision du propriétaire (18/11/2026)** : « Banc PaC en cluster », en réponse à « Que décides-tu pour PaC ? ». La décision fixe qu'il y a un banc, pas où il tourne ni ce qui s'installe. **Rien n'est installé ni lancé** avant un accord sur le lieu et les téléchargements.

**Correction d’un message précédent au propriétaire.** J'y ai rangé le rattrapage des webhooks perdus parmi ce que notre chaîne ne tient pas non plus. C'est faux : notre réconciliateur le tient, mesuré le 13/11/2026 ([`politique-rattrapage.log`](../../bricks/08-trust-plane/resultats/politique-rattrapage.log)). Forgejo n'a pas relivré un push perdu, et le PipelineRun a été créé par le rattrapage. Ce point départage, en notre faveur.

**Ce que le banc peut trancher.** Le statut de Forgejo (Tech Preview) et le Scorecard ne bougeront pas. Le banc ne peut renverser « garder Triggers » que si :
- le rejeu est refusé au tag v0.54.0, contrairement à la lecture ;
- **ou** PaC rattrape un webhook perdu ;
- **et** l'admission de `builds` borne la forme d'un PipelineRun venu de `.tekton/`, `env` du `podTemplate` compris.

**Estimation neuve : 1 pw** pour les étapes 1 et 2 (l'évaluation à sec en avait 0,5). Au-delà de 2 pw, décision avec le propriétaire.

### Étape 1 : cluster kind jetable, sur le modèle de A1

- **Cluster** : kind 0.33.0 (`mise.toml`), cluster `banc-pac`, avec un `KUBECONFIG` dédié jamais fusionné. Ports sur 127.0.0.1 seulement, nœud plafonné à 6 Gi.
  - Mémoire disponible relevée à 22:33 UTC : 11 Gi, avec les quatre VM du PoC allumées.
  - Docker est sur `/` (70 G libres) ; `/home` n'a que 29 G libres.
- **À vérifier avant lancement** :
  - version de Kubernetes du nœud : A1 a utilisé `kindest/node:v1.37.0@sha256:a1ed56cf…`, mais le `kubectl` de `mise.toml` est en 1.35.10, hors de l'écart toléré de ±1. Il faut l'image v1.35 listée par kind 0.33.0, avec le digest pris dans les notes de release, ou bien consigner l'écart ;
  - les besoins de PaC v0.54.0 : Pipelines v1.7.0 au minimum d'après sa doc (`requirements.md` l. 310), construit sur `tektoncd/pipeline` v1.18.0 (`go.mod` l. 33).
- **Téléchargements**, tous à archiver avec leur sha256 ou leur digest. **Rien n'est signé** côté PaC (voir la santé) :
  - nœud kind (image, par digest) ;
  - Tekton Pipelines v1.15.5 : manifeste **déjà téléchargé et vérifié** par la 08 (sha256 `c2fe5c2a…`), images par digest. C'est la version du PoC ;
  - `release.k8s.yaml` de PaC v0.54.0 (74 648 octets), appliqué depuis le disque, et ses trois images épinglées par digest (`crane digest`). Le binaire `tkn-pac` n'est pas téléchargé ;
  - Forgejo 15.0.11 : binaire de `mise.toml`, déjà vérifié. Il écoute sur la passerelle du réseau `kind`, en SQLite, avec un dépôt d'essai neuf.
- **Ne touche ni au webhook ni au dépôt `sample-app` du PoC.**
- **Cas mesurés** (secrets par fichier, journaux de PaC masqués, aucun message d'Event affiché) :
  - **K1** : installation, pods prêts, rôles sur les Secrets égaux à la lecture ;
  - **K2** : livraisons sans signature et à signature fausse (remesure de A1 sur v0.54.0) ;
  - **K3** : rejeu à l'identique (même corps, mêmes en-têtes, même `X-Forgejo-Delivery`) d'une livraison valide ; noms des PipelineRuns ;
  - **K4** : contrôleur à 0 réplique pendant un push, puis remis à 1. On attend 3 minutes et on compte les PipelineRuns de ce commit ;
  - **K5** : Repository global dans l'espace de PaC, Repository local sans secret, `secret-auto-create: false`. On regarde si le PipelineRun est créé et si un Secret apparaît dans l'espace du build (noms comptés, jamais lus). Le clone sans identifiant n'est pas mesuré ;
  - **K6** : `pipelinerun_provenance: default_branch`, avec une PR qui modifie `.tekton/`. Quelle définition est prise ?
  - **K7** : `pipelineRef` avec `resolver: bundles`, et la spec du PipelineRun créé, lue dans l'objet. L'exécution n'est pas demandée : il n'y a pas de registre de bundles dans kind ;
  - **K8** : PipelineRun hostile dans `.tekton/` (`env` au `podTemplate`, `taskSpec` en ligne, étape privilégiée). On archive l'objet créé par PaC, nettoyé des secrets et des UID, pour l'étape 2.
- **Démontage, écrit avant l'installation** : `kind delete cluster --name banc-pac`, arrêt de Forgejo, puis suppression du `KUBECONFIG` dédié par son nom en clair. Les journaux restent dans `resultats/` et les dossiers dans `~/.cache/supply-chain-poc/pac/`.

### Étape 2 : cluster du PoC, sans rien y installer

- Soumettre l'objet de K8, et ses variantes une à une, à l'admission de l'espace `builds` en **dry-run serveur** (`kubectl create --dry-run=server`).
- **À vérifier avant** :
  - que les webhooks de Kyverno et de Tekton acceptent le dry-run sans effet de bord (`sideEffects` de leurs configurations) ;
  - sous quelle identité soumettre l'objet (celle de l'EventListener).

### Étape 3, seulement si 1 et 2 laissent une question

Installer PaC dans le cluster du PoC. **Accord à part**, car :
- il faudrait des images non signées ;
- deux ClusterRoles écriraient tous les Secrets du plan de confiance ;
- il faudrait un jeton Forgejo réel ;
- Chains signerait les runs du banc.

### Prédictions (avant tout lancement)

- **K1** : installation en moins de 10 minutes ; rôles égaux à la lecture. Confiance haute.
- **K2** : les deux livraisons sont refusées, avec les messages de A1. Confiance haute (lecture et A1).
- **K3** : **rejeu accepté**, un second PipelineRun est créé, et les deux noms diffèrent (`generateName`). **Prédiction non aveugle** (A1 et lecture). Confiance haute.
- **K4** : aucun PipelineRun pour le commit poussé pendant l'arrêt. Confiance moyenne : l'absence n'a été cherchée que par mots-clés.
- **K5** : PipelineRun créé, aucun Secret neuf dans l'espace du build. Confiance moyenne.
- **K6** : définition de la branche par défaut. Confiance haute (lecture).
- **K7** : `pipelineRef` gardé tel quel, `resolver: bundles`. Confiance haute (lecture).
- **K8** : PaC crée l'objet hostile tel quel, sans filtre. Confiance haute (A1).
- **Étape 2** :
  - `taskSpec` en ligne et étape privilégiée refusés par l'admission de `builds` ;
  - **`env` du `podTemplate` admis**, d'après la brique 05 ([`m4b-predictions.md`](../../bricks/05-rpm-mock/resultats/m4b-predictions.md), l. 515).

  Confiance moyenne : le dry-run n'a jamais été essayé sur ce cluster.

### Note datée avant lancement (18/11/2026, écrite à 22:44:42 UTC) : accord « Oui, étapes 1 et 2 », écarts au protocole de `b25fc9d`

- **Accord du propriétaire** : « Oui, étapes 1 et 2 ». Script : [`banc.sh`](banc.sh), relu par le conseiller avant lancement. Modèles du dépôt d'essai : [`essai/`](essai/).
- **Vérifications faites avant d'écrire le script** :
  - kind 0.33.0 liste `kindest/node:v1.35.8@sha256:07b2536e…` dans ses notes de release : c'est le nœud retenu, compatible avec `kubectl` 1.35.10 ;
  - l'API de GitHub publie le digest de `release.k8s.yaml` (`62d6a4ee…`), que le script compare au fichier téléchargé ;
  - dans le cluster du PoC, tous les webhooks d'admission déclarent `sideEffects` `None` ou `NoneOnDryRun`, donc le dry-run est accepté ;
  - mon identité peut emprunter `declencheurs:el-forgejo`, et ce compte peut créer des PipelineRuns dans `builds`.
- **Écarts au protocole** :
  - **Une seule configuration pour tous les cas : celle de K5.** Repository global dans `pipelines-as-code`, avec les secrets ; Repository local sans secret ; `secret-auto-create: false`. La configuration par défaut n'est pas remesurée : A1 l'a vue, avec le secret `pac-gitauth-…` dans la provenance. **Si l'héritage du Repository global échoue**, le script s'arrête en KO à la référence. Ce sera le résultat de K5, et les autres cas repasseront avec un secret local, dans des journaux neufs ;
  - **K8 n'a pas d'étape privilégiée.** Elle tournerait vraiment dans le nœud kind. Le modèle hostile porte un `env` au `podTemplate`, un `taskSpec` en ligne et un `env` du même nom dans le pas : le journal du pod dira lequel l'emporte. L'étape privilégiée et `hostPath: /` sont ajoutés par `jq` à l'étape 2. Ils ne sont donc pas produits par PaC (A1 a mesuré qu'il les laisse passer). Comme la spec en ligne suffit à faire refuser l'objet, `v-hostile` ne prouve rien de plus que `v-enligne` sur l'étape privilégiée ;
  - **nœud en v1.35.8** au lieu de v1.37.0 ;
  - **le `KUBECONFIG` dédié reste en place** au démontage, vidé du contexte par kind (règle : pas de `rm` sur une variable) ;
  - **étape 2** : un PipelineRun réel de l'EventListener sert de témoin. Si le témoin est refusé, `v-env` n'est pas interprétable et le script s'arrête. Les quatre requêtes passent sous l'identité empruntée `el-forgejo` : leur fenêtre horaire est consignée pour l'audit.
- **Ordre et horaire.** Le banc tourne **avant** les relances du 19/11, jamais en même temps. Le cluster doit démarrer avant 23:15 UTC, et le démontage se faire avant 23:55 UTC. Sinon, l'étape en cours finit, le démontage suit, et les relances passent.
- **Prédiction ajoutée** : **K8 bis**, l'`env` du `podTemplate` l'emporte sur celui du pas. Confiance moyenne : c'est la doc de Tekton v1.15.5 citée par la brique 05, jamais mesurée chez nous.

### Résultats du banc, étapes 1 et 2 (18/11/2026, de 22:44:56 à 22:52:02 UTC ; note écrite à 22:52:55 UTC)

Journaux : [`preparer`](resultats/banc-preparer.log), [`cluster`](resultats/banc-cluster.log), [`tekton`](resultats/banc-tekton.log), [`pac`](resultats/banc-pac.log), [`forgejo`](resultats/banc-forgejo.log), [`depot`](resultats/banc-depot.log), [`cas`](resultats/banc-cas.log), [`admission`](resultats/banc-admission.log), [`demonter`](resultats/banc-demonter.log) ; objet de K8 : [`k8-objet.json`](resultats/k8-objet.json).

**Installation.**
- `release.k8s.yaml` a le sha256 du digest publié (`62d6a4ee…`), et le digest du contrôleur est celui de `sante.log`. Les images qui tournent sont toutes épinglées par digest.
- Pour Pipelines, les références par tag du manifeste sont des valeurs par défaut de configuration, pas des images lancées. Le compteur du script « références par tag restantes : 3 » est faux : il comptait aussi les lignes à digest.
- Temps : cluster en 36 s (client v1.35.10, serveur v1.35.8), Tekton en 27 s, PaC en 36 s.
- Forgejo 15.0.11 est joignable depuis le nœud kind sans règle sur l'hôte.

| Cas | Résultat | Prédiction |
|---|---|---|
| K1 | ClusterRoles du contrôleur et du watcher : `get`, `create`, `update` et `delete` sur tous les Secrets, comme à la lecture | tenue |
| K2 | Sans signature, puis signature fausse : HTTP 202, mais 3 → 3 PipelineRuns. Le contrôleur journalise les deux refus, avec les messages de A1 | tenue |
| K3 | **Rejeu à l'identique** (même corps, mêmes en-têtes, même `X-Forgejo-Delivery`) : 3 → **6** PipelineRuns, aux noms tous différents (`generateName`) | tenue (non aveugle) |
| K4 | Contrôleur arrêté pendant un push : une livraison Forgejo, en échec. 180 s après la relance : **0** PipelineRun pour ce commit. **Aucun rattrapage** | tenue |
| K5 | **L'héritage du Repository global fonctionne** : les PipelineRuns sont créés, et il n'y a **aucun Secret** dans `essai-pac` avant comme après. Les PipelineRuns portent pourtant l'annotation `git-auth-secret` (un nom, sans Secret). Le clone sans identifiant n'est pas mesuré | tenue |
| K6 | `default_branch` : la PR qui modifie `.tekton/k-pr.yaml` lance la définition de `main` (`marque = main`) | tenue |
| K7 | `pipelineRef` gardé tel quel (`resolver: bundles`), sans `pipelineSpec` | tenue |
| K8 | Objet hostile créé tel quel : `env` du `podTemplate` et `taskSpec` en ligne | tenue |
| **K8 bis** | **Mesuré** : le pas affiche `BANC_PAC=env-du-podTemplate`. L'`env` du `podTemplate` l'emporte sur celui du pas (Tekton v1.15.5, pas en ligne) | tenue |

**Étape 2, cluster du PoC.** Admission de `builds` en dry-run serveur, sous l'identité empruntée `declencheurs:el-forgejo`. Les quatre requêtes ont été faites à 22:51:53 UTC. Aucun objet n'a été créé : 0 `banc-pac-dry-*` dans `builds`.
- **Témoin** (PipelineRun réel de l'EventListener, `sample-app-86204c58…`, `pipelineRef` par bundle) : **admis**.
- **`v-env`** (le même, plus un `env` au `podTemplate`) : **admis**. Prédiction tenue.
- **`v-hostile`** (spec en ligne, étape privilégiée et `hostPath`, ajoutés par `jq`) : refusé par Kyverno (`tekton-references`, test 2 : spec en ligne interdite). Rien n'est conclu sur l'étape privilégiée.
- **`v-enligne`** (spec en ligne seule) : refusé par le webhook de validation de Tekton (`must not set the field(s): spec.pipelineSpec`).
- **Portée** : seule l'admission du PipelineRun est mesurée. Aucun pod n'est créé : ni Pod Security, ni les règles Kyverno sur les pods, ni Trusted Resources ne sont exercés.

**Ce que le banc tranche** (critères écrits avant le lancement) :
- le rejeu n'est pas refusé ;
- PaC ne rattrape pas un webhook perdu ;
- l'admission de `builds` ne borne pas l'`env` du `podTemplate`.

**Aucune des conditions qui renverseraient « garder Triggers » n'est remplie.** Concrètement : avec PaC, un dépôt qui écrit dans `.tekton/` un PipelineRun bien formé, `pipelineRef` par bundle signé compris, passe notre admission avec un `env` à lui. Ce dernier l'emporte sur celui des pas des tâches signées (K8 bis, mesuré sur un pas en ligne dans kind ; non mesuré sur une tâche venue d'un bundle). Avec Triggers, le `podTemplate` vient du gabarit, dans la zone Confiance.

**Ce que le banc ouvre pour notre chaîne aussi.** Notre admission laisse passer un `env` au `podTemplate`. Seul l'EventListener peut créer des PipelineRuns dans `builds` (docs/02), si bien que ce n'est pas exploitable par un dépôt. C'est en revanche une règle d'admission qui manque si cet invariant tombe. **Décision au propriétaire**, rien n'est changé.

**Démontage** : cluster `banc-pac` supprimé, Forgejo du banc arrêté (processus absent). Le `KUBECONFIG` dédié reste en place, vide de son contexte. Les dossiers restent dans `~/.cache/supply-chain-poc/pac/banc`.

**Effort** : de 22:44:56 à 22:52:02 UTC pour le banc, et de 22:11:40 UTC (cadre) à 22:52:55 UTC pour toute l'évaluation, préparation comprise. L'estimation était de 0,5 pw à sec, plus 1 pw pour les étapes 1 et 2 ; les heures ne sont pas converties en pw.
