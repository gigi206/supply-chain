# Brique 05, carte de M5, préparée à sec (18/11/2026, écrite à 18:27:30 UTC)

**Interprétation** : le « Continue » reçu après le `/compact` (heure non relevée) vaut permission de préparer à sec, sous l'accord permanent du 18/11. Rien n'a été lancé ni écrit dans Zot, le cluster ou les VM. Une seule mesure, hors ligne sur l'hôte (point 1). Aucun script de M5, aucune prédiction.

**Objet de M5** (tableau des jalons) : « Tests négatifs : rpm de fermeture altéré, sortie réseau pendant le build, pod privilégié hors Kata ; un rejeu de zéro », critère « Refus attendus, témoins acceptés ». Modèle : S5 de la 06 (carte du 11/11/2026, 21:13 UTC), découpée en S5a, tests négatifs tenus le 11/11, et S5b, rejeu de zéro, jalon de la 08 tenu le 13/11.

## Effort

- Brique 05 : 185 commits, **24,89 h** (date d'auteur, écarts d'au plus 1 h) à `c2c5809`, relevé à 18:21:34 UTC. Contrôle : la même méthode, bornée à `bdbe204`, redonne les 167 commits et 21,93 h archivés ([relevé](temps-05-1211.log)).
- Estimation : 2,5 pw ; décision avec le propriétaire à 5 pw. Les heures ne sont pas converties en pw.
- Comparables mesurés, même relevé : M4c, 18 commits, 2,30 h (4,29 h de bout en bout) ; S5a de la 06, 0,45 h du commit de préparation à celui du résultat, préparation non comptée.

## Points de la carte

Chaque point est marqué « vérifié dans le dépôt », « mesuré » (journal archivé), « (lecture) » ou « à mesurer ».

1. **Ce que la confrontation au verrou atteint.** C'est le point qui change la carte.
   - `construire-rpm` contrôle, avant mock (vérifié dans le dépôt, `construction/construire-rpm.yaml`, l. 84 à 143) :
     - les noms des rpm de `depot/`, égaux à ceux du verrou ;
     - aucun autre objet hors de `repodata/` et du dossier `dir:` ;
     - `rpm -qp --qf '%{SIGMD5}'` de chaque rpm, égal au `sigmd5` du verrou ;
     - le sha256 du `manifest.json` du dossier `dir:`, égal au `pull_digest` ;
     - la présence de `repodata/repomd.xml`.
   - Ni le contenu de `repodata/` ni les blobs du dossier `dir:` ne sont contrôlés à cet endroit (vérifié dans le dépôt).
   - **Mesuré hors ligne** ([script](m5-sigmd5.sh), `3b52b1d6…`, [journal](m5-sigmd5.log)), avec le rpm 4.16.1.3 de l'image d'outillage (couches du banc local de `image`), sous `unshare -rn chroot` :
     - un octet inversé dans le payload de `zlib-1.2.11-40.el9.x86_64.rpm`, en-tête intact, laisse `%{SIGMD5}` inchangé (`769b855a…`, code 0, rien sur stderr) ;
     - `rpm -Kv` voit l'altération : « Payload SHA256 digest: BAD », « MD5 digest: BAD », code 1.
   - **Conséquence** : un payload altéré passe la confrontation. La barrière, s'il y en a une, est plus loin, dans mock : dnf (sha256 des paquets dans `primary`, écrit par `createrepo_c` en M4b) ou rpm à l'installation (digest du payload). À mesurer. Si rien ne refuse, c'est un constat que je te remonte : la tâche est signée et revue, et M5 ne la corrige pas sans décision.
   - Relevé en passant : l'en-tête de ce rpm porte une signature V4 RSA/SHA256 (clé `350d275d`), « OK » avec le trousseau de l'image. Le verrou ne porte aucune signature : `sigmd5` est son seul lien aux rpm.
   - La pipeline signée fixe le digest de la fermeture, et oras vérifie chaque couche au tirage (vérifié dans le dépôt, en-tête de `preparer-rpm`). Une fermeture altérée publiée dans Zot aurait un autre digest. Le cas utile est donc l'altération après le tirage, sur le workspace : c'est ce que lit la confrontation. Une copie sur PVC suffit, sans écriture dans Zot.

2. **Deux coupures réseau, à ne pas compter l'une pour l'autre.**
   - **Pod** : `construction-rpm-sans-sortie`, posée par `m3_reseau` le 17/11. Elle est mesurée à chaque build par les témoins de `construire-rpm` (DNS et trois connexions TCP qui doivent échouer), **avant** mock, dans le même pod (vérifié dans le dépôt, l. 76 à 82 ; mesuré en M3 et en M4c).
   - **mock** : il tourne en `--isolation=simple`, car nspawn échoue (étape `essais`). Une coupure propre à mock pendant `%build` n'a jamais été mesurée.
   - **Leçon de N6 de la 06** : P17 n'a pas été mesurée aux deux premiers passages, parce que la cible qui portait la sonde n'était pas appelée. Elle a été tenue au troisième. Ici, la sonde imprimera un marqueur dans `build.log`, et l'étape vérifiera que `%build` a tourné avant de juger.

