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

## Additif du 09/11/2026, 13:39 UTC : décisions de cadrage, go1.26.9 installé, binaire officiel reproduit au bit près

**Réponses du propriétaire** aux quatre questions de 13:18 UTC :
- **Image laissée dans Zot** sous `essais/kyverno-correctif` : « 2 ok ».
- **Estimation de 4 h** : « 4 ok ».
- **Construction** : il a demandé « ben installe cette version via mise ? », à propos de go1.26.9. Je lui ai proposé ensuite une tâche mise jumelle de go1.26.10 et le témoin de reproduction au bit près, effets et pire cas compris. Il a répondu : « on fait le plus complet ».
- **Interprétation de « on fait le plus complet »**, écrite ici :
  - question 1 : oui, installer go1.26.9 et faire le témoin ;
  - question 2 : les 8 cas `j5-*` **et** les 17 cas du banc C.

  Les 30 cas d'admission de J6 restent hors du périmètre : ils ne passent pas par le code corrigé. Le banc ajoute environ 1 h : estimation proposée 5 h, à confirmer avant le passage. La signature d'essai reste retirée.

**go1.26.9 installé** par la tâche `outils:go-1.26.9` de `mise.toml`, jumelle de `outils:go-toolchain`. C'est le module `golang.org/toolchain@v0.0.1-go1.26.9.linux-amd64`, vérifié par `sum.golang.org`, installé dans `~/.cache/supply-chain-poc/outils/gomodcache`, rien au niveau système.

**Témoin : le binaire officiel du contrôleur d'admission v1.19.2 est reproduit au bit près** ([`kyverno-correctif-c-reproduction.log`](kyverno-correctif-c-reproduction.log), 13:39:42 UTC).
- Construit depuis un clone local à `e63308f1e16c`, sans le correctif, avec go1.26.9 :
  - `-trimpath` ;
  - `-ldflags "-s -w -X …/pkg/version.BuildVersion=v1.19.2"` ;
  - `CGO_ENABLED=0` ;
  - modules du cache, hors ligne.
- **sha256 `7913082b…`**, identique à celui du binaire extrait de l'image officielle (couche `29e1273f…` du manifeste amd64 `6f0c5200…`).
- Condition : un fichier non suivi, vide, dans l'arbre. Il reproduit `vcs.modified=true` et la version `v1.19.2+dirty` enregistrés dans le binaire officiel. Arbre propre : sha256 `b36353ea…`, seule différence attendue.
- Le premier essai dans un `git worktree` n'a enregistré aucune information VCS, sans erreur, même avec `-buildvcs=true`. Cause non cherchée : un clone local a été utilisé à la place.

**Conséquence pour C7.** Le binaire corrigé sera construit de la même façon, avec go1.26.9, depuis le clone qui porte le correctif v2 (arbre modifié, donc `v1.19.2+dirty` aussi). Le correctif est alors le seul écart avec le binaire officiel, et ce point est désormais mesuré. L'écart go1.26.10 de 13:18 UTC disparaît. C7 est réécrite :

| # | Prédiction | Confiance |
|---|---|---|
| C7 | Binaire corrigé construit avec go1.26.9 et les mêmes réglages ; l'image poussée en contient le même sha256 ; base, `kodata`, point d'entrée et utilisateur identiques au manifeste `6f0c5200…` | Haute |

## Additif du 09/11/2026, 13:52 UTC : estimation, script écrit à sec, binaire corrigé construit, prédictions complétées avant tout passage

**Estimation : 5 h.** Le propriétaire a répondu « Oui, 5 h » à « L'estimation passe à 5 h avec le banc C ? ». Le compte part de l'additif de 13:18 UTC (décision C0) et se fait par la méthode du 09/11 pour la 08c : écarts d'au plus 1 h entre commits qui touchent l'étape C. Une décision s'impose à partir de 10 h.

**Script : [`kyverno-admission.sh`](../kyverno-admission.sh)**, écrit à sec et relu par le conseiller avant tout passage. Il a quatre étapes :

