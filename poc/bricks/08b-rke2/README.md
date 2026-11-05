# Brique 08b : RKE2 à la place de k3s, durci CIS, dans le PoC

Origine : décision du propriétaire du 05/11/2026, « A la place de k3s ce sera un rke2 plutot », précisée le même jour par « PoC maintenant ». Elle change le point 1 de la décision provisoire de l'ADR 0001, et avance dans le PoC ce que la note du 30/10/2026 réservait au cluster final.

Seuil : **tout `rejeu.sh` repasse de zéro sur RKE2 en profil CIS, sans KO, avec la même image `3a7ca1b1` ; les 8 tests négatifs repassent, test 6 compris, avec `kubeProxyReplacement=true` ; aucun compte de service lié à `cluster-admin`.**

Règles reprises : projets jugés par le doc 04, rien de « Risqué » ; versions épinglées ; empreintes et signatures vérifiées ; prédictions datées et committées avant chaque mesure ; passages ratés archivés ; accord du propriétaire avant toute action au niveau système.

## État

**Préparation à sec du 05/11/2026, 20:10 UTC : rien installé, cluster et VM intacts.** Seuls l'audit au doc 04 et ce protocole sont faits. Les scripts ne sont pas encore convertis : leur conversion dépend de D1 à D3.

Estimation : 14 h (conversion 4 h, rejeux et correctifs 7 h, comparaison et documents 3 h). Une décision s'impose à partir de 28 h.

## Exigences du propriétaire (05/11/2026)

| Exigence | Traduction |
|---|---|
| CoreDNS et metrics-server nécessaires | Ils restent dans le cluster. Seul leur mode d'installation est en jeu (D1) |
| Cilium nécessaire | Cilium reste le CNI. `cni: none` veut dire que RKE2 ne pose pas le sien, pas que le cluster s'en passe (D1) |
| « oui durcit le : et audit activé etc » | `profile: cis`, audit de l'API gardé avec la politique du PoC, chiffrement des Secrets gardé |
| Anti-usurpation et test 6 à remesurer | Inclus au seuil : ils repassent dans le rejeu, et les nouveaux ports y sont ajoutés. Istio n'est pas installé dans cette brique |
| `kubeProxyReplacement=true` | Retenu, avec `disable-kube-proxy: true`. La doc de Cilium décrit cette option sans la recommander de façon générale : c'est un choix du propriétaire, à mesurer |
| cert-manager « surement » nécessaire | Audité ici. Installation dans un jalon distinct, après le rejeu (D6) |

## Faits vérifiés (05/11/2026)

- **Version visée** : `v1.35.9+rke2r1` du 30/09/2026, même Kubernetes que le PoC, ce qui isole le changement. Sommes dans [`sante-signatures.log`](resultats/sante-signatures.log).
- **Contrôleur Helm** : `disable-helm-controller` est un `dropFlag` au tag v1.35.9 (`pkg/cli/cmds/server.go`, ligne 186). RKE2 ne permet pas de le couper, et CoreDNS comme metrics-server sont des HelmChart. Le contrôleur est `k3s-io/helm-controller` v0.17.9, qui crée une `ClusterRoleBinding` par chart vers `jobClusterRole`. Ce rôle est `cluster-admin` dans k3s (mesuré en J8). Sous RKE2 : **déduit, non mesuré**.
- **Aucun provisionneur de volumes dans RKE2** (doc Epinio, relevés tiers) : les PVC restent en attente. Or OpenBao et les workspaces de pipeline utilisent `local-path`, que k3s fournissait. **`local-path-provisioner` devient un composant à part entière.**
- **Ports nouveaux sur `sc-confiance`** : 9345 (supervisor), 2379 à 2381 (etcd). Sous k3s, le supervisor passait par 6443, et `k3s.sh` ne demande pas etcd (aucun `cluster-init`).
- **Kata et Cilium** : le guide Kata de Cilium impose `socketLB.hostNamespaceOnly=true` dès que le socket LB est actif. Le PoC ne l'avait pas, le socket LB étant coupé.
- **Gateway** : `kubeProxyReplacement=true` ne suffit pas à la Gateway API de Cilium, qui exige aussi `l7Proxy=true`, donc Envoy. `l7Proxy` reste à `false` : votre décision du 03/11 n'est pas rouverte ici.
- **Marges mesurées** : `sc-confiance` 4,6 Gi disponibles et 5,3 Go libres sur 15 Go ; `sc-stockage` 9,1 Go libres sur 20 Go ; hôte 21 Gi disponibles, 54 Go libres sur le pool. RKE2 recommande 8 Go de RAM pour lui-même, et le scan occupe déjà 3,4 Go sur ce nœud.
- **Images** : `rke2-images-core` pèse 773 Mo compressé. Sa liste contient CoreDNS, metrics-server, etcd et le pod de Helm.

