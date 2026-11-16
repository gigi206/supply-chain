# Brique 06 : les trois tags `I:` de lintian restants sur 1.0.0-2 (fiche de faits, écrit à 2026-11-16T19:33:32Z)

Fiche préparée pendant l'attente de M5, sans rien lancer ni modifier : ni `poc/packaging`, ni les scripts de la 06, ni le cluster.
Elle rassemble les faits utiles à la décision du propriétaire et ne recommande rien. Toute recommandation sera relue par le
conseiller avant d'être présentée.

## Source des faits

- Les tags viennent de [`lintian-juger.log`](lintian-juger.log) (lancé le 16/11/2026 à 17:20:10 UTC). `lintian -I` rend **trois**
  lignes `I:` sur le `.dsc` 1.0.0-2. Sans `-I`, il n'en rend aucune. Ce sont les trois lignes que 1.0.0-1 portait déjà, hors
  `missing-static-built-using-field-for-golang-package`.
- Les descriptions sont lues dans lintian 2.122.0, celui du verrou, déjà installé sous `~/.cache/supply-chain-poc/06/lintian/chroot`.
  Les trois tags sont de sévérité `info`.
- `pkg-info.mk` et `deb-src-control(5)` viennent de dpkg-dev 1.22.22, lus dans ce même chroot. Ce chroot part de la racine de S1,
  le même instantané que le chroot de build.

| Fichier lu (dans le chroot) | sha256 |
|---|---|
| `/usr/share/lintian/tags/d/debian-rules-parses-dpkg-parsechangelog.tag` | `f4f37b34188b6bf4ffb62a39bc895ee306b2afb8d93e54cd36ed0711c7ddb742` |
| `/usr/share/lintian/tags/d/debian-watch-file-is-missing.tag` | `2a3e52e2f1b1111a03fa6f281c1321badfa7f72edecfe30931a2847bf7ac1fed` |
| `/usr/share/lintian/tags/m/missing-xs-go-import-path-for-golang-package.tag` | `56e070cf976117e2ebfdde4d53379f921d420aa5c4b01a826e416cfb628c9ce3` |
| `/usr/share/dpkg/pkg-info.mk` (dpkg-dev 1.22.22) | `30c14fe4372820142361c37aa360518d5e8e178a8289c598d1617d975216a0af` |
| `/usr/share/man/man5/deb-src-control.5.gz` | `9ef9e49ba1d0ec8f55c67c99ea0cb1aadcd0b1f7930d0e7deb6096dd6ba1902a` |

## 1. `debian-rules-parses-dpkg-parsechangelog [debian/rules:10]`

- Ligne 10 de `poc/packaging/debian/rules` : `VERSION := $(shell dpkg-parsechangelog -SVersion | sed 's/-[^-]*$$//')`. Cette valeur
  est passée au binaire par `-X main.Version=$(VERSION)`.
- Le tag propose d'inclure `/usr/share/dpkg/pkg-info.mk` et d'utiliser ses variables.
- `pkg-info.mk` a été lu en entier. Hors commentaires, il ne fait que définir des variables `DEB_*`, toutes évaluées à la demande
  (`dpkg_late_eval`). La seule autre action est `SOURCE_DATE_EPOCH ?= $(DEB_TIMESTAMP)` suivi de `export SOURCE_DATE_EPOCH` : la
  variable n'est posée que si elle est absente. Le commentaire de `rules` (l. 3) dit que dpkg la fournit déjà depuis le changelog.
  Ce n'est pas mesuré ici.
- `DEB_VERSION_UPSTREAM` applique le même `sed 's/-[^-]*$$//'` à `dpkg-parsechangelog -SVersion`, puis retire l'epoch
  (`s/^[0-9]*://`). La version `1.0.0-2` n'a pas d'epoch. Lu dans le texte, les deux formes rendent donc la même chaîne, `1.0.0`.
  Ce n'est pas mesuré par un build : que le binaire reste identique n'est pas éprouvé.

## 2. `debian-watch-file-is-missing`

