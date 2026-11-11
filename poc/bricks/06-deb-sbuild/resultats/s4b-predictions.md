# Brique 06, S4b : prédictions (écrites le 11/11/2026 entre 16:52 et 16:58 UTC, avant toute exécution)

Le script est [`s4b.sh`](../s4b.sh), avec les gabarits de [`fermetures/`](../fermetures/), tous écrits avec ces prédictions. **Rien n'a été lu ni écrit dans le cluster, Zot ou les VM pour S4b.** L'heure de l'en-tête sera relue dans le commit.

## Ce que produit S4b

Deux fermetures, publiées par `publier-fermeture` (brique 03, inchangée) sous `builds/fermetures/`, chacune par une pipeline signée :

| Pipeline | Tâches | Fermeture | Paramètres du créateur |
|---|---|---|---|
| `prefetch-deb-sample-app` (P1) | `prefetch-deb` (`4dac0609`, S4a) liée au sous-dossier `fermeture`, puis `publier-fermeture` (`7fa92ad3`) | `builds/fermetures/sample-app-deb` : `miroir/dists/…` et `miroir/pool/…` | aucun (workspace seul) |
| `prefetch-sources-sample-app` (P2) | `prefetch-gomod` **version 2** (gabarit neuf de la 06), puis `publier-fermeture` | `builds/fermetures/sample-app-sources` : `deps/gomod`, `deps/npm`, `.build-config.json` | commit et dépôt de Forgejo |

- **P1** : l'instantané, le sha256 de l'InRelease et la liste sont fixés dans la pipeline et couverts par sa signature. La liste reprend les colonnes 4 à 6 du verrou de l'artefact de packaging, tiré par digest (`c1719b13`). Décision A.
- **P2** : la demande Hermeto `[{"type": "gomod"}, {"type": "npm", "path": "web"}]` est fixée dans la pipeline. Le commit est `6391fd43`, celui de la voie image, dont l'arbre `30e808ff` est `poc/sample-app` actuel.
- **Version 2 de `prefetch-gomod`** : même nom et même sortie Cilium que la version 1. Elle reçoit le paramètre `paquets`, sans valeur par défaut, et contrôle le lockfile npm avant Hermeto. Écart de script avec la version 1 : 2 lignes changées et 62 ajoutées (relu à sec).
- **Rien d'autre ne change** : ni Cilium, ni la porte, ni la voie image (`prefetch-sample-app` reste en version 1, `5e7e5662`). La porte ne jugera pas ces fermetures avant S4d.

## Étapes et accords

| Étape | Touche | Accord |
|---|---|---|
| `prealables` | hôte seul, hors ligne | aucun, comme l'étape `verrou` de S4c, une fois ces prédictions commitées |
| `taches_deb` | Zot : bundle de P1 (`poc-ecriture`), lecture anonyme de l'artefact de packaging | nommé |
| `SIGNER=1 taches_sources` | Zot : bundle de la version 2 ; signature versionnée `fermetures/prefetch-gomod.signee.yaml` | nommé |
| revue de `taches.yml` | ajout du digest de la version 2 | nommé (relecture du propriétaire) |
| `taches_sources` | Zot : bundle de P2 | nommé |
| `deb`, `sources` | cluster (PipelineRuns) et Zot (fermetures, définitives) | nommé |
| `comparaison`, `provenance` | lecture dans Zot et le cluster | un accord pour les deux (levier b) |

## Prédictions

