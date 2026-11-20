# Brique 05, carte de M5b (rejeu de zéro), préparée à sec (18/11/2026, écrite à 19:26:46 UTC)

**Interprétation** : le « Continue » reçu après le `/compact` (heure non relevée) vaut permission de préparer à sec, sous l'accord permanent du 18/11. Rien n'a été lancé ni écrit dans Zot, le cluster ou les VM. `rejeu.sh` reste inchangé. Une seule mesure, sur l'hôte et hors ligne ([script](m5b-archives.sh), [journal](m5b-archives.log)). Aucun script de M5b, aucune prédiction.

**Objet** : M5b est la seconde moitié de M5 (« un rejeu de zéro », critère « Refus attendus, témoins acceptés »). Elle a été découpée à part par la décision « Ok » du 18/11 (carte de M5, note de 18:29:02 UTC) : « jalon à part, pas avant le 28/11, avec sa propre carte, qui tranche la dette des images d'essai ». Modèle : S5b de la 06, rejeu de zéro terminé le 13/11 (README de la 08, additif de 15:52:32 UTC).

**Date** : la contrainte vise le rejeu, pas la carte. `revision-predictions.md` de la 06, l. 80 : « le rejeu de zéro reste exclu avant le 28/11 ». Raison : il viderait Zot avant le balayage de G7 du 28/11, prévu vers 12:17:25 UTC. La tâche de mesure est proposée à 13:02:25 UTC, d'après `g7-replanification.md` de la 07a, l. 100 et 101 ; c'est un calcul, pas une mesure. Le rejeu vient donc après la mesure de G7.

## 1. La dette à trancher

La décision « Option 1 » du 17/11 (carte de M4, note de 20:47:02 UTC) a inscrit trois dettes, citées telles quelles : « provenance des deux images hors de la plateforme ; racines installées avec réseau ; rejeu de zéro non réglé, à trancher avant M5 ». Le refus du 10/11 se lit à son seul texte, « pas d'image d'outils construite avec le réseau » (même note) ; je ne le relis pas.

- **Les deux images** : `essais-05/mock-rocky9@sha256:99790c13…` (outillage) et `essais-05/rocky9-bootstrap@sha256:f0ccf105…` (bootstrap, `image_digest` `18d64b03…`). Un rejeu vide Zot : elles disparaissent.
- **Ce qui les cite par digest** (vérifié dans le dépôt) :
  - l'outillage, par les tâches signées `prefetch-rpm` (`fermeture/prefetch-rpm.signee.yaml`, l. 44) et `construire-rpm` (`construction/construire-rpm.signee.yaml`, l. 18). `preparer-rpm` ne cite que des images de la plateforme (`outils-prefetch`, `outils-horodatage`) ;
  - le bootstrap, par le verrou (`pull_digest`, `image_digest`) et par la fermeture rpm `builds/fermetures/sample-app-rpm@sha256:2a9e2ea7…`, qui le porte en dossier `dir:`.
- **Mesuré** (19:25:23 UTC, [journal](m5b-archives.log)) : les deux archives des racines sont toujours sur l'hôte, dans le dossier de travail de S1 (`T` de `s1.sh`, l. 190). Leur taille et leur sha256 sont égaux à ceux des journaux archivés :
  - `racine.tar` : 361 758 720 octets, `d7433a05…` (`s1-racine.log`) ;
  - `boot-racine.tar` : 258 129 920 octets, `8ae17f92…` (`s1-boot_racine.log`).
- **Écrit dans le dépôt, jamais mesuré** : le commentaire de `s1.sh`, l. 793, dit que l'archive d'une racine « n'est pas reproductible au bit près (base rpm : INSTALLTIME ; journaux de dnf sous var/log) ». Chaque racine n'a été construite qu'une fois.
- **Mesuré** : le passage de l'archive à l'image a donné deux fois le même digest pour chacune des deux images. Pour l'outillage, `image` contre son banc loopback ; pour le bootstrap, `boot_image` contre son passage local.

**Options**, chacune jugée sur les trois dettes :

