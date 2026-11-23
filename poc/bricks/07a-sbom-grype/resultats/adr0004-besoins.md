# ADR 0004 : besoins à définir, fiche préparée à sec (date -u de 22:01:31 UTC, le 2026-11-23)

Demande du propriétaire : « on peut avancer ? », pendant le rejeu `un-trait-1`, après la préparation de la pièce 8. Cette fiche ne décide rien : l'[ADR 0004](../../../../docs/adr/0004-vulnerabilites-vex.md) reste « À rédiger ». Elle rassemble, pour les trois besoins ouverts, ce que disent les documents du projet, ce que le PoC mesure déjà, et les options possibles. Aucune option n'est recommandée ici.

## Ce que disent les documents

| Besoin | Source | Texte (résumé) |
|---|---|---|
| Projection Dependency-Track | `docs/02`, §1 et l. 89 ; `docs/00`, l. 277 ; `docs/04`, l. 52, 133 et 203 | Dependency-Track v5 en **projection reconstructible** (phase 2c), alimentée par les SBOM et les VEX. Verdict de `docs/04` : **« À surveiller, hors chemin critique »** (un seul mainteneur fusionne ; parade écrite : « ré-ingest testé »). D'après `docs/00` (**non revérifié** depuis), Dependency-Track ne lit **ni OpenVEX ni CSAF**, seulement le VEX de CycloneDX. |
| Score « vulnérabilités après VEX » | `docs/02`, §5, l. 202-206 | Score informatif v1 : **35 % vulnérabilités après VEX (CVSS × EPSS)**, 25 % intégrité, 25 % santé amont, 15 % licences, fraîcheur et qualité SBOM. Calculé par `tools/score` (n'existe pas : `tools/` ne contient que `health`, `index` et `secrets-depot.sh`). |
| KPI de couverture VEX | `docs/02`, §7, l. 229 | `tools/metrics-exporter` (n'existe pas) dérive des attestations, entre autres, « KEV ouvertes et délai de correction, couverture VEX ». Seuil : 0 écart avec le recalcul. |

## Ce que le PoC mesure déjà

- **Entrées trouvées et écartées, par dépôt** (pièce 7, `entrees-scan.py`, posée le 23/11, `verif` tenue) : 44 séries dans Prometheus, dont `scan_entrees` (par gravité), `scan_entrees_kev`, `scan_entrees_avec_correctif`, `scan_entrees_vex` (écartées par un VEX, même grille), `scan_entrees_kev_vex`, `scan_vex_documents`, `scan_vex_rejetes`, `scan_vex_ecartees_sans_exemption`, `scan_vex_repli`. **Réelles = trouvées − écartées**, par soustraction dans Grafana. Une ligne JSON par entrée et par document VEX dans Loki.
- **Aucun tableau de bord Grafana n'affiche ces séries** : elles se lisent par l'exploration (aucun fichier du dépôt hors de la 07a ne nomme `scan_entrees`, recherche par grep le 23/11, entre 22:01:05 et 22:01:31 UTC).
- **Le prédicat de scan ne porte pas de score CVSS.** Champs d'une entrée : `id`, `aliases`, `severity` (gravité en mots : Critical, High, Medium, Low, Unknown), `kev`, `kevCves`, `epss`, `package`, `fixedIn`, `vex` (`outil/main.go`, l. 139-147).
- **EPSS est souvent absent** : 3 entrées sur 6 dans le dernier scan archivé de sample-app (`g4-scan-predicat.json`), 64 sur 67 dans celui du deb (`07b-t1-predicat-sample-app-deb.json`), 10 sur 13 dans le témoin KEV de G6 (relevé par jq le 23/11, entre 22:01:05 et 22:01:31 UTC).
- **Le VEX est en OpenVEX** (décision 4 du 21/11) ; la porte et le scanner n'en lisent pas d'autre.

## Besoin 1 : projection Dependency-Track

| Option | Ce que c'est | Prix connu | Limites connues |
|---|---|---|---|
| 1a. Pas de Dependency-Track | Grafana reste la vue des entrées trouvées et réelles (séries de la pièce 7) | aucun | pas de portefeuille ni de politiques CEL ; pas de vue par composant entre projets ; écart avec `docs/02`, à écrire |
| 1b. Dependency-Track v5 en projection | Service neuf (PostgreSQL), alimenté depuis les attestations signées : SBOM fusionné (CycloneDX) et VEX convertis d'OpenVEX en VEX CycloneDX ; « ré-ingest testé » comme parade de `docs/04` | brique neuve, non estimée ; un convertisseur OpenVEX → CycloneDX à écrire ou à choisir (`vexctl` est noté « peu actif » dans `docs/00`) ; un service de plus à journaliser dans Grafana | un seul mainteneur fusionne ; la conversion peut perdre de l'information (à mesurer) ; le non-support d'OpenVEX est à revérifier d'abord |
| 1c. Reporter en fin de projet | Rangé avec Konflux, le build récursif et Keycloak | aucun maintenant | l'ADR 0004 se clôt sans cette partie, ou reste « À rédiger » |

## Besoin 2 : score « vulnérabilités après VEX »

| Option | Ce que c'est | Prix connu | Limites connues |
|---|---|---|---|
| 2a. Grille de gravité × EPSS | Poids fixes par gravité en mots, multipliés par l'EPSS (une valeur par défaut quand il manque), sur les entrées réelles | un calcul sur les séries ou le prédicat ; règles à écrire et à versionner | ce n'est pas « CVSS × EPSS » de `docs/02` : `docs/02` serait à amender ; la valeur par défaut d'EPSS pèse lourd (3 sur 6 absents pour sample-app) |
| 2b. Ajouter le CVSS au prédicat | Le scanner recopie le score CVSS de Grype dans chaque entrée | changement de `outil/main.go`, nouvelle image `outils-scan`, poses des pièces 3 et 5 à refaire, porte et `entrees-scan` relus | plus de travail ; même problème d'EPSS absent |
| 2c. Pas de score, des comptes | Les comptes réels par gravité (déjà dans Prometheus) tiennent lieu de la part « vulnérabilités » | aucun | pas de score v1 tel que `docs/02` le décrit ; à écrire dans l'ADR |

Le score v1 entier (intégrité, santé amont, licences) dépasse l'ADR 0004 : seule sa part « vulnérabilités après VEX » y est attendue.

## Besoin 3 : KPI de couverture VEX

| Option | Définition | Calculable aujourd'hui |
|---|---|---|
| 3a. Couverture des entrées | entrées écartées par un VEX / entrées trouvées, par dépôt | oui (`scan_entrees_vex` / `scan_entrees`) |
| 3b. Couverture des KEV | KEV écartées / KEV trouvées ; « KEV ouvertes » = trouvées − écartées | oui (`scan_entrees_kev_vex`, `scan_entrees_kev`) ; vaut 0/0 aujourd'hui (aucune KEV) |
| 3c. Santé des VEX | documents passés, rejetés, écartées sans exemption, replis, et VEX à moins de N jours de leur échéance (30 jours) | en partie : les comptes existent ; l'échéance n'est que dans les lignes `ECHEANCE\|` de `signer-vex.sh`, pas dans Prometheus |
| 3d. Délai de correction des KEV | temps entre l'apparition d'une KEV et sa disparition (correctif ou VEX) | non : demande un historique par entrée (Loki le contient, aucune règle ne le calcule) |

Les options 3a à 3d ne s'excluent pas. Un tableau de bord Grafana qui les affiche est un besoin à part (aucun n'existe).

## Questions au propriétaire

1. Dependency-Track : 1a, 1b ou 1c ?
2. Part « vulnérabilités après VEX » du score : 2a, 2b ou 2c ?
3. KPI de couverture VEX : lesquels parmi 3a à 3d ? Avec un tableau de bord Grafana ?

Les réponses seront écrites dans l'ADR 0004, verbatim, avec la date ; l'ADR ne passera de « À rédiger » à une autre valeur que sur décision du propriétaire.

## Corrections après relecture du conseiller (note de 2026-11-23T22:05:07Z ; rien n'est réécrit au-dessus)

- **EPSS : les comptes ci-dessus sont inversés.** Le jq comptait les EPSS **présents**. Les entrées **sans** EPSS sont 3 sur 6 pour sample-app, **3 sur 67** pour le deb et 3 sur 13 pour le témoin G6. Mesuré par jq entre 22:04:20 et 22:04:40 UTC : ce sont exactement les entrées **sans identifiant CVE** (ni en id ni en alias : `GHSA-3fxj-6jh8-hvhx`, `GO-2026-5775`, `GO-2026-5777`), et toutes celles qui ont un CVE ont un EPSS (3 sur 3, 64 sur 64). L'EPSS est donné par CVE. Pour l'option 2a, la valeur par défaut d'EPSS pèse donc sur les entrées sans CVE, pas sur la moitié des entrées.
- **Option 2a** : les séries de Prometheus ne portent pas l'EPSS ; le calcul se fait depuis le prédicat signé ou les lignes de Loki (qui portent `epss`), pas depuis les séries.
- **Option 2b** : `outil/main.go` ne lit aucun champ CVSS dans la sortie de Grype, et aucune sortie de Grype archivée dans le dépôt ne contient `cvss` (grep du 23/11, entre 22:04:20 et 22:04:40 UTC) : la présence d'un CVSS dans la sortie de Grype 0.104.1 n'est **pas mesurée**.
- **Option 3c** : l'horodatage de chaque document VEX passé est déjà dans Loki (`vexTimestamp`), et chaque entrée écartée porte `vex` (statut, horodatage). L'échéance se déduit donc de Loki ; elle manque seulement dans Prometheus.
- **Unité de compte** : une entrée est un couple (identifiant, PURL), pas une CVE. Mesuré à 22:04:40 UTC sur les deux prédicats archivés : **aucun identifiant n'est l'alias d'une autre entrée, et aucun alias n'est partagé** par deux entrées. Pas de double compte visible aujourd'hui pour 2a et 3a ; à recontrôler à chaque base Grype (le témoin G6 du 04/11 avait `GO-2026-5774` avec l'alias `GHSA-3fxj-6jh8-hvhx`, que le scan du 23/11 liste seul).
- **« Aucun tableau de bord »** : à lire « aucun fichier hors de `resultats/` ne nomme ces séries, hors de la 07a » (la recherche excluait `resultats/`).
- **Dependency-Track** : « ni OpenVEX ni CSAF » reste **non revérifié** dans la documentation publique de la v5 ; c'est ce point qui fixe le prix de l'option 1b. À relire avant de trancher 1b.

