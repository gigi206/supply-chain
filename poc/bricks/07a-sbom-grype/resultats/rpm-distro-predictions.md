# rpm de la 05 et `distro=` : prédictions (écrites le 20/11/2026 à 2026-11-20T18:57:48Z UTC, avant toute exécution)

**Question**, laissée ouverte le 10/11 (R1 à R6) et le 12/11 (deb de la 06) : syft, sur un `.rpm` isolé, sans `/etc/os-release`, émet-il `distro=` ? Et grype juge-t-il ce SBOM, avec et sans `--distro` ? La proposition **D14** (la porte refuse un SBOM de paquet sans `distro`, ou le job passe `--distro`) en dépend. Cette mesure l'instruit, elle ne la tranche pas : D14 reste une décision du propriétaire.

**Script** : [`rpm-distro.sh`](../rpm-distro.sh) (sha256 `6f1ae4353d9da2d0…`).
- Il tourne sur l'hôte seul, hors réseau (`unshare -rn`), avec syft 1.38.0 et grype 0.104.1 de mise, et la base du 04/11 importée en G0.
- Il n'écrit que dans `~/.cache/supply-chain-poc/07a/rpm-distro` (refusé s'il existe) et dans `resultats/rpm-distro.log` (refusé s'il existe). Rien dans le cluster, dans Zot ni dans les VM.
- **Entrées**, copiées et contrôlées par sha256 avant tout usage :
  - `sample-app-1.0.0-2.el9.x86_64.rpm`, construit par la plateforme dans la cascade M1b, sha256 `864d55f4…` (`m1b-construction-construction.log` de la 05) ;
  - trois rpm Rocky de la fermeture tirée de Zot : `openssl-libs-3.5.1-7.el9_7`, `zlib-1.2.11-40.el9` et `glibc-2.34-231.el9_7.10`, contrôlés contre l'arbre archivé `m1b-fermeture-essai-arbre.txt`.
- Pour chacun : `syft scan dir:` sur un dossier qui ne contient que lui, comme P5 de la 06 ; puis grype sur le SBOM, sans `--distro` et avec `-q` comme `politique/scanner.sh`, puis avec `--distro rocky:9.7`.
- **Hors portée** : le binaire Go de `sample-app`. Aucun outil d'extraction de rpm n'est sur l'hôte (`rpm2cpio` et `bsdtar` absents), et je n'en installe pas. Le cas du binaire Go est déjà mesuré sur le deb de la 06 (140 correspondances sans `distro=`).

## Prédictions

| # | Cas | Prédit | Confiance |
|---|---|---|---|
| RD1 | Entrées | Les 4 sha256 sont égaux aux valeurs archivées ; syft rend 0 sur les 4 | haute |
| RD2 | PURL des 4 SBOM | Un composant `rpm` par fichier. Aucun PURL ne porte `distro=`, comme pour le deb de la 06 | haute |
| RD3 | Espace de noms des PURL | Absent (`pkg:rpm/<nom>@…`) : sans `/etc/os-release`, syft n'a pas de distribution d'où le tirer | moyenne : le champ Vendor de l'en-tête rpm pourrait servir |
| RD4 | grype sans `--distro`, 3 rpm Rocky | 0 correspondance, code 0, aucune ligne sur la sortie d'erreur (`-q`). L'échec silencieux de R5 se retrouve sur de vrais paquets | haute |
| RD5 | grype `--distro rocky:9.7`, `openssl-libs` | Des correspondances dans l'espace `redhat:distro:redhat:9`, CVE-2026-9076 présente (elle affecte les versions `< 1:3.5.5-4.el9_8`). La correspondance passe par le rpm source (`openssl`) | moyenne : nom binaire `openssl-libs` contre nom source non vérifié |
| RD6 | grype `--distro rocky:9.7`, `zlib` et `glibc` | Au moins une correspondance chacun, dans le même espace | faible : contenu de la base pour ces deux versions non lu |
| RD7 | grype, `sample-app` | 0 correspondance, avec et sans `--distro` : la base n'a rien pour ce nom, et le binaire Go n'est pas catalogué dans le rpm non extrait | moyenne |
| RD8 | Tous | grype rend 0 dans les 8 appels | haute |

Si RD2 tient, la porte ne peut pas compter sur syft pour `distro=` dans un SBOM de rpm isolé. Il faut donc que D14 soit tranchée avant de scanner les rpm de la 05 dans la plateforme.

## Résultat (écrit le 20/11/2026 à 2026-11-20T18:58:47Z UTC)

Le script a tourné le 20/11/2026 de 18:57:55 à 18:58:05 UTC, au dépôt `8a7f1d76`, code 0. **RD1 à RD8 sont tenues.** Journal : [`rpm-distro.log`](rpm-distro.log).

| # | Mesuré | Verdict |
|---|---|---|
| RD1 | 4 sha256 égaux aux valeurs archivées ; syft rend 0 quatre fois, sans sortie d'erreur | tenue |
| RD2 | Un composant `library` de type rpm par fichier, sans `distro=`. syft ajoute un composant `file` sans PURL (le fichier rpm lui-même) | tenue (le composant `file` n'était pas prédit) |
| RD3 | `pkg:rpm/<nom>@<version>-<release>?arch=…&epoch=…&upstream=<src.rpm>`, sans espace de noms | tenue |
| RD4 | 0 correspondance pour les 3 rpm Rocky, code 0, aucune ligne sur la sortie d'erreur | tenue |
| RD5 | `openssl-libs` : 49 correspondances, toutes dans `redhat:distro:redhat:9`, CVE-2026-9076 présente. Le passage par le rpm source n'est pas relevé (le résumé ne lit pas `matchDetails`) | tenue, mécanisme non mesuré |
| RD6 | `zlib` : 1 (CVE-2026-27171) ; `glibc` : 19 ; même espace | tenue |
| RD7 | `sample-app` : 0 avec et sans `--distro` | tenue |
| RD8 | grype rend 0 dans les 8 appels | tenue |

**Lecture**
- Syft n'émet pas `distro=` sur un rpm isolé, pas plus que sur le deb isolé de la 06. **Sans `--distro`, grype ne trouve rien, en silence (code 0, `-q`), sur de vrais paquets Rocky** : l'échec silencieux de R5 (PURL synthétique) se retrouve sur de vrais paquets.
- Avec `--distro rocky:9.7`, les mêmes SBOM sont jugés sur les données de Red Hat 9, comme en R1.
- **Pour D14** : un SBOM de rpm produit par syft sur le fichier seul n'a jamais `distro=`. La première branche de D14 (la porte refuse un SBOM de paquet sans `distro`) refuserait donc tous les SBOM de rpm faits ainsi ; la seconde (le job passe `--distro`) suffit à les juger. D14 reste ta décision.
- **Non mesuré** : le binaire Go de `sample-app` dans le rpm (rien pour extraire le rpm sur l'hôte) ; un SBOM fait sur la racine de construction, qui a un `/etc/os-release` ; le scan d'un rpm dans la plateforme.
- Le dossier de travail (6,9 Mio : copies des quatre rpm, SBOM et sorties de grype, lus par aucun script) est effacé après ce résultat.

## Correction du 20/11/2026, écrite à 2026-11-20T19:03:57Z UTC (la lecture ci-dessus reste écrite telle quelle)

**La lecture de D14 était fausse.** Le conseiller l'a relevé.
- D14 dit : « la porte refuse un scan dont la `distro` est vide, ou le job passe `--distro` explicitement ». La `distro` en cause est le champ `distro` du résultat de grype, pas un qualificatif du PURL.
- Il est vide sans `--distro` (`{"name": ""}`) et vaut `rockylinux 9.7` avec. Les deux branches de D14 sont donc compatibles : un job qui passe `--distro` produit un scan dont la `distro` n'est pas vide.
- « Refuserait tous les SBOM de rpm » est donc faux.
- « `--distro` suffit à les juger » est faux pour `sample-app` : 0 correspondance dans les deux cas. Le SBOM n'a que 2 composants, le rpm et le fichier, et aucun module Go.
  - Un scan du rpm seul serait donc vide pour l'application.
  - À comparer : le binaire Go extrait du deb de la 06 donnait 140 correspondances (12/11).
- D14 reste ta décision. Cette mesure ne l'oriente pas.
