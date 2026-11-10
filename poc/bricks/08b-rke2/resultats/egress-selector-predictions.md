# Brique 08b : `egress-selector-mode: disabled`, prédictions (écrites le 10/11/2026, terminées à 20:41 UTC, avant toute exécution)

Script : [`egress-selector.sh`](../egress-selector.sh). Configuration : [`config/sc-confiance.yaml`](../config/sc-confiance.yaml). **Rien n'est appliqué.**

## Décision et accord

**Décision du propriétaire** : « Mais on ne veux pas du proxy avec cilium », à 20:38:51 UTC (transcription). La réponse suit le diagnostic de la brique 06, qui situe le blocage de `kubectl exec` sur le chemin par le tunnel de l'agent.

Elle est consignée comme une **interprétation** : retirer le proxy du superviseur et le tunnel de l'agent pour le trafic de kube-apiserver vers kubelet, par `egress-selector-mode: disabled` sur le server. **L'application attend un accord nommé.**

## Lectures faites avant ces prédictions

- **Configuration** : `egress-selector-mode` vaut `agent` par défaut. Elle est à poser à l'identique sur tous les servers ; il n'y en a qu'un ici (docs.rke2.io, Server Configuration Reference).
- **Prérequis du mode `disabled`** (docs.k3s.io, Basic Network Options) : les servers font tourner kubelet, le CNI et kube-proxy, et joignent les agents en direct. Sinon, l'apiserver ne joint plus les services ni `kubectl exec` et `kubectl logs`. C'est le cas ici :
  - sc-confiance porte kubelet et Cilium, qui remplace kube-proxy (`disable-kube-proxy: true`) ;
  - le pare-feu d'hôte `hote-commun` (08c) ouvre 10250 depuis `remote-node`.
- **Ce qui change** : en mode `agent`, seul le trafic vers les kubelets passe par le tunnel ; les services sont déjà joints en direct. Passer en `disabled` ne change donc que le chemin vers les kubelets.
- **Pose** : `rke2.sh` pose `config/<vm>.yaml` tel quel en `config.yaml`, avec les jetons dans des fichiers à part (`token-file`, `agent-token-file`). Le script compare d'abord le sha256 de `config.yaml` en place à celui de la version versionnée d'avant ce changement, sans lire aucune valeur, et s'arrête s'ils diffèrent.

## Étapes, chacune sur accord nommé

- **`avant`** : lecture seule.
- **`appliquer`** : pose, puis redémarrage de rke2-server. Le plan de contrôle est indisponible le temps du redémarrage ; les pods continuent de tourner.
- **`retour`** : en cas d'échec seulement.
- **Vérification** : par `diag-exec-kata.sh croise` et `connexions` (brique 06), avec des accords à part.

## Prédictions

| # | Prédit | Confiance |
|---|---|---|
| E1 | `avant` : `config.yaml` en place identique à la version versionnée ; sélecteur actuel en HTTP CONNECT vers 127.0.0.1:9345 | haute |
| E2 | `appliquer` : `/readyz` en moins de 3 min, trois nœuds Ready | moyenne |
| E3 | Après la pose, le sélecteur de sortie relu n'envoie plus le trafic vers kubelet par 127.0.0.1:9345 : argument absent, ou sélection `cluster` sans HTTP CONNECT | moyenne : forme exacte non lue dans le code de RKE2 |
| E4 | Vérification `croise` (a), runc avec lecture lente vers sc-build : code 0, tout reçu | moyenne |
| E5 | Vérification `connexions` : pendant l'exec, une connexion directe de sc-confiance vers sc-build:10250 | moyenne |

**Ce que ces mesures ne couvrent pas** :
- les pipelines Tekton et les autres usages de l'apiserver vers les nœuds (journaux, métriques), à revérifier par un passage planifié ;
- la règle d'exploitation des morceaux de 64 Mio, qui reste en vigueur tant que E4 n'est pas mesurée.

**Commande prévue**, sous bash pour relever le code de sortie :

```
AVANT=1227858 mise exec -- poc/bricks/08b-rke2/egress-selector.sh <étape>
```

`1227858` est le dernier commit avant ce changement de `config/sc-confiance.yaml`.

