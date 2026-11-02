# O4, essai d'un correctif de Chains : prédictions (écrites le 02/11/2026, avant toute mesure)

Demande du propriétaire (02/11/2026) : « crée un correctif et teste le sur notre cluster et tu fais valider tout par l'advisor et ensuite on fait la MR ».

## Le correctif

Une ligne dans `pkg/chains/signing.go` : dans le chemin « aucun signataire » (`No signer %s configured for %s`), appel de `o.recordError(ctx, signableType, metrics.SignerUnavailableError)`. Nouveau type d'erreur `signer_unavailable` dans `pkg/metrics/common.go`, documenté dans `docs/metrics.md`. Test unitaire `TestSigner_Sign_NoSignerRecordsError` (TaskRun et PipelineRun) ; la contre-épreuve sans la ligne échoue.

- **PR visée :** `main` de tektoncd/chains (`0084070`). `go test -race ./...` : 40 paquets, aucun échec ; golangci-lint v2.14.0 (version de la CI de Chains) : 0 problème ; gofmt et `go vet` propres.
- **Image d'essai :** v0.29.9 (la version validée en 08) + cherry-pick de #1834 (`b1c0af9`, absent de toute release) + le correctif. Entre v0.29.9 et `main`, `signing.go` ne diffère que par #1834 et `pkg/metrics` est identique ; `config/`, `pkg/config` et `pkg/reconciler` diffèrent, d'où le choix de v0.29.9 pour ne changer que le chemin de signature.
- **Construction :** Go 1.27.3 (archive vérifiée par sha256 contre go.dev, utilisée depuis le dossier temporaire, rien d'installé), `CGO_ENABLED=0 go build -trimpath ./cmd/controller` (options de ko par défaut), dépendances vendorisées, `GOPROXY=off`. La release v0.29.9 est construite avec Go 1.26.10 : écart consigné.
- **Image :** l'image déployée (`amont/…/cmd/controller@sha256:2200972d…`, point d'entrée `/ko-app/controller`, utilisateur 65532) + une couche qui remplace `/ko-app/controller` (crane append), poussée dans `essais-chains/controller` (jamais sous `amont/`).

## Ce que dit le code (lu avant de prédire)

- `annotations.HandleRetry` : tant que `chains.tekton.dev/retries` < 3 (`MaxRetries`), l'annotation est créée à 0 puis incrémentée ; ensuite `MarkFailed` pose `chains.tekton.dev/signed=failed`, état terminal (`reconciledFromAnnotations`).
- Le contrôleur renvoie l'erreur de `Sign` ; knative remet l'objet en file avec `DefaultTypedControllerRateLimiter` (5 ms, doublé à chaque échec), et chaque patch d'annotation déclenche aussi une réconciliation.
- `recordError` ne compte que les types TaskRun et PipelineRun (pas OCI) ; le type TaskRun ou PipelineRun est traité en premier, et l'échec du signataire arrête `Sign` avant le type OCI.
- `marked_signed` n'est incrémenté qu'après `MarkSigned`, jamais après `MarkFailed`.

## Prédictions

Même incident que le troisième passage d'A2 : OpenBao scellé (suppression du pod), puis un build de la 01 (commit vide sur `custom/s5` du fork).

1. **Image :** l'image d'essai a un digest différent de l'officielle ; seul `/ko-app/controller` change (3 couches de l'officielle + 1). Le pod du contrôleur redémarre sur ce digest et devient prêt en moins de 2 min.
2. **Pendant le scellement :** le build réussit, avec le même digest d'image que les builds précédents (`3a7ca1b1`). Aucun des quatre objets (PipelineRun et ses trois TaskRuns) n'est `signed=true`. Chacun finit `signed=failed` avec `retries=3`, moins de 2 min après sa fin. Le journal du contrôleur montre `No signer kms configured for …`.
3. **Compteurs :** `watcher_taskrun_signing_failures_total{error_type="signer_unavailable"}` atteint au moins 15 (5 tentatives × 3 TaskRuns), et `watcher_pipelinerun_signing_failures_total{error_type="signer_unavailable"}` au moins 5. Il peut y avoir plus de tentatives si une remise en file passe avant le patch d'annotation. `marked_signed` : +0.
4. **Alertes :** `ChainsEchecSignature` déclenchée (série nouvelle), notifiée. `ChainsMarqueSansSignature` reste inactive pendant tout l'essai.
5. **Après le descellement :** les quatre objets restent `signed=failed`. Il n'y a ni nouvelle tentative ni enveloppe à leur UID dans le tag `.att` : un objet du build fait pendant une panne du KMS reste non signé, et cette fois c'est visible.
6. **Remise en état :** le déploiement revient sur le digest d'origine `sha256:2200972d…`, et le pod est prêt. Un build normal (OpenBao descellé) est `signed=true`, avec ses enveloppes `COUVERTE` : le plan de confiance est revenu à l'état de la 08. Les exécutions de l'essai sont purgées. La clé Transit `chains` est inchangée. Les passages d'`horodatage` et de `rattrapage` réussissent après le descellement.

## Limites connues avant l'essai

- L'essai porte sur v0.29.9 + #1834 + le correctif, pas sur `main` : les tests unitaires sont passés sur les deux bases.
- L'image d'essai n'est ni signée ni attestée. Elle ne sert qu'à cet essai, et le déploiement revient à l'image officielle à la fin, même en cas d'échec (piège de remise en état).

## Additif du 02/11/2026, après l'essai (22:52 à 23:04 UTC)

Les six prédictions sont conformes ; le détail est dans le README de la brique (section « Essai d'un correctif de Chains »). Un écart de mesure, pas de prédiction : `correctif_a2` a lu les compteurs à 22:53:43, avant la collecte suivante de Prometheus (toutes les 30 s), et a donc affiché 13 échecs TaskRun et aucune série PipelineRun. Les valeurs finales du pod d'essai, relues dans Prometheus ([`o4-correctif-compteurs.log`](o4-correctif-compteurs.log)), sont 20 et 7. Leur total, 27, est égal au nombre de lignes « No signer » du journal. Il y a plus de tentatives que les 5 par objet prévues (20 au lieu de 15 pour les TaskRuns, 7 au lieu de 5 pour le PipelineRun), conformément à la réserve écrite : une remise en file passe parfois avant le patch d'annotation.
