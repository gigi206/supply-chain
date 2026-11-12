# Brique 06, S6b : trousseau et chroot dans `sc-replay`, prédictions (12/11/2026, préparées à partir de 10:08:24 UTC, avant toute mesure)

Préparées après « Oui, prépare-les ». L'heure est celle du `date -u` du début de la préparation ; l'heure du commit fait foi.

**Rien n'est lancé.** Les deux étapes nouvelles de [`s6b.sh`](../s6b.sh) attendent chacune un **accord nommé**, dans cet ordre :

```
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh trousseau
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh chroot
```

Journaux : `s6b-trousseau.log` et `s6b-chroot.log`.

## Étape `trousseau` : le `.gpg` nommé par apt

L'étape `sqv` a lu `debian-archive-keyring.pgp`, alors qu'apt nomme `debian-archive-keyring.gpg` dans `Signed-By`. Je ne sais pas si ce sont les mêmes octets. L'étape tourne dans la VM seule, sans sudo, et n'installe rien.

- **K1** : pour les deux fichiers, le type, la cible, la taille et le sha256 ; les fichiers de `/usr/share/keyrings/` du paquet ; `dpkg -V debian-archive-keyring`.
- **K2** : `sqv -n 3` avec le `.gpg` sur l'InRelease. Les empreintes de sa sortie sont comparées aux trois de S1.

**Prédictions**
- **K1.** Les deux fichiers existent ; je ne prédis pas si l'un est un lien vers l'autre. `dpkg -V` ne donne aucune ligne : confiance haute, rien ne les a modifiés depuis l'installation.
- **K2.** Code 0, avec les trois signataires de S1. Confiance moyenne-haute : apt a mis ses listes à jour avec ce fichier.

## Étape `chroot` : mmdebstrap depuis l'instantané (décision 2, voie A)

Le chroot est construit **avec les options du chroot de la plateforme** : fonction `mm` de [`builder/construire-builder.yaml`](../builder/construire-builder.yaml), `--mode=root`, variante `buildd`, `SOURCE_DATE_EPOCH=1789199741`. Les crochets sont les mêmes : `etc/hostname` à « sbuild », `etc/resolv.conf` vidé, `etc/apt/sources.list` réécrit à la ligne de l'instantané.

**Écarts voulus avec la plateforme**
- La source est l'instantané en http, et non un miroir `file://`. Il n'y a donc ni crochet `file-mirror-automount` ni `rmdir` de son point de montage.
- `signed-by` désigne explicitement le trousseau `.gpg` de la VM : c'est lui qui vérifie l'InRelease, et pas les clés que mmdebstrap copierait de l'hôte.
- Un crochet en plus **ne fait que lire** le cache d'apt, comme dans `s2.sh` : il écrit le sha256 de chaque `.deb` téléchargé.

L'étape tourne avec sudo dans la VM, lien ouvert. Elle n'écrit que sous `/home/replay/s6b`, avec des chemins littéraux dans les `rm`. Le chroot y reste (`trixie-amd64.tar`) pour sbuild.

**Contrôles sur l'hôte, hors réseau**
- Le chroot de la plateforme est sur l'hôte : la copie de la comparaison de S4a fait 451 786 240 octets, sha256 `aec1c7a9…`.
- La lecture de `var/lib/dpkg/status` et la comparaison de l'étape y trouvent **122 paquets installés, tous dans `builder/paquets.txt`**, aux mêmes noms et versions.
- Son `sources.list` est la ligne de l'instantané. Il n'y reste ni listes d'apt ni `.deb`, et aucune trace du miroir `file://`.
- `bash -n` et `shellcheck -S warning` ne signalent rien.

**Prédictions**
- **C0.** mmdebstrap 1.5.7, code 0, en moins de 5 min. Confiance moyenne pour la durée : S2 a mis 54 s depuis l'instantané, mais depuis un pod, et snapshot.debian.org limite parfois son débit. Aucune ligne `E:`.
- **C1.** Environ 63 `.deb` dans le cache au moment des crochets, comme S2 (mêmes options et même instantané), **tous dans `builder/paquets.txt` par leur sha256**. Confiance haute pour l'appartenance : même InRelease, donc mêmes Packages et mêmes sha256. Confiance moyenne pour le nombre.
- **C2.** **Chroot identique à celui de la plateforme** : 451 786 240 octets, sha256 `aec1c7a9…`. Confiance moyenne.
  - Ce qui l'appuie :
    - S2 a reproduit son chroot octet pour octet depuis l'instantané ;
    - mmdebstrap fixe les dates par `SOURCE_DATE_EPOCH` ;
    - l'archive de la plateforme ne garde trace ni du miroir ni des listes.
  - Ce qui pourrait l'empêcher : l'écart de source, `file://` ou http ; le noyau et l'environnement d'un pod Kata face à ceux de la VM ; un fichier écrit par le crochet `file-mirror-automount` que je n'ai pas vu.
  - Un écart serait consigné tel quel. Le diagnostic comparerait la liste des deux archives, et la reproduction du deb `0b489d43` resterait le critère du contrôle 6.
