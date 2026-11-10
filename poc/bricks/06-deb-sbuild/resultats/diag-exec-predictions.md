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

## Résultat de l'étape bisection (10/11/2026, 19:41:09 à 19:41:38 UTC)

Accord : « Oui », à 19:41:04 UTC (transcription), en réponse à « Je lance la bisection ? ». Lancée sous bash, code **0**. Journal : [`diag-exec-bisection.log`](diag-exec-bisection.log). Le pod est supprimé ; plus aucun pod `diag` ensuite.

| # | Résultat |
|---|---|
| B1 | **Réfutée.** `crictl exec` avec lecture lente : code 0 en 13 273 ms, 134 217 728 octets reçus |
| B2 | **Tenue.** Code 0 en 387 ms |
| B3 | **Tenue.** `ctr task exec` avec lecture lente : code 0 en 13 393 ms |

**Bisection sur le nœud** (19:41:09 à 19:41:38 UTC, code 0 ; pod runc, 128 Mio tirés de `/dev/urandom` sur sc-build) :
- **B1** : `crictl exec`, lecture lente, **code 0 en 13,3 s** ;
- **B2** : `crictl exec`, lecture rapide, code 0 en 0,4 s ;
- **B3** : `ctr task exec`, lecture lente, code 0 en 13,4 s.

Tous les octets sont reçus dans les trois cas. **containerd, son serveur de flux CRI et le shim ne sont pas en cause** : la même lecture lente, qui bloque par `kubectl exec`, passe par `crictl exec` (crictl 1.35.0, containerd 2.2.7-k3s1). **Le maillon fautif est en amont, dans kubelet, l'apiserver ou kubectl**, et leur relais du flux. Il n'est pas encore identifié.

## Étape amont : préparée à sec (19:44 UTC), NON LANCÉE

Demande : « Prépare », à 19:43:19 UTC (transcription).

**Mise en place**
- Un pod runc `restricted`, et le même exec qu'en `croise` (a) : 128 Mio, lecture lente dans le pod, délai de 150 s.
- **C1** : kubectl de l'hôte. C'est le témoin de la fenêtre.
- **C2** : kubectl de sc-confiance (`D_KUBECTL` de `distro.sh` : binaire de RKE2 et `rke2.yaml`, utilisé et jamais lu), avec 128 Mio tirés de `/dev/urandom` sur sc-confiance. C2 retire de la chaîne le poste, son réseau vers les VM et le client de l'hôte (1.35.10). Il garde l'apiserver et kubelet.
- **Journaux de la fenêtre** : kubelet sur sc-build (`kubelet.log` de RKE2) et kube-apiserver sur sc-confiance (`/var/log/pods`). On garde les lignes qui citent exec, flux, websocket, spdy, upgrade, proxy, timeout ou stdin. Les lignes `jeton|token` sont retirées, et chaque ligne est coupée à 300 caractères.
- Rien n'est écrit sur les VM.

**Essais à sec** : les deux filtres de fenêtre ont tourné sur l'hôte sous `dash`, sur de faux journaux au format de klog et des journaux de pods de CRI. Seules les lignes de la fenêtre et du jour sont gardées.

| # | Prédit | Confiance |
|---|---|---|
| C1 | bloque au délai, tous les octets reçus | haute (`croise`) |
| C2 | bloque aussi : le maillon est dans l'apiserver ou kubelet, pas sur le poste | faible |
| C3 | aucune prédiction sur les journaux : la verbosité de kubelet et de l'apiserver n'est pas connue | — |

**Lecture prévue**
- **C2 passe** : le maillon est sur le poste. C'est soit kubectl 1.35.10, soit le réseau entre l'hôte et les VM.
- **C2 bloque** : le maillon est dans l'apiserver ou kubelet. Les journaux diront peut-être lequel.

## Résultat de l'étape amont (10/11/2026, 19:47:37 à 19:52:40 UTC)

Accord : « Oui », à 19:47:30 UTC (transcription), en réponse à « Je lance l'étape amont ? ». Lancée sous bash, code **0**. Journal : [`diag-exec-amont.log`](diag-exec-amont.log). Le pod est supprimé.

| # | Résultat |
|---|---|
| C1 | **Tenue.** Code 124 au délai, 134 217 728 octets reçus |
| C2 | **Tenue.** Code 124 au délai, 134 217 728 octets reçus |
| C3 | Aucune ligne utile dans les journaux de kubelet et de kube-apiserver pour la fenêtre |

