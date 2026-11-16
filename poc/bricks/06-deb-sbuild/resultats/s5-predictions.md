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

---
## Bilan (11/11/2026, de 21:40:40 à 21:50:33 UTC, accord « Oui, relance la suite »)

Journaux : `s5-fermeture.log` (premier passage : `s5-fermeture-1.log`), `s5-kata.log`, `s5-sbuild.log` (passages précédents : `s5-sbuild-1.log` et `s5-sbuild-2.log`, journal `.build` : `s5-sbuild-build.log`, précédent `s5-sbuild-build-2.log`), `s5-porte.log`, `s5-retirer.log`, `chrono.tsv`.

- **P12 : tenue.** `preparer-deb` sur la vraie fermeture, par un TaskRun isolé : clone de `6391fd43…` (arbre `30e808ff…`), trois tirages par digest, « 162 paquets, sha256, taille et chemin identiques ».
- **P13 : tenue.** La fermeture `paquet-modifie` est tirée par digest sans erreur : oras ne voit rien, puisque le manifeste est cohérent. Elle est ensuite refusée : « paquet différent du verrou : pool/main/g/gcc-defaults/g++-x86-64-linux-gnu_14.2.0-1_amd64.deb ». Même écart de raison (`StepFailed`).
- **P14 : tenue.** La fermeture `paquet-en-trop` est tirée, puis refusée : « pool : 163 fichiers, 162 dans le verrou ». Même écart de raison.
- **P15 : tenue.** Sans Kata : `False|PodAdmissionFailed`, « violates PodSecurity "restricted:latest": privileged… », aucun pod. Chains annote ce TaskRun `failed`.
- **P16 : tenue.** Sous Kata, sur sc-build : deb `0b489d43…` (1952080 octets) et `DIGEST_CONSTRUIT` = `sha256:039949f9…`.
  - Une mesure du script affiche un écart (« sample-a ») : mon extraction prenait le nom du fichier au lieu de son empreinte.
  - La ligne du journal porte bien `sample-app_1.0.0-1_amd64.deb 0b489d438370ddb6…`. L'écart vient du script ; le résultat est conforme.
