# Mesures réelles restantes sous H1 à H5 : prédictions et effets à connaître

Écrit le 07/11/2026 à 08:48 UTC, avant tout passage. Rien de lancé, rien écrit dans le cluster ni dans Zot pour cette préparation. Chaque mesure demande son propre accord, après la relecture du scan planifié de 09:30 UTC.

Références : relevés à sec du 06/11 (`durcissement-h5_controleurs_sec.log`, `durcissement-h5_resolveurs_sec.log`, `durcissement-h5_figees_sec.log`), et état relevé le 07/11 de 08:44 à 08:46 UTC : gabarit en service `sample-app`, `sample-app-6391fd43…` réussi (21:42 UTC), 22 enveloppes sur l'image réelle, rattrapage à `PRESENT`, première entrée gardée de l'audit de l'API 2026-11-06T16:24:33Z.

## Commandes, dans l'ordre proposé

Depuis la racine du dépôt, une par accord :

```bash
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- controleurs </dev/null
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- resolveurs </dev/null
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- test5_refus </dev/null
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- rattrapage_durci </dev/null
```

Les journaux `resultats/preuves-h5-<étape>.log` de la 08 n'existent pas encore ; chaque passage ajoute deux lignes à `chrono.tsv`.

**Échéance.** `controleurs` cherche dans l'audit au moins un pod créé dans `builds` par le contrôleur. Le dernier date de 21:42 UTC et l'audit garde environ 16 h : passage avant environ 13:40 UTC, ou après `rattrapage_durci`.

## Effets à connaître

| Mesure | Durée prédite | Écrit | Reste après |
|---|---|---|---|
| `controleurs` | moins de 1 min (20 s le 06/11 avant H1) | Espace `preuve-controleurs`, 2 RoleBindings temporaires, supprimés | 22 refus des droits et 2 refus de la règle dans l'audit |
| `resolveurs` | moins de 1 min (11 s le 06/11 avant H1) | Espace `preuve-resolveurs`, 4 ResolutionRequests, supprimés | 1 lecture de `zot-images` par les résolveurs, lectures de Zot, refus dans l'audit (5 lectures directes, 2 résolutions) |
| `test5_refus` | moins de 1 min | Rien dans le cluster ni dans Zot ; un secret jetable en local, effacé par le trap | 4 livraisons et 1 erreur « already exists » dans les journaux |
| `rattrapage_durci` | 3 à 5 min | Rattrapage suspendu quelques minutes ; `sample-app-6391fd43…` et ses TaskRuns purgés, reconstruits sous Kata | 2 enveloppes de plus sur l'image réelle (22 → 24), définitives ; bundles d'horodatage ; Job de la porte, TTL 1 h |

Sur KO :
- `controleurs` et `resolveurs` : le trap retire l'espace d'essai, ses liaisons et les ResolutionRequests. Corrigé dans `preuves.sh` pour cette préparation : un KO laissait l'espace, donc des droits de locataire temporaires.
- `rattrapage_durci` : le trap reprend le CronJob. Si le PipelineRun est absent, le rattrapage le recrée à la minute suivante. S'il finit en échec, il reste en place et le rattrapage s'arrête à `PRESENT` : purge à faire à la main, sur accord.

## Pourquoi deux étapes nouvelles

- `test5_refus` : `test5` reste bloqué par la bascule, son commit témoin n'existe pas dans Forgejo. La nouvelle étape garde les trois livraisons refusées. Son témoin est une livraison valide de la tête de main, acceptée par les intercepteurs puis refusée à la création : rien n'est construit. Elle ne mesure ni un rejeu à l'identique, ni la création par une livraison valide (déjà couverte par `construction_durcie`).
- `rattrapage_durci` : le chemin 2 de `bascule`, seul, sur le moule de `construction_durcie`. Rejouer `bascule` ajouterait 4 enveloppes au lieu de 2 et réappliquerait le gabarit.

## Prédictions

`controleurs`, écrites sur le relevé à sec, donc pas aveugles :
- K1 : aucun KO, code 0.
- K2 : 22 essais refusés par les droits, 0 objet créé, 0 annotation posée.
- K3 : 2 refus par `ValidatingAdmissionPolicy 'tekton-controleurs-builds'` dans `preuve-controleurs`, témoin administrateur admis. **Premier passage réel sous H5 du refus par ce chemin, le point le moins sûr** : un refus pour un autre motif donne un KO.
- K4 : 6 comptes peuvent créer des pods dans `kube-system`, pod `default` admis pour chacun.
- K5 : 0 refus de la règle dans `builds`, au moins 1 pod créé par le contrôleur dans la fenêtre d'audit.
- K6 : lectures de Secrets hors de `builds` ou en 403 : 0 ; 0 redémarrage ; 0 refus des droits dans les journaux des deux contrôleurs.
- K7 : espace absent ensuite, `can-i create pods` à `no`.

`resolveurs`, même réserve :
- L1 : aucun KO, code 0.
- L2 : 5 lectures refusées par les droits.
- L3 : résolution réussie dans `builds` par le compte `default` et par le Secret `zot-images`. **Premier passage réel sous H5 du chemin du Secret.**
- L4 : deux résolutions échouées dans `preuve-resolveurs`, refus sur le compte de service puis sur le Secret.
- L5 : 2 refus des droits au journal depuis le début de l'étape, tous dans `preuve-resolveurs`.
- L6 : `get secrets builds 200` : 1 dans l'audit, celle du passage (celle de 15:25 UTC est sortie de la fenêtre) ; rien hors de `builds` sauf les 2 refus de `preuve-resolveurs`.
- L7 : 4 lecteurs des Secrets de tout le cluster.
- L8 : pod des résolveurs inchangé, créé à 13:38 UTC le 06/11, 0 redémarrage. Son redémarrage sous H5 reste non mesuré.

`test5_refus` :
- T1 : gabarit `sample-app`, `sample-app-6391fd43…` à `Succeeded`.
- T2 : HTTP 202 aux 4 livraisons.
- T3 : 1 refus `no X-Hub-Signature-256 header set`, 2 refus `payload signature check failed`, 3 refus au total. Ce compte exact n'a jamais tourné après la bascule : `construction_durcie` ne mesure que le premier refus.
- T4 : témoin dans le journal de l'EventListener, même `eventID`, `already exists`.
- T5 : 0 PipelineRun du commit `1111…` et du commit jamais livré, UID de la tête inchangé.
- T6 : image réelle inchangée, 22 enveloppes si l'étape passe avant `rattrapage_durci`.

`rattrapage_durci` :
- B1 : PipelineRun créé par `declencheurs:rattrapage`, une création, 201, label `poc.test/declencheur=rattrapage`. Première création réelle par le rattrapage depuis `h5_deny`.
- B2 : `Succeeded`, pod `construire` sous Kata sur sc-build, digest `3a7ca1b1…`, spec identique à celle de `j7-sample-app`, bundle masqué.
- B3 : une seule ligne `CREE` dans les passages depuis la reprise.
- B4 : Chains signe, enveloppes 22 → 24.
- B5 : porte `true`, aucune violation, contrôle 9 ok, provenance la plus récente = ce PipelineRun.
- B6 : aucune anomalie exécutions/enveloppes au départ ni à la fin.
- B7 : CronJob repris (`suspend=false`), passage suivant à `PRESENT`.

Hors des étapes, relevé après la dernière :
- X1 : `KyvernoRefusAnormaux` ne se déclenche pas : ces refus viennent des droits, de la règle native ou des intercepteurs, pas de Kyverno. Non mesuré jusqu'ici pour ces étapes.

## Ce que ces quatre mesures ne couvrent pas

Démarrage réel d'un nouveau pod des résolveurs, redémarrage des VM, `decision3`, `enveloppes`, verdicts propres de `reglec`, `attseule`, `controle6`, `controle7`, `temoins_scan`, test 6 sous limites, `test5` complet, `intercepteurs`.

## Complément du 07/11/2026, 08:52 UTC : admission dans les espaces d'essai, avant tout passage

