# Brique 20, étape 3 : banc jetable des KPI, prédiction

Prédiction écrite le 2026-11-24T19:42:28Z (`date -u`), commitée avant tout lancement du banc : aucune de ses pièces n'a tourné, seulement un contrôle de syntaxe et le calcul de la table des attendus. Le premier lancement est le passage 1, archivé même raté. Sans accord : rien de partagé, rien de téléchargé. Plan relu par le conseiller.

## Ce qui est écrit pour cette étape

- [`tools/metrics-exporter/metrics_exporter.py`](../../../../tools/metrics-exporter/metrics_exporter.py) (`b22c696cb22a9948`) : l'exportateur, à l'emplacement que nomme docs/02 §7. Bibliothèque standard, ni git ni cosign. **Il ne vérifie pas les signatures** : c'est la seule forme possible sans installation, et le choix reste à poser (étape 4). Il n'importe pas `kpi.py`, pour que la comparaison ne compare pas un code à lui-même. Il n'est pas posé.
- [`recalcul.py`](../recalcul.py) (`09fa8e40d295f01c`) : paramétré pour le banc (`BANC=1`). Sans cette variable, les valeurs de la plateforme sont inchangées.
- [`banc.sh`](../banc.sh) (`9f9457b961f7cf13`), [`banc_temoins.py`](../banc_temoins.py) (`f33a37ff11113f1e`), [`banc_comparer.py`](../banc_comparer.py) (`674f20097d9cddd0`) : Zot 2.1.22 et clés jetables dans un espace de noms réseau vide, 9 sujets témoins, comparaison.

## Témoins

Provenances et signatures d'image au format de Chains (tags `.att` et `.sig`, formes relevées sur `f5e6bcb0` à 19:39:43 UTC). Scans, VSA et VEX en bundles sigstore publiés en référents, comme `scanner.sh`. Dates littérales.

| Sujet | Contenu | Attendu du recalcul |
|---|---|---|
| `banc-complet` | provenance PipelineRun et TaskRun, scan (3 entrées, 2 écartées, 1 KEV écartée), VSA PASSED L3, VEX | tout à 1, couverture 2/3 et 1/1 |
| `banc-sans-vsa` | provenance, scan sans entrée | replay 0, couvertures « sans objet » |
| `banc-vsa-failed` | VSA FAILED bien signée, qui porte pourtant L3 ; 1 KEV ouverte | replay 0, L3 0 |
| `banc-forge` | scan signé avec 1 KEV ; **scan plus récent sans entrée, VSA PASSED L3 et VEX signés par une clé étrangère** | les trois faux écartés : KEV ouverte 1, L3 0, VEX 0 |
| `banc-prov-forgee` | provenance et signature d'image par la clé étrangère | provenance 0 |
| `banc-prov-seule` | provenance seule | scan « absent », jamais 0 |
| `banc-prov-tache` | provenance de TaskRun seule | provenance 0 |
| `banc-sans-sig` | provenance sans signature d'image | provenance 0, 1 PipelineRun |
| `banc-kev` | 3 scans : deux KEV ouvertes le 01/11, l'une écartée par un VEX le 08/11 à 12:00, l'autre absente le 10/11, une troisième ouverte le 10/11 | délais 7,5 j et 9 j, une ouverte |

**Règle écrite** : une VSA PASSED vérifiée suffit, même si une FAILED est plus récente. Recalcul et exportateur l'appliquent tous deux.

## Cas comparés (10)

Dans `recalcul.py` (5) :
1. attestations vérifiées = listées − 4 signatures fausses : **19** sur 23 (10 provenances, 8 scans, 3 VSA, 2 VEX). Comptés à la main sur la table ;
2. témoin (troisième clé, qui ne signe rien) : **0** ;
3. scans dont le nombre d'entrées diffère de leur résumé : **0** ;
4. lignes d'entrées lues : **oui** ;
5. sujets : **9**.

Dans `banc_comparer.py` (5), attendus écrits à la main dans le script :
6. recalcul : **0** valeur différente sur 122 ;
7. exportateur : **0** valeur différente de ses propres attendus, sur 122 ;
8. écarts recalcul contre exportateur hors signatures fausses et taux : **0** ;
9. écarts dus aux signatures fausses : **14** (9 sur `banc-forge`, 2 sur `banc-prov-forgee`, 3 taux de plateforme ; liste ci-dessous) ;
10. énoncés refusés pour leur forme par l'exportateur : **0** : les faux sont bien formés.

Un onzième contrôle, dans `banc.sh` : Zot arrêté, l'exportateur rend le code 2 et laisse le fichier inchangé.

Les 14 écarts prédits : `banc-forge` (couverture_vex_entrees, couverture_vex_kev, kev_ouvertes, l3_verifie, replay_identique, scan_date, scan_entrees, scan_kev, vex_verifies : 9), `banc-prov-forgee` (provenance_chains_verifiee, provenances_pipelinerun : 2), taux de plateforme (3). 9 + 2 + 3 = 14.