## Impact sur le code

56 lignes propres à k3s dans 08 et 19b, en sept familles :

| Famille | k3s | RKE2 | Où |
|---|---|---|---|
| Unités | `k3s`, `k3s-agent` | `rke2-server`, `rke2-agent` | `k3s.sh`, `kata.sh`, `stockage.sh`, `controles.sh` |
| Configuration | `/etc/rancher/k3s` | `/etc/rancher/rke2` | `k3s.sh`, `kata.sh`, `stockage.sh`, 19b |
| État | `/var/lib/rancher/k3s` | `/var/lib/rancher/rke2` | `commun.sh`, `openbao.sh`, `fuites.sh`, 19b |
| Outils | `k3s crictl`, `k3s ctr` | binaires de `/var/lib/rancher/rke2/bin` | `kata.sh`, `buildkit.sh`, `tekton.sh`, `stockage.sh` |
| Arguments de l'API | journal de `k3s` | manifeste du pod statique `kube-apiserver` | `kata.sh`, `buildkit.sh` |
| Journaux | tout dans l'unité `k3s` | l'API, etcd et les autres passent en pods statiques | 19b : témoins et sources Alloy à revoir |
| Provisionneur | `kube-system`, app `local-path-provisioner` | espace à définir | `preuves.sh`, `fuites.sh` |

Ajout au test 6 : 9345 et 2379 à 2381 comme destinations refusées, ces ports étant nouveaux.

## Décisions soumises au propriétaire

| Décision | Recommandé | Autre choix |
|---|---|---|
| **D1, installation de Cilium, CoreDNS et metrics-server** | (a) depuis l'hôte par Helm, comme Cilium aujourd'hui : `cni: none`, `ingress-controller: none`, `disable:` des charts empaquetés. Tous restent en service. Aucun HelmChart, donc aucun compte `helm-*`. Votre option (b) du 01/11 tient, et les images restent vérifiées | (b) empaquetés par RKE2 : `cni: cilium` et `HelmChartConfig`. Plus simple, mais comptes `helm-*` à `cluster-admin` probables, à accepter en écart, et images Cilium de Rancher, non vérifiées par la chaîne actuelle |
| **D2, `local-path-provisioner`** | (a) v0.0.37, manifeste de la release et image épinglée par digest après revue, espace `local-path-storage`. Même logiciel que celui fourni par k3s, désormais visible | (b) autre pilote de stockage : audit et coût à chiffrer |
| **D3, taille des VM** | (a) `sc-confiance` de 8 à 12 Gi et de 15 à 25 Go. Le reste inchangé. Cela prend 4 Gi de plus sur l'hôte, qui en a 21 disponibles, et 10 Go sur le pool, qui en a 54 | (b) rien ne change : risque d'éviction pendant le scan, déjà suivi |
| **D4, calendrier** | (a) démarrer après le relevé du 06/11, 09:48 UTC. Le rejeu efface `sc-stockage`, donc Zot, Loki et les VSA. L'observation de la première suppression réelle de Zot repart à zéro, soit 14 jours après le rejeu | (b) attendre le 19/11 pour d'abord observer cette suppression |
| **D5, preuve du durcissement** | (a) mesurer CIS avec `kube-bench`, après audit au doc 04 | (b) se limiter à `profile: cis` et aux contrôles de RKE2 |
| **D6, cert-manager** | (a) jalon distinct après le rejeu : v1.21.3 (Kubernetes 1.33 à 1.36), émetteur sur la PKI d'OpenBao, droits sur les Secrets mesurés. Il ne couvrirait pas Zot, Forgejo, Loki ni Grafana, hors du cluster | (b) dans le rejeu : un échec serait plus difficile à attribuer |

