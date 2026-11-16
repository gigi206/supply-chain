# Packaging de sample-app (rpm et deb)

Recettes communes aux constructeurs de paquets du PoC :
- banc A2 : OBS ;
- brique 05 : mock pour rocky-9 ;
- brique 06 : sbuild pour debian-13.

| Fichier | Rôle |
|---|---|
| [`sources.sh`](sources.sh) | Prépare les sources (`mise run packaging:sources`), voir ci-dessous |
| [`sample-app.spec`](sample-app.spec) | rpm. `Release: 1%{?dist}`, pas de paquet debuginfo (binaire Go statique, déjà sans symboles) |
| [`debian/`](debian/) | deb, format `3.0 (quilt)`, debhelper 13. `SOURCE_DATE_EPOCH` vient de `debian/changelog` |

## Préparation des sources

`sources.sh` produit les sources dans `~/.cache/supply-chain-poc/packaging/`, de façon reproductible : deux passages donnent les mêmes sha256.

L'archive `sample-app-1.0.0.tar.gz` contient :
- le contenu de `poc/sample-app` au dernier commit qui le touche (`git archive`) ;
- les modules Go dans `vendor/`, vérifiés par `go.sum` (`go mod verify`) ;
- la bibliothèque npm `marked` dans `web/node_modules/marked`. L'intégrité sha512 du tarball est comparée à celle de `package-lock.json`.

La même archive sert d'archive amont Debian (`sample-app_1.0.0.orig.tar.gz`). `dpkg-source` construit à partir d'elle le paquet source (`.dsc` et `.debian.tar.xz`).

## Build hors ligne

Le build ne télécharge rien :
- Go : `GOPROXY=off`, `GOFLAGS=-mod=vendor -buildvcs=false -trimpath` et `GOTOOLCHAIN=local` ;
- web : `node build.mjs` copie `marked` et la page, sans npm.

Compilateurs utilisés :

| Distribution | Go | Node |
|---|---|---|
| Rocky 9.7 | `golang` 1.25.x | `nodejs` 16, version non modulaire par défaut |
| Debian 13 | `golang-go` 1.24 | `nodejs` 20 |

## Reproductibilité

Les réglages rpm suivants relèvent du constructeur, pas du spec :
- `%_buildhost` ;
- `%source_date_epoch_from_changelog` ;
- `%use_source_date_epoch_as_buildtime` ;
- `%clamp_mtime_to_source_date_epoch`.

Ils sont fixés dans le prjconf du projet OBS ([`poc/benchmarks/obs/projets/poc.prjconf`](../benchmarks/obs/projets/poc.prjconf)), puis repris dans la configuration de mock.

Les dates des deux changelogs sont celles du commit de sample-app.

## Licences

`Apache-2.0 AND MIT AND BSD-3-Clause` :
- sample-app est sous Apache-2.0 ;
- chi est sous MIT ;
- `marked` combine MIT et BSD-3-Clause : son `LICENSE.md` contient aussi la licence de Markdown.

## Note du 2026-11-16 (écrit à 2026-11-16T21:53:30Z ; rien n'est réécrit)

Le spec passe en `Release: 2%{?dist}` (ligne 11 de ce fichier : `1` jusqu'ici). Il porte les notices de la bibliothèque
standard de Go, liée statiquement : `golang-LICENSE`, `golang-PATENTS` et `golang-NOTICES`, écrits en `%prep` et listés au
`%license` (décision Q1 de la brique 05, [détail](../bricks/05-rpm-mock/resultats/m2-predictions.md)). L'entrée 1.0.0-2, en tête du
changelog du spec, est datée du 16/11/2026 ; l'entrée 1.0.0-1 garde sa date. La phrase « Les dates des deux changelogs sont
celles du commit de sample-app » ne vaut donc plus pour l'entrée de tête du rpm (pour le deb, voir le commentaire de `SDE_DEB` dans
[`sources.sh`](sources.sh)). La copie du spec dans le cache attend un nouveau passage de
`mise run packaging:sources`.
