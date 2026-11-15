# Correctif Kyverno v3 : lint, prédictions

Écrit le 15/11/2026 à 21:15 UTC, avant tout lancement. Le lancement attend un accord nommé.

## Outil

golangci-lint **v2.14.0**, version épinglée par le `Makefile` de Kyverno (`GOLANGCI_LINT_VERSION`). Il a été installé le 15/11/2026, de 21:13:43 à 21:14:01 UTC, sur « Oui, installe-le » : `go install …/cmd/golangci-lint@v2.14.0`, comme le `Makefile`, avec go1.27.3 du cache, `GOPROXY=https://proxy.golang.org` et `GOSUMDB=sum.golang.org` (vérification imposée, aucune exemption). Il est dans `~/.cache/supply-chain-poc/08/kyverno-correctif/outils/bin`, rien au niveau système.
- Somme du module `h1:ot8QffRa…`, égale à celle que `sum.golang.org` publie (lookup relu à 21:14:46 UTC).
- 211 modules téléchargés, chacun vérifié par `go` contre `sum.golang.org`. Binaire : sha256 `d8b665fe720d18e7…`.
- Journal : [`golangci-lint-v2.14.0-installation.log`](../kyverno-correctif/golangci-lint-v2.14.0-installation.log), sans les 211 lignes `go: downloading`.
- Verdict de projet : golangci-lint n'est pas un composant du PoC (absent de `docs/04`). C'est l'outil imposé par Kyverno ; le dépôt amont est actif (dernier push le 15/11, release v2.15.0 du 16/10).

## Ce qui est mesuré

Script [`lint-v3.sh`](../kyverno-correctif/lint-v3.sh), dans l'arbre `main-b2e65e2`, où le v3 est en place. Configuration `.golangci.yml` de Kyverno ; elle exclut les `_test.go` des linters et des formateurs. `GOPROXY=off`. Le lint porte sur le paquet `ivpol/cosign` seul : `make lint` couvre `./...`, mais seul ce paquet change.

## Prédictions

| N° | Prédiction | Confiance |
|---|---|---|
| L0 | Tête `b2e65e2` ; l'arbre porte exactement `correctif-v3.patch`. | haute |
| L1 | `run --new-from-rev=HEAD` sur le paquet : 0 problème, code 0. | moyenne-haute |
| L2 | `run` complet sur le paquet : 0 problème, code 0 (`main` passe le lint de la CI). | moyenne-haute |
| L3 | `fmt -c .golangci.yml --diff` sur le paquet : diff vide (0 ligne). | moyenne-haute |
| L4 | goimports seul sur `tsa_cert_chain_test.go` (comme `make imports-check`) : diff vide. | haute |
| L5 | gofumpt seul sur `tsa_cert_chain_test.go` : affiché, pas jugé (exclu par la configuration). | — |

Durée attendue : quelques minutes (premier chargement du cache d'analyse).

## Ce que le lint ne prouvera pas

- `make lint` sur tout `./...` ; `make verify-codegen` (aucun fichier généré n'est touché) ; le DCO, le fork et la PR.

## Résultat du 15/11/2026, 21:16 UTC : L0 à L4 tenues, L5 affichée

Lancé sur « Oui, lance-le », de 21:15:45 à 21:15:51 UTC (heures de la commande), code 0. Journaux : [`lint/`](../kyverno-correctif/lint/).

| N° | Mesure | Verdict |
|---|---|---|
| L0 | Tête `b2e65e2` ; arbre identique à `correctif-v3.patch` ; `.golangci.yml` `0612e18a…`. | tenue |
| L1 | « 0 issues. », code 0. | tenue |
| L2 | « 0 issues. », code 0. | tenue |
| L3 | Code 0, diff de 0 ligne. | tenue |
| L4 | Code 0, diff de 0 ligne. | tenue |
| L5 | Code 0, diff de 0 ligne (affiché). | — |

Les `--diff` n'ont pas modifié l'arbre (status inchangé, relevé à la fin de L5).

**Limite** : aucun témoin positif. Rien ne montre ici que ce lint, avec cette configuration, signale un défaut volontaire dans ce paquet : « 0 issues » prouve l'absence de signalement, pas que les linters ont analysé les fichiers. L2 a duré moins d'une seconde après L1 (cache d'analyse).
