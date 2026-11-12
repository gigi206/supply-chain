# Brique 13a, volet rpm/deb : protocole et prédictions de l'étape `deb` (12/11/2026, avant tout lancement)

**Ouverture.** Question posée : « J'ouvre le volet rpm/deb des licences maintenant ? » ; réponse du propriétaire : « Oui, ouvre-le »
(reçue après le `date -u` de 19:34:52 UTC). Ce fichier est écrit avant tout lancement de l'étape `deb` ; elle attend un accord nommé.

## Ce que le volet doit couvrir (docs/03, ligne « Licences » ; README de 13a, « Reste à faire »)
- licences des métadonnées des paquets construits, normalisées en SPDX (DEP-5 pour le deb, champ `License` pour le rpm) ;
- `.dsc` et SRPM en referrer dans Zot ;
- tâche de confiance signée dans Tekton.

**Premier pas, seul préparé ici** : le deb, sur l'hôte, sans réseau, ni cluster, ni Zot, ni VM. Le rpm attend le premier rpm de la
05 (S1, après S5b). Les referrers écrivent dans Zot : après S5b, sur accord à part. Le `.dsc` du cache
(`~/.cache/supply-chain-poc/packaging/`, sha256 `9050679e…`, celui du banc A2) n'est pas celui de la pipeline de la 06
(`s4d.sh` 232 : le `.dsc` y diffère) : à trancher à l'étape des referrers.

## Étape `deb` de [`paquets.sh`](../paquets.sh)
1. Le deb des deux builds de S3 de la 06 (`s3-comparaison.log` : `0b489d43…`, mêmes octets que le deb du banc A2) est lu dans
   `~/.cache/supply-chain-poc/08/travail/s3-06/build-1/` ; sha256 épinglé dans le script, sinon KO.
2. [`paquets.py`](../paquets.py) le lit sans rien extraire sur disque ni exécuter : membres ar exigés dans l'ordre
   (`debian-binary` à « 2.0 », `control.tar.xz`, `data.tar.xz`), `./control`, puis `./usr/share/doc/<Package>/copyright`, fichier
   ordinaire exigé.
3. Analyse DEP-5 1.0 : en-tête `Format` exigé (sinon NOASSERTION) ; `Files`, `Copyright` et `License` exigés dans chaque paragraphe
   `Files` ; texte présent pour chaque licence nommée ; « and » / « or » réécrits en `AND` / `OR` ; « with » et la virgule refusés
   (non traités, jamais devinés) ; aucun nom DEP-5 traduit (`Expat`, `GPL-2+`… restent tels quels). Expression du paquet : AND des
   paragraphes `Files`. Sortie : SBOM CycloneDX à un composant, `pkg:deb/debian/<nom>@<version>?arch=<arch>`.
4. Verdict par [`licences.py`](../licences.py), même [politique](../policy.json), liste SPDX 3.27.0 du nixpkgs épinglé ; prédicat
   archivé dans `paquets-deb.licences.json`.
