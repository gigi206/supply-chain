# Brique 05, M1b : prédictions du banc de reproductibilité (point 1 A de la carte), écrites avant le lancement (18/11/2026, 19:44:44 UTC)

**Banc** : [`m1b-repro.sh`](m1b-repro.sh), avec le comparateur [`m1b-repro-comparer.py`](m1b-repro-comparer.py). Il fait deux `dnf --installroot`, hors ligne, des 222 rpm du buildroot du verrou, dans deux dossiers neufs, à au moins 5 s d'intervalle. Les outils sont rpm 4.16.1.3 et dnf-3, pris dans la racine de l'image d'outillage (`99790c13`), sous `unshare --map-auto --map-root-user -n` et `chroot`. Les deux arbres sont ensuite comparés. Rien ne touche au cluster, à Zot ni au réseau. Chaque passage écrit dans un dossier neuf, `~/.cache/supply-chain-poc/05/m1b-repro-<UTC>`, laissé en place.

**Portée** : ce banc mesure ce que fait `dnf --installroot` de ces versions sur un ensemble de rpm figé. Il ne mesure ni l'image d'outillage de M1b (199 rpm de 9.8 et d'EPEL, dnf de l'amorce 9.8), ni l'image de bootstrap, ni un pod Kata. Il dit seulement quels écarts viennent de l'installation elle-même.

| # | Prédiction | Confiance |
|---|---|---|
| RB1 | Les deux installations rendent le code 0, hors ligne, avec 222 paquets chacune et la même liste triée de NEVRA | Moyenne : jamais lancé dans un espace de noms utilisateur avec `--map-auto` ; des scriptlets peuvent manquer de `/dev` ou de `/proc` dans la racine installée |
| RB2 | L'`INSTALLTIME` de `bash` diffère entre les deux installations | Haute : heure de la transaction, 5 s d'écart au moins |
| RB3 | Les deux archives normalisées (sans atime ni ctime dans les en-têtes pax) ont des sha256 différents | Haute : conséquence de RB2 si la base rpm entre dans l'archive |
| RB3t | Témoin : l'arbre 1, archivé deux fois à l'identique, donne deux sha256 différents avec les options brutes de `s1.sh` (`racine`, l. 377), et le même avec les options normalisées | Moyenne : tar écrit atime et ctime en en-tête pax avec `--format=posix` (lecture du manuel de GNU tar, non relu ici), et la lecture par le premier tar change les atime |
| RB4 | Des écarts de contenu apparaissent sous `var/lib/rpm` (base rpm), `var/lib/dnf` (historique) et `var/log` (journaux de dnf) | Haute pour la base rpm ; moyenne pour les deux autres, dont l'emplacement sous `--installroot` n'a pas été lu |
| RB5 | Aucun fichier livré par un rpm sous `usr/` ne diffère par son contenu | Moyenne : le contenu et la mtime viennent des en-têtes, mais des scriptlets ou des triggers (ldconfig, caches) peuvent réécrire des fichiers |
| RB6 | Au moins un fichier écrit par un scriptlet ou un trigger, hors de `var/`, diffère (par exemple sous `etc/`, ou un cache) | Faible : je ne sais pas lesquels tournent ici |

**dnf et la règle de docs/04** : la carte de M1b dit que je n'utiliserai pas dnf avant d'avoir vérifié son verdict. Ce banc lance pourtant dnf-3. Voici pourquoi j'estime qu'il n'en relève pas :
- c'est le dnf-3 déjà présent dans l'image d'essai, que mock appelle à chaque build depuis S1 ;
- le banc tourne sur l'hôte, hors ligne et sans écriture hors de son dossier ;
- il ne fait entrer dnf dans aucune tâche de la plateforme.

Le verdict reste à vérifier avant toute tâche de M1b.

**Ce qui est décidé d'avance** :
- Si RB1 n'est pas tenue, le banc ne mesure rien sur la reproductibilité. Je le consignerai, sans conclure.
- Si seuls des fichiers sous `var/` diffèrent, le point 1 A est jugé « neutralisable à mesurer ». Il restera à mesurer un second banc qui retire ou fige ces fichiers, et à vérifier que mock fonctionne encore sans eux.
- Si des fichiers hors de `var/` diffèrent, je les liste et je ne conclus pas sans relecture. Un écart de la seule mtime d'un répertoire compte comme un écart, puisqu'il entre dans le digest d'une couche.
- Je ne conclus pas sur les archives sans le témoin RB3t.

## Résultat du passage du 18/11/2026, de 19:44:49 à 19:45:19 UTC, code 0 (note écrite à 2026-11-18T19:46:49Z)

Journaux : [banc](m1b-repro.log), et [analyse en lecture seule des deux arbres](m1b-repro-analyse.log) par [`m1b-repro-analyse.py`](m1b-repro-analyse.py), de 19:45:53 à 19:45:55 UTC. Le dossier `~/.cache/supply-chain-poc/05/m1b-repro-20261118T194449Z` est laissé en place.

- **RB1 tenue** : deux installations hors ligne, chacune en code 0 et en 10 s environ (de 19:44:51 à 19:45:01, puis de 19:45:06 à 19:45:16 UTC). Chacune compte 222 paquets, avec la même liste triée de NEVRA (`42d1b11d…`) et 26 540 entrées des deux côtés. Les scriptlets ont tourné (25 lignes « Running scriptlet » ou assimilées par passage). `dev/null` est devenu un fichier ordinaire dans les deux racines installées, puisque `/dev` est absent.
- **RB2 tenue** : `INSTALLTIME` de `bash` à 1795031094 puis à 1795031109.
- **RB3t tenue** : l'arbre 1 archivé deux fois avec les options brutes de `s1.sh` donne `f2dfdcb3…` puis `023bbfd7…`, et avec les options normalisées `287eebe8…` les deux fois. **Les options de la ligne 377 de `s1.sh` ne donnent pas une archive stable, même d'un arbre inchangé.** La couche de la racine de M1b ne pourra pas les reprendre telles quelles.
- **RB3 tenue** : les archives normalisées des deux arbres diffèrent (`287eebe8…`, `eef303c3…`).
- **RB4 tenue** : contenu différent pour `var/lib/rpm/rpmdb.sqlite`, `var/lib/dnf/history.sqlite` (et ses fichiers `-shm` et `-wal`), et pour `var/log/dnf.log`, `dnf.librepo.log`, `dnf.rpm.log` et `hawkey.log`. S'y ajoute `var/cache/ldconfig/aux-cache`, qui n'était pas prédit.
- **RB5 tenue pour le contenu** : aucun fichier sous `usr/` ne diffère par son contenu. **Mais 3332 entrées ont une mtime différente**, sous `usr/` pour la plupart (1182 sous `usr/lib`, 1409 sous `usr/share`). Il y a 2824 répertoires, 326 liens et 172 fichiers ordinaires, dont la mtime tombe chaque fois pendant leur propre transaction.
- **RB6 tenue** : un fichier hors de `var/` diffère par son contenu, `etc/pki/ca-trust/extracted/java/cacerts`, écrit pendant la transaction (scriptlet ou trigger de `ca-certificates`, déduit du chemin, non lu).

**Lecture, selon la règle écrite d'avance** : des fichiers hors de `var/` diffèrent, par leur contenu (`cacerts`) et par leur mtime (répertoires, liens et fichiers sous `usr/` et `etc/`). Je les liste et **je ne conclus pas sans relecture**. Le point 1 A n'est donc pas établi.

Ce que le banc montre, et rien de plus : sur ces versions, une racine installée par `dnf --installroot` n'est pas reproductible au bit près sans traitement. Les écarts se rangent en trois familles :
- des mtimes posées pendant la transaction ;
- des fichiers d'état et des journaux de dnf et de rpm ;
- deux fichiers générés, `cacerts` et `aux-cache`.

Je n'ai mesuré aucun moyen de les neutraliser, par exemple borner les mtimes à l'archivage, retirer les journaux, ou traiter la base rpm et `cacerts`.

**Portée** : ce sont 222 rpm de vault 9.7, avec rpm 4.16.1.3 et dnf 4.14.0 de l'image d'essai, hors de Kata. Ce n'est pas l'ensemble de l'outillage de M1b, ni dnf de l'amorce 9.8.

## Note de portée du 18/11/2026, écrite à 2026-11-18T19:49:19Z UTC, après relecture du conseiller

- **Les 25 lignes du comptage** étaient en partie non lues : le journal du banc n'en imprimait que 10. Je les ai relues et archivées ([relevé](m1b-repro-scriptlets.log)). Les 25 sont toutes des lignes « Running scriptlet », dans chacun des deux passages. Aucune ne porte « warning » ni « error ». Les deux journaux de dnf sont identiques, aux espaces de fin de ligne près. Rien n'y montre l'échec d'un scriptlet. Cela ne prouve pas qu'aucun scriptlet n'a été gêné par l'absence de `/dev` et de `/proc` : `dev/null` est devenu un fichier ordinaire.
- **Le constat sur la ligne 377 de `s1.sh`** vaut pour le tar de l'hôte, avec lequel le banc a archivé, pas pour celui d'un pod.

## Relevé des sources de l'outillage (point 1 B de la carte) : prédictions écrites avant le lancement (2026-11-18T19:58:19Z UTC)

**Relevé** : [`m1b-sources.sh`](m1b-sources.sh), en lecture publique seule. Il reprend les 199 rpm du 17/11 ([`s1-racine.log`](s1-racine.log), l. 11 à 209) et cherche, pour chacun, le même nom de fichier avec le même sha256. Les dépôts interrogés sont pub/9.8 de Rocky (BaseOS, AppStream), vault/9.8 s'il existe, EPEL 9, chaque instantané 9.x de `pub/archive/epel`, et kojipkgs (chemin de construction, chemin signé, `sigcache`). Le repomd.xml de Rocky doit être signé par la clé de `s1.sh` ; sinon le relevé s'arrête. Seul un code HTTP 404 vaut « absent » : tout autre code est imprimé tel quel. Rien ne touche au cluster, à Zot ni aux dépôts de la brique.

| # | Prédiction | Confiance |
|---|---|---|
| SB1 | `pub/rocky` liste 9.8, et `vault/rocky` ne la liste pas | Moyenne : la date de sortie de 9.9 n'a pas été lue |
| SB2 | Les repomd.xml de BaseOS et d'AppStream de pub/9.8 diffèrent de ceux du 17/11 (`abac8b17…`, `a3ca4230…`) | Faible : un jour et demi d'écart |
| SB3 | Les 190 rpm de Rocky (169 et 21) sont encore dans le primary actuel de pub/9.8 avec le même sha256, et leurs 190 adresses répondent 200 | Moyenne : je crois que Rocky garde les versions antérieures dans un même dépôt mineur, sans l'avoir relu |
| SB4 | Le repomd.xml d'EPEL 9 diffère de celui du 17/11 (`8190707a…`) | Haute : il a changé à chaque relevé de S1 |
| SB5 | Le repomd.xml d'EPEL 9 n'a toujours pas de `.asc` | Haute : relevé de `s1-hote.log`, l. 20 |
| SB6 | Au moins un des 9 rpm d'EPEL n'est plus dans le primary actuel d'EPEL 9 | Faible : un jour et demi d'écart |
| SB7 | Au chemin signé de kojipkgs, les 9 rpm d'EPEL répondent 200 avec le sha256 du 17/11 | Moyenne : forme du chemin (`data/signed/<id>/`) citée de mémoire |
| SB8 | Au chemin de construction de kojipkgs, les 9 rpm répondent 200 avec un sha256 différent : ce sont les rpm non signés, la différence est attendue par construction et n'est pas une divergence | Moyenne : même réserve |
| SB9 | `pub/archive/epel` n'a aucun instantané 9.x servant un repomd.xml | Moyenne : index jamais lu |

**Règle de lecture, écrite d'avance** :
- **Adresse figée** : seule une archive déclarée comme telle par son éditeur compte, c'est-à-dire vault de Rocky, ou un instantané de `pub/archive/epel`. La présence constatée dans pub/9.8 ou dans EPEL 9 prouve seulement que les octets sont servis ce jour.
- **kojipkgs** : un 200 avec le bon sha256 prouve que les octets sont récupérables ce jour, sans métadonnées signées. La vérification reposerait alors sur `rpm -K` avec la clé d'EPEL 9 et sur une liste de sha256 tenue dans git. Ce n'est pas une adresse figée au sens de D2 (a). Un échec au chemin signé n'est pas concluant tant que `sigcache` n'est pas lu.
- **Conflit avec D4 (a)** : si Rocky 9.8 n'a pas de vault, ou si EPEL 9 n'a ni instantané ni adresse figée, le conflit avec D4 (a) est rouvert. C'est un **vrai choix du propriétaire**, hors de l'accord permanent : je le consignerai et je le poserai, sans le trancher.

