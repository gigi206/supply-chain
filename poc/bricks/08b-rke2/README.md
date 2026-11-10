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

## Décisions du propriétaire (05/11/2026, vers 20:13 UTC)

« Oui, tout en (a) » : D1 (a), D2 (a), D3 (a), D4 (a), D5 (a), D6 (a).

## Conversion à sec (05/11/2026, 20:21 UTC, rien installé, cluster k3s inchangé)

**Le choix de fond : `DISTRO=k3s` reste le défaut.** Le cluster en service et le relevé du 06/11/2026 passent par ces scripts : aucun chemin ne doit bouger avant le rejeu. `DISTRO=rke2` n'est pris que par `rke2.sh`, ou par `rejeu.sh` lancé avec cette variable. `mise.toml` n'est pas touché.

| Fichier | Rôle |
|---|---|
| [`distro.sh`](../08-trust-plane/distro.sh) | Chemins, unités, outils et `args_apiserver`, selon `DISTRO` |
| [`rke2.sh`](rke2.sh) | `telecharger`, `rendu`, `installer`, `cis` |
| [`config/`](config/) | Configuration des trois nœuds, Pod Security, valeurs de Cilium et de CoreDNS |
| [`essai-k3s.sh`](essai-k3s.sh) | Preuve de non-changement sous k3s |
| [`sante.sh`](sante.sh) | Audits du doc 04, dont kube-bench |

**Vérifié à sec** :
- [`rke2-telecharger.log`](resultats/rke2-telecharger.log) : toutes les empreintes conformes, 846 Mo.
- [`rke2-rendu.log`](resultats/rke2-rendu.log) : charts rendus. CoreDNS garde `k8s-app=kube-dns` et 10.43.0.10. Dans la configuration de Cilium, seules changent `kube-proxy-replacement` et `bpf-lb-sock-hostns-only` (plus la clé `kube-proxy-replacement-healthz-bind-address`, vide) ; `enable-l7-proxy` reste à `false`.
- [`essai-k3s.log`](resultats/essai-k3s.log) : substitution inverse sur chaque script, seules les lignes structurelles restent ; 11 lectures réelles conformes sur le cluster k3s ; `args_apiserver` de RKE2 essayé sur un manifeste d'essai, pas sur un vrai.
- [`controles-essai-08b.log`](../08-trust-plane/resultats/controles-essai-08b.log) : `controles.sh`, lecture seule, sur le cluster en service.

**Non vérifié** : aucun script n'a tourné avec `DISTRO=rke2` hors `telecharger`, `rendu` et `sante`. Le binaire `rke2` n'a jamais été exécuté, donc la configuration des nœuds n'a pas été validée. Le rendu des charts ne prouve pas leur fonctionnement.

**Constats de la conversion** :
- **Pod Security** : `rke2.sh` ne pose pas l'exemption. Comme sous k3s, `kata.sh essais` doit d'abord mesurer le refus du pod Kata privilégié, cette fois par le défaut du profil cis, avant que `kata.sh exemption` ne redémarre le server.
- **Réseau du profil cis** : avec `cni: none`, RKE2 retire les politiques par espace (`cisnetworkpolicy.Cleanup`), mais garde celles de `kube-system`, `default` et `kube-public`. Celles de CoreDNS et de metrics-server visent des labels que les charts conservent. La prédiction 5 ci-dessus est donc **remplacée** ci-dessous.
- **busybox** : absente des images de RKE2, alors que la 08 et le pod auxiliaire de `local-path` s'en servent. Archive ajoutée, même digest amd64 que `kata.sh`.
- **`local-path`** : le manifeste amont n'est pas la classe par défaut, et les pipelines en ont besoin. `rke2.sh` pose l'annotation.
- **Chiffrement des Secrets** : `secrets-encryption` est masquée dans RKE2. Elle n'est pas dans `config/` ; son état est relevé par `rke2 secrets-encrypt status`.
- **kube-bench** : audité ([`sante-kubebench.log`](resultats/sante-kubebench.log)), Scorecard 5,2 du 16/03/2026, 82 des 100 dernières fusions par une seule personne, sommes seulement. **Aucun profil RKE2 pour Kubernetes 1.35** : `rke2-cis-1.9` est le plus proche. Son résultat sera indicatif, pas une preuve de conformité CIS 2.0.

## Prédictions de l'application (05/11/2026, 20:21 UTC)

Elles remplacent la liste du 05/11/2026, 20:10 UTC, sous D1 à D6 (a). Elles valent à partir de la commande `DISTRO=rke2 mise run confiance:rejeu -- rke2`, sous accord, après le relevé du 06/11, 09:48 UTC.

