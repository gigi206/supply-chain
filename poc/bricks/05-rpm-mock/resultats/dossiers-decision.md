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
