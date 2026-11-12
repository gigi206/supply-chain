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