Le relevé du 06/11 n'avait présenté les objets de K3 et L4 que dans `bancc` et `builds`. Vérifié en lecture seule et en dry-run serveur, K3 et L4 restent telles qu'écrites :
- L4 : aucune règle Kyverno (`validatingpolicies`, `imagevalidatingpolicies`) ni ValidatingAdmissionPolicy ne vise `resolutionrequests`. Seuls les webhooks de Tekton le font, déjà passés dans `preuve-resolveurs` le 06/11 à 15:25 UTC, avant H1 à H5.
- K3 : les règles de pods de la 08c traitent `bancc` et un espace neuf de la même façon : sélection par liste d'exclusion, ou par nom pour `default`, `builds` et la zone de confiance. La seule différence est Pod Security : `bancc` est en `privileged`. Le même pod, avec le sélecteur de zone exigé, est admis dans `scan` (`restricted`) en dry-run serveur.
- Borne : `bench-release` (`Deny`, sans sélecteur d'espace) n'a pas refusé ce pod dans `bancc` ni dans `scan` ; sa portée exacte n'a pas été relue.

Les étapes `controleurs` et `resolveurs` citent maintenant K1 à K7 et L1 à L8 dans leur journal.

## Additif du 07/11/2026, 11:22 UTC : `enveloppes` et `decision3`, prédictions avant passage

Accord du propriétaire : « Oui les 2 », pour le redémarrage des VM et pour ces deux étapes. Écrit pendant le redémarrage, avant tout passage de ces étapes sous H1 à H5. Elles passeront après le redémarrage et ses contrôles, l'une après l'autre, `enveloppes` d'abord, comme le 06/11.

Commandes, depuis la racine du dépôt. `PIPE_ESSAI` ne sert qu'à lever la garde de `pr_gabarit` : le gabarit en service n'est pas touché, et chaque étape passe sa propre pipeline signée.

```bash
DISTRO=rke2 PIPE_ESSAI=<bundle de sample-app-essai, lu sur j6-porte-en-service> JOURNAL=preuves-h5 mise run confiance:preuves -- enveloppes </dev/null
DISTRO=rke2 PIPE_ESSAI=<idem> JOURNAL=preuves-h5 mise run confiance:preuves -- decision3 </dev/null
```

Références : derniers passages le 06/11 à 15:13 et 15:14 UTC (`preuves-enveloppes.log`, `preuves-decision3.log`), avant H1, avant la bascule et avant S1. Le dernier PipelineRun créé par l'administrateur dans `builds` (test 7, 20:11 UTC) est antérieur à `h5_roles` et `h5_cilium`. `tekton-controleurs-builds` ne vise que les pods, PVC et StatefulSets des deux contrôleurs, pas un PipelineRun de l'administrateur.

`enveloppes` :
- E1 : aucun KO, code 0, moins de 3 min (27 s le 06/11).
- E2 : départ sans anomalie.
- E3 : témoins logiques comme le 06/11 : `ABSENTE` seule anomalie, puis `SUJET_NON_SIGNE` seule anomalie.
- E4 : témoin réel signé par Chains, TaskRun `publier` et PipelineRun `COUVERTE`. Tag `.att` réécrit par `poc-ecriture` : TaskRun `ABSENTE`, puis PipelineRun `DOUBLE`, puis tag d'origine remis, les deux `COUVERTE`. **Premier passage sous H5 et S1 d'une signature de Chains hors de l'image réelle**, avec les identifiants injectés.
- E5 : fin sans anomalie ; image réelle inchangée, 24 enveloppes, dernière provenance `474b3f60`.

`decision3`, sur Zot (configuration modifiée puis remise, Zot redémarré deux fois) :
- D1 : configuration en service identique à `stockage/zot.json`, sinon arrêt avant toute modification. Confiance moyenne : non relue depuis le 06/11.
- D2 : témoin direct comme le 06/11 : tag neuf créé par `poc-build`, déplacement refusé en 403, `poc-ecriture` le déplace, `poc-build` le déplace de nouveau après remise.
- D3 : un objet `signed=true`, l'autre `signed=failed` et `retries=3`, une seule enveloppe dans `.att`, au moins 5 PUT `.att` refusés. Signatures Transit : 2 + N si le PipelineRun échoue, 1 + 2N si c'est le TaskRun. Le 06/11 : PipelineRun en échec, N = 5, 7 signatures. L'ordre n'est pas prédit.
- D4 : contrôle exécutions/enveloppes : l'objet en échec `SUJET_NON_SIGNE`, seule anomalie ; fin sans anomalie après purge ; configuration d'origine remise ; rattrapage et horodatage repris.
- D5 : image réelle inchangée, 24 enveloppes. Moins de 3 min (45 s le 06/11), retries de Chains compris.

Hors des étapes :
- X2 : `KyvernoRefusAnormaux` ne se déclenche pas.

Effets à connaître : de nouvelles images et tags `.att` sur `builds/essai-decision3`, `tekton/tasks` et `tekton/pipelines`, définitifs ; le témoin de `enveloppes` est purgé puis recréé ; les exécutions de `decision3` sont purgées à la fin. Zot est indisponible quelques secondes à chaque redémarrage, CronJobs suspendus pendant ce temps.

## Correction du 07/11/2026, 11:38 UTC : E4

E4 annonçait « premier passage sous H5 et S1 d'une signature de Chains hors de l'image réelle ». C'est faux : le 06/11 à 20:11 UTC, après S1 (appliqué à 18:40 UTC) et sous les limites et `Deny` de H5, le test 7 a fait signer `preuve-test7-en-service` par Chains sur `builds/essai-webhook` ([preuves-h5-test7.log](../../08-trust-plane/resultats/preuves-h5-test7.log), « Chains : signé=true »). La nouveauté se limite à un passage postérieur à `h5_roles` (20:36 UTC) et à `h5_cilium`. Le reste de E4, ce qui était attendu du témoin, n'est pas touché, et le résultat mesuré reste tenu.

## Additif du 07/11/2026, 12:30 UTC : étapes de la porte, prédictions avant passage

Accord du propriétaire : « Les 5 », pour `controle6`, `controle7`, `attseule`, `reglec` et `temoins_scan` sous H1 à H5. Rien n'a été passé avant ces lignes.

**Correction avant passage.** Le tableau soumis au propriétaire disait de `attseule` : « rien poussé dans Zot d'après le code ». C'est faux. `t7_temoin` (`preuves.sh:989`) pousse un témoin par `crane mutate -t` dans `essais-j8/test7`, puis son tag `.att` signé par une clé jetable. Ces écritures sont définitives. `attseule` attend donc une confirmation du propriétaire, et ne passe pas sur le seul « Les 5 ». Ses prédictions sont écrites ci-dessous quand même.

Commandes, depuis la racine du dépôt :

```bash
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- controle6 controle7 reglec </dev/null
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- temoins_scan </dev/null
```

`temoins_scan` passe seule et en dernier : sous `set -e`, son code 1 prédit (voir T2) couperait les étapes suivantes, et `chrono.tsv` n'aurait pas sa ligne « fait ».

Valeurs relevées à 12:28 UTC, en lecture anonyme de Zot :
- referrers de l'image réelle : 0 dans `builds/sample-app`, 4 dans `builds/scan/sample-app`, 1 dans `builds/vsa/sample-app`, 0 dans `builds/scan/essai-webhook` et dans `builds/vsa/essai-webhook` ;
- enveloppes : 24 sur l'image réelle, 36 sur `builds/essai-webhook` ;
- dernière provenance de `builds/essai-webhook` : le 06/11 à 20:14:46 UTC, tâche `publier-essai` seule, sans `construire-image` ;
- tags : 32 dans `essais-j8/test7`, 9 dans `essais-j8/regle-c`.

Références : derniers passages le 06/11, de 14:35 à 15:58 UTC, avant H1. `cm_porte` a déjà réappliqué la ConfigMap `porte` sous `Deny`, dans le test 8 du 06/11 vers 20:20 UTC ([preuves-h5-test8.log](../../08-trust-plane/resultats/preuves-h5-test8.log)). Les Jobs de la porte et `porte-temoin` y ont été admis, comme dans le test 7.

`controle6` :
- C6-1 : ConfigMap `porte` réappliquée et identique aux fichiers versionnés. Clé de VSA `578dd771…`.
- C6-2 : C1 `true||trusted_task.tagged`, contrôle 9 `ok` (24/24 enveloppes couvertes ; nombre de bundles non prédit), contrôle 6 `ok|1/1`.
- C6-3 : C2 en refus, `0/0 VSA` dans `builds/vsa/essai-webhook`. C3 : ec et contrôle 9 inchangés, contrôle 6 en refus, motif de seuil de signatures.
- C6-4 : 0 KO, moins de 5 min (2 min 53 le 06/11). `controle6` ne finit pas par `[ "$ko" = 0 ]` : son code de sortie ne prouve rien, il faut compter les lignes KO.

`controle7` :
- C7-1 : ConfigMap `porte` identique aux fichiers versionnés. Clé du scanner `1656a3fa…`.
- C7-2 : C1 admise, contrôle 7 `ok|4 énoncé(s)`, contrôles 9 et 6 `ok`, Job réussi. C2 : refus par `scan.scan_present`, Job en échec. C3 : refus, motif de seuil de signatures.
- C7-3 : 0 KO, code 0, moins de 5 min (2 min 54 le 06/11). Le CronJob du scan passe à 09:30 UTC : aucun nouvel énoncé pendant l'étape.

`reglec` (écrit dans Zot avec `poc-ecriture` ; configuration de Zot inchangée depuis le 06/11, `5806ba5c…`) :
- R1 : provenance reprise, celle du PipelineRun `474b3f60` (07/11, 10:49 UTC). Trois témoins neufs dans `essais-j8/regle-c`, signés par une clé jetable. Sur l'hôte, signature et attestation sont vérifiées avec la clé jetable et refusées avec celle de Chains.
- R2 : l'image réelle, sans source, est refusée par `slsa_source_correlated.source_code_reference_provided` seule. `porte.construction_kata` figure parmi les succès.
- R3 : `intacte` porte les violations de R2, plus `subject_build_task_matches` et `porte.fermeture_plateforme`, avec `porte.construction_kata` parmi les succès. `sans-kata` et `runc` portent les violations d'`intacte`, plus `porte.construction_kata` seule, avec les mêmes motifs que le 06/11.
- R4 : `en-service` produit la ligne CONSTAT du succès à vide (0 TaskRun de `construire-image` dans la dernière provenance).
- R5 : 0 KO, code 0, moins de 10 min (5 min 39 le 06/11). Image réelle inchangée : 24 enveloppes, dernière provenance `474b3f60`. Six tags de plus dans `essais-j8/regle-c` (15 au total) : `.sig` et `.att` des trois témoins, les trois tags nommés étant déplacés. Confiance moyenne sur ce compte.

`temoins_scan` (témoins de G6 posés le 06/11 à 15:47 UTC, non régénérés : `plateforme.sh g6_temoins` écrit dans Zot et réécrit deux fichiers versionnés, hors de l'accord) :
- T1 : 14 des 15 cas comme `g6-temoins.tsv`. Les fenêtres de `scan.rego` ne changent pas leur sort : `propre` a moins de 7 jours, `vieux` est daté du 29/10, `vex-expire` a expiré le 05/11, `vex-valide` court jusqu'au 06/12, et l'écart de base de `base-vieille` est fixe, de 4 jours.
- T2 : **`futur` admis**, contrôle 7 `ok` avec 1 énoncé. Son scan est daté du 06/11 vers 16:47 UTC, une heure après sa pose : cette date est passée depuis environ 20 h, et le témoin n'est plus dans le futur. Le script attend `refus|scan.scan_recent` : il comptera 1 écart et sortira en code 1. C'est prédit ici, ce n'est pas une régression de la porte. La branche « scan daté du futur » n'est donc pas couverte par ce passage.
- T3 : `g6-reelle` à `true||ok|ok|ok` ; ConfigMap `porte-temoin` posée puis retirée. Moins de 15 min (10 min 27 le 06/11).

`attseule`, si le propriétaire confirme :
- A1 : un témoin neuf dans `essais-j8/test7`, sans tag `.sig`, avec un tag `.att` de plus.
- A2 : refusé ; `builtin.image.signature_check`, `porte.fermeture_plateforme`, `porte.image_signature` et `subject_build_task_matches`, comme le 06/11 ; `builtin.attestation.signature_check` absent.
- A3 : 0 KO, image réelle inchangée.

Hors des étapes :
- X3 : `KyvernoRefusAnormaux` ne se déclenche pas, et le compteur Kyverno ne monte pas. CronJobs à `suspend=false`, 0 PipelineRun en cours, `porte-temoin` absente à la fin.

## Additif du 07/11/2026, 13:37 UTC : test 6 et `intercepteurs`, prédictions avant passage, aucun accord donné

Demande : « Continue », prise pour une préparation à sec. Rien lancé, rien écrit dans le cluster ni dans Zot. Relevés en lecture seule de 13:34 à 13:36 UTC. Chaque étape écrit dans Zot ou dans le cluster : chacune demande son propre accord.

Commandes, depuis la racine du dépôt, une par accord :

```bash
DISTRO=rke2 JOURNAL=preuves-h5 T6_FERMES="Supervisor Etcd" mise run confiance:preuves -- test6 </dev/null
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- intercepteurs </dev/null
```

- `T6_FERMES` est obligatoire. Sans elle, la contre-épreuve attend 9345 et 2379 ouverts (`preuves.sh:795`) et sort en KO dès Supervisor, alors que le pare-feu d'hôte de H4 les ferme toujours. La valeur est celle de `h4_bloque` (`durcissement.sh:349`).
- `JOURNAL=preuves-h5` écrit `preuves-h5-test6.log` et `preuves-h5-intercepteurs.log`, qui n'existent pas encore. Il n'écrase ni `preuves-test6.log` (06/11, 17:48 UTC, cité par H4b), ni `preuves-intercepteurs.log` (02/11).

Relevés :
- `builds` : une seule NetworkPolicy, `construction-sans-sortie` (`tekton.dev/task=construire-image`) ; ni ResourceQuota, ni LimitRange.
- RuntimeClass `kata` : `podFixed` de 250m et 320Mi.
- Sous-réseau des pods de `sc-build` : `10.42.1.0/24`, celui que `adresse_libre` suppose (`preuves.sh:133`). `10.42.1.250` n'est portée par aucun pod à 13:36 UTC.
- TaskRuns `preuve-test6-test` et `preuve-test6-contre` du 06/11 présents, réussis.
- Liaison `tekton-triggers-core-interceptors` : ClusterRole du même nom, sujet `tekton-pipelines:tekton-triggers-core-interceptors`, règle `secrets:get,list,watch`. C'est l'attendu de l'étape.
- Déploiement des intercepteurs : limites 500m et 256Mi posées par `h5_limites`, image de Zot par digest, `RollingUpdate` à 25 %, révisions 1 et 2.

### Effets à connaître

| Étape | Durée prédite | Écrit | Reste après |
|---|---|---|---|
| `test6` | moins de 3 min (88 s le 06/11 à 17:48 UTC) | Zot : bundles poussés dans `tekton/tasks/preuve-test6-contre` et `preuve-test6-test`. Cluster : les deux TaskRuns du 06/11 supprimés puis recréés, deux pods Kata en séquence sur `sc-build`. `tcpdump` sur `enp1s0` de `sc-build` | Deux manifestes de plus dans Zot (`poc-ecriture` ne supprime pas). Deux TaskRuns signés par Chains, sans sujet image, par OpenBao |
| `intercepteurs` | moins de 3 min (1 min 43 le 02/11) | Liaison retirée puis remise (le trap la remet sur KO). Deux `rollout restart` du déploiement | Deux révisions de plus (3 et 4) : `kubectl rollout undo`, retour prévu de `h5_limites`, reviendrait à la révision 3, encore limitée. Le retour de ce déploiement passerait par l'état sauvé, `~/.cache/supply-chain-poc/08/travail/durcissement/h5-avant/Deployment-tekton-pipelines-tekton-triggers-core-interceptors.json`, ou par `--to-revision=1` |

### `test6`

Référence : passage du 06/11 de 17:48 à 17:50 UTC sous H1 à H4, avant H5, S1, `h5_roles`, `h5_cilium`, H6 (posée puis retirée) et le redémarrage des VM.

- N1 : TaskRuns admis sous `Deny`, pods Kata privilégiés compris. Les conteneurs de Tekton reçoivent leurs limites de `config-defaults`, l'étape `construire` a les siennes (1 CPU, 1Gi), l'image BuildKit vient de Zot par digest et le compte est `build`. Confiance haute. Preuves : `preuves-h5-test1.log` (même gabarit, sous runc), R4 (construction réelle sous Kata) et `preuves-h5-sec_h5.log` (pod Kata privilégié admis).
- N2 : deux TaskRuns réussis, `TrustedResourcesVerified=True`. Bundles à digests neufs, différents de `26329a1f…` et `48ce77aa…` : la clé des tâches est ECDSA P-256 (`politique.sh:354`) et l'adresse usurpée est écrite dans le script. Digests non prédits.
- N3 : adresse usurpée tirée de `.250` à `.200` du `10.42.1.0/24`, contrôlée inutilisée par `t6_inutilisee` avant chaque passage. Probablement `10.42.1.250`, valeur non prédite.
- N4 : garde-fous tenus pour les deux passages. Label `tekton.dev/task` attendu, pod sous Kata (noyau de l'invité 6.18.56, différent de celui de `sc-build`), eth0 à l'IP du pod, adresse usurpée ajoutée puis retirée.
- N5 : contre-épreuve comme le 06/11. Zot, Forgejo, API du nœud et API par le service joignables. Supervisor et Etcd refusés par le pare-feu d'hôte. `nc -s` joint Zot. 3 SYN vers `203.0.113.10:443` sur `enp1s0`, source `192.168.161.12`. Aucun flux refusé de l'IP du pod. Zot et Forgejo injoignables depuis l'adresse usurpée, en `INVALID_SOURCE_IP`. Confiance moyenne à haute : Cilium a été redémarré par `h5_cilium` et par celui des VM, mais `kata.sh reseau` a passé ce matin à 11:26 UTC avec Hubble.
- N6 : `construire-image` voit ses 7 destinations refusées, chacune en `POLICY_DENIED EGRESS` chez l'agent de `sc-build` (l'API par le service apparaît sous `192.168.161.11:6443`). `nc -s` est refusé. Zot et Forgejo sont injoignables depuis l'adresse usurpée, en `INVALID_SOURCE_IP`. Aucun paquet sur `enp1s0`. Le nombre de flux par tentative n'est pas prédit (6 le 06/11).
- N7 : 0 KO. Image réelle inchangée : nombre d'enveloppes relu par l'étape au début et à la fin (24 à 12:45 UTC, non relu depuis). `KyvernoRefusAnormaux`, `ChainsEchecSignature` et `ChainsMarqueSansSignature` restent inactives.

### `intercepteurs`

Référence : passage du 02/11 de 11:14:50 à 11:16:33 UTC, sous k3s, avant H1 à H5. Les prédictions de l'étape, écrites le 02/11 d'après le code de Triggers v0.37.2, restent valables.

- I1 : liaison et ClusterRole conformes à l'attendu, relevés à 13:36 UTC.
- I2 : liaison retirée, `can-i list secrets -A` à `no`. Le nouveau pod n'est pas prêt après 90 s, et son journal porte le refus de lister les Secrets « at the cluster scope ».
- I3 : les deux nouveaux pods sont admis sous `Deny`. Le gabarit porte les limites de `h5_limites`, une image de Zot par digest et le compte `tekton-triggers-core-interceptors`, pas `default`. Ce sera la première admission d'un pod de ce déploiement sous `Deny` : le pod en service, `…-558f59555b-c9qnn`, a été créé le 06/11 à 19:19:59 UTC par `h5_limites`, sous Audit (`Deny` à 19:26 UTC). Le redémarrage des VM n'a fait que relancer son conteneur (`restartCount` 1), sans nouvelle admission. Confiance moyenne à haute.
- I4 : pendant la fenêtre, l'ancien pod reste en service (`RollingUpdate`, nouveau pod jamais prêt), comme le 02/11 (« 1 old replicas are pending termination »). Les livraisons ne seraient pas perdues. Aucune livraison n'est prévue pendant le passage, ce point n'est donc pas mesuré.
- I5 : liaison remise, `can-i` à `yes`, nouveau pod prêt, 0 refus dans son journal. `caBundle` des cinq ClusterInterceptors inchangé (longueur 1456 le 02/11 sous k3s ; la valeur sous RKE2 n'est pas prédite).
- I6 : 0 KO. Conclusion inchangée : borner les intercepteurs par les droits demande de modifier Triggers. La limite est gardée.

Ce que ces deux étapes ne couvrent pas : le démarrage d'un nouveau pod des résolveurs, la jonction d'un nœud, le saut d'un passage manqué du scan, la branche « scan daté du futur ». L'étape `test5` reste arrêtée par `gabarit_essai` tant que le gabarit d'essai n'est pas en service ; ses refus sont couverts par `test5_refus`.

## Additif du 07/11/2026, 14:29 UTC : `test5` complète, relecture à sec, rien lancé

Demande : « Continue », prise pour une préparation à sec. Rien écrit dans le cluster ni dans Zot, `preuves.sh` inchangé. Relevé en lecture seule de 14:28:33 UTC : [test5-complete-releve.log](test5-complete-releve.log).

**Pas de prédiction pour `etape_test5` telle quelle.** Elle appelle `gabarit_essai` sans condition (`preuves.sh:342`), et le gabarit en service est `sample-app` : KO immédiat, déjà constaté (C7). La garde est justifiée : le commit du témoin est inventé par le script et n'existe pas dans Forgejo, donc la pipeline `sample-app` échouerait à `preparer` et laisserait un PipelineRun `Failed` dans `builds`. La lancer demande l'une de ces voies, chacune sur accord :
- modifier le script ;
- remettre le gabarit d'essai (`politique.sh declencheurs`, `commun.sh:103`), puis revenir au gabarit `sample-app` ; mécanisme du retour non relu ;
- créer un vrai commit dans Forgejo pour le témoin, ce qui déplace la tête de main, constante dans les scripts (`TETE_J2`).

**Couverture des assertions de `test5` sous H1 à H5**, tous ces passages étant postérieurs à S1 (18:39 UTC le 06/11) et à `h5_deny` (19:26 UTC) :

| Assertion de `test5` | Mesure sous H1 à H5 | Journal |
|---|---|---|
| HTTP 202 à chaque livraison | 4 livraisons, 4 réponses 202 | `preuves-h5-test5_refus.log` (07/11, 10:40 UTC) |
| 3 refus de l'intercepteur github, motifs et compte exacts | 1 « no X-Hub-Signature-256 header set », 2 « payload signature check failed », 3 au total | idem |
| Aucun PipelineRun pour les livraisons refusées | 0 pour `1111…`, 0 pour le commit jamais livré | idem |
| Création par une livraison valide, construite et signée | Livraison de Forgejo : une création par `el-forgejo`, `Succeeded`, signée par Chains, porte `true` | `preuves-h5-r4-construction_durcie.log` (06/11, 20:56 UTC) |
| Nouvelle livraison de Forgejo pour la tête : `already exists` | Rejeu par Forgejo refusé à la création | idem |
| Livraison valide pour un PipelineRun existant : acceptée par les intercepteurs, `already exists` avec son `eventID` | Livraison signée par le script, même `eventID` dans le journal de l'EventListener, UID inchangé | `preuves-h5-test5_refus.log` |
| Un seul PipelineRun par commit | Idem, plus le chemin 2 | `preuves-h5-test5_refus.log`, `preuves-h5-rattrapage_durci.log` |

Non mesuré sous H1 à H5, à la lettre :
- **Rejeu à l'identique** d'un corps signé déjà accepté une fois. Mesuré le 06/11 à 14:32 UTC, avant H5 (`preuves-test5.log` de la 08) : rejeu accepté par les intercepteurs, refusé à la création (`already exists`). L'anti-rejeu vient du nom du PipelineRun (J4), comme pour la livraison valide de `test5_refus`. Écart attendu nul sous H5, non mesuré.
- **Absence de la ligne de niveau debug** « interceptor stopped trigger processing » dans le journal de l'EventListener : `test5` la contrôle, `test5_refus` non.

**Constat du relevé : aucune livraison traitée depuis le redémarrage.** Le conteneur de l'EventListener a redémarré à 11:23:32 UTC, et son journal ne porte aucun `eventID` depuis. Le pod des intercepteurs `…-6894848d5c-xh998`, créé à 14:06:23 UTC par l'étape `intercepteurs`, n'a journalisé que son démarrage. L'appel de l'EventListener vers ce pod n'a donc jamais été mesuré : `caBundle` inchangé (I5), mais aucune livraison.

**Issues soumises au propriétaire, aucune décidée :**
- **(a)** Retirer « `test5` complète » des non couverts, en renvoyant au tableau ci-dessus. Les deux points à la lettre restent nommés.
- **(b)** Étendre `test5_refus` : envoyer deux fois le corps du témoin, et contrôler l'absence de la ligne de niveau debug. Mêmes effets que `test5_refus` : rien dans le cluster ni dans Zot, un secret jetable effacé par le trap ; 5 livraisons et 2 erreurs `already exists` dans les journaux. Couvre aussi la première livraison par l'EventListener redémarré et le nouveau pod des intercepteurs. Script modifié et prédictions committées avant le passage, puis accord de passage.
- **(c)** Rejouer `test5_refus` sans changement : même couverture du redémarrage, sans le rejeu à l'identique ni la ligne de niveau debug.

## Additif du 07/11/2026, 14:43 UTC : extension de `test5_refus`, issue (b), prédictions avant passage, aucun accord de passage donné

Choix du propriétaire : « B ». `preuves.sh` modifié, rien lancé, rien écrit dans le cluster ni dans Zot.

**Changement de l'étape.** Après le témoin, le même corps est renvoyé avec la même signature, sous un nouvel en-tête `X-GitHub-Delivery`, comme le rejeu de `test5` le 06/11. Puis l'étape contrôle le journal de l'EventListener. Ajouts :
- l'`eventID` du rejeu, distinct de celui du témoin, porte l'erreur `already exists` ;
- 2 erreurs `already exists` au total depuis le début de l'étape (KO sinon) ;
- la ligne de niveau debug « interceptor stopped trigger processing » est comptée. En cas d'écart, l'étape écrit un `CONSTAT` sans sortir en KO, comme `test5`.

Commande, depuis la racine du dépôt :

```bash
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- test5_refus </dev/null
```

**Effets.** Mêmes effets que `test5_refus` : rien dans le cluster ni dans Zot, un secret jetable en local, effacé par le trap. Restent après le passage : 5 livraisons, 3 refus dans le journal des intercepteurs, 2 erreurs `already exists` dans celui de l'EventListener. Durée prédite : moins de 1 min (2 s le 07/11 à 10:40 UTC). Le journal `preuves-h5-test5_refus.log` sera écrasé : celui de 10:40 UTC est copié dans ce commit en `preuves-h5-test5_refus-premier-passage.log` de la 08.

**Prédictions.** Relevé de référence : [test5-complete-releve.log](test5-complete-releve.log) (14:28:33 UTC). Niveau de journal de l'EventListener lu avant 14:43 UTC, en lecture seule : `info`, dans `K_LOGGING_CONFIG` du déploiement `el-forgejo` et dans `config-logging-triggers` (`loglevel.eventlistener=info`).

T1 à T6 restent valables, avec deux précisions :
- T1 : le PipelineRun de la tête est `sample-app-6391fd43…`, UID `474b3f60…`, recréé par le rattrapage à 10:48 UTC.
- T6 : image réelle inchangée, 24 enveloppes (relevé du test 6 à 14:03 UTC, `preuves-h5-test6.log`).

Prédictions ajoutées :
- T7 : le rejeu à l'identique reçoit HTTP 202 et passe les intercepteurs. Il est refusé à la création (`already exists`), sous un `eventID` distinct de celui du témoin. 2 erreurs `already exists` au total. Confiance haute : même chemin qu'au témoin, et rejeu mesuré le 06/11 avant H5.
- T8 : 0 ligne « interceptor stopped trigger processing ». Confiance haute, d'après le niveau de journal relevé.
- T9 : première livraison traitée par l'EventListener redémarré à 11:23:32 UTC et par le pod des intercepteurs `…-6894848d5c-xh998` (créé à 14:06:23 UTC, seule réplique). Les 3 refus de T3 apparaissent dans le journal de ce pod, et le témoin comme le rejeu atteignent la création. Confiance moyenne à haute : `caBundle` inchangé (I5), mais l'appel de l'EventListener vers ce pod n'a jamais été mesuré.

Sur KO : aucun état à défaire. Un KO de T9 (refus absents, ou erreur TLS au journal de l'EventListener) viserait le lien entre l'EventListener et les intercepteurs depuis l'étape `intercepteurs`, et demanderait une décision avant toute autre livraison.

## Additif du 07/11/2026, 15:20 UTC : `test5` complète par l'étape `test5_essai`, effets et prédictions avant passage, aucun accord de passage donné

Demande du propriétaire : « Ben fais le tourner, non ? », prise pour une préparation. Le passage remplace le gabarit en service et écrit dans Zot : il attend un accord qui cite ces effets. Nouvelle étape `test5_essai` dans `preuves.sh`, jamais lancée.

**Voie retenue : gabarit d'essai remis le temps du passage, TriggerTemplate seule.** `politique.sh declencheurs` n'est pas utilisé : il recrée aussi des PipelineRuns de J6 et réapplique l'EventListener. Un vrai commit dans Forgejo déplacerait la tête de main. L'étape :
1. vérifie que le gabarit en service est identique au rendu de `gabarit-sample-app.yaml` avec `pipeline.ref` ;
2. suspend le rattrapage, puis pose le trap : gabarit de la bascule remis et rattrapage repris, même sur KO ;
3. applique la seule TriggerTemplate de `declencheurs.yaml`, rendue avec `PIPE_ESSAI`, et attend 10 s le cache de l'EventListener ;
4. lance `etape_test5` sans changement ;
5. remet le gabarit de la bascule et reprend le rattrapage. Elle contrôle que la spec est identique à l'objet sauvé (KO sinon), qu'un seul PipelineRun a été créé pendant la fenêtre, que l'UID de la tête est inchangé et que l'image réelle n'a pas bougé.

Commande, depuis la racine du dépôt :

```bash
DISTRO=rke2 PIPE_ESSAI=sc-stockage.poc.test:5000/tekton/pipelines/sample-app-essai@sha256:c51948595fc675ca5c1fae6a814faadca2d06663b49aba7cc202dcb30c8aca58 JOURNAL=preuves-h5 mise run confiance:preuves -- test5_essai </dev/null
```

`PIPE_ESSAI` est lu sur `j6-porte-en-service`.

**Vérifié à sec, rien créé** (dry-run serveur et lecture seule), journal [test5-essai-sec.log](test5-essai-sec.log), de 15:21:47 à 15:21:48 UTC :
- TriggerTemplate en service : un seul gestionnaire de champs, `kubectl` (`Apply`, 06/11 à 15:15:01 UTC). La spec fusionnée par `apply --server-side` du gabarit d'essai est identique au fichier : ni `workspaces` ni `taskRunSpecs` ne restent ;
- TriggerTemplate d'essai admise, et PipelineRun rendu depuis la spec fusionnée admis au nom de `el-forgejo`, comme celui du gabarit en service ;
- `gabarit-sample-app.yaml` rendu avec `pipeline.ref` (`sample-app@sha256:02c05736…`) : spec identique au gabarit en service ;
- aucune fonction appelée par `etape_test5` ne pose de trap ;
- état : 36 enveloppes sur `builds/essai-webhook@3a7ca1b1…`, 24 sur l'image réelle ; 11 PipelineRuns de la pipeline d'essai dans `builds`, le plus récent `preuve-enveloppes` (07/11, 11:34 UTC).

**Effets à connaître.**

| Quoi | Effet | Reste après |
|---|---|---|
| Gabarit en service | Pipeline d'essai pendant 40 s à 1 min 30 environ. Un vrai push sur `main` pendant cette fenêtre construirait avec la pipeline d'essai, et son commit serait ensuite écarté (`already exists`) | Gabarit de la bascule, même spec ; `managedFields` et `resourceVersion` changés |
| Rattrapage | Suspendu pendant la fenêtre | Repris |
| `builds` | PipelineRun `sample-app-<commit inventé>`, son TaskRun `publier` et son pod (runc, pas de tâche `construire`) | Laissés, comme le témoin du 06/11 (`sample-app-45a76111…`) |
| Zot | `publier-essai` réécrit le manifeste de `builds/essai-webhook` (même digest). Chains ajoute ses enveloppes au tag `.att` | Enveloppes définitives. La provenance de PipelineRun la plus récente de `essai-webhook` devient celle du témoin, à la place de `preuve-test7-hors-liste`. Bundles d'horodatage sur ce dépôt : non relu |
| Journaux | 5 livraisons, une nouvelle livraison de Forgejo, 3 refus des intercepteurs, 2 `already exists` | Nouveau journal `preuves-h5-test5_essai.log` ; `chrono.tsv` |

Sur KO, le trap remet le gabarit et reprend le rattrapage. Un PipelineRun `Failed` peut rester dans `builds`, à purger sur accord.

**Prédictions.**
- U1 : gabarit en service identique au rendu de `gabarit-sample-app.yaml` ; gabarit d'essai appliqué, admis. Confiance haute (vérifié à sec).
- U2 : les prédictions de `test5` (30/10/2026) sont tenues, 0 KO. 3 refus de l'intercepteur github. Le témoin est créé par l'EventListener sur la pipeline d'essai, réussit, et son TaskRun et son PipelineRun sont signés par Chains. Le rejeu à l'identique et la nouvelle livraison de Forgejo sont écartés (`already exists`). Un seul PipelineRun par commit, aucune ligne de niveau debug. Confiance moyenne à haute. Risque principal : le cache de l'EventListener rendrait encore le témoin avec la pipeline `sample-app` après 10 s. Le témoin échouerait alors à `preparer`, `non_repris` sortirait en KO et un PipelineRun `Failed` resterait. Durée de propagation non mesurée.
- U3 : un seul PipelineRun créé pendant la fenêtre, `sample-app-essai`, `Succeeded`.
- U4 : gabarit de la bascule remis, spec identique à l'objet sauvé ; rattrapage repris ; UID de la tête inchangé (`474b3f60`).
- U5 : image réelle inchangée, 24 enveloppes, provenance `474b3f60`.
- U6 : `builds/essai-webhook` passe de 36 à 38 enveloppes (TaskRun `publier` et PipelineRun du témoin). Confiance moyenne : ce décompte n'a jamais été relevé pour ce chemin. Affiché, pas contrôlé.
- U7 : hors étape, 0 événement `PolicyViolation`, 0 alerte active, 0 ligne `tls`, `x509` ou `certificate` au journal de l'EventListener.

Durée prédite : moins de 1 min 30 (test5 entre 18 et 20 s du 30/10 au 03/11, plus 10 s d'attente et la suspension du rattrapage).

## Additif du 07/11/2026, 15:38 UTC : les quatre non couverts restants, relecture à sec, rien lancé

Demande : « Continue », après le push de 71d3b11. Aucun accord de mesure n'est donné. Le relevé est fait en lecture seule de 15:38:49 à 15:38:50 UTC ([non-couverts-releve.log](non-couverts-releve.log)). Rien n'est écrit dans le cluster, dans Zot ni sur les VM, et `preuves.sh` n'est pas modifié. Chaque point demande son propre accord, avec des effets différents.

**1. Démarrage d'un nouveau pod des résolveurs.** Une grande partie est déjà exercée sous H1 à H5 (complément de 15:40:59 UTC au relevé). Au redémarrage des VM, kubelet a recréé le bac à sable du pod `…-xsv5n` à 11:23:32 UTC (tentative 1 ; celui du 06/11 est `NOTREADY`), et son CiliumEndpoint date de la même seconde (identité 11808, IP `10.42.0.81` conservée). Le démarrage réel, le montage de `ca-poc` sous `readOnlyRootFilesystem`, le contexte `restricted` et l'endpoint Cilium sont donc passés sous H1 à H5. Restent propres à un nouveau pod : l'admission réelle d'un nouvel objet Pod (A4 ne l'a vue qu'en dry-run), l'ordonnancement et la passation des baux d'élection. L'identité Cilium vient des labels : un nouveau pod aurait la même, seuls l'endpoint et l'IP changeraient.
- Déploiement `tekton-pipelines-remote-resolvers` : révision 1, une réplique, `nodeSelector` `zone: confiance`, donc seul `sc-confiance` convient. Limites 1 CPU et 4 Gi. Aucune sonde de disponibilité ni de vie.
- Image en `IfNotPresent`, en cache sur `sc-confiance` seulement. Un nouveau pod ne tirera pas l'image : le tirage depuis Zot sous H1 à H5 reste hors de cette mesure. Le précédent des intercepteurs est dans le même cas.
- Pod actuel `…-xsv5n`, créé le 06/11 à 13:38:02 UTC, conteneur relancé au redémarrage des VM (11:23:33 UTC). Il n'est jamais repassé par l'admission sous H1 à H5.
- Cinq baux d'élection, tous tenus par `…-xsv5n`, durée 60 s. Si l'ancien pod ne les rend pas en s'arrêtant, le nouveau attend jusqu'à 60 s avant de résoudre. Non vérifié.
- Précédent : le pod des intercepteurs `…-xh998`, créé à 14:06:23 UTC par l'étape `intercepteurs` (I3), prêt à 14:06:35 UTC, sur `sc-confiance`, image en cache. C'est un autre déploiement : il ne couvre pas les résolveurs. Ses 12 s jusqu'à Ready ne valent pas non plus pour eux : sans sonde, leur Ready sera quasi immédiat. Le délai qui compte est la passation des baux, à mesurer.
- Voie possible : `kubectl delete pod` plutôt que `rollout restart`. Le ReplicaSet recrée le pod sur le même gabarit, et le déploiement reste à sa révision 1. Avec `rollout restart`, l'historique change, comme pour les intercepteurs.
- Témoin après redémarrage : l'étape `resolveurs` (L1 à L8, 10:29 UTC). Elle résout le bundle en service dans `builds` et attend deux refus dans `preuve-resolveurs`. L8 lit l'heure de création du pod et changera donc de valeur.
- Effet : pendant la fenêtre, une résolution attendrait le nouveau chef. Le rattrapage s'arrête à `PRESENT` tant que la tête de main est construite. Le suspendre, sur le modèle de `test5_essai`, ne protège que contre un push pendant la fenêtre.

**2. Branche « scan daté du futur » de `scan.rego`.**
- La tolérance d'horloge est de 5 min (`_derive`, ligne 15). Le témoin `futur` est daté une heure après sa pose. Il reste donc dans le futur pendant 55 min, puis la branche n'est plus couverte.
- `g6_temoins` lance `preuves.sh temoins_scan` aussitôt après les témoins (`plateforme.sh:1259`). Le contrôle suit donc dans la fenêtre, sous le même accord.
- `temoins()` crée une nouvelle paire de clés à chaque passage (`plateforme.sh:1150`), puis la clé privée est effacée par le trap. On ne peut pas reposer `futur` seul : `g6-temoin-cle-publique.pem` et `g6-temoins.tsv` sont réécrits, et `essais-h5-figees.sh:105` lit ces digests.
- Écritures dans Zot : 14 images témoins et 16 publications de scan, illisible compris (boucle `temoins`, `plateforme.sh:1167` à 1181).
- Écritures dans le cluster : ConfigMap `porte-temoin` posée puis retirée, un Job de la porte par cas dans `porte` (`juger`, `politique.sh:1299`), plus celui de l'image réelle. `g6_temoins` entier a duré 11 min 36 le 04/11 : il tient dans la fenêtre de 55 min.
- Fichiers réécrits et cités ailleurs, à copier avant le passage : `preuves-temoins_scan.log` (`g6_temoins` lance `preuves.sh` sans `JOURNAL`, sauf s'il est exporté ; cité par `g6-predictions.md` et le README de la 08c), `g6_temoins.log` et `g6_temoins.copie.log` (cités par `g6-predictions.md`), `g6-temoins.tsv` et `g6-temoin-cle-publique.pem` (cités par `g6-predictions.md`, le README de la 08c et ce fichier). `preuves-h5-temoins_scan.log` n'est pas touché.
- Question de cadrage, laissée au propriétaire : la logique est couverte par `test_scan_du_futur` et `test_ecart_horloge_tolere` (`scan_test.rego`). La porte sous H1 à H5 est couverte par `temoins_scan` sur les autres cas. Faut-il quand même le rejeu, avec écriture dans Zot ?
- Une date très lointaine, un an par exemple, rendrait le témoin durable. Ce serait une modification de `plateforme.sh`, non faite.

**3. Saut d'un passage manqué du scan.**
- `scan-sample-app` : `30 9 * * *`, `startingDeadlineSeconds` 3600. Dernier passage le 07/11 à 09:30, réussi à 09:31:52 UTC. Rien n'est mesurable avant le 08/11 à 09:30 UTC. Échéance : l'accord et la suspension doivent précéder le 08/11 à 09:30 UTC, sinon le point glisse d'un jour.
- Mesure possible : suspendre avant 09:30 UTC, reprendre après 10:30 UTC.
- Comportement attendu du contrôleur, lu dans `pkg/controller/cronjob/cronjob_controllerv2.go` (branche `release-1.35`) : si l'heure prévue plus `startingDeadlineSeconds` est passée, il ne crée pas de job. Il émet un événement `Warning` `MissSchedule` (« Missed scheduled time to start a job: … »). Un événement ne vit qu'une heure par défaut (`--event-ttl`, non relevé sur ce cluster) : il faut le relever aussitôt.
- Reprendre entre 09:30 et 10:30 UTC montrerait au contraire le lancement en retard.
- Effet à annoncer : `ScanEnRetard` (avertissement, 26 h, `for: 5m`) se déclencherait vers 11:37 UTC le 08/11. Le dernier referrer lu dans Prometheus date de 09:31:48 UTC (complément de 15:40:59 UTC) : seuil franchi à 11:31:48 UTC, plus 5 min. C'est à la fois un effet et une mesure de plus.
- Il n'y a pas de variante le jour même avec `rattrapage` : il tourne chaque minute, et le passage manqué le plus récent a toujours moins de 60 s, sous ses 120 s. Le contrôleur le lance donc à la reprise, comme constaté à 15:25:22 UTC. Ce mécanisme relève du contrôleur des CronJobs, pas de H1 à H5.

**4. Jonction d'un nœud.** Elle demande une nouvelle VM ou une réinstallation de l'agent RKE2 : c'est une action système, soumise à accord préalable. Rien n'est préparé.

## Additif du 07/11/2026, 15:49 UTC : nouveau pod des résolveurs, étape `resolveurs_pod`, effets et prédictions avant passage, aucun accord de passage donné

Choix du propriétaire : « Résolveurs ». L'étape est écrite après ces lignes et n'a jamais été lancée.

**Vérifié à sec avant d'écrire**, en lecture seule, de 15:40 à 15:49 UTC. Les expressions de l'étape ont été rejouées sur l'état actuel de 15:52:15 à 15:52:36 UTC ([resolveurs-pod-sec.log](resolveurs-pod-sec.log)) :
- Un pod bâti sur le gabarit du ReplicaSet `…-56c4c4d957` est admis en dry-run serveur, au nom de l'administrateur comme de `system:serviceaccount:kube-system:replicaset-controller`. Limites 1 CPU et 4 Gi. 0 événement `PolicyViolation` dans le cluster.
- `terminationGracePeriodSeconds` vaut 30, et il n'y a aucune sonde.
- L'audit de l'API journalise la création des pods par le contrôleur des ReplicaSets. Celle de `…-xh998` y figure à 14:06:23 UTC, en 201. L'assertion sur l'audit est donc tenable. Le filtre de l'étape, rejoué sur cette création, rend `replicaset-controller 201`. L'audit enregistre aussi les dry-runs, au nom de `system:admin` emprunté : deux aujourd'hui dans `tekton-pipelines-resolvers`, ceux de cette vérification. Le filtre les exclut (`dryRun` dans `requestURI`), ajout fait à 15:52 UTC, avant tout passage.
- Depuis le redémarrage de 11:23 UTC : 0 ligne `is forbidden` au journal des résolveurs. Dans l'audit, 0 lecture de Secret ou de compte de service hors de `builds`, refus de `preuve-resolveurs` exceptés. Le démarrage d'un conteneur ne fait donc pas échouer les contrôles de l'étape `resolveurs`.
- Baux : `config-leader-election-resolvers` est vide. Les valeurs par défaut de knative.dev/pkg (`39ebae2ee2dc`, déclaré par le `go.mod` de tektoncd/pipeline v1.15.5) sont donc en vigueur : durée 60 s, renouvellement 40 s, nouvel essai toutes les 10 s.
  - `ReleaseOnCancel: true` (`leaderelection/context.go`).
  - `cmd/resolvers/main.go` part de `signals.NewContext()`, que SIGTERM annule.
  - Un `delete pod` doit donc rendre les cinq baux. Ce n'est pas encore mesuré ici.
- Précédent, l'autre branche : au redémarrage des VM, l'ancien processus est mort sans rendre ses baux. Le conteneur a démarré à 11:23:33 UTC et a pris les baux de 11:24:35 à 11:24:51 UTC, soit 62 à 78 s plus tard (`leaseTransitions` à 1).

**Commande** (sur accord, pas avant) :

```
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- resolveurs_pod </dev/null
```

**Déroulé.**
1. Relevé de l'état avant, puis dry-run.
2. Rattrapage suspendu, avec un trap qui le reprend même sur KO.
3. `kubectl delete pod --wait=true` sur l'ancien pod. Le ReplicaSet le recrée sur le même gabarit.
4. Attente du nouveau pod prêt, puis des cinq baux.
5. Rattrapage repris, puis contrôles.
6. Témoin : l'étape `resolveurs`, appelée dans l'étape. Son trap remplace celui de l'étape, d'où la reprise du rattrapage avant l'appel. Le journal `preuves-h5-resolveurs.log` de 10:29 UTC n'est pas réécrit.

Sur KO avant que le pod soit prêt, l'étape écrit dans son journal les événements de l'espace, dont les `FailedCreate` qui portent le motif d'un refus, et la fin du `describe` des pods, puis sort. Le trap reprend le rattrapage. Après un simple retard, aucun retour n'est nécessaire : le ReplicaSet réessaie seul.

**Pire cas.** La création réelle est refusée de façon durable, par Kyverno en `Deny` ou par une VAP, ou le conteneur ne démarre pas. Il n'y a alors plus de résolveur : aucun PipelineRun neuf ne se résout jusqu'à une intervention, et l'étape sort en KO au bout de 90 s en laissant ce trou. Probabilité faible : le dry-run au nom de `replicaset-controller` passe, et le conteneur a démarré sous H1 à H5 à 11:23 UTC. Retour existant au README de la 08c : `h2_kyverno` pour repasser Kyverno en Audit, à décider avec le propriétaire selon le motif.

**Effets.**
- Le pod `…-xsv5n` est supprimé. Pendant la passation, une résolution attendrait le nouveau chef.
- Le rattrapage est suspendu pendant la fenêtre. Un passage est lancé à la reprise et s'arrête à `PRESENT`.
- La révision 1 du déploiement ne change pas.
- L'étape `resolveurs` crée puis supprime l'espace `preuve-resolveurs` et deux ResolutionRequests dans `builds`.
- Nouveau journal `preuves-h5-resolveurs_pod.log`, ligne dans `chrono.tsv`.

**Ajouts au script après ces prédictions, avant tout passage** (07/11/2026, 15:52 et 15:55 UTC) : exclusion des requêtes `dryRun` dans le filtre d'audit, et une ligne affichée, non contrôlée, qui donne le trou réel de la passation : dernière prise de bail moins l'heure de la suppression demandée.

**Contrôles hors étape, à lancer juste après le passage** dans `resolveurs-pod-hors-etape.log`. Ils sont relevés une première fois avant, à titre de référence ([resolveurs-pod-avant.log](resolveurs-pod-avant.log)) :
- premier passage du rattrapage après la reprise, arrêté à `PRESENT` ;
- image réelle : nombre d'enveloppes (24 attendues), provenance `474b3f60` inchangée ;
- alertes actives dans Alertmanager (0 attendue) ;
- `crictl pods` sur `sc-confiance` : bacs à sable des résolveurs, celui de 11:23 UTC disparu, un seul neuf prêt ;
- CiliumEndpoint du nouveau pod : identité et IP ;
- événements `PolicyViolation` depuis le passage.

**Prédictions.**
- V1, avant : un seul pod, `…-xsv5n`. Révision 1. Cinq baux tenus par lui, `leaseTransitions` à 1. Admis en dry-run au nom du contrôleur des ReplicaSets. Confiance haute (vérifié à sec).
- V2, admission : un seul nouveau pod, du même ReplicaSet, sur `sc-confiance`. Sa création par `replicaset-controller` est à l'audit en 201. 0 refus, 0 `PolicyViolation` depuis la suppression. Confiance haute.
- V3, démarrage : nouveau pod prêt moins de 30 s après sa création, 0 redémarrage. Nouveau CiliumEndpoint, même identité 11808. L'IP est affichée, pas contrôlée. Confiance haute pour le délai et l'identité.
- V4, baux : les cinq passent au nouveau pod, `leaseTransitions` de 1 à 2. Ils sont pris au plus 25 s après le démarrage de son conteneur (un nouvel essai de 10 s, gigue de client-go comprise). Confiance moyenne : la remise à l'arrêt est lue dans le code, jamais mesurée ici. Si les baux n'étaient pas rendus, le délai serait de 60 à 82 s, comme à 11:23. L'étape l'écrirait en CONSTAT, sans KO.
- V5, journal du nouveau pod : cinq « Successfully acquired lease », 0 `is forbidden` avant le témoin.
- V6, témoin : l'étape `resolveurs` passe comme à 10:29 UTC, 0 KO. Les lectures hors de `builds` restent à 0 à l'audit.
- V7, hors étape : 0 PipelineRun créé pendant la fenêtre. Rattrapage `PRESENT` à la reprise. Image réelle inchangée, 24 enveloppes, `474b3f60`. 0 alerte.

Durée prédite : moins de 2 min, dont environ 11 s pour l'étape `resolveurs`.

## Additif du 07/11/2026, 16:15 UTC : saut d'un passage du scan, étapes `scan_saut_suspendre` et `scan_saut_reprendre`, effets et prédictions avant passage, aucun accord de passage donné

Demande : « continue ». Les deux étapes sont écrites après ces lignes et n'ont jamais été lancées. Rien n'a été modifié dans le cluster : seulement des lectures et deux dry-runs serveur de la suspension.

**Correction du point 3 de l'additif de 15:38 UTC.** Ce point annonçait, à la reprise, un événement `Warning` `MissSchedule`. C'est faux pour ce CronJob. Le source lu cette fois est celui de la version du cluster : `v1.35.9`, empreintes dans [scan-saut-sec.log](scan-saut-sec.log).
- `mostRecentScheduleTime` (`utils.go`, lignes 106 à 113) remonte le point de départ à « maintenant moins `startingDeadlineSeconds` » quand une échéance est posée.
- Le passage retenu est donc toujours postérieur à cette borne. La condition `tooLate` (`cronjob_controllerv2.go`, lignes 546 à 552) ne peut pas être vraie, et `MissSchedule` n'est jamais émis avec une échéance.
- Repris à 11:38 UTC, le contrôleur cherche les passages après 10:38 UTC. Il n'en trouve aucun avant le 09/11 à 09:30 UTC. Il ne crée ni Job ni événement, et `lastScheduleTime` reste au 07/11 à 09:30 UTC.
- Suspendu, il rend la main avant tout calcul (lignes 514 à 517).
- La preuve du saut n'est donc pas un événement. Elle tient en trois relevés : aucun Job, aucune création de Job à l'audit, et `lastScheduleTime` inchangé.

**Vérifié à sec** de 16:06 à 16:15 UTC ([scan-saut-sec.log](scan-saut-sec.log), complété par la vérification des expressions des étapes) :
- CronJob `scan-sample-app` :
  - planning `30 9 * * *`, `timeZone` `Etc/UTC`, échéance 3600 s, `Forbid`, `activeDeadlineSeconds` 1800 ;
  - non suspendu, aucun passage actif ;
  - dernier passage le 07/11 à 09:30 UTC.
- La suspension est admise en dry-run serveur, avec 0 `PolicyViolation`.
- La porte exige un scan de 7 jours au plus (`scan_age_max_jours: 7` dans la ConfigMap `porte/porte`, en service). La base de Grype vient d'un timer systemd séparé (`base-grype.timer`, 08:00 UTC) : `BaseGrypeVieillie` n'est pas touchée.
- Alertmanager a un seul récepteur, le webhook local `127.0.0.1:9095` (`recepteur-alertes`, journal de l'unité). Aucune notification ne sort de `sc-stockage`.
- L'audit de l'API garde les patchs des CronJobs et les créations de Jobs. Son historique ne remonte qu'à environ 16 h 25 : dix fichiers de 100 Mo, le plus ancien commençait le 06/11 à 23:49:54 UTC. La ligne de la suspension aura donc tourné avant la reprise : le journal de `scan_saut_suspendre` en garde la copie. La reprise vérifie que l'audit couvre encore le passage sauté.
- Seuls le CronJob et des Jobs lancés à la main écrivent des referrers dans `builds/scan/sample-app`. Aucune pipeline n'y écrit.
- Dernier referrer : 07/11 à 09:31:48 UTC. `ScanEnRetard` (évaluée toutes les 30 s) passe en pending le 08/11 à 11:31:48 UTC et en firing vers 11:36:48 UTC.

**Commandes** (sur accord, pas avant ; deux accords distincts) :

```
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- scan_saut_suspendre </dev/null
DISTRO=rke2 JOURNAL=preuves-h5 mise run confiance:preuves -- scan_saut_reprendre </dev/null
```

**Calendrier.**
- `scan_saut_suspendre` : à tout moment avant le 08/11 à 09:25 UTC. Elle refuse entre 09:25 et 10:31 UTC, quand le passage du jour tourne ou peut encore être lancé. Ce soir convient aussi bien que demain matin : le CronJob ne tourne qu'à 09:30.
- `scan_saut_reprendre` : le 08/11 entre 11:38 UTC (après le firing attendu) et vers 01:00 UTC le 09/11, marge comprise. Au-delà, l'audit (environ 16 h 25 d'historique, selon son volume) ne couvre plus le passage sauté de 09:30 UTC, et l'étape sort en KO. Elle refuse sans rien toucher avant 10:31 UTC, car le passage serait alors lancé en retard. Entre 10:31 et 11:38 UTC, elle reprend sans juger l'alerte.
- Passé cette garde, tout KO de `scan_saut_reprendre` reprend le CronJob par un trap : un contrôle raté ne laisse pas sauter le passage du 09/11.

**Effets.**
- Aucun scan le 08/11 : un referrer de moins dans `builds/scan/sample-app`. La tâche planifiée du 21/11 compte les referrers sans en prédire le nombre, et les scans quotidiens suivants restent.
- `ScanEnRetard` (avertissement) passe en firing le 08/11 vers 11:37 UTC. Elle est notifiée au récepteur local et visible dans Grafana. Elle reste active jusqu'au referrer suivant, le 09/11 vers 09:32 UTC. Un Job manuel (`kubectl create job --from=cronjob/scan-sample-app`) l'éteindrait plus tôt : il demande un accord séparé et n'est pas compris ici.
- Deux patchs du CronJob, à l'audit au nom de `system:admin`. Deux journaux (`preuves-h5-scan_saut_suspendre.log`, `preuves-h5-scan_saut_reprendre.log`) et quatre lignes dans `chrono.tsv`.
- Rien d'autre n'est touché : rattrapage, horodatage, porte et Zot.

**Pire cas : la reprise n'a pas lieu.** Plus aucun scan ne tourne.
- `ScanBientotRefuse` (critique) se déclenche le 12/11 à 09:31:48 UTC.
- La porte refuse `sample-app` à partir du 14/11 vers 09:31 UTC, `scannedAt` précédant de peu le referrer. Les pods en service ne sont pas touchés : la porte juge les publications.
- Retour : `kubectl patch cronjob -n scan scan-sample-app --type merge -p '{"spec":{"suspend":false}}'`, ou l'étape `scan_saut_reprendre`.

**Prédictions.**
- W1, avant la suspension : `30 9 * * *|3600|false|0`, admise en dry-run, `ScanEnRetard` inactive. Confiance haute (vérifié à sec).
- W2, suspension : admise, `suspend` à `true`, à l'audit en 200 au nom de `system:admin`, 0 `PolicyViolation`. Confiance haute.
- W3, passage de 09:30 UTC le 08/11 : aucun Job, aucune création de Job à l'audit depuis 09:30 UTC. `lastScheduleTime` reste à 2026-11-07T09:30:00Z. Confiance haute (lignes 514 à 517).
- W4, alerte : `ScanEnRetard` en firing. Le début notifié au récepteur local tombe 300 à 360 s après le 08/11 à 11:31:48 UTC. Prometheus v3.13.5, en service sur `sc-stockage`, envoie `StartsAt: alert.FiredAt` (`rules/manager.go`, ligne 478), et `FiredAt` est posé au passage en firing (`rules/alerting.go`, ligne 528), 300 s après `activeAt`, sur la grille des évaluations de 30 s. Empreintes : `manager.go` `0c5ae466…`, `alerting.go` `98880efc…`. L'`activeAt` du pending est affiché, pas contrôlé. Il y a au moins une notification firing : une seule si la reprise a lieu moins de 4 h après le firing (`repeat_interval`). `ScanBientotRefuse` reste inactive. Confiance haute.
- W5, reprise : admise en 200 au nom de `system:admin`, `suspend` à `false`, aucun passage actif.
- W6, après la reprise : 30 s plus tard, aucun Job depuis 09:30 UTC, `lastScheduleTime` inchangé, 0 événement de CronJob dans `scan`, `MissSchedule` compris. Confiance haute, sur le source de `v1.35.9`. Un `MissSchedule` ou un Job lancé à la reprise contredirait la lecture du source, et l'étape sortirait en KO.
- W7 : 0 `PolicyViolation` depuis la reprise.
- W8, le 09/11 : le passage de 09:30 UTC a lieu normalement, et `ScanEnRetard` se résout après le referrer suivant. Le relevé est hors étape, sans accord à demander (lecture seule).

Durée prédite : quelques secondes pour la suspension, environ 45 s pour la reprise (dont 30 s d'attente).

**Corrections avant tout passage** (07/11/2026, 16:18 UTC, avant le push, par amend du commit qui écrivait ces prédictions) :
- trap de reprise dans `scan_saut_reprendre` ;
- fenêtre de reprise bornée par l'historique de l'audit (09:25 UTC le 09/11 annoncé d'abord) ;
- W4 : début notifié prédit d'abord à 0 à 60 s après les 26 h, corrigé à 300 à 360 s après lecture du source de Prometheus v3.13.5 (complément de 16:18:36 UTC dans [scan-saut-sec.log](scan-saut-sec.log)).

Le principe du trap a été essayé localement, hors cluster : posé dans une fonction appelée dans le tube de `lancer`, il s'exécute à la sortie en KO, et sa sortie va au journal.

## Additif du 07/11/2026, 16:22 UTC : `scan_saut_suspendre` passée sur accord, W1 et W2 tenues, reprise programmée

Accord du propriétaire : « ok », en réponse à la recommandation de suspendre ce soir puis de lancer `scan_saut_reprendre` par un réveil le 08/11 à 11:40 UTC. Les effets et le pire cas avaient été cités dans les deux messages précédents.
- Passage de 16:21:58 à 16:21:59 UTC, code 0, journal [preuves-h5-scan_saut_suspendre.log](../../08-trust-plane/resultats/preuves-h5-scan_saut_suspendre.log).
- W1 tenue : `30 9 * * *|3600|false|0`, dernier passage le 07/11 à 09:30 UTC, suspension admise en dry-run, `ScanEnRetard` inactive.
- W2 tenue : `30 9 * * *|3600|true|0`. À l'audit, une ligne à 16:21:58.688 UTC, `system:admin`, code 200, recopiée dans le journal. 0 `PolicyViolation`.
- Défaut d'affichage, sans effet sur les contrôles : la dernière ligne (« sans reprise : … ») est sortie vide, avec deux erreurs de `date`, car le format contenant « à » n'était pas cité. Corrigé dans `preuves.sh` après le passage. La ligne rejouée donne : `ScanBientotRefuse` le 12/11 à 09:31:48, porte refusée le 14/11 à 09:31:48 UTC au plus tard.
- Reprise : tâche planifiée `supply-chain-scan-saut-reprise`, une seule fois, le 08/11/2026 à 11:40 UTC. Elle n'a droit qu'à l'étape `scan_saut_reprendre` : ni Job manuel, ni relance sur KO, ni commit, ni push. Elle rapporte à cette session.
- Si l'application est fermée à 11:40 UTC, la tâche part à son ouverture suivante. Au-delà de 01:00 UTC le 09/11 environ, l'étape sortira en KO, l'audit ne couvrant plus le passage sauté, et le trap reprendra le CronJob.

## Additif du 07/11/2026, 16:31 UTC : W8, relevé du 09/11 préparé à sec, bornes avant passage, rien lancé

Demande « continue » : préparer le jalon suivant à sec. Rien n'a été écrit dans le cluster, Zot ni les VM. La ligne W8 de l'additif de 16:15 UTC reste telle quelle. Elle disait le relevé « sans accord à demander » : c'était mon texte, pas celui du propriétaire. Le relevé du 09/11, et toute tâche planifiée qui le lancerait, lui seront soumis comme celui du 07/11. Essais archivés dans [scan-saut-w8-sec.log](scan-saut-w8-sec.log).

**Deux défauts de `essais-h5-planifie.sh`, corrigés avant tout passage le 09/11.**
- Le CronJob garde trois Jobs réussis (`successfulJobsHistoryLimit`). Le 09/11, le script aurait compté deux Jobs du planificateur, ceux du 07/11 et du 09/11, et relu le premier par ordre de nom, celui du 07/11. Il ne retient désormais que les Jobs créés depuis `PLAN`. Le filtre a été essayé hors ligne sur un JSON à deux passages : il rend le seul `scan-sample-app-29903610`, nom attendu le 09/11.
- La borne de l'audit était comparée comme une chaîne : `09:30:00.1Z` précède `09:30:00Z`. C'est la cause des deux KO du 07/11, décrite dans le complément de 09:49:54 UTC mais jamais corrigée dans le script. Elle est désormais comparée en secondes.
- Rejeu de la relecture du 07/11 (`PLAN=2026-11-07T09:30:00Z AVANT=3`), en lecture seule :
  - à 16:29:07 UTC, filtre seul corrigé : les deux mêmes KO d'audit ;
  - à 16:29:45 UTC, borne corrigée : `bilan : OK`, 1 création de Job par `cronjob-controller` et 1 création de pod par `job-controller` en 201, 0 refus 403 ou 422, 5 marqueurs dans Grafana.

**Nouveau script `scan-saut-resolution.sh`**, en lecture seule : Prometheus, le journal du récepteur local et Zot sur `sc-stockage`, le CronJob par l'API.
- Il refuse avant `FENETRE` (le 09/11 à 10:00 UTC) et si son journal existe.
- Il ne juge rien et sort en code 3 si le CronJob est suspendu ou si le dernier passage planifié n'est pas `PLAN`. W8 dépend de la reprise (W5).
- Essai à sec à 16:30:50 UTC : le CronJob est encore suspendu, la garde rend « non jugé », code 3.
- Essai sur une copie, la garde remplacée par l'état actuel et `ScanEnRetard` par `ChainsEchecSignature`, seule alerte du récepteur avec un firing et un resolved depuis le 05/11. Premier essai : 0 ligne lue, car `jq` n'avait pas l'option `-R`. Défaut corrigé, second essai : une notification firing, une resolved, un même début. L'écart de fin y est sans objet.

**Prédictions W8, le 09/11, relevé à partir de 10:00 UTC.**
- W8a, passage de 09:30 UTC. Commande : `PLAN=2026-11-09T09:30:00Z AVANT=4 JOURNAL=…/resultats/durcissement-h5_planifie-0911.log poc/bricks/08c-durcissement/essais-h5-planifie.sh`. Attendu : P1 à P6 comme le 07/11.
  - Le Job `scan-sample-app-29903610` est créé au plus 60 s après 09:30 UTC.
  - 6 conteneurs sortent avec le code 0, le pod tourne au plus 300 s.
  - 5 referrers sur l'image (4 relevés à 16:27 UTC).
  - À l'audit : 1 Job créé en 201 par `cronjob-controller`, 1 pod créé en 201 par `job-controller`, 0 refus 403 ou 422.
  - 5 marqueurs lus dans Grafana.
  - Le compte de 5 suppose aucun Job manuel d'ici là et aucune suppression par la rétention de Zot, dont la première est attendue le 21/11.
- W8b, résolution, par `scan-saut-resolution.sh`.
  - Garde passée : `false|2026-11-09T09:30:00Z`.
  - La métrique du dernier referrer est postérieure à 09:30 UTC et égale à la date du referrer le plus récent dans Zot.
  - `ScanEnRetard` et `ScanBientotRefuse` sont inactives.
  - Au récepteur, une seule notification resolved de `ScanEnRetard`, avec le même début que les firing. Sur les lignes firing, `endsAt` n'est pas une fin, et le script ne le lit pas.
  - La fin de `ScanEnRetard` tombe 0 à 1200 s après le nouveau referrer, en CONSTAT. La borne additionne `OnUnitActiveSec=15min` de `fraicheur-scan.timer`, sa précision d'une minute, la collecte de 30 s, l'évaluation de 30 s et 120 s de marge. Le 07/11, le délai réel était de 597 s.
  - Firing notifiées : 6, en CONSTAT. Le firing a lieu vers 11:36:48 UTC le 08/11, puis `repeat_interval` 4h jusqu'à la résolution vers 09:3x UTC le 09/11. Un redémarrage d'Alertmanager ou de la VM changerait ce compte.
  - Confiance : haute sur les états, moyenne sur le compte des firing.
- Ce qui n'est pas prouvé ici : l'heure de réception du resolved, affichée sans être contrôlée (`group_interval` 1m).

**Correction avant tout passage** (07/11/2026, 16:34 UTC, avant le push, par amend du commit qui écrivait ces prédictions) : borne de W8b prédite d'abord à 0 à 1020 s, portée à 1200 s. La précision du timer (`AccuracySec` d'une minute) absorbait toute la marge. Relevé en lecture seule à 16:33:33 UTC, complément 7 de [scan-saut-w8-sec.log](scan-saut-w8-sec.log) : délai réel de 597 s le 07/11 entre le referrer et la métrique dans Prometheus.

## Additif du 07/11/2026, 16:53 UTC : contre-relevé de la reprise du 08/11 préparé à sec, rien lancé

Demande « continue » : préparer à sec la lecture du rapport de reprise du 08/11. Le rapport de la tâche planifiée est une information, pas une preuve. Rien n'a été écrit dans le cluster, Zot ni les VM, aucune tâche planifiée n'a été créée.
- Nouveau script `scan-saut-reprise-verif.sh`, en lecture seule. Il relit le journal de `scan_saut_reprendre` et `chrono.tsv`, puis l'état réel : CronJob, Jobs, audit de l'API, alertes, récepteur local, referrers de l'image. Il refuse si son journal existe. Il sera lancé par la session principale après le rapport, journal `scan-saut-reprise-verif.log`.
- Les Events ne vivent qu'une heure. Relevé à 16:52:25 UTC : le plus vieil Event a été créé à 11:34:08 UTC, mais mis à jour pour la dernière fois à 15:52:03 UTC. Un compte d'Events lu plus d'une heure après la reprise ne prouve donc rien. W6 et W7 tiennent à l'étape elle-même, qui compte 30 s après la reprise. Le contre-relevé affiche les Events comme non probants et lit l'audit à leur place pour les Jobs et le CronJob.
- Essai à sec à 16:53:23 UTC, avec `PASSAGE=2026-11-07T09:00:00Z` pour exercer l'audit, dans [scan-saut-reprise-verif-sec.log](scan-saut-reprise-verif-sec.log), code 0 :
  - journal de l'étape et lignes de `chrono.tsv` absents, comme attendu avant la reprise ;
  - CronJob suspendu, dernier passage le 07/11 à 09:30 UTC ;
  - à l'audit, la création du Job du 07/11 à 09:30:00.104 UTC par `cronjob-controller` en 201, et la suspension à 16:21:58.688 UTC par `system:admin` en 200 ;
  - `ScanEnRetard` et `ScanBientotRefuse` inactives ;
  - 4 referrers, tous de type `https://supply-chain.example/scan/v1`, le dernier créé le 07/11 à 09:31:48 UTC. `AVANT=4` de W8a est confirmé à cette heure. Il sera relu au contre-relevé du 08/11. S'il change, il sera corrigé par un additif daté avant le 09/11 à 09:30 UTC.
- Non essayé sur des données réelles : la section du récepteur, aucune notification `ScanEnRetard` n'existant encore. L'expression est celle de `scan-saut-resolution.sh`, essayée sur `ChainsEchecSignature` (additif de 16:31 UTC).
