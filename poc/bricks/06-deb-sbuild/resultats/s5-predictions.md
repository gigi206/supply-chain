# Brique 06, S5a : prédictions (11/11/2026, 21:24 UTC, avant tout lancement)

Décision du propriétaire du 11/11/2026, 21:14:51 UTC : « Oui, les trois ». Elle porte sur trois points :
- découpage en **S5a**, les tests négatifs N1 à N7, et **S5b**, le rejeu de zéro, qui devient un jalon de plateforme à part ;
- **fermeture altérée poussée dans Zot** sous `entrees/sample-app-deb/fermeture-alteree`, avec un accord nommé par poussée ;
- **pods d'essai N4 et N6 gardés** dans S5a.

Carte : README, additif de 21:13 UTC. Script : [`s5.sh`](../s5.sh).

## Contrôles déjà faits sur l'hôte (21:18 à 21:23 UTC, hors ligne, rien sur le cluster ni dans Zot)

- **Copie de la fermeture deb de S4b** (`s4b-06/comparaison/deb`) : elle est conforme au verrou, avec 162 paquets (sha256, taille, chemin), 167 fichiers et aucun autre fichier dans le pool.
- **Layout local de cette copie**, poussé par la commande de `publier-fermeture` (03) avec oras 1.3.6 : il donne `sha256:bb7599a2…`, **le digest de la fermeture en service**.
- **Fermetures altérées**, chacune différant de l'intacte par une seule couche :
  - `paquet-modifie` : `sha256:a549729d…`, 167 couches. Le dernier octet de `pool/main/g/gcc-defaults/g++-x86-64-linux-gnu_14.2.0-1_amd64.deb`, le plus petit paquet (1200 octets), est modifié. La taille reste la même et la couche nouvelle est `446f8518…`.
  - `paquet-en-trop` : `sha256:b27225cf…`, 168 couches. Le fichier ajouté est `pool/main/s/s5-en-trop/s5-en-trop_1.0_all.deb` (34 octets, couche `8d7089f9…`).
- **`debian/rules` du paquet témoin de N6**, joué sur l'hôte par `make` : la ligne de connexion et la liste des interfaces s'exécutent. Depuis l'hôte, la connexion à Zot réussit (code 0).
- **Rendu des 13 TaskRuns, 2 PVC et 2 pods** avec des références factices :
  - hash faux : le dernier chiffre est changé ;
  - InRelease faux : le premier chiffre est changé ;
  - `subPath` conformes ;
  - Kata posé sur `construire-builder` et sur `n7-kata`, absent de `n7-hors-kata`.

## Prédictions

