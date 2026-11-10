# Brique 08c : sortie Internet des pods de builds, prédictions (écrites le 10/11/2026 à 13:40 UTC, avant toute exécution)

**Statut** : préparé à sec, **NON APPLIQUÉ**.
- Fichiers : [`sortie-builds.sh`](../sortie-builds.sh) et [`builds-sans-internet.yaml`](../politiques/cilium-sortie/builds-sans-internet.yaml).
- La règle est hors de `politiques/cilium/`, que `durcissement.sh` applique en bloc.

## Origine et interprétation

Le constat P3 de la [brique 06](../../06-deb-sbuild/resultats/s1-predictions.md) (S1, 10/11/2026) : un pod de `builds` sans label a joint `snapshot.debian.org` en http (port 80).

Le propriétaire a répondu « Oui, prépare-le » à la question : « Faut-il fermer par défaut la sortie réseau des pods de builds sans politique dédiée ? ». Cette réponse est consignée comme une **interprétation** : préparer, sans appliquer. **Le choix entre (a) et (b) ci-dessous reste au propriétaire.**

**Lecture faite sans accord** : `kubectl get cnp,netpol -n builds` le 10/11/2026 à 13:32:37 UTC, pendant l'inventaire. Résultat : `prefetch-sortie` (CNP) et `construction-sans-sortie` (NetworkPolicy, `tekton.dev/task=construire-image`). Aucune autre lecture du cluster n'a été faite depuis.

**Push de 13:31:36 UTC** (`9e8e1a3..bc0f352`, contrôle des secrets OK sur 17 fichiers) : consigné ici.

## Deux options

**(a) Refus pur des adresses publiques** (préparée). Une CNP `egressDeny` vers `0.0.0.0/0`, sauf les plages privées (les mêmes que `prefetch-sortie`).
- Elle vaut pour tout pod de `builds` sauf `prefetch-gomod`.
- Elle a `enableDefaultDeny` à `false` et aucune règle d'autorisation. L'invariant d'union de `construction.sh` reste donc vrai.
- **Elle ne ferme PAS**, pour un pod de `builds` sans label :
  - l'API de RKE2 sur sc-confiance (6443), ouverte aux pods par `hote-confiance.yaml`, qui suppose leur sortie déjà bornée ;
  - OpenBao et les autres services du cluster ;
  - sc-stockage sur tous ses ports : Zot, Forgejo, Grafana, Loki, ssh ;
  - le DNS, et avec lui un canal par requêtes DNS ;
  - IPv6, à vérifier en `prealables`.

**(b) Vrai refus par défaut, avec une autorisation par tâche** (décrite seulement). Une politique à `enableDefaultDeny` pour tout `builds`, puis une autorisation pour chaque tâche :
- preparer : Forgejo et Zot ;
- publier-image et publier-fermeture : Zot ;
- prefetch : déjà fait ;
- les essais de J6, et les pods de mesure des briques 05 et 06.

Ses conséquences :
- l'union devient la règle, et le contrôle de `construction.sh` (« aucune politique n'autorise de trafic ») doit être réécrit ;
- chaque oubli casse la pipeline ;
- plusieurs passages de bout en bout sont à prévoir ;
- elle fermerait aussi l'API de RKE2, sc-stockage hors de Zot et Forgejo, et OpenBao.

Coût estimé : 1 à 2 jours.

## Lectures faites avant ces prédictions (dépôt et documentation publique de Cilium au tag `v1.20.4`)

- **Cilium 1.20.4** (`cilium.sh`), avec `policyCIDRMatchMode: nodes` (`cilium/valeurs.yaml`). sc-stockage est un nœud du cluster, et des règles CIDR le joignent déjà (`prefetch-sortie`, `scan`).
- **`Documentation/security/policy/intro.rst`**, « Endpoint default policy » : une politique qui sélectionne un pod le fait passer en refus par défaut dans la direction concernée. Une règle à `EnableDefaultDeny` désactivé est ignorée pour ce calcul. L'exemple `intercept-all-dns` sélectionne avec `NotIn` des pods qui n'ont pas le label.
- **`deny.rst`** : les refus sont actifs par défaut depuis la 1.9. Un refus l'emporte sur toute autorisation, CNP, CCNP ou NetworkPolicy. D'où l'exclusion de `prefetch-gomod`.
- **Kyverno** : `limites-obligatoires` refuse un pod sans limites (README de la 08c). Les pods témoins ont donc des limites.
- **Qui crée des pods dans `builds`** : les opérateurs n'ont que la lecture (`droits.yaml`) ; le contrôleur de Tekton les crée pour les TaskRuns ; l'administrateur du cluster aussi. **Limite** : quiconque peut créer un pod dans `builds` et lui poser le label `tekton.dev/task=prefetch-gomod` échappe au refus. C'est la même limite que pour `prefetch-sortie`.