**Rejeu de zéro** : `rke2.sh installer` pose désormais cette configuration, donc le mode `disabled` y sera appliqué d'emblée.

## Résultats des étapes avant et appliquer (10/11/2026, 20:42:53 à 20:43:59 UTC)

Accord : « 1 », à 20:42:49 UTC (transcription), en réponse aux choix numérotés : « 1. avant puis appliquer ». Les deux étapes sont lancées sous bash, code **0** chacune. Journaux : [`egress-selector-avant.log`](egress-selector-avant.log) et [`egress-selector-appliquer.log`](egress-selector-appliquer.log).

| # | Résultat |
|---|---|
| E1 | **Tenue** |
| E2 | **Tenue.** `/readyz` 15 s après le retour du redémarrage, trois nœuds Ready |
| E3 | **Tenue**, forme « argument absent » |

**`egress-selector-mode: disabled` appliqué** (20:43:00 à 20:43:59 UTC, code 0) :
- configuration en place identique, avant la pose, à la version versionnée de `1227858` (`0d327c84…`) ; ancien sélecteur en HTTP CONNECT vers `127.0.0.1:9345` ;
- rke2-server redémarré (retour de la commande à 20:43:43 UTC) ; `/readyz` à 20:43:58 UTC ; trois nœuds Ready ;
- **argument `--egress-selector-config-file` absent** du manifeste de kube-apiserver. Le pod en cours, démarré à 20:43:18 UTC, après le début de la pose, n'a aucun argument de sélecteur.

Kube-apiserver joint désormais kubelet sans le proxy du superviseur ni le tunnel de l'agent. **Non encore mesuré** : l'exec à lecture lente vers sc-build et la connexion directe vers 10250 (E4, E5).

## Résultats de la vérification (10/11/2026, 20:45:02 à 20:47:14 UTC)

Accord : « Oui, vérifie », à 20:44:57 UTC (transcription). Lancée sous bash, code **0**. Journaux (brique 06) : [`diag-exec-croise.log`](../../06-deb-sbuild/resultats/diag-exec-croise.log) et [`diag-exec-connexions.log`](../../06-deb-sbuild/resultats/diag-exec-connexions.log). Les journaux d'avant le changement sont renommés `diag-exec-croise-agent.log` et `diag-exec-connexions-agent.log`.

| # | Résultat |
|---|---|
| E4 | **Tenue.** Code 0 en 13 323 ms, 134 217 728 octets reçus, sha256 conforme |
| E5 | **Non mesurée.** Relevé « pendant » à 45 s, après la fin de l'exec (environ 13 s) |

**Vérification après `egress-selector-mode: disabled`** (20:45:02 à 20:47:14 UTC, code 0) :
- **`croise` (a), runc avec lecture lente de 128 Mio vers sc-build : code 0 en 13,3 s, sha256 conforme.** Avant le changement, cet exec bloquait à chaque essai : 6 sur 6 (croise, amont C1 et C2, pile, connexions, tunnel). **Le blocage a disparu**, sur un essai ;
- `croise` (b), Kata avec envoi lent : code 0 en 26,6 s, comme avant ;
- `connexions` : l'exec finit en code 0. **E5 n'est pas mesurée** : le relevé « pendant » tombe à 45 s, alors que l'exec s'est terminé vers 13 s. Aucune connexion de sc-confiance vers sc-build:10250 n'est vue aux trois relevés, ce qui ne prouve rien sur le chemin pendant l'exec.

Cela confirme, par l'effet, que le maillon fautif était sur le chemin par le proxy du superviseur et le tunnel de l'agent RKE2. **Non vérifié** : le chemin direct pendant l'exec (E5, relevé trop tardif), un gros exec sous Kata (512 Mio), et les pipelines Tekton après ce changement. Le découpage en morceaux de 64 Mio de `s3.sh` reste valable, mais n'est plus forcément nécessaire.

## Additif du 10/11/2026, 20:53 UTC : push, puis vérification complémentaire préparée à sec (NON LANCÉE)

**Push** : `fc4afa3..1e7533d` poussé entre 20:48:15 et 20:48:18 UTC, sur l'accord « Oui, pousse » : 36 commits. Avant le push, contrôle des secrets dans un worktree temporaire, sur 43 fichiers : aucun secret trouvé.

