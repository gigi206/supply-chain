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
