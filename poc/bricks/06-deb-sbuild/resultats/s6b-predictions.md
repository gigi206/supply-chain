# Brique 06, S6b, relevé 1 : prédictions (12/11/2026, rédigées à partir de 09:13:30 UTC, avant toute mesure)

Préparées sur « continue » (cadre : à sec, rien lancé). L'heure est celle de `date -u` au début de la rédaction ; l'heure du commit fait foi.

Décision du propriétaire (12/11/2026, 08:50:32 UTC), point 3 : le chroot est reconstruit dans `sc-replay`, avec mmdebstrap et sbuild installés par apt, versions épinglées, sans recommandés, comme `busybox-static` en R2. **L'installation aura son propre accord nommé.** Ce relevé ne l'est pas : il prépare l'épinglage.

**Rien n'est lancé.** Le relevé attend un **accord nommé**. Commande, depuis la racine du dépôt :

```
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh releve
```

Script : [`s6b.sh`](../s6b.sh). Journal : `s6b-releve.log`.

## Ce que le relevé touche

- **Hôte** : lecture anonyme de Zot (manifestes, tag `.att` du deb) ; écritures sous `~/.cache/supply-chain-poc/06/s6b` et dans `resultats/` seulement. La reconstruction du layout (H2) tourne hors réseau (`unshare -rn`).
- **`sc-replay`** : SSH avec les clés du domaine de la 10, comme `replay.sh`. La seule écriture est **`apt-get update`**, qui met à jour les listes d'apt sans installer aucun paquet. `apt-get install --assume-no` calcule ce qu'apt installerait et répond non. Le nombre de paquets installés est relevé avant et après.
- Rien dans le cluster, rien d'écrit dans Zot.
- Les signatures des provenances ne sont **pas** vérifiées ici : elles le seront dans le domaine, comme en R3 de la 10.

## Prédictions

- **H1, provenances du deb.** Le tag `sha256-039949f9….att` existe dans `builds/sample-app-deb`, avec au moins une couche, chacune de type `https://slsa.dev/provenance/v1` et de sujet `039949f9`. Le nombre de couches n'est pas prédit : le deb a pu être produit à nouveau par S4d3. `finishedOn` tombe le 11/11/2026, entre 19:28 et 21:05 UTC (`chrono.tsv` : pipeline de S4d1 lancée à 19:28:08, porte de S4d3 finie à 21:04:32). Le délai de 24 h de `vsa.py` est donc dépassé depuis le 12/11 à 21:05 UTC au plus tard. Les entrées résolues comprennent :
  - l'image de build `749d746c` ;
  - la fermeture deb `bb7599a2`, la fermeture des sources `50dc73f7` et le packaging `c1719b13` ;
  - le bundle de tâche `construire-deb` `3726ff0b`.

  Confiance moyenne, pour la liste exacte et la forme des URI.
- **H2, layout reconstruit à partir des seuls octets du deb.** Le manifeste reconstruit est identique, octet à octet, à celui de Zot, de digest `039949f9`. C'est la condition de `PASSED` (`politique-replay.md` §3) si le deb lui-même se reproduit. Confiance haute :
  - le tar de l'hôte (GNU tar 1.35) a la même version amont que celui de l'image de build (`tar 1.35+dfsg-3.1`, `builder/paquets.txt`) ;
  - toutes les options qui fixent le contenu sont explicites (`--sort`, `--format=posix`, `--pax-option`, `--mtime=@0`, propriétaire, mode 0644).

  Si H2 échoue, la reconstruction du layout devra se faire avec le tar du chroot, pas celui de la VM.
- **H3, entrées à transporter.** Les trois manifestes se lisent en anonyme. La fermeture deb est la plus lourde, avec la chaîne Go `golang-1.24` : entre 30 et 300 Mo. Le total reste sous 1 Go. Confiance moyenne : je n'ai pas relevé les tailles.
- **V1, ressources.**
  - 4 vCPU, environ 5,7 Gio de mémoire, 20 Go de disque, Debian 13 ;
  - au moins 10 Go libres sur `/` ;
  - ni mmdebstrap ni sbuild installés.

  Confiance moyenne pour la place libre, qui n'a pas été relevée depuis R4.
