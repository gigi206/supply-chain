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


## Additif de la révision 1.0.0-2, ligne 11 de la cascade (écrit à 2026-11-16T16:22:46Z, corrigé avant commit après relecture du conseiller, après « Oui, prépare-les ») : NON LANCÉ

VSA du deb D (`60f25f5c`, S4d3 du 15/11) au lieu de `039949f9`, sur la provenance `c3d27e05` (décisions du propriétaire, note de
2026-11-16T16:17:15Z de [`revision-predictions.md`](revision-predictions.md)). Correctif préparé et archivé, **non appliqué** :
[`revision-correctif-7.patch`](../revision-correctif-7.patch) (`s6b.sh` : `INVOCATION`, garde d'`etape_vsa` sur le sujet du
journal de `rebuild`, commentaires et message périmés ; `rejeu/politique-replay-deb.md` : nouvelle version, l. 16 et dernière
limite, section « Versions »). `rejeu/verifier_deb.py`, `rebuild_deb.sh` et `vsa_deb.py` ne changent pas : sha256 `7498fdad…`,
`55ebf681…` et `34799510…`, égaux à ceux des journaux du 12/11 ; le commentaire de `verifier_deb.py` (l. 3) qui cite `454728c5`
reste, sans effet. Hors du correctif, sans effet sur la ligne 11 (recherche `git grep` de `97ae561`, `6cc94a50`, `454728c5` et
`POLITIQUE_COMMIT` dans tout le dépôt) : mentions historiques de `docs/03-validation-briques.md`, des journaux et des prédictions du
12/11 ; `POLITIQUE_COMMIT` de `replay.sh` (brique 10, sa propre politique) ; `rejeu.sh` de la 08 n'appelle `pousser_vsa` et `lire_vsa`
qu'avec `POUSSER_VSA=1`, sans épinglage.

Commandes, chacune sur accord nommé, code relevé juste après, arrêt au premier code non nul (`s6b.sh` ne prend qu'une étape par
appel ; chaque étape réécrit `resultats/s6b-<étape>.log`, dont la version du 12/11 ou du 14/11 reste dans git) :
0. Correctif 7 appliqué tel quel, puis commité. **Ce commit fige la nouvelle politique** : c'est `POLITIQUE_COMMIT`. Il doit être
   poussé avant la commande 5 (push sur accord).
