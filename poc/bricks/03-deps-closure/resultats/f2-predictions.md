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