## Ordre et prédictions

Prédictions écrites le 05/11/2026 à 20:10 UTC, sous réserve de D1 (a), D2 (a) et D3 (a). Un autre choix les invalide, et elles seront réécrites avant toute exécution.

1. **Conversion à sec** : aucun chemin de k3s ne reste actif dans 08 et 19b, hors commentaires et journaux archivés ; `bash -n` passe sur tous les scripts.
2. **RKE2 sur les trois VM (accord système)** : avec `profile: cis`, le server refuse de démarrer si l'utilisateur `etcd` manque ou si les sysctl ne sont pas posés. Une fois préparés, les nœuds restent `NotReady` jusqu'à l'installation de Cilium, puis `Ready`.
3. **`helm_cilium` (J8), inchangé** : aucun HelmChart, aucun compte de service lié à `cluster-admin`, pod portant un compte `helm-*` refusé.
4. **Pod Security** : au moins un composant sans label d'espace est refusé au premier passage. Sous k3s, le défaut était `privileged` ; sous CIS, il est `restricted`. Les pods Kata restent admis par l'exemption de RuntimeClass, à reposer dans le fichier du profil.
5. **DNS sous CIS** : les NetworkPolicy par défaut de `kube-system` visent les composants empaquetés. Un CoreDNS installé autrement peut être coupé des autres espaces. Je prédis une adaptation nécessaire ; sinon, l'écart sera consigné.
6. **Image** : `3a7ca1b1` reconstruite, binaire `e3749c68`, fermeture `74c265e7`. La distribution ne touche pas au contenu de la construction.
7. **Test 6, avec `kubeProxyReplacement=true`** : Zot, Forgejo, API, adresse externe, 9345 et 2379 injoignables depuis `construire-image`, `POLICY_DENIED` en sortie ; usurpation refusée, `INVALID_SOURCE_IP` ; rien sur `enp1s0`.
8. **Tests 1 à 5, 7 et 8** : mêmes verdicts que le rejeu `complet` du 03/11/2026. Porte, contrôles 6 et 7 conformes.
9. **Journalisation** : les dix témoins de la 19b relus dans Grafana, après adaptation des sources. Aucun secret dans Loki.
10. **Durée** : plus longue que les 3 574 s du rejeu d'un seul tenant, à cause d'etcd et des images. Le premier passage complet aura au moins un KO corrigé ensuite.

## Effets à connaître

- **Tout est effacé** : VM, Zot, Forgejo, Loki, Grafana et VSA de `sc-stockage` et du cluster. Perte acceptée pour une démo. `sc-replay` n'est pas touchée, et la VSA est re-poussée.
- **Observations interrompues** : celles de G7 et de la 19. La tâche `supply-chain-g7-premiere-suppression` du 19/11 devra être replanifiée.
- **Nouveaux composants** : RKE2 (chemin critique, « À surveiller »), `local-path-provisioner`, et etcd dans le plan de contrôle.
- **Images de RKE2 non signées** : aucune signature ni attestation trouvée sur `rke2-runtime`. Protection par sha256 seulement, comme k3s dans le PoC.
- **SELinux** : `selinux: true` ne s'applique pas sur les VM Debian 13.
- **Retour arrière** : `k3s.sh` reste dans l'historique git. Un retour demande un nouveau rejeu.

## Limites

- Rien n'est mesuré sous RKE2 à ce stade, en particulier Kata, `config-v3.toml.d`, le socket de containerd et le comportement exact du profil CIS.
- Le guide d'auto-évaluation CIS de RKE2 pour Kubernetes 1.35 n'a pas été trouvé ; le guide CIS 2.0 existe.
- La partie sur le provisionneur repose sur la doc d'Epinio et des guides tiers, pas sur la doc de RKE2. Elle sera vérifiée au premier démarrage.
