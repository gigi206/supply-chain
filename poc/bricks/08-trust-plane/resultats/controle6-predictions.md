# Contrôle 6 dans la porte de release : prédictions (03/11/2026, 15:25 UTC, avant exécution)

Demande : brique 10, choix du propriétaire du 03/11/2026 : « Contrôle 6 d'abord ». Le contrôle 6 de la grille C (ADR 0000 §4) exige une « VSA de replay présente, signée par la clé du domaine de replay, résultat `PASSED` ». Après R5, la porte de la 08 ne l'exige pas. Rien n'est appliqué au cluster ni écrit dans Zot avant l'accord du propriétaire.

## Chemin retenu

- **Hors de ec, comme le contrôle 9.** La règle Rego du banc C (`ec.sigstore.verify_attestation(input.image.ref, …)`) cherche la VSA dans le dépôt de l'image. Or elle est rangée dans `builds/vsa/sample-app`, et poser `COSIGN_REPOSITORY` sur ec redirigerait aussi la lecture de la signature et de la provenance.
- **Conteneur `vsa` dans le Job de la porte**, qui tourne en parallèle de `horodatage`, sur la même image d'outils (cosign v3.1.4).
  - Script : [`politique/porte/vsa.sh`](../politique/porte/vsa.sh), avec la commande de `lire_vsa` (R5) : `COSIGN_REPOSITORY`, clé du domaine, `--insecure-ignore-tlog`.
  - Le dépôt de la VSA est dérivé du nom de l'image (`builds/<nom>` vers `builds/vsa/<nom>`), pas fourni par l'appelant.
  - Un énoncé n'est retenu que si son sujet est le digest jugé, son `verifier.id` celui du domaine et son résultat `PASSED`. Il en faut au moins un.
- **Clé publique du domaine**, prise hors bande dans [`vsa-cle-publique.pem`](../../10-independent-replay/resultats/vsa-cle-publique.pem). Son empreinte DER, `578dd771…`, est celle du journal de R2. Elle est ajoutée par `cm_porte` à la ConfigMap `porte`.
- **`juger`** : ajout des champs 9 et 10 (`ok` ou `refus`, puis le détail). Les champs 1 à 8 ne changent pas, et leurs lecteurs les lisent par position.
- **Nouveau verdict de la porte** : succès de ec, horodatage complet **et** VSA retenue.
- **Grilles** : aucune note ne change. Le banc C est clos, ses notes sont définitives, et le contrôle 6 y était déjà couvert (17/17).

## Essai de plomberie sur l'hôte (15:21:27 à 15:24:51 UTC, heures des fichiers de l'essai ; non compté)

- **Forme de la sortie** (15:21:27) : `cosign verify-attestation` avec la commande de `lire_vsa` rend une ligne JSON par attestation, avec les clés `payload`, `payloadType` et `signatures`. `payload` décodé est l'énoncé signé, octet pour octet.
- **Lecture seule de Zot**, comme `lire_vsa`, avec `vsa.sh` sous busybox sh et les chemins `/etc/porte` remplacés.
  - image réelle : `RETENU`, empreinte de l'énoncé `c804d946…`, celle de `r5-vsa-enonce.json`, puis `VSA|ok|1/1` ;
  - même digest dans `builds/essai-webhook` : `refus`, 0/0, « no matching attestations » ;
  - clé de Chains : `refus`, « accepted signatures do not match threshold ».
- **Faux cosign local** (énoncés modifiés, rien poussé) : `FAILED`, autre sujet et autre `verifier.id` sont `ECARTE`, chacun avec son motif, ce qui donne un refus à 0/3. Avec l'énoncé réel en plus, on obtient `ok` à 1/4.
- **Défaut trouvé par l'essai et corrigé avant ces prédictions** : une erreur de cosign sans préfixe `Error:` (cosign absent, par exemple) n'apparaissait pas dans le motif. Le refus restait correct.

## Prédictions de `mise run confiance:preuves -- controle6`

- **ConfigMap `porte`** : réappliquée par `cm_porte`. `vsa.sh`, `vsa.pub` et `horodatage.sh` sont identiques aux fichiers versionnés.
- **Referrers** : 0 dans `builds/sample-app`, 1 dans `builds/vsa/sample-app`.
- **C1, image réelle avec la source attendue** :
  - ec `true`, aucune violation, avertissement `trusted_task.tagged` ;
  - contrôle 9 `ok` : 6/6 enveloppes ; 43 bundles attendus, un nombre plus grand n'est pas un écart ;
  - contrôle 6 : `ok|1/1 VSA retenue(s) dans sc-stockage.poc.test:5000/builds/vsa/sample-app`.
- **C2, `builds/essai-webhook@3a7ca1b1`** (même digest, sans source) :
  - contrôle 6 `refus`, avec « 0/0 VSA retenue(s) dans …/builds/vsa/essai-webhook », puis le motif de cosign « no matching attestations » ;
  - les champs de ec et du contrôle 9 sont consignés, pas prédits.
- **C3, image réelle avec la ConfigMap `porte-temoin`** (copie de `porte`, clé de Chains à la place de `vsa.pub`) :
  - ec et contrôle 9 identiques à C1 ;
  - contrôle 6 `refus`, avec « accepted signatures do not match threshold » ;
  - `porte-temoin` retirée ensuite.
- **Connexions** : le Job aboutit avec la NetworkPolicy `porte` inchangée (DNS et Zot), comme le contrôle 9.
- **Rien écrit dans Zot.** Bilan attendu : 0 écart.

## Effets à connaître avant d'accorder

- **La ConfigMap `porte` change durablement**, et le Job versionné porte le conteneur `vsa`. Après l'étape, toute image jugée par la porte sans VSA est refusée par le contrôle 6.
  - Images concernées : essai-webhook et les témoins des étapes `test7`, `test8`, `reglec`, `rc` et `ba`.
  - Les verdicts archivés restent valables. Une de ces étapes rejouée rendrait en plus `refus` au champ 9, sans changer ses champs 1 à 8 ni ses contrôles OK et KO, qui ne lisent pas le champ 9.
- **Choix inscrit dans le code** : une copie du même digest dans un autre dépôt (`essai-webhook`) n'est pas admise avec la VSA de `sample-app`. La VSA est cherchée dans `builds/vsa/<dépôt de l'image>`.
- **Hors du test** : une VSA signée mais `FAILED` dans le registre demanderait le push d'une VSA témoin (compte `poc-replay`, accord à chaque push). Le faux cosign couvre la logique, pas le registre.
