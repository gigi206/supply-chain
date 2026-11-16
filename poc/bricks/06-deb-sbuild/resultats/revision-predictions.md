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

## Option 1, ligne 1 rejouée : `sources.sh` (note de 2026-11-14T22:34:43Z ; rien n'est réécrit)
« Oui, relance-le » à « Je relance sources.sh (réseau, U15) ? ». `mise run packaging:sources` à b8eec63, à 22:34:07 UTC, code 0
relevé juste après la commande ([journal](revision-sources-option1.log)) ; chi v5.2.3 vérifié par go.sum, marked conforme au lockfile.
- **U15 en partie tenue** : orig **1591a05b…** égal à celui de la pipeline ; `sample-app-1.0.0.tar.gz` **07521c1e…** inchangé ; date
  `SDE_DEB` 1794693332 lue et appliquée (membres du `.debian.tar.xz` datés du 14/11 à 21:55 UTC).
- **U15 non tenue pour le `.dsc` (ee2a6b8e…) et le `.debian.tar.xz` (0cc3d47e…)**, prédits égaux à b284bd60 et 22cfff1d. **Erreur de
  la prédiction, pas de la chaîne** : le `.debian.tar.xz` de `sources.sh` porte le umask de l'hôte (664 et 775, lus par `tar -tvJf`),
  celui de la pipeline les modes de git (644 et 755) ; constat du 11/11/2026 écrit dans `s4d.sh` l. 230-232, que `prealables` traite
  en comparant membres, tailles et dates seulement (l. 233-235). Ce que la l. 55 du journal du 14/11 donnait pour le `.dsc` et le
  `.debian.tar.xz` n'était donc pas une valeur attendue de `sources.sh`. En 1.0.0-1 déjà, `.dsc` 7f9cf5d3 côté pipeline contre
  9050679e côté `sources.sh` (`s4d-prealables.log` à 0907d5f, l. 55-58).
- Effet attendu sur U17 : l'égalité de l'orig (l. 229) et celle des membres, tailles et dates (l. 233-235) doivent tenir.
Prochaine ligne : l. 261 de `s1.sh` rejouée, sur accord nommé.

## Option 1, ligne 2 rejouée : `s1.sh` l. 261 (note de 2026-11-14T22:35:45Z ; rien n'est réécrit)
« Oui, rejoue-la ». Sur l'hôte, à 22:35:34 UTC, code 0 ([journal](revision-sha256sums-s1-option1.log)) : `SHA256SUMS` du cache
contrôlé (5 OK) ; `SHA256SUMS.s1` réécrit : orig 1591a05b, `.dsc` ee2a6b8e, `.debian.tar.xz` 0cc3d47e, trois lignes contrôlées ;
l'ancien contenu est dans le journal. Prochaine ligne : S3 relancée (U16), sur accord nommé.

## Option 1, ligne 3 rejouée : S3 (note de 2026-11-14T22:50:09Z ; rien n'est réécrit)
« Oui, relance-la » à « Je relance S3 (restauration builds comparaison, U16) ? ». `s3.sh restauration builds comparaison` à ac44457,
de 22:36:53 à 22:49:10 UTC, code 0 relevé juste après la commande, 26 OK, 0 KO ; journaux `s3-*` réécrits (passage précédent à e3227d1).
- **U16 non tenue** : deb **N' = f66bbeb2aba31e5220b332ff3941697dce7660259aa182047a58e77f4f51892b** (1 953 492 octets) aux deux builds,
  au lieu de 3c6e6a29 (1 953 500 octets). **Cause, lue dans les journaux de sbuild** (`dpkg-deb --contents`, version commitée à e3227d1
  contre celle-ci) : une seule ligne diffère, la date de `./usr/share/doc/sample-app/copyright`, **2026-10-28 23:19** avant, **2026-11-14
  21:55** maintenant. Le `debian/copyright` du paquet source portait la date du `SOURCE_DATE_EPOCH` de `dpkg-source` (commit, 28/10)
  au premier passage ; il est copié dans le deb avec sa date, et `dpkg-deb` ne ramène à `SOURCE_DATE_EPOCH` (14/11) que les dates
  plus récentes, pas les plus anciennes. Désormais tout le deb est daté du 14/11 21:55, comme le paquet source de la pipeline.
  L'ancien deb n'est plus sur disque (réécrit par S3) ; la cause est établie par les deux journaux, pas par une comparaison des debs.
- **U1 (part S3), U2, U4, U5, U6 tenues de nouveau** : `Installed-Build-Depends` égaux à S2 ; deux builds égaux ; `Static-Built-Using:
  golang-1.24 (= 1.24.4-1)`, `Installed-Size` 5785 ; binaire 10d475d0 ; copyright égal au dépôt (`cmp`).
