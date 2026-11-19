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

## Additif du 19/11/2026, écrit à 21:10:42 UTC : O6-M0 passée, deux formes possibles pour P

O6-M0 est passée (21:09:53 à 21:10:00 UTC), et ses sept prédictions sont tenues ([résultat](o6-porte-banc-predictions.md), [journal](o6-porte-banc.log)).
- **La porte actuelle refuse les quatre objets de `signes/**`**, avec la clé de Chains comme avec la clé `lien`. Elle ne peut donc pas juger un objet signé telle quelle : P garde le manifeste non signé comme `IMAGE` jugée par ec.
- **ec vérifie l'attestation de lien quand on lui donne la clé `lien`** : 1 attestation comptée, contrôles de signature réussis. Il reste cinq violations, toutes dues à l'absence de provenance de Chains.

La voie P a donc deux formes :
- **P-sh** : un conteneur `lien` sur le modèle de `vsa.sh` (cosign et `sh`). C'est la forme déjà en service pour la VSA, et la plus courte à écrire.
- **P-ec** : un second passage d'ec sur `SIGNE`, avec la clé `lien` et une politique qui n'inclut que des règles du lien, en rego sur `input.attestations`. Les règles seraient testables par `ec opa test`, comme `porte_test.rego`. Il faut une source de politique de plus dans la ConfigMap, et lire le contrôle de signature à vide déjà vu au banc C (la règle `porte.image_signature` n'aurait pas cours ici). Rien de cette forme n'est mesuré.

L'estimation de P1 ne change pas (1 j, confiance moyenne). Elle vaut pour l'une ou l'autre forme, dont le choix est laissé au moment d'écrire P1.

## Correction datée du 19/11/2026, 21:13:46 UTC : P1 rechiffré, et Kyverno borné à ce qui est lu

Relecture du conseiller. Trois points de la carte dépassaient ce que j'avais vérifié.

**1. La voie P supposait que la porte admet déjà les manifestes non signés.** Recherche dans les résultats archivés de la 05, de la 06, de la 07a et de la 10, sans rien relancer :
- **deb `builds/sample-app-deb@60f25f5c…`** : le Job complet de la porte l'admet depuis S6a de la 06 (`VERDICT|s6a-deb|true|…`, [s6a-porte.log](../../06-deb-sbuild/resultats/s6a-porte.log), 16/11/2026). ec, horodatage (8/8), VSA (1/1) et scan sont admis. Avant S6a, la porte le refusait faute de VSA et de scan (S4d3 et S5). La copie `signes/sample-app-deb` a le même digest.
- **rpm `builds/sample-app-rpm@07b7bd6f…`** : **aucun verdict de la porte n'est archivé** (aucune ligne `VERDICT` qui le nomme). La 05 garde la réserve « Porte sans tâche rpm » ([m5b-carte.md](../../05-rpm-mock/resultats/m5b-carte.md), §4). `_constructions` de `porte.rego` ne nomme que `construire-image` et `construire-deb`, et `vsa.sh` comme le contrôle de scan exigent des énoncés dans `builds/vsa/` et `builds/scan/`. Je n'ai pas vérifié s'ils existent pour ce rpm.

**P1 rechiffré** :
- **P1-deb** : 1 j, confiance moyenne, inchangé. Le manifeste jugé par ec est déjà admis par la porte complète.
- **P1-rpm** : il faut d'abord étendre la porte à la voie rpm (règle Kata pour `construire-rpm`, VSA de la 10, scan de la 07a), comme S4d2a l'a fait pour le deb. Ce travail relève de la 05, de la 10 et de la 07a, pas de la 09. **Il n'est pas chiffré ici.** Tant qu'il n'est pas fait, un contrôle du lien du rpm signé s'appuierait sur un manifeste que la porte n'a jamais admis.

**2. « Cinq violations, toutes dues à l'absence de provenance de Chains »** (additif ci-dessus) : trop fort, voir la correction datée des [prédictions](o6-porte-banc-predictions.md). Seul est mesuré que ces violations restent avec la clé `lien`.

**3. Kyverno.** J'ai lu les deux fichiers de politiques Kyverno du dépôt : [`admission.yaml`](../../08-trust-plane/politique/admission.yaml) de la 08 et [`durcissement.yaml`](../../08c-durcissement/politiques/kyverno/durcissement.yaml) de la 08c. Le second ne vise que des pods, le premier des pods et des objets Tekton. Aucune de leurs règles ne vise un rpm, un deb ou un dépôt.
- La ligne « Risques » du README (« sans attestation de lien vérifiée à l'admission, Kyverno refuserait ou laisserait passer selon la règle ») ne s'appliquerait qu'à une image de pod construite à partir du rpm signé. Il n'en existe aucune dans le PoC.
- Cette ligne et les notes d'O5 (« porte et Kyverno (O6) ») se lisent donc ainsi : O6 ne touche que la porte.

**Secret `lien`** : la voie P n'emploie que la clé publique (`lien.pub`). Le secret gardé pour O6 n'y sert pas.

**Question au propriétaire, mise à jour** : **P1-deb ou N ?** T n'est pas proposée, car elle rouvre D2 (a). P1-rpm attend l'extension de la porte à la voie rpm, hors de la 09.

## Note datée du 19/11/2026, 21:15:33 UTC : la voie deb n'a de substance qu'avec le dépôt apt ; recommandation N

**Ce que dit le lien du deb.** J'ai lu le prédicat archivé [`o5-signes-predicat-deb.json`](o5-signes-predicat-deb.json).
- `unsigned.manifest` vaut `sha256:60f25f5c…` dans `builds/sample-app-deb`.
- `signed` porte `manifestCopiedFrom` `builds/sample-app-deb`, dans `signes/sample-app-deb`, au même digest.
- Le prédicat n'a pas de champ `b1`. Le contrôle d'O5 n'y vérifie que l'identité.

Le lien du deb relie donc un objet à sa propre copie. Le paquet deb n'est pas signé en OpenPGP : sa signature est celle du dépôt (`InRelease` de `depot-apt`, D1). **P1-deb seul n'apporterait à la porte qu'une vérification de signature, rien sur la signature OpenPGP.** La forme utile est P1-deb + P2-apt, soit 1,5 j d'après les estimations de cette carte, non mesurées.

**Deux formulations corrigées** (plus fortes que la mesure) :
- « le Job complet de la porte l'admet depuis S6a » se lit « l'a admis le 16/11/2026 (S6a), mesure non refaite depuis » ;
- « la porte actuelle refuse les quatre objets » se lit « la politique de la porte *du dépôt* (`porte.rego` et `taches.yml` du commit courant, pas la ConfigMap en service) les refuse, rejouée sur l'hôte ».

**Recommandation : N.**
- Le seuil de la brique est atteint sur l'hôte. O6 est optionnel et hors estimation.
- La moitié où le lien porte de la substance (rpm, B1 recalculé) attend une extension de la porte hors de la 09.
- P touche trois fichiers partagés de la 08 et demande un accord de cluster.

L'autre option est la **voie deb** : P1-deb + P2-apt, 1,5 j estimé, contrôle du lien du deb et du dépôt apt par la porte.

**Secret `lien`** : aucune des deux options ne l'emploie (la voie P ne lit que `lien.pub`). Il expire seul le 22/11/2026, au plus tard à 19:49:36 UTC.

**Question au propriétaire** : N, ou la voie deb ?

## Décision datée du 19/11/2026, consignée à 21:26:03 UTC : « Oui », lu comme N (pas d'O6)

- **Réponse relayée par la session principale.** Le propriétaire a répondu « Oui » à ce message : « Elle recommande N, pas d'O6. L'alternative est la voie deb (P1-deb + P2-apt), estimée à 1,5 j. »
- **Lecture.** La session principale et moi lisons ce « Oui » comme une acceptation de la recommandation, N. Le mot exact du propriétaire est « Oui ». Il ne nomme pas l'option. Si le propriétaire voulait la voie deb, cette décision se corrige par une note datée.
- **Effet.**
  - O6 n'est pas fait dans la 09 : aucune règle de la porte, aucun Job, rien dans le cluster ni dans Zot.
  - La réserve reste écrite : la porte ne juge pas l'attestation de lien.
  - Le contrôle du lien par la porte attend que la porte soit étendue à la voie rpm, ce qui ne relève pas de la 09.
- **Secret `lien`.** Il ne sert plus à rien. Il expire seul le 22/11/2026, au plus tard à 19:49:36 UTC, et aucune signature `lien` n'est prévue d'ici là.
- **Clôture de la brique.** Elle reste au propriétaire (`A-REPORTER.md`, §3).
