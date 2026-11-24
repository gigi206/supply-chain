# Brique 20, étape 2 : recalcul de référence, signatures vérifiées, prédiction

Prédiction écrite le 2026-11-24T18:54:59Z (`date -u`), commitée avant le lancement. Sans accord : lecture seule (Zot en anonyme, Grafana par l'auditeur, git) ; rien n'est écrit dans Zot, sur les VM, dans le cluster ni dans Grafana. Plan relu par le conseiller.

## Ce qui est mesuré

[`recalcul.py`](../recalcul.py) (`b74f7c2d8294d078…`), calculs purs dans [`kpi.py`](../kpi.py) (`a9101b4c7ecb18c8…`), lancés par [`recalcul.sh`](../recalcul.sh) ; journal `resultats/e2-recalcul.log`, jamais réécrit.

- **Sujets** : `sample-app`, `sample-app-deb` et `sample-app-rpm`, tous les digests vus par un tag (décision « Produits, tous digests »).
- **Attestations** : chacune est listée (couches du `.att`, referrers), puis vérifiée par cosign avec la clé publique versionnée de son émetteur. L'énoncé vérifié est relu pour son type et son sujet. cosign rend le code 1 pour absent, non vérifié et injoignable : il n'est appelé que si la liste n'est pas vide, et toute erreur réseau ou motif inconnu arrête le script.
- **Témoin négatif** : les mêmes appels avec `g6-temoin-cle-publique.pem`.
- **Dates, jamais des âges** : l'âge change entre le recalcul et l'exportateur.
- **« Taux L3 »** : deux comptes nommés. `taux_provenance_chains_verifiee` (signature de Chains, `builder.id` et `buildType` attendus, un PipelineRun au moins, signature d'image) et `taux_vsa_slsa_build_level_3` (VSA de replay qui porte `SLSA_BUILD_LEVEL_3`). Aucun n'est appelé « L3 vérifié » : la politique de la porte n'est pas rejouée, et le propriétaire a décidé le 12/11 de ne pas revendiquer `SLSA_BUILD_LEVEL_3` pour le deb (« Bit identique seul »). Choix à poser.
- **Pins** : provenance de PipelineRun la plus récente par sujet. La date est celle du premier commit qui écrit le digest dans un fichier de configuration (hors `resultats/`, `.md`, `.log`, `.patch`, `*_test.rego` et cette brique).
- **Délai des KEV** : Loki, 719 h, par dépôt. **Les lignes de `entrees-scan` n'ont pas de digest** (relu dans le script et sur une ligne réelle) : `builds/sample-app` y mélange `3a7ca1b1` puis `f5e6bcb0` depuis la bascule. Pour un délai de correction, c'est voulu : une image corrigée est un autre digest du même dépôt. Les scans sont tirés des résumés (« liste émise »), parce qu'un scan sans entrée n'émet aucune ligne.
- **Calculs purs** : [`essais_kpi.py`](../essais_kpi.py), jeu synthétique, 16 cas, 0 écart (déjà exécuté). Il n'y a aucune KEV dans la plateforme : c'est le seul exercice du délai de correction.

## Lu pendant l'orientation, donc pas prédit

Commandes lancées à 18:49:15 UTC et après, avant ce texte, par des scripts du scratchpad non archivés :
- provenances vérifiées : 6 (`3a7ca1b1`), 8 (`f5e6bcb0`), 8 (deb), 2 (rpm), une sur deux venant d'un PipelineRun ; une signature d'image par sujet ;
- scans vérifiés : 3, 2, 3, 0 ; VEX : 1, 1, 1, 0 ; VSA : 1 (`SLSA_BUILD_LEVEL_3` et `POC_REPLAY_BIT_IDENTIQUE`), 0, 1 (`POC_REPLAY_BIT_IDENTIQUE` seul), 0 ;
- derniers scans : 6 entrées dont 5 écartées, 5 dont 5, 67 dont 23 ; 0 KEV ;
- séries de Prometheus : mêmes comptes pour `f5e6bcb0` et le deb ; une ligne de Loki ;
- dates git des clés et des digests, avec un filtre un peu plus large que celui du script (`.patch` et `*_test.rego` n'étaient pas exclus).

Donc attendus, sans valeur de prédiction : `taux_provenance_chains_verifiee` 4/4, `taux_vsa_slsa_build_level_3` 1/4, `taux_replay_identique` 2/4, couverture VEX 5/6, 5/5, 23/67, rpm « absent » ; couverture des KEV et délais « sans objet » ; licences « source absente » ; trois pins « non épinglé dans git » (les bundles `tekton/pipelines` de `3a7ca1b1`, `f5e6bcb0` et du deb, écrits seulement dans des journaux).

## Cas comparés (10)

1. **Attestations vérifiées = listées** : **37** (24 provenances, 8 scans, 2 VSA, 3 VEX). Les comptes listés viennent de l'étape 1.
2. **Témoin** : **0** attestation vérifiée par la clé étrangère. Non lu.
3. **Loki, scans dont le nombre d'entrées diffère de leur résumé** : **0**. Non lu ; peu sûr si un scan a deux fois le même couple (identifiant, paquet).
4. **Loki, lignes d'entrées lues** : oui (une ligne lue en orientation).
5. **Sujets produits** : **4** (étape 1).
6. **TSA, sujets dont une provenance n'est couverte par aucun bundle horodaté** : **aucun**. Non lu. Cas le moins sûr : le CronJob d'horodatage traite peut-être des dépôts choisis, et `horodatage/bundles` n'a pas été relevé pour le rpm.
7. et 8. **Prometheus, `sample-app`** : la date désigne un seul sujet (attendu `f5e6bcb0`) ; entrées, écartées, KEV, KEV écartées égales au recalcul signé.
9. et 10. **Prometheus, `sample-app-deb`** : de même (`60f25f5c`).

Bilan attendu : **10 cas, 0 écart**. Réellement non lus : les cas 2, 3 et 6.

## Hors périmètre

- Clés : celle des tâches (Trusted Resources) et celle du lien OpenPGP (09) ne signent aucune attestation de produit, donc non datées ici.
- La politique de la porte (`ec`, tâches de confiance, Kata, fermetures) n'est pas rejouée.
- L'exportateur n'a pas git : les dates des pins et des clés devront lui être fournies par un relevé versionné (étape 4).

## Résultat (note de 2026-11-24T18:56:03Z)

[Journal](e2-recalcul.log) : passage du 2026-11-24 à 18:55:04 UTC, dépôt `e6219410`, scripts `e08485330baef30b`, cosign 3.1.4. **10 cas, 0 écart**, code 0.

| KPI | Valeur |
|---|---|
| Attestations vérifiées / listées | **37/37** ; clé étrangère : 0 vérifiée |
| Provenance de Chains vérifiée | **4/4** |
| VSA qui porte `SLSA_BUILD_LEVEL_3` | **1/4** (`3a7ca1b1`) |
| Replay identique | **2/4** (`3a7ca1b1`, deb) ; `f5e6bcb0` attend R5, le rpm n'a pas de VSA |
| KEV ouvertes | 0 pour les trois sujets scannés ; rpm « absent » |
| Couverture VEX, entrées | `f5e6bcb0` 5/5, `3a7ca1b1` 5/6, deb 23/67, rpm « absent » |
| Couverture VEX, KEV ; délai de correction | sans objet (0 KEV) |
| Licences | source absente |
| Pins | 42 lignes, 39 datées ; 3 « non épinglé dans git » (bundles de pipeline de `3a7ca1b1`, `f5e6bcb0` et du deb) |
| Clés (dernier changement) | Chains et TSA 2026-11-23T22:12:12Z ; scanner et VEX 23:36:23Z ; VSA 2026-11-03T10:02:16Z |

- **Horodatage** : toutes les provenances sont couvertes (6/6, 8/8, 8/8, 2/2) par un bundle vérifié avec la chaîne du TSA. Une chaîne étrangère n'a pas été essayée ici (J5 l'a fait, `j5-tsa-etrangere`).
- **Prometheus** : pour `f5e6bcb0` et le deb, les séries de `entrees-scan` sont égales au recalcul signé (5, 5, 0, 0 et 67, 23, 0, 0).

**Constat non prédit : Loki ne voit pas tous les scans.** Zot a 5 scans signés de `sample-app`, Loki 3. Relevé [`e2-loki-scans.log`](e2-loki-scans.log) (18:55:27 UTC, lancé **sans prédiction commitée**, pour expliquer cet écart) :
- `3a7ca1b1`, scan du 23/11 à 22:28:25Z : absent. Un autre scan a suivi à 22:30:42Z ; or `entrees-scan` passe toutes les 15 min et n'émet que le scan le plus récent ;
- `f5e6bcb0`, scan du 24/11 à 13:31:32Z : absent. La cible `SCANS` n'a été basculée vers ce digest qu'ensuite (07c).

Conséquence pour le KPI « délai de correction des KEV » (décision « Loki, 720 h ») : une KEV vue seulement dans un scan intermédiaire, ou sur un digest pas encore dans `SCANS`, n'est pas comptée, et le rpm n'est pas suivi. Les dates de scan, elles, sont exactes (`scannedAt`). Aucun effet aujourd'hui (les 8 scans signés des produits ont chacun 0 KEV, relus un par un).

**Heures de l'étape 2** : de 18:49:15 UTC (orientation) à cette note, 6 min 48 s.
