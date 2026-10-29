# Brique 02 : stockage des artefacts et index de provenance (partie locale)

Seuil (README, brique 02) : attestations récupérables (referrers ou tags) ; `tools/index` répond en moins d'une minute aux deux requêtes V4 :
- « quels artefacts ont été construits avec le digest X ? » ;
- « quelles attestations pour ce sha256 brut ? ».

## Outil : [`tools/index`](../../../tools/index/index.py)

`index.py crawl` parcourt le registre (catalogue, tags, API Referrers OCI 1.1) et range dans SQLite :
- les artefacts et leurs couches (fichiers ORAS) ;
- les énoncés in-toto lus dans les **bundles Sigstore v0.3 en referrers** (mode `sigstore-bundle` de Chains) et dans les **tags cosign `.att`** (enveloppes DSSE, mode `dsse` de Chains, celui retenu tant que tektoncd/chains#2096 n'est pas publiée) ;
- les sujets et les `resolvedDependencies` (SLSA v1) ou `materials` (v0.2) ;
- les signatures, comptées à part : les énoncés `https://sigstore.dev/cosign/sign/v1` et les tags `.sig` **ne sont pas** des attestations (voir le constat du banc C).

Requêtes :
- `index.py built-with <digest>` : artefacts dont la provenance cite ce digest ;
- `index.py attestations <digest>` : énoncés dont ce digest est le sujet, **ou** dont le sujet est l'artefact qui contient ce digest comme couche (un fichier rpm, deb ou binaire poussé avec ORAS).

**L'index n'est pas une source de confiance** : il ne vérifie aucune signature. Il retrouve vite ce que la porte (Conforma ou Kyverno) et le replay vérifieront. On peut le supprimer et le reconstruire à tout moment (`crawl --rebuild`). Un recrawl est idempotent et ne relit pas les attestations déjà indexées.

## Résultats ([`bench.sh`](bench.sh), journal : [`resultats/bench.log`](resultats/bench.log))

Registre Zot local peuplé avec :
- 10 000 artefacts synthétiques (50 dépôts), chacun avec une provenance SLSA v1 en referrer qui cite 20 dépendances ;
- les 17 images du banc C, signées et attestées avec cosign v3 (16 en bundles referrers), plus une provenance en tag `.att`.

| Mesure | Résultat |
|---|---|
| Contenu indexé | 10 023 artefacts, 10 067 énoncés, 200 088 dépendances, 16 signatures |
| **`built-with` (dépendance « canari » citée par 20 artefacts)** | **1 ms**, résultat exact (20 / 20) |
| **`attestations` d'un fichier brut** (couche d'un artefact ORAS) | **< 1 ms**, provenance retrouvée via le manifest qui le contient |
| Reconstruction complète (`crawl --rebuild`) | 58 s |
| Recrawl incrémental (rien de neuf) | 41 s (relecture des tags, manifests et referrers) |
| Taille de l'index | 120 Mo |

Tests unitaires ([`tools/index/test_index.py`](../../../tools/index/test_index.py), registre en mémoire) : 5 tests réussis. Ils couvrent les deux formats (referrer et `.att`), le fichier brut, les signatures non comptées comme attestations, le recrawl idempotent (ni bundle ni blob relu) et les `materials` v0.2.

**Rejeu sur le laptop (29/10/2026)** ([`resultats/bench-laptop.log`](resultats/bench-laptop.log)) : requêtes **exactes** et identiques au cloud (même artefact retrouvé pour le fichier brut), en 0 ms ; reconstruction en **23 s** (58 s dans le cloud). Les compteurs diffèrent de 2 dépôts et 6 artefacts, parce que le registre du cloud contenait déjà les fermetures de la brique 03.

## Limites et suite

- Le recrawl incrémental relit tous les tags. Au-delà de quelques dizaines de milliers d'artefacts, il faudra s'abonner aux **événements de Zot** (extension `events`, à vérifier) ou à ceux de Chains, et garder le recrawl complet en contrôle périodique.
- Les artefacts supprimés du registre ne disparaissent de l'index qu'au prochain `--rebuild`.
- **Sur le laptop** : indexer la vraie provenance de Chains (brique 08), y compris les rpm et deb poussés avec ORAS ; mesurer sur le volume réel de Traefik.
