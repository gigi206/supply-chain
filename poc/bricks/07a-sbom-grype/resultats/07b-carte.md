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
