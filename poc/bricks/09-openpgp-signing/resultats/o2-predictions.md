# Brique 09, O2 : prédictions

O2 (README, « Jalons proposés ») : clé OpenPGP du PoC selon D2, environnements de signature Rocky 9.8 et Debian 13, paquets épinglés et vérifiés. Préparation à sec demandée par le propriétaire le 19/11/2026 (« Oui, prépare O2 »).

## Relevé préalable `o2-releve.sh` (lectures locales et publiques seulement)

Écrites le 19/11/2026 avant tout lancement du script (heure : celle du commit qui les porte).

| # | Prédiction | Confiance |
|---|---|---|
| RL1 | Amorce `rockylinux:9.8` (`ed654c69`) : manifeste, configuration et couche égaux à leur sha256 (comme le 18/11 en 05). `rpm`, `rpmkeys`, `dnf-3` et la clé `RPM-GPG-KEY-Rocky-9` présents ; `rpmsign` et `createrepo_c` absents ; **aucun greffon dnf** (`download.py` absent), comme mesuré en 9.7 | moyenne : rpm et dnf relevés le 18/11 ; gpg et greffons jamais relevés en 9.8 |
| RL2 | Présence de `usr/bin/gpg2` ou `usr/bin/gpg` dans l'amorce Rocky | **pas de prédiction** (relevé) |
| RL3 | Amorce `debian:trixie-20261104-slim` (`7378260c…`) : sha256 égaux ; `apt-get`, `dpkg`, `gpgv` et `debian-archive-keyring.gpg` présents ; `gpg`, `gpg-agent` et `apt-ftparchive` absents | moyenne : image `slim` ; contenu jamais listé |
| RL4 | Instantané `20261105T000000Z` : `InRelease` signé par les 3 clés de la 06 ; `Packages.xz` égal au sha256 de `InRelease` ; `gnupg` et `gpg` en **2.4.7-21+deb13u1**, `gpgv` en **2.4.7-21+deb13u1+b5** ou en 2.4.7-21+deb13u1 ; `apt-utils` en 3.0.3 | moyenne : madison lit la suite stable du 19/11, pas l'instantané du 05/11 ; un `+deb13u1` publié après le 05/11 donnerait un conflit avec D4 |
| RL5 | `repomd.xml` de `vault/rocky/9.8` (BaseOS, AppStream) vérifiés par la clé Rocky 9 et **égaux** à ceux de `pub/9.8` relevés le 19/11 ; versions du relevé retrouvées (`gnupg2` 2.3.3-5.el9_7, `rpm-sign` 4.16.1.3-40.el9, `createrepo_c` 0.20.1-4.el9) ; `python3-dnf-plugins-core` présent dans BaseOS | moyenne : la 05 a mesuré l'égalité de vault et de pub le 18/11 ; un 9.8 encore servi par pub peut avoir bougé |
| RL6 | Hôte : `unshare --map-auto --map-root-user -n` fonctionne (code 0) ; `secrets-depot.sh` ne lit que les dossiers `08/secrets` et `10/secrets` et n'a pas de motif « BEGIN PGP » ; podman non nécessaire au mécanisme retenu | haute : lu dans le script et employé en 05 |

Téléchargements attendus : 3 clés de ftp-master, `InRelease`, `Packages.xz` (environ 10 Mo, ordre de grandeur non mesuré), 4 fichiers `repomd` de vault ; aucun `primary` si RL5 tient.
