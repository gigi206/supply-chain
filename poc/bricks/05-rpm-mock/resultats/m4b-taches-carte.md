# Brique 05, carte de l'étape `taches` de M4b, préparée à sec (17/11/2026, à partir de 22:38:38 UTC)

Préparée sur « Oui, prépare-la ». Rien n'a été lancé ni écrit dans Zot, le cluster ou les VM : ni tâche, ni script, ni prédiction. Base mesurée : le pas de prefetch final `PREFETCH_FINAL`, passé deux fois dans des pods neufs avec la même fermeture de 230 fichiers ([`m4b-final.log`](m4b-final.log)), et mock hermétique sur le même index V2 (`m4b_mock_v2`).

**Ordre consigné** (« Option A », [carte de M4b](m4b-carte.md)) : `verrou` et `publier` de M4a passent avant `taches`. La carte peut précéder ces deux étapes, mais pas le lancement de `taches`. Elles ne servent qu'à M4c : `prefetch-rpm` ne lit pas l'artefact de packaging.

**Effort** : brique 05, 140 commits, 18,83 h (écarts d'au plus 1 h) à HEAD `312efce` ([relevé](temps-05-1211.log)), pour 2,5 pw estimées ; décision avec le propriétaire à 5 pw. Les heures ne sont pas converties en pw.

## Objet

- Une tâche `prefetch-rpm` neuve, signée : `PREFETCH_FINAL` adapté à Tekton.
- Une pipeline signée `prefetch-rpm-sample-app`, sur le modèle de `prefetch-deb-sample-app` (S4b de la 06) :
  - `prefetch` : `prefetch-rpm`, workspace sous le `subPath` `fermeture` ;
  - `publier` : `publier-fermeture` inchangée (`7fa92ad3…` de la liste revue), à la racine ;
  - dépôt `builds/fermetures/sample-app-rpm`.
- Toutes les entrées sont fixées dans le gabarit et couvertes par la signature. Le PipelineRun est créé par l'hôte, sans déclencheur (condition de « Oui, ce découpage »).

## Points

Chaque point est marqué « vérifié dans le dépôt », « mesuré », « (lecture) » ou « à mesurer ».

1. **Tâche `prefetch-rpm`**
   - Image : `essais-05/mock-rocky9@sha256:99790c13…` (« Option 1 »).
   - Pod : runc ; UID 65532, `runAsNonRoot`, capacités retirées, comme `prefetch-deb` (vérifié dans le dépôt) ; `/tmp` en `emptyDir` ; CA du PoC par la ConfigMap `ca-poc` sous `/etc/ca-poc`.
   - Paramètres :
     - `liste` (222 lignes) ;
     - `source` et `dossier` de l'image de bootstrap, deux paramètres comme le veut « Option A », avec un contrôle de cohérence (`dossier` = partie de `source` avant le premier « : », puis « @ » et le digest) ;
     - `fp_rocky`, l'empreinte fixée dans la pipeline signée (point 5 de la carte de M4b).
   - Ressources explicites : 2 CPU et 2 Gi en limite, comme aux essais (mesuré : `essai` et `final`). Les valeurs par défaut de `config-defaults` (1 CPU, 512 Mi ; mesuré, M4a) n'ont jamais porté `createrepo_c`.
   - Résultat `BOOTSTRAP_ARTIFACT_INPUTS`, sous la forme de `preparer-deb` : `{"uri":"oci://<dépôt>","digest":"sha256:…"}` (vérifié dans le dépôt). Le digest de l'image de bootstrap entre ainsi dans `resolvedDependencies`, comme les fermetures du deb (D15 de S4d1, mesuré).
   - `rpm -K` est gardé : c'est le seul contrôle ancré sur la clé de Rocky plutôt que sur une liste calculée par l'hôte. Mesuré sans root : 222 OK sur 222, deux fois. Sa durée propre n'est pas isolée : 28 s par passage entier.
2. **Écarts du script de la tâche avec `PREFETCH_FINAL`** : aucun n'a tourné dans un pod.
   - La liste vient d'un paramètre et est écrite dans un fichier de `/tmp`, au lieu d'un fichier livré par `kubectl exec`.
   - `SORTIE` est le chemin du workspace.
   - La variable `CLE_ROCKY`, « réglable pour le banc seulement », est retirée : chemin fixe de la clé dans l'image.
   - Contrôles des paramètres, sur le modèle de `prefetch-deb` :
     - URL sous `https://dl.rockylinux.org/vault/rocky/9.7/` ;
     - sha256 de 64 caractères hexadécimaux, taille en chiffres ;
     - forme de `source` ; cohérence de `dossier` ; empreinte de 40 caractères hexadécimaux.
   - Écriture du résultat ; contrôle de `repomd.xml` (question ci-dessous).
3. **L'`env` du `podTemplate` l'emporte sur celui des pas (lecture).**
   - Documentation de Tekton v1.15.5, la version en service (`tekton.sh`, vérifié dans le dépôt), `docs/podtemplates.md` lu au tag : les variables d'environnement du `podTemplate` d'un TaskRun ou d'un PipelineRun l'emportent sur celles des `steps` et du `stepTemplate`.
   - Le test 2 de l'admission (`admission.yaml` de la 08) interdit au `podTemplate` les volumes, `hostNetwork`, `hostUsers` et `imagePullSecrets`, mais pas `env` (lecture).
   - Conséquence possible, non mesurée : quiconque crée un PipelineRun dans `builds` pourrait remplacer les valeurs que les tâches signées reçoivent par variable, sans toucher à la signature. Pour `prefetch-deb` en service, ce sont `INSTANTANE`, `INRELEASE` et `LISTE`. Il pourrait aussi remplacer `PATH` ou ajouter `LD_PRELOAD` à toute tâche signée.
   - **À signaler au propriétaire, pas corrigé d'office** : le point dépasse M4 et touche la 08.
   - Pour `prefetch-rpm`, retenu par défaut sauf avis contraire : aucune valeur de contrôle passée par variable. Les paramètres seront écrits dans des fichiers par substitution de Tekton dans le script (`$(params.…)` dans un heredoc entre apostrophes), puis contrôlés. Cela ne ferme pas le cas `PATH` / `LD_PRELOAD`.
   - Taille à mesurer : la liste fait 39 938 octets (mesuré, `m4b-liste.txt`), à peu près le double de celle du deb (20 293 octets pour 162 lignes, colonnes 4 à 6 de `verrou-deb.txt`, recomptées), dont B15 a mesuré la relecture dans la provenance. Une liste de cette taille n'a jamais été passée en paramètre ni substituée dans un script.
4. **`publier-fermeture` inchangée**
   - Admission :
     - `limites-obligatoires` est en `Deny` depuis le 06/11/2026 à 19:26 UTC (README de la 08c) ;
     - `publier-fermeture` déclare des ressources vides et a réussi le 11/11/2026 dans les PipelineRuns de S4b (mesuré) ;
     - les limites de `config-defaults` lui sont donc appliquées (déduit).
   - Charge non mesurée : 318 Mo et 230 couches sous 512 Mi, contre 194 Mo et 167 couches pour le deb (mesuré, `s4b-deb.log`).
   - Chemins à « : » et « @ » du dossier `dir:` : l'image d'outils de `publier-fermeture` porte oras 1.3.6 (lecture de `tsa.sh`), la même version que l'hôte. Le banc de M2 a mesuré ces chemins avec `closure.sh`, pas avec `publier-fermeture`.
   - **À rejouer sur l'hôte avant tout** : la section d'envoi `oras push --oci-layout` de `publier-fermeture`, extraite de sa version signée, sur un arbre aux 230 vrais noms de [`m4b-final-arbre.txt`](m4b-final-arbre.txt). C'est le précédent de S4b. Deux poussées doivent donner le même digest.
   - `bom.json` absent : la tâche journalise une erreur sans effet sur l'envoi (mesuré pour le deb).
   - Repli si la section ou la charge ne tient pas : la tâche ne serait plus « inchangée », décision au propriétaire.
5. **Arbre publié préfixé par `depot/`.** `prefetch-rpm` écrit `fermeture/depot/…` et `publier-fermeture` publie `fermeture/`. L'arbre archivé de `final` est relatif à `depot/` : l'étape `comparaison` devra ajouter ce préfixe.
6. **Réseau**
   - `prefetch-rpm-sortie`, posée le 16/11/2026, sélectionne `tekton.dev/task=prefetch-rpm` (vérifié dans le dépôt). Tekton écrit ce label à partir du nom de la tâche (mesuré en J7 ; lecture du message du commit `1c41d2c`).
   - Pods de `final` au même label : vault 9.7 et Zot joints (mesuré).
   - Le chemin de `publier-fermeture` vers Zot est celui du deb (mesuré en S4b).
7. **Essai avant signature.**
   - `trusted-resources-verification-no-match-policy=fail` (mesuré, R10 de M4a) : aucun essai Tekton non signé n'est possible.
   - Proposé :
     - jouer le script extrait du gabarit rendu, d'abord au banc par dash ;
     - puis dans un pod d'essai runc au label `prefetch-rpm`, comme `final` ;
     - avant `SIGNER=1`.
   - C'est le levier « pod d'essai avant signature de toute tâche neuve », appliqué au script qui sera signé. Un accord pour le pod.
8. **Signature et liste revue.**
   - Cycle de S4a et S4b (vérifié dans `s4b.sh`, `signer_tache`) : signature versionnée par `SIGNER=1` (la clé des tâches n'est jamais lue) ; revue de `taches.yml` par le propriétaire dans un commit à part ; bundles `tekton/tasks/prefetch-rpm` et `tekton/pipelines/prefetch-rpm-sample-app`.
   - Écritures définitives dans Zot : aucun droit de suppression.
9. **Workspace et Zot.**
   - Workspace : 1 Gi demandé par `volumeClaimTemplate`, comme le deb (vérifié dans `s4b.sh`), pour 318 Mo.
   - Espace libre de Zot : à relever avant `taches`. Dernier relevé : 5 055 672 320 octets libres à la fermeture de M2 (`s1-fermeture.log`). Que Zot ne stocke qu'une fois les blobs déjà présents (rpm de `f235a98b…`, couches de l'image de bootstrap) est une lecture, non vérifiée.

## Ordre proposé, sans prédictions

1. `prealables_taches` (hôte, hors ligne) :
   - gabarits rendus, avec des références factices ;
   - script de la tâche extrait du gabarit, comparé à `PREFETCH_FINAL` (écarts du point 2 seulement) et joué au banc ;
   - section d'envoi de `publier-fermeture` sur les 230 vrais noms ;
   - espace libre de Zot (lecture).
2. `essai_tache` : pod d'essai runc, avec le script extrait du gabarit (point 7).
3. `verrou` et `publier` de M4a (ordre consigné).
4. `taches` : `SIGNER=1`, puis revue de `taches.yml`, puis bundles.
5. `rpm` : deux PipelineRuns, l'un après l'autre ; même digest attendu.
6. `comparaison` : fermetures tirées par digest, contre l'arbre de `final` (préfixe `depot/`).
7. `provenance` : cosign, sujet, `resolvedDependencies` (image de bootstrap, tâches, pipeline), paramètre `liste` relu.

Chaque écriture (Zot, cluster, `taches.yml`) a son accord nommé.

## Question posée

**`repomd.xml` attendu dans le gabarit signé ?**
- **Oui** : un paramètre de plus, `repomd` (`239a5a71…`), contrôlé par la tâche à la fin de son pas, avant `publier-fermeture`. Une fermeture dont l'index diffère de celui que mock a accepté n'est alors jamais publiée. Coût : tout changement de liste ou d'image demande un passage de `final` avant signature, pour mesurer la nouvelle valeur.
- **Non** : contrôle sur l'hôte seulement, à l'étape `comparaison`, après publication. Une fermeture fausse resterait écrite dans Zot, sans retrait possible.
- **Recommandation** (relue par le conseiller) : oui. `repodata` est le seul contenu de la fermeture qui n'est pas fixé par la liste. La valeur a été mesurée cinq fois, dans trois environnements (deux copies à l'essai, `m4b_mock_v2`, deux pods de `final`), et une écriture dans Zot ne se retire pas.
