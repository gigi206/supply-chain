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

**Alerte non critique ajoutée** (décision du propriétaire du 02/11/2026, cert-manager reporté) : **A6, expiration d'un certificat à moins de 30 jours**, hors du seuil des 5 alertes critiques. Certificats du PoC relevés le 02/11/2026 (`openssl x509 -enddate`) : Zot, Forgejo et OpenBao (TLS, 180 jours) le 27/04/2027 ; CA du PoC le 29/10/2027 ; feuille du TSA le 02/11/2027 ; racine du TSA le 26/10/2036. Source de la métrique à choisir en O1 (sonde TLS des trois services, ou fichier de dates écrit par les scripts de la 08 à chaque émission) ; incident simulé : série de test dont l'échéance est à moins de 30 jours dans `promtool test rules` (promtool ne permet pas d'abaisser le seuil d'une règle : seuil réel conservé, correction d'O3).

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
- **D7, chemin vers OpenBao (A1)** : recommandé, **(a) proxy de l'API borné au seul service `https:openbao:8200`**, en `get` seulement : le compte ne fait que des GET sans jeton OpenBao, donc n'atteint que les points publics (`sys/health`, `sys/seal-status`, `sys/metrics`). **Correction après mesure (O2, 17:08 UTC)** : le proxy de l'API retire l'en-tête `Authorization` mais **transmet `X-Vault-Token`** (journal d'audit d'OpenBao, [`o2-proxy-entete-openbao.log`](resultats/o2-proxy-entete-openbao.log)). Sans jeton OpenBao, le compte n'atteint que les points publics ; mais qui détient à la fois ce jeton Kubernetes (présent sur `sc-stockage`) et un jeton OpenBao valide obtient, par ce chemin, toutes les lectures GET de l'API d'OpenBao, malgré la NetworkPolicy. Le risque est moindre que (b) (pas de POST : ni connexion, ni descellement, ni signature), mais plus large que ce qui était affirmé. L'alternative (b), un NodePort ouvert à l'IP de `sc-stockage`, donnerait à cette VM hors confiance l'accès à toute l'API d'OpenBao (connexion, descellement), en POST compris.

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
| 6 | API de k3s joignable, cibles `up` en 35 s | 7/8 `up` au premier relevé ([`o2-cibles-premier-passage.log`](resultats/o2-cibles-premier-passage.log)) | conforme hors Zot |
| 7 | API d'administration, lifecycle, remote-write refusés (4xx) ; écoute locale | `delete_series` et `snapshot` : **HTTP 500** « admin APIs disabled », séries `up` intactes ; `/-/reload` et `/-/quit` : 403 ; `/api/v1/write` : 404 ; écoute sur 127.0.0.1 seulement (9090, 9093, 9095, 9101), pas de 9094 ([`o2-lecture_seule.log`](resultats/o2-lecture_seule.log)) | conforme sur le fond, **code faux** (500 et non 4xx) |
| 8 | rejeu ciblé sans perte | OpenBao scellé puis descellé, même clé Transit ; Zot et Forgejo redémarrés ; porte inchangée ([`o2-porte-apres-rejeu08.log`](resultats/o2-porte-apres-rejeu08.log)) ; défaut d'attente dans `openbao.sh deployer` et contrôle d'`app.ini` à adapter (premiers passages archivés, [README de la 08](../08-trust-plane/README.md)) | conforme, deux défauts de script |

**Noms réels relevés pour O3** ([`o2-cibles-premier-passage.log`](resultats/o2-cibles-premier-passage.log)) : `vault_core_unsealed` (OpenBao) ; `watcher_*_signing_failures_total` (Chains) ; `kyverno_admission_requests_total`, `kyverno_image_validating_policy_results_total` (Kyverno) ; `sync_derniere_reussite_timestamp_seconds` (01) ; `certificat_expiration_timestamp_seconds` (D6) ; `gitea_*` (Forgejo, pas d'alerte prévue).

**Décision du propriétaire pour Zot** (seule cible `down`) :
- **(a) recommandé** : compte htpasswd `poc-metriques` (bcrypt, mot de passe généré, comme les autres comptes de la 08) et `accessControl.metrics.users = ["poc-metriques"]` ; Prometheus en `basic_auth` avec un fichier de mot de passe sur la même VM ;
- (b) `accessControl.metrics.anonymousPolicy = ["read"]` : aucun secret de plus, mais métriques de Zot lisibles depuis la zone build (noms des dépôts déjà lisibles anonymement, volumes et requêtes en plus).

**Contrôles après coup (17:07 à 17:09 UTC)** : aucun des deux jetons (Forgejo `/metrics`, compte de lecture) dans les journaux systemd ni les journaux de pods des trois VM ([`o2-fuites.log`](resultats/o2-fuites.log)), ni dans le dépôt ; A4 couvre les deux projets de la 01 (`sample-app-sync`, `traefik`) ; en-tête `X-Vault-Token` transmis par le proxy (voir la correction de D7). `observabilite.sh` nettoie désormais ses copies de secrets même en cas d'échec (`trap`).

### Séquence après un rejeu complet de la 08

Un rejeu complet recrée les VM et le cluster : jeton du compte invalide, Prometheus absent. À rejouer, dans l'ordre : `mise run observabilite -- certificats compte installer cibles lecture_seule` (les archives vérifiées restent dans `~/.cache/supply-chain-poc/19/amont`, revérifiées à l'installation). La 08 reprend d'elle-même la télémétrie d'OpenBao, l'extension de Zot et le jeton de Forgejo. Non rejoué à ce jour.

### Zot et D7 : décisions du propriétaire (02/11/2026, 17:38 UTC) et fin d'O2 (17:41 UTC)

Décisions : **Zot (a)**, compte `poc-metriques` ; **D7 (a) reconfirmée** après la correction du risque (`X-Vault-Token` transmis par le proxy). Commits poussés à la même heure.

- [`zot.json`](../08-trust-plane/stockage/zot.json) : `accessControl.metrics.users = ["poc-metriques"]` ; [`stockage.sh`](../08-trust-plane/stockage.sh) : compte htpasswd `poc-metriques` (bcrypt, mot de passe généré sur l'hôte en 0600, comme les autres comptes) ; Prometheus en `basic_auth` (`/etc/prometheus/secrets/zot.password`, 0640, sur la VM de Zot) ; `confiance:stockage -- zot` puis `observabilite -- installer cibles`.
- **Toutes les cibles `up` (8/8)** ([`o2-cibles.log`](resultats/o2-cibles.log)) ; métriques `zot_*` relevées.
- Prédictions 9 à 11 ([`o2-zot-compte-metriques.log`](resultats/o2-zot-compte-metriques.log)) : `/metrics` en 401 anonyme, **200** avec `poc-metriques`, **403** avec `poc-ecriture` (hors liste) : conforme. `/v2/` et le catalogue en 200 ; écriture refusée (403) : conforme. **Prédiction 10 fausse sur la lecture** : `poc-metriques` reçoit 403 sur un manifeste de `builds/sample-app` que l'anonyme lit (200) ; dans Zot, un compte authentifié absent des politiques d'un dépôt ne reçoit pas l'`anonymousPolicy`. Le compte n'a donc que `/metrics`, `/v2/` et le catalogue : plus restreint que prévu.

**Non-interférence côté 01** : runs planifiés de 17:18 (`sample-app-sync`) et 17:27 (`traefik`), après le redémarrage de Forgejo, terminés en code 0 ([`o2-timers-01-apres.log`](resultats/o2-timers-01-apres.log)).

**O2 : seuil de jalon atteint** (toutes les cibles `up`, lecture seule mesurée). Suite : O3 (règles des 5 alertes et de A6, tests `promtool test rules`), sur accord.

## O3, préparation à sec (02/11/2026, 17:54 UTC ; rien d'exécuté sur `sc-stockage`, rien de déployé)

Prédictions datées : [`o3-predictions.md`](resultats/o3-predictions.md). Règles : [`config/regles/alertes.yml`](config/regles/alertes.yml) ; tests : [`config/regles/alertes-tests.yml`](config/regles/alertes-tests.yml) ; étapes `regles`, `reference` et `deployer` d'`observabilite.sh` (journaux `resultats/o3-<étape>.log`).

| Alerte | Expression (résumé) | Pièges couverts par un test |
|---|---|---|
| A1 `OpenBaoScelle` (critique) | `vault_core_unsealed == 0`, ou `up{job="openbao"} == 0` **si** `up{job="kyverno"} == 1` ; `for: 1m` | scellé : jauge non collectée (O2), seul `up` tombe ; proxy ou jeton en panne (Kyverno aussi en panne) : pas de A1 ; borne du `for` |
| A2 `ChainsEchecSignature` (critique) | hausse sur 10 min de `watcher_{pipelinerun,taskrun}_signing_failures_total`, **ou série apparue depuis moins de 10 min** | après un redémarrage du contrôleur, le premier échec crée la série à 1 et `increase()` vaut 0 ; compteur ancien stable sans alerte |
| A3 `ReplayNonBitIdentique` (critique) | `replay_dernier_resultat == 0` (contrat de la brique 10, D2 a) | série de test ; pas d'`absent()` (la 10 n'existe pas) |
| A4 `MiroirEnRetard` (critique) | `time() - sync_derniere_reussite_timestamp_seconds > 86400`, ou plus aucune série | un projet en retard, l'autre à jour ; fichier disparu |
| A5 `KyvernoRefusAnormaux` (critique) | plus de **5** refus d'admission en 5 min (hausses, et séries apparues depuis moins de 5 min), tous espaces | refus anciens stables ; rafale ; nouvelle combinaison espace et type apparue avec 7 refus ; admissions acceptées ignorées |
| A6 `CertificatExpireBientot` (avertissement) | échéance à moins de 30 jours | 20 jours ; 30 jours et 10 min (franchit le seuil pendant le test) ; un an |
| `CollecteEnPanne` (avertissement) | `up == 0` depuis 5 min, OpenBao exclu (A1) | proxy en panne : Kyverno et Chains, pas OpenBao |

**Constats de conception** :

- **A2 ne peut pas être filtrée** : les compteurs de Chains v0.29.9 n'ont que `error_type` (O1), ni espace ni exécution. Chaque rejeu de la 08 la déclenchera (essais négatifs J6 et J7, décision 3). Ne pas filtrer non plus sur `error_type` : le type produit par un OpenBao scellé n'est pas encore mesuré (O4).
- **A5** : Kyverno porte `resource_namespace` ; exclure `bancc` (essais du banc) est possible. Seuil de 5 refus en 5 min **provisoire**, à confirmer par la mesure de référence (étape `reference`).
- **Limite commune à A2 et A5** : si Prometheus perd plus de 5 min de données (arrêt), toutes les séries paraissent « nouvelles » à la reprise et les deux alertes se déclenchent à tort pendant 10 min (A2) ou 5 min (A5).
- **Rechargement** : le lifecycle est désactivé (O2) et l'unité n'a pas d'`ExecReload` ; le déploiement redémarre Prometheus (données conservées dans `/var/lib/prometheus`). `ExecStartPre` (`promtool check config`) vérifie aussi les fichiers de règles.

## O3, exécuté (02/11/2026, 17:59 à 18:01 UTC, accord du propriétaire : « Oui, tout », A2 non filtrée, A5 tous espaces)

| # | Prédiction ([`o3-predictions.md`](resultats/o3-predictions.md)) | Mesure | Verdict |
|---|---|---|---|
| 1 | `promtool check rules` : 7 règles | `SUCCESS: 7 rules found` ([`o3-regles.log`](resultats/o3-regles.log)) | conforme |
| 2 | tous les tests réussissent au premier passage | `SUCCESS` ; **contrôle par mutation** : deux attentes faussées (A2, A5) rejetées, code 1 ([`o3-regles-mutation.log`](resultats/o3-regles-mutation.log)) : les tests discriminent | conforme |
| 3 | aucune des 7 expressions ne rend de résultat sur le Prometheus réel | aucune ([`o3-reference.log`](resultats/o3-reference.log)) | conforme |
| 4 | aucun refus de Kyverno depuis le début des données (vers 16:59) | 0 refus dans les 8 espaces, maximum sur 5 min = 0, pour **825 admissions acceptées** ; début des données à **17:02:19 UTC** (et non 16:59) | conforme (heure de début inexacte) |
| 5 | aucune hausse des échecs de Chains | 0 pour `payload_creation` et `storage` | conforme |

**Seuil de A5** : la référence est nulle en fonctionnement normal (58 min d'historique, sans essai de la 08 ni du banc). Elle ne calibre donc pas le seuil contre un bruit : 5 refus en 5 min est conservé comme choix (un essai négatif isolé ne le franchit pas), à éprouver par la rafale d'O4.

**Déploiement** ([`o3-deployer.log`](resultats/o3-deployer.log), [`o3-apres-deploiement.log`](resultats/o3-apres-deploiement.log)) : `alertes.yml` dans `/etc/prometheus/regles/` (0640, groupe `prometheus`), Prometheus redémarré ; 7 règles `ok` et `inactive`, aucune alerte active ni reçue par Alertmanager ; 8 cibles sur 8 `up` ; Alertmanager connu de Prometheus.

**Défauts rencontrés** : la boucle d'évaluation des expressions s'arrêtait après la première (`ssh` lisait la suite de la liste sur l'entrée standard) : lecture par un autre descripteur, premier passage archivé ([`o3-reference-premier-passage.log`](resultats/o3-reference-premier-passage.log)). `jq` absent de `sc-stockage` : filtrage sur l'hôte. Un répertoire `/tmp/regles-mutation` (copies des règles et des tests, aucun secret) reste dans la VM : sa suppression par `rm` dans une commande ad hoc a été refusée par le contrôle de sécurité de l'outil.

**O3 : seuil de jalon atteint** (tests de règles réussis). Suite : O4, un incident simulé par alerte avec retour à la normale, sur accord.


## O4, préparation à sec (02/11/2026, 18:29 UTC, rien exécuté sur les VM ni le cluster)

Prédictions : [`o4-predictions.md`](resultats/o4-predictions.md). Étapes de [`observabilite.sh`](observabilite.sh) : `fichiers`, puis un incident par alerte (`a1` à `a6`). Chaque étape vérifie que l'alerte est inactive au départ, puis relève, horodaté, chaque changement d'état dans Prometheus (`/api/v1/alerts`) et Alertmanager (`/api/v2/alerts`). Elle attend enfin les notifications `firing` et `resolved` dans le journal du récepteur local.

| Alerte | Incident | Retour à la normale |
|---|---|---|
| A1 | pod `openbao-0` supprimé : il redémarre scellé (état mesuré en O2) | descellement de J3 (clé par l'entrée standard) ; clé Transit `chains` comparée avant et après ; reprise des CronJobs `horodatage` et `rattrapage` vérifiée |
| A2 | `preuves.sh decision3` de la 08 : PUT `.att` refusé par Zot, échec de signature de type `storage` | la mesure remet Zot d'elle-même ; résolution après la fenêtre de 10 min |
| A3 | `replay_dernier_resultat{projet="essai-o4"} 0` | valeur à 1, puis fichier de test retiré |
| A4 | `sync_derniere_reussite_timestamp_seconds{projet="essai-o4"}` vieille de 25 h | horodatage à l'instant présent, puis fichier retiré |
| A5 | 4 créations refusées par Kyverno (sous le seuil, aucune alerte attendue), puis 10 | fin de la fenêtre de 5 min |
| A6 | `certificat_expiration_timestamp_seconds{certificat="essai-o4"}` à 20 jours | échéance à 60 jours, puis fichier retiré |

`CollecteEnPanne` n'a pas d'incident dédié : arrêter une collecte pendant 5 min déclencherait aussi A4 (`absent`) ou A1.

**Choix proposés au propriétaire** (préparés selon la recommandation, à confirmer avec l'accord d'O4) :

1. **Chemin des séries de test (A3, A4, A6)**. `fichiers.py` ne lisait que `sync.prom` et `certificats.prom`.
   - **Recommandé : (a)** élargir ses sources à `/etc/fichiers-metriques/*.prom`, une modification de code avec redéploiement du service (étape `fichiers`). La brique 10 pourra y servir sa métrique.
   - (b) un répertoire de test sous `/var/lib/synchro/`. Pas de code à changer, mais il mêle des essais à l'état de la 01.
   - Dans les deux cas, le vrai `sync.prom` de la 01 n'est pas vieilli : le timer le réécrit et les scripts de la 01 le lisent.
2. **A4 avec `for: 5m`** (défaut trouvé en préparation). Une seule collecte manquée du serveur de fichiers marque toutes ses séries périmées : `absent()` devient vrai et A4, critique et sans délai, se déclencherait. Cela peut arriver au redémarrage de l'étape `fichiers` comme à un redémarrage de la VM.
   - **Recommandé** : `for: 5m`. Le seuil de 24 h rend ce délai négligeable.
   - Les tests sont complétés : absence en attente puis déclenchée, collecte manquée 2 min sans alerte.
   - Ils doivent être rejoués (`JALON=o4 … regles deployer`, sans écraser les journaux d'O3) avant l'étape `fichiers`.
3. **A1 par redémarrage du pod plutôt que `bao operator seal`** (incident proposé au protocole).
   - Le redémarrage n'utilise pas le jeton root, et son état scellé a été mesuré en O2.
   - `bao operator seal` laisse le pod en marche : son effet sur la disponibilité du pod n'est pas mesuré.
4. **Type d'échec de Chains quand OpenBao est scellé** (point ouvert d'O3). **Recommandé : mesure reportée.**
   - A2 est éprouvée par l'échec `storage` de la décision 3 : déterministe, et sa remise en état est déjà prouvée.
   - Mesurer l'échec sous scellement demanderait une exécution signée lancée pendant A1, puis purgée pour garder la référence de la 08 (`ECHEC_SIGNATURE 8`).
   - Conséquence du report : A2 reste non filtrée sur `error_type`, comme décidé en O3.
5. **Journal de la 08** : `decision3` réécrit `08-trust-plane/resultats/preuves-decision3.log` et ajoute deux lignes au `chrono.tsv` de la 08.
   - L'étape `a2` copie le journal dans [`o4-a2-preuves-decision3.log`](resultats/) et rend à la 08 sa version versionnée (`git checkout` de ce seul fichier).
   - Les lignes du `chrono.tsv` restent : elles datent un vrai passage de la mesure.
6. **Rafale de A5 en dry-run serveur** : le pod de sonde de la 08 est refusé par la règle `zone-confiance` sans rien créer, même si une politique l'admettait par erreur.
   - Le comptage des requêtes en dry-run par Kyverno n'est pas vérifié. L'étape relève le compteur brut avant et après chaque rafale.

**Constat à consigner (calcul, à confirmer par la mesure)** : `increase()` extrapole aux bords de la fenêtre. Avec une collecte toutes les 30 s, 5 refus valent environ 5,56 et déclenchent A5 : le seuil réel est « au moins 5 refus en 5 min ».

**Ménage** : l'étape `fichiers` supprime aussi `/tmp/regles-mutation`, laissé dans `sc-stockage` en O3.

**Effets de bord d'O4, à accepter avec l'accord** :
- OpenBao scellé environ 3 à 5 min (A1) : aucune signature de Chains possible, la TSA et les passages d'`horodatage` peuvent échouer pendant ce temps.
- Zot reconfiguré puis remis, deux redémarrages ; CronJobs `rattrapage` et `horodatage` suspendus environ 1 min (`decision3`, A2).
- Prometheus redémarré (`deployer`, A4 avec `for: 5m`) ; jusque-là, `alertes.yml` en service diffère de celui du dépôt.
- `fichiers.py` modifié et son service redémarré (`fichiers`) ; `/tmp/regles-mutation` supprimé.
- Environ 50 min d'exécution en arrière-plan.

**Retour manuel si l'exécution est interrompue pendant A1** : `mise run confiance:openbao -- deverrouiller`, puis `git checkout` de `08-trust-plane/resultats/openbao-deverrouiller.log`. Le trap de l'étape `a1` descelle déjà en cas d'échec ; il attend le pod en marche avant de lire son statut.

## O4, exécuté (02/11/2026, 18:33 à 18:59 UTC, accord du propriétaire : « Oui, tout », six choix recommandés)

**Résultat : 4 alertes critiques sur 5 éprouvées sur incident simulé (A1, A3, A4, A5), plus A6 ; A2 non éprouvée (KO de l'incident, pas de l'alerte).** Pour chaque alerte éprouvée : `firing` dans Prometheus, `active` dans Alertmanager, notification `firing` reçue par le récepteur local, puis retour à la normale, alerte résolue et notification `resolved` reçue.

| # | Prédiction ([`o4-predictions.md`](resultats/o4-predictions.md)) | Mesure | Verdict |
|---|---|---|---|
| 1 | tests de règles réussis (A4 avec `for: 5m`), 7 règles après redéploiement | `SUCCESS` ([`o4-regles.log`](resultats/o4-regles.log)) ; 7 règles chargées, lues 5 s après le redémarrage : `unknown`, faute d'une première évaluation ([`o4-deployer.log`](resultats/o4-deployer.log)) ; A4 évaluée ensuite (passage par `pending`, ligne 3) | conforme (relevé trop tôt) |
| 2 | collecte des fichiers `up`, métriques toujours servies | `up` = 1, quatre métriques comptées ([`o4-fichiers.log`](resultats/o4-fichiers.log)) ; défaut du relevé : le comptage perd le nom des métriques (`requete` retire `__name__`) | conforme |
| 3 | A3, A6 : `firing` en moins de 90 s, `resolved` moins de 2 min 30 s après le retour ; A4 : `pending`, puis `firing` 5 min plus tard ; collecte jamais tombée | A3 : `firing` 32 s après l'écriture, résolue 53 s après le retour ([`o4-a3.log`](resultats/o4-a3.log)) ; A4 : `pending` à 53 s, `firing` 4 min 58 s plus tard, résolue 48 s après le retour ([`o4-a4.log`](resultats/o4-a4.log)) ; A6 : 52 s et 47 s ([`o4-a6.log`](resultats/o4-a6.log)) ; notifications 7 à 10 s après chaque changement vu par l'étape (envois d'Alertmanager groupés à la 47e seconde de chaque minute dans tout O4 ; jusqu'à 36 s pour la résolution de A5) ; `min_over_time(up)` = 1 pour les trois | conforme |
| 4 | dry-run compté ; 4 refus ≈ 4,44 sans alerte ; 10 refus ≈ 11,1, `firing` en moins de 90 s, résolue 5 à 6 min après | compteur brut 92 → 96 → 106 : **les créations en dry-run serveur sont comptées** ; **4,444 exactement**, A5 restée inactive pendant toute la fenêtre ; **11,111**, `firing` 31 s après la rafale, résolue 5 min 2 s après ([`o4-a5.log`](resultats/o4-a5.log)) | conforme |
| 5 | A1 par `up == 0`, `pending` en moins de 60 s, `firing` 1 min plus tard ; résolue après le descellement ; clé inchangée ; CronJobs repris ; pas de A2 | `pending` 24 s après la suppression du pod, `firing` 57 s plus tard ; `vault_core_unsealed` sans valeur, `up{job="openbao"}` = 0 et Kyverno à 1 : branche prévue ; résolue 36 s après le descellement ; clé Transit `chains` inchangée ; **un passage d'`horodatage` en échec pendant le scellement**, passages d'`horodatage` et de `rattrapage` réussis après ; TSA prête ; A2 inactive ([`o4-a1.log`](resultats/o4-a1.log)) | conforme |
| 6 | `decision3` reproduit sa preuve ; A2 `firing`, résolue après 10 min | **KO avant la mesure** : `decision3` suppose le gabarit d'essai de J6, or le gabarit en service est la pipeline `sample-app` depuis la bascule de J8 (14:35 à 14:39 UTC, juste après le dernier passage de `decision3`) ; Zot et CronJobs remis par la mesure elle-même ; compteurs d'échec de Chains inchangés, relus à 19:02 UTC (25, 6, 27) ([`o4-a2-premier-passage.log`](resultats/o4-a2-premier-passage.log), [journal de la 08](resultats/o4-a2-preuves-decision3-premier-passage.log)) | **fausse** : condition préalable non vérifiée en préparation |
| 7 | environ 50 min | 26 min (A2 interrompue au départ ; A4 et A5 plus courts que prévu) | — |

**Constat confirmé par la mesure** : `increase()` extrapole d'un facteur 300/270 avec une collecte toutes les 30 s (4 refus → 4,444 ; 10 → 11,111). **Le seuil réel de A5 est donc « au moins 5 refus en 5 min »** (5 refus → 5,56 > 5).

**Effets de bord relevés** :
- le `chrono.tsv` de la 08 garde une ligne `J8 decision3` à 18:59:19 UTC, sans ligne de fin (étape en KO) ; son journal `preuves-decision3.log` a été rendu à sa version versionnée ;
- une image témoin de plus dans `builds/essai-decision3` (tag `temoin-20261102T185919Z`), comme à chaque passage de `decision3` ;
- pendant A4, un build de `sample-app-sync` lancé par erreur depuis la brique 01 (voir son README) : réussi et signé, même digest que l'image de S5, sans effet sur les alertes ; il a ajouté une provenance au tag `.att` de cette image (voir A2, deuxième passage).

**O4 : seuil de la brique non atteint** (A2 non éprouvée). Décision à prendre pour A2.

### A2, deuxième passage : build pendant le scellement (02/11/2026, 19:40 à 19:47 UTC, décision du propriétaire « a, build pendant scellé »)

Prédictions 8 à 12 ([`o4-predictions.md`](resultats/o4-predictions.md), 19:40:03Z). Journal : [`o4-a2-deuxieme-passage.log`](resultats/o4-a2-deuxieme-passage.log) ; relevé de Chains après coup : [`o4-a2-chains-releve.log`](resultats/o4-a2-chains-releve.log).

- **Déroulé** : OpenBao scellé à 19:40:20 (pod supprimé) ; commit `902ce252…` poussé sur `custom/s5` du fork par `poc-dev` ; build réussi à 19:41:14, même digest `3a7ca1b1…` (prédiction 8 conforme) ; OpenBao gardé scellé jusqu'à 19:45:15, puis descellé, clé Transit inchangée ; exécutions purgées.
- **Prédictions 9 à 11 fausses : Chains ne signe rien, ne compte aucun échec, et marque les quatre objets `signed=true`.**
  - Journal du contrôleur : « error configuring kms signer … connection refused » (`signing.go:82`, niveau `warn`), puis « No signer kms configured for tekton / oci / tekton-pipeline-run » (`signing.go:175`, `warn`).
  - Compteurs sur 40 min : `marked_signed` +1 (PipelineRun) et +3 (TaskRuns) ; `sign_created`, `payload_stored` et `signing_failures` : 0.
  - **Constat de sécurité (Chains v0.29.9, mesuré)** : quand le signataire KMS ne peut pas être configuré, Chains **échoue en ouvert** : les objets sont marqués signés sans aucune signature ni attestation, et aucun compteur d'échec ne bouge. A2, écrite sur `signing_failures`, ne peut pas voir cette panne.
  - Non vérifié, car les exécutions ont été purgées avant le contrôle : ce qu'en dirait le contrôle exécutions/enveloppes de la 08, et la porte pour une image **neuve** (ici, le digest avait déjà des attestations d'un build identique, donc la porte l'admettrait).
- **Prédiction 12 conforme** : A1 déclenchée (19:41:37) puis résolue (19:45:37), notifications reçues ; passages d'`horodatage` et de `rattrapage` réussis après le descellement (relevé de 19:50).
- **Défaut de l'étape** : elle n'a pas attendu la résolution de A1 ni relevé les CronJobs, car elle s'est arrêtée en KO sur la notification de A2 (relevé fait à part).
- **Preuve directe, après la purge** ([`o4-a2-att-releve.log`](resultats/o4-a2-att-releve.log)) : le tag `.att` de `builds/sample-app-sync@3a7ca1b1…` ne contient que les provenances des builds de 15:17 (`1599e311`, S5) et 18:38 (`e209907f`) ; aucune du build de 19:40 (PipelineRun `8054172c-…`).
- **Code de Chains** ([`o4-a2-chains-code.log`](resultats/o4-a2-chains-code.log)) : en v0.29.9, un signataire absent fait `continue` sans ajouter d'erreur, puis `MarkSigned` marque l'objet. Sur `main` (commit `b1c0af9`, #1834, 13/08/2026), l'erreur est agrégée et l'objet n'est plus marqué signé ; ce commit n'est pas dans v0.29.9 (dernière release, 22/10/2026). **Même corrigé, ce cas n'appelle pas `recordError` : `signing_failures` ne le compterait toujours pas.**
- **Référence pour une détection** ([`o4-a2-ecart-reference.log`](resultats/o4-a2-ecart-reference.log)) : écart `increase(marked_signed[10m]) - increase(sign_created[10m])`, de 17:12 à 19:35 UTC (un seul build normal, celui de 18:38) : maximum 0 pour les PipelineRuns comme pour les TaskRuns (minimum −1,05 pour les TaskRuns : `publier` crée deux signatures) ; pendant le build scellé : 1,05 et 3,16.

**A2 reste non éprouvée ; seuil de la brique non atteint.** Options proposées au propriétaire :

1. **(a) recommandé : étendre A2 d'une branche « marqué sans signature »** : `increase(watcher_*_marked_signed_total[10m]) - increase(watcher_*_sign_created_total[10m]) > 0`, avec `for: 1m` (un compteur peut entrer dans la fenêtre une collecte avant l'autre), tests `promtool` (échec en ouvert seul, build normal, bord de fenêtre), puis **troisième passage** du même incident, avec contrôle exécutions/enveloppes de la 08 et lecture de Zot **avant** la purge. Limites à consigner : référence faite sur un seul build normal ; en trafic mêlé, un build normal à reprises peut masquer un échec en ouvert.
2. (b) Garder A2 telle quelle et consigner qu'elle ne voit pas cette panne ; la brique reste à 4 alertes critiques sur 5 éprouvées.
3. Indépendamment : signaler à l'amont que le cas « signataire absent » ne compte aucun échec, même sur `main` (action publique chez un tiers : sur accord explicite seulement). Et passer à une version de Chains qui contient `b1c0af9` dès sa publication.

**Effet de bord à revérifier** : le build de 18:38 lancé par erreur depuis la 01 a ajouté une provenance (commit `e209907f`, branche `custom/n…/b`) au tag `.att` que juge la porte de la 01 ; la non-interférence de la 01 avait été mesurée sur `1599e311`. Revérifier la porte (`synchro:declencheur -- porte`) est à décider.

### A2, troisième passage : second volet `ChainsMarqueSansSignature` (02/11/2026, 19:58 à 20:11 UTC, décision du propriétaire « a, étendre A2 »)

Règle ajoutée ([`alertes.yml`](config/regles/alertes.yml)) : `increase(marked_signed[10m]) - increase(sign_created[10m]) > 0`, pour les PipelineRuns ou les TaskRuns, `for: 1m`, étiquettes `alerte: A2`, `severite: critique`. Tests : échec en ouvert (en attente puis déclenché, résolu à la sortie de la fenêtre), build normal et bord de fenêtre sans alerte. Prédictions 13 à 16 ([`o4-predictions.md`](resultats/o4-predictions.md)).

| # | Mesure | Verdict |
|---|---|---|
| 13 | `SUCCESS: 8 rules found`, tests réussis ([`o4-a2-regles.log`](resultats/o4-a2-regles.log)) ; 8 règles chargées, aucune alerte active au départ ([`o4-a2-deployer.log`](resultats/o4-a2-deployer.log), lu 5 s après le redémarrage : `unknown`) ; **pas de contrôle par mutation** des nouveaux tests | conforme |
| 14 | OpenBao scellé à 19:59:10 ; build réussi à 20:00:06, même digest ; quatre objets `signed=true`, aucune signature ; écart 1,05 (PipelineRuns) et 3,16 (TaskRuns) ; **`ChainsMarqueSansSignature` `pending` dès 20:00:06** (marquage du TaskRun `preparer` à 19:59:22), **`firing` à 20:00:38, notification à 20:00:47**, pendant le scellement ; `ChainsEchecSignature` jamais déclenchée ([`o4-a2.log`](resultats/o4-a2.log)) | conforme |
| 15 | avant la purge : tag `.att` à 4 enveloppes ; PipelineRun et TaskRun `publier` **ABSENTE** (`signed=true`, aucune enveloppe de leur UID) | conforme |
| 16 | descellement à 20:01:42, clé inchangée ; A1 déclenchée (20:00:37) puis résolue (20:02:07), notification `resolved` ; `ChainsMarqueSansSignature` résolue à 20:10:12 (environ 10 min après le marquage), deux notifications `resolved` (séries des TaskRuns et des PipelineRuns) ; passages d'`horodatage` et de `rattrapage` réussis | conforme |

**O4 : seuil de la brique atteint : les 5 alertes critiques se déclenchent sur incident simulé** (A1 et A3 à A5 au premier passage, A2 par son second volet au troisième), avec retour à la normale et notifications reçues par le récepteur local ; A6 aussi. Limites consignées :
- A3 éprouvée sur une série de test (contrat de la brique 10, D2 a) ; preuve complète à la brique 10.
- Le premier volet de A2 (`signing_failures`) n'a été déclenché par aucun incident réel ici : `decision3`, qui le produisait, ne tourne plus depuis la bascule de J8.
- Second volet : référence sur un seul build normal ; en trafic mêlé, un build normal à reprises peut masquer un échec en ouvert.
- Chains v0.29.9 échoue en ouvert sans OpenBao : l'alerte le détecte, elle ne l'empêche pas. Le correctif amont (`b1c0af9`) n'est pas publié.

### Essai d'un correctif de Chains (02/11/2026, 22:52 à 23:04 UTC, demande du propriétaire)

Le correctif amont `b1c0af9` (#1834) n'est dans aucune release, ni dans aucune branche `release-v0.2x.x`, et même sur `main` le cas « aucun signataire » n'appelle pas `recordError` : `signing_failures` ne le compte pas. **Correctif proposé** ([`chains-correctif/correctif.patch`](chains-correctif/correctif.patch), sur `main` `0084070`) : une ligne qui compte ce cas sous un nouveau type `error_type="signer_unavailable"`, un test unitaire (TaskRun et PipelineRun ; il échoue sans la ligne) et la liste des `error_type` dans `docs/metrics.md`. `go test -race ./...` : 40 paquets, aucun échec ; golangci-lint v2.14.0 (celle de la CI de Chains) : 0 problème. Le second chemin de #1796 (format introuvable) est **écarté** : le corriger casse 5 tests existants (configuration OCI vide), et la ConfigMap refuse déjà tout format inconnu.

**Image d'essai** ([`o4-correctif_image.log`](resultats/o4-correctif_image.log)) : v0.29.9 + #1834 + le correctif, Go 1.27.3 (archive vérifiée par sha256 ; la release est construite avec 1.26.10), options de ko ; l'image officielle plus une couche `/ko-app/controller`, dans `essais-chains/controller` (non signée, sans attestation). Même incident que le troisième passage d'A2, puis remise en état ([`o4-correctif_a2.log`](resultats/o4-correctif_a2.log), prédictions dans [`o4-correctif-chains-predictions.md`](resultats/o4-correctif-chains-predictions.md)).

| # | Mesure | Verdict |
|---|---|---|
| 1 | digest `8aa1200d…` ; couches de l'officielle + `1df7048f…`, binaire relu dans Zot identique ; pod prêt 6 s après le changement | conforme |
| 2 | OpenBao scellé à 22:52:30 ; build réussi à 22:53:36, même digest `3a7ca1b1` ; **les quatre objets `signed=failed`, `retries=3`, à 22:53:42**, aucun `signed=true` ; `No signer kms configured for tekton` au journal | conforme |
| 3 | `signer_unavailable` : **20 (TaskRuns) et 7 (PipelineRun)**, soit les 27 lignes « No signer » du journal. Le script les a lus trop tôt (13, série PipelineRun pas encore collectée : collecte toutes les 30 s) ; valeurs finales relues dans Prometheus ([`o4-correctif-compteurs.log`](resultats/o4-correctif-compteurs.log)). **Le binaire d'essai n'a rien signé** : de 22:52:35 à sa dernière collecte (22:54:05), il n'a créé aucune série `marked_signed`, `sign_created` ni `payload_stored`, y compris après le descellement ; le tag `.att` est passé de 4 à 6 enveloppes, et les 2 nouvelles sont celles du build de contrôle, sous l'image officielle | conforme |
| 4 | **`ChainsEchecSignature` déclenchée** (premier volet, `error_type="signer_unavailable"`), notifiée à 22:53:17, résolue à 23:03:40 ; `ChainsMarqueSansSignature` inactive, 0 notification | conforme |
| 5 | après le descellement : les quatre objets restent `signed=failed` ; PipelineRun et TaskRun `publier` **ABSENTE** du tag `.att` | conforme |
| 6 | image officielle `2200972d…` remise, spec du pod identique à celle d'avant l'essai ; build normal `signed=true`, enveloppes **COUVERTE** ; exécutions purgées ; clé Transit inchangée ; A1 déclenchée puis résolue ; passages d'`horodatage` et de `rattrapage` réussis | conforme |

**Ce que l'essai montre :** avec #1834 et ce correctif, une panne du KMS n'échoue plus en ouvert. Les objets finissent `signed=failed`, et le premier volet d'A2 la voit. Le second volet ne sert alors plus qu'aux versions sans le correctif. Limites :
- **Pas de reprise après la panne :** les cinq tentatives (la première, puis `retries` de 0 à 3) sont épuisées en quelques secondes (file de knative à 5 ms, doublée à chaque échec, et réconciliation à chaque patch d'annotation), et un build fait pendant une panne du KMS reste définitivement non signé ; il faut le relancer.
- **Version essayée :** v0.29.9 + #1834, pas `main` (tests unitaires sur les deux).
- **PR amont ouverte le 03/11/2026** avec l'accord du propriétaire : [tektoncd/chains#2112](https://github.com/tektoncd/chains/pull/2112) (commit `dc808d18b`, fork `gigi206/chains`, adresse noreply de GitHub ; message et description : [`chains-correctif/`](chains-correctif/)). CLA individuel de la CDF signé par le propriétaire le 03/11/2026 : contrôle EasyCLA réussi (commit rattaché au compte `gigi206`) ; reste la revue des mainteneurs (étiquettes `lgtm` et `approved`) avant fusion. Elle fait référence à l'issue #1796 sans la fermer (issue attribuée à une mainteneuse depuis le 15/07/2026) et demande la publication de #1834.
- **Résidus :** l'image d'essai reste dans Zot (`essais-chains/controller:essai`) ; deux commits vides de plus sur `custom/s5` du fork (essai et build de contrôle).


## O5 : déplacé dans la brique 19b

L'exigence du propriétaire du 02/11/2026 (« absolument tout doit être loggé dans grafana pour auditer ») est traitée par une brique distincte, **19b, journalisation d'audit** (décision D12, retenue par le propriétaire). Protocole, audit des outils et décisions : [README de la 19b](../19b-journalisation/README.md). Les relevés de santé ([`o5-sante.log`](resultats/o5-sante.log), [`o5-scorecard.md`](resultats/o5-scorecard.md)) restent ici, sous leur nom d'origine. D3 (Grafana reporté) est levée par D8.

## Additif du 03/11/2026, 22:43 UTC : rejouée de zéro dans le rejeu `complet` de la 08

O2 (sans `telecharger`) et O3 (`regles deployer`) ont été rejoués sur une plateforme neuve, sans KO :
[`rejeu-complet.log`](../08-trust-plane/resultats/rejeu-complet.log) de la 08.
- Ordre : la 01 d'abord (groupe `synchro`), puis `certificats compte installer`. `cibles`, `lecture_seule` et les règles
  passent après Alloy (19b, L3).
- `reference`, O4 et les correctifs de Chains ont été sautés : ce sont des mesures.

## Additif du 05/11/2026, 10:40 UTC : alertes de fraîcheur de la brique 07a, préparées à sec

`ScanEnRetard`, `ScanBientotRefuse` et `BaseGrypeVieillie` ajoutées à `alertes.yml`, avec leurs tests et l'incident `a7`. **Rien n'est déployé, `promtool` n'a pas été lancé.** Elles lisent `fraicheur-scan.prom`, servi par `fichiers-metriques` sans changer ni `fichiers.py` ni `prometheus.yml`. Protocole : [`g8-predictions.md`](../07a-sbom-grype/resultats/g8-predictions.md) de la 07a.

**Additif du 05/11/2026, 10:58 UTC** : alertes de fraîcheur déployées, 14 règles, incident `a7` conforme. Journaux : [`g8-regles.log`](resultats/g8-regles.log), [`g8-deployer.log`](resultats/g8-deployer.log), [`g8-deployer-releve.log`](resultats/g8-deployer-releve.log), [`g8-a7.log`](resultats/g8-a7.log).

**Additif du 07/11/2026, 18:04 UTC : A2 annoncée dans les étapes de la 08.** La limite « A2 ne peut pas être filtrée » est confirmée par deux épisodes, relevés dans [chains-echec-signature.log](../08c-durcissement/resultats/chains-echec-signature.log) de la 08c :
- le 06/11, de 15:34 à 15:41 UTC, à la première collecte de Chains, sur les échecs voulus de J6, J7 et decision3 ;
- le 07/11, de 11:37 à 11:46 UTC, sur decision3.

Les étapes `preuves.sh decision3`, `politique.sh restreint` et `construction.sh construire` affichent désormais A2 dans leurs prédictions, sur accord du propriétaire. Le récepteur local a bien reçu les notifications du 06/11 (Loki), mais le journal local de `sc-stockage` les a perdues, par un mécanisme non établi.

**Limite d'A2 lue dans le source de Chains v0.29.9** (18:07 UTC, non observée) : `recordError` ne compte que les échecs sur les artefacts TaskRun et PipelineRun. Un échec limité à la signature d'image (OCI) mène à `signed=failed` sans hausse d'aucun compteur. Il échappe donc à A2, et aussi à `ChainsMarqueSansSignature`, puisque l'objet n'est pas marqué signé. Le cas des quatre TaskRuns de l'étape `taches` de J6 (`signed=failed`, type d'échec inconnu) reste non déterminé. Détail dans l'additif de 18:04 UTC des prédictions de la 08c.

**Additif du 09/11/2026, 17:32 UTC (chantier des Events, README de la 08c) : `config/regles/alertes.yml` et `alertes-tests.yml` modifiés dans le dépôt, non déployés.** La règle `EvenementsMuets` et ses quatre cas `promtool` attendent l'essai `evenements.sh essai_alerte`, puis une application avec l'accord du propriétaire. D'ici là, le dépôt et Prometheus divergent : un `observabilite.sh deployer` ou un rejeu poserait la règle sans décision, avant le compteur d'Alloy, et déclencherait une fausse alerte.
