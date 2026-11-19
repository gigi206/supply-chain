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

## Note datée du 19/11/2026, 20:03:31 UTC, après relecture du conseiller : compléments et corrections

1. **Texte pour la session principale.** La ligne « texte prêt, `A-REPORTER.md` » du tableau 1 n'était pas vraie au commit `763556e3`. Le texte est écrit à cette heure-ci, au §4 quinquies d'`A-REPORTER.md`.
2. **Valeurs archivées.** Le nom (`openbao.openbao.svc.cluster.local`) et la fin de validité (27/04/2027) du certificat d'OpenBao, cités au §4, viennent désormais d'un relevé archivé : [o5-ecritures-releve.log](o5-ecritures-releve.log). Le même relevé cite le bloc de `poc-replay` de `stockage.sh` et le dépôt des referrers de la 07a.
3. **Motif le plus long.** L'entrée `signes/**` remplace toute autre entrée pour ces dépôts ; elle doit donc porter elle-même la lecture anonyme. `droits_zot` essaiera :
   - la lecture anonyme ;
   - le refus d'écriture dans `signes/**` pour les autres comptes (au moins `poc-images` et `poc-scan`, avec leurs mots de passe lus par le script seul) ;
   - le refus d'écriture de `poc-lien` hors de `signes/**`.
4. **Précédent des referrers.** La 07a range les attestations du scanner dans `builds/scan/sample-app`, un dépôt distinct de celui de l'image (`builds/sample-app`), et les lit par l'API referrers de ce dépôt. **La copie `signes/sample-app-deb` du manifeste `60f25f5c…` est donc peut-être inutile** : l'attestation `identity` pourrait être un referrer de `60f25f5c…` rangé dans `signes/sample-app-deb`, sans copier le manifeste. `droits_zot` essaiera les deux formes ; le tableau du §3 sera figé ensuite.
5. **Renouvellement du jeton.** `acces_lien` refuse si la politique existe. Pour émettre un nouveau jeton, il faut une étape distincte : elle garde la politique, la relit contre le fichier versionné, puis n'émet qu'un jeton. Elle est à écrire et à passer au banc avant usage.
6. **`VAULT_TOKEN`.** Le script ne passe jamais le jeton par `env VAR=valeur`, qui le met en argument. Il l'exporte depuis le fichier, dans son propre processus.
7. **Premier contact avec OpenBao par cosign.** Ce sera une lecture seule : `cosign public-key --key hashivault://lien`, comparée à `lien-cle-publique.pem`. On ne sait pas si le client hashivault fonctionne sans la politique `default`, par exemple s'il consulte son propre jeton, ce qu'E8 refuse.
8. **Témoins.** `poc-lien` ne peut rien supprimer : tout objet d'essai (`signes/essai-09`, témoins faux) **reste dans Zot**. Les témoins faux sont signés par une clé cosign jetable. Ils sont vérifiés avec cette clé jetable, pour que ce soit le contrôle indépendant, et non cosign, qui les refuse.
9. **Redirection de port vers OpenBao.** Elle ouvre un nouveau chemin de l'hôte vers le plan de confiance. **Elle relève d'un accord à part**, demandé après celui-ci ; rien n'est lancé vers OpenBao d'ici là.
