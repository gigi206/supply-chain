# Brique 09, O5 réel : redirection vers OpenBao et cosign `hashivault://lien`, prédictions

Écrites le 19/11/2026 à 20:14:38 UTC, avant tout lancement.

**Accord.** Question posée : « Accordez-vous une redirection de port locale vers OpenBao pour que cosign signe avec la clé lien ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus : « Ok ».

**Mécanisme** ([`o5-cosign.sh`](../o5-cosign.sh)) :
- **Redirection** : `kubectl port-forward -n openbao pod/openbao-0 --address 127.0.0.1 :8200`, sur un port libre, ouverte le temps de l'étape. Elle est fermée par un `trap` du sous-shell de l'étape, puis le script vérifie que le port n'écoute plus.
- **Environnement du client hashivault de cosign** :
  - `VAULT_ADDR` vers ce port ;
  - `VAULT_CACERT` : la CA du PoC ;
  - `VAULT_TLS_SERVER_NAME=openbao.openbao.svc.cluster.local`, d'après le [relevé](o5-ecritures-releve.log) ;
  - `VAULT_TOKEN` : lu dans `09/secrets/openbao-lien.secret` par un sous-shell et exporté, jamais en argument ni affiché.
- **Contrôles** : le journal est écrit, puis contrôlé par K3 et K5, et seulement ensuite affiché. K5 couvre le journal et le dossier de travail.

**Banc hors cluster** ([o5-cosign-banc.sh](../o5-cosign-banc.sh)) : le faux `kubectl` ouvre un vrai port d'écoute ; le faux `cosign` contrôle l'environnement, puis signe avec une clé jetable, hors réseau. Trois passages :
1. **20:13:46 UTC, 2 OK et 13 KO** ([journal](o5-cosign-banc-premier-passage.log)) : `o5-cosign.sh` n'était pas exécutable.
2. **20:13:53 UTC, 11 OK et 4 KO** ([journal](o5-cosign-banc-deuxieme-passage.log)). **Défaut du script, révélé par le banc** : en mode banc, `PEM` gardait le chemin de la vraie clé `lien`, parce qu'il était défini avant la redirection vers le dossier du banc. Il est désormais défini après. En vrai passage, le chemin était juste.
3. **20:14:07 UTC, 15 OK et 0 KO** ([journal](o5-cosign-banc.log)), sur le script final `bfad5b26…`.

Les cas couverts : nominal ; autre clé rendue ; redirection en échec ; signature refusée ; fuite du secret dans une erreur ; dossier déjà présent.

**Le banc ne prouve pas** :
- le vrai client hashivault (chemins appelés, `VAULT_TLS_SERVER_NAME`, fonctionnement sans la politique `default`) ;
- la traversée de la NetworkPolicy d'OpenBao par la redirection.

**Réseau.** cosign tourne hors `unshare -n` pendant `cle` et `essai`, puisqu'il doit joindre `127.0.0.1` sur l'hôte. Pour `essai`, les drapeaux `--use-signing-config=false --tlog-upload=false` ont été mesurés hors réseau dans le banc d'O5 (`attest-blob` réussi sans aucun réseau, donc sans envoi). La vérification de l'essai se fait, elle, sous `unshare -n`.

## `cle` (lecture seule)

| N° | Prédiction | Confiance |
|---|---|---|
| PF1 | Redirection ouverte (« Forwarding from 127.0.0.1:<port> -> 8200 ») puis fermée : processus arrêté, port fermé | moyenne-haute : jamais fait vers OpenBao dans ce dépôt ; la NetworkPolicy porte sur le trafic du réseau des pods, et une redirection arrive par la boucle locale du pod (non mesuré) |
| CC1 | `cosign public-key --key hashivault://lien` : code 0 | moyenne : client hashivault jamais employé avec `VAULT_TLS_SERVER_NAME`, ni avec un jeton sans politique `default` (la 08 note qu'il lit `transit/keys/<clé>`) |
| CC2 | Clé rendue = clé archivée (SPKI `42529342…`) | haute, si CC1 est tenue |
| K | K3 et K5 tenus ; aucune ligne KO | haute |

## `essai` (lancé seulement si `cle` est tenue)

| N° | Prédiction | Confiance |
|---|---|---|
| CE1 | `cosign attest-blob --key hashivault://lien` d'un énoncé d'essai (type `https://supply-chain.example/lien-openpgp/essai`) : code 0 ; signature par `transit/sign/lien/sha2-256` | moyenne-haute : la politique couvre `transit/sign/lien/*` |
| CE2 | Bundle v0.3 ; vérifié **hors réseau** avec la clé publique archivée : « Verified OK » | haute, si CE1 est tenue |
| CE3 | Même bundle présenté avec une autre entrée : refusé, motif « digest » | haute : mesuré dans le banc d'O5 |
| K | K3 et K5 tenus ; redirection fermée ; aucune ligne KO | haute |

**Rien n'est écrit dans Zot.** La seule écriture possible dans OpenBao est une signature (Transit ne garde rien). Le dossier `~/.cache/supply-chain-poc/09/o5-cosign` est effacé après archivage.
