# Révision 1.0.0-2 du paquet deb : carte de la cascade et prédictions (préparées à sec le 14/11/2026 à partir de 21:49:01 UTC)

Étape 5 de la séquence d'après S5b. Décisions du 12/11/2026 (axes 1 et 2 de la 13a) : `Static-Built-Using` posé par une variable
`misc:` dans `debian/rules`, notices de Go en `Comment:` d'en-tête de `debian/copyright`. **RIEN N'EST APPLIQUÉ NI LANCÉ** :
`poc/packaging/` et les scripts sont inchangés ; le correctif est un fichier à part, appliqué sur accord nommé.
Préfixe `U`, libre dans la 06 (`git grep` à 1b64b3d : aucune ligne `| U<n>` dans `resultats/`).
Préparation hors dépôt (12 et 13/11) : bancs U4, U4c, U5r, U7r, W, D, E et F, journaux dans le cache
`~/.cache/supply-chain-poc/13a-axes12-esquisse/esquisse/` (`revision-predictions.md`) ; leurs résultats sont des analogues hors
sbuild, pas des mesures de la cascade. Témoin 1.0.0-1 du cache de packaging copié dans `13a-axes12-esquisse/temoin-1.0.0-1/`.

## Correctif `../revision-1.0.0-2.patch` (NON APPLIQUÉ)
`git apply --check` passé à 1b64b3d ; `bash -n` des sept scripts touchés et `shellcheck -S warning` de `sources.sh` passés sur les
copies modifiées. Contenu :
- `poc/packaging/debian/control` : `Static-Built-Using: ${misc:Static-Built-Using}` ; `rules` : `override_dh_gencontrol` qui lit
  `golang-1.24-src` par `dpkg-query` et refuse une valeur vide (`test -n`) ; `copyright` : `Comment:` d'en-tête (paragraphes 2, 3, 8
  et 9 du copyright de golang-1.24-src 1.24.4-1, texte de la licence Go). Copies de `13a-axes12-esquisse/esquisse/paquet2/debian/`.