**`prealables`** (lecture de l'API et de Zot, hôte, admission à blanc côté serveur)
- P1. Les pipelines `builder-sbuild@a9d48331` et `sample-app-deb@82c8373d`, exportées de Zot, référencent quatre tâches qui sont toutes dans la liste revue. Leurs paramètres sont ceux attendus, et la liste de `builder-sbuild` égale les colonnes 4 à 6 de `builder/paquets.txt`. L'image de `prefetch-deb` est l'amorce `7378260c…`. Confiance haute.
- P2. Les 13 TaskRuns, les 2 PVC et les 2 pods sont admis à blanc côté serveur, Kyverno compris. Confiance moyenne : c'est la première fois que la plateforme reçoit un TaskRun isolé, et la règle `tekton-references`, lue, l'admet.
- P3. Il n'existe aucun objet `s5` dans `builds` ni de dépôt `fermeture-alteree` dans Zot. Les enveloppes sont au nombre de 8 sur le deb et de 28 sur sample-app ; celles de la fermeture et de l'image de build sont relevées.

**`zot`** (écriture, accord nommé)
- P4. Les deux fermetures altérées sont relues dans Zot en lecture anonyme, avec les digests `a549729d…` et `b27225cf…`. Confiance haute.

**`prefetch`**
- P5. **N1 témoin** réussit, et son pod porte `tekton.dev/task: prefetch-deb`, posé par Tekton depuis le nom de la tâche résolue (lu dans `storeTaskSpecAndMergeMeta`, Pipelines v1.15.5). La sortie `prefetch-deb-sortie` s'applique donc. Confiance haute.
- P6. **N1 hash faux** échoue sur « téléchargement refusé » : c'est **apt-helper** qui refuse, pas le `sha256sum` du shell, qui n'est pas atteint. Le journal d'apt-helper contient « Hash Sum mismatch ». Confiance moyenne pour le libellé, haute pour la barrière. Si c'est « sha256 différent » qui apparaît, A4 reste non mesurée.
- P7. **N2 InRelease au mauvais sha256** échoue sur « téléchargement refusé : dists/trixie/InRelease », sans aucun index téléchargé. Ce test ne lève pas la réserve de A7. Confiance haute.

**`miroir`**
- P8. Le prefetch complet réussit sur `s5-miroir`, comme en S4a. Le pod d'essai runc fait deux copies par liens durs, de même taille que l'original : `.deb` altéré dans l'une, InRelease altéré dans l'autre (`Origin: Debiam`). Le miroir intact reste intact. Confiance haute.
- P9. **N3** : `construire-builder` sous Kata refuse de deux façons, par la revérification de la tâche, avant tout apt :
  - copie au `.deb` altéré : « paquet altéré : <chemin> » ;
  - copie à l'InRelease altéré : « InRelease du miroir différent ».

  Confiance haute.
- P10. **N3 témoin** : `construire-builder` sur le miroir intact réussit, avec `DIGEST_CONSTRUIT` = `sha256:749d746c…`, le digest de S4a, sans rien publier. Confiance moyenne-haute : la tâche fixe le nom d'hôte, donc le nom du pod ne compte pas, mais le TaskRun isolé et le PVC partagé n'ont jamais été mesurés.
- P11. **N4, apt seul** (réserve de A7), dans le pod d'essai, depuis `file:` sans `trusted=yes` :
  - miroir intact : `update` en code 0 avec les index, puis téléchargement du paquet témoin ;
  - InRelease altéré : `update` en échec et aucun index, car apt refuse la signature ;
  - `.deb` altéré : index acceptés, puis téléchargement refusé avec « Hash Sum mismatch » et aucun fichier.

  Confiance moyenne : apt sans root et `apt-get download` depuis `file:` ne sont pas mesurés. Si le témoin échoue, N4 ne prouve rien et la réserve reste ouverte.

**`fermeture`**
- P12. **N5 témoin** : `preparer-deb` sur la vraie fermeture réussit, avec « 162 paquets ». Ses entrées restent sur `s5-entrees` pour N7. Confiance haute.
- P13. **N5 `paquet-modifie`** : le tirage par digest réussit (oras ne voit rien d'anormal), puis la tâche refuse avec « paquet différent du verrou : pool/main/g/gcc-defaults/g++-x86-64-linux-gnu_14.2.0-1_amd64.deb ». Confiance haute.
- P14. **N5 `paquet-en-trop`** : le tirage réussit, puis la tâche refuse avec « pool : 163 fichiers, 162 dans le verrou ». Confiance haute.
- Rappel : apt ne protège pas ici. sbuild prend les paquets par `--extra-package` sans contrôle de hash. La barrière de N5 est la seule, avec la revérification de `construire-deb` en second.

**`kata`**
- P15. **N7 hors Kata** : `False|PodAdmissionFailed`, avec un refus de Pod Security « violates PodSecurity "restricted:latest": privileged… », sans aucun pod, comme en J7 de la 08. Confiance haute.
- P16. **N7 témoin sous Kata** réussit sur sc-build : deb `0b489d43…`, `DIGEST_CONSTRUIT` = `sha256:039949f9…`, rien n'est publié. Confiance haute.

**`sbuild`**
- P17. **N6** : depuis le pod d'essai Kata, hors de `construction-deb-sans-sortie`, la connexion TCP à Zot (`192.168.161.13:5000`) réussit, en code 0. C'est le témoin, permis par `builds-sans-internet` seule. Depuis `debian/rules`, sous sbuild `--chroot-mode=unshare`, la même connexion échoue, et la seule interface visible est `lo`. Confiance moyenne-haute : l'espace de noms réseau sans interface est le comportement par défaut de sbuild en mode unshare, lu dans le manuel et non mesuré. Le code de sbuild lui-même n'entre pas dans la mesure.

**`porte`** (invariance)
- P18. Aucune enveloppe nouvelle sur le deb (8), sample-app (28), la fermeture ni l'image de build. Aucun TaskRun de S5a n'a de sujet : seuls les résultats `IMAGE_URL`/`IMAGE_DIGEST` en donnent un, et `publier-image` ne tourne jamais. Confiance moyenne : ce que fait Chains d'un TaskRun sans sujet en stockage `oci` n'est pas mesuré. L'annotation `chains.tekton.dev/signed` des TaskRuns est relevée, sans prédiction.
- P19. La provenance la plus récente du deb reste celle du chemin 2 de S4d3 (`454728c5…`). Verdicts de S4d3 :
  - deb : `ec` sans violation, `trusted_task.tagged`, horodatage 8/8, VSA et scan refusés ;
  - sample-app : horodatage 28/28, VSA et scan ok.

  Confiance haute.

**`retirer`** : il ne reste aucun objet `s5` dans `builds`. Rien n'est retiré de Zot.

## Ce que S5a ne mesure pas

- Le rejeu de zéro : c'est S5b.
- Une altération du blob dans le stockage de Zot : le refus d'oras est mesuré par la brique 03 (« mismatched digest »).
- La coupure du réseau au niveau du pod de construction : elle est mesurée à chaque construction par les témoins de `construire-deb` et de `construire-builder`, et S5a ne la compte pas.