**Étape amont** (19:47:37 à 19:52:40 UTC, code 0 ; pod runc, 128 Mio lus lentement dans le pod) :
- **C1** (kubectl de l'hôte, 1.35.10) : code 124 au délai de 150 s, tout reçu ;
- **C2** (kubectl de sc-confiance, 1.35.9+rke2r1, données tirées sur sc-confiance) : **code 124 au délai, tout reçu**.

**Le poste, son réseau vers les VM et sa version de kubectl sont hors de cause. Avec la bisection, le maillon est situé dans l'apiserver ou kubelet**, dans leur relais du flux d'exec, entre kubectl et le serveur de flux de containerd. Les journaux de kubelet et de kube-apiserver de la fenêtre ne disent rien de cet exec à leur verbosité actuelle. Kubelet n'a écrit qu'une ligne, sur la durée de démarrage du pod, sans rapport.

**Pour aller plus loin** :
- appeler l'API d'exec de kubelet directement, sans l'apiserver. Il faudrait le certificat client de l'apiserver vers kubelet, un secret à utiliser sans le lire ;
- ou monter la verbosité des journaux. C'est un changement de la plateforme.

L'une et l'autre demandent une décision du propriétaire.

## Étape kubelet : préparée à sec (19:56 UTC), NON LANCÉE

Demande : « Prépare l'exec », à 19:54:00 UTC (transcription), en réponse à « exec direct sur kubelet, ou journaux plus détaillés ».

### Mise en place

**Client.** L'exec passe directement par l'API de kubelet de sc-build, port 10250, sans apiserver. Il part de sc-confiance avec [`diag-exec-kubelet.py`](../diag-exec-kubelet.py) :
- client WebSocket `v5.channel.k8s.io`, écrit pour l'occasion, bibliothèque standard de Python seule. **Rien n'est installé.**
- script passé par l'entrée standard de ssh ; rien n'est écrit sur la VM.

**Identité.** Le client prend celle de l'apiserver auprès de kubelet : son certificat client.
- Les chemins sont lus dans les arguments de kube-apiserver. À défaut, ce sont les chemins par défaut de RKE2 (`server/tls/client-kube-apiserver.crt` et `.key`).
- Le script vérifie que ces fichiers sont lisibles. Il les utilise pour le TLS, sans jamais les afficher.

**Vérification du certificat de kubelet.** Comme l'apiserver, le client ne vérifie pas le certificat de kubelet. Le contrôle CIS 1.2.5 est en échec dans `rke2-cis.log` (08b) : `--kubelet-certificate-authority` n'est pas posé.

**Mesures.** Un pod runc `restricted`. Deux exec de 128 Mio tirés sur sc-confiance, chacun avec un délai de 150 s :
- **K2** : lecture rapide. C'est le témoin du client.
- **K1** : lecture lente, la même commande qu'en `croise`, `bisection` et `amont`.

**Prérequis supposé, à vérifier au lancement** : python3 sur sc-confiance. cloud-init, qui configure ces VM, est écrit en Python ; le script relève la version.

### Essais à sec, sur l'hôte

- Les trames WebSocket se décodent à l'identique pour 0, 1, 125, 126, 65 535, 65 536 et 70 000 octets.
- Les 128 Mio de trames se préparent à environ 227 Mio/s, bien plus vite que la lecture lente du pod (environ 10 Mio/s) : le client reste un producteur rapide, comme kubectl.
- L'échange avec un vrai kubelet n'est pas essayé.

### Prédictions

| # | Prédit | Confiance |
|---|---|---|
| K2 | passe, code 0, statut `Success`, tout reçu | moyenne : premier usage du client |
| K1 | bloque au délai, tous les octets reçus : le maillon est dans le relais de kubelet | faible |

### Lecture prévue

- **K1 bloque** : le maillon est kubelet, c'est-à-dire son relais vers le serveur de flux de containerd. `crictl exec` passe sans ce relais (B1).
- **K1 passe** : le maillon est l'apiserver.
- **K2 échoue** : le client est en cause, et rien ne peut être lu de K1.

## Résultat de l'étape kubelet (10/11/2026, 19:58:33 à 19:58:35 UTC)

Accord : « Oui », à 19:58:29 UTC (transcription), en réponse à « Je lance l'étape kubelet ? ». Lancée sous bash, code **0** ; le script ne s'arrête pas sur un refus. Journal : [`diag-exec-kubelet.log`](diag-exec-kubelet.log). Le pod est supprimé.

**Relevés**
- Arguments de kube-apiserver : `--kubelet-client-certificate=/var/lib/rancher/rke2/server/tls/client-kube-apiserver.crt` et sa clé.
- Python 3.13.5 sur sc-confiance.

| # | Résultat |
|---|---|
| K2 | **Réfutée.** `403 Forbidden` en 8 ms, rien de transmis |
| K1 | **Non mesurable.** `403 Forbidden` en 5 ms |

**Étape kubelet** (19:58:33 à 19:58:35 UTC, code 0 du script) : **kubelet refuse les deux exec directs, `HTTP/1.1 403 Forbidden`**, en 8 et 5 ms, avant tout transfert. K2, le témoin, échoue ; K1 ne dit donc rien. Le maillon reste situé dans l'apiserver ou kubelet, sans être tranché. Le motif du refus n'a pas été lu, car le client n'affichait que la ligne de statut. Hypothèse non vérifiée : une autorisation de kubelet différente pour un exec par WebSocket (GET), alors que l'apiserver l'atteint autrement.

**Défaut du script**
- Le journal affiche le **chemin** de la clé, pas son contenu : la forme `${cle:+présente}${cle:-absente}` imprime aussi la valeur.
- Corrigé à 19:59 UTC, NON REJOUÉ. Le journal archivé n'est pas modifié.

**Corrigé à sec, NON REJOUÉ** : le client affiche aussi le corps de la réponse (300 caractères au plus), pour lire le motif d'un refus.

## Étape kubelet, rejeu (10/11/2026, 20:00:41 à 20:00:43 UTC)

**Accord** : « Je veux trouver d'où vient le soucis », à 20:00:33 UTC (transcription), en réponse à « Je rejoue l'étape kubelet pour lire le motif du 403, ou on arrête ? ». La réponse est consignée comme une **interprétation** : un accord sur ce seul rejeu.

**Exécution** : sous bash, code **0**.

**Journaux** : le premier passage est renommé [`diag-exec-kubelet-1.log`](diag-exec-kubelet-1.log), le rejeu est [`diag-exec-kubelet.log`](diag-exec-kubelet.log).

**Résultat** : de nouveau `403 Forbidden`, en 5 et 4 ms, **avec un corps de réponse vide**. Un refus d'autorisation de kubelet donne d'ordinaire un motif dans le corps : celui-ci vient peut-être d'un autre contrôle. C'est **non vérifié**.

## Préparé à sec (20:01 UTC), NON LANCÉ

- Le client affiche aussi les en-têtes de la réponse.
- L'étape `kubelet` lit en plus le journal de kubelet sur sc-build, depuis le début de l'étape. Elle garde les lignes qui citent un refus, une autorisation, un exec, un upgrade, un websocket ou 403, sans les jetons, 400 caractères au plus.
- Le filtre a été essayé sous `dash` sur un faux journal.

| # | Prédit | Confiance |
|---|---|---|
| K3 | Le journal de kubelet ou les en-têtes donnent le motif du 403 | faible : rien ne dit que kubelet journalise ce refus à sa verbosité actuelle |

## Étape pile : préparée à sec (20:04 UTC), NON LANCÉE

### Exec direct sur kubelet mis de côté

Deux 403 en moins de 10 ms, avec un corps vide. Cette branche testait surtout le client maison et l'identité empruntée à l'apiserver. Même réglée, elle aurait gardé un client différent de kubectl. La variante « en-têtes et journal de kubelet » reste commitée, NON LANCÉE, comme repli.

### Ce que fait l'étape

Elle relève les goroutines en cours avec le kubectl standard, en simple GET, sans client maison, sans secret lu et sans changement de la plateforme :
- **kubelet de sc-build**, par le proxy de nœud (`/api/v1/nodes/sc-build/proxy/debug/pprof/goroutine?debug=2`) ;
- **kube-apiserver** (`/debug/pprof/goroutine?debug=2`), si le profilage est actif.

Trois moments, dans un pod runc, avec un exec de 128 Mio à lecture lente :
- **avant** l'exec ;
- **pendant**, à 45 s : le processus est fini vers 15 s, et l'exec est pendu ;
- **après** la fin du délai de 150 s.

Les piles brutes restent dans le répertoire de travail, hors du dépôt. Le journal n'archive que les goroutines dont la pile cite le relais de flux (remotecommand, httpstream, spdy, websocket, proxy, streaming, UpgradeAware, Translator, exec), avec leur état, leur durée d'attente et la différence entre les moments.

### Vérifications hors ligne

- Profilage :
  - **apiserver** : le contrôle CIS 1.2.15 (`--profiling` à false) est en échec dans `08b-rke2/resultats/rke2-cis.log`, donc le profilage est probablement actif ;
  - **kubelet** : non relevé. Le script dira si la pile est disponible.
- L'analyse a été essayée sur de fausses piles. Une goroutine présente seulement « pendant » ressort avec sa durée d'attente et sa chaîne d'appels.

### Prédictions

| # | Prédit | Confiance |
|---|---|---|
| P1 | Les piles de kubelet et de l'apiserver sont disponibles | moyenne |
| P2 | Pendant le blocage, une goroutine du relais de flux, absente avant et après, attend **dans kubelet** depuis plus de 20 s | faible |
| P3 | L'exec finit en code 124, avec tous les octets reçus, comme en `croise` et `amont` | haute |

### Lecture prévue

Le composant qui garde une goroutine du relais de flux en attente pendant le blocage, et seulement pendant, est le maillon. Sa chaîne d'appels dit où elle attend.

## Résultat de l'étape pile (10/11/2026, 20:04:45 à 20:07:22 UTC)

Accord : « Oui », à 20:04:41 UTC (transcription), en réponse à « Je lance l'étape pile ? Merci de répondre oui ou non ». Lancée sous bash, code **0**. Journal : [`diag-exec-pile.log`](diag-exec-pile.log). Les piles brutes restent hors du dépôt. Le pod est supprimé.

| # | Résultat |
|---|---|
| P1 | **Tenue pour kubelet, réfutée pour l'apiserver** (`NotFound`, profilage coupé) |
| P2 | **Réfutée.** Aucune goroutine de relais en attente dans kubelet pendant le blocage |
| P3 | **Tenue.** Code 124, 134 217 728 octets reçus |

**Étape pile** (20:04:45 à 20:07:22 UTC, code 0 ; pod runc, 128 Mio lus lentement, exec en code 124, tout reçu) :
- **pile de kubelet disponible**, 224, 225 et 225 goroutines avant, pendant et après ;
- **pile de kube-apiserver indisponible** (`NotFound`) : son profilage est coupé. Le contrôle CIS 1.2.15 de la 08b en échec ne voulait donc pas dire profilage actif ;
- **pendant le blocage, kubelet n'a aucune goroutine de relais de flux en plus** : 11 avant, 11 pendant, 11 après, aux mêmes chaînes d'appels. Toutes piles confondues, la seule goroutine en plus est une tâche de statistiques de volumes (`volumeStatCalculator`), sans rapport.

**Lecture** : à 45 s, le processus est fini et kubelet ne relaie plus rien pour cet exec. Sa part semble achevée. Par élimination avec la bisection (containerd hors de cause) et l'étape amont (poste hors de cause), **le maillon probable est kube-apiserver**, qui garde l'exec ouvert vers kubectl. **Ce n'est pas prouvé** : la pile de l'apiserver manque, et les goroutines de kubelet pendant le transfert lui-même (avant 15 s) n'ont pas été relevées.

## Étape connexions : préparée à sec (20:08 UTC), NON LANCÉE

**Pourquoi cette étape** : la pile de l'apiserver est indisponible. Activer son profilage serait un changement de la plateforme, et ce n'est pas proposé ici. Cette étape relève donc l'état des connexions TCP établies, en adresses et ports seulement (`ss -tn`, sans contenu). Rien n'est changé ni écrit sur les VM.

**Connexions relevées** :
- sur sc-build : celles de kubelet sur le port 10250 venant de sc-confiance ;
- sur sc-confiance : celles de kube-apiserver vers sc-build:10250, et celles reçues sur 6443 ;
- sur l'hôte : celles du processus kubectl de l'exec.

**Trois moments** : avant, pendant (à 45 s), après le délai. Ils encadrent le même exec à lecture lente de 128 Mio, dans un pod runc.

| # | Prédit | Confiance |
|---|---|---|
| N1 | Pendant le blocage, aucune connexion de plus entre l'apiserver et kubelet par rapport à avant (la part de kubelet est finie), alors que le kubectl de l'exec garde sa connexion vers 6443 | moyenne (d'après la pile de kubelet) |
| N2 | Code 124, tous les octets reçus | haute |

**Lecture prévue**
- **N1 tenue** : l'apiserver garde ouverte la connexion avec kubectl après la fermeture du côté de kubelet. C'est le maillon, prouvé au niveau des connexions.
- **Une connexion de plus vers kubelet pendant le blocage** : le côté de kubelet reste ouvert, sans goroutine de relais, et la question reste ouverte.

**Limite** : les connexions de l'apiserver vers kubelet servent aussi à d'autres requêtes, comme les journaux et les métriques. La différence entre les moments peut donc être brouillée.

## Résultat de l'étape connexions (10/11/2026, 20:09:24 à 20:12:01 UTC)

Accord : « Oui », à 20:09:19 UTC (transcription), en réponse à « Je lance l'étape connexions ? Oui ou non ». Lancée sous bash, code **0**. Journal : [`diag-exec-connexions.log`](diag-exec-connexions.log). Le pod est supprimé.

| # | Résultat |
|---|---|
| N1 | **Tenue en apparence, mais mal posée.** Aucune connexion de plus entre l'apiserver et kubelet pendant le blocage, car il n'y en a **aucune**, à aucun moment ; le kubectl de l'exec garde ses connexions vers 6443 |
| N2 | **Tenue.** Code 124 |

**Étape connexions** (20:09:24 à 20:12:01 UTC, code 0 ; pod runc, 128 Mio lus lentement, exec en code 124) :
- **aucune connexion directe entre kube-apiserver et kubelet** (sc-confiance vers sc-build:10250) : 0 avant, 0 pendant, 0 après ;
- connexions reçues sur 6443 : 44 avant, **46 pendant**, 44 après ;
- **sur l'hôte, le kubectl de l'exec garde 2 connexions établies pendant le blocage**.

**Lecture** : l'apiserver ne joint pas kubelet en direct. Sous RKE2, il passe vraisemblablement par le **tunnel de l'agent** : le sélecteur de sortie (« egress selector »), relayé par `remotedialer` entre rke2-server (port 9345 du superviseur) et rke2-agent. **Ce n'est pas vérifié** : ni la configuration du sélecteur, ni les journaux de rke2-server et rke2-agent n'ont été lus. Ce tunnel est un maillon de plus, propre à RKE2 et k3s, entre l'apiserver et kubelet. Il est **le nouveau suspect** : la pile de kubelet est vide de relais, et le relais de l'apiserver n'est pas observable.

**Recherche** : aucun ticket ne décrit ce cas avec k3s, RKE2 ou `remotedialer`. Deux sources s'en rapprochent :
- le ticket Kubernetes [#13394](https://issues.k8s.io/13394), ancien, sur un `kubectl exec -i` alimenté par un tube qui ne se termine pas ;
- une note de CoreWeave, qui attribue des blocages d'exec au tunnel entre l'apiserver et kubelet (Konnectivity, un autre tunnel).

## Étape tunnel : préparée à sec (20:13 UTC), NON LANCÉE

**Lectures** :
1. l'argument `--egress-selector-config-file` de kube-apiserver et le contenu de ce fichier. C'est une configuration ; aucun secret n'y est attendu, et les lignes `jeton|token` sont retirées ;
2. les connexions établies vers le port 9345 du superviseur depuis sc-build, avant, pendant et après le blocage ;
3. les journaux de rke2-server (sc-confiance) et de rke2-agent (sc-build) dans la fenêtre. On garde les lignes qui citent le tunnel, `remotedialer`, un proxy, le sélecteur de sortie, 10250, un flux, une connexion, une erreur ou un délai. Les lignes `jeton|token` sont retirées, et chaque ligne est coupée à 300 caractères.

**Blocage** : le même exec à lecture lente de 128 Mio, dans un pod runc. Rien n'est changé ni écrit sur les VM.

| # | Prédit | Confiance |
|---|---|---|
| T1 | kube-apiserver a un sélecteur de sortie : le trafic vers kubelet passe par le tunnel du superviseur (port 9345) | moyenne : aucune connexion directe relevée |
| T2 | Une connexion durable de sc-build vers 9345, la même avant, pendant et après | moyenne |
| T3 | Les journaux de rke2-server et rke2-agent ne disent rien de cet exec à leur verbosité actuelle | moyenne |

**Lecture prévue** : si T1 tient, le tunnel est le seul maillon de la chaîne qui n'a pas encore été observé. Pour le confirmer, il faudrait une mesure qui le contourne, et la seule qui se présente est de changer le mode du sélecteur. Ce serait un changement de la plateforme, à décider avec le propriétaire.

## Résultat de l'étape tunnel (10/11/2026, 20:24:26 à 20:27:04 UTC)

Accord : « Oui », à 20:24:19 UTC (transcription), en réponse à « Je lance l'étape tunnel ? Oui ou non ». Lancée sous bash, code **0**. Journal : [`diag-exec-tunnel.log`](diag-exec-tunnel.log). Le pod est supprimé.

| # | Résultat |
|---|---|
| T1 | **Tenue** |
| T2 | **Tenue** (2 connexions) |
| T3 | **Tenue** |

**Étape tunnel** (20:24:26 à 20:27:04 UTC, code 0 ; pod runc, 128 Mio lus lentement, exec en code 124, tout reçu) :
- **sélecteur de sortie de kube-apiserver** (`/var/lib/rancher/rke2/server/etc/egress-selector-config.yaml`) : la sélection `cluster` passe par un proxy **HTTP CONNECT vers `https://127.0.0.1:9345`**, le superviseur de RKE2. Le fichier ne contient que des chemins de certificats, aucune valeur ;
- **2 connexions établies de sc-build vers 9345**, les mêmes avant, pendant et après le blocage : c'est le tunnel durable de l'agent ;
- **journaux de rke2-server et rke2-agent muets** dans la fenêtre, pour les mots cherchés.

**Lecture** : la chaîne d'un `kubectl exec` vers un pod de sc-build est kubectl, puis kube-apiserver, puis le proxy CONNECT du superviseur (rke2-server), puis le tunnel `remotedialer` jusqu'à rke2-agent, puis kubelet, puis containerd. Containerd est mis hors de cause par la bisection. Kubelet ne relaie plus rien pendant le blocage, d'après sa pile. Le poste est hors de cause par l'étape amont. **Le maillon fautif est donc kube-apiserver ou le tunnel du superviseur RKE2.** Le tunnel, propre à RKE2 et k3s, est le suspect principal, **sans preuve directe** : ni lui ni l'apiserver ne sont observables à la verbosité actuelle.

## Étape local : préparée à sec (20:30 UTC), NON LANCÉE

Demande : « Prépare », à 20:28:45 UTC (transcription), en réponse à « Je prépare un exec vers un pod de sc-confiance, sans le tunnel ? ».

**Code lu**, hors du dépôt : k3s au commit `58877f27`, celui que fixe le `go.mod` de RKE2 `v1.35.9+rke2r1`.
- `pkg/daemons/control/tunnel.go` (`dialBackend`) : le proxy CONNECT du superviseur joint **en direct** le kubelet du nœud qui porte le superviseur. Pour un autre nœud, il passe par la session `remotedialer` de son agent.
- `pkg/daemons/control/proxy/proxy.go` (`Proxy`) : dans les deux cas, le relais copie chaque sens à part, avec une mémoire de 32 Kio. À la première fin ou erreur d'un des deux sens, il ferme les deux connexions.

Un exec vers un pod de sc-confiance garde donc kubectl, l'apiserver et `proxy.Proxy`, mais **retire la session `remotedialer`**.

**Le pod d'essai**
- Placement : espace `default`, `kubernetes.io/hostname: sc-confiance`. La règle `zone-build` tient les pods de `builds` à sc-build.
- Profil : runc `restricted`, UID 1000, sans compte de service monté.
- Mémoire : 1 Gio, tmpfs de 512 Mio.
- Image : l'image d'essai de s1b.

**Admission** : le script l'essaie d'abord à blanc (`--dry-run=server`). En cas de refus, il s'arrête sans rien lancer.

**Mesure** : un seul exec, le même que plus haut (lecture lente de 128 Mio, délai de 150 s), par le kubectl de l'hôte. Le pod est supprimé à la fin.

| # | Prédit | Confiance |
|---|---|---|
| L0 | Le pod est admis dans `default` et démarre sur sc-confiance | moyenne : règles de l'espace `default` non relues en entier |
| L1 | L'exec passe, code 0, tout reçu : la session `remotedialer` est le maillon | faible |

**Lecture prévue**
- **L1 passe** : le maillon est le tunnel `remotedialer`, entre rke2-server et rke2-agent.
- **L1 bloque** : le maillon est kube-apiserver ou `proxy.Proxy` ; on ne peut pas encore départager les deux.

