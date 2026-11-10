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

## Additif du 10/11/2026, 13:29 UTC : S1 clos, mode retenu sbuild unshare en pod Kata privilégié

Le second passage `s1b` a été exécuté de 13:24 à 13:28 UTC, sur l'accord « Oui, lance s1b ». B1 à B4 sont tenues ; détail dans les [prédictions et résultats](resultats/s1-predictions.md).

**Résultat**
- sbuild construit sample-app en 79 s.
- **Le deb (`0b489d43…`) est identique, octet pour octet, à celui d'OBS.** Aucune prédiction n'avait été faite sur ce point.

**Mode retenu** : `sbuild --chroot-mode=unshare` dans un pod Kata privilégié (D1 a), sous l'UID 1000.

**Écartés** : D1 (b), et les replis 1 à 3.

**Image d'essai** : `essais-06/sbuild-debian13@sha256:d8041f9c…`. Elle contient iproute2 en plus de sbuild, mmdebstrap et uidmap.

**Reste**
- S2 : fermeture D2 (a), constructions reproductibles, image sous `builders/`.
- Le constat P3, une sortie http d'un pod de `builds` sans label, à soumettre au propriétaire.

*Corrigé à 13:30 UTC, avant tout push* :
- **Coupure du réseau** : elle vient du manuel de sbuild et n'est pas mesurée (test négatif prévu en S5).
- **Égalité avec OBS** : elle porte sur les 64 caractères de l'empreinte, comparés au journal `build-1/construire.log` d'OBS.
- **Fichiers non rapatriés** : le `.deb`, le `.buildinfo` et les `.changes` sont restés dans le pod ; la prochaine étape devra copier `/w/sortie`.
- **ADR 0001** : additif ajouté.

## Additif du 10/11/2026, 14:24 UTC : étape racine de s1.sh sous builds-sans-internet

Depuis 13:55:03 UTC, la règle `builds-sans-internet` de la 08c refuse Internet aux pods de `builds` sans label. Le pod `racine` de `s1.sh` en est un : l'étape ne joindrait plus `snapshot.debian.org`. C'est déduit du témoin sans label de la 08c, pas mesuré sur `racine`.

`s1.sh` pose désormais `tekton.dev/task=prefetch-deb` sur ce pod, et sur sa spec du dry-run d'admission. La sortie dédiée `prefetch-deb-sortie` est préparée à sec dans la [08c](../08c-durcissement/resultats/sortie-deb-predictions.md), **non appliquée**. Tant qu'elle ne l'est pas, `racine` reste cassée. S2 a le même besoin.

## Additif du 10/11/2026, 14:35 UTC : sortie dédiée posée

Depuis 14:29 UTC, `prefetch-deb-sortie` est en service dans la [08c](../08c-durcissement/resultats/sortie-deb-predictions.md).

Un témoin runc au label `prefetch-deb` joint `snapshot.debian.org` en 80, et rien d'autre parmi les destinations testées. L'étape `racine` de `s1.sh` devrait donc repasser.

**Ce n'est pas mesuré** sur `racine` elle-même, dans un pod Kata : c'est E3, qui demande un accord distinct.

## Additif du 10/11/2026, 14:41 UTC : étape racine rejouée avec le label (E3 de la 08c)

Passage `PREFIXE=s1c s1.sh racine` de 14:36 à 14:41 UTC, sur l'accord « Oui, lance E3 ». Journal : [`s1c-racine.log`](resultats/s1c-racine.log).

**L'étape repasse sous `builds-sans-internet`**, grâce à `prefetch-deb-sortie`. L'InRelease est identique à celui de l'hôte, et les 238 `.deb` sont conformes.

**Archives identiques aux passages précédents, octet pour octet**
- racine : `f8f221ca…`, comme en s1b ;
- chroot : `440ba93b…`, comme en s1.

C'est un premier indice de reproductibilité pour S2, pas sa preuve.

## Additif du 10/11/2026, 15:51 UTC : S2 préparé, étape hors ligne tenue

[`s2.sh`](s2.sh) et les [prédictions Q1 à Q12](resultats/s2-predictions.md) ont été écrits et commités avant toute exécution.

