# F1, fermetures de Traefik sur l'hôte : prédictions (03/11/2026, 16:21 UTC, avant exécution)

Protocole : [README](../README.md), section « Suite sur le laptop », validé par le propriétaire le 03/11/2026, avec l'accord de F1 (« Oui, tout »). Script : [`traefik.sh`](../traefik.sh), tâche `mise run fermetures -- <étape>`. Rien n'est installé dans le système : tout se trouve sous `~/.cache/supply-chain-poc/`.

Lectures faites avant ces prédictions (code de Hermeto 0.64.0, dans son venv) :
- **Toolchain Go** : Hermeto cherche `go` dans le `PATH`, dans `/usr/local/go` et dans son cache, puis choisit la version la plus proche du `go.mod`. Il lance go avec `GOTOOLCHAIN=auto` et un environnement réduit à `PATH`, `HOME`, `NETRC` et ses propres variables.
- **yarn** : Hermeto lance le `yarn` du `PATH` avec un environnement réduit à `PATH` et `NODE_USE_SYSTEM_CA`. Il réécrit le temps du prefetch le `.yarnrc.yml` du projet :
  - `checksumBehavior: throw`, `enableImmutableInstalls: true`, `enableScripts: false`, `enableMirror: false` ;
  - `enableGlobalCache: true`, `globalFolder` égal à `<sortie>/deps/yarn` ;
  - puis il le restaure.
- **Conséquence pour le relevé des noms** : ni `HTTPS_PROXY` ni `COREPACK_HOME` ne passent par l'environnement. D'où des enrobages `go` et `yarn` en tête du `PATH`, qui posent le proxy CONNECT journalisé ([`journal-connect.py`](../journal-connect.py)).
- `strace` (connect) montre toute connexion qui le contournerait.

## `outils`

1. Go 1.27.3 est téléchargé par la tâche `outils:go-1.27` (bootstrap : Go 1.24.7 de mise). Le `ziphash` du cache est égal au `h1:` de `sum.golang.org`. **OK**.
2. yarn 4.18.0 est installé par corepack 0.34.0 (Node 22.22.0). `yarn --version` donne `4.18.0` **hors réseau** (`unshare -rn`, `COREPACK_ENABLE_NETWORK=0`).
3. Contre-épreuve : un `packageManager` au sha512 faux est **refusé** par corepack (prédiction faible sur le texte du message, qui contiendra « hash » ou « mismatch »).

## `sources`

4. Commits relevés.
   - Prédiction faible : tags annotés, vérification GitHub `true`. Les releases de Traefik sont publiées par un robot, et le tag peut être léger ou non signé : consigné tel quel.
