# VSA de la construction du rejeu complet de la 08 : prédictions (écrites le 03/11/2026 vers 23:17 UTC, avant toute exécution)

Choix du propriétaire : « VSA sur 3a7ca1b1 ». Préparé à sec : rien n'a encore été lancé ni poussé.

## Ce qui change, et ce qui ne change pas

- **Image** : la même, `builds/sample-app@3a7ca1b1…`. Le rejeu complet de la 08 l'a reconstruite à l'identique sur la fermeture de la plateforme.
- **Provenance rejouée** : `c4242a11-18f6-439f-b947-7fe3d4319078`, au lieu de `d9006af7…`. C'est J7 du rejeu complet, du 03/11/2026 21:25:30 à 21:26:27 UTC.
  - Le tag `.att` porte cinq provenances de PipelineRun à 10 entrées : `c4242a11` (J7), puis `f07ef252`, `2b808c1a`, `8accfebc` et `aebe714b` (tests de J8). Relevé à 23:14 UTC.
  - Leurs `resolvedDependencies` ont des digests identiques (même empreinte de la liste). Le choix de J7 ne change donc aucune entrée. La porte, elle, juge la dernière de l'index : `aebe714b`.
  - `horodatage/bundles` compte 41 bundles de `3a7ca1b1`, avec un seul bundle par invocationId, dont un seul pour `c4242a11`. `vsa.py` exige exactement un bundle.
- **Entrées déclarées** par `c4242a11`, lues sans vérification à 23:13 UTC :

  | Entrée | Digest |
  |---|---|
  | fermeture `builds/fermetures/sample-app` | `74c265e7…` |
  | `construire-image` | `66a9f298…` |
  | `preparer-entrees` | `2070d601…` |
  | `web-dist` | `47f72275…` |
  | `builder-go-voie-d` | `d50ae575…` |
  | commit | `6391fd43…` |

  Par rapport à R3 du 03/11, quatre choses changent :
  - la fermeture (`0ab5a507…` sous `entrees/sample-app/fermeture`) ;
  - le bundle `construire-image` (`403ccbd8…`) : seul son emballage change, avec une couche compressée. Sa recette est identique, relevée à 23:16 UTC : Dockerfile `d56985c1…`, mêmes options de `buildctl` ;
  - la clé de Chains et la chaîne de la TSA, régénérées par le rejeu de zéro ;
  - `preparer-entrees` ne change pas : il a le même digest que dans `r4-rebuild.log`.
- **Code** :
  - `outils/entrees.py` et `outils/verifier_entrees.py` (fonction `est_entree`) reconnaissent maintenant la fermeture sous `builds/fermetures/` ;
  - la politique est révisée (§1.5 et Limites), ce qui demande un nouveau `POLITIQUE_COMMIT`, poussé avant R5 ;
  - `rebuild.sh` et `vsa.py` restent inchangés.

## Prédictions

**R3 (`JALON=r3 … transporter verifier_entrees`)**

- 41 bundles transportés, 41 vérifiés hors réseau avec la nouvelle clé de Chains ;
- provenance `c4242a11` extraite d'un bundle vérifié ;
- section 1 de la politique conforme, avec les six entrées déclarées listées ci-dessus ;
- digests transportés égaux ; commit `6391fd43…` ;
- Dockerfile `d56985c1…` ; `go1.26.10` des deux côtés ;
- `finishedOn` à `2026-11-03T21:26:27Z` ;
- 0 KO.

**R4 (`JALON=r4 … rebuild`)**

- refusé avant le **04/11/2026 à 21:26:27 UTC** ;
- ensuite, lien coupé pendant 1 200 s, sortie de la VM inchangée, `PASSED`, image reconstruite `3a7ca1b1…` (même recette et mêmes entrées, à la fermeture près ; son contenu, les fichiers des modules, est celui que la 03 reproduit).

**R5**

