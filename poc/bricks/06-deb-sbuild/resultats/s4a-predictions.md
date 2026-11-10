# Brique 06, S4a : prédictions (écrites le 10/11/2026 de 22:58 à 23:10 UTC, avant toute exécution dans le cluster ou Zot)

Le script sera `s4a.sh`, écrit après ces prédictions. **Rien n'a été lu ni écrit dans le cluster, Zot ou les VM pour S4a.**

## Décisions et accords

- **Forme de S4a** : décision du propriétaire de 22:52:55 UTC, « Oui, retiens-les » (additif de 22:54 UTC du README). Les quatre recommandations sont celles de la note de 22:51 UTC, validées par le conseiller. Ce n'est un accord pour aucune mesure ni aucune écriture.
- **Liste du constructeur** : [`builder/paquets.txt`](../builder/paquets.txt), 199 paquets, 133 065 812 octets, tirés hors ligne (additif de 22:54 UTC).
- **Avec un accord nommé pour chaque étape** :
  - `taches` : écritures dans Zot, bundles sous `tekton/tasks/` et `tekton/pipelines/` (compte `poc-ecriture`). Le diff de `politique/porte/taches.yml` est soumis au propriétaire entre les deux passes, comme en F2 de la 03.
  - `reseau` : une NetworkPolicy de plus dans `builds`.
  - `pipeline` : deux PipelineRuns dans `builds`, l'un après l'autre ; écritures dans Zot par `publier-image` (`poc-images`) et par Chains (`poc-build`).
  - `provenance` et `comparaison` : lectures dans Zot, puis travail sur l'hôte.
- **Sans accord** : l'étape `prealables`, sur l'hôte seul (rendu des gabarits, contrôle de la liste contre `Packages`). Elle ne lit ni le cluster ni Zot.

## Lectures faites avant ces prédictions (hôte et dépôt, à sec)

- **Appels de mmdebstrap repris** :
  - racine : `s1.sh`, fonction `mm`, variante `minbase`, `--include` de sbuild, libsbuild-perl, mmdebstrap, uidmap et iproute2 aux versions épinglées, trois crochets (`useradd` du compte `constructeur` 1000, `subuid`, `subgid`) ;
  - chroot : `s2.sh`, étape `racine`, variante `buildd`, sans `--include` (D2 a) ;
  - `SOURCE_DATE_EPOCH=1789199741`, la date de l'InRelease (`Sat, 12 Sep 2026 07:55:41 UTC`), calculée comme dans `s1.sh` et `s2.sh`.
- **InRelease de l'instantané `20261105T000000Z`** (copie de S1 sur l'hôte, sha256 `0584fba3…`, signataires vérifiés en S1) : `Acquire-By-Hash: yes` ; `Packages.xz` `7778d3e3…` (9 678 380 octets) ; `Translation-en.xz` `800dd225…` (6 485 704 octets).
- **`Packages` de l'hôte égal octet pour octet à `xz -dc Packages.xz`** : le rapprochement de `paquets.txt` porte donc bien sur l'index contrôlé.
- **Racine de S1** (`f8f221ca…`), indice et non preuve pour l'amorce : elle contient `usr/lib/apt/apt-helper`, `usr/bin/sqv`, `usr/bin/xz` et le crochet `usr/share/mmdebstrap/hooks/file-mirror-automount/`.
- **`apt-helper download-file`** (apt 3.0.3, `cmdline/apt-helper.cc`, lu au tag) : paires URI et cible, puis un hash facultatif de la forme `SHA256:<hex>`, passé à `pkgAcqFile`. Aucune vérification de root dans la commande.
- **Double publication** : en F2 de la 03, deux PipelineRuns ont publié le même digest avec un compte en création seule (`poc-fermetures`), les deux avec succès ([`f2-prefetch.log`](../../03-deps-closure/resultats/f2-prefetch.log)). `poc-images` a les mêmes droits sur `builds/**`.
- **`publier-image`** : `image.tar` à la racine de son workspace, un seul `digest` dans `index.json`, dépôt sous `builds/` sans tag.
- **Admission** : `images-zot-par-digest` (08c) accepte toute image du Zot du PoC par digest ; le test 2 interdit volumes, `hostNetwork` et jeton dans le podTemplate, et exige des bundles signés.
- **Invariant réseau de la 08** (`construction.sh`, `politique_sans_sortie`) : aucune NetworkPolicy de `builds` n'autorise de trafic.

