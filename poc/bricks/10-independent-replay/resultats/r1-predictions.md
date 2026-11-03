# R1, relevé et essais sur l'hôte : prédictions (écrites le 03/11/2026 vers 09:50 UTC, avant toute exécution)

Accord du propriétaire : « Oui, lancer R1 ». Pas de VM créée, rien d'installé. Les essais tournent dans `~/.cache/supply-chain-poc/10/`. Seule une lecture anonyme de Zot du PoC sort de l'hôte, plus le téléchargement de la toolchain Go depuis go.dev.

## Étapes

1. **`cosign_stockage`** : stockage d'une attestation par cosign 3.1.4, et absence d'envoi vers Rekor.
   - Un Zot 2.1.22 jetable (binaire de `mise.toml`) tourne sur la boucle locale **d'un espace de noms réseau vide** (`unshare -rn`) : il n'y a aucune route vers l'extérieur.
   - Dans cet espace : une image jetable (crane), une paire de clés jetable, puis `cosign attest --key` d'un prédicat VSA d'essai.
2. **`version_go`** : version de Go lue dans l'entrée `plateforme/builder-go-voie-d@sha256:d50ae575…` de la provenance, par lecture anonyme des couches, sans rien exécuter.
3. **`outils`** : toolchain Go officielle de go.dev, de cette version, téléchargée et vérifiée par le sha256 publié dans `go.dev/dl/?mode=json&include=all`. Empreintes des binaires de `mise.toml` qui iront dans la VM (BuildKit, runc, rootlesskit, cosign, oras, crane).

## Prédictions

1. **cosign, hors réseau** : je ne connais pas le comportement par défaut de la v3, et je n'en déduis rien. Deux issues possibles :
   - (a) **échec**, parce que cosign veut la racine TUF de Sigstore ou Rekor. La sortie nomme alors l'hôte visé. Il faudra un `--signing-config` sans journal de transparence pour l'éviter ;
   - (b) **succès sans réseau**.

   Dans les deux cas, **rien ne sort de l'hôte** : l'espace de noms n'a pas de route.
2. **cosign, stockage** : si la signature réussit, je m'attends au format bundle de Sigstore, stocké en **referrer OCI 1.1** de l'image (type d'artefact `application/vnd.dev.sigstore.bundle…`), sans tag `.att`. C'est une attente faible : si cosign écrit dans le tag `.att`, la VSA passera par `cosign attest --no-upload` puis `oras attach` (D5).
3. **Version de Go** : `go1.26.10`. C'est le module `golang.org/toolchain@v0.0.1-go1.26.10.linux-amd64` de `voie-d.sh`.
4. **Toolchain officielle** : `go1.26.10.linux-amd64.tar.gz` est présent dans la liste de go.dev, et son sha256 concorde. C'est un emballage différent du module de toolchain de la plateforme, donc une source indépendante pour le domaine. L'égalité du binaire produit sera mesurée en R4, pas ici.
5. **Empreintes des outils** : identiques à celles que mise a vérifiées (`mise.lock`).

## Limites

- L'essai de cosign se fait sans réseau du tout. Il ne dit pas ce que cosign tenterait avec le réseau, seulement s'il en a besoin.
- La politique de replay est rédigée en R1, mais son digest ne sera figé qu'avant R5.

## Additif du 03/11/2026, après l'exécution (09:50 à 09:52 UTC)

1. **cosign, hors réseau : issue (a)**, conforme. Sans option, `cosign attest --key` échoue d'emblée : `error getting signing config from TUF … Get "https://tuf-repo-cdn.sigstore.dev/15.root.json"`. Rien n'est sorti de l'hôte : l'espace de noms n'avait que `lo`, et 0 route. Avec une configuration de signature créée sans aucun service (`cosign signing-config create`, soit `{"mediaType":"application/vnd.dev.sigstore.signingconfig.v0.2+json","rekorTlogConfig":{},"tsaConfig":{}}`), la signature réussit hors réseau. `cosign verify-attestation --key --insecure-ignore-tlog` réussit aussi. Son message « Existence of the claims in the transparency log was verified offline » est le texte de cosign, pas une vérification de journal : aucun journal n'est utilisé.
2. **cosign, stockage** : conforme. Aucun tag `.att` ni `.sig`, seulement `v1`. Un referrer OCI 1.1, d'`artifactType` `application/vnd.dev.sigstore.bundle.v0.3+json`.
3. **Version de Go** : conforme, `go1.26.10` (`usr/local/go/VERSION` de l'unique couche de `builder-go-voie-d@sha256:d50ae575…`).
4. **Toolchain officielle** : conforme. `go1.26.10.linux-amd64.tar.gz`, sha256 `ccfe7ae8…` publié par go.dev : `OK`.
5. **Outils** : conforme. Les six archives de `mise.lock` sont `OK`.

**Écarts de passage**, archivés :
- `r1-version_go-premier-passage.log` : l'hôte ne résout pas `sc-stockage.poc.test`. L'adresse est passée en IP, couverte par le certificat de Zot.
- `r1-outils-premier-passage.log` : sans `-L`, curl a enregistré la page de redirection de go.dev (76 octets), et la vérification sha256 l'a refusée (`FAILED`). Le fichier a été supprimé, puis `-L` ajouté.
- Premier essai de `cosign_stockage`, non archivé, journal écrasé : crane, sans base, crée un manifeste au format Docker, que Zot 2.1.22 refuse (`MANIFEST_INVALID`). `--oci-empty-base` a été ajouté.