1. `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh transporter` (hôte : lectures anonymes de Zot et de Forgejo, copie dans
   `/home/replay/s6b/r3`, vidé d'abord).
2. `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh verifier` (VM). **Relecture du critère, décidable sur le journal** : la porte
   juge la provenance de PipelineRun au `finishedOn` le plus tardif (`prov_pr` de la 08, `max_by(finishedOn)`), et la porte de S5
   l'a mesurée le 16/11 : `c3d27e05`, avec 8 enveloppes sur D (`s5-porte.log` l. 4 et 9). Toute nouvelle exécution sur D ajouterait
   des enveloppes, donc des bundles. **Arrêt et décision si `verifier` ne compte pas exactement 8 bundles vérifiés, ou si
   `c3d27e05` n'est pas parmi eux.** Le journal ne montre ni la nature (PipelineRun ou tâche) ni `finishedOn` de chaque bundle :
   l'ordre des jetons de M3 est une prédiction, pas la règle d'arrêt.
3. `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh repetition` (VM, lien établi, non comptée). Elle n'était pas dans l'ordre noté le
   16/11 ; je l'ajoute, parce qu'elle peut passer avant le délai de 24 h et révèle un écart de reconstruction avant `rebuild`.
4. `ATTENTE_HORS_LIGNE=300 mise exec -- poc/bricks/06-deb-sbuild/s6b.sh rebuild` (lien de la VM coupé 300 s, comme le 12/11),
   pas avant `finishedOn` + 24 h, lu dans `verifie.txt` par la commande 2.
5. `POLITIQUE_COMMIT=<commit de la commande 0> mise exec -- poc/bricks/06-deb-sbuild/s6b.sh vsa` (VM, `unshare -rn`, signature
   par la clé du domaine ; rien dans Zot). Préalable : HEAD poussé.
6. `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh pousser_vsa` (accord propre à ce push ; compte `poc-replay`).
7. `mise exec -- poc/bricks/06-deb-sbuild/s6b.sh lire_vsa` (lecture anonyme).

`vsa_essai` n'est pas rejoué : ses trois refus ne dépendent pas du sujet (mesurés le 12/11).

| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| M1 | correctif 7 | `git apply --check` code 0 (fait à sec) ; après application, sha256 de la politique `30ee17ec…` (copie modifiée, calculée à sec) ; `bash -n` sans erreur et shellcheck sans avertissement nouveau | Haute |
| M2 | `transporter` | Sujet et tag `.att` de D copiés ; **8 bundles horodatés** de D ; 7 entrées lues ; `construire-deb` `3726ff0b…`, `preparer-deb` `588617b8…`, manifeste seul de `sbuild-debian13` `749d746c…`, `fermeture-deb` `bb7599a2…`, `fermeture-sources` `50dc73f7…`, `packaging` **`f0ed7a71…`** (au lieu de `c1719b13`) ; `outils-prefetch` non prédit (`68e0ae70…` si inchangé depuis le 12/11) ; `verifier_deb.py` `7498fdad…` ; archive d'environ 400 Mo | Haute pour 8 (`s5-porte.log` l. 4), les fermetures, le packaging et les tâches (journaux de S4d3 et de S5) ; moyenne pour la taille |
| M3 | `verifier` | `ko=0` ; 8 bundles sur 8 vérifiés, **8 `invocationId` distincts** (pour chacun des quatre PipelineRuns qui ont produit D, celui du PipelineRun et celui de sa tâche `publier`), dont `576b7e61` et `c3d27e05` ; jeton de TSA de `c3d27e05` le plus récent des 8, le 15/11 entre 20:31:44 et 20:39:34 UTC ; provenance `c3d27e05` extraite ; `_type`, `predicateType`, `builder.id`, `buildType` et sujet OK ; entrées de M2 ; commit `6391fd43` présent, arbre propre ; 15 lignes clés trouvées ; couche du chroot du domaine `1029232e…`, égale à celle de l'image déclarée ; Go égal à `outils-prefetch` ; `finishedOn` entre 2026-11-15T20:31:44Z et 20:39:34Z | Haute pour 8 bundles et la présence de `c3d27e05`, pour la recette et le chroot (tâches, image et chroot de la VM inchangés) ; moyenne pour le schéma de deux enveloppes par PipelineRun (enveloppes de D 4 → 8 par S4d3, `s4d3-chemins.log` l. 78) et pour l'ordre des jetons (le 12/11, le PipelineRun `454728c5` suivait sa tâche de 3 s) |
| M4 | `repetition` | Deux lignes retirées ; `verrou=162 paquets` ; sbuild code 0, aucune ligne apt en http(s) ; `couche=sha256:d8f9685c…` (1955840 octets, celle de `s4d-pipeline.log` l. 32) ; **`manifeste_reconstruit` = D** ; `verdict=PASSED` ; environ 72 s | Moyenne-haute : D a été reproduit par les deux exécutions du 14/11 (`s4d-pipeline.log` l. 32 et 89), par les deux chemins de S4d3 et par le témoin N7 de S5 (`s5-kata.log` l. 22), jamais dans le domaine |
| M5 | `rebuild` | Délai au moins 1440 min depuis `finishedOn` ; `rebuild_deb.sh` `55ebf681…` des deux côtés ; lien coupé, `tx_bytes` et `tx_packets` inchangés pendant les 300 s ; fin avant le rétablissement ; mêmes valeurs que M4 ; `bilan : PASSED, lien coupé, fini avant le rétablissement` | Haute si M4 tient |
| M6 | `vsa` | Garde du correctif : le journal de M5 porte `manifeste_reconstruit=` D (celui du 12/11 ne passerait plus) ; politique `https://github.com/gigi206/supply-chain/blob/<commit 0>/…`, sha256 `30ee17ec…` des deux côtés ; `vsa_deb.py` `34799510…` ; `bundles de l'invocation c3d27e05… parmi 8` : un seul ; `timeVerified` (fin de M5) au moins 24 h après `finishedOn` ; `PASSED`, `['POC_REPLAY_BIT_IDENTIQUE']` ; `inputAttestations` : ce bundle de `horodatage/bundles` ; signature et `verify-blob-attestation` code 0 ; énoncé et bundle archivés | Haute si M5 tient |
| M7 | `pousser_vsa` | Bundle revérifié sur l'hôte, 0 `connect()` ; énoncé : sujet `…@sha256:60f25f5c3fb5…`, `PASSED` ; copie de la CA égale à celle de la 08 et mot de passe de `poc-replay` présent (contrôlés à sec, sans rien afficher) ; sujet lu dans Zot, digest D ; referrers de D dans `builds/sample-app-deb` : 0 avant et après ; étiquettes inchangées ; un referrer de D dans `builds/vsa/sample-app-deb`, au digest poussé, aucune étiquette ; `bilan : tout OK` | Haute (même étape le 14/11, après S5b) |
| M8 | `lire_vsa` | Clé de VSA acceptée et clé de Chains refusée pour la VSA ; l'inverse pour la provenance ; témoin : **8 énoncés vérifiés** (enveloppes de D) ; aucune connexion hors de Zot ; `bilan : tout OK` | Haute pour les verdicts ; moyenne pour 8 |

**Effets.** Dans la VM : `/home/replay/s6b/r3`, `r4` et `r5` vidés puis réécrits ; le chroot du 12/11 est gardé. Sur l'hôte : journaux
`s6b-transporter`, `-verifier`, `-repetition`, `-rebuild`, `-vsa`, `-pousser_vsa`, `-lire_vsa`, et `s6b-vsa-enonce.json`,
`s6b-vsa.bundle.json`, `s6b-vsa-manifeste.json` réécrits ; `chrono.tsv`. Dans Zot : un manifeste, le blob du bundle et une
configuration vide dans `builds/vsa/sample-app-deb`. La porte de la ligne 12 doit alors retenir une VSA de D.
**Cas d'échec.** Provenance plus récente que `c3d27e05` (M3) : arrêt avant `rebuild`, décision. Manifeste reconstruit différent de
D (M4 ou M5) : `FAILED`, aucune VSA signée ; c'est un constat sur la reproductibilité dans le domaine, à porter au propriétaire. Arrêt
de `rebuild` lien coupé : `virsh -c qemu:///system domif-setlink sc-replay <interface> up` (ligne écrite par le script).
**Contrôles à sec faits.** Correctif : `git apply --check` code 0, `bash -n` de la copie modifiée, shellcheck sans avertissement
nouveau (69 lignes de sortie avant et après, mêmes codes) ; la politique modifiée ne porte aucune des mentions refusées par
`etape_vsa`. La nouvelle garde refuse le journal de `rebuild` du 12/11 (aucune ligne `manifeste_reconstruit=` D). VM `sc-replay`
allumée, chroot du 12/11 présent (451786240 octets), 12008 Mo libres. Rien d'écrit dans la VM, dans le cluster ni dans Zot.

## Résultat de M1 (note de 2026-11-16T16:27:36Z ; rien n'est réécrit)
« Oui, applique-le » à « J'applique le correctif 7 ? ». `revision-correctif-7.patch` appliqué tel quel (`git apply`, code 0).
**M1 tenue.**
- Politique : sha256 `30ee17ec…`.
- `s6b.sh` et la politique sont égaux octet pour octet aux copies modifiées à sec.
- `s6b.sh` : `bash -n` sans erreur ; shellcheck, mêmes codes qu'avant.
- `INVOCATION` vaut `c3d27e05-b4cd-487b-8980-7a40b3336ffc`.
- `verifier_deb.py`, `rebuild_deb.sh` et `vsa_deb.py` sont inchangés (`7498fdad…`, `55ebf681…`, `34799510…`).

Le commit qui porte ce résultat fige la nouvelle politique : c'est `POLITIQUE_COMMIT` de la commande 5. Il est à pousser avant cette
commande.
