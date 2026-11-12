# Brique 06, S6a, pod d'essai du mode deb : prédictions (12/11/2026, rédigées à partir de 09:09:35 UTC, avant toute mesure)

Préparées sur « continue » (cadre : à sec, rien lancé). L'heure est celle de `date -u` au début de la rédaction ; l'heure du commit fait foi.

**Rien n'est lancé.** L'étape `essai` de [`s6a.sh`](../s6a.sh) écrit dans le cluster (une ConfigMap et un pod, supprimés ensuite) : elle attend un **accord nommé**, comme tout pod d'essai (processus allégé, levier e). Commande, depuis la racine du dépôt :

```
mise exec -- poc/bricks/06-deb-sbuild/s6a.sh essai
```

Journal : `s6a-essai.log`.

## Le correctif, préparé à sec

[`s6a-scanner-deb.patch`](../s6a-scanner-deb.patch) modifie `poc/bricks/07a-sbom-grype/politique/scanner.sh`. **Il n'est pas appliqué à l'arbre de travail** : `rejeu.sh` déploie `scanner.sh` par la ConfigMap `scan-config` (`cm_scan` de la 07a, étape G4), et S5b doit déployer le script tel qu'il est aujourd'hui (sha256 `e744344f…`, blob git `e4bf10bd`). Il s'appliquera après S5b, comme `g5-porte.patch` en G5 de la 07a. `git apply --check` passe sur l'arbre de travail à 09:09 UTC ; `sh -n` passe sur le résultat, avec le `sh` de bash et celui de busybox de l'hôte.

Ce qu'il change :
- **Nouvelle fonction `artefact`**, tirée d'`analyser` : l'image est lue par digest, puis le SBOM de l'artefact seul est écrit dans `sbom-image.json`. `analyser` l'appelle à la place de ses trois lignes d'aujourd'hui (`oras cp`, contrôle du digest, `syft oci-dir:`), qui y sont reprises telles quelles. C'est aussi un mode du script, pour le pod d'essai ; le job ne l'appelle pas directement.
- **`NATURE`** : `image` par défaut, qui reprend le chemin d'aujourd'hui ; `deb`, qui passe par `extraire_deb` puis `syft dir:` sur le contenu extrait ; toute autre valeur donne un refus, code 2.
- **`extraire_deb`**, en échec fermé à chaque pas :
  - le manifeste doit avoir une seule couche, en `application/vnd.oci.image.layer.v1.tar` ;
  - la couche ne doit contenir qu'un fichier, en `.deb` ;
  - extraction avec `ar -x` (forme à tiret, admise par GNU ar et par busybox), puis `unxz -c` ou `gunzip -c`, puis `tar -xf`. Je n'utilise pas `tar -J`, dont la prise en charge par busybox n'est pas relevée ;
  - un `data.tar` en zstd est refusé, puisque busybox n'a pas zstd (P2 du relevé 1) ;
  - lignes `DEB|` (nom, sha256, taille) et `EXTRAIT|` (nombre de fichiers) au journal.
- **Plancher**, dans les deux natures : au moins une PURL versionnée dans le SBOM de l'artefact seul, sinon refus, code 1.
  - Le compte porte sur les occurrences (`grep -o … | wc -l`), pas sur les lignes. Le relevé 1 montre que syft écrit le JSON sur **une seule ligne** : `grep -c` donnerait au plus 1.
  - Le motif est vérifié sur les SBOM du relevé 1 : 2 PURL versionnées pour l'artefact du deb, 0 pour le dossier vide, 3 pour la source.

**Deux écarts aux conséquences écrites après le relevé 1**, à ton jugement :
1. **Le plancher est générique**, « au moins une PURL versionnée », et non « au moins un `pkg:golang/` versionné ». Le mode deb ne devient pas propre au Go, et pour ce deb le résultat est le même.
2. **Le plancher s'applique aussi à la voie image.** Une fois le correctif appliqué, c'est un changement de comportement du scan de sample-app. Il durcit le même angle mort, et le cas D le vérifie avant toute application.

## Le pod d'essai

