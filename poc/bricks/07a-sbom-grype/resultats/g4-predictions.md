# G4 : prédictions (écrites le 04/11/2026 à 20:35 UTC, avant toute exécution)

Le job de scan dans la plateforme : [`politique/scan-job.yaml`](../politique/scan-job.yaml) et [`politique/scanner.sh`](../politique/scanner.sh), un mode par conteneur. Préparé à sec : rien n'est appliqué au cluster, rien n'est écrit dans Zot.

## Conception

| Conteneur (ordre) | Image | Rôle | Identifiants |
|---|---|---|---|
| `source` | buildkit, la seule image avec git | commit lu dans Forgejo, vérifié par git (`fsck`, HEAD égal au commit), arbre exporté | aucun |
| `analyser` | `outils-scan` | base la plus récente résolue en digest, empreinte vérifiée, import ; image lue par digest ; SBOM fusionné ; scan ; prédicat | aucun |
| `jetons` | openbao | `scan-zot` : identifiants lus, jeton révoqué ; `scanner` : jeton pris après le scan (D9 a) | jeton projeté, monté ici seulement |
| `attester` | `outils-scan` | `cosign attest-blob --key hashivault://scanner`, sujet = digest de l'image ; bundle vérifié avec la clé publique | jeton de 5 min |
| `publier` | `outils-scan` | bundle poussé par digest, en referrer de l'image, dans `builds/scan/sample-app` | identifiants de `poc-scan` |
| `revocation` | openbao | jeton révoqué, identifiants et jeton effacés du volume en mémoire | jeton de 5 min |

- **Écart au README** : la lecture de la source a demandé un conteneur de plus, car `outils-scan` n'a pas git. L'image BuildKit est celle de `preparer-entrees`.
- **Limites du job** : 30 min au plus, volume de travail de 5 Gi, 2 Gi de mémoire pour `analyser`, job purgé 1 h après sa fin.
- **Pas de Secret**, pas de service Anchore ni Sigstore, pas de sortie hors de DNS, OpenBao, Zot et Forgejo.

## Mesuré à sec (04/11/2026, entre 20:24 et 20:35 UTC, sur l'hôte)

**`attest-blob` avec une clé jetable** : sujet `sample-app` de digest `3a7ca1b1…`, prédicat `scan/v1`. `verify-blob-attestation` accepte, et refuse un autre digest et un autre prédicat.

**`scanner.sh` dans le système de fichiers de l'image réelle** (`outils-scan@7eb4f26e`, en chroot, mêmes busybox et binaires) :
- `analyser`, Zot lu en anonyme : base `2026-11-04`, résolue en `13729131…`, empreinte `ed08c5e3…` vérifiée ;
- import de 3 222 Mo en 78 s, 4 composants avec PURL, **5 vulnérabilités, 0 KEV**, mêmes 5 identifiants qu'en G0 ;
- 82 s en tout, RSS maximal 228 Mo ;
- `attester` avec une clé jetable ; bundle vérifié sur l'hôte ;
- `publier` avec un `oras` factice : manifeste correct, digest conforme, **rien poussé**.

**`source`** a tourné sur l'hôte avec son git : commit `6391fd43…`, arbre `30e808ff…`, 12 fichiers.

**`g4_scan` et `g4_verifier`** avec des bouchons à la place de `kubectl`, `ssh` et `curl` : parcours complet, aucun marqueur `@…@` restant dans le job, YAML validé par `kubectl apply --dry-run=client`. Le comptage des KEV du journal rend 2 sur le cas log4j de G0.

**CronJob d'horodatage** : il parcourt tout `builds/`, et G1 y a créé des dépôts sans tag. Bilan relu dans Grafana : 80 passages entre 18:00 et 19:20 UTC, 65 entre 19:30 et 20:35 UTC, tous à `12 image(s), 56 enveloppe(s), 2 refusée(s), 1 anomalie(s)`. Les refus et l'anomalie sont des témoins de J6 (`builds/essai-j6-*`). G1 n'a rien changé.