| Étape | Effets | Accord |
|---|---|---|
| `construire` | Local, hors ligne | **Faite**, 13:52:05 UTC, voir ci-dessous |
| `image` | Lecture anonyme du manifeste officiel dans Zot ; écriture de `essais/kyverno-correctif:v1.19.2-v2` par `poc-ecriture`, environ 48 Mo compressés ; l'image reste | À demander |
| `temoins` | Lecture seule du cluster et de Zot ; deux pods témoins présentés en dry-run serveur (un refus produirait un Event `PolicyViolation`) | À demander |
| `passage` | CronJobs suspendus, `bancc` créé s'il manque, politiques d'essai, deux bascules du contrôleur d'admission ; tout est retiré et contrôlé | À demander, lancé en arrière-plan (10 à 20 min estimées) |

**`construire`, faite** ([`kyverno-admission-construire.log`](kyverno-admission-construire.log)). Le binaire corrigé est construit avec go1.26.9 et les réglages du témoin de reproduction :
- version `v1.19.2+dirty`, `vcs.modified=true`, révision `e63308f1e16c` ;
- sha256 `2b36652a…`, différent de l'officiel `7913082b…` ;
- taille identique : 141 267 106 octets.

La couche contient `ko-app/` et `ko-app/kyverno`, en 0555, propriétaire 0:0. La couche officielle écrit le chemin `/ko-app/kyverno`, avec une barre en tête : les deux désignent le même fichier dans l'image. Ce point sera contrôlé par `image`, qui relit le binaire de la couche poussée.

**Prédictions complétées, avant tout passage.**
- **Banc C**, 17 cas, dans les trois phases (officielle avant, corrigée, officielle après) : décisions de J6 inchangées. `ok` et `c7-kev-vex-ok` sont admis, les 15 autres refusés par `bench-release`. Confiance moyenne : le pod d'essai change (limites, sans jeton, conforme à restricted), et les images sont désormais désignées par le nom du registre.
- **Ce qui est jugé, et ce qui est seulement affiché** :
  - **jugés**, une erreur est KO :
    - la décision de chaque cas ;
    - l'absence d'erreur interne avec l'image corrigée (C11) ;
    - le bornage (C8) ;
    - la condition de bascule ;
    - C13 (décisions d'après égales à celles d'avant) ;
    - le retrait ;
    - C12, écrit comme 0 `FailedCreate` sur tout le cluster pendant le passage ;
    - un passage réussi de chaque CronJob après la reprise ;
  - **affichés, non jugés** :
    - l'erreur interne avec l'image officielle, annoncée par C9 ;
    - les motifs de l'étape B (C11 : la décision est jugée, le texte est affiché) ;
    - un refus du webhook sans motif reconnaissable (`INATTRIBUÉ`). Il est classé CONSTAT quand un refus est attendu : la forme du message d'une erreur interne à l'admission n'a jamais été relue.
- **Arrêts immédiats**, retrait assuré par le trap :
  - bornage KO ;
  - politique jamais prête ;
  - avant la bascule, `j5-temoin` non admis ou `j5-sans-jeton` non refusé et attribué. Cela couvre Kyverno qui ne joindrait pas Zot sous H4 ;
  - bascule ou retour qui échoue.
- **Pire cas, probablement plus doux qu'écrit à 13:18 UTC** : avec 1 réplique, `maxSurge: 1` et `maxUnavailable: 40 %` (arrondi à 0), l'ancien pod continue de servir tant que le nouveau n'est pas prêt. Ce n'est pas relu dans le cluster : les témoins donneront le nombre de répliques.

**Reprise manuelle**, si le passage est interrompu sans que le trap tourne, par exemple si l'hôte s'arrête :

```
kubectl set image -n kyverno deployment/kyverno-admission-controller kyverno=sc-stockage.poc.test:5000/amont/kyverno/kyverno@sha256:c8c4dd09e720d2cd7fd24ca73ac28e46651001372f988e0cba3f2f612f04b955
kubectl patch cronjob -n horodatage horodatage --type merge -p '{"spec":{"suspend":false}}'
kubectl patch cronjob -n declencheurs rattrapage --type merge -p '{"spec":{"suspend":false}}'
kubectl delete imagevalidatingpolicy -l poc.test/essai=kyverno-admission
```

Retirer aussi l'espace `bancc`, s'il n'existait pas avant le passage.

## Additif du 09/11/2026, 13:53 UTC : étape `image` passée, C7 tenue