**Interprétation** : le message « continue », à 20:50:11 UTC (transcription), n'est pas un accord. Il est consigné comme une permission de préparer à sec, sans lecture du cluster ni lancement.

### Ce qui est préparé

**Étape `direct`**, ajoutée à [`diag-exec-kata.sh`](../../06-deb-sbuild/diag-exec-kata.sh) (brique 06) ; les étapes déjà lancées ne changent pas :
- **But** : mesurer E5, manquée par le relevé unique à 45 s de l'étape `connexions`.
- **Charge** : la même que `croise` (a), pour que les résultats restent comparables : pod runc restricted, 128 Mio lus lentement, délai de 150 s, **trois essais**.
- **Échantillonnage** : pour chaque essai, deux échantillonneurs démarrent 3 s avant l'exec, chacun dans une seule session ssh. Ils font 80 relevés, un toutes les 0,5 s, soit environ 40 s :
  - sur sc-confiance, les connexions établies vers l'InternalIP de sc-build:10250 ;
  - sur sc-build, les connexions établies sur :10250 depuis sc-confiance.
- **Relevés** : `ss -Htn` seulement, adresses et ports, sans `-p`. Rien n'est écrit sur les VM. Les relevés bruts sont gardés dans `diag-exec-direct-releves.tsv`.
- **Adresses lues, pas supposées** : l'InternalIP de sc-build est lue sur le nœud. L'argument `--kubelet-preferred-address-types` de kube-apiserver est affiché, ainsi que les heures de l'hôte et des deux VM.
- **Essai à sec**, sur la machine hôte : les deux filtres `ss` comptent bien une connexion locale réelle, et le résumé est juste sur des relevés fictifs.

**Kata à 512 Mio : la sonde de S3 est rejouée telle quelle**, sans modifier [`s3.sh`](../../06-deb-sbuild/s3.sh) :
- même déroulé qu'à 18:02 UTC, avec un pod Kata privilégié puis un pod runc témoin ;
- tailles de 1, 8, 64 et 512 Mio, à plein débit, par WebSocket ; la copie n'est refaite en SPDY qu'en cas d'échec.

La sonde écrit `s3-sonde.log`, qui est la seule trace du blocage à 512 Mio et que les notes et l'ADR 0001 citent. Pour ne pas la perdre, la commande prévue procède en deux temps :
1. le nouveau journal est renommé `s3-sonde-direct.log` aussitôt après le lancement ;
2. l'ancien est restauré depuis git.

Les liens existants restent ainsi justes, sans réécrire de texte.

### Prédictions

| # | Prédit | Confiance |
|---|---|---|
| D1 | L'InternalIP de sc-build vaut 192.168.161.12, l'adresse vers laquelle les relevés de 20:46 UTC filtraient | haute |
| D2 | `direct` : sur les trois essais, code 0 en 10 à 20 s ; 134 217 728 octets reçus, sha256 conforme | moyenne-haute : un seul essai mesuré jusqu'ici |
| D3 (E5) | Dans chaque essai, au moins un relevé sur sc-confiance montre une connexion établie vers sc-build:10250 pendant l'exec, et autant côté sc-build depuis sc-confiance. Les premiers relevés, avant l'exec, sont à 0 | moyenne |
| D4 | Les derniers relevés, quelques secondes après la fin de l'exec, reviennent à 0 | moyenne |
| D5 | Sonde : sous Kata, les quatre tailles passent par WebSocket, en code 0 et sha256 conforme ; 512 Mio en moins de 120 s ; aucune copie en SPDY | moyenne : Kata a été mis hors de cause par comparaison, jamais par un passage de 512 Mio |
| D6 | Sonde : sous runc, les quatre tailles passent, comme à 18:02 UTC | haute |

Si D3 échoue alors que D2 tient, l'exec passerait par un chemin non identifié, et la lecture de la cause serait à revoir.

**Ce que ces mesures ne couvrent pas** :
- les pipelines Tekton après ce changement, laissés au choix du propriétaire ;
- `sortie-builds.sh`, dont la correction de DESTINATIONS n'est toujours pas rejouée.

### Commandes prévues, chacune sur accord nommé

