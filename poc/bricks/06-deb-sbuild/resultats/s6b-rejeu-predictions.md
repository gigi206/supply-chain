# Brique 06, S6b : transport, vérification et reconstruction du deb dans `sc-replay`, prédictions (12/11/2026, rédigées à partir de 10:34:57 UTC, avant toute mesure)

Préparées après « Oui, prépare-les », sur le modèle de R3 et R4 de la brique 10. L'heure est celle du `date -u` du début de la rédaction ; l'heure du commit fait foi.

**Rien n'est lancé.** Quatre étapes nouvelles de [`s6b.sh`](../s6b.sh) attendent chacune un **accord nommé**, dans cet ordre :

```
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh transporter
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh verifier
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh repetition
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh rebuild
```

`rebuild` refuse de tourner avant le 12/11/2026 à 21:03:37 UTC : il faut 24 h après le `finishedOn` de la provenance `454728c5`, lu dans la provenance vérifiée. Les deux outils de la VM sont versionnés : [`rejeu/verifier_deb.py`](../rejeu/verifier_deb.py) et [`rejeu/rebuild_deb.sh`](../rejeu/rebuild_deb.sh).

## Ce que font les étapes

- **`transporter`**, sur l'hôte, avec un transport non fiable : la VM vérifie tout.
  - Copies anonymes par oras, dans un layout OCI : le layout du deb (`039949f9`), son tag `.att`, ses bundles horodatés, et les entrées de la provenance `454728c5`. Ces entrées sont lues sans vérification :
    - `construire-deb` et `preparer-deb` ;
    - `outils-prefetch`, pour sa version de Go ;
    - les deux fermetures et le packaging.
  - De l'image de build `749d746c`, **le manifeste seul** : le chroot est reconstruit dans le domaine.
  - Un bundle git de toutes les références de `workspace/sample-app`.
  - La clé de Chains et la chaîne de la TSA de la 08, celles qu'utilise `s4d2.sh`.
  - `verifier_deb.py`.
  - Le tout est copié dans `/home/replay/s6b/r3`, vidé d'abord.
- **`verifier`**, dans la VM, par `verifier_deb.py` :
  - bundles horodatés vérifiés hors réseau, provenance `454728c5` extraite d'un bundle vérifié ;
  - section 1 de la politique ;
  - digests des huit entrées ;
  - présence du commit déclaré ;
  - **15 lignes clés des recettes** de `preparer-deb` et de `construire-deb`, lues dans leurs bundles vérifiés ;
  - version de Go d'`outils-prefetch`, comparée à la toolchain du domaine ;
  - **le chroot du domaine, rangé comme dans l'image de build, comparé à la couche du chroot de `749d746c`**. Cette comparaison rattache le chroot reconstruit à l'image que nomme la provenance vérifiée.
- **`repetition`** : lien établi, non comptée, comme la répétition de R4. C'est une copie de `rebuild_deb.sh` sans l'attente de 20 s ni le refus de porteuse.
- **`rebuild`** : lien coupé, comme R4.
  - `rebuild_deb.sh` est lancé détaché, sous le compte `replay`, puis l'interface est coupée (`virsh domif-setlink down`). Elle reste coupée 1 200 s, et les compteurs sont relus après la coupure et avant le rétablissement.
  - Le script revérifie les entrées contre la provenance, et le chroot contre `verifie.txt`.
  - Il refait la préparation de `preparer-deb` : sources du commit, confrontation au verrou, `vendor/` par Go hors ligne, marked, `debian/`. Puis la construction de `construire-deb` : paquet source, **la commande sbuild de la recette**, layout fait main.
  - **Critère** : le digest du manifeste reconstruit est égal au sujet de la provenance, `039949f9`.

**Écarts voulus avec la plateforme**
- Il n'y a aucun pod. Les entrées sont lues dans le layout et le bundle git transportés, et le travail se fait sur disque.
- Le refus de porteuse et les compteurs de l'interface remplacent les témoins réseau.
- Le chroot est `/home/replay/s6b/trixie-amd64.tar`, et non `/opt/sbuild/…`.
- Go 1.26.10 est celui de go.dev, installé par la 10.

