# Brique 06, S4d2a : prédictions et résultats

Décision du propriétaire (11/11/2026, 20:08:42 UTC, « Oui, S4d2a ») : S4d2a étend la porte à la voie deb avant tout trigger. Les contrôles 6 (VSA) et 7 (scan) du deb vont dans un jalon séparé ; d'ici là, ils refusent, en échec fermé. Les questions 2 à 4 de la carte (20:07 UTC) n'ont pas reçu de réponse. Pour la question 2, j'applique ma recommandation, qui ne change rien : la voie image n'est pas appariée et reste inchangée.

Prédictions écrites le 11/11/2026 à 20:17 UTC, avant tout lancement. Script : [`s4d2.sh`](../s4d2.sh). Règles : `politique/porte/porte.rego` et `porte_test.rego` de la 08. Mutations : [`deb/mutations-porte.txt`](../deb/mutations-porte.txt).

## Ce que S4d2a change dans la porte

- **`construction_kata`** : `construire-deb` est une construction, désignée par son nom ou par le dépôt de son bundle. Le message ne nomme plus `construire-image` mais « construction ».
- **`fermeture_plateforme`** :
  - les fermetures sont typées par le nom du résultat. `FERMETURE_DEB_ARTIFACT_INPUTS` n'est prouvée que par `prefetch-deb` et `publier-fermeture`, sans git. `FERMETURE_SOURCES_ARTIFACT_INPUTS`, comme `FERMETURE_ARTIFACT_INPUTS`, ne l'est que par `prefetch-gomod` et `publier-fermeture`, avec le même dépôt Forgejo ;
  - chaque résultat attendu d'une préparation doit être lu, sinon refus ;
  - le message de la règle « sans fermeture » change. Le test de F3 ne cherche que « sans fermeture ».
- **`preparation_appariee`**, règle neuve : `construire-deb` sans `preparer-deb` dans la même provenance est refusée. La voie image n'est pas appariée.
- **Hors du jugement**, dette inscrite : l'artefact de packaging, poussé depuis l'hôte, et la provenance de l'image de build `sbuild-debian13`.

## Prédictions

| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| E1 | `regle` | `ec opa check` sans erreur ; `ec opa test` : 39/39 (21 tests de F3, 18 de S4d2a) | moyenne : règles et tests écrits sans avoir été exécutés |
| E2 | `regle` | 18 mutations conformes à l'annonce : 17 font échouer au moins un test. `f.preparation == nom` survit, car les noms de résultats sont distincts d'une préparation à l'autre ; elle n'est gardée que pour un futur nom partagé | moyenne |
| E3 | `reel` | Deb, clé de Chains : aucun code `porte.*` (hors `image_signature`, que l'hôte n'évalue pas : `input.image` vient de ec). Fermetures lues : `FERMETURE_DEB_ARTIFACT_INPUTS` (forme deb) et `FERMETURE_SOURCES_ARTIFACT_INPUTS` (forme gomod) ; chacune vérifiée par la vraie fonction, au moins une provenance conforme | moyenne |
| E4 | `reel` | Deb, autre clé : `porte.fermeture_plateforme` | haute |
| E5 | `reel` | Image sample-app, clé de Chains : aucun code `porte.*` (non-régression) | haute |
| E6 | `reel` | Témoins sur la provenance du deb : hors Kata, `construction_kata` ; sans fermeture deb, `fermeture_plateforme` ; fermetures permutées, `fermeture_plateforme` ; sans `preparer-deb`, `fermeture_plateforme` et `preparation_appariee` | haute |
| E7 | `reel` | Règles en service (commit `a7c7405`) sur le deb réel, et sur le témoin hors Kata : aucun code, c'est le succès à vide constaté par la carte | haute |
| E8 | `porte` | Deb, porte en service : `ec` en succès sans violation ; VSA et scan refusés | moyenne : `@slsa3` n'a jamais jugé un artefact dont la seule couche est un `.deb` |
| E9 | `porte` | ConfigMap `porte` mise à jour : `porte.rego` en service égal au fichier versionné ; liste revue inchangée | haute |
| E10 | `porte` | Deb, porte étendue : `ec` en succès, sans violation, `trusted_task.tagged` en avertissement ; horodatage complet ; VSA et scan refusés ; parmi les succès : `construction_kata`, `fermeture_plateforme`, `image_signature`, `preparation_appariee`, `taches_vues` | moyenne : l'horodatage suppose que le CronJob de la 08 tourne (il peut avoir été suspendu par la 08c) ; `image_signature` suppose que Chains a signé l'image du deb, ce que S4d1 n'a pas vérifié |
| E11 | `porte` | Image sample-app, porte étendue : verdict de `c7-reelle` (07/11/2026) : succès, `trusted_task.tagged`, horodatage, VSA et scan admis | haute |

