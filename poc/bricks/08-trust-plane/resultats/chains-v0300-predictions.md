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
