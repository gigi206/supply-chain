# Brique 05, M5a : prédictions et résultats

Carte et décision : [m5-carte.md](m5-carte.md) (décision « Ok » du 18/11/2026 : M5a, tests R1 à R8 sans écriture dans Zot ; M5b, rejeu de zéro, à part).

## Note datée du 18/11/2026, écrite à 18:39:52 UTC : `m5.sh`, étape `prealables` préparée à sec, NON LANCÉE ; prédictions PR1 à PR10

**Fichiers** : [`m5.sh`](../m5.sh) (`f53b5830…`), [`m5-alterer.py`](../m5-alterer.py) (`8bc019dc…`), [`m5-reseau.spec`](../m5-reseau.spec) (`1dd1ad3b…`). Préparés sous l'accord permanent du 18/11. Seule `prealables` est écrite. Les étapes `temoin`, `alterer`, `fermeture`, `reseau`, `sans_kata`, `invariance` et `retirer` viendront après son passage, chacune avec ses prédictions.

**Ce que fait `prealables`**
- **Hôte, hors ligne** :
  - sept copies de l'arbre `entrees/` local (celui de `m4c.sh prealables`), par liens durs, une altération par copie ; chaque altération écrit un fichier neuf puis le renomme, pour ne jamais toucher l'inode partagé ;
  - preuves : empreinte de la source avant et après, et chaque copie ne diffère de la source que par l'objet voulu ;
  - le bloc de confrontation au verrou, tiré de `construire-rpm` signée, joué avec le rpm de l'image d'outillage (rootfs de `m5-sigmd5.sh`, `unshare -rnm chroot`), comme le pas l'appelle (`python3 -I - verrou depot`) ;
  - relevé de `rpm -i --test` sur la cible intacte et sur R4 ;
  - la section `%build` de `m5-reseau.spec`, jouée par `sh -e` sous `unshare -rn`.
- **Lecture, cluster et Zot** :
  - pipeline signée exportée de Zot, références des tâches, paramètres figés, liste revue ;
  - politiques de `builds` relues ;
  - aucun objet `m5-*` dans `builds` ;
  - les 13 objets de M5a rendus et admis à blanc côté serveur ;
  - enveloppes de l'artefact de M4c comptées.
- Rien n'est créé dans le cluster ni écrit dans Zot.

**Banc de la partie hôte** : copie de `m5.sh` arrêtée avant la lecture, préfixe `m5banc1`, journal hors du dépôt, puis archivé : [m5-prealables-hote-banc.log](m5-prealables-hote-banc.log). 15 OK du premier coup.
- Confrontation : `intacte`, `r4` et `r6` passent ; `r1`, `r2`, `r3` et `r5` sont refusées, chacune avec son message.
- `rpm -i --test` : la cible intacte passe (code 0) ; R4 est refusée (« does not verify: Payload SHA256 ALT digest: BAD »).
- Sonde : début et fin de `%build` imprimés, interface `lo` seule, connexion refusée (code 1).

**Ajout à la carte, signalé** : R7 a deux bras, deux pods d'essai Kata.
- **a**, sans label de tâche : le témoin depuis le pod doit joindre Zot ; la sonde de `%build` dit si mock coupe le réseau.
- **b**, au label `construire-rpm` : si mock ne coupe pas, c'est la seule mesure d'un refus pendant `%build`, par la politique du pod.

R4, R6 et R7 ont chacune trois issues : refus, acceptation, non mesuré. Leurs branches seront écrites dans les prédictions de leurs étapes, avant leur lancement.

**Prédictions de `prealables`**

