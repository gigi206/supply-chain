# ADR 0000 : adopter (Konflux, OBS) ou assembler, et challengers Nix et Kyverno

- **Statut** : **Proposé. Grille figée le 28/10/2026, avant tout benchmark.** Les résultats seront ajoutés en annexe sans modifier la grille.
- **Décideurs** : propriétaire du projet
- **Références** : [`00-etude-existant.md`](../00-etude-existant.md), [`01-exigences.md`](../01-exigences.md), [`04-sante-projets.md`](../04-sante-projets.md)

## Contexte

Aucun projet ne couvre l'ensemble du besoin. L'hypothèse par défaut est un « Konflux allégé » : Tekton + Chains + briques complémentaires. Quatre évaluations limitées dans le temps doivent confirmer ou infirmer trois choix :

| Évaluation | Question | Référence comparée | Durée max |
|---|---|---|---|
| **A1. Konflux** | Adopter Konflux comme cœur ? | Assemblage (référence papier, §2.3) | 3 jours |
| **A2. OBS** | Adopter OBS pour le packaging rpm/deb ? | mock + sbuild dans Tekton | 3 jours |
| **B. Nix** | Nix comme moteur de build pour Go et les images OCI ? | Hermeto + BuildKit (démon éphémère) | 3 jours |
| **C. Kyverno seul** | Kyverno comme moteur de politique unique (CLI + admission) ? | Conforma (release) + Kyverno (admission) | 2 jours |

Règles communes :
- grille et seuils **figés avant** les tests ;
- notes de 0 à 5 par critère, multipliées par le poids (total sur 500, ramené à 100) ;
- chaque note est **justifiée par une mesure ou une preuve** (commande, journal, capture) archivée dans `poc/benchmarks/<nom>/resultats/` ;
- dépasser la durée maximale vaut « non démontré » sur les critères restants.

## 1. Critères éliminatoires (communs)

Un candidat est **éliminé** si l'un de ces points n'est pas démontré :

1. **Provenance non falsifiable** : générée et signée hors de portée des étapes de build (L3), ou compatible avec Chains dans ce rôle (pour B et C).
2. **Fonctionnement offline** : build ou évaluation sans egress, à partir d'entrées archivées.
3. **Licence open source** et **auto-hébergement** complet, sans SaaS obligatoire.
4. **Santé** : pas de verdict « Risqué » ([doc 04](../04-sante-projets.md)).
5. **amd64** et distros cibles atteignables : Debian 12/13, Ubuntu 22.04/24.04, Rocky/Alma 9/10, CentOS Stream 9/10 (pour A1 et A2).

## 2. Grille A : socle (Konflux, OBS)

