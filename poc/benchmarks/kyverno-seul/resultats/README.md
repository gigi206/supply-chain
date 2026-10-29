# Résultats du banc C : Kyverno seul ou Conforma + Kyverno (28/10/2026)

Grille : [ADR 0000 §4](../../../../docs/adr/0000-assembler-ou-adopter.md) (figée avant le banc).

## Environnement

| Élément | Version / détail |
|---|---|
| Conforma | `ec` v0.10.42 (source `5d22a0b5`), empreinte SHA-256 vérifiée contre la release |
| Kyverno CLI | v1.19.2, empreinte vérifiée (`checksums.txt`) |
| cosign | v3.1.4, empreinte vérifiée |
| Registre | Zot v2.1.22 local (empreinte vérifiée), OCI 1.1 Referrers |
| Format | Signatures et attestations en **bundles Sigstore v0.3 via OCI Referrers** (le format de Chains `sigstore-bundle`), clés locales, sans journal de transparence |
| Hôte | 4 CPU, 15 Gi, sans KVM ni Docker |

Reproduction :

```bash
REG=localhost:5000 WORKDIR=/tmp/bench-c ./setup.sh
```

```bash
WORKDIR=/tmp/bench-c ./run.sh
```

Le détail par cas est dans [`resultats.md`](resultats.md).

## Résultats

- **17 cas sur 17 conformes à l'attendu pour les deux moteurs**, contrôles 1 à 8 et 10. Les cas couvrent signature, provenance, builder, source, dépendances, tâches de confiance, VSA (absente, en échec, mauvaise clé), KEV, VEX valide ou expiré, paquet malveillant et licences.
- **Temps médian par artefact** : Conforma 987 ms (max 1 162), Kyverno 498 ms (max 574).
- **Taille des règles** : Conforma 77 lignes de Rego + 13 lignes de données ; Kyverno 88 lignes de YAML/CEL.

### Rejeu sur le laptop (29/10/2026)

Mêmes versions (outils de [`mise.toml`](../../../../mise.toml), sommes et signatures vérifiées), même registre Zot v2.1.22 : **17 cas sur 17 avec les mêmes verdicts et les mêmes motifs** pour les deux moteurs ([`resultats-laptop.md`](resultats-laptop.md)). Temps médian : Conforma **1 030 ms** (max 2 040 ms ; 750 ms au premier passage), Kyverno **330 ms** (max 350 ms). C-6 ne change pas (≤ 5 s pour les deux).

Le premier passage a affiché une durée **négative** (−59 ms). `run.sh` mesurait avec `date +%s%3N`, une horloge murale qui peut reculer. Il utilise désormais `/proc/uptime`, une horloge monotone au centième de seconde, comme le banc de la brique 07a.

## Constat de sécurité : confusion signature / attestation (cosign v3)

Avec le format bundle de cosign v3, **la signature d'image est elle-même un DSSE in-toto** de type `https://sigstore.dev/cosign/sign/v1`. Les vérifications « par défaut » n'exigent pas ce type précis.

| Outil | Comportement observé sur une image **sans signature**, mais avec des attestations signées par la clé de confiance |
|---|---|
| `cosign verify` v3.1.4 | « The cosign claims were validated ». Les claims renvoyées ont pour `type` le type de prédicat de l'attestation (`https://slsa.dev/provenance/v1`, `…/scan/v1`). **Une seule attestation de scan suffit** |
| Conforma v0.10.42 | `signatures: 0`, mais « Image signature check passed » |
| Kyverno 1.19.2 | `verifyImageSignatures(...) > 0` |

