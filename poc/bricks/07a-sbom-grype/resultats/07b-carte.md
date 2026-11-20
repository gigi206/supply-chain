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
