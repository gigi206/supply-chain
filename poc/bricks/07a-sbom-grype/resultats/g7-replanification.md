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

## Note de 2026-11-14T20:52:18Z : correction de H1, H2 et H5 par balayage, après relecture du conseiller (rien n'est réécrit)

Lu dans les lignes brutes du 14/11 (hors du dépôt), sans nouvelle lecture de la VM :
- **Aucune ligne de gc entre le démarrage (13/11, 12:17:25) et le 14/11 à 12:45:50 UTC** : pas de balayage au démarrage.
- **Ordre dans le balayage** : `builds/scan/essai-07a` à 13:01:00, `builds/scan/essai-scan` à 13:01:24, `builds/scan/sample-app` à
  13:01:31, `vulndb/grype` à 13:22:15 UTC, soit 15 à 37 min après le début (138 dépôts au total).
- **Le premier balayage utile est celui du 27/11, pas du 28/11.** Le premier scan (13/11, 12:45:07) a 336 h le 27/11 à 12:45:07 ;
  un balayage du 27/11 de même horaire commencerait à 12:45:50 et passerait sur les dépôts de scan vers 13:01, donc après les
  dates d'éligibilité des scans du 13/11 (12:45 et 12:47) et des témoins (12:49:10 à 12:49:55). Si l'intervalle court de la fin
  d'un balayage, le décalage repousse le balayage du 27/11 plus tard dans la journée : même répartition.
- **Répartition corrigée** (le cumul après le balayage du 28/11 ne change pas) :
  - **27/11** : `builds/scan/sample-app`, les 2 scans du 13/11 (H1) ; `builds/scan/essai-scan`, les 16 témoins (H2) ; `vulndb/grype`,
    la base du 13/11 (sans tag depuis le 24/11, 336 h le 27/11 à 12:42:16) et le retrait d'un tag (16/11) (H5) ;
  - **28/11** : le scan du 14/11 (09:31) et la base du 14/11 (08:11), et le retrait d'un tag (17/11).
- **`g7-replanifier.sh`** : son modèle (balayage à démarrage + k × 24 h) est réfuté par la mesure du 14/11. Le script n'est pas
  modifié (accord nommé requis) ; ses lignes « premier balayage » et « heure proposée » du 14/11 ne valent plus.
- **`lastPullTimestamp`** : les deux décisions relevées portent sur des tags, pas sur des referrers. La mesure du 06/11 a été faite
  sur une copie du stockage (`g7-predictions.md`, l. 3) et ne tranche pas. Risque laissé ouvert pour H1 et H2.
- **Consigne du point 3, à compléter avant le point 4** : compter les décisions des balayages du 24/11, du 27/11 et du 28/11
  séparément ; relever `pushTimestamp` et `lastPullTimestamp` de tout referrer de scan survivant de plus de 336 h ; `fireAt` après
  la fin du balayage du 28/11, à fixer d'après un second balayage (15/11).

## Note de 2026-11-14T21:50:27Z : `lastPullTimestamp` lu dans le code de Zot, et lectures déjà faites (rien n'est réécrit)
Préparation de la révision 1.0.0-2 de la 06 (lecture seule, aucune lecture de la VM).
- **Code de Zot v2.1.22** (`pkg/storage/gc/gc.go` au tag v2.1.22, et copie du cache `07a/zot-src/gc.go`, même logique) : un
  referrer dont le sujet n'est pas dans son dépôt (cas de `builds/scan/**`, R5) est retiré par `removeReferrer`, puis
  `removeManifestIfOlderThan`, puis `isBlobOlderThan`, qui compare la **date de modification du blob** (`StatBlob`) à `retention.delay`.
  Le mot « pull » n'apparaît pas dans `gc.go`. D'après le code, un tirage ne repousse donc pas H1 ni H2 ; `lastPullTimestamp`
  sert aux règles de rétention des tags (`retention.go`, `pulledWithin`, `mostRecentlyPulledCount`), que la configuration
  n'utilise pas pour les scans. **Risque de la note de 20:52:18Z clos par lecture du code, à confirmer par la mesure du 27/11.**
- **Lectures déjà faites des scans du 13/11** (journaux archivés) : contrôle 7 de S5b à 12:48:15 UTC (`08-trust-plane/resultats/
  rejeu-s5b-plateforme-ctl.log` l. 1461-1464, `LECTURE|2`) et porte de la reprise du bloc 06 à 15:50:11 UTC
  (`08-trust-plane/resultats/rejeu-s5b-06-c.log` l. 245, « 2 énoncé(s) vérifié(s) dans …/builds/scan/sample-app »). La porte de
  S6a du 14/11 ne juge que le deb (`06-deb-sbuild/resultats/s6a-porte.log` l. 9).
- Note de 2026-11-14T21:53:55Z (rien n'est réécrit) : portée de la lecture de la note précédente : WebFetch au tag v2.1.22 (résumé et citations
  courtes, pas les octets) et copie du cache sans version relevée (`grep -ci pull` : 0) ; `zot.json` : `builds/scan/**` sans `keepTags`.

## Point 3 révisé d'après le relevé du 15/11 (note de 2026-11-20T19:09:44Z ; « Oui » du propriétaire ; rien n'est réécrit au-dessus)

Le relevé du 15/11 ([`g7-balayage-15-11.log`](g7-balayage-15-11.log)) est commité avec cette note, sur ta décision.
- Il contient un écart de masquage, noté dans son en-tête : quatre noms de dépôts ont été affichés à l'écran, pas dans le fichier.
- Il retient la **loi B**. Un balayage commence 24 h et 4,940 s après la fin du précédent. Elle n'est mesurée que sur un intervalle (14/11 → 15/11).
- Le journal de `zot.service` ne gardait qu'environ 14 h, profondeur mesurée une fois.

**Conséquences pour les prédictions du 14/11** :
- Les balayages dérivent d'environ 36 min 43 s par jour et tombent le soir. Les heures « vers 12:17 » et « 13:02:25 » ne valent plus.
- Une lecture unique après le 28/11 ne verrait ni le 24/11 ni le 27/11 : il faut **une lecture par balayage**, dans les 14 h qui suivent sa fin.

