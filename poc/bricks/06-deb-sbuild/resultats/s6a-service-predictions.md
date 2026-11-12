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

## Note datée du 12/11/2026 (corrigé avant tout lancement, après le commit `ffbdb87` de 13:57:37 heure de Paris, 12:57:37 UTC)

Relecture du conseiller, sur trois points que `bash -n` ne voit pas :
- **`periodique` n'était pas relançable.** Tout arrêt après la création du job `s6a-manuel` le laissait en place, et l'étape refusait ensuite de démarrer. Désormais, un `s6a-manuel` terminé est supprimé au départ ; seul un job encore actif fait refuser. Un second passage publie un second referrer : Q4 se lit alors en relatif, « avant plus un ».
- **Lecture de la place sur `sc-confiance`.** Une coupure SSH pendant l'attente arrêtait l'étape sous `set -e`, après les écritures. La lecture ratée est maintenant ignorée, et le minimum ne retient que des nombres.
- **Q9, Job de la porte en échec quand la VSA est refusée.** C'est établi, et non plus supposé :
  - `vsa.sh` sort en code 1 sur un refus (`politique/porte/vsa.sh`, ligne 47, dans la 08) ;
  - `vsa` est un conteneur principal du Job, avec `backoffLimit: 0` et `restartPolicy: Never` ;
  - l'en-tête de `porte-job.yaml`, lignes 13 et 14, dit que le Job ne réussit que si `horodatage`, `vsa` et `scan` réussissent.

  L'attente `/1` sans `pousser_vsa`, et `1/` avec, est donc conservée.

Le script corrigé demande le même accord nommé que la version précédente, aucune n'ayant tourné.

## Additif du 12/11/2026 (à partir de 13:04:25 UTC, après « continue ») : étape `grafana`, NON LANCÉE

La limite « Journaux du job du deb dans Grafana » ci-dessus est levée à sec par une quatrième étape de [`s6a.sh`](../s6a.sh), sur le même accord nommé que les trois autres. Elle suit l'exigence d'audit du propriétaire du 02/11/2026 : tout doit être consultable dans Grafana.

**Ce qu'elle fait.** Elle ne fait que lire, en auditeur, à travers Grafana, avec `grafana_lignes` de la 07a reprise telle quelle :
- les journaux des pods `s6a-manuel-*` dans l'espace `scan`, depuis le début de `periodique` ;
- la signature `transit/sign/scanner` dans l'audit d'OpenBao, et le poussage de `poc-scan` dans `builds/scan/sample-app-deb` dans l'audit de Zot ;
- le journal de `fraicheur-scan.service` sur `sc-stockage`, depuis le début de `fraicheur`.

Les lignes du job sont affichées sans celles qui contiennent `jeton` ou `token`. Les lignes d'audit sont comptées, jamais affichées. Les réponses de Grafana restent dans `~/.cache/supply-chain-poc/06/s6a/grafana` et sont effacées en fin d'étape, même en cas d'échec : aucune n'est archivée.

**Préalables.**
- `periodique` et `fraicheur` doivent finir sur `bilan : tout OK`.
- Aucun passage planifié de `scan-sample-app` ni de `scan-sample-app-deb` ne doit avoir eu lieu depuis le début de `periodique`. Sinon, l'étape refuse : sa signature et son poussage se mêleraient à ceux de `s6a-manuel`.
- L'étape se lance donc juste après `fraicheur`, avant 09:30 UTC le lendemain. Elle s'insère entre les points 4 et 5 de l'ordre ci-dessus :

  `mise exec -- poc/bricks/06-deb-sbuild/s6a.sh grafana`

| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| Q10 | `grafana` | Visibles dans Grafana : `SOURCE|`, `BASE|`, `DEB|` avec le sha256 `0b489d43…`, `ARTEFACT|deb`, `SCAN|`, `ATTESTATION|`, `PUBLIE|`, et la révocation du jeton du scanner. La ligne `PUBLIE|` est égale à celle du journal de `periodique`. Au moins une ligne d'audit d'OpenBao pour la signature. Un poussage de manifeste par `poc-scan` dans l'audit de Zot. Une ligne `scan builds/scan/sample-app=… builds/scan/sample-app-deb=…, base …` du journal de `fraicheur-scan`. Ni le mot de passe de `poc-scan` ni son encodage docker dans les réponses. Toutes les requêtes en HTTP 200 | Haute : mêmes requêtes que `g7_grafana` et `g8_grafana` de la 07a, qui ont passé ; seuls le nom du pod, le dépôt et le motif de la fraîcheur changent |

**Contrôles à sec faits.**
- `bash -n` de `s6a.sh`.
- Hors réseau, sur une réponse simulée de Grafana : extraction des lignes par le filtre `jq` de `grafana_lignes`, motif de la ligne de fraîcheur, ligne `PUBLIE|`, et date tirée de l'en-tête du journal.
- Aucun appel à Grafana, ni au cluster.

**Limite.** Le contrôle des identifiants de `poc-scan` dans les réponses est fait sans tube. Sous `pipefail`, `cat … | grep -q` peut rendre faux quand `grep` trouve, à cause du SIGPIPE de `cat`. Le contrôle aurait alors conclu à l'absence d'une fuite présente. `g7_grafana` (07a) utilise ce tube : c'est consigné ici, sans correction, puisque la 07a est rejouée par S5b telle quelle.

## Note datée du 12/11/2026 (corrigé avant tout lancement, après le commit `e237b3d` de 14:08:07 heure de Paris, 13:08:07 UTC)

Relecture du conseiller, sur trois points :
- **Lignes du job affichées.** L'étape affichait les lignes du job lues dans Grafana, sans celles qui contiennent `jeton` ou `token`, et elles entraient ainsi dans `resultats/s6a-grafana.log` avant le contrôle des identifiants. Elles sont désormais comptées, jamais affichées, comme dans `g7_grafana`. `periodique` archive déjà celles de `kubectl logs`.
- **Phrase inexacte de l'additif.** « Aucune n'est archivée » ne vaut que pour les réponses de Grafana elles-mêmes. Les lignes du journal de `fraicheur-scan` sont toujours affichées, et donc archivées dans le journal de l'étape, comme dans `g8_grafana`. Ce sont des dates (`scan …, base …`) et les messages de systemd.
- **Lecteurs à une seule série : la liste était incomplète.** Deux autres lectures prennent `.data.result[0]` de `scan_dernier_referrer_timestamp_seconds`, dans `preuves.sh` (08) :
  - ligne 3289, dans `etape_scan_saut_suspendre` ;
  - ligne 3321, dans `etape_scan_saut_reprendre`.

  Avec deux séries, aucune de ces lectures n'échoue : elles prennent en silence la première série rendue, image ou deb. Il y a donc cinq lecteurs en tout, tous hors du rejeu sauf `g8_metriques`. Aucun n'est corrigé : la 07a, la 08 et la 08c sont rejouées ou relues telles quelles.

**Contrôle à sec ajouté.** `etape_grafana`, `mesure`, `ecarts` et `grafana_lignes` ont été extraits tels quels des scripts, puis exécutés hors réseau (`unshare -rn`). `curl` et `kubectl` étaient simulés, `HOME` pointait vers le bloc-notes, et les deux mots de passe étaient factices. Quatre cas :
- nominal : `bilan : tout OK`, code 0 ;
- mot de passe factice de `poc-scan` dans la réponse de Zot : un `ÉCART`, code 1 ;
- HTTP 500 sur la requête d'OpenBao : `KO` de `grafana_lignes`, un `ÉCART`, code 1 ;
- passage planifié de `scan-sample-app` après `periodique` : refus avant toute lecture, code 1.

Dans les quatre cas, le dossier de travail est effacé à la sortie. Cela couvre la reprise de `grafana_lignes` par `eval`, ainsi que la portée de `ko`, `P` et `S8`. Grafana et Loki, eux, n'ont pas été interrogés.

L'étape corrigée demande le même accord nommé, puisqu'elle n'a jamais tourné.

