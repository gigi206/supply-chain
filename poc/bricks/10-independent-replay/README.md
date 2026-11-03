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
- **Rangement de la VSA révisé** (03/11/2026, vers 12:00 UTC, après la mesure préalable de R5, choix du propriétaire : « (a) Dépôt séparé ») :
  - la VSA va dans **`builds/vsa/sample-app`**, et non dans `builds/sample-app` ;
  - c'est un manifeste fait main dont le `subject` est l'image, poussé par digest sans étiquette ;
  - les droits D5 sont inchangés.
- **`policy.uri` de la VSA** (03/11/2026, vers 12:45 UTC, choix du propriétaire : « ok pour ta recommandation ») :
  - c'est l'URL GitHub du fichier au commit qui fige la politique, `https://github.com/gigi206/supply-chain/blob/<commit>/poc/bricks/10-independent-replay/politique-replay.md` ;
  - `policy.digest` est le sha256 du fichier à ce commit ;
  - l'étape de la VSA transporte la politique tirée de ce commit (`git show`), et refuse si le commit n'est sur aucune branche distante ;
  - ce commit doit donc être poussé avant R5, et ce push reste soumis à l'accord du propriétaire.
- **Politique alignée avant d'être figée** (03/11/2026, vers 13:20 UTC, pendant l'attente de R4 ; aucune mesure ne la citait encore) :
  - section 1, point 1 : le texte disait que la provenance est tirée du tag `.att`. R3 l'a tirée, et vérifiée, d'un bundle horodaté de `horodatage/bundles` (`verifier_entrees.py`). Le texte suit désormais R3 ;
  - section 6 : la signature passe par `cosign attest-blob --statement` dans la VM, chemin mesuré le 03/11 à 10:34 UTC, et non par `cosign attest`, qui exige un registre ; `inputAttestations` désigne le manifeste du bundle horodaté par son digest ;
  - sections 4 bis et 6 : `outils/vsa.py`, qui décide de la VSA, entre dans le code du domaine et dans `verifier.version` ; `outils/negatifs.sh` est journalisé, sans entrer dans la VSA ;
  - section 5 : `FAILED` est retiré des `verifiedLevels`. C'est une valeur de `verificationResult`, et une VSA `FAILED` n'est ni signée ni poussée.

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
    "verifier": {"id": "https://supply-chain.example/verifiers/replay-poc-administrateur-unique@v1", "version": {"buildkit": "<version>", "go": "<version>", "verifier_entrees.py": "<sha256>", "rebuild.sh": "<sha256>"}},
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
- (a) **Même réseau**, adresse `.14` : préchargement direct depuis Zot et Forgejo. Mais la VM joint aussi tous les ports des trois nœuds : API de k3s, kubelets, SSH, et les NodePort, relevés le 03/11 : `el-forgejo` (32631, 30717) et `el-forgejo-sync` (31264, 30778), c'est-à-dire les écouteurs des déclencheurs de builds. OpenBao n'a pas de NodePort. Elle n'a aucun identifiant, mais le « domaine distinct » s'en trouve affaibli.
- (b) **Réseau libvirt distinct** (`supply-chain-replay`), avec un NAT vers l'extérieur pour les paquets Debian (signés par l'archive), puis lien coupé.
  - Les entrées venues de Zot et de Forgejo sont **transportées par l'hôte** sous forme de fichiers (layouts OCI, bundle git), puis vérifiées dans la VM par signature et par digest. Le transport ne peut donc rien altérer sans être vu.
  - La VM ne joint jamais le plan de confiance.
  - Les règles de transfert de libvirt entre deux réseaux n'ont pas été lues, faute de root. L'absence de route vers `192.168.161.0/24` sera **mesurée** en R2.
- Recommandation : (b).

**Preuve des 24 h** (pour les prédictions de R5) :
- **Heure du build** : `finishedOn` est signé par Chains et **corroboré par un jeton RFC 3161** de la TSA de la 08. Il existe des bundles horodatés de cette image dans `horodatage/bundles`, un tag `3a7ca1b1…-<empreinte de l'enveloppe>` par enveloppe ; celui de l'enveloppe rejouée sera identifié en R3.
- **Heure du replay** : `timeVerified` est affirmé par le domaine. Il est corroboré par l'entrée d'audit de Zot du push du referrer (J6, lue dans Loki).

