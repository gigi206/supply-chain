# G5 : prédictions (écrites le 04/11/2026 à 21:01 UTC, avant toute application)

Le contrôle 7 dans la porte de release. **Rien n'est appliqué** : ni la ConfigMap `porte`, ni `porte-job.yaml`, ni `politique.sh`, ni `preuves.sh`. G5 ne s'applique qu'après R5 de la 10, avec l'accord du propriétaire.

## Pourquoi un correctif, et pas une modification directe

`preuves.sh reelle`, joué par `porte_avant` et `porte_apres` de R5, passe par `juger` et `cm_porte`, et lit `porte-job.yaml` dans l'arbre de travail. Modifier ces fichiers avant R5 changerait la porte que R5 mesure. Les fichiers neufs sont donc dans la 07a ([`politique/porte/`](../politique/porte/)), que R5 ne lit pas. Les modifications de la 08 sont dans [`politique/g5-porte.patch`](../politique/g5-porte.patch), appliqué par `g5_porte`.

`g5_porte` refuse de tourner tant que `builds/vsa/sample-app` n'a pas de **nouvelle** VSA pour l'image. Le dépôt en contient déjà une, `c1bfbcbd…`, poussée le 03/11/2026 sur la même image : elle ne compte pas. Refus relevé dans [`g5_porte-refus-avant-r5.log`](g5_porte-refus-avant-r5.log), arbre inchangé.

## Conception

| Conteneur | Type | Image | Rôle |
|---|---|---|---|
| `porte` | initialisation, inchangé | porte | `ec validate image`, toujours premier : le champ 6 de VERDICT lit `initContainerStatuses[0]` |
| `scan-verifier` | initialisation, **neuf** | outils de J5 | énoncés de `builds/scan/<nom>` vérifiés par `scanner.pub`, écrits dans `/partage/scan-entree.json`. **Toujours le code 0** : un échec ici empêcherait `horodatage` et `vsa` de démarrer |
| `horodatage`, `vsa` | principaux, inchangés | outils de J5 | contrôles 9 et 6 |
| `scan` | principal, **neuf** | porte | `ec validate input` ; code non nul si refus. L'image n'a pas de shell, d'où deux conteneurs |

- **Le dépôt du scan** est dérivé du nom de l'image, comme dans `vsa.sh`. Une image hors de `builds/`, sous `builds/scan/` ou `builds/vsa/`, n'a aucun scan recevable.
- **Le choix du scan retenu** se fait dans [`scan.rego`](../politique/porte/scan.rego) : le shell ne fait que concaténer les énoncés vérifiés.
- **VERDICT** gagne les champs 11 (`ok`, `refus` ou `absent`) et 12 (détail). Les champs 1 à 10 ne bougent pas. Aucun lecteur ne lit le statut du Job : `preuves.sh`, `bascule.sh`, `declencheur.sh`, `replay.sh` et `rejeu.sh` vérifiés par `grep`.
- **`porte-temoin`** est une copie de `porte` par `jq` : elle hérite des quatre nouvelles clés. `bascule.sh` passe par `cm_porte`.

### Écarts au README

- Deux conteneurs au lieu d'un, pour la raison ci-dessus.
- Les règles de `bench.rego` jugent **le scan retenu**, pas tous les scans. Reprises telles quelles, elles refuseraient l'image pour une KEV d'un vieux scan, ce qui contredit D4.
- **Deux ajouts, à faire valider** :
  - `scan.forme` : un champ absent ou d'un mauvais type refuse, au lieu de faire passer les règles suivantes à vide ;
  - `scan.scan_recent` refuse aussi un scan daté de plus de 5 min dans le futur : il resterait retenu indéfiniment. D4 ne le demandait pas.
- `ec opa test` au lieu de `opa` : `opa` n'est pas installé, et `bascule.sh` de la 03 fait de même.

**Décision du propriétaire (04/11/2026, après 21:05 UTC, réponse « 2 a ») : les deux ajouts sont retenus.**

## Mesuré à sec (04/11/2026, entre 20:51 et 21:01 UTC, sur l'hôte)

**Règles** ([journal](g5_regles.log)) : 27 tests sur 27, et les 17 conditions retirées tour à tour font chacune échouer au moins un test.

**Trois défauts trouvés et corrigés avant le commit :**
- `base_recente` passait à vide si le seuil manquait : réécrite pour refuser ;
- les messages lisaient les seuils : sans eux, le message était indéfini et aucun refus ne sortait. `test_seuils_absents_refus` l'a montré ;
- les `%d` recevaient des flottants (`%!d(float64=…)`), visible sur l'image réelle avec des seuils à 0.

**Premier passage de `g5_regles`** ([archivé](g5_regles-premier-passage.log)) : un seul KO, la condition `vulnerabilities`, dont `kev` couvrait le cas de l'absence. `test_vulnerabilites_hors_tableau` la couvre désormais.

**Essai sur les images réelles** ([journal](g5_sec.log), 32 OK) : `scan-verifier.sh` dans le système de fichiers de `outils-horodatage@c7bebae2`, Zot lu en anonyme ; `ec` de `porte@e77994c2` (v0.10.42, même binaire que celui de mise), sans interface réseau.

