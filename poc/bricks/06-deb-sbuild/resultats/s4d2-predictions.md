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
