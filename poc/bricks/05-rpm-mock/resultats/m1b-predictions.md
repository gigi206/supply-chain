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

### Résultat du banc avec les outils de l'amorce, 18/11/2026, de 21:25:17 à 21:27:20 UTC, code 0 (note écrite à 2026-11-18T21:28:20Z UTC)

Journal : [`m1b-outil-amorce.log`](m1b-outil-amorce.log). Modes de `var/lib/dnf`, relus après le passage : [`m1b-outil-amorce-modes.sh`](m1b-outil-amorce-modes.sh), [journal](m1b-outil-amorce-modes.log) (21:27:39 UTC). Arbres et archives laissés dans `~/.cache/supply-chain-poc/05/m1b-outil-amorce-20261118T212517Z`.

**AO1 à AO9 tenues.**
- **AO1** : les trois `repomd.xml` du miroir copié sont égaux aux copies du 18/11, et ceux de vault sont signés par la clé de Rocky. Les métadonnées et les 199 rpm (113 665 783 octets) ont le sha256 attendu.
- **AO2** : dans la racine d'outils, le umask vaut `0022` et `%_install_langs` vaut `en_US`. Témoins : `0002` pour `i11`, et `all` quand la macro de l'image est masquée. Versions : rpm 4.16.1.3-40.el9, dnf 4.14.0-34.el9_8.rocky.0.1.
- **AO3** : 199 « digests signatures OK » sur 199, et S = 1793914619.
- **AO4** : dnf rend 0 pour les quatre installations. Chacune a 201 entrées : les 199 NEVRA de `racine.tar` et 2 gpg-pubkey.
- **AO5** : `a8.tar` et `a9.tar` sont identiques octet à octet, et le témoin `a8b.tar` aussi : 13 332 membres, sha256 `06c289ad8da33198dd845be6cc899f688ecfb8986e77e4b333629e838876dfa5`. **C'est la référence du 18/11 pour l'outillage fait avec les outils de l'amorce sous `umask 022`**, distincte de `05d35d64`.
- **AO6** : `a8` et `racine.tar` ont chacun 34 membres sous `usr/share/locale`, dont 7 `.mo`. Aucun membre n'est seulement dans `a8`.
- **AO7** : 9 membres ne sont que dans `racine.tar` : les 8 fichiers exclus et `etc/machine-id`. 4 membres communs diffèrent, tous par leur contenu : le `cacerts` de Java, `etc/shadow`, `etc/shadow-` et `rpmdb.sqlite`. Aucun écart de mode : `var/lib/dnf` est en 0755 des deux côtés.
- **AO8** : `a10` (macro masquée) a 2 567 membres sous `usr/share/locale`, dont 1 157 `.mo`. Il a 2 533 membres de plus que `a8`, aucun de moins, et seul `rpmdb.sqlite` diffère.
- **AO9** : `a11` (umask 0002) a les mêmes membres que `a8`. Seul `var/lib/dnf` diffère, par son mode : 0775 contre 0755.

**Lecture**, sans conclusion au-delà de la mesure :
1. **Langues** : sur ce banc, avec les outils de l'amorce, masquer la seule macro `macros.image-language-conf` fait passer de 34 à 2 567 membres de langues. Les 2 533 membres en plus du banc de 20:57:14 UTC s'expliquent donc, sur le banc, par cette macro des outils.
2. **umask** : sur ce banc, le umask des outils décide du mode de `var/lib/dnf`, et de lui seul. `racine.tar` a 0755, ce qui va avec un umask de 022 dans le pod. Le umask du pod Kata reste non mesuré.
3. **Écart restant avec S1** : à part `etc/machine-id` et les fichiers exclus, seuls 4 contenus diffèrent. Ce sont ceux qui dépendent de l'heure d'installation : S1 tournait sans `SOURCE_DATE_EPOCH`. Pour `shadow`, c'est mesuré (banc de 20:57:14 UTC) ; pour `cacerts` et `rpmdb.sqlite`, c'est l'hypothèse des bancs précédents, non isolée ici.

