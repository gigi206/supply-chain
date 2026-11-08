# Audit de santé et de maintenance des projets

> Relevé du **28/10/2026**. À régénérer **chaque trimestre** avec `tools/health/scorecard.sh` (voir §6).
> Exigence : n'utiliser que des projets suffisamment actifs et maintenus. Un projet « Risqué » n'est jamais utilisé ; un projet « À surveiller » du chemin critique a un **plan de sortie**.

## 1. Critères

**Santé :**
- release ≤ 6 mois ;
- commits sur les 90 derniers jours ;
- ≥ 3 contributeurs actifs, **issus d'au moins 2 employeurs** ;
- processus de sécurité (SECURITY.md, avis publiés) ;
- **releases signées avec provenance**, vérifiées sur les images OCI (le contrôle Scorecard ne regarde que les fichiers attachés aux releases GitHub) ;
- délai de correction des CVE ;
- CLA combiné à un éditeur unique, signalé comme risque de changement de licence ;
- **OpenSSF Scorecard ≥ 6**.

| Verdict | Règle |
|---|---|
| **Sain** | Tous les critères sont remplis (ou presque, avec justification) |
| **À surveiller** | Un critère manque, bus factor de 1 ou 2, Scorecard < 6, ou maturité 0.x/alpha/beta |
| **Risqué** | Aucune release depuis plus de 12 mois, projet archivé, mainteneur unique sans soutien, ou compromission non résolue → **interdit** |

La **maturité** (0.x, alpha, beta) est notée à part. La **criticité** (chemin critique) et l'**adoption** pondèrent le verdict. Par exemple, l'absence de SECURITY.md sur un outil de distro (mock, diffoscope) n'est pas bloquante si le processus sécurité de la distro s'applique.

## 2. Relevé OpenSSF Scorecard (API publique)

Généré par `tools/health/scorecard.sh` :
- « n/d » : dépôt absent de l'analyse automatique de Scorecard. Il faudra le CLI `scorecard` avec un `GITHUB_AUTH_TOKEN`.
- « n/a » : projet hors GitHub, vérifié manuellement au §4.
- **Ne jamais mélanger** ces scores avec ceux de `scorecard --local`, qui n'exécute qu'une partie des contrôles.
- Relevés anciens : **sbomqs (2024-07-05)** et **Grype (2026-05-18)**. L'API ne se rafraîchit pas à la demande ; il faut le CLI avec un jeton.

Relevé du 2026-10-28 via https://api.securityscorecards.dev ; k3s, kind et k3d ajoutés le 2026-10-29 ; Cilium et kube-router (amont) ajoutés le 2026-10-30, candidats au contrôle réseau de la zone build (brique 08, J7 ; même API).