- **Conséquence** (prévue par la note de décision) : correctif d'épinglage 1 à refaire (`DEB_SHA` = f66bbeb2, témoin N7 de `s5.sh`) et
  13a à relancer ; S4c (f0ed7a71) et S4b (fermetures) ne dépendent pas du deb. Puis `prealables`.

## Option 1, correctif d'épinglage 1 bis (note de 2026-11-14T22:51:45Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique l'épinglage 1 bis (deb f66bbeb2) ? ». N' relu sur le deb du build 1 et dans `s3-comparaison.log` ;
[`../revision-epinglage-1b.patch`](../revision-epinglage-1b.patch) (sha256 77e61498…) généré depuis HEAD 7f552a5 (le correctif 1 reste
archivé tel quel), `git apply --check` puis `git apply`, code 0 ; `bash -n` des cinq scripts passé. `DEB_SHA` = f66bbeb2 dans `s4d.sh`,
`s6a.sh`, `s6b.sh`, 13a `paquets.sh` ; témoin N7 de `s5.sh` : `f66bbeb2`. Plus aucune occurrence de 3c6e6a29 dans les scripts.
Rien n'est lancé. Prochaine ligne : 13a `paquets.sh deb modules` sur N', sur accord nommé.

## Option 1, ligne 4 rejouée : 13a sur f66bbeb2 (note de 2026-11-14T22:53:08Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance paquets.sh deb modules (13a) sur f66bbeb2 ? ». `paquets.sh deb modules` à c279dd2, de 22:52:47 à 22:52:50 UTC, code 0 relevé juste après la commande, sur le deb f66bbeb2.
**U8, B2 et B3 tenues de nouveau** : journaux identiques à ceux de 3c6e6a29 hors des en-têtes, de l'empreinte et de la taille du deb
(`git diff`) ; prédicat `paquets-deb.licences.json` inchangé. Prochaine ligne : `s4d.sh prealables` (U17), sur accord nommé.

## Option 1, ligne 7 rejouée : `s4d.sh prealables` (note de 2026-11-14T22:54:59Z ; rien n'est réécrit)
« Oui, relance-le » à « Je relance s4d.sh prealables (U17) ? ». À 7940c91, de 22:54:38 à 22:54:46 UTC, code 0 relevé juste après la
commande, 46 OK, 0 KO ; « S4d1 prealables fait » dans `chrono.tsv` ; [journal](s4d-prealables.log) réécrit.
- **U17 tenue** : orig 1591a05b égal des deux côtés (l. 229) ; `.debian.tar.xz` : mêmes membres, tailles et dates que celui de
  `sources.sh`, groupe sans écriture (l. 233-235) ; côté pipeline, `.debian.tar.xz` 22cfff1d et `.dsc` b284bd60, comme le 14/11 à 22:26 ;
  deb de S3 et deb de la couche = f66bbeb2.
- **Digest attendu D = sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e** (`digest-attendu` réécrit) ; U3 (part D)
  tenue : D ≠ 039949f9.
Prochaine ligne : correctif d'épinglage 3 (D dans `s4d2.sh`, `s4d3.sh`, `s5.sh`, `s6a.sh`, `s6b.sh`), sur accord nommé.

## Carte, correctif d'épinglage 3 (note de 2026-11-14T22:57:45Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif d'épinglage 3 (D 60f25f5c) ? ». D relu dans `digest-attendu` et dans
`s4d-prealables.log` ; [`../revision-epinglage-3.patch`](../revision-epinglage-3.patch) (sha256 4f16d365…) généré depuis HEAD 2e2f0d8,
`git apply --check` puis `git apply`, code 0 ; `bash -n` des cinq scripts passé. D = 60f25f5c dans `s4d2.sh` l. 35 (`DEB`), `s4d3.sh`
l. 45, `s5.sh` l. 48, `s6b.sh` l. 104 (`DEB_DIGEST`), `s6a.sh` l. 54 (`DEB_REF`). Restent `039949f9` : commentaires d'en-tête de
`s4d2.sh`, `s6a.sh`, `s6b.sh` (mesures passées), le texte du message de refus de `s6b.sh` l. 749 (« S5b n'a pas reproduit 039949f9 ? »,
libellé seul : le contrôle porte sur `$DEB_SUJET`, dérivé de D), et les fixtures de `porte_test.rego` (U12). Rien n'est lancé.
Prochaine ligne : S4d `reseau taches pipeline` (cluster et Zot, U10), sur accord nommé.

