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

Relevé du 2026-10-28 via https://api.securityscorecards.dev

| Projet | Dépôt | Domaine | Chemin critique | Score | Date du relevé | Maintained | Signed-Releases | Code-Review | Vulnerabilities |
|---|---|---|---|---|---|---|---|---|---|
| Tekton Pipelines | tektoncd/pipeline | orchestration | oui | 6.7 | 2026-10-26 | 10 | 0 | 10 | 0 |
| Tekton Chains | tektoncd/chains | provenance | oui | 7.1 | 2026-10-19 | 10 | 0 | 10 | ? |
| Tekton Triggers | tektoncd/triggers | orchestration | oui | 6.9 | 2026-10-19 | 10 | 0 | 8 | ? |
| Conforma | conforma/cli | politique | oui | 6.6 | 2026-10-28 | 10 | 0 | 10 | 0 |
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
| **Sain, mais un seul éditeur** | Chainloop, DejaCode, Grafana (Grafana Labs, AGPL) |
| **À surveiller, chemin critique** | **Chains, Triggers, Conforma, Hermeto, mock, BuildKit, Grype, sbuild, mmdebstrap, tekton-lint** |
| **À surveiller (Scorecard < 6)** | REUSE (4,0), Athens (5,8), mock (4,9), Ceph (4,6), aptly (3,4), tekton-lint (5,8), VictoriaMetrics (5,4) |
| **À surveiller, hors chemin critique** | Konflux, rpm-lockfile-prototype, ko, nfpm, Witness, gittuf, AMPEL, vunnel, grype-db, Dependency-Track v5 (un seul mainteneur fusionne), Trustify, GUAC, vexctl, sbomqs, sbomasm, malicious-packages, Trivy, cdxgen, cyclonedx-cli, protobom, Macaron, sbomnix, createrepo_c, devpi, SeaweedFS, nixpkgs vmTools, StageX, debusine, diffoscope, reprotest, strip-nondeterminism, add-determinism, rebuilderd, OSS Rebuild, repro-env, debuerreotype, ScanCode toolkit, FOSSology, Grant, ORT Server, Plumber CLI, octoscan, frizbee |
| **Risqué → interdit** | kkRepo, Archivista, RSTUF, Sysbox, bombon, Hyades (archivé), go-licenses, askalono (archivé), ClearlyDefined (en offline), Legitify, kaniko (archivé), repro-get (archivé), Earthly, MinIO (archivé), Tern |

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
| Tekton Chains v0.29.9 | `release.yaml` hébergé sur `infra.tekton.dev`, qui redirige vers `objectstorage.us-ashburn-1.oraclecloud.com` | **Non vérifié** : ce dernier hôte est bloqué | À refaire (ouvrir ce domaine) |

**Enseignement.** Un score « Sain » ne garantit pas des artefacts vérifiables. Tekton (Scorecard 6,7, très actif) publie des images dont la signature ne se vérifie pas avec la clé documentée, Conforma ne documente pas comment vérifier ses images, et Zot (8,1) ne signe pas les siennes. Les trois sont sur le chemin critique. La règle reste donc : **on reconstruit les images d'outils du chemin critique, ou on les épingle par digest après revue**. Ce n'est pas une option.

## 6. Plans de sortie (chemin critique)

| Projet | Risque | Contre-contrôle ou sortie |
|---|---|---|
| Tekton Chains | 0.x, **aucun substitut L3** | OpenShift Pipelines ou Konflux (embarquent Chains). VSA de replay signée par une autre clé |
| Conforma | 0.x, sponsor unique | Mini-politique dupliquée en Kyverno-JSON ou OPA ; **challenger 2a : Kyverno moteur unique** |
| Hermeto | 3 avis Critical en 08/2026 | Dernière version, prefetch isolé sans secrets ; sortie : vendoring natif scripté |
| mock | Scorecard 4,9 | OBS (benchmark 2a) |
| BuildKit | 0.x, concentration sur 2 développeurs | Buildah (et inversement) ; **challenger 2a : Nix** |
| Grype | Unique scanner sur EL | Base archivée datée ; OSV-Scanner sur le SBOM (à valider) |
| sbuild / mmdebstrap | Bus factor faible | Paquets Debian épinglés (contrôle des uploads) ; debusine en option |
| Dependency-Track | Un seul mainteneur | Projection reconstructible depuis les SBOM et VEX (ré-ingest testé) |

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