**Conséquence** : la tâche future devra fixer ses outils (l'amorce par digest, avec sa macro de langue), son umask (022) et `SOURCE_DATE_EPOCH`, et écarter `etc/machine-id` et les fichiers listés. Avec cela, deux installations du même jour donnent la même archive. Restent non mesurés : un autre jour (à partir du 19/11, à comparer à `06c289ad…`), le choix entre fichier vide et fichier absent pour machine-id, le bootstrap, et le pod Kata lui-même. **Le point 1 A reste non établi.**

### Corrections au résultat du banc avec les outils de l'amorce, et prédiction de la comparaison `a10` contre `b5` (note écrite à 2026-11-18T21:30:15Z UTC, après relecture par le conseiller, avant le lancement)

**Corrections** (le texte d'origine reste en place) :
1. **« Conséquence »** : la phrase « la tâche future devra fixer ses outils (…), son umask (022) (…). Avec cela, deux installations du même jour donnent la même archive » dépasse la mesure. Elle devient : **sur le banc**, les outils, leur umask et `SOURCE_DATE_EPOCH` sont des entrées de l'archive, à fixer. Le banc ne dit pas quelles valeurs retenir : garder `en_US` et 022 (les valeurs de S1) est un choix qui revient à la carte, donc au propriétaire. Le pod Kata n'est pas mesuré.
2. **Conditions de la référence `06c289ad…`** : outils = couche `99c753a8…` de l'amorce `ed654c69`, macro de langue en place ; `umask 022` ; `container=oci` et `SOURCE_DATE_EPOCH=1793914619` dans l'environnement de dnf ; `dnf.conf` de sha256 `d554fb1c…` ; exclusions de l'archive du script, dont `./etc/machine-id`. La relance d'un autre jour devra reprendre [`m1b-outil-amorce.sh`](m1b-outil-amorce.sh) inchangé ; celle de `05d35d64…` reprendra ses propres scripts, inchangés.
3. **« Même dnf.conf que le banc de 20:57:14 UTC »** (en-tête du script) : c'est vérifié, les deux journaux donnent le même sha256, `d554fb1ce168663fbfbfaffa175056f049506a2fa33675acb63dedf2969d03cc` ([`m1b-outil.log`](m1b-outil.log), l. 56 ; [`m1b-outil-amorce.log`](m1b-outil-amorce.log), l. 34).

**Comparaison `a10` contre `b5`** ([`m1b-a10-b5.sh`](m1b-a10-b5.sh), lecture seule) : `a10` vient des outils de l'amorce avec la macro de langue masquée, sous `umask 022`. `b5` vient des outils de `99790c13` sous le umask de l'hôte (0002) ; c'est la référence `05d35d64…`. Les deux ont 15 865 membres et 396 861 440 octets, selon leurs journaux. La comparaison dit si, sur le banc, les outils entiers comptent, ou seulement la macro de langue et le umask.

**Prédiction :**
- **AB1** : les sha256 des deux archives sont égaux à ceux de leurs journaux, et les archives diffèrent octet à octet. Aucun membre n'est d'un seul côté. Un seul membre commun diffère : `var/lib/dnf`, par son mode. Confiance moyenne : la base rpm (versions de rpm des deux racines d'outils) et `container=oci` (absent du banc de 20:57:14 UTC) peuvent ajouter des écarts.

### Résultat de la comparaison `a10` contre `b5`, 18/11/2026, de 21:30:16 à 21:30:19 UTC, code 0 (note écrite à 2026-11-18T21:30:46Z UTC)

Journal : [`m1b-a10-b5.log`](m1b-a10-b5.log).

**AB1 tenue.** Les deux archives ont le sha256 de leur journal et diffèrent octet à octet. Elles ont les mêmes 15 865 membres, dont 2 567 sous `usr/share/locale`. Un seul membre commun diffère : `var/lib/dnf`, par son mode.

**Lecture** : sur le banc, une fois la macro de langue masquée et à umask près, les outils de l'amorce et ceux de `99790c13` donnent le même contenu d'archive. Les deux écarts du banc de 20:57:14 UTC avec `racine.tar` (langues et mode de `var/lib/dnf`) viennent donc, sur le banc, de la macro `macros.image-language-conf` et du umask, pas du reste des outils. `container=oci` n'a rien changé au contenu. Le pod Kata n'est pas mesuré, et le point 1 A reste non établi.

### Banc du bootstrap : lecture et prédictions (note écrite à 2026-11-18T21:41:32Z UTC, après relecture du plan par le conseiller, avant le lancement)

**Objet** : le bootstrap de M1b est la base `rockylinux:9.7` (`ee90dc0e`) plus les dix lignes de `verrou_brut` (décision « Dix lignes »). Deux installations faites le même jour, hors réseau, donnent-elles la même archive bornée à S ? Script : [`m1b-boot.sh`](m1b-boot.sh).

**Lecture préalable** :
- `boot_racine` de S1 a tourné sur l'image d'essai `99790c13`, avec `dnf-3` (pas de `/usr/bin/dnf`). Elle a copié la base par `podman image mount` et `cp -a`, sans `SOURCE_DATE_EPOCH`. Elle a archivé sans borne, en ne retirant que `/w` ([`s1-boot_racine.log`](s1-boot_racine.log)).
- Les dix rpm ne sont pas en local. Le banc les télécharge depuis vault 9.7 (lecture publique), avec les métadonnées de BaseOS seules ; S1 avait quatre dépôts actifs, et sa transaction n'a tiré que de `baseos97`.
- La racine d'outils du banc est l'arbre de `a8.tar` (`06c289ad…`, outils de l'amorce, banc de 21:25:17 UTC), plus proche de l'image que la plateforme construira que `99790c13`. Ce choix est noté ici ; il n'est pas mesuré contre `99790c13`.
- La base n'est pas une racine neuve : ses journaux et son historique de dnf restent dans l'archive. Le premier passage n'exclut donc que `./m`, où dnf place son cache sous `--installroot` (archives `c1`, `c2`). Les archives `x1` et `x2` ajoutent les exclusions du banc de l'outillage. Choisir la liste d'exclusions revient à la carte.

**Prédictions :**
- **BT1** (réseau) : `repomd.xml` de BaseOS a le sha256 `fa6d5054…` de `hote97` et une signature valide de `21CB256A…`. Les métadonnées sont conformes à `repomd.xml`, et les dix rpm ont le sha256 de `hote97`. Confiance haute : vault 9.7 est figé.
- **BT2** (outils) : `a8.tar` a le sha256 `06c289ad…`. `/usr/bin/dnf` et `macros.image-language-conf` sont absents de la racine d'outils, umask 022, `%_install_langs` vaut `all`, rpm 4.16.1.3 et dnf-3 4.14.0. `rpm -K` donne 10 sur 10. Confiance moyenne pour `all` : rien n'a lu la macro dans `a8`.
- **BT3** (base) : la couche `812c4412…` a son sha256. Aucun de ses membres n'a un mtime au-delà de S, et elle n'a aucun `.wh.`. Les deux extractions rendent 0 sans erreur. `rpm -qa` donne 147 lignes, dont une `gpg-pubkey`, comme « racine avant » de S1. S vaut 1766985142. Confiance moyenne : l'extraction des xattrs dans un espace de noms d'utilisateur n'a jamais été mesurée ici.
- **BT4** (témoin) : `n1` et `n2`, extractions nues archivées, sont identiques octet à octet. Confiance haute.
- **BT5** (installations) : `dnf-3` rend 0 deux fois. Chaque transaction compte 6 installations et 4 montées. La liste `rpm -qa` (153 lignes) est égale à celle de S1, au format de S1. Confiance moyenne : le miroir n'a qu'un dépôt.
- **BT6** (témoin) : `c1` et `c1b` sont identiques octet à octet. Confiance haute.
- **BT7** : `c1` et `c2` diffèrent. Aucun membre n'est d'un seul côté. Tous les membres différents sont dans la liste d'exclusions du banc de l'outillage (journaux de dnf, `history.sqlite*`, `aux-cache`). Confiance moyenne.
- **BT8** : `x1` et `x2` sont identiques octet à octet. Confiance moyenne : c'est la première mesure d'une transaction sur une base existante.
- **BT9** (lecture, sans pari sur l'égalité) : `c1` contre `boot-racine.tar` de S1, contenu seul, xattrs compris. Écarts attendus : `rpmdb.sqlite` (S1 sans `SOURCE_DATE_EPOCH`), les journaux de dnf, `history.sqlite*` et `aux-cache`. Le banc relève aussi le nombre de membres sous `usr/share/locale` des deux côtés. Confiance faible.
- **BT10** (lecture) : `n1` contre `c1` dit ce que la transaction ajoute et change.

**Portée** : la référence ne vaut que pour le 18/11, avec ces outils et ce miroir. Le pod Kata n'est pas mesuré, et le point 1 A reste non établi. Les valeurs à retenir (`en_US`, 022, machine-id, exclusions) reviennent à la carte.

### Premier passage du banc du bootstrap, interrompu (note écrite à 2026-11-18T21:42:21Z UTC, avant le second passage)

- **Passage** : 18/11/2026, début à 21:41:38 UTC, code 1, sans ligne de fin. Journal : [`m1b-boot-1.log`](m1b-boot-1.log), dossier `~/.cache/supply-chain-poc/05/m1b-boot-20261118T214138Z`, laissé en place.
- **Ce qu'il a mesuré** : BT1 tenue (réseau). Pour BT2 : `a8.tar` au bon sha256, `/usr/bin/dnf` et la macro de langue absents, umask 0022, `%_install_langs` à `all`, rpm 4.16.1.3 et dnf-3 4.14.0. `rpm -K` n'a pas tourné.
- **Cause de l'arrêt** : un défaut du script. `rpm -q … dnf …` rend 1 parce que dnf n'est pas installé dans les outils, et `pipefail` a arrêté le script. Aucune installation n'a eu lieu.
- **Correction** : `|| true` sur cette ligne, et sur le `grep` du résumé de la transaction, qui avait le même défaut. Rien d'autre ne change dans [`m1b-boot.sh`](m1b-boot.sh), ni dans les prédictions BT1 à BT10. Le second passage écrit dans `m1b-boot.log`, avec un dossier neuf.

### Résultat du banc du bootstrap, 18/11/2026, de 21:42:26 à 21:42:48 UTC, code 0 (note écrite à 2026-11-18T21:44:13Z UTC)

Journal : [`m1b-boot.log`](m1b-boot.log). Dossier : `~/.cache/supply-chain-poc/05/m1b-boot-20261118T214226Z`, laissé en place.

**BT1 à BT8 tenues.**
- `rpm -K` donne 10 sur 10.
- La couche a 11 170 membres. Son mtime maximal est 1763921880 (23/11/2025). Aucun membre n'est au-delà de S, et la couche n'a ni `.wh.`, ni fichier spécial, ni xattr.
- S vaut 1766985142 ; il vient des `FILEMTIMES` des dix rpm.
- Les extractions nues `n1` et `n2` sont égales (`1827fa72…`).
- Chaque installation prend 3 s (761 s dans S1, cause toujours inconnue). Elle fait 6 installations et 4 montées, et sa liste `rpm -qa` est égale à celle de S1.
- `c1` et `c2` diffèrent par 8 membres, tous dans la liste d'exclusions du banc de l'outillage : les 4 journaux de dnf, `history.sqlite`, `-shm`, `-wal` et `aux-cache`.
- `c1` est égale à `c1b`.
- **`x1` est égale à `x2`** : `28634a12c5e99aae558a0cd6719d8f87fad6bac329724f0afafee252e6b78ab3`, 241 981 440 octets, 11 472 membres. C'est la référence du 18/11 pour le bootstrap, avec ces outils, ce miroir et ces exclusions.

**BT9 en partie tenue.**
- `c1` et `boot-racine.tar` ont les mêmes 11 482 membres, dont 2 608 sous `usr/share/locale` (1 239 `.mo`) des deux côtés. Les langues sont donc celles de S1.
- Les écarts prévus sont là : `rpmdb.sqlite`, les 4 journaux, `history.sqlite*` et `aux-cache`.
- **Un écart n'était pas prévu : le mode de `.`**, 0775 dans `c1` et 0555 dans `boot-racine.tar`. La couche n'a pas de membre `.` : les archives nues en ont 11 171, la couche 11 170.
  - Dans le banc, ce mode vient du `mkdir` du dossier `b1` sur l'hôte (umask 0002, `stat` à 775). `x1` et `x2` ont le même.
  - Dans S1, il vient de `cp -a "$m/." "$R/"`, depuis la racine montée par podman. L'origine de 0555 n'est pas lue.

**BT10 (lecture).** La transaction ajoute 311 membres et en change 34 : les `.pyc` de dnf (montée de version), `etc/ld.so.cache`, `rpmdb.sqlite`, `aux-cache`, l'historique et les journaux. Le journal ne montre que les 20 premiers ajouts et les 40 premiers écarts.

**Observations** :
- dnf affiche « Importing GPG key 0x350D275D » à chaque installation. La base porte pourtant déjà `gpg-pubkey-350d275d`, et la liste `rpm -qa` reste égale à celle de S1, à 153 lignes.
- Les 4 lignes comptées dans chaque journal de dnf sont des « Running scriptlet ».

**Lecture** : sur le banc, deux installations du bootstrap faites le même jour donnent la même archive. Il y faut `SOURCE_DATE_EPOCH=S`, la borne S et les exclusions du banc de l'outillage. Le mode de la racine de l'archive est une entrée de plus, à fixer ; sa valeur (0555 comme S1, ou une autre) revient à la carte. Rien n'est mesuré un autre jour, ni dans le pod Kata, ni avec les outils de `99790c13`, ni avec les quatre dépôts. Le point 1 A reste non établi.

### Corrections au résultat du banc du bootstrap (note écrite à 2026-11-18T21:46:32Z UTC, après relecture par le conseiller ; le texte d'origine reste en place)

Relevé en lecture seule : [`m1b-boot-modes.sh`](m1b-boot-modes.sh), journal [`m1b-boot-modes.log`](m1b-boot-modes.log), de 21:46:00 à 21:46:02 UTC, code 0.

1. **Valeurs citées sans journal** : le mode de `.` (0775 dans `c1` et `x1`, 0555 dans `boot-racine.tar`), l'absence de membre racine dans la couche (11 170 membres, aucun « . », « ./ » ni nom vide), `stat` de `b1` et `b2` (775) et la date du mtime maximal de la couche (2025-11-23T18:18:00Z) venaient de commandes non archivées ou d'une déduction. Elles sont désormais mesurées dans ce journal, et elles sont égales à celles de la note.
2. **« Il y faut `SOURCE_DATE_EPOCH=S`, la borne S et les exclusions »** dépasse la mesure. Le banc montre que ces conditions **suffisent** sur le banc. Il n'a aucun témoin sans `SOURCE_DATE_EPOCH` ni sans borne pour le bootstrap. Seules les 8 exclusions dont les membres diffèrent entre `c1` et `c2` sont montrées nécessaires.
3. **« Dans S1, il vient de `cp -a "$m/." "$R/"` »** est une hypothèse tirée de la lecture de `s1.sh`, pas une mesure.
4. **Exclusions** : `x1` a 10 membres de moins que `c1`. Ce sont les 8 membres qui diffèrent, plus `./etc/machine-id` et `./var/cache/dnf`, membres de la base, égaux dans `c1` et `c2`, que S1 gardait. La liste minimale mesurée a donc 8 membres ; le reste est un choix de carte. La référence `28634a12…` vaut pour la liste large du banc de l'outillage.

### Relances d'un autre jour : plan et prédictions (note écrite à 2026-11-18T21:54:22Z UTC, le 18/11, après relecture du plan par le conseiller, avant tout lancement)

**Objet.** Les quatre références du 18/11 valent pour un seul jour : `05d35d64…` (outils de `99790c13`), `06c289ad…` (outils de l'amorce), `0c00666a…` (troisième banc, 222 rpm) et `28634a12…` (bootstrap). Les relances mesurent si une sortie dépend du jour. Une entrée qui ne change qu'avec la date, et pas avec l'heure, passe inaperçue le même jour.

**Écart de méthode (outils de `99790c13`).** [`m1b-sans-machine-id.sh`](m1b-sans-machine-id.sh) fixe en dur les arbres du 18/11 (l. 12). Relancé tel quel, il ré-archiverait ces arbres sans rien mesurer d'un autre jour. Le passage ne se fait donc pas à « scripts inchangés ».
- [`m1b-outil.sh`](m1b-outil.sh) est relancé inchangé, avec un dossier neuf et sa phase réseau.
- Le script neuf [`m1b-autre-jour.sh`](m1b-autre-jour.sh) archive ensuite `i5` et `i6` du dossier neuf. Il reprend la fonction `archive` et la liste `EXCL` de `m1b-sans-machine-id.sh` (l. 20 à 28, recopie contrôlée par `diff`, identique à l'indentation près), plus `--exclude=./etc/machine-id`.
- Les trois autres bancs sont relancés inchangés. `m1b-autre-jour.sh` lit ensuite leurs archives (aucune réinstallation) et compare chaque sha256 à sa référence. Sur un écart, il compare membre à membre avec l'archive du 18/11 restée sur disque (`m1b-repro2-comparer.py`). Il relève aussi le umask du shell de lancement et le mode de `b1` et `b2`.

**Relecture des scripts (chemins en dur, dossiers neufs, journaux lus).**
- Chaque banc crée un dossier neuf horodaté, et s'arrête si ce dossier existe.
- Tous relisent des journaux commités du 18/11 ou d'avant, sans les écrire : `m1b-sources.log`, `s1-hote97.log`, `s1-boot_racine.log`, `m1b-outil.log`.
- Entrées fixées au 18/11, en lecture seule :
  - `m1b-outil-amorce.sh` lit le miroir partiel du banc de 20:57:14 UTC ;
  - `m1b-repro3.sh` lit le premier banc ;
  - `m1b-boot.sh` lit `a8.tar` du 18/11. Sa relance ne dépend pas de celle de l'outillage.
- Ont une phase réseau : `m1b-outil.sh` (vault 9.8 et l'instantané d'EPEL 9.8) et `m1b-boot.sh` (vault 9.7 BaseOS). Les deux autres bancs sont hors ligne.
- Les lignes « Usage » des scripts nomment les journaux du 18/11. **Elles ne servent pas** : chaque relance écrit dans un journal neuf (`-j2.log`), et aucun journal commité n'est écrasé.

**Lancement (à partir du 19/11).**
- Chaque commande commence par une garde : `[ "$(date -u +%F)" != 2026-11-18 ]`.
- `df` de `/home` avant chaque banc. Place libre et taille des quatre dossiers du 18/11 relevées ce soir dans [`m1b-autre-jour-disque.log`](m1b-autre-jour-disque.log) : 30G libres sur /home (95% occupé) ; 3,6G pour m1b-outil-20261118T205714Z, 4,3G pour m1b-outil-amorce-20261118T212517Z, 5,2G pour m1b-repro3-20261118T201556Z, 2,6G pour m1b-boot-20261118T214226Z. Rien n'est supprimé.
- Ordre :
  1. `m1b-outil-amorce.sh` → `m1b-outil-amorce-j2.log` ;
  2. `m1b-boot.sh` → `m1b-boot-j2.log` ;
  3. `m1b-outil.sh` → `m1b-outil-j2.log` ;
  4. `m1b-repro3.sh` → `m1b-repro3-j2.log` ;
  5. `m1b-autre-jour.sh`, avec les quatre dossiers neufs → `m1b-autre-jour.log`.
- L'intervalle réel entre deux dossiers est imprimé par le script, en minutes. Un passage à 00:05 UTC fait un autre jour à environ 2 h 30 d'écart, pas à 24 h. La note de résultat le dira.

**Banc du script, ce soir (AJ0).** `m1b-autre-jour.sh` est lancé sur les quatre dossiers du 18/11 eux-mêmes, journal [`m1b-autre-jour-banc.log`](m1b-autre-jour-banc.log). Prédiction :
- 8 « OK » : `b5` et `b6` ré-archivés égaux à `05d35d64…`, `a8`, `a9`, `a3`, `a4`, `x1` et `x2` égaux à leurs références ;
- `stat` de `b1` et `b2` à 775 des deux côtés ;
- umask 0002.
Ce banc montre seulement que le script retrouve les références sur les arbres du 18/11. Il ne mesure aucun autre jour.

**Prédictions des relances.**
- **AJ1** : la garde de date passe, et chaque banc rend le code 0.
- **AJ2** : dans `m1b-outil-j2.log`, les `repomd.xml` sont égaux aux copies du 18/11, et la signature de vault est valide. Confiance haute : vault et `archive/epel/9.8` sont des instantanés. **Si un `repomd.xml` a changé, le script s'arrête : c'est un résultat à consigner, pas un défaut à corriger.**
- **AJ3** : dans `m1b-boot-j2.log`, `repomd.xml` de vault 9.7 a le sha256 `fa6d5054…`, et les dix rpm ont les sha256 de `s1-hote97.log`. Confiance haute, même raison ; même règle en cas de changement.
- **AJ4** : `m1b-outil-j2.log` donne `S = 1793914619`. `b5` et `b6` du dossier neuf valent `05d35d64…`.
- **AJ5** : `a8` et `a9` du dossier neuf valent `06c289ad…`.
- **AJ6** : `a3` et `a4` du dossier neuf valent `0c00666a…`.
- **AJ7** : `b1` et `b2` du dossier neuf sont en 775 (umask 0002 du shell de lancement), et `x1` et `x2` valent `28634a12…`. Si le umask du shell change, le mode de la racine change. `x1` différerait alors pour une cause sans rapport avec le jour ; le relevé du `stat` le montrera.
- Confiance moyenne pour AJ4 à AJ7. Les écarts du même jour sont neutralisés par `SOURCE_DATE_EPOCH`, la borne S et les exclusions. Mais aucune mesure ne couvre une entrée qui ne change qu'avec la date.

**Portée, avant le lancement.** Même si tout tient, les relances montrent seulement ceci : sur ce banc, cet hôte, ces outils et ces sources, deux jours donnent la même archive, à l'intervalle mesuré. Elles ne disent rien du pod Kata, ni d'un autre hôte. **Le point 1 A reste non établi.** Ensuite viendra la question des valeurs de la carte : `en_US` ou toutes les langues, umask 022, machine-id vide ou absent, liste d'exclusions, mode de la racine.

### Banc du script de comparaison (AJ0), 18/11/2026, de 21:54:36 à 21:54:43 UTC, code 0 (note écrite à 2026-11-18T21:55:08Z UTC)

Journal : [`m1b-autre-jour-banc.log`](m1b-autre-jour-banc.log). Lancé sur les quatre dossiers du 18/11 eux-mêmes ; intervalle imprimé : 0 min.

**AJ0 tenue.**
- 8 « OK » sur 8, sans « ÉCART » :
  - `b5` et `b6` ré-archivés par le script valent `05d35d64…` (396 861 440 octets, 15 865 membres). La fonction `archive` recopiée redonne donc la référence ;
  - `a8`, `a9`, `a3`, `a4`, `x1` et `x2` valent leurs références.
- `b1` et `b2` sont en 775 des deux côtés. Le umask du shell de lancement est 0002.

**Portée.** Le script retrouve les références sur les arbres du 18/11. **La branche « écart »**, qui appelle `m1b-repro2-comparer.py`, **n'a pas été exercée**. Le comparateur lui-même a déjà servi dans les bancs précédents. Aucun autre jour n'est mesuré. Les ré-archives de ce banc restent dans `~/.cache/supply-chain-poc/05/m1b-autre-jour-20261118T215436Z` (environ 800 Mo d'après les tailles du journal).

### Résultat des relances d'un autre jour (AJ1 à AJ7), 19/11/2026, de 00:00:38 à 00:06:27 UTC (note écrite à 2026-11-19T00:07:51Z UTC)

Journaux : [`m1b-outil-amorce-j2.log`](m1b-outil-amorce-j2.log), [`m1b-boot-j2.log`](m1b-boot-j2.log), [`m1b-outil-j2.log`](m1b-outil-j2.log), [`m1b-repro3-j2.log`](m1b-repro3-j2.log), [`m1b-autre-jour.log`](m1b-autre-jour.log). Les quatre bancs sont relancés sans modification, dans l'ordre prévu, chacun dans un dossier neuf daté du 19/11 UTC.

**AJ1 à AJ7 tenues.**
- **AJ1** : les quatre journaux sont datés du 19/11 UTC et finissent par leur ligne « # fin » (00:02:38, 00:03:02, 00:05:04, 00:06:05 UTC) : code 0.
- **AJ2** : les trois `repomd.xml` (baseos98, appstream98, epel9) sont égaux aux copies du 18/11. La signature de vault est valide (`21CB256A…`). Les métadonnées sont conformes à `repomd.xml`.
- **AJ3** : `repomd.xml` de vault 9.7 vaut `fa6d5054…`, et les dix rpm ont les sha256 de `s1-hote97.log`. Comme le 18/11, ce banc relit vault 9.7 par le réseau.
- **AJ4** : `S = 1793914619`. `b5` et `b6` ré-archivés valent `05d35d64…` (396 861 440 octets, 15 865 membres).
- **AJ5** : `a8` et `a9` valent `06c289ad…`.
- **AJ6** : `a3` et `a4` valent `0c00666a…`. Le banc voit bien un autre jour : « jour du passage » 20776, contre 20775 le 18/11 ; S est inchangée.
- **AJ7** : umask 0002 au lancement, `b1` et `b2` en 775 comme le 18/11 ; `x1` et `x2` valent `28634a12…`.
- 8 « OK » sur 8, aucun « ÉCART ». Les lignes OK et ÉCART des quatre journaux `-j2` sont celles du 18/11, y compris les écarts attendus (`a5`/`a6` avant exclusion de machine-id, `c1`/`c2`).

**Intervalles mesurés** (imprimés par le script, entre horodatages des dossiers) : 140 min (bootstrap), 155 min (amorce), 185 min (outils de 99790c13), 229 min (troisième banc). **C'est un autre jour UTC, pas 24 h d'écart.**

**Portée.** Sur ce banc, cet hôte, ces outils et ces sources figées, deux jours UTC à 140 à 229 min d'écart donnent les mêmes quatre archives. Rien n'est mesuré dans le pod Kata ni sur un autre hôte, ni à un écart de plusieurs jours. La branche « écart » de `m1b-autre-jour.sh` n'est toujours pas exercée. **Le point 1 A reste non établi.** Viennent ensuite les valeurs de la carte : `en_US` ou toutes les langues, umask 022, machine-id vide ou absent, liste d'exclusions, mode de la racine. Les dossiers neufs restent dans `~/.cache/supply-chain-poc/05/` ; rien n'est supprimé.

### Référence du bootstrap avec la racine en 0555 : prédictions (note écrite à 2026-11-19T08:40:17Z UTC, avant le lancement)

Suite de la décision « Absent » du 19/11 ([carte](m1b-carte.md)). Le banc [`m1b-boot-0555.sh`](m1b-boot-0555.sh) tourne hors ligne et n'installe rien. Il copie par `cp -a` les arbres `b1` et `b2` du 18/11 dans un dossier neuf, puis passe la racine de chaque copie en 0555. Il archive ensuite avec la fonction, la borne `S = 1766985142` et les exclusions de `m1b-boot.sh`. Les arbres du 18/11 ne sont pas modifiés.

- **BR0** : le ré-archivage de `b1` tel quel redonne `28634a12…`.
- **BR1** : les deux `cp -a` rendent le code 0, sans ligne d'erreur ; la racine des copies vaut 555.
- **BR2** : `y1.tar` et `y2.tar` sont identiques octet à octet.
- **BR3** : la racine de `y1` vaut 0555, et `etc/machine-id` en est absent.
- **BR4** (confiance moyenne) : `y1` et `x1` ont les mêmes 11 472 noms. Le seul champ d'en-tête qui diffère est le mode de `.`. Le risque : `cp -a` dans l'espace de noms pourrait changer des xattrs ou des liens.
- **BR5** : `tar` n'écrit rien sur stderr pour `t1`, `y1` et `y2`.
- **BR6** : `b1` et `b2` restent en 775 après le banc.
- **BR7** (lecture, sans valeur pariée) : le sha256 de `y1` devient la référence du bootstrap pour les valeurs fixées le 19/11.

Ce n'est un accord pour aucune écriture dans le cluster ni dans Zot.

### Référence du bootstrap avec la racine en 0555 : résultat, 19/11/2026, de 08:40:18 à 08:40:23 UTC, code 0 (note écrite à 2026-11-19T08:41:01Z UTC)

Journal : [`m1b-boot-0555.log`](m1b-boot-0555.log).

**BR0 à BR6 tenues.**
- **BR0** : `t1` (ré-archivage de `b1` tel quel) vaut `28634a12…`.
- **BR1** : les deux `cp -a` rendent le code 0, sans ligne d'erreur ; la racine des copies vaut 555.
- **BR2** : `y1` et `y2` sont identiques octet à octet (241 981 440 octets, 11 472 membres).
- **BR3** : la racine de `y1` vaut 0555, et `etc/machine-id` en est absent.
- **BR4** : `y1` et `x1` ont les mêmes 11 472 noms. Un seul membre diffère, `.`, et seulement par son mode (0775 → 0555). Le comparateur membre à membre (contenu compris) donne le même résultat.
- **BR5** : `tar` n'a rien écrit sur stderr pour `t1`, `y1` et `y2`.
- **BR6** : `b1` et `b2` sont en 775 avant et après le banc.
- **BR7** : `f265216965e3e4723dfeb8931469cb9e57335e231ecfa4b7dc9151ba40545ee7` est la référence du bootstrap pour les valeurs fixées le 19/11 (`en_US`, umask 022, racine 0555, machine-id absent).

**Portée.** La racine en 0555 est obtenue par un `chmod` sur une copie. Dans S1, elle venait du `cp -a` de la racine de la base, mais cette origine est lue dans `s1.sh`, non mesurée. Les quatre références ont désormais la racine en 0555 et machine-id absent : `05d35d64…`, `06c289ad…`, `0c00666a…`, `f2652169…`. Rien n'est mesuré dans le pod Kata ; le point 1 A reste non établi.

### tar de l'amorce contre tar de l'hôte : prédictions (note écrite à 2026-11-19T08:47:44Z UTC, avant le lancement)

Les références ont été archivées par le `tar` de l'hôte (GNU tar 1.35). La tâche archivera avec celui de l'amorce `ed654c69`. Le banc [`m1b-tar-amorce.sh`](m1b-tar-amorce.sh) ré-archive l'arbre `i8` du 18/11 avec le `tar` de l'amorce, dans sa racine d'outils, avec les mêmes options, la même borne S et les mêmes exclusions. Il tourne hors ligne et n'installe rien.

- **TA1** : le `tar` de l'amorce rend le code 0 et n'écrit rien sur stderr.
- **TA2** (sans pari) : l'archive est-elle égale à `06c289ad…` octet pour octet ? Je ne parie pas : les deux versions de `tar` peuvent écrire les en-têtes pax autrement.
- **TA3** : même nombre de membres que `a8` (13 332). Contenu des fichiers identique, membre par membre. S'il y a des écarts, ils ne portent que sur les en-têtes.
- **TA4** (lecture) : nombre de membres de `a8` qui ont un en-tête `SCHILY.xattr.*`, et quelles clés. Ce sont les membres les plus exposés entre l'espace de noms de l'hôte et le root réel de Kata.

**Suite selon TA2.** Égale : la cible du pod est `06c289ad…` au bit près. Différente : la référence utile devient l'archive du `tar` de l'amorce.

### tar de l'amorce contre tar de l'hôte : résultat, 19/11/2026, de 08:47:46 à 08:47:49 UTC, code 0 (note écrite à 2026-11-19T08:49:18Z UTC)

Journaux : [`m1b-tar-amorce.log`](m1b-tar-amorce.log) et, pour la localisation des écarts (lecture seule, 08:48:08 à 08:48:36 UTC), [`m1b-tar-amorce-ecart.sh`](m1b-tar-amorce-ecart.sh) et [`m1b-tar-amorce-ecart.log`](m1b-tar-amorce-ecart.log). Le second script a été écrit après avoir vu l'écart.

- **TA1 tenue** : le `tar` de l'amorce (GNU tar 1.34, `tar-1.34-11.el9`) rend le code 0, sans rien sur stderr.
- **TA2 (sans pari) : différente.** L'archive du `tar` de l'amorce vaut `7c07083cd7bee149d391180633ad9cca6c82c7ad0dfa5c6bf248acad0b1ef9b7`, contre `06c289ad…`. Elle a la même taille (343 930 880 octets).
- **TA3 tenue** : 13 332 membres des deux côtés. Le comparateur ne trouve aucun membre différent : noms, types, modes, propriétaires, mtimes, tailles, cibles, en-têtes pax et contenus sont égaux.
- **Écart localisé** :
  - 227 947 octets diffèrent, dans 13 332 blocs, un par membre : 8 390 fichiers, 1 900 liens durs, 1 651 liens symboliques et 1 391 dossiers ;
  - dans chacun, seuls trois champs de l'en-tête ustar diffèrent : `devmajor` et `devminor`, vides avec 1.35 et à `0000000` avec 1.34, ainsi que la somme d'en-tête qui en découle ;
  - les données des fichiers ne sont pas touchées.
- **TA4 (lecture)** : deux membres de `a8` ont un en-tête `SCHILY.xattr.security.capability`, aucun autre xattr.

**Conséquence.** Les octets de l'archive, et donc la couche de l'image, dépendent de la version de `tar`. La cible du pod et de la tâche, qui archivent avec le `tar` de l'amorce, est `7c07083c…`, pas `06c289ad…`. Le contenu est le même. La référence du bootstrap `f2652169…` a aussi été écrite par le `tar` de l'hôte : elle est à refaire avec le `tar` de l'image qui l'archivera. La cause côté code de `tar` n'est pas lue.

### Pod d'essai Kata hors ligne (m1b.sh) : prédictions (note écrite à 2026-11-19T08:58:50Z UTC, avant tout lancement)

Le script est [`m1b.sh`](../m1b.sh), préparé à sec. Créer les deux pods est une écriture dans le cluster, prévue au point 4 de la carte. Elle est lancée sous l'accord permanent du 18/11 (« Ne me demande plus oui ou non. Sur ce genre de réponse estime que je vais répondre oui »). Rien d'autre ne change : ni politique ni label neufs (le label `construire-rpm` est déjà coupé par `construction-rpm-sans-sortie`), rien dans Zot, ni tâche ni signature. Si l'admission à blanc refuse les pods, ou s'ils demandent un changement, le passage s'arrête et je te le signale. Il crée deux pods d'essai, une installation chacun, sur l'image de l'amorce `ed654c69`. Les entrées (clés, miroir partiel, `dnf.conf`) sont celles du banc de l'amorce du 18/11. Elles sont livrées par copie, pas par une tâche de prefetch.

**prealables** (hôte, lecture et création à blanc)
- **PP1** : `a8.tar`, `dnf.conf` et S (`1793914619`) sont égaux à ceux du banc. Les 199 rpm de la liste épinglée sont présents dans le miroir, au bon sha256.
- **PP2** : `construction-rpm-sans-sortie` est relue, et aucune politique de builds n'autorise de trafic à `construire-rpm`.
- **PP3** (confiance moyenne) : les deux pods sont admis à blanc côté serveur. L'image vient d'`amont/`, ce que les pods au label `construire-rpm` n'ont pas encore utilisé.

**banc** (hôte seul, hors ligne, avant tout pod)
- **PB1** : les deux sondes des pods tournent telles quelles, avec les mêmes `sed`, dans une racine de l'amorce extraite à neuf. Tous les outils sont présents (`dnf`, `rpm`, `tar`, `sha256sum`, `find`, `bash`, `timeout`, ainsi que `getent`, `awk` et `df`). Les entrées sont revérifiées (code 0). La S recalculée vaut `1793914619`.
- **PB2** : dnf rend le code 0. 201 paquets sont installés, dont 2 `gpg-pubkey`. La racine de l'arbre est en 555. `tar` rend le code 0. L'archive a 13 332 membres.
- **PB3** : l'archive du banc vaut `7c07083c…` octet pour octet. `env -i`, le lien `/m` et les substitutions ne changent donc rien.
  - Si PB3 est tenue, seul Kata reste en cause pour PK6.
  - Si elle ne l'est pas, je corrige sur l'hôte, sans aller au cluster.
- **Témoins réseau du banc** : relevés, sans pari. Le banc tourne sous `unshare -n`.
- **Place** : environ 1,5 G sur /home pour le banc et environ 0,9 G sous le dossier de travail pour les pods. `df` est relevé avant et après ; rien n'est nettoyé.

**pod_a et pod_b** (cluster ; `pod_a` d'abord, son journal est lu avant de lancer `pod_b`)
- **PK1** : le pod est prêt sous `kata`, au label `construire-rpm`. Les entrées sont copiées par morceaux, puis revérifiées dans le pod (code 0).
- **PK2** : `%_install_langs` vaut `en_US`. Les versions sont celles du banc : `rpm-4.16.1.3-40.el9`, `dnf-4.14.0-34.el9_8.rocky.0.1`, `libsolv-0.7.24-4.el9`, `libdnf-0.69.0-18.el9.rocky.0.1`, `tar-1.34-11.el9`. La S recalculée dans le pod vaut `1793914619`.
- **PK3** : les témoins réseau échouent, en TCP vers Zot comme en DNS public (codes non nuls).
- **PK4** (lecture, sans pari) : le umask par défaut du conteneur, jamais relevé. dnf tourne sous `umask 022` posé explicitement.
- **PK5** :
  - dnf rend le code 0 ;
  - 201 paquets sont installés, dont 2 `gpg-pubkey` ;
  - la racine de l'arbre est en 555 ;
  - `tar` rend le code 0, sans rien sur stderr ;
  - l'archive a 13 332 membres.
- **PK6** (confiance moyenne) : l'archive de chaque pod vaut `7c07083c…` octet pour octet. Ce qui change par rapport au banc :
  - un vrai root dans une VM Kata, et non un espace de noms ;
  - `env -i` au lieu de l'environnement de l'hôte ;
  - un tmpfs ;
  - un autre noyau.
- **Durée** : sans pari. L'étape `racine` de S1 avait duré 5 694 s, pour une cause inconnue. Les pods tournent en arrière-plan.

**comparer** (hôte)
- **PC1** : `p-a.tar` et `p-b.tar` sont identiques.
- **PC2** : si PK6 n'est pas tenue, le comparateur membre à membre contre `a8` nomme chaque écart. Aucun pari sur leur nature.

**Portée prévue.** Si PK6 et PC1 sont tenues, la mesure couvre deux pods Kata du cluster, le même jour. Les entrées y sont livrées par copie, et seule l'archive de la racine est faite : pas de couche de configuration, pas de layout. Rien ne sera établi pour le bootstrap, ni pour un autre jour, ni pour la tâche elle-même.

### Constat pendant pod_a : lenteur de dnf dans le pod (note écrite à 2026-11-19T09:30:37Z UTC, pendant le passage, demande du propriétaire)

Journaux :
- [`m1b-pod-observation.log`](m1b-pod-observation.log), relevé en lecture seule à partir de 09:27:08 UTC ([script](m1b-pod-observation.sh)). Le premier passage, [`-1`](m1b-pod-observation-1.log), avait pris un fils de dnf pour le processus principal : défaut du script, corrigé.
- [`m1b-rpm-cloexec.log`](m1b-rpm-cloexec.log), lecture publique du source amont de rpm 4.16.1.3 ([script](m1b-rpm-cloexec.sh)).

- **Mesure** :
  - dnf avance dans le pod (118 « Installing » à 09:27, contre 23 s pour toute l'installation sur l'hôte), mais lentement ;
  - pendant le scriptlet de `ca-certificates`, un fils du processus dnf reste plus de 133 s à environ un vCPU (utime 6 058 et stime 7 246 tops à 133 s), avec l'exécutable `python3.9` : il n'a pas encore fait son `exec` ;
  - la limite de fichiers ouverts vaut 1 073 741 824 dans le pod, contre 524 288 sur l'hôte.
- **Lecture du source amont** : avant l'`exec` d'un scriptlet, `doScriptExec` appelle `rpmSetCloseOnExec()`. Quand `/proc/self/fd` ne s'ouvre pas, cette fonction appelle `fcntl` sur chaque descripteur, jusqu'à la limite dure `RLIMIT_NOFILE`.
- **Hypothèse, non mesurée** :
  - dans le fils du scriptlet, la racine visible serait celle de l'installation, sans `/proc` monté ; ce serait alors environ 10⁹ appels par scriptlet dans le pod, contre 5·10⁵ sur l'hôte ;
  - trois points ne sont pas lus : le passage dans la racine avant le scriptlet (chroot), les correctifs de Rocky sur `rpm-4.16.1.3-40.el9`, et le lien avec les 5 694 s de l'étape `racine` de S1.
- **Ce qui la trancherait** : un essai à part, avec une limite dure basse (`ulimit -Hn`) ou `/proc` monté dans la racine. Les fichiers installés ne devraient pas en dépendre ; c'est à mesurer.
- **Rien n'est changé** dans `pod_a`, qui continue. `pod_b` gardera le même script, pour que PC1 compare deux passages identiques.

### Vérification de l'explication sur l'hôte : prédictions (note écrite à 2026-11-19T09:34:17Z UTC, avant le lancement)

Le propriétaire a demandé, le 19/11 : « il faut vérifier ton explication ». Le banc [`m1b-cloexec-banc.sh`](m1b-cloexec-banc.sh) tourne sur l'hôte, hors ligne, sans rien installer. Il reprend la racine de l'amorce, les entrées de `prealables` et l'installation de `SONDE_INSTALL`. Il fait quatre installations : A tracée sur les `openat` de `/proc/self/fd`, B tracée sur le nombre de `fcntl`, C et D sans trace, avec la limite dure de l'hôte (524 288) puis avec 1 024.

- **CX1** : dans A, au moins une ouverture de `/proc/self/fd` échoue avec `ENOENT`. Le reste des résultats est relevé, sans pari.
- **CX2** : dans B, le nombre de `fcntl` divisé par 524 285 est proche, à 5 % près, du nombre d'ouvertures en `ENOENT` de A. Cela montrerait une boucle complète par ouverture ratée.
- **CX3** : D est plus court que C.
- **CX4** : les archives de C et de D valent toutes deux `7c07083c…`. Le contenu installé ne dépendrait donc pas de la limite.
- **CX5** : dnf rend le code 0 dans les quatre installations.

**Portée prévue.** Le mécanisme serait montré sur l'hôte, avec une limite de 524 288. Dans le pod, la limite de 2³⁰ est mesurée, mais le nombre d'appels n'y est pas compté : ce banc ne le mesure pas. Un pod d'essai à limite basse le mesurerait.

### Vérification de l'explication sur l'hôte : résultat, 19/11/2026, de 09:54:30 à 09:59:18 UTC, code 0 (note écrite à 2026-11-19T10:00:21Z UTC)

Journaux : [`m1b-cloexec-banc.log`](m1b-cloexec-banc.log), [`m1b-cloexec-comparaison.log`](m1b-cloexec-comparaison.log) (archives comparées après coup, membre à membre) et, pour le premier passage, [`m1b-cloexec-banc-1.log`](m1b-cloexec-banc-1.log). Ce premier passage a été arrêté : `strace -f` attendait les `gpg-agent` lancés par dnf.

- **CX5 tenue** : dnf rend le code 0 dans les quatre installations, avec 29 lignes « Running scriptlet » chacune.
- **CX1 tenue** : sur 249 ouvertures de `/proc/self/fd`, 30 échouent avec `ENOENT` et 219 réussissent.
- **CX2 tenue** : B compte 15 798 388 appels `fcntl`, dont 15 728 033 en erreur. Or 30 boucles complètes jusqu'à 524 288 feraient 30 × 524 285 = 15 728 550 appels : l'écart de 517 vient des descripteurs réellement ouverts, qui ne sont pas en erreur. Il y a donc **une boucle complète jusqu'à la limite dure par ouverture ratée**, avec le rpm de l'amorce lui-même (correctifs de Rocky compris).
- **CX3 non mesurée** : `ulimit -Hn 1024` a été refusé (`Invalid argument`), car la limite souple, encore à 524 288, dépassait la nouvelle limite dure. D a donc tourné avec la même limite que C : défaut du script.
- **CX4 non tenue** : C et D ne valent pas `7c07083c…`. Le seul membre qui diffère est `var/lib/rpm/rpmdb.sqlite-shm`, entre le banc des sondes et C (taille et contenu) comme entre C et D (contenu). Ce banc ajoutait `--setopt=keepcache=0`, absent de `SONDE_INSTALL`. Le lien entre cette option et l'écart n'est pas mesuré. Le fichier `-shm` est la mémoire partagée de SQLite.

**Lecture.** Le mécanisme est montré sur l'hôte : avant chaque scriptlet, l'ouverture de `/proc/self/fd` échoue, et rpm parcourt alors tous les descripteurs jusqu'à la limite dure. La limite du pod vaut 2³⁰ (mesurée), soit environ 2 048 fois plus d'appels par scriptlet. **Ce qui n'est pas mesuré** : le nombre d'appels et la durée dans le pod. Les mesurer demande un passage dans Kata avec une limite basse, en abaissant d'abord la limite souple. Le fichier `rpmdb.sqlite-shm` devient aussi un candidat à l'exclusion. Ce n'est pas décidé.

### pod_c, limite basse dans Kata : prédictions (note écrite à 2026-11-19T10:01:51Z UTC, avant le lancement)

Décision du propriétaire : « Oui, après pod A », en réponse à « Je prépare un pod d'essai Kata à limite basse pour mesurer la durée ? ».

- **Changement de `m1b.sh`** :
  - nouvelle étape `pod_c`, soit `pod_essai c 1024` ;
  - pour ce seul pod, deux lignes sont insérées après `umask 022` : `ulimit -Sn 1024 && ulimit -Hn 1024`, la limite souple d'abord, puis un relevé de la limite ;
  - `pod_a` et `pod_b` reçoivent `SONDE_INSTALL` telle quelle.
- **Application différée** : le changement n'est appliqué qu'après la fin de `pod_a`, parce que bash relit le script en cours d'exécution. La version prête a le sha256 `a9361f70ed0f4f21…` ; son rendu de la sonde a été essayé hors du cluster.
- **Ordre** : `pod_c` d'abord, puis `pod_b` à l'identique de `pod_a`. Le pod est créé dans le cluster sous l'accord permanent du 18/11 : ni politique, ni label neufs, rien dans Zot.

- **PL1** : la limite relevée avant dnf vaut `1024 / 1024`.
- **PL2** : dnf rend le code 0 en moins de 300 s, contre la durée de `pod_a`, qui reste à relever.
- **PL3** (confiance moyenne) : l'archive vaut `7c07083c…`. Si elle diffère, le pari est que seul `var/lib/rpm/rpmdb.sqlite-shm` diffère, comme dans le banc de l'hôte.
- **PL4** : même nombre de paquets (201) et racine en 555, comme `pod_a`.

**Portée prévue.** Si PL1 et PL2 tiennent, la lenteur de dnf dans Kata vient de la limite de fichiers ouverts. La durée de S1 n'est pas remesurée.

### pod_a : résultat, 19/11/2026, de 08:59:58 à 10:38:10 UTC, code 0 (note écrite à 2026-11-19T10:39:07Z UTC)

Journal : [`m1b-pod_a.log`](m1b-pod_a.log). Le premier lancement de `pod_c`, refusé sans créer de pod, est gardé dans [`m1b-pod_c-1.log`](m1b-pod_c-1.log) : l'étape n'était pas encore dans `m1b.sh`.

**PK1 à PK6 tenues.**
- **PK1** : `m1b-a` est prêt sur `sc-build`, sous `kata`, au label `construire-rpm`. `entrees.tar` est copié en 4 morceaux puis revérifié dans le pod : 225 fichiers, code 0.
- **PK2** : `%_install_langs` vaut `en_US`. Les versions sont celles du banc (`rpm-4.16.1.3-40.el9`, `dnf-4.14.0-34.el9_8.rocky.0.1`, `libsolv-0.7.24-4.el9`, `libdnf-0.69.0-18.el9.rocky.0.1`, `tar-1.34-11.el9`), et la S recalculée vaut `1793914619`.
- **PK3** : les témoins TCP vers Zot et DNS public rendent le code 124, c'est-à-dire un délai dépassé.
- **PK4** (lecture) : le umask par défaut du conteneur vaut 0022. L'invité a 3 vCPU, noyau 6.18.56.
- **PK5** :
  - dnf rend le code 0 ;
  - 201 paquets sont installés, dont 2 `gpg-pubkey` ;
  - la racine est en 555, et `etc/machine-id` (33 octets) est exclu de l'archive ;
  - `tar` rend le code 0 sans rien sur stderr, et l'archive a 13 332 membres.
- **PK6 tenue** : l'archive faite dans le pod vaut `7c07083c…` octet pour octet, et elle est rapatriée au même sha256.
- **Durée** : dnf a pris 5 811 s, de 09:00:44 à 10:37:35 UTC, contre 23 s sur l'hôte. La cause est étudiée à part : [constat](#constat-pendant-pod_a--lenteur-de-dnf-dans-le-pod-note-écrite-à-2026-11-19t093037z-utc-pendant-le-passage-demande-du-propriétaire) et vérification sur l'hôte.

**Portée.** Dans un pod Kata du cluster, hors réseau, l'installation de l'outillage par le dnf de l'amorce redonne l'archive de l'hôte au bit près. C'est un seul pod, un seul jour. Les entrées sont livrées par copie, et seule la racine est archivée : pas de couche de configuration, pas de layout. PC1, la comparaison avec `pod_b`, reste à faire.

### pod_c : résultat, 19/11/2026, de 10:38:43 à 10:40:47 UTC, code 0 (note écrite à 2026-11-19T10:41:11Z UTC)

Journal : [`m1b-pod_c.log`](m1b-pod_c.log).

**PL1 à PL4 tenues.**
- **PL1** : la limite relevée avant dnf vaut `1024 / 1024`.
- **PL2** : dnf rend le code 0 en 40 s, contre 5 811 s pour `pod_a`, sur le même nœud, avec la même image, les mêmes entrées et la même sonde, à la limite près.
- **PL3** : l'archive vaut `7c07083c…` octet pour octet, comme celle de `pod_a`. Le fichier `rpmdb.sqlite-shm` n'a pas varié ici.
- **PL4** : 201 paquets sont installés, dont 2 `gpg-pubkey`, et la racine est en 555.

**Lecture.**
- **Cause de la lenteur** : avec la seule limite de fichiers ouverts abaissée, dnf passe de 5 811 s à 40 s dans Kata. Avec le banc de l'hôte (une boucle de `fcntl` jusqu'à la limite dure par scriptlet, faute de `/proc/self/fd`), c'est la cause de la lenteur de dnf dans le pod.
- **Contenu** : il ne dépend pas de cette limite. Deux pods Kata, l'un à la limite par défaut (2³⁰), l'autre à 1 024, donnent la même archive.
- **Ce qui n'est pas mesuré** : la même cause pour les 5 694 s de l'étape `racine` de S1 et les 761 s de `boot_racine`. C'est probable, mais ces durées n'ont pas été remesurées.
- **Pour la tâche à venir** : abaisser la limite de fichiers ouverts (souple, puis dure) avant dnf. C'est une proposition, pas une décision.

### pod_d, /proc monté dans la racine installée : prédictions (note écrite à 2026-11-19T10:51:48Z UTC, avant le lancement)

Décision du propriétaire : « Mesurer aussi /proc ».

- **Changement de `m1b.sh`** :
  - nouvelle étape `pod_d`, soit `pod_essai d - proc` ;
  - pour ce seul pod, la limite de fichiers ouverts reste celle par défaut ;
  - avant dnf, la sonde crée `/w/m/i/proc` et y monte `proc` ;
  - juste après dnf, avant `tar`, elle démonte `/proc` et relève les montages restants ;
  - `pod_a`, `pod_b` et `pod_c` ne changent pas.
- **Application différée** : comme pour `pod_c`, le changement n'est appliqué qu'après la fin de `pod_b`, que bash relit en cours d'exécution. La version prête a le sha256 `349dca4939052a65…` ; son rendu de la sonde a été essayé hors du cluster.

- **PD1** : `/proc` est monté dans la racine avant dnf, avec 1 montage.
- **PD2** (sans pari) : le code de dnf. Le paquet `filesystem` livre `/proc`, avec son mode, alors que le dossier est déjà un point de montage. Que rpm l'accepte n'est pas lu.
- **PD3** : si dnf rend 0, il dure moins de 300 s : rpm ouvre alors `/proc/self/fd` et ne boucle plus jusqu'à la limite.
- **PD4** : `/proc` est démonté après dnf (0 montage restant). La racine est en 555.
- **PD5** (sans pari) : l'archive vaut-elle `7c07083c…` ? Les scriptlets voient un `/proc` réel, ce qui peut changer des fichiers. Si elle diffère, le comparateur membre à membre contre `a8` nomme chaque écart. Elle est toujours rapatriée (344 Mo ; il reste environ 3,8 G sur /home).

**Ce qui départagera.** Si PD2, PD3 et PD5 sont tenues (code 0, rapide, même archive), les deux remèdes se valent pour cette installation, et le choix redevient une question de simplicité. Si l'archive diffère, garder `/proc` demanderait de refaire les références.

### pod_b et comparer : résultat, 19/11/2026 (note écrite à 2026-11-19T12:19:05Z UTC)

Journaux : [`m1b-pod_b.log`](m1b-pod_b.log) (de 10:41:12 à 12:17:56 UTC, code 0) et [`m1b-comparer.log`](m1b-comparer.log) (de 12:18:38 à 12:18:42 UTC, code 0). `pod_b` a tourné avec le même script que `pod_a` ; le changement pour `pod_d` n'a été appliqué qu'après sa fin.

**PK1 à PK6 tenues pour `pod_b`, PC1 tenue, PC2 sans objet.**
- **PK1** : pod prêt sous `kata`, au label `construire-rpm`, sur le nœud `sc-build`. Les entrées sont copiées en 4 morceaux et revérifiées dans le pod (code 0, 225 fichiers).
- **PK2** : `%_install_langs` vaut `en_US`, les versions sont celles du banc, et la S recalculée vaut `1793914619`.
- **PK3** : les deux témoins réseau échouent (code 124 en TCP vers Zot comme en DNS public).
- **PK4** (lecture) : umask du conteneur `0022`, comme dans `pod_a`.
- **PK5** : dnf rend 0 ; 201 paquets sont installés, dont 2 `gpg-pubkey` ; la racine est en 555 ; `tar` rend 0, sans rien sur stderr ; 13 332 membres.
- **PK6** : l'archive vaut `7c07083c…` octet pour octet.
- **PC1** : `p-a.tar` et `p-b.tar` sont identiques, et chacune égale la cible. Le comparateur membre à membre contre `a8` ne trouve aucun écart.
- **Durée** (lecture) : dnf met 5 724 s, contre 5 811 s dans `pod_a`, à la même limite par défaut.

**Portée.** Trois pods Kata (`pod_a`, `pod_b`, `pod_c`), du même nœud et du même jour, donnent l'archive `7c07083c…` de l'outillage. C'est la portée annoncée dans les prédictions : rien n'est établi pour le bootstrap, ni pour un autre jour, ni pour la tâche elle-même.

### pod_d : résultat, 19/11/2026, de 12:18:28 à 12:20:29 UTC, code 0 (note écrite à 2026-11-19T12:22:27Z UTC)

Journaux :
- [`m1b-pod_d.log`](m1b-pod_d.log) : le passage ;
- [`m1b-pod_d-ecarts.log`](m1b-pod_d-ecarts.log) : les écarts membre à membre contre `a8` ([script](m1b-pod_d-ecarts.sh)) ;
- [`m1b-pod_d-journaux.log`](m1b-pod_d-journaux.log) : les journaux de dnf de `pod_a` et de `pod_d`, comparés sans horodatage ([script](m1b-pod_d-journaux.sh)) ;
- [`m1b-pod_d-tmpfiles.log`](m1b-pod_d-tmpfiles.log) : les chemins en plus, rapprochés des fichiers `tmpfiles.d` de `a8` ([script](m1b-pod_d-tmpfiles.sh)).

**PD1, PD3 et PD4 tenues ; PD2 lue : code 0 ; PD5 : l'archive diffère.**
- **PD1** : `/proc` est monté dans la racine avant dnf, avec 1 montage. Le mode du point de montage vaut 555, celui de la racine 755 (dossier créé par `mkdir -p` sous `umask 022`).
- **PD2** (lecture) : dnf rend le code 0, avec 201 paquets dont 2 `gpg-pubkey`. Le paquet `filesystem` s'installe donc sur un `/proc` déjà monté.
- **PD3** : dnf dure 40 s, comme `pod_c` sous la limite 1 024, à la limite par défaut cette fois.
- **PD4** : `/proc` est démonté après dnf, sans montage restant. La racine est en 555.
- **PD5** : l'archive vaut `fb33228f…`, avec 13 352 membres au lieu de 13 332. Contre `a8` :
  - 20 membres n'existent que dans `pod_d`, et aucun que dans `a8` ;
  - 3 membres diffèrent : `./proc` est en 755 au lieu de 555, et la mtime de `./root` et de `./var/log` vaut S (`1793914619`) au lieu de `1730597381`.
- **Les 20 membres en plus** : 19 sont déclarés, ligne pour ligne, dans les fichiers `tmpfiles.d` de l'outillage (`systemd.conf`, `legacy.conf`, `var.conf`, `provision.conf`). Le vingtième, `/run/systemd`, est le parent de dossiers déclarés. Ce sont des dossiers vides, le lien `/var/log/README`, et les fichiers `btmp`, `wtmp` et `lastlog`.
- **Journaux de dnf** : ceux de `pod_a` et de `pod_d` ne diffèrent que par les débits et les heures. Aucun ne signale d'erreur de scriptlet.

**Lecture.**
- Avec `/proc` monté, un scriptlet crée les chemins de `tmpfiles.d` ; sans `/proc`, il ne les crée pas, sans rien signaler dans le journal de dnf. Que ce soit l'appel à `systemd-tmpfiles` du paquet `systemd` est probable, mais non lu : rpm est absent de l'hôte, et les scriptlets n'ont pas été extraits.
- La mtime de `./root` et de `./var/log` suit : un membre nouveau y a été créé, et `tar` borne la mtime à S.
- `./proc` en 755 : le mode de `filesystem` s'est appliqué au `/proc` monté. Au démontage, reste le dossier de `mkdir -p`. C'est une conséquence du montage lui-même, que la sonde pourrait corriger. Non essayé.
- Les 17 520 octets de `lastlog` ne sont pas expliqués. `tmpfiles.d` déclare ce fichier vide ; un `useradd` d'un scriptlet postérieur l'aurait rempli. C'est une hypothèse, non mesurée.

**Ce qui départage.** Les deux remèdes ne se valent pas :
- **limite de fichiers ouverts à 1 024** : même vitesse (40 s), même archive `7c07083c…` que les références ;
- **`/proc` monté dans la racine** : même vitesse, mais un autre contenu. Le garder demanderait de refaire les références.
- **S1** ([`m1b-pod_d-s1.log`](m1b-pod_d-s1.log), [script](m1b-pod_d-s1.sh)) : aucun des 20 chemins n'existe dans `racine.tar` (13 341 membres, `./proc` en 555) ni dans `boot-racine.tar` (11 482 membres, `./proc` en 755, venu de l'image amont). Sur ce point, les racines de S1 ressemblent à celles faites sans `/proc`, pas à `pod_d`.

**Note datée du 19/11/2026, écrite à 2026-11-19T12:25:00Z UTC, sur la note de résultat de `pod_d`** ([`m1b-pod_d-origines.log`](m1b-pod_d-origines.log), [script](m1b-pod_d-origines.sh)) :
- **`./proc` de `boot-racine.tar`** : la note l'a dit « venu de l'image amont » sans l'avoir lu. C'est maintenant lu. La couche amont `812c4412…` de l'image rockylinux 9.7, recalculée depuis le cache OCI local, a `proc` en 755.
- **`lastlog`** : 17 520 octets valent 60 enregistrements de 292 octets, soit jusqu'à l'uid 59. Dans `etc/passwd` de `a8`, l'uid 59 est `tss`, compte du paquet `tpm2-tss`, installé en 193ᵉ position sur 199. L'hypothèse d'un `useradd` qui remplit `lastlog` une fois le fichier créé est cohérente, mais pas lue dans les scriptlets.
- **Vocabulaire** : là où la note dit « un scriptlet », il faut lire « un scriptlet ou un déclencheur de fichiers » ; ni l'un ni l'autre n'a été lu.
- **Un seul passage** : `fb33228f…` vient d'un seul `pod_d`. Sa reproductibilité n'est pas établie.

### Référence du bootstrap avec le tar de l'amorce : prédictions (note écrite à 2026-11-19T12:45:13Z UTC, avant le lancement)

La référence du bootstrap `f2652169…` a été écrite par le `tar` 1.35 de l'hôte ; la tâche archivera avec le `tar` 1.34 de l'amorce. Pour l'outillage, le même changement de `tar` a changé les octets (`06c289ad…` devenu `7c07083c…`) par les seuls champs `devmajor` et `devminor`, sans changer le contenu ([`m1b-tar-amorce-ecart.log`](m1b-tar-amorce-ecart.log)).

- **Script** : [`m1b-boot-amorce.sh`](m1b-boot-amorce.sh), sha256 `f95152655df741e3…`. Il reprend la méthode de `m1b-tar-amorce.sh` :
  - les copies `b1` et `b2` en 0555 du banc du 19/11 (`m1b-boot-0555`, 08:40:18 UTC) sont ré-archivées par le `tar` de l'amorce, dans la racine d'outils du banc de l'amorce (chroot, umask 022) ;
  - les options, la borne S (`1766985142`) et les exclusions sont celles de `m1b-boot-0555.sh` ;
  - chaque copie est montée en lecture seule sur `/mnt` (dossier vide) de la racine d'outils, dans un espace de montage à part ;
  - hors ligne, rien n'est installé. Environ 0,5 Go écrit dans un dossier neuf ; il reste 2,8 G sur /home.

- **BA1** : le `tar` de l'amorce est `tar-1.34-11.el9`. Chaque ré-archivage rend le code 0, sans rien sur stderr, avec 11 472 membres. La copie est vue en 555 sous `/mnt`, et l'écriture y est refusée.
- **BA2** (confiance moyenne) : l'archive diffère de `f2652169…`. Les en-têtes de `y1.tar` ont `devmajor` et `devminor` vides, ceux de `z-b1.tar` les ont à `0000000`.
- **BA3** : le comparateur membre à membre contre `y1.tar` ne trouve aucun écart (0 d'un seul côté, 0 différent).
- **BA4** : `z-b1.tar` et `z-b2.tar` sont identiques octet à octet.
- **BA5** : `/mnt` de la racine d'outils reste vide, et les racines des copies restent en 555.

**Conséquence prévue.** Si BA1 à BA4 sont tenues, le sha256 de `z-b1.tar` devient la cible du bootstrap pour le pod et la tâche, à la place de `f2652169…`, comme `7c07083c…` pour l'outillage. Rien n'est mesuré dans Kata ; c'est le pod d'essai du bootstrap qui suit.

### Référence du bootstrap avec le tar de l'amorce : résultat, 19/11/2026, de 12:45:18 à 12:45:23 UTC, code 0 (note écrite à 2026-11-19T12:46:03Z UTC)

Journal : [`m1b-boot-amorce.log`](m1b-boot-amorce.log).

**BA1 à BA5 tenues.**
- **BA1** : le `tar` de l'amorce est `tar-1.34-11.el9`. Les deux ré-archivages rendent le code 0, sans rien sur stderr, avec 11 472 membres. La copie est vue en 555 sous `/mnt`, et l'écriture y est refusée.
- **BA2** : l'archive diffère de `f2652169…`, par les champs `devmajor` et `devminor` :
  - `y1.tar` (tar 1.35) les a vides dans ses 11 486 en-têtes ;
  - `z-b1.tar` (tar 1.34) les a à `0000000` dans 11 472 en-têtes, et vides dans 14 autres.

  Les 14 sont sans doute des en-têtes pax étendus (11 486 − 11 472), ce qui n'est pas lu en détail.
- **BA3** : le comparateur membre à membre contre `y1.tar` ne trouve aucun écart.
- **BA4** : `z-b1.tar` et `z-b2.tar` sont identiques octet à octet, avec le sha256 `b063feb3206deb3f1c0ad4eb7b497d683693967d194c7fdd366a2b0094823348`.
- **BA5** : `/mnt` de la racine d'outils reste vide, et les racines des copies restent en 555.

**Conséquence.** La cible du bootstrap pour le pod et la tâche, qui archiveront avec le `tar` de l'amorce, est `b063feb3…`, à la place de `f2652169…`. Le contenu est le même. Comme pour l'outillage (`7c07083c…`), rien n'est encore mesuré dans Kata.

**Correction datée du 19/11/2026, écrite à 2026-11-19T12:49:53Z UTC : langue du bootstrap.**
- **Ce qui est faux** : BR7 dit le sha256 de `y1` (`f2652169…`) « référence du bootstrap pour les valeurs fixées le 19/11 ». La note de résultat de BR la dit pour « `en_US`, umask 022, racine 0555, machine-id absent ». Les deux notes de la référence avec le `tar` de l'amorce disent `b063feb3…` « cible du bootstrap pour le pod et la tâche ».
- **Ce qui est mesuré** : l'arbre de cette référence a été installé par les outils de `a8` ([`m1b-boot.log`](m1b-boot.log)). `%_install_langs` y vaut `all`, et libsolv `0.7.24-6.el9_8`. La transaction y ajoute 32 membres sous `usr/share/locale` (2 576 dans la base nue, 2 608 après).
- **Ce que donne l'amorce** : `%_install_langs` y vaut `en_US`, et libsolv `0.7.24-4.el9` ([`m1b-pod_a.log`](m1b-pod_a.log)).
- **Correction** :
  - `f2652169…` et `b063feb3…` sont des références du bootstrap pour la racine 0555, l'umask 022 et machine-id absent, mais avec les langues `all`, comme S1. Elles ne correspondent pas à la valeur `en_US` annoncée le 19/11 ;
  - `b063feb3…` n'est la cible du pod et de la tâche que si la langue du bootstrap est `all`. Ce choix revient au propriétaire.
- **Ce qui suit** : un banc de l'hôte sépare la langue des outils (amorce + `en_US`, amorce + `all` posée explicitement) avant la question.

### Langue du bootstrap, séparée des outils : prédictions (note écrite à 2026-11-19T12:51:34Z UTC, avant le lancement)

- **Script** : [`m1b-boot-langue.sh`](m1b-boot-langue.sh), sha256 `459f07c14e9db3e1…`. Banc de l'hôte, hors réseau, sans rien installer sur l'hôte. La racine d'outils de l'amorce (banc du 18/11, lecture seule) installe deux fois la base `rockylinux:9.7` et les dix lignes, avec la sonde prévue pour le pod :
  - la couche `812c4412…` est extraite par le `tar` de l'amorce, sans podman ;
  - dnf-3 tourne sous `env -i`, umask 022, `SOURCE_DATE_EPOCH`=S et `container=oci`. La limite de fichiers ouverts est mise à 1 024, souple puis dure, dans un sous-shell qui n'entoure que dnf : c'est la forme décidée, jamais mesurée telle quelle (`pod_c` la posait pour toute la sonde) ;
  - `en` : `HOME=/root`, macro de l'amorce telle quelle ; `all` : `HOME=/m/h`, dont `.rpmmacros` pose `%_install_langs all` ;
  - la racine de l'arbre passe en 0555 avant l'archive. L'archive est faite par le `tar` de l'amorce, avec les options, la borne S et les exclusions de la référence.
- **Montages** : un dossier neuf sur `/m` de la racine d'outils, dans un espace de noms à part, et le miroir du 18/11 en lecture seule sur `/m/miroir`. Le banc s'arrête, sans rien effacer, s'il reste moins de 1,5 Go ; il en reste environ 2,3.

- **LG0** : la racine d'outils a `rpm-4.16.1.3-40.el9`, `python3-dnf-4.14.0-34.el9_8.rocky.0.1`, `libsolv-0.7.24-4.el9` et `tar-1.34-11.el9`. Le miroir est en lecture seule. Sous `env -i`, rpm de python lit `[en_US]` avec `HOME=/root` et `[all]` avec `HOME=/m/h`. Confiance moyenne pour la lecture de `.rpmmacros` sous `env -i`.
- **LG1** : l'extraction par le `tar` de l'amorce rend 0, sans rien sur stderr. `rpm -qa` donne 147 lignes avant l'installation.
- **LG2** : dnf-3 rend 0 deux fois. La limite vaut `1024 / 1024` dans le sous-shell, et celle du shell reste celle de l'hôte après. Chaque transaction compte 6 installations et 4 montées. La liste `rpm -qa` après (153 lignes) est égale à celle de S1.
- **LG3** : `tar` rend 0, sans rien sur stderr, et la racine est en 555.
- **LG4** (décisive, confiance moyenne) : `z-all.tar` vaut `b063feb3…` octet pour octet. Ce qui change par rapport à la référence : libsolv `-4` au lieu de `-6`, une extraction par le `tar` 1.34 et non 1.35, `env -i`, et la limite. Si elle diffère, le comparateur membre à membre nomme chaque écart.
- **LG5** (sans pari) : `z-en.tar` contre `z-all.tar`. Le comparateur nomme les écarts ; le banc compte les membres sous `usr/share/locale`. La transaction ajoute 32 membres de locale sous `all` ; sous `en_US`, les quatre montées peuvent aussi en retirer de la base.
- **LG6** : le `/m` de la racine d'outils garde le même nombre d'entrées, et `/mnt` reste vide.

**Ce qui départagera.** Si LG4 est tenue, seule la langue distingue l'amorce des outils de `a8` pour le bootstrap. La question au propriétaire porte alors sur la langue du bootstrap : `all` comme S1, ou `en_US` comme annoncé le 19/11.

### Langue du bootstrap, séparée des outils : résultat, 19/11/2026, de 12:51:40 à 12:51:51 UTC, code 0 (note écrite à 2026-11-19T12:52:51Z UTC)

Journaux : [`m1b-boot-langue.log`](m1b-boot-langue.log) ; complément sur l'hôte : [`m1b-boot-langue-listes.log`](m1b-boot-langue-listes.log) ([script](m1b-boot-langue-listes.sh)).

**LG0, LG1, LG3, LG4 et LG6 tenues ; LG2 tenue, mesurée en partie après coup ; LG5 lue.**
- **LG0** : les outils sont ceux de l'amorce (`libsolv-0.7.24-4.el9`, `python3-dnf-4.14.0-34.el9_8.rocky.0.1`, `tar-1.34-11.el9`), et le miroir est en lecture seule. Sous `env -i`, rpm de python lit `[en_US]` avec `HOME=/root` et `[all]` avec `HOME=/m/h`. Poser la langue par `.rpmmacros` fonctionne donc sous `env -i`.
- **LG1** : l'extraction par le `tar` de l'amorce rend 0, sans rien sur stderr ; `rpm -qa` donne 147 lignes avant l'installation.
- **LG2** : dnf-3 rend 0 deux fois (2 s et 3 s), avec 6 installations et 4 montées.
  - La limite vaut `1024 / 1024` dans le sous-shell ; celle du shell reste `524288 / 524288` après : la forme « sous-shell autour de dnf seul » est mesurée.
  - **Défaut du banc** : la comparaison des listes `rpm -qa` avec S1 a échoué deux fois sur « `cmp: command not found` » (l'amorce n'a pas `cmp`). Les « ÉCART » imprimés viennent de ce défaut, pas d'un écart.
  - Faite ensuite sur l'hôte, à partir des listes laissées par le banc, la comparaison donne les deux listes égales à celle de S1 (153 lignes).
  - **Pour la sonde du pod** : ne pas compter sur `cmp` dans l'amorce.
- **LG3** : `tar` rend 0, sans rien sur stderr, et la racine passe en 555.
- **LG4** : `z-all.tar` vaut `b063feb3…` octet pour octet. libsolv `-4`, l'extraction par le `tar` 1.34, `env -i` et la limite ne changent rien. **Seule la langue distingue l'amorce des outils de `a8` pour le bootstrap.**
- **LG5** : `z-en.tar` (`4171b0d3…`, 11 385 membres) n'a que 87 membres de moins que `z-all.tar`, tous des fichiers `.mo` sous `usr/share/locale`. `var/lib/rpm/rpmdb.sqlite` diffère aussi. Le détail :
  - **32 `dnf-plugins-core.mo`** : les traductions d'un paquet nouveau, que `en_US` n'installe pas ;
  - **55 `dnf.mo`** : des fichiers que la base nue avait, et que `z-en` n'a plus. Sous `en_US`, la montée de version qui les livre ne les réinstalle pas. `z-all` les garde tous.
- **LG6** : le `/m` de la racine d'outils garde 14 entrées, et `/mnt` reste vide.

**Lecture.**
- Avec `all` posée explicitement, l'amorce redonne le bootstrap de référence, celui que mock a utilisé de M2 à M4c, déjà retrouvé un autre jour UTC (`28634a12…`, de même contenu à la racine et au `tar` près).
- Avec `en_US`, le bootstrap perd 55 traductions que la base `rockylinux:9.7` publiée contient. Ce n'est plus « la base, plus les dix lignes ».
- **Place** : il reste 1 353 808 kB sous `$HOME` après le banc.

**Correction datée du 19/11/2026, écrite à 2026-11-19T12:55:19Z UTC, sur la note de résultat de la langue du bootstrap :**
- **« Le bootstrap de référence, celui que mock a utilisé de M2 à M4c »** : c'est trop fort. `b063feb3…` exclut `etc/machine-id`, `var/cache/dnf` et les journaux de dnf, que `boot-racine.tar` de S1 avait, et sa racine et son `tar` diffèrent. Ce qui est mesuré : les mêmes langues que `boot-racine.tar` (2 608 membres sous `usr/share/locale`, dont 1 239 `.mo`, [`m1b-boot.log`](m1b-boot.log)) et la même liste `rpm -qa` (153 lignes). Il faut lire « sur les langues et la liste de paquets ».
- **« Ce n'est plus la base, plus les dix lignes »** : c'est faux au niveau des paquets, où les deux variantes donnent la liste de S1 (décision « Dix lignes » tenue). L'écart est au niveau des fichiers : 55 `dnf.mo` de la base n'y sont plus. Le mécanisme n'est pas lu.
- **Un seul passage** : `4171b0d3…` vient d'un seul passage ; sa reproductibilité n'est pas établie.

### pod_e, bootstrap dans Kata : prédictions (note écrite à 2026-11-19T13:01:46Z UTC, avant le lancement)

Décision du propriétaire : « all, comme S1 ».

- **Changement de `m1b.sh`** : deux étapes neuves, `prealables_boot` et `pod_e`. Les étapes existantes ne changent pas. La version prête a le sha256 `373ae33436d298e3…`. Sa syntaxe et celle des deux sondes rendues sont vérifiées ; shellcheck ne signale rien.
  - **`prealables_boot`** (hôte et lecture) : il relit `dnf97.conf`, la couche `812c4412…`, `repomd.xml` et les métadonnées de BaseOS 9.7, ainsi que les dix rpm, contre le banc du 18/11 et `s1-hote97.log`. Il fait l'archive de transfert : couche, miroir, clés, `dnf97.conf`, `h/.rpmmacros` (`%_install_langs all`) et `aucun/`. Il relit les politiques, puis admet le pod `m1b-e` à blanc.
  - **`pod_e`** (cluster) : il crée le pod Kata au label `construire-rpm`, sur l'image de l'amorce, avec les ressources et le contexte du pas `construire`. Il copie les entrées par morceaux et relève les témoins.
  - **La sonde du pod** est celle du banc de la langue, avec les mêmes noms de chemins sous `/m` (lien vers `/w/m`). La liste `rpm -qa` est comparée sur l'hôte par sha256, faute de `cmp` dans l'amorce. L'archive est rapatriée, puis le pod est supprimé.
- **Écart avec le banc de la langue** : la sonde n'a pas été rejouée telle quelle sur l'hôte avant le pod. Le banc des sondes de l'outillage l'avait fait. Il reste 1,35 G sur /home : un tel banc, puis le pod, n'y tiendraient pas ensemble. Les commandes sont celles du banc de la langue ; seuls changent les chemins de `/w` et l'affichage de la liste.
- **Place** : environ 115 Mo d'entrées et 242 Mo d'archive rapatriée, dans `$T`.

- **PE1** : `prealables_boot` rend 0. Tous les sha256 sont conformes, avec 10 rpm sur 10, et le pod est admis à blanc.
- **PE2** : le pod est prêt sous `kata`, au label `construire-rpm`. Les entrées sont revérifiées dans le pod (code 0).
- **PE3** :
  - les témoins réseau échouent (codes non nuls) ;
  - sous `env -i`, rpm de python lit `[en_US]` avec `HOME=/root` et `[all]` avec `HOME=/m/h` ;
  - les versions sont celles de LG0.
- **PE4** :
  - l'extraction de la couche rend 0, sans rien sur stderr, et `rpm -qa` donne 147 lignes avant ;
  - la limite vaut `1024 / 1024` dans le sous-shell. Celle du shell reste celle du pod après (2³⁰ attendu, `1073741824`) ;
  - dnf-3 rend 0 en moins de 60 s, avec 6 installations et 4 montées. La boucle de rpm est bornée par la limite, et la durée n'est pas mesurée dans Kata pour le bootstrap.
- **PE5** : la liste `rpm -qa` après est celle de S1 (sha256 égal), la racine passe en 555, et `tar` rend 0, sans rien sur stderr.
- **PE6** (confiance moyenne) : l'archive vaut `b063feb3…` octet pour octet. Ce qui change par rapport au banc de la langue :
  - un vrai root dans une VM Kata, et non un espace de noms ;
  - un tmpfs ;
  - un autre noyau ;
  - une extraction de la couche dans Kata.

  Si elle diffère, le comparateur membre à membre contre `z-b1.tar` nomme chaque écart.

**Portée prévue.** Si PE6 est tenue, le bootstrap est reproduit dans un pod Kata hors réseau, le même jour, entrées livrées par copie, racine seule. Rien n'est établi pour un autre jour, ni pour la tâche elle-même. Le point 1 A reste non établi.

### pod_e, bootstrap dans Kata : résultat, 19/11/2026 (note écrite à 2026-11-19T13:03:47Z UTC)

Journaux : [`m1b-prealables_boot.log`](m1b-prealables_boot.log) (13:01:55 à 13:01:56 UTC, code 0) et [`m1b-pod_e.log`](m1b-pod_e.log) (13:02:04 à 13:03:08 UTC, code 0).

**PE1 à PE6 tenues.**
- **PE1** : les entrées sont conformes, avec 6 fichiers de métadonnées et 10 rpm sur 10, et le pod `m1b-e` est admis à blanc.
- **PE2** : le pod est prêt sous `kata`, au label `construire-rpm`, sur le nœud `sc-build`. Les 22 fichiers d'entrée sont revérifiés dans le pod (code 0).
- **PE3** :
  - les deux témoins réseau échouent (code 124) ;
  - sous `env -i`, rpm de python lit `[en_US]` avec `HOME=/root` et `[all]` avec `HOME=/m/h` ;
  - les versions sont celles de LG0.
- **PE4** :
  - l'extraction de la couche rend 0, sans rien sur stderr, et `rpm -qa` donne 147 lignes avant ;
  - la limite vaut `1024 / 1024` dans le sous-shell, et celle du shell reste `1073741824` après ;
  - dnf-3 rend 0 en 5 s, avec 6 installations et 4 montées.
- **PE5** : la liste `rpm -qa` après est celle de S1 (sha256 `1ca7c54b…`, 153 lignes), la racine passe en 555, et `tar` rend 0 sans rien sur stderr.
- **PE6** : l'archive vaut `b063feb3…` octet pour octet.

**Portée.** Le bootstrap est reproduit au bit près dans un pod Kata hors réseau : même jour, même nœud, entrées livrées par copie, racine seule. Ni couche de configuration, ni layout. Avec l'outillage (`pod_a` à `pod_c`), les deux racines de M1b sont reproduites dans Kata, avec les valeurs décidées : langue posée par la tâche, limite autour de dnf seul, racine 0555, machine-id absent. Rien n'est établi pour un autre jour dans Kata, ni pour la tâche elle-même : le point 1 A reste non établi au sens de la carte.

**Place** : `/home` avait 77 684 756 kB libres à 13:01:56 UTC, contre 1 353 808 kB à 12:51:51 UTC ([`m1b-boot-langue.log`](m1b-boot-langue.log)). La brique n'a rien effacé entre les deux relevés ; l'origine de la place libérée n'est pas relevée.

### Outils de l'amorce, relevé (note écrite à 2026-11-19T13:23:32Z UTC)

Journal : [`m1b-amorce-outils.log`](m1b-amorce-outils.log) (13:21:40 à 13:21:42 UTC, code 0), lecture hors ligne de la couche `99c753a8…` de l'amorce `ed654c69…`, sans prédictions : c'est un relevé, pas une mesure de comportement.

- **Présents** : `curl`, `gpgv`, `gpg`, `sha256sum`, `python3` (avec `ssl` et `urllib`), `tar`, `gzip`, `timeout`, `getent`, `rpm`, `dnf-3`, `bash`, `find`, `stat`.
- **Absents** : `skopeo`, `createrepo_c`, `cmp`, `jq`, `xz`, `wget`.
- **Clés** : la clé de Rocky de l'amorce (`etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9`, 1 750 octets) est celle des bancs de l'outillage et du bootstrap, octet pour octet. Aucun membre ne cite EPEL : la clé d'EPEL (1 656 octets, sha256 `fcf0eab4…`, empreinte `FF8AD134…`) devra entrer par une autre voie.

### Banc de l'outillage sous la forme de la tâche : prédictions (note écrite à 2026-11-19T13:23:32Z UTC, avant le lancement)

**Objet.** La cible `7c07083c…` et les pods `pod_a` à `pod_c` ont été installés par `/usr/bin/dnf` avec `HOME=/root` : la langue `en_US` venait alors de la macro de l'amorce. Pour `pod_c`, la limite entourait toute la sonde. La tâche poserait la forme du bootstrap (`pod_e`) : `dnf-3`, la limite dans un sous-shell qui n'entoure que dnf, `HOME=/m/h` avec `.rpmmacros` à `%_install_langs en_US`, et la racine en 0555. Cette forme n'a jamais tourné pour l'outillage. [`m1b-outil-forme.sh`](m1b-outil-forme.sh) (sha256 `82919aa8a5eed26c…`) la joue une fois sur l'hôte, hors réseau, dans la racine d'outils de l'amorce du banc du 18/11, sur son miroir, en lecture seule.

- **OF0** : les versions sont celles de LG0. Le miroir est en lecture seule, avec 199 rpm. rpm de python lit `[en_US]` avec `HOME=/root` comme avec `HOME=/m/h`.
- **OF1** : la limite vaut `1024 / 1024` dans le sous-shell. Celle du shell est inchangée après.
- **OF2** : dnf-3 rend 0 en moins de 120 s. 201 paquets sont installés, dont 2 `gpg-pubkey`, comme `pod_c`.
- **OF3** : la racine vaut déjà 555 avant le `chmod` (`pod_c`). `etc/machine-id` existe (33 octets), mais l'archive l'exclut. `tar` rend 0, sans rien sur stderr.
- **OF4** (confiance moyenne) : `f.tar` vaut `7c07083c…` octet pour octet. Les écarts avec la cible sont nommés ici :
  - `dnf-3` au lieu de `/usr/bin/dnf`, qui est un lien vers `dnf-3` dans l'amorce ;
  - la langue lue dans `.rpmmacros` plutôt que dans la macro de l'image, à valeur égale ;
  - la limite autour de dnf seul.

  Si `f.tar` diffère, le comparateur membre à membre contre `a8-amorce.tar` nomme chaque écart.

**Portée prévue.** Si OF4 est tenue, la forme de la tâche redonne l'outillage sur l'hôte. Ce n'est mesuré ni dans Kata, ni par la tâche.

### Banc de l'outillage sous la forme de la tâche : résultat (note écrite à 2026-11-19T13:24:28Z UTC)

Journal : [`m1b-outil-forme.log`](m1b-outil-forme.log) (13:23:44 à 13:24:10 UTC, code 0).

**OF0 à OF4 tenues.**
- **OF0** : les versions sont celles de LG0. Le miroir est en lecture seule, avec 199 rpm. rpm de python lit `[en_US]` avec `HOME=/root` comme avec `HOME=/m/h`.
- **OF1** : la limite vaut `1024 / 1024` dans le sous-shell. Celle du shell reste `524288 / 524288` après (valeur de l'hôte).
- **OF2** : dnf-3 rend 0 en 23 s, avec 199 installations ; 201 paquets installés, dont 2 `gpg-pubkey`.
- **OF3** : la racine vaut 555 avant le `chmod`. `etc/machine-id` existe (33 octets) et l'archive l'exclut. `tar` rend 0, sans rien sur stderr.
- **OF4** : `f.tar` vaut `7c07083c…` octet pour octet (343 930 880 octets, 13 332 membres).

**Portée.** Sur l'hôte, hors réseau, la forme que la tâche poserait (dnf-3, limite autour de dnf seul, langue `en_US` posée par `.rpmmacros`, racine 0555) redonne l'outillage. Les deux images ont donc maintenant une même forme d'installation, mesurée. Rien n'est mesuré dans Kata sous cette forme pour l'outillage, ni par une tâche.

### Tâches neuves de M1b, préparation et essais : prédictions (note écrite à 2026-11-19T13:44:07Z UTC, avant tout lancement)

**Objet.** Les deux tâches neuves du point 2 de la carte et le gabarit de pipeline sont écrits à sec. Ils sont éprouvés avant toute signature, sans politique neuve ni écriture dans Zot.
- [`builders/prefetch-racine-rpm.yaml`](../builders/prefetch-racine-rpm.yaml) (`738775b096b39a63…`) : runc, UID 65532, sur l'amorce. Il vérifie les clés, puis le `repomd.xml` de chaque dépôt (sha256 fixé, plus gpgv si le dépôt est signé), chaque métadonnée, chaque rpm de la liste (trouvé dans `primary`, puis `rpm -K`) et la couche de base (blob de Zot).
- [`builders/construire-racine-rpm.yaml`](../builders/construire-racine-rpm.yaml) (`57b3987439d824e6…`) : Kata privilégié, root, sur l'amorce. Il revérifie les entrées, relève les témoins réseau et installe sous la forme mesurée. Il compare la racine à la valeur fixée et arrête la tâche si elle diffère. Il écrit ensuite la couche de configuration et le layout OCI à la main.
- [`builders/builder-rpm.yaml`](../builders/builder-rpm.yaml) (`8c4e23bf70a2c031…`) : un gabarit rendu deux fois (`builder-mock-rocky9`, `builder-rocky9-bootstrap`), prefetch, construire, puis `publier-image` inchangée.
- Les entrées que les pipelines fixent sont copiées des bancs sous `builders/` : deux `dnf.conf`, la clé d'EPEL, les trois fichiers de configuration de S1, la liste du bootstrap. `prealables` contrôle leur égalité avec les bancs.
- [`m1b-builders.sh`](../m1b-builders.sh) (`19cf578efe481286…`) conduit quatre étapes. Les pods d'essai portent les labels existants `prefetch-rpm` et `construire-rpm`, dont les politiques sont posées. Un vrai PVC les enchaîne : le constructeur lit ce que le prefetch a écrit.

**Écarts avec les formes mesurées**, nommés avant la mesure :
- **pour les deux images** : `miroir` et `cles` sont atteints par des liens vers le workspace, au lieu de copies ;
- **pour le bootstrap**, par rapport à `pod_e` :
  - les chemins sont `/m/i`, `/m/cache` et `/m/dnf.conf`, au lieu de `/m/b-all`, `/m/cache-all` et `/m/dnf97.conf` ;
  - deux `rpm --root -qa` suivent dnf, contre un seul dans la sonde. `var/lib/rpm/rpmdb.sqlite-shm` est dans l'archive et a déjà varié sur l'hôte : c'est le premier membre à regarder si `b063feb3…` n'est pas retrouvé ;
- **pour l'outillage** : l'archive est écrite dans `/w`, puis l'arbre est retiré avant le layout.

**TQ, `prealables`** (hôte, hors ligne) :
- **TQ1** : l'étape rend 0. Les valeurs des pipelines sont égales aux bancs et aux journaux archivés, et les copies de `builders/` aussi.
- **TQ2** : les deux pipelines sont rendues sans marqueur restant. Les paramètres des pas sont ceux des tâches. Le contexte de sécurité et les ressources du constructeur sont ceux du pas `construire` de `construire-rpm` signée.
- **TQ3** : l'analyseur du paramètre `fichiers`, extrait de la tâche, redonne les trois fichiers de la couche de S1 octet pour octet.
- **TQ4** : les quatre scripts substitués passent `bash -n` ; shellcheck ne signale rien (confiance moyenne). Leur base64 reste sous la borne de 131 071, avec 1 000 de marge.
- **TQ5** (confiance moyenne) : entrées attendues du prefetch, 224 fichiers pour l'outillage (199 rpm, 23 fichiers de `repodata`, 2 clés), et 20 pour le bootstrap (10 rpm, 8 de `repodata`, 1 clé, la couche).

**TC, `banc`** (hôte, hors ligne : racine de l'amorce extraite à neuf, chroot sous `unshare -n`) :
- **TC1** : les entrées assemblées sont égales aux entrées attendues. Les deux scripts rendent 0. Les trois témoins réseau échouent.
- **TC2** : rpm de python lit `[en_US]` pour l'outillage et `[all]` pour le bootstrap. dnf-3 rend 0, sous la limite `1024 / 1024`.
- **TC3** : la tâche trouve la racine conforme, `7c07083c…` pour l'outillage et `b063feb3…` pour le bootstrap, au bit près. Confiance moyenne pour le bootstrap, à cause des écarts ci-dessus.
- **TC4** : les deux layouts sont relus par python (blobs, tailles, `diff_ids`) et par oras. Le manifeste a le digest du résultat. L'outillage a 2 couches et `Env` ; le bootstrap a 1 couche et les deux annotations de base.
- **TC5** (confiance moyenne) : le contenu de la couche de configuration est celui de S1, fichier par fichier. Son sha256 diffère de `f5710d47…` : S1 l'a archivée par le tar de l'hôte, la tâche par celui de l'amorce.
- Les digests des deux images ne sont pas prédits. Ils sont relevés, et servent de référence aux pods.

**EP, `essai_prefetch`** (cluster : PVC `m1bt-w`, deux pods runc au label `prefetch-rpm`) :
- **EP1** : les politiques sont relues. Le PVC et les pods sont admis à blanc. L'admission sous le label neuf `prefetch-racine-rpm` est relevée, sans prédiction.
- **EP2** : les deux scripts rendent 0 :
  - signatures de `repomd.xml` valides pour `baseos98`, `appstream98` et `baseos97` ;
  - `rpm -K` à 199 OK sur 199, puis 10 sur 10 ;
  - blob `812c4412…` lu dans Zot sans compte (confiance moyenne : la lecture anonyme du blob par `curl` n'a jamais été mesurée).
- **EP3** : chaque arbre écrit est égal aux entrées du banc, fichier par fichier.

**EC, `essai_construire`** (cluster : deux pods Kata au label `construire-rpm`, entrées lues sur le PVC en lecture seule) :
- **EC1** : les pods sont admis à blanc et prêts sous `kata`. L'admission sous le label neuf `construire-racine-rpm` est relevée, sans prédiction.
- **EC2** : les deux scripts rendent 0. Les témoins échouent, et la racine est conforme pour les deux images.
- **EC3** : `DIGEST_CONSTRUIT` et le sha256 d'`image.tar` sont égaux à ceux du banc, pour les deux images.
- **EC4** : les pods et le PVC sont retirés. Aucun objet au préfixe `m1bt-` ne reste.

**Portée prévue.** Si TC à EC sont tenues, les scripts qui seraient signés redonnent les deux racines, et donnent le même digest d'image sur l'hôte et dans Kata. Les entrées sont téléchargées par le prefetch, et non copiées. Restent hors de portée :
- l'essai ne passe pas par Tekton, et porte les labels existants ;
- rien n'est signé ni écrit dans Zot ;
- il a lieu le même jour : le point 1 A demande encore un autre jour.

### Tâches neuves, `prealables` : résultat (note écrite à 2026-11-19T13:46:27Z UTC)

Journaux :
- [`m1b-builders-prealables-1.log`](m1b-builders-prealables-1.log) (début 2026-11-19T13:44:16Z, code 1). Mon contrôle d'égalité des paramètres `depots`, `liste` et `cles` entre les deux tâches comparait par `==` de yq deux listes de dictionnaires. Il a rendu `false` sur des valeurs égales. Il compare maintenant les deux JSON en texte.
- [`m1b-builders-prealables-2.log`](m1b-builders-prealables-2.log) (début 2026-11-19T13:44:39Z, code 1). shellcheck signale SC2034 dans le script de construction : `url` est lue mais jamais utilisée dans la revérification des dépôts. La variable est remplacée par `_` dans la tâche.
- [`m1b-builders-prealables.log`](m1b-builders-prealables.log) (début 2026-11-19T13:44:49Z, fin 13:44:53 UTC, code 0).

**Correction datée des prédictions** : ces deux corrections changent `builders/construire-racine-rpm.yaml`, dont le sha256 passe à `3a2c00b2565324dd…`, et `m1b-builders.sh`, qui passe à `ab2969fd0e6ad3bd…`. Elles ont été faites après le commit des prédictions. Les dossiers de `prealables` sont aussi devenus neufs à chaque passage (`mktemp`), sans rien effacer. Aucune autre ligne des tâches ne change.

**TQ1 à TQ5 tenues** au troisième passage.
- **TQ1** : les valeurs sont égales aux bancs et aux journaux archivés, et les copies de `builders/` aussi.
- **TQ2** : aucun marqueur ne reste dans les deux pipelines, et les paramètres sont ceux des tâches. Le contexte de sécurité et les ressources du constructeur sont ceux de `construire-rpm` signée.
- **TQ3** : l'analyseur de la tâche redonne les trois fichiers de S1 octet pour octet (87, 1 047 et 1 043 octets).
- **TQ4** : `bash -n` passe et shellcheck ne signale rien, une fois SC2034 corrigé. Les quatre scripts font en base64, sous la borne de 131 071 :

  | Script | Octets | base64 |
  |---|---|---|
  | prefetch, outillage | 33 697 | 44 932 |
  | prefetch, bootstrap | 10 590 | 14 120 |
  | construction, outillage | 37 708 | 50 280 |
  | construction, bootstrap | 14 125 | 18 836 |

- **TQ5** : 224 entrées attendues pour l'outillage, 20 pour le bootstrap.

### Tâches neuves, `banc` : résultat (note écrite à 2026-11-19T13:46:27Z UTC)

Journal : [`m1b-builders-banc.log`](m1b-builders-banc.log) (13:45:03 à 13:45:45 UTC, code 0). Les deux scripts de construction substitués ont été joués tels quels sur l'hôte, hors réseau, dans une racine de l'amorce extraite à neuf.

**TC1 à TC5 tenues.**
- **TC1** : les entrées assemblées sont égales aux entrées attendues. Les deux scripts rendent 0. Les trois témoins réseau échouent, pour chaque image.
- **TC2** :
  - rpm de python lit `[en_US]` pour l'outillage et `[all]` pour le bootstrap ;
  - la limite vaut `1024 / 1024` dans le sous-shell ;
  - dnf-3 rend 0, en 26 s pour l'outillage (199 installations) et en 3 s pour le bootstrap (6 installations, 4 montées).
- **TC3** : la tâche a trouvé chaque racine conforme, et a donc continué :
  - outillage : `7c07083c…`, 343 930 880 octets, 13 332 membres ;
  - bootstrap : `b063feb3…`, 241 981 440 octets, 11 472 membres.

  Les écarts nommés avec `pod_e` n'ont rien changé : chemins `/m/i` et `/m/cache`, deux `rpm --root -qa` après dnf, liens vers le workspace.
- **TC4** : les layouts sont relus par python et par oras.
  - outillage : manifeste `sha256:70f8c412…` (553 octets), 2 couches, `Env` de S1, `image.tar` de sha256 `26ce192f…` ;
  - bootstrap : manifeste `sha256:6de899ac…` (624 octets), 1 couche, configuration `{}`, les deux annotations de base, `image.tar` de sha256 `e574aaa1…`.
- **TC5** : le contenu de la couche de configuration est celui de S1, fichier par fichier. Son sha256 vaut `04f0fe15…`, contre `f5710d47…` pour S1. Le comparateur membre à membre ne nomme aucun champ en cause : la cause de l'écart n'est pas relevée ici.

**Autres relevés** : pic de `/w`, 868 Mo pour l'outillage et 512 Mo pour le bootstrap (sur l'hôte, `/w` est un dossier ext4, pas un tmpfs). `memory.peak` est absent hors cgroup.

**Portée.** Sur l'hôte, les scripts qui seraient signés retrouvent les deux racines au bit près, puis écrivent un layout valide. Les digests `70f8c412…` et `6de899ac…` servent de référence aux pods d'essai. Rien n'est encore mesuré dans Kata ni par le prefetch.

### Correction datée du 19/11/2026, écrite à 2026-11-19T13:48:21Z UTC : premier essai du prefetch, et relance sous `m1bt2`

Journal : [`m1b-builders-essai_prefetch-1.log`](m1b-builders-essai_prefetch-1.log) (début 13:46:33 UTC, code 1).
- **Relevés avant l'échec** : les politiques sont relues, et le PVC et les deux pods sont admis à blanc. Le pod sous le label neuf `prefetch-racine-rpm` est lui aussi admis à blanc.
- **Échec** : le pod `m1bt-po` était prêt sur `sc-build`. Le script de l'outillage s'est arrêté au contrôle des paramètres, avant tout téléchargement : `KO   nom de rpm invalide : passt-0^20251210.gd04c480-7.el9_8.x86_64.rpm`.
- **Cause** : la liste des caractères permis dans un nom de rpm n'avait pas `^`. C'est le seul nom de la liste qui en a un ; le banc de l'hôte l'avait téléchargé tel quel.
- **Correctif** : `^` est admis dans `builders/prefetch-racine-rpm.yaml`, dont le sha256 passe à `60f4577f0da05a20…`. Le nom passe toujours non encodé à curl, comme au banc ; seul `+` est encodé, comme dans `prefetch-rpm`.
- **Ménage** : le pod raté et son PVC, vide, sont retirés.
- **Relance** sous le préfixe neuf `m1bt2`, puisque le script de prefetch change. `prealables` et `banc` sont rejoués sous ce préfixe, dans des journaux neufs (`m1b-builders-m1bt2-<étape>.log`). Les prédictions TQ à EC valent telles quelles pour cette relance, avec `m1bt2-w` et le préfixe `m1bt2-` à la place de `m1bt-w` et `m1bt-`. Les scripts de construction ne changent pas : TC doit redonner les mêmes digests, `70f8c412…` et `6de899ac…`.

### Tâches neuves, essais sous `m1bt2` : résultat (note écrite à 2026-11-19T13:56:06Z UTC)

Journaux, tous en code 0 :
- [`m1b-builders-m1bt2-prealables.log`](m1b-builders-m1bt2-prealables.log) (13:48:27 à 13:48:30 UTC) et [`m1b-builders-m1bt2-banc.log`](m1b-builders-m1bt2-banc.log) (13:48:30 à 13:49:13 UTC) : TQ et TC tenues de nouveau. Le banc redonne `70f8c412…` et `6de899ac…`, les mêmes digests que sous `m1bt`.
- [`m1b-builders-m1bt2-essai_prefetch.log`](m1b-builders-m1bt2-essai_prefetch.log) (13:49:13 à 13:52:15 UTC).
- [`m1b-builders-m1bt2-essai_construire.log`](m1b-builders-m1bt2-essai_construire.log) (13:52:26 à 13:55:03 UTC).

**EP1 à EP3 tenues.**
- **EP1** : les politiques sont relues. Le PVC `m1bt2-w` et les deux pods sont admis à blanc. Relevé : le pod est aussi admis à blanc sous le label neuf `prefetch-racine-rpm`.
- **EP2** :
  - signatures de `repomd.xml` valides pour `baseos98`, `appstream98` et `baseos97`. `epel9` n'est pas signé : son ancre est le sha256 fixé ;
  - `rpm -K` à 199 OK sur 199, puis 10 sur 10 ;
  - le blob `812c4412…` (87 054 388 octets) est lu dans Zot sans compte, par curl avec la CA du PoC.

  Durées des scripts : 99 s pour l'outillage (224 fichiers, 227 117 890 octets), 11 s pour le bootstrap (20 fichiers, 115 664 404 octets).
- **EP3** : chaque arbre écrit est égal aux entrées du banc, fichier par fichier (listes `93f2a63e…` et `7af63de7…`).

**EC1 à EC4 tenues.**
- **EC1** : les pods sont admis à blanc et prêts sous `kata`, sur `sc-build`. Relevé : le pod est aussi admis à blanc sous le label neuf `construire-racine-rpm`.
- **EC2** :
  - les deux scripts rendent 0 et les trois témoins échouent (code 124) ;
  - les entrées sont lues sur le PVC en virtiofs, en lecture seule, et revérifiées ;
  - dnf-3 rend 0 en 43 s (outillage) et 5 s (bootstrap) ;
  - les deux racines sont conformes : `7c07083c…` et `b063feb3…`.
- **EC3** : `DIGEST_CONSTRUIT` et le sha256 d'`image.tar` sont ceux du banc, pour les deux images :
  - outillage : `sha256:70f8c412…`, `image.tar` `26ce192f…` ;
  - bootstrap : `sha256:6de899ac…`, `image.tar` `e574aaa1…`.
- **EC4** : les pods et le PVC sont retirés, et aucun objet au préfixe `m1bt2-` ne reste.

**Autres relevés** :
- pic de `/w`, 862 Mo et 503 Mo ;
- `memory.peak` du cgroup, 1 360 482 304 et 711 454 720 octets, sous la limite de 6 Gi ;
- limite du shell hors du sous-shell, 2³⁰.

**Portée.** Les scripts qui seraient signés font la chaîne complète sans Tekton. Le prefetch runc télécharge et vérifie les entrées ; le constructeur Kata, sans réseau, les lit sur le même PVC. Les deux racines de M1b sont retrouvées au bit près, et chaque image a le même digest sur l'hôte et dans Kata. Restent hors de portée :
- l'essai porte les labels existants, et ne passe pas par Tekton ;
- rien n'est signé, rien n'est écrit dans Zot ;
- tout est mesuré le même jour : le point 1 A demande encore un autre jour.

Les deux pods seraient admis à blanc sous les labels neufs. Leurs politiques réseau restent à poser, sur accord.

## Prédictions du 19/11/2026, écrites à 14:14:38 UTC : base du bootstrap vérifiée et déclarée (« Vérifier et déclarer »)

**Changement**, fait après la décision du propriétaire (carte, note de 14:12:23 UTC) et avant tout lancement :
- `builders/prefetch-racine-rpm.yaml` passe de `60f4577f…` à `11a9a032eb4bc7b3…` :
  - le paramètre `couche` devient « dépôt sha256-manifeste sha256-couche » ;
  - le manifeste de base est lu par curl dans `/tmp` (`/v2/<dépôt>/manifests/sha256:<h>`, en-tête `Accept` de manifeste OCI). Le prefetch contrôle son sha256, son type et sa couche unique, égale à la couche fixée ;
  - le résultat objet `BASE_ARTIFACT_INPUTS` est déclaré. Il est écrit pour le bootstrap seulement.
- `m1b-builders.sh` passe de `ab2969fd…` à `906ce9911ac2971f…`. Changent :
  - le rendu de la pipeline du bootstrap (`couche` du prefetch avec `ee90dc0e…`) ;
  - la substitution du résultat (`/tmp/resultat-base`) ;
  - deux contrôles d'`essai_prefetch` : le JSON du bootstrap, et l'absence du fichier pour l'outillage.
- `builders/construire-racine-rpm.yaml` est inchangé (`3a2c00b2565324dd…`).

**Lancement prévu** : `prealables`, `banc`, `essai_prefetch` puis `essai_construire`, sous `PREFIXE=m1bt3`, chacune dans un journal neuf `m1b-builders-m1bt3-<étape>.log`.

- **BV1, `prealables`** : code 0.
  - `bash -n` passe, et shellcheck ne signale rien sur les quatre scripts.
  - Les scripts de construction sont inchangés par rapport à `m1bt2` : 50 280 et 18 836 caractères en base64.
  - Les scripts de prefetch grandissent, et restent sous la borne de 131 071.
  - Les entrées attendues restent 224 et 20 : le manifeste n'est pas écrit dans le workspace.
- **BV2, `banc`** : code 0, avec les mêmes digests qu'avant, `sha256:70f8c412…` pour l'outillage et `sha256:6de899ac…` pour le bootstrap. Les `image.tar` sont aussi les mêmes, `26ce192f…` et `e574aaa1…`.
- **BV3, `essai_prefetch`** : code 0.
  - Le pod du bootstrap lit le manifeste `ee90dc0e…` dans Zot sans compte, et l'affiche à 573 octets, image OCI à une couche, `812c4412…`.
  - Son `BASE_ARTIFACT_INPUTS` vaut `{"uri":"oci://sc-stockage.poc.test:5000/amont/rockylinux/rockylinux","digest":"sha256:ee90dc0e…"}`.
  - Le pod de l'outillage affiche « aucune base », et `/tmp/resultat-base` y est absent.
  - Les deux arbres sont égaux aux entrées du banc, fichier par fichier.
- **BV4, `essai_construire`** : code 0, mêmes digests et mêmes `image.tar` qu'au banc. Il ne reste aucun objet `m1bt3-` après coup.

**Pari le moins sûr** : BV3, sur la lecture anonyme d'un **manifeste** dans Zot. Celle d'un blob du même dépôt est mesurée (EP2), celle d'un manifeste ne l'est pas. Si Zot la refuse, le prefetch s'arrête sur « HTTP 401 » ; il faudrait alors revoir la lecture, sans changer la politique de Zot sans accord.

**Hors de portée** : le cas « déclaré mais non écrit » dans un vrai TaskRun. Les pods d'essai ne passent pas par Tekton, donc il reste lu dans le code et non mesuré jusqu'au premier PipelineRun de l'outillage.

### Base vérifiée et déclarée : résultat (note écrite à 14:21:39 UTC)

Journaux sous `m1bt3`, tous à code 0 :

| Étape | Journal | Heures UTC |
|---|---|---|
| `prealables` | [`m1b-builders-m1bt3-prealables.log`](m1b-builders-m1bt3-prealables.log) | fin 14:14:49 |
| `banc` | [`m1b-builders-m1bt3-banc.log`](m1b-builders-m1bt3-banc.log) | fin 14:15:33 |
| `essai_prefetch` | [`m1b-builders-m1bt3-essai_prefetch.log`](m1b-builders-m1bt3-essai_prefetch.log) | 14:15:38 à 14:17:57 |
| `essai_construire` | [`m1b-builders-m1bt3-essai_construire.log`](m1b-builders-m1bt3-essai_construire.log) | 14:18:07 à 14:20:43 |

**BV1 à BV4 tenues.**
- **BV1** : `bash -n` passe et shellcheck ne signale rien, sur les quatre scripts.
  - Les scripts de construction ont le même sha256 que sous `m1bt2` (`956e39c2…` et `cad7f550…`, relevés dans les deux journaux de `prealables`).
  - Les scripts de prefetch passent à 46 600 et 15 876 caractères en base64.
  - Il y a toujours 224 et 20 entrées attendues.
- **BV2** : mêmes digests, `70f8c412…` et `6de899ac…`, et mêmes `image.tar`, `26ce192f…` et `e574aaa1…`.
- **BV3** :
  - le pod du bootstrap lit dans Zot, sans compte, le manifeste `ee90dc0e…` : 573 octets, image OCI à une couche, `812c4412…`. Le pari le moins sûr est tenu : la lecture anonyme d'un manifeste est maintenant mesurée ;
  - le résultat vaut `{"uri":"oci://sc-stockage.poc.test:5000/amont/rockylinux/rockylinux","digest":"sha256:ee90dc0e…"}` ;
  - l'outillage affiche « aucune base », et le fichier du résultat y est absent ;
  - les deux arbres sont égaux aux entrées du banc.
- **BV4** : dans Kata, sur le PVC, les digests et les `image.tar` sont les mêmes qu'au banc. Aucun pod ni PVC `m1bt3-` ne reste.

**Portée** : l'annotation `base.digest ee90dc0e…` de l'image du bootstrap est maintenant contrôlée par le prefetch, ce qui ferme le point ouvert. Le cas « déclaré mais non écrit » reste lu dans le code, sans être mesuré dans un TaskRun. Ces pods ne passent pas par Tekton.

## Correction datée du 19/11/2026, écrite à 14:24:33 UTC : « l'annotation est contrôlée » dépassait la mesure

- **Ce qui était écrit.** La note « Base vérifiée et déclarée : résultat » dit que l'annotation `base.digest` est « maintenant contrôlée par le prefetch, ce qui ferme le point ouvert ». La carte le dit aussi.
- **Ce qui est mesuré.** Le prefetch contrôle le manifeste dont le digest figure dans son propre paramètre `couche`. L'annotation, elle, est écrite par `construire-racine-rpm` depuis un autre paramètre, `annotations`.
  - Dans la pipeline rendue, ce sont deux littéraux indépendants.
  - Ils ne sont égaux que parce que `m1b-builders.sh` les tire tous deux de la même variable.
  - Aucun contrôle ne les reliait.
- **Phrase juste.** Le manifeste passé au prefetch est contrôlé. Son égalité avec l'annotation n'est pas encore montrée.
- **Remède, sans changer aucune tâche.** `prealables` reçoit un contrôle sur chaque pipeline rendue (`m1b-builders.sh` passe à `82004de28016ee27…`). Le contrôle exige, pour le bootstrap :
  - `base.digest` égal à `sha256:` suivi du champ manifeste de `couche` du prefetch ;
  - `base.name` égal à `sc-stockage.poc.test:5000/` suivi du dépôt ;
  - la `couche` de construire égale au troisième champ.

  Pour l'outillage, il exige « sans base » des deux côtés, avec des annotations `{}`.

**AN1** : `prealables` est rejoué seul sous `PREFIXE=m1bt4`, dans le journal neuf `m1b-builders-m1bt4-prealables.log`.
- Il rend 0.
- Il affiche « sans base » pour l'outillage, et « base amont/rockylinux/rockylinux@sha256:ee90dc0e23c2, couche 812c44127102 : cohérentes » pour le bootstrap.
- Les quatre scripts substitués gardent les sha256 de `m1bt3`, puisque les tâches et les valeurs ne changent pas. Les essais de `m1bt3` restent donc valables.

### AN1 : résultat (note écrite à 14:25:24 UTC)

Journal : [`m1b-builders-m1bt4-prealables.log`](m1b-builders-m1bt4-prealables.log), fin à 14:24:43 UTC, code 0.

**AN1 tenue.**
- Le contrôle donne « sans base » pour l'outillage, et « base amont/rockylinux/rockylinux@sha256:ee90dc0e23c2, couche 812c44127102 : cohérentes » pour le bootstrap.
- Les quatre scripts substitués gardent les sha256 de `m1bt3` (`a93deebb…`, `912520ea…`, `956e39c2…`, `cad7f550…`). Les essais de `m1bt3` restent donc valables.

**Refus montrés** : [`m1b-coherence-refus.sh`](m1b-coherence-refus.sh), journal [`m1b-coherence-refus.log`](m1b-coherence-refus.log) (14:25:00 UTC). Le contrôle, extrait tel quel de `m1b-builders.sh`, a été joué sur des copies de la pipeline rendue du bootstrap.
- Sur la copie intacte, il répond « cohérentes ».
- Il répond « incohérent » sur chacune des trois altérations :
  - `base.digest` remplacé par `ed654c69…` ;
  - `base.name` changé ;
  - `couche` de construire changée.

**Portée** : dans les pipelines que `m1b-builders.sh` rend, l'annotation de base est maintenant égale au manifeste que le prefetch contrôle. La pipeline signée, elle, n'aura ce contrôle qu'à son rendu par ce script. Aucune tâche ne le refait à l'exécution.

## Prédictions du 19/11/2026, écrites à 15:33:13 UTC : mesure d'un autre jour dans Kata (à partir du 20/11 à 00:00 UTC)

**Ce qui est mesuré.** Le 19/11, les deux racines et les deux images ont été reproduites dans Kata, mais le même jour. Le point 1 A demande un autre jour. Rien n'a changé dans les scripts depuis : `m1b.sh` a le sha256 `373ae33436d298e3…` (celui de `pod_e`), `m1b-builders.sh` `82004de28016ee27…` (celui de `m1bt4`, dont `prealables` rend les mêmes quatre scripts que `m1bt3`).

**Lanceur** : [`m1b-jour-kata.sh`](m1b-jour-kata.sh) (sha256 `43f21076910a424e…`), une seule commande, qui refuse de partir avant le 20/11 à 00:00 UTC (essayé le 19/11 à 15:32:32 UTC : code 2, rien lancé). Il enchaîne huit étapes, chacune dans un journal neuf, et s'arrête à la première en échec ou sur un journal déjà présent :
- **ancienne forme**, sous le préfixe `m1b-20` : `prealables`, `pod_c` (outillage, limite posée dans le shell, comme le 19/11), `prealables_boot`, `pod_e` (bootstrap, limite dans le sous-shell de dnf) ; journaux `m1b-20-<étape>.log`. `pod_a` et `pod_b` ne sont pas rejoués : à la limite par défaut, chacun dure environ 97 min, sans rien dire de plus sur le contenu ;
- **forme de la tâche**, sous le préfixe `m1bt-20` : `prealables`, `banc`, `essai_prefetch`, `essai_construire` ; journaux `m1b-builders-m1bt-20-<étape>.log` ;
- **bilan** : 21 valeurs relues dans les journaux neufs et confrontées à celles du 19/11 (`m1b-pod_c.log`, `m1b-pod_e.log`, `m1b-builders-m1bt3-*.log`). Les motifs ont été essayés sur les journaux du 19/11 contre eux-mêmes : 21 OK. Journal du lanceur : `m1b-jour-kata.log`.

**Écritures** : quatre pods d'essai et un PVC dans `builds`, sous des labels existants, retirés par les scripts (accord permanent du 18/11). Ni politique, ni signature, ni écriture dans Zot.

**Téléchargements** (pods de prefetch, sortie posée le 16/11) : environ 113,7 Mo de rpm (199 paquets) et les métadonnées de BaseOS et AppStream 9.8 depuis `dl.rockylinux.org/vault/rocky/9.8`, et d'EPEL depuis `dl.fedoraproject.org/pub/archive/epel/9.8`. S'y ajoutent, depuis Zot sur le laptop, 10 rpm (environ 2 Mo), les métadonnées de BaseOS 9.7 et la couche amont `812c4412…` (87 Mo). Les sha256 sont contrôlés par le script, contre les valeurs fixées par la pipeline.

**Ancienne forme**
- **JK1** (haute) : `prealables` et `prealables_boot` rendent 0, entrées conformes, pods admis à blanc.
- **JK2** (haute) : dans `pod_c`, les témoins réseau échouent, la limite vaut `1024 / 1024`, dnf rend 0 en moins de 300 s (40 s le 19/11), 201 paquets dont 2 `gpg-pubkey`, racine en 555. L'archive vaut `7c07083c…` octet pour octet.
- **JK3** (haute) : dans `pod_e`, dnf-3 rend 0, la liste `rpm -qa` après vaut `1ca7c54b…` (celle de S1), et l'archive vaut `b063feb3…` octet pour octet.

**Forme de la tâche**
- **JT1** (haute) : `prealables` rend 0 et rend les quatre mêmes scripts que le 19/11 (`script-po` `a93deebb…`, `script-pb` `912520ea…`, `script-co` `956e39c2…`, `script-cb` `cad7f550…`), contrôle de cohérence de la base compris (AN1).
- **JT2** (haute) : au `banc`, les racines valent `7c07083c…` et `b063feb3…`, les manifestes `70f8c412…` (outillage) et `6de899ac…` (bootstrap), comme le 19/11.
- **JT3** (moyenne) : au prefetch, les `repomd.xml` publics sont ceux du 19/11 (`abac8b17…` BaseOS 9.8, `a3ca4230…` AppStream 9.8, `e86fdcd8…` EPEL), comme `fa6d5054…` (BaseOS 9.7, dans Zot). Les arbres écrits ont les listes `93f2a63e…` (224 fichiers) et `7af63de7…` (20 fichiers). La confiance est moyenne parce que ces sources sont hors du laptop : vault et l'archive d'EPEL sont présentés comme figés, ce qui n'est vérifié que d'un jour à l'autre.
- **JT4** (haute) : `BASE_ARTIFACT_INPUTS` vaut `ee90dc0e…` pour le bootstrap et reste absent pour l'outillage.
- **JT5** (haute) : dans Kata, `construire` rend les manifestes `70f8c412…` et `6de899ac…` et les `image.tar` `26ce192f…` et `e574aaa1…`, égaux au banc du jour et au 19/11. PVC retiré, 0 objet restant au préfixe.

**Ce qu'un écart voudrait dire**
- **Une racine différente** (JK2, JK3, JT2 ou JT5) : elle ne se reproduit pas d'un jour à l'autre, et le point 1 A n'est pas établi. Dans la forme de la tâche, `construire` s'arrête alors sur la racine (« Garder l'arrêt »), ce qui est voulu. Pas de signature ; le comparateur nomme les membres, et la suite est une décision avec toi.
- **Une racine égale, mais un manifeste ou une `image.tar` différents** : la cause est dans la couche de configuration ou dans le layout, pas dans dnf. Pas de signature avant d'avoir lu l'écart.
- **Un `repomd.xml` public différent** (JT3) : la source amont a bougé. Le prefetch s'arrête sur le sha256 fixé, ce qui est voulu. Pas de signature ; le choix des sources te revient.

**Portée prévue.** Si tout tient, les deux racines et les deux images se reproduisent dans Kata sur deux jours (19 et 20/11), sur un seul nœud et un seul hôte. Le point 1 A serait établi dans ce cadre, pas au-delà : ni pour un autre nœud, ni après une mise à jour du noyau ou de Kata. La signature resterait suspendue aux points ouverts : `--dry-run=server`, cas refusés, docs/04 pour curl et GnuPG, les deux politiques de réseau.

## Prédictions du 19/11/2026, écrites à 15:36:10 UTC : cas refusés de la construction, au banc

**Pourquoi.** Aucun cas refusé n'est mesuré pour les tâches neuves (carte, note de 13:58:26 UTC). Ce banc couvre la tâche de construction, hors ligne, sur l'hôte. Les cas du prefetch (`repomd` faux, autre manifeste, bon manifeste avec une couche fausse) demandent un pod du cluster et la sortie réseau du prefetch ; ils sont à préparer à part.

**Banc** : [`m1b-refus-banc.sh`](m1b-refus-banc.sh) (sha256 `779f6c763f122358…`), journal à venir `m1b-refus-banc.log`.
- Il joue tels quels les scripts que `prealables` a rendus sous `m1bt3` (`script-co.sh` `956e39c2…`, `script-cb.sh` `cad7f550…`), relus au sha256. Ce sont aussi ceux que JT1 attend le 20/11.
- Chaque cas ne change qu'une chose : une ligne du script, contrôlée par `diff`, ou un octet d'une entrée, sur une copie réelle et jamais sur un lien dur. Il a sa racine de l'amorce extraite à neuf et le même chroot que l'étape `banc` (`unshare -n`, entrées en lecture seule).
- Un refus ne compte que si le code est non nul, s'il n'y a qu'une ligne `KO` et si c'est exactement le message de la garde visée. Il faut aussi que ni `image.tar` ni le résultat `DIGEST_CONSTRUIT` ne soient écrits. Un refus pour une autre cause est donc un échec de la prédiction.
- Ni cluster, ni Zot, ni réseau.

- **RZ1** (haute) : témoin du bootstrap, script tel quel : code 0, résultat `sha256:6de899ac…`.
- **RZ2** (haute) : bootstrap avec `RACINE` remplacée par la racine de l'outillage. dnf tourne, la racine construite vaut `b063feb3…`, puis la tâche s'arrête sur « racine différente de la valeur fixée par la pipeline ».
- **RZ3** (haute) : un octet inversé dans `dbus-libs-1.12.20-8.el9.x86_64.rpm` : refus « rpm altéré : baseos97 … », avant dnf.
- **RZ4** (haute) : un octet inversé dans `couche.tar.gz` : refus « couche altérée », avant dnf et avant l'extraction.
- **RZ5** (haute) : un octet inversé dans `repomd.xml` de `baseos97` : refus « baseos97 : repomd.xml altéré », avant dnf.
- **RZ6** (haute) : témoin de l'outillage, script tel quel : code 0, résultat `sha256:70f8c412…`.
- **RZ7** (haute) : outillage avec `RACINE` remplacée par celle du bootstrap. La racine construite vaut `7c07083c…`, puis refus sur la racine.
- **RZ8** (haute) : les entrées des bancs du 18/11 et la couche amont du cache OCI sont inchangées après le banc (sha256 de la liste, avant et après).

**Portée prévue.** Si tout tient, la tâche de construction refuse au banc une racine fixée fausse, et un rpm, une couche ou un `repomd.xml` altérés après le prefetch, chacun par sa garde. Ce n'est pas mesuré dans Kata ni dans un TaskRun. La signature d'une clé ou d'un `repomd.xml` n'est pas rejouée ici : la tâche de construction ne contrôle que leur sha256, et c'est le prefetch qui vérifie les signatures.

### Correction datée du 19/11/2026, écrite à 15:37:06 UTC : premier passage du banc des cas refusés arrêté sur un défaut du script

- **Ce qui s'est passé.** Le premier passage, du 19/11 à 15:36:15 UTC, à HEAD `f39a39d`, est gardé dans [`m1b-refus-banc-1.log`](m1b-refus-banc-1.log). RZ1 à RZ3 y ont tenu. Le cas `b-couche` s'est ensuite arrêté avant d'être joué : python n'a pas pu ouvrir en écriture la copie de `couche.tar.gz`. La copie garde le mode du cache OCI (`0444`), alors que les autres entrées copiées sont inscriptibles. Rien n'a été altéré ; RZ8 n'a pas été relevée.
- **Correction** : `chmod u+w` sur la copie, juste après le contrôle qui refuse d'altérer un lien dur. Rien d'autre ne change. Le script corrigé a le sha256 `6db7ea19eb7c55d1…`.
- **Relance** : le banc complet est rejoué, RZ1 à RZ8, dans un journal neuf, `m1b-refus-banc.log`. Les prédictions ne changent pas.

### Cas refusés de la construction, au banc : résultat (note écrite le 19/11/2026 à 15:39:07 UTC)

Journal : [`m1b-refus-banc.log`](m1b-refus-banc.log), de 15:37:11 à 15:38:31 UTC, à HEAD `e21469b`, code 0, 0 KO. Premier passage arrêté : [`m1b-refus-banc-1.log`](m1b-refus-banc-1.log) (correction datée ci-dessus).

**RZ1 à RZ8 tenues.**
- **Témoins** : RZ1, bootstrap, code 0, `sha256:6de899ac…` ; RZ6, outillage, code 0, `sha256:70f8c412…`. Ce sont les manifestes de `m1bt3`.
- **RZ2 et RZ7, racine fixée fausse** : dnf tourne, la racine construite vaut `b063feb3…` (bootstrap) ou `7c07083c…` (outillage), puis la tâche s'arrête sur « racine différente de la valeur fixée par la pipeline », avec la valeur fausse dans le message.
- **RZ3, RZ4, RZ5, entrées altérées d'un octet** : refus « rpm altéré : baseos97 dbus-libs-1.12.20-8.el9.x86_64.rpm », « couche altérée » et « baseos97 : repomd.xml altéré », chacun avant dnf.
- Dans les cinq refus : code 1, une seule ligne `KO`, égale au message de la garde visée, et ni `image.tar` ni résultat `DIGEST_CONSTRUIT`.
- **RZ8** : les entrées des bancs du 18/11 et la couche amont du cache sont inchangées. La liste des entrées de l'outillage vaut `93f2a63e…`, la même que celle de l'arbre écrit par le prefetch de `m1bt3`.

**Portée.** Au banc, sur l'hôte, hors ligne, la tâche de construction refuse une racine fixée fausse, ainsi qu'un rpm, une couche ou un `repomd.xml` altérés après le prefetch, chacun par sa garde. Ce n'est mesuré ni dans Kata, ni dans un TaskRun. Les cas du prefetch (`repomd` faux, autre manifeste, bon manifeste avec une couche fausse) restent à jouer, dans un pod du cluster.

**Place** : 100 679 212 kB libres sur /home après le banc, contre 107 346 784 kB au début du premier passage (journaux des deux passages). La taille des deux dossiers `m1b-refus-banc-*` n'est pas relevée ; aucun script ne les relit.

## Relevé de santé de curl : ce qui est relevé, écrit le 19/11/2026 à 15:39:07 UTC, avant le lancement

**Pourquoi.** docs/04 n'a pas de ligne pour curl, que `prefetch-racine-rpm` exécute depuis l'amorce (point ouvert d'avant signature). GnuPG relève de la session de la brique 09 et n'est pas relevé ici.

**Relevé** : étape `curl` ajoutée à [`sante.sh`](../sante.sh) (sha256 `c1f036e1e113d33a…`), mêmes relevés que l'étape `dnf` (Scorecard, dernière release, commits sur 90 jours, auteurs et domaines, fusionneurs, SECURITY.md, avis GitHub), plus les avis publiés par le projet dans `curl.se/docs/vuln.json`, et les fichiers `curl`, `curl-minimal`, `libcurl` et `libcurl-minimal` listés dans vault 9.8 BaseOS. Journal à venir : `sante-curl.log`. Lectures publiques seulement (API de GitHub, API de Scorecard, curl.se, dl.rockylinux.org), quelques centaines de Ko.

**Sans pari sur le verdict.** Ce qui le ferait « Risqué » au sens de docs/04 : aucune release depuis plus de 12 mois, dépôt archivé, mainteneur unique sans soutien, compromission non résolue. Ce qui le ferait « À surveiller » : un critère manquant, dont un Scorecard sous 6. La version exécutée est celle de Rocky (curl 7.76.1, lue dans l'essai du 19/11), pas la release amont : les correctifs suivent le rythme de la distribution, comme pour dnf. Le verdict proposé passera par le conseiller avant d'être écrit dans docs/04.

### Correction datée du 19/11/2026, écrite à 15:43:18 UTC : source des entrées du bootstrap dans les prédictions JK et JT

- **Erreur.** La note de 15:33:13 UTC dit : « depuis Zot sur le laptop, 10 rpm (environ 2 Mo), les métadonnées de BaseOS 9.7 et la couche amont ». C'est faux pour les rpm et les métadonnées. La ligne `depots` de la pipeline du bootstrap (`pipeline-b.yaml`, rendu sous `m1bt3`) est `baseos97 https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/x86_64/os fa6d5054… RPM-GPG-KEY-Rocky-9`, et le prefetch n'admet que vault et l'archive d'EPEL. Les 10 rpm et les métadonnées de BaseOS 9.7 viennent donc de vault. Seuls le manifeste de base `ee90dc0e…` et la couche `812c4412…` viennent de Zot.
- **Conséquence pour JT3** : la confiance moyenne, due aux sources hors du laptop, vaut aussi pour `fa6d5054…` (BaseOS 9.7). Rien d'autre ne change dans les prédictions.
- **Lanceur, relu** : dans `m1b.sh`, `pod_c` n'exige que `entrees.tar`, écrit par `prealables`. `pod_e` exige `entrees-boot.tar` et le pod rendu, écrits par `prealables_boot`. L'étape `banc` de `m1b.sh`, jouée le 19/11 avant les pods, n'est requise par aucun des deux. Le lanceur n'a pas d'étape manquante.

## curl exécuté par les prefetch : prédictions écrites le 19/11/2026 à 15:46:05 UTC, avant le lancement

**Pourquoi.** Le relevé de santé ([`sante-curl.log`](sante-curl.log), 15:39:13 UTC) porte sur le projet amont, alors que les prefetch exécutent le paquet de Rocky. Une lecture à la main, faite à 15:41 UTC dans une racine du banc où une tâche avait tourné (`b-temoin/r`), donne `curl-minimal-7.76.1-40.el9` dans l'amorce, alors que vault 9.8 liste `40.el9_8.8` et `40.el9_8.9`. Cette lecture n'est pas citable telle quelle ; elle est refaite ici par un script archivé, sur des racines extraites à neuf.

**Relevé** : [`m1b-curl-amorce.sh`](m1b-curl-amorce.sh) (sha256 `84da085cd5255fd9…`), journal à venir `m1b-curl-amorce.log`. Lectures publiques de `curl.se/docs/vuln.json` et de vault 9.8 BaseOS (`repomd.xml` et sa signature, `other`), quelques Mo. Ni cluster, ni Zot.

- **CA1** (haute) : l'amorce (couche `99c753a8…`) porte `curl-minimal` et `libcurl-minimal` en `7.76.1-40.el9`, construits le 27/01/2026, ainsi que `gnupg2-2.3.3-5.el9_7`, et ni `curl` ni `libcurl` complets.
- **CA2** (moyenne) : la racine de `99790c13`, image de `prefetch-rpm` déjà signée, porte `curl` et `libcurl` en `7.76.1-40.el9_8.9`, la révision que liste `s1-racine.log`.
- **CA3** (sans pari) : le nombre d'avis du projet curl publiés depuis un an dont les versions touchées comptent 7.76.1, et leurs gravités.
- **CA4** (haute) : le `repomd.xml` de vault 9.8 BaseOS a une signature valide par la clé de Rocky de l'amorce, `other` est conforme à `repomd.xml`, et `curl-minimal` y a au moins deux révisions, dont `40.el9_8.9`.
- **CA5** (sans pari) : pour chaque avis de CA3, si le changelog du paquet de l'amorce et celui de la dernière révision de vault le mentionnent.

**Lecture prévue.**
- Un avis mentionné dans le changelog est corrigé selon Rocky. Un avis absent n'est pas pour autant une faille : la version 7.76.1 peut ne pas avoir le code touché, ou Red Hat peut ne pas corriger un avis de faible gravité. On écrira donc « en retard de révisions », jamais « vulnérable », sans lecture plus poussée.
- La décision qui en découle, garder le curl figé de l'amorce avec ses contre-contrôles ou rafraîchir l'amorce, ce qui referait les références, te revient avant `SIGNER=1`. Rien ne change dans l'amorce ni dans les tâches avant la mesure du 20/11.
- `gnupg2` est relevé pour information. Sa ligne dans docs/04 revient à la session de la brique 09.

### curl exécuté par les prefetch : résultat (note écrite le 19/11/2026 à 15:47:22 UTC)

Journal : [`m1b-curl-amorce.log`](m1b-curl-amorce.log), de 15:46:06 à 15:46:10 UTC, à HEAD `588a3da`, code 0, 0 KO.

**CA1, CA2 et CA4 tenues ; CA3 et CA5 lues.**
- **CA1** : l'amorce porte `curl-minimal` et `libcurl-minimal` en `7.76.1-40.el9`, construits le 27/01/2026, et `gnupg2-2.3.3-5.el9_7`, sans `curl` ni `libcurl` complets. Son changelog de `curl-minimal` a 12 entrées, la plus récente du 21/01/2026 (`7.76.1-40`).
- **CA2** : la racine de `99790c13`, image de `prefetch-rpm`, porte `curl` et `libcurl` en `7.76.1-40.el9_8.9`, construits le 30/10/2026, et le même `gnupg2`.
- **CA4** : le `repomd.xml` de vault 9.8 BaseOS (`abac8b17…`, celui que fixe la pipeline de l'outillage) a une signature valide par la clé de Rocky de l'amorce, et `other` est conforme. `curl-minimal` y a 5 révisions : `40.el9`, `el9_8.5`, `el9_8.7`, `el9_8.8` et `el9_8.9`.
- **CA3** (lecture) : 36 avis du projet curl publiés depuis le 19/11/2025 comptent 7.76.1 parmi les versions touchées, 26 « Low » et 10 « Medium ». Le seul « High » de l'année (`CURL-CVE-2026-92392`, 14/10/2026, [`sante-curl.log`](sante-curl.log)) ne la compte pas.
- **CA5** (lecture) : le changelog du paquet de l'amorce n'en mentionne aucun. Celui de `40.el9_8.9` en mentionne 9 : 4 « Medium » (`CVE-2026-11856`, `CVE-2026-8927`, `CVE-2026-3783`, `CVE-2026-1965`) et 5 « Low ». Les 27 autres ne sont mentionnés dans aucun des deux.

**Lecture.**
- Le curl de l'amorce est **en retard de quatre révisions** sur Rocky 9.8. Il n'a pas 9 corrections que Rocky a publiées pour des avis touchant 7.76.1, dont 4 de gravité « Medium ». L'absence d'une mention ne prouve pas qu'une faille est présente : la gravité, le code de 7.76.1 et le choix de Red Hat n'ont pas été lus.
- Ce retard vient de l'image `rockylinux:9.8` du 27/01/2026, figée par digest (`ed654c69…`, D4 a). Il touche le prefetch de M1b. Il ne touche pas `prefetch-rpm`, déjà signé, dont l'image porte `el9_8.9`.
- **Contre-contrôles en place** : curl n'est qu'un transport. Ce qu'il écrit n'est gardé que si le sha256 est fixé par la pipeline, ou si la signature passe gpgv et `rpm -K`. Le pod tourne en runc, sous l'UID 65532, en Pod Security `restricted` ; il n'a pas de secret, et sa sortie réseau ne sera ouverte qu'à DNS, au 443 public et à Zot. Une faille de curl ne peut donc pas changer le contenu d'une entrée sans être vue. Elle peut viser le pod lui-même, par un serveur ou un intermédiaire TLS hostile ; ce n'est pas mesuré.
- **Choix avant `SIGNER=1`, qui te revient** : garder l'amorce figée, avec ces contre-contrôles, ou rafraîchir le curl du prefetch. Rafraîchir demande une image dérivée ou une autre amorce, et refait les références. Rien ne change avant la mesure du 20/11.
- `gnupg2` est en `el9_7` dans les deux images. Le fait est transmis à la session de la brique 09 ; sa ligne n'est pas écrite ici.

## Prédictions du 19/11/2026, écrites à 15:49:55 UTC : cas refusés du prefetch, dans des pods d'essai

**Script** : [`m1b-refus-prefetch.sh`](m1b-refus-prefetch.sh) (sha256 `09784e3dd24ad753…`), journal à venir `m1b-refus-prefetch.log`.
- Il joue le script de prefetch du bootstrap rendu sous `m1bt3` (`script-pb.sh` `912520ea…`, celui de JT1), relu au sha256. Chaque cas ne change qu'une ligne, contrôlée par `diff`.
- Chaque cas a son pod runc, comme `essai_prefetch` : image de l'amorce, UID 65532, label `prefetch-rpm`, sortie posée le 16/11, sélecteur relu avant. La sortie va sur un `emptyDir` au lieu du PVC.
- Un refus ne compte que si le code est non nul, s'il n'y a qu'une ligne `KO`, égale au message de la garde visée, et si ni `BASE_ARTIFACT_INPUTS` ni `couche.tar.gz` ne sont écrits. Pour les deux cas du manifeste, qui partagent le même message, la ligne `AssertionError` doit aussi montrer la couche lue dans le manifeste, ce qui sépare la garde de la couche de celle du `mediaType`. Les deux manifestes, lus dans le cache OCI local, sont des manifestes OCI (`application/vnd.oci.image.manifest.v1+json`) : `ed654c69…` a la couche `99c753a8…`, `ee90dc0e…` la couche `812c4412…`.
- **Écritures** : quatre pods d'essai dans `builds`, sous un label existant, retirés par le script (accord permanent du 18/11). Ni politique, ni signature, ni écriture dans Zot.
- **Lectures** : vault 9.7 BaseOS (métadonnées et 10 rpm, environ 2 Mo par cas) et Zot (manifestes, et la couche de 87 Mo dans le témoin seulement).

- **PX1** (haute) : témoin, script tel quel : code 0, `BASE_ARTIFACT_INPUTS` à `ee90dc0e…`, `couche.tar.gz` écrite.
- **PX2** (haute) : `repomd.xml` de `baseos97` fixé à `abac8b17…` (celui de BaseOS 9.8) : refus « baseos97 : repomd.xml différent du sha256 fixé », avant tout rpm.
- **PX3** (haute) : autre manifeste, `ed654c69…` (l'amorce), avec la couche fixée `812c4412…` : le manifeste est lu à son sha256, puis le prefetch refuse sur « manifeste de base : image OCI à une seule couche, la couche fixée, attendue », avec `AssertionError: ['sha256:99c753a8…']`.
- **PX4** (haute) : bon manifeste, `ee90dc0e…`, avec une couche fausse, `99c753a8…` : même refus, avec `AssertionError: ['sha256:812c4412…']`.
- **PX5** (haute) : aucun pod restant au préfixe `m1brp-`.

**Cas non joué, et pourquoi.** La paire cohérente (`ed654c69…`, `99c753a8…`) passerait le prefetch, puisque ce manifeste a bien cette couche. Aucun refus n'y est donc prédit. Ce qui l'arrête est le contrôle de cohérence de `prealables` (AN1) : il exige que l'annotation `base.digest` et la couche de `construire` égalent la base contrôlée par le prefetch. C'est déjà mesuré par trois altérations refusées ([`m1b-coherence-refus.log`](m1b-coherence-refus.log)).

**Portée prévue.** Si tout tient, le prefetch refuse dans un pod un `repomd.xml` autre que celui fixé, un autre manifeste de base et une couche autre que celle du manifeste, chacun par sa garde et sans sortie écrite. Ce n'est pas mesuré dans un TaskRun.

### Correction datée du 19/11/2026, écrite à 15:50:41 UTC : premier passage des cas du prefetch arrêté au chargement

- **Ce qui s'est passé.** Le premier passage, lancé après le commit `3626d98`, s'est arrêté à la première ligne : `commun.sh` attend la variable `here`, qui donne le répertoire de l'appelant, et le script ne la posait pas. Il est gardé dans [`m1b-refus-prefetch-1.log`](m1b-refus-prefetch-1.log), une seule ligne, sans en-tête daté. Rien n'a été créé : 0 pod `m1brp-` dans `builds` et aucun dossier de travail `m1brp`, relevés juste après.
- **Correction** : `here` est posé avant le chargement, sur le répertoire de la brique 08, comme le font les scripts de la 05. Rien d'autre ne change. Le script corrigé a le sha256 `cb8a758bfb905f7e…`.
- **Relance** : le passage complet est rejoué dans un journal neuf, `m1b-refus-prefetch.log`. Les prédictions PX1 à PX5 ne changent pas.

### Correction datée du 19/11/2026, écrite à 15:51:31 UTC : deuxième passage des cas du prefetch arrêté avant le premier pod

- **Ce qui s'est passé.** Le deuxième passage, du 19/11 à 15:50:47 UTC, à HEAD `9990c3d`, est gardé dans [`m1b-refus-prefetch-2.log`](m1b-refus-prefetch-2.log). La relecture du sélecteur de `prefetch-rpm-sortie` et du script a passé. Puis le rendu du premier pod s'est arrêté : `yq` lisait les ressources dans le gabarit `builders/prefetch-racine-rpm.yaml`, dont le marqueur `@AMORCE@` n'est pas du YAML valide. C'est le même défaut que lors de la clôture de la 06. Aucun pod n'a été créé (0 pod `m1brp` dans `builds`, relevé juste après). Le dossier de travail `m1brp-05` a été créé, avec un pod rendu non valide.
- **Correction** : les ressources sont lues dans la tâche rendue sous `m1bt3` (`prefetch-racine-rpm.yaml`, sans marqueur), celle d'où vient `script-pb.sh`. Le préfixe peut être posé par `PREFIXE`. Rien d'autre ne change. Le script corrigé a le sha256 `80f627643ce52606…`.
- **Relance** : sous le préfixe `m1brp2`, puisque `m1brp-05` existe, dans un journal neuf, `m1b-refus-prefetch.log`. PX5 se lit donc pour le préfixe `m1brp2-`. Les autres prédictions ne changent pas.

### Cas refusés du prefetch : résultat (note écrite le 19/11/2026 à 15:54:36 UTC)

Journal : [`m1b-refus-prefetch.log`](m1b-refus-prefetch.log), de 15:51:32 à 15:54:05 UTC, à HEAD `19808d4`, sous le préfixe `m1brp2`, code 0, 0 KO. Les deux premiers passages, arrêtés avant tout pod, sont gardés en `-1.log` et `-2.log` (corrections datées ci-dessus).

**PX1 à PX5 tenues.**
- **PX1** : le témoin rend 0, `BASE_ARTIFACT_INPUTS` vaut `ee90dc0e…`, `couche.tar.gz` est écrite, et l'arbre a la liste `7af63de7…`, celle de `m1bt3`.
- **PX2** : avec le `repomd.xml` de `baseos97` fixé à `abac8b17…`, le prefetch s'arrête sur « baseos97 : repomd.xml différent du sha256 fixé », avant les métadonnées et les rpm.
- **PX3** : avec le manifeste `ed654c69…` et la couche fixée `812c4412…`, le manifeste est lu et passe son contrôle de sha256. Le prefetch s'arrête ensuite sur la garde du manifeste, avec `AssertionError: ['sha256:99c753a8…']`, la couche lue dans ce manifeste.
- **PX4** : avec le bon manifeste et une couche fausse, même garde, avec `AssertionError: ['sha256:812c4412…']`.
- Dans les trois refus : code 1, une seule ligne `KO`, ni `BASE_ARTIFACT_INPUTS` ni `couche.tar.gz`.
- **PX5** : les quatre pods sont retirés, et il ne reste aucun pod au préfixe `m1brp2-`.

**Portée.** Dans un pod runc du cluster, le prefetch refuse un `repomd.xml` autre que celui fixé, un autre manifeste de base, et une couche autre que celle du manifeste. Chaque refus vient de sa garde, sans sortie écrite. Avec RZ1 à RZ8 et AN1, les cas refusés demandés avant signature sont joués. Rien n'est mesuré dans un TaskRun.

### Correction datée du 19/11/2026, écrite à 15:59:32 UTC : date de l'amorce

- **Erreur.** La note de résultat de CA1 à CA5 dit : « Ce retard vient de l'image `rockylinux:9.8` du 27/01/2026 ». Le 27/01/2026 est la date de build du paquet `curl-minimal`, pas celle de l'image. La config de l'amorce (`686e4558…`, lue à la main à 15:56 UTC dans le cache OCI local) porte `created` 2026-05-25T20:19:03Z. Une autre trace la contredisait déjà : la même amorce porte `python3-dnf-4.14.0-34.el9_8.rocky.0.1`, que la ligne de dnf de docs/04 dit construit le 19/05/2026.
- **Lecture corrigée** : l'image du 25/05/2026 porte un `curl-minimal` construit le 27/01/2026. La date de l'image est relevée par le script ci-dessous (FR1). Le passage de docs/04 est reformulé dans le même commit.
- **Portée du constat** : seul curl a été relu. Toute l'amorce est figée par digest (D4 a), y compris les bibliothèques que curl charge face au réseau (TLS, glibc) et ce que `construire` exécute en root dans Kata (rpm, dnf, python). Le point ouvert s'appelle donc « fraîcheur de l'amorce (D4 a) », pas « curl ».

## Fraîcheur de l'amorce : prédictions écrites le 19/11/2026 à 15:59:32 UTC, avant le lancement

**Relevé** : [`m1b-amorce-fraicheur.sh`](m1b-amorce-fraicheur.sh) (sha256 `8edd98347dfa2be8…`), journal à venir `m1b-amorce-fraicheur.log`. Hors ligne.
- Il relit les paquets installés de l'amorce dans une racine extraite à neuf.
- Il les compare au plus récent de chaque nom dans les `primary` de BaseOS et AppStream 9.8 des bancs du 18/11. Ce sont les `repomd.xml` `abac8b17…` et `a3ca4230…`, que fixe la pipeline de l'outillage, avec `primary` et `updateinfo` contrôlés contre `repomd.xml`. La comparaison se fait par `rpm.labelCompare` de l'amorce.
- Il compte, par gravité, les errata de sécurité dont une version est plus récente qu'un paquet installé.
- Il détaille une liste fixée de paquets exposés au réseau ou exécutés en root.

- **FR1** (haute) : la config de l'amorce porte `created` 2026-05-25T20:19:03Z, avec une seule couche, `99c753a8…`.
- **FR2** (haute) : `primary` et `updateinfo` des deux dépôts sont conformes à leur `repomd.xml`.
- **FR3** (haute pour curl, sans pari pour le reste) : `curl-minimal` et `libcurl-minimal` sont en retard, et leur plus récent est `7.76.1-40.el9_8.9`, comme dans CA4. Le nombre total de paquets en retard est relevé sans pari.
- **FR4** (sans pari) : le nombre d'errata de sécurité plus récents que les paquets installés, leurs gravités, et le détail des paquets exposés.

**Lecture prévue.** Comme pour curl, un erratum plus récent ne prouve pas que le code exécuté est touché. Le relevé chiffre le retard de l'amorce ; il ne juge pas son exposition. Le choix entre amorce figée et amorce rafraîchie te revient avant `SIGNER=1`. Rafraîchir l'amorce changerait la racine de l'outillage et du bootstrap, donc les cibles `7c07083c…` et `b063feb3…`, et referait la mesure d'un autre jour.

### Fraîcheur de l'amorce : résultat (note écrite le 19/11/2026 à 16:00:25 UTC)

Journal : [`m1b-amorce-fraicheur.log`](m1b-amorce-fraicheur.log), de 15:59:33 à 15:59:43 UTC, à HEAD `f41d4a9`, code 0.

**FR1 à FR3 tenues ; FR4 lue.**
- **FR1** : la config `686e4558…` porte `created` 2026-05-25T20:19:03Z, avec une seule couche, `99c753a8…`.
- **FR2** : `primary` et `updateinfo` de BaseOS et AppStream 9.8 sont conformes à leur `repomd.xml`.
- **FR3** : `curl-minimal` et `libcurl-minimal` sont en retard sur `7.76.1-40.el9_8.9`. Sur 146 paquets installés (hors `gpg-pubkey`), tous présents dans 9.8, **44 sont en retard**.
- **FR4** (lecture) : 54 errata de sécurité de Rocky portent une version plus récente qu'un paquet installé, dont **1 « Critical », 22 « Important »**, 28 « Moderate » et 3 « Low ». Ils touchent 36 paquets.
  - **Paquets en retard, exposés au réseau** :
    - `ca-certificates`, avec l'erratum « Critical » `RLSA-2026:88459` ;
    - `openssl-libs` 3.5.5 contre 3.5.8, 4 errata dont 3 « Important » ;
    - `gnutls`, 1 « Important » ;
    - `glibc`, 5 « Moderate » ;
    - `libnghttp2`, 1 « Moderate » ;
    - curl, 4 errata dont 2 « Important » ;
    - `python3` et `python3-libs`, 3 « Important ».
  - **Paquets en retard, exécutés en root dans Kata** : `tar` et `libsolv`, 1 « Moderate » chacun.
  - **À jour** : `rpm`, `dnf`, `python3-dnf`, `libdnf`, `librepo`, `gnupg2`, `gpgme`, `zlib`.

**Lecture.**
- L'amorce, image du 25/05/2026 figée par digest (D4 a), n'a pas les correctifs que Rocky 9.8 a publiés depuis. Ce retard touche le pod de prefetch, qui parle au réseau en TLS, et le pod de construction, qui exécute python, tar et libsolv en root dans Kata, sans réseau.
- **Ce retard n'atteint pas le contenu des images construites.** L'outillage et le bootstrap sont installés depuis le miroir 9.8 fixé par la pipeline, avec ses révisions à jour, `curl-7.76.1-40.el9_8.9` par exemple. L'amorce ne fournit que les outils qui installent et archivent.
- Les contre-contrôles sont ceux de CA5 : sha256 fixés, signatures, pods sans secret, prefetch en runc et `restricted`, construction sans réseau. Un erratum plus récent ne prouve pas que le code exécuté est touché.
- **Choix avant `SIGNER=1`, qui te revient** :
  - **(a)** garder l'amorce figée, en réserve mesurée ;
  - **(b)** rafraîchir l'outillage des tâches, par une image dérivée construite sans réseau, ou par une amorce plus récente. Cela change les outils qui installent, donc peut-être les racines `7c07083c…` et `b063feb3…`, et referait la mesure d'un autre jour.

  Rien ne change avant la mesure du 20/11.

### Correction datée du 19/11/2026, écrite à 16:01:11 UTC : lanceur de la mesure d'un autre jour, préfixes réglables et répétition

- **Pourquoi.** Seuls le garde-date et le bilan du lanceur avaient été essayés ; le chemin `lancer` n'avait jamais tourné. Trois des scripts du jour ont échoué à leur premier passage. Et les préfixes à tiret (`m1b-20`, `m1bt-20`) sont neufs pour `m1b.sh` et `m1b-builders.sh`. Enfin, une relance après échec aurait demandé d'éditer le lanceur, dont le sha256 est cité dans JK et JT.
- **Changement** : les préfixes sont réglables par `PREFIXE_ANCIENNE` et `PREFIXE_TACHE`, avec pour défauts `m1b-20` et `m1bt-20`, ceux de JK et JT. Les journaux suivent le préfixe. `REPETITION=1` ne joue que les deux `prealables` (hôte et admission à blanc, aucun pod), sans le garde-date. Sans ces variables, le lanceur fait exactement ce que décrivaient JK et JT ; il refuse toujours de partir avant le 20/11 (essayé à 16:00:48 UTC : code 2). Le nouveau sha256 est `a4217d92d23680fa…` ; JK et JT ne changent pas.
- **Répétition** : sous `m1b-r1` et `m1bt-r1`, journal du lanceur `m1b-jour-kata-repetition.log`.
  - **LR1** (haute) : les deux `prealables` rendent 0 sous ces préfixes à tiret, et le lanceur s'arrête après eux, sur sa ligne de fin de répétition.
  - **LR2** (haute) : `m1b-builders.sh prealables` rend les mêmes quatre scripts que `m1bt3` (sha256 de JT1).

**LR1 et LR2 tenues** (note écrite le 19/11/2026 à 16:01:37 UTC) : [`m1b-jour-kata-repetition.log`](m1b-jour-kata-repetition.log), de 16:01:12 à 16:01:18 UTC, à HEAD `85f4365`, code 0. Sous `m1b-r1`, `prealables` rend 0 ([`m1b-r1-prealables.log`](m1b-r1-prealables.log)). Sous `m1bt-r1`, il rend 0 et donne les quatre scripts de JT1 ([`m1b-builders-m1bt-r1-prealables.log`](m1b-builders-m1bt-r1-prealables.log)). Le lanceur s'arrête sur sa ligne de fin de répétition. Aucun pod n'est créé. **Commande pour le 20/11, à partir de 00:00 UTC** (racine du dépôt) : `bash poc/bricks/05-rpm-mock/resultats/m1b-jour-kata.sh < /dev/null > poc/bricks/05-rpm-mock/resultats/m1b-jour-kata.log 2>&1`.

## Validation des tâches et pipelines par Tekton : prédictions écrites le 19/11/2026 à 16:10:43 UTC, avant le lancement

**Script** : [`m1b-taches-admission.sh`](m1b-taches-admission.sh) (sha256 `f6d7617692e936fb…`), journal à venir `m1b-taches-admission.log`. C'est le point « `--dry-run=server` par Tekton » de la carte : l'admission à blanc de `prealables` ne porte que sur les pods d'essai, jamais sur les objets Tekton. Le script passe les deux tâches et les deux pipelines rendues sous `m1bt3` en `kubectl create --dry-run=server` dans `builds`, comme `m4b-taches-admission`. Rien n'est créé et aucun fichier n'est écrit ; seul le nombre de lignes du motif de refus est relevé, jamais son texte.

- **TD1** (haute) : les quatre rendus sont ceux de `m1bt3`, écrits à 15:14 UTC (sha256 `b0fdff38…`, `de77ba0a…`, `13836c38…`, `b2443188…`).
- **TD2** (haute) : `prefetch-racine-rpm` et `construire-racine-rpm`, en `tekton.dev/v1beta1`, sont admises (code 0, aucun motif). Leurs noms de paramètres à tiret bas (`cle_sup`, `dnf_conf`, `dnf_conf_sha256`) et le champ `resources` du pas n'ont jamais été vus par le webhook. Tekton autorise le tiret bas dans un nom de paramètre, et M4b a mesuré que `resources` est le nom admis en v1beta1.
- **TD3** (haute) : `builder-mock-rocky9` et `builder-rocky9-bootstrap` sont admises (code 0). Leurs références de bundle portent un digest factice (zéros) : le webhook valide la forme, pas la résolution, comme pour la pipeline factice de M4b.
- **TD4** : deux témoins, pour vérifier que le passage contrôle bien quelque chose.
  - **Témoin de tâche** (haute) : `construire-racine-rpm` avec `computeResources` à la place de `resources` dans le pas est refusée, avec une ligne du motif « strict decoding error: unknown field », comme le témoin mesuré le 18/11.
  - **Témoin de pipeline** (moyenne) : `pipeline-b` avec un champ inconnu dans sa première tâche est refusée par le même motif. Le décodage strict n'a été mesuré que sur une tâche.
- **TD5** (haute) : les noms des tâches et pipelines de `builds` sont les mêmes avant et après.

**Lecture prévue.** Si TD1 à TD5 tiennent, le point « `--dry-run=server` » est fait pour les rendus de `m1bt3`. La mesure du 20/11 rendra de nouveau ces quatre objets sous `m1bt-20`. JT1 veut les mêmes scripts ; les objets entiers ne sont pas comparés, et la validation ne vaudra donc pour eux que si leurs sha256 sont égaux à ceux de TD1. Un refus de TD2 ou TD3 changerait le gabarit, donc les scripts rendus, et la mesure du 20/11 serait à repréparer.

### Validation par Tekton : résultat (note écrite le 19/11/2026 à 16:11:17 UTC)

Journal : [`m1b-taches-admission.log`](m1b-taches-admission.log), de 16:10:52 à 16:10:53 UTC, à HEAD `b191330`, code 0, 0 KO. **TD1 à TD5 tenues.**
- **TD1** : les quatre rendus sont ceux de `m1bt3`.
- **TD2 et TD3** : les deux tâches (5 et 13 paramètres) et les deux pipelines (3 tâches chacune) sont admises par le webhook de Tekton (`sha256:61ef794b055f…`), sans motif de refus. Les paramètres à tiret bas et le champ `resources` passent.
- **TD4** : les deux témoins sont refusés (code 1), chacun avec une ligne du motif de décodage strict. Le témoin de pipeline, de confiance moyenne, tient aussi : le décodage strict porte sur les pipelines comme sur les tâches.
- **TD5** : `builds` n'avait aucune tâche ni pipeline avant le passage, et n'en a toujours aucune.

**Portée.** La validation vaut pour les rendus de `m1bt3`. Elle vaudra pour ceux de `m1bt-20` si leurs sha256 sont égaux à ceux de TD1. Elle ne dit rien de la résolution des bundles, ni de la vérification des signatures, ni de l'exécution par le contrôleur : ces trois points viennent avec `SIGNER=1` et les PipelineRuns.
