# J7 : flux réseau des pods de construction dans Grafana, carte préparée à sec (20/11/2026)

**Rien n'est posé.** Ni les valeurs de Cilium, ni Alloy, ni le cluster ne sont touchés. Cette carte prépare une décision et une pose, chacune avec l'accord du propriétaire.

## Demande

Verbatim du propriétaire, le 20/11/2026 : « avoir également les logs réseau du container pour voir ceux bloqués (normalement tous) et ceux autorisés (normalement aucun) ». Contexte : la voie rpm n'a qu'une barrière réseau pendant `%build`, la NetworkPolicy du pod ([dossier 5 de la 05](../../05-rpm-mock/resultats/dossiers-decision.md)). Aucun contrôle continu de cette barrière n'a été trouvé.

C'est le J7 du [README](../README.md) de la 19b (« Flux réseau refusés (Hubble de Cilium) », optionnel, après une mesure de volume), jamais fait.

## Ce qui existe, lu dans le dépôt

- **Cilium 1.20.4** (`08-trust-plane/cilium.sh`, `CILIUM_VER=1.20.4`). Hubble est actif dans l'agent, sans relais ni interface (`cilium/valeurs.yaml`). `cilium.sh appliquer` pose les valeurs modifiées, puis redémarre agents et opérateur, ce que le chart ne fait pas.
- **Export de flux du chart**, au tag `v1.20.4` (`install/kubernetes/cilium/values.yaml`, sha256 `6ef6bcb8…`, lu par l'API publique de GitHub) :
  - statique (`hubble.export.static`) : un fichier, des listes `allowList` et `denyList`, un `fieldMask`. Il est lié au cycle de vie de l'agent : tout changement de filtre passe par un redémarrage ;
  - dynamique (`hubble.export.dynamic`) : une ConfigMap `cilium-flowlog-config`, des `includeFilters` et `excludeFilters`, sans redémarrage pour changer de filtre ;
  - rotation : `fileMaxSizeMb` (10 par défaut), `fileMaxBackups` (5) ; fichier par défaut `/var/run/cilium/hubble/events.log`, sur le nœud.
- **Filtres** (`api/v1/flow/flow.proto` au tag, sha256 `c3256c05…`) : `source_pod` et `destination_pod` par préfixe (`builds/`), `source_label` et `destination_label` par sélecteur de labels Kubernetes, `verdict`.
- **Alloy 1.21.3** tourne sur les trois VM (`systemd/alloy.service`). Il lit déjà des fichiers (`local.file_match` : `/var/log/pods`, audits de Zot et de l'API) avec la seule capacité `CAP_DAC_READ_SEARCH`, sans restriction sur `/run`. La lecture du fichier d'export en découle ; c'est déduit, pas mesuré.
- Les pods de construction tournent sur **sc-build** seul (taint `zone=build:NoSchedule`).

## Proposition

1. **Export dynamique**, filtré sur les pods du namespace `builds`, en source et en destination. Le filtre peut changer sans redémarrer les agents ; seule son activation en demande un.
2. **Champs gardés**, pour borner le volume : heure, verdict, raison du refus, pod et labels source, adresse et port de destination, protocole, sens.
3. **Alloy sur sc-build** lit le fichier et l'envoie à Loki sous `source="hubble"`.
4. **Grafana** :
   - par construction : flux refusés et autorisés, par pod ;
   - alerte si un pod de construction a un flux sortant autorisé ;
   - alerte si une construction n'a **aucun** refus. Les témoins de `construire-rpm` et de `construire-racine-rpm` doivent en produire à chaque fois (DNS, Zot, Forgejo, et une adresse publique pour `construire-rpm`). Zéro refus voudrait dire un export en panne.

## Limites, à écrire dans les prédictions

- **Par pod, pas par conteneur.** Hubble ne distingue ni les pas d'un pod Tekton, ni les processus de la VM Kata.
- **« Aucun autorisé » vaut pour les pods de construction seulement.** Les pods de prefetch ont des sorties permises. Le trafic du nœud vers ses propres pods est autorisé par défaut dans Cilium (`allow-localhost`, d'après la documentation, non relu au tag) : il peut apparaître comme autorisé.
- **Volume inconnu.** C'est la raison pour laquelle J7 était resté optionnel. Il faut le mesurer avant d'étendre le filtre.
- Un redémarrage des agents à l'activation. Le comportement des politiques pendant ce redémarrage n'a pas été mesuré.

## Étapes

| # | Étape | Touche | Accord |
|---|---|---|---|
| 1 | À sec : valeurs rendues avec l'export, `helm template` hors ligne comparé au rendu actuel ; configuration Alloy écrite et vérifiée par `alloy fmt` | rien | non (préparation) |
| 2 | Lecture seule : `hubble observe` dans l'agent de sc-build, pour vérifier la syntaxe du filtre par label sur les flux récents | rien | lecture |
| 3 | Prédictions datées : nombres de refus attendus par témoin, zéro flux sortant autorisé, volume par construction | rien | non |
| 4 | Pose : `cilium.sh appliquer`, **hors de 08:00 à 11:30 UTC** (import de la base grype, scans de G7) | valeurs de Cilium, redémarrage des agents | **oui** |
| 5 | Pose : configuration Alloy de sc-build | Alloy de sc-build | **oui** |
| 6 | Mesure : un TaskRun d'essai de `construire-rpm` sous Kata, lu dans Grafana | cluster (pod d'essai) | lancement prévu |

## Couplages

- **G7** : J7 ne touche pas Zot. Il reste compatible avec « Après le n°9 ».
- **Rejeu de M5b** : `cilium/valeurs.yaml` est relu par le rejeu. Une valeur posée et mesurée avant le 29/11 évite au rejeu de porter une valeur jamais essayée. C'est le même raisonnement qu'au dossier 4.
- **docs/04** : aucun projet nouveau. Hubble et Alloy sont déjà en service.

## Estimation

0,5 j, décision avec le propriétaire à 1 j.

## Corrections après relecture du conseiller (note de 2026-11-20T21:37:14Z ; rien n'est réécrit au-dessus)

**1. Un couplage manquait : Loki, sur sc-stockage.** Écrire « J7 ne touche pas Zot » ne suffit pas. Les flux iraient dans Loki, sur sc-stockage :
- c'est le disque dont le remplissage n'est pas expliqué (deux rythmes non rapprochés, `df` du 21/11) ;
- c'est là que la tâche du 29/11 lit les balayages n°2 à n°9 ;
- D9 de la 19b disait « J7 en option, après une mesure de volume ». La carte posait tout, puis mesurait.

**Ordre corrigé des poses** :
- **4a.** Export vers le fichier du nœud seulement, borné par la rotation (`fileMaxSizeMb` × `fileMaxBackups`, soit 60 Mo au plus avec les valeurs par défaut), puis mesure du volume sur ce fichier. Accord.
- **4b.** Branche Alloy vers Loki, sur un **second accord**, au vu du volume mesuré. Elle remplace l'étape 5.

**2. L'étape 6 prend la forme du bras b de R7 de M5a** : un pod d'essai Kata qui porte le label `tekton.dev/task=construire-rpm` et lance les mêmes témoins. Il exerce la même politique, sans tâche signée, sans Chains et sans PVC. Prédiction à écrire : aucun objet nouveau dans Zot, puisque `g7-etat.sh` compte les `.att`.

**3. Points vérifiés depuis** :
- **Refus d'un pod Kata dans Hubble : mesuré.** `kata-reseau-cilium-apres-redemarrage.log` de la 08, ligne 130 : « kata (10.42.1.233) : 3 connexions refusées, 6 flux refusés vers Zot dans Hubble (motif POLICY_DENIED) ». Le signal « zéro refus = export en panne » repose donc sur une mesure.
- **Filtres** : `flow.proto` au tag dit « If multiple fields are set, then all fields must match ». Il faut donc **deux filtres**, l'un en source (`source_pod: builds/`), l'autre en destination (`destination_pod: builds/`).
- **Estimation**, dans l'unité des jalons de la 19b (heures) : **4 h, décision avec le propriétaire à 8 h**. Elle remplace « 0,5 j, décision à 1 j ». Le seuil de la 19b est atteint depuis le 02/11 (`docs/03`) : J7 en est une extension, et l'effort compte sur la 19b.

**4. Points non lus** :
- que `/var/run/cilium` soit un `hostPath` du DaemonSet de Cilium : le `helm template` de l'étape 1 le dira ;
- « alerte » : la 19 a un Alertmanager, mais son branchement sur Loki n'a pas été relu. D'ici là, lire « requête et panneau » ;
- l'étape 2 (`hubble observe`) passe par un `kubectl exec` dans l'agent Cilium privilégié. Ce n'est pas une des lectures sans accord : elle sera **nommée dans la demande d'accord**, et seuls des comptes seront archivés, jamais de flux bruts.

## Étape 1 à sec : résultat (note de 2026-11-20T21:46:56Z ; rien n'est réécrit au-dessus)

Rien n'est posé. Journal : [`j7-etape1.log`](j7-etape1.log). Fichiers proposés dans [`j7-a-sec/`](j7-a-sec/) : `valeurs-export.yaml` (sha256 `11a3f50e3280e892…`) et `hubble.alloy` (`b4ec54152bb704ee…`).

- **Rendu hors ligne.** `helm template` de l'archive du chart (sha256 égal à `CHART_TGZ`), avec les mêmes fichiers que `cilium.sh appliquer` : `cilium/valeurs.yaml` rendu, `valeurs-cilium.yaml` de la 08b et de la 08c. La reconstruction est exacte : les 163 clés de `cilium-config` sont égales à celles du cluster (`kubectl get`, lecture seule). WireGuard n'est pas posé (clé absente).
- **Ce que l'export change**, Secrets du rendu ni comparés ni affichés :
  - `cilium-config` : une clé, `hubble-flowlogs-config-path: /flowlog-config/flowlogs.yaml` ;
  - DaemonSet `cilium` : un volume (ConfigMap `cilium-flowlog-config`, `optional: true`) et son montage `/flowlog-config` dans `cilium-agent` ;
  - une ConfigMap ajoutée, `cilium-flowlog-config`, avec un exportateur `builds` : deux filtres (`source_pod: builds/`, `destination_pod: builds/`), 18 champs gardés, fichier `/var/run/cilium/hubble/builds.log`, rotation 10 Mo × 5.
  - Le modèle de pod du DaemonSet change : `helm upgrade` seul relancerait donc les agents. C'est déduit, pas mesuré ; `cilium.sh appliquer` les relance de toute façon.
- **Point non lu n°1 levé** : `/var/run/cilium` est un `hostPath` du DaemonSet (volume `cilium-run`). Le fichier d'export est donc sur le disque de sc-build.
- **Alloy** : composition de sc-build (rôles `commun` et `noeud`, plus `journaux-rke2.alloy`), validée par `alloy validate` v1.21.3 (binaire extrait de l'archive vérifiée, non installé) : code 0 sans et avec `hubble.alloy` ; le témoin cassé (récepteur inexistant) est refusé (code 1). `alloy fmt` ne signale que des écarts de forme, comme sur `pods.alloy` et `journaux-rke2.alloy` du dépôt.
- **À la pose 4b** : un rôle `build` pour sc-build seul, dans `ROLES` de `journalisation.sh`.

**Non vérifié, à lire sur le fichier à l'étape 4a** :
- le format des lignes : `hubble.alloy` suppose les clés `time` et `flow.verdict` ;
- les droits du fichier `builds.log` : la lecture par Alloy (`CAP_DAC_READ_SEARCH`) est déduite ;
- la rotation réelle.

**Étape 2** (`hubble observe` dans l'agent de sc-build, `kubectl exec`) : elle attend un accord nommé. Elle n'est pas demandée ce soir.

## Compléments à l'étape 1, après relecture du conseiller (note de 2026-11-20T21:51:28Z ; rien n'est réécrit au-dessus)

**1. Commande de pose (étape 4a) : `cilium.sh appliquer` lancé seul retirerait le pare-feu d'hôte.**
- `etape_installer` passe `--reset-values`. Seuls `cilium/valeurs.yaml` rendu, le fichier de la 08b et **un** fichier `VALEURS_08C` sont appliqués.
- Le pare-feu d'hôte (clés de tête `hostFirewall`, `policyAuditMode` et `tls` du fichier de la 08c) a été posé par `durcissement.sh` avec `VALEURS_08C=$C/valeurs-cilium.yaml`.
- `cilium/valeurs.yaml` de la 08 a déjà une clé `hubble:` ; le fichier de la 08c n'en a pas.
- Deux formes possibles, **à choisir avant de demander l'accord 4a** :
  - (a) un fichier combiné, fichier de la 08c puis export, passé en `VALEURS_08C` (même motif que `valeurs_h6` de la 08c, clés de tête distinctes) ;
  - (b) l'export ajouté sous `hubble:` dans `cilium/valeurs.yaml` de la 08 : le rejeu le relirait.
- Dans les deux cas, un passage ultérieur de `durcissement.sh` avec son seul fichier retirerait l'export sans le dire. C'est à écrire dans la carte de pose.

**2. `fieldMask` : non vérifié.** `helm template` ne valide pas les chemins des champs. La réaction de l'agent à un chemin refusé n'est pas lue (refus de tout l'exportateur, champ ignoré ou erreur au journal). Ajouté aux points à lire en 4a.

**3. Scripts de l'étape 1** versés dans [`j7-a-sec/`](j7-a-sec/) : `j7-etape1.sh` (sha256 `4d6528a5b36e1d45…`) et `j7-compare.py` (`2841cf518b67897a…`), tels qu'ils ont tourné. Leur dossier de travail est le scratchpad de la session (variable `S`). Pour les rejouer, il faut changer `S`, sans rien d'autre.

## Étape 3 : prédictions écrites (note de 2026-11-20T22:14:17Z ; rien n'est réécrit au-dessus)

[`j7-predictions.md`](j7-predictions.md) : E1 à E6 pour l'étape 4a, T0 à T8 pour l'étape 6. Rien n'est posé.

Changements à la carte, après relecture du conseiller :
- **L'étape 6 compte deux pods d'essai Kata.** Le second, sans label de tâche comme le bras a de R7, est un **témoin positif** : il doit produire au moins un flux autorisé exporté. Sans lui, « aucun flux autorisé » ne prouverait pas que l'export fonctionne.
- **« Aucun autorisé » porte sur tous les verdicts** de `flow.proto`, pas seulement sur FORWARDED. Les requêtes et le panneau devront faire de même.
- **Format des lignes lu dans le code au tag** (`ExportEvent` en protojson, noms du proto) : `hubble.alloy` lit les bonnes clés. Ce point n'est plus dans les « non vérifié » de l'étape 1, mais reste à constater sur le fichier.
- **Placement confirmé** : la politique Kyverno `zone-build` (Deny) impose `zone=build` à tout pod de `builds`. « Alloy sur sc-build seul » tient.
- **Accords** : l'étape 6 est un lancement prévu, mais la lecture du fichier sur sc-build (`sudo` ou `kubectl exec`) demande un accord nommé.

## Étape 2 recadrée et forme de pose recommandée (note de 2026-11-20T22:18:38Z ; rien n'est réécrit au-dessus)

**L'étape 2, telle qu'écrite, ne mesurerait presque plus rien.**
- Le filtre n'est plus par label, et le format des lignes est lu dans le code.
- Hors construction, le tampon de Hubble de sc-build n'a sans doute aucun flux de `builds`. Sa taille n'est pas posée dans `cilium-config` ; la valeur commentée du chart est 4095, et le défaut de l'agent n'est pas lu.

**Recadrage.** L'étape 2 lance les deux pods Kata de T0 et T1 ([prédictions](j7-predictions.md)) et lit aussitôt `hubble observe` dans l'agent de sc-build, en comptes seulement.
- T0 à T6 se vérifient ainsi **sans toucher aux valeurs de Cilium**. E1 à E6 et T7 restent pour l'étape 4a.
- **Point décisif, jamais mesuré** : les flux d'un pod Kata portent-ils `source.namespace` et `source.pod_name` ? La mesure de la 08 filtrait par adresse (`hubble_refus` de `08-trust-plane/commun.sh` : `--from-ip`, sortie en adresses). Sans ces champs, le filtre `source_pod: builds/` n'exporterait rien, et la conception change avant toute pose.
- Ordre : préparation à sec (manifestes, dry-run serveur, script de comptes), puis accord nommé du `kubectl exec` dans l'agent, puis pods et lecture immédiate.

**Forme de pose de 4a : recommandation, (a) le fichier combiné**, fichier de la 08c puis export, en `VALEURS_08C`.
- Pour un essai, (a) est réversible et ne touche aucun fichier de la 08.
- Commande de retour, celle de `etape_h5_cilium` de la 08c : `VALEURS_08C=$C/valeurs-cilium.yaml cilium.sh appliquer`.
- Le rejeu de zéro passe par `durcissement.sh h4_bloque` (`rejeu.sh`), qui repose le seul fichier de la 08c : **l'export (a) disparaît au rejeu**.
- (b), l'export sous `hubble:` de `cilium/valeurs.yaml`, est gardé pour le cas où J7 est retenu après 4b. Ce serait un changement de la 08, avec son coût de rejeu (D9).

**Correction de lecture** : « après redémarrage » dans `kata-reseau-cilium-apres-redemarrage.log` de la 08 suit un redémarrage des VM (README de la 08, « Redémarrage des VM sous Cilium », 30/10/2026), pas un redémarrage des agents seuls. Le comportement des politiques pendant le redémarrage des agents reste non mesuré.

## Étape 2 recadrée : mesure faite (note de 2026-11-20T22:34:12Z ; rien n'est réécrit au-dessus)

Résultat dans les [prédictions](j7-predictions.md) ; [journal](j7-mesure.log). **T9 tenue** : les flux des pods Kata portent l'espace de noms et le nom du pod, donc l'export filtré sur `builds/` les verrait. T0, T1, T4, T5, T6 et T8 sont tenues. **T2 n'est pas tenue** : 14 flux par témoin TCP. **T3 l'est en partie** : un motif POLICY_DENY non prédit, sur 14 flux. Rien n'est posé. Prochaine étape : 4a (export vers le fichier, forme (a) recommandée), sur accord.

## Étape 4a préparée (note de 2026-11-20T22:45:04Z ; rien n'est réécrit au-dessus)

Forme (a), le fichier combiné. Les étapes `pose`, `export` et `retour` de [`j7.sh`](../j7.sh) sont prêtes, avec les prédictions P1 à P3 et X1 à X5 ([prédictions](j7-predictions.md)). `pose_sec` est tenue. Rien n'est posé.

Ordre recommandé (conseiller) : `pose` et `export` sur un accord ; `retour` sur un accord à part. Le retour viendrait après la mesure du volume d'une vraie construction, qui est l'objet de 4a. Cette mesure n'est pas préparée : une construction réelle écrirait dans Zot, ce qui est à peser contre G7.

## 4a : export posé et mesuré (note de 2026-11-20T22:49:25Z ; rien n'est réécrit au-dessus)

**L'export est posé depuis 22:46:23 UTC le 20/11** (forme (a)). Le passage s'est fait sans incident : P1, E1 à E3 et X1 à X5 sont tenues. E6 ne l'est pas pour sc-stockage : son pare-feu d'hôte voit les entrées autorisées des pods de `builds`. Détail dans les [prédictions](j7-predictions.md). Le retour attend un accord à part. 4b (envoi vers Loki) n'est pas commencé.