| | Option | Provenance hors plateforme | Racines avec réseau | Rejeu de zéro | Ce qui change en aval | Coût, comparables mesurés |
|---|---|---|---|---|---|---|
| A | **Republier à l'identique** depuis les deux archives (`image` et `boot_image`, sans `racine` ni `boot_racine`) | Inchangée | Inchangée | Rejoué **sauf deux archives** gardées sur l'hôte, hors de toute sauvegarde : un rejeu « de zéro, sauf deux fichiers » | Rien d'attendu : mêmes digests prédits pour les deux images, donc même verrou, même fermeture rpm, mêmes bundles de tâches, `taches.yml` inchangée. Prédiction, jamais mesurée après un vidage de Zot | Exécution : `image` 11 s, `boot_image` 10 s (`chrono.tsv`). Écriture : les modifications du point 2 |
| B | **Refaire les racines dans le rejeu** (`racine`, `image`, `boot_racine`, `boot_image`) | Inchangée | Inchangée | Rejoué en entier ; une racine refaite serait enfin comparée à la première | Nouveaux digests attendus (commentaire de la l. 793, jamais mesuré). Cascade : verrou (`image_digest`), fermeture rpm, bundles de `prefetch-rpm` et de `construire-rpm`, revue de `taches.yml`, rpm de M3 à recomparer | `racine` 5694 s et `boot_racine` 761 s d'exécution, causes inconnues ; plus la cascade, de l'ordre de M4b et M4c |
| C | **Images construites par la plateforme**, sans réseau (option 3 de la carte de M4) | Réglée | Réglée | Rejoué en entier | Tout : images, verrou, fermeture, tâches, revue, builds | Comparables de la carte de M4 : option 2 et la brique 05 de `boot_racine` à M3, 8,93 h, plus un prefetch d'outillage sans comparable. Un jalon à part, compté dans la règle des 2× |
| D | **Rejeu sans la 05** | Inchangée | Inchangée | Non rejoué pour la 05 : le critère de M5 n'est pas tenu | Rien | Nul |

A et D sont les seules options qui ne touchent ni aux tâches signées ni à `taches.yml`. Seule C règle les deux premières dettes.

**Recommandation, la mienne** : A, pour fermer M5 au moindre coût, avec la dette portée telle quelle et nommée dans le bilan : provenance hors plateforme, racines avec réseau, et deux archives de l'hôte en entrée du rejeu. C, en jalon à part, si tu veux régler la dette. Je ne l'appuie pas sur le refus du 10/11.

## 2. Ce que `rejeu.sh` devrait gagner (vérifié dans le dépôt, sauf mention)

- **État de `rejeu.sh`** :
  - aucune étape de la 05 (carte de M5) ;
  - la sortie rpm y est déjà : `sortie-builds.sh rejeu`, l. 263 à 272, pose `prefetch-rpm-sortie` et le `NotIn` à trois labels.
- **Jamais rejoué depuis le S5b du 13/11** :
  - l'intégration de S6 de la 06 : « pas encore rejoué », note du 14/11 au README de la 08 ;
  - la sortie rpm, appliquée au dépôt le 16/11 ;
  - la cascade 1.0.0-2 de la 06, avec l'artefact de packaging `f0ed7a71` (14/11).
- **Fermeture de sources épinglée par M4c** (`m4c.sh`, l. 66) : `sample-app-sources@50dc73f7…`. Elle a été retrouvée au bit près deux fois :
  - par le rejeu S5b du 13/11 (`rejeu-s5b-06-a.log`, l. 463 : deux exécutions, même fermeture) ;
  - après la cascade, par S4b le 14/11 (README de la 06, l. 2063 : « fermetures bb7599a2 et 50dc73f7 inchangées »).
  
  Les autres entrées de M4c venues de la 06 sont `outils-prefetch@68e0ae70` et `publier-image@d21931f3`. D'après le relevé 2 de la carte de S5b, elles ont été reproduites par les rejeux du 03/11 et du 06/11, et `68e0ae70` l'a été encore le 13/11.
- **Place du bloc de la 05** : après le bloc 06, parce que M4c lit la fermeture de sources de la 06 et que la sortie rpm est posée dans le bloc 08c.
- **Étapes durables de la 05 à rejouer**, avec leur durée mesurée (`chrono.tsv`) :

| Étape | Ce qu'elle pose | Durée mesurée |
|---|---|---|
| `s1.sh amorce` (05) | rockylinux 9.8 et 9.7, copiés par digest depuis quay.io dans Zot | 12 s |
| `s1.sh image`, `boot_image` (option A) | les deux images d'essai, depuis les archives | 11 s, 10 s |
| `s1.sh m3_reseau` | la NetworkPolicy `construction-rpm-sans-sortie` | moins de 1 s |
| `m4a.sh publier` | l'artefact de packaging `packaging-rpm@41c639b7…` | 3 s |
| `m4b.sh taches`, `rpm` | le bundle de `prefetch-rpm`, la pipeline `prefetch-rpm-sample-app`, la fermeture rpm | 2 s par passe, 2 min 43 s |
| `m4c.sh taches`, `pipeline` | les bundles de `preparer-rpm` et `construire-rpm`, la pipeline `sample-app-rpm`, le rpm publié | 4 s par passe, 4 min 32 s |