| # | Prédiction | Confiance |
|---|---|---|
| PR1 | Partie hôte identique au banc : 7 copies conformes, source inchangée (`d3a610bb…`) ; confrontation : `intacte`, `r4`, `r6` passent, `r1`, `r2`, `r3`, `r5` refusées avec leur message | Haute : même code, banc |
| PR2 | `rpm -i --test` : intacte code 0, R4 code 1, « does not verify » (relevé) | Haute : banc |
| PR3 | Sonde : `lo` seule, connexion refusée, `sh -e` code 0 | Haute : banc |
| PR4 | Pipeline exportée de Zot : `sample-app-rpm`, tâches `preparer-rpm`, `construire-rpm`, `publier-image` ; bundles égaux à `PREPARER_REF` et `CONSTRUIRE_REF`, tous deux dans la liste revue | Haute : relue au tag `m4c` en `pipeline` (PL) |
| PR5 | Paramètres de `preparer` figés (commit, dépôt, trois entrées par digest) ; `construire` : `epoque` seule | Moyenne-haute : noms lus dans la tâche signée, valeurs contrôlées par `rendre_pipeline` de `m4c.sh` ; extraction jamais jouée sur le bundle exporté |
| PR6 | `construction-rpm-sans-sortie` relue comme en M4c ; aucune politique n'autorise de trafic à `construire-rpm` | Haute : M4c |
| PR7 | Aucun objet `m5-*` dans `builds` | Haute |
| PR8 | Les 13 objets admis à blanc : un PVC, neuf TaskRuns (dont `m5-sans-kata`, dont le refus vient à la création du pod, comme N7 de la 06), trois pods | Moyenne : aucun TaskRun isolé des tâches rpm jamais admis ; un pod Kata privilégié avec un PVC jamais admis (l'essai de M4c n'avait que des emptyDir) |
| PR9 | 4 enveloppes valides sur `07b7bd6f…` | Haute : `provenance` de M4c |
| PR10 | Code 0 ; moins de deux minutes | Moyenne |

**Après le passage** : PR8 non tenue, le motif du refus est compté (Pod Security, ValidatingAdmissionPolicy, Kyverno), jamais affiché ; l'objet est corrigé avant toute création, avec une note datée.

## Note datée du 18/11/2026, écrite à 18:42:01 UTC : premier passage de `prealables` arrêté par mon script ; correction, relance

