# Brique 07a : SBOM + Grype hors ligne et porte KEV (partie locale)

Seuil (README, brique 07a) : Syft + Grype avec la base officielle archivée, **sans egress** ; la porte bloque un cas KEV de test.

## Chaîne

| Étape | Outil | Réseau |
|---|---|---|
| Archivage quotidien de la base officielle : `latest.json` et archive téléchargés, **empreinte vérifiée**, puis poussés dans Zot sous `vulndb/grype:<date>` | [`fetch-db.sh`](fetch-db.sh) | Oui (grype.anchore.io), une fois par jour |
| Restauration de la base **par digest**, import dans un cache vierge | `oras pull`, `grype db import` | Non (`unshare -rn`) |
| SBOM de fermeture : referrer CycloneDX de la fermeture Hermeto (brique 03) | `oras discover` / `pull` | Non |
| SBOM de l'artefact : Syft sur le binaire | `syft` | Non |
| Fusion sur une **clé PURL normalisée** (Hermeto écrit `…/chi/v5@v5.2.3`, Syft `…/chi@v5.2.3#v5`) ; composants sans version écartés | [`sbom_merge.py`](sbom_merge.py) | Non |
| Scan, puis prédicat `https://supply-chain.example/scan/v1` avec KEV, EPSS, alias, correctifs et **référence de la base utilisée** | `grype`, [`scan_predicate.py`](scan_predicate.py) | Non |
| Porte : image de test signée et attestée, évaluée avec les **politiques du banc C** | cosign, Conforma, Kyverno | Non (registre local) |

## Résultats ([`bench.sh`](bench.sh), journal : [`resultats/bench.log`](resultats/bench.log))

Syft 1.38.0 et Grype 0.104.1 viennent du nixpkgs 25.11 épinglé (binaires de cache.nixos.org, signatures vérifiées par Nix). La base Grype est en v6.1.10, construite le 28/10/2026 : 196 Mo compressée, 3,2 Go importée.

| Mesure | Résultat |
|---|---|
| Import de la base hors réseau | 167 s |
| SBOM fusionné de sample-app | chi v5.2.3, stdlib Go 1.26.10, marked 16.4.1, plus les modules du projet |
| Scan de sample-app (sans réseau) | < 1 s ; **5 vulnérabilités réelles sur chi v5.2.3** (2 GHSA Medium, 3 GO-2026 non notées), **0 KEV** |
| Scan du cas KEV (même SBOM + log4j-core 2.14.1) | ≈ 1 s ; 13 vulnérabilités dont **2 KEV** (CVE-2021-44228, CVE-2021-45046) |
| **Porte, cas ok** | **PASS** (Conforma et Kyverno) |
| **Porte, cas KEV** | **FAIL** dans les deux moteurs : « KEV sans VEX valide » (GHSA-jfh8-c2jp-5v3q, GHSA-7rjr-3q55-vv33) |

La donnée KEV vient de la base Grype v6 elle-même (`knownExploited`, catalogue CISA). Aucun flux externe n'est consulté au moment du scan.

**Rejeu sur le laptop (29/10/2026)** ([`resultats/bench-laptop.log`](resultats/bench-laptop.log)) : base du 29/10 (v6.1.10) importée hors réseau en **71 s** ; mêmes résultats que dans le cloud, soit 5 vulnérabilités et 0 KEV pour sample-app, 13 dont 2 KEV pour le cas log4j, et une porte PASS / FAIL dans les deux moteurs.

## Constats

- **Import coûteux** (167 s, 3,2 Go) : la plateforme importera chaque base **une fois**, dans une tâche dédiée, vers un volume en lecture seule indexé par le digest de l'archive. Les tâches de scan le monteront sans le modifier.
- **PURL divergents entre outils** pour les modules Go majeurs (≥ v2). C'est une entrée directe du **test négatif sur la correspondance des PURL** (VEX, brique 07b) : un VEX écrit sur un format doit s'appliquer à l'autre.
- Le **PURL du module principal** vient du remote `origin` du dépôt (ici un chemin local) ; sur la plateforme, ce sera l'URL Forgejo.
- **Séparation des clés** : pour rester comparable au banc C, le scan est signé ici avec la clé « chains ». Sur la plateforme, il le sera avec une **clé de scanner dédiée**, vérifiée comme la VSA (ADR 0003 ; constat de sécurité du banc C).
- sample-app a des vulnérabilités réelles mais non KEV sur chi v5.2.3 : la porte les laisse passer (la politique ne bloque que les KEV sans VEX et les paquets malveillants). Elles entreront dans le **score** (brique 07b), et Renovate proposera la montée de version.

## Reproduction

```bash
ORAS_OPTS=--plain-http REG=localhost:5000 WORKDIR=/tmp/db ./fetch-db.sh   # imprime DB_REF
DB_REF=… CLOSURE_REF=localhost:5000/deps/sample-app@sha256:… APP_BIN=…/sample-app \
  REG=localhost:5000 WORKDIR=/tmp/b07 ./bench.sh
```

`CLOSURE_REF` et `APP_BIN` viennent du banc de la brique 03.

## Reste à faire sur le laptop

- Tâches Tekton : import quotidien de la base (CronJob), scan dans une tâche de confiance, prédicat signé par la clé du scanner (brique 08).
- Scan des images et des rpm/deb (qualificatif `distro=` des PURL), puis Grype comme scanner unique sur EL, ce qui reste à documenter (2b-2).
