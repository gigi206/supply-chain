# Brique 05, M4c : prédictions de `prealables` (18/11/2026, écrites à 14:01:29 UTC, avant tout lancement)

Script : [`../m4c.sh`](../m4c.sh) (`e0c62169…`), préparé à sec sous l'accord permanent du 18/11. Gabarits : [`preparer-rpm.yaml`](../construction/preparer-rpm.yaml) (`a7dfa37e…`), [`construire-rpm.yaml`](../construction/construire-rpm.yaml) (`4b3bc493…`), [`sample-app-rpm.yaml`](../construction/sample-app-rpm.yaml) (`a9917a65…`). Décisions : « rpm seul », « option (i) » ([carte](m4c-carte.md)). Rien n'est lancé.

**Ce que fait `prealables`** : hôte seul, hors ligne, sans cluster ni Zot ; rien n'est écrit hors de `$W/m4c-05` et du journal. Les copies locales lues sont la fermeture rpm tirée par l'étape `comparaison` de M4b, la fermeture applicative tirée en S4b de la 06, le spec et le verrou du dépôt (égaux à l'artefact de M4a par V4), l'archive de `sources.sh` et le rpm de M3.

**Choix d'écriture des gabarits, à relire avant signature**
- `preparer-rpm` reprend tels quels les pas `sources` et `assemblage` de `preparer-deb` (sauf la fin de l'assemblage : copie du spec et du verrou). Le pas `entrees` tire les trois artefacts et contrôle seulement leur forme : spec et verrou présents, deux fichiers dans l'artefact de packaging, `depot/repodata` présent, rien d'autre que `depot/` à la racine de la fermeture.
- `construire-rpm` : pas root, privilégié, `--isolation=simple`, 2 CPU et 6 Gi ; outils de l'image contrôlés ; écriture refusée sur les entrées ; témoins réseau ; fermeture recopiée dans `/w`, puis confrontée au verrou par une section Python (`rpm -qp --qf %{SIGMD5}` par rpm) ; Source0 par la commande tar de `sources.sh`, à l'époque passée par la pipeline ; mock ; un src.rpm et un rpm binaire exigés, leurs sha256 et NEVRA imprimés ; paquets du buildroot imprimés ; layout OCI du rpm binaire seul.
- La pipeline passe l'époque `1793229566` en chaîne à `construire`, et fixe par digest les trois entrées de `preparer`.
- **L'hôte n'a pas `rpm`** : la confrontation y tourne avec un `rpm` simulé, qui lit le MD5 de l'en-tête de signature (étiquette 1004) en Python. Le vrai `rpm -qp` n'est joué que dans le pod d'essai.

**Prédictions**

| | Prédiction | Confiance |
|---|---|---|
| PR1 | Références épinglées tenues : verrou `b6d0f8f1…`, spec `918a83f5…`, `publier-image` `d21931f3…` dans la liste revue, époque égale à la date du dernier commit de `poc/sample-app` (1793229566), arbre `30e808ff…`, archive `07521c1e…`, rpm de M3 `864d55f4…`, 230 fichiers sous `depot/` de la fermeture tirée. | haute : valeurs relues dans le dépôt et les journaux avant l'écriture |
| PR2 | Les trois gabarits rendus se lisent ; images, contextes de sécurité, ressources, workspaces, résultats, `env`, `subPath`, entrées par digest, époque et noms des tâches égaux à l'attendu. | haute |
| PR3 | Syntaxe des quatre scripts sans erreur ; pas `sources` égal à celui de `preparer-deb` ; début du pas `assemblage` égal jusqu'à la copie du packaging ; un seul heredoc Python dans `construire`. | haute |
| PR4 | Sur l'hôte : contrôles du pas `entrees` passés ; `entrees/src` égal, en contenu, à l'arbre de l'archive de `sources.sh` ; spec et verrou égaux au dépôt ; premier niveau `fermeture sample-app.spec src verrou-rpm.json`. | haute : mêmes pas et même fermeture applicative qu'en S4d1, où l'égalité a été mesurée |
| PR5 | Sous le busybox de l'image de prefetch, entrées égales à celles des outils de l'hôte, en contenu, modes et types. | moyenne-haute : mesuré pour le deb ; la fin du pas (`cp`, `chmod`, `sha256sum`, `cut`) est neuve sous busybox |
| PR6 | Confrontation sur la fermeture tirée : sortie `sc-stockage.poc.test@sha256:f0ccf105… 18d64b03…`, message « 222 rpm (noms et sigmd5) … repodata 4 fichiers, dossier dir: 4 fichiers, aucun autre objet ». | moyenne : le `rpm` simulé est neuf ; les `sigmd5` du verrou viennent du vrai `rpm` (mock, `verrou_derivee`) ; si la lecture de l'étiquette 1004 est fausse, l'écart tombe ici et non dans la plateforme |
| PR7 | Onze cas altérés refusés, chacun avec son motif : rpm retiré, rpm en trop, fichier hors des dossiers admis, sous-dossier, lien symbolique, rpm remplacé, `sigmd5` altéré, `manifest.json` altéré, `repomd.xml` absent, nom en double, verrou vide. | moyenne-haute |
| PR8 | Source0 faite par la section du pas, avec le `tar` et le `gzip` de l'hôte, égale à `07521c1e…` ; spec livré égal au dépôt. | moyenne-haute : même commande, même époque et même arbre que l'orig du deb, mesuré égal en S4d1 ; les versions de `tar` et `gzip` qui ont fait `07521c1e…` ne sont pas relevées |
| PR9 | Layout écrit avec le rpm de M3 : lu comme `publier-image` (une ligne, égale au résultat), blobs nommés par leur sha256, `diff_ids` égaux aux couches, couche = le rpm seul en 0644, propriétaire 0, rpm de la couche égal à `864d55f4…`. Digest attendu relevé, non prédit. | haute : section reprise de `construire-deb`, mesurée en S4d1 |
| PR10 | Code 0, en moins de deux minutes. | haute pour le code si PR1 à PR9 tiennent ; moyenne pour la durée (deux `go mod vendor` hors ligne) |

**Non couvert par `prealables`** : le vrai `rpm`, le `tar` 1.34 et le `gzip` 1.12 de Rocky, mock dans un pas de Tekton, les pulls par `oras` de l'image d'outils, le réseau et l'admission. Ce sera aux pods d'essai.

## Note datée du 18/11/2026, écrite à 14:02:40 UTC : `prealables` passée (accord permanent du 18/11)

**Passage** ([journal](m4c-prealables.log)) : le 18/11/2026, `date -u` avant et après le lancement : 14:01:46 et 14:01:57 UTC ; code 0, 62 OK, aucun KO. Premier plan, sur `bb428e6`.

**Confrontation aux prédictions**
- **PR1 tenue** : références épinglées relues ; 230 fichiers sous `depot/` de la fermeture tirée, rien d'autre à la racine.
- **PR2 tenue** : les trois gabarits rendus se lisent, champs égaux à l'attendu.
- **PR3 tenue** : syntaxe sans erreur ; pas `sources` égal à celui de `preparer-deb` ; début de l'assemblage égal sur 31 lignes ; un seul heredoc Python.
- **PR4 tenue** : contrôles du pas `entrees` passés ; `entrees/src` (41 fichiers ; `vendor/` reconstitué, 17 fichiers ; `marked` 16.4.1, 12 membres extraits) égal en contenu à l'arbre de l'archive de `sources.sh` ; spec et verrou égaux au dépôt.
- **PR5 tenue** : sous le busybox de l'image de prefetch, mêmes entrées en contenu, modes et types.
- **PR6 tenue** : la confrontation, avec le `rpm` simulé, trouve les 222 `sigmd5` égaux au verrou, l'image de bootstrap, 4 fichiers de `repodata` et 4 du dossier `dir:`. Les `sigmd5` du verrou venant du vrai `rpm`, l'égalité sur 222 rpm vaut aussi contrôle de la lecture de l'étiquette 1004 (déduit).
- **PR7 tenue** : onze cas altérés refusés, chacun avec son motif.
- **PR8 tenue** : Source0 faite par la section du pas, avec le `tar` 1.35 et le `gzip` 1.14 de l'hôte, égale à `07521c1e…`. L'option (i) reproduit donc l'archive de M3 sur l'hôte. Avec le `tar` 1.34 et le `gzip` 1.12 de Rocky : à mesurer dans le pod d'essai.
- **PR9 tenue** : layout lu comme `publier-image`, couche = le rpm seul, rpm égal à `864d55f4…`. **Digest attendu** de l'artefact, si le rpm de la plateforme est celui de M3 et si le `tar` de l'image d'outillage écrit la même couche : `sha256:7b17e7e7…` (relevé).
- **PR10 tenue** : code 0, en 11 s d'après les deux `date -u`.

**Portée.** Tout a tourné sur l'hôte. Rien ne dit encore que le vrai `rpm`, le `tar` et le `gzip` de Rocky, mock dans un pas de Tekton, les pulls par `oras`, le réseau ou l'admission se comportent de même : c'est le rôle des pods d'essai. `entrees.tar` (318 842 880 octets, `1334e4a4…`) est prêt pour le pod d'essai de `construire-rpm`.

**Suite** : préparer à sec `essai_preparer` et `essai`, sur le modèle de `s4d.sh`, avec leurs prédictions.

## Note datée du 18/11/2026, écrite à 14:10:35 UTC : `essai_preparer` et `essai` préparées à sec (accord permanent du 18/11), NON LANCÉES ; `prealables` à rejouer

**Avis du conseiller** (après `prealables`) : rien de bloquant. Il demande :
- de garder lisibles les journaux de mock en cas d'échec ;
- de donner au pod d'essai Kata la forme que Tekton produira ;
- de comparer la Source0 en relevé, pas en KO.

**Changements**
- **`construire-rpm.yaml`** (`e88f5521…`) : en cas d'échec de mock, la fin de `mock.out`, `root.log` et `build.log` va au journal. Le reste du script est inchangé. `preparer-rpm.yaml` reste à `a7dfa37e…`.
- **`m4c.sh`** (`08b29ab5…`) : deux étapes ajoutées par insertion, `essai_preparer` et `essai`, sur le modèle de `s4d.sh`.
- **`prealables` sera rejouée** sur le gabarit corrigé avant les essais. Prédiction : PR1 à PR10 tenues de nouveau, 62 OK, même digest attendu `7b17e7e7…`. Le sha256 de `entrees.tar` n'est pas prédit : les dates des fichiers changent d'un passage à l'autre.

**`essai_preparer`** (cluster, pod d'essai, rien dans Zot)
- Pod runc restreint, au label `preparer-rpm`, avec les trois pas en initContainers : images, scripts rendus, montages et contexte de la tâche.
- Le clone de Forgejo et les pulls dans Zot sont réels.
- Les résultats sont lus, et l'arbre `entrees/` est comparé à celui de `prealables`.
- Les politiques de `builds` sont relues avant. Le pod est supprimé à la fin.

| | Prédiction | Confiance |
|---|---|---|
| EP1 | `construction-rpm-sans-sortie` relue telle que posée en M3 ; aucune politique de `builds` n'autorise de trafic à `construire-rpm`. Relevé : politiques qui sélectionnent `preparer-rpm`. | haute : mesuré en M3 ; l'état actuel n'est pas relu avant l'essai |
| EP2 | Pod admis en dry-run serveur, puis `Succeeded`. | haute pour l'admission (forme de `preparer-deb`) ; moyenne-haute pour le passage |
| EP3 | Pas `sources` : clone de Forgejo, commit `6391fd43…`, arbre `30e808ff…`. Pas `entrees` : trois pulls par l'`oras` de l'image d'outils, dont les chemins à « : » et « @ » du dossier `dir:`, et quatre contrôles passés sous son busybox. Pas `assemblage` : `vendor/` et `marked` comme sur l'hôte. | moyenne-haute : `publier-fermeture` a poussé ces chemins avec la même image ; le pull dans un pod n'est pas mesuré ; aucune politique ne nomme `preparer-deb`, qui a joint Forgejo et Zot (lecture) |
| EP4 | Résultats `CHAINS-GIT_URL`, `CHAINS-GIT_COMMIT` et les trois `*_ARTIFACT_INPUTS` égaux à l'attendu. | haute |
| EP5 | Arbre `entrees/` du pod égal à celui de `prealables`, en contenu, modes et types (273 fichiers : 230 de la fermeture, 41 sous `src`, le spec et le verrou). | moyenne-haute : mesuré pour le deb en S4d1 ; ici, les 230 fichiers de la fermeture viennent de l'`oras` de l'hôte d'un côté, de celui de l'image de l'autre |

**`essai`** (cluster, pod d'essai, rien dans Zot)
- Pod Kata au label `construire-rpm`. Le contexte du `podTemplate` (UID 65532, `runAsNonRoot`) est posé au niveau du pod, le pas root privilégié du gabarit au niveau du conteneur.
- `entrees.tar` est copié par morceaux de 64 Mio dans un volume à part, et déballé par un second conteneur en UID 65532. Ce volume est monté en lecture seule pour mock.
- Le script du gabarit est joué tel quel ; seules les trois lignes à variables de Tekton sont substituées.
- Les politiques sont relues avant. Le pod est supprimé à la fin.

| | Prédiction | Confiance |
|---|---|---|
| ES1 | Politiques relues comme EP1. | haute |
| ES2 | Pod admis en dry-run serveur, puis prêt sous `kata` sur sc-build. | moyenne : un pod root au niveau du pod a été admis en M3 ; la surcharge par le conteneur d'un `runAsNonRoot` posé au niveau du pod n'a jamais été soumise à l'admission |
| ES3 | Copie de `entrees.tar` en 5 morceaux, sha256 conforme ; 273 fichiers déballés par l'UID 65532. | haute |
| ES4 | Outils de l'image présents ; ligne « invité » atteinte, donc écriture refusée sur les entrées (montage relevé). | moyenne-haute : la lecture seule d'un `emptyDir` monté `readOnly` sous Kata n'est pas mesurée ; celle du PVC sous `subPath` l'a été pour le deb dans la pipeline (lecture) |
| ES5 | Les quatre témoins réseau échouent. | haute : M3, même politique |
| ES6 | Confrontation avec le vrai `rpm` : même sortie et même message que dans `prealables`. | haute, étant donné PR6 |
| ES7 | **Discriminant** : Source0, faite par le `tar` 1.34 et le `gzip` 1.12 de Rocky, égale à `07521c1e…`. Comparée en relevé : mock tourne quand même. | moyenne-haute : même commande, même époque, même arbre (PR8) ; les sorties de ces versions n'ont jamais été comparées |
| ES8 | mock `--hermetic-build` en code 0 ; « Using container image: dir: » et « Checking image digest: 18d64b03… » une fois chacune dans la sortie et dans `root.log` ; aucun repli, ni « Expected digest », ni « No space » ; aucune ligne `http(s)://` dans les trois journaux ; 222 paquets au buildroot, aucun écart au verrou. | moyenne-haute : mesuré en M3 et en `m4b_mock_v2`, mais par `kubectl exec` dans un pod root au niveau du pod ; le contexte de Tekton n'y est pas |
| ES9 | **Si ES7 tient** : src.rpm égal à `c802e60a…`, rpm égal à `864d55f4…`, digest de l'artefact égal à `7b17e7e7…`. **Si ES7 ne tient pas** : rien n'est prédit pour le rpm. | moyenne-haute si ES7 tient : même verrou, mêmes `repodata` V2, même image que `m4b_mock_v2` (MV tenues) ; la couche est écrite par le `tar` de Rocky, pas par celui de l'hôte |
| ES10 | Code 0 et 0 écart, en moins de 15 minutes. | moyenne |

**Si ES7 ne tient pas** (Source0 différente) : l'option (i) supposait M3 comme référence. La suite revient au propriétaire. Je n'applique aucun correctif de mon chef (avis du conseiller).
**Si ES2 ne tient pas** (refus d'admission) : la cause est relevée sans lire les messages des Events. La suite est une décision.

**Non couvert par les essais** : le PVC sous `subPath` et Kata, l'`env` et le `HOME` posés par Tekton, l'image d'entrée de Tekton et ses scripts, `publier-image`, Chains. Ce sera à `pipeline`.

## Note datée du 18/11/2026, écrite à 14:12:04 UTC : `prealables` rejouée sur le gabarit corrigé ; un échec de nettoyage, corrigé

- **Second passage, 14:10:48 UTC, code 1** ([journal](m4c-prealables-passage2.log)) : arrêt dès le nettoyage. Le retrait récursif du dossier de travail n'a pas pu enlever le cache de modules de go laissé par le premier passage, que go extrait en lecture seule (170 lignes « Permission denied »). Aucun contrôle n'a tourné. C'est un défaut de `m4c.sh` au second passage, non prédit, que le premier passage ne pouvait pas montrer.
- **Correction** : les droits d'écriture sont rendus avant le retrait (`chmod -R u+w`, comme le piège de `sources.sh`). `m4c.sh` passe de `08b29ab5…` à `b5a7f79d…`, par cette seule insertion de trois lignes ; les gabarits ne changent pas.
- **Troisième passage, 14:11:15 à 14:11:26 UTC, code 0, 62 OK** ([journal](m4c-prealables.log)) : journal identique ligne pour ligne au premier ([journal du premier passage](m4c-prealables-passage1.log)), sauf l'en-tête et la ligne de `entrees.tar` (nouveau sha256 `b84f68ee…`, même taille, 318 842 880 octets). La prédiction de rejeu tient : PR1 à PR10, digest attendu `7b17e7e7…`.

## Note datée du 18/11/2026, écrite à 14:13:18 UTC : `essai_preparer` passée (accord permanent du 18/11)

**Passage** ([journal](m4c-essai_preparer.log), [journaux du pod](m4c-essai-preparer-pod.log)) : le 18/11/2026, `date -u` avant et après le lancement : 14:12:26 et 14:12:35 UTC ; code 0, 14 OK, aucun KO. Sur `80592ce`, `m4c.sh` = `b5a7f79d…`.

**Confrontation aux prédictions**
- **EP1 tenue** : `construction-rpm-sans-sortie` telle que posée en M3 ; aucune politique de `builds` n'autorise de trafic à `construire-rpm`. Relevé : seule `builds-sans-internet` (CiliumNetworkPolicy) sélectionne `preparer-rpm`. Le libellé du relevé répète « CiliumNetworkPolicy », défaut d'affichage sans effet.
- **EP2 tenue** : admis en dry-run serveur ; créé à 14:12:26, vu `Succeeded` à 14:12:34 (relevé toutes les 2 s), sur sc-build, sans `runtimeClassName` (runc).
- **EP3 tenue** : clone de Forgejo (git 2.51.2, commit `6391fd43…`, arbre `30e808ff…`) ; trois pulls par l'`oras` de l'image d'outils, dont le dossier `dir:` (230 fichiers de la fermeture, 8 de la fermeture applicative, 2 du packaging) ; contrôles du pas `entrees` passés sous son busybox ; assemblage égal à l'hôte. Sous `builds-sans-internet`, sans politique dédiée, Forgejo et Zot ont été joints (mesuré).
- **EP4 tenue** : les cinq résultats égaux à l'attendu.
- **EP5 tenue** : arbre `entrees/` du pod égal à celui de `prealables`, 273 fichiers, en contenu, modes et types.

**Portée.** Le pod d'essai rejoue les pas, leurs images, leurs montages et leur contexte, sur des `emptyDir`. Le PVC sous `subPath`, l'image d'entrée de Tekton et l'ordre des pas tenu par Tekton ne sont pas couverts : ce sera à `pipeline`.

## Note datée du 18/11/2026, écrite à 14:16:37 UTC : `essai` passée, code 1 sur un seul écart ; rpm et src.rpm égaux à M3

**Passage** ([journal](m4c-essai.log), [journal du script](m4c-essai-construire.log), [comparaison des couches](m4c-essai-couches.log)) : le 18/11/2026, `date -u` avant et après le lancement : 14:12:44 et 14:15:23 UTC. Arrière-plan, sur `2779a90`, `m4c.sh` = `b5a7f79d…`. Code 1, voulu par l'étape dès qu'un écart est compté : 1 écart, aucun KO. Le script de `construire-rpm` a tourné de 14:13:37 à 14:15:22 UTC, code 0. `chrono.tsv` n'a pas de ligne « fait » pour cette étape, car `lancer` s'arrête sur le code 1.

**Confrontation aux prédictions**
- **ES1 tenue** : politiques relues comme en EP1.
- **ES2 tenue** : admis en dry-run serveur, prêt sous `kata` sur sc-build. Le contexte du `podTemplate` au niveau du pod et le pas root privilégié au niveau du conteneur sont admis ensemble.
- **ES3 tenue** : 318 842 880 octets en 5 morceaux, sha256 conforme ; 273 fichiers déballés par l'UID 65532.
- **ES4 tenue** : outils présents ; écriture refusée sur les entrées, montées en `virtiofs ro,relatime` sous Kata. Invité : 4 vCPU, 7 151 664 kB, uid 0.
- **ES5 tenue** : les quatre témoins échouent, code 124 (délai).
- **ES6 tenue** : confrontation avec le vrai `rpm`, même message que dans `prealables`.
- **ES7 tenue** : Source0 faite par le `tar` 1.34 et le `gzip` 1.12 de Rocky, égale à `07521c1e…`.
- **ES8 tenue** : mock en code 0 en 54 s ; « Using container image: dir: » et « Checking image digest: 18d64b03… » une fois chacune, dans la sortie et dans `root.log` ; ni repli, ni « Expected digest », ni « No space » ; aucune ligne `http(s)://` ; 222 paquets au buildroot, aucun écart au verrou.
- **ES9 en partie non tenue** :
  - le src.rpm est égal à `c802e60a…` et le rpm à `864d55f4…`, ceux de M3 ;
  - le digest de l'artefact est `sha256:07b7bd6f…`, non `7b17e7e7…`.
  - Cause mesurée : la couche fait la même taille (2 181 120 octets) et porte le même rpm. 17 octets de l'en-tête ustar diffèrent : le `tar` 1.34 de l'image écrit « 0000000 » dans `devmajor` et `devminor`, là où le `tar` 1.35 de l'hôte laisse des octets nuls, et la somme de l'en-tête suit.
  - La prédiction l'avait signalé comme risque : la couche est écrite par le `tar` de Rocky, pas par celui de l'hôte. Le digest attendu de `prealables` ne valait que pour un `tar` de l'hôte.
- **ES10 non tenue** sur le code : 1 écart, l'ES9 ci-dessus. Durée tenue : 2 min 39 s entre les deux `date -u`.

**Conséquences**
- Le rpm de la plateforme, dans le pod d'essai, est celui de M3 à l'octet près. L'option (i) tient donc sa promesse : M3 reste la référence.
- **Référence de l'artefact pour `pipeline`** : `sha256:07b7bd6f…`, digest produit par le `tar` de l'image d'outillage, celui de la tâche signée. Celui de `prealables` (`7b17e7e7…`) est consigné comme propre à l'hôte. Ce n'est pas une décision : le contenu est le même rpm, et la pipeline comparera ses deux exécutions entre elles puis à l'essai.
- Aucune correction du gabarit n'est demandée par cet essai. `construire-rpm.yaml` (`e88f5521…`) et `preparer-rpm.yaml` sont prêts pour la signature (étape `taches`, à préparer), puis pour la revue de `taches.yml`.

**Non couvert** : le PVC sous `subPath` et Kata, l'`env` et le `HOME` de Tekton, `publier-image`, Chains, la provenance.

## Note datée du 18/11/2026, écrite à 14:51:48 UTC : étape `taches` préparée à sec et appliquée (accord permanent du 18/11), NON LANCÉE ; prédictions TS0 à TS10 et TP1 à TP4

**Modèle** : l'étape `taches` de M4b (contenu signé relu avant tout versionnement), étendue à deux tâches. Les deux sont signées et relues **avant** que l'une soit versionnée ou poussée. `signer_tache` de la 06 n'est pas repris : il poussait la première tâche avant d'avoir relu la seconde.

**Ce que fait l'étape**
1. Clé des tâches présente (`test -s`) ; `publier-image` lue dans la liste revue, égale à `d21931f3…` ; les trois gabarits égaux, à l'octet près, à ceux des essais (`construction/` à `f66229a`, inchangé depuis).
2. Tâches et pipeline rendues (références factices dans la pipeline), admises en dry-run serveur ; témoin `computeResources` dans un pas v1beta1, refusé avec le message mesuré en M4b.
3. `tkn task sign` des deux tâches, puis relecture de chacune, normalisée :
   - égale à la tâche rendue, signature exceptée ;
   - `preparer-rpm` : images, `stepTemplate` (UID 65532, `runAsNonRoot`, capacités retirées, sans élévation), aucun contexte ni ressource au niveau des pas, env, paramètres, résultats, volumes ;
   - `construire-rpm` : image, contexte root privilégié du pas, aucun `stepTemplate`, ressources 2 CPU et 6 Gi, aucun `computeResources`, env, workspace d'entrées en lecture seule, volume mémoire de 4Gi ;
   - les quatre scripts, substitués par les expressions des essais, égaux à ceux joués dans les pods d'essai. Ceux-ci sont archivés sous [m4c-essai-scripts](m4c-essai-scripts/) (construire-rpm-construire.sh, preparer-rpm-assemblage.sh, preparer-rpm-entrees.sh, preparer-rpm-sources.sh), relevés dans `$T` (dates de 14:12:26 et 14:12:44 UTC).
4. Garde : au moins 1 Gio libre sur `/` de sc-stockage, relevé imprimé ; puis versionnement sous `construction/<tâche>.signee.yaml` (une nouvelle signature seulement si le contenu hors signature change) ; puis bundles sous le tag `m4c`, et `listee` de `commun.sh`.
5. Sous `SIGNER=1`, arrêt tant que la liste revue ne porte pas les deux tâches. Sinon : pipeline rendue avec les références réelles, admise, signée, relue ; bundle ; référence écrite dans `$T/sample-app-rpm.ref`.

**Préparation**
- `m4c.sh` passe de `b5a7f79d…` à `d2d895d9…` par deux insertions (5 lignes d'en-tête, 131 lignes avant `lancer`), appliquées à 14:49:53 UTC (`date -u` de la commande de copie).
- Banc [m4c-taches-banc.sh](m4c-taches-banc.sh) (`4bcebebf…`), avec le vrai `tkn` 0.46.2, une clé P-256 jetable et le vrai `commun.sh` (dossier de confiance du banc) ; faux `kubectl`, `bundle`, `listee`, `auth_zot` et `sur`. **89 OK** sur la copie ([journal](m4c-taches-banc.log)), puis **89 OK** sur le dépôt ([journal](m4c-taches-banc-applique.log)).
- Cas du banc : première passe et rejeu sans nouvelle signature ; refus si une seule tâche, ou aucune, est listée ; pipeline signée si les deux le sont ; refus, sans versionnement ni poussée d'aucune des deux tâches, sur un gabarit modifié, un script altéré, le contexte du pas de `construire-rpm` ou le `stepTemplate` de `preparer-rpm` altérés, un témoin admis, une tâche refusée à l'admission, un disque bas ou illisible.
- **Mesuré au banc**, quatre passages ([1](m4c-taches-banc-passage1.log), [2](m4c-taches-banc-passage2.log), [3](m4c-taches-banc-passage3.log), [4](m4c-taches-banc-passage4.log)) : `tkn` 0.46.2 réécrit l'objet qu'il signe.
  - Il réordonne les clés et ajoute `resources: {}` au `stepTemplate` et aux pas sans ressources, `annotations: {}`, et `description: ""` aux paramètres de la pipeline.
  - La comparaison au rendu se fait donc après normalisation (fonction `normaliser`). Le passage 1 refusait toute signature, le passage 2 la pipeline seule. Les passages 3 et 4 ont corrigé le compte des lignes OK, puis un avertissement de `yq`.

**Relevés de Zot, hors étape**, archivés à part comme en M4b, avant et après chaque passe : tags et digests de `tekton/tasks/preparer-rpm`, `tekton/tasks/construire-rpm` et `tekton/pipelines/sample-app-rpm`, nombre de dépôts du catalogue (N au relevé avant), `df` de `/` sur sc-stockage.

**Prédictions de `SIGNER=1 taches`**

| # | Prédiction | Confiance |
|---|---|---|
| TS0 | Relevé avant : les trois dépôts absents (`NAME_UNKNOWN`) | Haute : aucune étape n'y a écrit (journaux de la brique) |
| TS1 | `publier-image` de la liste = `d21931f3…` complet ; trois gabarits égaux à ceux des essais | Haute |
| TS2 | Les trois objets rendus admis (code 0) ; témoin refusé avec le message de M4b | Moyenne : premier dry-run serveur de ces objets. Les essais ont admis des pods, jamais une Task v1beta1 avec `volumes`, un workspace `readOnly` et des résultats objets |
| TS3 | Relecture des deux tâches signées tenue, dont les quatre scripts égaux aux sha256 des essais | Haute : banc avec le vrai `tkn` sur les mêmes gabarits ; seule la clé diffère, et elle ne touche que l'annotation |
| TS4 | Octets libres sur `/` de sc-stockage entre 1 Gio et 4,5 Go ; garde passée | Moyenne : 4 495 519 744 octets libres à 09:57 UTC, et `/` grossit sans écriture de la brique, à un rythme non constant |
| TS5 | Deux « SIGNER : nouvelle signature » ; `construction/preparer-rpm.signee.yaml` et `construction/construire-rpm.signee.yaml` écrites, conformes | Haute : fichiers absents du dépôt |
| TS6 | Bundles `tekton/tasks/preparer-rpm:m4c` puis `tekton/tasks/construire-rpm:m4c` poussés ; deux « à ajouter à politique/porte/taches.yml » avec leurs références ; « pipeline non signée » ; code 0 ; 31 lignes OK. Aucun digest parié : la signature ECDSA change à chaque signature | Haute (banc) |
| TS7 | `$T/auth` absent après la passe (`test -e`, sans lister) | Haute (banc) |
| TS8 | Rien dans le cluster : aucune tâche ni pipeline créée dans `builds` (dry-run seulement) | Haute |
| TS9 | Relevé après : deux dépôts de tâches, chacun avec le seul tag `m4c` au digest affiché ; pipeline toujours absente ; catalogue de N + 2 | Moyenne : forme de M4b (TS8 de M4b tenue) |
| TS10 | Durée sous 60 s | Moyenne : le banc entier a pris 17 et 18 s (journaux), sans Zot ni API |

**Prédictions de la seconde passe** (`taches` sans `SIGNER`, après la revue et le commit de `taches.yml` par le propriétaire)

| # | Prédiction | Confiance |
|---|---|---|
| TP1 | Les deux tâches dans la liste revue ; pas de nouvelle signature ; mêmes digests de bundle qu'en `SIGNER=1` | Haute : TP1 de M4b tenue sur la même forme |
| TP2 | Pipeline rendue avec les trois références, admise, signée, relue (normalisée) ; bundle `tekton/pipelines/sample-app-rpm:m4c` ; code 0 ; 41 lignes OK | Haute (banc) |
| TP3 | Référence de la pipeline dans `$T/sample-app-rpm.ref` | Haute (banc) |
| TP4 | Relevé après : dépôt de la pipeline créé avec le seul tag `m4c` ; tags des tâches inchangés ; catalogue de N + 3 | Moyenne |

**Points pour la revue de `taches.yml`** (lecture, non mesuré)
- `construire-rpm` tourne en root privilégié sous Kata, comme `construire-image` et `construire-builder`, déjà dans la liste revue.
- **La porte ne connaît pas encore `construire-rpm`** : `porte.rego` ne la nomme ni dans `_constructions` (règle `construction_kata`) ni dans `_appariement` (préparation exigée). Une fois le digest listé, la porte accepterait une provenance qui la contient sans exiger Kata ni `preparer-rpm`. C'était le cas de `construire-deb` avant S4d2a. Étendre la porte est un choix du propriétaire ; rien n'est fait ici.
- Comme en M4b, le bundle signé est résoluble par Tekton (Trusted Resources vérifie la clé, pas la liste) entre `SIGNER=1` et la revue.

**Ce que chaque issue permet**
- TS tenues : revue de `taches.yml` par le propriétaire, dans un commit à part. C'est un arrêt.
- TS2 non tenue : rien n'est signé. L'objet refusé est corrigé, puis le banc est rejoué.
- TS3 non tenue : rien n'est versionné ni poussé. Le gabarit ou le contrôle est corrigé, puis le banc est rejoué.
- TS4 non tenue (garde) : rien n'est versionné ni poussé. Décision sur le disque de sc-stockage.
- TS9 non tenue : écart relevé avant la revue, à expliquer avant toute autre écriture.

## Note datée du 18/11/2026, écrite à 14:53:18 UTC : `SIGNER=1 taches` passée, TS0 à TS10 tenues ; revue de `taches.yml` à demander

**Passage** ([journal](m4c-taches-signer.log)) : le 18/11/2026, `date -u` avant et après le lancement : 14:52:19 et 14:52:23 UTC, code 0, 31 OK, aucun KO. Sur `be3fa84`, `m4c.sh` = `d2d895d9…`. Relevés de Zot ([avant](m4c-taches-zot-avant.log), à 14:52:11 UTC ; [après](m4c-taches-zot-apres.log), à 14:52:31 UTC).

**Confrontation aux prédictions**
- **TS0 tenue** : les trois dépôts en `NAME_UNKNOWN` ; catalogue de 148 dépôts (N = 148).
- **TS1 tenue** : `publier-image` lue dans la liste, égale à `d21931f3…` ; trois gabarits égaux à ceux des essais.
- **TS2 tenue** : `preparer-rpm`, `construire-rpm` et `sample-app-rpm` rendues admises en dry-run serveur (code 0) ; témoin refusé avec le message de M4b.
- **TS3 tenue** : les deux tâches signées relues, normalisées, égales au rendu ; champs de sécurité conformes ; quatre scripts égaux aux sha256 des essais.
- **TS4 tenue** : 4 420 063 232 octets libres sur `/` de sc-stockage avant les poussées.
- **TS5 tenue** : deux nouvelles signatures, conformes :
  - `construction/preparer-rpm.signee.yaml` = `b32d073f…` ;
  - `construction/construire-rpm.signee.yaml` = `faab95fd…`.
- **TS6 tenue** : deux bundles poussés sous le tag `m4c`, deux lignes « à ajouter », « pipeline non signée », code 0, 31 OK. Références :
  - `sc-stockage.poc.test:5000/tekton/tasks/preparer-rpm@sha256:2f65f3903e98caa9944ab3fee4b67585b15d67ad477ff48a8487e8e86af5526f` ;
  - `sc-stockage.poc.test:5000/tekton/tasks/construire-rpm@sha256:d7f01398f188931c124273c8b5fb60e2a66c22e9d0a2dfcd229ecadee1e62164`.
- **TS7 tenue** : `$T/auth` absent après la passe (`test -e`).
- **TS8 tenue** : `kubectl get tasks.tekton.dev,pipelines.tekton.dev -n builds -o name` ne rend aucune ligne (14:52 UTC, non archivé).
- **TS9 tenue** : chaque dépôt de tâche porte le seul tag `m4c`, au digest affiché par l'étape ; pipeline toujours en `NAME_UNKNOWN` ; catalogue de 150 dépôts (N + 2). `df` : +749 568 octets utilisés entre les deux relevés.
- **TS10 tenue** : 4 s entre les deux `date -u`.

**Suite** : revue de `taches.yml` par le propriétaire, pour les deux références ci-dessus, dans un commit à part. C'est un arrêt. La seconde passe (TP1 à TP4) attend ce commit.

## Note datée du 18/11/2026, écrite à 15:16:54 UTC : liste revue acceptée, seconde passe de `taches` passée, TP1 à TP4 tenues

**Revue** : le propriétaire a répondu « Oui » aux deux entrées proposées (réponse lue avant 15:16:02 UTC). Elles sont ajoutées telles quelles à `politique/porte/taches.yml` de la 08, dans le commit à part `1d5e27d`.

**Passage** ([journal](m4c-taches.log)) : le 18/11/2026, `date -u` avant et après le lancement : 15:16:19 et 15:16:23 UTC, code 0, 41 OK, aucun KO. Sur `1d5e27d`, `m4c.sh` = `d2d895d9…`, sans `SIGNER`. Relevés de Zot ([avant](m4c-taches-pipeline-zot-avant.log), à 15:16:19 UTC ; [après](m4c-taches-pipeline-zot-apres.log), à 15:16:29 UTC).

**Confrontation aux prédictions**
- **TP1 tenue** : les deux tâches dans la liste revue, aucune nouvelle signature, mêmes digests de bundle qu'en `SIGNER=1` (`2f65f390…`, `d7f01398…`).
- **TP2 tenue** : pipeline rendue avec les trois références, admise, signée, égale au rendu après normalisation ; bundle `tekton/pipelines/sample-app-rpm:m4c` ; code 0 ; 41 OK.
- **TP3 tenue** : `$T/sample-app-rpm.ref` = `sc-stockage.poc.test:5000/tekton/pipelines/sample-app-rpm@sha256:ca87437546266359925ff5cf2895f6c9ddeca7114a5634680ebbb0bb325f06be`. `$T/auth` absent après la passe.
- **TP4 tenue** : dépôt de la pipeline créé avec le seul tag `m4c`, au digest affiché ; tags des tâches inchangés ; catalogue de 150 à 151 dépôts.

**Suite** : étape `pipeline` (deux PipelineRuns), à préparer à sec. Points ouverts : PVC sous `subPath` et Kata, `env` et `HOME` de Tekton, lecture par `publier-image` (UID 65532) de ce que root a écrit. La porte ne connaît pas encore `construire-rpm` : choix du propriétaire.

## Note datée du 18/11/2026, écrite à 15:39:14 UTC : étape `pipeline` préparée à sec et appliquée (accord permanent du 18/11), NON LANCÉE ; prédictions PL1 à PL12

**Modèle**
- Déroulé de `etape_rpm` de `m4b.sh` : gardes avant toute création, aucune purge, preuve imprimée avant toute assertion, jamais le message d'une condition.
- Forme du PipelineRun de `s4d.sh` de la 06 : Kata pour la seule tâche `construire`, par `taskRunSpecs` ; podTemplate de M4b, sans `env`.
- Trois lignes de `s4d.sh` ne sont pas reprises : `purger_pr` ; `fin_pr`, qui imprime le message de la condition ; le filtre `grep -viE`, remplacé par le masquage de règle.

**Ce que fait l'étape**
1. **Gardes, avant toute création :**
   - `$T/sample-app-rpm.ref` égal à `PIPELINE_REF` (`ca874375…`), pipeline relue au tag `m4c` en lecture anonyme ;
   - `preparer-rpm`, `construire-rpm` et `publier-image` dans la liste revue (`listee`) ;
   - politiques de builds relues : `construction-rpm-sans-sortie` présente, aucune autre ne laisse passer `construire-rpm` ;
   - pour chaque PipelineRun : dépôt `builds/sample-app-rpm` absent (au premier seulement), aucun PipelineRun du même nom, au moins 1 Gio libre sur `/` de sc-stockage, podTemplate sans `env` et Kata pour `construire` seule, dry-run serveur.
2. **`m4c-rpm-1`, puis `m4c-rpm-2`** : création, attente de 3 600 s au plus, puis relevés :
   - de chaque TaskRun : condition, résultats ;
   - de chaque pod : nœud, `runtimeClassName`, label, états et ressources des conteneurs ;
   - des journaux de chaque pas, masqués. Celui de `construire` est archivé, masqué, sous `resultats/m4c-pipeline-<i>-construire.log`.
3. **Exigé** (`attendu`, arrêt) :
   - PipelineRun `True|Succeeded` ;
   - pour chaque pod : label, nœud `sc-build`, `runtimeClassName` (`kata` pour `construire-rpm` seule) ;
   - résultats de `preparer` : dépôt, commit, trois entrées par digest ;
   - dans le journal de `construire` : écriture refusée sur les entrées, quatre témoins réseau en échec, 222 rpm confrontés au verrou, `mock --hermetic-build` rc 0, aucun repli en chroot, aucune ligne http, dernière ligne atteinte ;
   - `DIGEST_CONSTRUIT` égal au digest publié, ligne de publication de `publier-image`, manifeste relu dans Zot (descripteur, une couche) ;
   - signature de Chains.
4. **Mesuré sans arrêt** (`mesure`, code 1 à la fin en cas d'écart) :
   - Source0, src.rpm et rpm, contre M3 ;
   - digest de l'artefact, contre celui du pod d'essai (`07b7bd6f…`, et non `7b17e7e7…`, celui de `prealables`) ;
   - même artefact aux deux PipelineRuns.

**Préparation**
- `m4c.sh` passe de `d2d895d9…` à `d881b967…` par deux insertions (5 lignes d'en-tête, 144 lignes avant `lancer`), appliquées à 15:36:22 UTC (`date -u` de la commande de copie).
- PVC de 2 Gi, contre 1 Gi en M4b : `entrees/` de `prealables` pèse 318 609 833 octets, et `image.tar` de l'essai 2 191 360.
- Banc [m4c-pipeline-banc.sh](m4c-pipeline-banc.sh) (`b61e5e48…`) :
  - vrais : la fonction de l'étape, le verrou, la liste revue, `listee`, `selecteurs.jq`, et le journal réel du pod d'essai pour `construire` ;
  - faux : `kubectl`, `oras`, `sur`, `signe`, `sleep` ;
  - **81 OK** sur la copie ([journal](m4c-pipeline-banc.log)), puis **81 OK** sur le dépôt ([journal](m4c-pipeline-banc-applique.log)) ;
  - un premier passage donnait 79 OK et 2 KO ([journal](m4c-pipeline-banc-passage1.log)). Deux contrôles du banc coupaient le message attendu (`cut -c`, en octets). Ils ont été corrigés dans le banc ; l'étape n'a pas changé.
- **19 cas** au banc :
  - succès ;
  - écarts mesurés : digest autre que l'essai, digests divergents, rpm autre que M3 ;
  - échecs : `construire`, puis `publier`, preuve imprimée avant le KO ; `construire` sans Kata ; label faux ; témoin réseau absent ; deux couches ;
  - arrêts avant création : PipelineRun déjà présent, dépôt déjà présent, disque bas, pipeline autre au tag `m4c`, référence de `taches` autre, tâche hors de la liste revue, politique de M3 absente ;
  - refus à l'admission ; PipelineRun jamais terminé.

  Dans chaque cas : aucune suppression. Le message de condition, la variable d'environnement et la ligne de jeton sentinelles ne sont jamais affichés ni archivés.
- Non couvert par le banc : Tekton (résolveur, Trusted Resources, pods et montages réels), Kata, Kyverno, Chains, Zot, réseau.

**Relevé avant** ([journal](m4c-pipeline-zot-avant.log), 15:37:47 UTC)
- `builds/sample-app-rpm` en `NAME_UNKNOWN` ; pipeline au seul tag `m4c` (`ca874375…`) ; catalogue de 151 dépôts.
- 4 447 834 112 octets libres sur `/` de sc-stockage.
- 18 PVC dans `builds`, aucun PipelineRun `m4c-rpm-*`.

**Ce qui diffère de l'essai** (lecture, non mesuré)
- **VM plus petite.** Le pod de `construire` n'a qu'un conteneur de pas ; l'essai avait en plus `remplir` (1 CPU, 1 Gi).
  - Sous Tekton, le journal de `construire-deb` (06) donne 3 vCPU et 6 119 664 kB ; l'essai rpm, 4 vCPU et 7 151 664 kB.
  - La capacité de `/w` (tmpfs, moitié de la mémoire) passerait d'environ 3,58 à 3,06 Go. L'essai en utilisait 1,46 Go après mock.
- **Lancement.** Tekton lance le script depuis `/tekton/scripts`, par son shebang, et non par `kubectl exec bash`. Le script n'utilise ni `HOME` ni chemin relatif ; `preparer-rpm` et `publier-image` fixent `HOME=/tmp`.
- **Entrées.** Elles sont écrites par `preparer-rpm` (UID 65532) sur le PVC, et non déballées dans un `emptyDir`. Root les lit sous Kata, via `subPath`, en lecture seule.
- **Première mesure.** `publier-image` (UID 65532, runc) lit `image.tar` que root a écrit sous Kata (umask 022), via virtiofs, dans le sous-dossier `image/`. À l'essai, c'est root qui l'a relu. En 06, `construire-deb` écrivait en UID 1000.

**Prédictions de `pipeline`**

| # | Prédiction | Confiance |
|---|---|---|
| PL1 | Gardes passées : pipeline `ca874375…` au tag `m4c`, trois tâches listées, politiques conformes, dépôt absent, disque au-dessus de la garde, deux dry-runs admis | Haute : relevé avant ; forme de dry-run de s4d (06) |
| PL2 | `m4c-rpm-1` et `m4c-rpm-2` terminés en succès (statut `True`, raison `Succeeded`) ; code 0 | Moyenne : première exécution de ces tâches sous Tekton ; voir PL8 |
| PL3 | `preparer-rpm` et `publier-image` sans `runtimeClassName`, `construire-rpm` sous `kata`, tous sur `sc-build`, labels conformes | Haute : forme de s4d (06) |
| PL4 | Résultats de `preparer` égaux aux références (dépôt, commit, trois entrées) | Haute : essai_preparer |
| PL5 | Journal de `construire` : écriture refusée, quatre témoins en échec, 222 rpm, mock rc 0, aucun repli, aucune ligne http | Haute : essai ; mêmes script, image et entrées |
| PL6 | Source0 `07521c1e…`, src.rpm `c802e60a…` et rpm `864d55f4…` (M3) aux deux PipelineRuns | Moyenne : VM plus petite qu'à l'essai (PL7) ; effet du nombre de vCPU sur le rpm non mesuré |
| PL7 | Relevé, non exigé : ligne `invité` à 3 vCPU et environ 6 119 664 kB ; capacité de `/w` vers 3,06 Go ; aucun « No space left on device » | Moyenne : lecture du journal deb (06) |
| PL8 | `publier-image` lit `image.tar` et publie : ligne « publiée », `DIGEST_CONSTRUIT` = `IMAGE_DIGEST`, manifeste relu, une couche | Moyenne : premier fichier écrit par root via virtiofs et lu en UID 65532 |
| PL9 | Digest de l'artefact = `07b7bd6f…` (essai) aux deux PipelineRuns ; même artefact | Moyenne : suit PL6 |
| PL10 | Les deux PipelineRuns signés par Chains | Haute : M4b, 06 |
| PL11 | Chaque PipelineRun dure entre 1 et 8 min de la création à la condition finale ; l'étape entière, moins de 20 min | Moyenne : essai de preparer en 8 s, mock en 54 s ; démarrage de Kata et copie de la fermeture non mesurés sous Tekton |
| PL12 | Relevé après : `builds/sample-app-rpm` porte les tags de Chains `sha256-07b7bd6f….att` et `.sig` (forme de M4b), et aucun autre ; catalogue de 152 (N + 1) ; 20 PVC dans `builds` ; deux PipelineRuns `m4c-rpm-*` ; rien n'est supprimé | Moyenne : forme de M4b |

**Ce que chaque issue permet**
- Tout tenu : `comparaison` (rpm tiré de Zot par digest, confronté à M3), puis `provenance`.
- PL2 ou PL8 non tenue : rien n'est purgé. Les relevés (codes, raisons, journaux) sont lus avant toute relance, qui prendra d'autres noms.
- PL6 ou PL9 non tenue : la pipeline a publié un rpm différent de M3. L'écart est à expliquer avant `comparaison`.