| N° | Étape | Prédiction | Confiance |
|---|---|---|---|
| B1 | prealables | L'artefact tiré du layout local de S4c par digest donne un verrou égal à celui du dépôt ; liste de 162 lignes, 193 978 008 octets | haute : S4c, C4 et C6 |
| B2 | prealables | Les trois gabarits se rendent sans variable restante, avec les bons noms. Le paramètre `paquets` n'a pas de valeur par défaut. Dans P1, la liste rendue est identique à la liste, et les sous-dossiers des workspaces sont `["fermeture",null]`. Dans P2, la demande rendue est égale à la demande | haute |
| B3 | prealables | Le script de la version 2 passe `sh -n`. Il change 2 lignes de la version 1 : la ligne des versions et l'appel d'Hermeto | haute : relu à sec |
| B4 | prealables | Le contrôle npm, tiré du gabarit rendu, admet l'arbre de `sample-app` (« 1 paquet(s) », lockfileVersion 3) et la demande gomod seule. Il refuse les 17 cas altérés : autre hôte, `registry.yarnpkg.com`, hôte préfixe, git, integrity absente, integrity sha1, resolved absent, link, lockfileVersion 1, `npm-shrinkwrap.json` lu d'abord, `../`, chemin absolu, `pip`, forme objet, clé en plus, doublon, demande vide | haute |
| B5 | prealables | La section `oras push --oci-layout` de `publier-fermeture` (oras 1.3.6, comme l'image d'outils), sur un faux miroir, donne 7 couches et 7 titres distincts. Deux paires de couches ont le même contenu sous deux titres (index et `by-hash`). Les noms avec `+` et `~` passent. Une seconde poussée, depuis une autre copie, donne le même digest | moyenne : deux couches de même digest n'ont jamais été poussées dans le PoC |
| B6 | taches_deb | L'artefact relu dans Zot, par lecture anonyme, donne la même liste (B1). P1 est signée et poussée en bundle | haute |
| B7 | taches_sources | La version 2 signée a un digest différent de `5e7e5662`. Avec `SIGNER=1`, elle est à ajouter à la liste revue, et P2 n'est pas signée tant que cette liste n'est pas acceptée | haute : modèle de S4a |
| B8 | deb | Deux PipelineRuns réussis. Les pods tournent en runc (`runtimeClassName` vide) sur `sc-build`, avec les labels `prefetch-deb` et `publier-fermeture`. Le journal de `prefetch-deb` affiche « miroir : 162 paquets, 193978008 octets » | haute pour le téléchargement : même tâche qu'en S4a |
| B9 | deb | `prefetch-deb`, en UID 65532, crée `miroir/` dans le sous-dossier `fermeture`, que le kubelet a créé. Le kubelet v1.35.0 lui donne le mode de la racine du volume. Si ce mode est 0777 (créé par local-path, non relevé dans ce cluster), l'écriture passe ; sinon, la tâche échoue avant toute écriture dans Zot | **moyenne** : le mode de la racine d'un PVC n'est relevé nulle part |
| B10 | deb | Les deux exécutions publient la même fermeture, et Chains signe les deux PipelineRuns | haute : contenu fixé par les hashes, publication déterministe (F2) |
| B11 | sources | Deux PipelineRuns réussis. Le journal de `prefetch-gomod` affiche la ligne du contrôle npm puis la demande. npm passe par la sortie `prefetch-sortie` (443 public) sans changement de Cilium. Même fermeture pour les deux exécutions | haute pour la réussite, **moyenne** pour le même digest : `.build-config.json` avec npm n'a jamais été produit deux fois |
| B12 | comparaison | Fermeture deb : 167 fichiers, dont 162 `.deb`. InRelease `0584fba3`. `Packages.xz` et `Translation-en.xz` conformes à l'InRelease, chacun avec sa copie `by-hash`. Pool égal à la liste (sha256, taille, chemin), 193 978 008 octets | haute, si B9 tient |
| B13 | comparaison | Fermeture applicative : 8 fichiers (6 gomod, 1 npm, `.build-config.json`). Les fichiers gomod sont égaux, par sha256, à ceux de F2 (même commit, même Hermeto). Le sha512 de `deps/npm/marked-16.4.1.tgz` est égal à l'integrity du lockfile | haute |
| B14 | comparaison | Le `.build-config.json` diffère de celui de F2 : Hermeto y ajoute une entrée `project_files` pour le lockfile npm. Relevé par diff, pas exigé | moyenne : lu dans le code, pas mesuré |
| B15 | provenance | P1 : provenance vérifiée par cosign. Sujet égal à la fermeture deb, buildType `slsa-tekton`, InRelease `0584fba3` dans `resolvedDependencies`, tâches `prefetch-deb` et `publier-fermeture`. Le paramètre `liste` du TaskRun `prefetch-deb`, lu dans le contenu de la provenance, est égal à la liste du verrou | haute pour le reste, **moyenne** pour la liste : un paramètre de 162 lignes n'a jamais été relu dans une provenance |
| B16 | provenance | P2 : source `sha1:6391fd43`, image d'outils `68e0ae70`, bundle de la version 2. Le paramètre `paquets` est lu dans le contenu du TaskRun. Une autre clé est refusée | haute : F2 |

## Limites connues

