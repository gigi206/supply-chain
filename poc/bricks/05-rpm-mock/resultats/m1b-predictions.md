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
