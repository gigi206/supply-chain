# Brique 06, S4c : prédictions (écrites le 11/11/2026 vers 16:45 UTC, avant toute exécution)

Le script est [`s4c.sh`](../s4c.sh), écrit avec ces prédictions. **Rien n'a été lu ni écrit dans le cluster, Zot ou les VM pour S4c.**

## Ce que publie S4c

Un artefact OCI de packaging, publié par l'hôte comme `web/dist` (`construction.sh` de la 08, fonction `pousser_web_dist`) :
- **dépôt** `entrees/sample-app/packaging-deb`, tag `s4c`, type `application/vnd.supply-chain.packaging-deb.v1` ;
- **un fichier par couche** : les 5 fichiers de `poc/packaging/debian/`, **inchangés**, et le verrou `poc/packaging/verrou-deb.txt` ;
- **annotation** `org.opencontainers.image.created` fixée à `1970-01-01T00:00:00Z`, pour un manifeste déterministe.

**Le verrou** a le format de [`builder/paquets.txt`](../builder/paquets.txt), que `prefetch-deb` consomme déjà (note de 22:51 UTC : en S4b, « seule la liste change ») :
- une ligne par paquet : nom, version, architecture, sha256, taille, chemin dans le pool ;
- il est tiré des `Installed-Build-Depends` du buildinfo de S2, rapprochés du `Packages` de l'instantané `20261105T000000Z`.
- S2 a utilisé le même InRelease que S4a (`0584fba3…`, [`s2-racine.log`](s2-racine.log), ligne 5). Le verrou n'a donc pas besoin de son propre InRelease : celui de S4a s'applique.

## Décisions et accords

- **Ordre** : S4a, **S4c**, S4b, S4d, S5 (décision de 22:21:12 UTC).
- **Verrou avec `debian/`** (22:20:23 UTC).
- **`marked` par la plateforme pour le deb** (11/11/2026, 16:19:27 UTC). Rien de npm n'entre dans l'artefact de S4c.
- **Sans accord** : l'étape `verrou`, sur l'hôte seul et hors ligne. Elle lit les copies de S1 (`InRelease`, `Packages.xz`, `Packages`) et les résultats de S2. Elle écrit `poc/packaging/verrou-deb.txt` et deux layouts OCI locaux, sous `~/.cache`.
- **Avec un accord nommé** : l'étape `publier`, une écriture **définitive** dans Zot avec le compte `poc-ecriture`, celui de `web/dist`.

## Choix de conception, validés par le conseiller

- **`debian/rules` garde le mode vendor** (`GOFLAGS=-mod=vendor`, `GOPROXY=off`). Le mode module changerait `debian/`, que partagent `sources.sh` et les rejeux de S1 à S3. Il changerait aussi le binaire (banc nix, B-1).
  - Le coût passe en S4d : reconstituer `vendor/` depuis la fermeture gomod, et `web/node_modules/marked` depuis la fermeture npm.
  - **Prédiction reportée à S4d** : le `vendor/` reconstitué est identique à celui de `sources.sh`. La comparabilité avec S1 à S3 n'est pas promise avant cette mesure.
- **La configuration d'Hermeto** (écosystèmes, chemin `web`) n'entre pas dans l'artefact de S4c. Elle relève de S4b.
- **La tâche qui produira la fermeture npm** est un choix de S4b, à préparer dans sa carte. Critère relevé : la porte doit de toute façon passer à plusieurs fermetures en S4d (fermetures deb et Go). Étendre `prefetch-gomod` n'économise donc pas ce changement, et toucherait une tâche signée dont dépend la voie image de la 08.
- **Correction du tableau présenté avant la décision** : la colonne « web/dist par digest » indiquait « Plateforme : rien ». C'était faux : la pipeline deb aurait aussi demandé la porte à deux fermetures. L'écart entre les options était plus faible, en faveur de npm. La décision ne change pas.

## Prédictions

| N° | Étape | Prédiction | Confiance |
|---|---|---|---|
| C1 | verrou | InRelease de sha256 `0584fba3…` ; `Packages.xz` conforme à la ligne `main/binary-amd64/Packages.xz` de l'InRelease (`7778d3e3…`, 9 678 380 octets) ; `Packages` égal à `xz -dc Packages.xz` | haute : mesuré en S1 et S4a |
| C2 | verrou | 162 `Installed-Build-Depends`, tous distincts ; chacun présent une seule fois dans `Packages`, à sa version exacte, en `amd64` ou `all` ; 0 absent, 0 en double | haute : Q2 de S2 tenue sur la même liste |
| C3 | verrou | Le verrou, ramené à « fichier sha256 taille », est égal ligne pour ligne à `s2-fermeture-attendue.txt` (162 lignes) | moyenne : le nom de fichier du pool omet l'époque, comme celui de S2, mais ce n'est pas vérifié pour les 22 paquets à époque |
| C4 | verrou | Deux poussées vers deux layouts OCI locaux vides donnent le même digest de manifeste | haute : `web/dist` (08), même méthode |
| C5 | publier | Deux poussées dans Zot donnent le même digest, égal à celui de C4 | haute : un manifeste OCI ne dépend pas de la cible |
| C6 | publier | Les fichiers tirés par digest dans un répertoire vide sont égaux, par sha256, à ceux du dépôt | haute |
| C7 | publier | Le mode de `debian/rules` (755 dans git) n'est pas conservé par oras : tiré en 644 ou moins. Relevé, pas exigé par le script. Si c'est confirmé, S4d devra rétablir le bit d'exécution, ou appeler `make -f debian/rules` | moyenne : non lu dans le code d'oras 1.3.6 |

## Limites connues

- Le verrou reproduit ce que S2 a installé. Il ne prouve pas que sbuild, hors ligne, résoudra le même ensemble depuis un miroir partiel construit sur ce verrou : ce sera une prédiction de S4d.
- La version (`1.0.0-1`) et la date de `debian/changelog` sont figées pour tous les commits : c'est la limite consignée à 22:14 UTC.
- La porte ne juge pas l'artefact de packaging, pas plus qu'elle ne juge `web/dist` aujourd'hui.
