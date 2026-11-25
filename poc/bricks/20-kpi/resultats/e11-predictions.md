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

## Résultat (note de 2026-11-25T11:36:14Z)

[Seuil n° 4](e5-seuil-4.log), lancé à 11:34:27 UTC, codes 0, HTTP 200. Condition de validité tenue : fin du Job à 11:19:04, passage de l'exportateur à 11:34:00 (14 min 56 s après). Le compte du deb n'a pas été lu avant.

| Mesure | Attendu | Mesuré |
|---|---|---|
| Job du calendrier | 1 Job, 11:15:00, environ 2 min | `scan-sample-app-deb-29926755`, 11:15:00 à 11:19:04, réussi, 0 redémarrage : **4 min 04 s, écart** |
| Scans signés | deb 3 → 4, autres inchangés, 0 refusée | 4 ; `3a7ca1b1` 3, `f5e6bcb0` 3, rpm 0 ; 0 refusée |
| `kpi_scan_timestamp_seconds` du deb | entre 11:15 et 11:18 | 11:18:53 : **écart**, 53 s après la borne ; autres inchangés |
| Provenances, `sig`, VEX, VSA | inchangés (deb : 8, 1, 1, 1) | inchangés |
| Seuil | 105 valeurs, 0 écart, 43 signatures, clé étrangère 0 | 105 valeurs, 0 écart, 43 vérifiées, 0 refusée, clé étrangère 0 |
| KEV, taux | 0 ; 1/4, 4/4, 2/4 | 0 ; 1/4, 4/4, 2/4 |
| `ScanEnRetard` | pas d'alerte | aucune alerte en cours (11:35:31 UTC) |

**1 cause, 2 lignes en écart : la durée du Job.** Aucun critère « Réfuté si » n'est atteint et le seuil tient. Non prédit : entrées du deb, 67 dont 23 écartées, inchangé. Contre le seuil n° 3, hors date de passage et de journal, deux séries de Prometheus diffèrent : la date et le compte de scans du deb.

**Où est passé le temps** (journaux du conteneur `analyser`) : l'import de la base Grype a pris 219 s, contre 119 s à 09:30 avec le même digest de base (`8cc2d696`, 3465 Mo) et 111 s le 24/11 (base précédente, 3406 Mo). Le reste du Job a lui aussi ralenti (SBOM 4 s au lieu de 2).

**Cause non établie.** À 11:35:04, l'hôte avait une charge de 17,11 / 27,05 / 22,74 (1, 5 et 15 min) sur 16 cœurs, avec 71 % d'attente partielle d'entrées-sorties sur 10 s (`/proc/pressure/io`) ; un banc de mutations de la session Argo tournait (`porte.test`, `go`), avec les VM et l'application de bureau. Ces mesures sont prises 16 min après la fin du Job : compatibles, pas une preuve. Aucune mesure de charge pendant l'import n'a été trouvée (les séries `node_*` interrogées sont vides).

**Conséquence** : la durée d'un scan du calendrier dépend de la charge de l'hôte si cette cause est la bonne ; « environ 2 min » n'est pas une borne. Passages lus dans Prometheus : 11:03:06, 11:18:51, 11:34:00. Celui de 11:18:51 est antérieur à la fin du Job (13 s) : la condition sans marge l'aurait écarté aussi. La marge de 120 s n'a donc rien changé cette fois.
