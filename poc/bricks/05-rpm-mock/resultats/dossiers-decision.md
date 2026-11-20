# Dossiers de décision ouverts, préparés à sec le 20/11/2026

Ce sont les décisions qui te reviennent avant le rejeu de M5b et la clôture de la 05, plus D14 de la 07a. **Rien n'est appliqué** : ni `commun.sh`, ni `vm.sh`, ni `zot.json`, ni la porte ne sont touchés.

Chaque dossier donne les faits mesurés, avec leur source, puis les options et les couplages avec les autres décisions. Les heures sont en UTC.

## Ordre imposé par les couplages

Plusieurs décisions passent par le même geste, ou doivent précéder le même rejeu :

1. **Tout redémarrage de Zot remet G7 à zéro.** C'est mesuré le 19/11 : un balayage part au démarrage, et le calendrier repart de sa fin ([`g7-replanification.md`](../../07a-sbom-grype/resultats/g7-replanification.md), notes de 19:26:42Z et 19:28:08Z). Un passage de `stockage.sh zot` ou le rejeu de M5b redémarre Zot. Le rejeu efface en plus Zot et Loki.
2. Les premières suppressions réelles de G7 sont projetées le 28/11 de 01:37 à 02:52 (n°8), puis le 29/11 de 02:16 à 03:36 (n°9). C'est un calcul, sous l'hypothèse qu'aucun redémarrage ne survienne.
3. Trois décisions changent ce que le rejeu recrée : la taille du disque, la rétention grype et `TZ` dans `bundle`. Elles doivent donc être tranchées **avant** le rejeu, ou laissées en l'état pour ce rejeu.

## 1. Date du rejeu de M5b

**Faits** :
- La préparation est écrite (`m5b-rejeu.sh`, bloc 05 de `rejeu.sh`), mais elle n'a jamais été exécutée. Le rejeu est noté « pas avant le 28/11 ».
- Loki garde les lignes de `zot.service` 720 h, d'après la configuration. La lecture a été mesurée sur 7 jours (13/11).

**Options** :
- **(i) Après la lecture du n°9**, le 29/11 à partir de 05:40 environ. G7 voit ses premières suppressions réelles (N8, N9) avant que le rejeu ne recrée Zot.
- **(ii) Le 28/11, avant le n°8.** G7 repart de zéro. Les premières suppressions arriveraient environ 14 jours après le rejeu, donc vers le 12/12. Ce n'est pas calculé plus finement.

**Couplages** : point 4 de G7 (lecture ou tâche après le n°9). La perte de données au rejeu est acceptée par toi.

## 2. Rétention de la base grype (`vulndb/grype`)

**Faits** :
- `zot.json` : `retention.delay` 336 h, commun à toutes les politiques ; pour `vulndb/grype`, `mostRecentlyPushedCount: 11` et `deleteUntagged: true`.
- Le 20/11, le dépôt porte 8 tags, du 13 au 20/11, de 200,7 à 205,2 Mo de couches chacun ([`sc-stockage-attribution.log`](sc-stockage-attribution.log)). C'est l'écrivain périodique de sc-stockage, à environ 200 Mo par jour (`m1b-carte.md`).
- **Calcul**, non mesuré : une base détaguée n'est effacée qu'à 336 h. À l'équilibre, sc-stockage garderait donc les bases des 14 derniers jours environ, soit 2,8 à 3 Go, contre 1,6 Go aujourd'hui. L'équilibre serait atteint vers le 27/11.
- Ce que Zot permet comme délai propre à un dépôt n'est pas relu.

**Options** :
- **(i) Garder la rétention.** C'est celle que G7 mesure.
- **(ii) Réduire** le compte ou le délai. Il faut d'abord relire ce que Zot accepte par dépôt.

**Couplages** : appliquer (ii) sur la plateforme actuelle passe par `stockage.sh zot`, donc par un redémarrage. Il faut l'appliquer **après le n°9**, ou seulement dans `zot.json` avant le rejeu, qui la posera. Elle est liée aussi à la taille du disque (dossier 3).

## 3. Taille du disque de sc-stockage dans `vm.sh`

**Faits** :
- `vm.sh` crée sc-stockage avec 20G.
- Le 20/11, décision « Agrandir maintenant » : le disque est passé de 20G à 30G à chaud. La place libre est passée de 2 823 à 12 491 Mo (AG1 à AG5 tenues, `m1b-carte.md`).
- `vm.sh` n'a pas été modifié. Un rejeu recréerait donc un disque de 20G.
- Le 20/11 à 15:59, sur 20G, il restait 2 820 Mo libres.