### Projection (CALCUL, pas une mesure)

Durée prise égale à celle du 15/11 (2197,806 s) ou du 14/11 (2199,303 s). Le passage sur les dépôts de scan est placé à début + 964,4 s, comme le 15/11. Heures UTC.

| Balayage | Début | Dépôts de scan | Fin |
|---|---|---|---|
| 20/11 | 16:26:08 à 16:26:14 | 16:42:12 à 16:42:18 | 17:02:46 à 17:02:53 |
| 21/11 | 17:02:51 à 17:02:58 | 17:18:55 à 17:19:03 | 17:39:28 à 17:39:37 |
| 24/11 | 18:52:59 à 18:53:11 | 19:09:03 à 19:09:15 | 19:29:37 à 19:29:50 |
| 27/11 | 20:43:07 à 20:43:24 | 20:59:12 à 20:59:28 | 21:19:45 à 21:20:03 |
| 28/11 | 21:19:50 à 21:20:08 | 21:35:54 à 21:36:12 | 21:56:28 à 21:56:47 |

Toute variation de durée (nombre de dépôts, charge) déplace ces heures. L'écart s'accumule d'un jour à l'autre.

### Prédictions par balayage

Elles révisent H1, H2, H4 et H5. H3, H6 et H7 sont inchangées.

**Hypothèses**, non vérifiées :
- les poussées quotidiennes continuent : base de `vulndb/grype` vers 08:05 UTC, scan de `sample-app` à 09:30, scan du deb à 11:15 ;
- aucun autre scan n'a été poussé depuis le 15/11 ;
- `mostRecentlyPushedCount:11` et `retention.delay` 336 h sont inchangés.

| # | Balayage | Prédit | Confiance |
|---|---|---|---|
| B20 | 20/11, déjà passé, **non lu** | Début dans la fenêtre projetée, à ± 60 s : la loi B tient sur 5 intervalles. Aucune suppression. 8 décisions `keep` dans `vulndb/grype` (tags du 13/11 au 20/11) | moyenne : un seul intervalle mesuré |
| B24 | 24/11 | `vulndb/grype` : 12 tags, retrait du tag du 13/11 (H5), 11 `keep`. Aucune autre suppression | moyenne |
| B27 | 27/11 | `builds/scan/sample-app` : 2 referrers supprimés, les scans du 13/11 (H1). `builds/scan/essai-scan` : 16 (H2). `vulndb/grype` : retrait du tag du 16/11, et la base du 13/11 effacée (sans tag depuis le 24/11, 336 h le 27/11 à 12:42:16) (H5) | moyenne |
| B28 | 28/11 | `builds/scan/sample-app` : 1 (scan du 14/11 à 09:31) (H1). **`builds/scan/sample-app-deb` : 1, le premier scan du deb, du 14/11 à 21:01** (H4 révisée). `vulndb/grype` : retrait du tag du 17/11, et la base du 14/11 effacée (H5) | faible pour le deb, moyenne pour le reste |

