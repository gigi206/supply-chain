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
