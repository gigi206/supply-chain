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
