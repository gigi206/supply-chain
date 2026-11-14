# Brique 07a, G7 : replanification de la première suppression réelle de Zot après S5b (préparée le 12/11/2026 à partir de 14:46:25 UTC, NON LANCÉE)

Décisions du propriétaire du 12/11/2026 : « Oui, avance S5b », qui avance S5b et replanifie G7 ; puis « Oui, prépare-la », pour cette préparation. **Rien n'est lancé, et la tâche planifiée n'est pas modifiée.**

## Pourquoi

La tâche `supply-chain-g7-premiere-suppression` (21/11/2026, 16:00 UTC) suppose le Zot démarré le 06/11 à 15:14:56 UTC et son plus ancien blob de scan du 06/11, 15:39 UTC. S5b recrée sc-stockage, donc Zot : après lui, ses chiffres et sa prédiction ne valent plus.

## Procédure, chaque point sur accord

1. **Au lancement de S5b**, sur le même accord : désactiver la tâche du 21/11 (`enabled: false`), sans la supprimer.
2. **Après S5b, et après le premier passage de `periodique` de S6a** s'il a lieu dans les 24 h : lancer [`g7-replanifier.sh releve`](../g7-replanifier.sh). L'étape est en lecture seule sur sc-stockage. Elle relève :
   - le démarrage de `zot.service` ;
   - la configuration de rétention et de gc, comparée à `08-trust-plane/stockage/zot.json` ;
   - le nombre et les dates des blobs de chaque dépôt de `builds/scan/**` et de `vulndb/grype`.

   Elle calcule ensuite la première suppression possible, le balayage qui la suit, et l'heure proposée pour la tâche (balayage + 45 min).
3. **Écrire la nouvelle prédiction** d'après ce relevé, dépôt par dépôt, et la commiter avant la date.
4. **Replanifier la tâche** à l'heure calculée, avec la consigne réécrite ci-dessous, puis la réactiver.

Le dépôt de scan du deb, `builds/scan/sample-app-deb`, est créé par `periodique` de S6a.
- Si son premier scan arrive plus de 24 h après le plus ancien blob de `builds/scan/**`, il aura moins de 336 h au balayage calculé, donc aucune décision.
- S'il arrive plus tôt, une décision devient possible pour lui au même balayage. La nouvelle prédiction le tranchera d'après le relevé.

## Vérifié à sec

