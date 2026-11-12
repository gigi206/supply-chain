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
