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

