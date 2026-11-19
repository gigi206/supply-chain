# ADR 0007 : constructions indépendantes du langage et du format de sortie

- **Statut** : **Proposé**. L'exigence est décidée par le propriétaire ; sa mise en œuvre reste à concevoir.
- **Date** : 2026-11-10 (exigence formulée à 22:41:02 UTC)
- **Décideurs** : propriétaire du projet

## Contexte

L'exigence est apparue en préparant S4 de la brique 06 (deb dans Tekton). Le PoC ne traite aujourd'hui qu'un cas, `sample-app` (Go et npm), de façon propre à ce cas. État vérifié dans le dépôt le 10/11/2026 :

- **Go** : les dépendances passent par la plateforme. La tâche `prefetch-gomod` appelle Hermeto avec le seul type `gomod`. `publier-fermeture` publie la fermeture, et la règle `fermeture_plateforme` de `porte.rego` la contrôle (D6 de la brique 03).
- **npm** : il reste hors de la chaîne. `web/dist` est construit hors de la plateforme, puis poussé dans Zot par l'hôte (`construction.sh` de la 08 : « Node reste hors de la chaîne »). Pour le deb, `poc/packaging/sources.sh` embarque `node_modules` depuis l'hôte.
- **La porte** n'admet qu'une seule fermeture, et seulement si elle vient de `prefetch-gomod`. Ce nom est écrit en dur dans la règle.
- **Le packaging** (`debian/`, `sample-app.spec`) vit dans `poc/packaging`, hors du dépôt du projet. Le paquet source est assemblé sur l'hôte.

Résultat : pour un projet Go + npm, une partie des dépendances échappe déjà à la chaîne L3. Les autres langages ne sont pas prévus.

## Exigence du propriétaire (10/11/2026, 22:41:02 UTC)

> « on doit pouvoir build n'importe quel projet dans n'importe quel langage, avoir les binaires mais aussi pouvoir les packager en rpm, deb, docker, etc »
>
> « Et on ne doit jamais modifier le code source du projet, sauf branche ou tag custom »

## Décision

1. **N'importe quel projet, n'importe quel langage.** Un projet peut mêler plusieurs technologies, comme Go et npm. La chaîne ne suppose ni un langage ni un nombre de langages.
2. **Plusieurs sorties pour une même construction** : les binaires, puis leur packaging en rpm, deb, image OCI, et d'autres formats à venir.
3. **Le code source du projet n'est jamais modifié par la plateforme.** Seule exception : une branche ou un tag custom (voir le fork `workspace/sample-app-sync` de la brique 01). Tout ce que la plateforme ajoute vit hors du dépôt du projet : packaging, verrous de distribution, configuration de build.

## Conséquences

### Principes de conception (à mesurer, pas encore mesurés)

- **Un prefetch par écosystème, sans pipeline propre à un langage.** Chaque écosystème déclaré par le projet donne une fermeture produite par la plateforme : `gomod`, `npm`, `pip`, `cargo`, etc., et `deb` ou `rpm` pour les dépendances de packaging. Hermeto est le candidat pour les écosystèmes applicatifs. Restent **à vérifier** dans la version épinglée : les gestionnaires qu'il couvre, et s'il en traite plusieurs en un seul appel.
- **Une règle de porte générique.** Une construction déclare N fermetures. Chacune doit venir d'une tâche de prefetch inscrite dans la liste revue, au lieu d'un nom écrit en dur.
- **Les formats de sortie consomment les fermetures.** Image, deb et rpm se construisent depuis le commit et les fermetures, jamais depuis des sources assemblées sur l'hôte.
- **Le packaging reste hors du dépôt du projet.** C'est cohérent avec la décision « packaging hors du dépôt » de la 06 (22:12:03 UTC), et avec le verrou deb placé avec `debian/` (22:20:23 UTC).

### Décisions antérieures touchées (à rouvrir avec le propriétaire, rien n'est rouvert ici)

