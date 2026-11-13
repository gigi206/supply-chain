# Rejeu de zéro S5b : prédictions (11/11/2026, 23:10 UTC, avant tout lancement)

Décisions du propriétaire : « 1 ok », « 2 ok », « 3 ok » (carte et relevés : README de la 08, section « Rejeu de zéro S5b ») ; « Oui, prépare-les » pour les cinq modifications. Aucune n'est un accord de lancement. Le lancement viendra après la tâche planifiée du 21/11/2026 à 16:00 UTC, sur un accord nommé, avec `POUSSER_VSA=1` et l'accord du push de la VSA.

Commande prévue (racine du dépôt) : `DISTRO=rke2 POUSSER_VSA=1 mise run confiance:rejeu -- s5b`, journal `resultats/rejeu-s5b.log`.

## Étapes actuelles (jusqu'à « J8 (contrôle 7) » et « 07a (G6) »)

| # | Prédiction | Confiance | Fondement |
|---|---|---|---|
| A1 | RKE2 s'installe avec `egress-selector-mode: disabled` et toutes les étapes qui font `kubectl exec` ou `kubectl logs` passent | Moyenne | Réglage jamais posé à l'installation, seulement en place le 10/11 |
| A2 | Toutes les étapes actuelles passent avec 0 KO, comme les 06/11, avec le code de HEAD | Moyenne | Relevé 1 : une seule dérive bloquante, déplacée ; plusieurs branches seulement lues dans le code |
| A3 | Images reproduites : `outils-prefetch@68e0ae70`, `outils-horodatage@c7bebae2`, `3a7ca1b1`, `rattrapage c3992728`, porte `e77994c2` ; bundles `publier-image d21931f3`, `publier-fermeture 7fa92ad3` | Haute | Deux rejeux de zéro (03/11, 06/11) |
| A4 | Le test 6 de J8 détecte `builds-sans-internet` absente et suit le chemin d'origine, conforme | Moyenne | Branche jamais rejouée depuis sa réécriture |
| A5 | Témoins de la porte (`reglec`, `slsa`, `attseule`, `decision3`, contrôles 6 et 7) inchangés sous `porte.rego` étendu par la 06 | Moyenne | Lecture du code ; sample-app admise avec ces fichiers le 11/11 |

## Bloc 08c

| # | Prédiction | Confiance |
|---|---|---|
| B1 | `h1_api` : API relancée en moins de 300 s, au moins un 429 sur la rafale d'Events, OpenBao, Kyverno et TSA répondent | Haute |
| B2 | `h4_bloque` sans `h3_audit` avant : pare-feu d'hôte actif, SSH, API et Zot joignables, test 6 conforme avec `T6_FERMES` | Moyenne |
| B3 | S1 : chemins `kv/` écrits et relus égaux, Chains injecté, `zot-chains` absent | Haute |
| B4 | `h5_limites` : 13 correctifs posés, OpenBao descellé, témoins conformes | Moyenne : premier passage sur des objets créés par le rejeu |
| B5 | `h5_deny` sans H2 en Audit avant : 4 règles en `Deny`, témoins refusés pour leur motif | Haute |
| B6 | `h5_roles` : premier passage complet de la version corrigée, OK (le témoin attend « patched ») | Moyenne |
| B7 | `sortie-builds.sh rejeu` : NotIn `["prefetch-gomod","prefetch-deb"]`, invariants conformes | Haute |
| B8 | « J8 (résolveurs) » : 4 lecteurs de Secrets, sans `cilium-operator` | Haute |

## Bloc 06