## Note datée du 12/11/2026 (à partir de 13:14:56 UTC, après « continue ») : lecteurs à une seule série reclassés, aucun correctif

Les deux notes précédentes, et mon message au propriétaire après `2c2a8ba`, disaient que les cinq lecteurs prendraient « en silence » la première série. C'est inexact pour trois d'entre eux. Relu dans le code, lecteur par lecteur :

| Lecteur | Avec deux séries | Relancé avec deux séries ? |
|---|---|---|
| `g8_metriques` (07a, `plateforme.sh:1607-1612`) | Pas de `result[0]` : toutes les séries sont jointes et comparées à une chaîne exacte de deux entrées. Une troisième série donne un `KO` **bruyant** | Dans le rejeu, mais `sc-stockage` y est recréée sans le fichier complémentaire de S6a : sans `SCANS`, `fraicheur-scan.py` corrigé n'écrit qu'une série |
| `g8_grafana` (07a, `:1625`) | La ligne à deux dépôts ne suit pas `^scan [0-9]*, base [0-9]*$` : `KO` **bruyant** | Non : hors du rejeu, mesure ponctuelle |
| `scan-saut-resolution.sh:48` (08c) | `result[0]`, mais comparé ensuite à la date lue dans Zot pour l'image : une série du deb prise à sa place donne un `KO`, sauf dates égales | Non : relevé unique de `PLAN=2026-11-09T09:30:00Z`, et l'outil refuse dès que son journal existe (`resultats/scan-saut-w8_resolution.log` existe) |
| `preuves.sh:3289` (08, `scan_saut_suspendre`) | `result[0]`, **silencieux**, mais seulement affiché (dates prévues) | Non : a tourné (`resultats/preuves-h5-scan_saut_suspendre.log`), hors du rejeu |
| `preuves.sh:3321` (08, `scan_saut_reprendre`) | `result[0]`, **silencieux** : il choisit s'il faut juger `ScanEnRetard` | Non : a tourné (`resultats/preuves-h5-scan_saut_reprendre.log`), hors du rejeu |

**Décision : aucun correctif.** Aucun de ces lecteurs ne tournera avec deux séries dans ce qui est prévu. Corriger des scripts qui ont déjà tourné détacherait aussi leurs journaux archivés du code qui les a produits. Si l'un d'eux doit être relancé après S6a, il faudra d'abord sélectionner `{depot="builds/scan/sample-app"}`. C'est le label que pose `serie()` de `fraicheur-scan.py`, et que lisent les tests de `alertes-tests.yml`.

**Lecteurs d'alertes, ajoutés au relevé.** Ceux-là ne lisent pas la série, mais l'état de `ScanEnRetard` ou de `ScanBientotRefuse`, tous dépôts confondus. Avec `s6a-alertes-deb.patch`, un retard du deb seul les rendrait actives :
- `alertes_scan` (07a, `:1666`, dans `g8_suspendre` et `g8_reprendre`), comparé à exactement `ScanEnRetard=firing`, puis à une chaîne vide : `KO` bruyant ; hors du rejeu ;
- `ss_alerte` (08, `:3246`), l'état de la règle, et le `activeAt | first` de `preuves.sh:3326`, seulement affiché : les étapes `scan_saut_*`, qui ont déjà tourné ;
- `regle` de `scan-saut-resolution.sh` : relevé unique, déjà fait ;
- `etat_alerte` de l'étape `a7` de la 19 (`observabilite.sh:246`), qui exige l'alerte inactive au départ : hors du rejeu (O4 sauté, `rejeu.sh:126`).

Aucun n'est dans le rejeu. Le seul effet sur un rejeu reste celui déjà consigné plus haut : une fois `s6a-alertes-deb.patch` commité, l'étape O3 du rejeu déploie des règles qui attendent la série du deb, et `ScanEnRetard` reste active par `absent()` pour ce dépôt. Cela relève de la décision à prendre sur l'intégration de S6 dans `rejeu.sh`.

