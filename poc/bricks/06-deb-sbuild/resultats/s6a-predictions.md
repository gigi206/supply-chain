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

**Correction datée (12/11/2026, 08:56 UTC)** : l'heure « 08:56 UTC » du titre n'est pas exacte. Je ne l'avais tirée ni de `date -u` ni du journal. Ces prédictions sont commitées à 08:52:49 UTC (`d40dd3c`), avant le premier lancement du relevé à 08:54:07 UTC (`chrono.tsv`).

## Résultats (12/11/2026 ; journal [`s6a-releve.log`](s6a-releve.log))

**Trois passages, tous complets depuis zéro** (`chrono.tsv` : 08:54:07, 08:54:19, puis 08:54:30 à 08:54:37 UTC). Les deux premiers se sont arrêtés sur deux erreurs de mon script, sans effet de bord, puisque chaque passage efface `~/.cache/supply-chain-poc/06/s6a` au départ :
- à P3, le JSON de `syft cataloger list` a été lu avec une structure supposée, au lieu de `{default, selection, catalogers}` ;
- à P6, un f-string avec des guillemets échappés a été refusé par le Python de l'hôte.

Le journal archivé est celui du troisième passage.

| # | Résultat | Mesure |
|---|---|---|
| P1 | **Tenue** | `debian-binary`, `control.tar.xz`, `data.tar.xz` |
| P2 | **Tenue**, mesurée sur la vraie base `c142f6bc` (15 couches, 17 blobs revérifiés) | busybox `ar`, `tar`, `xz`, `unxz`, `gunzip`, `dpkg-deb` ; ni `zstd` ni `unzstd`. L'extraction ne demande pas de nouvelle image d'outils. |
| P3 | **Tenue** | `deb-archive-cataloger` : `directory`, sans `image` ; `go-module-binary-cataloger` et `dpkg-db-cataloger` : `directory` et `image` ; sélection par défaut `all` |
| P4 | **Tenue** (écart de forme : `stdlib@1.24.4`, sans « go ») | `data.tar` contient `usr/bin/sample-app` et deux fichiers de `usr/share/doc`. 3 PURL, tous `pkg:golang/` : le module principal (sans version), `github.com/go-chi/chi@v5.2.3#v5`, `stdlib@1.24.4`. Ni npm, ni deb, ni `distro=`. Code 0, rien sur la sortie d'erreur. |
| P5 | **Tenue en substance** | `pkg:deb/sample-app@1.0.0-1?arch=amd64`, sans espace de noms ni `distro=`, rien de Go |
| P6 | **En partie réfutée** | 140 correspondances, 140 identifiants. stdlib go1.24.4 : 135 (7 Critical, 76 High, 50 Medium, 2 Low). **chi v5.2.3 : 5** (GHSA-j6qf-3m9c-vwj3, GHSA-mqqf-5wvp-8fh8, GO-2026-5774, GO-2026-5775 et GO-2026-5777 ; corrigées entre 5.2.4 et 5.4.0) : prédit « aucune », donc réfuté. **Aucune KEV** : le champ `knownExploited` est présent sur le témoin log4j de G0 et absent ici. Aucun `MAL-`, aucun avertissement, distribution vide. |
| P7 | **Tenue, et plus nette que prédit** | Dossier vide : code 0, 0 PURL, 0 octet sur la sortie d'erreur. La source seule donne 4 PURL, la fusion source + vide 3, la fusion source + artefact 4. |

**Lecture de P7.** La fusion écarte tout PURL sans version, puisque `purlRe` de `scan-outil` exige `@version` : le module principal disparaît donc. Le seul apport de l'artefact est `stdlib@1.24.4`, qui porte 135 des 140 correspondances. Si l'extraction échouait, le SBOM du deb aurait 3 composants au lieu de 4, perdrait ces 135 correspondances, et aucune erreur ne le signalerait. Un plancher sur le total n'y voit rien ; il en faut un sur l'artefact seul.

**Conséquences pour le mode deb du scanner** (à préparer, rien d'écrit) :
- extraction par busybox dans `outils-scan` : `ar x`, puis `unxz` et `tar`. La forme exacte reste à mesurer dans un pod d'essai, la prise en charge de `-J` par le `tar` de busybox n'étant pas relevée ;
- scan `dir:` du seul `data.tar` extrait, puis fusion avec la source comme pour l'image. Le `.deb` comme fichier n'apporte qu'un PURL sans base de correspondance (P5) ;
- plancher : au moins un PURL `pkg:golang/` versionné dans le SBOM de l'artefact seul, dont `stdlib`, sinon refus en échec fermé ;
- `distro=` est inutile pour un binaire Go : la correspondance passe par `github:language:go`, `govulndb:language:go` et `nvd:cpe`.

**Constat pour la porte, conforme à l'ADR 0000 §4** : le contrôle 7 ne juge que les KEV sans VEX et les `MAL-`. Le deb le passerait donc avec 140 vulnérabilités, dont 7 Critical. Deux points ne sont pas mesurés :
- si `golang-1.24` 1.24.4-1 de l'instantané porte des correctifs rétroportés, ce qui rendrait une partie des correspondances de la stdlib fausses ;
- comment la voie image se compare sur la stdlib.
