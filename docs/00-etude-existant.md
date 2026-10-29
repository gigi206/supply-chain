# Étude de l'existant : plateforme supply-chain SLSA Build L3

> État au **28/10/2026**. Ce document détaille les alternatives étudiées, avec leurs pour et contre et leurs sources.
> Les décisions et le planning sont dans le [README](../README.md) ; l'audit de santé des projets est dans [`04-sante-projets.md`](04-sante-projets.md).
> Légende : **NV** = non vérifié à la source ; « Santé » renvoie aux verdicts du doc 04 (Sain / À surveiller / Risqué).

## 0. Réponse courte

**Aucun projet open source ne couvre l'ensemble du besoin.** Le besoin couvre :
- le rebuild bit à bit ;
- l'archivage des artefacts et de toutes les dépendances ;
- le SBOM et la provenance ;
- le replay offline ;
- un score de fiabilité ;
- l'analyse de licences ;
- les miroirs git avec branches custom ;
- les rpm/deb multi-distro ;
- SLSA Build L3.

- **Konflux** (Red Hat) est le plus proche, mais il lui manque les deb, une intégration Forgejo solide, Dependency-Track, l'analyse de licences complète, les snapshots de distros et la vérification de rebuild indépendante.
- **OBS** (SUSE) couvre très bien les rpm/deb multi-distro, mais pas le reste.
- **Tekton Chains** est aujourd'hui **le seul** composant open source auto-hébergeable qui génère et signe la provenance **hors de portée des étapes de build**, ce qui est l'exigence clé de L3.

La plateforme s'assemble donc autour de Tekton + Chains, avec des briques complémentaires. Konflux et OBS sont benchmarkés avant de trancher (ADR 0000), ainsi que deux challengers : Nix comme moteur de build et Kyverno comme moteur de politique unique.

## 1. Méthode

1. **Recherche par domaine.** Elle s'est faite en plusieurs vagues avec des agents de recherche, sur les sources primaires (README, releases, docs officielles), avec vérification de l'état en 2026.
2. **Relectures par un « advisor ».** Un architecte indépendant, en posture adversariale, a fait trois relectures. Chacune a donné des amendements, tous intégrés (B1 à B6, I1 à I9, V1 à V19, plus 5 amendements finaux).
3. **Vérification des faits techniques à la source** : docs Tekton Chains, texte SLSA v1.2, docs Hermeto, code Conforma et Kyverno.
4. **Audit de santé** d'environ 80 projets : releases, activité, contributeurs, sécurité, OpenSSF Scorecard. Voir le doc 04.
5. **Limites.** Plusieurs hôtes ont été bloqués par la politique réseau de la session, puis ouverts à la demande. Il reste non vérifiés :
   - la vérification cryptographique complète des signatures d'images (Sigstore TUF/Rekor, blobs GHCR, quay.io) ;
   - quelques pages qui renvoient 403 : docs.stagex.tools, reproducible-builds.org, gitlab.mister-muffin.de.

## 2. Plateformes « tout-en-un »

| Projet | État 2026 | Pour | Contre | Verdict |
|---|---|---|---|---|
| **Konflux** (konflux-ci) | Apache-2.0, v0.2.2 (09/2026), RC chaque semaine. Opérateur ; Kind, OpenShift ou k8s conforme | Tekton, Chains, Buildah, Hermeto, Sigstore, Conforma, Trustify, Zot/Quay, Kueue. Vise SLSA Build L3. Builds RPM (pipeline mock) **en adoption** chez CentOS Stream (RPM réimportés dans Koji) | 0.x, lourd (exemple Kind : 12 Gi). **Pas de deb.** Forgejo partiel : Pipelines-as-Code en tech preview sans vérification de signature des webhooks, bug de scope de token dans build-service, UI à faire. Cadre multi-tenant imposé | **Éliminé** (banc A1 du 29/10/2026, critère 1 : 17 contre 57) |
| **Open Build Service** (SUSE) | GPL-2.0, actif. Tag 2.10.34 (08/2026) | rpm **et** deb natifs pour toutes les distros visées, workers KVM, signature serveur (signd), dépôts téléchargés à la demande. SUSE revendique SLSA L4 (v0.1) pour SLE 15 SP4 et **Build L3 (v1.0)** pour les images BCI | SUSE **ne garantit pas la reproductibilité**. Rails + Perl, non natif k8s. Provenance SLSA v0.2 ou v1 (signée en DSSE) **seulement sur master** : aucune release 2.10.x n'en produit, et master n'a pas de release depuis la séparation de la branche 2.10 (06/2019) | **Banc A2 fait (29/10/2026) : non adopté** (42 contre 55) ; rpm et deb bit-identiques, provenance non falsifiable ([résultats](../poc/benchmarks/obs/resultats/README.md)) |
| FRSCA (OpenSSF) | Dormant, « not production ready » | Architecture de référence Tekton + Chains + SPIRE + Vault | Pas maintenu | Modèle de lecture |
| Chainguard melange/apko/Wolfi | Actif | Reproductible, SBOM natif | Paquets APK seulement | Hors sujet pour rpm/deb |
| Nix / Hydra | Actif ; forks Lix et Determinate | Meilleur modèle pour le bit à bit et l'offline (closures, dérivations à sortie fixe, `nix build --check`) | Provenance non signée nativement. CVE d'évasion du sandbox en 2025-2026. Hydra déconseillé pour les nouveaux déploiements. rpm/deb via `vmTools` seulement (voir §9) | **En veille** : banc B clos le 29/10/2026 (74 contre 91 pour Hermeto + BuildKit, voir §7) |
| GNU Guix | v1.5.0 (01/2026), Codeberg | Bootstrap complet depuis les sources (graine de 357 octets), `time-machine`, `challenge`, repli Software Heritage | `guix pack -f deb/rpm` embarque `/gnu/store` : ce ne sont pas des paquets natifs. npm faible. Coût d'adoption très élevé | Écarté (StageX couvre la racine de confiance) |
| Bazel (rules_oci, rules_pkg) | Actif | Hermétique | Il faudrait réécrire les builds ; inadapté aux projets tiers | Écarté |
| Dagger, BuildStream | Actifs | Pipelines en code, sandbox | Aucune provenance SLSA native | Écartés |
| Earthly | **Plus maintenu** (fork EarthBuild) | — | Pérennité | Exclu |

