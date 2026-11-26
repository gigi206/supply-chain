# Brique 08 : la porte Conforma juge les attestations signées par Chains v0.30.0, prédiction

Note de 2026-11-26T08:43:24Z, écrite avant le lancement. Suite du [banc de signature](chains-v0300-signature-predictions.md) (passage -4 : énoncé signé égal à la sortie à sec), qui laissait `ec validate image` non couvert. Banc local, sans cluster, sans VM, sans le vrai Zot, sans clé réelle.

## Ce qui est mesuré

[`porte.sh`](../essais/chains-v0300-signature/porte.sh) : le banc de signature (`main.go`, inchangé) signe les vrais objets de `j7-sample-app` avec v0.29.9 puis v0.30.0, chacun sur sa propre image, dans un registre en mémoire. Ensuite `ec validate image` les juge comme le Job de la porte (`--strict=false`, `--ignore-rekor`, clé publique, `SIGSTORE_REKOR_PUBLIC_KEY`).

- Le binaire `ec` est v0.10.42. Le script contrôle son empreinte contre `EC_BIN` de `politique.sh`, celle que l'image de la porte embarque.
- La politique est celle de la porte en service :
  - la bibliothèque conforma/policy `ebd3fbd2`, prise dans le dépôt nu de la 08 ; l'arbre `0fd26021` est vérifié et les tests sont retirés, comme dans l'image ;
  - `porte.rego` et `taches.yml` du dépôt ;
  - `policy.yaml` du dépôt, où seuls les chemins changent.
- Tout tourne dans un espace réseau neuf (`unshare -rn`, sans sudo, boucle locale seule) : un appel vers l'extérieur échouerait au lieu de partir.

## Écarts au service, voulus

- Le nom du registre `sc-stockage.poc.test:5000` est remplacé par celui du banc :
  - dans les objets (déjà le cas au passage -4) ;
  - dans `porte.rego` (1 ligne) et `taches.yml` (15 lignes).

  Le remplacement est identique pour les deux versions.
- Les bundles de tâches et les fermetures que la politique va lire (`ec.oci.image_manifests`, `ec.sigstore.verify_attestation`) ne sont pas dans le registre du banc. Les refus qui en découlent sont dus au banc. Ils sont les mêmes pour v0.29.9 et v0.30.0.
- **La mesure est donc l'écart entre les deux ensembles de codes refusés**, pas le verdict de chaque version.
- Le banc à sec du 25/11 ([lecteurs-3](chains-v0300-lecteurs-3.log), P5), qui disposait des vrais manifestes et des vraies fermetures, avait trouvé que l'énoncé neuf seul ajoutait quatre codes : `porte.taches_vues`, `slsa_build_scripted_build.build_task_image_results_found`, `slsa_build_scripted_build.image_built_by_trusted_task`, `tasks.pipeline_has_tasks`. Les paquets `tasks` et `slsa_build_scripted_build` font partie de `@slsa3`, que la porte inclut.

## Prédictions

- **U1** : le banc n'a qu'une interface et aucune route. `ec` a l'empreinte du verrou et l'arbre de la bibliothèque est conforme. Confiance très bonne.
- **U2** : les deux versions signent sans erreur, et `cosign verify-attestation` lit 2 attestations par image, comme au passage -4. Confiance très bonne.
- **U3** : `ec` rend le code 0 pour chaque jugement (`--strict=false`), et aucun ne réussit (`success` faux), à cause des refus dus au banc. Confiance moyenne.
  - Je ne sais pas d'avance comment la bibliothèque traite un bundle introuvable.
  - Les codes dus au banc devraient appartenir à `porte.fermeture_plateforme`, `porte.preparation_appariee` et `trusted_task.*`.
  - Si v0.29.9 était admis, U3 serait non tenue sans que la mesure en souffre.
- **U4 (décisive)** :
  - aucun code n'est refusé pour v0.29.9 sans l'être aussi pour v0.30.0 ;
  - `porte.taches_vues` est dans l'écart et absent pour v0.29.9 ;
  - l'écart est contenu dans les quatre codes du banc à sec.

  Confiance bonne. L'écart est égal aux quatre codes : confiance moyenne, car un bundle introuvable peut faire refuser `image_built_by_trusted_task` aux deux versions et le sortir de l'écart.
- **U5 (témoin)** : v0.30.0 jugée avec une autre clé publique.
  - `ec` rend 0 et `success` est faux.
  - `porte.taches_vues` est absent, puisque rien n'est lu.
  - Les codes de refus portent sur la vérification de signature. Je m'attends à `builtin.image.signature_check` et `builtin.attestation.signature_check`, sans être sûr des noms. Confiance moyenne sur les noms, bonne sur le reste.