Rien n'a été lancé. Aucun fichier n'est modifié, sauf celui-ci.

## Note datée du 12/11/2026 (à partir de 13:22:55 UTC, après « continue ») : `promtool` sur une copie détachée, préparé à sec, et témoin du deb laissé en question

**Correctifs non appliqués, vérifié.** Pour chacun des trois correctifs, `git apply --check` passe sur `cda8d55` et `git apply -R --check` échoue : aucun n'est appliqué, et tous s'appliquent encore. Le rejeu de S5b déploie donc, à l'étape O3, les règles actuelles, sans le deb.

**`promtool` avant S5b (Q7), préparé à sec, non lancé.** Appliquer `s6a-alertes-deb.patch` dans l'arbre avant S5b ferait garder `ScanEnRetard` active au rejeu (voir plus haut) : ce n'est pas la forme retenue. Le correctif est appliqué seulement dans une copie détachée, comme pour `verif-push`, et c'est le script de la copie qui tourne :

```bash
bash <<'EOS'
set -euo pipefail
cd /home/gigi/Documents/git/github/gigi206/supply-chain
C=/tmp/claude-1000/-home-gigi-Documents-git-github-gigi206-supply-chain/8e4ef563-ec63-44dd-b5a2-5f0729c4e8b2/scratchpad/promtool-s6a
git worktree add -q --detach "$C" HEAD </dev/null
git -C "$C" apply poc/bricks/06-deb-sbuild/s6a-alertes-deb.patch </dev/null
JALON=s6a mise exec -- "$C/poc/bricks/19-observabilite/observabilite.sh" regles || echo "code $?"
cp "$C/poc/bricks/19-observabilite/resultats/s6a-regles.log" poc/bricks/06-deb-sbuild/resultats/s6a-promtool.log
git worktree remove --force "$C" </dev/null && git worktree prune </dev/null
EOS
```

- `mise exec` part de la racine du dépôt, pour l'environnement ; `observabilite.sh` lit ses règles d'après son propre chemin (`here`), donc celles de la copie corrigée.
- Ce que l'étape touche : `/tmp/regles-test` sur `sc-stockage`, créé puis effacé par l'étape elle-même. Ni Prometheus, ni ses règles, ni le cluster, ni Zot : `deployer` n'est pas lancé. S5b recrée de toute façon `sc-stockage`.
- `JALON=s6a` : le journal de la copie s'appelle `s6a-regles.log` et n'écrase aucun journal de la 19. Il est recopié en `resultats/s6a-promtool.log`.

| N° | Prédiction | Confiance |
|---|---|---|
| P1 | `promtool, version 3.13.5`, comme dans `o3-regles.log` | Haute |
| P2 | `check rules` : `SUCCESS: 14 rules found`. Le correctif change l'expression de `ScanEnRetard` sans ajouter de règle | Haute |
| P3 | `test rules` : `SUCCESS`, y compris le groupe neuf (seul le dépôt du deb déclenche, à 6 min) | Moyenne : jamais lancé |
| P4 | Code 0, arbre principal inchangé (`git status` propre hors le journal recopié) | Haute |

En cas d'échec de P3, le correctif est repris avant S5b par un nouveau commit, et la prédiction Q7 tient compte de l'écart. Le journal recopié est commité avant le push de ce soir, jamais entre ce push et `vsa`.

**Témoin d'un scan manquant pour le deb : non transposable tel quel.** `g8_suspendre` et `g8_reprendre` (07a, plateforme.sh:1671-1727) ne se reprennent pas en changeant un nom :
- `alertes_scan` lit l'état de `ScanEnRetard` sur tous les dépôts : il faudrait le filtrer par `depot`, sinon une alerte de l'image passerait pour celle du deb ;
- les fenêtres d'interdiction sont celles du passage de 09:30 ; celui du deb est à 11:15 UTC ;
- l'essai suspend le CronJob au moins 26 h 15 min, ce qui retarde la porte du deb d'autant.

C'est une question au propriétaire : faire ce témoin après S6a, ou garder le test de règle comme seul témoin.

