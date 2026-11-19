# Brique 09, O5 réel, quatrième accord : carte des écritures dans Zot

*Écrite le 19/11/2026 à 20:01:03 UTC, à sec : rien n'est lancé.*

**Accord.** Question posée : « Accordez-vous les écritures dans Zot pour O5, avec un compte dédié ? ». Réponse du propriétaire : « Oui, prépare-le ».

## 1. Qui fait quoi

Les comptes et les droits de Zot appartiennent à la brique 08 :
- [`stockage.sh`](../../08-trust-plane/stockage.sh), étape `zot`, écrit le fichier htpasswd ;
- `stockage/zot.json` porte les droits par dépôt (`accessControl`). **Je ne l'ai pas lu** : vos règles l'interdisent.

Le modèle à suivre est celui du compte `poc-replay` de la brique 10 :
- la brique produit, dans son propre dossier de secrets, son mot de passe et **la seule ligne htpasswd** (hash bcrypt de coût 12) ;
- `stockage.sh` ne lit que cette ligne et l'ajoute ;
- l'étape `zot` réinstalle la configuration et **redémarre Zot sur sc-stockage**.

| Étape | Qui | Où |
|---|---|---|
| `compte_zot` : mot de passe et ligne htpasswd de `poc-lien` dans `09/secrets` (0600), comme `replay.sh compte_zot` (brique 10) | brique 09 | hôte, sans réseau |
| Bloc htpasswd de `poc-lien` dans `stockage.sh` (texte prêt, `A-REPORTER.md`) et entrée `signes/**` dans `zot.json` (décrite ci-dessous, à écrire par analogie avec `builds/scan/**`) | session principale | dépôt (fichiers partagés) |
| `mise run confiance:stockage -- zot` : **redémarrage de Zot** | session principale, au moment qu'elle choisit | sc-stockage |
| `droits_zot` : essais sur un dépôt jetable `signes/essai-09` | brique 09 | Zot |
| `publier`, `attester`, `verifier` (section 3) | brique 09 | Zot, OpenBao |

**Droits proposés pour `poc-lien`**, calqués sur `poc-scan` (`builds/scan/**`) et `poc-replay` :
- `signes/**` seulement ;
- **création par digest seulement** : pas de tag, pas de remplacement, pas de suppression ;
- referrers acceptés (`oras attach`, bundles cosign).

Aucun autre compte n'écrit dans `signes/**`, et `poc-lien` n'écrit nulle part ailleurs : ni `builds/**`, ni les dépôts de Chains ou du scanner.

## 2. Pourquoi un espace `signes/**` à part

- Le `.deb`, le rpm non signé et leurs manifestes restent dans `builds/**`, là où Chains signe. `poc-lien` n'a pas besoin d'y écrire.
- Un nouvel objet signé (rpm signé, dépôts) n'a pas de provenance de Chains. Le placer à part évite qu'une règle de `builds/**` l'admette ou le refuse par erreur. La porte et Kyverno ne changent pas : ce sera O6.
- **Autre voie, non recommandée** : écrire dans `builds/**`. Il faudrait ouvrir à un nouveau compte un espace où seuls Chains, la pipeline et les comptes de build écrivent.

## 3. Objets publiés (tous par digest, calculés à sec avant le lancement)

| Dépôt | Objet | Lien attesté (referrer, bundle cosign v0.3) |
|---|---|---|
| `signes/sample-app-rpm` | Image de même forme que `builds/sample-app-rpm` : une couche tar non compressée, un seul membre, le rpm signé `9f71d578…` (0/0, 0644, mtime 0) | `rpm-b1` : manifeste et fichier non signés (`07b7bd6f…`, `864d55f4…`), empreinte OpenPGP, B1 |
| `signes/sample-app-deb` | **Copie octet pour octet** du manifeste non signé `60f25f5c…` (deb inchangé, D1 a) | `identity` |
| `signes/depot-rpm` | Artefact OCI : une couche tar de `o3/signer/depot/` | `repository` : fichiers couverts |
| `signes/depot-apt` | Artefact OCI : une couche tar de `o4/signer/depot/` | `repository` : fichiers couverts |

**Sujet des énoncés.** Le sujet devient le **manifeste** publié, et non plus le fichier comme dans le banc. Le prédicat garde le fichier signé (`signedFile`) et le reste du prédicat du banc. Le contrôle indépendant `o5-lien.py` est à adapter à ce sujet, puis à repasser au banc.

**Signature.** `cosign attest --new-bundle-format --key hashivault://lien`, sans journal de transparence, comme `t8_v3` (08). La vérification se fait en anonyme : `cosign verify-attestation` avec `lien-cle-publique.pem`, puis le contrôle indépendant.

**Refus.**
- **Clé étrangère** : la même vérification avec une clé jetable est refusée.
- **Lien vers un autre digest** et **rpm à charge altérée** : écrits **dans `signes/essai-09` seulement**, avec une clé cosign jetable. La clé `lien` ne signe rien de faux.

## 4. Route de l'hôte vers OpenBao (proposition)

`kubectl port-forward -n openbao svc/openbao` sur `127.0.0.1`, le temps de l'étape `attester` seulement. Le client hashivault de cosign reçoit :
- `VAULT_ADDR=https://127.0.0.1:<port>` ;
- `VAULT_CACERT` = CA du PoC ;
- `VAULT_TLS_SERVER_NAME=openbao.openbao.svc.cluster.local`, seul nom du certificat d'OpenBao (relu le 19/11, valable jusqu'au 27/04/2027) ;
- `VAULT_TOKEN` lu dans `09/secrets/openbao-lien.secret` par le script et passé par l'environnement, jamais en argument.

**À mesurer :**
- la NetworkPolicy d'OpenBao laisse-t-elle passer une redirection de port ?
- quels chemins cosign appelle-t-il (lecture de la clé, `transit/sign/lien/<hachage>`) ?

**Autre voie** : signer par `bao write transit/sign/lien` via `kubectl exec`, comme les essais du deuxième accord, puis assembler l'enveloppe DSSE soi-même. Pas de redirection de port, mais du code de signature maison, là où cosign est le client standard (Chains et TSA l'utilisent).

## 5. Contraintes

- **Jeton `lien`** : il expire au plus tard le **22/11/2026 à 19:49:36 UTC**. Si le redémarrage de Zot vient plus tard, il faudra retirer puis recréer ce jeton.
- **Redémarrage de Zot** : il touche toutes les sessions qui lisent ou écrivent Zot. C'est à la session principale de le placer.
- **Chaque étape suit la méthode des étapes précédentes** : banc, prédictions commitées, lancement, notes datées.
- **Hors O5** : porte et Kyverno (O6) ; horodatage des attestations de lien.
