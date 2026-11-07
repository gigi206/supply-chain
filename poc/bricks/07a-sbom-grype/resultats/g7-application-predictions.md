# G7 de la brique 07a : prédictions de l'application

Écrites le 05/11/2026, 00:27 UTC, après `g7_sec` (conforme, un écart sur les dépôts vides : `g7-predictions.md`), avant toute application. Elles ne valent que pour l'ordre ci-dessous. Tout dépend d'un accord du propriétaire, qui n'est pas encore donné pour `g7_zot` ni pour `g7_periodique`.

État relevé en lecture seule le 05/11/2026 entre 00:04 et 00:27 UTC : 123 dépôts, 1 tag dans `vulndb/grype` (`2026-11-04`), 1 referrer dans `builds/scan/sample-app`, 2 dans `builds/vsa/sample-app`, 2 830 Mo dans `/var/lib/zot`, 9 588 Mo libres sur `sc-stockage`, 5 834 Mo libres sur `sc-confiance`. Le timer `base-grype` passera à 08:01:55 UTC et ajoutera le tag `2026-11-05` : toute prédiction sur les tags dépend de l'heure du passage et le dit.

## 1. `g7_zot` (accord)

- `storage` en service identique à `zot.json`. Binaire inchangé (Zot 2.1.22, empreinte revérifiée), mots de passe inchangés, hachages bcrypt refaits par l'étape `zot` de `stockage.sh`.
- Zot répond en moins de 60 s.
- Lectures identiques avant et après : image, `.sig`, `.att` à 200, mêmes referrers, mêmes tags.
- Le CronJob `horodatage` réussit au moins deux passages après le redémarrage. Un passage peut échouer pendant la coupure : effectif relevé, pas prédit.

## 2. `g7_balayage`

- Tous les dépôts du catalogue balayés, en 30 à 40 min.
- **0 décision de suppression** dans le journal : aucun manifeste n'a 14 jours : le plus ancien blob du store date du 03/11, 20:34 UTC, et le plus ancien de `builds/scan/**` du 04/11, 19:26 UTC.
- **2 dépôts vides disparaissent** du catalogue : `horodatage/essais` et `horodatage/essais-test8/aucun-20261103t215715z`, sans aucune décision journalisée, comme dans `g7_sec`. Soit 121 dépôts au lieu de 123, si rien n'en crée entre-temps.
- `/var/lib/zot` à 2 830 Mo, à 20 Mo près, plus 190 Mo environ si le timer de 08:01 UTC est passé. La mesure de `g7_sec` ne laisse aucune place à des blobs orphelins de volume notable : les 190 Mo retirés correspondent à la seule base du 04/11.
- `builds/scan/essai-scan` reste : ses manifestes ont moins de 14 jours.

## 3. `g7_retention` (lecture)

