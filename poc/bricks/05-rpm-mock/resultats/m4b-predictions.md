# Brique 05, M4b : prédictions de `prealables` et `essai` (17/11/2026, écrites à 21:32:50 UTC, avant tout lancement)

Script : [`../m4b.sh`](../m4b.sh) (`6da65a32…`), préparé à sec sur « Oui, prépare-les ». Décisions : « Option A » (liste dans le gabarit), « Le retirer » (pas de rpm de mock), « Option 1 » (images d'essai) ([carte](m4b-carte.md)). Rien n'est lancé.

Accords demandés : `prealables` (hôte seul, hors ligne) et `essai` (un pod d'essai dans `builds`, rien dans Zot), un chacun.

## Vérifié à sec, hors cluster

- `bash -n` passe ; shellcheck 0.11.0 : SC2015 (`attendu`) et SC2016 (`printf` voulu sans expansion), remarques de style.
- **Banc des trois scripts du pod** (sonde, pas de prefetch, comparaisons ; [script](m4b-banc.sh), [journal](m4b-banc.log)) : extraits de `m4b.sh`, joués par dash avec de faux `curl`, `rpm`, `createrepo_c`, `skopeo` et `gpg`, et un `PATH` restreint aux seuls outils de base présents dans l'image d'outillage (liste des paquets de `s1-racine.log` : ni `cmp` ni `diff`, `diffutils` absent) ; 21 OK, 0 KO. La sonde rapporte un outil absent et une clé absente sans s'arrêter, et lit le manifeste sous les deux formes de CA. Le pas de prefetch passe le cas nominal, et sans `gpg` ; il refuse un sha256 faux, une taille fausse, un nom en double, un HTTP 404, une signature refusée, une empreinte fausse, un identifiant court faux, un manifeste différent, `createrepo_c` absent. Les comparaisons voient `repodata` par défaut différer et les variantes égales (faux `createrepo_c` conçu pour cela : cela teste le script, pas l'outil). Premier passage du banc archivé à part ([journal](m4b-banc-passage1.log)) : deux attentes fausses du banc (8 fichiers et non 6 ; `gpg` de l'hôte dans `/usr/bin`), pas du script. Relecture du conseiller ensuite : les comparaisons utilisaient `cmp` et `diff`, absents de l'image, ce qui aurait fait conclure « différents » à tort ; remplacés par des sha256 et `comm`, et le banc rejoué sur le `PATH` restreint.
- Non archivé : la construction de la liste, essayée sur des primary synthétiques (222 lignes ; URL absente, écart avec la collecte et doublon refusés).

## Lectures qui fondent l'essai

- Pod de la future tâche, modelé sur la pipeline de la fermeture deb (S4b) : `serviceAccountName: build`, zone `build`, `runAsNonRoot`, UID 65532, seccomp `RuntimeDefault`, capacités retirées ; workspace en volume demandé par gabarit et monté sous un `subPath` (ici `fermeture`, comme `prefetch-deb`) ; CA du PoC par la ConfigMap `ca-poc` (`/etc/ca-poc`), comme `publier-fermeture`. Le volume est un volume éphémère du pod, de la même classe par défaut que le `volumeClaimTemplate` de Tekton (lecture : aucune `storageClassName` dans les deux).
- La clé de Rocky est prise dans l'image (`/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9`), et non livrée : la même clé signe les `repomd.xml` de vault 9.7 et de Rocky 9.8 (signataire `21CB256A…` des deux, mesuré, `s1-3-hote.log`) ; que le fichier de l'image soit cette clé est à vérifier par l'essai.
- Non couvert par l'essai : la liste reçue en paramètre de Tekton (ici, un fichier livré par `kubectl exec`), et `publier-fermeture`.
- `rpm -K` est gardé dans l'essai, en plus du sha256 fixé par fichier ; la décision de le garder dans la tâche signée se prendra sur la mesure (durée, sans root).

## `prealables` (hôte, hors ligne)

| # | Prédiction | Confiance |
|---|---|---|
| PA1 | Verrou `b6d0f8f1…` | Haute |
| PA2 | Pour BaseOS, AppStream, CRB et extras de vault 9.7 : `repomd.xml` signé par `21CB256A…`, `primary.xml.gz` égal à `repomd.xml`, primary décompressé égal à celui du cache de `s1.sh` | Haute : mêmes fichiers que `hote97` ; leur présence dans le cache n'est pas relevée (le cache n'est pas listé) |
| PA3 | Liste de 222 lignes, 0 URL absente, 0 doublon ; collecte : 222 rpm, 0 écart | Haute : la collecte a mesuré l'égalité aux primary |
| PA4 | `resultats/m4b-liste.txt` écrit ; 222 lignes, total des tailles égal aux 222 rpm de la collecte | Haute |
| PA5 | Les deux scripts du pod passent `sh -n` (dash) | Haute (banc) |

## `essai` (pod d'essai, rien dans Zot)

| # | Prédiction | Confiance |
|---|---|---|
| E1 | Pod admis en dry-run serveur | Moyenne : premier volume éphémère dans `builds` ; neuf ValidatingPolicy et Pod Security non essayés sur cette forme |
| E2 | Pod prêt sur un nœud `zone=build`, sans `runtimeClassName` (runc) | Moyenne : image tirée de `essais-05/` par le nœud, mesurée en M3 sous Kata seulement |
| E3 | `id` : uid 65532 ; volume inscriptible sous le `subPath` | Moyenne : `prefetch-deb` écrit en 65532 sous un `subPath` (S4b), mais avec un `volumeClaimTemplate` de Tekton |
| ES1 | Sonde : uid 65532 ; volume inscriptible | Moyenne : voir E3 |
| ES2 | Sonde : `cmp` et `diff` absents ; `curl`, `rpm`, `createrepo_c`, `skopeo`, `gpg`, `find`, `du`, `awk`, `comm` présents | Haute : liste des paquets de la racine (`s1-racine.log`) |
| ES3 | Sonde : clé de l'image présente, empreinte `21CB256A…` par `gpg`, identifiant court `350d275d` | Haute : `rocky-gpg-keys-9.8` dans la racine ; même signataire pour 9.7 et 9.8 |
| ES4 | Sonde : les deux formes de CA lisent le manifeste `f0ccf105…` en anonyme | Moyenne : lecture anonyme mesurée depuis l'hôte (R8 de M4a), jamais depuis un pod runc |
| E4 | Passage p1 : 222 téléchargés et contrôlés ; clé de Rocky conforme ; `rpm -K` 222 OK sur 222 sans root ; `createrepo_c` rc 0 ; `skopeo copy` anonyme rc 0, manifeste `f0ccf105…` ; 233 fichiers (222 rpm, 7 de `repodata`, 4 du dossier `dir:`) | Moyenne : jamais joué sans root ; `--src-cert-dir` jamais utilisé |
| E5 | Passage p2 : de même | Moyenne, si E4 tient |
| E6 | p1 et p2 égaux hors `repodata` (226 fichiers) | Haute, si E4 et E5 tiennent |
| E7 | `repodata` par défaut différents entre p1 et p2 | Haute : `repomd.xml` a déjà différé entre `voie2` et `collecte` (mesuré) |
| E8 | V1 (rpm datés à 0, `--compatibility --revision 0 --set-timestamp-to-revision`) : les deux options existent dans `createrepo_c` de l'image, et les deux copies donnent les mêmes `repodata` | Faible : options de mémoire, jamais relues ni essayées |
| E9 | V2 (V1 et `--no-database`) : deux copies égales, trois fichiers de moins (bases sqlite) | Faible : de même |
| E10 | Pod supprimé à la fin, avec son volume éphémère (une PVC et son volume) ; rien écrit dans Zot | Haute |
| E11 | Durée d'un passage sous 300 s | Moyenne : 61 s de téléchargement en M2, sous Kata |

## Résultat de `prealables` (17/11/2026, de 21:33:55 à 21:34:01 UTC, « Oui, lance-le » ; note écrite à 21:34:23 UTC)

Code 0 ([journal](m4b-prealables.log), `95bcad00…`), hôte seul, hors ligne.

| # | Résultat |
|---|---|
| PA1 | **Tenue.** Verrou `b6d0f8f1…`. |
| PA2 | **Tenue.** BaseOS, AppStream, CRB et extras de vault 9.7 : `repomd.xml` signé par `21CB256A…`, `primary.xml.gz` égal à `repomd.xml`, primary décompressé égal à celui du cache de `s1.sh`. |
| PA3 | **Tenue.** 222 lignes, 0 URL absente, 0 doublon ; collecte : 222 rpm, 0 écart de sha256 ou de taille. |
| PA4 | **Tenue.** [`m4b-liste.txt`](m4b-liste.txt) écrite : 222 lignes, 219 543 349 octets, égal à la somme des tailles des 222 rpm de la collecte (219 543 349, relevé à 21:34:23 UTC) ; sha256 `95541ee8…`. |
| PA5 | **Tenue.** Sonde, pas de prefetch et comparaisons passent `sh -n` (dash). |

La liste qui sera inscrite dans le gabarit est fixée : `95541ee86a3c8891d231df6896558a78f73a607037b2a7035312337ab80b8910`. Suite : `essai`, sur accord nommé.

## Résultat de `essai` (17/11/2026, de 21:34:52 à 21:36:04 UTC, « Oui, lance-le » ; note écrite à 21:36:36 UTC)

Code 0 ([journal](m4b-essai.log), `f6260291…`). Pod `m4b-05-essai` sur `sc-build`, sans `runtimeClassName` (runc), supprimé à la fin avec son volume éphémère ; plus aucun pod ni PVC de ce nom dans `builds` à 21:36:36 UTC. Rien écrit dans Zot.

| # | Résultat |
|---|---|
| E1 | **Tenue.** Admis en dry-run serveur. |
| E2 | **Tenue.** Prêt sur `sc-build`, runc. |
| ES1, E3 | **Tenues.** `uid=65532 gid=65532` ; `/workspace/sortie` (sous `subPath`) et `/tmp` en `drwxrwxrwx`, volume inscriptible. |
| ES2 | **Tenue.** `cmp` et `diff` absents ; tous les autres outils présents, `python3` aussi. |
| ES3 | **Tenue.** Clé de l'image présente, empreinte `21CB256AE16FC54C6E652949702D426D350D275D` par `gpg`, identifiant court `350d275d`. |
| ES4 | **Tenue.** Les deux formes de CA (`--cert-dir /etc/ca-poc`, `SSL_CERT_FILE`) lisent le manifeste `f0ccf105…` en anonyme. |
| E4 | **Tenue.** p1 : 222 rpm téléchargés et contrôlés (sha256, taille), `rpm -K` 222 OK sur 222 sans root, `createrepo_c` rc 0, `skopeo copy` anonyme, manifeste `f0ccf105…` ; 233 fichiers, 318 744 669 octets. |
| E5 | **Tenue.** p2 : de même ; 233 fichiers, 318 744 630 octets. |
| E6 | **Tenue.** p1 et p2 égaux hors `repodata` : 226 fichiers. |
| E7 | **Tenue.** `repodata` par défaut différents (`repomd.xml` `af75d39e…` contre `3524b507…`). Seuls diffèrent `primary.xml.gz`, `primary.sqlite.bz2` et `repomd.xml` : `filelists` et `other` sont égaux (lecture du journal). |
| E8 | **Tenue.** V1 (rpm datés à 0, `--compatibility --revision 0 --set-timestamp-to-revision`) : les options existent dans `createrepo_c` 0.20.1 ; deux copies, mêmes `repodata` (7 fichiers, `repomd.xml` `65061cd6…`). |
| E9 | **Tenue.** V2 (V1 et `--no-database`) : deux copies, mêmes `repodata` (4 fichiers, `repomd.xml` `239a5a71…`). |
| E10 | **Tenue.** Pod supprimé avec son volume. |
| E11 | **Tenue.** 26 s et 29 s par passage (61 s de téléchargement seul en M2, sous Kata). |

**Constats**
- La fermeture de la plateforme peut être reproductible : avec V1 ou V2, deux passages donnent les mêmes `repodata`, et le reste est déjà égal. L'écart venait des dates des fichiers (que `curl` pose au téléchargement et que `primary` reprend) et des dates de `repomd.xml`.
- `rpm -K` coûte peu : les deux passages entiers durent moins de 30 s.
- Le volume éphémère montre 30 753 032 kB, et non les 4 Gi demandés : la classe de stockage par défaut ne borne pas la taille (lecture du `df`).
- Non mesuré : que mock, en mode hermétique, accepte des `repodata` faits avec V1 ou V2 (sans bases sqlite pour V2). Ce sera à mesurer en M4c, ou par un build d'essai.

Suite : choisir la variante de `createrepo_c` et confirmer `rpm -K` avant d'écrire la tâche signée.

## Note datée du 17/11/2026, 21:40:04 UTC : deux corrections au résultat de `essai`, et question sur la variante

**Correction 1, la cause.** La note de résultat dit que l'écart « venait des dates des fichiers […] et des dates de `repomd.xml` ». C'est une inférence, pas une mesure : V1 change à la fois la date des rpm et les deux options, sans les isoler. V1 est donc une unité mesurée : la date des rpm à 0, `--revision 0` et `--set-timestamp-to-revision` restent ensemble dans la tâche.

**Correction 2, le retrait du pod.** Le contrôle de la note de résultat (« plus aucun pod ni PVC de ce nom ») masquait le code de `kubectl` et ne distinguait pas « aucun » d'un échec ; sa valeur n'était qu'à l'écran. Refait avec le code visible à 21:39:44 UTC ([journal](m4b-essai-retrait.log)) : `kubectl` rc 0, 68 objets pod et PVC dans `builds`, aucun nommé `m4b-05-essai`.

**`rpm -K` gardé.** 222 OK sur 222 sans root, dans des passages de moins de 30 s ; la ligne M2 du tableau des jalons demande des signatures vérifiées. Ce n'est pas une question.

**Question : la variante de `createrepo_c` pour la tâche signée.**
- **V1** (rpm datés à 0, `--compatibility --revision 0 --set-timestamp-to-revision`) : les sept fichiers de `repodata` de la fermeture de M3, mêmes types, seules les dates et la révision fixées. `repomd.xml` `65061cd6…` aux deux copies.
- **V2** (V1 et `--no-database`) : quatre fichiers, sans les trois bases sqlite ; un écart de plus avec la fermeture de M3. `repomd.xml` `239a5a71…`.
- Mock n'a lu ni l'une ni l'autre.
- **Recommandation** (relue par le conseiller) : V1, sur ce seul motif : c'est la fermeture de M3 aux dates près.

**Ce qui bloque `taches`, quelle que soit la variante**
1. **Mock sur des `repodata` V1** : rejouer un build hermétique sur un arbre restauré de M3 (`$T/m3`), `repodata` régénéré avec V1, sous Kata comme `m3_build`. Attendus : `repomd.xml` `65061cd6…` (sinon, une autre entrée que les rpm et les options y entre), rpm `864d55f4…`, src.rpm `c802e60a…`.
2. **Le script à signer n'a pas tourné entier** : le pas de prefetch a tourné avec `createrepo_c` par défaut ; V1 n'a tourné que dans les comparaisons, sur des copies en liens durs. Le pas final est à rejouer entier dans le pod runc.
- Les deux demandent un script modifié, donc un accord chacun ; la mesure de mock d'abord.
- Pour le script final et la carte de `taches` : retirer le repli par l'identifiant court (`gpg` est dans l'image épinglée) ; déclarer l'image de bootstrap en `*_ARTIFACT_INPUTS` ; rejouer la section d'envoi de `publier-fermeture` sur les vrais noms de fichiers.

