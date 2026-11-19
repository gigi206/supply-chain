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

# Deuxième accord : politique `lien-signature` et accès borné à la clé `lien`

*Écrit le 19/11/2026 à 19:49:18 UTC, avant tout lancement d'`acces_lien`.*

**Accord.** Question posée : « Accordez-vous le deuxième point : un jeton OpenBao et sa politique, bornés à la clé `lien` (signer avec elle et la lire, rien d'autre) ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus : « Oui ».

**Mes choix, que le « Oui » ne couvre pas mot pour mot** (à contester par le propriétaire) :
- **Jeton de service** : politique `lien-signature` seule, **sans la politique `default`**, orphelin, durée **72 h**, explicite et **non renouvelable**. Passé ce délai, il faudra le recréer avec la même étape, après retrait.
- **Révocation de soi** : la politique ([`politique/lien-signature.hcl`](../politique/lien-signature.hcl)) ajoute `auth/token/revoke-self`, comme `scanner-signature`. Ce droit **ne sera pas essayé**, puisque l'essai détruirait le jeton.
- **Stockage en clair** : le jeton est écrit par le script dans `~/.cache/supply-chain-poc/09/secrets/openbao-lien.secret` (0600), avec son accesseur à côté (`openbao-lien.accesseur`). Ni la session ni le journal ne voient sa valeur.
- **Vocabulaire du journal** : le masquage remplace toute ligne qui contient « jeton » ou « token ». L'étape s'appelle donc `acces_lien`, le fichier porte l'extension `.secret`, et le journal dit « secret lien ».

**Banc hors cluster** ([o5-openbao-banc.sh](../o5-openbao-banc.sh)) : faux `bao`, avec droits filtrés selon le jeton présenté et signature par une clé ECDSA jetable. Cinq passages ; les quatre premiers sont gardés avec leur cause :
1. **19:44:23 UTC, 28 OK et 3 KO** ([journal](o5-openbao-banc-jeton-premier-passage.log)). En cas d'échec, OpenSSL 4.1.0 écrit sa pile d'erreurs sur stderr avant « Verification failure ». Correction : seule la sortie standard est jugée.
2. **19:44:49 UTC, 30 OK et 1 KO** ([journal](o5-openbao-banc-jeton-deuxieme-passage.log)). Le chemin du banc et le nom d'étape `jeton_lien` contenaient « jeton », donc des lignes étaient masquées, dont l'heure de fin. Correction : l'étape devient `acces_lien`.
3. **19:45:30 UTC, 31 OK** ([journal](o5-openbao-banc-jeton-troisieme-passage.log)). Il restait une ligne masquée : le nom de fichier `openbao-lien.token`. Correction : `.secret`, et un verdict « aucune ligne masquée » est ajouté.
4. **19:45:47 UTC, 32 OK** ([journal](o5-openbao-banc-jeton-quatrieme-passage.log)). La relecture du conseiller a montré que, dans le cas « fuite », la valeur du secret factice atteignait la sortie standard : 1 occurrence, mesurée. K5 ne vidait le journal qu'après le `tee`. Correction : le journal est d'abord écrit en 0600 sans affichage, contrôlé par K3, K4 et K5, puis affiché. Le préfixe du secret n'est plus affiché (seulement « oui » ou « non »).
5. **19:48:47 UTC, 33 OK et 0 KO**, sur le script final `208c3e7d…` ([journal](o5-openbao-banc-jeton.log)). Le banc juge aussi la sortie du cas « fuite ».

**Le banc ne prouve pas les droits.** Le faux `bao` applique la liste que j'ai écrite. Les 11 essais seront mesurés pour la première fois sur le vrai OpenBao, après les deux écritures.

## Prédictions d'`acces_lien`

| N° | Prédiction | Confiance |
|---|---|---|
| J1 | OpenBao descellé ; clé `lien` toujours conforme ; clé publique égale à `lien-cle-publique.pem` ; politique `lien-signature` absente ; fichiers du secret absents | haute |
| J2 | Écriture 1, politique : relue identique au fichier, hors commentaires et lignes vides | haute : même méthode que la 07a |
| J3 | Écriture 2, jeton : relu par root via l'accesseur, `lien-signature,service,true,false,259200,true,true,0` (politiques, type, orphelin, renouvelable, durée maximale, durée restante, nom, usages) ; fichiers en 0600, préfixe `s.` | moyenne-haute : `-no-default-policy`, `-orphan` et `explicit_max_ttl` jamais relus dans ce dépôt |
| E1 | Avec le jeton : lecture de `transit/keys/lien` acceptée | haute |
| E2 | Signature `transit/sign/lien/sha2-256` acceptée ; `vault:v1:`, DER d'environ 70 octets ; **vérifiée sur l'hôte par OpenSSL avec la clé publique archivée** ; même signature sur une autre entrée refusée | haute pour l'accès ; moyenne-haute pour la vérification (format DER et hachage SHA-256 de Transit lus dans la 08, jamais vérifiés par OpenSSL ici) |
| E3 | Signatures avec `chains`, `tsa` et `scanner` refusées (403) | haute |
| E4 | Lecture de `transit/keys/chains` et export de la clé `lien` refusés | haute |
| E5 | Lecture de `kv/horodatage/zot` refusée | haute |
| E6 | Liste des politiques refusée | haute |
| E7 | Création d'un jeton enfant refusée | haute : pas de droit sur `auth/token/create` |
| E8 | Consultation de soi (`bao token lookup`) refusée, faute de politique `default` | moyenne : jamais mesurée dans ce dépôt |
| J4 | Seule politique ajoutée : `lien-signature` ; clés Transit inchangées depuis `cle_lien` | haute |
| K | K3, K4 et K5 tenus, aucune ligne masquée, aucune ligne KO | haute |

**En cas de KO après les écritures.** La politique et le jeton restent en place, et l'étape refuse toute relance. Le retrait passe par `racine` : `bao token revoke -accessor <accesseur>`, puis `bao policy delete lien-signature`, puis effacement des deux fichiers par chemins littéraux. **Ce retrait n'est ni scripté ni passé au banc.** Après un KO, je m'arrête et je rends compte ; je n'improvise pas de retrait.

**Portée.** Les essais passent par `kubectl exec` et `bao` dans `openbao-0`. Ils ne mesurent pas cosign `hashivault://lien` depuis l'hôte, et la route de l'hôte vers OpenBao (redirection de port ou autre) n'est pas décidée. Les 72 h courent dès la création.

## Note datée du 19/11/2026, 19:50:00 UTC : `acces_lien` passée (19:49:30 à 19:49:36 UTC, code 0), toutes les prédictions tenues

Journal : [o5-openbao-acces_lien.log](o5-openbao-acces_lien.log).

**J1 tenue.** Politiques avant : `chains-signature`, `chains-zot`, `default`, `horodatage-zot`, `root`, `scan-zot`, `scanner-signature` et `tsa-signature`.

**J2 tenue.**

**J3 tenue** : `lien-signature,service,true,false,259200,true,true,0`. Le secret fait 26 octets, préfixe `s.` ; il est en 0600, son accesseur aussi. **Il expire au plus tard le 22/11/2026 à 19:49:36 UTC**, 72 h après la fin de l'étape, et n'est pas renouvelable.

**Essais, E1 à E8 tenus :**
- **E1** : lecture de la clé `lien` acceptée.
- **E2** : signature avec `lien` acceptée. Signature `vault:v1:`, 72 octets DER. **OpenSSL 4.1.0 la vérifie avec `lien-cle-publique.pem`** (« Verified OK ») ; la même signature sur une autre entrée est refusée (« Verification failure »).
- **E3 à E8** : les neuf autres essais sont refusés, chacun avec « Code: 403 … permission denied ».
  - signatures avec `chains`, `tsa` et `scanner` ;
  - lecture de `chains` ;
  - export de `lien` ;
  - lecture de `kv/horodatage/zot` ;
  - liste des politiques ;
  - jeton enfant ;
  - consultation de soi (E8, confiance moyenne, désormais mesurée).

**J4 et K tenues** : K3, K4, K5 et aucune ligne masquée.

**État dans OpenBao :**
- clé `lien` ;
- politique `lien-signature` ;
- un jeton de service borné, détenu par l'hôte d'administration.

Rien n'est écrit dans Zot. cosign `hashivault://lien` depuis l'hôte n'est pas mesuré, et la route de l'hôte vers OpenBao n'est pas décidée. Le dossier `~/.cache/supply-chain-poc/09/o5-essai-signature` et le dossier du banc sont effacés après le commit de cette note.
