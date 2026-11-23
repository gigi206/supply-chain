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

## Résultat (note de 2026-11-23T20:14:03Z)

**Les trois lancements tiennent, aucun KO** : A, B et C finissent en code 0 ; les journaux réécrits de S4a, S4b, S4d, S4d3 et S6a ont 0 ligne `KO`.

- **A**, de 19:32:29 à 19:44:30 UTC ([journal](../../08-trust-plane/resultats/rejeu-06-reprise-a.log)) :
  - **R1 tient** : image de build `749d746c…` deux fois.
  - **R2 tient** : fermeture deb `bb7599a2…` deux fois ; fermeture des sources `50dc73f7…` deux fois ; `comparaison` passe.
- **B**, à 19:44:42 UTC ([journal](s4d-prealables.log)) : **R3 tient**, `digest-attendu` vaut `sha256:60f25f5c…`.
- **C**, de 19:44:55 à 20:12:18 UTC ([journal](../../08-trust-plane/resultats/rejeu-06-reprise-c.log)) :
  - **R4 tient** : artefact `builds/sample-app-deb@60f25f5c…` deux fois, égal à `digest-attendu`.
  - **R5 tient** : S4d3 `retirer prealables deployer chemins` passe ; la porte est sautée.
  - **R6 tient** :
    - S6a `periodique` applique `s6a-scanner-deb.patch` ;
    - `vex.pub` de `scan-config` est égale à la clé VEX archivée (fichier `04967fbe…`, SPKI `d0a12faa…`) ;
    - le scan du deb donne `VEX|0 énoncé(s)` (dépôt `builds/vex/sample-app-deb` absent) et `SCAN|… 67 vulnérabilités, 0 KEV, 0 écartée(s) par un VEX` ;
    - `fraicheur` passe ;
    - « 07b (entrees-scan, pose) » écrit 44 séries ;
    - `grafana` voit dans Grafana sept préfixes du scan (`SOURCE`, `BASE`, `DEB`, `ARTEFACT`, `SCAN`, `ATTESTATION`, `PUBLIE`) et la révocation du jeton du rôle scanner *(corrigé à 2026-11-23T20:18:03Z : la note disait « huit préfixes », non compté ; `VEX|` n'est pas dans la liste contrôlée par `s6a.sh grafana`)*.
- **R7** n'est pas mesurée directement : l'état de l'alerte `ScanEnRetard` n'a pas été lu. `fraicheur` lit dans Prometheus un dernier referrer du scan du deb à 20:11:55 UTC.

**Correction structurelle, écrite après C** (`rejeu.sh` ne tournait plus) :
- **`rejeu-entrees.sh`**, script neuf de la 06 :
  - `garder` s'exécute avant le démontage. Il copie l'InRelease, `Packages.xz` et le deb de S3 dans `~/.cache/supply-chain-poc/06/rejeu-entrees`, avec leurs empreintes épinglées. Une copie déjà présente est relue, jamais réécrite. En cas d'échec, rien n'est démonté.
  - `replacer` s'exécute avant « 06 (S4c) ». Il recopie ces fichiers et régénère `Packages` par `xz -dc`.
  - [Banc](rejeu-entrees-banc.log) jetable : 10 cas, 0 écart. La vraie copie a été faite à 20:13:03Z ([garder](rejeu-entrees-garder.log), [replacer](rejeu-entrees-replacer.log)).
- **`rejeu.sh`** :
  - `garder` passe avant le démontage, sous RKE2 et Cilium ;
  - nouvelle étape « 06 (entrées de l'hôte) » avant « 06 (S4c) » ;
  - nouvelle étape « 06 (S4d, prealables) » avant « 06 (S4d) » ;
  - le commentaire des exclusions est corrigé.
  - **Pas encore rejoué de zéro** : seule la syntaxe est contrôlée (`bash -n`).

**Reste, sur accord nommé** : avec `POUSSER_VSA=1`, les étapes S6b `pousser_vsa` et `lire_vsa`, puis S6a `porte` et `s4d3.sh porte`. La CA lue par `pousser_vsa` est identique à celle de la 08 (`cmp`).

## Fin de reprise : `fuites`, CIS et câblage (prédiction, `date -u` de 2026-11-23T20:16:49Z, avant les lancements ; relue par le conseiller)

`fuites` et CIS ont tourné à 18:27 UTC, à la fin de M5b, donc **avant** le bloc 06. Le 13/11, la reprise du bloc 06 se terminait par eux. Dans `rejeu.sh`, ils suivent les étapes Kyverno : aucun `JUSQUA` ne les isole. Ils sont donc lancés directement.

- **F1** : `mise run confiance:fuites -- 06-reprise-fin` (journal `08-trust-plane/resultats/fuites-06-reprise-fin.log`). Attendu : aucun secret, comme le `fuites` de 18:27 UTC. Confiance moyenne : le bloc 06 a créé des pods et des journaux neufs.
- **F2** : `DISTRO=rke2 mise exec -- poc/bricks/08b-rke2/rke2.sh cis` (journal `rke2-cis.log` réécrit ; version de 18:28 dans git). Attendu : 20 PASS, 61 FAIL, 42 WARN, comme à 18:28 UTC. Confiance haute : le bloc 06 ne touche ni aux nœuds ni à leur configuration.
- **F3**, le câblage de `rejeu.sh` (sans démontage) : `DISTRO=rke2 DEPUIS="06 (entrées de l'hôte)" JUSQUA="06 (entrées de l'hôte)" mise run confiance:rejeu -- 06-cablage`. Attendu :
  - `garder` tourne avant le démontage sautée et dit « copie présente, relue » ;
  - l'étape « 06 (entrées de l'hôte) », au libellé à apostrophe, est trouvée par `DEPUIS` et `JUSQUA` ;
  - `replacer` dit « déjà présent » quatre fois, bilan tenu ;
  - arrêt après cette étape ; rien d'autre ne tourne, `TAG_05` étant absent.
  - Confiance haute.

## Fin de reprise : résultat (note de 2026-11-23T20:18:03Z)

- **F1 tient** : `fuites` finit en code 0, avec « aucun secret dans les journaux des trois VM » ([journal](../../08-trust-plane/resultats/fuites-06-reprise-fin.log)).
- **F2 tient** : CIS donne 20 PASS, 61 FAIL, 42 WARN. Le journal `rke2-cis.log` ne diffère de la version de 18:28 UTC que par sa ligne d'en-tête datée (`git diff` : une ligne).
- **F3 tient**, de 20:17:12 à 20:17:12 UTC ([journal](../../08-trust-plane/resultats/rejeu-06-cablage.log)) :
  - `garder` tourne avant le démontage sauté et dit « copie présente, relue » (3 OK) ;
  - `DEPUIS` et `JUSQUA` trouvent l'étape au libellé à apostrophe ;
  - `replacer` dit « déjà présent » quatre fois, bilan tenu ;
  - arrêt après cette étape, et rien d'autre ne tourne.
  - Le câblage est donc exercé, sauf le démontage : la copie qui précède un vrai démontage n'est mesurée qu'au banc.
- **R7 tient**, lu dans Prometheus à 20:17:29Z :
  - `ALERTS{alertname=~"Scan.*"}` est vide ;
  - sur les deux heures précédentes, `ScanEnRetard` du dépôt `builds/scan/sample-app-deb` était `firing` ;
  - l'alerte a donc cessé après le scan du deb. Son heure de fin n'a pas été lue.
- **Heures** : de 19:31:27 UTC (deb replacé) à 20:18:03 UTC, soit 46 min 36 s, comptées au rejeu de zéro (la 06 est close).
  - Les fins de A (19:44:30) et de C (20:12:18) sont calculées : heure de début du journal plus durée affichée par `rejeu.sh`.
- **Journaux réécrits** par les scripts : leurs versions précédentes sont dans `a32c5689`.

## VSA du deb et portes : prédiction (`date -u` de 2026-11-23T20:21:43Z, avant les lancements ; accord du propriétaire « Oui, POUSSER_VSA=1 »)

**Ordre choisi** : dans le rejeu complet, `s4d3.sh porte` tourne avant S6, quand le deb n'a ni scan ni VSA. Le script attend donc « refus » pour les deux. Elle est lancée ici **en premier** (V1), avant `pousser_vsa`, pour rester au plus près de cet ordre. Le scan du deb existe déjà (S6a `periodique`, 20:11 UTC) : **un écart d'ordre est prévu** sur la mesure « deb : scan ».

- **V1** : `DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4d3.sh porte` (journal `s4d3-porte.log` réécrit ; version du 15/11 dans git).
  - Attendu : `ec` en succès, sans violation, avertissement `trusted_task.tagged` ; horodatage `ok`, enveloppes toutes couvertes ; VSA `refus` ; les cinq règles du PoC parmi les succès ; image sample-app `true||trusted_task.tagged`, horodatage `ok`, VSA et scan `ok|ok`.
  - **Écart prévu** : « deb : scan » vaut `ok`, attendu `refus` par le script. Le scan du deb est présent et sans KEV, et la porte en service (pièce 6) l'accepte. Le bilan du script sera donc KO pour cette seule mesure.
  - Confiance : moyenne. La porte a changé avec la pièce 6, et sa nouvelle règle n'a jamais jugé le deb.
- **V2** : `DISTRO=rke2 POUSSER_VSA=1 DEPUIS='06 (S6b, pousser_vsa)' JUSQUA='06 (S6a, porte)' mise run confiance:rejeu -- 06-vsa` (journal `08-trust-plane/resultats/rejeu-06-vsa.log`).
  - `garder` relit la copie avant le démontage sauté.
  - `pousser_vsa` : bundle archivé revérifié sur l'hôte, sans connexion hors de Zot. Manifeste poussé `sha256:97b4100d…`, comme le 16/11 (confiance moyenne à haute : manifeste sans annotation datée). Referrers et étiquettes de `builds/sample-app-deb` inchangés.
  - `lire_vsa` : tout OK. La VSA est acceptée par la clé du domaine seule, et la provenance par la clé de Chains seule.
  - S6a `porte` : `ec` en succès, horodatage `ok`, VSA `ok`, scan `ok`, Job de la porte `1/`.
  - Confiance moyenne : la porte a changé avec la pièce 6 et n'a jamais jugé le deb depuis.