**Premier passage** : 18:40:08 à 18:41:11 UTC, code 1 ([journal](m5-prealables-1.log)). 30 OK, puis un KO :
- toute la partie hôte, PR1 à PR3, passe comme au banc ;
- la lecture passe jusqu'aux objets rendus : pipeline, bundles, liste revue, paramètres figés, politiques, absence d'objets `m5-*` ;
- **le KO vient de mon attendu, pas du cluster** : le contexte de sécurité du conteneur des pods de R7 a les mêmes cinq valeurs que celui du pas signé, mais dans un autre ordre de clés (`yq` sur la tâche signée contre l'ordre du gabarit rendu dans `m4c.sh`) ;
- rien n'a été admis à blanc, et les enveloppes n'ont pas été comptées.

**Correction** (`m5.sh` = `3d629090…`) :
- comparaison en JSON trié des deux côtés ;
- relevé des politiques qui sélectionnent un pod sans label de tâche : le type n'est plus imprimé deux fois ;
- un dossier de banc hôte par passage (`banc-hote-<heure UTC>`), pour relancer sous le même préfixe sans rien purger. Les objets du cluster n'existent toujours pas.

Prédictions PR1 à PR10 inchangées. Relance de `prealables` sous `m5`.

**Erreur de procédure** : la correction a été commitée (`b17168f`) sans cette note, car la commande ne s'arrêtait pas sur l'échec de son script d'écriture (compte de OK faux : 30, et non 33). La note est ajoutée par le commit suivant, avant la relance.

## Note datée du 18/11/2026, écrite à 18:43:41 UTC : `prealables` passée (18:42:14 à 18:43:18 UTC, code 0), PR1 à PR10 tenues

[Journal](m5-prealables.log) : **45 OK, aucun KO**, en 64 s. Rien n'a été créé dans le cluster ni écrit dans Zot.

| # | Résultat |
|---|---|
| PR1 | Tenue : 7 copies conformes, source inchangée (`d3a610bb…`) ; `intacte`, `r4`, `r6` passent la confrontation, `r1`, `r2`, `r3`, `r5` refusées avec leur message, comme au banc |
| PR2 | Tenue : `rpm -i --test` sur R4, code 1, « does not verify: Payload SHA256 ALT digest: BAD » ; cible intacte, code 0 |
| PR3 | Tenue : `lo` seule, connexion refusée, code 0 |
| PR4 | Tenue : pipeline exportée de Zot, trois tâches, bundles égaux aux références, les deux dans la liste revue |
| PR5 | Tenue : paramètres de `preparer` figés, égaux aux références épinglées ; `construire` : `epoque` `1793229566` seule |
| PR6 | Tenue : `construction-rpm-sans-sortie` comme en M4c ; aucune politique n'autorise de trafic à `construire-rpm` |
| PR7 | Tenue : aucun objet `m5-*` |
| PR8 | Tenue : les 13 objets admis à blanc, dont `m5-sans-kata` et les deux pods Kata privilégiés de R7 avec le PVC |
| PR9 | Tenue : 4 enveloppes valides sur `07b7bd6f…` |
| PR10 | Tenue : code 0, 64 s |

**Relevés**
- Classe de stockage par défaut : `local-path` (`rancher.io/local-path`). Nœud de la zone build : `sc-build`, 29 916 549 507 octets de stockage éphémère allouable.
- Un pod sans label de tâche n'est sélectionné, dans `builds`, que par `builds-sans-internet` (Cilium). Le bras a de R7 doit donc joindre Zot, comme le témoin de N6 de la 06.
- Les PipelineRuns `m4c-rpm-1` et `m4c-rpm-2` sont gardés.

Suite : écrire les étapes `temoin`, `alterer`, `fermeture`, `reseau`, `sans_kata`, `invariance` et `retirer`, avec leur banc et leurs prédictions, avant tout lancement.

## Note datée du 18/11/2026, écrite à 18:48:06 UTC : étapes du cluster ajoutées à `m5.sh` à sec, NON LANCÉES ; prédictions des étapes du cluster

**Ajouté à `m5.sh`** (`5d8d8737…`, accord permanent du 18/11) : `banc_juges`, `preparer`, `alterer`, `fermeture`, `sans_kata`, `reseau`, `invariance` et `retirer`.
- Chaque objet porte le label `poc.test/jalon=m5`. Une garde d'absence précède chaque création, et rien n'est jamais purgé.
- `retirer` ne vise que ce label, jamais les PipelineRuns `m4c-rpm-*`.
- Aucun message de condition ni d'Event n'est affiché. Pour R8, seuls des motifs du message sont comptés.
- **Banc** `banc_juges` : [journal](m5-banc_juges.log), 5 OK. Les juges des constructions ont tourné sur des TaskRuns et des journaux fabriqués, un par issue : refus par la confrontation, accepté, refus dans mock, non mesuré (deux cas).
- Script de R7 rendu et contrôlé (`bash -n`). Son début, joué sous `unshare -rn` sur l'hôte, voit `lo` seule et une connexion refusée.

**Ordre** : `preparer`, `alterer`, `fermeture`, `sans_kata`, `reseau`, `invariance`, `retirer`.

**Prédictions**

| # | Prédiction | Confiance |
|---|---|---|
| PP1 | `preparer` : `True|Succeeded`, pod au label `preparer-rpm`, sans Kata ; résultats `CHAINS-GIT_*` et les trois `*_ARTIFACT_INPUTS` égaux aux références | Haute : même bundle qu'en `pipeline` (PL) ; admis à blanc (PR8) |
| AL1 | `alterer` : empreinte de `entrees/` sur le PVC égale à la source locale `d3a610bb…` | Moyenne-haute : l'essai de `preparer-rpm` a donné un arbre égal à celui de `prealables` (contenu, modes, types) ; l'empreinte n'a jamais été calculée dans le cluster |
| AL2 | 7 copies conformes, source inchangée | Haute : banc (PR1), même script |
| FE1 | Témoin `m5-intacte` : `True|Succeeded`, label `construire-rpm`, Kata ; écriture refusée, trois témoins TCP en échec ; rpm `864d55f4…` (M3), `DIGEST_CONSTRUIT` `07b7bd6f…` ; rien n'est publié | Haute : mêmes entrées et même époque que les deux PipelineRuns de M4c |
| FE2 | R1, R2, R3, R5 : `refus-confrontation`, avec les messages du banc, mock jamais lancé | Haute : PR1, même code, même rpm |
| FE3 | **R4** (payload altéré) : la confrontation passe, mock refuse (`refus-mock`). Barrière attendue dans le journal : rpm (« does not verify » ou « Payload SHA256 … BAD »), ou dnf (somme de contrôle du paquet contre `primary`). Lequel des deux vient en premier n'est pas prédit. Autres issues : **accepté**, à remonter comme constat, avec le sha256 du rpm contre `864d55f4…` ; **non mesuré**, échec avant mock | Moyenne-haute pour le refus : `rpm -i --test` le refuse (PR2) ; jamais joué dans mock |
| FE4 | **R6** (blob de l'image de bootstrap altéré) : la confrontation passe, mock refuse au chargement de l'image (`refus-mock`). Barrière attendue : une ligne de digest de l'image. Autres issues : **accepté**, dont un repli de mock sur un bootstrap fait de paquets (lignes « fallback » imprimées) : constat ; **non mesuré** | Moyenne : le chargement d'un `dir:` altéré n'a jamais été mesuré |
| SK1 | R8 : `False|PodAdmissionFailed`, aucun pod ; motif « PodSecurity » compté dans le message | Moyenne-haute : N7 de la 06, même contexte privilégié |
| RE1 | R7, bras a (sans label de tâche) : depuis le pod, connexion à Zot réussie (code 0) | Moyenne-haute : seule `builds-sans-internet` le sélectionne (relevé de `prealables`) ; témoin de N6 de la 06 |
| RE2 | R7, bras a, `%build` : début et fin de la sonde imprimés. Connexion : **refusée, interfaces `lo` seule** (mock coupe le réseau de `%build`), ou **réussie** (mock ne coupe pas, la politique du pod est la seule barrière, constat). Sans les marqueurs : **non mesuré** | Moyenne pour les marqueurs (mock hermétique d'une spec minimale jamais joué) ; aucun pari sur la coupure par mock |
| RE3 | R7, bras b (label `construire-rpm`) : connexion refusée depuis le pod ; refusée aussi pendant `%build` si les marqueurs sont imprimés | Haute : témoins de chaque build depuis M3 |
| RE4 | mock rc 0 dans les deux bras, `m5-reseau-1.0-1.noarch.rpm` produit (relevé) | Moyenne |
| IN1 | 4 enveloppes sur `07b7bd6f…` après les étapes ; aucun TaskRun du jalon ne publie | Moyenne-haute : S5a de la 06, aucune enveloppe nouvelle |
| RT1 | `retirer` : aucun objet du jalon restant ; PipelineRuns de M4c gardés | Haute |

**Durées** (non exigées) : `preparer` et `alterer`, quelques minutes ; `fermeture`, de l'ordre de 15 à 30 min (trois mock complets au plus, intacte, R4 et R6) ; `reseau`, deux mock hermétiques.

**Après le passage** : une prédiction non tenue est lue dans le journal avant toute correction. Une acceptation de R4, de R6 ou du bras a de R7 est un constat que je remonte, sans modifier de tâche signée.

## Note datée du 18/11/2026, écrite à 18:49:02 UTC : premier passage de `preparer` arrêté par mon attendu ; étape `preparer_relu` ajoutée

**Passage** : 18:48:14 à 18:48:27 UTC, code 1 ([journal](m5-preparer.log)) ; `alterer` n'a pas tourné.
- **Créés dans le cluster** : PVC `m5-entrees` et TaskRun `m5-preparer`, qui a réussi (`True|Succeeded`, pod au label `preparer-rpm`, sans Kata). Il a tiré 230 fichiers de fermeture rpm, 8 de fermeture applicative et 2 de packaging, et `go mod verify` a donné « all modules verified ».
- 5 OK, puis un KO **de mon attendu** : Tekton rend le résultat objet `FERMETURE_RPM_ARTIFACT_INPUTS` en JSON indenté, et je le comparais à une chaîne compacte. Ses deux valeurs, uri et digest `2a9e2ea7…`, sont celles attendues ; elles sont imprimées dans le journal.
- Les deux autres résultats objets n'ont pas été contrôlés.

**Correction** (`m5.sh` = `141c811a…`) :
- comparaison des résultats objets en JSON trié des deux côtés ;
- contrôles regroupés dans `verifier_preparer` ;
- étape **`preparer_relu`**, en lecture seule : elle relit le TaskRun existant et refait tous ses contrôles, sans rien recréer (garde d'absence).

PP1 sera jugée sur `preparer_relu`. Suite : `preparer_relu`, puis `alterer`.

## Note datée du 18/11/2026, écrite à 18:50:12 UTC : `preparer_relu` et `alterer` passées (18:49:09 à 18:49:50 UTC, code 0) ; PP1, AL1 et AL2 tenues

- **PP1 tenue** ([journal](m5-preparer_relu.log), 7 OK) : `m5-preparer` `True|Succeeded`, label `preparer-rpm`, sans Kata ; `CHAINS-GIT_URL`, `CHAINS-GIT_COMMIT` et les trois `*_ARTIFACT_INPUTS` (en JSON trié) égaux aux références. Relevé : Chains a signé ce TaskRun (`chains.tekton.dev/signed=true`).
- **AL1 tenue** ([journal](m5-alterer.log), 4 OK) : l'empreinte de `entrees/` remplie par `preparer-rpm` sur le PVC est `d3a610bb…`, égale à la source locale de `m4c.sh prealables`. 273 fichiers.
- **AL2 tenue** : 7 copies conformes, chacune ne diffère que par l'objet voulu ; empreinte de la source inchangée après les altérations.
- Relevé : le PVC `local-path` voit le disque du nœud, 16 874 396 kB utilisés sur 30 753 032.

Suite : `fermeture`.

## Note datée du 18/11/2026, écrite à 19:01:41 UTC : `fermeture` passée (18:50:25 à 19:00:41 UTC, code 0) ; FE1 à FE4 tenues

[Journal](m5-fermeture.log) : **21 OK, aucun KO**. Sept TaskRuns isolés de `construire-rpm` signée, sous Kata (label `construire-rpm`, nœud `sc-build`). Chacun a eu son écriture refusée sur les entrées (virtiofs en lecture seule) et ses quatre témoins réseau en échec (code 124), avant toute confrontation. Rien n'a été publié.

| Cas | Altération | Résultat | Barrière, d'après le journal |
|---|---|---|---|
| témoin | copie intacte | `True|Succeeded`, mock rc 0 en 46 s ; rpm `864d55f4…` (M3), src.rpm `c802e60a…`, `DIGEST_CONSTRUIT` `07b7bd6f…` (M4c) | — |
| R1 | rpm substitué | `False|StepFailed`, mock jamais lancé | confrontation : « sigmd5 différent du verrou : zlib-1.2.11-40.el9.x86_64.rpm » |
| R2 | fichier en trop | idem | confrontation : « 1 objet(s) hors du verrou … ['m5-en-trop.rpm'] » |
| R3 | rpm retiré | idem | confrontation : « 1 rpm du verrou absent(s) » |
| R4 | payload altéré, en-tête intact | confrontation **passée** ; mock rc 30 en 13 s | **dnf** : « Package "zlib-1.2.11-40.el9.x86_64" from local repository "offline" has incorrect checksum », puis « Some packages from local repository have incorrect checksum » ([journal du pod](m5-fermeture-r4-pod.log)). Ce refus vient avant rpm. |
| R5 | `manifest.json` altéré | `False|StepFailed`, mock jamais lancé | confrontation : « manifest.json du dossier dir: différent du pull_digest » |
| R6 | blob de l'image de bootstrap altéré | confrontation **passée** ; mock rc 1 en 124 s | **copie de l'image par podman** : « Copying blob sha256:22495746… », « Digest did not match », pull réessayé, puis `PodmanError: Image pull failed`. Aucun repli sur un bootstrap fait de paquets (0 ligne « falling back to chroot installation », [journal du pod](m5-fermeture-r6-pod.log)). |

- **FE1 tenue** : le témoin redonne le rpm de M3 et l'artefact de M4c, depuis une copie faite par le même mécanisme que les copies altérées.
- **FE2 tenue** : R1, R2, R3 et R5 sont refusées par la confrontation au verrou, avec les messages du banc, et mock n'est jamais lancé.
- **FE3 tenue, branche refus** : la barrière de R4 est **dnf**, qui compare la somme de contrôle du paquet à `primary` (écrit par `createrepo_c` en M4b), et non rpm. La confrontation au verrou ne voit pas ce cas (mesure hors ligne du point 1) ; dnf le voit, dans mock. Ce refus dépend de `repodata/`, que la confrontation ne contrôle pas : un `repodata/` refait pour le rpm altéré n'est pas testé ici. Rpm (digest du payload, PR2) reste une barrière derrière, non atteinte.
- **FE4 tenue, branche refus** : la barrière de R6 est la vérification du digest du blob par la copie de l'image. Le `manifest.json` intact fixe le digest attendu.

**Réserve** : R4 n'a pas de second test avec un `repodata/` cohérent avec l'altération. Si `repodata/` est refait, la seule barrière restante, déduite et non mesurée dans mock, est la vérification du digest du payload par rpm (refusée hors ligne, PR2).

Suite : `sans_kata`, puis `reseau`.

## Note datée du 18/11/2026, écrite à 19:04:40 UTC : `sans_kata`, `reseau`, `invariance` et `retirer` passées (19:01:48 à 19:03:47 UTC, code 0) ; bilan : M5a tenu, avec un constat

**`sans_kata`** ([journal](m5-sans_kata.log), 2 OK) — **SK1 tenue**. `m5-sans-kata` donne `False|PodAdmissionFailed` en 2 s, et aucun pod n'est créé. Motifs comptés dans le message, qui n'est pas affiché : PodSecurity 1, privileged 1, ValidatingAdmissionPolicy 0, kyverno 0. C'est Pod Security qui refuse, comme N7 de la 06.

**`reseau`** ([journal](m5-reseau.log), 2 OK) : deux pods d'essai Kata privilégiés, image d'outillage, entrées intactes en lecture seule. mock rc 0 dans les deux bras (31 s et 40 s), `m5-reseau-1.0-1.noarch.rpm` produit : **RE4 tenue**.

| Bras | Depuis le pod | Pendant `%build` (mock `--isolation=simple`) |
|---|---|---|
| a, sans label de tâche | interfaces `lo eth0`, connexion à Zot **réussie** (code 0) | marqueurs de début et de fin présents ; interfaces `lo eth0` ; connexion à Zot **réussie** (code 0) |
| b, label `construire-rpm` | connexion refusée (code 124) | marqueurs présents ; interfaces `lo eth0` ; connexion **refusée** (code 124) |

- **RE1 tenue** : depuis le bras a, Zot est joint.
- **RE2, branche « réussie »** : les marqueurs prouvent que `%build` a tourné, et la connexion y réussit. **mock, en `--isolation=simple`, ne coupe pas le réseau de `%build`** : le paquet voit `eth0` et joint Zot.
- **RE3 tenue** : sous le label `construire-rpm`, la connexion est refusée depuis le pod comme depuis `%build`. C'est la première mesure d'un refus pendant `%build`, et non avant mock.

**CONSTAT** : sur la voie rpm, **une seule barrière** coupe le réseau pendant la construction, la NetworkPolicy `construction-rpm-sans-sortie` au niveau du pod. Elle ne s'applique qu'au label `tekton.dev/task=construire-rpm`, que Tekton pose depuis le nom de la tâche. La voie deb en a deux : la politique du pod et sbuild `--chroot-mode=unshare`, qui ne laisse que `lo` (N6 de la 06). Ce constat ne change ni la tâche signée ni la politique. Une seconde barrière est une décision qui te revient ; rien n'a été essayé dans ce sens.

**`invariance`** ([journal](m5-invariance.log), 2 OK) — **IN1 tenue**. Toujours 4 enveloppes sur `07b7bd6f…`. Chains a signé les huit TaskRuns qui ont eu un pod (`chains.tekton.dev/signed=true`), aucun n'a publié ; `m5-sans-kata` porte `failed`. Les PipelineRuns de M4c sont gardés.

**`retirer`** ([journal](m5-retirer.log), 2 OK) — **RT1 tenue**. 18 objets au label `poc.test/jalon=m5` supprimés (TaskRuns, pods, PVC), plus aucun ensuite ; PipelineRuns de M4c gardés ; rien n'est retiré de Zot. Les dossiers de travail de l'hôte restent sous `~/.cache/supply-chain-poc/08/travail/m5-05` et `m5banc1-05`.

## Bilan de M5a

| # | Test | Barrière qui refuse (mesurée) | Témoin accepté |
|---|---|---|---|
| R1 | rpm substitué | confrontation au verrou de `construire-rpm` (sigmd5) | copie intacte : rpm de M3, artefact `07b7bd6f…` |
| R2 | fichier en trop | confrontation (objet hors du verrou) | idem |
| R3 | rpm retiré | confrontation (rpm absent) | idem |
| R4 | payload altéré, en-tête intact | **pas la confrontation** (sigmd5 stocké inchangé) ; dnf dans mock, « incorrect checksum » contre `primary` | idem |
| R5 | `manifest.json` de l'image de bootstrap altéré | confrontation (`pull_digest`) | idem |
| R6 | blob de l'image de bootstrap altéré | copie de l'image dans mock, « Digest did not match », sans repli | idem |
| R7 | connexion réseau pendant `%build` | NetworkPolicy du pod seule ; **mock ne coupe pas** | bras a : connexion réussie, depuis le pod et depuis `%build` |
| R8 | `construire-rpm` sans Kata | Pod Security, `PodAdmissionFailed`, aucun pod | témoin de R1 sous Kata |

**M5a tenu** : chaque altération est refusée et chaque témoin est accepté, conformément au critère du tableau des jalons. Prédictions PR1 à PR10, PP1, AL1, AL2, FE1 à FE4, SK1, RE1 à RE4, IN1 et RT1 tenues. RE2 a pris la branche « réussie », écrite d'avance.

**Réserves**
- **R4** : son refus dépend de `repodata/`, que la confrontation ne contrôle pas. Avec un `repodata/` refait pour le rpm altéré, la dernière barrière serait la vérification du payload par rpm. Elle est mesurée hors ligne seulement (PR2), pas dans mock.
- **R7** : la coupure pendant `%build` repose sur la seule politique du pod (constat ci-dessus).
- Les tests ont été lancés par des TaskRuns isolés et des pods d'essai, jamais par la pipeline. Les deux pods de R7 sont des pods d'essai : ce ne sont pas des TaskRuns de `construire-rpm`.
- Les réserves de M4c demeurent : image d'outillage hors plateforme, BUILDTIME non expliqué, porte sans tâche rpm, vérification par clé.

Suite : M5b (rejeu de zéro, pas avant le 28/11), sur sa propre carte.
