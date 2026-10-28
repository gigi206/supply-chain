# Brique 13a : licences déclarées, REUSE et bundle de sources (partie locale)

Seuil (README, brique 13a) : 0 `NOASSERTION` ; 100 % d'expressions SPDX valides ; 0 violation ERROR ; bundle de sources GPL en referrer.

## Chaîne

1. **Extraction complète de la fermeture, sans réseau** : `go mod download` avec la fermeture Hermeto servie en `GOPROXY`. Il faut toute la fermeture, pas seulement les modules du build : une dépendance propre à Windows comme `mousetrap` n'est extraite que de cette façon, et sans elle sa licence reste inconnue.
2. **SBOM Syft avec licences**, sans réseau : cache de modules Go (`SYFT_GOLANG_SEARCH_LOCAL_MOD_CACHE_LICENSES`) et lockfiles npm.
3. **Verdict** : [`licences.py`](licences.py) avec la [politique](policy.json) et la liste SPDX 3.27.0 (paquet `spdx-license-list-data` du nixpkgs épinglé).
   - Expression retenue : une **curation revue** si elle existe (clé PURL normalisée, partagée avec la brique 07a), sinon les licences déclarées combinées par AND.
   - Validation des identifiants et des exceptions SPDX ; les `LicenseRef-` ne passent que s'ils sont autorisés.
   - Classement allow / warn / deny : OR retient la branche la plus favorable, AND la plus défavorable.
   - **ERROR** pour NOASSERTION, une expression invalide ou une licence absente de la politique.
4. **Obligations de sources** (GPL, LGPL, MPL…) : le fichier source de la dépendance (zip de module Go, archive npm) doit être dans la fermeture, sinon ERROR. Les fichiers trouvés sont attachés à l'artefact en **referrer** `application/vnd.supply-chain.source-bundle.v1` (annotation `retention=P10Y`).
5. **REUSE** sur nos dépôts : le dépôt et `poc/sample-app` portent chacun un `REUSE.toml` (Apache-2.0) et le texte de la licence.

La sortie est le prédicat `https://supply-chain.example/licences/v1`. La porte du banc C le lit (`violations.error`) et refuse dès qu'il y a une erreur (cas `c8-licence`).

La politique fournie vise une **application distribuée en binaire sous licence permissive** : la GPL y est refusée. Les paquets rpm/deb de logiciels GPL relèveront d'une autre politique, avec obligations de sources mais sans refus.

## Résultats ([`bench.sh`](bench.sh), journal : [`resultats/bench.log`](resultats/bench.log))

| Cas | Résultat |
|---|---|
| **oras v1.3.6** (23 modules Go) | **0 ERROR, 0 NOASSERTION, 0 invalide**, 4 avertissements |
| Négatif : même SBOM sans recherche de licences | 23 NOASSERTION → **refusé** |
| **sample-app** (Go + npm) | **0 ERROR, 0 NOASSERTION, 0 invalide** |
| GPL-3.0-or-later | ERROR (deny) |
| `MIT AND (Apache-2.0` | ERROR (expression invalide) |
| Composant sans licence + curation revue | OK (curation appliquée) |
| LGPL-2.1-only, source présente dans la fermeture | Avertissement ; **source attachée en referrer** à l'image (rétention P10Y) |
| LGPL-2.1-only, source absente | ERROR (obligation impossible à tenir) |
| REUSE sur sample-app | **Conforme** (REUSE 3.3, 10 fichiers sur 10) |
| REUSE sur le dépôt entier | **Conforme** (REUSE 3.3, 76 fichiers sur 76) |
| Négatif REUSE : fichier sous GPL-3.0-only sans texte de licence | **Non conforme** (« Missing licenses: GPL-3.0-only ») |

Tests unitaires ([`test_licences.py`](test_licences.py)) : 9 tests réussis. Ils couvrent la grammaire SPDX et la normalisation, les expressions invalides, NOASSERTION et curation, les PURL écrits autrement, OR et AND, les licences hors politique, les `LicenseRef`, les entrées non SPDX, les exclusions et les obligations de sources.

## Constats

- **Les 4 avertissements d'oras ne sont pas cosmétiques.** Trois viennent de fichiers de licence que Syft ne reconnaît pas (empreinte au lieu d'un identifiant). Pour `go.yaml.in/yaml/v4`, le fichier ignoré contient probablement la part MIT d'une licence double, que la déclaration « Apache-2.0 » omet. C'est le rôle de **ScanCode** (brique 13b) de trancher ces cas.
- `opencontainers/go-digest` est sous **Apache-2.0 AND CC-BY-SA-4.0** (licence de la documentation) : avertissement à faire valider par le référent juridique.
- La **curation** reste le dernier recours. Elle est versionnée (dépôt `ort-config`), porte une preuve (fichier LICENSE vérifié, hash `go.sum`) et passe par une revue.
- Le **dépôt `supply-chain`** est sous **Apache-2.0** (décision du propriétaire du 28/10/2026) et conforme REUSE 3.3 : `REUSE.toml` à la racine, texte dans `LICENSES/`, contrôle par `make reuse`.

## Reproduction

```bash
B03=<WORKDIR du banc 03> SPDX=<spdx-license-list-data>/json REG=localhost:5000 WORKDIR=/tmp/b13 ./bench.sh
```

Outils : Syft, reuse, Go ≥ 1.26.7, oras, crane. Aucun accès réseau.

## Reste à faire

- **Laptop** : tâche Tekton de confiance, prédicat signé par une clé dédiée ; rpm/deb : licences des métadonnées de distro normalisées en SPDX (`fedora-license-data`, DEP-5) et bundle SRPM ou `.dsc` en referrer (briques 05, 06 et 09).
- **2c** : ORT + ScanCode pour les licences « concluded » et la précision mesurée avec un référent juridique (brique 13b).