**Décisions du propriétaire (03/11/2026)** :
- **réseau distinct** `supply-chain-replay`, entrées transportées par l'hôte et vérifiées dans la VM ;
- **BuildKit 0.25.2 accepté sur sa seule empreinte**, exception consignée comme pour tkn. crane et rootlesskit sont retirés de la VM : oras, signé, couvre manifestes et blobs, et BuildKit tourne en root dans la VM dédiée ;
- R2 lancé.

## R2, exécuté (03/11/2026, 10:00 à 10:02 UTC, accord du propriétaire : « Oui, lancer R2 »)

Commande : `JALON=r2 mise run replay -- vm isolement paquets outils cle_vsa`. Prédictions et additif : [`r2-predictions.md`](resultats/r2-predictions.md).

| # | Mesure | Verdict |
|---|---|---|
| 1 | VM `sc-replay` (4 vCPU, 6 Gi, 20 Go, Debian 13) sur le réseau propre `supply-chain-replay` (`192.168.162.14`), avec pool et clés SSH du domaine. SSH en 9 s. Trois VM du PoC non touchées | conforme |
| 2 | Zot, Forgejo et l'API de k3s **injoignables** depuis la VM ; l'extérieur joignable. **Sens inverse** : `sc-build` et `sc-confiance` ne joignent pas la VM. **Écart** : les services de l'hôte (22, 111, 2049, 22000) sont joignables depuis toutes les VM ([complément](resultats/r2-isolement-complement.log)) | conforme, avec un écart |
| 3 | `busybox-static` et `diffoscope-minimal` installés par apt, sans avertissement de signature | conforme |
| 4 | Cinq archives **revérifiées dans la VM** ; BuildKit 0.25.2, runc 1.3.3, cosign 3.1.4, oras 1.3.6, Go 1.26.10 | conforme |
| 5 | Clé de VSA P-256 générée dans la VM (600, `replay`), différente de celle de Chains ; [clé publique](resultats/vsa-cle-publique.pem) | conforme |

**Constat sur l'hôte**, hors du périmètre de la brique, **mesuré** : SSH, NFS (111, 2049) et 22000 du laptop sont joignables depuis `sc-build`, `sc-confiance` et `sc-replay`. Le nœud qui exécute le code des builds atteint donc le NFS du poste. Rien n'a été modifié sur le poste.

**Limite de D6** : le mot de passe de la clé de VSA est dans le même dossier 0600 que la clé. Il n'ajoute aucune protection au-delà des droits du fichier.

**Suite, R3** : préchargement. Les entrées sont tirées par l'hôte, en lecture anonyme, sous forme de layouts OCI et d'un bundle git, puis transportées dans la VM et vérifiées par le domaine. La signature de la provenance est vérifiée d'abord, puis la recette et les digests.

## R3, exécuté (03/11/2026, 10:18 à 10:20 UTC, accord du propriétaire : « Oui, lancer R3 »)

Commande : `JALON=r3 mise run replay -- transporter verifier_entrees`.
- L'hôte ne sert que de transport : lectures anonymes, layout OCI et bundle git.
- La VM vérifie tout elle-même avec [`outils/verifier_entrees.py`](outils/verifier_entrees.py).
- `git` a été ajouté à la VM (Debian `1:2.47.3-0+deb13u1`, épinglé), avec l'accord du propriétaire : « Installer git ».

Prédictions et additif : [`r3-predictions.md`](resultats/r3-predictions.md).

