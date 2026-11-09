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

## Additif du 07/11/2026, 17:07 UTC : revue des comptes d'Events, N1 du 07/11 sur une source archivée

Revue en lecture seule des comptes de `PolicyViolation` et de `FailedCreate` archivés, suite au constat de 16:53 UTC (Events gardés une heure). Proposée au propriétaire, menée sur « continue » sans qu'il l'ait validée. Les autres lecteurs d'Events (`cilium.sh`, `stockage.sh`) ne sont pas revus :
- Aucune fenêtre de plus d'une heure. H2 : 4 minutes 20. Comptes hors étape du 07/11 : de 25 s (`resolveurs-pod-hors-etape.log`) à 52 minutes (`resolveurs-pod-sec.log`). Seule exception, l'essai à sec de 16:53 UTC (`PASSAGE` à 09:00 UTC), dont la ligne d'Events se déclare elle-même non probante. Traces des tests : quelques secondes.
- Un défaut d'une autre nature touche N1 (test 6, 14:03 UTC). Sa phrase « Aucun événement `PolicyViolation` depuis 14:03 UTC » vient d'un compte ad hoc de 14:06:50 UTC :
  - jamais archivé ;
  - filtré sur `.lastTimestamp` seul, champ nul sur les Events de Kyverno 1.19.2 (`events.k8s.io/v1`, `eventTime` seul). Le source est lu, l'Event n'a pas été observé. Ce compte valait donc 0 quoi qu'il arrive.
- N1 reste tenue : l'admission des deux TaskRuns est dans `preuves-h5-test6.log`.
- Source de remplacement, archivée dans [n1-refus-audit.log](n1-refus-audit.log) : de 14:03 à 14:07 UTC, 0 refus d'admission à l'audit, avec un témoin à 11:24:46 UTC. La métrique des refus de Kyverno reste inchangée à 1 (la sonde).
- Limite : les violations du scan d'arrière-plan ne sont pas couvertes.
- « Aucune alerte » de N7 est relue dans Prometheus : 0 série `ALERTS` sur la fenêtre.
- Deux passages précédents, avec un compte des refus de Kyverno mal filtré : celui de 17:05:40 UTC, affiché en partie et jamais archivé, et celui de 17:05:51 UTC, dans `n1-refus-audit-premier-passage.log`.

## Additif du 07/11/2026, 17:16 UTC : autres lecteurs d'Events revus, aucun défaut, inventaire de 17:07 UTC incomplet

Revue statique du dépôt, menée sur « continue » sans validation du propriétaire. Rien n'a été lancé ni lu dans le cluster, Zot ou les VM.

- **L'inventaire de 17:07 UTC était incomplet.** Il nommait deux autres lecteurs (`cilium.sh`, `stockage.sh`). Les scripts en contiennent sept qui passent par kubectl, sans compter les comptes de `PolicyViolation` et de `FailedCreate` déjà revus. Recherche : `git grep` de `get events`, `events.k8s.io`, `lastTimestamp`, `eventTime`, `firstTimestamp`, `involvedObject`, `sort-by=…Timestamp` et `kubectl events`, hors `.md`, `.log` et `.tsv`. Les `kubectl describe` (section Events) ne servent qu'au diagnostic d'un KO, jamais à un `attendu`. Le collecteur d'Events de la 19b n'est pas revu (`loki.source.kubernetes_events` d'Alloy, J4) : son traitement des Events qui n'ont que `eventTime` est du code amont.
- **`cilium.sh:171` et `:173`** (`attendu` « événements Pulling des pods de Cilium » à 0). Aucun filtre de temps, donc le format de l'émetteur, non vérifié, est sans effet. Les quinze journaux archivés affichent, dans la même étape et juste avant, « Pulled : 22 » (« already present on machine »). Les Events de ces pods étaient donc vivants à la lecture : aucun 0 ne vient de l'expiration. Affirmation tenue. Ces passages précèdent tous H1 (06/11, 16:33 UTC) : le dernier commit de chacun de ces journaux date au plus tard de 16:00:27 UTC le 06/11. La question de la limite de débit des Events, posée par l'additif H1 du README, reste entière.
- **`stockage.sh:234`** : affichage seul, quelques secondes après la création du pod, sans `attendu`.
- **`preuves.sh:3147`** : diagnostic affiché seulement en KO.
- **`essais-h5-scan.sh:47`** : affichage seul, à la fin du Job. L'avertissement `UnexpectedJob` annoncé par le README y figure (`durcissement-h5_scan.log`). L'ordre de tri, par `.lastTimestamp`, n'est utilisé nulle part.
- **`journalisation.sh:70-71`** (prédiction 6 de L1, 1 114 Events, « faux, de peu ») : compte instantané. La prédiction disait déjà « rétention d'une heure ». Inchangé.
- **`preuves.sh:3294`** (W6, étape `scan_saut_reprendre` du 08/11). Aucun filtre de temps, lecture 30 s après la reprise. Le source de `v1.35.9` est relu (copie de travail, hors dépôt). Pendant la suspension :
  - `syncCronJob` sort à la garde de suspension (ligne 514), avant le calcul du planning ;
  - `MissSchedule` (ligne 552) n'est émis qu'après cette garde, donc seulement à la reprise, dans la fenêtre lue.

  D'autres Events peuvent naître sans garde de suspension, à toute synchronisation, reprise comprise. Ce relevé corrige celui de 17:16 UTC, qui n'en citait que trois et ne lisait que `syncCronJob` (corrigé à 17:19 UTC, avant tout push) :
  - `UnknownTimeZone` (ligne 509), et `UnexpectedJob`, `SawCompletedJob`, `MissingJob` (lignes 447 à 489) dans `syncCronJob` ;
  - surtout `SuccessfulDelete` ou `FailedDelete` (lignes 751 et 757), émis par `cleanupFinishedJobs`, que `sync` appelle avant `syncCronJob` (ligne 214).

  État archivé après la suspension (`scan-saut-w8-sec.log`, relevé à 16:28 UTC) :
  - `successfulJobsHistoryLimit` et `failedJobsHistoryLimit` à 3 ;
  - deux Jobs, réussis tous les deux (`scan-sample-app-h5-manuel` et `scan-sample-app-29900730`), aucun actif ;
  - fuseau `Etc/UTC`, valide.

  Le nettoyage ne supprimera donc rien à la reprise, et ces Events ne devraient pas naître. W6 tient, à condition qu'aucun Job ne soit créé d'ici là ; l'étape compte d'ailleurs aussi ces créations. Si un `SuccessfulDelete` apparaissait, W6 sortirait en KO sans contredire la lecture sur `MissSchedule`.
- **`scan-saut-reprise-verif.sh:41`** : se déclare déjà non probant.

Aucune affirmation archivée n'est touchée et aucun script n'est modifié. Toujours non couvert : les violations du scan d'arrière-plan de Kyverno.

## Additif du 07/11/2026, 17:32 UTC : X2 du 07/11 incomplète, `ChainsEchecSignature` non prédite

Lors de l'étape `decision3` du 07/11, D3 s'est vérifiée : 5 PUT `.att` refusés, entre 11:36:01 et 11:36:14 UTC. Ces refus ont déclenché `ChainsEchecSignature` (A2), en firing de 11:36:07 à 11:46:07 UTC selon le récepteur. X2 ne prédisait que l'inactivité de `KyvernoRefusAnormaux`. L'alerte était pourtant attendue, puisque la règle ne peut pas filtrer les essais négatifs. Constat non prédit, sans défaut de la chaîne : voir [chains-echec-signature.log](chains-echec-signature.log) et le README de la 08c (additif de 17:32 UTC). Même mécanisme le 06/11, de 15:34 à 15:41 UTC, à la reprise de la collecte. Les échecs venaient des essais négatifs j6 et j7 du rejeu et de decision3 ; Loki les attribue un par un. Correction faite à 17:39 UTC, avant tout push.

Risque pour W8b (09/11) : `scan-saut-resolution.sh` lit le récepteur dans le journal local de `sc-stockage`. Celui-ci a perdu ses lignes du 06/11 antérieures à 17:03 UTC, par un mécanisme non établi. Si la perte se reproduit, des firing du 08/11 manqueront : ce serait un CONSTAT sur leur nombre, pas un KO, puisque le resolved est lu le jour même. Lire aussi Loki relève du propriétaire.

## Additif du 07/11/2026, 17:59 UTC : W8b lit aussi le récepteur dans Loki, avant le passage