`entrees-scan.py` : **6** lignes d'entrées, **3** listes émises, **4** résumés (le quatrième passage ne trouve rien de neuf).

## Moins sûr

- `cosign import-key-pair` sur une clé EC en PKCS8 non chiffrée, et Zot acceptant ces manifestes fabriqués : jamais essayés ici.
- **`banc-forge`** : cosign face à un bundle vrai et un bundle faux du même type. S'il refuse l'ensemble, un compte autorisé à écrire pourrait masquer un vrai scan au recalcul : ce serait un constat, pas un défaut du banc.
- **`banc-prov-forgee`** : le motif d'erreur de `cosign verify` sur un `.sig` faux n'a jamais été vu par le recalcul, qui s'arrête sur un motif inconnu.

## Hors banc

Horodatage (TSA), dates des clés et des pins (git), Prometheus et Grafana, chaîne Alloy et Loki (les lignes du vrai `entrees-scan.py` sont lues dans un fichier). Le recalcul l'annonce par une ligne `HORS BANC|`.

## Non-régression du recalcul (troisième passage réel)

`SUFFIXE=-3 recalcul.sh`, lecture seule, après le banc : **10 cas, 0 écart**, et **0 ligne `KPI|`** différente de `e2-recalcul-2.log`, sauf si un nouveau scan a été publié depuis 19:32 UTC.

## Constat d'orientation (lu, pas mesuré en service)

Dans la configuration **versionnée** de Zot (`08-trust-plane/stockage/zot.json`), les motifs sont `**`, `builds/**`, `builds/fermetures/**`, `builds/scan/**`, `builds/vex/**`, `horodatage/**`, `signes/**` et `vulndb/**`. **`builds/vsa/**` n'a pas de motif propre** : `poc-ecriture`, `poc-build`, `poc-images` et `poc-replay` peuvent y créer un référent. Un exportateur qui ne vérifie pas compterait une VSA posée par la zone de build.

## Résultat (note de 2026-11-24T19:43:10Z)

**Banc** ([journal](e3-banc.log)) : passage 1, 2026-11-24 à 19:42:34 UTC, dépôt `9f97bcad`, scripts `b91d611338972054`, cosign 3.1.4, Zot 2.1.22, exportateur sous Python 3.14.4 de l'hôte (celui de `sc-stockage` n'a pas été exercé). **10 cas, 0 écart**, et le contrôle « Zot arrêté » conforme (code 2, fichier inchangé). Espace de noms sans route ; dossier du banc effacé.

- Recalcul : **19/23** attestations vérifiées, les 4 signatures fausses écartées ; témoin 0 ; 122 valeurs égales aux attendus écrits à la main.
- Exportateur : 122 valeurs égales à ses propres attendus ; **0 écart avec le recalcul sur les 7 sujets bien signés**.
- **14 écarts, tous dus aux signatures fausses, exactement la liste prédite.** Le plus parlant : `banc-forge`, KEV ouverte 1 au recalcul et **0 à l'exportateur** ; L3 vérifié 0 et **1**.
- Les trois points « moins sûrs » se sont bien passés : clés importées, manifestes acceptés, et cosign rend le vrai scan quand un faux du même type est à côté (`scan 2/1/0`). `cosign verify` sur un `.sig` faux donne un motif reconnu par le recalcul.
- KEV : délais 648 000 s (7,5 j) et 777 600 s (9 j), une ouverte ; les trois lignes égales dans les deux outils, à partir des lignes du vrai `entrees-scan.py` (6 entrées, 3 listes émises, 4 résumés).

**Non-régression** ([journal](e2-recalcul-3.log)) : 19:42:45 UTC, dépôt `9f97bcad`. **10 cas, 0 écart**, 105 lignes `KPI|`, **0 différente** de `e2-recalcul-2.log`.

### Ce que cela ne montre pas

- Les attendus, les témoins et les deux outils viennent de la même session : une erreur commune de lecture d'une règle ne se verrait pas.
- L'exportateur n'a pas encore lu le vrai Zot, et n'est pas posé.
- Écrire ces faux dans le vrai Zot demande un compte : le banc n'a ni comptes ni politique. La configuration versionnée le permet à `poc-build` et `poc-images` pour `builds/vsa/**`, pas pour `builds/scan/**` ni `builds/vex/**` (motifs plus précis, donc prioritaires). Pour les provenances, `poc-build` pousse `.att` et `.sig`, puisque c'est le compte de Chains. Donc, sur les faux du banc, la KEV masquée demande `poc-ecriture` ou `poc-scan`, le VEX `poc-vex`, et la VSA ou la provenance un compte de la zone de build.