- Le correctif est appliqué à une **copie** de `scanner.sh`, sous `~/.cache/supply-chain-poc/06/s6a/essai`.
- L'étape s'arrête avant toute écriture si un pod de l'espace `scan` est actif (`Running` ou `Pending`), par exemple le CronJob `scan-sample-app` de 09:30 UTC.
- **ConfigMap `essai-s6a`** dans l'espace `scan` : la copie corrigée et la CA du PoC.
- **Pod `essai-s6a`** :
  - image `outils-scan@7eb4f26e`, sur le nœud de confiance ;
  - mêmes restrictions que les pods d'essai de la 07a, sans compte de service monté, sans jeton ni identifiant ;
  - mémoire de 512 Mi demandée et 2 Gi au plus, comme `analyser` ; volume de travail de 1 Gi ;
  - Zot lu en anonyme, sans aucune écriture.
- Pod et ConfigMap sont supprimés à la fin, et aussi en cas d'échec (`trap`). Leur absence est contrôlée.
- La sortie du pod est filtrée de `jeton|token`, et le nombre de lignes filtrées est journalisé.

## Prédictions

- **E0, outils.** busybox donne sa version. `ar`, `tar`, `unxz`, `gunzip` et `sha256sum` sont présents. Confiance haute (P2).
- **E1, cas A, `NATURE=deb` sur `builds/sample-app-deb@039949f9`.** Code 0, avec trois lignes :
  - `DEB|sample-app_1.0.0-1_amd64.deb, sha256 0b489d43…, 1952080 octets` ;
  - `EXTRAIT|3 fichiers` ;
  - `ARTEFACT|deb, 2 PURL versionnées` (chi et stdlib, comme en P4).

  Confiance moyenne, sur trois points non relevés : la forme de `ar -x` dans ce busybox ; la lecture par le `tar` de busybox des en-têtes pax de la couche (`--format=posix`) ; sa lecture du `data.tar` de dpkg-deb. Chacun refuserait, sans faux succès.
- **E2, cas B, `NATURE=deb` sur l'image de sample-app.** Refus, code 1, avec « une couche attendue » ou « couche tar non compressée attendue ». Je ne prédis pas lequel : je n'ai pas relevé les couches de l'image. Confiance haute pour le refus.
- **E3, cas C, `NATURE=image` sur le layout du deb.** Refus, code 1, par le plancher : « aucune PURL versionnée … (image) ». C'est le témoin négatif du plancher sur un vrai artefact, qui fait voir le masquage du constat 3 de la carte. Confiance moyenne : syft pourrait échouer avant, sur une configuration sans `Cmd`, ce qui donnerait aussi le code 1 mais un autre message.
- **E4, cas D, `NATURE=image` sur l'image de sample-app.** Code 0, `ARTEFACT|image` avec au moins une PURL versionnée. Je ne prédis pas le nombre. Confiance haute : le binaire Go porte au moins la stdlib.
- **E5, cas E, `NATURE=autre`.** Code 2, « nature inconnue : autre ». Confiance haute.
- **E6, effets.**
  - Pod et ConfigMap `essai-s6a` absents à la fin.
  - Le sha256 de `scanner.sh` de l'arbre reste `e744344f…`.
  - Rien d'écrit dans Zot.
  - Le pod finit en moins de 300 s. Confiance moyenne pour la durée : c'est le délai d'attente du script, et le cas D lit toute l'image.

## Hors de cet essai

- La valeur de `NATURE` dans `scan-job.yaml` et `rendre_scan` ; le CronJob `scan-sample-app-deb` décalé ; le timer de fraîcheur sur deux dépôts ; le témoin positif : tout cela vient après S5b et le relevé du 21/11 (ordre c).
- grype et la base dans le pod ; la fusion avec la source. Ils sont mesurés sur l'hôte en P6 et P7, et le job les ferait comme pour l'image.
- La porte sur le deb (scan `ok` attendu).
- Le traitement des chemins `..` ou absolus d'un `data.tar` hostile par le `tar` de busybox. Ce n'est pas mesuré : le deb vient de la chaîne, et la porte vérifie sa provenance séparément.

