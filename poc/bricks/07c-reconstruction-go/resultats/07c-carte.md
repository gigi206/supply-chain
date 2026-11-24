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
