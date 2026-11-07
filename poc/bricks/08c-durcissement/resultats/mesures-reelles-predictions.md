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