- **La plateforme ne lit pas l'artefact de packaging** en S4b (décision A). La liste est lue par l'hôte puis signée dans P1. La confrontation de la fermeture deb au verrou, au moment de la construction, est reportée à S4d.
- **Contrôle npm** : il impose le registre et l'integrity sha512. Il ne prouve pas qu'un hash `sha512` faux serait refusé par Hermeto dans la plateforme (refus d'une archive altérée mesuré sur l'hôte seulement, T3 du banc nix). Ce test négatif relève de S5.
- **Sortie de `prefetch-gomod`** : un pod compromis pourrait toujours envoyer le code cloné vers une adresse publique en 443. C'est la limite consignée en F2, et la version 2 ne la change pas.
- **Nom trompeur** : `prefetch-gomod` produit aussi npm (additif de 16:48 UTC, ADR 0007).
- **Deux digests de `prefetch-gomod` dans la liste revue** : la porte accepte les deux, sous la même règle `_prefetch`.

## Résultats de l'étape `prealables` (11/11/2026, 16:56:14 UTC, hôte seul, hors ligne)

Journal : [`s4b-prealables.log`](s4b-prealables.log), 37 lignes OK, aucune KO. Étape lancée sans accord, comme prévu ci-dessus.

**Heures** :
- les prédictions ont été commitées à 16:53:09 UTC (`614b41b`). L'en-tête, « entre 16:52 et 16:58 UTC », est donc trop large ;
- `s4b.sh` a été corrigé avant tout lancement (`96252d3`, 16:56:10 UTC) : les essais tirent les scripts des versions signées de la 08, car les gabarits non rendus ne sont pas lisibles par `yq`.

| N° | Résultat |
|---|---|
| B1 | **Tenue.** Verrou tiré du layout de S4c par digest, égal à celui du dépôt ; liste de 162 lignes, 193 978 008 octets |
| B2 | **Tenue.** Trois gabarits rendus et nommés ; `paquets` sans valeur par défaut ; liste rendue identique ; sous-dossiers `["fermeture",null]` ; demande rendue égale |
| B3 | **Tenue.** `sh -n` passe. 2 lignes de la version 1 signée (`5e7e5662`) sont changées : la ligne des versions et l'appel d'Hermeto |
| B4 | **Tenue.** Le contrôle tiré du gabarit rendu admet l'arbre de `sample-app` (« 1 paquet(s) », lockfileVersion 3) et la demande gomod seule. Il refuse les 17 cas altérés, dont `registry.yarnpkg.com`, l'hôte préfixe et `npm-shrinkwrap.json` lu d'abord. Défaut d'affichage seulement : la ligne « gomod . : admis », écrite avant le refus, est capturée après lui et laisse « admis) » sur la ligne suivante |
| B5 | **Tenue.** La section de `publier-fermeture` signée, avec oras 1.3.6, donne 7 couches et 7 titres distincts. Deux paires de couches ont le même contenu sous deux titres. Les noms avec `+` et `~` passent. Une seconde poussée, depuis une autre copie, donne le même digest (`81291ea4`) |

Restent B6 à B16, qui attendent des accords nommés.

## Note datée du 11/11/2026, 17:05 UTC : B9 étayée hors ligne (confiance de la prédiction inchangée)

Question du propriétaire : « Comment fermer ce risque ? ». Chaîne relue dans le dépôt et le cache, sans cluster :
- **Manifeste de local-path** v0.0.37, tel que téléchargé et épinglé par la 08b : `~/.cache/supply-chain-poc/08b/telechargements/local-path-storage.yaml`, sha256 `9781b39c`, égal à `LP_MANIFESTE_SHA` de `rke2.sh`. Son script `setup` crée chaque volume par `mkdir -m 0777 -p "$VOL_DIR"`. Le mode s'applique au dernier composant, le dossier du volume, sans dépendre de l'umask.
- **`rendre_local_path`** de `rke2.sh` ne change que le chemin des volumes et les deux images. Le script `setup` est appliqué tel quel.
- **Kubelet v1.35.0** : le dossier du `subPath` reçoit le mode de la racine du volume (`GetMode`), créé par `Mkdirat` puis `Fchmod`, donc lui aussi sans umask (additif de 16:48 UTC). Il appartient à root, en 0777 : l'UID 65532 peut y créer `miroir/`.
- **Ce qui reste supposé** : que la ConfigMap `local-path-config` en service soit celle du manifeste rendu, sans dérive depuis son application. Ce n'est pas relu dans le cluster. Une lecture de cette ConfigMap fermerait ce dernier point, sans aucune écriture.

La prédiction B9 n'est pas réécrite. Cette note ne la remplace pas : seule l'exécution de `deb` la tranchera.