- **V2, espaces de noms sans privilège.** `max_user_namespaces` est non nul et `unprivileged_userns_clone` vaut 1 (noyau Debian). Aucune restriction AppArmor des espaces de noms : le fichier est absent ou vaut 0. Confiance moyenne. Pour `/etc/subuid` et `/etc/subgid` du compte `replay`, je prédis une ligne chacun, avec une confiance faible : le compte vient de cloud-init, et je n'ai pas vérifié s'il passe par `useradd`, qui ajoute ces lignes.
- **V3, apt.**
  - `apt-get update` réussit, sans avertissement de signature ;
  - candidats : mmdebstrap `1.5.7-1+deb13u1` et sbuild et `libsbuild-perl` `0.89.3+deb13u4`, les versions de l'instantané du 05/11/2026 (`builder/paquets.txt`), ou des versions plus récentes de `trixie-updates` ou `trixie-security` ;
  - uidmap `1:4.17.4-2` ;
  - `apt-get install --assume-no` répond non, code 1, et annonce entre 5 et 40 paquets nouveaux ;
  - le nombre de paquets installés est le même avant et après.

  Confiance moyenne pour les versions, faible pour le nombre de paquets.
- **V4, instantané depuis la VM.** `http://snapshot.debian.org/archive/debian/20261105T000000Z/dists/trixie/InRelease` répond 200 depuis la VM, et son sha256 est `0584fba3…`, celui de S1, puisqu'un instantané ne change pas. Confiance moyenne : la VM joint l'extérieur (R2 : `deb.debian.org`, HTTP 200), mais snapshot.debian.org limite parfois son débit.

## Ce que le relevé ne tranche pas

Ce sont des questions pour la suite, après le relevé.

1. **Source des paquets du chroot dans le domaine.**
   - La VM peut les tirer elle-même de snapshot.debian.org, en vérifiant la signature de l'archive avec le trousseau Debian de la VM et l'InRelease `0584fba3`. Le domaine ne dépendrait alors pas du miroir partiel de la plateforme : c'est plus indépendant.
   - Ou bien le miroir de la plateforme est transporté et revérifié dans la VM.

   La création du chroot se ferait lien établi ; le rebuild, lien coupé, comme en R4.
2. **Fermeture deb et sources.** Elles sont transportées comme en R3, sur un transport non fiable, puis revérifiées dans la VM contre la provenance vérifiée.
3. **Comparaison du chroot.** L'archive du chroot reconstruit pourrait être comparée, par son sha256, à la couche `opt/sbuild/trixie-amd64.tar` de `749d746c`. Ce serait une mesure de plus, que le contrôle 6 n'exige pas.

## Premier passage (12/11/2026, 09:16:23 UTC) : H1 à H3 mesurées, V1 à V4 non jouées

Lancé par le propriétaire depuis le terminal. Journal : `s6b-releve-premier-passage.log`.

**Arrêt.** La connexion SSH à `sc-replay` a été coupée avant l'authentification (« Too many authentication failures »). Rien n'a tourné dans la VM : ni `apt-get update`, ni aucune lecture. Ensuite, une connexion de diagnostic depuis ma session (`ssh -v … true`, entre 09:16:23 et 09:18 UTC ; heure exacte non relevée) a passé du premier coup avec la seule clé du domaine (« Server accepts key »). L'agent de ma session n'a qu'une clé.

**Cause : non établie.** L'hypothèse la plus probable est que l'environnement du terminal proposait d'autres clés avant celle du domaine. Je ne l'ai pas vérifiée. La correction ne dépend pas de la cause : `-o IdentitiesOnly=yes` dans `s6b.sh`, pour que seule la clé du domaine soit proposée. Le script corrigé demande un nouvel accord.

