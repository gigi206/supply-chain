# Brique 07c : reconstruction de sample-app en Go 1.26.11

Origine : la 07b relève `GO-2026-6859` (stdlib 1.26.10, Medium) sur l'image `3a7ca1b1`, non couvrable par un VEX (code lié, atteignable par `OPTIONS *`). Choix du propriétaire du 24/11/2026 (verbatim) : « reconstruire l'image en Go 1.26.11. » → « oui » ; puis, sur l'enveloppe (« Où compter la reconstruction en Go 1.26.11 (environ 10 h, non mesurées) ? ») : « Chantier à part ». Cette réponse vaut aussi accord pour télécharger le module `golang.org/toolchain@v0.0.1-go1.26.11.linux-amd64` (proxy.golang.org, 71 800 213 octets, `h1:KyINmJ/FQdKRmDYGuTAAXkumyeR2DyUlSNHZj7XaLFg=` sur sum.golang.org), rangé à côté de 1.26.10 dans `~/.cache`, **sans toucher à `mise.toml`**.

**Estimation : 10 h (non mesurée) ; seuil de décision : 20 h.** Heures comptées ici, pas dans la 07b, à partir de la note de 2026-11-24T13:11:58Z.

## État (2026-11-24T14:13:34Z)

**Étapes 1 à 4 faites**, journaux dans [`resultats/`](resultats/07c-carte.md) : toolchain vérifiée ; image prédite sur l'hôte (`f5e6bcb0`) ; image de build `plateforme/builder-go-voie-d@8c11e856` (tag `go1.26.11`) ; `construire-image` re-signée (`4dcbc4b7`, ajoutée à la liste revue, `66a9f298` gardée) ; construction dans le cluster conforme ; scan : **5 vulnérabilités chi, 0 stdlib, 0 KEV** ; déclencheurs basculés, porte admise. **Étape 6 faite** : VEX chi de `f5e6bcb0` validé (« Oui, je valide »), signé sur accord nommé (« J'autorise ») et publié (`builds/vex/sample-app@b139ef42`, 5 énoncés, échéance 2026-12-24) ; scan manuel : **5 vulnérabilités, 0 KEV, 5 écartées par un VEX**, visible dans Grafana. Reste l'étape 7 (défauts du rejeu, brique 10). Heures : au plus 0 h 50 min 13 s.

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
