# Brique 20 : `fuites.sh` et les secrets des 07a, 09 et 10, prédiction

Prédiction écrite le 2026-11-25T09:30:45Z, avant tout lancement. Décision du propriétaire du 25/11/2026 : « Oui » à « Étendre fuites aux secrets des 07a, 09 et 10, à sec, maintenant ? ».

`fuites.sh` (08) cherche en plus 6 fichiers, nommés d'après les scripts qui les créent (aucun dossier listé) :

| Étiquette | Créé par |
|---|---|
| `07a-zot-poc-vex.password` | `piece4-vex-zot.sh` |
| `07a-openbao-proprietaire.password` | fichier lu par `rejeu.sh` et `piece8-signer.sh` |
| `09-zot-poc-lien.password` | `o5-zot.sh` |
| `09-openbao-lien.secret` | `o5-openbao.sh` |
| `09-cle-openpgp.asc` | `o2.sh` |
| `10-zot-poc-replay.password` | `replay.sh` (`compte_zot`) |

Absent ou vide : dit, non cherché. Les motifs de moins de 16 caractères sont écartés : la ligne de contrôle d'une clé armurée en ferait de faux. Un fichier sans ligne de 16 caractères est dit, non cherché.

Banc sec (`essai-fuites.sh`, journal `e10-essai-fuites.log`) : HOME jetable, faux secrets, faux `ssh.sh` ; aucun vrai secret lu, aucune VM jointe. **Attendu : 23 cas, 0 écart** (3 + 3 + 1 + 3 + 7 + 1 + 1 + 3 + 1).

| Section | Attendu |
|---|---|
| 1 à 4 (e8, inchangées) | comme le 24/11 : 10 cas |
| 5 | 6 étiquettes × 3 VM = 18 lignes à 0, code 0 ; puis, pour chacune, une fuite sur `sc-confiance` : code 1, compte 1 sur `sc-confiance`, 0 sur `sc-build`, aucune autre étiquette touchée, valeur absente de la sortie |
| 6, témoin : fuite du secret de la 10, `fuites.sh` de `000edd4c` | code 0 (le défaut existait) |
| 7 | en-tête, pied et ligne de contrôle d'une clé armurée dans un journal : code 0, compte 0 |
| 8 | absents, puis vides : code 0, 6 lignes « absent ou vide » ; trop court : code 0, 1 ligne « aucune ligne de 16 caractères » |
| 9 | dossier de motifs effacé |

Non mesuré ici : le passage sur les vraies VM (ssh, accord du propriétaire). Non cherchés, dit dans l'en-tête : hachages htpasswd, copie base64 du compte de `poc-lien`, certificat de révocation OpenPGP, clé de la VSA (dans `sc-replay`).

## Premier passage, non valable en section 5 (note de 2026-11-25T09:30:58Z)

[23 cas, 0 écart](e10-essai-fuites.log), mais les 6 cas « fuite de … » portent tous sur `10-zot-poc-replay.password` : `neuf()` écrasait la variable `e` de la boucle. Cinq étiquettes n'ont donc pas été éprouvées. Banc corrigé (`local e`), `fuites.sh` inchangé, relancé avec `SUFFIXE=-2` : **attendu toujours 23 cas, 0 écart, cette fois une étiquette différente par cas**.

## Résultat (note de 2026-11-25T09:31:44Z)

[Second passage : 23 cas, 0 écart](e10-essai-fuites-2.log), 09:31:01 à 09:31:04 UTC, une étiquette différente par cas en section 5. Les témoins des sections 3 et 6 ont bien exécuté l'ancien `fuites.sh` : la ligne « aucun secret dans les journaux » y est 2 fois.

Mutants, joués hors du dépôt à 09:31:13 et 09:31:16 UTC (journaux non archivés) : sans le filtre de 16 caractères, 7 écarts ; en-têtes armurés gardés, 1 écart (section 7). Limite du banc : les témoins des sections 3 et 6 n'attendent que « code 0 », qu'un script vide rendrait aussi ; c'est la ligne citée ci-dessus qui prouve leur exécution.

`archive-vsa.patch` s'applique encore (`git apply --check`) ; `releve-dates.py verifier` : 0 ligne différente. **Jamais lancé sur les VM.**
