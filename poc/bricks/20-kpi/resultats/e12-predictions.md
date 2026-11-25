# Brique 20 : VSA de `f5e6bcb0` poussée (R5 de la brique 10), prédiction du seuil n° 5

Prédiction écrite le 2026-11-25T18:14:11Z, après le push de la VSA (18:13:16 à 18:13:19Z) et avant tout passage de l'exportateur qui le suit. `SUFFIXE=-5 seuil.sh` (lecture seule) n'est lancé qu'après un passage daté de plus de 120 s après 18:13:19Z, donc après 18:15:19Z. Suite de [e11](e11-predictions.md).

## État lu le 25/11, à 18:13:55Z

- Dernier passage de l'exportateur dans Prometheus : 1795630147, soit avant le push ; `f5e6bcb0` y vaut 0 pour `kpi_l3_verifie` et `kpi_replay_identique`.
- Aucune alerte en cours. Aucun Job de scan nouveau depuis le seuil n° 4.
- `releve-dates.py verifier`, après le push et avant les commits : identique à git, 0 ligne différente.
- Dernier état mesuré : [seuil n° 4](e5-seuil-4.log) (11:34:27Z, 105 valeurs, 0 écart, 43 signatures).

## Attendu

| Mesure | Attendu |
|---|---|
| `kpi_signatures_verifiees{…f5e6bcb0…, famille="vsa"}` | 0 → 1, 0 refusée |
| `kpi_l3_verifie` et `kpi_replay_identique` de `f5e6bcb0` | 0 → 1 |
| `taux_l3_verifie`, `taux_replay_identique` | 1/4 → **2/4**, 2/4 → **3/4** |
| `taux_provenance_chains_verifiee` | inchangé, 4/4 |
| Toutes les autres séries, hors date de passage et de journal | inchangées contre le seuil n° 4 |
| Seuil (`e5-seuil-5.log`) | 105 valeurs, 0 écart ; 44 signatures vérifiées, 0 refusée, clé étrangère 0 ; HTTP 200, codes 0 |
| `ScanEnRetard` | pas d'alerte |

**Réfuté si** : un écart recalcul contre exportateur, une signature refusée, ou une série changée hors de celles de ce tableau et des dates de passage et de journal.

**Non valable si** : aucun passage de l'exportateur daté d'après 18:15:19Z n'existe au moment du seuil ; dans ce cas, attendre le suivant.
