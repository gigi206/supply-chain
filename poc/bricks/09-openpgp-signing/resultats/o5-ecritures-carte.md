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

## Décision datée du 19/11/2026, 20:08:20 UTC : espace `signes/**`

Question posée : « Publier les objets d'O5 dans un espace signes/** à part, plutôt que dans builds/** ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus : « Oui, signes/** ».

Le §2 est retenu tel quel. La suite, dans cet ordre :
1. **`compte_zot`**, préparé et passé par la brique 09 : sur l'hôte, sans réseau, il écrit le mot de passe et la ligne htpasswd dans `09/secrets`.
2. **Application par la session principale** : §4 quinquies d'`A-REPORTER.md`, puis redémarrage de Zot.
3. **`droits_zot`**, par la brique 09.
4. **Accord à part** pour la redirection de port vers OpenBao.

## Prédictions de `compte_zot`, écrites le 19/11/2026 à 20:09:35 UTC, avant tout lancement

Étape `compte_zot` d'[`o5-zot.sh`](../o5-zot.sh), sur l'hôte, sans réseau, sur le modèle de `replay.sh compte_zot` (brique 10). Rien ne touche Zot.

**Banc** ([o5-zot-compte-banc.sh](../o5-zot-compte-banc.sh), dossier jetable) : 9 OK, 0 KO à 20:09:21 UTC ([journal](o5-zot-compte-banc.log)). Un passage précédent, à 20:09:12 UTC, donnait aussi 9 OK, mais affichait le journal de la relance au lieu du journal nominal. Seul l'affichage a été corrigé, et ce journal a été remplacé.

| N° | Prédiction | Confiance |
|---|---|---|
| CZ1 | `09/secrets` existe, sans `zot-poc-lien.password` ni `zot-poc-lien.htpasswd` | haute |
| CZ2 | Mot de passe de 48 caractères hexadécimaux, ligne `poc-lien:$2b$12$…` conforme au motif proposé pour `stockage.sh`, hash recalculé égal avec le même sel, modes 600 | haute : même outil (`mkpasswd` de whois 5.6.6) que la 08 et la 10 |
| K6 | Ni le mot de passe ni le hash dans le journal ; aucune ligne KO ; code 0 | haute |

## Note datée du 19/11/2026, 20:09:56 UTC : `compte_zot` passée (20:09:40 à 20:09:41 UTC, code 0), CZ1, CZ2 et K6 tenues

Journal : [o5-zot-compte_zot.log](o5-zot-compte_zot.log).

La ligne htpasswd de `poc-lien` est dans `09/secrets/zot-poc-lien.htpasswd`, et le mot de passe dans `zot-poc-lien.password`, tous deux en 0600. Ni l'un ni l'autre n'a été affiché.

**Rien n'est appliqué à Zot.** La suite revient à la session principale : §4 quinquies d'`A-REPORTER.md`, puis `mise run confiance:stockage -- zot`. Ensuite viendra `droits_zot`, à préparer.

## Prédictions de `droits_zot`, écrites le 19/11/2026 à 20:27:29 UTC, avant tout lancement

**Application, relue dans le dépôt.** La session principale a appliqué le §4 quinquies (accord du propriétaire « Maintenant »), au commit `4fe5e8a3` de `claude/focused-fermi-ul5y20`. Ce commit touche `stockage.sh` (7 lignes contiennent `poc-lien`) et `stockage/zot.json`. D'après son message, l'entrée `signes/**` de `zot.json` porte :
- la lecture anonyme ;
- pour `poc-lien` : lecture, et création à condition que `req.referenceType != "tag"` ;
- aucun autre compte.

Zot a été relancé à 20:24:09 UTC, puis une seconde fois, sans le vouloir, à 20:24:42 UTC. **Contrainte** : la mesure de M1b part à 00:01 UTC et lit Zot. Cette étape ne redémarre pas Zot et écrit peu.

**Étape** ([`o5-zot.sh`](../o5-zot.sh) `droits_zot`), calquée sur `replay.sh droits_zot` (brique 10) :
- **Configuration de `poc-lien`** : écrite par le script dans `09/secrets/zot-poc-lien-docker/config.json` (0600) et gardée pour la publication et pour cosign. C'est un secret de plus, à signaler à `secrets-depot.sh`.
- **Témoin `poc-ecriture`** : son mot de passe est lu par le script dans `08/secrets`, mis dans une configuration temporaire, puis vidée.
- **Image jetable** : une couche, un fichier daté.
- **Pas de banc** : il faudrait un registre local, donc une installation sur l'hôte.
- **Les objets d'essai restent dans Zot**, puisque `poc-lien` ne peut rien supprimer.