- **C3.** 122 paquets installés, tous dans `builder/paquets.txt`. Confiance haute.
- **C4.** Le témoin négatif est refusé, avec un message de signature (`NO_PUBKEY`, « not signed » ou équivalent). Confiance moyenne : je ne sais pas si le paquet fournit un trousseau de clés retirées ; à défaut, c'est un fichier vide.
- **Effets.**
  - Dans `/home/replay/s6b` restent `trixie-amd64.tar`, `mm-chroot.log` et `mm-temoin.log`, au compte `replay`.
  - Le dossier temporaire et l'archive du témoin sont supprimés.
  - Le disque libre baisse d'environ 0,5 Go.
  - Aucune écriture dans le cluster ni dans Zot.

## Hors de ces étapes

- Le transport de la fermeture deb `bb7599a2`, des sources et du packaging.
- sbuild lien coupé, puis la comparaison du deb à `0b489d43`.
- Le layout à `039949f9`, puis la VSA sur `454728c5` après le 12/11, 21:03:37 UTC.

## Note datée du 12/11/2026 (rédigée à partir de 10:19:14 UTC, après relecture du conseiller), avant tout lancement

Les prédictions ci-dessus ont été commitées dans `b8ae77e`, à 10:13:10 UTC. L'étape `chroot` est corrigée avant tout lancement ; `trousseau` est inchangée.

1. **Diagnostic de C2 préparé.** Un écart de C2 aurait seulement dit « DIFFÉRENT ». L'étape tire maintenant sur l'hôte, de la copie du chroot de la plateforme, sa liste des noms et sa liste détaillée (`TZ=UTC tar --numeric-owner --full-time -tvf`), après en avoir revérifié le sha256. La VM calcule les mêmes listes sur son chroot, les compare, et les garde sous `/home/replay/s6b`. Les listes de référence restent sur l'hôte, sous `~/.cache/supply-chain-poc/06/s6b/ref`.
2. **C3 exige l'égalité** avec les 122 paquets installés du chroot de la plateforme, et non plus la seule appartenance aux 199 de `builder/paquets.txt`.
3. **C4** : le motif ne contient plus « keyring », que le chemin du témoin contient aussi. La fin du journal du témoin est toujours affichée.
4. **Nettoyage** : le `rm -rf` du `trap` passe en `--one-file-system`, puisqu'il tourne en root sur un dossier où mmdebstrap monte `/proc` et `/sys`. Le nettoyage se fait aussi avant la ligne « gardés dans la VM ».
5. **Dossier temporaire de mmdebstrap sous `/var/tmp/s6b-mm`.** Si `/home/replay` était en 0700, le compte `_apt` ne pourrait pas y descendre, et apt téléchargerait en root avec des avertissements. Les modes des dossiers sont journalisés. Le chroot final reste sous `/home/replay/s6b`.

**Valeurs de référence**, calculées sur l'hôte avec GNU tar 1.35 et la commande même de l'étape :

| Liste | Lignes | sha256 (début) |
|---|---|---|
| paquets installés | 122 | `0ba5075e…` |
| noms | 12 515 | `49f3aa9a…` |
| détail | 12 515 | `35fe9780…` |

Les dates de l'archive ne sont pas toutes ramenées à `SOURCE_DATE_EPOCH` : 2 582 entrées sont du 29/08/2026, 2 421 du 30/08, 1 360 du 12/09.

**Prédictions ajoutées ou révisées**
- **Modes** : je ne les prédis pas. Avec le dossier temporaire sous `/var/tmp`, aucune ligne « unsandboxed » ou `_apt` dans le journal de mmdebstrap. Confiance moyenne.
- **C2**, comparaison des listes : si les archives sont identiques, les deux listes le sont aussi. Si C2 diffère, je ne prédis pas laquelle des deux listes diffère.
  - Le détail dépend de la version de tar de la VM : elle est journalisée, et une différence de version rendrait la comparaison du détail non concluante.
  - **Révision de l'appui** : les deux chroots de S1 (`440ba93b`, 10/11 à 13:04 et 14:36 UTC) et les deux de S2 sont du même jour. Les deux exécutions de S4a sont du même soir. Aucune reproduction d'un jour à l'autre, ni d'un environnement à l'autre, n'est donc mesurée. C2 reste à confiance moyenne, avec cet appui plus faible.
- **C3** : égalité avec la liste de la plateforme (`0ba5075e…`), et 122 paquets. Confiance haute.

**Lancement** : en arrière-plan sur l'hôte, pour qu'une fin de délai de l'outil ne coupe pas ssh. Une coupure laisserait mmdebstrap tourner seul dans la VM, sans C1 à C4.

