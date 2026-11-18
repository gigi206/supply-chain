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
