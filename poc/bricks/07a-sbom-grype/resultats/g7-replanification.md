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
