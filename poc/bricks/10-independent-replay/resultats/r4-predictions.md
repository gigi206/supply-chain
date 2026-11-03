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
