# R2, création du domaine de replay : prédictions (écrites le 03/11/2026 vers 10:00 UTC, avant toute exécution)

Accord du propriétaire : « Oui, lancer R2 ». Réseau distinct, BuildKit sur empreinte seule.

## Étapes (`mise run replay -- vm isolement paquets outils cle_vsa`)

1. **`vm`** : tout est propre au domaine.
   - Image Debian 13 vérifiée (sha512), la même que pour les trois VM.
   - Pool libvirt `supply-chain-replay` (`/var/lib/libvirt/supply-chain-replay`).
   - Réseau NAT `supply-chain-replay` (`192.168.162.0/24`, pont `virbr-screplay`) ; VM `sc-replay` en `192.168.162.14`, 4 vCPU, 6 Gi, 20 Go.
   - Clés SSH du domaine dans `~/.cache/supply-chain-poc/10/ssh`, et compte `replay` à clé seule.
2. **`isolement`** : mesuré depuis la VM.
3. **`paquets`** : `busybox-static` et `diffoscope-minimal` installés par apt, sans les paquets recommandés.
4. **`outils`** : archives copiées dans la VM et **revérifiées dans la VM**, contre les empreintes fixées dans `replay.sh`. Ce sont les mêmes empreintes que `mise.lock` et go.dev, signatures vérifiées sur l'hôte pour runc, oras et cosign. Puis BuildKit, runc, cosign et oras installés dans `/usr/local/bin`, et Go dans `/usr/local/go`.
5. **`cle_vsa`** : paire cosign ECDSA P-256 générée **dans la VM**, par le compte `replay`.
   - Le mot de passe est tiré au hasard dans la VM (0600) et n'en sort pas.
   - La clé publique est copiée dans `resultats/vsa-cle-publique.pem`.

## Prédictions

1. **`vm`** : la VM répond en SSH avec la clé d'hôte attendue en moins de 3 min. Les trois VM du PoC ne sont pas touchées : même PID de qemu avant et après, et réseau `supply-chain-poc` inchangé.
2. **`isolement`**, attente incertaine : les règles de transfert de libvirt n'ont pas été lues.
   - Je m'attends à ce que la VM **ne joigne aucune adresse de `192.168.161.0/24`** (Zot 5000, Forgejo 3000, API de k3s 6443 : refus ou délai dépassé). libvirt n'autorise normalement, sur un réseau NAT, que le trafic sortant vers l'extérieur et ses réponses.
   - Je m'attends à ce qu'elle **joigne l'extérieur** (`deb.debian.org` en HTTPS).
   - Si `192.168.161.0/24` était joignable, l'option retenue serait moins isolante que prévu, et je m'arrêterais pour vous le dire.
3. **`paquets`** : apt vérifie les signatures de l'archive Debian, sans « WARNING » ni « untrusted ». Les versions installées sont consignées.
4. **`outils`** : cinq empreintes `OK` dans la VM. `go version` donne `go1.26.10 linux/amd64`, et `buildctl --version` donne 0.25.2.
5. **`cle_vsa`** : `cosign.key` en 0600 et propriété de `replay`. La clé publique est une clé ECDSA P-256 (`openssl pkey -pubin -text`), différente de celle de Chains.

## Limites

- Le root de l'hôte peut lire le disque de la VM, clé de VSA comprise (D2 a).
- Le compte `replay` a sudo sans mot de passe : c'est l'administrateur du domaine, c'est-à-dire le propriétaire (D1 b).

## Additif du 03/11/2026, après l'exécution (10:00 à 10:02 UTC)

1. **`vm`** : conforme.
   - Image Debian `OK` (sha512) ; pool, réseau et VM créés.
   - SSH joignable avec la clé d'hôte attendue **9 s** après le démarrage.
   - VM de 4 vCPU, 6 Gi (`free -g` affiche 5) et 20 Go, sous Debian 13.
   - Les trois VM du PoC gardent leurs identifiants de domaine (122, 123, 124) ; `supply-chain-poc` est actif, avec ses 3 baux fixes.
