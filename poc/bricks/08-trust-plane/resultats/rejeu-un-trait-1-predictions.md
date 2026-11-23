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
