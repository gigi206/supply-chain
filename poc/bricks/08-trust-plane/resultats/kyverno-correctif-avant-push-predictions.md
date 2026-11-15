# Commit de la PR Kyverno : contrôles d'avant push, prédictions

Écrit le 15/11/2026 à 21:29 UTC, avant tout lancement. Le lancement attend un accord nommé.

## Contexte

Le propriétaire a validé le message de commit v2 (« Oui, je valide »). Le commit est `1851634f9aff`, sur la branche `fix/ivpol-tsa-key-attestor` de l'arbre `main-b2e65e2`. Le conseiller a demandé trois contrôles avant le push :
- la CI de Kyverno lance `make test-unit` avec `-race -covermode atomic` (`Makefile` l. 886), alors que nos passages étaient sans détecteur de courses ;
- le lint n'a pas de témoin positif ;
- `main` doit être relu juste avant le push.

Lu à sec (fin du modèle de PR, `pr_documentation.md`) : la liste de contrôle demande d'avoir lu la politique IA et de déclarer l'IA dans le commit (fait par `Assisted-by`), des tests unitaires pour un correctif de bug (faits), et des « proof manifests » (à trancher pour le texte de la PR). Une case signale un besoin de cherry-pick vers une branche de release : le PoC tourne en v1.19.2, où le correctif v2 passait ses tests le 08/11 (`kyverno-correctif/g2-*`, `i2-*`). C'est au propriétaire de décider s'il la coche. Seul un compte ayant le droit d'écriture peut demander `/cherry-pick`.

Script [`verifier-avant-push.sh`](../kyverno-correctif/verifier-avant-push.sh), local, `GOPROXY=off` (sauf V3, `git ls-remote` en lecture publique).

## Prédictions

| N° | Prédiction | Confiance |
|---|---|---|
| V0 | Arbre `main-b2e65e2` au commit `1851634f`, propre ; gcc présent (requis par `-race`). | haute |
| V1 | Paquet `ivpol/cosign` avec `-race -covermode atomic` : `ok`, code 0, 0 « WARNING: DATA RACE ». | moyenne-haute |
| V2 | Témoin (arbre jetable `temoin-lint`, un commentaire « occured » et une conversion `int(x)` inutile ajoutés à `opts.go`) : lint code non nul, au moins un signalement `misspell` et un `unconvert` ; défauts retirés ensuite (0 ligne de status). Le diff des formateurs est affiché, pas jugé. | moyenne-haute |
| V3 | `main` distant a bougé depuis `b2e65e2` (dépôt actif) : ÉCART attendu, donc rebase et rejeu avant le push. | moyenne |

Durée attendue : 3 à 10 minutes (le détecteur de courses ralentit les tests).

## Ce que ces contrôles ne prouveront pas

Toute la suite `make test-unit` (`./...`), les tests de CLI, `verify-codegen`, la CI de Kyverno.
