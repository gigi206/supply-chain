# Reprise du bloc 06 après le rejeu de zéro du 23/11 : carte et prédictions (écrites avant tout lancement)

Heure de rédaction : `date -u` = 2026-11-23T19:31:36Z, depuis HEAD `a32c5689`. Rien n'est encore lancé.

Le rejeu `plateforme-1` s'est arrêté dans « 06 (S4c) » : `vm.sh detruire` avait effacé les entrées de l'hôte sous `$W`. S4c et
S4b (sources) ont été refaits plus tôt dans la journée, depuis les fichiers retrouvés, puis M5b a repris sous `TAG_05=m5b-2`.
Ne sont pas rejoués : S4a, S4b `deb` et `comparaison`, S4d, S4d3, S6a (periodique, fraicheur, grafana) et « 07b (entrees-scan, pose) ».

## Correction d'une annonce

La [carte de la 07b](../../07a-sbom-grype/resultats/07b-carte.md) (note de 16:53:47Z), mon recap et mon message de clôture de
19:22 UTC disaient « `racine.tar` et `chroot.tar` à refaire par S1 et S2 ». **C'est faux pour le rejeu.**
- `s4a.sh` ne lit ces deux archives qu'à la ligne 324, dans `etape_comparaison`.
- Le rejeu ne lance de S4a que `prealables taches reseau pipeline` (`rejeu.sh`, l. 217).
- La reconstruction de S1 et S2 (pods Kata, instantané Debian) n'est donc pas nécessaire. Le 13/11, elle l'était pour la révision 1.0.0-1, parce qu'il fallait refaire aussi le deb de S3.

## Ce que le bloc lit sous `$W` et qui ne vient pas du rejeu

| Entrée | Lue par | État à 19:31 UTC |
|---|---|---|
| `s1-06/hote/InRelease`, `s1-06/hote/Packages.xz`, `s1-06/Packages` | S4c (l. 30-31), S4a `prealables` (l. 88-89) | replacés plus tôt ce jour depuis `03/banc-debian/hote` : `0584fba3…`, `7778d3e3…` |
| `s3-06/build-1/sample-app_1.0.0-2_amd64.deb` | `s4d.sh prealables` (l. 239) | **replacé à 19:31:27Z** depuis `~/.cache/supply-chain-poc/07a/t3/mesure0/deb-couche/` (deb extrait de l'artefact pendant la mesure 0 de la 07b) ; sha256 `f66bbeb2aba31e5220b332ff3941697dce7660259aa182047a58e77f4f51892b`, égal à `DEB_SHA` (S3, révision 1.0.0-2) ; 1 953 492 octets, 0644 |
| `s4b-06/comparaison/…`, `s4b-06/packaging` | `s4d.sh prealables` (`entrees_hote`) | refaits par « 06 (S4b) » du lancement A |
| `s4d-06/digest-attendu` | `s4d.sh pipeline` (l. 327, 540) | refait par le lancement B (`s4d.sh prealables`, exclu du rejeu) |

`s6a.sh` ne lit `$DEB` que dans `releve` et `essai`, hors rejeu. `entrees-scan.sh pose` ne lit rien sous `$W`.

## Séquence (accord implicite des lancements ; aucune VSA poussée)

- **A** (journal `08-trust-plane/resultats/rejeu-06-reprise-a.log`) :
  `DISTRO=rke2 DEPUIS='06 (S4a)' JUSQUA='06 (S4b)' mise run confiance:rejeu -- 06-reprise-a`
  Ni `TAG_05`, ni `POUSSER_VSA`.
- **B** (hôte seul, `unshare -rn`) : `DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4d.sh prealables`
- **C** (journal `rejeu-06-reprise-c.log`) :
  `DISTRO=rke2 DEPUIS='06 (S4d)' JUSQUA='06 (S6a, grafana)' mise run confiance:rejeu -- 06-reprise-c`
  - Sans `POUSSER_VSA` : « 06 (S4d3) » sans la porte.
  - « 06 (S6a, grafana) » est la dernière étape qui tourne dans ce cas.
  - Les étapes Kyverno de fin de rejeu ne sont pas atteintes.
- **Après, sur accord nommé** : `POUSSER_VSA=1` pour `s6b pousser_vsa`, `lire_vsa` et `s6a porte`, et pour `s4d3.sh porte`.

Les journaux propres aux scripts sont réécrits, comme à chaque rejeu ; les versions archivées restent dans git. Sont concernés `s4a-prealables`, `-taches`, `-reseau`, `-pipeline` ; `s4b-*` ; `s4d-prealables`, `-reseau`, `-taches`, `-pipeline` ; `s4d3-chemins` ; `s6a-periodique`, `-fraicheur`, `-grafana`.

## Prédictions

| # | Prédiction | Confiance |
|---|---|---|
| R1 | A : S4a `prealables` passe (Packages égal à `xz -dc Packages.xz`) ; image de build `builds/builders/sbuild-debian13@sha256:749d746c…` deux fois, comme le 13/11 | Moyenne : S4a non rejoué depuis le 13/11 ; scripts S4a inchangés depuis (`git log`) ; instantané et bundles épinglés |
| R2 | A : S4b `deb` : fermeture `bb7599a2…` deux fois ; `sources` : `50dc73f7…` (troisième fois ce jour) ; `comparaison` passe | Moyenne |
| R3 | B : `digest-attendu` = `sha256:60f25f5c3fb58b7c4be625c4e20222aeef35b1490f18af4f58cadc1e27f8279e` | Haute : même deb, mêmes entrées que le 14/11 |
| R4 | C : S4d : artefact `builds/sample-app-deb@60f25f5c…` deux fois, égal à `digest-attendu`, deb égal à `f66bbeb2…` | Moyenne |
| R5 | C : S4d3 `retirer prealables deployer chemins` passe sans la porte | Basse : S4d3 n'a été rejoué de zéro qu'une fois (13/11, après un correctif) |
| R6 | C : S6a `periodique` garde `vex.pub` dans `scan-config` (mesure du script) et applique `s6a-scanner-deb.patch` (`abd0abc1…`) ; `fraicheur` passe ; « 07b (entrees-scan, pose) » écrit ses séries ; `grafana` passe | **Basse** : l'intégration de S6 n'a jamais été rejouée de zéro ; la 07b y a touché aujourd'hui |
| R7 | Après C : l'alerte `ScanEnRetard` du deb cesse au premier scan du deb ; heure non prédite | Basse |

Arrêt : relevé, corrigé dans le dépôt si la cause est dans le code, repris par `DEPUIS=` sous un libellé neuf.
Ce que ce document ne règle pas : le prochain rejeu de zéro effacera de nouveau `$W`. La correction structurelle, sur le modèle de `m5b-rejeu.sh entree` (copies hors de `$W`, empreintes épinglées, contrôle avant le démontage, recopie avant « 06 (S4c) »), sera écrite après C, `rejeu.sh` n'étant jamais modifié pendant qu'il tourne.