| # | Mesure | Verdict |
|---|---|---|
| 1 | Transport par lectures anonymes ; 77 Mo dans la VM | conforme |
| 2 | **43** bundles horodatés de `3a7ca1b1` (6 prévus), tous vérifiés **hors réseau** dans la VM : clé de Chains, sujet, jeton de la TSA. La provenance `d9006af7…` est extraite d'un bundle vérifié | conforme, avec un écart sur le nombre |
| 3 | Politique, section 1 : `_type`, `predicateType`, `builder.id`, `buildType`, sujet, cinq entrées déclarées | conforme |
| 4 | Quatre digests recalculés égaux aux digests déclarés ; `main` = `6391fd43…` (`git bundle verify`), arbre propre | conforme |
| 5 | Dockerfile extrait du bundle signé : sha256 `d56985c1…`, égal au contrôle de la tâche et au Dockerfile de la brique 04 ; options de `buildctl` extraites | conforme |
| 6 | Go `go1.26.10` dans l'image de build vérifiée, comme dans la VM | conforme |
| 7 | Build terminé le 02/11 à 13:59:30 UTC (signé), horodaté par la TSA à 14:00:05 | conforme |

Premier passage (3 KO, dus au script) archivé. Le journal de `r2-paquets.log` réécrit par l'ajout de git a été reconstitué (`r2-paquets-premier-passage.log`).

**Pour R4** : la recette de `preparer-entrees` (contexte `src`, `deps`, `src/web/dist`) doit aussi être extraite de son bundle déclaré. **Le rebuild ne commence pas avant le 03/11 à 13:59:30 UTC.**

## D5, compte Zot `poc-replay` : préparation à sec (03/11/2026 ; rien appliqué)

Accord du propriétaire : « Oui, à sec ». L'application aura son propre accord, avant R5.

**Contrainte** : la VM du domaine ne joint pas Zot (réseau distinct, R2). Le chemin est donc le suivant :
- la VSA est **signée dans la VM**, et la clé n'en sort pas ;
- elle est **poussée par l'hôte**, qui la transporte en referrer. La VSA étant signée, le transport ne peut pas l'altérer sans que la vérification échoue.

**Secret** : le mot de passe de `poc-replay` est généré dans `~/.cache/supply-chain-poc/10/secrets/`, le dossier du domaine sur l'hôte. La 08 ne reçoit que son **hash bcrypt** : son script ne voit jamais le mot de passe.

**Modifications prévues dans la 08** (rejeu ciblé `mise run confiance:stockage -- zot`, qui redémarre Zot) :
- `stockage/zot.json`, dépôts `builds/**` : `poc-replay` reçoit `read`, et `create` avec la même condition CEL que `poc-images` (`req.referenceType != "tag"`). Il n'a ni `update`, ni tag, donc ni `.att` ni `.sig`.
- `stockage.sh`, étape `zot` : la ligne `poc-replay:<bcrypt>` du `htpasswd` est lue dans `~/.cache/supply-chain-poc/10/secrets/zot-poc-replay.htpasswd`, sans mot de passe.

**Vérifications prévues**, avec prédictions avant exécution :
- un referrer poussé par digest dans `builds/sample-app` est accepté ;
- un tag est refusé, de même qu'un dépôt hors de `builds/**` et une mise à jour ;
- en lecture anonyme, le referrer apparaît dans `GET /v2/builds/sample-app/referrers/sha256:3a7ca1b1…`.

**À mesurer avant R5, sur l'hôte et sur un Zot jetable (comme R1)** : ce que `cosign attest --no-upload` produit avec la configuration de signature vide, dans le format bundle v0.3. Il s'agit de savoir si la VM peut signer sans registre, et si `oras attach` peut ensuite pousser ce bundle tel quel, en referrer.

**D5 appliqué (03/11/2026, 10:40 à 10:42 UTC, accord du propriétaire : « Oui, appliquer D5 »)** : prédictions et additif dans [`d5-predictions.md`](resultats/d5-predictions.md).
- Compte `poc-replay` créé. Le hash est lu par la 08, et le mot de passe reste dans le dossier du domaine.
- Push par digest et referrer acceptés ; tag, autre dépôt et suppression refusés par le contrôleur d'accès.
- Les refus n'apparaissent pas dans l'audit de Zot.
- **Risque à mesurer avant R5** : l'effet d'une VSA en referrer de `builds/sample-app` sur la porte de la 08.
- Résidu : `builds/essai-replay`.