Accord du propriétaire : « Oui, lance image », en réponse à « Je lance l'étape image (écriture dans Zot) ? ». Les effets et le pire cas avaient été donnés juste avant. Le passage a eu lieu à 13:53:13 UTC ([`kyverno-admission-image.log`](kyverno-admission-image.log)). Bilan : OK.

**Image corrigée** : `sc-stockage.poc.test:5000/essais/kyverno-correctif@sha256:eec37159…`, étiquette `v1.19.2-v2`, poussée par `poc-ecriture`. Son digest est dans [`kyverno-admission-image.digest`](kyverno-admission-image.digest).

**C7 tenue** :
- 4 couches, dont les 3 premières identiques à celles du manifeste officiel `6f0c5200…` ;
- point d'entrée `/ko-app/kyverno` et utilisateur 65532 identiques, environnement identique ;
- binaire relu dans la couche poussée identique au binaire construit (`2b36652a…`).

La copie des identifiants de `poc-ecriture` a été retirée à la sortie (répertoire vide, vérifié). Rien n'a été lu ni écrit dans le cluster. L'image reste dans Zot, comme accepté.

## Additif du 09/11/2026, 13:54 UTC : étape `temoins` passée, une politique de J6 restée chargée

Accord du propriétaire : « Oui, lance temoins », en réponse à « Je lance l'étape temoins (lecture seule du cluster) ? ». Effets et pire cas donnés juste avant. Passage à 13:53:59 UTC ([`kyverno-admission-temoins.log`](kyverno-admission-temoins.log)), bilan : OK. Rien n'a été créé ni modifié.
- **Contrôleur d'admission** : image officielle `c8c4dd09…`, en spec comme en `imageID`. 1 réplique, sur `sc-confiance`. `RollingUpdate`, `maxSurge: 1`, `maxUnavailable: 40%`. **Aucun PodDisruptionBudget** dans `kyverno`. L'étiquette `app.kubernetes.io/component=admission-controller` est présente.
- **Webhooks** : en `Fail`, sauf `kyverno-ttl-validating-webhook-cfg` et `kyverno-verify-mutating-webhook-cfg` (`Ignore`).
- **Espaces** :
  - `bancc` existe, avec `pod-security.kubernetes.io/enforce: privileged` (décision D10 de la 08b, J6). Le passage ne le créera ni ne le retirera ;
  - `horodatage` est en `restricted`.
- **Pods témoins**, sans politique d'essai, en dry-run serveur : admis dans `horodatage` et dans `bancc`. Les règles de la 08c et de J6 ne les refusent pas.
- **CronJobs** `horodatage` et `rattrapage` actifs, dernier passage à 13:53:00 UTC.
- **Zot** :
  - `horodatage/bundles` : 63 referrers ;
  - `essais-j5/sans-jeton`, `jeton-altere`, `autre-signature` et `tsa-etrangere` : 1 chacun ;
  - `essais-j5/aucun` : 0 ;
  - les 17 images du banc C sont présentes, ainsi que l'image corrigée.

**Écart : 1 `ImageValidatingPolicy` déjà présente, pour 0 attendue.** L'étape l'affiche sans la juger, d'où le bilan OK. C'est `bench-release`, créée le 06/11/2026 à 13:47:07 UTC par la parité de J6 (`politique.sh parite`), qui ne la retire jamais (relu dans le script). Elle est en `Deny`, sans borne d'espace, sur `192.168.161.13:5000/bench/*`, une adresse qu'aucun pod réel n'utilise. Elle est donc restée sans effet depuis trois jours, ce qui est déduit et non mesuré.

**Conséquences pour le passage :**
- Le pire cas se confirme plus doux qu'écrit à 13:18 UTC : 1 réplique et `maxSurge: 1`. L'absence de PDB ne joue pas dans une mise à jour progressive.
- Le script est modifié avant tout passage (ajout de 13:56 UTC dans `kyverno-admission.sh`). Si `bench-release` du 06/11 est la seule politique d'images présente, il l'archive dans `kyverno-admission-bench-release-j6.json`, puis la retire avant toute autre action. Toute autre politique arrête le passage. Elle n'est pas remise à la fin : c'était un reste de J6. Ce retrait fait partie de l'accord du passage.
- Défaut de `politique.sh parite` : la politique du banc n'est pas retirée à la fin de l'étape. Il n'est pas corrigé ici et reste à décider.

