# F3 : bascule de la construction sur la fermeture de la plateforme, D5 et D6 (prédictions et résultats)

Script : [`bascule.sh`](../bascule.sh) (`mise run fermetures:f3 -- <étape>`). Préparation à sec demandée par le propriétaire le
03/11/2026 (« continue », après la question « Je prépare F3 à sec ? »), compris comme un oui à la **préparation à sec seulement** :
rien n'est poussé dans Zot ni appliqué au cluster avant l'accord d'exécution. Seule l'étape `regle` (hôte, sans réseau vers le
PoC) est lancée pendant la préparation.

## Prédictions de `regle` (03/11/2026, 18:45 UTC, avant toute exécution)

Étape sur l'hôte : `ec opa check` puis `ec opa test` de [`porte.rego`](../../08-trust-plane/politique/porte/porte.rego) (règle
`porte.fermeture_plateforme`, D6) avec ses tests
([`porte_test.rego`](../../08-trust-plane/politique/porte/porte_test.rego)), la bibliothèque conforma/policy v1.0.28
(commit `ebd3fbd2`, cache de la 08) et la liste revue (`taches.yml`). `ec.sigstore.verify_attestation` est simulé.

1. `ec opa check` : aucune erreur. **Peu sûr** : la règle est écrite sans avoir été évaluée ; une erreur de syntaxe ou de type au
   premier passage est plausible (elle serait corrigée et le passage raté archivé).
2. `ec opa test` : 15 tests, tous réussis. Mêmes réserves ; en particulier :
   - le chargement de `taches.yml` à la racine de `data` (`data.trusted_tasks`) par `ec opa test` n'est pas vérifié ;
   - le remplacement d'une fonction intégrée propre à ec (`ec.sigstore.verify_attestation`) par `with` n'est pas vérifié.
3. Cas refusés : fermeture de l'hôte (« no matching attestations » dans le message), clé absente, sans résultat de fermeture,
   référence sans digest, attestation de TaskRun seule, tâche en trop, tâche hors de la liste revue, digest publié différent,
   autre dépôt Forgejo, builder inconnu, dépôt hors de `builds/fermetures/`, ancienne provenance redevenue la plus récente.
4. Cas acceptés : fermeture de la plateforme, une provenance conforme parmi plusieurs, ancienne provenance suivie d'une nouvelle
   (seule la plus récente est jugée), image d'essai sans `preparer-entrees` ni `construire-image` (règle hors champ).

## Résultats de `regle`, premier et deuxième passages (18:46 UTC)

- **Premier passage, 12/15** ([journal](f3-regle-premier-passage.log)) : les trois cas acceptés échouent. Les simulations
  renvoyaient l'énoncé nu, alors que `ec.sigstore.verify_attestation` renvoie des éléments `{statement, signatures}` (code de ec
  v0.10.42, `internal/rego/sigstore/sigstore.go`, `attestationResult`). La règle lisait `att.statement`, conformément au code de ec ;
  ce sont les tests qui étaient faux. Les 12 refus de ce passage ne prouvaient donc rien.
- **Deuxième passage, 15/15** ([journal](f3-regle-deuxieme-passage.log)), simulations corrigées. `ec opa check` sans erreur ;
  `taches.yml` chargé à la racine de `data` et `with` sur la fonction de ec : vérifiés par les cas qui en dépendent.
- **Essai de mutation, hors script** (chaque condition retirée tour à tour) : 6 conditions survivent sans qu'aucun test n'échoue.
  - Le nom du sujet, le digest du sujet, `IMAGE_URL`, `buildType` et `predicateType` ne sont couverts par aucun test.
  - La comparaison de l'ensemble des noms de tâches est **redondante** : `count(taches) == 2` et la présence de
    `publier-fermeture` et de `prefetch-gomod` l'impliquent. Elle est retirée.

## Additif du 03/11/2026, 18:47 UTC (avant le troisième passage)

