# Brique 07b, tranche 2 : prédictions, écrites avant le banc

Écrites le 21/11/2026 vers 16:50 UTC, avant le premier passage de [`07b-t2-banc.sh`](07b-t2-banc.sh). Le banc compare chaque cas à la colonne « attendu » de ce tableau, recopiée dans le script.

## Ce qui était déjà vu avant d'écrire ces lignes

Deux sondes hors dépôt (scratchpad, `~/.cache/supply-chain-poc/07a/t2-sonde`), sans réseau, base du 04/11 :

- **SBOM CycloneDX fusionné en entrée** (`sbom:`, la forme du scanner de la plateforme) : **`--vex` refusé**, code 1, `source type not supported for VEX`. Avec un produit égal au PURL du composant, puis avec le chemin du SBOM en produit et le PURL en sous-composant.
- **Image archivée en entrée** (`oci-dir:`, digest `3a7ca1b14dbf…`, celui du scan signé réel) : référence à 5 correspondances. Un VEX `not_affected` sur `GHSA-mqqf-5wvp-8fh8` donne 4 et 1, avec les produits `pkg:oci/sample-app@sha256:3a7c…`, `sha256:3a7c…`, `sample-app` et le chemin du dossier, avec ou sans sous-composant au PURL de Syft.
- **SBOM syft-json produit depuis l'image** : source de type `image`, VEX appliqué, 4 et 1.
- Forme d'une entrée ignorée : `appliedIgnoreRules: [{namespace: "vex", vex-status: "not_affected"}]`.

Ces cas sont rejoués dans le banc ; leur prédiction n'est donc pas aveugle. Les autres le sont.

## Prédictions

Notation `m/i` : correspondances (`matches`) et ignorées (`ignoredMatches`). Vulnérabilité du VEX : `GHSA-mqqf-5wvp-8fh8` (alias `CVE-2025-69725`), sauf mention. Produit : `pkg:oci/sample-app@sha256:3a7c…`, sauf mention. Statut : `not_affected`, sauf mention.

| Cas | Entrée | VEX | Attendu | Confiance |
|---|---|---|---|---|
| ref | image | aucun | 5/0 | vu |
| syft-exact | image | sous-composant `pkg:golang/github.com/go-chi/chi@v5.2.3#v5` (Syft) | 4/1 | vu |
| hermeto | image | sous-composant `pkg:golang/github.com/go-chi/chi/v5@v5.2.3?type=module` (Hermeto) | 5/0 | faible |
| v5-nu | image | sous-composant `pkg:golang/github.com/go-chi/chi/v5@v5.2.3` | 5/0 | faible |
| sans-subpath | image | sous-composant `pkg:golang/github.com/go-chi/chi@v5.2.3` | 4/1 | faible |
| sans-version | image | sous-composant `pkg:golang/github.com/go-chi/chi#v5` | 4/1 | faible |
| autre-version | image | sous-composant `…/chi@v5.2.2#v5` | 5/0 | moyenne |
| autre-digest | image | produit `pkg:oci/sample-app@sha256:00…00`, sous-composant Syft | 5/0 | moyenne |
| autre-nom | image | produit `pkg:oci/autre-app@sha256:3a7c…`, sous-composant Syft | 5/0 | faible |
| autre-vuln | image | vulnérabilité `GHSA-0000-0000-0000` | 5/0 | forte |
| alias-cve | image | vulnérabilité `CVE-2025-69725` | 4/1 | faible |
| affected | image | statut `affected` | 5/0 | forte |
| under-investigation | image | statut `under_investigation` | 5/0 | forte |
| fixed | image | statut `fixed` | 4/1 | moyenne |
| sbom-fusionne | SBOM CycloneDX fusionné | sous-composant Syft | refus (code 1) | vu |
| sbom-composant | même SBOM, `metadata.component` de type `container` au digest de l'image | sous-composant Syft | refus (code 1) | faible |
| syft-json | SBOM syft-json de l'image | sous-composant Syft | 4/1 | vu |
| csaf | image | même énoncé en CSAF 2.0 (`known_not_affected`, PURL Syft) | refus ou 5/0 | faible |

**Le sens inverse des PURL divergents** (SBOM à la forme Hermeto, VEX à la forme Syft) ne peut pas être mesuré avec cette version : il faudrait un SBOM en entrée, et `--vex` y est refusé. Les SBOM réels de la forme Hermeto sont des CycloneDX de fermeture.

## Zot et clé jetables

Zot jetable dans un espace de noms réseau vide, sur 127.0.0.1, comme G6. Image archivée poussée, VEX du cas `syft-exact` signé en `attest-blob` par une clé jetable (type `https://openvex.dev/ns/v0.2.0`), publié en referrer sous `builds/vex/sample-app`, comme `scanner.sh publier`.

| Cas | Attendu | Confiance |
|---|---|---|
| zot-cle | `verify-attestation` avec la clé jetable : 1 énoncé ; prédicat relu égal au VEX signé (mêmes clés et valeurs, `jq -S`) ; Grype avec ce VEX relu : 4/1 | moyenne |
| zot-cle-etrangere | `verify-attestation` avec une autre clé : refus, 0 énoncé | forte |

Aucun appel au vrai Zot (192.168.161.13:5000) : G7 jusqu'au 29/11. La base Grype de `g0/dbcache` est lue sans être modifiée (empreinte du listage avant et après).

Les VEX de ce banc sont des **témoins** : aucune analyse d'atteignabilité ne les fonde (choix 5).

