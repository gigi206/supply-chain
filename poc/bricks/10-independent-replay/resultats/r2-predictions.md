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
