# Diagnostic du blocage de `kubectl exec` sous Kata : prédictions (écrites le 10/11/2026, terminées à 18:26 UTC, avant toute exécution)

Le script est [`diag-exec-kata.sh`](../diag-exec-kata.sh). **Rien n'a été lu ni écrit dans le cluster ou les VM pour ce diagnostic.**

## Demande et accord

- **Demande du propriétaire** : « il faut trouver ce qu'il se passe », à 18:21:02 UTC (transcription).
- **Avec un accord nommé pour chaque étape** :
  - `pod` : un pod Kata privilégié, UID 1000, sans label, image d'essai de s1b, dans `builds` sur sc-build. Le pod est supprimé à la fin. Durée d'environ 10 min au plus.
  - `noeud` : lecture par ssh sur la VM sc-build, dans la fenêtre horaire de la mesure `instantane`. Sont lus `containerd.log` de RKE2 et le journal système, sur des lignes filtrées. Les lignes `jeton|token` sont retirées, et chaque ligne est coupée à 300 caractères. Rien n'est modifié sur la VM.

## Ce qui est déjà mesuré

Résultats de la sonde de S3 ([`s3-sonde.log`](s3-sonde.log)) :
- **Sous Kata 4.3.1**, 1, 8 et 64 Mio passent par l'entrée standard de `kubectl exec`.
- **À 512 Mio**, le pod reçoit tout, mais l'exec ne rend pas la main en 120 s, en WebSocket comme en SPDY.
- **Sous runc**, sur le même nœud, 512 Mio passent en 3,6 s.
- **Les builds de S3 passent** en morceaux de 64 Mio.

## Lectures faites avant ces prédictions

### Code de Kata 4.3.1, lu au tag sur GitHub, hors du dépôt

Dans le shim runtime-rs (`process.rs`, `container_io.rs`) :
- un exec est tenu pour terminé quand ses copies de **stdout et stderr** sont finies, puis sur `wait_process` auprès de l'agent ;
- la copie de **stdin** n'entre pas dans cette attente ;
- le shim garde un descripteur d'écriture sur la FIFO de stdin, `stdin_w`, jusqu'à `CloseIO`. Il ne voit donc la fin de stdin qu'après `CloseIO`.

Dans l'agent (`rpc.rs`) :
- chaque écriture de stdin et chaque lecture de stdout prend le verrou du bac à sable pour trouver le processus ;
- après la fin du processus, la lecture de stdout attend 500 ms au plus le reste des données.

### Tickets de Kata

- **#9071** (stdout perdu après un exec) : corrigé par #12376, fusionné le 09/02/2026. La correction est donc dans 4.3.1, publiée le 21/10/2026.
- **#11747** (stdin bloqué sur un exec non interactif) : fermé.
- **#9186** (perte d'E/S par l'agent) : ouvert.

**Aucun ticket trouvé** ne décrit notre cas : un gros stdin, des octets tous reçus, et un exec qui ne rend pas la main.

### Où se trouve la cause

Le blocage est entre le shim Kata et l'agent, ou entre containerd et le shim. Sous runc, le chemin apiserver, kubelet et containerd est le même, et il passe. **La cause n'est pas connue.**

## Prédictions

| # | Mesure | Prédit | Confiance |
|---|---|---|---|
| G1 | taille | 128 Mio passe, code 0 | faible |
| G2 | taille | 256 Mio échoue au délai, avec tous les octets reçus | faible |
| G3 | duree | 32 Mio envoyés lentement sur environ 90 s passent, code 0 : la durée seule ne bloque pas | faible |
| G4 | instantane | À 100 s, le fichier fait 536 870 912 octets dans le pod. `head` et le `sh` de l'exec n'y existent plus ; seul `sleep` reste, avec le shell du relevé | moyenne : le fichier était complet dans la sonde |
| G5 | instantane | À 100 s, kubectl est vivant sur l'hôte, son entrée standard ouverte et en fin de fichier ; code final 124 | haute (déjà vu deux fois) |
| G6 | noeud | Aucune prédiction sur le contenu : le niveau de journal du shim et de containerd sur sc-build n'est pas connu | — |

