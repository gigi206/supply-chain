# F2, prefetch de sample-app dans la plateforme : prédictions (03/11/2026, 17:28 UTC, avant exécution)

Protocole : [README](../README.md), sections « Suite sur le laptop », « Décisions D1 à D6 » et « F2, préparation à sec ». Décisions du propriétaire :
- D1 (a), pipeline séparée ;
- **D2 révisée**, proxy DNS de Cilium ;
- **D3 révisée**, `builds/fermetures/**` ;
- D4 (a), image d'outils de la plateforme ;
- npm hors de F2.

Script : [`prefetch.sh`](../prefetch.sh) (`mise run fermetures:f2 -- <étape>`). Rien n'est exécuté avant l'accord du propriétaire, étape par étape.

## Fichiers préparés (versionnés, non appliqués)

- [`Dockerfile.prefetch`](../Dockerfile.prefetch) : image d'outils, sans image de base externe et sans réseau pendant la construction.
- Tâches [`prefetch-gomod`](../../08-trust-plane/politique/taches/prefetch-gomod.yaml) et [`publier-fermeture`](../../08-trust-plane/politique/taches/publier-fermeture.yaml), pipeline [`prefetch-sample-app`](../../08-trust-plane/politique/taches/prefetch-sample-app.yaml).
- [`politique/prefetch-sortie.yaml`](../../08-trust-plane/politique/prefetch-sortie.yaml) : CiliumNetworkPolicy, avec DNS, `toFQDNs` (`proxy.golang.org`, `storage.googleapis.com`) et Forgejo.
- [`stockage/zot.json`](../../08-trust-plane/stockage/zot.json) : politique `builds/fermetures/**`. [`stockage.sh`](../../08-trust-plane/stockage.sh) : compte `poc-fermetures`.
- [`cilium/valeurs.yaml`](../../08-trust-plane/cilium/valeurs.yaml) : `l7Proxy: true`.
- [`politique.sh`](../../08-trust-plane/politique.sh) `declencheurs` : le secret `zot-fermetures` est admis dans `builds`.

## Prédictions par étape