**Si une règle de `@slsa3` refuse le deb** (E8 ou E10) : je m'arrête et je reviens avec la règle et son motif, sans l'exclure.

**Si E10 échoue sur l'horodatage** ou sur `image_signature` : c'est un constat à instruire, pas une raison de toucher à la règle ; je reviens avec la cause.

**Retour arrière** : la ConfigMap est remise avec le `porte.rego` enregistré avant la mise à jour (`$T/porte-avant.rego`, égal à celui de `a7c7405`), au choix du propriétaire.

## Accords

- `regle` et `reel` : script neuf, sur l'hôte. `reel` lit Zot en anonyme. Aucune écriture.
- `porte` : deux Jobs de la porte et une écriture dans le cluster (la ConfigMap). Comme la ConfigMap est commune aux deux voies, cette étape a son propre accord.

## Résultats de `regle` et `reel` (11/11/2026, accord « Oui, lance-les »)

**`regle`** (20:18:11 UTC, [journal](s4d2-regle-1.log)) :
- **E1 tenue** : `ec opa check` ne signale aucune erreur ; `ec opa test` passe 39 tests sur 39.
- **E2 non tenue** : 17 des 18 mutations sont conformes à l'annonce, et `f.preparation == nom` survit comme prévu. En revanche, quand on remplace par `false` la correspondance par dépôt du bundle, aucun test n'échoue.
  - **Cause, dans le test et non dans la règle** : la bibliothèque prend le nom de la tâche dans le label `tekton.dev/task`, avant le paramètre `name` (`lib/tekton/refs.rego`, `_ref_name`). `test_deb_bundle_sous_autre_nom_hors_kata_refuse` ne changeait que le paramètre ; le label désignait donc encore `construire-deb`, et la correspondance par nom suffisait.
  - **Correction** : le test change maintenant aussi le label. `regle` est à relancer avec un nouvel accord, puisque le fichier de tests a changé. La règle n'a pas changé.

**`reel`** (20:18:38 à 20:18:49 UTC, [journal](s4d2-reel.log)) : **E3 à E7 tenues**.
- **E3** : la provenance la plus récente du deb (PipelineRun `s4d-deb-2`, 19:55:56 UTC) ne donne aucun code `porte.*`. La règle y lit les deux fermetures, typées `deb` et `gomod`. Pour chacune, la vraie fonction vérifie 4 provenances, et au moins une est conforme.
- **E4** : avec une autre clé, aucune provenance n'est vérifiée, et la porte refuse les deux fermetures par `porte.fermeture_plateforme`. Le message nomme le résultat et la forme attendue.
- **E5** : sur l'image sample-app (plus récent des 14 PipelineRuns : 10/11/2026, 21:12:22 UTC), aucun code `porte.*`. La fermeture de F2 est vérifiée.
- **E6**, les quatre témoins, chacun refusé par le code prévu :

  | Témoin | Code | Message |
  |---|---|---|
  | Hors Kata | `construction_kata` | `TaskRun s4d-deb-2-construire de construction` |
  | Sans fermeture deb | `fermeture_plateforme` | « préparation preparer-deb sans fermeture lisible dans le résultat FERMETURE_DEB_ARTIFACT_INPUTS » |
  | Fermetures permutées | `fermeture_plateforme` | chaque fermeture est refusée pour la forme de l'autre |
  | Sans `preparer-deb` | `fermeture_plateforme` et `preparation_appariee` | |