- **D6 de la brique 03** (« fermeture produite par la plateforme ») : le principe tient, mais la règle doit passer d'une fermeture `prefetch-gomod` à N fermetures d'écosystèmes approuvés.
- **« Node reste hors de la chaîne »** (voie image, brique 04 et 08) et **« web/dist par digest »** (brique 06, 10/11/2026) : ces choix contredisent l'exigence, puisque npm doit entrer dans la chaîne.
- **S4 de la brique 06** : son découpage du 10/11/2026 (22:14 et 22:21 UTC) suppose une fermeture gomod spécifique. Il est à revoir après cet ADR.
- **Option écartée** : publier par l'hôte le `.dsc` complet de `sources.sh`. Elle ferait entrer les dépendances par l'hôte.

### Plan de sortie

Les fermetures restent des artefacts OCI ordinaires dans Zot, avec un fichier par couche. Elles ne dépendent pas de l'outil de prefetch, qui peut être remplacé écosystème par écosystème, par Hermeto ou par le vendoring natif scripté (doc 04).

**Additif du 10/11/2026, 23:40 UTC : premier prefetch deb mesuré** (brique 06, S4a, [résultats](../../poc/bricks/06-deb-sbuild/resultats/s4a-predictions.md)).
- **Mesuré** : la tâche `prefetch-deb` tourne en runc restreint, sans root ni secret. Sa sortie se limite au DNS et au port 80 public. Elle télécharge par `apt-helper` une liste épinglée, contrôlée par l'InRelease (sha256 fixé par la pipeline signée), puis par les index et par le sha256 de chaque paquet. Elle sert ici à l'image de build ; sa provenance nomme l'InRelease.
- **Non mesuré** : le refus d'un hash faux (test négatif prévu en S5) et l'usage de la tâche pour une fermeture de construction (S4b).
- **La porte reste limitée à `prefetch-gomod`**, et la règle générique à N fermetures n'est pas écrite.

**Additif du 11/11/2026, 16:20 UTC : `marked` par la plateforme pour le deb** (brique 06, [README](../../poc/bricks/06-deb-sbuild/README.md)).
- **Décision du propriétaire** (16:19:27 UTC) : « npm par la plateforme », pour le deb. Elle remplace, pour le deb, « web/dist par digest » (10/11/2026, 22:30 UTC). La voie image de la 08 garde `web/dist` par digest : la dette reste ouverte.
- **Vérifié dans le code d'Hermeto 0.64.0** : le fetch npm ne lance aucune commande externe, donc ni `node` ni `npm`. Le point « gestionnaires couverts » est donc tranché pour npm. Hermeto traite gomod et npm en un seul appel, mesuré sur l'hôte (banc nix), pas encore dans la plateforme.
- **Non mesuré** : la fermeture npm produite par une tâche de la plateforme, et la règle de porte à N fermetures.

**Additif du 11/11/2026, 16:48 UTC : choix de S4b** (brique 06, [README](../../poc/bricks/06-deb-sbuild/README.md)).
- **Décision du propriétaire** (16:42:27 UTC) : « A, N1, combinée ».
- **Écart au principe « chaque écosystème déclaré par le projet donne une fermeture »** : gomod et npm donnent une seule fermeture applicative, en un seul appel à Hermeto. Le principe devient « une fermeture par appel de prefetch », avec un ou plusieurs écosystèmes.
- **Le verrou deb est lu par l'hôte** : la liste est inscrite dans la pipeline signée au rendu, et la plateforme ne lit pas l'artefact de packaging en S4b. La confrontation de la fermeture deb au verrou est reportée à S4d.
- **Le nom `prefetch-gomod` devient trompeur** : sa version 2 produit aussi npm. Le renommage est reporté à la règle de porte générique.
- **Non mesuré** : tout ce qui précède. Les prédictions de S4b seront commitées avant toute exécution.