- `poc/packaging/sources.sh` : la révision est lue dans `debian/changelog` (`dpkg-parsechangelog -SVersion`, refus si elle ne
  commence pas par `1.0.0-`) au lieu du `-1` en dur des l. 60 à 62 ; commentaires des l. 8 et 26 mis à jour (la date de l'archive
  amont n'est plus celle du changelog à partir de 1.0.0-2).
- Noms de fichiers `1.0.0-1` → `1.0.0-2` là où ils désignent le paquet courant : `s1.sh` (l. 45, 261, 266, 284), `s3.sh` (l. 42,
  46, 220, 244, 245), `s4d.sh` (l. 61, 233, 236, 554, 556), `s6a.sh` (l. 44, 360, 496), `s6b.sh` (l. 102), 13a `paquets.sh` (l. 44).
  Libellé de `s4d.sh` l. 556 borné : « deb égal à celui de S3 » au lieu de « d'OBS, S1 et S3 ».
- **Laissés en 1.0.0-1, volontairement** : `s2.sh` l. 39 et `s4c.sh` l. 32 (buildinfo de S1b et de S2, entrées archivées ; S2
  n'est pas rejouée, voir U1) ; `construire.sh` du banc OBS l. 45 (banc supprimé le 29/10/2026, non rejouable) ; `s3.sh` l. 250
  (libellé informatif : « deb différent de celui de s1b et d'OBS » est la sortie attendue, U3) ; spec du rpm (étape 7).
- **Hors correctif** : l'entrée de changelog, écrite à l'application avec l'heure de `date -u` (son `SOURCE_DATE_EPOCH` fixe tous
  les digests en aval, qui ne sont donc pas prévisibles) ; les épinglages, réécrits par trois petits correctifs après mesure.

## Carte (un accord nommé par ligne ; prédictions de chaque étape reprises de ses fichiers, avec les nouvelles valeurs)
| # | Étape | Lit | Produit | Épinglage à réécrire ensuite |
|---|---|---|---|---|
| 0 | correctif appliqué + entrée 1.0.0-2 datée par `date -u`, commit | patch | `debian/` 1.0.0-2 | — |
| 1 | `sources.sh` (réseau : `go mod vendor`, `curl` de marked ; efface les sorties 1.0.0-1 du cache) | `poc/sample-app`, `debian/` | `.dsc`, `.debian.tar.xz` 1.0.0-2, orig | — |
| 2 | commande de `s1.sh` l. 261 rejouée seule (comme le 13/11) | `SHA256SUMS` du cache | `$W/s1-06/SHA256SUMS.s1` | — |
| 3 | S3 `restauration builds comparaison` (réécrit `resultats/s3-*` ; versions 1.0.0-1 dans git à 636b190) | fermeture de S2, chroot e0b1f37c, sources 1.0.0-2 | deb N (deux fois), deux buildinfo | **correctif 1** : `DEB_SHA=N` dans `s4d.sh` l. 62, `s6a.sh` l. 45, `s6b.sh` l. 103, 13a `paquets.sh` l. 45 ; `s5.sh` l. 460 (`0b489d43` en dur, libellé « de S1, S3 et S4d ») |
| 4 | 13a `paquets.sh` (étapes deb et modules) | deb N | journaux de la 13a | — |
| 5 | S4c `verrou publier` | buildinfo de S2 (inchangé), `debian/` 1.0.0-2 | artefact de packaging P | **correctif 2** : `PACKAGING=…@P` dans `s4b.sh` l. 40, `s4d.sh` l. 55, `s6b.sh` l. 109 |
| 6 | S4b (étapes du rejeu) | P | fermetures | — (U9) |
| 7 | `s4d.sh prealables` | deb de S3 | digest attendu D | **correctif 3** : `DEB_DIGEST`/`DEB` à D dans `s4d2.sh` l. 35, `s4d3.sh` l. 45, `s5.sh` l. 48, `s6a.sh` l. 54, `s6b.sh` l. 104 |
| 8 | S4d `reseau taches pipeline`, S4d2, S4d3 `retirer prealables deployer chemins porte` | P, D | deb dans Zot, bundle de pipeline neuf | — |
| 9 | S5 (tests négatifs) | D | — | — |
| 10 | S6a `periodique fraicheur grafana` (`periodique` refusé de 09:00 à 12:59 UTC) | D | CronJob sur D, scan du deb N | — |
| 11 | S6b : nouvelle VSA du deb (étapes de la VM à préciser avant ce point), `pousser_vsa`, `lire_vsa` | D | VSA | — |
| 12 | S6a `porte` | D | verdict | — |
Le comportement d'un épinglage périmé est relevé au fil de la carte : `s4d.sh` l. 239 (`attendu "deb de S3"`) refuse un `DEB_SHA`
ancien (arrêt) ; `s6b.sh` l. 746-749 refuse une VSA si D est absent de Zot. Les autres cas sont à relire avant leur étape.
Les fixtures `c1719b13` et `039949f9` de `porte_test.rego` (l. 279, 292, 296) sont des données de test : non réécrites (U12).
Le bundle de pipeline change à chaque nouvel épinglage (`sample-app-deb.yaml` porte `PACKAGING` en paramètre fixé par digest,
`s4d.sh` l. 105-111) ; les bundles des tâches ne changent pas (`PACKAGING` est un paramètre de `preparer-deb`) : `taches.yml`
inchangé, pas de pod d'essai neuf.

## Prédictions
| Id | Prédiction | Confiance |
|---|---|---|
| U1 | Les deux buildinfo de S3 en 1.0.0-2 ont les mêmes `Installed-Build-Depends` que celui de S2 (comparaison de `s3.sh`, `BUILDINFO_S2`) ; `s4c.sh verrou` rend `verrou-deb.txt` 89d648b5 | Haute (banc F : même champ b9165ce4 en 1.0.0-1 et 1.0.0-2, hors sbuild). Portée : S2 n'est pas rejouée ; la mesure de U1 est la comparaison de S3 |
| U2 | Les deux builds de S3 rendent le même deb N | Haute |
| U3 | N diffère de 0b489d43 ; D diffère de 039949f9 ; valeurs non prédites | Haute |
| U4 | `dpkg-deb -f N` : `Static-Built-Using: golang-1.24 (= 1.24.4-1)`, pas de `Built-Using` | Haute (bancs U4c et D, dpkg 1.22.22 du chroot) |
| U5 | `./usr/bin/sample-app` de N = 10d475d0… | Haute (banc U5r, recette réelle) |
| U6 | `/usr/share/doc/sample-app/copyright` de N = `debian/copyright` 1.0.0-2 (`cmp`) | Haute (constat U6 sur 0b489d43) |
| U7 | `sources.sh` : orig 07521c1e… inchangé ; code 0 | Moyenne : téléchargements de proxy.golang.org et du registre npm (banc U7r hors réseau tenu) |
| U8 | 13a sur N : expression `Apache-2.0 AND MIT AND (MIT AND BSD-3-Clause)` ; `licences.py` 0 erreur ; `modules` : B2 et B3 de la bascule de M5 (ligne OK du contrôle croisé, ÉCART « Comment d'en-tête présent »), code 0 | Haute (banc E) |
| U9 | S4b : fermetures bb7599a2 et 50dc73f7 inchangées (épinglées telles quelles dans `s4d.sh` l. 53-54, `s5.sh` l. 49, `s6b.sh` l. 107-108) | Haute : le verrou (U1) et `poc/sample-app` ne changent pas. S4a (image de build 749d746c) n'est pas rejouée : elle ne dépend pas du paquet |
| U10 | S4d : le deb de la pipeline sous Kata = N ; digest du deb dans Zot = D (deux chemins) | Haute (S5b, C8) |
| U11 | S4d3 `porte` : deb : VSA et scan refusés (pas encore de VSA ni de scan pour D) ; sample-app `ok|ok` | Haute (S5b, C9) |
| U12 | tests de la porte 39/39 (fixtures inchangées) | Haute |
| U13 | `ScanEnRetard` reste inactive de l'étape 8 à l'étape 10 : le CronJob scanne D-ancien (039949f9) jusqu'à `periodique`, puis D | Moyenne (série par dépôt, règle non relue pour ce cas) |
| U14 | S6a `porte` après S6b : ec en succès, horodatage, VSA et scan `ok` sur D | Haute (S6a du 14/11) |

## Ce que la cascade ne mesure pas
- La résolution d'apt dans un S2 rejoué (S2 n'est pas rejouée) ; l'égalité avec le deb d'OBS (banc supprimé) : bornée à 1.0.0-1.
- La reproductibilité d'une date d'entrée donnée : chaque application du correctif fixe une date, donc des digests différents.

## G7 (fenêtre jusqu'au balayage du 28/11)
La cascade relit les scans de `builds/scan/sample-app` : la porte de S4d3 (l. 350) et celle de S5 (l. 563) jugent l'image réelle,
et `scan-verifier.sh` vérifie TOUTES ses attestations (`cosign verify-attestation`). Lecture du code de Zot v2.1.22
(`pkg/storage/gc/gc.go`, tag v2.1.22, et copie du cache `07a/zot-src/gc.go`) : un referrer sans sujet dans son dépôt est retiré par
`removeReferrer` → `removeManifestIfOlderThan` → `isBlobOlderThan`, sur la **date de modification du blob** (`StatBlob`) ; le mot
« pull » n'apparaît pas dans `gc.go`. Une lecture ne repousse donc pas H1 ni H2, d'après le code ; confirmation par la mesure du
27/11. **Aucun verrou G7 sur la cascade** ; le rejeu de zéro reste exclu avant le 28/11 (la cascade n'efface pas Zot).

## Coût
Note du README du 14/11 (21:40:25Z) : consommé 0,696 à 0,701 pw ; projection avec la cascade et lintian 1,00 à 1,44 pw, sous 2 pw.
Les trois correctifs d'épinglage et l'étape 2 s'ajoutent à la cascade comptée.

## Note de 2026-11-14T21:53:55Z : correctif v2 et corrections, après relecture du conseiller (rien n'est réécrit)
1. **Défaut du correctif de 9106ed3** : dans `s3.sh`, `BUILDINFO` (l. 42) nomme à la fois le buildinfo rapatrié des builds (l. 232)
   et celui de S2 (l. 43, `BUILDINFO_S2=$R/s2-$BUILDINFO`). Passé en 1.0.0-2, il ferait chercher `s2-sample-app_1.0.0-2_amd64.buildinfo`,
   qui n'existe pas ; le `|| true` du bloc Python de la comparaison (l. 251) pouvait masquer l'échec, et **U1 n'aurait pas été
   mesurée**. **`../revision-1.0.0-2-v2.patch` remplace `revision-1.0.0-2.patch`, qui ne doit pas être appliqué** : seule
   différence, `BUILDINFO_S2` épinglé à `s2-sample-app_1.0.0-1_amd64.buildinfo` (présent dans `resultats/`). `git apply --check`
   et `bash -n` passés. Autres lignes remplacées, tracées par usage : `s1.sh` (`DSC` et noms des sources du cache, tous du paquet
   courant), `s4d.sh` (`DEB_S3`, noms dans le pod et la couche), `s6a.sh` et `s6b.sh` (`DEB`, deb de S3) : aucun autre double usage.
2. **Nombre d'accords** : la carte a 13 lignes (0 à 12) **plus** trois correctifs d'épinglage, soit **16 accords nommés** ; « treize
   étapes, dont trois correctifs » (README et message de 9106ed3) est faux.
3. **Heure** : « à partir de 21:49:01 UTC » est l'heure de rédaction de la carte ; le correctif a été généré avant (heure non relevée
   par `date -u`).
4. **Lecture de Zot** : la copie du cache `07a/zot-src/gc.go` n'a pas de version relevée (copiée le 05/11) ; `grep -ci pull` y rend 0.
   La lecture au tag v2.1.22 est passée par WebFetch, qui rend un résumé et des citations courtes, pas les octets : `isBlobOlderThan`
   (`StatBlob`, `modtime.Add(delay)`), les deux appels de `removeManifestIfOlderThan` dans `removeReferrer`, et l'absence de « pull »
   dans le fichier, selon cet outil. `zot.json` (08) : `builds/scan/**` a `deleteReferrers: true`, `deleteUntagged: false`, sans
   `keepTags`.
5. **Regrep complété** (paquet source) : `9050679e` (`.dsc`), `863cf4da` (`.debian.tar.xz`), `20c9dd35` et `a3cbcf92` (copyright),
   `1952080` (taille du deb) : aucune occurrence hors de `resultats/`, `docs/` et des `.md`. `docs/` ne cite pas `lastPullTimestamp`.

## Carte, ligne 0 : correctif v2 appliqué (note de 2026-11-14T21:55:49Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif v2 avec l'entrée de changelog datée ? ». `git apply` de
`revision-1.0.0-2-v2.patch` (sha256 c8563413…), code 0, sur 09bff27. Entrée `sample-app (1.0.0-2)` datée **Sat, 14 Nov 2026 21:55:32
+0000** (`date -u`, epoch **1794693332** : le `SOURCE_DATE_EPOCH` du build 1.0.0-2) ; `dpkg-parsechangelog` 1.23.7 de l'hôte :
`Version` 1.0.0-2, `Timestamp` 1794693332, deux entrées lisibles. Contrôles : `control`, `rules`, `copyright` égaux à `paquet2/`
(`cmp`) ; `bash -n` des sept scripts touchés ; `1.0.0-1` ne reste, hors textes, que là où la carte le garde (`s2.sh` l. 39,
`s3.sh` l. 43, `s4c.sh` l. 32, banc OBS, spec, ancienne entrée du changelog, commentaire de `sources.sh`). Rien n'est lancé ;
prochaine ligne : `sources.sh` (réseau), sur accord nommé.

## Carte, ligne 1 : `sources.sh` (note de 2026-11-14T21:57:39Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance sources.sh (réseau) ? ». `mise run packaging:sources` de 21:57:18 à 21:57:19 UTC, code 0, à 593cee4
([journal](revision-sources.log)) ; témoin 1.0.0-1 du cache contrôlé avant (`sha256sum -c`, 5 OK).
- **U7 tenue** : chi v5.2.3 téléchargé, `go mod verify` « all modules verified » (go 1.24.7) ; marked 16.4.1 conforme à l'intégrité
  du lockfile ; orig **07521c1e…** (140 171 octets), inchangé ; spec e1281b3d inchangé.
- Paquet source 1.0.0-2 : `.dsc` **92335109…**, `.debian.tar.xz` **86e30d04…** (4 196 octets) ; le `.dsc` référence l'orig 07521c1e ;
  `debian/` extrait du `.debian.tar.xz` égal à `poc/packaging/debian/` (`diff -r`) ; `SHA256SUMS` du cache : 5 OK.
  Les fichiers 1.0.0-1 du cache sont effacés par `sources.sh` (l. 52) ; témoin gardé dans `13a-axes12-esquisse/temoin-1.0.0-1/`.
Prochaine ligne : commande de `s1.sh` l. 261 rejouée seule (`SHA256SUMS.s1`), sur accord nommé.

## Carte, ligne 2 : `s1.sh` l. 261 rejouée seule (note de 2026-11-14T22:00:00Z ; rien n'est réécrit)
« Oui, rejoue-la ». Sur l'hôte, à 21:59:48 UTC, code 0 ([journal](revision-sha256sums-s1.log)) : texte de la l. 261 et `DSC` lus
dans `s1.sh` à 15440e0 ; `SHA256SUMS` du cache contrôlé d'abord (5 OK) ; `$W/s1-06/SHA256SUMS.s1` réécrit : trois lignes (orig
07521c1e, `.dsc` 92335109, `.debian.tar.xz` 86e30d04), contrôlées (3 OK) ; l'ancien contenu (1.0.0-1) est dans le journal.
Prochaine ligne : S3 `restauration builds comparaison` (pods Kata), sur accord nommé ; prédictions U1 à U6 commitées.

## Carte, ligne 3 : S3 (note de 2026-11-14T22:13:58Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S3 (restauration builds comparaison) ? ». `s3.sh restauration builds comparaison` à 94b770f, de
22:00:52 à 22:13:25 UTC (`date -u` autour du lanceur), code 0, 26 OK, 0 KO ; journaux `s3-*` réécrits (versions 1.0.0-1 à 636b190).
Fermeture `3a0e54ae` restaurée deux fois (162 fichiers), chroot de S2 `e0b1f37c`, `SHA256SUMS.s1` 1.0.0-2 livré aux deux pods.
- **U1, part S3 tenue** : `Installed-Build-Depends` des deux buildinfo identiques à celui de S2 (comparaison de `s3.sh`, sur
  `BUILDINFO_S2` épinglé par le correctif v2). La part S4c (verrou 89d648b5) reste à la ligne 5.
- **U2 tenue** : deb **N = 3c6e6a290fed15f9b41f0b442f5946008ff075790af0c247da8f00428d5a48aa** (1 953 500 octets) aux deux builds.
- **U3 tenue (part deb)** : N ≠ 0b489d43 (« deb différent de celui de s1b et d'OBS », sortie attendue). D reste à la ligne 7.
- Lectures sur le deb du build 1, à 22:13:40 UTC (hôte, dpkg-deb 1.23.7) :
  - **U4 tenue** : `Static-Built-Using: golang-1.24 (= 1.24.4-1)`, pas de `Built-Using` ; `Version` 1.0.0-2, `Installed-Size` 5785.
  - **U5 tenue** : `./usr/bin/sample-app` = **10d475d0…** (inchangé).
  - **U6 tenue** : copyright du deb égal à `poc/packaging/debian/copyright` (`cmp`).
  - `SOURCE_DATE_EPOCH="1794693332"` dans l'environnement des deux buildinfo (date de l'entrée 1.0.0-2).
Prochaines lignes : correctif d'épinglage 1 (`DEB_SHA` = N, `s5.sh` l. 460), puis 13a ; chacun sur accord nommé.

## Carte, correctif d'épinglage 1 (note de 2026-11-14T22:15:59Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif d'épinglage 1 (deb 3c6e6a29) ? ». N relu sur le deb du build 1 et dans
`s3-comparaison.log` ; [`../revision-epinglage-1.patch`](../revision-epinglage-1.patch) (sha256 52d9c802…) généré depuis HEAD
e3227d1, `git apply --check` puis `git apply`, code 0 ; `bash -n` des cinq scripts passé. `DEB_SHA` = 3c6e6a29… dans `s4d.sh` l. 62,
`s6a.sh` l. 45, `s6b.sh` l. 103, 13a `paquets.sh` l. 45 ; `s5.sh` l. 460 : témoin N7 `3c6e6a29`, libellé « deb de S3 et S4d ».
`0b489d43` ne reste, dans les scripts, que là où il désigne le passé : `DEB_S1` de `s2.sh` et `s3.sh` (deb de s1b), commentaires
de `s4d.sh` l. 11 et de `taches.yml` l. 72, banc X11 de la 13a (`resultats/x11-fichiers.sh`, mesure du 14/11 sur 0b489d43).
Rien n'est lancé. Prochaine ligne : 13a `paquets.sh` sur N (U8, B2, B3), sur accord nommé.

## Carte, ligne 4 : 13a sur le deb 1.0.0-2 (note de 2026-11-14T22:17:33Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance paquets.sh deb modules (13a) sur le deb 3c6e6a29 ? ». `paquets.sh deb modules` à 408b226, de 22:16:56 à 22:16:59 UTC (`date -u` autour du lanceur), code 0, sur le deb 3c6e6a29 (sha256 épinglé, OK).
- **U8 tenue** : copyright du deb égal à `debian/copyright` (a3cbcf92…), DEP-5 1.0, 6 paragraphes, expression
  `Apache-2.0 AND MIT AND (MIT AND BSD-3-Clause)` ; `licences.py` : 0 erreur, 0 NOASSERTION, 0 invalide ; quatre témoins refusés.
- **B2 et B3 de la bascule de M5 tenues** (`modules`) : `control : Static-Built-Using golang-1.24 (= 1.24.4-1)`, ligne OK « paquet
  source et version amont égaux à go1.24.4 du buildinfo » ; ÉCART « … Comment d'en-tête présent, contenu non contrôlé ;
  Static-Built-Using golang-1.24 (= 1.24.4-1) » ; témoin chi refusé. Journaux de la 13a réécrits (versions sur 0b489d43 à 5264a31).
Prochaine ligne : S4c `verrou publier` (écriture dans Zot), sur accord nommé.

## Carte, ligne 5 : S4c (note de 2026-11-14T22:19:04Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S4c (verrou publier, écriture dans Zot) ? ». `s4c.sh verrou publier` à badc113, de 22:18:38 à
22:18:43 UTC (`date -u` autour du lanceur), code 0, 11 OK, 0 KO ; journaux `s4c-verrou.log` et `s4c-publier.log` réécrits.
- **U1, part S4c tenue** : C2 « verrou égal à celui du dépôt », 162 paquets, sha256 **89d648b5…** ; C3 égal à la fermeture de S2.
  **U1 tenue en entier** (S3 et S4c).
- Artefact de packaging **P = sha256:f0ed7a71cfcc72e15f2c91d0ec6d81f4452bf6627d3dec40a5a7ceac6dcfe88f** : deux poussées locales et deux
  poussées dans Zot, même digest (C4, C5) ; fichiers tirés égaux au dépôt (C6) ; seuls les quatre fichiers de `debian/` changent
  dans la liste du journal (changelog, control, copyright a3cbcf92, rules). C7 relevé comme au premier passage (`rules` tiré en 644).
  `entrees/sample-app/packaging-deb@f0ed7a71` est définitif dans Zot.
Prochaine ligne : correctif d'épinglage 2 (`PACKAGING` = P dans `s4b.sh` l. 40, `s4d.sh` l. 55, `s6b.sh` l. 109), sur accord nommé.

## Carte, correctif d'épinglage 2 (note de 2026-11-14T22:20:29Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif d'épinglage 2 (artefact f0ed7a71) ? ». P relu dans `s4c-publier.log`
(`PACKAGING_DEB=…@sha256:f0ed7a71…`) ; [`../revision-epinglage-2.patch`](../revision-epinglage-2.patch) (sha256 050fea28…) généré
depuis HEAD a43bcc2, `git apply --check` puis `git apply`, code 0 ; `bash -n` des trois scripts passé. `PACKAGING` = f0ed7a71 dans
`s4b.sh` l. 40 et `s4d.sh` l. 55, entrée de `ENTREES` dans `s6b.sh` l. 109. Restent `c1719b13` : commentaire de `s6b.sh` l. 13 (H3,
mesure passée) et fixture de `porte_test.rego` l. 279 (données de test, U12). Rien n'est lancé.
Prochaine ligne : S4b (fermetures, U9), sur accord nommé.

## Carte, ligne 6 : S4b (note de 2026-11-14T22:25:13Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S4b (prealables taches_deb taches_sources deb sources comparaison) ? ». `s4b.sh` à 7cdfb33, de
22:22:24 à 22:24:40 UTC (`date -u` autour du lanceur), code 0, 65 OK, 0 KO ; journaux `s4b-*` réécrits (versions du 13/11 à 774471f).
- **U9 tenue** : deux PipelineRuns par fermeture, mêmes digests : deb **bb7599a2…** (167 couches), sources **50dc73f7…** (8 couches) ;
  les épinglages de `s4d.sh` l. 53-54, `s5.sh` l. 49 et `s6b.sh` l. 107-108 restent valables.
- Artefact de packaging relu dans Zot : f0ed7a71 (épinglage 2). Bundles de pipeline neufs : `prefetch-deb-sample-app@206a539e`
  (au lieu de 880bcf58 : porte le nouvel artefact en paramètre) et `prefetch-sources-sample-app@b0d37e59` (au lieu de aa5f62c1).
  Constat, sans lien avec la révision : le bundle de `prefetch-sources-sample-app` change à chaque passage (0ebd1cb8 le 11/11,
  aa5f62c1 le 13/11, b0d37e59 le 14/11, d'après les journaux archivés) ; cause non relevée.
Prochaine ligne : `s4d.sh prealables` (digest attendu D), sur accord nommé.

## Carte, ligne 7 : `s4d.sh prealables` ARRÊTÉE en KO (note de 2026-11-14T22:30:26Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance s4d.sh prealables (digest attendu) ? ». À 19b4cd8, début 22:26:21 UTC (`chrono.tsv` : « S4d1
prealables » sans ligne « fait ») ; [journal](s4d-prealables.log) réécrit (version du 13/11 à 0907d5f). 37 OK, puis arrêt sur :
`KO   sample-app_1.0.0.orig.tar.gz égal à celui de sources.sh : 1591a05b… (attendu : 07521c1e…)` (`s4d.sh` l. 229, `attendu`).
`digest-attendu` n'est pas réécrit : il contient encore `039949f9` ; **aucune étape de S4d ne doit tourner avant un `prealables`
réussi**. Rien n'est écrit dans Zot ni dans le cluster (étape de l'hôte).
- **Cause (lue dans le code)** : la tâche signée `construire-deb` refait l'archive amont avec `--mtime` = date de `debian/changelog`
  (`deb/construire-deb.yaml` l. 13-15 et 90-97, « égale au SOURCE_DATE_EPOCH de sources.sh »), comme `rejeu/rebuild_deb.sh` l. 122 ;
  `sources.sh` la date au dernier commit de `poc/sample-app` (l. 29, `%ct`). Les deux dates étaient égales en 1.0.0-1 ; l'entrée
  1.0.0-2 datée du 14/11 les sépare. Le préalable 6 du brouillon (12/11) avait vu l'égalité rompue pour `sources.sh`, pas son
  consommateur dans la pipeline : **oubli de la préparation**, les relectures ayant tracé noms et digests, pas la date.
