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

À venir.
