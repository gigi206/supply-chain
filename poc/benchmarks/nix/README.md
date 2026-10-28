# B : Nix comme moteur de build (Go et OCI)

**But** : noter Nix sur la grille B de l'ADR 0000, face à la référence Hermeto + BuildKit (démon éphémère), sur `poc/sample-app`.

## Protocole (≤ 3 jours)

**Référence (Hermeto + BuildKit)** :
1. Prefetch Hermeto (gomod, npm), puis fermeture archivée (OCI, fichier par fichier) et SBOM Hermeto.
2. Build du binaire Go (`-trimpath`, `CGO_ENABLED=0`, `GOFLAGS=-mod=vendor`, `GOTOOLCHAIN=local`) et de l'image (BuildKit, `SOURCE_DATE_EPOCH`, `rewrite-timestamp`), sans réseau.

**Candidat (Nix)** :
1. `flake.nix` épinglé (nixpkgs par révision) : `buildGoModule` (`vendorHash`), `buildNpmPackage` (`npmDepsHash`), image `dockerTools.buildLayeredImage` ou `nix2container`.
2. `nix build` puis `nix build --rebuild` (vérification intégrée), sur 2 hôtes et à ≥ 1 h d'écart (B-1).
3. Archive de la fermeture : `nix copy --to file://…` ou `nix-store --export`, puis rebuild **egress bloqué** à partir de cette seule archive (B-2). Mesurer la taille et la déduplication entre 2 versions de sample-app (B-3).
4. SBOM : sbomnix et Syft sur l'image. Mesurer le taux de composants corrélés par Grype et DT (B-4 ; attention aux `pkg:nix`).
5. Dans une tâche Tekton : sandbox Nix en pod **userns** (sans privilège), sujets et `resolvedDependencies` dans la provenance Chains (B-5).
6. Mesurer le temps passé et les lignes de configuration (B-6).

## Exécutable dans l'environnement de développement actuel

Étapes 1 à 4 du candidat sur un seul hôte : Nix 2.34 et cache.nixos.org sont disponibles. Le second hôte (B-1) et Tekton (B-5) demandent l'infra du PoC.