5. Comparaison du copyright du deb avec `poc/packaging/debian/copyright` (écart nommé, sans arrêt).
6. Quatre témoins négatifs, copyright synthétiques écrits par l'étape : GPL (refus de la politique), sans `Format` (NOASSERTION),
   paragraphe sans `License` (refus de l'analyse), `Expat` (identifiant invalide).

**Lu avant d'écrire ces prédictions** (à ne pas compter comme mesure) :
- `licences.py` compare les opérateurs sans la casse (`peek().upper() == op`, ligne 60) : un « and » minuscule est accepté et
  réécrit en `AND`. La prédiction du brouillon (« refusé sans normalisation ») était fausse ; elle n'est pas reprise.
- Les membres ar du vrai deb ont été listés à sec (noms et tailles seulement) : `debian-binary`, `control.tar.xz`, `data.tar.xz`.
- Le banc fabrique un deb dont le copyright est `poc/packaging/debian/copyright` : l'expression qu'en tire `paquets.py` est donc
  connue ; ce qui reste à mesurer, c'est le copyright **du deb construit**.

## Banc hors réseau
[`paquets-essai-local.sh`](paquets-essai-local.sh) ([journal](paquets-essai-local.log)) : debs synthétiques (ar et tar.xz par python3),
copie de `paquets.sh` avec `DEB_SHA`, `R` et `T` remplacés. Neuf cas au code attendu : nominal (0) ; copyright GPL, copyright en lien
symbolique, copyright absent, `data.tar.zst`, membre ar en plus, sha256 différent (1) ; puis deux cas où les témoins échouent pour
une autre raison, qui doivent donner KO (1) : trace Python de `paquets.py` en mode `dep5`, motif attendu changé. Chaque témoin a son
étage (analyse ou politique) et son motif attendus ; tout autre échec est un KO (sur relecture du conseiller : la première version
comptait tout code non nul comme un refus). Rien n'est écrit dans `resultats/` ni dans `chrono.tsv` de 13a. Non couverts : un
`control.tar.zst`, un DEP-5 à virgules ou à « with », un copyright non UTF-8. Limites de l'analyse, refus fermés ou oublis
connus : un DEP-5 valide dont `Files:` ou `Copyright:` commence par une ligne vide (valeur sur les lignes suivantes) est refusé ;
un champ `License` du paragraphe d'en-tête est ignoré.

## Prédictions
| # | Prédiction | Confiance |
|---|---|---|
| P1 | Le deb du cache a le sha256 épinglé `0b489d43…` | Haute : `s3-comparaison.log` ; même valeur relevée à sec dans le cache |
| P2 | `control` : `sample-app` `1.0.0-1` `amd64` ; membres ar dans l'ordre exigé | Haute : membres listés à sec ; `control` non lu |
| P3 | Le copyright du deb est identique à `poc/packaging/debian/copyright` (`20c9dd35…`) | Haute : `dh_installdocs` le copie ; fichier inchangé depuis 4b9722e (29/10), avant S3 (10/11) |
| P4 | Expression du paquet `Apache-2.0 AND MIT AND (MIT AND BSD-3-Clause)` ; 0 erreur, 0 NOASSERTION, 0 invalide | Haute si P3 tient (banc sur le même texte) |
| P5 | Les quatre témoins sont refusés, comme au banc | Haute |

## Ce que l'étape ne mesure pas
- les licences **conclues** : rien ne vérifie que les trois paragraphes couvrent tous les fichiers du paquet (ScanCode, brique 13b) ;
- les licences des paquets du buildroot (Debian ou EL9), ni `fedora-license-data` (sans verdict au doc 04) ;
- l'espace de noms `debian` du purl désigne la distribution cible, pas l'éditeur : notre paquet n'est pas un paquet Debian.

## Estimation
Premier pas (deb, hors cluster) : ~0,2 pw. Volet complet (rpm, referrers, tâche signée) : dans les ~7 pw de la phase Packaging
(README, ligne 75 ; 05, 06, 09, 13a).

## Résultats de `deb` : lancement le 12/11/2026 à 19:43:12 UTC, fin à 19:43:13 UTC (`chrono.tsv`), code 0

Accord : « Oui, lance deb » à « Je lance deb ? (paquets.sh, commit c444a8b) » ; HEAD c444a8b, arbre propre, contrôlés à 19:43:10 UTC.
Journal : [`paquets-deb.log`](paquets-deb.log) ; prédicat : [`paquets-deb.licences.json`](paquets-deb.licences.json). Résultats écrits à
partir de 19:43:35 UTC.

| # | Résultat |
|---|---|
| P1 | **Tenue.** sha256 du deb `0b489d438370ddb6…` égal à l'épinglé, 1 952 080 octets |
| P2 | **Tenue.** `control` : `sample-app` `1.0.0-1` `amd64` ; membres ar dans l'ordre exigé (sinon `paquets.py` aurait refusé) |
| P3 | **Tenue.** Copyright du deb : sha256 `20c9dd35…`, 3 333 octets, identique à `poc/packaging/debian/copyright` |
| P4 | **Tenue.** DEP-5 1.0, 6 paragraphes, 3 paragraphes `Files` ; expression `Apache-2.0 AND MIT AND (MIT AND BSD-3-Clause)` ; `licences.py` code 0 : 0 erreur, 0 avertissement, 0 NOASSERTION, 0 invalide, liste SPDX 3.27.0 |
| P5 | **Tenue.** Les quatre témoins sont refusés à l'étage et au motif attendus : `t-gpl` (deny), `t-sans-format` (NOASSERTION), `t-sans-license` (analyse : champ manquant), `t-expat` (identifiant SPDX inconnu) |

- Le prédicat porte le sha256 de la politique calculé par `licences.py` sur son JSON trié (`b9f47d89…`) ; le journal donne celui du
  fichier (`dc284d67…`) : deux calculs du même fichier, pas un écart.
- Ce qui est établi : la licence **déclarée** du deb construit, lue dans le paquet lui-même, est conforme à la politique de 13a.
  Rien n'établit que les trois paragraphes couvrent tous les fichiers du paquet (licences conclues : 13b).
- Suite du volet : rpm après S1 de la 05 ; `.dsc` et SRPM en referrer après S5b (accord à part) ; tâche de confiance signée.

## Étape `modules` (ajoutée à sec le 12/11/2026 après le passage de `deb`, sur « continue »), NON LANCÉE

**Pourquoi.** `deb` établit la licence **déclarée** par le copyright. Le binaire Go dit lui-même ce qui y est compilé : ses
informations de build (module principal, dépendances, version de Go, réglages) restent lisibles malgré `-s -w -trimpath`. Les
rapprocher des paragraphes `Files` vérifie que chaque dépendance compilée a une licence déclarée qui lui est propre.

**Ce que fait l'étape** ([`paquets.sh`](../paquets.sh) `modules`, [`paquets.py`](../paquets.py) `modules`) : hôte seul, sans réseau ;
même deb, sha256 épinglé ; chaque fichier de `./usr/bin` est lu en mémoire, jamais exécuté ; en-tête `\xff Go buildinf:` exigé une
seule fois, au format de go1.18 et après (sinon refus) ; pour chaque dépendance, le **dernier** paragraphe `Files` qui couvre
`vendor/<module>/…` s'applique, comme en DEP-5 : KO s'il n'y en a pas, ou si seul `Files: *` la couvre (elle prendrait la licence du
projet) ; un paragraphe `vendor/` sans module compilé est un ÉCART ; la bibliothèque standard de Go, compilée mais hors des sources
donc hors du copyright, est toujours un ÉCART, avec le champ `Built-Using` du `control`. Témoin : le même deb, copyright privé du
paragraphe de `chi`, réécrit dans le dossier de travail (0700, effacé à la fin) : il doit donner un KO sur `chi`.

