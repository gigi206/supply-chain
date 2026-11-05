# G8 de la brique 07a : alerte de fraîcheur du scan, prédictions

Écrites le 05/11/2026, 10:40 UTC, à sec, avant toute application : aucun fichier n'a été posé sur `sc-stockage`, Prometheus n'a pas été redémarré, le cluster n'a pas été touché. Tout dépend d'un accord du propriétaire. Elles ne valent que pour l'ordre ci-dessous.

## Pourquoi

Rien ne signale un CronJob `scan-sample-app` en échec. La porte refuse pourtant un scan de plus de 7 jours, ou dont la base a été construite plus de 3 jours avant lui (D4). Une série d'échecs passerait inaperçue jusqu'au premier refus d'image.

## Relevé en lecture seule (05/11/2026, 10:33 à 10:39 UTC)

- `kube-state-metrics` n'est pas installé, et il est listé comme non audité au doc 04. Le compte `prometheus-lecture` n'a que `services/proxy` sur trois services : Prometheus ne voit pas l'état des Jobs.
- `lastSuccessfulTime` du CronJob : 09:31:49 UTC. Referrers de l'image, lus en anonyme : 3, le dernier créé à 09:31:45 UTC.
- `vulndb/grype` : 2 tags. Bases construites à 06:20:59 UTC le 04/11 et à 06:21:06 UTC le 05/11.
- `sc-stockage` : python3 3.13.5, curl et oras, pas de jq. `/etc/base-grype/ca-poc.crt` est lisible par tous ; `/etc/prometheus/ca-poc.crt` ne l'est pas.
- Les notifications du récepteur local sont lisibles par l'auditeur dans Grafana (les dernières datent du 03/11).

## Décisions soumises au propriétaire (numérotation de la 07a)

| Décision | Recommandé | Autre choix |
|---|---|---|
| **D11, source** | (a) mesurer ce que la porte exige : referrers et tags lus en anonyme dans Zot par un timer sur `sc-stockage`. Une panne du CronJob, du job, de la signature ou de la publication se voit de la même façon | (b) `kube-state-metrics` : audit au doc 04 d'abord ; ne verrait ni la base, ni un job réussi sans referrer |
| **D12, seuils** | `ScanEnRetard` à 26 h (avertissement) ; `ScanBientotRefuse` à 5 jours (critique) ; `BaseGrypeVieillie` à 2 jours (critique) | Autres valeurs |
| **D13, date du scan** | (a) annotation `org.opencontainers.image.created`, non signée, une seule lecture : suffisant pour une alerte, la porte lit le `scannedAt` signé | (b) `scannedAt` du bundle : une lecture par scan, et sans vérifier la signature il n'est pas plus sûr |

Calcul de 26 h : un passage peut démarrer jusqu'à 10:30 UTC (`startingDeadlineSeconds` 3600) et durer 30 min (`activeDeadlineSeconds`), soit 11:00 UTC, 25 h 30 après le passage le plus tôt (09:32 UTC). Un seul passage manqué déclenche l'alerte vers 11:37 UTC le jour même (26 h, plus le `for: 5m`).

## Déjà vérifié à sec (05/11/2026, 10:39 UTC, depuis l'hôte, sortie dans le répertoire temporaire de la session)

| Cas | Résultat |
|---|---|
| Nominal | code 0 ; scan 1793871105 (09:31:45 UTC), base 1793859666 (06:21:06 UTC), conformes au relevé |
| Digest sans referrer | code 0 ; série du scan non écrite, base écrite |
| Zot injoignable | code 1 ; fichier inchangé |
| Dépôt de base inexistant (404) | code 1 ; fichier inchangé |

**Non vérifié** : `promtool` n'a pas été lancé, ni sur les règles ni sur leurs tests. Il n'est pas sur l'hôte, et son exécution est la première étape ci-dessous. Le filtrage `IPAddressAllow` de l'unité n'a jamais tourné sur `sc-stockage`.

## Ordre et prédictions