## Ajout avant le second passage (rien n'est réécrit au-dessus)

Écrit après le premier journal ([`07b-t2-banc.log`](07b-t2-banc.log)), avant le second. Le premier a donné 4 écarts : `autre-digest` et `autre-nom` à 4/1 (prédit 5/0), `alias-cve` à 5/0 (prédit 4/1), et le contrôle du digest de l'image poussée vide (défaut du banc : erreur jetée, à afficher). Cinq cas sont ajoutés pour situer ce que Grype compare dans le produit et la vulnérabilité :

| Cas | Entrée | VEX | Attendu | Confiance |
|---|---|---|---|---|
| autre-tout | image | produit `pkg:oci/autre-app@sha256:00…00`, sous-composant Syft | 4/1 | faible |
| autre-tout-sans-sous | image | même produit, sans sous-composant | 4/1 | faible |
| produit-texte | image | produit `n-importe-quoi`, sans sous-composant | 4/1 | faible |
| autre-sous | image | produit habituel, sous-composant `pkg:golang/stdlib@1.26.10` | 5/0 | moyenne |
| alias-liste | image | vulnérabilité `CVE-2025-69725` avec `aliases: [GHSA-mqqf-5wvp-8fh8]` | 4/1 | faible |

Les cas du premier passage gardent leur prédiction d'origine : leurs écarts restent des écarts au second.

## Ajout avant le troisième passage (rien n'est réécrit au-dessus)

**Défaut du banc aux deux premiers passages** : le SBOM d'entrée du cas `sbom-composant` portait le même nom que la sortie de Grype (`$T/<cas>.json`). La redirection le vidait avant sa lecture, d'où « sbom format not recognized ». Ce refus ne mesurait rien. L'entrée prend un autre nom.

Une sonde hors dépôt (`t2-sonde`), après le second passage : un SBOM CycloneDX fusionné, auquel on ajoute un `metadata.component` de type `container` sans `bom-ref`, est lu par Grype comme une source `image`, et le VEX s'y applique (4/1). Avec le type `application`, `--vex` est refusé comme pour le SBOM fusionné.

| Cas | Entrée | Attendu | Confiance |
|---|---|---|---|
| sbom-composant (inchangé : `container`, avec `bom-ref` et PURL) | SBOM fusionné + `metadata.component` | 4/1 | moyenne (sonde sans `bom-ref`) |
| sbom-application | même composant, de type `application` | refus | vu |

## Ajout avant le quatrième passage, après relecture du conseiller (rien n'est réécrit au-dessus)

**Heure d'écriture du premier tableau** : « vers 16:50 UTC » était une estimation. Elle est bornée par deux relevés `date -u` : après 16:48:28Z (contrôle des chemins libres), avant 16:51:10Z (début du premier passage).

**Phrase devenue fausse** : « le sens inverse des PURL divergents ne peut pas être mesuré avec cette version ». Le troisième passage montre qu'un SBOM CycloneDX à `metadata.component` de type `container` accepte `--vex` : le sens inverse se mesure sur un tel SBOM, où le PURL de chi prend la forme Hermeto archivée (`reference-hermeto.log`). Le nom du composant reste `github.com/go-chi/chi/v5` : seul le PURL d'Hermeto est archivé, pas son nom.

**Produit ignoré, à situer** : l'`oci-dir` n'a ni tag ni `repoDigests`. Les mêmes cas sont rejoués sur une source `registry:` (le Zot jetable, dans l'espace de noms vide) et sur le SBOM à composant.

| Cas | Entrée | VEX | Attendu | Confiance |
|---|---|---|---|---|
| reg-ref | `registry:127.0.0.1:15001/builds/sample-app@sha256:3a7c…` | aucun | 5/0 | moyenne |
| reg-bon | même | produit habituel, sous-composant Syft | 4/1 | moyenne |
| reg-nu | même | produit `127.0.0.1:15001/builds/sample-app@sha256:3a7c…`, sans sous-composant | 4/1 | faible |
| reg-autre-digest | même | produit `pkg:oci/sample-app@sha256:00…00`, sous-composant Syft | 4/1 | faible |
| reg-autre-nom | même | produit `pkg:oci/autre-app@sha256:3a7c…`, sous-composant Syft | 4/1 | faible |
| reg-produit-texte | même | produit `n-importe-quoi`, sans sous-composant | 4/1 | faible |
| sbom-composant-autre | SBOM à composant | produit `pkg:oci/autre-app@sha256:00…00`, sous-composant Syft | 4/1 | faible |
| sbom-composant-texte | SBOM à composant | produit `n-importe-quoi`, sans sous-composant | 4/1 | faible |
| inv-ref | SBOM à composant, chi au PURL Hermeto | aucun | 5/0 | faible |
| inv-syft | même | sous-composant Syft | 5/0 | faible |
| inv-hermeto | même | sous-composant Hermeto | 4/1 | moyenne |
| vex-vide | image | document `{}` | refus | faible |

Le témoin `vex-vide` sert à lire le 5/0 du cas `csaf` : si `{}` donne aussi 5/0 sans erreur, Grype accepte un document quelconque sans effet, et le cas `csaf` ne dit rien du format.

## Ajout avant le cinquième passage (rien n'est réécrit au-dessus)

Le quatrième journal coupe à 200 caractères le refus du cas `vex-vide`, avant sa cause. Le cinquième passage ne change que cette coupe (400 caractères, dossier du banc remplacé par `<banc>`). Aucun cas nouveau : les prédictions sont celles des sections précédentes, écarts compris.