| # | Résultat | Mesure |
|---|---|---|
| H1 | **Tenue**, avec un écart de forme | Tag `.att` : **8 couches**, toutes `https://slsa.dev/provenance/v1` de sujet `039949f9`. **Quatre PipelineRuns**, chacun donnant deux provenances : celle de la pipeline (11 entrées) et celle de la TaskRun `publier-image` (2 entrées : `publier-image` `d21931f3`, `outils-horodatage` `c7bebae2`). PipelineRuns : `b9d4881e` (19:41:24 à 19:48:48 UTC), `629b6bb1` (19:48:57 à 19:55:56), `b0e14893` (20:49:00 à 20:56:26), `454728c5` (20:56:35 à 21:03:37). Le dernier `finishedOn` est **21:03:37 UTC le 11/11**, dans la fenêtre prédite : le délai de 24 h est dépassé pour toutes à partir du 12/11, 21:03:37 UTC. Les 11 entrées comprennent les cinq prédites (`749d746c`, `bb7599a2`, `50dc73f7`, `c1719b13`, `construire-deb` `3726ff0b`), plus la pipeline `sample-app-deb` `82c8373d`, `preparer-deb` `588617b8`, `outils-prefetch` `68e0ae70`, `outils-horodatage`, `publier-image` et le commit `6391fd43`. Les quatre provenances de pipeline ont les mêmes entrées. |
| H2 | **Tenue** | Couche reconstruite `12dd5c42…` (1 955 840 octets). **Manifeste identique, octet à octet, à celui de Zot ; digest `039949f9`.** Le layout se reconstruit donc à partir des seuls octets du deb, avec le tar de l'hôte. |
| H3 | **Tenue** | Fermeture deb `bb7599a2` : 167 couches, 226 446 597 octets (216 Mio). Fermeture des sources `50dc73f7` : 8 couches, 220 881 octets. Packaging `c1719b13` : 6 couches, 29 805 octets. Total : environ 227 Mo, sous 1 Go. |
| V1 à V4 | **Non mesurées** | Pas de connexion |

**Conséquences pour S6b**
- **Une provenance à retenir parmi quatre.** `vsa.py` en désigne une par son `invocationId`, comme `INVOCATION` pour l'image. Les quatre ont les mêmes entrées, donc la recette est la même. Le choix reste à faire avec toi. Le plus simple est la première, `b9d4881e` (S4d1), ou la dernière, `454728c5` (S4d3, rattrapage).
- **Ce qu'il faut reproduire.** H2 montre que `PASSED` ne dépend plus que de la reproduction du deb `0b489d43` dans le domaine. Le layout s'en déduit.

## Second passage (12/11/2026, 09:23:13 à 09:23:15 UTC, accord « Oui, lance S6b »), code 0

Journal : `s6b-releve.log`. H1 est identique au premier passage, ligne à ligne, et H2 et H3 donnent les mêmes valeurs.

| # | Résultat | Mesure |
|---|---|---|
| V1 | **Tenue** | 4 vCPU ; 5 931 Mo de mémoire, dont 5 444 disponibles ; `/` de 19 953 Mo, dont **13 306 Mo libres** ; Debian 13 (trixie), noyau 6.12.113+deb13 ; 339 paquets. mmdebstrap et sbuild absents. Le script affiche « déjà là : libsbuild-perl » sans version : dpkg connaît le nom, mais le paquet n'est pas installé (`apt-cache policy` : `Installed: (none)`). C'est un défaut d'affichage de mon script. |
| V2 | **Tenue** | `unprivileged_userns_clone` = 1, `max_user_namespaces` = 23555, pas de restriction AppArmor (fichier absent). `replay:100000:65536` dans `/etc/subuid` et dans `/etc/subgid`. |
| V3 | **Tenue, sauf le nombre de paquets (réfuté)** | `apt-get update` sans avertissement (910 kB). Candidats **identiques à l'instantané du 05/11** : mmdebstrap `1.5.7-1+deb13u1`, sbuild et `libsbuild-perl` `0.89.3+deb13u4`, uidmap `1:4.17.4-2`. `--assume-no` : code 1. Sans recommandés, **44 paquets nouveaux** (prédit : 5 à 40), 13,8 Mo à télécharger, 55,3 Mo sur le disque. Parmi eux : `dpkg-dev`, binutils, make, patch, gnupg, gpg-agent, dirmngr, et les modules Perl de sbuild. 339 paquets avant et après : rien d'installé. Apt signale aussi un paquet déjà installé à mettre à jour (« 1 not upgraded ») ; il n'est pas touché. |
| V4 | **Non jugée** (défaut du relevé) | L'URL de l'InRelease répond **HTTP 302**. Mon script n'a pas suivi la redirection (`curl` sans `-L`) : le sha256 `2774284c…` est celui de la page de redirection, pas celui de l'InRelease. La redirection est visible ; la joignabilité de l'instantané et l'identité de l'InRelease ne sont pas mesurées. La cible de la redirection n'est pas relevée : snapshot.debian.org pourrait renvoyer vers l'horodatage réel le plus proche ou vers https. |

