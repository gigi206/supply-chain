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