## R5, mesure préalable : VSA en referrer de l'image et porte de la 08 (03/11/2026, 11:17 à 11:23 UTC ; rien poussé)

Prédictions datées, additifs et résultats : [`r5-referrer-porte-predictions.md`](resultats/r5-referrer-porte-predictions.md). Le banc :
- l'image réelle `3a7ca1b1`, son `.sig` et son `.att` sont copiés en lecture anonyme dans un **Zot jetable** v2.1.22, dans un espace de noms réseau vide ; les digests sont égaux au PoC ;
- **ec v0.10.42**, même empreinte que la porte, avec la politique de la porte : bibliothèque `ebd3fbd2`, `porte.rego`, `taches.yml` ;
- cosign 3.1.4 ;
- une VSA signée par une **clé jetable**, rangée comme en R5 ;
- aucune écriture dans le Zot du PoC ni dans le cluster.

Les scripts sont dans [`essais/`](essais), hors de `replay.sh` jusqu'à la fin de R4.

**Constat : la VSA en referrer de l'image ferait refuser l'image réelle par la porte.**
- **Avant** ([`r5-referrer_porte.log`](resultats/r5-referrer_porte.log)) : avec la source attendue, ec rend `success` vrai : 1 signature d'image, 6 attestations, 33 succès, 3 avertissements `trusted_task.tagged`. cosign vérifie la signature et les 6 attestations avec la clé de Chains.
- **Après un seul referrer de type bundle v0.3** : ec ne lit plus `.sig` ni `.att`, et voit **0 signature et 0 attestation**. `builtin.image.signature_check` et `builtin.attestation.signature_check` passent en violation, avec ou sans source attendue. `cosign verify` et `cosign verify-attestation` refusent aussi avec la clé de Chains (`Found: 0, Expected 1`).
- La 08 avait écarté ce rangement pour ses bundles d'horodatage. Le commentaire de `tsa/horodater.sh` l'expliquait pour Kyverno ; la mesure le confirme pour ec et cosign.
- **Premier passage** ([archivé](resultats/r5-referrer_porte-premier-passage.log)) : sans la source attendue, il donnait la même conclusion. J'avais prédit à tort que la porte admettait l'image sans cette source.
- **Limite du banc** : ec ne peut pas lire les bundles de tâches sur `sc-stockage.poc.test` (9 échecs, sans réseau). Le verdict de ec « avant » est celui du cas `reel` du test 8 de la 08 (`preuves-test8.log` : `success` vrai, aucune violation, avertissement `trusted_task.tagged`). Le test 8 voyait 2 enveloppes, l'image en porte 6 aujourd'hui.

**Alternative mesurée** ([`r5-referrer_depot_separe.log`](resultats/r5-referrer_depot_separe.log)), sur le modèle de `horodatage/bundles` : un manifeste fait main dont le `subject` est l'image, dans un **autre dépôt** (nom d'essai : `builds/vsa/sample-app`), poussé **par digest, sans étiquette**.
- Zot l'accepte alors que le sujet est absent de ce dépôt. L'API referrers de ce dépôt le liste, et le dépôt n'a aucune étiquette.
- **L'image réelle reste admise** : ec rend `success` vrai, 1 signature, 6 attestations ; cosign l'accepte avec la clé de Chains.
- **La VSA se lit** par `COSIGN_REPOSITORY=<dépôt séparé> cosign verify-attestation --key <clé de la VSA>`. La clé de Chains la refuse.
- **Job d'horodatage** (journaux du passage de 11:23:00 à 11:23:04 UTC, lecture seule) : `builds/essai-replay`, sans étiquette avec un referrer depuis D5, n'y cause aucune anomalie. La seule anomalie est le témoin connu de J6.
- **Durée de vie d'un referrer sans étiquette dont le sujet est absent du dépôt** : lu dans `08-trust-plane/stockage/zot.json`, `gc: false`, et aucune politique de rétention. Le ramasse-miettes de Zot est donc désactivé. **Non mesuré** dans le banc, qui a duré moins d'une minute. Les bundles de `horodatage/bundles`, eux, sont étiquetés.
- **Droits** : en D5, les droits de `poc-replay` ont été mesurés sur `builds/essai-replay`. Ils acceptent un push par digest et un referrer sous `builds/**`. Le nom du dépôt définitif n'est pas mesuré.

