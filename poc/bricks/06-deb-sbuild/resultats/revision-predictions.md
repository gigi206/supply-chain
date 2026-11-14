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
