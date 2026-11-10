# Brique 06 : deb hermétique avec sbuild (debian-13), protocole proposé

Seuil (README, brique 06) : **bit-identique ; 0 pod privilégié sur l'hôte.** Effort estimé : **2 pw** ; décision avec le propriétaire à 4 pw.

Règles reprises : celles de la [brique 05](../05-rpm-mock/README.md). sbuild et mmdebstrap sont « À surveiller », chemin critique, au doc 04 ; plan de sortie : paquets Debian épinglés.

## État

**Préparé à sec le 05/11/2026 à 22:21 UTC, rien installé, rien construit.** Le relevé amont est commun avec la 05 ([journal](../05-rpm-mock/resultats/releve-amont.log)). Les jalons S1 et suivants attendent le rejeu RKE2 (08b), les décisions ci-dessous et un accord pour chacun.

## Ce qui existe déjà

- **Recettes** : [`poc/packaging/debian`](../../packaging/README.md), format `3.0 (quilt)`, debhelper 13.
- **Mesure d'OBS** : deb identique d'emblée sur 2 builds (`0b489d43…`), hors ligne compris ; `.buildinfo` et `.changes` diffèrent par la date ([résultats](../../benchmarks/obs/resultats/README.md)).
- **Limite d'OBS** : son DoD a rejeté `snapshot.debian.org`, ce qui ne dit rien de sbuild.

## Relevé amont (05/11/2026, 22:26 UTC)

| Point | Mesuré | Conséquence |
|---|---|---|
| Versions Debian stable | sbuild **0.89.3+deb13u4**, mmdebstrap **1.5.7-1+deb13u1**, golang-go 2:1.24~2, nodejs 20.19.2+dfsg-1+deb13u2, diffoscope 297+deb13u1, reprotest 0.7.30 | Paquets de stable, pas la dernière version amont du doc 04 |
| Instantané | `snapshot.debian.org/archive/debian/20261105T000000Z` : `InRelease` HTTP 200 après une redirection vers `/file/<sha1>` du même hôte, sha1 égal à celui du contenu ; trixie, daté du 12/09/2026, sans `Valid-Until` | Pas de contournement de date à prévoir pour cette suite |
| `uidmap` 1:4.17.4-2 (sha256 conforme à l'index de l'instantané) | `newuidmap` et `newgidmap` en **setuid root**, sans `postinst` | Pas de capacités de fichier dans le paquet : voir le risque principal |
| Mode `unshare` (manuel de sbuild, tag `debian/0.89.3+deb13u4`) | Construit dans une archive de chroot, ne dépend que de deux binaires setuid, `newuidmap` et `newgidmap` ; pas de réseau pendant le build, par défaut | Compte non root et plages `subuid` et `subgid` à déclarer dans l'image |

Le manuel `sbuild-unshare` cherché dans ce tag n'existe pas à ce chemin : les détails du mode restent à mesurer en S1.

## Risque principal : `newuidmap` sous Kata

La brique 08 a mesuré en J7 que `newuidmap` échoue sous Kata 4.3.1, même dans un pod privilégié (« Could not set caps », [journal](../08-trust-plane/resultats/buildkit-exempte.log)). Cause mesurée : virtiofsd tourne sans `--xattr`, donc les capacités de fichier ne sont pas visibles dans l'invité. Or le mode `unshare` de sbuild dépend de ce binaire.

**Différence relevée** : dans cette mesure, `newuidmap` portait des capacités de fichier, sans bit setuid. Le paquet `uidmap` de Debian 13 l'installe en setuid root, sans capacités de fichier. La cause de J7 ne s'applique donc pas telle quelle. **Reste à mesurer** si un setuid agit sur la racine `virtiofs` de l'invité. S1 commence par là.

Replis, dans l'ordre, si `newuidmap` échoue :
1. placer le binaire et ses capacités sur un tmpfs de l'invité, où l'attribut étendu a été accepté en J7 ;
2. lancer sbuild en root dans le pod Kata, sans `unshare`, si un mode le permet (à lire avant S1) ;
3. activer `--xattr` dans la configuration de Kata : changement de la plateforme, décision du propriétaire.

## Préalables au doc 04

L'image de base Debian de `builders/sbuild-debian13` n'est pas auditée au doc 04 (recherche du 05/11/2026). Elle sera choisie par digest, avec sa signature si elle existe, et auditée avant tout usage. Un verdict « Risqué » arrêterait cette voie. sbuild et mmdebstrap sont déjà au doc 04.

**Additif du 05/11/2026, 22:37 UTC, audit fait, rien installé** ([journaux de la 05](../05-rpm-mock/resultats/sante-signatures.log)). Verdict de `debian:trixie-20261104-slim` et de debuerreotype : **« À surveiller », chemin critique, avec une échéance** (doc 04, §3, §5, §6). Le digest amd64 `sha256:7378260c…` est identique à l'OCI publié dans `docker-debian-artifacts`, mais l'image n'est pas signée, et son attestation SPDX non plus. **Dernière release de debuerreotype : 0.17 du 08/12/2025 : sans nouvelle release, ce projet devient « Risqué » le 09/12/2026**. **Verdict limite dès aujourd'hui** : un seul compte fait les 100 fusions et les 2 commits mesurés ; le second mainteneur est déclaré, mais son activité n'a pas été mesurée. D'où la décision D4.