**Options** :
- **(i) Passer `vm.sh` à 30G** avant le rejeu. Le rejeu recrée alors l'état d'aujourd'hui.
- **(ii) Garder 20G.** Le rejeu repart avec la marge mesurée le 20/11, moins ce que la base grype ajoutera jusqu'à l'équilibre (dossier 2).

**Couplages** : à trancher avant le rejeu. Ce choix ne touche pas G7, puisque `vm.sh` ne tourne qu'au rejeu. Il est lié à la rétention grype.

## 4. `TZ` dans `bundle` (`08-trust-plane/commun.sh`)

**Faits**, mesurés au banc le 20/11 (RE1 à RE7, `m5b-carte.md`) :
- tkn 0.46.2 écrit la date de création du bundle dans le fuseau de l'hôte. Le digest en dépend : `TZ=UTC` change les 9 digests de la liste revue, et `TZ=Europe/Paris` les redonne.
- `bundle` est appelé 41 fois dans 15 scripts, des briques 01, 03, 05, 06 et 08, sans `TZ=`.
- `m5b-republier.sh` pose déjà `TZ=Europe/Paris` pour lui seul.

**Options** :
- **(i) `TZ=Europe/Paris` dans `bundle`.** Les digests actuels restent valables, et ils ne dépendent plus de l'hôte.
- **(ii) `TZ=UTC`.** C'est plus neutre, mais tous les digests changent : il faudrait une nouvelle signature et une revue de `taches.yml` pour chaque brique.
- **(iii) Laisser l'hôte décider.** Rien ne change tant que les poussées partent de cet hôte.

**Couplages** : ce n'est pas bloquant pour M5b. Mais (i) et (ii) modifient `commun.sh`, que le rejeu utilise : il faudrait un banc avant le rejeu.

## 5. Seconde barrière réseau sur la voie rpm

**Faits** :
- Constat de M5a (`m5-predictions.md`) : une seule barrière coupe le réseau pendant `%build`. C'est la NetworkPolicy `construction-rpm-sans-sortie`, posée sur le label de la tâche.
- `mock --isolation=simple` ne crée pas d'espace de noms réseau.
- La voie deb en a deux : la politique du pod, et sbuild `--chroot-mode=unshare`, qui ne laisse que `lo`.
- Aux essais du 17/11, `nspawn` a échoué dans le pod Kata (bus système absent).

**Options** :
- **(i) Garder une barrière**, en réserve écrite de la 05.
- **(ii) En ajouter une seconde** dans la construction. La tâche `construire-rpm` change alors : nouvelle signature, revue de `taches.yml` et nouvelle cascade de M1b. Aucun moyen n'a été essayé.

**Couplages** : si c'est (ii), elle vient avant le rejeu et avant la clôture. C'est la plus coûteuse des options de ce fichier.

## 6. Clôture de la 05

**Faits** :
- Jalons tenus, d'après le README de la 05 :
  - M1b avec réserves (amorce figée, un nœud et un hôte, prefetch ouvert en 443, porte qui ne connaît pas `construire-racine-rpm`) ;
  - M2, avec 3 réserves ;
  - M3 ;
  - M4 (M4b et M4c refaits sur M1b) ;
  - M5a ;
  - la cascade, terminée le 20/11.
- **M5b, le rejeu de zéro, n'est pas passé.**
- Le seuil est « bit-identique ; 0 pod privilégié sur l'hôte », lu comme le test 4 de la 08 (D1 (a)).

**Options** :
- **(i) Clore maintenant**, avec M5b en réserve, rejoué avec la plateforme. C'est ce que tu as fait pour la 06, close le 19/11 avec des réserves.
- **(ii) Clore après M5b**, donc pas avant le 28/11 ou le 29/11 (dossier 1).

**Couplages** : les dossiers 3 à 5 peuvent passer en réserves de clôture, ou être tranchés avant.

## 7. D14, distro des scans de paquets (brique 07a)

**Faits** :
- Mesure du 20/11 ([`rpm-distro-predictions.md`](../../07a-sbom-grype/resultats/rpm-distro-predictions.md), RD1 à RD8 tenues) : syft 1.38.0 n'émet pas de `distro` pour un rpm isolé. Sans `--distro`, grype 0.104.1 ne rapporte **aucune** correspondance, en silence. Avec `--distro rocky:9.7`, il juge les rpm Rocky : openssl-libs 49, glibc 19, zlib 1.
- Le rpm de sample-app ne donne aucune correspondance dans les deux cas : il ne contient aucun module Go. Le binaire Go extrait du deb en donne 140.
- Le scan du deb dans la plateforme lit le contenu extrait (`syft dir:`), sans `--distro` (`scanner.sh`, `NATURE=deb`).
- Le rpm n'est pas encore scanné dans la plateforme.

