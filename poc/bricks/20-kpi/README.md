# Brique 20 : KPI supply-chain dérivés des attestations, carte à sec

Seuil (README, brique 20) : **0 écart avec le recalcul depuis les attestations**. Effort estimé : **1,5 pw**. Au-delà de 3 pw, décision avec le propriétaire.

Ouverte le 2026-11-24, choix du propriétaire « 20 KPI (Recommandé) », en réponse à la question « Pendant l'attente de R4, quelle brique de la phase 2c ouvre-t-on à sec (protocole, audit docs/04, estimation, rien sur le cluster) ? ». Heures comptées depuis 17:45:07 UTC, première lecture de docs/02 pour cette brique.

Règles reprises : projets jugés par le doc 04, rien de « Risqué » ; versions épinglées ; prédictions datées et commitées avant chaque mesure ; passages ratés archivés ; accord du propriétaire avant tout changement du cluster, des VM, de Zot ou de Grafana. Tout doit être consultable dans Grafana.

## État

**Carte écrite à sec, rien n'est lu dans Zot, rien n'est posé.** Les faits ci-dessous viennent du dépôt. Aucun n'est encore relevé sur la plateforme en service.

## Ce que demande docs/02

docs/02, §7 (l. 229) : « `tools/metrics-exporter` dérive les métriques **des attestations** (taux L3 vérifié, taux de replay identique, KEV ouvertes et délai de correction, couverture VEX, violations de licences, âge des pins et des clés). Seuil : 0 écart avec le recalcul. » Le schéma du §5 (l. 189) place `metrics-exporter` après `tools/score`, qui n'existe pas non plus.

Vérifié le 2026-11-24 à 17:45 UTC : `tools/` ne contient que `health/`, `index/` et `secrets-depot.sh`. Il n'y a ni `tools/metrics-exporter` ni `tools/score`.

## Inventaire des KPI

| KPI | Attestation source | Dans la plateforme en service | Couvert aujourd'hui |
|---|---|---|---|
| Taux L3 vérifié | provenance `https://slsa.dev/provenance/v1` de Chains, verdict de la porte | oui (`builds/*`, tag `.att` et referrers) | non : la porte juge à l'admission, aucun compte |
| Taux de replay identique | VSA `https://slsa.dev/verification_summary/v1` du domaine de replay | oui pour l'image (`builds/vsa/sample-app`) ; pour le deb, seulement si `pousser_vsa` de la 06 a tourné | non |
| KEV ouvertes | scan `https://supply-chain.example/scan/v1` (champs `kev`, `kevCves`) moins les VEX | oui | **oui**, 07b : `scan_entrees_kev - scan_entrees_kev_vex`, panneau 7 du tableau « Vulnérabilités et VEX » |
| Délai de correction des KEV | historique des scans : première apparition d'une KEV, puis premier scan où elle est absente ou écartée | historique partiel : rétention des referrers dans Zot (G7), listes par scan dans Loki (`entrees-scan`, 720 h) | non ; 0 KEV aujourd'hui, donc il faudra un témoin |
| Couverture VEX | scan et VEX `https://openvex.dev/ns/v0.2.0` | oui | **oui**, 07b : KPI 3a et 3b (panneaux 6 et 8) |
| Violations de licences | `https://supply-chain.example/licences/v1` (13a, `licences.py`) | **non** : prédicat produit au banc, pas par une tâche de la plateforme (docs/03, ligne Licences) | non |
| Âge des pins | `resolvedDependencies` des provenances ; verrous `verrou-rpm.json`, `verrou-deb.txt` | partiel | non ; définition à choisir |
| Âge des clés | clés de Chains, du scanner, du TSA, des VEX et des VSA | clés publiques dans le dépôt ; dates de création dans OpenBao | non ; source à choisir |

Constat qui pèse sur le seuil : `entrees-scan.py` (07b) **ne vérifie pas les signatures**. L. 8 : « cosign n'est pas sur sc-stockage. La porte fait foi. » Un KPI « dérivé des attestations » sans vérification compte des énoncés, pas des attestations prouvées.

## Plan proposé, sans recommandation (à valider)

1. **Relevé à sec, lecture seule** : par dépôt de `builds/`, lister les attestations présentes dans Zot (anonyme) et leur type de prédicat. Résultat attendu : les dénominateurs (combien d'artefacts, lesquels ont une VSA ou un scan). Aucun accord.
2. **Recalcul de référence sur l'hôte** : un script qui relit chaque attestation, la vérifie avec la clé publique de son émetteur (cosign, déjà utilisé dans le PoC) et calcule chaque KPI. C'est lui qui définit « le recalcul » du seuil.
3. **Banc jetable** : Zot local et attestations témoins (un artefact sans VSA, une VSA FAILED, une KEV non écartée puis corrigée, une signature fausse). Le recalcul et l'exportateur doivent donner les mêmes valeurs, et la signature fausse doit être écartée.
4. **Pose de l'exportateur** (accord, sudo sur sc-stockage) : un service systemd et un fichier `.prom`, sur le modèle de `entrees-scan`.
5. **Seuil** : valeurs de Prometheus, lues par l'auditeur dans Grafana, comparées au recalcul de l'étape 2 : 0 écart.
6. **Tableau « KPI supply-chain »** (accord) : provisionné comme « Vulnérabilités et VEX » (ADR 0004).
7. **Câblage dans `rejeu.sh`**, sinon un rejeu de zéro efface la pose (leçon de l'export Hubble et de `entrees-scan`).

## Choix du propriétaire à poser (avant l'étape 2)

- **Vérification des signatures** : sur sc-stockage (installer cosign, donc accord et sudo), ou seulement dans le recalcul de l'hôte (l'exportateur compte les énoncés comme `entrees-scan`, et le recalcul prouve l'écart nul).
- **Âge des pins** : âge depuis l'épinglage (date du commit qui fixe le digest), ou retard sur l'amont (comme les 44 paquets en retard de l'amorce de la 05, mesure qui demande un accès au réseau).
- **Âge des clés** : date de la clé publique dans le dépôt (premier commit) ou date de création dans OpenBao (lecture avec un jeton, depuis l'hôte).
- **Licences** : KPI vide tant que la 13a n'a pas de tâche de confiance, ou mesuré sur les prédicats du banc.
- **Délai de correction des KEV** : historique tiré de Loki (720 h, listes de `entrees-scan`), ou état gardé par l'exportateur.

## Outils

Aucun outil nouveau n'est prévu : Python 3 de la distribution (comme `entrees-scan.py`), cosign et crane déjà épinglés et vérifiés dans le PoC. Si un outil s'ajoute, il passera d'abord par le doc 04.

## Liens

docs/02 §5 et §7 ; [07b, tableau et `entrees-scan`](../07a-sbom-grype/README.md) ; [ADR 0004](../../../docs/adr/0004-vulnerabilites-vex.md) ; [brique 10](../10-independent-replay/README.md) ; [13a](../13a-licences/README.md).
