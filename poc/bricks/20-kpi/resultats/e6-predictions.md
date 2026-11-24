# Brique 20, étape 6 : tableau « KPI supply-chain » et règles d'alerte, à sec, prédiction

Prédiction écrite le 2026-11-24T21:42:07Z (`date -u`), commitée avant tout passage. Plan relu par le conseiller. Sans accord : hôte et lecture par l'auditeur seulement ; rien n'est posé dans Grafana, ni dans Prometheus, ni sur les VM.

**Aveu** : les séries `kpi_*` de la plateforme ont été lues par l'auditeur à 21:35:58 UTC pour dessiner le tableau, sans prédiction commitée. Les attendus sur le vrai Prometheus (passage 3) **ne sont donc pas aveugles**. Ceux des témoins (passage 1) le sont : aucune requête n'a été évaluée avant cette prédiction, sur aucun moteur.

## Fichiers

- Tableau [`kpi-supply-chain.json`](../../19b-journalisation/config/provisioning/dashboards/tableaux/kpi-supply-chain.json) (sha256 `6b46d45734a9639b`) : 18 panneaux, 29 requêtes. `tableaux.yaml` n'est pas touché. `journalisation.sh` (19b) ne copie que `vulnerabilites-vex.json`, nommé : ce commit ne change donc rien à un rejeu.
- Témoins [`tableau_temoins.py`](../tableau_temoins.py) (`f253396ea4073595`), banc [`promql-banc.sh`](../promql-banc.sh) (`9ac13b63095b7249`).
- Règles [`alertes-kpi.patch`](../alertes-kpi.patch) (`069ec1c12bcdc51f`) : `KpiPassageEnRetard` et `KpiSignatureRefusee`. **Livrées en correctif, pas dans `alertes.yml`**, comme `s6a-alertes-deb.patch` (06) : une fois dans `alertes.yml`, un rejeu de zéro les déploierait, et `absent()` sonnerait tant que l'étape 7 n'est pas câblée.
- Banc Grafana [`tableau-banc.sh`](../tableau-banc.sh) (`1271624ae2d0cb74`), pose [`tableau-pose.sh`](../tableau-pose.sh) (`b5aa711d62f24102`, étape `sec` seule lancée).

## Passage 1 : requêtes et règles, promtool (`e6-promql-banc.log`)

- Archive de Prometheus 3.13.5 : sha256 attendu. Requêtes : 29, dans 4 états, 116 cas, **passés**.
- **14 mutants du tableau refusés** (dénominateur, taux, scan à 0 entrée, faux zéro par `vector(0)`, jointure sans dépôt ou sans date d'ouverture, `or` aux étiquettes différentes…).
- Correctif appliqué ; `check rules` valide ; 2 règles de plus ; une ligne `expr:` par alerte ; tous les tests passés, anciens compris ; **6 mutants de règles refusés**.
- Bilan attendu : **28 cas, 0 écart** (archive, témoins écrits, requêtes, 14 mutants, correctif, check, nombre de règles, lignes `expr`, tests, 6 mutants).
- Point le moins sûr : la comparaison d'un `NaN` attendu par `promtool` (scan à 0 entrée).

## Passage 2 : Grafana 13.3.0 jetable (`e6-tableau-banc.log`)

Attendu : 0 écart ; tableau absent avant, servi après, 18 panneaux, dossier PoC, provisionné ; enregistrement et suppression refusés (400), enregistrement par un Viewer refusé (403) ; « Vulnérabilités et VEX » inchangé.

## Passage 3 : vrai Prometheus, par l'auditeur (`e6-tableau-sec.log`)

Attendu : tableau absent (404), « Vulnérabilités et VEX » servi (200), 29 requêtes à 200 sans erreur, avec le nombre de séries écrit dans `tableau-pose.sh` (4 digests, 3 scannés, 5 clés, 24 pins, 0 KEV) : **31 cas, 0 écart**. Valeurs consignées, non comparées : L3 1/4, replay 2/4, provenance 4/4, un digest sans scan (le rpm), contrôles à 0.

## Non couvert

Affichage réel dans Grafana (dont `noValue`, couleurs, lisibilité) ; Alertmanager ; pose ; collecte. Une série qui porte une étiquette de plus, un jour, changerait le nombre de séries sans erreur.
