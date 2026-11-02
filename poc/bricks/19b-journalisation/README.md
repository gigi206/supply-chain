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