Ajouté sur accord du propriétaire (« Oui, prépare-le »), à sec. Rien n'a été lancé dans le cluster, Zot ou les VM.
- `scan-saut-resolution.sh` lit maintenant les notifications de `ScanEnRetard` à deux endroits : dans le journal local de `sc-stockage`, comme avant, et dans Loki, par l'auditeur à travers Grafana (`{unite="recepteur-alertes.service"}`).
- Les OK et KO de W8b sont inchangés : ils restent jugés sur le journal local. Loki est affiché, avec ses comptes. Un écart entre les deux sources est un CONSTAT.
- Essai sur une copie, à 17:59 UTC, avec la garde remplacée et `ChainsEchecSignature` à la place de `ScanEnRetard`, depuis le 06/11 à 15:00 UTC ([scan-saut-w8-loki-sec.log](scan-saut-w8-loki-sec.log)) :
  - les lignes du 07/11 sont identiques des deux côtés ;
  - les 6 lignes du 06/11 (3 firing à 15:32:47, 3 resolved à 15:41:47) ne sont que dans Loki, et sortent en CONSTAT ;
  - second essai à 18:01 UTC, depuis le 07/11 à 11:00 UTC : « Loki et journal local : mêmes lignes », la branche que prédit le 09/11.
- Prédiction ajoutée : le 09/11, Loki et le journal local auront les mêmes lignes de `ScanEnRetard`. Confiance moyenne. Aux relevés de 17:39 et 18:01 UTC, les archives du journal local commencent le 06/11 à 17:03 UTC. Un seul état ne dit pas si la perte est glissante ou ponctuelle : ce n'est pas établi. Corrigé à 18:01 UTC, avant tout push : la première rédaction disait « environ 24 h ». Si les firing du 08/11 manquent au journal local, le CONSTAT de nombre de W8b s'expliquera par Loki.

## Additif du 07/11/2026, 18:04 UTC : A2 prédite dans les étapes decision3, restreint et construire

`ChainsEchecSignature` (A2) est désormais annoncée dans les prédictions affichées par les trois étapes où ces échecs voulus ont été constatés le 06 et le 07/11, sur accord du propriétaire (« Oui, ajoute-la ») :
- `preuves.sh decision3` : `storage`, une hausse par PUT `.att` refusé ;
- `politique.sh restreint` (J6) : `payload_creation` sur `j6-sans-restriction-enforce` et `j6-sans-drapeau`, jamais lancés ;
- `construction.sh construire` (J7) : `payload_creation` sur les PipelineRuns sans Kata et à étiquette, et sur leurs TaskRuns `construire`.

La prédiction : firing jusqu'à environ 10 min après le dernier échec, puis firing et resolved au récepteur local. Dans un rejeu complet, si Prometheus ne collecte pas encore Chains, l'alerte part à la première collecte, comme le 06/11 à 15:32 UTC. La brique 19 annonçait déjà, dans son README, que chaque rejeu de la 08 déclencherait A2. Il manquait la prédiction dans les étapes elles-mêmes : c'est ce qui a manqué à X2 le 07/11. Seuls des `echo` sont ajoutés, aucun contrôle ne change. Rien n'a été lancé. Base : [chains-echec-signature.log](chains-echec-signature.log) de la 08c.

**Cas non déterminé, et limite d'A2 (corrigé à 18:07 UTC, avant tout push, après relecture du conseiller).**
- **Les quatre TaskRuns de l'étape `taches` de J6** : `j6-non-signee`, `j6-modifiee`, `j6-autre-cle` et `j6-hors-politique`, tous en `signed=failed` avec `retries=3`.
  - Ils ont été créés de 13:47:48 à 13:48:18 UTC le 06/11. L'étape `chains` de J6 a ensuite redémarré le contrôleur (patch du déploiement, de 13:48:48 à 13:48:50 UTC), avant toute collecte.
  - Loki n'a aucune ligne de l'ancien pod, donc le type de leur échec est inconnu.
