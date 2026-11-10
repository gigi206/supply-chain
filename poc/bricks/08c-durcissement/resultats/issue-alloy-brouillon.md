# Brouillon d'issue chez grafana/alloy : NON ENVOYÉ

Rédigé le 10/11/2026 à 10:27 UTC, en local, sur l'interprétation de « il faut tout traiter » (propriétaire, 10/11/2026) : rédiger l'issue sans l'envoyer. **L'envoi est une action publique : il attend un oui explicite du propriétaire, sur ce texte exact.**

Faits repris des journaux archivés, pas de mémoire :
- l'erreur : `evenements-classe.log` ;
- la santé du composant : `evenements-diagnostic.log` ;
- la relance par un redémarrage : `evenements-redemarrage.log` et `evenements-verification.log`.

Le source est lu au tag `v1.21.3` et sur `main` au commit `cbdd9bfd97139011f0ee40cc5c1965edf4701ca4` (10/11/2026, environ 10:25 UTC), sans changement sur ce point. Le CHANGELOG de `v1.22.0-rc.0` ne cite aucun correctif de `loki.source.kubernetes_events` après la 1.21.3.

Une recherche par `gh search issues` sur `grafana/alloy` (« kubernetes_events retry », « failed to configure informers », « kubernetes_events connection refused », « kubernetes_events healthy ») ne trouve aucune issue sur ce défaut. Les plus proches sont #233 (close) et #274 (ouverte).

L'adresse de l'API et les noms internes sont retirés du texte.

*Corrigé à 10:29 UTC, avant tout push, sur relecture du conseiller* : le texte disait que l'API « answered normally » pendant toute la panne. Ce n'est pas mesuré en continu : on sait seulement que les nœuds étaient `Ready` 77 s après le démarrage des VM (V1 du 07/11) et que les lectures kubectl ont réussi le 09/11. La phrase dit maintenant cela.

*Additif du 10/11/2026, 10:43 UTC* : sur la question du propriétaire (« regarde le code source : il y a peut-être une option ou configuration, non ? »), le source de `v1.21.3` a été relu, cette fois avec `scheduler.go`, `reconcile.go` et `file.go`. Trois éléments ont été ajoutés au texte :
- un rechargement ne recrée pas l'observateur ;
- aucun réglage ne permet de le relancer ;
- la correction possible par `NewSourceWithRetry`.

*Additif du 10/11/2026, 11:03 UTC* (accord du propriétaire : « Oui, consigne », après sa question « tu as bien testé avec la dernière version d'alloy ? ») :
- **Aucun test n'a été fait sur une autre version que v1.21.3.** Aucun Alloy n'a été lancé pour reproduire le défaut. La seule observation est la panne du 07/11, survenue par accident en v1.21.3, qui est la dernière version stable. La seule plus récente est la pré-version `v1.22.0-rc.0` (05/11/2026).
- Le source a été comparé en `v1.21.3`, en `v1.22.0-rc.0` et sur `main` (`cbdd9bfd`) : [`alloy-source-comparaison.log`](alloy-source-comparaison.log). `reconcile.go`, `scheduler.go` (où est défini `NewSourceWithRetry`), `event_controller.go` et `common/kubernetes/kubernetes.go` sont identiques dans les trois. `kubernetes_events.go` change en rc.0, mais seulement par le nettoyage des positions (#7645), sans rapport. **Le chemin de relance est inchangé ; le fichier ne l'est pas.** Le titre de la section « Analysis » est corrigé dans ce sens.
- Les recherches d'avant 10:43 ne portaient que sur les issues. Deux recherches de PR (« kubernetes_events » et « kubernetes events retry », toutes, ouvertes comme fusionnées) ne trouvent aucun correctif de ce défaut.
- **La rubrique « Steps to reproduce » n'a jamais été jouée** : elle décrit la panne du 07/11, pas une reproduction délibérée. Avant tout envoi, il faut une décision du propriétaire :
  - la reformuler en « ce qui s'est passé » ;
  - ou faire une reproduction avec rc.0, sur accord : téléchargement vérifié par empreinte et signature, puis API ouverte seulement après le démarrage d'Alloy. Non lancée.

*Additif du 10/11/2026, 12:18 UTC* : la séquence s'est reproduite au redémarrage des VM du 10/11, toujours en v1.21.3 ([`evenements-boot.log`](evenements-boot.log)). Alloy a démarré à 11:22:01 UTC. L'observateur a échoué à 11:22:04 sur `connection refused`, sans reprendre jusqu'à la relance de 11:23:27. Il y a donc deux occurrences dans la même configuration, mais toujours pas de reproduction minimale isolée. L'envoi est reporté à la fin du projet, sur décision du propriétaire. Le texte anglais n'est pas modifié.

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

After this, the component's health was `healthy` ("started component") the whole time. Not a single event line reached Loki in about 54 hours, although the API server was back shortly after the reboot (all nodes Ready 77 s after the VMs started), and kubectl queries against it succeeded on the last day of that period. A plain `systemctl restart alloy` restored collection immediately.

**Expected**

One of the following:
- the watcher retries with a backoff, as client-go informers do once they are running;
- or the component reports itself unhealthy while no watcher is running, so the failure can be alerted on.

**Analysis (source at v1.21.3; the retry path is unchanged in v1.22.0-rc.0 and on main at cbdd9bf)**

- `eventController.Run` (`internal/component/loki/source/kubernetes_events/event_controller.go`) logs `event watcher exited with error` and returns.
- Controllers are only (re)created by `Component.reconcile()`. It is called from `Update()` (configuration change) and from `NotifyClusterChange()`, which returns early unless clustering is enabled.
- So, without clustering, nothing restarts a watcher whose `Run` has returned, and `CurrentHealth` does not reflect it.
- A configuration reload does not help either. `source.Scheduler` keeps the exited source in its map, so `Reconcile` sees the key as already scheduled (`s.Contains(key)`) and does not recreate it. Only a change of the `client` block, which calls `scheduler.Reset()`, or a restart of Alloy brings the watcher back.
- There is no argument to tune this. `informerSyncTimeout` (10 min) is hard-coded, and it does not apply here anyway: discovery failed immediately with `connection refused`.

**Possible fix**

The same package already provides `source.NewSourceWithRetry`, which `loki.source.file` uses (`MinBackoff: 1s`, `MaxBackoff: 10s`). Wrapping the `eventController` returned in `reconcile()` the same way would retry the watcher with a backoff until the context is cancelled. Reporting the component as unhealthy while no watcher runs would also help alerting.

A similar non-recovering state was fixed for `mimir.rules.kubernetes` in 1.22.0 (#6339). #233 is related (startup failure on a large number of events), but it is about the startup timeout, not about the missing retry. #274 (component failure not reflected in metrics) is also related.

**Workaround**

- Restart Alloy once the API server is up.
- Alert on the absence of event lines. We count forwarded lines with `stage.metrics` and alert when the counter stops increasing.

**Environment**

- Alloy v1.21.3, official linux-amd64 binary, systemd.
- Kubernetes: RKE2, CIS profile.
- Alloy runs on a VM outside the cluster.
