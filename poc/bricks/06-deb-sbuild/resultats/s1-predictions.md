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
