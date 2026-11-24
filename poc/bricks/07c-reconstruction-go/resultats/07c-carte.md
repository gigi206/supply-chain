# Brique 07c : carte

## Ouverture (note de 2026-11-24T13:11:58Z)

Décision du propriétaire, verbatim : « Chantier à part ». Périmètre et accords : [README](../README.md). Départ du compte d'heures : 2026-11-24T13:11:58Z.

## Étape 1 : toolchain (prédiction, note de 2026-11-24T13:12:15Z)

[`telecharger.sh`](../telecharger.sh), journal `telecharger.log` : module absent avant ; 71 800 213 octets ; `ziphash` = `h1:KyINmJ/…` relevé avant l'accord et relu maintenant ; `go version go1.26.11 linux/amd64` ; 1.26.10 intacte. **Bilan attendu : 6 cas, 0 écart.**

**Étape 1, résultat** ([journal](telecharger.log), 13:12:18 à 13:12:27 UTC) : **6 cas, 0 écart**, conforme. Module de 71 800 213 octets, `ziphash` = `h1:KyINmJ/…` (relevé avant l'accord et relu), `go version go1.26.11 linux/amd64`, 1.26.10 intacte (`h1:5VAGHlY8…`).

## Étape 2 : banc de la 04 sur l'hôte (prédiction, note de 2026-11-24T13:13:37Z)

[`banc-hote.sh`](../banc-hote.sh), journal `banc-hote.log`, BuildKit du nixpkgs rootless, `bench.sh` de la 04 inchangé, entrées de la 03 :
- entrées de la 03 : binaire de référence `e3749c68…` ;
- **témoin Go 1.26.10** : image `3a7ca1b1…`, `bench.sh` sans KO ;
- **Go 1.26.11** : image identique sur deux constructions, digest différent de `3a7ca1b1` (valeur non prédite : elle devient la prédiction des étapes suivantes, ligne `DIGEST PRÉDIT|`) ; seul KO de `bench.sh` : son étape 3 (binaire comparé à celui de la 03, compilé en 1.26.10), attendu par construction ; binaire hors BuildKit en 1.26.11, sans réseau = binaire de l'image ;
- **scan** (Grype hors ligne, base du 24/11, sur l'image et non sur le SBOM fusionné de la plateforme) : témoin à 6 entrées dont `GO-2026-6859` ; 1.26.11 à 5 entrées, toutes sur chi, 0 stdlib ;
- **bilan attendu : 11 cas, 0 écart.**

**Étape 2, résultat** ([journal](banc-hote.log), 13:13:42 à 13:17:31 UTC ; note de 2026-11-24T13:17:56Z) : **11 cas, 1 écart**, écart de **prédiction** sur le témoin.
- Témoin Go 1.26.10 : l'hôte reproduit toujours `3a7ca1b1…` (deux constructions, binaire `e3749c68…` = celui de la 03, négatifs tenus).
- **Go 1.26.11 : image `sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7`**, identique sur deux constructions sans cache depuis deux chemins ; binaire `56f3cd7d…` (6 197 374 octets, go1.26.11, chi v5.2.3), identique à la compilation hors BuildKit sans réseau ; négatifs tenus ; seul KO de `bench.sh` : son étape 3, attendu. Image de build BuildKit `06359cd6…` (sur l'hôte seulement ; le cluster utilise l'image de la voie D, assemblée sans BuildKit).
- **Scan, écart** : Grype lancé directement sur l'image témoin donne **15** entrées, pas 6 : les 6 du scan de la plateforme plus 9 correspondances NVD par CPE (`cpe:2.3:a:golang:go:1.26.10`, `CVE-2026-97033` à `97039`, `97043`, `97054`, toutes corrigées en 1.26.11 et 1.27.4). Ma prédiction reprenait le compte du scan de la plateforme (SBOM fusionné, `scan-outil`), qui ne les fait pas ressortir ; la cause de cette différence n'est pas mesurée ici. **Image 1.26.11 : 5 entrées, toutes sur chi, 0 stdlib**, conforme : la reconstruction retire les 10 entrées stdlib du scan direct.
- **Prédiction pour les étapes suivantes** : l'image construite par la pipeline de la plateforme en Go 1.26.11 sur les mêmes entrées devrait être `f5e6bcb0…` (la voie A de la 08 et la 04 donnaient le même digest, `3a7ca1b1`).

**Heures** : 13:11:04 à 13:17:56 UTC (0 h 06 min 52 s) ; **total de la 07c : 0 h 06 min 52 s** pour 10 h estimées.

## Étape 3 à sec : image de build de la voie D (prédiction, note de 2026-11-24T13:18:30Z)

[`predire-builder.sh`](../predire-builder.sh), journal `predire-builder.log`, registre Zot jetable sur 127.0.0.1:5077, assemblage recopié de `voie-d.sh` : **témoin 1.26.10 = `d50ae575…`** (sinon la recopie est fausse) ; 1.26.11 identique sur deux assemblages, digest non prédit (ligne `BUILDER PRÉDIT|`) ; `go version go1.26.11`. **Bilan attendu : 3 cas, 0 écart.**

**Étape 3 à sec, résultat** ([journal](predire-builder.log), 13:18:32 à 13:18:52 UTC ; note de 2026-11-24T13:19:09Z) : **3 cas, 0 écart**, conforme. Témoin 1.26.10 : `d50ae575…`, la recopie de `voie-d.sh` est fidèle. **Image de build Go 1.26.11 : `sha256:8c11e856b10fcc3dce8d22815b803d95e2f643cda265cfd3ebdaed8615b2edf7`** (couche de 226 785 280 octets, identique sur deux assemblages). Registre jetable effacé ; rien écrit dans le vrai Zot.

**Suite, sur accord nommé** : pousser cette image dans le vrai Zot (`plateforme/builder-go-voie-d`, compte d'écriture de `voie-d.sh`), digest attendu `8c11e856…`. Puis l'étape 4 (tâches re-signées, pipeline, liste revue, porte, cible des CronJobs), changement de politique et de configuration, sur un second accord.

**Heures** : 13:11:04 à 13:19:09 UTC ; **total de la 07c : 0 h 08 min 05 s** pour 10 h estimées.

## Étape 3 : image de build dans le vrai Zot (note de 2026-11-24T13:20:28Z)

**Accord** : à la question « Autorisez-vous l'écriture de l'image de build 8c11e856 dans le vrai Zot ? », réponse verbatim du propriétaire : « J'autorise ». Portée : ce seul manifeste, dépôt `plateforme/builder-go-voie-d`, compte `poc-ecriture` (droits `create` et `update` sur `**`, relus dans `08-trust-plane/stockage/zot.json`).

**Prédiction** ([`pousser-builder.sh`](../pousser-builder.sh), journal `pousser-builder.log`) : assemblage refait comme `predire-builder.sh` (témoin `d50ae575`, deux assemblages, digest `8c11e856…`) ; tag `go1.26.11` absent avant ; layout OCI tiré du registre jetable puis `crane push` avec vérification TLS (pas de `--insecure` vers le vrai Zot) sous le **tag neuf `go1.26.11`** ; relu en anonyme : tag et digest = `8c11e856…`, couche identique ; tags `a` et `b` toujours `d50ae575`. **Bilan attendu : 9 cas, 0 écart.** Si un cas échoue avant la poussée, rien n'est poussé.

**Étape 3, résultat** ([journal](pousser-builder.log), 13:20:30 à 13:20:56 UTC ; note de 2026-11-24T13:21:05Z) : **9 cas, 0 écart**, conforme. `192.168.161.13:5000/plateforme/builder-go-voie-d@sha256:8c11e856b10fcc3dce8d22815b803d95e2f643cda265cfd3ebdaed8615b2edf7`, tag `go1.26.11`, relu en anonyme (Env de la voie D) ; tags `a` et `b` toujours `d50ae575`. Authentification effacée, dossier de travail effacé.

**Heures** : 13:11:04 à 13:21:05 UTC ; **total de la 07c : 0 h 10 min 01 s** pour 10 h estimées.

## Étape 4 : relevé à sec du périmètre (note de 2026-11-24T13:21:54Z)

Épinglages du chemin vivant (lecture seule, hors bancs et essais historiques) :
- **image de build `d50ae575`** : `construction.sh` (l. 60), `bascule.sh` de la 03 (l. 50), `buildkit.sh` (l. 380), et la tâche signée `politique/taches/construire-image.signee.yaml` (l. 28 et 59) ;
- **image `3a7ca1b1` attendue** : `construction.sh` (l. 48), `voie-d.sh`, `buildkit.sh`, `durcissement.sh` de la 08c (l. 886), `declencheur.sh` de la 01 (l. 31), `replay.sh` de la 10 (l. 74), `plateforme.sh` de la 07a (l. 96, cible du CronJob de scan), `s6a.sh` de la 06 (l. 55) ;
- **images d'essai signées en J4** (`APP_DIGEST` de `stockage.sh`, `tekton.sh`, `tsa.sh`, `politique.sh`, `kyverno-*.sh`, `redemarrer.sh`) : copies de `3a7ca1b1` sous `builds/essai-*`, sans lien avec Go ; à laisser.

Ce que l'étape 4 changerait :
- la tâche `construire-image` rendue avec `8c11e856`, **re-signée** (`SIGNER=1`, clé des tâches lue par `tkn` sans être affichée) et publiée en bundle, avec la pipeline `sample-app` et celle de la bascule de la 03 (à mesurer : laquelle est en service) ;
- la **liste revue** `politique/porte/taches.yml` augmentée des nouvelles références, anciennes gardées, puis posée dans le cluster ;
- un PipelineRun qui doit produire `f5e6bcb0…`, signé par Chains, admis par la porte ;
- la cible du CronJob `scan/scan-sample-app` portée à `f5e6bcb0…` ;
- les scripts du rejeu ci-dessus.

Journaux : `lancer` de `commun.sh` réécrit `resultats/<préfixe>-<étape>.log`. Il faut un préfixe propre à la 07c pour ne réécrire aucun journal.

**Heures** : 13:11:04 à 13:21:54 UTC ; **total de la 07c : 0 h 10 min 50 s** pour 10 h estimées.
