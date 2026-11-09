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

## Additif du 09/11/2026, 13:18 UTC : décision C0, option (a), et protocole révisé, à sec

**Décision du propriétaire.** Il a répondu « (i) passage borné » à « Pour C0, que retenez-vous ? ». Le choix proposé était : (i), le passage (a), limité au temps de la mesure ; (ii), garder l'image corrigée en service ; ou attendre. Il avait d'abord écrit : « non attendre nous ralentirait : il vaut mieux avancer avec, non ? ». J'avais alors rappelé que l'attente ne ralentit pas le PoC : le contrôle 9 est vérifié par cosign dans la porte (README de la 08, décision du 29/10). Le choix vaut pour le passage, pas pour une estimation ni pour les accords de chaque effet.

Rien n'est construit, téléchargé, poussé ni appliqué. Relevés locaux archivés : [`kyverno-correctif-c-sec.log`](kyverno-correctif-c-sec.log).

### Construction : interprétation, sans téléchargement

Le protocole (a) prévoyait ko et une image de base téléchargés. Les relevés locaux montrent qu'on peut s'en passer. C'est un écart au protocole accepté : je l'écris comme une interprétation, soumise au propriétaire.
- **Image officielle**, déjà dans le cache OCI local : manifeste amd64 `sha256:6f0c5200…` de l'index `c8c4dd09…`. Elle a trois couches :
  - la base apko ;
  - `kodata` ;
  - le binaire `/ko-app/kyverno`.

  Point d'entrée `/ko-app/kyverno`, utilisateur 65532.
- **Binaire officiel** (`go version -m`) :
  - go1.26.9, `-trimpath`, `CGO_ENABLED=0`, amd64 v1 ;
  - `vcs.revision=e63308f1e16c`, `vcs.modified=true`, 333 dépendances.

  `-ldflags` n'est pas enregistré, sans doute à cause de `-trimpath` (non vérifié dans le source de Go). Le Makefile de v1.19.2 donne `-s -w -X …/pkg/version.BuildVersion=$(VERSION)`.
- **Binaire corrigé** : `./cmd/kyverno` du clone v1.19.2 (`e63308f1e16c` et le correctif v2, deux fichiers sous `pkg/image/verifiers/ivpol/cosign/`).
  - Construit hors ligne : `GOPROXY=off`, modules du cache vérifiés contre `go.sum` (« all modules verified »), `go list -deps` complet.
  - Mêmes réglages que le binaire officiel, avec `-ldflags "-s -w -X github.com/kyverno/kyverno/pkg/version.BuildVersion=v1.19.2"`.
  - **Écart connu** : la chaîne Go est go1.26.10 (cache), au lieu de go1.26.9. Prendre go1.26.9 demanderait un téléchargement : à décider.
- **Image corrigée** : `crane append` (go-containerregistry v0.20.6, déjà épinglé dans `mise.toml`), sur le manifeste amd64 officiel par digest, d'une couche qui contient `ko-app/kyverno` en mode 0755, propriétaire 0:0.
  - Base, `kodata`, point d'entrée et utilisateur restent identiques. Le binaire officiel reste dans l'image, masqué par la couche ajoutée.
  - Le contrôle compare le binaire extrait de l'image poussée au binaire construit.
- **Signature par une clé d'essai : retirée.** L'espace `kyverno` est exclu des règles de la 08c, et aucune `ImageValidatingPolicy` ne vérifie les images de cet espace : la signature ne serait jugée par personne. L'image d'essai est désignée par son digest, relevé au moment de l'envoi.

### Ce que le passage (a) écrirait dans Zot

- Écriture sous `essais/kyverno-correctif` par `poc-ecriture`, le compte de l'hôte qui écrit dans tous les dépôts. Lecture anonyme : le kubelet peut tirer l'image.
- **`poc-ecriture` n'a pas le droit de supprimer** (`stockage.sh`, refus vérifié à la mise en place). L'image reste donc dans Zot après le passage. Effet à accepter, ou à retirer par un autre moyen à décider.

### Découvertes sous H5, en plus de la correction de 11:10

