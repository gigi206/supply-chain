# Résultats du banc A1 : Konflux v0.2.2 sur kind (29/10/2026)

Grille : [ADR 0000 §2](../../../../docs/adr/0000-assembler-ou-adopter.md) (figée avant le banc). Protocole et préparation validée : [`../README.md`](../README.md). Banc d'essai : [`poc/sample-app`](../../../sample-app) (Go + interface npm embarquée), construit depuis Forgejo par le chemin natif de Konflux.

## Environnement

| Élément | Détail |
|---|---|
| Hôte | Laptop de l'[infra du PoC](../../../infra/README.md) ; Docker 28.4.0 |
| Cluster | kind 0.33.0, nœud `kindest/node:v1.37.0@sha256:a1ed56cf…` (digest des notes de release), plafonné à **20 Gi** (`docker update`), allocatable du kubelet ramené à 19,3 Gi ; ports publiés sur **127.0.0.1** seulement ; `KUBECONFIG` dédié, `~/.kube/config` inchangé ([`installation.log`](installation.log)) |
| Konflux | **v0.2.2** (commit `be0e6cac`, tag non signé), `install.yaml` `68fbb841…` appliqué depuis le disque, opérateur épinglé par digest `36493a95…` ; Tekton operator v0.81.1 (Pipelines v1.15.0, Chains v0.29.1, PaC v0.50.0, Triggers v0.37.0, Results v0.20.0) |
| Vérification des entrées | [`preparation.log`](preparation.log) : sha256 des manifestes, signatures de cert-manager (clé publiée) et trust-manager (keyless) vérifiées ; **non vérifiables** et épinglés par digest : opérateur Konflux, `task-runner`, `registry:2` ; images UBI de sample-app : signature GPG Red Hat vérifiée ([`onboarding.log`](onboarding.log)) |
| Forge | Forgejo 15.0.11 (binaire GPG vérifié) hors cluster, publié dans le cluster en `https://forgejo.banc-a1.svc.cluster.local` (Service sans sélecteur vers la passerelle `kind`, certificat de la CA de Konflux) ; voir [`forgejo.sh`](../forgejo.sh) |
| Scripts | [`preparer.sh`](../preparer.sh), [`deployer.sh`](../deployer.sh), [`forgejo.sh`](../forgejo.sh), [`onboarder.sh`](../onboarder.sh), [`parametrer.sh`](../parametrer.sh), [`verifier.sh`](../verifier.sh), [`tests-negatifs.sh`](../tests-negatifs.sh), [`t6-hermetique.sh`](../t6-hermetique.sh), [`preuves.sh`](../preuves.sh), [`etat.sh`](../etat.sh) ; tâches `mise run konflux:*` |

## Chronomètre ([`chrono.tsv`](chrono.tsv))

| Étape | Depuis le début | Seuil |
|---|---|---|
| Cluster kind prêt, plafond et ports contrôlés | 0 h 00 min 40 s | |
| **Konflux Ready** (`deploy-local.sh`) | **0 h 06 min 53 s** | installation ≤ 1 j : **atteint** |
| Premier PipelineRun lancé depuis Forgejo | 0 h 18 min 10 s | |
| **Premier build signé** (provenance Chains vérifiée, Conforma exécuté) | **1 h 23 min 36 s** | ≤ 2 j : **atteint** |

L'écart entre l'installation et le premier build signé tient presque entièrement aux **écarts d'intégration** ci-dessous, tous corrigés par configuration, sans fork.

## Écarts d'intégration constatés ([`preuves.log`](preuves.log))

Tous rejoués par [`onboarder.sh`](../onboarder.sh) et [`parametrer.sh`](../parametrer.sh).