## Évaluateur commun des sélecteurs

[`selecteurs.jq`](../../08-trust-plane/selecteurs.jq) évalue `matchLabels` et `matchExpressions` (In, NotIn, Exists, DoesNotExist ; tout autre opérateur est une erreur, donc un échec fermé), sur les NetworkPolicy comme sur les CNP.

Deux contrôles l'utilisent désormais :
- **`prefetch.sh reseau`** : l'ancien contrôle tenait toute CNP à `matchLabels` vide pour « sélectionne tout », et aurait échoué à tort sur `builds-sans-internet`.
- **`construction.sh`** : nouvelle vérification qu'aucune CNP n'autorise de trafic aux pods de `construire-image`. Le contrôle existant ne lisait que les NetworkPolicy.

**Essai hors cluster**, sur les YAML du dépôt et quatre politiques synthétiques :
- `builds-sans-internet` exclut `prefetch-gomod`, et retient `construire-image`, `publier-image` et un pod sans label ;
- une politique permissive à sélecteur vide est retenue pour tous ;
- un opérateur inconnu provoque une erreur ;
- un refus large ajouté fait signaler `prefetch-sortie` par le troisième invariant.

## Prédictions

| # | Étape | Prédit | Confiance |
|---|---|---|---|
| Q1 | prealables | Agents en v1.20.4, `enable-ipv6` à `false`, `policy-cidr-match-mode` à `nodes`. Politiques de `builds` : `construction-sans-sortie` et `prefetch-sortie`. Invariants OK. Règle absente | haute |
| Q2 | avant, sans label | DNS résolu pour les deux noms ; snapshot en 80 joint ; proxy.golang.org en 443 joint ; API de RKE2 jointe (HTTP 401 ou 403) ; Zot joint (401) ; Forgejo joint | haute pour snapshot (mesuré en S1), moyenne pour le reste |
| Q3 | avant, prefetch-gomod | Comme `prefetch.sh reseau` : DNS résolu, 443 public joint, snapshot en 80 refusé, API refusée, Zot refusé, Forgejo joint | haute |
| Q4 | avant, construire-image | Tout refusé, DNS compris (`construction-sans-sortie`) | haute |
| Q5 | appliquer | Règle valide pour Cilium. Les trois invariants sont OK : prefetch sélectionné par `prefetch-sortie` seule, aucune autorisation pour `construire-image`, aucune sortie CIDR sous un refus | haute |
| Q6 | apres, sans label | Snapshot en 80 et proxy.golang.org en 443 **refusés**. DNS, API de RKE2, Zot et Forgejo **toujours joints** | moyenne : premier `egressDeny` du PoC |
| Q7 | apres, prefetch-gomod | Identique à Q3 : l'exclusion par `NotIn` fonctionne | moyenne |
| Q8 | apres, construire-image | Identique à Q4 | haute |
| Q9 | bout_en_bout | `preuves.sh construction_durcie` réussit : PipelineRun de la tête de main réussi par le webhook, deux enveloppes de Chains de plus, aucune anomalie. preparer, construire et publier n'ont rien perdu | moyenne |
| Q10 | retirer | Règle supprimée ; le pod sans label rejoint de nouveau snapshot.debian.org | haute |

