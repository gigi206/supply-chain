# L2, prédictions écrites avant toute exécution (2026-11-02T20:43:24Z)

Préparation à sec : rien installé. Ordre proposé :
`JALON=l2 mise run journalisation -- certificats installer controle`, puis `JALON=l2 mise run observabilite -- regles deployer` (19, alerte de disque).

1. **`certificats`** : quatre certificats vérifiés par la CA du PoC. `loki` et `grafana` sont serveur (SAN `sc-stockage.poc.test` et `192.168.161.13`) ; `grafana-client` et `controle` sont clients, sous `clients.poc.test`, et la contrainte de noms de la CA les admet. Clés et mots de passe en 0600.
2. **`installer`** :
   - les ports 3001, 3100 et 9096 sont libres avant l'installation (0 écoute) ;
   - les empreintes sont vérifiées de nouveau dans la VM ;
   - `loki -verify-config` accepte la configuration ;
   - versions lues : Loki 3.7.9 et Grafana 13.3.0 ;
   - `loki`, `grafana` et `disque-metriques.timer` sont `active` ; Grafana répond en moins de 2 min ;
   - compte `auditeur` créé (HTTP 200), liste des comptes : `admin` (Admin) et `auditeur` (Viewer).
   - Prédictions faibles :
     - Grafana démarre sous `ProtectSystem=strict` sans autre chemin en écriture que `/var/lib/grafana` ;
     - le `$__file{}` des `secureJsonData` provisionnées est interprété.
3. **`controle`, Loki** :
   - sans certificat client : la poignée TLS échoue (HTTP 000) ;
   - avec `controle` : `/ready` répond 200, la ligne témoin est écrite (204) puis relue ;
   - **demande de suppression refusée** (4xx, `deletion_mode: disabled` ; le code exact n'est pas connu).
4. **`controle`, Grafana** :
   - anonyme : 401 ;
   - santé des deux sources : OK ;
   - l'auditeur lit la ligne témoin dans Loki **à travers Grafana**, et lit `up` dans Prometheus ;
   - création de tableau et création de source par l'auditeur : 403 ;
   - suppression de la source provisionnée par l'administrateur : refusée (prédiction faible : Grafana 13 refuse la suppression des sources provisionnées, code 4xx non connu).
5. **Sorties** : aucune connexion établie de `loki` ou de `grafana` hors du réseau du PoC (rapports d'usage, mises à jour, nouvelles et préinstallation de plugins coupés).
6. **Disque** : `disque.prom` contient `point="/"` à environ 0,36 à 0,40 (35 % avant Grafana, plus environ 1,2 Go une fois l'archive extraite). `/var/lib` est sur le même système de fichiers, donc une seule ligne.
7. **Alerte de disque (19)** : 9 règles, tests réussis (déjà vérifiés sur l'hôte par promtool 3.13.5 : `SUCCESS` ; le test échoue si le seuil passe à 0,82) ; règle chargée, inactive.
8. **Mémoire** : `sc-stockage` garde plus de 3 Gi disponibles avec Loki et Grafana (prédiction faible : Loki 200 à 400 Mi, Grafana 150 à 300 Mi).

## Additif (2026-11-02T20:46:33Z, avant toute exécution, après relecture)

Changements :
- `domain = 192.168.161.13` au lieu de `sc-stockage.poc.test`, que l'hôte ne résout pas (`getent hosts`) ;
- `router_logging = true`, parce que Grafana OSS n'a pas de section `[auditing]` dans `defaults.ini` (lu) ;
- nouveaux contrôles.

9. **Navigateur** : `POST /login` en tant qu'auditeur répond 200 avec un cookie `grafana_session`. `GET /api/user` avec ce cookie et l'en-tête `Origin` répond 200 (`auditeur`). Sans session, `/` redirige vers `https://192.168.161.13:3001/login`.
10. **Trace des lectures** : au moins une requête `/api/ds/query` de l'auditeur figure dans le journal de Grafana, avec son `userId`. Format non vérifié : prédiction faible.
11. **Appels vers Grafana Labs** : 0 ligne mentionnant `grafana.com` ou `stats.grafana` dans les journaux de `loki` et `grafana`. La prédiction 5 est reformulée : **aucune connexion sortante établie à l'instant du contrôle**, tout étant coupé dans les configurations. Une seule capture de `ss` ne prouve pas l'absence d'appels périodiques.
