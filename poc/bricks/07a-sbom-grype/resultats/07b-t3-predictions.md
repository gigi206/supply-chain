# 07b, tranche 3 : prédictions écrites avant chaque passage

Chaque section est écrite avant le passage qu'elle prédit et n'est jamais réécrite. Un écart se dit dans la carte.

## Mesure 0 : composant `container` dans la fusion (écrite le 2026-11-21 entre 17:22:45 UTC, date -u précédente, et 17:23:20 UTC, début de la mesure 0)

Entrées :
- l'image et le deb que scannent aujourd'hui les deux CronJob, copiés depuis Zot en lecture anonyme :
  - `builds/sample-app@sha256:3a7ca1b1…` ;
  - `builds/sample-app-deb@sha256:60f25f5c…` ;
- le SBOM de la source archivé de G0 ;
- la base de G0 (v6.1.10, 04/11) ;
- Grype hors réseau.

Comparaison, pour l'image et pour le deb : le SBOM fusionné tel que l'écrit la fusion actuelle, puis le même avec `metadata.component` de type `container` (nom de l'artefact, digest, `pkg:oci/…`). Grype tourne sans `--vex` ; on compare la sortie de `scan-outil predicat`, hors `scannedAt`.

| Cas | Prédiction | Confiance |
|---|---|---|
| image, prédicats avant et après | identiques | moyenne |
| deb, prédicats avant et après | identiques | moyenne |
| image, couples (id, PURL) de `matches` avant et après | identiques | moyenne |
| deb, couples (id, PURL) de `matches` avant et après | identiques | moyenne |
| deb, au moins une correspondance avec la base de G0 | oui | moyenne |

Si l'un des deux bouge, le choix 1 revient au propriétaire avant toute écriture de la tranche 3.

## Banc de la tranche 3 (écrite le 2026-11-21, date -u de 17:29:54 UTC juste après l’écriture ; après la mesure 0 tenue, avant le premier passage du banc, à 17:33:04 UTC)

Pièces jugées : le patch de la tranche 3 appliqué à une copie (scan-outil, scanner.sh, scan.rego, scan_test.rego, policy-scan.yaml, plateforme.sh). Les VEX sont des **témoins** (auteur « témoin ») : aucune analyse ne les fonde.

**A. Hôte, hors réseau**

| Cas | Prédiction | Confiance |
|---|---|---|
| fusion, image sans `@sha256:` | refus (code 1) | haute |
| compatibilité : prédicat neuf sans VEX = prédicat d'avant + `vex: {documents: [], rejetes: 0}`, image et deb de la mesure 0 | égal (`jq -S`) | haute |
| `ec opa check`, `ec opa test` des règles neuves | aucune erreur, tous PASS | haute |
| mutations de `g5_regles` (liste du patch) | chaque condition fait échouer au moins un test | moyenne |
| `scan-outil vex` : document valide (un énoncé) | retenu | haute |
| statut `fixed` ; statut `affected` | rejetés | haute |
| sans `impact_statement` ; `impact_statement` blanc | rejetés | haute |
| sans justification ; justification hors spécification | rejetés | haute |
| document mixte (un énoncé valide, un sans `impact_statement`) | rejeté entier | haute |
| sujet différent du digest ; `predicateType` autre ; `@context` autre | rejetés | haute |
| énoncé sans horodatage | retenu, horodatage du document | haute |
| deux énoncés horodatés différemment | retenu, le plus ancien | haute |
| horodatage illisible ; aucun énoncé | rejetés | haute |
| aucun fichier | 0 retenu, 0 rejeté | haute |
| `predicat` : correspondance écartée par un VEX sans document retenu | refus (code 1) | haute |

**B. Zot et clés jetables, espace de noms réseau vide ; `scanner.sh` du patch (modes `analyser` et `vex`)**

Image `sample-app@sha256:3a7ca1b1…` (Y) et deb `sample-app-deb@sha256:60f25f5c…`, copiés dans le Zot jetable ; X = Y relabellisé (autre digest). Chaque cas a son propre dépôt, pour qu'un VEX d'un cas ne se mêle pas à un autre. « m/i » : correspondances / écartées.

| Cas | Journal `VEX|` (vérifiés, retenus, rejetés) | Grype | Confiance |
|---|---|---|---|
| analyser complet, image, VEX valide sur `GHSA-mqqf-5wvp-8fh8` | 1, 1, 0 | 4/1 ; l'entrée porte `vex` (not_affected, horodatage du document) ; `vex.documents` = empreinte de l'énoncé décodé | moyenne |
| autre sujet, simple : VEX signé pour X, referrer de X | 0, 0, 0 | 5/0 | haute |
| autre sujet, adverse : VEX signé pour X, referrer de Y | 0, 0, 0 (refus de cosign) | 5/0 | moyenne |
| VEX signé par une autre clé (rôle de la clé du scanner) | 0, 0, 0 | 5/0 | haute |
| VEX `fixed` | 1, 0, 1 | 5/0 | haute |
| VEX sans `impact_statement` | 1, 0, 1 | 5/0 | haute |
| deux VEX valides, horodatés le 01/11 et le 20/11 | 2, 2, 0 | 4/1 ; horodatage de l'entrée = 01/11 | moyenne |
| clé VEX absente du conteneur, VEX valide publié | 0, 0, 0 ; cosign en erreur | 5/0 | haute |
| analyser complet, deb, VEX valide sur `GO-2025-3849` (`pkg:golang/stdlib@1.24.4`) | 1, 1, 0 | 65/1 | moyenne |
| VEX daté du futur (2027-01-01) | 1, 1, 0 | 4/1 | haute |

**C. Porte** (`ec validate input` de l'hôte, règles du patch, validité de banc de 30 jours, l'entrée écartée passée en KEV par `jq`)

| Cas | Prédiction | Confiance |
|---|---|---|
| prédicat de l'analyser complet de l'image | admis | moyenne |
| prédicat du VEX daté du futur | refus `scan.kev_without_vex` | haute |
| prédicat sans VEX (cas « autre sujet » adverse) | refus `scan.kev_without_vex` | haute |
| politique du patch telle quelle (`vex_age_max_jours: null`), prédicat de l'image | refus `scan.kev_without_vex` | moyenne |

## Ajout avant le troisième passage (écrit le 2026-11-21, date -u de 17:34:36 UTC dans la même commande que l’écriture)

Partie D, neuve : `entrees-scan.py` du patch, fonctions `comptes` et `entrees` appelées sur les prédicats des deux analyser complets de B. Grille de 7 gravités pour `scan_entrees` et pour `scan_entrees_vex`, plus 4 séries par dépôt : 18 séries.

| Cas | Prédiction | Confiance |
|---|---|---|
| image (analyser complet) | 18 séries, trouvées 5, écartées 1, KEV écartées 0, 5 lignes dont 1 avec `vex` | haute |
| deb (analyser complet) | 18 séries, trouvées 66, écartées 1, KEV écartées 0, 66 lignes dont 1 avec `vex` | haute |

## Ajout avant le quatrième passage (écrit le 2026-11-21, date -u de 17:39:48 UTC dans la même commande que l’écriture)

Passage 3 : un écart, `deux` sans prédicat. Cause mesurée par une sonde hors dépôt et hors réseau, sur le SBOM et les deux documents du cas : Grype 0.104.1 sort en code 1, sans message sous `-q`, avec `--vex a,b` ; il donne 4/1 avec `--vex a --vex b`, et 4/1 avec le second document seul. Le patch passe désormais un `--vex` par document, et le banc reprend les mêmes commandes. Le motif de rejet n'est plus entre guillemets droits, qui coupaient la ligne `REJET|` du journal.

Prédictions inchangées pour tous les cas ; en particulier `deux` : 2, 2, 0 ; 4/1 ; horodatage de l'entrée 2026-11-01. Ligne `REJET|` du cas `fixed` entière.

## Ajout avant le cinquième passage (écrit le 2026-11-21, date -u de 17:47:48 UTC dans la même commande que l’écriture)

Après relecture du conseiller : un document que le filtre du scanner retient mais que Grype refuserait ferait échouer le scan entier (`set -e`), chaque jour, sans prédicat. Le filtre ne regarde ni `vulnerability` ni `products`. Trois cas neufs en B, en mode `vex` ; les autres prédictions sont inchangées.

| Cas | Journal `VEX|` | Grype | Confiance |
|---|---|---|---|
| énoncé valide sans `products` | 1, 1, 0 | 5/0 (énoncé sans effet) ; refus de Grype possible | faible |
| énoncé valide sans `vulnerability` | 1, 1, 0 | 5/0 (énoncé sans effet) ; refus de Grype possible | faible |
| `--vex a,b` sur les deux documents du cas `deux` (sonde du passage 3, archivée) | sans objet | code 1 ; `--vex a --vex b` : 4/1 | haute |

## Ajout avant le sixième passage (écrit le 2026-11-21, date -u de 20:19:46 UTC dans la même commande que l’écriture)

Deux changements du banc, après le choix de `vex_age_max_jours` à 30 jours (patch `e063abd2aedf18af…`).

**1. Politiques de la partie C.** Le patch porte désormais 30. La politique « 30 » est celle du patch telle quelle. La politique « null » est fabriquée par le sed inverse, comme contre-épreuve. Chacune est contrôlée par `grep`. Sans ce changement, le cas « politique à null » aurait jugé 30 sans le dire.

| Cas | Prédiction | Confiance |
|---|---|---|
| politique du patch | contient `vex_age_max_jours: 30` | haute |
| politique fabriquée | contient `vex_age_max_jours: null` | haute |
| porte, image complet, politique à null | code 1, `scan.kev_without_vex` (inchangé) | haute |

**2. Renouvellement d'un VEX par retrait de l'ancien référent (cas neuf en B, puis C).**
- Une image est publiée sous `builds/renouv`.
- Deux documents sont publiés sur son digest, dans `builds/vex/renouv` : un ancien, daté 2026-10-01T00:00:00Z (plus de 30 jours), et un récent, daté de la veille.
- Le retrait se fait par `oras manifest delete --force` sur le digest du manifeste référent, dans le Zot jetable : `gc: false`, sans contrôle d'accès.

| Cas | Journal `VEX|` | Grype | Horodatage de l'entrée | Porte à 30 jours | Confiance |
|---|---|---|---|---|---|
| avant tout retrait | 2, 2, 0 | 4/1 | 2026-10-01T00:00:00Z | code 1, `scan.kev_without_vex` | haute |
| retrait de l'ancien | code 0 ; référents 2 puis 1 | — | — | — | moyenne |
| après le retrait | 1, 1, 0 | 4/1 | la veille (`H1`) | code 0, admis | moyenne |
| retrait du dernier (contre-épreuve) | code 0 ; référents 0 ; puis 0, 0, 0 | 5/0 | aucune | code 1, `scan.kev_without_vex` | moyenne |

**Ce que le banc ne mesure pas** :
- le vrai Zot (droits de suppression sur `builds/vex/**`, ramasse-miettes, rétention) ;
- la signature par `hashivault://vex` ;
- le délai du scan quotidien.

Toutes les autres prédictions sont inchangées.

## Ajout avant le septième passage : remplacement (écrit le 2026-11-21, date -u de 20:44:39 UTC dans la même commande que l’écriture, avant toute ligne de code)

Choix du propriétaire du 21/11 (« Remplacement »). **Conception**, après relecture du conseiller :
- **`scan-outil vex`** :
  - Le filtre des documents ne change pas. Choix 5 : un document est rejeté entier dès qu'un énoncé n'est pas recevable. Les documents recevables sont écrits tels que signés et passés à Grype, comme avant.
  - Nouveau : la sortie liste aussi les **énoncés** de tous les documents lisibles, recevables ou non. Chaque énoncé porte :
    - ses noms : `vulnerability.name` et `aliases` ;
    - son horodatage : celui de l'énoncé, à défaut celui du document ;
    - son statut ;
    - un booléen `exemptant`.
  - `exemptant` est vrai seulement si le document est recevable et si un produit de l'énoncé cite le digest scanné.
  - Un énoncé sans vulnérabilité n'est pas listé.
  - Un document illisible (type, sujet, contexte, horodatage) ne compte pas.
- **`scan-outil predicat`** :
  - On part d'une correspondance que Grype a écartée par un VEX. Ses énoncés candidats sont ceux dont un nom croise son identifiant ou ses alias, quel que soit le produit.
  - Le plus récent l'emporte. L'entrée ne reçoit `vex` (statut de Grype, horodatage du gagnant) que si tous les énoncés à cet horodatage sont `exemptant`.
  - Sinon, l'entrée reste ordinaire et est comptée dans `vex.ecarteesSansExemption`.
  - Le résultat ne dépend pas de l'ordre des fichiers : on prend un maximum, et une égalité se tranche vers l'échec fermé.
- **Fermé dans les deux sens** :
  - Une rétractation sous un autre nom (alias) ou pour un autre produit fait tomber l'exemption.
  - Un `not_affected` récent pour un autre produit n'exempte pas.
- **Limite** : avec un registre en ajout seul, un document daté dans le futur gagne tous les classements jusqu'à sa date. La porte le refuse alors (horodatage postérieur au scan) : c'est un blocage fermé. La réparation est le retrait du passage 6, sur accord.

**Prédictions** (inchangées si non citées) :

| Partie | Cas | Prédiction | Confiance |
|---|---|---|---|
| A | les 15 cas unitaires de `vex`, sans fichier, document écrit = prédicat | inchangés | haute |
| A, predicat | remplacement (not_affected 01/11 puis 20/11) | vex `not_affected` 2026-11-20T00:00:00Z | haute |
| A, predicat | ordre inversé des fichiers | identique : 2026-11-20T00:00:00Z | haute |
| A, predicat | rétractation (not_affected 01/11, affected 20/11) | aucune exemption, 1 sans exemption | haute |
| A, predicat | rétractation sous l'alias `CVE-2025-69725` | aucune exemption, 1 sans exemption | moyenne |
| A, predicat | égalité (not_affected et affected le 20/11) | aucune exemption, 1 sans exemption | haute |
| A, predicat | réaffirmation (affected 01/11, not_affected 20/11) | vex `not_affected` 2026-11-20T00:00:00Z | haute |
| A, predicat | not_affected 20/11 pour un autre produit | aucune exemption, 1 sans exemption | haute |
| A, predicat | document récent sur une autre vulnérabilité (`GHSA-j6qf-3m9c-vwj3`) | vex 2026-11-01T00:00:00Z (non concerné) | haute |
| B | `deux` | 2, 2, 0 ; 4/1 ; horodatage de l'entrée **2026-11-20T00:00:00Z** (au lieu du 01/11) | haute |
| B | `renouv-avant` | 2, 2, 0 ; 4/1 ; horodatage de l'entrée **la veille** (au lieu du 01/10) | haute |
| B | `inverse` (récent publié avant l'ancien) | 2, 2, 0 ; 4/1 ; la veille | haute |
| B | `retract-avant` (not_affected d'il y a deux jours, seul) | 1, 1, 0 ; 4/1 ; il y a deux jours | haute |
| B | `retract-apres` (+ affected de la veille, sous l'alias `CVE-2025-69725`) | 2, 1, 1 ; **5/0** (Grype écarte, le prédicat n'exempte pas) | moyenne |
| B | `partiel` (ancien du 01/10 sur V1 et V2, récent de la veille sur V1) | 2, 2, 0 ; 3/2 ; V1 la veille, V2 2026-10-01 | moyenne |
| C | porte, `renouv-avant` | **code 0, admis** (au lieu du refus) | haute |
| C | porte, `inverse` | code 0, admis | haute |
| C | porte, `retract-avant` / `retract-apres` | code 0 / code 1, `scan.kev_without_vex` | haute / moyenne |
| C | porte, `partiel`, V1 en KEV / V2 en KEV | code 0 / code 1, `scan.kev_without_vex` | moyenne |
| A | `ec opa test` sur les règles du patch | toujours vert (commentaires seulement dans `scan.rego`) | haute |

## Ajout avant le huitième passage (écrit le 2026-11-21, date -u de 20:51:55 UTC dans la même commande que l’écriture)

Passage 7 : 105 OK, 2 KO. Les deux écarts sont les contrôles de compatibilité de la partie A (image et deb), que je n'avais pas prévus. Le prédicat neuf sans VEX porte désormais `ecarteesSansExemption: 0` dans le bloc `vex`. Comparé au prédicat d'avant, complété par `documents: []` et `rejetes: 0`, c'est la seule différence : relevée par `diff` sur les deux fichiers du banc, avant toute modification. Tous les cas du remplacement sont conformes.

Changement du banc : le bloc attendu devient `documents: []`, `rejetes: 0`, `ecarteesSansExemption: 0`. Prédiction : compatibilité image et deb OK ; toutes les autres prédictions inchangées (dont tous les cas du septième passage).

## Ajout avant le neuvième passage : couverture du paquet (écrit le 2026-11-21, date -u de 20:59:25 UTC dans la même commande que l’écriture, avant toute ligne de code)

**Trou trouvé par le conseiller et confirmé par une sonde hors banc**, sur le binaire du passage 8 :
- L'ancien document `pa` vise `go-chi` (01/11). Un récent, du 20/11, vise la même vulnérabilité sur le même produit, mais un autre sous-composant (`pkg:golang/stdlib@1.24.4`).
- Résultat : l'entrée `go-chi` reçoit l'horodatage du 20/11, avec 0 entrée sans exemption. L'exemption est renouvelée par un énoncé qui ne la couvre pas.
- La note de 20:56:05Z (« fermé dans les deux sens ») est donc fausse sur ce point. Aucun cas du banc ne portait un autre sous-composant.

**Correction prévue (échec fermé)** :
- Le classement reste par noms.
- L'exemption exige en plus que chaque énoncé gagnant couvre l'entrée :
  - soit un produit qui cite le digest n'a aucun sous-composant (énoncé large) ;
  - soit le PURL de l'entrée figure parmi les sous-composants des produits qui citent le digest (égalité exacte).
- `vulnerability.@id` est ajouté aux noms.
- **Conséquence, écrite comme limite** : un énoncé récent sur P2 fait tomber l'exemption de P1 tant que P1 n'est pas re-signé.

| Partie | Cas | Prédiction | Confiance |
|---|---|---|---|
| A, `predicat` | `pa` puis un récent sur un autre sous-composant | aucune exemption, 1 sans exemption | haute |
| A, `predicat` | `pa` puis un récent sans sous-composant (large) | exempt, 2026-11-20T00:00:00Z | haute |
| A, `predicat` | les 8 cas du septième passage | inchangés | haute |
| B | `deb-complet` | 1, 1, 0 ; **65/1** : l'égalité exacte entre le PURL de l'énoncé (`pkg:golang/stdlib@1.24.4`) et celui de Grype doit tenir | moyenne |
| B, C, D | tous les autres cas | inchangés (même sous-composant que Grype) | haute |

## Ajout avant le dixième passage : énoncés par paquet (écrit le 2026-11-21, date -u de 21:06:51 UTC dans la même commande que l’écriture, avant toute ligne de code)

**Défaut de la règle du passage 9**, signalé par le conseiller et confirmé par une sonde hors banc sur le binaire du passage 9 (sonde effacée ensuite).
- Un seul document, du 20/11, porte deux énoncés `not_affected` sur la même vulnérabilité : l'un pour `go-chi`, l'autre pour `stdlib`.
- Résultat : aucune exemption, 1 sans exemption. À égalité, chaque énoncé devait couvrir l'entrée.
- Avec deux documents, chacun ferait tomber l'autre à sa re-signature. La limite écrite à 21:04:20Z (« tant que P1 n'est pas re-signé ») est donc fausse.

**Correction prévue** :
- Un énoncé `exemptant` dont les sous-composants ne contiennent pas le paquet de l'entrée sort du classement de cette entrée.
- Tous les autres énoncés restent : `affected`, non recevable, autre produit, énoncé large. Une rétractation garde donc sa portée large.

| Partie | Cas | Prédiction | Confiance |
|---|---|---|---|
| A, `predicat` | `pa` (01/11, go-chi) puis un récent sur un autre sous-composant | **exempt au 2026-11-01T00:00:00Z** (non renouvelé, au lieu d'aucune exemption) | haute |
| A, `predicat` | un document, deux énoncés de même date (go-chi, stdlib) | exempt au 2026-11-20T00:00:00Z, 0 sans exemption | haute |
| A, `predicat` | `pa` puis un `affected` récent sur l'autre sous-composant | aucune exemption, 1 sans exemption | haute |
| A, `predicat` | `large` et les 8 cas du septième passage | inchangés | haute |
| B, C, D | tous les cas | inchangés | haute |

## Ajout avant le onzième passage : pièce 8, `signer-vex.sh` (écrit le 2026-11-21, date -u de 21:27:36 UTC dans la même commande que l’écriture, après le code et une sonde)

**Ordre réel, dit en clair** : le script et les cas du banc sont écrits **avant** cette prédiction. Une sonde hors banc a déjà passé les 12 témoins de la partie A en mode `verifier` (2026-11-21T21:25:03Z, binaire `scan-outil` du passage 10, sonde effacée ensuite). Les prédictions de la partie A recopient donc une mesure : ce ne sont pas des prédictions indépendantes. Celles de la partie B sont neuves : le mode `signer` n'a jamais tourné.

Patch `992af0d0b7073b57…` : le précédent (`02ac8e835fe74fbe…`) plus un fichier neuf, `signer-vex.sh`. Aucune ligne existante ne change.

| Partie | Cas | Prédiction | Confiance |
|---|---|---|---|
| A, `verifier` | ok, rétractation, énoncé large | code 0 ; exemption, rétractation, exemption avec 1 énoncé large | haute (sonde) |
| A, `verifier` | daté du futur (document ou énoncé), sous-composant absent, `fixed`, mêlé, sans `impact_statement`, autre digest, sans vulnérabilité, sans horodatage | code 1, chacun avec son motif | haute (sonde) |
| A, `verifier` | image sans digest | code 2 | haute (sonde) |
| B, `signer` | daté du futur | code 1, motif horodatage, 0 référent : refus avant signature | haute |
| B, `signer` | clé étrangère, clé publique `vex` | code 1, motif « signature non vérifiée », 0 référent : refus avant publication | haute |
| B, `signer` | clé `vex`, document du jour d'avant | code 0, 1 référent ; `scanner.sh vex` le retient (1,1,0), 4/1, horodatage `H1` ; l'empreinte du prédicat égale celle annoncée par `SIGNE` | moyenne : première publication par le script (oras avec `--registry-config`) |
| B, `signer` | rétractation `affected` datée de l'instant | code 0, 2 référents ; 2,1,1, 5/0, 1 sans exemption | moyenne |
| B, C, D | les 111 contrôles du passage 10 | inchangés | haute |

**Total prédit** : 137 OK (111 + 13 en A + 13 en B), 0 KO.

**Non mesuré par ce passage** : `hashivault://vex` (pièce 2, sur accord), le compte d'écriture de `builds/vex/**` (pièce 4), et la signature du prédicat de scan fourni au script, que le script ne vérifie pas.

## Ajout avant le douzième passage : noms confrontés au scan, `action_statement` (écrit le 2026-11-21, date -u de 21:35:33 UTC dans la même commande que l’écriture, avant toute ligne de code)

**Trou du passage 11**, signalé par le conseiller et confirmé par une sonde hors banc (21:34:42 UTC, binaire et script du passage 11, sonde effacée ensuite) : une rétractation `affected` sur `CVE-2025-69752`, faute de frappe pour `CVE-2025-69725`, sort en code 0. Elle serait signée et publiée sans rien rétracter : l'exemption de la KEV resterait jusqu'à 30 jours. C'est un échec ouvert.

**Correction prévue dans `signer-vex.sh`** (le jugement de `scan-outil vex` ne change pas) :
- chaque énoncé doit avoir un nom (`@id`, `name`, `aliases`) égal à l'`id` ou à un alias d'une entrée du prédicat de scan fourni ;
- chaque sous-composant d'une exemption doit être le paquet d'une entrée qui porte ce nom ;
- `affected` exige un `action_statement` non vide. La spécification v0.2.0 l'écrit en MUST dans la description du champ, mais sa colonne « Required » le marque facultatif. Le script prend la lecture stricte, comme pour `not_affected`. `under_investigation` n'exige rien.

Les témoins de rétractation du banc reçoivent donc un `action_statement` par `jq`, sans changer `07b-t3-vex.py`.

| Partie | Cas | Prédiction | Confiance |
|---|---|---|---|
| A, `verifier` | rétraction sur `CVE-2025-69752` | code 1, motif « aucun nom ne croise une entrée du prédicat de scan » | haute |
| A, `verifier` | rétractation sans `action_statement` | code 1, motif `action_statement` | haute |
| A, `verifier` | prédicat où `GO-2026-5774` est sur `stdlib` : exemption de `GO-2026-5774` pour `go-chi` | code 1, motif « sous-composant sans entrée de cette vulnérabilité » | haute |
| A, `verifier` | même prédicat, exemption de `GO-2026-5774` pour `stdlib` | code 0, exemption | haute |
| A, `verifier` | les 13 cas du passage 11 (la rétractation reçoit un `action_statement`) | inchangés, mêmes motifs | haute |
| B, `signer` | les 13 contrôles du passage 11 (la rétractation reçoit un `action_statement`) | inchangés | haute |
| B, C, D | les autres contrôles | inchangés | haute |

**Total prédit** : 141 OK (137 + 4), 0 KO.

## Ajout avant le treizième passage : séries VEX dans Prometheus (écrit le 2026-11-21, date -u de 22:04:47 UTC dans la même commande que l’écriture, avant toute ligne de code)

**Limite visée** (ADR 0004) : le compteur `ecarteesSansExemption` n'a pas de série dans Grafana, contrairement à l'exigence d'audit du propriétaire.

**Changement prévu**, dans `entrees-scan.py` du patch (pièce 7) : trois séries par dépôt, lues dans le bloc `vex` du prédicat de scan, 0 si le bloc est absent (prédicats d'avant la tranche 3) :
- `scan_vex_documents` : nombre de documents VEX passés au scanner ;
- `scan_vex_rejetes` : documents vérifiés mais rejetés par le filtre ;
- `scan_vex_ecartees_sans_exemption` : entrées dont le gagnant n'exempte pas.

`verif` d'`entrees-scan.sh` (patch) suit : 42 séries au lieu de 36, et les trois valeurs comparées à `jq` sur l'énoncé relu.

| Partie | Cas | Prédiction | Confiance |
|---|---|---|---|
| D | `complet` | 21 séries, trouvées 5, écartées 1, kev écartées 0, lignes 5, lignes avec vex 1, vex 1/0/0 | haute |
| D | `deb-complet` | 21 séries, trouvées 66, écartées 1, kev écartées 0, lignes 66, lignes avec vex 1, vex 1/0/0 | haute |
| D | `signe-retract` (neuf) | 21 séries, trouvées 5, écartées 0, kev écartées 0, lignes 5, lignes avec vex 0, vex 1/1/1 | haute |
| D | prédicat d'avant la tranche 3 (`image-avant` de la mesure 0, neuf) | 21 séries, vex 0/0/0 | haute |
| A, B, C | les autres contrôles | inchangés | haute |

**Total prédit** : 143 OK (141 + 2), 0 KO.

**Non mesuré par ce passage** : `verif` (Prometheus et Grafana réels), qui demande la pose de la pièce 7.

## Ajout avant le quatorzième passage : `signer-vex.sh` lit et vérifie le scan signé (écrit le 2026-11-21, date -u de 22:11:04 UTC dans la même commande que l’écriture, avant toute ligne de code ; limite 1 de l'inventaire)

**Changement prévu** : `signer-vex.sh` ne prend plus de fichier `scan.json`. Il lit les scans attestés sur le digest dans `builds/scan/<nom>` (`cosign verify-attestation`, clé publique du scanner `CLE_SCANNER`, comme `lire_vex` de `scanner.sh`), garde le plus récent par `scannedAt`, et refuse s'il n'y en a aucun. Usage : `signer-vex.sh verifier|signer <document> <hôte/dépôt@sha256:…>`. `verifier` lit donc le registre.

**Banc** : les cas `verifier` passent de la partie A (hors registre) à la partie B (Zot jetable). Une clé locale `scanner` signe des scans témoins, publiés en referrers :
- `builds/signe/sample-app` : un ancien scan (le prédicat où `GO-2026-5774` est sur `stdlib`, `scannedAt` du 01/11), puis un récent (`image-avant` de la mesure 0, tout sur `go-chi`) ;
- `builds/deux/sample-app` : le prédicat `stdlib` seul ;
- `builds/etranger/sample-app` : un scan signé par la clé étrangère seulement.

| Partie | Cas | Prédiction | Confiance |
|---|---|---|---|
| B, `verifier` | les 12 témoins et l'image sans digest du passage 11, sur `builds/signe` | inchangés, mêmes codes et motifs | haute |
| B, `verifier` | les 4 cas du passage 12 ; les deux cas « couple » sur `builds/deux` | inchangés | haute |
| B, `verifier` | exemption de `GO-2026-5774` pour `stdlib` sur `builds/signe` (le plus récent la place sur `go-chi`) | code 1, « sous-composant absent » : c'est le scan le plus récent qui est lu | moyenne : tri par `scannedAt` à décalage horaire |
| B, `verifier` | document correct sur `builds/etranger` | code 1, « aucun scan signé vérifié » | haute |
| B | scans publiés (référents) : `signe` 2, `deux` 1, `etranger` 1 | `2,1,1` | haute |
| B, `signer` | les 13 contrôles des passages 11 et 12 | inchangés | haute |
| A, C, D | les autres contrôles | inchangés | haute |

**Total prédit** : 146 OK (143 + 3), 0 KO.

## Ajout avant le quinzième passage : documents VEX comptés, dans Loki (écrit le 2026-11-22, date -u de 17:46:52 UTC dans la même commande que l’écriture, avant toute ligne de code ; limite 2 de l'inventaire)

**Changement prévu** :
- `entrees-scan.py` émettra une ligne JSON par document du bloc `vex.documents` du prédicat : `depot`, `scannedAt`, `scanne`, `vexDocument` (empreinte) et `vexTimestamp` (horodatage), sans `id`.
- Ces lignes seront émises avec les lignes d'entrée, sous la même marque d'état, donc une fois par referrer de scan. Le résumé ne change pas.
- `verif` d'`entrees-scan.sh` (patch) exclura ces lignes du compte des entrées (`| vexDocument=""`). Il comptera les documents à part (`| vexDocument!=""`) et les comparera à `jq '.predicate.vex.documents | length'`, une réponse vide valant 0.
- Sonde du filtre, lecture seule par l'auditeur ([journal](07b-t3-sonde-loki-filtre.log)) : sur le vrai Loki, `vexDocument=""` garde 6 et 67 lignes, et `vexDocument!=""` ne rend aucune série, pas « 0 ».

**Banc** : la partie D gagne, par cas :
- les lignes de document et leurs empreintes, comparées au bloc `vex` ;
- trois passages de `main()` sur un faux Zot (fonction `lire` remplacée, comme au banc de la tranche 1 : la lecture est synthétique, `main()` est réel) : referrer A, encore A, puis un referrer neuf B.

| Cas D | Prédiction | Confiance |
|---|---|---|
| `complet` | 21 séries et comptes inchangés ; 1 document = prédicat ; `main` : 7 lignes (5 entrées, 1 document, résumé « liste émise »), puis 1 (résumé seul), puis 7 | haute |
| `deb-complet` | inchangé ; 1 document ; `main` : 68, 1, 68 | haute |
| `signe-retract` | inchangé (`vex` 1/1/1) ; 1 document ; `main` : 7, 1, 7 | haute |
| `avant-t3` | inchangé ; 0 document, aucune ligne de document ; `main` : 6, 1, 6 | haute |
| A, B, C | inchangés | haute |

**Total prédit** : 146 OK, 0 KO. Le nombre de contrôles ne change pas, car les quatre lignes D s'allongent.

**Non mesuré par ce passage** : le `verif` du patch sur le vrai Loki (`bash -n` seulement) ; il attend la pose. À la pose, la marque du referrer courant existe déjà : les lignes de document n'apparaîtront qu'au scan suivant.

## Ajout avant le seizième passage : avis de renouvellement dans `signer-vex.sh` (écrit le 2026-11-22, date -u de 18:31:58 UTC dans la même commande que l’écriture, avant toute ligne de code ; limite 3 de l'inventaire)

**Changement prévu** (approche relue par le conseiller) :
- `signer-vex.sh` exige `CLE_PUBLIQUE` (clé publique VEX) dans les deux modes, plus seulement en `signer`.
- Après le premier jugement, et avant toute signature, il lit les VEX déjà publiés sur le digest dans `builds/vex/<nom>`, comme `lire_vex` de `scanner.sh` : `cosign verify-attestation` avec `CLE_PUBLIQUE`, puis `scan-outil vex` sur les énoncés vérifiés. Ce second appel ne porte que sur les publiés.
- Il écrit toujours une ligne `PUBLIES|` : le nombre d'énoncés publiés vérifiés, le code de cosign et sa première erreur. « Pas d'avis » ne veut donc jamais dire « non comparé ».
- **Même entrée** : les noms d'un énoncé neuf sont étendus par les entrées du scan déjà lu (id et alias). Un énoncé publié concurrent est un énoncé dont un nom croise ces noms étendus. La comparaison porte sur tous les `enonces` publiés, recevables ou non, comme le classement de `gagnant`.
- **Comparaison** : en entiers à la nanoseconde (`date -u -d … +%s%N`), jamais en chaînes.
- **Avis** (lignes `AVIS|`, sortie standard, code inchangé) :
  - `renouvellement` : une exemption dont l'horodatage est inférieur ou égal à celui d'un énoncé publié concurrent ;
  - `rétractation` : une rétractation dans le même cas, qui peut ne rien rétracter ;
  - `âge` : une exemption dont l'échéance (horodatage + `VEX_AGE_MAX_JOURS`, défaut 30) est passée ou à moins d'un jour, le délai du scan quotidien. Il ne s'applique pas aux rétractations.
- Une ligne `ECHEANCE|` donne l'échéance de chaque énoncé d'exemption.
- La couverture par paquet n'est pas reproduite : l'avis peut avertir à tort, et il le dit (« peut »).
- Le calcul se fait hors de `juger`, une seule fois, y compris en mode `signer`.

**Banc** :
- `sv_verifier` et `signer_vex` reçoivent `CLE_PUBLIQUE`. Les 18 cas `verifier` des passages 11, 12 et 14 sont inchangés.
- Nouveau dépôt `builds/avis` : un scan signé par la clé `scanner` (prédicat d'avant la tranche 3) et trois VEX publiés :
  - P1 : exemption de `GHSA-mqqf-5wvp-8fh8`, clé `vex`, datée d'il y a 10 jours, à `.500000000` s ;
  - P2 : la même, clé étrangère, datée d'il y a 1 h ;
  - P3 : exemption non recevable (sans `impact_statement`) de `GHSA-j6qf-3m9c-vwj3`, clé `vex`, datée d'il y a 5 jours.

| Contrôle | Prédiction | Confiance |
|---|---|---|
| seuil par défaut du script = `vex_age_max_jours` de la politique (`yq`) | 30 | haute |
| énoncés publiés lus par les cas `verifier` acceptés (ok, retract, large, couple-ok sur `deux`) | 0,0,0,2 (les deux VEX publiés sous `builds/vex/deux` au cas 7) | haute |
| `builds/avis` : scans et référents VEX | 1,3 | haute |
| `recent` : exemption de `GHSA-mqqf` d'il y a 1 jour | code 0 ; publiés 2 ; avis aucun (P2 ignoré : clé étrangère) | moyenne (cosign rend-il les attestations valides quand l'une échoue ? non mesuré) |
| `egal` : même horodatage que P1, à la nanoseconde | code 0 ; publiés 2 ; avis renouvellement | haute |
| `ancien` : même seconde que P1, sans fraction (0,5 s plus ancien) | code 0 ; publiés 2 ; avis renouvellement | haute |
| `fraction` : même seconde que P1, à `.700000000` | code 0 ; publiés 2 ; avis aucun (une comparaison à la seconde avertirait) | haute |
| `alias` : exemption nommée `CVE-2025-69725` (alias), il y a 11 jours | code 0 ; publiés 2 ; avis renouvellement | haute |
| `retract-ancienne` : `affected` sur `GHSA-mqqf`, il y a 11 jours | code 0 ; publiés 2 ; avis rétractation | haute |
| `retract-recente` : `affected` sur `GHSA-mqqf`, il y a 1 jour | code 0 ; publiés 2 ; avis aucun | haute |
| `non-recevable` : exemption de `GHSA-j6qf`, il y a 6 jours (P3, non recevable, est plus récent) | code 0 ; publiés 2 ; avis renouvellement | haute |
| `vieux-31` : exemption de `GO-2026-5775`, il y a 31 jours | code 0 ; publiés 2 ; avis âge | haute |
| `vieux-29` : exemption de `GO-2026-5777`, il y a 708 h (29,5 jours) | code 0 ; publiés 2 ; avis âge | haute |
| `vieux-28` : exemption de `GO-2026-5774`, il y a 28 jours | code 0 ; publiés 2 ; avis aucun | haute |
| `signer` du passage 11, document publié en premier (`signer-ok.log`) | publiés 0 ; avis aucun | haute |
| `signer` de la rétractation, plus récente que l'exemption publiée (`signer-retract.log`) | publiés 1 ; avis aucun | haute |

**Total prédit** : 162 OK, 0 KO (146, plus 16 contrôles).

**Non mesuré par ce passage** : `hashivault://vex` et le vrai Zot. L'avis reste un avis : une rétractation plus ancienne qu'une exemption publiée est signée et publiée, sans rien rétracter. La passer en refus serait un choix du propriétaire.

## Ajout avant le dix-septième passage : rétractation ancienne en mode `signer` (écrit le 2026-11-22, date -u de 18:40:43 UTC dans la même commande que l’écriture ; demandé par le conseiller après le passage 16)

**Pourquoi** : la note de 18:38:35Z dit qu'une rétractation plus ancienne qu'une exemption publiée « est signée et publiée ». Au passage 16, les avis n'ont été vus qu'en mode `verifier`. Ce passage le mesure en mode `signer`. `signer-vex.sh` ne change pas : le patch reste `dbad512077db97a6…`.

**Banc** : après les 11 cas `verifier` de `builds/avis`, pour ne pas changer leur « publiés 2 » :
- `signer` du document `retract-ancienne` sur `builds/avis`, clé `vex` ;
- puis le mode `vex` de `scanner.sh` et les commandes d'`analyser` sur ce dépôt (cas `avis-apres`).

| Contrôle | Prédiction | Confiance |
|---|---|---|
| `signer` de la rétractation ancienne | code 0 ; référents 4 ; publiés 2 ; avis rétractation | haute |
| lignes `PUBLIE|` du journal de `signer` | 1 | haute |
| `avis-apres` : VEX vérifiés, retenus, rejetés | 3,1,2 (P1, P3 et la rétractation ; P2 ignoré ; seul P1 recevable) | haute |
| `avis-apres` : entrées sans VEX / avec VEX | 4/1 : l'exemption de P1 tient, la rétractation plus ancienne ne rétracte rien | haute |
| `avis-apres` : entrée écartée | `GHSA-mqqf-5wvp-8fh8`, horodatage de P1 à `.5` s | haute |

**Total prédit** : 167 OK, 0 KO (162, plus 5 contrôles).

## Ajout avant le dix-huitième passage : repli sans `--vex` (limite 4) (écrit le 2026-11-22, date -u de 19:07:17 UTC dans la même commande que l’écriture, avant le code ; approche relue par le conseiller)

**Changement prévu** :
- `scanner.sh`, mode `analyser` : si Grype échoue alors qu'au moins un VEX est retenu, une ligne `REPLI|grype code <c> avec <N> VEX[ : <erreur>] ; …` est écrite, puis Grype est relancé sans `--vex`. Si la relance échoue, le scan échoue comme avant. Sans VEX retenu, un échec de Grype reste un échec.
- `scan-outil predicat … repli` (cinquième argument facultatif) : `vex.documents` est vide, et `vex.repli` vaut le nombre de documents retenus non appliqués, lu dans `vex-retenus.json`. Hors repli, le champ est absent, et les prédicats ordinaires ne changent pas. En repli, une correspondance écartée par un VEX est une erreur, comme un repli sans document retenu.
- `entrees-scan.py` : nouvelle série `scan_vex_repli` (0 si le champ est absent). `entrees-scan.sh` : verif l'ajoute à sa comparaison avec jq (44 séries pour deux dépôts au lieu de 42). La pose attendait encore 20 séries écrites, compte d'avant la tranche 3 (42 depuis le patch) : corrigé à 44, en passant.
- `scan_test.rego` : deux tests, repli admis sans KEV, repli avec KEV refusé par `scan.kev_without_vex`. Aucune règle ne change.

**Banc** : la panne est **injectée, donc synthétique**. Un faux `grype`, placé devant le vrai dans le PATH du cas, note chaque appel (sous-commande, nombre de `--vex`) puis appelle le vrai par son chemin absolu. Il échoue sur `sbom:` avec au moins un `--vex` (cas `repli`), ou sur tout `sbom:` (cas `panne-totale`). L'import de la base passe toujours. Les deux cas utilisent le vrai mode `analyser`, sur un dépôt neuf `builds/repli` avec un VEX recevable.

| Contrôle | Prédiction | Confiance |
|---|---|---|
| A : `predicat … repli` sur le scan témoin, avec 1 document retenu | prédicat d'avant + `vex` = documents vide, rejetés 0, sans exemption 0, `repli` 1 | haute |
| A : `predicat … repli` sans document retenu | code 1 | haute |
| A : `predicat … repli` avec une entrée écartée par un VEX | code 1 | haute |
| A : `predicat` à 5 arguments dont le dernier n'est pas `repli` | code 2 (usage) | haute |
| A : `ec opa test` | `PASS: 41/41` | haute |
| B, `complet` : `repli` absent du prédicat | false | haute |
| B, `repli` : appels du faux | `db 0,sbom 1,sbom 0` | haute |
| B, `repli` : ligne `REPLI|` | 1 ligne, `grype code 1 avec 1 VEX` | haute |
| B, `repli` : VEX vérifiés, retenus, rejetés | 1,1,0 | haute |
| B, `repli` : entrées sans VEX / avec VEX | 5/0 | haute |
| B, `repli` : bloc `vex` du prédicat | `{"documents":[],"ecarteesSansExemption":0,"rejetes":0,"repli":1}` | haute |
| B, `repli` : entrées = celles de `complet` sans le champ `vex` | égales | moyenne (entrée écartée contre entrée trouvée) |
| B, `panne-totale` : appels du faux | `db 0,sbom 1,sbom 0` | haute |
| B, `panne-totale` : lignes `REPLI|`, code final, prédicat | 1 ; `code 1` ; absent | haute |
| C : porte sur le repli, `GHSA-mqqf-5wvp-8fh8` en KEV | code 1, `scan.kev_without_vex` (la direction est stricte) | haute |
| C : porte sur le repli, aucune KEV | code 0, admis (le champ passe la porte) | haute |
| D : les quatre cas existants | 22 séries au lieu de 21, `scan_vex_repli` à 0 | haute |
| D : `repli` | 22 séries, trouvées 5, écartées 0, vex 0/0/0/1, documents 0, main 6/1/6 | haute |
| D : séries attendues par `entrees-scan.sh` à la pose et au verif | 44 et 44 (2 × 22) | haute |

**Durée** : deux `analyser` de plus, donc deux imports de base, non prédite.

**Total prédit** : 186 OK, 0 KO (167, plus 4 en A, 11 en B, 2 en C, 2 en D).

## Ajout avant le dix-neuvième passage : échec de Grype sans VEX retenu (écrit le 2026-11-22, date -u de 19:18:18 UTC dans la même commande que l’écriture ; demandé par le conseiller après le passage 18)

**Pourquoi** : la note de 19:16:04Z dit « Sans VEX retenu, un échec reste un échec ». Aucun cas du passage 18 ne le mesure, et ce chemin a changé (stderr capturé, puis `exit "$c"`). C'est celui de tous les scans sans VEX. Le patch ne change pas : `9fcb4b40dc31c95d…`.

**Banc** : un cas `sans-vex-panne`, avec le même `grype` factice, `PANNE=tout` (panne injectée, synthétique), sur un dépôt neuf `builds/sans-vex` sans VEX publié, en mode `analyser` réel.

| Contrôle | Prédiction | Confiance |
|---|---|---|
| appels du faux | `db 0,sbom 0` (aucune relance) | haute |
| VEX vérifiés, retenus, rejetés | 0,0,0 | haute |
| lignes `REPLI|` | 0 | haute |
| message du faux dans le journal du cas | 1 ligne (le stderr de Grype reste visible) | haute |
| code final | `code 1` | haute |
| prédicat | absent | haute |

**Total prédit** : 192 OK, 0 KO (186, plus 6 contrôles).

## Ajout avant le vingtième passage : exemptant daté du futur, forme asymétrique, cas unitaire (écrit le 2026-11-22, date -u de 19:38:25 UTC dans la même commande que l’écriture ; approche relue par le conseiller)

**Pourquoi** : l'inventaire (classe 2) dit qu'une seule forme tient si l'on sort le document daté du futur du classement : l'énoncé **exemptant** daté du futur sort, l'énoncé **non exemptant** reste. C'est à mesurer par un cas unitaire avant la question au propriétaire.

**Ce n'est pas le patch** : la variante amende le choix 3, donc `07b-t3.patch` reste à `9fcb4b40dc31c95d…`. Elle vit dans un petit diff à part, `resultats/07b-t3-variante-futur.patch`, appliqué par le banc sur la copie de `outil/` du patch. Le banc en tire un second binaire. Les deux binaires passent la même table.

**Variante** (seul `predicat` change) :
- L'heure de référence est celle du scan, `descriptor.timestamp` de Grype (celle que la porte lit dans `scannedAt`), plus 5 min, l'écart d'horloge de la porte (`_derive`). Ce n'est pas l'horloge de la machine.
- Dans le classement d'une entrée, un énoncé exemptant postérieur à cette limite sort. Un énoncé non exemptant reste, quelle que soit sa date.
- S'il y a des énoncés et que l'heure du scan est illisible, c'est une erreur (échec fermé).

**Heure du scan témoin** (`ecarte-sans-doc.json`, tiré de `image-avant.grype.json`) : 2026-11-21T18:23:25.018413605+01:00, soit 17:23:25 UTC le 21/11. Tous les documents de la table existante datent du 20/11 au plus tard. Aucun n'est donc « futur » pour la variante.

**Cas neufs** (`pf` : exemptant daté du 2027-01-01 ; `prf` : `affected` du 2027-01-01 ; `pnf-autre-produit` : `not_affected` du 2027-01-01 pour un autre produit, non exemptant ; `p4` et `p6` : exemptants à l'heure du scan plus 4 et 6 min, soit 17:27:25Z et 17:29:25Z) :

| Cas | Documents | Aujourd'hui | Variante | Confiance |
|---|---|---|---|---|
| futur-seul | pf | `vex not_affected 2027-01-01T00:00:00Z ; sans exemption 0` | `aucune ; sans exemption 1` | haute |
| futur-et-ancien | pa, pf | `vex … 2027-01-01T00:00:00Z ; sans exemption 0` | `vex … 2026-11-01T00:00:00Z ; sans exemption 0` | haute |
| retractation-future | pa, prf | `aucune ; sans exemption 1` | idem | haute |
| futur-egalite | pf, prf | `aucune ; sans exemption 1` | idem | haute |
| retractation-puis-futur | pa, pr, pf | `vex … 2027-01-01T00:00:00Z ; sans exemption 0` | `aucune ; sans exemption 1` | haute |
| futur-autre-produit | pa, pnf-autre-produit | `aucune ; sans exemption 1` | idem | haute |
| bord-4-min | pa, p4 | `vex … 2026-11-21T17:27:25Z ; sans exemption 0` | idem | haute |
| bord-6-min | pa, p6 | `vex … 2026-11-21T17:29:25Z ; sans exemption 0` | `vex … 2026-11-01T00:00:00Z ; sans exemption 0` | haute |

**Lecture attendue** :
- Les lignes `futur-et-ancien` et `bord-6-min` portent le changement d'effet : un exemptant daté du futur ne masque plus une exemption valide plus ancienne.
- `retractation-future` est la preuve de l'asymétrie : une rétractation datée du futur garde son effet.
- Dans `retractation-puis-futur`, aujourd'hui, l'exemptant daté du futur l'emporte sur la rétractation du 20/11 : c'est un énoncé daté du futur qui lève une rétractation, et la porte le refuse alors (horodatage postérieur au scan). Avec la variante, la rétractation reste gagnante.
- `futur-autre-produit` montre que la variante ne lève pas tout le blocage : un `not_affected` daté du futur pour un autre produit n'est pas exemptant et reste dans le classement.

**Autres contrôles** :
- Toute la table existante du remplacement (11 cas) sur le binaire de la variante : résultats inchangés. Confiance haute.
- Compatibilité de l'image sur la variante : prédicat égal à celui du binaire du patch. Confiance haute.
- Heure du scan illisible (`descriptor.timestamp` à `x`, documents de `remplacement`) : aujourd'hui code 0 (l'heure est recopiée sans être lue), variante code 1. Confiance moyenne pour aujourd'hui, haute pour la variante.
- Diff de la variante appliqué, binaire construit, `go vet` : 3 OK.

**Total prédit** : 224 OK, 0 KO (192, plus 3 pour la variante, 1 de compatibilité, 11 pour la table existante, 16 pour les cas neufs sur deux binaires et 2 pour l'heure illisible). Patch inchangé : `9fcb4b40dc31c95d…`.

**Correction avant le vingtième passage** (date -u de 19:40:00 UTC, avant tout lancement) : la table existante du remplacement compte 12 cas, et non 11 (j'avais oublié `affected-autre-sous`). Le total prédit devient **225 OK, 0 KO**. Les autres prédictions ne changent pas.

## Ajout avant le vingt-et-unième passage : pièce 2, clé Transit `vex` (date -u de 20:12:52 UTC, le 2026-11-22, avant tout code)

**Objet** : mesurer à sec la signature avec `hashivault://vex`, jamais essayée (point 6 de la note du 21/11 à 17:51:53Z). C'est la pièce 2 de la pose, mesurée dans un OpenBao jetable, sans réseau, jamais dans celui du cluster. Mesure **synthétique**.

**Préparation, hors banc** (`resultats/07b-p2-bao.sh`, journal `07b-p2-bao.log`) : lecture anonyme de la copie de l'image OpenBao 2.7.2 en miroir dans Zot (`amont/openbao/openbao`, digest épinglé de la 08). Prédictions :
- l'index signé référence le manifeste linux/amd64 `sha256:a78eb12a…` ;
- la signature de l'index est revérifiée sur la copie de Zot avec l'identité de la 08 (workflow `release-images.yml` au tag v2.7.2, commit `9e0a0d3c…`, déclencheur `release`) ;
- `usr/bin/bao` est extrait dans `~/.cache/supply-chain-poc/07a/bao-2.7.2/` ; empreinte `9c5f36287c673f38…` (relevée par un essai d'extraction dans ce segment, dossier `p2-essai` effacé ensuite) ;
- `bao version` donne v2.7.2, commit `9e0a0d3c3504a0a00b45e61355afac5e35c78379`.

Confiance haute, sauf pour la signature : moyenne, car elle n'a été revérifiée qu'à la 08 et dépend de la racine TUF en cache.

**Banc, partie A** (hôte) : empreinte du binaire `9c5f36287c673f38` et `v2.7.2 (9e0a0d3c…)`, soit 2 OK. Confiance haute.

**Banc, partie B** (espace de noms réseau vide) : serveur `bao server -dev` sur 127.0.0.1:18200. Le jeton racine est écrit par le serveur dans un `HOME` du banc et n'est jamais passé en argument. Transit est activé. Les clés `vex`, `scanner` et `chains` sont en ecdsa-p256, non exportables. Les politiques `vex-signature` (fichier neuf du patch, calqué sur `scanner-signature`) et `scanner-signature` (fichier du dépôt) sont posées.

Le **jeton du propriétaire simulé** est émis par la racine du banc : politique `vex-signature` seule, sans `default`, orphelin, 15 min. Le vrai mode est un choix du propriétaire. Image et scan signé dans un dépôt neuf, `builds/bao`.

| Contrôle | Prédit | Confiance |
|---|---|---|
| OpenBao jetable : version, scellé | `2.7.2 false` | haute |
| clé vex (type, exportable, sauvegarde en clair, suppression) | `ecdsa-p256,false,false,false` | haute |
| politique `vex-signature` relue = fichier | empreintes égales | haute |
| jeton simulé : politiques, durée, renouvelable | `vex-signature 900 true` | moyenne (renouvelable) |
| signer, jeton vex, clé `hashivault://scanner` | `code 1 ; référents 0 ; refus signature en échec` | haute |
| signer, jeton vex, clé `hashivault://chains` | idem | haute |
| signer, jeton scanner, clé `hashivault://vex` | idem | haute |
| signer, jeton vex, clé `hashivault://vex` | `code 0 ; référents 1 ; refus aucun` | moyenne (premier essai de cosign avec hashivault sans `default`) |
| scanner.sh vex, `CLE_VEX` = clé publique tirée de Transit | VEX vérifiés, retenus, rejetés `1,1,0` | haute |
| scanner.sh vex, clé locale `vex.pub` | `0,0,0` | haute |
| jeton vex : création d'une clé, export de `vex`, `deletion_allowed` sur `vex`, écriture d'une politique, lecture de la clé `scanner`, émission d'un jeton | 6 refus, chacun `code 2 ; 1` (« permission denied ») | moyenne (texte de l'erreur) |

**Total prédit** : **244 OK, 0 KO**. Ce sont les 226 du passage 20, plus 2 en A et 16 en B. Le patch change, puisqu'il gagne `politique/vex-signature.hcl` : son empreinte sera relevée au passage. Aucun autre fichier du patch ne change.

## Ajout avant le vingt-deuxième passage : pièce 2, `userpass` du propriétaire et traces d'audit (date -u de 21:17:38 UTC, le 2026-11-22, avant tout code)

**Objet** : mesurer à sec le mode choisi par le propriétaire (`userpass`, décision de 21:16:55 UTC) et le critère qui l'a fait choisir : dans l'audit d'OpenBao, une signature par `userpass` et un contournement par la racine laissent-ils des traces distinctes ? Même OpenBao jetable que le passage 21, mesure **synthétique**.

**Changements du banc** :
- un device d'audit `file` dans le banc (`$T/bao-audit.log`), activé juste après Transit, donc avant les signatures du passage 21 ;
- après les refus du passage 21 : `userpass` activé, utilisateur `proprietaire` (politique `vex-signature` seule, sans `default`, 15 min) ;
- le mot de passe est aléatoire, dans un fichier 0600 du banc, et lu par `bao` (`password=@fichier`), jamais en argument ;
- dépôt neuf `builds/up` (image et scan signé).

| Contrôle | Prédit | Confiance |
|---|---|---|
| utilisateur `userpass` : politiques, sans default, durée | `vex-signature true 900` | haute |
| `bao login -method=userpass -no-store` : code, jeton écrit dans le `HOME` de la connexion | `code 0 ; absent` | moyenne (`password=@fichier` à la connexion) |
| jeton du propriétaire : politiques, utilisateur, durée | `vex-signature proprietaire 900` | haute |
| `signer`, jeton `userpass`, `hashivault://vex` | `code 0 ; référents 1 ; refus aucun` | haute |
| révocation par le propriétaire (`token revoke -self`) | `code 0` | haute |
| `signer` après révocation | `code 1 ; référents 1 ; refus signature en échec` | haute |
| connexion avec un mauvais mot de passe | `code 2 ; 1` (« invalid username or password ») | moyenne (texte) |
| audit : changement du mot de passe du propriétaire par la racine (contournement) | `root 1` | moyenne (nom affiché de la racine) |
| audit : signatures réussies sur `transit/sign/vex`, par identité | `token 1,userpass-proprietaire 1` | moyenne (noms affichés par défaut) |

**Lecture attendue** : la dernière ligne est le critère de la décision. La signature du passage 21 (jeton émis par la racine) apparaît sous `token`, celle du propriétaire sous `userpass-proprietaire`. Le contournement (la racine change le mot de passe) laisse sa propre ligne sous `root`.

**Total prédit** : **253 OK, 0 KO** (244 du passage 21, plus 9). Le patch ne change pas (`08d36964085e0814…`).

**Correction avant la relance du vingt-deuxième passage** (date -u de 21:27:03 UTC, avant la relance) : le premier passage, lancé à 21:18:07 UTC ([journal](07b-t3-banc-22-premier-passage.log)), s'est arrêté au début de la section OpenBao, après 205 OK et 0 KO. OpenBao 2.7.2 refuse d'activer un device d'audit par l'API (« use declarative, config-based audit device management instead »). Je ne l'avais pas prévu. Le banc sortait en code 2, et mon enrobage affichait ce code sans le traiter comme un échec.
- **Changement** : le device d'audit du banc est déclaré dans un fichier de configuration passé à `bao server -dev -config=…`, comme le fait la 08 pour l'OpenBao du cluster. Un essai jetable hors banc l'a confirmé (device `banc/` listé, lignes écrites).
- **Contrôle ajouté** : « audit déclaratif du banc » : `banc/ file`. Confiance haute.
- **Total prédit** : **254 OK, 0 KO**. Les autres prédictions ne changent pas.

## Ajout avant le banc de pose de la pièce 2 : `vex-openbao.sh` (date -u de 22:09:33 UTC, le 2026-11-22, avant tout code)

**Objet** : écrire à sec le script qui posera la pièce 2 dans l'OpenBao du cluster, et l'éprouver sur l'OpenBao 2.7.2 jetable des passages 21 et 22, avec cette fois TLS (`-dev-tls`). Rien n'est lancé sur le vrai cluster, pas même la lecture `releve`, car `kubectl exec` dans `openbao-0` avec le jeton racine demande un accord.

**Script** : `poc/bricks/07a-sbom-grype/vex-openbao.sh`, calqué sur `o5-openbao.sh` de la 09. Il est ajouté à l'arbre du patch, à côté de `politique/vex-signature.hcl` qu'il lit, donc le patch change d'empreinte (11 fichiers). Il a quatre étapes, chacune refusant si son objet existe déjà :
- `releve` : lecture seule (état, clés Transit, politiques, méthodes d'authentification) ;
- `cle_vex` : clé Transit `vex` (ecdsa-p256, non exportable, sans sauvegarde en clair), clé publique exportée dans `resultats/vex-cle-publique.pem` (chemin attendu par `cm_scan`), seule différence vérifiée ;
- `acces_vex` : **lancé par le propriétaire dans son terminal**. Le mot de passe est saisi deux fois sur `/dev/tty`, sans écho, et refusé si les saisies diffèrent ou s'il compte moins de 12 caractères. Puis viennent la politique `vex-signature`, le montage `userpass/` et l'utilisateur `proprietaire`. Le mot de passe passe par l'entrée standard de `kubectl exec`, puis par celle de `bao write … password=-` dans le pod, jamais en argument. L'étape refuse si la politique, le montage ou l'utilisateur existe déjà : une relance ne réécrit jamais le mot de passe (contournement du passage 22) ;
- `essai` : **lancé par le propriétaire**. Redirection 127.0.0.1 vers `openbao-0:8200` (comme `o5-cosign.sh`), `bao login -method=userpass -no-store` par l'invite, puis une signature `transit/sign/vex` vérifiée par openssl avec la clé publique archivée, des refus croisés, `cosign public-key --key hashivault://vex` comparé à la clé archivée, `token revoke -self`, et un refus après révocation. Le jeton vit dans un fichier 0600 effacé à la sortie.

Les journaux évitent « jeton » et « token », que le masquage remplace. Les valeurs de l'utilisateur sont donc relues par `jq` en valeurs seules. Contrôles de fin de journal, comme K4 et K5 de la 09 : la valeur du jeton racine et celle du mot de passe sont absentes du journal, sinon le journal est vidé.

**Banc** : `resultats/07b-p2-pose-banc.sh`, dans `unshare -rn`.
- OpenBao 2.7.2 en `-dev -dev-tls`, audit déclaré dans la configuration (passage 22).
- Clés `chains`, `scanner`, `tsa` et `lien` créées d'abord, pour imiter le cluster.
- Faux `kubectl` : `exec` lance un `sh` local pointé sur le serveur du banc ; `port-forward` annonce le port du serveur.
- Secrets du banc seulement, jamais `08/secrets`.
- Hors du vrai terminal, le mot de passe vient d'un fichier du banc désigné par une variable lue seulement quand `BANC` est posé.

| Cas | Prédit | Confiance |
|---|---|---|
| `releve`, OpenBao neuf | code 0 ; `vex` absente, PEM absent, politique absente, `userpass/` absent | haute |
| `cle_vex` | code 0 ; `ecdsa-p256,false,false,false,1,true` ; PEM lisible par openssl (P-256) ; seule différence : `vex` ajoutée | haute |
| `cle_vex` relancée | code 1 ; refus « existe déjà », clés inchangées | haute |
| `acces_vex` sans terminal ni fichier du banc | code 1 ; refus avant toute écriture (`/dev/tty` illisible dans la session) | moyenne (message de `/dev/tty`) |
| `acces_vex`, saisies différentes | code 1 ; rien écrit (politique et `userpass/` absents) | haute |
| `acces_vex`, mot de passe de 11 caractères | code 1 ; rien écrit | haute |
| `acces_vex` | code 0 ; politique relue = fichier ; seule méthode ajoutée : `userpass/` ; utilisateur : `vex-signature`, sans `default`, 900 s, 900 s | haute |
| journal d'`acces_vex` | valeur du mot de passe et du jeton racine absentes | haute |
| `acces_vex` relancée avec un autre mot de passe | code 1 ; refus « existe déjà » ; la connexion avec le premier mot de passe marche encore | haute |
| connexion par `password=@fichier` sans saut de ligne final (mot de passe posé par le canal du script) | code 0 | **moyenne** : c'est le point qui peut casser (`password=-` ou le heredoc pourraient garder un saut de ligne) |
| connexion par `password=@fichier` avec un saut de ligne final | code 2 | **basse** : `bao` peut retirer le saut de ligne d'un fichier, auquel cas le contrôle ne discrimine pas |
| connexion par l'invite, sous un pty (canal réel du propriétaire) | code 0 | moyenne (pilotage du pty) |
| `essai` | code 0 ; signature acceptée et vérifiée par openssl ; témoin refusé ; refus : signature `chains`, `scanner`, `tsa`, `lien`, lecture de `transit/keys/chains`, export de `vex`, `vex` rendue exportable, sauvegarde de `vex`, `kv`, liste des politiques, création d'un jeton, consultation de soi ; `cosign public-key` = clé archivée (SPKI) ; révocation acceptée ; signature après révocation refusée ; fichier du jeton effacé, redirection fermée | moyenne (`cosign` à travers `-dev-tls` et le nom TLS du banc) |
| audit du banc | signature réussie sur `transit/sign/vex` : `userpass-proprietaire 1` ; création de l'utilisateur : `root 1` | moyenne |

**Total** : le nombre exact de lignes OK dépend du code, pas encore écrit. Il sera fixé par un ajout daté, après le code et avant le premier passage. Les prédictions de comportement ci-dessus ne changeront pas.

**Total prédit du banc de pose de la pièce 2** (date -u de 22:15:23 UTC, après le code, avant le premier passage) : **31 OK, 0 KO**, un par appel d'`attendu` du banc (2 dans le parent, 29 dans l'espace de noms). Script éprouvé : `vex-openbao.sh` de l'arbre du patch, sha256 `e4d59af97816491a…`. Les prédictions de comportement ne changent pas. Un KO sur « connexion, fichier avec saut de ligne final » (confiance basse) voudrait dire que `bao` retire le saut de ligne : la prédiction serait fausse, sans défaut du script.

**Correction avant la relance du banc de pose de la pièce 2** (date -u de 22:16:26 UTC, avant la relance) : le premier passage ([journal](07b-p2-pose-banc-premier-passage.log)) a fini à 11 OK et 20 KO. L'OpenBao du banc n'a jamais démarré : `bao server -dev -dev-tls` exige que le dossier de `-dev-tls-cert-dir` existe, et le banc ne le créait pas. C'est un défaut du banc, non du script. Les 11 OK venaient de refus et de contrôles qui ne demandent pas de serveur. Un essai jetable hors banc, avec le dossier créé, a donné `2.7.2 false` en TLS, avec le nom `localhost` présent dans le certificat. Changement : le banc crée ce dossier (0700). Les prédictions et le total (**31 OK, 0 KO**) ne changent pas.

**Deuxième correction du banc de pose de la pièce 2** (date -u de 22:16:58 UTC, avant la relance) : le deuxième passage ([journal](07b-p2-pose-banc-deuxieme-passage.log)) a fini à 30 OK et 1 KO. Le KO vient de la forme attendue par le banc : OpenBao liste les politiques dans l'ordre `default,vex-signature,root`, non trié, alors que j'attendais `default,root,vex-signature`. L'ensemble est le même, et le script n'est pas en cause : il trie lui-même ses listes avant de les comparer. Toutes les prédictions de comportement ont tenu, y compris les deux de confiance basse ou moyenne : le fichier avec saut de ligne final est refusé (code 2), et l'invite sous un pty accepte le mot de passe. Changement : le banc trie la liste. Le total prédit (**31 OK, 0 KO**) ne change pas.

## Ajout avant le quatrième passage du banc de pose de la pièce 2 (date -u de 22:21:30 UTC, le 2026-11-22, avant tout code)

**Objet** : le conseiller a relevé trois chemins jamais exécutés, que seul le propriétaire prendra et que la session ne pourra pas déboguer faute de terminal :
- les branches terminal du script (`lire_mdp` sur `/dev/tty` et la connexion d'`essai` par l'invite), le pty du troisième passage ayant lancé `bao login` directement ;
- la relance d'`essai` après une connexion ratée : le dossier de travail restait, et toute relance répondait « existe déjà » ;
- la reprise d'`acces_vex` après un échec partiel (« politique identique : laissée », « montage présent : laissé », « politique différente : refus »).

Il a aussi noté que `${#MDP}`, sous `LC_ALL=C`, compte des octets, alors que le message dit « caractères ».

**Changements prévus** :
- `essai` crée un dossier neuf par lancement (`mktemp -d`), donc une connexion ratée n'empêche plus la relance ;
- la branche de connexion se choisit sur `BANC_MDP_CONNEXION`, et non plus sur `BANC`, comme `lire_mdp` le fait déjà ;
- la longueur du mot de passe se compte en caractères (`wc -m` sous `C.UTF-8`) ;
- le banc passe `acces_vex` et `essai` sous un pty, avec `BANC` mais sans fichier de mot de passe, et ajoute les cas de reprise. Le cas « `essai` relancé, refus » disparaît.

Journal neuf : `07b-p2-pose-banc-4.log`. Le journal du troisième passage n'est pas réécrit.

| Cas neuf | Prédit | Confiance |
|---|---|---|
| `acces_vex`, 11 caractères accentués (plus de 12 octets) | code 1, refus « moins de 12 caractères » | moyenne (locale `C.UTF-8` présente) |
| utilisateur effacé par la racine du banc, politique modifiée dans OpenBao, `acces_vex` | code 1, « présente et différente », utilisateur toujours absent, politique toujours modifiée | haute |
| politique remise conforme, `acces_vex` **sous pty, deux invites**, troisième mot de passe | code 0 ; « laissée » et « laissé » ; utilisateur conforme ; K6 ; deux invites vues | moyenne (pilotage du pty, `read -s` sur `/dev/tty`) |
| connexion avec le troisième mot de passe / avec le premier | code 0 / code 2 | haute |
| `essai`, mauvais mot de passe (fichier) | code 1, connexion refusée | haute |
| `essai` relancé **sous pty**, invite de `bao` | code 0 ; 14 essais conformes ; invite vue ; aucun fichier dans les `HOME` des clients | moyenne (invite de `bao` sur `/dev/tty`, sortie standard vers le journal) |
| audit : écritures (création ou mise à jour) de l'utilisateur, par identité | `root 2` | moyenne (nom de l'opération) |
| audit : signatures réussies sur `transit/sign/vex`, par identité | `userpass-proprietaire 1` | haute |

Les autres cas du troisième passage gardent leur prédiction. Le total sera fixé par un ajout daté, après le code et avant le passage.

**Total prédit du quatrième passage du banc de pose** (date -u de 22:24:11 UTC, après le code, avant le passage) : **37 OK, 0 KO**. C'est 31, moins le cas « `essai` relancé, refus », qui disparaît, plus 7 contrôles : 11 caractères accentués, politique différente, reprise sous pty, connexions après la reprise, mauvais mot de passe, `essai` sous pty, un dossier par lancement. Le contrôle de connexion directe sous pty change de forme : le pilote n'affiche qu'un résumé, `pty : code 0 ; invites vues 1 ; échos du mot de passe 0`. Script éprouvé : `vex-openbao.sh` sha256 `8e2177864616a82a…`. Journal : `07b-p2-pose-banc-4.log`.

**Correction avant la relance du quatrième passage du banc de pose** (date -u de 22:24:53 UTC, avant la relance) : le premier essai du quatrième passage ([journal](07b-p2-pose-banc-4-premier-passage.log)) a fini à 36 OK et 1 KO. Le KO, « rien dans le HOME du client : 10 », vient du banc. Le motif `-path '*/home/*'` correspond aussi au début de tous les chemins (`/home/<utilisateur>/…`), si bien que les 10 fichiers comptés étaient les fichiers de travail des deux dossiers d'essai. Recompté avant l'effacement du banc, chaque dossier `home` des clients contient 0 fichier. Changement : le banc compte dans `travail/essai-*/home`. Toutes les prédictions de comportement ont tenu, y compris les deux pilotages sous pty (`invites vues 2`, puis `invites vues 1`, `échos du mot de passe 0`). Le total (**37 OK, 0 KO**) ne change pas.

## Ajout avant la pose réelle de la pièce 2 (date -u de 22:36:30 UTC, le 2026-11-22, avant tout lancement sur le cluster)

**Accord** du propriétaire, « Oui » (22/11/2026), pour quatre choses : reporter les deux fichiers de la pièce 2 dans le dépôt (fait, a614595b) ; lancer `releve` puis `cle_vex` par `kubectl exec` avec le jeton racine ; lancer, de sa main, `acces_vex` puis `essai` ; puis le compte de `userpass-proprietaire` dans Loki par l'auditeur. Ici, seuls `releve` et `cle_vex` sont lancés par la session.

| Étape et contrôle | Prédit | Confiance |
|---|---|---|
| `releve` : état | OpenBao 2.7.2, initialisé, descellé | haute |
| `releve` : clés Transit | `chains`, `lien`, `scanner`, `tsa`, chacune ecdsa-p256, non exportable | moyenne (une rotation non notée est possible) |
| `releve` : absences | `vex`, `resultats/vex-cle-publique.pem`, politique `vex-signature`, montage `userpass/` : absents | haute |
| `releve` : méthodes d'authentification hors la méthode native | `jwt/ jwt` seule | moyenne |
| `releve` : code ; KO | code 0 ; 0 KO | haute |
| `cle_vex` | code 0 ; `ecdsa-p256,false,false,false,1,true` ; clé publique P-256 ; seule différence : `vex` ajoutée | haute |
| journaux | K3 et K4 : OK | haute |