**Ce que le passage ne couvre pas**
- Un vrai PipelineRun de prefetch (Q7 ne mesure qu'un pod au label).
- Les essais de J6 et les briques 05 et 06 : chacune aura besoin d'une sortie dédiée vers son dépôt (instantané Debian pour S2, `vault` de Rocky pour M1 et M2), donc d'un label ajouté à l'exclusion. Ce sera une décision du propriétaire, le moment venu.

**Intégration** : la règle n'est pas dans le rejeu de zéro, et le prochain rejeu ne la reposerait pas. Son intégration est à décider avec son application.

## Corrigé à 13:43 UTC, avant tout push, sur relecture du conseiller (lectures du dépôt seulement)

### 1. L'option (a) ferait échouer le test 6 de `preuves.sh`, rejoué à chaque rejeu

Le test 6 vise `EXTERNE=203.0.113.10:443` (`T6_DESTINATIONS`, ligne 654), une adresse publique de documentation.

**Pour la tâche `construire-image`**
- Le test exige un flux `POLICY_DENIED` en `EGRESS` (lignes 833 à 839).
- Or `builds-sans-internet` sélectionne aussi ces pods, et un refus l'emporte. Dans `api/v1/flow/flow.proto` de Cilium 1.20.4, le refus explicite a son propre motif, `POLICY_DENY = 181`, distinct de `POLICY_DENIED = 133`.
- Prédit, si (a) est appliquée telle quelle : **KO**, flux en `POLICY_DENY`. Confiance moyenne : l'ordre d'évaluation entre ce refus et le refus par défaut de `construction-sans-sortie` n'est pas lu.

**Pour la contre-épreuve `preuve-test6-temoin`**
- Le test exige des SYN vers `EXTERNE:443` sur `enp1s0` de sc-build (ligne 807).
- Ce pod porte un autre label, donc `builds-sans-internet` le sélectionne et coupe cette sortie.
- Prédit : **KO**. Confiance haute.

**Deux décisions sur ce point, au propriétaire**
- (i) Exclure aussi `construire-image` de la règle. Le test garde `POLICY_DENIED`, mais on perd la défense en profondeur si `construction-sans-sortie` disparaissait.
- (ii) Revoir les attentes du test 6 :
  - accepter `POLICY_DENY` ;
  - prouver la non-sélection de la contre-épreuve par une destination privée (Zot ou Forgejo joints), et non plus par `EXTERNE`.

Le refus d'Internet devient alors une propriété de `builds`, plus seulement de la construction.

Aucun autre contrôle trouvé ne compte les politiques de `builds` ni ne juge un motif de rejet vers une adresse publique :
- `kata.sh`, `buildkit.sh` et `releve-secrets.sh` ne lisent que les NetworkPolicy de Kubernetes ;
- les tests 1 et 6 jugent OpenBao, Zot, Forgejo et l'API, toutes des adresses privées.

### 2. `bout_en_bout` : ses effets

`preuves.sh construction_durcie` n'est pas une lecture. Il :
- suspend puis reprend le CronJob `rattrapage` ;
- purge le PipelineRun de la tête de main ;
- demande une livraison de test à Forgejo ;
- reconstruit l'image ;
- fait écrire deux enveloppes de Chains de plus dans Zot (définitif) ;
- fait juger par la porte la provenance la plus récente ;
- ajoute une ligne au `chrono.tsv` de la 08, qui est commité.

L'environnement de `mise exec` suffit : celui de `mise.toml` est global (`[env]`), et la tâche `confiance:preuves` n'en ajoute pas.

### 3. La limite du label est plus étroite qu'écrit

Le contrôleur de Tekton v1.15.5 réécrit `tekton.dev/task` au nom de la tâche résolue, celle du bundle signé. C'est mesuré en J7 : le créateur avait imposé `autre` par `taskRunSpecs[].metadata`, et le pod a gardé `construire-image` (README de la 08, « Sélection des pods »).

**L'auteur d'un PipelineRun ne peut donc pas imposer `prefetch-gomod`.** Seuls échappent au refus :
- celui qui crée un pod brut dans `builds`, c'est-à-dire l'administrateur du cluster (les opérateurs n'ont que la lecture) ;
- une tâche signée nommée `prefetch-gomod`, qui doit figurer dans la liste revue.

### 4. Séquence, critère de retrait, estimation

- **Séquence prévue** : `prealables`, `avant`, `appliquer`, `apres`, `bout_en_bout`. **La règle reste en place à la fin.**
- **Critère de retrait** : `retirer` n'est lancé que si Q9 échoue, ou si Q6 montre Zot ou Forgejo coupés. Q10 devient conditionnelle.
- **Le test 6** n'est pas dans cette séquence : sa mise à jour suit la décision (i) ou (ii).
- **Estimation** : environ 30 min de passage, dont 5 à 10 min de PipelineRun. Décision avec le propriétaire au-delà d'1 h.