**Correction d'heure** : la note titrée « 17:05 UTC » a été écrite à 17:21 UTC et commitée à 17:21:43 UTC (`7a163f2`).

## Note datée du 11/11/2026, 17:24 UTC : B9, preuve tirée de S4a (avis du conseiller demandé par le propriétaire)

- **Le pod auxiliaire de local-path tourne en root** : la section `helperPod.yaml` du manifeste en cache (`9781b39c`) n'a ni `securityContext` ni `runAsUser`. Le manifeste entier n'en contient aucun (relevé par `grep`), et l'image est `busybox`. La racine de chaque volume appartient donc à root.
- **S4a a déjà écrit en UID 65532 à la racine d'un tel volume** : `prefetch-deb` tournait en UID 65532 (`stepTemplate`), sans `fsGroup` dans le `podTemplate` de `s4a.sh`, avec un workspace sans `subPath` dans `builder-sbuild`. Elle a écrit `miroir/` : « miroir : 199 paquets » dans [`s4a-pipeline.log`](s4a-pipeline.log), lignes 28 et 66.
- Puisque la racine appartient à root, cette écriture prouve que son mode donne l'écriture aux autres. Elle le prouve dans ce cluster, sous la ConfigMap en service le 10/11 vers 23:37 UTC, et pas seulement d'après le manifeste. Le kubelet recopie ce mode sur le `subPath` (additif de 16:48 UTC).
- **Seule hypothèse ouverte** : une dérive de la ConfigMap depuis S4a. La relire n'apporterait pas plus que cette preuve, car elle ne montre que le script, pas le mode réel. Avis du conseiller : lancer sans cette lecture.

B9 n'est pas réécrite. Seule l'exécution de `deb` la tranchera.

## Résultats des étapes `taches_deb` et `deb` (11/11/2026, de 17:28:42 à 17:31:06 UTC, accord « Oui, lance taches_deb et deb »)

Journaux : [`s4b-taches_deb.log`](s4b-taches_deb.log) et [`s4b-deb.log`](s4b-deb.log). Écritures définitives dans Zot : le bundle de P1 et la fermeture deb.

| N° | Résultat |
|---|---|
| B6 | **Tenue.** L'artefact de packaging relu dans Zot, en lecture anonyme, donne un verrou égal à celui du dépôt et la même liste (162 lignes, 193 978 008 octets). P1 est signée et poussée : `tekton/pipelines/prefetch-deb-sample-app@sha256:86e70b7fd45a2f471ed7264b48e73394b756ed358693747a70c5a3c04205cba8` |
| B8 | **Tenue.** Deux PipelineRuns réussis (`s4b-deb-1` et `s4b-deb-2`). Les pods tournent en runc (`runtimeClassName` vide) sur `sc-build`, avec les labels `prefetch-deb` et `publier-fermeture`. `prefetch-deb` affiche « miroir : 162 paquets, 193978008 octets », en 20 s puis 12 s. Les index sont conformes à l'InRelease : `Packages.xz` `7778d3e3`, `Translation-en.xz` `800dd225` |
| B9 | **Tenue.** `prefetch-deb`, en UID 65532, a écrit `miroir/` dans le sous-dossier `fermeture` créé par le kubelet (notes de 17:05, en fait 17:21, et de 17:24 UTC) |
| B10 | **Tenue.** Même fermeture pour les deux exécutions : `builds/fermetures/sample-app-deb@sha256:bb7599a2e1cde30770fdb4405a5f9cce94de5ea5b12c358e512dfbe7d5b9f290`, 167 couches, relue en lecture anonyme. Chains a signé les deux PipelineRuns |

**Constat, non prévu** : `publier-fermeture` affiche « can't open bom.json: no such file », puis « SBOM de Hermeto non publié : » sans empreinte.
- Cause : la tâche calcule l'empreinte du `bom.json` d'Hermeto pour la journaliser. Une fermeture deb n'en a pas.
- L'erreur vient d'une substitution de commande dans un `echo`, ce qui ne fait pas échouer `set -eu`. La publication et les résultats ne sont pas touchés.
- La tâche n'est pas modifiée (décision A). Le message est trompeur pour une fermeture sans Hermeto : à reprendre avec la règle de porte générique (S4d).

Restent B7, B11 à B16 : `SIGNER=1 taches_sources`, revue de la liste, `taches_sources`, `sources`, puis `comparaison` et `provenance`.
