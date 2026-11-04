# G0 : prédictions (écrites le 04/11/2026 à 18:37 UTC, avant toute exécution)

Étape [`plateforme.sh g0`](../plateforme.sh), sur l'hôte seul, dans `~/.cache/supply-chain-poc/07a`. Rien n'est écrit dans Zot, dans Forgejo ni dans le cluster.

## Base

- `latest.json` du jour : schéma `v6.1.10`, comme au relevé de 18:22 UTC. L'archive téléchargée a l'empreinte qu'il annonce.
- Signature : ni `latest.json` ni l'archive n'en ont aux chemins essayés. Le relevé documentaire (documentation de Grype, `grype db` en 0.104.1) n'indique aucune signature de la base, seulement l'empreinte. **Incertain** : si une signature existe, sa vérification devient une exigence de G1.
- Import hors réseau (`unshare -rn`) par Grype 0.104.1 (construit le 24/11/2025, D5 a) : il réussit, le schéma est compatible. Durée de l'ordre de 70 s, comme le 29/10.

## SBOM de D1 (a)

- Source lue anonymement dans Forgejo au commit `6391fd43…`, la tête de `main` relevée à 18:31 UTC. Le hash du commit est vérifié par git.
- Image lue par digest dans Zot : `builds/sample-app@sha256:3a7ca1b1…`.
- **Image (Syft)** : le binaire Go seul, avec `github.com/go-chi/chi/v5@v5.2.3` et `stdlib@1.26.10`. Le module principal apparaît sans version utilisable (`(devel)`, à cause de `-buildvcs=false`). **Pas de `marked`.**
- **Source (Syft)** : `go.mod` et `go.sum` (chi v5.2.3), et le fichier de verrou npm du web avec `marked@16.4.1`. **Incertain** : des dépendances de développement du fichier de verrou peuvent s'ajouter, ce qui ferait plus de composants qu'au banc.
- **Fusion** : on retrouve au moins chi v5.2.3, stdlib 1.26.10 et marked 16.4.1, soit les dépendances réelles du banc du 29/10. Le banc comptait 5 PURL, dont 2 propres au projet ; leur forme change ici (pas de chemin local).

## Scan hors réseau

- sample-app (SBOM fusionné) : **0 KEV**. Les vulnérabilités sur chi v5.2.3 du banc (5 au 29/10) reviennent ; leur nombre peut différer avec une base plus récente, il sera relevé.
- Cas KEV (même SBOM plus `log4j-core 2.14.1`) : au moins 2 KEV (CVE-2021-44228 et CVE-2021-45046), comme au banc.

## Résultat (04/11/2026, 18:39 à 18:42 UTC) : conforme

Journaux : [`g0.log`](g0.log) et [`g0-premier-passage.log`](g0-premier-passage.log).

**Premier passage : un KO, dû au contrôle et non au résultat.** Le contrôle attendait chi sous la forme de PURL de Hermeto (`…/chi/v5@v5.2.3`). Or les deux SBOM viennent désormais de Syft, qui écrit `…/chi@v5.2.3#v5`, et chi était bien présent. Le contrôle a été corrigé, puis le passage rejoué.

**Base**
- Schéma `v6.1.10`, construite le 04/11/2026 à 06:20:59 UTC. L'empreinte de l'archive de 198,7 Mo est conforme.
- **Aucune signature** : les cinq chemins essayés répondent 404. `latest.json` ne contient que `built`, `checksum`, `path`, `schemaVersion` et `status`. G1 ne peut donc vérifier que l'empreinte, sur TLS.
- Import hors réseau par Grype 0.104.1 en 74 s, puis 75 s au second passage. La base importée occupe 3 222 Mo.

**SBOM**
- Source au commit `6391fd43…` : `git fsck` passe. Les fichiers de verrou sont `go.mod`, `go.sum` et `web/package-lock.json`. **Aucune dépendance de développement en plus** : la source donne `marked@16.4.1` et `sample-app-web@1.0.0`.
- Image `3a7ca1b1…` lue par digest : chi v5.2.3, `stdlib@1.26.10` et le module principal sans version. **Pas de `marked`**, comme prédit.
- La fusion donne 4 PURL versionnés : chi, stdlib, marked et sample-app-web. Ce sont les dépendances réelles du banc, sans le chemin local du module principal.

**Scans**
- sample-app : **5 vulnérabilités, 0 KEV**. Ce sont les mêmes identifiants sur chi qu'au banc (2 GHSA Medium, 3 GO-2026), alors que la base est plus récente de 6 jours.
- Cas KEV : 13 vulnérabilités, dont **2 KEV** (CVE-2021-44228 et CVE-2021-45046), comme au banc.

**Stabilité entre les deux passages**
- Le SBOM fusionné est identique (`dba7b4fe…`).
- Les SBOM de Syft et les prédicats diffèrent seulement par leurs champs datés (numéro de série, `scannedAt`).
