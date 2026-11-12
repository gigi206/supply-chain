# Brique 06, S6a, pas 3 et 4 (contrôle 7 du deb en service) : prédictions (12/11/2026, préparées à partir de 12:51:01 UTC)

Préparées sur « continue » (cadre : à sec, rien lancé). Le travail a commencé à 12:51:01 UTC et la rédaction de ce fichier à 12:56:24 UTC, d'après `date -u`. L'heure du commit fait foi.

**Rien n'est lancé.** Tout ce qui suit écrit dans le cluster, dans Zot ou sur `sc-stockage`, et vient **après S5b et le relevé du 21/11** (ordre c, décision du 12/11/2026). Chaque étape attend un **accord nommé**.

## Ce qui est préparé

Aucun fichier rejoué par S5b n'est modifié : `scanner.sh`, `scan-job.yaml`, `plateforme.sh`, `fraicheur-scan.*`, `alertes.yml` et `s4d3.sh` restent tels quels. Tout passe par des correctifs non appliqués ou par des étapes neuves de [`s6a.sh`](../s6a.sh). `s6b.sh` et `rejeu/` ne sont pas touchés.

**Deux correctifs neufs**, non appliqués, en plus de [`s6a-scanner-deb.patch`](../s6a-scanner-deb.patch) :
- **[`s6a-fraicheur-deb.patch`](../s6a-fraicheur-deb.patch)** porte sur `fraicheur-scan.py` (07a).
  - Une variable `SCANS` liste les « dépôt@digest », avec une série par dépôt.
  - Sans `SCANS`, le script garde `DEPOT_SCAN@DIGEST` et sa sortie d'aujourd'hui. L'unité de la 07a n'a donc pas à changer.
  - Tout est lu avant d'écrire : un dépôt illisible laisse le fichier entier inchangé.
  - Un seul `.prom` est écrit : un second fichier aurait répété la série de la base, avec les mêmes labels.
- **[`s6a-alertes-deb.patch`](../s6a-alertes-deb.patch)** porte sur `alertes.yml` et `alertes-tests.yml` (19).
  - `ScanEnRetard` prend un `absent()` par dépôt. Sans sélecteur, `absent()` ne se déclencherait plus si une seule des deux séries disparaissait.
  - L'expression reste sur une ligne, puisque l'étape `regles` lit chaque `expr:` ligne par ligne.
  - Les tests G8 reçoivent la série du deb. Le test « fichier disparu » attend deux alertes, une par dépôt.
  - Un test neuf fait manquer la seule série du deb : seul ce dépôt doit déclencher, après le `for: 5m`.

**Trois étapes neuves de `s6a.sh`** :
- **`periodique`** :
  - vérifie que `s6a-scanner-deb.patch` est appliqué et commité ;
  - réapplique `scan-config` comme `cm_scan` de la 07a ;
  - crée le CronJob `scan-sample-app-deb` à 11:15 UTC, puis lance un passage depuis lui.
  - Le CronJob est rendu depuis `scan-job.yaml`, avec `NATURE=deb` dans `analyser` et les limites de `revocation` tirées de `limites.tsv` (08c). Sans ces limites, `limites-obligatoires` le refuserait, comme le premier passage de l'essai.
  - Avant toute écriture, son gabarit, ramené à l'image, doit égaler celui de `scan-sample-app` en service.
  - Avec `S6A_SEC=1`, l'étape s'arrête après le dry-run serveur et cette comparaison.
- **`fraicheur`** :
  - installe le `fraicheur-scan.py` corrigé sur `sc-stockage` ;
  - passe les deux dépôts par un fichier complémentaire de l'unité (`fraicheur-scan.service.d/s6a-deb.conf`) ;
  - compare les séries à une lecture de Zot depuis l'hôte, puis à Prometheus.
- **`porte`** :
  - lance le Job de la porte sur le deb avec `juger` de `politique.sh` (08), comme l'étape `porte` de `s4d3.sh` ;
  - tourne en sous-shell, pour que les variables de la 08 ne sortent pas de l'étape.

Le sujet du scan est nommé `sample-app-deb` (`@NOM_IMAGE@`). `scan.rego` ne juge que le digest du sujet, pas son nom.

## Contrôles à sec faits

- `git apply --check` des trois correctifs, chacun seul, sur l'arbre de travail : passe.
- Les trois correctifs appliqués ensemble à une copie de HEAD (`git worktree`, retirée ensuite) : passe, et `sh -n` passe sur le `scanner.sh` obtenu.
- `fraicheur-scan.py` corrigé, compilé, puis exécuté hors réseau (`unshare -rn`), avec une lecture de Zot simulée, sur trois cas :
  - deux dépôts : trois séries ;
  - un seul dépôt, sans `SCANS` : la sortie et le fichier d'aujourd'hui, à l'identique ;
  - panne de lecture du deb : code 1, fichier inchangé.
- `bash -n` de `s6a.sh`. Les seules lignes retirées sont l'usage et le `case`, réécrits avec les trois étapes.
- **Non fait** : `promtool`, qui n'existe que sur `sc-stockage` ; aucun rendu par `kubectl`, puisque je ne lance `kubectl` qu'à travers les scripts.