**Décision du propriétaire** (03/11/2026, vers 12:00 UTC) : « (a) Dépôt séparé ».
- La VSA sera rangée dans `builds/vsa/sample-app`, selon la méthode mesurée ici : manifeste fait main, poussé par digest, sans étiquette.
- `oras attach` n'est plus utilisé, car le sujet est absent de ce dépôt. Son comportement dans ce cas n'est pas mesuré.
- La section 6 de la politique est mise à jour, avant d'en figer le digest.
- Rien n'est poussé avant l'accord de R5.

## R5, mesure préalable : cosign et le TUF public en vérification par clé (03/11/2026, 13:21 et 13:24 UTC ; sur l'hôte seul)

Accord du propriétaire : « Oui, mesurer ». Prédictions datées et résultat : [`r5-tuf-predictions.md`](resultats/r5-tuf-predictions.md). Script : [`essais/tuf-verification-cle.sh`](essais/tuf-verification-cle.sh). Le banc : espace de noms réseau vide, Zot, image et clés jetables, tentatives de connexion relevées par `strace`.

- **Résultat** : les quatre vérifications des étapes de R5 sur l'hôte ne tentent **aucune** connexion hors de Zot, avec `HOME` vide comme avec une copie du cache TUF. Il s'agit de `verify-blob-attestation --new-bundle-format`, de `verify-attestation` par `COSIGN_REPOSITORY`, et de `verify` et `verify-attestation` au format ancien. Avec la bonne clé, elles réussissent hors réseau. Avec une autre clé, comme dans les cas N3, elles sont refusées, toujours sans tentative.
- **Deux passages** : le premier ne mesurait que des vérifications réussies, et son extrait des traces s'arrêtait au premier fichier. Il est [archivé](resultats/r5-tuf-premier-passage.log). Le second ajoute les refus ; il est fait avec le script archivé.
- **Témoin** : `cosign attest` sans configuration de signature tente 8 résolutions de `tuf-repo-cdn.sigstore.dev`. La sonde voit donc ce qu'elle cherche, et les connexions à Zot sont bien relevées.
- **Constat annexe** : `root.json` est écrit dans `~/.sigstore`, localement et sans connexion. La commande qui l'écrit n'est pas isolée par cette mesure.
- **Conséquence** : les étapes `pousser_vsa` et `lire_vsa` peuvent garder le réseau sur l'hôte. Le relevé des `connect()` par `strace` est maintenu pendant R5, parce que le banc (HTTP local, copie de `HOME`) n'est pas R5 (TLS vers Zot, vrai `~/.sigstore`).
- Dans la VM, `unshare -rn` reste une précaution, et la section 6 de la politique l'inscrit. Son fonctionnement pour `replay` n'est pas mesuré : il le sera après R4, avant de pousser le commit qui fige la politique.

## R4, premier passage : échec avant le build, dû au code du domaine (03/11/2026, 14:00 à 14:20 UTC)

Lancé automatiquement à 14:00:04 UTC, 24 h après la fin du build, avec l'accord du propriétaire (« Préparer puis lancer »). Journal : [`r4-rebuild-premier-passage.log`](resultats/r4-rebuild-premier-passage.log) ; constat détaillé dans [`r4-predictions.md`](resultats/r4-predictions.md).

- **Conforme** :
  - lien coupé à 14:00:05 UTC, porteuse à `0` vue de l'invité ;
  - **sortie de la VM inchangée pendant les 1 200 s de coupure** (`tx_bytes=1774754`, `tx_packets=17805`) ;
  - recette de `preparer-entrees` vérifiée (digest et trois opérations `OK`).
