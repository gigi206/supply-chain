# Brique 09, carte d'O6 : chiffrage à sec (19/11/2026)

O6 est **optionnel**, « à chiffrer après O5 », hors de l'estimation de 1,5 pw ([README](../README.md), table des jalons). Il propose deux voies : une tâche signée dans la pipeline, ou un contrôle par la porte (Conforma). Cette carte les chiffre. Elle n'engage rien : aucune règle ni aucun script de la porte n'est écrit avant la décision du propriétaire.

J'ai lu la réponse « Continue » du propriétaire, après la question « faut-il préparer O6 à sec ? », comme un oui à cette préparation. Rien n'est posé dans le cluster, et rien n'est écrit dans Zot.

## Ce qui est déjà vrai (lu ou mesuré)

- **Seuil de la brique atteint sur l'hôte** : rpm, deb et dépôts signés, attestations de lien vérifiées en anonyme, par cosign et par le contrôle indépendant ([o5-signes-predictions.md](o5-signes-predictions.md)). O6 n'est pas nécessaire au seuil.
- **La porte ignore les attestations de lien.** La liste des refus du doc 02 (§5) ne nomme pas le lien, alors que le §4 le range parmi les referrers des artefacts livrés.
- **Modèle déjà en service : le contrôle 6 (VSA).** [`vsa.sh`](../../08-trust-plane/politique/porte/vsa.sh) est un conteneur du Job de la porte, sur l'image d'outils (cosign 3.1.4). Il appelle `cosign verify-attestation` avec une autre clé que celle de Chains (`vsa.pub`, dans la ConfigMap). Il retient les énoncés selon leur type, leur sujet et leurs champs. Le Job ne réussit que si tous ses conteneurs réussissent ([`porte-job.yaml`](../../08-trust-plane/politique/porte-job.yaml), en-tête).
- **Ce qu'un bundle en referrer fait à ec et à cosign, mesuré par la brique 10 (R5, 03/11/2026)** ([r5-referrer-porte-predictions.md](../../10-independent-replay/resultats/r5-referrer-porte-predictions.md)) :
  - un bundle v0.3 rangé en referrer d'une image fait ignorer `.sig` et `.att` par ec 0.10.42 et par cosign 3.1.4 ;
  - avec la clé de Chains, ec voit alors 0 signature et 0 attestation ;
  - les attestations de lien sont rangées dans `signes/**`, jamais dans `builds/**` : elles ne touchent pas aux images que la porte juge aujourd'hui.
- **Objets de `signes/**`** : aucune signature d'image, aucune provenance SLSA, aucun bundle horodaté. Leur seule attestation est celle du lien, signée par la clé Transit `lien`.
- **D2 décidée en (a)** : la clé OpenPGP reste hors du cluster, sur l'hôte d'administration.
- **Kyverno** : ses règles d'admission ([`admission.yaml`](../../08-trust-plane/politique/admission.yaml)) jugent des pods et des objets Tekton. Un rpm, un deb ou un dépôt n'est jamais l'image d'un pod. **Kyverno est sans objet pour O6**, et la carte ne le chiffre pas.

## Voies

### P. Contrôle du lien par la porte (conteneur `lien`, sur le modèle de `vsa.sh`)

