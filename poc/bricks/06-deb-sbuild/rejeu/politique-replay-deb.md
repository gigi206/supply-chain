# Politique du replay indépendant du deb (brique 06, contrôle 6)

**Projet du 12/11/2026, soumis à la relecture du propriétaire. Non figé.** La VSA du deb la citera dans `policy.uri`, avec son digest : le sha256 de ce fichier au commit qui la fige, avant la signature. `policy.uri` est l'URL GitHub du fichier à ce commit, comme pour la [politique de la brique 10](../../10-independent-replay/politique-replay.md).

Cette politique reprend celle de la brique 10. Elle ne change que ce qui tient à l'artefact : un paquet Debian construit par sbuild, au lieu d'une image construite par BuildKit. Le domaine est le même : la VM `sc-replay`, administrée par le propriétaire (D1 b) et hébergée sur le même hyperviseur que le plan de confiance (D2 a). L'indépendance est donc technique, pas organisationnelle.

## 1. Provenance acceptée

Chaque condition est éliminatoire : un échec arrête le replay avant tout build.

1. La provenance est tirée d'un **bundle horodaté** de `horodatage/bundles` (brique 08), copié par l'hôte en lecture anonyme. Dans la VM, chaque bundle est vérifié hors réseau, comme dans la brique 10 :
   - signature avec la clé publique de Chains, prise hors bande dans ce dépôt ;
   - sujet égal au layout du deb ;
   - jeton RFC 3161 de la TSA.

   L'énoncé retenu est celui du bundle vérifié de l'`invocationId` demandé, jamais celui du transport. Le propriétaire a retenu `454728c5` le 12/11/2026 : c'est la provenance la plus récente, celle que juge la porte.
2. `_type`, `predicateType`, `builder.id` et `buildType` : mêmes valeurs que dans la brique 10.
3. Le sujet est le layout OCI du deb (`builds/sample-app-deb`). Son digest est celui comparé à la section 4.
4. `resolvedDependencies` déclare, chacun avec un digest :
   - le commit (`git+https://…/workspace/sample-app.git`, `sha1`) ;
   - la fermeture deb (`builds/fermetures/sample-app-deb`) et la fermeture applicative (`builds/fermetures/sample-app-sources`) ;
   - l'artefact de packaging (`entrees/sample-app/packaging-deb`), qui porte `debian/` et le verrou ;
   - l'image de build (`builds/builders/sbuild-debian13`) et l'image `plateforme/outils-prefetch` ;
   - les bundles des tâches `preparer-deb` et `construire-deb`.

## 2. Entrées et recette

- **Commit** : lu dans un bundle git de Forgejo, puis comparé au `sha1` déclaré.
- **Artefacts** : tirés par digest dans Zot. Leur digest est recalculé dans la VM.
- **Recette** : elle est lue dans les bundles `preparer-deb` et `construire-deb`, par leurs digests déclarés. Quinze lignes clés doivent y figurer telles quelles, sinon le replay est refusé (`rejeu/verifier_deb.py`) :
  - pour la préparation : `git archive` du commit, les trois `oras pull`, l'environnement de Go hors ligne, `go mod vendor` et `go mod verify`, le contrôle d'integrity de marked et son extraction, la copie de `debian/` ;
  - pour la construction : l'archive amont, `dpkg-source -b`, **la commande sbuild**, l'archive de la couche et la configuration du layout.

  La préparation et la construction sont refaites d'après ces lignes. Une différence avec la recette signée est consignée comme un constat.
- **Fermeture deb** : confrontée au verrou de l'artefact de packaging : même sha256, même taille et même chemin pour chaque paquet, et aucun autre fichier.
- **Image de build déclarée** : seul son manifeste est transporté. Il sert à comparer la couche du chroot (section 3). Son contenu n'est ni exécuté ni réutilisé.
- **Image `outils-prefetch`** : elle sert seulement à lire la version de Go.

## 3. Indépendance du build

- **Chroot reconstruit dans le domaine** (décision du propriétaire du 12/11/2026, point 3 et décision 2) :
  - mmdebstrap dans la VM, depuis l'instantané Debian lu par la VM, avec les options de la tâche `construire-builder` de la plateforme ;
  - l'InRelease est vérifié par apt (`sqv`) avec le trousseau Debian de la VM, et son sha256 est égal à celui contrôlé en S1 ;
  - **le chroot, rangé comme dans l'image de build, doit donner la couche du chroot de l'image déclarée**. Sinon, le replay est refusé.
- **Outils du domaine** :
  - mmdebstrap, sbuild, libsbuild-perl et uidmap, par apt, aux versions de l'image de build de la plateforme. Leur sha256 est comparé à `builder/paquets.txt` avant l'installation ;
  - Go de go.dev (brique 10), de la même version que celle d'`outils-prefetch`.
- **Écarts voulus avec la plateforme**, consignés et non comparés :
  - aucun pod ;
  - le chroot sous `/home/replay/s6b`, et non `/opt/sbuild` ;
  - l'arbre de travail sous `/var/tmp/s6b-r4`.