Six tests ajoutés (nom et digest du sujet, `IMAGE_URL`, tâche en double, `buildType`, `predicateType`) ; l'essai de mutation
entre dans l'étape `regle` (13 conditions listées dans le script).

5. `ec opa test` : 21 tests, tous réussis.
6. Mutations : chacune des 13 conditions retirée fait échouer au moins un test.

## Résultats des troisième et quatrième passages, additif (03/11/2026, 18:48 UTC)

- **Troisième passage** ([journal](f3-regle-troisieme-passage.log)) : 21/21 ; arrêt à la première mutation survivante,
  `predicateType`. **Quatrième passage** ([journal](f3-regle-quatrieme-passage.log)), toutes les mutations rapportées :
  **12 conditions sur 13 couvertes** ; seule `predicateType` survit.
- Explication, lue dans la bibliothèque (`policy/lib/tekton/task.rego`, `_maybe_tasks`) : `tekton.tasks` ne lit les entrées
  `pipelineTask` que d'une provenance `https://slsa.dev/provenance/v1`. Avec un autre type, aucune tâche n'est vue et
  `count(taches) == 2` refuse. La condition est gardée, explicite et indépendante de la bibliothèque ; le script attend sa survie.

7. Cinquième passage : 21/21 ; 12 mutations font échouer au moins un test ; `predicateType` survit, comme attendu.

## Résultats de `regle`, cinquième passage (18:48 UTC)

**Conforme** ([journal](f3-regle.log)) : `ec opa check` sans erreur ; 21 tests sur 21 ; les 12 conditions testables font chacune
échouer au moins un test quand elles sont retirées ; `predicateType` survit, comme attendu. Limite : ces tests jugent la logique de
la règle sur des provenances simulées ; la vérification réelle par ec (clé de Chains lue dans les options, lecture anonyme de
Zot depuis le pod de la porte, `.att` de la fermeture) n'est mesurée qu'à l'étape `porte`, sous accord.

Relance du script final à 18:54 UTC : `politique.sh` est désormais sourcé (fonctions `juger`, `cm_porte`, `passage`). Un
premier lancement à 18:54:11 a échoué au contrôle de la bibliothèque, à cause d'une collision de `CPOL_COMMIT` avec
`politique.sh` (huit caractères contre quarante). Son journal a été écrasé par le lancement suivant et n'est pas archivé.
Le lancement de 18:54:27 est conforme : 21/21, 12 mutations détectées, `predicateType` survit. Les étapes de `politique.sh`
sont retirées de `bascule.sh` après le chargement : seules les étapes de F3 sont appelables.

## Prédictions des étapes sur le cluster (03/11/2026, 18:54 UTC, avant tout accord d'exécution)

Ordre proposé : `taches` (passe `SIGNER=construire-image`, revue de la liste, passe normale), `porte`, `temoins`,
`lecture_seule`, `construire`, `provenance`, `bascule`.

**`taches`** (écritures dans Zot : bundles par `poc-ecriture`)
1. `preparer-entrees` et `publier-image` : gabarits inchangés, signatures versionnées conformes, bundles **identiques à J7**
   (`2070d601`, `d21931f3`), dans la liste revue.
2. `construire-image` (D5) : passe `SIGNER=construire-image`, nouvelle signature et **nouveau bundle**, absent de la liste.
   Arrêt pour la revue de `taches.yml` par le propriétaire (ajout, et retrait éventuel de `403ccbd8`), puis passe normale.
3. Pipeline `sample-app` signée, bundle à l'étiquette `f3`, fermeture épinglée `builds/fermetures/sample-app@74c265e7`.

