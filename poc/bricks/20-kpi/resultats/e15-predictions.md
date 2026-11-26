# Brique 20 : application des correctifs de genre(), prédictions (2026-11-26T10:40:27Z)

Choix du propriétaire du 2026-11-26 (verbatim) : « Patchs de genre() ». Il ouvre le chantier. Il ne vaut pas accord de pose
sur sc-stockage (sudo), qui sera demandé à part.

Les deux correctifs ont été mesurés à sec le 25/11 ([e13](e13-predictions.md), second passage retenu, dépôt `5e7f07eb`) :
- `genre-temoins.patch` ;
- `genre-chains-v0300.patch`.

Contrôle de la base, lu à 10:39Z : aucun commit depuis `5e7f07eb` ne touche les deux correctifs ni leurs quatre fichiers
cibles (`metrics_exporter.py`, `recalcul.py`, `banc.sh`, `banc_comparer.py`), et `git apply --check` passe pour les deux. Les
mutants de G3 portent donc sur le code qui sera commité.

Seul `kpi-pose.sh` (étape `pose`) compare l'exportateur du dépôt à celui de sc-stockage. Entre le commit et la pose,
sc-stockage garde l'exportateur `98f917ab…`, et aucun script ne refuse.

Gain : latent. Tant que Chains reste en v0.29.9, les noms lus sont `pipelineTask`, et aucune série ne change (G6 de e13 :
301 lignes, 0 différente).

| N° | Mesure | Prédiction |
|---|---|---|
| H1 | correctifs appliqués par `git apply` | 4 fichiers changés ; exportateur à l'empreinte `fc0b8e0d…`, celle du second passage de e13 |
| H2 | `banc.sh`, `SUFFIXE=-4` | code 0 ; 5 bilans ; comparaison 25 cas, 0 écart (G2 de e13) |
| H3 | `releve-dates.py verifier` | à jour (les correctifs ne touchent ni pins ni clés) |
| H4 | `kpi-pose.sh sec` | code 0 ; 12 fichiers à poser ; exportateur à poser `fc0b8e0d…` |

`banc-genre.sh` ne pourra plus s'appliquer sur HEAD une fois les correctifs commités : ses journaux e13 restent la mesure.

Après accord seulement, prédit pour la suite :
- **H5** (`kpi-pose.sh pose`) : 0 KO ; exportateur installé identique au dépôt ; premier passage réussi ; 0 signature refusée,
  0 clé ni pin sans date ;
- **H6** (`kpi-pose.sh verif`) : 0 KO ;
- **H7** (`seuil.sh`, après un passage de l'exportateur posé) : 105 valeurs, 0 écart.

## Résultat, partie hôte (note de 2026-11-26T10:41:18Z)

Correctifs appliqués à 10:40:44Z sur `7278d746`.

| N° | Journal | Mesuré |
|---|---|---|
| H1 | `git diff --stat` (hors journal) | exportateur `fc0b8e0d…`, comme prédit ; **5 fichiers changés et non 4** : `genre-temoins.patch` touche aussi `banc_temoins.py` (deux lignes). Faute de la prédiction, qui comptait les fichiers cibles de e13 de mémoire |
| H2 | [banc](e4-banc-4.log) | code 0, 5 bilans, 25 cas, 0 écart |
| H3 | (hors journal) | `releve-dates.py verifier` : à jour |
| H4 | [sec](e15-sec.log) | tenu : 12 fichiers à poser, aucune clé privée, exportateur à poser `fc0b8e0d…`. Passage fait avant le commit des correctifs (arbre de travail) |

Écart dépôt/VM : ouvert à partir du commit des correctifs. sc-stockage garde `98f917ab…` jusqu'à la pose.

Complément (2026-11-26T10:42Z) : `banc_temoins.py`, cinquième fichier, n'était pas dans le contrôle de la base. `git log
5e7f07eb..7278d746` ne le montre dans aucun commit : la base des mutants de e13 tient pour les cinq fichiers.

## Résultat, pose (note de 2026-11-26T10:55:26Z)

Accord du propriétaire du 2026-11-26 (verbatim) : « Pose ». Il porte sur la question « Je pose l'exportateur corrigé sur
sc-stockage (sudo, commit faf63450) ? ».

| N° | Journal | Mesuré |
|---|---|---|
| H5 | [pose](e15-pose.log), 10:54:04Z à 10:54:16Z | tenu, 0 KO. `metrics_exporter.py` installé identique (`fc0b8e0d…`), `lecteur_loki.py` aussi. Premier passage réussi pour `kpi-journal` et `kpi`, timer actif. Le compte `kpi` ne lit pas le mot de passe. 0 signature refusée, 0 clé ni pin sans date. Exposition systemd : 3,0 pour `kpi.service`, 2,9 pour `kpi-journal.service` |
| H6 | [verif](e15-verif.log), 10:54:24Z, puis [verif -2](e15-verif-2.log), 10:56:46Z | premier passage non valable (voir plus bas) ; second passage tenu : 134 séries `kpi_*`, passage et journal de moins de 20 min, 0 refus |
| H7 | [seuil -7](e5-seuil-7.log), 10:55:00Z | tenu : 105 valeurs, 0 écart ; passage vu par Prometheus vieux de 46 s (10:54:14Z, celui de la pose) |

**H6 rejoué, même défaut.** Le premier `verif` (10:54:24Z) a tourné six secondes avant le seuil -6. Il lisait donc très
probablement l'ancien passage, et il ne compte pas pour H6. Il est rejoué dans [verif -2](e15-verif-2.log) à 10:56:46Z,
après la lecture de 10:54:14Z par Prometheus : tenu, 134 séries, passage et journal de moins de 20 min, 0 refus.

Réserve : le seuil -7 lit le passage lancé à la main par la pose. Aucun passage déclenché par le timer avec le nouvel
exportateur n'est observé ici.

Passage non valable, gardé : le [seuil -6](e5-seuil-6.log), lancé à 10:54:30Z, a lu dans Prometheus le passage de 10:51:19Z
(« âge du passage 191 s »). C'était le dernier passage de l'ancien exportateur `98f917ab…`, avant que Prometheus ait relevé
celui de la pose. Il rend lui aussi 105 valeurs et 0 écart, mais ne mesure pas le nouvel exportateur. La faute vient de
l'ordre de lancement : j'ai lancé le seuil sans contrôler l'âge du passage, contre la règle déjà écrite (« planifier un
seuil après un passage de l'exportateur »). Avant le -7, une requête de l'auditeur a lu 10:54:14Z comme dernier passage
(10:54:56Z, hors journal).

L'écart dépôt/VM est fermé : sc-stockage porte l'exportateur du commit `faf63450`. Le gain reste latent tant que Chains est
en v0.29.9.

Heures : 10:40:27Z à 10:41:36Z (prédiction, application, banc, sec, commits), puis 10:54:04Z à 10:55:26Z (pose, verif,
seuils, notes), soit 2 min 31 s. La lecture des correctifs et la préparation, du choix jusqu'à 10:40:27Z, n'ont pas de
`date -u` : elles ne sont pas mesurées. L'attente de l'accord n'est pas comptée, et le temps de la question non plus.