**Conséquences pour l'installation** (pas encore demandée)
- Les versions à épingler sont celles de l'instantané, que l'image de build de la plateforme utilise aussi : `mmdebstrap=1.5.7-1+deb13u1`, `sbuild=0.89.3+deb13u4`, `libsbuild-perl=0.89.3+deb13u4`, `uidmap=1:4.17.4-2`. Elles s'épinglent comme en R2, sur les paquets demandés ; les 40 dépendances suivent les candidats de trixie.
- 55,3 Mo sur 13 306 Mo libres. Il reste à prévoir le chroot (509 Mo en S2), la fermeture (216 Mio), le build et ses copies : quelques Go au plus.
- Les espaces de noms sans privilège et les subuid sont en place pour `sbuild --chroot-mode=unshare` sous le compte `replay`. Il n'y a rien à changer au système.

## Étape `v4` préparée à sec (12/11/2026, rédigée à partir de 09:40 UTC, sur « continue »), NON LANCÉE

V4 n'a pas été jugée au second passage : `curl` n'avait pas `-L`, alors que `s1.sh` lit le même InRelease avec `curl -fsSL`. Je ne rejoue pas tout le relevé, ce qui écraserait `s6b-releve.log` et referait `apt-get update`. J'ajoute une étape `v4` à [`s6b.sh`](../s6b.sh), qui ne joue que la VM :
- **sans sudo** ni `apt-get update` : rien d'installé, et la seule écriture est un dossier temporaire, supprimé à la fin ;
- **V1c** : l'état dpkg de chaque paquet visé (`ii` installé, `un` connu mais non installé). Il remplace la ligne trompeuse « déjà là : libsbuild-perl ». Le format est vérifié sur l'hôte, où `libsbuild-perl` donne aussi `un` ;
- **V4a** : la cible de la redirection, sans la suivre ;
- **V4b** : l'InRelease lu en suivant les redirections, en http et https seulement, 5 au plus ; l'URL finale ; le sha256 comparé à celui de S1 ;
- **V4c** : la signature vérifiée par `gpgv` avec le trousseau `debian-archive-keyring` de la VM. Ce trousseau ne doit rien à la plateforme ni aux clés de ftp-master que S1 a lues sur l'hôte. Les signataires sont comparés à ceux de S1.

Commande, sur accord nommé (le script a changé) : `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh v4`. Journal : `s6b-v4.log`. `bash -n` passe sur le script et sur la partie VM.

**Prédictions**
- **V1c.** `mmdebstrap`, `sbuild`, `uidmap` et `schroot` : inconnus de dpkg ou `un` ; `libsbuild-perl` : `un`. `debian-archive-keyring` : `ii`. `gpgv` : `ii`, confiance moyenne, puisqu'il ne figure pas parmi les 44 paquets qu'apt ajouterait avec gnupg. Je ne prédis pas `ca-certificates`.
- **V4a.** HTTP 302, vers une URL de snapshot.debian.org sous `/archive/debian/<horodatage>/dists/trixie/InRelease`, avec un horodatage réel antérieur ou égal à `20261105T000000Z`. Confiance moyenne : la cible pourrait aussi être en https.
- **V4b.** Code 0, HTTP 200 après une redirection, sha256 `0584fba3…`, celui de S1. Confiance haute pour le sha256 : S1 a lu la même URL en suivant la redirection, et un instantané ne change pas. Si la cible est en https et que `ca-certificates` manque, `curl` échoue (code 60) : ce serait une mesure, pas un faux succès.
- **V4c.** Trousseau présent, `gpgv` présent, et les trois signataires de S1 (`04B54C3C…`, `41587F7D…`, `B8B80B5B…`). Confiance moyenne : si l'une de ces clés est plus récente que le trousseau de la VM, il en manquera une, et ce sera écrit tel quel.
- **Effets.** Rien d'installé ; aucune écriture dans le cluster ni dans Zot ; moins de 90 s.

