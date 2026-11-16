# Brique 06, révision 1.0.0-2 : étape lintian, prédictions (écrites à 2026-11-16T16:58:08Z, préparées à sec, « Oui, prépare-le ») : NON LANCÉ

Script : [`../lintian.sh`](../lintian.sh), nouveau. Cinq étapes, une par appel, **chacune sur accord nommé**, code relevé juste
après. Rien n'a été lancé, rien n'a été téléchargé, rien n'est installé au niveau système.

## Origine et décisions
- **Étape 6 de la séquence d'après S5b** : le tag lintian `missing-static-built-using-field-for-golang-package` doit disparaître
  avec la révision 1.0.0-2 (`Static-Built-Using: ${misc:Static-Built-Using}` dans `debian/control`). Décision des axes 1 et 2 de
  la 13a, du 12/11/2026.
- **Ébauche reprise** : constats et brouillon du 12/11/2026 (à partir de 22:07:30 UTC), écrits hors dépôt dans
  `~/.cache/supply-chain-poc/13a-axes12-esquisse/esquisse/lintian-predictions.md` ; ils sont repris ici. Lus alors dans lintian
  2.122.0 sur salsa, et relus par `juger` dans le paquet installé :
  - la règle (`Lintian/Check/Languages/Golang/BuiltUsing.pm`) juge la **source** : elle n'agit que si `Build-Depends` satisfait
    `golang-go | golang-any`, et sort le tag pour chaque paquet binaire d'architecture autre que `all` dont `Static-Built-Using`
    ne contient pas le littéral `${misc:Static-Built-Using}` ; l'entrée est donc le `.dsc`, pas le `.deb` ;
  - le tag est de sévérité `info`, masquée par défaut (il faut `-I`) ;
  - le code de sortie vaut 2 dès qu'un tag `E:` sort, 1 pour une erreur d'exécution : le jugement porte sur la ligne du tag.
- **Décision du propriétaire du 12/11/2026 (22:14:45 UTC), « Chroot à part »** : le chroot de build et `verrou-deb.txt` ne changent
  pas ; lintian tourne dans un chroot à part, même suite, même instantané `20261105T000000Z`, avec sa propre fermeture verrouillée.
  Inscrite hors dépôt, dans la même ébauche, et reprise ici.
- **Décisions du propriétaire du 16/11/2026** :
  - base du chroot : **racine de S1** (« Racine de S1 (Recommandé) ») ;
  - lintian n'a aucun verdict dans `docs/04-sante-projets.md` : **relevé de santé d'abord** (« Relevé de santé d'abord
    (Recommandé) »), à préparer sur accord et à faire **avant tout lancement** de ce script.

## Mesures à sec qui fondent le choix de la base (16/11/2026)
- **Racine de S1** `~/.cache/supply-chain-poc/08/travail/s1-06/racine.tar` : sha256 `f8f221ca…`, égal à
  [`s1b-racine.log`](s1b-racine.log) l. 139 (mmdebstrap sur l'instantané, 10/11/2026). 166 paquets installés, **tous égaux à
  l'index** (nom, version, architecture) ; lintian absent ; 8 nœuds de périphérique sous `./dev` (non extraits : `mknod` est
  refusé dans l'espace de noms, `/dev` de l'hôte est lié). Ses listes d'apt sont celles de l'index vérifié : InRelease
  `0584fba3…` ([`s1-prealables.log`](s1-prealables.log)), Packages `4f2c68d6…`, listé dans cet InRelease et égal à
  `Packages.xz` (`7778d3e3…`) décompressé. `sources.list` : l'instantané seul.
- **Amorce écartée** `debian:trixie-20261104-slim` (`7378260c…`, en cache) : 78 paquets, dont 7 hors de l'index, plus récents
  (`apt` et `libapt-pkg7.0` 3.0.4, `liblzma5`, `libpcre2-8-0`, `libssl3t64`, `openssl-provider-legacy`, `tzdata`).