**H4 change** : la prédiction du 14/11 (« absent, ou aucune décision ») supposait un balayage vers 12:17 UTC.
- Avec la loi B, le balayage du 28/11 passe sur les dépôts de scan vers 21:36 UTC, après la 336e heure du premier scan du deb (poussé le 14/11 vers 21:01, d'après `docs/03` ; seconde non relue).
- La marge n'est que d'environ 35 min. Si le balayage passait plus tôt, ce scan survivrait jusqu'au 29/11.

### Consigne (révise celle du 14/11 ; chaque lecture sur accord nommé)

- **Une lecture du journal de `zot.service` par balayage** : B20, puis B24, B27 et B28. Chacune entre 1 h et 10 h après la fin projetée, en lecture seule (`sudo journalctl` sur sc-stockage, comme le 15/11).
- **Relevé par balayage** :
  - début, fin, durée et nombre de dépôts ;
  - heures de passage de `builds/scan/**` et de `vulndb/grype` ;
  - toutes les décisions de rétention, comptées par dépôt et par raison, puis comparées à la ligne de ce balayage ci-dessus.
- **Après B28 seulement**, les points 1, 3, 4, 5 et 6 de la consigne du 14/11 :
  - image réelle et deb lisibles ;
  - aucun blob manquant ;
  - décisions lisibles dans Grafana (comptes seulement) ;
  - CronJob ;
  - place libre.
- Au premier relevé, je regarde si les lignes de Zot sont dans Loki, en comptes seulement, sans archiver de réponse de Grafana. Si elles y sont, la limite de 14 h ne tient plus.
- **Contrainte de calendrier** : le rejeu de M5b recrée Zot. Il ne commence donc pas avant la lecture de B28, vers 23:00 UTC le 28/11.

### Point 4, sur accord

- La tâche `supply-chain-g7-premiere-suppression` reste désactivée. Elle sera remplacée par trois tâches ponctuelles, pour B24, B27 et B28. Leurs heures seront fixées après la lecture de B20, qui corrige la projection.
- La lecture de B20 n'a pas besoin de tâche : le journal la garde jusque vers 07:00 UTC le 21/11 (calcul, profondeur de 14 h).

## Note de 2026-11-20T19:13:11Z : correction de la note de 19:09:44Z (point 3 révisé ; rien n'est réécrit au-dessus)

Le conseiller a relevé quatre trous dans la note de 19:09:44Z. Ses prédictions restent écrites telles quelles. Les trous sont comblés ici, avant toute lecture.

**1. Fenêtres élargies, réinventoriées.** Avec des balayages du soir, deviennent éligibles :
- à B27, tout ce qui a été poussé le 13/11 avant environ 20:59 UTC ;
- à B28, tout ce qui a été poussé le 14/11 avant environ 21:36 UTC.

Relu dans les journaux commités des 13 et 14/11 (lignes `PUBLIE|…/builds/scan/…`) :
- **13/11** : deux scans seulement dans `builds/scan/sample-app`, `9e2c8cf4…` et `043e1382…`, vers 12:45 et 12:47 UTC (`rejeu-s5b-plateforme-ctl.log`, commit `45880b90`). Ce sont les deux de H1.
- **Témoins de G6** (`builds/scan/essai-scan`) : ils passent par un autre chemin, déjà comptés en H2 (16, vers 12:49 UTC).
- **14/11** : le scan `256c3190…` dans `builds/scan/sample-app-deb`. C'est un referrer du deb 1.0.0-1 (`039949f9…`). Le job est parti à 20:59:40 UTC et a duré 125 s : poussée vers 21:01:45 UTC, à la seconde près non relue.
- **Rien d'autre** dans ces fenêtres. Ce relevé ne voit qu'un motif dans les journaux commités : une poussée hors des scripts du dépôt lui échapperait.
- **Relevé en passant** : `s6a-periodique.log` du 14/11 a été réécrit le 16/11 à 16:06:34 UTC par `lancer`, pour le deb 1.0.0-2 (`60f25f5c…`). Sa première version reste dans git (`31e6e5c1`). C'est un écart à la règle « un journal n'est jamais réécrit ». Les scans du 16/11 visent un autre sujet et deviennent éligibles le 30/11.

**2. Hypothèse manquante : Zot non redémarré depuis le 13/11 à 12:17:25 UTC.** La projection n'est valide que sous cette hypothèse.
- L'agrandissement de sc-stockage, aujourd'hui vers 16:04 UTC, a relevé « zot active » avant et après. Il n'a relevé ni `ActiveEnterTimestamp` ni `NRestarts` : l'absence de redémarrage n'est **pas vérifiée**.
- Chaque lecture commence donc par ce contrôle, comme le 15/11. Si Zot a redémarré, la projection ne vaut plus, et B20 le dira.
- Le même relevé compte 166 dépôts au catalogue, contre 139 balayés le 15/11. Des balayages plus longs décaleraient la projection vers plus tard, sans que je sache de combien.
- Pour H4, un passage plus tardif sur les dépôts de scan élargirait la marge. Non calculé.

**3. Loki.** D'après la configuration de la 19b :
- Alloy envoie à Loki tout le journal systemd de chaque VM, sans filtre, étiqueté par unité (`commun/journal.alloy`) ;
- Loki garde 720 h (`loki.yaml`).

Les lignes de `zot.service` devraient donc y être environ 30 jours. **Ce n'est pas mesuré.** Si c'est confirmé, la limite des 14 h tombe, et les lectures de B24, B27 et B28 peuvent attendre, tant que la plateforme n'est pas recréée.
- **« Jusque vers 07:00 UTC » était optimiste.** Le début de B20 sortirait du journal de la VM vers 06:26 UTC. La profondeur, mesurée une seule fois, dépend du volume écrit : elle peut être plus courte.

**4. « Le rejeu de M5b ne commence pas avant la lecture de B28 »** n'est pas un fait. C'est une **proposition** au propriétaire : il accepte de tout perdre au rejeu, et l'ordre lui revient.

## Lecture de B20 : prédiction non tenue, Zot redémarré le 19/11 (note de 2026-11-20T19:26:42Z ; « Oui » du propriétaire ; rien n'est réécrit au-dessus)

**Lecture** du 20/11 de 19:24:33 à 19:24:36 UTC, au dépôt `963daa36` ([`g7-balayage.sh`](../g7-balayage.sh), script `7abe1bc3…`, [journal](g7-balayage-20-11.log)). Fenêtre de 11:00 à 19:30 UTC, élargie pour voir un balayage même si la loi B était fausse.
- **`zot.service` a démarré le 19/11 à 20:24:46 UTC** (`ActiveEnterTimestamp`), avec `NRestarts=0` : c'est un redémarrage commandé, pas un redémarrage automatique.
  - Cause, relue dans le dépôt : le passage de `stockage.sh zot` qui a posé le compte `poc-lien` de la brique 09 (commit `4fe5e8a3` de la 08, accord « Maintenant » du 19/11). Il y a eu deux passages, à 20:24:09 et à 20:24:42 UTC (`stockage-zot-1.log`, `stockage-zot.log`). Le second n'était pas voulu, comme le dit le commit.
  - La rétention et le gc ne changent pas : le diff de `zot.json` n'ajoute que l'entrée d'accès `signes/**`.
- **L'hypothèse « Zot non redémarré depuis le 13/11 » de la note de 19:13:11Z est réfutée.** La projection de la note de 19:09:44Z ne vaut plus, à partir du 19/11. Les prédictions B20, B24, B27 et B28 restent écrites, mais leurs heures sont caduques.
- **B20 non tenue** : aucune ligne « executing gc of orphaned blobs » ni décision de rétention entre 11:00 et 19:30 UTC. Le journal de la VM remonte au 20/11 à 07:18:03 UTC (287,1 Mio). Dans la fenêtre, les 3040 lignes retenues par le filtre sont toutes des « HTTP API ».
- **Loki** : 0 ligne de gc dans la même fenêtre, ce qui concorde avec le journal. Le filtre `|= "decision"` était trop large : il rend 2000 lignes de `zot.service`, au plafond, de 11:00 à 16:31 UTC. Ce compte est inexploitable, mais il montre que **les lignes de `zot.service` sont dans Loki**. La note de 19:13:11Z le prévoyait d'après la configuration. Les 14 h de profondeur du journal de la VM ne sont donc plus la seule limite.

**Script v2** (`g7-balayage.sh`, sha256 `d68c726a4991e68c…`) :
- `SANS_JOURNAL=1` lit Loki seul, sans sudo ;
- `SUFFIXE` donne un journal neuf ;
- Loki filtre « executing gc of orphaned blobs » ou `"decision":`, jusqu'à 5000 lignes. Elles sont masquées, puis résumées comme celles du journal, sans être archivées.

**Prédictions de la lecture du 19/11** (Loki seul, fenêtre de 20:00 à 23:59 UTC, journal `g7-balayage-19-11.log`), écrites avant le lancement :

| # | Prédit | Confiance |
|---|---|---|
| BD1 | Un balayage part au démarrage : premières lignes de gc moins de 5 min après 20:24:46 UTC | faible : hypothèse du 15/11, jamais vérifiée (journal perdu) |
| BD2 | S'il existe : entre 140 et 170 dépôts, durée de 25 à 45 min | faible |
| BD3 | Aucune décision autre que `keep`. Rien n'a 336 h, et `vulndb/grype` n'a que 7 tags (13/11 au 19/11), sous le seuil de 11 | moyenne |
| BD4 | Lignes de Loki sans masquage, et sous le plafond de 5000 | moyenne |

**Conséquence pour ce soir.** Avec BD1, le prochain balayage commencerait 24 h et environ 5 s après la fin de celui du démarrage, soit vers 20:50–21:10 UTC le 20/11. Sans balayage au démarrage, il commencerait vers 20:53 UTC, si l'écart de 28 min 25 s du 13/11 se répète. Ce sont des calculs, pas des mesures.

## Lecture du 19/11 dans Loki : un balayage part au démarrage de Zot (note de 2026-11-20T19:28:08Z ; rien n'est réécrit au-dessus)

**Lecture** du 20/11 à 19:26:50 UTC, au dépôt `8ad78e90` (script v2 `d68c726a…`, Loki seul, sans sudo, [journal](g7-balayage-19-11.log)). Fenêtre du 19/11, de 20:00 à 23:59 UTC. Loki rend 172 lignes, dont 4 masquées.
- Les lignes « executing gc of orphaned blobs » vont de **20:24:14 à 21:03:47 UTC**, au nombre de 161.
- Ces lignes mêlent deux balayages : celui du premier passage de `stockage.sh zot` (20:24:09), interrompu par le second redémarrage, et celui qui suit le démarrage de 20:24:46.
  - Le résumé ne les sépare pas. Le nombre de dépôts du second balayage n'est donc pas mesuré.
- **Passages, au dernier balayage** :
  - `builds/scan/essai-07a` à 20:39:55 ;
  - `essai-scan` à 20:40:08 ;
  - `sample-app` à 20:40:31 ;
  - `sample-app-deb` à 20:40:47 ;
  - `vulndb/grype` à 21:03:21.
- **7 décisions**, toutes `keep` dans `vulndb/grype` (« retained by mostRecentlyPushedCount:11 policy »).

| # | Verdict |
|---|---|
| BD1 | **Tenue** : les premières lignes de gc arrivent 5 s après le premier démarrage. Un balayage part au démarrage de Zot. La lecture ne montre pas l'heure exacte de départ après le second démarrage |
| BD2 | **Tenue avec réserve** : 161 lignes, deux balayages mêlés. Durée du second d'au plus 39 min 1 s (2341 s, depuis 20:24:46) |
| BD3 | **Tenue** : 7 `keep`, aucune autre décision |
| BD4 | **Non tenue pour le masquage** : 4 lignes masquées, sans doute les dépôts au motif masqué comme le 15/11 (non lu). **Tenue pour le plafond** : 172 lignes, sous 5000 |

**Conséquence** : l'hypothèse « balayage au démarrage », invérifiable le 15/11, est vérifiée ici. Elle explique aussi les 28 min 25 s du 14/11. Le calendrier part désormais de la fin de ce balayage, le 19/11 à 21:03:47 UTC.

### Nouvelle projection (CALCUL, pas une mesure)

Hypothèses :
- loi B : début = fin du précédent + 24 h + 4,940 s ;
- durée constante de 2341 s, qui est un majorant ;
- passages à début + 909,7 s pour les dépôts de scan et à début + 2315,4 s pour `vulndb/grype`, comme le 19/11 ;
- **aucun redémarrage de Zot.** Tout passage de `stockage.sh zot` relance un balayage et remet ce calendrier à zéro.

Heures UTC. Un balayage glisse d'environ 39 min par jour et passe minuit à partir du n°5.

| Balayage | Début | Dépôts de scan | `vulndb/grype` | Fin |
|---|---|---|---|---|
| n°1 | 20/11 21:03:52 | 20/11 21:19 | 20/11 21:42 | 20/11 21:42:53 |
| n°2 | 21/11 21:42:58 | 21/11 21:58 | 21/11 22:21 | 21/11 22:21:59 |
| n°3 | 22/11 22:22:04 | 22/11 22:37 | 22/11 23:00 | 22/11 23:01:05 |
| n°4 | 23/11 23:01:10 | 23/11 23:16 | 23/11 23:39 | 23/11 23:40:11 |
| n°5 | 24/11 23:40:16 | 24/11 23:55 | 25/11 00:18 | 25/11 00:19:17 |
| n°6 | 26/11 00:19:22 | 26/11 00:34 | 26/11 00:57 | 26/11 00:58:23 |
| n°7 | 27/11 00:58:28 | 27/11 01:13 | 27/11 01:37 | 27/11 01:37:29 |
| n°8 | 28/11 01:37:34 | 28/11 01:52 | 28/11 02:16 | 28/11 02:16:35 |
| n°9 | 29/11 02:16:40 | 29/11 02:31 | 29/11 02:55 | 29/11 02:55:41 |
| n°10 | 30/11 02:55:46 | 30/11 03:10 | 30/11 03:34 | 30/11 03:34:47 |

### Prédictions par balayage

Elles remplacent les heures de B24, B27 et B28. Le contenu change de balayage, comme suit.

**Éligibilité** : poussée + 336 h, avant le passage sur le dépôt.
- Les heures des scans du 15/11 sont supposées (09:31 et 11:16), non relues.
- Les tags de `vulndb/grype` sont poussés vers 08:05 UTC, d'après le 15/11.

| # | Balayage | Prédit | Marge |
|---|---|---|---|
| N1 | n°1, ce soir (20/11) | Début à 21:03:52 UTC, à ± 120 s. 8 décisions `keep` dans `vulndb/grype` (tags du 13/11 au 20/11). Aucune suppression | — |
| N5 | n°5 (24/11 23:40 → 25/11 00:19) | Retrait du tag du 13/11 dans `vulndb/grype` (12e tag poussé le 24/11). Aucune autre suppression | environ 16 h |
| N6, N7 | n°6 et n°7 | Retrait d'un tag chacun (14/11, puis 15/11). Aucune autre suppression | environ 16 h |
| N8 | **n°8 (28/11 01:37 → 02:16)** | **Premières suppressions réelles** : 2 scans du 13/11 dans `builds/scan/sample-app`, 16 témoins dans `essai-scan`, base du 13/11 effacée, retrait du tag du 16/11 | 13 h et plus |
| N9 | n°9 (29/11 02:16 → 02:55) | Scan du 14/11 (09:31) dans `sample-app`, **premier scan du deb (14/11, 21:01:45)** dans `sample-app-deb`, base du 14/11 effacée, retrait du tag du 17/11 | 5 h 30 pour le deb |

**Lectures** : Loki garde les lignes de `zot.service` (lu ici). Chaque lecture peut donc se faire sans sudo, après la fin du balayage, tant que la plateforme n'est pas recréée.
- La lecture de N1 est couverte par ton « Oui » de ce soir. Je la ferai après 22:00 UTC, en Loki seul.
- Pour voir N8 et N9, le rejeu de M5b, qui recrée Zot et Loki, devrait attendre le 29/11 vers 03:00 UTC. **C'est ta décision** : tu acceptes de tout perdre au rejeu.

## Note de 2026-11-20T19:31:21Z : lectures Loki des balayages passés, prédictions avant lancement ; corrections de la note de 19:28:08Z (rien n'est réécrit au-dessus)

**Pourquoi.** Loki garde 720 h : les balayages passés sont lisibles maintenant, sans sudo. Le conseiller a relevé que la note de 19:28:08Z reposait encore sur un seul intervalle mesuré.

**Corrections de la note de 19:28:08Z**
- « Elle explique aussi les 28 min 25 s du 14/11 » était affirmé, pas mesuré. La lecture du 13/11 ci-dessous le mesurera.
- La durée de 2341 s et les décalages de passage (909,7 s et 2315,4 s) viennent de deux balayages mêlés, comptés depuis 20:24:46. Ce sont des bornes, pas des mesures. La projection sera refaite avec la durée du dernier balayage complet d'avant le redémarrage.
- BD1 : les « 5 s » courent depuis l'en-tête du premier passage de `stockage.sh zot` (20:24:09), pas depuis un démarrage de Zot relevé.
- **Écart à la consigne** : les journaux du 19/11 et des lectures ci-dessous archivent des heures, les noms des dépôts suivis et les raisons des décisions, tirés de la réponse de Grafana. La consigne du 14/11 et la note de 19:09:44Z disaient « comptes seulement ». Aucune ligne brute n'est archivée. **C'est à toi de trancher**, avant toute poussée.

**Lectures** (`g7-balayage.sh` v2, `SANS_JOURNAL=1`, un journal neuf par lecture) :

| # | Fenêtre (UTC) | Journal | Prédit (loi B depuis le 15/11, durée de 2197,8 à 2199,3 s) | Confiance |
|---|---|---|---|---|
| L13 | 13/11, 12:00 à 13:30 | `g7-balayage-13-11.log` | Un balayage au démarrage de Zot (12:17:25) : début moins de 2 min après, fin vers 12:45:45 (déduite du début du 14/11, 24 h + 4,94 s plus tôt) ; aucune décision autre que `keep` | faible : Alloy a pu démarrer après Zot. 0 ligne dirait seulement que la collecte manquait |
| L16 | 16/11, 12:00 à 18:00 | `g7-balayage-16-11.log` | Début 13:59:17, à ± 120 s ; fin vers 14:35:55 ; 4 `keep` (tags du 13 au 16/11) | moyenne |
| L17 | 17/11, 12:00 à 18:00 | `g7-balayage-17-11.log` | Début vers 14:36:00, à ± 5 min ; 5 `keep` | moyenne |
| L18 | 18/11, 13:00 à 19:00 | `g7-balayage-18-11.log` | Début vers 15:12:42, à ± 5 min ; 6 `keep` | moyenne |
| L19 | 19/11, 14:00 à 20:20 | `g7-balayage-19-11-avant.log` | Début vers 15:49:25, à ± 5 min, fin avant le redémarrage ; 7 `keep` | moyenne |

Pour toutes : aucune suppression, puisque rien n'a 336 h et que `vulndb/grype` reste sous 11 tags. Les durées pourraient s'allonger avec le nombre de dépôts : 139 balayés le 15/11, 166 au catalogue le 20/11. La tolérance de ± 5 min en tient compte, sans calcul.

## Résultat des lectures L13 à L19 (note de 2026-11-20T19:32:31Z ; rien n'est réécrit au-dessus)

**Lectures** le 20/11 de 19:31:28 à 19:31:29 UTC, au dépôt `1790a28a` : Loki seul, script `d68c726a…`, cinq journaux neufs (`g7-balayage-13-11.log`, `-16-11`, `-17-11`, `-18-11`, `-19-11-avant`). Chacun compte 4 lignes masquées et aucune décision autre que `keep`.
- Une première boucle, lancée sous zsh, a échoué avant toute lecture : `set -- $c` n'y découpe pas les mots. Aucun journal n'a été écrit. La relance s'est faite sous `bash -c`.

Les heures sont celles des première et dernière lignes « executing gc ». La fin réelle (« gc successfully completed ») suit la dernière ligne de moins de 0,01 s, mesuré le 15/11.

| # | Début mesuré | Prédit | Écart | Dernière ligne | Dépôts | Durée | `keep` | Verdict |
|---|---|---|---|---|---|---|---|---|
| L13 | 13/11 12:16:43.3 | moins de 2 min après 12:17:25 | **42 s avant** le démarrage relevé | 12:45:35.5 (prédit vers 12:45:45) | 117 | 1732 s | 1 | **tenue sur le balayage de démarrage et sa fin**, à 10 s ; début antérieur au démarrage relevé, non expliqué |
| L16 | 16/11 13:59:30.9 | 13:59:17 ± 120 s | +14 s | 14:33:17.8 | 135 | 2027 s | 4 | tenue |
| L17 | 17/11 14:33:35.4 | 14:36:00 ± 5 min | −145 s | 15:10:27.8 | 139 | 2212 s | 5 | tenue |
| L18 | 18/11 15:10:29.8 | 15:12:42 ± 5 min | −132 s | 15:48:15.6 | 148 | 2266 s | 6 | tenue |
| L19 | 19/11 15:48:21.4 | 15:49:25 ± 5 min | −64 s | 16:28:28.7 | 148 | 2407 s | 7 | tenue |

**Loi B mesurée sur six intervalles.** On mesure le début d'un balayage moins la dernière ligne du précédent, moins 24 h.
- 13→14/11 : +15,0 s, mesuré depuis le balayage de démarrage ;
- 14→15/11 : +4,9 s ;
- 15→16/11 : +18,4 s ;
- 16→17/11 : +17,6 s ;
- 17→18/11 : +2,0 s ;
- 18→19/11 : +5,8 s.

Le balayage de démarrage du 13/11 **explique les 28 min 25 s du 14/11** : c'est maintenant mesuré, et non plus seulement déduit. La durée croît avec le nombre de dépôts, de 1732 à 2407 s. Le début du 13/11, 42 s avant `ActiveEnterTimestamp`, laisse penser à un démarrage antérieur, comme les deux passages du 19/11. Ce n'est pas vérifié.

### Projection refaite (CALCUL)

Elle part de la dernière ligne du balayage de redémarrage, le 19/11 à 21:03:47 UTC.
- Durée : de 2341 à 2600 s.
- Écart quotidien : de 2 à 19 s.
- Passages à début + 1057 s pour les dépôts de scan et à début + 2395 s pour `vulndb/grype`, comme le 19/11 avant le redémarrage.
- Aucun redémarrage de Zot.

| # | Balayage | Plage projetée (UTC) | Contenu prédit | Marge minimale |
|---|---|---|---|---|
| N1 | n°1 | début le 20/11 entre 21:03:49 et 21:04:06 | 8 `keep`, aucune suppression | — |
| N5 | n°5 | `vulndb/grype` le 25/11 entre 00:19 et 00:38 | retrait du tag du 13/11 | environ 16 h |
| N8 | n°8 | le 28/11, de 01:37 à 02:52 | **premières suppressions réelles** : 2 scans du 13/11, 16 témoins, base du 13/11, tag du 16/11 | 13,1 h |
| N9 | n°9 | le 29/11, de 02:16 à 03:36 | scan du 14/11, **premier scan du deb**, base du 14/11, tag du 17/11 | 5,5 h (le deb) |

Les contenus prédits N1 à N9 de la note de 19:28:08Z sont inchangés. Seules les plages s'élargissent.

**Décision du propriétaire sur les résumés tirés de Grafana** (note de 2026-11-20T19:47:09Z) : « Oui ». La question posée était : « J'accepte ces résumés tirés de Grafana et je pousse ? ».
- Les journaux `g7-balayage-*.log` gardent donc des heures, les noms des dépôts suivis et les raisons des décisions de rétention, en plus des comptes.
- Aucune ligne brute de Grafana ni de Loki n'est archivée.
- La consigne « comptes seulement » du 14/11 et de la note de 19:09:44Z est levée pour ces relevés.

## Point 4 à sec : état de Zot avant les premières suppressions, prédictions E1 à E8 (note de 2026-11-20T19:58:13Z ; rien n'est réécrit au-dessus)

**Pourquoi.** Après le balayage n°9, un 404 ne prouve une suppression que si l'objet était présent avant. Le conseiller a demandé de relever cet état maintenant, en lecture seule, et de le commiter.

**Script** [`g7-etat.sh`](../g7-etat.sh) (sha256 `40406b2f1bcc3499…`, neuf) :
- uniquement des GET et des HEAD anonymes sur l'API de Zot ; ni ssh, ni sudo, ni Grafana, ni cluster ;
- `MOMENT=avant` : image réelle et deb avec `.sig` et `.att`, referrers des sujets réels (scans et VSA), témoins de G6, tags de `vulndb/grype` avec leurs digests, blob `{}` (H7) ;
- `MOMENT=apres AVANT=…` : la même chose, puis chaque digest du journal « avant » relu un par un (200 présent, 404 supprimé).
- `bash -n` passe, et shellcheck ne relève aucun avertissement (`-S warning`).

**Sujets, relus ce soir dans les CronJobs** (`kubectl get cronjob -n scan`, variables des conteneurs d'initialisation) :
- `scan-sample-app` (09:30 UTC) vise `builds/sample-app@sha256:3a7ca1b1…` ;
- `scan-sample-app-deb` (11:15 UTC) vise `builds/sample-app-deb@sha256:60f25f5c…`, le deb 1.0.0-2. Le premier scan du deb (`256c3190…`, 14/11) a pour sujet le deb 1.0.0-1, `039949f9…`. Le script lit les deux.

**Prédictions**, avant lancement :

| # | Prédit | Confiance |
|---|---|---|
| E1 | Image réelle, deb 1.0.0-1 et deb 1.0.0-2 : manifestes, `.sig` et `.att` en 200 | haute : tags lus ce soir dans `tags/list` |
| E2 | `builds/scan/sample-app`, referrers de l'image : 9 (2 du 13/11, puis un par jour du 14 au 20/11) | moyenne : un autre scan manuel m'échapperait |
| E3 | `builds/scan/sample-app-deb` : 7 referrers en tout, sur les deux debs. Le premier, du 14/11, a pour sujet `039949f9…` | moyenne. La répartition entre les deux debs n'est pas prédite : l'heure de création du deb 1.0.0-2, le 16/11, n'est pas relue |
| E4 | Témoins de G6 : 16 referrers dans `builds/scan/essai-scan`, sur 14 images de `builds/essai-scan` | moyenne : H2. Le cas `absent` n'a pas de scan, et un cas peut en avoir plusieurs |
| E5 | `vulndb/grype` : 8 tags, du 2026-11-13 au 2026-11-20, chacun avec un digest distinct | haute pour le compte (lu dans `tags/list`) ; moyenne pour « distinct » |
| E6 | Blob `{}` en 200 dans les trois dépôts | haute |
| E7 | VSA : au moins un referrer dans `builds/vsa/sample-app` et `builds/vsa/sample-app-deb` | moyenne. Le nombre exact n'est pas prédit |
| E8 | Les dates annotées (`org.opencontainers.image.created`) des scans du 13/11 tombent vers 12:45 et 12:47 UTC, celle du premier scan du deb vers 21:01 UTC le 14/11 | moyenne : rien ne garantit que le scanner annote la date de création |

## Résultat de l'état avant, E1 à E8 (note de 2026-11-20T19:58:59Z ; rien n'est réécrit au-dessus)

**Lecture** le 20/11 de 19:58:22 à 19:58:23 UTC, au dépôt `d33bc4ef`, script `40406b2f…`, code 0 ([journal](g7-etat-avant.log)). Aucune ligne masquée, aucun 404.

| # | Mesuré | Verdict |
|---|---|---|
| E1 | 3 manifestes, 3 `.sig` et 3 `.att` en 200 | tenue |
| E2 | 9 referrers, créés le 13/11 à 12:45:07 et 12:47:15, puis chaque jour du 14 au 20/11 entre 09:31:51 et 09:32:04 UTC | tenue |
| E3 | **8 referrers**, et non 7 : 3 pour le deb 1.0.0-1 (14/11 21:01:35, 15/11 11:16:51, **16/11 11:16:51**) et 5 pour le deb 1.0.0-2 (16/11 16:08:29, puis du 17 au 20/11 vers 11:17) | **non tenue pour le compte** : le CronJob du 16/11 à 11:15 visait encore le deb 1.0.0-1, et le scan de 16:08 (`s6a-periodique`) s'y est ajouté. Tenue pour le premier scan du deb, de sujet `039949f9…` |
| E4 | 16 referrers sur 14 images ; `absent` sans scan ; `illisible`, `recent-kev` et `recent-propre` en ont 2 ; tous créés le 13/11 entre 12:49:10 et 12:49:54 UTC | tenue |
| E5 | 8 tags, du 2026-11-13 au 2026-11-20, 8 digests distincts | tenue |
| E6 | Blob `{}` en 200 dans les trois dépôts | tenue |
| E7 | 1 VSA pour l'image, 1 pour chaque deb | tenue (compte non prédit) |
| E8 | 13/11 à 12:45:07 et 12:47:15 ; premier scan du deb le 14/11 à **21:01:35** UTC | tenue |

**Conséquences pour N8 et N9** (calcul ; Zot décide sur l'heure de poussée, pas sur l'annotation, qui la précède de quelques secondes) :
- Le premier scan du deb devient éligible le **28/11 à 21:01:35 UTC**, après le n°8 (28/11, de 01:37 à 02:52) et avant le n°9 (29/11, de 02:16 à 03:36). La marge de 5,5 h de N9 tient.
- Les deux autres scans du deb 1.0.0-1 (15/11 et 16/11 à 11:16:51) deviennent éligibles après le n°9 : ils iront aux n°10 (30/11) et n°11 (1/12). **Le deb 1.0.0-1 garde donc des scans jusqu'au 1/12.** Ce n'était pas prédit en H4 ni en N9, qui ne parlaient que du premier.
- Le scan de `sample-app` du 14/11 (09:31:51) devient éligible le 28/11 à 09:31:51 UTC, après le n°8 : il ira au n°9, comme N9 le prévoit.
- Les 16 témoins (13/11, 12:49:10 à 12:49:54) et les deux scans du 13/11 sont éligibles le 27/11 avant 12:50 UTC : n°8, comme N8.

## Point 4 à sec : lectures et tâche planifiée, choix au propriétaire (note de 2026-11-20T20:00:02Z ; rien n'est réécrit au-dessus ; RIEN N'EST PLANIFIÉ)

**Ce qui change la question.** Loki garde les lignes de `zot.service` 720 h (lu le 20/11). Une seule lecture, après le n°9, relit les n°1 à n°9, comme L13 à L19 l'ont fait pour les balayages passés. Les trois tâches de la note de 19:09:44Z (B24, B27, B28) ne sont plus nécessaires.

**La seule contrainte qui compte** : ni passage de `stockage.sh zot`, ni recréation de sc-stockage, ni rejeu de M5b avant la lecture. Un redémarrage de Zot déplace les balayages, et une recréation efface Loki.

**Options** :

| | Lecture | Ce qu'elle demande | Risque |
|---|---|---|---|
| (a) | Aucune tâche : je lis dans une session ouverte, après le 29/11 vers 05:40 UTC | rien à planifier | dépend d'une session ouverte ; aucun, tant que Loki garde les lignes (jusque vers le 20/12 pour le n°1, d’après la configuration ; la lecture n’a été mesurée que sur 7 jours, avec le 13/11) |
| (b) | **Une tâche ponctuelle**, le 29/11 à 05:40 UTC (fin la plus tardive du n°9, 03:36, plus 2 h) | ton accord pour remplacer la consigne de `supply-chain-g7-premiere-suppression`, fixer `fireAt` et la réactiver | la lecture se fait sans moi ; rien n'est commité ni poussé par la tâche |
| (c) | Une tâche par balayage (n°5, n°8, n°9) | trois accords | rien de plus que (b), puisque Loki garde tout |

**Fenêtres des lectures** (une par balayage, de 12:00 UTC le jour J à 12:00 UTC le lendemain) :
- d'après la projection, les balayages n°1 à n°9 commencent entre 20:00 et 04:00 UTC. Chaque fenêtre n'en contient donc qu'un, même s'il passe minuit ;
- le n°k est dans la fenêtre qui commence le (19 + k)/11 à 12:00 UTC ;
- `g7-balayage.sh` v2 ne prend qu'un seul jour (`JOUR`, `DE`, `A`). **Une v3 ajoutera `JOUR_A`** (jour de fin, `JOUR` par défaut), après la lecture de N1 pour ne pas la mêler à N1. Elle sera passée au banc avant toute tâche.

**Consigne de la tâche (b), à poser telle quelle sur ton accord.** Elle remplace celle du 14/11, désormais périmée :
- `sudo journalctl --since 13/11` ne vaut plus, puisque le journal de la VM ne garde qu'environ 14 h : la lecture passe par Loki seul ;
- Zot a redémarré le 19/11 à 20:24:46 UTC, et les heures, la loi B et la projection ont changé ;
- les sujets ont changé : le deb scanné chaque jour est le 1.0.0-2 (`60f25f5c…`) ;
- « comptes seulement » est levé pour les résumés de balayage, mais seulement pour eux ;
- **la tâche n'exécute que des scripts commités**, contrôlés par sha256, et rien en forme libre. Le relevé du 15/11, en forme libre, avait laissé un écart de masquage.

> Réponds en français. Dépôt : /home/gigi/Documents/git/github/gigi206/supply-chain, branche claude/focused-fermi-ul5y20. Brique 07a, G7, point 4. Lis d'abord poc/bricks/07a-sbom-grype/resultats/g7-replanification.md à partir de « Point 3 révisé » (notes du 20/11), en particulier « Projection refaite », « Résultat de l'état avant » et la note qui suit.
>
> TOUT EST EN LECTURE SEULE : ne modifie ni Zot, ni le cluster, ni les VM, ni Loki ; pas de sudo ; ne pousse rien, n'installe rien, ne committe rien. N'écris que les journaux produits par les deux scripts ci-dessous. N'exécute aucune autre commande sur la VM ou dans Grafana que celles de ces scripts. Si quelque chose échoue, dis-le, ne corrige rien, ne relance pas sous un autre nom de journal.
>
> 1. Vérifie que `sha256sum poc/bricks/07a-sbom-grype/g7-balayage.sh poc/bricks/07a-sbom-grype/g7-etat.sh` donne les empreintes écrites dans la note de pose de cette tâche. Si l'une diffère, arrête-toi et dis-le.
> 2. Pour chaque balayage n°2 à n°9 (n°1 déjà lu), lance depuis la racine : `JOUR=2026-11-<J> DE=12:00 JOUR_A=2026-11-<J+1> A=12:00 SANS_JOURNAL=1 mise exec -- poc/bricks/07a-sbom-grype/g7-balayage.sh`, J allant de 21 à 28. Chaque journal est neuf (`g7-balayage-<J>-11.log`).
> 3. Lance `MOMENT=apres AVANT=resultats/g7-etat-avant.log mise exec -- poc/bricks/07a-sbom-grype/g7-etat.sh`.
> 4. Relève en lecture seule : `KUBECONFIG=$HOME/.kube/supply-chain-poc.yaml kubectl get cronjob -n scan` (dernier succès de chaque CronJob), sans `describe` ni message d'événement.
> 5. Compare aux prédictions N5 à N9 et aux conséquences de « Résultat de l'état avant » : pour chaque balayage, début, `ActiveEnterTimestamp` de la section 1 (Zot a-t-il redémarré depuis le 19/11 à 20:24:46 UTC ?), décisions par dépôt et par raison, puis, dans l'état après, les digests passés de 200 à 404.
>
> Rapport court au propriétaire : résultat d'abord, écarts aux prédictions nommés, ce qui reste non vérifié. Les notes, le README et docs/03 seront écrits ensuite dans une session ouverte, sur son accord.

**Prédictions** : celles de N5 à N9, inchangées pour le contenu, et les conséquences de « Résultat de l'état avant ». Les heures sont des calculs ; un redémarrage de Zot les déplace sans changer ce qui doit être supprimé, sauf au balayage où tombe le redémarrage.

**Hors de cette tâche** : la place libre sur sc-stockage. Le relevé du 21/11 vers 16:00 UTC est prévu à part, à la main.

## Note de 2026-11-20T20:06:18Z : `g7-etat.sh` v2 (blobs), prédictions E9 à E11 avant relance (rien n'est réécrit au-dessus)

**Correction, relevée par le conseiller.** La v1 ne lisait que des manifestes, plus le blob `{}`. Elle perdait donc le point 3 de la consigne du 14/11 : « aucun blob manquant » sur les manifestes qui restent et sur la base la plus récente. C'est pourtant le risque propre au gc avec déduplication. Les notes de 19:58 et de 20:00 ne le disaient pas.

**v2** (sha256 `a12f0653831cb798…`) : une section 6 fait un HEAD, dans le même dépôt, de la config et de chaque couche de chaque manifeste présent. Elle couvre les referrers réels, les témoins et la base `vulndb/grype` la plus récente. Un blob qui ne rend pas 200 est listé (`BLOB-KO`). La relecture des digests du journal « avant » passe en section 7. `bash -n` passe, et shellcheck ne relève aucun avertissement.

**Relance** sous `SUFFIXE=-2` (journal `g7-etat-avant-2.log`). Le journal v1 reste tel quel.

| # | Prédit | Confiance |
|---|---|---|
| E9 | Sections 1 à 5 identiques au journal v1, en-tête et heures exceptés. Aucun scan ni aucune base ne sont poussés avant le 21/11 vers 08:05 | haute |
| E10 | 37 manifestes présents : 9 et 8 scans, 3 VSA, 16 témoins, 1 base | haute |
| E11 | Tous les blobs en 200, aucun `BLOB-KO`. Chaque scan et chaque témoin a 2 blobs (config `{}` et bundle) | haute pour les 200 ; moyenne pour « 2 blobs » ; nombre de blobs de la base non prédit |
