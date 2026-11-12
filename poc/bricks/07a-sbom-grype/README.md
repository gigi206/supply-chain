# Brique 07a : SBOM + Grype hors ligne et porte KEV (partie locale)

Seuil (README, brique 07a) : Syft + Grype avec la base officielle archivée, **sans egress** ; la porte bloque un cas KEV de test.

## Chaîne

| Étape | Outil | Réseau |
|---|---|---|
| Archivage quotidien de la base officielle : `latest.json` et archive téléchargés, **empreinte vérifiée**, puis poussés dans Zot sous `vulndb/grype:<date>` | [`fetch-db.sh`](fetch-db.sh) | Oui (grype.anchore.io), une fois par jour |
| Restauration de la base **par digest**, import dans un cache vierge | `oras pull`, `grype db import` | Non (`unshare -rn`) |
| SBOM de fermeture : referrer CycloneDX de la fermeture Hermeto (brique 03) | `oras discover` / `pull` | Non |
| SBOM de l'artefact : Syft sur le binaire | `syft` | Non |
| Fusion sur une **clé PURL normalisée** (Hermeto écrit `…/chi/v5@v5.2.3`, Syft `…/chi@v5.2.3#v5`) ; composants sans version écartés | [`sbom_merge.py`](sbom_merge.py) | Non |
| Scan, puis prédicat `https://supply-chain.example/scan/v1` avec KEV, EPSS, alias, correctifs et **référence de la base utilisée** | `grype`, [`scan_predicate.py`](scan_predicate.py) | Non |
| Porte : image de test signée et attestée, évaluée avec les **politiques du banc C** | cosign, Conforma, Kyverno | Non (registre local) |

## Résultats ([`bench.sh`](bench.sh), journal : [`resultats/bench.log`](resultats/bench.log))

Syft 1.38.0 et Grype 0.104.1 viennent du nixpkgs 25.11 épinglé (binaires de cache.nixos.org, signatures vérifiées par Nix). La base Grype est en v6.1.10, construite le 28/10/2026 : 196 Mo compressée, 3,2 Go importée.

| Mesure | Résultat |
|---|---|
| Import de la base hors réseau | 167 s |
| SBOM fusionné de sample-app | chi v5.2.3, stdlib Go 1.26.10, marked 16.4.1, plus les modules du projet |
| Scan de sample-app (sans réseau) | < 1 s ; **5 vulnérabilités réelles sur chi v5.2.3** (2 GHSA Medium, 3 GO-2026 non notées), **0 KEV** |
| Scan du cas KEV (même SBOM + log4j-core 2.14.1) | ≈ 1 s ; 13 vulnérabilités dont **2 KEV** (CVE-2021-44228, CVE-2021-45046) |
| **Porte, cas ok** | **PASS** (Conforma et Kyverno) |
| **Porte, cas KEV** | **FAIL** dans les deux moteurs : « KEV sans VEX valide » (GHSA-jfh8-c2jp-5v3q, GHSA-7rjr-3q55-vv33) |

La donnée KEV vient de la base Grype v6 elle-même (`knownExploited`, catalogue CISA). Aucun flux externe n'est consulté au moment du scan.

**Rejeu sur le laptop (29/10/2026)** ([`resultats/bench-laptop.log`](resultats/bench-laptop.log)) : base du 29/10 (v6.1.10) importée hors réseau en **70 s** ; mêmes résultats que dans le cloud, soit 5 vulnérabilités et 0 KEV pour sample-app, 13 dont 2 KEV pour le cas log4j, et une porte PASS / FAIL dans les deux moteurs.

## Constats

- **Import coûteux** (167 s, 3,2 Go) : la plateforme importera chaque base **une fois**, dans une tâche dédiée, vers un volume en lecture seule indexé par le digest de l'archive. Les tâches de scan le monteront sans le modifier.
- **PURL divergents entre outils** pour les modules Go majeurs (≥ v2). C'est une entrée directe du **test négatif sur la correspondance des PURL** (VEX, brique 07b) : un VEX écrit sur un format doit s'appliquer à l'autre.
- Le **PURL du module principal** vient du remote `origin` du dépôt (ici un chemin local) ; sur la plateforme, ce sera l'URL Forgejo.
- **Séparation des clés** : pour rester comparable au banc C, le scan est signé ici avec la clé « chains ». Sur la plateforme, il le sera avec une **clé de scanner dédiée**, vérifiée comme la VSA (ADR 0003 ; constat de sécurité du banc C).
- sample-app a des vulnérabilités réelles mais non KEV sur chi v5.2.3 : la porte les laisse passer (la politique ne bloque que les KEV sans VEX et les paquets malveillants). Elles entreront dans le **score** (brique 07b), et Renovate proposera la montée de version.

## Reproduction

```bash
ORAS_OPTS=--plain-http REG=localhost:5000 WORKDIR=/tmp/db ./fetch-db.sh   # imprime DB_REF
DB_REF=… CLOSURE_REF=localhost:5000/deps/sample-app@sha256:… APP_BIN=…/sample-app \
  REG=localhost:5000 WORKDIR=/tmp/b07 ./bench.sh
```

`CLOSURE_REF` et `APP_BIN` viennent du banc de la brique 03.

## Reste à faire sur le laptop

- Tâches Tekton : import quotidien de la base (CronJob), scan dans une tâche de confiance, prédicat signé par la clé du scanner (brique 08).
- Scan des images et des rpm/deb (qualificatif `distro=` des PURL), puis Grype comme scanner unique sur EL, ce qui reste à documenter (2b-2).

