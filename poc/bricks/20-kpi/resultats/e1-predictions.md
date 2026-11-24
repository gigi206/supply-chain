# Brique 20, étape 1 : relevé anonyme des attestations de builds/, prédiction

Prédiction écrite le 2026-11-24 à 18:25:46 UTC (`date -u`), commitée avant le lancement. Sans accord : lecture anonyme seule, rien n'est écrit dans Zot, ni sur les VM, ni dans le cluster, ni dans Grafana. Plan relu par le conseiller.

## Ce qui est mesuré

Script [`releve-zot.sh`](../releve-zot.sh) (sha256 `caa8ae0a8f60c7b4…` à l'écriture de la prédiction), journal `resultats/e1-releve-zot.log`. Il est refusé si le journal existe ; un passage raté est relancé avec `SUFFIXE=-1`.

- **Catalogue** : `_catalog` en anonyme. Orientation faite à 18:23:41 UTC : code 200 et pas d'en-tête `Link`, donc pas de pagination. Le contenu n'a pas été lu avant cette prédiction.
- **Sujets** : pour chaque dépôt `builds/` qui n'est pas un dépôt d'attestations, digests tirés des tags `sha256-<digest>.<suffixe>` (Chains : `.sig`, `.att`), plus le digest de chaque autre tag. **Limite** : un artefact sans aucun tag reste invisible.
- **Attestations** :
  - couches du tag `.att` ;
  - referrers du sujet dans `builds/<famille>/<nom>` (familles `scan`, `vsa`, `vex`, `avis`), si ce dépôt est au catalogue.

  Chaque énoncé est décodé (enveloppe DSSE, ou `dsseEnvelope` d'un bundle sigstore) pour deux informations seulement : son `predicateType`, et s'il nomme le digest de son sujet. **Les signatures ne sont pas vérifiées** : c'est l'étape 2. Les lignes du journal comptent donc des énoncés, pas des attestations prouvées.
- **Archivage** : type, sujet, digest, forme, date de création annotée et comptes. Aucun contenu d'énoncé, puisque les VEX portent un auteur.
- **Classe** : déduite du nom du dépôt (`produit`, `builder`, `fermeture`, `attestation`, `autre`). Elle sert à décrire, pas à décider : le dénominateur des KPI reste un choix du propriétaire (voir le README).

## Cas comparés (11)

Chaque attendu vient d'un journal archivé :

1. **Catalogue en anonyme** : `200`. Source : orientation de 18:23:41 UTC.
2. **VSA de `3a7ca1b1`** dans `builds/vsa/sample-app` : **1**. Source : `08-trust-plane/resultats/rejeu-un-trait-1-reprise.log` l. 1479-1490, poussée le 23/11 à 22:31:15Z, manifeste `69a2b103…`. Après ce rejeu, Zot n'a pas été recréé.
3. **VSA de `f5e6bcb0`** : **0**. R5 n'a pas eu lieu, et R4 n'est pas possible avant le 2026-11-25T13:27:42Z.
4. **VSA du deb `60f25f5c`** dans `builds/vsa/sample-app-deb` : **1**. Source : même journal, `s6b.sh pousser_vsa` du 23/11 à 23:19:47Z, manifeste `97b4100d…`.
5. **VEX de `3a7ca1b1`** dans `builds/vex/sample-app` : **1**. Source : `07a-sbom-grype/resultats/piece8-signer-signer-sample-app-3a7ca1b1.log`, `PUBLIE|…@sha256:fbf5d0bf…`.
6. **VEX de `f5e6bcb0`** : **1**. Source : `piece8-signer-signer-sample-app-f5e6bcb0.log`, `PUBLIE|…@sha256:b139ef42…`.
7. **VEX du deb `60f25f5c`** dans `builds/vex/sample-app-deb` : **1**. Source : `piece8-signer-signer-sample-app-deb-60f25f5c.log`, `PUBLIE|…@sha256:44f86e53…`.
8. **Au moins un scan de `f5e6bcb0`** : **oui**. Source : carte de la 07c, bascule des unités de scan (« Derniers scans dans Zot : `f5e6bcb0` à 14:12:32Z »).
9. **Provenance `https://slsa.dev/provenance/v1`** dans le `.att` de `f5e6bcb0` : **oui**. Source indirecte : Chains attache la provenance au tag `.att` de chaque image qu'il signe (`07a-sbom-grype/resultats/g7-etat-avant-2.log`, section 1 : `.att` à 200 pour `3a7ca1b1`), et `f5e6bcb0` sort de la même pipeline. Le `.att` de `f5e6bcb0` n'a pas été lu.
10. **Prédicats `licences/v1`** : **0**. Le prédicat n'est produit qu'au banc (docs/03, ligne Licences).
11. **Referrers dont le type ne suit pas la famille** : **0**. Les types attendus, écrits par les scripts (relevé dans le dépôt à 18:25 UTC), sont :
    - `scan` → `https://supply-chain.example/scan/v1` ;
    - `vsa` → `https://slsa.dev/verification_summary/v1` ;
    - `vex` → `https://openvex.dev/ns/v0.2.0` (`OPENVEX` de `signer-vex.sh` l. 50).

Un douzième cas est ajouté par le script : **énoncés qui ne nomment pas leur sujet**, attendu **0**. Il est moins sûr que les autres. La forme du sujet des provenances de Chains pour le deb et le rpm (artefacts OCI qui ne sont pas des images) n'a jamais été lue. Un écart ici serait un constat sur la forme du sujet, pas un défaut du relevé.

Bilan attendu : **12 cas, 0 écart**.

## Consigné, non comparé

- Nombre de dépôts, de sujets par classe et d'attestations par type.
- Nombre de scans par sujet : la rétention G7 (`07a`) supprime les plus anciens, donc le compte n'est pas prévisible.
- Plus ancienne et plus récente date annotée par dépôt d'attestations. Elles serviront au choix « délai de correction des KEV », pour savoir si l'historique de Zot suffit.
- Sujets du rpm (`builds/sample-app-rpm`, rejeu M5b du 23/11) : provenance attendue, ni scan ni VSA ; leur présence n'est pas comparée.
- Dépôts d'attestations sans dépôt de sujets du même nom (`ORPHELIN`).

## Heures

Brique 20 : de 18:23:30 UTC (fin de la dernière note de la 07c) à cette prédiction, puis jusqu'au résultat. Elles sont additionnées au total de la carte avec le résultat.

## Résultat (note de 2026-11-24T18:26:51Z)

[Journal](e1-releve-zot.log) : passage du 2026-11-24 à 18:26:24 UTC, dépôt `991c0021`, script `caa8ae0a8f60c7b4`. **12 cas, 2 écarts.** Les deux écarts sont des fautes de la prédiction, pas des défauts de la plateforme.

**Les 10 premiers cas sont conformes** :
- VSA : 1 pour `3a7ca1b1`, 0 pour `f5e6bcb0`, 1 pour le deb `60f25f5c` ;
- VEX : 1 pour chacun des trois ;
- au moins un scan de `f5e6bcb0` ;
- provenance SLSA v1 dans le `.att` de `f5e6bcb0` ;
- aucun prédicat `licences/v1`.

**Écarts 11 et 12** (1 referrer d'un autre type, 4 énoncés qui ne nomment pas leur sujet) : les quatre lignes en cause sont des **témoins négatifs voulus**, que la prédiction aurait dû exclure ou attendre :
- `builds/essai-j6-att-illisible` : `.att` illisible, témoin de J6 (08, README l. 499) ;
- `builds/essai-j6-autre-sujet` : provenance authentique de Chains qui nomme un autre sujet, témoin de J6 (08, README l. 518) ;
- `builds/scan/essai-scan` : un scan qui nomme un autre sujet et un referrer illisible, témoins de G6 (07a, « 15 témoins »).

Pour les dépôts produits, builders et fermetures, **aucun énoncé n'est illisible et tous nomment leur sujet**. Cela vaut aussi pour le deb et le rpm, le cas le moins sûr de la prédiction.

**Consigné** :
- 156 dépôts au catalogue, dont 31 sous `builds/` : 8 d'attestations, 3 produits, 3 builders, 5 fermetures, 12 autres (essais et témoins). La liste des dépôts hors `builds/`, écrite sur une seule ligne, a été masquée par le filtre `jeton|token` : un nom au moins contient le motif. Le prochain relevé l'écrira une ligne par dépôt ;
- 38 sujets (produit 4, builder 3, fermeture 5, autre 26) et 122 énoncés ; aucun dépôt d'attestations orphelin.
- **Produits, par sujet** (énoncés non vérifiés) :

  | Sujet | Provenances (`.att`) | Scans | VEX | VSA |
  |---|---|---|---|---|
  | `sample-app@3a7ca1b1` | 6 | 3 | 1 | 1 |
  | `sample-app@f5e6bcb0` (en service) | 8 | 2 | 1 | 0 |
  | `sample-app-deb@60f25f5c` | 8 | 3 | 1 | 1 |
  | `sample-app-rpm@07b7bd6f` | 2 | 0 | 0 | 0 |

- **Historique dans Zot** : les plus anciens scans datent du rejeu du 23/11 (`builds/scan/sample-app` depuis 2026-11-23T22:28:30Z, deb depuis 23:19:26Z). Un rejeu de zéro remet donc l'historique à zéro. Pour le délai de correction des KEV, Zot ne donne pas plus d'un jour aujourd'hui ; Loki (720 h) ne survit pas non plus à un rejeu.

**Premier aperçu des dénominateurs, à ne pas prendre pour des KPI** (énoncés non vérifiés, dénominateur non choisi) : sur les 4 sujets produits, 4 ont une provenance, 3 un scan, 3 un VEX et 2 une VSA. Le seul digest en service de l'image, `f5e6bcb0`, n'a pas encore de VSA (R5).

**Heures de la 20, étape 1** : de 18:23:30 à 18:27:04 UTC, script, prédiction, passage et note compris : 0 h 03 min 34 s.

## Après relecture du conseiller (note de 2026-11-24T18:30:36Z)

**Loki repart de zéro à chaque rejeu : mesuré.** La note de résultat l'affirmait sans mesure. Relevé [`e1-loki-anciennete.log`](e1-loki-anciennete.log) (script [`loki-anciennete.sh`](../loki-anciennete.sh), auditeur, comptes seulement, 18:30:04 UTC) :
- les fenêtres de 24 h qui finissent le 22/11 à 12:00 et le 23/11 à 20:00 UTC n'ont **aucune série**, ni pour tout le journal, ni pour `entrees-scan`, alors que `entrees-scan` tourne depuis le 21/11 ;
- la fenêtre qui finit le 24/11 à 12:00 a 475 914 lignes, dont 199 de `entrees-scan`.

Le rejeu du 23/11 commence à 20:35:05 UTC (`rejeu-un-trait-1.log`). L'historique de Loki commence donc avec lui. Un premier passage du même relevé, lancé depuis le scratchpad à 18:29:44 UTC, a donné les mêmes valeurs ; il n'est pas archivé.

**`releve-zot.sh` corrigé pour les prochains passages** (sha256 `9893deefc1f1acad…`, contre `caa8ae0a…` pour le passage archivé) :
- les dépôts hors `builds/` s'écrivent une ligne par dépôt (`HORS|…`), donc le filtre ne masque plus que les noms concernés ;
- les cas 11 et 12 excluent les trois dépôts de témoins négatifs ; un treizième cas attend leurs **4** énoncés défectueux. Rejoués sur les lignes archivées, les trois cas donnent 0, 4 et 0.
