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