- **U6** : moins de 5 min au total. Confiance bonne.

Les contrôles `attendu` du script couvrent U1, U2, U4 et le témoin ; U3, les noms de U5 et U6 seront lus dans le journal.

## Non couvert

- KMS et contrôleur réel.
- Zot réel, bundles et fermetures réels : le banc à sec les avait, ce banc ne les a pas.
- `ivpol`, Kyverno, horodatage (contrôle 9), VSA (contrôle 6), scan (contrôle 7).
- Un seul cas (`j7-sample-app`).

## Résultat (note de 2026-11-26T08:44:43Z)

Commit de la prédiction : `d30d4932`. [Journal](chains-v0300-porte.log) : 2026-11-26T08:43:54Z → 08:43:58Z, 4 s, 1 KO.

| Prédiction | Verdict |
|---|---|
| U1 | **Tenue** : 1 interface, 0 route ; `ec` v0.10.42 à l'empreinte du verrou ; arbre `0fd26021`, 76 fichiers Rego |
| U2 | **Tenue** : les deux versions signent sans erreur ; 2 attestations vérifiées par image |
| U3 | **Tenue sur le verdict, non tenue sur les codes** : code 0 et `success` faux pour les deux. Codes dus au banc : `porte.fermeture_plateforme` pour v0.29.9 seule (fermeture absente du registre du banc), et `slsa_source_correlated.source_code_reference_provided` pour les deux. Ce second code vient de l'appel, pas du registre : aucune source attendue n'est fournie à `ec`, comme pour l'image réelle de J6 (README de la 08, réglé au test 7). Je ne l'avais pas prévu. Bundles introuvables : 9 erreurs d'`ec` pour v0.29.9 (3 bundles, `NAME_UNKNOWN`), 3 avertissements `trusted_task.tagged`, mais **aucun refus** de `trusted_task` |
| U4 | **Non tenue sur la première partie** : `porte.fermeture_plateforme` est refusé pour v0.29.9 et pas pour v0.30.0. **Tenue** sur les autres : `porte.taches_vues` est dans l'écart et absent pour v0.29.9 ; l'écart (`porte.taches_vues`, `slsa_build_scripted_build.build_task_image_results_found`, `tasks.pipeline_has_tasks`) est contenu dans les quatre codes du banc à sec. Il en compte trois : `image_built_by_trusted_task` appartient aux collections `redhat` et `redhat_security`, pas à `@slsa3`. Le banc à sec évaluait les paquets entiers ; j'avais vérifié l'appartenance par fichier et non par règle |
| U5 | **Tenue** : code 0, `success` faux, refus `builtin.attestation.signature_check` et `builtin.image.signature_check` (noms attendus), 0 attestation lue, `porte.taches_vues` absent |
| U6 | **Tenue** : 4 s |

**Faute de prédiction (U4)** : j'ai tenu le refus de fermeture pour un effet du banc, le même pour les deux versions. Or le banc à sec l'avait déjà mesuré : avec l'énoncé neuf, `fermeture_plateforme` et `construction_kata` sont muettes. Une règle qui ne voit aucune tâche ne cherche pas de fermeture.

**Ce que le banc établit.** Les règles réussies, comparées entre les deux versions (relevé du 2026-11-26T08:44Z, `succes-29.txt` et `succes-30.txt` dans le dossier de travail) :

- v0.30.0 seule : `porte.fermeture_plateforme` et `trusted_task.tagged` y passent de refus ou avertissement à **réussite** ;
- v0.29.9 seule : `porte.taches_vues`, `slsa_build_scripted_build.build_task_image_results_found`, `tasks.pipeline_has_tasks` et `tasks.successful_pipeline_tasks` ; cette dernière n'apparaît pour v0.30.0 ni en réussite ni en refus ;
- pour v0.30.0, `porte.construction_kata` et les règles `trusted_task` qui jugent les tâches (`trusted`, `pinned`, `current`) réussissent alors qu'aucune tâche n'est vue. `ec` ne lit même pas les bundles (0 erreur, 0 avertissement). `porte.preparation_appariee` réussit pour les deux versions ; je n'ai pas vérifié si elle réussit à vide pour v0.30.0.

