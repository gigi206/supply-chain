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