## Second banc (point 1 A) : prédictions écrites avant le lancement (2026-11-18T20:01:10Z UTC)

**Banc** : [`m1b-repro2.sh`](m1b-repro2.sh), avec [`m1b-repro2-comparer.py`](m1b-repro2-comparer.py), [`m1b-repro2-rpmdb.py`](m1b-repro2-rpmdb.py) et [`m1b-repro2-cacerts.py`](m1b-repro2-cacerts.py). Il reprend les deux arbres du premier banc sans réinstaller et sans les écrire :
- **Borne** : E est le plus grand `BUILDTIME` des paquets installés.
- **Archives** : options normalisées du premier banc, mtimes bornées à E (`--mtime=@E --clamp-mtime`), sans huit fichiers :
  - les quatre journaux de dnf ;
  - `history.sqlite` et ses fichiers `-shm` et `-wal` ;
  - `aux-cache`.
- **Comparaison** : membre par membre.
- **Base rpm** : lue sur une copie, en-tête par en-tête et table par table.
- **`cacerts`** : lu champ par champ.

Les archives vont dans un dossier neuf, `~/.cache/supply-chain-poc/05/m1b-repro2-<UTC>`, et les copies des bases rpm dans la racine d'outils du premier banc (`m/repro2-<UTC>`), hors des arbres.

**Portée** : retirer ces huit fichiers et borner les mtimes, ce n'est ici qu'un traitement de l'archive. Le banc ne dit pas si mock fonctionne sans eux, ni ce que fera la tâche de la plateforme.

| # | Prédiction | Confiance |
|---|---|---|
| RD1 | E est le même pour les deux arbres | Haute : mêmes 222 paquets |
| RD2 | Dans chaque arbre, au moins 3332 entrées ont une mtime supérieure à E | Moyenne : je suppose que rpm pose des mtimes au plus égales au `BUILDTIME`, sans l'avoir vérifié |
| RD3 | Témoin : l'arbre 1 archivé deux fois donne deux fichiers identiques octet à octet | Haute : RB3t, options normalisées |
| RD4 | Les deux archives diffèrent, et les seuls membres différents sont `var/lib/rpm/rpmdb.sqlite` et `etc/pki/ca-trust/extracted/java/cacerts`, par leur seul contenu | Moyenne : d'autres en-têtes pax ou un fichier de la base rpm peuvent différer |
| RD5 | Les en-têtes des 222 paquets ne diffèrent que par `Installtime` et `Installtid` | Moyenne : noms des étiquettes dans la sortie `--xml` non lus |
| RD6 | Dans `rpmdb.sqlite`, les blobs de `Packages` diffèrent (222 sur 222) avec les mêmes `hnum`, et les autres tables sont identiques | Moyenne : ordre d'insertion supposé identique |
| RD7 | `cacerts` est au format JKS, avec les mêmes alias et les mêmes certificats ; seuls les horodatages des entrées et l'empreinte finale diffèrent | Moyenne : générateur (p11-kit) non lu |

**Ce qui est décidé d'avance** :
- Si RD4 tient, le point 1 A se réduit à deux fichiers, mais il **n'est pas établi pour autant**. Aucun moyen de neutraliser la base rpm ni `cacerts` n'est mesuré ici. Ces moyens feront l'objet d'une carte à part. Si l'un d'eux demande une installation, ou si c'est un vrai choix, la décision reviendra au propriétaire.
- Si d'autres membres diffèrent, je les liste et je ne conclus pas.
- Sans le témoin RD3, je ne conclus pas sur les archives.

## Résultat du relevé des sources, du 18/11/2026, de 19:58:32 à 20:01:09 UTC, code 0 (note écrite à 2026-11-18T20:02:39Z)

Journal : [`m1b-sources.log`](m1b-sources.log). Le dossier `~/.cache/supply-chain-poc/05/m1b-sources-20261118T195832Z` est laissé en place. Les quatre repomd.xml de Rocky sont signés par la clé de `s1.sh`. La clé d'EPEL 9 a la même empreinte que dans `s1-hote.log`.

- **SB1 non tenue** : Rocky 9.9 est sortie. `pub/rocky` liste 9.8 et 9.9, et `vault/rocky` liste 9.8.
- **SB2 non tenue** : les repomd.xml de BaseOS et d'AppStream de pub/9.8 sont ceux du 17/11 (`abac8b17…`, `a3ca4230…`). Ceux de vault/9.8 aussi.
- **SB3 tenue**, et de même dans vault : les 190 rpm de Rocky (169 et 21) y sont avec le même sha256, et leurs adresses répondent 200, dans pub/9.8 comme dans vault/9.8.
- **SB4 tenue** : le repomd.xml d'EPEL 9 est `ace203bb…`, révision du 18/11/2026 à 01:40:30 UTC.
- **SB5 tenue** : il n'a pas de `.asc`.
- **SB6 non tenue** : les 9 rpm d'EPEL sont encore dans son primary actuel, avec le même sha256.
- **SB7 tenue** : au chemin signé de kojipkgs (`data/signed/3228467c/`), les 9 rpm répondent 200 avec le sha256 du 17/11. Les 9 fichiers de `sigcache` répondent aussi 200.
- **SB8 tenue** : au chemin de construction, les 9 rpm répondent 200 avec un sha256 différent. Je n'ai pas vérifié qu'ils sont non signés : il n'y a pas de `rpm` sur l'hôte.
- **SB9 non tenue** : 12 instantanés 9.x de `pub/archive/epel` servent un repomd.xml. Celui de **9.8** a la révision du 10/11/2026 à 03:20:16 UTC (`e86fdcd8…`). Il contient **les 9 rpm avec le même sha256**, et ses 9 adresses répondent 200. Il n'a pas de `.asc`, comme les autres. Les instantanés de 9.1 à 9.7 en contiennent de 2 à 5.

**Lecture, selon la règle écrite d'avance** :
- **Rocky** : `vault/rocky/9.8` est une adresse figée. C'est une archive déclarée par l'éditeur, avec un repomd.xml signé, identique à celui du 17/11, et elle contient les 190 rpm.
- **EPEL** : `pub/archive/epel/9.8` est une adresse figée au sens de la règle, puisque c'est une archive déclarée par Fedora. Elle contient les 9 rpm. Ses métadonnées ne sont pas signées, comme celles de `pub/epel` le 17/11 : la vérification resterait celle de S1, `rpm -K` avec la clé d'EPEL 9, plus des sha256 tenus dans git.
- **Le conflit avec D4 (a) n'est donc pas rouvert.** Les 199 rpm de l'outillage du 17/11 sont servis aujourd'hui à deux adresses figées.

**Ce que le relevé ne montre pas** :
- **La durée de conservation des archives** : j'ai seulement constaté que les instantanés d'EPEL depuis le 09/05/2023 et vault depuis 8.3 sont encore servis. Je n'ai lu aucun engagement de durée.
- **La fin des mises à jour de 9.8** : elle est déduite de la sortie de 9.9, je ne l'ai pas lue. Si elle se confirme, l'outillage épinglé sur 9.8 ne recevra plus de correctifs, comme le bootstrap sur vault 9.7 (D2 a). Je le signale, sans le trancher.
- **La liste des paquets** : la liste complète à installer reste à retirer de la base rpm de la racine archivée (201 paquets), selon la leçon de S4a.

## Résultat du second banc, du 18/11/2026, de 20:02:56 à 20:03:12 UTC, code 0 (note écrite à 2026-11-18T20:04:50Z)

Journaux : [banc](m1b-repro2.log), et [lecture complémentaire](m1b-repro2-analyse.log) par [`m1b-repro2-analyse.py`](m1b-repro2-analyse.py), à 20:03:51 UTC. Les archives sont dans `~/.cache/supply-chain-poc/05/m1b-repro2-20261118T200256Z`, laissées en place.

- **RD1 tenue** : E vaut 1778602708 (12/05/2026, 16:18:28 UTC), dans les deux arbres.
- **RD2 tenue** : 4317 entrées dépassent E dans chaque arbre. Parmi elles :
  - 3332 ont une mtime différente d'un arbre à l'autre : ce sont les écarts du premier banc ;
  - **985 ont la même mtime des deux côtés**. Ce sont toutes des fichiers sous `usr/include`, dont 769 sous `usr/include/linux`, datés du 12/05/2026 entre 18:33:40 et 18:34:12 UTC. Leur mtime vient donc des en-têtes rpm, et elle est postérieure au plus grand `BUILDTIME`. Le paquet n'a pas été lu.
  - **Conséquence** : borner à E change la mtime de 985 fichiers livrés par rpm. `rpm -V` les signalerait sans doute, mais c'est déduit, pas mesuré. Une autre borne reste à choisir.
- **RD3 tenue** : l'arbre 1 archivé deux fois donne deux fichiers identiques octet à octet (`f89341db…`).
- **RD4 tenue** : les deux archives diffèrent (`f89341db…`, `89465527…`), avec 26 533 membres chacune et la même taille, 776 755 200 octets. **Seuls deux membres diffèrent, par leur seul contenu** : `var/lib/rpm/rpmdb.sqlite` et `etc/pki/ca-trust/extracted/java/cacerts`. Les huit fichiers exclus sont bien absents.
- **RD5 tenue** : les en-têtes des 222 paquets ne diffèrent que par `Installtime` et `Installtid`.
- **RD6 en partie** : les 222 blobs de `Packages` diffèrent, avec les mêmes `hnum` et les mêmes tailles. **Mais la table `Installtid` diffère aussi**, puisqu'elle indexe cette étiquette. Les 19 autres tables sont identiques. Le WAL est vide (0 octet) des deux côtés : la lecture en `immutable=1` n'a rien manqué.
- **RD7 tenue** : `cacerts` est au format JKS (version 2), avec 146 entrées, et les mêmes alias et certificats des deux côtés. Chaque magasin a un seul horodatage, celui de sa génération pendant la transaction (19:44:59 et 19:45:14 UTC). L'empreinte finale diffère.

**Lecture, selon la règle écrite d'avance** : RD4 tient, et le point 1 A se réduit à deux fichiers. **Il n'est pas établi pour autant.**
- **Origine des écarts** : tous ceux que le banc a lus viennent de l'heure de l'installation, `Installtime` et `Installtid` dans la base rpm, l'horodatage des entrées dans `cacerts`.
- **Neutralisation** : aucun moyen de neutraliser ces écarts n'est mesuré ici, ni le choix de la borne des mtimes. Ce sera une carte à part. Si l'un des moyens demande une installation, ou si c'est un vrai choix, la décision reviendra au propriétaire.

**Portée** : ce banc traite l'archive, sur l'hôte, des 222 rpm de vault 9.7. Il ne dit pas si mock fonctionne sans les huit fichiers retirés, ni ce que fera la tâche Kata de la plateforme.

## Corrections et compléments après relecture du conseiller : prédictions écrites avant le lancement (2026-11-18T20:07:49Z UTC)

**Corrections** de la note du relevé des sources :
- **« Rocky 9.9 est sortie » dépasse la mesure.** Le journal montre seulement que l'index de `pub/rocky` liste `9.9/` et que celui de `vault/rocky` liste `9.8/`. Je n'ai lu ni le contenu de pub/9.9, ni ses métadonnées, ni une annonce. La même correction vaut pour la ligne du README du 2026-11-18T20:05:20Z.
- **Les révisions des repomd.xml** (10/11/2026 à 03:20:16 UTC pour `archive/epel/9.8`, 18/11/2026 à 01:40:30 UTC pour `pub/epel/9`) ont été lues par une commande sans journal. Elles sont relues et archivées par [`m1b-complements.sh`](m1b-complements.sh), partie 1.
- **Les 985 fichiers de `usr/include`** : dire que leur mtime vient des en-têtes rpm était une déduction tirée de leur égalité entre les deux arbres. Elle est mesurée ici, partie 2.