## Ordre et commandes, après S5b et le relevé du 21/11

1. J'applique les trois correctifs, je commite, et je pousse sur ton « oui ».
2. `S6A_SEC=1 mise exec -- poc/bricks/06-deb-sbuild/s6a.sh periodique` : rien d'écrit.
3. `mise exec -- poc/bricks/06-deb-sbuild/s6a.sh periodique`
4. `mise exec -- poc/bricks/06-deb-sbuild/s6a.sh fraicheur`
5. `mise run observabilite -- regles`, puis `mise run observabilite -- deployer` (étapes existantes de la 19), une fois la série du deb dans Prometheus.
6. `DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s6a.sh porte`, après `pousser_vsa` si la VSA doit être `ok`.

## Prédictions

| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| Q1 | `periodique`, `S6A_SEC=1` | Gabarit du Job du deb, ramené à l'image, égal à celui de `scan-sample-app` ; `NATURE=deb` ; `15 11 * * * Etc/UTC Forbid` ; horaire de l'image inchangé (`30 9 * * *`) ; rien d'écrit | Moyenne : des champs posés à la main sur l'objet en service, autres que les limites de `limites.tsv`, feraient un écart. L'étape s'arrête alors avant toute écriture |
| Q2 | `periodique` | sha256 de `scanner.sh` dans `scan-config` égal à l'arbre corrigé ; CronJob admis ; job `s6a-manuel` réussi avant l'échéance de 1800 s | Moyenne : premier passage sous `limites-obligatoires` en `Deny` avec ce gabarit |
| Q3 | `periodique` | `DEB|sample-app_1.0.0-1_amd64.deb, sha256 0b489d43…` ; `ARTEFACT|deb, 2 PURL versionnées`, comme E1 | Haute, si le deb reste `039949f9` |
| Q4 | `periodique` | Referrers du deb dans `builds/scan/sample-app-deb` : 0 avant (dépôt absent, 404, ou vide) et 1 après ; sujet `039949f9` ; bundle vérifié sur l'hôte avec la clé du scanner | Haute |
| Q5 | `periodique` | Prédicat : au moins une vulnérabilité, dont des correspondances de la stdlib go1.24.4 et de chi v5.2.3 (P6 : 140 correspondances sur la base de G0). 0 KEV. Je ne prédis pas le nombre : la base sera plus récente | Moyenne pour 0 KEV |
| Q6 | `fraicheur` | `Result` à `success` ; fichier complémentaire lu par systemd ; trois séries dans Prometheus, égales aux lectures de l'hôte, sous 90 s ; une ligne au journal, `scan builds/scan/sample-app=… builds/scan/sample-app-deb=…, base …` | Haute pour les séries ; moyenne pour le délai |
| Q7 | `regles` (19) | `promtool check rules` et `promtool test rules` passent, y compris le test neuf | Moyenne : jamais lancé |
| Q8 | `deployer` (19) | Règles chargées ; `ScanEnRetard` inactive, puisque les deux séries sont présentes et fraîches | Haute |
| Q9 | `porte` | `success` de ec à `true`, aucune violation, horodatage `ok`, **scan `ok`** ; VSA `ok` si `pousser_vsa` a tourné, sinon `refus` ; Job réussi seulement si la VSA est `ok` | Moyenne pour le scan : premier jugement de `scan.rego` sur un deb |

`bilan : tout OK` et code 0 sont attendus pour chaque étape de `s6a.sh`. Toute ligne `ÉCART` rend le code 1.

## Limites, consignées sans correction

- **`rejeu.sh` n'intègre pas S6.** Une fois `s6a-alertes-deb.patch` commité, un rejeu de zéro déploierait des règles qui attendent la série du deb, et `ScanEnRetard` resterait active pour ce dépôt jusqu'aux étapes de S6. C'est à décider avec toi avant le prochain rejeu.
- **Lecteurs à une seule série**, invalides avec deux séries :
  - `g8_metriques` et `g8_grafana` (07a), dont le motif est `^scan [0-9]*, base [0-9]*$` ;
  - `scan-saut-resolution.sh` (08c), qui lit `.data.result[0]`.
- **Journaux du job du deb dans Grafana** : la lecture par l'auditeur, sur le modèle de `g7_grafana`, n'est pas dans ce lot. Les journaux sont archivés par l'étape et collectés par Loki.
- **Témoin de scan manquant** pour le deb, sur le modèle de `g8_suspendre` et `g8_reprendre` : non préparé. Le test de règle neuf est le seul témoin.
- **Digest du deb.** Si S5b ne reproduit pas `039949f9`, chaque étape refuse sans rien écrire, et la suite est à décider.
- **Effet sur l'image.** `scan-config` porte ensuite le `scanner.sh` corrigé, et le scan de `sample-app` de 09:30 passe aussi par le plancher. E4 de l'essai montre qu'il le tient, avec 2 PURL versionnées.