**`rejeu.sh` et S6.** La décision ne bloque rien avant S5b, puisque les correctifs ne sont pas appliqués. Elle est à prendre avant le premier rejeu qui suit l'application des correctifs de S6a.

## Résultats de `promtool` sur la copie détachée (12/11/2026, 13:25:27 à 13:25:36 UTC, accord « Oui, lance-le »), code 0

Journal : [`s6a-promtool.log`](s6a-promtool.log). Copie détachée à `cecb367`, avec `s6a-alertes-deb.patch` appliqué dans la copie seulement. La copie est retirée (`git worktree list` ne montre plus que l'arbre principal).

| N° | Prédiction | Mesure | Verdict |
|---|---|---|---|
| P1 | `promtool, version 3.13.5` | `promtool, version 3.13.5 (… revision: f497435984d1…)` | Tenue |
| P2 | `SUCCESS: 14 rules found` | `SUCCESS: 15 rules found` | **Fausse** |
| P3 | `test rules` : `SUCCESS`, y compris le groupe neuf | `SUCCESS` | Tenue |
| P4 | Code 0, arbre principal inchangé hors le journal recopié | Code 0 ; `git status` : seul `s6a-promtool.log` est nouveau | Tenue |

**Pourquoi P2 est fausse.** J'ai pris le nombre de règles dans `o3-regles.log` (06/11), au lieu de le compter dans l'arbre. L'arbre compte 15 `- alert:` à `cecb367`. La 15e vient du commit `5fbb0b5` (09/11, chantier des Events), postérieur à ce journal. Le correctif n'ajoute aucune règle (aucune ligne `+ - alert:`) : c'est la partie de P2 qui tient.

**Conséquence.** Les règles corrigées passent `check rules`, et tous les tests passent, y compris celui où seul le dépôt du deb déclenche `ScanEnRetard`. Q7 est donc tenue sur une copie avant S5b ; elle reste à rejouer par `regles` dans l'arbre, une fois le correctif commité après S5b. Rien n'a été déployé.

## Note datée du 12/11/2026 (à partir de 13:36:30 UTC) : décision du propriétaire, « Test de règle seul »

**Le propriétaire a retenu le test de règle comme seul témoin d'un scan manquant pour le deb.** Aucun témoin sur le modèle de `g8_suspendre` et `g8_reprendre` ne sera fait. La question laissée ouverte dans la note de 13:22:55 UTC est donc close.

Ce qui couvre le cas :
- **La règle** : le test neuf de `alertes-tests.yml`, où seul le dépôt du deb déclenche `ScanEnRetard`, passe `promtool test rules` (mesure : [`s6a-promtool.log`](s6a-promtool.log), sur une copie). Il reste à rejouer par `regles` dans l'arbre après S5b (Q7).
- **La chaîne réelle de cette règle** a été exercée pour l'image par le témoin G8 de la 07a. Le correctif n'ajoute qu'une branche `absent()` par dépôt. Une erreur d'étiquette dans la branche du deb ferait sonner l'alerte en permanence, ce qui se verrait.
- **La porte** : d'après l'ADR 0000, un arrêt du CronJob se voit par le refus de la porte après 7 jours. Ce défaut bloque, même sans alerte.

**Limite acceptée** : la détection en service d'un scan manquant du deb n'est pas mesurée de bout en bout. Le témoin aurait coûté une modification de `plateforme.sh` (filtre par `depot`, fenêtres du passage de 11:15 UTC) et au moins 26 h 15 min de retard sur la porte du deb.

La décision sur `rejeu.sh` et S6 reste à prendre avant le premier rejeu qui suit l'application des correctifs de S6a.

## Note datée du 12/11/2026 (à partir de 13:42:24 UTC, après « continue ») : intégration de S6 dans `rejeu.sh`, options préparées à sec

**`rejeu.sh` n'est pas modifié** : S5b doit lancer le script approuvé tel quel. Les deux options ci-dessous le modifient, l'une par un commentaire, l'autre par des étapes. Dans les deux cas, rien n'y sera touché avant S5b, ni sans accord. Cette note prépare la décision laissée ouverte plus haut, à prendre avant le premier rejeu qui suit l'application des correctifs de S6a. Rien n'a été lancé.

**Ce qui est vérifié dans le code (lecture seule)**
- Les étapes de la 07a déjà dans le rejeu ne cassent pas avec les correctifs commités :
  - `07a (G8)` : relevé de 13:14:56 UTC. Sans `SCANS`, `fraicheur-scan.py` corrigé n'écrit qu'une série et garde la ligne `scan <date>, base <date>` (docstring et `print` de `s6a-fraicheur-deb.patch`) ;
  - `07a (G4)` et le passage périodique : le plancher de `s6a-scanner-deb.patch` touche aussi la voie image. Le cas D de l'essai (E4) le montre tenu sur sample-app, avec 2 PURL versionnées.
- **Sans intégration**, `ScanEnRetard` reste active pour `builds/scan/sample-app-deb` dès O3, par la branche `absent()`, jusqu'à ce que `periodique` et `fraicheur` soient relancés à la main. Aucun lecteur d'alerte du rejeu ne la juge (relevé de 13:14:56 UTC). Sur le chemin k3s, où le bloc 06 n'est pas joué, elle resterait active en permanence, quelle que soit l'option.
- **Les étapes de `s6a.sh` se rejouent sans réécriture** :
  - `applique` exige seulement les correctifs appliqués et commités ;
  - `periodique` supprime un job `s6a-manuel` terminé, et ne refuse que s'il est encore actif ;
  - `grafana` relit `resultats/s6a-periodique.log` et `resultats/s6a-fraicheur.log`, réécrits par le même passage ;
  - `porte` déduit la VSA attendue des referrers de `builds/vsa/sample-app-deb`, et lit `DISTRO`, que `rejeu.sh` exporte.
- **`s6b.sh pousser_vsa`** lit le bundle et l'énoncé versionnés dans `resultats/` (`s6b-vsa.bundle.json`, `s6b-vsa-enonce.json`). Ils survivent à `detruire`, comme le bundle versionné de la 10. `lire_vsa` n'a pas besoin du bundle horodaté que désigne `inputAttestations`, effacé par tout rejeu. Son témoin, la provenance acceptée par la clé de Chains, lit `08-trust-plane/resultats/chains-cle-publique.pem`, que le rejeu réécrit (`openbao.sh:320`). `rebuild` et `vsa` ne se rejouent pas : 24 h après `finishedOn`, lien coupé, VM sc-replay.

**Contraintes d'une intégration**
1. **Ordre** : après `06 (S4d3)`. Son étape `porte` attend pour le deb une VSA et un scan **refusés** (`s4d3.sh:343-344`). Un scan ou une VSA du deb poussés avant elle la feraient échouer.
2. **Fenêtre horaire** : `hors_fenetre` refuse `periodique` de 09:00 à 12:59 UTC. Sous `set -e`, ce refus arrête le rejeu avant `fuites` et le CIS. La reprise par `DEPUIS=` à cette étape devrait rester possible, puisqu'elle vient après le bloc 08c. C'est déduit du code, non mesuré. Il faut alors un autre libellé, car `tee` réécrit `rejeu-<libellé>.log` (`rejeu.sh:62`).
3. **Digest en dur** : `s6a.sh` et `s6b.sh` désignent `039949f9`. Si le rejeu ne le reproduit pas, `present` refuse et le rejeu s'arrête à cette étape. C'est la limite déjà consignée pour S5b.
4. **Une étape par appel** : `s6a.sh` et `s6b.sh` n'acceptent qu'un argument. Il faut une ligne `etape` par étape.
5. **Durée** : `periodique` attend le job pendant au plus 380 tours de 5 s de sommeil (31 min 40 s), plus le temps des lectures.
6. **Un second push sous `POUSSER_VSA=1`** : aujourd'hui, ce drapeau couvre le push de la VSA de sample-app (brique 10). Avec (b), il couvrirait aussi celui de la VSA du deb. La politique du replay du deb (section 6) soumet chaque push à ton accord : cet élargissement est à approuver en clair.
7. **`applique` repose sur `git apply -R --check`** : un commit ultérieur qui toucherait `scanner.sh` ou `fraicheur-scan.py` près des blocs du correctif ferait refuser l'étape, et arrêterait le rejeu.
8. **Journaux réécrits** : `s6a-*.log`, `s6a-periodique.bundle.json` et les journaux de `pousser_vsa` et de `lire_vsa` seraient réécrits à chaque rejeu. C'est la convention de `rejeu.sh` (lignes 118 et 119) ; l'historique git garde les précédents.

**Options**
- **(a) Pas d'intégration.** Un commentaire de `rejeu.sh` consigne la fenêtre `absent()` du deb, sur le modèle des lignes 146-147 pour l'image.
  - Coût : après chaque rejeu, `ScanEnRetard` reste active pour le deb, et la porte du deb refuse le scan, jusqu'aux étapes de S6 relancées à la main, chacune sur accord.
- **(b) Intégration des étapes durables**, dans le bloc RKE2 et Cilium, après `06 (S4d3)` :
  - `06 (S6a, periodique)`, `06 (S6a, fraicheur)`, puis `06 (S6a, grafana)` ;
  - avec `POUSSER_VSA=1` : `06 (S6b, pousser_vsa)` et `06 (S6b, lire_vsa)` ;
  - enfin `06 (S6a, porte)`, dans les deux cas : VSA attendue `ok` après `pousser_vsa`, `refus` sans.
  - Coût : les contraintes 2 à 8, et une modification de `rejeu.sh` à relire à sec et à faire approuver.

**Ma recommandation : (b), après le premier passage réel des étapes de S6.**
- Pour (b) : c'est le précédent constant. Les étapes de la 07a (G7, G8) et le bloc 06 de S5b ont tous été intégrés au rejeu. (a) laisserait après chaque rejeu une alerte active par construction, alors que cette alerte est le seul mécanisme en service retenu par la décision « Test de règle seul ».
- La condition : n'écrire le diff de `rejeu.sh` qu'après le premier passage manuel des étapes de S6a et de `pousser_vsa`, donc après S5b. Ces étapes n'ont jamais tourné, et P2 vient de montrer qu'une prédiction peut tomber. Les intégrer avant reviendrait à empiler du non-mesuré.
- La question ne porte donc que sur l'orientation, (a) ou (b). Elle ne bloque rien avant S5b.

## Note datée du 12/11/2026 (à partir de 13:46:54 UTC) : décision du propriétaire, « (b) intégrer après S6 »

**Le propriétaire a retenu l'option (b), avec sa condition de calendrier.** Les étapes durables de S6 entreront dans `rejeu.sh`, dans le bloc RKE2 et Cilium, après `06 (S4d3)` :
- `06 (S6a, periodique)`, `06 (S6a, fraicheur)`, puis `06 (S6a, grafana)` ;
- avec `POUSSER_VSA=1` : `06 (S6b, pousser_vsa)` et `06 (S6b, lire_vsa)` ;
- enfin `06 (S6a, porte)`, dans les deux cas.

**Ce qui n'est pas décidé, et le sera sur le diff :**
- l'élargissement de `POUSSER_VSA=1` au push de la VSA du deb (contrainte 6), à approuver en clair ;
- le traitement de la fenêtre horaire de `hors_fenetre` (contrainte 2).

**Calendrier.** Le diff de `rejeu.sh` ne sera écrit qu'après le premier passage manuel réel des étapes de S6a, de `pousser_vsa` et de `lire_vsa`, donc après S5b et le relevé du 21/11. Il sera préparé à sec, puis soumis à un accord nommé, avant le premier rejeu qui suit l'application des correctifs de S6a. Jusque-là, `rejeu.sh` reste celui que S5b lancera.

Rien n'a été lancé. Aucun fichier n'est modifié, sauf celui-ci et `docs/03-validation-briques.md`.