- **E7** : avec les règles en service (`a7c7405`), aucun code, ni sur le deb réel ni sur le témoin hors Kata. C'est le succès à vide décrit par la carte, désormais mesuré.

**`regle`, second passage** (20:19:52 UTC, accord « Oui, relance-la », [journal](s4d2-regle-2.log)), avec le test corrigé et la règle inchangée :
- `ec opa test` passe 39 tests sur 39.
- Les 18 mutations sont conformes à l'annonce : 17 font échouer au moins un test, et `f.preparation == nom` survit comme prévu. Remplacer par `false` la correspondance par dépôt du bundle fait maintenant échouer `test_deb_bundle_sous_autre_nom_hors_kata_refuse`.

**E2 tenue au second passage**, après correction du test.

## Note du 11/11/2026, 20:21 UTC : premier passage de `porte` arrêté avant toute écriture, E8 et E9 révisées

**Arrêt** : le premier passage de `porte` (20:20:44 UTC, accord « Oui, lance porte », [journal](s4d2-porte-1.log)) s'est arrêté au contrôle préalable, avant tout Job et toute écriture.
- `porte.rego` en service est bien celui de `a7c7405`.
- En revanche, `taches.yml` en service n'est pas le fichier versionné : c'est celui de `b1e5ef4` (brique 03, F3, 03/11/2026). La ConfigMap n'a pas été redéployée depuis.
- Il manque à la liste en service les cinq entrées ajoutées depuis, toutes relues par le propriétaire : `prefetch-gomod` en version 2 (`170bef53`), `prefetch-deb` (`4dac0609`), `construire-builder` (`746c2e11`), `preparer-deb` (`588617b8`) et `construire-deb` (`3726ff0b`). Aucune entrée n'a été retirée.

**Ce qui était faux dans la carte et les prédictions** :
- **Ce que la porte en service fait du deb** : seules les règles `porte.*` réussissent à vide (E7, mesurée sur l'hôte). La porte en service, elle, devrait refuser le deb par `trusted_task`, puisque ses tâches ne figurent pas dans la liste déployée. La carte de 20:07 UTC ne l'avait pas vu.
- **E8** (« `ec` en succès sans violation ») devient : `ec` en échec, avec `trusted_task.trusted` en violation ; VSA et scan refusés. Confiance moyenne : d'autres règles de `@slsa3` pourraient s'ajouter.
- **E9** (« liste revue inchangée ») devient : `cm_porte` déploie `porte.rego` et la liste versionnée, soit les cinq ajouts relus. Ce second déploiement sort de l'accord « Oui, lance porte » et en demande un nouveau.

**Script corrigé** :
- le contrôle préalable attend désormais la liste de `b1e5ef4`, affiche les entrées ajoutées et exige qu'aucune ne soit retirée ;
- après la mise à jour, il vérifie que `porte.rego` et `taches.yml` en service sont ceux du dépôt ;
- le retour arrière remet les deux fichiers enregistrés.

E10 et E11 restent inchangées.

## Note du 11/11/2026, 20:23 UTC : second passage de `porte` arrêté avant toute écriture, par un défaut du script corrigé

**Arrêt** : le second passage (20:22:00 UTC, accord « Oui, relance porte », [journal](s4d2-porte-2.log)) a tenu les deux contrôles préalables :
- `porte.rego` en service est celui de `a7c7405` ;
- la liste en service est celle de `b1e5ef4`, et les cinq ajouts sont affichés.

Il s'est arrêté juste après, sans message. Rien n'a été écrit : `porte.rego` en service est toujours `53b01702…`, et aucun Job n'a été créé (vérifié après l'arrêt).

