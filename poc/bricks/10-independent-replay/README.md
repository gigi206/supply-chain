# Brique 10 : replay indépendant

Seuil (README, brique 10) : **domaine distinct, clé de VSA séparée, au moins 24 h : bit-identique + VSA**. Effort estimé : **2 pw**. Au-delà de 4 pw, décision avec le propriétaire.

Exigences couvertes :
- **B1** (docs/01) : le replay dans un domaine indépendant annonce « bit-identical » et produit une VSA.
- **B5** : le replay réussit avec 0 connexion sortante, journalisée.
- **B2** : la VSA est rangée dans Zot, en referrer de l'artefact.

Cadre :
- **ADR 0001, point 4** : le domaine de replay est un hôte ou un cluster distinct, administré par une autre personne, avec sa propre clé de VSA. En 2b-1, ses images de build sont « indépendantes minimales » : toolchain Go officielle à checksum vérifié, image reconstruite dans ce domaine.
- **docs/02** : rebuild hors ligne, caches froids, au moins 24 h d'écart, comparaison sha256, VSA signée par la clé du domaine de replay, diffoscope en cas d'écart.

## Préparation à sec (03/11/2026 ; rien créé, rien installé)

Demande du propriétaire : « Brique 10 ». Ce qui suit est un protocole à valider. Rien ne démarre sans les décisions D1 à D7, et chaque jalon est soumis à accord.

### Faits vérifiés (03/11/2026, lecture seule)

| Fait | Mesure |
|---|---|
| **Provenance à rejouer** | Tag `sha256-3a7ca1b1….att` de `builds/sample-app` : 6 enveloppes `https://slsa.dev/provenance/v1`, toutes de sujet `3a7ca1b1`. Trois sont des provenances de PipelineRun (6 entrées repérées) ; la plus ancienne court du **02/11/2026 13:58:36 au 13:59:30 UTC** (`runDetails.metadata`, `invocationId d9006af7…`) |
| **Entrées déclarées dans cette provenance** (`resolvedDependencies`) | <ul><li>commit `git+https://sc-stockage.poc.test:3000/workspace/sample-app.git@sha1:6391fd43…`</li><li>`entrees/sample-app/fermeture@sha256:0ab5a507…`</li><li>`entrees/sample-app/web-dist@sha256:47f72275…`</li><li>image de build `plateforme/builder-go-voie-d@sha256:d50ae575…`</li><li>pipeline et trois tâches, en bundles par digest</li></ul> |
| **Recette de build** | Signée, dans le bundle de la tâche `construire-image` (`sha256:403ccbd8…`, présent dans la provenance) : le Dockerfile de la brique 04 y est intégré et contrôlé par sha256. Options : `buildctl build --frontend dockerfile.v0 --no-cache`, `SOURCE_DATE_EPOCH=0`, `context:builder=oci-layout://…@<digest>`, `context:deps=local:deps`, `--output type=oci,rewrite-timestamp=true`. Le dépôt sample-app ne fournit pas de Dockerfile |
| **Lecture sans compte** | <ul><li>Zot : `anonymousPolicy: read` sur tous les dépôts (`stockage/zot.json`)</li><li>Forgejo : `GET /api/v1/repos/workspace/sample-app` répond 200 sans compte, et `git ls-remote` donne `6391fd43…` sur `main`</li></ul> |
| **Ancre de confiance** | Clé publique de Chains versionnée : [`chains-cle-publique.pem`](../08-trust-plane/resultats/chains-cle-publique.pem) |
| **Referrers** | Zot 2.1.22 sert l'API `GET /v2/<dépôt>/referrers/<digest>` : 200, index vide pour `3a7ca1b1`. cosign 3.1.4 n'a **aucune option de referrer** dans `cosign attest --help`. Son mode de stockage par défaut (tag `.att` ou referrer) et un éventuel envoi vers Rekor ne sont **pas établis**. `oras attach` (1.3.6) a `--artifact-type` et `--distribution-spec v1.1-referrers-api` |
| **Reproductibilité déjà mesurée** (brique 04) | Image `3a7ca1b1` identique : <ul><li>avec BuildKit 0.25.2 (laptop, rootless) comme avec 0.34.1 (Tekton, Kata) ;</li><li>alors que l'image de build diffère d'un hôte à l'autre (`bdd56bab`, `509f03bb`) ;</li><li>le binaire (`e3749c68…`) est aussi identique hors BuildKit.</li></ul>Le résultat ne dépend que des entrées : toolchain, fermeture, sources, options |
| **VSA** (spécification SLSA v1.2, relue) | <ul><li>`predicateType` : `https://slsa.dev/verification_summary/v1`, inchangé depuis v1.0</li><li>obligatoires : `verifier.id`, `resourceUri`, `policy` (`uri`, et `digest` recommandé), `verificationResult` (`PASSED` ou `FAILED`), `verifiedLevels`</li><li>facultatifs : `verifier.version` (depuis 1.1), `timeVerified`, `inputAttestations`, `dependencyLevels`, `slsaVersion`</li><li>les valeurs personnalisées de `verifiedLevels` ne doivent pas commencer par `SLSA_`</li></ul> |
| **Ressources de l'hôte** | Environ 23 Gi de RAM disponibles, 63 Go libres sur `/` (pool libvirt `supply-chain-poc`) ; trois VM en service |

