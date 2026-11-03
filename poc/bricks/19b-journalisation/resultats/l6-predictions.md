# L6, TLS sur le gRPC de Loki et du relais : prédictions (écrites le 03/11/2026, première version vers 08:45 UTC, revue après relecture de l'advisor à 08:50 UTC, avant toute exécution)

Choix du propriétaire (03/11/2026) : « TLS sur le gRPC (b) ». Constat : [`constat-grpc-relais.log`](constat-grpc-relais.log). Essai local sur l'hôte, sans toucher sc-stockage : [`correctif-grpc-essai-local.log`](correctif-grpc-essai-local.log). Il en a tiré une correction du gabarit : `frontend_worker.grpc_client_config` est refusé par `-verify-config` à côté de `query_frontend_grpc_client` et de `query_scheduler_grpc_client`.

## Le correctif

- **`config/loki.yaml`**
  - `server.grpc_tls_config` : `loki.crt`, avec `RequireAndVerifyClientCert` sur la CA du PoC, comme `http_tls_config`.
  - Clients gRPC internes, avec l'ancre YAML `tls_interne` : `ingester_client`, `frontend`, `frontend_worker` (`query_frontend_grpc_client`, `query_scheduler_grpc_client`), `query_scheduler`, `compactor_grpc_client` et `ruler.ruler_client`.
  - Ces clients présentent le nouveau certificat `loki-interne` de la CA du PoC, avec `tls_server_name: sc-stockage.poc.test`.
- **`config/alloy/stockage/relais.alloy`**
  - Un bloc `grpc` par source.
  - Boucle locale, ports fixes 3511 (confiance) et 3512 (build).
  - Même certificat et même autorité que le bloc `http` de la source.
- **`journalisation.sh`**
  - Jalon L6 : étapes `certificats_grpc`, `avant_grpc`, `grpc_tls`, `controle_grpc` et `pertes_grpc`.
  - `grpc_tls` prend des copies de sauvegarde (`*.avant-l6`) et valide sur une copie. Il recharge Alloy par SIGHUP, ce qui ne redémarre que le serveur du relais et garde la file de `loki.write` (code : `NeedsRestart`). Il redémarre ensuite Loki. Si un service ne revient pas, il revient en arrière automatiquement.
  - Le tunnel SSH de `controle_grpc` est fermé par un piège, même en cas d'échec.
  - `loki-interne` est ajouté aux étapes `certificats` et `installer` de L2, pour qu'un rejeu complet reste cohérent.

Commande prévue :

```
JALON=l6 mise run journalisation -- certificats_grpc avant_grpc grpc_tls controle_grpc controle_l3 temoins pertes_grpc
```

## Prédictions

1. **`certificats_grpc`** : `loki-interne.crt` vérifié `OK` par la CA du PoC (`sslclient`), clé en 600.
2. **`avant_grpc`** (état actuel, rien de modifié) :
   - Ports :
     - Alloy écoute sur 3501 et 3502 (`192.168.161.13`), 12345 (boucle locale) et **deux ports au hasard sur `*`**. Les numéros peuvent différer de 35459 et 38365 si Alloy a redémarré depuis.
     - Loki écoute sur 3100 et sur 9096 (boucle locale).
   - Sondes :
     - Sur les deux ports au hasard et sur 9096, `httpgrpc` en clair répond `grpc-status: 0` et « ready ».
     - En TLS, la poignée échoue, puisque ces serveurs ne parlent pas TLS.
   - Depuis l'hôte, 3100, 3501, 3502 et les deux ports au hasard sont ouverts.
3. **`grpc_tls`** :
   - `-verify-config` : « config is valid ». Alloy : configuration valide.
   - Alloy, après SIGHUP : même PID, 3511 et 3512 en écoute sur la boucle locale en moins de 30 s, et plus aucun port sur `*`.
   - Loki `active`, `/ready` à 200 en moins de 60 s.
   - Erreurs depuis le redémarrage : seulement les bruits connus (`deletion is not available`, `empty ring` au démarrage).
   - Aucune erreur TLS ni `transport` sur les clients internes de Loki.
4. **`controle_grpc`** :
   - Ports d'écoute :
     - Loki : 3100 sur `192.168.161.13`, 9096 sur `127.0.0.1`.
     - Alloy : 3501 et 3502 sur `192.168.161.13` ; 3511, 3512 et 12345 sur `127.0.0.1`.
     - **Plus aucun port sur `*`.**
   - Sondes sur 9096, 3511 et 3512 :
     - En clair : échec du cadrage HTTP/2.
     - En TLS sans certificat : `certificate required`.
   - Depuis l'hôte, seuls 3100, 3501 et 3502 sont tenus hors boucle locale par Loki et Alloy.
   - Matrice des certificats (`grpc-status: 0` et « ready » si accepté, `unknown ca` sinon) :

     | Port | `loki-interne` | `controle` | `alloy-sc-confiance` | `alloy-sc-build` |
     |---|---|---|---|---|
     | 9096 (Loki) | accepté | accepté | refusé | refusé |
     | 3511 (relais, confiance) | refusé | refusé | accepté | refusé |
     | 3512 (relais, build) | refusé | refusé | refusé | accepté |

     `controle` est accepté sur 9096 parce que Loki accepte toute la CA du PoC, comme sur 3100 (limite de D16, inchangée).
