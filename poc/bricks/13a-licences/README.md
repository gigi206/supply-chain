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

## Rejeu sur le laptop (29/10/2026)

Journal : [`resultats/bench-laptop.log`](resultats/bench-laptop.log). **Sortie identique au cloud** (7 contrôles sur 7), à un détail près : le digest de l'image de test régénérée à chaque passage.

**Constat : le SBOM de Syft dépend de l'hôte.** Le premier passage a trouvé 4 composants pour sample-app, dont un `NOASSERTION` (ERROR), contre 3 dans le cloud. Quand un `go` est dans le `PATH`, Syft 1.38 analyse les sources (métadonnées `go-source-entry`) et ajoute le **module principal** `example.com/supply-chain/sample-app`, sans version ni licence. Sans `go` dans le `PATH`, il ne l'ajoute pas. Ni le cache de modules ni le réseau n'y sont pour rien (vérifié avec un cache vide et sans réseau). Correctif du banc : Syft est lancé avec un `PATH` réduit à son seul dossier. Sur la plateforme, la tâche de scan tournera dans une image épinglée par digest, sans toolchain. La licence du module principal (le produit lui-même) relève de REUSE, pas du SBOM des dépendances.

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

## Volet rpm/deb, ouvert le 12/11/2026 (« Oui, ouvre-le », reçu après le `date -u` de 19:34:52 UTC)

Premier pas préparé à sec, **NON LANCÉ** (accord nommé attendu) : étape `deb` de [`paquets.sh`](paquets.sh), sur l'hôte, sans réseau, ni
cluster, ni Zot, ni VM. Le deb de S3 de la 06 (sha256 épinglé) est lu par [`paquets.py`](paquets.py) sans rien extraire ni exécuter ; son
copyright DEP-5 devient un SBOM CycloneDX jugé par `licences.py`, avec la même politique ; quatre témoins négatifs doivent être refusés.
Banc hors réseau : neuf cas au code attendu ([journal](resultats/paquets-essai-local.log)). Protocole, prédictions P1 à P5 et limites :
[`resultats/paquets-predictions.md`](resultats/paquets-predictions.md). Le rpm (après S1 de la 05), le `.dsc` et le SRPM en referrer
(après S5b) et la tâche signée suivent.

**Premier passage de `deb`, le 12/11/2026 de 19:43:12 à 19:43:13 UTC (« Oui, lance deb »)** : code 0, P1 à P5 tenues ([journal](resultats/paquets-deb.log),
[résultats](resultats/paquets-predictions.md)). Licence déclarée du deb de la 06 : `Apache-2.0 AND MIT AND (MIT AND BSD-3-Clause)`, 0 erreur,
0 NOASSERTION, 0 invalide ; copyright du deb identique à celui du dépôt ; quatre témoins refusés au motif attendu.

**Étape `modules` ajoutée à sec, NON LANCÉE** (après « continue ») : rapproche les dépendances compilées dans le binaire Go du deb (informations
de build lues en mémoire, binaire jamais exécuté) des paragraphes `Files` du copyright ; bibliothèque standard de Go en écart ; témoin
sans le paragraphe de `chi`. Banc hors réseau tenu, lecture identique à `go version -m` ([journal](resultats/paquets-modules-essai-local.log)).
Prédictions M1 à M7 : [`resultats/paquets-predictions.md`](resultats/paquets-predictions.md).

**Passage de `modules`, le 12/11/2026 de 19:53:09 à 19:53:11 UTC (« Oui, lance modules »)** : code 0, M1 à M7 tenues ([journal](resultats/paquets-modules.log),
[résultats](resultats/paquets-predictions.md)). Binaire compilé avec go1.24.4 ; seule dépendance, `chi` v5.2.3, couverte par son paragraphe MIT ;
témoin refusé. Écart ouvert, à décider : la bibliothèque standard de Go est compilée sans être déclarée dans le paquet (`Built-Using` absent).

**Étape `stdlib` ajoutée à sec, NON LANCÉE** (décision « Axe 3, puis 1+2 ») : la bibliothèque standard de Go devient un second composant du
prédicat de licences, avec la licence que Debian déclare pour `golang-1.24-src` 1.24.4-1 (paquet de la fermeture de S3 de la 06, sha256 épinglé,
recoupé avec le verrou et le buildinfo) ; le deb n'est pas modifié. Banc hors réseau tenu ([journal](resultats/paquets-stdlib-essai-local.log)).
Prédictions S1 à S6 : [`resultats/paquets-predictions.md`](resultats/paquets-predictions.md). Axes 1 et 2 (`Static-Built-Using`, notice de Go
dans le paquet) : une seule révision du paquet, après S5b.

