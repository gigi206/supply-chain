# Brouillon d'issue chez grafana/alloy : NON ENVOYÉ

Rédigé le 10/11/2026 à 10:27 UTC, en local, sur l'interprétation de « il faut tout traiter » (propriétaire, 10/11/2026) : rédiger l'issue sans l'envoyer. **L'envoi est une action publique : il attend un oui explicite du propriétaire, sur ce texte exact.**

Faits repris des journaux archivés, pas de mémoire :
- l'erreur : `evenements-classe.log` ;
- la santé du composant : `evenements-diagnostic.log` ;
- la relance par un redémarrage : `evenements-redemarrage.log` et `evenements-verification.log`.

Le source est lu au tag `v1.21.3` et sur `main` au commit `cbdd9bfd97139011f0ee40cc5c1965edf4701ca4` (10/11/2026, environ 10:25 UTC), sans changement sur ce point. Le CHANGELOG de `v1.22.0-rc.0` ne cite aucun correctif de `loki.source.kubernetes_events` après la 1.21.3.

Une recherche par `gh search issues` sur `grafana/alloy` (« kubernetes_events retry », « failed to configure informers », « kubernetes_events connection refused », « kubernetes_events healthy ») ne trouve aucune issue sur ce défaut. Les plus proches sont #233 (close) et #274 (ouverte).

L'adresse de l'API et les noms internes sont retirés du texte.

---

**Title:** `loki.source.kubernetes_events`: event watcher never retries after a startup error, component stays healthy

**What's wrong?**

If the Kubernetes API server is not reachable when `loki.source.kubernetes_events` starts, the event watcher logs one error and stops. It is never restarted, and the component keeps reporting `healthy`. No events are collected until Alloy is restarted or its configuration changes. In our case this went unnoticed for about two days, and the events of that period expired from the API.

**Steps to reproduce**

1. Run Alloy v1.21.3 as a systemd service on a host outside the cluster. Use a `loki.source.kubernetes_events` component with `client { api_server = "https://<api-server>:6443" ... }`, authenticated with a service account token.
2. Start Alloy while nothing listens on the API server port yet. In our case, all VMs were rebooted together, and Alloy came up before the control plane.
3. Wait until the API server is up and serving.

**Observed**

```
level=info  msg="watching events for namespace" component_id=loki.source.kubernetes_events.evenements
level=error msg="event watcher exited with error" component_id=loki.source.kubernetes_events.evenements err="failed to configure informers: failed to get server groups: Get \"https://<api-server>:6443/api\": dial tcp <api-server>:6443: connect: connection refused"
level=info  msg="stopping watcher for events" component_id=loki.source.kubernetes_events.evenements
```

After this, the component's health was `healthy` ("started component") the whole time. Not a single event line reached Loki in about 54 hours, although the API server answered normally during that period. A plain `systemctl restart alloy` restored collection immediately.

**Expected**

One of the following:
- the watcher retries with a backoff, as client-go informers do once they are running;
- or the component reports itself unhealthy while no watcher is running, so the failure can be alerted on.

**Analysis (source at v1.21.3, unchanged on main at cbdd9bf)**

- `eventController.Run` (`internal/component/loki/source/kubernetes_events/event_controller.go`) logs `event watcher exited with error` and returns.
- Controllers are only (re)created by `Component.reconcile()`. It is called from `Update()` (configuration change) and from `NotifyClusterChange()`, which returns early unless clustering is enabled.
- So, without clustering, nothing restarts a watcher whose `Run` has returned, and `CurrentHealth` does not reflect it.

A similar non-recovering state was fixed for `mimir.rules.kubernetes` in 1.22.0 (#6339). #233 is related (startup failure on a large number of events), but it is about the startup timeout, not about the missing retry. #274 (component failure not reflected in metrics) is also related.

**Workaround**

- Restart Alloy once the API server is up.
- Alert on the absence of event lines. We count forwarded lines with `stage.metrics` and alert when the counter stops increasing.

**Environment**

- Alloy v1.21.3, official linux-amd64 binary, systemd.
- Kubernetes: RKE2, CIS profile.
- Alloy runs on a VM outside the cluster.
