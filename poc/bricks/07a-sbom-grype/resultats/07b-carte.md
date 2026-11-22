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

## Recommandation pour `vex_age_max_jours`, demandée par le propriétaire (note de 2026-11-21T20:08:57Z ; rien n'est modifié dans la politique)

Le propriétaire a demandé ce que recommande le conseiller. **Recommandation : 30 jours.** C'est un jugement, sans mesure qui le fonde. Le choix reste au propriétaire ; `policy-scan.yaml` garde `null` jusqu'à sa réponse.

- **Pourquoi pas 90 jours, la cadence de B13** : l'exemption porte sur une KEV, c'est-à-dire une faille exploitée. Elle repose sur une analyse écrite à la main, que personne d'autre ne relit. B13 concerne la santé des projets, pas les VEX.
- **Pourquoi pas 7 ou 14 jours** : un seul propriétaire renouvelle les VEX, à la main et sans script (pièce 8). Une fois l'échéance passée, la porte refuse. Une durée courte rend donc la porte bloquante à la première absence.
- **Portée réelle** : le VEX est attesté sur un digest, et toute reconstruction exige donc un VEX neuf. La durée ne limite que les digests qui restent longtemps en service.
- **Ce qui ne fonde pas ce chiffre** : les tests de `scan_test.rego` utilisent 30, mais c'était une valeur d'essai.
- **Alternatives** :
  - 90 jours, si l'on préfère la seule cadence écrite dans le dépôt et moins de re-signatures ;
  - 14 jours, si l'on accepte la corvée pour suivre de près les délais de remédiation des KEV.
- **Ancrage externe non retenu** : la BOD 22-01 de la CISA donnait deux semaines de remédiation pour les CVE attribuées à partir de 2021. Sa page indique qu'elle est révoquée et remplacée par la BOD 26-04, que je n'ai pas lue. Cet argument n'entre pas dans la recommandation.

**Limite trouvée en vérifiant, à lever avant la pièce 8 : on ne renouvelle pas un VEX en en ajoutant un.**
- La porte compte l'âge à partir de l'horodatage le plus ancien des documents retenus. C'est mesuré : dans le cas `deux` du banc, avec un document du 01/11 et un du 20/11, l'entrée porte 2026-11-01T00:00:00Z.
- Un VEX est un référent OCI publié par `cosign attest-blob`. La commande `cosign attest` v3.1.4 n'a pas d'option de remplacement (aucune ligne `replace` dans son aide).
- Pour renouveler, il faut donc retirer l'ancien référent de `builds/vex/<nom>`. Aucun script ni essai ne le fait aujourd'hui. Sans ce chemin, toute durée finit en refus à l'échéance.

**Délai de prise en compte** : un VEX renouvelé n'entre dans le prédicat qu'au scan quotidien suivant. Il faut donc re-signer au moins un jour avant l'échéance.

## Choix de `vex_age_max_jours` : 30 jours (note de 2026-11-21T20:13:42Z ; pièce 1 de la pose, dans le patch seulement)

**Choix du propriétaire, verbatim : « 30 ».** C'est la recommandation du conseiller (note précédente).

- **Seul le patch change** : la valeur `null` de `policy-scan.yaml` devient `30` dans la copie `b/` de `~/.cache/supply-chain-poc/07a/t3/`, et le commentaire est réécrit. Le patch est régénéré par `diff -ruN a b` (`e063abd2aedf18af…`, au lieu de `234d449aefb5507a…`). Aucun autre fichier du patch ne change.
- **Rien n'est posé** : la ConfigMap de la porte est la pièce 6, qui demande son propre accord.
- **Contrôles faits après la régénération** :
  - `git apply --check` passe sur l'arbre ;
  - `ec opa test` sur `b/` : 39/39 ;
  - la ligne lue par les témoins de G6 de `plateforme.sh` donne 30 ;
  - `yq` lit `vex_age_max_jours: 30` dans `ruleData`.
- **La porte avec 30 jours a déjà été mesurée** : la partie C du banc tournait avec une copie de la politique où `null` était remplacé par 30.
- **Le banc n'a pas été rejoué sur ce patch.** S'il l'était, ses lignes 308 et 309 ne trouveraient plus `null` : le cas « politique à `null` » jugerait 30 sans le dire. Il faudrait d'abord les adapter.
- **La limite de la note précédente vaut toujours** : le retrait d'un ancien VEX n'est pas outillé, et sans lui l'échéance de 30 jours finit en refus.

## Renouvellement d'un VEX : retrait de l'ancien référent mesuré au banc (note de 2026-11-21T20:24:29Z ; passage 6, rien posé)

La limite de la note de 20:08:57Z est mesurée au banc jetable. Les prédictions ont été écrites avant le passage (section « Ajout avant le sixième passage », 20:19:46 UTC).