## Conception (tirée des choix retenus, détails de mise en œuvre)

Pipeline `builder-sbuild`, signée, publiée en bundle, créée par le script de l'hôte (pas de webhook ni de rattrapage).

1. **`prefetch-deb`** (runc, Pod Security restricted, UID 65532, image : l'amorce par digest). Sortie réseau : `prefetch-deb-sortie`, déjà appliquée (DNS, adresses publiques en 80).
   - Entrées fixées dans la pipeline signée : l'URL de l'instantané, le sha256 de l'InRelease, la liste (sha256, taille, chemin dans le pool). Aucune lecture de Zot ni de Forgejo.
   - Chaîne d'intégrité : sha256 épinglé de l'InRelease, puis sha256 de `Packages.xz` et de `Translation-en.xz` lus dans l'InRelease, puis sha256 de chaque `.deb` selon la liste. Chaque fichier est téléchargé par `apt-helper download-file` avec son hash.
   - Sortie : un miroir partiel dans le workspace (`dists/trixie/InRelease`, les deux index à leur chemin et sous `by-hash/SHA256/`, `pool/…`).
   - Résultat `INSTANTANE_ARTIFACT_INPUTS` : l'URL de l'InRelease et son sha256.
2. **`construire-builder`** (Kata privilégié, root, image : l'amorce par digest, aucune sortie réseau).
   - Le miroir est relu en lecture seule et revérifié (mêmes sha256).
   - Les 20 paquets `deb amorce` sont installés par `dpkg -i` : mmdebstrap 1.5.7 et ses dépendances.
   - mmdebstrap construit la racine puis le chroot sur le miroir `file://`, avec le crochet `file-mirror-automount`.
   - Écarts voulus avec S1 et S2 : miroir `file://` ; crochet qui fixe `etc/hostname` (`sbuild`) et vide `etc/resolv.conf` ; crochet qui réécrit `etc/apt/sources.list` à la ligne de l'instantané utilisée en S1 ; listes d'apt nettoyées (pas de `--skip=cleanup/apt/lists`, car leurs noms dériveraient du chemin du miroir).
   - Layout OCI écrit à la main : couche 1 = l'archive racine telle quelle ; couche 2 = une archive qui contient le chroot sous `opt/sbuild/trixie-amd64.tar` (même commande `tar` que `s1.sh`, `etape_image`) ; configuration `linux/amd64`, `PATH`, `HOME=/w/home` comme en S1 ; un seul manifeste. `image.tar` est écrit dans le PVC, et chaque intermédiaire est supprimé dès qu'il est consommé.
   - Témoin TCP vers l'instantané en 80, qui doit échouer.
3. **`publier-image`**, inchangée (digest approuvé `d21931f3…`), vers `sc-stockage.poc.test:5000/builds/builders/sbuild-debian13`.

Réseau : une NetworkPolicy `builder-sans-sortie`, entrée et sortie, sans aucune règle, qui ne sélectionne que `tekton.dev/task: construire-builder`. `builds-sans-internet` et son `NotIn` restent inchangés.

PipelineRun : compte `build`, podTemplate du gabarit `sample-app`, `taskRunSpecs` avec `runtimeClassName: kata` pour la tâche `construire` seule, workspace en `volumeClaimTemplate` de 2 Gio.

## Prédictions

### Étape `prealables` (hôte)

- **A1.** Les trois gabarits et la pipeline se rendent sans variable `@…@` restante. Chaque ligne de la liste rendue dans la pipeline correspond à une entrée du `Packages` contrôlé (nom, version, architecture, sha256, taille, chemin).

### Étape `taches`

- **A2.** `prefetch-deb` et `construire-builder` sont signées par `tkn`, publiées en bundles. Leurs digests manquent d'abord à la liste revue (premier passage en `SIGNER=1`), puis y figurent après la revue du propriétaire. La pipeline est signée et publiée à chaque passage.

### Étape `reseau`

- **A3.** Après application, une seule NetworkPolicy sélectionne `construire-builder`, en entrée et en sortie. Aucune NetworkPolicy de `builds` n'autorise de trafic. Aucune CiliumNetworkPolicy de `builds` n'autorise de trafic à `construire-builder` (évaluateur `selecteurs.jq`).

### Étape `pipeline`, premier PipelineRun

- **A4. `prefetch-deb` en runc restreint, non root, réussit.** C'est le risque principal de S4a : rien n'a été mesuré en non root. `apt-helper` est présent dans l'amorce, télécharge en 80 et refuse un hash faux. Prédiction moyenne. Si elle échoue, l'étape s'arrête, et le repli (par exemple `Dir::*` détournés pour apt) demande une nouvelle prédiction et un accord.
- **A5.** Le miroir contient 199 `.deb`, 133 065 812 octets, plus l'InRelease (`0584fba3…`) et les deux index à leur chemin et sous `by-hash`.
- **A6. `dpkg -i` des 20 paquets réussit hors ligne dans l'amorce.** La complétude de cette liste n'est pas confirmée : `install.log` n'a pas été rapatrié en S1. Prédiction moyenne.
- **A7. mmdebstrap construit la racine et le chroot depuis le miroir `file://`, sans réseau.** apt vérifie l'InRelease du miroir avec le trousseau de l'amorce. Prédiction moyenne : le manuel ne le dit pas pour `file://`.
- **A8.** Les paquets installés (`dpkg/status`, champs `Package`, `Version`, `Architecture`, `Status`) sont ceux de la racine de S1 (166) et du chroot de S2 (122).
- **A9.** Le témoin TCP de `construire-builder` échoue (code non nul, délai ou refus).
- **A10.** Le pic du tmpfs reste sous 4 Gio, et le pod sous sa limite de 6 Gio. Le pod n'est pas tué pour mémoire.
- **A11.** `publier-image` publie sous `builds/builders/sbuild-debian13@sha256:<D1>` et relit le digest en lecture anonyme. Le PipelineRun réussit.
- **A12.** Les pods de `prefetch-deb` et de `publier` tournent sous runc ; celui de `construire` sous Kata. Tous sur sc-build.

### Second PipelineRun

- **A13. Deux exécutions donnent le même digest `D1`, bit pour bit**, grâce aux crochets `hostname` et `resolv.conf` et à `SOURCE_DATE_EPOCH`. La seconde publication réussit, comme en F2.
- **A14.** **Aucune égalité n'est attendue** avec les archives de S1 et S2 (`f8f221ca`, `e0b1f37c`) : `hostname`, `resolv.conf` et les listes d'apt diffèrent par construction.

### Étapes `provenance` et `comparaison`

- **A15.** Chains signe le PipelineRun. La provenance a pour sujet `builds/builders/sbuild-debian13@D1`, `buildType` `slsa-tekton`, et `resolvedDependencies` contient l'amorce, l'InRelease (`0584fba3…`), la pipeline et les bundles des tâches. La vérification par cosign avec la clé de Chains réussit ; une autre clé est refusée.
- **A16.** Sur l'hôte : le digest de la couche 1 est le sha256 de l'archive racine ; le chroot extrait de la couche 2 a le sha256 imprimé par la tâche ; les `diff_ids` égalent les digests des couches.
- **A17.** `sbuild` et `mmdebstrap` de l'image sont aux versions épinglées ; le compte `constructeur` (1000) et ses plages `subuid` et `subgid` sont présents.

## Hors S4a

- L'usage de l'image par sbuild : S4d.
- Un `.deb` altéré dans le miroir, et un InRelease au mauvais sha256 : tests négatifs de S5.
- La porte ne juge pas cette pipeline : `fermeture_plateforme` ne s'y applique pas, succès à vide.
- `prefetch-deb` lira en S4b sa liste dans le workspace, posée par une tâche qui lit Zot ; en S4a, elle la reçoit en paramètre fixé par la pipeline.

## Note datée du 10/11/2026, 23:03 UTC

**Correction d'heure** : l'en-tête annonce une rédaction « de 22:58 à 23:10 UTC ». Le fichier a été écrit et commité à 22:58 UTC (`7b7e5d8`). « 23:10 » était une estimation, pas une heure relevée.

**Résultat de l'étape `prealables`** (hôte seul, sans accord, comme prévu) : de 23:02:39 à 23:03 UTC, deux passages en échec puis un passage au code 0. Journal du dernier passage : [`s4a-prealables.log`](s4a-prealables.log).
- **Premier échec (23:02:39 UTC)** : `PyYAML` est absent de l'hôte, et le contrôle des YAML a été sauté.
- **Deuxième échec (23:03:04 UTC)** : yq a refusé la pipeline rendue. Le rendu remplaçait aussi le `@LISTE@` cité dans le commentaire d'en-tête. Le script a été corrigé : seules les lignes hors commentaire sont rendues, et la lecture par yq est désormais contrôlée.
- **Dernier passage** : le contrôle de la liste échouait sur le saut de ligne final ajouté par yq. Après correction, code 0.

**A1 : tenue.** Ce que le dernier passage établit :
- les 199 paquets sont rapprochés du `Packages` contrôlé, sans écart ;
- les 20 paquets de l'amorce sont retrouvés dans la liste ;
- les trois YAML se lisent ;
- la liste rendue dans la pipeline est identique, pour `prefetch` comme pour `construire` ;
- aucune variable ne reste dans le rendu.

## Note datée du 10/11/2026, 23:09 UTC : relecture du conseiller avant `taches`, prédictions précisées (rien lancé)

Le conseiller a relu S4a écrit à sec. Deux corrections ont été faites dans `construire-builder.yaml` avant toute signature, et trois relevés deviennent des contrôles dans `s4a.sh`. Cette note précise les prédictions sans réécrire celles du haut.

**A9 précisée.** Les deux témoins du haut (nom et adresse de Fastly en 80) échoueraient aussi sans `builder-sans-sortie`, à cause de `builds-sans-internet`. Ils ne prouvaient donc pas la politique. Témoins ajoutés, qui doivent tous échouer :
- le DNS seul (`getent hosts snapshot.debian.org`) ;
- Zot (`192.168.161.13:5000`) ;
- Forgejo (`192.168.161.13:3000`).

`builds-sans-internet` seule laisse ces trois cibles ouvertes. L'adresse publique est gardée, et le code d'échec est relevé (124 pour un délai).

**A10 précisée.** Le relevé après chaque appel de mmdebstrap manquait le pic réel, pendant la construction du chroot. Un échantillonneur relève maintenant `du -sm /w` chaque seconde, dans `/tmp`, et la tâche imprime le maximum et `memory.peak` du cgroup s'il existe. Prédiction inchangée : pic sous 4 Gio.

**A11 précisée.** `publier-image` n'a pas de `resources`. Tekton lui applique donc les valeurs par défaut de la 08c (`tekton-defauts.yaml`) : limite de 512 Mio de mémoire et de 1 CPU, sans limite d'`ephemeral-storage`. Aucun `LimitRange` n'est versionné pour `builds`. Elle déballera environ 860 Mo dans un `emptyDir` sur disque, ce que la voie image n'a jamais fait à cette taille. Prédiction moyenne : réussite, le cache de pages étant récupérable. Un échec par manque de mémoire remettrait en cause « `publier-image` inchangée », et ce choix reviendrait au propriétaire.

**A12, A16 et A17 deviennent des contrôles** (`attendu`) :
- A12 : `runtimeClassName` vide pour `prefetch-deb` et `publier-image`, `kata` pour `construire-builder`, nœud sc-build ;
- A16 : sha256 du chroot intérieur égal à celui du journal de `construire` ;
- A17 : versions des cinq paquets inclus égales à `INCLURE`.

**Fait à signaler à la revue de `taches.yml`.** Ce fichier est la liste `trusted_tasks` de la porte (`porte/policy.yaml`). Y inscrire `construire-builder`, tâche privilégiée et root, la rend acceptable dans toute provenance que la porte juge, pas seulement dans `builder-sbuild`. Il en va de même pour `prefetch-deb`.

**Pour S4d, non bloquant.** Les listes d'apt sont maintenant nettoyées dans le chroot. Les `--chroot-setup-commands` de S3 suppriment deux listes par leur nom exact : il faudra vérifier si elles échouent sur des fichiers absents.