- **Hors du rejeu**, comme les mesures de la 06 : `hote`, `essais`, `verrou*`, `voie2`, `hermetique`, `collecte`, la fermeture de M2, les builds et la comparaison de M3, les étapes d'essai de M4. Les lectures `comparaison` et `provenance` de M4b et M4c peuvent servir de témoins après le rejeu.
- **Modifications prévisibles**, à préparer à sec après ta décision :
  - Les digests de pipeline écrits en dur (`m4b.sh`, l. 716 ; `m4c.sh`, l. 650 ; `m5.sh`, l. 45) cassent à coup sûr. Un bundle de pipeline change à chaque signature, car ECDSA n'est pas déterministe ; c'est mesuré dans la 06, et c'est le cas de `PIPE_DEB` en S5b.
  - Le chemin sans `SIGNER` de `taches` est à relire (`m4b.sh`, l. 679 à 691 ; `m4c.sh`, l. 590 à 630). Il faut savoir s'il repousse les bundles de tâches depuis les fichiers signés versionnés sur un Zot vide, comme le fait la 06.
  - Les gardes « dépôt absent » et les préfixes de tags sont à relire.
  - Option A : `image` lit `$T/racine.tar`, avec un `T` fixe (`s1.sh`, l. 190). Sa couche de configuration est régénérée depuis `MOCK_CFG` et `STOCKAGE`, deux constantes de `s1.sh` (l. 454 à 477), en tar à date nulle. `s1.sh` a changé depuis `image`. Le sha256 de la configuration est donc à recomparer à `a8e5f2bc…` (`s1-image.log`, l. 3), et le digest de l'image à `99790c13…`, avant qu'une tâche ne la lise.
  - Option A : `boot_racine` efface `boot-racine.tar` en repartant (`s1.sh`, l. 943). Elle ne doit pas être dans le rejeu.
- **Mêmes digests prédits** pour les bundles de tâches, pour la fermeture rpm (`2a9e2ea7` : calcul à sec égal à la mesure en M4b) et pour l'artefact rpm (`07b7bd6f`, égal entre l'essai et deux PipelineRuns). Ce sont des prédictions, à écrire avec leur confiance avant le rejeu.

## 3. Préalables à relever le jour du lancement

L'état du cluster et de l'hôte aura bougé d'ici le 28/11. Rien de ce qui suit n'est relevé aujourd'hui, sauf les archives (point 1).

- **Disque** : PT7 n'a pas été tenue le 18/11, avec 4,49 Go libres pour Zot. `/` de sc-stockage grossit d'environ 1,19 Go par jour sans écriture de la brique, et sa cause n'est pas attribuée. Sur dix jours, cela peut bloquer le rejeu avant même la 05. Le `sudo du -B1` reste chez toi ; je ne mesure rien sous sudo.
- **Archives de l'hôte** (option A) : `m5b-archives.sh` est à relancer juste avant `image` et `boot_image`.
- **Amont** : sont à relire `quay.io/rockylinux/rockylinux` aux deux digests de l'amorce, et vault 9.7 pour `prefetch-rpm`.
- **Ordre** : après la mesure de G7 du 28/11, et sous `POUSSER_VSA=1` seulement si tu l'accordes pour ce rejeu.
- **Perte de données** : acceptée en démo. Aucune sauvegarde n'est proposée.

## 4. Réserves héritées

| Réserve | Origine | Couverte par M5b |
|---|---|---|
| R4 avec un `repodata/` refait | M5a | Non : test négatif, hors du rejeu |
| Seconde barrière réseau du build rpm (mock `--isolation=simple` ne coupe pas `%build`) | M5a | Non : point ouvert chez toi, non tranché ici |
| `BUILDTIME` `1794787200` dans les journaux de `construire`, qui n'est pas l'époque `1793229566` | M4c | Non : le rejeu peut redonner `07b7bd6f` sans l'expliquer |
| Porte sans tâche rpm | M4 | Non |
| Vérification par clé, sans journal de transparence | M4 | Non |
| Provenance hors plateforme, racines avec réseau | « Option 1 » | Option C seulement |

## 5. Effort et estimation

