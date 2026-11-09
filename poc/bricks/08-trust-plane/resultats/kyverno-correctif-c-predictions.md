# Correctif Kyverno, étape C : protocole et prédictions, à sec

Écrits le 09/11/2026 à 11:07 UTC, avant tout passage. Accord : « traite tout, non ? », en réponse à la proposition de trois travaux à sec, compris comme : les trois, à sec. Rien n'a été construit, téléchargé, poussé dans Zot ni appliqué au cluster. Aucun script n'est écrit : la forme du passage dépend de la décision C0.

Sources relues dans le dépôt :
- `politique.sh` : installation de Kyverno v1.19.2 en J6, 5 images épinglées par digest et copiées dans Zot sous `amont/kyverno/`, webhooks lus en `failurePolicy` ;
- `resultats/politique-parite.tsv` : décisions du CLI et de l'admission sur les cas `j5-*` en J6 ;
- [`kyverno-correctif-b-predictions.md`](kyverno-correctif-b-predictions.md) et le journal de l'étape B ;
- `install.yaml` de la release, en cache : 4 Deployments, `RollingUpdate` avec `maxSurge: 1` et `maxUnavailable: 40%`, nombre de répliques non fixé dans le manifeste ;
- règles de la 08c (`politiques/kyverno/`) : l'espace `kyverno` est exclu des 4 règles par leur `namespaceSelector`.

## Ce que C mesure

Le correctif v2 corrige le panic dans le CLI : c'est l'étape B, 24 cas sur 24. C mesure la même chose à l'admission. Le contrôleur d'admission évalue `ImageValidatingPolicy` dans le cluster, avec un pod présenté en dry-run serveur, comme pour la parité de J6. En J6, l'admission refusait `j5-jeton-valide` alors que le pod était légitime.

## C0, décision du propriétaire : d'où vient l'image corrigée

Seule l'image `kyverno` (contrôleur d'admission) a besoin du correctif. Les trois autres contrôleurs n'évaluent pas l'admission. Le background et les rapports évaluent peut-être aussi la politique : non relu dans le source.

Toute image corrigée est construite par nous. Elle n'a ni release signée ni provenance de l'éditeur, ce qui va contre le critère du doc 04, §1. C'est pourquoi C0 revient au propriétaire.

