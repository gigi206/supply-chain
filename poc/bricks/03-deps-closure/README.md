# Brique 03 : fermeture des dépendances en OCI (partie locale)

Seuil (README, brique 03) : fermeture Hermeto (gomod, npm) restaurable par digest ; **déduplication fichier par fichier ≥ 50 % entre deux builds proches**.

## Principe

[`closure.sh`](closure.sh) range la sortie de Hermeto dans un registre OCI (Zot), **un fichier par couche** :

- `closure.sh push <répertoire> <dépôt:tag>` pousse la fermeture et imprime `<dépôt>@sha256:…`. Le manifest a pour type `application/vnd.supply-chain.deps-closure.v1`. Le SBOM Hermeto (`bom.json`) est attaché en **referrer** (`application/vnd.cyclonedx+json`) plutôt qu'en couche.
- `closure.sh pull <dépôt@sha256:…> <répertoire>` restaure la fermeture. Il **refuse une référence par tag**. oras vérifie le digest du manifest puis celui de chaque couche.
- **Manifest déterministe** : fichiers triés, date fixée par `SOURCE_DATE_EPOCH` (0 par défaut). La même fermeture donne donc le même digest, et c'est ce digest qui entre dans `resolvedDependencies`.

Deux fermetures qui partagent un fichier (zip de module Go, archive npm) partagent le blob, que le registre ne stocke qu'une fois.

## Résultats ([`bench.sh`](bench.sh), journal : [`resultats/bench.log`](resultats/bench.log))

Banc : **oras v1.3.5 puis v1.3.6**, deux versions proches d'un vrai projet Go (23 modules, une dépendance change : `oras-go` v2.6.4 → v2.7.0). Puis `poc/sample-app` (gomod + npm).

| Mesure | Résultat |
|---|---|
| Fermeture oras v1.3.6 | 155 fichiers, 6,4 Mo |
| **Couches partagées avec v1.3.5** | **149 / 155, 92,9 % des octets** (seuil ≥ 50 %). Nouveautés : `oras-go` v2.7.0 et deux tuiles `sumdb` |
| **Croissance du registre** (Zot, `dedupe: true`) | +7,65 Mo pour v1.3.5, puis **+0,68 Mo** pour v1.3.6 |
| Même fermeture repoussée | Même digest de manifest |
| Restauration par digest | Arbre identique (155 fichiers) |
| **Build hors réseau depuis la fermeture restaurée** | oras : binaire **identique** à celui construit depuis la fermeture d'origine (`cc397d5e…`) |
| sample-app (gomod + npm) poussée, supprimée, restaurée | Binaire et interface **identiques** avant et après restauration |
| Pull par tag | **Refusé** |
| Blob altéré dans le stockage du registre | **Refusé** (« mismatched digest ») |

