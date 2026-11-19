# Brique 09, O5 réel : publication dans `signes/**` et attestations de lien, prédictions

Écrites le 19/11/2026 à 20:47:12 UTC, avant tout lancement. Scripts : [`o5-signes.sh`](../o5-signes.sh) `747853a9…` et [`o5-signes.py`](../o5-signes.py) `329c60ea…`.

**Accords.**
- Écritures dans Zot avec un compte dédié : « Oui, prépare-le ».
- Espace : « Oui, signes/** ».
- Clé Transit `lien` et accès borné : « Oui », « Oui ».
- Redirection de port vers OpenBao : « Ok ».

Les objets publiés sont ceux du §3 de la [carte des écritures](o5-ecritures-carte.md). La copie du manifeste deb vient de la note du 20:28:37 UTC (D5).

**Ce qui est définitif.** `poc-lien` ne peut rien supprimer. Tout objet et tout referrer écrit dans `signes/**` reste dans Zot. D'où deux règles :
- les inconnues de `cosign attest` sont mesurées d'abord avec une clé jetable, dans `signes/essai-09-*` (`essai_attest`) ;
- la clé `lien` ne signe rien de faux, et rien en double : `attester` refuse si une attestation de lien est déjà présente.

## Étapes, dans cet ordre

| Étape | Écrit dans Zot | Secret lu par le script | Fait |
|---|---|---|---|
| `construire` | non (hors réseau) | aucun | trois layouts OCI déterministes : rpm signé, dépôt rpm, dépôt apt |
| `essai_attest` | `signes/essai-09-attest`, `-autre`, `-altere` | configuration de `poc-lien` | clé cosign jetable : relevés de `cosign attest` sous `poc-lien`, témoins faux |
| `publier` | `signes/sample-app-rpm`, `-deb`, `depot-rpm`, `depot-apt` | configuration de `poc-lien` | poussée par digest, relue en anonyme |
| `attester` | referrers des quatre objets | secret `lien`, configuration de `poc-lien` | Chains revérifiée, prédicats contrôlés avant signature, `cosign attest --key hashivault://lien` par la redirection |
| `verifier` | non (anonyme) | aucun | `cosign verify-attestation` avec la clé archivée, puis contrôle indépendant sur les octets tirés de Zot |

**Garde horaire.** `essai_attest`, `publier` et `attester` refusent d'écrire entre 23:30 et 08:00 UTC : la mesure de M1b part à 00:01 UTC et lit Zot.

**Contrôles de fin d'étape**, faits avant tout affichage :
- K3 : aucun bloc privé dans le journal ;
- K5 : la valeur du secret `lien` n'est ni dans le journal ni dans le dossier de l'étape ;
- K6 : ni le mot de passe, ni le hash, ni la chaîne d'authentification de `poc-lien`, au même endroit.

## Contrôle indépendant (`o5-signes.py controle`)

Il juge une sortie de `cosign verify-attestation`, déjà vérifiée par cosign. Les attendus viennent des journaux archivés. Il exige :
- une seule enveloppe du type lien ;
- un seul sujet, égal au manifeste publié ;
- l'origine (dépôt, manifeste et fichier non signés), l'empreinte OpenPGP et le sha256 de la clé publique égaux aux valeurs archivées ;
- l'image non signée, tirée de `builds/**`, relue : un seul fichier, de sha256 archivé ;
- l'objet publié, tiré de `signes/**`, relu :
  - **rpm** : un seul membre, le rpm signé `9f71d578…` ; B1 recalculé sur les octets tirés des deux images ;
  - **deb** : manifeste publié = manifeste non signé (identité) ;
  - **dépôts** : chaîne recalculée sur les membres (repomd → repodata → primary → rpm ; texte signé d'InRelease = Release → index → Packages → deb), aucun membre hors de la chaîne, liste couverte = membres lus.

**Balayage des membres** que la brique écrit, c'est-à-dire tout sauf les paquets (décompressés s'il le faut) : aucun bloc privé, aucune adresse hors des domaines réservés `.invalid` et `.example`.
- Mesuré à sec : le rpm porte deux adresses fictives `…@supply-chain.invalid`, déjà publiées dans `builds/**`.
- Les octets compressés du deb donnent un faux motif d'adresse. Les paquets ne sont donc pas balayés : ils sont jugés par leur sha256.

## Banc

[o5-signes-banc.sh](../o5-signes-banc.sh) : **28 OK, 0 KO** au premier passage, de 20:46:20 à 20:46:32 UTC ([journal](o5-signes-banc.log)).

**Ce qu'il simule** :
- Zot, par des dossiers de layouts et de referrers ;
- `oras`, `curl` et `cosign` (attest et vérifications) ;
- la redirection (vrai port d'écoute) ;
- les images non signées, construites localement, dont les digests remplacent les valeurs archivées par `O5_SIGNES_ATTENDUS` (variable refusée hors banc).

**Cas couverts** :
- les cinq étapes nominales ;
- publication relancée : objets déjà présents, rien n'est repoussé ;
- garde horaire à 23:45 et à 07:59 UTC ;
- `attester` relancée : refus avant signature ;
- layout corrompu après `construire` ;
- provenance de Chains refusée ;
- redirection en échec ;
- secret dans une erreur du client : journal vidé par K5 ;
- variable de banc hors banc.

**Le banc ne prouve pas** :
- la vraie signature ni la vraie poussée de `cosign attest` sous `poc-lien` : c'est `essai_attest` qui les mesure ;
- la forme réelle de la sortie de `verify-attestation --new-bundle-format` ;
- l'API referrers réelle de Zot ;
- la condition CEL appliquée à un referrer poussé par cosign.

## Prédictions

| N° | Prédiction | Confiance |
|---|---|---|
| CO1 | `construire` : code 0 ; digests rpm `sha256:fa5b175786dc…`, depot-rpm `sha256:ed666ab80dd1…`, depot-apt `sha256:90909a869321…` (ceux du banc, mêmes sources et même code) ; seconde construction égale | haute |
| CO2 | Chaînes complètes, aucun membre de trop ; adresses fictives : 0 (rpm, paquet non balayé), 4 (depot-rpm), 2 (depot-apt) | haute : mesuré à sec |
| EA1 | `essai_attest` : provenance de Chains revérifiée, 4 enveloppes (rpm) et 8 (deb), comme `lecture` ; trois poussées par `poc-lien` acceptées | haute |
| EA2 | `cosign attest` (clé jetable) sous `poc-lien` : code 0 pour les trois ; un referrer `application/vnd.dev.sigstore.bundle.v0.3+json` annoté du type lien ; aucun tag | moyenne-haute : t8_v3 (08) a mesuré 0 tag avec cosign 3.1.4, mais sous un autre compte, sans condition CEL ; D4 a mesuré un referrer accepté pour `poc-lien`, mais poussé par `oras attach` |
| EA3 | Relevé, sans pari ferme : une ligne par attestation ; `_type` `https://in-toto.io/Statement/v0.1` (valeur d'`attest-blob`) ; sujet = `192.168.161.13:5000/signes/essai-09-attest` avec un digest sha256. Le contrôle admet une enveloppe DSSE ou un bundle par ligne, et `_type` v0.1 ou v1 | moyenne |
| EA4 | Contrôle sur les octets tirés de Zot : prédicat réel ACCEPTÉ ; témoin « autre manifeste » refusé (manifeste non signé) ; témoin « rpm altéré » refusé (rpm signé) ; la clé `lien` refuse l'attestation jetable | haute |
| PU1 | `publier` : quatre poussées acceptées, digests = CO1 et `sha256:60f25f5c…` pour le deb ; relues en anonyme ; aucun tag | haute |
| AT1 | `attester` : quatre objets présents sans referrer de lien ; Chains revérifiée (4 et 8) ; quatre prédicats ACCEPTÉ avant signature | haute |
| AT2 | Quatre `cosign attest --key hashivault://lien` à code 0, puis une attestation de lien par objet ; redirection fermée | moyenne-haute : signature `hashivault://lien` mesurée (`o5-cosign.sh essai`) ; poussée mesurée d'abord par EA2 |
| VE1 | `verifier` : une enveloppe par objet avec la clé archivée ; contrôle ACCEPTÉ ×4 (B1 recalculé, identité du deb, deux chaînes recalculées) ; quatre énoncés archivés | haute |
| VE2 | Clé jetable refusée ×4 ; aucun tag ; une attestation de lien par objet | haute |
| K | K3, K5 et K6 tenus à chaque étape ; aucune ligne KO | haute |

**Si EA2 ou EA3 échoue**, rien n'est signé par `lien` : la suite attend une note datée et, s'il le faut, une décision.

**Objets laissés dans Zot après `essai_attest`** :
- `signes/essai-09-attest` et `signes/essai-09-autre`, au digest du rpm signé, avec leur referrer jetable ;
- `signes/essai-09-altere`, au digest du rpm altéré, avec son referrer jetable.

## Note datée du 19/11/2026, 20:48:15 UTC : `construire` passée (20:48:09 UTC), CO1 et CO2 tenues

Journal : [o5-signes-construire.log](o5-signes-construire.log). Aucune ligne KO. Les digests sont ceux du banc : rpm `sha256:fa5b175786dc…`, depot-rpm `sha256:ed666ab80dd1…`, depot-apt `sha256:90909a869321…`. La seconde construction donne les mêmes. Adresses fictives : 0, 4 et 2. Le dossier `09/o5-signes/construire` est gardé pour la suite ; la seconde construction est effacée.
