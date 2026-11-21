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