Sources : [konflux-ci](https://github.com/konflux-ci/konflux-ci), [Konflux, Conforma et SLSA](https://01f02e92.enterprise-contract.pages.dev/docs/user-guide/slsa), [builds hermétiques Konflux](https://pr-581--konflux-docs.netlify.app/building/hermetic-builds/), [CentOS Stream et Konflux](https://lists.centos.org/hyperkitty/list/devel@lists.centos.org/thread/4SDZPLIABACUPBYGIDU3S7PXOBF64G7R/), [SUSE et SLSA](https://documentation.suse.com/sbp/security/html/SBP-SLSA4/), [FRSCA](https://github.com/buildsec/frsca), [Earthly](https://github.com/earthly/earthly).

## 3. Orchestration et provenance (le cœur L3)

Exigence SLSA v1.2 Build L3 (citation vérifiée) :

> « Every field in the provenance MUST be generated or verified by the build platform in a trusted control plane. The user-controlled build steps MUST NOT be able to inject or alter the contents, except as noted in Provenance is Authentic. »

L'exception autorise le build à déclarer **les noms et digests des sujets** (artefacts produits).

| Option | Niveau SLSA réel | Pour | Contre | Verdict |
|---|---|---|---|---|
| **Tekton Pipelines + Chains + Triggers** | **L3** : le contrôleur Chains, séparé des tâches, signe via un KMS | Pipelines v1.17.1 (LTS 1.15/1.12). Chains v0.29.9 : formats `slsa/v2alpha4` (= SLSA v1.0), stockage OCI (`sigstore-bundle` = **OCI 1.1 Referrers**, depuis la v0.29.0 ; **mais signatures d'image invalides en v0.29.x**, correctif [chains#2096](https://github.com/tektoncd/chains/pull/2096) non publié au 28/10/2026, d'où le mode `dsse` en attendant), Archivista, KMS `hashivault://`. Incubation CNCF depuis le 24/03/2026. Adopté par Konflux et OpenShift Pipelines | Chains, Triggers et Trusted Resources en 0.x ou alpha. Chains signe ce que les tâches **déclarent** (d'où les tâches de confiance). **Pas de TSA native** (seulement Rekor). Pas d'intercepteur Forgejo. CVE-2026-33211 (git resolver) et CVE-2026-25542 (Trusted Resources) à corriger | **Retenu** |
| Argo Workflows | **L1** sans ajout ; **L2** avec Witness ; L3 seulement avec un contrôleur maison (2 à 4 personnes-mois) | CNCF Graduated, très bonne UI, vrais DAG | Aucune provenance native. Aucun équivalent de Trusted Resources. CVE de contournement de templates en 2026 (CVE-2026-31892, CVE-2026-42296). Pods en root par défaut | Écarté pour les builds |
| GitLab CI (self-managed) | **L2**. L3 en **« Experiment », GitLab.com, Ultimate** ; self-managed non supporté directement | Intégré à la forge | Pull mirror payant. L3 pas disponible en auto-hébergé | Écarté |
| GitHub Actions + slsa-github-generator / artifact attestations | L3, **hébergé** | Référence de l'écosystème | SaaS GitHub uniquement | Hors sujet |
| Forgejo Actions, Woodpecker, Jenkins | L2 au mieux | Simples | Aucune provenance native ; les secrets sont accessibles aux steps | Écartés |
| Buildkite | — | — | Plan de contrôle SaaS | Écarté |
| **Witness** (in-toto) + Archivista | **L2** : s'exécute dans le build, la clé ou l'identité est atteignable | 28 attesteurs (dont `commandrun` avec traçage expérimental), politique multi-étapes (`artifactsFrom`), TSA. v0.12.0 corrige un avis Critical | 0.x, activité faible. Archivista : **Risqué** (voir §5) | **Veille** (complément de trace, jamais source du L3) |
| Provenance BuildKit (`mode=max`) | L2 : non signée, contrôlée par le client | Gratuite | Docker ne revendique aucun niveau | Indice complémentaire |
| Argo CD | — (déploiement) | GitOps de la plateforme ; releases SLSA L3 | RCE dans le repo-server corrigée en ≥ 3.3.15 / 3.4.10 / 3.5.4 | Phase 4 |

**Conclusion.** Aucune autre option auto-hébergeable n'atteint L3. C'est pourquoi le cœur reprend les mêmes briques que Konflux : ce n'est pas du mimétisme, c'est le seul choix possible aujourd'hui.

Sources :
- Tekton : [config Chains](https://github.com/tektoncd/chains/blob/main/docs/config.md), [format d'encodage OCI](https://tekton.dev/docs/chains/oci-encoding-format/), [provenance SLSA de Chains](https://github.com/tektoncd/chains/blob/main/docs/slsa-provenance.md), [Tekton au CNCF](https://www.cncf.io/blog/2026/03/24/tekton-becomes-a-cncf-incubating-project/).
- SLSA : [exigences de build SLSA v1.2](https://slsa.dev/spec/v1.2/build-requirements).
- Argo : [releases Argo Workflows](https://github.com/argoproj/argo-workflows/releases), [ARGO-SLSA (L2)](https://arxiv.org/abs/2503.20079).
- GitLab : [GitLab L3 (Experiment)](https://docs.gitlab.com/ci/pipeline_security/slsa/level_3/), [ADR GitLab sur le self-managed](https://handbook.gitlab.com/handbook/engineering/architecture/design-documents/slsa_level_3/decisions/003_attest_sign_location).
- GitHub : [slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator).
- Witness : [witness](https://github.com/in-toto/witness), [attesteurs go-witness](https://github.com/in-toto/go-witness/tree/main/attestation).

## 4. Signature, horodatage, racine de confiance

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **cosign + OpenBao Transit** | La clé ne quitte jamais le KMS. cosign accepte `openbao://`, Chains accepte `hashivault://` (compatibilité avec OpenBao à valider). OpenBao : OpenSSF/LF, Scorecard 8,5 | Clé de longue durée : il faut une rotation et un horodatage. Descellement manuel après redémarrage | **Retenu** |
| **TSA RFC 3161** (sigstore timestamp-authority) | Vérification possible dans 10 ans, après rotation ou compromission de la clé. SLSA v1.2 recommande les services d'horodatage | Chains n'a **aucune clé TSA** : il faut un job séparé. Kyverno (`tsaCertChain`) ne vérifie que l'horodatage **intégré au bundle**, d'où le choix à faire en brique 08 : bundle réémis avec `timestampVerificationData`, ou `tools/verify-ts`. **Mesuré en brique 08 (J5)** : bundle réémis vérifié par cosign v3.1.4 ; le CLI de Kyverno 1.19.2 plante sur un jeton valide (clé, sans journal) | **Retenu** |
| Sigstore auto-hébergé sans clé (Fulcio, Rekor v2, CTlog, TUF) | Certificats de courte durée, journal de transparence | Exploitation lourde (OIDC, racine TUF). Rekor v2 (GA 10/2025) casse l'API v1 ; compatibilité avec Chains, Conforma et Kyverno non vérifiée | **Veille** |
| Notation (Notary Project) | PKI X.509 | Plugin Vault expérimental, orienté signatures plus qu'attestations | Écarté |
| **TUF statique** (python-tuf / go-tuf) ou trousseau signé avec gittuf | Distribuer et faire tourner les clés publiques sur 10 ans | À opérer | **Retenu** (ADR 0003) |
| RSTUF | Service TUF complet | Dépôt principal sans release depuis plus de 12 mois : **Risqué** | Écarté |
| **Signature OpenPGP** des rpm, deb et dépôts : service isolé + HSM (sigul, signd d'OBS, worker debusine…) | Obligatoire pour rpm et apt | Transit **ne fait pas d'OpenPGP**. `rpmsign`/`debsign` modifient l'artefact, d'où une **attestation de lien** entre la version non signée et la version signée | **Retenu** (brique 09) |

Sources : [gestion des clés cosign](https://docs.sigstore.dev/cosign/key_management/overview/), [Rekor v2 GA](https://blog.sigstore.dev/rekor-v2-ga/), [charts Helm Sigstore](https://github.com/sigstore/helm-charts), [timestamp-authority](https://github.com/sigstore/timestamp-authority), [RSTUF](https://github.com/repository-service-tuf/repository-service-tuf).

## 5. Politique, vérification, stockage des attestations

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **Conforma** (`ec`, ex-Enterprise Contract) | Bibliothèque de règles : collection `slsa3` (« policy rules required to meet SLSA Level 3 »), `trusted_task`, `signing_identities`. Builtin `ec.oci.image_referrers` (OCI Referrers) et lecture des bundles dans le code depuis la v0.8.122 environ (**non documentée** sur conforma.dev) | 0.x (release à chaque merge ; utiliser des tags figés). Sponsor : Red Hat de fait. **`--vsa` déprécié** (sans date de retrait). **Aucune méthode documentée pour vérifier ses propres images** | **Retenu** comme porte de release. **Challenger 2a** : Kyverno seul |
| **Kyverno** ≥ 1.19.2 | `ImageValidatingPolicy` (`policies.kyverno.io/v1`, annoncée GA en 1.17, doc « FEATURE STATE: Stable • Kyverno v1.19 » ; version de stockage v1beta1 jusqu'en 1.20) : cosign v3, referrers, in-toto, chaîne TSA (`ctlog.tsaCertChain`) pour l'horodatage **intégré au bundle**. Vérification d'un jeton RFC 3161 séparé : **non** (brique 08, J5, CLI : horodatage lu dans le bundle seulement, et plantage avec une clé sans journal). CNCF Incubating, Scorecard 7,8 | Avis Critical en 10/2026 (corrigés en 1.19.2). `ClusterPolicy verifyImages` ne fonctionne pas en mode bundle | **Retenu** (admission). Candidat moteur unique |
| OPA Gatekeeper + Ratify | Générique | Plus complexe ; provider cosign « not for production » | Écarté |
| sigstore policy-controller | Alternative à Kyverno | CVE de contournement en 2026 (NV) | Écarté |
| slsa-verifier | Référence | Ne gère que les builders GitHub et GCB | Hors sujet |
| AMPEL (policylabs) | CEL, émet des VSA | Bus factor 1 | Veille |
| **VSA émise par nous** (`https://slsa.dev/verification_summary/v1`, signée par une clé dédiée) | Standard SLSA, indépendant de Conforma | Petit outillage maison | **Retenu** |
| Archivista | Index GraphQL des attestations | **Risqué** : release de plus de 12 mois, un seul humain actif, pas d'authentification | **Écarté**, remplacé par les referrers OCI et `tools/index` |
| Chainloop | Stockage de preuves, contrats, politiques, intégrations DT et GUAC. Très actif (Scorecard 8,4) | Un seul éditeur ; tableaux de bord d'organisation dans la version commerciale | Veille |
| GUAC | Graphe SBOM → SLSA → artefacts | Aucune release depuis 7 mois, surtout du Dependabot ; certifiers en ligne | Veille |

Sources : [Conforma CLI](https://github.com/conforma/cli), [ImageValidatingPolicy de Kyverno](https://kyverno.io/docs/policy-types/image-validating-policy/), [Archivista](https://github.com/in-toto/archivista), [Chainloop](https://github.com/chainloop-dev/chainloop), [GUAC](https://github.com/guacsec/guac), [AMPEL](https://github.com/policylabs/ampel).

## 6. Intégrité des sources (miroirs et branches custom)

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **Forgejo** : dépôt miroir + fork `workspace/` portant les branches custom | GPL-3.0+, gouverné par Codeberg e.V. v17.0.1, v16.0.7 et v15.0.11 (LTS jusqu'au 07/2027) publiées le 26/10/2026. Équipe sécurité, release de sécurité toutes les 2 à 4 semaines | **Hors programme CVE** (s'abonner au flux `security-announcements`). Pull mirror en lecture seule ; conversion irréversible ; comportement sur force-push non maîtrisé | **Retenu**, avec un **job de sync maison** : `fetch` sans prune vers `refs/archive/<date>/…`, détection des force-push, `git bundle` vers WORM |
| GitLab CE | — | Pull mirroring réservé aux éditions Premium et Ultimate | Écarté |
| Gerrit | — | Plugin pull-replication passé sous BSL | Écarté |
| **gittuf** (OpenSSF Incubating) | Politique par branche et par fichier (packaging), Reference State Log, détection des réécritures. Scorecard 9,3 | **Beta.** Compatibilité Forgejo non vérifiée | Pilote non bloquant (Source Track, option O1) |
| gitsign | Signature de commits sans clé | Exige Fulcio, Rekor et OIDC ; Forgejo ne vérifie pas x509 | Écarté (signatures SSH à la place) |
| source-tool (SLSA Source Track) | VSA de source | GitHub uniquement en pratique | Écarté ; on garde son modèle |
| **Renovate** (plateforme Forgejo) | Tient à jour les digests, bundles Tekton, go.mod, npm, pip et lockfiles | Ne traite pas les miroirs en découverte automatique | **Retenu** |

SLSA v1.2 **Source Track** : L1 « Version controlled », L2 « History & Provenance », L3 « Continuous technical controls », L4 « Two-party review ».

Sources : [releases Forgejo](https://codeberg.org/forgejo/forgejo/releases), [politique de sécurité Forgejo](https://codeberg.org/forgejo/governance/src/branch/main/SECURITY-POLICY.md), [gittuf](https://github.com/gittuf/gittuf), [plateforme Forgejo dans Renovate](https://github.com/renovatebot/renovate/tree/main/lib/modules/platform/forgejo), [exigences de source SLSA v1.2](https://slsa.dev/spec/v1.2/source-requirements).

## 7. Construction et bases de confiance

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **BuildKit** v0.34 | `SOURCE_DATE_EPOCH` + `rewrite-timestamp`, source policies (forcer les digests), `RUN --network=none`, `proxyNetwork`. Scorecard 8,6 | 0.x. **Un démon partagé partage son cache**, ce qui est incompatible avec L3 : il faut **un démon éphémère par TaskRun** (`buildctl-daemonless`). Rootless dans un pod : seccomp et AppArmor `Unconfined`, ou Kata. Digest sensible à la version de BuildKit | **Retenu** (sous réserve de l'ADR 0000) |
| Buildah 1.46 | `--network=none` global, modèle Konflux, Scorecard 8,2 | Reproductibilité « non garantie » selon Red Hat | Repli, ou retenu si Konflux est choisi |
| ko | Images Go sans privilèges | Activité faible | Option |
| apko | Bit à bit | APK seulement | Hors sujet |
| kaniko, repro-get | — | **Archivés** | Exclus |
| **StageX** | Bootstrap complet depuis les sources, reproductible sur 2 marques de CPU, multi-signature PGP (≥ 2, clés sur carte à puce), utilisé par Talos. ISC, 8 mainteneurs | **Seulement 2 signataires sur sx2026.09.0** (le minimum), un contributeur fait environ 63 % des commits, pas de politique de sécurité formalisée, correctifs irréguliers. musl ; **pas de SBOM** (issue ouverte depuis 2024), provenance NV, **pas d'arm64**. Vérification par signatures *lookaside* : Podman OK, Skopeo KO, Kubernetes inconnu | **Retenu, limité à la toolchain Go**, avec reproduction interne et notre propre signature |
| Docker Hardened Images | Gratuites (Apache-2.0 depuis 12/2025), SBOM, VEX, Build L3 | Pas de bit à bit revendiqué ; un seul fournisseur | Repli pour les images d'exécution glibc |
| distroless, Ubuntu chisel, debuerreotype | Images minimales, rootfs Debian reproductibles | Un seul fournisseur, ou un seul mainteneur (debuerreotype) | Options |
| **Nix** (`dockerTools`, `nix2container`, `buildGoModule`, `buildNpmPackage`) | Closures complètes, `--check`, images reproductibles | Écosystème à apprendre ; sandbox exigeant les user namespaces ; cache privé obligatoire ; provenance via Chains seulement | **Challenger 2a** (3 jours) face à Hermeto + BuildKit |

Sources : [releases BuildKit](https://github.com/moby/buildkit/releases), [reproductibilité BuildKit](https://github.com/moby/buildkit/blob/master/docs/build-repro.md), [provenance SLSA BuildKit](https://github.com/moby/buildkit/blob/master/docs/attestations/slsa-provenance.md), [exemples Kubernetes BuildKit](https://github.com/moby/buildkit/tree/master/examples/kubernetes), [doc buildah build](https://github.com/containers/buildah/blob/main/docs/buildah-build.1.md), [StageX](https://codeberg.org/stagex/stagex), [signatures StageX](https://codeberg.org/stagex/signatures), [catalogue DHI](https://github.com/docker-hardened-images/catalog), [nix2container](https://github.com/nlewo/nix2container).

## 8. Isolation et hermétisme

| Option | Isolation | Prérequis | Compatibilité mock / sbuild / buildah | Verdict |
|---|---|---|---|---|
| **Kata Containers** 4.3 | Forte (VM) | KVM : bare metal ou virtualisation imbriquée | Oui (`privileged_without_host_devices=true`) | **Retenu** si KVM est disponible |
| **gVisor** (systrap) | Moyenne à forte | Pas de KVM | Docker validé ; mock et sbuild **à tester** | **Retenu** sans virtualisation imbriquée |
| **Pods en user namespace** (GA en K8s 1.36) | Faible à moyenne (noyau partagé) | Noyau ≥ 6.3, containerd 2 | BuildKit et buildah oui ; mock et sbuild **à tester** | Alternative |
| Sysbox | Moyenne | Ubuntu/Debian, en retard sur K8s | — | **Écarté** : un seul développeur, pas de SECURITY.md |
| Firecracker | Forte | KVM ; virtualisation imbriquée non supportée en production | — | Écarté |
| KubeVirt, Incus | Forte (VM système) | Hyperviseur | Oui (debusine utilise Incus) | Options |

**Preuve d'hermétisme** : on combine trois éléments.
1. **Prévention** : pods de prefetch et de build séparés, NetworkPolicy deny-all.
2. **Configuration attestée** : la configuration d'isolation est inscrite dans la provenance.
3. **Trace et reproduction** : une trace **Tetragon** au format in-toto `runtime-trace`, signée hors du build, plus le **replay indépendant**.

Falco alerte, mais ne produit pas d'attestation. Une trace « vide » seule reste une preuve faible.

Sources : [Kata en mode privilégié](https://github.com/kata-containers/kata-containers/blob/main/docs/how-to/privileged.md), [Docker dans gVisor](https://github.com/google/gvisor/blob/master/g3doc/user_guide/tutorials/docker-in-gvisor.md), [KEP-127 user namespaces](https://github.com/kubernetes/enhancements/blob/master/keps/sig-node/127-user-namespaces/README.md), [releases Sysbox](https://github.com/nestybox/sysbox/releases), [prédicat in-toto runtime-trace](https://github.com/in-toto/attestation/blob/main/spec/predicates/runtime-trace.md).

## 9. Packaging rpm/deb multi-distro

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **mock 6.x hermétique** : `--calculate-build-dependencies` → `buildroot_lock.json` → `mock-hermetic-repo` → `--hermetic-build` | Verrou natif du buildroot ; configs Rocky, Alma, CentOS Stream, RHEL 10 ; images bootstrap | Exige des privilèges, donc VM, gVisor ou user namespace. Scorecard 4,9 (pas de SECURITY.md ; processus Fedora) | **Retenu** |
| **sbuild** (unshare) + **mmdebstrap** | Sans root ; mode des buildd Debian | sbuild : aucun commit sur la branche principale depuis 4 mois, 18 MR ouvertes. mmdebstrap : un seul mainteneur. Atténué par le contrôle des uploads Debian | **Retenu** (paquets Debian épinglés) |
| debusine (Freexian) | Workers de signature, incus | 0.x, une seule entreprise, pas de politique de sécurité | Option |
| OBS | Tout-en-un rpm/deb | Voir §2 | Non adopté (banc A2) ; réglages de reproductibilité et modèle de provenance repris |
| Koji, Copr | Référence Fedora | rpm seulement, lourds | Écartés |
| nfpm | rpm/deb pour binaires statiques | Pas de résolution des dépendances de distro ; bus factor ~1 | Option |
| Nix `vmTools` | rpm/deb natifs pour Debian 12/13, Ubuntu 22.04/24.04, Rocky/Alma 9/10 | **Pas d'EL8 ni de CentOS Stream** (retiré en 01/2026). Un seul contributeur substantiel | Non retenu pour les paquets |
| `guix pack -f deb/rpm` | — | Embarque `/gnu/store` : pas natif | Écarté |

**Macros de reproductibilité rpm** (vérifiées dans `macros.in`, tag par tag) :
- `%_buildhost` existe depuis rpm 4.13 ;
- `%clamp_mtime_to_source_date_epoch` et `%source_date_epoch_from_changelog` existent depuis 4.14 ;
- `%use_source_date_epoch_as_buildtime` existe en 4.16 (EL9) ; sa présence en 4.15 reste NV ;
- `%build_mtime_policy` existe depuis 4.20, donc absent sur EL.
- **Conséquence : EL8 sera reproductible « au mieux ».**

Sources : [builds hermétiques mock](https://github.com/rpm-software-management/mock/blob/main/docs/feature-hermetic-builds.md), [macros rpm 4.14](https://raw.githubusercontent.com/rpm-software-management/rpm/rpm-4.14.0-release/macros.in), [sbuild sur le wiki Debian](https://wiki.debian.org/sbuild), [sbuild en mode unshare (LWN)](https://lwn.net/Articles/999532/), [vmTools](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/vm/default.nix), [debusine](https://salsa.debian.org/freexian-team/debusine).

## 10. Reproductibilité et vérification

| Outil | Rôle | Santé | Usage |
|---|---|---|---|
| diffoscope | Explique les écarts | À surveiller (un mainteneur dominant ; release 335 le 23/10/2026) | Rapport en cas d'écart |
| reprotest | Fait varier l'environnement de build | À surveiller | Replay indépendant |
| strip-nondeterminism, add-determinism | Normalisation après le build (Debian, Fedora) | À surveiller | Selon la distro |
| rebuilderd | Démon de rebuild (Arch, Debian) | À surveiller (un mainteneur dominant) | Ne sait pas traiter nos propres paquets |
| debrebuild + `.buildinfo` | Rebuild Debian | — | Paquets de l'archive Debian uniquement |
| Google OSS Rebuild | Rebuild npm, PyPI et crates, avec attestations | À surveiller (aucune release) | Option pour vérifier les dépendances amont |

**Pratiques retenues :**
- `SOURCE_DATE_EPOCH` ;
- images épinglées par digest ;
- Go : `-trimpath`, `CGO_ENABLED=0`, `GOFLAGS=-mod=vendor` ou `-mod=readonly`, `GOTOOLCHAIN=local` (jamais `-mod=mod`). Avec Hermeto, la fermeture est servie en `GOPROXY=file://…` avec un `GOMODCACHE` vierge : l'environnement de `generate-env` (fermeture = `GOMODCACHE`) laisse passer un zip altéré (mesuré au banc B). Le mode (module ou vendor) change le binaire et s'inscrit dans la provenance ;
- npm : `npm ci` avec lockfile v2/v3 ;
- pip : `--require-hashes` ;
- comparaison des sha256 hors signature OpenPGP ;
- les outils de vérification ne servent **jamais de porte unique**.

**État par écosystème :**
- Debian trixie : environ 97 % de paquets reproductibles en CI variée. Depuis 05/2026, les régressions de reproductibilité bloquent l'entrée dans testing.
- Fedora : environ 90 %.
- Go : la toolchain est reproductible depuis la 1.21.

## 11. Dépendances, stockage, miroirs

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **Hermeto** | Fermeture des dépendances par build. Gestionnaires stables : gomod, npm, pnpm, yarn, pip, bundler, cargo, rpm, generic ; `x-maven` et `x-uv` expérimentaux. SBOM CycloneDX 1.6 / SPDX 2.3 | **Pas de deb.** 3 avis Critical en 08/2026 (exécution de code via les lockfiles). GPL-3.0. Pas de score Scorecard | **Retenu** (dernière version, isolé, sans secrets) ; sortie : vendoring natif |
| Proxies : Athens (Go), Verdaccio (npm), devpi (PyPI), Pulp python | Confort pour le dev et la CI | Le replay ne doit pas dépendre d'eux. Athens : 0.x. devpi : un seul mainteneur, 2 failles High | Verdaccio et Athens retenus en 2c ; devpi remplacé par Pulp |
| **Pulp 3** (pulpcore, pulp_rpm, pulp_deb) | Versions de dépôt immuables (snapshots), déduplication, S3. Red Hat, très actif | Opérateur en beta. En mode `on_demand`, un snapshot n'est pas une archive | **2c**, décidé par l'ADR 0002 (face à aptly) |
| aptly | Snapshots deb simples, MIT | Scorecard 3,4, pas de SECURITY.md, 1 release par an | Repli |
| Nexus CE | Multi-formats | Limites de volume (40k composants / 100k requêtes par jour selon la doc) ; blocage au-delà | Écarté |
| Artifactory OSS / JCR | — | Formats limités (Maven ; Docker/Helm pour JCR) | Écarté |
| **kkRepo** | Compatible Nexus, nombreux formats, Apache-2.0 | **Risqué** : un seul développeur, projet de moins de 4 mois, faille Critical de contournement de l'authentification admin, pas de snapshots | **Écarté** |
| Forgejo packages | Publication de nombreux formats | Pas de proxy | Publication possible |
| **Zot** + **ORAS** | Registre OCI léger, referrers natifs, sync, rétention. `oras cp -r` conserve les referrers | Image Zot **non signée** sur ghcr.io (v2.1.22) : à reconstruire ou épingler | **Retenus** |
| Harbor | UI, RBAC, réplication, Trivy | Plus lourd ; proxy-cache en lecture seule avec rétention de 7 jours par défaut | Alternative multi-équipes |
| CNCF Distribution, Quay | — | Referrers absents (NV) ; Quay lourd | Écartés |
| **Archive WORM** : Ceph hors du cluster de build, ou S3 Object Lock en mode compliance hors site | Rétention garantie | Ceph est lourd (Scorecard 4,6). Le mode governance peut être contourné | **ADR 0006** (2c) |
| MinIO, Garage, SeaweedFS | — | MinIO **archivé le 25/04/2026** ; Garage sans Object Lock ; SeaweedFS : bus factor ~1 et failles Critical | Écartés (SeaweedFS en repli léger) |

**Snapshots publics**, utilisés **en secours uniquement** :
- snapshot.debian.org ;
- snapshot.ubuntu.com, qui couvre depuis le 01/03/2023 ;
- vaults Rocky et Alma, **sans durée de conservation garantie**.

CentOS Stream est une distribution continue : son snapshot local est **obligatoire**.

Sources : [Hermeto](https://github.com/hermetoproject/hermeto), [doc Hermeto](https://hermetoproject.github.io/hermeto/), [dépôts Pulp](https://github.com/orgs/pulp/repositories), [aptly](https://github.com/aptly-dev/aptly), [Zot](https://github.com/project-zot/zot), [oras cp](https://oras.land/docs/commands/oras_cp), [kkRepo](https://github.com/klboke/kkRepo), [MinIO](https://github.com/minio/minio), [service de snapshots Ubuntu](https://documentation.ubuntu.com/server/how-to/software/snapshot-service).

## 12. SBOM

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **Syft** v1.55 | rpmdb, dpkg et langages ; CycloneDX et SPDX. Scorecard 8,7 | Faible sur les images sans base de paquets (StageX, scratch) | **Retenu** (vérifier le qualificatif `distro=` dans les PURL) |
| SBOM Hermeto | Exact sur la fermeture prefetchée | — | **Retenu** |
| Trivy | Complet | **Compromis en 03/2026** (CVE-2026-33634, au catalogue KEV) ; corrigé, releases immuables | Option, épinglé (≥ 0.76.1) |
| cdxgen | Riche pour les langages | Bus factor 1, 6 avis en 2026 dont un Critical. Lance les gestionnaires de paquets (réseau) | Option |
| MS sbom-tool, bom, Tern | — | Pas de CycloneDX ; incubation ; abandonné | Écartés |
| sbomnix / bombon | Closure Nix exacte | `pkg:nix` mal corrélé par les bases de vulnérabilités ; bombon : **Risqué** | Seulement si Nix est adopté |
| **sbomqs** (+ sbomasm, ou `cyclonedx-cli merge`) | Qualité NTIA et BSI TR-03183 ; fusion | Même éditeur, bus factor ~2 | Non bloquants |
| bomctl | — | Inactif depuis plus d'un an | Écarté |

Format pivot : **CycloneDX 1.6**, avec export SPDX 2.3. SPDX 3 reste immature.

## 13. Vulnérabilités, VEX, score

| Option | Rôle | Pour | Contre | Verdict |
|---|---|---|---|---|
| **Grype** (+ vunnel / grype-db) | Scanner | Fournisseurs Alma, Rocky, RHEL, Debian, Ubuntu ; EPSS, KEV, OpenVEX ; base importable hors ligne et **constructible soi-même** | 0.x ; tous ces outils viennent d'Anchore | **Retenu** : autorité pour les paquets OS. Base officielle archivée en 2b, base vunnel en 2c si besoin |
| **OSV / OSV-Scanner v2** | Données + scanner | Zips en masse hors ligne. Couvre Debian (converti), Ubuntu, Alma, Rocky, Red Hat, Go, npm, PyPI, malicious-packages. Scorecard 8,6 | Analyse couche par couche **seulement pour deb/apk** ; pas de VEX. CentOS Stream absent | Contre-contrôle (2c) |
| **Dependency-Track v5** | Plateforme de gestion | Portefeuille, politiques CEL, notifications, CycloneDX VEX, comparaison selon la distro (Debian, Ubuntu, RH), KEV. GA le 09/06/2026, PostgreSQL seul | **Un seul mainteneur fusionne.** Ni CSAF ni OpenVEX. Rocky et Alma non confirmés. Hyades archivé | **Retenu en projection reconstructible** (2c) |
| Trustify | CSAF et VEX natifs (Red Hat) | Très actif | 0.x, pas de SECURITY.md, deb non démontré | POC seulement si un écart est mesuré |
| GUAC | Graphe | Rayon d'impact | Release ancienne ; certifiers en ligne | Veille |
| **VEX** | Format | OpenVEX (Grype, Trivy) ; CycloneDX VEX (DT) ; CSAF (Red Hat, SUSE). Ubuntu publie de l'OpenVEX ; **Debian n'a pas de VEX officiel** | Spec OpenVEX en brouillon v0.2 ; vexctl peu actif | Source en OpenVEX signée et convertie. **L'ADR 0004 évalue CSAF** |
| malicious-packages + GuardDog | Paquets malveillants | Hors ligne (zips OSV) | Revue humaine assurée par une seule personne | **Retenus** |
| Scorecard | Santé amont | GitHub, GitLab, `--local` | Forgejo non supporté | **Retenu** |
| Macaron | Analyse SLSA des dépendances | — | Faible activité | Option |

Point capital : **les backports des distros**. Debian, Ubuntu et RHEL corrigent sans changer la version upstream. Il faut donc des flux propres à chaque distro et une comparaison de versions qui tient compte de la distro, sinon on obtient des faux positifs massifs.

Sources : [vunnel](https://github.com/anchore/vunnel/tree/main/src/vunnel/providers), [construire sa propre base Grype](https://anchore.com/blog/build-your-own-grype-database/), [données OSV](https://github.com/google/osv.dev/blob/master/docs/data.md), [OSV-Scanner hors ligne](https://github.com/google/osv-scanner/blob/main/docs/offline-mode.md), [releases Dependency-Track](https://github.com/DependencyTrack/dependency-track/releases), [Trustify](https://github.com/guacsec/trustify), [VEX Ubuntu](https://documentation.ubuntu.com/security/security-updates/vex/), [données de sécurité Red Hat](https://access.redhat.com/security/data), [avis Trivy](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23).

## 14. Licences (analyse complète « type FOSSA »)

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **ORT** (OSS Review Toolkit) | Chaîne complète : analyzer, scanner, evaluator en Kotlin, reporter (NOTICE, SPDX, CycloneDX, WebApp) ; curations dans git (`ort-config`) ; LF/ACT. Scorecard 6,3 | Pas de rpm/deb natif. Majeures cassantes chaque semaine. Pas de SECURITY.md. L'analyzer lance les gestionnaires de paquets (réseau) | **Retenu** (2c), en tâche Tekton de confiance |
| **ScanCode toolkit** | Licences et copyrights fichier par fichier, **offline** | Lent ; stable de 01/2026, v33 en RC | **Retenu** comme scanner d'ORT |
| ScanCode.io + DejaCode | UI, pipelines, attributions | DejaCode en AGPL | Alternative |
| FOSSology + SW360 | Clearing juridique | Lourds ; FOSSology sans politique de sécurité | Alternative |
| FOSSA CLI | — | Sans le SaaS, il ne reste presque rien ; pas d'air-gap. Licence actuelle NV | Écarté |
| Grant (Anchore) | Autorise ou refuse des licences sur un SBOM | Bus factor 1 | Porte légère (2b-2) |
| **REUSE** (FSFE) | Conformité SPDX de nos dépôts | Scorecard 4,0 | **Retenu** (pré-merge) |
| ClearlyDefined, go-licenses, askalono | — | Pas de dump offline ; inactif ; archivé | Écartés |

**Métadonnées des distros** :
- Fedora : SPDX depuis F41 ;
- EL9 : ancienne nomenclature, traduite via `fedora-license-data` ;
- EL10 et CentOS Stream 10 : mixtes ;
- Debian : DEP-5 non obligatoire.

**Obligations :**
- sources GPL (SRPM, `.dsc`) attachées au binaire et **conservées 10 ans**, avec une offre écrite ;
- règle LGPL pour les binaires Go statiques ;
- RHEL et Ubuntu Pro exclus des paquets redistribués ;
- alignement **OpenChain ISO/IEC 5230 / 18974**.

Sources : [ORT](https://github.com/oss-review-toolkit/ort), [ScanCode toolkit](https://github.com/aboutcode-org/scancode-toolkit), [pipelines ScanCode.io](https://github.com/aboutcode-org/scancode.io/blob/main/docs/built-in-pipelines.rst), [FOSSology](https://github.com/fossology/fossology), [REUSE](https://github.com/fsfe/reuse-tool), [SPDX dans Fedora](https://fedoraproject.org/wiki/Changes/SPDX_Licenses_Phase_4), [OpenChain](https://openchainproject.org/get-started).

## 15. Posture CI/CD et « radar » (type Plumber Radar)

**Plumber Radar** ([getplumber.io/radar](https://getplumber.io/radar)) :
- analyse en direct environ 105 000 projets ;
- note de A à E et score en points ;
- « attack paths » par criticité ;
- tendance sur 7 jours.

C'est un service **hébergé**, non auto-hébergeable. La CLI Plumber (MPL-2.0, v0.7.16) ne couvre que GitHub Actions et GitLab CI.

| Outil | Formats | Hors ligne sur clone | Santé | Usage |
|---|---|---|---|---|
| zizmor | GitHub Actions | Oui | Sain | Radar amont (option O8) |
| poutine | GitHub Actions, GitLab CI, Azure, Tekton PaC (partiel) | Oui (`--disable-version-check`) | Sain (7,3) | Radar amont (O8) |
| `scorecard --local` | Contrôles sur fichiers | Oui | Sain | Radar amont (O8) |
| tekton-lint | Tekton | Oui | À surveiller (5,8) | **Nos pipelines** (brique 08) |
| Plumber CLI | GitHub, GitLab (API GitLab obligatoire) | Partiel | À surveiller (0.x) | Option |
| Legitify, actionlint, octoscan, frizbee, gato-x | — | — | Legitify : Risqué | Écartés ou options |

Tableau de bord :
- v1 en option O8 : site statique (Hugo/Astro) généré à partir de JSON, signé dans Zot, plus Grafana ;
- v2 : Backstage, seulement si un portail développeur est prévu ;
- écartés : scorecard-monitor (lié à GitHub) et Thoughtworks BYOR (inactif).

## 16. Observabilité

| Brique | Santé (Scorecard 28/10/2026) | Licence | Usage |
|---|---|---|---|
| Prometheus + Alertmanager | 8,1 / 6,6 | Apache-2.0 | Métriques d'exploitation et alertes (2b-1) |
| Grafana | 7,0 | **AGPL-3.0** (sans impact en usage interne non modifié) | Tableaux de bord exploitation et KPI supply-chain |
| Loki | 8,4 | AGPL-3.0 | Journaux (option) |
| OpenTelemetry Collector | 7,7 | Apache-2.0 | Option |
| VictoriaMetrics | 5,4 | Apache-2.0 | Alternative si le volume l'exige |

## 17. Synthèse : pourquoi ces choix, et ce qui reste challengé

- **Cœur L3 : Tekton + Chains.** Il n'existe pas d'alternative open source auto-hébergée.
- **Mieux que Konflux sur plusieurs points** :
  - Grype/DT (au lieu de Clair/Trustify) ;
  - Zot (au lieu de Quay) ;
  - BuildKit à démon éphémère ;
  - sbuild ;
  - ORT/ScanCode ;
  - OpenPGP ;
  - TSA ;
  - rebuild indépendant avec VSA ;
  - observabilité.
- **Mesuré en phase 2a**, avec une grille pondérée fixée d'avance :
  - Konflux et OBS (adopter ?) ;
  - **Nix** (moteur de build) ;
  - **Kyverno seul** (moteur de politique).
- **En veille** : Guix, Chainloop, GUAC, AMPEL, Witness, Sigstore auto-hébergé sans clé, Trustify.

## 18. Points non vérifiés (à lever en phase 2)

- Sujet non-image dans Chains (rpm poussé via ORAS, `isBuildArtifact: true`) : déduit du code, **à tester** (brique 08).
- **Confusion signature / attestation** avec les bundles cosign v3 : confirmée par le banc C et par des rapports publics. En conséquence : contrôle strict `cosign/sign/v1`, Chains en mode `dsse` jusqu'à la publication de chains#2096, et clés séparées par usage.
- Compatibilité de `hashivault://` de Chains avec OpenBao.
- mock et sbuild sous gVisor et en user namespace (brique 05).
- Qualificatif `distro=` produit par Syft et Hermeto, et consommé par DT.
- Vérification des images amont : **faite** (doc 04 §5). Renovate, OpenBao et Kyverno sont vérifiés. **Tekton** (clé documentée non concordante), **Conforma** (méthode non documentée) et **Zot** (non signé) ne sont pas vérifiables : il faut les reconstruire, ou les épingler après revue.
- ~~Vérification par Kyverno d'un jeton RFC 3161 séparé (non documentée)~~ : **mesurée en brique 08 (J5)**. Kyverno 1.19.2 (CLI ; admission en J6) ne lit l'horodatage que dans un bundle et, avec une clé sans journal de transparence, **plante sur un jeton valide** (nil pointer) ; il ne vérifie pas non plus les attestations au format historique (`.att`) sans journal. cosign v3.1.4 vérifie le bundle réémis (`--trusted-root`), et refuse jeton absent, altéré, d'une autre signature ou d'une TSA étrangère. Support des bundles Sigstore par Conforma (présent dans le code, absent de la doc) : à tester en brique 08.
- Scores Scorecard de Hermeto, Pulp, Trustify, ScanCode, vunnel, Tetragon, Konflux, Grant et zizmor : il faut le CLI Scorecard et un jeton GitHub.
- Licence actuelle de FOSSA CLI (sans impact : écarté).