| N° | Prédiction | Confiance |
|---|---|---|
| D1 | `poc-lien`, par digest dans `signes/essai-09` : accepté | haute |
| D2 | `poc-lien`, par tag : refusé | haute : condition CEL décrite |
| D3 | `poc-lien`, hors de `signes/**` (`builds/essai-09`) : refusé | haute |
| D4 | `poc-lien`, referrer (`oras attach`) sur `signes/essai-09@image` : accepté | moyenne-haute : un referrer est poussé par digest ; la condition CEL n'a pas été lue sur un referrer |
| D5 | `poc-lien`, referrer dans un dépôt où le sujet est absent (`signes/essai-09-sans-sujet`) : refusé par `oras attach`, sujet introuvable | moyenne : décide si la copie `signes/sample-app-deb` du manifeste `60f25f5c…` est nécessaire (refus : copie nécessaire) |
| D6 | `poc-lien`, suppression : refusée | haute |
| D7 | Anonyme, écriture dans `signes/` : refusée | haute |
| D8 | `poc-ecriture`, écriture dans `signes/` : refusée (le motif le plus long remplace `**`) | moyenne-haute : dit par la session principale, pas encore mesuré |
| D9 | Manifeste et referrer relus en anonyme ; aucun tag dans `signes/essai-09` | haute |
| K6 | Ni mot de passe, ni hash, ni chaîne d'authentification dans le journal ; aucune ligne KO | haute |

## Note datée du 19/11/2026, 20:27:53 UTC : premier passage de `droits_zot` (20:27:33 UTC, code 1), rien d'écrit dans Zot ; correction avant relance

Le journal est gardé : [o5-zot-droits_zot-premier-passage.log](o5-zot-droits_zot-premier-passage.log).

**Cause : un défaut de mon script.** Le layout OCI jetable n'avait pas de fichier `oci-layout`, et `oras cp` le refusait (« invalid OCI Image Layout ») avant tout contact avec Zot. Aucune image n'a donc été poussée, et les refus de ce passage ne mesurent rien :
- **D2, D3, D7 et D8** : refus du layout, pas de Zot ;
- **D1** : refusée pour cette raison ;
- **D4 et D5** : refus, l'image n'existant pas (« failed to resolve ») ;
- **D6** : la « suppression acceptée » vient de `oras manifest delete --force`, qui ignore une référence inexistante ;
- **D9** : rien à relire.

**Rien n'a été écrit dans `signes/`** : D9 ne relit aucun manifeste ni aucun tag.

**Effet de bord.** La configuration de registre de `poc-lien` est écrite (`09/secrets/zot-poc-lien-docker`) ; la relance la réutilise. La configuration du témoin a été vidée.

**Correction.** Le script écrit `oci-layout` (`imageLayoutVersion 1.0.0`). Les prédictions ne changent pas. Le dossier de travail est effacé avant la relance.

## Note datée du 19/11/2026, 20:28:37 UTC : `droits_zot` relancée (20:27:57 à 20:28:10 UTC, code 0), D1 à D9 et K6 tenues

Journal : [o5-zot-droits_zot.log](o5-zot-droits_zot.log). L'image jetable est `signes/essai-09@sha256:c5fa3f60…`.

**Écritures de `poc-lien` :**
- **D1** : par digest dans `signes/essai-09`, acceptée.
- **D2** : par tag, refusée (« denied: requested access to the resource is denied »).
- **D3** : hors de `signes/**`, refusée.
- **D4** : referrer sur l'image, accepté.
- **D5** : referrer dans un dépôt où le sujet est absent, refusé par `oras attach` (« failed to resolve »). **Le tableau du §3 est donc figé avec la copie `signes/sample-app-deb@60f25f5c…`** : le manifeste non signé du deb, recopié octet pour octet, porte le referrer `identity`.
- **D6** : suppression refusée (« The access controller denied access »).

**Autres comptes :**
- **D7** : l'anonyme est refusé.
- **D8** : `poc-ecriture` est refusé dans `signes/` ; le motif le plus long remplace bien `**`.

**D9** : manifeste et referrer relus en anonyme ; aucun tag.

**Réserve.** Pour D3, D7 et D8, le motif du refus est coupé à 140 caractères dans le journal. Il s'arrête sur l'adresse refusée, avant la raison. Ces trois refus ne sont pas jugés sur leur motif.

**Objets laissés dans Zot** : `signes/essai-09@sha256:c5fa3f60…` et son referrer d'essai, puisque `poc-lien` ne peut rien supprimer.

**Secrets sur l'hôte** :
- `09/secrets/zot-poc-lien-docker/config.json` (0600), gardé pour la publication ;
- `09/secrets/temoin-poc-ecriture-docker/config.json`, vidé (0 octet).

**Suite** : préparer à sec la publication dans `signes/**` et les quatre attestations de lien réelles. Ce sera la prochaine étape, avec banc et prédictions.

## Note datée du 19/11/2026, 20:47:51 UTC : publication et attestations préparées à sec

Prédictions, banc et ordre des étapes : [o5-signes-predictions.md](o5-signes-predictions.md). Deux écarts au §3 :
- **Prédicat** : il garde `unsigned` (dépôt, manifeste, fichier) et porte `signed` (dépôt, fichier ou racine du dépôt). `chainsProvenance` dit ce qui a été vérifié juste avant la signature : la clé, le nombre d'enveloppes, l'heure, et que les jetons d'horodatage ne sont pas vérifiés.
- **Témoins** : chacun dans son propre dépôt (`signes/essai-09-attest`, `-autre`, `-altere`), puisqu'un referrer est rangé avec son sujet.