**Additif du 11/11/2026, 17:37 UTC : S4b mesuré** (brique 06, [résultats](../../poc/bricks/06-deb-sbuild/resultats/s4b-predictions.md)).
- **Mesuré** : une fermeture applicative gomod et npm, produite par un seul appel à Hermeto dans la plateforme (`prefetch-gomod` version 2, lockfile npm contrôlé avant Hermeto), et une fermeture deb, produite par `prefetch-deb` sur la liste du verrou. Toutes deux sont publiées par `publier-fermeture`, signées par Chains et reproductibles au digest près.
- **Le point « gestionnaires couverts » est mesuré pour npm** dans la plateforme, sans Node dans l'image d'outils.
- **Non mesuré** : la règle de porte à N fermetures, la confrontation de la fermeture deb au verrou à la construction (S4d), et le refus d'une archive altérée dans la plateforme (S5).

**Additif du 11/11/2026, 19:58 UTC : S4d1 mesuré** (brique 06, [résultats](../../poc/bricks/06-deb-sbuild/resultats/s4d-predictions.md)).
- **Mesuré** : la fermeture deb est confrontée au verrou dans la plateforme (`preparer-deb`), qui consomme deux fermetures (deb et applicative) et un artefact de packaging, tous tirés par digest et déclarés à Chains. La construction ne prend ses dépendances que dans ces fermetures, sans réseau, et rend le même deb que l'hôte et OBS.
- **Non mesuré** : la règle de porte à N fermetures (S4d2), le refus d'une archive altérée dans la plateforme (S5).

**Additif du 11/11/2026, 20:24 UTC : S4d2a mesuré** (brique 06, [résultats](../../poc/bricks/06-deb-sbuild/resultats/s4d2-predictions.md)).
- **Mesuré** : la porte de release juge une construction à plusieurs fermetures. Chaque fermeture est typée par le nom du résultat qui la déclare, et prouvée par la pipeline de prefetch de sa forme : `prefetch-deb` sans git pour le deb, `prefetch-gomod` avec le même dépôt Forgejo pour les sources. Chaque résultat attendu de la préparation est exigé.
- **Conséquence pour la règle générique** : une nouvelle forme de fermeture demande une entrée dans `_attendues` et une branche de `_forme` dans `porte.rego`. Le nom des tâches reste écrit en dur.
- **Non mesuré** : VSA et scan d'un deb (jalon séparé), le refus d'une archive altérée dans la plateforme (S5).

**Additif du 11/11/2026, 21:05 UTC : S4d3 mesuré** (brique 06, [résultats](../../poc/bricks/06-deb-sbuild/resultats/s4d3-predictions.md)).
- **Mesuré** : une seconde forme de construction s'ajoute aux déclencheurs sans toucher à ceux de la première, ni au code du rattrapage.
  - Un Trigger est sélectionné par label, avec ses propres intercepteurs.
  - Un gabarit est créé, avec les seuls paramètres `commit` et `depot`.
  - Un CronJob reprend le binaire du rattrapage, sous son propre compte.
- **Conséquence pour la règle générique** : chaque nouvelle forme apporte son gabarit, son Trigger et son CronJob. L'EventListener et `main.go` restent communs. Le CronJob doit reprendre les correctifs que la 08c pose par patch : les limites en sont un.
- **Non mesuré** : deux constructions simultanées d'un même push, VSA et scan d'un deb (jalon séparé), et le refus d'une archive altérée dans la plateforme (S5).


**Additif du 11/11/2026, 21:52 UTC : S5a mesuré** (brique 06, [résultats](../../poc/bricks/06-deb-sbuild/resultats/s5-predictions.md)).
- **Mesuré** : la construction deb refuse une archive altérée à chaque niveau.
  - Au téléchargement, `apt-helper` refuse un hash faux.
  - Dans le miroir, la tâche le revérifie, puis apt contrôle la signature de l'InRelease et le hash des paquets.
  - Dans la fermeture, la confrontation au verrou refuse un paquet modifié ou un fichier en trop.

  Sous sbuild unshare, la construction n'a aucun réseau. Hors Kata, la tâche privilégiée est refusée.
