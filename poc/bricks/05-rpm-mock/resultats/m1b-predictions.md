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