- **Caches froids** : l'arbre de travail est vidé en root à chaque transport, et le reconstructeur refuse de démarrer s'il existe encore.
- **Sans réseau pendant le build** (D4) :
  - le lien de la VM est coupé ;
  - le reconstructeur refuse de démarrer si une interface a encore sa porteuse ;
  - les compteurs de l'interface sont relus depuis l'hôte, après la coupure et avant le rétablissement ;
  - le build doit finir avant le rétablissement.
- **Délai** : `timeVerified` est au moins 24 h après `runDetails.metadata.finishedOn` de la provenance.

## 4. Verdict

- **`PASSED`** si toutes les conditions des sections 1 à 3 tiennent, et si **le digest du manifeste reconstruit est égal au digest du sujet**.
- **`FAILED`** sinon. Aucune VSA n'est alors signée.

## 4 bis. Code du domaine

- Le code qui vérifie, reconstruit et décide de la VSA est versionné dans ce dépôt : `rejeu/verifier_deb.py`, `rejeu/rebuild_deb.sh` et `rejeu/vsa_deb.py`. L'hôte le copie dans la VM.
- Ce code n'est pas vérifié par le domaine lui-même. Son sha256 est journalisé à chaque passage et **inscrit dans la VSA** (`verifier.version`), avec les versions de sbuild, de mmdebstrap, de dpkg-dev et de Go.

## 5. Niveaux revendiqués (`verifiedLevels`)

Mêmes règles que dans la brique 10 : `SLSA_BUILD_LEVEL_3` si la section 1 tient, et `POC_REPLAY_BIT_IDENTIQUE` si le verdict est `PASSED`.

## 6. Signature et rangement de la VSA

- `verifier.id`, clé et signature : comme dans la brique 10. Clé cosign du domaine, signature dans la VM sans registre ni réseau (`unshare -rn`), `cosign attest-blob --statement` avec une configuration sans service.
- **Rangement proposé** : en referrer OCI 1.1 du layout du deb, dans un dépôt séparé, `builds/vsa/sample-app-deb`, sur le modèle de `builds/vsa/sample-app`. C'est à décider par le propriétaire.
- Chaque push est soumis à l'accord du propriétaire. D'après la décision du 12/11/2026 (ordre c), il vient après S5b.

## Limites

- Les mêmes que la brique 10 : avec D1 (b) et D2 (a), le propriétaire, ou le root de l'hôte, peut forger à la fois la provenance et la VSA.
- La provenance propre des deux fermetures et de l'artefact de packaging n'est pas vérifiée par le domaine. Seuls leurs digests déclarés le sont.
- S5b remet Zot à zéro. `inputAttestations` désignera alors un bundle horodaté effacé, et la VSA ne reviendra que par un bundle versionné re-poussé, si `039949f9` se reproduit.

## Notes de relecture, 12/11/2026 (à partir de 10:56:18 UTC, après relecture du conseiller) : à intégrer au texte au moment de le figer

Ces notes s'ajoutent au projet commité dans `1b36f83`, à 10:50:25 UTC. Le commit qui figera la politique réécrira les passages concernés, avec ton accord, et le dira dans son message. `vsa` refuse une politique qui porte encore une mention de projet.

1. **Section 3, InRelease** : l'égalité de son sha256 avec S1 est mesurée sur les lectures par curl des étapes `v4`, `sqv` et `trousseau`, et non sur la lecture d'apt pendant mmdebstrap. apt, lui, a vérifié la signature avec `sqv` ; le témoin négatif l'a mesuré. **Ce qui lie le chroot, c'est l'égalité de sa couche avec celle de l'image de build déclarée.** Le texte doit le dire ainsi.
2. **Section 6, rangement** : ce n'est pas une décision. La porte de la 08 (`politique/porte/vsa.sh`) dérive le dépôt de la VSA du nom de l'artefact : `builds/<nom>` devient `builds/vsa/<nom>`. Pour le deb, c'est donc `builds/vsa/sample-app-deb`.
3. **Section 5, `SLSA_BUILD_LEVEL_3` : question au propriétaire.** Pour l'image, la 10 s'appuie sur les mesures de la 08 : isolation, et clé hors des nœuds de build. Le deb est construit dans un pod Kata **privilégié**. Je n'ai pas relevé de mesure archivée qui porte ce niveau pour une tâche privilégiée sous Kata. Deux choix :
   - garder le niveau en citant une mesure ;
   - ne revendiquer que `POC_REPLAY_BIT_IDENTIQUE` pour le deb.

**Décision du propriétaire, 12/11/2026, reçue avant 10:59:06 UTC (« Bit identique seul »)**, sur la note 3 : la VSA du deb ne revendique que `POC_REPLAY_BIT_IDENTIQUE`. Au moment de figer le texte, la section 5 dira donc : « `POC_REPLAY_BIT_IDENTIQUE` si le verdict est `PASSED`. `SLSA_BUILD_LEVEL_3` n'est pas revendiqué pour le deb : aucune mesure archivée ne le porte pour un build dans un pod Kata privilégié. » `rejeu/vsa_deb.py` est modifié en conséquence.

