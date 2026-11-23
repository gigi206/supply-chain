# Rejeu de zéro d'un trait `un-trait-1` : prédiction (date -u de 20:34:16 UTC, le 2026-11-23, avant le lancement)

**Accords du propriétaire** (verbatim) : « Oui, lance le rejeu » (rejeu de zéro d'un trait avant la pièce 8 de la 07b, VM détruites et recréées) et « Oui, POUSSER_VSA=1 » (VSA poussées dans le Zot neuf).

**Commande** (racine du dépôt) :

```
DISTRO=rke2 POUSSER_VSA=1 TAG_05=m5b-3 mise run confiance:rejeu -- un-trait-1
```

Journal : [`rejeu-un-trait-1.log`](rejeu-un-trait-1.log). `TAG_05=m5b-3` est neuf (aucun journal ni dossier `m5b-3`, relevé par `ls` entre 20:30:47 et 20:34:16 UTC) ; `m5b-1` et `m5b-2` sont pris.

**But** : mesurer, en un seul passage depuis le démontage, ce qui n'a été rejoué que par morceaux le 23/11 :
- les gardes d'avant démontage : `m5b-rejeu.sh entree` (copie `~/.cache/supply-chain-poc/05/rejeu-entrees` présente, relue) et `rejeu-entrees.sh garder` (copie `~/.cache/supply-chain-poc/06/rejeu-entrees` présente, relue) ;
- le bloc 06 dans l'ordre de `rejeu.sh`, avec « 06 (entrées de l'hôte) » `replacer` et « 06 (S4d, prealables) » ;
- le bloc 05 enchaîné (le 23/11, il a tourné par `DEPUIS=`, en deux reprises) ;
- le bloc « 08 (Kyverno corrigé) » (ajouté à 18:43:04Z, **jamais rejoué**) ;
- `fuites` et CIS en fin de rejeu.

## Prédictions