**Le `.buildinfo` de sample-app est retrouvé sans nouveau build.** sbuild l'imprime dans son journal, archivé en s1b. L'étape `buildinfo` le reconstitue à l'octet près (`a2d1a419…`, l'empreinte du `.changes`).

Ses 162 paquets sont tous dans l'instantané, à la version exacte. La fermeture attendue fait 194 Mo, en 162 fichiers. L'étape a tourné sur l'hôte seul, hors ligne, avec le code 0.

**Non lancé** : le chroot `buildd` construit deux fois, le téléchargement de la fermeture, son envoi dans Zot et sa restauration. Chaque étape attend un accord nommé.

**Non mesurable en S2** : la déduplication entre deux fermetures, car il n'en existe qu'une.

## Additif du 10/11/2026, 15:58 UTC : étape racine de S2 tenue

Passage de 15:53:52 à 15:57:40 UTC, sur l'accord « Oui, lance racine ». Code 0. Journal : [`s2-racine.log`](resultats/s2-racine.log).

**Le chroot `buildd` sans dépendances (D2 a) sort identique sur deux constructions** : `e0b1f37c…`, 509 Mo. Les deux ont été faites dans le même pod, coup sur coup.

**La fermeture du `.buildinfo` est téléchargée et conforme** : 162 .deb, 194 Mo, chacun identique à `Packages`. Elle est sur l'hôte, pas encore dans Zot.

**Reste** :
- l'envoi dans Zot et la restauration par digest, sur accord ;
- puis S3 : deux builds hors ligne depuis la fermeture restaurée.

## Additif du 10/11/2026, 16:25 UTC : fermeture dans Zot, étape arrêtée en code 1

La fermeture est écrite dans Zot, sous `deps/sample-app/deb-buildinfo@sha256:3a0e54ae…` (tags `s2` et `s2-bis`), sur l'accord « Oui, lance-les ». Le second envoi a donné le même digest.

L'étape s'est ensuite arrêtée en code 1, sur une option refusée par `oras manifest fetch`. Le contrôle des couches et la restauration n'ont pas tourné.

Le script est corrigé à sec, **non rejoué**. Le rejeu attend un nouvel accord. Détails : [prédictions de S2](resultats/s2-predictions.md).

## Additif du 10/11/2026, 16:31 UTC : S2 tenu, sauf la déduplication

Rejeu de `fermeture restauration` de 16:31:17 à 16:31:20 UTC, sur l'accord « Oui, rejoue-les ». Code 0.

