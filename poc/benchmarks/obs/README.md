# A2 : Open Build Service (packaging rpm/deb)

**But** : noter OBS sur la grille A restreinte au packaging (critères A-1 sur B1, B4, B5 et B8, puis A-3, A-5 et A-6). Seuil : rpm **et** deb bit-identiques sur 2 builds.

**Prérequis** : VM ou serveur avec KVM (workers OBS), image OBS appliance ou paquets openSUSE.

## Protocole (≤ 3 jours)

1. Installer OBS (appliance) et un worker KVM. Mesurer le temps et la RAM.
2. Configurer les dépôts cibles : Debian 13 et Rocky 9, en **dépôts téléchargés à la demande** (DoD) pointant vers des miroirs figés.
3. Construire `poc/packaging` (spec et debian/) pour rocky-9 et debian-13.
4. Reconstruire sans changement (`rebuild`) et comparer les sha256 : rpm et deb.
5. Exporter la provenance OBS (format SLSA v0.2) et évaluer sa conversion en SLSA v1, ou sa signature par notre plateforme.
6. Tester le fonctionnement **hors ligne** : worker sans egress, dépôts locaux.
7. Évaluer la signature (signd) face à notre service OpenPGP (brique 09).

## Mesures à archiver dans `resultats/`

- Versions ; ressources ; journaux de build ; sha256 des deux builds ; provenance produite.
