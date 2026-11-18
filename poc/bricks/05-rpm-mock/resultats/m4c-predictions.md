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