**La fermeture est restaurable** : `deps/sample-app/deb-buildinfo@sha256:3a0e54ae…` (même digest qu'au premier passage), 162 couches. Le digest de chaque couche est le SHA256 du paquet dans `Packages`. La restauration par digest redonne les 162 fichiers, identiques à la liste attendue.

**Jalon S2** : chroot reproductible, résolution depuis le `.buildinfo`, fermeture dans Zot et restauration, **tenus**. **La déduplication entre deux fermetures n'est pas mesurée** : il n'en existe qu'une.

**Reste** : S3, non préparé.

## Additif du 10/11/2026, 16:45 UTC : S3 préparé, NON LANCÉ

Le propriétaire a répondu « continue » à 16:36:51 UTC. Cette réponse n'autorise rien sur le cluster, Zot ou les VM : seule la préparation à sec est engagée.

[`s3.sh`](s3.sh) et les [prédictions R1 à R12](resultats/s3-predictions.md) sont écrits avant toute exécution dans le cluster ou Zot.

**Mécanisme, lu dans le code de sbuild 0.89.3** : `--extra-package=/w/fermeture` sert la fermeture restaurée comme dépôt local du chroot. Deux précautions s'ajoutent :
- **Les sources de l'instantané sont neutralisées dans le chroot**, par `--chroot-setup-commands`, car le chroot de S2 les garde. Sans cela, apt pourrait prendre les paquets sur l'instantané plutôt que dans la fermeture.
- **Pod sans label**, sous `builds-sans-internet`, avec un témoin TCP qui doit échouer. sbuild ne coupe le réseau que pendant `dpkg-buildpackage`, pas pendant l'installation des dépendances.

**Simulation hors ligne sur l'hôte, code 0** ([journal](resultats/s3-simulation.log)) : depuis la fermeture seule, apt installe 48 paquets. Avec les 114 du chroot, cela fait exactement les 162 de Installed-Build-Depends.

**Non lancé** : la restauration et les deux builds. Chaque étape attend un accord nommé. Deux questions sont posées : le chroot de S2 copié dans `/w` plutôt qu'une nouvelle image, et la neutralisation des sources.

Push de 16:32:36 UTC (`4072aee..fc4afa3`, 13 fichiers) consigné.

## Additif du 10/11/2026, 16:49 UTC : restauration de S3 tenue

L'étape `restauration` a tourné de 16:49:42 à 16:49:43 UTC, sur l'accord « Oui, lance restauration ». Code 0. Journal : [`s3-restauration.log`](resultats/s3-restauration.log).

Les deux pulls par digest de la fermeture de S2 redonnent chacun 162 fichiers. Les empreintes sont identiques à la liste attendue (R1).

**Non lancés** : les deux builds et la comparaison. Ils attendent un accord nommé, et les questions sur le chroot et la neutralisation des sources restent ouvertes.

## Additif du 10/11/2026, 17:43 UTC : builds de S3 bloqués sur la copie du chroot, arrêtés, script corrigé à sec

Lancés à 16:52:09 UTC sur l'accord « Oui, lance builds ». Le pod `s3-build-1` était prêt, mais la copie du chroot (509 Mo) par `kubectl exec -i … cat` ne s'est jamais terminée, alors que kubectl avait lu tout le fichier.

- Étape arrêtée à 17:42 UTC et pod supprimé, sur la réponse « Ok ».
- Aucun build n'a tourné. Journal : [`s3-builds-1.log`](resultats/s3-builds-1.log).
- **Correction à sec, NON REJOUÉE** : copies à nombre d'octets exact (`head -c`), délai, taille comparée dans le pod. Un nouvel accord est attendu. Détails : [prédictions de S3](resultats/s3-predictions.md).

## Additif du 10/11/2026, 17:54 UTC : rejeu des builds de S3, même blocage, arrêté

Le rejeu a été lancé à 17:44:28 UTC, sur l'accord « Oui ». Il s'est bloqué à la même copie du chroot, cette fois avec `head -c`, qui ne dépend pas de la fin de flux. L'étape a été arrêtée à 17:53 UTC, sur « Arrête et propose ». Le pod a été supprimé par le script. Journal : [`s3-builds-2.log`](resultats/s3-builds-2.log).

**Aucun build n'a tourné.** Le transfert vers le pod par l'entrée standard de `kubectl exec` est écarté pour 509 Mo. Une autre voie est à décider.

## Additif du 10/11/2026, 18:07 UTC : sonde du transfert vers le pod, blocage propre à Kata

Sonde lancée de 18:02 à 18:06 UTC, sur l'accord « Oui, lance la sonde ». Code 0. Journal : [`s3-sonde.log`](resultats/s3-sonde.log).

**Sous runc**, 1, 8, 64 et 512 Mio passent par l'entrée standard de `kubectl exec` ; 512 Mio en 3,6 s.

**Sous Kata**, 1 à 64 Mio passent (64 Mio en 7,2 s). À 512 Mio, le pod reçoit tout le fichier, mais `kubectl exec` ne rend pas la main avant le délai de 120 s, en WebSocket comme en SPDY. La cause n'est pas diagnostiquée. Détails : [prédictions de S3](resultats/s3-predictions.md).

**Builds de S3** : toujours non lancés. La voie de transfert est à décider.

## Additif du 10/11/2026, 18:24 UTC : S3 tenu

Builds lancés de 18:11:00 à 18:23:23 UTC, sur l'accord « Oui, lance builds », copie par morceaux de 64 Mio. Code 0. Comparaison sur l'hôte : code 0, aucun écart. Détail : [prédictions et résultats](resultats/s3-predictions.md).

**Deux builds par sbuild, en pods Kata privilégiés sans accès à l'instantané, depuis la fermeture de S2 restaurée par digest : même deb, `0b489d43…`, octet pour octet.** C'est aussi celui d'OBS et de s1b.
- Les 48 paquets installés viennent tous de la fermeture. Aucune requête http, et les sources de l'instantané sont neutralisées dans le chroot.
- Le test TCP vers l'instantané échoue (code 124) dans les deux pods.
- Installed-Build-Depends est identique à celui de s1b. Seul `Build-Date` diffère entre les `.buildinfo`.
- sbuild tourne en 272 et 274 s.

**Limites** : même chemin de build (`/build/reproducible-path`), même nœud. La coupure du réseau par sbuild est laissée à S5.

**Reste** : S4 (Tekton, Chains, deb dans Zot) et S5. L'incident de copie vers un pod Kata est à diagnostiquer, à la demande du propriétaire.

## Additif du 10/11/2026, 18:48 UTC : diagnostic du blocage de `kubectl exec` sous Kata, et correction de lecture

**Correction de lecture** : « le blocage est propre à Kata » n'est pas établi. La comparaison runc/Kata change deux choses à la fois, le runtime et la vitesse de lecture du pod (environ 150 Mo/s sous runc, 10 Mo/s sous Kata). Sous Kata, kubectl a tout envoyé bien avant que le pod ait tout lu, et des centaines de Mo restent en attente dans la chaîne. Ce cas n'a jamais été mesuré sous runc. De même, « la quantité compte, pas la durée » est trop fort : l'envoi lent ne portait que sur 32 Mio, sous les 64 Mio qui passent. **La règle d'exploitation reste vraie** : sous Kata, un gros fichier ne passe pas par l'entrée standard de `kubectl exec`.

Diagnostic ([prédictions et résultats](resultats/diag-exec-predictions.md)) :
- **seuil** : entre 64 et 128 Mio par exec sous Kata ;
- **processus** : au bout de 60 s, le processus de l'exec est fini dans le pod ;
- **shim** : son journal sur sc-build montre qu'il a tout fait en 13 s. Il a transmis les 128 Mio, vu la fin du processus en code 0 et émis `TaskExit` ; containerd note « stdin closed » à la même seconde.

**Le blocage est en aval du shim**, dans la remontée de la fin de l'exec vers kubectl : containerd, kubelet ou apiserver. La cause n'est pas connue. Deux tests croisés sont préparés à sec : runc avec une lecture lente dans le pod, et Kata avec un envoi lent.

Script : [`diag-exec-kata.sh`](diag-exec-kata.sh). Étapes `pod`, `releve` et `noeud` lancées sur accord, code 0 ; étape `croise` NON LANCÉE.

## Additif du 10/11/2026, 18:59 UTC : étape croise du diagnostic, Kata hors de cause

Étape `croise` (18:54:38 à 18:58:13 UTC, code 0) :
- **(a) runc, lecture lente dans le pod** : code 124 au délai de 150 s, alors que les 134 217 728 octets sont reçus et que le sha256 est conforme. **Le blocage se reproduit hors de Kata.**
- **(b) Kata, envoi lent** (environ 5 Mio/s) : **code 0 en 26,6 s**, tout reçu.

**Kata n'est pas la cause.** L'exec ne rend pas la main quand une grande quantité de données d'entrée attend dans la chaîne de flux (kubectl, apiserver, kubelet, containerd) parce que le pod la lit moins vite qu'elle n'arrive. Le processus finit, et la fin de l'exec ne remonte pas. Kata n'y joue que par son débit plus faible (environ 10 Mo/s), qui crée cette attente. Le maillon exact de la chaîne n'est pas identifié. Aucun ticket Kubernetes, containerd ou Kata trouvé ne décrit ce cas.

Détail : [diagnostic](resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 19:42 UTC : bisection sur le nœud

**Bisection sur le nœud** (19:41:09 à 19:41:38 UTC, code 0 ; pod runc, 128 Mio tirés de `/dev/urandom` sur sc-build) :
- **B1** : `crictl exec`, lecture lente, **code 0 en 13,3 s** ;
- **B2** : `crictl exec`, lecture rapide, code 0 en 0,4 s ;
- **B3** : `ctr task exec`, lecture lente, code 0 en 13,4 s.

Tous les octets sont reçus dans les trois cas. **containerd, son serveur de flux CRI et le shim ne sont pas en cause** : la même lecture lente, qui bloque par `kubectl exec`, passe par `crictl exec` (crictl 1.35.0, containerd 2.2.7-k3s1). **Le maillon fautif est en amont, dans kubelet, l'apiserver ou kubectl**, et leur relais du flux. Il n'est pas encore identifié.

Détail : [diagnostic](resultats/diag-exec-predictions.md).