2. **`isolement`** : **conforme, avec un écart**.
   - Zot (`192.168.161.13:5000`), Forgejo (`:3000`) et l'API de k3s (`192.168.161.11:6443`) sont **injoignables**. L'extérieur est joignable (HTTP 200).
   - Écart : `192.168.161.1:22` est **joignable**. Ce n'est pas une VM du PoC : c'est l'adresse de **l'hôte** sur le pont `virbr-scpoc`. Le sshd du laptop écoute sur `0.0.0.0`, et la VM l'atteint par l'hôte.
   - Relevé de l'hôte (`ss -ltn`) : il écoute aussi sur `0.0.0.0` ou `*` pour 111 et 2049 (NFS), 22000 et plusieurs ports RPC. Leur joignabilité est **mesurée dans le complément ci-dessous** ; au premier relevé, elle n'était que déduite.
   - Ce n'est pas un chemin vers le plan de confiance, mais une surface de l'hôte. La configuration du poste n'est pas modifiée ; c'est consigné pour le propriétaire.
3. **`paquets`** : conforme. `busybox-static 1:1.37.0-6+b9` et `diffoscope-minimal 297+deb13u1`. Aucun « warning », « untrusted » ni « unauthenticated » dans la sortie d'apt.
4. **`outils`** : conforme.
   - Cinq empreintes `OK` dans la VM.
   - BuildKit `v0.25.2` (`dcc0fe5e`), runc 1.3.3, cosign v3.1.4, oras 1.3.6, `go version go1.26.10 linux/amd64`.
5. **`cle_vsa`** : conforme.
   - `mot-de-passe`, `cosign.key` et `cosign.pub` en 600, propriété de `replay`.
   - Clé ECDSA **P-256** (`prime256v1`), d'empreinte DER `578dd771…`, différente de celle de Chains (`ecf50485…`).
   - [`vsa-cle-publique.pem`](vsa-cle-publique.pem).

## Prédictions du complément d'isolement (écrites le 03/11/2026 vers 10:03 UTC, avant la mesure)

- **Sens inverse :** depuis `sc-build` et `sc-confiance`, `192.168.162.14:22` est **injoignable**. Je m'attends à ce que libvirt n'autorise pas le transfert entre deux réseaux NAT ; c'est une attente incertaine.
- **Surface de l'hôte :** depuis `sc-replay` vers `192.168.162.1` et `192.168.161.1`, et depuis `sc-build` vers `192.168.161.1`, je ne présume rien pour les ports 111, 2049 et 22000 : un pare-feu de l'hôte peut filtrer ce qui écoute sur `0.0.0.0`. Le port 22 est attendu joignable.

## Complément d'isolement, mesuré (03/11/2026, 10:03 UTC) : [`r2-isolement-complement.log`](r2-isolement-complement.log)

- **Sens inverse : conforme.** Depuis `sc-build` et `sc-confiance`, `192.168.162.14:22` est **injoignable**. Le plan de confiance, y compris le nœud qui exécute le code des builds, ne joint pas le domaine de replay.
- **Surface de l'hôte : mesurée.** Tout ce qui a été essayé est **joignable** :
  - 22, 111, 2049 (NFS) et 22000 sur `192.168.161.1`, depuis `sc-build` et `sc-confiance` ;
  - 111, 2049 et 22000 sur `192.168.161.1`, et 22, 111, 2049 et 22000 sur `192.168.162.1`, depuis `sc-replay` ;
  - 22 seulement sur `192.168.162.1`, depuis `sc-build` et `sc-confiance`. Ce ne sont que des connexions TCP ; aucun service n'a été interrogé.
  - **Conséquence pour le plan de confiance**, hors de la brique 10 : depuis le système de `sc-build`, le NFS du laptop est joignable. Les pods de construction n'ont pas de sortie (NetworkPolicy de la 08), mais le nœud, lui, en a une.
- **Horloge de `sc-replay`** : synchronisée par NTP, à la même seconde que l'hôte (10:03:45 UTC). `timeVerified` en dépendra.