## Note datée du 17/11/2026, 21:46:41 UTC : décision « V2 »

**Décision du propriétaire** (réponse reçue avant 21:46:41 UTC, heure exacte non relevée) : « V2 ». Ce n'était pas ma recommandation (V1). Ce n'est un accord pour aucune mesure ni aucune écriture.
- La tâche signée régénère `repodata` avec : rpm datés à l'époque 0, `createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database`. Ces réglages restent ensemble (correction 1 de la note précédente).
- `repodata` de la fermeture de la plateforme : quatre fichiers, sans les trois bases sqlite. Mesuré à l'essai : `repomd.xml` `239a5a71c887d4370228ffdff016517282086f19de93418ee740482c089be164` aux deux copies.
- Écart avec la fermeture de M3 : les trois bases sqlite en moins, en plus des dates fixées.
- **Mesure qui bloque `taches`, ajustée à V2** : un build hermétique par mock, sous Kata, sur un arbre restauré de M3 dont `repodata` est régénéré avec V2. Attendus : `repomd.xml` `239a5a71…`, rpm `864d55f4…`, src.rpm `c802e60a…`. Puis le pas final rejoué entier dans le pod runc. Chacun demande un script modifié et un accord.

## Étape `m4b_mock_v2` de `s1.sh` : préparée à sec (17/11/2026, 21:59:20 UTC, « Oui, prépare-la »), NON APPLIQUÉE

