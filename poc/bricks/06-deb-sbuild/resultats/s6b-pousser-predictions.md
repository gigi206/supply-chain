# S6b : VSA du deb dans Zot, prédictions (préparées à sec le 12/11/2026 à partir de 11:58:09 UTC, après « continue »)

**Rien n'est lancé.** Les deux étapes viennent **après S5b** (ordre c, décision du 12/11/2026) et après `vsa`. Elles reprennent `pousser_vsa` et `lire_vsa` de la brique 10 ([`replay.sh`](../../10-independent-replay/replay.sh), journaux `r5-pousser_vsa.log` et `r5-lire_vsa.log`).

```
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh pousser_vsa
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh lire_vsa
```

## Ce que font les étapes

- **`pousser_vsa`** : sur l'hôte, compte `poc-replay` (D5 : écriture par digest seulement sous `builds/**`). **Un accord du propriétaire par push.**
  - Refus, sans rien pousser :
    - sans `resultats/s6b-vsa.bundle.json` et `s6b-vsa-enonce.json` (étape `vsa`) ;
    - si la copie de la CA du PoC (`~/.cache/supply-chain-poc/10/ca-poc.crt`) diffère de celle de la 08 (`cmp`, certificats publics, non affichés). La 08 ne recrée la CA que si sa clé manque (`stockage.sh`, ligne 46) ;
    - sans le mot de passe de `poc-replay` (`test -s`, jamais lu à l'écran) ;
    - si le bundle ne se vérifie pas sur l'hôte par la clé publique du domaine (`10-independent-replay/resultats/vsa-cle-publique.pem`) ;
    - si l'énoncé du bundle diffère de `s6b-vsa-enonce.json`, si son sujet n'est pas `039949f9`, s'il n'est pas `PASSED` ou s'il ne porte pas `["POC_REPLAY_BIT_IDENTIQUE"]` seul ;
    - **si le layout du deb `039949f9` n'est pas dans Zot**. S5b remet Zot à zéro : le sujet n'y revient que si le build du deb le reproduit.
  - Ensuite : manifeste fait main (sujet : le layout du deb), poussé par digest dans **`builds/vsa/sample-app-deb`**, le dépôt que dérive la porte (`politique/porte/vsa.sh`). Le manifeste est archivé dans `resultats/s6b-vsa-manifeste.json`.
  - Relecture anonyme : referrers et étiquettes de `builds/vsa/sample-app-deb` ; referrers et étiquettes de `builds/sample-app-deb`, comparés à ceux d'avant le push.
- **`lire_vsa`** : lecture anonyme, `cosign` sous `strace -e trace=connect`. Quatre essais : la VSA par `COSIGN_REPOSITORY`, avec la clé du domaine puis avec celle de Chains ; la provenance du tag `.att`, avec la clé du domaine puis avec celle de Chains (témoin).

## Prédictions

**`pousser_vsa`**
- **P1.** `verify-blob-attestation` sur l'hôte : code 0, `Verified OK`, aucune connexion (0 `connect()`), comme dans la 10.
- **P2.** `OK` sur l'énoncé : sujet `sc-stockage.poc.test:5000/builds/sample-app-deb@sha256:039949f947f2…`, `PASSED`, `['POC_REPLAY_BIT_IDENTIQUE']`, `timeVerified` égal au `fin_deb` de `rebuild`.
- **P3.** Sujet lu dans Zot : `application/vnd.oci.image.manifest.v1+json` (type écrit par `deb/construire-deb.yaml`, ligne 135), digest `039949f9…`. Confiance moyenne : elle dépend de S5b.
- **P4.** Push : « blob du bundle poussé », « config vide poussée », puis le digest du manifeste. Confiance haute pour les droits : `poc-replay` a déjà poussé de la même façon dans `builds/vsa/sample-app`.
- **P5.** Relecture : un seul referrer du deb dans `builds/vsa/sample-app-deb`, de type `application/vnd.dev.sigstore.bundle.v0.3+json`, au digest poussé ; aucune étiquette ; `OK` sur les referrers et les étiquettes de `builds/sample-app-deb`, inchangés.

**`lire_vsa`**
- **L1.** VSA par `COSIGN_REPOSITORY`, clé du domaine : acceptée, une VSA vérifiée.
- **L2.** VSA par `COSIGN_REPOSITORY`, clé de Chains : refusée (« accepted signatures do not match threshold »).
- **L3.** Provenance du tag `.att`, clé du domaine : refusée.
- **L4.** Témoin : provenance du tag `.att`, clé de Chains : acceptée. Le nombre d'énoncés vérifiés dépend des builds du deb après S5b.
- **L5.** Chaque essai : aucune connexion hors de Zot.

Confiance moyenne pour L1 à L4 : la 10 a fait ces lectures sur une image, jamais sur le layout d'un deb. `cosign` ne lit pourtant que le manifeste et ses referrers, et le manifeste du deb est un manifeste d'image OCI.

## Limites

- **`inputAttestations` désignera un bundle horodaté effacé par S5b** (`horodatage/bundles@sha256:856a4270…`). La politique le dit déjà, section « Limites ». La VSA reste vérifiable par sa clé ; la provenance qu'elle juge, elle, ne sera plus dans Zot.
- **La porte sur le deb n'est pas préparée ici.** Elle vient après S5b, avec le CronJob de scan du deb.

## Note datée du 12/11/2026 (rédigée entre le commit 9521f0c, 12:02:59 UTC, et 12:04:45 UTC, après relecture du conseiller), avant tout lancement

**Codes de sortie corrigés après `9521f0c`.** Un `KO` de `connexions`, ou des referrers ou étiquettes de `builds/sample-app-deb` changés après le push, laissaient le code à 0. `connexions` lève maintenant le drapeau `ko` de l'étape qui l'appelle, et `pousser_vsa` finit, comme `lire_vsa`, par une ligne `bilan` et le code 1 sur tout `KO`. Prédiction ajoutée : **P6.** `bilan : tout OK`, code 0 ; de même pour `lire_vsa`.

## Note datée de 2026-11-14T20:30:05Z : état après S5b, avant le lancement (rien n'est réécrit)

Relevés sans contact avec le cluster, sauf une ouverture TCP vers Zot (`192.168.161.13:5000`, joignable) :
- **S5b terminé** (`2cec0df`) : le deb `039949f9` a été reproduit au bit près (C8 tenue). **P3 passe en confiance haute.**
- **CA** : `~/.cache/supply-chain-poc/10/ca-poc.crt` et `08/pki/ca-poc.crt` identiques (`cmp`) ; le refus sur la CA n'est pas attendu.
- **poc-replay** : mot de passe présent (`test -s`) ; le push de VSA de la 10 a réussi après S5b
  (`08-trust-plane/resultats/rejeu-s5b-plateforme-ctl.log`, 12:47:44 UTC, manifeste `69a2b103…`) : droits et mot de passe valides.
- **Clé de Chains changée par S5b** (`688af09`, `08-trust-plane/resultats/chains-cle-publique.pem`). `lire_vsa` lit la clé actuelle :
  L2 et L4 portent sur elle. La provenance du deb dans Zot est celle des builds d'après S5b (C9 : 12 enveloppes de Chains sur le
  deb). **L4 précisée** : acceptée, au moins une provenance vérifiée ; le nombre n'est pas prédit (confiance faible).
