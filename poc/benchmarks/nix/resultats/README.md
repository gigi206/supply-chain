# Résultats du banc B : Nix ou référence Hermeto (28/10/2026, partie locale)

Grille : [ADR 0000 §3](../../../../docs/adr/0000-assembler-ou-adopter.md) (figée avant le banc). Banc d'essai : [`poc/sample-app`](../../../sample-app) (Go + interface npm embarquée).

## Environnement

| Élément | Détail |
|---|---|
| Hôte | 4 CPU, 15 Gi, sans KVM ni Docker ; Nix 2.34.6 mono-utilisateur, sandbox actif |
| nixpkgs | `nixos-25.11` révision `b6018f87da91`, archive immuable de releases.nixos.org figée par `flake.lock` (narHash) |
| Candidat Nix | [`flake.nix`](../flake.nix) : `buildNpmPackage` (interface), `buildGoModule` (binaire, Go 1.25.10), `dockerTools.buildLayeredImage` (image) |
| Référence | **Hermeto 0.64.0** (installé depuis le tag source avec l'accord du propriétaire), Go 1.24.7 et Node 22 de l'hôte. Script reproductible : [`reference/hermeto.sh`](../reference/hermeto.sh), journal : [`reference-hermeto.log`](reference-hermeto.log). La **solution de repli** (vendoring natif : `go mod vendor`, cache npm) a aussi été mesurée. BuildKit n'est pas disponible (pas de démon) |

## Mesures

| Critère | Nix | Référence (Hermeto ; repli : vendoring natif) |
|---|---|---|
| **B-1** bit à bit | `nix build --rebuild` : interface, binaire et **image** identiques. Également identiques après reconstruction **dans un store vierge, sans réseau** (voir B-2) | **Hermeto** : binaire et interface identiques entre 2 builds hors réseau (`unshare -rn`, seule l'interface `lo`), dans 2 chemins différents, caches vides. **Repli** : identique aussi, mais le binaire diffère de celui d'Hermeto (`086c06e9…` contre `99ddc97c…`) : en mode module, Go inscrit le hash `h1:` de chi dans les métadonnées du binaire (`go version -m`), pas en mode vendor. **Le mode de dépendances est donc un paramètre de build à figer et à inscrire dans la provenance**. **Image non testée** (pas de BuildKit) |
| **B-2** rebuild offline depuis l'archive | **Réussi** : `nix copy` de la fermeture de build vers un cache `file://`, puis store Nix vierge, `unshare -n` (aucune interface réseau) : substitution puis `--rebuild` → identique. **Toolchains incluses** dans l'archive | Réussi (Hermeto et repli) pour le binaire et l'interface, à partir de la seule fermeture. Mais les **toolchains (Go, Node) viennent de l'hôte** et ne sont pas dans la fermeture : sur la plateforme, c'est le rôle de l'image de build archivée par digest |
| **B-3** taille et déduplication | Fermeture de build complète : **1 531 Mo** (457 Mo en zstd), toolchains comprises. Version suivante (1.0.1) : **+9,0 Mo** seulement (99,4 % partagés). Les dérivations de dépendances sont refaites car leur nom porte la version (≈ 200 Kio) | Fermeture Hermeto : **214 Kio** (zip Go 109 Kio + archive npm 105 Kio) ; repli : 276 Kio. **Hors toolchains** |
| **B-4** SBOM et PURL standards | **sbomnix 1.7.4** : uniquement des `pkg:nix` (3 à l'exécution ; 839 + 51 sans PURL au build), **0 % corrélable** par Grype ou DT. **Syft sur l'image** : 3 `pkg:golang` (application, chi v5.2.3, stdlib 1.25.10) + 4 `pkg:nix`, mais **`marked` (npm, embarqué) absent** | **SBOM Hermeto** (CycloneDX 1.6, 179 composants) : `pkg:golang/github.com/go-chi/chi/v5@v5.2.3` et `pkg:npm/marked@16.4.1` corrects, mais **173 paquets de la bibliothèque standard Go sans version** (`pkg:golang/net/http?type=package`), donc non corrélables. Le PURL du module principal est dérivé du remote `origin`. **Syft sur le binaire** apporte `pkg:golang/stdlib@1.24.7`. Combinés (et le bruit filtré) : 100 % des dépendances réelles en PURL standards |
| **B-5** Tekton + Chains, pod non privilégié | Non mesuré (il faut un cluster). Le sandbox Nix fonctionne ici en root ; en pod, il exige des user namespaces | Non mesuré |
| **B-6** coût d'adoption | Flake de 49 lignes ; ≈ 2 h, dont la résolution d'un **piège de TLS** : `fetchNpmDeps` utilise son propre bundle de CA tant que le hash est factice, donc échoue derrière un proxy TLS d'entreprise. Il faut calculer le hash hors sandbox (`prefetch-npm-deps`) | Hermeto : une ligne de configuration JSON ; < 0,5 j. Deux pièges : le source doit être un dépôt git avec un remote `origin` **joignable** (Hermeto y lit les tags) ; l'environnement de `generate-env` est à écarter (voir le constat ci-dessous) |
| **B-7** santé | Nix/nixpkgs : À surveiller (forks, CVE de sandbox 2025-2026) | Hermeto, BuildKit : À surveiller (doc 04) |

## Notation provisoire (critères mesurés seulement : B-1, B-2, B-3, B-4, B-6, B-7 ; 85 points sur 100)

| Critère | Poids | Nix | Justification | Référence | Justification |
|---|---|---|---|---|---|
| B-1 | 25 | 4 | Binaire, interface et image identiques, y compris en store vierge hors réseau ; manque 2 hôtes à ≥ 1 h d'écart | 3 | Binaire et interface identiques ; image non testée |
| B-2 | 20 | 5 | Offline complet, toolchains incluses | 3 | Offline, mais toolchains hors fermeture (à archiver via l'image de build) |
| B-3 | 10 | 3 | Fermeture lourde (toolchains) mais déduplication excellente | 4 | Fermeture minime, mais hors toolchains |
| B-4 | 15 | 2 | SBOM natif inexploitable (`pkg:nix`) ; Syft ne décrit qu'en partie l'artefact réel | 5 | PURL standards complets en combinant Hermeto (dépendances) et Syft (version de Go) |
| B-6 | 10 | 4 | Rapide, mais piège TLS et second écosystème | 5 | Une ligne de configuration ; pièges documentés |
| B-7 | 5 | 3 | À surveiller | 3 | À surveiller |
| **Score sur les critères mesurés** | 85 | **63 → 74/100** | | **63 → 74/100** | |

**Lecture provisoire** : **égalité (74 / 74)**. La règle de décision exige **+15 points** pour Nix : elle n'est pas atteinte, **Nix reste en veille** sauf si les mesures restantes le départagent nettement (B-1 sur 2 hôtes, B-5 en pod userns). Les deux approches ont des forces complémentaires :
- **Nix** l'emporte sur la reconstruction offline complète, toolchains et image incluses ;
- **la référence** l'emporte sur l'exploitabilité du SBOM et sur le coût.

## Constat de sécurité : fermeture Go restaurée depuis une archive

Le replay rejoue un build des années plus tard à partir de la fermeture archivée. Il faut donc qu'une fermeture **altérée** fasse échouer le build. Tests de [`reference/hermeto.sh`](../reference/hermeto.sh) :

| Test | Configuration | Résultat |
|---|---|---|
| T1 | Zip de chi complété par un fichier Go qui affiche `ALTERE`, environnement de `hermeto generate-env` (`GOMODCACHE` = la fermeture) | **`go build` réussit et le binaire contient le code injecté.** Go se fie au fichier `.ziphash` du cache au lieu de recalculer l'empreinte. Seul `go mod verify` détecte l'altération (« zip has been modified ») |
| T2 | Même altération, fermeture servie en `GOPROXY=file://…` en lecture seule, `GOMODCACHE` vierge | **Refusé** : « checksum mismatch » contre `go.sum` |
| T3 | Archive npm reconstruite avec un fichier modifié | **Refusé** : intégrité sha512 du lockfile |

Le build sain donne le **même binaire** dans la configuration de T2 que dans celle de Hermeto. De plus, avec l'environnement de `generate-env`, le build **écrit dans la fermeture** (`GOCACHE`, modules extraits), ce qui est un vecteur d'empoisonnement si elle est partagée.

**Contrôles retenus pour les briques 03 et 04 :**
1. fermeture tirée de Zot **par digest**, digest inscrit dans `resolvedDependencies`, montée en **lecture seule** ;
2. Go : fermeture servie en `GOPROXY`, `GOMODCACHE` et `GOCACHE` vierges à chaque build, `GOFLAGS=-mod=readonly`, `GOTOOLCHAIN=local` ; **jamais l'environnement de `generate-env` tel quel** ;
3. `go mod verify` en étape de la tâche de build de confiance (défense en profondeur) ;
4. npm : l'intégrité du lockfile suffit (T3). **À refaire pour chaque gestionnaire** (yarn berry pour Traefik, pip, cargo, rpm) en brique 03.

**Enseignements utiles même si Nix n'est pas retenu :**
- La fermeture de référence doit **inclure les toolchains** : image de build archivée par digest, ou toolchains en artefacts OCI. Sinon le replay dans 10 ans n'est pas garanti.
- Le SBOM doit décrire **l'artefact réellement construit**. Un SBOM issu des seuls lockfiles rate les toolchains ; un SBOM d'image rate les dépendances embarquées (`marked`) ; le SBOM Hermeto liste la bibliothèque standard Go sans version. Il faut **combiner** le SBOM de fermeture (Hermeto) et celui de l'artefact (Syft), en filtrant le bruit.
- Le **mode de dépendances Go** (module ou vendor) change le binaire : c'est un paramètre de build à figer et à inscrire dans la provenance.
- Derrière un **proxy TLS d'entreprise**, les fetchers qui embarquent leur propre bundle de CA posent problème : c'est à prévoir pour Hermeto et les autres outils de prefetch.