## Contrôles faits sur l'hôte, hors réseau

- **Lecture des entrées** : appliquée aux huit couches du tag `.att` gardées par le relevé H1, elle donne, pour `454728c5`, exactement sept entrées OCI, chacune une fois, aux digests du relevé.
- **Lignes clés de la recette** : les 15 se trouvent dans `deb/preparer-deb.signee.yaml` et `deb/construire-deb.signee.yaml`, après retrait de l'indentation.
- **Rangement du chroot** : appliqué à la copie du chroot de la plateforme, il redonne **la couche `1029232e…` de l'image de build** (451 788 800 octets), à une condition : `opt/` et `opt/sbuild/` doivent être en 0755. Avec mon umask de 002, il donnait `f266479e…`. Les modes sont donc fixés explicitement dans `verifier_deb.py`.
- `bash -n`, `shellcheck -S warning` et l'analyse Python ne signalent rien.

## Prédictions

**`transporter`**
- **T1.** Huit bundles horodatés, puisque S4d3 a trouvé l'horodatage complet sur 8 enveloppes. Confiance moyenne-haute.
- **T2.** Sept entrées copiées, plus le manifeste de `749d746c`.
- **T3.** Archive de quelques centaines de Mo : la fermeture deb fait 216 Mio, et je ne connais pas la taille d'`outils-prefetch`.
- Code 0 ; aucune écriture dans Zot ni dans le cluster.

**`verifier`**
- **V1.** Racine de la TSA construite. Digest du sujet `039949f9`.
- **V2.** Huit bundles vérifiés sur huit, et provenance `454728c5` extraite. Confiance moyenne-haute : S4d a vérifié ces provenances avec la même clé.
- **V3.** Section 1 tenue ; huit entrées déclarées, une fois chacune ; digests transportés égaux.
- **V4.** Commit `6391fd43…` présent ; je prédis que `main` le désigne. Confiance moyenne.
- **V5.** Les 15 lignes clés sont trouvées. Confiance moyenne-haute : le test portait sur le YAML signé, et le bundle stocke la tâche en JSON.
- **V6.** `go1.26.10` des deux côtés. Confiance moyenne : la version d'`outils-prefetch` ne vient que d'un commentaire de `preparer-deb.yaml`.
- **V7.** **Couche du chroot du domaine égale à `1029232e…`**. Confiance haute : C2 a montré le chroot identique, et le rangement est vérifié sur l'hôte.
- **V8.** `finishedOn` `2026-11-11T21:03:37Z`.
- **V0.** Code 0, `bilan : 0 KO`.

**`repetition`** (lien établi, non comptée)
- **P1.** Entrées, chroot et verrou `OK` ; `vendor/` et marked reconstitués.
- **P2.** sbuild : code 0, en moins de 10 min, sans aucune ligne apt en http(s).
- **P3.** **Deb `0b489d43…` (1 952 080 octets), couche `12dd5c42…` (1 955 840 octets), manifeste `039949f9…` : `verdict=PASSED`.** Confiance moyenne-haute.
  - Ce qui l'appuie : chroot, fermeture, sources et commande sbuild identiques. Le deb a déjà été reproduit en S1, S3 et S4d, dans des pods différents. H2 a montré que le layout se déduit du deb seul.
  - Les risques : le compte (`replay` ici, UID 1000 dans le pod), le noyau, et un chemin de travail qui fuirait dans le deb.
- **P4.** Je ne prédis pas les sha256 du paquet source. Ils ne jouent pas sur le deb, que sbuild construit dans le chroot.

**`rebuild`**
- **R0.** Refus avant le 12/11/2026 à 21:03:37 UTC.
- **R1.** Après cette heure : `porteuse_*=0` dans la VM. Sortie de la VM inchangée pendant la coupure, côté hôte et côté invité.
- **R2.** Mêmes résultats que la répétition, `verdict=PASSED`.
- **R3.** Fin avant le rétablissement du lien.

## Hors de ces étapes

