# L4, prédictions écrites avant toute exécution (2026-11-02T21:09:51Z)

Ordre proposé :
1. `JALON=l4 mise run journalisation -- prometheus_alloy` ;
2. `JALON=l4 mise run observabilite -- regles deployer` (19 : SourceMuette et LokiInjoignable) ;
3. `JALON=l4 mise run journalisation -- temoins secrets muette`.

1. **`prometheus_alloy`** : configuration valide, cible `alloy` `up`, toutes les autres cibles toujours `up`.
2. **Règles** : 11 règles et tests réussis, comme sur l'hôte (`SUCCESS` ; deux mutations détectées). `SourceMuette` et `LokiInjoignable` sont chargées et `inactive`.
3. **Témoins** : chacun est lu par l'auditeur à travers Grafana, en **moins de 2 min** :
   - J1 : journal des trois nœuds ;
   - J2 : pods de `sc-confiance` (`openbao-0`) et de `sc-build` (agent Cilium), par écriture sur la sortie standard du conteneur ;
   - J3 : nom de la ConfigMap créée puis supprimée, dans l'audit de l'API ;
   - J4 : événement créé ;
   - J5 : chemin `sys/policy/<marqueur>` en clair dans l'audit d'OpenBao (seules les valeurs sont en HMAC, lu dans la doc ; prédiction faible) ;
   - J6 : étiquette poussée par `poc-ecriture` dans `essais-19b/temoin`, dans l'audit de Zot. Prédiction faible : l'audit de Zot porte le nom de l'étiquette. Résidu : l'artefact reste dans Zot, que `poc-ecriture` ne peut pas supprimer ;
   - J8 : ligne du récepteur d'alertes.

   Délai typique : moins de 15 s. Le lot d'Alloy (`batch_wait` par défaut d'environ 1 s) et le relais s'ajoutent à l'interrogation toutes les 2 s.
4. **Secrets** :
   - **0 ligne** de Loki contient la valeur d'un secret connu (jetons, mots de passe, clé de descellement, corps des clés privées de `…/08/secrets`) ;
   - **témoin positif trouvé** (1 ligne) ;
   - export de 300 000 à 400 000 lignes.
5. **Source muette** : Alloy est arrêté sur `sc-build`.
   - `SourceMuette` `{noeud="sc-build"}` passe en `firing` en **6 à 8 min** (fenêtre de 5 min, puis `for: 2m`), avec sa notification `firing`.
   - Après la reprise, **les deux témoins écrits pendant l'arrêt arrivent dans Grafana** (reprise sur la position du journal), en moins de 2 min.
   - Résolution en moins de 3 min, notification `resolved`.
   - 0 entrée abandonnée par Alloy de `sc-build`.
   - Aucune autre alerte, sauf `CollecteEnPanne`, qui ne concerne pas `sc-build`.
6. **Seuil de la brique atteint si 3, 4 et 5 sont conformes.**

Limites connues d'avance :
- `LokiInjoignable` n'est éprouvée que par promtool, pas par un arrêt réel de Loki ;
- l'arrêt d'Alloy de `sc-stockage` relève de `CollecteEnPanne` (`up == 0`, 5 min), non éprouvé ici.
