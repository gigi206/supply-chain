# Banc Debian (option E du plan de sortie de Nix) : prédictions (13/11/2026, avant toute exécution)

Décisions du propriétaire : « Oui, les deux » (régulariser Nix et instruire l'option Debian par un banc), puis « Oui, prépare-le ».
Script : [`banc-debian.sh`](../banc-debian.sh), étapes `lecture` (réseau, accord nommé) et `simulation` (hors réseau). Les étapes
`image`, `essai` et la mesure de fermeture viendront après la simulation, écrites sur sa liste réelle, avec leurs propres prédictions.

## Ce que le banc est, et n'est pas
- Contenu Debian de l'instantané de la 06 (`20261105T000000Z`, clés de ftp-master épinglées dans `s1.sh` l. 33) à la place de la
  clôture Nix de `outils-prefetch` (python313, gitMinimal, cacert, busybox).
- **Pas l'option E elle-même** : E construirait l'image dans la chaîne, comme S4a de la 06 construit `sbuild-debian13`
  (`749d746c`) par mmdebstrap dans un PipelineRun. Le banc résout la fermeture avec l'apt de l'hôte (3.2.1, solveur de l'hôte,
  pas celui de trixie) et, plus tard, extraira les paquets par `dpkg-deb -x` (aucun script de mainteneur) : son digest ne sera pas
  celui de E.
- Hors cluster, rien installé sur l'hôte, hors de sc-replay. BuildKit et runc de l'étape `image` viendront de Nix (outils de
  l'hôte) : le banc ne mesure pas l'option C.

## Lecture

| # | Prédiction | Confiance |
|---|---|---|
| L1 | Signataires d'InRelease = les trois empreintes épinglées | Haute : même instantané et mêmes clés que S1 de la 06 |
| L2 | `Packages.xz` égal à l'empreinte d'InRelease | Haute |
| L3 | python3.13 en `3.13.5-2+deb13u5` | Haute : relevé dans les journaux de S1 et S2 |
| L4 | python3.13-venv, git, ca-certificates et busybox-static présents | Moyenne : noms non relus dans ce Packages |

## Simulation

| # | Prédiction | Confiance |
|---|---|---|
| S1 | Code 0, aucune interface que `lo` | Haute : essai à sec sur un Packages synthétique (13/11, 13:48 UTC) |
| S2 | Aucun paquet Essential tiré sans être une dépendance | Faible : vu sur des données synthétiques seulement |
| S3 | git tire perl | Moyenne : non relu |
| S4 | Installed-Size de la fermeture au-dessus des 263 Mo de la clôture Nix (sans Go ni Hermeto) | Faible |

## Les quatre critères de confiance (jugés au fil du banc, pour les deux options)

| Critère | Nix (aujourd'hui) | Debian (banc) |
|---|---|---|
| Clé épinglée dans le dépôt, contrôlée au passage | non (configuration de l'hôte) | à mesurer par L1, à chaque lecture |
| Le serveur seul peut-il falsifier ? | non si signature vérifiée ; un seul signataire (Hydra) | non : InRelease signé |
| Binaires amont reconstruits | 9 chemins sur 45 égaux à Hydra, ni python ni git | aucun ; non visé par ce banc |
| Verdict doc 04 | « À surveiller, chemin critique » (13/11) | archive non évaluée comme source |

## Règle des 2× (brique 03, jalons F : 1 pw, décision à 2 pw)
Consommé recompté le 13/11 à 13:45:10 UTC (heures de git et `date -u`, 40 h par pw) : 03/11 de 16:13:24 à 19:58:45 UTC, 0,094 pw ;
13/11 de 10:58:20 UTC (échec de F2) à 13:45:10 UTC, 0,070 pw, partagé avec S5b de la 08 : **de 0,094 à 0,163 pw**. Non relevé :
les parties locales des briques 03 et 04 d'avant le protocole F. Projection du banc (estimation, non mesurée) : 0,2 à 0,5 pw,
soit 0,36 à 0,66 pw au plus, sous l'estimation de 1 pw. Aucune décision due.

## Résultats de lecture et simulation (note de 2026-11-13T13:53:02Z ; rien n'est réécrit)

Lancées sur « Oui, lance-les » à « Je lance banc-debian.sh lecture simulation ? », de 13:52:21 à 13:52:27 UTC, code 0
([lecture](banc-debian-lecture.log), [simulation](banc-debian-simulation.log)).
- **L1 tenue** (trois signataires épinglés) ; InRelease `0584fba3…`, **égal à celui de S1 de la 06** (10/11) : instantané inchangé.
- **L2 tenue** ; Packages : 68 825 paragraphes. **L3 tenue** (python3.13 `3.13.5-2+deb13u5`). **L4 tenue** : python3.13-venv
  `3.13.5-2+deb13u5`, git `1:2.47.3-0+deb13u1`, ca-certificates `20250419`, busybox-static `1:1.37.0-6+b9`.
- **S1 tenue** (code 0, `lo` seule). **S2 tenue** : un seul paquet Essential, perl-base, dépendance de perl ; base-files absent.
  **S3 tenue** : git tire perl, libperl5.40 et perl-modules-5.40 (environ 57 Mo installés à eux trois). **S4 non tenue** :
  fermeture de 69 paquets, 47,5 Mo de .deb, **183,7 Mo installés**, sous les 263 Mo de la clôture Nix.
- Dépendances lues : python3.13-venv tire python3-pip-whl et python3-setuptools-whl ; ca-certificates tire openssl et debconf
  (le fichier `ca-certificates.crt` est produit par un script de mainteneur, que `dpkg-deb -x` n'exécutera pas).
- Questions ouvertes pour l'étape `image` : base-files absent, donc ni `/bin` ni `/lib64` fournis par un paquet de la fermeture
  (à vérifier sur les .deb par `dpkg-deb -c`) ; bundle de certificats à reconstituer ; écart avec E (S4a, mmdebstrap, scripts).

## Note de 2026-11-13T13:53:16Z : correction des résultats (rien n'est réécrit)
1. « environ 57 Mo installés à eux trois » est faux : perl, libperl5.40 et perl-modules-5.40 font 50 156 Kio installés, soit
   **49,0 Mo** ; avec perl-base, 57 971 Kio, soit 56,6 Mo (Installed-Size du journal de simulation, en Kio).
2. « le fichier `ca-certificates.crt` est produit par un script de mainteneur » n'est **pas vérifié** (écrit de mémoire) : à lire
   dans le .deb de ca-certificates (scripts de contrôle) à l'étape `image`.
