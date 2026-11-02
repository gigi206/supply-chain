# O4, prédictions écrites avant toute exécution (2026-11-02T18:29:04Z)

Étapes préparées à sec dans [`observabilite.sh`](../observabilite.sh) (`fichiers`, `a1` à `a6`) : rien n'est exécuté sur les VM ni sur le cluster avant l'accord du propriétaire.
Ordre proposé : `JALON=o4 mise run observabilite -- regles deployer fichiers a3 a4 a6 a5 a1 a2`.

Délais communs : collecte toutes les 30 s, évaluation toutes les 30 s, `group_wait` de 10 s, `group_interval` de 1 min (Alertmanager).

1. **`regles` et `deployer` (A4 avec `for: 5m`)** : `promtool test rules` réussit, y compris les deux nouveaux cas de A4 (absence en attente à 4 min, déclenchée à 6 min ; collecte manquée pendant 2 min sans alerte). 7 règles `ok` après redéploiement.
2. **`fichiers`** : la cible `fichiers` reste `up` ; les quatre métriques des fichiers sont toujours servies (`sync_*` à trois noms, `certificat_expiration_timestamp_seconds`). `/tmp/regles-mutation` est supprimé.
3. **A3, A4, A6 (séries de test dans `essais-o4.prom`)** : la collecte des fichiers ne tombe jamais (`min_over_time(up)` = 1). Lignes `# TYPE` en double entre fichiers déjà tolérées (deux `sync.prom` servis ensemble depuis O2). Le fichier de test n'en contient pas.
   - A3 et A6 : `firing` en moins de 90 s ; une notification `firing` puis `resolved` dans le journal du récepteur. `resolved` arrive moins de 2 min 30 s après le retour de la valeur.
   - A4 : `pending` en moins de 90 s, puis `firing` 5 min plus tard (`for: 5m`). La résolution suit le même délai qu'A3.
4. **A5** : les créations en dry-run serveur sont comptées dans `kyverno_admission_requests_total`.
   - Indice : 2 refus dans `tsa` relevés en O1, peut-être dus à la sonde de la 08 (en dry-run), origine non vérifiée. Ce n'est pas une preuve : si le compteur brut ne bouge pas, A5 ne se déclenche pas et l'étape s'arrête en KO.
   - Série `tsa`/`Pod`/`create` existante (pas de redémarrage de Kyverno depuis O1) : branche `increase`, extrapolée aux bords de la fenêtre. Dix échantillons couvrent 270 s, le facteur est donc 300/270.
   - **4 refus : valeur maximale ≈ 4,44, pas d'alerte.**
   - **10 refus : ≈ 11,1, `firing` en moins de 90 s, résolue 5 à 6 min après la rafale.**
   - Conséquence à consigner : **5 refus donneraient ≈ 5,56 et déclencheraient A5**. Le seuil réel est « au moins 5 », non « plus de 5 ».
5. **A1 (pod d'OpenBao supprimé)** : le pod redémarre scellé, n'est pas `Ready` et le proxy répond 503 (état mesuré en O2).
   - A1 passe par la branche `up{job="openbao"} == 0` (Kyverno `up`). `vault_core_unsealed` n'a pas de valeur récente.
   - `pending` en moins de 60 s, `firing` 1 min plus tard ; notification `firing`.
   - Après le descellement : pod `Ready`, `resolved` en moins de 2 min 30 s, clé Transit `chains` inchangée.
   - Effets de bord : des passages du CronJob `horodatage` peuvent échouer pendant le scellement. Un passage d'`horodatage` et de `rattrapage` réussit dans les 6 min après le descellement. TSA prête.
   - Pas de A2 : aucune signature n'est demandée pendant la fenêtre.
6. **A2 (`decision3` de la 08)** : la mesure reproduit sa preuve, avec au moins 5 PUT `.att` refusés et un objet `signed=failed`.
   - Le compteur `storage` augmente du nombre de tentatives (7 ou 8 aux passages précédents) sur `pipelinerun` ou, si c'est le TaskRun qui échoue, sur une série `taskrun` neuve.
   - `firing` pendant ou juste après la mesure, avec une notification `firing`.
   - **Résolution au moins 10 min après le dernier échec** (fenêtre de `increase`), puis `resolved`.
   - Le journal de la 08 est copié dans `o4-a2-preuves-decision3.log`, puis rendu à sa version versionnée. Le `chrono.tsv` de la 08 reçoit deux lignes datées d'O4.
7. **Durée totale** : environ 50 min. Le détail : `regles deployer fichiers` 2 min, A3 4 min, A4 9 min, A6 4 min, A5 13 min, A1 7 à 12 min, A2 14 min.
