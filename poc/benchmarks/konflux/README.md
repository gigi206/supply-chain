# A1 : Konflux

**But** : noter Konflux sur la grille A de l'ADR 0000, face à la référence « assemblage » (57/100).

**Prérequis** : infra du PoC (ADR 0001), Forgejo avec un dépôt de test, sample-app.

## Protocole (≤ 3 jours)

1. **Installation** (≤ 1 jour) : opérateur Konflux sur k3s ou Kind, version stable épinglée (pas de RC). Mesurer le temps, la RAM au repos et le nombre de pods et composants.
2. **Intégration Forgejo** : Pipelines-as-Code ou autre déclencheur. Vérifier que le webhook est **authentifié** : un webhook non signé doit être refusé.
3. **Premier build signé** (≤ 2 jours) : sample-app en image OCI (Buildah, mode hermétique, prefetch Hermeto), avec provenance Chains et vérification Conforma.
4. **Tests négatifs** : rejouer les 8 tests du doc 01 et compter ceux que Konflux bloque nativement (A-2).
5. **Reproductibilité** : 2 builds de l'image, comparaison des digests (A-3).
6. **deb** : évaluer l'ajout d'une tâche sbuild **sans forker** le cœur (custom pipeline). Sinon, estimer l'effort (A-4).
7. **rpm rocky-9** : pipeline mock de Konflux, puis 2 builds et comparaison.
8. Estimer les pw nécessaires pour couvrir B1 à B14 (A-4).

## Mesures à archiver dans `resultats/`

- Versions et digests ; `kubectl get pods -A` ; consommation mémoire.
- Journaux des tests négatifs, provenance obtenue, sortie Conforma.
- sha256 des artefacts des deux builds.

## Résultats (29/10/2026)

**17/100 contre 57 pour la référence : Konflux n'est pas adopté** ; **éliminé** au titre du critère 1 (confirmé par le propriétaire le 29/10/2026). Détail, preuves et notation : [`resultats/README.md`](resultats/README.md). Rejeu : `mise run konflux:preparer`, puis `deployer`, `forgejo`, `onboarder`, `parametrer`, `verifier`, `tests-negatifs`, `t6-hermetique` et `preuves` ; démontage : `mise run konflux:demonter` et `mise run konflux:forgejo -- stop`.

## Préparation sur le laptop (29/10/2026) : validée par le propriétaire et exécutée

### Version et installation

- **Konflux v0.2.2** : dernière version stable, du 07/09/2026. Les versions `v0.2.3-rc.*` sont exclues, car le protocole interdit les RC.
  - Commit `be0e6cac`. Le tag est annoté mais **non signé**.
  - `install.yaml` a pour sha256 `68fbb841e8c83a6c…`. Le fichier téléchargé et archivé est appliqué tel quel, pas l'URL.
- **Méthode** : `scripts/deploy-local.sh` de ce tag, avec :
  - `OPERATOR_INSTALL_METHOD=release` et `OPERATOR_RELEASE=v0.2.2` ;
  - `SKIP_SECRETS=true` : ni GitHub App, ni secrets ;
  - `SKIP_SMEE=true` : aucun relais de webhooks par smee.io ;
  - Quay ignoré, ce qui est le défaut ;
  - télémétrie Segment (`api.segment.io`) **désactivée explicitement** dans le CR, alors qu'elle l'est déjà par défaut.
- **Cluster** : kind 0.33.0, nœud `kindest/node:v1.37.0@sha256:a1ed56cf…` (digest donné dans les notes de release de kind). Les autres options :
  - `KUBECONFIG` dédié (`~/.kube/supply-chain-poc-konflux.yaml`), jamais fusionné dans `~/.kube/config` ;
  - copie de travail sur disque, dans `~/.cache/supply-chain-poc/` ;
  - le réseau docker `kind`, déjà présent, est conservé au démontage.

### Isolation de l'hôte

- **Ports sur loopback seulement.** Docker publie ses ports en contournant ufw, et l'interface a des comptes de démonstration à mot de passe fixe. La copie de `kind-config.yaml` met donc `listenAddress: "127.0.0.1"` sur chaque port publié :
  - 9443 (interface) ;
  - 8180 (PaC) ;
  - 5001 (registre sans authentification) ;
  - 8888.

  Elle retire aussi le port 8443 (Quay), déjà occupé sur l'hôte. Contrôle après création : `docker port konflux-control-plane`.
- **Mémoire plafonnée.** Sous Linux, `KIND_MEMORY_GB` ne règle que `system-reserved`, et le nœud verrait les 61 Gi de l'hôte, qui n'a pas de swap. Le nœud est donc plafonné à **20 Gi** avec `docker update --memory=20g --memory-swap=20g`. Konflux recommande 16 Gi pour la pile complète.
- **Démontage** : `kind delete cluster --name konflux`, puis suppression du `KUBECONFIG` dédié et de la copie de travail.

### Images et vérifiabilité

