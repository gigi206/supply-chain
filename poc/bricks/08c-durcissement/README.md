# Brique 08c : durcissement du cluster RKE2 et plan des secrets

Origine : exigence du propriétaire du 05/11/2026, « configurer kyverno, psa, pss, vérifier les roles, network policies (celle de cilium sont plus puissantes), activer l'audit, etc pour obtenir la meilleur sécurité possible au niveau du cluster kubernetes », et « on met les secrets dans openbao ? ». Intégration des idées de son dépôt [`gigi206/k8s`](https://github.com/gigi206/k8s) décidée le même jour (« Oui, intègre »).

Seuil : **les 8 tests négatifs, la porte et les contrôles 6 et 7 repassent, cluster durci ; tous les ports d'hôte non listés sont refusés ; aucune règle Kyverno n'est en Audit à la fin.**

Rien n'est appliqué tant que la brique 08b n'a pas passé son seuil. Une étape à la fois, pour qu'un échec soit attribuable.

## État

**Préparation à sec du 05/11/2026, 20:39 UTC : rien appliqué.** `durcissement.sh verifier` est conforme ([journal](resultats/durcissement-verifier.log)) :
- politique d'audit : 18 cas simulés conformes, aucun corps de requête pour les Secrets, les ConfigMaps et les jetons ;
- règles Kyverno : 9 pods d'essai jugés comme prévu par le CLI 1.19.2 ;
- 4 politiques Cilium et 4 règles Kyverno acceptées par l'API en dry-run, sur le cluster k3s ;
- valeurs de Cilium rendues sans cluster.

**Non vérifié** : aucune de ces règles n'a tourné. Le dry-run valide le schéma, pas l'effet. Les ports viennent d'un relevé `ss` sous k3s, pas sous RKE2. `kube-apiserver` n'a pas lu la politique d'audit, et la clé `kubelet-arg+` n'a pas été essayée sous RKE2.

## Repris de `gigi206/k8s` (non remesuré dans ce PoC)

| Idée | Où | Adaptation |
|---|---|---|
| Politique d'audit par niveaux | `config/audit-policy.yaml` de la 08b | Règles Tekton, Kyverno et Cilium ajoutées, jetons en Metadata |
| Journaux kubelet et containerd en fichiers | `config/alloy/journaux-rke2.alloy` de la 08b | Absents de la conversion, correctif ; aussi lus par `fuites.sh` |
| `NodeRestriction` à garder dans la liste, `EventRateLimit`, réglages du kubelet | `config/` | Repris, seuils à relever |
| Structure des `default-deny` | `politiques/cilium/` | Fortement resserrée, voir ci-dessous |
| WireGuard strict | `config/valeurs-cilium-wireguard.yaml` | Mesure seulement. Format du chart 1.20.4 différent |
| Automount et espace `default` | `politiques/kyverno/` | Validation, pas mutation |

**Deux différences voulues avec ce dépôt** :
- la politique d'hôte y accepte tout le trafic de `cluster`, donc les pods. Ici, 9345 n'accepte que les nœuds, et etcd n'est pas ouvert ;
- `endpointSelector: {}` serait dangereux ici : les autorisations s'additionnent, et rouvriraient la sortie de `construire-image`. La liste d'espaces est donc fermée.

## Étapes et prédictions

Écrites le 05/11/2026 à 20:39 UTC, avant toute application. Chaque étape demande un accord, et la suivante n'est lancée qu'après la précédente.

| # | Étape | Prédiction |
|---|---|---|
| H1 | `h1_api` : plugins d'admission, `EventRateLimit`, kubelet | Arguments lus dans le pod statique. Trois nœuds `Ready`. Si `pod-max-pids=4096` ou `seccomp-default` gêne, le premier symptôme sera dans les pods runc, pas dans la construction Kata |
| H2 | `h2_kyverno` : 4 règles en Audit | Rien de refusé. `limites-obligatoires` et `images-zot-par-digest` relèvent des écarts, liste relevée puis corrigée |
| H3 | `h3_audit` : pare-feu d'hôte en audit | Aucun blocage. Des verdicts `audit` pour des flux non prévus, au moins sur sc-replay, dont l'adresse source n'est pas connue. Le redémarrage d'un agent applique les politiques d'hôte : console `virsh` prête |
| H4 | `h4_bloque` : fin du mode audit, test 6 | SSH, API et Zot restent joignables. Une tâche signée autre que `construire-image` n'atteint plus 9345 ni 2379 : la limite relevée au test 6 est fermée. Zot et Forgejo sont protégés pour la première fois |
| H5 | Règles Kyverno en `Deny` | Après correction des écarts de H2, la porte et les tests repassent |
| H6 | WireGuard, mesure | L'image `3a7ca1b1` reste identique. Le MTU sous Kata est le risque principal. Sans décision préalable, retiré après la mesure |

## Rôles

À traiter en H5, sans nouveau composant : ramener ou justifier les cinq lecteurs de Secrets à l'échelle du cluster (ADR 0000, limites résiduelles), revoir le droit des comptes de RKE2 absents sous k3s, et mesurer qui peut créer un `HelmChart`, puisque le contrôleur Helm reste actif.

## Plan des secrets (décision S1 ouverte)

Relevé du cluster le 05/11/2026, 23 Secrets, valeurs non lues :

| Catégorie | Secrets | Sort proposé |
|---|---|---|
| Identifiants Zot et webhook | `zot-images`, `zot-fermetures`, `zot-chains`, `forgejo-webhook` | OpenBao |
| À relever | `signing-secrets` | Contenu à vérifier avant décision |
| Jetons de service | `prometheus-lecture-jeton`, `alloy-evenements-jeton` | Durée et usage à revoir |
| Certificats internes | Kyverno, Tekton, Hubble, Cilium | Restent, ou cert-manager |
| Amorçage | `openbao-tls` | Reste : OpenBao ne peut pas fournir son propre certificat au démarrage |

**S1, recommandé (a)** : lecture directe d'OpenBao par jeton court, comme pour l'horodatage et le scan. Le secret n'existe alors pas dans Kubernetes. External Secrets seulement si un outil exige un vrai Secret. **(b)** : External Secrets partout : plus simple, mais le secret reste dans etcd, et le fournisseur OpenBao est listé en alpha.

## À auditer avant toute décision

Kubescape, NeuVector, Tetragon (brique 17), et l'essai du runtime en bloc de Kata, qui pourrait contourner le blocage virtio-fs. Aucun n'entre dans cette brique sans passage au doc 04.

## Effets à connaître

- **H1 et H3 redémarrent** RKE2 et les agents de Cilium.
- **H3 et H4 peuvent couper l'accès aux nœuds.** Secours : console `virsh`, suppression de la politique. Comme le cluster est reconstructible par `rejeu.sh`, le pire cas est un rejeu.
- **Audit** : plus de volume, lu sur `sc-confiance` puis envoyé à Loki. Mesuré au rejeu de la 08b, jamais prédit en chiffre.
- **Retrait** : supprimer les fichiers d'appoint et les politiques, puis relancer `cilium.sh appliquer`.

Estimation : 10 h, hors plan des secrets. Une décision s'impose à partir de 20 h.