**Cause, dans le script** : la ligne qui affiche les ajouts faisait passer `diff` dans un tube. `diff` rend 1 quand les listes diffèrent ; avec `pipefail`, `set -e` arrête l'étape en silence. C'est un défaut de la correction de 20:21 UTC, que je n'avais vérifiée que pour la syntaxe.

**Correction** : la sortie de `diff` est écrite dans un fichier, hors du tube, puis relue. Les prédictions ne changent pas.

**Correction datée (11/11/2026, 20:24 UTC)** : la note titrée « 20:23 UTC » a en réalité été écrite à 20:22:30 UTC (heure lue par `date -u` juste avant le commit `4117099`).

## Résultats de `porte` (troisième passage, 11/11/2026, 20:23:01 à 20:23:28 UTC, accord « Oui, relance porte »)

[Journal](s4d2-porte-3.log). Contrôles préalables tenus : `porte.rego` en service est celui de `a7c7405`, la liste en service celle de `b1e5ef4`, cinq entrées ajoutées et aucune retirée.

**E8 tenue, dans sa version révisée de 20:21 UTC.** Le deb jugé par la porte en service donne :
- `ec` en échec, avec `trusted_task.trusted` comme seule violation et `trusted_task.tagged` en avertissement ;
- horodatage complet ;
- VSA refusée (0 retenue dans `builds/vsa/sample-app-deb`) et scan refusé (`scan.scan_present`).

**La porte en service ne laissait donc pas passer le deb**, puisque ses tâches ne figuraient pas dans la liste déployée. Le succès à vide ne concernait que les règles `porte.*`.

**E9 tenue** : la ConfigMap `porte` est mise à jour, et `porte.rego` comme `taches.yml` en service sont égaux aux fichiers versionnés (`f16c81ac…` et `cdac17f1…`).

**E10 tenue.** Le deb jugé par la porte étendue (`VERDICT|s4d2-deb`) donne :
- `ec` en succès, sans violation, avec `trusted_task.tagged` en avertissement ;
- parmi les succès, `porte.construction_kata`, `porte.fermeture_plateforme`, `porte.image_signature`, `porte.preparation_appariee` et `porte.taches_vues` ;
- horodatage complet : 4 enveloppes sur 4 couvertes ;
- VSA et scan refusés.

Le Job de la porte échoue donc, en échec fermé, comme décidé pour S4d2a. Les deux inconnues de E10 sont levées : le CronJob d'horodatage tourne, et Chains a signé l'image du deb. Aucune règle de `@slsa3` ne refuse un artefact dont la seule couche est un `.deb`.

**E11 tenue** : sample-app jugée par la porte étendue (`VERDICT|s4d2-reelle`) donne le même verdict que `c7-reelle` :
- succès, sans violation, `trusted_task.tagged` en avertissement ;
- horodatage complet (28 enveloppes sur 28) ;
- VSA retenue (1 sur 1) et scan admis (7 énoncés vérifiés).

**Bilan de S4d2a : E1 à E11 tenues, E2 au second passage de `regle`, et E8 et E9 dans leur version révisée de 20:21 UTC.** Écarts :
- un test ne couvrait pas la correspondance par bundle ; il a été corrigé ;
- la liste déployée datait du 03/11, ce que la carte n'avait pas vu, d'où la révision de E8 et E9 avant mesure ;
- deux défauts du script, tous deux arrêtés avant toute écriture.

**Note datée sur un commentaire devenu faux** : dans `politique/porte/taches.yml` de la 08, le commentaire de `construire-deb` dit que la porte « ne connaît pas encore son nom » et qu'elle « sera étendue en S4d2 ». C'est faux depuis 20:23 UTC. Le fichier n'est pas réécrit : le modifier changerait la liste déployée.
