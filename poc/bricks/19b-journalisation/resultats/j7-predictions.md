# J7 : prédictions des étapes 4a et 6, écrites à sec (2026-11-20T22:14:17Z UTC)

**Rien n'est posé, rien n'est lancé.** Ces prédictions sont l'étape 3 de la [carte](j7-carte.md). Elles sont écrites avant toute pose.

Accords nécessaires :
- **Étapes 2 et 4a** : un accord nommé chacune.
- **Étape 6** (pods d'essai) : lancement prévu, une fois l'export posé.
- **Lecture du fichier** sur sc-build : elle passe par `sudo` sur la VM ou par un `kubectl exec` dans l'agent, donc par un accord nommé.

Seuls des comptes seront archivés, jamais de flux bruts.

## Bases, lues dans le dépôt ou dans le code au tag

**Format des lignes, lu dans le code de Cilium v1.20.4.**
- L'exportateur écrit chaque événement avec `encoding/json` (`pkg/hubble/exporter/encoder.go`, sha256 `badd7a71d3d66932…`).
- `ExportEvent` encode en protojson avec `UseProtoNames: true` (`api/v1/observer/observer.pb.json.go`, `7d409e9dafbd90c9…`). Ses champs sont `flow`, `node_status`, `lost_events`, `agent_event`, `debug_event`, `node_name` et `time` (`observer.proto`, `99a0c75e7f333d4c…`).
- Avec un masque, seuls les champs du masque sont copiés dans un `Flow` vide (`exporter.go`, `02413bce95988363…`, `FieldMask.Copy`). protojson omet les valeurs nulles.
- Le fichier est géré par lumberjack (`writer.go`, `cb5d2d4686b72575…`). Son comportement à vide n'a pas été lu.
- `Verdict` (`flow.proto`) : VERDICT_UNKNOWN, FORWARDED, DROPPED, ERROR, AUDIT, REDIRECTED, TRACED, TRANSLATED.

**Deux flux par SYN refusé.** Mesuré dans la 08 ([`kata-reseau-cilium-apres-redemarrage.log`](../../08-trust-plane/resultats/kata-reseau-cilium-apres-redemarrage.log)) :
- pod Kata sur sc-build, 6 flux `POLICY_DENIED EGRESS` pour 3 connexions, deux par horodatage ;
- chaque connexion était un `nc -z -w 1` suivi d'un `sleep 1` (`kata.sh`, ligne 505), donc un seul SYN par connexion ;
- **les retransmissions n'y ont pas été mesurées.**

**Témoins des tâches.**
- `construire-rpm` ([`construire-rpm.yaml`](../../05-rpm-mock/construction/construire-rpm.yaml), lignes 76 à 82) :
  - `timeout 10 getent hosts dl.rockylinux.org` ;
  - puis TCP, chacun avec `timeout 10`, vers 192.168.161.13/5000, 192.168.161.13/3000 et 199.232.170.132/80.
- `construire-racine-rpm` ([`construire-racine-rpm.yaml`](../../05-rpm-mock/builders/construire-racine-rpm.yaml), lignes 150 à 154) : le même DNS, puis TCP vers 192.168.161.13/5000 et /3000.

**Bras a et b de R7 (M5a et cascade M1b)**, deux pods Kata :
- **bras b**, au label `construire-rpm` : connexion refusée, code 124 (délai écoulé), donc SYN jeté sans réponse ([prédictions de M1b](../../05-rpm-mock/resultats/m1b-predictions.md)) ;
- **bras a**, sans label de tâche : seul `builds-sans-internet` le sélectionne, il joint Zot.

**Placement.** La politique Kyverno `zone-build` (Deny, relue dans le cluster) exige `nodeSelector zone=build` pour tout pod de `builds`. Les 84 pods de `builds` présents au relevé tournent tous sur sc-build. Les Jobs du scan sont dans l'espace `scan`, hors du filtre.

**DNS.** Le serveur du cluster est 10.43.0.10 (`08b-rke2/config/valeurs-coredns.yaml`).

## Étape 4a : export vers le fichier du nœud, sans Alloy

| # | Prédiction | Confiance |
|---|---|---|
| E1 | Après la pose, DaemonSet `cilium` prêt (3/3). La forme est à choisir : fichier combiné 08c + export, ou export sous `hubble:` de la 08. `cilium-config` a alors 164 clés : les 163 d'aujourd'hui, inchangées, plus `hubble-flowlogs-config-path`. `enable-host-firewall=true` reste posé | Haute : rendu de l'étape 1 |
| E2 | ConfigMap `cilium-flowlog-config` présente, avec un seul exportateur, `builds` | Haute : rendu |
| E3 | Hors construction, `/var/run/cilium/hubble/builds.log` est absent sur sc-build, ou ne grossit pas | Moyenne : création à vide non lue |
| E4 | Une ligne JSON par événement. Pour un flux : clés de tête `flow`, `node_name` et `time`, avec le verdict sous `flow.verdict`, en nom (`DROPPED`), comme le suppose `hubble.alloy`. Des lignes `lost_events`, sans `flow`, sont possibles : elles sont comptées à part | Haute : code au tag |
| E5 | Les champs hors du masque sont absents des lignes de flux (par exemple `uuid`, `ethernet`, `Summary`) | Haute : code au tag |
| E6 | Sur sc-confiance et sc-stockage, fichier absent ou vide | Haute : `zone-build`, 84 pods sur sc-build |

**Mesure du volume (4a).** Elle compte aussi les fichiers déjà tournés (rotation 10 Mo × 5) : au-delà de 60 Mo, le début est perdu. Elle donne des lignes et des octets par construction, et par jour au rythme actuel.

**Critère de 4b** : ces chiffres sont remis au propriétaire, avec le coût estimé sur le disque de Loki (sc-stockage). L'envoi vers Loki se décide sur son second accord.

## Étape 6 : deux pods Kata d'essai, mêmes témoins

| # | Prédiction | Confiance |
|---|---|---|
| T0 | **Témoin positif.** Un pod Kata sans label de tâche, comme le bras a de R7, se connecte à 192.168.161.13:5000 (code 0). Au moins un flux sortant autorisé (FORWARDED) est exporté. Sans ce témoin, T5 ne prouverait rien | Haute : bras a de R7 |
| T1 | Pod au label `construire-rpm` : les quatre témoins échouent. Pour les trois TCP : code 124, comme le bras b de R7 | Haute |
| T2 | Pour chaque témoin TCP : flux refusés = 2 × SYN envoyés en 10 s. Pari : 4 SYN (0, 1, 3 et 7 s, valeurs par défaut de Linux, non lues pour le noyau de l'invité Kata), soit **8 flux par témoin et 24 en tout**. Plage admise : 2 à 8 par témoin. Les deux flux d'un même SYN sont comptés aussi par `event_type` | Moyenne |
| T3 | Chaque flux TCP refusé porte `verdict` DROPPED, `drop_reason_desc` POLICY_DENIED et `traffic_direction` EGRESS, avec l'adresse et le port du témoin | Haute : mesure de la 08 |
| T4 | Témoin DNS : au moins 2 flux refusés vers le port 53 en UDP. Pas de pari sur leur nombre (domaines de recherche, `ndots`, tentatives de la libc). Pas de pari non plus sur la destination vue : service 10.43.0.10 ou pod CoreDNS | Moyenne |
| T5 | **Aucun flux sortant de ce pod avec un verdict autre que DROPPED.** Tous les verdicts sont comptés. Un FORWARDED, AUDIT ou REDIRECTED serait un constat à remonter. Un TRACED ou TRANSLATED est relevé à part, avec ce qui le suit | Haute : NetworkPolicy sans règle, NC1 tenue |
| T6 | Aucun flux entrant vers ce pod, ni autorisé ni refusé : il n'a ni sonde ni service | Moyenne : trafic de l'hôte vers le pod non lu (`allow-localhost`) |
| T7 | Volume du fichier pour les deux pods : moins de 150 lignes et moins de 300 Ko | Moyenne |
| T8 | Aucun objet nouveau dans Zot : le catalogue est relu en anonyme avant et après | Haute : le pod au label n'a ni identifiant ni sortie, et le pod témoin ne fait qu'ouvrir une connexion |

## Ce qui n'est pas prédit

- **Le volume d'une construction complète**, prefetch compris. Les pods de prefetch ont des sorties permises : leurs flux FORWARDED sont attendus et ne contredisent pas T5. Ce volume sera mesuré en 4a.
- **Le comportement des politiques pendant le redémarrage des agents** à la pose.
- **La réaction de l'agent à un chemin de `fieldMask` refusé.**

## Étape 2 recadrée : script et prédiction T9 (note de 2026-11-20T22:20:24Z ; rien n'est réécrit au-dessus)

**Script** : [`j7.sh`](../j7.sh) (sha256 `5baffc6f89cbfffc…`).
- **Étape `sec`, passée** ([journal](j7-sec.log)) : les deux pods sont admis à blanc par dry-run serveur, admission comprise. Ce sont deux pods Kata en zone `build`, avec l'image d'outillage de M1b et le contexte du pas `construire` signé ; le pod b porte le label `construire-rpm`. Rien n'est créé.
- **Étape `mesure`, en attente de l'accord nommé** du `kubectl exec` dans l'agent Cilium de sc-build. Elle crée le pod a puis le pod b et lance leurs témoins. Elle lit ensuite `hubble observe` deux fois par pod, avec `--ip` (comme la 08) puis avec `--pod builds/<pod>` (le filtre de l'export), en comptes seulement. Les pods sont ensuite supprimés, et le catalogue de Zot est relu en anonyme.
- T0 à T6 et T8 s'y vérifient. E1 à E6 et T7 restent pour l'étape 4a.

| # | Prédiction | Confiance |
|---|---|---|
| T9 | Pour chaque pod, `--pod builds/<pod>` rend autant de flux que `--ip`, et chaque flux sortant porte `source.namespace=builds` et `source.pod_name` = le pod. L'endpoint est créé par le plugin CNI de Cilium avec les labels du pod, comme sous runc. **Si `--pod` ne rend rien alors que `--ip` rend des flux, le filtre `source_pod: builds/` de l'export ne verrait rien, et la conception change avant toute pose** | Moyenne : jamais mesuré sous Kata |

## Corrections de j7.sh avant la mesure (note de 2026-11-20T22:24:23Z ; rien n'est réécrit au-dessus)

`j7.sh` passe de `5baffc6f89cbfffc…` à **`6cae4217abe98b9e…`**, après relecture du conseiller. Les manifestes des pods ne changent pas : l'étape `sec` reste valable.

- **Plus d'échec silencieux** :
  - chaque `hubble observe` relève son code et ses lignes d'erreur, et l'étape s'arrête sur un code non nul. Un « 0 flux » ne peut plus venir d'un exec en échec ;
  - **T0 est imposé** : sans flux sortant FORWARDED du pod a, l'étape s'arrête avant le pod b ;
  - le catalogue de Zot doit être lisible et non vide. Essai en lecture anonyme : 166 dépôts.
- **Comptes plus riches**, car rien de brut n'est gardé :
  - verdict × sens × `is_reply` × « la source est le pod » ;
  - protocole × destination ;
  - horodatages distincts par destination, pour juger T2 ;
  - lignes sans `flow`, comme `lost_events`.
  La fonction a tourné sur un banc local (fichier vide ; `lost_events`, DROPPED et FORWARDED). Défaut trouvé et corrigé : `is_reply` à `false` s'affichait « - » (opérateur `//` de jq).
- **Flux bruts** : les fichiers de `hubble observe` restent dans le dossier de travail hors du dépôt, le temps des comptes. Ils sont effacés en fin d'étape, comme sur arrêt (`trap`), avec les pods du jalon.
- **Fenêtre** : elle commence à la création du pod (horloge de l'API). L'écart entre l'horloge de l'agent de sc-build et celle de l'hôte est relevé.
- **Pas de troncature à 20 flux**, lu dans le code du CLI au tag (`hubble/cmd/observe/flows.go`, sha256 `e84789fd9348296e…`). La limite par défaut ne s'applique que sans `--since`, `--until` ni `--first`. Le CLI embarqué dans l'agent n'a pas été comparé à ce code.

## Résultat de la mesure de l'étape 2 (note de 2026-11-20T22:34:12Z ; rien n'est réécrit au-dessus)

Accord du propriétaire : « Oui », à la demande nommant les deux pods Kata privilégiés, le `kubectl exec` dans l'agent Cilium de sc-build (`hubble observe`, `date`), des comptes seulement, et rien de posé. `j7.sh` (`6cae4217…`), étape `mesure` : de 22:32:09 à 22:33:12 UTC, code 0 ([journal](j7-mesure.log)). Les valeurs de Cilium ne sont pas touchées. Les pods sont supprimés et les flux bruts effacés. L'horloge de l'agent de sc-build est à 0 s de celle de l'hôte.

| # | Résultat |
|---|---|
| T0 | **Tenue.** Pod a : TCP vers Zot, code 0 ; 5 flux sortants FORWARDED vers 192.168.161.13:5000, plus 2 réponses (`is_reply` vrai) vers le pod |
| T1 | **Tenue.** Pod b : les quatre témoins échouent en code 124, le DNS compris |
| T2 | **Non tenue.** 14 flux refusés par témoin TCP, 42 en tout, contre un pari de 8 et une plage de 2 à 8. Les 14 horodatages sont tous distincts. Sur les 46 flux du pod b : 23 de type 1 (perte) et 23 de type 5 (verdict de politique). Lecture déduite, non mesurée (drapeaux TCP non comptés) : deux événements par paquet refusé, donc environ 7 SYN par témoin en 10 s. Les « deux flux par horodatage » de la 08 étaient lus à la milliseconde |
| T3 | **En partie.** Tous les flux sont DROPPED et EGRESS, vers les destinations des témoins. Mais deux motifs : POLICY_DENIED (32) et **POLICY_DENY (14), non prédit**. Le compte de 14 est celui d'un seul témoin TCP. Son attribution à 199.232.170.132:80 est déduite, pas mesurée : le croisement motif × destination n'a pas été compté. Ce serait un refus explicite d'une politique Cilium (`builds-sans-internet` refuse les adresses publiques) |
| T4 | **Tenue.** 4 flux UDP refusés vers le port 53. La destination vue est le pod CoreDNS (10.42.2.203, `kube-system/rke2-coredns-…`), pas le service : la traduction précède la politique |
| T5 | **Tenue.** Aucun flux sortant du pod b avec un verdict autre que DROPPED |
| T6 | **Tenue sur la fenêtre.** Aucun flux entrant vers le pod b : les 46 flux sont EGRESS, source le pod |
| T8 | **Tenue.** Catalogue de Zot : 166 dépôts avant et après |
| T9 | **Tenue, point décisif.** Pour chaque pod, `--pod builds/<pod>` rend exactement les flux de `--ip` (7 = 7, 46 = 46). Chaque flux sortant porte `source.namespace=builds` et le nom du pod. **Le filtre `source_pod: builds/` de l'export verrait donc les pods Kata.** La conception tient |

**Conséquences pour la suite** :
- **Requêtes et panneau** : les réponses aux pods de `builds` (`is_reply` vrai, destination le pod) apparaissent en FORWARDED avec le sens EGRESS. « Aucun autorisé » doit se lire sur les flux dont la source est un pod de construction, réponses exclues, et sur tous les verdicts autres que DROPPED.
- **Volume** : le pod b donne 46 flux pour ses quatre témoins. C'est l'ordre de grandeur d'une construction rpm sans autre trafic ; il est à mesurer en 4a.
- **Comptes de 4a** : il faudra croiser le motif avec la destination, pour mesurer l'attribution de POLICY_DENY.

## Lectures après la mesure (note de 2026-11-20T22:35:57Z ; rien n'est réécrit au-dessus)

**T3 : l'attribution de POLICY_DENY est lue, plus seulement déduite** (elle n'est toujours pas mesurée).
- `builds-sans-internet` (`08c-durcissement/politiques/cilium-sortie/`) porte un `egressDeny` vers `0.0.0.0/0`, sauf les plages privées (10/8, 172.16/12, 192.168/16, 169.254/16, 127/8).
- Son sélecteur exclut seulement les quatre tâches de prefetch : elle s'applique donc à `construire-rpm`.
- Sa spec dans le cluster est égale à celle du dépôt (sha256 du JSON trié : `1c6d23c21f6241dd…` des deux côtés).
- `POLICY_DENY` vaut 181 dans `DropReason` (`flow.proto` au tag), distinct de `POLICY_DENIED` (133).
- Des quatre destinations du pod b, seule 199.232.170.132 est publique. Ses 14 flux sont donc les POLICY_DENY, et 32 = 14 + 14 + 4 pour les autres : refus implicites de la NetworkPolicy sans règle.
- Conséquence : l'adresse publique est refusée par deux politiques à la fois, et le refus explicite l'emporte dans le motif.

**T2 : piste, pas un verdict.** Sept paquets en 10 s ne collent pas aux reprises de 0, 1, 3 et 7 s. Ajouté aux comptes de 4a :
- relever `net.ipv4.tcp_syn_linear_timeouts` dans l'invité Kata ;
- compter les drapeaux SYN ;
- croiser le motif avec la destination.

**T9 : réserve.** La mesure a filtré sur le nom complet (`--pod builds/<pod>`). L'export filtrera sur le préfixe `builds/`. Le sens du préfixe est lu dans `flow.proto`, pas mesuré : c'est un point de 4a.

## Étape 4a préparée : pose, export, retour (note de 2026-11-20T22:42:28Z ; rien n'est réécrit au-dessus)

`j7.sh` passe à **`5f753a08acd74e9f…`**. Ajouts : `pose_sec`, `pose`, `export` et `retour`. La forme retenue est (a), le fichier combiné (valeurs de la 08c, puis export) passé en `VALEURS_08C`. Il disparaît au rejeu de zéro.

- **`pose_sec`, passée** ([journal](j7-pose_sec.log)) : rien n'est posé.
  - Le rendu du fichier combiné est égal, hors Secrets, au rendu de l'étape 1 fait avec des fichiers séparés.
  - Il ajoute la seule ConfigMap `cilium-flowlog-config`.
  - Le rendu actuel est égal au `cilium-config` du cluster (clés et valeurs).
  - Clés de `cilium-config` : 163 aujourd'hui, 164 après la pose.
- **Commandes** :
  - pose : `VALEURS_08C=<fichier combiné> cilium.sh appliquer` ;
  - retour : `VALEURS_08C=08c-durcissement/config/valeurs-cilium.yaml cilium.sh appliquer`, la commande de `etape_h5_cilium`.
- **Précautions reprises de la 08c** : le rattrapage est suspendu, et la pose est refusée si un PipelineRun est actif. Les certificats de Cilium et de Hubble (versions d'objet), le nombre de redémarrages et le pare-feu d'hôte sont contrôlés après coup.
- **Fenêtre gardée par le script** : jamais de 08:00 à 11:30 UTC. Le 21/11, jamais de 21:30 à 22:45 UTC (balayage n°2) ; le 22/11, jamais de 22:15 à 23:30 UTC (n°3). Au-delà du 22/11, la pose est refusée tant que les balayages ne sont pas recalculés.
- **Journal de la 08** : `cilium.sh appliquer` réécrit `08-trust-plane/resultats/cilium-appliquer.log`, comme chaque passage de la 08c (h4, h5_cilium, h6, h6_retrait). L'historique reste dans git.
- **Fichier d'export** : il est sous `/var/run` du nœud, sans doute un tmpfs, donc en mémoire (60 Mo au plus avec la rotation). Ce n'est pas lu sur la VM.

| # | Prédiction | Confiance |
|---|---|---|
| P1 | `pose` : agents prêts (3/3), état OK et Hubble Ok sur les trois. API prête, Zot joignable depuis l'hôte. Certificats de Cilium et de Hubble inchangés, nombre de redémarrages inchangé, pare-feu d'hôte toujours posé | Haute : même chemin que h5_cilium et h6 |
| P2 | E1 et E2 (164 clés, un exportateur `builds`), E3 et E6 comme écrites plus haut | Haute |
| X1 | `export`, réserve de T9 : le fichier de sc-build contient, pour chaque pod, autant de flux que `hubble observe --ip`. Le préfixe `builds/` filtre comme le nom complet | Moyenne : préfixe lu, pas mesuré |
| X2 | Motif × destination, pod b : POLICY_DENY = 14 sur 199.232.170.132:80 ; POLICY_DENIED sur les trois autres destinations | Haute : politique lue |
| X3 | Drapeaux SYN : 7 par témoin TCP, d'après les 14 flux de la mesure. `tcp_syn_linear_timeouts` est relevé dans l'invité, sans pari | Moyenne |
| X4 | E4 et E5 dans le fichier : clés de tête `flow`, `node_name` et `time`, verdict en nom, aucun champ hors du masque, aucune ligne hors de `builds` | Haute : code au tag |
| X5 | T7 : moins de 150 lignes et moins de 300 Ko pour les deux pods. Aucun fichier tourné | Moyenne |
| P3 | `retour` : 163 clés, `cilium-flowlog-config` absente, mêmes contrôles que P1. Le fichier reste sur sc-build jusqu'au redémarrage de la VM | Haute |

## Corrections de 4a avant la demande de pose (note de 2026-11-20T22:45:04Z ; rien n'est réécrit au-dessus)

`j7.sh` passe de `5f753a08acd74e9f…` à **`edbc4fdbf9b1dfdb…`**, après relecture du conseiller. Rien n'est posé.

1. **`DISTRO`, le plus grave.** `distro.sh` (08) met `DISTRO=k3s` par défaut, et `cilium.sh` n'ajoute le fichier de la 08b que hors k3s. Une pose lancée sans `DISTRO=rke2` aurait donc retiré `kubeProxyReplacement`, par `--reset-values`. `pose` et `retour` exigent désormais `DISTRO=rke2`.
   - Relance à sec avec `DISTRO=rke2` ([`j7v2-pose_sec.log`](j7v2-pose_sec.log)) : tout est tenu.
   - Témoin sans `DISTRO` ([`j7v3-pose_sec.log`](j7v3-pose_sec.log)) : `DISTRO=k3s`, refusé.
   - Le premier journal `j7-pose_sec.log` n'est pas réécrit. Son rendu fixait la liste des fichiers en dur et ne passait pas par ce chemin.
2. **Redémarrages** : le compte se fait désormais hors pods de Cilium, que `cilium.sh appliquer` recrée avec des compteurs remis à zéro. S'y ajoute un contrôle à part : zéro redémarrage pour les pods de Cilium recréés. Au relevé : 17 hors Cilium, 0 pour Cilium.
3. **Retour toujours possible** : `FORCER_RETOUR=1` passe outre la garde de fenêtre, et c'est écrit dans le journal. Si `pose` finit en KO après `cilium.sh`, l'export peut rester posé. Le script affiche alors la commande de retour : `DISTRO=rke2 [FORCER_RETOUR=1] j7.sh retour`.
4. **`lire_export`** :
   - l'étape s'arrête si l'exec échoue ;
   - les lignes non JSON (une dernière ligne coupée) sont comptées, sans arrêter l'étape.
   Sur un banc local avec une ligne coupée : 1 ligne non JSON, et les 4 valides gardées.

Commande de chaque étape, depuis la racine : `DISTRO=rke2 mise exec -- poc/bricks/19b-journalisation/j7.sh <pose|export|retour>`.

## Résultats de 4a : pose et export (note de 2026-11-20T22:49:25Z ; rien n'est réécrit au-dessus)

Accord du propriétaire : « Oui il faut mettre rke2 ». La demande nommait la pose des valeurs Helm de Cilium (redémarrage des agents des trois nœuds, réécriture de `cilium-appliquer.log` de la 08), les deux pods Kata privilégiés, et les `kubectl exec` dans les agents des trois nœuds. Les deux étapes ont tourné avec `DISTRO=rke2` et `j7.sh` `edbc4fdbf9b1dfdb…`, chacune en code 0.

**`pose`**, de 22:45:30 à 22:46:23 UTC ([journal](j7-pose.log), et [`cilium-appliquer.log`](../../08-trust-plane/resultats/cilium-appliquer.log) de la 08, révision 3 de la release).
- **P1 tenue** :
  - trois agents recréés (de 22:45:57 à 22:46:10), avec l'état OK et Hubble Ok ;
  - API prête, Zot joignable (HTTP 200) ;
  - certificats de Cilium et de Hubble inchangés (versions d'objet 426 et 427) ;
  - 17 redémarrages hors Cilium, avant comme après, et 0 pour les pods de Cilium recréés ;
  - pare-feu d'hôte posé.
- **E1 et E2 tenues** : 164 clés, et un seul exportateur, `builds`. Relu juste après : les 163 autres clés sont égales à celles d'avant la pose (sha256 du JSON trié `2cf9627a73576d91…` des deux côtés), et `kube-proxy-replacement=true`.
- **E3 tenue** : fichier absent sur sc-build tant qu'aucun flux de `builds` n'a passé.

**`export`**, de 22:47:07 à 22:48:11 UTC ([journal](j7-export.log)). Pods supprimés, copies effacées.

| # | Résultat |
|---|---|
| X1 (réserve de T9) | **Tenue.** Le fichier de sc-build, filtré par le préfixe `builds/`, contient autant de flux que `hubble observe --ip` : 7 = 7 pour le pod a, 46 = 46 pour le pod b |
| X2 | **Tenue, et cette fois mesurée.** POLICY_DENY = 14 sur 199.232.170.132:80 ; POLICY_DENIED sur le DNS (4) et sur Zot et Forgejo (14 et 14) |
| X3 | **Tenue.** 42 flux SYN pour le pod b, 14 par témoin TCP, soit 7 paquets SYN par témoin à deux événements chacun. L'invité Kata (noyau 6.18.56) a `tcp_syn_retries=6` et **`tcp_syn_linear_timeouts=4`** : quatre reprises à intervalle fixe avant le doublement. Cela explique T2 |
| X4 (E4, E5) | **Tenue.** 53 lignes, toutes avec `flow`, `node_name` et `time`. Le verdict est écrit en nom. Aucun champ hors du masque. Aucune ligne hors de `builds`. Aucune ligne non JSON |
| X5 (T7) | **Tenue.** 53 lignes et 67 604 octets pour les deux pods (environ 1,3 Ko par ligne). Aucun fichier tourné |
| E6 | **Non tenue pour sc-stockage.** Le fichier de sc-stockage existe, avec une ligne (1 201 octets) : un verdict de politique FORWARDED **en entrée**, de `builds/j7-a` vers Zot (192.168.161.13:5000). Le pare-feu d'hôte du nœud de destination voit les connexions autorisées des pods de `builds`. Les connexions refusées, elles, sont jetées à la source. Ce comptage a été lu après l'étape, dans l'agent de sc-stockage, puis la copie a été effacée. sc-confiance : absent |

**Constats pour la suite** :
- **Alloy sur sc-build seul** voit tout ce qui est refusé, et les sorties autorisées vues à la source. Les nœuds de destination ajoutent les entrées autorisées vers leurs services (Zot et Forgejo sur sc-stockage). Ce sont des doublons utiles, à décider en 4b.
- **Volume** : environ 1,3 Ko par flux. Une construction rpm sans autre trafic en donnerait environ 46 pour ses témoins. Une vraie construction, prefetch compris, n'est pas mesurée.
- **Journal** : la ligne « command terminated with exit code 1 » vient du `grep -c` sans correspondance du compte des fichiers tournés. Elle est sans effet (0 fichier tourné).

**État laissé : l'export est posé** sur les trois agents. Il borne le fichier à 60 Mo par nœud, sous `/var/run` (sans doute un tmpfs, non lu). Le retour est un accord à part : `DISTRO=rke2 mise exec -- poc/bricks/19b-journalisation/j7.sh retour`.

## Relevés après la pose (note de 2026-11-20T22:52:08Z ; rien n'est réécrit au-dessus)

- **Rattrapage** : `pose` a suspendu le CronJob `rattrapage`, puis l'a remis à `suspend: false` sans avoir relevé sa valeur de départ. Celle-ci est établie après coup. Dans Loki, par Grafana (auditeur, comptes seulement), 15 pods `rattrapage` ont tourné entre 22:30 et 22:45 UTC, un par minute : le CronJob était actif avant la pose, et la reprise a rétabli son état. Au relevé : `suspend=false`, dernier passage à 22:50:00 UTC. **Avant `retour`, `j7.sh` doit relever cette valeur et la restaurer.**
- **`rattrapage-deb`** : 15 pods de ce second CronJob ont tourné sur la même plage. Il n'est pas suspendu par la pose, pas plus que par `etape_h5_cilium` de la 08c. Le contrôle « aucun PipelineRun actif » couvre le moment de la pose, pas la durée du redémarrage.
- **`/var/run` de sc-build** : c'est un tmpfs de 995 Mo (`findmnt` par ssh, sans sudo), sur une VM de 9 950 Mo de mémoire. Le fichier d'export, borné à 60 Mo par la rotation, est en mémoire.
- **Volume d'une vraie construction** : l'export est posé, donc tout PipelineRun à venir remplira le fichier. Derniers PipelineRuns de `builds` : le 20/11 à 13:41:07 UTC. La mesure passive consiste à relire la taille du fichier après le prochain passage, sans rien écrire dans Zot. Cette relecture est un `kubectl exec`, à nommer dans la demande.
- **`DISTRO`** : le défaut de `distro.sh` reste `k3s`. Le changer serait une modification de configuration pour tous les scripts de la 08, et n'est pas fait.

## Correctif de la reprise du rattrapage (note de 2026-11-21T16:15:03Z ; rien n'est réécrit au-dessus)

La note « Relevés après la pose » demandait que `j7.sh` relève l'état du CronJob `rattrapage` avant `retour`, puis le restaure. C'est fait, à sec : `j7.sh` passe de `edbc4fdbf9b1dfdb…` à **`ec581e035ff148a6…`**. Rien n'est lancé dans le cluster.

- **`suspendre_rattrapage`** lit d'abord `.spec.suspend`, un champ absent valant `false`. Une autre valeur arrête l'étape avant toute écriture. L'état de départ est écrit dans le journal, puis le trap de sortie est posé, et enfin la suspension.
- **`reprendre_rattrapage`** remet cette valeur, au lieu de `false` en dur, et la relit pour le journal.
- **Banc local** ([script](j7-rattrapage-banc.sh), [journal](j7-rattrapage-banc.log)) : les deux fonctions sont extraites de `j7.sh` telles quelles, avec un faux `kubectl`. **6 cas sur 6 tenus** :
  - départ `false`, `true` ou champ absent : état final égal au départ ;
  - arrêt sur un PipelineRun actif, au départ `false` puis `true` : le trap remet l'état de départ ;
  - valeur illisible : arrêt sans aucune écriture.
- **État relevé à 16:13 UTC** (`kubectl get`, lecture seule) : `rattrapage` et `rattrapage-deb` sont à `suspend=false`, avec un dernier passage à 16:13:00 UTC.

**Reste avant `retour`**, qui attend toujours un accord à part :
- `garde_fenetre` ne connaît que les 20, 21 et 22/11. Au-delà, elle refuse tant que les balayages de Zot ne sont pas recalculés, sauf avec `FORCER_RETOUR=1`.
- `rattrapage-deb` n'est toujours pas suspendu, comme dans `etape_h5_cilium` de la 08c.

## Complément au correctif du rattrapage (note de 2026-11-21T16:17:19Z ; rien n'est réécrit au-dessus)

Relecture du conseiller. Le correctif reprend l'état trouvé au départ, quel qu'il soit. Si un passage interrompu sans trap laissait `suspend=true`, le passage suivant prendrait cette valeur pour l'état de départ et la garderait. La ligne « rattrapage : suspend=… avant la suspension » du journal le montrerait. **Avant `retour`, relire que `rattrapage` est à `suspend=false`** (c'était le cas le 21/11 à 16:13 UTC).
