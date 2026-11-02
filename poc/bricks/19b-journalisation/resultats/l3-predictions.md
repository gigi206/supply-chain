# L3, prédictions écrites avant toute exécution (2026-11-02T20:59:05Z)

Ordre proposé : `JALON=l3 mise run journalisation -- certificats_l3 evenements openbao_sortie alloy controle_l3`.

1. **`certificats_l3`** :
   - certificat serveur `relais` et certificat client `alloy-stockage` (CA du PoC) ;
   - deux autorités propres aux nœuds, `ca-sc-confiance` et `ca-sc-build`, chacune avec son certificat client `alloy-<vm>` ;
   - **ces deux certificats de nœud ne sont pas vérifiés par la CA du PoC** (« unable to get local issuer certificate ») ;
   - clés en 0600.
2. **`evenements`** : `can-i list events -A` et `watch events.events.k8s.io -A` répondent `yes` ; `get secrets`, `list pods`, `pods/log` et `create events` répondent `no`.
3. **`openbao_sortie`** :
   - avant : `["fichier/"]` ;
   - la ConfigMap est vue par le pod en moins de 2 min ;
   - après le SIGHUP : `fichier/` et `sortie/` (`file_path` `stdout`) ;
   - au moins une ligne `"type":"request"` sur la sortie standard du pod ;
   - **OpenBao reste descellé** (`sealed: false`), sans redémarrage, donc A1 ne se déclenche pas.
   - Prédiction faible : le rechargement par SIGHUP ajoute un device d'audit déclaré. La 08 l'a mesuré pour `fichier/`, seulement après un descellement.
4. **`alloy`**, sur les trois VM :
   - empreinte vérifiée, `alloy validate` réussi, service `active` ;
   - sous un compte non root avec la seule capacité `CAP_DAC_READ_SEARCH` : lecture du journal (`systemd-journal`), de `/var/log/pods`, de l'audit k3s (0600 root) et de l'audit de Zot ;
   - prédiction faible : aucune erreur de lecture.
5. **`controle_l3`, sources présentes dans Loki** :
   - J1 : journaux des trois nœuds ;
   - J2 : pods de `sc-confiance` et de `sc-build` ;
   - J3 : audit k8s ;
   - J4 : événements ;
   - J5 : audit d'OpenBao, par la sortie du pod ;
   - J6 : audit de Zot ;
   - J8 : récepteur d'alertes, par le journal.

   **Chaque requête compte au moins une ligne.** Au premier démarrage, les fichiers existants sont relus depuis le début, et le journal jusqu'à 7 jours. Loki refuse les lignes de plus de 168 h, et des refus pour cette raison peuvent apparaître dans les journaux d'Alloy.
6. **D17** :
   - le certificat de `sc-build` est refusé par Loki à la poignée TLS (code 000) et par le port de `sc-confiance` (000) ;
   - sur son propre port, une ligne qu'il étiquette `noeud=sc-confiance` est **stockée sous `noeud=sc-build`** (prédiction faible : la règle `replace` du relais remplace l'étiquette reçue).
7. **Grafana** : l'auditeur lit le journal de k3s à travers Grafana (HTTP 200, au moins une ligne).
8. **Ressources** : Alloy prend moins de 200 Mi par VM, et `sc-stockage` garde plus de 3 Gi disponibles.
9. **Seuil de la brique** : toujours non atteint après L3. Les événements témoins datés, mesurés source par source en moins de 2 min, et l'alerte « source muette » relèvent de L4.