| Cas | Résultat |
|---|---|
| Scan réel | 1 énoncé (`4d197192…`, 20:40:09), admis, 6 règles en succès |
| `builds/essai-webhook` | 0 énoncé, `scan.scan_present` |
| `builds/scan/…`, `builds/vsa/…`, `plateforme/…`, tag sans digest | 0 énoncé sans appel à cosign, `scan.scan_present` |
| Clé de Chains à la place de `scanner.pub` | 0 énoncé, `accepted signatures do not match threshold`, `scan.scan_present` |
| KEV ; VEX expiré | `scan.kev_without_vex` |
| VEX valide | admis |
| MAL- | `scan.malicious` |
| Scan trop vieux | `scan.scan_recent` |
| Base trop vieille | `scan.base_recente` |
| Prédicat sans `vulnerabilities` | `scan.forme` |
| Entrée au JSON invalide, ou absente | ec en erreur, code 1 : échec fermé |

Dans ce tableau, les cas KEV, VEX, MAL- et de fraîcheur modifient l'entrée après la lecture : la signature n'y est pas en jeu. Les témoins signés sont le rôle de G6.

**Premier passage de `g5_sec`** ([archivé](g5_sec-premier-passage.log)) : trois KO, tous dus au contrôle de l'essai, pas à la porte. Deux violations `scan.forme` n'étaient pas dédoublonnées, et une réponse vide de ec n'était pas classée « sans verdict ».

**Autres mesures :**
- `time.now_ns()` ne suit pas `--effective-time` : deux valeurs, même verdict. G6 ne peut donc pas simuler l'heure avec cette option, il lui faut un témoin signé à date ancienne ;
- ec rend son JSON sur la sortie standard et le code 1 en refus (`--strict` par défaut) ;
- RSS maximal de ec : 95 Mo, pour une limite de 512 Mi ;
- le correctif s'applique à l'arbre (`git apply --check`) et à une copie ; Job rendu avec les `sed` de `juger`, aucun marqueur restant, validé par `kubectl apply --dry-run=client --validate=strict` (schéma lu sur l'API, rien d'écrit) ;
- `initContainers : porte, scan-verifier ; containers : horodatage, vsa, scan`.

## Prédictions de `g5_porte`, à jouer après R5

`preuves.sh controle7` de la 08, prédiction par cas :

1. **ConfigMap** : `scan-verifier.sh`, `scan.rego`, `policy-scan.yaml` et `scanner.pub` identiques aux fichiers versionnés ; clé `8cbcbb4e…`.
2. **C1, image réelle, source attendue** :
   - champs 3 à 5 : `true||trusted_task.tagged` ;
   - champs 7 et 9 : `ok`, `ok` ;
   - champs 11 et 12 : `ok|1 énoncé(s) vérifié(s) dans sc-stockage.poc.test:5000/builds/scan/sample-app` ;
   - Job réussi. Le compte de 1 énoncé suppose qu'aucun autre scan n'a été publié d'ici là.
3. **C2, même digest dans `builds/essai-webhook`** : champ 11 `refus`, règle `scan.scan_present`, Job en échec.
4. **C3, clé de Chains dans `porte-temoin`** : ec et contrôles 9 et 6 inchangés, champ 11 `refus`, motif `accepted signatures do not match threshold`.

Les journaux de R5 restent ceux de la porte d'avant G5 : `g5_porte` ne les réécrit pas.

## Effets à connaître

- **Date limite du scan** : celui de G4 expire le **11/11/2026 à 20:40:09 UTC**. Après cette date, C1 rend `scan.scan_recent` tant qu'un scan n'a pas été refait : c'est le comportement voulu par D4.
- **La porte refuse toute image sans scan récent**, y compris pour les témoins de `preuves.sh` : leur Job échouera, mais ces étapes ne lisent que les champs 1 à 10. Le scan de chaque image réelle doit passer avant la porte. C'est l'objet de G7 dans `rejeu.sh`.
- **ConfigMap `porte`** : quatre clés de plus, réappliquée sans redémarrage. Si la ConfigMap est réappliquée sans le Job corrigé, ou l'inverse, le pod ne démarre pas ou le contrôle n'a pas lieu : `controle7` applique les deux ensemble.
- **Le correctif porte sur un état précis.** Les adaptations d'après R5 de `preuves.sh` (contrôle 6 à `2/2`) touchent un passage hors de son contexte, mais `g5_sec` rejoue `git apply --check` : un KO demanderait de le régénérer.
- **`g3_cluster`** retirerait `scanner.sh` et `scanner.pub` de `scan-config` s'il était rejoué : à traiter en G7. D7 (rétention) reste ouverte : chaque scan s'ajoute à la liste que `scan-verifier` relit.

## Non joué à sec

- Le Job réel dans le cluster : utilisateur 65532, racine en lecture seule, volumes `emptyDir`, liens symboliques de la ConfigMap sous `/etc/porte/regles-scan`. Le précédent est `/etc/porte/regles`, mais il n'est pas prouvé pour ce nouveau dossier.
- Le nom `sc-stockage.poc.test` : l'essai lit Zot par son adresse. Le précédent est `vsa.sh`.
- Un bundle invalide dans `builds/scan/` à côté d'un bundle valide : prévu en G6.
- Plusieurs scans réels : `scan.rego` est testé, mais la lecture n'a vu qu'un seul énoncé.
