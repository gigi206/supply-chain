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
