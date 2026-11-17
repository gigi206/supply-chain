# Brique 05, carte de M4b, préparée à sec (17/11/2026, à partir de 21:16:51 UTC)

Sur « Oui, prépare-la » (après le relevé de l'état en service de M4a). Rien n'a été lancé ni écrit dans Zot, le cluster ou les VM. Aucune tâche, aucun script, aucune prédiction. Découpage décidé : [carte de M4](m4-carte.md), note « Oui, ce découpage ».

**Objet de M4b** : une tâche `prefetch-rpm` neuve, mise au point dans un pod d'essai puis signée, et une pipeline qui produit la fermeture rpm sous `builds/fermetures/`, avec `publier-fermeture` inchangée si elle tient.

## La fermeture de M2, et ce qui doit y rester

Mesuré : la collecte de M2 a archivé chaque fichier avec son chemin, son sha256 et sa taille ([`s1-collecte.log`](s1-collecte.log), 235 lignes `fichier`). Elle a aussi mesuré que les sha256 des 222 rpm sont égaux aux primary de vault 9.7 vérifiés par `hote97`, et celui du rpm de mock au primary d'EPEL du dernier passage de `hote`.

| Partie | Fichiers | Origine dans M2 | Dans la plateforme |
|---|---|---|---|
| rpm du buildroot | 222 sous `depot/` | vault 9.7, par les URL du verrou | téléchargés par `prefetch-rpm` (443 public) |
| `repodata` | 7 sous `depot/repodata/` (dont trois `.sqlite.bz2`) | `createrepo_c --compatibility` dans le pod | recalculés par `prefetch-rpm` (point 6) |
| image de bootstrap | 4 sous `depot/sc-stockage.poc.test@sha256:f0ccf105…/` | `skopeo copy --preserve-digests` depuis Zot | même geste, depuis `essais-05/` (« Option 1 ») |
| verrou | `verrou.json` (`b6d0f8f1…`) | livré par l'hôte | **pas nécessairement dans la fermeture** : `mock --hermetic-build` le prend en argument séparé du dépôt (`s1.sh`, ligne 1223 : `mock --hermetic-build /w/verrou.json "$D"`), vérifié dans le dépôt |
| rpm de mock | `outils/mock-6.9-1.el9.noarch.rpm` (`a5043350…`) | EPEL 9 | choix ouvert (point 4) |

## Points de la carte

Chaque point est marqué « vérifié dans le dépôt », « mesuré », « (lecture) », « de mémoire, à lire » ou « à mesurer ».

1. **Transport de la liste : la décision de M4b.**
   - `prefetch-rpm` a besoin d'une liste des rpm attendus : URL, sha256, taille. Le verrou n'a que `url` et `sigmd5` (vérifié dans le dépôt). Les sha256 et tailles viennent des primary de vault 9.7, vérifiés par `hote97`, auxquels la collecte a mesuré l'égalité. La liste n'en couvre que les rpm : `repodata` est recalculé, il ne peut pas y être.
   - **Option A, précédent de S4b de la 06** : l'hôte inscrit la liste dans le gabarit de la pipeline de la fermeture avant signature. `prefetch-rpm` ne lit pas Zot pour ses entrées, et n'a besoin que de l'image `mock-rocky9`. Le verrou reste dans l'artefact de packaging (spec et verrou, deux fichiers, comme `m4a.sh` le prépare). La préparation de M4c le tire par digest et confronte la fermeture au verrou, comme `preparer-deb` le fait pour le deb (vérifié dans le dépôt). Mesuré pour le deb (B15 de S4b, tenue) : la liste de 162 lignes, paramètre du TaskRun, se relit dans la provenance de Chains.
   - **Option B** : `prefetch-rpm` tire par digest l'artefact de packaging, qui porterait le spec, le verrou, la liste et les clés publiques ; son digest entrerait dans `resolvedDependencies` par un `*_ARTIFACT_INPUTS`. Sa sortie l'autorise (`prefetch-rpm-sortie` ouvre Zot en 5000, vérifié dans le dépôt). Coûts :
     - un second pas avec une image qui porte `oras`, absent de `mock-rocky9` (lecture), comme les deux images de `preparer-deb` ;
     - **ordre** : le pod d'essai doit tirer le vrai artefact, donc `publier` de M4a passe avant `essai`, et cette écriture est définitive ; une erreur de contenu vue à l'essai demanderait un second artefact ;
     - `m4a.sh` publie aujourd'hui deux fichiers : en publier quatre est une modification du script, avec un accord à part.
2. **Images de la tâche.** Les gestes de M2 demandent `curl`, `rpm`, `createrepo_c`, `skopeo` et `sha256sum`, que le script de la voie 2 exige de l'image `mock-rocky9@99790c13…` (vérifié dans `s1.sh`). Sous A, une seule image ; sous B, deux (point 1).
3. **Runtime : runc, sans root, à mesurer.**
   - Précédents vérifiés dans le dépôt : `prefetch-gomod` tourne sous runc, conforme à Pod Security `restricted`, `runAsNonRoot` ; `prefetch-deb` aussi, en UID 65532.
   - En M2, la voie 2 a tourné en Kata privilégié, root. Ses gestes n'exigent pas root d'après le script (lecture) : `rpm --dbpath` sur une base créée par la tâche, `createrepo_c` et `skopeo copy` vers un dossier. L'image `mock-rocky9` n'a jamais tourné sans root.
   - L'écriture sous un `subPath` du PVC sans root dépend du mode de la racine du volume : c'était une prédiction de S4b de la 06, dont le résultat n'est pas relu ici.
   - Repli, s'il échoue : rien n'est signé, la décision revient au propriétaire (note de « Hors plateforme »).
4. **rpm de mock : le garder dans la fermeture ou non (choix ouvert).**
   - Le build prend mock dans l'image d'outillage, pas dans la fermeture (lecture de `s1.sh`). Le rpm de mock y était au titre de la ligne M2 du tableau des jalons.
   - Le garder ajoute EPEL et sa clé comme dépendance mouvante. La note de confiance de HB7 dit qu'EPEL ne garde en général que la dernière construction (non mesuré) : un rejeu de zéro pourrait ne plus le trouver.
   - Ce choix change la liste : il se tranche avant `verrou` de M4a sous B, avant `taches` sous A.
5. **Clés et CA.** En M2, l'hôte livrait au pod les clés de Rocky et d'EPEL (empreintes contrôlées par `hote`) et le CA de Zot pour `skopeo` (`/etc/containers/certs.d/…`), vérifié dans `s1.sh`. Dans Tekton : les clés par la pipeline (A) ou par l'artefact (B), leurs empreintes fixées dans la pipeline signée ; le CA monté comme pour `publier-fermeture` (`/etc/ca-poc`). Sous A, le sha256 fixé par fichier ancre déjà chaque rpm ; garder `rpm -K` reste à décider en préparation.
6. **`repodata` non reproductible tel quel : mesuré.** Sur les mêmes 222 rpm, `createrepo_c --compatibility` a donné `repomd.xml` `86ddcef1…` à `voie2` et `108f954a…` à `collecte` ([`s1-voie2.log`](s1-voie2.log), [`s1-collecte.log`](s1-collecte.log)). Deux passages de la tâche donneraient donc deux fermetures de digests différents, alors que S4b a reproduit chaque fermeture deux fois au même digest. Options de `createrepo_c` pour fixer la révision, les dates et les bases sqlite : de mémoire, à lire. Toute option change `repodata` par rapport à la fermeture de M3. À mesurer dans le pod d'essai par deux passages.
7. **`publier-fermeture` sur des chemins à « : » et « @ »** : à vérifier (point 4 de la carte de M4). Le banc de la fermeture l'a mesuré avec `closure.sh`, même forme d'envoi.
8. **Signature et liste revue.** Une tâche neuve suit le cycle de S4a : signature versionnée par `SIGNER=1` (la clé des tâches n'est jamais lue), revue de `taches.yml` par le propriétaire dans un commit à part, puis bundle ; même cycle pour la pipeline. Vérifié dans `s4a.sh`.
9. **Ressources.** `limites-obligatoires` (08c) est en `Deny` en service (mesuré, M4a). M4a a mesuré la valeur de `config-defaults` (512 Mi de limite), pas que Tekton l'applique. Chaque pas de `prefetch-rpm` pose donc ses propres ressources.

## Ordre proposé, selon l'option, sans prédictions

| Option A | Option B |
|---|---|
| `prealables` (hôte : liste tirée des primary vérifiés, confrontée au verrou et à la collecte ; gabarits rendus ; relevé en lecture de `mock-6.9-1.el9` dans EPEL si le rpm de mock reste) | `prealables` (de même) |
| `essai` (pod d'essai runc sans root, label `prefetch-rpm`, gestes réels, deux passages, `repodata` comparés) | `m4a.sh` modifié (quatre fichiers), accord ; `verrou` et `publier` de M4a (écriture définitive) |
| `verrou` et `publier` de M4a (deux fichiers, script inchangé) | `essai` (tire le vrai artefact) |
| `taches` (`prefetch-rpm` signée, revue de `taches.yml`, bundle ; pipeline signée), `rpm` (deux PipelineRuns), `comparaison`, `provenance` | de même |

Chaque écriture (Zot, cluster, `taches.yml`) a son accord nommé ; les étapes en lecture, un accord pour le jalon. Comparable : S4b de la 06, 0,87 h de commits, plus l'écriture et la signature d'une tâche neuve (S4a : 1,01 h) ([relevé](m4-projection-06.log)).

## Question posée

Le transport de la liste (point 1). **Recommandation** (relue par le conseiller) : l'option A. Elle suit le précédent mesuré de S4b (liste dans le gabarit, relue dans la provenance), garde une seule image à `prefetch-rpm`, laisse `m4a.sh` inchangé et met le pod d'essai avant toute écriture dans Zot. Le verrou n'a pas à passer par `prefetch-rpm` : mock le prend en argument séparé, et la préparation de M4c le tirera de l'artefact de packaging, dont le digest entrera alors dans la provenance du build. B ajouterait cette trace à la provenance de la fermeture, au prix d'une seconde image et d'une écriture définitive avant l'essai.