- **Sources jugées** :
  - 1.0.0-1, témoin : `.dsc` `9050679e…` (copie hors dépôt du 12/11 ; même sha256 que
    `poc/benchmarks/obs/resultats/build-4/debian_13/sha256.txt` l. 2) ;
  - 1.0.0-2 : `.dsc` `ee2a6b8e…`, celui de `sources.sh` ([`revision-sha256sums-s1-option1.log`](revision-sha256sums-s1-option1.log)
    l. 16). **Ce n'est pas le `.dsc` de D** (`b284bd60…`, produit dans la pipeline, absent de l'hôte) : les deux ont le même orig
    (`1591a05b…`) ; leurs `.debian.tar.xz` ont « mêmes membres, tailles et dates », le groupe sans écriture dans la pipeline
    (`s4d-prealables.log` l. 55 à 58). Le tag ne lit que `debian/control` : `juger` le compare au blob de HEAD de
    `poc/packaging/debian/control`. Ce fichier n'a pas changé depuis `593cee4` (2026-11-14T21:55:57Z), avant S4c (22:18:38Z,
    [`s4c-verrou.log`](s4c-verrou.log)), qui a produit l'artefact de packaging `f0ed7a71…` dont D est construit : c'est ce lien
    qui rattache le jugement à D. Mesuré à sec : `debian/control` de 1.0.0-2 égal à
    `poc/packaging/debian/control` (`cmp`), littéral `Static-Built-Using: ${misc:Static-Built-Using}` à la l. 13 ; aucun
    `Static-Built-Using` dans celui de 1.0.0-1 ; `Build-Depends` contient `golang-go (>= 2:1.24~)` ; `Architecture: amd64`.
  - L'orig a changé entre les deux révisions (`07521c1e…` puis `1591a05b…`), déjà consigné (`revision-predictions.md`, note de
    l'option 1) : sans effet sur ce tag.
- **Fermeture estimée** (outil `lintian_fermeture.py` de l'ébauche, base = les 166 paquets de la racine, résolution simplifiée,
  première alternative) : **168 paquets, 25 695 012 octets**. Ordre de grandeur seulement : le verrou vient d'apt (`resoudre`).
  Aucun de ces 168 paquets n'a de `Pre-Depends` (lu dans Packages) : `dpkg -i` du lot entier ne bute pas sur un `Pre-Depends`
  interne non configuré.

## Commandes (racine du dépôt), dans l'ordre, chacune sur accord nommé
0. Avant tout : relevé de santé de lintian pour `docs/04`, sur accord (décision du 16/11).
1. `poc/bricks/06-deb-sbuild/lintian.sh prealables` (hors réseau).
2. `poc/bricks/06-deb-sbuild/lintian.sh resoudre` (hors réseau) ; puis **commit du verrou** `lintian/verrou-lintian.txt` et du
   journal.
3. `poc/bricks/06-deb-sbuild/lintian.sh telecharger` (réseau : snapshot.debian.org en https ; refusé si le verrou n'est pas
   commité ou a changé).
4. `poc/bricks/06-deb-sbuild/lintian.sh installer` (hors réseau).
5. `poc/bricks/06-deb-sbuild/lintian.sh juger` (hors réseau).

