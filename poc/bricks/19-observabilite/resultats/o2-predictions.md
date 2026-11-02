# O2, prédictions écrites avant toute exécution (2026-11-02T16:58:26Z)

Rien n'est encore installé ni appliqué : ces prédictions précèdent l'accord d'installation du propriétaire.

1. **Archives** : sha256 conformes aux valeurs relevées en O1 ; `gh attestation verify` réussit pour Prometheus 3.13.5 (prédicat release v0.2) ; aucune vérification autre que le sha256 pour Alertmanager.
2. **Noms dans `resourceNames`** : le nom contrôlé par l'API pour `services/proxy` est celui de l'URL, port compris (`kyverno-svc-metrics:8000`, `https:openbao:8200`) : `can-i` répond `yes` pour les trois et les requêtes réelles rendent 200 ; `no` pour Secret, pod, journal, création, et pour un autre service ou port (`kyverno-svc:443`, `https:openbao:8201`, TSA) ; 403 sur `/api/v1/namespaces/openbao/secrets`.
3. **OpenBao** après `telemetry` : `/v1/sys/metrics?format=prometheus` en 200 sans jeton ; une métrique d'état de descellement existe (nom à relever, du type `vault_core_unsealed` ou `openbao_core_unsealed`) ; **scellé, l'endpoint ne répond plus en 200** : A1 devra alors reposer sur l'échec de collecte (`up == 0`), à mesurer en O4.
4. **Zot** avec l'extension : `/metrics` lisible sans authentification (lecture anonyme déjà permise) ; sinon, un compte de lecture htpasswd sera nécessaire (arrêt et décision).
5. **Forgejo** : `/metrics` en 401 ou 403 sans jeton, 200 avec le jeton.
6. **Connexion** de `sc-stockage` vers l'API de k3s (192.168.161.11:6443) ouverte : toutes les cibles `up` en moins de 35 s.
7. **Lecture seule** : `delete_series` refusé (API d'administration désactivée, HTTP 4xx), `/-/reload` et `/-/quit` refusés (lifecycle désactivé), `/api/v1/write` refusé (récepteur remote-write désactivé) ; écoute sur 127.0.0.1 seulement (9090, 9093, 9095, 9101) ; aucun port de grappe d'Alertmanager (9094).
8. **Rejeu ciblé de la 08** : OpenBao revient scellé après le changement de configuration, descellé par `deverrouiller`, même clé Transit (étape `controle`) ; Zot et Forgejo redémarrés sans perte ; la porte admet toujours l'image réelle de la 08.

## Complément Zot, décision (a) du propriétaire (2026-11-02T17:39:36Z, avant toute modification)

9. Avec `accessControl.metrics.users = ["poc-metriques"]` et le compte htpasswd `poc-metriques` : `/metrics` en 200 avec ce compte, 401 sans authentification, 401 ou 403 avec un autre compte (`poc-ecriture`, pas dans la liste).
10. `poc-metriques` n'est cité dans aucune politique de dépôt : il garde la lecture des dépôts par l'`anonymousPolicy` (lecture anonyme déjà permise), mais une écriture (création d'un blob par POST) est refusée (401 ou 403).
11. Après le redémarrage de Zot : `/v2/` en 200, cible `zot` `up` ; les autres cibles restent `up`.