```
bash -c 'DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/diag-exec-kata.sh direct; echo "rc $?"'
bash -c 'DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s3.sh sonde; echo "rc $?"; d=poc/bricks/06-deb-sbuild/resultats; mv $d/s3-sonde.log $d/s3-sonde-direct.log && git checkout -- $d/s3-sonde.log'
```

**Correction du 10/11/2026, 20:55 UTC, avant tout lancement** : côté sc-build, le filtre utilisait l'adresse de sc-confiance tirée du dépôt. Il utilise désormais l'InternalIP de sc-confiance lue sur le nœud, comme pour sc-build. Si les deux adresses avaient différé, D3 aurait été ambiguë : une connexion vue côté apiserver, aucune côté kubelet. Les prédictions ne changent pas.

## Résultats de la vérification complémentaire (10/11/2026, 20:56:42 à 21:00:36 UTC)

Accord : « 3, les deux », à 20:56:34 UTC (transcription), en réponse aux choix numérotés « 1. `direct` ; 2. la sonde ; 3. les deux, dans cet ordre ». Les deux commandes prévues sont lancées sous bash, code **0** chacune ; restauration de l'ancien `s3-sonde.log` depuis git, code 0. Journaux (brique 06) : [`diag-exec-direct.log`](../../06-deb-sbuild/resultats/diag-exec-direct.log), relevés bruts [`diag-exec-direct-releves.tsv`](../../06-deb-sbuild/resultats/diag-exec-direct-releves.tsv), [`s3-sonde-direct.log`](../../06-deb-sbuild/resultats/s3-sonde-direct.log).

| # | Résultat |
|---|---|
| D1 | **Tenue.** InternalIP de sc-build 192.168.161.12, de sc-confiance 192.168.161.11, identiques au dépôt ; `--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname` |
| D2 | **Tenue.** Trois essais en code 0, en 13 298, 13 277 et 13 286 ms ; 134 217 728 octets reçus, sha256 conforme |
| D3 (E5) | **Tenue.** Dans chaque essai, 26 relevés sur 80 à une connexion, des deux côtés. Le premier tombe 0,15 à 0,19 s après le lancement de l'exec (heure de l'hôte) ; tous les relevés d'avant sont à 0 |
| D4 | **Tenue.** Dernier relevé non nul 0,4 s avant la fin de l'exec vue de l'hôte, puis 0 jusqu'à la fin, environ 24 s plus tard |
| D5 | **Tenue.** Kata : 1, 8, 64 et 512 Mio en code 0, sha256 conforme ; 512 Mio en 54 820 ms ; aucune copie en SPDY |
| D6 | **Tenue.** runc : les quatre tailles en code 0 ; 512 Mio en 3 269 ms |

Les horloges des trois machines concordent à 0,31 s près, aller-retour ssh compris (en-tête du journal), ce qui suffit pour situer les relevés par rapport à l'exec.

**E5 est tenue** : avec `egress-selector-mode: disabled`, kube-apiserver ouvre une connexion directe vers kubelet pour chaque exec, et elle ne dure que le temps de l'exec.

**Vérification complémentaire** (10/11/2026, 20:56:42 à 21:00:36 UTC, accord : « 3, les deux », code 0 à chaque commande) :
- **chemin direct observé (E5)** : pendant chacun des trois exec à lecture lente de 128 Mio vers sc-build, une connexion de sc-confiance vers sc-build:10250, vue des deux côtés, et une seule. Elle apparaît moins de 0,2 s après le lancement et disparaît à la fin de l'exec. Les relevés avant et après sont à 0 ;
- **exec à lecture lente vers sc-build : 3 sur 3** en code 0, 13,3 s chacun, sha256 conforme ;
- **Kata, 512 Mio à plein débit (sonde de S3 rejouée telle quelle) : code 0 en 54,8 s, sha256 conforme.** À 18:02 UTC, la même copie ne rendait pas la main en 120 s. runc : 512 Mio en 3,3 s.

Le blocage de S3 venait donc du chemin par le tunnel de l'agent RKE2, pas de Kata. **Non vérifié** : les pipelines Tekton après ce changement. Le découpage en morceaux de 64 Mio reste dans `s3.sh` ; le retirer serait un changement à part.
