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

---
## Résultats partiels (11/11/2026, de 21:25:12 à 21:31 UTC, accord « Oui, lance S5a »)

Étapes `prealables`, `prefetch`, `miroir` et `sbuild`. Rien n'est écrit dans Zot : l'étape `zot` attend son accord nommé. Journaux : `s5-prealables.log`, `s5-prefetch.log`, `s5-miroir.log`, `s5-sbuild.log`.

- **P1 à P3 : tenues.**
  - Les quatre tâches sont dans la liste revue, et la liste de `builder-sbuild` égale `paquets.txt`.
  - Les 16 objets sont admis à blanc ; le pod de N6 n'est rendu qu'au lancement.
  - Enveloppes de départ : deb 8, sample-app 28, fermeture 4, image de build 4.
- **P5 : tenue.** Le pod du TaskRun isolé porte `tekton.dev/task: prefetch-deb`, et le témoin télécharge son paquet.
- **P6 : barrière tenue, libellés réfutés.** C'est `apt-helper` qui refuse le hash faux (« E: Download Failed », « téléchargement refusé »), et le `sha256sum` du shell n'est pas atteint. **A4 est donc mesurée.** Les libellés sont réfutés de deux façons :
  - la raison du TaskRun est `StepFailed`, pas `Failed` ;
  - « Hash Sum mismatch » n'est pas dans les 5 dernières lignes que la tâche garde du journal d'`apt-helper`.
- **P7 : tenue**, même barrière, aucun index téléchargé. Même écart de raison (`StepFailed`).
- **P8 : tenue.** 199 paquets en 18 s. Les copies altérées ont la même taille que l'original, et le miroir intact est inchangé.
- **P9 : tenue.** Sous Kata, la revérification refuse « paquet altéré : pool/main/g/gcc-defaults/g++-x86-64-linux-gnu_14.2.0-1_amd64.deb » et « InRelease du miroir différent ». Ni mmdebstrap ni apt ne sont lancés, et les quatre témoins réseau de la tâche échouent (code 124). Même écart de raison.
- **P10 : tenue.** `DIGEST_CONSTRUIT` = `sha256:749d746c…`, le digest de S4a, depuis un TaskRun isolé ; `memory.peak` vaut 1,8 Gio.
- **P11 : tenue. La réserve de A7 est levée.** apt 3.0.4 de l'amorce, sans root, depuis `file:` et sans `trusted=yes` :
  - miroir intact : index puis téléchargement acceptés ;
  - InRelease altéré : sqv refuse (« Message has been manipulated »), puis « The repository … is not signed », code 100, aucun index ;
  - `.deb` altéré : index acceptés, puis « Hash Sum mismatch » au téléchargement, code 100, aucun fichier.
- **P17 : non mesurée, par une erreur de mon script.**
  - Le témoin tient : depuis le pod d'essai Kata, la connexion TCP à Zot réussit (code 0).
  - sbuild rend le code 0, mais les lignes de `debian/rules` ne sont pas dans `/w/sbuild.out`. sbuild écrit le journal de construction dans le fichier `.build` horodaté de `--build-dir`, ce que `s3.sh` savait déjà (l. 229 et 230).
  - N6 n'est donc ni tenue ni réfutée. La correction lit `/w/sortie/*Z.build`, et elle demande un accord.
- **Chains** : l'annotation `chains.tekton.dev/signed` vaut `true` sur les 7 TaskRuns. Le comptage des enveloppes (P18) se fait à l'étape `porte`.

**Erreur de prédiction commune** : j'ai écrit `False|Failed` pour un TaskRun en échec. Tekton donne `False|StepFailed` quand une étape sort en erreur. Le script n'est pas modifié pour ce libellé. Les étapes à venir (`fermeture`) produiront le même écart, qui ne touche pas la barrière mesurée.

---
## Suite (11/11/2026, de 21:34:26 à 21:37:30 UTC, accord « Oui, les deux »)

- **P4 : tenue.** Les fermetures `a549729d…` et `b27225cf…` sont dans Zot sous `entrees/sample-app-deb/fermeture-alteree`, relues en lecture anonyme (`s5-zot.log`).
- **P17, second passage : toujours non mesurée, par une autre erreur de ma part** (`s5-sbuild-2.log`, journal `s5-sbuild-build.log`). Le journal `.build` est bien lu, et sbuild y écrit `Status: successful`. Mais avec `Rules-Requires-Root: no`, `dpkg-buildpackage -b` n'appelle que `debian/rules clean` puis `binary` (l. 240 et 242), et la cible `build`, qui porte la mesure, n'est jamais appelée. Le premier passage est archivé sous `s5-sbuild-1.log`.
- **P12 à P14, premier passage de `fermeture` : non atteintes, par une erreur de mon script** (`s5-fermeture-1.log`).
  - Les paramètres de `preparer` sont recopiés de la pipeline, et `commit` et `depot` y valent `$(params.commit)` et `$(params.depot)`. Un TaskRun isolé ne les résout pas.
  - Les trois TaskRuns s'arrêtent dans la première étape, sur « commit invalide », avant tout tirage : l'échec est fermé et rien n'est construit.
  - Mon rendu sur l'hôte utilisait des paramètres factices et ne pouvait pas voir ce défaut. Le relevé de `prealables` ne comparait que les noms des paramètres.

**Corrections faites à sec dans `s5.sh`** :
- **`figer`** remplace les deux variables par les valeurs du gabarit en service (commit `6391fd43…`, dépôt de Forgejo) et exige qu'aucune variable ne reste. `fermeture` retire d'abord les objets de N5 du premier passage, puis refait l'admission à blanc.
- **`debian/rules`** : la cible `binary` dépend de `build`. Joué sur l'hôte par `dpkg-buildpackage --sanitize-env -us -uc -b` (code 0), `clean` puis `binary` exécute bien les lignes de mesure. La connexion réussit depuis l'hôte, ce qui est attendu hors de sbuild.

`kata` n'est pas lancé, car il dépend du témoin de N5. `porte` et `retirer` non plus.