**Vérification approfondie (pas d'erreur de manipulation).** Le code de cosign v3.1.4 confirme le comportement. Dans `cmd/cosign/cli/verify/verify.go`, avec le commentaire `// OCI bundle always contains attestation`, `cosign verify` appelle `VerifyImageAttestations`. Celui-ci récupère **tous** les referrers (`GetBundles` → `Referrers(digest, "")`), et le vérificateur de claims ne contrôle que le sujet, jamais le `predicateType`. Le même problème a été reproduit indépendamment dans [juburr/cosign-orb#47](https://github.com/juburr/cosign-orb/pull/47) (cosign 3.1.3 et 2.6.5 ; le mode historique `.sig` n'est pas affecté) et corrigé dans Zot par [project-zot/zot#4492](https://github.com/project-zot/zot/pull/4492). **Au 28/10/2026, aucune issue ni aucun avis n'existe chez sigstore/cosign.**

**Implication pour Tekton Chains** : selon [tektoncd/chains#2096](https://github.com/tektoncd/chains/pull/2096) (**ouverte**, non fusionnée au 28/10/2026), Chains v0.29.x en mode `sigstore-bundle` écrit des **signatures d'image invalides** : un payload simplesigning dans un DSSE, journalisé en `hashedrekord`. Cosign masque l'échec dès qu'une attestation SLSA est présente. **Il faut donc rester en mode `dsse` (tags) tant que ce correctif n'est pas publié.**

**Conséquence.** Tout composant qui atteste une image avec une clé de confiance (scanner, licences) la rend « signée » aux yeux de ces contrôles. C'est un contournement possible de la porte si les clés sont partagées entre usages.

**Correctifs appliqués au banc et à retenir pour la plateforme :**
1. **Contrôle strict de la signature** :
   - Conforma : `count(input.image.signatures) > 0` ;
   - Kyverno : `verifyAttestationSignatures(i, attestations.sig, …)` avec `type: https://sigstore.dev/cosign/sign/v1`.

   Avec ce contrôle, `c1-unsigned` est rejeté par les deux moteurs.
2. **Séparation des clés par usage** (ADR 0003) : la clé qui signe les images et la provenance (Chains) n'est jamais utilisée par les scanners ni par l'analyse de licences.
3. **Signalement amont** : le problème est déjà public (PR citées), mais aucune issue n'existe chez sigstore/cosign, ni chez Conforma (contrôle « Image signature check passed » avec 0 signature) ou Kyverno. Ouvrir ces issues est **à décider par le propriétaire du projet** ; aucune action n'a été faite.
4. **Chains en mode `dsse`** (tags `.sig`/`.att`) tant que tektoncd/chains#2096 n'est pas publiée ; le contrôle strict reste actif dans les deux modes.

## Autres constats

- **Kyverno** : `extractPayload()` renvoie l'**énoncé in-toto complet** (accès par `.predicate.…`), alors que l'exemple de la doc suggère le prédicat directement. Il faut aussi appeler `verifyAttestationSignatures()` avant, dans la même politique. Les fonctions `time.now()` et `timestamp()` permettent les exceptions datées.
- **Conforma** :
  - les règles doivent être dans le paquet `release` (espace de noms évalué) ;
  - les attestations signées par une **autre clé** que celle passée en `--public-key` sont ignorées en entrée ; la VSA est donc vérifiée via `ec.sigstore.verify_attestation(ref, {"public_key": …})` ;
  - la lecture des bundles et des referrers fonctionne, mais elle **n'est pas documentée**.
- **Non testé en local** :
  - **contrôle 9** (horodatage RFC 3161) : il faut une TSA ; **mesuré en brique 08, J5** (voir plus bas) ;
  - **C-2** (parité entre CLI et admission) : il faut un cluster ; **mesuré en brique 08, J6** (voir plus bas) ;
  - **bibliothèque Conforma** `slsa3` / `trusted_task` sur une **vraie** provenance Chains : à refaire en brique 08.

## Notation provisoire (grille C)

Les notes restent provisoires : C-2 est mesuré (brique 08, J6), mais le propriétaire a reporté la décision C à J8 (voir plus bas). Contrôle 9 mesuré en brique 08, J5 ; lecture du propriétaire du 29/10/2026.

| Critère | Poids | Kyverno seul | Justification | Conforma + Kyverno | Justification |
|---|---|---|---|---|---|
| C-1 Couverture | 35 | 5 | 10/10 : contrôles 1 à 8 et 10 au banc (17/17 cas) ; contrôle 9 en brique 08 (J5), vérifié par cosign v3.1.4 dans la porte (`tools/verify-ts`), compté par décision du propriétaire | 5 | Idem : le contrôle 9 ne dépend pas du moteur |
| C-2 Parité CLI / admission | 15 | 5 | **Mesuré en brique 08, J6** : même fichier de politique, mêmes pods, 25/25 décisions identiques (17 cas du banc, 8 cas d'horodatage) ; note retenue par le propriétaire | 2 | Deux langages (Rego en CLI, CEL à l'admission) : parité par double maintenance |
| C-3 Bundles, referrers, TSA | 15 | 2 | Bundles et referrers natifs, y compris dans un dépôt séparé ; doc d'`extractPayload` inexacte ; **horodatage natif mais en erreur interne** avec une clé sans journal (brique 08, J5, CLI) | 3 | Natifs mais non documentés ; horodatage de Conforma non mesuré (aucune option dans `ec validate image`), à reprendre en J8 |
| C-4 Maintenabilité | 15 | 3 | 88 lignes, un seul langage ; tests (`kyverno test`) à écrire | 2 | 77 lignes de Rego + 88 de CEL, deux langages ; tests à écrire |
| C-5 Santé | 10 | 4 | Sain, CNCF, plusieurs employeurs (Scorecard 7,8) | 2 | Limité par Conforma : 0.x, sponsor unique (6,6) |
| C-6 Performance | 10 | 5 | ≈ 0,5 s | 5 | ≈ 1 s |
| **Score /100** | | **83** | | **70** | |

**Contrôle 9 mesuré en brique 08, J5 (29/10/2026)** ([journal](../../../bricks/08-trust-plane/resultats/tsa-chemins.log)). Le job d'horodatage réémet chaque enveloppe de Chains en bundle v0.3 avec un jeton RFC 3161, dans un dépôt séparé de celui de l'image :
- **Kyverno 1.19.2, CLI** (attestor à clé, `insecureIgnoreTlog`, `tsaCertChain`) : jeton valide → `error` (« nil pointer dereference ») ; jeton absent ou aucun bundle → refus. Le contrôle 9 n'est donc pas assuré par le CLI de Kyverno ; l'admission partage ce code, la parité se mesure en J6 (C-2). Sans `tsaCertChain`, le même bundle passe (témoin). Kyverno ne vérifie pas non plus la provenance au format historique (`.att`) sans journal de transparence ;
- **cosign v3.1.4** (`--use-signed-timestamps`, racine de confiance du TSA) : jeton valide accepté ; aucun bundle, bundle sans jeton, jeton altéré, jeton d'une autre signature et jeton d'une TSA étrangère refusés ;
- **Conforma v0.10.42** : non mesuré (aucune option d'horodatage dans `ec validate image`).

**Lecture du propriétaire (29/10/2026)** : un contrôle 9 vérifié hors du moteur de politique (`tools/verify-ts`, ici cosign) compte dans C-1, pour les deux options. Notes mises à jour en conséquence : C-1 passe de 4 à 5 pour les deux (10/10), et C-3 de Kyverno seul passe de 3 à 2 (horodatage natif mais en erreur). Scores : 76 → **80** et 63 → **70**.

**C-2 mesuré en brique 08, J6 (29/10/2026)** ([journal](../../../bricks/08-trust-plane/resultats/politique-parite.log), [tableau](../../../bricks/08-trust-plane/resultats/politique-parite.tsv)). Kyverno 1.19.2 installé à l'admission sur k3s (images vérifiées, tirées de Zot) :
- **même fichier de politique** pour le CLI et l'admission : le modèle du banc, clés injectées comme dans `run.sh`, seul le glob change (`localhost:5000/*` → `192.168.161.13:5000/bench/*`) ; **mêmes pods**, créés à l'admission en `kubectl create --dry-run=server` (preuve préalable : `c1-unsigned` est refusé par l'API, donc Kyverno évalue bien en dry-run) ;
- **17 cas du banc** (repoussés par `setup.sh` dans le Zot du cluster) : 17/17 décisions et motifs identiques, conformes à l'attendu ;
- **8 cas d'horodatage de J5** (une politique par variante) : témoin, bundle sans jeton, aucun bundle et attestation `.att` identiques. Dès qu'un jeton est présent (valide, altéré, d'une autre signature, d'une TSA étrangère), **les deux côtés rencontrent la même erreur interne** (« nil pointer dereference ») : le CLI la rend en `error` avec le code de sortie 1, l'admission la traduit en **refus** avec le même message (pas d'admission par défaut) ;
- **parité des décisions : 25/25** (admis si et seulement si `pass`, code 0) ; parité des libellés : 21/25 ;
- durée moyenne par cas : 406 ms en CLI (lancement du binaire compris), 144 ms à l'admission (aller-retour de `kubectl` compris).

**Lecture du propriétaire (29/10/2026)** : C-2 = 5 pour Kyverno seul (parité totale des décisions). Score 80 → **83**, référence inchangée à **70** (C-2 = 2, deux langages : non mesurable par construction). Kyverno seul passe la règle C (10/10, 83 ≥ 63), mais **la décision C est reportée à J8** : Conforma reste la porte de release en J6, et la réserve ci-dessous est mesurée d'abord. Réserve : la bibliothèque Conforma (`slsa3`, `trusted_task` sur la vraie provenance Chains) n'a pas été mise à profit ici ; la réimplémenter en CEL sur la vraie provenance pourrait coûter plus que dans ce banc synthétique.