## Carte, ligne 8 : S4d (note de 2026-11-14T23:11:25Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S4d (reseau taches pipeline, U10) ? ». `s4d.sh reseau taches pipeline` à 78cb12f, du 14/11 22:58:40 au
14/11 23:11:01 UTC, code 0 relevé juste après la commande, 27 OK, 0 KO, 0 ÉCART ; « S4d1 pipeline fait » dans `chrono.tsv` ; journaux
`s4d-reseau`, `s4d-taches`, `s4d-pipeline*` réécrits (version du 13/11 à 2cec0df).
- **U10 tenue** : deux PipelineRuns, deb produit sous Kata **f66bbeb2…** (1 953 492 octets, égal à S3) aux deux ; artefact publié
  **builds/sample-app-deb@sha256:60f25f5c…** deux fois, égal au digest attendu de `prealables`, relu en lecture anonyme.
- Bundle de pipeline neuf : `tekton/pipelines/sample-app-deb@d1fb3871` (au lieu de 5b4bacb8), qui porte l'artefact de packaging f0ed7a71.
  `builds/sample-app-deb@60f25f5c` est définitif dans Zot.
Prochaine ligne : S4d2 et S4d3 (`retirer prealables deployer chemins porte`, U11 et U12), sur accord nommé.

## Carte, ligne 8 : S4d2 `regle reel` (note de 2026-11-14T23:15:32Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance s4d2.sh regle reel (U12, sans écriture) ? ». À beb39d7, du 14/11 23:14:56 au 14/11 23:15:11 UTC,
code 0 relevé juste après la commande, 31 OK, 0 KO, 0 ÉCART ; lignes « fait » des deux étapes dans `chrono.tsv`. `s4d2-regle.log`
archivé pour la première fois ; `s4d2-reel.log` réécrit (version du 11/11). Étape `porte` de S4d2 non lancée (ConfigMap en service).
- **U12 tenue** : `ec opa test` 39/39 ; mutations conformes à l'annonce (0 écart sur 18).
- Provenances réelles relues dans Zot (lecture anonyme, cosign, clé de Chains) : deb **60f25f5c**, 4 énoncés dont 2 de PipelineRun, le
  plus récent du 14/11 à 23:10:54 UTC ; aucun code `porte.*` avec la clé de Chains, `porte.fermeture_plateforme` avec une autre clé ;
  fermetures bb7599a2 et 50dc73f7 lues dans la provenance (8 provenances chacune, deux passages de S4b) ; les quatre témoins refusés
  comme prévu ; sample-app sans code `porte.*`.
Prochaine ligne : S4d3 `retirer prealables deployer chemins porte` (cluster, U11), sur accord nommé.

## Carte, ligne 8 : S4d3 `retirer prealables deployer chemins porte` (note de 2026-11-15T20:40:05Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S4d3 (retirer prealables deployer chemins porte, U11) ? ». À 6ca290e, du 15/11 20:24:36 au
15/11 20:39:34 UTC, code 0 relevé juste après la commande, 93 OK, 0 KO, 0 ÉCART ; lignes « fait » des quatre étapes lancées après
`retirer` dans `chrono.tsv`. Journaux `s4d3-{retirer,prealables,deployer,chemins,porte}.log` réécrits (versions du 11/11).
- **U11 tenue** : deb **60f25f5c** (provenance de PipelineRun c3d27e05…, seule jugée) : `ec` en succès, sans violation, avertissement
  `trusted_task.tagged` ; horodatage 8/8 ; **VSA refusée** (0/0 retenue) et **scan refusé** ; règles `porte.*` du PoC parmi les succès.
  sample-app : `true`, horodatage 6/6, VSA et scan **`ok|ok`**.
- Chemins : webhook de Forgejo et rattrapage (CronJob `rattrapage-deb` repris), chacun un PipelineRun réussi (3/3 TaskRuns,
  construction sous Kata) sur le bundle `d1fb3871`, signé par Chains, **IMAGE_DIGEST 60f25f5c** les deux fois ; UID différents, spec
  identique.
Prochaine ligne : S5 (U13 : ScanEnRetard), sur accord nommé.

## Carte, ligne 9 : S5 non lancée, deux valeurs périmées dans `s5.sh` (note de 2026-11-15T20:44:46Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S5 (U13 : ScanEnRetard) ? » (15/11). **S5 n'a pas été lancée** : la relecture d'avant lancement a
trouvé deux valeurs périmées. Cet accord ne vaut plus : il portait sur un script qui va changer, et sans liste d'étapes.
- **Erreur de la carte** : la ligne 9 dit que S5 ne lit que D. Elle lit aussi le bundle de pipeline deb (`s5.sh` l. 45, `PIPE_DEB`),
  dont `prealables` exporte les paramètres des tâches. `figer` ne remplace que `commit` et `depot` et exige 0 variable restante :
  `packaging` est donc en dur dans le bundle. `PIPE_DEB` épingle encore `82c8373d` (S4d1, 11/11), qui porte l'ancien packaging ;
  le bundle en vigueur est `d1fb3871` (S4d3). `apres-s5b.md` et la carte avaient manqué cette ligne : ils cherchaient des valeurs
  connues (deb, manifeste), pas tous les épinglages. **Non mesuré** : si `82c8373d` existe encore dans Zot après S5b ; le mode
  d'échec (arrêt à l'export ou écart au témoin N7) n'est donc pas annoncé.