- Valeurs côté pipeline (l. 55 du journal, outils de l'hôte, SOURCE_DATE_EPOCH 1794693332) : orig **1591a05b…**, `.dsc` **b284bd60…**,
  `.debian.tar.xz` **22cfff1d…** (contre 07521c1e, 92335109 et 86e30d04 de `sources.sh`).
- Autre consommateur de l'archive, relevé par `git grep` : `s4d.sh` l. 192 épingle `sample-app-1.0.0.tar.gz` (archive complète, rpm
  compris) à 07521c1e. L'artefact de S4c (f0ed7a71) ne contient que `debian/` et le verrou : non concerné.
- **U10 en suspens** ; S3, U1 à U9 restent valables pour ce qu'elles ont mesuré (S3 a construit depuis le paquet source de `sources.sh`).

**Erreur d'instrument (lancements au premier plan de 13a, S4c et de celui-ci)** : la commande de l'assistant écrivait
`echo "fin $(date -u …) code $?"` ; la substitution `$(date …)` remet `$?` à 0 avant sa lecture : **le « code 0 » de ces trois
lancements n'a pas été mesuré**. Preuve de repli : `lancer` (`08-trust-plane/commun.sh` l. 334-336, `set -euo pipefail`) n'écrit
« fait » qu'après une étape réussie ; « 13a paquets modules fait » (22:16:59) et « S4c publier fait » (22:18:43) sont présents,
« S4d1 prealables fait » absent (témoin négatif). 13a et S4c ont donc fini leurs étapes ; leur code de sortie reste non mesuré.
`sources.sh`, la l. 261, S3, S4b et les pushs relevaient le code correctement.