**`sc-confiance`** : 6,2 Go libres sur 15 Go, seuils d'éviction à 5 % (0,75 Go), nettoyage des images à 85 %.

## Non joué à sec

- `jetons` et `revocation` : pas de `bao` dans le chroot. Leurs commandes ont un précédent mesuré (G3, J8).
- `source` avec le git de BuildKit, sous l'uid 65532 et en lecture seule. Précédent : `preparer-entrees`.
- L'absence de réseau : le chroot avait le réseau. Le fonctionnement hors réseau reste celui de G0, avec les mêmes variables.
- La limite de mémoire : le chroot n'en avait pas.
- Le refus d'une base corrompue dans le job : contrôle présent, non essayé.
- Le poussage réel par digest dans `builds/scan/sample-app`. Précédent : `g1_droits` pour le droit, J5 pour le referrer, mais J5 pose un tag et pas `poc-scan`.

## Étapes et prédictions (accord du propriétaire avant `g4_scan`)

Ordre : `g4_scan g4_verifier g4_grafana`.

**g4_scan**
- Job terminé en moins de 5 min, dont 80 à 120 s d'import.
- Base : tag `2026-11-04`, `13729131…`, sauf si le timer de demain (08:00 UTC) est déjà passé.
- SBOM à 4 composants avec PURL ; **5 vulnérabilités, 0 KEV**.
- Environ 3,4 Go dans le volume au plus haut. Place libre la plus basse sur `sc-confiance` : au moins 2,5 Go, loin du seuil de 0,75 Go.
- Un jeton `scan-zot` révoqué, un jeton `scanner` révoqué.

**g4_verifier**
- Un seul referrer de scan, lu en anonyme ; manifeste et bundle aux bonnes empreintes.
- Bundle vérifié sur l'hôte : clé du scanner, sujet `3a7ca1b1…`, prédicat `scan/v1`.
- Autre digest, autre prédicat et clé de Chains refusés.
- Prédicat : `grype 0.104.1`, base citée par digest sous `sc-stockage.poc.test:5000/vulndb/grype`, 0 KEV, 0 paquet malveillant.
- Mêmes identifiants qu'en G0, tant que la base reste celle du 04/11.
- 0 Secret dans l'espace `scan`.
- Audit d'OpenBao : connexions `scan-zot` et `scanner`, `kv/scan/zot` lu, `transit/keys/scanner`, `transit/sign/scanner/sha2-256`, deux `revoke-self`, sans erreur.

**g4_grafana**
- Lignes `SOURCE`, `BASE`, `SCAN`, `ATTESTATION`, `PUBLIE` et la révocation, lues par l'auditeur.
- Signature visible dans l'audit d'OpenBao, poussage par `poc-scan` visible dans l'audit de Zot.
- Identifiants de `poc-scan` absents des réponses.

**CronJob d'horodatage** : même bilan après G4 (12 images, 56 enveloppes). `builds/scan/sample-app` n'a pas de tag `.att`.

**Incertain**
- **Mémoire** : l'import écrit 3,2 Go sur disque, et le cache de pages compte dans la limite de 2 Gi. Il est récupérable, mais l'import peut être plus lent, voire le conteneur tué. Le cas échéant, le passage sera archivé.
- **Durée** : `sc-confiance` a 4 cœurs partagés avec la porte et OpenBao ; le temps d'import peut dépasser celui de l'hôte.
- **Premier tirage de BuildKit** sur `sc-confiance` (zone de confiance : jamais tiré ici, à vérifier au passage).

## Effets à connaître

- **Zot** : un manifeste et deux blobs dans `builds/scan/sample-app`, définitifs : ni `poc-scan` ni personne ne peut les supprimer (`gc` à false). Un rejeu de zéro les efface.
- **Cluster** : `scan-config` complétée, un job et son pod. Le job est supprimé en fin de `g4_grafana`.
- **`sc-confiance`** : environ 3,4 Go de disque et de l'activité pendant 2 à 5 min, libérés par le job.
- **Porte** : elle ne lit pas `builds/scan` avant G5. Aucun effet sur les déploiements.
- **R4 et R5 de la 10** : aucune interaction.
- **À noter pour G7** : rejouer `g3_cluster` réappliquerait `scan-config` avec la seule CA et retirerait `scanner.sh` et `scanner.pub`.

