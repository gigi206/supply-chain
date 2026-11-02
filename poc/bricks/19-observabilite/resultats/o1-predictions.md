# O1, prédictions écrites avant mesure (2026-11-02T16:46:07Z)

Relevé en lecture seule (accord du propriétaire du 02/11/2026, « Go »). Rien n'est installé ni modifié.

1. **Kyverno 1.19.2** : métriques Prometheus sur le port 8000 (`/metrics`) des services `*-metrics` ; refus d'admission visibles dans `kyverno_admission_requests_total` et `kyverno_policy_results_total` (étiquette de résultat `fail`).
2. **Chains v0.29.9** : métriques sur 9090 ; compteurs de signatures réussies (`watcher_*_sign_created_total` ou proche) ; **pas de compteur d'échec de signature direct** : l'alerte devra se déduire (écart entre PipelineRuns terminés et signés, ou annotation `chains.tekton.dev/signed=failed`).
3. **OpenBao** : `/v1/sys/metrics` refusé sans jeton (pas de `unauthenticated_metrics_access` dans la configuration de la 08) ; `/v1/sys/health` lisible sans jeton et donne l'état scellé.
4. **Zot** (sur `sc-stockage`) : extension de métriques non activée dans la configuration de la 08 : `/metrics` absent.
5. **Forgejo 15.0.11** : `[metrics] ENABLED` non activé : `/metrics` répond 404.
6. **NetworkPolicy** : les six espaces de la 08 refusent l'entrée par défaut ; `kyverno` et `tekton-chains` n'en ont pas, donc collecte possible sans modifier la 08 pour ces deux sources ; OpenBao demandera d'ouvrir l'entrée de `openbao`.
