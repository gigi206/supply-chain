# Brique 20 : premier scan du calendrier sous l'exportateur posé, prédiction

Prédiction écrite le 2026-11-25T06:53:38Z, avant le passage de 09:30 UTC du 25/11/2026. Rien n'est lancé à la main : le CronJob `scan-sample-app` tourne seul, puis `SUFFIXE=-3 seuil.sh` (lecture seule) est lancé après lui et après un passage de l'exportateur.

## État lu le 25/11 à 06:53 UTC (Prometheus par l'auditeur, cluster en lecture)

- 0 alerte en cours ; dernier referrer de scan : `sample-app` le 24/11 à 14:12:32, `sample-app-deb` le 24/11 à 13:42:43 ; base Grype construite le 24/11 à 06:22:05.
- Cibles lues dans les CronJobs : `sample-app@f5e6bcb0e0fb` (09:30) et `sample-app-deb@60f25f5c3fb5` (11:15). `3a7ca1b1` et le rpm ne sont scannés par aucun CronJob.
- Signatures de scan vérifiées : `3a7ca1b1` 3, `f5e6bcb0` 2, deb 3, rpm 0. Entrées : `f5e6bcb0` 5 dont 5 écartées, deb 67 dont 23 écartées.
- Alerte `ScanEnRetard` : 26 h sans nouveau referrer, puis 5 min. Sans scan, elle sonnerait le 25/11 après 15:42:43 (deb) et 16:12:32 (sample-app).

## Attendu après 09:30 (avant 11:15)

| Mesure | Attendu |
|---|---|
| Job du calendrier | 1 Job nouveau `scan-sample-app-<n>`, créé à 09:30:00, réussi, environ 2 min comme le 24/11 (09:30:00 à 09:32:07) |
| Signatures de scan vérifiées | `f5e6bcb0` 2 → 3 ; `3a7ca1b1` reste 3, deb reste 3, rpm reste 0 ; 0 refusée |
| `kpi_scan_timestamp_seconds` | `f5e6bcb0` passe au 25/11 entre 09:30 et 09:33 ; les autres inchangés |
| Provenances, `sig`, VEX, VSA | inchangés (`f5e6bcb0` : 8, 1, 1, 0) |
| Seuil (`seuil.sh`, `e5-seuil-3.log`) | 4 sujets, 0 écart entre recalcul et exportateur ; 42 signatures vérifiées au lieu de 41 ; clé étrangère 0 ; HTTP 200, codes 0 |
| KEV, taux | 0 KEV ; `taux_l3_verifie` 1/4, `taux_provenance_chains_verifiee` 4/4, `taux_replay_identique` 2/4 |
| `ScanEnRetard` | pas d'alerte |

**Non prédit** : le nombre d'entrées de `f5e6bcb0` (5 au 24/11) et les VEX appliqués. La base importée le 25/11 (archive de 08:00 UTC) peut ajouter ou retirer des entrées. Le nombre exact n'est pas l'objet : l'exportateur doit rendre le même que le recalcul. Une entrée nouvelle sans VEX serait un constat à rapporter, pas un écart.

**Réfuté si** : un écart recalcul contre exportateur, une signature refusée, un Job en échec, ou un referrer de scan nouveau pour un autre sujet que `f5e6bcb0` avant 11:15.

Le second scan (deb, 11:15) n'est pas l'objet de ce passage : `SUFFIXE=-4` ensuite, sur le même modèle (deb 3 → 4), seulement si l'heure s'y prête.

## Résultat (note de 2026-11-25T09:49:44Z)

Premier passage planifié à 09:36 UTC : **non lancé**, l'exportateur était passé à 09:31:47, avant la fin du Job. Reporté à 09:49, après son passage de 09:46:57. [Seuil n° 3](e5-seuil-3.log), 09:49:12 UTC : codes 0, HTTP 200.

| Mesure | Attendu | Mesuré |
|---|---|---|
| Job du calendrier | 1 Job, 09:30:00, environ 2 min | `scan-sample-app-29926650`, 09:30:00 à 09:32:16, réussi |
| Scans signés | `f5e6bcb0` 2 → 3, autres inchangés, 0 refusée | 3 ; `3a7ca1b1` 3, deb 3, rpm 0 ; 0 refusée |
| `kpi_scan_timestamp_seconds` de `f5e6bcb0` | entre 09:30 et 09:33 | 09:32:07 (referrer à 09:32:11) ; autres inchangés |
| Provenances, `sig`, VEX, VSA | inchangés | inchangés (8, 1, 1, 0) |
| Seuil | 0 écart, 42 signatures, clé étrangère 0 | 105 valeurs, 0 écart, 42 vérifiées, 0 refusée, clé étrangère 0 |
| KEV, taux | 0 ; 1/4, 4/4, 2/4 | 0 ; 1/4, 4/4, 2/4 |
| `ScanEnRetard` | pas d'alerte | aucune alerte (09:49:07 UTC) |

**0 écart avec la prédiction.** Non prédit : entrées de `f5e6bcb0`, 5 dont 5 écartées, inchangé. Contre le seuil n° 2, une seule série de Prometheus diffère hors dates (le compte de scans de `f5e6bcb0`).

**Portée** : l'exportateur suit un scan réel du calendrier. L'absence d'alerte ne prouve pas que `ScanEnRetard` sonnerait ; le retard n'a pas été provoqué. Le scan du deb (11:15) n'est pas mesuré.
