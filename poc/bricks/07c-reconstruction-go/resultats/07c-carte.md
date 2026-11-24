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

## Étape 4 (note de 2026-11-24T13:24:16Z)

**Accord** : à la question « Autorisez-vous l'étape 4 (re-signature, liste revue, PipelineRun, cible du scan) ? », réponse verbatim du propriétaire : « J'autorise l'étape 4 ».

**Pipeline en service** (mesuré à 13:22:20Z) : le TriggerTemplate `declencheurs/sample-app` lance `tekton/pipelines/sample-app@b8ff5ebb…`, publiée par `construction.sh taches` et posée par `preuves.sh bascule` (J8). `bascule.sh` de la 03 n'est pas sur ce chemin. `taches.yml` du cluster (ConfigMap `porte/porte`) = dépôt.

**Changements de scripts** (défauts inchangés : le rejeu fait la même chose qu'avant) :
- `commun.sh` : `R=${RESULTATS:-…}` (journaux de la 07c dans son `resultats/`, aucun journal de la 08 réécrit) ;
- `construction.sh` : `APP_REF` et `BUILDER` surchargeables ; `SIGNER="<nom>…"` ne re-signe que ces tâches (`SIGNER=1` : toutes, comme avant) ;
- `preuves.sh` : `APP_REEL` pour l'image réelle (`APP_DIGEST` reste celui des images d'essai de J4).

