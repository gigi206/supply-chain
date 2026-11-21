# 07b : CVE trouvées et failles réelles après VEX, carte préparée à sec (2026-11-20T21:53:35Z UTC)

**Rien n'est posé et aucun outil nouveau n'est retenu.** Cette carte prépare des choix du propriétaire. Aucun fichier de la 07a, de la porte ou du cluster n'est modifié.

## Demande

Verbatim du propriétaire, le 20/11/2026, après la comparaison avec Konflux et TPA ([additif de la 07a](../README.md), 2026-11-20T21:28:28Z) : « Il faudrait faire mieux, les cve trouvées et les failles réelles (VEX) ».

Lecture retenue, à confirmer : voir dans Grafana, pour chaque artefact, les vulnérabilités trouvées par le scan, puis celles qui restent après application des VEX.

## Ce qui existe, lu dans le dépôt

**Le scan signé garde déjà les CVE trouvées.**
- [`scan_predicate.py`](../scan_predicate.py) écrit le prédicat `https://supply-chain.example/scan/v1`. Pour chaque couple (vulnérabilité, PURL), il garde : `id`, `aliases`, `severity`, `kev`, `kevCves`, `epss`, `package` et `fixedIn`.
- Il ne lit que la liste `matches` du rapport de grype.
- Le champ `malicious` est toujours vide : le commentaire du code renvoie ce contrôle à « la brique 07b (2c) ».
- [`politique/scanner.sh`](../politique/scanner.sh) fusionne les SBOM (`sbom.json`), lance `grype -o json`, puis efface le SBOM.

**La porte attend un VEX qu'aucun scan n'écrit.**
- La règle `kev_without_vex` de [`politique/porte/scan.rego`](../politique/porte/scan.rego) lit `v.vex.status` et `v.vex.expires`.
- Aucun prédicat réel n'écrit `vex`. Seuls les témoins de G6 l'ajoutent, par `jq`, pour les cas « VEX expiré » et « VEX valide ».
- La 07a le dit : « Pas de VEX avant la 07b ». « KEV sans VEX » veut donc dire « aucune KEV ».

**Grafana ne montre aucune CVE.**
- Seule la fraîcheur du scan est surveillée : alertes `ScanEnRetard` et `ScanBientotRefuse`, et âge de la base, dans `19-observabilite/config/regles/alertes.yml`.
- Ces alertes lisent `fraicheur-scan.prom`. Ce fichier est écrit par un timer de sc-stockage (`07a-sbom-grype/systemd/fraicheur-scan.service`), qui lit Zot en anonyme. C'est le motif existant pour montrer des données de scan sans composant neuf.

**grype 0.104.1 (épinglé dans `mise.toml`) sait appliquer un VEX.** Lu dans l'aide et dans le code au tag, pas essayé.
- Option `--vex` : « a list of VEX documents to consider when producing scanning results ».
- Deux lecteurs : `grype/vex/openvex` et `grype/vex/csaf`.
- Les correspondances écartées vont dans `ignoredMatches` (`presenter/models/document.go`, sha256 `656c61ac8d5cbd74…`). Chacune porte ses règles appliquées, dont `vex-status` et `vex-justification` (`presenter/models/ignore.go`).
- « Trouvées » et « réelles » demandent donc les deux listes : `matches` et `ignoredMatches`.

**Ce que prévoient les documents.**
- `docs/01`, B6 : la porte bloque MAL- et KEV sans VEX ; un score informatif versionné ; briques 07a et 07b.
- `docs/02` :
  - SBOM, résultats de scan et VEX sont des attestations ;
  - le score v1 compte « 35 % vulnérabilités après VEX (CVSS × EPSS) » ;
  - les KPI 2c dérivent des attestations, dont la couverture VEX (`tools/metrics-exporter`, absent du dépôt) ;
  - Dependency-Track v5 est une projection reconstructible (2c) ;
  - l'ADR 0004 (« OpenVEX ou CSAF ») est prévu en phase 3.
- `docs/04`, ligne 133 : Dependency-Track v5 (« un seul mainteneur fusionne »), Trustify, GUAC, vexctl et malicious-packages sont « À surveiller, hors chemin critique ». Ligne 203 : le plan de sortie de Dependency-Track est la projection reconstructible.
- **Aucune estimation de la 07b** n'a été trouvée dans `docs/03` ni ailleurs. L'estimation ci-dessous est neuve.

## Incohérence à signaler

- L'ADR 0004 hésite entre OpenVEX et CSAF. Or, d'après `docs/00` (ligne 277), Dependency-Track ne lit « ni CSAF ni OpenVEX », seulement le VEX de CycloneDX. La projection prévue ne lirait donc pas les VEX dans aucun des deux formats envisagés.
- La porte exige une échéance `expires`. Que les formats OpenVEX ou CSAF en portent une n'a pas été lu.

## Découpage proposé

La demande est plus étroite que la 07b des documents. Trois tranches, chacune utile seule :

1. **CVE trouvées dans Grafana**, depuis les prédicats déjà signés. Ni VEX, ni outil nouveau, ni changement de la porte. Même motif que `fraicheur-scan` : un timer de sc-stockage lit le dernier prédicat de chaque artefact dans Zot en lecture anonyme, puis publie :
   - des comptes par gravité, par KEV et par présence d'un correctif ;
   - la liste par CVE.
   À décider : faut-il vérifier la signature du prédicat avant de l'afficher ?
2. **VEX à blanc**, sur un Zot et une clé jetables, comme G6. Rien dans le vrai Zot. Mesures :
   - `grype --vex` sur un SBOM de sample-app : `matches` contre `ignoredMatches` ;
   - le test négatif des PURL divergents, prévu par la 07a (modules Go ≥ v2) : un VEX écrit sur un format de PURL doit s'appliquer à l'autre.
3. **Prédicat et porte** : `scan_predicate.py` lit aussi `ignoredMatches` et remplit `vex` ; `scan.rego` et `scan_test.rego` suivent. C'est un changement de politique : accord du propriétaire.

**Hors de cette carte**, mais dans la 07b des documents : MAL- (champ `malicious` toujours vide), score, projection Dependency-Track, KPI de `tools/metrics-exporter`, ADR 0004.

## Choix du propriétaire, sans recommandation à ce stade

1. **Qui applique le VEX** :
   - le scanner (`grype --vex`), et le prédicat signé porte le résultat ;
   - ou la porte, qui lit des VEX en attestations séparées.
2. **Quelle clé signe un VEX** : celle du scanner, ou une clé distincte.
3. **D'où vient l'échéance `expires`** exigée par la porte, selon le format retenu.
4. **Quel format** : OpenVEX ou CSAF (ADR 0004), et l'écart avec Dependency-Track.
5. **Qui écrit « not_affected », et sur quelle preuve.** Aucun outil d'analyse d'atteignabilité n'a de ligne dans `docs/04`. Un VEX écrit pour la démonstration est un témoin, et doit être étiqueté comme tel.
6. **Tranche 1** : comptes dans Prometheus (faible cardinalité), ou liste par CVE dans Loki, ou les deux.

## Couplages

- **G7** : rien dans le vrai Zot avant la lecture du n°9, le 29/11 vers 05:40 UTC. La tranche 1 ne fait que lire Zot. Les tranches 2 et 3 restent jetables avant cette date.
- **sc-stockage** : si la liste par CVE va dans Loki, même couplage que J7 : disque dont le remplissage n'est pas expliqué, `df` du 21/11.
- **05, dossier 7 (D14)** : le scan du rpm dans la plateforme. Le scan du rpm seul de sample-app est vide : aucun module Go n'y est catalogué (`rpm-distro.sh`, note de 2026-11-20T19:03:57Z).
- **Porte et rejeu de la 08** : la tranche 3 change la porte, donc ce que rejoue `rejeu.sh`.

## Étapes

