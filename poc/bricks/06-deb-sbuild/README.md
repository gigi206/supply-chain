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
