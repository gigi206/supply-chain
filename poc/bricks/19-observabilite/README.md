# Brique 19 : observabilité d'exploitation (protocole proposé et validé par le propriétaire le 02/11/2026)

Seuil (README, brique 19) : **les 5 alertes critiques se déclenchent sur incident simulé**. Effort estimé : **0,5 pw** ; décision avec le propriétaire à 1 pw. Rien n'est installé avant l'accord sur ce protocole, puis sur chaque jalon.

Cible (doc 02 §7) : métriques de Tekton, Kyverno, Zot, OpenBao et Forgejo ; Prometheus et Grafana **en lecture seule, hors des nœuds de confiance** ; tableaux de bord versionnés dans git. Les 5 alertes critiques :

| # | Alerte | Source de la métrique | Incident simulé proposé |
|---|---|---|---|
| A1 | OpenBao scellé | OpenBao (`/v1/sys/metrics`, ou état de `sys/seal-status`) | `bao operator seal`, puis descellement (procédure de J3) |
| A2 | Échec de signature de Chains | métriques du contrôleur de Chains | une exécution dont la signature échoue (OpenBao scellé, ou mesure de la décision 3 : PUT `.att` refusé) |
| A3 | Replay non bit-identique | **brique 10, pas encore faite** | voir D2 |
| A4 | Miroir en retard de plus de 24 h | `sync.prom` de la brique 01 (`sync_derniere_reussite_timestamp_seconds`) | timer arrêté et horodatage vieilli (fichier de test), ou règle évaluée avec un seuil réduit |
| A5 | Refus Kyverno anormaux | métriques d'admission de Kyverno | rafale de créations refusées (cas du test 2 ou 4 de la 08) |

**Alerte non critique ajoutée** (décision du propriétaire du 02/11/2026, cert-manager reporté) : **A6, expiration d'un certificat à moins de 30 jours**, hors du seuil des 5 alertes critiques. Certificats du PoC relevés le 02/11/2026 (`openssl x509 -enddate`) : Zot, Forgejo et OpenBao (TLS, 180 jours) le 27/04/2027 ; CA du PoC le 29/10/2027 ; feuille du TSA le 02/11/2027 ; racine du TSA le 26/10/2036. Source de la métrique à choisir en O1 (sonde TLS des trois services, ou fichier de dates écrit par les scripts de la 08 à chaque émission) ; incident simulé : seuil abaissé dans le test de la règle (`promtool test rules`).

## Constats relevés avant le protocole (02/11/2026, pendant le rejeu `enchainement` de la 08 ; lecture seule)

- **Santé des projets (doc 04)** : Prometheus « Sain », Grafana « Sain, mais un seul éditeur » (Grafana Labs, AGPL), Alertmanager présent au tableau (Scorecard 6,6). **Non audités** : kube-prometheus-stack (chart), prometheus-operator, kube-state-metrics, node_exporter. Le doc 02 cite kube-prometheus-stack : il faudrait d'abord les auditer (règle du propriétaire : seulement des projets jugés, rien de « Risqué »).
- **Ressources** : `sc-stockage` (zone stockage, hors confiance) a 2 vCPU et 5,0 Gi disponibles sur 5,9 Gi ; `sc-confiance` 5,1 Gi sur 7,9 Gi ; `sc-build` 9,1 Gi sur 9,9 Gi (zone hostile : exclue). Hôte : 13 Go de mémoire disponibles, 70 Go de disque libres. La 08 réservait un nouveau calcul de disque pour la 19 (`sc-stockage` : 20 Go, 14 Go libres).
- **Réseau** : six espaces de la 08 ont des NetworkPolicy (`openbao`, `porte`, `tsa`, `horodatage`, `declencheurs`, `builds`). Collecter leurs métriques demande d'y autoriser l'entrée depuis Prometheus : modification de la 08, à rejouer.
- **Signatures amont** des binaires et des images de Prometheus, Alertmanager et Grafana : **non vérifiées à ce jour** ; à relever avant tout choix (règle : empreintes et signatures vérifiées).

## Décisions