Sur une vraie signature, la porte en service refuse donc v0.30.0 : `ec` vérifie les deux signatures, lit les deux attestations et rend trois refus. Mais **la fermeture de la porte tient à trois règles seulement** : `porte.taches_vues`, qui est maison, et deux règles de `@slsa3`. Les contrôles de Kata, de fermeture et de tâches de confiance réussissent à vide. Une adaptation des lecteurs qui ferait passer `taches_vues` sans réapprendre les noms aux autres règles admettrait une image sans aucun de ces contrôles. Le témoin montre que le refus vient bien de la politique : avec une autre clé, rien n'est lu et seules les règles de signature refusent.

Non couverts, inchangés : KMS, contrôleur, Zot réel (bundles et fermetures), `ivpol`, Kyverno, contrôles 6, 7 et 9, un seul cas.

## Relecture du conseiller et prédiction du passage -2 (note de 2026-11-26T08:48:46Z)

**Corrections du résultat ci-dessus**, sur avis du conseiller :

- **Preuve non archivée.** Les listes de réussites viennent d'une commande hors du script, dans un dossier que le prochain lancement efface. Le passage -2 écrit l'état de chaque règle dans son journal.
- **« À vide », démontré pour la fermeture seulement.** Pour la fermeture, le premier passage le montre directement : la fermeture est absente pour les deux versions ; v0.29.9 est refusée, v0.30.0 réussit. Pour `construction_kata`, c'est `porte.rego` qui le dit (« Sans TaskRun de construire-image, la règle ne refuse rien (succès à vide) »), et le banc à sec du 25/11 l'avait trouvée muette. Pour `trusted_task`, c'est une déduction : `trusted` réussit aussi pour v0.29.9 sans bundles. Le passage -2 ajoute un témoin.
- **« Admettrait une image sans aucun de ces contrôles » est faux tel quel.** Si `porte.taches_vues` passait seule, deux règles de `@slsa3` refuseraient encore. Et `porte.rego` montre que ses trois règles de tâches (`taches_vues`, `construction_kata`, `fermeture_plateforme`) lisent la même extraction, `lib.tasks_from_pipelinerun`, de la bibliothèque. Critère pour toute adaptation : la corriger là où les tâches sont extraites, puis montrer qu'un témoin fautif est refusé par chaque règle.
- **« Vient de l'appel »**, précisé : depuis le test 7, `politique.sh` passe l'image par `--images` avec la source attendue (ApplicationSnapshot). Le premier passage utilisait `--image` sans source, comme J6. Le passage -2 reprend la forme du service.

**Changements du script** (passage -2) :

- source attendue passée comme en service : dépôt et commit lus dans le PipelineRun ;
- état de chaque règle `porte.*`, `trusted_task.*`, `tasks.*` et `slsa_build_scripted_build.*` pour les deux versions ;
- écart attendu ramené à trois codes ;
- `porte.fermeture_plateforme` attendue en refus pour v0.29.9 et en réussite pour v0.30.0 ;
- erreurs d'`ec` coupées à 400 caractères au lieu de 240 ;
- témoin `trusted_task` : même politique, mais le digest de `publier-image` est remplacé par un digest nul dans la liste revue.

**Prédictions** :

- **V1** : contrôles d'isolement, d'empreinte, d'arbre et de signature tenus comme au premier passage. Confiance très bonne.
- **V2** : avec la source attendue, `slsa_source_correlated.source_code_reference_provided` disparaît pour les deux versions. Confiance moyenne : d'autres codes `slsa_source_*` peuvent apparaître, la provenance du banc étant celle de j7 (dépôt et commit réels). Si aucun n'apparaît, v0.29.9 n'est plus refusée que par `porte.fermeture_plateforme`, qui est dû au banc.
- **V3** :
  - refusé pour v0.29.9 seule : `porte.fermeture_plateforme` ;
  - refusés pour v0.30.0 seule : les trois codes ;
  - fermeture : refus pour v0.29.9, réussite pour v0.30.0.

  Confiance bonne.
- **V4** : pour v0.30.0, `porte.construction_kata` et `trusted_task.trusted` réussissent, et `tasks.successful_pipeline_tasks` est absent. Pour v0.29.9, `trusted_task.tagged` est en avertissement. Confiance bonne.
- **V5 (témoin `trusted_task`)** : `trusted_task.trusted` est refusé pour v0.29.9, avec un message qui nomme la tâche `publier`, et réussit pour v0.30.0. Confiance bonne pour v0.30.0, moyenne-bonne pour v0.29.9 (au premier passage, la règle a réussi sans manifestes : elle compare donc les références à la liste).
- **V6** : le témoin de clé est inchangé : refus par les deux règles de signature, 0 attestation lue. Confiance très bonne.
- **V7** : moins d'une minute. Confiance bonne.
