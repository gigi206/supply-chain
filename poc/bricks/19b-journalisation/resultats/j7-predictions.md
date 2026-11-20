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
