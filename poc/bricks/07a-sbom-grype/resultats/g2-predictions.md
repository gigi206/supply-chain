# G2 : prédictions (écrites le 04/11/2026 à 19:37 UTC, avant toute exécution)

Image d'outils du scanner `plateforme/outils-scan`, construite depuis la base cosign v3.1.4-dev (busybox) que J5 a déjà copiée dans Zot (`amont/sigstore/cosign/cosign@c142f6bc…`, présente, relu en lecture anonyme à 19:37 UTC).

## Décision ajoutée : D8, outil du prédicat

**Constat** : l'image n'a pas de python, alors que `sbom_merge.py` et `scan_predicate.py` en exigent un.

**Options**
- (a) les réécrire en Go, sans dépendance, dans `outil/` ;
- (b) jq statique, mais ce projet n'a pas de verdict dans la doc 04 ;
- (c) une image Python, qui ajouterait une base de plus.

**Recommandation : (a).**

**Mesuré à sec le 04/11/2026, entre 19:30 et 19:37 UTC (bornes relevées : push de 19:30, date de 19:37), sur l'hôte et sur les fichiers de G0** :
- `scan-outil fusion` et `scan-outil predicat` rendent un JSON **identique en contenu** aux deux scripts Python, sur la fusion (avec et sans libellés) et sur les prédicats `ok` et `kev`. Les octets diffèrent : Go trie les clés et n'échappe pas l'Unicode.
- Le binaire est statique, `3d442df7…`, et **identique quand on reconstruit à cache vide** (Go 1.24.7 de mise, `-trimpath`, `CGO_ENABLED=0`).

## Étapes et prédictions (accord du propriétaire avant `g2_telecharger`, qui télécharge, et avant `g2_image`, qui pousse dans Zot)

**g2_telecharger** : 8 fichiers dans `~/.cache/supply-chain-poc/07a/telechargements` (environ 60 Mo). Pour Grype 0.104.1 et pour Syft 1.38.0 : l'archive `linux_amd64`, `checksums.txt`, `.sig` et `.pem`. Ces releases de 2025 ont une paire `.sig` et `.pem`, pas de `.sigstore.json` (relevé dans la liste des assets entre 19:30 et 19:37 UTC).

**g2_verifier**
- Les empreintes des archives sont celles de `mise.lock` (`2cb820b6…` et `bc664deb…`), et elles figurent dans `checksums.txt`.
- La signature sans clé de `checksums.txt` se vérifie avec l'émetteur `https://token.actions.githubusercontent.com` et une identité du workflow `release.yaml` du dépôt anchore. L'identité exacte (branche ou tag) sera lue dans le certificat, pas supposée.
- Contre-épreuve : l'identité d'un autre dépôt est refusée.
- **Incertain** :
  - le `.pem` est peut-être en base64 (goreleaser) ; le script gère les deux formes ;
  - la vérification consulte le Sigstore public, en vérification seulement, comme `tsa.sh` pour cosign. Rien n'y est signé.

**g2_image**
- grype et syft de l'image sont identiques à ceux de mise : les binaires viennent des mêmes archives.
- oras est celui de J5 ; `scan-outil` est `3d442df7…`.
- La couche est reproductible : tri, date 0, propriétaire 0.
- Le second assemblage donne le même digest, relu en lecture anonyme. Ce digest sera épinglé dans le script après le premier passage.
- La taille dépend des binaires, de l'ordre de 150 Mo.

## Effets à connaître

- Un téléchargement d'environ 60 Mo depuis GitHub.
- Un push dans Zot (`plateforme/outils-scan`, avec un tag) par `poc-ecriture`.
- Rien dans le cluster ni dans `sc-stockage`.
- **Décision du propriétaire (04/11/2026, après 19:37 UTC, « Oui ») : D8 (a) retenue, G2 appliqué.**

## Résultat (04/11/2026, 19:44:05 à 19:44:31 UTC) : conforme

Journaux : [`g2_telecharger.log`](g2_telecharger.log), [`g2_verifier.log`](g2_verifier.log) et [`g2_image.log`](g2_image.log).

**g2_telecharger** : 8 fichiers téléchargés, soit 27,7 Mo pour Grype et 23,3 Mo pour Syft. C'est moins que les 60 Mo prédits, sans conséquence.

**g2_verifier**
- Les empreintes sont celles de `mise.lock` et de `checksums.txt`.
- La signature sans clé est vérifiée pour les deux releases. L'identité, lue dans le certificat, est `https://github.com/anchore/<dépôt>/.github/workflows/release.yaml@refs/heads/main` : le workflow de release tourne sur `main`, pas sur le tag.
- L'identité d'un autre dépôt est refusée.
- Le `.pem` était bien en base64 : le cas « incertain » était réel, et le script l'a traité.

**g2_image**
- Les binaires sont `c833472c…` (grype), `6d380157…` (syft), `2be7e2b6…` (oras) et `3d442df7…` (scan-outil) ; grype et syft sont identiques à ceux de mise.
- La couche fait 162,6 Mo (`5f2c05ab…`), contre environ 150 Mo prédits.
- L'image est `plateforme/outils-scan@sha256:7eb4f26e…`. **Le second assemblage donne le même digest**, relu en lecture anonyme.
- Ce digest est désormais épinglé dans `plateforme.sh` (`OUTILS_SCAN_DIGEST`).