1. **Forgejo exige le HTTPS sans port** : le build-service refuse les dépôts en `http:`, et cherche les identifiants par un label qui porte l'hôte de l'URL, port compris (`172.19.0.1:3000` n'est pas une valeur de label valide). D'où le Service sans sélecteur sur le port 443 et le certificat émis par la CA de Konflux.
2. **NodePort de PaC faux** : le Service livré par Konflux vise le port 8080 (serveur de sondes), alors que PaC v0.50.0 écoute les événements sur **8082**, seul port admis par sa NetworkPolicy. Les webhooks venant de l'extérieur du cluster n'arrivaient jamais. Corrigé (`targetPort: 8082`).
3. **CA de Konflux absente du contrôleur et du watcher PaC** : Konflux monte `trusted-ca` pour Chains et les résolveurs, pas pour PaC ; l'API Forgejo en HTTPS échoue et le secret git du PipelineRun n'est jamais créé (pod bloqué). L'opérateur Tekton **ne propage pas** les `options` du TektonConfig vers son objet PaC sur Kubernetes : correctif posé sur les deux.
4. **Webhook vers l'URL interne** : sans `webhookURLs` dans le CR Konflux avant la création du Component, le build-service crée un webhook vers `pipelines-as-code-controller.tekton-pipelines.svc.cluster.local`, injoignable depuis Forgejo.
5. **Registre interne** : Zot authentifié, certificat valable pour `registry-service.kind-registry` (pas la forme `.svc.cluster.local`) ; le secret de push doit être relié au compte de build à la main (étape documentée « Build pipeline push secret »), l'image-controller (Quay) n'étant pas déployé.

## Sorties vers des tiers ([`preuves.log`](preuves.log))

| Service | Appelé par | Donnée envoyée | Constat |
|---|---|---|---|
| **`exhort.stage.devshift.net`** (Red Hat, *staging*) | tâche `tpa-scan`, **exigée** par la politique Conforma `default` (`required_tasks.yml`) | **SBOM complet de l'image** (POST) | Le SBOM de sample-app est parti **une fois** (build `2cfmd`), avant que le constat soit fait. Ensuite, NetworkPolicy `tpa-scan-sans-sortie` ([`k8s/`](../k8s/netpol-tpa-scan-sans-sortie.yaml)) : la tâche échoue avant l'envoi. Les CVE bloquantes de Conforma viennent de ce rapport |
| `catalog.redhat.com` | `deprecated-image-check` (exigée) | noms des images de base | Noms publics ; échoue sans réseau |
| `registry.npmjs.org`, proxy Go | prefetch Hermeto | requêtes de paquets | Attendu (le prefetch est en ligne) |
| `github.com`, `quay.io` | Conforma | téléchargement des données et du bundle de politique | Pas d'envoi ; empêche l'évaluation hors réseau sans miroir |

## Premier build signé (PipelineRun `2cfmd`, [`verification-2cfmd.log`](verification-2cfmd.log))

- Pipeline `docker-build-oci-ta-min` généré par le build-service (PR de configuration), **11/11 tâches** ; buildah en mode **hermétique**, prefetch Hermeto 0.61.0 gomod + npm, `source-date-epoch=0`, `rewrite-timestamp=true` (paramètres natifs posés dans la PR) ; build 4 min 46 s.
- Image `sha256:3aa51998…` ; **signature cosign et attestation vérifiées** avec la clé de Chains (cosign du nixpkgs, depuis l'hôte).
- **Provenance SLSA v0.2** (`https://slsa.dev/provenance/v0.2`, builder `https://tekton.dev/chains/v2`), 27 matériaux, `hermetic=true` et `source-date-epoch=0` inscrits ([`provenance-3aa51998d84c.json`](provenance-3aa51998d84c.json)) ; stockage en tags `.sig`/`.att` ; **transparence désactivée, aucun horodatage**.
- **Conforma** (politique `default` de Konflux, exécutée avec l'`ec` 0.10.42 du PoC et non par l'IntegrationTestScenario natif) : **refus, 12 violations** : 10 CVE « high » des paquets UBI (`cve_blockers`, données du rapport `tpa-scan`), `base_image_info_found`, et `source_code_reference_provided` (attendu hors Snapshot). Sans rapport `tpa-scan`, la règle devient `cve_results_found` (vu sur T7b) : la porte dépend du service externe.

## Tests négatifs (A-2, [`tests-negatifs.log`](tests-negatifs.log))

Règle validée : chaque test du doc 01 est transposé ; un contrôle absent compte « non bloqué ». Les tenants ne peuvent lancer un build que par `.tekton/` dans git (le RBAC leur refuse la création de pods, TaskRuns et PipelineRuns) : le test passe donc par une **PR « hostile »** ([`tests-negatifs.yaml`](../tests-negatifs/tests-negatifs.yaml)).

| # | Test | Résultat | Bloqué ? |
|---|---|---|---|
| 1 | Lire la clé de signature de Chains depuis une tâche de build | API : **403**. Mais une étape privilégiée de la PR lit `cosign.key` sur le nœud : **sha256 identique** à celui du secret `tekton-pipelines/signing-secrets`. Le secret est monté en entier (`cosign.key`, `cosign.password`, `cosign.pub`) dans le pod de Chains, sur le même nœud ([`preuves.log`](preuves.log) §2b) ; la lecture effective du mot de passe n'a pas été mesurée | **Non** |
| 2 | `taskSpec` inline | Créé et exécuté par PaC depuis `.tekton/` ; aucun refus à l'admission (les PipelineRuns de Konflux embarquent eux-mêmes un `pipelineSpec`) | **Non** |
| 3 | Modifier le `status` d'un TaskRun terminé | **403** avec le jeton du build ; RBAC refusé à l'utilisateur du tenant et au compte de build. Risque non testé : sur ce nœud unique, T4 donne accès à `/etc/kubernetes/admin.conf` | **Oui** |
| 4 | Pod privilégié ou `hostPath` dans le tenant | Étape **privilégiée, uid 0, `hostPath: /`** acceptée ; aucun label Pod Security sur l'espace du tenant | **Non** |
| 5 | Webhook non signé ou rejoué | Non signé et signature fausse : **refusés** par PaC (le seuil pratique « webhook authentifié » est atteint). **Rejeu à l'identique d'une livraison valide : accepté**, un nouveau PipelineRun est lancé (aucun anti-rejeu dans PaC v0.50.0) | **Non** |
| 6 | Sortie réseau en build hermétique | PR dont le Containerfile ouvre une connexion TCP vers la passerelle pendant un build `hermetic=true` : **`Network is unreachable`**, build en échec ([`t6-hermetique.log`](t6-hermetique.log)). Constat séparé, hors test : une étape de pipeline (hors buildah) atteint quay.io (HTTP 200), et l'hermétisme est un paramètre laissé au contributeur, que la politique `default` ne vérifie pas (`hermetic_task` exclu) | **Oui** |
| 7 | Artefact non signé, ou portant les seules attestations, admis ou publié | Copie sans signature ni attestation, puis copie avec l'attestation seule : **refusées** par cosign et Conforma (stockage en tags : la signature `.sig` est exigée) | **Oui** |
| 8 | Jeton d'horodatage absent ou falsifié | Aucun horodatage RFC 3161 dans Chains, transparence désactivée : contrôle absent | **Non** |

**Bilan : 3/8 bloqués** (T3, T6, T7).

## Reproductibilité (A-3, [`reproductibilite.log`](reproductibilite.log))

| Artefact | Résultat |
|---|---|
| **Image** sample-app | **Identique** (`sha256:3aa51998…`) sur deux builds du même commit, dans des pods éphémères (stockage buildah en `emptyDir`), à 20 min d'écart |
| **rpm rocky-9** | **Non démontré** : Konflux v0.2.2 n'embarque aucun pipeline rpm ; le pipeline amont `konflux-ci/rpmbuild-pipeline` (mock) exige le multi-platform-controller (absent de l'opérateur, 0 occurrence dans `install.yaml`) et des VM de build |
| **deb debian-13** | **Non démontré** : aucun pipeline ni dépôt deb chez konflux-ci. Un pipeline sbuild dans `.tekton/` serait possible sans forker le cœur, mais exigerait d'enregistrer ses tâches comme tâches de confiance ; rien n'a été construit |

## Poids opérationnel (A-5)

| Mesure | Valeur |
|---|---|
| Composants (Deployments, StatefulSets, DaemonSets hors `kube-system` et `local-path-storage`) | **30** ([`etat-installation/composants.txt`](etat-installation/composants.txt)) ; 40 pods |
| RAM du nœud après installation | 2,47 Gi |
| **RAM au repos** (`docker stats` du nœud, 30 min après le dernier build) | **4,14 Gi** sur le plafond de 20 Gi ; CPU 16 % d'un cœur ([`etat-repos-30min/memoire.txt`](etat-repos-30min/memoire.txt)) |
| Images | 42 références après l'installation ; build-service, integration-service, release-service et PaC cités **par tag** (`imageID` archivés). Après les builds : la tâche `clamav-scan`, tâche de confiance, tire `quay.io/konflux-ci/clamav-db:latest` **par tag flottant** |
| Procédure de mise à jour | Opérateur (nouvelle release `install.yaml`) ; **non mesurée** ici |

## Santé (A-6, [`preuves.log`](preuves.log) §4)

Doc 04 : « À surveiller, hors chemin critique » ; version 0.x. Sur 90 jours, 4 dépôts (`konflux-ci`, `build-service`, `integration-service`, `release-service`) : 240 commits humains, de 8 à 19 auteurs par dépôt ; **adresses `redhat.com` majoritaires** (187 sur 240). Parmi les autres auteurs, ceux qui déclarent un employeur sur GitHub déclarent Red Hat, sauf 2 commits (OpenGeeks-Community, une école) ; 5 commits viennent d'auteurs sans employeur déclaré. Éditeur unique de fait, mais pas de bus factor de 1.

## Effort pour combler les manques (A-4, estimation)

Estimation en semaines-personnes (pw), poste par poste, à partir des constats ci-dessus ; fourchette basse et haute. Ce n'est pas une mesure : c'est l'estimation documentée qu'exige le critère.

| Poste | Constat qui le motive | pw |
|---|---|---|
| **Propres à Konflux** | | |
| Durcissement du tenant : Pod Security ou Kyverno (privilégié, `hostPath`), refus des `taskSpec` inline compatible avec les `pipelineSpec` de Konflux, NetworkPolicy de sortie des pods de build, nœuds de build séparés de Chains | T1, T2, T4, T6 | 1,5 – 2,5 |
| Clé de Chains hors du cluster de build (KMS OpenBao) | T1 | 0,5 – 1 |
| Anti-rejeu des webhooks devant PaC | T5 | 0,5 – 1 |
| Provenance SLSA v1 (`slsa/v2alpha4`) et règles Conforma correspondantes | B9 | 0,5 – 1 |
| Sortie du SaaS : Trustify/exhort auto-hébergé ou politique propre sans `tpa-scan`, catalogue d'images interne | `tpa-scan`, `deprecated-image-check` | 1 – 2 |
| Air-gap : miroir des images de Konflux, des bundles de tâches et des données de politique | sorties vers des tiers | 1 – 2 |
| Maintien des écarts d'intégration à chaque montée de version de l'opérateur | écarts 1 à 5 | 0,5 – 1 |
| rpm : multi-platform-controller, pool de VM, `rpmbuild-pipeline` reproductible sur rocky-9 | A-3 | 2 – 3 |
| deb : pipeline sbuild dans `.tekton/`, tâches de confiance, signature OpenPGP | A-3 | 2 – 3 |
| *Sous-total* | | *9,5 – 16,5* |
| **Communs avec l'assemblage** (non couverts par Konflux) | | |
| Replay dans un domaine indépendant et VSA (B1, brique 10) | | 2 – 3 |
| Horodatage RFC 3161 et vérification (B9, T8) | | 1 – 1,5 |
| Synchronisation git et branches custom (B7, brique 01) | | 0,5 – 1 |
| Licences (B11, briques 13a et 13b) | | 1,5 – 2 |
| Porte MAL, KEV et VEX, score (B6, briques 07a et 07b) | | 1 – 1,5 |
| Index, referrers et archive WORM (B2, briques 02 et 15) | | 1 – 1,5 |
| Observabilité : 5 alertes et KPI (B14, briques 19 et 20) | | 1 – 1,5 |
| *Sous-total* | | *8 – 12* |
| **Total** | | **17,5 – 28,5 ; valeur centrale ≈ 23** |

## Notation (grille A)

Règle d'interpolation : **linéaire entre les ancres 0 et 5 de la grille, arrondie à l'entier le plus proche, la moitié vers le haut** (A-1, A-2, A-3, A-4, A-5) ; pour A-5, la dimension la plus défavorable l'emporte (« ou » de l'ancre 0).

