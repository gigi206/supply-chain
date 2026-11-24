# Brique 07c : reconstruction de sample-app en Go 1.26.11

Origine : la 07b relève `GO-2026-6859` (stdlib 1.26.10, Medium) sur l'image `3a7ca1b1`, non couvrable par un VEX (code lié, atteignable par `OPTIONS *`). Choix du propriétaire du 24/11/2026 (verbatim) : « reconstruire l'image en Go 1.26.11. » → « oui » ; puis, sur l'enveloppe (« Où compter la reconstruction en Go 1.26.11 (environ 10 h, non mesurées) ? ») : « Chantier à part ». Cette réponse vaut aussi accord pour télécharger le module `golang.org/toolchain@v0.0.1-go1.26.11.linux-amd64` (proxy.golang.org, 71 800 213 octets, `h1:KyINmJ/FQdKRmDYGuTAAXkumyeR2DyUlSNHZj7XaLFg=` sur sum.golang.org), rangé à côté de 1.26.10 dans `~/.cache`, **sans toucher à `mise.toml`**.

**Estimation : 10 h (non mesurée) ; seuil de décision : 20 h.** Heures comptées ici, pas dans la 07b, à partir de la note de 2026-11-24T13:11:58Z.

## État (2026-11-24T15:13:31Z)

**Étapes 1 à 4 faites**, journaux dans [`resultats/`](resultats/07c-carte.md) : toolchain vérifiée ; image prédite sur l'hôte (`f5e6bcb0`) ; image de build `plateforme/builder-go-voie-d@8c11e856` (tag `go1.26.11`) ; `construire-image` re-signée (`4dcbc4b7`, ajoutée à la liste revue, `66a9f298` gardée) ; construction dans le cluster conforme ; scan : **5 vulnérabilités chi, 0 stdlib, 0 KEV** ; déclencheurs basculés, porte admise. **Étape 6 faite** : VEX chi de `f5e6bcb0` validé (« Oui, je valide »), signé sur accord nommé (« J'autorise ») et publié (`builds/vex/sample-app@b139ef42`, 5 énoncés, échéance 2026-12-24) ; scan manuel : **5 vulnérabilités, 0 KEV, 5 écartées par un VEX**, visible dans Grafana. **Étape 7, scripts du rejeu : faits à sec** (décision « Un seul digest ») : voie D en Go 1.26.11 (mesurée à sec, 14 cas), voie A, construction, images d'essai de J2 à J8, Kyverno, scans de la 07a et de la 06 portés à `f5e6bcb0` ; `publier-essai` re-signée sur accord (« J'autorise », bundle `17b50c7c`, ajouté en premier à la liste revue). Rien de ceci n'a tourné dans un cluster ; **ces scripts ne valent plus, lancés seuls, qu'après un rejeu de zéro** (images d'essai `f5e6bcb0` absentes du Zot en service ; `redemarrer.sh` reste sur `3a7ca1b1`). Constat hors périmètre : le deb de la 06 est encore compilé en Go 1.26.10 (`s4d.sh`). **VSA de `f5e6bcb0` préparée à sec** ([prédictions](../10-independent-replay/resultats/f5e6bcb0/predictions.md)) : cible `9539952b` (J7 du passage 2, fini à 13:27:42 UTC), `replay.sh` de la 10 paramétré par l'environnement (défauts inchangés), R1 `version_go` conforme (`go1.26.11`) ; sur accord « J'autorise » : archive Go 1.26.11 vérifiée (13 cas, 0 écart), R2 et R3 conformes (8 bundles vérifiés, 0 KO) ; R4 pas avant le 2026-11-25T13:27:42Z. Restent, sur accord : R4 et R5 de la 10 (VM `sc-replay`, push de la VSA), rejeu de zéro (recrée la clé `vex`), déclaration de Go 1.26.11 dans `mise.toml`. Heures : au plus 1 h 48 min 00 s.

## Seuil

L'image sample-app reconstruite en Go 1.26.11 par la pipeline de la plateforme, signée (Chains), admise par la porte, scannée par le CronJob : **0 entrée stdlib**, les 5 entrées chi écartées par un nouveau VEX signé (accord nommé). Le rejeu de zéro attend la nouvelle image.

## Étapes et accords

| Étape | Où | Accord à demander |
|---|---|---|
| 1. Toolchain : téléchargement, `ziphash` = `h1` de sum.golang.org | hôte | donné (« Chantier à part ») |
| 2. Banc de la 04 sur l'hôte avec Go 1.26.11 : deux constructions, même digest ; prédiction du digest et du scan (Syft, Grype hors ligne, base du jour) | hôte | aucun (lecture, `~/.cache`) |
| 3. Image de build (voie D) avec Go 1.26.11, poussée dans Zot | vrai Zot | écriture nommée |
| 4. Tâches re-signées, pipeline, liste revue, porte, cible des CronJobs, scripts du rejeu | cluster et dépôt | changement de politique et de configuration |
| 5. PipelineRun, provenance, admission, scan | cluster | lancement (accord implicite) |
| 6. VEX chi de la nouvelle image (mesure du binaire, brouillon, validation, signature) | vrai Zot | accord nommé de signature |
| 7. Brique 10 (rejeu indépendant) et documents | hôte, cluster | selon l'étape |

## Conséquences connues

- Nouveau digest : le VEX signé de la 07b ne vaut que pour `3a7ca1b1` ; les 5 entrées chi reviennent jusqu'à l'étape 6.
- Au moins 12 scripts du rejeu épinglent `3a7ca1b1` ou l'image de build `d50ae575` (relevé de la 07b, appels indirects non mesurés). Les bancs historiques restent tels quels (journaux jamais réécrits).
- Jamais de rejeu de zéro pendant le chantier : il recrée la clé `vex`.

## Journal

Notes datées : [`resultats/07c-carte.md`](resultats/07c-carte.md).
