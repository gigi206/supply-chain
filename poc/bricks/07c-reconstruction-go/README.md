# Brique 07c : reconstruction de sample-app en Go 1.26.11

Origine : la 07b relève `GO-2026-6859` (stdlib 1.26.10, Medium) sur l'image `3a7ca1b1`, non couvrable par un VEX (code lié, atteignable par `OPTIONS *`). Choix du propriétaire du 24/11/2026 (verbatim) : « reconstruire l'image en Go 1.26.11. » → « oui » ; puis, sur l'enveloppe (« Où compter la reconstruction en Go 1.26.11 (environ 10 h, non mesurées) ? ») : « Chantier à part ». Cette réponse vaut aussi accord pour télécharger le module `golang.org/toolchain@v0.0.1-go1.26.11.linux-amd64` (proxy.golang.org, 71 800 213 octets, `h1:KyINmJ/FQdKRmDYGuTAAXkumyeR2DyUlSNHZj7XaLFg=` sur sum.golang.org), rangé à côté de 1.26.10 dans `~/.cache`, **sans toucher à `mise.toml`**.

**Estimation : 10 h (non mesurée) ; seuil de décision : 20 h.** Heures comptées ici, pas dans la 07b, à partir de la note de 2026-11-24T13:11:58Z.

## État (2026-11-24T15:22:58Z)

**CLOSE le 2026-11-26 (2026-11-26T13:22:18Z), seuil atteint avec réserves** (choix du propriétaire « Clore avec réserves », verbatim, sur la question « Que faire de la 07c ? »). Détail à la section « Clôture », à la fin de ce README. Ce qui suit est l'historique.

**Étapes 1 à 4 faites**, journaux dans [`resultats/`](resultats/07c-carte.md) : toolchain vérifiée ; image prédite sur l'hôte (`f5e6bcb0`) ; image de build `plateforme/builder-go-voie-d@8c11e856` (tag `go1.26.11`) ; `construire-image` re-signée (`4dcbc4b7`, ajoutée à la liste revue, `66a9f298` gardée) ; construction dans le cluster conforme ; scan : **5 vulnérabilités chi, 0 stdlib, 0 KEV** ; déclencheurs basculés, porte admise. **Étape 6 faite** : VEX chi de `f5e6bcb0` validé (« Oui, je valide »), signé sur accord nommé (« J'autorise ») et publié (`builds/vex/sample-app@b139ef42`, 5 énoncés, échéance 2026-12-24) ; scan manuel : **5 vulnérabilités, 0 KEV, 5 écartées par un VEX**, visible dans Grafana. **Étape 7, scripts du rejeu : faits à sec** (décision « Un seul digest ») : voie D en Go 1.26.11 (mesurée à sec, 14 cas), voie A, construction, images d'essai de J2 à J8, Kyverno, scans de la 07a et de la 06 portés à `f5e6bcb0` ; `publier-essai` re-signée sur accord (« J'autorise », bundle `17b50c7c`, ajouté en premier à la liste revue). Rien de ceci n'a tourné dans un cluster ; **ces scripts ne valent plus, lancés seuls, qu'après un rejeu de zéro** (images d'essai `f5e6bcb0` absentes du Zot en service ; `redemarrer.sh` reste sur `3a7ca1b1`). Constat hors périmètre : le deb de la 06 est encore compilé en Go 1.26.10 (`s4d.sh`) ; **correction du 2026-11-24T17:40:25Z** : faux, le deb est compilé par le Go de Debian (`golang-1.24-go` 1.24.4-1, `verrou-deb.txt`), le 1.26.10 de `s4d.sh` ne sert qu'à l'assemblage sur l'hôte ; GO-2026-6859 (Medium, hors KEV) mesuré dans le dernier scan du deb sur `stdlib@1.24.4` ([relevé](resultats/deb-go-6859.log), 3 cas, 0 écart), correction à décider. **VSA de `f5e6bcb0` préparée à sec** ([prédictions](../10-independent-replay/resultats/f5e6bcb0/predictions.md)) : cible `9539952b` (J7 du passage 2, fini à 13:27:42 UTC), `replay.sh` de la 10 paramétré par l'environnement (défauts inchangés), R1 `version_go` conforme (`go1.26.11`) ; sur accord « J'autorise » : archive Go 1.26.11 vérifiée (13 cas, 0 écart), R2 et R3 conformes (8 bundles vérifiés, 0 KO) ; R4 pas avant le 2026-11-25T13:27:42Z. Relecture à sec avant R4 et R5 faite (15:22:58 UTC) : caches froids tenus, aucune image d'essai dans la porte réelle ; le re-push de la VSA par `rejeu.sh` est à adapter dans le commit qui l'archive. **R4 `PASSED` le 25/11** (13:28:12 à 13:48:14 UTC, accord « Les 2 », 0 écart, note de 2026-11-25T13:48:52Z). **R5 conforme le 25/11** (accord « Tout », note de 2026-11-25T18:15:17Z) : VSA de `f5e6bcb0` signée et poussée (`f6442817`), porte inchangée, contrôle 6 de `refus` à `ok`, 0 écart ; défauts de `replay.sh` et `rejeu.sh` portés à `f5e6bcb0` (`122168d9`). Reste, sur accord : rejeu de zéro (recrée la clé `vex`, seconde VSA). **Go 1.26.11 déclaré dans `mise.toml`** (2026-11-24T16:55:24Z, choix du propriétaire « 2 ») : tâche `outils:go-1.26.11`, `GOROOT_DIR` reste en 1.26.10 ; [journal](resultats/mise-go-1.26.11.log) conforme, aucun téléchargement. **Oubli de l'étape 4 réparé** (2026-11-24T16:15:17Z) : `fraicheur-scan` et `entrees-scan` de sc-stockage visaient encore `3a7ca1b1` ; basculés sur accord (« J'autorise la bascule »), 44 séries conformes. Heures : au plus 2 h 13 min 01 s.

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

