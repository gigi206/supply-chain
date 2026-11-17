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
