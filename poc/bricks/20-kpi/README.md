# Brique 20 : KPI supply-chain dérivés des attestations

Seuil (README, brique 20) : **0 écart avec le recalcul depuis les attestations**. Effort estimé : **1,5 pw**. Au-delà de 3 pw, décision avec le propriétaire.

Ouverte le 2026-11-24, choix du propriétaire « 20 KPI (Recommandé) », en réponse à la question « Pendant l'attente de R4, quelle brique de la phase 2c ouvre-t-on à sec (protocole, audit docs/04, estimation, rien sur le cluster) ? ». Heures comptées depuis 17:45:07 UTC, première lecture de docs/02 pour cette brique.

Règles reprises : projets jugés par le doc 04, rien de « Risqué » ; versions épinglées ; prédictions datées et commitées avant chaque mesure ; passages ratés archivés ; accord du propriétaire avant tout changement du cluster, des VM, de Zot ou de Grafana. Tout doit être consultable dans Grafana.

## État

**Règles d'alerte KPI déployées (26/11, note de 2026-11-26T08:09:27Z)** : accord « Comme tu veux mais avance » sur l'option recommandée ; [`alertes-kpi.patch`](alertes-kpi.patch) appliqué et commité (`96a66df7`), `KpiPassageEnRetard` et `KpiSignatureRefusee` posées sur `sc-stockage` par `observabilite.sh regles reference deployer` (`JALON=kpi20`) : promtool 17 règles et tests réussis, 17 règles saines et inactives, empreinte en place égale au commit ; par l'auditeur dans Grafana ([`alertes-verif.sh`](alertes-verif.sh)) 8 cas, 0 KO au second passage (le premier, 10 s après le redémarrage, lisait encore 15 règles : faute du contrôle, gardé) ; aucune alerte déclenchée ([prédiction et résultat](resultats/e14-predictions.md)). Prix : un rejeu sans `TAG_05` fera sonner `KpiPassageEnRetard`. Non exercés : déclenchement réel, Alertmanager. `promql-banc.sh` (étape 6) ne s'applique plus tel quel : le correctif est déjà dans HEAD.

**`genre()` et Chains v0.30.0 (25/11, note de 2026-11-25T21:26:34Z)** : deux correctifs éprouvés à sec, **non appliqués, non déployés** ([témoins](genre-temoins.patch), [exportateur et recalcul](genre-chains-v0300.patch), [banc](banc-genre.sh)) : rouge 2 écarts, vert 0, sept mutants refusés, 13 tâches sur 13 reconnues dans les sorties de v0.30.0, 301 lignes égales sur le vrai Zot ; second passage après relecture, mêmes résultats ([prédictions et résultat](resultats/e13-predictions.md), heures comprises). Les témoins ajoutent un contrôle qui manquait : au banc, rien ne regardait le genre lu par le recalcul. La montée de Chains reste bloquée ailleurs (porte, `ivpol`, scripts).

**VSA de `f5e6bcb0` (25/11, note de 2026-11-25T18:25:07Z)** : [seuil n° 5](resultats/e5-seuil-5.log) conforme à la [prédiction](resultats/e12-predictions.md) (105 valeurs, 0 écart, 44 signatures) ; `taux_l3_verifie` 1/4 → **2/4**, `taux_replay_identique` 2/4 → **3/4**.

