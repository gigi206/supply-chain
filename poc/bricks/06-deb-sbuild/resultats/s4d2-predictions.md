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
