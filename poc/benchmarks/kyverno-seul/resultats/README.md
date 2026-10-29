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
  - **contrôle 9** (horodatage RFC 3161) : il faut une TSA ;
  - **C-2** (parité entre CLI et admission) : il faut un cluster ;
  - **bibliothèque Conforma** `slsa3` / `trusted_task` sur une **vraie** provenance Chains : à refaire en brique 08.

## Notation provisoire (grille C)

Les notes sont provisoires tant que le contrôle 9 et C-2 ne sont pas mesurés.

| Critère | Poids | Kyverno seul | Justification | Conforma + Kyverno | Justification |
|---|---|---|---|---|---|
| C-1 Couverture | 35 | 4 | 9/9 contrôles testés réussis, contrôle 9 non testé | 4 | Idem |
| C-2 Parité CLI / admission | 15 | 4 | Même politique et même moteur en CLI et à l'admission (à confirmer sur cluster) | 2 | Deux langages (Rego en CLI, CEL à l'admission) : parité par double maintenance |
| C-3 Bundles, referrers, TSA | 15 | 3 | Natifs ; doc d'`extractPayload` inexacte ; TSA non testée | 3 | Natifs mais non documentés ; TSA non testée |
| C-4 Maintenabilité | 15 | 3 | 88 lignes, un seul langage ; tests (`kyverno test`) à écrire | 2 | 77 lignes de Rego + 88 de CEL, deux langages ; tests à écrire |
| C-5 Santé | 10 | 4 | Sain, CNCF, plusieurs employeurs (Scorecard 7,8) | 2 | Limité par Conforma : 0.x, sponsor unique (6,6) |
| C-6 Performance | 10 | 5 | ≈ 0,5 s | 5 | ≈ 1 s |
| **Score /100** | | **76** | | **63** | |

**Lecture provisoire.** Kyverno seul dépasse nettement le seuil de 90 % de la référence (76 ≥ 57). La décision reste **suspendue** à la règle « 10/10 contrôles » : il faut tester le contrôle 9 (TSA) et la parité à l'admission en brique 08. Réserve : la bibliothèque Conforma (`slsa3`, `trusted_task` sur la vraie provenance Chains) n'a pas été mise à profit ici ; la réimplémenter en CEL sur la vraie provenance pourrait coûter plus que dans ce banc synthétique.
