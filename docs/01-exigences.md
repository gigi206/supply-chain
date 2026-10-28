# Exigences, modèle de menace et contrôles SLSA Build L3

> Les seuils chiffrés des briques sont dans le [README](../README.md#briques-et-seuils) ; les choix d'outils dans [`00-etude-existant.md`](00-etude-existant.md).
> Référence : **SLSA v1.2** (statut « Approved »), textes vérifiés sur [slsa.dev/spec/v1.2](https://slsa.dev/spec/v1.2/build-requirements).

## 1. Besoins et critères vérifiables

| # | Besoin | Critère vérifiable | Brique(s) |
|---|---|---|---|
| B1 | Rejouer un binaire **bit à bit** | Deux builds de la même entrée donnent le même sha256 (contenu hors signature OpenPGP). Le replay **dans un domaine indépendant** annonce « bit-identical » et produit une VSA. EL8 au mieux, avec les écarts documentés | 04, 05, 06, 10 |
| B2 | Archiver les résultats de build (binaire, image, lib, rpm, deb) | Chaque artefact est stocké dans Zot, adressé par digest, avec provenance, SBOM, VEX, licences et VSA en referrers. Copie en archive WORM (2c) | 02, 15 |
| B3 | SBOM | SBOM CycloneDX 1.6 (Syft + Hermeto) attaché à 100 % des artefacts. 0 composant `NOASSERTION` sur la licence | 07a, 13a |
| B4 | Archiver **toutes** les dépendances (go, npm, python, paquets OS) | Fermeture des dépendances (Hermeto, lockfile mock, `.buildinfo`) restaurable par digest. Déduplication ≥ 50 % entre deux builds proches | 03, 14 |
| B5 | Rejouer le build complet **offline** | Build et replay réussissent avec **0 connexion sortante**, journalisée (NetworkPolicy deny-all) | 04, 10 |
| B6 | Score de fiabilité (vulnérabilités, santé) | La porte bloque MAL-, KEV sans VEX, provenance ou signature invalide, non-reproductibilité hors EL8. Le score informatif versionné se calcule en moins de 5 min | 07a, 07b |
| B7 | Synchroniser des dépôts git distants et créer des branches custom | Miroir et fork Forgejo. Un force-push amont est détecté et archivé (`refs/archive/*`), avec un `git bundle` exporté. Le build part d'un commit exact de la branche custom | 01 |
| B8 | rpm et deb multi-distro | Bit-identique sur rocky-9 et debian-13 (2b-2), puis debian-12, ubuntu-24.04, alma-9 et centos-stream-10 (2c). Signés en OpenPGP avec attestation de lien | 05, 06, 09, 16 |
| B9 | Provenance | Provenance SLSA v1.0 (`slsa/v2alpha4`) générée **et signée par Chains**, stockée en referrer et horodatée (TSA) | 08 |
| B10 | **SLSA Build L3** | Les contrôles du §3 sont en place et **les 8 tests négatifs échouent comme attendu** | 08, 10 |
| B11 | Analyse de licences complète | 0 violation ERROR. NOTICE et SBOM « concluded » attestés. Sources GPL conservées 10 ans | 13a, 13b |
| B12 | Kubernetes ou docker compose | Décidé par l'ADR 0001. L3 exige Kubernetes : compose seul plafonne à L2 | ADR 0001 |
| B13 | Projets maintenus | Aucun projet « Risqué » en usage. Projets « À surveiller » du chemin critique avec plan de sortie. Ré-audit trimestriel | `tools/health`, doc 04 |
| B14 | Observabilité | Les 5 alertes critiques se déclenchent sur incident simulé. KPI dérivés des attestations, avec 0 écart au recalcul | 19, 20 |

**Contraintes non fonctionnelles :**
- **amd64 uniquement**, modèle CPU **x86-64-v3** fixé dans les sandboxes et inscrit dans la provenance (EL10 l'exige) ;
- fonctionnement **air-gap** possible ;
- conservation sur **10 ans** des artefacts, attestations, sources GPL et bases de vulnérabilités datées ;
- uniquement des projets open source maintenus.

## 2. Modèle de menace

### 2.1 Actifs à protéger

| Actif | Pourquoi |
|---|---|
| Sources (miroirs amont, branches custom) | Tout part d'un commit exact |
| Fermetures de dépendances et snapshots de distros | Contenu réellement compilé |
| Images de build et tâches Tekton | Un builder compromis empoisonne tout ce qu'il produit |
| **Clé de provenance** (OpenBao Transit) | Permet de forger un L3 |
| Clé VSA (domaine de replay), clés OpenPGP (HSM), racine TUF (hors ligne) | Confiance des consommateurs |
| Artefacts et attestations (Zot, WORM) | Ce qui est livré et prouvé |
| Politiques (Conforma, Kyverno, licences, VEX) | Une politique affaiblie laisse tout passer |

### 2.2 Acteurs malveillants considérés

- **Code amont non fiable** : un mainteneur compromis ou un tag réécrit (cas Trivy en 03/2026).
- **Dépendance malveillante** : typosquatting, compte de publication compromis, `postinstall` npm.
- **Étape de build hostile** : le code compilé tente de lire la clé, d'empoisonner un cache, de sortir sur le réseau ou de falsifier un résultat.
- **Administrateur interne** : un seul administrateur ne doit pas pouvoir forger une provenance et sa vérification (d'où le **domaine de replay distinct**).
- **Attaquant réseau** : webhook forgé ou rejoué, registre altéré, miroir empoisonné.
- **Compromission d'un outil de la chaîne** : outil de scan ou de build compromis (cas Trivy), d'où l'épinglage par digest, la vérification des signatures et la reconstruction des images d'outils.

### 2.3 Menaces SLSA (A à I) et contrôles

| Menace SLSA | Exemple chez nous | Contrôles | Test négatif ou vérification |
|---|---|---|---|
| **A**. Producteur | Projet amont malveillant | Santé amont (Scorecard), posture CI amont (O8), malicious-packages, revue des branches custom | Paquet MAL- de test bloqué par la porte |
| **B**. Rédaction et revue | Patch malveillant dans une branche custom | Revue par PR dans Forgejo ; gittuf et commits signés SSH (Source Track, O1) | Push non signé refusé (pilote gittuf) |
| **C**. Gestion des sources | Réécriture d'historique amont, miroir altéré | Job de sync sans prune, `refs/archive/*`, détection des force-push, `git bundle` en WORM | Force-push amont simulé, détecté et archivé |
| **D**. Paramètres externes | Déclenchement forgé, paramètre injecté | Intercepteur HMAC Forgejo (anti-rejeu), RBAC du seul déclencheur, `externalParameters` vérifiés par Conforma | **Webhook non signé ou rejoué refusé** |
| **E**. Processus de build | Étape qui lit la clé, empoisonne un cache, falsifie un `status` | Chains et OpenBao sur nœuds dédiés ; pod éphémère ; isolation Kata, gVisor ou user namespace ; PVC par run ; démon BuildKit éphémère ; Trusted Resources et `trusted_task` ; Kyverno (pas d'inline, de `hostPath` ni de `privileged` hors Kata) ; posture des pipelines (tekton-lint, Rego) | **Lecture du jeton OpenBao, `taskSpec` inline, modification d'un `status`, pod privilégié ou `hostPath`, sortie réseau : tous refusés** |
| **F**. Publication | Artefact publié sans provenance, ou modifié | Porte Conforma, Kyverno à l'admission, horodatage TSA | **Artefact non signé refusé ; jeton TSA absent ou falsifié refusé** |
| **G**. Canal de distribution | Registre ou dépôt altéré | Digests partout, `oras cp -r`, WORM, TUF pour les clés publiques, OpenPGP sur les dépôts | Digest modifié détecté par `tools/index` et la vérification |
| **H**. Sélection du paquet | Mauvais paquet ou typosquatting | Lockfiles et fermetures, PURL, malicious-packages, GuardDog | Paquet typosquatté signalé |
| **I**. Usage | Artefact consommé sans vérification | Kyverno `ImageValidatingPolicy` côté déploiement ; documentation de vérification pour les consommateurs | Image non vérifiée refusée à l'admission |
| **Fermeture archivée** (transverse) | Fermeture de dépendances altérée entre le prefetch et le build, ou dans l'archive avant un replay | Fermeture tirée de Zot par digest (inscrit dans `resolvedDependencies`), montée en lecture seule ; Go : fermeture servie en `GOPROXY` avec `GOMODCACHE` vierge, jamais l'environnement de `hermeto generate-env` tel quel, plus `go mod verify` ; npm : intégrité sha512 du lockfile | **Zip Go et archive npm altérés : build refusé** (banc B, [`hermeto.sh`](../poc/benchmarks/nix/reference/hermeto.sh)) |
| **Dépendances** (transverse) | Dépendance vulnérable ou compromise | Grype, OSV, DT, VEX, base datée, score | Cas KEV bloqué par la porte |

## 3. Exigences SLSA Build L3 → contrôles

Citations vérifiées sur SLSA v1.2 :

| Exigence (citation) | Contrôle |
|---|---|
| « Every field in the provenance MUST be generated or verified by the build platform in a trusted control plane. » | Chains génère la provenance depuis le plan de contrôle. Conforma vérifie `resolvedDependencies` et `externalParameters`. La plateforme, et non la tâche, inscrit le mode hermétique |
| **Exception** : « The names and cryptographic digests of the output artifacts, i.e. subject in SLSA Provenance » peuvent être fournis par le build | Résultats Tekton `*_ARTIFACT_*` / `IMAGE_DIGEST` admis ; c'est la vérification (replay) qui en assure la cohérence |
| « Such secret material MUST NOT be accessible to the environment running the user-defined build steps. » | Clé dans OpenBao Transit, auth k8s du **seul** compte Chains, politique `sign`, nœuds dédiés, audit activé |
| « an ephemeral build environment MUST be provisioned for each build » | Un pod par TaskRun, un PVC par run (`volumeClaimTemplate`), démon BuildKit éphémère |
| « It MUST NOT be possible for one build to inject false entries into a build cache used by another build… the output of the build MUST be identical whether or not the cache is used » | Caches désactivés ou protégés contre l'empoisonnement. **Seuil : build avec cache = build sans cache** |
| « MUST NOT open services that allow for remote influence unless… captured as externalParameters » | Pas de service exposé par les pods de build ; NetworkPolicy deny-all |
| Recommandation : « methods which rely on transparency logs or, when transparency isn't appropriate, time stamping services » | Job TSA hors des pods de build ; vérification par bundle réémis ou `tools/verify-ts` |

### Tests négatifs obligatoires (brique 08)

Chacun **doit échouer** et produire une trace :

1. Lire le jeton ou la clé OpenBao depuis une tâche de build.
2. Lancer un TaskRun avec un `taskSpec` inline.
3. Modifier le `status` ou les résultats d'un TaskRun terminé.
4. Lancer un pod privilégié hors Kata, ou monter un `hostPath`.
5. Envoyer un webhook Forgejo non signé, ou rejouer un webhook valide.
6. Ouvrir une connexion réseau sortante pendant l'étape de build.
7. Publier ou admettre un artefact non signé, **y compris un artefact qui ne porte que des attestations signées**. Avec les bundles cosign v3, `cosign verify`, Conforma et Kyverno l'acceptent par défaut : exiger le type `https://sigstore.dev/cosign/sign/v1` (banc C).
8. Présenter une attestation avec un jeton d'horodatage absent ou falsifié.

## 4. Autres propriétés (distinctes de L3)

| Propriété | Exigence | Vérification |
|---|---|---|
| Reproductibilité | `SOURCE_DATE_EPOCH` ; images, outils et tâches épinglés par digest ; normalisation (strip-nondeterminism, add-determinism) | Double build + **replay dans un domaine d'administration distinct**, avec une autre clé de VSA, des caches froids et au moins 24 h d'écart ; diffoscope en cas d'écart |
| Hermétisme | Prefetch et build dans des pods distincts ; aucune sortie réseau pendant le build | Journal d'egress vide ; trace Tetragon `runtime-trace` (2c) ; replay offline |
| Offline | Toutes les entrées viennent de Zot ou des snapshots internes | Replay avec egress complètement bloqué |
| Conservation | 10 ans pour artefacts, attestations, sources GPL, bases de vulnérabilités datées | Archive WORM (ADR 0006), test de restauration (brique 12) |
| Clés | Séparation par usage (provenance, VSA, OpenPGP, TUF), rotation, révocation, racine hors ligne, cérémonie | ADR 0003. Une attestation reste vérifiable après rotation |
| Licences | Politique ORT et DT, curations revues, obligations GPL | Brique 13 |

## 5. Hypothèses et hors périmètre

- Un seul tenant (l'organisation). Le code amont reste **non fiable** par principe.
- Pas de distribution publique au début : la distribution externe des clés passe par TUF (ADR 0003).
- RHEL et Ubuntu Pro ne servent pas de dépendances redistribuées (licences).
- arm64 hors périmètre initial (option O3).
- Le « Build Environment track » (attestation matérielle) est encore en brouillon chez SLSA : il reste en veille.