**`image`** (hôte ; téléchargements : tag de Hermeto, roues de PyPI ; écriture dans Zot par `poc-ecriture`)
1. Le tag `0.64.0` désigne le commit `1f37e32d…`. pip télécharge les roues de `requirements.txt` en contrôlant leurs empreintes : 50 roues, une par dépendance (le venv de l'hôte en compte 51 avec Hermeto).
2. La roue de Hermeto est identique sur deux constructions (`SOURCE_DATE_EPOCH`). Prédiction faible : `setuptools-scm` lit le tag dans le clone superficiel, ce qui donne la version `0.64.0`.
3. Go 1.26.10 est conforme à `sum.golang.org` (`ziphash`).
4. Clôture nix : 45 chemins, environ 275 Mo.
5. **Deux constructions sans cache donnent le même digest.** Prédiction moyenne : pip compile les `.pyc` en mode « checked-hash » sous `SOURCE_DATE_EPOCH`, et `rewrite-timestamp` fige les dates des couches. Une différence serait consignée et l'étape échouerait.
6. Essai hors réseau : `hermeto 0.64.0`, `git version 2.51.2`, `go1.26.10`, `Python 3.13.12`.
7. Copie dans `plateforme/outils-prefetch` par digest, relue en lecture anonyme. Taille : environ 650 Mo, prédiction faible.

**`cilium`** (modification du cluster)

8. `helm upgrade` puis redémarrage des agents et de l'opérateur, 3/3 prêts. `enable-l7-proxy=true` et `external-envoy-proxy=false` dans `cilium-config`.
9. **Aucun processus envoy dans les agents** (`onDemandXdsStarter`, aucune politique HTTP). L'état du proxy est `OK`.
10. Le test 6 de la 08, rejoué ensuite, reste conforme (`POLICY_DENIED`, `INVALID_SOURCE_IP`), puisque `l7Proxy` ne touche pas aux politiques L3 et L4.

**`compte`** (Zot modifié et redémarré)

11. `poc-fermetures` :
    - pousse par digest deux fois dans `builds/fermetures/essai` ;
    - est refusé (403) pour un tag, avec le motif de la condition, dans `builds/essai-fermetures` (où `builds/**` ne le liste pas) et pour une suppression.
12. `poc-images` est refusé dans `builds/fermetures/`, puisque le motif le plus long l'emporte et ne le liste pas.
13. `poc-build` (Chains) y écrit un tag. Lecture anonyme. Secret `zot-fermetures` dans `builds`.

**`reseau`** (CiliumNetworkPolicy appliquée)

14. Seule `prefetch-sortie` sélectionne les pods au label.
15. Sonde au label :
    - `proxy.golang.org` joint (HTTP 200) ;
    - `storage.googleapis.com` joint (HTTP 400, sans requête valide, prédiction faible sur le code) ;
    - Forgejo joint ;
    - **`sum.golang.org`, `github.com` et Zot refusés**, par délai dépassé : paquets jetés.
16. Sonde sans label : tout est joint, Zot compris (témoin : aucune politique).
17. Hubble montre les requêtes DNS inspectées et des `DROPPED` (`POLICY_DENIED`) vers les adresses de `github.com` et de `sum.golang.org`.

**`taches`** (bundles dans Zot ; liste revue modifiée à la main, puis revue par le propriétaire)

18. Premier passage avec `SIGNER=1` : signatures versionnées, puis bundles à ajouter à `politique/porte/taches.yml`. Second passage sans `SIGNER` : `OK` dans la liste revue. Bundles reproductibles.

**`prefetch`** (deux PipelineRuns réels dans `builds`)

19. Les deux réussissent. Pod de prefetch sur `sc-build`, `tekton.dev/task=prefetch-gomod`, `TrustedResourcesVerified=True`. Hermeto choisit Go 1.26.10, le seul présent.
20. Fermeture publiée dans `builds/fermetures/sample-app`. **Mêmes fichiers gomod que la fermeture de l'hôte `0ab5a507`** (chi v5.2.3 : `.info`, `.mod`, `.zip`, `.lock`, `list`). Prédiction moyenne : même contenu.
    - Pourraient différer : les tuiles `sumdb` (constat de la 03), présentes ou absentes ; et `.build-config.json`, qui contient des chemins (`/tmp/depot`, et non le chemin de l'hôte).
    - **Le digest diffère donc probablement de `0ab5a507`.**
21. Les deux prefetch du même commit donnent la même fermeture, sauf si des tuiles `sumdb` y entrent (prédiction faible). Toute différence est consignée.
22. Chains signe le PipelineRun, et `.sig` et `.att` sont écrits dans `builds/fermetures/sample-app`.
23. Hubble : flux `FORWARDED` vers les adresses de `proxy.golang.org` et vers Forgejo, aucun `DROPPED`.

**`provenance`**

24. `cosign` (clé de Chains) vérifie la provenance du PipelineRun :
    - sujet : la fermeture ;
    - `buildType` : `slsa-tekton` ;
    - source `git+https://…/workspace/sample-app.git` en `sha1:6391fd43…` ;
    - image d'outils, bundle de `prefetch-gomod` et pipeline dans `resolvedDependencies`.

    Une autre clé est refusée.

## Effets à connaître avant d'accorder

- **Cilium** : `l7Proxy: true` change durablement la configuration du réseau. Les agents redémarrent (quelques secondes de coupure des pods du cluster, dont Zot vu depuis les pods). Le test 6 est rejoué. Retour arrière : `l7Proxy: false`, puis `cilium.sh appliquer`.
- **Zot** : redémarrage (comme en D5 de la 10) et nouveau compte. Les dépôts `builds/fermetures/**` ne sont plus régis par `builds/**`.
- **Horodatage** : le CronJob parcourt `builds/`. Il horodatera les enveloppes des fermetures, ce qui ajoute des bundles dans `horodatage/bundles`.
- **Liste revue** : deux tâches ajoutées à `politique/porte/taches.yml`, à relire avant tout push.
- **La porte et la construction ne changent pas en F2.** `3a7ca1b1` reste admise. D5 et D6 viennent en F3.
- **Dépôts d'essai** laissés dans Zot, qui n'autorise pas la suppression : `builds/fermetures/essai`, `plateforme/outils-prefetch`, `tekton/*/prefetch-*`.

## Additif du 03/11/2026, 17:31 UTC (avant exécution, après relecture)

- **SBOM retiré des referrers.** `publier-fermeture` n'attache plus `bom.json` à la fermeture.
  - Un referrer posé sur un digest que Chains signe n'est mesuré que pour le bundle Sigstore. La brique 10 a montré que `.sig` et `.att` sont alors ignorés.
  - Le retrait est fait avant toute signature de la tâche. L'empreinte du SBOM est journalisée ; sa publication viendra plus tard (07a).
- **Deux arrêts obligatoires dans F2** :
  - après `image`, `PREFETCH_DIGEST` est épinglé dans `prefetch.sh`, puis commité ;
  - `taches` se fait en deux passes. Entre les deux, les deux digests sont ajoutés à la main à `politique/porte/taches.yml`, et **le diff est montré au propriétaire, qui doit l'accepter** avant le second passage.
- **La configuration versionnée de la 08 est déjà modifiée** dans le commit de préparation : `valeurs.yaml`, `zot.json`, `stockage.sh` et `politique.sh`. Tant que F2 n'a pas tourné, le dépôt ne décrit plus le cluster réel, et un rejeu de la 08 appliquerait ces changements. Le commit reste en local jusqu'à l'accord.
- **Exigence « tout dans Grafana »** (19b) :
  - les journaux des pods de `builds` (source J2, donc ceux de `prefetch-gomod` et de `publier-fermeture`) et l'audit de Zot (J6, avec les écritures de `poc-fermetures`) atteignent Loki ;
  - **les refus de sortie du pod de prefetch ne sont visibles que dans Hubble**, dans l'agent. La source J7 (flux Hubble) a été laissée en option par D9 et n'est pas collectée. **C'est un écart à l'exigence d'audit**, consigné ici. Le collecter est une décision séparée de la 19b.

## Résultats de `image` (17:39:23 à 17:41:04 UTC) et de `cilium` (17:41 UTC)

[`f2-image.log`](f2-image.log), [`f2-cilium.log`](f2-cilium.log), [`f2-cilium-envoy.log`](f2-cilium-envoy.log).

**`image`** :
1. **Démentie en partie** : commit `1f37e32d…` conforme, mais **46 roues**, et non 50.
2. **Conforme** : roue de Hermeto identique (`15ca1dc5…`).
3. et 4. **Conformes** : `h1:5VAGHlY8…` égal à `sum.golang.org` ; 45 chemins nix (263 Mo).
5. **Conforme** : **`sha256:68e0ae70…` sur deux constructions sans cache**.
6. **Conforme** : `hermeto 0.64.0`, `git version 2.51.2`, `go1.26.10`, `Python 3.13.12`.
7. **Conforme** : copiée et relue, 6 couches, 207 Mo (198 Mo compressés), sous la fourchette prédite.

Le digest est épinglé dans `prefetch.sh`.

**`cilium`** :
8. **Conforme** : release révision 2, 3/3 agents recréés à 17:41:20 et 17:41:34 UTC, `enable-l7-proxy=true` et `external-envoy-proxy=false`.
9. **Démentie** : **Envoy tourne dans les trois agents** (`cilium-envoy-starter` et `/usr/bin/cilium-envoy`, `-c /var/run/cilium/envoy/bootstrap.pb`), et `cilium-dbg status` affiche « Envoy ».
   - Ma lecture de `pkg/envoy/cell.go`, « démarré à la demande seulement », ne tient pas : Envoy démarre avec l'agent.
   - **cilium/proxy (Envoy) n'est pas évalué au doc 04** (choix de J7 : « ni Envoy (cilium/proxy, non évalué au doc 04) »).
   - **F2 est arrêté** ici, avant `compte`. Décision soumise au propriétaire.
10. Test 6 : non rejoué, F2 étant arrêté.

## Retour à `l7Proxy: false` (18:10:56 UTC ; décision du propriétaire : « Revenir et évaluer ») et évaluation de cilium/proxy

[`f2-cilium-retour.log`](f2-cilium-retour.log) :
- agents recréés de 18:10:57 à 18:11:10 UTC, 3/3 prêts ;
- `enable-l7-proxy=false` ;
- **aucun processus envoy** dans les trois agents.

« Envoy » dans le statut du proxy n'est que le type de proxy, déjà affiché avant. La configuration de Cilium est revenue à celle d'avant F2. Le test 6 n'est pas rejoué : les valeurs sont identiques à celles de J7 et J8.

**Évaluation de cilium/proxy** (lecture seule, 03/11/2026 ; [doc 04](../../../../docs/04-sante-projets.md)) : verdict **« À surveiller (Scorecard < 6) »**, pas « Risqué ».
- Scorecard 4,4, revue de code à 1.
- Aucune release ni tag propre, aucun SECURITY.md propre (politique de cilium/cilium).
- 100 commits en 90 jours : 36 de Renovate, 59 de deux mainteneurs.
- Embarqué dans l'image de l'agent : `cilium-envoy` v1.39.5 en 1.20.4, épinglé par digest dans `images/cilium/Dockerfile` au tag, et couvert par la signature de l'image de l'agent.
- Envoy amont : Scorecard 8,5.
- Plan de sortie : `l7Proxy: false`, avec une sortie par plages d'adresses.

D2 est resoumise au propriétaire.