- **Deuxième valeur** : la porte de S5 (l. 565) attend `ok|28/28` enveloppes pour sample-app ; la porte de S4d3 du 15/11 en a
  mesuré `6/6` (`s4d3-porte.log` l. 17). Le deb attend `8/8`, égal à S4d3.
- **Relevé complet** des empreintes de `s5.sh`, `s6a.sh` et `s6b.sh` contre les valeurs en vigueur : seules ces deux lignes sont
  périmées. Restent valables : S4a (`a9d48331`, `749d746c`, chroot `aec1c7a9`), amorce `7378260c`, D `60f25f5c`, fermetures
  `bb7599a2` et `50dc73f7`, P `f0ed7a71`, témoin N7 `f66bbeb2`, outils `7eb4f26e`, sample-app `3a7ca1b1`. `039949f9`, `c1719b13`,
  `454728c5` ne sont que dans des commentaires d'en-tête. Les comptes en dur de `prealables`, `fermeture` et `kata` (162 paquets du
  verrou, 167 fichiers de la copie, 163 fichiers du pool altéré) ne dépendent pas de la révision (verrou inchangé, U1).
- **Correctif d'épinglage 4**, préparé et archivé, **non appliqué** : [`revision-epinglage-4.patch`](../revision-epinglage-4.patch)
  (`PIPE_DEB` → `d1fb3871…`, porte sample-app → `ok|6/6`).
- **Correction de ma question** : S5 ne juge pas U13. `ScanEnRetard` n'apparaît ni dans `s5.sh` ni dans `s6a.sh` ; la règle est
  relevée dans la 08c (`scan-saut-*`). Où et comment U13 sera lue reste à préciser avant la ligne 10. La fenêtre « étapes 8 à 10 »
  court depuis la fin de S4d3 (15/11, 20:39:34 UTC) et s'allonge pendant ce détour.
- **Étapes de S5, à décider sur mesure** : S5a n'a pas tourné depuis le 11/11 (`chrono.tsv`), S5b est passée depuis, et le
  répertoire de travail `s5-06` n'existe plus. `fermeture` s'arrête si les fermetures altérées manquent sous
  `entrees/sample-app-deb/fermeture-alteree`, et `zot` écrit dans Zot (accord à part). Proposé : `prealables` seule d'abord
  (lecture et admission à blanc), puis la liste d'étapes. Les prédictions de S5 avec les nouvelles valeurs (P1 → `d1fb3871`,
  témoin N7 → `f66bbeb2`, porte → verdicts de S4d3 du 15/11) seront commitées avant tout lancement, en additif à
  `s5-predictions.md`. Non relevé : pourquoi la reprise du bloc 06 du 13/11 n'a pas rejoué S5.
Prochaine ligne : correctif d'épinglage 4, sur accord nommé ; puis S5 `prealables`, sur accord nommé.

## Correctif d'épinglage 4 appliqué (note de 2026-11-15T20:45:27Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif d'épinglage 4 ? ». `revision-epinglage-4.patch` appliqué tel quel à `s5.sh`
(`git apply --check` puis `git apply`, code 0) : `PIPE_DEB` → `d1fb3871…` (l. 45), porte sample-app → `ok|6/6` (l. 565). Plus aucune
occurrence de `82c8373d` ni de `28/28` dans `s5.sh`. Rien lancé.
Prochaine ligne : additif de prédictions de S5 (nouvelles valeurs), puis S5 `prealables`, sur accord nommé.

## Carte, ligne 9 : deux autres valeurs périmées dans `s5.sh`, correctif d'épinglage 5 préparé (note de 2026-11-16T15:07:58Z ; rien n'est réécrit)
Relecture d'avant `prealables`, à b390e3e, hors ligne : chaque attente de `etape_prealables` est confrontée au dernier journal qui
l'a produite après S5b (Zot neuf le 13/11). Rien lancé.
- **Erreur de la note de 2026-11-15T20:44:46Z** : le « relevé complet » ne l'était pas, et « Restent valables : S4a (`a9d48331`… » est
  faux. Le rejeu de S4a du 13/11 a poussé la pipeline `builder-sbuild@71f84839…` (`s4a-taches.log` l. 10, `s4a-pipeline.log` l. 2) ;
  `s5.sh` l. 44 épingle encore `a9d48331` (10/11). **Cause** : le relevé comparait aux journaux d'avant S5b (`s4a-provenance.log`
  date du 10/11 et n'a pas été rejoué) au lieu de dater chaque valeur par le journal qui l'a produite.