**Options**, compatibles entre elles (correction de 19:03:57Z) :
- **(a)** la porte refuse un scan de paquets dont la `distro` est vide ;
- **(b)** le job passe `--distro` explicitement ;
- **(a) et (b)** ensemble.

**Couplages** : aucun avec G7 ni le rejeu. C'est à trancher quand le scan du rpm entrera dans la plateforme.

## Corrections et compléments (note de 2026-11-20T20:07:45Z ; rien n'est réécrit au-dessus)

Le conseiller a relu ce fichier avant la poussée. Les dossiers ci-dessus restent écrits tels quels. Voici ce qu'il y manquait.

**Dossier 1, le cas le plus probable manquait.**
- Le n°8 finit le 28/11 vers 02:52, d'après le calcul. Un rejeu « le 28/11 » tombe donc presque sûrement **après le n°8 et avant le n°9** : N8 est vu, N9 est perdu. « Avant le n°8 » suppose un rejeu en pleine nuit.
- Comme le rejeu efface Loki, il faut alors **lire le n°8 avant de lancer le rejeu**.
- La tâche (b) du point 4 de G7 (29/11 à 05:40) lirait un Loki vide si le rejeu passait avant elle. **Le choix de la tâche dépend donc de la date du rejeu**, qui se tranche en premier.
- Options révisées :
  - (i) rejeu après la lecture du n°9, le 29/11 à partir de 05:40 environ ;
  - (ii) rejeu le 28/11 après la lecture du n°8, à partir de 05:00 environ : N9 et le premier scan du deb ne sont pas vus ;
  - (iii) rejeu plus tôt : G7 repart de zéro.

**Dossier 3, option (ii) : affirmation sans mesure.** « Le rejeu repart avec la marge mesurée le 20/11 » n'est pas établi : un rejeu de zéro recrée un Zot et un Loki vides. Le fait mesuré est celui-ci : S5b a recréé sc-stockage sur 20G le 13/11, et il restait 2 820 Mo libres le 20/11 à 15:59, sept jours plus tard.

**Dossier 4, option (i) : portée de la mesure.** « Les digests actuels restent valables » n'est mesuré que sur les 9 bundles de la 05 (RE7). Pour les bundles des autres briques, c'est déduit : même fonction, même hôte, même fuseau.

**Dossier 6, ce qui manquait pour trancher.**
- **Seuil « bit-identique »** : `m3_comparaison`, le 17/11 à 20:21:03 UTC. Elle donne les mêmes NEVRA et les mêmes sha256 pour le src.rpm (`c802e60a…`) et le rpm (`864d55f4…`) entre deux `--hermetic-build` dans deux répertoires, avec « écarts du critère : 0 » (README de la 05, journal du 17/11). Le rpm de M4b, de M4c et de leurs reprises sur M1b est ce même rpm.
- **Seuil « 0 pod privilégié sur l'hôte »**, lu comme le test 4 de la 08 (D1 (a)) : R8 de M5a. `construire-rpm` sans Kata est refusé par Pod Security (`PodAdmissionFailed`), et aucun pod n'est créé (`m5-predictions.md`, bilan de M5a). Ce test a été rejoué dans la cascade (RJ1 à RJ12).
- Le **rejeu de zéro**, quatrième élément du jalon M5, n'est pas passé : c'est M5b.
- **Effort**, même méthode que `temps-05-1211.log` (date d'auteur, écarts d'au plus 1 h entre commits touchant la brique) : **46.78 h, 396 commits**, au dernier commit de la brique (`3d09ede7`). Le contrôle de la méthode redonne 42.82 h à `a4360d3b`, comme le relevé précédent. L'estimation du README est de 2,5 pw, avec décision à 5 pw. Je ne convertis pas les heures.

**Recommandations, avec leurs contraintes** (passées par le conseiller) :
- **Dossier 1 : (i), rejeu après la lecture du n°9.** Il coûte un jour, et c'est la seule occasion de voir supprimer un scan du deb. Contrainte : aucun passage de `stockage.sh zot` d'ici là.
- **Dossier 3 : (i), `vm.sh` à 30G**, ce qui est cohérent avec « Agrandir maintenant ». Contrainte : le modifier avant le rejeu, avec un banc de `vm.sh` à sec.
- **Dossier 4 : (iii) pour ce rejeu**, `TZ` laissé à l'hôte. On ne modifie pas `commun.sh` juste avant un rejeu jamais exécuté, et `m5b-republier.sh` pose déjà `TZ` pour la 05. La décision pour toute la plateforme peut venir après.
- **Dossier 5 : (i), une barrière, en réserve écrite.** La seconde rouvrirait la signature et la cascade.
- **Dossier 2** : pas de recommandation. Ce que Zot permet par dépôt n'est pas relu.
- **Dossier 6** : pas de recommandation. C'est ta décision, et elle dépend de la date du rejeu.
- **Dossier 7** : pas de recommandation, puisque le scan du rpm n'est pas dans la plateforme.

