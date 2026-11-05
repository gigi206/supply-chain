# Brique 05 : rpm hermétique avec mock (rocky-9), protocole proposé

Seuil (README, brique 05) : **bit-identique ; 0 pod privilégié sur l'hôte.** Effort estimé : **2,5 pw** ; décision avec le propriétaire à 5 pw.

Règles reprises : projets jugés par le doc 04, rien de « Risqué » (mock : « À surveiller », chemin critique) ; versions épinglées ; empreintes et signatures vérifiées ; prédictions datées et committées avant chaque mesure ; passages ratés archivés ; accord du propriétaire avant tout changement du cluster, de Zot ou d'un système.

## État

**Préparé à sec le 05/11/2026 à 22:21 UTC, rien installé, rien construit.** Seul [`releve-amont.sh`](releve-amont.sh) a tourné : il lit des métadonnées et des textes amont aux tags épinglés, et le seul paquet téléchargé, `uidmap`, est listé sans être extrait ni exécuté ([journal](resultats/releve-amont.log) ; passages incomplets archivés : [premier](resultats/releve-amont-premier-passage.log), [deuxième](resultats/releve-amont-deuxieme-passage.log)). Les décisions ci-dessous attendent le propriétaire. Les jalons M1 et suivants n'ont pas de place avant le rejeu RKE2 (08b) : tout ce qui serait posé avant serait effacé par lui.

La brique [06](../06-deb-sbuild/README.md) suit le même plan.

## Ce qui existe déjà

- **Recettes** : [`poc/packaging`](../../packaging/README.md) contient le spec et les sources de sample-app, reproductibles et vendorées (Go et `marked`).
- **Réglages rpm mesurés sur OBS** : [`poc.prjconf`](../../benchmarks/obs/projets/poc.prjconf) fixe `%_buildhost`, `%source_date_epoch_from_changelog`, `%use_source_date_epoch_as_buildtime` et `%clamp_mtime_to_source_date_epoch`. Ils ont donné un rpm identique sur 2 builds, hors signature ([résultats](../../benchmarks/obs/resultats/README.md)). OBS est démonté : le banc ne peut pas être rejoué.
- **Construction sans sortie** : la voie A de la brique 08 (pod Kata privilégié, tâche signée, `construction-sans-sortie`, anti-usurpation par Cilium) est en service pour BuildKit.
- **Fermetures** : la brique 03 archive dans Zot, par digest, et son prefetch tourne encore sur l'hôte.

## Relevé amont (05/11/2026, 22:26 UTC)

| Point | Mesuré | Conséquence |
|---|---|---|
| mock | **6.9-1** et `mock-core-configs` 45.2-1 dans EPEL 9 ; dernière release amont `mock-6.9-1` (01/10/2026) | L'index d'EPEL 9 n'a montré que ces versions : les rpm de mock retenus doivent être archivés, sinon l'image du constructeur ne se reconstruit plus |
| mock dans Debian stable | **Absent** du relevé | L'image du constructeur part d'un système EL, pas de Debian |
| Rocky | 9.8 dans `pub/`, **9.7 dans `vault/`** avec `repomd.xml` et `repomd.xml.asc` (HTTP 200) pour BaseOS, AppStream et CRB | 9.7 est la version du banc OBS ; empreintes des `repomd.xml` au journal |
| Configuration `rocky-9-x86_64`, tag `mock-core-configs-45.2-1` | `mirrorlist=` par défaut, `bootstrap_image=quay.io/rockylinux/rockylinux:9` (tag mobile) | À remplacer par des `baseurl` fixes et une image par digest |
| Documentation hermétique, tag `mock-6.9-1` | Déconseille les dépôts à miroirs pour le verrou ; dit que le mode hermétique ne donne pas à lui seul un build reproductible ; exige une image de bootstrap prête ; le verrou n'est garanti que pour **la même version de mock** | Version de mock identique entre résolution et build, et réglages de reproductibilité gardés |

Séquence amont : `mock --calculate-build-dependencies` (en ligne) produit `buildroot_lock.json`, `mock-hermetic-repo` télécharge les rpm et l'image de bootstrap, `mock --hermetic-build` construit sans réseau.

## Préalables au doc 04

Le protocole introduit des éléments que le doc 04 n'audite pas (recherche du 05/11/2026 sur `podman`, `rockylinux` et `rocky`, sans résultat utile). Rien ne sera utilisé avant leur audit, et un verdict « Risqué » arrêterait la voie concernée :
- **podman**, exigé de fait par l'image de bootstrap de mock ;
- **image `quay.io/rockylinux/rockylinux`**, par digest, avec sa signature si elle existe ;
- les versions exactes de mock et de `mock-core-configs`, déjà auditées comme projet, à repréciser.