| # | Étape | Touche | Accord |
|---|---|---|---|
| 1 | Choix 1 à 6 | rien | **choix du propriétaire** |
| 2 | Tranche 1 à sec : lecture d'un prédicat réel dans Zot (anonyme), script et requêtes, banc local | rien | non (préparation) |
| 3 | Tranche 1, pose : timer sur sc-stockage, panneau Grafana | sc-stockage, Grafana | **oui** |
| 4 | Tranche 2 : Zot et clé jetables, `grype --vex`, PURL divergents | rien de partagé | lancement prévu |
| 5 | Tranche 3 à sec : prédicat, règles, tests `opa` | dépôt | non (préparation) |
| 6 | Tranche 3, pose : ConfigMap de la porte | porte | **oui** |

## Estimation (neuve)

10 h : 3 h pour la tranche 1, 3 h pour la tranche 2, 4 h pour la tranche 3. Décision avec le propriétaire à 20 h.

## Correction : la tranche 1 ne dépend que du choix 6 (note de 2026-11-20T22:18:38Z ; rien n'est réécrit au-dessus)

La carte bloquait à tort les trois tranches sur les six choix.
- **La tranche 1 ne dépend que du choix 6.**
- **Les choix 1 à 5 viennent après la tranche 2**, dont la mesure les éclaire. Ils ne sont pas posés avant.

**Choix 6, recommandation (conseiller) : les deux.**
- Les comptes vont dans Prometheus, par le motif de `fraicheur-scan`.
- La liste par CVE va dans Loki, jamais en labels Prometheus.

**Lectures faites depuis** :
- **Taille** : le prédicat archivé de G4 (`resultats/g4-scan-predicat.json`) a 6 vulnérabilités en 1422 octets de JSON compact (calcul). Le couplage de la liste avec le disque de sc-stockage serait de l'ordre de quelques Ko par scan. C'est à mesurer sur un prédicat réel récent ; le scan du binaire Go de la 06 avait 140 correspondances.
- **G7** : `zot.json` du dépôt n'a aucune règle de rétention par tirage. Un GET anonyme sur `builds/scan/*` ne change donc rien à ce que G7 mesure. Seuls `deleteReferrers` et `deleteUntagged` comptent.
- **Signature** : aucun script du dépôt n'installe cosign sur sc-stockage. Le seul `install … cosign` du dépôt vise la VM du rejeu indépendant (`10-independent-replay/replay.sh`). Sans installation, le panneau serait étiqueté « signature non vérifiée ici, la porte fait foi ». Ce n'est pas vérifié sur la VM.

## Tranche 1 à sec (note de 2026-11-21T16:27:54Z ; rien n'est réécrit au-dessus)

C'est l'étape 2 du tableau, une préparation sans accord, commencée à 16:20:22 UTC. **Rien n'est posé** : ni compte, ni timer, ni panneau. Les seules lectures sont Zot en anonyme depuis l'hôte, et Loki en comptes par l'auditeur. Le travail suit la recommandation du choix 6 (les deux), qui reste à confirmer.

**Lu avant d'écrire**
- **Prédicats réels.** `builds/scan/sample-app` a 10 referrers de scan, du 13/11 à 12:45:07 UTC au 21/11 à 09:32:00 UTC. `builds/scan/sample-app-deb` en a 6, le dernier du 21/11 à 11:17:01 UTC. Les énoncés les plus récents sont archivés comme témoins :
  - [sample-app](07b-t1-predicat-sample-app.json) : 1 713 octets compacts, 6 entrées ;
  - [deb](07b-t1-predicat-sample-app-deb.json) : 13 184 octets, 67 entrées.
- **Chemin vers Loki.** Le journal de sc-stockage y arrive déjà, par `19b-journalisation/config/alloy/commun/journal.alloy`, avec l'étiquette `unite`. Compte lu par l'auditeur : `fraicheur-scan.service` donne 4 lignes en 1 h et 96 en 24 h, une par passage.
- **Chemin vers Prometheus.** `19-observabilite/systemd/fichiers.py` sert tout `/etc/fichiers-metriques/*.prom`. Aucun nom `scan_entrees*` n'existe ailleurs dans le dépôt.

**Ce qui est écrit**, sans toucher à `fraicheur-scan.py` (contrôlé par G8, patché par S6a) :
- [`systemd/entrees-scan.py`](../systemd/entrees-scan.py) (`0b6d67187c0fd0f5…`), bibliothèque standard seulement. Pour chaque « dépôt@digest » de `SCANS`, il lit le referrer de scan le plus récent, son manifeste et son bundle.
  - **Contrôles sans signature** : type de la couche, empreinte du blob, `payloadType`, `predicateType` et sujet égal au digest demandé. Un écart donne le code 2, sans aucune écriture.
  - **Comptes** dans `entrees-scan.prom` : `scan_entrees{depot, gravite}` sur une grille fixe de 7 gravités, zéros écrits, dont « autre » pour une valeur hors grille. S'y ajoutent `scan_entrees_kev`, `scan_entrees_avec_correctif` et `scan_entrees_scanne_timestamp_seconds`, qui relie les comptes au scan lu. Cela fait 10 séries par dépôt.
  - **Liste** sur la sortie standard, donc dans le journal puis dans Loki : une ligne JSON par entrée, avec le dépôt et `scannedAt` dans la ligne, jamais en étiquette. Elle n'est émise qu'au premier passage qui voit un nouveau referrer : le digest du dernier manifeste émis est gardé dans `StateDirectory`. Les autres passages n'écrivent qu'une ligne de résumé.
- [`entrees-scan.service`](../systemd/entrees-scan.service) et [`.timer`](../systemd/entrees-scan.timer) : copiés sur `fraicheur-scan`, un passage toutes les 15 min. Les mêmes durcissements s'y ajoutent, avec `@SCANS@` rendu à la pose.

**Unité de compte : des entrées, pas des CVE.** Une entrée est un couple (identifiant, PURL) du prédicat. Pour sample-app, 3 entrées sur 6 ont un identifiant ou un alias CVE, et 2 sont en « Unknown ». Pour le deb, c'est 64 sur 67. Les séries et le futur panneau disent donc « entrées ».

**Banc** ([script](07b-t1-banc.sh), [cas](07b-t1-banc.py), [journal](07b-t1-banc.log)) : **0 KO, 26 contrôles tenus.**
- Les attendus sont calculés par jq, indépendamment du script :
  - sample-app : 6 entrées, 4 Medium et 2 Unknown ;
  - deb : 67 entrées, 3 Critical, 33 High, 28 Medium, 1 Low et 2 Unknown ;
  - témoin de G6 : 13 entrées, dont 2 KEV.
- **12 cas sur un faux Zot** :
  - les deux témoins réels, puis un second passage sans ligne d'entrée et aux comptes identiques ;
  - le témoin KEV de G6 et un prédicat vide (zéros partout) ;
  - un dépôt sans referrer (séries absentes, les autres écrites) ;
  - une lecture impossible (code 1, fichier inchangé) ;
  - cinq refus à code 2, fichier inchangé : sujet, `payloadType`, empreinte, type de couche et `predicateType` ;
  - une gravité hors grille, rangée dans « autre ».
- **Passage réel depuis l'hôte**, sortie hors dépôt, effacée :
  - les énoncés relus sont identiques aux témoins ;
  - 73 lignes d'entrée au premier passage, aucune au second ;
  - les 20 séries sont égales à jq.
- Le banc a été corrigé deux fois avant le journal archivé : `fromdate` de jq ne lit pas le décalage `+01:00` du témoin de G6, puis un chemin jq était faux. Ces erreurs venaient du banc. Le script n'a pas changé entre ces passages.