**`porte`** (ConfigMap `porte` modifiée durablement)
4. `porte.rego` et `taches.yml` de la ConfigMap identiques aux fichiers versionnés.
5. Image réelle `3a7ca1b1` avant la construction : **refusée**.
   - Violations : `porte.fermeture_plateforme`, plus `trusted_task.trusted` si `403ccbd8` est retirée de la liste.
   - Message : référence `entrees/sample-app/fermeture@0ab5a507`, avec 0 provenance vérifiée. **Peu sûr** : l'erreur de
     cosign pour une fermeture sans `.att` devrait contenir « no matching attestations » ou « no signatures found ».
   - Horodatage et VSA inchangés (ok).
   - **Peu sûr aussi** : c'est le premier appel réel de `ec.sigstore.verify_attestation` depuis le pod de la porte (clé
     prise dans les options de ec, lecture anonyme de Zot). Un échec technique donnerait le même refus, pour une autre
     raison : le message le dira.
6. Témoin hors règle `builds/essai-webhook@3a7ca1b1` : verdict de ec identique à `c6-sans-vsa` (mêmes trois violations de
   source, avertissement `trusted_task.tagged`) ; aucune violation `porte.fermeture_plateforme`.

**`temoins`** (Zot : `entrees/sample-app/fermeture-alteree` par `poc-ecriture`, bundles ; cluster : deux PipelineRuns)
7. Zip de `go-chi/chi/v5@v5.2.3` modifié (un fichier `.go`), zip valide, fermeture altérée de digest différent de `74c265e7`.
8. `f3-alteree` : `preparer` réussit ; `construire` échoue au `go build` sur « checksum mismatch » (`go.sum`) ; `publier`
   jamais lancé.
9. `f3-absente` : `preparer` échoue au tirage (« not found ») ; ni `construire` ni `publier`.
10. Aucune écriture de `poc-images` dans `builds/essai-f3`.

**`lecture_seule`** (cluster : un PVC et trois pods, supprimés à la fin)
11. Le pod runc écrit `entrees/temoin`. Dans le pod Kata privilégié en root, `/e` est monté `ro`. La lecture réussit et
    l'écriture est **refusée** (système de fichiers en lecture seule).
12. **Remontage `rw` : accepté dans l'invité** (root, `CAP_SYS_ADMIN`). L'écriture qui suit, **peu sûr, non lu dans le code de
    Kata 4.3.1** :
    - hypothèse principale : refusée, si Kata partage les volumes `readOnly` en lecture seule côté hôte ;
    - sinon acceptée : la lecture seule ne serait alors qu'une protection contre l'erreur, pas une frontière, et ce serait
      consigné comme limite de D5.
    Le relevé côté PVC tranche.

**`construire`** (cluster : un PipelineRun ; Zot : enveloppes de Chains sur `builds/sample-app`)
13. `f3-construire` réussit. Le montage de `construire` montre `entrees` en sous-dossier `entrees`, `readOnly` ;
    « écriture refusée » apparaît dans le journal.
14. BuildKit lit le layout de l'image de build en lecture seule sans erreur : le magasin local de containerd v2.4.1 ne crée
    `ingest` qu'à la première écriture (`plugins/content/local/store.go`). Un avertissement fsverity est possible.
15. **Image `3a7ca1b1`, identique** : mêmes sources, même Dockerfile, même image de build, mêmes fichiers gomod (F2). Les
    différences de la fermeture (`.build-config.json`, archive npm absente) ne sont pas lues par le Dockerfile.
16. Chains signe le PipelineRun (deux enveloppes de plus, horodatées au passage suivant du CronJob).
17. Porte : **admise**. ec `true`, aucune violation, avertissement `trusted_task.tagged` ; horodatage ok ; VSA ok. La VSA
    retenue atteste le rejeu de la provenance de J7 (constat, voir les effets).

**`provenance`**
18. Une enveloppe du PipelineRun `f3-construire`.
    - Fermeture : `oci://…/builds/fermetures/sample-app`, digest `74c265e7`.
    - Bundle `construire-image` : celui de l'étape `taches`.
    - Workspaces du TaskRun `construire` dans le contenu signé : `entrees:entrees,sortie:image`.
    - Autre clé refusée.

**`bascule`** (cluster : TriggerTemplate `sample-app` de `declencheurs`)
19. Gabarit en service rendu avec la pipeline de F3, appliqué, relu.