- **Ce que dit le source de Chains v0.29.9** (`pkg/chains/signing.go`, `recordError`) : seuls les échecs sur les artefacts TaskRun et PipelineRun font monter les compteurs. Un échec limité aux artefacts OCI (signature d'image) mène à `signed=failed` (`HandleRetry`, puis `MarkFailed`) sans hausse d'aucun compteur.
- **Conséquences :**
  - lancée seule, l'étape `taches` peut déclencher A2 ou non : ce n'est pas prédit ;
  - dans un rejeu complet, le redémarrage de l'étape `chains` l'efface ;
  - plus largement, d'après le source et sans l'avoir observé, A2 ne voit pas un échec de signature limité à l'image, et `ChainsMarqueSansSignature` non plus, puisque l'objet n'est pas marqué signé.

## Additif du 07/11/2026, 18:18 UTC : collecteur d'Events de la 19b (Alloy) revu, aucun défaut

Revue statique menée sur « continue », sans validation du propriétaire. Rien lu dans le cluster, Zot ou les VM. L'additif de 17:16 UTC laissait ce lecteur de côté. Base : [revue-alloy-evenements.log](../../19b-journalisation/resultats/revue-alloy-evenements.log) (source d'Alloy v1.21.3, f2108cd, copie intacte ; version installée sur `sc-stockage` au rejeu du 06/11 à 15:31 UTC, `rejeu-rke2.log`, ajouté à 18:20 UTC, avant tout push).
- **Horodatage** : `eventTimestamp` prend `series.lastObservedTime`, sinon `lastTimestamp`, sinon `eventTime`. Les Events de Kyverno 1.19.2 (`eventTime` seul) sont donc collectés. Le défaut du filtre sur `.lastTimestamp` seul (additif de 17:07 UTC) ne touche pas Alloy. Non vérifié dans Loki.
- **TTL d'une heure** : Alloy écrit chaque Event à sa réception, avec l'heure de l'Event. La TTL ne touche que les Events émis plus d'une heure avant la reprise d'Alloy après un arrêt (corrigé à 18:20 UTC, avant tout push : « émis pendant un arrêt de plus d'une heure » était inexact, ceux de la dernière heure sont rattrapés).
- **Témoin du deuxième passage L4** : sans aucun horodatage, il est ignoré par la garde de la ligne 204 (heure zéro jamais postérieure à la position). Le « jamais collecté » archivé est expliqué.
- **Positions au redémarrage** (lu, non observé) : la position est figée au démarrage et vaut l'heure du dernier Event envoyé, pas de la plus grande. Un redémarrage d'Alloy peut donc perdre des Events non encore vus, ou en doubler.
- **Lecteurs dans Loki** : `journalisation.sh:391`, compte sur 24 h affiché comme contrôle de présence, qui compte des écritures (chaque mise à jour d'un Event en ajoute une) et non des Events distincts ; `journalisation.sh:496`, témoin J4, fenêtre de 15 min pour une date tronquée à la seconde, tenu.
- **« 1 sur 918 »** de `l4-evenements-horodatage.log` : commande non archivée, source non établie, non jugé.
- Lire les Events dans Loki au lieu de kubectl éviterait la TTL : possible, à décider avec le propriétaire.

## Additif du 07/11/2026, 19:56 UTC : perte du journal local de `sc-stockage`, mécanisme probable et prédictions avant la relecture du 08/11

Revue statique menée sur « continue », sans validation du propriétaire. Rien n'a été lu ni écrit dans le cluster, Zot ou les VM. Base : [revue-journald-stockage.log](revue-journald-stockage.log).

**Source de systemd v257.13, version de l'image Debian.**
- `journal-file.c:4003-4080` : par défaut, journald fixe `max_use` à 10 % du système de fichiers et `max_size` au huitième de `max_use`.
- Ces valeurs sont fixées au démarrage du processus (`journald-server.c:2665`), sans rechargement.
- À chaque rotation, journald supprime les archives les plus vieilles, jusqu'à repasser sous la limite (`journal-vacuum.c:291-317`).

**Lecture.**
- La racine de l'image fait 2,874 GiB avant agrandissement. Au premier démarrage, le 06/11 à 13:28 UTC, le plafond valait donc environ 290 Mo. Deux archives environ ont été supprimées, d'où la tête du 06/11 à 17:03:02 UTC.
- Les 386,1 M du 07/11 à 17:39 UTC dépassent le maximum permis par ce plafond, 367,9 Mio. Il a donc été levé, au plus tard au redémarrage de 11:22 UTC, vers 10 % de 20 Go.
- La perte était glissante sous ce plafond, sur une fenêtre d'environ 18 h. Elle s'est arrêtée à sa levée : la tête du 06/11 à 17:03:02 UTC est l'état figé au redémarrage (corrigé à 19:59 UTC, avant tout push : « ponctuelle, pas glissante » contredisait le mécanisme). Lu dans le source et compatible avec les archives, non observé.
- Non relus : la version installée, les correctifs Debian, l'ordre de growpart et du transfert du journal.
- Les lignes de 13 h à 16 h du démarrage -1 encore lues restent inexpliquées. Piste : `user-1000.journal`, jamais supprimé.

**Prédictions.**
- **P1, relecture du 08/11 après la reprise.** La plus vieille archive reste `…-00000000000160aa-00065f9e95c7cfcc` (tête du 06/11 à 17:03:02 UTC). L'occupation dépasse 386,1 M. Une tête avancée réfute le mécanisme.
- **P2, mesure qui tranche, sur accord du propriétaire seulement.** Au démarrage 0, le message de journald annonce un max de 1,8 à 2,0 G. `dpkg-query -W systemd` donne `257.13-1~deb13u1`.
- **P3, W8b du 09/11.** Les notifications de `ScanEnRetard` depuis le 08/11 à 11:30 UTC sont encore dans le journal local : « mêmes lignes » que Loki. Confiance haute si P1 tient : pour perdre ces lignes, il faudrait environ 80 Mo/h, cinq fois le rythme moyen observé (15,7 M/h). Elle remplace la confiance moyenne de l'additif de 17:59 UTC, sans réécrire celui-ci.

**Conséquence, sans action.** Depuis le redémarrage du 07/11, journald peut occuper jusqu'à environ 2,5 Go sur `sc-confiance` (25 Go), sous réserve de garder 5 % de place libre ; G7 de la 07a supposait 282 Mo. L'effet sur la marge avant éviction n'est pas mesuré. Fixer `SystemMaxUse` toucherait les VM : décision du propriétaire.

## Additif du 07/11/2026, 20:20 UTC : P1 et P2 lues sur `sc-stockage`, sur accord du propriétaire

Accord : « traite tout », reçu peu avant 20:17:44 UTC. Il répond au message qui citait les effets : une session ssh en lecture seule, rien d'écrit sur la VM ; pire cas, une ligne de session dans l'audit de `sc-stockage`. Lecture faite à 20:18:00 UTC. Base : [journald-stockage-p1p2.log](journald-stockage-p1p2.log).

- **P2 tenue.** Au démarrage 0 (07/11 à 11:22:36 UTC), journald annonce `System Journal … is 271.2M, max 1.9G, 1.6G free` (prédit : max de 1,8 à 2,0 G). `dpkg-query -W systemd` donne `257.13-1~deb13u1`. Les 271,2 M de ce moment restent sous l'ancien plafond d'environ 290 Mo : compatible.
- **P1, point intermédiaire seulement.** La plus vieille archive système reste `…-00000000000160aa-00065f9e95c7cfcc`, et l'occupation vaut 418.1M (plus de 386,1 M). P1 se juge à la relecture du 08/11 après la reprise.
- **Tailles des archives.** Les sept archives d'avant le 07/11 à 10:24 UTC font chacune 37 031 936 octets (35,3 Mio). C'est sous le maximum par fichier de l'ancien plafond, environ 36,8 Mio. `system.journal` fait 134 217 728 octets, soit 128 Mio, le maximum par fichier sous le nouveau plafond. Compatible avec le mécanisme, sans être expliqué à l'octet.
  - La huitième archive (`…-0000000000060b74`, tête du 07/11 à 10:24:02 UTC) fait 41 943 040 octets (40 Mio), au-dessus d'environ 36,8 Mio : non expliqué. Piste, non lue : fichier rouvert après le redémarrage et écrit sous le nouveau maximum avant d'être archivé. (Ajouté à 20:21 UTC, avant tout push, après relecture du conseiller.)
- **Précision sur la « tête ».** Pour `journalctl`, l'entrée la plus ancienne date du 06/11 à 13:28:37 UTC (numéro 974, démarrage -1), et non de 17:03:02 UTC.
  - D'après leurs noms, les archives système commencent toutes au numéro 90 282 ou après. L'entrée 974 est donc dans un autre fichier ; par élimination, `user-1000.journal`, jamais supprimé. C'est déduit, non lu directement.
  - Cela expliquerait les lignes de 13 h à 16 h du démarrage -1 encore lisibles.
  - Le « 06/11 à 17:03:02 UTC » des additifs précédents est la tête des archives système. C'est là que vivent les lignes du récepteur ; P1 et P3 portent sur elles.
- **Rythme.** De 271,2 M (07/11 à 11:22 UTC) à 418,1 M (20:18 UTC), environ 16 M/h, proche des 15,7 M/h moyens. La confiance haute de P3 tient, sous réserve de P1 au 08/11.
- Le message de journald du démarrage -1 n'est plus dans le journal (aucune ligne « max ») : le plafond d'environ 290 Mo du premier démarrage reste déduit, non lu.

## Additif du 07/11/2026, 20:45 UTC : décisions du propriétaire sur `SystemMaxUse`, A2 et les Events dans Loki

**Décisions du propriétaire, 07/11/2026, écrites à 20:45 UTC.** La réponse « garde tes recommandations », reçue peu avant 20:44:42 UTC, retient les trois recommandations du message qui suivait le commit 2ed0290 :
- **`SystemMaxUse` : aucun changement avant le relevé W8 du 09/11.** Une limite vers 500 M nettoierait dès maintenant le journal de `sc-stockage` (418 M, environ 16 M/h) et emporterait les lignes que W8b relit. Après le 09/11, la seule raison de la reconsidérer est la marge disque de `sc-confiance` pour G7 : Loki reste la référence d'audit. Deux points restent non vérifiés : l'effet d'un redémarrage de journald sur les VM en service, et la levée du plafond du premier démarrage par une configuration posée par cloud-init.
- **A2 : limite acceptée.** Les compteurs d'échec de Chains v0.29.9 n'ont pas d'étiquette : les échecs voulus des essais négatifs ne se filtrent pas. Cette limite est écrite dans le commentaire de la règle et annoncée dans les prédictions des étapes depuis 0f5b964. Rien n'est changé dans Prometheus ni dans Alertmanager.
- **Events dans Loki : une passe dédiée après le 09/11, avec ses propres prédictions.** Ce n'est pas un simple remplacement : Loki garde une ligne par mise à jour d'Event (`journalisation.sh:391`), donc les comptes changent. Six lectures fondent un verdict sur des Events : `preuves.sh:3184`, `3238`, `3298` et `3304`, `durcissement.sh:270`, `cilium.sh:173`. Les lignes 3298 et 3304 tournent le 08/11 pendant la reprise : aucun script n'est touché avant la fin de W8.
- La relecture P1 du 08/11 n'a pas d'accord à ce stade : sans accord, P1 sera écrite « non relue ».

## Additif du 08/11/2026, 12:05 UTC : `scan_saut_reprendre` passée par la tâche planifiée, W3 à W7 tenues ; P1 tenue

La tâche `supply-chain-scan-saut-reprise` (accord du 07/11 vers 16:21 UTC) a lancé l'étape à 11:40:43 UTC ; elle s'est terminée à 11:41:16 UTC avec 14 OK, 0 KO et 0 CONSTAT. Journal : [preuves-h5-scan_saut_reprendre.log](../../08-trust-plane/resultats/preuves-h5-scan_saut_reprendre.log). Le contre-relevé en lecture seule, à 12:04:29 UTC, sur accord du propriétaire (« Oui » à « Je lance les deux, ou le contre-relevé seul ? », compris comme : les deux ; précisé à 12:07 UTC, avant tout push), retrouve les mêmes faits : [scan-saut-reprise-verif.log](scan-saut-reprise-verif.log).
- **W3 tenue.** 0 Job et 0 création de Job à l'audit depuis le 08/11 à 09:30 UTC. Le dernier passage reste le 07/11 à 09:30:00 UTC.
- **W4 tenue.** `ScanEnRetard` est en firing, en pending depuis 11:32:07 UTC (affiché). Le récepteur local a reçu un seul firing à 11:37:17 UTC, avec un début notifié à 11:37:07 UTC, soit 319 s après les 26 h (prédit : 300 à 360 s). `ScanBientotRefuse` est inactive.
- **W5 tenue.** Reprise à 11:40:44 UTC : à l'audit, `system:admin` en 200 ; `suspend` à `false`, aucun passage actif, encore vrai au contre-relevé.
- **W6 tenue.** Après la reprise : dernier passage inchangé, 0 Job, 0 événement du CronJob, `MissSchedule` compris.
- **W7 tenue.** 0 `PolicyViolation` depuis la reprise.
- **Referrers de l'image : 4 au contre-relevé**, les mêmes que le 07/11 à 16:27 UTC. Le dernier date du 07/11 à 09:31:48 UTC. `AVANT=4` de W8a est confirmé.
- **P1 tenue** (additif du 07/11, 19:56 UTC), relue à 12:04:36 UTC sur le même accord : [journald-stockage-p1-0811.log](journald-stockage-p1-0811.log). La plus vieille archive système reste `…-00000000000160aa-00065f9e95c7cfcc` (06/11 à 17:03:02 UTC), et l'occupation vaut 650.1M (plus de 386,1 M).
  - Deux archives de 128 Mio sont apparues : leurs têtes datent du 07/11 à 12:01:03 et à 20:35:03 UTC.
  - Le rythme est d'environ 14,7 M/h depuis le 07/11 à 20:18 UTC.
  - Le mécanisme n'est pas réfuté, et la confiance haute de P3 tient pour le 09/11.
- **Ce que le relevé ne prouve pas.**
  - Que le passage du 09/11 à 09:30 UTC aura lieu et que l'alerte se résoudra : c'est W8, relevé le 09/11.
  - Les comptes d'Events du contre-relevé, lus 24 min après la reprise : ils ne couvrent que l'heure de la TTL. W6 et W7 se jugent sur l'étape et sur l'audit.
  - Le rapport de la tâche n'est qu'une information : tout ce qui précède vient des journaux.


## Additif du 09/11/2026, 10:51 UTC : W8 relevé par la tâche planifiée, W8a et W8b tenues ; P3 tenue

La tâche `supply-chain-scan-saut-releve-0911`, accordée le 08/11 peu avant 12:09:50 UTC (« 2 oui »), a démarré à 10:40:30 UTC. Elle a lancé les deux scripts en lecture seule, et les deux journaux concluent `bilan : OK`, sans KO ni CONSTAT. Le rapport de la tâche n'est qu'une information : tout ce qui suit vient des journaux, lus par la session principale.

**W8a tenue**, relecture de 10:40:42 UTC : [durcissement-h5_planifie-0911.log](durcissement-h5_planifie-0911.log).
- CronJob non suspendu, dernier passage planifié le 09/11 à 09:30:00 UTC, aucun Job actif.
- Job `scan-sample-app-29903610`, le nom attendu, créé 0 s après 09:30 UTC (prédit : au plus 60 s). C'est le seul Job du planificateur retenu depuis `PLAN`.
- 6 conteneurs sur 6 sortis avec le code 0, sans OOM ni redémarrage ; pod de 114 s (prédit : au plus 300 s), sur `sc-confiance`.
- 5 referrers sur l'image (prédit : 5, 4 avant le passage).
- Audit depuis 09:30 UTC : 1 Job créé en 201 par `cronjob-controller`, 1 pod créé en 201 par `job-controller`, 0 refus 403 ou 422 (prédit : 1, 1 et 0). Les seuls refus affichés sont des 404 de lecture (`ciliumendpoints` de Cilium, `ephemeralreports` et `policyreports` de Kyverno), hors du contrôle.
- 5 marqueurs lus dans Grafana par le compte auditeur (prédit : 5).

**W8b tenue**, relevé de 10:40:50 UTC : [scan-saut-w8_resolution.log](scan-saut-w8_resolution.log).
- Garde passée : `false|2026-11-09T09:30:00Z`.
- Métrique du dernier referrer : 09:31:52 UTC, postérieure au passage et égale au referrer de scan le plus récent dans Zot.
- `ScanEnRetard` et `ScanBientotRefuse` inactives.
- Au récepteur local : une seule notification resolved, reçue à 09:41:22 UTC, avec le même début que les firing (08/11 à 11:37:07 UTC).
- Fin de `ScanEnRetard` 555 s après le nouveau referrer (prédit : 0 à 1200 s ; 597 s le 07/11).
- Firing notifiées : 6, comme prédit (confiance moyenne), de 11:37:17 UTC le 08/11 à 07:37:22 UTC le 09/11, toutes les 4 h. Cette régularité est compatible avec l'absence de redémarrage d'Alertmanager : déduit, non relu.
- Resolved reçue 15 s après la fin : affiché, non contrôlé.

**P3 tenue** (additif du 07/11, 19:56 UTC) : Loki, lu par l'auditeur à travers Grafana, a les 7 mêmes lignes que le journal local (6 firing, 1 resolved) : « Loki et journal local : mêmes lignes ». Le journal local de `sc-stockage` n'a pas perdu les notifications depuis le 08/11 à 11:30 UTC.

**Ce que le relevé ne prouve pas.**
- Le comportement d'un passage sauté plus long que 26 h, ou de deux passages sautés de suite : non essayé.
- L'heure de réception du resolved (`group_interval` 1m) : affichée seulement.
- La tenue du journal local de `sc-stockage` au-delà du 09/11 : `SystemMaxUse` reste à reconsidérer après W8, selon la décision du 07/11 à 20:45 UTC.

Le saut d'un passage du scan (W1 à W8) est entièrement passé.

## Additif du 09/11/2026, 11:05 UTC : Events dans Loki, analyse à sec, décisions à prendre et prédictions d'un relevé, rien lancé

Accord : « traite tout, non ? », en réponse à la proposition de trois travaux à sec, sans effet sur le cluster, Zot ou les VM. Je le comprends comme : les trois, à sec. Rien n'a été lu ni écrit dans le cluster, Loki, Prometheus, Zot ou les VM. Seul le source public d'Alloy v1.21.3 a été relu sur GitHub (`internal/component/loki/source/kubernetes_events/event_controller.go`). Aucun script n'est modifié : la forme des contrôles dépend des décisions E1 à E4 ci-dessous.

**Ce qu'Alloy écrit dans Loki, d'après son source.** Cela complète la revue du 07/11 à 18:18 UTC.
- Étiquettes : `namespace`, celui de l'objet concerné ; `job` et `instance` ; et `source="evenements-k8s"`, posée par `evenements.alloy`.
- Ligne JSON :
  - `name` et `kind` de l'objet concerné, pas de l'Event ;
  - `reason`, `type`, `count`, `msg`, `eventRV`, `sourcecomponent`, `reportingcontroller`, etc.
  - Ni le nom de l'Event ni son `creationTimestamp` n'y figurent.
- Horodatage de la ligne : `series.lastObservedTime` s'il existe, sinon `lastTimestamp`, sinon `eventTime`.
- Une ligne par création, puis une par mise à jour qui change la `resourceVersion`. Un Event répété donne donc plusieurs lignes.
- Ligne ignorée si son horodatage ne dépasse pas la position enregistrée au démarrage du collecteur. D'où les pertes ou doublons possibles après un redémarrage d'Alloy, déjà notés le 07/11.
- Rétention de Loki : `retention_period: 720h` (`19b-journalisation/config/loki.yaml`). Les fenêtres du 06/11 au 08/11 restent lisibles jusqu'au 06/12 environ.

**Les six contrôles, relus dans le dépôt (lignes inchangées depuis le 07/11).**

| Contrôle | Lecture actuelle | Défaut propre à kubectl | Avec Loki |
|---|---|---|---|
| `preuves.sh:3184`, `resolveurs_pod` | `PolicyViolation` dont `creationTimestamp` ≥ t0, attendu 0 | Un Event plus ancien que t0, répété après t0, n'est pas compté | Toute ligne datée après t0 compte, répétition comprise : plus strict |
| `preuves.sh:3238`, `scan_saut_suspendre` | Idem | Idem | Idem |
| `preuves.sh:3298`, `scan_saut_reprendre` | Events du CronJob dans `scan`, **sans borne de temps**, attendu 0 | Compte ce qui reste de la dernière heure, avant comme après la reprise | Fenêtre bornée à partir de la reprise |
| `preuves.sh:3304`, `scan_saut_reprendre` | `PolicyViolation` après t1, attendu 0 | Comme 3184 | Comme 3184 |
| `durcissement.sh:270`, `h2_releve` | `FailedCreate` dont `lastTimestamp // eventTime` > t0, attendu 0 | Un relevé lancé plus d'une heure après H2 rend 0 quoi qu'il soit arrivé | La TTL ne joue plus |
| `08-trust-plane/cilium.sh:173` | `Pulling` des pods `cilium*` de `kube-system`, **sans borne**, attendu 0 | Passée une heure après le démarrage des pods, rend 0 quoi qu'il soit arrivé | Fenêtre bornée au déploiement des pods |

Point commun : les six attendent 0. Un 0 dans Loki ne prouve rien si la collecte ne tournait pas. Il faut donc un témoin de vie (E3).

**Décisions à prendre par le propriétaire, avec mes recommandations.**
- **E1, rôle de Loki.**
  - (a) Loki donne le verdict, et la lecture par kubectl reste affichée ; un écart entre les deux est un CONSTAT, comme pour W8b.
  - (b) Loki seul.
  - (c) Double verdict.
  - Recommandé : (a). Il garde la comparaison sans faire échouer une étape sur la TTL.
- **E2, unité de compte.**
  - Des lignes, pas des Events : l'identité de l'Event n'est pas dans la ligne, la reconstruire serait fragile.
  - Pour des contrôles attendus à 0, l'unité ne change pas le verdict.
  - Recommandé : compter les lignes et le dire dans le libellé.
- **E3, témoin de vie de la collecte.**
  - (a) Le script crée un Event témoin et le retrouve, comme J4 de la 19b. Cela écrit dans le cluster.
  - (b) Témoin passif, sans rien écrire :
    - au moins une ligne `evenements-k8s` dans la fenêtre (`rattrapage` et `horodatage` en produisent chaque minute, non relu) ;
    - Alloy de `sc-stockage` non redémarré dans la fenêtre, d'après `ActiveEnterTimestamp` lu par ssh ;
    - sinon, non jugé.
  - Recommandé : (b).
- **E4, ordre.**
  - (a) D'abord un relevé en lecture seule sur les fenêtres déjà archivées (prédictions R1 à R8), pour régler les requêtes et mesurer l'écart avec kubectl. Ensuite seulement, la modification des six contrôles, sans rejouer les étapes, qui écrivent dans le cluster.
  - (b) Modifier tout de suite.
  - Recommandé : (a).

**Prédictions du relevé R, avant tout passage.**
- Commande à écrire après les décisions.
- Effets : lecture de Loki par l'auditeur à travers Grafana ; en option une session ssh sur `sc-stockage`, en lecture seule. Rien n'est écrit.
- Pire cas : quelques requêtes de plus dans les journaux de Grafana et de Loki.
- Requêtes :
  - de forme `{source="evenements-k8s"} | json | reason="…"` ;
  - avec le filtre `namespace` ou `kind` selon le contrôle ;
  - comptées sur une fenêtre de 5 minutes à partir de l'heure de départ archivée.
- Cette fenêtre déborde l'instant du contrôle d'origine : une ligne venue après lui serait un CONSTAT, pas une réfutation.

| # | Fenêtre (UTC) | Attendu | Confiance |
|---|---|---|---|
| R1, témoin positif | 06/11, 16:49:02 à 16:53:29 (`h2_releve`), `PolicyViolation` | Au moins 32 lignes, puisque kubectl y comptait 32 Events | Moyenne : collecte non vérifiée ce jour-là |
| R2, `durcissement.sh:270` | Même fenêtre, `FailedCreate` | 0 | Haute |
| R3, `preuves.sh:3184` | 07/11 dès 16:00:56, `PolicyViolation` | 0 | Moyenne : d'autres pods ont pu en produire dans les 5 minutes |
| R4, `preuves.sh:3238` | 07/11 dès 16:21:58, `PolicyViolation` | 0 | Moyenne, même raison |
| R5, `preuves.sh:3298` | 08/11 dès 11:40:44, `namespace="scan"`, `kind="CronJob"` | 0 | Haute |
| R6, témoin positif de R5 | 09/11 dès 09:30:00, même filtre | Au moins 1 ligne, création du Job par le contrôleur ; motif exact non relu dans le source | Moyenne |
| R7, `preuves.sh:3304` | 08/11 dès 11:40:44, `PolicyViolation` | 0 | Moyenne |
| R8, `cilium.sh:173` | 06/11, 11:00 au 09/11, `namespace="kube-system"`, `reason="Pulling"`, `name=~"cilium.*"` | 0 : les images sont dans le cache de containerd, « already present on machine » au rejeu du 06/11 | Moyenne : pods recréés à H3, `h5_cilium`, H6 et au redémarrage des VM |

- Affiché, non jugé : le dernier démarrage d'Alloy sur `sc-stockage`. Prédit : au redémarrage des VM du 07/11, vers 11:22 UTC. R1, R2 et R8 sont donc antérieurs ou à cheval.
- Ce que R ne prouvera pas :
  - que les étapes rejouées avec Loki rendraient les mêmes verdicts ;
  - l'effet d'un redémarrage d'Alloy pendant une étape ;
  - le délai d'ingestion d'un Event : sa mesure demanderait un témoin écrit, option (a) de E3.

## Additif du 09/11/2026, 13:11 UTC : Events dans Loki, décisions E1 à E4 des Events prises, précondition du relevé écrite avant tout passage

**Décision du propriétaire.** Il a répondu « 2 ok » à « Les Events deviennent un chantier à part, avec E1 à E4 tels que je les recommande et E3 obligatoire ? ». Ce chantier est la passe dédiée décidée le 07/11 (additif de 20:45 UTC). La 08c est close (README, additif de 13:11 UTC). Les libellés E1 à E4 et R1 à R8 ci-dessous sont ceux des Events, additif de 11:05 UTC, distincts des E1 à E5 et R3, R4 de la 08c.

- **E1 des Events** : (a). Loki donne le verdict, la lecture par kubectl reste affichée ; un écart entre les deux est un CONSTAT.
- **E2 des Events** : compter des lignes, et le dire dans le libellé.
- **E3 des Events** : (b), témoin passif, **obligatoire**. Au moins une ligne `evenements-k8s` dans la fenêtre, et Alloy de `sc-stockage` non redémarré dans la fenêtre d'après `ActiveEnterTimestamp`. Sinon, le contrôle est **non jugé**, jamais OK.
- **E4 des Events** : (a). D'abord le relevé R1 à R8 en lecture seule, sur son propre accord ; ensuite la modification des six contrôles.

**Précondition du relevé, écrite avant tout passage.** R1 et R6 sont les deux témoins positifs. Si R1 ou R6 échoue, aucun 0 de R2 à R5, R7 et R8 ne compte : ils sont écrits non jugés, et la requête ou la collecte est à reprendre avant toute conclusion. R1 ne vaut que pour R2 (même fenêtre) ; R6 que pour R5 (même filtre) ; R3, R4, R7 et R8 n'ont pas de témoin positif dans leur fenêtre et reposent sur E3 seul.

**Estimation** : aucune n'est fixée à cette heure ; elle sera proposée au propriétaire avant tout passage.

## Additif du 09/11/2026, 14:46 UTC : relevé R1 à R8 des Events préparé à sec, non lancé

Travail local, rien lu ni écrit dans le cluster, Loki, Grafana, Zot ou les VM. Le propriétaire a choisi « Chantier des Events » parmi les décisions ouvertes. Ce choix ouvre le chantier : il ne valide pas l'estimation et ne vaut pas accord pour le relevé.

- **Début du chantier** : entre 14:38:26 et 14:42:02 UTC, compté depuis 14:38:26 (corrigé à 14:49 UTC, avant tout push : 14:42:02 avait été relevée après plusieurs minutes de recherche ; 14:38:26 est la dernière heure relevée avant le choix du propriétaire, à la lecture de l'issue #18525). **Estimation proposée** : 4 h, non validée ; le seuil de décision (2×) serait atteint à 8 h.
- **Commande** : `mise exec -- poc/bricks/08c-durcissement/evenements.sh releve`, journal `resultats/evenements-releve.log`. Le script est rangé dans la 08c, close, parce que les décisions et les prédictions du chantier y sont ; le propriétaire peut le déplacer.
- **Lu dans le source d'Alloy v1.21.3** (version épinglée par la 19b, `internal/component/loki/source/kubernetes_events/event_controller.go` au tag) :
  - chaque ligne est horodatée par `series.lastObservedTime`, à défaut `lastTimestamp`, à défaut `eventTime` ; kubectl, dans `durcissement.sh:270`, prenait `lastTimestamp // eventTime` : un Event en série peut tomber d'un côté différent de la borne ;
  - chaque mise à jour d'un Event (nouvelle `resourceVersion`) donne une nouvelle ligne ; une suppression n'en donne pas ;
  - au démarrage, Alloy écarte les Events dont l'horodatage n'est pas postérieur à la dernière position enregistrée ; un Event sans aucun horodatage est donc toujours écarté (1 sur 918 en L4 de la 19b, `l4-evenements-horodatage.log`). Un 0 dans Loki ne couvre pas ces Events ;
  - champs JSON utilisés : `kind`, `name` (objet concerné), `reason`, `count` ; étiquettes `namespace`, `job`, `instance`, plus `source` posée par `evenements.alloy`.
- **Fenêtres exactes, bornées des deux côtés** (la fonction `grafana_lignes` de la 07a, qui lit jusqu'à l'instant présent, n'est pas reprise) :
  - R1 et R2 : 06/11, 16:49:02 à 16:53:29. 16:49:02 est le `t0` de `h2_releve`, début de `h2_kyverno` (`durcissement.sh:250`, première ligne de `durcissement-h2_kyverno.log`) ; kubectl a compté les 32 Events à `h2_releve`, lancé à 16:53:22. La fenêtre couvre donc la population du contrôle d'origine ;
  - R3 : 07/11, 16:00:56 à 16:05:56 ; R4 : 16:21:58 à 16:26:58 ; R5 et R7 : 08/11, 11:40:44 à 11:45:44 ; R6 : 09/11, 09:30:00 à 09:35:00 ;
  - R8 : 06/11, 11:00:00 jusqu'à l'heure du passage. Le filtre ajoute `kind="Pod"`, comme `cilium.sh:173`. Lecture par kubectl affichée : `cilium-verifier.log`, dernier passage archivé du contrôle, 06/11 à 13:32:30 (corrigé à 14:49 UTC, avant tout push : `rejeu-rke2-sixieme-passage.log`, 13:28, pris dans une liste non triée ; essai repassé, mêmes bilans).
- **Numéros de ligne** : depuis le commit `3791082`, les contrôles de `preuves.sh` sont 4 lignes plus bas (3188, 3242, 3302, 3308 au lieu de 3184, 3238, 3298, 3304).
- **Verdicts écrits avant le passage** :
  - une réponse en erreur ou qui atteint `maxLines` (1000) est **non jugée**, jamais un compte ;
  - le témoin E3 et le contrôle passent par la même fonction de lecture ;
  - un compte non nul reste **KO**, même sans témoin E3 ou si la précondition n'est pas remplie : une ligne trouvée est une preuve ;
  - seuls les 0 dépendent du témoin E3 et de la précondition ; la précondition est appliquée telle qu'écrite à 13:11 UTC : si R1 ou R6 n'est pas OK, tous les 0 de R2 à R5, R7 et R8 sont non jugés ;
  - **interprétation soumise au propriétaire** : E3 porte sur les contrôles attendus à 0. Pour les témoins positifs R1 et R6, un compte atteint prouve la collecte dans la fenêtre ; E3 y est affiché, sans effet sur le verdict.
- **Limite de E3 (b), relevée avant le passage** : `ActiveEnterTimestamp` ne donne que le dernier démarrage d'Alloy. Une fenêtre qui commence avant ce démarrage n'est pas jugeable, puisque les redémarrages antérieurs sont inconnus. Si Alloy a démarré au redémarrage des VM du 07/11, vers 11:22 UTC, **R2 et R8 sont prédits non jugés par construction**. R3 à R7 restent jugeables si Alloy n'a pas redémarré depuis. Une autre source d'historique (par exemple `journalctl -u alloy` sur `sc-stockage`) changerait E3 ; c'est au propriétaire de la choisir, elle n'est pas utilisée.
- **Essai hors cluster** (`resultats/evenements-releve-essai.log`) : onze scénarios avec de faux `curl`, `ssh` et `kubectl` ; chaque scénario rend le bilan attendu. Aucun appel à kubectl ; le ssh se limite à `systemctl show -p ActiveEnterTimestamp --value alloy` et `systemctl is-active alloy` ; le mot de passe n'est jamais passé en argument ; aucun mot de passe ni champ `msg` dans le journal ; `resultats/` et `git status` du dépôt sont inchangés. Limites : les réponses de Grafana sont fabriquées sur la forme déjà lue dans le dépôt ; le format de date de systemd est supposé.
- **Effets du passage** : 16 requêtes `POST /api/ds/query` de l'auditeur à Grafana (un témoin E3 et un contrôle par fenêtre), en lecture ; 2 commandes ssh en lecture sur `sc-stockage`. Rien n'est écrit dans le cluster, Loki, Grafana ou les VM. Le journal est local.
- **Pire cas** : quelques requêtes de plus dans les journaux de Grafana et de Loki. Les deux requêtes de R8 portent sur trois jours et chargent un peu `sc-stockage` pendant quelques secondes.

## Additif du 09/11/2026, 15:46 UTC : lecture des témoins positifs tranchée, (a)

Le propriétaire a répondu « (a) compte seul » à « Quelle lecture des témoins positifs R1 et R6 retenez-vous ? ». Les options proposées étaient :
- (a) un compte atteint prouve la collecte dans la fenêtre ; E3 est affiché sans effet sur le verdict ;
- (b) lecture stricte, avec `journalctl -u alloy` comme source de E3 ;
- (c) lecture stricte, sans autre source.

L'interprétation de l'additif de 14:46 UTC devient donc une décision. `evenements.sh` l'applique déjà, et le script n'est pas modifié. R2 et R8 restent prédits non jugés si Alloy a démarré après le début de leur fenêtre.

Cette réponse ne porte que sur cette question. Restent sans réponse à cette heure :
- l'estimation de 4 h ;
- l'accord pour le relevé ;
- le push de `dd12881` et `67a88ee`.

Rien n'est lancé.

## Additif du 09/11/2026, 16:22 UTC : résultat du relevé R1 à R8 des Events, précondition non remplie, constat de collecte

**Accord du propriétaire.** Il a répondu « Oui, lance le relevé » à « Je lance le relevé evenements.sh releve ? ». La proposition citait les effets et le pire cas (additif de 14:46 UTC). Commande lancée de 16:21:25 à 16:21:27 UTC, code 1, journal `resultats/evenements-releve.log`. Seules les 16 requêtes de l'auditeur et les 2 lectures `systemctl` prévues ont été faites ; rien n'a été écrit dans le cluster, Loki, Grafana ou les VM.

**Bilan : R1 OK, R6 KO, R2 à R5, R7 et R8 non jugés.**

| # | Prédit | Mesuré | Lecture |
|---|---|---|---|
| Démarrage d'Alloy | Vers 11:22 UTC le 07/11 | 07/11, 11:22:39 UTC | Tenue |
| R1, témoin positif | Au moins 32 lignes | 32 lignes, de 16:50:00 à 16:53:00 ; témoin E3 : 99 lignes `evenements-k8s` | Tenue ; autant de lignes que d'Events comptés par kubectl |
| R6, témoin positif | Au moins 1 ligne | 0 ligne ; témoin E3 : **aucune ligne `evenements-k8s` dans la fenêtre** | **Réfutée** |
| R2 | 0 | 0, non jugé : Alloy a démarré après le début de la fenêtre | Non jugé, comme prédit à 14:46 UTC |
| R3, R4, R5, R7 | 0 | 0, non jugés : aucune ligne `evenements-k8s` dans leur fenêtre, et précondition non remplie | Non jugés ; **non prédit** : E3 était attendu présent |
| R8 | 0 | 0, non jugé : Alloy a démarré après le début de la fenêtre ; témoin E3 : au moins 1000 lignes (réponse tronquée, lues depuis le 06/11 à 11:00) | Non jugé, comme prédit à 14:46 UTC |

**Constat, mesuré.** Les quatre fenêtres postérieures au démarrage d'Alloy du 07/11 (07/11 à 16:00:56 et 16:21:58, 08/11 à 11:40:44, 09/11 à 09:30:00, cinq minutes chacune) ne contiennent **aucune** ligne `{source="evenements-k8s"}`. La fenêtre du 06/11 de R1 et R2 en contient 99. La fenêtre de R8 va du 06/11 au 09/11 : ses 1000 lignes (réponse tronquée) sont les premières, lues depuis le 06/11 à 11:00 ; elles ne disent rien des jours suivants (corrigé à 16:24 UTC, avant tout push). Borne mesurée : des lignes jusqu'au 06/11 à 16:53:29, aucune dans les fenêtres lues à partir du 07/11 à 16:00:56.

**Pourquoi R6 ne peut pas être un 0 réel.** D'après `durcissement-h5_planifie-0911.log` (relecture du 09/11 à 10:40:42 UTC), le CronJob du scan a créé le Job `scan-sample-app-29903610` à 09:30:00. Son pod a tourné sur `sc-confiance` de 09:30:00 à 09:31:54, et le Job a réussi. Des Events (création du Job, ordonnancement et conteneurs du pod) sont donc attendus dans la fenêtre. Ce point est déduit du fonctionnement de Kubernetes ; ces Events n'ont pas été relus.

**Deux hypothèses, non départagées** (corrigé à 16:24 UTC, avant tout push : une seule était écrite) :
- (H-a) la collecte par Alloy (`loki.source.kubernetes_events`, `evenements.alloy`) ne livre plus rien, alors que le service `alloy` est actif ;
- (H-b) l'API n'enregistre plus d'Events.

Le moment de l'arrêt, sa cause et le composant en faute ne sont pas établis. Recherche locale faite à 16:24 UTC : aucun journal archivé daté d'après le 07/11 à 11:22:39 ne montre un Event présent dans l'API, puisque toutes les lectures kubectl archivées comptent 0. Cette recherche ne départage donc pas les deux hypothèses. Des Jobs `rattrapage` ont été créés le 07/11 à 15:23:00 et 15:24:00 (`test5-essai-hors-etape.log`), ce qui produit normalement des Events ; ces Events n'ont pas été relus. Si l'hypothèse se confirme, l'exigence d'audit (« tout consultable dans Grafana ») n'est pas tenue pour les Events depuis le 07/11, et le chantier doit réparer la collecte avant de modifier les six contrôles.

**Ce que le relevé ne permet pas de dire** :
- l'heure de la dernière ligne `evenements-k8s` ;
- si la collecte s'est arrêtée au démarrage du 07/11 ou plus tard ;
- la cause.

Le relevé ne lisait que des fenêtres de cinq minutes. Un diagnostic demande d'autres lectures, chacune soumise à l'accord du propriétaire.

**Temps** : 1 h 43 min écoulées depuis 14:38:26 UTC, attentes de réponse comprises. L'estimation de 4 h n'est pas validée, et elle ne couvrait pas une réparation de la collecte.

## Additif du 09/11/2026, 16:32 UTC : diagnostic (a) à (d) des Events, prédictions avant le passage

**Accord du propriétaire.** Il a répondu « Oui, (a) à (d) » à « Je lance le diagnostic en lecture seule, (a) à (d) ? ». La proposition citait les effets et le pire cas.

**Commande** : `mise exec -- poc/bricks/08c-durcissement/evenements.sh diagnostic`, journal `resultats/evenements-diagnostic.log`.

**Effets du passage** : 6 requêtes de l'auditeur à travers Grafana, en lecture seule, et 2 commandes par ssh sur `sc-stockage` : `curl` de l'API locale d'Alloy (`127.0.0.1:12345`, route `/api/v0/web/components/<id>` lue dans le source au tag v1.21.3) et `date -u`. Rien n'est écrit et rien n'est redémarré.

**Essai hors cluster** : `resultats/evenements-diagnostic-essai.log`.

**Ce qui est affiché** :
- le journal d'Alloy n'est affiché que réduit à `level`, `msg`, `component_id` et `err` ;
- une erreur qui contient « jeton » ou « token » n'est affichée que par sa classe ;
- les lignes du journal de `sc-stockage` sont comptées, jamais affichées.

**Prédictions, avant le passage :**

| # | Lecture | Prédit | Confiance |
|---|---|---|---|
| (a) | Dernière ligne `evenements-k8s` après le 06/11 à 16:53:29 | Entre le 06/11 à 16:53:29 et le 07/11 à 11:22:39 : la collecte s'est arrêtée à l'extinction des VM du 07/11, et pas plus tard | Moyenne |
| (a) | Lignes `evenements-k8s` depuis le démarrage d'Alloy (07/11, 11:22:39) | 0 | Moyenne |
| (b) | Lignes du journal de `sc-stockage` dans la fenêtre de R6 | Au moins 1 : Alloy écrit encore dans Loki, seul le composant des Events est en cause, ce qui écarte la panne de toute la sortie (H-a restreinte au composant) | Haute |
| (c) | Lignes d'`alloy.service` depuis le 07/11 à 11:00 | Au moins 1 (messages de démarrage) | Haute |
| (c) | Lignes du composant des Events | Au moins la ligne « watching events for namespace » au démarrage. Erreur éventuelle : classe inconnue, candidats « failed to start informers », refus de connexion à l'API au démarrage, `Unauthorized` | Basse |
| (d) | Santé du composant | `healthy` : le source ne remonte pas d'erreur de l'informer dans la santé | Basse |
| (d) | `last_event_timestamp` | Égal, à la seconde près, à la dernière ligne lue en (a). Une valeur postérieure à l'heure de la VM soutiendrait l'hypothèse d'une position enregistrée en avance, qui écarte les Events sans erreur | Moyenne |

**Ce que le diagnostic ne dira pas** :
- si l'API enregistre encore des Events (H-b) : seule l'option (e), non accordée, le dirait ;
- la cause, si le journal d'Alloy est muet.

## Additif du 09/11/2026, 16:33 UTC : résultat du diagnostic (a) à (d), cause de l'arrêt de la collecte des Events

Commande lancée de 16:32:20 à 16:32:21 UTC, code 0, journal `resultats/evenements-diagnostic.log`. Seules les 6 requêtes de l'auditeur et les 2 commandes ssh prévues ont été faites, sans rien écrire ni redémarrer.

| # | Prédit | Mesuré | Lecture |
|---|---|---|---|
| (a) dernière ligne | Entre le 06/11 à 16:53:29 et le 07/11 à 11:22:39 | 07/11 à 11:20:08 (`Job horodatage-29900840 Completed`) | Tenue |
| (a) lignes depuis le démarrage | 0 | 0 | Tenue |
| (b) journal de `sc-stockage`, fenêtre de R6 | Au moins 1 | Au moins 1000 (réponse tronquée) ; `evenements-k8s` : 0 | Tenue : Alloy écrit encore dans Loki |
| (c) lignes d'`alloy.service` | Au moins 1 | 77 depuis le 07/11 à 11:00 | Tenue |
| (c) composant des Events | Ligne de démarrage et erreur de classe inconnue | 11:20 : « stopping watcher for events » (arrêt des VM) ; 11:22 : « watching events for namespace », puis `level=error` « event watcher exited with error », `failed to configure informers: failed to get server groups: Get "…`, puis « stopping watcher for events » | Tenue en partie : la fin du message, qui porte la classe (adresse, refus, délai), n'a pas été lue. Elle n'est pas coupée à 200 caractères, comme écrit d'abord : l'extraction `err="[^"]*"` du script s'arrête au premier guillemet échappé, `Get \"`, vers le 75ᵉ caractère. Le masque `jeton|token` n'a porté que sur ce début ; la suite n'a pas été affichée, sans fuite (corrigé à 17:00 UTC, avant tout push) |
| (d) santé | `healthy` | `healthy`, « started component », depuis le 07/11 à 11:22:41 | Tenue |
| (d) `last_event_timestamp` | Égal à (a) | 2026-11-07T11:20:08Z, égal à (a) ; heure de la VM à la lecture : 16:32:21 | Tenue : position en retard, pas en avance ; l'hypothèse d'une position en avance est écartée |

**Cause, mesurée.** Hypothèse (H-a). Au démarrage d'Alloy, le 07/11 à 11:22, l'observateur d'Events a échoué une fois, sur la découverte des groupes de l'API (`failed to get server groups`). Il s'est ensuite arrêté. Depuis, le composant reste `healthy` et n'a livré aucune ligne. Ce point est mesuré.

**Ce qui est lu dans le source d'Alloy v1.21.3, et non mesuré.**
- `eventController.Run` journalise l'erreur et rend la main.
- Le contrôleur n'est recréé que par `reconcile`. Celui-ci n'est appelé que par `Update` : changement de configuration ou rechargement.
- Rien ne relance donc l'observateur avant un rechargement ou un redémarrage d'Alloy, et la santé du composant n'en dit rien. C'est une panne silencieuse.

Explication probable du premier échec, déduite et non vérifiée : l'API de `sc-confiance` n'était pas encore prête quand Alloy de `sc-stockage` a redémarré, deux minutes après l'arrêt.

**Ce qui reste non établi** :
- la classe exacte de l'erreur (fin du message non lue, voir la correction de 17:00 UTC dans le tableau). Elle décide du remède : un refus de connexion ou un délai se répare par un redémarrage d'Alloy ; `Unauthorized`, `x509` ou une erreur de jeton feraient échouer le redémarrage de la même façon ;
- (H-b), l'enregistrement par l'API : il n'a pas été lu, mais il n'est plus nécessaire pour expliquer l'absence de lignes ;
- pourquoi aucune alerte n'a signalé cette source muette depuis le 07/11 : non relu.

**Recherche publique** (deux requêtes sur `grafana/alloy`). L'issue 233, close en 2024, est voisine : délai de démarrage de l'observateur sur un gros volume d'Events. Aucune issue sur l'absence de relance n'a été trouvée par ces deux requêtes.

**Conséquences.**
- Aucun Event n'est consultable dans Grafana du 07/11 à 11:20:08 jusqu'à une relance. Ceux de cette période qui ont expiré de l'API (durée de vie d'une heure) sont perdus.
- Si l'explication par l'API pas encore prête se confirme, le même arrêt se reproduirait à chaque redémarrage de `sc-stockage` qui précède la disponibilité de l'API, par exemple à chaque rejeu ou redémarrage des VM (formulation rendue conditionnelle à 17:00 UTC, avant tout push).

**Lectures locales, 17:00 UTC, sans accès au cluster.**
- Le jeton du collecteur vient du Secret `alloy-evenements-jeton`, de type `kubernetes.io/service-account-token` (`19b-journalisation/cluster/evenements.yaml`, `journalisation.sh:288`), donc sans durée de vie fixée. Valeur non lue.
- L'alerte `SourceMuette` (`19-observabilite/config/regles/alertes.yml`) ne surveille que le relais de `sc-confiance` et `sc-build` et le journal de `sc-stockage`, pas `evenements-k8s`. C'est pourquoi aucune alerte n'a signalé la panne.
- Les pertes d'un redémarrage d'Alloy de `sc-stockage`, qui porte aussi le relais, n'ont jamais été mesurées : L6 a mesuré les pertes du relais gRPC, pas d'un redémarrage.

**Observation sur E3.** La moitié « Alloy non redémarré » du témoin E3 n'aurait rien détecté : `alloy` était actif, jamais redémarré, et le composant restait `healthy`. Seule la condition « au moins une ligne `evenements-k8s` dans la fenêtre » a révélé la panne. Pour la modification des six contrôles, un témoin fondé sur la présence de lignes est nécessaire ; l'état systemd et la santé du composant ne suffisent pas. La décision sur E3 reste au propriétaire.

**Temps** : 1 h 55 min écoulées depuis 14:38:26 UTC, attentes de réponse comprises.

## Additif du 09/11/2026, 17:01 UTC : classe de l'erreur lue, refus de connexion à l'API

**Accord du propriétaire** : « Oui, relis la classe », en réponse à « Je relis la classe de l'erreur (evenements.sh classe, une requête) ? ».

**Passage** : commande lancée à 17:01:41 UTC, code 0, journal `resultats/evenements-classe.log`. Une seule requête de l'auditeur, sur le 07/11 de 11:00 à 12:00 ; rien n'a été écrit.

**Mesuré.** Les 8 lignes sont celles du diagnostic. L'erreur entière est :

`failed to configure informers: failed to get server groups: Get "https://192.168.161.11:6443/api": dial tcp 192.168.161.11:6443: connect: connection refused`

Sa classe est **`connection refused`**. Au démarrage d'Alloy de `sc-stockage`, le 07/11 à 11:22, rien n'écoutait encore sur le port 6443 de l'API de `sc-confiance`. L'explication donnée à 16:33 UTC (« API pas encore prête ») est donc mesurée pour ce démarrage. Ce n'est ni une erreur de jeton ni une erreur de certificat.

**Conséquences, écrites avant toute action.**
- D'après le source, un redémarrage d'Alloy recrée l'observateur. L'API répond aujourd'hui, comme le montrent les lectures kubectl de la journée. Un redémarrage devrait donc rétablir la collecte. C'est une prédiction, non vérifiée.
- Si rien ne change, l'arrêt se reproduira à chaque démarrage d'Alloy de `sc-stockage` antérieur à l'écoute de l'API.

## Additif du 09/11/2026, 17:05 UTC : redémarrage d'Alloy de sc-stockage, prédictions avant l'action

**Accord du propriétaire.** Réponse : « Oui, redémarre Alloy ». Question posée : « Je redémarre Alloy sur sc-stockage puis je vérifie les nouvelles lignes d'Events ? ». La proposition citait les effets et le pire cas :
- effets : interruption de quelques secondes de toute la collecte de `sc-stockage`, relais compris, et reprise depuis la position de 11:20:08 ;
- pire cas : perte, jamais mesurée, de lignes relayées pendant l'interruption, ou nouvel échec.

**Commandes**
- `mise exec -- poc/bricks/08c-durcissement/evenements.sh redemarrage` : `sudo systemctl restart alloy` sur `sc-stockage`, avec le démarrage relevé avant et après.
- Quelques minutes plus tard, `evenements.sh verification`, en lecture seule. Elle fait 3 requêtes de l'auditeur et 2 commandes ssh : `ActiveEnterTimestamp` et l'API locale d'Alloy.
- Essai hors cluster : additif de 17:05 UTC de `resultats/evenements-diagnostic-essai.log`.

**Prédictions, avant l'action :**

| # | Prédit | Confiance |
|---|---|---|
| P1 | `ActiveEnterTimestamp` postérieur à celui du 07/11, service `active` | Haute |
| P2 | Journal d'`alloy.service` depuis le redémarrage : « watching events for namespace », sans « event watcher exited with error » ni « failed to start informers » | Haute : l'API répond aujourd'hui |
| P3 | Santé `healthy` ; `last_event_timestamp` postérieur au 07/11 à 11:20:08 | Haute pour la santé, moyenne pour la position (il faut au moins un Event postérieur à la position, encore présent dans l'API) |
| P4 | Au moins 1 ligne `evenements-k8s` entre le redémarrage moins 65 min et la vérification. Au démarrage, l'observateur relit les Events encore présents dans l'API (durée de vie d'une heure) ; leurs lignes portent leur propre horodatage, antérieur au redémarrage. | Moyenne : (H-b), l'enregistrement par l'API, n'a pas été lu |
| P5 | Lignes horodatées après le redémarrage : affichées, non prédites | — |

**Verdict « collecte rétablie »** : P2 et P4 tenues.

**Limites**
- Loki peut refuser une ligne trop en retard sur la plus récente de son flux. Cette limite n'a pas été relue dans la configuration de la 19b, et une partie des Events relus pourrait manquer.
- Les Events expirés depuis le 07/11 restent perdus.
- Les pertes du relais pendant le redémarrage ne sont pas mesurées par ces étapes.

## Additif du 09/11/2026, 17:08 UTC : Alloy de sc-stockage redémarré, collecte des Events rétablie

**Redémarrage** : 09/11 à 17:05:19 UTC (`resultats/evenements-redemarrage.log`). Alloy était actif depuis le 07/11 à 11:22:39 ; il est actif depuis le 09/11 à 17:05:19, état `active`. Seul `sudo systemctl restart alloy` a été lancé, aucune autre modification.

**Vérification** : à 17:08:44 UTC, en lecture seule (`resultats/evenements-verification.log`).

| # | Prédit | Mesuré | Lecture |
|---|---|---|---|
| P1 | Démarrage postérieur à celui du 07/11, service `active` | 17:05:19, `active` | Tenue |
| P2 | « watching events for namespace » sans erreur | 5 lignes du composant depuis 17:05:19 : démarrage de l'observateur, aucune erreur | Tenue |
| P3 | Santé `healthy`, position postérieure au 07/11 à 11:20:08 | `healthy` depuis 17:05:19.96 ; `last_event_timestamp` 2026-11-09T17:08:07Z | Tenue |
| P4 | Au moins 1 ligne entre 16:00:19 et la vérification | 948 lignes, de 16:05:07 à 17:08:07 | Tenue |
| P5 | Affiché | 45 lignes horodatées après le redémarrage | — |

**Verdict : collecte des Events rétablie.** P2 et P4 sont tenues.

**Ce que la vérification établit en plus**
- L'API enregistre des Events : l'hypothèse (H-b) est écartée pour la période relue, depuis 16:05.
- Les Events de `horodatage` reviennent chaque minute.
- Chaque Event de pod affiché paraît en double (par exemple `Started` deux fois pour un même pod). Ce point n'est pas interprété : deux conteneurs par pod, ou deux lignes par Event, sans vérification.

**Ce qui est perdu.** Les Events du 07/11 à 11:20:08 au 09/11 vers 16:05 ne sont pas dans Loki. Ils ont expiré de l'API, dont la première ligne relue date de 16:05:07, et ne sont pas récupérables.

**Pertes du relais pendant le redémarrage** : non mesurées.

**Ce qui reste à décider par le propriétaire**
- Le remède durable : alerte sur l'absence de lignes `evenements-k8s`, ordre de démarrage d'Alloy après l'API, issue chez Alloy (action publique). Sans lui, la panne reviendra au prochain démarrage d'Alloy de `sc-stockage` antérieur à l'écoute de l'API.
- Le périmètre et l'estimation du chantier.
- La suite d'E4 : modifier les six contrôles, et choisir leur témoin.

**Temps** : 2 h 30 min écoulées depuis 14:38:26 UTC, attentes de réponse comprises.