**Scan du deb au calendrier (25/11, note de 2026-11-25T11:36:14Z)** : [seuil n° 4](resultats/e5-seuil-4.log) conforme (105 valeurs, 0 écart, 43 signatures ; deb 3 → 4 scans) ; la [prédiction](resultats/e11-predictions.md) est en écart sur la durée du Job (4 min 04 s au lieu d'environ 2 min, import de la base en 219 s, cause non établie).

**Premier scan du calendrier sous l'exportateur posé (25/11, note de 2026-11-25T09:49:44Z)** : [seuil n° 3](resultats/e5-seuil-3.log) conforme à la [prédiction](resultats/e9-predictions.md) (105 valeurs, 0 écart, 42 signatures ; `f5e6bcb0` 2 → 3 scans).

**Tableau posé et étape 7 écrite le 2026-11-24** (accords « Tableau seul (Recommandé) » et « Pose au rejeu, sans dates (Recommandé) »).
- **Pose du tableau** : [40 cas, 0 KO](resultats/e6-tableau-pose.log) (21:57:56 UTC). `journalisation.sh` (19b) le copie aussi ; **posé, non vu** : l'affichage réel reste à regarder. Les règles d'alerte restaient alors en correctif ; **déployées le 26/11** (plus haut).
- **Pose au rejeu** : `rejeu.sh` lance, en fin de rejeu, `kpi-pose.sh compte` puis `pose_rejeu`, **seulement si `TAG_05` est posé**. Prix non dit dans la question : un rejeu sans M5b (comme `plateforme-1`) perd la pose, car l'exportateur refuse un produit absent du catalogue ; le tolérer changerait le dénominateur, donc une décision. Si les règles sont déployées, `KpiPassageEnRetard` sonnerait après un tel rejeu. Essai à sec [12 cas, 0 écart](resultats/e7-essai-rejeu-2.log) au second passage (premier : [11 cas, 0 écart](resultats/e7-essai-rejeu.log), 21:59:41 UTC ; [prédiction](resultats/e7-predictions.md)) : relevé recalculé, autant de clés sans date que de clés réécrites, une de moins refusée, clé étrangère refusée. **`rejeu.sh` lui-même n'est contrôlé que par `bash -n`** : ni VM recréée, ni Loki vide, ni Grafana neuf exercés. Le contrôle `fuites` de la 08 cherche désormais le mot de passe de `kpi-journal` ([prédiction](resultats/e8-predictions.md), [banc sec, 11 cas, 0 écart](resultats/e8-essai-fuites.log), 22:17:05 UTC ; faux secrets, aucune VM), jamais lancé ainsi sur les VM. `essai-rejeu.sh` relancé après ce changement : [12 cas, 0 écart](resultats/e7-essai-rejeu-3.log). Affichage du tableau : le navigateur intégré refuse le certificat de la CA du PoC (note de 2026-11-24T22:19:37Z), il reste à regarder par le propriétaire. **Depuis le 25/11 (note de 2026-11-25T09:32:01Z)**, `fuites.sh` cherche aussi 6 fichiers des 07a, 09 et 10 ([prédiction et résultat](resultats/e10-predictions.md)) : premier passage non valable (variable du banc écrasée), [second, 23 cas, 0 écart](resultats/e10-essai-fuites-2.log) ; jamais lancé ainsi sur les VM.
- **Après un rejeu** : relire et commiter les clés, `releve-dates.py ecrire`, commit, `kpi-pose.sh pose` (accord).

**Étape 6 préparée à sec le 2026-11-24, avant la pose** ([prédictions et résultats](resultats/e6-predictions.md)). Tableau [`kpi-supply-chain.json`](../19b-journalisation/config/provisioning/dashboards/tableaux/kpi-supply-chain.json), 18 panneaux, 29 requêtes ; deux règles d'alerte en [correctif](alertes-kpi.patch), pas dans `alertes.yml` (un rejeu les déploierait avant le câblage de l'étape 7).
- Requêtes et règles jouées par `promtool` 3.13.5 : [28 cas, 0 écart](resultats/e6-promql-banc-3.log) au troisième passage (21:46:02 UTC) et au [quatrième](resultats/e6-promql-banc-4.log) (21:52:28, description d'un panneau retouchée), 14 mutants du tableau et 6 des règles refusés. Les deux premiers sont gardés : 15 écarts (un `NaN` mal écrit dans le témoin), puis 1 écart (`promtool` ne tient pas deux `NaN` pour égaux ; ses mutants « refusés » n'y prouvaient rien).
- Grafana 13.3.0 jetable : [22 cas, 0 écart](resultats/e6-tableau-banc.log), « Vulnérabilités et VEX » inchangé.
- Vrai Prometheus, par l'auditeur : [31 cas, 0 écart](resultats/e6-tableau-sec.log), attendus non aveugles (séries lues avant la prédiction).
- Non couvert : affichage réel dans Grafana, Alertmanager, pose.