**Rejeu sur le laptop (29/10/2026)** ([`resultats/bench-laptop.log`](resultats/bench-laptop.log)) : **binaires identiques au cloud**, sample-app `e3749c68…` (Go 1.26.10), oras `cc397d5e…` et `web/dist`. Déduplication **92,9 %**, comme dans le cloud ; négatifs refusés. Le digest de la fermeture change à chaque prefetch (`2cab9804…` dans le cloud, puis `625d0f7c…` et `123a2c86…` sur le laptop, à 40 min d'intervalle), comme prévu : les tuiles `sumdb` dépendent du moment du prefetch.

## Constats

- **Chemins canoniques obligatoires.** Hermeto inscrit des chemins absolus dans `.build-config.json` et dans le lockfile npm réécrit par `inject-files`. La fermeture doit donc être restaurée **au même chemin** qu'au prefetch. Les pods de build monteront sources et fermeture à des chemins fixes (par exemple `/workspace/source` et `/workspace/deps`), et le replay fera de même.
- **La toolchain fait partie des entrées.** sample-app construite avec Go 1.26.10 (`e3749c68…`) ne donne pas le même binaire qu'avec Go 1.24.7 au banc B (`99ddc97c…`). Il faut donc archiver la toolchain (image de build par digest) et l'inscrire dans la provenance.
- **`GOTOOLCHAIN=auto` télécharge une toolchain en silence** quand `go.mod` exige une version plus récente (ici, oras exige Go ≥ 1.26.7). Il faut donc `GOTOOLCHAIN=local` dans les builds, ce que fait déjà `bench.sh`.
- **Tuiles `sumdb`** : Hermeto met en cache des tuiles du journal de sommes de contrôle de Go, qui changent selon la date du prefetch. Le bruit est négligeable (2 petits fichiers), mais deux prefetch du même code à des dates différentes ne donnent pas exactement la même fermeture. **Le digest de la fermeture identifie un prefetch, pas un code source** : c'est le prefetch archivé qui sert au replay.
- Le **rejet d'un blob altéré** repose sur la vérification d'oras au `pull`. La tâche de build doit s'arrêter sur cette erreur et restaurer dans un répertoire vierge.

## Reproduction

```bash
HERMETO=hermeto ORAS=oras GO=go REG=localhost:5000 WORKDIR=/tmp/b03 \
  ZOT_DATA=/var/lib/zot ./bench.sh
```

Prérequis : un Zot local ([`zot-config.json`](zot-config.json), `dedupe: true`) ; Go ≥ 1.26.7, Node/npm, git, unzip et unshare. Le réseau ne sert qu'au téléchargement des sources d'oras et aux prefetch Hermeto.

## Reste à faire sur le laptop (infra du PoC)

- Tâches Tekton prefetch et build, avec la fermeture montée en lecture seule à un chemin fixe et son digest dans `resolvedDependencies` (brique 08).
- Mesure sur **Traefik** (gomod + yarn berry) : taille, nombre de couches, partage entre deux tags proches ; tests d'altération pour **yarn berry**.
- Dédoublonnage **entre dépôts** du registre (plusieurs projets partageant des modules) et politique de rétention (briques 15 et 12).

## Suite sur le laptop : protocole proposé (03/11/2026, 16:12 UTC ; rien exécuté)

Origine : choix du propriétaire du 03/11/2026, « Fermetures et images » (briques 03 et 04). Rien n'est installé, appliqué au cluster ni écrit dans Zot avant son accord sur ce protocole, puis sur chaque jalon.

### Ce qui est déjà fait, tranché autrement, ou reste

Les lignes « Fermetures » et « Images » de la doc 03 dataient d'avant la J7 de la 08, qui en a fait l'essentiel.

| Point | État | Référence |
|---|---|---|
| BuildKit en pod | **Fait** (08, J7) : BuildKit v0.34.1 en root dans un pod Kata privilégié (voie A), image `3a7ca1b1` retrouvée | [`construction-construire.log`](../08-trust-plane/resultats/construction-construire.log), [`buildkit-sample_app.log`](../08-trust-plane/resultats/buildkit-sample_app.log) |
| Rootless avec seccomp et AppArmor | **Tranché autrement** : rootless mesuré impossible sous Kata 4.3.1 (`newuidmap` sans capacités de fichier dans l'invité), voie A retenue par le propriétaire le 30/10/2026, voie B (`--xattr`) non poursuivie ; pas de seccomp dans l'invité (constat de J7) | [README de la 08](../08-trust-plane/README.md), section « Jalon J7 » |
| Push dans une tâche séparée | **Fait** : `publier-image` (pod runc restreint, compte `poc-images`, création par digest seulement) | [`construction-compte.log`](../08-trust-plane/resultats/construction-compte.log) |
| NetworkPolicy sans sortie | **Fait** : `construction-sans-sortie` sur les pods de `construire-image` ; test 6 de J8 sous Cilium | [`preuves-test6.log`](../08-trust-plane/resultats/preuves-test6.log) |
| Digest de la fermeture dans `resolvedDependencies` | **Fait** : fermeture, `web/dist` et image de build déclarées par `preparer-entrees` | [`construction-provenance.log`](../08-trust-plane/resultats/construction-provenance.log) |
| Fermeture en lecture seule | **En partie** : montée en lecture seule dans l'étape `RUN` (bind de BuildKit, [`Dockerfile`](../04-hermetic-repro/Dockerfile)), mais restaurée dans le workspace `sortie`, inscriptible, que l'étape privilégiée de `construire-image` partage avec `image.tar` (aucun `readOnly` dans [`construire-image.yaml`](../08-trust-plane/politique/taches/construire-image.yaml)) | D5 ci-dessous |
| Prefetch dans Tekton | **Reste** : la fermeture de sample-app est préfetchée sur l'hôte (sortie de cette brique), poussée par `poc-ecriture` et épinglée par digest dans la pipeline signée | [`construction-entrees.log`](../08-trust-plane/resultats/construction-entrees.log) |
| Chemins fixes | **Reste pour yarn et npm** : sans objet pour gomod tel que monté (`GOPROXY=file://`, image identique depuis un autre chemin) ; `web/dist` est construit hors de la chaîne | F1 |
| Traefik (gomod et yarn berry), altération yarn | **Reste** | F1 |
| Interface de Traefik construite dans l'image de build (Node) | **Hors périmètre proposé** : demande Node dans l'image de build (2c, brique 11) | — |
| Entrées de l'image de build archivées par digest | **Hors périmètre proposé** : brique 11 | — |

### Faits relevés pour ce protocole (lecture seule, 03/11/2026, 16:00 à 16:12 UTC)

- **Traefik** : dernière release stable `v3.7.17` (30/10/2026), `v3.7.16` le 20/10/2026.
  - L'interface (`webui/`) déclare `"packageManager": "yarn@4.18.0+sha512.fcb8716f…"`, sans binaire dans `.yarn/releases`. yarn passe donc par corepack.
  - `.yarnrc.yml` : `nodeLinker: node-modules`, `enableScripts: false`. `.nvmrc` : Node `24.21.0`. Notre `mise.toml` épingle Node `22.22.0`.
- **Hermeto 0.64.0** est toujours la dernière release (27/10/2026).
  - Sa documentation au tag ([`docs/yarn.md`](https://github.com/hermetoproject/hermeto/blob/0.64.0/docs/yarn.md)) annonce yarn 1, 3 et 4, tous les protocoles sauf `exec`, et les dépendances git en mode `permissive` seulement.
  - Les plugins non officiels sont désactivés. Le prefetch appelle en interne `yarn install --mode=skip-build` : **il lui faut un binaire yarn**, que le venv de `mise run outils:hermeto` ne contient pas.
- **Images de Hermeto 0.64.0** :
  - `quay.io/konflux-ci/hermeto@sha256:3c7a8622…` porte les tags `.sig`, `.att` et `.sbom` de son digest. La clé ou l'identité qui permet de les vérifier n'est pas établie.
  - `ghcr.io/hermetoproject/hermeto@sha256:b941a525…` n'a aucun tag de signature ni aucun referrer listé par `oras discover`.
- **Sortie réseau des pods de `builds`**, déduite des fichiers versionnés et non mesurée : la seule NetworkPolicy de `builds` sélectionne les pods de `construire-image`. Ceux de `preparer-entrees` et de `publier-image` n'ont aucune politique, donc aucune restriction de sortie. Le réseau libvirt `supply-chain-poc` est en NAT : les VM sortent sur Internet.

### Jalons proposés (chacun soumis à accord)

| # | Contenu | Où | Estimation |
|---|---|---|---|
| F1 | **Traefik sur l'hôte**, comme le banc de cette brique : prefetch gomod et yarn 4.18.0 de `v3.7.16` puis `v3.7.17` dans un Zot éphémère ; taille, couches, partage entre les deux tags ; restauration par digest **à un autre chemin** puis au même chemin (`yarn install --immutable` hors réseau, `go build` hors réseau) ; altérations : zip yarn de la fermeture, archive dans le registre, `yarn.lock` | hôte, `~/.cache/supply-chain-poc/03` | 0,25 pw |
| F2 | **Prefetch de sample-app dans Tekton** (gomod et npm) selon D1 à D4 ; fermeture poussée par une tâche séparée ; deux prefetch du même commit : même arbre hors tuiles `sumdb` | cluster | 0,5 pw |
| F3 | **Bascule de la construction** sur la fermeture produite par la plateforme (et D5) ; image comparée à `3a7ca1b1` ; provenance (fermeture par digest, provenance du prefetch retrouvée) ; tests négatifs : fermeture absente, altérée, ou poussée hors de la plateforme | cluster | 0,25 pw |

Total : **1 pw**. Décision avec le propriétaire à **2 pw**. Le temps passé avant ce protocole sur les parties locales des briques 03 et 04 (estimées à 1 et 1,5 pw au [README](../../../README.md)) n'a pas été relevé.

### Décisions soumises au propriétaire

- **D1. Place du prefetch.**
  - (a) **Pipeline de prefetch séparée**, recommandé. Elle pousse la fermeture et Chains signe sa provenance. La pipeline de construction reste épinglée sur le digest de la fermeture, mis à jour par une nouvelle signature de la pipeline, et la construction garde ses entrées revues et sans sortie réseau. C'est le prefetch archivé qui sert au replay (constat des tuiles `sumdb`).
  - (b) **Tâche dans la pipeline `sample-app`**, dont le digest passe en résultat. La provenance du PipelineRun couvre le prefetch, mais la fermeture n'est plus revue, et le modèle de confiance de la porte change : une fermeture épinglée dans une pipeline signée devient une fermeture produite à chaque build.
- **D2. Sortie du pod de prefetch.**
  - (a) **`toFQDNs` de Cilium**, recommandé : DNS, `proxy.golang.org`, `sum.golang.org` et `registry.npmjs.org` seulement. Les noms exacts seront relevés pendant F1 (trace des connexions de Hermeto).
  - (b) Sortie vers Internet hors des plages privées.
  - Dans les deux cas : aucune entrée, ni Zot ni Forgejo en écriture, et des témoins refusés (autre nom, adresse du cluster).
- **D3. Écriture de la fermeture.** Aucun secret dans le pod de prefetch (doc 04 : « prefetch isolé sans secrets »). La fermeture passe par le workspace jusqu'à une tâche `publier-fermeture` (pod runc restreint).
  - (a) **Nouveau compte Zot `poc-fermetures`**, recommandé : création par digest seulement, dans `entrees/**`, sous la même condition CEL que `poc-images`.
  - (b) Étendre `poc-images` à `entrees/**`.
  - Dans les deux cas, Zot est modifié et redémarré : accord à part.
- **D4. Image d'outils du prefetch.**
  - (a) **Image construite par la plateforme**, recommandé, comme l'image de build de la 04 : venv de Hermeto 0.64.0 installé par hash, Python 3.13, Go 1.26.10 de la 04 (gomod), Node 22.22.0 et yarn 4.18.0 (empreinte `sha512` du `packageManager`). Elle est construite par BuildKit, deux fois au même digest, puis poussée dans Zot. Ses entrées sont listées par digest dans le journal.
  - (b) **`quay.io/konflux-ci/hermeto` épinglée par digest**, après avoir établi la clé de ses `.sig` et `.att` et les avoir vérifiées.
- **D5. Fermeture en lecture seule dans le pod de construction.**
  - (a) **Workspace `entrees` séparé**, monté `readOnly` dans `construire-image`, recommandé : `image.tar` reste dans `sortie`. Les tâches sont re-signées et la liste revue est mise à jour.
  - (b) En rester au bind en lecture seule de BuildKit.

### Accords demandés avant chaque jalon

- **F1** :
  - **téléchargement de yarn 4.18.0** par corepack, depuis `registry.npmjs.org`, dans `~/.cache/supply-chain-poc/` et non dans le système, avec contrôle du `sha512` du `packageManager` ;
  - sources de Traefik clonées par tag, commit relevé ;
  - Zot éphémère local, déjà utilisé par `mise run bancs`.
  - Rien n'est installé dans le système.
- **F2** :
  - image d'outils (D4) ;
  - NetworkPolicy de sortie (D2) ;
  - compte Zot (D3) ;
  - tâches et pipeline signées, avec leurs digests ajoutés à la liste revue de la porte.
- **F3** :
  - pipeline `sample-app` re-signée ;
  - PipelineRun réel ;
  - gabarit en service inchangé tant que le propriétaire n'a pas accordé la bascule.

Chaque jalon commence par des prédictions datées (`date -u`), archivées dans `resultats/`. Les passages ratés y sont conservés.

### Points à vérifier en cours de jalon (non supposés)

- Hermeto avec yarn 4.18.0 sous Node 22.22.0 alors que `.nvmrc` demande Node 24.21.0 : la fermeture en dépend-elle ? La construction de l'interface reste hors périmètre.
- Les chemins absolus de la fermeture yarn : le prefetch et la restauration doivent-ils se faire au même chemin, comme pour npm ? La restauration à un autre chemin est faite en premier.
- La détection d'une altération par yarn hors réseau (somme de `yarn.lock` ou du cache) : prédite en F1 après lecture du code de yarn 4.18.0, pas supposée.
- Les noms de domaine contactés par le prefetch, relevés en F1, avant d'écrire la règle `toFQDNs`.

### Additif du 03/11/2026, 16:15 UTC (avant toute exécution, après relecture)

- **Heure des faits relevés** : leur début n'a pas été mesuré. Seule la fin est relevée (`date -u` : 16:11:17 UTC). Il faut lire « jusqu'à 16:12 UTC ».
- **Go de Traefik** : le `go.mod` de `v3.7.17` exige `go 1.27.0`, sans directive `toolchain`. Go 1.26.10 (brique 04, `mise run outils:go-toolchain`) ne suffit pas.
  - Dernière version stable : **go1.27.3** (`go.dev/dl`, relevé à 16:14 UTC).
  - F1 demande donc en plus le **téléchargement de Go 1.27.3** comme module `golang.org/toolchain`, vérifié par `sum.golang.org` comme Go 1.26.10, dans `~/.cache/supply-chain-poc/`.
  - Avec `GOTOOLCHAIN=local`, aucun autre téléchargement n'est permis. La façon dont Hermeto 0.64.0 choisit sa toolchain pour un `go.mod` en 1.27 sera lue dans son code avant les prédictions, sans être supposée.
- **`go build` de Traefik hors réseau sans l'interface** : `webui/embed.go` déclare `//go:embed static`, et `webui/static/` ne contient dans le dépôt que `DONT-EDIT-FILES-IN-THIS-DIRECTORY.md`, `static/*` étant ignoré par git.
  - La compilation n'exige donc pas l'interface construite. Le binaire de F1 est **un binaire sans interface**, ce qui suffit à mesurer la fermeture gomod. Aucun répertoire bouche-trou n'est ajouté.
  - Pour l'interface, F1 mesure la fermeture yarn et `yarn install --immutable` hors réseau, pas `vite build`.
- **Test négatif « fermeture poussée hors de la plateforme » de F3** : avec D1 (a), aucun mécanisme ne le refuserait aujourd'hui. Celui qui signe la pipeline peut y épingler n'importe quel digest, et rien ne vérifie d'où vient la fermeture. Sans règle, ce test serait un faux négatif. D'où D6.
- **D6. Origine de la fermeture vérifiée par la porte.**
  - (a) **Nouvelle règle de la porte**, recommandé : la fermeture déclarée dans `resolvedDependencies` doit avoir une provenance de Chains (clé de Chains) dont le sujet est son digest, issue de la pipeline de prefetch approuvée. Le test négatif de F3 n'est gardé qu'avec (a).
  - (b) **Pas de règle**, et le test négatif est retiré de F3 : la fermeture est produite par la plateforme sans que la porte le vérifie.
  - **Effets à connaître avant d'accorder (a)** :
    - la ConfigMap `porte` change durablement ;
    - l'image `3a7ca1b1` de `builds/sample-app`, construite avec la fermeture `0ab5a507…` poussée par `poc-ecriture` depuis l'hôte, **serait refusée** jusqu'à une construction sur une fermeture de la plateforme (F3) ;
    - les témoins des étapes de la 08 qui passent par la porte (`test7`, `test8`, `reglec`, `rc`, `ba`, `controle6`) rendraient eux aussi ce refus s'ils étaient rejoués. Leurs verdicts archivés restent valables.
- **`web/dist` reste un intrant produit sur l'hôte**, poussé par `poc-ecriture`, même après F3. « Prefetch dans Tekton » ne couvre que la fermeture : toutes les entrées ne viendront pas de la plateforme. Une règle D6 limitée à la fermeture laisse ce même trou pour `web/dist`. Le combler suppose Node dans la chaîne (2c, brique 11), hors périmètre proposé.
- **Ordre des accords** : F1 ne dépend d'aucune des décisions D1 à D6. Le protocole et l'accord de F1 sont soumis d'abord. D1 à D6 le seront avant F2, une fois connus par F1 les noms de domaine (D2) et le comportement des chemins (D4, D5).

## F1, fermetures de Traefik sur l'hôte (03/11/2026, 16:21 à 16:43 UTC ; accord du propriétaire : « Oui, tout »)

Script : [`traefik.sh`](traefik.sh) (`mise run fermetures -- <étape>`). Proxy de relevé des noms : [`journal-connect.py`](journal-connect.py). Prédictions et résultats : [`resultats/f1-predictions.md`](resultats/f1-predictions.md), avec les passages ratés archivés.

| Mesure | Résultat |
|---|---|
| Outils | Go 1.27.3 (module `golang.org/toolchain`, `h1:` égal à `sum.golang.org`) ; yarn 4.18.0 par corepack (sha512 du `packageManager` ; sha512 faux refusé) |
| Sources | `v3.7.16` (`af6d927c`) et `v3.7.17` (`04e8ccf8`), **tags légers**, commits vérifiés par GitHub ; `go 1.26.0` puis `go 1.27.0` ; `yarn.lock` identique, **86 modules Go changent** |
| Prefetch (Hermeto 0.64.0) | 87 s et 90 s. gomod 402 et 403 zips (323 et 329 Mo) ; yarn 688 zips (361 Mo) ; aucun chemin absolu dans la fermeture ; sources intactes |
| Noms contactés | `proxy.golang.org`, `registry.yarnpkg.com`, `storage.googleapis.com` (une fois) ; **`git fetch` des tags vers l'origine (GitHub), hors proxy**, lancé par Hermeto pour dater le module principal ; `sum.golang.org` jamais contacté (`go.sum` complet) |
| Registre (Zot, dedupe) | 4 433 et 4 437 couches ; +704 Mo puis +239 Mo ; même digest au second push ; **65,8 % des octets de `v3.7.17` partagés** (yarn 100 %, gomod 28 %) |
| Restauration | Arbre identique ; `go build` hors réseau : **binaire `6dee223e…` identique** depuis la fermeture d'origine et depuis une restauration à un autre chemin ; `yarn install --immutable` hors réseau : **`node_modules` identiques aux deux chemins** ; sans fermeture : refus |
| Altérations | zip yarn avec checksum : `YN0018` ; checksum de `yarn.lock` : `YN0018` ; zip Go valide modifié : « checksum mismatch » ; blob altéré dans Zot : « mismatched digest » ; **zip d'un paquet natif linux-x64 (sans checksum dans `yarn.lock`) : accepté** |

**Constats** :
- **Paquets yarn conditionnels non vérifiés.** yarn 4.18.0 n'enregistre pas de checksum pour les paquets à `conditions` (45 dans le `yarn.lock` de Traefik, dont 3 natifs linux-x64), et sa validation du cache les accepte sans calculer d'empreinte (`unstablePackages`, lu dans `yarn.js`).
  - **Mesuré** : le binaire `.node` altéré est installé dans `node_modules` (`e536f326…` au lieu de `ae168566…`, [relevé](resultats/f1-releve-complementaire.log)).
  - Seul le digest OCI de la couche protège ces paquets, et le SBOM de Hermeto ne porte aucune empreinte.
  - Déduit, non mesuré : un registre amont qui servirait un autre binaire serait accepté dès le prefetch, puis figé dans la fermeture.
  - **Le seuil de la brique 04 (« fermeture altérée → build refusé, pour chaque gestionnaire ») n'est donc pas atteint pour yarn sur ces paquets.**
- **Hermeto contacte l'origine git des sources** (`git fetch` de tous les tags), sans passer par le proxy. Dans le cluster, le pod de prefetch devra pouvoir lire Forgejo.
- **Le chemin de la fermeture n'est pas figé** pour gomod ni pour yarn : `generate-env` le reporte dans les variables (`YARN_GLOBAL_FOLDER`, `GOPROXY`…). Le constat « chemins canoniques obligatoires » de cette brique reste à revérifier pour npm (lockfile réécrit par `inject-files`), non mesuré en F1.
- **La toolchain suit le projet** : Traefik est passé de Go 1.26 à 1.27 entre deux tags correctifs.

## Décisions D1 à D6 pour F2 (03/11/2026, choix du propriétaire : « Toutes (Recommandé) »)

- **D1 (a)** : pipeline de prefetch séparée. La pipeline de construction reste épinglée sur le digest de la fermeture.
- **D2 (a)** : `toFQDNs` limité aux noms mesurés en F1 pour Go (`proxy.golang.org`, `storage.googleapis.com`), plus la lecture de Forgejo (`git fetch` des tags par Hermeto). Aucune autre sortie. Le registre npm dépend de la question npm, encore ouverte.
- **D3 (a)** : compte Zot `poc-fermetures`, création par digest dans `entrees/**`, avec la tâche `publier-fermeture` séparée et sans secret dans le pod de prefetch.
- **D4 (a)** : image d'outils construite par la plateforme : Hermeto 0.64.0, ses toolchains, et Node et yarn si npm est retenu.
- **D5 (a)** : workspace `entrees` monté en lecture seule dans `construire-image`.
- **D6 (a)** : règle de la porte qui exige que la fermeture vienne de la pipeline de prefetch. L'image `3a7ca1b1` actuelle est refusée jusqu'à F3.

**npm (03/11/2026, choix du propriétaire : « gomod seul (Recommandé) »)** : F2 ne préfetche que les modules Go. Le Dockerfile de la 04 ne lit que `deps/gomod`, et `web/dist` arrive tout fait. Il reste un intrant produit sur l'hôte : c'est un trou connu, à traiter avec Node dans l'image de build (2c, brique 11). D2 se limite donc à `proxy.golang.org`, `storage.googleapis.com` et la lecture de Forgejo, et D4 n'embarque ni Node ni yarn.

**D1 à D6 ne valent pas accord d'exécution de F2.** F2 sera préparé à sec : image d'outils, compte `poc-fermetures`, NetworkPolicy, tâches et pipeline signées, règle D6, prédictions datées. Il sera ensuite soumis avec ses effets à connaître, dont le refus durable de `3a7ca1b1` par D6 jusqu'à F3. Rien n'est appliqué au cluster ni à Zot avant ce oui.

## F2, préparation à sec (03/11/2026, à partir de 16:55 UTC ; demande du propriétaire : « Oui, préparer F2 »)

**Deux décisions révisées par le propriétaire avant toute écriture :**
- **D2, révisée : activer le proxy DNS de Cilium** (choix « Activer le proxy DNS (Recommandé) »).
  - Fait relevé : `toFQDNs` est coupé dans notre Cilium. [`cilium/valeurs.yaml`](../08-trust-plane/cilium/valeurs.yaml) a `l7Proxy: false`, choix de J7, et au tag `v1.20.4`, `pkg/fqdn/bootstrap/dns_proxy.go` ne démarre pas le proxy DNS sans `EnableL7Proxy`.
  - Au même tag, avec `envoy.enabled` faux, l'Envoy embarqué n'est démarré qu'à la demande (`onDemandXdsStarter`, `pkg/envoy/cell.go`). Une politique DNS et `toFQDNs` seule ne devrait donc pas lancer Envoy. C'est à mesurer, pas à supposer.
  - Le test 6 de la 08 est rejoué après le changement.
- **D3, révisée : fermetures rangées dans `builds/fermetures/**`** (choix « builds/fermetures (Recommandé) »). Chains y écrit `.sig` et `.att` avec son compte actuel `poc-build`. `poc-fermetures` y crée par digest seulement.
  - Fait lu dans le code de Zot v2.1.22 (`pkg/api/authz.go`) : **le motif de dépôt le plus long l'emporte**. La politique `builds/fermetures/**` remplace donc `builds/**` pour ces dépôts : elle reliste la lecture anonyme, `poc-ecriture` et `poc-build`. `poc-images` et `poc-replay` n'y ont aucun droit.

**Faits relevés pour l'image d'outils (D4), hors ligne** :
- Dans le nixpkgs épinglé du banc B, déjà présents sur l'hôte : `python313` 3.13.12, `gitMinimal` 2.51.2 (avec `git-remote-https`) et `cacert` 3.123. Leur clôture fait 45 chemins et 275 Mo.
- Les 51 dépendances de Hermeto 0.64.0 installées sur l'hôte sont toutes des roues : 44 `py*-none-any`, les autres `manylinux` en `cp313`.
- sample-app déclare `go 1.24` : Go 1.26.10, celui de l'image de build de la 04, suffit.

**Autres faits** :
- Le CronJob d'horodatage parcourt tous les dépôts sous `builds/`. Il horodatera donc aussi les enveloppes de Chains des fermetures.
- Aucune règle Kyverno ne restreint les images des pods de `builds`.
- Trusted Resources couvre `tekton/(tasks|pipelines)/*`.

**Périmètre de F2** :
- image d'outils ;
- proxy DNS de Cilium ;
- compte `poc-fermetures` ;
- NetworkPolicy `prefetch-sortie` ;
- tâches `prefetch-gomod` et `publier-fermeture`, et pipeline `prefetch-sample-app` ;
- deux prefetch du même commit ;
- provenance.

D5 (workspace en lecture seule) et D6 (règle de la porte) sont faites en F3, avec la bascule de la construction : la fenêtre pendant laquelle la porte refuse `3a7ca1b1` reste ainsi la plus courte possible.

**D2, révisée une seconde fois (03/11/2026, 18:17 UTC ; décision du propriétaire : « Sortie 443 hors privé (Recommandé) »).**
- Mesuré : `l7Proxy: true` démarre l'Envoy embarqué dans les trois agents. cilium/proxy est évalué « À surveiller » au doc 04. Retour à `l7Proxy: false` à 18:11 UTC ([résultats](resultats/f2-predictions.md)).
- Le pod de prefetch sort vers les adresses publiques en 443 seulement, plus Forgejo et le DNS.
- La source des modules est imposée par Hermeto (`HERMETO_GOMOD__PROXY_URL=https://proxy.golang.org`), et leur intégrité par `go.sum`.
- Limite : un pod compromis pourrait envoyer le code cloné vers une adresse publique.

## F2 exécuté (03/11/2026, 17:39 à 18:25 UTC ; accord du propriétaire : « Dans l'ordre »)

Résultats complets : [`resultats/f2-predictions.md`](resultats/f2-predictions.md), avec les passages ratés archivés.
- **Image d'outils** `plateforme/outils-prefetch@68e0ae70` : identique sur deux constructions BuildKit sans cache, 198 Mo, sans image de base externe.
- **Cilium** : `l7Proxy: true` a démarré l'Envoy embarqué. Retour à `false`, puis D2 révisée une seconde fois.
- **Zot** : compte `poc-fermetures`, création par digest seulement dans `builds/fermetures/**`. Mesuré : le motif le plus long remplace `builds/**`.
- **Réseau** : `prefetch-sortie` laisse sortir en 443 vers le public, vers Forgejo et le DNS. Port 80, API de k3s et Zot refusés, avec trace dans Hubble.
- **Prefetch** : deux PipelineRuns du commit `6391fd43` donnent **la même fermeture `74c265e7`**, dont le contenu gomod est celui de la fermeture de l'hôte. Chains la signe, et sa provenance la relie au commit, à l'image d'outils et aux tâches revues.
- **Reste F3** : bascule de la construction, D5 et D6.

## F3, préparation à sec (03/11/2026, à partir de 18:42 UTC ; demande du propriétaire : « continue », compris comme un oui à la seule préparation)

Script : [`bascule.sh`](bascule.sh) (`mise run fermetures:f3 -- <étape>`). Prédictions et résultats :
[`resultats/f3-predictions.md`](resultats/f3-predictions.md). Rien n'est poussé dans Zot ni appliqué au cluster avant
l'accord d'exécution.

**D6, règle `porte.fermeture_plateforme`** ([`porte.rego`](../08-trust-plane/politique/porte/porte.rego)) :
- **Lecture de la fermeture** : elle vient du résultat `FERMETURE_ARTIFACT_INPUTS` du TaskRun `preparer-entrees`, dans le
  contenu signé de la provenance, et jamais d'un motif de dépôt.
- **Provenance jugée** : seule la plus récente des provenances de PipelineRun l'est, comme pour `trusted_task`
  (`lib.pipelinerun_attestations` de la bibliothèque).
  - Une construction de F3 qui redonne `3a7ca1b1` rend donc l'image de nouveau admissible, malgré l'ancienne provenance
    restée attachée.
  - À l'inverse, toute construction plus récente sur une fermeture de l'hôte la ferait refuser de nouveau.
- **Vérification** : la provenance de la fermeture est vérifiée par `ec.sigstore.verify_attestation`, avec la clé et les
  options de ec (`--public-key`, `--ignore-rekor`). Il en faut une issue d'un **PipelineRun** :
  - buildType slsa-tekton et `builder.id` autorisé ;
  - sujet égal à la fermeture, sous `builds/fermetures/` ;
  - tâches exactement `prefetch-gomod` et `publier-fermeture`, de la liste revue ;
  - digest et dépôt publiés par `publier-fermeture` ;
  - même dépôt Forgejo que la construction.
- **Cas exclu** : une attestation de TaskRun seule (`publier-fermeture` lancée hors de sa pipeline sur un PVC prérempli) ne
  suffit pas.
- **Champ** : la règle ne s'applique qu'aux provenances qui contiennent `preparer-entrees` ou `construire-image`. Les images
  d'essai de la 08 ne sont pas touchées.
- **Testée sur l'hôte**, étape `regle` : 21 tests sur des provenances simulées, à la forme des provenances réelles. Chacune
  des 12 conditions testables, retirée, fait échouer au moins un test.
  - La 13e (`predicateType`) est impliquée par la bibliothèque et gardée explicite.
  - Quatre passages ratés sont archivés, dont un où les simulations étaient fausses et les refus non probants.

**D5, entrées en lecture seule** ([`construire-image.yaml`](../08-trust-plane/politique/taches/construire-image.yaml),
[`sample-app.yaml`](../08-trust-plane/politique/taches/sample-app.yaml)) :
- **Pourquoi un seul PVC** : `coschedule: workspaces` de Tekton v1.15.5 refuse un TaskRun lié à deux PVC
  (`ValidateOnlyOnePVCIsUsed`, lu au tag). La pipeline lie donc le même workspace par sous-dossier.
  - `preparer` écrit `entrees/`.
  - `construire` lit `entrees/` en `readOnly` et écrit `image/`.
  - `publier` lit `image/`.
  - Un volumeClaimTemplate donne un seul nom de PVC aux deux liaisons (`taskWorkspaceByWorkspaceVolumeSource`).
- **Tâches touchées** : seule `construire-image` change. `preparer-entrees` et `publier-image` gardent leur bundle.
- **Contrôle dans la tâche** : `construire-image` essaie d'écrire dans `entrees` et échoue si l'écriture passe.
- **Lecture du layout** : BuildKit lit le layout en lecture seule. Le magasin local de containerd ne crée `ingest` qu'à la
  première écriture (lu dans containerd v2.4.1).
- **Limite** : l'étape est privilégiée et root. Le témoin `lecture_seule` mesure si un remontage en lecture-écriture dans
  l'invité Kata permet d'écrire.

**Autres changements** :
- `politique.sh` calcule son dossier par `BASH_SOURCE`, pour être sourcé depuis la brique 03. Rien ne change pour
  l'exécution directe ni pour `preuves.sh`, qui est dans le même dossier.
- `construction.sh` (J7) rend désormais la tâche D5 et la pipeline à sous-dossiers, avec la fermeture de l'hôte.

**Effets à connaître avant d'accorder l'exécution** :
- **Zot** :
  - bundles `tekton/tasks/{preparer-entrees,construire-image,publier-image}:f3` et `tekton/pipelines/sample-app:f3`, plus
    `:f3-alteree` et `:f3-absente` (témoins) ;
  - fermeture altérée dans `entrees/sample-app/fermeture-alteree` (`poc-ecriture`) ;
  - enveloppes de Chains sur `builds/sample-app`.
  - Zot n'autorise pas la suppression : ces objets restent.
- **ConfigMap `porte`** : elle change durablement (D6 et liste revue). Entre les étapes `porte` et `construire`, l'image
  réelle `3a7ca1b1` est **refusée** par la porte, pendant quelques minutes si tout se passe bien.
- **Liste revue** :
  - ajout du nouveau digest de `construire-image`, revu par le propriétaire en cours d'exécution, comme en F2 ;
  - **retrait proposé de `403ccbd8`** (J7, entrées inscriptibles). Sans ce retrait, une construction avec l'ancienne tâche
    resterait admise par `trusted_task`, et D5 ne serait qu'une option.
- **Contrôle 6** : la VSA est liée au digest, pas à la provenance jugée (`vsa.sh`). Si F3 redonne `3a7ca1b1`, la porte retient
  la VSA du rejeu de la provenance de J7, celle de la fermeture de l'hôte : c'est un écart à consigner. Si le digest diffère,
  la porte refuse au contrôle 6 jusqu'à un nouveau rejeu de la brique 10 et au push d'une VSA, soumis à accord.
- **Rejeu complet de la 08** (`rejeu.sh`) : avec D6, la bascule de J8 jugerait une image construite par J7 sur la fermeture de
  l'hôte et la refuserait. Le rejeu doit intégrer F2 et F3 de la brique 03 avant la bascule de J8. C'est un travail à part,
  après F3.
- **`preuves.sh bascule`** relit `$W/construction/pipeline.ref` (J7). Rejoué après F3, il remettrait la pipeline de J7 en
  service.
- **Témoin `lecture_seule`** : un pod Kata privilégié en root, hors Tekton, dans `builds`, plus un PVC de 16 Mi. Tout est
  supprimé à la fin.
- **`web/dist`** reste un intrant produit sur l'hôte (inchangé).

**Ordre d'exécution proposé** : `taches` (passe `SIGNER=construire-image`, revue de la liste, passe normale), `temoins`,
`lecture_seule`, puis `porte` juste avant `construire`, puis `provenance` et `bascule`. Cet ordre garde la fenêtre de refus
de l'image réelle la plus courte. **Retour arrière** si `construire` échoue après `porte` : remettre la ConfigMap avec
`porte.rego` et `taches.yml` de `d7d05b4`, ou garder le refus, au choix du propriétaire.

**Essai réel avant tout accord** (étape `reel`, sur l'hôte, lecture anonyme de Zot seulement) : la vraie fonction
`ec.sigstore.verify_attestation`, avec la clé de Chains, vérifie 4 provenances sur la fermeture de F2. La règle en retient 2,
celles des deux PipelineRuns de F2, et écarte les provenances de TaskRun. Une autre clé n'en vérifie aucune. La fermeture de
l'hôte n'en a aucune (« no matching attestations »). La règle lit bien la fermeture dans la provenance archivée de J7. Les
options de clé passées par ec à la règle sont lues dans le code de conforma/cli v0.10.42 (`conftest_evaluator.go`).

**Journaux** :
- pods des PipelineRuns, Jobs de la porte et pods témoins : collectés par Alloy (`pods.alloy` de la 19b) ;
- refus réseau : dans Hubble seulement, écart de F2 inchangé ;
- étapes `regle` et `reel` : sur l'hôte, dans `resultats/`.

## F3 exécuté (03/11/2026, 19:24 à 19:31 UTC ; accord du propriétaire : « Oui, avec la bascule », « Retirer 403ccbd8 »)

Résultats complets : [`resultats/f3-predictions.md`](resultats/f3-predictions.md), passages ratés archivés.
- **Liste revue** : `construire-image@66a9f298` (D5) remplace `403ccbd8`. `preparer-entrees` et `publier-image` sont
  inchangées.
- **Témoins** :
  - fermeture altérée (zip de chi valide, un fichier non compilé modifié) : refusée au `go build` (« checksum mismatch »,
    `go.sum`) ;
  - fermeture absente : refusée au tirage ;
  - rien n'est poussé.
- **D5, mesuré** : `entrees` est monté `virtiofs ro`, et une écriture est refusée. Mais **un root privilégié de l'invité Kata
  remonte le volume en lecture-écriture, et son écriture atteint le PVC**. La lecture seule protège donc des erreurs, pas
  d'une étape malveillante ([ADR 0001](../../../docs/adr/0001-runtime-isolation.md)).
- **D6** : l'image réelle est refusée tant que sa provenance la plus récente nomme la fermeture de l'hôte (19:26 à 19:31). Elle
  est admise une fois reconstruite sur la fermeture de la plateforme : **même image `3a7ca1b1`**, horodatage et VSA ok.
- **Provenance** : elle nomme `builds/fermetures/sample-app@74c265e7` et les sous-dossiers des workspaces.
- **Bascule** : le gabarit en service utilise la pipeline de F3 (`sample-app@e11fe3af`).
- **Écarts** :
  - VSA liée au digest et non à la provenance : la VSA retenue est celle du rejeu de J7 ;
  - `web/dist` toujours produit sur l'hôte ;
  - refus réseau du prefetch hors de Grafana (F2).
- **Journaux** : les changements faits par l'API et dans Zot sont dans les journaux d'audit collectés par Alloy (19b), et
  les pods dans `pods.alloy`. C'est déduit de la configuration, aucune requête n'a été faite dans Loki.
- **Suite** : le rejeu complet de la 08 (`rejeu.sh`) doit intégrer F2 et F3 avant la bascule de J8.

## Additif du 03/11/2026, 19:45 UTC : rejeu complet de la 08, inventaire à sec (rien exécuté, `rejeu.sh` inchangé)

La « Suite » ci-dessus (intégrer F2 et F3 avant la bascule de J8) **sous-estimait le travail**. Relevé à sec dans les
scripts :

- **D6 est chargée dès J6.** Dans un rejeu de zéro, `politique.sh porte` (`cm_porte`) charge `porte.rego` (D6) et
  `taches.yml` (sans `403ccbd8`) versionnés. Tout jugement ultérieur de l'image réelle se fait donc sous D6, alors que J7
  la construit encore sur la fermeture de l'hôte. Tests de J8 touchés :
  - `attseule` (`t8_cas`) exige « ec admet », et `decision3` exige `true||ok`. Les deux seraient refusés par
    `porte.fermeture_plateforme`.
  - `decision3` et `preuves.sh bascule` reconstruisent avec `$W/construction/pipeline.ref`, la pipeline de J7 (fermeture de
    l'hôte). Placer F2 et F3 juste avant la bascule ne suffit donc pas.
  - `reglec` compare des violations relatives à celles de l'image réelle. Il ne devrait pas changer, mais ce n'est pas
    vérifié.
- **`vm.sh detruire` détruit les trois VM**, `sc-stockage` comprise (`VMS=(sc-confiance sc-build sc-stockage)`). Le dernier
  rejeu complet (« enchainement », 02/11, 13:10 à 14:40 UTC) est antérieur aux jalons suivants, qu'aucun script de
  `rejeu.sh` ne refait :

| Jalon | Perdu par `detruire` | Nécessaire pour que la porte admette l'image réelle | Rejouable sans accord à chaque action |
|---|---|---|---|
| 01, S2 à S6 (comptes Forgejo, synchro en timer, `sample-app-sync`, Traefik) | oui (`sc-stockage`) | non | non vérifié (S6 lit GitHub) |
| 19, O2 et O3 (Prometheus, Alertmanager, règles) ; O4 (incidents simulés) | oui (`sc-stockage`) | non | non vérifié |
| 19b, L2 à L6 (Loki, Grafana, Alloy sur les trois VM, battement de cœur, TLS) | oui, **avec l'historique des journaux d'audit** | non | non vérifié |
| 10, D5 (compte Zot `poc-replay`) | non : recréé par `stockage.sh zot` (J2), depuis le htpasswd en cache | non | oui |
| 10, R5 et 19b, L7 (VSA dans `builds/vsa/sample-app`) | oui (Zot) | **oui** : sans VSA, le contrôle 6 refuse | **non** : accord à chaque push de VSA |
| 08, `controle6` et `reelle` (preuves.sh) | non concerné : `cm_porte` charge `vsa.sh` dès J6 | — | absents de `rejeu.sh` |
| 03, F2 (image d'outils dans Zot, secret `zot-fermetures`, `prefetch-sortie`, tâches, prefetch) | oui (Zot, cluster) ; compte `poc-fermetures` recréé par J2 | **oui** (D6) | oui en principe, à mesurer |
| 03, F3 (tâches D5, construction sur la fermeture de la plateforme, bascule) | oui | **oui** (D6) | oui en principe, à mesurer |

- **Constantes de `bascule.sh`** : les bundles de tâches sont stables d'un rejeu à l'autre. `preparer-entrees@2070d601`
  apparaît 17 fois, identique, dans les journaux de rejeu et de construction. La fermeture `74c265e7` a été obtenue deux
  fois en F2. Sa stabilité depuis zéro n'est pas mesurée.

**Effet à connaître** : tout rejeu de zéro efface l'historique de Loki (19b), ce qui contredit l'exigence « tout consultable
dans Grafana », ainsi que la VSA. Une décision du propriétaire est attendue avant toute modification de `rejeu.sh`.

**Choix du propriétaire (03/11/2026, avant 19:58 UTC : « 1 c »)** : pas de rejeu de zéro de la 08 pour l'instant. `rejeu.sh`
n'est pas jouable tel quel depuis le 02/11/2026 (rejeu « enchainement »). Il reste inchangé, avec un avertissement en
en-tête. La première décision à prendre porte sur l'historique de Loki (19b) avant toute destruction de `sc-stockage`.
Les options (a) (F2 et F3 seulement) et (b) (intégration complète) restent ouvertes.

**Additif du 03/11/2026, 20:04 UTC** : les options sur l'historique de Loki sont préparées à sec en D22 (README de la 19b) ;
rien n'a été arrêté ni copié. Décision du propriétaire attendue.

**Additif du 03/11/2026, 20:08 UTC** : D22 (d) retenue par le propriétaire (« On s'en moque de tout perdre sur une démo ») :
la perte de l'historique de Loki, de la VSA et des données de Zot n'est plus un obstacle au rejeu de zéro. Reste le choix entre
les options (a) et (b) ci-dessus.

## Additif du 03/11/2026, 20:23 UTC : intégration complète dans `rejeu.sh` (choix « b » du propriétaire), faite à sec

Choix du propriétaire, 03/11/2026, entre 20:08 et 20:23 UTC : « 1 b » (intégration complète). Rien n'a été exécuté ; `rejeu.sh` et
`construction.sh` passent `bash -n`, et chaque étape appelée existe dans son script.

**Correction de l'inventaire de 19:45 UTC** (lu dans `preuves.sh` après coup) :
- `attseule` juge un témoin sous la ConfigMap `porte-temoin`. Il exige seulement `builtin.image.signature_check` présent et
  `builtin.attestation.signature_check` absent : une violation D6 en plus ne le change pas.
- `decision3` construit sa propre pipeline d'essai et ne lit pas `pipeline.ref`.
- Les tests touchés par D6 sont en fait `test7` (verdict de l'image réelle), `test8` (`t8_cas reel ok … 2/2`) et la bascule.
  `test8` compte en dur deux enveloppes sur l'image : un F3 joué avant J8 en ajouterait deux, et le ferait échouer.

**Montage retenu (B)** : J7 construit directement sur la fermeture de la plateforme, et F3 n'est plus nécessaire.
- F2 s'insère entre `construction.sh entrees` et `construction.sh taches`. Il garde les étapes `image`, `compte`, `reseau`,
  `taches`, `prefetch` et `provenance` ; `cilium` est abandonnée.
- Les digests de F2 d'un passage précédent sont retirés avant, parce que le cache `03/f2` survit à `detruire`.
- `construction.sh taches` lit le digest produit par ce passage (`03/f2/fermeture-1.digest`), sans valeur en dur. La
  vérification de la provenance compare à cette même référence. `FERMETURE_SOURCE=hote` garde l'ancien comportement.

**Ajouts après J8**, avec les étapes sautées annoncées par une ligne du journal :
- Brique 01 : S2 à S4, puis S6. S5 est sautée : D6 refuserait l'image du fork, qui n'a pas de fermeture propre. C'est déduit
  du code, non mesuré, et cela vaut sans doute aussi sur le cluster actuel.
- Brique 19 : O2 sans `telecharger`, puis O3 `regles deployer` une fois Alloy en place.
- Brique 19b :
  - L2 ;
  - L3 avec `evenements`, qui régénère le jeton ;
  - L5 `battement` ;
  - L6 réduit à `controle_grpc`, parce que L2 et L3 posent déjà la configuration finale ;
  - L4 `temoins secrets`, sans `muette` ni L7.
- VSA de la brique 10, avec `POUSSER_VSA=1` seulement (accord à chaque push). Le bundle versionné est re-poussé, puis le
  contrôle 6 est joué.
- `fuites` reste en dernier.

**Non vérifié à sec** :
- La fermeture `74c265e7` et l'image d'outils `68e0ae70` sur un nouveau cluster, un autre jour : `prefetch.sh image` exige
  `68e0ae70` et s'arrêterait sur un écart.
- F2 `prefetch` sous le gabarit d'essai de J6.
- `reglec`.
- Le témoin `builds/essai-webhook` du contrôle 6 (C2).
- Les fausses alertes A2 et A5 possibles sur un Prometheus vide.

**Additif du 03/11/2026, 20:29 UTC (relecture avant soumission, à sec)** :
- **Témoins à clé jetable sous D6.** `test7` (témoins D1, sauf `sans-date`), `reglec` et `test8` (témoins `v3`) reprennent
  la provenance réelle. Ils la re-signent avec une clé jetable, puis la jugent sous `porte-temoin`.
  - D6 vérifie la provenance de la fermeture avec la clé de ec, ici la clé jetable. Ces témoins porteraient donc
    `porte.fermeture_plateforme` en plus, quel que soit le montage.
  - Leurs attendus exacts sont complétés dans `preuves.sh` (`D6_TEMOIN`). C'est une prédiction déduite de `porte.rego`, non
    mesurée ; sans cette correction, J8 se serait arrêté en KO.
  - L'attendu de `v3-sig` est désormais trié.
- **Fichiers du cache.** Les CA `ca-sc-confiance` et `ca-sc-build` de la 19b sont fabriquées par `openssl`, et non tirées
  de k3s. `k8s-ca.crt` est relu dans le kubeconfig du nouveau cluster. Les jetons périmés (Prometheus, événements d'Alloy,
  Forgejo) sont régénérés par leurs étapes.
- **VSA re-poussée.** Le bundle versionné atteste le rejeu de l'ancienne construction : invocation `d9006af7`, sur la
  fermeture de l'hôte. Il n'atteste pas la construction du rejeu. Le contrôle 6 passera quand même, parce que `vsa.sh` ne lie
  la VSA qu'au digest (même constat qu'en F3).
- **Durée estimée** : environ 2 h. Le rejeu « enchainement » a pris 5 429 s. F2 a pris environ 5 min le 03/11, avec
  le cache. Il faut compter environ 6 min pour la 01 (jusqu'à 15 min si `planifie` attend) et environ 10 min pour la 19 et
  la 19b.

## Additif du 03/11/2026, 22:43 UTC : rejeu `complet` de la 08 exécuté (accord du propriétaire : « Oui, avec VSA »)

Il s'est déroulé de 20:31 à 22:42 UTC, en cinq parties ; le détail est dans le README de la 08.
- **F2 dans le rejeu** : 217 s.
  - Image d'outils `68e0ae70` et fermeture `74c265e7` reconstruites à l'identique sur un cluster neuf, un autre jour. Les deux
    prefetch donnent le même résultat.
  - Ce point était non vérifié à sec ; il est maintenant mesuré.
  - Premier passage raté : le contexte de `image` copié au passage précédent était en lecture seule. Le passage est archivé
    (`f2-image-rejeu-complet-rate.log`, condensé) et `prefetch.sh` est corrigé.
- **Montage (B)** :
  - J7 construit `3a7ca1b1` sur la fermeture de la plateforme ; la provenance la déclare, avec deux enveloppes.
  - Les tests de J8 passent avec les mêmes nombres d'OK qu'avant D6.
  - La prédiction `D6_TEMOIN` (témoins à clé jetable) est vérifiée.
  - La bascule et le contrôle 6 sont conformes.