- **Brique 05** : **24,89 h** (185 commits, date d'auteur) à `c2c5809`, relevé à 18:21:34 UTC (`temps-05-1211.log`). M5a s'y ajoute et n'est pas encore relevé. Estimation de la brique : 2,5 pw ; décision avec toi à 5 pw. Les heures ne sont pas converties en pw.
- **S5b mesuré**, comparable du rejeu : de 08:54:01 UTC (`rejeu-s5b.log`, l. 1) à 15:51:47 UTC le 13/11, soit environ 7 h sur une journée. Il a fallu neuf journaux de rejeu (`rejeu-s5b*.log`), des étapes rejouées à la main, six arrêts et trois correctifs d'instruments (additif de fin). Son estimation était d'une journée, avec une décision à deux jours ; tenue.
- **Estimation de M5b, option A** : **1,5 jour**.
  - 0,5 jour de préparation : modifications du point 2, prédictions, banc. Comparable : M4c, 2,30 h de commits et 4,29 h de bout en bout.
  - 1 jour de rejeu : comme S5b, plus environ 8 min d'exécution mesurée pour la 05 (somme du tableau du point 2), plus l'intégration de S6 et la cascade, jamais rejouées.
- **Règle des 2×** : décision avec toi à 3 jours. Option B : à chiffrer après mesure, avec en plus `racine` et `boot_racine` (6455 s d'exécution mesurée, environ 1 h 48) et la cascade de M4b et M4c. Option C : sa propre carte.

## Question posée

**La dette des images d'essai au rejeu** : A, B, C ou D (point 1). Rien ne change dans `rejeu.sh` avant ta réponse.

## Note datée du 18/11/2026, écrite à 19:33:32 UTC : décision « C »

**Décision du propriétaire** (réponse reçue avant 19:33:32 UTC, heure exacte non relevée) : « C », sur la question « La dette des images d'essai au rejeu : A, B, C ou D ». Elle va contre ma recommandation, qui était A. Ce n'est un accord pour aucun lancement ni aucune écriture. `rejeu.sh` reste inchangé.
- **Option C** (point 1) : les deux images, outillage et bootstrap, seront construites par la plateforme, sans réseau, sur le modèle de l'option 3 de la carte de M4. Ce sera un jalon à part, avec sa propre carte et sa propre estimation, compté dans la règle des 2×.
- **Lecture** : la question portait sur les images utilisées « au rejeu ». Je lis donc que le rejeu de M5b se fera avec les images construites par la plateforme, une fois ce jalon tenu, et non avec les images d'essai `99790c13…` et `f0ccf105…`. A, B et D ne sont pas retenues.
- **Conséquences attendues**, écrites au point 1 et non mesurées :
  - nouveaux digests d'images ;
  - verrou (`pull_digest`, `image_digest`) et fermeture rpm à refaire ;
  - nouveaux bundles pour `prefetch-rpm` et `construire-rpm`, avec une nouvelle revue de `taches.yml` ;
  - builds de M3 et de M4 à recomparer.
  
  L'estimation de 1,5 jour du point 5 ne vaut que pour l'option A. Elle sera refaite dans la carte du jalon des images.
- **Inchangé** : le rejeu reste exclu avant le 28/11. Les réserves du point 4 restent ouvertes, dont la seconde barrière réseau du build rpm, qui n'est pas tranchée.
- **Suite** : carte du jalon des images, préparée à sec sous l'accord permanent du 18/11.

## Note datée du 20/11/2026, écrite à 2026-11-20T16:18:58Z UTC : préparation du rejeu sous l'option C (inventaire à sec)

**Portée** : lecture des scripts et des journaux seulement. Rien n'est lancé ni écrit dans Zot, le cluster ou les VM. `rejeu.sh` et `vm.sh` ne sont pas touchés.
- Pour l'option C, cette note remplace la liste des étapes durables du point 2, le préalable « Disque » du point 3 et l'estimation du point 5. Ces passages restent écrits tels quels.
- Elle complète les « modifications prévisibles » du point 2, qui restent valables. En particulier, aucun journal n'est réécrit : le rejeu se fait sous un autre `PREFIXE`, que `TAG` suit par défaut. Les gardes « dépôt absent » et les préfixes de tags restent à relire.

**Déjà couvert par le rejeu** :
- **Quatre labels** : l'étape `rejeu` de `sortie-builds.sh` (l. 350 à 364) pose les deux politiques de M1b et attend le `NotIn` à quatre labels (l. 360). La référence « l. 263 à 272 » du point 2 est périmée.
- **ConfigMap `porte`** : `cm_porte` (`politique.sh`, l. 1316) la refait depuis le `taches.yml` du dépôt (l. 1322). Son retard sur `taches.yml` disparaît donc avec le rejeu. C'est déduit du code, non mesuré.
- **Anciennes versions dans `taches.yml`** : les bundles de M4b et M4c (`9afe09db…`, `d7f01398…`) y restent listés et seront absents de Zot après le rejeu. Une recherche par motif dans les scripts ne trouve aucun contrôle qui exige que chaque référence listée existe dans Zot. Non mesuré.

**Étapes durables de la 05 sous l'option C** (à la place des images d'essai) :

| Étape | Ce qu'elle pose | Durée mesurée |
|---|---|---|
| `s1.sh amorce` | rockylinux 9.8 `ed654c69…` (amorce des tâches de M1b, `m1b-signature.sh`, l. 33) et 9.7 `ee90dc0e…` (base du bootstrap, `m1b-pipeline.sh`, l. 65) | 12 s |
| `s1.sh m3_reseau` | `construction-rpm-sans-sortie`, que le rejeu de la 08c ne pose pas ; dépendances aux images d'essai à relire | moins de 1 s |
| `m1b-signature.sh taches`, sans `SIGNER` | bundles de `prefetch-racine-rpm` et `construire-racine-rpm` poussés depuis `builders/*.signee.yaml` (l. 107) ; pipelines `builder-mock-rocky9` et `builder-rocky9-bootstrap` signées et poussées | non relevée |
| `m1b-pipeline.sh pipeline` | les deux images, `70f8c412…` et `6de899ac…` (l. 57 et 61), par quatre PipelineRuns | 9 min 15 s (09:02:23 à 09:11:38Z le 20/11) |
| artefact de M4a, puis `m1b-artefact.sh publier` | `packaging-rpm@41c639b7…`, puis `333b7322…` | 3 s pour M4a ; celle de la cascade non relevée |
| bundles des tâches rpm | `prefetch-rpm` (`b9bbeba3…`), `construire-rpm` (`ca03f189…`), `preparer-rpm` (`2f65f390…`) | 2 à 4 s par passe en M4b et M4c |
| pipeline et fermeture (M4b refait) | `prefetch-rpm-sample-app` (`61814acd…`), fermeture `09838980…` | 1 min 58 s (`m1b-fermeture-rpm.log`) |
| pipeline et rpm (M4c refait) | `sample-app-rpm` (`7d361cb1…`), artefact `07b7bd6f…` | 4 min 29 s (`m1b-construction-construction.log`) |

**Hors du rejeu** :
- `s1.sh racine`, `image`, `boot_racine` et `boot_image` : images d'essai, écartées par la décision C.
- `m1b-verrou.sh` : c'est une mesure. `m1b-artefact.sh` lit le verrou `c544599a…` dans le dépôt (`resultats/m1b-verrou.json`, l. 50).
- `m1b-builders.sh prealables` (hôte, hors ligne, l. 5), les bancs, les pods d'essai et R1 à R8.
- `comparaison` et `provenance` peuvent servir de témoins après le rejeu.

**Entrées lues hors du dépôt**, sur l'hôte, qui survivent à la recréation des VM mais pas à un nettoyage du cache :
- `$W/m1bt-20-05` : rendu de `prealables`, lu par `m1b-signature.sh` (`RENDU`, l. 27) et contrôlé par sha256 (`RENDUS_SHA`, l. 37) ;
- `$W/m1b-signature-05` : sorties de `m1b-signature.sh`, lues par `m1b-pipeline.sh` (`SIG`, l. 41) ;
- `$W/m4a-05/layout-1` : manifeste de M4a, lu par `m1b-artefact.sh` (`M4A_LAYOUT`, l. 55) ;
- l'arbre de l'essai archivé, lu par la garde de `m1b-fermeture.sh rpm` (l. 546).

**Ce qui casse si on rejoue les étapes telles quelles** :
- **Signature à chaque passage** : `m1b-bundles.sh taches`, `m1b-fermeture.sh pipeline` et `m1b-construction.sh pipeline` exigent `SIGNER=1` (l. 473, 486 et 755) et re-signent. ECDSA n'est pas déterministe. Les digests changeraient, et avec eux les `PIPELINE_REF` écrites en dur (`m1b-fermeture.sh`, l. 94 ; `m1b-construction.sh`, l. 118) et la liste revue.
- **Remède prévu** : `bundle` (`commun.sh`, l. 308) pousse avec une date de création fixe. Un même fichier signé doit donc donner le même digest.
  - C'est mesuré dans S5b pour les tâches de la 06 : sur un Zot neuf, `rejeu-s5b-06-a.log` à `-c.log` comptent 11 contrôles « dans la liste revue » passés. Ce n'est pas mesuré dans la 05.
  - Les signatures versionnées existent pour toutes les tâches et pipelines rpm : `builders/*.signee.yaml`, `fermeture/*.m1b.signee.yaml`, `construction/*.m1b.signee.yaml` et `construction/preparer-rpm.signee.yaml`.
  - Une étape de republication sans signature, comme dans la 06, est à écrire.
- **Pipelines `builders`** : `m1b-signature.sh` les re-signe à chaque passage (l. 127) et ne les versionne pas (l. 131 : seulement sous `$T`). Leur digest changera donc au rejeu. Rien ne casse pour autant : `m1b-pipeline.sh` lit leur référence dans `$SIG` (l. 157), pas en dur. Les deux tâches `builders` sont, elles, versionnées (l. 76).
- **Gardes tournées vers M4b, M4c et les images d'essai** : elles échouent sur un Zot vide sans les images d'essai. Elles sont à sauter ou à remplacer dans le chemin du rejeu, sans toucher aux étapes de mesure.
  - `m1b-bundles.sh` : l. 54, 65 et 66 ;
  - `m1b-fermeture.sh` : l. 62, 84 et 89 ;
  - `m1b-construction.sh` : l. 114 ;
  - `m1b-artefact.sh` : « tag m4a sur 41c639b7 », l. 18 et 22. L'artefact de M4a doit donc être republié avant `m1b-artefact.sh`.

**Préalables du point 3, corrigés** :
- **Disque** :
  - Le rythme d'environ 1,19 Go par jour sans cause est remplacé par l'attribution du 20/11 à 16:00:00Z, la base grype quotidienne d'environ 200 Mo par jour. S'y ajoute l'agrandissement à 30G (note de 16:04:46Z de la carte de M1b).
  - Le rejeu recrée sc-stockage à 20G (`vm.sh`). Les neuf journaux de S5b ne contiennent aucun relevé de place de sc-stockage : « octets libres » y apparaît 0 fois. La place occupée après un rejeu est donc **non mesurée**.
  - Premier relevé à prendre : un `df` de `/` sur sc-stockage vers 16:00Z le 21/11, à 24 heures de celui de 16:04Z.
- **Amont** : il faut relire vault 9.8 et l'archive EPEL 9.8 (`m1b-builders.sh`, l. 46), en plus de vault 9.7 (l. 47), et l'amorce par ses deux digests sur quay.io.

**Prédictions, à écrire avant le rejeu** :
- **Bundles republiés depuis les signatures versionnées** : mêmes digests que la liste revue. Confiance haute (`commun.sh`, l. 308 ; mesuré pour la 06 en S5b).
- **Pipelines `builders`** : digests neufs, ce qui est certain.
- **Images `70f8c412…` et `6de899ac…`** : confiance moyenne. Deux passages et une mesure d'un autre jour ont donné le même digest, mais tout dépend des sources 9.8 figées et de l'amorce.
- **Artefact `333b7322…`** : confiance haute (calcul local, deux layouts, même digest).
- **Fermeture `09838980…`** : haute si les images retombent sur leurs digests, car la fermeture contient le bootstrap. Sinon, elle change.
- **rpm `07b7bd6f…`** : confiance moyenne. La réserve du `BUILDTIME` (point 4) n'est pas expliquée.

**Effort mesuré**, même méthode que [`temps-05-1211.log`](temps-05-1211.log) (date d'auteur, écarts d'au plus 1 h). Ce relevé y est ajouté, et la méthode y redonne les valeurs déjà archivées.
- **M1b et sa cascade**, de `1e25df14` (carte de M1b, 18/11 à 19:38:40Z) à `a4360d3b` : 177 commits, **16,38 h**, et 44,44 h de bout en bout. L'estimation était de 3 jours, avec une décision à 6. Les heures ne sont pas converties.
- **Brique 05**, de `196ee343` à `a4360d3b` : 376 commits, **42,82 h**.

**Estimation de M5b sous l'option C** : **2 jours**, avec une décision avec toi à 4 jours.
- **Hypothèse** : la republication depuis les signatures versionnées redonne les digests de la liste revue. Si ce n'est pas le cas, il faut une nouvelle signature et une revue de `taches.yml`, ce qui est ta décision.
- **1 jour de préparation** : étape de republication sans signature, chemin du rejeu pour les gardes, bloc 05 dans `rejeu.sh`, banc et prédictions. Comparable : la cascade après M1b, 5,38 h de commits de `636f6b83` à `a4360d3b`.
- **1 jour de rejeu** : comme S5b (environ 7 h le 13/11), plus environ 16 min d'exécution mesurée pour la 05 (somme du tableau), plus l'intégration de S6 et la cascade de la 06, jamais rejouées.

**Décisions ouvertes, chez toi, non posées ici** :
- la taille du disque de sc-stockage dans `vm.sh`, qui attend le `df` du 21/11 ;
- la rétention de la base grype dans Zot (07a) ;
- la seconde barrière réseau du build rpm ;
- la clôture de la brique 05, après M5b.

Le rejeu reste exclu avant la mesure de G7 du 28/11.

## Prédictions écrites le 20/11/2026 à 2026-11-20T16:27:07Z UTC, avant tout lancement : banc de republication

**But** : mesurer l'hypothèse de l'estimation de M5b sous C (note de 16:18:58Z), avant d'écrire l'étape de republication. Un même fichier signé, poussé par `bundle` (`commun.sh`, l. 308), doit redonner le digest de la liste revue, sans nouvelle signature.

**Banc** : [`m5b-republication-banc.sh`](m5b-republication-banc.sh) (`2ec613ef45b5773e…`, shellcheck sans remarque), journal `m5b-republication-banc.log`, dossier neuf `~/.cache/supply-chain-poc/05/banc-m5b-republication`.
- Registre crane local en http sur `127.0.0.1:5909`. Rien n'est écrit dans Zot ni dans le cluster. Aucune clé n'est lue, rien n'est signé.
- `bundle` est extraite par texte de `commun.sh`, qui n'est pas sourcé : son `REG_HOTE` est le vrai Zot. `DOCKER_CONFIG` pointe vers un `{}` du banc.
- `tkn bundle push` lit `SOURCE_DATE_EPOCH` (aide de tkn 0.46.2, date par défaut 1970-01-01T00:00:00Z). Le banc la retire.
- Les 9 signatures versionnées sont poussées sous leur chemin de dépôt réel, avec le tag `m1b` puis `banc2`. Les attendus sont lus dans le dépôt : `taches.yml` de la 08 pour les 7 tâches, lignes `PIPELINE_REF` de `m1b-fermeture.sh` (l. 94) et `m1b-construction.sh` (l. 118) pour les 2 pipelines.

**Prédictions** :
- **RE1** (haute) : tkn 0.46.2 et crane 0.20.6, `SOURCE_DATE_EPOCH` absente, `bundle` extraite telle quelle et sans `--ctime`.
- **RE2** (haute) : les 9 digests au tag `m1b` sont égaux aux attendus :
  - tâches : `prefetch-racine-rpm` `16a32993…`, `construire-racine-rpm` `bdde08ed…`, `prefetch-rpm` `9afe09db…` (M4b) et `b9bbeba3…` (M1b), `construire-rpm` `d7f01398…` (M4c) et `ca03f189…` (M1b), `preparer-rpm` `2f65f390…` ;
  - pipelines : `prefetch-rpm-sample-app` `61814acd…`, `sample-app-rpm` `7d361cb1…`.
- **RE3** (haute) : le tag `banc2` redonne les 9 mêmes digests. Le digest ne dépend donc pas du tag, que le rejeu change avec le `PREFIXE`.
- **RE4** (haute) : la date de création de la configuration vaut 1970-01-01T00:00:00Z pour les 9.

**Clé des tâches au rejeu** : `politique.sh` garde une clé existante (l. 370, « clé existante »). C'est mesuré en S5b : `rejeu-s5b-plateforme.log` compte une fois « clé existante ». La clé publique reste donc la même, et les signatures versionnées restent valides pour Trusted Resources. C'est déduit du code et de ce journal ; l'admission elle-même n'est pas couverte par le banc.

**Non couvert** : Zot (TLS, authentification, compte `poc-ecriture`), Tekton, Trusted Resources, Kyverno.

**Suite** :
- Un écart sur l'un des 9 : arrêt, archivage, et l'hypothèse de l'estimation n'est pas tenue (nouvelle signature et revue de `taches.yml`, ta décision).
- 9 sur 9 : l'étape de republication sera écrite comme un script frère, sans toucher aux `m1b-*.sh` de mesure. Elle ne prendra ni clé ni `SIGNER` et poussera les tâches avant les pipelines. Elle s'arrêtera au premier digest hors liste. Elle portera sur 5 fichiers (trois tâches rpm, deux pipelines) : `m1b-signature.sh taches` republie déjà les deux tâches `builders`.

## Note datée du 20/11/2026, écrite à 2026-11-20T16:28:06Z UTC : banc de republication, résultat, et prédiction d'un passage sous `TZ=UTC`

**Passage** le 20/11/2026 à 16:27:19 UTC, au dépôt `23727e28`. Le banc rend 1 avec « bilan : 36 OK, 9 KO » ([`m5b-republication-banc.log`](m5b-republication-banc.log)). Les 9 KO sont tous des C3. Les poussées durent 1 s.

- **RE1 tenue** : tkn 0.46.2 et crane 0.20.6. `SOURCE_DATE_EPOCH` est absente. `bundle` est extraite telle quelle de `commun.sh` et ne porte pas `--ctime`.
- **RE2 tenue** : au tag `m1b`, les 9 digests sont égaux aux attendus lus dans le dépôt (9 C1).
- **RE3 tenue** : le tag `banc2` redonne les 9 mêmes digests (9 C2).
- **RE4 non tenue dans sa forme** : la date de création vaut `1970-01-01T01:00:00+01:00` pour les 9, et non `1970-01-01T00:00:00Z`. C'est le même instant, l'époque 0, mais tkn l'écrit dans le fuseau local de l'hôte : Europe/Paris, `TZ` non posée.
  - La configuration, et donc le digest, contient ce texte. Les digests de la liste revue ont été poussés sous ce même fuseau, et c'est pourquoi RE2 tient.
  - Ni `rejeu.sh` ni `commun.sh` ne posent `TZ`.

**Conséquence pour l'hypothèse de l'estimation** : elle est tenue sur le banc pour les 9 fichiers. Elle l'est pour un hôte au fuseau Europe/Paris, qui écrit `+01:00` pour le 1er janvier 1970 (pas d'heure d'été en 1970). Zot, Tekton et l'admission restent non couverts.

**Prédiction, écrite avant le lancement** : le même banc, inchangé, est relancé sous `TZ=UTC`. Il utilise un dossier neuf (`banc-m5b-republication-utc`), le port 5910 et le journal `m5b-republication-banc-utc.log`.
- **RE5** (haute) : la date de création vaut `1970-01-01T00:00:00Z` pour les 9 (9 C3 OK).
- **RE6** (haute) : les 9 digests diffèrent des attendus, aux deux tags (18 KO en C1 et C2). Le digest dépend donc du fuseau de l'hôte.
- Si RE5 et RE6 tiennent, l'étape de republication devra fixer `TZ=Europe/Paris` pour `tkn bundle push`. Il faudra aussi le signaler comme une condition de reproductibilité des bundles de toute la plateforme. Ce constat ne touche pas la 06 en S5b, poussée depuis le même hôte.

## Note datée du 20/11/2026, écrite à 2026-11-20T16:28:59Z UTC : banc de republication sous `TZ=UTC`, résultat

**Passage** le 20/11/2026 à 16:28:16 UTC, au dépôt `5b415052`, avec le même script sous `TZ=UTC`. Le banc rend 1 avec « bilan : 27 OK, 18 KO » ([`m5b-republication-banc-utc.log`](m5b-republication-banc-utc.log)). Les 18 KO sont tous des C1 et des C2.

- **RE5 tenue** : la date de création vaut `1970-01-01T00:00:00Z` pour les 9 (9 C3 OK).
- **RE6 tenue** : les 9 digests diffèrent des attendus. Chaque fichier donne pourtant un même digest aux deux tags. Par exemple, `prefetch-racine-rpm` donne `df6098fb…` au lieu de `16a32993…`.

**Constat** : le digest d'un bundle poussé par `bundle` (`commun.sh`, l. 308) dépend du fuseau de l'hôte, parce que tkn 0.46.2 écrit la date de création en heure locale. Sur cet hôte (Europe/Paris, `TZ` non posée), un même fichier signé redonne le digest de la liste revue, quel que soit le tag.

**Conséquences pour l'étape de republication, à écrire** :
- Elle fixe `TZ=Europe/Paris` pour `tkn bundle push`, et `SOURCE_DATE_EPOCH` absente.
- Elle s'arrête au premier digest hors liste.
- Le reste de la plateforme pousse ses bundles par la même fonction, sans `TZ` : cette condition vaut pour toutes les briques, et la 06 en S5b l'a remplie sans le savoir, depuis le même hôte. `commun.sh` n'est pas modifié ici ; c'est une proposition, à te soumettre.

## Note datée du 20/11/2026, écrite à 2026-11-20T16:31:38Z UTC : corrections et prédiction RE7

**Corrections des notes de 16:28:06Z et 16:28:59Z** (elles restent écrites telles quelles) :
- « pas d'heure d'été en 1970 » n'était établi par aucune commande. `TZ=Europe/Paris date -d @0 +%:z` donne `+01:00`, et la même commande pour le 1er juillet 1970 à 12:00 UTC donne `+01:00`. L'indépendance à la saison est **déduite** : tkn écrit l'époque 0, dont le décalage ne dépend pas du jour du passage.
- « Le reste de la plateforme pousse ses bundles par la même fonction » ne s'appuyait que sur la 05. Recherche élargie à `poc/`, `tools/` et `mise.toml` :
  - `tkn bundle push` n'apparaît dans aucun script hors de `commun.sh` (les autres occurrences sont dans des journaux, des notes et un README) ;
  - `$(bundle ` est appelé 41 fois dans 15 scripts, des briques 01, 03, 05, 06, 08 ;
  - aucun de ces appels n'est précédé d'un `TZ=`.
- Le remède « `TZ=Europe/Paris` » n'est pas encore mesuré. Seuls `TZ` absente (premier passage) et `TZ=UTC` l'ont été. Il est prédit ci-dessous.
- Les dossiers `banc-m5b-republication` et `banc-m5b-republication-utc` ont été effacés après les passages (108 Kio chacun, lus par aucun script). Les journaux archivés restent.

**Prédiction, écrite avant le lancement** : le même banc, inchangé, sous `TZ=Europe/Paris` posée explicitement. Il utilise un dossier neuf (`banc-m5b-republication-paris`), le port 5911 et le journal `m5b-republication-banc-paris.log`.
- **RE7** (haute) : même bilan que le premier passage, « 36 OK, 9 KO ». Les 9 C1 et les 9 C2 sont égaux aux attendus, et les 9 KO sont des C3 à `1970-01-01T01:00:00+01:00`.
