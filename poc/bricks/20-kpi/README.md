# Brique 20 : KPI supply-chain dérivés des attestations, carte à sec

Seuil (README, brique 20) : **0 écart avec le recalcul depuis les attestations**. Effort estimé : **1,5 pw**. Au-delà de 3 pw, décision avec le propriétaire.

Ouverte le 2026-11-24, choix du propriétaire « 20 KPI (Recommandé) », en réponse à la question « Pendant l'attente de R4, quelle brique de la phase 2c ouvre-t-on à sec (protocole, audit docs/04, estimation, rien sur le cluster) ? ». Heures comptées depuis 17:45:07 UTC, première lecture de docs/02 pour cette brique.

Règles reprises : projets jugés par le doc 04, rien de « Risqué » ; versions épinglées ; prédictions datées et commitées avant chaque mesure ; passages ratés archivés ; accord du propriétaire avant tout changement du cluster, des VM, de Zot ou de Grafana. Tout doit être consultable dans Grafana.

## État

**Étape 2 faite le 2026-11-24 (recalcul de référence, signatures vérifiées, 18:55:04 UTC).** [Prédiction et résultat](resultats/e2-predictions.md) : **10 cas, 0 écart** ; 37 attestations listées et vérifiées, 0 par la clé étrangère. Provenance de Chains vérifiée 4/4, VSA `SLSA_BUILD_LEVEL_3` 1/4, replay identique 2/4, 0 KEV ; pour `f5e6bcb0` et le deb, Prometheus est égal au recalcul. Constat : Loki ne voit pas tous les scans (3 sur 5 pour `sample-app`). Rien n'est posé.

**Étape 1 faite le 2026-11-24 (relevé anonyme de Zot, 18:26:24 UTC).** [Prédiction et résultat](resultats/e1-predictions.md) : **12 cas, 2 écarts**, tous deux des fautes de la prédiction. Les 4 énoncés en cause sont des témoins négatifs voulus (J6, G6) qu'elle n'avait pas comptés. Pour les produits, les builders et les fermetures, tous les énoncés sont lisibles et nomment leur sujet. Signatures non vérifiées à cette étape.

Aperçu des produits, énoncés non vérifiés : 4 sujets (`sample-app` `3a7ca1b1` et `f5e6bcb0`, deb `60f25f5c`, rpm `07b7bd6f`). Tous ont une provenance ; 3 ont un scan, 3 un VEX et 2 une VSA. Le digest en service, `f5e6bcb0`, n'a pas encore de VSA. L'historique des scans dans Zot commence au rejeu du 23/11, et celui de Loki aussi (mesuré, `e1-loki-anciennete.log`) : un rejeu de zéro remet les deux à zéro.