## Suite sur le laptop : scan dans la plateforme (protocole préparé à sec le 04/11/2026 à 18:22 UTC, rien joué)

Le choix revient au propriétaire (« Celui que tu veux ») : la 07a est préparée pendant l'attente de R4 (brique 10). Ce protocole ne touche ni `sc-replay` ni `builds/vsa`. La porte de la 08 n'est modifiée qu'après R5, car `porte_avant` et `porte_apres` comparent ses verdicts.

But : le **contrôle 7** de l'ADR 0000 (« attestation de scan : aucune KEV sans VEX, aucun MAL- ») est **exigé par la porte réelle**, comme le contrôle 6 l'est depuis le 03/11/2026. Le scan est signé par une **clé de scanner dédiée**, distincte de celle de Chains.

### Relevés (04/11/2026, 18:15 à 18:22 UTC, lecture seule)

- **Pas de SBOM dans la plateforme.**
  - `publier-fermeture` (prefetch F2 de la 03) n'affiche que l'empreinte de `bom.json`. Il ne le publie pas : un referrer sur un digest signé par Chains n'a été mesuré que pour le bundle Sigstore.
  - L'image de sample-app part de `FROM scratch` et ne contient qu'un binaire Go. Syft sur l'image ne verra que les modules Go et la stdlib, pas `marked` (npm), qui venait du SBOM de Hermeto au banc.
- **La porte ne sait pas lire un scan.** Le `ec` de la porte vérifie avec `chains.pub` seulement, et `porte.rego` n'a aucune règle de scan. Les règles `scan_present`, `kev_without_vex` et `malicious` existent dans le banc C (`poc/benchmarks/kyverno-seul/conforma/policy/bench.rego`). `ec validate input` existe en v0.10.42, la version épinglée.
- **Où ranger le scan.** R5 de la 10 a montré qu'un bundle rangé dans le dépôt de l'image fait ignorer `.sig` et `.att` par ec et cosign. Il faut un dépôt séparé, comme `builds/vsa/<nom>`. Constat sur Zot : la règle `builds/**` donne le droit de créer (par digest) à `poc-images` et à `poc-replay` **partout** dessous, `builds/vsa/` compris. C'est la clé qui protège l'attestation, pas l'ACL.
- **Base Grype du jour.**
  - Schéma `v6.1.10`, construite le 04/11/2026 à 06:20:59 UTC : c'est le même schéma qu'au banc du 29/10.
  - `latest.json` n'annonce qu'une empreinte. Pas de `.sig` aux chemins évidents (`<archive>.sig` et `latest.json.sig` répondent 404) ; une signature ailleurs n'est pas exclue, c'est à confirmer en G0.
- **Versions.**
  - Épinglées dans `mise.toml` : Grype 0.104.1 et Syft 1.38.0.
  - Amont : Grype v0.121.1 et Syft v1.56.0, du 02/11/2026. Leurs `checksums.txt` sont signés sans clé (`checksums.txt.sigstore.json`).
  - Précédent de vérification d'une signature amont sans clé : `tsa.sh` (cosign, identité et émetteur attendus) ; on ne signe jamais rien avec le Sigstore public.
- **Stockage éphémère allouable.** `sc-confiance` 14,9 Go, `sc-build` 29,9 Go, `sc-stockage` 19,9 Go. La base importée fait 3,2 Go.
- **Référence morte** : la section « Constats » cite « ADR 0003 », mais `docs/adr` ne contient que 0000 et 0001. Le texte est laissé tel quel ; ce relevé vaut correction.

### Décisions à prendre (avant G1)