## Additif du 09/11/2026, 13:58 UTC : passage fait, C8 à C13 tenues, le correctif v2 fonctionne à l'admission

**Accord du propriétaire** : « Oui, lance le passage », en réponse à « Je lance le passage (cluster, en arrière-plan) ? ». Les effets, arrêts et pire cas avaient été donnés juste avant, retrait de `bench-release` de J6 compris.

**Passage** : de 13:55:25 à 13:58:15 UTC, en arrière-plan, code 0, bilan OK.
- Journal : [`kyverno-admission-passage.log`](kyverno-admission-passage.log).
- Tableau des 75 présentations : [`kyverno-admission-passage.tsv`](kyverno-admission-passage.tsv).
- `bench-release` de J6 archivée dans [`kyverno-admission-bench-release-j6.json`](kyverno-admission-bench-release-j6.json), qui contient les clés publiques du banc et aucune clé privée (vérifié), puis retirée.

| Phase | Image | Cas conformes | Erreurs internes |
|---|---|---|---|
| avant | officielle `c8c4dd09…` | 25 sur 25 | 4 : `j5-jeton-valide`, `j5-jeton-altere`, `j5-autre-signature`, `j5-tsa-etrangere` |
| corrigée | `essais/kyverno-correctif@eec37159…` | 25 sur 25 | **0** |
| après | officielle `c8c4dd09…` | 25 sur 25 | les 4 mêmes |

| # | Résultat |
|---|---|
| C7 | Tenue à l'étape `image` (13:53 UTC) |
| C8 | **Tenue** : à chacune des 27 politiques chargées (8 cas `j5-*` et `bench-release`, dans les trois phases), le même pod hors de `bancc` est admis. Le témoin du banc porte sur `c1-unsigned`, un cas refusé dans `bancc` |
| C9 | **Tenue** : `j5-temoin` admis. `j5-jeton-valide` refusé par une erreur interne (« Policy j5-jeton-valide error: failed to evaluate policy »), comme `jeton-altere`, `autre-signature` et `tsa-etrangere`. `sans-jeton`, `aucun-bundle` et `att-historique` sont refusés par la règle (« Policy … failed: C9 : provenance sans horodatage RFC 3161 valide »). Zot est lu par Kyverno sous H4, par le nom du registre |
| C10 | **Tenue** : avec l'image corrigée, `j5-temoin` et **`j5-jeton-valide` admis** |
| C11 | **Tenue** : les 6 autres sont refusés par la règle (« failed: C9 : … »), sans erreur interne. Les trois falsifications passent d'« error » à « failed ». `j5-att-historique` reste refusé (kyverno#17109, hors du correctif) |
| C12 | **Tenue** : 0 `FailedCreate` sur le cluster de 13:55:25 à 13:57:58 UTC ; chaque bascule terminée sans attente du webhook (0 s) |
| C13 | **Tenue** : `imageID` officiel `c8c4dd09…` après le retour ; décisions d'après identiques à celles d'avant, erreurs internes comprises |
| Banc C | **Tenu** dans les trois phases : `ok` et `c7-kev-vex-ok` admis, 15 refus attribués à `bench-release`, aucune erreur interne |

**Retrait contrôlé** : aucune politique d'images restante. CronJobs repris, puis `horodatage-29903878` et `rattrapage-29903877` réussis. `bancc`, présent avant le passage, est laissé tel quel.

**Lecture.** Le correctif v2 rend au contrôle 9, à l'admission, le comportement de cosign en J5 :
- le jeton valide est accepté ;
- les falsifications sont refusées par la règle, et non plus par une erreur interne.

Il ne change rien d'autre sur les 25 cas, et le retour à l'image officielle redonne exactement l'état d'avant. Le refus de `j5-jeton-valide` par l'image officielle, à l'admission, est mesuré pour la première fois sous H5.

**Non prouvé, inchangé** :
- le background et les rapports ;
- la tenue dans la durée ;
- un redémarrage avec l'image corrigée ;
- golangci-lint.

L'image corrigée n'est plus en service : l'admission du PoC reste celle de la release officielle, et le contrôle 9 est toujours jugé par cosign à la porte.
