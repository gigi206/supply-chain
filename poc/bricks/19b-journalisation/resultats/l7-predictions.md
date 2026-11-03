# L7, domaine de replay dans Grafana : prédictions (03/11/2026, 15:43 UTC, avant exécution)

Demande du propriétaire du 03/11/2026 : « Replay dans Grafana ». Origine : clôture de la brique 10, point « non fait » ([README de la 10](../../10-independent-replay/README.md), section « Clôture »).

## Étape `corroborer_vsa` (lecture seule)

Commande : `JALON=l7 mise run journalisation -- corroborer_vsa`. Requêtes faites par le compte `auditeur` (Viewer) à travers l'API de Grafana (`/api/ds/query`). Rien n'est écrit dans Loki, dans Zot ni dans le cluster.

Faits de départ :
- la VSA a été poussée par l'hôte, avec le compte `poc-replay`, à partir de 15:00:55 UTC (en-tête de [`r5-pousser_vsa.log`](../../10-independent-replay/resultats/r5-pousser_vsa.log)), sous forme du manifeste `sha256:c1bfbcbd…` dans `builds/vsa/sample-app`, avec deux blobs (le bundle et une config vide) ;
- `timeVerified` vaut `2026-11-03T14:27:05Z` ([`r5-vsa-enonce.json`](../../10-independent-replay/resultats/r5-vsa-enonce.json)) ;
- en D5, les écritures réussies de `poc-replay` apparaissaient dans l'audit de Zot et dans Loki ; les refus, non ([`d5-predictions.md`](../../10-independent-replay/resultats/d5-predictions.md), point 5) ;
- le push a eu lieu après L6 (08:55 à 08:59 UTC) : la ligne d'audit a été envoyée sous les garanties de D16 et D17 rétablies.

Prédictions :
1. La requête de l'auditeur répond HTTP 200.
2. **Exactement une** ligne d'audit porte `manifests/sha256:c1bfbcbd…` sous `builds/vsa/sample-app`, pour `poc-replay`, avec le statut 201. Son heure de Zot (champ `time`, prédiction faible sur le nom du champ) est comprise entre 15:00:55 et 15:01:30 UTC.
3. Les autres lignes de `poc-replay` sous `builds/vsa/` dans la fenêtre sont les envois des deux blobs, toutes entre 15:00:55 et 15:01:30 UTC. Prédiction faible : quatre lignes (POST 202, puis PUT 201 par blob). Aucune écriture de `poc-replay` sous `builds/vsa/` en dehors de cet intervalle.
4. Verdict `OK` : le push est postérieur à `timeVerified` d'environ 34 min (2 030 à 2 065 s).
5. Contre-épreuve : 0 ligne de données ne contient le marqueur jamais émis.

**Portée** : cette corroboration ne donne qu'une **borne haute** de l'heure du replay (la VSA existait au plus tard au moment du push). La borne basse des 24 h repose sur `timeVerified`, affirmé par le domaine, et sur les compteurs du lien de R4, relevés par l'hôte.

## Résultat de `corroborer_vsa` (03/11/2026, 15:47:05 UTC ; choix du propriétaire : « Oui, lancer »)

[`l7-corroborer_vsa.log`](l7-corroborer_vsa.log) : **les cinq prédictions sont conformes.**
1. HTTP 200. Champs du cadre de données de Grafana : `labels`, `Time`, `Line`, `tsNs`, `labelTypes`, `id`.
2. Une seule ligne `PUT …/builds/vsa/sample-app/manifests/sha256:c1bfbcbd…`, `subject` `poc-replay`, statut 201, `time` à **15:00:59.268 UTC**.
3. Quatre autres lignes, POST 202 puis PUT 201 pour chacun des deux blobs (`7b93e4b3…` et `44136fa3…`), de 15:00:56.382 à 15:00:58.030 UTC. Aucune autre écriture de `poc-replay` sous `builds/vsa/` entre 14:00 et 16:00 UTC. Toutes viennent de `192.168.161.1`, l'hôte, qui transporte la VSA.
4. `OK` : le push est postérieur à `timeVerified` de **2 034 s**.
5. Contre-épreuve : 0 ligne.

**Portée, inchangée** : l'heure du replay est bornée par le haut, à 15:00:59 UTC au plus tard, par un témoin extérieur au domaine (l'audit de Zot, lu par l'auditeur dans Grafana). La borne basse des 24 h repose toujours sur `timeVerified`, affirmé par le domaine, et sur les compteurs du lien de R4.