| # | Question | Options | Recommandation |
|---|---|---|---|
| D1 | **Source du SBOM** (point bloquant) | (a) Syft sur l'image, plus Syft sur la source au commit, lue dans Forgejo (`go.mod`, `go.sum`, `package-lock.json`), fusionnés par `sbom_merge.py` ; (b) `bom.json` de Hermeto publié par `publier-fermeture` dans un dépôt séparé ; (c) Syft sur l'image seule, en acceptant la perte de `marked` | **(a)**. Aucune tâche signée n'est modifiée, et le commit épinglé donne l'intégrité (git vérifie les objets). La construction est hermétique depuis une fermeture vérifiée contre ces mêmes fichiers de verrou. (b) modifie une tâche signée et la liste revue, et oblige à rejouer F2 et F3. (c) perd une dépendance |
| D2 | **Dépôts et comptes de Zot** | `builds/scan/<nom>` avec un compte `poc-scan` qui crée par digest seulement ; `vulndb/**` avec un compte `poc-vulndb` qui pose des tags datés | Oui. Cela modifie `zot.json` et redémarre Zot (accord du propriétaire) |
| D3 | **Import quotidien de la base** (le cluster n'a aucune sortie vers grype.anchore.io) | (a) timer systemd sur `sc-stockage`, comme la décision D1 de la 01, avec `fetch-db.sh` et l'empreinte vérifiée ; (b) lancement à la main depuis l'hôte | **(a)** |
| D4 | **Fraîcheur exigée par la porte** | On retient le scan vérifié le plus récent (`scannedAt`). Il est refusé s'il date de plus de **7 jours**, ou si sa base a été construite plus de **3 jours** avant lui | Ces seuils, ou d'autres fixés par le propriétaire. Effet : chaque rejeu de la 08 refait un scan |
| D5 | **Versions** | (a) garder Grype 0.104.1 et Syft 1.38.0 : même schéma de base, résultats comparables au banc ; (b) passer à 0.121.1 et 1.56.0 | **(a)**, puis montée de version à part (Renovate). Prédit : compatibles avec le schéma v6.1.10, vérifié en G0 |
| D6 | **Moteur du contrôle 7** | (a) cosign vérifie, puis `ec validate input` juge le prédicat avec les règles du banc, reprises et testées ; (b) `grep` sous busybox, comme `vsa.sh` | **(a)** : (b) est fragile sur des tableaux JSON |

### Jalons

| Jalon | Contenu | Touche | Estimation |
|---|---|---|---|
| G0 | Relevés : signature éventuelle de la base. Import à sec de la base du jour par Grype 0.104.1, sur l'hôte et hors réseau (`unshare -rn`), dans `~/.cache/supply-chain-poc/07a`. SBOM de D1 (a) comparé à celui du banc (5 PURL attendus) | Hôte seul (téléchargement de 200 Mo, avec accord) | 0,5 h |
| G1 | Base : compte `poc-vulndb` et dépôt `vulndb/grype` (D2), puis timer sur `sc-stockage` (D3), durci comme celui de S3 de la 01. Preuves : une archive poussée par jour, empreinte vérifiée, contre-épreuve d'une empreinte altérée refusée | Zot, `sc-stockage` | 1,5 h |
| G2 | Image d'outils du scanner : Grype et Syft depuis les archives de release (empreinte, signature des `checksums.txt` vérifiée comme dans `tsa.sh`), cosign v3.1.4, oras, et jq ou python3 pour le prédicat (à trancher en G2). Construction reproductible, comme l'image d'outils de J5, puis copie dans Zot `plateforme/outils-scan` | Zot | 1,5 h |
| G3 | Clé et identité : clé Transit `scanner` (ecdsa-p256, non exportable), politique `scanner-signature` limitée aux trois chemins du client hashivault, rôle JWT lié au seul compte `scan:scanner`. Espace `scan` sur `sc-confiance`, NetworkPolicy d'OpenBao ouverte à cet espace seulement. Calque de J5 (clé `tsa`) | OpenBao, cluster | 1 h |
| G4 | Job de scan (`politique/scan-job.yaml`), sans sortie hors de Zot, Forgejo et OpenBao : base tirée par digest et importée dans un emptyDir (limite 5 Gi), SBOM de D1, scan, prédicat `https://supply-chain.example/scan/v1` (`scan_predicate.py`). Connexion JWT, puis `cosign attest-blob --key hashivault://scanner`, sujet = digest de l'image. Bundle poussé en referrer dans `builds/scan/sample-app` par `poc-scan`. Preuves : 5 vulnérabilités et 0 KEV, comme au banc (base plus récente : nombre à relever), signature vérifiée sur l'hôte, audit d'OpenBao | Cluster, Zot | 2 h |
| G5 | **Après R5 seulement.** Contrôle 7 dans la porte : conteneur `scan` (cosign, avec `scanner.pub` de la ConfigMap), puis `ec validate input` sur le prédicat retenu (D4, D6), avec les règles reprises de `bench.rego` et leurs tests `opa`. **Champs ajoutés en fin de VERDICT** : les positions lues par `preuves.sh`, `bascule.sh` et `replay.sh` ne bougent pas | Porte (ConfigMap, Job) | 1,5 h |
| G6 | Tests négatifs, avec des témoins signés par une clé jetable sous une ConfigMap `porte-temoin`, comme pour les témoins de D6 : KEV (SBOM augmenté de log4j-core 2.14.1), MAL-, VEX expiré, VEX valide (admis), clé étrangère sur la porte réelle, autre digest, scan absent, scan trop vieux. Témoin : image réelle `3a7ca1b1` admise | Porte, Zot (`builds/essai-*`) | 1,5 h |
| G7 | Intégration : étapes ajoutées à `rejeu.sh` de la 08. Journaux du Job et audit d'OpenBao consultables dans Grafana (19b). README, doc 03 et constat dans l'ADR 0000, sans changer les grilles | Dépôt | 1 h |

**Estimation : 10,5 h** (une décision s'impose à partir de 21 h). G0 à G4 peuvent avancer pendant que R4 et R5 de la 10 attendent ; G5 à G7 viennent après R5.

### Effets à connaître

- Zot redémarre une fois en G1 (nouveaux comptes et dépôts). OpenBao gagne une clé et un rôle en G3.
- La porte gagne un conteneur. Une image sans scan récent est refusée : le rejeu de la 08 devra lancer un scan avant la porte.
- La base importée ajoute 3,2 Go temporaires sur `sc-confiance`, et l'archive environ 200 Mo par jour dans Zot.
- Pas de VEX avant la 07b. « KEV sans VEX » veut donc dire, en pratique, « aucune KEV ».

**Décisions du propriétaire (04/11/2026, vers 18:37 UTC, « Go ») : D1 (a), D2, D3 (a), D4 (7 jours et 3 jours), D5 (a), D6 (a), toutes conformes aux recommandations ; G0 lancé.** Prédictions de G0 : [`resultats/g0-predictions.md`](resultats/g0-predictions.md).

**G0 joué le 04/11/2026 (18:39 à 18:42 UTC), conforme** ([prédictions et résultat](resultats/g0-predictions.md), [journal](resultats/g0.log)). Premier passage archivé : un seul KO, dû au contrôle, qui attendait le PURL de chi sous sa forme Hermeto. Résultats :
- la base du jour n'a **aucune signature**, seulement une empreinte ;
- l'import hors réseau par Grype 0.104.1 prend 74 s, pour 3,2 Go ;
- D1 (a) retrouve les 4 dépendances versionnées du banc ; Syft sur l'image seule ne voit pas `marked` ;
- sample-app a 5 vulnérabilités et 0 KEV ; le cas log4j a 2 KEV.

Prochaine étape : G1 (comptes et dépôts de Zot, timer sur `sc-stockage`), avec accord, car Zot redémarre.

**G1 préparé à sec le 04/11/2026 à 18:46 UTC** ([prédictions](resultats/g1-predictions.md)). Ce qui a été écrit :
- `zot.json` (brique 08) : dépôts `builds/scan/**` (`poc-scan`, par digest seulement ; ni `poc-build`, ni `poc-images`, ni `poc-replay`) et `vulndb/**` (`poc-vulndb`, création seulement) ;
- `stockage.sh` : comptes `poc-vulndb` et `poc-scan` ;
- `systemd/` : `base-grype.service`, `base-grype.timer` et `base-grype.sh` ;
- `fetch-db.sh` : ne repousse pas une base déjà archivée, après avoir vérifié l'empreinte ;
- `plateforme.sh` : étapes `g1_oras`, `g1_droits`, `g1_base` et `g1_essai`.

Une décision est ajoutée :
- **D7** : la conservation des bases. Zot tourne avec `gc: false`, 9,7 Go sont libres sur `sc-stockage`, et chaque base fait environ 200 Mo par jour, soit environ 48 jours de marge. Recommandation : pas de rétention dans le PoC (un rejeu de zéro remet à vide), et une alerte de la 19 sur le disque, à prévoir.

`oras` est absent de `sc-stockage` : on y installe le binaire 1.3.6 déjà vérifié en J5, avec son empreinte et sa signature GPG, sans nouveau téléchargement.

**G1 appliqué le 04/11/2026 (19:26 à 19:28 UTC, accord du propriétaire : « Oui »), conforme** ([prédictions et résultat](resultats/g1-predictions.md)) :
- Zot reconfiguré : 9 comptes, `builds/scan/**` et `vulndb/**` ;
- oras 1.3.6 vérifié (GPG et empreinte), puis installé sur `sc-stockage` ;
- droits : 9 essais sur 9 conformes. `poc-images` et `poc-replay` n'écrivent plus dans `builds/scan/`, et une base archivée ne peut pas être remplacée ;
- base du jour archivée sous `vulndb/grype:2026-11-04`, à l'empreinte `ed08c5e3…` ; l'archive tronquée est refusée ;
- timer quotidien actif ; journal lisible dans Grafana.

Un écart de prédiction : `/v2/` répond 200 (lecture anonyme), pas 401. D7, sans rétention, n'est pas encore tranchée : rien ne s'y oppose avant une trentaine de jours.

Prochaine étape : G2, l'image d'outils du scanner.

**G2 préparé à sec le 04/11/2026 à 19:37 UTC** ([prédictions](resultats/g2-predictions.md)) : l'image d'outils du scanner est assemblée sur la base cosign de J5, avec Grype, Syft, oras et `scan-outil`.

**D8, ajoutée** : `scan-outil` réécrit en Go la fusion et le prédicat, parce que l'image n'a pas de python. Mesuré à sec : même JSON que les scripts Python sur G0, binaire reproductible.

**G2 appliqué le 04/11/2026 (19:44 UTC, accord du propriétaire : « Oui », D8 (a) retenue), conforme** ([prédictions et résultat](resultats/g2-predictions.md)) :
- releases de Grype 0.104.1 et de Syft 1.38.0 vérifiées : empreintes de `mise.lock`, signature sans clé du workflow de release sur `main`, contre-épreuve d'identité refusée ;
- image `plateforme/outils-scan@sha256:7eb4f26e…` reproductible (même digest au second assemblage), digest épinglé.

Prochaine étape : G3, la clé Transit `scanner` et l'espace `scan`.

**G3 préparé à sec le 04/11/2026 à 20:00 UTC** ([prédictions](resultats/g3-predictions.md)). Quatre étapes de `plateforme.sh` :
- `g3_cluster` : espace `scan` (`politique/scan.yaml`), NetworkPolicy d'OpenBao et règle `zone-confiance` de la 08, chacune réappliquée seule ;
- `g3_openbao` : clé Transit `scanner`, politiques, identifiants de `poc-scan` dans `kv/scan/zot`, rôles, clé publique exportée ;
- `g3_essais` : refus et connexions croisées comptés, signature vérifiée sur l'hôte ;
- `g3_cosign` : vrai `cosign sign-blob --key hashivault://scanner` depuis un pod de `scan`, sondes réseau, audit des chemins appelés.

Une cinquième étape, `g3_grafana`, relit les journaux du pod et l'audit d'OpenBao à travers Grafana (correction avant exécution, consignée dans les prédictions).

**D9, ajoutée** : les identifiants Zot du job sont lus dans OpenBao, comme en J8, avec deux rôles liés au même compte. `scan-zot` lit les identifiants avec un jeton de 1 min ; `scanner` signe avec un jeton de 5 min pris juste avant la signature. Recommandation : (a). `scanner-signature` a donc quatre chemins, révocation comprise, et non trois.

**G3 appliqué le 04/11/2026 (20:21 à 20:22 UTC, accord du propriétaire : « 1 a, 2 oui, 3 oui », D9 (a) retenue), conforme du premier coup** ([prédictions et résultat](resultats/g3-predictions.md)) :
- clé Transit `scanner` non exportable, rôles `scanner` (5 min) et `scan-zot` (1 min) liés au seul compte `scan:scanner`, identifiants de `poc-scan` dans `kv/scan/zot` ;
- 16 refus et 8 connexions croisées refusées, comptes exacts ;
- vrai `cosign sign-blob --key hashivault://scanner` depuis un pod de `scan`, bundle vérifié sur l'hôte avec [`scanner-cle-publique.pem`](resultats/scanner-cle-publique.pem) ;
- sorties de `scan` limitées à DNS, OpenBao, Zot et Forgejo (Grafana et Internet injoignables) ; OpenBao injoignable sans l'étiquette `app=scan` ;
- journaux et audit lus par l'auditeur dans Grafana.

Le chemin que cosign appelle est `transit/sign/scanner/sha2-256`, et il lit `transit/keys/scanner`. D7 n'est toujours pas tranchée.

Prochaine étape : G4, le job de scan.

**G4 préparé à sec le 04/11/2026 à 20:35 UTC** ([prédictions](resultats/g4-predictions.md)) : job de scan en six conteneurs, un mode de [`politique/scanner.sh`](politique/scanner.sh) chacun. Le scan tourne sans aucun identifiant ; le jeton qui signe est pris après le scan.

`scanner.sh` a tourné dans le système de fichiers de l'image réelle : 5 vulnérabilités, 0 KEV, mêmes identifiants qu'en G0. La lecture de la source demande un conteneur de plus, sur l'image BuildKit, car `outils-scan` n'a pas git. Les refus et l'anomalie du CronJob d'horodatage viennent des témoins de J6, et G1 n'a rien changé à son bilan.

**G4 appliqué le 04/11/2026 (20:38 à 20:40 UTC, accord du propriétaire : « Oui les 2 »), conforme du premier coup** ([prédictions et résultat](resultats/g4-predictions.md)) :
- job de 2 min sur `sc-confiance`, base `vulndb/grype@sha256:13729131…` importée en 103 s, **5 vulnérabilités, 0 KEV**, mêmes identifiants qu'en G0 ;
- attestation signée par la clé `scanner`, sujet `3a7ca1b1…`, publiée par `poc-scan` en referrer dans `builds/scan/sample-app@sha256:23ec3bcf…` ;
- bundle vérifié sur l'hôte, autre digest, autre prédicat et clé de Chains refusés ;
- aucun Secret dans l'espace, audit d'OpenBao sans erreur, journaux et audits lus dans Grafana.

Prochaine étape : G5, le contrôle 7 dans la porte, après R5 de la 10.

**G5 préparé à sec le 04/11/2026 à 21:01 UTC, rien appliqué** ([prédictions](resultats/g5-predictions.md)). R5 mesure la porte avec les fichiers de l'arbre de travail : les fichiers neufs sont donc dans [`politique/porte/`](politique/porte/) et les modifications de la 08 dans [`politique/g5-porte.patch`](politique/g5-porte.patch), appliqué après R5 par `g5_porte`, qui refuse de tourner sans nouvelle VSA dans `builds/vsa/sample-app` (celle du 03/11/2026, `c1bfbcbd…`, ne compte pas).

- **Conteneurs** : `scan-verifier` (initialisation, image d'outils, toujours le code 0) vérifie les énoncés par la clé du scanner ; `scan` (principal, image de la porte) rend la décision avec `ec validate input`.
- **Règles** : elles jugent le scan le plus récent, pas tous les scans (D4). 27 tests sur 27, 17 mutations toutes détectées.
- **Essai sur les images réelles de la porte** : scan réel admis ; sans scan, autre clé, dépôts refusés, KEV, MAL-, scan ou base trop vieux refusés ; entrée absente ou invalide : échec fermé.
- **À valider par le propriétaire** : deux ajouts à D4, `scan.forme` (prédicat incomplet refusé) et le refus d'un scan daté du futur.

Le scan de G4 expire le 11/11/2026 à 20:40:09 UTC. Prochaine étape : `g5_porte`, après R5 de la 10 et avec l'accord du propriétaire.

**Décision du propriétaire (04/11/2026, après 21:05 UTC, réponse « 2 a ») : les deux ajouts à D4 sont retenus**, `scan.forme` et le refus d'un scan daté de plus de 5 min dans le futur.

R5 de la 10 est fini le 04/11/2026 à 22:21 UTC : `g5_porte` n'attend plus que l'accord du propriétaire. Le correctif s'applique toujours à l'arbre après les adaptations d'après R5.

**G5 appliqué le 04/11/2026 (22:25 à 22:28 UTC, accord du propriétaire : « A »), 0 écart du premier coup** ([résultat](resultats/g5-predictions.md)). **Le contrôle 7 est en service dans la porte** :
- image réelle admise, Job réussi, contrôles 6 et 9 inchangés ;
- même digest sans scan refusé (`scan.scan_present`), clé de Chains à la place de celle du scanner refusée, Jobs en échec ;
- journaux lus par l'auditeur dans Grafana ; `controle6` rejoué sur la porte corrigée, 0 écart.

Une image sans scan récent a désormais son Job en échec, et `rejeu.sh` ne lance pas encore de scan : c'est G7. Prochaine étape : G6, les témoins négatifs signés.

**G6 préparé à sec le 04/11/2026 à 22:43 UTC, rien appliqué** ([prédictions](resultats/g6-predictions.md)) : 15 témoins signés par une clé jetable, joués sur un Zot jetable avec le cosign et le ec des images de la porte, tous conformes. Ils couvrent KEV (log4j), MAL-, VEX, fraîcheur, prédicat incomplet, autre digest, clé étrangère, plusieurs scans et referrer illisible. `g6_temoins` écrit dans Zot : il attend l'accord du propriétaire.

**G6 appliqué le 04/11/2026 (22:47 à 22:59 UTC, accord du propriétaire : « A »), 0 écart du premier coup** ([résultat](resultats/g6-predictions.md)) : les 15 témoins sont jugés comme prédit par la vraie porte, l'image réelle reste admise, le bilan du CronJob d'horodatage n'a pas bougé. Prochaine étape : G7, `rejeu.sh`, passage périodique du scan et constat dans l'ADR 0000 ; D7 reste à trancher.

**Décision du propriétaire pour D7 (04/11/2026, « 2 b ») : une rétention réelle, à concevoir**, et non « pas de rétention » que je recommandais. Le code de Zot et un premier passage exploratoire montrent que `gc: true` efface par défaut tout manifeste sans tag, donc l'image réelle : la rétention demande des règles explicites, à mesurer sur une copie du stockage réel avant de toucher à Zot. Prédictions et règles proposées : [`resultats/g7-predictions.md`](resultats/g7-predictions.md). `zot.json` de la 08 porte ces règles, **pas encore appliquées**.

**G7 mesuré à sec du 04/11/2026, 23:50 UTC, au 05/11/2026, 00:22 UTC, rien appliqué** ([résultat](resultats/g7-predictions.md)) : trois Zot jetables sur des copies du stockage réel, blobs vieillis de 30 jours, un balayage complet de 123 dépôts en 32 min.

- **Règles proposées** : 0 écart ligne à ligne avec la prédiction, 0 blob manquant. 19 entrées retirées, 2 tags retirés, 190 Mo libérés. L'image réelle, sa signature, son attestation et ses VSA restent lisibles.
- **À blanc** : 0 entrée modifiée, les mêmes 21 décisions journalisées.
- **Sans règle** : 119 entrées effacées, dont l'image réelle. C'est le défaut de Zot avec `gc: true`, et la raison pour laquelle ces règles ne sont pas facultatives.
- **Un écart** : j'ai prédit 2 dépôts disparus, il y en a eu 3. Un dépôt d'essai déjà vide n'était pas nommé. Cette disparition n'écrit aucune décision au journal d'audit.

Ajouts depuis les prédictions : `g7_grafana` scindée (la lecture de la rétention, `g7_retention`, reste hors de `rejeu.sh`, car `vulndb/grype` n'existe pas au balayage de J2), et rejeu de `controle7` après le passage périodique, car le changement de C1 dans `preuves.sh` n'a jamais été joué. Prédictions de l'application, **sous accord du propriétaire** : [`resultats/g7-application-predictions.md`](resultats/g7-application-predictions.md).

La rétention n'effacera rien de réel avant le 18 ou le 19 novembre : d'ici là, seule cette mesure à sec en répond.

**G7 : décisions du propriétaire du 05/11/2026.** Application de la rétention (« 2 oui »), à 08:18 UTC. **D10 (« A ») : passage périodique du scan, CronJob quotidien à 09:30 UTC sur l'image `3a7ca1b1`.** Une panne du CronJob se traduit par un refus de la porte au bout de 7 jours : elle coûte de la disponibilité, pas de la sécurité, et aucune alerte n'est prévue.

**G7 appliqué le 05/11/2026 (08:18 à 08:53 UTC), du premier coup** ([résultat](resultats/g7-application-predictions.md)) : rétention en service sur le vrai Zot, premier balayage de 30 min sans aucune suppression, 2 dépôts vides disparus comme prédit. CronJob `scan-sample-app` créé, passage manuel réussi avec la base du jour, lisible dans Grafana. Porte conforme avec 2 scans, C2 et C3 toujours refusés. Un écart : 230 Mo de moins que prévu sur `sc-confiance`, non expliqués.

Restent hors de portée : aucune suppression réelle avant le 18 novembre, et `rejeu.sh` n'a pas été rejoué.

**Premier passage planifié réussi le 05/11/2026 à 09:30 UTC** (`scan-sample-app-29897850`, 3 referrers, lisible dans Grafana). Constat consigné dans l'[ADR 0000](../../../docs/adr/0000-assembler-ou-adopter.md), sans changer de note.

**Écart de place expliqué (05/11/2026, 09:34 UTC)** : ce n'est pas le scan, c'est `sc-confiance` qui perd 29 Mo/h, surtout par l'audit de l'API k3s. Audit et journald sont plafonnés, environ 6 Mo/h restent non attribués. Projection, pas une mesure : marge de 835 Mo au-dessus de l'éviction, peut-être consommée vers le 12 novembre. [Détail](resultats/g7-application-predictions.md).

**Additif du 07/11/2026, 19:59 UTC, avant tout push** : le plafond de journald de 282 Mo ne valait que jusqu'au premier redémarrage des VM. Sous RKE2, journald peut occuper jusqu'à environ 2,5 Go sur `sc-confiance`. Lecture tirée du source de systemd, non observée : voir l'additif de 19:56 UTC dans [g7-application-predictions.md](resultats/g7-application-predictions.md).

**G8 préparé à sec le 05/11/2026 (10:40 UTC, rien appliqué)** : alerte de fraîcheur, à soumettre au propriétaire. Prometheus ne voit pas l'état des Jobs ; un timer sur `sc-stockage` mesurera donc ce que la porte exige, la date du dernier referrer de scan et celle de la base, lues en anonyme dans Zot. Trois alertes : `ScanEnRetard`, `ScanBientotRefuse`, `BaseGrypeVieillie`. Script testé depuis l'hôte (nominal, sans referrer, Zot injoignable, 404) ; `promtool` pas encore lancé. Décisions D11 à D13, ordre et effets : [`resultats/g8-predictions.md`](resultats/g8-predictions.md).

**G8 appliqué le 05/11/2026 (10:50 à 10:58 UTC, décisions D11 à D13 du propriétaire, « 1a, 2a, 3a, 4a, 5a »)** : timer `fraicheur-scan` en service, 3 alertes déployées, incident simulé conforme (3 déclenchées, 3 résolues, 6 notifications lues dans Grafana). Un écart de lecture, sans effet sur les règles. Reste à relever le passage du 06/11 ; ni un vrai CronJob en échec, ni le blocage réseau de l'unité, ni `rejeu.sh` n'ont été essayés. Une alerte ne sort pas du PoC : elle se lit dans Grafana. Détail : [`resultats/g8-predictions.md`](resultats/g8-predictions.md).

**Additif du 10/11/2026, 12:26 UTC : `rejeu.sh` rejoué sous RKE2, et relevé de la base pour rpm/deb.** Le propriétaire a choisi « 2 », poursuivre le scan. Rien n'a été lu ni écrit dans le cluster, Zot ou les VM : ce sont des lectures de journaux archivés et de la base importée en G0, sur l'hôte.

- **`rejeu.sh` a été rejoué.** L'affirmation « pas rejoué » ci-dessus, et celle de la ligne Scan de doc 03, sont périmées depuis le 06/11/2026. Les deux reprises à J8 sous RKE2 ont joué toutes les étapes de la 07a (G1, G2, G3, G4, passage périodique, G8, G6), avec 0 KO dans chaque journal :
  - 12:34 UTC : [`rejeu-rke2-reprise-j8.log`](../08-trust-plane/resultats/rejeu-rke2-reprise-j8.log) ;
  - 15:25 UTC : [`rejeu-rke2.log`](../08-trust-plane/resultats/rejeu-rke2.log).

  Ces reprises sont déjà consignées dans la [08b](../08b-rke2/README.md), mais pas ici. G6 apparaît deux fois parce qu'il y a eu deux reprises. Ce n'est pas un rejeu de zéro : les étapes d'avant J8 ont été sautées.
- **Toujours pas prouvé** :
  - le blocage réseau de l'unité `fraicheur-scan` ;
  - la réaction à un vrai CronJob en échec ;
  - le scan des rpm et des deb, parce que les briques 05 et 06 n'ont encore produit aucun paquet dans la plateforme.
- **Relevé de la base pour rpm/deb**, sur la base du 04/11 importée en G0, en lecture seule : [`rpm-deb-releve-base.log`](resultats/rpm-deb-releve-base.log).
  - Il n'y a aucun fournisseur Rocky ; `rhel`, `alma` et `debian` sont présents.
  - La base remplace `rocky` et `rockylinux` par `rhel`. Un rpm de Rocky serait donc jugé sur les données de Red Hat.
  - Debian 13 (trixie) a 60 293 entrées affectées ; Red Hat 9, 31 401.
  - AlmaLinux 9 n'a aucune entrée affectée. C'est non expliqué.
  - Le traitement de cet alias par Grype 0.104.1 n'a pas été lu dans son source : la question « Grype comme scanner unique sur EL » reste ouverte.

*Corrigé à 12:29 UTC, avant tout push, sur relecture du conseiller* :
- **« Un rpm de Rocky serait jugé sur les données de Red Hat » n'est pas établi.** La base remplace `rocky` par `rhel`, mais aucune ligne d'OS ne s'appelle `rhel` : celles de Red Hat s'appellent `redhat` ([complément](resultats/rpm-deb-releve-base-complement.log)). La chaîne `rocky` → `rhel` → `redhat` n'est pas vérifiée : il reste à voir ce que fait Grype 0.104.1.
- **AlmaLinux 9 est expliqué en partie.** Il n'a aucune entrée affectée, mais il a 27 493 entrées non affectées (versions corrigées). Les données d'Alma sont donc rangées autrement que celles de Red Hat (31 401 affectées, 27 368 non affectées). Leur effet sur un scan n'est pas mesuré.
- **Push du 10/11/2026 à 12:20:25 UTC**, oublié dans l'additif de 12:26 :
  - accord : « Oui » ;
  - commits `0aa1a3c..884670b` ;
  - contrôle des secrets OK sur 7 fichiers, dans une copie de travail temporaire retirée ensuite ;
  - branche distante identique à la locale.

**Additif du 10/11/2026, 12:33 UTC : rpm et deb hors ligne, R1 à R6 tenues** ([prédictions et résultat](resultats/rpm-deb-predictions.md)). Choix du propriétaire : « dans l'ordre que tu veux » pour a, b et c ; c passe en premier. Grype 0.104.1 a tourné sur l'hôte seul, hors réseau, sur la base du 04/11, avec des PURL synthétiques d'openssl. Aucun téléchargement ; rien n'a été lu ni écrit dans le cluster, Zot ou les VM.
- Rocky 9.7 et AlmaLinux 9.7 sont jugés sur les données de Red Hat 9 (`redhat:distro:redhat:9`), avec les mêmes 48 vulnérabilités. La version corrigée en garde 20, toutes sans correction publiée par Red Hat.
- Debian 13 est jugé sur ses propres données (38 vulnérabilités).
- **Sans `distro=`, aucune vulnérabilité n'est trouvée, sans aucun avertissement.** Les SBOM de paquets devront porter ce qualificatif, et la porte devra refuser ceux qui ne l'ont pas. Ce point est à reprendre quand les briques 05 et 06 produiront des paquets.
- Grype peut donc servir de scanner unique sur EL, avec deux limites : les errata propres à Rocky ne sont pas utilisés, et le rôle des données d'Alma n'est pas mesuré.
- Le push de 12:31:42 UTC est consigné : accord « 1 oui », commits `884670b..3d5980e`, contrôle des secrets OK sur 5 fichiers dans une copie temporaire retirée ensuite, branche distante identique à la locale. *J'avais annoncé 6 fichiers ; le contrôle en a compté 5.*

*Corrigé à 12:37 UTC, avant tout push, sur relecture du conseiller* (additif de 12:33 UTC et message du commit `d77bbef`) :
- **« Sans aucun avertissement » est faux.** Grype écrit une ligne `WARN` quand il ne connaît pas la distribution, mais `-q` la supprime, et le job réel (`politique/scanner.sh`) utilise `-q`. Le code de sortie reste 0. `--distro rocky:9.7` rattrape un PURL sans qualificatif : 48 correspondances, comme avec `distro=` (S1 réfutée, S2 tenue : [résultat](resultats/rpm-deb-predictions.md)).
- **« Grype peut servir de scanner unique sur EL » va trop loin.** L'essai montre seulement que la correspondance fonctionne quand la distribution est fournie. Pour les briques 05 et 06, une question reste ouverte et n'est pas mesurée : Syft, sur un `.rpm` ou un `.deb` isolé produit par mock ou sbuild, sans `/etc/os-release`, émet-il `distro=` ?
- **« La porte devra refuser » n'est pas une décision.** C'est une proposition au propriétaire, notée **D14** : pour un SBOM de paquets rpm ou deb, la porte refuse un scan dont la `distro` est vide, ou le job passe `--distro` explicitement. À trancher quand les briques 05 et 06 produiront des paquets.
- **Interprétation de « dans l'ordre que tu veux »** (réponse du propriétaire à « lesquelles de a, b et c ») : c est accordé, car il ne touche que l'hôte, et l'ordre m'est laissé. a et b touchent une VM et le cluster : ils attendent chacun un accord nommé.

**Additif du 10/11/2026, 12:47 UTC : filtre réseau de `fraicheur-scan` prouvé ; essai du scan manquant arrêté, car c'est un doublon de la 08c** ([détail](resultats/g8-predictions.md)).
- Avec les filtres de l'unité, Zot passe ; Prometheus et l'API de RKE2 sont bloqués. Sans les filtres, les trois cibles passent. Il y a deux écarts de forme : l'ordre d'affichage de `IPAddressDeny`, et un blocage par dépassement de délai au lieu d'`EPERM`.
- La réaction à un scan manquant était déjà prouvée sous RKE2 du 07 au 09/11, dans la 08c (W1 à W8). La mention « vrai CronJob en échec pas essayé » de cette brique était donc dépassée.
- `scan-sample-app` est suspendu depuis le 10/11 à 12:46:40 UTC, en attendant la décision du propriétaire.

**Additif du 10/11/2026, 12:49 UTC** : sur la décision du propriétaire (« Oui, reprends-le »), `scan-sample-app` a été repris à 12:49:35 UTC. Aucun passage n'a été manqué ; le prochain est attendu le 11/11 à 09:30 UTC ([détail](resultats/g8-predictions.md)).

## Additif du 12/11/2026, 08:58 UTC : deb de la 06, réponse partielle à la question de `distro=`

Mesure de la brique 06 (S6a, relevé 1, [résultats](../06-deb-sbuild/resultats/s6a-predictions.md)), sur l'hôte, hors réseau, avec syft 1.38.0 et grype 0.104.1, et la base de G0.
- Sur le `.deb` isolé de sbuild, syft n'émet pas `distro=` : `pkg:deb/sample-app@1.0.0-1?arch=amd64`, sans espace de noms.
- Pour le binaire Go qu'il contient, extrait de `data.tar`, `distro=` n'est pas nécessaire : 140 correspondances par `github:language:go`, `govulndb:language:go` et `nvd:cpe`.
- **La question reste ouverte pour les paquets de distribution** (rpm de la 05, dépendances deb), ce relevé ne les couvre pas.
- Mesuré aussi : `scan-outil fusion` écarte un PURL sans version, et un SBOM d'artefact vide passe sans erreur (code 0, rien sur la sortie d'erreur).

**Additif du 12/11/2026, à partir de 14:45:38 UTC : replanification de G7 après S5b préparée à sec (« Oui, prépare-la »), NON LANCÉE.**
- S5b, avancé au 13/11, recrée Zot : la tâche `supply-chain-g7-premiere-suppression` du 21/11 ne vaudra plus.
- [`g7-replanifier.sh`](g7-replanifier.sh) relèvera après S5b, en lecture seule :
  - le démarrage de Zot et sa configuration de rétention, comparée au dépôt ;
  - les dates des blobs de `builds/scan/**` et de `vulndb/grype`.

  Il calculera ensuite la nouvelle heure de la tâche. Le calcul, rejoué sur les chiffres du 06/11, retrouve le plan d'alors (balayage le 21/11 à 15:14:56 UTC).
- Procédure, prédictions G1 à G4 et brouillon de la consigne : [`resultats/g7-replanification.md`](resultats/g7-replanification.md).
- La tâche planifiée n'est pas modifiée. Elle sera désactivée au lancement de S5b, sur le même accord.

**Additif du 12/11/2026, à partir de 14:50:52 UTC : deux défauts de `g7-replanifier.sh` corrigés avant tout accord, NON LANCÉ.** Un dossier absent arrêtait l'étape sans message, et `/var/lib/zot` était écrit en dur. Essai hors cluster conforme, trois cas : [`resultats/g7-replanification.md`](resultats/g7-replanification.md).