| # | Prédiction | Confiance |
|---|---|---|
| C1 | Amorce `amont/library/debian@7378260c`, depuis le cache OCI de l'hôte | Haute |
| C2 | `entrees/sample-app/packaging-deb@c1719b13` | Haute |
| C3 | Bundles `prefetch-deb 4dac0609`, `construire-builder 746c2e11`, `prefetch-gomod` v2 `170bef53`, `preparer-deb 588617b8`, `construire-deb 3726ff0b` : mêmes digests, aucune nouvelle signature de tâche | Haute |
| C4 | Image de build `749d746c`, deux fois | Moyenne : dépend de snapshot.debian.org et de mmdebstrap sur un nœud neuf |
| C5 | Fermetures `bb7599a2` (deb) et `50dc73f7` (Go et npm) | Moyenne pour le deb, faible à moyenne pour `sources` (amont Go et npm) |
| C6 | `builds/sample-app-deb@039949f9`, deux fois, deb `0b489d43` | Moyenne |
| C7 | Bundle de la pipeline `sample-app-deb` **différent** de `82c8373d` (signature ECDSA), lu dans `pipeline.ref` sans écart | Haute |
| C8 | S4d3 : `retirer` sans effet, Trigger et CronJob posés, les deux chemins rendent `039949f9`, tête `6391fd43` | Moyenne |
| C9 | Porte : deb en succès sans violation, enveloppes toutes couvertes, VSA et scan refusés ; sample-app en succès, toutes couvertes, VSA et scan `ok` | Moyenne : le scan dépend de l'âge de la base grype au moment du jugement |

## Fin

| # | Prédiction | Confiance |
|---|---|---|
| D1 | `fuites` : aucun secret dans les journaux ; CIS sans attendu | Haute |
| D2 | Durée d'exécution : environ 3 h 15 (entre 2 h 45 et 4 h) | Moyenne |
| D3 | Zot neuf : les fermetures altérées de S5a absentes | Haute |

## Limites connues

- Même hôte : PKI, `taches.key`, caches OCI et fichiers de `$W` (S1 à S4d) gardés. Le rejeu ne prouve pas la variante B, sur un hôte neuf.
- `s4d prealables` n'est pas rejoué : `digest-attendu` est celui du 11/11.
- La première suppression réelle de la rétention de Zot repart de zéro, 14 jours après le rejeu.

## Note du 13/11/2026 (2026-11-13T08:59:45Z) : S5b arrêté à la première étape (rien n'est réécrit)

Lancé à 08:54:01 UTC, code 1 à 08:54:05 UTC, pendant `vm.sh detruire` ([journal](rejeu-s5b.log)). La limite connue « fichiers
de `$W` (S1 à S4d) gardés » est fausse : `vm.sh detruire` efface `$W` (l. 152). A1 à D3 ne sont pas mesurées. Détail : README
de la 08, additif du 13/11/2026.

## Note du 13/11/2026 (2026-11-13T09:01:19Z), avant lancement : rebâti de la plateforme seule (rien n'est réécrit)

Décision du propriétaire : « Oui, avec push » à « Je rebâtis la plateforme seule, jusqu'à « J8 (résolveurs) » ? » (push de
la VSA de la brique 10 compris, par `POUSSER_VSA=1`). Avant le lancement, le reliquat en lecture seule de `$W`
(`s4d-06/essais`) est levé (`chmod -R u+w` puis `rm -rf` sur ce seul dossier).
Commande : `DISTRO=rke2 POUSSER_VSA=1 JUSQUA='J8 (résolveurs)' mise run confiance:rejeu -- s5b-plateforme`, journal
`resultats/rejeu-s5b-plateforme.log`.
- Jugées dans ce passage : A1 à A5 et B1 à B8, telles qu'écrites le 11/11.
- NON jugées dans ce passage : C1 à C9 (bloc 06, non jouable tel quel : entrées de S1 à S4d effacées), D1 (`fuites`) et
  D3, qui viennent après le bloc 06, et D2 (durée du passage complet).