- Au moins une ligne `"decision":"keep"` sur `vulndb/grype` visible dans Grafana, de raison `retained by … policy`. **Déduit du code, jamais observé** : la raison relevée dans l'audit de `g7_sec` (`didn't meet any tag retention rule`, soit `filteredByTagRules`) n'existe que dans `GetRetainedTagsFromMetaDB`, et cette fonction appelle `logAction(repo, "keep", …, &p.log)` pour chaque tag gardé. Si la ligne manque alors que le journal de `zot.service` la porte, c'est la requête qui est fausse, pas la rétention.
- 0 suppression dans l'audit de Zot, mot de passe de `poc-scan` absent.

## 4. `g7_periodique` (accord)

- CronJob `scan-sample-app`, `30 9 * * *`, `Etc/UTC`, `Forbid`. Il n'existait aucun autre CronJob dans l'espace `scan`.
- `g7-manuel` réussit, comme G4 : référence de la base résolue en digest, 5 vulnérabilités, 0 KEV avec la base du 04/11. Une base plus récente peut changer ce compte, et seule la signature fait foi. Durée d'analyse de l'ordre de 2 min.
- Exactement un referrer de plus qu'avant le passage, sujet égal au digest de l'image, bundle vérifié sur l'hôte avec la clé du scanner. L'étape attend 10:00 UTC si elle tombe entre 09:00 et 10:00 UTC. Je n'ai pas vérifié si `Forbid` voit un job lancé par `--from`, et cette attente rend la question sans objet.
- Place libre la plus basse sur `sc-confiance` : environ 2 400 Mo (5 834 Mo moins les 3 411 Mo du volume). G4 avait relevé 2 505 Mo.

## 5. `g7_grafana` (lecture, sous l'accord de `g7_periodique`)

Seule écriture : la suppression de `g7-manuel` à la fin. Marqueurs `SOURCE`, `BASE`, `SCAN`, `ATTESTATION`, `PUBLIE` et révocation du jeton lus par l'auditeur, signature `transit/sign/scanner` et poussage de `poc-scan` visibles, identifiants absents. Scindée ce jour : la partie rétention est passée à `g7_retention`, et `rejeu.sh` ne l'appelle pas.

## 6. `preuves.sh controle7` de la 08 (accord)

**Ajouté à G7 : `5649c38` a changé C1 sans jamais le rejouer.** Aucune VSA poussée, mais ce n'est pas une lecture : l'étape réapplique la ConfigMap `porte` (identique), crée puis retire `porte-temoin`, et crée trois Jobs dans l'espace `porte`.

- C1 image réelle admise : `ok|2 énoncé(s) vérifié(s) dans …/builds/scan/sample-app`, le scan le plus récent retenu, contrôles 6 et 9 inchangés.
- C2 refus `scan.scan_present`, C3 refus par signature.
- 0 écart.

Le journal réécrit `08-trust-plane/resultats/preuves-controle7.log` ; il sera copié en `g7-controle7.log`, avec l'ancien conservé par l'historique git.

## Hors d'atteinte de ce jalon

- **Effacement réel.** Rien ne sera effacé avant le 18 novembre à 19:26 UTC, 14 jours après le plus ancien blob de `builds/scan/**`, puis au balayage suivant : `gcInterval` vaut 24 h, donc le 18 ou le 19 novembre. D'ici là, seules les preuves à sec tiennent lieu de mesure.
- **Rejeu de zéro.** `rejeu.sh` n'est pas rejoué : le scan et les témoins y sont ajoutés (`5649c38`), sans essai.
- **Passage planifié.** `g7-manuel` part du CronJob à la main ; le premier passage réellement planifié aura lieu à 09:30 UTC le jour suivant et devra être relu à part.

## Additif du 05/11/2026, 08:24 UTC, avant `g7_periodique`

**Décision du propriétaire, D10 (05/11/2026, « A »)** : CronJob quotidien à 09:30 UTC, recommandé par l'advisor et par moi. `g7_zot` est passée à 08:18 UTC, et le balayage suit son cours.

**Corrections de la section « Hors d'atteinte ».** J'y écrivais que le premier passage planifié aurait lieu « le jour suivant ». C'est faux si le CronJob existe avant 09:30 UTC :

- `g7_periodique` lancé avant 09:00 UTC : passage planifié **aujourd'hui à 09:30 UTC**, un referrer de plus (3 au total) ;
- `g7_periodique` lancé entre 09:00 et 10:00 UTC : l'étape attend 10:00 UTC, et le premier passage planifié a lieu demain à 09:30 UTC.

**Prédictions du premier passage planifié**, à relire à part : un Job `scan-sample-app-…` réussi, 1 Job au plus à la fois, base du 05/11, place libre la plus basse sur `sc-confiance` de l'ordre de 2 400 Mo, comme `g7-manuel`.

**`controle7`** est tenu hors de 09:25 à 09:40 UTC : un scan publié entre le jugement et le compte des referrers fausserait la valeur attendue de C1, sans rien dire de la porte.

## Résultat

Application du 05/11/2026, 08:18 à 08:53 UTC, accords du propriétaire (« 2 oui », « 4 oui », « A » pour D10), toutes les étapes du premier coup, codes 0.

| Étape | Prédiction | Mesure | Verdict |
|---|---|---|---|
| `g7_zot` | `storage` identique à `zot.json`, réponse en moins de 60 s, lectures inchangées | Empreinte identique, réponse en 1 s, 3 × 200, 1 et 2 referrers, 123 dépôts | Conforme |
| `g7_zot` | 2 passages d'horodatage réussis, échec éventuel relevé | Réussis ; 5 Jobs visibles, tous complets, aucun en échec. Historique limité : cela n'exclut pas tout à fait un échec | Conforme |
| `g7_balayage` | Tous les dépôts, 30 à 40 min | 123 dépôts, du 08:18:39 à 08:48:30 UTC, soit 30 min | Conforme |
| `g7_balayage` | 0 décision de suppression | 0 | Conforme |
| `g7_balayage` | 121 dépôts au catalogue | 121 | Conforme |
| `g7_balayage` | 2 830 Mo à 20 Mo près, plus 190 Mo environ après le timer | 3 019 Mo | Conforme |
| `g7_retention` | Au moins une ligne `keep`, lue dans Grafana | 2 lignes, `retained by mostRecentlyPushedCount:11 policy`, une par tag | Conforme, première observation de ce format |
| `g7_periodique` | CronJob `30 9 * * *`, `Etc/UTC`, `Forbid` | Conforme | Conforme |
| `g7_periodique` | `g7-manuel` réussi, 5 vulnérabilités, 0 KEV, analyse de l'ordre de 2 min, base la plus récente | 5, 0 KEV, 100 s, base du 05/11 construite à 06:21 UTC | Conforme |
| `g7_periodique` | Un referrer de plus, sujet correct, bundle vérifié | 2 referrers, sujet et bundle corrects | Conforme |
| `g7_periodique` | Place libre la plus basse : environ 2 400 Mo | **2 168 Mo** | **Écart de 230 Mo environ** |
| `g7_grafana` | Marqueurs, signature, poussage visibles, identifiants absents | Conforme | Conforme |
| `controle7` | C1 admise avec 2 énoncés, C2 et C3 refusés, 0 écart | `2 énoncé(s) vérifié(s)`, `scan.scan_present`, signature refusée, 0 écart | Conforme |

**Écart de place libre.** J'ai soustrait le volume de 3 413 Mo aux 5 834 Mo relevés à 00:26 UTC. La différence, environ 230 Mo, tient à la place perdue par le nœud entre 00:26 et 08:50 UTC : voir « Place sur `sc-confiance` » plus bas.

**Ce que `controle7` ne montre pas.** Le journal liste les deux énoncés lus (`LU|…`), pas celui que les règles ont retenu. Le choix du plus récent reste couvert par les tests de la règle (G5), non par cette exécution.

**Ce que le balayage ne montre pas.** Rien n'a été effacé, seuls deux dépôts vides ont disparu. Le 05/11, les règles de suppression n'ont encore rien eu à faire sur le vrai store.

**Premier passage planifié, 05/11/2026, 09:30:00 à 09:31:49 UTC** ([relevé](g7-premier-passage-planifie.log), par un [script en lecture seule](g7-premier-passage-planifie.sh) hors de `plateforme.sh`) : conforme à l'additif, sauf la place libre. Job `scan-sample-app-29897850` réussi, 1 Job à la fois, base du 05/11, 5 vulnérabilités, 0 KEV, 100 s d'analyse, 3 referrers, journaux visibles par l'auditeur dans Grafana. Place libre la plus basse : 2 161 Mo, soit le même niveau que `g7-manuel` (2 168 Mo). L'écart de 230 Mo à ma prédiction se retrouve sur les deux passages ; il est expliqué ci-dessous.

## Place sur `sc-confiance` (mesure du 05/11/2026, 09:34 UTC, lecture seule)

L'écart ne vient pas du scan : au repos, le nœud a 5 572 Mo libres, et 5 572 − 3 413 = 2 159 Mo, soit le creux mesuré à 2 161 Mo. **C'est le nœud qui perd de la place**, 262 Mo en 9 h 08 depuis 00:26 UTC, soit 29 Mo/h ou 690 Mo par jour à ce rythme.

| Poste | Mesuré | Plafond | Reste à venir |
|---|---|---|---|
| Audit de l'API k3s | 641 Mo, 100 Mo toutes les 6 h environ, soit 17,5 Mo/h | `audit-log-maxbackup=10` : environ 1 100 Mo | Environ 460 Mo, atteints en un peu plus d'un jour |
| journald | 160 Mo, environ 5,5 Mo/h d'après deux archives de 25 Mo | 282,5 Mo, annoncé par journald | Environ 120 Mo |
| Reste | Environ 6 Mo/h, **non attribués** ; peut venir des Jobs ponctuels de la nuit et du matin | Inconnu | Inconnu |

Seuils relus par `configz` : éviction à `nodefs.available` 5 %, soit 745 Mo sur 14 915 Mo ; image GC au-delà de 85 % d'occupation, soit moins de 2 237 Mo libres. **Le creux du scan franchit déjà ce second seuil** (85,5 %), le temps de 2 min environ. `DiskPressure` reste à False depuis le 03/11, aucun événement d'éviction ni d'image GC relevé.

**Projection, pas une mesure.** Une fois audit et journald plafonnés, le creux du scan serait d'environ 1 580 Mo, 835 Mo au-dessus de l'éviction. Si les 6 Mo/h résiduels persistent, ces 835 Mo tiennent environ 6 jours après le plafond, donc jusque vers le 12 novembre. S'ils ne persistent pas, le creux reste stable. Prédiction vérifiable : **creux de 1 400 à 1 600 Mo au passage du 06/11 à 09:30 UTC**.

Une éviction toucherait d'abord le pod de scan, plus gros consommateur de stockage éphémère, et l'image GC peut libérer de la place avant elle, effet non mesuré. Ce nœud porte aussi OpenBao. L'audit de l'API est déjà copié dans Loki (`audit-k8s.alloy`).

**Point à suivre, aussi** : en régime établi, le dépôt de scans compte environ 14 énoncés et non 2. L'effet sur la durée de la porte n'est pas mesuré.

## Additif : relevé du 06/11/2026 (06/11/2026, 10:00 UTC, [journal](g7-passage-2026-11-06.log))

Passage planifié de 09:30 UTC réussi en 2 min 06. Creux de 1 645 Mo à l'échantillonneur, 1 663 Mo au script, contre 2 161 Mo le 05/11 ; 900 Mo au-dessus de l'éviction, 745 Mo ; image GC franchi environ 1 min.

| Prédiction du 05/11 | Mesuré | Verdict |
|---|---|---|
| Creux de 1 400 à 1 600 Mo | 1 645 Mo | Non tenue, de 45 Mo, sens favorable |
| Audit à 1 100 Mo au plus | 1 045 Mo | Tenue à ce jour, plafond pas encore éprouvé |
| journald plafonné à 282 Mo | 244 Mo | Tenue à ce jour, plafond pas encore éprouvé |
| Reste d'environ 6 Mo/h | 0,04 Mo/h sur 24 h | Non retrouvé |

**Projection, pas une mesure** : creux d'environ 1 552 Mo une fois les plafonds atteints, 807 Mo au-dessus de l'éviction. **Jamais mesuré sous k3s** : le plafond d'audit. Le rejeu RKE2, lancé sur accord du propriétaire, retire ce cluster avant la rotation de 12:50 UTC. Décision sur le disque : aucune, recommandation « ne rien faire », `sc-confiance` passant à 25 Go sous RKE2 (D3 de la 08b).

## Additif du 07/11/2026, 19:56 UTC : le plafond de journald de 282 Mo ne vaut que jusqu'au premier redémarrage

Revue statique menée sur « continue », sans validation du propriétaire. Rien n'a été lu ni écrit dans les VM. Base : [revue-journald-stockage.log](../../08c-durcissement/resultats/revue-journald-stockage.log) de la 08c.

D'après le source de systemd v257.13, journald calcule son plafond une seule fois, au démarrage du processus, à 10 % du système de fichiers.
- Au premier démarrage d'une VM neuve, la racine de l'image n'est pas encore agrandie (2,874 GiB). Le plafond vaut alors environ 290 Mo, du même ordre que les 282,5 Mo annoncés sous k3s le 05/11.
- Après un redémarrage, il passe à 10 % du disque. `sc-confiance` est redémarrée depuis le 07/11 à 11:22 UTC et a désormais 25 Go sous RKE2 : journald peut donc y occuper jusqu'à environ 2,5 Go, sous réserve de garder 5 % de place libre (précisé à 19:59 UTC, avant tout push).

Le poste « journald plafonné à 282 Mo » de la projection ne vaut donc plus sous RKE2. Lecture tirée du source, non observée. Aucune note ne change.