**Fenêtre des 24 h** : le replay de la provenance du 02/11 13:58 ne peut commencer qu'après le **03/11/2026 à 13:59:30 UTC**. L'heure du build vient de la provenance signée (`finishedOn`) ; celle du replay sera portée par la VSA (`timeVerified`).

### Décisions du propriétaire (avant tout jalon)

**D1 : administrateur du domaine de replay.** ADR 0001 demande un nom avant la brique 10, et docs/01 en donne la raison : un seul administrateur ne doit pas pouvoir forger à la fois une provenance et sa vérification.
- (a) **Une autre personne**, nommée : séparation organisationnelle réelle. Elle détient seule la clé de VSA et l'accès à la VM.
- (b) **Le propriétaire**, par écart documenté. La séparation est seulement technique : VM, clé SSH, clé de VSA et compte Zot propres, aucun identifiant du plan de confiance dans le domaine, aucun identifiant du domaine dans le plan de confiance. La séparation organisationnelle n'est **pas démontrée**. La VSA (`verifier.id`) et ce README le disent.
- Recommandation : (a) si une personne est disponible ; sinon (b), avec l'écart inscrit dans ADR 0001.

**D2 : hébergement.**
- (a) **Une quatrième VM libvirt `sc-replay` sur le laptop.** Elle partage l'hyperviseur : le root de l'hôte peut lire son disque, clé de VSA comprise.
- (b) **Une autre machine ou un autre site**, s'il en existe un : il faudra joindre Zot et Forgejo, ou transporter les entrées. C'est la réponse à la question ouverte d'ADR 0001 (« autre site ou autre hyperviseur ? »).
- Recommandation : (b) s'il existe une machine ; sinon (a), avec l'écart consigné.

**D3 : dimensionnement** (si D2 a). ADR 0001 prévoit 8 vCPU, 16 Gi et 150 Go pour le domaine. Proposé, comme la révision du 29/10/2026 : **4 vCPU, 6 Gi, 20 Go**. La brique 04 construisait en 51 s sur le laptop, et l'image est petite.
- Même image Debian 13 vérifiée que les trois VM, avec une graine cloud-init propre.
- Réseau libvirt **distinct** (`supply-chain-replay`) avec une seule route vers `sc-stockage` (Zot 5000, Forgejo 3000), ou le réseau existant : à préciser en R1 selon ce que libvirt permet sans toucher aux trois VM.
- Aucun identifiant de k3s, d'OpenBao ni de compte Zot d'écriture des builds.

**D4 : preuve du « 0 connexion sortante » (B5).** Le build se fait en deux temps : préchargement des entrées avec le réseau, puis build sans réseau. Pour la preuve :
- (a) **lien réseau de la VM coupé pendant le build** (`virsh domif-setlink … down`), et compteurs de l'interface relus depuis l'hôte avant et après (`virsh domifstat`). Rien à installer, et la mesure est prise hors de la VM ;
- (b) nftables dans la VM, avec une politique de refus et un journal : un paquet à installer, et la mesure est prise par le domaine lui-même ;
- recommandation : (a), plus `RUN --network=none` dans le Dockerfile, déjà dans la recette.