- **(a) Image d'essai construite sur l'hôte**, depuis `v1.19.2` `e63308f1e16c` et `correctif-v2-final.patch` (sha256 `5b8ae9b4…`) :
  - outil de construction de Kyverno (ko, d'après son Makefile, non relu ce jour) et image de base : téléchargements à épingler et vérifier, avec accord ;
  - poussée dans Zot sous `essais/kyverno-correctif` (écriture), signée par une clé d'essai, jamais sous `amont/` ;
  - utilisée le temps de C, puis retour à l'image officielle dans le même passage.
- **(b) Image construite par notre propre chaîne** (Tekton, Chains, porte) : elle porterait notre provenance. Il faudrait la fermeture des dépendances Go de Kyverno (brique 03), un travail bien plus long que C : hors de l'estimation.
- **(c) Attendre une release de Kyverno qui contient le correctif.** Rien à construire, mais aucune date : la PR attend le tri de l'issue #18525.
- **Recommandé : (c) si le propriétaire tient au critère du doc 04 sans exception ; sinon (a), limité au passage, retour vérifié.** Je n'ai pas de préférence forte : c'est un arbitrage entre règle et preuve.

## Protocole proposé pour (a), non écrit

1. **Garde horaire.** Hors de 09:20 à 09:45 UTC (scan planifié) et hors du 21/11 de 15:30 à 16:30 UTC (tâche de rétention de Zot).
2. **Témoins avant**, en lecture seule :
   - image en service du contrôleur d'admission par `imageID`, égale au digest officiel `sha256:c8c4dd09…` de `politique.sh` ;
   - webhooks de Kyverno et leur `failurePolicy` ;
   - nombre de répliques réel (le manifeste ne le fixe pas) ;
   - les 8 cas `j5-*` à l'admission avec l'image officielle (témoin négatif du jour).
3. **Suspension** de `horodatage` et `rattrapage`, qui créent des pods chaque minute, comme le fait `h5_limites`. Reprise par un trap en cas de KO.
4. **Bascule** : `kubectl set image` du Deployment `kyverno-admission-controller` vers `essais/kyverno-correctif@<digest>` dans Zot, puis attente du déploiement.
5. **Cas mesurés** à l'admission, en dry-run serveur, même politique et même pod qu'en J6 et B :
   - les 8 cas `j5-*` ;
   - les 25 décisions de parité de J6 et les 30 cas d'admission de J6 (`politique-admission.tsv`), pour voir qu'il n'y a pas de régression.
6. **Retour** à l'image officielle par digest et attente du déploiement. Contrôle : `imageID` officiel, puis les 8 cas `j5-*` rejoués, qui doivent redonner le témoin de l'étape 2.
7. **Reprise** des CronJobs, puis un passage réussi de chacun.

## Prédictions, pour (a)

| # | Prédiction | Confiance |
|---|---|---|
| C1 | Image officielle, avant : `j5-temoin` admis ; les 7 autres cas `j5-*` refusés, comme en J6, `j5-jeton-valide` compris. Motif à l'admission affiché, non prédit : en J6, le tableau ne garde que l'avertissement de PodSecurity | Haute sur les verdicts : mesurés en J6, et en B pour le CLI |
| C2 | Image corrigée : `j5-temoin` et `j5-jeton-valide` admis | Moyenne : le chemin d'admission n'a pas été relu pour ce cas |
| C3 | Image corrigée : `j5-sans-jeton`, `j5-aucun-bundle`, `j5-jeton-altere`, `j5-autre-signature`, `j5-tsa-etrangere` et `j5-att-historique` refusés, sans erreur interne, avec les motifs de B | Moyenne |
| C4 | Image corrigée : parité de J6 et 30 cas d'admission inchangés, hors `j5-jeton-valide` | Haute : le correctif ne touche que les bundles avec horodatage vérifié et matériel absent |
| C5 | Aucune création de pod refusée par une indisponibilité du webhook pendant les deux bascules, CronJobs suspendus | Moyenne : nombre de répliques non relu |
| C6 | Retour : `imageID` officiel, et C1 rejoué à l'identique | Haute |

**Pire cas** : le contrôleur d'admission ne démarre pas avec l'image corrigée. Avec `failurePolicy: Fail` sur ses webhooks, toute création de pod dans le champ de Kyverno est alors refusée jusqu'au retour, qui reste possible puisque l'espace `kyverno` est exclu. Un passage du scan ou de la tâche du 21/11 dans cette fenêtre échouerait : c'est l'objet de la garde horaire.

**Ce que C ne prouvera pas** : le comportement du background et des rapports, la tenue dans la durée et un redémarrage avec l'image corrigée. Une release officielle de Kyverno contenant le correctif reste attendue (issue #18525 à suivre).

## Correction du 09/11/2026, 11:10 UTC, avant tout push : le pod d'essai de J6 tomberait sous les règles de H5

Ce point a été relevé à la relecture du conseiller, puis vérifié dans le dépôt. Les prédictions C1 à C6 ci-dessus restent écrites telles quelles, mais ne valent pas en l'état.
- Le pod d'essai de J6 (`poc/benchmarks/kyverno-seul/kyverno/pod.tmpl.yaml`) n'a ni limites ni compte dédié. Il est présenté dans l'espace `bancc`, qui ne figure pas dans les exclusions des 4 règles de la 08c, en `Deny` depuis H5. `limites-obligatoires` le refuserait, et sans doute `jeton-compte-default` (jeton du compte `default` monté par défaut), quel que soit le correctif. C2 ne pourrait jamais montrer `j5-jeton-valide` admis, et C1 et C4 perdraient leur sens.
- La parité et les 30 cas d'admission de J6 datent du 06/11 à 13:43 UTC, sous RKE2 mais avant H1 à H5. Ils n'ont pas été rejoués depuis. Le tableau de J6 ne peut donc pas servir de base à C4.

**Ce qui change, toujours à sec, à confirmer avec C0 :**
- Pod d'essai de C : celui de J6, avec des limites et `automountServiceAccountToken: false`, pour que seule la règle d'images de Kyverno juge. Sinon, `bancc` serait ajouté aux exclusions des 4 règles le temps du passage : c'est une modification du cluster, moins bonne.
- Étape 2 du protocole : la parité et les 30 cas d'admission sont rejoués avec l'image officielle le même jour, avec le même pod. C4 se compare à cette base, non à J6.
- Effets ajoutés :
  - la politique d'images de J6 (`ivpol` de `commun.sh`) est créée dans le cluster, bornée à `bancc` ;
  - l'espace `bancc` est créé s'il n'existe plus ;
  - les deux sont retirés à la fin, et leur retrait est contrôlé.
- C1 : avant la bascule, avec le pod corrigé, `j5-temoin` est admis. Confiance moyenne : ce pod n'a jamais été présenté sous H5.
