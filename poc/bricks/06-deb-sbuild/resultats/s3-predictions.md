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

## Résultat de l'étape restauration (10/11/2026, 16:49:42 à 16:49:43 UTC)

Accord : « Oui, lance restauration », à 16:49:38 UTC (transcription). Lancée sous bash, code de sortie relevé : **0**. Journal : [`s3-restauration.log`](s3-restauration.log).

| # | Résultat |
|---|---|
| R1 | **Tenue.** Deux pulls par digest de `deps/sample-app/deb-buildinfo@sha256:3a0e54ae…`, chacun dans un répertoire vide : 162 fichiers chacun, empreintes identiques à la liste attendue |

Lecture seule dans Zot ; rien n'y est écrit. **`builds` et `comparaison` ne sont pas lancées.** Les questions 1 et 2 restent ouvertes. `builds` attend un accord nommé.

## Étape builds, premier passage (10/11/2026, 16:52:09 UTC) : bloqué sur la copie du chroot, arrêté

Accord : « Oui, lance builds », à 16:51:59 UTC (transcription). La réponse ne disait rien des questions 1 et 2. Elle est consignée comme une interprétation, annoncée avant le lancement : un accord sur le chroot copié dans `/w` et sur la neutralisation des sources, tels qu'ils sont dans le script.

**Ce qui s'est passé** : le pod `s3-build-1` (Kata privilégié, sans label) a été prêt à 16:52 UTC. La copie du chroot par `kubectl exec -i … sh -c 'cat > /w/chroot.tar'` ne s'est pas terminée. À 17:42:00 UTC, le processus kubectl tournait depuis 2985 s. Côté hôte, il avait lu les 508 546 560 octets du fichier (position de son entrée standard) et écrit environ 509,7 Mo sur sa connexion.

La cause probable est que la fin de l'entrée standard n'est jamais parvenue à `cat` dans le pod. C'est **supposé, non vérifié** : vérifier aurait demandé une lecture dans le pod. Ce mode de copie a marché en S2 pour un fichier de 3,7 ko.

**Arrêt** : sur la réponse « Ok » (17:41:54 UTC, transcription) à « J'arrête l'étape et je supprime le pod s3-build-1 ? », consignée comme une interprétation (arrêt et nettoyage seulement, pas de rejeu) :
- kubectl local terminé à 17:42:00 UTC ; script arrêté en code 143 ;
- pod supprimé à 17:42:07 UTC.

Journal : [`s3-builds-1.log`](s3-builds-1.log).

**Aucune prédiction n'est mesurée.** sbuild n'a pas démarré, le build 2 et la comparaison n'ont pas tourné. R11 est déjà compromise sur la durée de ce passage, mais elle porte sur un build qui aboutit.

**Correction à sec, à 17:43 UTC, NON REJOUÉE** :
- chaque copie lit dans le pod le nombre d'octets exact (`head -c`), sous un délai de 600 s ;
- la taille écrite dans le pod est comparée à celle de l'hôte, et le pod est supprimé en cas d'écart ;
- les arborescences passent par une archive tar faite sur l'hôte ;
- l'exécution de sbuild est bornée à 1800 s.

Le rejeu de `builds` demande un nouvel accord, puisque le script a changé.

## Étape builds, deuxième passage (10/11/2026, 17:44:28 UTC) : même blocage, arrêté

Accord : « Oui », à 17:44:23 UTC (transcription), en réponse à « je rejoue l'étape builds avec les copies corrigées ? ». Journal : [`s3-builds-2.log`](s3-builds-2.log).

**Même blocage, sur la même copie.**
- Le pod `s3-build-1` était prêt.
- À 17:52:48 UTC, `kubectl exec -i … sh -c 'head -c 508546560 > /w/chroot.tar'` tournait depuis 494 s.
- Côté hôte, kubectl avait lu les 508 546 560 octets et écrit environ 509,7 Mo sur sa connexion.
- `head -c` n'a pas besoin de fin de flux. **L'hypothèse du premier passage, une fin de flux non reçue, tombe donc.** Reste, supposé et non vérifié : les octets envoyés n'arrivent pas tous dans le pod, ou n'y sont pas écrits.

**Arrêt** : sur « Arrête et propose » (17:53:40 UTC), kubectl local terminé à 17:53:47 UTC, avant le délai de 600 s.
- Le script a supprimé le pod lui-même et s'est arrêté en code 1 (« KO copie de chroot.tar »).
- Le pod était absent à 17:53:51 UTC.