| Projet | Dépôt | Domaine | Chemin critique | Score | Date du relevé | Maintained | Signed-Releases | Code-Review | Vulnerabilities |
|---|---|---|---|---|---|---|---|---|---|
| Tekton Pipelines | tektoncd/pipeline | orchestration | oui | 6.7 | 2026-10-26 | 10 | 0 | 10 | 0 |
| Tekton Chains | tektoncd/chains | provenance | oui | 7.1 | 2026-10-19 | 10 | 0 | 10 | ? |
| Tekton Triggers | tektoncd/triggers | orchestration | oui | 6.9 | 2026-10-19 | 10 | 0 | 8 | ? |
| Conforma | conforma/cli | politique | oui | 6.6 | 2026-10-28 | 10 | 0 | 10 | 0 |
| Conforma policy | conforma/policy | politique | oui | 7.0 | 2026-10-29 | 10 | -1 | 8 | 0 |
| Kyverno | kyverno/kyverno | politique | oui | 7.8 | 2026-10-13 | 10 | 8 | 10 | 7 |
| Hermeto | hermetoproject/hermeto | dépendances | oui | n/d | — | — | — | — | — |
| mock | rpm-software-management/mock | packaging | oui | 4.9 | 2026-10-19 | 10 | 0 | 7 | ? |
| BuildKit | moby/buildkit | construction | oui | 8.6 | 2026-10-26 | 10 | 8 | 10 | ? |
| Buildah | containers/buildah | construction | non | 8.2 | 2026-10-26 | 10 | -1 | 10 | ? |
| Syft | anchore/syft | sbom | oui | 8.7 | 2026-10-26 | 10 | 8 | 10 | ? |
| Grype | anchore/grype | vulnérabilités | oui | 8.2 | 2026-05-18 | 10 | 8 | 8 | 7 |
| vunnel | anchore/vunnel | vulnérabilités | non | n/d | — | — | — | — | — |
| grype-db | anchore/grype-db | vulnérabilités | non | 7.5 | 2026-10-26 | 10 | 0 | 10 | ? |
| Dependency-Track | DependencyTrack/dependency-track | vulnérabilités | non | 7.5 | 2026-10-26 | 10 | 10 | 1 | ? |
| OSV-Scanner | google/osv-scanner | vulnérabilités | non | 8.6 | 2026-10-28 | 10 | 10 | 10 | -1 |
| Trustify | guacsec/trustify | vulnérabilités | non | n/d | — | — | — | — | — |
| Zot | project-zot/zot | stockage | oui | 8.1 | 2026-10-28 | 10 | 0 | 8 | 2 |
| ORAS | oras-project/oras | stockage | oui | 7.6 | 2026-10-19 | 10 | 8 | 10 | ? |
| Harbor | goharbor/harbor | stockage | non | 7.8 | 2026-10-26 | 10 | 3 | 10 | ? |
| Pulp (pulpcore) | pulp/pulpcore | stockage | non | n/d | — | — | — | — | — |
| aptly | aptly-dev/aptly | stockage | non | 3.4 | 2026-10-26 | 5 | 0 | 7 | ? |
| Verdaccio | verdaccio/verdaccio | stockage | non | 6.7 | 2026-10-19 | 10 | -1 | 6 | ? |
| Athens | gomods/athens | stockage | non | 5.8 | 2026-10-19 | 10 | 0 | 10 | ? |
| Rook | rook/rook | stockage | non | 8.8 | 2026-10-28 | 10 | -1 | 10 | 6 |
| Ceph | ceph/ceph | stockage | non | 4.6 | 2026-10-26 | 10 | -1 | 9 | ? |
| cosign | sigstore/cosign | signature | oui | 8.4 | 2026-10-26 | 10 | 8 | 10 | 7 |
| timestamp-authority | sigstore/timestamp-authority | signature | oui | 8.6 | 2026-10-27 | 10 | 2 | 10 | 4 |
| OpenBao | openbao/openbao | signature | oui | 8.5 | 2026-10-27 | 10 | 8 | 10 | 0 |
| python-tuf | theupdateframework/python-tuf | signature | non | 8.4 | 2026-10-26 | 10 | 3 | -1 | 10 |
| go-tuf | theupdateframework/go-tuf | signature | non | 7.5 | 2026-10-19 | 10 | -1 | 10 | ? |
| Kata Containers | kata-containers/kata-containers | isolation | non | 6.9 | 2026-10-28 | 10 | 8 | 9 | 0 |
| gVisor | google/gvisor | isolation | non | 6.2 | 2026-10-19 | 10 | 0 | 0 | ? |
| k3s | k3s-io/k3s | runtime | oui | 8 | 2026-10-29 | 10 | 0 | 10 | 0 |
| RKE2 (ajouté le 05/11/2026, brique 08b) | rancher/rke2 | runtime | oui | 5.9 | 2026-10-26 | 10 | 0 | 10 | ? |
| cert-manager (ajouté le 05/11/2026, brique 08b) | cert-manager/cert-manager | signature | non | 8.4 | 2026-11-05 | 10 | 0 | 10 | 9 |
| local-path-provisioner (ajouté le 05/11/2026, brique 08b) | rancher/local-path-provisioner | stockage | non | 5.5 | 2026-11-02 | 10 | -1 | 2 | ? |
| kube-bench (ajouté le 05/11/2026, brique 08b) | aquasecurity/kube-bench | conformité | non | 5.2 | 2026-03-16 | 10 | 0 | 10 | ? |
| podman (ajouté le 05/11/2026, briques 05 et 06 ; dépôt renommé `podman-container-tools/podman`) | containers/podman | construction | oui | 7.8 | 2026-11-02 | 10 | 0 | 10 | ? |
| skopeo (ajouté le 05/11/2026, brique 05 ; dépôt renommé `podman-container-tools/skopeo`) | containers/skopeo | construction | oui | 8.6 | 2026-11-02 | 10 | -1 | 10 | ? |
| images Rocky, debuerreotype, images Debian (ajoutés le 05/11/2026, briques 05 et 06) | rocky-linux/sig-cloud-instance-images, debuerreotype/debuerreotype, debuerreotype/docker-debian-artifacts | image de base | oui | n/d | — | — | — | — | — |
| kind | kubernetes-sigs/kind | runtime | non | 6.6 | 2026-10-19 | 10 | 0 | 10 | ? |
| k3d | k3d-io/k3d | runtime | non | 3.6 | 2026-10-26 | 2 | 0 | 6 | ? |
| Cilium | cilium/cilium | réseau | oui | 6 | 2026-10-26 | 10 | -1 | 10 | ? |
| cilium/proxy (Envoy de Cilium ; relevé du 03/11/2026, brique 03, F2) | cilium/proxy | réseau | oui | 4.4 | 2026-10-26 | 10 | -1 | 1 | ? |
| Helm | helm/helm | installation | non | 9.1 | 2026-11-01 | 10 | 8 | 10 | 7 |
| kube-router (amont) | cloudnativelabs/kube-router | réseau | oui | 7.5 | 2026-10-26 | 10 | 0 | 10 | 2 |
| Tetragon | cilium/tetragon | isolation | non | n/d | — | — | — | — | — |
| Witness | in-toto/witness | provenance | non | 7.9 | 2026-10-24 | 8 | 8 | 8 | 0 |
| gittuf | gittuf/gittuf | sources | non | 9.3 | 2026-10-28 | 10 | 8 | 10 | 7 |
| Chainloop | chainloop-dev/chainloop | provenance | non | 8.4 | 2026-10-28 | 10 | 8 | 10 | 1 |
| Renovate | renovatebot/renovate | maintenance | non | 6.7 | 2026-10-28 | 10 | 0 | 10 | 0 |
| ORT | oss-review-toolkit/ort | licences | non | 6.3 | 2026-10-28 | 10 | 8 | 10 | 0 |
| ScanCode toolkit | aboutcode-org/scancode-toolkit | licences | non | n/d | — | — | — | — | — |
| REUSE | fsfe/reuse-tool | licences | non | 4 | 2026-10-26 | 10 | -1 | 1 | ? |
| Grant | anchore/grant | licences | non | n/d | — | — | — | — | — |
| sbomqs | interlynk-io/sbomqs | sbom | non | 7 | 2024-07-05 | 10 | 0 | 10 | 10 |
| GuardDog | DataDog/guarddog | vulnérabilités | non | 7.2 | 2026-10-26 | 10 | -1 | 10 | 0 |
| malicious-packages | ossf/malicious-packages | vulnérabilités | non | 7.3 | 2026-10-28 | 10 | -1 | 1 | 1 |
| Scorecard | ossf/scorecard | santé | non | 8.6 | 2026-10-28 | 10 | 10 | 3 | 6 |
| OBS | openSUSE/open-build-service | packaging | non | 6.9 | 2026-10-28 | 10 | -1 | 8 | 10 |
| Konflux | konflux-ci/konflux-ci | socle | non | n/d | — | — | — | — | — |
| Argo CD | argoproj/argo-cd | déploiement | non | 8.9 | 2026-10-28 | 10 | 10 | 10 | 0 |
| Prometheus | prometheus/prometheus | observabilité | non | 8.1 | 2026-10-28 | 10 | 0 | 10 | 0 |
| Alertmanager | prometheus/alertmanager | observabilité | non | 6.6 | 2026-10-26 | 10 | 0 | 10 | ? |
| Grafana | grafana/grafana | observabilité | non | 7 | 2026-10-26 | 10 | 0 | 10 | ? |
| Loki | grafana/loki | observabilité | non | 8.4 | 2026-10-19 | 10 | 0 | 10 | ? |
| Grafana Alloy | grafana/alloy | observabilité | non | n/d | — | — | — | — | — |
| Vector | vectordotdev/vector | observabilité | non | 6.1 | 2026-11-02 | 10 | 0 | 9 | 0 |
| Fluent Bit | fluent/fluent-bit | observabilité | non | 5.4 | 2026-10-31 | 10 | 0 | 2 | 0 |
| zizmor | zizmorcore/zizmor | posture-ci | non | n/d | — | — | — | — | — |
| poutine | boostsecurityio/poutine | posture-ci | non | 7.3 | 2026-10-27 | 5 | 8 | 10 | 0 |
| tekton-lint | IBM/tekton-lint | posture-ci | oui | 5.8 | 2026-10-26 | 10 | -1 | 2 | ? |
| Forgejo | hors GitHub | sources | oui | n/a | — | — | — | — | — |
| sbuild | hors GitHub | packaging | oui | n/a | — | — | — | — | — |
| mmdebstrap | hors GitHub | packaging | oui | n/a | — | — | — | — | — |
| StageX | hors GitHub | construction | non | n/a | — | — | — | — | — |

