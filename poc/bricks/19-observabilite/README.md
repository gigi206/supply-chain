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
