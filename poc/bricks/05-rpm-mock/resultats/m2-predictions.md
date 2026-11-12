# Brique 05, M2 : protocole et prédictions du relevé (écrits le 12/11/2026 à partir de 14:37:18 UTC, avant toute exécution)

Sur « Oui, prépare M2 ». **Rien n'a été lancé, et rien n'a été lu sur le réseau pour M2.** M2 n'est pas un script fini.
- Ses étapes dans le cluster dépendent de ce que S1 mesurera après S5b : l'isolation (P9), le stockage de podman (P8) et mock en root (P12).
- La syntaxe du mode hermétique de mock n'est pas encore relevée. Aucune option n'est écrite de mémoire.

Seule l'étape `releve` de [`m2.sh`](../m2.sh) est écrite. Elle attend un accord.

## Objet de M2 (README)

M2 versionne la configuration de mock, calcule le verrou et vérifie les signatures des rpm. Il pousse ensuite la fermeture dans Zot sous `deps/sample-app/mock-buildroot-lock`, avec le rpm de mock et l'image de bootstrap. Preuves attendues : fermeture restaurable par digest, et déduplication mesurée.

Le rangement suit celui de la 06. Sa fermeture manuelle de S2 est sous `deps/sample-app/deb-buildinfo`, celle de Tekton (S4b) sous `builds/fermetures/sample-app-deb`, la seule que lise la porte. M2 est manuel, donc `deps/` ; M4 passera par `builds/fermetures/sample-app-rpm`.

## Faits déjà établis, sans réseau

Source : le primary d'EPEL vérifié par `s1.sh hote` le 12/11 (`~/.cache/…/travail/s1-05/epel9.primary.xml`).

- **mock 6.9-1.el9 livre** `/usr/bin/mock-hermetic-repo` et `/etc/mock/hermetic-build.cfg`.
- **Il exige** createrepo_c, systemd-container, usermode, python3-pyroute2, pigz et tar, entre autres. Cela confirme la part de P5 sur systemd-container.
- **Il recommande seulement** podman, skopeo, buildah, fuse-overlayfs, dnf-utils et python3-dnf-plugins-core. Avec `install_weak_deps=0`, podman et skopeo ne viennent que parce que S1 les épingle.
- **mock-core-configs 45.2-1.el9 exige** `(python3-libdnf5 or (python3-dnf and python3-hawkey))`, `distribution-gpg-keys` et `system-release`.

## Étape `releve` (hôte seul, sur accord)

Elle lit les sources de mock au tag `mock-6.9-1` (codeload de GitHub), comme `sante.sh` le 05/11. Elle archive au journal les lignes qui fixent la syntaxe et le comportement du mode hermétique :
- options de `mock.py` et de la page de manuel ;
- arguments et commandes de `mock-hermetic-repo` ;
- contenu de `hermetic-build.cfg` ;
- clés du verrou ;
- traitement de `bootstrap_image_ready` ;
- documentation.

Puis elle efface les sources.

| # | Prédiction | Confiance |
|---|---|---|
| M1r | L'archive du tag donne `Version: 6.9` dans `mock.spec` | Haute |
| M2r | `mock.py` déclare `--calculate-build-dependencies` et `--hermetic-build` ; `--hermetic-build` prend un verrou et un dépôt local | Moyenne : les noms viennent du relevé amont du 05/11 (documentation, ligne 9), pas la forme des arguments |
| M3r | `mock-hermetic-repo` prend un verrou et un répertoire de sortie, télécharge les rpm, lance `createrepo_c` et tire l'image de bootstrap par `skopeo sync` vers un répertoire | Moyenne : `skopeo sync … --dest dir` est au journal de l'audit du 05/11 ; le reste est déduit |
| M4r | Le verrou enregistre le digest de l'image de bootstrap (`image_digest`, d'après `buildroot_lock.py` lu le 05/11) et, pour chaque rpm, son NEVRA, son URL et sa somme | Moyenne |
| M5r | Le mode hermétique impose `bootstrap_image_ready = True` et `use_bootstrap_image = True`. Dans ce cas, l'image doit déjà contenir dnf et ses greffons | Moyenne : la documentation l'exigeait le 05/11 ; ce qu'elle doit contenir n'est pas lu |
| M6r | Archive de moins de 2 Mo, étape de moins de 30 s | Faible |

## Embranchements de M2, à trancher après S1 et le relevé

1. **Lieu de la résolution (D3 a).**
   - La décision dit : « résolution sur l'hôte d'abord, comme le prefetch de la 03, puis dans Tekton en M4 ». Or l'hôte n'a ni mock ni dnf, et l'installer sur l'hôte demanderait ton accord.
   - Lecture proposée : « hors Tekton d'abord », c'est-à-dire `--calculate-build-dependencies` dans un pod Kata à la main, comme S1, puis dans Tekton en M4.
   - **Cette lecture s'écarte du texte de D3 (a) : c'est une question au propriétaire.**
2. **Image de bootstrap prête.**
   - S1 tire `rockylinux:9.7` brut et laisse mock y installer dnf (`bootstrap_image_ready = False`).
   - Si M5r se confirme et que l'image brute ne suffit pas, il faudra une image de bootstrap construite par notre chaîne, par digest, avec dnf et ses greffons. Ce serait un jalon et une décision de plus.
   - Si l'image brute suffit, M2 la range telle quelle dans la fermeture.
3. **Isolation, stockage de podman, utilisateur** : repris de S1 (P8, P9, P12). Un échec de S1 sur l'un d'eux arrête M2 avant son écriture.
4. **Sortie réseau** : `prefetch-rpm-sortie` sert à la résolution et au téléchargement par `mock-hermetic-repo`. `--hermetic-build` tournera dans un pod sans ce label, donc sous `builds-sans-internet`. Ce sera le premier pas vers M3, sans réseau.

## Limites

- L'archive de codeload n'est pas signée. Seul son sha256 est journalisé. Le rpm de mock, lui, est signé par EPEL et contrôlé en S1.
- Le relevé lit le code du tag, pas le rpm installé. Un écart entre les deux sera visible en S1, où la sonde affiche les versions.
