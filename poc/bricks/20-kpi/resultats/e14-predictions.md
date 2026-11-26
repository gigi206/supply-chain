# Brique 20, étape 14 : déploiement des règles d'alerte KPI, prédiction

Note de 2026-11-26T07:57:18Z, écrite avant le déploiement. Accord du propriétaire (réponse verbatim, à la question « Déployer les alertes de la 20 (je le recommande), ou le banc de signature de Chains ? », dont le prix nommait le correctif appliqué et commité, ssh et sudo, et le redémarrage de Prometheus) : « Comme tu veux mais avance ».

Ce qui est déployé : [`alertes-kpi.patch`](../alertes-kpi.patch), écrit et éprouvé à l'étape 6 ([e6-predictions.md](e6-predictions.md) : 28 cas, 0 écart, 6 mutants de règles refusés). Il ajoute `KpiPassageEnRetard` et `KpiSignatureRefusee` à `alertes.yml` (19), et quatre tests à `alertes-tests.yml`. Les règles attendaient l'étape 7 ; elle est écrite (`rejeu.sh` pose l'exportateur si `TAG_05`), jamais rejouée.

## État avant (relevé à 07:56:31Z par ssh, puis à 07:57:13Z par Grafana)

- `alertes.yml` en place sur `sc-stockage` : sha256 `cf892dc1…`, égal à celui de HEAD (`3aed35d2`). Le déploiement n'emporte donc que le correctif.
- Prometheus actif, 15 règles chargées, toutes saines, aucune hors de l'état `inactive` ; `ALERTS` vide.
- Âge du dernier passage de l'exportateur : 461 s ; `kpi_signatures_refusees` : 20 séries, somme 0. Étiquette `instance` réelle : `127.0.0.1:9101` (les tests disent `local` ; les règles ne filtrent pas dessus).
- Par l'auditeur dans Grafana ([journal](e14-alertes-verif-avant.log), `REGLES=15`) : 8 cas, 0 KO.

## Procédure

1. Correctif appliqué (`git apply`) et commité, après `make reuse` et `tools/secrets-depot.sh`.
2. `JALON=kpi20 mise run observabilite -- regles reference deployer` (journaux `19-observabilite/resultats/kpi20-*.log`) : promtool dans la VM, expressions évaluées sur le vrai Prometheus avant déploiement, puis `install` dans `/etc/prometheus/regles/`, redémarrage, règles lues dans l'API.
3. `alertes-verif.sh` (`REGLES=17`) juste après, puis `SUFFIXE=-2` après un passage du timer de l'exportateur et plus de 10 min après le redémarrage (fin du `for` de `KpiPassageEnRetard`).
4. sha256 du fichier en place comparé à celui du commit.

## Prédictions

- **D1** : `regles` : `check rules` valide, 17 règles ; `test rules` réussi, anciens tests compris. Confiance très bonne (rejoué à l'étape 6 sur le même `alertes.yml`).
- **D2** : `reference` : les deux expressions neuves ne rendent aucun résultat (âge < 2700 s, somme des refus à 0). Confiance bonne.
- **D3** : `deployer` : Prometheus `active` ; 17 règles, toutes `ok`, toutes `inactive`, dont `KpiPassageEnRetard` et `KpiSignatureRefusee`. Confiance très bonne.
- **D4** : sha256 en place = sha256 de `alertes.yml` du commit de l'étape 1. Confiance très bonne.
- **D5** : `alertes-verif.sh` : 8 cas, 0 KO, juste après et au second passage ; aucune alerte `kpi` en attente ou déclenchée. Confiance bonne. Risque : un passage de l'exportateur qui échouerait pendant la fenêtre ; `absent()` ne joue pas, la série est présente et le TSDB survit au redémarrage.
- **D6** : aucune autre alerte (`ALERTS` vide) au second passage. Confiance moyenne : le redémarrage remet à zéro les `for` en cours, mais rien n'était en attente ; des séries `rate()` peuvent manquer d'un point.

## Prix et non couvert

- Un rejeu sans `TAG_05` laisse l'exportateur non posé : `KpiPassageEnRetard` sonnera (voulu), ce qui fera du bruit pendant ce rejeu.
- `promql-banc.sh` (étape 6) applique le correctif à une copie de HEAD : une fois le correctif appliqué, son cas « correctif appliqué » échouera. Le banc reste archivé ; ce n'est pas un défaut des règles.
- Non exercés : le déclenchement réel des deux alertes sur la plateforme et la notification par Alertmanager (couverts par promtool seulement).

## Résultat (note de 2026-11-26T08:09:27Z)

Commits : prédiction `a57a4b01`, correctif appliqué `96a66df7`.

| Prédiction | Verdict |
|---|---|
| D1 | **Tenue** ([journal](../../19-observabilite/resultats/kpi20-regles.log), 07:57:48Z) : promtool 3.13.5, `SUCCESS: 17 rules found`, tests réussis |
| D2 | **Tenue** ([journal](../../19-observabilite/resultats/kpi20-reference.log)) : les deux expressions neuves, et toutes les autres, sans résultat |
| D3 | **Tenue** ([journal](../../19-observabilite/resultats/kpi20-deployer.log), 07:58:01Z) : Prometheus `active`, 17 règles `ok` et `inactive`, dont `KpiPassageEnRetard` et `KpiSignatureRefusee` |
| D4 | **Tenue** (07:58:11Z) : sha256 en place `a2d66710…` = `alertes.yml` de `96a66df7` |
| D5 | **Non tenue au premier passage, faute du contrôle** ([journal](e14-alertes-verif.log), 07:58:11Z) : 1 KO, Grafana lit encore **15** règles. `prometheus_rule_group_rules` vient de la collecte de Prometheus par lui-même : 10 s après le redémarrage, le dernier point était celui d'avant. **Tenue au second** ([journal](e14-alertes-verif-2.log), 08:09:20Z) : 8 cas, 0 KO, 17 règles vues par l'auditeur, aucune alerte `kpi`, âge du passage 323 s (passage de l'exportateur postérieur au redémarrage) |
| D6 | **Tenue** ([relevé](e14-alertes-toutes.log), 08:09:27Z) : aucune alerte en attente ou déclenchée. La commande du passage en arrière-plan qui devait le relever a échoué (jq lisait aussi la date) : relevé refait à part |

**Règles d'alerte KPI déployées**, 0 écart sur les règles elles-mêmes. Leçon : après un redémarrage, attendre une collecte avant de lire une série que Prometheus produit sur lui-même.

Non couverts, inchangés : déclenchement réel des deux alertes sur la plateforme, notification par Alertmanager, rejeu (étape 7).