- **Conséquence pour la règle générique** : un gestionnaire dont l'outil de construction ne vérifie pas les hash (sbuild et `--extra-package`, comme les paquets natifs de yarn) doit être confronté à un verrou dans la tâche de préparation. Le tirage par digest ne suffit pas, puisqu'il accepte une fermeture cohérente mais différente.
- **Non mesuré** : le rejeu de zéro (S5b, jalon de plateforme), VSA et scan d'un deb (jalon séparé).

**Additif du 18/11/2026, 13:08 UTC : M4b de la brique 05 mesuré** (brique 05, [résultats](../../poc/bricks/05-rpm-mock/resultats/m4b-predictions.md)).
- **Mesuré** : une fermeture rpm produite par la plateforme. La tâche neuve `prefetch-rpm` (runc, sans root) prend la liste des 222 rpm du verrou, inscrite par l'hôte dans la pipeline signée, comme `prefetch-deb` en S4b. Elle contrôle chaque rpm (sha256, taille, signature de Rocky), bâtit `repodata` de façon reproductible et copie l'image de bootstrap de mock par digest.
- `publier-fermeture` est reprise sans changement. Deux PipelineRuns donnent la même fermeture au digest près. Tirée de Zot, elle est égale fichier par fichier à celle mesurée dans les pods d'essai. Chaque PipelineRun a une provenance signée par Chains, qui nomme les tâches, la liste et l'image de bootstrap.
- **Conséquence pour la règle générique** : le rpm suit le schéma du deb (liste lue par l'hôte, prefetch dans la plateforme, publication commune). Une troisième forme de fermeture demandera, d'après S4d2a, son entrée dans `_attendues` et sa branche de `_forme` dans `porte.rego`.
- **Non mesuré** : la construction rpm depuis cette fermeture dans la plateforme et sa confrontation au verrou (M4c), la porte sur une construction rpm, le refus d'une archive altérée dans la plateforme.

**Additif du 18/11/2026, 18:05 UTC : M4c de la brique 05 mesuré** (brique 05, [résultats](../../poc/bricks/05-rpm-mock/resultats/m4c-predictions.md)).
- **Mesuré** : la construction rpm suit le schéma du deb de la 06. `preparer-rpm` reprend le pas `sources` et le début du pas `assemblage` de `preparer-deb` à l'identique (journal de `prealables`) ; `construire-rpm` tourne sous Kata ; `publier-image` est la même tâche signée (`d21931f3…`) dans les provenances deb (`s4d-deb-1`) et rpm. Les deux provenances ont la même forme : pipeline, trois tâches, images des pas, commit git et trois entrées en `inputs/result` (journal de `provenance`, banc de cette étape).
- **Conséquence pour la règle générique** : une construction rpm demandera, comme le deb en S4d2, ses entrées dans `_constructions`, `_attendues` et `_appariement` de `porte.rego` avant tout déclencheur.
- **Non mesuré** : la porte sur une construction rpm ; les tests négatifs de M5.

**Additif du 18/11/2026, 19:04 UTC : M5a de la brique 05 tenu** ([détail](../../poc/bricks/05-rpm-mock/resultats/m5-predictions.md)).
- **Mesuré** : la confrontation au verrou de `construire-rpm` refuse un rpm substitué, un fichier en trop, un rpm absent et un `manifest.json` altéré. Elle laisse passer un payload altéré à en-tête intact, car le `sigmd5` qu'elle lit est stocké dans l'en-tête et n'est pas recalculé (mesure hors ligne). Ce cas est refusé plus loin, par dnf dans mock (somme de contrôle contre `primary`). Un blob altéré de l'image de bootstrap est refusé à la copie de l'image (digest).
- **Différence avec le deb** : `construire-deb` revérifie chaque sha256 de la fermeture. La voie rpm s'appuie sur `sigmd5` et sur `repodata/`, que la confrontation ne contrôle pas.
- **Non mesuré** : un payload altéré accompagné d'un `repodata/` refait ; la porte sur une construction rpm.

**Additif du 18/11/2026, 19:46 UTC : reproductibilité d'une racine rpm, banc hors ligne de M1b** ([détail](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)).
- **Mesuré** : deux `dnf --installroot` hors ligne des mêmes 222 rpm (rpm 4.16.1.3, dnf 4.14.0), à 15 s d'écart, donnent les mêmes paquets mais pas le même arbre. Dix fichiers diffèrent par leur contenu : la base rpm, l'historique et les journaux de dnf, `aux-cache` de ldconfig et `cacerts` de Java. Les mtimes de 3332 entrées sont posées pendant la transaction.
- **Différence avec le deb** : l'image sbuild de la 06 est reproductible au bit près (`749d746c`, deux passages et S5b), parce que mmdebstrap prend `SOURCE_DATE_EPOCH` (lecture du manuel en S4a de la 06). Pour la voie rpm, aucun moyen équivalent n'est mesuré.
- **Conséquence pour cet ADR** : aucune décision ne change. Construire les images rpm par la plateforme (décision « C » du 18/11/2026) demande d'abord de neutraliser ces écarts. Sinon, chaque rejeu donnera une image nouvelle, donc de nouvelles signatures.
- **Portée** : 222 rpm du buildroot de vault 9.7, rpm et dnf de l'image d'essai, sur l'hôte, hors de Kata, archivés avec le tar de l'hôte. Ce n'est ni l'outillage de M1b ni dnf de l'amorce 9.8 (note de portée du 2026-11-18T19:49:19Z).

**Additif du 18/11/2026, 20:05 UTC : second banc de M1b et sources de l'outillage** ([détail](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)).
- **Mesuré** : sur les deux arbres du premier banc, une archive aux mtimes bornées au plus grand `BUILDTIME`, sans les quatre journaux de dnf, son historique et `aux-cache`, ne diffère plus que par deux fichiers. Le premier est `rpmdb.sqlite`, où seules les étiquettes `Installtime` et `Installtid` diffèrent, avec leur table d'index. Le second est `cacerts`, où seuls l'horodatage de génération et l'empreinte finale diffèrent. La borne change aussi la mtime de 985 fichiers de `usr/include` livrés par rpm.
- **Mesuré aussi** : les 199 rpm de l'outillage du 17/11 sont servis à deux adresses figées. Les 190 de Rocky sont dans vault 9.8, avec des repomd signés identiques à ceux du 17/11. Les 9 d'EPEL sont dans `pub/archive/epel/9.8`, sans métadonnées signées.
- **Conséquence pour cet ADR** : aucune décision ne change. Tous les écarts lus viennent de l'heure de l'installation, et aucun moyen de les neutraliser n'est mesuré.
- **Portée** : ce sont un traitement de l'archive sur l'hôte et un relevé public. Ils ne disent rien de mock sans les fichiers retirés, ni de la tâche Kata, ni de la durée de conservation des archives.

**Additif du 18/11/2026, 20:17 UTC : troisième banc de M1b** ([détail](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)).
- **Mesuré** : sur l'hôte, hors ligne, deux `dnf --installroot` des mêmes 222 rpm, avec `SOURCE_DATE_EPOCH=S`, donnent la même archive octet à octet. L'archive est bornée à S et ne contient ni les journaux de dnf, ni son historique, ni `aux-cache`. S est le plus grand des `BUILDTIME` et des `FILEMTIMES`. rpm 4.16.1.3 pose alors `INSTALLTID` à S et `INSTALLTIME` à S plus le rang du paquet. p11-kit horodate `cacerts` à S.
- **Conséquence pour cet ADR** : aucune décision ne change. Une racine rpm reproductible paraît possible sans outil ajouté, mais ce n'est pas établi.
- **Portée** : il reste à mesurer un autre jour, les paquets de l'outillage et du bootstrap, le rpm de l'amorce et un miroir partiel au lieu de fichiers locaux.

**Correction du 18/11/2026, 20:20 UTC, à l'additif du troisième banc de M1b** : « `INSTALLTIME` à S plus le rang du paquet » dépasse la mesure. Le banc montre 222 valeurs consécutives, de S à S + 221, et la même suite dans les deux installations. Il ne montre pas le lien avec l'ordre de la transaction.

**Note du 18/11/2026, 20:21 UTC** : le lien avec l'ordre de la transaction est mesuré sur l'installation i3. Trier les paquets par `INSTALLTIME` redonne l'ordre des lignes « Installing » du journal de dnf. S se calcule aussi avant l'installation, par `rpm -qp` sur les fichiers rpm.

**Note du 18/11/2026, écrite à 20:50 UTC** : les listes complètes de l'outillage et du bootstrap sont retirées des bases rpm des racines archivées ([résultat](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)). Deux formes restent à mesurer pour la reproductibilité : les gpg-pubkey importées par dnf, absentes du troisième banc, et le bootstrap, dont 143 entrées viennent de l'image de base. Aucune décision ne change.

**Note du 18/11/2026, écrite à 21:01 UTC, banc de l'outillage** ([résultat](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)) : sur un miroir partiel vérifié, deux installations de l'outillage sous SOURCE_DATE_EPOCH ne diffèrent que par `etc/machine-id`, aléatoire. Les gpg-pubkey sont fixées à S. La configuration des outils (langues installées, umask) change le contenu de la racine : les outils font partie de l'entrée de la construction. Aucune décision ne change.

**Correction du 18/11/2026, écrite à 21:03 UTC, à la note du banc de l'outillage** : « les outils font partie de l'entrée de la construction » est une hypothèse, pas une mesure. Le banc mesure des écarts de langues et de mode, mais ni l'amorce ni le umask n'ont été variés.

**Note du 18/11/2026, écrite à 21:09 UTC, outillage sans machine-id** ([résultat](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)) : `etc/machine-id` est écrit par le %post de systemd. Une fois ce membre exclu (machine-id exclu de l'archive), deux installations de l'outillage faites le même jour donnent la même archive. Le choix entre un fichier vide et un fichier absent n'est pas fait. Aucune décision ne change.

**Note du 18/11/2026, écrite à 21:13 UTC, lecture de l'amorce** ([lecture](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)) : l'amorce `ed654c69` est en local, contrairement à une note précédente. `%_install_langs` y vaut `en_US`, posé par `/etc/rpm/macros.image-language-conf`, contre `all` dans la racine d'outils de `99790c13`. L'hypothèse « configuration des outils » a donc une cause lisible, mais son lien avec les langues de S1 n'est pas encore mesuré. Aucune décision ne change.

**Note du 18/11/2026, écrite à 21:28 UTC, outils de l'amorce** ([résultat](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)) : avec les outils de l'amorce `ed654c69` sous `umask 022`, deux installations de l'outillage faites le même jour donnent la même archive (`06c289ad…`), avec les mêmes membres de langues que S1. Sur le banc, la macro `macros.image-language-conf` des outils décide des langues, et le umask décide du mode de `var/lib/dnf`. Les outils, leur umask et `SOURCE_DATE_EPOCH` font donc partie de l'entrée, sur le banc ; le pod Kata n'est pas mesuré. Aucune décision ne change.

**Note du 18/11/2026, écrite à 21:30 UTC, précision** ([résultat](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md)) : macro de langue masquée et umask mis à part, les outils de l'amorce et ceux de `99790c13` donnent le même contenu d'archive sur le banc. Les entrées mesurées sont donc la macro `%_install_langs` des outils, le umask et `SOURCE_DATE_EPOCH` ; les valeurs à retenir reviennent à la carte de M1b. Aucune décision ne change.

**Note du 18/11/2026, écrite à 21:44 UTC, bootstrap** ([résultat](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md), [`m1b-boot.sh`](../../poc/bricks/05-rpm-mock/resultats/m1b-boot.sh)) : sur le banc, la base `ee90dc0e` plus les dix lignes donne deux fois la même archive le même jour, avec `SOURCE_DATE_EPOCH`, la borne S et les exclusions du banc de l'outillage. Le mode de la racine de l'archive est une entrée de plus ; sa valeur revient à la carte de M1b. Aucune décision ne change.

**Note du 18/11/2026, écrite à 21:46 UTC, correction de la note sur le bootstrap** ([corrections](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md), [`m1b-boot-modes.log`](../../poc/bricks/05-rpm-mock/resultats/m1b-boot-modes.log)) : ces conditions suffisent sur le banc. Aucun témoin ne montre qu'elles sont nécessaires, sauf 8 exclusions (journaux de dnf, historique, `aux-cache`). Aucune décision ne change.

**Note du 19/11/2026, écrite à 00:07 UTC, autre jour** ([résultat](../../poc/bricks/05-rpm-mock/resultats/m1b-predictions.md), [`m1b-autre-jour.log`](../../poc/bricks/05-rpm-mock/resultats/m1b-autre-jour.log)) : relancés le 19/11 UTC, à 140 à 229 min des passages du 18/11, les quatre bancs redonnent les mêmes archives sur cet hôte. Ce n'est mesuré ni à 24 h, ni dans le pod Kata, ni sur un autre hôte. Aucune décision ne change.

**Note du 19/11/2026, écrite à 08:41 UTC, valeurs de la carte de M1b** ([carte](../../poc/bricks/05-rpm-mock/resultats/m1b-carte.md), [`m1b-boot-0555.log`](../../poc/bricks/05-rpm-mock/resultats/m1b-boot-0555.log)) : `etc/machine-id` est absent des images de M1b (décision du propriétaire, « Absent »). `en_US`, umask 022 et la racine en 0555 sont fixés dans la tâche. La référence du bootstrap, refaite avec la racine en 0555, est `f2652169…`. Ce n'est mesuré ni dans le pod Kata, ni sur un autre hôte. Aucune décision de l'ADR ne change.

**Note du 19/11/2026, écrite à 08:49 UTC, version de tar** ([`m1b-tar-amorce-ecart.log`](../../poc/bricks/05-rpm-mock/resultats/m1b-tar-amorce-ecart.log)) : sur un même arbre, GNU tar 1.34 et 1.35 écrivent des archives différentes. Le contenu est égal ; seuls `devmajor` et `devminor` changent dans chaque en-tête. Une couche reproductible suppose donc d'épingler aussi l'outil qui archive, et pas seulement les entrées. Aucune décision de l'ADR ne change.

**Note du 19/11/2026, écrite à 10:46 UTC, dnf dans Kata** ([carte de M1b](../../poc/bricks/05-rpm-mock/resultats/m1b-carte.md)) : dans un pod Kata, la limite de fichiers ouverts vaut 2³⁰. Faute de `/proc` dans la racine installée, rpm 4.16 boucle jusqu'à cette limite avant chaque scriptlet : `dnf --installroot` prend 5 811 s, contre 40 s sous une limite à 1 024. L'archive est la même dans les deux cas. Une tâche qui installe une racine avec rpm doit donc fixer cette limite elle-même. Aucune décision de l'ADR ne change.

**Note du 19/11/2026, écrite à 12:25 UTC, `/proc` dans la racine installée** ([carte de M1b](../../poc/bricks/05-rpm-mock/resultats/m1b-carte.md)) : monter `/proc` dans la racine avant dnf supprime aussi la boucle (40 s), mais change le contenu : 20 chemins déclarés dans `tmpfiles.d` apparaissent, absents des racines de S1. Le contenu d'une racine installée par rpm dépend donc de la présence de `/proc`, entrée implicite de la construction. Une tâche agnostique doit la fixer explicitement, comme la langue, le umask et la limite de fichiers ouverts. Aucune décision de l'ADR ne change.

**Note du 19/11/2026, écrite à 12:27 UTC** : décision du propriétaire « Limite seule ». La tâche d'installation d'une racine rpm fixe la limite de fichiers ouverts à 1 024 autour de dnf, et ne monte pas `/proc` dans la racine installée. Aucune décision de l'ADR ne change.