## 3. Verdicts

| Verdict | Projets |
|---|---|
| **Sain** | Tekton Pipelines, Kyverno (≥ 1.19.2), OpenBao, cosign, timestamp-authority, Argo CD (≥ 3.5.4), OBS, Buildah, Kata, gVisor, Renovate, Zot*, Harbor, ORAS, Pulp, Verdaccio, Rook, Syft, OSV-Scanner, osv.dev, GuardDog, Scorecard, ORT (sans SECURITY.md), ScanCode.io, SW360, Forgejo, Guix, Prometheus, Loki |
| **Sain, mais un seul éditeur** | Chainloop, DejaCode, Grafana (Grafana Labs, AGPL) ; **ajoutés le 02/11/2026** (brique 19, O5, [`o5-sante.log`](../poc/bricks/19-observabilite/resultats/o5-sante.log)) : Loki (Grafana Labs, AGPL ; `SHA256SUMS` sans signature ni attestation, images non signées) et Grafana Alloy (Apache-2.0 ; attestation de release GitHub sur les archives ; Scorecard n/d, à relever par le CLI) ; Vector (Datadog) relevé, non jugé |
| **À surveiller, chemin critique** | **Chains, Triggers, Conforma, Conforma policy (bibliothèque de règles : v1.0.28 du 26/08/2026, aucune release depuis, commits continus ; tags non signés, commit de fusion signé par GitHub ; 12 auteurs depuis le 01/08/2026 ; sur les 100 derniers commits, 54 avec une adresse redhat.com, 45 avec une adresse noreply de GitHub, employeur non vérifiable, et 1 autre ; relevé du 30/10/2026, brique 08), Hermeto, mock, BuildKit, Grype, sbuild, mmdebstrap, tekton-lint, k3s** (Scorecard 8, releases mensuelles, v1.37.1+k3s1 du 30/09/2026 ; signatures des releases et diversité des employeurs non vérifiées) ; **Cilium** et **kube-router amont**, candidats de l'option 1 du contrôle de sortie de la brique 08 (Cilium **retenu pour le PoC** par le propriétaire le 30/10/2026 après sa mesure, kube-router amont non retenu ; verdict inchangé, faute de nouvelle mesure de santé ; relevé du 30/10/2026, [`sante-reseau-releves.log`](../poc/bricks/08-trust-plane/resultats/sante-reseau-releves.log) ; signatures au §5) : **Cilium** : v1.20.4 du 23/10/2026 ; 1 685 commits en 90 jours ; auteurs d'Isovalent (Cisco, dominant), de Datadog et d'autres (adresses des commits) ; 16 fusionneurs sur les 100 dernières PR ; DCO, sans CLA ; SECURITY.md et 44 avis publiés, dont 11 en un an, avec leurs versions corrigées ; images signées. Manquent : **aucune provenance trouvée** pour les images, et un Scorecard de 6,0, exactement au seuil ; **kube-router amont** : v2.11.2 du 22/10/2026 ; 105 commits en 90 jours ; **deux fusionneurs font 96 des 100 dernières fusions** (bus factor de 2) ; employeurs non vérifiables, hormis Mirantis ; SECURITY.md et 3 avis en 2026, avec leurs versions corrigées ; image et SBOM signés ; provenance SLSA v1 des binaires vérifiée, mais **aucune provenance pour l'image**, celle qu'on déploierait ; Scorecard 7,5. k3s embarque un fork en v2.6.3 |
| **À surveiller (Scorecard < 6)** | **cilium/proxy (4,4 ; ajouté le 03/11/2026, brique 03, F2)** : Envoy embarqué dans l'image de l'agent Cilium (`cilium-envoy` v1.39.5 en 1.20.4, épinglé par digest dans le Dockerfile de Cilium et couvert par la signature de l'image de l'agent, vérifiée par `cilium.sh`) ; aucune release ni tag propre, aucun SECURITY.md (politique de sécurité de cilium/cilium) ; 100 commits en 90 jours, dont 36 de Renovate et 59 de deux mainteneurs ; Envoy amont : Scorecard 8,5 ; **démarré dès que `l7Proxy` est vrai, même sans politique HTTP** (mesuré, brique 03, F2) ; **non retenu** (décision du propriétaire du 03/11/2026 : sortie 443 hors privé à la place de `toFQDNs`, `l7Proxy` reste faux), Fluent Bit (5,4 ; ajouté le 02/11/2026), REUSE (4,0), Athens (5,8), mock (4,9), Ceph (4,6), aptly (3,4), tekton-lint (5,8), VictoriaMetrics (5,4), k3d (3,6 ; Maintained 2, une release en 16 mois : **non retenu**, kind et k3s couvrent ses usages) |
| **À surveiller, hors chemin critique** | Helm (ajouté le 01/11/2026, brique 08 : installe Cilium depuis l'hôte, option (b) du propriétaire, à la place du contrôleur Helm de k3s ; hors chemin critique : outil d'installation lancé depuis l'hôte, absent du chemin d'exécution des builds et du cluster, sortie possible par `helm template` puis `kubectl apply` ; [`helm-releve.log`](../poc/bricks/08-trust-plane/resultats/helm-releve.log) : v4.3.1 du 15/10/2026, releases mensuelles, branche 3 en fin de vie ; Scorecard 9,1 ; au moins 100 commits en 90 jours, 10 mainteneurs ; SECURITY.md, 24 avis publiés dont 3 depuis un an, corrigés en 4.1.4 ; tarball signé par GPG, vérifié avec la clé du fichier KEYS au tag. Manquent : **aucune provenance** dans la release, et diversité des employeurs non vérifiée, la majorité des adresses étant noreply ou personnelles), kind (v0.33.0 du 26/08/2026, sert au seul banc A1 ; signatures des releases non vérifiées), Konflux, rpm-lockfile-prototype, ko, nfpm, Witness, gittuf, AMPEL, vunnel, grype-db, Dependency-Track v5 (un seul mainteneur fusionne), Trustify, GUAC, vexctl, sbomqs, sbomasm, malicious-packages, Trivy, cdxgen, cyclonedx-cli, protobom, Macaron, sbomnix, createrepo_c, devpi, SeaweedFS, nixpkgs vmTools, StageX, debusine, diffoscope, reprotest, strip-nondeterminism, add-determinism, rebuilderd, OSS Rebuild, repro-env, debuerreotype, ScanCode toolkit, FOSSology, Grant, ORT Server, Plumber CLI, octoscan, frizbee |
| **À surveiller, ajoutés le 05/11/2026 (brique 08b, [relevés](../poc/bricks/08b-rke2/resultats/sante-releves.log), [signatures](../poc/bricks/08b-rke2/resultats/sante-signatures.log))** | **RKE2, chemin critique** : Scorecard 5,9 (sous le seuil) ; v1.37.1+rke2r1 et v1.35.9+rke2r1 du 30/09/2026 ; 254 commits en 90 jours ; 7 fusionneurs sur les 100 dernières PR, auteurs à adresses suse.com et rancher.com, donc un seul éditeur (SUSE) ; pas de SECURITY.md dans le dépôt ; 3 avis publiés, aucun depuis un an ; sha256 seulement dans les releases, aucune signature trouvée sur `rke2-runtime`. **Retenu pour le PoC** par le propriétaire le 05/11/2026 à la place de k3s. **local-path-provisioner**, fourni par k3s, absent de RKE2 : Scorecard 5,5 ; v0.0.37 du 05/08/2026 ; **93 des 100 dernières fusions par une seule personne** (bus factor 1, adresse suse.com vue sur le dépôt, employeur de ce fusionneur non vérifié) ; pas de SECURITY.md ; 2 avis en 2026, dont un critique (traversée de chemin) et un élevé (injection dans le gabarit du pod auxiliaire) ; image sans signature trouvée ; pas « Risqué » tant qu'un éditeur le soutient, à revérifier. **cert-manager**, hors chemin critique : Scorecard 8,4 ; v1.21.3 du 23/10/2026 ; 439 commits en 90 jours ; adresses de plusieurs organisations, dont paloaltonetworks.com, cyberark.com et redhat.com ; SECURITY.md et 3 avis ; images signées, vérifiées par cosign avec la clé du projet ; **aucune provenance trouvée**, seul critère manquant ; **retenu par le propriétaire le 05/11/2026 pour un jalon distinct** (D6 a de la 08b), pas encore installé. **kube-bench**, hors chemin critique, lancé ponctuellement ([relevé](../poc/bricks/08b-rke2/resultats/sante-kubebench.log)) : Scorecard 5,2 du 16/03/2026 ; v0.16.0 du 05/08/2026 ; 82 des 100 dernières fusions par une seule personne ; pas de SECURITY.md ; sommes sans signature ; aucun profil RKE2 pour Kubernetes 1.35 ; même éditeur que Trivy (Aqua). Retenu pour une mesure indicative (D5 a) |
| **À surveiller, chemin critique, ajoutés le 05/11/2026 (briques 05 et 06, [relevés](../poc/bricks/05-rpm-mock/resultats/sante-releves.log), [signatures](../poc/bricks/05-rpm-mock/resultats/sante-signatures.log), [podman](../poc/bricks/05-rpm-mock/resultats/sante-podman.log))** | **podman** : v6.1.4 (12/10/2026), 831 commits sur 90 jours, Scorecard 7,8, SECURITY.md, 5 avis en un an dont un critique (GHSA-2cvf-wqm6-wr9g, `podman run`, corrigé en amont en v5.8.8 et v6.1.3). Fusions surtout par Red Hat et par un compte dont l'employeur n'est pas établi ; le critère des 2 employeurs n'est donc pas prouvé. Le PoC emploierait le rpm signé de Rocky, pas la release amont. **skopeo** : v1.24.1 (16/09/2026), 129 commits, Scorecard 8,6, 0 avis ; 75 fusions sur 100 par un seul compte, Red Hat. **Images Rocky** : source déclarée `sig_core/rocky-kiwi-descriptions` sur git.resf.org (branche r9 : dernier commit 30/10/2026, 8 auteurs sur 50 commits), security.txt signé, errata publiés, dépôts signés et vérifiés ; **images sans signature ni attestation**, employeurs non établis. Pas de Scorecard utile : le dépôt GitHub ne porte pas la source. **debuerreotype et images Debian** : image trixie reconstruite le 04/11/2026, manifeste identique à l'OCI publié dans Git ; 2 mainteneurs déclarés, développeurs Debian, employeurs non établis ; 100 fusions sur 100 par un seul compte sur debuerreotype, 2 commits sur 90 jours, aucun SECURITY.md ; **image sans signature**, attestation SPDX non signée, sans provenance. **Verdict limite** : la règle « Risqué » vise un mainteneur unique sans soutien ; le second mainteneur est déclaré, mais son activité n'a pas été mesurée. **Échéance : dernière release 0.17 du 08/12/2025, ce projet passe en « Risqué » le 09/12/2026 sans nouvelle release** ; à relever avant tout usage après cette date. |
| **À surveiller, hors chemin critique, non retenus, ajoutés le 08/11/2026 (brique 08, [relevés](../poc/bricks/08-trust-plane/resultats/sante-sigstore-releves.log), [compléments](../poc/bricks/08-trust-plane/resultats/sante-sigstore-complements.log))** | **Rekor v1** (sigstore/rekor) : Scorecard 8,6 ; v1.5.5 du 21/10/2026 ; **« in maintenance mode »** (README) ; 28 commits humains sur 121 en 90 jours ; fusions par trois comptes (65, 29, 6 sur 100), employeurs non établis ; politique de sécurité de l'organisation sigstore ; 3 avis en un an ; fichiers `.sigstore.json` dans la release, non vérifiés. **Trillian** (google/trillian, dépendance du serveur Rekor v1) : Scorecard 8,4 ; v1.8.0 du 21/09/2026 ; **« in maintenance mode »**, Tessera recommandé ; 4 commits humains sur 15 en 90 jours. **Rekor v2** (sigstore/rekor-tiles) : Scorecard 8 ; v2.4.1 du 30/10/2026 ; 32 commits humains sur 128 ; release sans signature (Signed-Releases 0) ; hors sujet tant que Chains ne parle que la v1. **Fulcio** : Scorecard 8,4 ; v1.9.1 du 21/10/2026 ; 17 commits humains sur 68 ; fusions par trois comptes ; 4 avis en un an (OIDC, méta-émetteurs) ; sans objet sans OIDC. Images non relues. |
| **Risqué → interdit** | Promtail (fin de vie le 02/03/2026, doc de Loki ; ajouté le 02/11/2026), kkRepo, Archivista, RSTUF, Sysbox, bombon, Hyades (archivé), go-licenses, askalono (archivé), ClearlyDefined (en offline), Legitify, kaniko (archivé), repro-get (archivé), Earthly, MinIO (archivé), Tern |