## Décisions à prendre

**D1. Lecture du seuil et isolation.** Recommandé : **(a)**.
- (a) mock tourne en pod Kata privilégié (voie A, comme BuildKit). « 0 pod privilégié sur l'hôte » se lit alors comme le test 4 de la 08 : aucun pod privilégié hors Kata. Le root reste celui de l'invité.
- (b) Exiger un pod non privilégié même sous Kata. Non documenté par mock ; il faudrait d'abord mesurer si c'est possible.

**D2. Source des rpm.** Recommandé : **(a)**.
- (a) `vault/rocky/9.7`, en `baseurl` fixes. Dépôt figé, signatures relevées, mêmes versions que le banc OBS. Il ne reçoit plus de correctifs : le scan le montrera.
- (b) `pub/rocky/9.8`. À jour, mais son contenu bouge ; la fermeture devient la seule référence.

**D3. Résolution.** Recommandé : **(a)**.
- (a) Sur l'hôte d'abord, comme le prefetch de la 03, puis dans Tekton en M4.
- (b) Dans Tekton dès le début : plus proche de la cible, mais une panne mêlerait mock, réseau et admission.

## Jalons proposés

Chaque jalon demande un accord. Une étape à la fois, pour qu'un échec soit attribuable.

| Jalon | Contenu | Preuve attendue |
|---|---|---|
| M1 | Après les préalables au doc 04 : image `builders/mock-rocky9` construite par notre chaîne, base Rocky par digest, mock 6.9 épinglé ; essai à la main dans un pod Kata : mock, podman imbriqué, isolation `nspawn` puis `simple` | Journal de chaque essai ; choix d'isolation motivé |
| M2 | Configuration de mock versionnée (D2, digest du bootstrap, macros d'OBS) ; verrou calculé ; signatures des rpm vérifiées ; fermeture poussée dans Zot sous `deps/sample-app/mock-buildroot-lock`, avec le rpm de mock et l'image de bootstrap | Fermeture restaurable par digest ; déduplication mesurée |
| M3 | Deux `--hermetic-build` sans réseau depuis la fermeture restaurée, dans deux répertoires différents | Mêmes NEVRA, même sha256 pour le rpm et le src.rpm ; sinon diffoscope |
| M4 | Tâches signées de prefetch et de build dans la pipeline ; rpm poussé par ORAS sous `artifacts/sample-app/rpm` ; provenance de Chains | Sujet rpm signé, digest de la fermeture dans `resolvedDependencies` |
| M5 | Tests négatifs : rpm de fermeture altéré, sortie réseau pendant le build, pod privilégié hors Kata ; un rejeu de zéro | Refus attendus, témoins acceptés |

## Prédictions (05/11/2026, 22:21 UTC, avant toute exécution)

| # | Prédiction | Confiance |
|---|---|---|
| 1 | M3 donne deux rpm identiques avec les macros d'OBS, sans autre réglage | Moyenne : OBS y arrive, mais avec un autre chemin d'installation du buildroot |
| 2 | Le rpm diffère de celui d'OBS (`57343ca6…`) | Haute : OBS écrit `DISTURL` (srcmd5 de ses sources), ce que mock ne fait pas de lui-même |
| 3 | `nspawn` échoue dans le pod Kata, `simple` passe | Faible : non documenté, à mesurer en M1 |
| 4 | Podman imbriqué est le premier point de blocage, car le mode hermétique dépend de l'image de bootstrap | Moyenne |
| 5 | Build hors ligne en moins de 5 min (rpm d'OBS : 51 s de build) | Moyenne |
| 6 | Fermeture de moins de 1,5 Go | Faible : aucune mesure, ordre de grandeur |
| 7 | `isBuildArtifact: true` suffit à Chains pour un sujet rpm | Faible : déduit du code, jamais testé |
| 8 | L'effort reste sous 2,5 pw grâce aux acquis de la 08 et de la 03 | Moyenne : le point 4 peut l'invalider |

## Limites connues

- **Hors du seuil** : scan et licences du rpm (07a, 13a), signature OpenPGP (09), replay dans le domaine séparé (10). `tools/index` et la porte devront connaître les sujets non-image ; ce travail n'est pas chiffré ici.
- **Root de l'invité** : comme mesuré en 03 F3, un volume `readOnly` peut être remonté en écriture depuis un pod Kata privilégié. L'intégrité des entrées repose sur les empreintes.
- **Rocky 9.7 figé** : choix de reproductibilité du PoC, pas une recommandation pour la plateforme finale.