### Options pour le propriétaire (aucune appliquée)
Critères : tâche signée intacte ; date véridique ; artefact f0ed7a71 encore valable ; même paquet source pour S3 et la pipeline.
1. **`sources.sh` : orig daté au changelog, archive complète au commit** (seule option qui passe les quatre critères) : l'orig Debian
   prend la date de `dpkg-parsechangelog -STimestamp`, comme la tâche signée ; `sample-app-1.0.0.tar.gz` (rpm, `s4d.sh` l. 192) reste
   au commit, 07521c1e. Prédictions en valeur absolue : orig 1591a05b, `.dsc` b284bd60, `.debian.tar.xz` 22cfff1d (l. 55).
   À refaire : correctif de `sources.sh`, `sources.sh`, l. 261, S3 (deb 3c6e6a29 attendu inchangé, confiance moyenne : seules les
   dates de l'orig changent), puis `prealables`. Si le deb change : correctif d'épinglage 1 et 13a à refaire.
2. Antidater l'entrée 1.0.0-2 au 28/10 23:19:26 : date fausse, artefact f0ed7a71 orphelin, six étapes à refaire.
3. Assouplir `s4d.sh` l. 229 : perd l'égalité des paquets sources entre S3 et la pipeline.
4. Modifier la tâche signée : nouvelle signature, liste revue de la 08, pod d'essai.

## Décision du propriétaire : option 1 (note de 2026-11-14T22:31:45Z ; rien n'est réécrit)
« Option 1 » à « Quelle option pour réaligner l'archive amont ? ». Correctif préparé à sec, **NON APPLIQUÉ** :
[`../revision-sources-option1.patch`](../revision-sources-option1.patch) (sha256 df163ce5…, `git apply --check` à dca9fe5, `bash -n` et
`shellcheck -S warning` passés sur la copie). `sources.sh` : `SDE_DEB` lu par `dpkg-parsechangelog -STimestamp` ; l'orig est fait par
la même commande `tar` que l'archive complète, avec `--mtime=@$SDE_DEB` (au lieu d'une copie) ; `dpkg-source` sous
`SOURCE_DATE_EPOCH=$SDE_DEB` ; l'archive complète (rpm, `s4d.sh` l. 192) reste datée du commit. Les options de `tar` et de `gzip`
sont celles de `deb/construire-deb.yaml` l. 94-95 (comparées ligne à ligne).