- **Arrêt 20 s après le début** : `rebuild.sh` tourne en root, et `git archive` refuse le dépôt `~replay/r3/src`, qui appartient à `replay` (`detected dubious ownership`). Aucune image n'a été construite : ce n'est **pas** un résultat de reproductibilité.
- **Deux défauts de `replay.sh`** :
  - l'état de l'unité affiché (`success inactive`) est faux après `--collect` ; le journal de l'unité donne `status=2` ;
  - le piège `EXIT` cite une variable locale déjà disparue à la sortie. Le lien avait été rétabli explicitement ; il est bien `up`.
- **Arrêt conforme à la règle de R4.** La correction et le second passage attendent la décision du propriétaire. Effort : bien en deçà du seuil de 4 pw.

## R4, second passage hors ligne : `PASSED` (03/11/2026, 14:26 à 14:46 UTC ; choix du propriétaire : « Corriger, répéter, relancer »)

- **Correctifs** :
  - `git archive` tourne en tant que `replay` (`runuser`), et `tar` reste en root ;
  - `rebuild.sh` écrit son code de sortie dans `resultat.txt` ;
  - le piège du lien reçoit le nom de l'interface au moment où il est posé.
- **Mesures dans la VM** ([`r4-mesures-vm.log`](resultats/r4-mesures-vm.log)) :
  - **`unshare -rn` fonctionne pour `replay`** (seul `lo` est visible). La section 6 de la politique est donc applicable ;
  - le `git archive` corrigé fonctionne en root.
- **Répétition, lien établi, essai non compté** ([`r4-repetition.log`](resultats/r4-repetition.log)) : `PASSED` en 46 s. Son premier passage, arrêté avant tout transport par un `diff` sous `pipefail`, est archivé.
- **Second passage, lien coupé** ([`r4-rebuild.log`](resultats/r4-rebuild.log)) : les huit prédictions sont conformes.
  - Image reconstruite **`sha256:3a7ca1b1…`, égale au sujet de la provenance : `PASSED`**.
  - Binaires des deux moteurs égaux, `e3749c68…`.
  - Image de build du domaine `dc20b752…`, différente de celle du plan de confiance, qui ne change pas l'image produite.
  - **La VM n'a rien émis pendant les 1 200 s de coupure** : compteurs de sortie inchangés côté hôte et côté invité.
  - Rebuild en 62 s, fini 19 min avant le rétablissement du lien.
- **Seuil B5** (le replay réussit avec 0 connexion sortante, journalisée) : atteint pour le rebuild.
- **Politique, section 3, réécrite avant le gel** (14:48 UTC) : « VM neuve » n'était plus exact après la répétition. Les caches froids reposent désormais sur `--no-cache`, la racine BuildKit effacée et `~/r4` vidé. Un relevé en lecture seule ne trouve sur le disque de la VM aucun fichier de la répétition ([`r4-etat-residuel.log`](resultats/r4-etat-residuel.log)).
- **Reste** : R5, avec la VSA, les contre-épreuves N1 à N3 et la porte avant et après.

## R5, étape `vsa` : VSA écrite et signée dans le domaine (03/11/2026, 14:57 UTC ; choix du propriétaire : « Pousser et lancer vsa »)

- **Défaut corrigé avant exécution** (14:56 UTC) : `vsa.py` lisait bundles et racine de la TSA dans `~/r3/travail`, que `verifier_entrees.py` vide en fin de R3. Il les refait désormais dans `~/r5/travail`, et exige un seul bundle de l'invocation.
- **Résultat** ([`r5-vsa.log`](resultats/r5-vsa.log)) : les prédictions 1 à 4 sont conformes.
  - Dans la VM, sous `unshare -rn`, le bundle horodaté de la provenance est revérifié : clé de Chains et jeton de la TSA, sans réseau. Son énoncé est identique à celui de R3.
  - L'énoncé de la VSA ([`r5-vsa-enonce.json`](resultats/r5-vsa-enonce.json)) contient :
    - `policy.uri` au commit `309644f4…`, digest `4f1cca93…` ;
    - `inputAttestations` `horodatage/bundles@sha256:f5969ecf…` ;
    - `verifier.version`, qui donne les sha256 de `verifier_entrees.py`, `rebuild.sh` et `vsa.py` ;
    - `PASSED`, avec `SLSA_BUILD_LEVEL_3` et `POC_REPLAY_BIT_IDENTIQUE`.
  - Signé par la clé du domaine (`attest-blob --statement`, configuration sans service) puis revérifié : `Verified OK`. Le bundle est en v0.3, sans journal de transparence ni horodatage ([`r5-vsa.bundle.json`](resultats/r5-vsa.bundle.json)).