**Constat pour le propriétaire** : la règle écrite d'avance n'avait pas prévu qu'une version 9.9 paraisse. Rester sur 9.8 figée, ou suivre 9.9, est un vrai choix. Il est à trancher avant la liste épinglée de M1b, sans recommandation de ma part à ce stade.

| # | Prédiction | Confiance |
|---|---|---|
| CP1 | Les révisions relues sont 1794280816 pour `archive-9.8` et 1794966030 pour `epel9`, et les sha256 des repomd.xml sont ceux de `m1b-sources.log` | Haute : mêmes fichiers, déjà lus |
| CP2 | Les 985 fichiers ont une mtime égale à `FILEMTIMES` dans leur en-tête, et appartiennent tous à `kernel-headers` | Haute pour l'égalité ; moyenne pour le paquet, deviné d'après `usr/include/linux` |

## Résultat des compléments, du 18/11/2026 à 20:07:51 UTC, code 0 (note écrite à 2026-11-18T20:08:11Z)

Journal : [`m1b-complements.log`](m1b-complements.log).
- **CP1 tenue** : `archive-9.8` est à la révision 1794280816 (10/11/2026, 03:20:16 UTC) et `epel9` à la révision 1794966030 (18/11/2026, 01:40:30 UTC). Leurs sha256 sont ceux de `m1b-sources.log`. Les repomd.xml de Rocky portent la révision « 9.8 » et non une date.
- **CP2 tenue** : les 985 fichiers ont une mtime égale à `FILEMTIMES` dans leur en-tête, et appartiennent tous à `kernel-headers`. Leur mtime vient donc bien de l'en-tête rpm. Borner les mtimes à E change donc des métadonnées livrées par rpm. Que `rpm -V` le signale reste déduit, pas mesuré.

## Troisième banc (neutralisation par SOURCE_DATE_EPOCH) : prédictions écrites avant le lancement (2026-11-18T20:15:41Z UTC)

**Lecture préalable, sans journal** (18/11/2026, reprise dans l'en-tête du banc) : la chaîne `SOURCE_DATE_EPOCH` est présente dans `librpm.so.9` de l'image d'outillage (rpm 4.16.1.3-40.el9), au voisinage de « rpmts.c ». Elle l'est aussi dans `/usr/bin/trust` de p11-kit 0.25.3-3.el9_5, que le scriptlet de `ca-certificates` appelle par `update-ca-trust` pour écrire `cacerts`. **Ce que la variable fixe n'est pas lu** : le banc le mesure, et la lecture des sources ne viendra que si le résultat est partiel.

**Banc** : [`m1b-repro3.sh`](m1b-repro3.sh). Il utilise les mêmes outils (couches de `99790c13`) et les mêmes 222 rpm que le premier banc, dans un dossier neuf (`~/.cache/supply-chain-poc/05/m1b-repro3-<UTC>`). Il ne fait que lire le premier banc.
- **Borne** : S = max(plus grand `BUILDTIME`, plus grande `FILEMTIMES` des en-têtes installés). Ainsi, aucune mtime livrée par rpm ne dépasse la borne, par construction.
- **Installations** : i3 et i4, avec `SOURCE_DATE_EPOCH=S`, 5 s d'écart.
- **Archives** : bornées à S, sans les huit fichiers du second banc. Deux témoins : i3 archivé deux fois, et i1 (installé sans la variable) archivé de la même façon.
- **Comparaisons** : archives membre par membre, base rpm et `cacerts`.
- **Jour près** : troisième champ de `etc/shadow` dans i1 et i3.

| # | Prédiction | Confiance |
|---|---|---|
| RT1 | S est supérieur ou égal à E (1778602708), et S est le plus grand `FILEMTIMES` (au moins 12/05/2026, 18:34:12 UTC) | Haute : 985 fichiers de `kernel-headers` au-dessus de E (CP2) |
| RT2 | dnf rend 0 aux deux installations, avec 222 paquets et la même liste triée qu'au premier banc | Haute : mêmes rpm, mêmes outils |
| RT3 | Dans i3 comme dans i4, `INSTALLTIME` et `INSTALLTID` valent S pour les 222 paquets (un seul couple) | Moyenne : chaîne présente près de `rpmts.c`, usage non lu ; l'heure d'installation pourrait venir d'ailleurs que de la transaction |
| RT4 | Dans i3 comme dans i4, environ 3332 entrées dépassent encore S : ce sont celles que l'installation crée ou touche (4317 au-dessus de E au second banc, moins les 985 de `kernel-headers`) | Moyenne : je suppose que la variable ne change pas les mtimes du système de fichiers |
| RT5 | `cacerts` est identique entre i3 et i4, et ses 146 entrées portent l'horodatage S | Moyenne-basse : suppose que l'environnement passe de dnf au scriptlet, puis à `update-ca-trust` et à `trust`, et que `trust` s'en sert pour les horodatages |
| RT6 | Témoin : i3 archivé deux fois donne deux fichiers identiques octet à octet | Haute : RD3 |
| RT7 | a3.tar et a4.tar sont identiques octet à octet | Moyenne-basse : conjonction de RT3 et de RT5, et rien d'autre ne diffère |
| RT8 | Témoin sans la variable (a1s.tar contre a3.tar) : seuls `rpmdb.sqlite` et `cacerts` diffèrent | Moyenne : la variable pourrait changer autre chose, et c'est ce que ce témoin doit montrer |
| RT9 | Le troisième champ de `etc/shadow` a les mêmes valeurs dans i1 et i3 | Haute, mais sans portée : même jour |

**Ce qui est décidé d'avance** :
- **Si RT7 tient**, j'écrirai « neutralisable sur le banc », **et non « établi »**. Quatre angles morts restent à mesurer :
  1. **Jour différent** : à 15 s d'écart, un champ au jour près reste invisible, et le rejeu aura lieu après le 28/11. Fausser l'horloge demanderait une installation.
  2. **Mauvais jeu de paquets** : ces 222 rpm forment le buildroot. Il reste à mesurer les 201 paquets de l'outillage, et le bootstrap (base 9.7 plus dix lignes : heures d'installation mêlées, `cacerts` peut-être jamais régénéré).
  3. **Mauvais installeur** : le banc utilise rpm -40, de l'image d'outillage. La tâche retenue utilisera le dnf de l'amorce `ed654c69`, que je n'ai pas en local et dont je n'ai pas lu la version de rpm.
  4. **Dépôt et non fichiers locaux** : sur un miroir partiel, dnf écrira sous `var/cache/dnf` et `var/lib/dnf`, ce qu'aucun banc n'a vu.
