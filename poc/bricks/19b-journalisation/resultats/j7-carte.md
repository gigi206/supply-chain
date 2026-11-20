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
