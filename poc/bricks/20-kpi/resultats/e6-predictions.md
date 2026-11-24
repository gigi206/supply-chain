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

## Résultat des premiers passages, et second passage 1 (note de 2026-11-24T21:43:44Z)

- **Passage 1** ([journal](e6-promql-banc.log), 21:42:11 UTC) : 28 cas, **15 écarts, tous dus à une faute du témoin** : `NaN` écrit comme une chaîne, que le YAML de `promtool` refuse ; aucune requête du tableau n'a donc été évaluée, et les 14 mutants sont « erreur », pas « refusé ». Les règles d'alerte sont conformes : 11 cas, 0 écart, 6 mutants refusés.
- **Passage 2** ([journal](e6-tableau-banc.log), 21:43:22 UTC) : 22 cas, **0 écart**.
- **Passage 3** ([journal](e6-tableau-sec.log), 21:43:32 UTC) : 31 cas, **0 écart**.

Correctif du témoin : `.nan`. Le tableau et ses requêtes ne changent pas. Attendu du second passage 1 (`SUFFIXE=-2`) : 28 cas, 0 écart. Il reste aveugle : aucun témoin n'a été évalué.

## Second passage 1, et troisième (note de 2026-11-24T21:45:59Z)

[Second passage](e6-promql-banc-2.log) (21:43:46 UTC) : 28 cas, **1 écart**. `promtool` ne tient pas deux `NaN` pour égaux, même attendu et obtenu. **Ce que ce journal ne prouve pas** : ses 14 lignes « refusé » de mutants du tableau, car le test de base échouait déjà ; un mutant sans effet y aurait été « refusé » aussi. Les mutants de règles ne sont pas touchés (leur test de base passe).

Corrections, sans changer ni le tableau ni les requêtes :
- la requête à `NaN` attendu (11A, état mixte) devient deux cas : les nombres, puis l'ensemble des `NaN` ; donc 117 cas pour `promtool` ;
- un mutant du tableau ne compte que si le test de base passe **et** si la seule requête en échec est la mutée.

Attendu du troisième passage (`SUFFIXE=-3`) : 28 cas, 0 écart ; les 28 autres requêtes ont déjà été évaluées conformes au second (aucun autre échec affiché), donc seuls 11A et les mutants restent aveugles.

## Résultat du troisième passage (note de 2026-11-24T21:47:59Z)

[Journal](e6-promql-banc-3.log), 21:46:02 UTC, dépôt `07521785` : **28 cas, 0 écart** ; 117 cas de `promtool` passés, 14 mutants du tableau refusés sans qu'une autre requête échoue, 6 mutants de règles refusés. Le cas `NaN` (digest scanné sans entrée) est couvert par deux requêtes dérivées, pas par la requête telle quelle.

## Après relecture du conseiller : description du panneau 2, clés non commitées (prédiction de 2026-11-24T21:52:26Z)

- La description du panneau 2 disait « non déployée au 24/11/2026 » : retirée, sinon déployer les règles imposerait une seconde pose du tableau. Aucune requête ne change. Passages refaits : `e6-promql-banc-4.log` (28 cas, 0 écart), `e6-tableau-banc-2.log` (22 cas, 0 écart, même empreinte des panneaux `b679e16a01a0b41a`, qui ne porte pas les descriptions), `e6-tableau-sec-2.log` (31 cas, 0 écart).
- `kpi-pose.sh` refuse une clé publique de l'arbre différente de HEAD. Essai par l'étape `sec` (hôte, sans ssh), dans un clone jetable : `e7-cles-conformes.log`, arbre propre, **4 cas, 0 KO, code 0** ; `e7-cles-changees.log`, une ligne vide ajoutée à la clé de Chains du clone, **1 KO, celui de ce contrôle**, code 1. Le relevé (`verifier`) doit rester « à jour » dans les deux cas : c'est le défaut corrigé.

Résultat (note de 2026-11-24T21:54:26Z) : [`e6-promql-banc-4.log`](e6-promql-banc-4.log) 28 cas, [`e6-tableau-banc-2.log`](e6-tableau-banc-2.log) 22 cas (empreinte `b679e16a01a0b41a`), [`e6-tableau-sec-2.log`](e6-tableau-sec-2.log) 31 cas, **0 écart** ; [`e7-cles-conformes.log`](e7-cles-conformes.log) tenu, [`e7-cles-changees.log`](e7-cles-changees.log) 1 KO, le seul prédit, relevé « à jour » dans les deux cas. Conforme.

## Pose du tableau, prédiction de 2026-11-24T21:57:52Z

Accord du propriétaire (réponse verbatim) : « Tableau seul (Recommandé) ». Les règles d'alerte attendent l'étape 7. Décision sur l'étape 7, verbatim : « Pose au rejeu, sans dates (Recommandé) ».

`ACCORD='Tableau seul (Recommandé)' tableau-pose.sh pose`, journal `e6-tableau-pose.log` : fichier posé identique, rechargement 200, puis contrôle par l'auditeur ; **40 cas, 0 KO**. Retour arrière : `retrait`, sur accord. `journalisation.sh` (19b) copie aussi ce fichier désormais : contrôlé par `bash -n` seulement, non mesuré avant un rejeu.

**Résultat de la pose** ([`e6-tableau-pose.log`](e6-tableau-pose.log), 21:57:56 UTC) : 40 cas, **0 KO**. Conforme.