## Clôture (note de 2026-11-26T13:22:18Z)

**Brique 07c CLOSE, seuil atteint avec réserves.** Accord : choix du propriétaire « Clore avec réserves », verbatim, sur la question « Que faire de la 07c ? ». La clôture est réversible et n'est pas poussée à cette heure.

**Seuil** (relu dans la [carte](resultats/07c-carte.md), sans nouvelle mesure) : image `f5e6bcb0` construite par la pipeline de la plateforme (Kata, Chains), signée, admise par la porte ; scan : 5 vulnérabilités chi, **0 stdlib**, 0 KEV ; les 5 entrées chi écartées par le VEX signé `builds/vex/sample-app@b139ef42` (accord nommé). Au-delà du seuil : R4 de la 10 `PASSED` (25/11) et R5 conforme (VSA `f6442817`, contrôle 6 `refus` → `ok`).

**Réserves** :
- scan planifié : le seuil dit « scannée par le CronJob ». Les passages archivés en propre sont lancés à la main depuis le CronJob `scan/scan-sample-app` (`scan-cible.log`, `vex-apres-scan.log`). Les passages planifiés sont vus **indirectement** : les seuils de la 20 lisent `kpi_scan_timestamp_seconds` de `f5e6bcb0` à 2026-11-25T09:32:07Z ([seuil n° 3](../20-kpi/resultats/e5-seuil-3.log), n° 4, n° 5) et à 2026-11-26T09:32:09Z ([seuil n° 6](../20-kpi/resultats/e5-seuil-6.log), n° 7, n° 8), sans lancement manuel noté à ces heures. Que ces scans viennent du CronJob de 09:30 est déduit (heure compatible avec le Job du 24/11, 09:30:00 à 09:32:07) : aucun journal de Job, `kubectl` ou Loki, n'est archivé pour les 25 et 26/11 ;
- rejeu de zéro jamais rejoué (scripts faits à sec seulement) ; il recrée la clé `vex`, et la seconde VSA, sur la provenance du rejeu, reste à faire ; le re-push de la VSA par `rejeu.sh` n'est pas rejoué ;
- écart d'écriture non tranché : l'historique de la ligne de docs/03 dit encore « reste le rejeu de zéro », le seuil de ce README le place après la 07c ;
- deb de la 06 : `GO-2026-6859` reste mesurée sur `stdlib@1.24.4` (Go de Debian) ; correction à décider par le propriétaire ;
- VEX chi de `f5e6bcb0` : échéance le 2026-12-24 ;
- scripts du rejeu : les appels indirects qui épinglent encore `3a7ca1b1` ne sont pas mesurés ; `redemarrer.sh` reste sur `3a7ca1b1`.

**Effort** : au plus **2 h 13 min 01 s** (total de la carte, bornes « au plus »), plus la clôture, de 13:21:42Z à 13:22:18Z (lecture, écriture). La lecture faite avant la question, à partir de 12:51:44Z, n'a pas d'heure de fin : elle n'est pas comptée. Plus la retouche de la réserve « scan planifié » (lecture des seuils de la 20, relecture du conseiller), de 13:22:31Z (commit de clôture) à 13:24:09Z. Estimation : 10 h ; seuil de décision : 20 h.