**Étape 7, avant la décision.** Un rejeu réécrit les clés publiques de Chains, du scanner, des VEX et du TSA, « à relire et commiter » (`rejeu.sh` l. 188 pour celle des VEX), sans les commiter. Les digests des pipelines non épinglées changent d'un rejeu à l'autre : entre les deux rejeux du 23/11 (`construction-taches.log`, 15:59:44Z et 21:39:28Z), les deux journaux ne diffèrent que par les dates et les digests de pipeline (`43141b5d` puis `b8ff5ebb`, et l'ancienne pipeline témoin), sans commit sur `construction.sh` entre eux ; les versions plus anciennes diffèrent aussi, sans qu'on y sépare le contenu. Après un rejeu, `releve-dates.py verifier` rendrait donc « PÉRIMÉ » et `kpi-pose.sh pose` refuserait avant tout ssh ; `rejeu.sh` (`set -e`) s'arrêterait là. Déduit de ces journaux et du code, jamais observé. Aucune option ne donne l'âge des clés en fin de rejeu : cette date est, par décision, celle d'un commit.

Défaut corrigé au passage (note de 2026-11-24T21:52:26Z), sans lien avec ce choix : `verifier` lit les clés dans HEAD alors que `preparer` copie celles de l'arbre ; `kpi-pose.sh` refuse maintenant une clé de l'arbre différente de HEAD, avant tout ssh (essai : `resultats/e7-cles-*.log`).

Accord à demander : déploiement des règles (correctif appliqué et commité, redémarrage de Prometheus).

**Posé et seuil tenu le 2026-11-24** (accords « Liste, compte, pose (Recommandé) », [prédiction et résultat](resultats/e4-predictions.md)). Liste du proxy de Grafana : 10 cas, 0 KO (21:07:17 UTC). Compte `kpi-journal` : 5 cas (21:07:28). Exportateur et lecteur sur `sc-stockage` : 16 cas, 0 KO (21:07:28), 134 séries, 41 signatures vérifiées par OpenSSL 3.5.9 sous l'unité durcie. **Étape 5, le seuil : [8 cas, 0 écart](resultats/e5-seuil.log) (21:09:33), puis après un passage du timer (21:22:47) [8 cas, 0 écart](resultats/e5-seuil-2.log) (21:24:16)**, 105 valeurs comparées au recalcul signé : 102 issues des séries de Prometheus, lues par l'auditeur, et 3 égales par construction (`violations_licences`, deux `kev_delais`).

Réserves : délais des KEV égaux parce qu'aucune KEV n'est vue ; un journal bien formé mais faux ne serait pas vu ; `Wants` avec un lecteur en échec et les refus réseau non exercés ; aucune alerte sur l'âge du passage ; câblé dans `rejeu.sh` mais jamais rejoué (étape 7, plus haut) ; après un rejeu, clés et relevé à commiter, trois VEX à refaire ; tableau posé (étape 6, plus haut).

**Banc Grafana et Loki (20:47:52 à 20:50:15 UTC)** : le compte Viewer choisi pour le lecteur peut arrêter Loki, voir la correction sous la décision. Lecteur et délais des KEV conformes contre de vrais Grafana 13.3.0 et Loki 3.7.9 jetables (17 cas, 0 écart au troisième passage ; premier : 5 écarts, gardé). **Correction candidate** (décision « Chercher une correction à sec ») : `data_source_proxy_whitelist = 127.0.0.1:9090` dans `grafana.ini`, banc 40 cas, 0 écart ([journal](resultats/e4-banc-grafana-liste.log)). **Pose écrite à sec** : [`kpi-pose.sh`](kpi-pose.sh), [`kpi-journal.service`](systemd/kpi-journal.service), [`liste-proxy.sh`](../19b-journalisation/liste-proxy.sh) ; unité du lecteur essayée sur l'hôte (27 cas, 0 écart au cinquième passage, `ProtectHome` excepté). `kpi-pose.sh pose` refuse tant que le proxy mène à Loki. Accords à demander : liste, compte, pose.

**Étape 4 préparée à sec le 2026-11-24 (en-têtes des journaux : 20:29:15 à 20:35:32 UTC), rien n'est posé.** [Prédiction et résultat](resultats/e4-predictions.md). Banc à 15 témoins : **62 cas, 0 écart** au troisième passage (le premier avait un témoin mal placé ; le deuxième, 59 cas, 0 écart, précédait le traitement d'un journal malformé). Vrai Zot depuis l'hôte : **10 cas, 0 écart** sur 105 valeurs, dates des pins et des clés comprises, 41 signatures vérifiées. Unité durcie [`kpi.service`](systemd/kpi.service), essayée sur l'hôte sans sudo : **23 cas, 0 écart** aux deuxième et troisième passages, sous Python 3.14 et 3.13. Ajouts : vecteur de test RFC 6979 vérifié au départ, [relevé versionné des dates de git](releve/dates-git.tsv), heure du dernier passage, [lecteur de Loki](../../../tools/metrics-exporter/lecteur_loki.py) séparé. `sc-stockage`, Prometheus, Grafana et les variables propres de l'unité ne sont pas exercés ; 0 KEV dans le vrai Loki.