**Volume vers Loki** (mesure du passage réel, puis calculs) :
- **Une fois par scan**, comme écrit : 19 259 octets pour les deux listes et le résumé. S'y ajoutent 125 octets de résumé par passage, soit 12 000 octets par 24 h.
- **À chaque passage**, ce serait 96 × 19 259, soit environ 1,85 Mo par 24 h.
- Les deux restent faibles devant les 1,8 à 1,9 Gio envoyés chaque jour par Alloy (relevé `df` du 21/11).

**Résultat à donner au propriétaire, avec le choix 6.** Le deb porte 3 Critical et 33 High, toutes avec correctif, et aucune KEV. Les 67 entrées n'ont que 2 PURL distincts. sample-app porte 4 Medium et 2 Unknown, toutes avec correctif.

**Requêtes prévues pour le panneau, non essayées** (rien n'est encore écrit dans Prometheus ni dans Loki) :
- `sum by (depot, gravite) (scan_entrees)`, puis `scan_entrees_kev` et `scan_entrees_avec_correctif` ;
- `time() - scan_entrees_scanne_timestamp_seconds` pour l'âge du scan affiché ;
- `{source="journal", unite="entrees-scan.service"} |= "\"depot\"" | json` pour la liste, à filtrer sur le dernier `scannedAt`.

**Limites**
- **Signature non vérifiée ici.** cosign n'est pas sur sc-stockage. Le panneau dira « signature non vérifiée ici, la porte fait foi ». Un moyen de vérifier sur la VM, par installation ou par clé publique déposée, serait un choix à part.
- **Digests épinglés**, comme pour `fraicheur-scan` : une nouvelle image ne s'affiche pas sans nouveau rendu de `SCANS`.
- **Python de sc-stockage non relu.** `epoque` coupe les nanosecondes de `scannedAt`, que `fromisoformat` refuse avant Python 3.11. Le banc a tourné sous Python 3.13.12 de l'hôte. La version de la VM est à relire à la pose.
- Une lecture impossible laisse une trace Python au journal (code 1), comme `fraicheur-scan`.

**Pose, étape 3, sur accord à part** :
- sudo sur sc-stockage : compte système `entrees-scan`, script, unité rendue avec `SCANS`, `entrees-scan.prom` créé vide, et timer ;
- puis le panneau Grafana ;
- aucune écriture dans Zot. G7 n'est pas touché : la tranche ne fait que des GET anonymes.

## Complément à la tranche 1 (note de 2026-11-21T16:31:27Z ; la note de 2026-11-21T16:27:54Z n'est pas réécrite)

Relecture du conseiller. Quatre points.

**1. Noms de séries, lus dans le vrai Prometheus.** La note précédente ne les avait vérifiés que dans le dépôt, alors que l'incident a7 venait d'un fichier servi sur la VM. Lecture par l'auditeur dans Grafana :
- `count({__name__=~"scan_entrees.*"})` revient vide ;
- parmi les noms en `scan_`, seule `scan_dernier_referrer_timestamp_seconds` existe, avec 2 séries.

**2. Clé de jointure entre comptes et liste.** La série portait une époque en secondes, et la ligne une chaîne ISO à nanosecondes : une variable Grafana n'avait aucune clé commune pour les relier.
- Chaque ligne porte maintenant `scanne`, l'époque entière, égale à `scan_entrees_scanne_timestamp_seconds` du même dépôt. Le script passe à **`bdac36b853f845b3…`**.
- Le banc est relancé sous un autre nom ([journal 2](07b-t1-banc-2.log)) : **30 contrôles, 0 KO**. S'y ajoutent quatre contrôles :
  - `scanne` est égal à jq pour chaque ligne des deux témoins ;
  - il reste égal malgré le décalage `+01:00` du témoin de G6 ;
  - au passage réel, pour chacun des deux dépôts, une seule valeur de `scanne`, égale à sa série.
- La requête de liste devient `{source="journal", unite="entrees-scan.service"} | json | scanne = "$scanne"`. `$scanne` est une variable lue dans `scan_entrees_scanne_timestamp_seconds`. Elle n'est pas essayée.
- Le volume passe à **20 719 octets par émission**. À chaque passage, ce serait environ 1,99 Mo par 24 h (calcul). Les chiffres de la note précédente valent pour la version `0b6d6718…`.

**3. Sur quoi portent les entrées du deb.** Les 67 entrées n'ont que 2 PURL :
- `pkg:golang/stdlib@1.24.4` : 62 entrées, dont **les 3 Critical et les 33 High**, plus 25 Medium et 1 Low ;
- `pkg:golang/github.com/go-chi/chi@v5.2.3#v5` : 3 Medium et 2 Unknown.

sample-app porte `pkg:golang/stdlib@1.26.10`, avec une seule entrée. L'écart entre les deux vient donc de la version de la bibliothèque standard de Go vue dans chaque artefact. Son origine côté construction du deb n'est pas relue ici.

**4. Sous-point du choix 6 : quand émettre la liste.**
- Le volume ne départage pas : environ 33 Ko contre 1,99 Mo par 24 h, devant 1,8 à 1,9 Gio.
- **Une fois par scan**, comme écrit :
  - il y a un état à tenir (`StateDirectory`). Perdu au rejeu, il fait réémettre la liste une fois, sans dommage ;
  - le panneau doit remonter jusqu'au dernier scan. Si le scan prend du retard, les comptes restent, mais la liste sort d'une fenêtre courte.
- **À chaque passage** : aucun état, et la liste est toujours dans les 15 dernières minutes, mais en 96 copies par jour.
- **Recommandation : une fois par scan, avec une fenêtre de panneau de 7 jours.** C'est l'âge auquel la porte refuse un scan (D4, rappelé par l'alerte `ScanBientotRefuse`). Au-delà, la liste n'a plus d'objet pour la porte, et l'alerte a déjà sonné.

**Écart de méthode, dit franchement.** Les deux passages en échec du banc, décrits dans la note précédente, ont été écrits sous le même nom, `07b-t1-banc.log`, avant le premier commit. Seul le troisième passage y est archivé, et les deux premiers sont perdus. Le complément est journalisé sous un autre nom.

**Pour la pose, pas maintenant.** `SCANS` contient des `/`. Le `sed "s/@DIGEST@/…/"` de `g8_metriques`, copié tel quel, casserait. Il faudra changer de délimiteur, ou passer par un drop-in comme S6a.

## Choix 6 tranché, et pose préparée à sec (note de 2026-11-21T16:37:53Z ; rien n'est réécrit au-dessus)

**Décision du propriétaire**, le 21/11/2026, verbatim : « Les 2 ». L'option choisie disait : comptes dans Prometheus, liste dans Loki une fois par scan, et un panneau couvrant 7 jours.

**Écart avec l'option et avec l'étape 3 du tableau : pas de tableau de bord.** Le PoC n'en a aucun. `journalisation.sh` crée le dossier de provisionnement des tableaux de bord, mais le dépôt n'y dépose rien (seul `provisioning/datasources` existe). Toute la consultation passe aujourd'hui par l'exploration de Grafana, comme pour G8.
- La pose s'en tient à ce chemin : les requêtes de la note précédente, sur une fenêtre de 7 jours.
- Un tableau provisionné changerait la configuration de Grafana : ce serait un accord à part.

**Script de pose** [`entrees-scan.sh`](../entrees-scan.sh) (`595b9b664c9ba387…`), calqué sur `etape_g8_metriques`. Quatre étapes :
- **`sec`** : lecture seule, sans accord.
  - `SCANS` est relu dans l'unité `fraicheur-scan` en place, avec le drop-in de S6a : les mêmes artefacts.
  - Le rendu se fait par une substitution de bash, pas par `sed` (`SCANS` contient des `/`).
- **`pose`** : accord du propriétaire.
- **`verif`** : lecture seule, par l'auditeur.
  - Dans Prometheus, les séries sont comparées à jq sur les énoncés relus en anonyme.
  - Dans Loki, seuls des comptes sont lus : les lignes de chaque dépôt qui portent le `scanne` de son dernier scan.
- **`retrait`** : accord du propriétaire.

Les écritures sur la VM s'arrêtent d'elles-mêmes sur un échec : `set -e` ne joue plus sous `etape || rc`. Il n'y a aucun « rm -rf », seulement `find <chemin écrit> -delete`.

**`sec`, deux passages** :
- [premier journal](07b-t1-pose-sec.log) : **son « bilan : tenu » est faux**. Il porte un KO, 2 lignes rendues au lieu d'une, car le commentaire de l'unité contenait lui aussi le marqueur. Et `etape_sec` ne renvoyait pas son KO. Les deux défauts sont corrigés.
- [second journal](07b-t1-pose-sec-2.log) : tenu.
  - Une seule ligne rendue, avec les digests `3a7ca1b14dbf…` et `60f25f5c3fb5…`.
  - Sur sc-stockage : Python 3.13.5, et ni compte, ni `.prom`, ni timer `entrees-scan`.

**Forme des réponses de `verif`, éprouvée sur des séries existantes** (auditeur) :
- Les cadres de Prometheus portent `__name__` et `depot`, avec une époque en entier (`scan_dernier_referrer_timestamp_seconds`).
- Côté Loki, `| json` sur une ligne qui n'est pas du JSON la garde, avec `__error__="JSONParserErr"` : 4 lignes de `fraicheur-scan` en 1 h. Sans étiquette `depot`, une telle ligne est écartée par le filtre de `verif`.
- Si le compte Loki revient à 0 après la pose, il faudra d'abord vérifier la comparaison de `scanne`, qui se fait en chaîne.

**En-têtes** : « non posé » est retiré du script et de l'unité, qui seront installés tels quels. Le script passe à `01e733fdb4341fb5…`. Le banc est relancé sous un troisième nom ([journal 3](07b-t1-banc-3.log)) : **30 contrôles, 0 KO**.

**Rejeu.** `08-trust-plane/rejeu.sh` appelle `g8_metriques` et `s6a.sh fraicheur`, mais pas `entrees-scan`. Si M5b recrée sc-stockage, `entrees-scan` disparaît. La phrase de la note précédente, « perdu au rejeu, il fait réémettre la liste », supposait un branchement qui n'existe pas. Le brancher, après « 06 (S6a, fraicheur) » puisque `SCANS` y est lu, est un changement du rejeu, à proposer après la pose.

**« Une fois par scan » n'est prouvé sur la VM qu'au prochain scan**, le 22/11 vers 09:32 UTC pour sample-app et 11:17 UTC pour le deb, d'après les derniers referrers. Un second `verif` est prévu après, sans tâche planifiée.

**Pose, sur accord à part.** Elle comprend :
- sudo sur sc-stockage ;
- la création du compte système `entrees-scan` ;
- le script, l'unité rendue et le fichier `entrees-scan.prom` vide ;
- un timer toutes les 15 min, et un premier passage lancé tout de suite ;
- une lecture sudo du journal de l'unité : le résumé, et le nombre de lignes d'entrée (les lignes elles-mêmes ne sont pas archivées).

Aucune écriture dans Zot, ni dans Grafana, ni dans le cluster.

## Pose de la tranche 1 (note de 2026-11-21T16:41:07Z ; rien n'est réécrit au-dessus)

**Accord du propriétaire**, le 21/11/2026, verbatim : « Oui », en réponse à « Je pose entrees-scan sur sc-stockage ? ». La demande nommait le sudo, le compte système, le timer et la lecture sudo du journal.

**Pose**, de 16:38:35 à 16:38:37 UTC ([journal](07b-t1-pose.log)) : **tenue**.
- Le script installé est identique, `01e733fd…`. Le premier passage se termine en `success`, et le timer est actif.
- Au journal : 73 lignes d'entrée, et le résumé `sample-app=6`, `sample-app-deb=67`.
- 20 séries sont écrites.
- `systemd-analyze security` donne 2,9, comme `fraicheur-scan`.

**Vérification par l'auditeur dans Grafana.**
- [Premier journal](07b-t1-verif.log) : **KO, mais l'erreur venait de la requête de `verif`**, pas de la pose.
  - Elle demandait `a or b or c or d`. En PromQL, `or` écarte les séries de droite dont les étiquettes sont déjà à gauche, sans tenir compte du nom. `scan_entrees_avec_correctif` et `scan_entrees_scanne_timestamp_seconds` ont les mêmes étiquettes que `scan_entrees_kev` : il manquait donc 4 séries sur 20.
  - Un `count by (__name__)` sur `{__name__=~"scan_entrees.*"}` en trouve bien 14, 2, 2 et 2.
  - La requête passe à un sélecteur sur `__name__` (`entrees-scan.sh` `5beedbca6627e3e7…`).
- [Second journal](07b-t1-verif-2.log), à 16:40:30 UTC : **tenu**.
  - Prometheus a 20 séries, égales à jq sur les énoncés relus en anonyme, dépôt par dépôt.
  - Loki a 6 et 67 lignes, celles du `scanne` du dernier scan de chaque dépôt : la jointure marche dans Grafana.

**Deux passages dès la pose.** Le `start` de l'étape, puis le timer, parti à son activation puisque `OnBootSec` était déjà dépassé, à 16:38:36 UTC. Comptes dans Loki, par l'auditeur, sur 24 h :
- 1 résumé avec « liste émise » et 1 sans ;
- 73 lignes d'entrée au total.

Le second passage n'a donc rien réémis pour le même referrer : c'est un premier constat, sur la VM, de « une fois par scan ». L'émission sur un **nouveau** scan reste à voir après ceux du 22/11, vers 09:32 et 11:17 UTC, avec un second `verif`.

**Reste ouvert** : le branchement au rejeu (`rejeu.sh`), et un tableau de bord, qui serait un accord à part.

## Tranche 2 : VEX à blanc (note de 2026-11-21T17:00:50Z ; rien n'est réécrit au-dessus)

**Lancée sans accord à part** (étape 4, « lancement prévu »). Heures mesurées : de 16:45:51 UTC (premier relevé) à 16:59:33 UTC (fin du dernier passage), pour 3 h estimées.

**Rien de partagé** :
- Grype hors réseau (`unshare -rn`).
- Zot et clés jetables sur 127.0.0.1, dans un espace de noms réseau vide, comme G6. Aucun appel au vrai Zot, à cause de G7.
- La base de G0 et l'image archivée sont lues sans modification : l'empreinte de leur listage est la même avant et après.

**Pièces** : le banc [`07b-t2-banc.sh`](07b-t2-banc.sh) (`4164579e17cc15e7…`), le générateur de témoins [`07b-t2-vex.py`](07b-t2-vex.py) (`19ea69ba02cae54a…`), et les [prédictions](07b-t2-predictions.md), écrites avant chaque passage.

**Portée** :
- La base de G0 (v6.1.10, construite le 04/11) donne 5 correspondances sur chi, pas les 6 du scan signé actuel.
- Le VEX porte sur `GHSA-mqqf-5wvp-8fh8`, une Medium hors KEV. La règle KEV de la porte n'est donc pas exercée.
- Tous les VEX sont des **témoins** : aucune analyse d'atteignabilité ne les fonde (choix 5).

**Cinq passages**, journaux jamais réécrits :

| Journal | OK | KO | Ce qui change |
|---|---|---|---|
| [1](07b-t2-banc.log) | 20 | 4 | Premier passage. |
| [2](07b-t2-banc-2.log) | 26 | 3 | Cinq cas ajoutés pour situer le produit et l'alias. |
| [3](07b-t2-banc-3.log) | 27 | 3 | Défaut du banc corrigé. |
| [4](07b-t2-banc-4.log) | 36 | 6 | Douze cas ajoutés après relecture du conseiller. |
| [5](07b-t2-banc-5.log) | 36 | 6 | Mêmes verdicts ; seule la coupe des messages d'erreur change. |

**Défauts du banc, dits franchement** :
- Au journal 1, le KO « image poussée » vient du banc. Le digest était écrit par un chemin relatif, et un fichier `image-poussee` s'est retrouvé à la racine du dépôt. Il contenait le bon digest, et il a été effacé.
- Aux journaux 1 et 2, le verdict « OK sbom-composant : refus » **ne mesure rien**. Le SBOM d'entrée portait le même nom que la sortie de Grype, et la redirection le vidait avant sa lecture.

**Constats, d'après le journal 5.** Les 6 écarts aux prédictions sont les cas `autre-digest`, `autre-nom`, `alias-cve` et les trois `reg-autre-*`.

1. **L'entrée du scanner de la plateforme refuse `--vex`.** C'est le SBOM CycloneDX fusionné, passé par `grype sbom:` : Grype répond `source type not supported for VEX`, et le refus est le même quand `metadata.component` est de type `application`. `--vex` est accepté :
   - quand ce composant est de type `container`, car le SBOM est alors lu comme une source `image` ;
   - sur un SBOM syft-json d'image ;
   - sur l'image elle-même.
2. **Le produit n'est vérifié que si la source porte un `repoDigest`.**
   - Avec une source `registry:` (le Zot jetable), le bon produit s'applique : `pkg:oci/…` avec sous-composant, ou la référence nue sans sous-composant. Un autre digest, un autre nom ou un texte quelconque ne s'appliquent pas.
   - Sur l'`oci-dir`, qui n'a ni tag ni `repoDigest`, et sur le SBOM à composant `container`, **n'importe quel produit s'applique**, même `n-importe-quoi` sans sous-composant.
   - Sur ces deux sources, la portée d'un VEX ne tient donc qu'à la vulnérabilité et au sous-composant.
3. **Le sous-composant (PURL)** :
   - la version est comparée : un VEX écrit pour `v5.2.2` ne s'applique pas ;
   - le subpath `#v5` est ignoré ;
   - un PURL sans version vaut pour toutes les versions.
   - **Le test négatif de la 07a est confirmé dans les deux sens.** La forme d'Hermeto (`…/chi/v5@v5.2.3?type=module`) ne s'applique pas à un SBOM de Syft. La forme de Syft ne s'applique pas à un SBOM où chi porte le PURL d'Hermeto. Chaque forme s'applique à elle-même.
   - Dans le sens inverse, seul le PURL a été changé, pas le nom du composant : seul le PURL d'Hermeto est archivé, pas son nom.
4. **La vulnérabilité** doit être l'identifiant que Grype affiche, ou figurer dans `aliases`. `CVE-2025-69725` seul en `name` ne s'applique pas à la correspondance `GHSA-mqqf-5wvp-8fh8`.
5. **Les statuts** :
   - `not_affected` et `fixed` passent dans `ignoredMatches`, avec `appliedIgnoreRules: [{namespace: "vex", vex-status: …}]` ; c'est la forme que lira la tranche 3 ;
   - `affected` et `under_investigation` restent dans `matches`.
6. **CSAF 2.0** : le format est reconnu, alors qu'un document `{}` est refusé (« unable to detect document format »). Mais le document est sans effet : 5 correspondances, 0 ignorée. La cause n'est pas établie.
7. **Zot et clé jetables.** Le VEX est signé en `attest-blob` (type `https://openvex.dev/ns/v0.2.0`), puis publié en referrer sous `builds/vex/sample-app`.
   - `verify-attestation` avec la clé jetable le relit : 1 énoncé, prédicat égal au VEX signé (`jq -S`). Rendu à Grype, il donne 4/1.
   - Avec une clé étrangère : refus, 0 énoncé.
   - Ce banc n'a pas de cas « autre sujet ». Le lien entre le sujet et l'image n'y est pas mesuré ; il l'est pour le scan, par le même mécanisme de cosign, dans `g6-autre-digest`.

**Ce que ces constats éclairent, sans recommandation.** Les choix 1 à 5 restent au propriétaire et ne sont pas posés ici.
- **Choix 1** : en l'état, le scanner ne peut pas appliquer de VEX. Il le pourrait si son SBOM portait un composant `container`, mais le produit n'y serait pas vérifié.
- **Choix 4** : le CSAF est sans effet dans cette version.
- **Choix 5** : un VEX doit être écrit sur le PURL et l'identifiant que Grype affiche.

## Corrections de la tranche 2, après relecture du conseiller (note de 2026-11-21T17:02:53Z ; la note de 2026-11-21T17:00:50Z n'est pas réécrite)

1. **Écarts : 7 aux prédictions d'origine, pas 6.** La prédiction aveugle de `sbom-composant` était « refus » (premier tableau des [prédictions](07b-t2-predictions.md)). Le banc attend 4/1 depuis le troisième passage, valeur fixée **après** une sonde, et le dit dans la section « Ajout avant le troisième passage ». Ce septième écart porte sur la forme qui compte pour le scanner : la prédiction aveugle tenait qu'un composant `container` ne changerait rien.
2. **CSAF, constat 6 et ligne « Choix 4 »** : « sans effet dans cette version » dit plus que la mesure. Celle-ci porte sur **un seul document témoin**, écrit à la main, non validé contre le schéma CSAF, et passé sur l'`oci-dir`. Elle montre qu'il est accepté sans erreur, mais sans effet, pour une cause non établie. Elle ne dit rien de la prise en charge du format CSAF par Grype.
3. **Prémisse du constat 1, vérifiée dans la source** : la fusion du scanner (`outil/main.go`, ligne 103, seule clé `metadata`) n'écrit que `metadata.tools`, sans `metadata.component`. Le SBOM que le scanner passe à Grype a donc la forme de `g0/sbom-ok.json`, refusée avec `--vex`. Seule la source est lue ici : l'image déployée du scanner n'est pas reconstruite.
4. **Deux formulations dépassent la mesure** :
   - « le subpath `#v5` est ignoré » : seul un VEX **sans** subpath a été essayé ; il s'applique au PURL à `#v5`. Aucun cas ne porte un autre subpath.
   - « le produit n'est vérifié que si la source porte un `repoDigest` » : c'est une corrélation sur trois sources (`registry:` avec `repoDigests`, `oci-dir` et SBOM à composant sans). La cause n'est pas isolée.

Le fragment de `docs/03` est corrigé dans les mêmes termes. Le message du commit de la note précédente garde « CSAF reconnu mais sans effet » et « 6 écarts » : un message de commit ne se réécrit pas, c'est cette note qui fait foi.

## Choix 1 à 5 : recommandations, relues par le conseiller (note de 2026-11-21T17:11:23Z ; rien n'est réécrit au-dessus)

**Faits vérifiés pour ces recommandations** :
- **Spécifications**, lues sur la branche `main` par un sous-agent ; le bloc `tracking` de CSAF n'a pas été lu en entier.
  - OpenVEX v0.2.0 n'a aucun champ d'échéance. Ses dates sont `timestamp` (émission du document ; pour un énoncé, l'heure où l'information était vraie), `last_updated` et `action_statement_timestamp`.
  - Pour `not_affected`, la spec est incohérente. Le tableau des champs exige `justification` **ou** `impact_statement` ; le tableau des statuts exige `justification`.
  - Pour `fixed`, la spec n'exige aucun champ propre.
  - CSAF 2.0 : aucun champ d'échéance lu. Les dates de `flags`, `remediations` et `threats` sont des dates d'évaluation ou de début.
- **Porte** : le seuil `vex_statuts_acceptes` vaut `not_affected` et `fixed` (`scan_test.rego`). La règle s'intitule « exceptions datées » et compare `v.vex.expires` à l'heure courante.
- **Scanner** : le deb passe par la même fusion que l'image (`scanner.sh`, `syft dir:` puis `scan-outil fusion`).
- **Cadence** : CronJob `scan-sample-app` à 09:30 UTC et `scan-sample-app-deb` à 11:15 UTC, une fois par jour (`kubectl get cronjob`, 21/11 à 17:10 UTC).
- **Clés Transit citées dans le dépôt** : `chains`, `lien`, `scanner` et `tsa`. Aucune clé VEX.
- **ADR 0004** : aucun fichier. `docs/00`, ligne 280 : « Source en OpenVEX signée et convertie », avec la réserve « Spec OpenVEX en brouillon v0.2 ».
- **Aucun outil d'atteignabilité** n'est évalué dans `docs/04`.
- **Sonde hors dépôt, hors réseau** (`t2-sonde/ignore-forme`, base de G0, 21/11 à 17:10:32 UTC). Sur une correspondance écartée, Grype n'écrit que `appliedIgnoreRules: [{namespace: "vex", vex-status}]`, sans justification, sans identifiant de document et sans horodatage. La liste des documents passés est écrite une seule fois, dans `descriptor.configuration.vex-documents`.

**Le choix 1 conditionne les choix 2, 3 et 5** : leurs recommandations ne valent que sous « le scanner applique ».

1. **Qui applique : le scanner** (`grype --vex`). Le prédicat signé porte `vex`, que la tranche 3 tire de `ignoredMatches`.
   - **Pour** : une seule logique de correspondance, celle de Grype, mesurée en tranche 2. La porte et Grafana en dérivent les mêmes listes : « trouvées » = `matches` + `ignoredMatches`, « réelles » = `matches`.
   - **Contre l'option porte** : Rego devrait refaire la correspondance des PURL (formes de Syft et d'Hermeto, versions) et des alias, au risque de diverger de Grafana.
   - **Limite, dite en clair** : la porte fait confiance au scanner pour le VEX. Un scanner compromis écrirait `vex` lui-même, ou tairait une correspondance.
   - **Atténuation** : le prédicat cite l'empreinte de chaque document VEX passé, pour qu'un auditeur puisse revérifier.
   - **Coût** : le SBOM fusionné doit porter un `metadata.component` de type `container`. Ce point n'est mesuré que sur l'image de sample-app, et le deb, qui porte les 3 Critical et 33 High, passe par la même fusion. Le produit n'y étant pas vérifié, la portée doit venir du sujet : le scanner ne passe à Grype que les VEX attestés sur le digest scanné.
   - **À mesurer en tranche 3**, pour l'image et pour le deb :
     - mêmes `matches` avant et après l'ajout du composant ;
     - un VEX attesté sur un autre digest n'est pas passé (cas « autre sujet », absent de la tranche 2).
   - **Délais** :
     - un VEX neuf ne compte qu'au scan suivant, soit jusqu'à environ 24 h ;
     - un VEX retiré reste effectif dans le prédicat jusqu'au scan suivant. La porte retient le scan le plus récent, recevable jusqu'à `scan_age_max_jours`.
   - **Prix de la portée par le sujet** : chaque nouveau digest (reconstruction) demande un nouveau VEX signé à la main. Sinon la porte bloque une KEV déjà exemptée.
2. **Quelle clé : une clé distincte** (par exemple `hashivault://vex` dans Transit), dont seul le propriétaire a l'usage.
   - **Ce qu'elle apporte** : qui peut écrire sous `builds/vex/` sans la clé ne peut pas faire exempter, et l'auteur humain est séparé de la tâche de scan.
   - **Ce qu'elle n'apporte pas**, sous le choix 1 : une protection contre un scanner compromis.
   - **Coût** : une clé et une politique OpenBao neuves. C'est un changement de configuration du cluster, sur accord.
3. **Échéance : la durée dans la politique, la date dans le VEX.**
   - Un seuil neuf `vex_age_max_jours` entre dans `policy-scan.yaml`.
   - Grype ne dit pas quel énoncé a écarté quelle correspondance. Le scanner écrit donc, pour toute correspondance écartée, l'horodatage **le plus ancien** des énoncés passés, sans refaire la correspondance.
   - La porte calcule l'échéance à partir de cet horodatage et du seuil.
   - Un horodatage postérieur à l'heure du scan est refusé. Il n'existe pas d'heure de signature de confiance : signing-config vide et `--insecure-ignore-tlog`.
   - **C'est un changement** : la règle passe d'une date par exception à une durée uniforme.
   - **Autre option** : une échéance propre à chaque exception, dans un champ hors spécification d'OpenVEX. Grype ne l'utiliserait pas, et la lecture de ce champ par le scanner n'est pas mesurée.
4. **Format : OpenVEX.** Il est mesuré de bout en bout : appliqué par Grype 0.104.1, signé, puis relu par `verify-attestation`.
   - L'ADR 0004 le noterait avec **CSAF non évalué** : un seul témoin non validé n'a eu aucun effet, pour une cause non établie.
   - Il garderait aussi la réserve « spec en brouillon v0.2 ».
   - L'écart avec Dependency-Track (VEX de CycloneDX seulement, d'après `docs/00` ligne 277, non revérifié) reste ouvert : la projection est hors de cette carte.
