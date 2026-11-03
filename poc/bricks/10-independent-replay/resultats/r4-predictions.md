# R4, rebuild hors ligne : prédictions (écrites le 03/11/2026 vers 10:30 UTC, avant toute exécution)

Accord du propriétaire : « Préparer puis lancer ». Le lancement est automatique, **pas avant 14:00 UTC** : la fin du build est signée à 13:59:30 UTC le 02/11, plus 24 h. Aucun push.

## Déroulé (`JALON=r4 mise run replay -- rebuild`)

1. **Sur l'hôte** :
   - refus si moins de 24 h se sont écoulées depuis `finishedOn` ;
   - transport du bundle `preparer-entrees`, dont le digest est lu dans la provenance vérifiée en R3, et de `outils/rebuild.sh` ;
   - lancement détaché dans la VM (`systemd-run`), puis **lien coupé aussitôt** (`virsh domif-setlink … down`) ;
   - compteurs de l'interface relevés côté hôte juste après la coupure, puis 600 s plus tard, juste avant le rétablissement.
2. **Dans la VM** (`rebuild.sh`, en root), lien coupé :
   - refus si l'interface a encore sa porteuse ;
   - digest du bundle `preparer-entrees` comparé à la provenance vérifiée, et présence de ses trois opérations ;
   - contexte reproduit : `git archive` du commit, fermeture dans `deps`, `web-dist` dans `src/web/dist` ;
   - **image de build du domaine** construite : busybox de Debian, Go de go.dev, `Env` déclaré ;
   - **image reconstruite** avec le Dockerfile signé et les options de `buildctl`, seul le digest de l'image de build changeant ;
   - second moteur : `go build` direct, puis comparaison des binaires.

## Prédictions

1. **Délai** : plus de 24 h depuis la fin du build ; le lancement n'est pas refusé.
2. **Réseau** :
   - `porteuse_enp1s0=0` au départ de `rebuild.sh` ;
   - compteurs de l'hôte **identiques** entre la coupure et le rétablissement (aucun octet, aucun paquet) ;
   - rebuild terminé **avant** le rétablissement du lien.
3. **Recette de `preparer-entrees`** : digest `OK`, et trois opérations `OK`.
4. **Contexte** : commit `6391fd43…`. Les nombres de fichiers de la fermeture et de `web/dist` sont consignés, sans valeur prédite.
5. **Image de build du domaine** : son digest est **différent** de `d50ae575…`, l'image déclarée. L'archive de go.dev contient des fichiers absents du module de toolchain (tests, `api`, `misc`, documentation), et le busybox vient d'un autre paquet. Le digest est consigné, pas comparé.
6. **Image reconstruite** : **`sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5`**, égale au sujet de la provenance, d'où le verdict `PASSED`. C'est la prédiction centrale de la brique. Elle s'appuie sur la brique 04 : même image avec BuildKit 0.25.2 et 0.34.1, et avec deux images de build différentes.
7. **Second moteur** : binaire de l'image = binaire du `go build` direct = **`e3749c68…`**, le binaire de la brique 04. Les options du `go build` sont identiques au `RUN` du Dockerfile signé.
8. **Durée** : rebuild complet en moins de 5 min, image de build du domaine comprise.

## Si une prédiction échoue

- **Image différente (6)** : verdict `FAILED`. Rien n'est poussé, les sorties sont gardées dans la VM pour un diffoscope en R5, et je m'arrête pour en décider avec le propriétaire.
- **Compteurs qui bougent, ou rebuild non terminé avant le rétablissement (2)** : le résultat n'est pas valable hors ligne, et je m'arrête.

## Limites

- Le code du domaine (`rebuild.sh`, `verifier_entrees.py`) est transporté par l'hôte. Son sha256 est journalisé et sera inscrit dans la VSA (politique, section 4 bis).
- Les tests négatifs (fermeture altérée : build refusé ; source altérée : digest différent, VSA `FAILED` non poussée, diffoscope) sont en R5, avec leurs propres prédictions.

## Additif du 03/11/2026, avant l'exécution (vers 10:30 UTC, relecture de l'advisor)

- **Options de build** : la fonction `build` de `poc/bricks/04-hermetic-repro/bench.sh` utilise exactement les options de la recette signée (`--frontend dockerfile.v0 --no-cache`, `SOURCE_DATE_EPOCH=0`, `type=oci,…,rewrite-timestamp=true`, contextes `builder` et `deps`). La brique 04 a produit `3a7ca1b1` avec BuildKit 0.25.2 : la prédiction 6 tient telle quelle.
- **Essai de coupure, sans build, sur la VM au repos** (prédiction écrite avant l'essai) :
  - pendant la coupure, la porteuse vue par l'invité passe à `0`, et ses compteurs `tx_packets` et `tx_bytes` ne bougent pas ;
  - côté hôte, la sortie de l'invité ne bouge pas. Je ne sais pas encore quel champ de `domifstat` la porte ; l'essai le calibre par une rafale sortante, lien établi ;
  - l'entrée vers l'invité (ARP, STP du pont) peut faire bouger un compteur sans que l'invité émette.
- **Critère révisé pour le rebuild** :
  - la **sortie** de l'invité est inchangée, côté hôte (champ calibré) comme côté invité (`tx_*` relevés par `rebuild.sh` au début et à la fin) ;
  - les mouvements d'entrée sont consignés, sans être comptés comme KO.

## Résultat de l'essai de coupure (03/11/2026, 10:30 à 10:32 UTC) : [`r4-essai-coupure.log`](r4-essai-coupure.log)

- **Porteuse** : `0` pendant toute la coupure, vue par l'invité ; `1` dès le rétablissement. Conforme.
- **Invité** : `tx_packets` et `tx_bytes` sont inchangés pendant la coupure (17479 et 1714745), et `rx_*` aussi. Conforme.
- **Calibrage de `domifstat`** : ses champs sont **vus de la VM**. Pendant la rafale descendante (environ 9,8 Mo), `rx_bytes` a augmenté de la même quantité que le `rx_bytes` de l'invité. `tx_*` correspond donc à **ce que la VM émet**.
- **Pendant la coupure, côté hôte** : `tx_*` est inchangé, mais `rx_packets` augmente de 34 paquets (3 852 octets), alors que l'invité ne reçoit rien. Ce sont des trames entrantes du pont, non délivrées. Comparer la ligne entière aurait donné un **faux KO**.

**Corrections de R4 avant le lancement** :
- le critère porte sur `tx_bytes` et `tx_packets` de `domifstat`, et sur `tx_*` de l'invité, relevés par `rebuild.sh` au début et à la fin ;
- l'attente hors ligne passe à 1 200 s ;
- un piège rétablit le lien si l'étape s'interrompt ;
- `verdict` et `fin_image` sont écrits dès que le digest de l'image est connu ; le second moteur, hors du verdict, ne peut plus l'empêcher ;
- le nettoyage de `~/r4` se fait par `sudo`, car `rebuild.sh` y écrit en root.
