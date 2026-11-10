# Brique 06, S3 : prédictions (écrites le 10/11/2026, terminées à 16:45 UTC, avant toute exécution dans le cluster ou Zot)

Le script est [`s3.sh`](../s3.sh). **Rien n'a été lu ni écrit dans le cluster, Zot ou les VM pour S3.**

## Accord

Le propriétaire a répondu « continue » à 16:36:51 UTC (transcription), après le push de 16:32:36 UTC. « Continue » n'autorise aucune action sur le cluster, Zot ou les VM. La préparation de S3 à sec est donc la seule suite engagée.

**Sans accord** : l'étape `simulation`, lancée à 16:44:06 UTC, code 0. Elle tourne sur l'hôte seul, avec apt sous `unshare -rn` (seule interface : `lo`), sur des fichiers déjà présents de S2.

**Avec un accord nommé pour chaque étape**
- `restauration` : lecture dans Zot, deux pulls par digest de `deps/sample-app/deb-buildinfo@sha256:3a0e54ae…`, chacun dans un répertoire vide.
- `builds` :
  - deux pods Kata privilégiés, l'un après l'autre, UID 1000, dans `builds` sur sc-build ;
  - **sans label**, donc sous `builds-sans-internet` (08c) ;
  - image d'essai `essais-06/sbuild-debian13@sha256:d8041f9c…` (s1b) ;
  - chaque pod est supprimé à la fin de son build.
- `comparaison` : hôte seul, sans réseau ni cluster. Elle ne demande pas d'accord, mais n'a de sens qu'après `builds`.

Rien n'est écrit dans Zot en S3.

## Push consigné

Push de 16:32:36 UTC : `4072aee..fc4afa3`, 13 fichiers contrôlés par `tools/secrets-depot.sh` dans une copie temporaire, aucun secret.

## Lectures faites avant ces prédictions