## Dossier 2 : rétention de Zot lue dans le code (note de 2026-11-20T20:18:43Z ; rien n'est réécrit au-dessus)

**Lecture** du code de Zot au tag `v2.1.22`, la version épinglée par `stockage.sh`, par l'API publique de GitHub, sans rien télécharger dans le dépôt :
- `pkg/api/config/config.go`, structures `ImageRetention`, `RetentionPolicy`, `KeepTagsPolicy` et `KeepUntaggedPolicy` ;
- `pkg/storage/gc/gc.go` (sha256 `4205b7bc4aa3654a…`), fonctions `removeUntaggedManifests`, `removeManifestIfOlderThan` et `isBlobOlderThan` ;
- `pkg/retention/retention.go`.

**Ce que le code dit** :
- **Le délai est global.** `ImageRetention.Delay`, commenté « applied for referrers and untagged », n'existe qu'une fois, pour toutes les politiques. Il n'y a **pas de délai propre à un dépôt** en v2.1.22.
- Une politique de dépôt ne règle que les points suivants :
  - `deleteReferrers` et `deleteUntagged` ;
  - `keepTags` : motifs, `mostRecentlyPushedCount`, `mostRecentlyPulledCount`, `pushedWithin`, `pulledWithin` ;
  - `keepUntagged`, avec les mêmes critères. Ce réglage ne peut que garder davantage.
- **Un manifeste non tagué n'est effacé que si son fichier a plus que ce délai.** Le critère est la date de modification du blob du manifeste (`StatBlob`, `modtime + delay`). Ce n'est ni le `pushTimestamp` de la base de métadonnées ni une annotation.
- Les blobs devenus orphelins sont effacés ensuite, au délai `gcDelay` (1 h).

**Conséquence pour le dossier 2** (calcul, à partir du code) :
- Baisser `mostRecentlyPushedCount` sous 14 **ne libère rien**. Une base détaguée plus tôt reste jusqu'à ses 336 h. L'équilibre reste d'environ 14 bases, soit 2,8 à 3 Go.
- Seule une baisse du délai global libère de la place. Mais elle raccourcit aussi la vie des scans de `builds/scan/**`, que lit la porte et que G7 mesure.
- Une autre voie existe hors de la configuration : effacer explicitement les vieilles bases par l'API, depuis l'import quotidien. C'est une écriture dans Zot, et donc ton accord. Elle n'est pas évaluée ici.

**Options révisées** :
- (i) garder la rétention ;
- (ii) baisser le délai global, ce qui change aussi la vie des scans ;
- (iii) effacer les vieilles bases par l'import.

Je n'ai toujours pas de recommandation : (ii) et (iii) touchent tous deux à des choses mesurées par G7.

## Dossier 3 : correctif préparé à sec, NON APPLIQUÉ (note de 2026-11-20T20:20:55Z ; rien n'est réécrit au-dessus)

Il ne sert que si tu choisis l'option (i).

**Correctif** [`vm-30g.patch`](vm-30g.patch) : une seule ligne de `08-trust-plane/vm.sh`, la ligne 25 (`TAILLE[sc-stockage]` de 20G à 30G), avec un commentaire.
- `vm.sh` dans le dépôt : sha256 `6268db0da362ad84…`, non modifié.
- Copie corrigée, hors du dépôt : sha256 `2e725deee5ec0597…`.

**Contrôles à sec** :
- `bash -n` passe. shellcheck ne relève aucun avertissement (`-S warning -x`), ni sur la copie ni sur le dépôt.
- La ligne 25 de la copie, évaluée seule avec la règle de la ligne 27, donne :
  - sous k3s : confiance 15G, build 30G, stockage 30G ;
  - sous RKE2 : confiance 25G, build 30G, stockage 30G.
- Rien n'est créé : `vm.sh` n'a pas tourné.

**Place sur l'hôte**, relevée sans sudo dans la même session :
- `/` : 61 845 Mo libres ;
- disques des VM, allocation réelle (`virsh vol-info`) : sc-confiance 11,64 GiB, sc-build 20,13 GiB, sc-stockage 17,29 GiB ;
- capacité totale sous RKE2 avec le correctif : 85G. Les volumes sont fins (qcow2), et un rejeu repart d'images neuves.