- Prédiction ajoutée : E1, le passage s'arrête par « arrêt après J8 (résolveurs) (JUSQUA) » avec le code 0 ; confiance
  moyenne (A2 et B4 sont « Moyenne », la 08c n'a jamais tourné sur un cluster neuf).

## Note du 13/11/2026 (2026-11-13T11:03:08Z) : rebâti arrêté à F2 (rien n'est réécrit)

Code 1 à 10:58:20 UTC à « J7 (fermeture, F2 de la 03) » ([journal](rejeu-s5b-plateforme.log)) ; cause : README de la 08,
additif du 13/11 (rebâti arrêté à F2).
- **E1 non tenue** ; **A2 non tenue** (étape en échec, 0 ligne KO avant elle).
- **A3** : lus dans le journal, `outils-horodatage@c7bebae2`, `3a7ca1b1` (16 lignes OK), `rattrapage@c3992728`,
  `porte@e77994c2`, bundles `d21931f3` et `7fa92ad3` ; `outils-prefetch@68e0ae70` non mesuré (étape en échec).
- A1, A4, A5 : non jugées (étapes de J8 et de la porte non atteintes). B1 à B8 : non jugées.

## Note du 13/11/2026 (2026-11-13T11:12:29Z), avant reprise : prédictions ajoutées (rien n'est réécrit)

Reprise prévue, sur accords nommés (rebâti et push de la VSA à part) : `DISTRO=rke2 POUSSER_VSA=1 DEPUIS='J7 (fermeture, F2
de la 03)' JUSQUA='J8 (résolveurs)' mise run confiance:rejeu -- s5b-plateforme-reprise`. Jugées : A1 à A5, B1 à B8, E1
(arrêt par JUSQUA, code 0), et :
| # | Prédiction | Confiance |
|---|---|---|
| E2 | F2 ne construit rien avec Nix (aucune ligne `building '/nix/store/`), ligne « clôture nix : 45 chemins », empreinte 66de99598aa176a1 | Haute : clôture mesurée dans le store |
| E3 | Image d'outils `68e0ae70` reconstruite deux fois (A3 complète) | Moyenne : roues de Hermeto, toolchain Go et sources amont relues au réseau |

## Note du 13/11/2026 (2026-11-13T11:40:22Z) : reprise arrêtée au test 6 (rien n'est réécrit)

Code 1 à 11:38:52 UTC ([journal](rejeu-s5b-plateforme-reprise.log)).
- **E2 tenue** : aucune ligne `building '/nix/store/` ni `copying path`, clôture 66de99598aa176a1.
- **E3 tenue** : `68e0ae70` sur deux constructions, égale au digest épinglé ; **A3 complète** avec la note précédente.
- **A4 non tenue** : `builds-sans-internet` vue absente (chemin d'origine suivi), mais contre-épreuve en KO (ajout d'adresse
  refusé dans le pod privilégié). **E1 non tenue.** A1, A2, A5, B1 à B8 : non jugées.

## Note du 13/11/2026 (2026-11-13T11:42:58Z) : correction de la note précédente (rien n'est réécrit)

A4 : le KO vient d'une collision d'adresse (IP du pod de la contre-épreuve = adresse usurpée 10.42.1.250), défaut de
l'instrument ; **A4 n'est pas jugée** à ce passage (au lieu de « non tenue ») et reste à rejuger. Détail : README de la 08.

## Note du 13/11/2026 (2026-11-13T12:04:31Z), avant lancement : reprise à « J8 (tests) » (rien n'est réécrit)

Décision du propriétaire : « Oui, tel quel » à « Je reprends à « J8 (tests) » tel quel, push compris ? ». Commande :
`DISTRO=rke2 POUSSER_VSA=1 DEPUIS='J8 (tests)' JUSQUA='J8 (résolveurs)' mise run confiance:rejeu -- s5b-plateforme-j8`.
Jugées : A1, A2 (étapes de ce passage), A4, A5, B1 à B8, E1, et :
| # | Prédiction | Confiance |
|---|---|---|
| E4 | Test 6 : IP du pod de la contre-épreuve différente de l'adresse usurpée tirée, « AJOUT|accepté », contre-épreuve OK | Moyenne : tirage de Cilium au hasard selon 23b4537, fréquence de collision non mesurée |
| E5 | Les tests de J8 déjà passés (test2 à test5) repassent sur le même cluster | Moyenne : aucune reprise archivée à « J8 (tests) » |

## Note du 13/11/2026 (2026-11-13T12:26:24Z) : reprise à « J8 (tests) » arrêtée à « J8 (contrôleurs) » (rien n'est réécrit)

Code 1 à 12:22:01 UTC ([journal](rejeu-s5b-plateforme-j8.log)).
- **E4 tenue** : adresse tirée 10.42.1.249, IP des pods 10.42.1.66 (contre) et 10.42.1.201 (test), ajout et retrait acceptés.
- **E5 tenue** : « J8 (tests) » passée en entier sur le même cluster.
- **A4 tenue** : `builds-sans-internet` absente, chemin d'origine, contre-épreuve et test OK.
- **E1 non tenue.** A5 partielle (contrôles 6 et 7 non atteints) ; push de la VSA non atteint ; B1 à B8 non jugées.
- KO de « J8 (contrôleurs) » : au moins un refus de watch sans `.timestamp` dans le journal de Chains, décompte impossible ;
  pas de prédiction sur ce point.

## Note du 13/11/2026 (2026-11-13T12:30:18Z), avant toute reprise : prédiction E6 (rien n'est réécrit)

| # | Prédiction | Confiance |
|---|---|---|
| E6 | Avec le correctif `(.timestamp // .ts)`, « J8 (contrôleurs) » rend 0 refus pour Chains et une ligne « CONSTAT  écarté, kube-apiserver démarrant : 2026-11-13T09:40:32.442Z cannot watch resource "pipelineruns" … » | Haute : ligne et démarrage relevés à 12:29:29 UTC, filtre essayé à sec |

## Note du 13/11/2026 (2026-11-13T12:59:26Z) : plateforme rebâtie jusqu'à « J8 (résolveurs) » (rien n'est réécrit)

Code 0 à 12:58:19 UTC ([journal](rejeu-s5b-plateforme-ctl.log)), 441 OK, 0 KO.
- **E6 tenue** : « CONSTAT  écarté, kube-apiserver démarrant : 2026-11-13T09:40:32.442Z cannot watch resource "pipelineruns"
  … at the cluster scope », puis « tekton-chains-controller : refus des droits dans le journal : 0 ».
- **E1 tenue** dans ce passage (« arrêt après J8 (résolveurs) (JUSQUA) », code 0) ; non tenue aux trois passages précédents.
- **A1 tenue** : toutes les étapes à `kubectl exec` ou `kubectl logs` de la journée sont passées, sauf les deux KO d'instruments
  corrigés. **A2 non tenue** sur l'ensemble (quatre arrêts, voir les notes précédentes). **A3 tenue** (note de F2).
  **A4 tenue** (note de la reprise à J8). **A5 tenue** : contrôles 6 et 7 passés avec la VSA re-poussée.
- **B2** : pare-feu d'hôte actif (mode audit coupé), SSH des trois VM et Zot joignables ; test 6 avec `T6_FERMES` non rejoué
  après H4 : partiellement jugée. **B3 tenue** (chemins `kv/` identiques à la source, `zot-chains` absent). **B6 tenue**
  (témoin « patched »). **B7 tenue** (NotIn `["prefetch-gomod","prefetch-deb"]`). **B8 tenue** (4 lecteurs de Secrets, sans
  `cilium-operator`). **B1, B4, B5** : étapes passées sans KO, mais le 429, les 13 correctifs et les 4 règles en `Deny` ne sont
  pas relevés dans le journal par cette note : non jugées.
- C1 à C9, D1 à D3 : non jugées (bloc 06, `fuites` et CIS non lancés).

## Note du 13/11/2026 (2026-11-13T13:00:39Z), avant lancement : passage fuites et CIS (rien n'est réécrit)

Décision du propriétaire : « Oui, lance-les » à « Je lance fuites et CIS (DEPUIS=fuites, sans le bloc 06) ? ». Commande :
`DISTRO=rke2 DEPUIS=fuites mise run confiance:rejeu -- s5b-fin` (bloc 06 sauté, rien poussé). Jugée : **D1** telle qu'écrite le
11/11 (« `fuites` : aucun secret dans les journaux ; CIS sans attendu »).

## Note du 13/11/2026 (2026-11-13T13:01:41Z) : fuites et CIS passés (rien n'est réécrit)

**D1 tenue** : « aucun secret dans les journaux des trois VM », témoin retrouvé sur chacune ; CIS sans attendu (20 PASS,
61 FAIL, 42 WARN, 7 INFO). D2 et D3 : non jugées (passage complet et bloc 06 non joués).