## Prédictions
| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| Y1 | `prealables` | Signataires d'InRelease : les trois clés épinglées ; InRelease `0584fba3…` ; Packages `4f2c68d6…` listé et égal à `Packages.xz` décompressé ; lintian `2.122.0` dans l'index ; racine `f8f221ca…`, listes et `sources.list` égaux ; 166 paquets, 0 hors index, lintian absent ; 8 nœuds de périphérique ; `.dsc` `9050679e…` et `ee2a6b8e…`, chaque fichier de leurs `Checksums-Sha256` égal ; `bilan : tout OK`, code 0 | Haute : chaque valeur mesurée à sec le 16/11, sauf gpgv (S1, 10/11) |
| Y2 | `resoudre` | `apt-get -s` code 0, aucune ligne `Remv`, aucune mise à jour ; lintian `2.122.0 all` dans le verrou ; chaque paquet du verrou dans l'index ; nombre de paquets entre 130 et 200, environ 26 Mo | Moyenne : premier apt dans la racine en espace de noms ; le nombre vient d'une résolution simplifiée |
| Y3 | `telecharger` | Chaque `.deb` égal au verrou (sha256 et taille) ; autant de fichiers que de lignes du verrou ; code 0 | Moyenne : disponibilité de snapshot.debian.org |
| Y4 | `installer` | `dpkg -i` code 0 ; tous les paquets `ii` ; installés = racine + verrou ; lintian `2.122.0` ; `dpkg --audit` vide | Moyenne : scripts de maintenance dans l'espace de noms, sans systemd, et `chroot` de l'hôte (uutils) jamais employé ici ; aucun `Pre-Depends` dans la fermeture estimée |
| Y5 | `juger` | `lintian -I` sur le `.dsc` 1.0.0-1 (témoin) : **une** ligne `I: sample-app source: missing-static-built-using-field-for-golang-package` (suite de la ligne non prédite) ; condition de validité de Y6 | Haute : règle lue, un seul paquet binaire `amd64` |
| Y6 | `juger` | `lintian -I` sur le `.dsc` 1.0.0-2 : **aucune** ligne de ce tag ; n'a de valeur que si Y5 tient | Haute : littéral mesuré dans `debian/control` |
| Y7 | `juger` | `lintian` sans `-I` sur les deux `.dsc` : aucune ligne de ce tag (témoin de la sévérité) | Haute |
| Y8 | `juger` | Règle et fichier de tag trouvés dans le lintian installé, sévérité `info` (champ `Visibility` ou `Severity`, nom non relu pour 2.122.0) ; `debian/control` de 1.0.0-2 égal au blob de HEAD ; codes de lintian 0 ou 2 ; aucune autre forme de ligne qui nomme le tag ; `bilan : tout OK` | Haute pour `debian/control` (mesuré) ; moyenne pour les codes |

Les autres tags (E, W, I) ne sont pas prédits un par un : ils sont relevés tels quels dans le journal, et chacun sera décidé à
part. Les sorties d'erreur de lintian (root projeté) sont relevées, pas prédites.

## Effets
- Écritures : `~/.cache/supply-chain-poc/06/lintian/` (racine extraite, environ 345 Mo, plus environ 26 Mo de `.deb` et
  l'installation), `lintian/verrou-lintian.txt` (par `resoudre`), journaux `resultats/lintian-<étape>.log`, `chrono.tsv`.
- Rien au niveau système, rien dans le cluster, dans Zot, ni sur `sc-stockage`. Une seule étape joint le réseau : `telecharger`.

## Cas d'échec
- Y5 non tenue (tag absent sur le témoin) : Y6 ne prouve rien ; arrêt et lecture de la règle installée.
- Y6 non tenue (tag présent sur 1.0.0-2) : écart sur l'objet de la révision ; arrêt et décision.
- Code 1 de lintian, ou KO d'une étape : arrêt au premier non nul, rien de rattrapé sans nouvel accord.

## Contrôles à sec faits (16/11/2026)
- `bash -n` et shellcheck (`-S warning`) de `lintian.sh`, sans avertissement. Relu par le conseiller : `curl -L` limité à https
  (comme `s1.sh` l. 120, 124), nom du champ de sévérité accepté sous ses deux formes, comparaison au blob de HEAD.
- Partie Python du script passée sur des copies de l'index et des statuts : `lintian` → `2.122.0` ; racine → `166 0 0` ;
  amorce → `78 7 0` ; simulation fabriquée à deux lignes `Inst` → verrou écrit, sha256 et chemins de l'index ; témoins négatifs
  refusés (code 1) : mise à jour `Inst apt [3.0.3] (3.0.4 …)`, paquet absent de l'index, ligne `Remv`.
- Analyse du statut de dpkg par `awk` (`installer`) : 166 lignes sur la racine, égal à Python.
- Espace de noms éprouvé sur un dossier vide du scratchpad : root projeté (UID 0), seule interface `lo`, `/dev` de l'hôte lié par
  `mount --rbind`.
- Non éprouvés : `chroot` dans la racine, apt et dpkg dans l'espace de noms, lintian.