**Heures de la 20** (2026-11-24, `date -u`) : 17:45:07 à 17:50:31 (ouverture, carte), 18:23:30 à 18:27:23 (étape 1), 18:27:23 à 18:30:36 (relecture, Loki, corrections), soit 0 h 12 min 30 s ; étape 2 de 18:49:15 à 18:56:03 (6 min 48 s). Total **19 min 18 s**. Majorant par la méthode de la 05 (écarts d'au plus 1 h entre commits de `poc/bricks/20-kpi`) : 42 min 16 s ; il compte à tort l'écart de 17:50:31 à 18:26:20, qui contient la clôture de la 05 et la 07c. Estimation : 1,5 pw.

Les faits des sections suivantes, écrits avant l'étape 1, viennent du dépôt.

## Ce que demande docs/02

docs/02, §7 (l. 229) : « `tools/metrics-exporter` dérive les métriques **des attestations** (taux L3 vérifié, taux de replay identique, KEV ouvertes et délai de correction, couverture VEX, violations de licences, âge des pins et des clés). Seuil : 0 écart avec le recalcul. » Le schéma du §5 (l. 189) place `metrics-exporter` après `tools/score`, qui n'existe pas non plus.

Vérifié le 2026-11-24 à 17:50:01 UTC (`date -u` de la même commande) : `tools/` ne contient que `health/`, `index/` et `secrets-depot.sh`. Il n'y a ni `tools/metrics-exporter` ni `tools/score`.

## Inventaire des KPI

| KPI | Attestation source | Dans la plateforme en service | Couvert aujourd'hui |
|---|---|---|---|
| Taux L3 vérifié | provenance `https://slsa.dev/provenance/v1` de Chains, verdict de la porte | oui (`builds/*`, tag `.att` et referrers) | non : la porte juge à l'admission, aucun compte |
| Taux de replay identique | VSA `https://slsa.dev/verification_summary/v1` du domaine de replay | oui pour l'image (`builds/vsa/sample-app`) ; pour le deb, seulement si `pousser_vsa` de la 06 a tourné | non |
| KEV ouvertes | scan `https://supply-chain.example/scan/v1` (champs `kev`, `kevCves`) moins les VEX | oui | **oui**, 07b : `scan_entrees_kev - scan_entrees_kev_vex`, panneau 7 du tableau « Vulnérabilités et VEX » |
| Délai de correction des KEV | historique des scans : première apparition d'une KEV, puis premier scan où elle est absente ou écartée | historique partiel : rétention des referrers dans Zot (G7), listes par scan dans Loki (`entrees-scan` ; `retention_period: 720h`, `19b-journalisation/config/loki.yaml` l. 77) | non ; 0 KEV aujourd'hui, donc il faudra un témoin |
| Couverture VEX | scan et VEX `https://openvex.dev/ns/v0.2.0` | oui | **oui**, 07b : KPI 3a et 3b (panneaux 6 et 8) |
| Violations de licences | `https://supply-chain.example/licences/v1` (13a, `licences.py`) | **non** : prédicat produit au banc, pas par une tâche de la plateforme (docs/03, ligne Licences) | non |
| Âge des pins | `resolvedDependencies` des provenances ; verrous `verrou-rpm.json`, `verrou-deb.txt` | partiel | non ; définition à choisir |
| Âge des clés | clés de Chains, du scanner, du TSA, des VEX et des VSA | clés publiques dans le dépôt ; dates de création dans OpenBao | non ; source à choisir |

Constat qui pèse sur le seuil : `entrees-scan.py` (07b) **ne vérifie pas les signatures**. L. 8 : « cosign n'est pas sur sc-stockage. La porte fait foi. » Un KPI « dérivé des attestations » sans vérification compte des énoncés, pas des attestations prouvées.

## Plan proposé, sans recommandation (à valider)

1. **Relevé à sec, lecture seule** : par dépôt de `builds/`, lister les attestations présentes dans Zot (anonyme) et leur type de prédicat. Résultat attendu : les dénominateurs (combien d'artefacts, lesquels ont une VSA ou un scan). Aucun accord.
2. **Recalcul de référence sur l'hôte** : un script qui relit chaque attestation, la vérifie avec la clé publique de son émetteur (cosign, déjà utilisé dans le PoC) et calcule chaque KPI. C'est lui qui définit « le recalcul » du seuil.
3. **Banc jetable** : Zot local et attestations témoins (un artefact sans VSA, une VSA FAILED, une KEV non écartée puis corrigée, une signature fausse). Le recalcul et l'exportateur doivent donner les mêmes valeurs sur les témoins signés. Pour la signature fausse, l'attendu dépend du premier choix ci-dessous : si l'exportateur vérifie, il l'écarte ; s'il ne vérifie pas, le recalcul doit la détecter comme un écart non nul.
4. **Pose de l'exportateur** (accord, sudo sur sc-stockage) : un service systemd et un fichier `.prom`, sur le modèle de `entrees-scan`.
5. **Seuil** : valeurs de Prometheus, lues par l'auditeur dans Grafana, comparées au recalcul de l'étape 2 : 0 écart.
6. **Tableau « KPI supply-chain »** (accord) : provisionné comme « Vulnérabilités et VEX » (ADR 0004).
7. **Câblage dans `rejeu.sh`**, sinon un rejeu de zéro efface la pose (leçon de l'export Hubble et de `entrees-scan`).

## Décisions du propriétaire (2026-11-24, 18:32:11 UTC)

Quatre questions posées ensemble, chacune avec la recommandation du conseiller en première option. Réponses verbatim :

- **Dénominateur** : « Produits, tous digests (Recommandé) ». Les taux comptent `sample-app`, `sample-app-deb` et `sample-app-rpm`, chaque digest présent dans Zot, étiqueté. Prix accepté : `3a7ca1b1` reste compté tant qu'il est dans Zot ;
- **Âge des pins** : « Depuis l'épinglage (Recommandé) », c'est-à-dire la date du commit qui fixe le digest ou la version ;
- **Âge des clés** : « Clé publique dans git (Recommandé) », c'est-à-dire le dernier changement de la clé publique versionnée ;
- **Délai de correction des KEV** : « Loki, 720 h (Recommandé) ». Réserve écrite : l'historique repart de zéro à chaque rejeu (mesuré).

Restent à poser, sans bloquer l'étape 2 : la vérification des signatures par l'exportateur (étape 4) et les licences (le recalcul donne « source absente », 0 prédicat mesuré dans Zot).

## Après l'étape 2 : décision et limites

- **« Taux L3 vérifié » (docs/02)** : décision du propriétaire du 24/11, verbatim **« VSA seule (Recommandé) »**. L3 vérifié = VSA de replay qui porte `SLSA_BUILD_LEVEL_3`. Les deux lectures comparées :
  - provenance de Chains vérifiée (signature, `builder.id`, PipelineRun, signature d'image) : **4/4**. La politique de la porte n'est pas rejouée, donc « L3 » n'y est pas prouvé ; afficher le deb en L3 contredirait la décision du 12/11 (« Bit identique seul »). Affiché à côté, sous son nom littéral ;
  - VSA de replay qui porte `SLSA_BUILD_LEVEL_3` : **1/4**. Le deb ne l'aura jamais, par décision ; le rpm non plus tant qu'il n'a pas de VSA.
- **Délai des KEV** : limite mesurée de la décision « Loki, 720 h » : `entrees-scan` n'émet que le scan le plus récent de chaque passage (15 min) et seulement pour les digests de `SCANS` : les scans intermédiaires et le rpm sont invisibles.
- **L'exportateur n'a pas git** : les dates des pins et des clés devront lui venir d'un relevé versionné (étape 4).

## Choix du propriétaire (liste d'origine)

Relu après l'étape 1 (conseiller) : seuls le dénominateur, l'âge des pins, l'âge des clés et le délai des KEV bloquent l'étape 2. Le recalcul de l'hôte vérifie les signatures quoi qu'il arrive : le premier choix ne concerne que l'exportateur (étape 4). Pour les licences, l'étape 1 a mesuré 0 prédicat `licences/v1` dans Zot, donc le recalcul donnera « source absente » quel que soit le choix.


- **Vérification des signatures** : sur sc-stockage (installer cosign, donc accord et sudo), ou seulement dans le recalcul de l'hôte (l'exportateur compte les énoncés comme `entrees-scan`, et le recalcul prouve l'écart nul).
- **Âge des pins** : âge depuis l'épinglage (date du commit qui fixe le digest), ou retard sur l'amont (comme les 44 paquets en retard de l'amorce de la 05, mesure qui demande un accès au réseau).
- **Âge des clés** : date de la clé publique dans le dépôt (premier commit) ou date de création dans OpenBao (lecture avec un jeton, depuis l'hôte).
- **Licences** : KPI vide tant que la 13a n'a pas de tâche de confiance, ou mesuré sur les prédicats du banc.
- **Délai de correction des KEV** : historique tiré de Loki (720 h, listes de `entrees-scan`), ou état gardé par l'exportateur. Réserve mesurée : Loki repart de zéro à chaque rejeu, comme tout état gardé sur sc-stockage.
- **Dénominateur** (ajouté le 2026-11-24, sur relecture du conseiller du plan de l'étape 1) : deux définitions changent tous les taux. Quels dépôts comptent : les produits seuls (`sample-app`, `sample-app-deb`, `sample-app-rpm`), ou aussi les builders, les fermetures et les essais ? Quel digest compte : celui en service seulement, ou tous les digests présents dans Zot (`3a7ca1b1` et `f5e6bcb0` cohabitent) ? Le relevé de l'étape 1 liste tout, avec une classe déduite du nom, et ne tranche pas.

## Outils

Aucun outil nouveau n'est prévu : Python 3 de la distribution (comme `entrees-scan.py`), cosign 3.1.4 et crane 0.20.6, épinglés dans `mise.toml` (l. 21-22, `mise.lock`). Si un outil s'ajoute, il passera d'abord par le doc 04.

## Liens

docs/02 §5 et §7 ; [07b, tableau et `entrees-scan`](../07a-sbom-grype/README.md) ; [ADR 0004](../../../docs/adr/0004-vulnerabilites-vex.md) ; [brique 10](../10-independent-replay/README.md) ; [13a](../13a-licences/README.md).