**Retenues par le propriétaire le 02/11/2026** : D1 (a) binaires vérifiés en services systemd sur `sc-stockage` ; D2 (a) règle A3 écrite sur le contrat de métrique de la brique 10, preuve complète reportée à la 10 ; D3 Grafana reporté ; D4 aucune notification externe, récepteur webhook local.

**D1. Mode de déploiement.** Recommandé : **(a)**.

| Option | Pour | Contre |
|---|---|---|
| **(a) Binaires vérifiés en services systemd sur `sc-stockage`** (Prometheus, Alertmanager ; comme Forgejo et Zot) | Pas d'opérateur ni de chart à auditer ; hors des nœuds de confiance ; configuration et règles versionnées | Pas de découverte des pods par l'opérateur : cibles déclarées par `kubernetes_sd_configs` (jeton d'un compte de lecture) ou statiques ; Prometheus hors du cluster doit joindre les métriques des pods (NodePort ou routage vers les pods) |
| **(b) kube-prometheus-stack dans le cluster** (doc 02) | Forme cible du doc 02 ; découverte par ServiceMonitor ; kube-state-metrics et node_exporter fournis | Quatre projets à auditer d'abord (doc 04) ; images à vérifier ou à reconstruire ; empreinte mémoire plus forte (opérateur, kube-state-metrics, node_exporter sur chaque nœud, y compris la zone build) |

**D2. Alerte A3 sans la brique 10.** Recommandé : **(a)**.
- (a) Règle écrite maintenant sur la métrique que la brique 10 devra exposer (contrat fixé ici : par exemple `replay_dernier_resultat{projet}` 1 = bit-identique, 0 = écart), déclenchée par une série de test ; preuve complète reportée à la brique 10 ;
- (b) A3 reportée à la brique 10 : le seuil de la 19 n'est alors atteint que pour 4 alertes sur 5.

**D3. Grafana** (AGPL, un seul éditeur). Recommandé : **reporté**. Le seuil de la 19 ne porte que sur les alertes ; Grafana sert aux tableaux de bord (doc 02), utiles mais non exigés ici. Alternative : l'inclure maintenant, en lecture seule, avec ses tableaux versionnés.

**D4. Destination des alertes.** Recommandé : **aucune notification externe** dans le PoC (mailer de Forgejo coupé, pas de messagerie) ; une alerte « déclenchée » = état `firing` lu dans l'API d'Alertmanager, plus un récepteur webhook local qui journalise la notification reçue (preuve de la chaîne complète).

## Jalons proposés (chacun soumis à accord)

| # | Jalon | Contrôle de fin |
|---|---|---|
| O1 | Relevé : signatures et empreintes des binaires ou images retenus en D1 ; métriques exposées par OpenBao, Chains, Kyverno, Zot, Forgejo (noms exacts, lus sur le cluster, pas supposés) ; NetworkPolicy à ouvrir | Liste des métriques et des modifications de la 08, avec leur coût de rejeu |
| O2 | Prometheus et Alertmanager selon D1, durcis ; collecte des cinq sources ; `sync.prom` de la 01 | Toutes les cibles `up` ; aucune écriture possible depuis Prometheus (lecture seule) |
| O3 | Règles des 5 alertes (versionnées), tests unitaires des règles (`promtool test rules`) avant tout incident | Tests de règles réussis |
| O4 | Incidents simulés, un par alerte, avec retour à la normale | Chaque alerte passe à `firing` puis se résout ; notification reçue par le récepteur local |

Hors périmètre : KPI supply-chain (brique 20, 2c) ; observabilité du domaine de replay (brique 10).

## Points à vérifier en cours de brique (non supposés)

- Métriques réelles de Chains pour un échec de signature (nom et étiquettes, version v0.29.9) ; de Kyverno 1.19.2 pour les refus d'admission ; d'OpenBao pour l'état scellé (accès aux métriques sans jeton, ou avec un jeton de lecture limité).
- Effet de la collecte sur la zone de confiance : un compte de lecture Kubernetes (D1 a) ne doit lire aucun Secret.
- Lecture de `sync.prom` : Prometheus ne lit pas de fichier, il collecte des points HTTP. Il faut un exportateur : node_exporter et son collecteur textfile (non audité au doc 04), ou un serveur minimal qui sert ce seul fichier en lecture ; à trancher en O1.

## O1, partie lecture seule (02/11/2026, pendant le rejeu de la 08)

Moyens de vérification des binaires amont ([`o1-verification-amont.log`](resultats/o1-verification-amont.log), 14:29 UTC) :

| Binaire | Release | Vérification disponible |
|---|---|---|
| Prometheus | v3.15.1 (21/10/2026) ; branche 3.13 encore corrigée (v3.13.5 le même jour) | `sha256sums.txt` sans signature ; **attestation de release GitHub** (bundle Sigstore v0.3, prédicat `https://in-toto.io/attestation/release/v0.2`, 38 sujets, certificat et jeton d'horodatage) qui lie l'archive au tag de la release ; ce n'est pas une provenance de build |
| Alertmanager | v0.34.2 (29/10/2026) | `sha256sums.txt` seul, **aucune attestation ni signature** |
| Images `quay.io/prometheus/*` | — | aucun tag `.sig` ni `.att` |

Conséquence pour D1 (a) : l'empreinte de Prometheus peut être liée à sa release par l'attestation de GitHub (vérification à faire avec l'outil adapté, `gh release verify-asset` ou cosign sur le bundle, avant toute installation) ; Alertmanager ne peut être vérifié que par l'empreinte publiée sur la même page que l'archive, ce qui ne protège pas d'une release compromise. Même situation que Zot (doc 04 §5) : à consigner comme limite, ou à reconstruire depuis les sources (brique 11). Choix de la version de Prometheus (3.15 ou branche 3.13) à faire en O1 d'après la politique de support amont, lue et non supposée.

## O1, relevé sur le cluster et `sc-stockage` (02/11/2026, 16:46 à 16:50 UTC, accord du propriétaire, lecture seule)

Prédictions écrites avant mesure : [`o1-predictions.md`](resultats/o1-predictions.md) (16:46:07Z). Relevé : [`o1-metriques-cluster.log`](resultats/o1-metriques-cluster.log). Rien n'a été installé ni modifié.

| Source | Mesure | Prédiction |
|---|---|---|
| **Kyverno 1.19.2** (`kyverno-svc-metrics:8000`) | `kyverno_admission_requests_total{request_allowed="false",resource_kind,resource_namespace,…}` ; `kyverno_image_validating_policy_results_total{policy_name,result="pass"/"fail"/"error",…}` ; pas de `kyverno_policy_results_total` (les politiques de la 08 sont des ImageValidatingPolicy) | **partiellement fausse** (nom de la seconde métrique) |
| **Chains v0.29.9** (`tekton-chains-metrics:9090`) | compteurs `watcher_{pipelinerun,taskrun}_sign_created_total`, `…_payload_stored_total`, `…_marked_signed_total` et **`watcher_{pipelinerun,taskrun}_signing_failures_total{error_type}`** (`payload_creation`, `storage`) | **fausse** : un compteur d'échec direct existe |
| **OpenBao 2.7.2** | `sys/health` lisible sans jeton (`"sealed":false`) ; `sys/metrics?format=prometheus` refusé sans jeton (Forbidden) ; aucun bloc `telemetry` dans `openbao-config` | conforme |
| **Zot v2.1.22** | binaire construit avec l'extension `metrics`, mais `extensions` absent de `config.json` : `/metrics` en 404 | conforme |
| **Forgejo 15.0.11** | aucune section `[metrics]` dans `app.ini` : `/metrics` en 404 | conforme |
| **NetworkPolicy** | six politiques (`builds`, `declencheurs`, `horodatage`, `openbao`, `porte`, `tsa`), dont trois limitées à certains pods ; aucune dans `kyverno` ni `tekton-chains` ; l'entrée d'OpenBao n'admet que `tekton-chains`, la TSA et `horodatage`, port 8200 | **partiellement fausse** : pas un refus par défaut dans les six espaces |

**Constats pour la suite :**

- **A2 (Chains)** : les compteurs d'échec ne sont pas à zéro (PipelineRuns : 25 `payload_creation`, 6 `storage` ; TaskRuns : 27 `payload_creation`). Attribution complète, d'après les journaux du contrôleur depuis son démarrage (pod lancé à 13:27:21 UTC, aucun redémarrage : compteurs et journaux couvrent la même fenêtre) : les 52 échecs `payload_creation` (25 + 27) sont les 52 erreurs « expected imageID to be separable by @ », toutes sur les exécutions **négatives J6 et J7 de la 08** dans `builds` (`j6-sans-drapeau`, `j6-sans-restriction-enforce`, `j7-sample-app-etiquette`, `j7-sample-app-sans-kata`, et leurs tâches : 5 à 7 chacune) ; les 6 `storage` sont les PUT refusés vers `builds/essai-decision3` (essai de la décision 3). **Aucun échec sur une construction normale.** Une règle sur la valeur absolue serait toujours déclenchée : la règle portera sur une hausse (`increase(...[…]) > 0`), que chaque rejeu de la 08 déclenchera aussi (essais négatifs voulus) ; à accepter, ou à filtrer par espace ou par nom d'exécution en O3.
- **A5 (Kyverno)** : les refus sont déjà nombreux en fonctionnement normal (essais du banc `bancc` et de la 08) ; le seuil « anormal » sera un taux, fixé sur une mesure de référence en O3.
- **Modifications de la 08 nécessaires**, chacune à rejouer : bloc `telemetry` d'OpenBao (avec `unauthenticated_metrics_access`, ou un jeton de lecture limité à `sys/metrics`), et entrée de la NetworkPolicy `openbao` **si la collecte passe par un NodePort ou une route directe** (voir le constat suivant pour le proxy de l'API) ; extension `metrics` de Zot ; `[metrics] ENABLED = true` de Forgejo (avec `TOKEN` : vide par défaut, pas d'autorisation sur `/metrics`, doc de configuration de Forgejo). Coût : un rejeu ciblé des étapes de configuration d'OpenBao, de Zot et de Forgejo, puis de `enchainement`.
- **Accès depuis `sc-stockage` (D1 a)** : les services de Kyverno et Chains sont en `ClusterIP`, injoignables hors du cluster. Deux voies, à trancher en O2 : la collecte par le proxy de l'API (compte de lecture avec `get` sur `services/proxy` de deux espaces, sans lecture de Secret) ou des NodePort dédiés aux métriques. La lecture faite ici passait par le proxy de l'API.
- **Constat de sécurité pour la 08 (mesuré)** : par le proxy de l'API, `sys/health` d'OpenBao a répondu alors que la NetworkPolicy `openbao` n'admet en entrée que `tekton-chains`, la TSA et `horodatage`. Qui détient `get` sur `services/proxy` dans l'espace `openbao` atteint donc OpenBao sans passer par cette politique. La cause (trafic de l'hôte admis par Cilium, nœud du serveur d'API) n'a pas été vérifiée. Avec la collecte par le proxy, l'ouverture de la NetworkPolicy ne serait pas nécessaire, mais ce droit deviendrait un chemin vers OpenBao à borner (espace et nom de service).
- **Version de Prometheus** : la 3.13 est la LTS en cours (fin de support le 31/07/2027, correctifs CVSS ≥ 7,0, « best effort ») ; la 3.15 n'est pas LTS et cesse d'être corrigée à la mineure suivante. **Recommandé : v3.13.5** (21/10/2026), dont l'archive `linux-amd64` porte aussi une attestation de release GitHub (sha256 `0388822a…`).

**Décisions du propriétaire avant O2** (toutes retenues comme recommandées le 02/11/2026, « Go ») :

1. Alertmanager v0.34.2 sans signature ni attestation : limite consignée (comme Zot), ou reconstruction depuis les sources (brique 11).
2. Lecture de `sync.prom` : node_exporter et son collecteur textfile (non audité au doc 04), ou serveur minimal qui ne sert que ce fichier.
3. Collecte des métriques du cluster : proxy de l'API, ou NodePort.
4. Modifications de la 08 ci-dessus, et le rejeu qu'elles entraînent.
5. Version de Prometheus : 3.13.5 (LTS) recommandée.

Retenu : (1) limite d'Alertmanager consignée ; (2) serveur minimal pour `sync.prom` ; (3) collecte par le proxy de l'API, droit `services/proxy` borné à `kyverno` et `tekton-chains` ; (4) modifications de la 08 faites maintenant, avec rejeu ciblé ; (5) Prometheus 3.13.5.

**Temps relevé** : O1 en deux parties, relevé amont à 14:29 UTC et relevé du cluster de 16:46 à 16:50 UTC, attribution des échecs de Chains comprise ; le temps de rédaction du protocole n'a pas été relevé, le cumul de la brique face aux 0,5 pw n'est donc pas établi.

## O2, préparation (02/11/2026, 16:54 UTC, exécuté ensuite : voir la section suivante)

Prédictions : [`o2-predictions.md`](resultats/o2-predictions.md). Script : [`observabilite.sh`](observabilite.sh) (`mise run observabilite -- <étape>`), configurations dans [`config/`](config/), unités et services minimaux dans [`systemd/`](systemd/), compte de lecture dans [`cluster/lecture.yaml`](cluster/lecture.yaml) (validé en `--dry-run=client` seulement).

**Modifications de la 08 (décision 4), écrites, pas encore appliquées :**
- [`openbao/config.hcl`](../08-trust-plane/openbao/config.hcl) : `telemetry` (format Prometheus, sans nom d'hôte) et `unauthenticated_metrics_access` sur l'écouteur ([doc de l'écouteur tcp d'OpenBao](https://openbao.org/docs/configuration/listener/tcp/)). Aucun jeton OpenBao sur `sc-stockage`.
- [`stockage/zot.json`](../08-trust-plane/stockage/zot.json) : extension `metrics`.
- [`stockage.sh`](../08-trust-plane/stockage.sh), étape `forgejo` : jeton de `/metrics` généré dans la VM, section `[metrics]` ajoutée à `app.ini` à l'installation (le dépôt n'en contient aucun).
- Rejeu ciblé proposé : `mise run confiance:openbao -- temoin deployer deverrouiller controle` (le pod redémarre et revient scellé : descellement de J3, puis même clé Transit vérifiée), `mise run confiance:stockage -- zot forgejo`, puis la porte de la 01 (`mise run synchro:declencheur -- porte`) pour vérifier que l'image réelle de la 08 est toujours admise. Le prochain rejeu complet de la 08 reprendra ces fichiers.

**Deux décisions de plus, nées de la préparation :**
- **D6, source d'A6** : recommandé, un fichier `certificats.prom` écrit depuis la PKI de la 08 sur l'hôte (étape `certificats`), servi par le même serveur minimal que `sync.prom` ; pas de blackbox_exporter (non audité). Limite : à réécrire à chaque réémission de certificat.
- **D7, chemin vers OpenBao (A1)** : recommandé, **(a) proxy de l'API borné au seul service `https:openbao:8200`**, en `get` seulement : le compte ne fait que des GET sans jeton OpenBao, donc n'atteint que les points publics (`sys/health`, `sys/seal-status`, `sys/metrics`). L'alternative (b), un NodePort ouvert à l'IP de `sc-stockage`, donnerait à cette VM hors confiance l'accès à toute l'API d'OpenBao (connexion, descellement), en POST compris.

**Limites consignées :**
- Alertmanager 0.34.2 vérifié par sha256 seul (décision 1).
- Jeton longue durée du compte de lecture sur `sc-stockage`, zone hors confiance. Ses droits : GET sur trois services nommés, mesurés par l'étape `compte`.
- Le serveur de fichiers a le groupe `synchro` : il pourrait lire les rapports et bundles de la 01 ; le code ne lit que les `.prom`.

## O2, exécuté (02/11/2026, 16:59 à 17:06 UTC, accord du propriétaire, D6 et D7 (a) retenus)

**Résultat : 7 cibles sur 8 `up` ; Zot `down` (401), décision du propriétaire en attente.** Rien d'autre en échec.

| # | Prédiction ([`o2-predictions.md`](resultats/o2-predictions.md)) | Mesure | Verdict |
|---|---|---|---|
| 1 | sha256 conformes, attestation de Prometheus vérifiée | sha256 conformes ; `gh attestation verify` : « no attestations found » ([premier passage](resultats/o2-telecharger-premier-passage.log)) ; **`gh release verify-asset v3.13.5` réussit** ([`o2-telecharger.log`](resultats/o2-telecharger.log)) | conforme, outil corrigé |
| 2 | nom avec le port dans `resourceNames` ; refus ailleurs | requêtes réelles : 200 sur les trois services, 403 sur les Secrets d'`openbao` et sur `kyverno-svc:443` ; `can-i` : `yes` pour les trois, `no` pour le reste, **y compris le nom sans port** ([`o2-compte.log`](resultats/o2-compte.log)) ; premier passage avec une syntaxe de `can-i` fausse (`services/proxy/<nom>` : `no` partout) archivé | conforme |
| 3 | `sys/metrics` en 200 sans jeton ; scellé : plus de 200 | descellé : 200 par le proxy, `vault_core_unsealed` = 1 dans Prometheus ; **scellé : le pod n'est plus Ready, le Service n'a plus d'endpoint, le proxy répond 503** (« no endpoints available ») ; dans le pod, `vault_core_unsealed` = 0 reste servi ([`o2-openbao-scelle.log`](resultats/o2-openbao-scelle.log)) | conforme : A1 reposera sur `up{job="openbao"} == 0` (ou `absent`), la jauge n'étant pas collectable scellée |
| 4 | Zot `/metrics` lisible sans authentification | **401** ; le code de Zot v2.1.22 (`MetricsAuthzHandler`) refuse tout, anonyme ou authentifié, sans `accessControl.metrics` ([`o2-zot-forgejo-metriques.log`](resultats/o2-zot-forgejo-metriques.log)) | **fausse** |
| 5 | Forgejo 401/403 sans jeton, 200 avec | 401 sans jeton et avec un jeton faux, 200 avec le jeton ; métriques `gitea_*` (compteurs d'objets) | conforme |
| 6 | API de k3s joignable, cibles `up` en 35 s | 7/8 `up` au premier relevé ([`o2-cibles.log`](resultats/o2-cibles.log)) | conforme hors Zot |
| 7 | API d'administration, lifecycle, remote-write refusés (4xx) ; écoute locale | `delete_series` et `snapshot` : **HTTP 500** « admin APIs disabled », séries `up` intactes ; `/-/reload` et `/-/quit` : 403 ; `/api/v1/write` : 404 ; écoute sur 127.0.0.1 seulement (9090, 9093, 9095, 9101), pas de 9094 ([`o2-lecture_seule.log`](resultats/o2-lecture_seule.log)) | conforme sur le fond, **code faux** (500 et non 4xx) |
| 8 | rejeu ciblé sans perte | OpenBao scellé puis descellé, même clé Transit ; Zot et Forgejo redémarrés ; porte inchangée ([`o2-porte-apres-rejeu08.log`](resultats/o2-porte-apres-rejeu08.log)) ; défaut d'attente dans `openbao.sh deployer` et contrôle d'`app.ini` à adapter (premiers passages archivés, [README de la 08](../08-trust-plane/README.md)) | conforme, deux défauts de script |

**Noms réels relevés pour O3** ([`o2-cibles.log`](resultats/o2-cibles.log)) : `vault_core_unsealed` (OpenBao) ; `watcher_*_signing_failures_total` (Chains) ; `kyverno_admission_requests_total`, `kyverno_image_validating_policy_results_total` (Kyverno) ; `sync_derniere_reussite_timestamp_seconds` (01) ; `certificat_expiration_timestamp_seconds` (D6) ; `gitea_*` (Forgejo, pas d'alerte prévue).

**Décision du propriétaire pour Zot** (seule cible `down`) :
- **(a) recommandé** : compte htpasswd `poc-metriques` (bcrypt, mot de passe généré, comme les autres comptes de la 08) et `accessControl.metrics.users = ["poc-metriques"]` ; Prometheus en `basic_auth` avec un fichier de mot de passe sur la même VM ;
- (b) `accessControl.metrics.anonymousPolicy = ["read"]` : aucun secret de plus, mais métriques de Zot lisibles depuis la zone build (noms des dépôts déjà lisibles anonymement, volumes et requêtes en plus).
