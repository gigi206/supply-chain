# L1, prédictions écrites avant toute exécution (2026-11-02T20:34:46Z)

Accord du propriétaire : « Oui, lancer L1 ». Lecture seule sur les VM et le cluster. Seuls des téléchargements vers `~/.cache/supply-chain-poc/19b/amont` sur l'hôte.

1. **Empreintes** : les trois archives correspondent aux sha256 figés dans le script, relevés le 02/11/2026.
   - Loki 3.7.9 : `17a5fae2…`, lu dans `SHA256SUMS` de la release GitHub.
   - Alloy 1.21.3 : `50d23af2…`, même source.
   - Grafana 13.3.0 : `cec8f98c…`. Deux sources de Grafana Labs concordent : le `.sha256` de dl.grafana.com et l'API grafana.com. Le `.deb` de GitHub a lui aussi l'empreinte publiée par cette API (`458cb478…`).
2. **Attestations** : `gh release verify-asset` réussit pour Alloy et **échoue pour Loki** (aucune attestation de release). Grafana n'a pas d'archive `tar.gz` dans sa release GitHub, donc pas de vérification possible par ce moyen.
3. **`sc-stockage`** : 2 vCPU. Mémoire disponible entre 4 et 5 Gi (Prometheus et Alertmanager depuis O2). Disque libre entre 11 et 14 Go.
4. **Journald, dernière heure** (sortie JSON, prédiction faible) :
   - `sc-confiance` est la plus bavarde (serveur k3s), entre 5 et 50 Mo ;
   - `sc-build` et `sc-stockage` sont chacune sous 15 Mo.
5. **Journaux de pods, dernière heure** (horodatage CRI) : moins de 50 Mo en tout. Les espaces les plus bavards sont `kube-system` (Cilium) et ceux de Tekton et Chains.
6. **Événements Kubernetes** : moins de 1 000 au total, rétention d'une heure.
7. **Audits non configurés** : aucun device d'audit dans OpenBao, aucune section `audit` dans la configuration de Zot. Aucune option d'audit sur le serveur k3s (`--audit-*` absent de sa ligne de commande et de sa configuration).
8. **CLA** : Grafana Labs exige un CLA pour `grafana`, `loki` et `alloy` (prédiction faible). C'est un risque de changement de licence, à consigner.
9. **Dimensionnement** : 30 jours de rétention tiennent sur le disque libre de `sc-stockage`, en supposant une compression d'environ ×10 dans Loki.