- **Porte de la 08 avant le push** (14:58 UTC, [`r5-porte_avant.log`](resultats/r5-porte_avant.log)) : ec admet l'image réelle sans violation, et le contrôle 9 est `ok` (6/6 enveloppes couvertes, 43 bundles). Constat : sur un dépôt inconnu, l'API referrers de Zot rend un index vide (HTTP 200), et non une erreur.
- **VSA poussée** (15:00 UTC, choix du propriétaire : « Pousser la VSA », [`r5-pousser_vsa.log`](resultats/r5-pousser_vsa.log)) : manifeste fait main `sha256:c1bfbcbd…`, égal au digest calculé d'avance. Il est poussé par digest, avec le compte `poc-replay`, dans `builds/vsa/sample-app`. On y trouve un seul referrer de l'image et aucune étiquette ; `builds/sample-app` n'a toujours aucun referrer. Vérifiée sur l'hôte sans aucune connexion.
- **Porte de la 08 après le push** (15:02 UTC, [`r5-porte_apres.log`](resultats/r5-porte_apres.log)) : même verdict qu'avant, durée exclue (ec admet, contrôle 9 `ok`, 6/6) ; `builds/vsa/sample-app` a 1 referrer. Le dépôt séparé ne gêne pas la porte.
  - Le premier passage avait rendu `KO` à cause du script de la brique 10, qui comparait aussi le libellé du cas. Ce passage est archivé, et le script est corrigé.
- **Lecture et N3** (15:03 UTC, [`r5-lire_vsa.log`](resultats/r5-lire_vsa.log)) :
  - la VSA est acceptée avec sa clé, et refusée avec celle de Chains ;
  - la provenance est refusée avec la clé de VSA, et acceptée avec celle de Chains (6 attestations) ;
  - chaque commande cosign n'ouvre qu'une connexion, vers Zot.
- **Contre-épreuves N1 et N2** (15:04 UTC, dans la VM, sur des copies, [`r5-negatifs.log`](resultats/r5-negatifs.log)) :
  - **N1** (un octet changé dans le zip de `go-chi/chi`, zip resté valide) : build refusé par Go (`checksum mismatch`, `SECURITY ERROR`), `FAILED` ;
  - **N2** (`":8080"` remplacé par `":8081"` dans `main.go`) : image `fa05b94a…`, différente du sujet, `FAILED` ;
  - diffoscope ([couche](resultats/r5-n2-diffoscope-couche.txt), [config](resultats/r5-n2-diffoscope-config.txt)) : seul le binaire `sample-app` diffère, d'un octet, et dans la config seul `rootfs.diff_ids`.
- **R5 est complet.**
- **Hors R5, non tranché** : la porte de la 08 n'exige pas encore la VSA (contrôle 6 de la grille C). Elle admet l'image avec ou sans VSA.
  - **Préparé à sec le 03/11/2026 à 15:25 UTC** (choix du propriétaire : « Contrôle 6 d'abord ») : conteneur `vsa` dans la porte de la 08, prédictions datées dans [`controle6-predictions.md`](../08-trust-plane/resultats/controle6-predictions.md). Rien n'est appliqué au cluster.
  - **Mesuré le 03/11/2026, de 15:30 à 15:32 UTC** (choix du propriétaire : « Lancer controle6 » ; [`preuves-controle6.log`](../08-trust-plane/resultats/preuves-controle6.log)), avec 0 écart : la porte admet l'image réelle avec sa VSA. Elle refuse le même digest sans VSA (`essai-webhook`) et une VSA vérifiée avec la clé de Chains. La porte en service exige désormais la VSA.