5. **Qui écrit : le propriétaire, à la main.**
   - Pour `not_affected`, le scanner exige **et** `justification` **et** `impact_statement`, sinon il ne passe pas le document. C'est plus strict que la spec, et nécessaire : Grype ne recopie pas la justification.
   - **`fixed`** est accepté par la porte et écarté par Grype comme `not_affected` (tranche 2), sans aucune preuve. Un `fixed` écrit à la main exempterait une KEV. Recommandation : **retirer `fixed` du seuil** de la porte, puisque la correction se voit au scan suivant, quand la version change.
   - Tout VEX de démonstration porte « témoin » dans `author` et ne vise aucune KEV réelle.
   - govulncheck pourrait fonder `vulnerable_code_not_in_execute_path` pour les modules Go, mais il faudrait d'abord l'évaluer dans `docs/04`. C'est une décision à part, hors de ces recommandations.

## Choix 1 à 5 tranchés (note de 2026-11-21T17:14:19Z ; rien n'est réécrit au-dessus)

Réponses du propriétaire, le 21/11/2026, aux questions posées après la note précédente. Elles suivent toutes la recommandation :

| Choix | Réponse (libellé choisi) | Ce qui en découle pour la tranche 3 |
|---|---|---|
| 1 | « Le scanner (Recommandé) » | `grype --vex` dans le scanner ; `metadata.component` de type `container` dans la fusion ; seuls les VEX attestés sur le digest scanné sont passés ; empreinte de chaque document passé dans le prédicat |
| 2 | « Clé distincte (Recommandé) » | clé Transit neuve et sa politique OpenBao : pose sur accord |
| 3 | « Durée dans la politique (Recommandé) » | seuil `vex_age_max_jours` ; horodatage le plus ancien des énoncés passés ; horodatage postérieur au scan refusé ; règle `kev_without_vex` réécrite |
| 4 | « OpenVEX (Recommandé) » | ADR 0004 à rédiger : OpenVEX, CSAF non évalué, spec en brouillon v0.2 |
| 5 | « Toi, à la main (Recommandé) » | `not_affected` passé seulement avec `justification` **et** `impact_statement` ; témoins étiquetés, aucune KEV réelle visée |
| 5, `fixed` | « Retirer fixed (Recommandé) » | seuil `vex_statuts_acceptes` réduit à `not_affected` |

