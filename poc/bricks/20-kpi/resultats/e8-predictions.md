# Brique 20 : `fuites.sh` et le mot de passe de `kpi-journal`, prédiction

Prédiction écrite le 2026-11-24T22:17:00Z, avant tout lancement.

`fuites.sh` (08) ne cherchait que les fichiers de `08/secrets`. Il cherche maintenant aussi `20/secrets/grafana-kpi-journal.password`, par son nom, sans lister le dossier. Absent ou vide : il le dit et continue.

Banc sec (`essai-fuites.sh`) : HOME jetable, faux secrets tirés au sort, faux `ssh.sh`. Aucun vrai secret n'est lu et aucune VM n'est jointe. **Attendu : 11 cas, 0 écart.**

| Cas | Attendu |
|---|---|
| 1, aucune fuite | code 0 ; les deux secrets cherchés sur les 3 VM ; pas de ligne « absent » |
| 2, fuite du mot de passe sur `sc-stockage` | code 1 ; compte 1 sur `sc-stockage`, 0 sur `sc-build` ; valeurs absentes de la sortie |
| 3, témoin : même fuite, `fuites.sh` de `40dccc25` | code 0 (le défaut existait) |
| 4, fichier absent, fichier vide, fuite d'un secret de la 08 | code 0 avec la ligne « absent ou vide » ; idem ; code 1 (non-régression) |
| 5 | dossier de travail effacé |

Non mesuré ici : le passage sur les vraies VM (ssh, accord du propriétaire). Les secrets des 07a, 09 et 10 ne sont pas cherchés non plus : constat du même relevé, choix à poser au propriétaire.

## Résultat (note de 2026-11-24T22:19:49Z)

[11 cas, 0 écart](e8-essai-fuites.log), 22:17:03 à 22:17:05 UTC. `essai-rejeu.sh` relancé : [12 cas, 0 écart](e7-essai-rejeu-3.log) ; `releve-dates.py verifier` : 0 ligne différente ; `archive-vsa.patch` s'applique encore (`git apply --check`).