- **Pourquoi ce bundle a changé** : `s4a.sh`, `builder/` et `08-trust-plane/commun.sh` sont inchangés entre 52b00a2 et 774471f
  (`git log`), et les tâches aussi (`prefetch-deb@4dac0609`, `construire-builder@746c2e11` aux deux dates). `etape_taches` signe la
  pipeline à chaque passage (`s4a.sh` l. 218, `tkn pipeline sign`), avec une clé EC P-256 (`politique.sh` l. 371) ; cette signature
  n'est pas versionnée, à la différence de celles des tâches, et une signature ECDSA change à chaque fois. **Explication probable,
  non mesurée** : les spécifications des deux bundles ne sont pas comparées, et la présence de `a9d48331` dans Zot n'est pas relevée.
- **Erreur de la note de 2026-11-15T20:45:27Z** : « plus aucune occurrence de `28/28` » est vrai, mais `prealables` attend encore
  `"8 28"` enveloppes (deb, sample-app) à la l. 264, alors que S4d3 a mesuré 8 et **6** (`s4d3-chemins.log` l. 78-79).
- **Effet sans correctif** : si `a9d48331` est absent de Zot, `prealables` s'arrête à l'export par une erreur de crane, sans ligne
  KO ; sinon, l'écart des enveloppes la fait finir en KO.
- **Troisième valeur, pour les étapes suivantes** : `"False|Failed"` aux l. 324, 330, 375, 379 et 437. Le 11/11 a mesuré
  `False|StepFailed` six fois, chaque fois en ÉCART (`s5-prefetch.log` l. 23 et 37, `s5-miroir.log` l. 28 et 38, `s5-fermeture.log`
  l. 29 et 40). Ne touche pas `prealables`.
- **Correctif d'épinglage 5**, préparé et archivé, **non appliqué** : [`revision-epinglage-5.patch`](../revision-epinglage-5.patch)
  (`git apply --check` code 0) : `PIPE_BUILDER` → `71f84839…` (l. 44), enveloppes de départ → `"8 6"` (l. 264), cinq libellés →
  `False|StepFailed`.
- **Relevé à refaire avec cette datation avant les lignes 10 à 12** : celui du 15/11 couvrait aussi `s6a.sh` et `s6b.sh`. Ne
  bloque pas S5.
- Prédictions de `prealables`, conditionnées au correctif 5 : additif de [`s5-predictions.md`](s5-predictions.md).
Prochaine ligne : correctif d'épinglage 5, sur accord nommé ; puis S5 `prealables`, sur accord nommé.

## Correctif d'épinglage 5 appliqué (note de 2026-11-16T15:08:49Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif d'épinglage 5 ? ». `revision-epinglage-5.patch` appliqué tel quel à `s5.sh`
(`git apply --check` puis `git apply`, code 0 ; diff de l'arbre identique au correctif, `bash -n` code 0) : plus aucune occurrence de
`a9d48331`, de `"8 28"` ni de `"False|Failed"` ; `71f84839` une fois, `"8 6"` une fois, `"False|StepFailed"` cinq fois. Rien lancé.
Prochaine ligne : S5 `prealables` (additif Q1 à Q8 de `s5-predictions.md`), sur accord nommé.

## Carte, ligne 9 : S5 `prealables` (note de 2026-11-16T15:09:57Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S5 `prealables` (lecture et admission à blanc, Q1 à Q8) ? ». `s5.sh prealables` à 7d09bd3, du 16/11 15:09:15 au 16/11 15:09:18 UTC, code 0 relevé juste après la commande, 39 OK, 0 KO,
0 ÉCART ; lignes « S5a prealables » et « fait » dans `chrono.tsv`. Journal `s5-prealables.log` réécrit (version du 11/11 dans git).
- **Q1 à Q8 tenues** (détail dans `s5-predictions.md`) : bundles `71f84839` et `d1fb3871` exportés, quatre tâches dans la liste
  revue, copie de la fermeture conforme au verrou, layouts aux digests du 11/11, 16 objets admis à blanc, enveloppes `8 6`,
  `fermeture-alteree` absent de Zot.
- Reste de S5, à décider : `zot` (écriture dans Zot des deux fermetures altérées, accord à part), puis `prefetch miroir fermeture
  kata sbuild porte retirer`, avec leur additif de prédictions commité avant. `fermeture` exige `zot`.
Prochaine ligne : additif de prédictions des étapes suivantes de S5, puis `zot`, sur accord nommé.

## Carte, ligne 9 : additif des étapes suivantes de S5, correctif 6 préparé (note de 2026-11-16T15:13:21Z ; rien n'est réécrit)
Relecture des étapes `zot` à `retirer` contre les journaux du 11/11 : deux défauts du script, mesurés ce jour-là, n'ont jamais été
corrigés : l'extraction du deb dans `kata` (champ 4 au lieu de 5, `s5-kata.log` l. 21) et le libellé « Hash Sum mismatch » de N1
dans `prefetch` (`s5-prefetch.log` l. 26, libellé réel « Hashes of received file », l. 17). Le bilan du 11/11 les nommait ; la
correction n'a pas suivi. **Correctif 6** préparé et archivé, **non appliqué** :
[`revision-correctif-6.patch`](../revision-correctif-6.patch) (`git apply --check` code 0 ; extraction essayée sur
`s4d-pipeline-1-construire.log` : champ 4 « sample-a », champ 5 « f66bbeb2 »). Additif Q9 à Q22 dans `s5-predictions.md`. Rien lancé.
Prochaine ligne : correctif 6, sur accord nommé ; puis `zot`, sur accord nommé.

## Correctif 6 appliqué (note de 2026-11-16T15:17:47Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif 6 ? ». `revision-correctif-6.patch` appliqué tel quel à `s5.sh` (`git apply --check`
puis `git apply`, code 0 ; diff de l'arbre identique au correctif ; `bash -n` code 0) : extraction du deb de N7 au champ 5 (l. 460,
plus aucune au champ 4) ; N1 mesure « Hashes of received file » (l. 327) ; « Hash Sum mismatch » ne reste que dans la mesure de N4.
Rien lancé.
Prochaine ligne : S5 `zot` (écriture dans Zot, Q9), sur accord nommé.

