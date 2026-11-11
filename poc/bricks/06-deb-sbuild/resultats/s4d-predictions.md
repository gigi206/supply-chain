# Brique 06, S4d1 : prédictions (écrites le 11/11/2026 à partir de 18:04 UTC, avant toute étape qui touche le cluster ou Zot)

Le script est [`s4d.sh`](../s4d.sh), avec les gabarits de [`deb/`](../deb/). **Rien n'a été lu ni écrit dans le cluster, Zot ou les VM pour S4d1.** L'heure de l'en-tête sera relue dans le commit.

Décisions du propriétaire (11/11/2026, 17:54:35 UTC, « Oui, retiens-les ») : S4d en trois sous-jalons, la porte (S4d2) avant le trigger (S4d3) ; le deb seul dans l'artefact signé ; le `.dsc` assemblé dans le pod de construction.

## Ce que produit S4d1

La pipeline `sample-app-deb`, signée, lancée depuis l'hôte par `s4d.sh` (ni webhook ni rattrapage). Ses entrées hors du commit sont fixées par digest dans la pipeline : fermeture deb `bb7599a2`, fermeture applicative `50dc73f7` (S4b), artefact de packaging `c1719b13` (S4c).

| Tâche | Pod | Ce qu'elle fait |
|---|---|---|
| `preparer-deb` (neuve) | runc restreint, UID 65532, sans secret | clone le commit `6391fd43` de Forgejo ; tire les trois artefacts par digest ; confronte la fermeture deb au verrou ; reconstitue `vendor/` (Go 1.26.10 de `outils-prefetch`, `GOPROXY=off`) et `web/node_modules/marked` ; copie `debian/` (avec `rules` en 0755) et le verrou dans `entrees/` |
| `construire-deb` (neuve) | Kata privilégié, image de build `749d746c` de S4a, UID 1000 | entrées en lecture seule ; fermeture revérifiée ; archive amont et `.dsc` ; sbuild `--chroot-mode=unshare` avec `--extra-package`, `sources.list` vidé ; artefact en manifeste d'image OCI (une couche : le deb seul) ; NetworkPolicy `construction-deb-sans-sortie` |
| `publier-image` (`d21931f3`, inchangée) | runc restreint | pousse l'artefact vers `builds/sample-app-deb` par digest |

**Hors de S4d1** : la porte ne juge pas encore cet artefact (S4d2), et aucun trigger n'est branché (S4d3).

## Étapes et accords

| Étape | Touche | Accord |
|---|---|---|
| `prealables` | hôte seul, hors ligne | aucun ; **déjà jouée** (voir plus bas) |
| `reseau` | cluster : NetworkPolicy `construction-deb-sans-sortie` | nommé |
| `essai` | cluster : un pod Kata privilégié, supprimé à la fin (levier e) | nommé |
| `SIGNER=1 taches` | Zot : bundles des deux tâches neuves ; signatures versionnées dans `deb/` | nommé |
| revue de `taches.yml` | ajout des deux digests | nommé (relecture du propriétaire) |
| `taches` | Zot : bundle de la pipeline | nommé |
| `pipeline` | cluster (deux PipelineRuns) et Zot (artefact, définitif) | nommé |
| `comparaison`, `provenance` | lecture dans Zot et le cluster | un accord pour les deux (levier b) |

`reseau` doit précéder `essai` : le pod d'essai porte le label `tekton.dev/task: construire-deb`, et ses témoins réseau n'ont de sens que sous la NetworkPolicy.

## Déjà observé : étape `prealables`, avant l'écriture de ces prédictions

Cinq passages de 18:03:01 à 18:04:02 UTC (`chrono.tsv`) ; le dernier en code 0 ([journal](s4d-prealables.log)). Les quatre premiers se sont arrêtés sur des défauts du script, corrigés avant ces prédictions :
1. ordre de tri de la chaîne attendue des modes de `debian/` ;
2. `.dsc` différent de celui de `sources.sh` : constat ci-dessous ;
3. motif `sed` de la comparaison des modes ;
4. chemin de l'hôte remplacé deux fois dans la section du layout.

