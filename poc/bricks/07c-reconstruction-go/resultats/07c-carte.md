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
