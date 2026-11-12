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