**Passage de `stdlib`, le 12/11/2026 à 20:05:09 UTC (« Oui, lance stdlib »)** : code 1, `bilan : KO`, comme prédit (S1 à S4 et S6 tenues, S5 en partie)
([journal](resultats/paquets-stdlib.log), [résultats](resultats/paquets-predictions.md)). Le copyright de Debian pour `golang-1.24-src` nomme la licence du
projet « Go », hors SPDX, avec quatre autres noms hors SPDX et `X11` hors politique : la bibliothèque standard n'est pas déclarable telle quelle. Suite à
décider ; le deb n'est pas modifié.

**Traduction du nom « Go » préparée à sec, NON APPLIQUÉE** (« Oui, prépare-la ») : [`traductions-dep5.json`](traductions-dep5.json), traduction par nom
dans `paquets.py` (pas une curation de `licences.py`, qui remplacerait toute l'expression), liée au sha256 du texte de la licence et appliquée seulement
après revue du propriétaire. Le texte « Go » de Debian est celui de `BSD-3-Clause` plus une concession de brevets de Google, qui resterait hors de
l'expression ([détail](resultats/paquets-predictions.md)).

**Relance de `stdlib`, le 12/11/2026 à 20:13:36 UTC (« Oui, relance stdlib »)** : code 1, T1 à T3 tenues ([journal](resultats/paquets-stdlib.log), premier passage
[conservé](resultats/paquets-stdlib-premier-passage.log)). « Go » traduit en `BSD-3-Clause` après revue ; restent quatre noms hors SPDX (`FreeBSD`, `MPEG`,
`noderivs`, `BSD-3-clause-svgpan`) et `X11` hors politique. Suite à décider.

**Étape `noms` ajoutée à sec, NON LANCÉE** (étude, « Oui, prépare-la ») : pour les cinq noms restants, dit si leurs paragraphes portent sur du code lié
dans `sample-app` (noms de fonctions qualifiés cherchés dans le binaire ; `cmd`, `testdata` et `debian` classés par les règles de `go build`) et compare
leurs textes aux textes SPDX candidats ; aucun verdict. Banc hors réseau tenu ([journal](resultats/paquets-noms-essai-local.log)) ; prédictions N1 à N6
([détail](resultats/paquets-predictions.md)).

**Passage de `noms`, le 12/11/2026 de 20:23:00 à 20:23:02 UTC (« Oui, lance noms »)** : code 0 ([journal](resultats/paquets-noms.log), [résultats](resultats/paquets-predictions.md)).
`FreeBSD`, `MPEG`, `noderivs` et `BSD-3-clause-svgpan` ne portent sur aucun code lié ; **`X11` si** : son paragraphe couvre aussi des fichiers de `src/runtime/`
(N5 non tenue), et son texte est, en mots normalisés, celui de `MIT` (0,979), pas celui de `X11` de SPDX (0,837). Décisions possibles : traduction revue
`X11` -> `MIT`, règle qui écarte les paragraphes non liés.

**Traduction `X11` -> `MIT` préparée, NON APPLIQUÉE** (« Oui, prépare-les ») : seconde entrée de [`traductions-dep5.json`](traductions-dep5.json), liée au texte
(`75fce626…`), en attente de revue. La règle qui écarterait les paragraphes non liés n'est pas préparée ce soir.

*Additif du 12/11/2026* : traduction `X11` -> `MIT` revue par le propriétaire (« Oui, je valide », inscrite à 20:33:23 UTC). **Étape `lies`
préparée à sec, NON LANCÉE** : `stdlib` avec la règle des paragraphes non liés (`paquets.py --lies`) ; un paragraphe n'est écarté que si
chacun de ses motifs est probant contre (empaquetage, cmd, testdata, paquet absent du binaire dont la source a une fonction à corps) ;
lecture du binaire par le projet, pas une règle de Debian. Banc hors réseau : 8 cas, 8 OK ; autres bancs inchangés. Prédictions L1 à L5
dans [`resultats/paquets-predictions.md`](resultats/paquets-predictions.md) (10 paragraphes écartés sur 14, expression `BSD-3-Clause AND MIT AND
BSD-3-Clause AND BSD-3-Clause`). Lancement sur accord nommé, après `vsa`.