**Ordre** : (a) `SIGNER=construire-image construction.sh taches` → nouvelle signature versionnée et référence à ajouter ; (b) revue et ajout à `taches.yml` (ancienne référence `66a9f298` gardée : l'image `3a7ca1b1` doit rester jugeable), ConfigMap de la porte mise à jour sur la seule clé `taches.yml` ; (c) `construction.sh taches construire provenance` ; (d) `preuves.sh bascule` ; (e) cible du scan.

**Prédiction de (a)** (journal `signer/construction-taches.log`) : `construire-image` rendue avec `8c11e856`, re-signée, signature versionnée remplacée (le diff ne touche que les deux digests de l'image de build et la signature), nouveau bundle « à ajouter » ; `preparer-entrees` et `publier-image` inchangées et listées (`2070d601…`, `d21931f3…`) ; pipeline `sample-app` re-signée et publiée sous un nouveau digest ; témoin `c7e8b275` conforme ; code 0.

**(a), résultat** ([journal](signer/construction-taches.log), 13:24:18 à 13:24:24 UTC ; note de 2026-11-24T13:24:54Z) : **conforme**. `construire-image` re-signée : le diff de `construire-image.signee.yaml` ne touche que la signature et les deux digests de l'image de build (`d50ae575` → `8c11e856`) ; bundle **`tekton/tasks/construire-image@sha256:4dcbc4b7468137d894bb40085b32b9cc816a37bfece3204ed06466ee4741eb6b`** à ajouter ; `preparer-entrees` (`2070d601`) et `publier-image` (`d21931f3`) inchangées et listées ; pipeline `sample-app@6838969f…` ; témoin `c7e8b275` conforme.

**(b), prédiction** : `taches.yml` augmenté de `4dcbc4b7` sous `construire-image` (`66a9f298` gardé) ; [`porte-taches.sh`](../porte-taches.sh), journal `porte-taches.log` : liste du cluster = ancienne version commitée avant le patch ; après : = dépôt, nouvelle et ancienne références présentes, autres clés de la ConfigMap inchangées ; **5 cas, 0 écart**.

**(b), résultat** ([journal](porte-taches.log), 13:24:55 UTC ; note de 2026-11-24T13:25:13Z) : **5 cas, 0 écart**, conforme. ConfigMap `porte/porte` : `taches.yml` = dépôt (`8e4e1b31…`), `4dcbc4b7` et `66a9f298` présentes, autres clés inchangées.

**(c), prédiction** (`construction.sh taches construire provenance`, `BUILDER=…@8c11e856`, `APP_REF=f5e6bcb0…`, journaux `construction-<étape>.log` de la 07c ; `construction.sh` s'arrête au premier KO) :
- taches : les trois tâches dans la liste revue (`construire-image@4dcbc4b7`), pipeline re-signée sous un nouveau digest ;
- construire : PipelineRun `j7-sample-app` (l'ancien, de `3a7ca1b1`, purgé par le script) réussi sous Kata (`-smp 3 -m 6176M`), **`IMAGE_DIGEST` = `sha256:f5e6bcb0…`**, arbre `30e808ff`, Chains signe les TaskRuns et le PipelineRun, écriture par `poc-images` ; témoins : label imposé, ancienne pipeline en échec fermé, PipelineRun sans Kata refusé ; alerte `ChainsEchecSignature` attendue, comme au rejeu ;
- provenance : enveloppe valide sur `builds/sample-app@f5e6bcb0…`, sujet, `slsa-tekton`, **image de build `8c11e856…`** dans `resolvedDependencies`, autre clé refusée.

**(c), passage 1** (13:25:20 à 13:25:45 UTC ; journaux [`construction-taches.log`](construction-taches.log) et [`construction-construire-1.log`](construction-construire-1.log), renommé sans modification ; note de 2026-11-24T13:26:37Z) : **arrêté, défaut de lancement** : `DISTRO` non fourni, `distro.sh` a pris le défaut `k3s` et l'étape construire a lancé `sudo k3s crictl` sur sc-build (« k3s: command not found »). taches : conforme (trois tâches listées, `construire-image@4dcbc4b7`). Le PipelineRun `j7-sample-app`, déjà créé, a continué sans le script : **réussi à 13:26:27Z, `IMAGE_DIGEST=sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7`**, conforme à la prédiction de l'étape 2.

**Passage 2, prédiction** : `DISTRO=rke2 RESEAU=cilium construction.sh construire provenance` (même `T`, mêmes références de `taches` ; `j7-sample-app` purgé et recréé par le script) : prédiction de (c) inchangée pour construire et provenance.

**Ordre revu (note de 2026-11-24T13:26:51Z)** : le scan (e) passe **avant** la bascule (d). La porte juge aussi le scan signé de l'image (contrôle 7 de la 07a) : l'image reconstruite doit avoir un scan avant que la bascule ne la fasse juger.

**(e), prédiction** ([`scan-cible.sh`](../scan-cible.sh), journal `scan-cible.log`) : cible du CronJob `scan/scan-sample-app` à `3a7ca1b1` ×3 avant (analyser, attester, publier), seule la valeur `IMAGE` change, `f5e6bcb0` ×3 après ; un passage lancé à la main depuis le CronJob réussit ; `SCAN|…sample-app@sha256:f5e6bcb0…, 5 vulnérabilités, 0 KEV` (les 5 chi, 0 stdlib, aucun VEX pour cette image) ; `PUBLIE|` présent ; **5 cas, 0 écart**.

**(c), passage 2** (13:26:44 à 13:28:43 UTC ; [construire](construction-construire.log), [provenance, arrêtée](construction-provenance-1.log) ; note de 2026-11-24T13:29:09Z) :
- **construire : conforme, tous les cas OK**. `j7-sample-app` réussi sous Kata (`-smp 3 -m 6176M`, label `construire-image`) ; **image `sha256:f5e6bcb0…`** ; arbre `30e808ff` ; PipelineRun signé par Chains ; une écriture de `poc-images`. Témoins tenus : label imposé, ancienne pipeline en échec fermé (DNS), PipelineRun sans Kata refusé par Pod Security, aucune écriture de `poc-images` pendant ces témoins. CONSTAT : l'étape construire démarre 3 s après le premier conteneur, comme au rejeu.
- **provenance : arrêtée, défaut de ma surcharge** : `RESULTATS` remplaçait `R`, que `construction.sh` lit aussi pour la clé publique de Chains (`$R/chains-cle-publique.pem`, l. 452) ; cosign n'a pas trouvé la clé. Correction : `commun.sh` garde `R` pour les entrées et n'envoie que les journaux de `lancer` et `chrono.tsv` vers `RJ=${RESULTATS:-$R}`. Aucune entrée de la 08 n'a été lue ailleurs (les autres usages de `$R/` de `construction.sh` : cette seule ligne).

**Passage 3, prédiction** : `construction.sh provenance` seul (même `T`) : prédiction de (c) pour la provenance, inchangée.

**(c), passage 3** ([journal](construction-provenance.log), 13:29:11 UTC ; note de 2026-11-24T13:29:18Z) : **provenance conforme, tous les cas OK**. 4 enveloppes valides sur `builds/sample-app@f5e6bcb0…` (TaskRun publier et PipelineRun, aux passages 1 et 2), 1 du `j7-sample-app` en cours ; sujet, `slsa-tekton`, source `6391fd43`, fermeture `74c265e7`, web/dist `47f72275`, **image de build `8c11e856…`**, `preparer-entrees` `2070d601`, `kata` dans les paramètres et le contenu signé ; autre clé refusée.

**(e), résultat** ([journal](scan-cible.log), 13:29:20 à 13:31:42 UTC ; note de 2026-11-24T13:32:00Z) : **5 cas, 0 écart**, conforme. CronJob `scan/scan-sample-app` : seule la valeur `IMAGE` a changé (0 autre différence), `f5e6bcb0` ×3. Passage manuel `scan-sample-app-07c-132920` réussi : `VEX|0 énoncé` (aucun VEX pour cette image) ; **`SCAN|…f5e6bcb0…, 5 vulnérabilités, 0 KEV, 0 écartée(s) par un VEX`** ; publié `builds/scan/sample-app@a92cf233…`. **`GO-2026-6859` n'est plus comptée** ; les 5 entrées chi reviennent, faute de VEX pour cette image (attendu).

**(d), prédiction** (`DISTRO=rke2 RESEAU=cilium APP_REEL=sha256:f5e6bcb0… preuves.sh bascule`, journal `preuves-bascule.log` de la 07c) : `preuves.sh` compare aussi les résultats du PipelineRun à `APP_DIGEST` (l. de `ba_chemin`) : remplacé par `${APP_REEL:-$APP_DIGEST}`, défaut inchangé. Prédiction de l'étape, celle de son en-tête, avec l'image `f5e6bcb0` : gabarit posé sur la nouvelle pipeline ; chemin 1 (livraison de Forgejo) et chemin 2 (rattrapage) : PipelineRun réussi, `IMAGE_DIGEST=f5e6bcb0…`, porte admise sans violation, horodatage ok ; rejeu refusé (already exists) ; 4 enveloppes de plus sur l'image ; posture sans signalement.

**(d), résultat** ([journal](preuves-bascule.log), 13:32:07 à 13:36:34 UTC ; note de 2026-11-24T13:36:55Z) : **conforme, tous les cas OK**, code 0. Gabarit en service : `tekton/pipelines/sample-app@da76d95b…` (publiée par `taches` au passage 1 de (c), celle du `j7-sample-app` du passage 2 ; les trois tâches dans la liste revue). Chemin 1 (livraison de Forgejo, HTTP 204) et chemin 2 (rattrapage) : PipelineRun `sample-app-6391fd43…` réussi sous Kata sur sc-build, **`IMAGE_DIGEST=f5e6bcb0…`**, spec identique à `j7-sample-app` et entre les deux chemins, signé par Chains, **porte : `true||ok`** (admise, aucune violation, horodatage ok ; elle a jugé le scan signé de (e)). Rejeu de la livraison refusé (already exists). Enveloppes sur l'image : 4 → 8. Posture : 5 ressources, aucun signalement. Rattrapage repris.

**Étape 4 : faite.** La plateforme construit, signe, admet et scanne sample-app en Go 1.26.11 : `builds/sample-app@sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7`, 5 vulnérabilités (chi), 0 stdlib, 0 KEV.

**Reste** :
- étape 6 : VEX chi de `f5e6bcb0` (mesure du binaire comme `piece8-binaire.sh`, brouillon, validation, **accord nommé de signature**) ;
- étape 7 : défauts des scripts du rejeu (`construction.sh`, `voie-d.sh`, `plateforme.sh`, `declencheur.sh`, `replay.sh`, `s6a.sh`, `durcissement.sh`, `bascule.sh` de la 03) ; tant qu'ils ne sont pas portés, un rejeu de zéro reconstruirait `3a7ca1b1` et re-signerait l'ancienne tâche ; brique 10 (rejeu indépendant) ;
- l'image `3a7ca1b1` reste jugeable (`66a9f298` gardée dans la liste revue) ; son VEX du 24/11 reste publié.

**Heures** : 13:11:04 à 13:36:55 UTC ; **total de la 07c : 0 h 25 min 51 s** pour 10 h estimées.

## Étape 6 : VEX chi de `f5e6bcb0` (prédiction, note de 2026-11-24T13:50:05Z)

Reprise du chantier : 2026-11-24T13:49:12Z. Déroulé de la pièce 8 de la 07b : mesure du binaire, brouillon, vérification, **validation du contenu par le propriétaire**, puis **accord nommé de signature** (ce document seul).

**(a) mesure, prédiction** ([`vex-binaire.sh`](../vex-binaire.sh), copie de `piece8-binaire.sh` passage 4 avec trois ajouts ; journal `vex-binaire.log`) :
- entrées du scan signé en vigueur (`a92cf233`) : les 5 noms du VEX de `3a7ca1b1` (`GHSA-3fxj-6jh8-hvhx`, `GHSA-j6qf-3m9c-vwj3`, `GHSA-mqqf-5wvp-8fh8`, `GO-2026-5775`, `GO-2026-5777`), aucune hors chi ; gabarit : noms, alias et sous-composants identiques à ceux de ce VEX, produit `pkg:oci/sample-app@sha256:f5e6bcb0…` ;
- binaire : sha256 `56f3cd7d…` (banc de l'hôte), `go1.26.11`, chi `v5.2.3` ;
- témoins présents (`(*Mux).ServeHTTP`, `(*Mux).routeHTTP`, `net/http.(*Server).Serve`) ; paquets de chi liés : le seul paquet racine `github.com/go-chi/chi/v5` ; les 7 mêmes fichiers sources (`chain.go` à `tree.go`) ; **0** pour tout ce qui touche `middleware` (fonctions, chemins, nom qualifié), `RealIP`, `ClientIPFromXFF`, `GetClientIP`, `RedirectSlashes`, `realip`, `/strip.go` ;
- fiches OSV : 5 lues, imports seulement dans `github.com/go-chi/chi/v5/middleware` ;
- **bilan attendu : 25 cas, 0 écart.**

**(a), passage 1** ([journal](vex-binaire-1.log), renommé sans modification, 13:50:18 à 13:50:20 UTC ; note de 2026-11-24T13:50:35Z) : **25 cas, 1 écart, défaut de mon critère**. Le cas « paquets de chi liés = le seul paquet racine » relève aussi `github.com/go-chi/chi/v5@v5` : ce sont les 7 chemins de fichiers sources (`…/chi/v5@v5.2.3/<fichier>.go`), que `piece8-binaire-4.log` montrait déjà à l'identique pour `3a7ca1b1` (« 7 github.com/go-chi/chi/v5@v5 »), pas un paquet. Les 24 autres cas sont conformes à la prédiction : mêmes 5 entrées, gabarit identique (`0c222a08`), binaire `56f3cd7d…` en `go1.26.11`, témoins présents, 7 mêmes fichiers sources, 0 pour tout ce qui touche `middleware` et les quatre noms, 5 fiches OSV lues (imports seulement dans `chi/v5/middleware`, symbole `RealIP` pour les deux GO ; les 3 GHSA sans imports).

**Passage 2, prédiction** : critère corrigé (lignes contenant `@` exclues) et un cas ajouté : les lignes `github.com/go-chi/…@` de la table des noms sont toutes des chemins `chi/v5@v5.2.3/<fichier>.go` (7 = 7). **Bilan attendu : 26 cas, 0 écart.**

**(a), passage 2** ([journal](vex-binaire.log), 13:50:47 à 13:50:49 UTC ; note de 2026-11-24T13:51:11Z) : **26 cas, 0 écart**, conforme. Seul le paquet racine `github.com/go-chi/chi/v5` est lié ; les 7 lignes `…@` sont les chemins des fichiers `.go`.

**(b) brouillon de la session, non validé** : [`vex/sample-app-f5e6bcb0.json`](../../07a-sbom-grype/vex/sample-app-f5e6bcb0.json), sha256 `f99026eb22eba7d0`. Texte du VEX de `3a7ca1b1` (validé et signé le 24/11), seuls changent : l'`@id` du document (`…/sample-app/f5e6bcb0`), le produit de chaque énoncé (`pkg:oci/sample-app@sha256:f5e6bcb0…`), et dans chaque `impact_statement` le digest de l'image, l'empreinte du fichier (`56f3cd7d256562be…`) et le journal cité (`07c-reconstruction-go/resultats/vex-binaire.log`). `author` et horodatages vides ; 0 occurrence restante de `3a7ca1b1`, `e3749c68`, `piece8-binaire-4`.

**(c) verdict de `verifier`, prédiction** ([`vex-brouillon-verif.sh`](../vex-brouillon-verif.sh), copie de `deb-brouillon-verif.sh`, journal `vex-brouillon-verif.log`) : juge `scan-outil` reconstruit depuis HEAD (`7dde1a8ed457f254`) ; brouillon tel quel refusé (code 1) ; copie témoin (auteur témoin, heure du moment, jamais signée) acceptée, exemption de 5 énoncés, 5 échéances ; `outil/` inchangé. **Bilan attendu : 6 cas, 0 écart.**

**(c), résultat** ([journal](vex-brouillon-verif.log), 13:51:21 à 13:51:25 UTC ; note de 2026-11-24T13:51:32Z) : **6 cas, 0 écart**, conforme. Brouillon tel quel refusé ; copie témoin acceptée : exemption de 5 énoncés (0 large), sujet `f5e6bcb0`, 5 échéances à 30 jours ; aucun VEX encore publié pour ce digest.

**En attente du propriétaire** : validation du contenu du brouillon (et auteur à inscrire), puis accord nommé de signature pour ce document seul. Rien n'est signé.

**Heures** : reprise 13:49:12 à 13:51:25 UTC (2 min 13 s) ; **total de la 07c : 0 h 28 min 4 s** pour 10 h estimées.

## Étape 6 : validation et préalables de la signature (note de 2026-11-24T13:59:35Z)

**Validation du propriétaire**, verbatim : « Oui, je valide » (contenu du brouillon `f99026eb22eba7d0` et auteur proposé). Seul champ écrit : `author` = « Ghislain LE MEUR » ; document sha256 `4297ba587b615261`.

**(d) préalables, prédiction** (`mise exec -- bash 07a-sbom-grype/piece8-signer.sh prealables vex/sample-app-f5e6bcb0.json 4297ba587b615261`, lecture seule, journal `07a-sbom-grype/resultats/piece8-signer-prealables-sample-app-f5e6bcb0.log`) : image déduite du document `builds/sample-app@f5e6bcb0…` ; document à l'empreinte attendue, horodatages vides ; `bao` vérifié ; mots de passe présents (`test -s`) ; `poc-vex` authentifié (200) ; juge `7dde1a8e…` ; redirection ouverte puis fermée ; copie horodatée acceptée (exemption de 5 énoncés, 5 échéances) ; aucun VEX publié sur `f5e6bcb0` (celui de `3a7ca1b1` est sur un autre digest) ; **10 cas, 0 écart**. Ensuite seulement : accord nommé de signature.

**(d), résultat** ([journal](../../07a-sbom-grype/resultats/piece8-signer-prealables-sample-app-f5e6bcb0.log), 13:59:47 à 13:59:52 UTC ; note de 2026-11-24T13:59:59Z) : **10 cas, 0 écart**, conforme. Copie horodatée acceptée (exemption de 5 énoncés, 0 large, 5 échéances au 2026-12-24) ; aucun VEX publié sur `f5e6bcb0` ; rien signé, rien publié, document inchangé (`4297ba587b615261`).

**(e) signature, prédiction** (`ACCORD='<phrase du propriétaire>' mise exec -- bash 07a-sbom-grype/piece8-signer.sh signer vex/sample-app-f5e6bcb0.json 4297ba587b615261`, journal `piece8-signer-signer-sample-app-f5e6bcb0.log`) : document horodaté (seul champ écrit), `verifier` accepte ; connexion userpass « proprietaire », signature `hashivault://vex`, publication par `poc-vex` dans `builds/vex/sample-app` en referrer de `f5e6bcb0` ; révocation, redirection fermée ; relecture `PUBLIES|5` ; **15 cas, 0 écart**. **En attente de l'accord nommé du propriétaire.**

**Accord nommé du propriétaire**, verbatim : « J'autorise » (signature et publication de ce document seul).

**(e), résultat** ([journal](../../07a-sbom-grype/resultats/piece8-signer-signer-sample-app-f5e6bcb0.log), 14:09:52 à 14:09:59 UTC ; note de 2026-11-24T14:10:24Z) : **15 cas, 0 écart**, conforme. Document horodaté `2026-11-24T14:09:55Z` (seuls les horodatages ont changé ; sha256 `8b8ae8b7…`), accepté ; connexion userpass « proprietaire » (politique `vex-signature`, 900 s) ; signé (`hashivault://vex`) et **publié `builds/vex/sample-app@sha256:b139ef42efb4bba328119e2cc4016779552c3c61ba9fd88753da866bdbe3766e`, referrer de `f5e6bcb0`** ; révocation, redirection fermée ; relecture `PUBLIES|5`. Échéance : 2026-12-24T14:09:55Z. Les 5 `AVIS|renouvellement` de la relecture désignent le document lui-même, déjà publié (attendu).

**(f) effet sur un scan, prédiction** ([`vex-apres-scan.sh`](../vex-apres-scan.sh), copie de `deb-apres-scan.sh`, journal `vex-apres-scan.log`) : Job lancé à la main depuis `scan/scan-sample-app`, réussi ; `VEX|1 énoncé(s) vérifié(s), 1 retenu(s), 0 rejeté(s)` ; **`SCAN|…f5e6bcb0…, 5 vulnérabilités, 0 KEV, 5 écartée(s) par un VEX`** ; `PUBLIE|` ; la ligne visible dans Grafana (Loki, compte auditeur) ; tableau du scan neuf : « écartées par un VEX 5 » ; **6 cas, 0 écart**.

**(f), résultat** ([journal](vex-apres-scan.log), 14:10:26 à 14:13:08 UTC ; note de 2026-11-24T14:13:34Z) : **6 cas, 0 écart**, conforme. Job `scan-sample-app-07c-vex-141026` réussi : `VEX|1 énoncé(s) vérifié(s), 1 retenu(s), 0 rejeté(s)` ; **`SCAN|…f5e6bcb0…, 5 vulnérabilités, 0 KEV, 5 écartée(s) par un VEX`** ; publié `builds/scan/sample-app@4b7f5a0c…` ; la ligne est visible dans Grafana ; tableau : les 5 entrées `not_affected (2026-11-24T14:09:55Z)`.

**Étape 6 : faite.** L'image `f5e6bcb0` a 0 entrée stdlib et ses 5 entrées chi sont écartées par un VEX signé ; le seuil de la 07c est tenu, sauf son dernier point (le rejeu de zéro attend la nouvelle image : étape 7).

**Reste** : étape 7, défauts des scripts du rejeu (`construction.sh`, `voie-d.sh`, `plateforme.sh`, `declencheur.sh`, `replay.sh`, `s6a.sh`, `durcissement.sh`, `bascule.sh` de la 03) et brique 10 ; jamais de rejeu de zéro avant (il recrée la clé `vex` et reconstruirait `3a7ca1b1`).

**Heures** : reprise de 13:49:12 à 2026-11-24T14:13:34Z, attentes des réponses du propriétaire comprises : 24 min 22 s ; **total de la 07c : au plus 0 h 50 min 13 s** pour 10 h estimées.

## Étape 7 : relevé à sec des défauts du rejeu (note de 2026-11-24T14:20:40Z)

Méthode : périmètre tiré de la liste des étapes de `08-trust-plane/rejeu.sh` (étape → script → fonction → valeur épinglée), pas d'une recherche des digests. Lecture seule ; rien lancé, rien écrit hors du dépôt.

**Correction de la phrase de l'étape 4 et de l'étape 6** (« un rejeu de zéro reconstruirait `3a7ca1b1` et re-signerait l'ancienne tâche ») : fausse, mesurée sur le code. `construction.sh taches` rend la tâche avec `BUILDER` (défaut `d50ae575`) et la compare à la signature versionnée, qui porte `8c11e856` depuis l'étape 4. Sans `SIGNER`, la comparaison échoue (« gabarit modifié depuis la signature versionnée ») : **un rejeu de zéro lancé aujourd'hui s'arrêterait en KO à « J7 (construction) »**, après avoir refait la voie D et la voie A en Go 1.26.10. Rien n'est re-signé.

**Sur le chemin du rejeu** (à porter) :
- **J7 (voie D)**, `voie-d.sh` : toolchain `GO_MODULE` 1.26.10, prise dans `GOROOT_DIR` de `mise.toml` (1.26.10) ; `BIN_REF` `e3749c68` ; `APP_REF` `3a7ca1b1`, lue dans `workspace/sample-app`. C'est la seule étape du rejeu qui produit `plateforme/builder-go-voie-d` : elle doit donner `8c11e856`, sinon la tâche signée tire une image absente. `ARBRE_*` et `ENTREES_SHA` portent sur les sources et la fermeture, indépendantes de Go : inchangées ;
- **J2 (registre)**, `stockage.sh` : pousse dans `workspace/sample-app` la seule référence de la 04 (`3a7ca1b1`, `~/.cache/supply-chain-poc/w/b04/app-layout`), dont viennent aussi les images d'essai de J4. La voie D en 1.26.11 a besoin d'une référence `f5e6bcb0` : layout de la 04 en 1.26.11 présent sur l'hôte (`07c/banc/b04-1.26.11/app-layout`, index = `f5e6bcb0`), à copier hors du banc, sous `w/` (qui survit au démontage) ;
- **J7 (voie A, sans réseau)**, `buildkit.sh` l. 380 à 382 : `BUILDER_D` `d50ae575`, `APP_REF` `3a7ca1b1`, `BIN_REF` `e3749c68` ;
- **J7 (construction)**, `construction.sh` : défauts `APP_REF` et `BUILDER` (surchargeables depuis l'étape 4) ;
- **J8 (tests, bascule, contrôles 6 et 7)**, `preuves.sh` : `APP` vaut `builds/sample-app@${APP_REEL:-$APP_DIGEST}`, défaut `3a7ca1b1`. Plus profond : **le test 8 suppose que l'image réelle et les images d'essai ont le même digest** (index des bundles par `APP_DIGEST`, l. 1421 : « toutes les images de ce digest », bundles de `essai-webhook` pris dans le même index ; « autre digest » exclu par `APP_DIGEST`, l. 1464 à 1475), et `referrers()` (contrôles 6 et 7, R5) compte les referrers de l'image réelle par `APP_DIGEST`. C2 du contrôle 6 (« même digest, autre dépôt ») change de sens. Ces blocs n'ont jamais tourné avec deux digests (l'étape 4 n'a lancé que `bascule`) ;
- **07a (G3, G4, G6, G7, G8)**, `plateforme.sh` l. 96 : `IMAGE` `3a7ca1b1`, cible du CronJob de scan. Après un démontage, `builds/sample-app@3a7ca1b1` n'existe plus : le scan échouerait ;
- **06 (S6a)**, `s6a.sh` l. 55 : `APP_REF` `3a7ca1b1`, même CronJob reposé avec le deb.

**Hors du chemin du rejeu** (à garder tels quels, mesures historiques ; mesuré dans `rejeu.sh`) : `declencheur.sh` de la 01 (S5 sautée), `bascule.sh` de la 03 (pas sur le chemin, mesure de 13:22:20Z), `durcissement.sh` l. 886 (`etape_h6_mesure`, `h6*` exclues), les images d'essai de J4 (`APP_DIGEST` de `stockage.sh`, `tekton.sh`, `tsa.sh`, `politique.sh`, `kyverno-*.sh`, `redemarrer.sh`, tâche signée `publier-essai`) : elles restent des copies de `3a7ca1b1`, ce qui évite de re-signer `publier-essai`.

**Choix de conception (à sec)** : deux digests. L'image réelle passe à `f5e6bcb0` ; les images d'essai restent `3a7ca1b1` (la référence de la 04 en 1.26.10, toujours poussée en J2). Le test 8 et `referrers()` séparent les deux.

**Restent au propriétaire** (rien lancé) :
- **VSA** : le bundle versionné de la 10, re-poussé par `pousser_vsa`, est lié à `3a7ca1b1`. Avec `POUSSER_VSA=1`, le contrôle 6 ne peut pas passer sur `f5e6bcb0` tant que la brique 10 n'a pas produit une VSA de la nouvelle image (clé du propriétaire, un accord par push) ;
- **rejeu de zéro** : action sur les VM ; il recrée la clé `vex`, donc les trois VEX signés deviennent invérifiables et chacun demande un nouvel accord nommé ;
- **`mise.toml`** : Go 1.26.11 n'y est déclaré nulle part (promesse de l'étape 1 de ne pas le modifier). `voie-d.sh` lira la toolchain dans le cache des modules, comme `prefetch.sh` de la 03, sans toucher `GOROOT_DIR`.

**Prédiction de la mesure suivante** ([`predire-voie-d.sh`](../predire-voie-d.sh), journal `predire-voie-d.log`) : assemblage de la voie D recopié de `voie-d.sh etape_assembler` sur un Zot jetable (127.0.0.1:5077). Témoin : binaire `e3749c68` face au layout `3a7ca1b1` ; puis binaire `56f3cd7d` face au layout `f5e6bcb0`. Dans les deux cas : deux assemblages identiques, index du layout = digest de référence, binaire de la référence = binaire assemblé, même taille de tar, écarts limités à la somme de contrôle, devmajor et devminor, configuration identique hors rootfs, historique et created, created `1970-01-01T00:00:00Z` face à `0001-01-01T00:00:00Z`. Le digest de la voie D n'est pas prédit (il diffère de la référence par construction) : il est relevé. **Bilan attendu : 14 cas, 0 écart.**

**Mesure, résultat** ([journal](predire-voie-d.log), 2026-11-24T14:21:45Z ; note de 2026-11-24T14:27:25Z) : **14 cas, 0 écart**, conforme. Témoin 1.26.10 : voie D `c9244139…`, **égal au digest du dernier rejeu de la 08** (`08-trust-plane/resultats/voie-d-assembler.log`, l. 28) : la recopie est fidèle. **Go 1.26.11 : voie D `sha256:a4223414484792eba58326fa3608d994ddb8ee4d1d0bf4e7db2a0402780d9821`**, mêmes 18 octets d'écart (somme de contrôle, devmajor, devminor), même configuration, même created que face à `3a7ca1b1`. Registre jetable effacé.

**Constat qui remet en cause le choix « deux digests »** (relevé à sec, même note) : plusieurs témoins des étapes rejouées de `preuves.sh` reposent sur le fait que l'image réelle et les images d'essai ont **le même digest** :
- test 7, cas C : `builds/essai-images`, « même digest » poussé sans Chains ;
- test 8, cas « webhook-seul » (l. 1502 à 1504 : cosign doit vérifier les 2 bundles pour le digest jugé) et le CONSTAT de l'ancien contrôle (l. 1515 et 1516 : « accepté » attendu) ;
- contrôles 6 et 7, cas C2 (« même digest, autre dépôt »).

Avec deux digests, ces cas deviennent triviaux (refus pour cause de digest) ou échouent : ils ne démontreraient plus rien, à chaque rejeu futur. Le choix « deux digests » est **suspendu** jusqu'à la décision du propriétaire ; les modifications de `preuves.sh` et `stockage.sh` faites dans ce sens sont retirées du dépôt (gardées hors du dépôt).

Autres défauts trouvés en chemin : `construction.sh compte` lit `APP_LAYOUT@APP_REF` (défaut `w/b04/app-layout`, qui ne contient que `3a7ca1b1`) ; `s4d3.sh` de la 06 juge `builds/sample-app@$APP_DIGEST`.

**Prix des deux options** :
- **un seul digest** (images d'essai elles aussi en `f5e6bcb0`) : les témoins gardent leur sens et `preuves.sh` ne change pas de logique. En contrepartie, la tâche signée `publier-essai` porte `3a7ca1b1` en dur et doit être re-signée (accord nommé de signature). Il faut aussi une entrée de plus dans la liste revue, le cas de posture `param-en-trop-par-bundle.yaml` à repointer, la lecture de `taches.yml` par `preuves.sh` l. 1213 (première référence), et `APP_DIGEST` à porter dans `stockage.sh`, `tekton.sh` (5 littéraux), `tsa.sh`, `politique.sh`, `kyverno-*.sh` et `redemarrer.sh` ;
- **deux digests** : aucune signature, mais 5 témoins affaiblis à chaque rejeu futur (ci-dessus), un journal du test 8 et des contrôles 6 et 7 réécrit avec des témoins plus faibles, et une logique de `preuves.sh` jamais exécutée que seul un rejeu de zéro validerait.

Faits pour les deux options (dans ce commit) : `voie-d.sh` (Go 1.26.11 lu dans le cache des modules, image de build exigée `8c11e856`, binaire `56f3cd7d`, référence `f5e6bcb0`), `buildkit.sh` (`BUILDER_D`, `APP_REF`, `BIN_REF`), `construction.sh` (défauts `APP_REF`, `BUILDER`, `APP_LAYOUT`).

**Prédiction** ([`reference-layout.sh`](../reference-layout.sh), journal `reference-layout.log`) : layout `f5e6bcb0` du banc copié sous `~/.cache/supply-chain-poc/w/b04-1.26.11/app-layout` (lu par `construction.sh compte`, et par `stockage.sh registre` selon l'option) : index = `f5e6bcb0`, blobs conformes avant et après, copie identique. **Bilan attendu : 4 cas, 0 écart.**

**Résultat** ([journal](reference-layout.log), 2026-11-24T14:27:56Z ; note de 2026-11-24T14:27:57Z) : **4 cas, 0 écart**, conforme ; 2,6 Mo, 3 blobs.

**En attente** : décision du propriétaire, « un seul digest » (re-signature de `publier-essai`, accord nommé) ou « deux digests » (5 témoins affaiblis). Rien n'est lancé dans le cluster ni sur les VM.

**Heures** : reprise de 14:15:44 à 14:27:57 UTC : 12 min 13 s ; **total de la 07c : au plus 1 h 02 min 26 s** pour 10 h estimées.

## Étape 7 : option « un seul digest » (note de 2026-11-24T14:34:15Z)

**Décision** : à la question « Pour les images d'essai : un seul digest ou deux digests ? », réponse verbatim du propriétaire : « Un seul digest ». Les images d'essai de J4 (`builds/essai-*`, copies de la référence de la 04 poussée en J2) passent elles aussi à `f5e6bcb0` ; `preuves.sh` garde sa logique (`APP_REEL` = `APP_DIGEST`).

**Périmètre relevé à sec** (remplacements de `3a7ca1b1` par `f5e6bcb0`, et de `w/b04/app-layout` par `w/b04-1.26.11/app-layout`) :
- J2 : `stockage.sh` (`APP_LAYOUT`, `APP_DIGEST`) ;
- J4 : `tekton.sh` (5 littéraux et 2 chemins de layout, `signature`, `verifier`, `webhook`, `essais_webhook`) ;
- J5 : `tsa.sh` ; J6 et suivants : `politique.sh` (sourcé par `preuves.sh` et `s4d3.sh` de la 06) ; fin du rejeu : `kyverno-correctif.sh`, `kyverno-permanent.sh`, `kyverno-admission.sh` ; hors rejeu, par cohérence : `redemarrer.sh` (lit `workspace/sample-app@APP_DIGEST`, que J2 ne poussera plus en `3a7ca1b1`) ;
- 07a : `plateforme.sh` l. 96 (cible du scan) ; 06 : `s6a.sh` l. 55 ;
- **tâche signée `publier-essai`** : son gabarit écrit le digest des essais en dur dans le résultat `IMAGE_DIGEST` ; la version signée porte `3a7ca1b1`. Re-signature par la clé des tâches (**accord nommé requis**), puis une entrée de plus dans la liste revue, **placée en premier** sous `publier-essai` : `preuves.sh` l. 1213 lit la première référence comme tâche en service (l'ancienne `836cd080` reste, pour le cluster en service, dont les images d'essai sont toujours `3a7ca1b1`) ;
- inchangés : le cas de posture `param-en-trop-par-bundle.yaml` (référence lue comme une chaîne par le linter, jamais tirée : son attendu « aucune » ne dépend pas du bundle) ; `porte_test.rego` (jeu d'essai unitaire de la règle).

**Prédiction** ([`predire-publier-essai.sh`](../predire-publier-essai.sh), journal `predire-publier-essai.log`, rien signé, Zot jetable) : rendus du gabarit avec `3a7ca1b1` et `f5e6bcb0` : 2 lignes de diff, la seule ligne changée est le résultat `IMAGE_DIGEST` ; la tâche signée versionnée porte l'ancien digest ; témoin : la tâche signée versionnée poussée par `tkn bundle push` dans le Zot jetable redonne `836cd080` (liste revue), deux fois. **Bilan attendu : 5 cas, 0 écart.** Si le témoin tient, le digest du bundle de la nouvelle signature pourra être calculé hors du vrai Zot.

**Passage 1** ([journal](predire-publier-essai-1.log), 2026-11-24T14:34:31Z, renommé sans modification) : **5 cas, 2 écarts, tous deux de mon fait**. (1) Critère faux : la ligne 2 du gabarit (commentaire) cite les marqueurs `@BUSYBOX@`, `@IMAGE@` et `@DIGEST@`, que `sed` remplace aussi : 2 lignes changées (4 lignes de diff), pas 1 ; la seule ligne de spec changée est bien le résultat `IMAGE_DIGEST` (cas OK), et `tkn task sign` ne garde pas les commentaires. (2) Banc faux : le Zot jetable (configuration de la 03) refuse le manifeste Docker v2 que pousse `tkn bundle push` (`MANIFEST_INVALID`) ; le vrai Zot a `http.compat: ["docker2s2"]` (`08-trust-plane/stockage/zot.json`). Le dernier cas passait à vide (deux digests vides) : critère durci.

**Passage 2, prédiction** : même script corrigé (lignes changées `2c2,40c40` ; Zot jetable avec `compat docker2s2` ; les deux poussées comparées à `836cd080`). **Bilan attendu : 5 cas, 0 écart.**

**Passage 2, résultat** ([journal](predire-publier-essai.log), 2026-11-24T14:35:05Z) : **5 cas, 0 écart**, conforme : seule ligne de spec changée, le résultat `IMAGE_DIGEST` ; bundle de la tâche signée versionnée = `836cd080` sur deux poussées dans le Zot jetable. Le digest d'un bundle se calcule hors du vrai Zot.

**Remplacements faits** (note de 2026-11-24T14:36:46Z ; `bash -n` sur chaque fichier ; `shellcheck -S error` : seules les 3 erreurs déjà présentes de `preuves.sh` l. 3296 et 3297, comparaisons d'heures voulues) : `stockage.sh` (`APP_LAYOUT`, `APP_DIGEST`), `tekton.sh` (5 littéraux, 2 chemins de layout), `tsa.sh`, `politique.sh`, `kyverno-correctif.sh`, `kyverno-permanent.sh`, `kyverno-admission.sh`, `redemarrer.sh`, `plateforme.sh` (07a), `s6a.sh` (06) ; commentaires de `preuves.sh` ; `rejeu.sh` : additif du 24/11 et mise en garde sur la VSA (avec `POUSSER_VSA=1`, le contrôle 6 refuserait `f5e6bcb0` tant que la brique 10 n'a pas produit sa VSA ; déduit du code, non mesuré). Vérification à sec de la clé publique des tâches (`~/.cache/supply-chain-poc/08/pki/taches.pub`) : la signature versionnée de `publier-essai` est acceptée par `tkn task verify`, une copie au digest altéré est refusée.

**Prédiction de la re-signature** ([`signer-publier-essai.sh`](../signer-publier-essai.sh), journal `signer-publier-essai.log`, **sur accord nommé**, recopié au journal) : témoin, ancienne signature acceptée par la clé publique ; `tkn task sign` réussi ; nouvelle signature acceptée ; négatif, nouvelle signature avec le digest remis à `3a7ca1b1` refusée ; écart avec l'ancienne, signature exceptée : la seule ligne `IMAGE_DIGEST` ; témoin, bundle de l'ancienne = `836cd080` ; bundle de la nouvelle identique sur deux poussées (digest relevé, ligne `NOUVEAU BUNDLE|`) ; signature versionnée remplacée seulement si tout est conforme. **Bilan attendu : 8 cas, 0 écart.** Ensuite, à la main : la nouvelle référence est ajoutée en premier sous `publier-essai` dans `politique/porte/taches.yml` (`836cd080` gardée), puis `tools/secrets-depot.sh` et commit. Rien n'est écrit dans le vrai Zot ni dans le cluster : la ConfigMap `porte` du cluster en service n'a pas besoin de la nouvelle référence (ses images d'essai sont toujours `3a7ca1b1`).

**Accord** : à la question « Autorisez-vous la re-signature de la tâche publier-essai (digest f5e6bcb0) ? », réponse verbatim du propriétaire : « J'autorise ».

**Re-signature, résultat** ([journal](signer-publier-essai.log), 2026-11-24T14:39:05Z ; note de 2026-11-24T14:39:31Z) : **8 cas, 0 écart**, conforme. Clé publique des tâches `9e118e036265b4de…` (DER) ; ancienne signature acceptée, nouvelle acceptée, copie au digest remis à `3a7ca1b1` refusée ; seule ligne changée hors signature : `IMAGE_DIGEST` (l. 37) ; témoin du bundle `836cd080` ; **nouveau bundle `sha256:17b50c7c8bfa6c617f21946e75839db2acd0a0d159565e9ab45aed01301881af`**, identique sur deux poussées. `politique/taches/publier-essai.signee.yaml` remplacée. Liste revue : `17b50c7c` ajoutée **en premier** sous `publier-essai` (relu par `yq` : deux références ; l'`awk` de `preuves.sh` l. 1213 rend `17b50c7c`), `836cd080` gardée. Rien n'est écrit dans le vrai Zot ni dans le cluster.

**Étape 7, scripts du rejeu : portés à sec.** Mesuré à sec : l'assemblage de la voie D (14 cas), le rendu et la signature de `publier-essai` (5 et 8 cas), la copie du layout (4 cas). Le reste est un portage de valeurs, **jamais exécuté dans un cluster** ; seul un rejeu de zéro le prouvera.

**Contrôles après la signature** (note de 2026-11-24T14:42:59Z, lecture seule) :
- **balayage complet** : les 39 scripts qu'appelle `rejeu.sh` (champ `run` des tâches de `mise.toml` et chemins directs), lignes hors commentaires, motifs `b04/app-layout`, `GOROOT_DIR`, `1.26.10`, `3a7ca1b1`, `d50ae575`, `e3749c68`, `c9244139`. Restent, hors de l'image sample-app : `prefetch.sh` de la 03 (Go de l'image d'outils du prefetch, pas celui de la compilation ; la fermeture ne change pas, mesuré à l'étape 4), `politique.sh` l. 96 et 1041 à 1045 (binaire du rattrapage, outil de la plateforme), `durcissement.sh` l. 886 (`h6_mesure`, exclue du rejeu), `replay.sh` de la 10 (`pousser_vsa`, sous `POUSSER_VSA=1` : VSA de la brique 10, ci-dessous). **Constat hors du périmètre de la 07c** : `s4d.sh` de la 06 compile le **deb** de sample-app avec Go 1.26.10 (l. 63, « même version que l'image de prefetch ») ; que le deb `60f25f5c` porte aussi `GO-2026-6859` n'est pas mesuré ici. 19 et 19b : aucune occurrence ;
- `construction.sh compte`, `entrees` et `constat_cm` relus : `compte` lit `APP_LAYOUT@APP_REF` (cohérent après le portage), `entrees` ne dépend que des arbres de la 03 ;
- **défauts résolus = valeurs de l'étape 4** : `BUILDER` `8c11e856…` (`construction-taches.log`, `construction-provenance.log`), `APP_REF` `f5e6bcb0…` (`construction-construire.log`, `construction-provenance.log`) ;
- **le dépôt est en avance sur le cluster en service** : dans le vrai Zot (lecture anonyme), `workspace/sample-app`, `builds/essai-signature` et `builds/essai-webhook` en `f5e6bcb0` → **404** ; `builds/sample-app@f5e6bcb0` → 200. Conséquences : `redemarrer.sh`, hors du rejeu et utilisé sur le cluster en service, est **remis à `3a7ca1b1`** (il exige `workspace/sample-app@APP_DIGEST`) ; `tekton.sh`, `tsa.sh`, `politique.sh`, `preuves.sh` (test 8, contrôles), `kyverno-*.sh` ne valent plus, lancés seuls, que **après un rejeu de zéro** : sur le cluster en service ils chercheraient des images d'essai absentes, et `politique.sh declencheurs` publierait le nouveau bundle dans le vrai Zot. La liste revue du dépôt n'est plus égale à la ConfigMap `porte` du cluster (une référence de plus, `17b50c7c`). À savoir pour les travaux Kyverno A2 et A5, qui reprendraient `kyverno-*.sh`.

**Restent** (chacun sur accord) :
- **VSA** : la brique 10 doit produire une VSA de `f5e6bcb0` avant tout rejeu avec `POUSSER_VSA=1` (sans quoi le contrôle 6 refuserait l'image réelle ; déduit du code) ;
- **rejeu de zéro** : action sur les VM ; il recrée la clé `vex`, les trois VEX signés seront à re-signer (un accord nommé par document) ;
- **`mise.toml`** : Go 1.26.11 n'y est pas déclaré (`voie-d.sh` le lit dans le cache des modules ; un cache effacé le perdrait) ;
- hors du chemin, laissés tels quels : `declencheur.sh` de la 01, `bascule.sh` de la 03, `durcissement.sh` l. 886, les bancs et essais historiques.

**Heures** : de 14:27:57 à 14:39:31 UTC, attentes des réponses du propriétaire comprises : 11 min 34 s ; **total de la 07c : au plus 1 h 14 min 00 s** pour 10 h estimées.

## Étape 7, VSA de `f5e6bcb0` (brique 10) : préparée à sec

Note de 2026-11-24T15:04:46Z. Prédictions datées et commitées avant tout lancement (`214b96b5`) : [`predictions.md`](../../10-independent-replay/resultats/f5e6bcb0/predictions.md).

**Relevé** (lectures anonymes de Zot, 14:58 à 15:01 UTC) :
- quatre provenances de PipelineRun sur `f5e6bcb0`. La cible est **`9539952b`**, J7 du passage 2, terminé à **13:27:42 UTC**. La règle des 24 h de la 10 place donc R4 au plus tôt le **2026-11-25T13:27:42Z** ;
- la clé de Chains versionnée valide les enveloppes, et `horodatage/bundles` contient 8 bundles horodatés ;
- `politique-replay.md` et `outils/` sont inchangés depuis `6c44219`. Aucune valeur n'y est épinglée, donc ni nouvelle politique ni poussée de politique ;
- le contrôle 6 ne lie une VSA qu'au digest (additif du 03/11, 22:45 UTC, de la 10). Après un rejeu de zéro, qui reconstruit la même image, il accepterait donc encore une VSA de `f5e6bcb0` faite sur le cluster en service. Mais elle attesterait une construction d'avant le rejeu : c'est la limite « acceptée en connaissance de cause » du 03/11, après laquelle le propriétaire avait demandé une seconde VSA sur la provenance du rejeu (nouvelle attente de 24 h). L'archive Go et R2 servent dans les deux ordres ;
- go.dev publie pour `go1.26.11.linux-amd64.tar.gz` le sha256 `9849f4e0…` et une taille de 66 999 944 octets.

**Portage de `replay.sh` de la 10** :
- `IMAGE`, `INVOCATION`, `FIN_BUILD`, `GO_ARCHIVE`, `GO_SHA256` et `RESULTATS` passent par l'environnement. Sans eux, les valeurs effectives sont identiques à `HEAD~` (relu par `bash -x`) ;
- le cache `provenance.json` du domaine n'est réutilisé que pour la même invocation (avant, il aurait relu `c4242a11`) ;
- avec `RESULTATS`, le journal de la porte de la 08 va dans un sous-dossier : sinon la copie aurait lu l'ancien `preuves-reelle.log` ;
- un journal existant est refusé.

**Corrections après relecture** (note de 2026-11-24T15:08:17Z) :
- la variable s'appelle `RESULTATS_REPLAY`, pas `RESULTATS`. `rejeu.sh` de la 08 exporte `RESULTATS`, et `replay.sh`, lancé par `pousser_vsa`, en aurait hérité. Le chemin est rendu absolu (`realpath -m`), puisque `porte` le transmet à `preuves.sh`. Les défauts ont été relus par `bash -x` dans trois cas (rien, `RESULTATS` seul, `RESULTATS_REPLAY`) : sans `RESULTATS_REPLAY`, le dossier reste `resultats/` ;
- R3 transportera **4 entrées**, et non 6 (supposition de la prédiction). C'est mesuré à sec : les couches `.att` passées dans `outils/entrees.py` donnent `construire-image` `4dcbc4b7`, `builder-go-voie-d` `8c11e856`, fermeture `74c265e7` et web-dist `47f72275`. La prédiction est corrigée avant tout lancement de R3.

À relire avant R4 et R5 :
- `rebuild.sh` et les caches froids (GOCACHE, racine BuildKit) ;
- le commentaire de `etape_vsa`, « vsa.py de HEAD, poussé » ;
- les dépendances de `preuves.sh reelle` envers les images d'essai absentes du cluster en service.

**Défaut relevé** : deux fonctions `etape_outils` (R1 l. 191, R2 l. 281). Bash garde la seconde, donc l'archive de Go passe par [`go-domaine.sh`](../go-domaine.sh), sur accord.

**R1 `version_go`** ([journal](../../10-independent-replay/resultats/f5e6bcb0/r1-version_go.log), 15:04:42 UTC, lecture seule) : **conforme**. Entrée `builder-go-voie-d@8c11e856…`, manifeste OCI, 1 couche, `go1.26.11`, version retenue `go1.26.11`.

**Restent, chacun sur accord** :
- téléchargement de l'archive (`go-domaine.sh`, 13 cas) ;
- R2 `outils` et R3 dans `sc-replay` ;
- R4 au plus tôt le 2026-11-25T13:27:42Z, déclenché à la main ;
- R5, avec un accord nommé pour le push de la VSA.

Les défauts de `replay.sh` et `rejeu.sh` ne passeront à `f5e6bcb0` que dans le commit qui archive la VSA.

**Heures** : de 14:39:31 à 15:08:17 UTC, poussée et reprise comprises : 28 min 46 s. **Total de la 07c : au plus 1 h 42 min 46 s** pour 10 h estimées.

**Accord** : à la question « Autorisez-vous le téléchargement de l'archive Go 1.26.11 et les étapes R2 et R3 dans sc-replay ? », réponse verbatim du propriétaire : « J'autorise ».

**Résultats** (note de 2026-11-24T15:13:31Z), tous conformes aux prédictions :
- **archive Go** ([journal](go-domaine.log), 15:12:48 UTC) : **13 cas, 0 écart**.
  - sha256 `9849f4e0…` et taille de 66 999 944 octets identiques sur go.dev et sur l'archive téléchargée ;
  - ziphash du module = `h1:KyINmJ/…` ;
  - fichiers : 11 524 communs, tous de contenu identique ; `bin/go`, `gofmt`, `compile`, `link` et `VERSION` identiques ;
  - seuls 20 `_go.mod` sont propres au module (0 hors `_go.mod`) ;
  - archive gardée dans `~/.cache/supply-chain-poc/10/telechargements`.
- **R2 `outils`** ([journal](../../10-independent-replay/resultats/f5e6bcb0/r2-outils.log), 15:13:14 UTC) : 5 empreintes `OK` dans la VM ; `go version go1.26.11 linux/amd64` ; BuildKit 0.25.2, runc 1.3.3, cosign 3.1.4 et oras 1.3.6, inchangés.
- **R3 `transporter`** ([journal](../../10-independent-replay/resultats/f5e6bcb0/r3-transporter.log), 15:13:22 UTC) : sujet et `.att`, **8 bundles horodatés** et **4 entrées** copiés, bundle git de `main` ; 77 Mo dans la VM.
- **R3 `verifier_entrees`** ([journal](../../10-independent-replay/resultats/f5e6bcb0/r3-verifier_entrees.log), 15:13:26 UTC) : **0 KO** (31 `OK`).
  - 8 bundles vérifiés sur 8, hors réseau ; provenance `9539952b` extraite d'un bundle vérifié ; section 1 de la politique tenue ;
  - entrées `4dcbc4b7`, `74c265e7`, `47f72275`, `8c11e856` et commit `6391fd43`, digests recalculés égaux ;
  - Dockerfile `d56985c1`, contrôlé par la tâche ; `go1.26.11`, égal à la toolchain du domaine ;
  - `finishedOn` signé à 13:27:42Z, jeton de la TSA à 13:28:06 UTC.

**Prochaine étape** : R4 `rebuild`, au plus tôt le **2026-11-25T13:27:42Z**, déclenché à la main (action sur la VM, accord à demander). Il faut d'abord relire les trois points notés plus haut.

**Heures** : de 15:08:17 à 15:13:31 UTC : 5 min 14 s. **Total de la 07c : au plus 1 h 48 min 00 s** pour 10 h estimées.

### Relecture à sec avant R4 et R5 (note de 2026-11-24T15:22:58Z)

Faite sur l'hôte, par lecture du code et des journaux. Seule lecture extérieure : deux lectures anonymes de manifestes dans Zot. Rien dans la VM, le cluster ou `mise.toml`.

**1. Caches froids de R4 : tenus.**
- `transporter_r4` vide `~/r4` avant la copie.
- `rebuild.sh` vide la racine BuildKit (`rm -rf /var/lib/replay-buildkit`) et le contexte `~/r4/e`. Les deux constructions passent `--no-cache`.
- Le second moteur pose `GOCACHE` et `GOMODCACHE` dans `~/r4/e`, donc vides.
- R2 a fait `rm -rf /usr/local/go` avant d'extraire 1.26.11 : aucun fichier de 1.26.10 ne reste dans la toolchain copiée dans l'image de build du domaine.
- Recette : Dockerfile `d56985c1`, contrôlé par la tâche en R3. C'est le même que celui du PASSED de `3a7ca1b1` (`04-hermetic-repro/Dockerfile`). Ses options de `go build` sont celles que `rebuild.sh` recherche. Seule change l'image de build.

**2. « vsa.py de HEAD, poussé » (`etape_vsa`) : tenu, avec une conséquence pratique.**
- Le contrôle porte sur deux choses : `outils/vsa.py` sans modification hors commit, et HEAD présent sur une branche distante.
- Au moment de la relecture, HEAD est `7d8a0c8e`, poussé. Le commit de cette note le fait avancer : **il faut le pousser avant R5 `vsa`**, sinon l'étape refuse.
- Ensuite, `vsa` peut suivre R4 sans nouvelle poussée, tant que le journal de R4 n'est pas commité. S'il l'est d'abord, il faut pousser avant `vsa`, avec un accord.
- Aucune valeur figée (`3a7ca1b1`, `c4242a11`, 1.26.10) dans les scripts Python de `outils/` (`*.py`, seuls cherchés), ni dans `politique-replay.md` à `6c44219` (103 lignes, lu par `git show`), que la VSA citera. `vsa.py` reçoit l'image et l'invocation en arguments.

**3. Dépendances de `preuves.sh reelle` (porte avant et après) : aucune image d'essai.**
- `etape_reelle` ne juge que l'image réelle `builds/sample-app@f5e6bcb0` (`APP_DIGEST` de `politique.sh`). La source attendue est `TETE_J2` = `6391fd43`, le commit de la provenance vérifiée en R3. Elle utilise aussi les 8 bundles de `horodatage/bundles` et l'image de la porte `plateforme/porte@e77994c2`.
- `PORTE_DIGEST` est inchangé depuis le 23/11 (aucun commit ne le touche).
- Lecture anonyme dans Zot, entre 15:21:19 et 15:22:50 UTC (encadrement par deux `date -u`) : `plateforme/porte@e77994c2` et `builds/sample-app@f5e6bcb0` sont présents.
- Les images d'essai `f5e6bcb0` absentes du Zot en service ne servent qu'aux étapes de J2 à J8 et au contrôle 6 (C2, `builds/essai-webhook`), hors de R5.
- **Verdict comparé avant et après le push** (`juger` de `politique.sh` et `politique/porte-job.yaml`, lus en entier) :
  - `porte_apres` compare les champs 3 à 5 (`success`, violations et avertissements de `ec`), 7 et 8 (contrôle 9, conteneur `horodatage`) ;
  - les champs 9 et 10, ceux du contrôle 6 (conteneur `vsa`), sont exclus ; les champs 11 et 12 (contrôle 7) aussi ;
  - `ec` tourne dans le premier conteneur d'initialisation (`porte`). `vsa` est un conteneur ordinaire, lancé après : son refus ne peut ni empêcher ni changer le verdict de `ec` ;
  - le push écrit dans `builds/vsa/sample-app`. Il ne touche ni aux enveloppes de Chains ni à `horodatage/bundles`, d'où les champs 7 et 8 sont tirés.
- La prédiction « porte inchangée avant et après le push » reste donc cohérente avec le commentaire de `rejeu.sh` : sans VSA de `f5e6bcb0`, c'est l'étape `controle6` qui refuserait l'image réelle (C1), pas `porte_avant`.
- Attendu, sans être comparé : avant le push, le champ 9 ne sera pas `ok`, puisqu'aucune VSA de `f5e6bcb0` n'existe (le 03/11, il valait `ok|1/1` avant et `ok|2/2` après). Après le push, il devrait valoir `ok`, si la ConfigMap `porte` du cluster porte encore la clé du domaine. Ce n'est pas vérifié ici (lecture du cluster non faite).

**Relevé à reporter dans le commit qui archive la VSA**
- `rejeu.sh` re-pousse la VSA par `env JALON=r5 mise run replay -- pousser_vsa`.
- Avec les défauts de `3a7ca1b1`, `lancer` réécrit `resultats/r5-pousser_vsa.log`. Avec `RESULTATS_REPLAY=…/f5e6bcb0`, il refuserait, puisque ce journal existera.
- Ce commit devra donc donner au rejeu :
  - un dossier ou un jalon propre (par exemple `JALON=rejeu-r5`) ;
  - le chemin du bundle `f5e6bcb0`.
- Code lu, non lancé.

**Heures** : de 15:13:31 à 15:22:58 UTC, poussée comprise : 9 min 27 s. **Total de la 07c : au plus 1 h 57 min 27 s** pour 10 h estimées.
