# Chains v0.30.0 : banc à sec, prédictions

Prédiction écrite le 2026-11-25T18:45:45Z, avant tout téléchargement de la source de v0.30.0 et avant toute lecture de son code par la session (le renommage vient des notes de #2041 lues le 24/11). Accord du propriétaire, verbatim : « J'autorise », sur la question « J'autorise le téléchargement de Go 1.27.3 et de la source de Chains v0.30.0 ? ».

## Ce qui change par rapport à la demande

- **Go 1.27.3 est déjà local** : `~/.cache/supply-chain-poc/chains-correctif/go-dl/go.tgz`, 70 588 678 octets, sha256 `65efbc80fdc1…` égal à celui que go.dev publie (18:44:40Z). Rien à télécharger. Le relevé du 25/11 (« le Go de l'hôte est 1.24.7, une chaîne récente à demander ») ne l'avait pas vu.
- Un clone local de Chains contient l'étiquette v0.29.9 ; il sert de référence, sans y toucher (il porte la branche de la PR amont).
- Seul téléchargement : le commit `b59bced2524ec2da5dcbe3f916c2109262b9b819` (v0.30.0), sans historique, avec son `vendor/`. Compilation hors réseau (`GOPROXY=off`, `-mod=vendor`).

## Dispositif

1. **Objets réels** : PipelineRun et TaskRuns du cluster, lus sans écriture (`kubectl get`), gardés hors du dépôt. Cas : `j7-sample-app` (`9539952b`), `sample-app-deb-6391fd43…`, `m5b-4-rpm-1`, `f2-prefetch-1`.
2. **Même programme dans les deux sources** : le format `slsa/v2alpha4` de Chains appelé sur ces objets, avec le `builder.id`, le `buildType` et l'inspection profonde de `chains-config.yaml`.
3. **Témoin du banc** : la sortie de v0.29.9 est comparée à la provenance signée dans Zot (cosign, clé de Chains). Si elle diffère pour une autre raison que l'état des objets après signature (annotations `chains.tekton.dev/*`, `finalizers`, `resourceVersion`), le banc n'est pas valable.
4. **Lecteurs**, sur l'énoncé ancien, sur l'énoncé neuf (sortie réelle de v0.30.0) et sur un mélange : règles de la porte par `ec opa eval` (bibliothèque `ebd3fbd2`, `porte.rego`, `taches.yml`, les règles `slsa3` et `trusted_task` que le banc sait évaluer hors registre), `genre()` de l'exportateur et du recalcul importés tels quels, et les sélections `jq` des scripts.

## Prédictions

| N° | Mesure | Attendu | Confiance |
|---|---|---|---|
| P1 | v0.29.9 contre la provenance signée | égale, aux métadonnées postérieures à la signature près | moyenne |
| P2 | v0.30.0, nom des dépendances de tâches | `pipelineTask/<nom>` (nom de la tâche dans la pipeline), une par tâche ; 0 dépendance `pipelineTask` | haute |
| P3 | v0.30.0, autres différences avec v0.29.9 (`buildType`, `builder`, `externalParameters`, `internalParameters`, sujets, autres dépendances, contenu des TaskRuns) | aucune | basse (code non lu) |
| P4 | Provenance de TaskRun seule | inchangée | moyenne |
| P5 | Porte, énoncé neuf seul | **refus** avec `porte.taches_vues` parmi les codes ; `porte.construction_kata` et `trusted_task` muets (aucune tâche vue) | haute |
| P6 | Porte, énoncé ancien seul | admis par les règles évaluées (aucun code `porte.*`), comme aujourd'hui | haute |
| P7 | Porte, mélange | ancien le plus récent : admis ; neuf le plus récent : refus `porte.taches_vues`. Aucun mélange n'admet une tâche non vue sous la seule provenance neuve | moyenne |
| P8 | Fermeture prouvée seulement par un énoncé neuf | **refus** `porte.fermeture_plateforme`, même si la provenance de l'image est ancienne | moyenne |
| P9 | `porte_test.rego` | reste vert : 39 tests sur 39, sans rien prouver du nom neuf. Témoin ajouté par le banc : les mêmes tests avec le nom neuf échouent (au moins un) | haute |
| P10 | `genre()` de l'exportateur et de `recalcul.py` | les deux rendent `image` au lieu de `tache` pour chaque dépendance de tâche ; ils restent d'accord entre eux, donc le seuil ne le verrait pas | haute |
| P11 | Sélections `jq` des scripts | vides sur l'énoncé neuf ; les mutants de `preuves.sh` l. 927 et de `s4d2.sh` l. 115 rendent l'énoncé inchangé | haute |

**Réfuté si** : P5 ou P8 rend une admission (échec ouvert, à signaler aussitôt) ; P2 donne une autre forme.

**Non mesuré par ce banc** : la signature et le stockage (`b1c0af9`, #2096), le contrôleur lui-même, la politique d'image Kyverno de la réserve C (lue seulement), l'enveloppe Go de la branche `claude/argo-l3`, `ec validate image` de bout en bout (il demande le registre et les noms du cluster).

## Résultat (2026-11-25T20:38:13Z)

Journaux : [provenances](chains-v0300-provenances.log) (P1 à P4), [lecteurs](chains-v0300-lecteurs-3.log) (P5 à P11). **0 écart sur P5 à P11 ; P3 et P4 réfutées ; aucune admission à tort : pas d'échec ouvert de la porte sur les cas joués.**

| N° | Résultat |
|---|---|
| P1 | Tenue : 4 provenances signées sur 4 égales à la sortie de v0.29.9 (`m5b-4-rpm-1` non comparé). Écarts retirés : annotations `chains.tekton.dev/*`, `resourceVersion`, `finalizers`, `kind`/`apiVersion`, `managedFields` (caché par `kubectl`, donc champ signé non comparé) |
| P2 | Tenue : `pipelineTask/<tâche>`, une par tâche, 0 `pipelineTask`, sur 5 PipelineRuns. La forme d'une matrice (`pipelineTask/<tâche>/<TaskRun>`) est lue dans la source, pas mesurée |
| P3 | **Réfutée** : les noms de `byproducts` changent aussi. Rien d'autre ne change (comparaison de tous les chemins). docs/04 l'annonçait déjà (« change les `byProducts` ») : la prédiction ne l'a pas repris |
| P4 | **Réfutée** pour la même raison, dans les TaskRuns qui ont des `byproducts` (8 sur 13 ; 5 TaskRuns `publier` inchangés) |
| P5 | Tenue, app et deb, énoncé neuf seul et tous renommés : refus `porte.taches_vues`, plus `tasks.pipeline_has_tasks` et deux codes `slsa_build_scripted_build` |
| P6 | Tenue : 0 code de refus |
| P7 | Tenue : ancien le plus récent, admis ; neuf le plus récent, refus |
| P8 | Tenue : `porte.fermeture_plateforme`, seul code (app : 4 provenances de fermeture ; deb : 8) |
| P9 | Tenue : 39/39 avec l'ancien nom ; avec le nom neuf, 5 réussites et 34 échecs |
| P10 | Tenue : `image` au lieu de `tache` chez l'exportateur **et** le recalcul, d'accord entre eux |
| P11 | Tenue pour les sélections (3 puis 0). L'effet sur les mutants est déduit de la sélection vide : les mutants n'ont pas été lancés |

**Trois passages.** Le premier ([journal](chains-v0300-lecteurs-premier-passage.log)), lancé à 2026-11-25T18:51:19Z, a été arrêté pendant le cas deb, entre 20:34:50Z (dernier relevé) et 20:35:42Z ; le processus avait alors plus de 1 h 43 min 18 s. `ec.oci.image_manifests` cherchait les bundles sur `sc-stockage.poc.test`, que l'hôte ne résout pas, et réessayait. Les bundles n'y étaient donc pas lus : ses résultats d'app valent pour `porte.*`, pas pour `trusted_task`. Le deuxième ([journal](chains-v0300-lecteurs-2.log), 20:35:42Z à 20:36:31Z) injecte les vrais manifestes, lus par l'adresse du registre à la même empreinte : mêmes codes. Il comptait deux fois chaque échec de P9 (68 au lieu de 34, `opa` liste les échecs deux fois). Le troisième, retenu (20:36:54Z à 20:37:42Z), ne change que ce compte.

**Limites** : énoncés neufs non signés (règles seules) ; nombre de fermetures lues = 0 quand l'énoncé neuf est seul, la règle de fermeture n'y est donc pas éprouvée (P8 la couvre) ; six des neuf paquets (`trusted_task`, `attestation_type`, `slsa_build_build_service`, `slsa_provenance_available`, `slsa_source_correlated`, `slsa_source_version_controlled`) n'ont rendu aucun refus : le banc ne dit pas s'ils refuseraient un énoncé neuf fautif ; `trusted_task`, muet, n'a vu aucune tâche. Le « Non mesuré » ci-dessus reste entier.
