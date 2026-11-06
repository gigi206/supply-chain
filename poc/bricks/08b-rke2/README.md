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