- **Le pod de J6 serait aussi refusé par `images-zot-par-digest`.** Son image est désignée par l'adresse de l'hôte (`192.168.161.13:5000/…`). La règle exige `sc-stockage.poc.test:5000/` et un digest, et `bancc` n'en est pas exclu.
- **La politique d'images de J6 n'est bornée que par l'image** (`glob: "192.168.161.13:5000/*"`), pas par l'espace. Avec le nom `sc-stockage.poc.test:5000`, elle viserait tous les pods réels du cluster, et refuserait tous ceux qui n'ont pas de bundle valide.
- **Révision** : la politique de C est bornée deux fois :
  - par l'espace (`namespaceSelector` sur `bancc`) ;
  - par l'image (`glob` sur `sc-stockage.poc.test:5000/builds/essai-signature*`).

  Le dépôt des bundles est désigné par le même nom. Témoin juste après sa création : un pod ordinaire hors de `bancc` (dry-run serveur) reste admis. Sinon, la politique est retirée sur-le-champ et le passage s'arrête KO.
- **Non relu : la joignabilité de Zot depuis les pods de Kyverno sous H4.** En J6, sous k3s, Kyverno lisait Zot par l'adresse de l'hôte. Depuis H4, le pare-feu d'hôte protège Zot, et aucune vérification d'image par l'admission n'a tourné. Le témoin `j5-temoin` avec l'image officielle le dira : s'il échoue sur une erreur réseau, le passage s'arrête avant toute bascule.
- **Chaque refus est attribué** : le script exige le nom de la politique d'essai dans le message de refus. Un refus par une règle de la 08c est KO pour la mesure, jamais le refus attendu.

### Périmètre proposé, réduit

- **Gardés** : les 8 cas `j5-*`, avec l'image officielle puis avec l'image corrigée, puis de nouveau avec l'image officielle.
- **Retirés, proposition** :
  - les 30 cas d'admission de J6 : ils jugent des `ValidatingPolicy`, un chemin que le correctif ne touche pas ;
  - les 17 cas du banc C : ils exigent une écriture de plus dans Zot (`bench/`), avec un pod de banc qui ne passe plus sous H5.

  La non-régression du chemin `ivpol` reste couverte par `j5-temoin`, `j5-att-historique` et les 6 refus, et en CLI par l'étape B (24 cas sur 24).

### Prédictions du passage révisé, avant tout passage

C1 à C6 restent écrites ci-dessus, sans valeur en l'état (correction de 11:10). Les prédictions suivantes les remplacent pour ce protocole.

| # | Prédiction | Confiance |
|---|---|---|
| C7 | Construction : binaire construit hors ligne ; l'image poussée en contient le même sha256 ; base, `kodata`, point d'entrée et utilisateur identiques au manifeste `6f0c5200…` | Haute |
| C8 | Politique d'essai bornée : le pod ordinaire hors de `bancc` est admis | Haute |
| C9 | Image officielle, avant : `j5-temoin` admis ; `j5-jeton-valide` refusé avec une erreur interne (« nil pointer ») ; les 6 autres refusés, par la politique d'essai | Moyenne : Zot n'a pas été lu depuis Kyverno sous H4, ni avec ce nom |
| C10 | Image corrigée : `j5-temoin` et `j5-jeton-valide` admis | Moyenne |
| C11 | Image corrigée : les 6 autres refusés par la politique d'essai, sans erreur interne, avec les motifs de l'étape B | Moyenne |
| C12 | Aucune création de pod réelle refusée pendant les deux bascules, CronJobs `horodatage` et `rattrapage` suspendus ; 0 `FailedCreate` | Moyenne : nombre de répliques non relu |
| C13 | Retour : `imageID` officiel `c8c4dd09…`, et C9 rejouée à l'identique | Haute |

**Pire cas.** Les webhooks de Kyverno sont en `failurePolicy: Fail`. Si le contrôleur d'admission ne démarre pas avec l'image corrigée, toute création de pod dans le champ de Kyverno est refusée jusqu'au retour. Le retour reste possible, puisque l'espace `kyverno` est exclu. D'où la garde horaire du protocole :
- hors de 09:20 à 09:45 UTC ;
- hors du 21/11, de 15:30 à 16:30 UTC.

Une politique d'essai mal bornée refuserait aussi des pods réels. Le témoin C8 l'arrête dans la seconde.

**Ce que C ne prouvera pas, inchangé** : le background et les rapports, la tenue dans la durée, et un redémarrage avec l'image corrigée.

**Estimation** : aucune n'est fixée. Je propose 4 h (script et passage), à valider par le propriétaire avant tout passage.