- **Entrées du Job** : `IMAGE` est le manifeste non signé (`builds/…@sha256`). ec le juge comme aujourd'hui (provenance de Chains, horodatage, VSA, scan). `SIGNE` est l'objet signé (`signes/…@sha256`), une entrée neuve.
- **Conteneur `lien`** (image d'outils, cosign 3.1.4) : `cosign verify-attestation --new-bundle-format --key lien.pub --type https://supply-chain.example/lien-openpgp/v1` sur `SIGNE`, puis les retenues :
  - une seule attestation de lien ;
  - sujet égal au digest de `SIGNE` ;
  - `predicate.unsigned.manifest` égal à `IMAGE`.
- **Verdict** : le Job réussit si ec, horodatage, VSA, scan et lien réussissent.
- **Ce que la porte ne peut pas faire** : recalculer B1, qui demande de lire l'en-tête rpm, impossible en `sh` et cosign. Elle s'en remet au signataire du lien. Le recalcul indépendant reste celui d'`o5-signes.py`, sur l'hôte.
- **Sous-voies** :
  - **P1** : paquets seulement (rpm et deb), le dépôt non signé étant jugé par ec.
  - **P2** : dépôts aussi (`depot-rpm`, `depot-apt`). Ils n'ont pas de manifeste non signé dans `builds/**`. Il faut une règle neuve : le champ `covers` de l'attestation ne nomme que des paquets admis par P1.
  - **PH** : horodatage des attestations de lien. Le doc 02 (§5) exige un bundle horodaté pour chaque attestation jugée. Sans PH, P1 et P2 portent cette réserve écrite.
- **Fichiers partagés touchés** (08, à passer par `A-REPORTER.md`) : `porte-job.yaml` (conteneur et entrée `SIGNE`), la ConfigMap `porte` (`lien.sh`, `lien.pub`) par `cm_porte`, et `politique.sh porte` (paramètre `SIGNE`).
- **Accords** : point 5 des « Accords à demander » du README (modification de la porte). Aucun Secret neuf, aucune écriture dans Zot, aucune NetworkPolicy neuve : la porte lit déjà Zot en anonyme.
- **Estimation, non mesurée** :
  - P1 : 1 j (script et banc hors cluster comme pour `vsa.sh`, puis Job réel sur les deux paquets, témoins compris) ;
  - P2 : + 0,5 j ;
  - PH : + 1 j (le job d'horodatage de la 08 ne vise que `builds/**`).
  - Confiance moyenne : le modèle VSA existe et a été mesuré, mais la 05 et la 06 ont dépassé leurs estimations.

### T. Tâche signée dans la pipeline

- La signature OpenPGP se ferait dans une tâche Tekton signée. Chains signerait la provenance des produits signés, et la porte les jugerait comme n'importe quel artefact de `builds/**`.
- **Contraire à D2 (a)** : la clé privée entrerait dans le cluster, Secret monté, soit D2 (b). Il faudrait donc rouvrir une décision.
- **À faire en plus** : deux images de signature construites par la plateforme (point 3 des accords), deux tâches signées et la liste revue, NetworkPolicy, pods d'essai sous Kata, puis la porte (règles `trusted_task` pour les tâches neuves).
- **Estimation, non mesurée** : au moins 3 j, confiance faible. La 05 et la 06 ont dépassé leurs estimations sur des tâches neuves de même nature.

### N. Pas d'O6

- La brique se clôt sur O5 : seuil atteint sur l'hôte, réserve écrite (« la porte ne juge pas le lien »). O6 passe au backlog.

## Mesure préalable utile au chiffrage (O6-M0)

Avant la décision, une seule mesure : **la porte actuelle, telle quelle, sur des copies des quatre objets de `signes/**`**.
- ec sur l'hôte, d'empreinte égale à celle de l'image de la porte (`895c6f7e…`, comme en R5).
- Politique de la porte en chemins locaux.
- Zot jetable dans un espace de noms réseau vide (`unshare -rn`, sans sudo, essayé le 19/11).
- Lecture anonyme du Zot du PoC, clés publiques archivées : ni secret `lien`, ni redirection de port, ni écriture dans le Zot du PoC.

Elle dit si P peut s'appuyer sur ec avec la clé `lien`, ou s'il faut un conteneur `sh` comme pour la VSA. Script : [`o6-porte-banc.sh`](../o6-porte-banc.sh) ; prédictions : [`o6-porte-banc-predictions.md`](o6-porte-banc-predictions.md), commitées avant le lancement.

## Question au propriétaire (après O6-M0)

Une seule : **P1, T ou N ?** Puis, si P1 : P2 et PH, une question à la fois.