**Code de sbuild 0.89.3+deb13u4**, lu dans l'archive `racine.tar` de S1 (`f8f221ca…`), extraite hors du dépôt :
- `--extra-package=<répertoire>` copie chaque `.deb` du répertoire dans le chroot. sbuild y construit un dépôt, déclaré `deb [trusted=yes] file://…` (`ResolverBase.pm`). D'où la revérification des empreintes dans le pod, juste avant sbuild : c'est la condition de D2 (a).
- **`--no-apt-update` ne rafraîchit que les dépôts internes de sbuild** (`APT_UPDATE_ARCHIVE_ONLY`, 1 par défaut). Le cache apt est ensuite régénéré avec **toutes** les sources du chroot.
- **Le chroot de S2 garde une source vers l'instantané.** Son `sources.list` pointe vers l'instantané, et `/var/lib/apt/lists/` en contient `InRelease` et `Packages` (liste de l'archive `e0b1f37c…`), à cause de `--skip=cleanup/apt/lists`. Sans précaution, apt verrait les mêmes versions dans deux sources, et pourrait choisir l'instantané.
- **`--chroot-setup-commands` tourne en root dans le chroot, avant la mise en place des dépôts internes** (`Build.pm`, `run_chroot_session_locked`). Chaque commande donnée en chaîne est découpée aux espaces, sans shell (`run_command`). Le script les utilise pour vider `sources.list` et retirer les deux listes de l'instantané, avec des noms exacts. En mode `unshare`, le chroot est redéballé à chaque build : l'archive garde son empreinte.
- **sbuild ne coupe le réseau que pour la commande de build.** `ENABLE_NETWORK` n'est passé qu'à `dpkg-buildpackage` (`Build.pm`). L'installation des dépendances par apt garde le réseau du pod. Pendant cette phase, **c'est Cilium qui coupe** (`builds-sans-internet` : refus des adresses publiques, DNS interne permis), d'où le pod sans label et le témoin TCP.
- **Chemin de build** : `BUILD_PATH` vaut `/build/reproducible-path` par défaut. Changer `--build-dir` ne change donc pas le chemin vu par le build.
- Le chroot sbuild se déballe sous `$TMPDIR` (`UNSHARE_TMPDIR_TEMPLATE`), donc dans le tmpfs `/w` du pod.

**Image** : l'image de s1b embarque `/opt/sbuild/trixie-amd64.tar`, le chroot de S1 (`440ba93b…`) avec debhelper, golang-go et nodejs préinstallés. S'en servir viderait le test. Le script copie donc le chroot de S2 (`e0b1f37c…`) dans `/w`, le revérifie dans le pod et le passe par `--chroot`. Le chroot embarqué reste dans l'image, inutilisé (question 1).

**Déjà observé avant ces prédictions, par l'étape `simulation`** (journal [`s3-simulation.log`](s3-simulation.log)). Ce ne sont pas des prédictions :
- apt de l'hôte (3.2.1 ; celui du chroot est 3.0.3) résout le paquet factice sur l'état dpkg du chroot de S2, avec la fermeture pour seule source ;
- il installe **48 paquets** ;
- avec les 114 paquets déjà dans le chroot, au même nom et à la même version, cela fait **exactement les 162 de Installed-Build-Depends**, sans paquet en plus ;
- liste archivée : [`s3-simules.txt`](s3-simules.txt).

Une première simulation, à la main dans le répertoire de travail de la session, entre 16:36:51 et 16:44:06 UTC, avait donné le même compte. Elle a échoué une fois avant, sur le bac à sable `_apt` d'apt sous `unshare -r`. Le script le désactive (`APT::Sandbox::User=root`), pour la simulation seulement.

**Effort** : les commits de la brique 06 s'étalent le 05/11 de 22:24 à 22:38 UTC, puis le 10/11 de 12:14 à 16:31 UTC. S1 et S2 ont été comptés 0,5 pw chacun. Le cumul reste loin du seuil de décision de 4 pw. C'est une estimation par les dates de commit, pas une mesure.

## Périmètre

- **Deux builds** : deux pods distincts, deux restaurations par digest dans deux répertoires vides de l'hôte, deux `--build-dir` (`/w/b1/sortie`, `/w/b2/sortie`). **Limite** : le chemin vu par le build est le même (`/build/reproducible-path`), et les deux pods iront sur le même nœud. S3 ne teste pas la reproductibilité à chemin variable.
- **Sources de sample-app** : celles de `packaging:sources`, contrôlées par `SHA256SUMS`, comme en S1.
- **Si les deux deb diffèrent** : ils sont gardés sur l'hôte. diffoscope n'est ni sur l'hôte ni dans l'image ; son installation se demande au propriétaire.
- Le code de sortie sera relevé sous bash (`bash -c '…; echo "rc $?"'`).

## Prédictions

| # | Étape | Prédit | Confiance |
|---|---|---|---|
| R1 | restauration | Deux pulls par digest, 162 fichiers chacun, tous conformes à la liste attendue | haute (Q11 de S2) |
| R2 | builds | Dans chaque pod : chroot `e0b1f37c…`, fermeture revérifiée par `sha256sum -c` (rc 0, 162 fichiers), sources conformes | haute |
| R3 | builds | Témoin DNS de `snapshot.debian.org` : rc 0. Témoin TCP vers `snapshot.debian.org:80` : échec. Code 124, délai de 10 s dépassé, paquets jetés par Cilium | haute pour l'échec ; moyenne pour le code 124 |
| R4 | builds | sbuild rc 0 sur les deux builds | moyenne : première fois avec `--extra-package` et `--chroot-setup-commands` ; découpage des commandes, droits du répertoire, tmpfs non essayés |
| R5 | comparaison | Aucune ligne `Get:` en http ou https dans les deux journaux de sbuild ; méthodes `copy` et `file` seulement | haute si R4 |
| R6 | comparaison | Paquets installés par sbuild (lignes `Setting up`, hors paquet factice) : les 48 de la simulation, aux mêmes versions | moyenne : apt 3.0.3 du chroot contre 3.2.1 de l'hôte ; paquet factice de sbuild reconstitué, pas lu |
| R7 | comparaison | Les deux deb sont identiques | haute (S1 et OBS) |
| R8 | comparaison | Le deb est `0b489d43…`, celui de s1b et d'OBS | haute : mêmes sources, mêmes versions des outils, même chemin de build |
| R9 | comparaison | Installed-Build-Depends des deux `.buildinfo` identique à celui de S2 (s1b) | haute si R6 |
| R10 | comparaison | Seul `Build-Date` diffère entre les deux `.buildinfo`, et entre celui de s1b et le build 1 | moyenne |
| R11 | durée | Chaque build dure moins de 5 min, copies comprises ; le tmpfs de 4 Gio suffit (environ 2 Go prévus) | moyenne |
| R12 | effort | S3 coûte au plus 0,5 pw, préparation comprise | moyenne |

**Ce que S3 ne prouvera pas**
- que sbuild coupe le réseau pendant le build : c'est le manuel, et le test négatif est prévu en S5 ;
- la reproductibilité à chemin de build variable ;
- la provenance, la signature et le deb dans Zot : c'est S4.

## Questions pour le propriétaire

1. **Chroot de S3.** Le script copie le chroot de S2 dans `/w` et garde l'image de s1b, dont le chroot embarqué reste inutilisé. Aucune écriture dans Zot. L'autre voie est une nouvelle image d'essai, avec ce chroot à sa place, et une écriture définitive dans Zot. Je recommande la copie dans `/w` pour S3, et l'image sous `builders/` pour S4.
2. **Sources de l'instantané neutralisées dans le chroot** pendant le build, par `--chroot-setup-commands`. La fermeture devient ainsi la seule source d'apt. Cela vous convient-il ?
3. **Accords nommés** : `restauration` (lecture dans Zot), puis `builds` (deux pods Kata privilégiés, sans label).

## Additif du 10/11/2026, 16:49 UTC : ordre de la simulation et corrections du script, avant tout push et tout lancement

**Ordre.** L'étape `simulation` de `s3.sh` a tourné à 16:44:06 UTC, **avant** l'écriture de ces prédictions, terminée à 16:45 UTC. Elle ne porte donc aucune prédiction : ses résultats sont classés plus haut en « déjà observés ».

L'en-tête du script, commité en `5525180`, affirmait des prédictions « écrites et commitées avant toute exécution ». C'était faux pour cette étape. L'en-tête est corrigé : l'affirmation vaut pour `restauration`, `builds` et `comparaison`.

**Lu en plus dans `Build.pm`, hors ligne**
- Le bloc qui ajoute de lui-même une source `deb-src` (« Automatically adding to EXTRA_REPOSITORIES ») ne sert que si sbuild tire les sources par apt. Ici, il reçoit un fichier `.dsc` (branche `DSC Base =~ m/\.dsc$/`) : aucune source n'est ajoutée après la neutralisation.
- Le contrôle d'architecture des paquets de `--extra-package` ne fait qu'avertir. Les 162 paquets sont `amd64` ou `all`.

**Script corrigé**, toujours avant tout lancement :
- **`comparaison` ne s'arrête plus au premier écart.** Chaque mesure s'imprime `OK` ou `ÉCART`, et le code final est 1 s'il y a eu au moins un écart.
- **R5 compte désormais toutes les lignes apt Get, Hit, Ign et Err en http ou https**, pas seulement Get. Une tentative réseau échouée s'écrit `Err:` ou `Ign:`.

| # | Étape | Prédit | Confiance |
|---|---|---|---|
| R13 | comparaison | Chaque journal de sbuild contient une fois `Finished running` pour chacune des deux commandes de neutralisation | haute si R4 |

