# ADR 0004 : vulnérabilités et VEX (OpenVEX ou CSAF)

- **Statut** : **À rédiger**. Seules les décisions du propriétaire du 21/11/2026 (brique 07b, choix 1 à 5) et leurs limites sont écrites. Restent la projection Dependency-Track, le score et les KPI de couverture VEX. `vex_age_max_jours` est fixé à 30 jours (2026-11-21T20:13:42Z).
- **Date** : 2026-11-21
- **Décideurs** : propriétaire du projet

Sources : la [carte de la 07b](../../poc/bricks/07a-sbom-grype/resultats/07b-carte.md) (tranche 2 : mesures de Grype 0.104.1 avec `--vex` ; recommandations relues par le conseiller ; réponses du propriétaire, verbatim) et la tranche 3, préparée à sec et non posée.

## Décision

Format **OpenVEX** (spécification v0.2.0). Le VEX est une attestation in-toto signée, rattachée en referrer au digest de l'artefact dans un dépôt séparé (`builds/vex/<nom>`), comme le scan.

| # | Question | Décision du propriétaire (21/11/2026) |
|---|---|---|
| 1 | Qui applique le VEX | **Le scanner** (`grype --vex`). Le prédicat de scan signé porte le résultat : chaque entrée écartée garde ses champs et reçoit `vex` (statut, horodatage) ; le prédicat cite l'empreinte de chaque document passé. |
| 2 | Quelle clé signe un VEX | **Une clé distincte** de celle du scanner (clé Transit neuve, dont seul le propriétaire a l'usage). |
| 3 | D'où vient l'échéance | **Une durée dans la politique** (`vex_age_max_jours`), comptée depuis l'horodatage le plus ancien des documents passés ; un horodatage postérieur au scan est refusé. **Amendé le 2026-11-21 (remplacement)** : l'horodatage est celui de l'énoncé gagnant, le plus récent qui nomme l'entrée (nom ou alias), quel que soit son statut ; exemption seulement si tous les énoncés à cet horodatage sont recevables et citent le digest scanné. |
| 4 | Quel format | **OpenVEX** ; CSAF non évalué. |
| 5 | Qui écrit `not_affected`, sur quelle preuve | **Le propriétaire, à la main**, avec `justification` **et** `impact_statement` ; `fixed` retiré des statuts acceptés. |

## Limites, dites en clair

- **La porte fait confiance au scanner pour le VEX.** Un scanner compromis écrirait `vex` lui-même ou tairait une correspondance. La clé distincte n'y change rien : elle protège seulement contre qui écrit sous `builds/vex/` sans la clé.
- **Grype ne dit pas quel énoncé a écarté quelle correspondance.** Seul son statut est recopié. L'horodatage retenu est donc le plus ancien des documents passés : quand le plus vieux expire, toutes les exemptions du scan tombent.
- **Amendement du 2026-11-21** : Grype ne le dit toujours pas. Le prédicat retrouve désormais les énoncés qui nomment chaque entrée (identifiant et alias, des deux côtés). Un vieux document sur une autre vulnérabilité ne tire plus l'échéance des autres (mesuré : cas `partiel`).
- **Remplacement, limites** :
  - Un document daté dans le futur gagne tous les classements jusqu'à sa date. La porte le refuse : c'est un blocage fermé. La réparation est le retrait de l'ancien référent, sur accord.
  - Un document illisible (type, sujet, contexte, horodatage) ne remplace rien.
  - Grype reçoit toujours tous les documents recevables, même remplacés : c'est le prédicat qui décide.
  - Le compteur `ecarteesSansExemption` n'a pas de série dans Grafana.
  - **Couverture du paquet (2026-11-21T21:04:20Z)** : le gagnant doit couvrir le paquet de l'entrée (énoncé sans sous-composant, ou PURL de l'entrée parmi les sous-composants, égalité exacte). Conséquence : un énoncé récent sur un paquet P2 fait tomber l'exemption de P1, pour la même vulnérabilité, tant que P1 n'est pas re-signé (échec fermé). `vulnerability.@id` compte parmi les noms. Patch `2005250baa1c3682…`, passage 9 : 109 OK, 0 KO.
- **Il n'existe pas d'heure de signature de confiance** : la signature se fait sans journal de transparence (signing-config vide, `--insecure-ignore-tlog`). L'horodatage est celui que l'auteur écrit ; la porte refuse seulement qu'il soit postérieur au scan.
- **Le produit du VEX n'est pas vérifié par Grype sur l'entrée du scanner** (SBOM fusionné à composant `container`, tranche 2, constat 2). La portée vient du sujet de l'attestation : seuls les VEX attestés sur le digest scanné sont passés. Chaque nouveau digest demande donc un nouveau VEX signé.
- **Délais** : un VEX neuf ne compte qu'au scan suivant (une fois par jour) ; un VEX retiré reste effectif jusqu'au scan suivant.
- **La spécification OpenVEX est en brouillon (v0.2)** et elle est incohérente sur `not_affected` (`justification` **ou** `impact_statement` dans un tableau, `justification` dans l'autre). Le PoC exige les deux, plus strict que la spécification.
- **CSAF non évalué** : un seul document témoin, non validé contre le schéma, accepté sans erreur et sans effet, pour une cause non établie. Rien n'est dit de la prise en charge de CSAF par Grype.
- **Aucun outil d'atteignabilité** n'est évalué dans `docs/04` : un `not_affected` ne repose que sur l'analyse de son auteur.

## Reste ouvert

- `vex_age_max_jours` : **30 jours**, choix du propriétaire (2026-11-21T20:13:42Z), recommandation du conseiller suivie. C'est un jugement, sans mesure qui le fonde. Sans la clé, aucune KEV n'est exemptée.
- Renouvellement : *jusqu'au patch `e063abd2aedf18af…`*, la durée partait de l'horodatage le plus ancien des documents retenus. Un VEX neuf ne renouvelait donc rien tant que l'ancien restait publié dans `builds/vex/`, et `cosign attest` v3.1.4 n'a pas d'option de remplacement. Le retrait de l'ancien référent est mesuré au banc jetable (2026-11-21T20:24:29Z, passage 6). `oras manifest delete` sur le digest du manifeste référent le retire de l'API referrers ; l'échéance suit alors le document restant. Rien n'est outillé dans la plateforme : le vrai Zot demanderait un droit de suppression sur `builds/vex/**`, c'est-à-dire un changement de configuration, sur accord. **Choix du propriétaire (2026-11-21T20:39:16Z) : remplacement dans `scan-outil`** (recommandation du conseiller, jugement). Pour un même couple vulnérabilité et produit, l'énoncé le plus récent l'emporte, quel que soit son statut ; le filtre de recevabilité s'applique ensuite. Le registre reste en ajout seul. Le retrait mesuré au banc n'est pas retenu. Le patch est écrit et mesuré (2026-11-21T20:56:05Z, `f38347ad37379efa…`, passage 8 du banc : 107 OK, 0 KO).
- Écart avec Dependency-Track : d'après `docs/00` (ligne 277, non revérifié), il ne lit que le VEX de CycloneDX. La projection est hors de la 07b.
- Score « vulnérabilités après VEX » et KPI de couverture VEX (`docs/02`).