Si tu choisis (i), je l'applique avant le rejeu, puis je repasse `bash -n` et shellcheck sur le dépôt.

## Décision du propriétaire sur le dossier 1 (note de 2026-11-20T20:21:48Z ; rien n'est réécrit au-dessus)

Question posée : « Quand se fait le rejeu de M5b ? », avec deux choix : « Après le n°9 » et « Le 28/11, après le n°8 ». **Réponse : « Après le n°9 ».**

- Le rejeu de M5b ne commence pas avant la lecture du balayage n°9 de G7. D'après la projection, ce balayage finit au plus tard le 29/11 vers 03:36 UTC, et la lecture se fait au plus tôt vers 05:40 UTC. C'est un calcul.
- **Contrainte jusque-là** : aucun passage de `stockage.sh zot`, ni aucune recréation de sc-stockage. Un redémarrage de Zot déplacerait les balayages.
- Si Zot redémarrait quand même, la lecture du n°9 se ferait à la nouvelle heure, que la loi B permet de recalculer depuis le redémarrage.
- La décision rend possible l'option (b) du point 4 de G7 : une tâche le 29/11 à 05:40 UTC. Le choix entre (a), (b) et (c) reste à toi.
- Le dossier 6 (clôture) n'est pas tranché. Clore après M5b voudrait dire clore au plus tôt le 29/11.

## Dossier 2, option (iii) : effacer les vieilles bases, lu dans le code (note de 2026-11-20T20:42:13Z ; rien n'est réécrit au-dessus)

La note de 20:18:43Z laissait l'option (iii) non évaluée. Lecture du code de Zot au tag `v2.1.22`, par l'API publique de GitHub, comme pour `gc.go` :
- `pkg/api/routes.go` (sha256 `7b7b3443b3df4cd5…`) ;
- `pkg/api/authz.go` (`46d3b41ffbdffb3a…`) ;
- `pkg/storage/imagestore/imagestore.go` (`2819ca7ba2904b75…`) ;
- `pkg/storage/common/common.go` (`db848f6ceb693e9f…`).

**Ce que le code dit** :
- **Effacer un manifeste demande le droit `delete`** : une requête `DELETE` prend l'action `DeletePermission` (`authz.go`, `DistSpecAuthzHandler`). Dans `zot.json`, `poc-vulndb` n'a que `read` et `create` sur `vulndb/**`. Le commentaire de `fetch-db.sh` le rappelle : « poc-vulndb n'a que le droit de créer ».
- **Par tag, rien n'est libéré.** `RemoveManifestDescByReference` ne retire que le tag ; le manifeste reste, non tagué, et attend la rétention, donc ses 336 h.
- **Par digest, le manifeste part tout de suite** (`deleteImageManifest` efface son blob). Ses couches deviennent orphelines. D'après le code, elles partent au balayage suivant (`gcInterval` 24 h), puisqu'elles ont plus que `gcDelay` (1 h) (`deleteUnreferencedBlobs`). Ce n'est pas mesuré.
- La porte ne relit pas la base : elle juge `scanner.db.built` dans le prédicat du scan (`scan.rego`). Le scanneur prend la base la plus récente.

