# Brique 09, O5 réel, premier accord : prédictions de la clé Transit `lien`

Écrites le 19/11/2026 à 19:38:21 UTC, avant tout accès au cluster.

**Accord.** Le propriétaire a été interrogé : « Accordez-vous la création d'une clé Transit `lien` dans OpenBao, réservée à l'attestation de lien ? ». Il a répondu « Oui » avant l'heure ci-dessus.

L'accord couvre **la clé seule**. Il ne couvre ni politique, ni jeton, ni rôle (deuxième accord), ni lecture de Zot (troisième accord).

**Mécanisme.** [`o5-openbao.sh`](../o5-openbao.sh) reprend la fonction `racine` de la 07a et de la 08 : le script lit le jeton root et le passe sur l'entrée standard de `kubectl exec` dans `openbao-0`. La session ne le lit pas. La clé est créée comme `scanner` (07a, G3) et `tsa` (08) : `ecdsa-p256`, `exportable=false`, `allow_plaintext_backup=false`. C'est le type qu'attend la voie `hashivault://` de cosign.

**Banc hors cluster** ([o5-openbao-banc.sh](../o5-openbao-banc.sh)), avec un faux `kubectl`, un faux `bao` et un jeton factice :
- **Premier passage**, à 19:37:12 UTC : 14 OK, 1 KO ([journal](o5-openbao-banc-premier-passage.log)). La clé publique exportée avait un saut de ligne de plus, ajouté par `jq -r`. Corrigé avec `jq -j`, qui écrit les octets exacts de la chaîne d'OpenBao.
- **Deuxième passage**, à 19:37:39 UTC : 15 OK. Ce journal a été remplacé par le passage suivant.
- **Troisième passage**, à 19:37:56 UTC, après l'ajout du contrôle K4 (valeur du jeton absente du journal) : 15 OK, 0 KO, sur le script final `6537f746…` ([journal](o5-openbao-banc.log)).
- **Cas couverts** : nominal ; relance ; clé présente ; OpenBao scellé ; écriture qui modifie une autre clé ; clé exportable. Le faux `bao` refuse tout appel sans le jeton attendu.

## `releve` (lecture seule)

| N° | Prédiction | Confiance |
|---|---|---|
| R1 | OpenBao initialisé et descellé, version 2.7.2 (`BAO_ID` d'`openbao.sh`, 08) | moyenne-haute : version non relue depuis la 08 |
| R2 | Clés Transit : exactement `chains`, `scanner` et `tsa`, toutes `ecdsa-p256`, non exportables. `autre` n'est pas une clé : c'est l'écriture refusée d'un témoin (journaux de rejeu de la 08) | moyenne : versions (rotation) et clés d'autres briques non relues |
| R3 | `transit/keys/lien` est absente, et `resultats/lien-cle-publique.pem` aussi | haute |
| K | K3 et K4 tenus ; aucune ligne KO | haute |

## `cle_lien` (une seule écriture, lancée seulement si R1 et R3 sont tenues)

| N° | Prédiction | Confiance |
|---|---|---|
| C1 | `bao write -f transit/keys/lien type=ecdsa-p256 exportable=false allow_plaintext_backup=false` : code 0 | haute : même commande que `scanner` en 07a |
| C2 | Relecture : `ecdsa-p256,false,false,false,1,true` (type, exportable, sauvegarde en clair, suppression, version, signature) | haute : mêmes valeurs mesurées pour `scanner` |
| C3 | Clé publique P-256 exportée dans `resultats/lien-cle-publique.pem`, lisible par openssl ; son empreinte SPKI est relevée, pas prédite | haute |
| C4 | Clés Transit après = clés avant + `lien ecdsa-p256 1 false` ; les autres sont inchangées | haute |
| K | K3 et K4 tenus ; aucune ligne KO | haute |

**Après.** Aucun compte ni pod n'a encore le droit de signer avec `lien` : la politique et le jeton relèvent du deuxième accord. La clé n'est pas supprimable (`deletion_allowed=false`) ; la retirer demanderait de changer sa configuration avec le jeton root.

## Note datée du 19/11/2026, 19:39:00 UTC : `releve` et `cle_lien` passées, toutes les prédictions tenues

**`releve`**, de 19:38:33 à 19:38:34 UTC, code 0 ([journal](o5-openbao-releve.log)).
- **R1 tenue** : OpenBao 2.7.2, initialisé et descellé.
- **R2 tenue** : exactement `chains`, `scanner` et `tsa`, toutes `ecdsa-p256`, version 1, non exportables.
- **R3 tenue**.
- **K tenue** : K3 et K4.

**`cle_lien`**, de 19:38:38 à 19:38:42 UTC, code 0 ([journal](o5-openbao-cle_lien.log)).
- **C1 tenue** : code 0. OpenBao 2.7.2 renvoie l'état de la clé dès l'écriture, clé publique comprise ; elle figure dans le journal, et c'est une clé publique. La clé a été créée à 2026-11-19T19:38:40Z, selon `creation_time`.
- **C2 tenue** : `ecdsa-p256,false,false,false,1,true`.
- **C3 tenue** : clé publique P-256 dans [`lien-cle-publique.pem`](lien-cle-publique.pem). Fichier sha256 `e661718dc8f97d9981ecc398277021ac43281a900ff67e3ad74794633bd0cce9` ; SPKI sha256 `42529342ceb102ad76f45285b2655d38265eebbe0c956f53706dcedf08e8d861`.
- **C4 tenue** : seule `lien` est ajoutée ; `chains`, `scanner` et `tsa` sont inchangées.
- **K tenue**.

**État.** La clé `lien` existe dans OpenBao, mais aucun compte n'a le droit de signer avec : il n'y a ni politique, ni jeton, ni rôle. Rien n'est écrit dans Zot.

**Suite d'O5 réel**, à accorder dans cet ordre :
1. un jeton OpenBao borné à `transit/sign/lien` (et à la lecture de `transit/keys/lien`), avec sa politique ;
2. un accès en lecture à Zot.