1. **Installation** : VM recréées, `sc-confiance` en 12 Gi et 25 Go ; les trois nœuds `Ready` après Cilium ; 0 HelmChart, 0 pod `kube-proxy`. Risque connu : les chemins CNI, qui ont fait échouer le premier passage sous k3s, peuvent demander un ajustement de `valeurs-cilium.yaml`.
2. **`cilium.sh verifier`, `helm_cilium`** : conformes, ni compte ni liaison `helm-*`, aucun compte de service lié à `cluster-admin`.
3. **`kata.sh essais`** : pod Kata privilégié refusé par le défaut cis, puis admis après l'exemption.
4. **Pod Security** : au moins un composant de la plateforme refusé au premier passage, faute de label d'espace (défaut `restricted`). Liste non prédite, relevée.
5. **DNS et métriques sous CIS** : aucune adaptation de NetworkPolicy, les labels étant conservés. `kubectl top nodes` répond. Cette prédiction peut tomber sur metrics-server : le serveur d'API n'est pas un pod de `kube-system`.
6. **Image et entrées** : image `3a7ca1b1`, binaire `e3749c68`, fermeture `74c265e7`.
7. **Test 6** : `construire-image` n'atteint ni Zot, ni Forgejo, ni l'API, ni l'adresse externe. Sous RKE2, `preuves.sh` y ajoute 9345 et 2379 : refusés pour `construire-image`, et joignables par la contre-épreuve, qui doit les atteindre pour que le test prouve quelque chose. Ce serait aussi une limite à consigner : une autre tâche signée garde cette sortie. Motifs `POLICY_DENIED` et `INVALID_SOURCE_IP`, rien sur `enp1s0`, adresse de service toujours traduite avant la politique.
8. **Tests 1 à 5, 7 et 8, contrôles 6 et 7** : mêmes verdicts que le rejeu `complet` du 03/11/2026.
9. **Journalisation** : les dix témoins relus dans Grafana, avec `rke2-server.service`. Les journaux de `kube-apiserver` passent par la source des pods. Aucun secret dans Loki.
10. **Disque et mémoire** : `sc-stockage` garde au moins 5 Go libres (9,1 Go aujourd'hui, images de RKE2 en plus). `sc-confiance` n'atteint pas le seuil d'éviction pendant le scan.
11. **`kube-bench`** : des FAIL ou WARN liés au profil inadapté. Chacun sera classé, aucun n'est prédit.
12. **Durée et correctifs** : plus de 3 574 s, et au moins un KO corrigé avant un passage complet. Les passages ratés seront archivés.

## Additif : idées du dépôt `gigi206/k8s` (05/11/2026, 20:39 UTC, « Oui, intègre »)

- **Correctif de la conversion** : sous RKE2, kubelet et containerd écrivent dans des fichiers, pas dans le journal. Ils n'étaient ni collectés ni contrôlés. [`journaux-rke2.alloy`](config/alloy/journaux-rke2.alloy) les envoie à Loki, `fuites.sh` les lit, et les sources attendues de la 19b les vérifient. Repéré dans [`gigi206/k8s`](https://github.com/gigi206/k8s).
- **Politique d'audit** : [`config/audit-policy.yaml`](config/audit-policy.yaml), reprise de ce dépôt et adaptée, remplace `k3s/audit-policy.yaml` sous RKE2. Elle **revient sur D14 (a) de la 19b** : les lectures de Secrets et de ConfigMaps sont journalisées pour tous, en Metadata. Sous k3s, rien ne change.
- **Prédiction ajoutée au n° 9** : les journaux `kubelet` et `containerd` sont lus dans Grafana, et les tests qui lisent l'audit repassent. Le volume d'audit est relevé, pas prédit.
- Le reste du durcissement est dans la [brique 08c](../08c-durcissement/README.md), après le rejeu de cette brique.

## Additif : D6 relevée à sec (05/11/2026, 20:50 UTC)

D6 (a) reste valable tant que le propriétaire n'en décide pas autrement. Les relevés de la [brique 08d](../08d-cert-manager/README.md) montrent un seul consommateur direct, Hubble, sur un port sans client, et un contrôleur en écriture sur tous les Secrets. La CA du PoC ne peut pas signer l'émetteur : OpenBao devrait porter une racine séparée. Décision D7 ouverte, rien installé.

## Additif : relecture à sec de la voie `DISTRO=rke2` (06/11/2026, 08:32 UTC, cluster k3s inchangé)

Relecture de `rke2.sh`, de `distro.sh` et des scripts du rejeu, puis [`releve-restricted.sh`](releve-restricted.sh), tout en `--dry-run=server`. Journal : [`releve-restricted.log`](resultats/releve-restricted.log). Rien n'a tourné sous RKE2 : ces mesures portent sur l'admission du cluster k3s, pas sur l'exécution. Le passage planifié de 09:30 UTC n'est pas concerné : son script ne lit aucun fichier de la 08.

**Blocages mesurés, non corrigés, décisions ci-dessous** :

| # | Mesure | Effet attendu sous RKE2 |
|---|---|---|
| 1 | Contrôleur de Chains refusé par `restricted` : capacités, `runAsNonRoot`, seccomp. L'espace `tekton-chains` n'a pas de label, et le défaut du profil cis s'y appliquerait. Avec ces trois réglages, le même pod est admis ; son conteneur tourne déjà en UID 65532 | `tekton.sh` s'arrête sur `kubectl wait` : rien n'est signé |
| 2 | Pod à `hostPath` refusé par `pods-isolation` dans un espace ordinaire, témoin en `emptyDir` admis. `provisioner.go` au tag v0.0.37 ajoute bien ce `hostPath`. Les webhooks de Kyverno n'excluent que `kube-system` et `kyverno` ; `local-path-storage` n'y est pas | Après J6, plus aucun volume `local-path` : **les workspaces des pipelines restent en attente**. Sous k3s, ce pod tournait dans `kube-system` |
| 3 | Gabarit du banc C refusé par PodSecurity, sans passer par Kyverno : le message est celui de PodSecurity alors que Kyverno le refuserait aussi. **PodSecurity répond donc avant Kyverno** | `bancc` n'a pas de label : les témoins du banc C, sans `securityContext`, y seraient refusés. Pire, le contrôle `c1-unsigned` de `politique.sh` passerait pour une mauvaise raison : il attend `FAIL` et prouverait « évalué par Kyverno » sur un refus de PodSecurity. Les cas de `cas-admission.py`, eux, sont conformes (section 7 du journal) |
| 4 | `sample-app` de `j2-essais` refusé par `restricted`, admis avec `runAsNonRoot` et seccomp. Le pod `dns` a le même `securityContext` et n'a pas été présenté. busybox ne déclare aucun utilisateur | `stockage.sh` échoue en J2 |

**Mesuré conforme** : les pods de `kyverno` passent `restricted` ; `bancc`, `cilium-secrets`, `default` et `observabilite` n'ont aucun pod ; les cas `zone-confiance` et `pod-cap-net-bind`, présentés à `scan`, sont admis. D'après leurs manifestes, non présentés à l'API : les pods de `j3-essais`, `j5-essais`, `preuve-controleurs` et le conteneur d'initialisation de S1 (`chains-zot-injecte.yaml`) sont conformes. Les pods de `kata.sh` et de `preuves.sh` visent `builds`, déjà en `restricted` sous k3s : même décision attendue.

**Craintes écartées à la lecture** :
- CoreDNS : le chart ne fixe pas `replicas`, le déploiement démarre donc à un pod, et `--wait` ne bloque pas sur le seul `sc-confiance`, malgré l'anti-affinité obligatoire. Le second réplica du `preventSinglePointFailure` est attendu sur `sc-stockage`, seul autre nœud sans taint : non mesuré.
- `share/rke2/rke2-cis-sysctl.conf`, unités et binaires sont aux chemins attendus dans l'archive. Les images de CoreDNS, de son autoscaler et de metrics-server sont dans `rke2-images-core`.
- Le drop-in de Kata : `config-v3.toml.d` est bien importé par le gabarit de k3s au commit `58877f27435f`, celui de `go.mod` de RKE2.
- `k8sServiceHost` est déjà posé pour Cilium, ce que `kubeProxyReplacement=true` exige. Les zones de Kyverno n'énumèrent pas `local-path-storage`.

**Corrigé** : trois littéraux `-n kube-system` de `preuves.sh`, lignes 2485, 2486 et 2497, visaient le pod `$lp` que la ligne 2477 cherche dans `$D_LP_NS`. Sous RKE2, le contrôle aurait échoué en `NotFound`. Identité sous k3s, donc invisible pour `essai-k3s.sh` : **la phrase « aucun chemin de k3s ne reste actif » de la prédiction 1 du 05/11/2026, 20:10 UTC, était fausse sur ce point**. Les autres `-n kube-system` trouvés visent Cilium ou des refus de droits, et restent justes.

### Décisions D8 à D11, ouvertes (D7 est celle de la 08d)

| Décision | Recommandé | Autre choix |
|---|---|---|
| **D8, Chains sous `restricted`** | (a) `runAsNonRoot`, seccomp `RuntimeDefault` et `capabilities.drop: [ALL]` ajoutés au rendu de `tekton.sh` sous `DISTRO=rke2`. Le signataire reste en `restricted` | (b) `tekton-chains` en `enforce=privileged` : plus simple, mais affaiblit l'espace de la clé de signature |
| **D9, `local-path-storage` et Kyverno** | (a) espace ajouté aux exclusions des webhooks de Kyverno sous `DISTRO=rke2`, comme `kube-system` sous k3s. Pas de dépendance des volumes au démarrage de Kyverno, ce qui compte après un redémarrage. **Ce que cela expose** : l'espace devient système, hors de `pods-isolation` et en `privileged`, et le compte du provisionneur y crée des pods par son Role (section 6 du journal). Ce compte échappe donc à Kyverno, comme dans `kube-system` sous k3s, ni plus ni moins. Sur 80 comptes lus, les autres autorisés sont ceux des contrôleurs de `kube-system`, par des liaisons de tout le cluster, relevées sous k3s, à relire sous RKE2 | (b) installer `local-path` dans `kube-system` : aucune exclusion nouvelle, mais revient sur D2 (a) |
| **D10, `bancc`** | (a) espace en `enforce=privileged` sous `DISTRO=rke2` : ses pods ne sont jamais créés, tout y passe en dry-run. Le banc C et ses grilles ne bougent pas | (b) modifier le gabarit du banc C : exclu, le banc est figé |
| **D11, `j2-essais`** | (a) `securityContext` conforme aux deux pods de `stockage.sh`, avec `runAsUser: 65532` explicite : la variante mesurée le porte, et sans lui, busybox, qui ne déclare aucun utilisateur, serait probablement refusé au lancement par kubelet. Admission mesurée, exécution non. Sans effet attendu sous k3s : prédiction | (b) espace en `privileged` : inutile pour deux pods simples |

## Additif à la prédiction 4 (06/11/2026, 08:32 UTC, avant tout rejeu)

Le texte du 05/11/2026 reste écrit. « Liste non prédite » est désormais remplacée par une liste relevée à sec. **Sans D8 à D11, sont attendus refusés** : le contrôleur de Chains, les témoins du banc C dans `bancc`, et les pods de `j2-essais`. L'adoption de D8 à D11 changera cette prédiction, par un nouvel additif. Cette liste ne couvre que ce que l'admission permet de voir sur k3s : un refus d'un composant non relu ici reste possible.

## Additif : `builds` avant J6 (06/11/2026, 08:56 UTC, cluster k3s inchangé)

Cinquième blocage, trouvé en cherchant ce qu'un relevé des pods présents ne pouvait pas voir : les fenêtres de temps et les pods éphémères. [`releve-builds-j4.sh`](releve-builds-j4.sh), tout en `--dry-run=server`, journal [`releve-builds-j4.log`](resultats/releve-builds-j4.log). **Le rejeu s'arrêterait ici en J4 au plus tard, avec D8 à D11 seules appliquées.**

**Correction** : l'additif de 08:32 UTC dit que les pods de `kata.sh` et de `preuves.sh` visent `builds`, « déjà en `restricted` sous k3s ». C'est vrai après J6, et ces pods tournent après J6. Mais `builds` n'a aucun label avant `politique.sh restreint` : `tekton/builds.yaml` n'en déclare pas, et les journaux de J6 archivés le montrent (« aucun label pod-security, niveau privileged par défaut »). Le texte de 08:32 UTC reste écrit.

| # | Mesure | Effet attendu sous RKE2 |
|---|---|---|
| 5 | Pod réel de J4, `essai-signature-pod`, du 03/11/2026, présenté à `builds` : **refusé** par `restricted` sur `prepare`, `place-scripts` et `step-publier`. Conteneurs de Tekton réglés seuls : **encore refusé**, sur `step-publier`. Étape réglée aussi : PodSecurity passe, puis `zone-build` refuse le jeton du compte de service, règle posée en J6, après ce pod | `builds` hérite du défaut `restricted` dès sa création, avec `set-security-context` encore à faux. `tekton.sh signature` échoue sur `kubectl wait` : même effet que le blocage 1, à la même étape, et la correction de D8 ne le lève pas |
| 6 | `politique.sh:612` retire le label `enforce` pour le cas « sous warn et audit ». Lecture seule : aucun retrait ailleurs dans les scripts de la 08 | Sous k3s, retirer le label redonne `privileged`. Sous RKE2, il redonne `restricted` : le pod est refusé au lieu d'être tracé, `verdict … True` sort en erreur, J6 s'arrête |

**Mesuré conforme** : tous les CronJob et Job présents sont dans des espaces en `enforce=restricted`, aucun dans un espace sans label, `kyverno` compris. **D'après leurs manifestes, conformes ou hors de l'API** : `reserve-c`, `essai-j5` et les essais de la 08c passent par `kyverno apply`, sans l'API ; les pods de `pod_outils`, `pod_scan`, `pod_essai` et `essai-reseau-rattrapage` portent les réglages de `restricted`. `local-path-storage` est déjà en `privileged` avant son manifeste (`rke2.sh:173`). Sonde `sonde-o4` de la 19 : pod conforme, espace `tsa` déjà en `restricted`, et O4 n'est pas rejoué. Les pods de 01, 03, 19 et 19b tournent après J6 ou dans `builds` : 03 en J7 et J8, même état que sous k3s ; 01, 19 et 19b n'ajoutent aucun pod trouvé à la lecture de leurs `kubectl apply` et `create`.

**Non présenté à l'API** : l'EventListener de J4 dans `builds`. Sans objet sous D12 (a).

### Décision D12, ouverte

| Décision | Recommandé | Autre choix |
|---|---|---|
| **D12, `builds` entre J4 et J6** | (a) sous `DISTRO=rke2`, `enforce=privileged` explicite sur `builds` à sa création, puis `politique.sh restreint` pose `restricted` comme aujourd'hui ; la ligne 612 passe de retrait du label à `enforce=privileged`, ce qui ne change rien sous k3s. Reproduit le chemin déjà mesuré, état final identique. **Ce que cela expose** : `builds` en `privileged` pendant le rejeu, de J4 à J6, comme sous k3s. **À écrire avec soin** : pose dans `tekton.sh`, seulement si le label est absent, jamais dans `tekton/builds.yaml`, dont `politique.sh:653` exige qu'il conserve `restricted`. `tekton.sh signature` rejoué après J6 ne doit ni rabaisser l'espace ni échouer : `kubectl label` sans `--overwrite` sort en erreur sur une valeur différente, code 1 mesuré (section 8 du journal), ce qui arrêterait le script sous `set -e` | (b) `builds` en `restricted` dès J4 : `set-security-context` activé par `tekton.sh`, étapes de `essai-signature.yaml` et `webhook.yaml` réglées. Plus strict, mais il déplace l'essai du drapeau de J6, et les tâches signées d'avant `restreint`, comme `j6-signee`, restent à relire. Le cas de la ligne 612 demande (a) de toute façon |

## Second additif à la prédiction 4 (06/11/2026, 08:56 UTC, avant tout rejeu)

Le texte précédent reste écrit. **Sans D12, sont aussi attendus refusés** : les pods de TaskRun de J4 et ceux de J6 antérieurs à `restreint`, ainsi que le cas « sous warn et audit » de la ligne 612. La réserve demeure : un refus d'un composant non relu reste possible, et aucune de ces mesures ne porte sur l'exécution.

## Additif : D8 à D12 adoptées en (a) (« Oui, tout en (a) », 06/11/2026, 09:11 UTC, cluster k3s inchangé)

Ces cinq décisions, ouvertes plus haut, sont tranchées par le propriétaire. Les tableaux de D8 à D12 restent écrits. Le correctif a été préparé hors du dépôt, vérifié à sec, puis appliqué tel quel. **Rien n'a tourné sous RKE2, et rien n'a été appliqué au cluster.**

| Décision | Fichier | Sous k3s |
|---|---|---|
| D8 | `tekton/chains/restricted.yaml`, ajouté au rendu par `tekton.sh rendre` | Rendu de Chains identique, 20 objets, `b21f5f22…` avant et après |
| D9 | `politique.sh`, `install.yaml` de Kyverno modifié avant le rendu ; contrôle du rendu, arrêt si l'espace n'est pas exclu | `install.yaml` inchangé, contrôle passé sur `kube-system` |
| D10 | `politique.sh`, fonction `espace_essai`, seul créateur de `bancc` | Aucun label |
| D11 | `stockage.sh`, `securityContext` des deux pods | **Change aussi sous k3s** : `dns` passe de root à 65532. `sample-app` déclare déjà `65532:65532`, son utilisateur ne change pas. Rejouer `stockage.sh` sur le cluster k3s actuel échouerait : le `securityContext` d'un pod existant ne se modifie pas |
| D12 | `tekton.sh`, fonction `builds_privilegie` ; `politique.sh`, retrait du label remplacé par `enforce=privileged` | Label de `builds` non posé. **Le cas sous warn et audit change aussi sous k3s** : sans effet attendu, non mesuré à l'exécution, notamment sur l'annotation lue par la fonction `violations` |

**Vérification** : [banc](resultats/verif-d8-d12.sh) et [journal](resultats/verif-d8-d12.log), blocs extraits des scripts du clone qui portait le correctif, faux `kubectl` pour les branches RKE2, `--dry-run=server` sur k3s pour l'admission. Chains rendu sous `rke2` admis dans `scan`, les deux pods de `stockage.sh` admis dans `builds`, le pod `dns` présenté pour la première fois ; témoins refusés. `builds_privilegie` : 1 label sans niveau posé, 0 sur `restricted` ou `privileged`, jamais `--overwrite`. Témoin de D9 sans le `sed` : KO. Exclusion réelle mesurée sur `pods-isolation` : le même pod à `hostPath` admis dans `kube-system`, refusé dans `bancc`, et le sélecteur `NotIn` lu sur les webhooks des `ValidatingPolicy`. L'ajout de `local-path-storage` à ce sélecteur n'a pas été essayé sur l'API. L'espace n'est pas ajouté à `resourceFilters` : le webhook n'étant plus appelé, ce n'est pas attendu nécessaire, à confirmer au rejeu.

**[Premier passage](resultats/verif-d8-d12-premier-passage.log) raté** : le banc décalait `$T`, aucun rendu n'existait, et il a affiché à tort « OK rendu identique » et « aucun KO ». Corrigé : rendus vides refusés.

**Relu sans conflit** : `politique.sh` charge `distro.sh` par `commun.sh` (ligne 77) ; la 08c n'interdit pas `enforce=privileged` ; `chains-zot.yaml` n'ajoute aucun conteneur ; le conteneur injecté par S1 porte déjà ses réglages.

**Balayage statique (06/11/2026, 09:16 UTC, lecture seule, sans cluster)** : tous les espaces créés par les scripts et les manifestes de la 07a, de la 08, de la 08b et de la 08c, croisés avec leurs gabarits de pods, y compris les espaces éphémères qu'un relevé du cluster ne voit pas. Sans label sous k3s et absents des relevés : `j3-essais` et `j5-essais`, gabarits conformes ; `preuve-resolveurs`, aucun pod ; `preuve-controleurs`, `hc_pod` conforme à `restricted`, donc le refus attendu reste celui de `tekton-controleurs-builds`. Le pod `essai-j5` de `tsa.sh`, sans réglage, ne sert qu'au CLI de Kyverno ; celui de `politique.sh` passe dans `bancc`, couvert par D10. **Aucun sixième blocage trouvé**. Cette lecture ne couvre pas les pods créés par des contrôleurs, sauf ceux des TaskRun de `builds`, ni l'exécution.

## Troisième additif à la prédiction 4 (06/11/2026, 09:11 UTC, avant tout rejeu)

Les textes précédents restent écrits. **Avec D8 à D12 en (a), aucun des cinq blocages relevés ne doit bloquer le rejeu.** Pour confronter, sous `DISTRO=rke2` :

| # | Prédiction | Confiance |
|---|---|---|
| 4a | Chains `Available` sous `restricted`, signatures et attestations produites | Moyenne : UID 65532 déjà en service, exécution avec seccomp `RuntimeDefault` jamais mesurée |
| 4b | `j2-essais` : `sample-app` `Ready`, `dns` `Succeeded`, résolution réussie | Haute pour `sample-app`, moyenne pour `dns` : `nslookup` jamais lancé en 65532 |
| 4c | `builds` en `privileged` à J4, TaskRun `essai-signature` réussi, puis `restricted` après `restreint`, et le contrôle d'état final de `politique.sh restreint` conforme | Haute |
| 4d | Cas sous warn et audit : `True`, violations de `step-publier` tracées | Moyenne : annotation d'audit non mesurée avec le label explicite |
| 4e | Les volumes de pipeline se créent après J6 : pod auxiliaire de `local-path` non refusé | Moyenne : exclusion mesurée pour `kube-system`, pas pour cet espace |
| 4f | `c1-unsigned` refusé par Kyverno, pas par PodSecurity ; verdicts de parité inchangés | Haute |

La réserve demeure : un refus d'un composant non relu reste possible. La prédiction 12 reste valable : au moins un KO corrigé avant un passage complet.

## Rejeu sous RKE2 (06/11/2026, 13:10 UTC)

Lancé sur accord du propriétaire (« Oui, lance », 06/11/2026, 10:00 UTC, `POUSSER_VSA=1`). **Chaque étape de `rejeu.sh` a passé sous RKE2 en profil `cis`, sans KO au dernier passage de chaque étape, mais pas d'un seul tenant : le seuil n'est pas encore atteint.** Il exige un passage complet de zéro, sans KO. Le passage de zéro s'est arrêté en J7 (réseau), et la fin vient de deux reprises.

| Passage | Heure (UTC) | Résultat | Cause | Suite |
|---|---|---|---|---|
| [1](../08-trust-plane/resultats/rejeu-rke2-premier-passage.log), de zéro | 10:01 | Arrêt avant toute installation | `$vm` développé avant son `local`, `rke2.sh` jamais exécuté | Corrigé, une seule occurrence au balayage |
| [2](../08-trust-plane/resultats/rejeu-rke2-deuxieme-passage.log), étape RKE2 | 10:06 | RKE2 installé, KO de `cilium.sh verifier` | `rke2-runtimeclasses`, déployé par défaut : `HelmChart` et compte `helm-*` lié à `cluster-admin`, oubli de la conversion | Ajouté à `disable:`, absent de la liste documentée, confirmé à l'exécution |
| [3](../08-trust-plane/resultats/rejeu-rke2-troisieme-passage.log), de zéro | 10:28 | J1 à J5, arrêt en J6 | Sans `crun`, l'API refuse avant Kyverno : effet de bord de la correction précédente | RuntimeClass témoin le temps des cas |
| [Reprise à J6](../08-trust-plane/resultats/rejeu-rke2-reprise-j6.log) | 10:33 | Arrêt en J6 | Artefact de la reprise : `zone-build` déjà chargée avant `taches` | Rien à corriger, repartir de zéro |
| [5](../08-trust-plane/resultats/rejeu-rke2-cinquieme-passage.log), de zéro | 10:35 à 11:37 | J1 à J7 (construction), arrêt en J7 (réseau) | `10.42.0.250` tirée au hasard par `tekton-pipelines-webhook` | `HORS_CIDR` choisie libre juste avant l'essai |
| [Reprise à J7 (réseau)](../08-trust-plane/resultats/rejeu-rke2-reprise-j7.log) | 11:38 à 12:33 | Réseau, 8 tests, bascule, arrêt à `helm_cilium` | Comptage figé sous k3s : 6 comptes pour 7, celui de `local-path` étant borné à son espace | Attendu dans `distro.sh` |
| [Reprise à J8 (helm-cilium)](../08-trust-plane/resultats/rejeu-rke2-reprise-j8.log) | 12:34 à 13:08 | Jusqu'à `fuites` et `kube-bench`, 0 KO, 2 042 s | | |

Durée cumulée du passage de zéro et des deux reprises : environ 9 070 s, soit 2 h 31.

### Prédictions confrontées

| # | Résultat | Verdict |
|---|---|---|
| 1 | 0 HelmChart et 0 `kube-proxy`, mais seulement après correction ; `sc-confiance` en 12 Gi et 25 Go ; aucun ajustement des chemins CNI | Non tenue au premier essai, tenue ensuite |
| 2 | `cilium.sh verifier` et `helm_cilium` conformes, aucun compte de service lié à `cluster-admin` | Tenue |
| 3 | Pod Kata privilégié refusé par le défaut `cis`, admis après l'exemption | Tenue |
| 4 | 4a à 4f tenues : Chains signe sous `restricted`, `dns` résout en 65532, `builds` conforme à l'état final, violations tracées pour l'étape seule, pipelines construites après J6, `c1-unsigned` refusé par Kyverno. Aucun refus d'un composant non relu | Tenue |
| 5 | Aucune adaptation de NetworkPolicy, `kubectl top nodes` répond | Tenue |
| 6 | Image `3a7ca1b1`, binaire `e3749c68`, fermeture `74c265e7` | Tenue |
| 7 | Test 6 : Zot, Forgejo, API, externe, 9345 et 2379 refusés à `construire-image`, joints par la contre-épreuve. La limite reste : une autre tâche signée garde cette sortie | Tenue |
| 8 | Tests 1 à 5, 7 et 8, contrôles 6 et 7 conformes | Tenue |
| 9 | 10 témoins lus dans Grafana par l'auditeur, `rke2-server.service` vu (718 lignes) ; dans Loki, seul le témoin positif trouvé. Le passage de `kube-apiserver` par la source des pods n'a pas été vérifié | Tenue en partie |
| 10 | Au repos : `sc-stockage` 8 645 Mo libres, `sc-confiance` 14 136 Mo. Le creux pendant le scan n'a pas été mesuré, le job a réussi | Tenue au repos |
| 11 | Voir ci-dessous | Tenue en partie : 4 contrôles sont réels |
| 12 | Plus de 3 574 s, cinq KO corrigés | Tenue |

**`kube-bench`, indicatif (D5), [journal](resultats/rke2-cis.log)** : server `sc-confiance`, 78 PASS, 5 FAIL ; agent `sc-build`, 18 PASS, 61 FAIL.
- **Sans objet, 56 FAIL sur l'agent** : sections 1, 2 et 3, contrôles du plan de contrôle lancés sur un nœud qui n'en porte pas.
- **Sans objet, `4.3.1` sur les deux** : `kube-proxy` n'existe pas ici.
- **Réels, mêmes 4 contrôles sur les deux, pour la 08c** :
  - `5.1.1` : `cluster-admin` n'est lié qu'au groupe `system:masters`, le défaut. Rien à retirer.
  - `5.1.3` : 10 ClusterRoles à joker, dont `cluster-admin`, `rke2-cloud-controller-manager` et `tekton-triggers-admin`. Non relus un par un.
  - `5.1.5` : 15 comptes `default` sur 19 sans `automountServiceAccountToken: false`, mais aucun pod en cours ne les utilise.
  - `5.1.6` : 27 pods en cours sur 29 sans `automountServiceAccountToken: false` explicite. Non relu pod par pod.

**Exposition de D9, relue sous RKE2** : 7 comptes sur 77 peuvent créer des pods dans `local-path-storage`, les 6 contrôleurs de `kube-system` et le provisionneur. Celui-ci n'a plus de droit sur `kube-system`.

**Écarts anciens, sans lien avec RKE2** : `j5-*` en parité, `nil pointer` du CLI compris, identiques à la référence k3s du 03/11 ; export de 19b, 31 lignes de plus que le compte de Loki, le même écart qu'au rejeu du 03/11. Je n'avais pas relevé les `j5-*` au troisième passage : `parite` ne s'arrête pas dessus.

**Tirage de Cilium** : `USURPEE` et `HORS_CIDR` sont choisies libres par `adresse_libre` (`commun.sh`). `USURPEE` l'est au chargement, avant les scripts de pods qui la développent ; la garde reste. [Essai](resultats/essai-usurpee.log) sur les scripts rendus : `.248` partout quand `.250` et `.249` sont prises, constante gardée hors de l'étape `reseau`. Exécution réelle à venir au passage de zéro.

**Non prouvé** : passage d'un seul tenant ; redémarrage des VM sous RKE2 ; règles 08c, S1, cert-manager, `isBuildArtifact: true`, jamais appliqués.

## Sixième passage, de zéro, arrêté à `J8 (contrôleurs)` (06/11/2026, 15:23 UTC)

Lancé sur accord (« Oui, relance »), 13:28 à 15:21 UTC, [journal](../08-trust-plane/resultats/rejeu-rke2-sixieme-passage.log). J1 à J7, les 8 tests, la bascule et `helm_cilium` passent, 0 KO jusque-là. `adresse_libre` a tourné pour de vrai, sans avoir à écarter d'adresse : `.250` était libre sur les deux nœuds. **Seuil non atteint.**

**Arrêt** : 2 refus de droits au journal du contrôleur de Pipelines, `cannot watch` sur `pipelineruns` et `resolutionrequests` dans `builds`, à 14:09:31 UTC. `kata.sh exemption` a redémarré `rke2-server` ; `kube-apiserver`, pod statique, a démarré à 14:09:30, 1 s avant. L'audit de l'API ne montre pour ce contrôleur que les refus PodSecurity attendus, aucun droit manquant. Le passage précédent n'avait rien eu à cet endroit : c'est une course, pas un défaut constant.

**Correction du contrôle** : sous RKE2, `refus_droits` écarte uniquement les `watch` refusés dans la minute qui suit le démarrage de `kube-apiserver`, et les affiche. Tout autre refus compte. Sous k3s, rien ne change. [Essai](resultats/essai-refus-droits.log) sur les journaux réels : 0 avec les 2 écartés affichés ; témoins sans exclusion et fenêtre décalée : 2.

**Ce que cela affaiblit** : pendant cette minute, un `watch` refusé pour un vrai manque de droits ne serait pas compté. Il le serait au prochain essai, et l'informer ne fonctionnerait pas, ce que les tests suivants verraient.

## Reprise à `J8 (contrôleurs)` et état du seuil (06/11/2026, 16:00 UTC)

Décision du propriétaire : « Reprends à J8 », reprise de 15:25 à 15:59 UTC, 2 021 s, [journal](../08-trust-plane/resultats/rejeu-rke2.log). **0 KO jusqu'à `fuites` et `kube-bench`.** Les 2 `watch` écartés sont affichés au journal, le contrôle compte 0 pour les deux contrôleurs. Contrôles 6 et 7 conformes, VSA repoussée sur accord, aucun secret dans les journaux des VM. `kube-bench` : mêmes chiffres, 78 PASS et 5 FAIL sur le server, 18 et 61 sur l'agent. Écart d'export de 19b : 31 lignes, comme avant.

**Seuil : atteint avec un écart accepté, pas au sens strict.** Le passage de zéro de 13:28 UTC a couvert J1 à `helm_cilium` sans KO, puis s'est arrêté à `J8 (contrôleurs)` ; la reprise a fini sur le même cluster. Durée : 6 780 s puis 2 021 s, soit 2 h 27. Aucune étape n'a été rejouée après correction d'un défaut du cluster : l'arrêt portait sur le contrôle. Un passage d'un seul tenant reste non fait.

**Résultats** : les journaux suivis des briques portent désormais les mesures RKE2. Les versions k3s restent dans l'historique, dernier commit `d357f4d`, rejeu `complet` dans `f3cb8ad`. Les liens de l'ADR 0001 sont épinglés à `d357f4d` ; ceux des README des briques ne le sont pas, ils affichent donc du RKE2 sous un texte k3s.

**Replanifié** : `supply-chain-g7-premiere-suppression`, du 19/11 au 21/11/2026, 16:00 UTC. Zot a redémarré le 06/11 à 15:14:56 UTC et le plus ancien blob de `builds/scan` date du même jour à 15:39 UTC. Les 336 h expirent le 20/11 à 15:39, juste après le balayage du 20/11 ; premier balayage utile attendu le 21/11 vers 15:15 UTC. Calcul, pas une mesure : un redémarrage de Zot le déplacerait.

## Additif du 10/11/2026, 20:38 UTC : `kubectl exec` et le tunnel du superviseur (diagnostic de la brique 06)

**Chemin vers kubelet.** kube-apiserver joint kubelet par un proxy HTTP CONNECT vers le superviseur (`https://127.0.0.1:9345`, sélection `cluster` de `egress-selector-config.yaml`). Le superviseur passe ensuite par la session `remotedialer` de l'agent du nœud visé. Pour son propre nœud, d'après le code de k3s, il joint kubelet en direct.

**Défaut constaté.** Un `kubectl exec` dont l'entrée attend dans la chaîne, parce que le pod lit moins vite qu'elle n'arrive (128 Mio lus à environ 10 Mio/s), ne rend pas la main vers un pod de sc-build, alors que le processus a fini et que tout est reçu. Le même exec vers un pod de sc-confiance passe en 13,4 s.

**Cause située** sur le chemin par la session `remotedialer`. C'est une preuve par différence ; le mécanisme exact n'est pas identifié.

**Contournement** : morceaux de 64 Mio au plus par exec. Tekton n'est pas concerné, car il ne passe pas de données par `exec`.

Détail : [diagnostic de la 06](../06-deb-sbuild/resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 20:41 UTC : `egress-selector-mode: disabled` préparé à sec, NON APPLIQUÉ

**Décision du propriétaire** : « on ne veut pas du proxy avec cilium ». `config/sc-confiance.yaml` reçoit `egress-selector-mode: disabled`.

Le script [`egress-selector.sh`](egress-selector.sh) a trois étapes :
- **`avant`** : vérifie, par sha256, que la configuration en place est celle du dépôt ;
- **`appliquer`** : pose la nouvelle configuration et redémarre rke2-server ;
- **`retour`** : revient à la configuration précédente.

Prérequis vérifiés dans le dépôt : kubelet et Cilium (remplacement de kube-proxy) sur sc-confiance, 10250 ouvert entre nœuds. Prédictions E1 à E5 : [`egress-selector-predictions.md`](resultats/egress-selector-predictions.md). Chaque étape attend un accord nommé.

## Additif du 10/11/2026, 20:44 UTC : `egress-selector-mode: disabled` appliqué

**`egress-selector-mode: disabled` appliqué** (20:43:00 à 20:43:59 UTC, code 0) :
- configuration en place identique, avant la pose, à la version versionnée de `1227858` (`0d327c84…`) ; ancien sélecteur en HTTP CONNECT vers `127.0.0.1:9345` ;
- rke2-server redémarré (retour de la commande à 20:43:43 UTC) ; `/readyz` à 20:43:58 UTC ; trois nœuds Ready ;
- **argument `--egress-selector-config-file` absent** du manifeste de kube-apiserver. Le pod en cours, démarré à 20:43:18 UTC, après le début de la pose, n'a aucun argument de sélecteur.

Kube-apiserver joint désormais kubelet sans le proxy du superviseur ni le tunnel de l'agent. **Non encore mesuré** : l'exec à lecture lente vers sc-build et la connexion directe vers 10250 (E4, E5).

## Additif du 10/11/2026, 20:47 UTC : vérification après le retrait du tunnel

**Vérification après `egress-selector-mode: disabled`** (20:45:02 à 20:47:14 UTC, code 0) :
- **`croise` (a), runc avec lecture lente de 128 Mio vers sc-build : code 0 en 13,3 s, sha256 conforme.** Avant le changement, cet exec bloquait à chaque essai : 6 sur 6 (croise, amont C1 et C2, pile, connexions, tunnel). **Le blocage a disparu**, sur un essai ;
- `croise` (b), Kata avec envoi lent : code 0 en 26,6 s, comme avant ;
- `connexions` : l'exec finit en code 0. **E5 n'est pas mesurée** : le relevé « pendant » tombe à 45 s, alors que l'exec s'est terminé vers 13 s. Aucune connexion de sc-confiance vers sc-build:10250 n'est vue aux trois relevés, ce qui ne prouve rien sur le chemin pendant l'exec.

Cela confirme, par l'effet, que le maillon fautif était sur le chemin par le proxy du superviseur et le tunnel de l'agent RKE2. **Non vérifié** : le chemin direct pendant l'exec (E5, relevé trop tardif), un gros exec sous Kata (512 Mio), et les pipelines Tekton après ce changement. Le découpage en morceaux de 64 Mio de `s3.sh` reste valable, mais n'est plus forcément nécessaire.

## Additif du 10/11/2026, 21:01 UTC : chemin direct observé, Kata à 512 Mio passe

**Vérification complémentaire** (10/11/2026, 20:56:42 à 21:00:36 UTC, accord : « 3, les deux », code 0 à chaque commande) :
- **chemin direct observé (E5)** : pendant chacun des trois exec à lecture lente de 128 Mio vers sc-build, une connexion de sc-confiance vers sc-build:10250, vue des deux côtés, et une seule. Elle est vue à chaque relevé pendant l'exec, à l'incertitude d'horloge près (0,3 s) ; les relevés des 3 s d'avant et des 24 s d'après sont à 0 ;
- **exec à lecture lente vers sc-build : 3 sur 3** en code 0, 13,3 s chacun, sha256 conforme ;
- **Kata, 512 Mio à plein débit (sonde de S3 rejouée telle quelle) : code 0 en 54,8 s, sha256 conforme.** À 18:02 UTC, la même copie ne rendait pas la main en 120 s. runc : 512 Mio en 3,3 s.

Le blocage de S3 venait donc du chemin par le tunnel de l'agent RKE2, pas de Kata, sur un passage à 512 Mio. **Non vérifié** : les pipelines Tekton après ce changement. Le découpage en morceaux de 64 Mio reste dans `s3.sh` ; le retirer serait un changement à part.

Détail et prédictions D1 à D6 : [`egress-selector-predictions.md`](resultats/egress-selector-predictions.md).