**D5 : rangement de la VSA (B2).**
- (a) Un **compte Zot `poc-replay`**, en création par digest seulement dans `builds/**`, avec la même condition CEL que `poc-images` (aucun tag, donc ni `.att` ni `.sig`). La VSA est poussée en referrer OCI 1.1 de l'image. Cela modifie `stockage/zot.json` de la 08 (rejeu ciblé de `stockage.sh zot`).
- (b) Pas de push : la VSA reste dans `resultats/`. C'est un écart à B2.
- Recommandation : (a). Chaque push est soumis à accord. Le mode de stockage de cosign 3.1.4 (tag `.att` partagé avec Chains, ou referrer) est **mesuré en R1** avant de choisir entre `cosign attest` et `cosign attest --no-upload` suivi d'`oras attach`.

**D6 : clé de VSA.**
- (a) **Paire cosign ECDSA P-256 générée dans la VM.** La clé privée ne sort pas de la VM (0600, mot de passe tiré au hasard dans la VM) ; la clé publique est versionnée dans `resultats/`.
- (b) Un OpenBao propre au domaine : plus lourd, pour un gain faible sur un PoC.
- **Jamais** l'OpenBao du plan de confiance (docs/02).
- Recommandation : (a).

**D7 : outils du domaine** (installés dans la VM seulement, chacun vérifié). C'est une installation système, soumise à accord :
- **toolchain Go officielle** (go.dev, sha256 publié), **de la même version** que l'image de build déclarée dans la provenance. La version est lue dans cette entrée (fichier `VERSION`), sans exécuter son binaire ;
- **BuildKit, runc et rootlesskit** : releases amont épinglées, vérifiées par attestation ou sha256 comme dans `mise.toml`. La version de BuildKit est inscrite dans la VSA. Une version différente de celle de Tekton renforce l'indépendance (la brique 04 a mesuré la même image avec 0.25.2 et 0.34.1) ;
- **cosign 3.1.4, oras 1.3.6 et crane** (binaires vérifiés comme dans `mise.toml`) ;
- **busybox statique** pour l'image de build (paquet Debian `busybox-static`, signé par l'archive Debian). Il ne change pas le binaire ;
- **diffoscope** (paquet Debian ; verdict de doc 04 : « À surveiller, vérificateur secondaire »), utilisé seulement en cas d'écart et pour le test négatif.

### Décisions retenues par le propriétaire (03/11/2026)

Toutes les recommandations sont retenues :
- **D1 (b)** : le propriétaire administre le domaine, par écart documenté. La séparation est technique seulement ; la VSA et ADR 0001 le disent.
- **D2 (a)** : quatrième VM `sc-replay` sur le laptop, même hyperviseur (écart consigné).
- **D3** : 4 vCPU, 6 Gi, 20 Go.
- **D4 (a)** : lien coupé pendant le build, compteurs relus depuis l'hôte.
- **D5 (a)** : compte Zot `poc-replay` en création par digest seulement, chaque push sur accord.
- **D6 (a)** : clé cosign générée dans la VM.
- **D7** : outils vérifiés, installés dans la VM.

### Jalons proposés (chacun soumis à accord ; prédictions datées avant chaque exécution)

- **R1, relevé et essais sur l'hôte**, sans création de VM. Les essais se font dans `~/.cache/supply-chain-poc/10/`, sur 127.0.0.1, sans installation :
  - mode de stockage de cosign 3.1.4 (`.att` ou referrer) et absence d'envoi vers Rekor, mesurés contre un Zot jetable, réseau extérieur coupé ;
  - version de Go lue dans l'entrée `builder-go-voie-d` ;
  - empreintes des outils de D7 ;
  - premier jet de la politique de replay (`policy.uri` et son digest).
- **R2, création du domaine** (D1, D2, D3) :
  - VM `sc-replay` et clés SSH du domaine dans `~/.cache/supply-chain-poc/10/`, sans rien de commun avec `08/` ;
  - outils de D7 et clé de VSA générée dans la VM (D6).