| Élément | Origine | Vérifiable ? |
|---|---|---|
| Opérateur `quay.io/konflux-ci/konflux-operator@sha256:36493a95…` | Construit par Konflux | **Non** : signature par clé (`.sig`, `.att`, `.sbom`), sans certificat ni Rekor, et aucune clé publique publiée. C'est le même cas que Tekton et Conforma (doc 04 §5) |
| Composants : build-service, integration, release, UI, image-controller, namespace-lister, Dex, oauth2-proxy, Zot… | Épinglés par digest ou par commit dans les manifestes de l'opérateur | **Non**, même cause |
| Tekton operator v0.81.1 (`release.yaml` de infra.tekton.dev), puis Pipelines, Chains, Triggers et PaC | Tekton | **Non** : `release.yaml` non signé, images non vérifiables (doc 04 §5) |
| cert-manager v1.21.1, trust-manager v0.24.0 | Jetstack | À vérifier ; versions épinglées par tag |
| Bundles de tâches `quay.io/konflux-ci/tekton-catalog/*` | Épinglés par digest | Non (Konflux) |
| Nœud kind | Digest donné dans les notes de release de kind | Épinglé, non signé |

Règle du doc 04 : on reconstruit les images d'outils, ou on les épingle par digest après revue. Pour un banc jetable de 3 jours, reconstruire Konflux est hors de portée. **Proposition** : épingler par digest, ne rien conserver après le banc, et archiver dans `resultats/` les `imageID` réels de tous les conteneurs (ces mêmes données servent à A-5).

**Registres contactés** : quay.io, ghcr.io, registry.k8s.io, docker.io, infra.tekton.dev, registry.access.redhat.com, ainsi que les registres des images de tâches. `registry.redhat.io` exige une authentification : s'il est appelé, on le note et le composant concerné sera « non démontré ».

### Forgejo (étape 2 du protocole)

Forgejo **15.0.11 LTS** (Codeberg) sera installé par `mise.toml`, en binaire, car son image OCI n'est pas signée.
- Vérification : sha256 et signature GPG (`.asc`), avec l'empreinte de clé publiée sur forgejo.org.
- Écoute : uniquement sur la passerelle du réseau `kind`, jamais sur 0.0.0.0.
- Données : SQLite, dans `~/.cache/supply-chain-poc/`.
- Mot de passe administrateur : dans un fichier en 0600, jamais dans les journaux.
- Intégration : PaC en mode Forgejo (fournisseur « gitea »).

### Outils à ajouter à `mise.toml`

| Outil | Version | Vérification |
|---|---|---|
| kind | 0.33.0 (aqua) | sha256 amont |
| kubectl | 1.37.x (aqua) | sha256 et signature sigstore des binaires Kubernetes (identité donnée par la doc Kubernetes) |
| Forgejo | 15.0.11 (backend `forgejo`) | sha256 et GPG |

### Ressources prévues

| Ressource | Prévision |
|---|---|
| RAM | 20 Gi au plus (plafond du nœud), sur environ 30 Gi disponibles |
| Disque | 25 à 40 Go d'images dans `/var/lib/docker` (sur `/`, 88 Go libres) |
| Ports | 9443, 8180, 5001 et 8888 sur 127.0.0.1, tous libres ; 8443 non utilisé |

### Règles de comptage, fixées avant de mesurer (validées par le propriétaire le 29/10/2026)

- **A-2, tests négatifs.** Chaque test du doc 01 est transposé à son équivalent Konflux. Si le contrôle n'existe pas, le test compte « non bloqué » : il n'y a pas de catégorie « non applicable ».
  1. Lecture de la clé de signature de Chains (secret Kubernetes) depuis une tâche de build.
  2. `taskSpec` inline.
  3. Modification du `status` d'un TaskRun terminé.
  4. Pod privilégié ou `hostPath` dans un espace de noms de tenant, contrôlé à l'admission. Le nœud kind lui-même n'est pas jugé.
  5. Webhook Forgejo non signé ou rejoué.
  6. Sortie réseau en build hermétique.
  7. Artefact non signé, ou ne portant que des attestations, admis ou publié.
  8. Jeton d'horodatage absent ou falsifié.
- **A-5, nombre de composants** : nombre de Deployments, StatefulSets et DaemonSets des espaces de noms créés par Konflux et ses dépendances, hors `kube-system` et `local-path-storage`. **RAM au repos** : mémoire du conteneur nœud (`docker stats`), après 30 minutes sans build.
- **Chronomètre** : il démarre au lancement de `deploy-local.sh`. Chaque étape est journalisée, pour les seuils « installation ≤ 1 j » et « premier build signé ≤ 2 j ». Au-delà de 3 jours, ce qui reste est « non démontré ».

### Risques connus (non bloquants)

- **rpm mock et deb** : ces pipelines peuvent exiger le multi-platform-controller ou des hôtes distants, absents de kind. Ce serait alors « non démontré », avec un effort estimé (A-4).
- **Webhook Forgejo** : PaC en mode Forgejo ne vérifie peut-être pas la signature du webhook (doc 00). Dans ce cas, le seuil « webhook authentifié » n'est pas démontré.
- **Format de provenance** : Konflux configure Chains en `artifacts.*.format: in-toto`, c'est-à-dire une provenance SLSA v0.2, et non `slsa/v2alpha4` (SLSA v1, exigence B9). À mesurer.
- **Stockage des attestations** : Konflux configure Chains en stockage `oci` (tags `.sig`/`.att`), qui n'est pas concerné par chains#2096. La version de Chains sera relevée.
- **Pipeline de build** : les tâches du pipeline docker-build peuvent appeler des services externes (catalogue Red Hat, scanners). La liste des tâches du bundle épinglé sera relevée avant le premier build, et toute sortie vers un tiers sera notée.
- **Composants hors audit** : cert-manager, trust-manager, Dex, Kueue, oauth2-proxy, etc. ne sont pas audités dans le doc 04. Ils entrent dans la note A-6 du candidat, et rien n'est conservé après le banc.