## Carte, ligne 9 : S5 `zot` (note de 2026-11-16T15:26:59Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S5 `zot` (écriture dans Zot des deux fermetures altérées, Q9) ? ». `s5.sh zot` à 012cd11, du 16/11
15:25:43 au 16/11 15:26:41 UTC, code 0 relevé juste après la commande, 2 OK, 0 KO, 0 ÉCART ; lignes « S5a zot » et « fait » dans
`chrono.tsv` ; journal `s5-zot.log` réécrit (version du 11/11 dans git) ; dossier d'identifiants `auth` retiré par l'étape.
- **Q9 tenue** : les deux fermetures altérées sont dans Zot à `a549729d…` et `b27225cf…`.
Prochaine ligne : S5 `prefetch miroir fermeture kata sbuild porte retirer` (Q10 à Q22), sur accord nommé.

## Carte, ligne 9 : S5 `prefetch miroir fermeture kata sbuild porte retirer` (note de 2026-11-16T15:41:03Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S5 `prefetch miroir fermeture kata sbuild porte retirer` (Q10 à Q22) ? ». À 91e76f7, en
arrière-plan, du 16/11 15:27:20 au 16/11 15:40:27 UTC, code 0 relevé par la même commande, **72 OK, 0 KO, 0 ÉCART** ; les sept
lignes « fait » sont dans `chrono.tsv` (`prefetch` 21 s, `miroir` 4 min 34 s, `fermeture` 34 s, `kata` 5 min 43 s, `sbuild` 57 s,
`porte` 57 s, `retirer` 1 s). Journaux `s5-{prefetch,miroir,fermeture,kata,sbuild,porte,retirer}.log` et `s5-sbuild-build.log`
réécrits (versions du 11/11 dans git) ; aucune ligne `jeton|token`.
- **Q10 à Q22 tenues** (détail dans `s5-predictions.md`) : N1 à N7 refusent, leurs témoins réussissent ; N7 sous Kata produit
  `f66bbeb2` et D `60f25f5c` ; enveloppes inchangées ; porte : deb VSA et scan refusés, sample-app `ok|ok`. **Ligne 9 close.**
- U13 n'est pas jugée par S5 (note du 15/11). Le refus du scan de D confirme que le CronJob deb ne scanne pas D
  (`scan.scan_present`, 0 énoncé), cohérent avec la cible `039949f9` rendue le 14/11.
Prochaine ligne : relecture hors ligne de `ScanEnRetard` (U13) et relevé daté des épinglages de `s6a.sh` et `s6b.sh`, puis S6a
`periodique fraicheur grafana` (ligne 10, refusée de 09:00 à 12:59 UTC), sur accord nommé.