1. **`JALON=g8 mise run observabilite -- regles`** (accord ; fichiers temporaires dans `/tmp` de `sc-stockage`, supprimés ensuite) : `promtool check rules` trouve 14 règles (11 + 3), `promtool test rules` réussit. Un échec arrête le jalon avant toute installation.
2. **`mise exec -- poc/bricks/07a-sbom-grype/plateforme.sh g8_metriques`** (accord, hors de 07:55 à 08:20 et de 09:25 à 09:40 UTC : un nouveau tag ou referrer entre la mesure et la lecture témoin donnerait un faux KO jusqu'au passage suivant du timer) : compte `fraicheur-scan`, script, unités, fichier `.prom` créés ; `Result=success`, timer actif ; les deux séries lues dans Prometheus égalent la lecture témoin de l'hôte, en moins de 90 s. Si le passage se fait avant le 06/11 à 08:00 UTC : scan 1793871105, base 1793859666.
3. **`JALON=g8 mise run observabilite -- deployer`** (accord) : Prometheus redémarre ; 14 règles chargées, toutes `ok` ; les 3 nouvelles sont `inactive`.
4. **`mise run observabilite -- a7`** (accord) : les 3 alertes sont inactives avant l'incident. `ScanBientotRefuse` passe `firing` en moins de 3 min, `ScanEnRetard` et `BaseGrypeVieillie` en moins de 8 min. Après rattrapage, les 3 sont résolues, avec 3 notifications `firing` et 3 `resolved` reçues. `up{job="fichiers"}` reste à 1, et le fichier d'essai est retiré.
5. **`mise exec -- poc/bricks/07a-sbom-grype/plateforme.sh g8_grafana`** : les mesures et exactement 6 notifications sont lisibles par l'auditeur.
6. **Le 06/11, après le passage de 09:30 UTC** : aucune des 3 alertes n'a été active, la série du scan a avancé d'environ 24 h et celle de la base aussi.

Estimation : 1,5 h, préparation comprise (une décision s'impose à partir de 3 h).

Cumul de la brique, borne haute : 16 h 30 de temps écoulé entre le premier relevé (04/11/2026, 18:15 UTC) et 10:45 UTC le 05/11, nuit et attentes de timers comprises. Le seuil de décision de la brique est 21 h (2 × 10,5 h) : il n'est pas atteint, y compris avec G8.

## Effets à connaître

- **Aucune notification ne sortira du PoC** (D4 de la 19) : une alerte, ici, c'est une ligne dans Alertmanager, dans le journal du récepteur et dans Grafana. Il faut aller la lire.
- **`sc-stockage`** : un compte système, un script, deux unités, un fichier dans `/etc/fichiers-metriques/`. Le service a le réseau, limité à l'adresse de Zot, et n'écrit que ce fichier.
- **Prometheus redémarre** : quelques secondes sans collecte, et les délais `for:` en cours peuvent repartir de zéro.
- **Zot** : 3 lectures anonymes toutes les 15 min. Leur volume dans son journal sera relevé, pas prédit.
- **`rejeu.sh`** : une étape ajoutée, pas rejouée. Les règles y sont déployées avant le scan : `ScanEnRetard` et `BaseGrypeVieillie` seront actives jusqu'à l'étape G8, ce qui est attendu.
- **Reconstruction de l'image** : le digest est figé dans `plateforme.sh`, comme pour le CronJob. Il faudrait relancer `g7_periodique` et `g8_metriques`. Entre les deux, l'alerte signalerait un scan absent, à raison.
- **Retrait** : arrêter et désactiver `fraicheur-scan.timer`, retirer ses unités, son script, son fichier et son compte, retirer les 3 règles, puis relancer `deployer`.

## Limites

- L'incident `a7` prouve la chaîne de la série à la notification, avec des séries vieillies. Il ne prouve pas la réaction à un vrai CronJob en échec : les tests hors ligne couvrent la lecture, et l'âge qui croît ensuite relève de la règle.
- L'alerte porte sur l'image `3a7ca1b1` seulement, comme le CronJob.
- Une annotation forgée par le détenteur de `poc-scan` tromperait l'alerte, pas la porte.

Aucun contrôle de `rejeu.sh`, `preuves.sh` ni `journalisation.sh` n'exige zéro alerte active ni un nombre fixe de notifications (recherche du 05/11/2026) : ces alertes actives pendant le rejeu ne le font pas échouer.

## Résultat

Pas encore exécuté.
