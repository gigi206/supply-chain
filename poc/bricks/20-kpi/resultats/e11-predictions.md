# Brique 20 : scan du deb au calendrier (11:15 UTC), prédiction du seuil n° 4

Prédiction écrite le 2026-11-25T10:41:45Z, avant le passage de 11:15 UTC du 25/11/2026. Rien n'est lancé à la main : le CronJob `scan-sample-app-deb` tourne seul, puis `SUFFIXE=-4 seuil.sh` (lecture seule) est lancé après lui et après un passage de l'exportateur qui suit la fin du Job. Suite de [e9](e9-predictions.md).

## État lu le 25/11, entre 10:41:26 et 10:41:32 UTC

- `scan-sample-app-deb` : `15 11 * * *`, `Etc/UTC`, non suspendu, dernier passage le 24/11 à 11:15:00 (Job réussi à 11:17:06) ; aucun Job en échec dans l'espace `scan`.
- Aucune alerte en cours ; dernier passage de l'exportateur lu : 10:32:23.
- Dernier état mesuré : [seuil n° 3](e5-seuil-3.log) (09:49:12, 105 valeurs, 0 écart, 42 signatures).

## Attendu

| Mesure | Attendu |
|---|---|
| Job du calendrier | 1 Job nouveau `scan-sample-app-deb-<n>`, créé à 11:15:00, réussi, environ 2 min |
| Scans signés | deb 3 → 4 ; `3a7ca1b1` 3, `f5e6bcb0` 3, rpm 0 ; 0 refusée |
| `kpi_scan_timestamp_seconds` | deb passe au 25/11 entre 11:15 et 11:18 ; `f5e6bcb0` (1795599127) et `3a7ca1b1` (1795512718) inchangés |
| Provenances, `sig`, VEX, VSA | inchangés (deb : 8, 1, 1, 1) |
| Seuil (`e5-seuil-4.log`) | 105 valeurs, 0 écart ; 43 signatures vérifiées, 0 refusée, clé étrangère 0 ; HTTP 200, codes 0 |
| KEV, taux | 0 KEV ; `taux_l3_verifie` 1/4, `taux_provenance_chains_verifiee` 4/4, `taux_replay_identique` 2/4 |
| `ScanEnRetard` | pas d'alerte |

**Non prédit** : le nombre d'entrées du deb (67 dont 23 écartées au seuil n° 3). La base Grype peut en ajouter ou en retirer ; l'exportateur doit rendre le même nombre que le recalcul. Une entrée nouvelle sans VEX serait un constat à rapporter, pas un écart.

**Réfuté si** : un écart recalcul contre exportateur, une signature refusée, un Job en échec, ou un scan nouveau pour un autre sujet que le deb.

**Non valable si** : aucun passage de l'exportateur n'a eu lieu entre la fin du Job et le seuil ; dans ce cas, attendre.

**Condition de validité resserrée, note du 2026-11-25T10:44:25Z** (avant le scan, sur relecture du conseiller) : l'exportateur date son passage à la fin de son travail (`metrics_exporter.py`, juste avant l'écriture). Un passage commencé avant la fin du Job peut donc porter une date postérieure, et donner un faux écart (recalcul 4, exportateur 3). `kpi.service` est borné par `TimeoutStartSec=2min` : le seuil n'est lancé qu'après un passage daté de plus de 120 s après la fin du Job, sinon au passage suivant. Le compte du deb n'est pas lu avant le seuil.