**Ce que (iii) demanderait** (relevé, rien n'est fait) :
- un compte qui a le droit `delete` sur `vulndb/**`, dans `zot.json`. Deux variantes, aucune essayée :
  - donner `delete` à `poc-vulndb` lui-même ;
  - un compte distinct, avec `read` et `delete` seulement, pour l'effacement.
- Dans les deux cas, c'est un changement de politique de Zot, donc un passage de `stockage.sh zot` et un redémarrage : après le n°9, ou seulement dans le dépôt avant le rejeu ;
- un effacement par digest dans `base-grype.sh` ou `fetch-db.sh`, déployé sur sc-stockage ;
- une écriture quotidienne dans Zot par un service.

**Ce que (iii) ferait perdre** :
- **avec la première variante, la garantie « création seulement » de G1.** Aujourd'hui, `poc-vulndb` ne peut pas remplacer un tag (`plateforme.sh`, essai « même tag repoussé » refusé). Avec `delete`, il pourrait effacer une base puis repousser un autre contenu sous le même tag. C'est déduit de `authz.go`, pas mesuré. Le compte distinct garde cette garantie à `poc-vulndb`, mais il ajoute un secret ;
- dans les deux variantes, les bases citées par digest dans les scans encore gardés (`.scanner.db.ref`), si elles partent avant ces scans (336 h). Un scan ne pourrait plus être rejoué avec sa base.

**Place, en calcul** (bases de 200,7 à 205,2 Mo de couches, relevé du 20/11 ; aucune autre écriture comptée) :
- (i), rétention gardée : environ 14 bases, soit 2,8 à 3 Go à l'équilibre, comme au dossier 2 ;
- (ii), délai global seul baissé sous 11 jours : `mostRecentlyPushedCount: 11` garde quand même 11 bases, soit 2,2 à 2,3 Go. Le gain est d'environ 0,6 Go, et les scans vivent moins longtemps. En baissant **le délai et le compte ensemble**, on garde à peu près max(compte, délai en jours) bases, sans droit `delete`. Les scans ne vivent alors que ce délai ;
- (iii), garder K bases : K × 0,2 Go environ. Ni la porte ni le scanneur n'imposent de plancher à K : le scanneur prend la plus récente, et la porte ne juge que `scanner.db.built`. Par exemple, K = 4 donne environ 0,8 Go.
- Mesure de comparaison : 12 491 Mo libres sur sc-stockage après l'agrandissement à 30G du 20/11 (AG1 à AG5). Le passage de `vm.sh` à 30G est le dossier 3.

Les options restent (i), (ii) et (iii). Ce fichier n'en tranche aucune.

## Décision du propriétaire sur le dossier 3 : correctif appliqué (note de 2026-11-20T20:49:03Z ; rien n'est réécrit au-dessus)

Question posée : « Je l'applique, ou on garde 20G ? », à propos de [`vm-30g.patch`](vm-30g.patch). **Réponse : « Ok ».** C'est l'option (i), celle que je recommandais.

**Application** :
- `08-trust-plane/vm.sh` : sha256 avant `6268db0da362ad84…`, après `2e725deee5ec0597…`. C'est l'empreinte de la copie contrôlée à sec (note de 20:20:55Z).
- `patch -p0`, lancé depuis `08-trust-plane/`, essayé d'abord à sec. Le correctif est écrit pour ce dossier : un essai lancé depuis la racine du dépôt avait échoué sans rien modifier.

**Contrôles repassés sur le dépôt** :
- `bash -n` et shellcheck (`-S warning -x`) passent.
- La ligne 25, évaluée seule avec la règle de la ligne 27, donne sous k3s 15G, 30G et 30G, et sous RKE2 25G, 30G et 30G (confiance, build, stockage).

**Portée** : rien ne tourne. Le disque actuel de sc-stockage est déjà à 30G depuis « Agrandir maintenant ». `vm.sh` ne crée de disque qu'au rejeu de M5b, qui recréera donc sc-stockage à 30G. Aucun banc de `vm.sh creer` n'est passé.

## Décision du propriétaire sur le dossier 4 : `TZ` laissé à l'hôte pour ce rejeu (note de 2026-11-20T20:50:43Z ; rien n'est réécrit au-dessus)

Question posée : (iii) laisser `TZ` à l'hôte pour ce rejeu, ou (i) `TZ=Europe/Paris` dans `bundle`. **Réponse : « Ta recommandation »**, donc (iii).

- `08-trust-plane/commun.sh` n'est pas modifié. `bundle` reste sans `TZ=`, et les digests des bundles dépendent toujours du fuseau de l'hôte.
- Pour la 05, `m5b-republier.sh` pose déjà `TZ=Europe/Paris` (relu à l'instant dans le dépôt). D'après RE1 à RE7, mesurés sur cet hôte, `TZ=Europe/Paris` redonne les 9 digests de la liste revue. Sur un autre hôte, c'est déduit, pas mesuré.
- **Réserve** : les bundles des autres briques (01, 03, 06, 08) ne sont reproductibles que depuis un hôte réglé sur le même fuseau. La décision pour toute la plateforme reste ouverte, après le rejeu.

## Dossier 5 : la barrière unique relue (note de 2026-11-20T21:03:02Z ; question du propriétaire « La network policy est-elle réellement suffisante ? » ; rien n'est réécrit au-dessus ; AUCUNE DÉCISION)

**Mesuré** :
- RE3 de M5a : sous le label `construire-rpm`, la connexion est refusée depuis le pod comme depuis `%build`.
- `construction-rpm-sans-sortie` n'a aucune règle : tout est refusé, en entrée comme en sortie, DNS et API du cluster compris.
- Sous Cilium, depuis un pod Kata privilégié (`kata-reseau-cilium-apres-redemarrage.log` de la 08) : aucune fenêtre au démarrage en 3 essais, et usurpation d'adresse source refusée (`INVALID_SOURCE_IP`).

**Lu dans les tâches signées, et non mesuré comme mode de panne** :
- Le premier pas de `construire-rpm` (`construire-rpm.m1b.signee.yaml`) lance des témoins **avant mock** : DNS de `dl.rockylinux.org`, TCP vers Zot (5000), Forgejo (3000) et une adresse publique (80). **Il s'arrête en échec si l'un d'eux réussit.** `construire-racine-rpm` a les mêmes témoins, sans l'adresse publique.
- Si la politique manquait, ou si le label ne correspondait plus, `builds-sans-internet` laisserait encore Zot joignable (son en-tête : elle ne ferme ni sc-stockage, ni le DNS, ni l'API). Le témoin Zot réussirait, et la construction s'arrêterait avant mock. **La barrière échoue donc fermée au démarrage.** C'est déduit de la lecture ; ce cas n'a pas été provoqué.
- Le label vient du contrôleur de Tekton, qui le réécrit depuis le nom de la tâche résolue. C'est lu dans le code de Tekton (en-tête de la politique de la 08), pas mesuré ici.

**Limites** :
- Les témoins ne regardent qu'au démarrage. Une politique retirée pendant la construction (46 s pour le témoin de M5a) ne serait pas vue.
- Vers Internet, deux politiques ferment la sortie (`construction-rpm-sans-sortie` et `builds-sans-internet`). Mais elles passent par le même moteur, Cilium : elles sont deux en nombre, pas indépendantes. Vers Zot, le DNS et l'API, il n'y en a qu'une.
- Aucun contrôle continu de la présence de la politique n'a été trouvé hors des tâches. Elle n'est vérifiée qu'à la pose, par les invariants de `sortie-builds.sh`.
- Ce que pourrait faire le code de `%build` contre la politique depuis l'invité Kata : seule l'usurpation a été mesurée. « Il faudrait sortir de la VM » est une déduction.
- La barrière réseau ne couvre pas l'autre voie de sortie : le contenu du rpm lui-même. Un `%build` hostile et déterministe passerait la confrontation bit-identique.
- L'utilisateur sous lequel mock lance `%build` n'a pas été relevé.

Les options restent (i) et (ii). Une piste de contrôle hors de la tâche signée, qui ne rouvrirait ni la signature ni la cascade, serait un relevé périodique des politiques de `builds`. Elle n'est ni écrite ni essayée.

## Décision du propriétaire sur le dossier 5 : une barrière, en réserve écrite (note de 2026-11-20T21:05:43Z ; rien n'est réécrit au-dessus)

Question posée : (i) une barrière, avec les limites de la note précédente en réserve écrite, ou un relevé périodique des politiques de `builds` en plus. **Réponse : « Ok i ».**

- Rien n'est modifié : ni `construire-rpm`, ni `construire-racine-rpm`, ni leurs politiques. Pas de nouvelle signature, et la cascade de M1b reste valable.
- **Réserve de la 05**, à reprendre à la clôture :
  - une seule politique réseau coupe la voie rpm pendant `%build`, parce que mock en `--isolation=simple` ne crée pas d'espace de noms réseau ;
  - les témoins des tâches signées font échouer la construction, fermée, au démarrage seulement ;
  - aucun contrôle continu de la politique n'existe ;
  - les deux politiques vers Internet passent par le même moteur ;
  - le contenu du rpm reste une voie de sortie que la barrière réseau ne couvre pas.
- Le relevé périodique des politiques reste une piste, ni écrite ni essayée.

## Correction de la réserve du dossier 5 (note de 2026-11-20T21:07:59Z ; relecture du conseiller ; rien n'est réécrit au-dessus)

Deux lignes de la réserve écrite à la décision affirment plus que ce qui est établi :
- « aucun contrôle continu de la politique n'existe » : lire **aucun trouvé**. La recherche n'a porté que sur `sortie-builds.sh` et `invariants`, dans les `.timer`, `.service` et `.yaml` du dépôt, plus les rôles et les règles Kyverno de la 08c.
- « les témoins font échouer la construction, fermée, au démarrage » : c'est **lu dans les tâches signées, pas provoqué**. La moitié en est mesurée : le bras a de R7 de M5a a joint Zot sans le label, ce qui ferait réussir le témoin Zot et arrêter la tâche. L'arrêt de la tâche signée elle-même dans ce cas n'a pas été mesuré.

## Lecture de Konflux en mode hermétique, et demande de journaux réseau (note de 2026-11-20T21:28:28Z ; rien n'est réécrit au-dessus ; décision (i) inchangée)

Question du propriétaire : « Comment Konflux fonctionne lui en hermetic à true ? ». Lu par l'API publique de GitHub, sans rien télécharger dans le dépôt :
- `konflux-ci/rpmbuild-pipeline` au commit `27d94051`, `task/rpmbuild.yaml` (sha256 `6b58d680…`) et `docs/architecture.md` (`897c7dc1…`) ;
- `konflux-ci/konflux-build-cli` au commit `58526622`, `pkg/commands/build.go` (`3f2f9c4e…`), appelé par la tâche buildah 0.14.2 de `konflux-ci/container-build-catalog` au commit `774bb868` (`f18fef21…`).

**Ce que le code dit** :
- Images : en hermétique, `konflux-build-cli` lance `buildah build` sous `unshare --net`, un espace de noms réseau sans sortie. Le commentaire du code dit que `--network=none` de buildah ne couvre pas `ADD`.
- rpm : `calculate-deps` n'est pas hermétique ; il écrit un verrou, et les rpm listés sont téléchargés dans un dépôt local. `rpmbuild` tourne sur une **VM dédiée** par architecture, pilotée par ssh depuis le pod (contrôleur multi-plateforme), avec `podman run --network=none --privileged -u mockbuilder … mock --hermetic-build`.
- La coupure est donc dans le conteneur de mock, sur une machine hors du cluster. Le filtrage réseau de ces VM n'est pas lu.

**Chez nous** (rappel) : podman imbriqué fonctionne dans le pod Kata (P8, essais du 17/11, `pull` et `image mount`). `podman run --network=none` autour de mock n'a jamais été essayé : ce serait l'option (ii), qui change la tâche signée.

**Décision du propriétaire** : « Gardons ce qu'on fait ». (i) reste la décision.

**Demande du propriétaire, même message** : « avoir également les logs réseau du container pour voir ceux bloqués (normalement tous) et ceux autorisés (normalement aucun) ». C'est le J7 de la 19b (flux Hubble), resté optionnel. Il répond en partie à la limite « aucun contrôle continu trouvé » de ce dossier. Détail : [README de la 19b](../../19b-journalisation/README.md), note de 2026-11-20T21:28:28Z.

## Décision du propriétaire sur le dossier 2 : rétention gardée pour ce rejeu (note de 2026-11-20T21:32:17Z ; rien n'est réécrit au-dessus)

Question posée : « On retient (i) pour ce rejeu ? », après la recommandation du conseiller (i). **Réponse : « Oui ».**

- `zot.json` n'est pas modifié : délai de 336 h, `mostRecentlyPushedCount: 11` et `deleteUntagged: true` pour `vulndb/grype` (relu à l'instant dans le dépôt). Le rejeu posera la même rétention.
- Raisons retenues :
  - (ii) et (iii) passeraient par un redémarrage de Zot, exclu avant le n°9 ;
  - (ii) seule ne rend qu'environ 0,6 Go (calcul), et change ce que G7 mesure ;
  - (iii) n'est pas essayée, et elle coûte la garantie « création seulement » ou un compte de plus ;
  - le disque est à 30G (dossier 3).
- **À revoir** avec le relevé `df` de sc-stockage du 21/11 vers 16:00 UTC et l'état du 29/11. Deux rythmes de remplissage ne sont pas rapprochés : 1,19 Go par jour le 18/11, et environ 200 Mo par jour attribués à grype. L'équilibre à environ 14 bases est un calcul ; la tâche du 29/11 le lira.

## Décision du propriétaire sur le dossier 6 : clôture après M5b (note de 2026-11-20T21:33:46Z ; rien n'est réécrit au-dessus)

Question posée : « On clôt la 05 maintenant avec M5b en réserve, ou après M5b ? », sans recommandation. **Réponse : « Après ».**

- La 05 reste ouverte jusqu'au rejeu de zéro (M5b). Celui-ci attend la lecture du balayage n°9 de G7, le 29/11 vers 05:40 UTC au plus tôt (calcul ; dossier 1).
- Les décisions des dossiers 2 à 5 valent pour ce rejeu : rétention grype gardée, `vm.sh` à 30G, `TZ` laissé à l'hôte, une barrière réseau en réserve.
- Le dossier 7 (D14) n'est pas lié à la clôture : il se tranchera quand le scan du rpm entrera dans la plateforme.
- Effort au 20/11 : 46,78 h de commits (note de 20:07:45Z), pour une estimation de 2,5 pw avec décision à 5 pw. Je ne convertis pas les heures ; l'effort sera relevé de nouveau à la clôture.
