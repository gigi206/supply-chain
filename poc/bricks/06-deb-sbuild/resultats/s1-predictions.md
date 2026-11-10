# Brique 06, S1 : prédictions (écrites le 10/11/2026 à 13:03 UTC, avant toute exécution)

Le script est [`s1.sh`](../s1.sh). **Rien n'a encore été lu ni écrit dans le cluster, Zot ou les VM.**

## Accord

Le propriétaire a répondu « S1 de la 06 » à la proposition de jalon. Cette réponse est consignée comme une **interprétation** : elle choisit le jalon, mais elle n'autorise pas des effets précis. Les effets listés ci-dessous lui sont soumis par une question numérotée, et ils attendent un accord nommé.

**Effets prévus**
- lecture des arguments de kube-apiserver sur sc-confiance (manifeste du pod statique) ;
- quatre specs de pod en dry-run serveur ;
- lecture des ressources de sc-build et de la place libre de Zot ;
- écritures **définitives** dans Zot, qui n'autorise pas la suppression :
  - `amont/library/debian@sha256:7378260c…` ;
  - `essais-06/sbuild-debian13:s1`, environ 1,5 Go prévus ;
- quatre pods Kata ou runc dans `builds`, sur sc-build, supprimés à la fin de chaque essai ;
- une sortie réseau d'un pod de `builds` vers `snapshot.debian.org` (http).

`builders/sbuild-debian13` reste réservé à S2, où l'image sera construite deux fois et comparée.

## Lectures faites avant ces prédictions (sur l'hôte seul, ressources publiques)

- **Manuel de sbuild au tag `debian/0.89.3+deb13u4`** (`man/sbuild.1.in`). Il y a quatre modes de chroot : `schroot`, `sudo`, `autopkgtest` et `unshare`. Seul `unshare` coupe le réseau pendant le build (`--no-enable-network`, « only implemented for the unshare mode »).
  - Repli 2 du README : `sudo` ou `autopkgtest` (serveur `chroot`) en root, sans `unshare`.
  - Ce repli perdrait la coupure du réseau par sbuild. Elle devrait alors venir de la NetworkPolicy `construction-sans-sortie`.
- **Clés de l'archive**, prises sur ftp-master.debian.org (source indépendante de l'image d'amorce, qui n'est pas signée). L'`InRelease` de l'instantané `20261105T000000Z` porte exactement trois signatures valides, vérifiées par `gpgv` :
  - la clé d'archive 12/bookworm (`B8B80B5B…47F8`) ;
  - la clé d'archive 13/trixie (`04B54C3C…88BD`) ;
  - la clé de release 13/trixie (`41587F7D…9DE4`).
- **`Packages.xz`** est conforme à `InRelease`. Versions présentes dans l'instantané :
  - sbuild et libsbuild-perl `0.89.3+deb13u4`, mmdebstrap `1.5.7-1+deb13u1`, uidmap `1:4.17.4-2` ;
  - golang-go `2:1.24~2`, nodejs `20.19.2+dfsg-1+deb13u2`, debhelper `13.24.2`, util-linux `2.41.5-0+deb13u1`.
- **HTTP** : `http://snapshot.debian.org/…/InRelease` répond par une redirection 302 vers `/file/<sha1>` du même hôte, puis 200. L'amorce n'a pas de certificats ; l'intégrité vient de la signature.
- **Sources de sample-app** : `~/.cache/supply-chain-poc/packaging` existe, avec `SHA256SUMS`, et date du 29/10/2026. Le dernier commit de `poc/sample-app` est du 28/10/2026.

## Périmètre

- Le chroot de sbuild contient déjà les dépendances de build (debhelper, golang-go, nodejs). **Ce n'est pas la fermeture D2 (a)**, prévue en S2. S1 ne conclut rien sur le caractère bit-identique.
- L'instantané n'est lu que dans `main` de trixie, sans `trixie-security`.
- Les replis 1 à 3 du README ne sont pas lancés par ce script. Chacun demanderait sa propre prédiction et un accord.

## Prédictions