| # | Critère | Poids | 5 = | 0 = |
|---|---|---|---|---|
| A-1 | Couverture des besoins B1 à B14 sans développement | 25 | ≥ 12 besoins couverts nativement | ≤ 4 |
| A-2 | Garanties L3 **démontrées** (sur les 8 tests négatifs du doc 01, combien sont passables, c'est-à-dire bloqués) | 20 | 8/8 | ≤ 3/8 |
| A-3 | Reproductibilité : artefacts bit-identiques sur 2 builds (rpm rocky-9, deb debian-13, image) | 15 | 3/3 identiques | 0/3 |
| A-4 | Effort pour combler les manques (pw estimés, documentés) | 15 | ≤ 5 pw | ≥ 25 pw |
| A-5 | Poids opérationnel (RAM au repos, nombre de composants, procédure de mise à jour) | 10 | ≤ 8 Gi, ≤ 10 composants | ≥ 32 Gi ou ≥ 40 composants |
| A-6 | Santé et pérennité (doc 04) | 10 | Sain, plusieurs employeurs | À surveiller avec bus factor 1 |
| A-7 | Maîtrise et dépendance (cadre imposé, possibilité de sortie) | 5 | Briques remplaçables une à une | Tout ou rien |

**Seuils pratiques** (au-delà, « non démontré ») :
- installation ≤ 1 jour ;
- premier build signé avec provenance ≤ 2 jours ;
- ≤ 32 Gi de RAM ;
- webhook Forgejo **authentifié** (signature vérifiée) ;
- Konflux : deb possible **sans forker** le cœur ;
- OBS : rpm **et** deb bit-identiques sur 2 builds.

### 2.3 Référence « assemblage » (notée sur papier avant les tests)

| Critère | Note | Justification |
|---|---|---|
| A-1 | 2 | Tout est à intégrer, mais chaque besoin a une brique identifiée |
| A-2 | 4 | Contrôles L3 conçus (Chains, OpenBao, Kyverno, Conforma) ; à démontrer en 2b-1 |
| A-3 | 3 | Pratiques connues (SDE, mock hermétique, sbuild) ; EL8 au mieux |
| A-4 | 1 | ≈ 21 pw pour 2b-1 + 2b-2 |
| A-5 | 4 | Composants choisis pour leur légèreté |
| A-6 | 3 | Chemin critique « À surveiller » mais avec plans de sortie |
| A-7 | 5 | Briques remplaçables une à une |
| **Total** | **(2×25 + 4×20 + 3×15 + 1×15 + 4×10 + 3×10 + 5×5) / 5 = 57/100** | |

**Règle de décision A** : un candidat est **adopté** s'il n'est pas éliminé **et** s'il dépasse la référence d'au moins **10 points** (≥ 67/100). OBS peut être adopté **pour le packaging seul** sur les critères A-1 (restreint à B1, B4, B5 et B8), A-3, A-5 et A-6.

## 3. Grille B : moteur de build (Nix ou Hermeto + BuildKit)

Banc d'essai : `poc/sample-app` (Go + front npm embarqué), qui produit un binaire et une image OCI.

| # | Critère | Poids | 5 = | 0 = |
|---|---|---|---|---|
| B-1 | Bit à bit : 2 builds sur 2 hôtes, à ≥ 1 h d'écart, caches vides | 25 | Binaire et image identiques | Aucun |
| B-2 | Rebuild offline depuis la fermeture archivée (egress bloqué) | 20 | Réussi sans intervention | Impossible |
| B-3 | Taille de l'archive de fermeture et déduplication entre 2 versions | 10 | ≤ 1,5× les sources + dépendances, dédup ≥ 50 % | ≥ 5× |
| B-4 | SBOM : PURL standards, exploitables par Grype et DT (taux de composants corrélés) | 15 | ≥ 95 % | ≤ 50 % |
| B-5 | Intégration Tekton + Chains : sujets et `resolvedDependencies` exacts, sans privilège hors userns | 15 | Complète, pod non privilégié | Pod privilégié requis |
| B-6 | Coût d'adoption : temps pour empaqueter sample-app, lignes de configuration à maintenir | 10 | ≤ 0,5 j, ≤ 100 lignes | ≥ 3 j |
| B-7 | Santé et pérennité | 5 | Sain | À surveiller, bus factor 1 |

**Règle de décision B** : Nix est retenu pour Go et l'OCI s'il n'est pas éliminé **et** s'il dépasse la référence Hermeto + BuildKit d'au moins **15 points**, l'écart couvrant le coût d'un second écosystème. Sinon, il reste en veille.

## 4. Grille C : moteur de politique (Kyverno seul ou Conforma + Kyverno)

Jeu de règles de référence : les **10 contrôles de release** qui doivent être exprimables et vérifiés **hors ligne en CLI** comme à l'admission.

1. Signature de l'artefact par l'identité attendue (clé ou identité sans clé).
2. Provenance SLSA v1 présente, signée, avec `builder.id` attendu.
3. `buildType` et `externalParameters` conformes (dépôt Forgejo `workspace/…`, ref autorisée).
4. `resolvedDependencies` tous épinglés par digest, depuis des origines autorisées (Zot interne).
5. Tâches de confiance uniquement : bundles Tekton signés, liste autorisée (équivalent `trusted_task`).
6. VSA de replay présente, signée par la clé du domaine de replay, résultat `PASSED`.
7. Attestation de scan : aucune KEV sans VEX, aucun MAL-.
8. Verdict de licences : aucune violation ERROR.
9. Horodatage RFC 3161 valide (intégré au bundle ou vérifié par `tools/verify-ts`).
10. Exceptions datées et motivées (VEX, dérogations) avec expiration.

| # | Critère | Poids | 5 = | 0 = |
|---|---|---|---|---|
| C-1 | Couverture des 10 contrôles | 35 | 10/10 | ≤ 5/10 |
| C-2 | Évaluation hors ligne en CLI identique à l'admission (mêmes règles, mêmes résultats) | 15 | Parité totale | Pas de CLI |
| C-3 | Bundles Sigstore et referrers OCI, horodatage | 15 | Natifs et documentés | Absents |
| C-4 | Maintenabilité : lignes de règles, tests unitaires des règles, lisibilité | 15 | ≤ 300 lignes testées | ≥ 1 500 lignes ou pas de tests |
| C-5 | Santé et pérennité | 10 | Sain, plusieurs employeurs | Un seul sponsor, 0.x |
| C-6 | Performance : évaluation d'un artefact | 10 | ≤ 5 s | ≥ 60 s |

**Règle de décision C** : Kyverno seul est retenu s'il n'est pas éliminé, couvre **10/10** contrôles **et** atteint au moins **90 %** du score de la référence Conforma + Kyverno. Un moteur en moins est une simplification qui justifie de concéder 10 %.

## 5. Décision

> À compléter après les benchmarks : notes, preuves, scores, décision et plan de sortie. **La grille ci-dessus ne doit pas être modifiée** ; tout ajustement passe par un nouvel ADR.
>
> **Constat de sécurité du banc C** : avec les bundles cosign v3, `cosign verify`, Conforma et Kyverno acceptent une image **sans signature** dès qu'elle porte une attestation signée par la clé de confiance. Il faut un contrôle strict du type `https://sigstore.dev/cosign/sign/v1` et des clés séparées par usage (voir les résultats du banc C). Ce comportement est connu publiquement (cosign-orb#47, zot#4492) et touche aussi Chains v0.29.x en mode `sigstore-bundle` (chains#2096, non publiée) : **Chains reste en mode `dsse`** jusqu'au correctif.

| Évaluation | Score candidat | Score référence | Éliminé ? | Décision |
|---|---|---|---|---|
| A1. Konflux | **17** (banc du 29/10/2026) | 57 | **Proposé** : critère 1 non démontré en configuration par défaut (une PR lit la clé de Chains sur le nœud) ; critères 2 (évaluation), 3 (`tpa-scan` exige un service Red Hat) et 5 (rpm, deb) non démontrés | **Non adopté** (17 < 67). Installation en 7 min, premier build signé en 1 h 24 (seuils atteints), image reproductible ; mais 1 besoin couvert nativement sur 14, 3 tests négatifs bloqués sur 8, provenance SLSA v0.2 sans horodatage, rejeu de webhook accepté, SBOM envoyé à `exhort.stage.devshift.net` par une tâche exigée, environnement Go de `hermeto generate-env` utilisé tel quel (constat du banc B). L'assemblage reprend les artefacts de confiance, la PR de configuration et les règles Conforma ([résultats](../../poc/benchmarks/konflux/resultats/README.md)) |
| A2. OBS (packaging) | **42** (banc du 29/10/2026, grille restreinte A-1 sur B1/B4/B5/B8, A-3, A-5, A-6) | **55** (référence restreinte ; seuil 65) | **Non** (critère 5 partiellement démontré : rocky-9 et debian-13 seulement) | **Non adopté** (42 < 65). Master épinglé (`2.11~alpha`, commit `58021baee2`) : **aucune release ne produit de provenance**, et master n'a pas de release depuis 2019. rpm et deb **bit-identiques** sur 2 builds (rpm hors signature, avec `Release: <CI_CNT>`) ; rebuild hors ligne identique ; provenance générée par le worker hors de la VM de build (KVM sans réseau), signée en DSSE, **non falsifiable** sur 6 tentatives ; dépendances conservées et récupérables par digest. Mais 1 besoin sur 4 couvert nativement (B5) : pas de replay ni de VSA, fermeture Go/npm hors OBS, pas d'attestation de lien. SLSA v1 non conforme (`runDetails.id`). Lecture de A-1 à valider : compter B4 et B8 ferait passer à 75 ([résultats](../../poc/benchmarks/obs/resultats/README.md)) |
| B. Nix | **74 (provisoire, critères mesurés)** | **91 (provisoire : B-1 mesuré sur 2 hôtes le 29/10/2026)** | Non | **Veille (provisoire)** : la référence passe devant, alors que la règle exige +15 pour Nix. Nix gagne sur l'offline complet (toutes toolchains) mais perd sur le SBOM (`pkg:nix`). Référence : binaire et image identiques entre le cloud et le laptop (> 10 h d'écart). Nix : B-1 multi-hôtes non mesurable contre le cloud (empreintes de sortie non archivées), B-5 reste à mesurer ; même à 5 sur les deux (83/100), Nix ne peut plus atteindre l'écart de +15 exigé, la référence ayant déjà 77 points sans B-5. Constat : l'environnement de `hermeto generate-env` laisse passer un zip Go altéré ; la fermeture doit être servie en `GOPROXY` ([résultats](../../poc/benchmarks/nix/resultats/README.md)) |
| C. Kyverno seul | **76 (provisoire)** | **63 (provisoire)** | Non | **Suspendue** : 9/9 contrôles testés réussis (17/17 cas) ; contrôle 9 (TSA) et parité à l'admission à mesurer en brique 08 ([résultats](../../poc/benchmarks/kyverno-seul/resultats/README.md)) |

## 6. Préalables d'exécution

| Évaluation | Peut tourner dans l'environnement de développement actuel (4 CPU, 15 Gi, sans KVM ni Docker) ? | Prérequis |
|---|---|---|
| A1. Konflux | **Non** | Infra du PoC (ADR 0001) : Kind ou k3s, ≥ 16 Gi |
| A2. OBS | **Non** | VM ou serveur avec KVM (workers OBS) |
| B. Nix | **Partiellement** : Nix 2.34 et cache.nixos.org disponibles. B-1 sur 2 hôtes et B-5 (Tekton) demandent l'infra du PoC | sample-app ; second hôte |
| C. Kyverno seul | **Oui** pour C-1 à C-4 et C-6 en CLI : registre Zot local, attestations de test signées avec cosign. La parité avec l'admission demande un cluster | Binaires Kyverno CLI et Conforma |
