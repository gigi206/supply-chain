# Brique 19b : journalisation d'audit dans Grafana (protocole retenu par le propriétaire le 02/11/2026)

Origine : exigence du propriétaire du 02/11/2026, « absolument tout doit être loggé dans grafana pour auditer », posée pendant la brique 19. Rattachée à une brique distincte (D12) pour ne pas porter la 19 au-delà de 2× son estimation.

Seuil : **pour chaque source retenue (J1 à J6 et J8), un événement témoin daté est retrouvé par une requête à travers l'API de Grafana en moins de 2 min ; aucun secret connu dans Loki ; l'alerte « source muette » se déclenche quand un agent s'arrête.** Effort estimé : **1 pw** (0,5 pw sans J3, J5 et J6) ; décision avec le propriétaire à 2 pw. Rien n'est installé avant l'accord sur chaque jalon ; J3, J5 et J6 modifient la 08 et demandent un accord séparé (J3 : redémarrage du serveur k3s, installation système).

Règles reprises : projets jugés par la doc 04, rien de « Risqué » ; versions épinglées ; empreintes et signatures (ou attestations) vérifiées ; prédictions datées avant chaque mesure ; résultats dans `resultats/`.

## Préparation à sec (02/11/2026, 20:29 UTC, d'abord écrite comme O5 de la brique 19 ; rien installé, rien modifié)

**Exigence du propriétaire (02/11/2026)** : « absolument tout doit être loggé dans grafana pour auditer ». Elle dépasse le seuil de la 19, qui ne porte que sur les alertes, et revient sur D3 (Grafana reporté). Ce qui suit est un protocole à valider. Aucun jalon ne démarre sans accord.

### Santé et vérifiabilité des candidats

Relevés : [`o5-sante.log`](../19-observabilite/resultats/o5-sante.log) et [`o5-scorecard.md`](../19-observabilite/resultats/o5-scorecard.md). Lecture seule, sur le réseau public, à 20:29 UTC.

| Projet | Release | Scorecard | Vérification amont possible | Auteurs sur 90 j | Verdict proposé (doc 04) |
|---|---|---|---|---|---|
| **Grafana** | v13.3.0 (27/10/2026), AGPL | 7 | `.sha256` sur dl.grafana.com, aucun `.asc` ; `.deb` de GitHub sans attestation ; image sans signature ; dépôt APT signé par GPG, non relevé | 178 adresses lisibles, Grafana Labs dominant | inchangé : Sain, mais un seul éditeur |
| **Loki** | v3.7.9 (20/10/2026), AGPL | 8,4 | `SHA256SUMS` **sans signature ni attestation** ; image sans signature | 42 adresses lisibles ; grafana.com en tête, redhat.com 17 commits | **Sain, mais un seul éditeur** (Grafana Labs) ; artefacts non vérifiables, comme Alertmanager et Zot |
| **Grafana Alloy** (collecteur) | v1.21.3 (28/10/2026), Apache-2.0 | n/d (absent de l'API) | **attestation de release GitHub** sur l'archive (prédicat `release/v0.2`, comme Prometheus en O1), donc liée au tag ; ce n'est pas une provenance de build ; image sans signature | 27 adresses lisibles, grafana.com en tête | **Sain, mais un seul éditeur** ; Scorecard à relever par le CLI |
| Promtail | inclus dans Loki | — | — | — | **Risqué → interdit** : fin de vie le 02/03/2026 (doc de Loki, tag v3.7.9) |
| Vector | v0.61.0 (29/10/2026), MPL-2.0 | 6,1 | `SHA256SUMS` seul, sans attestation | non relevé | non jugé (alternative à Alloy, un seul éditeur : Datadog) |
| Fluent Bit | v5.1.5 (21/10/2026), Apache-2.0 | 5,4 (Code-Review 2) | aucun fichier de sommes dans la release GitHub | non relevé | À surveiller (Scorecard < 6) |

SECURITY.md : absent à la racine de grafana, loki et alloy ; celui de l'organisation (`grafana/.github`) s'applique. Je n'ai pas vérifié si Grafana Labs exige un CLA, ce qui comporterait un risque de changement de licence : point à relever avant D8.

### Sources à journaliser : inventaire proposé (« absolument tout »)

| # | Source | Où | Ce qu'il faut pour l'avoir | Coût |
|---|---|---|---|---|
| J1 | Journaux systemd des trois VM : Forgejo (routeur, pushes), Zot, synchro de la 01 (timers), Prometheus, Alertmanager, récepteur d'alertes, sshd, sudo, k3s, containerd | 3 VM | collecteur sur chaque VM (lecture de journald) | agent sur chaque VM, y compris `sc-confiance` et `sc-build` |
| J2 | Journaux de tous les pods : Tekton, Chains, Triggers et EventListeners, Kyverno, OpenBao, TSA, horodatage, rattrapage, porte, builds | `/var/log/pods` des nœuds | même collecteur | aucun en plus |
| J3 | **Audit de l'API Kubernetes** : qui a fait quoi sur le cluster | serveur k3s (`sc-confiance`) | `--audit-policy-file` et `--audit-log-path` sur le serveur k3s : **redémarrage du serveur k3s** (installation système, accord requis), puis modification des scripts de la 08 pour que ce réglage survive à un rejeu | rouvre l'installation de la 08 | **Corrigé par L1 : déjà actif depuis la 08** (écritures seulement) |
| J4 | Événements Kubernetes, dont les refus de Kyverno et les PolicyReports | API | collecteur avec un compte de lecture (sans Secrets), comme pour Prometheus en O2 | un compte de plus |
| J5 | **Audit d'OpenBao** : chaque signature Transit, chaque connexion | pod OpenBao | `bao audit enable file` (sortie standard ou fichier). **OpenBao refuse les requêtes s'il ne peut écrire dans aucun journal d'audit (fermé par défaut)** : à mesurer, sinon un disque plein arrête les signatures | modification de la 08 (`openbao.sh`) | **Corrigé par L1 : device `fichier/` déjà actif, sans rotation (D15)** |
| J6 | Audit de Zot : écritures et suppressions par compte | `sc-stockage` | `log.audit` dans la configuration de Zot | modification de la 08 (registre) | **Corrigé par L1 : déjà configuré (`/var/log/zot/audit.log`)** |
| J7 | Flux réseau refusés (Hubble de Cilium) | 3 VM | export des flux Hubble vers un fichier | volume à mesurer ; optionnel |
| J8 | Notifications d'Alertmanager | `sc-stockage` | déjà dans journald (récepteur) : couvert par J1 | aucun |
| J9 | Scripts du PoC lancés depuis l'hôte (`mise run …`) | laptop | collecteur **sur votre ordinateur** (installation système) ; leurs journaux sont déjà versionnés dans `resultats/` | proposé : non |

### Décisions (numérotation reprise de la 19) : **toutes retenues par le propriétaire le 02/11/2026 (« Oui, toutes »)**

- **D8. Pile** : Loki et Grafana sur `sc-stockage` (hors confiance, comme Prometheus, D1 a), binaires vérifiés en services systemd. Collecteur : **Alloy**. Promtail est interdit, Fluent Bit est à surveiller, Vector n'est pas jugé. Loki et Alloy sont « un seul éditeur » (Grafana Labs), comme Grafana. Recommandé : (a) Loki, Alloy et Grafana. Alternative : (b) VictoriaLogs, qui n'apparaît pas dans l'API Scorecard et dont l'éditeur est déjà « à surveiller » pour VictoriaMetrics (5,4).
- **D9. Périmètre** : recommandé J1 à J6 et J8. J7 en option, après une mesure de volume. J9 exclu. J3, J5 et J6 modifient la 08 : décision distincte, avec son coût de rejeu.
- **D10. Intégrité** : Loki ne rend pas un journal infalsifiable. Proposé :
  - API de suppression de Loki laissée désactivée, rétention de 30 jours dans le PoC ;
  - ~~Loki joignable seulement depuis les trois VM (pare-feu)~~ remplacé par D16 : certificat client de la CA du PoC exigé par Loki, sans pare-feu ; Grafana en lecture seule, sans accès anonyme, comptes en 0600 dans `…/08/secrets` ;
  - limite consignée : un nœud compromis peut injecter de faux journaux ou cesser d'en envoyer. Une alerte « source muette » est ajoutée à Prometheus (absence de lignes d'une source depuis N minutes).
- **D11. Secrets dans les journaux** : `fuites.sh` de la 08 interroge aussi Loki (LogQL) pour chaque secret connu. Les journaux d'audit d'OpenBao hachent les valeurs par défaut (HMAC) : à vérifier, pas à supposer.
- **D12. Rattachement** : vu le temps déjà passé, la 19 approche de son plafond de 1 pw avant décision (O1 à O4 de 14:29 à 20:11 UTC, sans les préparations). Recommandé : **nouvelle brique « 19b, journalisation d'audit »**, estimée à 1 pw avec J3, J5 et J6, ou 0,5 pw sans eux, plutôt qu'un jalon de la 19 qui la ferait dépasser 2×.