**Passage 6** ([journal](07b-t3-banc-6.log)) :
- 82 OK, 0 KO, de 20:20:24 à 20:23:42 UTC ;
- même patch `e063abd2aedf18af…` ; banc `15854e0a16688c5c…` ;
- hors réseau ; Zot et clés jetables (`gc: false`, sans contrôle d'accès) ; rien dans le vrai Zot ni dans le cluster.

**1. Politiques de la partie C, corrigées.**
- La politique « 30 » est désormais celle du patch telle quelle. La politique « null » est fabriquée par le sed inverse.
- Chacune est contrôlée par `grep`.
- Les lignes 308 et 309 signalées dans la note de 20:13:42Z sont donc réglées.
- Porte, politique à `null` : code 1, `scan.kev_without_vex`, inchangé.

**2. Renouvellement par retrait.**
- Image `builds/renouv`.
- Deux documents sur son digest, dans `builds/vex/renouv` :
  - un ancien, daté 2026-10-01T00:00:00Z (plus de 30 jours) ;
  - un récent, daté de la veille.

| Étape | Référents | Journal `VEX|` | Grype | Horodatage de l'entrée | Porte à 30 jours |
|---|---|---|---|---|---|
| avant tout retrait | 2 | 2, 2, 0 | 4/1 | 2026-10-01T00:00:00Z | code 1, `scan.kev_without_vex` |
| après retrait de l'ancien (`oras manifest delete`, code 0) | 1 | 1, 1, 0 | 4/1 | 2026-11-20T20:20:34Z | code 0, admis |
| après retrait du dernier (contre-épreuve, code 0) | 0 | 0, 0, 0 | 5/0 | aucune | code 1, `scan.kev_without_vex` |

**Ce que cela établit** :
- Retirer le manifeste référent suffit. Cosign ne voit plus le document, et l'âge repart du document restant.
- Ajouter un VEX ne suffit pas, comme mesuré au cas `deux` et ici avant le retrait.
- Sans document, l'exemption disparaît : l'échec reste fermé.

**Limites** :
- Le code 0 d'`oras manifest delete --force` ne prouve rien seul : `--force` ignore aussi une référence absente. C'est le compte des référents (2, 1, puis 0) qui tranche.
- Le banc garde le digest du manifeste au moment de la publication. Dans la plateforme, rien ne le garde : il faudrait le retrouver par l'API referrers. Ce n'est pas mesuré.
- Vrai Zot : il faudrait un droit de suppression sur `builds/vex/**`, c'est-à-dire un changement de configuration, sur accord. Le ramasse-miettes et la rétention ne sont pas mesurés. Je n'ai pas lu sa configuration (secrets).
- Signature par `hashivault://vex` et délai du scan quotidien : non mesurés.

**Choix ouvert, au propriétaire** : retrait dans le registre (voie mesurée ici), ou règle de remplacement dans le filtre de `scan-outil`. La seconde voie n'est ni écrite ni mesurée ; elle modifierait le patch et la règle du choix 3 (âge compté depuis le document le plus ancien).

## Lectures avant le choix du renouvellement (note de 2026-11-21T20:28:00Z ; à sec, rien posé ; demandées par le conseiller)

**1. Rétention du vrai Zot pour `builds/vex/**`.** Source : le fichier versionné `08-trust-plane/stockage/zot.json`. La configuration déployée sur sc-stockage n'est pas relue.
- Aucune règle ne nomme `builds/vex`. Le dépôt relève donc de la règle fourre-tout `**` : `deleteReferrers: false`, `deleteUntagged: false`.
- Paramètres globaux : `gc: true`, `gcDelay` 1 h, `retention.delay` 336 h.
- Selon la lecture du code faite pour G7 (`g7-predictions.md`, « déduit, pas mesuré ») : un manifeste porteur d'un `subject` n'est retiré que par `deleteReferrers`. Un VEX publié resterait donc indéfiniment.
- Ce n'est pas mesuré : aucun VEX n'existe dans le vrai Zot, et le banc tourne avec `gc: false`.
- Contrôle d'accès versionné : `builds/**` donne `read`, `create` et `update`, et l'accès anonyme en lecture. Aucune action `delete` n'est donnée, à personne, dans aucun dépôt.
- Le retrait dans le vrai Zot demande donc d'ajouter un droit `delete`. C'est un changement de configuration, sur accord.

**2. Ce qui reste consultable d'un VEX retiré** (lu sur le prédicat du cas `complet` du passage 6 et dans `entrees-scan.py` du patch) :
- Prédicat :
  - `vex.documents` garde l'empreinte sha256 et l'horodatage de chaque document ;
  - chaque entrée écartée garde le statut et l'horodatage.
  - Ni la justification, ni l'`impact_statement`, ni le document lui-même ne sont gardés.
- `entrees-scan` (Loki, puis Grafana) : le même champ `vex`, soit le statut et l'horodatage.
- Les prédicats de `builds/scan/**` sont retirés après 336 h (`deleteReferrers: true`).
- Le document signé dans `builds/vex/**` est donc la seule copie de la justification. Le retrait l'efface, et il ne reste que l'empreinte. Où l'auteur garde ses VEX avant de les signer n'est pas décidé : la pièce 8 n'a pas de script.

**3. Spec OpenVEX v0.2.0** (lue le 21/11 sur `raw.githubusercontent.com/openvex/spec/v0.2.0/OPENVEX-SPEC.md`) :
- `version` doit être incrémenté à chaque changement du document.
- La spec ne dit pas qu'un document de même `@id` et de version supérieure remplace le précédent. Son propre exemple de mise à jour change même d'`@id`.
- La spec présente les VEX comme une suite d'énoncés : chacun remplace et complète les précédents.
- L'horodatage d'un énoncé l'emporte sur celui du document.
- Aucune règle explicite n'est donnée au consommateur.
- **Conséquence** : une règle de remplacement ne peut pas s'appuyer sur `@id` et `version`. Elle devrait porter sur le couple vulnérabilité et produit, et garder l'énoncé le plus récent. La règle du choix 3 compte l'âge depuis le document le plus ancien ; la spec, elle, décrit des énoncés qui remplacent les précédents.

## Vérifications avant la question du renouvellement (note de 2026-11-21T20:30:14Z ; à sec, rien posé)

1. **Droit `delete`, contrôle complet.** `accessControl` du `zot.json` versionné ne porte que `metrics` et `repositories`, sans `adminPolicy`. Les politiques par défaut et anonymes ne donnent que `read`. La note précédente tient : aucune action `delete` n'est donnée à personne.
2. **Granularité du filtre** (`main.go` du patch) :
   - Le filtre juge **des documents entiers**. Un seul énoncé autre que `not_affected` (ou sans justification, ou sans impact) fait rejeter tout le document.
   - L'horodatage d'un document est le plus ancien de ses énoncés.
   - L'horodatage porté par une entrée écartée est le plus ancien de **tous** les documents retenus, quelle que soit la vulnérabilité visée, car Grype ne dit pas quel énoncé a écarté quelle correspondance.
   - **Conséquences pour le renouvellement** :
     - Un ancien document qui vise d'autres vulnérabilités tire aussi l'échéance des autres.
     - Un document plus récent au statut `affected` (une rétractation) est aujourd'hui rejeté par le filtre. Il ne retire donc pas l'exemption de l'ancien `not_affected` : seuls le retrait ou l'échéance la font tomber.
   - Une règle de remplacement exigerait :
     - un horodatage par couple vulnérabilité et produit ;
     - le plus récent qui l'emporte quel que soit son statut ;
     - puis le filtre de recevabilité.
     C'est plus qu'un tri des documents.

**Heures mesurées de ce segment** : de 20:17:00 UTC (premier `date -u`, avant toute lecture) à 20:30:14 UTC. Cela couvre la correction du banc, les prédictions (20:19:46), le passage 6 (20:20:24 à 20:23:42), les notes de 20:24:29 et 20:28:00, la lecture de la spec et ces vérifications. Le total des heures de la 07b reste loin de 2× l'estimation de 10 h.

## Choix du renouvellement : remplacement dans `scan-outil` (note de 2026-11-21T20:39:16Z ; rien n'est encore écrit dans le patch)

**Choix du propriétaire, verbatim : « Remplacement ».** C'est la recommandation du conseiller, un jugement sans mesure.

- **Principe retenu** : pour un même couple vulnérabilité et produit, l'énoncé le plus récent l'emporte, quel que soit son statut. Le filtre de recevabilité ne s'applique qu'ensuite. Une rétractation (`affected` plus récent) fait donc tomber l'exemption.
- Le registre reste en ajout seul, et les anciens VEX restent comme trace. Aucun droit de suppression n'est demandé dans le vrai Zot.
- Le retrait mesuré au passage 6 n'est pas retenu. Sa mesure reste archivée.
- **Coût annoncé** : patch régénéré (nouvelle empreinte), un passage 7 du banc avec prédictions écrites avant, et la règle du choix 3 amendée dans l'ADR 0004.
- **Conception** : elle fait l'objet de la note suivante, écrite avant le code.

## Heures de la 07b : somme par enveloppes (note de 2026-11-21T20:42:26Z ; corrige la dernière phrase de la note de 20:30:14Z)

La phrase « Le total des heures de la 07b reste loin de 2× l'estimation de 10 h » a été écrite sans somme. La voici, par enveloppes. Ce sont des bornes hautes : du travail sur d'autres briques s'y intercale.
- **20/11** : de 21:28:28 UTC (additif de la 07a qui précède la demande) à 22:18:44 UTC (correction de la carte, commit `8f5fc886`), soit au plus 0 h 50 min.
- **21/11** : de 16:17:27 UTC (dernier commit avant la tranche 1, `7eb75cb0`, briques 05 et 19b) à 20:42:26 UTC, soit au plus 4 h 24 min.
- **Total** : au plus 5 h 15 min, pour 10 h estimées et un seuil de décision à 20 h. Le seuil n'est pas atteint.

## Remplacement écrit dans le patch et mesuré au banc (note de 2026-11-21T20:56:05Z ; passages 7 et 8, rien posé)

La conception et les prédictions ont été écrites avant le code (section « Ajout avant le septième passage », 20:44:39 UTC).

**Patch** `f38347ad37379efa…` (remplace `e063abd2aedf18af…`). Contrôles refaits après régénération :
- `git apply --check` passe ;
- `ec opa test` : 39/39 ;
- témoins de G6 et `yq` : 30.

Changements, tous dans `b/` :
- `outil/main.go` :
  - `vex` liste les énoncés de tous les documents lisibles, recevables ou non (noms et alias, horodatage, statut, `exemptant`) ;
  - `predicat` retient l'énoncé le plus récent qui nomme l'entrée, et compte `vex.ecarteesSansExemption`.
  Le filtre des documents (choix 5) et les fichiers passés à Grype ne changent pas.
- Commentaires de `scan.rego` et de `policy-scan.yaml` : plus aucun « plus ancien » dans `b/`. `go vet` et `gofmt` sont propres.

**Passage 7** ([journal](07b-t3-banc-7.log)) : 105 OK, 2 KO, de 20:48:02 à 20:51:25 UTC.
- Les deux écarts sont les contrôles de compatibilité (image, deb), que je n'avais pas prévus.
- Cause unique, relevée par `diff` : le bloc `vex` porte désormais `ecarteesSansExemption: 0`.
- Tous les cas du remplacement sont conformes.

**Passage 8** ([journal](07b-t3-banc-8.log)) : 107 OK, 0 KO, de 20:51:55 à 20:55:18 UTC. Le contrôle de compatibilité a été adapté et la cause écrite avant (section « Ajout avant le huitième passage »).

| Cas | Mesure |
|---|---|
| A, `predicat` : remplacement, ordre inversé, réaffirmation | exempt, horodatage 2026-11-20 (le plus récent) |
| A, `predicat` : rétractation, rétractation sous l'alias `CVE-2025-69725`, égalité, `not_affected` pour un autre produit | aucune exemption, 1 sans exemption |
| A, `predicat` : document récent sur une autre vulnérabilité | exempt, horodatage 2026-11-01 (non concerné) |
| B, `deux` | horodatage de l'entrée 2026-11-20, au lieu du 01/11 |
| B, `renouv-avant` (01/10 + veille) | horodatage de la veille ; porte **admise** (refusée au passage 6) |
| B, `inverse` | 2, 2, 0 ; 4/1 ; la veille ; porte admise |
| B, `retract-avant` puis `retract-apres` (affected sous l'alias) | 1, 1, 0 ; 4/1 ; admise, puis 2, 1, 1 ; 5/0 ; 1 sans exemption ; porte refusée |
| B, `partiel` (ancien sur V1 et V2, récent sur V1) | 3/2 ; V1 la veille, V2 au 01/10 ; porte : V1 en KEV admise, V2 en KEV refusée |

**Ce que cela établit** :
- Un VEX récent renouvelle l'échéance sans rien retirer du registre.
- Une rétractation la fait tomber, même sous un alias.
- Une égalité ou un autre produit ne donne pas d'exemption.
- Le résultat ne dépend pas de l'ordre des fichiers ni de l'ordre de publication.

**Limites** :
- Un document daté dans le futur gagne tous les classements jusqu'à sa date. La porte le refuse alors : c'est un blocage fermé, réparable par le retrait du passage 6, sur accord.
- Un document illisible ne remplace rien. Une rétractation mal formée est donc ignorée.
- Grype reçoit toujours les documents remplacés : c'est le prédicat qui décide de l'exemption.
- `ecarteesSansExemption` n'a pas de série dans Grafana : `entrees-scan` n'est pas modifié.
- La justification et l'impact restent hors de Grafana (statut et horodatage seulement).
- Tout est mesuré sur des témoins, sans KEV réelle, avec une clé locale (pas `hashivault://vex`).
- La pose reste en 9 pièces, chacune sur accord.

**Heures mesurées** : de 20:38:23 UTC (premier `date -u` après le choix) à 20:56:05 UTC.

## Couverture du paquet : trou fermé (note de 2026-11-21T21:04:20Z ; passage 9, rien posé ; corrige la note de 20:56:05Z)

**Ce qui était faux dans la note de 20:56:05Z** : le remplacement n'était pas « fermé dans les deux sens ».
- Le conseiller a signalé le cas, et une sonde hors banc, sur le binaire du passage 8, l'a confirmé (sonde effacée ensuite).
- Le cas : un ancien `not_affected` sur `go-chi` (01/11), puis un récent, du 20/11, sur la même vulnérabilité et le même produit, mais pour un autre sous-composant (`pkg:golang/stdlib@1.24.4`).
- Résultat : l'entrée `go-chi` recevait l'horodatage du 20/11, avec 0 entrée sans exemption.
- Aucun cas des passages 7 et 8 ne portait un autre sous-composant.

**Correction** (prédictions écrites avant le code, section « Ajout avant le neuvième passage », 20:59:25 UTC) :
- Le classement reste par noms.
- L'exemption exige en plus que chaque énoncé gagnant couvre le paquet de l'entrée : soit un produit qui cite le digest n'a pas de sous-composant, soit le PURL de l'entrée figure parmi ses sous-composants (égalité exacte).
- `vulnerability.@id` compte désormais parmi les noms.
- Patch `2005250baa1c3682…`. Contrôles refaits : `git apply --check`, `ec opa test` 39/39, témoins de G6 et `yq` à 30. `go vet` et `gofmt` sont propres.

**Passage 9** ([journal](07b-t3-banc-9.log)) : 109 OK, 0 KO, de 21:00:17 à 21:03:39 UTC.
- Autre sous-composant : aucune exemption, 1 sans exemption.
- Énoncé large, sans sous-composant : exempt au 20/11.
- `deb-complet` : 65/1. L'égalité exacte entre le PURL de l'énoncé et celui de Grype tient sur ce cas.
- Tous les autres cas sont inchangés.

**Limites ajoutées** :
- Un énoncé récent sur un paquet P2 fait tomber l'exemption de P1, pour la même vulnérabilité, tant que P1 n'est pas re-signé. L'échec est fermé, au prix d'une re-signature.
- L'égalité des PURL est exacte. Un VEX écrit avec un PURL qui diffère de celui de Grype (qualificatifs, `#v5`) n'exempte pas. C'est mesuré seulement sur `go-chi` (image) et `stdlib` (deb).

**Lecteurs du bloc `vex` du prédicat** : `grep` refait avec des motifs entre guillemets, sur tout le dépôt et sur `b/`. Seuls le banc et la fixture de `scan_test.rego` le lisent. La porte et `entrees-scan` ne lisent que le champ `vex` des entrées.

**Heures mesurées** : de 20:56:05 UTC (note précédente) à 21:04:20 UTC.

## Énoncés par paquet (note de 2026-11-21T21:11:13Z ; passage 10, rien posé ; corrige la limite de la note de 21:04:20Z)

**Ce qui était faux à 21:04:20Z** : la règle du passage 9 (chaque gagnant doit couvrir le paquet) bloquait un cas courant, celui d'une même vulnérabilité sur deux paquets avec un énoncé par paquet.
- Le conseiller l'a signalé. Une sonde hors banc, sur le binaire du passage 9, l'a confirmé (sonde effacée ensuite) : un document du 20/11 à deux énoncés, `go-chi` et `stdlib`, ne donnait aucune exemption.
- Avec deux documents, chacun aurait fait tomber l'autre à sa re-signature. La limite « tant que P1 n'est pas re-signé » était fausse.

**Correction** (prédictions écrites avant le code, section « Ajout avant le dixième passage », 21:06:51 UTC) :
- Un énoncé `exemptant` dont les sous-composants ne contiennent pas le paquet de l'entrée sort du classement de cette entrée.
- Tous les autres restent : `affected`, non recevable, autre produit, énoncé large.
- Patch `02ac8e835fe74fbe…`. Contrôles refaits : `git apply --check`, `ec opa test` 39/39, témoins de G6 et `yq` à 30. `go vet` et `gofmt` sont propres.

**Passage 10** ([journal](07b-t3-banc-10.log)) : 111 OK, 0 KO, de 21:07:17 à 21:10:40 UTC.
- Récent sur un autre sous-composant : exempt au 01/11, donc non renouvelé (au passage 9 : aucune exemption).
- Un document, deux énoncés par paquet : exempt au 20/11.
- `affected` récent sur l'autre paquet : aucune exemption.
- `large`, les huit cas du septième passage, B, C et D : inchangés (`deb-complet` 65/1).

**Écart avec les mots du choix, dit en clair** : le propriétaire a choisi « même vulnérabilité sur un même produit ». La règle écrite fonctionne autrement :
- elle classe les énoncés par noms (identifiant et alias), quel que soit le produit ;
- l'exemption exige que le gagnant cite le digest scanné ;
- un `not_affected` qui ne couvre pas le paquet de l'entrée n'entre pas dans son classement.
C'est plus strict que le couple vulnérabilité et produit pour les rétractations, qui comptent quel que soit le produit et le paquet. C'est équivalent pour les exemptions.

**Heures mesurées** : de 21:04:20 UTC (note précédente) à 21:11:13 UTC.

## Pièce 8 : `signer-vex.sh` écrit et mesuré (note de 2026-11-21T21:32:16Z ; passage 11, rien posé ; complète le point 6 de la note de 17:51:53Z)

**Le point 6 de 17:51:53Z** (« aucun script ni essai de signature ») **ne vaut plus pour le script** ; il vaut toujours pour `hashivault://vex`.

**Ce que fait le script** (`politique/07b-t3.patch`, fichier neuf `signer-vex.sh`, patch `992af0d0b7073b57…` ; le précédent `02ac8e835fe74fbe…` plus ce fichier, aucune ligne existante changée) :
- `verifier <document> <hôte/dépôt@sha256:…> <scan.json>` : juge sans signer ni toucher au registre ;
- `signer` : juge, signe (`cosign attest-blob`, `hashivault://vex` par défaut), vérifie la signature par la clé publique, rejuge le contenu signé, puis publie le referrer dans `builds/vex/<nom>` comme `publier` de `scanner.sh`.
- Le jugement est celui du scanner : `scan-outil vex` sur l'énoncé in-toto qui sera signé. Le script n'a pas de seconde implémentation des règles de recevabilité.
- Il refuse **avant signature** :
  - un statut `fixed` ;
  - un document qui mêle `not_affected` et d'autres statuts ;
  - une exemption que `scan-outil vex` rejette ;
  - une rétractation hors `affected` et `under_investigation` ;
  - un énoncé sans nom de vulnérabilité ou sans produit qui cite le digest ;
  - un horodatage illisible ou postérieur à l'heure de la commande ;
  - un sous-composant qui n'est pas exactement le PURL d'une entrée du prédicat de scan fourni.

**Ordre réel** : le script et les cas du banc ont été écrits avant la prédiction. Une sonde hors banc a passé les 12 témoins de `verifier` (21:25:03 UTC), puis a été effacée. La prédiction (section « Ajout avant le onzième passage », 21:27:36 UTC) le dit : en partie A, elle recopie la sonde ; en partie B, elle est neuve.

**Contrôles du patch refaits** : `git apply --check`, `ec opa test` 39/39, témoins de G6 et `yq` à 30.

**Passage 11** ([journal](07b-t3-banc-11.log)) : 137 OK, 0 KO, de 21:27:44 à 21:31:10 UTC. C'est la prédiction.
- **A, `verifier`** (13 cas) :
  - acceptés : ok, rétractation, énoncé large ;
  - refusés, chacun avec son motif : daté du futur (document ou énoncé), sous-composant absent, `fixed`, mêlé, sans `impact_statement`, autre digest, sans vulnérabilité, sans horodatage ;
  - image sans digest : code 2.
- **B, `signer`**, Zot jetable, clé locale :
  - daté du futur : refusé, 0 référent ;
  - clé étrangère : refusé avant publication, 0 référent ;
  - clé `vex` : publié ; `scanner.sh vex` le retient (1,1,0), 4/1, et l'empreinte citée par le prédicat est celle que le script annonce ;
  - rétractation datée de l'instant : publiée, 2 référents ; 5/0 et 1 sans exemption.
- Les 111 contrôles du passage 10 sont inchangés.

**Limites, dites en clair** :
- Non mesurés :
  - `hashivault://vex` (pièce 2) ;
  - le compte d'écriture de `builds/vex/**` (pièce 4) ;
  - un VEX réel (aucune KEV réelle).
- Le prédicat de scan fourni au script n'est pas vérifié par lui (signature, digest). Une liste de PURL fausse fausse le contrôle des sous-composants.
- « Futur » se juge sur l'horloge de la machine qui signe. Un VEX publié sans le script n'est pas filtré : la porte reste le seul contrôle.
- Le script ne garde pas de copie du document. Où l'auteur garde ses VEX reste non décidé (note de 2026-11-21T20:28:00Z).
- `git apply` et `patch` ne portent pas le bit d'exécution : appeler `bash signer-vex.sh`, ou poser le bit à la pose.

**Heures mesurées** :
- Ce segment : de 21:19:40 UTC (programmation de la lecture G7) à 21:32:16 UTC.
- Somme des enveloppes de la 07b, prolongée jusqu'à cette note : au plus 6 h 06 pour 10 h estimées.

## Pièce 8 : noms confrontés au scan, `action_statement` (note de 2026-11-21T21:54:57Z ; passage 12, rien posé ; corrige la note de 21:32:16Z)

**Ce qui était faux à 21:32:16Z** : le script confrontait les sous-composants au prédicat de scan, mais pas les noms de vulnérabilité.
- Le conseiller l'a signalé. Une sonde hors banc l'a confirmé (21:34:42 UTC, sonde effacée ensuite) : une rétractation `affected` sur `CVE-2025-69752`, faute de frappe pour `CVE-2025-69725`, sortait en code 0.
- Elle aurait été signée et publiée sans rien rétracter : l'exemption de la KEV restait jusqu'à 30 jours. C'était le seul échec ouvert du script. Les autres erreurs ne font que perdre une exemption.

**Correction** (prédiction écrite avant le code, section « Ajout avant le douzième passage », 21:35:33 UTC) :
- chaque énoncé doit avoir un nom égal à l'`id` ou à un alias d'une entrée du prédicat de scan fourni ;
- chaque sous-composant d'une exemption doit être le paquet d'une entrée qui porte ce nom ;
- `affected` exige un `action_statement` non vide. La spécification v0.2.0 l'écrit en MUST dans la description du champ, mais sa colonne « Required » le marque facultatif (lu le 21/11 sur le texte de l'étiquette v0.2.0, par une extraction de page, non comparé octet par octet). Le script prend la lecture stricte, comme pour `not_affected`. `under_investigation` n'exige rien.
- `scan-outil vex` et la porte ne changent pas. Les témoins de rétractation du banc reçoivent un `action_statement` par `jq`, et `07b-t3-vex.py` ne change pas.
- Patch `bf53ddddf09e4f5a…`, seul `signer-vex.sh` change. Contrôles refaits : `git apply --check`, `ec opa test` 39/39, témoins de G6 et `yq` à 30.

**Passage 12** ([journal](07b-t3-banc-12.log)) : 141 OK, 0 KO, de 21:51:22 à 21:54:47 UTC. C'est la prédiction.
- Refusés : la rétractation mal nommée, la rétractation sans `action_statement`, et l'exemption de `GO-2026-5774` pour `go-chi` quand le prédicat la place sur `stdlib`.
- Acceptée : la même exemption pour `stdlib`.
- Les 137 contrôles du passage 11 sont inchangés.

**Sonde demandée par le conseiller** (hors banc, 21:37:06 à 21:37:10 UTC ; binaire du passage 11, SBOM du cas `signe-ok`, base de G0, hors réseau ; effacée ensuite) : un document recevable par `scan-outil vex` peut-il faire sortir Grype en erreur ?
- Cinq formes testées : le témoin, un produit qui n'est pas un PURL, un sous-composant qui n'est pas un PURL, un horodatage à décalage horaire, un nom de vulnérabilité suivi d'une espace.
- Grype sort en code 0 dans les cinq cas. Aucune erreur trouvée, sans que cela prouve qu'il n'en existe pas : le repli « scan sans `--vex` » reste ouvert, non bloquant.
- Constat en passant : le produit qui n'est pas un PURL écarte quand même la correspondance (4 correspondances, 1 ignorée). C'est le constat 2 de la tranche 2 : Grype ne vérifie pas le produit sur le SBOM fusionné, la portée vient du sujet de l'attestation. Le sous-composant qui n'est pas un PURL et le nom suivi d'une espace n'écartent rien (5 correspondances, 0 ignorée).

**Limites ajoutées** :
- **Audit** : `JUGE`, `SIGNE`, `PUBLIE` et `REFUS` ne sortent que sur le terminal de l'auteur. Rien n'en est consultable dans Grafana, contrairement à l'exigence du propriétaire. La publication n'apparaît qu'au scan suivant, par `vex.documents` du prédicat.
- **Renouvellement** : le script ne dit pas si le document gagnera son classement. Un horodatage plus ancien que celui du gagnant en place, ou vieux de plus de 30 jours, est signé et publié, mais ne renouvelle rien.
- Le refus d'un identifiant absent du scan suppose que le prédicat fourni est à jour. Une vulnérabilité apparue depuis, avec une base plus récente, demande un prédicat plus récent.

**Heures mesurées** : de 21:32:16 UTC (note précédente) à 21:54:57 UTC.

## Branchement d'`entrees-scan` au rejeu (note de 2026-11-21T22:02:57Z ; à sec, non rejoué ; complète le paragraphe « Rejeu » de la note de 16:37:53Z)

- `08-trust-plane/rejeu.sh` appelle désormais `entrees-scan.sh pose` dans l'étape « 07b (entrees-scan, pose) », juste après « 06 (S6a, fraicheur) ». Un additif daté est ajouté dans son en-tête.
- **Pourquoi à cet endroit** : `pose` exige deux artefacts dans `SCANS` (contrôle « deux artefacts dans SCANS »), et l'unité `fraicheur-scan` ne porte le deb qu'après `fraicheur` de la 06.
- `verif` reste hors du rejeu : « une fois par scan » ne se prouve qu'au scan quotidien suivant.
- **Contrôle fait** : `bash -n`. **Non fait** : aucun rejeu, et aucun passage de `pose` dans ce contexte. `pose` relance `useradd` sous garde et réinstalle les fichiers ; sur une VM recréée, l'état part de zéro.

## Séries VEX dans Prometheus (note de 2026-11-21T22:09:17Z ; passage 13, rien posé ; pièce 7 de la pose)

**Limite visée** : le compteur `ecarteesSansExemption` n'avait pas de série dans Grafana, contrairement à l'exigence d'audit.

**Changement**, dans `entrees-scan.py` du patch (prédiction écrite avant le code, section « Ajout avant le treizième passage », 22:04:47 UTC). Trois séries par dépôt, lues dans le bloc `vex` du prédicat, 0 si le bloc est absent :
- `scan_vex_documents` : documents VEX passés au scanner ;
- `scan_vex_rejetes` : documents vérifiés mais rejetés par le filtre ;
- `scan_vex_ecartees_sans_exemption` : entrées dont le gagnant n'exempte pas.

`verif` d'`entrees-scan.sh` (patch) suit : **42 séries** au lieu de 36 (21 par dépôt ; le tableau de la pose disait « séries de 20 à 36 »), et les trois valeurs comparées à `jq` sur l'énoncé relu.

Patch `0d641017e662d483…`. Contrôles refaits : `git apply --check`, `ec opa test` 39/39, témoins de G6 et `yq` à 30.

**Passage 13** ([journal](07b-t3-banc-13.log)) : 143 OK, 0 KO, de 22:05:38 à 22:09:07 UTC. C'est la prédiction.
- `complet` et `deb-complet` : 21 séries, `vex` 1/0/0.
- `signe-retract` (rétractation publiée par `signer-vex.sh`) : 1/1/1.
- Prédicat d'avant la tranche 3 : 0/0/0.

**Non mesuré** : `verif` sur le vrai Prometheus et le vrai Grafana, qui attend la pose de la pièce 7. Une série reste un compte : elle ne dit pas quelle entrée a perdu son exemption. Pour cela, il faut la liste dans Loki, dont la ligne porte `vex` seulement pour les entrées écartées.

**Heures mesurées** : de 22:02:57 UTC (note du branchement au rejeu) à 22:09:17 UTC.

## Inventaire des limites de la 07b (note de 2026-11-21T22:10:13Z ; demande du propriétaire, verbatim : « Oui lève toutes les limites »)

**Portée de la demande** : le travail à sec seulement. Elle ne vaut ni accord pour les pièces 2 à 9 de la pose (cluster, vrai Zot, sudo), ni poussée, ni révision des choix 1 à 5. Une limite se lève par une mesure ; une limite qui ne peut pas l'être reste écrite.

**Classe 1, levable à sec** : une prédiction et un passage par limite, dans cet ordre.
1. **Prédicat de scan fourni à `signer-vex.sh`, non vérifié** : le script lira lui-même le scan signé le plus récent du digest et le vérifiera avec la clé publique du scanner. Le Zot jetable du banc n'a aujourd'hui aucun scan signé (`analyser` seul) : le banc devra en publier un, avec une clé locale.
2. **Audit des VEX comptés** : `entrees-scan.py` émettra dans Loki une ligne par document VEX compté (empreinte, horodatage), une fois par scan. Les `REFUS` de `signer-vex.sh` restent sur le poste de l'auteur : les envoyer dans Loki demande une écriture de l'hôte vers Loki, donc un accord (classe 3).
3. **Renouvellement** : `signer-vex.sh` affichera un avis, pas un refus, si le document neuf n'est pas plus récent que les énoncés déjà publiés sous le même nom, ou s'il a plus de 30 jours. La comparaison porte sur les `enonces` rendus par `scan-outil vex`, sans réécrire le classement en shell.
4. **Repli sans `--vex`** : si Grype échoue avec les VEX, le scanner relancera sans eux, et le prédicat et les séries le diront. Aucune panne réelle n'a été trouvée (5 formes sondées), la mesure passera donc par une panne injectée (faux `grype` dans le PATH) : synthétique, et dite comme telle.
- **Déjà levées** : la série de `ecarteesSansExemption` (passage 13). La « seule copie de la justification » de la note de 20:28:00Z ne vaut plus depuis le choix du remplacement : le registre est en ajout seul, et le document signé y reste. Le bit d'exécution : appeler `bash signer-vex.sh`, ou le poser à la pose.

**Classe 2, choix du propriétaire** :
- **Document daté du futur** : aujourd'hui, la porte le refuse (blocage fermé, choix 3). Le sortir du classement amenderait le choix 3. Seule une forme asymétrique tient : l'énoncé exemptant daté du futur sort, l'énoncé non exemptant reste ; sinon, une rétractation signée sur une horloge décalée serait ignorée sans bruit. À mesurer par un cas unitaire avant de poser la question.
- **Heure de signature de confiance** : ce n'est pas une limite de structure, le PoC a une TSA (J5). `cosign signing-config create --tsa` et `verify-blob-attestation --use-signed-timestamps` existent en v3.1.4 (aide lue, non essayé). La porte devrait alors juger l'âge sur l'heure de la TSA, pas sur celle de l'auteur : c'est un amendement du choix 3, qui touche l'ADR 0003, et la TSA du cluster demande un accord (classe 3).

**Classe 3, accord nommé** : `hashivault://vex` (pièce 2) ; compte d'écriture de `builds/vex/**` (pièce 4, pas avant le 29/11, G7) ; `verif` sur le vrai Prometheus et le vrai Grafana (pièce 7) ; scan déclenché à la publication d'un VEX (délai d'un jour) ; envoi des `REFUS` dans Loki ; essai de la TSA du cluster.

**Classe 4, non levable dans la 07b** :
- Grype ne dit pas quel énoncé a joué ; le prédicat le retrouve, mais c'est une reconstruction.
- La porte fait confiance au scanner.
- La spécification OpenVEX est un brouillon (v0.2), incohérent.
- Il n'existe aucune KEV réelle sur les artefacts.
- Le produit du VEX n'est pas vérifié par Grype sur le SBOM fusionné : la portée vient du sujet de l'attestation (constat 2 de la tranche 2).
- CSAF, l'atteignabilité et la projection Dependency-Track sont d'autres chantiers.

**Heures** : la somme des enveloppes est recalculée à chaque note ; une demande au propriétaire sera faite avant 20 h (2× l'estimation de 10 h).

## Limite 1 levée : `signer-vex.sh` lit et vérifie le scan signé (note de 2026-11-21T22:17:09Z ; passage 14, rien posé)

**Limite** (notes de 21:32:16Z et de l'inventaire) : le script jugeait les sous-composants et les noms sur un fichier `scan.json` fourni par l'appelant, sans en vérifier la signature.

**Changement** (prédiction écrite avant le code, section « Ajout avant le quatorzième passage », 22:11:04 UTC) :
- Le script ne prend plus de fichier. Usage : `signer-vex.sh verifier|signer <document> <hôte/dépôt@sha256:…>`.
- Il lit les scans attestés sur le digest dans `<hôte>/builds/scan/<nom>` par `cosign verify-attestation`, avec la clé publique du scanner (`CLE_SCANNER`), comme `lire_vex` de `scanner.sh`.
- Il garde le plus récent par `scannedAt`, converti en secondes, et refuse s'il n'en vérifie aucun.
- Les deux modes lisent donc le registre.
- Patch `9c08785442f9ad90…`, seul `signer-vex.sh` change. Contrôles refaits : `git apply --check`, `ec opa test` 39/39, témoins de G6 et `yq` à 30.

**Banc** : les cas `verifier` passent de la partie A à la partie B (Zot jetable). Une clé locale `scanner` signe des scans témoins, publiés en referrers (2, 1 et 1 référents) :
- `builds/signe` : un ancien scan, où `GO-2026-5774` est sur `stdlib` (01/11), puis un récent, tout sur `go-chi` ;
- `builds/deux` : le prédicat `stdlib` seul ;
- `builds/etranger` : un scan signé par la clé étrangère seulement.

**Passage 14** ([journal](07b-t3-banc-14.log)) : 146 OK, 0 KO, de 22:12:57 à 22:16:26 UTC. C'est la prédiction.
- Les 17 cas `verifier` des passages 11 et 12 sont inchangés, désormais sur un scan signé.
- L'exemption de `GO-2026-5774` pour `stdlib` passe sur `builds/deux` et est refusée sur `builds/signe` : c'est bien le scan le plus récent qui est lu.
- Le scan signé par la clé étrangère est ignoré : « aucun scan signé vérifié ».
- `signer` publie et `scanner.sh` retient, comme au passage 11.

**Limite qui reste** : un scan plus ancien que le dernier scan quotidien, mais plus récent que les autres scans publiés, ne se distingue pas d'un scan à jour. Le script prend ce qui est publié et signé ; il ne relance pas de scan.

**Heures mesurées** :
- Ce segment : de 22:10:13 UTC (inventaire) à 22:17:09 UTC.
- Somme des enveloppes de la 07b : au plus 6 h 50 pour 10 h estimées (demande au propriétaire avant 20 h).

## Second `verif` de la tranche 1, après les scans du 22/11 (note de 2026-11-22T17:44:16Z ; lecture seule, rien posé)

**But** (note de 16:41:07Z du 21/11) : voir l'émission sur un **nouveau** scan, puisque la pose n'avait montré que la non-réémission sur le même referrer.

**[`verif`](07b-t1-verif-3.log)**, de 17:43:20 à 17:43:21 UTC, `entrees-scan.sh` `5beedbca6627e3e7…` inchangé : **tenu**.
- Prometheus a 20 séries, égales à jq sur les énoncés relus en anonyme.
- `builds/scan/sample-app` : `scanne` passe au 22/11 09:31:56 UTC (scan précédent : 21/11 09:31:55), 6 lignes dans Loki pour ce scan.
- `builds/scan/sample-app-deb` : `scanne` passe au 22/11 11:16:56 UTC (scan précédent : 21/11 11:16:56), 67 lignes dans Loki pour ce scan.

**[Comptes dans Loki](07b-t1-loki-comptes.log)**, par l'auditeur, à 17:43:44 UTC (comptes seuls, aucune ligne brute ; requêtes `count_over_time` sur `{source="journal", unite="entrees-scan.service"}`) :
- 96 résumés en 24 h : un passage toutes les 15 min ;
- 2 résumés « liste émise » en 24 h, un par nouveau scan, et 3 en 30 h avec celui de la pose ;
- 6 et 67 lignes d'entrée en 24 h, 146 en 30 h, soit 2 × 73.

**Lecture** : chaque scan a été émis une fois, et une seule, dans 94 passages sans réémission. « Une fois par scan » est donc vu sur la VM pour un nouveau scan. Rien n'est noté sur le délai entre le scan et l'émission, qui n'a pas été mesuré.

## Limite 2 levée à sec : documents VEX comptés, dans Loki (note de 2026-11-22T17:52:04Z ; passage 15, rien posé)

**Limite** (inventaire) : le prédicat dit quels documents VEX le scanner a reçus, mais Grafana n'en avait que le nombre (`scan_vex_documents`).

**Changement** (prédiction écrite avant le code, section « Ajout avant le quinzième passage », 17:46:52 UTC) :
- `entrees-scan.py` émet une ligne JSON par document du bloc `vex.documents` du prédicat : `depot`, `scannedAt`, `scanne`, `vexDocument` (empreinte de l'énoncé signé décodé) et `vexTimestamp`, sans `id`.
- Ces lignes partent avec les lignes d'entrée, sous la même marque d'état : une fois par referrer de scan. Le résumé ne change pas.
- `verif` d'`entrees-scan.sh` écarte ces lignes du compte des entrées (`| vexDocument=""`) et les compte à part, contre `jq '.predicate.vex.documents | length'`. Une réponse vide vaut 0.
- Patch `5c41cf55e4ef7511…`. Contrôles refaits : `git apply --check`, `ec opa test` 39/39, `yq` à 30.

**Sonde avant le code** ([journal](07b-t3-sonde-loki-filtre.log), auditeur, lecture seule) : sur le vrai Loki, `vexDocument=""` garde les 6 et 67 lignes des scans du jour, et `vexDocument!=""` ne rend aucune série, pas « 0 ».

**Passage 15** ([journal](07b-t3-banc-15.log)) : 146 OK, 0 KO, de 17:48:26 à 17:51:57 UTC. C'est la prédiction.
- Dans les quatre cas D, les lignes de document reprennent les empreintes du bloc `vex`, aucune n'a d'`id`, et aucune ligne d'entrée n'a de `vexDocument`.
- `main()` passe trois fois : referrer A, encore A, puis B. Il rend 7, 1 et 7 lignes pour `complet` et `signe-retract`, 68, 1 et 68 pour `deb-complet`, et 6, 1 et 6 pour le prédicat d'avant la tranche 3, sans ligne de document. La liste est émise, puis non, puis émise.
- La lecture de Zot est synthétique (fonction `lire` remplacée, comme au banc de la tranche 1). `main()` est le vrai.

**Limites qui restent** :
- Seuls les documents retenus ont une ligne. Les rejetés n'ont qu'un compte (`rejetes`) : les lister demanderait de changer le prédicat (`main.go`).
- À la pose, la marque du referrer courant existe déjà. Les lignes de document n'apparaîtront donc qu'au scan suivant.
- `verif` du patch sur le vrai Loki : `bash -n` seulement, il attend la pose.
- Les `REFUS` de `signer-vex.sh` restent sur le poste de l'auteur (classe 3 de l'inventaire).

**Heures mesurées** :
- Ce segment : de 17:43:00 UTC (premier relevé du 22/11, `verif` de la tranche 1 compris) à 17:52:04 UTC.
- Somme des enveloppes de la 07b : au plus 7 h 00 pour 10 h estimées (demande au propriétaire avant 20 h).

## Limite 3 levée à sec : avis de renouvellement dans `signer-vex.sh` (note de 2026-11-22T18:38:35Z ; passage 16, rien posé)

**Limite** (note de 21:54:57Z du 21/11, inventaire) : le script ne disait pas si le document gagnerait son classement. Un horodatage plus ancien que celui du gagnant en place, ou vieux de plus de 30 jours, était signé et publié sans rien renouveler.

**Changement** (approche relue par le conseiller ; prédiction écrite avant le code, section « Ajout avant le seizième passage », 18:31:58 UTC) :
- `CLE_PUBLIQUE` (clé publique VEX) est exigée dans les deux modes.
- Après le premier jugement, avant toute signature, le script lit les VEX publiés sur le digest dans `builds/vex/<nom>`, comme `lire_vex` de `scanner.sh`, et les passe à `scan-outil vex`. Une ligne `PUBLIES|` donne toujours le nombre d'énoncés publiés vérifiés et le code de cosign.
- Un énoncé publié est concurrent s'il nomme une entrée du scan qui porte un nom de l'énoncé neuf (id ou alias). Tous les énoncés publiés comptent, recevables ou non, comme dans le classement de `gagnant`. Les horodatages sont comparés en entiers à la nanoseconde.
- Avis (`AVIS|`, code de sortie inchangé) :
  - `renouvellement` : exemption pas plus récente qu'un énoncé concurrent ;
  - `rétractation` : rétractation dans le même cas ;
  - `âge` : exemption dont l'échéance (horodatage + `VEX_AGE_MAX_JOURS`, 30 par défaut) est passée ou à moins d'un jour.
- `ECHEANCE|` donne l'échéance de chaque énoncé d'exemption.
- Patch `dbad512077db97a6…`, seul `signer-vex.sh` change. Contrôles refaits : `git apply --check`, `ec opa test` 39/39, `yq` à 30.

**Passage 16** ([journal](07b-t3-banc-16.log)) : 162 OK, 0 KO, de 18:34:15 à 18:37:47 UTC. C'est la prédiction.
- Les 18 cas `verifier` des passages 11, 12 et 14 sont inchangés. Ils lisent 0, 0, 0 et 2 énoncés publiés (les deux VEX de `builds/vex/deux`).
- Dépôt `builds/avis` : P1 (clé VEX, il y a 10 jours, à 0,5 s), P2 (clé étrangère, il y a 1 h), P3 (clé VEX, non recevable, il y a 5 jours). Deux énoncés sont lus : P2 est ignoré, et cosign rend les attestations valides quand une autre échoue (code 0).
- Avis `renouvellement` : même horodatage que P1, même seconde sans fraction (0,5 s plus ancien), alias `CVE-2025-69725` plus ancien, et exemption plus ancienne que P3, non recevable.
- Aucun avis : 1 jour (P2 ignoré), même seconde à 0,7 s (une comparaison à la seconde aurait averti), rétractation récente, exemption de 28 jours.
- Avis `rétractation` : rétractation plus ancienne que P1. Avis `âge` : 31 jours, et 708 h (échéance dans 12 h).
- `signer` : 0 énoncé publié avant le premier document, 1 avant la rétractation, aucun avis dans les deux cas.
- Le seuil par défaut du script (30) est égal à `vex_age_max_jours` de la politique du patch, lu par `yq`.

**Limites qui restent** :
- **Avis, pas refus.** Une rétractation plus ancienne qu'une exemption publiée est signée et publiée, mais ne rétracte rien : c'est l'échec ouvert corrigé au passage 12, par un autre chemin. La passer en refus est un choix du propriétaire. Elle rejoint la question unique prévue avec le cas de l'exemptant daté du futur.
- La couverture par paquet n'est pas comparée : l'avis peut avertir à tort (« peut ne pas renouveler »).
- Sans VEX publié, cosign sort en code 1 (« no matching attestations ») : seul le message distingue ce cas d'un registre illisible.
- `AVIS`, `REFUS` et `PUBLIE` restent sur le terminal de l'auteur (classe 3 de l'inventaire).
- `hashivault://vex` et le vrai Zot ne sont pas mesurés.

**Heures mesurées** :
- Ce segment : de 17:43:00 UTC à 18:38:35 UTC, compté d'un seul tenant, y compris la poussée et le compactage entre 17:52:04 et 18:27:19 UTC.
- Somme des enveloppes de la 07b : au plus 7 h 46 pour 10 h estimées (demande au propriétaire avant 20 h).

## Rétractation ancienne en mode `signer` (note de 2026-11-22T18:44:41Z ; passage 17, rien posé ; complète la note de 18:38:35Z)

**Ce qui n'était pas mesuré à 18:38:35Z** : la note dit qu'une rétractation plus ancienne qu'une exemption publiée « est signée et publiée ». Au passage 16, les avis n'avaient été vus qu'en mode `verifier`. Le conseiller l'a relevé.

**Passage 17** ([journal](07b-t3-banc-17.log)) : 167 OK, 0 KO, de 18:40:58 à 18:44:31 UTC. C'est la prédiction (section « Ajout avant le dix-septième passage », 18:40:43 UTC). Patch inchangé, `dbad512077db97a6…`.
- `signer` du document `retract-ancienne` sur `builds/avis`, après les 11 cas `verifier` : code 0, `AVIS|rétractation`, une ligne `PUBLIE|`, 4 référents.
- Scan suivant (mode `vex` de `scanner.sh`, puis les commandes d'`analyser`) : 3 VEX vérifiés, 1 retenu, 2 rejetés. L'entrée `GHSA-mqqf-5wvp-8fh8` reste écartée avec l'horodatage de P1 : la rétractation ne rétracte rien.

**Ce que cela confirme** : l'avis est le seul signal. Le document est publié dans le registre en ajout seul, et l'exemption tient jusqu'à son échéance. La question au propriétaire (avis ou refus) repose donc sur un fait mesuré.

**Heures mesurées** :
- Ce segment : de 18:38:35 UTC (note précédente) à 18:44:41 UTC.
- Somme des enveloppes de la 07b : au plus 7 h 52 pour 10 h estimées (demande au propriétaire avant 20 h).

## Limite 4 levée à sec : repli sans `--vex` (note de 2026-11-22T19:16:04Z ; passage 18, rien posé)

**Limite** (inventaire, note de 22:10:13Z du 21/11) : si Grype échouait avec les VEX, le scan échouait, sans prédicat ni série. Aucune panne réelle n'a été trouvée (cinq formes sondées). La mesure passe donc par une **panne injectée, synthétique**.

**Changement** (approche relue par le conseiller ; prédiction écrite avant le code, section « Ajout avant le dix-huitième passage », 19:07:17 UTC) :
- `scanner.sh`, mode `analyser` : si Grype échoue alors qu'au moins un VEX est retenu, il écrit une ligne `REPLI|grype code <c> avec <N> VEX[ : <erreur>] ; scan relancé sans --vex, aucun VEX appliqué`, puis relance Grype sans `--vex`. Si la relance échoue, le scan échoue comme avant. Sans VEX retenu, un échec reste un échec.
- `scan-outil predicat … repli` : `vex.documents` est vide, et `vex.repli` compte les documents retenus non appliqués, lus dans `vex-retenus.json`, la seule source. Le champ est absent hors repli, donc les prédicats ordinaires ne changent pas : le contrôle de compatibilité tient. En repli, une correspondance écartée par un VEX est une erreur, comme un repli sans document retenu.
- `entrees-scan.py` écrit une série neuve, `scan_vex_repli` (0 si le champ est absent). `entrees-scan.sh` (verif) la compare à jq et attend 44 séries.
- **Correction en passant** : la pose attendait encore 20 séries écrites. C'est le compte d'avant la tranche 3 : le patch en écrit 42 depuis le passage 13, et la pose aurait donné un faux KO. Elle attend maintenant 44.
- `scan_test.rego` : deux tests (repli admis sans KEV, repli avec KEV refusé). Aucune règle ne change.
- Patch `9fcb4b40dc31c95d…`. Contrôles refaits : `git apply --check`, `go vet`, `shellcheck`, `ec opa test` 41/41, `yq` à 30.

**Passage 18** ([journal](07b-t3-banc-18.log)) : 186 OK, 0 KO, de 19:09:26 à 19:15:56 UTC. C'est la prédiction.
- A : en repli sur le scan témoin, le prédicat vaut celui d'avant, plus `vex` avec `documents` vide et `repli` à 1. Code 1 sans document retenu, et code 1 avec une entrée écartée par un VEX. Code 2 pour un cinquième argument autre que `repli`.
- B : le vrai mode `analyser` tourne avec un `grype` factice devant le vrai dans le PATH du cas. Le faux note chaque appel, puis échoue ou passe la main au vrai par son chemin absolu. L'import de la base passe toujours. Dépôt neuf `builds/repli`, un VEX recevable :
  - `repli` (panne sur `sbom:` avec `--vex`) : appels `db 0, sbom 1, sbom 0`. Une ligne `REPLI|grype code 1 avec 1 VEX`. 1 VEX vérifié et retenu. Entrées 5/0, bloc `vex` `{documents: [], ecarteesSansExemption: 0, rejetes: 0, repli: 1}`, entrées égales à celles de `complet` sans le champ `vex`.
  - `panne-totale` (panne sur tout `sbom:`) : mêmes appels, une ligne `REPLI|`, code 1, aucun prédicat.
  - `complet` : `repli` absent.
- C : la porte refuse le repli quand `GHSA-mqqf-5wvp-8fh8` est passée en KEV (`scan.kev_without_vex`), car aucun VEX n'est appliqué : la direction est stricte. Elle l'admet sans KEV : le champ passe la porte.
- D : 22 séries par prédicat, `scan_vex_repli` à 1 pour le repli et à 0 pour les quatre autres. Les comptes de `entrees-scan.sh` à la pose et au verif valent 44 et 44, soit deux dépôts de 22.

**Limites qui restent** :
- La panne est synthétique : aucune panne réelle de Grype avec `--vex` n'est connue.
- Une panne passagère de Grype donne aussi un repli. C'est strict, mais c'est un faux positif possible.
- En repli, `documents` est vide, et aucune ligne `vexDocument` ne part dans Loki. Seules les lignes `VEX|` et `REPLI|` du journal du pod disent quels VEX n'ont pas joué.
- Aucune alerte ni aucun panneau sur `scan_vex_repli` : cela demande un accord (tableau de bord provisionné).
- Rien n'est posé : l'image `outils-scan` du scanner et `entrees-scan.py` sur sc-stockage sont des pièces de la pose, chacune sur accord.

**Heures mesurées** :
- Ce segment : de 19:03:15 UTC à 19:16:04 UTC.
- Somme des enveloppes de la 07b : au plus 8 h 05 pour 10 h estimées (demande au propriétaire avant 20 h).

## Échec sans VEX retenu et effet du repli (note de 2026-11-22T19:26:25Z ; passage 19, rien posé ; complète la note de 19:16:04Z, relue par le conseiller)

**Ce qui n'était pas mesuré à 19:16:04Z** : « Sans VEX retenu, un échec reste un échec ». Ce chemin a changé au passage 18 (stderr capturé, puis `exit "$c"`), et c'est celui de tous les scans sans VEX.

**Passage 19** ([journal](07b-t3-banc-19.log)) : 192 OK, 0 KO, de 19:18:23 à 19:26:14 UTC. C'est la prédiction (section « Ajout avant le dix-neuvième passage », 19:18:18 UTC). Patch inchangé, `9fcb4b40dc31c95d…`.
- Cas `sans-vex-panne` : même `grype` factice (panne injectée, synthétique) en panne totale, dépôt neuf `builds/sans-vex` sans VEX publié, mode `analyser` réel.
- Résultat : appels `db 0, sbom 0` (aucune relance), VEX 0,0,0, aucune ligne `REPLI|`, message du faux dans le journal (le stderr de Grype reste visible), code 1, aucun prédicat.

**Effet du repli sur la porte** (lu dans `scan.rego`, non mesuré sur un scan antérieur) :
- `_retenus` garde le scan le plus récent.
- Avant le passage 18, un scan en échec ne publiait rien, et le scan précédent restait jugé, exemptions comprises.
- Un repli publie un scan signé sans exemption. Une KEV exemptée est donc refusée dès ce scan, jusqu'au scan suivant sans panne.

C'est la direction stricte, mais c'est un changement d'effet, à lire par le propriétaire.

**Précision sur la note de 19:16:04Z** : « la pose aurait donné un faux KO » est lu dans le code (`attendu … 20`, contre 42 séries écrites par le patch), pas mesuré. Aucun autre compte en dur n'a été trouvé dans `entrees-scan.sh` ni dans `plateforme.sh` de l'arbre b.

**Correction des heures** (conseiller) : la note de 19:16:04Z partait de 19:03:15 UTC et ne comptait pas l'intervalle de 18:44:41 à 19:03:15 UTC (poussée et compactage). La note du passage 16 comptait ces intervalles d'un seul tenant. Recalculée ainsi, la somme est d'au plus 8 h 24 à 19:16:04Z, et non 8 h 05.

**Heures mesurées** :
- Ce segment : de 18:44:41 UTC à 19:26:25 UTC, compté d'un seul tenant.
- Somme des enveloppes de la 07b : au plus 8 h 34 pour 10 h estimées (demande au propriétaire avant 20 h).

## Exemptant daté du futur : forme asymétrique mesurée hors patch (note de 2026-11-22T19:48:35Z ; passage 20, rien posé ; approche relue par le conseiller)

**Question** (inventaire, classe 2) : aujourd'hui, un document daté du futur gagne tous les classements jusqu'à sa date, et la porte le refuse (blocage fermé). Le sortir du classement amenderait le choix 3. Seule une forme asymétrique tient. Elle est mesurée ici par un cas unitaire, avant la question au propriétaire.

**Variante, hors patch** ([diff](07b-t3-variante-futur.patch), `afa6b30d0838019d…`) : `07b-t3.patch` ne change pas (`9fcb4b40dc31c95d…`). Le banc applique le diff à une copie de `outil/` du patch et construit un second binaire. Seul `predicat` change :
- limite = heure du scan (`descriptor.timestamp`, que la porte lit dans `scannedAt`) plus 5 min (le `_derive` de la porte, constante dupliquée en Go) ;
- dans le classement d'une entrée, un énoncé **exemptant** postérieur à la limite sort ; un énoncé **non exemptant** reste, quelle que soit sa date ;
- s'il y a des énoncés et que l'heure du scan est illisible, c'est une erreur (échec fermé).

**Passage 20** ([journal](07b-t3-banc-20.log)) : 226 OK, 0 KO, de 19:40:06 à 19:48:11 UTC.
- Chaque contrôle prédit tient (section « Ajout avant le vingtième passage », 19:38:25 UTC). Le bilan du banc est de 0 écart.
- **Le total prédit, lui, était faux** : la correction de 19:40:00 UTC (12 cas dans la table existante, non 11) annonçait 225. Or 192 + 3 + 1 + 12 + 16 + 2 font 226. C'est une erreur d'addition dans la prédiction, pas un contrôle de plus : la comparaison au passage 19 donne 34 contrôles neufs et aucun perdu.

Heure du scan témoin : 17:23:25 UTC le 21/11. Résultats pour l'entrée `GHSA-mqqf-5wvp-8fh8` (aujourd'hui → variante) :

| Cas | Documents | Aujourd'hui | Variante |
|---|---|---|---|
| futur-seul | exemptant du 2027-01-01 | exemptée au 2027-01-01 (refus de la porte en KEV) | aucune exemption |
| futur-et-ancien | exemptant du 01/11 + exemptant du 2027-01-01 | exemptée au 2027-01-01 (refus de la porte en KEV) | **exemptée au 01/11** |
| retractation-future | exemptant du 01/11 + `affected` du 2027-01-01 | aucune | aucune |
| futur-egalite | exemptant et `affected` du 2027-01-01 | aucune | aucune |
| retractation-puis-futur | exemptant du 01/11 + `affected` du 20/11 + exemptant du 2027-01-01 | exemptée au 2027-01-01 (refus de la porte en KEV) | **aucune** |
| futur-autre-produit | exemptant du 01/11 + `not_affected` du 2027-01-01 pour un autre produit | aucune | aucune |
| bord-4-min | exemptant du 01/11 + exemptant à 17:27:25Z | exemptée à 17:27:25Z | idem |
| bord-6-min | exemptant du 01/11 + exemptant à 17:29:25Z | exemptée à 17:29:25Z (refus de la porte en KEV) | **exemptée au 01/11** |

- Les 12 cas existants du remplacement donnent le même résultat sur les deux binaires, et le prédicat de compatibilité de l'image est identique.
- Heure du scan illisible : code 0 aujourd'hui (l'heure est recopiée sans être lue), code 1 avec la variante.

**Lecture** :
- **Ce que la variante change** : un exemptant daté du futur ne masque plus une exemption valide plus ancienne (`futur-et-ancien`, `bord-6-min`). Dans `retractation-puis-futur`, il ne lève plus une rétractation : aujourd'hui, le résultat est un refus de la porte ; avec la variante, l'entrée reste sans exemption. C'est la même issue à la porte pour une KEV, mais pour la bonne raison.
- **Ce qu'elle garde** : une rétractation datée du futur garde son effet (`retractation-future`). C'est la preuve de l'asymétrie : sans elle, une rétractation signée sur une horloge décalée serait ignorée sans bruit.
- **Ce qu'elle ne lève pas** : un `not_affected` daté du futur pour un autre produit n'est pas exemptant, et il reste dans le classement (`futur-autre-produit`). Ce cas reste un blocage fermé.
- La « réparation par retrait sur accord » n'est plus nécessaire pour un exemptant daté du futur. Elle reste nécessaire pour un énoncé non exemptant daté du futur.

**Limites** :
- La constante de 5 min est dupliquée entre Go et rego. Si l'une change sans l'autre, le scanner et la porte divergent.
- L'heure du scan est celle de la machine du scanner. Une horloge du scanner en avance élargit la fenêtre.
- Mesuré au niveau du prédicat seulement : le refus de la porte sur un horodatage futur est déjà mesuré (cas `futur`, partie C), mais la variante n'a pas été jugée à la porte ni dans le mode `analyser` réel.
- Rien n'est posé, et le patch ne contient pas la variante : elle amende le choix 3, c'est au propriétaire de décider.

**Heures mesurées** :
- Ce segment : de 18:44:41 UTC à 19:48:35 UTC, compté d'un seul tenant.
- Somme des enveloppes de la 07b : au plus 8 h 56 pour 10 h estimées (demande au propriétaire avant 20 h).

## Décision du propriétaire : exemptant daté du futur et rétractation ancienne (note de 2026-11-22T19:52:55Z ; rien posé)

**Question** posée après le passage 20, en deux parties, chacune avec les coûts mesurés ou lus. Recommandations relues par le conseiller.

**Réponses** (verbatim) :
- Exemptant daté du futur : « Garder le refus (Recommandé) ». La variante est écartée, et le choix 3 ne change pas. Un exemptant daté du futur gagne le classement jusqu'à sa date, et la porte le refuse (blocage fermé). La réparation reste le retrait du référent dans le vrai Zot, sur accord. `resultats/07b-t3-variante-futur.patch` reste archivé comme mesure, hors patch.
- Rétractation plus ancienne qu'une exemption publiée : « Garder l'avertissement (Recommandé) ». `signer-vex.sh` la signe, la publie et écrit `AVIS|rétractation`. Le refus reste possible plus tard, une fois la couverture par paquet comparée.

**Réserves dites au propriétaire avant la réponse** (lues dans le code, non mesurées) :
- La porte ne lit que `vex.status` et `vex.timestamp` de chaque entrée, jamais `vex.documents`. Qu'elle admette `futur-et-ancien` avec la variante est donc lu, pas mesuré.
- Avec la variante, le document écarté resterait dans `vex.documents` et dans les lignes `vexDocument` de Loki, sans ligne ni série qui dise qu'il n'a pas joué.
- L'avis de rétractation ne compare pas la couverture par paquet : il peut avertir à tort, et un refus bâti dessus pourrait bloquer une rétractation légitime.

**Correction de la note précédente** (conseiller) : « Ce qu'elle ne lève pas » présente `futur-autre-produit` comme un blocage propre au futur. Ce n'est pas le cas : `autre-produit`, au 20/11, donne déjà « aucune » (remplacement, tout produit). C'est un effet du remplacement, pas de la date.

**Hors de cette question** : le repli sans `--vex` (passages 18 et 19) est dans le patch, et son effet est écrit (une KEV exemptée est refusée dès un scan en repli, jusqu'au scan suivant sans panne). Il se tranche avec l'accord de la pièce du scanner, avant la pose.

**Heures mesurées** :
- Ce segment : de 18:44:41 UTC à 19:52:55 UTC, compté d'un seul tenant.
- Somme des enveloppes de la 07b : au plus 9 h 00 pour 10 h estimées (demande au propriétaire avant 20 h).

## Pièces de la pose : fichiers du patch rattachés, tableau corrigé (note de 2026-11-22T20:09:09Z ; lecture seule, rien posé ; relue par le conseiller)

**Pourquoi** : le tableau des 9 pièces date du 21/11. Le patch a changé depuis, jusqu'au passage 19 (`9fcb4b40dc31c95d…`). Les accords nommés se donneront sur ce tableau, il doit donc dire ce que chaque pièce touche.

**Fichiers du patch, rattachés** (lus dans `07b-t3.patch`, 9 fichiers, aucun orphelin) :

| Fichier | Pièce |
|---|---|
| `outil/main.go` | 3 (image `outils-scan`) |
| `politique/scanner.sh` | 5 |
| `plateforme.sh`, fonction `cm_scan` (clé `vex.pub` dans `scan-config`) | 5 |
| `politique/porte/policy-scan.yaml`, `scan.rego`, `scan_test.rego` | 1 et 6 |
| `systemd/entrees-scan.py` | 7 |
| `entrees-scan.sh` (étapes `pose` et `verif`) | 7 |
| `signer-vex.sh` (fichier neuf) | 8 |
| `plateforme.sh`, `g5_regles`, contre-épreuves de G5, témoins de G6 | 9 |

**Corrections du tableau du 21/11** :
- **Pièce 7** : « séries de 20 à 36 » est périmé. Le patch attend **44 séries** (22 par dépôt, deux dépôts), dans `pose` comme dans `verif`. La pièce comprend aussi `entrees-scan.sh`, qui la pose et la vérifie.
- **Pièce 9** : `rejeu.sh` n'est pas dans le patch. Il appelle `g6_temoins` et, depuis la note du 21/11 à 22:02:57Z, `entrees-scan.sh pose`. La pièce 9 ne touche donc que `plateforme.sh`.
- **Pièce 5** : elle touche aussi `plateforme.sh` (`cm_scan` ajoute `vex.pub` quand la clé publique existe ; sans elle, `scanner.sh` scanne sans VEX et le journal le dit).

**Pièces 6 et 9, lues** : G5 et G6 copient `policy-scan.yaml` et `scan.rego` du **dépôt** dans la racine de la porte. Ils prennent la clé du scanner dans `resultats/` (témoin `porte` de G6) et lisent les images de la porte dans Zot, en anonyme. Ils ne lisent jamais la ConfigMap déployée. La pièce 6 (ConfigMap dans le cluster) et la pièce 9 ne sont donc pas liées par la ConfigMap. Toutes deux supposent que le patch est appliqué au dépôt.

**Ce qui est posable avant le 29/11** : les pièces 3 et 4 écrivent dans le vrai Zot (G7). La pièce 5 suit la 3, la 8 suit la 2 et la 4, et le repli se tranche avec le scanner. Restent :
- **Pièce 2** : elle n'a **ni script ni mode d'authentification du propriétaire**. `signer-vex.sh` attend `VAULT_ADDR` et le jeton d'OpenBao de l'appelant. La clé `vex` et sa politique se calqueraient sur la clé `scanner` de G3 (ajout pur). En revanche, le jeton du propriétaire est un choix : qui l'émet, avec quelle durée. Si les scripts du PoC peuvent l'émettre avec le jeton racine, « réservé au propriétaire » n'est que nominal. La signature avec `hashivault://vex` n'a jamais été essayée (point 6 de la note de 17:51:53Z du 21/11). Elle se mesure à sec sur un OpenBao 2.7.2 jetable, tiré de l'image signée déjà en miroir. Ce sera le passage suivant.
- **Pièce 7** : `entrees-scan.py` neuf écrit 0 pour le bloc `vex` absent des prédicats d'avant la tranche 3 (lu dans le code, non mesuré sur la VM). Posée seule, elle n'apporterait que 24 séries à zéro. Elle obligerait aussi à appliquer deux fichiers du patch au dépôt, puis à régénérer le patch. Enfin, une nouvelle `pose` pourrait réémettre dans Loki les lignes d'un scan déjà listé, ce qui doublerait le compte sur 24 h (non vérifié). **Recommandation : attendre**, et la poser avec les autres.
- **Pièces 6 et 9** : rien de mesurable tant que le scanner n'émet pas `vex`.

**Hors pose** :
- **Heure de signature de confiance (TSA)** : classe 2 de l'inventaire, **écrite, non essayée**. Elle amende le choix 3 et l'ADR 0003, et la TSA du cluster demande un accord.
- **G7, balayage n°3** (attendu le 22/11 vers 22:30 UTC) : il n'est pas relevé ce soir. La tâche du 29/11 lit les n°2 à n°9 et ne dépend pas du nombre de séries.

**Heures mesurées** :
- Enveloppe fermée à 20:06:09 UTC : au plus 9 h 14 (33187 s).
- Segment suivant : de 20:06:09 UTC à 20:09:09 UTC, compté d'un seul tenant.
- Somme des enveloppes de la 07b : au plus 9 h 17 pour 10 h estimées (demande au propriétaire avant 20 h).