- **P17 : tenue, au troisième passage.**
  - Depuis le pod d'essai Kata, la connexion TCP à Zot réussit (code 0).
  - Depuis `debian/rules`, sous sbuild `--chroot-mode=unshare`, elle échoue aussitôt (code 1, sans délai d'attente), et la seule interface visible est `lo`. **La coupure du réseau par sbuild est mesurée.**
- **P18 : tenue.**
  - Enveloppes inchangées : deb 8, sample-app 28, fermeture 4, image de build 4.
  - Chains annote `signed: true` sur les TaskRuns réussis ou échoués, mais n'écrit rien dans Zot : sans `IMAGE_URL`/`IMAGE_DIGEST`, il n'a pas de sujet.
- **P19 : tenue.**
  - La provenance jugée du deb reste celle du chemin 2 de S4d3 (`454728c5…`).
  - Verdict du deb : `ec` sans violation, horodatage 8/8, VSA et scan refusés.
  - Verdict de sample-app : horodatage 28/28, VSA et scan ok.
- **`retirer`** : 12 TaskRuns et 2 PVC supprimés, aucun objet `s5` restant. Les deux fermetures altérées restent dans Zot.

**Toutes les barrières prédites ont refusé, et chaque témoin a été accepté.** Les écarts sont :
- **trois erreurs de mon script**, qui ont fait relancer `sbuild` deux fois et `fermeture` une fois, toujours en échec fermé :
  - journal de sbuild lu sur la sortie au lieu du fichier `.build` ;
  - cible `build` non appelée par `dpkg-buildpackage -b` ;
  - variables de la pipeline non résolues dans un TaskRun isolé ;
- **une extraction fausse dans une mesure** (P16) ;
- **un libellé de raison mal prédit** : `StepFailed` au lieu de `Failed`, six fois ;
- **le libellé d'`apt-helper` absent** des cinq lignes gardées (P6).

**Leçon** : un contrôle sur l'hôte doit utiliser les valeurs réelles, pas des valeurs factices, et rejouer l'outil réel (`dpkg-buildpackage`) plutôt que la cible seule. Les deux premières erreurs auraient été vues sur l'hôte.

---
## Additif de la révision 1.0.0-2 : `prealables` (note de 2026-11-16T15:07:58Z, avant tout lancement ; rien n'est réécrit)

Ligne 9 de la carte de la cascade ([`revision-predictions.md`](revision-predictions.md)). Ces prédictions valent pour `s5.sh`
**avec le correctif d'épinglage 5 appliqué** ; sans lui, `prealables` n'est pas lancée. Elles ne portent que sur `prealables` :
lecture de l'API et de Zot, travail sur l'hôte, admission à blanc, aucune écriture. Les étapes suivantes auront leur propre
additif. Chaque valeur vient du dernier journal qui l'a produite après S5b (Zot neuf le 13/11) ; la référence de forme est
`s5-prealables.log` du 11/11.

| # | Prédiction | Source de la valeur | Confiance |
|---|---|---|---|
| Q1 | Export de `builder-sbuild@71f84839` et `sample-app-deb@d1fb3871` réussi ; tâches `prefetch,construire,publier` et `preparer,construire,publier` ; image de `prefetch-deb` égale à l'amorce `7378260c` | `s4a-taches.log` l. 10 (13/11) ; `s4d3-prealables.log` l. 24 (15/11) ; `s1r-amorce.log` l. 3 (13/11) | Haute pour `d1fb3871` ; moyenne-haute pour `71f84839`, non relu dans Zot depuis le 13/11 |
| Q2 | Les quatre tâches dans la liste revue, aux mêmes digests que le 11/11 : `prefetch-deb@4dac0609`, `construire-builder@746c2e11`, `preparer-deb@588617b8`, `construire-deb@3726ff0b` | `s4a-taches.log` l. 5 et 8 (13/11) ; `s4d-taches.log` l. 5 et 8 (15/11) | Haute |
| Q3 | Paramètres de `prefetch`, de `construire` (builder) et de `preparer` égaux à ceux du 11/11 ; fermeture deb de la pipeline `bb7599a2` ; liste égale à `builder/paquets.txt` (`b47135c9…`) ; paquet témoin du miroir `g++-x86-64-linux-gnu_14.2.0-1_amd64.deb` (1200 octets) | `s4a.sh` et `builder/` inchangés depuis le 10/11 (`paquets.txt` : 029ee64) ; `s4d-taches.log` l. 11 (15/11) | Haute |
| Q4 | Copie de S4b : 162 paquets confrontés au verrou, 167 fichiers ; layout de la copie intacte `bb7599a2` ; `paquet-modifie` `a549729d…` (167 couches) et `paquet-en-trop` `b27225cf…` (168 couches), une couche différente chacun | copie du 14/11 à 23:24 (S4b de la cascade, U9) ; 167 fichiers comptés le 16/11 ; oras 1.3.6 relu le 16/11 ; `layout` fixe la date de création et trie les fichiers | Haute |
| Q5 | 16 objets admis à blanc côté serveur : 12 TaskRuns, 2 PVC, 2 pods | 11/11 ; mêmes tâches ; politiques remises par S5b | Moyenne-haute : aucun TaskRun isolé admis depuis S5b |
| Q6 | Politiques réseau de `builds` : les six du 11/11 (trois NetworkPolicy, trois CiliumNetworkPolicy), mêmes sélecteurs ; relevé sans mesure | 11/11 | Moyenne |
| Q7 | Aucun objet `s5` dans `builds` ; dépôt `fermeture-alteree` **absent** de Zot ; enveloppes de départ `8 6` (deb `60f25f5c`, sample-app) ; fermeture et image de build relevées sans mesure | Zot neuf depuis S5b, étape `zot` non rejouée (`chrono.tsv` l. 206-208, dernière S5a le 11/11) ; `s4d3-chemins.log` l. 78-79 (15/11) | Haute |
| Q8 | Code 0, aucun ÉCART ni KO | Q1 à Q7 | Moyenne-haute |

- **Conséquence de Q7** : `fermeture` exige les deux fermetures altérées dans Zot (l. 434). L'étape `zot`, qui écrit dans Zot et
  demande un accord à part, est donc à refaire avant `fermeture`.
- **Écart d'annonce du 11/11, noté sans réécriture** : P2 annonçait 13 TaskRuns ; `s5-prealables.log` en admet 12 (l. 26 à 37),
  et `rendre_tout` en rend 12.
- **Non mesuré par `prealables`** : la présence de `a9d48331` dans Zot, et l'égalité des spécifications des bundles `a9d48331` et
  `71f84839`.

### Résultats de l'additif `prealables` (note de 2026-11-16T15:09:57Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance S5 `prealables` (lecture et admission à blanc, Q1 à Q8) ? ». `s5.sh prealables` à 7d09bd3, du 16/11 15:09:15 au 16/11 15:09:18 UTC, code 0 relevé juste après la commande, 39 OK, 0 KO,
0 ÉCART ; lignes « S5a prealables » et « fait » dans `chrono.tsv`. Journal `s5-prealables.log` réécrit (version du 11/11 dans git).
- **Q1 tenue** : export des deux bundles réussi (`71f84839` est donc dans Zot) ; tâches `prefetch,construire,publier` et
  `preparer,construire,publier` ; image de `prefetch-deb` = amorce `7378260c`.
- **Q2 tenue** : `prefetch-deb@4dac0609`, `construire-builder@746c2e11`, `preparer-deb@588617b8`, `construire-deb@3726ff0b`, tous
  dans la liste revue.
- **Q3 tenue** : paramètres égaux à ceux du 11/11 ; fermeture deb `bb7599a2` ; liste `b47135c9…` ; paquet témoin
  `g++-x86-64-linux-gnu_14.2.0-1_amd64.deb` (1200 octets).
- **Q4 tenue** : 162 paquets, 167 fichiers ; layout intact `bb7599a2` ; `paquet-modifie` `a549729d…` (167 couches), `paquet-en-trop`
  `b27225cf…` (168 couches), une couche différente chacun : mêmes digests que le 11/11.
- **Q5 tenue** : 16 objets admis à blanc (12 TaskRuns, 2 PVC, 2 pods) ; les trois TaskRuns de N5 sans variable de pipeline restante.
- **Q6 tenue** : six politiques, mêmes sélecteurs que le 11/11.
- **Q7 tenue** : aucun objet `s5` ; `fermeture-alteree` absent de Zot ; enveloppes `8 6`. Relevées sans mesure : fermeture
  `bb7599a2` **8** (4 le 11/11), image de build `749d746c` **4** (4 le 11/11).
- **Q8 tenue** : code 0, aucun ÉCART ni KO.
- Non mesuré : l'égalité des spécifications de `a9d48331` et `71f84839` ; la présence de `a9d48331` dans Zot.

---
## Additif de la révision 1.0.0-2 : étapes `zot` à `retirer` (note de 2026-11-16T15:13:21Z, avant tout lancement ; rien n'est réécrit)

Ces prédictions valent pour `s5.sh` **avec le correctif 6 appliqué** ([`revision-correctif-6.patch`](../revision-correctif-6.patch),
non appliqué à cette heure). Ce correctif corrige deux défauts mesurés le 11/11 et restés dans le script ; sans lui, `prefetch` et
`kata` finissent en KO sur un écart garanti :
- `kata` : l'extraction du deb prend le champ 4 (nom du fichier) au lieu du champ 5 (empreinte) : « sample-a » le 11/11
  (`s5-kata.log` l. 21). Le champ 5 donne `f66bbeb2` sur la ligne « deb produit » de `s4d-pipeline-1-construire.log` (15/11).
- `prefetch` : apt-helper 3.0.4 n'écrit pas « Hash Sum mismatch » pour N1 (`s5-prefetch.log` l. 26) ; il écrit « Hashes of received
  file » (l. 17). La mesure prend ce libellé. Celle de N4 (`apt-get download`, l. 412) garde « Hash Sum mismatch », mesuré le 11/11
  (`s5-miroir.log` l. 72).

Valeurs : celles du 11/11 (journaux `s5-*.log` de cette date, dans git) sauf les quatre qui suivent la révision et S5b : deb du témoin
N7 `f66bbeb2`, `DIGEST_CONSTRUIT` de N7 = D `60f25f5c`, enveloppes de départ `8 6 8 4` (`prealables` du 16/11), provenance la plus
récente du deb = PipelineRun `c3d27e05…` (`$W/s4d3-06/uid-chemin-2`, écrit le 15/11 à 20:38 UTC).

| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| Q9 | `zot` (écriture, compte poc-ecriture) | `paquet-modifie` relu en lecture anonyme à `a549729d…`, `paquet-en-trop` à `b27225cf…` | Haute |
| Q10 | `prefetch` | N1 témoin `True|Succeeded`, pod `prefetch-deb|sc-build|-`, miroir d'un paquet | Haute ; dépend d'Internet en 80 vers snapshot.debian.org |
| Q11 | `prefetch` | N1 hash faux `False|StepFailed` ; « téléchargement refusé » 1 ; « sha256 différent » 0 ; « Hashes of received file » présent | Haute |
| Q12 | `prefetch` | N2 `False|StepFailed` ; refus sur `dists/trixie/InRelease` 1 ; aucun index | Haute |
| Q13 | `miroir` | prefetch complet `True|Succeeded` ; copies altérées `1|1200` et `1|1` ; N3 `.deb` et InRelease `False|StepFailed`, refus par la revérification, pods `construire-builder|sc-build|kata` ; N3 témoin `True|Succeeded`, `DIGEST_CONSTRUIT` = `749d746c` | Moyenne-haute : Internet ; témoin reproduit deux fois le 13/11 (`s4a-pipeline.log` l. 78) |
| Q14 | `miroir` | N4 : intact `0|1` puis `0|1` ; InRelease altéré `1|0` ; `.deb` altéré `0|1` puis `1|0`, « Hash Sum mismatch » | Haute : même amorce `7378260c`, même apt |
| Q15 | `fermeture` | commit et dépôt `6391fd43` ; N5 témoin `True|Succeeded`, 162 paquets ; deux fermetures altérées présentes (Q9), tirées, `False|StepFailed`, refusées par la confrontation au verrou (paquet différent ; 163 fichiers pour 162) | Haute ; le packaging `f0ed7a71` du bundle `d1fb3871` ne touche pas la fermeture |
| Q16 | `kata` | N7 hors Kata `False|PodAdmissionFailed`, refus de Pod Security « restricted » (privileged), aucun pod ; N7 témoin `True|Succeeded`, `construire-deb|sc-build|kata`, deb `f66bbeb2`, `DIGEST_CONSTRUIT` = `60f25f5c` | Haute : S4d du 14/11 et S4d3 du 15/11, deux fois chacune sous Kata |
| Q17 | `sbuild` | journal `.build` 1 ; connexion TCP à Zot depuis le pod en code 0 ; `debian/rules` exécuté une fois, connexion en échec, interfaces `lo` | Moyenne-haute : image de build `749d746c` identique, passage tenu le 11/11 |
| Q18 | `porte` | aucun TaskRun en cours ; enveloppes `8 → 8`, `6 → 6`, `8 → 8`, `4 → 4` ; annotations de Chains relevées (`true`, `failed` pour N7 hors Kata) | Moyenne-haute : suppose qu'aucun PipelineRun ne tourne pendant S5 (rattrapage repris en S4d3, PipelineRun déjà présent pour `6391fd43`) |
| Q19 | `porte` | provenance de PipelineRun la plus récente du deb : `c3d27e05…` | Haute |
| Q20 | `porte` | deb : `true||trusted_task.tagged`, `ok|8/8`, `refus|refus` ; sample-app : `true||trusted_task.tagged`, `ok|6/6`, `ok|ok` | Moyenne-haute : le scan de sample-app doit dater de 7 jours au plus et sa base de 3 jours au plus avant lui (`07a/politique/porte/scan.rego` l. 80-109) ; dernier verdict `ok` le 15/11, non relu depuis |
| Q21 | `retirer` | aucun objet `s5` restant ; les fermetures altérées restent dans Zot | Haute |
| Q22 | toutes | code 0 et aucun ÉCART à chaque étape | Moyenne-haute |

- **Ordre proposé**, un accord par lancement : correctif 6 ; `zot` seule (écriture dans Zot) ; puis
  `prefetch miroir fermeture kata sbuild porte retirer` (cluster, Internet en 80 pour `prefetch` et `miroir`).
- **Ne mesure pas** : ce que la note « Ce que S5a ne mesure pas » exclut déjà ; U13 (`ScanEnRetard`), qui n'est pas jugée par S5.

### Note de 2026-11-16T15:16:49Z sur les deux additifs (relecture du conseiller ; rien n'est réécrit)
- **Deux heures non mesurées, corrigées** : « copie du 14/11 à 23:24 » (Q4) venait d'un `ls` en heure locale ; `date -u -r` donne
  **2026-11-14T22:24:38Z**. « écrit le 15/11 à 20:38 UTC » (`uid-chemin-2`) était une conversion ; `date -u -r` donne
  **2026-11-15T20:38:25Z**.
- **Source de Q18** (au lieu de « suppose ») : `prealables` du 16/11 à 15:09 UTC relève 8 enveloppes sur le deb, comme S4d3 à la fin
  de `chemins` le 15/11 (`s4d3-chemins.log` l. 78) : aucun PipelineRun n'a ajouté de provenance au deb entre les deux. Q18 reste à
  moyenne-haute pour la durée de S5 elle-même.
- **Source de Q20, moitié deb** : le CronJob du scan du deb a été rendu par S6a `periodique` le 14/11 (20:59:40 à 21:01:45 UTC,
  `chrono.tsv`), avant le correctif d'épinglage 3 (22:57:45Z) ; `rendre_deb` (`s6a.sh` l. 276-277) y écrit `DEB_REF` en dur, alors
  `039949f9` (`s6a-periodique.log` l. 29). Le CronJob en service scanne donc `039949f9`, pas D : `refus` du scan de D, **confiance
  haute** (non relu dans le cluster).
- **Mode d'échec de la chaîne** : `lancer` (`08-trust-plane/commun.sh` l. 329-338) tourne sous `set -euo pipefail`
  (`politique.sh` l. 73) ; un KO en fin d'étape arrête la chaîne, sans ligne « fait » dans `chrono.tsv` (le 11/11 : `prefetch`,
  `miroir`, `fermeture` et `kata`). `retirer` ne tourne alors pas. Restent dans `builds` : les TaskRuns `s5-*` déjà créés, le PVC
  `s5-miroir` (4Gi, après `miroir`) et `s5-entrees` (1Gi, après `fermeture`) ; les pods d'essai `s5-miroir-essai` et `s5-sbuild` sont
  supprimés par le `trap` de leur étape. Reprise : `retirer` seule, sur accord.
- **Durée** : le 11/11, les étapes ont pris de 37 s (`prefetch`) à environ 7 min (`kata`), soit une quinzaine de minutes de
  calcul ; la chaîne sera lancée en arrière-plan, code et heure de fin relevés par la même commande.