**Essai openssl fait le 2026-11-24 (20:01:07 et 20:01:21 UTC).** [Prédiction et résultat](resultats/e3b-predictions.md) : l'exportateur peut vérifier les signatures avec `/usr/bin/openssl` et les quatre clés publiques, sans cosign. Banc à 14 témoins : **26 cas, 0 écart** (vérifiées : 0 écart avec le recalcul signé ; comptées : 39 écarts, ceux prédits). Vrai Zot depuis l'hôte : **8 cas, 0 écart**, 41 signatures vérifiées, 0 par une clé étrangère. Mode obligatoire (`SIGNATURES`), **décision du 24/11 : « openssl (Recommandé) »**, rien n'est posé. `sc-stockage` a OpenSSL 3.5.9 et Python 3.13.5 ([lu](resultats/e4-stockage-versions.log), 20:07:20 UTC) ; la vérification n'y a pas tourné, l'unité durcie non plus ; les délais des KEV ne sont pas couverts (lignes de `entrees-scan`, non vérifiées).

**Étape 3 faite le 2026-11-24 (banc jetable, 19:42:34 UTC).** [Prédiction et résultat](resultats/e3-predictions.md) : **10 cas, 0 écart**, au premier passage. 9 sujets témoins dans un Zot jetable sans réseau. Sur les 7 sujets bien signés, 0 écart entre le recalcul et l'exportateur ; sur les 2 à signature fausse, **14 écarts, exactement ceux prédits** : l'exportateur, qui ne vérifie pas, masque une KEV ouverte et compte une VSA et une provenance fausses. Recalcul paramétré pour le banc, non-régression sur la plateforme à 19:42:45 UTC : 10 cas, 0 écart, 0 ligne `KPI|` différente. Exportateur écrit ([`tools/metrics-exporter`](../../../tools/metrics-exporter/metrics_exporter.py)), **non posé**. Lancé depuis l'hôte sur le vrai Zot en lecture anonyme (19:47:15 UTC, [journal](resultats/e3-exportateur-zot.log)) : 56 valeurs comparées au recalcul signé, **0 écart**.

**Étape 2 faite le 2026-11-24 (recalcul de référence, signatures vérifiées, 18:55:04 UTC).** [Prédiction et résultat](resultats/e2-predictions.md) : **10 cas, 0 écart** (second passage à 19:32:02 UTC : 10 cas, 0 écart, 0 ligne de différence) ; 37 attestations listées et vérifiées, 0 par la clé étrangère. Provenance de Chains vérifiée 4/4, VSA `SLSA_BUILD_LEVEL_3` 1/4, replay identique 2/4, 0 KEV ; pour `f5e6bcb0` et le deb, Prometheus est égal au recalcul. Constat : Loki ne voit pas tous les scans (3 sur 5 pour `sample-app`). Rien n'est posé.