| Critère | Poids | Note | Justification |
|---|---|---|---|
| A-1 couverture de B1 à B14 sans développement | 25 | **0** | **1 besoin couvert nativement** (B12 : Kubernetes), donc ≤ 4. Partiels, non comptés : B2 (image, SBOM et provenance au registre, en tags), B3 (SBOM SPDX attaché ; CycloneDX en option), B4 (fermeture Hermeto stockée en artefact OCI par digest ; restauration et déduplication non mesurées), B5 (build hermétique, prefetch en ligne, pas de replay), B6 (porte Conforma sur CVE, sans MAL, KEV ni VEX), B9 (provenance signée par Chains, mais SLSA v0.2 et sans TSA). Non couverts : B1, B7, B8, B10, B11, B13, B14 |
| A-2 garanties L3 démontrées | 20 | **0** | **3/8 bloqués** (T3, T6, T7), donc ≤ 3/8 |
| A-3 reproductibilité (rpm, deb, image) | 15 | **2** | Image identique sur 2 builds ; rpm et deb non démontrés : 1/3, soit 1,7 |
| A-4 effort pour combler les manques | 15 | **1** | ≈ 23 pw (17,5 à 28,5) : 0,5, arrondi à 1. À 25 pw ou plus, la note tomberait à 0 (−3 points) |
| A-5 poids opérationnel | 10 | **2** | RAM au repos 4,14 Gi (≤ 8 Gi : 5) ; **30 composants** (entre 10 et 40 : 1,7) ; la dimension la plus défavorable l'emporte. Procédure de mise à jour non mesurée |
| A-6 santé et pérennité | 10 | **1** | À surveiller (doc 04), 0.x, éditeur unique de fait (Red Hat) ; pas de bus factor de 1 |
| A-7 maîtrise et dépendance | 5 | **2** | Cadre imposé : l'opérateur gère Tekton et PaC (options non propagées), politique « Red Hat » (tâches exigées, registres UBI, service `tpa-scan`). Les composants sont standards (Tekton, Chains, PaC, Conforma, Hermeto) : on peut en sortir vers l'assemblage, brique par brique |
| **Total** | 100 | | **(0×25 + 0×20 + 2×15 + 1×15 + 2×10 + 1×10 + 2×5) / 5 = 17/100** |