## Dependency-Track : formats VEX revérifiés dans la documentation publique (note de 2026-11-23T23:02:02Z ; lecture publique seule, pendant la reprise du rejeu)

Lu le 23/11 entre 23:00 et 23:02 UTC (une recherche, puis quatre pages lues par un agent de lecture, toutes en HTTP 200) :
- **v5 (« next »)**, [VEX and VDR documents](https://dependencytrack.github.io/docs/next/reference/vex-and-vdr/) : Dependency-Track « imports CycloneDX VEX documents to apply analysis decisions to existing findings » ; `POST /api/v1/vex` ou `PUT /api/v1/vex` ; le document est validé contre le schéma CycloneDX, un écart donne un 400 ; l'import ne crée ni composant ni finding, il applique des décisions d'analyse aux findings existants. **OpenVEX et CSAF ne sont pas mentionnés.**
- **v5**, [File formats](https://dependencytrack.github.io/docs/next/reference/file-formats/) : CycloneDX est le seul format accepté pour les SBOM ; le VEX y figure en export (`GET /api/v1/vex/cyclonedx/project/{uuid}`). OpenVEX et CSAF non mentionnés.
- **v4**, [Executive Order 14028](https://docs.dependencytrack.org/usage/executive-order-14028/) : « Supports the OWASP CycloneDX VEX format ». OpenVEX et CSAF non mentionnés.
- L'issue [DependencyTrack/dependency-track#3584](https://github.com/DependencyTrack/dependency-track/issues/3584) porte sur l'import des SBOM CycloneDX 1.6 (fermée le 15/05/2024), pas sur OpenVEX ni CSAF.

**Conclusion, avec sa limite** : la documentation de la v5 ne décrit que l'import de VEX CycloneDX ; l'affirmation de `docs/00` (« ni CSAF ni OpenVEX ») est **cohérente avec la documentation**, sans preuve d'absence dans le code (notes de version et code non lus). Pour l'option 1b, une conversion OpenVEX → VEX CycloneDX reste donc nécessaire, et l'import n'agit que sur des findings que Dependency-Track a déjà calculés lui-même (à partir du SBOM), pas sur ceux de Grype.