## Carte, ligne 10 : relecture de `ScanEnRetard` (U13) et relevé daté de `s6a.sh` et `s6b.sh` (note de 2026-11-16T15:55:25Z ; rien n'est réécrit)
Relecture hors ligne, à f9a7938, relue par le conseiller. Rien lancé, rien lu dans le cluster, dans Zot ni sur `sc-stockage`.
- **U13 : mécanisme relu, non mesuré.** `ScanEnRetard` (`19-observabilite/config/regles/alertes.yml` l. 81-86) se déclenche, par
  dépôt, si le dernier referrer de scan a plus de 26 h, ou si la série d'un des deux dépôts manque (`for: 5m`). La série est écrite
  par `fraicheur-scan.py` sur `sc-stockage` pour le digest fixé dans `SCANS`, que `s6a.sh fraicheur` a posé le 14/11 sur
  `039949f9` (`s6a-fraicheur.log`). L'alerte ne voit donc pas D : elle reste inactive tant que les passages de 11:15 UTC sur
  `039949f9` réussissent, et aucun journal archivé ne montre ceux des 15/11 et 16/11. **Erreur de la ligne U13 de la carte** : c'est
  `fraicheur` qui fait passer la série sur D, pas `periodique` (qui rend le CronJob sur D). U13 se lira par une lecture seule sur
  `sc-stockage`, sur accord, avant `periodique` : historique de `ALERTS{alertname="ScanEnRetard"}` depuis 2026-11-15T20:39:34Z,
  valeur actuelle de la série du deb, notifications de `ScanEnRetard` au récepteur.
- **Contrainte de délai.** Après `periodique`, plus rien ne rafraîchit la série de `039949f9` : `fraicheur` doit passer avant son
  dernier referrer plus 26 h (échéance donnée par la lecture ci-dessus). Si `periodique` finit en KO après avoir appliqué le
  CronJob, ou si `fraicheur` est refusée, l'alerte sonnera à cette échéance. `grafana` refuse dès qu'un passage planifié a eu lieu
  après `periodique` (`s6a.sh` l. 480-484) : elle doit passer avant 09:30 UTC le lendemain. `periodique` refuse de 09:00 à 12:59 UTC
  (l. 270).
- **Une étape par appel** : `s6a.sh` n'en accepte qu'une (l. 528). La ligne 10 fait trois commandes ; code relevé après chacune,
  arrêt au premier non nul.
- **Relevé de `s6a.sh`** :
  - datées après S5b : `DEB_SHA` f66bbeb2 (S3 du 14/11 ; N7 de S5 le 16/11, `s5-kata.log`) ; `DEB_REF` 60f25f5c (S4d3 du 15/11,
    `s4d3-porte.log` ; présent dans Zot le 16/11, `s5-porte.log`) ; `APP_REF` 3a7ca1b1, égal à `IMAGE` de `plateforme.sh` (07a),
    sample-app jugée `ok|ok` le 16/11 (`s5-porte.log`). Ligne `DEB|sample-app_1.0.0-2_amd64.deb, sha256 f66bbeb2…` attendue
    aux l. 360 et 496 : `scanner.sh` (07a, l. 61) affiche le nom du seul fichier de la couche, que `deb/construire-deb.yaml`
    (l. 112-124) y met tel que sbuild l'a produit ; la construction de D sous Kata le 16/11 a produit
    `sample-app_1.0.0-2_amd64.deb f66bbeb2` avec `60f25f5c` (`s5-n7-kata.log` du cache, écrit à 15:38:32Z ; `s5-kata.log`).
  - constantes de la 07a (`val07`, `OUTILS`, `BASE_DIGEST`) égales à `plateforme.sh` ; aucun commit depuis 4229318 (14/11) sur
    `scanner.sh`, `fraicheur-scan.py`, `alertes.yml`, `scan-job.yaml`, `plateforme.sh` ni `limites.tsv` ; réciproques des trois
    `s6a-*.patch` applicables (`git apply -R --check`, code 0).
  - non vérifiée : `ARBRE` (6391fd43 est un commit du dépôt de Forgejo, absent de ce dépôt) ; ne sert qu'à `releve`.
  - **non datée par un journal** : le 14/11, `comparer_cronjobs` a tourné avant que `scan-sample-app-deb` existe ; cette fois,
    `kubectl apply --dry-run=server` (apply côté client) porte sur l'objet créé par `--server-side`. À mesurer par
    `S6A_SEC=1 periodique`, qui n'écrit rien (précédent : `s6a-periodique-sec.log`, 14/11, 20:58:42Z).
  - commentaires périmés, sans effet : `# S4d1` (l. 54), `039949f9` dans l'en-tête (l. 6).
  - écarts attendus au 14/11 : D au lieu de `039949f9` ; referrers de D dans `builds/scan/sample-app-deb` 0 avant (porte de S5 :
    `scan.scan_present`), 1 après ; CronJob `scan-sample-app-deb` mis à jour, non créé ; fichier complémentaire réécrit sur D.