Référence « assemblage » : **57/100** (§2.3, papier). Règle de décision A : adoption à **67** ou plus. **Konflux n'est pas adopté**, et l'écart (40 points) ne dépend d'aucune des notes discutables : même avec A-4 à 0 ou A-3 à 1, le score reste sous 20.

## Critères éliminatoires (§1)

| Critère | Résultat |
|---|---|
| 1. Provenance non falsifiable | **Non démontré en configuration par défaut** : une PR lit la clé de signature de Chains depuis une étape de build (T1 + T4, empreinte identique). Contexte : nœud unique où cohabitent les builds et Chains ; sur OpenShift, cible première de Konflux, les SCC bloqueraient probablement T4 (non mesuré ici) |
| 2. Fonctionnement offline | **Partiel** : build sans sortie réseau démontré (T6), mais chaque build refait le prefetch en ligne ; aucun rebuild depuis l'archive n'a été mesuré. Évaluation : **non démontrée** (données et bundle de politique sur github.com et quay.io, rapport CVE du service `tpa-scan`) |
| 3. Licence et auto-hébergement sans SaaS obligatoire | Apache-2.0. **Non démontré** : la politique `default` exige `tpa-scan`, qui envoie le SBOM à un service Red Hat ; il faudrait auto-héberger exhort/Trustify |
| 4. Santé (pas « Risqué ») | Démontré : À surveiller |
| 5. amd64 et distros cibles | **Non démontré** pour rpm et deb |

