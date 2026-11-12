# Brique 05, S1 : prédictions (écrites le 12/11/2026 à partir de 14:16:03 UTC, avant toute exécution)

Le script est [`s1.sh`](../s1.sh). Le jalon S1 est le M1 du [README](../README.md), renommé comme dans la brique 06. **Rien n'a encore été lu ni écrit dans le cluster, Zot ou les VM, et aucune ressource réseau n'a été lue pour ce jalon.** Les faits cités viennent des journaux déjà archivés de la 05 (relevé amont et audit du 05/11/2026) et du dépôt.

## Accord et calendrier

« Oui, prépare-le » (12/11/2026) vaut pour la préparation à sec seulement. Chaque étape attend un accord nommé.

**Après S5b seulement.** S5b remet Zot à zéro le 13/11 au plus tôt. Une copie faite avant serait effacée, et la règle de sortie touche `builds-sans-internet`, que S5b rejoue.

**Effets prévus**
- **Préalable, hors du script (décision du propriétaire, question 1)** : la politique [`politiques/prefetch-rpm-sortie.yaml`](../politiques/prefetch-rpm-sortie.yaml), puis `prefetch-rpm` ajouté au `NotIn` de `builds-sans-internet` (08c).
- **prealables**, en lecture seule :
  - lecture des politiques de `builds` et des arguments de kube-apiserver ;
  - une spec de pod en dry-run serveur ;
  - lecture des ressources de sc-build et de la place libre de Zot ;
  - lectures publiques depuis l'hôte : clés de Rocky et d'EPEL, page de sécurité de Fedora, repomd et primary de Rocky 9.8, d'EPEL 9 et de vault 9.7.
- **amorce** : écritures **définitives** dans Zot, `amont/rockylinux/rockylinux@sha256:ed654c69…` (9.8) et `@sha256:ee90dc0e…` (9.7).
- **racine** : un pod Kata privilégié root dans `builds`, avec une sortie vers dl.rockylinux.org et dl.fedoraproject.org en 443 ; archive rapatriée sur l'hôte, sous `~/.cache` (`$W/s1-05`).
- **image** : écriture **définitive** dans Zot, `essais-05/mock-rocky9:s1`.
- **essais** :
  - un pod Kata privilégié root, avec une sortie en 443 vers vault 9.7 et, si le modèle les garde, vers les miroirs de Rocky pour les dépôts non remplacés ;
  - tirage de l'image de bootstrap depuis Zot, en 5000 ;
  - journaux de mock archivés dans `resultats/s1-essais-mock.log`, lignes `jeton|token` retirées.

`builders/mock-rocky9` reste réservé à S2, comme `builders/sbuild-debian13` pour la 06.

## Périmètre

- **Risque visé** : podman imbriqué dans un pod Kata (prédiction 4 du README), puis l'isolation `nspawn` contre `simple` (prédiction 3).
  - Le build de sample-app n'est **pas hermétique** : mock résout et télécharge depuis vault 9.7 pendant l'essai.
  - Le verrou, `mock-hermetic-repo` et `--hermetic-build` sont l'objet de M2.
  - S1 ne conclut rien sur le caractère bit-identique.
- **Image de bootstrap non « prête »** (`bootstrap_image_ready = False`) : mock y installe dnf depuis vault 9.7. Le mode hermétique exige une image prête : c'est M2 qui le traitera.
- **mock tourne en root**, dans l'invité Kata (D1 a).
- **Replis non lancés** par ce script : stockage `vfs` pour podman, mock non root, bootstrap sans image. Chacun demandera sa prédiction et un accord.
- **Dépôts de debug et de sources** : ceux du modèle `rocky-9.tpl` gardent leur `mirrorlist`, mais ne sont pas remplacés. Le script s'arrête avant mock s'il reste un `mirrorlist` actif pour BaseOS, AppStream ou CRB.

## Prédictions