**Banc hors réseau** ([`paquets-modules-essai-local.sh`](paquets-modules-essai-local.sh), [journal](paquets-modules-essai-local.log)) :
un programme Go à une dépendance vendorisée, compilé avec le Go 1.24.7 de mise (`GOPROXY=off`, options de `debian/rules`) ;
`paquets.py` lit les mêmes path, mod, dep, version de Go et nombre de réglages que `go version -m` ; six debs synthétiques au code et
au motif attendus : dépendance vendorisée sous le nom de `chi` avec le copyright du dépôt et `TEMOIN_DEP` d'origine (0 : `chi` couverte,
témoin refusé ; c'est le texte réel sur lequel le témoin tournera, P3 l'ayant mesuré identique à celui du deb), nominal 0, sans
paragraphe propre 1, paragraphe orphelin 0 avec ÉCART, script sans informations de build 1, en-tête en double 1 (cas `chi` ajouté sur
relecture du conseiller). Le banc de `deb`, rejoué après ces changements, reste à neuf cas tenus ([journal](paquets-essai-local.log)).
Non couverts : un remplacement de module (`=>`, refusé sans être essayé), le format d'avant go1.18, un binaire non Go dans `./usr/bin`
d'un vrai paquet.

**Lu avant de prédire** : `go.mod` de sample-app (`require github.com/go-chi/chi/v5 v5.2.3`, seule dépendance) ; `s3-build-1.buildinfo`
de la 06 (`golang-1.24-go (= 1.24.4-1)`) ; `debian/control` du dépôt (pas de `Built-Using`) ; `debian/rules` (`-mod=vendor -trimpath`,
`-ldflags "-s -w -buildid= -X main.Version=…"`). Le contenu de `./usr/bin` du vrai deb n'a été listé que par noms et tailles.
Mesuré au banc, sur relecture du conseiller : avec `-trimpath`, Go 1.24.7 n'enregistre pas `-ldflags` ; les 7 réglages sont
`-buildmode=exe`, `-compiler=gc`, `-trimpath=true`, `CGO_ENABLED=0`, `GOARCH=amd64`, `GOOS=linux`, `GOAMD64=v1`.