\* Zot : **image v2.1.22 non signée** sur ghcr.io (voir §5). On la reconstruit, ou on l'épingle par digest après revue.

## 4. Projets hors GitHub (vérifiés sur Codeberg, salsa et tracker.debian.org)

| Projet | Constat | Verdict |
|---|---|---|
| **Forgejo** | GPL-3.0+, Codeberg e.V. Une release stable par trimestre ; v17.0.1, v16.0.7 et v15.0.11 publiées le 26/10/2026. **LTS v15 (16/04/2026) jusqu'au 15/07/2027**, LTS suivante v19 (04/2027). 163 auteurs sur 90 jours. Signalement à security@forgejo.org, traitement « best effort ». « Forgejo does not participate in … the CVE Program » | Sain. S'abonner au flux `security-announcements` ; **planifier la migration vers la v19 avant 07/2027** |
| **StageX** | ISC, 8 mainteneurs listés dans MAINTAINERS, RFC et vote signé (72 h pour les sujets de sécurité). Règle : « Two or more release engineers MUST contribute their signatures », clés PGP sur carte à puce, reproduction sur 2 marques de CPU. sx2026.09.0 (30/09/2026) n'a que **2 signataires** (le minimum). Un contributeur fait environ 63 % des commits. **Pas de politique de sécurité formalisée** ; SBOM non supporté (issue #248 ouverte depuis 09/2024) ; provenance NV ; **pas d'arm64**. Vérification via signatures *lookaside* (`sigs.stagex.tools`) : **Podman OK, Skopeo KO, Kubernetes inconnu** | À surveiller. Vérifier soi-même ≥ 2 signatures distinctes (Podman, `policy.json`) **dans l'étape de build**, pas à l'admission ; reproduire en interne |
| **GNU Guix** | v1.5.0 (01/2026), puis distribution continue, **sans branche stable**. 94 auteurs en 17 jours. Processus sécurité formalisé (guix-security@gnu.org, embargo de 3 mois maximum, avis publiés), releases signées par 3 clés | Sain (en veille) |
| **sbuild** | 0.91.10 (06/2026). **Aucun commit sur la branche principale depuis 4 mois**, 18 MR ouvertes, un contributeur fait 72 % des commits. Criticité très haute (buildd Debian) | À surveiller. Paquet Debian épinglé |
| **mmdebstrap** | Amont (instance Forgejo gitlab.mister-muffin.de) : tag 1.6.0 (03/10/2026), **70 commits sur 90 jours**, 9 auteurs sur la période mais très majoritairement un seul (J. Schauer Marin Rodrigues) ; 30 auteurs sur tout l'historique | À surveiller (actif, mais mainteneur quasi unique). Paquet Debian épinglé |
| **debusine** | 0.16.2 (28/10/2026), 0.x, une seule entreprise (Freexian), pas de politique de sécurité | À surveiller (option) |
| **diffoscope / reprotest / strip-nondeterminism** | Projet Reproducible Builds, **membre de la Software Freedom Conservancy** (501(c)3), financé par dons et sponsors. diffoscope 335 (23/10/2026, 40 commits sur 90 jours) ; reprotest 0.7.33 (7 commits) ; strip-nondeterminism 1.15.1 (**0 commit**). Un mainteneur dominant par outil | À surveiller (vérificateurs secondaires) |

