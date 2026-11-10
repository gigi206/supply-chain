# Brique 06, S2 : prédictions (écrites le 10/11/2026 à 15:50 UTC, avant toute exécution)

Le script est [`s2.sh`](../s2.sh). **Rien n'a été lu ni écrit dans le cluster, Zot ou les VM pour S2.**

## Accord

Le propriétaire a répondu « continue » à 15:43:21 UTC (transcription), après le push de 14:45:31 UTC. « Continue » n'autorise aucune action sur le cluster, Zot ou les VM. La préparation de S2 à sec est donc la seule suite engagée.

**Sans accord** : l'étape `buildinfo` tourne sur l'hôte seul, hors ligne, sous `unshare -rn`. Elle lit des fichiers déjà présents :
- l'`InRelease`, le `Packages.xz` et les clés de ftp-master, tirés par l'étape `prealables` de `s1.sh` le 10/11 à 13:04 UTC ;
- le journal de sbuild archivé, `s1b-relance-sbuild.log`.

**Avec un accord nommé pour chaque étape**
- `racine` :
  - un pod Kata privilégié, root, image d'amorce, dans `builds` sur sc-build, label `tekton.dev/task=prefetch-deb` ;
  - sortie vers `snapshot.debian.org` en http, par `prefetch-deb-sortie` (08c) ;
  - pod supprimé à la fin de l'étape.
- `fermeture` : **écriture définitive dans Zot** (compte `poc-ecriture`), dépôt `deps/sample-app/deb-buildinfo`, tags `s2` et `s2-bis`.
- `restauration` : lecture dans Zot, par digest.

## Lectures faites avant ces prédictions

- **Le `.buildinfo` de sample-app est déjà dans le dépôt.** sbuild l'imprime dans son journal, et `s1.sh relance` a archivé ce journal (`s1b-relance-sbuild.log`). En explorant, vers 15:46 UTC et avant d'écrire ces prédictions, je l'ai reconstitué une fois (premier bloc « Format: 1.0 » jusqu'à la première ligne vide) :
  - 5415 octets, sha256 `a2d1a419…` : la valeur que le `.changes` du même journal donne au fichier ;
  - 162 lignes dans Installed-Build-Depends ;
  - deb décrit : `0b489d43…`.

  Ces trois points sont **déjà observés, ce ne sont pas des prédictions**. L'étape `buildinfo` les refait et les journalise.
- `s1-06/Packages` (56 Mo) date de l'étape `prealables` de S1 (13:04 UTC) ; l'étape `buildinfo` le reprend depuis `Packages.xz`, revérifié.
- `closure.sh` (brique 03) pousse un fichier par couche, avec un manifeste déterministe (fichiers triés, date à `SOURCE_DATE_EPOCH`, 0 par défaut). En brique 03, deux envois du même répertoire ont donné le même digest.
- Le compte `poc-ecriture` a `read+create+update` sur `**` dans la configuration de Zot (`08-trust-plane/stockage/zot.json`). La plateforme range ses fermetures sous `builds/fermetures/**` (compte `poc-fermetures`, brique 03, décision du 03/11/2026). Le jalon S2 et le doc 02, §4, nomment `deps/sample-app/deb-buildinfo`. Le script suit le jalon ; la question 3 ci-dessous porte sur ce choix.

## Périmètre

- **D2 (a)** : le chroot de S2 est un `buildd` sans `--include`. Les dépendances de build viendront de la fermeture restaurée, en S3. Le chroot de S1, qui préinstallait debhelper, golang-go et nodejs, sert seulement à avoir produit le `.buildinfo`.
- **Fermeture** : tous les paquets de Installed-Build-Depends, y compris ceux déjà présents dans le chroot `buildd` (paquets essentiels). Leurs versions sont celles de l'instantané, donc les mêmes.
- **Pas de nouveau build en S2.** Le `.buildinfo` est celui de s1b (sbuild rc 0, 13:28 UTC).
- **Déduplication** : le jalon demande de la mesurer. Il n'existe qu'un `.buildinfo`, donc une seule fermeture. S2 mesure seulement une condition nécessaire : le digest de chaque couche est le SHA256 du `.deb` dans `Packages`. Une autre fermeture qui contient la même version partage donc le blob. **La déduplication entre deux fermetures n'est pas mesurée** (question 4).
- L'image sous `builders/` n'est pas dans ce script : étape à part, avec son accord.
- Le code de sortie sera relevé en lançant sous bash (`bash -c '…; echo "rc $?"'`), et non plus déduit de `chrono.tsv` comme pour E3.

## Prédictions

| # | Étape | Prédit | Confiance |
|---|---|---|---|
| Q1 | buildinfo | Trois signataires épinglés, `Packages.xz` conforme, aucune lecture du réseau (sous `unshare -rn`) | haute (mêmes fichiers qu'en S1) |
| Q2 | buildinfo | Les 162 paquets de Installed-Build-Depends sont tous présents une seule fois dans `Packages` (amd64 ou all), à la version exacte ; 162 distincts | haute : le chroot de S1 vient de cet instantané |
| Q3 | buildinfo | Taille de la fermeture entre 150 et 400 Mo | faible |
| Q4 | racine | `apt-get update` rc 0 par `prefetch-deb-sortie`, `InRelease` identique à celui de l'hôte | haute (mesuré en E3) |
| Q5 | racine | `chroot-a` et `chroot-b` ont le même sha256 | haute : le chroot de S1 est sorti identique à 1 h 30 d'écart (s1, s1c) |
| Q6 | racine | `apt-get download` rc 0 ; 162 fichiers ; tous conformes à la liste attendue après renommage de l'époque | moyenne : `apt-get download` en root avertit (téléchargement hors bac à sable de `_apt`) ; versions à époque et `+b1` non essayées |
| Q7 | racine | Les .deb de l'amorce, des deux chroots et de la fermeture sont tous conformes à `Packages` | haute |
| Q8 | racine | L'étape tient dans le tmpfs de 4 Gio et dure moins de 15 min | moyenne |
| Q9 | fermeture | Le second envoi donne le même digest que le premier | haute (brique 03) |
| Q10 | fermeture | 162 couches ; le digest de chaque couche est le SHA256 de `Packages` du fichier de même nom | haute (oras prend le sha256 du contenu) |
| Q11 | restauration | 162 fichiers restaurés par digest, tous conformes à la liste attendue | haute |
| Q12 | durée | S2 coûte au plus 0,5 pw, préparation comprise (depuis 15:43 UTC). S1 a coûté 0,5 pw. Brique estimée à 2 pw, décision à 4 pw | moyenne |

**Ce que S2 ne prouvera pas**
- que sbuild construit depuis cette fermeture, hors ligne : c'est S3 ;
- la déduplication entre deux fermetures ;
- le caractère bit-identique du deb.
