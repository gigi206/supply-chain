# Brique 07c : carte

## Ouverture (note de 2026-11-24T13:11:58Z)

Décision du propriétaire, verbatim : « Chantier à part ». Périmètre et accords : [README](../README.md). Départ du compte d'heures : 2026-11-24T13:11:58Z.

## Étape 1 : toolchain (prédiction, note de 2026-11-24T13:12:15Z)

[`telecharger.sh`](../telecharger.sh), journal `telecharger.log` : module absent avant ; 71 800 213 octets ; `ziphash` = `h1:KyINmJ/…` relevé avant l'accord et relu maintenant ; `go version go1.26.11 linux/amd64` ; 1.26.10 intacte. **Bilan attendu : 6 cas, 0 écart.**

**Étape 1, résultat** ([journal](telecharger.log), 13:12:18 à 13:12:27 UTC) : **6 cas, 0 écart**, conforme. Module de 71 800 213 octets, `ziphash` = `h1:KyINmJ/…` (relevé avant l'accord et relu), `go version go1.26.11 linux/amd64`, 1.26.10 intacte (`h1:5VAGHlY8…`).

## Étape 2 : banc de la 04 sur l'hôte (prédiction, note de 2026-11-24T13:13:37Z)

[`banc-hote.sh`](../banc-hote.sh), journal `banc-hote.log`, BuildKit du nixpkgs rootless, `bench.sh` de la 04 inchangé, entrées de la 03 :
- entrées de la 03 : binaire de référence `e3749c68…` ;
- **témoin Go 1.26.10** : image `3a7ca1b1…`, `bench.sh` sans KO ;
- **Go 1.26.11** : image identique sur deux constructions, digest différent de `3a7ca1b1` (valeur non prédite : elle devient la prédiction des étapes suivantes, ligne `DIGEST PRÉDIT|`) ; seul KO de `bench.sh` : son étape 3 (binaire comparé à celui de la 03, compilé en 1.26.10), attendu par construction ; binaire hors BuildKit en 1.26.11, sans réseau = binaire de l'image ;
- **scan** (Grype hors ligne, base du 24/11, sur l'image et non sur le SBOM fusionné de la plateforme) : témoin à 6 entrées dont `GO-2026-6859` ; 1.26.11 à 5 entrées, toutes sur chi, 0 stdlib ;
- **bilan attendu : 11 cas, 0 écart.**

**Étape 2, résultat** ([journal](banc-hote.log), 13:13:42 à 13:17:31 UTC ; note de 2026-11-24T13:17:56Z) : **11 cas, 1 écart**, écart de **prédiction** sur le témoin.
- Témoin Go 1.26.10 : l'hôte reproduit toujours `3a7ca1b1…` (deux constructions, binaire `e3749c68…` = celui de la 03, négatifs tenus).
- **Go 1.26.11 : image `sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7`**, identique sur deux constructions sans cache depuis deux chemins ; binaire `56f3cd7d…` (6 197 374 octets, go1.26.11, chi v5.2.3), identique à la compilation hors BuildKit sans réseau ; négatifs tenus ; seul KO de `bench.sh` : son étape 3, attendu. Image de build BuildKit `06359cd6…` (sur l'hôte seulement ; le cluster utilise l'image de la voie D, assemblée sans BuildKit).
- **Scan, écart** : Grype lancé directement sur l'image témoin donne **15** entrées, pas 6 : les 6 du scan de la plateforme plus 9 correspondances NVD par CPE (`cpe:2.3:a:golang:go:1.26.10`, `CVE-2026-97033` à `97039`, `97043`, `97054`, toutes corrigées en 1.26.11 et 1.27.4). Ma prédiction reprenait le compte du scan de la plateforme (SBOM fusionné, `scan-outil`), qui ne les fait pas ressortir ; la cause de cette différence n'est pas mesurée ici. **Image 1.26.11 : 5 entrées, toutes sur chi, 0 stdlib**, conforme : la reconstruction retire les 10 entrées stdlib du scan direct.
- **Prédiction pour les étapes suivantes** : l'image construite par la pipeline de la plateforme en Go 1.26.11 sur les mêmes entrées devrait être `f5e6bcb0…` (la voie A de la 08 et la 04 donnaient le même digest, `3a7ca1b1`).

**Heures** : 13:11:04 à 13:17:56 UTC (0 h 06 min 52 s) ; **total de la 07c : 0 h 06 min 52 s** pour 10 h estimées.
