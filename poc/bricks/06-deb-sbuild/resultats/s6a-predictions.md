# Brique 06, S6a, relevé 1 : prédictions (12/11/2026, 08:56 UTC, avant toute mesure)

Décision du propriétaire (12/11/2026, 08:50:32 UTC) : « 1 ok / 2 ok / 3 ok / 4 ok ». Les quatre recommandations de la carte (README, additif de 08:39 UTC) sont retenues :
- **ordre (c)** : avant S5b, seulement ce qui survit au rejeu ; le CronJob du deb et le push de la VSA viennent après S5b et après le relevé du 21/11 ;
- **contrôle 7** : mode deb du scanner, sous réserve de ce relevé ;
- **contrôle 6** : chroot reconstruit dans `sc-replay` ;
- **relevé 1 de S6a** autorisé : sur l'hôte, hors réseau, écritures seulement sous `~/.cache/supply-chain-poc/06/s6a` et dans `resultats/`.

Script : [`s6a.sh`](../s6a.sh), étape `releve`. Journal : `s6a-releve.log`.

## Entrées, relevées avant les prédictions (lecture seule)

- **deb** : `$W/s3-06/build-1/sample-app_1.0.0-1_amd64.deb`, sha256 `0b489d43…`, celui de `builds/sample-app-deb@039949f9`.
- **Outils** : syft 1.38.0 et grype 0.104.1 de mise, les mêmes binaires que l'image `outils-scan` (contrôle `attendu` de G2).
- **Base** : celle de G0, construite le 04/11/2026 à 06:20:59 UTC, schéma v6.1.10, sous `~/.cache/supply-chain-poc/07a/g0/dbcache`. Elle a plus de 3 jours, mais le relevé ne juge rien.
- **Image de base d'`outils-scan`** : `amont/sigstore/cosign/cosign@sha256:c142f6bc…` (`COSIGN_BASE` de `plateforme.sh`), dont un layout local existe sous `~/.cache/supply-chain-poc/08/telechargements/oci/`. Ses couches sont listées, sans rien exécuter.
- **Code** : `go.mod` de sample-app requiert seulement `github.com/go-chi/chi/v5 v5.2.3`. Le deb est construit avec `golang-1.24-go` 1.24.4-1 de l'instantané.

## Prédictions

- **P1, format.** `ar t` donne `debian-binary`, `control.tar.xz` et `data.tar.xz` : xz est la compression par défaut de dpkg-deb dans trixie. Confiance moyenne.
- **P2, outils de l'image.** La racine de `c142f6bc` contient busybox avec les applets `ar`, `tar` et `unxz` (ou `xz`), mais aucun outil zstd. Si P1 tient, l'extraction ne demande pas de nouvelle image. Confiance moyenne : la liste des applets n'est connue que par la racine d'`outils-horodatage` extraite en G5, sans preuve que la base soit la même.
- **P3, catalogueurs.** Dans `syft cataloger list` :
  - `go-module-binary-cataloger` porte l'étiquette `directory` ;
  - `deb-archive-cataloger` porte `directory` mais pas `image`, comme relevé en S4d2.

  Confiance moyenne.
- **P4, SBOM de l'artefact seul** (`syft dir:` sur `data.tar` extrait) : au moins 3 composants avec PURL, tous `pkg:golang/` :
  - `stdlib@go1.24.4` ;
  - `github.com/go-chi/chi/v5@v5.2.3` ;
  - le module principal.

  Il n'y a ni PURL npm (les fichiers web sont livrés construits, sans `package.json`) ni PURL deb. Aucun PURL ne porte `distro=`. Confiance moyenne : un binaire sans buildinfo lisible ferait tomber le compte à 0.
- **P5, le deb comme fichier** (`syft dir:` sur un dossier qui ne contient que le `.deb`) : un composant `pkg:deb/…/sample-app@1.0.0-1?arch=amd64`, sans `distro=`, et rien de Go (syft ne descend pas dans l'archive). Confiance faible.
- **P6, grype sur le SBOM de P4** : au moins une vulnérabilité sur `stdlib` go1.24.4, publiée après juin 2025. Aucune sur chi v5.2.3. Aucune KEV. Aucun avertissement de distribution qui change le résultat : la correspondance Go ne dépend pas de `distro=`. Confiance moyenne pour la stdlib, faible pour le nombre exact, qui n'est pas prédit.
- **P7, le vide masqué** (témoin de la carte, constat 3). `syft dir:` sur un dossier vide, avec `-q` : code 0, 0 PURL, rien sur la sortie d'erreur. Fusionné au SBOM de la source, le compte total reste celui de la source. Un plancher sur l'artefact seul est donc nécessaire. Confiance haute.

**Rien d'autre** : aucune connexion (`unshare -rn`), rien dans le cluster ni dans Zot, rien installé.
