# Brique 08 : témoins des règles qui réussissent pour Chains v0.30.0 sans témoin, prédiction

Note de 2026-11-26T09:27:41Z, écrite avant le lancement. Ce banc suit le passage -3 de la [porte Conforma](chains-v0300-porte-predictions.md) et le passage -2 du [banc ivpol](chains-v0300-ivpol-predictions.md). Ces deux passages laissaient des règles en succès pour v0.30.0 sans témoin. Il est local : pas de cluster, pas de VM, pas de vrai Zot, pas de clé réelle, pas de TSA.

Choix du propriétaire du 26/11 : « Témoins des règles ».

## Les règles visées

Elles sont tirées des journaux [`chains-v0300-porte-3.log`](chains-v0300-porte-3.log) et [`chains-v0300-ivpol-2.log`](chains-v0300-ivpol-2.log), croisés avec la bibliothèque `ebd3fbd2`. Chacune lit les tâches et réussit (ou n'avertit pas) pour v0.30.0 sans qu'un témoin prouve qu'elle sait refuser :

- chez `ec` :
  - `slsa_build_scripted_build.subject_build_task_matches` et `build_script_used` ;
  - `trusted_task.current`, `future_deny_rule`, `pinned`, `trusted_parameters` et `valid_trusted_artifact_inputs` ;
  - `porte.preparation_appariee` ;
- sous reserve-c : `subject_build_task_matches`, `successful_pipeline_tasks`, `trusted_task.pinned`, `trusted_parameters` et `valid_trusted_artifact_inputs`.

`tasks.successful_pipeline_tasks` est absent chez `ec` pour v0.30.0, car il dépend de `pipeline_has_tasks`, qui refuse. Son témoin vaut donc pour v0.29.9 sous les deux juges, et pour v0.30.0 sous reserve-c seulement.

## Ce qui est mesuré

[`temoins.sh`](../essais/chains-v0300-signature/temoins.sh) part du banc de signature, avec `main.go` inchangé. Chaque témoin change un seul champ des objets de j7, ou une ligne de la liste revue. Il est signé par v0.29.9 et par v0.30.0, chaque fois sur une image neuve. Il est ensuite jugé :

- par `ec` v0.10.42 avec la politique en service, comme dans `porte.sh` ;
- par reserve-c en diagnostic sous `kyverno apply` 1.19.2, comme dans `ivpol.sh` : bundles sans jeton TSA, referrers par repli d'étiquette, TaskRun publié avant PipelineRun.

Le cas de base (objets non changés) est signé et jugé dans le même passage, et sert de référence.

| Témoin | Champ changé | Règle visée |
|---|---|---|
| sujet | `publier` : résultat `IMAGE_DIGEST` remplacé par un digest nul | `subject_build_task_matches` |
| echec | `preparer` : condition `Succeeded` à `False` | `successful_pipeline_tasks` |
| parametre | `publier` : paramètre `digest` remplacé par un digest nul | `trusted_parameters` |
| artefact | `construire` : paramètre `SOURCE_ARTIFACT` (`oci:…@` digest nul) ajouté | `valid_trusted_artifact_inputs` |
| epingle | `publier` : digest retiré de la référence du bundle | `pinned` |
| courant | liste revue : `expires_on: 2099-12-31` ajouté à `publier-image` (`ec` seulement) | `current` |

Trois règles n'ont pas de témoin possible ici. Le banc contrôle la raison de chacune :

- **`build_script_used`** : aucune tâche de la provenance v1 n'a de champ `steps` au premier niveau. La condition de refus (`count(task_steps) == 0`) est donc déjà vraie pour v0.29.9, et la règle réussit quand même. Elle réussit à vide pour v0.29.9 aussi. Lecture, non mesurée : son message lit `build_task.name`, absent d'un TaskRun (le nom est dans `metadata.name`), ce qui rend le corps de la règle indéfini.
- **`future_deny_rule`** : elle ne s'active qu'avec `trusted_task_rules`. La liste revue est à l'ancien format `trusted_tasks`.
- **`preparation_appariee`** : elle ne vise que la voie deb (`construire-deb`), absente de j7.

Tout tourne sous `unshare -rn` (boucle locale seule).

## Ce qui est déjà vu

Une sonde exploratoire est passée avant cette prédiction (hors dépôt, effacée ensuite). Elle signait seulement, sans juger, les cinq témoins sur objets, avec les deux versions. Constats :

- les deux versions signent chaque témoin sans erreur ;
- chaque champ changé se retrouve dans l'énoncé du PipelineRun signé par v0.29.9 ;
- **sujet** : une seule attestation sur l'image au lieu de deux. Chains donne le digest nul pour sujet à l'attestation du TaskRun `publier`, et ajoute ce digest au sujet du PipelineRun (deux sujets : l'image et le digest nul).

Aucun jugement n'a été vu avant cette prédiction.

## Prédiction

| | Énoncé |
|---|---|
| Y1 | Base : `ec` refuse v0.29.9 par `porte.fermeture_plateforme` seul, et v0.30.0 par les trois codes du passage -3. reserve-c : 0 `ko` pour v0.29.9, les deux codes du passage -2 pour v0.30.0. Chaque diagnostic retient la provenance du PipelineRun |
| Y2 | Pour v0.29.9, chaque témoin ajoute exactement ces codes, sans en retirer. Chez `ec` : `subject_build_task_matches`, `successful_pipeline_tasks`, `trusted_parameters` et `valid_trusted_artifact_inputs` en refus ; `current` en avertissement ; `pinned` en avertissement avec `trusted` en refus (epingle). Sous reserve-c, les mêmes cinq premiers en `ko`, et `pinned` en `avert` avec `trusted` en `ko` |
| Y3 | Pour v0.30.0, aucun témoin ne change l'ensemble des codes refusés ou avertis, ni chez `ec` ni sous reserve-c. Ces règles réussissent donc à vide pour v0.30.0 |
| Y4 | Les trois règles sans témoin sont en succès pour les deux versions, avec leur raison contrôlée : 0 tâche avec `steps`, 0 `trusted_task_rules`, 0 `construire-deb` |
| Y5 | Contrôles du banc (isolement, versions, `main.go`, bibliothèque, un seul fichier changé par témoin, sujet à une attestation) OK ; 0 KO, moins de 3 minutes |

Points incertains, écrits d'avance :

- **sujet** : reserve-c compte le digest de l'image parmi les digests sûrs, comme `ec` (composant du snapshot). La prédiction est donc que `trusted_parameters` ne bouge pas, même si le résultat de `publier` devient nul.
- **artefact** : chez `ec`, une entrée Trusted Artifacts fait passer `trusted` dans sa voie par chaîne de dépendances. Toutes les tâches étant approuvées, la prédiction est qu'il ne refuse pas.

Si Y3 tombe pour un témoin, la règle lit au moins une tâche de v0.30.0, et c'est l'écart à expliquer. Si Y2 tombe, le témoin ne prouve rien pour sa règle, et celle-ci reste sans témoin.

## Réserves écrites d'avance

- Les réserves des deux bancs précédents : bundles sans jeton TSA, referrers par repli d'étiquette, CLI et non admission, registre en HTTP, un seul cas.
- Un témoin par règle, sur un seul champ : il montre que la règle sait refuser ce cas, pas qu'elle refuse tout ce qu'elle devrait.
- `current` est témoigné par la liste revue (`ec` seulement) ; reserve-c n'a pas cette règle.

## Résultat du passage 1 (note de 2026-11-26T09:29:27Z)

Commit de la prédiction : `7aef1c22`. [Journal](chains-v0300-temoins.log) : 2026-11-26T09:28:18Z → 09:28:45Z, 27 s, 135 OK, 4 KO.

Y1, Y4 et Y5 (hors KO) sont tenues. Y2 et Y3 sont tenues pour echec, parametre, artefact, epingle et courant, sous les deux juges.

**Le témoin sujet donne les 4 KO, par une faute de prédiction.** La règle visée se comporte comme prévu :

- `subject_build_task_matches` passe de succès à refus pour v0.29.9 chez `ec`, et de `ok` à `ko` sous reserve-c ;
- elle reste en succès (`ok`) pour v0.30.0.

Mais le témoin retire aussi la signature de l'image, pour les deux versions. `builtin.image.signature_check` et `porte.image_signature` refusent chez `ec`, et `builtin.image.signature_check` est `ko` sous reserve-c. Chains signe l'image depuis le TaskRun `publier`, dont le résultat `IMAGE_DIGEST` est devenu le digest nul. La sonde l'avait montré pour l'attestation du TaskRun, mais je n'en ai pas tiré la conséquence pour la signature. C'est une lecture : le passage 1 ne contrôle pas l'absence de signature.

Correction : pour le témoin sujet, ces codes de signature sont attendus pour les deux versions, et le banc contrôle que l'image est signée ou non (`cosign verify`). Les contrôles « v30 inchangé » deviennent « codes ajoutés » et « codes retirés » pour v0.30.0, vides sauf pour sujet. Rien d'autre ne change.

## Prédiction du passage -2 (2026-11-26T09:29:27Z)

Mêmes énoncés Y1 à Y5, avec ces changements :

- sujet : image non signée pour les deux versions (les autres témoins et la base : signée) ;
- Y2 pour sujet : `builtin.image.signature_check` et `porte.image_signature` en plus chez `ec`, `builtin.image.signature_check` en plus sous reserve-c ;
- Y3 pour sujet : ces mêmes codes de signature ajoutés pour v0.30.0, et rien d'autre.

0 KO attendu.

## Résultat du passage -2 (note de 2026-11-26T09:30:15Z)

Commit de la prédiction : `983aa98d`. [Journal](chains-v0300-temoins-2.log) : 2026-11-26T09:29:42Z → 09:30:11Z, 29 s, 164 OK, 0 KO. L'état des règles visées est identique à celui du passage 1, avec en plus les lignes de signature d'image du témoin sujet.

| Prédiction | Verdict |
|---|---|
| Y1 | **Tenue** : base v0.29.9 refusée par `porte.fermeture_plateforme` seul, v0.30.0 par les trois codes du passage -3 ; reserve-c, 0 `ko` et les deux codes du passage -2 ; chaque diagnostic retient la provenance du PipelineRun |
| Y2 | **Tenue** : pour v0.29.9, chaque témoin ajoute exactement les codes prédits, sans en retirer, sous les deux juges (signature d'image comprise pour sujet) |
| Y3 | **Tenue** : pour v0.30.0, aucun témoin ne change les codes, sauf la signature d'image retirée par sujet, comme prédit au passage -2 |
| Y4 | **Tenue** : `build_script_used`, `future_deny_rule` et `preparation_appariee` en succès pour les deux versions ; 0 tâche avec `steps`, 0 `trusted_task_rules`, 0 `construire-deb` |
| Y5 | **Tenue** : 0 KO, 29 s ; image non signée pour sujet seulement |

**Ce que le banc établit.** Ces règles savent refuser (ou avertir) quand elles voient les tâches, et chacune a maintenant un témoin pour v0.29.9 :

- chez `ec` : `subject_build_task_matches`, `successful_pipeline_tasks`, `trusted_parameters`, `valid_trusted_artifact_inputs`, `pinned` et `current` ;
- sous reserve-c : les mêmes, sauf `current`, que reserve-c n'a pas.

Pour v0.30.0, le même champ changé ne change rien : elles réussissent à vide. Pour `successful_pipeline_tasks` chez `ec`, la règle reste absente (elle dépend de `pipeline_has_tasks`).

Trois règles n'ont pas de témoin possible sur j7, et elles réussissent à vide pour v0.29.9 aussi :

- `build_script_used`, faute de champ `steps` lisible ;
- `future_deny_rule`, faute de `trusted_task_rules` ;
- `preparation_appariee`, faute de voie deb.

Le témoin sujet retire aussi la signature de l'image, pour les deux versions. Il ne prouve donc la règle visée que par l'état de cette règle, pas par un ensemble de codes inchangé par ailleurs.

Réserves, celles écrites d'avance :

- celles des deux bancs précédents : bundles sans jeton TSA, referrers par repli d'étiquette, CLI et non admission, registre en HTTP, un seul cas ;
- un témoin par règle, sur un seul champ ;
- `current` témoigné par la liste revue, chez `ec` seulement.

Non couverts : KMS, contrôleur, Zot réel, admission, la porte Kyverno de l'autre session ; `build_script_used` et `future_deny_rule` sur une autre forme de provenance ou de liste ; `preparation_appariee` sur un cas deb.