## Décisions à prendre

**D1. Isolation.** Recommandé : **(a)**.
- (a) Pod Kata privilégié (voie A). Le pod reste en dehors de `restricted`, comme BuildKit. Les replis ci-dessus restent ouverts.
- (b) Pod Kata non privilégié. Plus strict, mais la 08 a mesuré qu'en `restricted`, BuildKit rootless n'exécute aucune étape `RUN`, et `newuidmap` y échoue de la même façon. À mesurer en S1 : si cela passe, (b) devient préférable.

**D2. Fermeture.** Recommandé : **(a)**.
- (a) Dépôt apt local construit depuis les paquets du `.buildinfo`, archivés fichier par fichier dans Zot. C'est le modèle du doc 02, et il permet la déduplication. Les paquets sont vérifiés par leurs empreintes ; `[trusted=yes]` ne vaut que pour ce dépôt restauré.
- (b) Tout préinstaller dans l'archive du chroot. Plus simple, un seul digest, mais pas de déduplication par paquet : B4 serait à revoir.

**D3. Source des paquets.** Recommandé : **(a)**.
- (a) Instantané daté de `snapshot.debian.org` pour la résolution, chemin vérifié ci-dessus.
- (b) `deb.debian.org`, dont le contenu bouge.

**D4. Base de l'image du constructeur** (ajoutée le 05/11/2026, 22:37 UTC, après l'audit). Recommandé : **(a)**.
- (a) Base produite par mmdebstrap depuis l'instantané, archive signée par Debian. L'image `debian` sert au plus d'amorce une fois, puis disparaît. Plus de dépendance à debuerreotype, mais une étape de plus à construire et à mesurer.
- (b) `debian:trixie-20261104-slim` par digest après revue. Immédiat, mais soumis à l'échéance du 09/12/2026.

## Jalons proposés

| Jalon | Contenu | Preuve attendue |
|---|---|---|
| S1 | Après le préalable au doc 04 : image `builders/sbuild-debian13`, base Debian par digest, paquets épinglés ; essai à la main dans un pod Kata : d'abord `newuidmap`, puis `sbuild --chroot-mode=unshare`, compte non root, D1 (b) mesuré, replis si besoin | Journal des essais ; mode retenu motivé |
| S2 | Archive du chroot par mmdebstrap depuis l'instantané, construite deux fois ; résolution depuis un `.buildinfo` ; fermeture dans Zot sous `deps/sample-app/deb-buildinfo` | Empreinte de l'archive comparée ; fermeture restaurable ; déduplication mesurée |
| S3 | Deux builds sans réseau depuis la fermeture restaurée, dans deux répertoires différents | Même sha256 pour le deb ; sinon diffoscope |
| S4 | Tâches signées dans la pipeline ; deb poussé par ORAS sous `artifacts/sample-app/deb` ; `.buildinfo` joint ; provenance de Chains | Sujet deb signé, digest de la fermeture dans `resolvedDependencies` |
| S5 | Mêmes tests négatifs que M5 de la 05 ; un rejeu de zéro | Refus attendus, témoins acceptés |

## Prédictions (05/11/2026, 22:21 UTC, avant toute exécution)