| # | Étape | Attendu | Confiance |
|---|---|---|---|
| U1 | gardes d'avant démontage | `entree` de M5b : copie relue, contrôles tenus ; `garder` de la 06 : « copie présente, relue », 3 OK | haute (mesurées à 18:25 et 20:13) |
| U2 | démontage à « 01 », 19, 19b | comme `plateforme-1` (toutes passées) ; cette fois, les VM existent et sont détruites | haute |
| U3 | 07a, 07b | `g2_image` redonne `b799feda…` ; « 07b (clé VEX) » et « 07b (accès VEX) » tenues ; **`vex-cle-publique.pem` réécrite, SPKI neuve ≠ `d0a12faa…`** (clé Transit recréée) ; G4 pose `vex.pub` | haute |
| U4 | 10 (VSA), contrôles 6 et 7, G6 | tenus, comme dans `plateforme-1` | haute |
| U5 | 08c, J8 (résolveurs), 06 (S1, amorce) | passent, comme dans `plateforme-1` | haute |
| U6 | « 06 (entrées de l'hôte) » | `replacer` : 3 fichiers copiés (`$W` vide après le démontage), `Packages` régénéré `4f2c68d6…`, bilan tenu | haute (banc, 10 cas) |
| U7 | S4c à S4d | image de build `749d746c…`, fermetures deb `bb7599a2…` et sources `50dc73f7…`, artefact deb `60f25f5c…` (comme à la reprise de 19:32 à 20:12) | haute |
| U8 | « 06 (S4d3) » avec `porte` | tient : `porte` tourne avant S6, donc « deb : VSA » et « deb : scan » valent `refus`, comme `s4d3.sh` l'attend (l. 345-346) ; 12 OK | moyenne (jamais jouée dans cet ordre depuis la 07b) |
| U9 | S6a `periodique` à `grafana`, `entrees-scan` | `vex.pub` gardée (= clé neuve de U3), 44 séries, `grafana` tenu ; hors de la fenêtre de 09:00 à 12:59 UTC | haute |
| U10 | S6b et S6a `porte` | `pousser_vsa` et `lire_vsa` tenus ; manifeste de la VSA du deb `97b4100d…` comme le 16/11 et le 23/11 ; `porte` : VSA ok, scan ok, Job 1/ | moyenne pour le digest du manifeste, haute pour le reste |
| U11 | bloc 05 (M5b) | images `70f8c412…` et `6de899ac…`, artefact `333b7322…`, fermeture rpm `09838980…`, rpm relevé `07b7bd6f…` (comparé, non exigé) | haute (au bit près le 23/11) |
| U12 | « 08 (Kyverno corrigé) » | `construire` et `image` tenus, image `eec37159…` (exigée par `kyverno-permanent.sh`) ; `pose` : témoin officiel refusé par l'erreur interne, puis image corrigée : `horodate` PASS, `sans-provenance` FAIL, `hors-livraison` PASS ; bilan tenu | moyenne (bloc jamais rejoué ; `pose` du 23/11 avait un défaut sur `hors-livraison`, corrigé par la zone `confiance`, mesuré par `recette` seulement) |
| U13 | `fuites`, 08b (CIS) | aucun secret ; CIS 20 PASS, 61 FAIL, 42 WARN, comme le `rke2-cis.log` de la reprise du bloc 06 | haute |

**Durée** : somme des durées mesurées le 23/11, 6321 s jusqu'à « 06 (S1, amorce) » (`plateforme-1`), 2364 s pour le bloc 06 (721 + 1643, reprises A et C), 846 s pour le bloc 05 (711 + 135) ; soit 9531 s, plus le bloc Kyverno (non mesuré en rejeu), `fuites` et CIS. Fin attendue avant 01:00 UTC le 24/11, loin de la fenêtre de 09:00.

**Conséquences attendues** : toutes les clés de la plateforme sont neuves (Chains, scanner, TSA, VEX) ; `vex-cle-publique.pem` est à relire et à commiter ; les états posés à la main après `plateforme-1` (l'export Hubble posé à la main le 20/11 n'est pas dans `rejeu.sh`, qui ne nomme Hubble qu'en commentaire ; son état depuis `plateforme-1` n'est pas relevé) sont perdus. Un arrêt se reprend par `DEPUIS=<étape>` sous un `TAG_05` neuf si l'arrêt est dans le bloc 05 ou avant.

**Résultat** : à écrire après la fin, sous ce titre, sans réécrire la prédiction.

## Résultat : arrêt à « J8 (contrôleurs) » (note de 2026-11-23T22:11:46Z)

[Journal](rejeu-un-trait-1.log) : lancé à 20:35:05 UTC, **arrêt à 22:07:01 UTC (code 1)** dans « J8 (contrôleurs) », après « J8 (tests) » (802 s), « J8 (bascule) » (265 s) et « J8 (helm-cilium) » (21 s). Un seul KO : « lectures de Secrets hors de builds ou refusées (403), par l'un ou l'autre : 2 (attendu : 0) ».

| # | Résultat |
|---|---|
| U1 | **tenue** : copies de la 05 et de la 06 relues, contrôles tenus ; démontage en 6 s |
| U2 | **non tenue** : arrêt à « J8 (contrôleurs) » ; toutes les étapes d'avant passent (démontage, VM, RKE2, Cilium, J2 à J7, J8 tests, bascule, helm-cilium) |
| U3 à U13 | non atteintes |

**Cause, mesurée en lecture seule** ([relevé](rejeu-un-trait-1-audit-403.log), script [`rejeu-un-trait-1-audit-403.sh`](rejeu-un-trait-1-audit-403.sh), de 22:11:01 à 22:11:08 UTC) :
- les 2 lignes sont **un seul watch** des Secrets de `builds` par le contrôleur de Pipelines (étapes `ResponseStarted` et `ResponseComplete`), refusé à **21:21:09.219Z**, **2 s après le démarrage de kube-apiserver** (21:21:07Z), redémarré par J7 (pose de la configuration de Kata sur sc-confiance et redémarrage du serveur RKE2) ; raison : RBAC, le compte n'avait plus que les rôles de base ;
- le même watch repasse en 200 à **21:21:12.858Z** (3,6 s après) ;
- **rafale de 72 refus 403** des comptes `system:` et des comptes de service de 21:20:25 à 21:22:20 UTC (nœuds, `kube-controller-manager`, `kube-scheduler`, Triggers, Kyverno, Cilium) : les caches d'autorisation du serveur d'API ne sont pas encore chargés ;
- **aucune écriture** sur les liaisons et rôles `*-tenant-access` après leur pose (20:47:02 à 20:47:41 UTC) ;
- `refus_droits` (journaux des contrôleurs) écarte déjà ces refus depuis le 06/11 (« dans la minute qui suit son démarrage (kata.sh exemption) ») : 0 refus réel, 9 et 2 watch écartés à 21:21:09 ;
- aucun reste de l'étape interrompue (espace `preuve-controleurs` absent).

**Défaut du contrôle, pas des droits** : le contrôle de l'audit compte les 403 « depuis l'installation » sans l'exception que `refus_droits` applique aux journaux. `plateforme-1` a passé le même redémarrage sans ce refus : c'est une course. Seul ce contrôle est concerné : celui des résolveurs (`preuves.sh`, l. 2765) ne compte que les lectures hors de `builds` ; `essais-h5-controleurs.sh` (08c) n'est pas dans le rejeu.

## Correction du contrôle : prédiction (date -u de 22:11:46 UTC, le 2026-11-23, avant l'écriture)

**Correction** (`preuves.sh`, `etape_controleurs`) : le jugement passe dans une fonction `secrets_ctrl_juge` (fichier d'audit, démarrages de kube-apiserver). Un **watch** refusé (403) **dans `builds`**, dans les **60 s** qui suivent un démarrage de kube-apiserver (démarrage courant et précédent du conteneur du pod statique, sous RKE2 seulement ; même fenêtre que `refus_droits`), est écarté et affiché (`CONSTAT`). Tout autre 403, et toute lecture hors de `builds`, comptent comme avant. Témoin ajouté : après chaque watch écarté, une lecture en 200 du même compte dans `builds`.

**Banc hors ligne** (lignes d'audit témoins, fonction lue dans `preuves.sh`) : (1) watch 403 dans `builds` 2 s après un démarrage, suivi d'un 200 : écarté, KO 0, témoin vrai ; (2) le même à 61 s : compté, KO 1 ; (3) un `get` 403 dans `builds` dans la fenêtre : compté (seuls les watch) ; (4) un watch 403 hors de `builds` dans la fenêtre : compté ; (5) une lecture 200 hors de `builds` : comptée ; (6) watch écarté sans 200 après : témoin faux ; (7) aucun démarrage connu (`[]`, k3s) : le cas 1 compte ; (8) les vraies lignes d'audit du rejeu, relevées sur sc-confiance : KO 0, témoin vrai, 2 lignes écartées. **Bilan attendu : 0 écart.**

## Correction du contrôle : résultat (note de 2026-11-23T22:13:04Z)

`secrets_ctrl_juge` écrit dans `preuves.sh` (commit `13b0b51c`) ; [banc](controleurs-juge-banc.log) ([script](controleurs-juge-banc.sh)) de 22:12:58 UTC : **12 cas, 0 écart**, la prédiction de 22:11:46Z tient (cas 1 à 8, plus un cas 7b : deux démarrages connus, refus dans la fenêtre du premier, écarté). Sur les **vraies lignes d'audit** du rejeu (40 lignes, démarrages `[1795468867,1795468866]`) : l'ancien contrôle compte 2, le nouveau 0, avec 2 lignes `ECARTE` affichées et le témoin 200 vrai.

**Limites** : les démarrages connus sont le courant et le précédent du conteneur kube-apiserver ; un redémarrage plus ancien de deux crans n'est pas couvert (il compterait, contrôle plus strict). Sous k3s (pas de pod statique), rien n'est écarté, comme dans `refus_droits`. La rafale mesurée court jusqu'à 73 s après le démarrage (21:22:20Z) ; la fenêtre reste de 60 s, celle de `refus_droits`, plus stricte. **Non mesuré** : `etape_controleurs` entière avec la correction (elle tournera à la reprise ou au rejeu suivant).

**Suite, au choix du propriétaire** : reprise à « J8 (contrôleurs) » (libellé neuf, `TAG_05=m5b-4` : `entree` refuse `m5b-3`, dont le journal existe ; reprise antérieure au bloc 08c, non encore appliqué : permise par `rejeu.sh`, l. 40-43), ou rejeu de zéro sous un libellé neuf.

## Reprise à « J8 (contrôleurs) » : prédiction (date -u de 22:14:20 UTC, le 2026-11-23, avant le lancement ; choix du propriétaire « Reprise, VSA=1 »)

**Commande** : `DISTRO=rke2 POUSSER_VSA=1 TAG_05=m5b-4 DEPUIS='J8 (contrôleurs)' mise run confiance:rejeu -- un-trait-1-reprise`. Journal [`rejeu-un-trait-1-reprise.log`](rejeu-un-trait-1-reprise.log). Libellé et `TAG_05=m5b-4` libres (relevé par `ls` à 22:14:20 UTC).

**Prédiction** :
- R0, avant tout démontage (blocs exécutés même en reprise) : `m5b-rejeu.sh entree` sous `m5b-4` (copie relue) et `rejeu-entrees.sh garder` (copie relue) tenus ; étapes antérieures « sautées » ;
- R1, « J8 (contrôleurs) » : tenue, avec 2 lignes `CONSTAT  écarté, kube-apiserver démarrant` (le watch de 21:21:09Z) ; le reste de l'étape comme dans `plateforme-1` ;
- puis U3 à U13 de la prédiction de 20:34:16Z, inchangées (07a et 07b avec clé VEX neuve ≠ `d0a12faa…` ; VSA et contrôles 6, 7, G6 ; 08c ; « 06 (entrées de l'hôte) » `replacer` : 3 fichiers copiés, `$W` ayant été effacé par le démontage de 20:35 ; S4c à S6a ; S4d3 `porte` ; S6b et S6a `porte` ; bloc 05 sous `m5b-4` ; Kyverno corrigé ; `fuites` et CIS).

**Durée** : à partir des mesures de `un-trait-1` et `plateforme-1`, environ 2 h (calcul, non garanti) ; fin attendue avant 01:00 UTC, loin de la fenêtre de 09:00.

**Réserve** : ce n'est plus un rejeu « d'un trait » : le démontage et les étapes jusqu'à « J8 (helm-cilium) » viennent du passage de 20:35:05Z.

## Reprise à « J8 (contrôleurs) » : résultat (note de 2026-11-23T23:35:45Z)

[Journal](rejeu-un-trait-1-reprise.log) : lancé à 22:14:34 UTC, **fin à 23:34:39 UTC, code 0**, durée totale mesurée **4805 s** (80 min ; calcul de la prédiction : environ 2 h). **Aucun KO** dans la sortie (`grep -c KO` : 0).

| # | Résultat |
|---|---|
| R0 | **tenue** : `m5b-rejeu.sh entree` sous `m5b-4` (TAG libre, copie relue, 4 rendus et 5 fichiers signés contrôlés, rien écrit) ; `rejeu-entrees.sh garder` : copie relue, 3 OK, « bilan : tenu » ; démontage à « J8 (helm-cilium) » : « sautée » |
| R1 | **tenue** : « J8 (contrôleurs) » en 22 s ; 2 lignes `CONSTAT  écarté, kube-apiserver démarrant` pour le watch de 21:21:09.219027Z (`ResponseStarted` et `ResponseComplete`), plus les refus écartés des journaux par `refus_droits` (9 et 2 lignes, comme dans le relevé de 22:11) |
| U3 | **tenue** : `g2_image` redonne `b799feda…` (second assemblage, épingle et lecture anonyme) ; « 07b (clé VEX) » et « 07b (accès VEX) » tenues ; `vex-cle-publique.pem` réécrite, **SPKI neuve `aeef0a8c482be447cfee461f80660b7941f10f03ec09a55acf4af9bdafeea710`** (≠ `d0a12faa…`, relue par `openssl pkey` à 23:35 UTC) ; seule différence dans Transit : `transit/keys/vex` ajoutée |
| U4 | **tenue** : 10 (VSA) 5 s ; contrôles 6 et 7 : « 0 écart(s) aux prédictions » ; G6 183 s, 0 écart |
| U5 | **tenue** : 08c (H1, H4, S1, H5, sortie des builds), J8 (résolveurs) 10 s, 06 (S1, amorce) 3 s |
| U6 | **tenue** : `replacer` : 3 fichiers, `Packages` `4f2c68d6…`, « bilan : tenu » |
| U7 | **tenue** : S4c, S4a (339 s), S4b (189 s), S4d (783 s) ; image de build `749d746c…`, fermetures `bb7599a2…` et `50dc73f7…`, artefact deb `60f25f5c…` (« deux exécutions, même artefact ») |
| U8 | **tenue** : « 06 (S4d3) » 810 s ; `porte` : 12 OK, « deb : VSA » et « deb : scan » à `refus` |
| U9 | **tenue** : `periodique` et `fraicheur` « tout OK » ; `vex.pub` de scan-config égale à la clé archivée (fichier `d40d41a0…`, soit la SPKI `aeef0a8c…`) ; 44 séries écrites ; `grafana` « tout OK » |
| U10 | **tenue** : `pousser_vsa` et `lire_vsa` « tout OK » ; manifeste de la VSA du deb **`97b4100d…`**, le même que le 16/11 et le 23/11 ; `porte` : VSA ok, scan ok, Job 1/ |
| U11 | **tenue** : images `70f8c412…` et `6de899ac…`, artefact `333b7322…`, fermeture rpm `09838980…`, rpm `07b7bd6f…` (égal à celui de la cascade) ; bloc 05 en 808 s |
| U12 | **tenue** : `construire` OK (binaire `2b36652a…`) ; `image` : **`eec37159…`** (fichier `kyverno-admission-image.digest` inchangé) ; `pose` : témoin officiel FAIL avec erreur interne, puis image corrigée : `horodate` PASS, `sans-provenance` FAIL, `hors-livraison` PASS, sans erreur interne ; « bilan : tenue ». **Premier rejeu du bloc** |
| U13 | **tenue** : `fuites` : aucun secret dans les journaux des trois VM ; CIS : `rke2-cis.log` identique au précédent à la ligne d'en-tête près (sc-confiance 80 PASS, 5 FAIL, 38 WARN ; sc-build 20 PASS, 61 FAIL, 42 WARN) |

**Conséquences** : clés publiques archivées réécrites (scanner `007f233f…`, VEX `aeef0a8c…`, témoin de G6) ; les clés Transit `chains`, `scanner` et `tsa` sont en version 1 dans l’OpenBao du passage de 20:35 ; l’image corrigée de Kyverno est en service ; l’export Hubble posé à la main le 20/11 n’est pas dans `rejeu.sh` : perdu avec les VM (non relevé dans Cilium). **Non mesuré** : un rejeu entier d'un seul trait avec la correction de `secrets_ctrl_juge` (le démontage et J2 à « J8 (helm-cilium) » viennent du passage de 20:35:05Z).
