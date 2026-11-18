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