## 5. Signatures des images amont (vérifiées le 28/10/2026)

Outil : `cosign v3.1.4` (checksum vérifié), avec la racine de confiance Sigstore (TUF) et Rekor accessibles.

| Image | Méthode de signature constatée | Résultat | Conséquence |
|---|---|---|---|
| **Renovate** 44.192.2 (`ghcr.io/renovatebot/renovate`) | Sans clé (GitHub OIDC), bundle en OCI referrer, journal de transparence | **Vérifiée** : identité `https://github.com/renovatebot/…`, émetteur `token.actions.githubusercontent.com`, présence dans le journal vérifiée | Exiger cette identité dans Kyverno et Conforma |
| **OpenBao** 2.7.2 (`ghcr.io/openbao/openbao`) | Sans clé (GitHub OIDC) | **Vérifiée** : identité `https://github.com/openbao/openbao/…` | Idem |
| **Kyverno** v1.19.2 (`ghcr.io/kyverno/kyverno`) | Sans clé (GitHub OIDC), signatures stockées **dans un dépôt séparé** `ghcr.io/kyverno/signatures` | **Vérifiée** avec `COSIGN_REPOSITORY=ghcr.io/kyverno/signatures` | Utiliser ce dépôt pour la vérification et le mirroring (`oras cp -r` ne suffit pas) |
| **Tekton Pipelines** v1.17.1 (`ghcr.io/tektoncd/pipeline/controller-…@sha256:086cdd16…`) | Signature **par clé** (`.sig`, `.att`, `.sbom` en tags), **sans entrée Rekor, sans certificat, sans horodatage** | **Non vérifiable** : la clé publique documentée (`tektoncd/chains/tekton.pub`, citée dans `tektoncd/plumbing/docs/signing.md`) **ne correspond pas** à la signature, et l'attestation est refusée pour la même raison. La v1.6.0 n'a aucune signature | **Reconstruire les images Tekton** nous-mêmes (ko, depuis le tag source) ou les **épingler par digest après revue**. Signaler l'écart de documentation à Tekton |
| **Conforma** (`quay.io/conforma/cli:latest`, construit par Konflux ; une release à chaque merge, tags `gh-<sha>` et `snapshot`) | Signature, attestation et SBOM présents (tags `.sig`, `.att`, `.sbom`) | **Non vérifiable avec la doc publique** : conforma.dev ne publie **ni clé publique ni identité keyless** pour ses propres images (l'étape « Verify Images » du processus de release n'est qu'un test fonctionnel) | **Reconstruire le CLI Conforma** depuis un tag stable, ou épingler par digest après revue. Demander au projet de publier sa méthode de vérification |
| **Zot** v2.1.22 (`ghcr.io/project-zot/zot*`) | **Aucune signature** (ni cosign ni Notation) sur les images ; la release ne fournit qu'un `checksums.sha256.txt` **non signé** | **Non signée** | **Reconstruire Zot** depuis le tag source (Go), ou épingler par digest après revue |
| **Tekton Chains** v0.29.9 (`ghcr.io/tektoncd/chains/…/cmd/controller@sha256:486b562d…`) | Signature **par clé** (`.sig`, `.att` en tags), **sans Rekor, sans certificat, sans horodatage** ; `release.yaml` (infra.tekton.dev → Oracle Object Storage) **non signé** (pas de `.sig`, `.pem`, `.bundle` ni `.sha256`) | **Non vérifiable**, même cause que Pipelines : la clé documentée `tekton.pub` ne correspond pas | **Reconstruire** (ko, depuis le tag source) ou épingler par digest après revue |
| **Cilium** v1.20.4 (`quay.io/cilium/cilium`, `quay.io/cilium/operator-generic`), vérifiée le 30/10/2026 ([`sante-reseau-signatures.log`](../poc/bricks/08-trust-plane/resultats/sante-reseau-signatures.log)) | Sans clé (GitHub OIDC), signature et SBOM SPDX en référents OCI | **Vérifiée** : identité exacte `https://github.com/cilium/cilium/.github/workflows/build-images-releases.yaml@refs/tags/v1.20.4` (documentée), émetteur `token.actions.githubusercontent.com` ; témoin : identité du tag v1.20.3 refusée. **Aucune provenance** : ni attestation SLSA par cosign, ni attestation GitHub, ni manifeste d'attestation dans l'index | Signature vérifiable ; provenance à obtenir (reconstruction, ou demande amont avec l'accord du propriétaire) |
| **kube-router** v2.11.2 (`docker.io/cloudnativelabs/kube-router`), vérifiée le 30/10/2026 ([même journal](../poc/bricks/08-trust-plane/resultats/sante-reseau-signatures.log)) | Sans clé (GitHub OIDC), signature et SBOM SPDX en référents OCI ; binaires de la release attestés par GitHub | **Image vérifiée** : identité `https://github.com/cloudnativelabs/kube-router/.github/workflows/ci-container.yml@refs/tags/v2.11.2`, relevée dans un refus volontaire. L'identité n'est pas documentée : elle est lue dans le workflow au tag. Pas de provenance sur l'image. **Binaire `linux_amd64` vérifié** : sha256 conforme à `checksums.txt`, provenance SLSA v1 vérifiée par `gh attestation verify` (workflow signataire `ci-release.yml@refs/tags/v2.11.2` ; témoin : `ci.yml` refusé) | Signature et provenance des binaires vérifiables ; provenance de l'image absente |
| **RKE2** v1.35.9+rke2r1 (`docker.io/rancher/rke2-runtime`), vérifiée le 05/11/2026 ([journal](../poc/bricks/08b-rke2/resultats/sante-signatures.log)) | Aucune trouvée par `cosign tree` ; release avec `sha256sum-amd64.txt` seul | **Non signée d'après cette recherche** (image rke2-runtime seule, méthode Rancher hors cosign non explorée) | sha256 vérifié dans chaque VM, comme k3s ; digests épinglés |
| **local-path-provisioner** v0.0.37 (`docker.io/rancher/local-path-provisioner`), vérifiée le 05/11/2026 ([même journal](../poc/bricks/08b-rke2/resultats/sante-signatures.log)) | Aucune trouvée par `cosign tree` | **Non signée d'après cette recherche** | Épingler par digest après revue |
| **cert-manager** v1.21.3 (`quay.io/jetstack/cert-manager-*`), vérifiée le 05/11/2026 ([même journal](../poc/bricks/08b-rke2/resultats/sante-signatures.log)) | Par clé, publiée par le projet (`cert-manager-pubkey-2021-09-20.pem`), sans journal de transparence | **Vérifiée** pour le contrôleur, le webhook et le cainjector ; témoin : autre image refusée. Aucune provenance trouvée | Signature vérifiable ; provenance à obtenir |
| **Rocky** `quay.io/rockylinux/rockylinux:9.7` (`sha256:53f4c6dc…`, créée le 23/11/2025) et `:9.8` (`sha256:81019941…`, créée le 25/05/2026), vérifiées le 05/11/2026 ([journal](../poc/bricks/05-rpm-mock/resultats/sante-signatures.log)) | Aucune trouvée par `cosign tree` ; aucun manifeste d'attestation | **Non signées d'après cette recherche** ; les dépôts le sont : `repomd.xml` de BaseOS, AppStream et CRB 9.7 vérifiés avec la clé `21CB 256A…275D`, empreinte identique sur rockylinux.org, témoin altéré refusé | Épingler par digest après revue ; `rpm -Va` et signatures des rpm contrôlés dans l'image avant usage |
| **Debian** `docker.io/library/debian:trixie-20261104-slim` (`sha256:a72b4433…`), vérifiée le 05/11/2026 ([même journal](../poc/bricks/05-rpm-mock/resultats/sante-signatures.log)) | Aucune signature trouvée par `cosign tree` ; 8 manifestes d'attestation, SPDX seul pour amd64, sans signature | **Non signée** ; manifeste amd64 identique à `trixie/slim/oci/index.json` de `docker-debian-artifacts`, ce qui relie l'image au dépôt sans prouver son contenu | Épingler par digest après revue, ou construire la base par mmdebstrap depuis l'archive Debian signée (D4 de la brique 06) |
**Action (brique 11, `builder-bootstrap`)** : reconstruire depuis les tags sources les images **Tekton Pipelines, Chains et Triggers** (ko), **Conforma** et **Zot**, puis les signer avec notre clé et inscrire leur provenance ; à défaut, les épingler par digest après revue documentée.

**Enseignement.** Un score « Sain » ne garantit pas des artefacts vérifiables. Tekton (Scorecard 6,7, très actif) publie des images dont la signature ne se vérifie pas avec la clé documentée, Conforma ne documente pas comment vérifier ses images, et Zot (8,1) ne signe pas les siennes. Les trois sont sur le chemin critique. La règle reste donc : **on reconstruit les images d'outils du chemin critique, ou on les épingle par digest après revue**. Ce n'est pas une option.

## 6. Plans de sortie (chemin critique)

| Projet | Risque | Contre-contrôle ou sortie |
|---|---|---|
| Tekton Chains | 0.x, **aucun substitut L3**. En mode `sigstore-bundle`, la v0.29.x écrit des **signatures d'image invalides** (correctif [chains#2096](https://github.com/tektoncd/chains/pull/2096) non publié au 28/10/2026) | **Mode `dsse`** (tags) jusqu'au correctif ; contrôle strict `cosign/sign/v1`. **Coût du mode `dsse` mesuré en brique 08 (29/10/2026)** : deux envois d'attestations simultanés vers un même digest en perdent un sans erreur (lecture puis réécriture du tag `.att`, sans verrou ; [constat](../poc/bricks/08-trust-plane/resultats/constat-att-ecrasee.log)). Le choix se pose donc entre signatures d'image invalides (`sigstore-bundle`) et attestations perdues sous concurrence (`dsse`) ; contre-contrôle : une enveloppe par exécution signée. Sortie : OpenShift Pipelines ou Konflux (embarquent Chains). VSA de replay signée par une autre clé **Additif du 08/11/2026** : Chains v0.29.9 et main ne parlent que **Rekor v1, « in maintenance mode »** (client `sigstore/rekor` v1.5.4, [journal](../poc/bricks/08-trust-plane/resultats/sante-sigstore-fulcio.log)) ; sans effet aujourd'hui (transparence désactivée dans notre configuration), mais aucun journal de transparence possible avec Chains avant son passage à Rekor v2 : à suivre au ré-audit |
| Conforma | 0.x, sponsor unique | Mini-politique dupliquée en Kyverno-JSON ou OPA ; **challenger 2a : Kyverno moteur unique** |
| Hermeto | 3 avis Critical en 08/2026 | Dernière version, prefetch isolé sans secrets ; sortie : vendoring natif scripté |
| mock | Scorecard 4,9 | OBS (benchmark 2a) |
| BuildKit | 0.x, concentration sur 2 développeurs | Buildah (et inversement) ; **challenger 2a : Nix** |
| Grype | Unique scanner sur EL | Base archivée datée ; OSV-Scanner sur le SBOM (à valider) |
| sbuild / mmdebstrap | Bus factor faible | Paquets Debian épinglés (contrôle des uploads) ; debusine en option |
| Dependency-Track | Un seul mainteneur | Projection reconstructible depuis les SBOM et VEX (ré-ingest testé) |
| k3s | Éditeur dominant (SUSE) ; signatures des releases à vérifier avant installation | Manifestes en Kubernetes standard, sans dépendance propre à k3s : toute distribution conforme (kubeadm, RKE2) convient |
| RKE2 (retenu pour le PoC le 05/11/2026, brique 08b) | Éditeur unique (SUSE) ; Scorecard sous le seuil ; images sans signature trouvée ; contrôleur Helm impossible à désactiver | Manifestes en Kubernetes standard : k3s, déjà mesuré dans le PoC, ou kubeadm. Composants installés depuis l'hôte, sans HelmChart (D1 de la 08b) |
| local-path-provisioner (si retenu, D2 de la 08b) | Bus factor 1 ; 2 avis en 2026 | Volumes `local` statiques, ou autre pilote de stockage ; à chiffrer |
| Cilium (retenu pour le PoC le 30/10/2026, option 1b de la brique 08) | Éditeur dominant (Isovalent, Cisco) ; Scorecard au seuil ; aucune provenance pour les images ; agent eBPF privilégié sur chaque nœud | Les NetworkPolicy Kubernetes standard restent portables vers tout autre contrôleur. Les fonctions propres à Cilium (`toFQDNs`, Hubble, vérification de l'adresse source) se perdent : Calico pour l'anti-usurpation (refus par défaut à vérifier) ; trace du test 6 à redéfinir |
| cilium/proxy (Envoy embarqué, si `l7Proxy` est activé pour `toFQDNs`) | Scorecard 4,4 ; deux mainteneurs d'un même éditeur ; aucune release propre | `l7Proxy: false` (Envoy arrêté, mesuré le 03/11/2026) ; sortie par plages d'adresses (ipBlock, port 443) à la place de `toFQDNs`, et proxy Go imposé par la configuration de Hermeto |
| kube-router amont (non retenu, option 1 de la brique 08) | Bus factor de 2 (deux fusionneurs) ; employeurs non vérifiables ; aucune provenance pour l'image | Contrôleur intégré de k3s (même sémantique, mais sans `--netpol-default-deny`) ; Cilium ou Calico |
| podman et skopeo (si retenus, brique 05) | Éditeur dominant (Red Hat) ; le correctif dépend du rythme de Rocky ; sur 5 CVE podman cherchés, seuls CVE-2026-57231 et CVE-2026-19730 apparaissent, en 9.8 ; l'absence d'une mention ne prouve rien ; 9.7 et 9.8 sont toutes deux dans la plage amont de l'avis critique | Rpm signés de Rocky, images par digest ; mock n'emploie que `pull`, `image inspect`, `image mount`, `tag`, `rmi` et `skopeo sync`, jamais `podman run`. Sortie : OBS, comme pour mock |
| Images de base Rocky et Debian (si retenues, briques 05 et 06) | Non signées ; debuerreotype concentré sur un mainteneur | Bases reconstruites depuis les dépôts signés (dnf `--installroot`, mmdebstrap), à mesurer |

**Versions minimales imposées** :
- Chains ≥ 0.29.0 (`sigstore-bundle`) ;
- Conforma ≥ 0.10 ;
- Kyverno ≥ 1.19.2 ;
- Argo CD ≥ 3.5.4 ;
- Witness ≥ 0.12 ;
- Trivy ≥ 0.76.1 ;
- Hermeto en dernière version.

## 7. Procédure de ré-audit (trimestrielle)

1. Mettre à jour `tools/health/projects.tsv` (ajouts et retraits de briques).
2. Lancer `tools/health/scorecard.sh > /tmp/scorecard.md` et remplacer le §2.
3. Pour les « n/d » : lancer le CLI `scorecard --repo=github.com/<owner>/<repo>` avec `GITHUB_AUTH_TOKEN`.
4. Vérifier les projets hors GitHub (§4) : releases, commits sur 90 jours, mainteneurs, avis de sécurité.
5. Vérifier les signatures des images utilisées (`cosign verify`, `cosign tree`) et mettre à jour le §5.
6. Réviser les verdicts. Tout passage en « Risqué » déclenche la mise en œuvre du plan de sortie.