| # | Prédiction | Confiance |
|---|---|---|
| M1 | Un seul fichier dans `./usr/bin` (`sample-app`), informations de build lisibles au format de go1.18 et après | Haute |
| M2 | Version de Go `go1.24.4` (golang-1.24 de Debian 13 au build de S3) | Moyenne : la chaîne exacte n'est pas lue |
| M3 | `path` et `mod` `example.com/supply-chain/sample-app` ; une seule dépendance, `github.com/go-chi/chi/v5 v5.2.3` | Haute : go.mod |
| M4 | `chi` couverte par le paragraphe `vendor/github.com/go-chi/chi/v5/*` (MIT) : OK, aucun paragraphe orphelin | Haute |
| M5 | ÉCART de la bibliothèque standard, `Built-Using` absent | Haute |
| M6 | Les réglages de build portent `-trimpath=true` et `CGO_ENABLED=0`, et pas `-ldflags` (non enregistré avec `-trimpath`) | Moyenne : mesuré avec go1.24.7 au banc, pas avec go1.24.4 |
| M7 | Le témoin sans paragraphe de `chi` donne un KO sur `chi` | Haute |

**Limites de l'analyse** : un paragraphe large (`Files: vendor/*`, ou une liste qui contient `*` et d'autres motifs) compte comme
propre pour toute dépendance qu'il couvre ; un `control` sans `Package` donne une trace Python au lieu d'un REFUS (code 1 : refus
fermé quand même).

**Ce que l'étape ne mesure pas** : les paquets npm intégrés à `web/dist` (`marked`), invisibles dans les informations de build de Go ;
la licence de la bibliothèque standard elle-même (seule sa présence est constatée) ; ce que Debian attend pour elle (`Built-Using`,
`Static-Built-Using`), non relu.

## Résultats de `modules` : lancement le 12/11/2026 à 19:53:09 UTC, fin à 19:53:11 UTC (`chrono.tsv`), code 0

Accord : « Oui, lance modules » à « Je lance modules ? (paquets.sh, commit ce49cf0) » ; HEAD ce49cf0, arbre propre, contrôlés à
19:53:09 UTC. Journal : [`paquets-modules.log`](paquets-modules.log). Résultats écrits à partir de 19:53:28 UTC.

| # | Résultat |
|---|---|
| M1 | **Tenue.** Un seul fichier dans `./usr/bin` : `sample-app`, 5 906 320 octets, sha256 `10d475d0…` ; informations de build lues (en-tête unique, format de go1.18 et après) |
| M2 | **Tenue.** `go1.24.4` |
| M3 | **Tenue.** `path` `example.com/supply-chain/sample-app`, `mod` le même en `(devel)` ; une seule dépendance, `github.com/go-chi/chi/v5 v5.2.3` (sans somme : build en `-mod=vendor`) |
| M4 | **Tenue.** `chi` couverte par `vendor/github.com/go-chi/chi/v5/*` (MIT) ; aucun paragraphe `vendor/` orphelin |
| M5 | **Tenue.** ÉCART de la bibliothèque standard de go1.24.4, `Built-Using` absent du `control` |
| M6 | **Tenue.** 7 réglages : `-buildmode=exe`, `-compiler=gc`, `-trimpath=true`, `CGO_ENABLED=0`, `GOARCH=amd64`, `GOOS=linux`, `GOAMD64=v1` ; pas de `-ldflags` |
| M7 | **Tenue.** Témoin sans le paragraphe de `chi` (retiré une fois) : KO sur `chi`, couverte par `Files: *` seul |

- Ce qui est établi : la seule dépendance Go compilée dans le deb a une licence déclarée qui lui est propre (MIT).
- Reste ouvert, sans décision : la bibliothèque standard de Go est compilée dans le binaire sans être déclarée nulle part dans le
  paquet (ni copyright, ni `Built-Using`). Que faire (champ `Built-Using` ou `Static-Built-Using` dans `debian/control`, mention dans
  le copyright, ou rien) est à décider avec le propriétaire ; la convention de Debian n'est pas relue. `marked` (npm, dans
  `web/dist`) n'est pas vu par cette étape.

