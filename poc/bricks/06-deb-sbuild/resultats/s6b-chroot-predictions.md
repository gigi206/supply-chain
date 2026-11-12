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

## Résultats (12/11/2026, accord « Oui, lance les deux »)

### `trousseau` : 10:24:58 UTC, code 0, `bilan : tout OK`

Journal : `s6b-trousseau.log`.

| # | Résultat | Mesure |
|---|---|---|
| K1 | **Tenue** | `debian-archive-keyring` `ii 2025.1`. **`debian-archive-keyring.gpg` est un lien symbolique** (26 octets) vers `debian-archive-keyring.pgp`, un fichier de 55 918 octets ; les deux donnent le sha256 `506b815c…`. Le paquet fournit chaque trousseau en `.pgp` et en `.gpg`, dont `debian-archive-removed-keys`. `dpkg -V` : aucune ligne. |
| K2 | **Tenue** | InRelease : sha256 de S1. `sqv -n 3` avec le `.gpg` : code 0, et les trois signataires de S1. |

**L'écart relevé après `sqv` est levé** : le fichier qu'apt nomme et celui que le témoin `sqv` a lu sont le même fichier.

### `chroot` : 10:25:03 à 10:26:08 UTC, code 0, `bilan : tout OK`

Journal : `s6b-chroot.log`, 123 lignes. Lancé en arrière-plan sur l'hôte. Aucune ligne `jeton|token`.

| # | Résultat | Mesure |
|---|---|---|
| Réf. | **Tenue** | La copie du chroot de la plateforme a le sha256 `aec1c7a9…`. Ses listes, calculées par l'étape : 122 paquets installés (`74c3eded…`), 12 515 noms (`49f3aa9a…`), détail `20d2f4b7…`. GNU tar 1.35 sur l'hôte comme dans la VM. |
| Modes | **Tenue** | `/home/replay` est en **700**, ce qui justifie la correction du dossier temporaire. `/home/replay/s6b` 755 root, `/var/tmp` 1777, `/var/tmp/s6b-mm` 755 root. Aucune ligne « unsandboxed » ni `_apt`. |
| C0 | **Tenue** | mmdebstrap 1.5.7, code 0, « success in 52.4743 seconds ». Le journal de mmdebstrap (80 lignes) n'a **aucune ligne `W:` ni `E:`**. |
| C1 | **Tenue** | **63 `.deb`** dans le cache au moment des crochets, comme S2, **tous dans `builder/paquets.txt` par leur sha256** |
| C2 | **Tenue** | **451 786 240 octets, sha256 `aec1c7a9…` : identique, octet pour octet, au chroot de la plateforme.** La liste des noms (12 515 entrées) et la liste détaillée (modes, propriétaires, tailles, dates) sont identiques aussi. |
| C3 | **Tenue** | 122 paquets installés, tous dans `builder/paquets.txt`, **identiques à ceux du chroot de la plateforme**, noms et versions |
| C4 | **Tenue** | Le trousseau du témoin est `debian-archive-removed-keys.gpg`. Code 25. apt : « Sub-process /usr/bin/sqv returned an error code (1) … Missing key 4CB50190207B4758A3F73A796ED0E7B82643E131 … Missing key B8E5F13176D2A7A75220028078DBA3BC47EF2265 », puis « The repository … is not signed », puis « mmdebstrap failed to run ». |
| Effets | **Tenus** | Restent dans `/home/replay/s6b` : `trixie-amd64.tar`, `mm-chroot.log`, `mm-temoin.log`, `noms.txt`, `detail.txt` et `installes.txt`. Le dossier temporaire et l'archive du témoin sont supprimés. Le disque libre passe de 13 363 à 12 930 Mo. Aucune écriture dans le cluster ni dans Zot. |

**Un fait mesuré au passage** : C4 montre qu'**apt vérifie l'InRelease avec `/usr/bin/sqv`**, et qu'il refuse quand le trousseau donné par `signed-by` n'a pas les clés. L'étape `sqv` l'avait seulement déduit. Les empreintes de clés manquantes ne sont pas celles des clés primaires de S1, et je n'ai pas relevé à quelles clés elles appartiennent : des sous-clés de signature, probablement.

**Erreur dans mes valeurs de référence d'avant le lancement** (note datée de 10:19:14) : `0ba5075e…` pour les paquets installés et `35fe9780…` pour le détail ont été calculés **sans `LC_ALL=C`**, dans la locale `fr_FR.UTF-8` de mon shell. La locale change l'ordre de `sort` et l'affichage de `tar -tv`. Recalculées avec `LC_ALL=C`, comme dans l'étape, elles donnent `74c3eded…` et `20d2f4b7…`, les valeurs de l'étape. L'hôte et la VM ont tous deux tourné avec `LC_ALL=C`, et la comparaison de l'étape est donc valable. La liste des noms, qui n'est pas triée, a le même sha256 dans les deux locales.

**Conséquences**
- **Le chroot de l'image de build `749d746c` est reproduit dans le domaine**, indépendamment de la plateforme. Les octets viennent de l'instantané, et ils sont vérifiés par `sqv` avec le trousseau de la VM. Ce sont les mêmes octets que ceux de la plateforme, construits le 10/11 dans un pod Kata depuis un miroir `file://`.
- **C'est la première reproduction du chroot d'un jour à l'autre et d'un environnement à l'autre.**
- Pour sbuild, le chroot est à `/home/replay/s6b/trixie-amd64.tar`, au compte `replay`.
- **La suite** : transporter la fermeture deb `bb7599a2`, les sources et le packaging, lancer sbuild lien coupé, puis comparer le deb à `0b489d43`.