| # | Étape | Prédit | Confiance |
|---|---|---|---|
| P1 | prealables | Exemption de kata lue. Quatre specs admises en dry-run : racine, Kata privilégié, Kata avec escalade, runc restreint. Sources conformes. Trois signataires épinglés. Versions présentes. Plus de 1,5 Go libres pour Zot | haute (signatures et versions déjà lues sur l'hôte) |
| P2 | amorce | Copie dans Zot, digest identique à `7378260c…` | haute |
| P3 | racine | Un pod de `builds` sans label joint `snapshot.debian.org` en http : `apt-get update` réussit. **Si oui, c'est un constat** : aucune politique ne coupe la sortie Internet d'un pod de `builds` qui n'est ni `construire-image` ni `prefetch-gomod`. Aucune politique ne sera ouverte ni changée | moyenne |
| P4 | racine | L'`InRelease` lu par apt dans le pod a le même sha256 que celui vérifié sur l'hôte | haute |
| P5 | racine | `mmdebstrap --mode=root` produit les deux archives (racine minbase et chroot buildd) dans le pod Kata privilégié, sur le tmpfs `/w` | moyenne |
| P6 | racine | Les empreintes des .deb sont relevées par le crochet de personnalisation (le cache d'apt n'est vidé qu'après les crochets) et sont toutes conformes au `Packages` vérifié | faible pour la présence, haute pour la conformité |
| P7 | essais, Kata privilégié (D1 a) | NoNewPrivs 0, `/` en virtiofs sans `nosuid`, `newuidmap` en `-rwsr-xr-x root`. `unshare --user --map-auto` réussit : le bit setuid est un mode du fichier, transmis par virtio-fs, contrairement aux capacités de fichier de J7 | moyenne ; **contredit la prédiction 3 du README** (faible) |
| P8 | essais, Kata privilégié | `sbuild --chroot-mode=unshare` construit sample-app sans réseau ni mise à jour d'apt : statut `successful`, un deb | moyenne |
| P9 | essais, Kata avec escalade (D1 b) | NoNewPrivs 0 et `unshare --user --map-auto` réussit. Mais sbuild échoue au montage de `/proc` dans son espace, car les chemins de `/proc` sont masqués hors privilégié (`procMount` par défaut) | faible |
| P10 | essais, runc restreint (témoin) | NoNewPrivs 1. `unshare --user --map-auto` échoue (le setuid est sans effet), donc pas de sbuild | haute |
| P11 | durée | S1 coûte au plus 0,5 pw, préparation comprise (commencée à 12:53 UTC le 10/11, heure de la réponse « S1 de la 06 » dans la transcription). Brique estimée à 2 pw, décision à 4 pw | moyenne |

Pas de prédiction sur l'égalité du deb avec celui d'OBS (`0b489d43…`) : l'égalité n'est pas exigée (prédiction 2 du README).

## Résultat (exécuté le 10/11/2026 de 13:04:34 à 13:11 UTC, accord du propriétaire : « Oui, lance S1 »)

Journaux :
- [`s1-prealables.log`](s1-prealables.log), [`s1-amorce.log`](s1-amorce.log) et [`s1-racine.log`](s1-racine.log) ;
- [`s1-image.log`](s1-image.log) et [`s1-essais.log`](s1-essais.log).

Toutes les étapes ont rendu le code 0. Les quatre pods ont été supprimés.

**Écrit dans Zot, de façon définitive**
- `amont/library/debian@sha256:7378260c…` ;
- `essais-06/sbuild-debian13@sha256:1475738b58d99e87431dd8465239c69b4506648cd0a7511886204662501d7b3f`, en deux couches compressées de 128,6 Mo et 348,9 Mo. C'est moins que les 1,5 Go prévus, car crane compresse les couches.

| # | Mesuré | Verdict |
|---|---|---|
| P1 | Exemption de kata lue ; quatre specs admises en dry-run ; sources conformes ; trois signataires épinglés ; versions présentes ; 5 791 Mo libres sous `/` de sc-stockage | tenue |
| P2 | Amorce copiée, digest `7378260c…` relu dans Zot | tenue |
| P3 | `apt-get update` réussit en 5 s depuis un pod de `builds` sans label, en http, port 80, vers `snapshot.debian.org`. **Constat** : rien ne coupe cette sortie pour un pod de `builds` sans politique dédiée. Seuls ce port et cet hôte sont mesurés. Aucune politique n'a été changée | tenue |
| P4 | `InRelease` du pod : `0584fba3…`, identique à celui vérifié sur l'hôte | tenue |
| P5 | Racine : 336 Mo en 54 s. Chroot : 920 Mo en 69 s. Invité de 3 vCPU et 6 Go | tenue |
| P6 | Empreintes relevées pour 224 .deb (amorce 20, racine 93, chroot 111), toutes conformes au `Packages` vérifié | tenue |
| P7 | Kata privilégié, UID 1000 : NoNewPrivs 0 ; `/` en `virtiofs rw,nodev`, **sans `nosuid`** ; `newuidmap` et `newgidmap` en `-rwsr-xr-x root`. `unshare --user --map-auto` réussit : `uid_map 0 100000 65536` | tenue ; **prédiction 3 du README réfutée** |
| P8 | `sbuild` sort avec le code 2 en 57 s, sur « Build failure (dpkg-buildpackage died with exit 2) ». Le détail est resté dans le journal `.build` du pod, supprimé sans copie : défaut du script | **réfutée** |
| P9 | Kata avec escalade (D1 b) : NoNewPrivs 0, bounding set `a80425fb`. **`newuidmap` échoue** : « write to uid_map failed: Operation not permitted ». sbuild n'est pas lancé. Cause non diagnostiquée | **réfutée** (échec plus tôt que prédit) |
| P10 | runc restreint : NoNewPrivs 1, Seccomp 2. `unshare` échoue dès la création de l'espace utilisateur (« unshare failed: Operation not permitted ») : `newuidmap` n'est jamais appelé | **tenue sur l'issue, motif réfuté** |
| P11 | 21 min, de 12:53 à 13:14 UTC, préparation et consignation comprises | tenue à ce stade |

**Lecture**
- **Le risque principal de la 06 est levé pour D1 (a).** Dans un pod Kata privilégié, `/` est monté sans `nosuid`, et le setuid de `newuidmap` agit. Le mode `unshare` de sbuild y dispose donc de ses deux binaires.
- Les replis 1 à 3 du README deviennent sans objet pour `newuidmap`. Ils ne seront pas lancés.
- **D1 (b) est écarté** : `newuidmap` échoue hors privilégié. D1 (a) reste.
- **Déduction, non mesurée** : la mise en place du chroot et des dépendances par sbuild a réussi, puisque sbuild n'appelle `dpkg-buildpackage` qu'après ces étapes. Ce qui a échoué dans le build n'est pas connu.

**Diagnostic statique de P8**, sur l'hôte seul, sans rien exécuter des archives :
- le chroot porte Go `go1.24.4` (`/usr/lib/go-1.24/VERSION`) ;
- `go.mod` demande `go 1.24`, et `vendor/modules.txt` contient chi v5.2.3, `go 1.20` ;
- OBS a construit le même `.dsc` avec golang-1.24-go 1.24.4, nodejs 20.19.2+dfsg-1+deb13u2 et debhelper 13.24.2 ([`_buildenv`](../../../benchmarks/obs/resultats/build-v1/debian_13/_buildenv)), les mêmes versions que ce chroot. **L'hypothèse d'une incompatibilité de versions ne tient pas.**

**Push oublié dans l'additif de 13:03** : le push de 12:50:22 UTC (`f4eecab..9e8e1a3`, contrôle des secrets OK sur 6 fichiers) n'y était pas consigné. Il l'est ici.

## Relance du seul essai Kata privilégié : prédictions (écrites le 10/11/2026 à 13:14 UTC, avant toute exécution), NON LANCÉE

Le script a une nouvelle étape, `relance`. Elle rejoue la même sonde dans le seul pod Kata privilégié, puis copie le journal `.build` de sbuild dans `s1-relance-sbuild.log`, sans les lignes `jeton|token`, avant de supprimer le pod.

Ce script modifié n'est pas celui qu'a accordé « Oui, lance S1 ». La relance attend donc un accord nommé.

| # | Prédit | Confiance |
|---|---|---|
| RL1 | `unshare --user --map-auto` réussit de nouveau | haute |
| RL2 | sbuild échoue de nouveau, avec le code 2 : rien n'a changé | haute |
| RL3 | Le journal `.build` nomme la commande en échec. C'est une commande de `debian/rules` (`dh` ou une surcharge), pas la mise en place du chroot | moyenne |

### Résultat de la relance (13:22:02 UTC, accord : « Oui, relance » ; [`s1-relance.log`](s1-relance.log), [`s1-relance-sbuild.log`](s1-relance-sbuild.log))

| # | Mesuré | Verdict |
|---|---|---|
| RL1 | `unshare --user --map-auto` rc 0, `uid_map 0 100000 65536` | tenue |
| RL2 | sbuild rc 2 en 52 s, même message | tenue |
| RL3 | L'échec est dans la mise en place du réseau par sbuild, avant `dpkg-buildpackage`. `sbuild-usernsexec` ne trouve pas `ip` (« Can't exec "ip": No such file or directory », ligne 410) pour `ip link set lo up`. Build-Time 1 s | **réfutée** |

**Cause mesurée** : `iproute2` n'est pas dans l'image. Ce n'est qu'une recommandation de sbuild, que mmdebstrap n'installe pas (« Recommends: … uidmap, mmdebstrap (>= 1.4.0), iproute2 » dans le `Packages` vérifié). uidmap et mmdebstrap avaient été inclus à la main, mais pas iproute2. **Défaut de préparation, pas une limite de Kata.**

Autre ligne relevée : « cannot bind-mount /dev/console as it does not exist outside the chroot », répétée. C'est un avertissement, qui n'arrête rien.

## Second passage `s1b` (iproute2) : prédictions (écrites le 10/11/2026 à 13:24 UTC, avant toute exécution), NON LANCÉ

Ce que fait le script :
- **Racine** : il la reconstruit avec `iproute2=6.15.0-1`, version présente dans le `Packages` vérifié.
- **Chroot de sbuild** : il réutilise celui du premier passage (`GARDER_CHROOT=1`), contrôlé par son sha256 `440ba93b…`.
- **Image** : il la pousse dans Zot sous `essais-06/sbuild-debian13:s1b`. **C'est une nouvelle écriture définitive**, d'environ 130 Mo si la couche du chroot est reprise à l'identique.
- **Relance** : il rejoue l'essai Kata privilégié seul.
- **Journaux** : ils vont dans `s1b-*.log`, et ceux du premier passage ne sont pas réécrits.

Les effets sont un pod Kata root pour mmdebstrap, un pod Kata pour l'essai et cette écriture dans Zot. Ils attendent un accord nommé.

| # | Prédit | Confiance |
|---|---|---|
| B1 | `racine` : `iproute2` installé ; les empreintes de tous les .deb sont conformes au `Packages` vérifié | haute |
| B2 | `image` : couche du chroot identique au premier passage (`sha256:1744236b…`), puisque l'archive est la même, le tar déterministe et la compression de crane sans date. Seule la couche de la racine change | moyenne |
| B3 | `relance` : `ip link set lo up` réussit ; sbuild construit sample-app, statut `successful`, un deb dont le sha256 est relevé | moyenne |
| B4 | L'avertissement `/dev/console` reste, sans effet sur le build | haute |

Pas de prédiction sur l'égalité du deb avec celui d'OBS (`0b489d43…`).

### Résultat de s1b (13:24:34 à 13:28 UTC, accord : « Oui, lance s1b »)

Journaux : [`s1b-racine.log`](s1b-racine.log), [`s1b-image.log`](s1b-image.log), [`s1b-relance.log`](s1b-relance.log) et [`s1b-relance-sbuild.log`](s1b-relance-sbuild.log).

**Écrit dans Zot, de façon définitive** : `essais-06/sbuild-debian13@sha256:d8041f9cf7254a1e73523dc1b01e4065c0c9f9f4e7f8c9dc4e3c5fd656f495a1`, avec le tag `s1b`. Seule une nouvelle couche de 132,3 Mo a été poussée.

| # | Mesuré | Verdict |
|---|---|---|
| B1 | `iproute2_6.15.0-1` installé, avec sa dépendance `libcap2-bin`. 127 .deb (amorce 20, racine 107), tous conformes au `Packages` vérifié | tenue |
| B2 | Couche du chroot identique au premier passage (`sha256:1744236b…`). La couche de la racine change (`sha256:0afc00f4…`) | tenue |
| B3 | sbuild rc 0 en 79 s, statut `successful`, Build-Time 20 s. Un seul deb : `sample-app_1.0.0-1_amd64.deb`, sha256 `0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5`, mesuré dans le pod et repris par les `.changes` | tenue |
| B4 | 222 lignes `cannot bind-mount /dev/console`, sans effet sur le statut | tenue |

**Fait sans prédiction** : le deb est **identique, octet pour octet, à celui d'OBS** (`0b489d43…`). Les 64 caractères sont comparés à `0b489d438370ddb6b55d541829a3ffd480642fea524db6a3defcf802097551e5`, relevé pour OBS dans [`build-1/construire.log`](../../../benchmarks/obs/resultats/build-1/construire.log), ligne 77, et dans [`build-5/horsligne.log`](../../../benchmarks/obs/resultats/build-5/horsligne.log). Le même `.dsc` a été construit avec les mêmes versions de Go, de nodejs et de debhelper, dans deux constructeurs différents : sbuild en mode unshare sous Kata, et OBS.

## Conclusion de S1 (écrite le 10/11/2026 à 13:29 UTC)

**Mode retenu : `sbuild --chroot-mode=unshare` dans un pod Kata privilégié (D1 a), sous un compte non root (UID 1000).**

**Pourquoi ce mode**
- `newuidmap` et `newgidmap` agissent par leur bit setuid, car `/` est monté sans `nosuid` dans l'invité.
- Le réseau serait coupé par sbuild pendant le build : c'est ce que dit son manuel (`--no-enable-network`, actif par défaut en mode unshare), **pas une mesure**. sbuild a seulement lancé `ip link set lo up` dans son propre espace. Le test négatif « sortie réseau pendant le build » est prévu en S5.

**Ce qui est écarté**
- **D1 (b)** : `newuidmap` y échoue, avec EPERM sur `uid_map` (cause non diagnostiquée).
- **Les replis 1 à 3 du README** : sans objet.

**Ce que l'image doit contenir** : `iproute2` en plus de sbuild, mmdebstrap et uidmap.

**Reste pour S2 et la suite**
- La fermeture D2 (a). Ici, le chroot portait déjà les dépendances de build.
- La reproductibilité de la racine et du chroot.
- La place de l'image sous `builders/`.
- Le constat P3 (sortie http d'un pod de `builds` sans label), soumis au propriétaire.

**Durée** : de 12:53 à 13:29 UTC, préparation, trois exécutions et consignation comprises, pour 0,5 pw prévue (P11 tenue).

*Corrigé à 13:30 UTC, avant tout push, sur relecture du conseiller* :
- **Coupure du réseau** : la conclusion la présentait comme mesurée. Elle vient du manuel de sbuild, et le texte le dit maintenant.
- **Égalité avec OBS** : l'empreinte complète du deb est comparée, avec les journaux d'OBS qui la portent.
- **Fichiers non rapatriés** : le `.deb`, le `.buildinfo` et les `.changes` sont restés dans le pod ; seul le journal `.build` a été copié. La prochaine étape devra copier `/w/sortie` avant de supprimer le pod. Deux besoins en dépendent : la question de la 07a (Syft indique-t-il `distro=` sur un deb isolé ?) et la résolution de S2 depuis un `.buildinfo`.