- **R3, préchargement**. Le domaine prend sa recette dans la provenance signée, pas dans ce dépôt :
  - **la signature de la provenance est vérifiée d'abord**, avec la clé publique de Chains ; un refus arrête tout ;
  - recette extraite du bundle `construire-image` par digest ;
  - entrées tirées par digest (lecture anonyme), et chaque digest recalculé ;
  - commit cloné depuis Forgejo et comparé au `sha1` déclaré ;
  - **image de build reconstruite dans le domaine** depuis la toolchain officielle. Son digest est consigné, pas comparé.
- **R4, replay hors ligne** (D4) :
  - lien coupé, puis build `--no-cache` avec la recette signée ;
  - **critère principal** : digest de l'image égal au sujet de la provenance (`3a7ca1b1`) ;
  - critère secondaire : binaire extrait comparé à un `go build` direct, second moteur ;
  - compteurs réseau relus depuis l'hôte.
- **R5, VSA et contre-épreuves** :
  - VSA signée par la clé du domaine, poussée en referrer (D5, accord à chaque push), puis vérifiée ;
  - négatifs :
    - VSA vérifiée avec la clé de Chains : refus ;
    - provenance vérifiée avec la clé de VSA : refus ;
    - entrée altérée (un octet de la fermeture, dans une copie locale) : build différent ou refusé, VSA `FAILED` non poussée, rapport diffoscope archivé.

### VSA prévue (champs de la spécification v1.2)

```json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": "sc-stockage.poc.test:5000/builds/sample-app", "digest": {"sha256": "3a7ca1b1…"}}],
  "predicateType": "https://slsa.dev/verification_summary/v1",
  "predicate": {
    "verifier": {"id": "https://supply-chain.example/verifiers/replay-independant@v1", "version": {"buildkit": "<version>", "go": "<version>"}},
    "timeVerified": "<horodatage UTC du replay>",
    "resourceUri": "oci://sc-stockage.poc.test:5000/builds/sample-app@sha256:3a7ca1b1…",
    "policy": {"uri": "<politique de replay versionnée>", "digest": {"sha256": "<…>"}},
    "inputAttestations": [{"uri": "<tag .att>", "digest": {"sha256": "<digest de l'enveloppe de provenance>"}}],
    "verificationResult": "PASSED",
    "verifiedLevels": ["SLSA_BUILD_LEVEL_3", "POC_REPLAY_BIT_IDENTIQUE"],
    "slsaVersion": "1.2"
  }
}
```

`POC_REPLAY_BIT_IDENTIQUE` est une valeur propre au PoC, sans le préfixe `SLSA_` réservé. `SLSA_BUILD_LEVEL_3` n'est revendiqué que si la politique vérifie ce que demande le niveau 3 : signature par la clé de Chains et `builder.id` attendu.

### Limites connues avant d'exécuter

- **web/dist n'est pas rejoué**. Il est pris par digest, conformément au choix du propriétaire de garder Node hors de la chaîne (brique 08). La VSA ne couvre pas la construction de l'interface.
- Avec D1 (b) ou D2 (a), l'indépendance reste technique. Root sur l'hôte, ou le propriétaire seul, peut forger à la fois la provenance et la VSA.
- La consommation de la VSA par la porte (ADR 0000, critère 6) **n'est pas dans le seuil** : c'est une suite, hors de cette brique.
- Le Dockerfile n'est pas dans le dépôt sample-app : la recette dépend du bundle de tâche signé. Si une option n'y figurait pas, ce serait un constat sur la complétude de la provenance, pas une lecture de ce dépôt.

## R1, exécuté (03/11/2026, 09:50 à 09:52 UTC, accord du propriétaire : « Oui, lancer R1 »)

Commande : `mise run replay -- cosign_stockage version_go outils` ([`replay.sh`](replay.sh)). Prédictions et additif : [`r1-predictions.md`](resultats/r1-predictions.md).

