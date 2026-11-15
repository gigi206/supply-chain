# Correctif Kyverno contre la PR kyverno/kyverno#18533 : prédictions

Écrit le 15/11/2026 à 20:50 UTC, avant tout lancement, sur « Oui, mesure-le » du propriétaire (réponse à « Je mesure notre correctif contre la PR 18533, en local ? »).

## Pourquoi

[kyverno/kyverno#18533](https://github.com/kyverno/kyverno/pull/18533) (`pgmpofu`, ouverte, `ready-for-review`) modifie `opts.go` et `verifier.go`, comme notre correctif. Elle :
- résout un `trustedRoot` en ligne aussi sur le chemin rapide (clé ou certificat avec `insecureIgnoreTlog`) ; sans `trustedRoot` en ligne, `resolveTrustedMaterial` rend `nil` ;
- ajoute `sigVerifier == nil` à `shouldUseSignedTimestamps`, qui ne s'applique donc plus aux attesteurs à clé ou certificat ;
- refuse un attesteur `key: {}` vide.

Lecture du code (non mesurée) : dans notre cas (clé, `ctlog.tsaCertChain`, `insecureIgnoreTlog`, pas de `trustedRoot`), `checkOptions` met `UseSignedTimestamps = true` dans le bloc TSA, quel que soit `shouldUseSignedTimestamps`, et `TrustedMaterial` reste nil. La PR ne devrait donc pas corriger notre cas. Notre modification de `verifier.go` ajoute un bloc juste après la condition qu'elle réécrit : le contexte du correctif ne correspond plus à la ligne réécrite.

## Ce qui est mesuré

Script [`mesure-18533.sh`](../kyverno-correctif/mesure-18533.sh), local, `GOPROXY=off`, go1.27.3 du cache. Arbre de travail détaché `pr-18533` à la tête de la PR `04385c77395d3aea22bc1fd11e5e31cf049b00ca` (récupérée par `git fetch` en lecture publique le 15/11 ; base commune `2be1bc3`, celle de notre correctif ; 4 commits ; `go.mod` et `go.sum` identiques à `2be1bc3`). Mêmes pièces que les rejeux précédents : `correctif-v2-final.patch` et `repro_tsa_test.go.txt`.

## Prédictions

| N° | Prédiction | Confiance |
|---|---|---|
| M0 | Arbre de travail créé à `04385c77`, propre ; base commune `2be1bc3`. | haute |
| M1 | Reproducteur sur la PR seule : échec, panique « nil pointer » (au moins une ligne), code non nul. La PR ne corrige pas notre cas. | moyenne-haute |
| M2 | Paquet `ivpol/cosign` sur la PR seule : `ok`, code 0 (référence avant notre correctif). | haute |
| M3 | `git apply --check` du correctif v2 : **échec** (contexte de `verifier.go`). `git apply --3way` : code 0, 0 fichier en conflit, 0 marqueur de conflit. | moyenne |
| M4 | Reproducteur sur la PR + correctif : `--- PASS`, code 0. | moyenne-haute (si M3 tient) |
| M5 | Paquet `ivpol/cosign` sur la PR + correctif : `ok`, code 0 ; 6/6 tests de la PR et 9/9 tests du correctif passés ; 0 `--- FAIL`. | moyenne |
| M6 | Régression `./pkg/image/...` et `./pkg/cel/policies/ivpol/...` sur la PR + correctif : aucun `FAIL`, code 0. | moyenne |
| M7 | Aucun module téléchargé ; `go.mod` et `go.sum` non modifiés. | haute |

Si M3 échoue en `--3way`, M4 à M6 sont mesurées sur un arbre sans le correctif, ou en conflit : elles ne seront pas jugées. Durée attendue : moins de 10 minutes.

## Ce que la mesure ne prouvera pas

- Le comportement d'un `trustedRoot` en ligne avec la PR (contournement possible de notre cas, non essayé ici).
- golangci-lint, la CI de Kyverno, le DCO ; l'admission ; l'ordre dans lequel les mainteneurs fusionneraient les deux PR.
- `correctif-v2-sur-18533.patch` (diff produit par M3) n'est ni proposé ni publié : c'est une pièce de travail.
