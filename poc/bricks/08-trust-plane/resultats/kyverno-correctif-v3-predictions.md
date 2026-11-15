# Correctif Kyverno v3 (tests regroupés) : prédictions

Écrit le 15/11/2026 à 21:08 UTC, avant tout lancement. Décision du propriétaire : « PR directe » (réponse à « Pour notre correctif, PR directe ou question à un mainteneur d'abord ? »). Le lancement attend un accord nommé.

## Ce qui change

Le correctif v2 ajoute deux fichiers de tests (`tsa_key_attestor_test.go`, 273 lignes ; `tsa_extra_test.go`, 300 lignes, avec un troisième groupe d'imports mal placé). Le v3 les regroupe en un seul, `tsa_cert_chain_test.go`, à la manière des fichiers par sujet du paquet (`bundle_detect_test.go`, `cert_limit_test.go`…) :
- générateur [`regrouper-tests.py`](../kyverno-correctif/regrouper-tests.py) : un bloc d'imports (standard, puis le reste, triés, dédoublonnés, alias gardés), puis les deux corps tels quels ; assertions sur les déclarations de premier niveau (mêmes noms, sans doublon) et sur 9 fonctions `Test` ;
- `opts.go` et `verifier.go` ne changent pas.

Essai à sec du générateur, le 15/11, sur une copie des deux fichiers dans le répertoire de travail de la session (rien lancé, aucun test exécuté) : 554 lignes, 33 imports dont 15 standard, 18 déclarations, 9 tests ; `gofmt -l` vide.

Script [`regrouper-tests.sh`](../kyverno-correctif/regrouper-tests.sh), local, `GOPROXY=off`, go1.27.3 du cache. Référence : les `--- PASS` de nos 9 tests et de leurs sous-tests dans `mesure-18533/m5-paquet-detail.log` (PR 18533 + v2).

## Prédictions

| N° | Prédiction | Confiance |
|---|---|---|
| G0 | Arbre `main-b2e65e2` à `b2e65e2`, correctif v2 présent (`git apply -R --check` code 0). | haute |
| G1 | `regrouper-tests.py` : code 0 ; il ne reste que `tsa_cert_chain_test.go` parmi `tsa_*_test.go`. | haute |
| G2 | `gofmt -l` vide ; `go vet` du paquet code 0. | haute (gofmt) ; moyenne-haute (vet) |
| G3 | Correctif v3 : 3 fichiers (`opts.go`, `verifier.go`, `tsa_cert_chain_test.go`) ; diff d'`opts.go` et `verifier.go` identique au v2. | haute |
| G4 | Sur main + v3 : paquet `ok`, code 0, 0 `--- FAIL` ; liste des PASS de nos tests identique à la référence. | haute |
| G5 | Sur la PR 18533 + v3 (nouvel arbre `pr-18533-v3`, `git apply --3way`) : code 0, 0 conflit ; paquet `ok`, 6/6 tests de la PR ; PASS de nos tests identiques à la référence. | moyenne-haute |
| G6 | `go.mod` et `go.sum` non modifiés dans les deux arbres. | haute |

Durée attendue : moins de 6 minutes (deux passages du paquet d'environ 80 s).

## Ce que le v3 ne prouve pas

- `goimports`, `gofumpt` et golangci-lint : non installés ; `.golangci.yml` exclut de toute façon les `_test.go` des linters et des formateurs.
- La régression large (`./pkg/image/...`) : seul le paquet modifié est rejoué, le code étant celui du v2 (rejeu et mesure du 15/11).
- Rien n'est commité dans les arbres de Kyverno ; le DCO, le fork et le texte de la PR restent à faire, chacun avec son accord.