**Aucune prédiction n'est mesurée.** sbuild n'a pas démarré. Le transfert vers le pod par l'entrée standard de `kubectl exec` est écarté pour un fichier de cette taille. Les copies réussies jusqu'ici dans ce sens ne dépassaient pas 4 ko. Une autre voie est à décider avec le propriétaire.

*Corrigé à 17:56 UTC, avant tout push* : « Les copies réussies jusqu'ici dans ce sens ne dépassaient pas 4 ko » est faux, et n'avait pas été mesuré. En S1 (`essais` et `relance`), l'archive tar des sources de sample-app est passée par l'entrée standard de `kubectl exec`. Ses trois fichiers font 140 171, 2 684 et 919 octets (relevé sur l'hôte à 17:56 UTC). Le plus gros transfert réussi dans ce sens fait donc environ 144 ko, contre 509 Mo pour le chroot. Le seuil d'échec reste inconnu.

## Sonde du transfert vers le pod : préparée à sec (18:01 UTC), NON LANCÉE

**Choix du propriétaire** : « Diagnostic d'abord », à 18:00:21 UTC (transcription), parmi l'image d'essai (A), la copie par morceaux (B), la restauration par oras (C) et le diagnostic. Cette réponse est consignée comme une interprétation : elle désigne la voie, et le lancement attend un accord nommé.

**Étape `sonde` de `s3.sh`**
- Fichiers aléatoires de 1, 8, 64 et 512 Mio, créés sur l'hôte.
- Chacun est copié par l'entrée standard de `kubectl exec`, avec `head -c` dans le pod et un délai de 120 s.
- Par copie, on relève : le code, la durée, les octets reçus dans le pod et le sha256 dans le pod.
- Deux pods, l'un après l'autre, UID 1000, sans label, image d'essai de s1b :
  - Kata privilégié, la forme des builds ;
  - runc en `restricted`, déjà admis en S1.
- Dans chaque pod, les tailles s'arrêtent au premier échec. La taille en échec est alors recopiée avec `KUBECTL_REMOTE_COMMAND_WEBSOCKETS=false`, en SPDY au lieu de WebSocket.
- kubectl client 1.35.10, serveur 1.35.9 (RKE2).
- Durée maximale d'environ 20 min, chaque pod supprimé à la fin. Rien n'est écrit dans Zot.

| # | Prédit | Confiance |
|---|---|---|
| D1 | 1 Mio passe dans les deux pods, sha256 conforme | haute : 144 ko sont passés en S1 |
| D2 | Dans le pod Kata, une taille entre 8 et 512 Mio échoue au délai, avec moins d'octets reçus qu'envoyés | moyenne : deux blocages à 509 Mo, seuil inconnu |
| D3 | Dans le pod runc, les quatre tailles passent | faible : le blocage peut venir du chemin apiserver, kubelet et conteneur, commun aux deux, plutôt que de Kata |
| D4 | En SPDY, la taille en échec passe | faible |
| D5 | Aucun pod ne reste après l'étape | haute |

**Ce que la sonde ne dira pas** : la cause exacte. Elle localise le blocage (taille, runtime, protocole) sans lire les journaux de kubelet, de containerd ou de Kata.

## Résultat de la sonde (10/11/2026, 18:02:04 à 18:06:32 UTC)

Accord : « Oui, lance la sonde », à 18:01:59 UTC (transcription). Lancée sous bash, code de sortie relevé : **0**. Journal : [`s3-sonde.log`](s3-sonde.log).

| Copie | Kata privilégié (WebSocket) | runc `restricted` (WebSocket) |
|---|---|---|
| 1 Mio | code 0, 242 ms, conforme | code 0, 101 ms, conforme |
| 8 Mio | code 0, 1 023 ms, conforme | code 0, 114 ms, conforme |
| 64 Mio | code 0, 7 196 ms, conforme | code 0, 505 ms, conforme |
| 512 Mio | **code 124** au délai de 120 s ; **536 870 912 octets reçus dans le pod** | code 0, 3 593 ms, conforme |

En SPDY, sous Kata, 512 Mio donne aussi le code 124 au délai, avec les 536 870 912 octets reçus.

| # | Résultat |
|---|---|
| D1 | **Tenue** dans les deux pods |
| D2 | **Tenue en partie.** Sous Kata, 64 Mio passe et 512 Mio échoue au délai. **Réfutée sur les octets** : le pod a reçu le fichier entier, ce qui n'avait pas été prédit |
| D3 | **Tenue.** Les quatre tailles passent sous runc ; 512 Mio en 3,6 s |
| D4 | **Réfutée.** SPDY échoue de la même façon |
| D5 | **Tenue.** Le pod runc, supprimé sans attente par le script, a disparu à 18:07:03 UTC, après le délai de grâce. Plus aucun pod `s3-` |

**Lecture**
- **Le blocage est propre à Kata.** Sous runc, sur le même nœud, avec la même image et le même chemin apiserver et kubelet, 512 Mio passe en 3,6 s.
- **Sous Kata, les octets arrivent, mais `kubectl exec` ne se termine pas.** Le protocole (WebSocket ou SPDY) n'y change rien. Je n'ai mesuré ni la fin de `head` dans le pod, ni l'heure d'arrivée du dernier octet : la cause reste inconnue. Elle est à chercher entre le shim Kata et l'agent dans l'invité, sans lecture de leurs journaux à ce stade.
- **Débit sous Kata** : 64 Mio en 7,2 s, environ 9 Mo/s, contre environ 150 Mo/s sous runc à 512 Mio.
- **Taille sûre mesurée sous Kata : 64 Mio**, sur un seul essai. Le seuil se situe entre 64 et 512 Mio.
- **Les deux passages de `builds` s'expliquent probablement de la même façon** : le chroot (509 Mo) était sans doute arrivé, et c'est l'exec qui ne rendait pas la main. Ce n'est pas mesuré pour ces passages.

## Copie par morceaux de 64 Mio : préparée à sec (18:10 UTC), NON LANCÉE

Choix du propriétaire : « Morceaux de 64 Mio », à 18:09:41 UTC (transcription), contre l'image d'essai (A).

**`copier` de `s3.sh`**
- Chaque fichier passe en morceaux de 64 Mio au plus : `dd` sur l'hôte, puis `head -c` ajouté au fichier dans le pod, avec un délai de 120 s par morceau.
- La taille cumulée est relevée dans le pod après chaque morceau.
- Le sha256 du fichier entier est comparé dans le pod à la fin.
- En cas d'écart, le pod est supprimé et l'étape s'arrête.
- Il faut 8 morceaux pour le chroot (508 546 560 octets) et environ 3 pour l'archive de la fermeture. Les autres fichiers tiennent en un seul.

La logique de découpage a été essayée sur l'hôte seul, avec des morceaux de 1 Mio : tailles de 1, 1 048 576, 3 670 017 et 4 194 304 octets, reconstituées avec un sha256 identique. Ce n'est pas une mesure dans un pod.

| # | Prédit | Confiance |
|---|---|---|
| E1 | Tous les morceaux passent sous Kata, avec le code 0, chacun en moins de 15 s ; tailles cumulées et sha256 conformes | moyenne : 64 Mio n'est passé qu'une fois, depuis un fichier et non depuis un tube |
| E2 | Les copies d'un pod prennent moins de 3 min au total (environ 9 Mo/s mesurés sous Kata) | moyenne |

R2 à R10, R12 et R13 sont inchangées. **R11 est précisée** : la limite de 5 min par build exclut les copies, que mesure E2.

## Résultat des builds et de la comparaison (10/11/2026, 18:11:00 à 18:23:43 UTC)

**Builds, troisième passage**
- Accord : « Oui, lance builds », à 18:10:54 UTC (transcription).
- De 18:11:00 à 18:23:23 UTC, lancés sous bash, code **0**.
- Journaux : [`s3-builds.log`](s3-builds.log), [`s3-build-1-sbuild.log`](s3-build-1-sbuild.log), [`s3-build-2-sbuild.log`](s3-build-2-sbuild.log). `.buildinfo` : [build 1](s3-build-1.buildinfo), [build 2](s3-build-2.buildinfo).

**Comparaison** : sur l'hôte seul, à 18:23:43 UTC, code **0**, aucun écart. Journal : [`s3-comparaison.log`](s3-comparaison.log).

| # | Résultat |
|---|---|
| E1 | **Tenue.** Toutes les copies passent sous Kata, morceau par morceau : chroot en 8 morceaux, archive de la fermeture en 3, le reste en 1. Tailles cumulées et sha256 conformes, dans les deux pods |
| E2 | **Tenue, d'après les heures relevées.** L'étape commence à 18:11:00 UTC. L'exec de build du pod 1 tournait depuis 124 s à 18:14:29 UTC, donc depuis environ 18:12:25. Démarrage du pod et copies ont pris moins de 90 s |
| R2 | **Tenue.** Dans chaque pod : chroot `e0b1f37c…`, fermeture revérifiée (rc 0, 162 fichiers), sources conformes |
| R3 | **Tenue, code 124 compris.** DNS rc 0 ; TCP vers `snapshot.debian.org:80` rc 124 (délai de 10 s), dans les deux pods |
| R4 | **Tenue.** sbuild rc 0 sur les deux builds, en 272 s et 274 s |
| R5 | **Tenue.** Aucune ligne apt Get, Hit, Ign ou Err en http ou https. 55 lignes `Get` par build : 51 `file`, 4 `copy` |
| R6 | **Tenue.** 48 paquets installés par sbuild dans chaque build, identiques à la simulation (nom et version) |
| R7 | **Tenue.** Les deux deb sont identiques |
| R8 | **Tenue.** Le deb est `0b489d43…`, celui de s1b et d'OBS |
| R9 | **Tenue.** Installed-Build-Depends des deux `.buildinfo` identique à celui de S2 (s1b) |
| R10 | **Tenue.** Seul `Build-Date` diffère, entre les deux builds comme entre s1b et le build 1 |
| R11 | **Tenue.** Chaque build dure moins de 5 min hors copies (272 et 274 s). Package-Time de 262 et 264 s, contre 69 s en s1b, où les dépendances étaient préinstallées. Le tmpfs a suffi |
| R12 | **Tenue.** S3 est passé de la préparation (16:36 UTC) aux builds réussis (18:23 UTC) en moins d'une demi-journée, incidents de copie compris |
| R13 | **Tenue.** Une ligne `Finished running` pour chacune des deux commandes de neutralisation, dans chaque journal |

**Jalon S3 tenu.**
- Deux builds sans accès à l'instantané, depuis la fermeture restaurée par digest, donnent le même deb, octet pour octet : `0b489d43…`.
- C'est aussi le deb d'OBS et de s1b.

**Limites, telles qu'écrites avant le lancement**
- Le chemin de build est le même (`/build/reproducible-path`), et les deux pods sont sur le même nœud.
- La coupure du réseau par sbuild pendant la compilation n'est pas testée : c'est S5.

L'incident de copie reste ouvert. Le propriétaire a demandé « il faut trouver ce qu'il se passe » (18:21:02 UTC) : un diagnostic est préparé à part.

## Additif du 10/11/2026, 18:48 UTC : correction de lecture de la sonde

**Correction de lecture** : « le blocage est propre à Kata » n'est pas établi. La comparaison runc/Kata change deux choses à la fois, le runtime et la vitesse de lecture du pod (environ 150 Mo/s sous runc, 10 Mo/s sous Kata). Sous Kata, kubectl a tout envoyé bien avant que le pod ait tout lu, et des centaines de Mo restent en attente dans la chaîne. Ce cas n'a jamais été mesuré sous runc. De même, « la quantité compte, pas la durée » est trop fort : l'envoi lent ne portait que sur 32 Mio, sous les 64 Mio qui passent. **La règle d'exploitation reste vraie** : sous Kata, un gros fichier ne passe pas par l'entrée standard de `kubectl exec`.

Le diagnostic qui a suivi est dans [`diag-exec-predictions.md`](diag-exec-predictions.md).

## Additif du 10/11/2026, 21:01 UTC : sonde rejouée après le retrait du tunnel (08b)

Accord : « 3, les deux », à 20:56:34 UTC (transcription). `s3.sh sonde` rejouée sans modification de 20:58:47 à 21:00:36 UTC, code 0. Nouveau journal : [`s3-sonde-direct.log`](s3-sonde-direct.log) ; [`s3-sonde.log`](s3-sonde.log) garde la mesure de 18:02 UTC, restaurée depuis git.

- **Kata : 512 Mio en code 0 en 54,8 s, sha256 conforme** ; à 18:02 UTC, la même copie ne rendait pas la main en 120 s, en WebSocket comme en SPDY ;
- runc : 512 Mio en 3,3 s, comme avant (3,6 s).

Le blocage de la sonde ne venait pas de Kata mais du chemin par le tunnel de l'agent RKE2, retiré par `egress-selector-mode: disabled` (08b). Le découpage en morceaux de 64 Mio reste dans `s3.sh` ; le retirer serait un changement à part. Prédictions D5 et D6 : [`egress-selector-predictions.md`](../../08b-rke2/resultats/egress-selector-predictions.md).