## Note datée du 12/11/2026 (premier passage, 09:16:09 UTC)

Lancé par le propriétaire depuis le terminal. Le passage s'est arrêté à la création du pod : la politique Kyverno `limites-obligatoires` (08c, H5) l'a refusé avec « limites de mémoire et de CPU obligatoires ». Rien n'a donc tourné dans le cluster, aucune prédiction n'est jugée, et le journal est gardé dans `s6a-essai-premier-passage.log`.

- **Mon erreur** : j'ai repris les ressources du conteneur `analyser`, qui n'a pas de limite de CPU. La règle ne lit que les conteneurs principaux, pas ceux d'initialisation, et le pod d'essai n'a qu'un conteneur principal. J'ai aussi écrit plus haut « mêmes restrictions que les pods d'essai de la 07a », alors que ces pods sont antérieurs à H5 : la phrase ne vaut que pour le contexte de sécurité.
- **Correction** : le conteneur demande 100 m de CPU et 512 Mi de mémoire, avec une limite de 1 CPU et 2 Gi. Le cas D, qui lit toute l'image, peut en être ralenti ; la prédiction de durée E6 garde son délai de 300 s.
- **ConfigMap `essai-s6a`** : elle a été créée avant le refus. Le `trap` de sortie a dû la supprimer, mais je ne l'ai pas vérifié, puisque je ne lance `kubectl` qu'à travers les scripts. Le passage suivant la supprime d'abord, puis contrôle à la fin que le pod et la ConfigMap sont absents.
- Le script corrigé demande un nouvel accord.

## Résultats (second passage, 12/11/2026, 09:19:10 UTC, accord « Oui, relance-le »)

Journal : `s6a-essai.log`. Script : version avec la limite de CPU. Code 0 ; pod en `Succeeded` après 96 s.

| # | Résultat | Mesure |
|---|---|---|
| E0 | **Tenue** | BusyBox v1.37.0 ; `ar`, `tar`, `unxz`, `gunzip`, `sha256sum` sous `/busybox/` |
| E1 | **Tenue** | `DEB|sample-app_1.0.0-1_amd64.deb, sha256 0b489d43…, 1952080 octets` ; `EXTRAIT|3 fichiers` ; `ARTEFACT|deb, 2 PURL versionnées` ; code 0. `ar -x`, les en-têtes pax de la couche et `unxz -c` passent avec busybox. |
| E2 | **Tenue** | « deb : une couche attendue dans le manifeste », code 1 |
| E3 | **Tenue** | « aucune PURL versionnée dans le SBOM de l'artefact seul (image) », code 1. syft n'a pas échoué avant le plancher. **Le vide masqué du constat 3 de la carte est arrêté par le plancher, sur un vrai artefact.** |
| E4 | **Tenue** | `ARTEFACT|image, 2 PURL versionnées`, code 0 |
| E5 | **Tenue** | « nature inconnue : autre », code 2 |
| E6 | **Tenue** | Pod et ConfigMap absents à la fin, contrôlés. sha256 de `scanner.sh` de l'arbre inchangé (`e744344f…`). Durée : 96 s. Rien n'est écrit dans Zot : le pod n'avait aucun identifiant, mais je n'ai pas fait de relevé côté Zot. |

**ConfigMap du premier passage** : le second passage commence par `nettoyer`, qui supprime une ConfigMap restante sans rien journaliser. Je ne sais donc pas si celle du premier passage était encore là. Elle est absente maintenant.

**Pour la suite de S6a**, après S5b et le relevé du 21/11 (ordre c) :
- appliquer le correctif à `scanner.sh` ;
- passer `NATURE` dans `scan-job.yaml` et `rendre_scan` ;
- créer le CronJob `scan-sample-app-deb` décalé ;
- étendre le timer de fraîcheur à deux dépôts ;
- vérifier la porte sur le deb, où un scan `ok` est attendu.

Le plancher change aussi la voie image (écart 2) : E4 montre que sample-app le passe, avec 2 PURL versionnées.