- `bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement.
- **Calcul rejoué sur les chiffres du 06/11** (démarrage 15:14:56 UTC, plus ancien blob 15:39 UTC) : première suppression possible le 20/11 à 15:39:00 UTC, balayage le 21/11 à 15:14:56 UTC, tâche à 15:59:56 UTC. C'est le plan du 06/11 (balayage vers 15:15 UTC, tâche à 16:00 UTC).
- **Rétention relue dans `zot.json`** :
  - `delay` 336h, `gcInterval` 24h, `gcDelay` 1h ;
  - `vulndb/grype` : 11 tags les plus récents gardés, non tagués supprimés ;
  - `builds/scan/**` : referrers supprimés, non tagués gardés ;
  - le reste : rien de supprimé.

**Corrigé à sec le 12/11/2026 à partir de 14:50:52 UTC, avant tout accord, sur relecture du conseiller.** Deux défauts du script :
- `find … 2>/dev/null` sur un dossier absent rendait un code non nul, et `set -e` arrêtait l'étape sans message. Chaque dossier est maintenant testé : absent, il est signalé (`ABSENT`) ; un `find` en échec donne un KO.
- `/var/lib/zot` était écrit en dur. Le dossier racine est maintenant lu dans la configuration de la VM, et comparé à celle du dépôt avec les champs de rétention.

Essai hors cluster, VM et Zot simulés ([journal](g7-replanifier-essai-local.log), [banc](g7-replanifier-essai-local.sh)) : dépôt absent signalé et calcul conforme (code 0), `find` en échec refusé (code 1), dossier racine différent du dépôt refusé (code 1). Le relevé sur la vraie VM n'est pas fait.

**Corrigé à sec le 12/11/2026 à partir de 15:52:35 UTC, avant tout accord, sur relecture du conseiller.** Le banc simulait `systemctl` par une date fixe, et ne voyait donc pas ce défaut :
- pour une unité jamais démarrée, `systemctl show … -p ActiveEnterTimestamp --value` rend une chaîne vide (vérifié sur l'hôte, systemd 259, avec une unité absente ; `ActiveState` y vaut `inactive`) ;
- `date -u -d ''` rend alors minuit du jour, avec le code 0 (vérifié sur l'hôte : `2026-11-12T00:00:00Z`). Le calcul aurait été faux, sans message.

Le script exige maintenant que `zot.service` soit `active`, et refuse un démarrage vide ou illisible. Banc rejoué le même jour ([journal](g7-replanifier-essai-local.log)) : essais 1 à 3 inchangés ; démarrage vide refusé (essai 4, code 1) ; Zot inactif refusé (essai 5, code 1). `bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement (`-S warning`). Le relevé sur la vraie VM n'est toujours pas fait.

**Corrigé à sec le 12/11/2026 à partir de 16:13:25 UTC, avant tout accord, sur relecture du conseiller.** Si la première suppression possible tombait au plus tard au démarrage de Zot (plus ancien blob + 336 h ≤ démarrage, par exemple après un redémarrage de sc-stockage), le calcul rendait k ≤ 0, donc un balayage au démarrage ou avant, sans message. Qu'un balayage ait lieu au démarrage n'a jamais été mesuré : le script refuse maintenant ce cas, en affichant les deux dates.

Banc rejoué le même jour ([journal](g7-replanifier-essai-local.log)) : essais 1 à 5 identiques au journal précédent, hors ligne d'en-tête ; première suppression possible égale au démarrage refusée (essai 6, code 1) ; une seconde plus tôt, acceptée avec un balayage à démarrage + 1 × 24 h (essai 6, code 0). Un premier passage du banc, à 16:13:30 UTC, avait échoué à cause du banc lui-même : la date simulée portait un nom de jour en français (« ven. »), que le script, en `LC_ALL=C`, refusait comme illisible. Le banc fixe maintenant `LC_ALL=C`. Si `systemctl` rendait sur la VM un nom de jour en français, il serait refusé de même, sans calcul faux ; la langue de la VM n'est pas relevée, et les autres langues ne sont pas essayées. `bash -n` passe, et shellcheck 0.11.0 ne relève aucun avertissement (`-S warning`). Le relevé sur la vraie VM n'est toujours pas fait.

## Prédictions du relevé

| # | Prédiction | Confiance |
|---|---|---|
| G1 | La configuration de rétention et de gc de la VM est identique à celle du dépôt | Haute : posée par `stockage.sh` depuis `zot.json` |
| G2 | Zot a démarré pendant S5b, le 13/11, et pas depuis | Moyenne : un redémarrage de sc-stockage le déplacerait |
| G3 | `builds/scan/sample-app` a ses premiers blobs pendant S5b (scan de G4 du rejeu), puis un par jour à 09:30 UTC (CronJob) | Moyenne |
| G4 | Avec S5b le 13/11, la première suppression possible tombe le 27/11, et la tâche proposée le 27/11 ou le 28/11, selon l'heure du balayage | Moyenne : calcul, jamais mesuré |

## Consigne réécrite de la tâche (brouillon, à compléter par le relevé)

Les champs entre chevrons viennent du relevé du point 2. Le reste reprend la consigne actuelle, dont les accès et les règles de lecture seule sont inchangés.

> Contexte chiffré, relevé le <date du relevé> après S5b : Zot a redémarré le <démarrage>, `gcInterval` vaut 24 h, `retention.delay` vaut 336 h. Le plus ancien blob de `builds/scan/**` date du <plus ancien> (<dépôt>). La première suppression possible tombe donc au premier balayage après le <plus ancien + 336 h>, attendu le <balayage>, si Zot n'a pas redémarré. Ce calcul n'a jamais été mesuré : vérifie-le d'abord (`systemctl show zot.service -p ActiveEnterTimestamp`). Si le balayage n'a pas encore eu lieu, dis-le et arrête-toi.
>
> Prédit, dépôt par dépôt :
> - `builds/scan/sample-app` : seuls les scans de plus de 14 jours au balayage (<nombre>) ;
> - `builds/scan/essai-scan` : <témoins de G6 rejoués par S5b, s'il y en a> ;
> - `builds/scan/sample-app-deb` : <aucune décision si son plus ancien blob a moins de 14 jours au balayage ; sinon, le nombre> ;
> - `vulndb/grype` : 11 tags au plus ;
> - `builds/vsa/**`, `amont/**` et `builds/**` hors scan : intacts, aucune décision.

## Limites

- Les dates viennent de la date de modification des blobs, comme pour le calcul du 06/11. La règle de Zot porte sur l'âge des manifestes : un écart entre les deux décalerait la première décision.
- Les balayages sont supposés tomber à « démarrage de Zot + k × 24 h ». C'était l'hypothèse du 06/11 ; elle n'a jamais été mesurée.

## Note datée de 2026-11-14T20:41:05Z : avant le relevé, après S5b (rien n'est réécrit)

- **Point 1 fait** : la tâche `supply-chain-g7-premiere-suppression` est désactivée (`enabled: false`, relu ce jour dans la liste
  des tâches planifiées), non supprimée.
- **Condition du point 2 remplie** : S5b est terminé (13/11, 15:51:47 UTC, `2cec0df`) ; `periodique` de S6a n'a pas tourné, et
  plus de 24 h ont passé. Le relevé peut donc se faire sans l'attendre.
- **Prédictions ajoutées** (relues dans les journaux de S5b, pas dans Zot) :
  - **G5.** `builds/scan/sample-app-deb` n'a aucun blob : S6a n'a pas tourné (le dépôt n'apparaît pas dans la liste par dépôt).
    Confiance haute.
  - **G6.** `builds/scan/essai-scan` a des blobs du 13/11, écrits par `g6_temoins` de la 07a pendant S5b, à partir de 12:48:42 UTC
    (`08-trust-plane/resultats/rejeu-s5b-plateforme-ctl.log`). Confiance haute.
  - **G3 précisée** : le plus récent blob de `builds/scan/sample-app` date du 14/11, vers 09:30 UTC (CronJob du jour). Confiance
    moyenne : le passage du 14/11 n'a pas été relu.
- Le relevé lit `/etc/zot/config.json` par sudo sur la VM et ne garde que les champs de rétention et de gc (sans secret).

## Résultat du relevé (point 2) (note de 2026-11-14T20:43:08Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance g7-replanifier.sh releve (lecture seule sur sc-stockage) ? ». De 20:42:30 à 20:42:31 UTC, code 0
([journal](g7-replanifier-releve.log)).
- **G1 tenue** : rétention et gc de la VM identiques au dépôt (`/var/lib/zot`, `delay` 336h, `gcInterval` 24h).
- **G2 tenue** : `zot.service` démarré le 13/11 à 12:17:25 UTC, pendant S5b, et actif.
- **G3 tenue** (forme précisée) : premiers blobs de `builds/scan/sample-app` le 13/11 à 12:45:07 UTC ; ceux du CronJob du 14/11 à
  09:31:51 et 09:31:52 UTC (lu dans la liste brute du relevé, `$W/g7-replanifier/blobs.txt`, hors du dépôt).
- **G4 tenue** : première suppression possible le 27/11 à 12:41:47 UTC ; balayage le 28/11 à 12:17:25 UTC (démarrage + 15 × 24 h) ;
  **tâche proposée le 28/11/2026 à 13:02:25 UTC**. Calcul, pas une mesure.
- **G5 tenue** : `builds/scan/sample-app-deb` absent de la liste.
- **G6 tenue** : `builds/scan/essai-scan`, 33 blobs, le plus ancien le 13/11 à 12:49:10 UTC.
- **Non prédit** : un dépôt `builds/scan/essai-07a` (3 blobs, le plus ancien le 13/11 à 12:41:47 UTC), écrit pendant S5b. **C'est lui
  qui fixe la date** : son plus ancien blob est le plus ancien de `builds/scan/**`. Son origine dans S5b n'est pas encore relue.
- **Non prédit, mesuré dans la liste brute** : le « plus récent » de chaque dépôt (14/11, 20:30:53 UTC) est le blob vide `{}`
  (`sha256:44136fa3…`), et lui seul. 20:30:53 UTC tombe pendant `pousser_vsa` de la 06 (20:30:50 à 20:30:55 UTC), qui a poussé ce
  même blob dans `builds/vsa/sample-app-deb`. **Le push d'un blob a donc changé la date de modification du blob de même empreinte
  dans les autres dépôts.** Le mécanisme (fichier partagé par la déduplication de Zot, ou date réécrite) n'est pas vérifié.
  Conséquence pour la limite déjà écrite : la date de modification d'un blob partagé n'est pas son âge. Le calcul ne s'en sert pas
  ici (le plus ancien blob, `7af558b5…`, n'est pas `{}`), mais un « plus récent » lu de cette façon peut être faux.
- Suite (points 3 et 4) : prédiction et consigne de la tâche réécrites d'après ce relevé, puis tâche replanifiée et réactivée, chacun
  sur accord.

## Point 3 : prédiction et consigne réécrites d'après le relevé (note de 2026-11-14T20:45:57Z, « Oui, prépare-la » ; rien n'est réécrit au-dessus)

**Rien n'est modifié dans la tâche planifiée** : elle reste désactivée, avec l'ancienne consigne, jusqu'au point 4 (accord à part).

### Origine de `builds/scan/essai-07a`, relue
`plateforme.sh g1_droits` de la 07a (journal `08-trust-plane/resultats/rejeu-s5b-plateforme-ctl.log`, l. 990) : `oras push` d'un
artefact d'essai **sans sujet**, poussé par digest, **sans tag**, par `poc-scan`. Ce n'est pas un referrer, et la règle de
`builds/scan/**` ne supprime que les referrers (`deleteUntagged: false`). **Aucune décision attendue pour lui** (confiance moyenne :
lecture du script, pas de la VM). Il fixe le « plus ancien blob » du relevé sans être supprimable.
**Correction du raisonnement, pas de la date** : le plus ancien *referrer* est le premier scan de `builds/scan/sample-app`
(13/11, 12:45:07 UTC). Première décision possible **pour un referrer de `builds/scan/**`** le 27/11 à 12:45:07 UTC, au lieu de 12:41:47 ; **même
balayage** (28/11, 12:17:25 UTC) et **même heure proposée** (28/11/2026, 13:02:25 UTC).

### `vulndb/grype` décide avant le 28/11 (relu avant le commit, sur relecture du conseiller)
Le retrait d'un tag se fait au compte (11 les plus récents), sans attendre `retention.delay` (`g7-predictions.md`, l. 14, et sa
mesure du 06/11, l. 39 et 60 : tag retiré alors que la base était plus jeune que le délai). Avec une base et un tag par jour
depuis le 13/11, le 12ᵉ tag arrive le 24/11 vers 08:11 UTC : le balayage du 24/11 vers 12:17 UTC retire le tag du 13/11, puis
un tag par balayage. **Les premières décisions réelles du nouveau Zot sont donc attendues le 24/11, dans `vulndb/grype`** ; le
28/11 reste la date des premières suppressions de referrers de scan (G7 proprement dite) et des premières bases effacées.

### Prédictions du balayage du 28/11 (vers 12:17 UTC), dépôt par dépôt
Hypothèses, jamais mesurées : balayages à démarrage de Zot + k × 24 h ; âge d'un manifeste lu sur la date de son blob, comme le
06/11 (`g7-predictions.md`, l. 12) ; Zot non redémarré d'ici là ; CronJob de scan et timer de la base quotidiens jusqu'au 28/11.

| # | Dépôt | Prédit | Confiance |
|---|---|---|---|
| H1 | `builds/scan/sample-app` | **3 referrers supprimés** : les scans du 13/11 (12:45 et 12:47 UTC, rejeu) et du 14/11 (09:31 UTC) ; ceux du 15/11 au 28/11 restent | Moyenne : une paire de blobs par scan (manifeste et bundle) lue dans le relevé |
| H2 | `builds/scan/essai-scan` | Tous ses referrers supprimés (témoins de G6 du 13/11, 12:49 UTC) : **16**, d'après 32 blobs hors `{}` lus par paires comme en H1 (même nombre que le 06/11) | Moyenne |
| H3 | `builds/scan/essai-07a` | Aucune décision (artefact sans sujet ni tag) | Moyenne |
| H4 | `builds/scan/sample-app-deb` | Absent, ou aucune décision (tout scan du deb sera postérieur au 14/11, 12:17:25 UTC) | Haute |
| H5 | `vulndb/grype` | **Cumul au 28/11** : 11 tags ; 5 tags retirés, un par balayage du 24/11 au 28/11 (13/11 au 17/11). **Balayage du 28/11 seul** : 1 tag retiré (17/11) ; bases du 13/11 et du 14/11 effacées (plus de 336 h) ; bases du 15/11 au 17/11 lisibles par digest | Moyenne : suppose une base et un tag par jour, comme le 06/11 (`g7-predictions.md`, l. 39) |
| H6 | `builds/vsa/**`, `builds/**` hors scan, `amont/**`, `horodatage/**`, `vulndb/essai-07a` | Aucune décision | Haute : règle `**` sans suppression |
| H7 | Blob vide `sha256:44136fa3…` | Toujours lisible après le gc dans `builds/vsa/sample-app`, `builds/vsa/sample-app-deb` et `builds/scan/sample-app` | Moyenne : la déduplication et le gc n'ont jamais été observés ensemble sur un blob partagé |

### Consigne réécrite de la tâche (à poser au point 4, telle quelle)

> Réponds en français. Dépôt : /home/gigi/Documents/git/github/gigi206/supply-chain, branche claude/focused-fermi-ul5y20. Contexte : brique 07a du PoC supply-chain, G7, décision D7 (b). Cluster sous RKE2, rebâti par S5b le 13/11/2026. Lis d'abord poc/bricks/07a-sbom-grype/resultats/g7-replanification.md (sections « Résultat du relevé (point 2) » et « Point 3 »), puis g7-predictions.md.
>
> Tout est EN LECTURE SEULE : ne modifie ni Zot, ni le cluster, ni les VM, ne pousse rien, n'installe rien, ne committe rien. Tu peux seulement écrire poc/bricks/07a-sbom-grype/resultats/g7-premiere-suppression.log. N'y archive aucune réponse de Grafana : seulement des comptes. Remplace toute ligne contenant « jeton » ou « token » par un marqueur visible « [ligne masquée : motif jeton|token] ». Si quelque chose échoue, dis-le, ne corrige rien.
>
> Contexte chiffré, relevé le 14/11/2026 à 20:42 UTC : Zot a démarré le 13/11/2026 à 12:17:25 UTC ; `gcInterval` vaut 24 h, `retention.delay` 336 h. Le plus ancien referrer de builds/scan/** date du 13/11 à 12:45:07 UTC (builds/scan/sample-app) ; builds/scan/essai-07a, plus ancien (12:41:47 UTC), n'est pas un referrer. La première suppression possible d'un referrer de scan tombe donc au premier balayage après le 27/11 à 12:45:07 UTC, attendu le 28/11 vers 12:17:25 UTC si Zot n'a pas redémarré. Ce calcul n'a jamais été mesuré. Vérifie d'abord cette hypothèse (`systemctl show zot.service -p ActiveEnterTimestamp`). Si le balayage n'a pas encore eu lieu, dis-le et arrête-toi là. Dans vulndb/grype, des tags ont dû être retirés dès le balayage du 24/11 (retrait au compte, sans délai) : compte les décisions balayage par balayage depuis le démarrage de Zot.
>
> Accès : Zot https://192.168.161.13:5000/v2 en anonyme, CA ~/.cache/supply-chain-poc/08/pki/ca-poc.crt. SSH : `ssh -i ~/.cache/supply-chain-poc/08/ssh/id_ed25519 -o UserKnownHostsFile=$HOME/.cache/supply-chain-poc/08/ssh/known_hosts -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10 poc@192.168.161.13 ...`, sudo disponible. Journal : `sudo journalctl -u zot.service --since '2026-11-13 12:00:00' -o cat` (toute la vie de ce Zot, pour compter par balayage). Audit : /var/log/zot/audit.log. Image réelle : builds/sample-app@sha256:3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5 ; deb : builds/sample-app-deb@sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e. Grafana : https://192.168.161.13:3001/api/ds/query, compte auditeur, mot de passe dans ~/.cache/supply-chain-poc/08/secrets/grafana-auditeur (jamais affiché).
>
> À vérifier, en comparant à H1 à H7 de g7-replanification.md :
> 1. Image réelle et deb, avec leurs .sig et .att, lisibles (HEAD avec Accept: application/vnd.oci.image.manifest.v1+json, 200 attendu) ; VSA de builds/vsa/sample-app et builds/vsa/sample-app-deb lisibles (referrers).
> 2. Décisions de suppression, comptées par balayage, par dépôt et par raison, comparées à H1 à H6 (H5 : cumul du 24/11 au 28/11 et balayage du 28/11 séparés).
> 3. Aucun blob manquant : sur les manifestes qui restent de builds/scan/sample-app, sur la base la plus récente de vulndb/grype, et blob sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a lisible dans builds/vsa/sample-app, builds/vsa/sample-app-deb et builds/scan/sample-app (H7).
> 4. Les décisions de suppression lisibles par l'auditeur dans Grafana (comptes seulement).
> 5. La porte n'est pas à relancer : ne crée aucun Job. Relève seulement que le CronJob scan-sample-app réussit toujours et le nombre de referrers (KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml).
> 6. Place libre sur sc-stockage et sc-confiance.
>
> Archive les résultats dans g7-premiere-suppression.log. Rapport court au propriétaire : résultat d'abord, écarts à la prédiction nommés, ce qui reste non vérifié. Toute correction demande son accord.

### Question ouverte avant le point 4
L'hypothèse « balayage à démarrage + k × 24 h » est mesurable dès maintenant : un balayage a dû passer le 14/11 vers 12:17 UTC.
Une lecture du journal de `zot.service` (lecture seule, accord nommé) la confirmerait ou la réfuterait avant de fixer `fireAt`.

### Point 4, à faire sur accord
Remplacer la consigne de `supply-chain-g7-premiere-suppression` par celle ci-dessus, `fireAt` au **28/11/2026 à 13:02:25 UTC**,
réactiver la tâche, puis relire la liste des tâches.

## Balayage du 14/11 relu dans le journal de Zot (note de 2026-11-14T20:49:33Z ; rien n'est réécrit)
« Oui, lis-le » à « Je lis le journal de zot.service pour vérifier le balayage du 14/11 ? ». Lecture seule à 20:48:36 UTC
([résumé](g7-balayage-14-11.log) ; lignes brutes hors du dépôt).
- **Hypothèse « démarrage + k × 24 h » réfutée pour l'heure de début.** Le premier balayage a commencé le 14/11 à **12:45:50 UTC**,
  soit 24 h 28 min 25 s après le démarrage (12:17:25), et fini à **13:22:29 UTC** (36 min 39 s, 138 dépôts passés au gc).
- **Conséquence** : la tâche proposée à 13:02:25 UTC tomberait **au milieu** d'un balayage de même horaire. Le `fireAt` du point 4
  n'est plus valable.
- **Loi de l'intervalle inconnue** : un seul point. Si l'intervalle court du début d'un balayage au suivant, le 28/11 commencerait
  vers 12:46 ; s'il court de la fin, le décalage s'accumule (environ 37 min par jour, soit plusieurs heures au 28/11). Il faut un
  second balayage (15/11) pour trancher.
- **Décisions de rétention** : 2, toutes `keep` dans `vulndb/grype` (tags 2026-11-13 et 2026-11-14, « retained by
  mostRecentlyPushedCount:11 »), `dry-run` faux. Aucune décision dans `builds/scan/**` (rien n'a 336 h).
- **Non prévu** : chaque décision porte `pushTimestamp` et `lastPullTimestamp` (base de métadonnées de Zot), pas la date du blob.
  Si `retention.delay` se mesure aussi depuis le dernier tirage, un scan relu (porte, `lire_vsa`, contrôles) verrait sa
  suppression repoussée : **risque pour H1 et H2, non vérifié** (ni dans le code de Zot ni par une mesure).