**Étape 1 faite le 2026-11-24 (relevé anonyme de Zot, 18:26:24 UTC).** [Prédiction et résultat](resultats/e1-predictions.md) : **12 cas, 2 écarts**, tous deux des fautes de la prédiction. Les 4 énoncés en cause sont des témoins négatifs voulus (J6, G6) qu'elle n'avait pas comptés. Pour les produits, les builders et les fermetures, tous les énoncés sont lisibles et nomment leur sujet. Signatures non vérifiées à cette étape.

Aperçu des produits, énoncés non vérifiés : 4 sujets (`sample-app` `3a7ca1b1` et `f5e6bcb0`, deb `60f25f5c`, rpm `07b7bd6f`). Tous ont une provenance ; 3 ont un scan, 3 un VEX et 2 une VSA. Le digest en service, `f5e6bcb0`, n'a pas encore de VSA. L'historique des scans dans Zot commence au rejeu du 23/11, et celui de Loki aussi (mesuré, `e1-loki-anciennete.log`) : un rejeu de zéro remet les deux à zéro.

**Heures de la 20** (2026-11-24, `date -u`) : 17:45:07 à 17:50:31 (ouverture, carte), 18:23:30 à 18:27:23 (étape 1), 18:27:23 à 18:30:36 (relecture, Loki, corrections), soit 0 h 12 min 30 s ; étape 2 de 18:49:15 à 18:56:03 (6 min 48 s). Corrections et second passage de 19:32:00 à 19:32:27 (0 min 27 s), attente du propriétaire non comptée. Étape 3 de 19:35:55 à 19:47:45 (11 min 50 s, relecture et complément compris). Essai openssl de 19:55:31 à 20:02:05 (6 min 34 s). Relevé d'OpenSSL et corrections de 20:02:05 à 20:05:11 (3 min 06 s). Décision et lecture des versions de 20:07:03 à 20:07:37 (0 min 34 s). Étape 4 à sec de 20:18:37 à 20:35:53 (17 min 16 s). Banc Grafana de 20:43:08 à 20:54:14 (11 min 06 s). Correction et pose à sec de 20:55:04 à 21:00:36 (5 min 32 s), attente du propriétaire non comptée. Relecture et corrections de 21:00:36 à 21:03:58 (3 min 22 s). Poses, seuil et notes de 21:07:03 à 21:13:10 (6 min 07 s), attente du timer non comptée. Étape 6 à sec et relecture de 21:35:29 à 21:54:26 (18 min 57 s). Pose, étape 7 et relecture de 21:57:46 à 22:06:48 (9 min 02 s), attente du propriétaire non comptée. `fuites` et relances de 22:14:18 à 22:19:49 (5 min 31 s). Le 25/11, `fuites` (07a, 09, 10) de 09:29:23 à 09:32:01 (2 min 38 s) ; contrôles en lecture et prédiction e9 de la même journée non comptés à part. Seuil n° 3 de 09:49:07 à 09:49:44 (0 min 37 s). Prédiction du seuil n° 4 de 10:41:17 à 10:41:48 (0 min 31 s), seuil et notes de 11:34:27 à 11:36:14 (1 min 47 s), attente du scan non comptée. Seuil n° 5 : prédiction de 18:13:43 à 18:14:21 (0 h 00 min 38 s), seuil et notes de 18:24:20 à 18:25:07 (0 h 00 min 47 s), attente du passage non comptée. Total **2 h 05 min 40 s**. Majorant, calculé avant l'étape 4, par la méthode de la 05 (écarts d'au plus 1 h entre commits de `poc/bricks/20-kpi`) : 42 min 16 s ; il compte à tort l'écart de 17:50:31 à 18:26:20, qui contient la clôture de la 05 et la 07c. Estimation : 1,5 pw.

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

Décision du 2026-11-24 sur la **vérification des signatures par l'exportateur** (écrite le 2026-11-24T20:07:20Z), verbatim : **« openssl (Recommandé) »**. Option retenue telle que posée : « Paquet openssl de Debian sur sc-stockage, rien à installer s'il y est déjà (à vérifier). Verdict docs/04 proposé « Sain » ; 14 CVE ouvertes dans trixie, aucun titre ne nomme la vérification ECDSA. Prix : 4 clés publiques à poser et à reposer après chaque rejeu. » Options écartées : « cosign épinglé », « Ne pas vérifier ». Donc `SIGNATURES=verifiees` à la pose, et pas de renommage des séries. Cette décision ne vaut pas accord de pose (étape 4).

Décision du 2026-11-24 sur **l'accès du lecteur à Loki** (écrite le 2026-11-24T20:41:04Z), verbatim : **« Compte Grafana Viewer (Recommandé) »**. Prix accepté, tel que posé : « un compte à créer, un mot de passe sur la VM, lecture de tous les journaux et des métriques, câblage dans rejeu.sh ». Elle ne vaut ni accord de pose, ni accord de création du compte. Options comparées, aucune n'étant neutre :

| Option | Pouvoir sur les journaux | Secret sur `sc-stockage` | Fidélité à « Loki, 720 h » |
|---|---|---|---|
| Compte Grafana dédié, rôle Viewer | lit tous les journaux et les métriques, n'écrit pas dans Loki | un mot de passe, lisible du seul lecteur | oui |
| Certificat client de la CA du PoC | lit **et écrit** tous les journaux (limite de D16, 19b, README l. 466) | une clé privée | oui |
| Journal local (`journalctl -u entrees-scan.service`, par root avant le lecteur) | lit cette seule unité | aucun | non : ce n'est pas Loki, rétention de journald non mesurée |

Seule la première a été essayée, avec le compte `auditeur`, depuis l'hôte.

**Correction (note de 2026-11-24T20:54:14Z)** : la décision ci-dessus a été prise sur un prix incomplet. [Mesuré au banc](resultats/e4-predictions.md) (20:48:55 et 20:50:15 UTC) : un compte Viewer ne peut écrire dans Loki ni par POST ni par PUT (403), mais il **arrête Loki** par un GET à travers le proxy de Grafana. Le compte `auditeur` a le même rôle. Reconfirmé par le propriétaire avec ce prix corrigé (réponse reçue avant 2026-11-24T20:55:04Z), verbatim : « Compte Grafana Viewer (Recommandé) ». Le défaut de la 19b a une correction éprouvée au banc, non posée : voir l'état.

Reste à poser : les licences (le recalcul donne « source absente », 0 prédicat mesuré dans Zot).

## Après l'étape 2 : décision et limites

- **« Taux L3 vérifié » (docs/02)** : décision du propriétaire du 24/11, verbatim **« VSA seule (Recommandé) »**. L3 vérifié = VSA de replay qui porte `SLSA_BUILD_LEVEL_3`. Les deux lectures comparées :
  - provenance de Chains vérifiée (signature, `builder.id`, PipelineRun, signature d'image) : **4/4**. La politique de la porte n'est pas rejouée, donc « L3 » n'y est pas prouvé ; afficher le deb en L3 contredirait la décision du 12/11 (« Bit identique seul »). Affiché à côté, sous son nom littéral ;
  - VSA de replay qui porte `SLSA_BUILD_LEVEL_3` : **1/4** le 24/11, **2/4** depuis la VSA de `f5e6bcb0` (25/11). Le deb ne l'aura jamais, par décision ; le rpm non plus tant qu'il n'a pas de VSA.
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

Python 3 de la distribution (comme `entrees-scan.py`), cosign 3.1.4 et crane 0.20.6, épinglés dans `mise.toml` (l. 21-22, `mise.lock`). **Un outil s'ajoute si l'exportateur vérifie** (note de 2026-11-24T20:05:11Z) : `openssl` de Debian 13, version du paquet de la VM, non épinglée par mise. [docs/04](../../../docs/04-sante-projets.md) n'avait pas de verdict pour lui : relevé du 2026-11-24 ([journal](resultats/sante-openssl.log)), verdict proposé « Sain ».

## Liens

docs/02 §5 et §7 ; [07b, tableau et `entrees-scan`](../07a-sbom-grype/README.md) ; [ADR 0004](../../../docs/adr/0004-vulnerabilites-vex.md) ; [brique 10](../10-independent-replay/README.md) ; [13a](../13a-licences/README.md).