**Lecture prévue**
- **Si G4 tient** (le processus est fini, l'exec ne rend pas la main) : l'attente porte sur la fin de stdout, sur `wait_process`, ou sur le retour vers containerd.
- **Si `head` vit encore avec le fichier complet** : le processus n'a pas vu sa fin, et l'attente est dans l'invité.
- **Si G3 est réfutée** : la durée suffit, et la piste d'un délai d'inactivité ou d'un minuteur prend le dessus sur celle de la taille.

**Ce que ce diagnostic ne fera pas** :
- activer le mode débug de Kata, ce qui serait un changement de la plateforme ;
- lire les journaux de l'agent dans l'invité ;
- ouvrir un ticket chez Kata. Ce serait une action publique, à décider avec le propriétaire.

## Résultat de l'étape pod (10/11/2026, 18:27:44 à 18:38:22 UTC)

Accord : « Oui, lance pod », à 18:27:39 UTC (transcription). Lancée sous bash, code de sortie relevé : **0**. Journal : [`diag-exec-pod.log`](diag-exec-pod.log). Pod Kata prêt à 18:27:49 UTC, supprimé à la fin, absent à 18:38:27 UTC.

| Mesure | Résultat |
|---|---|
| 128 Mio à plein débit | code 124 au délai de 150 s ; **134 217 728 octets reçus** (tout) |
| 256 Mio à plein débit | code 124 au délai de 150 s ; **268 435 456 octets reçus** (tout) |
| 32 Mio en 32 envois espacés de 2,8 s | **code 0** en 89,9 s ; tout reçu |
| 512 Mio, relevé à 100 s (18:36:02 UTC) | fichier complet dans le pod ; kubectl vivant sur l'hôte, entrée standard ouverte en fin de fichier ; code final 124 au délai de 240 s, tout reçu |

| # | Résultat |
|---|---|
| G1 | **Réfutée.** 128 Mio bloque déjà. Le seuil se situe entre 64 Mio (passé en S3) et 128 Mio |
| G2 | **Tenue.** 256 Mio échoue au délai, avec tous les octets reçus |
| G3 | **Tenue.** 32 Mio étalés sur 90 s passent : la durée seule ne bloque pas, la quantité si |
| G4 | **Non mesurée, défaut du script.** Seule la première ligne s'est affichée (`processus 1 état S : sleep 7200`). Le filtre `grep -v` a vu un octet non textuel et a remplacé la suite par « binary file matches » : il fallait `grep -a`. On ne sait donc pas si `head` et le `sh` de l'exec vivaient encore |
| G5 | **Tenue.** kubectl vivant à 100 s, entrée standard ouverte en fin de fichier (position 536 870 912), code final 124 |

**Lecture, à ce stade**
- Le blocage dépend de la **quantité de données par exec**, entre 64 et 128 Mio, et non de la durée.
- Les octets arrivent toujours en entier : c'est la fin de l'exec qui ne remonte pas.
- La fenêtre de l'étape `noeud` est gardée : de 18:34:22 à 18:38:22 UTC.

## Étape releve : préparée à sec (18:39 UTC), NON LANCÉE

L'étape `releve` corrige G4. Elle copie 128 Mio en arrière-plan ; cette taille bloque, c'est mesuré. Le délai est de 120 s.

À 60 s, l'étape relève :
- dans le pod : la taille du fichier, et pour chaque processus son pid, son état, sa ligne de commande et ses descripteurs 0 à 2 ;
- sur l'hôte : l'entrée standard de kubectl.

Le relevé brut est gardé sur l'hôte et affiché avec `grep -a`. Le relevé des processus a été essayé sur l'hôte seul, sur ses propres processus. Le pod est supprimé à la fin.

**Cause probable de la troncature** : les lignes contiennent « état », en UTF-8. Le script tourne sous `LC_ALL=C`, où GNU grep traite les octets non ASCII comme binaires. Ce n'est pas vérifié sur le relevé perdu. Le nouveau relevé retire les caractères non imprimables des lignes de commande.

L'étape `noeud` prend désormais sa fenêtre par `FENETRE` : `instantane`, la mesure de 512 Mio (18:34:22 à 18:38:22 UTC, par défaut), ou `releve`.

| # | Prédit | Confiance |
|---|---|---|
| G4 (releve) | À 60 s, le fichier est complet (134 217 728 octets) ; `head` et le `sh` de l'exec n'existent plus dans le pod ; seuls `sleep` et le shell du relevé restent | moyenne |
| G7 | kubectl vivant à 60 s, entrée standard en fin de fichier ; code final 124 | haute (G5) |

## Résultat des étapes releve et noeud (10/11/2026, 18:41:06 à 18:43:19 UTC)

Accord : « Oui, releve puis noeud », à 18:41:01 UTC (transcription). Les deux étapes sont lancées sous bash, code **0** chacune. Journaux : [`diag-exec-releve.log`](diag-exec-releve.log) et [`diag-exec-noeud.log`](diag-exec-noeud.log) (fenêtre de 18:41:12 à 18:43:12 UTC).

### releve (128 Mio, relevé à 60 s, 18:42:12 UTC)

- Le fichier est complet dans le pod : 134 217 728 octets.
- Il ne reste que deux processus dans le conteneur : `sleep 7200` (pid 1) et le `sh` du relevé lui-même (pid 5). **Le `sh` et le `head` de l'exec ont disparu.**
- kubectl est vivant sur l'hôte, entrée standard en fin de fichier. Il sort en code 124 au délai de 120 s.

| # | Résultat |
|---|---|
| G4 | **Tenue** : le processus de l'exec est fini, et l'exec ne rend pas la main |
| G7 | **Tenue** |

### noeud (journal système de sc-build, identifiant `kata`, et `containerd.log` de RKE2)

Pour l'exec `204b7a67…` :
- **18:41:12** : le shim ouvre les FIFO et lance ses copies stdin, stdout et stderr.
- **18:41:25** :
  - `run_io_copy[Stdin]: stop to copy stream length 134217728` : le shim a passé les 128 Mio à l'agent, en 13 s ;
  - les copies stdout et stderr se terminent (longueur 0) ; `end wait group for io` ;
  - `end wait process exit code 0` ;
  - le shim émet `TaskExit` pour cet exec, avec le statut 0 ;
  - à la même seconde, containerd écrit `Container exec "204b7a67…" stdin closed`.
- Aucune ligne de containerd au niveau info sur cet exec ensuite, jusqu'à la suppression du pod à 18:43:12.

**G6** : aucune prédiction n'avait été faite. Le journal du shim est au niveau info et suffit à suivre l'exec.

**Lecture**
- **Le shim Kata et l'agent ont fini leur travail en 13 s.** Données transmises, processus fini, fin signalée à containerd.
- **Le blocage est en aval du shim**, dans la remontée de la fin de l'exec : flux de containerd (serveur de flux de CRI), kubelet, apiserver ou kubectl. Les 107 s suivantes n'ont laissé aucune trace au niveau info.
- **Ce qui reste inexpliqué** :
  - pourquoi la même remontée passe sous runc à 512 Mio ;
  - pourquoi elle dépend de la quantité sous Kata.
- **Bruit relevé, sans lien établi** : `failed to connect agent-log` à 18:41:20. Le shim n'a pas joint le port de journal de l'agent (1025). Le journal de l'agent n'est donc pas transmis.

## Additif du 18:48 UTC : correction de lecture, et étape croise préparée à sec, NON LANCÉE

**Correction de lecture** : « le blocage est propre à Kata » n'est pas établi. La comparaison runc/Kata change deux choses à la fois, le runtime et la vitesse de lecture du pod (environ 150 Mo/s sous runc, 10 Mo/s sous Kata). Sous Kata, kubectl a tout envoyé bien avant que le pod ait tout lu, et des centaines de Mo restent en attente dans la chaîne. Ce cas n'a jamais été mesuré sous runc. De même, « la quantité compte, pas la durée » est trop fort : l'envoi lent ne portait que sur 32 Mio, sous les 64 Mio qui passent. **La règle d'exploitation reste vraie** : sous Kata, un gros fichier ne passe pas par l'entrée standard de `kubectl exec`.

**Étape `croise`**, un seul exec par mesure, 128 Mio, délai de 150 s :
- **(a)** pod runc `restricted`, envoi à plein débit. Le pod lit lentement : 128 fois `dd bs=1M count=1 iflag=fullblock` suivi de `sleep 0.1`, soit environ 10 Mio/s.
- **(b)** pod Kata, envoi lent : 1 Mio toutes les 0,2 s, soit environ 5 Mio/s, sous le débit du pod. Le pod lit à plein débit (`head -c`).

**Vérifications hors ligne**
- `racine.tar` (`f8f221ca…`) contient GNU coreutils 9.7-3 (`dd`, `sleep`, `timeout`).
- La boucle de lecture a été essayée sur l'hôte sur 8 Mio, avec le `dd` de l'hôte : octets identiques.

| # | Prédit | Confiance |
|---|---|---|
| G8 | (a) bloque au délai sous runc, tous les octets reçus : la quantité en attente suffit, hors de Kata | faible |
| G9 | (b) passe sous Kata, code 0 : sans données en attente, 128 Mio ne bloquent pas | faible |

**Lecture prévue**
- **G8 et G9 tenues** : la cause est la quantité de données en attente dans la chaîne de flux, et Kata n'y joue que par sa lenteur.
- **G8 réfutée et G9 tenue** : il faut à la fois Kata et des données en attente.
- **G9 réfutée** : c'est la taille totale sous Kata qui compte.

La bisection sur le nœud (`crictl exec`, puis `ctr task exec`) viendra ensuite, selon le résultat, avec un accord à part.

## Résultat de l'étape croise (10/11/2026, 18:54:38 à 18:58:13 UTC)

Accord : « Continue la prochaine étape », à 18:54:30 UTC (transcription). La réponse est **consignée comme une interprétation** : un accord sur l'étape `croise`, la seule proposée dans la question précédente. Lancée sous bash, code **0**. Journal : [`diag-exec-croise.log`](diag-exec-croise.log). Les deux pods sont supprimés ; plus aucun à 18:58:23 UTC.

| # | Résultat |
|---|---|
| G8 | **Tenue.** (a) runc avec lecture lente : code 124 au délai de 150 s ; 134 217 728 octets reçus, sha256 conforme |
| G9 | **Tenue.** (b) Kata avec envoi lent : code 0 en 26,6 s, tout reçu |

**Étape `croise`** (18:54:38 à 18:58:13 UTC, code 0) :
- **(a) runc, lecture lente dans le pod** : code 124 au délai de 150 s, alors que les 134 217 728 octets sont reçus et que le sha256 est conforme. **Le blocage se reproduit hors de Kata.**
- **(b) Kata, envoi lent** (environ 5 Mio/s) : **code 0 en 26,6 s**, tout reçu.

**Kata n'est pas la cause.** L'exec ne rend pas la main quand une grande quantité de données d'entrée attend dans la chaîne de flux (kubectl, apiserver, kubelet, containerd) parce que le pod la lit moins vite qu'elle n'arrive. Le processus finit, et la fin de l'exec ne remonte pas. Kata n'y joue que par son débit plus faible (environ 10 Mo/s), qui crée cette attente. Le maillon exact de la chaîne n'est pas identifié. Aucun ticket Kubernetes, containerd ou Kata trouvé ne décrit ce cas.

**Recherche** : aucun ticket ne correspond exactement à ce cas. Les plus proches (Kubernetes #112834 et #124571, sur des données perdues dans un exec) ne décrivent pas un exec qui ne rend pas la main.

**Suite possible** : une bisection sur le nœud, avec un accord à part. `crictl exec` contourne l'apiserver et kubelet ; `ctr task exec` contourne en plus CRI.

## Étape bisection : préparée à sec (19:38 UTC), NON LANCÉE

Demande : « Prépare », à 19:37:09 UTC (transcription), en réponse à la question sur la bisection sur le nœud.

**Mise en place**
- Un pod runc `restricted` : l'étape `croise` a montré que runc reproduit le blocage.
- Sur la VM sc-build : ssh, `sudo sh -s`, script passé par l'entrée standard de ssh. Aucun fichier n'est écrit sur la VM.
- Trois exec dans le conteneur du pod, chacun avec 128 Mio tirés de `/dev/urandom` sur le nœud et un délai de 150 s :

| Mesure | Chemin | Lecture dans le pod |
|---|---|---|
| B1 | `crictl exec -i` : serveur de flux CRI de containerd, sans apiserver ni kubelet | lente (128 × 1 Mio, `sleep 0.1`) |
| B2 | `crictl exec -i` (témoin) | rapide (`head -c`) |
| B3 | `ctr -n k8s.io task exec` : API de tâches de containerd et FIFO, sans CRI | lente |

- Après chaque exec, on relève les octets reçus, puis on supprime le fichier. Le pod est supprimé à la fin.
- Outils et socket repris de `08-trust-plane/distro.sh` (variante RKE2), passés tels quels au script distant.

**Essai à sec** : le script distant a tourné sur l'hôte sous `dash`, avec des `crictl` et `ctr` factices, 2 Mio et 2 envois. Les trois mesures se sont déroulées, et la quantité reçue a été relevée.

| # | Prédit | Confiance |
|---|---|---|
| B2 | passe, code 0 | haute : lecture rapide, comme à 512 Mio sous runc |
| B1 | bloque au délai, tous les octets reçus : le maillon est dans le serveur de flux CRI de containerd ou en dessous | faible |
| B3 | passe, code 0 : le chemin des tâches de containerd et des FIFO n'est pas en cause | moyenne |

**Lecture prévue**
- **B1 bloque et B3 passe** : le maillon est le serveur de flux CRI de containerd.
- **B1 passe** : le maillon est dans kubelet, l'apiserver ou kubectl.
- **B3 bloque aussi** : le maillon est dans containerd, sous CRI, ou dans le shim runc.