| # | Mesure | Verdict |
|---|---|---|
| 1 | Dans un espace de noms sans route (`lo` seul), `cosign attest --key` échoue d'emblée : il veut le TUF public de Sigstore (`tuf-repo-cdn.sigstore.dev`). Avec une configuration de signature sans aucun service, la signature et la vérification réussissent hors réseau | conforme (issue a) |
| 2 | Attestation rangée en **referrer OCI 1.1** (`application/vnd.dev.sigstore.bundle.v0.3+json`), sans tag `.att` | conforme |
| 3 | Image de build déclarée par la provenance : `go1.26.10` | conforme |
| 4 | Toolchain officielle `go1.26.10.linux-amd64.tar.gz` vérifiée par le sha256 de go.dev (`ccfe7ae8…`) | conforme |
| 5 | BuildKit 0.25.2, runc 1.3.3, rootlesskit 2.3.5, cosign 3.1.4, oras 1.3.6 et crane 0.20.6 : archives vérifiées contre `mise.lock` | conforme, mais **prédiction trop faible**, voir ci-dessous |

**Conséquences pour la suite** :
- **Rekor** : la VSA sera signée avec `--signing-config` vide. Sans elle, cosign contacterait les services publics de Sigstore : une action publique, à proscrire.
- **Rangement** : le referrer convient à D5, et le compte `poc-replay` n'a besoin d'aucun tag. `oras attach` n'est pas nécessaire.
- **Politique** : la [politique de replay](politique-replay.md) est rédigée. Son digest sera figé avant R5.

Écarts de passage, archivés et sans effet sur les mesures :
- nom `poc.test` non résolu par l'hôte ;
- page de redirection de go.dev refusée par la vérification sha256 ;
- manifeste au format Docker de crane refusé par Zot.

Téléchargements vérifiés, gardés pour la VM : `~/.cache/supply-chain-poc/10/telechargements/`.

**Signatures des outils du domaine** (après relecture de l'advisor) :

| Outil | Vérification |
|---|---|
| runc, oras, rootlesskit | GPG, vérifiée le 29/10 pour la même empreinte |
| cosign | Sigstore, vérifiée le 29/10 pour la même empreinte |
| BuildKit 0.25.2 | **aucune signature ni attestation** : empreinte seulement |
| crane 0.20.6 | provenance SLSA publiée mais non vérifiée, aucune attestation GitHub ; retirable de la VM, oras suffit |
| toolchain Go 1.26.10 | `.asc` d'une clé non authentifiée, non retenue ; **recoupement** avec le module vérifié par sum.golang.org : les 11 503 fichiers communs sont identiques ([journal](resultats/r1-go-recoupement.log)) |

En R2, chaque archive est revérifiée **dans la VM** après la copie : le domaine contrôle ses propres outils.

**Réseau de la VM** : question laissée par D3, à trancher avec l'accord de R2. Le réseau `supply-chain-poc` est un NAT libvirt simple (`virsh net-dumpxml`), sans filtrage entre les VM.
- (a) **Même réseau**, adresse `.14` : préchargement direct depuis Zot et Forgejo. Mais la VM joint aussi tous les ports des trois nœuds : API de k3s, kubelets, SSH, OpenBao par NodePort. Elle n'a aucun identifiant, mais le « domaine distinct » s'en trouve affaibli.
- (b) **Réseau libvirt distinct** (`supply-chain-replay`), avec un NAT vers l'extérieur pour les paquets Debian (signés par l'archive), puis lien coupé.
  - Les entrées venues de Zot et de Forgejo sont **transportées par l'hôte** sous forme de fichiers (layouts OCI, bundle git), puis vérifiées dans la VM par signature et par digest. Le transport ne peut donc rien altérer sans être vu.
  - La VM ne joint jamais le plan de confiance.
  - Les règles de transfert de libvirt entre deux réseaux n'ont pas été lues, faute de root. L'absence de route vers `192.168.161.0/24` sera **mesurée** en R2.
- Recommandation : (b).

**Preuve des 24 h** (pour les prédictions de R5) :
- **Heure du build** : `finishedOn` est signé par Chains et **corroboré par un jeton RFC 3161** de la TSA de la 08. Il existe des bundles horodatés de cette image dans `horodatage/bundles`, un tag `3a7ca1b1…-<empreinte de l'enveloppe>` par enveloppe ; celui de l'enveloppe rejouée sera identifié en R3.
- **Heure du replay** : `timeVerified` est affirmé par le domaine. Il est corroboré par l'entrée d'audit de Zot du push du referrer (J6, lue dans Loki).