**Suite** : la tranche 3 est préparée à sec (étape 5 : prédicat, règles, tests `opa`, mesures avant et après sur l'image et le deb, cas « autre sujet »). Sa pose (étape 6), la clé neuve et toute écriture dans le vrai Zot attendent chacune un accord. G7 interdit toute écriture dans le vrai Zot avant le 29/11.

## Tranche 3 à sec (note de 2026-11-21T17:44:18Z ; rien n'est réécrit au-dessus)

**Rien n'est posé.** Aucun fichier en service n'est modifié. La tranche 3 tient dans un patch, [`politique/07b-t3.patch`](../politique/07b-t3.patch) (`234d449aefb5507a…`), comme `g5-porte.patch`. Trois raisons à cette forme :
- `scan-outil` est figé dans l'image `outils-scan`, épinglée par digest dans le vrai Zot. La reconstruire est une écriture interdite par G7 avant le 29/11.
- `g4_scan` et `rejeu.sh` posent `scanner.sh` depuis le dépôt. Un `scanner.sh` neuf sur l'ancienne image casserait les scans quotidiens : `fusion` prend désormais l'image en sixième argument.
- La valeur de `vex_age_max_jours` n'est pas choisie.

**Heures mesurées** : de 17:18:18 UTC (première lecture) à 17:44:18 UTC, pour 4 h estimées.

**Mesure 0, avant toute écriture** ([script](07b-t3-mesure0.sh), [journal](07b-t3-mesure0.log), [prédictions](07b-t3-predictions.md) écrites avant). Entrées : l'image et le deb que scannent les deux CronJob, copiés depuis Zot en lecture anonyme ; la base de G0 ; Grype hors réseau, sans `--vex`.
- Avec ou sans `metadata.component` de type `container`, les prédicats sont identiques hors `scannedAt`, de même que les couples (id, PURL) : 5 pour l'image, 66 pour le deb.
- Grype lit alors la source comme `image` au lieu de `sbom-file`.
- 8 OK, 0 KO. Le choix 1 tient donc sur le deb comme sur l'image.

**Contenu du patch** (8 fichiers) :
- **`outil/main.go`** :
  - `fusion` écrit toujours le composant `container` (nom : dernier élément du dépôt ; version : digest) ;
  - un mode neuf, `vex`, revérifie chaque énoncé décodé : type in-toto, `predicateType` et `@context` OpenVEX v0.2.0, sujet égal au digest scanné. Il ne passe un document que si **tous** ses énoncés sont `not_affected`, avec une justification de la spécification, un `impact_statement` non vide et un horodatage lisible. Sinon il rejette le document entier, raison au journal ;
  - `predicat` lit aussi `ignoredMatches`. Une entrée écartée par une règle `vex` garde tous ses champs, dont `kev`, et reçoit `vex: {status, timestamp}`, avec l'horodatage le plus ancien des documents passés. Une entrée écartée par une autre règle reste ordinaire : seul un VEX exempte. Une entrée trouvée l'emporte sur une entrée écartée de même clé. Le prédicat porte `vex.documents`, empreintes des énoncés décodés à la manière de `scan-verifier.sh`, et le nombre de documents rejetés.
- **`politique/scanner.sh`** :
  - fonction `lire_vex` (et mode `vex`, pour le banc) : `cosign verify-attestation` avec la clé VEX sur `builds/vex/<nom>`, lu en anonyme. Sans VEX lisible, clé absente comprise, le scan se fait sans `--vex`. C'est la direction stricte, et le journal le dit (`VEX|…|cosign code …`) ;
  - un `--vex` par document.
- **Porte** :
  - `kev_without_vex` est réécrite : statut accepté, horodatage au plus 5 min après le scan, âge au plus `vex_age_max_jours` à l'heure du jugement ;
  - la forme vérifie `vex` quand il est présent (facultatif : les prédicats déjà signés restent recevables) ;
  - `vex_statuts_acceptes` est réduit à `not_affected`, et `vex_age_max_jours: null` refuse toute exemption tant que la valeur n'est pas choisie ;
  - 39 tests à heure simulée au lieu de 27, dont 16 sur le VEX au lieu de 4.
- **`plateforme.sh`** :
  - mutations de `g5_regles` ;
  - contre-épreuves de G5 (forme neuve, `fixed`, horodatage postérieur au scan, ancienne forme `expires`) ;
  - témoins de G6 datés d'après `vex_age_max_jours` ;
  - `cm_scan` monte `vex.pub` dès qu'elle existe.
- **`systemd/entrees-scan.py` et `entrees-scan.sh`** : `scan_entrees_vex` (même grille de gravités) et `scan_entrees_kev_vex`, de 20 à 36 séries. « Réelles » = trouvées - écartées, par soustraction dans Grafana. Ce sont les entrées que le scanner a écartées, pas celles que la porte admet. La ligne Loki porte `vex`.

**Banc** [`07b-t3-banc.sh`](07b-t3-banc.sh) (`4b51cc1bc17f5ad8…`), témoins [`07b-t3-vex.py`](07b-t3-vex.py) (`bb7fcf8c2fccf820…`). Le patch est appliqué à une copie des fichiers du dépôt, et ce sont ces copies qui tournent.
- **A.** Hôte, hors réseau : `scan-outil`, compatibilité avec la mesure 0, `ec opa check`, `ec opa test` et mutations, 15 cas unitaires de `vex`.
- **B.** Zot et clés jetables, dans un espace de noms réseau vide : le vrai `scanner.sh` du patch, en `analyser` complet (image puis deb, import de la base compris) et en mode `vex`, suivi des mêmes commandes qu'`analyser`.
- **C.** `ec validate input` sur les prédicats produits.
- **D.** `comptes` et `entrees` d'`entrees-scan.py`.

| Journal | OK | KO | Ce qui s'est passé |
|---|---|---|---|
| [1](07b-t3-banc.log) | 27 | 0 | Arrêt au début de B, défaut du banc : le nom du fichier de la base contient `:`, et `oras push` y lisait un type de média. Corrigé comme `fetch-db.sh`. |
| [2](07b-t3-banc-2.log) | 47 | 1 | **Passage interrompu par moi** : j'ai modifié le script du banc pendant qu'il tournait (ajout de la partie D). J'ai arrêté ses processus, pour que le shell principal ne lise pas le script à des positions décalées. Son KO est le même qu'au passage 3. |
| [3](07b-t3-banc-3.log) | 59 | 1 | **Défaut réel du patch** : `deux` sans prédicat (détail ci-dessous). |
| [4](07b-t3-banc-4.log) | 61 | 0 | Toutes les prédictions tenues. |

**Le défaut du passage 3.** Grype 0.104.1 sort en code 1, sans message sous `-q`, quand les VEX sont donnés en liste séparée par des virgules (`--vex a,b`). Avec `--vex a --vex b`, il donne 4/1. La sonde est hors dépôt et hors réseau, sur le SBOM et les deux documents du cas.
- En service, deux VEX sur un même artefact auraient fait échouer le scan, sans prédicat publié.
- Le patch et le banc passent désormais un `--vex` par document.
- Section « Ajout avant le quatrième passage » des prédictions.

**Constats du passage 4** :
1. Avec un VEX valide sur `GHSA-mqqf-5wvp-8fh8` :
   - l'image donne 4/1, et l'entrée porte `not_affected` avec l'horodatage du document ;
   - `vex.documents` est égal à l'empreinte de l'énoncé signé ;
   - le deb, avec un témoin sur `GO-2025-3849` (`pkg:golang/stdlib@1.24.4`), donne 65/1.
2. **Autre sujet** : aucun VEX n'est passé, et le scan donne 5/0, dans les deux variantes.
   - Dans la variante simple, le VEX est signé pour X et rattaché à X.
   - Dans la variante adverse, il est signé pour X et rattaché à Y. Zot sert bien ce referrer de Y, et c'est cosign qui le refuse.
   - Une autre clé (rôle de la clé du scanner) : rien n'est passé non plus.
3. **Statut `fixed` et `impact_statement` absent** : le document est vérifié par cosign, puis rejeté par le scanner, motif au journal. Le scan donne 5/0.
4. **Deux documents**, datés du 01/11 et du 20/11 : 4/1, et l'entrée porte le 01/11. C'est la conséquence voulue de « le plus ancien » : quand le plus vieux expire, l'exemption tombe.
5. **Clé VEX absente du conteneur** : cosign sort en code 1, aucun VEX n'est passé, le scan donne 5/0, et le journal le dit.
6. **VEX daté du futur** : le scanner le passe (4/1), et c'est la porte qui le refuse.
7. **Porte** (`ec` de l'hôte, validité de banc de 30 jours, entrée écartée passée en KEV par `jq`) :
   - l'image est admise ;
   - le VEX daté du futur, l'autre sujet adverse et la politique du patch telle quelle (`null`) sont refusés par `scan.kev_without_vex`.

**Limites, dites franchement** :
- `analyser` a tourné sur l'hôte : outils de mise et `ar`/`unxz` de l'hôte, pas l'image `outils-scan` (busybox), qui n'est pas reconstruite.
- Grype et la porte ont tourné ailleurs qu'en service :
  - la base est celle de G0 (04/11) ;
  - pour la porte, `scanner.db.built` est réécrit à l'heure du scan, sinon `base_recente` refuse ;
  - `ec` est celui de l'hôte (v0.10.42), pas celui de l'image de la porte.
- Aucune KEV réelle n'existe : la règle n'est exercée que par les tests `opa` et par une KEV posée par `jq`. Les prédicats signés du 21/11 n'en ont aucune (tranche 1 : 6 et 67 entrées, 0 KEV).
- Les contre-épreuves de G5 et les témoins de G6 du patch n'ont pas tourné : il leur faut le cluster. Seules les mutations de `g5_regles` ont tourné. Le filtre `jq` de la contre-épreuve « postérieur au scan » n'a été essayé que sur une entrée faite à la main.
- `entrees-scan.py` n'a été appelé que par ses fonctions, sans Zot ni VM, et l'étape `verif` du patch n'a pas tourné.
- Tous les VEX sont des témoins.

**La pose (étape 6) est plus large que la carte ne le disait** : « ConfigMap de la porte » ne suffit pas. Chaque pièce demande son accord :

| # | Pièce | Touche | Contrainte |
|---|---|---|---|
| 1 | Valeur de `vex_age_max_jours` | `policy-scan.yaml` | **choix du propriétaire** ; `null` dans le patch : aucune KEV exemptée |
| 2 | Clé Transit `vex` et sa politique OpenBao (usage réservé au propriétaire) ; clé publique prise hors bande dans `resultats/vex-cle-publique.pem` | OpenBao | changement de configuration du cluster |
| 3 | Image `outils-scan` reconstruite (scan-outil neuf) ; `OUTILS_SCAN_DIGEST` mis à jour | vrai Zot (`plateforme/outils-scan`) | **G7 : pas d'écriture avant le 29/11** |
| 4 | Dépôt `builds/vex/` dans Zot : lecture anonyme, compte d'écriture pour le propriétaire | `zot.json` de sc-stockage | idem G7 ; changement de configuration |
| 5 | `scan-config` avec `scanner.sh` neuf et `vex.pub` ; rendu des deux CronJob | espace `scan` | après 3 : un `scanner.sh` neuf sur l'ancienne image casse les scans quotidiens (`fusion` à 6 arguments) |
| 6 | ConfigMap de la porte (`scan.rego`, `policy-scan.yaml`) | porte | après 1 ; les prédicats déjà signés restent recevables (`vex` facultatif) |
| 7 | `entrees-scan.py` neuf sur sc-stockage | sc-stockage (sudo) | séries de 20 à 36 ; `verif` du patch |
| 8 | Premier VEX réel écrit et signé par le propriétaire | `builds/vex/` | aucune KEV réelle aujourd'hui sur sample-app (scan du 21/11) |
| 9 | `plateforme.sh` et `rejeu.sh` : `g5_regles`, contre-épreuves de G5, témoins de G6 | dépôt | les témoins de G6 lisent la valeur de 1 ; sans elle, `g6` s'arrête en KO |

**Question au propriétaire** : la valeur de `vex_age_max_jours` (choix 3). Rien n'est posé avant elle et avant l'accord de chaque pièce.

## Compléments de la tranche 3, après relecture du conseiller (note de 2026-11-21T17:51:53Z ; la note de 2026-11-21T17:44:18Z n'est pas réécrite)

1. **Passage 5** ([journal](07b-t3-banc-5.log) : 67 OK, 0 KO ; banc `5ec7f0a25f13b136…`, témoins `23249e05286b2bf7…`, même patch `234d449aefb5507a…`). Trois cas neufs, prédits avant le passage (section « Ajout avant le cinquième passage ») :
   - **Un document retenu par le filtre, mais sans `products` ou sans `vulnerability`** : Grype ne le refuse pas, l'énoncé est sans effet, 5/0.
     - Le risque visé : sous `set -e`, un document que Grype refuserait ferait échouer le scan entier, chaque jour, sans prédicat, jusqu'au refus de la porte par `scan_recent`.
     - Seules ces deux formes sont mesurées. Le patch n'a pas de repli « scan sans `--vex` si Grype refuse les VEX » : c'est une limite, à trancher avant la pose.
     - Un document sans effet compte pourtant dans `vex.documents` et dans l'horodatage le plus ancien : il peut avancer l'échéance des autres.
   - **La sonde du passage 3 est archivée** : `--vex a,b` donne le code 1 ; `--vex a --vex b` donne 4/1.
2. **Les refus de cosign sont distincts** (quatrième champ de la ligne `VEX|` des journaux de cas du passage 4, lus avant l'effacement du banc) :
   - autre sujet, simple : « no matching attestations » ;
   - autre sujet, adverse : « provided artifact digest does not match any digest in statement » ;
   - autre clé : « accepted signatures do not match threshold » ;
   - clé absente : « loading public key ».
   Dans le cas adverse, c'est donc cosign qui refuse : la revérification du sujet par `scan-outil vex` n'a tourné qu'en cas unitaire (`autre-sujet`).
3. **Un appelant de `scan-outil` est hors du patch** : `06-deb-sbuild/s6a.sh` (brique 06, close) appelle `fusion` à cinq arguments, avec le binaire du cache `~/.cache/supply-chain-poc/07a/outil/scan-outil`, que le patch ne reconstruit pas. Si ce script est rejoué avec un `scan-outil` neuf, il faudra lui ajouter l'image en sixième argument. Aucun autre appelant hors `resultats/` et hors worktrees.
4. **Environnement de cosign dans `analyser`** : `scan-job.yaml` lui donne `HOME=/travail` et `TMPDIR=/travail` (volume inscriptible), comme à `attester`. Le banc lui donnait aussi un `HOME` inscriptible. Ce n'est pas mesuré dans le pod : la pièce 5 de la pose commence par un pod d'essai.
5. **Portée de la mesure 0** : deux artefacts à modules Go (image et deb de sample-app), avec le SBOM source de G0. Rien n'est mesuré sur un artefact à paquets de distribution, comme le rpm du dossier 7 de la 05.
6. **Pièce 8 de la pose** : aucun script ni essai de signature avec `hashivault://vex`. Seul existe `publier_vex` du banc, avec une clé locale jetable.
7. **Deux écarts de méthode, de mon fait** :
   - j'ai lancé un `rm -rf` en clair sur un dossier `__pycache__` de la brique, qui existait avant la session ;
   - j'ai redaté les en-têtes des deux premières sections des [prédictions](07b-t3-predictions.md) (heures approchées remplacées par les heures mesurées) après les passages 1 et 2, sans toucher aux prédictions elles-mêmes.

**Valeur de `vex_age_max_jours`, sans recommandation** : aucune cadence propre aux VEX n'est écrite dans le dépôt. Une seule cadence de revue y figure : le ré-audit **trimestriel** des projets (`docs/01`, B13). Il porte sur la santé des projets, pas sur les VEX.
