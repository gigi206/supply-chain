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