La VSA de `039949f9` sur `454728c5` (`vsa.py` adapté), signée dans la VM et non poussée avant S5b (ordre c).

## Note datée du 12/11/2026 (rédigée à partir de 10:40:48 UTC, après relecture du conseiller), avant tout lancement

Les prédictions ci-dessus ont été commitées dans `b50b6ad`, à 10:35:18 UTC. Quatre défauts sont corrigés avant tout lancement :
1. **Nettoyage de `~/s6b/r4` en root.** `go mod vendor` laisse des modules en lecture seule, et un sbuild interrompu laisserait des fichiers des subuid. `replay` ne pourrait pas les supprimer, et le second passage, `rebuild` après `repetition`, aurait échoué avant même de couper le lien. `transporter_r4` vide donc `/home/replay/s6b/r4` et `/var/tmp/s6b-r4` avec `sudo rm -rf --one-file-system`, en chemins littéraux. `rebuild_deb.sh` refuse de démarrer si `/var/tmp/s6b-r4` existe encore.
2. **Arbre de travail sous `/var/tmp/s6b-r4`** (0755), et non plus sous `/home/replay/s6b/r4`. Le code de sbuild 0.89.3 (`Sbuild/ChrootUnshare.pm`, lu dans la couche racine de l'image de build de S4a) le montre :
   - le chroot est créé sous `$TMPDIR`, puis touché par le root de l'espace de noms, c'est-à-dire le premier subuid ; si le chemin n'est pas traversable, il y a refus (« unable to access ») ;
   - `/home/replay` est en 700 (mesuré par l'étape `chroot`) ;
   - l'archive du chroot, elle, est lue par le compte lui-même, et reste sous `/home/replay/s6b`.

   Les modes de l'arbre sont journalisés (`arbre=`). Le journal et le résultat restent dans `~/s6b/r4`.
3. **Codes de sortie** : `repetition` rend 1 sans `verdict=PASSED`. `rebuild` rend 1 sans `verdict=PASSED`, si la VM a émis pendant la coupure, ou si le rebuild n'a pas fini avant le rétablissement.
4. **Version de Go d'`outils-prefetch`** : le vérificateur cherchait un chemin finissant par `go/VERSION`. Il accepte maintenant tout fichier `VERSION` dont la première ligne commence par `go1.`, et journalise son chemin. Un KO à cet endroit aurait fait refuser `rebuild_deb.sh` (`ko≠0`).

`rebuild` journalise aussi, avant la coupure, la commande qui rétablit le lien si le script est arrêté : `virsh -c qemu:///system domif-setlink sc-replay <interface> up`.

**Prédictions ajoutées**
- **P0.** `arbre=` : `/var/tmp` 1777 root, `/var/tmp/s6b-r4` 755 replay, l'arbre 755 replay. Aucun « unable to access » dans le journal de sbuild.
- **P5.** Le second passage, `rebuild` après `repetition`, ne bute pas sur le nettoyage. Le `sudo rm` de `transporter_r4` rend 0.
- **V6 révisée.** Un fichier `VERSION` à `go1.26.10` dans `outils-prefetch` ; je ne prédis pas son chemin.

## Résultats (12/11/2026, accord « Oui, lance les trois »)

### `transporter` : 10:42:31 à 10:42:35 UTC, code 0

Journal : `s6b-transporter.log`.

| # | Résultat | Mesure |
|---|---|---|
| T1 | **Tenue** | 8 bundles horodatés pour `039949f9` |
| T2 | **Tenue** | 7 entrées copiées (`preparer-deb`, `outils-prefetch`, `construire-deb`, deux fermetures, packaging), plus le manifeste seul de `749d746c` |
| T3 | **Tenue** | Archive de 402 Mo, 402 Mo dans la VM. Le bundle git fait 8,0 Kio. |

Le transport a pris 4 s : Zot est sur le réseau local.

### `verifier` : 10:42:41 à 10:42:47 UTC, code 0, `bilan : 0 KO`

Journal : `s6b-verifier.log`. sha256 de `verifier_deb.py` : `7498fdad…`.

| # | Résultat | Mesure |
|---|---|---|
| V1 | **Tenue** | Racine de la TSA construite ; sujet `039949f9` |
| V2 | **Tenue** | **8 bundles vérifiés sur 8**, hors réseau, avec la clé de Chains de la 08 (`a7ca8ce8…`) et le jeton de la TSA. Les huit `invocationId` sont les quatre PipelineRuns et quatre TaskRuns `publier-image`. Provenance `454728c5` extraite ; son jeton de la TSA est du 11/11, 21:04:09 GMT. |
| V3 | **Tenue** | Section 1 tenue ; 8 entrées déclarées, une fois chacune ; les 6 digests transportés et celui du manifeste de `749d746c` sont égaux à la provenance |
| V4 | **Tenue** | Commit `6391fd43…` présent, et `main` le désigne ; arbre extrait, propre |
| V5 | **Tenue** | Les 15 lignes clés sont trouvées dans les bundles vérifiés |
| V6 | **Tenue** | `usr/local/go/VERSION` : `go1.26.10`, égal à la toolchain du domaine |
| V7 | **Tenue** | **La couche du chroot du domaine est `1029232e…`, celle de l'image de build déclarée** (2 couches, 451 788 800 octets). Le chroot de la VM a le sha256 `aec1c7a9…`. |
| V8 | **Tenue** | `finishedOn` `2026-11-11T21:03:37Z` |

**Le chroot reconstruit dans le domaine est donc rattaché, par la provenance vérifiée, à l'image de build qui a construit le deb.**

### `repetition` : 10:42:53 à 10:44:05 UTC, lien établi, non comptée ; code 0, `bilan : PASSED`

Journal : `s6b-repetition.log`. Deux lignes retirées de la copie, comme prévu. sha256 de la copie transportée : `1422b13d…`, identique côté hôte et côté VM. L'unité systemd a tourné 1 min 11 s, pour 1 min 31 s de CPU.

| # | Résultat | Mesure |
|---|---|---|
| P0 | **Tenue** | `arbre=/var/tmp 1777 root;/var/tmp/s6b-r4 755 replay;/var/tmp/s6b-r4/e 755 replay` ; aucun refus d'accès. Le compte est `replay`, **UID 1000, comme le compte constructeur du pod**. |
| P1 | **Tenue** | 5 entrées et chroot `OK` ; commit `6391fd43` ; verrou : 162 paquets identiques, aucun autre fichier ; `vendor/` reconstitué par go1.26.10 (17 fichiers) ; marked 16.4.1, integrity conforme (12 membres) ; `src` 41 fichiers, `debian` 5 fichiers |
| P2 | **Tenue** | sbuild : code 0 en **68 s**, **aucune ligne apt en http(s)** |
| P3 | **Tenue** | **Deb `0b489d43…` (1 952 080 octets), couche `12dd5c42…` (1 955 840 octets), manifeste `039949f9…`, égal au sujet de la provenance : `verdict=PASSED`** |
| P4 | Non prédite | Paquet source **identique à celui de la plateforme** : `.orig.tar.gz` `07521c1e…`, `.dsc` `7f9cf5d3…`, `.debian.tar.xz` `f0e5cfc8…`. Ce sont les mêmes valeurs que dans les journaux des PipelineRuns de S4d et de S3. |
| P5 | **Tenue** | Le premier nettoyage en root de `transporter_r4` est passé. Le second passage le rejouera, à `rebuild`. |

**Fait mesuré au passage** : bien que le lien soit établi, les compteurs d'émission de l'invité sont identiques au début et à la fin (`tx_packets=42054`, `tx_bytes=4482824`). **La VM n'a rien émis pendant la reconstruction.** Ce n'est pas une preuve hors ligne, puisque le lien était là : c'est le rôle de `rebuild`.

**Conséquence** : la reconstruction indépendante du deb tient. Il reste `rebuild`, lien coupé, possible à partir du 12/11/2026 à 21:03:37 UTC, pour que le contrôle 6 soit valable hors ligne et que `vsa.py` accepte le délai.

