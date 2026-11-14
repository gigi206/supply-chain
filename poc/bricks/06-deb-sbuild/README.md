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

## Additif du 10/11/2026, 19:53 UTC : étape amont du diagnostic

**Étape amont** (19:47:37 à 19:52:40 UTC, code 0 ; pod runc, 128 Mio lus lentement dans le pod) :
- **C1** (kubectl de l'hôte, 1.35.10) : code 124 au délai de 150 s, tout reçu ;
- **C2** (kubectl de sc-confiance, 1.35.9+rke2r1, données tirées sur sc-confiance) : **code 124 au délai, tout reçu**.

**Le poste, son réseau vers les VM et sa version de kubectl sont hors de cause. Avec la bisection, le maillon est situé dans l'apiserver ou kubelet**, dans leur relais du flux d'exec, entre kubectl et le serveur de flux de containerd. Les journaux de kubelet et de kube-apiserver de la fenêtre ne disent rien de cet exec à leur verbosité actuelle. Kubelet n'a écrit qu'une ligne, sur la durée de démarrage du pod, sans rapport.

Détail : [diagnostic](resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 19:59 UTC : étape kubelet du diagnostic, refusée par kubelet

**Étape kubelet** (19:58:33 à 19:58:35 UTC, code 0 du script) : **kubelet refuse les deux exec directs, `HTTP/1.1 403 Forbidden`**, en 8 et 5 ms, avant tout transfert. K2, le témoin, échoue ; K1 ne dit donc rien. Le maillon reste situé dans l'apiserver ou kubelet, sans être tranché. Le motif du refus n'a pas été lu, car le client n'affichait que la ligne de statut. Hypothèse non vérifiée : une autorisation de kubelet différente pour un exec par WebSocket (GET), alors que l'apiserver l'atteint autrement.

Détail : [diagnostic](resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 20:08 UTC : piles de goroutines pendant le blocage

**Étape pile** (20:04:45 à 20:07:22 UTC, code 0 ; pod runc, 128 Mio lus lentement, exec en code 124, tout reçu) :
- **pile de kubelet disponible**, 224, 225 et 225 goroutines avant, pendant et après ;
- **pile de kube-apiserver indisponible** (`NotFound`) : son profilage est coupé. Le contrôle CIS 1.2.15 de la 08b en échec ne voulait donc pas dire profilage actif ;
- **pendant le blocage, kubelet n'a aucune goroutine de relais de flux en plus** : 11 avant, 11 pendant, 11 après, aux mêmes chaînes d'appels. Toutes piles confondues, la seule goroutine en plus est une tâche de statistiques de volumes (`volumeStatCalculator`), sans rapport.

**Lecture** : à 45 s, le processus est fini et kubelet ne relaie plus rien pour cet exec. Sa part semble achevée. Par élimination avec la bisection (containerd hors de cause) et l'étape amont (poste hors de cause), **le maillon probable est kube-apiserver**, qui garde l'exec ouvert vers kubectl. **Ce n'est pas prouvé** : la pile de l'apiserver manque, et les goroutines de kubelet pendant le transfert lui-même (avant 15 s) n'ont pas été relevées.

Détail : [diagnostic](resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 20:13 UTC : connexions pendant le blocage, tunnel de RKE2 suspecté

**Étape connexions** (20:09:24 à 20:12:01 UTC, code 0 ; pod runc, 128 Mio lus lentement, exec en code 124) :
- **aucune connexion directe entre kube-apiserver et kubelet** (sc-confiance vers sc-build:10250) : 0 avant, 0 pendant, 0 après ;
- connexions reçues sur 6443 : 44 avant, **46 pendant**, 44 après ;
- **sur l'hôte, le kubectl de l'exec garde 2 connexions établies pendant le blocage**.

**Lecture** : l'apiserver ne joint pas kubelet en direct. Sous RKE2, il passe vraisemblablement par le **tunnel de l'agent** : le sélecteur de sortie (« egress selector »), relayé par `remotedialer` entre rke2-server (port 9345 du superviseur) et rke2-agent. **Ce n'est pas vérifié** : ni la configuration du sélecteur, ni les journaux de rke2-server et rke2-agent n'ont été lus. Ce tunnel est un maillon de plus, propre à RKE2 et k3s, entre l'apiserver et kubelet. Il est **le nouveau suspect** : la pile de kubelet est vide de relais, et le relais de l'apiserver n'est pas observable.

Détail : [diagnostic](resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 20:27 UTC : tunnel du superviseur RKE2

**Étape tunnel** (20:24:26 à 20:27:04 UTC, code 0 ; pod runc, 128 Mio lus lentement, exec en code 124, tout reçu) :
- **sélecteur de sortie de kube-apiserver** (`/var/lib/rancher/rke2/server/etc/egress-selector-config.yaml`) : la sélection `cluster` passe par un proxy **HTTP CONNECT vers `https://127.0.0.1:9345`**, le superviseur de RKE2. Le fichier ne contient que des chemins de certificats, aucune valeur ;
- **2 connexions établies de sc-build vers 9345**, les mêmes avant, pendant et après le blocage : c'est le tunnel durable de l'agent ;
- **journaux de rke2-server et rke2-agent muets** dans la fenêtre, pour les mots cherchés.

**Lecture** : la chaîne d'un `kubectl exec` vers un pod de sc-build est kubectl, puis kube-apiserver, puis le proxy CONNECT du superviseur (rke2-server), puis le tunnel `remotedialer` jusqu'à rke2-agent, puis kubelet, puis containerd. Containerd est mis hors de cause par la bisection. Kubelet ne relaie plus rien pendant le blocage, d'après sa pile. Le poste est hors de cause par l'étape amont. **Le maillon fautif est donc kube-apiserver ou le tunnel du superviseur RKE2.** Le tunnel, propre à RKE2 et k3s, est le suspect principal, **sans preuve directe** : ni lui ni l'apiserver ne sont observables à la verbosité actuelle.

Détail : [diagnostic](resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 20:31 UTC : étape local refusée à l'admission

Un pod d'essai sur sc-confiance devait retirer le tunnel `remotedialer` de la chaîne. Le code de k3s inclus dans RKE2 1.35.9 joint en direct le kubelet du nœud du superviseur. L'admission à blanc (20:31 UTC, « Oui ») a été refusée par la règle `espace-default-interdit` : rien n'a été lancé. Il faudrait un espace de la zone confiance ou un espace dédié, ce qui relève d'une décision du propriétaire. Détail : [diagnostic](resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 20:35 UTC : cause du blocage de `kubectl exec` trouvée, le tunnel de RKE2

**Conclusion du diagnostic.** Un `kubectl exec` dont l'entrée attend dans la chaîne, parce que le pod lit moins vite qu'elle n'arrive, ne rend pas la main sur sc-build, bien que le processus ait fini et que tout soit reçu. Le même exec vers un pod de sc-confiance passe en 13,4 s (étape local, 20:34 UTC). Pour ce pod, d'après le code de k3s inclus dans RKE2 v1.35.9+rke2r1, le superviseur joint kubelet en direct, sans la session `remotedialer`. Kubectl, kube-apiserver et le relais `proxy.Proxy` du superviseur sont communs aux deux cas. Containerd et le shim sont hors de cause (bisection), kubelet ne relaie plus rien pendant le blocage (pile), et le poste est hors de cause (étape amont). **Le maillon fautif est le tunnel `remotedialer` entre rke2-server et rke2-agent** (remotedialer `v0.6.0-rc.1.0.20250916111157-f160aa32568d`, d'après le `go.mod` de RKE2). Kata n'y joue que par son débit plus faible, qui crée l'attente. **Limites** : c'est une preuve par différence, sur un essai par chemin. Le mécanisme exact dans `remotedialer` n'est pas identifié. Les deux nœuds diffèrent aussi par d'autres points que le tunnel, sans rôle connu dans un exec.

Détail : [diagnostic](resultats/diag-exec-predictions.md).

## Additif du 10/11/2026, 20:38 UTC : précisions à la cause

**Précisions à la conclusion (20:38 UTC)**
- **Le suspect est le chemin par la session `remotedialer`, pas `remotedialer` seul.** `proxy.Proxy` est commun aux deux cas, mais il relaie une connexion TCP locale vers sc-confiance et une connexion `remotedialer` vers sc-build. Sa façon de traiter la fin et la fermeture d'une connexion `remotedialer` reste aussi suspecte que `remotedialer`. Les deux fichiers en cause (`tunnel.go`, `proxy.go`) sont dans k3s.
- **Le contournement du tunnel sur sc-confiance est déduit du code, non observé.** Il repose sur l'égalité entre le nom du nœud et `ServerNodeName`. Pour le confirmer, il faudrait relever par `ss`, sur sc-confiance pendant l'exec, une connexion locale vers :10250. C'est proposé, non lancé.
- **Versions** : le `go.mod` de RKE2 `v1.35.9+rke2r1` ne remplace ni k3s ni remotedialer (aucune directive `replace` pour eux). Elles valent pour le code relu, à condition que le binaire déployé soit bien ce tag, comme l'a mesuré la 08b.
- **En amont, lu sans action publique**, sans lien établi avec ce cas :
  - k3s `b3b26bce` (15/10/2026), « Fix goroutine leak in the proxy » : postérieur au commit embarqué ; il corrige une goroutine restée bloquée sur un canal non tamponné de `proxy.Proxy`, pas la fermeture qui nous bloque, à première lecture ;
  - remotedialer : versions `v0.6.1` (16/04/2026) et `v0.6.2` (06/11/2026), postérieures à celle embarquée, sans commit lu qui traite ce cas.

## Additif du 10/11/2026, 20:47 UTC : blocage de `kubectl exec` disparu après le retrait du tunnel (08b)

**Vérification après `egress-selector-mode: disabled`** (20:45:02 à 20:47:14 UTC, code 0) :
- **`croise` (a), runc avec lecture lente de 128 Mio vers sc-build : code 0 en 13,3 s, sha256 conforme.** Avant le changement, cet exec bloquait à chaque essai : 6 sur 6 (croise, amont C1 et C2, pile, connexions, tunnel). **Le blocage a disparu**, sur un essai ;
- `croise` (b), Kata avec envoi lent : code 0 en 26,6 s, comme avant ;
- `connexions` : l'exec finit en code 0. **E5 n'est pas mesurée** : le relevé « pendant » tombe à 45 s, alors que l'exec s'est terminé vers 13 s. Aucune connexion de sc-confiance vers sc-build:10250 n'est vue aux trois relevés, ce qui ne prouve rien sur le chemin pendant l'exec.

Cela confirme, par l'effet, que le maillon fautif était sur le chemin par le proxy du superviseur et le tunnel de l'agent RKE2. **Non vérifié** : le chemin direct pendant l'exec (E5, relevé trop tardif), un gros exec sous Kata (512 Mio), et les pipelines Tekton après ce changement. Le découpage en morceaux de 64 Mio de `s3.sh` reste valable, mais n'est plus forcément nécessaire.

## Additif du 10/11/2026, 21:01 UTC : chemin direct observé, Kata à 512 Mio passe

**Vérification complémentaire** (10/11/2026, 20:56:42 à 21:00:36 UTC, accord : « 3, les deux », code 0 à chaque commande) :
- **chemin direct observé (E5)** : pendant chacun des trois exec à lecture lente de 128 Mio vers sc-build, une connexion de sc-confiance vers sc-build:10250, vue des deux côtés, et une seule. Elle est vue à chaque relevé pendant l'exec, à l'incertitude d'horloge près (0,3 s) ; les relevés des 3 s d'avant et des 24 s d'après sont à 0 ;
- **exec à lecture lente vers sc-build : 3 sur 3** en code 0, 13,3 s chacun, sha256 conforme ;
- **Kata, 512 Mio à plein débit (sonde de S3 rejouée telle quelle) : code 0 en 54,8 s, sha256 conforme.** À 18:02 UTC, la même copie ne rendait pas la main en 120 s. runc : 512 Mio en 3,3 s.

Le blocage de S3 venait donc du chemin par le tunnel de l'agent RKE2, pas de Kata, sur un passage à 512 Mio. **Non vérifié** : les pipelines Tekton après ce changement. Le découpage en morceaux de 64 Mio reste dans `s3.sh` ; le retirer serait un changement à part.

Détail et prédictions D1 à D6 : [`egress-selector-predictions.md`](../08b-rke2/resultats/egress-selector-predictions.md).

## Additif du 10/11/2026, 21:19 UTC : carte des dépendances de S4, préparée à sec, rien lancé

**Push consigné** : `58fd6c1..57b76be`, de 21:14:41 à 21:14:42 UTC. Il contient 3 commits (`b08d5f7`, `28b812e`, `57b76be`). Avant l'envoi, 6 fichiers ont été contrôlés dans un worktree temporaire, sans aucun secret trouvé. Accord : « Oui, pousse ».

**Interprétation** : je consigne le « continue » de 21:15:41 UTC comme une permission de préparer à sec, pas comme un accord. Ce tour n'a rien écrit dans Zot, ni dans le cluster, ni sur les VM.

**Effort de la brique**
- Commits sur `poc/bricks/06-deb-sbuild` : 2 le 05/11, puis 54 le 10/11, de 12:14:44 à 21:02:39 UTC.
- Ce total comprend le diagnostic de l'exec sous Kata, de 18:27 à 21:00 UTC, qui a débordé sur la 08b.
- L'estimation est de 2 pw, avec une décision à 4 pw. Le travail fait reste loin des deux seuils : aucune décision n'est requise.

**Carte des dépendances de S4.** Chaque point est marqué « vérifié dans le dépôt » ou « à vérifier ».

1. **Sortie réseau de `prefetch-deb`** : vérifié dans le dépôt. Elle est appliquée depuis E1 (14:29:39 UTC), et E3 est tenue ([08c](../08c-durcissement/resultats/sortie-deb-predictions.md)). Correction de lecture : la phrase « non appliquée » de l'additif sur la sortie dédiée date d'avant E1. Elle n'est plus vraie, et elle n'est pas réécrite.
2. **Correction `TimeoutExpired` de `sortie-builds.sh`** (14:35 UTC, non rejouée) : vérifié dans le dépôt. Elle ne touche que `DESTINATIONS`, et seule l'étape des témoins s'en sert. Elle ne bloque pas S4.
3. **ORAS** : vérifié dans le dépôt. Il est classé « Sain » au doc 04, `oras` 1.3.6 est épinglé dans `mise.toml`, et S2 s'en est déjà servi depuis l'hôte.
4. **Sujet signé par Chains (v0.29.9)**
   - Vérifié dans le dépôt : il existe un précédent. `publier-fermeture` émet `IMAGE_URL` et `IMAGE_DIGEST`, et Chains signe l'artefact ORAS.
   - Conséquence : par cette voie, le sujet signé est le digest du manifeste OCI qui porte le deb, pas le sha256 du fichier `.deb`. Le lien entre les deux passe par la couche du manifeste.
   - À vérifier dans le code de Chains v0.29.9, pas de mémoire : un résultat `*_ARTIFACT_OUTPUTS` permettrait-il un sujet au sha256 du deb ?
5. **Fermeture dans `resolvedDependencies`**
   - Vérifié dans le dépôt : `preparer-entrees` déclare `FERMETURE_ARTIFACT_INPUTS` (uri et digest). La même forme convient pour `deps/sample-app/deb-buildinfo@sha256:3a0e54ae…`.
   - À vérifier : sa présence dans la provenance de la PipelineRun pour ce cas.
6. **Dépôt de sortie dans Zot** : vérifié dans `stockage/zot.json`.
   - `artifacts/sample-app/deb`, prévu au tableau de S4, tombe sous `**`, où seul `poc-ecriture` écrit.
   - Une tâche de publication demande donc soit un dépôt sous `builds/**`, avec un compte qui a déjà la création seule, soit une règle et un compte nouveaux.
   - La seconde voie est un changement de Zot : elle demande un accord nommé.
7. **Chroot et image de build**
   - Vérifié dans le dépôt : en S3, le chroot de S2 (`e0b1f37c…`) passe de l'hôte au pod par `kubectl exec`. Il n'est pas dans Zot.
   - L'image est une image d'essai (`essais-06/sbuild-debian13:s1b`), pas encore sous `builders/`.
   - Dans une pipeline, les deux doivent venir de Zot par digest, ce qui veut dire écrire dans Zot, donc un accord nommé.
   - L'image de base garde son verdict D4 : « À surveiller », avec une échéance au 09/12/2026.
8. **Politique** : vérifié dans le dépôt.
   - Chaque nouvelle tâche est un fichier signé dans `politique/taches/`, et son digest s'ajoute à `porte/taches.yml`, relu par le propriétaire.
   - Le motif de `verification-policy.yaml` couvre déjà `tekton/(tasks|pipelines)/…`.
   - Les cas de `posture/`, le gabarit et les déclencheurs sont à revoir.
   - Signer et publier des bundles, c'est écrire dans Zot : il faut un accord nommé, et `taches.key` n'est jamais lue.
9. **Porte** : à vérifier. `porte.rego` ne juge peut-être pas une pipeline dont le sujet n'est pas une image.

**Reste** : S4 et S5. Leur ordre face aux autres points ouverts est une question posée au propriétaire. Rien n'est écrit pour S4, ni tâche, ni script, ni prédiction.

## Complément du 10/11/2026, 21:20 UTC : deux dépendances de S4 absentes de la carte, et un point resserré

Relevé dans le dépôt, à sec. Rien n'est lancé.

- **Point 2 resserré** : vérifié. `DESTINATIONS` ne sert que dans la fonction `temoins()` de `sortie-builds.sh`.
- **10. Admission d'un pod Kata privilégié lancé par Tekton** : vérifié dans `politique/admission.yaml`.
  - Le test 4 n'autorise un conteneur privilégié que si `runtimeClassName == 'kata'`, quel que soit le nom de la tâche. Une tâche sbuild sous Kata passerait donc sans changer cette politique.
  - En revanche, `construction-sans-sortie.yaml`, qui interdit toute sortie, ne sélectionne que `tekton.dev/task: construire-image`.
  - Une tâche de construction deb sous un autre nom tomberait sous `builds-sans-internet` (aucune adresse publique, mais Zot et Forgejo restent joignables, d'après les témoins de la 08c). Pour avoir la même coupure que la voie image, il faut la renommer ou ajouter une politique de Cilium : c'est un changement du cluster, qui demande un accord nommé.
- **11. Provenance de la fermeture** : vérifié dans `porte/porte.rego`, règle `fermeture_plateforme`.
  - Depuis la décision D6 de la 03 (03/11/2026), la porte exige que la fermeture d'une construction vienne de la pipeline de prefetch de la plateforme.
  - Les tâches doivent être exactement `prefetch-gomod` et `publier-fermeture`, et le sujet doit être sous `builds/fermetures/`.
  - La règle ne s'applique qu'aux provenances qui contiennent `preparer-entrees` ou `construire-image`.
  - Conséquences :
    - (a) la fermeture deb de S2, poussée depuis l'hôte sous `deps/`, n'a aucune provenance, et la porte la refuserait ;
    - (b) une pipeline deb qui réutilise `preparer-entrees` serait refusée, parce que la règle attend `prefetch-gomod` ;
    - (c) une pipeline deb sous d'autres noms de tâches échapperait à la règle sans rien refuser (succès à vide) : c'est un trou, pas une acceptation.
  - S4 comprend donc vraisemblablement une pipeline `prefetch-deb`. La tâche doit garder exactement ce nom, que sélectionne `prefetch-deb-sortie`. Il faut aussi étendre `porte.rego` à la voie deb, avec ses cas de test dans `porte_test.rego`.
- **Renvoi** : le push `58fd6c1..57b76be` portait sur la 08b et la 06 ; il est consigné dans l'additif précédent de ce README.

## Additif du 10/11/2026, 21:23 UTC : décision d'ordre ; deux points « à vérifier » de la carte tranchés par lecture, à sec

**Décision du propriétaire** (21:22:16 UTC) : « S4 et S5 d'abord ». S4 et S5 passent avant les autres points ouverts. Cette réponse fixe l'ordre seulement : elle ne vaut accord pour aucune mesure ni aucune écriture dans Zot.

**Point 4, sujet signé par Chains**
- Lu dans le code de Chains v0.29.9 : sources locales au tag `v0.29.9`, commit `89219ea5`.
- Ce qui est lu :
  - Un résultat `*_ARTIFACT_OUTPUTS` (objet `uri`, `digest`, `isBuildArtifact: "true"`) devient un sujet (`extract.go`). Il entre aussi dans les cibles OCI à signer, dès que `uri` et `digest` ne sont pas vides (`signable.go`, `hasImageRequirements`).
  - Avec `storage: oci` et l'encodage `dsse` du PoC, l'attestation est écrite pour chaque sujet dans le dépôt OCI nommé par `uri`, sous la référence `uri@sha256:<digest>` (`legacy.go`).
  - Quand aucun manifeste n'a ce digest, le stockeur se replie sur `SignedUnknown` (`attestation.go`).
  - Un `uri` préfixé `oci://` ne passerait pas `name.NewDigest`. Le préfixe est accepté pour les entrées, mais pas pour les sorties.
- Conséquences, déduites du code et non mesurées :
  - Un sujet au sha256 du `.deb` est possible : son attestation serait accrochée à un digest qu'aucun manifeste ne porte.
  - La porte lit l'image par son digest (`input.image`, règle `image_signature`), et elle ne trouverait rien à ce digest.
  - Le sujet « manifeste OCI qui porte le deb » est celui du précédent `publier-fermeture`. C'est le seul cohérent avec la porte actuelle. Le sha256 du `.deb` reste lisible dans le descripteur de la couche, et dans le `.buildinfo` joint.

**Point 5, fermeture dans `resolvedDependencies`**
- Mesuré pour la voie image : F3 de la 03 ([f3-predictions.md](../03-deps-closure/resultats/f3-predictions.md)), avec `builds/fermetures/sample-app@74c265e7` dans `resolvedDependencies`.
- Lu dans le code : tout résultat dont le nom finit par `ARTIFACT_INPUTS` devient une dépendance (`RetrieveMaterialsFromStructuredResults`). Le mécanisme ne dépend donc pas du type de paquet.
- Non mesuré pour le deb.

**Encore à vérifier** : le point 9 (porte pour un sujet non image) devient « à étendre » d'après le point 11. Rien d'autre n'est ouvert dans la carte.

**Rien d'écrit pour S4** : aucune tâche, aucun script, aucune prédiction. Trois choix de conception attendent le propriétaire : le sujet, le dépôt de sortie et la pipeline `prefetch-deb`.

## Note datée du 10/11/2026, 21:25 UTC : deux corrections à l'additif de 21:23 UTC, et la liste complète des choix

**Correction 1 : origine du refus de `oci://`.** L'additif de 21:23 UTC range parmi les lectures de Chains le refus d'un `uri` préfixé `oci://`. Ce refus n'est pas dans Chains : il vient de l'analyse des noms de go-containerregistry. Je l'ai vérifié depuis dans le code vendu par Chains v0.29.9 (`go-containerregistry` v0.21.9, `pkg/name`).
- `NewDigest` passe par `NewTag` ou par `NewRepository`.
- Dans `oci://sc-stockage.poc.test:5000/…`, la première partie (`oci:`) est prise pour le registre. Le reste contient `:`, qui n'est pas dans `repositoryChars`.
- Ce refus a donc été lu dans le code, mais pas exécuté.

**Correction 2 : il reste plus de choix ouverts que je ne l'ai écrit.** « Rien d'autre n'est ouvert » et « trois choix » étaient trop courts. Choix du propriétaire avant d'écrire S4 :
1. **Forme de la pipeline.** Soit une pipeline deb à part, sous le même gabarit et le même webhook ; soit des tâches ajoutées à `sample-app`. Ce choix décide de ce qu'il faut changer dans le gabarit, dans les déclencheurs et dans la porte. La porte juge par PipelineRun, et D6 exige que la construction et la fermeture viennent du même dépôt Forgejo.
2. **Sujet signé.** Le manifeste OCI est cohérent avec la porte, mais il ne couvre le `.deb` que par le digest de couche qu'il porte. Le critère de S4 dit « Sujet deb signé » : c'est au propriétaire de dire si ce lien indirect le satisfait.
3. **Dépôt de sortie dans Zot.** Soit `builds/**` avec un compte qui existe déjà et n'a que le droit de créer, soit une règle et un compte nouveaux.
4. **Pipeline `prefetch-deb`.** Elle découle de D6 et demande d'étendre `porte.rego`.
5. **Coupure réseau de la construction deb.** Soit la tâche reprend la politique `construction-sans-sortie`, en la renommant ; soit une nouvelle politique de Cilium la couvre. Les deux voies changent le cluster.
6. **Image de build sous `builders/`.** Il faut décider qui la construit et la pousse dans Zot : l'hôte, ou une pipeline. Dans les deux cas, c'est une écriture dans Zot. L'échéance D4 tombe le 09/12/2026.

**S5** : la liste des tests existe (M5 de la 05) : fermeture altérée, sortie réseau pendant le build, pod privilégié hors Kata, rejeu de zéro. S5 n'appelle donc aucun choix de plus.

## Additif du 10/11/2026, 21:33 UTC : décision sur la forme de la pipeline, et ce qu'elle touche (lu dans le dépôt, à sec)

**Décision du propriétaire** (21:32:22 UTC) : « Pipeline deb à part ». Elle tranche le choix 1 de la note de 21:25 UTC. Ce n'est un accord pour aucune mesure ni aucune écriture.

**Correction de la formulation du choix 1** : « sous le même gabarit » ne tient pas. Le rattrapage (`politique/rattrapage/main.go`, ligne 198) refuse tout gabarit qui contient autre chose qu'un seul PipelineRun. Une pipeline deb à part demande donc **son propre gabarit**, derrière le même webhook.

**Pièces touchées**, chacune vérifiée dans le dépôt sauf mention contraire :
- **Gabarit** : une TriggerTemplate `sample-app-deb` dans `declencheurs`, sur le modèle de `gabarit-sample-app.yaml`. Paramètres `commit` et `depot` seulement. Un PipelineRun `sample-app-deb-<commit>` dans `builds`, dont le nom fournit l'anti-rejeu. Construction sur `zone: build`, sous Kata.
- **EventListener** : un second trigger à côté de `sample-app-push` (`tekton/webhook.yaml`). Mêmes intercepteurs, même filtre, même dépôt Forgejo, qu'exige D6. Il faut vérifier, au moment de l'écrire, si les droits de `el-forgejo` couvrent déjà un second gabarit.
- **Rattrapage** : il est paramétré par `GABARIT` (ligne 135). Il faut un second CronJob, avec `GABARIT=declencheurs/sample-app-deb`, sans changer le code.
- **Pipeline** : une Pipeline `sample-app-deb` signée et publiée en bundle, avec ses tâches signées : préparer, construire sous sbuild, publier. Plus la pipeline `prefetch-deb` (choix 4). Chaque digest s'ajoute à `porte/taches.yml`.
- **Porte**
  - `porte-job.yaml` juge une référence d'image (`ec validate image --image @IMAGE@`).
  - **À vérifier** : `ec` accepte-t-il comme « image » un artefact ORAS, c'est-à-dire un manifeste qui n'est pas une image ? Il n'est pas établi que la fermeture de la voie image ait jamais été jugée ainsi. Le vérifier demande un Job dans `porte`, donc un accord nommé.
  - `porte.rego` est à étendre à la voie deb (point 11).

**Choix encore ouverts** (numérotation de la note de 21:25 UTC) : 2 (sujet signé et critère), 3 (dépôt de sortie), 4 (`prefetch-deb`), 5 (coupure réseau), 6 (image sous `builders/`). Le push des commits de la 06 attend aussi un oui.

## Additif du 10/11/2026, 21:33 UTC : décision sur le sujet signé

**Décision du propriétaire** (21:33:33 UTC) : « Manifeste OCI ». Elle tranche le choix 2 de la note de 21:25 UTC. Ce n'est un accord pour aucune mesure ni aucune écriture.

**Ce que la décision fixe**
- Le sujet de la provenance de `sample-app-deb` est le manifeste OCI qui porte le `.deb`, publié par ORAS, comme dans le précédent `publier-fermeture`.
- La tâche de publication émet `IMAGE_URL` (un dépôt sans préfixe `oci://`) et `IMAGE_DIGEST`.
- Le `.deb` est couvert par le digest de sa couche dans ce manifeste. Le `.buildinfo` est joint au même manifeste, comme le demande S4.

**Lecture du critère** : le critère « Sujet deb signé » est rempli par ce lien indirect. C'est mon interprétation de la réponse : la réponse ne le dit pas en toutes lettres. Les prédictions de S4 vérifieront le lien : sha256 du `.deb` égal au digest de la couche, et manifeste égal au sujet.

**Choix encore ouverts** : 3 (dépôt de sortie), 4 (`prefetch-deb`), 5 (coupure réseau), 6 (image sous `builders/`). Le push des commits de la 06 attend aussi un oui.

## Additif du 10/11/2026, 21:35 UTC : décision sur le dépôt de sortie, et ce qu'elle permet (lu dans le dépôt, à sec)

**Décision du propriétaire** (21:34:43 UTC) : « builds/**, compte existant ». Elle tranche le choix 3 de la note de 21:25 UTC. Ce n'est un accord pour aucune mesure ni aucune écriture, et Zot ne change pas.

**Compte** : `poc-images`, vérifié dans `stockage/zot.json` et `publier-image.yaml`.
- Son secret est `zot-images`, dans `builds`.
- Il crée par digest sous `builds/**`, mais ne pose ni tag, ni mise à jour, ni suppression.
- `builds/fermetures/**` et `builds/scan/**` ont leurs propres règles.

**Dépôt proposé** : `builds/sample-app-deb`, à côté de l'image `builds/sample-app`. C'est une proposition, pas une décision.

**Réutiliser `publier-image` telle quelle**
- Possible d'après son script, lu, non mesuré.
  - La tâche extrait `image.tar`, un layout OCI, du workspace `sortie`. Elle compare le digest de l'index au paramètre `digest`.
  - Elle pousse par `oras cp --from-oci-layout`, puis relit le manifeste en lecture anonyme. Elle émet `IMAGE_URL` et `IMAGE_DIGEST`.
  - Rien dans ce script ne suppose que le manifeste soit une image.
- Ce que ça éviterait : aucune nouvelle tâche de publication, et le secret `zot-images` reste monté par une seule tâche signée, qui garde son digest approuvé `d21931f3`.
- Condition : la construction deb doit livrer un `image.tar` contenant le manifeste ORAS (`.deb` et `.buildinfo`), avec son digest. Reste à décider où tourne `oras push --oci-layout` : dans l'image de build, ou dans une petite tâche runc entre la construction et la publication.

**Choix encore ouverts** : 4 (`prefetch-deb`), 5 (coupure réseau), 6 (image sous `builders/`). Le push des commits de la 06 attend aussi un oui.

## Additif du 10/11/2026, 21:36 UTC : décision sur `prefetch-deb`, ce qu'elle permet et ce qu'elle laisse ouvert (lu dans le dépôt, à sec)

**Décision du propriétaire** (21:36:13 UTC) : « Oui, selon D6 ». Elle tranche le choix 4 de la note de 21:25 UTC : une pipeline `prefetch-deb` dans la plateforme, avec la porte étendue à la voie deb. Ce n'est un accord pour aucune mesure ni aucune écriture.

**Réutiliser `publier-fermeture` telle quelle** : c'est possible d'après son script, lu, non mesuré.
- Elle publie chaque fichier de `sortie/fermeture/`, sauf `bom.json`, un fichier par couche, triés, avec une date fixe. Elle pousse dans `builds/fermetures/**` avec le compte `poc-fermetures`, par digest seulement.
- Rien dans le script n'est propre à Go. Son digest approuvé reste `7fa92ad3`.
- La règle `fermeture_plateforme` attend déjà `publier-fermeture` ; seul `prefetch-gomod` est à généraliser en « `prefetch-gomod` ou `prefetch-deb` ».
- Le type d'artefact est le même que pour Go (`deps-closure.v1`). Il ne permet donc pas de distinguer une fermeture deb d'une fermeture Go : la porte devra les distinguer par la tâche de prefetch.
- **Non établi** : que le digest obtenu égale celui de S2 (`3a0e54ae…`, poussé par `closure.sh`). La convention est la même, mais la comparaison n'a pas été faite.

**La tâche `prefetch-deb` est à écrire.**
- Son nom est fixé par `prefetch-deb-sortie`, qui sélectionne `tekton.dev/task=prefetch-deb`.
- En S2, la chaîne était : InRelease de l'instantané vérifié par `gpgv`, puis Packages contrôlé par InRelease, puis liste attendue tirée du `.buildinfo`, puis `apt-get download` dans un pod, puis `.deb` contrôlés contre Packages.
- **Question ouverte, la source de la liste.** En S2, le `.buildinfo` venait du journal du build en réseau de s1b. Dans la plateforme, `prefetch-gomod` lit un fichier de verrouillage du dépôt (`go.sum`). Pour le deb, il faut choisir :
  - (a) un `.buildinfo`, ou une liste équivalente, versionné dans `sample-app` comme fichier de verrouillage ;
  - (b) une résolution des `Build-Depends` sur l'instantané, dans la tâche elle-même.
  - (a) suit le modèle de Go et de S2 ; (b) déplace la résolution dans la plateforme.
- **Question ouverte, le runtime de la tâche.** `prefetch-gomod` tourne sous runc, en `restricted`. En S1 et S2, le pod `prefetch-deb` était Kata et privilégié, parce qu'il construisait aussi la racine par `mmdebstrap`. Il reste à mesurer si `apt-get download` seul passe en `restricted`, sans root.

**Choix encore ouverts** : la source de la liste (nouveau, ci-dessus), 5 (coupure réseau), 6 (image sous `builders/`). Le push des commits de la 06 attend aussi un oui.

## Additif du 10/11/2026, 21:41 UTC : source de la liste, et origine du packaging (lu dans le dépôt, à sec)

**Réponse du propriétaire** (21:40:33 UTC) : « ok ».
- Elle suivait l'avis du conseiller que je venais de relayer, et ma phrase : « Si tu suis cet avis, réponds […] par « Verrou dans sample-app » ».
- **Interprétation consignée** : le « ok » est lu comme le choix d'un verrou versionné. Ce n'est pas un accord de mesure.
- Format proposé, pas encore décidé : les `Installed-Build-Depends` et la date de l'instantané, avec éventuellement le sha256 de chaque paquet. Le `.buildinfo` brut est exclu : son champ `Checksums-Sha256` décrit le deb de s1b.
- **Limite** : mettre le verrou à jour demande un build en réseau hors de la plateforme, comme `go.sum`.

**Origine du packaging.** Ce point était absent de la carte. Vérifié dans le dépôt, sauf mention contraire :
- `debian/` vit dans ce dépôt, sous `poc/packaging/debian`, **pas dans `poc/sample-app`**.
- Le `.dsc` de S1 à S3 est produit sur l'hôte par `poc/packaging/sources.sh` (`mise run packaging:sources`). L'archive contient les sources de `poc/sample-app` (git archive), les modules Go vendus, vérifiés par `go.sum`, et `web/node_modules/marked`, vérifié par l'intégrité du lockfile. Le script en sort le paquet source.
- `debian/rules` construit hors ligne (`GOFLAGS=-mod=vendor`) et refait `web/dist` lui-même, au lieu de le prendre par digest comme la voie image.
- L'arbre de `workspace/sample-app` dans Forgejo était égal à `poc/sample-app` au commit de J2 (`construction.sh`, ligne 65), donc sans `debian/`. **À vérifier** : son contenu au commit de tête actuel, par une lecture de Forgejo.

**Conséquences pour S4**
- Une pipeline déclenchée par le webhook construit depuis le commit poussé. Le packaging (`debian/`) et le verrou doivent donc entrer dans `workspace/sample-app`, à moins d'une autre voie.
- Ce serait une écriture dans Forgejo. Un commit sur `main` relance aussi la pipeline image, qui écrit des enveloppes définitives dans Zot : il faut un accord nommé.
- **Seconde fermeture.** Le build deb a besoin des modules Go et de `marked`. Dans la plateforme, les modules Go viennent de la fermeture `prefetch-gomod` (D6). La pipeline deb dépendrait donc de **deux** fermetures, gomod et deb, et la règle `fermeture_plateforme` devrait admettre les deux. Pour `marked`, la source dans la plateforme reste à établir : la voie image prend `web/dist` par digest.

## Additif du 10/11/2026, 22:14 UTC : quatre décisions groupées, deux conflits, découpage de S4 en jalons (à sec)

**Décisions du propriétaire** (22:12:03 UTC, heure du résultat de la question groupée, tirée du jsonl). Aucune ne vaut accord de mesure.
1. **Packaging hors du dépôt** : `debian/` est fixé par digest dans la pipeline signée, comme `web/dist` pour la voie image. `sample-app` reste inchangé. Ce n'était pas ma recommandation.
2. **Modules Go tirés de la fermeture `prefetch-gomod`** (D6) : la porte doit admettre deux fermetures, gomod et deb.
3. **Coupure réseau** : une politique Cilium dédiée à la construction deb. `construction-sans-sortie` reste intacte.
4. **`builders/` construit par une pipeline de la plateforme** (image sbuild et chroot), et non poussé par l'hôte. Ce n'était pas ma recommandation. Le texte de l'option disait : « chantier à part, hors de S4 ».

**Conflit 1 : l'emplacement du verrou.**
- L'additif de 21:41 UTC lit le « ok » comme un verrou dans `sample-app`.
- La décision 1 laisse `sample-app` inchangé et fige `debian/` par digest. Or les `Installed-Build-Depends` découlent de `debian/control` : un verrou dans `sample-app` et un `debian/` figé ailleurs peuvent diverger.
- La décision de 22:12 affaiblit donc mon interprétation de 21:41, qui n'est pas réécrite. **Question** : le verrou va-t-il dans le même artefact que `debian/` ? Je le recommande.

**Conflit 2 : l'ordre des chantiers.** S4 ne peut pas tourner avant la pipeline de `builders/`. **Question** : l'ordre est-il bien `builders/` d'abord ?

**Précédents relevés dans le dépôt**
- **`web/dist`** a été poussé depuis l'hôte, sous `entrees/sample-app/web-dist` (`construction.sh`, lignes 53 à 58 et 145), avec le compte d'écriture. Le packaging traité « comme `web/dist` » hérite donc d'une écriture dans Zot par l'hôte, et de son accord nommé.
- **`porte.rego`** ne juge la provenance ni de `BUILDER` ni de `WEB_DIST` : aucune occurrence. L'image produite par la pipeline de `builders/` aura donc une provenance que la porte ne consomme pas. C'est acceptable, mais à savoir. L'étendre serait un ajout.
- **Date du paquet.** D'après le commentaire de la ligne 26 de `sources.sh`, la date de `debian/changelog` doit égaler celle du dernier commit de `poc/sample-app`. Un `debian/` figé fige donc la version (`1.0.0-1`) et la date du changelog, d'où dpkg tire `SOURCE_DATE_EPOCH`, pour tous les commits.
  - C'est une limite de la décision 1 ; je la consigne.
  - Le `.dsc` est assemblé aujourd'hui par `sources.sh` sur l'hôte. Dans la plateforme, une tâche devra l'assembler, ce qui est un nouveau travail.
- **Réseau de la pipeline `builders/`** : elle fait tourner `mmdebstrap` et a besoin de l'instantané, comme la racine de S1. Le nom `prefetch-deb` est déjà pris par la fermeture. Il faut donc une sortie Cilium de plus, ou un élargissement de `prefetch-deb-sortie`, avec le `NotIn` de `builds-sans-internet`. C'est un changement du cluster de plus.

**Découpage proposé, sans prédictions** :

| Jalon | Contenu | Écrit dans | Accord |
|---|---|---|---|
| S4a | Pipeline `builders/` : image sbuild et chroot par `mmdebstrap`, signés par Chains | Zot (bundles, images), cluster (sortie Cilium, gabarit) | nommé, pour chaque écriture |
| S4b | Pipeline `prefetch-deb` : liste du verrou, InRelease vérifié, `.deb` contrôlés, puis `publier-fermeture` inchangée | Zot (bundles, fermeture), `porte/taches.yml` | nommé |
| S4c | Artefact de packaging (`debian/`, verrou), publié par l'hôte comme `web/dist` | Zot | nommé |
| S4d | Pipeline `sample-app-deb` : préparer (deux fermetures, packaging, `.dsc`), construire sous Kata, ORAS, `publier-image` inchangée ; second trigger, second rattrapage, politique Cilium dédiée, porte étendue | Zot, cluster | nommé |
| S5 | Tests négatifs de M5 de la 05, rejeu de zéro | cluster, Zot | nommé |

**Estimation**, fondée sur les dates des commits, pas de mémoire.
- Durées archivées des jalons comparables :
  - F2 et F3 de la 03 (couple prefetch et publication, chaîne préparer, construire, publier pour une fermeture) : 03/11, de 16:15 à 19:34 UTC, 17 commits ;
  - J7 de la 08 (première chaîne complète) : commits sur 7 jours, du 29/10 au 07/11, 51 commits, rejeux compris.
- Travail fait sur la 06 : environ une journée.
- Projection pour S4a à S5 : 3 à 6 jours de travail. La brique atteindrait donc environ **1 à 1,5 pw**, sous l'estimation de 2 pw et loin du seuil de 4 pw.
- Cette projection est fragile : J7 a duré plus d'une semaine de calendrier. Je la vérifierai à la fin de S4a.

**Questions ouvertes** : l'emplacement du verrou, l'ordre (`builders/` d'abord), la source de `marked` dans la plateforme (la voie image prend `web/dist` par digest), et le push des commits de la 06.

## Additif du 10/11/2026, 22:20 UTC : décision sur l'emplacement du verrou

**Décision du propriétaire** (22:20:23 UTC) : « Oui, avec debian/ ». Ce n'est un accord pour aucune mesure ni aucune écriture.
- Le verrou (`Installed-Build-Depends` et date de l'instantané, avec éventuellement le sha256 de chaque paquet) est placé dans le même artefact que `debian/`, publié par l'hôte (S4c).
- Le conflit 1 de l'additif de 22:14 UTC est levé. L'interprétation de 21:41 UTC (« verrou dans `sample-app` ») est remplacée par cette décision ; elle n'est pas réécrite.
- **Conséquence pour S4b** : `prefetch-deb` lit sa liste dans l'artefact de packaging, fixé par digest dans sa pipeline signée, et non dans le commit de `sample-app`. S4c doit donc précéder S4b.
- Ordre proposé, à confirmer : S4a (`builders/`), S4c (packaging et verrou), S4b (`prefetch-deb`), puis S4d.

**Questions ouvertes** : cet ordre, la source de `marked` dans la plateforme, et le push des commits de la 06.

## Additif du 10/11/2026, 22:21 UTC : décision sur l'ordre des jalons de S4

**Décision du propriétaire** (22:21:12 UTC) : « Oui, cet ordre ». S4 se déroule dans cet ordre : **S4a** (`builders/`), **S4c** (packaging et verrou), **S4b** (`prefetch-deb`), **S4d** (`sample-app-deb`), puis **S5**. Ce n'est un accord pour aucune mesure ni aucune écriture : chaque jalon sera préparé à sec, avec ses prédictions commitées avant tout lancement, puis attendra un accord nommé.

**Questions ouvertes** : la source de `marked` dans la plateforme, à trancher avant S4c, puisque l'artefact de packaging en dépend si `debian/rules` change ; et le push des commits de la 06.

## Additif du 10/11/2026, 22:30 UTC : push consigné ; décision sur `marked`, et ce qu'elle change (lu dans le dépôt, à sec)

**Push consigné** : `57b76be..3eb8489`, de 22:25:37 à 22:25:39 UTC. Il contient 12 commits, tous sur ce README. Avant l'envoi, ce fichier a été contrôlé dans un worktree temporaire, sans aucun secret trouvé. Accord : « Oui, pousse ».

**Décision du propriétaire** (22:30:32 UTC) : « web/dist par digest ». La pipeline deb prend `web/dist` par digest, comme la voie image (`entrees/sample-app/web-dist`, `construction.sh`, ligne 53). Node reste hors de la chaîne. Ce n'est un accord pour aucune mesure ni aucune écriture.

**Ce que la décision change**, vérifié dans le dépôt, à faire en S4c :
- `debian/rules` lance `node build.mjs` dans `override_dh_auto_build`, et `override_dh_auto_clean` supprime `web/dist`. Les deux sont à changer.
  - La construction ne doit plus lancer Node.
  - Le nettoyage ne doit plus effacer un `web/dist` livré. Le nettoyage du paquet source, que sbuild peut lancer avant la construction, l'effacerait. **À mesurer.**
- `main.go` embarque `web/dist` à la compilation (`//go:embed all:web/dist`). `web/dist` doit donc être présent dans l'arbre source avant `go build`.
- `debian/control` déclare `nodejs` dans `Build-Depends`, et la fermeture de S2 le contient. Le retirer change les `Installed-Build-Depends`, donc le verrou et la fermeture.
- **Effet** : le deb de S4 ne sera pas celui de S1 à S3, car ses entrées changent. La comparaison bit à bit sera refaite en S4d ou en S5, entre deux constructions de la nouvelle voie.
- Ces changements touchent `poc/packaging`, qui sert aussi à la brique 05 (rpm), via `sources.sh` et le spec. **À vérifier en S4c** : séparer le paquet source de la plateforme de celui de l'hôte, ou les changer ensemble.

**Questions ouvertes** : aucune avant la préparation de S4a.

## Additif du 10/11/2026, 22:37 UTC : carte de S4a (pipeline `builders/`), à sec, rien lancé

Le propriétaire a répondu « continue » après la clôture de 22:30 UTC. Je le lis comme une permission de préparer S4a à sec, pas comme un accord de mesure ni d'écriture. Rien n'a été lu ni écrit dans le cluster, Zot ou les VM.

**Vérifié dans le dépôt et sur l'hôte**
- **Comptes de Zot** (`stockage/zot.json`, règles lues sans les secrets) : `builders/**` n'a pas de règle propre. Seul `poc-ecriture` y écrit, par `**`. `builds/**` admet `poc-images` (création seule) et `poc-build`.
- **Compte de Chains** : `poc-build` (`politique/chains-zot.yaml`). Chains ne pourrait donc écrire ni `.sig` ni `.att` sous `builders/**` sans changer Zot.
- **Image d'outils** `plateforme/outils-horodatage` (`tsa.sh image`) : base cosign, plus `oras` 1.3.6 et `timestamp-cli`. **Pas de `crane`** : l'assemblage de S1 (`crane append` sur l'hôte) ne se transpose pas tel quel.
- **Création des PipelineRun hors webhook** : `prefetch.sh` de la 03 les crée depuis l'hôte (`kubectl create`, fonction `pr_f2`). La VerificationPolicy `taches-plateforme` (mode `enforce`) exige des tâches et pipelines signées sous `tekton/(tasks|pipelines)/`.
- **Appel de mmdebstrap en S1** (`s1.sh`, ligne 158) : `--skip=cleanup/apt/lists`. Les listes d'apt de l'instantané restent donc dans l'archive `racine`, et leurs noms de fichiers dérivent de l'URL du miroir.
- **Listes épinglables** : les journaux donnent chaque `.deb` avec son sha256. Ce sont les lignes `deb amorce` et `deb racine` de [`s1c-racine.log`](resultats/s1c-racine.log), et `deb chroot-a` de [`s2-racine.log`](resultats/s2-racine.log).
- **Manuel de mmdebstrap 1.5.7** (lu au tag, sur la forge de l'auteur) :
  - un miroir donné comme fichier voit son contenu écrit dans le `sources.list` de la cible ;
  - `--customize-hook` tourne avant le nettoyage final ;
  - `SOURCE_DATE_EPOCH` rend le résultat reproductible « avec les mêmes options et le même contenu de miroir » ;
  - `resolv.conf` et `hostname` de l'hôte sont copiés dans la cible ;
  - le manuel ne dit pas si apt vérifie encore l'InRelease d'un miroir `file://`. **À mesurer.**

**Contenu de l'image, un fait et non un choix** : la racine de s1b et s1c (`f8f221ca…`, iproute2 compris), plus le chroot `buildd` de S2 (D2 a, `e0b1f37c…`). C'est ce chroot que S3 a utilisé, et non celui de S1 (`440ba93b…`), qui a les dépendances de build préinstallées.

**Choix ouverts, avec ma recommandation**
1. **Destination dans Zot.**
   - (a) `builds/builders/sbuild-debian13` : Zot, `publier-image` et Chains restent inchangés. **Recommandé.**
   - (b) `builders/sbuild-debian13`, le nom du README et de l'ADR : il faut une règle nouvelle dans `zot.json` pour `poc-images` et `poc-build`, donc un changement de Zot.
   - (c) `plateforme/…` : précédent de `builder-go-voie-d`, mais poussé par l'hôte, et sans compte de création pour la pipeline.
2. **Réseau du constructeur privilégié.**
   - (a) Comme S1 et S2 : une seule tâche Kata privilégiée, root, ouverte vers les adresses publiques en 80. C'est déjà mesuré, mais cela contredit l'option 3 de la voie image, où la construction n'a aucune sortie.
   - (b) Deux tâches :
     - une tâche runc restreinte télécharge les listes épinglées, vérifie l'InRelease par gpgv avec les clés de ftp-master et le sha256 de chaque `.deb` contre `Packages`, puis reconstitue un miroir partiel (`dists/` et `pool/`) ;
     - une tâche Kata privilégiée, **sans aucune sortie**, lance mmdebstrap sur ce miroir.
     
     **Recommandé.**
   - Dans les deux cas, il faut une sortie Cilium dédiée en 80 sous un nom de tâche neuf, car `prefetch-deb` est réservé à la fermeture par D6. Ce nom doit aussi entrer dans le `NotIn` de `builds-sans-internet`.
   - En (b), il faut en plus que la tâche Kata soit couverte par une politique sans sortie. Aujourd'hui, `construction-sans-sortie` ne sélectionne que `construire-image` ; sinon, sc-stockage, l'API et les services internes resteraient joignables.
   - Ce sont deux changements du cluster, chacun avec son accord.
   - **Effet sur les prédictions en (b)** : le miroir `file://` change le `sources.list` et les noms des listes d'apt. L'égalité bit à bit avec `f8f221ca` n'est donc pas attendue, même si un crochet réécrit le `sources.list` : il faudrait aussi nettoyer les listes, que S1 garde, ce qui est une autre différence. Les prédictions compareraient alors l'état de dpkg avec celui de s1c, et deux exécutions de la pipeline entre elles, bit à bit.
3. **Origine de mmdebstrap dans la tâche hors ligne** (question de confiance).
   - (a) `dpkg -i` des `.deb` de la liste `deb amorce`, téléchargés et vérifiés par la tâche runc, dans l'amorce `debian:trixie-20261104-slim` par digest. C'est fidèle à D4 (a). **Recommandé.**
   - (b) L'image `essais-06/sbuild-debian13:s1b`, qui n'a aucune provenance.
   - (c) Plus tard, l'image `builders/` précédente : auto-hébergement.
4. **Assemblage de l'image.**
   - (a) Layout OCI écrit à la main dans la tâche Kata (tar, JSON et sha256), avec des couches non compressées. Chaque couche est alors l'archive de mmdebstrap elle-même : **son digest se compare directement à `f8f221ca` et `e0b1f37c`**. `publier-image` le pousse sans changement. **Recommandé.**
   - (b) BuildKit (`FROM scratch`, `ADD`), avec une image déjà approuvée : la couche serait réécrite, et ce lien de comparaison se perd.

**Points fixés sans choix, à consigner**
- **Créateur du PipelineRun** : un script de l'hôte, comme `prefetch.sh`. Il n'y a ni webhook ni rattrapage, puisqu'aucun commit de Forgejo n'est en jeu.
- **Signature** : pipeline et tâches signées, publiées en bundles sous `tekton/`, digests ajoutés à `porte/taches.yml`.
- **Entrées de la provenance** : l'amorce, l'InRelease et les listes sont émis en résultats `*_ARTIFACT_INPUTS`, que Chains range dans `resolvedDependencies`. C'est lu dans le code, non mesuré.
- **La porte ne juge pas cette pipeline.** `fermeture_plateforme` ne s'y applique pas, car aucun de ses noms de tâches n'y figure : c'est un succès à vide, comme relevé pour la voie deb au point 11.
- **Effort** : S4a ajoute deux tâches, une pipeline, un script et deux politiques. La projection de 1 à 1,5 pw tient, mais son haut devient plus probable.

**Rien d'écrit pour S4a** au-delà de cette carte : ni tâche, ni script, ni prédiction. Les prédictions dépendent des choix 1 à 4, et le push de `fc155b7` attend toujours un oui.

**Questions ouvertes** : les choix 1 à 4 ci-dessus.

## Note datée du 10/11/2026, 22:47 UTC : trois corrections à la carte de S4a (`d42ad99`), vérifiées sur l'hôte

Vérifié sur les archives de S1 et S2 gardées sur l'hôte (`$W/s1-06`, `$W/s2-06`) et dans les journaux, sans toucher au cluster.

**Correction 1 : les listes des journaux sont incomplètes.**
- `base-files`, `bash`, `dpkg` et `libc6` n'apparaissent dans aucune ligne `deb racine`, `deb chroot-a` ni `deb amorce`.
- Les lignes `deb racine` sont 107, alors que le `var/lib/dpkg/status` de `racine.tar` (`f8f221ca…`) compte 166 entrées `Package:`.
- Les lignes `deb chroot-a` sont 63, alors que le status du chroot de S2 (`e0b1f37c…`) en compte 122.
- Cause probable, non vérifiée dans le code : mmdebstrap retire du cache les `.deb` essentiels après leur installation (`essential/unlink`), avant que le crochet ne liste le cache.
- Le « 238 sur 238 » de S1 ne couvrait donc que les paquets listés.
- **Conséquence pour le choix 2 (b)** : un miroir partiel bâti sur ces listes ne suffirait pas. La liste complète peut se tirer sur l'hôte, hors ligne, du `dpkg/status` des archives (paquet, version, architecture), puis se vérifier contre le `Packages` signé. Ce travail reste à faire à sec, avant les prédictions. La recommandation 2 (b) tient, avec cette liste.

**Correction 2 : `/etc/hostname` est le nom du pod.**
- Il vaut `s1-racine` dans les deux archives de S1, et `s2-racine` dans le chroot de S2. `etc/resolv.conf` fait 102 octets dans les trois archives.
- L'égalité bit à bit entre s1b et s1c s'explique donc aussi par un pod de même nom, et celle des deux chroots de S2 par un seul pod.
- Dans une pipeline, le nom du pod change à chaque TaskRun. **L'égalité entre deux exécutions n'est pas attendue sans un crochet qui fixe `etc/hostname` et `etc/resolv.conf`**, ce que le manuel prévoit.
- Ce crochet écarte aussi toute égalité avec `f8f221ca` et `e0b1f37c`.
- Cela vaut pour 2 (a) comme pour 2 (b). « Déjà mesuré », dans le choix 2 (a), ne couvre pas des pods de noms différents.

**Correction 3 : le digest de couche du chroot ne se compare pas à `e0b1f37c`.**
- En S1 (`s1.sh`, `etape_image`), le chroot entre dans l'image comme fichier `opt/sbuild/trixie-amd64.tar`, à l'intérieur d'une couche qui l'enveloppe.
- Seule la couche racine est l'archive de mmdebstrap elle-même. Pour le chroot, la comparaison porte sur le sha256 du fichier intérieur.
- La recommandation 4 (a) tient : couches non compressées, digest de la couche racine égal au sha256 de l'archive racine, et sha256 du chroot lu dans l'image.

**À vérifier, non bloquant** : la présence de `gpgv` (ou de `sqv`) dans l'amorce slim, pour la tâche runc de 2 (b).

**Forme des prédictions, une fois les choix faits** :
- deux exécutions de la pipeline, bit à bit, avec le crochet de `hostname` et de `resolv.conf` ;
- `dpkg/status` égal à celui de s1c (racine) et de S2 (chroot), hors champs liés au nom d'hôte ;
- couche racine égale au sha256 de l'archive racine.

**Questions ouvertes** : les choix 1 à 4 de la carte, et le push.

*Corrigé à 22:39 UTC* : la note « 22:47 UTC » ci-dessus a été écrite et commitée (`1febbf4`) à 22:39 UTC (horloge de l'hôte, `date -u` relevé à 22:39:25). L'heure de son titre et de son message de commit est fausse ; le contenu est inchangé.

## Note datée du 10/11/2026, 22:51 UTC : recommandations de S4a revues par le conseiller, contrôles en lecture seule

Le propriétaire a demandé que le conseiller valide les recommandations de S4a avant de les lui présenter. Le conseiller a demandé trois contrôles, faits en lecture seule sur le dépôt et l'hôte. Il a aussi révisé la recommandation 2. Cette note corrige la carte de 22:37 UTC et la note de 22:39 UTC sans les réécrire.

**Recommandation 1 (`builds/builders/sbuild-debian13`) : confirmée par trois lectures.**
- **Rétention de Zot** (`stockage/zot.json`) : `builds/**` relève de la règle `**`, avec `deleteUntagged: false`. Seul `builds/scan/**` perd ses référents. Une image poussée par digest, sans tag, n'est donc pas supprimée par la rétention.
- **Admission** : la règle `images-zot-par-digest` de la 08c exige une image du Zot du PoC, par digest, sans liste de dépôts. Aucune politique ne vérifie de signature d'image d'étape dans `builds`.
- **`publier-image`** refuse tout dépôt hors de `sc-stockage.poc.test:5000/builds/`. `builders/` exigerait donc, en plus de la règle de Zot, une autre tâche ou une tâche modifiée, avec un nouveau digest approuvé.

**Exigences de `publier-image`, relues dans son script** :
- `image.tar` à la racine du workspace ;
- un `index.json` où le champ `digest` n'apparaît qu'une fois, donc un seul manifeste ;
- un digest reçu en paramètre, égal à celui de l'index.

La tâche Kata devra écrire ce layout et émettre le digest en résultat.

**Recommandation 2 révisée : la tâche runc de téléchargement s'appelle `prefetch-deb`.**
- La raison du « nom autre que `prefetch-deb` » (additif de 22:14 UTC, et carte de 22:37 UTC) supposait une tâche privilégiée avec réseau, comme la racine de S1. En 2 (b), la tâche qui a le réseau est une tâche runc restreinte qui télécharge une liste épinglée et la vérifie : c'est exactement le rôle de `prefetch-deb` en S4b, seule la liste change.
- Rien dans D6 ne réserve ce nom : `fermeture_plateforme` ne vise que `prefetch-gomod`, et seulement en présence de `preparer-entrees` ou de `construire-image`. **« Réservé à la fermeture par D6 », dans la carte de 22:37 UTC, est faux.**
- `prefetch-deb-sortie` est appliquée depuis 14:29 UTC, et `prefetch-deb` figure déjà dans le `NotIn` de `builds-sans-internet`. **Il ne reste qu'un changement Cilium au lieu de deux** : une politique sans sortie pour la tâche Kata.
- La même tâche servirait à S4a et à S4b, ce qui réduit S4b et suit le principe « un prefetch par écosystème » de l'ADR 0007.

**Recommandation 3 (`dpkg -i` dans l'amorce) : tenue, complétude non confirmée.**
- Les 20 lignes `deb amorce` viennent d'`apt-get install` avec `Keep-Downloaded-Packages`, sans `essential/unlink`. Elles sont donc vraisemblablement complètes par rapport à l'amorce.
- Le `install.log` du pod n'a pas été rapatrié, ce qui empêche de confirmer. Le confirmer sur l'amorce elle-même demanderait de la lire dans Zot, ce que je n'ai pas fait.
- **À mettre en prédiction** : `dpkg -i` hors ligne de ces 20 paquets réussit.

**Recommandation 4 (layout OCI à la main) : tenue**, avec les exigences de `publier-image` ci-dessus.

**Risques non mesurés, à prédire en premier**
- Le téléchargement en runc restreint, non root, depuis l'amorce slim, qui n'a ni curl ni wget. Il faudrait passer par apt, avec des répertoires `Dir::*` détournés et sans verrou.
- La présence de `gpgv` ou de `sqv` dans l'amorce, et l'origine du trousseau.
- La mémoire de la tâche Kata. En S1, un tmpfs de 4 Gio sur 6 Gio contenait la racine et le chroot. Il faudra en plus le miroir, ou le lire depuis le PVC, et écrire le layout dans le PVC.

**Questions ouvertes** : les choix 1 à 4, avec la recommandation 2 révisée, et le push.

## Additif du 10/11/2026, 22:54 UTC : décision du propriétaire sur S4a, et liste complète du constructeur (hôte, hors ligne)

**Décision du propriétaire** (22:52:55 UTC) : « Oui, retiens-les ». Les quatre recommandations validées par le conseiller (note de 22:51 UTC) sont retenues :
1. publication dans `builds/builders/sbuild-debian13`, par `publier-image` inchangée ;
2. une tâche runc restreinte `prefetch-deb` qui télécharge et vérifie, puis une tâche Kata privilégiée sans aucune sortie qui lance mmdebstrap sur le miroir partiel ;
3. mmdebstrap installé par `dpkg -i` dans l'amorce `debian:trixie-20261104-slim`, fixée par digest ;
4. layout OCI écrit à la main, couches non compressées, un seul manifeste.

Ce n'est un accord pour aucune mesure ni aucune écriture.

**Liste complète du constructeur** : [`builder/paquets.txt`](builder/paquets.txt), 199 paquets, 133 065 812 octets. Elle a été tirée sur l'hôte, hors ligne, sans toucher au cluster ni à Zot :
- les paquets `install ok installed` du `var/lib/dpkg/status` de la racine de S1 (`f8f221ca…`, 166 paquets) et du chroot de S2 (`e0b1f37c…`, 122 paquets) ;
- les 20 lignes `deb amorce` de [`s1c-racine.log`](resultats/s1c-racine.log), retrouvées par leur sha256 ;
- chaque paquet, rapproché par nom, version et architecture du `Packages` de l'instantané `20261105T000000Z`. Ce `Packages` a été contrôlé en S1 : InRelease `0584fba3…` signé par les trois clés épinglées, puis `Packages.xz` contrôlé par InRelease ([`s1-prealables.log`](resultats/s1-prealables.log)). **Aucun paquet manquant.**
- Format, une ligne par paquet : nom, version, architecture, sha256, taille, chemin dans le pool.

**Limite** : la liste reproduit ce que S1 et S2 ont installé. Elle ne prouve pas qu'apt, hors ligne, résoudra le même ensemble depuis le miroir partiel. Ce sera une prédiction de S4a.

## Additif du 10/11/2026, 22:58 UTC : prédictions de S4a écrites, NON LANCÉ

Les [prédictions A1 à A17](resultats/s4a-predictions.md) sont écrites et commitées avant le script, les tâches et toute exécution. Rien n'a été lu ni écrit dans le cluster, Zot ou les VM.

**Vérifié à sec avant de les écrire**, sur l'hôte et dans le dépôt :
- les appels exacts de mmdebstrap (`s1.sh` pour la racine, `s2.sh` pour le chroot) et `SOURCE_DATE_EPOCH=1789199741` ;
- `Acquire-By-Hash: yes` dans l'InRelease ;
- le `Packages` de l'hôte, égal à `xz -dc Packages.xz` ;
- `apt-helper`, `sqv`, `xz` et le crochet `file-mirror-automount` dans la racine de S1 ;
- la syntaxe d'`apt-helper download-file` dans apt 3.0.3 ;
- la double publication, réussie en F2 avec un compte en création seule.

**Risques principaux** : `prefetch-deb` en non root (A4), la complétude des 20 paquets de l'amorce (A6) et la vérification de l'InRelease d'un miroir `file://` (A7). Les trois sont des prédictions moyennes.

**Reste à écrire, à sec** : `s4a.sh`, les tâches `prefetch-deb` et `construire-builder`, la pipeline `builder-sbuild` et la NetworkPolicy `builder-sans-sortie`. Chaque étape qui touche Zot ou le cluster attendra son accord nommé.

## Additif du 10/11/2026, 23:03 UTC : S4a écrit à sec, A1 tenue, NON LANCÉ au-delà de l'hôte

**Écrit à sec**, sans rien lancer dans le cluster ni dans Zot :
- le script [`s4a.sh`](s4a.sh) ;
- dans [`builder/`](builder/), la tâche `prefetch-deb` (runc, `apt-helper` avec les hashes), la tâche `construire-builder` (Kata privilégiée, mmdebstrap sur un miroir `file://`, layout OCI écrit à la main), la pipeline `builder-sbuild` et la NetworkPolicy `builder-sans-sortie`.

**Étape `prealables`** : elle tourne sur l'hôte seul, donc sans accord. Elle a rendu le code 0 au troisième passage, après deux corrections du script (détail dans les [prédictions](resultats/s4a-predictions.md)). **A1 est tenue.**

**Non lancé** : `taches`, `reseau`, `pipeline`, `provenance` et `comparaison`. Chaque étape attend un accord nommé.

**L'étape `taches`** se fera en deux passes :
1. `SIGNER=1` : signatures, bundles dans Zot, puis diff de `politique/porte/taches.yml` (08) soumis au propriétaire ;
2. une seconde passe, une fois la liste acceptée.

## Additif du 10/11/2026, 23:11 UTC : étape `taches` de S4a, première passe (`SIGNER=1`)

Lancée de 23:10:15 à 23:10:18 UTC, sur l'accord « Oui, lance taches ». Code 0. Journal : [`s4a-taches.log`](resultats/s4a-taches.log).

**A2, première passe : tenue.**
- `prefetch-deb` et `construire-builder` sont signées par `tkn` 0.46.2 avec la clé des tâches. La clé n'a pas été affichée.
- Leurs signatures sont versionnées dans `builder/*.signee.yaml`.
- Leurs bundles sont publiés dans Zot avec `poc-ecriture` : `tekton/tasks/prefetch-deb@sha256:4dac0609…` et `tekton/tasks/construire-builder@sha256:de18e9cf…`.
- Les deux digests sont absents de la liste revue, comme prévu. La pipeline n'est ni signée ni publiée tant que la liste n'est pas acceptée.

**Diff de `politique/porte/taches.yml` (08) préparé, NON COMMITÉ** : deux entrées ajoutées à la fin, chacune avec son commentaire. Il attend la revue du propriétaire. Ce fichier est la liste `trusted_tasks` de la porte : `construire-builder`, tâche privilégiée et root, y deviendrait acceptable dans toute provenance que la porte juge.

## Additif du 10/11/2026, 23:12 UTC : liste revue acceptée, seconde passe de `taches` tenue

**Décision du propriétaire** : « Accepter ». Le diff de `taches.yml` est commité tel que soumis (`96b7bbd`). Ma demande annonçait aussi la seconde passe ; la réponse vaut donc accord pour celle-ci.

**Seconde passe** de 23:11:17 à 23:11:19 UTC, code 0. Journal : [`s4a-taches.log`](resultats/s4a-taches.log). Il remplace celui de la première passe, qui reste dans `1eb4ed6`.

**A2 : tenue.**
- Les deux tâches sont conformes à leur signature versionnée.
- Leurs digests sont maintenant dans la liste revue.
- La pipeline est signée et publiée : `tekton/pipelines/builder-sbuild@sha256:26683852…`.

**Non lancé** : `reseau`, `pipeline`, `provenance` et `comparaison`. Chaque étape attend un accord nommé. La prochaine est `reseau` : la NetworkPolicy `builder-sans-sortie` posée dans `builds`.

## Additif du 10/11/2026, 23:12 UTC : étape `reseau` de S4a tenue

Lancée à 23:11:49 UTC, sur l'accord « Oui, lance reseau ». Code 0. Journal : [`s4a-reseau.log`](resultats/s4a-reseau.log).

**A3 : tenue.** La NetworkPolicy `builder-sans-sortie` est posée dans `builds`, à côté de `construction-sans-sortie`. Trois contrôles :
- elle est la seule à sélectionner `construire-builder`, en entrée comme en sortie ;
- aucune NetworkPolicy de `builds` n'autorise de trafic ;
- aucune CiliumNetworkPolicy de `builds` n'autorise de trafic vers `construire-builder` (liste vide).

**À noter** : l'efficacité de la politique n'est pas encore mesurée. Ce sont les témoins d'A9, dans l'étape `pipeline`, qui la mesureront.

**Non lancé** : `pipeline`, `provenance` et `comparaison`. Chaque étape attend un accord nommé.

## Additif du 10/11/2026, 23:15 UTC : étape `pipeline` de S4a, premier passage en échec sur `dpkg -i`

Lancée de 23:12:21 à 23:13:52 UTC, sur l'accord « Oui, lance pipeline ». Code 1. Le premier PipelineRun a échoué dans `construire-builder`, et le second n'a pas été créé. Détail : [prédictions et résultats](resultats/s4a-predictions.md).

**Tenues**
- **A4** : téléchargement par `apt-helper`, en runc et sans root, des 199 paquets en 19 s.
- **A9** : les quatre témoins échouent (DNS, Zot, Forgejo, Fastly). La politique `builder-sans-sortie` est donc efficace.
- **A12** : runc pour le téléchargement, Kata pour la construction, toutes deux sur sc-build.

**Réfutée : A6.** Le `dpkg -i` groupé ne respecte pas les pré-dépendances de `python3-minimal` et de `python3`, relevées dans `Packages`. Ce n'est pas un manque de paquet. La correction change `construire-builder`, ce qui demande de la signer à nouveau, de réviser la liste revue et de republier la pipeline. Elle attend un accord.

Rien n'a été publié dans `builds/builders/` : la tâche `publier` n'a pas tourné.

## Additif du 10/11/2026, 23:19 UTC : `taches` relancée en `SIGNER=1` avec la tâche corrigée

Lancée à 23:17:20 UTC, sur l'accord « Oui, relance taches ». Code 0. Journal : [`s4a-taches.log`](resultats/s4a-taches.log).

- **`construire-builder` corrigée** : signée de nouveau, bundle `tekton/tasks/construire-builder@sha256:49173846…`.
- **`prefetch-deb` re-signée par erreur.** Son contenu n'avait pas changé, mais le script re-signait tout en `SIGNER=1`. Elle a pris un nouveau digest, `9fa81ae9…`, poussé dans Zot. Ce bundle reste hors de la liste revue et ne sert pas.
  - La signature versionnée déjà acceptée a été restaurée depuis git, pour garder `4dac0609`.
  - Le script ne re-signe plus une tâche inchangée (correction à sec, non rejouée).
- **Diff de `taches.yml` préparé, NON COMMITÉ** : `49173846` remplace `de18e9cf`, qui est retirée de la liste comme version cassée. `prefetch-deb` reste à `4dac0609`. Il attend la revue du propriétaire.

## Additif du 10/11/2026, 23:19 UTC : liste revue acceptée, seconde passe de `taches` tenue (tâche corrigée)

**Décision du propriétaire** : « Accepter ». Le diff est commité tel que soumis (`3673760`) : `49173846` remplace `de18e9cf`, qui est retirée de la liste.

**Seconde passe** à 23:18:19 UTC, code 0.
- `prefetch-deb` reste à `4dac0609` et `construire-builder` passe à `49173846`. Les deux sont conformes à leur signature versionnée et inscrites dans la liste revue.
- La pipeline est signée et publiée : `tekton/pipelines/builder-sbuild@sha256:3066d2f0…`.

**Non lancé** : le second passage de `pipeline`. Il attend un accord, car le script a été modifié depuis le dernier.

## Additif du 10/11/2026, 23:22 UTC : second passage de `pipeline`, échec sur `--no-download` ; liste de l'amorce complète

Lancé de 23:18:52 à 23:20:05 UTC, sur l'accord « Oui, relance pipeline ». Code 1. Rien n'a été publié. Détail : [prédictions et résultats](resultats/s4a-predictions.md).

- **La liste des 20 paquets de l'amorce est complète.** apt les résout depuis les seuls fichiers locaux, sans dépendance manquante.
- **Échec** : erreur interne d'apt avec `--no-download`. La cause est lue dans le code d'apt 3.0.3 : le chemin d'un `.deb` local n'est rendu absolu qu'après le passage de la méthode `file`, que `--no-download` empêche.
- **Correction proposée** : retirer `--no-download`. Les fichiers locaux passent alors par la méthode `file`, qui copie sans réseau. Le réseau reste coupé par `builder-sans-sortie` (A9 tenue deux fois). Cela demande une nouvelle signature de `construire-builder`, une revue de la liste et un accord.

## Additif du 10/11/2026, 23:24 UTC : `--no-download` retiré, contrôles ajoutés sur l'hôte, NON SIGNÉ

La correction est validée par le conseiller. Avant de signer, trois contrôles nouveaux sur l'hôte passent dans `prealables` (code 0) : syntaxe des scripts de tâche, arguments de mmdebstrap, et layout OCI sur des archives factices, lu comme le fait `publier-image`. Détail : [prédictions](resultats/s4a-predictions.md).

**Reste** : `taches` en `SIGNER=1`, puis la revue de la liste (le nouveau digest remplace `49173846`), la seconde passe et `pipeline`. Chaque étape attend son accord.

## Additif du 10/11/2026, 23:26 UTC : `taches` relancée en `SIGNER=1` (sans `--no-download`)

Lancée à 23:25:02 UTC, sur l'accord « Oui, relance taches ». Code 0. Journal : [`s4a-taches.log`](resultats/s4a-taches.log).

- **Correctif de `SIGNER=1` tenu**, rejoué pour la première fois : `prefetch-deb` reste à `4dac0609`, sans nouvelle signature.
- **`construire-builder` signée de nouveau** : `tekton/tasks/construire-builder@sha256:746c2e11…`.
- **Diff de `taches.yml` préparé, NON COMMITÉ** : `746c2e11` remplace `49173846`, retirée comme version cassée. Il attend la revue du propriétaire.

## Additif du 10/11/2026, 23:26 UTC : liste acceptée, seconde passe de `taches` tenue (sans `--no-download`)

**Décision du propriétaire** : « Accepter ». Le diff est commité tel que soumis (`9705337`) : `746c2e11` remplace `49173846`.

**Seconde passe** à 23:25:42 UTC, code 0. `prefetch-deb` (`4dac0609`) et `construire-builder` (`746c2e11`) sont conformes à leur signature et inscrites dans la liste revue. La pipeline est publiée sous `tekton/pipelines/builder-sbuild@sha256:a9d48331…`.

**Non lancé** : le troisième passage de `pipeline`, qui attend un accord.

## Additif du 10/11/2026, 23:33 UTC : S4a, pipeline `builders/` tenue, image reproductible

Troisième passage de `pipeline`, de 23:26:12 à 23:31:47 UTC, sur l'accord « Oui, relance pipeline ». Code 0. Détail : [prédictions et résultats](resultats/s4a-predictions.md).

**La plateforme construit l'image de build sbuild sans réseau, la publie et la signe. Deux exécutions donnent le même digest :** `builds/builders/sbuild-debian13@sha256:749d746c…`.
- Téléchargement vérifié en runc, sans root, en 17 s.
- Construction en Kata, sans aucune sortie réseau : apt installe mmdebstrap en 13 s, puis mmdebstrap construit la racine en 22 s et le chroot en 21 s.
- Publication de 740 Mo par `publier-image`, inchangée.
- Pic mémoire de l'invité : environ 1,7 Gio sur 6.

**Réserves**
- La vérification de l'InRelease du miroir par apt est déduite (dépôt accepté sans `trusted=yes`), pas mesurée. Le test négatif est prévu en S5.
- L'échantillonneur du tmpfs sous-estime le pic. `memory.peak` fait foi.

**Reste pour S4a** : `provenance` (A15) et `comparaison` (A8, A14, A16 à A18). Ce sont des lectures dans Zot, puis des contrôles sur l'hôte, sur accord.

## Additif du 10/11/2026, 23:39 UTC : S4a tenu

`provenance` et `comparaison` ont tourné de 23:37:20 à 23:37:24 UTC, sur l'accord « Oui, lance-les ». Code 0. A8 et A14 à A18 sont tenues. Bilan : [prédictions et résultats](resultats/s4a-predictions.md).

**L'image de build `builds/builders/sbuild-debian13@sha256:749d746c…` est construite par la plateforme**, et cette construction a les propriétés suivantes :
- elle est reproductible : deux exécutions donnent le même digest ;
- elle se fait sans réseau ;
- elle est signée par Chains, et sa provenance nomme l'amorce, l'InRelease de l'instantané (`0584fba3…`) et les tâches revues ;
- l'image contient les mêmes paquets que la racine de S1 et le chroot de S2.

**Effort de S4a** : de 22:37 à 23:39 UTC, en comptant la carte, les décisions, trois cycles de signature et trois passages de `pipeline`.

**Limites**
- La vérification de la signature de l'InRelease du miroir par apt est déduite, pas mesurée. Le test négatif est prévu en S5.
- L'échantillonneur du tmpfs sous-estime le pic.
- La porte ne juge pas cette pipeline.

**Suite, selon l'ordre décidé** : S4c (packaging et verrou). L'ADR 0007 conteste « web/dist par digest », sur lequel S4c repose : il faut d'abord que le propriétaire tranche.

## Note datée du 10/11/2026, 23:40 UTC : bilan de S4a corrigé, effort de la brique revu

**Correction** : le bilan de S4a compte à tort A4 et A7 comme pleinement tenues. Ni le refus d'un hash faux ni la vérification de la signature de l'InRelease ne sont mesurés. Trois tests négatifs s'ajoutent à S5 : hash faux, `.deb` altéré, InRelease au mauvais sha256. Détail : [prédictions](resultats/s4a-predictions.md).

**Effort, revu après S4a comme annoncé à 22:14 UTC.** Les chiffres viennent de `git log` sur `poc/bricks/06-deb-sbuild` :
- 90 commits sur deux jours de calendrier : 2 le 05/11 et 88 le 10/11, ce dernier jour de 12:14 à 23:38 UTC environ ;
- environ 1,5 jour de travail effectif, soit à peu près 0,3 pw.

Le total reste sous l'estimation de 2 pw, et très loin du seuil de 4 pw : aucune décision n'est due. La projection de 1 à 1,5 pw pour la brique entière tient, avec S4c, S4b, S4d et S5 encore à faire. Elle reste fragile, car S4c dépend d'une décision ouverte par l'ADR 0007.

## Additif du 10/11/2026, 23:52 UTC : push consigné, et décision du propriétaire sur le processus

**Push** de 23:40:42 à 23:40:44 UTC : `3eb8489..44cbe06`, 27 commits, 24 fichiers. Les secrets ont été contrôlés dans un worktree temporaire : aucun secret trouvé. Accord : « Oui, pousse ».

**Décision du propriétaire** (23:50:00 UTC, « ok je suis l'advisor ») : il adopte les leviers recommandés par le conseiller pour alléger le processus. Rien ne change pour L3, pour B5 ni pour les mesures des grilles.
- **(e)** Toute nouvelle tâche privilégiée est d'abord mise au point dans un pod d'essai, sur le modèle de S1, avec un accord par pod. Elle n'est signée qu'une fois au point. Sur S4a, ce levier aurait évité 6 des 11 accords et deux bundles cassés.
- **(a)** Un additif par jalon. Chaque décision laisse une ligne datée dans le message de commit au moment où elle est prise.
- **(b)** Un accord par jalon, seulement pour les étapes en lecture ou réversibles. Restent soumis à un accord à part :
  - les écritures dans Zot, qui sont définitives ;
  - la revue de `taches.yml` ;
  - tout script modifié.
- **(d)** Des contrôles sur l'hôte avant chaque signature.
- **(c) est refusé** : pas d'image d'outils construite avec le réseau.

## Additif du 11/11/2026, 16:20 UTC : décision du propriétaire sur la source de `marked` pour le deb

**Vérifications faites avant la question**, en lecture seule, sans réseau ni installation :
- **Hermeto 0.64.0 n'a pas besoin de Node pour npm.** Le module `core/package_managers/javascript/npm` du venv installé par mise (`mise.toml`, tâche `outils:hermeto`) n'importe ni `run_cmd`, ni `subprocess`, et n'appelle pas `which`. Il lit le lockfile et télécharge par `aiohttp`. L'image de prefetch, sans Node (`Dockerfile.prefetch` de la 03), convient donc telle quelle.
- **Node est déjà dans la fermeture deb de S2**, sous l'InRelease signé : `nodejs` 20.19.2+dfsg-1+deb13u2 (sha256 `3e2d151f…`) et `libnode115` de même version (`resultats/s2-fermeture-attendue.txt`, `resultats/s2-sample-app_1.0.0-1_amd64.buildinfo`).
- **Seul `marked` vient de l'hôte** (`poc/packaging/sources.sh`, lignes 39 à 48). `build.mjs` n'a besoin que de `node` et de `marked` sur disque, pas du binaire npm.
- **Mesure archivée** : le banc nix (`poc/benchmarks/nix/reference/hermeto.sh`, lignes 36 et 37) passe gomod et npm en un seul appel à Hermeto 0.64.0 sur sample-app ; l'archive npm altérée y est refusée (T3). Limite : c'était sur l'hôte, pas dans une tâche de la plateforme.
- **Sortie réseau** : `prefetch-sortie` (08) autorise déjà le port 443 vers les adresses publiques, donc le registre npm, mais seulement pour les pods de `prefetch-gomod`.

**Décision du propriétaire** (11/11/2026, 16:19:27 UTC) : « npm par la plateforme ». La question portait sur le deb : la fermeture npm du deb sera produite par la plateforme. La voie image de la 08 garde `web/dist` par digest ; c'est la dette déjà notée par l'ADR 0007. Pour le deb, cette décision remplace celle de 22:30 UTC (« web/dist par digest »), qui n'est pas réécrite. Ce n'est un accord pour aucune mesure ni aucune écriture.

**Ce que la décision change**, vérifié dans le dépôt :
- La liste de 22:30 UTC tombe : `debian/control` garde `nodejs`, `debian/rules` garde `node build.mjs`, et le verrou tiré de S2 ne change pas.
- **Correction** de ce que j'ai présenté avant la décision (« `debian/` inchangé ») : ce n'est vrai que sous condition. `debian/rules` construit avec `GOFLAGS=-mod=vendor` et `GOPROXY=off`, depuis l'archive de `sources.sh`, qui contient `vendor/` et `web/node_modules/marked`. Dans la plateforme, il faut donc soit que la préparation (S4d) reconstitue `vendor/` depuis la fermeture gomod et `web/node_modules/marked` depuis la fermeture npm, soit que `debian/rules` passe en mode module. Le mode module change le binaire (banc nix, B-1 : hash `h1:` inscrit dans les métadonnées). À trancher dans la carte de S4c.
- **Côté plateforme**, une tâche de prefetch doit produire la fermeture npm : nouvelle signature, revue de `taches.yml`, et porte à adapter si la fermeture change de tâche (nom écrit en dur, `porte.rego`, lignes 69 à 74).

**Questions ouvertes** : la carte de S4c, à préparer à sec ; le push de `dd99196`.

## Additif du 11/11/2026, 16:30 UTC : S4c tenu

**Ce qui est publié** : l'artefact de packaging du deb, `entrees/sample-app/packaging-deb@sha256:c1719b13…`. Il contient `poc/packaging/debian/` inchangé et le verrou [`poc/packaging/verrou-deb.txt`](../../packaging/verrou-deb.txt) : 162 paquets, au format de `builder/paquets.txt`. Détail : [prédictions et résultats](resultats/s4c-predictions.md).

**Ce qui s'est passé**
- **Choix validés par le conseiller** : `debian/rules` reste en mode vendor ; la configuration d'Hermeto et le choix de la tâche npm passent en S4b.
- **Prédictions** commitées à 16:25:24 UTC (`defdd02`).
- **Étape `verrou`** (16:25:30 UTC, hôte seul, sans accord) : C1 à C4 tenues. Le verrou est tiré des `Installed-Build-Depends` de S2, rapprochés du `Packages` contrôlé par l'InRelease `0584fba3…`. Il est égal à la fermeture de S2.
- **Étape `publier`** (16:27:54 UTC, accord « Oui, lance publier ») : C5 à C7 tenues. Le même digest est obtenu en local et dans Zot, et les fichiers tirés par digest sont égaux à ceux du dépôt.

**Ce qu'il faudra traiter ensuite**
- `debian/rules` perd son bit d'exécution par oras : à rétablir en S4d.
- `prefetch-deb` reçoit sa liste en paramètre et ne peut pas lire Zot. Le transport du verrou, et la trace de son digest dans la provenance, sont à concevoir dans la carte de S4b.
- Corrections faites par notes datées : l'heure de l'en-tête des prédictions, et le tableau présenté avant la décision.

**Effort** : de 16:19 à 16:30 UTC, deux accords (la décision et `publier`).

**Suite, selon l'ordre décidé** : S4b (`prefetch-deb` pour la fermeture deb, et la fermeture npm par la plateforme), à préparer à sec.


## Additif du 11/11/2026, 16:31 UTC : push consigné

**Push** de 16:30:26 à 16:30:28 UTC : `44cbe06..7b57ca7`, 6 commits, 9 fichiers, en avance rapide. Avant l'envoi, les secrets ont été contrôlés dans un worktree temporaire : aucun secret trouvé. Accord : « Oui, pousse ».

## Additif du 11/11/2026, 16:48 UTC : décisions pour S4b

**Décision du propriétaire** (16:42:27 UTC) : « A, N1, combinée ». Ce n'est un accord pour aucune mesure ni aucune écriture.
- **A, transport du verrou** : l'hôte tire l'artefact de packaging par digest (`c1719b13`). Les colonnes 4 à 6 du verrou (sha256, taille, chemin) sont inscrites dans le gabarit de la pipeline de la fermeture deb, avant sa signature, comme en S4a. `prefetch-deb` (`4dac0609`) et `publier-fermeture` (`7fa92ad3`) ne changent pas.
- **N1, tâche npm** : une version 2 de `prefetch-gomod`, sous le même nom, dans un gabarit neuf de la 06. Elle reçoit la demande Hermeto de la pipeline signée, et contrôle le lockfile npm avant Hermeto. La 08 reste en version 1 (`5e7e5662`) : son gabarit et sa signature versionnée ne sont pas touchés.
- **Fermeture applicative combinée** : un seul appel à Hermeto pour gomod et npm. Elle produit une fermeture applicative, plus la fermeture deb : la porte en jugera deux en S4d.

**Ce que A remplace**, sans réécrire les textes commités :
- la conséquence de l'additif de 22:20 UTC (« `prefetch-deb` lit sa liste dans l'artefact de packaging ») ;
- la ligne de l'en-tête de `builder/prefetch-deb.yaml` : « S4b : la liste viendra du verrou par le workspace ».

Avec A, c'est l'hôte qui lit l'artefact de packaging, et non la plateforme. La plateforme ne confrontera la fermeture deb au verrou qu'en S4d, par une tâche qui reste à écrire.

**Vérifié hors ligne pendant la carte** :
- **Provenance** : la provenance de F2 (`~/.cache/supply-chain-poc/03/f2/prov.json`) contient les paramètres de chaque TaskRun dans `resolvedDependencies`. Pour un paramètre long, comme la liste de 162 lignes, ce n'est encore qu'une prédiction de S4b.
- **npm dans Hermeto 0.64.0** : il accepte toute URL `https` ou `git` d'un lockfile. Une dépendance du registre sans `integrity` n'y est que signalée, pas refusée. Il lit `npm-shrinkwrap.json` avant `package-lock.json`. D'où le contrôle de la version 2.
- **`subPath`** : le kubelet v1.35.0 crée un dossier de `subPath` absent avec le mode de la racine du volume (`GetMode`, puis `Fchmod`), sans changer son propriétaire (`pkg/kubelet/kubelet_pods.go` et `pkg/volume/util/subpath/subpath_linux.go`, lus sur GitHub). Qu'un pod en UID 65532 puisse y écrire dépend donc du mode de la racine du PVC local-path : c'est une prédiction de S4b.

## Additif du 11/11/2026, 17:37 UTC : S4b tenu

**S4b tenu**, de 16:56:14 à 17:36:58 UTC, avec les accords nommés de chaque étape : B1 à B16 ([prédictions et résultats](resultats/s4b-predictions.md)). Les deux fermetures de construction du deb sont produites par la plateforme, signées par Chains, et reproduites deux fois au même digest :
- **fermeture deb** : pipeline `prefetch-deb-sample-app` (`86e70b7f`), avec `prefetch-deb` et `publier-fermeture` inchangées. Fermeture `builds/fermetures/sample-app-deb@sha256:bb7599a2…` : 162 `.deb`, InRelease et index, pool égal au verrou ;
- **fermeture applicative** : pipeline `prefetch-sources-sample-app` (`0ebd1cb8`), avec `prefetch-gomod` en version 2 (`170bef53`, ajoutée à la liste revue après relecture, `915e14e`) et `publier-fermeture`. Fermeture `builds/fermetures/sample-app-sources@sha256:50dc73f7…` : modules Go égaux à ceux de F2, et `marked-16.4.1.tgz` conforme à l'integrity du lockfile.

**Décisions et accords du jalon** (lignes datées dans les commits) : « A, N1, combinée » (16:42:27 UTC) ; avis du conseiller sur B9, demandé par le propriétaire ; « Oui, lance taches_deb et deb » ; « Oui, lance-la » (`SIGNER=1 taches_sources`) ; « Oui, commite-le » (liste revue) ; « Oui, lance-les » (`taches_sources` et `sources`, puis `comparaison` et `provenance`).

**Écarts et constats** : B14 a deux entrées `project_files` (`package-lock.json` et `package.json`) au lieu d'une ; `publier-fermeture` journalise une erreur sur `bom.json` absent pour la fermeture deb ; le `bom.json` d'Hermeto, non publié, change d'une exécution à l'autre ; deux titres de notes ont été datés à tort, et corrigés par des lignes datées.

**Durée** : S4b a pris environ une heure, de la reprise par « continue » (16:32:02 UTC, lue dans la transcription) au bilan. La brique reste sous son estimation de 2 pw.

**Suite, selon l'ordre décidé** : S4d (pipeline `sample-app-deb` : confronter la fermeture deb au verrou, reconstituer `vendor/` et `web/node_modules/marked`, rétablir le bit d'exécution de `debian/rules`, porte à plusieurs fermetures), puis S5.

## Additif du 11/11/2026, 17:40 UTC : push consigné

**Push** de 17:40:22 à 17:40:24 UTC : `7b57ca7..cdf4c9b`, 14 commits, 20 fichiers, en avance rapide. Accord : « Oui, pousse ». Il contient la modification relue de `politique/porte/taches.yml` de la 08 (`915e14e`).

**Contrôle des secrets**, dans un worktree temporaire : aucun secret dans les 20 fichiers qui diffèrent d'origin.
- **Premier contrôle sans valeur** (17:39:46 UTC) : j'ai appelé `tools/secrets-depot.sh` par le chemin du dépôt principal. Le script se place à la racine de son propre dépôt (`cd "$(dirname "$0")/.."`). Il a donc examiné l'arbre principal, qui était propre (« fichiers : 0 »), et non le worktree.
- **Contrôle refait** avec la copie du worktree : « fichiers : 20 ».
- **Pushs précédents** : relus dans la transcription, ils appelaient tous la copie du worktree.

## Additif du 11/11/2026, 17:51 UTC : carte de S4d, à sec, rien lancé

Le propriétaire a répondu « Continue » après la clôture de S4b (17:44:27 UTC, lu dans la transcription). Je le lis comme une permission de préparer S4d à sec, pas comme un accord de mesure ni d'écriture. Rien n'a été lu ni écrit dans le cluster, Zot ou les VM. La carte a été relue par le conseiller avant les contrôles ci-dessous.

**Contrôles sur l'hôte, hors ligne**, sur les copies des fermetures tirées par digest en S4b (étape `comparaison`) :
- **`vendor/`** : Go 1.26.10, celui de l'image `outils-prefetch`, lance `go mod vendor` sous `unshare -rn`, avec `GOPROXY=off` et un `GOMODCACHE` copié de la fermeture `sample-app-sources@50dc73f7`. Le résultat est identique au `vendor/` de l'archive de `sources.sh` (`07521c1e…`, faite avec Go 1.24.7), et `go mod verify` passe.
- **`marked`** : `marked-16.4.1.tgz` de la même fermeture a l'integrity du lockfile. Extrait avec `--strip-components=1`, il donne un `web/node_modules` identique.
- **Arbre entier** (commit `3da431db` de `poc/sample-app`, plus `vendor/` et `marked`) : mêmes chemins et même contenu que l'archive. Les modes ne diffèrent que par le umask de l'hôte (002), que l'archive neutralise (`--mode=go-w,a+rX`).
- **`debian/`** : seul `rules` est en 100755 (`git ls-files -s`). C'est le seul bit d'exécution à rétablir.
- **`dpkg-dev`** 1.22.22 est dans `builder/paquets.txt` : le `.dsc` peut être assemblé dans le pod de construction.
- **Chroot de l'image S4a** (`aec1c7a9…`, différent de `e0b1f37c` utilisé en S3) : `sources.list` pointe vers l'instantané et il n'y a aucune liste d'apt (A14). La neutralisation de S3 se réduit donc à vider `sources.list` ; la suppression des listes n'a plus d'objet.
- **Image S4a** : sa configuration a été vérifiée en S4a (`diff_ids`, `linux/amd64`, `HOME=/w/home`), mais elle n'a jamais été lancée comme image de pod. Le pod d'essai sera son premier lancement.
- **Sortie réseau** : `builds-sans-internet` (08c) n'exempte que `prefetch-gomod` et `prefetch-deb`. Une tâche de préparation neuve n'a donc que les adresses privées (Forgejo, Zot), comme `preparer-entrees`.

**Conséquence** : la prédiction centrale est fondée. Le deb de S4d devrait être `0b489d43…`, celui d'OBS, de S1 et de S3 : mêmes sources, même `vendor/`, même `marked`, même `debian/`, mêmes paquets de build (verrou égal à la fermeture de S2). Ce qui change : le chroot (`hostname`, `resolv.conf`), et la construction par une tâche Tekton.

**Découpage proposé**. La carte de 22:14 UTC présentait S4d comme un seul jalon ; je propose trois sous-jalons, dans cet ordre :

| Jalon | Contenu | Écrit dans | Accord |
|---|---|---|---|
| S4d1 | Pipeline `sample-app-deb`, lancée depuis l'hôte comme S4a et S4b : `preparer-deb`, `construire-deb`, `publier-image` inchangée | Zot (bundles, artefact), cluster (NetworkPolicy), `porte/taches.yml` | nommé, par écriture |
| S4d2 | Porte étendue : plusieurs fermetures, Kata pour `construire-deb`, préparation du deb, jugement d'un artefact deb | Zot (VSA), cluster (porte) | nommé |
| S4d3 | Second trigger et second rattrapage | cluster | nommé |

**Contrainte d'ordre** : dans `porte.rego`, `_construction` ne connaît que `construire-image`, `_preparation` que `preparer-entrees`, et `_prefetch` exige `prefetch-gomod`, `publier-fermeture` et `CHAINS-GIT_URL`. Avec deux tâches neuves, `construction_kata` et `fermeture_plateforme` réussiraient à vide : un deb jugé par la porte actuelle passerait sans contrôle de Kata ni de fermeture. Aucun trigger ne sera donc branché avant la porte étendue.

**Forme proposée de S4d1**
1. **`preparer-deb`**, pod runc restreint (UID 65532), sans secret :
   - le commit est cloné depuis Forgejo et exporté, comme dans `preparer-entrees` ;
   - les deux fermetures et l'artefact de packaging (`c1719b13`) sont tirés par digest, fixés dans la pipeline signée ;
   - la fermeture deb est confrontée au verrou : InRelease `0584fba3…`, et exactement les 162 `.deb` du verrou (sha256, taille, chemin), rien de plus ;
   - `vendor/` est reconstitué par `go mod vendor` (image `outils-prefetch`, `GOPROXY=off`), puis `go mod verify` ;
   - `marked` est extrait après contrôle de l'integrity, et `debian/` copié avec le bit d'exécution de `rules` ;
   - à Chains : `CHAINS-GIT_URL`, `CHAINS-GIT_COMMIT`, et un résultat `*_ARTIFACT_INPUTS` par entrée (deux fermetures, packaging, image de build), sous des noms distincts.
2. **`construire-deb`**, pod Kata privilégié :
   - image de build `builds/builders/sbuild-debian13@749d746c`, par digest ;
   - workspace d'entrées en lecture seule ; travail sur un emptyDir en mémoire ;
   - le pool est revérifié contre le verrou ;
   - l'archive amont est assemblée avec la commande `tar` de `sources.sh`, à la date de `dpkg-parsechangelog -STimestamp`, puis le `.dsc` par `dpkg-source -b`. **Écart avec la carte de 22:14 UTC**, qui plaçait le `.dsc` dans la préparation : seule l'image de build a `dpkg-dev`, ce qui évite une image de plus ;
   - sbuild en UID 1000, `--chroot-mode=unshare`, avec le chroot de l'image, `--extra-package` sur le pool, et `sources.list` vidé ;
   - aucune entrée ni sortie réseau : NetworkPolicy `construction-deb-sans-sortie`, sans règle, sur le modèle de `builder-sans-sortie` ;
   - l'artefact sort en manifeste d'image OCI écrit à la main, comme en S4a, pour que `publier-image` et `ec validate image` fonctionnent sans changement.
3. **`publier-image`**, inchangée (`d21931f3…`), vers `builds/sample-app-deb`.

**Processus** : pod d'essai de `construire-deb` avant toute signature (levier e) ; deux tâches neuves, donc `SIGNER=1` puis une revue de `taches.yml` dans un commit à part, deux accords distincts ; la NetworkPolicy est une écriture dans le cluster, sous accord nommé.

**Déjà listé pour la suite**
- S4d2 :
  - une forme de fermeture deb pour `_prefetch` (`prefetch-deb` et `publier-fermeture`, sans git) ;
  - `porte_test.rego` à étendre ;
  - `porte-job` exige la VSA de replay (brique 10) et le scan (07a), qui échoueront pour un deb : décision à prendre ;
  - `ec validate image` sur l'artefact deb, non mesuré.
- S4d3 : `rattrapage.yaml` a `resourceNames: [sample-app]`, et `main.go` ne lit qu'un gabarit.

**Effort** : la brique en est à environ 0,35 pw (0,3 pw au bilan de S4a, puis S4c et S4b en environ une heure et demie). Estimation de S4d : 2 à 4 jours de travail (S4d1 de 1 à 2, S4d2 de 0,5 à 1,5, S4d3 environ 0,5), donc une brique d'environ 0,8 à 1,2 pw avec S5, sous l'estimation de 2 pw et loin du seuil de 4 pw. C'est une estimation : J7, de taille comparable, a duré 7 jours de calendrier.

**Questions au propriétaire**
1. Le découpage S4d1, S4d2, S4d3, avec la porte avant le trigger.
2. Le contenu de l'artefact signé. S3 a mesuré que seul `Build-Date` diffère entre deux `.buildinfo`, ce qui rend le choix structurant :
   - (a) le deb seul : le digest de l'artefact est reproductible, et la porte juge un digest stable. Le `.buildinfo` reste dans le journal du TaskRun et dans les résultats. **Ma recommandation** ;
   - (b) le deb et le `.buildinfo` : la reproductibilité se juge sur le sha256 du deb, et le digest de l'artefact change à chaque exécution.
3. L'assemblage du `.dsc` dans le pod de construction, au lieu de la préparation.

**Décision du propriétaire** (11/11/2026, 17:54:35 UTC) : « Oui, retiens-les ». Sont retenus : le découpage S4d1, S4d2, S4d3, avec la porte avant le trigger ; le deb seul dans l'artefact signé (a) ; l'assemblage du `.dsc` dans le pod de construction. Ce n'est un accord pour aucune mesure ni aucune écriture : S4d1 sera préparé à sec, avec ses prédictions commitées avant tout lancement.

## Additif du 11/11/2026, 19:58 UTC : S4d1 tenu

**S4d1 tenu**, de la carte (« Continue », 17:44:27 UTC) au bilan (19:57:28 UTC), avec les accords nommés de chaque étape : D1 à D17 ([prédictions et résultats](resultats/s4d-predictions.md)). **La plateforme construit le deb de sample-app de bout en bout** : la pipeline signée `sample-app-deb` (`82c8373d`) enchaîne `preparer-deb` (runc ; clone, trois artefacts tirés par digest, fermeture deb confrontée au verrou, `vendor/` et `marked` reconstitués), `construire-deb` (Kata, sbuild en UID 1000, entrées en lecture seule, aucune sortie réseau) et `publier-image` inchangée. Elle publie `builds/sample-app-deb@sha256:039949f9…`, même digest aux deux exécutions et digest calculé à l'avance sur l'hôte ; le deb est `0b489d43…`, celui d'OBS, de S1 et de S3. Chains signe, et la provenance nomme le commit, les deux fermetures, l'artefact de packaging, l'image de build et les tâches revues.

**Décisions et accords du jalon** (lignes datées dans les commits) : « Oui, retiens-les » (17:54:35 UTC : découpage S4d1, S4d2, S4d3 ; deb seul ; `.dsc` dans le pod de construction) ; « Ok » (`busybox_outils`, `reseau`, `essai`) ; trois cycles de signature, de relecture de `taches.yml` et de lancement de la pipeline ; « Oui, lance-le » (`essai_preparer`) ; « Oui, lance-les » (`comparaison`, `provenance`).

**Écarts** : deux PipelineRuns en échec dans `preparer-deb`, de même origine (les contrôles sur l'hôte imitaient l'environnement de la tâche, et le pod d'essai ne couvrait que la tâche privilégiée) ; corrigés par un pod d'essai de la préparation. Quatre bundles inutilisables restent dans Zot (`preparer-deb` `b310c262` et `5f0ca26b`, pipeline `83455f46` et `c43988a8`). **Leçon pour la suite** : le levier (e) s'applique à toute tâche neuve, privilégiée ou non, avant sa signature.

**Constat** : le `.debian.tar.xz` de `sources.sh` portait le umask de l'hôte (664) ; celui de la plateforme a les modes de git. Le `.dsc` change, pas le deb.

**Durée** : environ 2 h 15, de 17:44 à 19:58 UTC. La brique reste sous son estimation de 2 pw, au bas de la fourchette de la carte pour S4d1 (1 à 2 jours).

**Suite, selon le découpage décidé** : S4d2 (porte étendue : plusieurs fermetures, Kata pour `construire-deb`, préparation du deb, jugement d'un artefact deb, VSA et scan), puis S4d3 (trigger et rattrapage), puis S5.

## Additif du 11/11/2026, 19:59 UTC : push consigné

**Push** de 19:58:52 à 19:58:53 UTC : `cdf4c9b..66b68da`, 18 commits, 33 fichiers, en avance rapide. Accord : « Oui, pousse ». Il contient les deux modifications relues de `politique/porte/taches.yml` de la 08 (`3836bde`, `cc4b8dd`, `c5da4c4`).

**Contrôle des secrets**, dans un worktree temporaire, avec le script de la copie : « fichiers : 33 », égal au nombre de fichiers qui diffèrent d'origin ; aucun secret trouvé.

**Correction datée du 11/11/2026, 19:59 UTC** : l'additif ci-dessus (`f153c92`) annonce « les deux modifications relues » de `taches.yml` en citant trois commits. Il y en a trois, toutes relues : ajout des deux tâches (`3836bde`), puis deux remplacements du digest de `preparer-deb` (`cc4b8dd`, `c5da4c4`).

## Additif du 11/11/2026, 20:07 UTC : carte de S4d2, à sec, rien lancé

Rédigée sur « continue » (cadre : préparer sans rien lancer), après relecture de `porte.rego`, `porte-job.yaml`, `juger` (`politique.sh` de la 08), `vsa.sh`, `scan-verifier.sh` et `scanner.sh` (07a), et avis du conseiller. Aucune écriture dans le cluster ni dans Zot.

**Vérifié pendant la carte**, en lecture seule :
- **Provenance réelle de S4d1** (`prov.json` du PipelineRun `s4d-deb-1`, vérifiée en D15) : `preparer` émet `CHAINS-GIT_URL`, `CHAINS-GIT_COMMIT`, `FERMETURE_DEB_ARTIFACT_INPUTS`, `FERMETURE_SOURCES_ARTIFACT_INPUTS` et `PACKAGING_ARTIFACT_INPUTS` ; `construire` porte `runtimeClassName` `kata` dans sa spec ; `publier` émet `IMAGE_URL` et `IMAGE_DIGEST`.
- **Provenances des fermetures** (S4b) : celle de la fermeture deb n'a que `prefetch-deb` (résultat `INSTANTANE_ARTIFACT_INPUTS`, InRelease `0584fba3…`) et `publier-fermeture`, **sans git** ; celle de la fermeture applicative a `prefetch-gomod` (version 2) avec `CHAINS-GIT_URL` égal à celui de `preparer-deb`, et `publier-fermeture`.
- **Porte actuelle** : `_construction` ne connaît que `construire-image`, `_preparation` que `preparer-entrees`, `_fermetures` ne lit que `FERMETURE_ARTIFACT_INPUTS`, et `_prefetch` exige `prefetch-gomod`. Sur la provenance de S4d1, `construction_kata` et `fermeture_plateforme` réussissent donc à vide. `trusted_task` voit les trois tâches, toutes dans la liste revue.
- **Contrôle 9 (horodatage)** : le CronJob de la 08 parcourt tous les dépôts sous `builds/`, donc `builds/sample-app-deb`. Prédiction à mesurer, pas un fait.
- **Contrôles 6 et 7** : `vsa.sh` lit `builds/vsa/sample-app-deb` et `scan-verifier.sh` lit `builds/scan/sample-app-deb`. Les deux sont vides : la porte refuse le deb aujourd'hui, en échec fermé.
- **syft 1.38** (`syft cataloger list`, hors réseau) : `deb-archive-cataloger` n'a pas l'étiquette `image`, il ne tourne donc pas par défaut sur `oci-dir:`. Il ne lirait de toute façon que les métadonnées déclarées du deb, pas les modules Go du binaire. Un scan utile du deb suppose d'extraire `data.tar`, puis `syft dir:` : à mesurer.
- **Replay (brique 10)** : FIN_BUILD + 24 h, domaine séparé, VM `sc-replay` sans sbuild ni mmdebstrap. Rejouer le deb demanderait une installation de paquets dans cette VM.

**Forme proposée de la règle étendue** (`porte.rego`), chaque point avec ses tests :
1. **Kata** : `_construction` reconnaît `construire-deb`, par son nom et par le dépôt de son bundle, sur le modèle de `construire-image`.
2. **Fermetures typées par le nom du résultat** :
   - `FERMETURE_DEB_ARTIFACT_INPUTS` n'est prouvée que par la forme deb : exactement `prefetch-deb` et `publier-fermeture`, toutes deux revues, sujet et `IMAGE_URL`/`IMAGE_DIGEST` égaux, sans git ;
   - `FERMETURE_SOURCES_ARTIFACT_INPUTS`, comme l'actuel `FERMETURE_ARTIFACT_INPUTS`, n'est prouvée que par la forme gomod, avec `CHAINS-GIT_URL` égal à celui de la préparation.

   Un test « fermetures permutées » doit être refusé.
3. **Préparation complète** : `preparer-deb` exige les deux types, chacun présent et prouvé. La règle actuelle ne refuse que si aucune fermeture n'est lue. Tests : résultat deb absent, résultat sources absent.
4. **Appariement** : une provenance qui contient `construire-deb` sans `preparer-deb` est refusée. Le même appariement pour `construire-image` ⇒ `preparer-entrees` changerait la voie image : question 2.
5. **Hors du jugement, à inscrire comme dette** :
   - `PACKAGING_ARTIFACT_INPUTS`, poussé depuis l'hôte sous `entrees/`, sans provenance de la plateforme, comme `web/dist` dans la voie image ;
   - la provenance de l'image de build `sbuild-debian13` : son digest n'est revu qu'à travers `taches.yml`, comme image d'étape de `construire-deb`.

**Vérification prévue** (prédictions commitées avant tout lancement) :
- **Sur l'hôte, sans accord** : `ec opa check` et `ec opa test` ; les 21 tests actuels de `porte_test.rego` gardés ; fixtures deb tirées des vraies provenances de S4d1 et de S4b, pas d'une forme imaginée ; mutations sur le modèle de `g5_regles` de la 07a (chaque condition retirée tour à tour fait échouer au moins un test) ; règle neuve évaluée sur l'énoncé réel de S4d1 (levier d).
- **Dans le cluster, sous accord nommé** :
  - mise à jour de la ConfigMap `porte`, commune aux deux voies ;
  - Job de la porte sur `builds/sample-app-deb@sha256:039949f9…`. Prédiction : `ec` en succès, sans violation, `trusted_task.tagged` en avertissement comme pour sample-app ; horodatage complet ; VSA et scan refusés. `@slsa3` n'a jamais jugé un artefact dont la seule couche contient un `.deb`. Les règles `slsa_source_correlated`, qui refusent une provenance sans source (`c7-sans-scan`, même journal), devraient passer : la provenance de S4d1 nomme le commit. Si une règle de la collection refuse le deb, je m'arrête et je reviens avec la règle et son motif, sans l'exclure ;
  - Job de la porte sur l'image sample-app, en non-régression. Prédiction : verdict identique au dernier archivé pour l'image réelle (`c7-reelle` dans `preuves-h5-controle7.log` de la 08, 07/11/2026 : succès, `trusted_task.tagged`, horodatage, VSA et scan admis).
- **Témoins négatifs**, par des énoncés modifiés évalués sur l'hôte : `construire-deb` hors Kata, fermeture deb absente, fermetures permutées.

**Accords à prévoir** : la mise à jour de la ConfigMap (écriture dans le cluster) ; le script de S4d2 (neuf, ou `s4d.sh` étendu), qui appelle `juger` de la 08 ; toute modification de `politique.sh` ou de `porte-job.yaml`, accord à part.

**Effort** : la règle, ses tests, la ConfigMap et les deux jugements tiennent dans le bas de la fourchette de S4d2 (0,5 jour). Les contrôles 6 et 7 du deb n'y tiennent pas :
- le mode deb du scanner (07a) est un script modifié, avec une mesure à faire, soit 0,5 à 1 jour ;
- le replay du deb (brique 10) demande une installation dans la VM, plus l'attente de 24 h, soit 1 à 2 jours.

Avec eux, S4d2 dépasserait sa fourchette, sans approcher le seuil de la brique (4 pw ; elle en est à environ 0,4 pw).

**Questions au propriétaire**
1. **Découpage.** S4d2a : la règle étendue et le jugement du deb, contrôles 6 et 7 en refus (échec fermé), avant S4d3. Les contrôles 6 et 7 du deb passent dans un jalon séparé, après S4d3 ou avec S5. **Ma recommandation** : la porte ne réussit plus à vide sur le deb, et rien n'est publié tant que 6 et 7 refusent.
2. **Appariement dans la voie image** (`construire-image` ⇒ `preparer-entrees`) : l'ajouter en S4d2a, avec la non-régression sur sample-app, ou le laisser hors périmètre. **Ma recommandation** : le laisser hors périmètre et l'inscrire comme dette, pour que S4d2a ne change pas le comportement de la voie image.
3. **Contrôle 7 du deb** : un mode deb du scanner (extraction de `data.tar`, puis `syft dir:`, à mesurer d'abord), ou un écart à l'ADR 0000 §4 pour le deb. Rien n'est à trancher avant le jalon séparé, si la question 1 est retenue.
4. **Contrôle 6 du deb** : un replay du deb dans le domaine de la brique 10 (installation de sbuild ou de mmdebstrap dans `sc-replay`, sous ton accord), ou un écart à l'ADR. Même remarque.

## Additif du 11/11/2026, 20:17 UTC : décision S4d2a, préparation à sec

**Décision du propriétaire** (11/11/2026, 20:08:42 UTC) : « Oui, S4d2a ». S4d2a étend la porte à la voie deb avant S4d3. Les contrôles 6 et 7 du deb passent dans un jalon séparé ; d'ici là, ils refusent le deb (échec fermé). Les questions 2 à 4 n'ont pas reçu de réponse. Pour la 2, j'applique ma recommandation, qui ne change rien : la voie image n'est pas appariée. Les questions 3 et 4 attendent le jalon séparé. Ce n'est un accord pour aucune mesure ni aucune écriture.

**Préparé, rien lancé** :
- `porte.rego` de la 08 : Kata pour `construire-deb` ; fermetures typées par le nom du résultat ; préparation complète ; règle neuve `preparation_appariee`.
- `porte_test.rego` : 18 tests de la voie deb, avec les digests et les noms de résultats des provenances réelles de S4d1 et de S4b.
- [`s4d2.sh`](s4d2.sh), qui ajoute trois étapes :
  - `regle` : tests et mutations, sur l'hôte ;
  - `reel` : règles évaluées sur les provenances réelles du deb et de sample-app, et témoins, sur l'hôte avec lecture anonyme de Zot ;
  - `porte` : ConfigMap et trois Jobs de la porte, dans le cluster.
- [Prédictions E1 à E11](resultats/s4d2-predictions.md).

**Dette inscrite** :
- l'artefact de packaging, poussé depuis l'hôte, n'est pas jugé par la porte ;
- la provenance de l'image de build `sbuild-debian13` non plus ;
- la voie image n'est pas appariée (`construire-image` et `preparer-entrees`).

## Additif du 11/11/2026, 20:24 UTC : S4d2a tenu

**S4d2a tenu**, de la carte (20:03 UTC, sur « continue ») au troisième passage de `porte` (20:23:28 UTC). Les prédictions E1 à E11 sont tenues ([prédictions et résultats](resultats/s4d2-predictions.md)). **La porte de release juge désormais le deb** :
- Kata est exigé pour `construire-deb` ;
- les deux fermetures doivent être prouvées par leurs pipelines de la plateforme, chacune selon sa forme ;
- `preparer-deb` est appariée à `construire-deb`.

Sur `builds/sample-app-deb@sha256:039949f9…`, `ec` réussit, sans violation, avec les cinq règles du PoC parmi les succès et un horodatage complet. Le Job de la porte échoue, comme décidé : VSA et scan refusent le deb. L'image sample-app garde le verdict du 07/11.

**Décisions et accords du jalon** :
- « Oui, S4d2a » (20:08:42 UTC) ;
- « Oui, lance-les » (`regle` et `reel`) ;
- « Oui, relance-la » (`regle`, test corrigé) ;
- trois fois « Oui, lance porte » ou « Oui, relance porte ». Le deuxième accord porte aussi sur le déploiement de la liste versionnée.

**Écarts** :
- **Un test sur 39** ne couvrait pas la correspondance par dépôt du bundle : la bibliothèque prend le nom de la tâche dans le label `tekton.dev/task`. Le test est corrigé, la règle n'a pas changé.
- **La liste revue déployée** était celle du 03/11 (`b1e5ef4`) : les cinq tâches des briques 06 n'avaient jamais été déployées. La carte de 20:07 UTC décrivait un « succès à vide » de la porte. C'était vrai des règles `porte.*`, faux de la porte entière : `trusted_task` refusait déjà le deb (E8 révisée, puis mesurée).
- **Deux défauts du script** : le contrôle de la liste, puis `diff` dans un tube. Les deux arrêts ont eu lieu avant toute écriture.
- **Une erreur d'heure**, corrigée par une ligne datée.

**Dette inscrite** :
- l'artefact de packaging, poussé depuis l'hôte, n'est pas jugé par la porte ;
- la provenance de l'image de build `sbuild-debian13` non plus ;
- la voie image n'est pas appariée ;
- le commentaire de `construire-deb` dans `taches.yml` de la 08 est devenu faux. Il est corrigé par une note datée, sans réécrire le fichier.

**Durée** : environ 20 minutes de travail, de 20:03 à 20:24 UTC, au bas de la fourchette de S4d2 (0,5 à 1,5 jour). La brique reste à environ 0,4 pw.

**Suite, selon le découpage décidé** : S4d3 (second trigger et second rattrapage), puis S5. Les contrôles 6 et 7 du deb passent dans un jalon séparé ; les questions 3 et 4 de la carte restent ouvertes.

## Additif du 11/11/2026, 20:33 UTC : carte de S4d3, à sec, rien lancé

**Carte de S4d3**, préparée sur « continue » : rien n'a été lancé ni lu dans le cluster. Objet : brancher le deb sur les deux chemins de déclenchement de la 08, la livraison du webhook de Forgejo et le rattrapage.

**Ce que montre le dépôt**
- **EventListener `forgejo`** (`politique/declencheurs.yaml` de la 08, J6) : un seul trigger en ligne, `sample-app-push`, avec ses intercepteurs. L'intercepteur github vérifie le HMAC du secret `forgejo-webhook` et l'événement push ; le filtre CEL vérifie la branche main, le dépôt et un commit de 40 caractères. Selon le dépôt, le gabarit en service est celui de la bascule de J8 (`politique/gabarit-sample-app.yaml`) ; ce n'est pas relevé dans le cluster.
- **Rattrapage** (`politique/rattrapage.yaml`, `politique/rattrapage/main.go`) : chaque minute, un CronJob lit la tête de main et crée `<gabarit>-<commit>` depuis une seule TriggerTemplate (variable `GABARIT`). Son Role ne lit que `sample-app`. `main.go` exige :
  - les paramètres `commit` et `depot`, et eux seuls ;
  - une seule ressource : un PipelineRun `tekton.dev/v1` dans builds, nommé `<gabarit>-<commit>`.
- **La pipeline `sample-app-deb`** prend exactement `commit` et `depot` (`s4d.sh`, `pr_json`). `main.go` sert donc sans changement pour un gabarit `sample-app-deb` : ni nouveau binaire, ni nouvelle image.
- **Triggers v0.37.2**, lu dans le code (`pkg/apis/triggers/v1beta1/event_listener_types.go`, `pkg/sink/sink.go`) :
  - `spec.triggers` est une liste atomique ;
  - avec un `labelSelector`, l'EventListener ajoute à ses triggers en ligne les objets Trigger de son espace qui portent ces labels ;
  - chaque trigger exécute ses propres intercepteurs (`t.Spec.Interceptors`), dans l'espace du trigger.

**Forme proposée**
1. **`politique/declencheurs.yaml` (08)** : l'EventListener reçoit un `labelSelector`. C'est la seule modification d'un fichier de la 08, relue à part. Elle va dans le dépôt, pas dans un simple apply de la 06 : `politique.sh declencheurs` réapplique ce fichier en server-side, et un sélecteur posé d'ailleurs disparaîtrait au rejeu. Ce serait la dérive de S4d2a, construite d'avance.
2. **`deb/declencheur.yaml` (06)**, appliqué par l'étape de S4d3 :
   - **TriggerTemplate `sample-app-deb`** : paramètres `commit` et `depot`, PipelineRun `sample-app-deb-$(tt.params.commit)` dans builds. Elle reprend la forme de `pr_json` : workspace `sortie` en PVC, `taskRunTemplate`, Kata pour la seule tâche `construire` (sinon `porte.construction_kata` refuse). Bundle : `pipeline.ref` de S4d1 ;
   - **Trigger `sample-app-deb-push`**, labellisé pour l'EventListener, avec ses propres intercepteurs github et CEL, recopiés de `sample-app-push`. Sans eux, n'importe quel POST au NodePort lancerait une construction du deb, avec un commit et un dépôt tirés d'un corps non signé ;
   - **compte `rattrapage-deb`** : un Role qui ne lit que le gabarit `sample-app-deb`, et un RoleBinding dans builds (get et create de PipelineRuns) ;
   - **CronJob `rattrapage-deb`** : même image épinglée, `GABARIT=declencheurs/sample-app-deb`, label `app: rattrapage` (la NetworkPolicy existante le couvre). Il est appliqué suspendu. Avec un compte à part, l'audit de l'API distingue les deux rattrapages.
3. **Étape `s4d3.sh`**, sur le modèle de `preuves.sh bascule` :
   - essai à blanc du gabarit ;
   - chemin 1 : livraison de Forgejo ;
   - chemin 2 : rattrapage repris ;
   - rejeu de la livraison ;
   - livraisons sans signature et à mauvaise signature (aides `envoyer` et `hmac_corps` de `commun.sh`) ;
   - porte sur le deb.

**Relevé à faire avant les prédictions** (lecture seule ; leçon de S4d2a : l'état déployé se relève pendant la carte) :
- la TriggerTemplate, l'EventListener, le Role et le CronJob `rattrapage` en service, comparés au dépôt, avec l'état de suspension du CronJob ;
- la tête de main dans Forgejo, comparée à `COMMIT` de `s4d.sh` (`6391fd43`) ;
- la présence de `sample-app-6391fd43…`. S'il est absent, le chemin 1 lancerait aussi la construction de l'image : deux constructions Kata en même temps sur sc-build (non mesuré), et des enveloppes de plus sur `builds/sample-app` ;
- les PipelineRuns `sample-app-deb-*` existants ;
- le bundle de la pipeline deb dans Zot, comparé à `pipeline.ref` de S4d1.

**Prédictions esquissées**, à écrire et commiter après le relevé :
- **à blanc** : le PipelineRun rendu est admis au nom de `el-forgejo` et de `rattrapage-deb` ;
- **chemin 1** : une seule création, par `el-forgejo`. Le PipelineRun réussit, avec `construire` sous Kata sur sc-build ; `IMAGE_DIGEST` vaut `039949f9…` (mêmes entrées qu'en S4d1) ; Chains le signe. Le trigger de l'image répond « already exists » si son PipelineRun existe ;
- **chemin 2** : une création par `rattrapage-deb`, même spec, autre UID. Le rattrapage de l'image répond PRESENT ;
- **rejeu** : « already exists », même UID ;
- **livraison sans signature ou à mauvaise signature** : refusée par l'intercepteur github du trigger deb, aucun `sample-app-deb-*` créé ;
- **porte sur le deb** :
  - `ec` réussit sans violation, et la provenance jugée est celle du chemin 2 ;
  - VSA et scan refusent, comme décidé ;
- **sample-app** : enveloppes et verdict inchangés, si son PipelineRun existe ;
- **noms des TaskRuns** : `sample-app-deb-<commit>` a 55 caractères. Avec `-preparer` ou `-construire`, le nom d'un TaskRun enfant dépasse 63 caractères, et Tekton le raccourcit avec un hash ; `-publier` tient juste. Les scripts sélectionnent par label.

**Limites et effets croisés**
- **Commits incompatibles** : le trigger construit tout commit de main, avec les fermetures et l'artefact de packaging épinglés dans la pipeline signée.
  - Un commit qui change `go.mod` échoue dans `preparer-deb` : l'échec est fermé.
  - Un changement de `debian/` dans le dépôt n'est pas pris en compte : le packaging vient de l'artefact.
  - Dette à inscrire.
- **Rejeux isolés de la 08** : après S4d3, rejouer une étape de la 08 qui pousse des commits d'essai lancera aussi la construction du deb pour ces commits, par l'EventListener et par `rattrapage-deb`. C'est le cas de `politique.sh rattrapage` de J6, avec ses commits c1 et c2. Un rejeu depuis zéro n'est pas touché, puisque la 08 passe avant la 06. Proposition : l'écrire comme limite, et donner à l'étape de S4d3 un moyen de suspendre `rattrapage-deb`.
- **Deux constructions Kata simultanées** sur sc-build, après un vrai push : non mesurées dans S4d3.

**Effort** : environ 0,5 jour, comme estimé dans la carte de S4d.

**Questions au propriétaire**
1. **La forme.**
   - Elle comprend : un Trigger à part, sélectionné par label, avec ses propres intercepteurs ; un `labelSelector` ajouté à l'EventListener dans `declencheurs.yaml` de la 08 ; un compte `rattrapage-deb` ; `main.go` et l'image du rattrapage inchangés.
   - Alternative : un second trigger en ligne dans `declencheurs.yaml`. C'est plus simple, mais la 08 référencerait un gabarit de la 06, absent tant que la 06 n'est pas rejouée.
   - **Ma recommandation** : la forme proposée.
2. **Le relevé en lecture seule**, avant d'écrire les prédictions.
3. **La limite des commits incompatibles** avec les fermetures épinglées, inscrite en dette.

## Additif du 11/11/2026, 20:41 UTC : décision S4d3, relevé et préparation à sec

**Décision du propriétaire** (11/11/2026, 20:35:01 UTC) : « Oui, les deux ». La forme de la carte est retenue, et le relevé en lecture seule est fait avant les prédictions. La question 3, sur la limite des commits incompatibles, n'a pas reçu de réponse. J'applique ma recommandation : la limite est inscrite en dette.

**Relevé** (20:36:05 à 20:36:28 UTC, [`s4d3-releve-1.log`](resultats/s4d3-releve-1.log), [`s4d3-releve-2.log`](resultats/s4d3-releve-2.log)) :
- l'état déployé des déclencheurs et du rattrapage est celui du dépôt ;
- la tête de main est `6391fd43…`, et `sample-app-6391fd43…` existe : le chemin 1 ne relancera pas la construction de l'image ;
- aucun PipelineRun `sample-app-deb-*` n'existe.

Le premier passage montrait de faux écarts, dus à ma comparaison (documents multiples lus sans `jq -s`). Le second passage les corrige.

**Préparé à sec** : rien n'est lancé.
- `politique/declencheurs.yaml` (08) : un `labelSelector` sur l'EventListener. C'est la seule modification d'un fichier de la 08 ; elle est à relire.
- [`deb/declencheur.yaml`](deb/declencheur.yaml) : gabarit `sample-app-deb`, Trigger `sample-app-deb-push`, compte, droits et CronJob `rattrapage-deb` (appliqué suspendu).
- [`s4d3.sh`](s4d3.sh), cinq étapes :
  - `prealables` : lecture seule ;
  - `deployer` : écrit dans le cluster, de façon réversible ;
  - `chemins` : écrit dans le cluster et dans Zot, par Chains ;
  - `porte` ;
  - `retirer`, au choix du propriétaire seulement.
- [Prédictions T1 à T14](resultats/s4d3-predictions.md).

Contrôles sur l'hôte : `bash -n` et `shellcheck` sans remarque. Je n'ai pas pu relire la règle de troncature des noms des TaskRuns : T9 est donc en confiance moyenne.

## Additif du 11/11/2026, 21:05 UTC : S4d3 tenu

**S4d3 tenu**, de la carte (« continue », 20:27:23 UTC) au bilan (21:04:32 UTC) : T1 à T14 ([prédictions et résultats](resultats/s4d3-predictions.md)).

**Le deb de sample-app est branché sur les deux chemins de déclenchement de la plateforme** :
- **Livraison du webhook de Forgejo** : l'EventListener `forgejo` sélectionne désormais par label le Trigger `sample-app-deb-push`, qui fait son propre contrôle du HMAC. Trois livraisons mal signées ont donné six refus et aucun PipelineRun.
- **Rattrapage** : le CronJob `rattrapage-deb` utilise la même image et le même binaire que celui de l'image, sous son propre compte. Il ne peut lire que le gabarit `sample-app-deb`.
- **Résultat** : par chacun des deux chemins, `sample-app-deb-6391fd43…` construit le deb `039949f9…`, avec la spec de S4d1 et `construire` sous Kata. Chains le signe.
- **Porte** : elle juge la provenance la plus récente, sans violation ; l'horodatage couvre 8 enveloppes sur 8. VSA et scan refusent, comme décidé. sample-app est inchangé.

**Décisions et accords du jalon** (lignes datées dans les commits) :
- « Oui, les deux » (20:35:01 UTC) : la forme, et le relevé avant les prédictions ;
- puis les lancements : « Oui, lance-les », « Oui, relance-les », « Oui, lance-les » (`retirer`, `prealables`, `deployer`), « Oui, lance-les » (`chemins`, `porte`).

**Écarts** :
- **Deux défauts de mes comparaisons** :
  - deux défauts du serveur non retirés ;
  - les ressources, retirées à tort.

  Le second a caché le refus du CronJob par `limites-obligatoires` de la 08c : la 08c pose les limites de `rattrapage` par patch, et elles sont absentes de `rattrapage.yaml`.
- **Correction** : les limites de `limites.tsv` sont ajoutées au CronJob du deb. Ensuite, `retirer` puis un nouveau déploiement.
- Aucun arrêt n'a touché Zot.

**Dette et limites inscrites** :
- le trigger construit tout commit de main avec les fermetures et le packaging épinglés. Un commit qui change `go.mod` échoue dans `preparer-deb` (échec fermé), et `debian/` vient de l'artefact ;
- rejouer isolément une étape de la 08 qui pousse des commits d'essai lance aussi le deb. Remèdes : `s4d3.sh retirer`, ou suspendre `rattrapage-deb` ;
- deux constructions Kata simultanées sur sc-build ne sont pas mesurées ;
- `durcissement.sh` de la 08c suspend `rattrapage` pendant ses redémarrages, mais pas `rattrapage-deb`.

**Durée** : environ 40 minutes, de 20:27 à 21:05 UTC, sous l'estimation de S4d3 (environ 0,5 jour). La brique reste à environ 0,4 pw.

**Suite, selon le découpage décidé** : S5 (archive altérée, hash faux, InRelease altéré). Les contrôles 6 et 7 du deb attendent leur jalon séparé ; les questions 3 et 4 de la carte de S4d2 restent ouvertes.

## Additif du 11/11/2026, 21:13 UTC : carte de S5, à sec (rien lancé, rien écrit dans Zot)

**Inventaire de S5**, relevé dans ce README :
- M5 de la 05, repris en S5 (tableau des jalons) : fermeture altérée, sortie réseau pendant le build, pod privilégié hors Kata, rejeu de zéro ;
- note datée de 23:40 UTC (10/11) : hash faux passé à `apt-helper`, `.deb` altéré dans le miroir, InRelease au mauvais sha256 ;
- coupure du réseau par sbuild lui-même, « laissée à S5 » (bilan de S3) ;
- vérification de la signature de l'InRelease par apt, encore déduite (réserve de A7, S4a).

La comparaison bit à bit de la nouvelle voie, annoncée « en S4d ou en S5 », est déjà faite : S4d1 a donné deux fois `039949f9…`, avec le deb `0b489d43…`, puis S4d3 deux fois de plus. Elle ne revient pas dans S5.

**Ce que chaque test mesure.** Le piège est de compter comme mesurée une barrière que le test n'atteint pas. Plusieurs couches se suivent :
- `prefetch-deb` : `apt-helper` reçoit le sha256 attendu, puis le shell recalcule le sha256 (`tele`) ;
- `construire-builder` : la tâche revérifie le miroir (l. 109 et suivantes) **avant** mmdebstrap, puis apt vérifie l'InRelease et les paquets ;
- `preparer-deb` : la fermeture deb est confrontée au verrou, puis `construire-deb` revérifie chaque sha256. **apt ne protège pas ici** : sbuild prend les paquets par `--extra-package`, sans aucun contrôle de hash, comme les paquets natifs de yarn dans la 03.

| # | Test | Mécanisme | Barrière qui doit refuser | Témoin accepté | Écriture dans Zot |
|---|---|---|---|---|---|
| N1 | Hash faux | TaskRun isolé de `prefetch-deb` (bundle de la liste revue), un paquet au sha256 faux | `apt-helper` (« téléchargement refusé ») ; si c'est « sha256 différent », c'est le shell qui rattrape et A4 reste non mesurée | même TaskRun, bon sha256 | non |
| N2 | InRelease au mauvais sha256 | même TaskRun, paramètre `inrelease` faux | `apt-helper`, sur l'épinglage ; apt ne lit jamais l'InRelease ici, donc A7 n'est pas levée | N1 témoin | non |
| N3 | Miroir altéré après le prefetch | `prefetch-deb` complet sur un PVC, copies altérées par un pod runc (un `.deb`, l'InRelease), puis `construire-builder` sous Kata sur chaque copie | revérification de la tâche, avant mmdebstrap | `construire-builder` sur la copie intacte, digest attendu `749d746c…` (rien n'est publié) | non |
| N4 | Signature de l'InRelease et hash des paquets par apt seul (réserve de A7) | pod d'essai runc (amorce, UID 65532) : `apt-get update` puis téléchargement depuis `file://`, sans `trusted=yes`, sur des copies qui contournent l'épinglage | apt : signature invalide ; hash différent | miroir intact accepté | non |
| N5 | Fermeture deb altérée | TaskRun isolé de `preparer-deb` sur deux fermetures altérées (un `.deb` modifié ; un fichier de plus dans le pool) | confrontation au verrou : « paquet différent du verrou » ; « pool : 163 fichiers, 162 dans le verrou » | même TaskRun sur la vraie fermeture `bb7599a2…` | **oui** (question 2) |
| N6 | Coupure du réseau par sbuild | pod d'essai Kata (image de build, UID 1000), hors de `construction-deb-sans-sortie` : connexion TCP à Zot depuis le pod, puis depuis `debian/rules` d'un paquet minimal construit par sbuild `--chroot-mode=unshare` | sbuild (espace de noms réseau réduit à `lo`) | la même connexion depuis le pod réussit | non |
| N7 | Pod privilégié hors Kata | TaskRun isolé de `construire-deb` sans `runtimeClassName`, sur le PVC du témoin de N5 | Pod Security `restricted` (403) avant Kyverno, puis `PodAdmissionFailed`, comme au test 4 de la 08 | même TaskRun sous Kata : deb `0b489d43…`, digest `039949f9…` (rien n'est publié) | non |

N6 mesure la seule coupure par sbuild. La coupure au niveau du pod est déjà mesurée à chaque construction, par les témoins de `construire-deb`. S5 ne compte pas l'une pour l'autre.

**Invariance** : avant et après S5, la porte garde le même verdict et le même nombre d'enveloppes : 8 sur le deb, 28 sur sample-app. Chains stocke en `oci` sur le sujet. Aucun TaskRun de S5 ne publie d'image : il n'a donc pas de sujet. Le précédent de S4d3 (4 enveloppes de plus par PipelineRun de trois TaskRuns) ne dit pas lesquelles. C'est une prédiction, à mesurer.

**Mécanisme, lu dans le dépôt** : la règle `tekton-references` (`politique/admission.yaml`) admet un TaskRun qui référence un bundle `tekton/tasks/…@sha256` avec le compte `build` et un workspace PVC ou emptyDir. Les quatre tâches sont déjà signées et revues. Il n'y a donc aucune nouvelle signature ni revue de `taches.yml`.

**À vérifier au relevé, avant toute prédiction ferme** :
- le label `tekton.dev/task: prefetch-deb` sur le pod d'un TaskRun isolé : sans lui, `prefetch-deb-sortie` ne s'applique pas et le téléchargement échoue ;
- un `--dry-run=server` de chaque objet neuf (leçon de S4d3) ;
- les valeurs des paramètres, prises dans les pipelines signées et non recopiées à la main.

**Effets à connaître** :
- environ 200 Mo téléchargés depuis l'instantané, comme en S4a ;
- deux PVC et trois pods dans `builds`, retirés à la fin ;
- rien n'est poussé sur Forgejo : un commit sur main lancerait les deux triggers ;
- seule écriture possible dans Zot : N5 en (a).

**Rejeu de zéro.** `rejeu.sh` de la 08 date du 05/11/2026. Il n'a aucune étape de la 06, ni de la 08c, ni de la 08d (relevé par grep). Rejouer de zéro aujourd'hui veut dire :
- intégrer d'abord tout ce qui a été fait depuis, sous RKE2 ;
- recréer les VM.

Ce travail dépasse très probablement 2× l'estimation de S5 : la règle de décision s'applique.

**Questions au propriétaire**
1. **Découpage.** Ma recommandation : **S5a**, les tests N1 à N7, maintenant ; **S5b**, le rejeu de zéro, en jalon de plateforme à part, avec sa propre carte et sa propre estimation. Rien ne change dans `rejeu.sh` avant ta réponse.
2. **Fermeture altérée (N5).**
   - (a) Deux fermetures altérées poussées depuis l'hôte sous `entrees/sample-app-deb/`, avec le compte `poc-ecriture`, comme F3 de la 03. La fermeture compte 167 couches, une par fichier : chaque variante n'ajoute qu'un blob et un manifeste. L'écriture est définitive, et chaque poussée demande un accord nommé. **Ma recommandation.**
   - (b) Un pod d'essai rejoue le contrôle sur une copie altérée en local, sans écriture. Il teste le script, pas la tâche signée.
3. **Pods d'essai N4 et N6.** Ma recommandation : les garder dans S5a, car ce sont les deux propriétés encore déduites. Sinon, la réserve de A7 et la coupure par sbuild restent ouvertes et inscrites.

**Estimation de S5a** : une demi-journée, sur le modèle de S4d3. La brique est à environ 0,4 pw.

## Additif du 11/11/2026, 21:25 UTC : décision sur S5, préparation de S5a à sec

**Décision du propriétaire** (21:14:51 UTC) : « Oui, les trois ».
- **Découpage** : S5a, les tests négatifs N1 à N7 ; S5b, le rejeu de zéro, en jalon de plateforme à part. Rien ne change dans `rejeu.sh`.
- **Fermeture altérée** : poussée dans Zot sous `entrees/sample-app-deb/fermeture-alteree`, avec un accord nommé à part.
- **Pods d'essai N4 et N6** : gardés dans S5a.

Ce n'est un accord pour aucun lancement.

**Préparé** : [`s5.sh`](s5.sh) et les [prédictions](resultats/s5-predictions.md) P1 à P19.

Les étapes, dans l'ordre :
- `prealables` : lecture et admission à blanc côté serveur ;
- `zot` : la seule écriture ;
- `prefetch`, `miroir`, `fermeture` (après `zot`), `kata`, `sbuild` ;
- `porte` : contrôle d'invariance ;
- `retirer`.

Les paramètres sont pris dans les pipelines signées, exportées de Zot.

**Contrôles sur l'hôte** (hors ligne) :
- **Fermeture intacte** : la copie de S4b, poussée en layout local par la commande de `publier-fermeture`, redonne exactement `bb7599a2…`.
- **Fermetures altérées** : `a549729d…` (un paquet modifié) et `b27225cf…` (un fichier en trop) n'ajoutent chacune qu'une couche.
- **Paquet témoin de N6** : son `debian/rules` s'exécute.
- **Objets** : le rendu des 17 objets est conforme.

**Effets à connaître** :
- **Zot** : deux manifestes et deux blobs (1200 et 34 octets), définitifs.
- **Instantané** : environ 200 Mo téléchargés, comme en S4a.
- **Kata** : deux constructions sur sc-build, l'une après l'autre (`construire-builder` puis `construire-deb`, 6 Gio chacune), sans publication.
- **Cluster** : 2 PVC, 2 pods d'essai et 13 TaskRuns, retirés par `retirer`.
- **Forgejo** : rien n'y est poussé.

## Additif du 11/11/2026, 21:52 UTC : S5a tenu

Tests négatifs N1 à N7 de 21:25:12 à 21:50:33 UTC ([prédictions et résultats](resultats/s5-predictions.md)). **Toutes les barrières prédites refusent, et chaque témoin est accepté. Deux propriétés qui n'étaient que déduites sont désormais mesurées.**

| # | Altération | Barrière qui refuse | Témoin accepté |
|---|---|---|---|
| N1 | Hash faux d'un paquet | `apt-helper` dans `prefetch-deb`, avant le shell : **A4 mesurée** | même paquet, bon hash |
| N2 | InRelease au mauvais sha256 | `apt-helper`, sur l'épinglage | N1 |
| N3 | `.deb` ou InRelease altéré dans le miroir | revérification de `construire-builder`, avant apt | miroir intact : image `749d746c…`, celle de S4a |
| N4 | les mêmes, apt seul | sqv : « Message has been manipulated » ; apt : « Hash Sum mismatch » : **réserve de A7 levée** | miroir intact |
| N5 | fermeture deb altérée (paquet modifié, fichier en trop) | confrontation au verrou de `preparer-deb` ; oras tire sans rien voir | vraie fermeture |
| N6 | connexion réseau pendant la construction | sbuild `--chroot-mode=unshare` : seule `lo`, échec immédiat | même connexion depuis le pod : réussie |
| N7 | `construire-deb` sans Kata | Pod Security `restricted`, `PodAdmissionFailed`, aucun pod | sous Kata : deb `0b489d43…`, `039949f9…` |

**Invariance** :
- aucune enveloppe nouvelle sur le deb, sample-app, la fermeture ni l'image de build ;
- la porte garde les verdicts de S4d3 ;
- Chains annote les TaskRuns isolés, mais n'écrit rien dans Zot sans sujet.

**Décisions et accords du jalon** :
- « Oui, les trois » (21:14:51 UTC) : découpage S5a/S5b, poussée dans Zot, pods d'essai ;
- « Oui, lance S5a » ;
- « Oui, les deux » : poussée dans Zot et relance de `sbuild` ;
- « Oui, relance la suite ».

**Écarts** : trois erreurs de mon script ont fait relancer `sbuild` deux fois et `fermeture` une fois, toujours en échec fermé :
- le journal de sbuild était lu sur la sortie au lieu du fichier `.build` ;
- la cible `build` n'était pas appelée par `dpkg-buildpackage -b` ;
- les variables de la pipeline n'étaient pas résolues dans un TaskRun isolé.

S'y ajoutent une extraction fausse dans une mesure et deux libellés mal prédits. **Leçon** : un contrôle sur l'hôte prend les valeurs réelles et rejoue l'outil réel.

**Écrit dans Zot, définitif** : `entrees/sample-app-deb/fermeture-alteree`, tags `paquet-modifie` (`a549729d…`) et `paquet-en-trop` (`b27225cf…`).

**Limites** :
- **Dépendances de sbuild** : apt ne protège pas les dépendances de build, que sbuild prend par `--extra-package`. La confrontation au verrou est la seule barrière, doublée par `construire-deb`.
- **TaskRuns isolés** : la plateforme admet un TaskRun isolé d'une tâche signée, avec des paramètres libres. La porte ne juge que les PipelineRuns, et un TaskRun isolé ne publie rien.

**Durée** : environ 40 minutes, de la carte (21:13 UTC) au bilan. La brique est à environ 0,45 pw, sous l'estimation de 2 pw.

**Suite** : S5b, le rejeu de zéro, est un jalon de plateforme qui demande d'abord d'intégrer la 06, la 08c et la 08d à `rejeu.sh`. Les contrôles 6 et 7 du deb ont leur jalon séparé, et les questions 3 et 4 de la carte de S4d2 restent ouvertes.

## Additif du 11/11/2026, 22:09 UTC : carte de S5b à sec

La carte du rejeu de zéro (S5b) est écrite dans le README de la [08](../08-trust-plane/README.md), section « Rejeu de zéro S5b », puisque c'est un jalon de plateforme. Rien lancé, rien modifié. Bloc 06 proposé : `s1 amorce`, `s4c`, `s4a`, `s4b`, `s4d` (étapes durables seulement), puis `s4d3` avec `PIPE_DEB` lu dans `pipeline.ref` et des compteurs de porte relatifs.

**Correction** : dans `docs/03-validation-briques.md` (commit `afa9bfe`), un « ; » manque avant « S5a de la 06 tenu », à la fin de la phrase de S4d3.

## Additif du 11/11/2026, 23:10 UTC : S5b préparé à sec, NON LANCÉ

Le bloc 06 de `rejeu.sh` comprend `s1 amorce`, `s4c verrou publier`, `s4a prealables taches reseau pipeline`, `s4b prealables taches_deb taches_sources deb sources comparaison` et `s4d reseau taches pipeline`. Il se termine par `s4d3 retirer prealables deployer chemins porte`, où `porte` ne tourne qu'avec `POUSSER_VSA=1`.

Trois changements dans [`s4d3.sh`](s4d3.sh) :
- `PIPE_DEB` est lu dans `pipeline.ref` ;
- les compteurs d'horodatage de la porte sont relatifs ;
- `retirer` purge aussi le PipelineRun deb.

`s5.sh` garde ses valeurs en dur : il n'est pas dans le rejeu.

Détail et prédictions : README de la [08](../08-trust-plane/README.md), section « Rejeu de zéro S5b ».

## Additif du 12/11/2026, 08:39 UTC : carte de S6 (contrôles 6 et 7 du deb), à sec, rien lancé

Rédigée sur « continue » (cadre : préparer sans rien lancer), après relecture de `scanner.sh` et `scan-verifier.sh` (07a), `vsa.sh` (08), `replay.sh` et `politique-replay.md` (10), `deb/construire-deb.yaml`, `rejeu.sh`, `s4d3.sh` et de la consigne de la tâche planifiée du 21/11 ; avis du conseiller. Aucune mesure, aucune écriture hors du dépôt. S6 est le « jalon séparé » décidé en S4d2 (« Oui, S4d2a »).

**Constats, en lecture seule**
1. **Conflit avec S5b.** La porte de [`s4d3.sh`](s4d3.sh) (lignes 343 et 344) et la prédiction C9 de S5b attendent VSA et scan **refusés** pour le deb ; `rejeu.sh` ne rejoue ni scan ni VSA du deb. Si S6 aboutit avant S5b dans le cluster, S5b casse : il faudrait modifier `rejeu.sh` et `s4d3.sh`, et dater une note sur C9.
2. **Contrôle 7, cible unique en dur** :
   - [`plateforme.sh`](../07a-sbom-grype/plateforme.sh), lignes 96 et 114 (`IMAGE`, `DEPOT_SCAN`) ;
   - le CronJob `scan-sample-app` ;
   - le timer de fraîcheur de G8 ([`fraicheur-scan.service`](../07a-sbom-grype/systemd/fraicheur-scan.service), ligne 11 : `DEPOT_SCAN=builds/scan/sample-app`).
3. **Contrôle 7, la fusion masquerait un deb vide.**
   - `analyser` fusionne `syft oci-dir:image` et `syft dir:source`.
   - Sur le deb, syft 1.38 ne lance pas `deb-archive-cataloger` sur `oci-dir:` (relevé de S4d2). La moitié « artefact » serait vide ou presque, tandis que la moitié « source » remplirait le SBOM.
   - Avec `-q` et le code 0, une extraction qui n'a rien lu passerait pour saine.
   - Il faut donc un compte de PURL de l'artefact seul, avec un plancher strictement positif, et un témoin positif sur le modèle de G6.
4. **Contrôle 7, non vérifié** :
   - les catalogueurs actifs sur `dir:` (étiquettes de `syft cataloger list`) ;
   - la compression de `data.tar` dans le vrai `.deb` ;
   - la présence de `ar` et du décompresseur dans l'image `outils-scan`, sans quoi il faut reconstruire l'image, la réépingler et passer un pod d'essai ;
   - le rôle de `distro=` pour un binaire Go (question ouverte, [README de la 07a](../07a-sbom-grype/README.md), ligne 278).
5. **Contrôle 6, l'indépendance d'abord.** [`politique-replay.md`](../10-independent-replay/politique-replay.md) §3 interdit d'exécuter ou de réutiliser l'image de build déclarée : elle est reconstruite dans le domaine. Pour le deb :
   - l'image de build `749d746c` porte sbuild et le chroot ;
   - l'équivalent indépendant est mmdebstrap puis sbuild **dans `sc-replay`**, depuis le miroir de l'instantané et la fermeture deb `bb7599a2`, lien coupé.
6. **Contrôle 6, le code du domaine est propre à la voie image** : `POLITIQUE_COMMIT`, `entrees.py`, `verifier_entrees.py`, `rebuild.sh`, `vsa.py` et `pousser_vsa` (`builds/vsa/sample-app`).
   - La recette du deb viendrait du bundle `construire-deb` (`3726ff0b`).
   - `PASSED` exige que le digest du layout fait main soit égal à `039949f9`. Ce layout est déterministe (`deb/construire-deb.yaml`, lignes 119 à 139 : `tar --mtime=@0`, configuration sans date), donc reconstructible à partir des seuls octets du deb.
7. **Survie au rejeu.**
   - `sc-replay` n'est pas touchée par `rejeu.sh` : elle n'y figure pas, et `virsh list` la montre en cours d'exécution.
   - Zot est remis à zéro. Une VSA du deb faite avant S5b ne revient que par un bundle versionné re-poussé, et seulement si `039949f9` se reproduit (C6, confiance « Moyenne »).
   - Son `inputAttestations` désignerait un bundle horodaté effacé, comme pour la VSA de sample-app : `vsa.sh` ne le lit pas.
   - Le scan est refait par le CronJob.
8. **Tâche planifiée du 21/11.** Elle prédit `builds/**` intacts, et des décisions de suppression seulement dans `builds/scan/sample-app` et `builds/scan/essai-scan`. Un dépôt `builds/scan/sample-app-deb` créé après le 12/11 aurait moins de 336 h le 21/11, donc aucune décision prédite, mais ce dépôt n'est pas prévu par sa consigne. Le plus simple est de n'écrire dans Zot qu'après ce relevé.
9. **Place.** Le scan occupe 3,4 Go sur un nœud de 15 Go (07a). Un second CronJob ne doit pas chevaucher le premier et doit tenir dans les limites de `h5_limites` (08c).

**Découpage proposé**
- **S6a, contrôle 7** :
  1. relevé sur l'hôte, hors réseau (`unshare -rn`), prédictions commitées d'abord : `ar` et compression de `data.tar` sur le vrai `.deb` de `$W/s3-06/build-1` ; `syft dir:` 1.38 sur `data.tar` extrait (nombre de PURL, types, `distro=`) ; grype 0.104.1 avec la base de G0 ; catalogueurs actifs ; outils présents dans `outils-scan` ;
  2. mode deb de `scanner.sh` : extraction, compte de l'artefact seul, plancher ;
  3. CronJob `scan-sample-app-deb` décalé, timer de fraîcheur sur deux dépôts, témoin positif ;
  4. porte sur le deb : scan `ok` attendu.
- **S6b, contrôle 6** :
  1. relevé : versions de mmdebstrap et de sbuild candidates dans `sc-replay` ; place et mémoire de la VM (20 Go, 6 Gi) ; heure `finishedOn` de la provenance retenue (délai de 24 h) ;
  2. installation dans `sc-replay`, sous accord nommé ;
  3. code du domaine pour la voie deb, transport, rebuild lien coupé, VSA signée dans la VM ;
  4. push de la VSA, avec un accord à chaque push.

**Effort**
- S6a : 0,5 à 1 jour (estimation de S4d2).
- S6b : 2 à 3 jours, au-dessus des 1 à 2 jours de S4d2, puisqu'il faut reconstruire le chroot dans le domaine.
- Total imputé à la 06 : 0,5 à 0,8 pw. Elle passerait d'environ 0,45 pw à 1 à 1,25 pw, sous l'estimation de 2 pw.
- Si l'effort est imputé aux briques d'origine : la 10 est estimée à 2 pw, mais je n'ai pas relevé son consommé ; je n'ai trouvé aucune estimation dans le README de la 07a.

**Questions au propriétaire**
1. **Ordre par rapport à S5b.**
   - (a) Tout S6 après S5b.
   - (b) Tout S6 avant S5b, intégré au rejeu.
   - (c) Avant S5b, ce qui survit au rejeu (relevés sur l'hôte, scripts, installation et rebuild dans `sc-replay`, VSA signée dans la VM) ; après S5b et après le relevé du 21/11, ce qui écrit dans le cluster ou dans Zot (CronJob du deb, push de la VSA).

   **Ma recommandation : (c).** Elle utilise l'attente, laisse S5b et C9 tels que commités, et tient la tâche du 21/11 à l'écart. L'intégration de S6 à `rejeu.sh` vient ensuite, pour les rejeux suivants.
2. **Contrôle 7 du deb.** Un mode deb du scanner (extraction de `data.tar`, `syft dir:`, plancher de l'artefact seul), ou un écart à l'ADR 0000 §4, qui est ton choix. **Ma recommandation** : le mode deb, sous réserve du relevé de S6a.
3. **Contrôle 6 du deb.**
   - Chroot reconstruit dans le domaine : mmdebstrap et sbuild installés dans `sc-replay` par apt, archive Debian signée, versions épinglées, sans recommandés, comme `busybox-static` en R2.
   - Ou `749d746c` réutilisée, comme écart déclaré à `politique-replay.md` §3.
   - Ou un écart à l'ADR.

   **Ma recommandation** : la reconstruction dans le domaine, seule à garder la même indépendance que le replay de la voie image.
4. **Accord pour le relevé 1 de S6a**, sur l'hôte : hors réseau, lecture du deb local, écriture seulement sous `~/.cache/supply-chain-poc/06/s6a` et dans `resultats/`. Rien dans le cluster ni dans Zot.

## Additif du 12/11/2026, 08:56 UTC : décisions sur S6

**Décision du propriétaire** (12/11/2026, 08:50:32 UTC) : « 1 ok / 2 ok / 3 ok / 4 ok ». Les recommandations sont toutes retenues :
- l'ordre (c) ;
- le mode deb du scanner pour le contrôle 7 ;
- le chroot reconstruit dans `sc-replay` pour le contrôle 6 ;
- le relevé 1 de S6a sur l'hôte, hors réseau.

Ce n'est pas un accord pour l'installation dans `sc-replay`, ni pour une écriture dans le cluster ou dans Zot : chacune aura son accord nommé. [Prédictions du relevé 1](resultats/s6a-predictions.md), commitées avant toute mesure.

## Additif du 12/11/2026, 08:58 UTC : relevé 1 de S6a tenu

Relevé sur l'hôte, hors réseau, de 08:54:30 à 08:54:37 UTC (troisième passage complet ; les deux premiers se sont arrêtés sur deux erreurs de lecture dans mon script). [Résultats](resultats/s6a-predictions.md) : P1 à P5 et P7 tenues, P6 en partie réfutée.

- Le deb est en xz, et busybox dans la base d'`outils-scan` a `ar`, `xz`, `unxz` et `tar` : **pas de nouvelle image d'outils**.
- `syft dir:` sur `data.tar` extrait donne 3 PURL Go, dont `stdlib@1.24.4`, sans `distro=`, qui n'est pas nécessaire. Grype trouve 140 correspondances, dont 135 sur la stdlib et 5 sur chi v5.2.3 (prédit : aucune). Aucune n'est KEV ni `MAL-`.
- **Le vide est masqué, mesuré** : un artefact vide donne code 0 et rien sur la sortie d'erreur, et la fusion avec la source garde 3 PURL sur 4. Le seul apport du deb, la stdlib, disparaîtrait sans erreur. Le mode deb aura donc un plancher sur l'artefact seul.
- Constat : la porte admettrait le deb avec 7 vulnérabilités Critical, puisque le contrôle 7 ne juge que les KEV et les `MAL-` (ADR 0000 §4). L'exactitude des correspondances de la stdlib, face à d'éventuels rétroportages Debian, n'est pas mesurée.

**Correction datée** : le titre de l'additif « 08:56 UTC : décisions sur S6 » et celui des prédictions donnent une heure que je n'avais pas relevée. L'heure vraie est celle du commit `d40dd3c`, 08:52:49 UTC, avant la mesure.

**Suite** : préparer à sec le mode deb de `scanner.sh` et son pod d'essai (forme de l'extraction par busybox), puis les relevés de S6b (versions de mmdebstrap et de sbuild candidates dans `sc-replay`, place, `finishedOn`). Aucune écriture dans le cluster ni dans Zot avant S5b et le relevé du 21/11.

## Additif du 12/11/2026, 09:14 UTC : mode deb du scanner et relevé 1 de S6b, préparés à sec, rien lancé

Préparé sur « continue » (cadre : à sec). Rien n'a tourné : ni pod, ni SSH, ni lecture de Zot.

**Mode deb du scanner (S6a, pas 2)**
- Le changement est un correctif, [`s6a-scanner-deb.patch`](s6a-scanner-deb.patch), **non appliqué** à `politique/scanner.sh` de la 07a. `rejeu.sh` déploie ce script (ConfigMap `scan-config`), et S5b doit le déployer tel qu'il est commité. Le correctif s'appliquera après S5b, comme `g5-porte.patch` en G5.
- Il ajoute :
  - une variable `NATURE` (`image` par défaut, ou `deb`) ;
  - l'extraction du `data.tar` du deb par busybox, en échec fermé ;
  - un plancher : au moins une PURL versionnée dans le SBOM de l'artefact seul, pour les deux natures.
- Il s'écarte sur deux points des conséquences écrites après le relevé 1 : le plancher est générique et non propre au Go, et il s'applique aussi à l'image. Le détail est dans les [prédictions de l'essai](resultats/s6a-essai-predictions.md).
- **Pod d'essai** : étape `essai` de [`s6a.sh`](s6a.sh), sur une copie corrigée du script. Il compte cinq cas : le deb ; deux natures croisées, qui doivent être refusées ; l'image ; une nature inconnue. Une ConfigMap et un pod sont créés dans l'espace `scan`, puis supprimés. Rien n'est écrit dans Zot. **Il attend un accord nommé.**

**Relevé 1 de S6b (contrôle 6)**
- Script : [`s6b.sh`](s6b.sh), étape `releve`. [Prédictions](resultats/s6b-predictions.md).
- Il relève :
  - sur l'hôte : les provenances du deb (`finishedOn`, entrées), la reconstruction du layout `039949f9` à partir des seuls octets du deb, et la taille des entrées à transporter ;
  - dans `sc-replay` : les ressources, les espaces de noms sans privilège, les candidats apt de mmdebstrap et de sbuild sans recommandés (`--assume-no`), et l'instantané Debian joint depuis la VM.
- La seule écriture hors des dossiers de travail est `apt-get update` dans la VM. Aucun paquet n'est installé. **Il attend un accord nommé.**

**Suite** : sur accord, l'essai puis le relevé. Viendront ensuite, chacune sous son accord nommé, la décision sur la source des paquets du chroot et l'installation dans `sc-replay`. Aucune écriture dans le cluster autre que l'essai, et rien dans Zot, avant S5b et le relevé du 21/11.

## Additif du 12/11/2026, 09:18 UTC : premiers passages de l'essai et du relevé 1 de S6b

Les deux étapes ont été lancées par toi depuis le terminal, à 09:16 UTC.

- **Essai de S6a** : le pod a été refusé à l'admission par `limites-obligatoires` (08c, H5), faute de limite de CPU. C'était mon erreur. Rien n'a tourné. La limite est ajoutée ([note](resultats/s6a-essai-predictions.md)) et l'essai n'est pas rejoué.
- **Relevé 1 de S6b** : H1 à H3 sont tenues ([résultats](resultats/s6b-predictions.md)).
  - Le layout `039949f9` se reconstruit, octet à octet, à partir des seuls octets du deb.
  - Le tag `.att` porte quatre provenances de pipeline aux mêmes entrées, la dernière finie le 11/11 à 21:03:37 UTC.
  - Les entrées à transporter font 227 Mo.
  - La partie dans la VM n'a pas tourné : SSH a été coupé avant l'authentification. `IdentitiesOnly=yes` est ajouté, et la partie n'est pas rejouée.

## Additif du 12/11/2026, 09:21 UTC : essai du mode deb tenu

Le second passage, lancé à 09:19:10 UTC sur ton accord « Oui, relance-le », finit en code 0 après 96 s ([résultats](resultats/s6a-essai-predictions.md)). E0 à E6 sont tenues.

- **Le mode deb fonctionne avec le busybox d'`outils-scan`** (1.37.0). Il retrouve le deb `0b489d43`, en extrait 3 fichiers et trouve 2 PURL versionnées.
- **Les refus marchent** : deux natures croisées et une nature inconnue sont refusées. Le cas « voie image sur le deb » est arrêté par le plancher : c'est le vide masqué du constat 3 de la carte. La voie image de sample-app passe le plancher.
- Pod et ConfigMap sont supprimés, et `scanner.sh` de l'arbre n'a pas changé.
- Le correctif reste non appliqué jusqu'après S5b.

Le relevé 1 de S6b, partie VM, attend toujours ton accord.

## Additif du 12/11/2026, 09:23 UTC : relevé 1 de S6b tenu, sauf V4

Le second passage a tourné de 09:23:13 à 09:23:15 UTC, sur ton accord « Oui, lance S6b », en code 0 ([résultats](resultats/s6b-predictions.md)).

- Dans `sc-replay` : 13 Go libres et 5,4 Go de mémoire disponibles. Les espaces de noms sans privilège et les subuid de `replay` sont en place. Rien n'est installé.
- Les candidats apt de mmdebstrap, sbuild et uidmap sont exactement les versions de l'instantané. Sans recommandés, apt ajouterait 44 paquets (prédit : au plus 40), pour 55 Mo.
- V4 n'est pas jugée : l'instantané répond par une redirection 302, que mon script n'a pas suivie.

**Questions ouvertes**, avant l'installation dans `sc-replay` : la provenance à retenir parmi les quatre, la source des paquets du chroot, et V4 à remesurer.

## Additif du 12/11/2026, 09:41 UTC : V4 à remesurer et deux décisions, préparées à sec, rien lancé

Préparé sur « continue » : aucune commande n'a été lancée vers la VM, le cluster ou Zot.

**V4 à remesurer** : nouvelle étape `v4` de [`s6b.sh`](s6b.sh), avec ses [prédictions](resultats/s6b-predictions.md). Elle tourne dans la VM seule, sans sudo ni `apt-get update` :
- la cible de la redirection 302 ;
- l'InRelease lu en suivant la redirection, comme `s1.sh`, et son sha256 comparé à celui de S1 ;
- sa signature, vérifiée par `gpgv` avec le trousseau Debian de la VM ;
- l'état dpkg de chaque paquet visé, qui remplace la ligne trompeuse « déjà là : libsbuild-perl ».

Elle attend ton accord nommé : `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh v4`.

**Décision 1 : la provenance que la VSA désigne.**
- `vsa.py` désigne une provenance par son `invocationId`. Il exige le bundle horodaté de cette invocation, et au moins 24 h entre `finishedOn` et la vérification. Les quatre provenances d'aujourd'hui passent ce délai depuis le 12/11, 21:03:37 UTC.
- **S5b remet Zot à zéro** (point 7 de la carte de S6), et la plateforme doit y reconstruire le deb deux fois ([C6 de S5b](../08-trust-plane/resultats/s5b-predictions.md), confiance moyenne). Les quatre provenances et leurs bundles horodatés disparaissent. La VSA poussée après S5b (ordre c) désignera donc une provenance nouvelle, pas l'une des quatre.
- **Ma recommandation : une règle plutôt qu'un identifiant.** La VSA désigne la provenance la plus récente du digest au moment du rejeu, celle que la porte juge (S4d3). Son `invocationId` est relevé et écrit au journal. Avant S5b, pour la VSA signée dans la VM et non poussée, la règle donne `454728c5`.
- L'autre voie, la première exécution (`b9d4881e`), ne se transpose pas après S5b : rien ne dit quelle exécution S5b fera en premier.

**Décision 2 : d'où viennent les paquets du chroot.**
- **A, l'instantané lu par la VM.** `sc-replay` lit les paquets sur snapshot.debian.org. L'InRelease est contrôlé deux fois : par son sha256, fixé en S1, et par la signature, vérifiée avec le trousseau Debian de la VM (V4c). mmdebstrap tourne lien ouvert ; sbuild tourne ensuite lien coupé, comme R4 pour l'image. Les octets ne passent pas par la plateforme.
- **B, le miroir de la plateforme transporté.** C'est le miroir partiel de `prefetch-deb`, que `construire-builder` lit dans un PVC. Je n'ai pas relevé s'il en existe une copie dans Zot. Transporté, il serait revérifié par le même InRelease. Le domaine n'aurait plus besoin d'accès extérieur, mais les octets viendraient de la plateforme.
- **Ma recommandation : A**, si V4 est tenue. C'est la seule voie où le domaine ne reçoit de la plateforme que des empreintes. La fermeture deb `bb7599a2`, nommée dans la provenance, reste transportée, comme les entrées de l'image en R3.
- Le volume du chroot à télécharger n'est pas mesuré ; S2 a mesuré 509 Mo pour le chroot construit.

Il n'y a rien d'autre à préparer avant tes réponses : l'installation dans `sc-replay` (4 versions épinglées) attendra un accord nommé, après V4 et ces deux décisions.

## Note datée du 12/11/2026, 09:44 UTC : correction de l'additif précédent, après relecture du conseiller

L'additif précédent est de 09:42:08 UTC (commit `844bf9e`), et non de 09:41 : l'heure était extrapolée d'un `date -u` de 09:40:56.

**Décision 1 : ma prémisse était fausse.**
- Selon l'ordre (c), la VSA du deb est **signée dans la VM avant S5b** et poussée seulement après. Elle revient par un bundle versionné re-poussé, avec un `inputAttestations` vers un bundle horodaté effacé (point 7 de la carte de S6), comme celle de sample-app.
- Elle désigne donc **l'une des quatre provenances d'aujourd'hui**. Ma phrase « désignera une provenance nouvelle » et mon argument contre `b9d4881e` ne tiennent pas.
- La question reste celle du relevé : `b9d4881e` (S4d1, la première) ou `454728c5` (S4d3, la plus récente). Je recommande toujours **`454728c5`**, parce que c'est la provenance que la porte juge : porte et VSA portent alors sur la même provenance.
- **Délai de 24 h** : « passent ce délai depuis le 12/11, 21:03:37 UTC » était faux à cette heure. Aucune ne le passe encore : `b9d4881e` à partir du 12/11 à 19:48:48 UTC, `454728c5` à partir du 12/11 à 21:03:37 UTC. `vsa.py` compare `finishedOn` à la fin de la reconstruction (`timeVerified`) : la reconstruction dans la VM doit finir après cette heure.
- Une VSA refaite après S5b, sur une provenance nouvelle, changerait l'ordre (c). Elle demanderait de rejouer le contrôle 6 et d'attendre 24 h après le nouveau `finishedOn`. Je ne la propose pas.

**Décision 2 : la recommandation A est inchangée, mais deux précisions.**
- Dans A, la vérification qui protège le chroot est celle d'apt, pendant mmdebstrap, avec le trousseau de la VM. V4c n'en est qu'un **témoin préalable**.
- Les paquets du chroot reconstruit seront **comparés à [`builder/paquets.txt`](builder/paquets.txt)** (199 lignes : nom, version, sha256, taille), la liste épinglée de la plateforme. Sans cette comparaison, un chroot lu sur l'instantané pourrait différer de celui de la plateforme sans qu'on le voie.

**Défaut de `v4` corrigé avant tout lancement** ([note datée](resultats/s6b-predictions.md)) : les trois clés de S1 arrivaient en trois arguments par ssh, et V4c n'aurait comparé qu'une clé. `sqv` est ajouté à la liste de V1c.

## Additif du 12/11/2026, 09:48 UTC : décisions 1 et 2 prises, V4 remesurée

**Décisions du propriétaire** : « 1 ok / 2 ok / 3 ok », reçue avant le lancement de 09:47:50 UTC (heure exacte du message non relevée).
1. **La VSA du deb désigne la provenance `454728c5`** (S4d3, la plus récente), celle que la porte juge. La reconstruction dans `sc-replay` doit finir après le 12/11/2026 à 21:03:37 UTC (délai de 24 h de `vsa.py`).
2. **Les paquets du chroot viennent de l'instantané, lus par `sc-replay`** (voie A). apt les vérifie pendant mmdebstrap, avec le trousseau de la VM. Le chroot est construit lien ouvert, puis sbuild tourne lien coupé, et les paquets du chroot sont comparés à [`builder/paquets.txt`](builder/paquets.txt).
3. Accord pour lancer `v4`.

**V4 remesurée** (09:47:50 UTC, code 0, [résultats](resultats/s6b-predictions.md)) :
- L'instantané est joignable depuis la VM. La redirection 302 mène au magasin de fichiers de snapshot, par empreinte, en http.
- **L'InRelease lu par la VM est celui de S1** : sha256 `0584fba3…`.
- **La signature n'est pas vérifiée** : `gpgv` n'est pas installé dans la VM. apt y utilise `sqv` (1.3.0), avec le trousseau `debian-archive-keyring` 2025.1 (`.pgp`). C'est donc `sqv`, par apt, qui vérifiera l'instantané pendant mmdebstrap. Un témoin préalable avec `sqv` reste à écrire, une fois sa syntaxe lue dans la VM.
- L'état dpkg explique la ligne trompeuse : `libsbuild-perl` est connu de dpkg (`un`) sans être installé.

**Reste avant la reconstruction** : préparer à sec l'installation dans `sc-replay` (les quatre versions épinglées, sans recommandés) et le témoin `sqv`. L'installation attend un accord nommé.

## Additif du 12/11/2026, 09:52 UTC : témoin `sqv` et installation dans `sc-replay`, préparés à sec, rien lancé

Préparés après « Oui, prépare-les » : deux étapes nouvelles de [`s6b.sh`](s6b.sh), avec leurs [prédictions](resultats/s6b-installation-predictions.md). Chacune attend ton accord nommé.

- **`sqv`** : le témoin de signature que V4c n'a pas pu faire.
  - Il tourne dans la VM seule, sans sudo, et n'installe rien.
  - `sqv`, le vérificateur qu'apt utilise dans la VM, contrôle l'InRelease de l'instantané avec le trousseau de la VM, en exigeant un puis trois signataires. Le message extrait doit porter le sha256 de Packages.xz contrôlé en S1.
  - Une copie altérée doit être refusée. Sur l'hôte, `gpgv` refuse la même altération.
- **`installer`** : l'installation système.
  - mmdebstrap, sbuild, libsbuild-perl et uidmap, aux versions épinglées, sans recommandés, et sans `apt-get update`.
  - Les quatre `.deb` sont d'abord seulement téléchargés. Leurs sha256 sont comparés à `builder/paquets.txt` **avant toute installation** ; un écart arrête tout.
  - Puis l'installation depuis le cache, et un bilan : versions, paquets nouveaux (44 prédits), services actifs, cache vidé.

Commandes, dans cet ordre :
- `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh sqv`
- `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh installer`

**Note datée du 12/11/2026, 09:54 UTC** : trois défauts corrigés avant tout lancement, après relecture du conseiller ([note](resultats/s6b-installation-predictions.md)) :
- le témoin négatif de `sqv` n'est jugé que si l'original est accepté ;
- un `KO` donne le code 1 ;
- les `apt-get` d'`installer` lisent `/dev/null`, et non le script.

Les commandes ne changent pas.

**Note datée du 12/11/2026 (heure de la note précédente)** : « 09:54 UTC » n'a pas été relevée. Le `date -u` lancé juste avant la rédaction de la note précédente donnait 09:55:38, et son commit `8d538af` est de 09:55:39 UTC. Ces heures font foi ; le titre du commit `8d538af` porte la même erreur.

## Additif du 12/11/2026, 10:03 UTC : témoin `sqv` et installation tenus

Lancés sur ton accord « Oui, lance les deux » ([résultats](resultats/s6b-installation-predictions.md)).

- **`sqv`** (10:02:00 UTC, code 0) : le trousseau de la VM vérifie l'InRelease de l'instantané, et ses signataires sont **exactement les trois de S1**. Une copie altérée est refusée (« Message has been manipulated »), et le message extrait porte le sha256 de Packages.xz de S1.
- **`installer`** (10:02:07 à 10:02:45 UTC, code 0) :
  - mmdebstrap, sbuild, libsbuild-perl et uidmap sont installés aux versions épinglées. Leurs sha256 étaient égaux à ceux de `builder/paquets.txt` avant l'installation.
  - 44 paquets nouveaux, **tous à la version de la plateforme** (comparaison faite sur l'hôte) ; aucun service nouveau ; cache vidé.
- **Écarts** :
  - le compte de paquets (338 `ii`, non 339) vient de deux façons de compter ;
  - `sbuild --version` n'a donné qu'un avis ;
  - **apt nomme le trousseau `.gpg`, et le témoin a lu le `.pgp`** : leur identité reste à relever.

**Suite** (à préparer à sec) : le relevé du `.gpg`, puis mmdebstrap depuis l'instantané dans `sc-replay`, avec la comparaison du chroot à `builder/paquets.txt`.

## Additif du 12/11/2026, 10:13 UTC : trousseau et chroot dans `sc-replay`, préparés à sec, rien lancé

Préparés après « Oui, prépare-les » : deux étapes nouvelles de [`s6b.sh`](s6b.sh), avec leurs [prédictions](resultats/s6b-chroot-predictions.md). Chacune attend ton accord nommé.

- **`trousseau`** relève le fichier `.gpg` qu'apt nomme. Elle compare son sha256 à celui du `.pgp` qu'a lu `sqv`, passe `dpkg -V` sur le paquet, puis lance `sqv -n 3` avec le `.gpg`. VM seule, sans sudo.
- **`chroot`** lance mmdebstrap dans la VM, depuis l'instantané, avec les options du chroot de la plateforme (`--mode=root`, variante `buildd`, même `SOURCE_DATE_EPOCH`, mêmes crochets). `signed-by` est explicite sur le trousseau de la VM. Quatre contrôles suivent :
  - chaque `.deb` téléchargé dans `builder/paquets.txt`, par son sha256 ;
  - le chroot comparé à celui de la plateforme (`aec1c7a9…`, 451 786 240 octets) ;
  - les paquets installés dans `builder/paquets.txt` ;
  - un témoin négatif avec un trousseau sans les clés de trixie, qui doit échouer.

  L'étape tourne avec sudo et lien ouvert, et n'écrit que sous `/home/replay/s6b`.
- **Contrôle fait sur l'hôte**, sur la copie du chroot de la plateforme : la comparaison de l'étape y trouve 122 paquets, tous dans `builder/paquets.txt`.

Commandes, dans cet ordre :
- `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh trousseau`
- `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh chroot`

**Note datée du 12/11/2026, 10:19 UTC** : l'étape `chroot` est corrigée avant tout lancement, après relecture du conseiller ([note](resultats/s6b-chroot-predictions.md)) :
- un écart de C2 sera diagnostiqué par la liste des noms et le détail de l'archive, comparés à ceux du chroot de la plateforme ;
- C3 exige l'égalité avec ses 122 paquets ;
- le motif du témoin négatif est corrigé ;
- le `rm` passe en `--one-file-system` ;
- le dossier temporaire de mmdebstrap est sous `/var/tmp`.

L'appui de C2 est plus faible que je ne l'avais écrit : aucune reproduction du chroot d'un jour à l'autre n'est mesurée. Les commandes ne changent pas.

## Additif du 12/11/2026, 10:27 UTC : trousseau et chroot tenus, chroot de la plateforme reproduit dans `sc-replay`

Lancés sur ton accord « Oui, lance les deux » ([résultats](resultats/s6b-chroot-predictions.md)).

- **`trousseau`** (10:24:58 UTC, code 0) : `debian-archive-keyring.gpg` est un lien vers le `.pgp` qu'a lu `sqv`. `dpkg -V` est propre, et `sqv` donne les trois signataires de S1 avec le `.gpg`. L'écart est levé.
- **`chroot`** (10:25:03 à 10:26:08 UTC, code 0) : mmdebstrap a tourné 52 s dans `sc-replay` depuis l'instantané, sans avertissement.
  - **Le chroot est identique, octet pour octet, à celui de l'image de build de la plateforme** (`aec1c7a9…`, 451 786 240 octets), avec les mêmes 12 515 entrées et les mêmes attributs.
  - Les 63 `.deb` téléchargés et les 122 paquets installés sont ceux de la plateforme.
  - Le témoin négatif est refusé par apt, sur la signature, avec **`/usr/bin/sqv`** : c'est maintenant mesuré.
- **Mon erreur** : les valeurs de référence de ma note de 10:19 étaient calculées dans ma locale, et non avec `LC_ALL=C`. L'étape, elle, a tourné avec `LC_ALL=C` des deux côtés ; recalculées ainsi, les valeurs concordent.

**Suite du contrôle 6** (à préparer à sec) : transporter la fermeture deb `bb7599a2` (216 Mio), les sources et le packaging dans `sc-replay` ; lancer sbuild lien coupé ; comparer le deb à `0b489d43`.

## Additif du 12/11/2026, 10:35 UTC : transport, vérification et reconstruction du deb dans `sc-replay`, préparés à sec, rien lancé

Préparés après « Oui, prépare-les », sur le modèle de R3 et R4 de la brique 10 ([prédictions](resultats/s6b-rejeu-predictions.md)). Il y a quatre étapes nouvelles de [`s6b.sh`](s6b.sh) et deux outils de la VM, sous [`rejeu/`](rejeu/). Chaque étape attend ton accord nommé.

1. **`transporter`** (hôte, transport non fiable) copie le layout du deb, ses bundles horodatés et les entrées de la provenance `454728c5`, le manifeste seul de l'image de build, un bundle git et les ancres de la 08.
2. **`verifier`** (VM) vérifie les bundles horodatés hors réseau, puis la provenance, les digests, le commit, 15 lignes clés des recettes signées et la version de Go. Il **rattache le chroot du domaine à la couche de l'image de build `749d746c`**.
3. **`repetition`** reconstruit lien établi, sans être comptée.
4. **`rebuild`** reconstruit **lien coupé**. Elle n'est pas possible avant le 12/11/2026 à 21:03:37 UTC (24 h après `finishedOn`). Critère : manifeste reconstruit = `039949f9`.

**Contrôles faits sur l'hôte**, hors réseau :
- la lecture des entrées sur les provenances du relevé H1 ;
- les lignes clés sur les tâches signées ;
- le rangement du chroot sur la copie de la plateforme, qui redonne la couche `1029232e…`. Ce dernier contrôle a trouvé un défaut, corrigé avant tout lancement : les modes des répertoires dépendaient de l'umask.

**Note datée du 12/11/2026, 10:40 UTC** : quatre défauts du lot précédent sont corrigés avant tout lancement, après relecture du conseiller ([note](resultats/s6b-rejeu-predictions.md)) :
- nettoyage en root ;
- arbre de travail sous `/var/tmp`, puisque sbuild en mode unshare doit le traverser avec un subuid (lu dans son code) ;
- code 1 sans `PASSED` ;
- recherche de la version de Go.

## Additif du 12/11/2026, 10:44 UTC : deb reconstruit dans `sc-replay`, identique, en répétition (lien établi)

Lancés sur ton accord « Oui, lance les trois » ([résultats](resultats/s6b-rejeu-predictions.md)) :
- **`transporter`** (10:42:31 UTC, code 0) : 8 bundles horodatés, 7 entrées et le manifeste de l'image de build, soit 402 Mo.
- **`verifier`** (10:42:41 UTC, `0 KO`) :
  - 8 bundles vérifiés sur 8 hors réseau, et la provenance `454728c5` extraite ;
  - les 8 entrées, le commit, les 15 lignes clés des recettes et Go 1.26.10 conformes ;
  - **le chroot reconstruit dans la VM, rangé comme dans l'image de build, donne la couche `1029232e…` de `749d746c`**.
- **`repetition`** (10:42:53 à 10:44:05 UTC, lien établi, non comptée) : **deb `0b489d43…`, manifeste `039949f9…`, égal au sujet de la provenance : `PASSED`**. sbuild a tourné 68 s, sans aucune ligne apt en http(s). Le paquet source est identique à celui de la plateforme. Les compteurs d'émission de la VM n'ont pas bougé pendant la reconstruction.

**Reste pour le contrôle 6** : `rebuild`, lien coupé, à partir du 12/11/2026 à 21:03:37 UTC, sur ton accord. Puis la VSA, signée dans la VM et non poussée avant S5b.

## Additif du 12/11/2026, 10:50 UTC : VSA du deb, préparée à sec, rien lancé ni signé

Préparée après « Oui, prépare-la », sur le modèle de R5 de la brique 10 ([prédictions](resultats/s6b-vsa-predictions.md)).

- **[`rejeu/politique-replay-deb.md`](rejeu/politique-replay-deb.md)** : un **projet de politique, à ta relecture**. Celle de la 10 est écrite pour l'image. La VSA citera celle-ci par URL, à un commit poussé, et par son sha256. Le projet propose de ranger la VSA dans `builds/vsa/sample-app-deb`.
- **[`rejeu/vsa_deb.py`](rejeu/vsa_deb.py)** écrit l'énoncé seulement si tout tient. Par rapport à la 10, il exige en plus **la porteuse à 0 au départ et à la fin** : un résultat de répétition ne peut donc pas produire de VSA.
- **`vsa_essai`** joue `vsa_deb.py` tout de suite sur la répétition, sans rien signer. Il doit refuser sur exactement trois conditions : lien établi au départ, lien établi à la fin, délai.
- **`vsa`** signe dans la VM après `rebuild`. Il faut auparavant un commit qui fige la politique et un push.

**Ce qui attend une décision de ta part** :
- la relecture du projet de politique ;
- le dépôt de rangement ;
- le push des commits ;
- puis les lancements, chacun sur accord nommé.

**Note datée du 12/11/2026, 10:56 UTC**, après relecture du conseiller ([note](resultats/s6b-vsa-predictions.md)). Avant tout lancement :
- **Ordre** : un seul push, après le commit des résultats de `rebuild`.
- **`vsa_essai`** construit l'énoncé complet sans l'écrire, et vérifie la présence de la clé sans la lire.
- **`vsa`** refuse une politique qui porte encore une mention de projet.
- **Rangement** : la porte fixe déjà `builds/vsa/sample-app-deb`.
- **Une question te revient** : faut-il revendiquer `SLSA_BUILD_LEVEL_3` pour un deb construit dans un pod Kata privilégié ([notes de relecture](rejeu/politique-replay-deb.md)) ?

## Additif du 12/11/2026, 10:57 UTC : essai de la VSA du deb tenu, rien de signé

`vsa_essai` a tourné à 10:56:55 UTC, sur ton accord « Oui, lance-le », avec le code 0 ([résultats](resultats/s6b-vsa-predictions.md)).
- `vsa_deb.py` a tourné hors réseau dans la VM sur le résultat de la répétition. Il a revérifié le bundle horodaté de `454728c5` et construit tout l'énoncé.
- **Il a refusé sur exactement les trois conditions attendues** : lien établi au départ et à la fin, et délai de 24 h non atteint. Aucun énoncé n'a été écrit.
- La clé du domaine est présente ; elle n'a pas été lue.

**Pour finir le contrôle 6** :
1. ta relecture de la politique, et ta réponse sur `SLSA_BUILD_LEVEL_3` ;
2. `rebuild` ce soir, à partir de 21:03:37 UTC ;
3. un push ;
4. `vsa`.

**Décision du 12/11/2026, reçue avant 10:59 UTC (« Bit identique seul »)** : la VSA du deb ne revendique que `POC_REPLAY_BIT_IDENTIQUE`, et `rejeu/vsa_deb.py` est modifié en conséquence. Il reste ta relecture du projet de politique, avant le commit qui la fige.

## Additif du 12/11/2026, 11:00 UTC : texte proposé pour figer la politique du deb, à ton approbation

Préparé après « Oui, prépare-le ». [`rejeu/politique-replay-deb.md`](rejeu/politique-replay-deb.md) est réécrit : c'est un texte déjà commité, réécrit avec ton accord. Les trois notes de relecture et ta décision sont intégrées, puis les notes sont retirées. Les changements de fond :
- **section 3** : ce qui lie le chroot, c'est l'égalité de sa couche avec celle de l'image de build déclarée. apt vérifie l'InRelease avec `sqv` et le trousseau de la VM ; la VSA exige la porteuse à 0 au départ et à la fin ;
- **section 5** : seul `POC_REPLAY_BIT_IDENTIQUE` est revendiqué ;
- **section 6** : le dépôt `builds/vsa/sample-app-deb` est celui que dérive la porte.

Le texte ne porte plus aucune mention de projet, et la garde de `vsa` l'accepte. Son sha256 est `6cc94a50…`.

**Ce commit n'est pas encore `POLITIQUE_COMMIT`.** Il le deviendra sur ton approbation ; si tu demandes des changements, ce sera le commit qui les porte. La VSA citera l'URL du fichier à ce commit, et son sha256.

**Approbation du propriétaire, 12/11/2026, reçue avant 11:04 UTC (« Oui, je l'approuve »)** : la politique du deb est figée par **`POLITIQUE_COMMIT=97ae561de9e9eccb296fcba09fbbc351988ecf1b`** (`97ae561`). Le sha256 du fichier à ce commit, `6cc94a50…`, a été relu par `git show`. La VSA citera `https://github.com/gigi206/supply-chain/blob/97ae561de9e9eccb296fcba09fbbc351988ecf1b/poc/bricks/06-deb-sbuild/rejeu/politique-replay-deb.md`. Il faut que ce commit soit poussé : `vsa` le vérifie.

**Reste** :
1. `rebuild`, à partir de 21:03:37 UTC (avec `ATTENTE_HORS_LIGNE=300`, si tu es d'accord) ;
2. le commit de ses résultats, puis un seul push, avec ton « oui » ;
3. `POLITIQUE_COMMIT=97ae561de9e9eccb296fcba09fbbc351988ecf1b mise exec -- poc/bricks/06-deb-sbuild/s6b.sh vsa`.


**Additif du 12/11/2026 (à partir de 11:58:09 UTC, après « continue ») : push de la VSA du deb préparé à sec, rien lancé.** `s6b.sh` gagne deux étapes, pour après S5b :
- `pousser_vsa` pousse par digest, avec le compte `poc-replay`, la VSA archivée par `vsa` dans `builds/vsa/sample-app-deb`. Elle refuse si le layout `039949f9` n'est pas dans Zot, ce qui arrivera après S5b si le build ne le reproduit pas ;
- `lire_vsa` relit la VSA et la provenance en anonyme, avec les clés croisées.

Prédictions : [`resultats/s6b-pousser-predictions.md`](resultats/s6b-pousser-predictions.md). `rebuild` et `vsa` ne changent pas.

**Additif du 12/11/2026 (à partir de 12:51:01 UTC, après « continue ») : contrôle 7 du deb en service (pas 3 et 4 de S6a) préparé à sec, rien lancé.** Pour après S5b et le relevé du 21/11, chaque étape sur accord nommé :
- deux correctifs non appliqués :
  - [`s6a-fraicheur-deb.patch`](s6a-fraicheur-deb.patch) fait écrire par `fraicheur-scan.py` (07a) une série par dépôt ;
  - [`s6a-alertes-deb.patch`](s6a-alertes-deb.patch) donne à `ScanEnRetard` (19) un `absent()` par dépôt, et des tests en conséquence ;
- trois étapes neuves de [`s6a.sh`](s6a.sh) :
  - `periodique` crée le CronJob `scan-sample-app-deb` à 11:15 UTC et lance un passage depuis lui. Le CronJob doit égaler celui de l'image, hors image, nom, dépôt et `NATURE` ;
  - `fraicheur` installe le script corrigé sur `sc-stockage` ;
  - `porte` lance la porte sur le deb, avec un scan `ok` attendu.

Aucun fichier rejoué par S5b n'est modifié, et `s6b.sh` ne change pas. Prédictions et limites : [`resultats/s6a-service-predictions.md`](resultats/s6a-service-predictions.md). La principale limite est que `rejeu.sh` n'intègre pas S6.

**Additif du 12/11/2026 (à partir de 13:04:25 UTC, après « continue ») : lecture du contrôle 7 du deb dans Grafana préparée à sec, rien lancé.** Une quatrième étape de [`s6a.sh`](s6a.sh), `grafana`, lit en auditeur, à travers Grafana, ce que `periodique` et `fraicheur` ont produit : les journaux du job, la signature dans l'audit d'OpenBao, le poussage dans l'audit de Zot et le journal de `fraicheur-scan` avec les deux dépôts. Elle ne fait que lire, et vient juste après `fraicheur`, avant tout passage planifié. Prédiction : Q10 de [`resultats/s6a-service-predictions.md`](resultats/s6a-service-predictions.md).

**Additif du 12/11/2026 (à partir de 14:04:51 UTC) : ordre (c) modifié par la décision « Oui, avance S5b », RIEN LANCÉ.** S5b est avancé au 13/11, après l'étape `vsa` de ce soir (README de la 08, additif du même jour). Partout où les textes commités de S6 disent « après S5b et le relevé du 21/11 », il faut lire « après S5b » : S6a (`periodique`, `fraicheur`, `grafana`, `regles`, `deployer`, `porte`), `pousser_vsa`, `lire_vsa`, puis le diff de `rejeu.sh`. Le point 8 de la carte de S6 ne tient plus : la tâche du 21/11 est désactivée au lancement de S5b, et sa nouvelle prédiction devra compter `builds/scan/sample-app-deb`. Ce soir, rien ne change : `rebuild` à partir de 21:03:37 UTC, commit, push, puis `vsa`, chacun sur accord.

**Additif du 12/11/2026, 21:04 UTC : `rebuild`, deb reconstruit dans `sc-replay`, lien coupé, identique.** Lancé à 21:04:45 UTC (« Oui, lance rebuild » à « Je lance rebuild ? »), lien coupé de 21:04:46 à 21:09:46 UTC, code 0 ([journal](resultats/s6b-rebuild.log), [résultats](resultats/s6b-rejeu-predictions.md)).
- Deb `0b489d43…` (1 952 080 octets), manifeste `039949f9…`, égal au sujet de la provenance : `verdict=PASSED`. Sortie de la VM inchangée pendant la coupure ; rebuild fini avant le rétablissement du lien. **Le contrôle 6 du deb est valable hors ligne.**
- **Reste** : la vérification d'avant push et un seul push, avec ton « oui » ; puis `vsa`, sur accord nommé ; puis S5b, le 13/11.

**Additif du 12/11/2026, 21:20 UTC : `vsa`, VSA du deb signée par la clé du domaine.** Lancée à 21:20:08 UTC (« Oui, lance vsa » à « Je lance vsa ? »), code 0 ([journal](resultats/s6b-vsa.log), [résultats](resultats/s6b-vsa-predictions.md)).
- Énoncé `POC_REPLAY_BIT_IDENTIQUE` seul, `timeVerified` `2026-11-12T21:06:14Z`, politique au commit `97ae561` ; signé dans la VM, sous `unshare -rn`, sans tlog ni horodatage ; [énoncé](resultats/s6b-vsa-enonce.json) et bundle archivés. **Rien n'est poussé dans Zot.**
- **Reste** : S5b le 13/11, sur accord ; puis `pousser_vsa` et `lire_vsa`, chacun sur accord.

**Note du 13/11/2026 (2026-11-13T13:57:31Z) : règle des 2× avant la reprise du bloc 06** (estimation de la 06 : 2 pw, décision à 4 pw ; rien lancé).
- Consommé haut de la 06 : 0,639 pw au 13/11 à 08:50:45 UTC (recompte hors dépôt du matin, `cascade_calc.py`) ; le rejeu S5b
  d'aujourd'hui est compté à la 08.
- Reprise du bloc 06 (entrées de `$W` effacées par `vm.sh detruire` au lancement de S5b, README de la 08) : S1, S2, S3, puis le
  bloc 06 du rejeu (S1 amorce, S4c, S4a, S4b, S4d, S4d3). Enveloppe des lanceurs au premier passage de ces étapes, lue dans
  `resultats/chrono.tsv` : **7:36:59, soit 0,190 pw** (S4a de 23:02:39 à 23:37:24 UTC le 10/11 ; les autres comme au recompte du
  matin) ; mesure de lanceurs, pas de temps de personne.
- Projection (estimation) : 0,639 + reprise (0,190 à 0,639) + cascade 1.0.0-2 (0,25 à 0,639) + lintian (0,05 à 0,1) =
  **1,13 à 2,02 pw**. La borne haute (hypothèse : chaque passage coûte autant que tout le premier) dépasse l'estimation de 2 pw
  sans atteindre le seuil de 4 pw : **aucune décision due**, dépassement possible de l'estimation signalé. Non compté : la
  construction de `outils-prefetch` dans la chaîne (option E, brique 03), qui s'ajouterait à la reprise.

**Note du 13/11/2026 (2026-11-13T14:04:41Z) : carte de reprise du bloc 06 préparée à sec, RIEN LANCÉ** (« Oui, prépare-la ») :
[carte et prédictions P1 à P9](resultats/s5b-reprise-predictions.md). Six lancements, chacun sur accord nommé : S1 (`PREFIXE=s1r`,
prealables, amorce, racine, image), S2 (buildinfo, racine, fermeture, restauration), S3 (restauration, builds, comparaison), rejeu
jusqu'à « 06 (S4b) », `s4d.sh prealables`, rejeu depuis « 06 (S4d) » jusqu'à `fuites` et CIS. L'option E (outils-prefetch dans la
chaîne) vient après, avec la cascade 1.0.0-2.
- 2026-11-13T14:22:31Z : reprise, étape 1 (S1, `PREFIXE=s1r`) de 14:17:00 à 14:22:09 UTC, code 0 : racine `f8f221ca`, chroot `440ba93b`, image `d8041f9c` retrouvés au bit près ; P1 à P3 tenues ([prédictions](resultats/s5b-reprise-predictions.md)).
- 2026-11-13T14:28:59Z : reprise, étape 2 (S2) de 14:23:57 à 14:28:33 UTC, code 0 : chroot `e0b1f37c` deux fois, fermeture `3a0e54ae` retrouvée dans le nouveau Zot ; P4 et P5 tenues.
- 2026-11-13T14:33:28Z : reprise, étape 3 (S3) arrêtée en code 1 au début de `builds` : `SHA256SUMS.s1` absent (écrit par `s1.sh essais`, oublié par la carte) ; restauration passée.
- 2026-11-13T14:51:53Z : reprise, étape 3 (S3) reprise après la ligne 261 de `s1.sh` rejouée seule (`SHA256SUMS.s1`) : builds de 14:38:15 à 14:51:07 UTC, code 0, deb `0b489d43` deux fois ; P6 tenue.
- 2026-11-13T15:03:01Z : reprise, étape 4 (rejeu jusqu'à « 06 (S4b) ») de 14:52:30 à 15:02:27 UTC, code 0 : amorce, `c1719b13`, image de build `749d746c` deux fois, fermetures `bb7599a2` et `50dc73f7` deux fois ; C1 à C5 tenues.
- 2026-11-13T15:05:24Z : reprise, étape 5 (`s4d.sh prealables`) de 15:05:01 à 15:05:10 UTC, code 0 : `digest-attendu` = `039949f9` ; P7 tenue.
- 2026-11-13T15:33:05Z : reprise, étape 6 en code 1 : S4d tenue (`039949f9` deux fois) ; S4d3 chemins : un pod sans label de tâche en plus au rattrapage, porte, `fuites` et CIS non lancés.
- 2026-11-13T15:36:09Z : pod sans label de tâche relevé : assistant d'affinité de Tekton (README de la 08, l. 650), défaut du contrôle de `s4d3.sh` ; correctif préparé à sec, non appliqué ; prédiction P10.
- 2026-11-13T15:52:32Z : reprise, fin : bloc 06 passé (de 15:36:53 à 15:51:47 UTC, code 0, filtre de l'assistant d'affinité appliqué), C7 à C9 tenues, `fuites` sans secret, CIS inchangé ; **reprise du bloc 06 terminée, P1 à P10 tenues**.
- 2026-11-14T20:31:22Z : S6b `pousser_vsa` (de 20:30:50 à 20:30:55 UTC, code 0) : VSA du deb poussée dans `builds/vsa/sample-app-deb`, manifeste `bd7c77ec` ; P1 à P6 tenues, P7 non mesurée directement ; `lire_vsa` à suivre, sur accord.
- 2026-11-14T20:36:05Z : S6b `lire_vsa` (20:35:50 UTC, code 0) : L1 à L5 tenues (VSA acceptée par la clé du domaine seule, provenance par la clé de Chains seule, 12 vérifiées ; aucune connexion hors de Zot) ; **VSA du deb dans Zot terminée**.
- 2026-11-14T20:57:35Z : S6a, point 1 : `s6a-scanner-deb.patch`, `s6a-fraicheur-deb.patch` et `s6a-alertes-deb.patch` appliqués (décision « a » sur l'ordre) ; contrôles de syntaxe passés ; rien de déployé.
- 2026-11-14T20:58:56Z : S6a, point 2 : `periodique` à sec, code 0, Q1 tenue, rien d'écrit.
- 2026-11-14T21:02:27Z : S6a, point 3 : `periodique` (20:59:40 à 21:01:45 UTC, code 0) : CronJob `scan-sample-app-deb` en service, premier scan du deb publié (`256c3190`, 67 vulnérabilités, 0 KEV) ; Q2 à Q5 tenues.
- 2026-11-14T21:03:36Z : S6a, point 4 : `fraicheur` (21:02:50 à 21:03:17 UTC, code 0) : trois séries dans Prometheus ; Q6 tenue pour les séries, ligne de journal non mesurée (instrument).
- 2026-11-14T21:04:37Z : S6a, `grafana` (21:04:19 UTC, code 0) : Q10 tenue ; ligne de journal de `fraicheur-scan` vue par Loki.