## Résultat (04/11/2026, de 20:38:17 à 20:40:27 UTC)

Accord du propriétaire : « Oui les 2 » (pousser `84b90d3`, appliquer G4). Trois étapes, code 0 du premier coup, sans passage raté à archiver.

**g4_scan** : job terminé en 2 min (20:38:17 à 20:40:17), sous la limite de 2 Gi.
- `source` : commit `6391fd43…`, arbre `30e808ff…`, 12 fichiers, premier essai, avec le git de BuildKit sous l'uid 65532.
- `analyser` : base `2026-11-04`, `13729131…`, empreinte `ed08c5e3…` ; import de 3 222 Mo en 103 s ; 3 411 Mo dans le volume au plus haut ; 4 composants avec PURL ; **5 vulnérabilités, 0 KEV** ; 108 s en tout.
- `jetons` : identifiants lus, jeton `scan-zot` révoqué, jeton `scanner` obtenu.
- `attester` : bundle `7c70dfff…`, vérifié dans le job avec la clé publique.
- `publier` : `builds/scan/sample-app@sha256:23ec3bcf…`, referrer de `3a7ca1b1…`.
- `revocation` : jeton révoqué, identifiants et jeton effacés.
- Place libre la plus basse sur `sc-confiance` : 2 505 Mo.

**g4_verifier**
- Un seul referrer de scan, lu en anonyme ; manifeste et bundle aux bonnes empreintes.
- Bundle vérifié sur l'hôte ; autre digest, autre prédicat et clé de Chains refusés.
- Prédicat archivé ([`g4-scan-predicat.json`](g4-scan-predicat.json), [`g4-scan.bundle.json`](g4-scan.bundle.json)) : `grype 0.104.1`, base citée par digest, 0 KEV, 0 paquet malveillant, mêmes 5 identifiants qu'en G0 (tous sur chi `v5.2.3`), `scannedAt` à 20:40:09.
- 0 Secret dans l'espace `scan`.
- Audit d'OpenBao conforme, sans erreur : connexions `scan-zot` et `scanner`, `kv/scan/zot`, `transit/keys/scanner`, `transit/sign/scanner/sha2-256`, deux `revoke-self`.

**g4_grafana** : lignes du job lues par l'auditeur, signature visible dans l'audit d'OpenBao (2 lignes), poussage par `poc-scan` visible dans l'audit de Zot (5 lignes), identifiants absents des réponses. Job supprimé ensuite.

**Levés par ce passage** : `source` avec le git de BuildKit, `jetons`, `revocation`, le réseau limité de `scan`, la limite de mémoire (ni arrêt ni échec), le poussage réel par digest par `poc-scan`.

**Écarts et marges**
- Place libre basse tout juste au-dessus de la prédiction (2 505 Mo pour « au moins 2,5 Go ») : l'image BuildKit, tirée pour la première fois sur `sc-confiance`, y reste. Après le job, 5 915 Mo sont libres, contre 6,2 Go avant.
- Import plus lent que sur l'hôte (103 s contre 78 s), dans la fourchette prédite.

**Limites**
- La consommation mémoire réelle du conteneur n'a pas été relevée.
- Le refus d'une base corrompue dans le job n'a pas été essayé.
- La porte n'exige pas encore ce scan : ce sera G5, après R5. Les négatifs viennent en G6.
- Le job est lancé à la main : le passage périodique et le rejeu de zéro sont à traiter en G7.

**CronJob d'horodatage** : même bilan après G4, conforme à la prédiction. Passage de 20:41:00 UTC, postérieur au poussage : 12 images, 56 enveloppes, 54 déjà, 2 refusées, 1 anomalie, sans aucune ligne citant `builds/scan`.
