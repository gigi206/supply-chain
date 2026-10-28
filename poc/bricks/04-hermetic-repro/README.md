# Brique 04 : build hermétique et reproductible (partie locale)

Seuil (README, brique 04) :
- 0 connexion sortante ;
- 2 builds donnent le même sha256 (binaire Go, image) ;
- une fermeture altérée fait refuser le build, pour chaque gestionnaire.

## Montage

- **BuildKit 0.25.2 en démon éphémère**, avec runc 1.3.3 (nixpkgs épinglé), en root dans la VM de développement, **sans Docker** : worker OCI, snapshotter `native`. Sur la plateforme, il y aura un démon par TaskRun (`buildctl-daemonless`).
- **Image de build construite par la plateforme** ([`Dockerfile.builder`](Dockerfile.builder)) :
  - toolchain Go 1.26.10 officielle, téléchargée comme module `golang.org/toolchain` et vérifiée par sum.golang.org ;
  - busybox 1.36.1 statique ;
  - aucune image de base externe (`FROM scratch`).

  C'est une version réduite de la brique 11.
- **Build de sample-app** ([`Dockerfile`](Dockerfile)) :
  - l'image de build est un **contexte nommé épinglé par digest** (`oci-layout://builder@sha256:…`) ;
  - la fermeture Hermeto est un contexte nommé monté en lecture seule et servie en `GOPROXY` ;
  - la compilation tourne avec `RUN --network=none` ;
  - l'image finale part de `scratch`, avec un utilisateur non root.
- Réglages de reproductibilité : `SOURCE_DATE_EPOCH=0`, sortie OCI avec `rewrite-timestamp=true`, `--no-cache` à chaque build.

## Résultats ([`bench.sh`](bench.sh), journal : [`resultats/bench.log`](resultats/bench.log))

| Test | Résultat |
|---|---|
| Image de build, 2 builds | **Identique** (`sha256:bdd56bab…`) |
| **Image sample-app, 2 builds sans cache depuis 2 chemins** | **Identique** (`sha256:3a7ca1b1…`). Mêmes digests à l'exécution suivante du banc, soit 4 builds identiques |
| Binaire extrait de l'image comparé au binaire de la brique 03 (même toolchain, compilé hors BuildKit sous `unshare -rn`) | **Identique** (`e3749c68…`) : le résultat ne dépend pas de l'environnement d'exécution |
| Négatif : build sans fermeture | **Refusé** : aucun module disponible, la fermeture est la seule source |
| Négatif : sortie réseau depuis une étape `--network=none` | **Refusée** (`wget: bad address`) |
| Fermeture altérée (zip Go, archive npm) | **Refusée** : banc B, [`reference/hermeto.sh`](../../benchmarks/nix/reference/hermeto.sh) ; blob altéré dans le registre : brique 03 |

Durée du banc : ≈ 2 min (4 builds sans cache, dont 2 de l'image de build).

## Constats

- **Le binaire ne dépend que des entrées** (toolchain, fermeture, sources, options) : même sha256 dans BuildKit et hors BuildKit. C'est ce que le replay indépendant (brique 10) exploitera : un autre domaine d'administration peut rebâtir avec un autre moteur et comparer.
- L'**image de build** doit être construite par la plateforme et épinglée par digest. Une image de base prise sur un registre public devient une entrée non maîtrisée.
- L'interface npm est construite hors ligne mais **hors de BuildKit**, avec le Node de l'hôte. Pour que Node vienne aussi d'une image archivée, l'image de build devra embarquer Node (2c, brique 11).
- Le démon tourne ici **en root, avec le réseau de l'hôte par défaut** ; le blocage réseau tient à `--network=none` par étape. Sur la plateforme, il faudra en plus une NetworkPolicy deny-all sur le pod de build et une isolation (rootless avec seccomp/AppArmor, ou Kata).

## Reste à faire sur le laptop

- BuildKit **en pod** (rootless, ou Kata) dans une tâche Tekton, avec push dans une tâche séparée ; sujets et `resolvedDependencies` de la provenance Chains (B-5, brique 08).
- **2 hôtes à ≥ 1 h d'écart** (B-1 complet), puis le replay indépendant (brique 10).
- Traefik : gomod + yarn berry, interface construite dans l'image de build.