### Note datée du 12/11/2026 (rédigée à partir de 09:44:18 UTC, après relecture du conseiller), avant tout lancement de `v4`

- **Défaut corrigé dans `s6b.sh`** : `sur bash -s … "$CLES"` passait les trois clés en trois arguments, puisque ssh recolle les arguments et que le shell distant les redécoupe. `$3` ne contenait que la première clé, et V4c aurait conclu « DIFFÉRENTS » même avec les trois bons signataires. Les clés sont désormais jointes par des virgules. Reproduit sur l'hôte, hors réseau : 5 arguments avant, 3 après, et les trois clés retrouvées.
- **`sqv` ajouté à V1c** : apt de trixie peut vérifier les signatures avec `sqv` plutôt qu'avec `gpgv`. Prédiction : je ne prédis pas lequel des deux est installé. Si `gpgv` manque, V4c ne vérifie rien et le dit, sans rien installer.
- **L'heure du titre de la section précédente** : « 09:40 » vient de `date -u` (09:40:56) ; le commit `844bf9e` est de 09:42:08 UTC.

## Résultats de `v4` (12/11/2026, 09:47:50 UTC, accord « 3 ok »), code 0

Journal : `s6b-v4.log` (`chrono.tsv` : début et fin à la même seconde). Aucune ligne `jeton|token`.

| # | Résultat | Mesure |
|---|---|---|
| V1c | **Tenue, sauf `gpgv` (réfuté)** | mmdebstrap, sbuild, uidmap et schroot inconnus de dpkg ; `libsbuild-perl` : `un`, ce qui explique la ligne « déjà là » du second passage. `debian-archive-keyring` `ii 2025.1`, `ca-certificates` `ii 20250419+deb13u1`. **`gpgv` : `un`, non installé ; `sqv` : `ii 1.3.0-3+b2`**. apt de la VM vérifie donc ses signatures avec `sqv`. |
| V4a | **Réfutée sur la forme de la cible** | HTTP 302 vers `http://snapshot.debian.org/file/aa33cb317177428f33c9ff72fc3e9b634645f6ae/InRelease` : un chemin par empreinte du magasin de fichiers de snapshot, en http, sur le même hôte. Je prédisais un chemin par horodatage. |
| V4b | **Tenue** | HTTP 200 après une redirection ; **sha256 `0584fba3…`, identique à celui de S1** ; `Date: Sat, 12 Sep 2026 07:55:41 UTC`. L'instantané est joignable depuis la VM. |
| V4c | **Non mesurée** | Trousseau trouvé : `/usr/share/keyrings/debian-archive-keyring.pgp` (le suffixe `.pgp`, prévu par le script). `gpgv` absent : signature non vérifiée, rien installé, comme le script le prévoit. |
| Effets | **Tenus** | Rien d'installé (sans sudo) ; aucune écriture dans le cluster ni dans Zot ; moins d'une seconde côté script. |

**Conséquences**
- L'empreinte suffit à l'identité : l'InRelease que la VM lit est celui que S1 a vérifié sur l'hôte avec les clés de ftp-master, octet pour octet.
- La signature n'est pas encore vérifiée **par le trousseau de la VM**. Dans la voie A, c'est apt, pendant mmdebstrap, qui la vérifie, avec `sqv` et ce trousseau : un échec y arrêterait le chroot. Le témoin préalable V4c reste à faire, avec `sqv`, dont je n'ai pas relevé la syntaxe : à lire dans la VM (`sqv --help`) avant d'écrire la commande.