**Note datée du 12/11/2026, écrite à 19:58:04 UTC : Décision du 12/11/2026 sur la bibliothèque standard de Go.** Elle complète, sans le réécrire, « la convention de Debian
n'est pas relue » des résultats de `modules`.
- **Lu ce soir** : Policy 4.7.4.1, §7.8 (`Built-Using` réservé aux licences qui imposent de garder les sources incorporées, pas au
  suivi des reconstructions) ; §2.3 (notices des fichiers compilés dans le binaire à reprendre dans `copyright` quand la licence
  l'exige) ; `deb-control(5)` de dpkg 1.22.22 (`Static-Built-Using`, depuis dpkg 1.21.3, pour les liaisons statiques dont Go) ; tag
  lintian `missing-static-built-using-field-for-golang-package` (info) ; `debian/copyright` de hugo dans trixie, lu en partie, sans
  mention de la bibliothèque standard. Clause de redistribution binaire de la LICENSE de Go lue dans le Go 1.24.7 de mise, pas dans
  le `golang-1.24` 1.24.4-1 qui a compilé le deb. Aucune conclusion de conformité juridique : elle revient au propriétaire.
- **Options proposées** : (1) `Static-Built-Using` dans `debian/control` ; (2) notice de Go dans le paquet ; (3) composant
  « bibliothèque standard » dans le prédicat de licences de 13a, sans toucher au deb ; (4) ne rien faire.
- **Question** : « Quel ordre retiens-tu pour la bibliothèque standard de Go ? » ; **réponse du propriétaire** : « Axe 3, puis 1+2 ».
- **Conséquence** : l'axe 3 se prépare maintenant (prédictions, banc, accord nommé) ; les axes 1 et 2 iront ensemble dans une seule
  révision du paquet, **après S5b** (`poc/packaging/` est lu par `s4c.sh` et comparé par `s4d.sh` ; le changer change le deb
  `0b489d43…` et le sujet du rebuild, de la VSA et de S5b), avec les mesures de la 06 à refaire une fois ; le spec du rpm suivra la
  même décision avant son premier build.

## Étape `stdlib` (axe 3, décision « Axe 3, puis 1+2 »), ajoutée à sec le 12/11/2026, NON LANCÉE

**Ce que fait l'étape** ([`paquets.sh`](../paquets.sh) `stdlib`, [`paquets.py`](../paquets.py) `stdlib`) : hôte seul, sans réseau, le
deb n'est pas modifié. Le paquet `golang-1.24-src_1.24.4-1_all.deb` de la fermeture restaurée de S3 de la 06 (build 1) a son sha256
épinglé (`c396bc2c…`), recoupé avec `poc/packaging/verrou-deb.txt` et avec la ligne `golang-1.24-src (= 1.24.4-1)` de
`s3-build-1.buildinfo`. `paquets.py stdlib` exige une seule version de Go dans `./usr/bin` du deb, égale à la version amont du
paquet (époque et révision Debian retirées), puis met le copyright DEP-5 de ce paquet en second composant du SBOM
(`pkg:deb/debian/golang-1.24-src@1.24.4-1?arch=all`), à côté du composant du deb. `licences.py` juge les deux. Témoin, joué **avant** l'appel principal : le
deb de l'application à la place du paquet de Go, refus exigé. Un verdict non conforme donne `bilan : KO`, code 1, prédicat archivé tel
quel.

**Analyse souple pour le seul copyright de Debian** (sur relecture du conseiller, avant tout lancement) : pour ce composant, `Files` et
`Copyright` comptent aussi quand leur valeur commence à la ligne suivante (DEP-5 valide), et l'analyse ne s'arrête plus au premier
défaut : chaque paragraphe `Files` est journalisé avec son nom de licence, chaque défaut (« with », virgule, champ manquant, texte
absent) est listé, puis un seul refus en donne le nombre, sans composant écrit. Les modes `deb` et `dep5`, déjà mesurés, gardent
l'analyse stricte. Un seul lancement donne ainsi la liste complète de ce qu'il faudrait traduire ou curer.

**Ce que vaut ce composant** : la licence que Debian déclare pour **tout** le paquet source de la bibliothèque standard, fichiers non
compilés compris (tests, outils) : une borne haute, pas la licence des seuls fichiers compilés dans le binaire.

**Banc hors réseau** ([`paquets-stdlib-essai-local.sh`](paquets-stdlib-essai-local.sh), [journal](paquets-stdlib-essai-local.log)) :
programme Go compilé avec le Go 1.24.7 de mise, faux `golang-1.24-src` ; sept cas au code et au motif attendus : nominal 0 ; époque
`2:` 0 ; version amont différente 1 (refus) ; paquet mal nommé 1 (refus) ; licence `Expat` 1 (verdict non conforme, prédicat archivé) ;
`Files` et `Copyright` à la ligne suivante 0 ; deux défauts dans deux paragraphes 1, les deux listés et journalisés (deux derniers
cas ajoutés sur relecture du conseiller).
Les bancs de `deb` (neuf cas) et de `modules` (six debs) sont rejoués après ces changements, tenus. Non couverts : plusieurs versions
de Go dans `./usr/bin` ; un purl avec époque garde le « : » non encodé (limite, sans effet sur 1.24.4-1).

**Lu avant de prédire** : sha256 du paquet dans la fermeture (deux copies, `c396bc2c…`, 21 182 488 octets) ; membres ar ; noms des
fichiers sous `doc/` : `./usr/share/doc/golang-1.24-src/copyright`, 16 932 octets, **contenu non lu** ; pas de `LICENSE` sous
`./usr/share/go-1.24/` à ce niveau de l'arborescence (filtre de noms, non exhaustif).

| # | Prédiction | Confiance |
|---|---|---|
| S1 | Le paquet a le sha256 épinglé, présent dans le verrou et dans le buildinfo | Haute : relevé à sec |
| S2 | `golang-1.24-src` `1.24.4-1` `all` ; `go1.24.4` du binaire égal à la version amont | Haute (M2) |
| S3 | Le copyright de `golang-1.24-src` est au format DEP-5 1.0 | Moyenne : non lu |
| S4 | L'analyse souple l'accepte (ni « with », ni virgule, texte présent pour chaque licence) ; sinon tous les défauts sont listés | Faible : 16 932 octets, plusieurs paragraphes probables |
| S5 | Si S4 tient : l'expression contient `BSD-3-Clause` (licence du projet Go), et le verdict n'est pas conforme sur au moins un nom DEP-5 hors SPDX ou hors politique : `bilan : KO`, code 1 | Faible |
| S6 | Le témoin est refusé (« n'est pas un paquet golang-X.Y-src ») | Haute |

Un KO à S4 ou S5 est un résultat, pas une panne : il dirait ce qu'il faut traduire ou curer pour déclarer la bibliothèque standard,
sans changer le deb. Rien de ce que l'étape écrit n'est relancé sans nouvel accord.

*Note datée du 12/11/2026, écrite à 20:03:49 UTC* : la limite écrite pour l'étape `deb` (« un DEP-5 valide dont `Files:` ou `Copyright:`
commence par une ligne vide est refusé ») vaut toujours pour les modes `deb` et `dep5` ; elle ne vaut plus pour le composant de la
bibliothèque standard de l'étape `stdlib`, analysé en mode souple (voir cette étape).

## Résultats de `stdlib` : lancement le 12/11/2026 à 20:05:09 UTC, code 1 (`bilan : KO`, attendu par S5), sans ligne « fait »

Accord : « Oui, lance stdlib » à « Je lance stdlib ? (paquets.sh, commit 7cffdb1) » ; HEAD 7cffdb1, arbre propre, contrôlés à
20:05:09 UTC. Dernière ligne du journal à 20:05:11 UTC (`date -u` de la commande) ; `chrono.tsv` n'a pas « 13a paquets stdlib fait » :
le lanceur s'arrête sur le code 1 (`set -euo pipefail`). Journal : [`paquets-stdlib.log`](paquets-stdlib.log) ; prédicat archivé tel
quel : [`paquets-stdlib.licences.json`](paquets-stdlib.licences.json). Résultats écrits à partir de 20:05:55 UTC.

| # | Résultat |
|---|---|
| S1 | **Tenue.** sha256 `c396bc2c…` (21 182 488 octets), présent dans `verrou-deb.txt` et dans `s3-build-1.buildinfo` |
| S2 | **Tenue.** `golang-1.24-src` `1.24.4-1` `all` ; `go1.24.4` du binaire égal à la version amont |
| S3 | **Tenue.** Copyright de `golang-1.24-src` : sha256 `a739b83e…`, 16 932 octets, DEP-5 1.0, 22 paragraphes, dont 14 `Files` |
| S4 | **Tenue.** L'analyse souple l'accepte sans défaut ; trois paragraphes `Files` ont leur valeur à la ligne suivante : l'analyse stricte les aurait refusés (correctif du conseiller décisif) |
| S5 | **Tenue en partie.** Verdict non conforme, `bilan : KO`, code 1 : tenu. « L'expression contient `BSD-3-Clause`, licence du projet Go » : **non tenue telle qu'écrite** ; Debian nomme la licence du projet « Go » (`Files: *` et 6 autres paragraphes) ; `BSD-3-clause` ne couvre que `src/cmd/trace/static/*` |
| S6 | **Tenue.** Témoin refusé avant l'appel principal (« sample-app n'est pas un paquet golang-X.Y-src ») |