3. **Pod privilégié hors Kata.**
   - `admission.yaml` de la 08 (l. 89 et 100) n'admet un conteneur privilégié que sous `runtimeClassName: kata` (vérifié dans le dépôt).
   - N7 de la 06 : `construire-deb` sans Kata a été refusé par Pod Security `restricted`, avec `PodAdmissionFailed` et aucun pod (mesuré, S5a).
   - Même mécanisme attendu pour `construire-rpm`, à mesurer.

4. **Mécanisme, à revérifier au relevé.**
   - TaskRuns isolés des bundles signés, par la règle `tekton-references` (compte `build`, PVC ou emptyDir). Aucune tâche neuve, aucune signature, aucune revue de `taches.yml`.
   - Tekton pose `tekton.dev/task` depuis le nom de la tâche résolue (mesuré, P5 de la 06). `construction-rpm-sans-sortie` s'appliquera donc au TaskRun isolé de `construire-rpm`. À revérifier.
   - Dans la pipeline, `construire-rpm` monte `entrees` en lecture seule, sous `subPath: entrees` (vérifié dans le dépôt). Le TaskRun isolé montera un PVC rempli par un TaskRun isolé de `preparer-rpm`.
   - `--dry-run=server` de chaque objet neuf avant tout lancement (leçon de S4d3).

5. **Invariance.** 4 enveloppes sur `builds/sample-app-rpm@sha256:07b7bd6f…` (mesuré, `provenance` de M4c). Aucun TaskRun de M5 ne publie. Recomptées après.

## Tests proposés pour M5a

| # | Altération | Mécanisme | Barrière attendue | Témoin accepté | Écriture dans Zot |
|---|---|---|---|---|---|
| R1 | rpm substitué : un autre rpm réel sous un nom du verrou | copies de l'entrée du témoin sur PVC par un pod runc (liens durs, une altération par copie), puis TaskRun isolé de `construire-rpm` sous Kata sur chaque copie | confrontation : « sigmd5 différent du verrou » | copie intacte : rpm `864d55f4…` de M3, `DIGEST_CONSTRUIT` `07b7bd6f…` ; rien n'est publié | non |
| R2 | fichier en trop dans `depot/` | idem | confrontation : « objet(s) hors du verrou » | R1 | non |
| R3 | rpm du verrou retiré | idem | confrontation : « rpm du verrou absent(s) » | R1 | non |
| R4 | payload altéré, en-tête intact | idem | pas la confrontation (mesuré, point 1) ; dnf ou rpm dans mock, à mesurer | R1 | non |
| R5 | `manifest.json` du dossier `dir:` altéré | idem | confrontation : « manifest.json du dossier dir: différent du pull_digest » | R1 | non |
| R6 | un blob du dossier `dir:` altéré, `manifest.json` intact | idem | pas la confrontation (vérifié dans le dépôt) ; chargement de l'image par mock (« Checking image digest »), à mesurer | R1 | non |
| R7 | connexion réseau pendant `%build` | pod d'essai Kata privilégié (image d'outillage), hors du label `construire-rpm` ; spec minimale dont `%build` imprime ses interfaces et tente une connexion TCP à Zot, construite par mock `--isolation=simple` sur la fermeture | mock, à mesurer ; si la connexion passe, la politique du pod est la seule barrière | même connexion depuis le pod : réussie | non |
| R8 | `construire-rpm` sans Kata | TaskRun isolé sans `runtimeClassName`, sur le PVC du témoin | Pod Security ou admission : `PodAdmissionFailed`, aucun pod | R1 | non |

**Effets à connaître** : des PVC et des pods dans `builds`, retirés à la fin ; rien n'est poussé sur Forgejo ni écrit dans Zot ; la place des PVC sera relevée avant (PT7 non tenue, `/` de sc-stockage qui grossit, `sudo du` encore chez toi).

**Estimation de M5a** : de l'ordre de M4c (2,30 h de commits), plus que S5a de la 06 (0,45 h hors préparation). R4, R6 et R7 n'ont pas de comparable.

## Rejeu de zéro

- `rejeu.sh` de la 08 (223 lignes) a un bloc 06 et aucune étape de la 05 (vérifié par grep : ni `05-rpm`, ni `bricks/05`).
- Un rejeu de zéro vide Zot. Les deux images d'essai disparaissent : `essais-05/mock-rocky9@sha256:99790c13…` et `essais-05/rocky9-bootstrap@sha256:f0ccf105…`.
- Elles ont été construites hors plateforme, une seule fois chacune, depuis des racines installées avec réseau (dettes de l'« Option 1 »). Une racine refaite n'a jamais été comparée. Un bootstrap refait peut changer `image_digest`, et avec lui le verrou, la fermeture rpm, les bundles des tâches qui citent les images et la revue de `taches.yml` (carte de M4, point B).
- Contrainte de date : aucun rejeu de zéro avant le 28/11.
- La dette « rejeu de zéro non réglé, à trancher avant M5 » (décision « Option 1 » du 17/11) se règle donc dans une carte de M5b, avec sa propre estimation et la règle des 2×.

## Question posée

**Découpage.** Ma recommandation :
- **M5a**, maintenant : les tests R1 à R8, sans écriture dans Zot ;
- **M5b**, en jalon à part, pas avant le 28/11 : le rejeu de zéro, avec sa propre carte, qui tranche la dette des images d'essai.

Rien ne change dans `rejeu.sh` avant ta réponse. La liste des tests et les pods d'essai viendront ensuite, sur M5a.