**Proposition** au propriétaire (décideur de l'ADR) : constater l'élimination au titre du critère 1, en configuration par défaut. La décision tient sans elle : 17 contre 57.

## Ce que l'assemblage reprend de Konflux

- **Artefacts de confiance** (ADR 0036 de Konflux) : sources et fermeture passées entre tâches en artefacts OCI par digest, au lieu de PVC.
- **PR de configuration** générée par le build-service : modèle d'onboarding d'un composant, avec les PipelineRuns dans `.tekton/`.
- **Image reproductible** avec `source-date-epoch` et `rewrite-timestamp` de buildah, en build hermétique : confirme la brique 04.
- **Règles Conforma** `required_tasks` et `trusted_task`, adaptées à nos tâches et sans dépendance à un service externe.
- **À éviter** :
  - clé de Chains en secret dans le cluster qui exécute les builds ;
  - tenants sans Pod Security ;
  - tâches de confiance tirées par tag flottant (`clamav-db:latest`) ;
  - envoi de SBOM à un tiers par une tâche exigée ;
  - **environnement Go de `hermeto generate-env` utilisé tel quel** : Konflux pose `GOMODCACHE` sur la fermeture prefetchée, `GOPROXY=file://${GOMODCACHE}/cache/download` et `GOSUMDB=off` ([`preuves.log`](preuves.log) §2c). C'est le schéma que le [banc B](../../nix/resultats/README.md) a pris en défaut (un zip Go altéré passe) ; la règle retenue sert la fermeture en `GOPROXY` en lecture seule, avec un `GOMODCACHE` vierge.
