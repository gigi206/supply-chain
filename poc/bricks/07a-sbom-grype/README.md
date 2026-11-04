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