- `vsa` : énoncé signé avec `inputAttestations` = le bundle de `c4242a11`, et `timeVerified` au moins 24 h après `finishedOn` ;
- `pousser_vsa` : second manifeste dans `builds/vsa/sample-app` (`poc-replay` n'a pas le droit de supprimer) ;
- contrôle 6 de la porte : `ok|2/2 VSA retenue(s)` si l'ancienne VSA reste. L'attendu `1/1` de `preuves.sh controle6` sera alors à réécrire ;
- `porte_apres` : même verdict qu'en `porte_avant`. Les champs comparés (3 à 5, 7 et 8) ne contiennent pas le nombre de VSA.

## Limite qui demeure

Chaque rejeu de zéro régénère la clé de Chains et les invocationId. La VSA que `POUSSER_VSA=1` re-poussera pointera donc de nouveau vers un bundle disparu, comme celle de `d9006af7` aujourd'hui : son `inputAttestations` `horodatage/bundles@f5969ecf…` répond 404, relevé à 23:14 UTC.

## Résultat de R3 (03/11/2026, 23:20 UTC)

Conforme à toutes les prédictions de R3 : 41/41 bundles, provenance `c4242a11`, entrées et digests attendus, Dockerfile `d56985c1…`, `go1.26.10`, `finishedOn` à 21:26:27 UTC, 0 KO.

## Résultat de R4 (04/11/2026, 21:26:33 à 21:46:36 UTC, accord du propriétaire : « 3a ») : [`r4-rebuild.log`](r4-rebuild.log)

Conforme aux prédictions de R4, du premier coup :
- lancé 1 440 min après `finishedOn`, le délai de 24 h est tenu ; `rebuild.sh` `a1945ff2…` ;
- lien coupé pendant 1 200 s, de 21:26:34 à 21:46:34 UTC ; sortie de la VM inchangée (`tx_bytes=2524076`, `tx_packets=23504`) ; porteuse à 0 au début et à la fin ;
- **`PASSED`** : image reconstruite `3a7ca1b1…`, égale au sujet de la provenance `c4242a11`, en 16 s ;
- binaire `e3749c68…` identique avec le second moteur (`go build`), options identiques au `RUN` du Dockerfile signé ;
- rebuild terminé à 21:27:41 UTC, avant le rétablissement du lien ; `sortie=code 0`.

Le journal remplace celui de `d9006af7`, qui reste dans l'historique git (`4306ff3` et avant). Rien n'a encore été signé ni poussé pour cette provenance : R5 attend l'accord du propriétaire.

## Résultat de `vsa` et de `porte_avant` (04/11/2026, 22:09 à 22:10 UTC, accord du propriétaire : « Oui »)

**`vsa`** ([journal](r5-vsa.log)), 0 KO :
- politique figée `6c44219`, `143c6227…` ;
- bundle de `c4242a11` retrouvé parmi 41, revérifié dans la VM (signature de Chains et jeton de la TSA) ;
- `inputAttestations` : `horodatage/bundles@sha256:d09de125…`, présent dans Zot, de sujet `3a7ca1b1…` ;
- `timeVerified` `2026-11-04T21:27:33Z`, soit 24 h et 66 s après `finishedOn` ;
- `PASSED` ; signé par la clé du domaine et revérifié, sans journal de transparence ni horodatage ;
- énoncé `17a75bdd…`, bundle `2a55e529…`.

**`porte_avant`** ([journal](r5-porte_avant.log)), 0 KO, sans la VSA nouvelle : `VERDICT|reelle-avant|true||trusted_task.tagged|61|ok|10/10 enveloppe(s) couverte(s), 41 bundle(s) vérifié(s)…|ok|1/1 VSA retenue(s)…`. Referrers : `builds/sample-app` 0, `builds/vsa/sample-app` 1.

**Prédictions de `pousser_vsa` et de `porte_apres`, écrites à 22:10 UTC, avant le push** :
- manifeste **`sha256:69a2b10326017d997ace216a789c1d9c4820a4a5f4440aa60f724e95c7682d9b`**, calculé d'avance à partir du format de celui du 03/11 ; rien de nouveau dans `builds/sample-app`, aucun tag ;
- `builds/vsa/sample-app` passe à 2 referrers, `c1bfbcbd…` et ce manifeste ;
- `porte_apres` : champs 3 à 5, 7 et 8 identiques à ceux de `porte_avant`, et contrôle 6 à `ok|2/2 VSA retenue(s)` ;
- `lire_vsa` : les deux VSA vérifiées par la clé du domaine, clé de Chains refusée, connexions de cosign vers Zot seulement.

## Après R5 : ce qu'il faudra adapter (relevé à sec le 04/11/2026 à 18:14 UTC, rien modifié)

R5 réécrit les fichiers `r5-vsa.log`, `r5-vsa-enonce.json`, `r5-vsa.bundle.json`, `r5-vsa-manifeste.json`, `r5-pousser_vsa.log`, `r5-porte_avant.log`, `r5-porte_apres.log` et `r5-lire_vsa.log`. Ceux de la VSA `c804d946` restent dans l'historique git. Points qui les citent ou qui en dépendent :

- `08-trust-plane/preuves.sh` (contrôle 6, C1) : l'attendu `ok|1/1 VSA retenue(s)` devient `ok|2/2` tant que l'ancienne VSA reste dans Zot ;
- `08-trust-plane/resultats/controle6-predictions.md` : il cite l'énoncé `c804d946…` et `1/1`. Ces valeurs seront corrigées en additif, sans réécrire le texte ;
- `19b-journalisation/journalisation.sh` (L7) : `VSA_MANIFESTE` (`c1bfbcbd…`), `TIME_VERIFIED` (`2026-11-03T14:27:05Z`) et la fenêtre du 03/11/2026 de 14:00 à 16:00 UTC sont à remplacer par ceux du nouveau push ;
- `03-deps-closure/bascule.sh` (étape `construire`) : le CONSTAT affiché sans condition (« atteste le rejeu de la provenance de J7 (fermeture de l'hôte) ») n'est plus exact pour la nouvelle VSA. Il est à reformuler ;
- `08-trust-plane/rejeu.sh` (`POUSSER_VSA=1`) re-pousse `r5-vsa.bundle.json`. Au prochain rejeu de zéro, ce sera la nouvelle VSA, avec la limite décrite plus haut.