- `debian/source/format` vaut `3.0 (quilt)` : le paquet n'est pas natif, d'où le tag.
- L'amont est ce dépôt (`Homepage: https://github.com/gigi206/supply-chain`). L'archive d'origine est fabriquée par `sources.sh`
  à partir du dépôt. La copie locale ne porte aucun tag git (`git tag -l` : 0) et ses références distantes ne sont que des
  branches. L'absence de version publiée chez GitHub n'est pas vérifiée : rien n'a été lu en ligne.
- Pour un amont qu'uscan ne peut pas suivre, le texte du tag propose un `debian/watch` qui ne contient que des commentaires
  expliquant la situation.

## 3. `missing-xs-go-import-path-for-golang-package`

- `debian/control` ne déclare pas `XS-Go-Import-Path`. Le module de `poc/sample-app/go.mod` est `example.com/supply-chain/sample-app`.
- La recommandation retenue le 12/11 (« Oui, je retiens ») exclut dh-golang. Pour un paquet sans dh-golang, le texte du tag
  propose un chemin d'import fictif. Il cite comme usages dh-make-golang et la CI de l'équipe Go de Debian. `git grep` ne trouve
  ni `dh-make-golang`, ni `go-team`, ni `XS-Go` dans le dépôt, hors des journaux de lintian.
- Selon `deb-src-control(5)` du chroot (section « USER-DEFINED FIELDS »), la lettre `S` copie le champ dans le contrôle du paquet
  source (`.dsc`), la lettre `B` dans celui du paquet binaire. Un champ `XS-` irait donc au `.dsc` seul. C'est lu dans la
  documentation, pas mesuré sur un build.

## Qui lit lintian

- Aucun build ne lance lintian. Le build de la tâche Tekton, S1, S3, S5 et le rejeu passent tous `--no-run-lintian` à sbuild
  (`deb/construire-deb.yaml` l. 105, `s1.sh` l. 249, `s3.sh` l. 196, `s5.sh` l. 523, `rejeu/rebuild_deb.sh` l. 136).
- Hors de la 06, `git grep -i lintian` ne trouve que `docs/04-sante-projets.md`, `tools/health/projects.tsv`, un commentaire de
  `poc/packaging/debian/rules` (l. 30) et une prédiction de la 13a. Aucune porte ni politique ne le lit.
- Verdict de docs/04 (l. 144) : « À surveiller, hors chemin critique ».

## Ce que coûterait une modification (projection)

Le seul précédent archivé est la révision 1.0.0-2 ([`revision-predictions.md`](revision-predictions.md)). Une modification de
`poc/packaging/debian/` (rules, watch, control) en ferait une nouvelle. Par analogie, elle rouvrirait la même cascade : sources,
build, mesures, provenance, rejeu et VSA. C'est une projection, pas une mesure. La cascade de 1.0.0-2 n'est pas finie : M5 à M8
et la ligne 12 restent.

## Décision du propriétaire (note du 2026-11-16, écrit à 2026-11-16T21:15:12Z ; rien n'est réécrit)

Une recommandation, retouchée sur relecture du conseiller, a été présentée le 16/11/2026 avec la question « Pas de révision dédiée pour les trois tags I: de lintian ? ».
Réponse : « Oui, pas de révision ».

**Décision : pas de révision dédiée.** `poc/packaging/debian/` reste en 1.0.0-2 (première ligne du changelog lue à l'écriture
de cette note) et les trois tags `I:` restent.

Motifs de la recommandation présentée (la réponse ne porte que sur la question) :
- les trois tags n'ajoutent rien au contenu ni à la provenance du deb, lu dans leurs textes et non mesuré (pour le tag 1, que
  le binaire reste identique n'est pas éprouvé par un build) ; au contraire, le champ de
  `missing-static-built-using-field-for-golang-package` est lu par la 13a (`paquets.py`) ;
- lintian est hors chemin critique et aucun build ne le lance.

Piste de la recommandation, non décidée : si une autre raison impose un jour une révision, 1 et 2 pourraient y être joints
(1 éprouvé d'abord par un banc hors réseau, binaire au bit près ; 2 en commentaires seuls, forme que propose le texte du tag),
et le choix pour 3 se ferait à cette révision.

La section « Ce que coûterait une modification » disait la cascade de 1.0.0-2 inachevée : elle est finie depuis (ligne 12,
commit `c9d73eb`).
