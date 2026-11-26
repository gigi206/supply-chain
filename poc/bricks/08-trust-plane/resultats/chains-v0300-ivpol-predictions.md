# Brique 08 : les politiques Kyverno jugent les attestations signées par Chains v0.30.0, prédiction

Note de 2026-11-26T09:05:46Z, écrite avant le lancement. Ce banc suit celui de la [porte Conforma](chains-v0300-porte-predictions.md) (passage -3), qui laissait `ivpol` non couvert. Il est local : pas de cluster, pas de VM, pas de vrai Zot, pas de clé réelle, pas de TSA.

Choix du propriétaire du 26/11 : « Banc ivpol à sec ».

## Ce qui est mesuré

[`ivpol.sh`](../essais/chains-v0300-signature/ivpol.sh) part du banc de signature, avec `main.go` inchangé. Il signe les vrais objets de `j7-sample-app`, une fois avec v0.29.9 et une fois avec v0.30.0, chaque version sur sa propre image, dans un registre en mémoire servi en HTTP sur 127.0.0.1. Le CLI Kyverno 1.19.2, épinglé dans `mise.toml`, juge ensuite chaque image par `kyverno apply`.

Kyverno lit la même forme d'entrée que le job d'horodatage produit : des bundles Sigstore v0.3 publiés en referrers de l'image, dans le dépôt séparé `horodatage/bundles`. Le banc les fabrique comme `tsa/horodater.sh` :

- `cosign bundle create` sur chaque enveloppe de Chains ;
- puis `cosign verify-blob-attestation`, qui vérifie la clé, le sujet et le prédicat.

L'ordre de publication est fixé : le bundle du TaskRun d'abord, celui du PipelineRun ensuite. Kyverno garde la dernière provenance valide. Chaque diagnostic contrôle donc que la provenance retenue est celle du PipelineRun : l'invocationId doit être égal à l'uid du PipelineRun (`9539952b…`).

Deux politiques sont jugées :

- **reserve-c** : `politique/reserve-c/ivpol.tmpl.yaml`, rendue par `generer.py` avec la liste revue et les builders de la porte et la source de j7. Elle tourne en mode diagnostic (statut de chaque règle) et en mode décision.
- **Contrôle 9** : la fonction `ivpol` de `commun.sh`, lue dans le fichier. Elle ne vérifie que la signature des bundles. Elle tourne sans `tsaCertChain`.

Témoins :

- la liste revue sans le digest de `publier-image`, pour `trusted_task.trusted` ;
- une autre clé publique, pour reserve-c et pour le contrôle 9.

Tout tourne sous `unshare -rn` (boucle locale seule).

## Ce qui est déjà vu

Une sonde exploratoire est passée avant cette prédiction (hors dépôt, effacée), avec le même CLI, sur les mêmes objets et le même registre. Elle était en mode diagnostic seulement, avec l'ordre de publication laissé à `cosign download attestation`.

- **v0.29.9** : provenance du PipelineRun retenue. Toutes les règles de reserve-c sont `ok`, sauf `trusted_task.tagged`, en avertissement trois fois.
- **v0.30.0** : provenance du PipelineRun retenue. Deux règles sont `ko` : `slsa_build_scripted_build.build_task_image_results_found` et `tasks.pipeline_has_tasks`. `trusted_task.trusted` et `trusted_task.tagged` sont `ok`.

Les lignes X1 et X2 ci-dessous rejouent donc la sonde. Elles ne peuvent tomber que si le banc diffère de la sonde. Les lignes X3 à X7 sont nouvelles.

## Prédiction

| | Énoncé |
|---|---|
| X1 (rejeu) | Les deux versions signent sans erreur, avec 2 attestations chacune. Chaque bundle est créé, vérifié et publié dans l'ordre TaskRun puis PipelineRun. Chaque diagnostic retient la provenance du PipelineRun |
| X2 (rejeu) | reserve-c, diagnostic : 0 règle `ko` pour v0.29.9 ; pour v0.30.0, exactement `build_task_image_results_found` et `pipeline_has_tasks` |
| X3 | reserve-c, décision : v0.29.9 `pass`, v0.30.0 `fail`, avec pour motif exactement ces deux règles |
| X4 | Témoin `trusted_task.trusted` : `ko` pour v0.29.9 (seul code de plus), `ok` pour v0.30.0, dont les échecs restent les mêmes. La règle réussit donc à vide sous Kyverno aussi |
| X5 | Témoin de clé : signature d'image et signature de la provenance `ko` pour les deux versions |
| X6 | Contrôle 9 : `pass` pour les deux versions, car il ne lit pas le contenu ; `fail` pour les deux avec l'autre clé |
| X7 | Contrôles du banc (isolement, kyverno 1.19.2, `main.go`, rendu, chaque `apply` évalué) OK ; 0 KO, moins de 60 s |

