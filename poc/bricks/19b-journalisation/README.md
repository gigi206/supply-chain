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
| J3 | **Audit de l'API Kubernetes** : qui a fait quoi sur le cluster | serveur k3s (`sc-confiance`) | `--audit-policy-file` et `--audit-log-path` sur le serveur k3s : **redémarrage du serveur k3s** (installation système, accord requis), puis modification des scripts de la 08 pour que ce réglage survive à un rejeu | rouvre l'installation de la 08 |
| J4 | Événements Kubernetes, dont les refus de Kyverno et les PolicyReports | API | collecteur avec un compte de lecture (sans Secrets), comme pour Prometheus en O2 | un compte de plus |
| J5 | **Audit d'OpenBao** : chaque signature Transit, chaque connexion | pod OpenBao | `bao audit enable file` (sortie standard ou fichier). **OpenBao refuse les requêtes s'il ne peut écrire dans aucun journal d'audit (fermé par défaut)** : à mesurer, sinon un disque plein arrête les signatures | modification de la 08 (`openbao.sh`) |
| J6 | Audit de Zot : écritures et suppressions par compte | `sc-stockage` | `log.audit` dans la configuration de Zot | modification de la 08 (registre) |
| J7 | Flux réseau refusés (Hubble de Cilium) | 3 VM | export des flux Hubble vers un fichier | volume à mesurer ; optionnel |
| J8 | Notifications d'Alertmanager | `sc-stockage` | déjà dans journald (récepteur) : couvert par J1 | aucun |
| J9 | Scripts du PoC lancés depuis l'hôte (`mise run …`) | laptop | collecteur **sur votre ordinateur** (installation système) ; leurs journaux sont déjà versionnés dans `resultats/` | proposé : non |

### Décisions (numérotation reprise de la 19) : **toutes retenues par le propriétaire le 02/11/2026 (« Oui, toutes »)**

- **D8. Pile** : Loki et Grafana sur `sc-stockage` (hors confiance, comme Prometheus, D1 a), binaires vérifiés en services systemd. Collecteur : **Alloy**. Promtail est interdit, Fluent Bit est à surveiller, Vector n'est pas jugé. Loki et Alloy sont « un seul éditeur » (Grafana Labs), comme Grafana. Recommandé : (a) Loki, Alloy et Grafana. Alternative : (b) VictoriaLogs, qui n'apparaît pas dans l'API Scorecard et dont l'éditeur est déjà « à surveiller » pour VictoriaMetrics (5,4).
- **D9. Périmètre** : recommandé J1 à J6 et J8. J7 en option, après une mesure de volume. J9 exclu. J3, J5 et J6 modifient la 08 : décision distincte, avec son coût de rejeu.
- **D10. Intégrité** : Loki ne rend pas un journal infalsifiable. Proposé :
  - API de suppression de Loki laissée désactivée, rétention de 30 jours dans le PoC ;
  - Loki joignable seulement depuis les trois VM (pare-feu) ; Grafana en lecture seule, sans accès anonyme, comptes en 0600 dans `…/08/secrets` ;
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