### Jalons (chacun soumis à accord ; O5 à O8 dans la première rédaction)

| # | Jalon | Contrôle de fin |
|---|---|---|
| L1 | Relevé, en lecture seule : espace disque et mémoire de `sc-stockage` ; volume de journaux par source sur 1 h (journald, `/var/log/pods`) ; vérification des archives retenues (empreintes, et attestation d'Alloy par `gh release verify-asset` ou cosign) ; CLA de Grafana Labs | Dimensionnement et rétention chiffrés |
| L2 | Loki et Grafana sur `sc-stockage`, services durcis ; sources de données Prometheus et Loki provisionnées depuis git ; aucun accès anonyme | Grafana lit Prometheus et Loki ; écriture refusée au compte de lecture |
| L3 | Alloy sur les trois VM, J1, J2, J4 et J8 ; puis, sur accord séparé, J3, J5 et J6 (modifications de la 08) | Chaque source présente dans Loki |
| L4 | **Contrôle « tout est dans Grafana »** : pour chaque source, un événement témoin daté (push Forgejo, création de pod refusée par Kyverno, signature Transit, écriture Zot, `kubectl` sur l'API…) retrouvé par une requête **à travers l'API de Grafana** en moins de 2 min ; recherche des secrets ; redémarrage d'Alloy sans perte (reprise sur position) ; alerte « source muette » déclenchée en arrêtant un agent | Matrice source par source, journal archivé |

## L1, exécuté (02/11/2026, 20:35 à 20:37 UTC, accord du propriétaire : « Oui, lancer L1 »)

Script : [`journalisation.sh`](journalisation.sh), étapes `telecharger` et `releve` (`mise run journalisation -- …`). Prédictions : [`l1-predictions.md`](resultats/l1-predictions.md), écrites à 20:34:46Z. Journaux : [`l1-telecharger.log`](resultats/l1-telecharger.log) et [`l1-releve.log`](resultats/l1-releve.log).

Deux passages du relevé sont archivés. Le premier ([`l1-releve-premier-passage.log`](resultats/l1-releve-premier-passage.log)) avait deux défauts : `jq` est absent des VM, donc la section `log` de Zot est restée illisible ; et ma recherche « CLA », sans distinction de casse, trouvait « clarifying ». Le deuxième ([`l1-releve-deuxieme-passage.log`](resultats/l1-releve-deuxieme-passage.log)) n'avait toujours pas le détail par unité, faute de `jq`. Les mesures de volume sont identiques à quelques pour cent près d'un passage à l'autre.

| # | Prédiction | Mesuré | Verdict |
|---|---|---|---|
| 1 | Les trois empreintes correspondent | `OK` pour les trois ; l'API grafana.com, relue au téléchargement, donne la même empreinte pour Grafana | conforme |
| 2 | Attestation : Alloy oui, Loki non | Alloy : « Verification succeeded », tag `v1.21.3` résolu en `f2108cd7…`. Loki : « no attestations found for tag v3.7.9 » | conforme |
| 3 | `sc-stockage` : 2 vCPU, 4 à 5 Gi disponibles, 11 à 14 Go libres | 2 vCPU, 4 868 Mi disponibles, 13 Go libres sur 20 Go (Prometheus : 9,6 Mo) | conforme |
| 4 | Journald : `sc-confiance` la plus bavarde (5 à 50 Mo/h), les deux autres sous 15 Mo/h | `sc-confiance` 6,1 Mo/h, `sc-build` 3,4 Mo/h, **`sc-stockage` 25,3 Mo/h, la plus bavarde** (`zot.service` : 11 517 lignes sur 16 841) | **faux** pour `sc-stockage` |
| 5 | Pods : moins de 50 Mo/h, `kube-system`, Tekton et Chains en tête | 5,5 Mo/h, dont 3,9 Mo pour `tekton-pipelines`, 0,9 Mo pour `kube-system`, 0,2 Mo pour `tekton-chains` ; seulement 0,1 Mo sur `sc-build` | conforme |
| 6 | Moins de 1 000 événements Kubernetes | **1 114** (`horodatage` 532, `declencheurs` 367, `builds` 154) | **faux**, de peu |
| 7 | Aucun audit configuré (k3s, OpenBao, Zot) | **Les trois existent déjà, posés par la 08** : voir ci-dessous | **faux** |
| 8 | CLA chez Grafana Labs (prédiction faible) | statut `license/cla` sur la dernière PR fermée de `grafana`, `loki` et `alloy` ; section « Contributor License Agreement (CLA) » dans le CONTRIBUTING.md de `grafana` | conforme |
| 9 | 30 jours tiennent sur le disque | voir le dimensionnement : oui, avec peu de marge dans l'hypothèse haute | conforme, avec réserve |

**Audits déjà en place (prédiction 7 fausse)**, ce qui change le coût de J3, J5 et J6 :
- **k3s (J3)** : l'audit de l'API est actif depuis la 08 (test négatif 3). On le voit dans `config.yaml` (`audit-policy-file`, `audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log`, rotation : 100 Mo, 10 fichiers, 30 jours). Volume : **13 697 événements et 18,9 Mo dans la dernière heure**.
  - La politique journalise les écritures au niveau `Metadata`.
  - Les lectures (`get`, `list`, `watch`) **ne sont pas journalisées**, sauf les lectures de Secrets par Tekton, Chains et les résolveurs. Les leases sont exclues.
  - Aucun redémarrage de k3s n'est donc nécessaire pour J3 : il suffit de collecter le fichier.
- **OpenBao (J5)** : un device d'audit `fichier/` (type `file`, valeurs sensibles en HMAC) écrit dans `/openbao/data/audit.log`, sur le volume persistant. Il pèse 4,7 Mo pour 3 603 lignes. Ce volume a 7,3 Go libres.
  - **Aucune rotation n'est visible.** OpenBao refuse toute requête s'il ne peut plus écrire dans son seul device d'audit : un disque plein arrêterait les signatures. Le débit reste à mesurer en L3.
  - Collecte possible depuis le nœud (le volume `local-path` est lisible par root), sans modifier la 08.
- **Zot (J6)** : `"log": {"level": "info", "audit": "/var/log/zot/audit.log"}`, déjà configuré. Son débit n'a pas été mesuré.

**Dimensionnement** (hypothèse haute : sortie JSON de journald, qui grossit les lignes) :
- journald 34,8 Mo/h, pods 5,5 Mo/h, audit k3s 18,9 Mo/h, soit environ **59 Mo/h**. Il faut y ajouter les audits d'OpenBao et de Zot, non mesurés à l'heure.
- Cela fait environ 1,4 Go par jour et 43 Go en 30 jours, avant compression. Avec une compression de ×5 à ×10 dans Loki (hypothèse, à mesurer en L3) : **4 à 9 Go**, pour 13 Go libres sur `sc-stockage`.

**Points nouveaux à décider** (avant L2) :
- **D13. Rétention** :
  - (a) 30 jours, avec une alerte sur le disque de `sc-stockage` à 80 %, et la compression réelle mesurée en L3 ;
  - (b) 15 jours ;
  - (c) agrandir le disque de `sc-stockage` (modification des VM de la 08).

  Recommandé : (a).
- **D14. Lectures de l'API Kubernetes** : « absolument tout » inclurait les `get`, `list` et `watch`, que la politique d'audit de la 08 exclut. Les contrôleurs lisent en continu, donc le volume serait multiplié, sans mesure à ce jour.
  - (a) Garder la politique actuelle (écritures, plus les lectures de Secrets) et consigner la limite.
  - (b) Mesurer d'abord le volume d'une politique qui ajoute les lectures en `Metadata`. Cela demande de modifier la 08 et de redémarrer le serveur k3s (accord séparé).

  Recommandé : (a).
- **D15. Rotation de l'audit d'OpenBao** : sans rotation, le journal finit par remplir le volume, et OpenBao refuse alors toute requête.
  - (a) Ajouter un second device d'audit `socket` ou `file` vers la sortie standard, collecté par Alloy. Le blocage n'arrive alors que si les deux échouent.
  - (b) Rotation par `logrotate` sur le nœud, avec un signal à OpenBao.
  - (c) Consigner la limite et poser seulement une alerte sur le disque.

  Recommandé : (a). C'est une modification de la 08, à mesurer.

### Décisions D13 à D15 : retenues par le propriétaire le 02/11/2026 (« Oui, les trois (a) »)

D13 (a) : rétention de 30 jours, alerte sur le disque à 80 %. D14 (a) : politique d'audit de l'API de la 08 gardée (écritures, plus les lectures de Secrets), limite consignée. D15 (a) : second device d'audit d'OpenBao vers la sortie standard, collecté par Alloy (modification de la 08, préparée en L3).

## L2, préparation à sec (02/11/2026, 20:43 UTC ; rien installé)

Fichiers :
- [`config/loki.yaml`](config/loki.yaml), [`config/grafana.ini`](config/grafana.ini) et [`config/provisioning/datasources/sources.yaml`](config/provisioning/datasources/sources.yaml) ;
- [`systemd/`](systemd/) : `loki.service` et `grafana.service`, durcis comme Prometheus, et la mesure du disque `disque-metriques` (timer chaque minute) ;
- étapes `certificats installer controle` de [`journalisation.sh`](journalisation.sh), avec `JALON=l2`.

Prédictions : [`l2-predictions.md`](resultats/l2-predictions.md), écrites à 20:43:24Z.

**Lu dans la configuration de référence (Loki v3.7.9, Grafana 13.3.0), pas supposé :**
- **Loki supprime sur demande par défaut** (`deletion_mode`, défaut `filter-and-delete`). Il est mis à `disabled` (D10). La rétention exige `delete_request_store`, renseigné `filesystem`.
- Loki envoie des statistiques d'usage à Grafana Labs par défaut (`analytics.reporting_enabled`). Coupé.
- Grafana joint l'extérieur par défaut, de plusieurs façons, toutes coupées :
  - rapports d'usage ;
  - vérification des mises à jour de Grafana et des plugins ;
  - fil de nouvelles ;
  - **préinstallation de plugins avec mise à jour automatique** (`preinstall_auto_update = true`) ;
  - instantanés externes.
- Également désactivés : tableaux publics, alerting de Grafana (les alertes restent dans Alertmanager), accès anonyme et inscription. Le mot de passe de l'administrateur est lu par `$__file{}`.

**D16 : authentification par certificat client (mTLS) plutôt qu'un pare-feu ; retenue par le propriétaire le 02/11/2026 (« a, mTLS seul »), elle remplace le pare-feu de D10.** D10 prévoyait « Loki joignable seulement depuis les trois VM (pare-feu) ».
- Loki exige à la place un certificat client de la CA du PoC (`RequireAndVerifyClientCert`). Chaque agent Alloy aura le sien en L3, Grafana a `grafana-client`.
- C'est plus fort qu'un filtrage par adresse, et la configuration réseau de `sc-stockage` reste inchangée.
- Limite : Loki ne distingue pas lecture et écriture. Tout porteur d'un certificat client peut lire tous les journaux et en écrire. Un nœud compromis lit donc aussi les journaux des autres.
- Le pare-feu pourra s'ajouter plus tard si le propriétaire le veut.
- **Additif du 03/11/2026** : D16 est contournée en l'état. Le gRPC de Loki (`127.0.0.1:9096`) expose les mêmes routes sans certificat, depuis `sc-stockage` ; voir [Constat du 03/11/2026](#constat-du-03112026-mtls-contourné-par-le-grpc-de-dskit).

**Alerte de disque (D13 a)** : règle `DisqueStockagePlein` (`disque_utilise_ratio > 0.8`, `for: 5m`, avertissement) ajoutée aux règles de la 19, avec son test. `promtool` 3.13.5 a été extrait de l'archive vérifiée de la 19, sur l'hôte, sans installation : `SUCCESS` sur 9 règles. Contrôle par mutation : avec un seuil à 0,82, le test échoue.

**Corrections après relecture (additif daté aux prédictions)** :
- `domain` de Grafana mis à `192.168.161.13` : l'hôte ne résout pas `poc.test`, et `root_url`, qui sert aux redirections et au contrôle d'origine des sessions, en dépend. Contrôle ajouté pour le chemin du navigateur : connexion, cookie de session, en-tête `Origin`.
- `router_logging = true` : Grafana OSS n'a pas de section `[auditing]` (lu dans `defaults.ini`), donc aucun journal d'audit des actions de ses utilisateurs. Chaque requête HTTP est journalisée avec son utilisateur, et L3 collecte ce journal. Limite consignée (ADR 0001).
- Absence d'appels vers Grafana Labs vérifiée sur tout le journal des services, et non plus sur une seule capture de `ss`.

**Points mesurés en L2, non supposés** : Grafana sous `ProtectSystem=strict`, et sans `MemoryDenyWriteExecute`, retiré par prudence (à mesurer) ; `$__file{}` dans les `secureJsonData` provisionnées ; code de refus de la suppression dans Loki ; suppression d'une source provisionnée.

## L2, exécuté (02/11/2026, 20:51 à 20:53 UTC, accord du propriétaire : « Oui, lancer L2 »)

Commande : `JALON=l2 mise run journalisation -- certificats installer controle`, puis `JALON=l2 mise run observabilite -- regles deployer` (19).

Journaux :
- 19b : [`l2-certificats.log`](resultats/l2-certificats.log), [`l2-installer.log`](resultats/l2-installer.log), [`l2-controle.log`](resultats/l2-controle.log) et [`l2-complement.log`](resultats/l2-complement.log), ce dernier relevé après coup ;
- 19 : [`l2-regles.log`](../19-observabilite/resultats/l2-regles.log) et [`l2-deployer.log`](../19-observabilite/resultats/l2-deployer.log).

La dernière ligne de `l2-controle.log` (`/ready` à 20:52:19) a été ajoutée à la main, juste après l'étape.

| # | Mesuré | Verdict |
|---|---|---|
| 1 | Quatre certificats vérifiés (serveur pour `loki` et `grafana`, client pour `grafana-client` et `controle`) ; clés et mots de passe en 0600 | conforme |
| 2 | Ports libres avant l'installation (0 écoute) ; empreintes revérifiées dans la VM ; Loki 3.7.9 (`d3b4a2f7`) et Grafana 13.3.0 ; `loki`, `grafana` et le timer `active` ; compte `auditeur` créé (HTTP 200), avec `admin` (Admin) et `auditeur` (Viewer). Grafana tourne sous `ProtectSystem=strict`, et `$__file{}` des `secureJsonData` est interprété (la source Loki se connecte en mTLS) | conforme, prédictions faibles comprises |
| 3 | Sans certificat client : poignée TLS refusée (« tlsv13 alert certificate required », HTTP 000). **`/ready` répond 503 juste après le démarrage** (« Ingester not ready: waiting for 15s after being ready », 20:52:09 et 20:52:19), puis 200 à partir de 20:52:33, soit 35 s après le démarrage (20:51:58). Ligne témoin écrite (204) puis relue ; **suppression refusée, HTTP 403** (« deletion is not available for this tenant ») | conforme, sauf le délai de `/ready`, non prévu |
| 4 | Anonyme : 401 ; sources Prometheus et Loki saines ; **l'auditeur lit la ligne témoin dans Loki à travers Grafana**, et 8 séries `up` dans Prometheus ; création de tableau et de source par l'auditeur : 403 ; suppression de la source provisionnée par l'administrateur : **403, « Cannot delete read-only data source »** | conforme |
| 5 | Aucune connexion établie de `loki` ou de `grafana` hors du réseau du PoC à l'instant du contrôle | conforme, portée limitée à cet instant |
| 6 | `disque_utilise_ratio{point="/"}` à 0,4036, une seule ligne ; collecté par Prometheus (0,4094 à 20:53:44) | **faux de peu** (0,36 à 0,40 prévu) |
| 7 | 9 règles, tests réussis ; `DisqueStockagePlein` chargée, `ok`, `inactive` | conforme |
| 8 | Mémoire disponible : 4 541 Mi ; Loki 46 Mi, Grafana 303 Mi, Prometheus 65 Mi | conforme (Loki sous la fourchette) |
| 9 | `POST /login` en tant qu'auditeur : 200, cookie de session ; `GET /api/user` avec le cookie et l'en-tête `Origin` : 200 (`auditeur`) ; `/` sans session redirige vers `https://192.168.161.13:3001/login` | conforme |
| 10 | 2 requêtes `/api/ds/query` journalisées avec leur `userId` | conforme |
| 11 | 0 ligne mentionnant `grafana.com` ou `stats.grafana` dans les journaux des deux services | conforme |

**Constats :**
- **Effet de bord de `deletion_mode: disabled`** : chaque requête vers Loki produit une ligne `level=error` (« error loading cache generation numbers … deletion is not available for this tenant »). On en compte 5 depuis le démarrage, sur 6 erreurs au total. C'est du bruit **dans le journal d'audit lui-même**, et il faudra l'exclure des alertes sur les erreurs de Loki en L4. Effet sur le cache des résultats : non mesuré.
- La sonde de disponibilité de Loki n'est utilisable que 35 s environ après un démarrage. L3 doit en tenir compte, car Alloy réessaie ses envois (à mesurer).

**Seuil de la brique : non atteint.** Seule la ligne témoin de l'hôte est dans Loki : les sources J1 à J6 et J8 arrivent en L3, par Alloy.

## L3, préparation à sec (02/11/2026 ; rien installé)

Fichiers :
- configurations d'Alloy par rôle dans [`config/alloy/`](config/alloy/) :
  - `commun` : journal ;
  - `noeud` : pods, et sortie vers le relais ;
  - `confiance` : audit k8s ;
  - `stockage` : sortie vers Loki, relais, audit de Zot, événements ;
- [`systemd/alloy.service`](systemd/alloy.service) : compte `alloy`, seule capacité `CAP_DAC_READ_SEARCH`, groupe `systemd-journal`, `--disable-reporting` ;
- [`cluster/evenements.yaml`](cluster/evenements.yaml) : compte `alloy-evenements`, avec seulement `get`, `list` et `watch` sur les événements ;
- second device d'audit dans [`config.hcl`](../08-trust-plane/openbao/config.hcl) de la 08 (D15 a) ;
- étapes `certificats_l3 evenements openbao_sortie alloy controle_l3` (`JALON=l3`).

Prédictions : [`l3-predictions.md`](resultats/l3-predictions.md).

**Lu dans la doc d'Alloy v1.21.3 :**
- Alloy envoie par défaut des statistiques d'usage. Il est lancé avec `--disable-reporting`.
- `loki.source.journal` ne relit que 7 h par défaut, porté à 168 h (`max_age`, limite d'âge de Loki).
- Un répertoire passé à `alloy run` est lu comme une seule configuration.

Les trois compositions sont validées sur l'hôte par `alloy validate`, avec le binaire extrait de l'archive vérifiée, sans installation. Un témoin cassé (récepteur inexistant) est refusé.

**D17 : relais en écriture seule sur `sc-stockage` ; retenue par le propriétaire le 02/11/2026 (« a, relais »).** Avec D16 seule, chaque agent porterait un certificat accepté par Loki, et pourrait donc lire tous les journaux de la plateforme. C'est grave pour `sc-build`, où tournent les builds. Proposé :
- `sc-confiance` et `sc-build` n'écrivent que vers un relais Alloy de `sc-stockage` : port 3501 pour l'une, 3502 pour l'autre ;
- chaque port n'accepte que les certificats d'une **autorité propre au nœud**, hors de la CA du PoC, que Loki refuse ;
- le relais **impose l'étiquette `noeud`** : un nœud ne peut pas se faire passer pour un autre ;
  - **additif du 03/11/2026** : faux en l'état déployé. Chaque source du relais ouvre aussi un port gRPC sans TLS, sur toutes les interfaces, qui sert les mêmes routes : sans certificat, on lit `/ready` (mesuré) et, d'après le code, on peut écrire sous l'étiquette de l'un ou l'autre nœud (non essayé). Voir [Constat du 03/11/2026](#constat-du-03112026-mtls-contourné-par-le-grpc-de-dskit) ;
- seuls Grafana (`grafana-client`), Alloy de `sc-stockage` (`alloy-stockage`) et l'hôte (`controle`) gardent un certificat accepté par Loki.

Alternative : chaque agent écrit directement dans Loki avec un certificat de la CA du PoC (limite de D16 acceptée).

**D15 (a), coût pour la 08** : `config.hcl` change. Au prochain `openbao.sh deployer`, l'empreinte de la configuration, portée en annotation du gabarit, changera, et le pod sera recréé, donc scellé. C'est le chemin normal de la 08. En L3, la ConfigMap est appliquée et OpenBao rechargé par SIGHUP, sans redémarrage.

**Pare-feu (décision du propriétaire, 02/11/2026) : « on fera le fw avec les network policies une fois tout validé ».** À faire après L4, avec une nuance à trancher à ce moment-là : les NetworkPolicies, et les politiques de Cilium, filtrent le trafic des pods et des nœuds du cluster (`sc-confiance`, `sc-build`), pas `sc-stockage`, qui n'est pas un nœud k3s. Elles peuvent interdire aux pods de joindre Loki (3100), le relais (3501, 3502) et Grafana (3001). Les ports de `sc-stockage` eux-mêmes demanderaient un filtrage sur la VM (nftables).

**Additif du 03/11/2026 (vérifié sur le cluster)** : la phrase précédente est fausse sur un point. `sc-stockage` **est** un agent k3s (README de la 08, `k3s.sh` ; `kubectl get nodes` : `Ready` depuis le 02/11/2026 13:11 UTC), mais seul `cilium` y tourne en pod. Forgejo, Zot, Loki, Grafana, Alloy, Prometheus et Alertmanager y sont des processus de l'hôte : les NetworkPolicies, qui sélectionnent des pods, ne filtrent pas leur entrée. Deux voies : le pare-feu d'hôte de Cilium (`CiliumClusterwideNetworkPolicy` avec `nodeSelector`), désactivé (`enable-host-firewall=false` dans `cilium-config`), donc modification de la 08 ; ou nftables sur la VM, **non installé** (`nft` absent), donc installation système soumise à accord.

## L3, exécuté (02/11/2026, 21:02 à 21:05 UTC, accord du propriétaire : « Oui, lancer L3 »)

Commande : `JALON=l3 mise run journalisation -- certificats_l3 evenements openbao_sortie alloy controle_l3`.

Journaux :
- [`l3-certificats_l3.log`](resultats/l3-certificats_l3.log), [`l3-evenements.log`](resultats/l3-evenements.log), [`l3-openbao_sortie.log`](resultats/l3-openbao_sortie.log), [`l3-alloy.log`](resultats/l3-alloy.log), [`l3-controle_l3.log`](resultats/l3-controle_l3.log) ;
- [`l3-complement.log`](resultats/l3-complement.log) : relevé de sc-stockage à 21:04:57.

**Passages archivés (défauts de script, sans effet sur les VM) :**
- `certificats_l3`, deux passages :
  - [premier](resultats/l3-certificats_l3-premier-passage.log) : `pki-client.cnf` exige `SAN`, même vide, pour l'autorité. Clé créée, certificat non ; le script teste désormais le certificat ;
  - [deuxième](resultats/l3-certificats_l3-deuxieme-passage.log) : la vérification **attendue en échec** par la CA du PoC arrêtait le script (`pipefail`).
- `controle_l3`, [premier passage](resultats/l3-controle_l3-premier-passage.log), avec trois défauts :
  - le contrôle a démarré 30 s après les agents, pendant la relecture de l'historique : le journal de `sc-confiance` et de `sc-stockage` n'était pas encore arrivé ;
  - les comptes sans étiquette étaient lus dans la mauvaise colonne (`$2` au lieu du dernier champ), d'où des 0 partout ;
  - la fenêtre de 168 h remontait avant le début du schéma de Loki, d'où 1 476 avertissements « Query does not fit in a single sharding configuration ».

  Corrigé : attente de la présence du journal des trois nœuds, dernier champ, fenêtre de 24 h.

| # | Mesuré | Verdict |
|---|---|---|
| 1 | `relais` et `alloy-stockage` vérifiés par la CA du PoC ; `alloy-sc-confiance` et `alloy-sc-build` vérifiés par leur autorité, **refusés par la CA du PoC** (erreur 20, « unable to get local issuer certificate ») ; clés en 0600 | conforme |
| 2 | `list events -A` et `watch events.events.k8s.io -A` : `yes` ; `get secrets`, `list pods`, `pods/log`, `create events` : `no` | conforme |
| 3 | Avant : `["fichier/"]`. ConfigMap vue par le pod, puis SIGHUP : `fichier/` et `sortie/` (`stdout`), 3 lignes `request` sur la sortie standard dans les 30 s ; **OpenBao descellé** (`sealed: false`), sans redémarrage | conforme, prédiction faible comprise |
| 4 | Sur les trois VM : empreinte vérifiée, Alloy v1.21.3 (`f2108cd`), `alloy validate` réussi, `active` ; aucune erreur, aucun avertissement ; tous les composants `healthy` | conforme |
| 5 | Comptes sur 24 h :<br>• J1, journal : `k3s.service` de `sc-confiance` 19 532, `sc-build` 13 315, `forgejo.service` 2 861<br>• J8, récepteur d'alertes : 19<br>• J2, pods : `tekton-chains` 3 702, `sc-build` 2 825<br>• J3, audit k8s : 37 912<br>• J4, événements : 962<br>• **J5, audit d'OpenBao par la sortie du pod : 7**<br>• J6, audit de Zot : 2 405 | conforme |
| 6 | Certificat de `sc-build` refusé par Loki (000) et par le port de `sc-confiance` (000) ; sur son port, une ligne étiquetée `noeud=sc-confiance` est **stockée sous `noeud=sc-build`** | conforme |
| 7 | L'auditeur lit 5 lignes du journal de k3s à travers Grafana (HTTP 200) | conforme |
| 8 | Alloy : 127, 96 et 125 Mi ; `sc-stockage` : 4 220 Mi disponibles, Loki 417 Mi | conforme |
| 9 | Seuil non atteint (témoins datés et « source muette » en L4) | conforme |

**Constats :**
- **Relecture de l'historique** : en moins de 3 min, Loki a reçu environ 140 000 lignes de journal sur 7 jours, plus les fichiers existants (audit k8s, audit de Zot, pods).
  - `/var/lib/loki` : 179 Mo ;
  - disque de `sc-stockage` : de 40,4 % à 44,6 %, binaires d'Alloy compris.
- **Pods de `sc-build`** : les lignes ont l'horodatage CRI d'origine. Les fichiers anciens n'apparaissent donc pas dans une fenêtre de 10 min, ce qui n'est pas une perte : 2 825 lignes sur 24 h.
- **Loki sous `RestrictAddressFamilies`** : 16 avertissements « error getting network interfaces … address family not supported ». Il lui manque `AF_NETLINK`, sans effet mesuré. C'est du bruit ; ajouter `AF_NETLINK` reste à décider.
- **La 08 a changé** (D15 a) : `config.hcl` déclare `sortie/`. Au prochain `openbao.sh deployer`, le pod sera recréé, donc scellé, et la procédure de descellement de la 08 s'appliquera.

## L4, préparation à sec (02/11/2026 ; rien exécuté)

Étapes `prometheus_alloy temoins secrets muette` (`JALON=l4`). Prédictions : [`l4-predictions.md`](resultats/l4-predictions.md).

- **Témoins** : un marqueur daté par source, émis par le moyen le plus direct, puis lu **par l'auditeur à travers l'API de Grafana** (`/api/ds/query`), avec le délai mesuré, en 120 s au plus.
  - J1 : `logger` sur chaque VM ;
  - J2 : écriture sur la sortie standard d'un conteneur, `openbao-0` sur `sc-confiance` et l'agent Cilium sur `sc-build`. `sc-build` porte la taint `zone=build`, et c'est le seul pod hors de `builds` qui y tourne ;
  - J3 : ConfigMap créée puis supprimée ;
  - J4 : objet Event ;
  - J5 : lecture d'un chemin inexistant dans OpenBao ;
  - J6 : étiquette poussée dans Zot par `poc-ecriture` ;
  - J8 : notification postée au récepteur.
- **Secrets** :
  - tout Loki est exporté sur l'hôte, dans un répertoire 0700 supprimé ensuite, depuis le début du schéma ;
  - on y cherche chaque secret de `…/08/secrets` par `grep -F -f` sur un fichier de motifs : aucune valeur n'apparaît en argument, dans une requête LogQL ou dans un journal. Seul le nombre de lignes trouvées par fichier est affiché ;
  - un témoin positif, une valeur aléatoire écrite dans Loki, doit être retrouvé.
- **Source muette** :
  - règles `SourceMuette` et `LokiInjoignable` dans les règles de la 19, avec leurs tests. promtool a donné `SUCCESS` sur 11 règles. Deux mutations sont détectées : fenêtre de 3 min, et codes 5xx comptés comme réussis ;
  - Prometheus collecte Alloy de `sc-stockage` (job `alloy`, `127.0.0.1:12345`) ;
  - essai réel : Alloy de `sc-build` est arrêté jusqu'au déclenchement, avec deux témoins écrits pendant l'arrêt et retrouvés après la reprise (absence de perte).
- **Défaut trouvé à la relecture, avant exécution** : la réponse de `/api/ds/query` contient le texte de la requête. Un marqueur jamais émis y figure 1 fois, contre 0 dans les lignes de données (sonde du 02/11/2026). La recherche porte donc sur les lignes seules, avec une contre-épreuve. L2 et L3 n'étaient pas touchés : ils sélectionnaient sans marqueur ou comptaient des lignes.
- **Secrets, garde-fous ajoutés** :
  - total exporté comparé au compte de Loki ;
  - code HTTP vérifié page par page ;
  - copies de secrets effacées même en cas d'échec (`trap`) ;
  - secrets propres aux VM ajoutés : jetons de k3s, jeton de métriques et `app.ini` de Forgejo.
  - **Premier essai du test de `SourceMuette` faux** : j'attendais l'alerte en attente à 15 min. Prometheus 3 évalue les fenêtres ouvertes à gauche : la fenêtre (9 min, 14 min] ne voit plus de hausse dès 14 min, donc elle se déclenche à 16 min. Attendu corrigé, commentaire dans le test.

## L4, exécuté (02/11/2026, 21:13 à 21:34 UTC, accord du propriétaire : « Oui, lancer L4 »)

Commandes :
- `JALON=l4 mise run journalisation -- prometheus_alloy`, puis `JALON=l4 mise run observabilite -- regles deployer` (19) ;
- `JALON=l4 mise run journalisation -- temoins secrets muette`.

Journaux :
- [`l4-prometheus_alloy.log`](resultats/l4-prometheus_alloy.log) : il contient la trace d'une erreur Python, née de l'attente de la cible pendant le redémarrage de Prometheus, puis la cible `alloy` `up` ;
- [`l4-cibles.log`](resultats/l4-cibles.log) : premier relevé 13 s après le redémarrage de `deployer`, d'où `unknown` partout ; second à 21:29:43 ;
- [`l4-temoins.log`](resultats/l4-temoins.log), [`l4-secrets.log`](resultats/l4-secrets.log), [`l4-muette.log`](resultats/l4-muette.log) ;
- [`l4-muette-analyse.log`](resultats/l4-muette-analyse.log) et [`l4-evenements-horodatage.log`](resultats/l4-evenements-horodatage.log).

**Passages archivés :**
- `temoins` :
  - [premier](resultats/l4-temoins-premier-passage.log) : Event refusé par l'API (`involvedObject.namespace` vide) ;
  - [deuxième](resultats/l4-temoins-deuxieme-passage.log) : Event témoin sans horodatage (`firstTimestamp`, `lastTimestamp` et `eventTime` nuls), **jamais collecté**, absent de Loki depuis le début du schéma. Les vrais événements sont horodatés : un seul des 918 ne l'était pas, et c'était le témoin. Le témoin est désormais daté comme un vrai événement.
- `secrets` :
  - [premier](resultats/l4-secrets-premier-passage.log) et [deuxième](resultats/l4-secrets-deuxieme-passage.log) : pages de 5 000 lignes. Loki journalise « ResourceExhausted » sur un message gRPC interne de plus de 4 Mo, et curl échoue (« bad decrypt »). Corrigé : pages de 1 000 lignes, nouvel essai sur erreur ;
  - [troisième](resultats/l4-secrets-troisieme-passage.log) : 213 lignes manquantes, perdues à la reprise de page (horodatage maximal + 1) ; et les secrets de Forgejo cherchés dans `app.ini`, qui ne contient que leurs chemins (`*_URI = file:…`).
  - Les copies de secrets ont été effacées après chaque échec : vérifié, aucune copie restante dans le répertoire de travail.

| # | Mesuré | Verdict |
|---|---|---|
| 1 | Configuration valide ; 9 cibles `up`, dont `alloy` (21:29:43) | conforme |
| 2 | 11 règles, tests réussis ; toutes `ok`, `inactive` | conforme |
| 3 | **Contre-épreuve : marqueur jamais émis absent.** Les dix témoins sont lus par l'auditeur à travers Grafana, **en 2 à 5 s** (J1 sur les trois nœuds, J2 sur `sc-confiance` et `sc-build`, J3, J4, J5, J6, J8). J5 : le chemin `sys/policy/<marqueur>` figure en clair dans l'audit d'OpenBao. J6 : l'étiquette poussée figure dans l'audit de Zot | conforme, prédictions faibles comprises |
| 4 | 45 fichiers de motifs, dont 6 lus sur les VM (jetons de k3s, quatre secrets de Forgejo) : **0 ligne pour chacun ; témoin positif : 1 ligne**. 326 597 lignes exportées pour 326 558 comptées par Loki | conforme pour les secrets ; **écart de 39 lignes (0,01 %) non expliqué** |
| 5 | Alloy de `sc-build` arrêté à 21:29:38. **`SourceMuette` `{noeud="sc-build"}` `firing` en 180 s**, notifiée. Relancé à 21:32:49 : **les deux témoins écrits pendant l'arrêt sont lus dans Grafana** (reprise sans perte). Résolution 210 s après l'arrêt, notifiée. Une notification `firing` et une `resolved` | conforme, sauf le délai (**faux** : 6 à 8 min prévus) |

**Écart de l'export.** L'export compte 39 lignes de plus que Loki. Une page manquante donnerait moins de lignes, et chaque page a répondu 200 : l'export ne manque donc pas de page. La cause de l'excédent n'est pas mesurée. Hypothèses non vérifiées : un comptage approché de `count_over_time` par découpage de la requête, ou des lignes de même horodatage et même texte, gardées par l'export et regroupées par Loki. La conclusion « aucun secret » porte sur les 326 597 lignes exportées.

**Délai de `SourceMuette` : constat qui la rend inutilisable telle quelle pour `sc-build`.** Les 180 s ne viennent pas de la règle, mais du trafic.
- Avant l'arrêt, `sc-build` n'avait rien envoyé depuis 21:26 : silence naturel de 3 min 30.
- Sur la journée (13:00 à 21:29), **`sc-build` est resté silencieux 5 min ou plus à 23 reprises, jusqu'à 27 min** (`l4-muette-analyse.log`). Il n'a pas de build en continu, et son journal système est calme.
- La règle se déclencherait donc régulièrement à tort pour ce nœud. Depuis L3, la relecture de l'historique masquait ces silences.
- `sc-confiance` (plus de 2 000 lignes par 5 min) et `sc-stockage` ne sont pas concernés à ce jour, mais rien ne le garantit.
- **Proposé, D18 : un battement de cœur.** Un timer systemd sur chaque VM écrit une ligne par minute (`logger -t battement-19b`). `SourceMuette` signifie alors « chaîne de collecte rompue », et non « nœud calme ». Cela installe un timer sur les trois VM : accord requis.

**Seuil de la brique :** témoins de toutes les sources retenues lus dans Grafana en moins de 2 min (atteint) ; aucun secret connu dans Loki (atteint, avec l'écart de 39 lignes) ; alerte « source muette » déclenchée à l'arrêt d'un agent, sans perte (atteint). **Réserve** : sans D18, l'alerte n'est pas exploitable pour `sc-build`, à cause des fausses alertes. Le seuil est donc **atteint avec réserve**, levée par D18 et un nouvel essai.

Limites :
- `LokiInjoignable` n'est éprouvée que par promtool ;
- l'arrêt d'Alloy de `sc-stockage` relève de `CollecteEnPanne`, non éprouvée ici ;
- résidu dans Zot : `essais-19b/temoin`, trois étiquettes (une par passage), que `poc-ecriture` ne peut pas supprimer ;
- les témoins J2 passent par `kubectl exec`, dont ceux dans l'agent Cilium privilégié de `kube-system` ;
- pare-feu par NetworkPolicies à faire après validation (décision du propriétaire).

## D18 : battement de cœur ; retenue par le propriétaire le 02/11/2026 (« Oui, D18 »). L5, préparé à sec

- **Unités** : [`systemd/battement-19b.service`](systemd/battement-19b.service) et [`systemd/battement-19b.timer`](systemd/battement-19b.timer). Une ligne `logger -t battement-19b` par minute, sous un compte dynamique, sans réseau.
- **Étapes** (`JALON=l5`) :
  - `battement` : installation sur les trois VM ;
  - `silences` : après au moins 12 min, plus long silence par nœud dans Loki, minimum de l'expression de `SourceMuette` depuis l'installation, état de l'alerte ;
  - puis un nouvel essai de `muette`.
- Prédictions : [`l5-predictions.md`](resultats/l5-predictions.md).

## L5, exécuté (02/11/2026, 21:57 à 22:19 UTC, accord du propriétaire : « Oui, lancer L5 »)

Journaux : [`l5-battement.log`](resultats/l5-battement.log), [`l5-silences.log`](resultats/l5-silences.log), [`l5-muette.log`](resultats/l5-muette.log).

| # | Mesuré | Verdict |
|---|---|---|
| 1 | Timer `battement-19b` `active` sur les trois VM (21:58:00) | conforme |
| 2 | De 21:58 à 22:11 : **plus long silence de 0 min** sur les trois nœuds ; battements sur les 10 dernières minutes : 10 (`sc-confiance`), 9 (`sc-build`), 9 (`sc-stockage`) ; minimum de l'expression de `SourceMuette` : **17,8 pour `sc-build`** (0 avant D18), 2 022 pour `sc-confiance` ; `SourceMuette` `inactive` | conforme |
| 3 | Alloy de `sc-build` arrêté à 22:11:11 : **`SourceMuette` `firing` après 420 s** (6 à 8 min prévus), notifiée. Relancé à 22:18:17 : les deux témoins écrits pendant l'arrêt sont lus dans Grafana. Résolution 446 s après l'arrêt ; une notification `firing` et une `resolved` | conforme |

Un faux départ de ma part, sans effet : 14 s après l'installation, un seul battement était arrivé par nœud, et je l'ai pris pour un défaut. Le timer ne s'était déclenché qu'une fois.

**Réserve de L4 levée. Seuil de la brique 19b atteint** :
- chaque source retenue (J1 à J6, J8) est retrouvée par l'auditeur à travers l'API de Grafana en moins de 2 min (2 à 5 s) ;
- aucun secret connu dans Loki (écart de 39 lignes de l'export consigné) ;
- l'alerte « source muette » se déclenche quand un agent s'arrête, sans perte de lignes, et ne se déclenche plus sur un nœud calme.

**Limites consignées** :
- `LokiInjoignable` et l'arrêt d'Alloy de `sc-stockage` (`CollecteEnPanne`) ne sont pas éprouvés en réel ;
- les lectures de l'API Kubernetes ne sont pas auditées (D14 a) ;
- Grafana OSS n'a pas d'audit de ses utilisateurs : seules les requêtes HTTP sont tracées ;
- Loki n'est pas infalsifiable : la suppression est refusée, mais root sur `sc-stockage` peut tout effacer ;
- bruit dans les journaux : une erreur par requête avec la suppression désactivée, `AF_NETLINK` absent dans l'unité de Loki ;
- résidu dans Zot (`essais-19b/temoin`) ;
- le pare-feu par NetworkPolicies reste à faire, après validation (décision du propriétaire).

## Constat du 03/11/2026 : mTLS contourné par le gRPC de dskit

Découverte fortuite en préparant le pare-feu, pas une mesure planifiée : aucune prédiction écrite avant. Rien n'a été écrit dans Loki ni modifié sur le cluster. Journal : [`constat-grpc-relais.log`](resultats/constat-grpc-relais.log).

**Mesuré** (requête `httpgrpc.HTTP/Handle` `GET /ready` construite à la main, envoyée avec curl en HTTP/2 sans TLS) :

| Cible | Depuis | Sans certificat client |
|---|---|---|
| Relais Alloy, ports TLS 3501 et 3502 | hôte | refusé (`certificate required`) |
| Relais Alloy, gRPC `*:35459` et `*:38365` (ports tirés au hasard) | hôte (les deux ports), `sc-stockage` (35459) ; depuis l'hôte de `sc-build`, connexion TCP seulement (les deux ouverts) | **200, « ready »** |
| Loki, port TLS 3100 | `sc-stockage` | refusé (`certificate required`) |
| Loki, gRPC `127.0.0.1:9096` | `sc-stockage` | **200, « ready »** |

**Cause, lue dans le code** (Alloy v1.21.3 `f2108cd`, dskit `8b24b9af5808`) :
- dskit enregistre toujours, sur son serveur gRPC, le pont `httpgrpc`, qui sert tout le routeur HTTP. Le TLS du bloc `http` ne s'y applique pas.
- `loki.source.api` prend par défaut un gRPC sur toutes les interfaces, sur un port libre. Le repli sur 127.0.0.1 prévu dans `api.go` ne joue jamais, parce que `SetToDefault` remplit déjà le bloc.
- Les gestionnaires ne contrôlent pas le certificat client.
- Connu en amont, sans l'angle TLS : [grafana/alloy#6071](https://github.com/grafana/alloy/issues/6071), ouvert le 16/04/2026 et non corrigé.
- **Additif du 03/11/2026, après lecture de la documentation d'Alloy v1.21.3** : le gRPC n'est pas caché. La page de `loki.source.api` annonce que le composant « receives log entries over HTTP and gRPC ». Elle documente un bloc `grpc` > `tls` distinct de `http` > `tls`, ainsi que l'écoute par défaut sur toutes les interfaces, sur un port au hasard. Notre configuration ne l'avait pas fermé : c'est notre oubli. Ce qui n'est pas documenté : ce point d'entrée existe même sans bloc `grpc`, et reste alors sans TLS. Le repli sur 127.0.0.1 prévu par le code (`api.go`) ne joue jamais.
- **Décision du propriétaire (03/11/2026) : « Ne rien signaler »** à Grafana, ni en privé ni sur #6071.

**Conséquences** :
- **D17** : par le relais, toute machine qui joint `192.168.161.13` pourrait écrire dans Loki sous `noeud="sc-confiance"` ou `noeud="sc-build"` (déduit du code, écriture non essayée). La joignabilité depuis un pod n'est pas mesurée.
  - **Additif du 03/11/2026, mesuré** : l'écriture a été essayée sur l'hôte, avec les configurations d'avant le constat prises dans git, les mêmes binaires et une PKI jetable ([`constat-grpc-ecriture-essai-local.log`](resultats/constat-grpc-ecriture-essai-local.log)). Sans aucun certificat :
    - un push par chacun des deux ports au hasard du relais, envoyé depuis l'adresse réseau de l'hôte, est accepté (204) et stocké sous `noeud="sc-build"` pour l'un, `noeud="sc-confiance"` pour l'autre ;
    - un push par le gRPC de Loki est stocké avec l'étiquette envoyée telle quelle (`noeud="usurpe"`).

    Contre-épreuve, avec les configurations de L6 : en clair comme en TLS sans certificat, refus sur les trois ports, et aucune ligne dans Loki. Rien n'a été écrit dans le Loki d'audit.
- **D16** : tout processus local de `sc-stockage` (Forgejo, Zot, Grafana…) atteint Loki sans certificat. Il peut donc lire et écrire tous les journaux.
- **Le seuil de la brique** (témoins, secrets, source muette) ne portait pas sur ces garanties. Il n'est pas modifié ici : la décision revient au propriétaire.

**Correctifs possibles, lus dans le code, non essayés** :
- un bloc `grpc` explicite dans chaque `loki.source.api` de `relais.alloy` (gabarit de `journalisation.sh`) :
  - (a) `listen_address = "127.0.0.1"` seul, qui ramène le relais au niveau actuel de Loki ;
  - (b) en plus, `tls { client_auth_type = "RequireAndVerifyClientCert" … }`, appliqué au serveur gRPC par dskit ;
- pour Loki, `server.grpc_tls_config`. Il faut alors des certificats pour ses propres clients gRPC internes (à vérifier dans Loki 3.7.9, dont la version de dskit n'a pas été lue).

**Limites du constat** :
- Les lignes stockées sous `noeud="sc-confiance"` ou `noeud="sc-build"` entre L3 (02/11/2026, 21:03 UTC) et le correctif n'ont pas la garantie de D17. Une injection par le gRPC ne peut pas être exclue, parce que le serveur gRPC du relais ne journalise pas ses requêtes : dskit est lancé avec `RegisterInstrumentation=false`.
- Pour la même raison, une écriture directe dans Loki par un processus local de `sc-stockage` ne peut pas être exclue sur cette période.

### Additif du 03/11/2026 : choix (b) du propriétaire, L6 préparé

Choix du propriétaire : « TLS sur le gRPC (b) ».

**Correctif préparé** :
- `config/loki.yaml` :
  - `grpc_tls_config` avec certificat client exigé, sur la CA du PoC, comme pour le HTTP ;
  - les clients gRPC internes de Loki présentent un nouveau certificat, `loki-interne`.
- `relais.alloy` :
  - un bloc `grpc` par source, sur la boucle locale, avec des ports fixes (3511, 3512) ;
  - le même certificat et la même autorité que le bloc `http` de la source.
- Jalon L6 dans `journalisation.sh` :
  - sauvegarde, validation sur copie, Alloy rechargé par SIGHUP puis Loki redémarré, retour arrière automatique ;
  - sondes avant et après, matrice des certificats ;
  - comptage des battements de journald et de Loki, pour mesurer l'absence de perte.

**Essai local sur l'hôte** ([`correctif-grpc-essai-local.log`](resultats/correctif-grpc-essai-local.log)) : binaires des archives vérifiées, PKI jetable, 127.0.0.1, sans installation.
- `loki -verify-config` a refusé `frontend_worker.grpc_client_config` à côté de `query_frontend_grpc_client` et `query_scheduler_grpc_client`. Le gabarit est corrigé.
- Loki a démarré tous ses services. L'écriture et la requête ont traversé le chemin interne en gRPC TLS.
- Le gRPC de Loki et celui du relais refusent la connexion en clair, sans certificat, et avec une autre autorité. Ils répondent avec la bonne autorité.
- Chaque port du relais n'accepte que l'autorité de sa source.
- Plus aucun port d'Alloy n'est ouvert au hasard.
- Le relais HTTP est inchangé (étiquette `noeud` imposée).

Prédictions : [`l6-predictions.md`](resultats/l6-predictions.md). Posé sur `sc-stockage` en L6, ci-dessous.

## L6, exécuté (03/11/2026, 08:55 à 08:59 UTC, accord du propriétaire : « Oui, lancer L6 »)

Commandes :
- `JALON=l6 mise run journalisation -- certificats_grpc avant_grpc grpc_tls controle_grpc`
- `controle_grpc`, rejoué après une correction du script
- `controle_l3 temoins pertes_grpc`

Journaux : `resultats/l6-*.log`, dont [`l6-complement.log`](resultats/l6-complement.log), relevé en lecture seule après le passage.

| # | Mesure | Verdict |
|---|---|---|
| 1 | `loki-interne` vérifié `OK` par la CA du PoC, clé en 600 | conforme |
| 2 | Avant : Alloy écoute sur `*:35459` et `*:38365`, ouverts depuis l'hôte ; `httpgrpc` en clair répond « ready » sur ces deux ports et sur 9096 ; en TLS, échec de la poignée (`wrong version number`) | conforme |
| 3 | `config is valid`, copie d'Alloy valide ; Alloy rechargé par SIGHUP (**même PID 48561**, relais rechargé en 1 s) ; Loki `/ready` 200 **19 s** après le redémarrage ; erreurs : arrêt de l'ancien querier (`context canceled`, 4), `empty ring` au démarrage, **un push refusé (500, `empty ring`) pendant le démarrage** ; aucune erreur TLS | **conforme, avec écart** : le push refusé et les 4 `context canceled` n'étaient pas prévus. Le push est réessayé par l'Alloy de `sc-stockage` (48e nouvelle tentative, à 08:56), et rien n'est perdu (`loki_write_dropped_entries_total` à 0) |
| 4 | Après : **plus aucun port sur `*`** (Alloy : 3501 et 3502 sur `192.168.161.13` ; 3511, 3512 et 12345 sur `127.0.0.1` ; Loki : 3100 et `127.0.0.1:9096`) ; en clair, échec du cadrage HTTP/2 ; sans certificat, `certificate required` ; depuis l'hôte, seuls 3100, 3501 et 3502 ; matrice des certificats identique à la prédiction (9096 : `loki-interne` et `controle` acceptés, certificats des nœuds refusés en `unknown ca` ; 3511 : `alloy-sc-confiance` seul ; 3512 : `alloy-sc-build` seul) | conforme |
| 5 | Dans les 10 dernières minutes, des lignes des trois nœuds (dont `audit-k8s`, `pods` et `journal` de `sc-confiance`, et `journal` de `sc-build`, par le relais). **Ce tableau ne prouve pas la reprise** : relevé 40 s après le redémarrage, il porte surtout sur des lignes d'avant L6. La reprise est prouvée par les témoins (ligne 6) et les battements (ligne 7) ; D17 inchangée (certificat de `sc-build` refusé par Loki et par 3501, ligne `noeud=sc-confiance` stockée sous `sc-build`) ; l'auditeur lit k3s par Grafana ; Alloy : 0 erreur sur les trois VM | conforme |
| 6 | Dix témoins lus par l'auditeur dans Grafana en 2 à 5 s, contre-épreuve comprise | conforme |
| 7 | Battements de journald et de Loki sur 08:53:11 à 08:57:30 ([premier relevé](resultats/l6-pertes_grpc-fenetre-4min.log)) : 4 et 4 (`sc-confiance`), 5 et 5 (`sc-build`), 4 et 4 (`sc-stockage`) ; relevé de 08:59 sur 08:53:11 à 08:58:33 : 5 et 5, 6 et 6, 5 et 5 ; aucune alerte active. Le battement de `sc-build` de **08:55:21 est tombé pendant l'arrêt de Loki** (08:55:12 à 08:55:31) : passé par le relais, il a été réessayé puis livré. Compteurs `loki_write_dropped_entries_total` à 0 sur les trois VM ([complément](resultats/l6-complement.log)) | conforme |

**Écart du script, sans effet sur les services** : au premier passage de `controle_grpc` ([archivé](resultats/l6-controle_grpc-premier-passage.log)), les certificats acceptés recevaient `grpc-status: 2`.
- La trame gRPC était gardée dans une variable bash, et bash tronque une chaîne au premier octet nul : la trame envoyée était vide. La poignée TLS avait pourtant réussi, puisque le serveur répondait un statut gRPC.
- Le piège de fermeture du tunnel lisait une variable locale déjà détruite (`unbound variable`). Le tunnel était fermé quand même par la fin normale de l'étape.
- Après correction (trame écrite par une fonction, piège développé à sa pose), le second passage est conforme.

**Constat (mesuré au niveau de journalisation actuel, `info`)** : les refus du gRPC (`unknown ca`, `certificate required`) n'apparaissent dans aucun journal. Le serveur gRPC de dskit ne trace pas les poignées échouées, alors que le serveur HTTP de Go les trace (`http: TLS handshake error`). Une tentative refusée sur 9096, 3511 ou 3512 ne laisse donc pas de trace d'audit. Ces ports n'écoutent que sur la boucle locale.

**D16 et D17 rétablies en l'état déployé** :
- sur le relais, seuls les certificats de l'autorité du nœud sont acceptés, en HTTP comme en gRPC ;
- sur Loki, seuls les certificats de la CA du PoC sont acceptés, en HTTP comme en gRPC.

La limite de D16 demeure : tout porteur d'un certificat de la CA du PoC lit et écrit tous les journaux. La période de L3 à L6 reste sans garantie (voir les limites du constat).

**Résidus** : `/etc/loki/loki.yaml.avant-l6` et `/etc/alloy/relais.alloy.avant-l6` sur `sc-stockage`, pour un retour arrière manuel.

**Point ouvert résolu (refus de débit au démarrage de L3)** : à sa première collecte par Prometheus (02/11, 21:15), l'Alloy de `sc-stockage` comptait 47 nouvelles tentatives et 0 ligne perdue. Ce processus tourne depuis 21:03, et c'est le seul écrivain régulier de Loki. Les 47 refus `ingestion rate limit exceeded` de Loki (21:03 et 21:04) ont donc été réessayés, sans perte ([complément](resultats/l6-complement.log)).

## L7, domaine de replay de la brique 10 : préparation à sec (03/11/2026, 15:43 UTC ; rien écrit dans Loki)

Demande du propriétaire du 03/11/2026 : « Replay dans Grafana ». À la clôture de la brique 10, deux points restaient ouverts : le domaine de replay n'envoie aucun journal à Loki, et la corroboration de `timeVerified` par l'audit de Zot n'a pas été faite.

**Relevé de la VM `sc-replay`** (03/11/2026, vers 15:39 UTC, lecture seule par SSH avec la clé du domaine, non archivé dans un journal) :
- le journal systemd est persistant (`/var/log/journal`). Il n'y a qu'un démarrage, depuis le 03/11/2026 à 10:00:43 UTC : **3 172 entrées**, 3,4 Mo en JSON, 8 Mo sur le disque ;
- entrées par unité : `init.scope` 790, `user@1000.service` 689, `systemd-logind` 315, `ssh` 251, `cloud-init-main` 38, puis les sessions ; 75 lignes `sudo` ;
- `replay-r4.service` n'a que **10 lignes** (démarrage, arrêt, consommation). La sortie du build va dans des fichiers, rapatriés dans `resultats/` de la 10 ;
- le compte `replay` n'est pas dans le groupe `systemd-journal` : la lecture complète passe par `sudo`.

### Étape `corroborer_vsa` (préparée, lecture seule)

L'auditeur lit, à travers Grafana, les écritures de `poc-replay` sous `builds/vsa/` dans l'audit de Zot (J6), puis l'heure du PUT du manifeste de la VSA est comparée à `timeVerified`. Une contre-épreuve vérifie qu'un marqueur jamais émis est bien absent. Prédictions : [`l7-predictions.md`](resultats/l7-predictions.md). Portée : une **borne haute** de l'heure du replay, pas la borne basse des 24 h.

### Journal de la VM dans Loki : contraintes et décisions à prendre

Contraintes (mesurées ou lues, pas supposées) :
- **réseau** : la VM ne joint pas `sc-stockage` (R2 de la 10, réseau distinct choisi par le propriétaire) ;
- **suppression impossible dans Loki** (D10, 403 mesuré en L2) : un secret écrit ne s'efface plus. Le contrôle des secrets se fait donc **avant** l'envoi, pas après ;
- **secrets du domaine** : le mot de passe et la clé privée de la VSA ne sortent pas de la VM (D6 de la 10). La recherche de ces motifs se fait dans la VM ; celle du mot de passe de `poc-replay` et de la clé SSH du domaine, sur l'hôte ;
- **âge** : Loki refuse les lignes de plus de 168 h (`reject_old_samples_max_age`). Le journal de la VM (depuis le 03/11, 10:00:43 UTC) passe en entier ; un domaine resté plus de 7 jours sans envoi perdrait le début ;
- **alerte** : l'expression de `SourceMuette` ne retient que `loki.source.api.(confiance|build)`. Une source envoyée par lots ne déclenche donc pas de fausse alerte, mais elle n'est pas couverte non plus ;
- **doc d'Alloy v1.21.3** (sources au tag, `f2108cd`) : `loki.source.journal` accepte un `path` vers un répertoire de journal. Il faudrait alors copier les fichiers binaires de la VM et lancer Alloy sur l'hôte. La voie `journalctl -o json` et jq est plus simple, et le contrôle des secrets porte exactement sur les octets envoyés.

**D19. Transport.**
- (a) **Lots tirés par l'hôte**, comme les entrées en R3 : `sudo -n journalctl -o json --after-cursor=…` par SSH, avec la clé du domaine. Le curseur est gardé dans le dossier du domaine sur l'hôte, ce qui évite trous et doublons d'un lot à l'autre. Un lot est envoyé à la fin de chaque intervention dans le domaine, ou à la demande. La VM et son réseau ne changent pas. L'envoi n'est pas en temps réel.
- (b) **Alloy dans la VM**, avec une route vers le relais. Cela revient sur le réseau distinct de R2, installe un paquet dans la VM, et donne au domaine un certificat d'écriture vers le plan de confiance.
- Recommandé : (a).

**D20. Identité d'écriture.**
- (a) **Un port 3503 du relais**, avec une autorité propre au domaine dont la clé reste dans `~/.cache/supply-chain-poc/10/`. Le relais impose l'étiquette `noeud="sc-replay"`, et ce certificat ne lit pas Loki (D17). Il faut modifier `relais.alloy` sur `sc-stockage`, avec un rechargement par SIGHUP comme en L6, et ouvrir le bloc `grpc` sur la boucle locale (3513).
- (b) **Le certificat `controle` de l'hôte**, directement vers Loki. Rien ne change sur `sc-stockage`, mais les étiquettes sont libres, le porteur lit tout Loki, et l'audit ne distingue pas le domaine des essais.
- Recommandé : (a).

**D21. Périmètre.**
- (a) **Journal de la VM seul** : sshd, sudo, unités `systemd-run`, noyau, apt. Les journaux d'étape de `replay.sh` (sortie du build, compteurs du lien relevés par `virsh`, VSA) restent dans `resultats/` et dans git. Ils relèvent de J9 (scripts lancés depuis l'hôte), exclu par D9.
- (b) **En plus, les fichiers `resultats/` de la 10**, envoyés une fois avec une étiquette `fichier`. Ces lignes n'ont pas d'heure propre : elles seraient datées de l'envoi, pas de l'événement.
- Recommandé : (a). C'est un choix à confirmer, parce qu'il laisse hors de Grafana la preuve « 0 connexion sortante » (compteurs du lien).

**Mécanique prévue avec D19 (a)** (à essayer d'abord sur l'hôte, avec un Loki jetable tiré des archives vérifiées, comme le correctif du gRPC) :
- étiquettes reprises de [`commun/journal.alloy`](config/alloy/commun/journal.alloy) : `source="journal"`, `unite` (`_SYSTEMD_UNIT`, sinon `SYSLOG_IDENTIFIER`), `priorite` (mot clé de `PRIORITY`), plus `noeud="sc-replay"` ; la ligne est `MESSAGE`, et son heure `__REALTIME_TIMESTAMP` ;
- lots de 500 lignes, envoyés dans l'ordre chronologique, avec un nouvel essai sur 429 ou 5xx (refus de débit vus en L3) ;
- contrôles : sha256 du lot dans la VM et sur l'hôte ; recherche des secrets des deux côtés, chacun avec un témoin positif ; compte de journald égal au compte de Loki, unité par unité ; une ligne témoin `logger` dans la VM, lue par l'auditeur dans Grafana ; un second lot vide (pas de doublon).

**Ordre** : le journal est exporté **avant** tout nettoyage de `~/r5n`, de `/var/lib/replay-buildkit-n` ou de la VM, qui l'emporterait. `~/r4` et `~/r3` ne sont pas touchés.

**Limites, à consigner quel que soit le choix** :
- journald n'est pas scellé (pas de FSS) ;
- le root de l'hôte peut altérer un lot avant son envoi. C'est le même administrateur que le domaine (D1 b de la 10) ;
- aucune alerte de source muette pour le domaine.