| # | Prédiction | Confiance |
|---|---|---|
| P1 | `prealables` s'arrête au premier contrôle tant que `prefetch-rpm-sortie` n'est pas posée. Une fois posée, et `prefetch-rpm` dans le `NotIn`, tous les contrôles passent | Haute pour l'arrêt ; moyenne pour le reste |
| P2 | Clé de Rocky : empreinte `21CB256A…350D275D`. Les cinq repomd de Rocky (9.8 : BaseOS, AppStream ; 9.7 : BaseOS, AppStream, CRB) sont signés par cette clé | Haute : mesuré le 05/11 pour 9.7 et 9.8 |
| P3 | EPEL 9 ne publie pas de `repomd.xml.asc` : son intégrité repose sur les rpm signés et sur TLS. L'empreinte de sa clé figure sur la page de sécurité de Fedora | Moyenne pour les deux points : rien n'a été lu |
| P4 | Les quatre paquets épinglés ont chacun un seul candidat : mock `6.9-1.el9` et mock-core-configs `45.2-1.el9` (noarch, EPEL), podman `5.8.2-8.el9_8` et skopeo `1.22.2-9.el9_8` (x86_64, AppStream 9.8). Le primary d'EPEL est en zstd, ceux de Rocky en gzip | Moyenne : 9.8 et EPEL bougent depuis le 05/11 ; compression non lue |
| P5 | `racine` : dnf installe les quatre paquets et leurs dépendances. Les repomd lus par dnf sont égaux à ceux de l'hôte. 100 % des rpm sont conformes aux primary et `rpm -K` est OK. systemd-container est tiré par mock | Moyenne : la dépendance de mock à systemd-container n'est pas lue |
| P6 | Le cache de dnf se trouve dans la racine (`/w/racine/w/cache`) et non sous `/w/cache`, à cause de `--installroot` | Faible : le script lit les deux |
| P7 | Archive de la racine entre 400 et 900 Mo ; rapatriement par `kubectl exec` (sortie) sans blocage | Faible pour la taille ; moyenne pour le rapatriement (`egress-selector-mode: disabled` est dans `08b-rke2/config/sc-confiance.yaml`, rejoué par S5b) |
| P8 | `essais`, podman imbriqué : stockage `overlay` sous `/w` (tmpfs) accepté ; `podman pull` du bootstrap depuis Zot et `image mount` réussis | **Faible** : c'est le risque principal. Si overlay échoue, le repli `vfs` demandera un accord |
| P9 | `nspawn` échoue dans le pod Kata, `simple` passe | Faible : prédiction 3 du README, non documentée |
| P10 | Avec `simple`, le src.rpm et le rpm de sample-app sont produits, golang et nodejs venant de vault 9.7. `rpm --rebuild` dure moins de 5 minutes | Moyenne pour le build ; faible pour la durée |
| P11 | La place occupée sous `/w` reste sous 3,5 Gio, pour 4 Gio de tmpfs | Faible : aucune mesure |
| P12 | mock accepte de tourner en root, avec au plus un avertissement | Faible : non lu dans le code |

## Ce qui reste non vérifié avant l'exécution

- Le comportement de `dnf --installroot` avec `-c`, `cachedir` et `reposdir` (P6). Le script lit les deux emplacements possibles du cache.
- La présence d'un `fedoraproject.org/security/` lisible sans JavaScript (P3). Si la page ne l'est pas, l'étape `prealables` s'arrête en KO, sans repli.
- La clé que vise `gpgkey` dans `rocky-9.tpl` : la sonde affiche l'empreinte des clés `distribution-gpg-keys/rocky`, sans l'imposer.

## Note du 12/11/2026, à partir de 14:20:06 UTC (relecture du conseiller, avant tout lancement)

- **Correction** : « renommé comme dans la brique 06 » est inexact. Le tableau de la 06 nomme ses jalons S1 et S2 dès l'origine, alors que celui de la 05 les nomme M1 à M5. S1 désigne ici le M1 de la 05, pour suivre la numérotation de la 06.
- **Nouvelle étape `hote`**, séparée de `prealables`. Elle reprend les sources, les clés, les repomd, les primary et les quatre paquets épinglés, sans cluster ni Zot.
  - Elle peut tourner avant S5b, sur accord, et tranche alors P2 à P4.
  - Elle sera rejouée avant `racine`, puisque pub/9.8 et EPEL bougent.
  - `prealables` ne garde que le cluster et Zot, et P1 ne porte plus que sur elle.
- **Deux règles en vigueur reprises** :
  - un pod non prêt n'affiche plus ses Events : seulement sa phase et la raison de l'état de chaque conteneur ;
  - les `rm -rf` de l'hôte passent par `${x:?}`.
- **Coût de la règle de sortie rpm, lu dans `08c/sortie-builds.sh` et non préparé** : l'appliquer demande d'étendre ce script comme pour le deb :
  - étapes `rpm_sec`, `rpm_appliquer`, `rpm_temoins` et `rpm_retirer` ;
  - un invariant qui exige `prefetch-rpm-sortie` seule sur les pods `prefetch-rpm` ;
  - le `NotIn` attendu par `appliquer`, `rejeu` et les contre-épreuves de `deb_sec` ;
  - `builds-sans-internet.yaml`.

  Les invariants `SOUS_REFUS` et `EXCLUS_SANS_SORTIE` refuseraient la politique tant que le `NotIn` ne contient pas `prefetch-rpm`. Tous ces fichiers sont rejoués par S5b : rien n'est modifié avant lui.