- **Relevé de `s6b.sh` et de `rejeu/`, pour la ligne 11 (sans effet sur la ligne 10)** :
  - datées après S5b : `DEB_DIGEST` D ; `ENTREES` bb7599a2, 50dc73f7, f0ed7a71 (relues par S5 le 16/11) ; `CHROOT_SHA` aec1c7a9 et
    451786240 octets (`s4a-pipeline.log`, 13/11, 14:52:43Z).
  - d'avant S5b, indépendantes de Zot : `INRELEASE`, `PACKAGES_XZ`, `CLES`, `SDE` (S1 du 10/11, instantané 20261105T000000Z fixe) ;
    `EPINGLES` (V3 du 12/11, paquets de la VM).
  - **périmée** : `INVOCATION=454728c5` (l. 118), PipelineRun de `039949f9` (décision 1 du 12/11). Le nom figure aussi dans la
    politique figée `rejeu/politique-replay-deb.md` (l. 16) et dans un commentaire de `verifier_deb.py` (l. 3) ; les scripts de
    `rejeu/` n'épinglent rien d'autre (sujet et invocation passés en argument). Le choix parmi les provenances de D (dont
    c3d27e05, chemin 2 de S4d3, la plus récente, seule jugée par la porte) est une décision du propriétaire, suivie d'un correctif
    sur accord ; une nouvelle version de la politique figée est aussi à décider. `finishedOn` de c3d27e05 non relevé : créé à
    2026-11-15T20:31:44Z (`s4d3-chemins.log` l. 41), donc `rebuild` pas avant 2026-11-16T20:31:44Z.
  - journaux et fichiers périmés : la garde d'`etape_vsa` lit `s6b-rebuild.log`, dont la version du 12/11 (sur `039949f9`) la
    satisfait ; `vsa_deb.py` refuserait dans la VM (manifeste reconstruit comparé au sujet, l. 50). `s6b-vsa.bundle.json` et
    `s6b-vsa-enonce.json` portent `039949f9` : `pousser_vsa` les refuse (sujet comparé à D, l. 739). L'ordre `transporter`,
    `verifier`, `rebuild`, `vsa` est à fixer dans l'additif de la ligne 11.
  - messages périmés, sans effet : `039949f9` aux l. 746 et 749.
Prochaine ligne : additif de prédictions de la ligne 10 dans `s6a-service-predictions.md` (lecture seule de U13, `S6A_SEC=1
periodique`, puis `periodique`, `fraicheur`, `grafana`), sur accord ; puis chaque lancement sur accord nommé.

## Carte, ligne 10 : additif de prédictions préparé (note de 2026-11-16T16:02:49Z ; rien n'est réécrit)
« Oui, prépare-le » à « Je prépare l'additif de prédictions de la ligne 10 ? ». Additif L1 à L13 dans
[`s6a-service-predictions.md`](s6a-service-predictions.md), relu par le conseiller ; nouveau script de lecture seule
[`lecture-u13.sh`](../lecture-u13.sh) (U13 lue avant `periodique` et après `fraicheur`, une lecture ratée rend le code 1), essayé
hors réseau avec des commandes simulées. Six commandes, chacune sur accord nommé : `lecture-u13`, `S6A_SEC=1 periodique`,
`periodique`, `fraicheur`, `grafana`, `lecture-u13` après. Rien lancé.
Prochaine ligne : `lecture-u13.sh` (L1 à L7), sur accord nommé.

## Carte, ligne 10 : `lecture-u13.sh` (note de 2026-11-16T16:04:43Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance lecture-u13.sh (lecture seule, L1 à L7) ? ». Du 16/11 16:04:21 au 16/11 16:04:22 UTC, code 0, toutes
les lectures faites. **L1 à L7 tenues** (détail dans `s6a-service-predictions.md`) : passages du deb des 15/11 et 16/11 réussis sur
`039949f9`, aucun scan de D, aucune alerte de scan ni notification depuis 2026-11-15T20:39:34Z. **U13 tenue jusqu'à 16:04:21Z.**
Échéance pour `fraicheur` : 2026-11-17T13:16:51Z.
Prochaine ligne : `S6A_SEC=1 s6a.sh periodique` (L8, rien d'écrit), sur accord nommé.

## Carte, ligne 10 : `S6A_SEC=1 periodique` (note de 2026-11-16T16:06:10Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance S6A_SEC=1 s6a.sh periodique (L8, rien d'écrit) ? ». Le 16/11 à 16:05:44 UTC, code 0, rien d'écrit
dans le cluster ni dans Zot ; **L8 tenue** (gabarit égal sur le CronJob existant, avertissement de kubectl annoncé). Lignes
« S6a periodique » et « fait » dans `chrono.tsv` ; journal renommé en `s6a-periodique-sec.log`.
Prochaine ligne : `s6a.sh periodique` (L9, L10 : cluster et Zot, premier scan de D ; refusé de 09:00 à 12:59 UTC), sur accord nommé.
