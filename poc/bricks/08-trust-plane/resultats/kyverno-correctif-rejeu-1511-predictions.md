# Correctif Kyverno : rejeu sur le main du 14/11/2026, prédictions

Écrit le 15/11/2026 à 20:17 UTC, avant tout lancement, sur « Oui, rejoue-le » du propriétaire (réponse à « Je rejoue le correctif sur le main actuel, à sec ? »). Contexte : additif du 15/11 au README de la 08 (issue kyverno/kyverno#18525 confirmée par un contributeur, `triage` retirée par un mainteneur).

## Ce qui est rejoué

Script [`rejeu-main.sh`](../kyverno-correctif/rejeu-main.sh), local seulement : rien publié, rien lu ni écrit dans le cluster, Zot ou les VM.
- Arbre de travail détaché à `b2e65e2fa88f8ff8bfb0a6351712433d6b14796d` (main du 14/11, 15:26:00 UTC), ajouté au clone du cache `~/.cache/supply-chain-poc/08/kyverno-correctif/main` (récupéré par `git fetch` en lecture publique le 15/11). Le clone du 08/11 (`2be1bc3`, correctif appliqué) n'est pas touché.
- go1.27.3 du cache (celle du 08/11 ; `go.mod` demande toujours `go 1.27.3`), `GOPROXY=off`.
- Mêmes pièces que le 08/11 : [`correctif-v2-final.patch`](../kyverno-correctif/correctif-v2-final.patch) et [`repro_tsa_test.go.txt`](../kyverno-correctif/repro_tsa_test.go.txt) (sha256 `0fc91917b65857b0…`).

Relevés à sec avant d'écrire (15/11) : 19 commits de `2be1bc3` à `b2e65e2` ; aucun ne touche `pkg/image/verifiers/ivpol/cosign`, `go.mod` ni `go.sum`. Dans le périmètre de régression, 9 fichiers changent (dont `pkg/image/verification/evaluator/policy.go`, commit `e904af0` « hoist K8s CEL activation assembly »). Les trois aides du reproducteur sont toujours dans `bundle_detect_test.go`.

## Prédictions

| N° | Prédiction | Confiance | Fondement |
|---|---|---|---|
| R1 | `git apply --check` puis `git apply` du correctif v2 final : code 0, sans décalage signalé ; `git apply -R --check` code 0 ensuite. | haute | aucun commit sur les fichiers touchés depuis `2be1bc3` |
| R2 | Reproducteur sur `b2e65e2` intact : code de sortie non nul, panique « nil pointer » dans la sortie (au moins une ligne). | haute | lignes 93, 180, 181 d'`opts.go` inchangées ; confirmé par le contributeur sur `main` |
| R3 | Reproducteur avec le correctif : `--- PASS`, code 0. | haute | k2 du 08/11 sur le même code |
| R4 | Paquet `ivpol/cosign` complet avec le correctif et ses tests : `ok`, code 0. | haute | j du 08/11 ; paquet inchangé |
| R5 | Régression `./pkg/image/...` et `./pkg/cel/policies/ivpol/...` avec le correctif : aucun `FAIL`, code 0. | moyenne | h du 08/11, mais 9 fichiers du périmètre ont changé (hors paquet corrigé) |
| R6 | Aucun module à télécharger : `GOPROXY=off` suffit à tout construire ; `go.mod` et `go.sum` non modifiés à la fin. | haute | `go.mod` et `go.sum` identiques à `2be1bc3` |

Durée attendue : moins de 10 minutes (le 08/11 : environ 100 s pour le paquet, 105 s pour la régression). Aucune estimation à fixer : rejeu local court.

## Ce que ce rejeu ne prouvera pas

- golangci-lint (téléchargement à accorder), la CI de Kyverno, la signature DCO.
- La compatibilité avec kyverno/kyverno#18533, ouverte sur les mêmes fichiers : conflit textuel probable, non mesuré ici.
- L'admission : l'étape C du 09/11 a été faite sur v1.19.2 corrigée, pas sur ce `main`.
- L'arbre de travail `main-b2e65e2` est laissé en place pour préparer la PR ; rien n'y est commité.

## Additif du 15/11/2026, 20:18 UTC : v1 du rejeu arrêtée au départ, erreur d'instrument, script corrigé, rien jugé

- **Lancement** de 20:17:46 à 20:17:46 UTC (heures de la commande), code 2. Sortie et journal de préparation archivés : [`v1-echec-chemin.log`](../kyverno-correctif/rejeu-1511/v1-echec-chemin.log).
- **Cause** : le répertoire des journaux était passé en chemin relatif, puis le script se place dans l'arbre de travail. Toutes les redirections ont échoué (« No such file or directory »), donc aucun bloc après la préparation n'a été exécuté : ni reproducteur, ni `git apply`, ni tests. Le code 2 est celui du `grep` final, pas d'un test.
- **Fait** : l'arbre de travail `main-b2e65e2` a été créé (`worktree add` code 0, tête `b2e65e2…`). Relevé à 20:18:02 UTC : à `b2e65e2`, 0 ligne de status, pas de `repro_tsa_test.go`.
- **Correction** : chemin des journaux rendu absolu ; un arbre de travail existant n'est repris que s'il est à `b2e65e2` et propre (sinon KO). R1 à R6 sont inchangées et restent à juger. Le relancement attend l'accord du propriétaire (script modifié).