- **Nouvelle limite** : la VSA a été émise le 12/11 sur une provenance signée par l'ancienne clé de Chains. Elle reste vérifiable
  par la clé du domaine, et son sujet (le digest) est inchangé ; la provenance qu'elle juge n'est plus dans Zot (s'ajoute à la
  limite sur `inputAttestations`).
- **P7.** Avant le push, aucun referrer du deb dans `builds/vsa/sample-app-deb` (aucune VSA du deb poussée depuis S5b ; la porte
  du deb refusait la VSA, C9). Les referrers de `builds/sample-app-deb` sont relevés avant le push et inchangés après (P5).

Ordre : `pousser_vsa`, puis `lire_vsa`, chacun sur un accord nommé. Le push écrit dans le Zot du PoC (pas une action publique).

## Résultat de `pousser_vsa` (note de 2026-11-14T20:31:22Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance s6b.sh pousser_vsa (push de la VSA du deb dans Zot) ? ». De 20:30:50 à 20:30:55 UTC, code 0
([journal](s6b-pousser_vsa.log), [manifeste](s6b-vsa-manifeste.json)).
- **P1 tenue** : `Verified OK`, 0 `connect()`.
- **P2 tenue** : énoncé identique, sujet `039949f947f2…`, `PASSED`, `['POC_REPLAY_BIT_IDENTIQUE']`, `timeVerified`
  2026-11-12T21:06:14Z, égal au `fin_deb` de `s6b-rebuild.log`.
- **P3 tenue** : sujet `application/vnd.oci.image.manifest.v1+json`, `039949f9…`, 400 octets.
- **P4 tenue** : bundle et config poussés, manifeste `sha256:bd7c77ec312ed48a9adf8c3e4f4c32b98f71b1980c032b4604a26d37156e004d`.
- **P5 tenue** : un seul referrer du deb dans `builds/vsa/sample-app-deb`, de type `application/vnd.dev.sigstore.bundle.v0.3+json`,
  au digest poussé ; aucune étiquette ; referrers (0) et étiquettes (`.att` et `.sig`) de `builds/sample-app-deb` inchangés.
- **P6 tenue** : `bilan : tout OK`, code 0.
- **P7 non mesurée directement** : l'étape ne relève pas les referrers de `builds/vsa/sample-app-deb` avant le push. Le referrer
  unique relevé après est compatible avec P7, sans la prouver (un manifeste identique déjà présent donnerait le même relevé).

## Résultat de `lire_vsa` (note de 2026-11-14T20:36:05Z ; rien n'est réécrit)
« Oui, lance-le » à « Je lance s6b.sh lire_vsa (lecture anonyme, quatre essais de clés) ? ». Lancée à 20:35:50 UTC, finie dans la
même seconde (`date -u` avant et après), code 0 ([journal](s6b-lire_vsa.log)).
- **L1 tenue** : VSA par `COSIGN_REPOSITORY`, clé du domaine : acceptée, une VSA vérifiée.
- **L2 tenue** : VSA par `COSIGN_REPOSITORY`, clé de Chains : refusée (« accepted signatures do not match threshold, Found: 0 »).
- **L3 tenue** : provenance du tag `.att`, clé du domaine : refusée (même motif, « Expected 1 »).
- **L4 tenue** (forme précisée le 14/11) : témoin, provenance du tag `.att`, clé de Chains actuelle : acceptée, **12 vérifiées**,
  autant que les enveloppes de Chains relevées sur le deb par C9 de la reprise.
- **L5 tenue** : chaque essai, un seul `connect()`, vers Zot. **P6 tenue** pour `lire_vsa` : `bilan : tout OK`, code 0.
