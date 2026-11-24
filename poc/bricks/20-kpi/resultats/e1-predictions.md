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