**Noms de licence du copyright de Debian**, confrontés à la liste SPDX 3.27.0 et à la politique de 13a (lecture du journal et des
deux fichiers, après le lancement) :
- hors SPDX : `Go` (7 paragraphes, dont `Files: *` et `debian/*`), `FreeBSD` (`src/debug/elf/elf.go`, `src/cmd/link/internal/ld/elf.go`),
  `MPEG` (`src/image/jpeg/idct.go`), `noderivs` (`src/image/png/testdata/pngsuite/*`), `BSD-3-clause-svgpan` (un fichier de pprof) ;
- SPDX mais absent de la politique : `X11` (fichiers de `src/cmd/internal/objabi/`) ;
- SPDX et autorisés : `Apache-2.0` (pprof vendorisé dans `src/cmd`), `BSD-3-clause`.
`licences.py` ne signale que le premier identifiant invalide (`Go`) ; les autres viennent de cette lecture.

**Ce que cela dit, sans décision** :
- La bibliothèque standard n'est pas déclarable telle quelle par la chaîne de 13a : il faudrait, au moins, traduire `Go` (texte de la
  licence non relu ici, à comparer à `BSD-3-Clause`), et traiter les autres noms ou les écarter.
- Plusieurs paragraphes portent sur des fichiers qui ne sont sans doute pas compilés dans `sample-app` (données de test, outils de
  `src/cmd`) : la borne haute surcharge l'expression ; restreindre aux paquets compilés demanderait la liste des paquets du binaire,
  que les informations de build ne donnent pas.