5. **`controle_l3`** (étape existante, rejouée) :
   - Dans le tableau des 10 dernières minutes, `sc-confiance`, `sc-build` et `sc-stockage` ont des lignes, dont celles des sources reçues par le relais (`journal`, `pods`, `audit-k8s`). C'est ce tableau qui prouve que la collecte reprend après L6. La liste des sources porte sur 24 h et inclut des lignes d'avant L6.
   - D17 inchangée : le certificat de `sc-build` est refusé par Loki et par le port 3501, et sa ligne étiquetée `noeud=sc-confiance` est stockée sous `noeud=sc-build`.
   - L'auditeur lit le journal de k3s par Grafana.
   - Alloy `active` sur les trois VM. D'éventuelles erreurs d'envoi sont limitées à la fenêtre de redémarrage de Loki.
6. **`temoins`** (étape existante, rejouée) : chaque témoin est lu par l'auditeur à travers Grafana en moins de 2 min. Contre-épreuve comprise.
7. **`pertes_grpc`, pas de perte** : sur la fenêtre qui va de 2 min avant `grpc_tls` à 1 min avant le relevé, le nombre de battements est le même dans journald et dans Loki, pour chacune des trois VM.
   - Les lignes de `sc-confiance` et de `sc-build` passent par le relais rechargé.
   - Celles de `sc-stockage` vont directement dans Loki redémarré, réessayées par `loki.write` ; le WAL de Loki est activé.
   - `SourceMuette` reste `inactive`, mais ne prouverait rien sur une coupure de quelques secondes.

## Limites connues avant l'exécution

- La version de dskit embarquée par Loki 3.7.9 n'a pas été lue. Le comportement est établi par l'essai local du binaire de la release vérifiée, pas par son code.
- `controle` reste accepté par le gRPC de Loki : le correctif ferme l'accès sans certificat, pas la limite de D16, où tout porteur d'un certificat de la CA du PoC lit et écrit.
- Les clients gRPC internes non configurés (index gateway, bloom, pattern ingester, limites d'ingestion) ne servent pas dans cette configuration : ces fonctions sont désactivées, ou en mode binaire unique sans passerelle d'index. S'ils étaient activés, ils échoueraient en clair contre le serveur TLS. L'essai local a démarré tous les services sans erreur TLS.
- L'écriture sans certificat par le gRPC n'a pas été essayée avant le correctif. Le propriétaire n'a pas donné son accord pour un témoin écrit par ce chemin.

## Ce que le passage modifie ou écrit

- Sur `sc-stockage` :
  - `loki-interne` (certificat et clé) dans `/etc/loki/tls/`, `loki.yaml` et `relais.alloy` remplacés, copies `*.avant-l6` ;
  - Alloy rechargé et Loki redémarré, d'où une interruption de la lecture par Grafana de quelques dizaines de secondes.
- `controle_l3` écrit une ligne de contrôle par le port 3502.
- `temoins` écrit des lignes témoins, dont un push vers Zot (`essais-19b/temoin`, résidu déjà consigné), comme en L4.
- Rien n'est modifié sur le cluster, `sc-confiance` ni `sc-build`.

## Point ouvert, sans lien avec L6

Le journal de Loki contient 47 refus `ingestion rate limit exceeded` : 29 le 02/11/2026 à 21:03 et 18 à 21:04 UTC, au démarrage de L3, pendant la relecture de l'historique. Le journal d'Alloy ne contient aucun « error sending batch » sur les trois VM. Le chemin des lignes refusées (réessayées ou perdues) n'est pas établi.

## Additif du 03/11/2026, après l'exécution (08:55 à 08:59 UTC)

- Les sept prédictions sont conformes. Le détail est dans le README de la brique (« L6, exécuté »).
- **Premier passage de `controle_grpc` archivé** ([`l6-controle_grpc-premier-passage.log`](l6-controle_grpc-premier-passage.log)). C'est un défaut du script, pas des services : la trame gRPC tronquée par bash (octets nuls) donnait `grpc-status: 2` aux certificats acceptés, et le piège du tunnel lisait une variable locale détruite. Le script est corrigé, et le second passage est conforme.
- **Écart sur la prédiction 3** : un push refusé (500, `empty ring`) pendant le démarrage de Loki, et quatre `context canceled` à l'arrêt de l'ancien querier. Le push a été réessayé par l'Alloy de `sc-stockage` (48e nouvelle tentative), sans perte.
- **Prédiction 5, correction** : le tableau des 10 dernières minutes, relevé 40 s après le redémarrage, ne prouve pas la reprise de la collecte. La version revue de ces prédictions affirmait à tort le contraire. La reprise est prouvée par les témoins, tous écrits après 08:56, et par les battements.
- **Prédiction 7** : le battement de `sc-build` de 08:55:21 est tombé pendant l'arrêt de Loki (08:55:12 à 08:55:31) et a été livré. `loki_write_dropped_entries_total` vaut 0 sur les trois VM.
- **Point ouvert résolu** : les 47 refus de débit du démarrage de L3 correspondent aux 47 nouvelles tentatives de l'Alloy de `sc-stockage`, sans perte ([`l6-complement.log`](l6-complement.log)).