Suite de la carte (un accord nommé chacune) : 1b correctif appliqué ; 1 `sources.sh` relancé (réseau) ; 2 l. 261 rejouée ; 3 S3
relancée ; 7 `s4d.sh prealables`. Les lignes 4 à 6 (13a, S4c, S4b) ne sont à refaire que si le deb change.
| Id | Prédiction | Confiance |
|---|---|---|
| U15 | `sources.sh` corrigé : orig **1591a05b…**, `.dsc` **b284bd60…**, `.debian.tar.xz` **22cfff1d…** (valeurs de la pipeline, l. 55 de `s4d-prealables.log`) ; `sample-app-1.0.0.tar.gz` **07521c1e…** inchangé | Haute : même arbre, même commande, même date (l'arbre de la pipeline vient du même commit, vendor et marked contrôlés) |
| U16 | S3 relancée sur ce paquet source : deb **3c6e6a29…** inchangé aux deux builds | Moyenne : seules les dates des fichiers de l'orig changent ; dpkg-deb borne les dates à SOURCE_DATE_EPOCH, inchangé ; non mesuré |
| U17 | `s4d.sh prealables` : orig, `.dsc` et `.debian.tar.xz` égaux à ceux de `sources.sh` ; code 0 ; digest attendu D écrit, différent de 039949f9 | Haute si U15 tient |
Si U16 ne tient pas : correctif d'épinglage 1, 13a, puis seulement `prealables` (S4c et S4b ne dépendent pas du deb).

## Option 1, ligne 1b : correctif de `sources.sh` appliqué (note de 2026-11-14T22:33:11Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif de sources.sh (option 1) ? ». `git apply` de `revision-sources-option1.patch`
(df163ce5…) sur 2216693, code 0 ; `bash -n` et `shellcheck -S warning` passés sur `poc/packaging/sources.sh` ; `SDE_DEB` lu dans le
changelog : 1794693332. Rien n'est lancé. Prochaine ligne : `sources.sh` (réseau), U15, sur accord nommé.