- Le composant du deb reste conforme (`ok`), comme dans `deb`.
- La suite (curation revue au sens de 13a, restriction aux fichiers compilés, autre source de licence) est à décider avec le
  propriétaire ; rien n'est relancé.

## Traduction du nom DEP-5 « Go » (préparée à sec le 12/11/2026 à partir de 20:07 UTC, « Oui, prépare-la »), NON APPLIQUÉE, NON LANCÉE

**Écart avec le message précédent** : ce n'est pas « le mécanisme de curation existant de 13a ». Dans `licences.py`, une curation est
indexée par purl et remplace **toute** l'expression d'un composant ; une curation du seul nom « Go » n'y entre pas (il faudrait aussi
trancher `FreeBSD`, `MPEG`, `noderivs`, `BSD-3-clause-svgpan` et `X11`). Ce qui est préparé est une **traduction par nom**, dans
`paquets.py`, réservée au mode souple (composant de la bibliothèque standard). `licences.py` et `policy.json` ne changent pas. Le README
de 13a place les curations dans un dépôt `ort-config` ; ce fichier-ci, [`traductions-dep5.json`](../traductions-dep5.json), est dans la
brique : écart nommé.

**Règle** : un nom n'est traduit que si (1) l'entrée vise le même paquet et la même version, (2) le sha256 du paragraphe `License`
autonome de ce nom, sous la forme de `texte_licence()` (nom, puis lignes de continuation telles que `paragraphes()` les rend), est égal
à la preuve, et (3) l'entrée est revue (`revue` non vide). Sinon le nom reste tel quel et `licences.py` le refuse. L'étape journalise
pour chaque nom de l'expression : identifiant SPDX ou non, classe dans la politique (le tableau fait à la main après `stdlib` devient
une mesure archivée).