5. `go.mod` : `go 1.26.0` pour `v3.7.16`, `go 1.27.0` pour `v3.7.17` (relevé par l'API le 03/11), sans directive `toolchain`.
6. `packageManager` : `yarn@4.18.0+sha512.fcb8716f…` pour les deux tags.
7. `yarn.lock` : autant de `checksum:` que de résolutions, à quelques unités près (les `workspace:` n'en ont pas). Hors `@npm:`, seulement le `workspace:` de l'interface. Prédiction faible : aucune dépendance git ou `patch:`.

## Résultats de `outils` et `sources` (16:21:45 à 16:21:54 UTC)

[`f1-outils.log`](f1-outils.log), [`f1-sources.log`](f1-sources.log). Deux premiers passages de `outils` ratés sur la plomberie, archivés :
- [`f1-outils-premier-passage.log`](f1-outils-premier-passage.log) : `mise run a b` passe `b` en argument de `a` ;
- [`f1-outils-deuxieme-passage.log`](f1-outils-deuxieme-passage.log) : dossier des shims de corepack absent.

Rien d'autre n'avait été modifié.

1. **Conforme** : `h1:r0ub+Fnq…` dans le cache et chez `sum.golang.org`.
2. **Conforme** : `4.18.0` hors réseau. Corepack consigne le hash `sha512.fcb8716f…` du `packageManager`.
3. **Conforme** : « Mismatch hashes ».
4. **Démentie** : **tags légers**. Ce sont les commits qui sont vérifiés par GitHub (`true valid`) : `af6d927c…` pour `v3.7.16`, `04e8ccf8…` pour `v3.7.17`.
5. et 6. **Conformes**.
7. **Démentie en partie** :
   - **732 résolutions pour 685 checksums**, soit 47 sans checksum, et non « quelques unités ». Ce sont 45 paquets natifs à `conditions` (`@rolldown/binding-*`, `lightningcss-*`, `@unrs/resolver-binding-*`), **y compris ceux de linux-x64**, plus le patch `fsevents` et le `workspace:` ;
   - hors `@npm:`, 4 patches `builtin<compat/…>` de yarn (`fsevents`, deux `resolve`, `typescript`) et le `workspace:`, sans dépendance git ;
   - **`yarn.lock` est identique entre les deux tags** ; `go.sum` change de 3 lignes (`cloud.google.com/go/auth` et `oauth2adapt`).

**Conséquence, avant mesure** : un paquet natif linux-x64 n'a pas de checksum dans `yarn.lock`. Une altération de son zip dans la fermeture risque donc de ne pas être vue par yarn hors réseau. Le cas est ajouté à `alterer`, sa prédiction est donnée plus bas.

## Prédictions de `prefetch` (16:22 UTC, avant exécution)

8. `fetch-deps` réussit pour les deux tags. Prédiction faible : moins de 10 min chacun.
9. Noms vus par le proxy :
   - **exactement `proxy.golang.org`, `sum.golang.org` et `registry.yarnpkg.com`**, le registre par défaut de yarn berry, et non `registry.npmjs.org` comme l'écrivait D2 ;
   - prédiction faible : aucun nom de forge (`github.com`), puisque tous les modules sont sur le proxy.
   - Aucun refus ni échec du proxy.
10. Aucun `connect()` inet hors du proxy : les clients passent par lui, sans résolution DNS propre. Prédiction faible sur les sockets unix (aucun).
11. Tailles, prédiction faible :
    - gomod : 600 à 1 100 zips, 0,5 à 1,5 Go ;
    - yarn : environ 690 zips (685 avec checksum, plus les natifs linux-x64), 100 à 300 Mo.
12. Natifs linux-x64 présents en variante `gnu` seulement : `@rolldown/binding-linux-x64-gnu`, `lightningcss-linux-x64-gnu`, `@unrs/resolver-binding-linux-x64-gnu`. Pas de `musl`.
13. Aucun chemin absolu de la sortie ni des sources dans les fichiers de la fermeture. Prédiction moyenne : les chemins n'apparaissent que dans les fichiers de configuration de Hermeto, s'il en écrit à la racine de la sortie.
14. Sources : aucun fichier suivi par git modifié après le prefetch. Prédiction faible : des entrées ignorées par git, `webui/node_modules` ou `webui/.yarn`, peuvent rester.

## Résultats de `prefetch` (16:24:43 à 16:27:42 UTC)

[`f1-prefetch.log`](f1-prefetch.log). Un premier passage est archivé : [`f1-prefetch-premier-passage.log`](f1-prefetch-premier-passage.log), où le prefetch de `v3.7.16` réussit en 91 s puis le script s'arrête sur un `grep` sans correspondance (`pipefail`), corrigé. Un diagnostic suit : [`f1-prefetch-diagnostic.log`](f1-prefetch-diagnostic.log), de 16:28 à 16:30 UTC, même commande sur `v3.7.17`, tracée aussi sur `execve`.

8. **Conforme** : 87 s et 90 s.
9. **Démentie en partie** :
   - `proxy.golang.org` (16 connexions) et `registry.yarnpkg.com` (688, une par archive), conformes ;
   - **`sum.golang.org` n'est jamais contacté** : `go.sum` est complet ;
   - **`storage.googleapis.com` l'est une fois**, pour un usage non identifié ;
   - aucun refus ni échec du proxy.
10. **Démentie** : **une connexion directe vers GitHub** (140.82.121.x:443, puis 20.250.119.67:443 dans le diagnostic), précédée d'une requête DNS à `127.0.0.53`.
    - Le diagnostic l'attribue à **`git fetch -v --force -- origin +refs/tags/*:refs/tags/*`**, lancé par Hermeto dans sa copie temporaire des sources (`*.hermeto-source-copy`) pour dater le module principal (`git tag --points-at`, `for-each-ref --merged`) : 106 558 objets rapatriés.
    - git ne passe pas par le proxy : Hermeto ne lui transmet pas `HTTPS_PROXY`.
    - Le clone d'origine reste superficiel, avec un seul tag.
    - Sockets unix : deux tentatives vers `/var/run/nscd/socket`, absent.
11. **Démentie** : gomod **402 zips, 323 Mo** (`v3.7.16`) et **403 zips, 329 Mo** (`v3.7.17`), sous la fourchette prédite. yarn : **688 zips, 361 Mo**, au-dessus.
12. **Conforme** : les trois natifs `linux-x64-gnu`, aucun `musl`.
13. **Conforme** : aucun chemin absolu de la sortie ni des sources dans la fermeture. À la racine : `.build-config.json` et `bom.json` (3 852 et 3 880 composants).
14. **Conforme** : 0 entrée, ignorées comprises.

**Conséquences pour F2** :
- D2 doit autoriser, en plus des registres, **la lecture de l'origine git des sources**. Dans le cluster, ce sera Forgejo, et non GitHub.
- La liste de `toFQDNs` mesurée est `proxy.golang.org`, `registry.yarnpkg.com` et `storage.googleapis.com`. Pour sample-app (npm), elle reste à mesurer.

## Prédictions de `registre`, `restaurer` et `alterer` (16:30 UTC, avant exécution)

Lecture faite avant : code de yarn 4.18.0 (`yarn.js` du cache de corepack).
- Une archive dont le checksum attendu diffère de celui calculé lève l'erreur 18, « The remote archive doesn't match the expected checksum », sous `checksumBehavior: throw` (défaut).
- **Pour un paquet conditionnel** (`unstablePackages` = `conditionalLocators`), la validation du cache rend `{isValid: true, hash: null}` **sans calculer d'empreinte**. Un paquet sans checksum attendu est accepté (`case null`).

`registre` :
15. Chaque fermeture compte une couche par fichier, hors `bom.json` : 4 433 (`v3.7.16`) et 4 437 (`v3.7.17`). Prédiction faible : Zot accepte un manifeste de cette taille.
16. Stockage : environ +684 Mo pour `v3.7.16`, puis **moins de 15 Mo** pour `v3.7.17`. Couches partagées : yarn 688/688 (`yarn.lock` identique), gomod au moins 3 700/3 748, **au moins 97 % des octets**.
17. Même digest au second push.

`restaurer` :
18. Arbre restauré identique.
19. `go build` hors réseau réussi depuis la fermeture d'origine et depuis la restaurée, **binaires identiques**. Prédiction faible : quelques minutes chacun.
20. `yarn install --immutable` hors réseau réussi aux deux chemins, avec l'environnement de `generate-env` pour chacun. `node_modules` identiques : **la restauration à un autre chemin suffit pour yarn**, puisque le chemin ne passe que par `YARN_GLOBAL_FOLDER`.
21. Sans fermeture : refus (prédiction faible sur le code `YN…`).

`alterer` :
22. Zip yarn avec checksum altéré : **refusé**, erreur 18 (`YN0018`).
23. Checksum de `yarn.lock` altéré : **refusé**, `YN0018` (prédiction moyenne : `--immutable` peut aussi refuser par `YN0028`).
24. **Zip natif linux-x64 sans checksum altéré : accepté hors réseau.** C'est un constat attendu d'après le code, et une faille de la fermeture yarn : seul le digest OCI de la couche le protège.
25. Zip Go altéré : **refusé** (`checksum mismatch` contre `go.sum`, « SECURITY ERROR »).
26. Blob altéré dans le stockage de Zot : **refusé** par `oras pull` (digest).

## Premier passage de `registre`, `restaurer` et `alterer` (16:30:29 à 16:33:40 UTC) et additif du 03/11/2026, 16:40 UTC

Journaux archivés : [`f1-registre-premier-passage.log`](f1-registre-premier-passage.log), [`f1-restaurer-premier-passage.log`](f1-restaurer-premier-passage.log), [`f1-alterer-premier-passage.log`](f1-alterer-premier-passage.log). Défauts du script, corrigés avant le second passage :
- **Partage des couches** : le `join` sur les digests comptait des produits cartésiens, puisque des fichiers identiques partagent un digest (171 884 « couches »). Le calcul porte désormais sur les digests distincts.
- **« Sans fermeture » accepté : faux résultat.** `generate-env` échouait faute de `.build-config.json`, et yarn reprenait le fichier d'environnement du cas précédent. L'échec de `generate-env` est maintenant bloquant, et `.build-config.json` est copié.
- **Motif de refus** : le premier code `YN` trouvé était `YN0000`. Le vrai refus du zip altéré était bien `YN0018` (« The remote archive doesn't match the expected checksum »). On cherche désormais le premier code non nul.
- **`alterer` arrêté** par un `diff` sous `pipefail`, après le cas du zip natif.

**Correction d'un résultat de `sources` (point 7)** : « `go.sum` change de 3 lignes » est **faux**. Le `diff` avait été lu à travers `head`.
- Entre les deux tags, **86 modules Go changent de version**, avec les zips associés (Azure, Akamai, Google Cloud, brotli…) : 236 Mo de zips propres à `v3.7.17`.
- Comparaison fichier par fichier, sur l'hôte : 3 997 chemins communs, dont 79 fichiers `list` différents ; 439 chemins propres à `v3.7.17` et 435 à `v3.7.16`, tous dans gomod. **Les zips de même chemin sont identiques.**
- En digests distincts, `v3.7.17` partage **3 047 blobs sur 3 439** et **454 Mo sur 690 Mo, soit 65,8 %** avec `v3.7.16`. yarn est partagé à 100 %, gomod à environ 28 % des octets.
- **La prédiction 16 (≥ 97 %, < 15 Mo) est donc démentie** : elle reposait sur cette lecture fausse. Le premier passage mesurait +239 Mo dans Zot. Le seuil de la brique (≥ 50 %) reste atteint.

Résultats du premier passage qui ne dépendent pas de ces défauts :
- push à 4 433 et 4 437 couches, acceptés par Zot ; même digest au second push ;
- arbre restauré identique ;
- binaires Go identiques (`6dee223e…`, 84 s et 83 s) ;
- `yarn install --immutable` hors réseau réussi aux deux chemins, `node_modules` identiques (819 `package.json`) ;
- zip avec checksum refusé (`YN0018`) ; **zip natif linux-x64 altéré accepté** (« Completed »).

Le second passage rejoue les trois étapes.

## Second passage (16:35:25 à 16:43:28 UTC) : résultats de `registre`, `restaurer` et `alterer`

Journaux : [`f1-registre.log`](f1-registre.log), [`f1-restaurer.log`](f1-restaurer.log), [`f1-alterer.log`](f1-alterer.log). Un deuxième passage d'`alterer` est archivé : [`f1-alterer-deuxieme-passage.log`](f1-alterer-deuxieme-passage.log). Il avait deux défauts, corrigés :
- l'octet altéré cassait la décompression du zip Go (« flate: corrupt input »), qui était refusé avant tout contrôle de `go.sum`. Le zip est désormais reconstruit valide, un fichier `.go` modifié ;
- `grep | head -1` recevait un SIGPIPE sous `pipefail`, ce qui arrêtait le cas du blob de Zot.

15. **Conforme** : 4 433 et 4 437 couches, acceptées par Zot.
16. **Démentie** (voir l'additif de 16:40) :
    - stockage +704 Mo, puis **+239 Mo** ;
    - en blobs distincts, gomod 2 359/2 751 (28,3 % des octets), yarn 688/688 (100 %), **total 3 047/3 439, 65,8 % des octets** ;
    - **seuil de la brique (≥ 50 %) atteint**.
17. **Conforme** : `sha256:883e1066…` deux fois.
18. **Conforme** : 4 437 fichiers.
19. **Conforme** : **`6dee223e…` identique** depuis la fermeture d'origine et depuis la restaurée, en 82 s et 83 s.
20. **Conforme** :
    - 819 `package.json` aux deux chemins, `node_modules` identiques ;
    - `generate-env` ne fait passer le chemin que par `YARN_GLOBAL_FOLDER`, et par `GOPROXY`, `GOMODCACHE`, `GOPATH`, `GOCACHE` pour Go. **La restauration à un autre chemin suffit, pour yarn comme pour gomod.**
21. **Conforme** : refus `YN0001` (« getaddrinfo ENOTFOUND registry.yarnpkg.com », hors réseau).
22. **Conforme** : `YN0018`, « The remote archive doesn't match the expected checksum ».
23. **Conforme** : `YN0018`, sur le paquet dont le checksum a été altéré.
24. **Conforme, constat** : **le zip altéré de `@rolldown/binding-linux-x64-gnu` est accepté hors réseau** (« Completed »).
    - yarn 4.18.0 ne contrôle pas les paquets conditionnels, et `yarn.lock` ne porte aucun checksum pour eux.
    - Dans la fermeture de Traefik, trois paquets natifs (binaires exécutés au build de l'interface) ne sont protégés que par le digest OCI de leur couche.
25. **Conforme** : « verifying cloud.google.com/go/auth@…: checksum mismatch ».
26. **Conforme** : `oras pull` par digest refuse, « mismatched digest ».

## Bilan de F1

- **Seuil de la brique 03 sur Traefik** :
  - restaurable par digest, au même chemin ou à un autre ;
  - builds hors réseau identiques ;
  - déduplication de 65,8 % des octets entre deux tags proches (≥ 50 %).
- **Altérations** : refusées pour gomod, pour yarn avec checksum et dans le registre. **Acceptée pour un paquet yarn conditionnel**, faute de checksum (constat).
- **Pour F2 (D2)** : `proxy.golang.org`, `registry.yarnpkg.com`, `storage.googleapis.com` (une connexion), plus **l'origine git des sources** (`git fetch` des tags par Hermeto, hors proxy). `sum.golang.org` n'a pas été contacté.
- **Pour F2 (D4)** : la toolchain Go doit couvrir le `go.mod` (Traefik `v3.7.17` exige Go 1.27). Une image d'outils figée sur une toolchain devra suivre les projets.
- Durée de F1 : de 16:21 à 16:43 UTC pour les mesures, sans compter la préparation. C'est bien en deçà de l'estimation de 0,25 pw.

## Additif du 03/11/2026, 16:46 UTC : relevé complémentaire, après relecture

[`f1-releve-complementaire.log`](f1-releve-complementaire.log) (lecture seule, 16:45 UTC).
- **Le constat 24 est prouvé jusqu'au binaire installé.** `rolldown-binding.linux-x64-gnu.node` vaut `ae168566…` avec la fermeture intacte et **`e536f326…` avec le zip altéré**. L'octet altéré atteint donc `node_modules`, et le binaire natif modifié est installé sans erreur.
- **Le SBOM de Hermeto ne porte aucune empreinte** (0 composant sur 3 880 avec `hashes`), ni pour ces paquets ni pour les autres. Il ne permet donc pas de détecter l'altération après coup.
- **Portée, déduite et non mesurée** : faute de checksum dans `yarn.lock`, un registre amont qui servirait un autre binaire pour ces paquets serait accepté **dès le prefetch**, puis figé dans la fermeture avec un digest OCI valide. Le risque n'est pas limité à une altération de la fermeture avant son push.
- **`storage.googleapis.com`** : le CONNECT (16:26:41 UTC) tombe dans la phase gomod de Hermeto (16:26:28 à 16:27:15 UTC). Il vient donc de go, et non de yarn.
- **Chemins pour npm** : non mesuré en F1, qui portait sur gomod et yarn. Le constat « chemins canoniques obligatoires » de cette brique reste à revérifier pour npm en F2.