**Objet** : mesurer que mock, en mode hermétique, construit le même rpm sur des `repodata` faits avec la variante V2, avant de signer `prefetch-rpm`.

**Correctif** [`s1-m4b-v2.patch`](../s1-m4b-v2.patch) (`b7535d39…`), copie bancée `3d26df84…` ; `s1.sh` du dépôt `06c2da46…`.
- Insertions seules : en-tête de 7 lignes, code de 33 lignes ; aucune ligne de `s1.sh` retirée ni changée.
- `m3_build` inchangé, appelé avec `n=v2` : pod `s1-05-m3-v2`, label `construire-rpm` (politique « Tout couper » relue, quatre témoins fermés exigés), chemins `/w/bv2`, sur une copie en liens durs de la fermeture restaurée 1 (`$T/m3/restauree-v2`).
- Seule la sonde change, par une insertion juste avant mock, après la porte d'intégrité et la vérification des sources : `repodata` de la fermeture retiré, rpm datés à l'époque 0, `createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database` (fin de son journal imprimée s'il échoue), ligne « repodata V2 », puis `repomd.xml` imprimé en entier (sommes de chaque fichier de `repodata`).
- Mesures comptées en écarts (code 1 s'il y en a un) : `repomd.xml` égal à `239a5a71…` (essai), 4 fichiers, rpm `864d55f4…` et src.rpm `c802e60a…` (M3).

**Bancs**
- Banc dédié ([script](s1-m4b-v2-banc.sh), [journal](s1-m4b-v2-banc.log)) : 27 OK, 0 KO. Il joue la vraie fonction de l'étape avec un `m3_build` simulé (nominal en code 0 ; `repomd.xml`, rpm ou src.rpm faux, ligne absente : code 1), la composition de la sonde, et `BLOC_V2` par dash avec un faux `createrepo_c`. Il se rejoue après application contre le `s1.sh` d'avant (arguments).
- Premier passage ([journal](s1-m4b-v2-banc-passage1.log)) : il a trouvé un vrai défaut, corrigé. Dans `${s/"$m"/$BLOC_V2$m}`, bash 5.2 et plus remplacent chaque « & » du remplacement par le motif trouvé : `2>&1` aurait altéré la sonde. Le remplacement est mis entre guillemets. Défaut du banc aussi : shellcheck sous `LC_ALL=C` s'arrêtait sur les accents.
- Second passage ([journal](s1-m4b-v2-banc-passage2.log)), 17 OK : tenu, mais la fin de l'étape n'y était pas jouée ; banc réécrit sur relecture du conseiller, qui a aussi fait imprimer `repomd.xml` et l'erreur de `createrepo_c`.
- Non-régression sur la copie finale : banc de M3 ([journal](s1-m4b-v2-banc-m3.log)), 76 OK et 1 KO, celui de sa section A, propre aux blocs du correctif de M3 ; aucune remarque shellcheck de niveau warning ou error. Banc N3/N4 ([journal](s1-m4b-v2-banc-n34.log)) : 35 OK.
- Dossiers de banc laissés : `~/.cache/supply-chain-poc/05/banc-m4v2`, `banc-m4v2-2`, `banc-m4v2-3`, `banc-n34-m4v2`, `banc-n34-m4v2-2`, `banc-n34-m4v2-3`.

**Prédictions** (écrites avant toute application et tout passage)

| # | Prédiction | Confiance |
|---|---|---|
| MV1 | Copie en liens durs de 235 fichiers ; point d'insertion unique ; sonde composée de la sonde de M3 et de `BLOC_V2` seuls | Haute (banc) |
| MV2 | Politique relue ; quatre témoins à 124 dans le pod `construire-rpm` | Haute : deux fois en M3 |
| MV3 | Fermeture copiée et revérifiée dans le pod : 235 fichiers, porte d'intégrité rc 0 | Haute : deux fois en M3 |
| MV4 | `repodata` V2 dans le pod : `repomd.xml` `239a5a71…`, 4 fichiers | Moyenne : mêmes rpm et même `createrepo_c` (même image) qu'à l'essai, mais premier passage sur un autre système de fichiers (`/w` en tmpfs sous Kata, contre un volume sous runc) et en root. S'il diffère : regarder d'abord l'ordre des fichiers et le nombre de fils de `createrepo_c` |
| MV5 | `mock --hermetic-build` rc 0 sur ces `repodata` sans bases sqlite | Moyenne : dnf lit les métadonnées XML (de mémoire, non vérifié) ; jamais mesuré |
| MV6 | rpm `864d55f4…` et src.rpm `c802e60a…`, égaux à M3 ; 222 paquets au buildroot | Moyenne, si MV5 tient : `repodata` n'entre pas dans le paquet |
| MV7 | Aucune ligne http ou https dans les journaux de mock ; « écarts : 0 », code 0 | Moyenne, si MV4 à MV6 tiennent |

**Ce que chaque issue permet**
- MV4 tenue : mock a lu les quatre fichiers mêmes que la tâche produira (`repomd.xml` porte leurs sha256).
- MV4 non tenue, MV5 et MV6 tenues : mock accepte un index V2, mais la reproductibilité d'un environnement à l'autre n'est pas établie ; la signature reste bloquée.
- Non couvert : ce build part de la fermeture de M3, avec `verrou.json` et `outils/` ; la fermeture de la plateforme n'aura ni l'un ni l'autre (« Option A », « Le retirer »).

## Note datée du 17/11/2026, écrite à 22:05:44 UTC : correctif appliqué à `s1.sh` (« Oui, applique-le »)

- Appliqué le 17/11/2026 à 22:04:05 UTC : `s1.sh` passe de `06c2da46…` à `362af7ef…`, soit la copie bancée `3d26df84…` plus deux lignes datées à l'en-tête, après le bloc de `m4b_mock_v2` (même forme qu'à l'application de M3). Annoncé au propriétaire : une ligne datée (en-tête de 8 lignes) ; fait : deux (en-tête de 9 lignes). Une première tentative, à 22:03:54 UTC, n'a rien écrit : une assertion du script d'application (plafond de largeur de la ligne datée, choisi par moi) l'a arrêtée avant l'écriture ; la ligne a été coupée en deux.
- Banc dédié rejoué sur le fichier du dépôt contre le `s1.sh` d'avant (`06c2da46…`), arguments 9 et 33 : 27 OK, 0 KO ([journal](s1-m4b-v2-banc-applique.log)).
- Banc de M3 sur le fichier du dépôt ([journal](s1-m4b-v2-banc-m3-applique.log)) : 75 OK, 2 KO, tous deux dans sa section A, qui cherche les blocs du correctif de M3 entre le `s1.sh` du dépôt et une copie, ici le même fichier (0 bloc). Hors section A, les écarts avec le journal de la copie sont : chemins du dossier de banc, heures, `df` de l'hôte, taille du faux `root.log` (349 et 352 octets ; le chemin du dossier de banc y est plus long de 3 caractères, lecture), et remarques shellcheck désormais égales des deux côtés (32).
- Banc N3/N4 sur le fichier du dépôt : 35 OK ([journal](s1-m4b-v2-banc-n34-applique.log)).
- Dossiers de banc laissés : `~/.cache/supply-chain-poc/05/banc-m4v2-4`, `banc-m4v2-m3-4`, `banc-n34-m4v2-4`.
- Rien n'est lancé. MV1 à MV7 sont inchangées ; le lancement de `m4b_mock_v2` demande son propre accord.

## Note datée du 17/11/2026, écrite à 22:11:49 UTC : `m4b_mock_v2` passée (« Oui, lance-le »)

Passage du 17/11/2026 de 22:07:42 à 22:11:10 UTC, code 0, « écarts : 0 », aucune ligne KO ([journal](s1-m4b_mock_v2.log), [journaux de mock](s1-m3_buildv2-mock.log)). `s1.sh` = `362af7ef…`.

| # | Mesure | Verdict |
|---|---|---|
| MV1 | Copie en liens durs de 235 fichiers, arbre égal à la liste ; point d'insertion unique ; sonde composée de la sonde de M3 et de `BLOC_V2` seuls (593 caractères de plus) | Tenue |
| MV2 | Politiques de `builds` relues, aucune n'autorise de trafic au label `construire-rpm` ; témoins DNS, public, Zot, API : 124 124 124 124 | Tenue |
| MV3 | Fermeture revérifiée dans le pod : rc 0, 235 fichiers, 235 lignes de liste | Tenue |
| MV4 | `repodata` V2 dans le pod : `repomd.xml` `239a5a71…`, 4 fichiers (`repomd.xml`, primary, filelists, other ; aucune base sqlite), imprimé en entier au journal : révision 0, horodatages 0 | Tenue |
| MV5 | `mock --hermetic-build` rc 0 sur ces `repodata` | Tenue |
| MV6 | src.rpm `c802e60a…` et rpm `864d55f4…`, égaux à M3 ; 222 paquets au buildroot, lignes « paquet » égales à celles de `s1-m3_build1.log` | Tenue |
| MV7 | 0 ligne http ou https dans la sortie de mock, `root.log` et `build.log` ; « écarts : 0 », code 0 | Tenue |

**Ce que cela établit** : mock accepte, en hermétique et sous Kata, un index produit par la variante V2 de `createrepo_c`, et le `repomd.xml` obtenu dans ce pod (tmpfs, root, Kata) est celui des deux copies de l'essai (volume, UID 65532, runc). Le rpm et le src.rpm ne changent pas.

**Ce que cela n'établit pas** : ce build part de la fermeture de M3 (`verrou.json`, `outils/`) ; la fermeture de la plateforme n'aura ni l'un ni l'autre. Le pas final de `prefetch-rpm` n'a pas encore été rejoué entier avec V2.

Pod `s1-05-m3-v2` supprimé ; rien écrit dans Zot ; arbres `$T/m3/restauree-v2` et `$T/m3/build-v2` laissés.

## Note datée du 17/11/2026, écrite à 22:24:18 UTC : étape `final` préparée à sec (« Oui, prépare-le »), NON LANCÉE

**Script** : [`../m4b.sh`](../m4b.sh) passe de `6da65a32…` à `bf927e5b…`, par insertions seules (trois blocs : 7 lignes d'en-tête, 65 de scripts, 48 de fonction), comme l'étape `politiques` de `m4a.sh` (« Oui, complète-le », puis un accord de lancement). `PREFETCH` reste le script mesuré à l'essai ; le pas final est un script distinct, `PREFETCH_FINAL`.
- `PREFETCH_FINAL` = `PREFETCH` avec trois changements, et eux seuls (diff archivé au journal du banc) : `gpg` obligatoire (repli sur l'identifiant court seul retiré ; contrôle de l'identifiant court après import gardé) ; rpm datés à l'époque 0 puis `createrepo_c --compatibility --revision 0 --set-timestamp-to-revision --no-database` (mêmes options que `BLOC_V2` de `s1.sh` et la variante V2 de l'essai), fin de son journal imprimée en cas d'échec ; ligne « repodata V2 » (sha256 de `repomd.xml`, nombre de fichiers, durée) et `repomd.xml` imprimé en entier. La valeur attendue de `repomd.xml` n'est pas dans le script du pod : elle reste côté hôte (`REPOMD_V2`) ; la mettre ou non dans le gabarit signé relève de la carte de `taches`.
- Étape `final` : liste des rpm contrôlée (`95541ee8…`) ; **un pod neuf par passage** (`m4b-05-final-p1`, puis `-p2`), chacun avec son volume éphémère, spec de l'essai (runc, UID 65532, label `prefetch-rpm`, volume sous `subPath`, CA du PoC) ; `SORTIE=/workspace/sortie` (racine du volume, comme le workspace de la tâche) ; dans chaque pod : `PREFETCH_FINAL` entier, puis `repomd.xml` comparé à `239a5a71…` sur l'hôte, arbre relevé (chemin, taille, sha256 de chaque fichier, `repodata` compris), retrait du pod (code de `kubectl`), attente de la suppression de la PVC `<pod>-w` (code de `kubectl wait`), pods et PVC relus. Puis arbres p1 et p2 comparés, 230 fichiers attendus, arbre archivé sous `resultats/m4b-final-arbre.txt` (référence pour l'étape `comparaison`). Journaux sous des noms distincts de ceux de l'essai. Un passage en échec laisse son pod pour lecture.

**Banc** ([script](m4b-final-banc.sh), [journal](m4b-final-banc.log)) : tenu, 51 OK, 0 KO.
- A : insertions seules contre `6da65a32…` ; lignes retirées de `PREFETCH` et ajoutées à `PREFETCH_FINAL` (10 et 10) limitées à `gpg`, aux dates et à `createrepo_c` ; options égales à celles de `BLOC_V2` et de la variante V2 ; rpm datés avant `createrepo_c`.
- B : `bash -n`, `dash -n` ; shellcheck : un SC2016 de plus (le `printf` de la durée, sans expansion voulue).
- C : `PREFETCH_FINAL` joué par dash, `PATH` restreint aux outils de base de l'image et à de faux outils ; le faux `createrepo_c` exige les options exactes, des rpm datés à 0 et aucun dossier dans le dépôt. Nominal (222 rpm, nom avec « + », 4 fichiers de `repodata`, `repomd.xml` imprimé ligne à ligne, 230 fichiers) ; `gpg` absent désormais refusé ; `createrepo_c` en échec refusé avec la fin de son journal ; les dix refus de `PREFETCH` inchangés.
- D : la vraie fonction `etape_final` de la copie (vrais `attendu`, `pod_spec`, `dans`), avec un faux `kubectl` qui joue les scripts du pod par dash dans un dossier par pod : nominal en code 0 (19 lignes OK, deux pods créés puis retirés avec leur PVC, arbre archivé de 230 lignes dont 4 de `repodata`), rejoué en code 0 (arbre égal à l'archivé) ; code 1 pour `repomd.xml` différent, arbres p1 et p2 différents, retrait en échec, PVC restante, passage en échec (pod laissé), liste différente, arbre archivé différent. Le verrou du banc est le vrai, avec l'image de bootstrap mise au digest du faux manifeste.
- Non-régression : le banc de l'essai ([journal](m4b-final-banc-essai.log)) sur le fichier modifié : 21 OK, 0 KO.
- Deux passages antérieurs, non tenus par défauts du banc seul, archivés ([1](m4b-final-banc-passage1.log), [2](m4b-final-banc-passage2.log)) : `dash` absent du `PATH` restreint ; nombre de lignes de fonction faux (50 pour 48) ; motif oubliant la ligne `[ "$fp" = … ]`, réindentée ; verrou réel au digest de la vraie image, que le faux manifeste ne peut pas avoir. Chemins du dossier personnel écrits `~` à l'archivage de ces deux journaux, comme le fait `lancer`.
- Non couvert par le banc : vrais pods, réseau, rpm, `createrepo_c` et admission (mesurés à l'essai, sauf l'admission de deux pods successifs).

**Prédictions de `final`** (écrites avant tout passage)

| # | Prédiction | Confiance |
|---|---|---|
| FN1 | Liste `95541ee8…` ; source du bootstrap `…rocky9-bootstrap@sha256:f0ccf105…` | Haute (prealables, essai) |
| FN2 | Pour chaque passage : pod admis en dry-run serveur, prêt sur un nœud `zone=build`, sans `runtimeClassName` ; liste livrée égale | Haute : même spec qu'à l'essai, autre nom |
| FN3 | Pour chaque passage : 222 rpm téléchargés et contrôlés ; empreinte de la clé conforme par `gpg` ; `rpm -K` 222 OK sur 222 | Haute : deux fois à l'essai |
| FN4 | Pour chaque passage : `repodata` V2, `repomd.xml` `239a5a71…`, 4 fichiers | Haute : même valeur mesurée dans trois dossiers et deux environnements (essai, deux copies sous runc ; `m4b_mock_v2` sous Kata). Différences avec ces mesures : `createrepo_c` tourne ici sur les fichiers téléchargés et non sur des copies en liens durs, et avant la copie de l'image (aucun dossier `dir:` dans le dépôt) ; il ne lit que les rpm (lecture, non vérifié) |
| FN5 | Pour chaque passage : `skopeo copy` anonyme, manifeste `f0ccf105…` | Haute (essai) |
| FN6 | Pour chaque passage : 230 fichiers (222 rpm, 4 de `repodata`, 4 du dossier `dir:`) ; arbres p1 et p2 égaux, `repodata` compris ; arbre archivé | Haute, si FN4 tient : hors `repodata`, égalité mesurée à l'essai (226 fichiers) |
| FN7 | Pour chaque passage : retrait du pod code 0 ; PVC retirée dans les 180 s ; aucun pod ni PVC au nom du pod | Moyenne : la suppression de la PVC du volume éphémère n'a été relue qu'une fois, 3 min 40 s après l'essai (E10) ; jamais attendue |
| FN8 | Durée d'un passage sous 120 s | Haute : 26 et 29 s à l'essai |
| FN9 | Code 0 ; rien écrit dans Zot | Haute, si FN1 à FN7 tiennent |

**Ce que chaque issue permet**
- FN4 et FN6 tenues : `PREFETCH_FINAL` peut servir de base au script de la tâche `prefetch-rpm` ; prochaine étape, la carte de `taches`.
- FN4 non tenue : l'index V2 ne serait pas reproductible d'une exécution de la tâche à l'autre ; arrêt, décision avec le propriétaire avant toute tâche signée.
- Non couvert : la liste reçue en paramètre de Tekton, le workspace de Tekton (ici un volume éphémère), `publier-fermeture`, la tâche signée.

## Note datée du 17/11/2026, écrite à 22:27:10 UTC : trois corrections à la note de préparation de `final`, avant tout passage

Relecture du conseiller. Le texte commité reste ; il se lit avec ces corrections.
- « les dix refus de `PREFETCH` inchangés » : ils sont **neuf** (`createrepo_c` absent, sha256, taille, doublon, HTTP 404, signature, empreinte, identifiant court, manifeste ; [journal](m4b-final-banc.log), section C). Les deux autres refus de la section C (`gpg` absent, `createrepo_c` en échec) sont nouveaux.
- « `SORTIE=/workspace/sortie` (racine du volume) » : c'est la racine du **montage**, qui est le sous-dossier `fermeture` du volume (`subPath`), comme pour l'essai.
- FN9, « rien écrit dans Zot » : l'étape ne le mesure pas. Les pods de `final` joignent Zot (lecture anonyme de l'image de bootstrap), à la différence du pod de `m4b_mock_v2`, dont le témoin Zot était fermé. FN9 se lit : code 0 ; rien écrit dans Zot **(lecture : aucune commande d'écriture vers un registre dans les scripts du pod, `skopeo copy` vers un dossier `dir:` ; aucun identifiant de Zot monté, `automountServiceAccountToken: false`)**.

## Note datée du 17/11/2026, écrite à 22:31:03 UTC : étape `final` passée (« Oui, lance-la »)

Passage du 17/11/2026 de 22:28:13 à 22:30:29 UTC (`chrono.tsv`), code 0, aucune ligne KO ([journal](m4b-final.log), [arbre](m4b-final-arbre.txt)). `m4b.sh` = `bf927e5b…`. Relevé avant le lancement : ni journal ni arbre archivé, aucun pod ni PVC `m4b-05-final-*` parmi 68 objets de `builds` ; après : 68 objets (comptés, non comparés nom à nom).

| # | Mesure | Verdict |
|---|---|---|
| FN1 | Liste `95541ee8…` ; source du bootstrap `…rocky9-bootstrap@sha256:f0ccf105…` | Tenue |
| FN2 | Deux pods admis en dry-run serveur, prêts sur `sc-build`, `runtimeClassName` vide ; liste livrée égale | Tenue |
| FN3 | Chaque passage : 222 téléchargés et contrôlés ; empreinte conforme par `gpg` ; `rpm -K` 222 OK sur 222 | Tenue |
| FN4 | Chaque passage : `repomd.xml` `239a5a71…`, 4 fichiers (`createrepo_c` en 1 s) | Tenue |
| FN5 | Chaque passage : `skopeo copy` anonyme, manifeste `f0ccf105…` (1 s) | Tenue |
| FN6 | Chaque passage : 230 fichiers, 317 984 334 octets ; arbres p1 et p2 égaux, `repodata` compris (liste `fc556539…` aux deux) ; arbre archivé | Tenue |
| FN7 | Chaque pod : retrait code 0, PVC `<pod>-w` retirée (`kubectl wait` code 0), aucun pod ni PVC au nom du pod | Tenue (durée de chaque retrait non relevée) |
| FN8 | 28 s par passage | Tenue |
| FN9 | Code 0 ; rien écrit dans Zot (lecture, voir la note de correction) | Tenue pour le code ; Zot non mesuré |

Recoupement hors script, à la relecture (non archivé autrement que par ce texte) : les 222 rpm de l'arbre archivé ont le sha256 et la taille de `m4b-liste.txt` ; `repodata/repomd.xml` y vaut `239a5a71…` ; les 4 autres fichiers sont ceux du dossier `dir:`.

**Ce que cela établit** : deux exécutions du pas final, chacune dans un pod neuf avec son volume, sans root, sous runc, donnent la même fermeture au fichier près, `repodata` compris, et cet index est celui que mock a accepté en hermétique (`m4b_mock_v2`). `PREFETCH_FINAL` peut servir de base au script de la tâche `prefetch-rpm`.

**Ce que cela n'établit pas** : la liste reçue en paramètre de Tekton, le workspace de Tekton, `publier-fermeture` et la tâche signée ; qu'un build parte de cette fermeture (sans `verrou.json` ni `outils/`) ; rien écrit dans Zot (non mesuré).

## Note datée du 17/11/2026, écrite à 22:54:34 UTC : `prealables_taches` et `essai_tache` préparées à sec (« Oui, prépare-les »), NON LANCÉES

**Fichiers**
- Gabarit de la tâche [`../fermeture/prefetch-rpm.yaml`](../fermeture/prefetch-rpm.yaml) :
  - image d'outillage par digest, runc, UID 65532, `runAsNonRoot`, capacités retirées, `/tmp` en `emptyDir`, CA du PoC ;
  - 2 CPU et 2 Gi en demandes et en limites ;
  - seule variable d'environnement : `HOME` ;
  - paramètres `liste`, `source`, `dossier`, `empreinte`, `repomd`, écrits dans le script par substitution de Tekton, jamais lus dans une variable : l'`env` du `podTemplate` l'emporterait (carte de `taches`, point 3) ;
  - résultat `BOOTSTRAP_ARTIFACT_INPUTS`.
- Gabarit de la pipeline [`../fermeture/prefetch-rpm-sample-app.yaml`](../fermeture/prefetch-rpm-sample-app.yaml) : `prefetch-rpm` sous le `subPath` `fermeture`, puis `publier-fermeture` à la racine ; dépôt `builds/fermetures/sample-app-rpm`.
- [`../m4b.sh`](../m4b.sh) passe de `bf927e5b…` à `d2b5fd7d…`, par insertions seules (14 lignes d'en-tête, 165 de code), comme `final`.
- **Script de la tâche contre `PREFETCH_FINAL`** : une ligne retirée (la clé réglable pour le banc) et 29 ajoutées. Le détail :
  - en-tête de 13 lignes : heredoc de la liste et affectations par substitution ;
  - 13 lignes de contrôles des entrées :
    - source au digest de 64 caractères ;
    - dossier cohérent avec la source ;
    - empreinte en 40 majuscules hexadécimales ;
    - `repomd` de 64 caractères ;
    - chaque ligne de la liste : URL sous vault 9.7, sans « .. », jeu de caractères limité, sha256, taille, trois champs ;
  - chemin fixe de la clé ;
  - comparaison de `repomd.xml` à l'attendu, avant la copie de l'image ;
  - écriture du résultat.

**Étapes**
- `prealables_taches` (hôte, plus une lecture sur sc-stockage) :
  - gabarits rendus, avec des références factices des tâches, puis relus champ par champ ;
  - écarts du script contre `PREFETCH_FINAL` ;
  - script substitué comme Tekton le fera : aucune référence `$(params.…)`, `$(workspaces.…)` ni `$(results.…)` restante, liste du heredoc égale à la liste ;
  - section d'envoi de `publier-fermeture`, version signée, jouée deux fois en layout OCI local. L'arbre a les 230 vrais noms de `final` : 226 fichiers réels, en liens durs depuis la fermeture restaurée de M3 et contrôlés par sha256 et taille, plus 4 fichiers de `repodata` factices ;
  - `df` de `/var/lib/zot`.
- `essai_tache` (pod d'essai, rien dans Zot) : le script substitué, tel qu'il sera signé, joué dans un pod neuf runc au label `prefetch-rpm`. Contrôles :
  - `repomd.xml`, résultat, arbre égal à celui de `final` ;
  - puis le même script avec un `repomd` attendu faux, dans un sous-dossier neuf : refus attendu avant la copie de l'image ;
  - retrait du pod et de sa PVC relu.

**Banc** ([script](m4b-taches-banc.sh), [journal](m4b-taches-banc.log)) : tenu, 40 OK, 0 KO.
- A : insertions seules ; shellcheck, seulement des SC2016 de plus (`printf` et `echo` sans expansion voulue).
- B : la vraie fonction `etape_prealables_taches`, avec les vrais gabarits et le vrai `publier-fermeture` signé. yq, jq et oras de l'hôte sur des layouts locaux, sur des données du banc :
  - nominal : 22 lignes OK, deux layouts, titres à « : » et « @ » ;
  - fichier restauré différent : refusé ;
  - variable d'environnement de plus dans la tâche : refusée.
- C : le script rendu et substitué par les fonctions de l'étape, joué par dash avec de faux outils sur le `PATH` de l'image :
  - nominal : résultat exact, arbre égal à la référence ;
  - **la vraie liste des 222 rpm passe tous les contrôles** (arrêt au premier téléchargement, faux 404) ;
  - `repomd` attendu faux refusé, sans dossier `dir:` ni résultat ;
  - dix entrées invalides refusées ; `gpg` absent refusé.
- D : la vraie fonction `etape_essai_tache`, avec un faux `kubectl` :
  - nominal : 14 lignes OK ;
  - code 1 pour un script en échec (pod laissé), un arbre différent, un retrait en échec, une PVC restante.
- Premier passage ([journal](m4b-taches-banc-passage1.log)) : un défaut de l'étape, trouvé et corrigé. yq ajoute une ligne vide à la fin du script extrait, qui comptait comme 30e ligne ajoutée ; elle est retirée à l'extraction.
- Non-régression sur la copie :
  - banc de l'essai ([journal](m4b-taches-banc-essai.log)) : 21 OK ;
  - banc de `final` ([journal](m4b-taches-banc-final.log)) : 49 OK et 2 KO. Les deux KO sont dans ses sections A et B, qui comptent les lignes insérées par `final` seul et ses SC2016 ; ses sections C et D sont toutes tenues.
- Non couvert : Tekton lui-même (substitution réelle, chemin du résultat, workspace en PVC, conteneurs d'initialisation, admission d'un pod de TaskRun), `publier-fermeture` dans son pod sous 512 Mi, et la taille du script substitué (environ 45 Ko) dans un pod de Tekton.
- Relevé à la préparation, non archivé autrement que par ce texte : les 226 fichiers de l'arbre de `final` hors `repodata` sont dans la fermeture restaurée de M3, aux mêmes sha256 et tailles.

**Prédictions de `prealables_taches`**

| # | Prédiction | Confiance |
|---|---|---|
| PT1 | Liste `95541ee8…` ; source `…rocky9-bootstrap@sha256:f0ccf105…`, dossier `sc-stockage.poc.test@sha256:f0ccf105…` | Haute |
| PT2 | Gabarits rendus sans variable restante ; tous les contrôles de la tâche et de la pipeline tenus | Haute (banc, mêmes gabarits) |
| PT3 | Script de la tâche : 1 ligne retirée, 29 ajoutées ; `dash -n` | Haute (banc) |
| PT4 | Script substitué : aucune référence de Tekton restante ; liste du heredoc égale ; environ 45 Ko | Haute |
| PT5 | Arbre : 226 fichiers réels conformes, 4 factices | Haute (relevé à la préparation) |
| PT6 | Section d'envoi : deux poussées au même digest, 230 couches aux titres distincts, égaux aux chemins de `final` préfixés par `depot/`, dont 4 à « : » et « @ » | Haute : forme mesurée au banc avec le même oras ; jamais sur 318 Mo |
| PT7 | `/var/lib/zot` : entre 4,5 et 5,1 Go libres | Moyenne : 5 055 672 320 octets libres à la fermeture de M2 ; aucune écriture de M3 ni de M4 depuis, d'après les journaux de la brique ; le système de fichiers peut porter autre chose (non relevé) |
| PT8 | Code 0, sous 120 s | Moyenne : deux layouts de 318 Mo |

**Prédictions de `essai_tache`**

| # | Prédiction | Confiance |
|---|---|---|
| ET1 | Scripts nominal et refusé : trois lignes d'écart (workspace, résultat, `repomd`) | Haute (banc) |
| ET2 | Pod admis en dry-run serveur, prêt sous runc, sans `runtimeClassName` | Haute (`final`) |
| ET3 | Nominal : 222 rpm téléchargés et contrôlés ; empreinte conforme ; `rpm -K` 222 sur 222 ; `repomd.xml` `239a5a71…`, contrôle passé ; manifeste `f0ccf105…` ; 230 fichiers ; code 0 ; sous 120 s | Haute : mêmes gestes que `final`, plus des contrôles d'entrée que la vraie liste passe au banc ; la clé de l'image au chemin fixe a été lue à l'essai (ES3) |
| ET4 | Résultat : `{"uri":"oci://sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap","digest":"sha256:f0ccf105…"}` | Haute |
| ET5 | Arbre égal à celui de `final` (liste `fc556539…`) | Haute |
| ET6 | Cas refusé : code 1, « repomd.xml différent de l'attendu », ni dossier `dir:` ni résultat | Haute : `createrepo_c` réel donne `239a5a71…` (ET3) |
| ET7 | Retrait du pod code 0, PVC retirée, aucun objet restant | Haute (FN7) |
| ET8 | Rien écrit dans Zot | Lecture : aucune écriture vers un registre dans le script, aucun identifiant de Zot monté |

**Ce que chaque issue permet**
- PT et ET tenues : le script de `prefetch-rpm` est essayé tel qu'il sera signé. Viennent ensuite `verrou` et `publier` de M4a (ordre consigné), puis `taches`, chacune sur son accord.
- PT6 non tenue : `publier-fermeture` ne publierait pas cette fermeture telle quelle ; décision au propriétaire avant toute signature.
- ET3 ou ET6 non tenues : pas de signature ; correction du gabarit, puis nouveau passage.

Accords demandés : `prealables_taches`, puis `essai_tache`, un chacun.

## Note datée du 17/11/2026, écrite à 22:59:14 UTC : correction du champ des ressources, avant tout passage

Relecture du conseiller. Le texte commité reste ; il se lit avec ces corrections.
- **Défaut du gabarit, corrigé.** La tâche est en `tekton.dev/v1beta1`. Le `Step` de cette version porte les ressources sous `resources` : `pkg/apis/pipeline/v1beta1/container_types.go` lu au tag v1.15.5, champ `Resources`, json `resources`, aucun champ `computeResources`. Les tâches signées du dépôt en v1beta1 écrivent aussi `resources`. `computeResources` est le nom de l'API v1. Il aurait été perdu à la lecture du gabarit, et le pas aurait tourné sous les valeurs de `config-defaults` (1 CPU, 512 Mi).
- **Pourquoi aucun contrôle ne l'a vu.** `prealables_taches` relisait le texte YAML, et le banc reprenait le même champ. `essai_tache` prend ses limites dans la spec du pod d'essai, pas dans le gabarit.
- **Corrections.**
  - Gabarit `prefetch-rpm.yaml` : `resources` au lieu de `computeResources` (`96b9d6bd…`).
  - Contrôle de `prealables_taches` : exige `resources` et aucune clé `computeResources` dans la tâche. C'est la seule ligne de `m4b.sh` changée, une ligne commitée mais jamais lancée. `m4b.sh` = `5e08bef0…`.
  - Banc : un cas de plus, `computeResources` refusé ; rejoué : 41 OK, 0 KO ([journal](m4b-taches-banc-2.log)).
  - Les bancs de l'essai et de `final` ne lisent pas cette ligne ; ils ne sont pas rejoués.
- **SC2016.** La note précédente les attribue à `printf` et `echo`. Le relevé de shellcheck en montre aussi sur des motifs de `sed` et de `grep` (`'$fp'`, `'^cd "$f"$'`) et sur un littéral attendu (`'K=${CLE_ROCKY:-…}'`). Tous sont sans expansion voulue.
- **À lire avant `taches`, sans bloquer ces deux étapes.**
  - `pkg/pod/script.go` au tag v1.15.5 : comment le script d'environ 45 Ko arrive dans le pod (taille d'un argument unique).
  - Après `SIGNER=1` et avant tout bundle : comparer le script et les ressources du fichier signé à ceux du gabarit rendu. Un bundle écrit dans Zot ne se retire pas.
- **Prédictions PT1 à PT8 et ET1 à ET8 inchangées.** PT2 couvre désormais le champ `resources`.

## Note datée du 18/11/2026, écrite à 09:08:17 UTC : `prealables_taches` passée (« Oui »)

Passage du 18/11/2026 de 09:07:03 à 09:07:08 UTC, code 0 ([journal](m4b-prealables_taches.log)). `m4b.sh` = `5e08bef0…`.

| # | Mesure | Verdict |
|---|---|---|
| PT1 | Liste `95541ee8…` ; source `…rocky9-bootstrap@sha256:f0ccf105…` ; dossier `sc-stockage.poc.test@sha256:f0ccf105…` | Tenue |
| PT2 | Tous les contrôles des gabarits rendus tenus, dont `resources` (2 CPU, 2 Gi) et aucune clé `computeResources` | Tenue |
| PT3 | 1 ligne retirée, 29 ajoutées ; `dash -n` | Tenue |
| PT4 | Script substitué : `dash -n`, liste du heredoc égale ; 44 751 octets, sha256 `572fb78c…` | Tenue |
| PT5 | Arbre : 226 fichiers réels conformes, 4 factices | Tenue |
| PT6 | Deux poussées au même digest de manifeste local (`f550faf1…`) ; 230 couches aux titres distincts, égaux aux chemins de `final` préfixés par `depot/`, dont 4 à « : » et « @ » ; layout de 317 347 580 octets ; oras 1.3.6 | Tenue |
| PT7 | `/var/lib/zot` : 4 491 038 720 octets libres, 15 529 877 504 utilisés | **Non tenue** (sous 4,5 Go) |
| PT8 | Code 0, en 5 s | Tenue |

**PT7.** La base de la prédiction était fausse. Les 5 055 672 320 octets libres de `s1-fermeture.log` ont été relevés *avant* l'envoi de la fermeture de M2, qui a ajouté 225 861 632 puis 253 952 octets. Le reste de l'écart, 338 518 016 octets utilisés de plus depuis la fin de M2, n'est attribué à rien : il n'a pas été relevé, et la prédiction supposait à tort qu'il n'y en avait pas. L'espace libre reste plus de dix fois supérieur au layout local de la fermeture (317 347 580 octets). PT7 ne bloque donc pas `essai_tache`, qui n'écrit rien dans Zot (ET8).

**Ce que cela établit** :
- les gabarits rendus portent les valeurs attendues ;
- le script de `prefetch-rpm`, substitué comme Tekton le fera, est du sh valide, et la liste lui arrive intacte ;
- la section d'envoi de `publier-fermeture` signée publie les 230 vrais noms en titres `depot/…` distincts, au même digest à deux poussées, sur le volume réel de la fermeture.

**Ce que cela n'établit pas** :
- le script dans un pod (`essai_tache`) ;
- Tekton lui-même ;
- `publier-fermeture` dans son pod sous 512 Mi ;
- l'envoi vers Zot ;
- l'origine des 338 518 016 octets.

Accord suivant : `essai_tache`. Le sha256 du script substitué qu'elle imprimera doit être `572fb78c…`.

## Note datée du 18/11/2026, écrite à 09:10:30 UTC : portée de « rien dans le cluster ni dans Zot » et de PT7

Relecture du conseiller. Le texte commité en `0158c9b` reste ; il se lit avec ces corrections.
- **« Rien écrit dans le cluster ni dans Zot » est une lecture, pas une mesure.** C'est le cas dans la note précédente, dans la ligne du README, dans la note de docs/03 et dans le message de commit. Les éléments lus :
  - l'étape ne lance que des commandes locales (yq, jq, oras sur des layouts locaux) et un `df` par ssh ;
  - elle n'appelle `kubectl` nulle part.

  Aucun relevé de Zot ni du cluster n'a été fait avant et après le passage. Cela vaut « (lecture) », comme FN9.
- **PT7 : le `df` ne mesure pas Zot.**
  - Relevé archivé à 09:10:08 UTC ([journal](m4b-zot-fs.log)) : `/var/lib/zot` n'a pas de montage dédié. Il est sur `/`, soit `/dev/vda1` en ext4 de 20 922 114 048 octets.
  - Les 338 518 016 octets de plus peuvent donc venir de tout le système de sc-stockage, pas seulement de Zot. Entre 09:07 et 09:10 UTC, sans écriture de la brique, l'occupation a encore pris 8 712 192 octets.
  - Le relevé de M2 de comparaison est « après l'envoi 2 » de `s1-fermeture.log`, et non « la fin de M2 ».
- **Conséquence.** `essai_tache` n'écrit pas dans Zot (lecture) : pas d'effet sur elle. En revanche, `publier`, `taches` et `rpm` écrivent dans Zot. Avant elles, il faudra relever la taille de `/var/lib/zot` elle-même (`du`, ce qui demande sudo ou l'utilisateur zot, à décider) en plus du `df`.

## Note datée du 18/11/2026, écrite à 09:18:20 UTC : `essai_tache` passée (« Oui »)

Passage du 18/11/2026 de 09:16:37 à 09:17:47 UTC, code 0 ([journal](m4b-essai_tache.log)). `m4b.sh` = `5e08bef0…`. État relu juste avant, à 09:16:33 UTC : ni journal, ni pod, ni PVC `m4b-05-essai-tache`, trois nœuds prêts (non archivé).

| # | Mesure | Verdict |
|---|---|---|
| ET1 | Scripts nominal et refusé : 3 lignes d'écart ; sha256 du nominal `572fb78c…`, le même que dans `prealables_taches` | Tenue |
| ET2 | Pod admis en dry-run serveur ; prêt sur `sc-build`, `runtimeClassName` vide (runc) | Tenue |
| ET3 | Nominal : 222 rpm téléchargés et contrôlés ; empreinte conforme (gpg) ; `rpm -K` 222 OK sur 222 ; `repomd.xml` `239a5a71…`, contrôle passé ; manifeste `f0ccf105…` ; 230 fichiers, 317 984 334 octets ; code 0 ; pas de 17 s | Tenue |
| ET4 | Résultat `{"uri":"oci://sc-stockage.poc.test:5000/essais-05/rocky9-bootstrap","digest":"sha256:f0ccf105…"}` | Tenue |
| ET5 | Arbre égal à celui de `final` | Tenue |
| ET6 | Cas refusé : `repomd.xml` calculé `239a5a71…`, puis « repomd.xml différent de l'attendu (fixé par la pipeline) », code 1 ; ni dossier `dir:` ni résultat | Tenue |
| ET7 | Retrait du pod code 0, PVC `m4b-05-essai-tache-w` retirée, aucun pod ni PVC restant | Tenue |
| ET8 | Rien écrit dans Zot | Lecture seulement (aucun relevé de Zot avant et après) |

**Ce que cela établit** : le script de `prefetch-rpm`, substitué comme il le sera, produit dans un pod neuf sous runc, sans root, au label de la tâche, la fermeture de `final` au fichier près. Il émet le résultat attendu pour Chains. Il refuse un `repomd.xml` qui n'est pas celui fixé par la pipeline, avant la copie de l'image.

**Ce que cela n'établit pas** :
- Tekton lui-même : substitution réelle, script d'environ 45 Ko passé au pod (`pkg/pod/script.go` à lire), workspace en PVC, chemin réel du résultat, admission d'un pod de TaskRun ;
- `publier-fermeture` dans son pod sous 512 Mi ;
- l'envoi vers Zot.

Restent avant `taches` : `verrou` et `publier` de M4a (ordre consigné), puis la lecture de `pkg/pod/script.go` et la taille de `/var/lib/zot` elle-même ; chacune sur son accord.

## Note datée du 18/11/2026, écrite à 09:27:06 UTC : passage du script de `prefetch-rpm` dans un pod de Tekton (`pkg/pod/script.go`)

Point « à lire avant `taches` » de la note de 22:59:14 UTC le 17/11.

**Lecture** de `pkg/pod/script.go`, téléchargé au tag v1.15.5 depuis `raw.githubusercontent.com/tektoncd/pipeline` : 12 575 octets, sha256 `88c3ac71…`, copie sous `~/.cache/supply-chain-poc/05/tekton-v1.15.5-source/`.
- `placeScriptInContainer` code chaque script Linux en base64 (`encodeScript`). Le résultat est ajouté à `Args[1]` du conteneur d'initialisation `place-scripts`, lancé par `sh -c`. Ce script d'initialisation écrit le base64 dans un heredoc terminé par `_EOF_`, puis appelle `/tekton/bin/entrypoint decode-script`.
- Le script du pas est donc dans **un seul argument** d'`execve`, avec ceux des autres pas de la tâche (un seul pas ici).
- Un script qui commence par `#!` ne reçoit pas de préambule : c'est le cas de `prefetch-rpm`.

**Mesure** ([script](m4b-script-tekton.sh), [journal](m4b-script-tekton.log), 09:26:30 à 09:26:37 UTC) :
- Script substitué de 44 751 octets (`572fb78c…`, celui d'`essai_tache`). Son base64 fait 59 668 caractères. `Args[1]`, reconstruit au format lu, fait 59 848 octets. Le décodage local redonne le script, et `_EOF_` n'apparaît pas dans le base64.
- Sur sc-build : `getconf ARG_MAX` vaut 2 097 152. Un argument unique de 60 848 caractères passe à `sh -c` (code 0). La borne d'un argument unique est mesurée : 131 071 caractères passent, 131 072 échouent (« Argument list too long », code 126).
- Marge : environ ×2,19. Un script substitué jusqu'à 98 168 octets environ resterait sous la borne (calcul, non mesuré).

**Limites.** La mesure est faite par ssh sur l'hôte sc-build, pas dans un pod. Les pods en runc partagent le noyau de l'hôte (lecture), mais `place-scripts` dans un vrai TaskRun n'est pas mesuré : ce sera fait au premier PipelineRun de `rpm`. Le reste de `Args[1]` (préfixe de `place-scripts`, script de débogage) n'est pas lu en entier dans `convertScripts`. Ce point est clos pour la taille, sans bloquer `taches`.