**Lu pour la preuve** (copyright de `golang-1.24-src` 1.24.4-1, paquet au sha256 épinglé ; texte non reproduit ici) :
- un seul paragraphe `License: Go` autonome, 42 lignes de continuation ; preuve `6ce83989…` (calculée par le code de l'étape) ;
- comparaison de mots normalisés (minuscules, ponctuation retirée ; **pas** la correspondance de SPDX) avec `BSD-3-Clause` de la liste
  3.27.0 : mêmes clauses ; écarts : la ligne de copyright, « Google Inc. » dans la clause 3, « OWNER » au lieu de « HOLDER » ; le
  modèle SPDX les couvre (`organizationClause3`, motif lu en entier, 848 caractères, essayé sur la phrase de Go : accepté ;
  `copyrightHolderLiability`, motif `.+`) ;
- **en plus** : une concession de brevets de Google (131 mots), avec résiliation en cas de litige de brevets ; rédaction différente du
  `PATENTS` du Go 1.24.7 de mise (202 mots, ratio de mots 0,72), même nature. Elle n'est pas dans `BSD-3-Clause`.

**Entrée préparée** : `Go` -> `BSD-3-Clause`, `revue: null`. Traduire ainsi laisse la concession de brevets hors de l'expression :
savoir si c'est acceptable est une lecture juridique, au propriétaire. Sa réponse sera la revue ; aucun relecteur n'est écrit avant.

**Banc** ([journal](paquets-stdlib-essai-local.log)) : onze cas au code et au motif attendus, dont quatre de traduction : texte égal à
la preuve et revue (appliquée, 0) ; un mot changé (non appliquée, 1) ; entrée non revue (non appliquée, 1) ; autre version du paquet
(ignorée, 1). Bancs de `deb` (neuf cas) et `modules` (six debs) rejoués, tenus : modes `deb` et `dep5` inchangés.

**Si la traduction est revue puis l'étape relancée** (prédictions, avant tout lancement) :
| # | Prédiction | Confiance |
|---|---|---|
| T1 | `traduction Go -> BSD-3-Clause : appliquée`, texte au sha256 `6ce83989…` | Haute : calculée sur le même paquet |
| T2 | Les sept paragraphes `Go` deviennent `BSD-3-Clause` ; les statuts journalisés : `FreeBSD`, `MPEG`, `noderivs`, `BSD-3-clause-svgpan` hors SPDX, `X11` hors politique, `Apache-2.0` et `BSD-3-Clause` autorisés | Haute : lecture du passage de 20:05:09 UTC |
| T3 | `bilan : KO`, code 1 : `licences.py` s'arrête au premier nom invalide restant | Haute |

*Note datée du 12/11/2026, écrite à 20:12:28 UTC* : **revue de la traduction « Go » -> `BSD-3-Clause`.** Question : « Tu valides « Go » →
BSD-3-Clause, brevets hors de l'expression ? » ; réponse du propriétaire : « Oui, je valide ». Inscrite dans `traductions-dep5.json`
(champ `revue`), preuve inchangée (`6ce83989…`). L'étape `stdlib` n'est pas relancée : accord nommé attendu ; T1 à T3 tiennent lieu de
prédictions.

## Résultats de la relance de `stdlib` : 12/11/2026, 20:13:36 UTC, code 1 (`bilan : KO`, attendu par T3), sans ligne « fait »

Accord : « Oui, relance stdlib » à « Je relance stdlib ? (paquets.sh, commit a69ab7a) » ; HEAD a69ab7a, arbre propre, contrôlés à
20:13:36 UTC. Dernière ligne du journal à 20:13:38 UTC (`date -u` de la commande). Le premier passage (20:05:09 UTC) est conservé tel
quel dans [`paquets-stdlib-premier-passage.log`](paquets-stdlib-premier-passage.log) et
[`paquets-stdlib-premier-passage.licences.json`](paquets-stdlib-premier-passage.licences.json) (copies égales à celles de a69ab7a) ;
[`paquets-stdlib.log`](paquets-stdlib.log) et [`paquets-stdlib.licences.json`](paquets-stdlib.licences.json) sont ceux de la relance.
Résultats écrits à partir de 20:13:55 UTC.

| # | Résultat |
|---|---|
| T1 | **Tenue.** `traduction Go -> BSD-3-Clause : appliquée`, texte au sha256 `6ce83989…`, revue citée au journal |
| T2 | **Tenue.** Les sept paragraphes `Go` sont rendus en `BSD-3-Clause` ; statuts journalisés : `FreeBSD`, `MPEG`, `noderivs`, `BSD-3-clause-svgpan` hors SPDX ; `X11` SPDX, hors politique ; `Apache-2.0`, `BSD-3-Clause` (et `BSD-3-clause`) autorisés |
| T3 | **Tenue.** `licences.py` code 1, une erreur : premier identifiant invalide restant, `FreeBSD` ; composant du deb toujours `ok` |

**Ce qui reste pour déclarer la bibliothèque standard**, d'après les statuts archivés (sans décision) : `FreeBSD` (deux fichiers ELF,
dont `src/debug/elf/elf.go`), `MPEG` (`src/image/jpeg/idct.go`), `noderivs` (données de test de `image/png`), `BSD-3-clause-svgpan`
(un fichier de pprof sous `src/cmd`) : quatre noms hors SPDX ; `X11` (fichiers de `src/cmd/internal/objabi`) : absent de la politique.
Plusieurs de ces fichiers ne sont sans doute pas compilés dans `sample-app` (données de test, outils de `src/cmd`) ; ce n'est pas mesuré.
