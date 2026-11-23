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
