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