Ce qui est observé :
- **Gabarits** : rendus sans variable restante ; scripts sans erreur de syntaxe (`sh -n`, `bash -n`, `ast` pour Python).
- **Confrontation au verrou** (section de l'étape `entrees`, jouée telle quelle) : 162 paquets identiques. **Sept cas altérés refusés** : paquet altéré d'un octet, paquet retiré, paquet en plus, paquet remplacé par un lien, chemin avec `..`, chemin hors de `pool/`, verrou vide.
- **Assemblage** (étape jouée sous `unshare -rn`) : `go mod verify` passe ; `entrees/src` est égal, en contenu, à l'arbre de l'archive de `sources.sh` (`07521c1e`) ; `debian/` est égal à `poc/packaging/debian`, avec `rules` en 755 et le reste en 644.
- **Paquet source** (section de `construire-deb`, outils de l'hôte) : l'archive amont est **identique** à celle de `sources.sh` (`07521c1e`).
- **Constat** : le `.debian.tar.xz` diffère de celui de `sources.sh`, et donc le `.dsc` aussi. Seuls les modes changent : `sources.sh` copie `debian/` depuis l'arbre de travail, avec le umask 002 de l'hôte (664 et 775) ; la plateforme a les modes de git (644 et 755). Sur l'hôte : `.debian.tar.xz` `f0e5cfc8…`, `.dsc` `7f9cf5d3…` (S1 : `863cf4da…`, `9050679e…`). Le deb n'en dépend pas (`dh_fixperms` fixe les modes installés) : c'est D8 qui le dira.
- **Layout** (section de `construire-deb`, avec le deb de S3 `0b489d43`) : lu comme le lit `publier-image`, une couche (le deb seul, 0644, propriétaire 0), `diff_ids` conformes. **Digest attendu de l'artefact : `sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e`.**
- **Entrées du pod d'essai** : `entrees.tar`, 227 266 560 octets.

## Prédictions

| N° | Étape | Prédiction | Confiance |
|---|---|---|---|
| D1 | reseau | La NetworkPolicy est posée. Une seule politique sélectionne `construire-deb`, en entrée et en sortie. Aucune NetworkPolicy de `builds` n'autorise de trafic, et aucune CiliumNetworkPolicy n'en autorise à `construire-deb` | haute : forme de S4a |
| D2 | essai | Le pod est admis (Kyverno, Pod Security) et démarre sous Kata sur sc-build. L'image de build de S4a est tirée de Zot par digest : c'est son **premier lancement comme image de pod** | moyenne : configuration vérifiée en S4a, jamais exécutée |
| D3 | essai | `entrees.tar` arrive en 4 morceaux de 64 Mio, sha256 conforme | haute : S3 |
| D4 | essai | Les quatre témoins réseau échouent (DNS, Zot 5000, Forgejo 3000, adresse publique en 80) | haute : S4a, même forme |
| D5 | essai | La fermeture est revérifiée : 162 paquets copiés dans `/w/fermeture` | haute |
| D6 | essai | L'archive amont est `07521c1e`, comme sur l'hôte (tar 1.35 dans les deux cas ; gzip 1.13 dans l'image, 1.14 sur l'hôte). Le `.debian.tar.xz` et le `.dsc` sont ceux de l'hôte (`f0e5cfc8`, `7f9cf5d3`) | moyenne pour l'archive amont ; faible pour les deux autres (dpkg-dev 1.22.22 et xz 5.8.1 dans l'image, 1.23.7 et 5.8.3 sur l'hôte) |
| D7 | essai | sbuild réussit en UID 1000, `--chroot-mode=unshare`, avec le chroot de l'image (`/opt/sbuild/trixie-amd64.tar`). Aucune ligne apt `Get`, `Hit`, `Ign` ou `Err` en http(s) | moyenne : comme S3, mais avec un autre chroot (S4a) et la seule neutralisation de `sources.list` |
| D8 | essai | **Le deb est `0b489d43…`**, celui d'OBS, de S1 et de S3 | moyenne : mêmes entrées vérifiées sur l'hôte ; seuls le chroot, les modes de `debian/` et la tâche changent |
| D9 | essai | L'artefact a le digest attendu `039949f9…` | moyenne : suppose D8 et la même couche tar dans l'image |
| D10 | SIGNER=1 taches | `preparer-deb` et `construire-deb` sont signées, versionnées dans `deb/`, poussées en bundles, et signalées absentes de la liste revue | haute : forme de S4a et S4b |
| D11 | taches | Après la revue, les deux tâches sont dans la liste ; la pipeline est signée et poussée en bundle | haute |
| D12 | pipeline | Les deux PipelineRuns réussissent. `preparer` et `publier` tournent en runc, `construire` sous Kata, tous sur sc-build. Dans `construire`, l'écriture dans les entrées est refusée | moyenne : deux tâches neuves ; `construire-deb` est la première étape Tekton en UID 1000 |
| D13 | pipeline | Les deux exécutions publient `builds/sample-app-deb@sha256:039949f9…`, et Chains signe chaque PipelineRun | moyenne : suppose D8 et D9 |
| D14 | comparaison | Les deux artefacts tirés par digest ont une couche, qui contient le deb seul, égal à `0b489d43`. Les `Installed-Build-Depends` des deux `.buildinfo` (journal de `construire`) sont égaux au verrou (162 paquets, nom et version) | haute si D13 |
| D15 | provenance | La provenance se vérifie avec la clé de Chains, et pas avec une autre. Elle porte : sujet `builds/sample-app-deb@<digest>`, `buildType` `slsa-tekton`, source `git+…/sample-app.git` au commit `6391fd43` ; les deux fermetures et l'artefact de packaging à leurs digests ; l'image de build `749d746c` comme image d'étape ; les tâches `construire-deb`, `preparer-deb` et `publier-image` ; `runtimeClassName: kata` dans la spec du TaskRun de `construire-deb` | moyenne : comme B15 ; trois `*_ARTIFACT_INPUTS` dans une tâche, jamais mesuré |

## Risques nommés

- **D2, D7, D12** : la tâche `construire-deb` est la première en UID 1000 sous Tekton (les répertoires de Tekton et le workspace sortie doivent être inscriptibles), et la première à lancer l'image de S4a.
- **D8** : si le deb diffère, le `.buildinfo` (dans le journal) et une comparaison de contenu (sans diffoscope, absent de l'hôte) diront où.
- **Effort** : S4d1 est le plus gros des trois sous-jalons. L'estimation de la carte (1 à 2 jours) sera relevée à la fin.

## Note datée du 11/11/2026, 18:11 UTC : relecture du conseiller, corrections avant tout lancement

Relecture du conseiller après le commit des prédictions (`7f2a3c2`). Rien n'a été lancé dans le cluster ni dans Zot.

- **D15, motif de la confiance faux** : trois `*_ARTIFACT_INPUTS` dans une tâche ont déjà été mesurés. `preparer-entrees` en émet trois (fermeture, `web/dist`, image de build), et les rejeux de la 08 les montrent dans `resolvedDependencies` (par exemple `08-trust-plane/resultats/rejeu-complet-partie-4.log`, lignes 225 à 228). La confiance reste moyenne, pour une autre raison : ce sont trois noms neufs, et l'image de build n'est plus une entrée déclarée mais l'image d'une étape (forme mesurée en S4b pour l'image de prefetch, B15).
- **`s4d.sh`, étape `essai`, corrigée** :
  - le script passe dans le pod comme fichier (`/w/construire.sh`), lancé sans entrée standard, comme sous Tekton. Par `bash -s`, un processus fils qui lit l'entrée standard aurait avalé la suite du script, et l'essai aurait paru réussi ;
  - un témoin exige la dernière ligne du script (`image.tar : … octets`) ;
  - un piège supprime le pod d'essai à toute sortie de l'étape ;
  - les étapes `essai`, `pipeline` et `comparaison` rendent le code 1 s'il y a un écart.
- **`prealables` étendue, rejouée** (deux passages, de 18:10:57 à 18:11:19 UTC, code 0 au second ; le premier s'est arrêté sur la recherche de la couche de busybox, corrigée) : les sections de `preparer-deb` sont rejouées sous le busybox de l'image de prefetch (`49227c02`, BusyBox v1.36.1, tiré du layout local `68e0ae70`), avec ses seuls applets plus `go` et `python3`. La confrontation passe, et l'assemblage donne des entrées égales en contenu, en modes et en types à celles des outils de l'hôte.
- **Étape ajoutée, `busybox_outils`** (lecture dans Zot) : l'image d'outils (`c7bebae2`), qui fait tourner l'étape `entrees`, n'a pas de copie locale. L'étape la tire par digest, en extrait le busybox, et y rejoue la confrontation avec deux cas altérés. Elle n'est pas lancée.
- **Accords** : `busybox_outils` (lecture), `reseau` et `essai` (réversibles) peuvent être groupés sous un seul accord nommé (leviers b et e).

Prédictions ajoutées pour `busybox_outils` :

| N° | Étape | Prédiction | Confiance |
|---|---|---|---|
| D16 | busybox_outils | L'image d'outils est tirée au digest `c7bebae2` et contient un busybox. Sous ses seuls applets, la confrontation admet la fermeture (162 paquets) et refuse un paquet en plus et un paquet altéré | haute : mêmes applets que ceux de `preparer-entrees` et `vsa.sh`, qui tournent dans cette image |

## Résultats du 11/11/2026, 18:32 UTC : busybox_outils, reseau et essai

**Accord du propriétaire** (18:25:34 UTC) : « Ok », donné à la question « Je lance busybox_outils, reseau et essai ? ». Trois étapes, toutes en code 0 ([busybox_outils](s4d-busybox_outils.log), [reseau](s4d-reseau.log), [essai](s4d-essai.log), [journal du script dans le pod](s4d-essai-construire.log)).

- **D16 : tenue** (18:25:41 UTC). L'image d'outils est tirée au digest `c7bebae2`. Son busybox est `/busybox/busybox`, BusyBox v1.37.0 (sha256 `62035898…`), avec 399 applets. Sous ses seuls applets, la confrontation admet les 162 paquets, et refuse un paquet en plus et un paquet altéré.
- **D1 : tenue** (18:25:50 UTC). `construction-deb-sans-sortie` est posée et elle seule sélectionne `construire-deb`, en entrée et en sortie. Aucune NetworkPolicy de `builds` n'autorise de trafic, et aucune CiliumNetworkPolicy n'en autorise à `construire-deb`.
- **Essai**, de 18:25:55 à 18:32:04 UTC :
  - **D2 : tenue.** Le pod est admis et prêt sur sc-build, sous Kata (invité 6.18.56, 3 vCPU), avec l'image de build de S4a tirée par digest : premier lancement de cette image comme image de pod, sans incident.
  - **D3 : tenue.** `entrees.tar` arrive en 4 morceaux, sha256 conforme.
  - **D4 : tenue.** Les quatre témoins réseau échouent, tous par délai (code 124).
  - **D5 : tenue.** 162 paquets revérifiés et copiés.
  - **D6 : tenue, y compris pour les parties à confiance faible.** L'archive amont est `07521c1e`, le `.dsc` `7f9cf5d3` et le `.debian.tar.xz` `f0e5cfc8`, les mêmes que sur l'hôte, malgré des versions de gzip, dpkg-dev et xz différentes.
  - **D7 : tenue.** sbuild réussit en UID 1000 en 276 s, sans aucune ligne apt en http(s).
  - **D8 : tenue.** **Le deb est `0b489d438370ddb6…`**, celui d'OBS, de S1 et de S3. Le changement des modes de `debian/` n'a donc pas d'effet sur le deb.
  - **D9 : tenue.** L'artefact a le digest attendu, `039949f9…` ; `image.tar` est lu comme le lit `publier-image`.
  - **En plus** : les `Installed-Build-Depends` du `.buildinfo` de l'essai sont égaux au verrou (162 paquets, nom et version, aucun écart). `Build-Path` vaut `/build/reproducible-path/sample-app-1.0.0`.
- **Défaut de formulation du journal de l'essai** : la ligne « invité » affiche « écriture refusée » après le type de montage des entrées. C'est un texte fixe du script, et non une mesure : dans l'essai, le contrôle de lecture seule est remplacé (première ligne du journal), et `/e` est monté `rw`. La lecture seule ne sera mesurée que dans la pipeline (D12).

## Résultat du 11/11/2026, 19:25 UTC : SIGNER=1 taches

**Accord du propriétaire** (19:25:26 UTC) : « Oui, lance-la ». Étape en code 0 à 19:25:33 UTC ([journal](s4d-taches-signer.log) ; `chrono.tsv` la note « taches »).

- **D10 : tenue.** `preparer-deb` et `construire-deb` sont signées par tkn, versionnées dans [`deb/`](../deb/), et leurs bundles sont poussés dans Zot :
  - `tekton/tasks/preparer-deb@sha256:b310c262a6a730824d7df6314a52a74fbd600d468709ea7bd1f7a3a50ab6540d` ;
  - `tekton/tasks/construire-deb@sha256:3726ff0b116cb6f4e13a44de69ca7a9be84061f4f70585783932f2685c79d10a`.
  Toutes deux sont signalées absentes de la liste revue ; la pipeline n'est pas signée.
- L'ajout des deux digests à `politique/porte/taches.yml` (08) est préparé, non commité, en attente de relecture.

## Résultats du 11/11/2026, 19:29 UTC : taches, puis pipeline en échec au premier PipelineRun

**Accord du propriétaire** (19:27:55 UTC) : « Oui, lance-les », donné à la question « Je lance taches, puis pipeline ? ». Avant, à 19:27:06 UTC, « Oui, commite-le » pour l'ajout relu à la liste revue (`3836bde`).

- **D11 : tenue** (`taches`, 19:28:01 UTC, code 0, [journal](s4d-taches.log)). Les deux tâches sont dans la liste revue. La pipeline est signée et son bundle poussé : `tekton/pipelines/sample-app-deb@sha256:83455f46d1ccc16db8708d402226a192ae52975983afa7c114f28f6fe5c4376e`.
- **D12 : réfutée au premier passage** (`pipeline`, 19:28:08 UTC, code 1, [journal](s4d-pipeline.log)). Le TaskRun `s4d-deb-1-preparer` échoue dès l'étape `sources` : `fatal: could not create work tree dir '/tmp/depot': Permission denied`. `construire` et `publier` n'ont pas tourné, `s4d-deb-2` n'a pas été créé, et rien n'a été publié sous `builds/sample-app-deb`.
- **Cause, lue dans les couches des images** : `/tmp` de l'image de prefetch (`68e0ae70`) appartient à root, en 0755 ; celui de l'image d'outils est en 1777. `prefetch-gomod` monte un emptyDir sur `/tmp`, et je ne l'avais pas repris dans `preparer-deb`. Les contrôles sur l'hôte ne l'ont pas vu : ils jouent les scripts avec un `/tmp` de l'hôte, et le pod d'essai ne visait que `construire-deb`, la tâche privilégiée.
- **Correction, à sec** : un emptyDir est monté sur `/tmp` pour toutes les étapes de `preparer-deb`, et `prealables` exige ce montage (rejouée à 19:29:07 UTC, code 0). La tâche corrigée a un autre digest : il faut la re-signer (`SIGNER=1 taches`), puis remplacer `b310c262` par le nouveau digest dans la liste revue.
- **Coût** : le bundle `tekton/tasks/preparer-deb@sha256:b310c262…` reste dans Zot, inutilisable, faute de droit de suppression. Il sera retiré de la liste revue.

## Résultat du 11/11/2026, 19:30 UTC : re-signature de preparer-deb

**Accord du propriétaire** (19:30:00 UTC) : « Oui, re-signe ». `SIGNER=1 taches` à 19:30:07 UTC, code 0 ([journal](s4d-taches-signer-2.log)).
- `preparer-deb` corrigée est signée, versionnée et poussée : `tekton/tasks/preparer-deb@sha256:5f0ca26bd273e005753fce846672436873d481bc460a237a15f26a2dc4576cd6`.
- `construire-deb` est inchangée : sa signature versionnée est conforme et son bundle reste `3726ff0b`, déjà dans la liste revue.
- Le remplacement de `b310c262` par `5f0ca26b` dans `politique/porte/taches.yml` (08) est préparé, non commité, en attente de relecture.

## Résultats du 11/11/2026, 19:33 UTC : second passage de taches et pipeline, nouvel échec dans preparer-deb

**Accords du propriétaire** : « Oui, commite-le » (remplacement relu dans la liste revue, `cc4b8dd`), puis « Oui, lance-les » (19:32:33 UTC). Journaux du second passage : [taches](s4d-taches-2.log), [pipeline](s4d-pipeline-2.log). Ceux du premier passage gardent leur nom.

- **`taches`** (19:32:39 UTC, code 0) : la pipeline est re-signée avec `preparer-deb@5f0ca26b`, bundle `tekton/pipelines/sample-app-deb@sha256:c43988a8abf0a3a7377229e7b6e3b38b8182d4fa772002d452550334424e877a`.
- **D12 : réfutée au second passage** (`pipeline`, 19:32:51 UTC, code 1). Dans `s4d-deb-1-preparer`, l'étape `sources` passe (git 2.51.2, commit `6391fd43`, arbre `30e808ff`). L'étape `entrees` passe aussi : trois artefacts tirés (167, 8 et 6 fichiers), confrontation au verrou réussie (162 paquets). L'étape `assemblage` échoue : `cp: can't stat '/workspace/sortie/entrees/deps/gomod/pkg/mod'`. Rien n'est publié, et `s4d-deb-2` n'est pas créé.
- **Cause** : la fermeture applicative porte déjà un dossier `deps/` à sa racine (`deps/gomod`, `deps/npm`, `.build-config.json`). Tirée par `oras pull -o "$e/deps"`, elle donne `entrees/deps/deps/gomod`. La simulation de `prealables` copiait `comparaison/sources/deps` (un sous-dossier) au lieu de la racine de l'artefact, et masquait donc l'erreur.
- **Leçon, avec le premier échec** : les deux défauts viennent du même écart. `prealables` imite l'environnement de la tâche (`/tmp` de l'hôte, copies `cp`) au lieu de l'exécuter, et le pod d'essai ne visait que `construire-deb`.
- **Bundles désormais inutilisables dans Zot**, sans droit de suppression : `tekton/tasks/preparer-deb@5f0ca26b`, `tekton/pipelines/sample-app-deb@83455f46` et `@c43988a8`. Avec `b310c262`, cela fait quatre.

## Note datée du 11/11/2026, 19:45 UTC : correction de preparer-deb et pod d'essai de la préparation, à sec

Avis du conseiller après le second échec : une troisième simulation sur l'hôte ne refermerait pas l'écart, le pod d'essai (levier e) doit couvrir aussi `preparer-deb` avant la troisième signature. Rien n'a été lancé depuis le second échec.

- **Correction de `preparer-deb`** : la fermeture applicative est tirée sous `entrees/sources` (racine de l'artefact) et lue sous `sources/deps/`. Dans `prealables`, chaque copie de l'hôte est désormais la racine d'un `oras pull`. `prealables` est rejouée à 19:44 UTC environ (code 0) ; les entrées obtenues sont inchangées en contenu. Le sha256 d'`entrees.tar` change (`c2dcc982…`), car l'archive porte les dates des fichiers recréés.
- **Écriture en UID 1000 sous Tekton**, lue sans exécution dans la spec du pod `s4d-deb-1-preparer-pod` et dans le source de Tekton v1.15.5 :
  - tous les volumes `tekton-internal-*` sont des emptyDir (`/tekton/run/<i>`, `/tekton/results`, `/tekton/home`), sauf `downward` ;
  - les scripts sont créés par `touch` puis `chmod +x` ;
  - `entrypoint` est copié en mode `0311` (`cmd/entrypoint/subcommands/cp.go`) : exécutable par tout UID, sans droit de lecture, ce qui suffit pour un binaire Go statique.
  `construire-deb` n'a donc pas à changer. C'est une déduction ; D12 la mesurera.
- **Étape ajoutée, `essai_preparer`** : un pod runc restreint, avec le label `tekton.dev/task: preparer-deb`. Les trois étapes y sont des initContainers, avec leurs images, leurs scripts rendus et les montages de la tâche (`ca-poc`, emptyDir sur `/tmp`). Le pod fait un vrai clone de Forgejo et de vrais pulls dans Zot, aux digests de la pipeline. Rien n'est écrit dans Zot.

| N° | Étape | Prédiction | Confiance |
|---|---|---|---|
| D17 | essai_preparer | Le pod est admis et ses trois étapes finissent en code 0. Les résultats sont `CHAINS-GIT_URL` et `CHAINS-GIT_COMMIT` du dépôt et du commit, et les trois `*_ARTIFACT_INPUTS` aux digests fixés. L'arbre `entrees/` est égal, en contenu, modes et types, à celui de `prealables`. L'essai de `construire-deb` (deb `0b489d43`) vaut donc pour la préparation réelle | moyenne : premier pod nu à initContainers et ConfigMap dans `builds` ; `/tmp` et `sources/` corrigés |

**Suite, si D17 est tenue** : `SIGNER=1 taches` (troisième version de `preparer-deb`), revue de `taches.yml`, puis `taches` et `pipeline`.

**Correction datée du 11/11/2026, 19:38 UTC** : la note précédente, commitée à 19:38:31 UTC (`d80e9d8`), porte deux heures fausses, écrites sans les relire. Son titre aurait dû dire 19:38 UTC, et non 19:45 UTC. `prealables` a tourné de 19:38:01 à 19:38:10 UTC (`chrono.tsv`), et non vers 19:44 UTC.

## Résultat du 11/11/2026, 19:39 UTC : essai_preparer

**Accord du propriétaire** (19:39:12 UTC) : « Oui, lance-le ». Étape de 19:39:18 à 19:39:31 UTC environ, code 0 ([journal](s4d-essai_preparer.log), [journaux du pod](s4d-essai-preparer-pod.log)).

- **D17 : tenue.** Le pod est admis, en runc sur sc-build. Ses trois étapes finissent en code 0 : clone du commit `6391fd43` (arbre `30e808ff`), trois artefacts tirés (167, 8 et 6 fichiers), confrontation au verrou (162 paquets), `vendor/` (17 fichiers, `go mod verify`) et `marked` (integrity conforme).
- **Résultats** : `CHAINS-GIT_URL`, `CHAINS-GIT_COMMIT` et les trois `*_ARTIFACT_INPUTS` sont exactement ceux attendus.
- **L'arbre `entrees/` du pod est égal à celui de `prealables`** : 214 fichiers, même contenu, mêmes modes et mêmes types. L'essai de `construire-deb` (deb `0b489d43`, artefact `039949f9`), fait sur l'arbre de `prealables`, vaut donc pour ce que produit la préparation réelle.

## Résultat du 11/11/2026, 19:40 UTC : troisième signature de preparer-deb

**Accord du propriétaire** (19:40:05 UTC) : « Oui, re-signe ». `SIGNER=1 taches` à 19:40:13 UTC, code 0 ([journal](s4d-taches-signer-3.log)).
- `preparer-deb` est signée, versionnée et poussée : `tekton/tasks/preparer-deb@sha256:588617b8382513c3aa5b2d79de8f45324ab6cfdc2b6009664ab0a50e1123c492`. C'est la version jouée dans le pod d'essai (D17).
- `construire-deb` est inchangée (`3726ff0b`).
- Le remplacement de `5f0ca26b` par `588617b8` dans `politique/porte/taches.yml` (08) est préparé, non commité, en attente de relecture.

## Résultats du 11/11/2026, 19:56 UTC : troisième passage de taches et pipeline, tenus

**Accords du propriétaire** : « Oui, commite-le » (liste revue avec `preparer-deb@588617b8`, `c5da4c4`), puis « Oui, lance-les » (19:41:09 UTC). Journaux du troisième passage : [taches](s4d-taches-3.log), [pipeline](s4d-pipeline-3.log), journaux de `construire` ([1](s4d-pipeline-1-construire.log), [2](s4d-pipeline-2-construire.log)).

- **`taches`** (19:41:19 UTC, code 0) : pipeline re-signée avec `preparer-deb@588617b8`, bundle `tekton/pipelines/sample-app-deb@sha256:82c8373d725941bf65d6530e0c88904bb291e5f8b5c18c2209919a6d355f54a5`.
- **D12 : tenue au troisième passage** (`pipeline`, de 19:41:24 à 19:56:04 UTC, code 0). Les deux PipelineRuns réussissent. `preparer` et `publier` tournent en runc, `construire` sous Kata, tous sur sc-build. Dans `construire`, l'étape en UID 1000 s'exécute sous Tekton (la déduction de la note de 19:38 UTC est confirmée). Les entrées sont montées `ro` (virtiofs), et l'écriture d'essai y est refusée. Les quatre témoins réseau échouent.
- **D13 : tenue.** Les deux exécutions publient **`builds/sample-app-deb@sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e`**, le digest calculé sur l'hôte en `prealables`. Chains signe les deux PipelineRuns.
- **Constats** : dans les deux constructions, le deb est `0b489d43…`, l'archive amont `07521c1e` et le `.dsc` `7f9cf5d3`, comme dans l'essai. sbuild met 361 s puis 339 s, sans aucune ligne apt en http(s).