| # | Prédiction | Confiance |
|---|---|---|
| 1 | S3 donne deux deb identiques sans réglage supplémentaire | Haute : déjà vrai sur OBS, sample-app inchangé |
| 2 | L'empreinte peut coïncider avec `0b489d43…` ou non, selon la version de Go de l'instantané | Pas de prédiction : l'égalité n'est pas exigée |
| 3 | `unshare` échoue au premier essai dans un pod Kata privilégié, sur `newuidmap`, et il faut un repli | Moyenne : échec mesuré en J7 avec des capacités de fichier, cas du setuid non mesuré |
| 4 | `unshare` échoue aussi en pod Kata non privilégié (D1 b) | Moyenne : même cause que BuildKit en `restricted` |
| 5 | L'archive de mmdebstrap est identique sur deux constructions | Moyenne : suppose `SOURCE_DATE_EPOCH` et un instantané fixe |
| 6 | Build hors ligne en moins de 5 min (deb d'OBS : 41 s de build) | Moyenne |
| 7 | La brique 06 coûte moins que la 05, sans podman imbriqué, si un repli sans changement de Kata suffit | Faible : dépend de la prédiction 3 |

**Additif du 05/11/2026, 22:26 UTC, après ces prédictions et avant toute exécution** : le paquet `uidmap` installe `newuidmap` en setuid root, sans capacités de fichier. La prédiction 3 reste écrite, mais son appui faiblit : sa confiance passe de moyenne à **faible**, et la prédiction 7 en dépend. Aucune mesure n'a tranché.

## Limites connues

- **Hors du seuil** : scan et licences du deb (07a, 13a), signature OpenPGP (09), replay séparé (10).
- **sbuild de stable** : 0.89.3 contre 0.91.10 en amont. Choix d'épinglage cohérent avec le doc 04, à revoir à chaque version mineure de Debian.
- **`snapshot.debian.org`** n'est lu qu'à la résolution : à partir de S3, seule la fermeture compte.

## Additif du 10/11/2026, 12:14 UTC : D1 à D4 décidées, option (a) partout

Décision du propriétaire : « Briques 05 et 06 : je recommande (a) pour D1 à D4. Tu valides ? », réponse « oui ». Rien n'a été lu ni écrit dans le cluster, Zot ou les VM.
- **D1 (a)** : pod Kata privilégié (voie A). La clause reste : si un pod Kata non privilégié passe en S1, (b) redevient à examiner.
- **D2 (a)** : dépôt apt local construit depuis les paquets du `.buildinfo`, archivés fichier par fichier dans Zot.
- **D3 (a)** : instantané daté de `snapshot.debian.org` pour la résolution.
- **D4 (a)** : base produite par mmdebstrap depuis l'instantané.

**Aucun jalon n'est lancé.** S1 et chaque jalon suivant demandent un accord à part.

## Additif du 10/11/2026, 13:03 UTC : S1 préparé, NON LANCÉ

Le propriétaire a choisi « S1 de la 06 ». Cette réponse est consignée comme une interprétation : elle désigne le jalon, et les effets précis attendent un accord nommé.

- Script : [`s1.sh`](s1.sh), avec les étapes `prealables`, `amorce`, `racine`, `image` et `essais`.
- Prédictions P1 à P11 : [`resultats/s1-predictions.md`](resultats/s1-predictions.md), écrites avant toute exécution.

Rien n'a été lu ni écrit dans le cluster, Zot ou les VM.

**Lu sur l'hôte** :
- le manuel de sbuild au tag : le repli 2 se ferait en mode `sudo` ou `autopkgtest`, sans coupure du réseau par sbuild ;
- les signataires de l'instantané, avec les clés de ftp-master ;
- les versions épinglées dans `Packages`.

**D4 (a)** : la racine de l'image vient de mmdebstrap, et `debian:trixie-20261104-slim` ne sert que d'amorce. L'image d'essai va dans `essais-06/`, et `builders/` attend S2.

## Additif du 10/11/2026, 13:14 UTC : S1 exécuté, risque principal levé pour D1 (a), sbuild en échec de build

S1 a été exécuté de 13:04 à 13:11 UTC, sur l'accord « Oui, lance S1 ». Détail : [prédictions et résultat](resultats/s1-predictions.md).

**Tenues**
- P1 à P7, et P11 à ce stade.
- **`newuidmap` fonctionne dans un pod Kata privilégié**, où `/` est monté sans `nosuid`. La prédiction 3 de ce README est réfutée, et les replis 1 à 3 deviennent sans objet.

**Réfutées**
- **P8** : sbuild sort avec le code 2 dans `dpkg-buildpackage`. Le journal `.build` n'a pas été gardé, par défaut du script.
- **P9** : en Kata non privilégié (D1 b), `newuidmap` échoue (EPERM sur `uid_map`), cause non diagnostiquée. D1 (b) est écarté.

**P10 tenue sur l'issue, motif réfuté.**

**Constat (P3)** : un pod de `builds` sans label joint `snapshot.debian.org` en http.

**Diagnostic statique de P8** : Go, nodejs et debhelper ont les mêmes versions qu'OBS, qui a construit ce `.dsc`. La cause reste inconnue.

**Relance préparée, NON LANCÉE** : étape `relance` du script, prédictions RL1 à RL3, accord nommé attendu.

Push de 12:50:22 UTC (`f4eecab..9e8e1a3`, 6 fichiers) consigné, car il manquait à l'additif de 13:03.

## Additif du 10/11/2026, 13:24 UTC : cause de l'échec de sbuild trouvée ; second passage s1b préparé, NON LANCÉ

La relance a eu lieu à 13:22 UTC, sur l'accord « Oui, relance ». RL1 et RL2 sont tenues, RL3 est réfutée.

**Cause** : `ip` manque dans l'image. sbuild ne fait que recommander `iproute2`, et mmdebstrap n'installe pas les recommandations. C'est un défaut de préparation, pas une limite de Kata.

**Second passage `s1b`, NON LANCÉ** : `iproute2=6.15.0-1` est ajouté, et le chroot du premier passage est réutilisé.
- Nouvelle image : `essais-06/sbuild-debian13:s1b`.
- Prédictions B1 à B4 : [`resultats/s1-predictions.md`](resultats/s1-predictions.md).
- Accord nommé attendu.