Si X4 tombe, `trusted_task.trusted` de reserve-c ne lit pas les tâches de v0.30.0 comme la bibliothèque, et c'est l'écart à expliquer.

## Réserves écrites d'avance

- Les bundles n'ont pas de jeton TSA ; en service, ils en ont un.
- Les referrers passent par le repli par étiquette, pas par l'API referrers de Zot.
- On mesure le CLI, pas l'admission ; le registre est en HTTP ; un seul cas.
- reserve-c n'a pas d'équivalent de `porte.taches_vues`, de Kata ni de la fermeture. Son refus de v0.30.0 ne repose que sur deux règles de la bibliothèque.

## Résultat du passage 1 (note de 2026-11-26T09:06:28Z)

Commit de la prédiction : `268df164`. [Journal](chains-v0300-ivpol.log) : 2026-11-26T09:06:13Z → 09:06:21Z, 8 s, 41 OK, 1 KO.

X1 à X6 sont tenues dans le journal. **X7 n'est pas tenue**, à cause d'un défaut de la garde et non de la mesure. La garde « fonction ivpol lue dans commun.sh » coupait la première ligne à 8 caractères (`ivpol() `, espace compris) et la comparait à `ivpol()`. Le rendu du contrôle 9 a pourtant été contrôlé par la ligne suivante (sans `tsaCertChain`, une règle C9), et il a été jugé.

Correction : la coupe passe à 7 caractères. Rien d'autre ne change.

## Prédiction du passage -2 (2026-11-26T09:06:28Z)

Mêmes énoncés X1 à X7, avec la garde corrigée : 0 KO.

## Résultat du passage -2 (note de 2026-11-26T09:06:50Z)

Commit de la prédiction : `bd3d3f70`. [Journal](chains-v0300-ivpol-2.log) : 2026-11-26T09:06:39Z → 09:06:46Z, 7 s, 42 OK, 0 KO. La table d'état des règles est identique à celle du passage 1.

| Prédiction | Verdict |
|---|---|
| X1 (rejeu) | **Tenue** : bundles créés, vérifiés et publiés dans l'ordre TaskRun puis PipelineRun ; tout diagnostic à clé juste retient la provenance du PipelineRun (`9539952b…`) |
| X2 (rejeu) | **Tenue** : v0.29.9, 0 règle `ko` (`trusted_task.tagged` en avertissement 3 fois) ; v0.30.0, exactement `build_task_image_results_found` et `pipeline_has_tasks` |
| X3 | **Tenue** : décision `pass` pour v0.29.9, `fail` pour v0.30.0, avec ces deux règles pour motif |
| X4 | **Tenue** : liste revue sans `publier-image`, `trusted_task.trusted` est `ko` pour v0.29.9 (seul code de plus) et `ok` pour v0.30.0 (échecs inchangés) |
| X5 | **Tenue** : avec l'autre clé, signature d'image et de provenance `ko` pour les deux versions (aucune provenance retenue) |
| X6 | **Tenue** : contrôle 9 `pass` pour les deux versions, `fail` pour les deux avec l'autre clé. Le message reste « provenance sans horodatage RFC 3161 valide » : il est fixe dans la politique, alors que le refus vient de la clé |
| X7 | **Tenue** : 0 KO, 7 s |

**Ce que le banc établit.** Sous Kyverno, la réserve de la décision C refuse v0.30.0 comme Conforma, par les deux mêmes règles de la bibliothèque. Elle n'a pas l'équivalent de `porte.taches_vues`, qui fait le troisième code chez Conforma. `trusted_task.trusted` y réussit à vide pour v0.30.0, comme chez Conforma ; le témoin le prouve. D'autres règles réussissent aussi pour v0.30.0, sans témoin :

- `subject_build_task_matches` ;
- `successful_pipeline_tasks` ;
- les autres règles `trusted_task.*`.

`trusted_task.tagged` passe d'avertissement à succès, ce qui est cohérent avec une règle qui ne voit plus de tâche (sans témoin). Écart de parité : `tasks.successful_pipeline_tasks` est `ok` sous reserve-c pour v0.30.0, mais absent chez `ec`.

Le contrôle 9 admet les deux versions dans ce banc : il ne vérifie que la signature des bundles et ne lit pas leur contenu. La voie avec jeton TSA et `tsaCertChain` n'est pas mesurée. Ce banc ne dit pas non plus quelle politique est posée dans le cluster : ce n'est pas vérifié.

Réserves, celles écrites d'avance :

- bundles sans jeton TSA ;
- referrers par le repli par étiquette ;
- le CLI et non l'admission ;
- registre en HTTP ;
- un seul cas ;
- refus de reserve-c tenu par deux règles seulement.

Non couverts : KMS, contrôleur, Zot réel, admission, la porte Kyverno de l'autre session.