- **Si seul un des deux fichiers devient stable**, c'est un résultat à noter, pas un échec. Je lirai alors les sources de rpm ou de p11-kit, sur leurs SRPM signés.
- **Si RT8 montre d'autres membres**, je les liste et je ne conclus pas.
- **Les replis** (réécrire la base rpm après l'installation, retirer ou régénérer `cacerts`) restent non mesurés. Ils ne seront listés dans la carte que comme tels.

## Résultat du troisième banc, du 18/11/2026, de 20:15:56 à 20:16:39 UTC, code 0 (note écrite à 2026-11-18T20:17:28Z)

Journal : [`m1b-repro3.log`](m1b-repro3.log). Les arbres et les archives sont dans `~/.cache/supply-chain-poc/05/m1b-repro3-20261118T201556Z`, laissés en place.

- **RT1 tenue** : S vaut 1778610852 (12/05/2026, 18:34:12 UTC). C'est la plus grande `FILEMTIMES`, au-dessus de E.
- **RT2 tenue** : dnf rend 0 aux deux installations, avec 222 paquets et la même liste triée (`251ac6c5…`).
- **RT3 en partie** :
  - `INSTALLTID` vaut S pour les 222 paquets ;
  - **`INSTALLTIME` n'est pas constant** : il vaut S pour le premier paquet, puis augmente d'une seconde par paquet, jusqu'à S + 221 (18:37:53 UTC) ;
  - la suite est la même dans i3 et dans i4. L'écart à la prédiction ne coûte donc rien à la reproductibilité.
- **RT4 tenue** : 3332 entrées dépassent S dans chaque arbre (2824 répertoires, 326 liens, 182 fichiers). La variable ne change pas les mtimes du système de fichiers ; c'est la borne de tar qui s'en charge.
- **RT5 tenue** : `cacerts` est identique entre i3 et i4. Ses 146 entrées portent l'horodatage S. La variable passe donc de dnf au scriptlet de `ca-certificates`, puis à `trust`.
- **RT6 tenue** : i3 archivé deux fois donne deux fichiers identiques.
- **RT7 tenue** : **a3.tar et a4.tar sont identiques octet à octet** (`0c00666a…`, 776 755 200 octets). La base rpm l'est aussi, table par table : 222 blobs égaux, 2691 pages.
- **RT8 tenue** : contre i1, installé sans la variable, seuls `rpmdb.sqlite` et `cacerts` diffèrent. La variable ne change rien d'autre dans l'archive.
- **RT9 tenue** : le troisième champ de `etc/shadow` vaut 19820 (7/04/2024) sur 13 lignes, dans i1 comme dans i3. Il ne vient donc pas du jour de l'installation, mais il ne dit rien des autres champs au jour près.

**Lecture, selon la règle écrite d'avance** : **le point 1 A est neutralisable sur le banc. Il n'est pas établi.** Deux moyens suffisent ici, et aucun ne demande d'installation :
1. poser `SOURCE_DATE_EPOCH=S` pendant `dnf --installroot` ;
2. borner les mtimes de l'archive à cette même valeur S (`--mtime=@S --clamp-mtime`), avec S = max(`BUILDTIME`, `FILEMTIMES`). Aucune mtime livrée par rpm ne change alors.

Il faut aussi retirer les huit fichiers du second banc (journaux et historique de dnf, `aux-cache`). Les quatre angles morts écrits d'avance restent à mesurer :
1. **Jour différent** : le rejeu aura lieu après le 28/11. Fausser l'horloge demanderait une installation.
2. **Jeu de paquets** : il reste les 201 paquets de l'outillage, et le bootstrap (base 9.7 plus dix lignes).
3. **Installeur** : rpm de l'amorce `ed654c69`, non lu.
4. **Miroir partiel** au lieu de fichiers locaux : `var/cache/dnf` et `var/lib/dnf`.

**Portée** : ce sont des installations sur l'hôte, des 222 rpm de vault 9.7, avec rpm 4.16.1.3-40. Le banc ne dit pas si mock fonctionne sans les huit fichiers retirés. Il ne dit pas non plus ce que fera la tâche Kata. Les replis (réécrire la base rpm, retirer ou régénérer `cacerts`) restent non mesurés et sans objet tant que la variable suffit. Le choix de S est le mien : c'est la plus petite borne qui ne change aucune mtime livrée par rpm. Il ne devient une recommandation qu'après relecture du conseiller.

## Corrections du troisième banc après relecture du conseiller, et compléments C3a à C3c : prédictions écrites avant le lancement (2026-11-18T20:20:09Z UTC)

**Corrections** de la note du résultat du troisième banc :
- **Lectures sans journal** : l'en-tête du banc annonce une lecture préalable « reprise ici », mais le banc ne relance aucun `strings`. Les versions rpm 4.16.1.3-40 et p11-kit 0.25.3-3.el9_5 citées dans les notes ne sont pas non plus dans son journal : il ne porte que « RPM version 4.16.1.3 ». Elles sont relues et archivées par [`m1b-complements3.sh`](m1b-complements3.sh), partie 1.
- **« S + rang du paquet » dépasse la mesure** (README et additif de l'ADR 0007 de 20:17 UTC) : le journal montre 222 valeurs consécutives, de S à S + 221, une par paquet, et la même suite dans i3 et i4. Il ne montre pas que la suite suit l'ordre de la transaction. C'est mesuré ici, partie 3.
- **S a été lu dans la base d'une installation antérieure** (i1). Or la tâche devra le connaître avant d'installer. Partie 2 : calcul sur les fichiers rpm eux-mêmes.

| # | Prédiction | Confiance |
|---|---|---|
| C3a | La racine d'outils a rpm-4.16.1.3-40.el9. L'arbre i3 a p11-kit-0.25.3-3.el9_5. La chaîne `SOURCE_DATE_EPOCH` est présente dans `librpm.so.9` et dans `/usr/bin/trust`, comme à la lecture sans journal | Haute : mêmes binaires, déjà lus |
| C3b | S calculé par `rpm -qp` sur les 222 fichiers vaut 1778610852, comme dans le banc | Haute : mêmes en-têtes |
| C3c | Trier les paquets de i3 par `INSTALLTIME` donne l'ordre des lignes « Installing » du journal de dnf de i3 | Moyenne : je suppose une seconde de plus à chaque élément de la transaction, sans l'avoir lu |

## Résultat des compléments du troisième banc, du 18/11/2026 à 20:20:11 UTC, code 0 (note écrite à 2026-11-18T20:20:42Z)

Journal : [`m1b-complements3.log`](m1b-complements3.log).
- **C3a tenue** : la racine d'outils a rpm-4.16.1.3-40.el9 et l'arbre i3 p11-kit-0.25.3-3.el9_5. La chaîne `SOURCE_DATE_EPOCH` figure une fois dans `librpm.so.9` (voisine de « rpmts.c ») et quatre fois dans `/usr/bin/trust`.
- **C3b tenue** : S, calculé par `rpm -qp` sur les 222 fichiers avant toute installation, vaut 1778610852, comme dans le banc. La tâche pourra donc le calculer sur les rpm qu'elle reçoit. Pour le bootstrap, il faudra aussi couvrir la base de l'image : c'est à mesurer.
- **C3c non conclue : mon comparateur était défectueux.** Il confondait deux écritures du même paquet. rpm écrit `1:gmp-6.2.0-13.el9.x86_64` et le journal de dnf `gmp-1:6.2.0-13.el9.x86_64`. Il ne tenait pas compte non plus des noms que dnf tronque dans sa colonne (rang 104). Les 50 rangs « différents » ne disent donc rien de l'ordre. **La prédiction C3c est inchangée.** Elle est remesurée sur les fichiers déjà écrits par le banc, avec un comparateur corrigé, [`m1b-complements3-ordre.py`](m1b-complements3-ordre.py), commité avant le lancement.

### Comparateur corrigé, premier passage (18/11/2026, 20:20:43 UTC, code 0 ; note écrite à 2026-11-18T20:21:08Z)

Journal : [`m1b-complements3-ordre.log`](m1b-complements3-ordre.log), remplacé par le passage suivant. Ce premier passage est conservé dans l'historique de git, dans le commit qui ajoute cette note.
- **Résultat** : 199 rangs donnent le même nom, et 2 un nom tronqué par dnf. Les 21 autres rangs ne sont pas conclus : **le comparateur était encore défectueux**. Les 20 rangs affichés portent tous une époque nulle, que rpm écrit `perl-B-0:1.80-…` et que dnf omet (`perl-B-1.80-…`). Le 21e n'est pas affiché.
- **Seconde correction**, écrite avant le passage suivant : une époque nulle est retirée de l'écriture de rpm. **La prédiction C3c est inchangée.**

### Comparateur corrigé, second passage (18/11/2026, 20:21:10 UTC, code 0 ; note écrite à 2026-11-18T20:21:29Z)

Journal : [`m1b-complements3-ordre.log`](m1b-complements3-ordre.log).
- **C3c tenue** : 220 rangs donnent le même nom, et 2 un nom que dnf tronque (préfixe du nom de rpm). Aucun autre écart. **Trier les paquets par `INSTALLTIME` redonne l'ordre de la transaction** du journal de dnf : `INSTALLTIME` vaut S plus le rang du paquet dans la transaction, moins un.
- **Conséquence** : la formule corrigée à 20:20 UTC est maintenant mesurée, sur une installation. La reproductibilité de `INSTALLTIME` dépend donc aussi de l'ordre de la transaction, et cet ordre était le même dans i3 et i4.

## Relevé de santé de dnf : prédictions écrites avant le lancement (2026-11-18T20:24:33Z UTC)

**Objet** : la carte de M1b interdit d'utiliser dnf avant d'avoir vérifié son verdict dans docs/04, car il n'y a pas de ligne propre. La tâche Kata de M1b lancera `dnf --installroot` depuis l'amorce `rockylinux:9.8`. Le relevé couvre :
- dnf 4 ;
- les trois bibliothèques que dnf exécute : libdnf (avec hawkey), librepo et libsolv.

**Relevé** : étape `dnf` de [`sante.sh`](../sante.sh), ajoutée le 18/11/2026, avec les mêmes relevés que l'étape `voie2` :
- Scorecard, release, commits sur 90 jours, auteurs, fusionneurs, SECURITY.md et avis de l'année ;
- en plus, les cinq premières étiquettes et la date de leur commit, car un projet peut publier sans release GitHub ;
- la liste des fichiers de ces paquets dans `vault/rocky/9.8/BaseOS`. Cette liste n'est pas signée : c'est un indice de version, pas un épinglage.

Journal : `resultats/sante-dnf.log`.

**Règle de docs/04 (§1)** :
- **Risqué** : aucune release depuis plus de 12 mois, projet archivé, mainteneur unique sans soutien, ou compromission non résolue.
- **À surveiller** : un critère manque, bus factor de 1 ou 2, ou Scorecard < 6.

| # | Prédiction | Confiance |
|---|---|---|
| DN1 | Aucun des quatre dépôts n'est archivé | Haute : bibliothèques de Fedora et de RHEL 9 |
| DN2 | Chacun a une release ou une étiquette datée de moins de 12 mois | Moyenne : libsolv publie peut-être sans release GitHub (d'où les étiquettes) ; dnf 4 est en maintenance depuis dnf5 |
| DN3 | Chacun a des commits sur les 90 derniers jours | Moyenne : même raison |
| DN4 | Au moins un critère « À surveiller » par projet : Scorecard sous 6 ou « n/d », fusionneurs d'un seul employeur, ou SECURITY.md absent | Moyenne-haute : même éditeur que rpm et createrepo_c (ligne du 12/11) |
| DN5 | vault/rocky/9.8/BaseOS liste dnf-4.14.0 et python3-dnf-4.14.0, de la même version que le python3-dnf de l'image d'outillage (4.14.0-34.el9_8.rocky.0.1) | Moyenne : liste lue, mais le nom exact de la release Rocky est incertain |

**Ce qui est décidé d'avance** :
- **Si DN1 à DN3 tiennent pour les quatre**, aucun n'est « Risqué ». J'ajouterai une ligne « À surveiller » ou « Sain » à docs/04, selon les critères du §1, avec un plan de sortie. Je proposerai le verdict au propriétaire. Je ne l'écrirai pas comme un verdict de sa part.
- **Si l'un d'eux tombe sous « Risqué »**, dnf n'est pas utilisé. M1b revient au propriétaire, car la transposition 3 de S4a ne tient plus.
- **Le relevé ne dit rien du rythme de correction des CVE** par Rocky, que docs/04 laisse aux distributions.

## Résultat du relevé de santé de dnf, du 18/11/2026 à 20:24:37 UTC, code 0 (note écrite à 2026-11-18T20:26:07Z)

Journal : [`sante-dnf.log`](sante-dnf.log).
- **DN1 tenue** : aucun des quatre dépôts n'est archivé.
- **DN2 non tenue pour dnf, ou du moins non établie** :
  - **dnf** : sa dernière release GitHub est la 4.24.0, du 21/10/2025. Au jour du relevé, elle a donc plus de 12 mois (12 mois et 28 jours), ce qui est le critère « Risqué » de docs/04. Les cinq étiquettes lues ne datent pas la plus récente : l'API ne les trie pas par date (les cinq lues datent de 2012 à 2017). Le relevé ne dit donc pas si dnf a publié depuis sans release GitHub.
  - **libdnf** : 0.76.0, du 17/09/2026.
  - **librepo** : 1.22.0, du 2/11/2026.
  - **libsolv** : aucune release GitHub, mais l'étiquette 0.7.41 a un commit du 23/10/2026.
- **DN3 tenue** : il y a des commits sur 90 jours pour les quatre : 7 pour dnf, 12 pour libdnf, 32 pour librepo, 40 pour libsolv.
- **DN4 tenue** :
  - **Scorecard** : 4 pour dnf, 4,3 pour libsolv, « n/d » pour libdnf et librepo ;
  - **SECURITY.md** : absent des quatre ;
  - **libsolv** : 95 des 100 dernières fusions sont de mlschroe (adresse suse.de), soit un bus factor de 1.
- **DN5 tenue** : vault 9.8 liste `dnf-4.14.0-34.el9_8.rocky.0.1`, de la même version que l'image d'outillage. Il liste aussi libdnf 0.69.0, librepo 1.19.0 et libsolv 0.7.24 (deux releases Rocky, -5 et -6). Ces versions sont très en retrait de l'amont.

**Lecture, selon la règle écrite d'avance** : je ne conclus pas encore. Si aucune publication de dnf n'est plus récente que le 21/10/2025, dnf tombe sous le critère « Risqué », et M1b revient au propriétaire. Le complément [`m1b-dnf-complements.sh`](m1b-dnf-complements.sh) lit :
- les étiquettes triées par date ;
- les dernières releases GitHub ;
- ce que le README de dnf dit de dnf5 ou de la maintenance.

### Compléments du relevé de dnf : prédictions écrites avant le lancement (2026-11-18T20:26:07Z UTC)

| # | Prédiction | Confiance |
|---|---|---|
| DC1 | Aucune étiquette de dnf n'a de commit postérieur au 21/10/2025 | Moyenne : 7 commits en 90 jours, mais aucune release |
| DC2 | Les étiquettes les plus récentes de libdnf, librepo et libsolv sont celles de leur dernière release (0.76.0, 1.22.0, 0.7.41) | Moyenne-haute |
| DC3 | Le README de dnf cite dnf5 | Moyenne : Fedora est passée à dnf5 |

**Ce qui est décidé d'avance** :
- **Si DC1 tient**, dnf remplit le critère « Risqué » de docs/04 au sens littéral (aucune release depuis plus de 12 mois). Je ne l'utiliserai pas, et je poserai la question au propriétaire. Le dnf de Rocky 9.8 est maintenu par la distribution (4.14.0-34.el9_8), et docs/04 dit que « la criticité et l'adoption pondèrent le verdict ». Mais pondérer ce critère, ou le lever, n'est pas à moi de le décider.
- **Si une étiquette postérieure existe**, dnf n'est pas « Risqué » par ce critère. Je proposerai alors une ligne « À surveiller », avec un plan de sortie.

## Résultat des compléments du relevé de dnf, du 18/11/2026, de 20:26:08 à 20:26:11 UTC, code 0 (note écrite à 2026-11-18T20:26:36Z)

Journal : [`m1b-dnf-complements.log`](m1b-dnf-complements.log).
- **DC1 tenue** : la plus récente étiquette de dnf est la 4.24.0, avec un commit du 21/10/2025. C'est aussi la dernière release GitHub : 4.23.0 date du 7/03/2025 et 4.22.0 du 12/11/2024.
- **DC2 tenue** : les étiquettes les plus récentes sont celles des dernières releases :
  - libdnf : 0.76.0 (commit du 16/09/2026) ;
  - librepo : 1.22.0 (22/10/2026) ;
  - libsolv : 0.7.41 (23/10/2026).
- **DC3 tenue** : le README de dnf dit que le dépôt ne sert qu'à DNF4, et que la version courante, DNF5, a son propre dépôt.

**Lecture, selon la règle écrite d'avance** : **dnf 4 remplit le critère « Risqué » de docs/04 au sens littéral.** Il n'a aucune release depuis plus de 12 mois (21/10/2025, soit 12 mois et 28 jours au jour du relevé). Le dépôt a pourtant 7 commits en 90 jours, et le paquet de Rocky est reconstruit par la distribution (4.14.0-34.el9_8). **Je n'utilise pas dnf dans M1b, et la question revient au propriétaire.** libdnf, librepo et libsolv ne tombent sous aucun critère « Risqué ». libsolv a un bus factor de 1 (« À surveiller »).

**Fait à porter à la question** : dnf tourne déjà dans la chaîne rpm hors de M1b. mock s'en sert, dans le bootstrap, pour installer le buildroot (S1, `verrou_brut` : « dnf rocky.0.1 »). Le verdict ne concerne donc pas que M1b. Je ne l'ai pas encore relu dans les journaux de M3 et de M4c.

**Note du 18/11/2026, écrite à 2026-11-18T20:26:50Z UTC** : relu dans [`s1-m3_build1-mock.log`](s1-m3_build1-mock.log), l. 46 à 54 : mock y écrit « Package manager dnf4 detected and used (direct choice) », puis installe le buildroot minimal avec dnf (python3-dnf 4.14.0-31 dans le bootstrap). **M3 a donc exécuté dnf 4.** Les journaux de M4c ne sont pas relus.

## Corrections après relecture du conseiller, et portée de dnf : prédictions écrites avant le lancement (2026-11-18T20:28:59Z UTC)

**Corrections** de la note des compléments du relevé de dnf (20:26 UTC) :
- **« Le paquet de Rocky est reconstruit par la distribution (4.14.0-34.el9_8) »** dépasse la mesure. Je l'ai tiré d'un nom de fichier, dans une liste qui n'est pas signée. La date de construction et le changelog sont mesurés ici, partie 1, hors ligne.
- **« libsolv ne tombe sous aucun critère Risqué »** dépasse aussi la mesure. 95 des 100 dernières fusions viennent d'une seule personne. Le soutien d'un employeur n'est déduit que du domaine de son adresse (suse.de). Correction : **mainteneur unique, soutien non mesuré**. Le verdict de libsolv reste ouvert, comme celui de dnf.
- **Le seuil était déjà franchi au premier usage.** La dernière release de dnf date du 21/10/2025. Au premier passage de `racine` en S1, le 17/11/2026, dnf avait donc déjà plus de 12 mois sans release. Le relevé de santé du 5/11/2026 ne couvrait pas dnf. C'est un manque de ma part, antérieur à M1b.
- **Conséquence** : je n'utilise pas dnf dans M1b avant ta réponse. La relance du troisième banc le 19/11 et le banc du bootstrap sont suspendus.

**Mesure de la portée** : [`m1b-dnf-portee.sh`](m1b-dnf-portee.sh), sur l'hôte, hors ligne, en lecture seule.

| # | Prédiction | Confiance |
|---|---|---|
| DP1 | La racine d'outils a python3-dnf-4.14.0-34.el9_8.rocky.0.1, construit en 2026. La première entrée de son changelog date aussi de 2026 | Moyenne : suffixe el9_8 ; la date n'est pas lue |
| DP2 | L'arbre i3 (buildroot) n'a pas dnf | Moyenne : le buildroot minimal de mock ne demande pas dnf, et je ne l'ai pas lu |
| DP3 | « Package manager dnf4 detected » apparaît au moins dans les journaux de mock de S1 (essais, verrous) et de M3. `installroot` ou `dnf-3` apparaît au moins dans les journaux de `racine`, `boot_racine` et M2 | Haute : liste des fichiers déjà vue sans journal |
| DP4 | Aucun journal archivé de M4b ni de M4c ne contient ces motifs, car mock y a tourné dans des pods dont les journaux ne sont pas archivés ici. Ce n'est pas une preuve que dnf n'y a pas tourné | Moyenne |

## Résultat de la portée de dnf, du 18/11/2026 à 20:29:00 UTC, code 0 (note écrite à 2026-11-18T20:29:30Z)

Journal : [`m1b-dnf-portee.log`](m1b-dnf-portee.log).
- **DP1 en partie** :
  - **Image d'outillage** : `python3-dnf-4.14.0-34.el9_8.rocky.0.1` a été construit le 19/05/2026 ; `dnf-data` aussi. Le paquet `dnf` lui-même n'est pas installé : l'image n'a que `python3-dnf` et `dnf-3`.
  - **Changelog** : sa première entrée (19/05/2026) est celle de Rocky (« Add Rocky bugtracker »). Les entrées de l'amont de la distribution ne sont pas lues : la date de construction ne dit pas quels correctifs y sont.
  - **Autres bibliothèques** : libdnf a été construit le 16/02/2026, librepo le 29/12/2025 et libsolv le 14/07/2026.
- **DP2 tenue** : l'arbre i3 (buildroot) n'a aucun de ces paquets.
- **DP3 en partie** :
  - `Package manager dnf4 detected` apparaît dans les journaux de mock de S1 (essais, verrou, `verrou_brut`, `verrou_derivee`) et de M3 (`build1`, `build2`, `buildv2`).
  - `dnf-3` ou `installroot` apparaît dans `boot_racine`, M2 (relevés 2 à 9) et `s1-m4b_mock_v2`.
  - **`s1-racine.log` ne contient aucun des quatre motifs**, alors que `racine` a installé l'outillage avec dnf (carte de M1b, point 2). Son journal n'archive pas cette commande.
- **DP4 non tenue** : `s1-m4b_mock_v2.log`, l'étape `m4b_mock_v2` de M4b, contient `installroot`. Aucun journal dont le nom cite M4c ne contient ces motifs. Ce n'est pas une preuve que dnf n'y a pas tourné : mock y a tourné dans des pods.

**Lecture** : dnf 4 a tourné dans la brique 05 au moins en S1, M2, M3 et M4b, par mock et par nos étapes. Le verdict ne concerne donc pas seulement M1b. Il appartient au propriétaire.

## Question du propriétaire sur dnf5 : prédictions écrites avant le lancement (2026-11-18T20:37:21Z UTC)

**Question** (reçue avant 2026-11-18T20:37:21Z UTC, heure exacte non relevée) : « et dnf5 ? il faut utiliser le bon outil avec la bonne distribution, non ? »

**Lecture préalable, sans journal**, reprise par le relevé : les gabarits `rhel-9.tpl` et `rocky-9.tpl` de mock-core-configs posent `package_manager = 'dnf'`, de même que `rhel-10.tpl` et `rocky-10.tpl`. Seul `fedora-branched.tpl` choisit `dnf5`, à partir de la version 40.

**Relevé** : [`m1b-dnf5.sh`](m1b-dnf5.sh). Il fait trois lectures :
- les gabarits de mock, hors ligne ;
- les listes de fichiers de Rocky 9.8, d'EPEL 9.8 et de Rocky 10, en lecture publique, non signées ;
- la santé de dnf5.

| # | Prédiction | Confiance |
|---|---|---|
| F1 | mock-core-configs choisit `dnf` (dnf 4) pour rhel et rocky 9 et 10, et `dnf5` seulement pour Fedora à partir de 40 (et d'autres distributions hors EL) | Haute : déjà lu sans journal |
| F2 | Rocky 9.8 (BaseOS et AppStream) n'a aucun paquet dnf5 | Haute |
| F3 | EPEL 9.8 n'a aucun paquet dnf5 | Moyenne : je ne l'ai jamais lu |
| F4 | Rocky 10 a dnf (4.x) dans BaseOS et aucun dnf5 | Moyenne : je crois que RHEL 10 a gardé dnf 4, sans l'avoir lu |
| F5 | dnf5 n'est pas archivé et a une release de moins de 6 mois | Haute |

**Ce qui est décidé d'avance** : la réponse au propriétaire ne donnera que les faits mesurés. Si F2 à F4 tiennent, dnf5 n'est pas l'outil de la distribution, ni pour Rocky 9, ni pour Rocky 10. Le verdict de dnf 4 reste au propriétaire.

## Résultat du relevé sur dnf5, du 18/11/2026, de 20:37:22 à 20:37:29 UTC, code 0 (note écrite à 2026-11-18T20:37:55Z)

Journal : [`m1b-dnf5.log`](m1b-dnf5.log).
- **F1 tenue** : mock-core-configs 45.2 pose `package_manager = 'dnf'` (dnf 4) pour rhel, rocky et centos-stream, en 9 comme en 10. Il ne choisit `dnf5` que pour Fedora (à partir de 40, et rawhide), et pour quelques distributions hors EL (Amazon Linux 2027, Azure Linux 4, Mageia, openSUSE Tumbleweed).
- **F2 tenue** : les listes de Rocky 9.8 (BaseOS et AppStream) n'ont aucun fichier dnf5. Seul figure `dnf-4.14.0-34.el9_8.rocky.0.1`.
- **F3 tenue** : la liste d'EPEL 9.8 (archive) n'a aucun fichier dnf5.
- **F4 tenue** : la liste de BaseOS de Rocky 10 a `dnf-4.20.0-28.el10.rocky.0.1`, et ni BaseOS ni AppStream n'ont de dnf5.
- **F5 tenue** : dnf5 n'est pas archivé. Sa dernière release est la 5.4.8.0, du 11/11/2026, avec 227 commits en 90 jours.

**Lecture** :
- **dnf5 n'est l'outil de la distribution ni pour Rocky 9, ni pour Rocky 10**, d'après ces listes non signées et d'après les gabarits de mock. L'outil que Rocky livre et que mock choisit pour EL est dnf 4.
- **Employer dnf5 ici** voudrait dire l'apporter hors de la distribution. Ce n'est pas mesuré.
- **Le verdict de dnf 4 reste au propriétaire.**

## Recommandation du conseiller sur dnf 4, et ses conditions : prédictions écrites avant le lancement (2026-11-18T20:41:01Z UTC)

**Demande du propriétaire** (reçue avant 2026-11-18T20:41:01Z UTC) : « Que recommande l'advisor ».

**Recommandation du conseiller**, rapportée comme la sienne : « À surveiller, chemin critique », par décision datée du propriétaire, sous une condition non mesurée.
- **Pour** :
  - le critère « Risqué » vise l'abandon, or le dépôt n'est pas archivé : 7 commits en 90 jours, 11 fusionneurs sur 100 PR ;
  - ce qui s'exécute est le paquet de Rocky, pas la release amont, et docs/04 juge déjà rpm ainsi ;
  - aucun autre outil n'existe dans la distribution (relevé dnf5).
- **Contre** :
  - ce serait une première : la pondération de docs/04 porte sur un critère « À surveiller » ;
  - l'amont décline : les releases s'espacent, puis cessent depuis 13 mois, et le README renvoie à DNF5 ;
  - aucun plan de sortie n'est mesuré.
- **Condition** : l'argument « maintenu par la distribution » ne repose que sur une date de construction et une entrée propre à Rocky. S'il n'y a aucun correctif de la distribution sur 12 mois, la recommandation tombe.
- **libsolv** : son verdict bloque autant que celui de dnf. Ma formule « mainteneur unique » est corrigée : le journal montre deux fusionneurs, mlschroe (95) et igor-raits (5). La date des fusions du second départage « bus factor de 2 » et « mainteneur unique ».

**Mesure** : [`m1b-dnf-conditions.sh`](m1b-dnf-conditions.sh).

| # | Prédiction | Confiance |
|---|---|---|
| K1 | Le changelog de python3-dnf (4.14.0-34) a, outre l'entrée de Rocky, au moins une entrée de la distribution amont depuis un an | Moyenne : passage de la -31 (9.7) à la -34 (9.8), contenu non lu |
| K2 | Au moins une de ces entrées porte un correctif (référence RHEL- ou CVE, ou mot « fix ») | Moyenne |
| K3 | libdnf, librepo et libsolv ont chacun au moins une entrée depuis un an | Moyenne : librepo construit le 29/12/2025, mais d'une version 1.19.0 peut-être ancienne |
| K4 | Les 5 fusions d'igor-raits sur libsolv sont toutes plus anciennes que les 95 de mlschroe | Basse : je n'en sais rien |

**Ce qui est décidé d'avance** : je rapporterai la recommandation et le résultat de sa condition, sans rien écrire dans docs/04, et sans reprendre dnf avant un oui explicite du propriétaire.

### Premier passage des conditions (18/11/2026, 20:41:02 UTC, code 0 ; note écrite à 2026-11-18T20:41:32Z)

**Le premier passage est défectueux, et son journal n'est pas archivé.**
- **Cause** : `rpm --qf` ne lit pas l'échappement `\x1e`, que j'avais pris pour séparateur. Les entrées des changelogs n'ont donc pas été séparées : chaque paquet compte « 1 entrée ».
- **Adresses** : le texte des entrées suivantes a laissé passer deux adresses de mainteneurs de la distribution, que le script devait retirer. Ces adresses sont publiques dans les paquets, mais le journal a été écrasé par le passage suivant, sans être commité.
- **Partie 2 lisible** : les 5 fusions d'igor-raits sur libsolv datent du 25/03/2019 au 13/08/2019. Les 95 de mlschroe vont du 13/02/2019 au 26/10/2026. Le passage corrigé la relit.

**Correction**, écrite avant le passage suivant :
- les séparateurs sont en clair (`@@T@@`, `@@FIN@@`) ;
- les adresses sont retirées aussi du texte ;
- les lignes qui citent `RHEL-`, `CVE-` ou « fix » sont comptées.

Les prédictions K1 à K4 sont inchangées.

### Résultat des conditions, du 18/11/2026, de 20:41:34 à 20:41:35 UTC, code 0 (note écrite à 2026-11-18T20:42:02Z)

Journal : [`m1b-dnf-conditions.log`](m1b-dnf-conditions.log).
- **K1 tenue** : outre l'entrée de Rocky, le changelog de python3-dnf 4.14.0-34 a trois entrées de la distribution amont depuis un an :
  - -32 du 9/01/2026 ;
  - -33 du 11/02/2026 ;
  - -34 du 25/03/2026.
- **K2 tenue, au sens du critère écrit** : chacune de ces entrées renvoie à un ticket RHEL :
  - `bootc` (RHEL-138512) ;
  - `autoremove` (RHEL-76112) ;
  - `dnf-automatic` (RHEL-94321).

  Ce sont des corrections de comportement. **Aucune ne cite de CVE.**
- **K3 tenue** : chaque bibliothèque a des entrées de la distribution depuis un an :
  - libdnf : deux, dont « Fix a crash… », RHEL-145618 ;
  - librepo : une, rebase vers 1.19.0, RHEL-62033 ;
  - libsolv : trois, dont la correction d'un débordement de tampon, CVE-2026-48864, le 5/06/2026.
- **K4 tenue** : les 5 fusions d'igor-raits datent de 2019 (25/03 au 13/08). Depuis août 2019, toutes les fusions des 100 dernières PR sont de mlschroe. libsolv a donc un mainteneur unique de fait ; son soutien (adresse suse.de) n'est pas mesuré.

**Lecture** : la condition du conseiller est remplie. dnf 4 et ses bibliothèques reçoivent des correctifs de la distribution sur les 12 derniers mois. La recommandation du conseiller (« À surveiller » par décision du propriétaire) tient donc. Le verdict reste au propriétaire. Il porte aussi sur libsolv : le critère « mainteneur unique sans soutien » se joue sur le soutien, qui n'est pas mesuré. Rien n'est écrit dans docs/04, et dnf n'est pas repris.

## Note datée du 18/11/2026, écrite à 2026-11-18T20:43:19Z UTC : décision « À surveiller » pour dnf 4 et libsolv

**Décision du propriétaire** (réponse reçue avant 2026-11-18T20:43:19Z UTC, heure exacte non relevée) : « À surveiller ». La question portait sur dnf 4 et libsolv : « « À surveiller » par pondération, ou « Risqué » ? ».
- **Contexte** : elle suit la recommandation du conseiller, rapportée à la demande du propriétaire, et la mesure de sa condition (correctifs de la distribution en 12 mois).
- **Consigné** : ligne au §3 de docs/04 et plan de sortie au §6, ce dernier marqué « non mesuré ».
- **Conséquence** : dnf n'est plus suspendu dans M1b. La relance du troisième banc, à partir du 19/11, et le banc du bootstrap reprennent.
- **Ce n'est pas un accord** pour une écriture dans le cluster ni dans Zot.

## Listes complètes de l'outillage et du bootstrap : prédictions écrites avant le lancement (2026-11-18T20:49:39Z UTC)

**Objet** : retirer la liste complète de l'outillage de la base rpm de `racine.tar`, comme le demande la leçon de S4a. C'est le préalable au banc de l'outillage, qui demandera de télécharger les 199 rpm. Le même passage lit `boot-racine.tar`, sans rien installer, pour préparer les prédictions du bootstrap.
- **Ordre** : choisi avec le conseiller, consulté avant la mesure.
- **Ce qui n'est pas supposé** : l'écart entre 201 paquets en base et 199 rpm téléchargés (`s1-racine.log`) est mesuré, pas attribué d'avance.

**Mesure** : [`m1b-listes.sh`](m1b-listes.sh), hors ligne, sur l'hôte seul. Les deux archives ne sont que lues.

| # | Prédiction | Confiance |
|---|---|---|
| L1 | `racine.tar` fait 361 758 720 octets, `d7433a05…` ; `boot-racine.tar` fait 258 129 920 octets, `8ae17f92…` | Haute : sha256 égaux le 18/11 (`m5b-archives.log`) |
| L2 | La base de l'outillage a 201 entrées : 199 se rapprochent une à une d'une ligne « rpm » de `s1-racine.log`, et les 2 autres sont des gpg-pubkey (Rocky 9 et EPEL 9). Aucune entrée sans ligne, aucune ligne sans entrée | Moyenne : l'écart de 2 n'a jamais été lu |
| L3 | Les 199 entrées de l'outillage ont un seul INSTALLTID, le 17/11/2026 entre 08:44:02 et 10:21:00 UTC ; leurs INSTALLTIME prennent plusieurs valeurs | Moyenne : installation de 5694 s, sans SOURCE_DATE_EPOCH |
| L4 | Le S de l'outillage est au moins le 19/05/2026 (construction de python3-dnf 4.14.0-34, lue dans cette racine) et avant le 10/11/2026 (révision de l'instantané EPEL) ; il diffère donc du S du buildroot (1778610852) | Haute pour la borne basse, moyenne pour la haute |
| L5 | La base du bootstrap a au moins 2 INSTALLTID. Celui du 17/11/2026 (entre 14:31:54 et 14:45:36 UTC) porte exactement 10 entrées, et il n'y a qu'une gpg-pubkey, venue de l'image | Moyenne : boot_racine a compté les dix NEVRA, pas les INSTALLTID |
| L6 | rpm n'écrit rien sur stderr en lisant les deux bases | Moyenne |

**Ce qui est décidé d'avance** :
- Si L2 n'est pas tenue, la liste écrite ne garde que les entrées rapprochées, et l'écart est consigné.
- Rien n'est épinglé avant la relecture de l'instantané `archive/epel/9.8`.
- Le banc de l'outillage, qui télécharge les 199 rpm, aura ses propres prédictions.

### Résultat des listes, du 18/11/2026, de 20:49:44 à 20:49:47 UTC, code 0 (note écrite à 2026-11-18T20:50:47Z)

Journal : [`m1b-listes.log`](m1b-listes.log). Liste épinglée : [`m1b-listes-outillage.txt`](m1b-listes-outillage.txt) (199 lignes : dépôt, fichier, sha256). Les copies des bases sont dans `~/.cache/supply-chain-poc/05/m1b-listes-20261118T204944Z`.

**Les six prédictions sont tenues.**
- **L1** : les deux archives ont la taille et le sha256 du journal de S1.
- **L2** : la base de l'outillage a 201 entrées. Les 199 rpm se rapprochent un à un des lignes de `s1-racine.log` : 169 de baseos98, 21 d'appstream98 et 9 d'epel9. Les 2 autres sont des gpg-pubkey, `350d275d` (Rocky 9) et `3228467c` (EPEL 9). Aucune entrée sans ligne, aucune ligne sans entrée.
- **L3** : les 199 rpm ont un seul INSTALLTID (17/11/2026, 08:45:29 UTC) et 22 valeurs d'INSTALLTIME, de 08:45:30 à 09:48:36 UTC. Les deux gpg-pubkey ont leur propre INSTALLTID, 10 s plus tôt (08:45:19 UTC).
- **L4** : le S de l'outillage vaut 1793914619, soit le 5/11/2026 à 21:36:59 UTC (plus grande FILEMTIMES ; plus grand BUILDTIME le même jour à 21:13:36). Il diffère de celui du buildroot. Le paquet qui le porte n'est pas lu.
- **L5** : la base du bootstrap a 153 entrées et 3 INSTALLTID :
  - 142 entrées le 23/11/2025 à 18:17:49 UTC, l'image `rockylinux:9.7` ;
  - la seule gpg-pubkey (`350d275d`), 10 s plus tard, dans la même image ;
  - 10 entrées le 17/11/2026 à 14:32:27 UTC, les dix lignes, avec 2 valeurs d'INSTALLTIME.

  Son S vaut 1766985142 (29/12/2025, 05:12:22 UTC). Il est postérieur à l'image : il vient donc des dix lignes.
- **L6** : rpm n'écrit rien sur stderr.

**Ce que cela change pour le banc de l'outillage** :
- Les gpg-pubkey entrent dans la base, avec leur propre INSTALLTID. Le troisième banc n'en avait aucune ; il faudra mesurer si SOURCE_DATE_EPOCH les fixe aussi.
- Le bootstrap mêle deux époques : 143 entrées figées par l'image et 10 posées le jour de l'installation. Une reproduction devra au moins fixer ces 10.

**Inchangé** : rien n'est épinglé avant la relecture de l'instantané `archive/epel/9.8`. Les 9 rpm d'EPEL de la liste viennent du dépôt EPEL 9 vivant du 17/11 ; `m1b-sources.log` les a trouvés dans l'instantané, 9 sur 9, avec le même fichier et le même sha256 (relevé du 18/11, `repomd.xml` `e86fdcd8…`, non signé).

## Banc de l'outillage : prédictions écrites avant le lancement (2026-11-18T20:54:44Z UTC)

**Question** : deux installations de l'outillage, faites sous SOURCE_DATE_EPOCH depuis un miroir partiel, donnent-elles la même archive bornée ? Le miroir garde les métadonnées amont et les 199 rpm de la liste épinglée.
- **Forme** : choisie avec le conseiller. C'est la forme de la future tâche : `dnf install` des six noms de l'étape racine de S1, sur un miroir en `file://` avec les métadonnées amont. Un témoin installe les 199 fichiers locaux, dépôts coupés, comme le troisième banc. Le banc vise deux angles morts d'un coup : le jeu de paquets de l'outillage et le miroir partiel.
- **Relecture** : le `repomd.xml` de l'instantané `archive/epel/9.8` est relu et comparé à la copie du 18/11. S'il a changé, le banc s'arrête avant tout téléchargement de rpm.
- **Téléchargements** : 199 rpm et les métadonnées des trois dépôts, sous `~/.cache/supply-chain-poc/05/`. Ce n'est pas une installation système. Chaque fichier est vérifié par sha256 contre `repomd.xml` (signé pour vault), le primary et la liste épinglée, puis par `rpm -K` avec les deux clés. Les bases sqlite `*_db`, que dnf 4 ne lit pas, ne sont pas téléchargées.
- **Outils** : la racine d'outils reste celle de `99790c13`, comme au troisième banc. Le rpm et le dnf de l'amorce `ed654c69` restent un angle mort.

**Mesure** : [`m1b-outil.sh`](m1b-outil.sh).

| # | Prédiction | Confiance |
|---|---|---|
| O1 | Les trois `repomd.xml` sont égaux aux copies du 18/11 ; ceux de vault ont une signature valide de la clé de Rocky ; l'instantané d'EPEL n'a pas bougé | Haute pour vault, moyenne pour EPEL |
| O2 | Toutes les métadonnées téléchargées ont le sha256 de `repomd.xml`. Les 199 rpm sont trouvés dans les primary avec le sha256 de la liste, et téléchargés conformes ; `rpm -K` donne 199 « digests signatures OK » | Moyenne : 199 sur 199 dans S1 |
| O3 | S, calculé par `rpm -qp` sur les 199 fichiers, vaut 1793914619, comme dans la base de `racine.tar` | Haute |
| O4 | i5 et i6 : dnf rend 0 ; 201 entrées, les 199 NEVRA de `racine.tar` et 2 gpg-pubkey | Moyenne : EPEL vient de l'instantané, pas du dépôt vivant du 17/11 |
| O5 | Dans i5 et i6, les 199 rpm ont un INSTALLTID égal à S et 199 INSTALLTIME consécutifs, de S à S + 198 | Moyenne : forme du troisième banc, autre jeu de paquets |
| O6 | Les gpg-pubkey de i5 et i6 ont un INSTALLTIME et un INSTALLTID égaux à S | Basse : je ne sais pas si l'import des clés lit SOURCE_DATE_EPOCH |
| O7 | `a5.tar` et `a6.tar` sont identiques octet à octet, et `a5b.tar` aussi | Moyenne : dépend de O6 et du cache de dnf exclu |
| O8 | i7 (fichiers locaux) : dnf rend 0, 199 entrées, aucune gpg-pubkey. `a7.tar` diffère de `a5.tar`, mais seulement par `var/lib/rpm/rpmdb.sqlite` | Basse |
| O9 | Contenu seul de `a5.tar` contre `racine.tar` : les membres propres à `racine.tar` sont les fichiers exclus ; les contenus ne diffèrent que dans `rpmdb.sqlite` et le `cacerts` de Java | Basse |

**Ce qui est décidé d'avance** :
- Si O1 n'est pas tenue pour EPEL, le banc s'arrête et l'instantané est déclaré mobile. Rien n'est épinglé.
- Si O7 est tenue, j'écrirai « neutralisable sur le banc pour l'outillage », jamais « établi » : il resterait un autre jour, le rpm et le dnf de l'amorce, et le bootstrap.
- Rien n'est écrit dans le cluster ni dans Zot.

### Premier passage du banc de l'outillage (18/11/2026, de 20:54:47 à 20:55:47 UTC, code 1 ; note écrite à 2026-11-18T20:57:10Z)

Journal : [`m1b-outil-1.log`](m1b-outil-1.log). **Le passage s'arrête à la première installation.**
- **Avant l'arrêt** : O1, O2 et O3 sont tenues.
  - Les trois `repomd.xml` sont égaux aux copies du 18/11, et ceux de vault ont une signature valide de la clé de Rocky. L'instantané d'EPEL (`e86fdcd8…`) n'a pas bougé.
  - Les 199 rpm (113 665 783 octets) ont le sha256 de la liste et des primary, et `rpm -K` donne 199 « digests signatures OK ».
  - S vaut 1793914619.
- **Arrêt** : dnf rend 1 sur baseos98, avec « repomd.xml GPG signature verification error » et « Invalid crypto engine » (gpgme).
- **Défaut secondaire** : le porteur de la plus grande FILEMTIMES est vide, car la balise NEVRA d'un format tableau doit s'écrire `%{=NEVRA}`.

**Diagnostic** : [`m1b-outil-diag.sh`](m1b-outil-diag.sh), [journal](m1b-outil-diag.log), lecture seule sur la racine d'outils du passage.
- La racine d'outils n'a ni `/dev` (exclu à l'extraction des couches, comme au troisième banc) ni `/proc`. Sans `/proc`, gpgconf ne lit pas `/proc/self/exe`.
- Avec `/dev` lié et `/proc` monté, gpgme trouve `/usr/bin/gpg` 2.3.3, et aucun montage ne reste après la sortie.
- Le troisième banc n'avait pas rencontré ce défaut : il installait des fichiers locaux, sans vérification de dépôt.
- gpgconf donne pour homedir le HOME de l'hôte, hérité dans la racine.

**Correction**, écrite avant le passage suivant :
- La racine d'outils reçoit `/dev` (lié) et `/proc`, dans un espace de montage et de processus propre, qui disparaît avec chaque commande.
- `HOME=/root`.
- Le porteur s'écrit `%{=NEVRA}`.

**Effet sur les prédictions** : O1 à O9 sont inchangées, et O1 à O3 seront relues au passage corrigé. Le troisième banc tournait sans `/proc`, et les scriptlets peuvent s'y comporter autrement : la comparaison avec lui n'est donc pas directe. Le pod Kata de la future tâche a `/proc`.

### Résultat du banc de l'outillage, passage corrigé du 18/11/2026, de 20:57:14 à 20:59:22 UTC, code 0 (note écrite à 2026-11-18T21:01:09Z)

Journal : [`m1b-outil.log`](m1b-outil.log). Les adresses e-mail de la clé de Rocky, affichées par dnf, en ont été retirées après le passage. Analyse des écarts : [`m1b-outil-analyse.sh`](m1b-outil-analyse.sh), [journal](m1b-outil-analyse.log). Arbres et archives : `~/.cache/supply-chain-poc/05/m1b-outil-20261118T205714Z`, laissés en place.
- **Erreur dans l'analyse** : son premier lancement visait un dossier deviné (`…205713Z`) au lieu du dossier réel (`…205714Z`), et s'est arrêté sur « banc absent ». Le chemin a été corrigé, puis l'analyse relancée.

**Tenues : O1 à O6.**
- **O1** : les trois `repomd.xml` sont égaux aux copies du 18/11, et ceux de vault sont signés par la clé de Rocky. **L'instantané `archive/epel/9.8` n'a pas bougé** (`e86fdcd8…`) : c'est sa relecture.
- **O2** : les métadonnées ont le sha256 de `repomd.xml`. Les 199 rpm (113 665 783 octets) ont le sha256 de la liste et des primary, et `rpm -K` donne 199 « digests signatures OK ».
- **O3** : S vaut 1793914619. Il est porté par glibc-common 2.34-284.el9_8.4.
- **O4** : i5 et i6 ont chacune 201 entrées : les 199 NEVRA de `racine.tar` et les 2 gpg-pubkey. Le miroir partiel et l'instantané d'EPEL résolvent donc les mêmes paquets que S1.
- **O5** : les 199 rpm ont un INSTALLTID égal à S, et des INSTALLTIME de S à S + 198.
- **O6** : les 2 gpg-pubkey ont un INSTALLTIME et un INSTALLTID égaux à S.

**Non tenues : O7, O8 (en partie) et O9.**
- **O7** : `a5.tar` et `a6.tar` diffèrent (`babac006…` et `edb00b6d…`), alors que le témoin `a5b.tar` est égal à `a5.tar`. **Un seul membre diffère, `etc/machine-id`.** Il fait 33 octets, avec un contenu différent dans chaque installation (i5, i6, i7) et dans `racine.tar`. Les journaux de dnf ne citent pas machine-id : le scriptlet qui l'écrit n'est pas identifié. Le troisième banc tournait sans `/proc` ; cet écart n'y apparaissait pas, et la cause de cette différence n'est pas mesurée.
- **O8** : i7 rend 0, avec 199 entrées et aucune gpg-pubkey (tenu). Mais `a7.tar` diffère de `a5.tar` par `etc/machine-id` en plus de `rpmdb.sqlite` (non tenu).
- **O9** : les 8 membres propres à `racine.tar` sont bien les fichiers exclus (tenu). Mais `a5.tar` a 2 533 membres de plus, presque tous sous `usr/share/locale` : 2 567 membres et 1 157 fichiers `.mo`, contre 34 et 7 dans `racine.tar`. Six membres communs diffèrent :
  - `etc/machine-id` ;
  - le `cacerts` de Java ;
  - `rpmdb.sqlite` ;
  - `etc/shadow` et `etc/shadow-` : le troisième champ de 2 lignes vaut 20762, le jour de S, dans le banc, et 20774, le 17/11/2026, dans `racine.tar` ;
  - le mode de `var/lib/dnf` : 0775 dans le banc, 0755 dans `racine.tar`.

**Lecture**, sans conclusion au-delà de la mesure :
1. **machine-id** : c'est le seul écart entre deux installations du banc. Il faut le neutraliser (par exemple, le vider), ce qui n'est pas mesuré. À ce membre près, deux installations de l'outillage donnent la même archive.
2. **Les outils comptent.** La racine d'outils de `99790c13` n'a aucune macro `%_install_langs` ni `override_install_langs`. Elle installe donc toutes les langues, alors que l'installation de S1, faite par le dnf de l'amorce `ed654c69`, n'en a gardé que peu. La configuration de l'amorce n'est pas lue, car elle n'est pas en local. C'est l'angle mort « rpm et dnf de l'amorce », désormais visible.
3. **umask** : le mode 0775 de `var/lib/dnf` suggère que le umask des commandes de l’hôte (0002, lu après le passage) est passé dans le banc ; le lien n’est pas mesuré. La tâche devra fixer son umask.
4. **shadow** : SOURCE_DATE_EPOCH fixe aussi le jour du dernier changement. Sans la variable, ce champ vaut le jour de l'installation.

**Conséquence** : le point 1 A n'est pas neutralisable sur le banc pour l'outillage, à cause de machine-id. Il n'est pas établi non plus. Restent : machine-id, les outils de l'amorce (langues, umask), un autre jour et le bootstrap.

### Corrections du résultat du banc de l'outillage (note écrite à 2026-11-18T21:03:44Z UTC, après relecture par le conseiller)

Trois formules dépassent la mesure. Elles sont corrigées ici, le texte d'origine restant en place.
1. **« Le point 1 A n'est pas neutralisable sur le banc pour l'outillage »** devient : **machine-id n'a pas été neutralisé sur ce banc.** Le banc n'a tenté aucune neutralisation ; on ne peut donc pas dire qu'elle est impossible.
2. **Langues et umask** : le banc mesure 2 533 membres en plus et un mode 0775 au lieu de 0755, pas leur cause.
   - Le umask n'a jamais été varié, et l'amorce `ed654c69` n'a pas été lue.
   - Le relevé de `override_install_langs` dans le `etc/dnf/dnf.conf` des outils ne départage rien : le banc et S1 passent tous deux `-c` à dnf, qui ne lit donc pas ce fichier.
   - Pour départager, il faut lire `rpm -E '%_install_langs'` dans l'amorce.
   - Les mêmes formules du README, de docs/03 et de l'ADR 0007 (« les outils font partie de l'entrée ») sont des hypothèses.
3. **« Le pod Kata de la future tâche a `/proc` »** : le pod de l'étape racine de S1 l'avait. Sa ligne « invité » lit `/proc/meminfo` : « invité : 6.18.56, 3 vCPU, 6119664 kB ; /w : tmpfs » ([`s1-racine.log`](s1-racine.log), l. 3). Le pod de la future tâche n'existe pas encore.

**Script** : `m1b-outil.sh` retire désormais lui-même les adresses des identités de clé. Un nouveau passage écrira dans un nouveau journal, car `m1b-outil.log` est commité.

### Ré-archivage sans `etc/machine-id` : lecture et prédictions (écrites à 2026-11-18T21:08:40Z UTC, avant le lancement)

**Lecture faite avant les prédictions** ([script](m1b-machine-id.sh), [journal](m1b-machine-id.log)), sur les 199 fichiers rpm du miroir partiel (`rpm -qp`), sans toucher aux arbres :
- Un seul paquet déclare `/etc/machine-id` : systemd 252-67.el9_8.6.rocky.0.1, avec les drapeaux `cng` (config, noreplace, ghost), le mode 0444 et une taille de 0 : rpm ne livre pas de contenu.
- Son scriptlet `%post` lance `systemd-machine-id-setup`, qui écrit l'identifiant. Une autre ligne du même scriptlet lit `/etc/machine-id` pour changer le groupe des dossiers du journal. Aucun autre scriptlet ni trigger des 199 rpm ne cite machine-id.
- Dans i5, i6 et i7, le fichier fait 33 octets, en mode 0444, avec une mtime à l'heure de l'installation (ex. 1795035511 pour i5), et non à S. L'archive la ramène à S par `--clamp-mtime`.

**Ce qui est lancé** ([`m1b-sans-machine-id.sh`](m1b-sans-machine-id.sh)) : hors ligne, sur les arbres laissés du passage de 20:57:14 UTC, un témoin `t5` (i5 avec les exclusions du passage), puis `b5`, `b6` et `b7` avec `--exclude=./etc/machine-id` en plus. Les archives vont dans un dossier neuf ; les arbres ne sont pas modifiés.

**Prédictions :**
- **MS1** : `t5.tar` a le sha256 de `a5.tar` du passage (`babac006…`). Les lectures faites depuis (analyse, stat, cat) n'ont pas changé ce que l'archive retient.
- **MS2** : `b5`, `b6` et `b7` n'ont aucun membre `./etc/machine-id`. `b5` a exactement un membre de moins que `t5`.
- **MS3** : `b5.tar` et `b6.tar` sont identiques octet à octet.
- **MS4** : `b5` et `b7` n'ont aucun membre d'un seul côté, et un seul membre différent : `var/lib/rpm/rpmdb.sqlite`.

**Portée, avant le lancement** : même si MS1 à MS4 tiennent, ce banc ne montre qu'une chose : **exclure** ce membre suffit à rendre égales deux installations faites le même jour avec la racine d'outils de `99790c13`. Restent non mesurés :
- le choix entre un fichier vide et un fichier absent, qui revient à la carte ;
- un autre jour ;
- les outils de l'amorce (langues, umask) ;
- le bootstrap.

Le point 1 A reste non établi.

### Résultat du ré-archivage sans `etc/machine-id`, 18/11/2026, de 21:08:52 à 21:08:57 UTC, code 0 (note écrite à 2026-11-18T21:09:22Z UTC)

Journal : [`m1b-sans-machine-id.log`](m1b-sans-machine-id.log). Archives laissées dans `~/.cache/supply-chain-poc/05/m1b-sans-machine-id-20261118T210852Z`.

**MS1 à MS4 tenues.**
- **MS1** : `t5.tar` a le sha256 de `a5.tar` du passage (`babac006…`, 15 866 membres).
- **MS2** : `b5`, `b6` et `b7` n'ont aucun membre `./etc/machine-id`. Elles ont 15 865 membres chacune, soit un de moins que `t5`.
- **MS3** : `b5.tar` et `b6.tar` sont identiques octet à octet, avec le sha256 `05d35d64f09692b13bd08af86b405607bca75c72d359550864fcf89a0321a59a`. **C'est la référence du 18/11 pour l'outillage sans machine-id.**
- **MS4** : `b7` (`9f87c36f…`) n'a aucun membre d'un seul côté, et un seul membre diffère de `b5` : `var/lib/rpm/rpmdb.sqlite`.

**Lecture** : avec la racine d'outils de `99790c13`, le même jour, deux installations de l'outillage par nom donnent la même archive, dès que `etc/machine-id` en est exclu. L'installation par fichiers, sans gpg-pubkey, ne diffère que par la base rpm.

Restent non mesurés :
- le choix entre un fichier vide et un fichier absent ;
- un autre jour (à partir du 19/11) ;
- les outils de l'amorce (langues, umask) ;
- le bootstrap.

Le point 1 A reste non établi.

### Lecture de l'amorce `ed654c69`, 18/11/2026, de 21:10:51 à 21:10:52 UTC, code 0 (note écrite à 2026-11-18T21:11:17Z UTC)

**Correction** : plusieurs notes du 18/11 disent que l'amorce « n'est pas en local » : l'en-tête de `m1b-outil-analyse.sh`, les prédictions du troisième banc (point 3, « Mauvais installeur ») et le résultat du banc de l'outillage (lecture, point 2). **C'est faux.** `s1.sh amorce` l'a copiée dans le cache OCI `~/.cache/supply-chain-poc/08/telechargements/oci/amont/rockylinux/rockylinux` (voir [`s1-amorce.log`](s1-amorce.log), l. 2). Je ne l'avais pas cherchée là. Le manifeste, la configuration et l'unique couche y sont présents, et leur sha256 est égal à leur nom. C'est aussi le cas de `ee90dc0e`, l'image du bootstrap : manifeste, configuration et couche `812c4412…`, vérifiés à la main avant ce script.

**Lecture** ([script](m1b-amorce-lecture.sh), [journal](m1b-amorce-lecture.log)), hors ligne, dans la couche extraite :
- **Versions** : rpm 4.16.1.3-40.el9, dnf 4.14.0-34.el9_8.rocky.0.1, libsolv 0.7.24-4.el9, libdnf 0.69.0-18.el9.rocky.0.1.
- **Langues** : `%_install_langs` vaut `en_US` dans l'amorce. Il est posé par `/etc/rpm/macros.image-language-conf`. La racine d'outils de `99790c13` donne `all`, et aucun de ses fichiers ne cite `install_langs`.
- **dnf.conf** : celui de l'amorce a `tsflags=nodocs`. S1 et le banc passent `-c` à dnf ; ce fichier n'est donc pas lu à l'installation (lecture du script, non mesurée).
- **umask** : la configuration de l'image n'en porte pas (Env `container=oci`, Cmd `/bin/bash`). Il vient du lanceur, et il n'est pas lu ici.

**Ce que cela change** : l'hypothèse « langues des outils » a désormais une cause lisible : `en_US` contre `all`. Le lien avec les 34 membres de `racine.tar` reste à mesurer. Il faut refaire le banc de l'outillage avec la racine de l'amorce comme outils, sous `umask 022`, après des prédictions commitées. La racine extraite est laissée dans `~/.cache/supply-chain-poc/05/m1b-amorce-20261118T211051Z/racine`.

### Compléments à la lecture de l'amorce (note écrite à 2026-11-18T21:13:18Z UTC, après relecture par le conseiller)

1. **`ee90dc0e` archivé** : la vérification « à la main » de l'image du bootstrap n'avait laissé aucun journal. Elle est refaite par [`m1b-images-locales.sh`](m1b-images-locales.sh) ([journal](m1b-images-locales.log)), de 21:12:59 UTC, code 0. Pour les deux images, le manifeste, la configuration et la couche ont la taille et le sha256 attendus (6 « OK »).
2. **Balayage des notes fausses** : j'ai cherché « pas en local », « n'ai pas en local », « non lisible » et « seule lisible » dans la brique 05, docs/03, l'ADR 0007 et la mémoire. Les trois endroits listés dans la correction sont les seuls trouvés.
3. **Portée de la référence `05d35d64`** : elle ne vaut que pour la racine d'outils de `99790c13`, sous le umask des commandes de l'hôte (0002). Un banc fait avec les outils de l'amorce, sous `umask 022`, donnera une autre archive, qui ne se compare pas à `05d35d64`. Si cette configuration est retenue, il lui faudra sa propre référence du même jour avant la relance d'un autre jour.
4. **Avant les prédictions de ce banc** :
   - lire l'étape racine de `s1.sh` pour savoir si le pod a tourné sur `ed654c69` sans rien y installer ni changer avant `dnf --installroot`, et quel umask il avait ;
   - relire `%_install_langs` dans le banc lui-même, comme témoin.

### Banc de l'outillage avec les outils de l'amorce : lecture et prédictions (écrites à 2026-11-18T21:25:06Z UTC, avant le lancement)

**Lecture de l'étape racine de [`s1.sh`](../s1.sh)**, faite avant ces prédictions. Elle porte sur le fichier du passage du 17/11 (08:44:02 UTC) : à `b70f384`, `s1.sh` a le sha256 `ad16fc99…`. Ses fonctions `etape_racine`, `dnf_conf`, `dans`, `livrer`, `pod_demarrer` et son script `RACINE` sont égaux, au sha256 près, à ceux du fichier actuel. `pod_spec` ne diffère que par `sleep 10800` au lieu de `sleep 43200` (correctif de durée, appliqué après le passage).
- **Base du pod** : le pod `s1-05-racine` tourne sur `$AMORCE`, c'est-à-dire `ed654c69` par digest (l. 169 et 434 du fichier actuel). Son conteneur ne lance que `sleep` (`pod_spec`). `etape_racine` (l. 430 à 449, lue en entier) ne fait, avant le script, que livrer deux clés et `/w/dnf.conf` (l. 436 à 438). Le script `RACINE` (l. 355 à 379) n'installe rien dans l'amorce et ne change pas sa configuration. **Les outils de l'étape racine sont donc l'amorce nue.**
- **umask** : le `umask 022` de la l. 192 s'applique sur l'hôte, au script lui-même. Le script `RACINE` ne fixe aucun umask : il hérite de celui de `kubectl exec … sh -s` dans le pod Kata. [`s1-racine.log`](s1-racine.log) ne le relève pas. **Le umask du pod n'est pas mesuré.** Seul indice : `var/lib/dnf` a le mode 0755 dans `racine.tar`, ce qui va avec un umask de 022, sans le prouver.
- **Commande** : `dnf -y -c /w/dnf.conf --setopt=reposdir=/w/aucun --installroot=/w/racine --releasever=9 install …` (l. 366), donc `/usr/bin/dnf` de l'amorce. Sa configuration (`dnf_conf`, l. 381) a `tsflags=nodocs` et `install_weak_deps=0`, comme celle du banc de 20:57:14 UTC.

**Ce qui est lancé** ([`m1b-outil-amorce.sh`](m1b-outil-amorce.sh)), entièrement hors ligne :
- le miroir partiel du banc de 20:57:14 UTC est copié dans un dossier neuf et revérifié (repomd, signatures de vault, métadonnées, 199 rpm) ;
- la couche de l'amorce est extraite et sert de racine d'outils, avec `umask 022` fixé dans chaque commande ;
- quatre installations par nom ont la forme de S1, sous `SOURCE_DATE_EPOCH=S` et `container=oci` (Env de l'image) : `i8` et `i9` sous `umask 022` ; le témoin `i10` sous `umask 022`, avec `/etc/rpm/macros.image-language-conf` de la racine d'outils masqué (`/dev/null` lié dessus) ; le témoin `i11` sous `umask 0002` ;
- les archives sont bornées à S, avec les exclusions du ré-archivage (dont `etc/machine-id`) : `a8`, `a9`, le témoin `a8b`, `a10` et `a11` ;
- comparaisons de contenu : `a8` contre `racine.tar`, `a10` contre `a8`, `a11` contre `a8`.

**Prédictions :**
- **AO1** : les trois `repomd.xml` du miroir copié sont égaux aux copies du 18/11. Ceux de vault sont signés par la clé de Rocky. Les métadonnées et les 199 rpm ont le sha256 attendu.
- **AO2** : dans la racine d'outils, le umask vaut `0022` et `%_install_langs` vaut `en_US`. Témoins : le umask de `i11` vaut `0002`, et `%_install_langs` vaut `all` quand la macro de l'image est masquée. Les versions sont celles de la lecture de l'amorce (rpm 4.16.1.3-40.el9, dnf 4.14.0-34.el9_8.rocky.0.1).
- **AO3** : `rpm -K` donne 199 « digests signatures OK » sur 199, et S vaut 1793914619.
- **AO4** : dnf rend 0 pour `i8`, `i9`, `i10` et `i11`. Chacune a 201 entrées : les 199 NEVRA de `racine.tar` et 2 gpg-pubkey.
- **AO5** : `a8.tar` et `a9.tar` sont identiques octet à octet, et le témoin `a8b.tar` est égal à `a8.tar`.
- **AO6** (langues) : `a8` et `racine.tar` ont le même nombre de membres sous `usr/share/locale` : 34, dont 7 fichiers `.mo`. Aucun membre n'est seulement dans `a8`.
- **AO7** (reste de l'écart avec S1) : 9 membres ne sont que dans `racine.tar`, soit les 8 fichiers exclus et `etc/machine-id`. Exactement 4 membres communs diffèrent : le `cacerts` de Java, `etc/shadow`, `etc/shadow-` et `rpmdb.sqlite`. Aucun écart de mode, `var/lib/dnf` compris.
- **AO8** (témoin de langue) : `a10` a 2 567 membres sous `usr/share/locale`, dont 1 157 fichiers `.mo`, comme `a5` au banc de 20:57:14 UTC. Il a 2 533 membres de plus que `a8`, aucun de moins, et un seul membre commun diffère : `rpmdb.sqlite`.
- **AO9** (témoin de umask) : `a11` et `a8` ont les mêmes membres. Un seul diffère : `var/lib/dnf`, par son mode (0775 contre 0755).

**Confiance** : AO1 à AO4 sont des relectures. AO5 suit le ré-archivage de 21:08:52 UTC, mais avec d'autres outils. AO6 à AO9 sont le vrai test de l'hypothèse « langues et umask des outils ». AO8 et AO9 sont moyennes : d'autres membres (dossiers créés par des scriptlets, base rpm) peuvent bouger avec la macro ou le umask. Si AO6 ne tient pas, la cause des 2 533 membres reste ouverte.

**Portée, avant le lancement** : même si tout tient, ce banc montre seulement trois choses, le même jour. Avec les outils de l'amorce sous `umask 022`, deux installations donnent la même archive. Ces outils donnent les mêmes membres de langues que `racine.tar`. Et, dans ces outils, masquer la seule macro `macros.image-language-conf` suffit à ramener toutes les langues. Ce dernier point attribue l'écart à cette macro **sur le banc** ; il ne dit rien du pod Kata. Le umask du pod Kata reste non mesuré ; le témoin `i11` montre seulement l'effet d'un umask sur ce banc. Écart connu avec S1 : le banc tourne dans un chroot sous `unshare`, pas dans un pod Kata. Si AO5 tient, `a8.tar` devient la référence du 18/11 pour cette configuration, distincte de `05d35d64`. Restent non mesurés : un autre jour, le choix entre fichier vide et fichier absent pour machine-id, et le bootstrap. Le point 1 A reste non établi.
