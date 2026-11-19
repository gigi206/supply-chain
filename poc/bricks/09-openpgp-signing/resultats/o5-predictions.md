# Brique 09, O5 à sec : prédictions du banc hôte de l'attestation de lien

Écrites le 19/11/2026 à 18:54:08 UTC, avant tout lancement de `banc`.

**Ce que le banc est.** O5 réel demande trois accords qui ne sont pas donnés : la clé Transit `lien` d'OpenBao, un jeton OpenBao, un accès en lecture à Zot. Ce banc ne mesure donc que ce qui ne dépend pas d'eux, sur l'hôte, sans réseau et sans installation (script [`o5.sh`](../o5.sh), contrôle [`o5-lien.py`](../o5-lien.py)) :
- **forme du prédicat**, promise par le README : type `https://supply-chain.example/lien-openpgp/v1`, sur le modèle des types `https://supply-chain.example/…` déjà employés dans le dépôt. Champs : `link`, `unsigned.manifest`, `unsigned.file`, `openpgp`, `b1`, `covers`, `tools` et `chainsProvenance`. Toutes les valeurs sont relues dans des journaux archivés :
  - `m4c-comparaison.log` (05) et `s4d-pipeline.log` (06) ;
  - `o2-cle.log`, `o3-signer.log` et `o4-signer.log` (09) ;
- **quatre énoncés in-toto** signés par `cosign attest-blob`, sur les produits gardés d'O3 et d'O4, lus sans jamais être re-signés :
  - le rpm signé, avec un lien `rpm-b1` ;
  - le deb, avec un lien `identity` ;
  - `repomd.xml` et `InRelease`, avec un lien `repository` ;
- **vérification par cosign**, avec `verify-blob-attestation`, puis par un **contrôle indépendant**. Ce code est neuf, sur l'hôte, sans rpm ni gpg, et ne passe ni par `o3-interne.sh` ni par les racines. Il relit :
  - le sujet, égal au fichier en main ;
  - le lien vers les valeurs archivées ;
  - l'empreinte v4 de la clé, recalculée depuis `cle-publique.asc` ;
  - **B1**, recalculé par lecture du lead et des en-têtes ;
  - les chaînes `repomd.xml` → repodata → `primary` → rpm, et `Release` → index → `Packages` → deb ;
- **témoins de refus** du protocole.

**Ce qu'il ne mesure pas** :
- la signature par la clé Transit `lien` (cosign l'adresserait par `hashivault://`, présent dans son aide) ;
- le referrer dans Zot ;
- un sujet de type manifeste OCI : ici, le sujet est un fichier ;
- la provenance de Chains du manifeste non signé : aucune enveloppe n'est archivée dans les `resultats/` des briques, et Zot n'est pas lu. `chainsProvenance` le dit dans chaque prédicat.

**Clés.** Deux clés cosign **jetables** (`lien` et `autre`), sans mot de passe : la variable d'environnement est vide et passe par `env`, jamais en argument. Elles sont créées dans `~/.cache/supply-chain-poc/09/o5/banc/cles/`, hors du dépôt, jamais affichées, et sont effacées avec le dossier du banc après archivage.

**Hors ligne.** cosign tourne dans un espace de noms réseau vide (`unshare -n`), avec un environnement vidé et un `HOME` jetable : un drapeau mal compris échoue au lieu de publier.

## `prealables` : lecture locale, avant ces prédictions

Le premier passage, de 18:53:07 à 18:53:08 UTC, a donné le code 1 ([journal](o5-prealables-premier-passage.log)). La cause est un défaut de mon motif : `o3-signer.log` a deux lignes `outils :`, une pour la signature et une pour la vérification. Le motif est restreint à la ligne qui porte `rpm-sign`.

Le second passage, à 18:53:19 UTC, donne le code 0 ([journal](o5-prealables.log)) :
- cosign 3.1.4 (`0e48502c…`) est égal à `mise.lock` (`424e2c97…`) ;
- les drapeaux `--new-bundle-format`, `--use-signing-config=false`, `--tlog-upload=false` et `--insecure-ignore-tlog` sont acceptés, mais **cosign les déclare dépréciés**. Pour `--use-signing-config`, il écrit : « TUF will continue to provide a signing config by default if one is not provided manually » ;
- les 16 valeurs archivées sont trouvées, chacune une seule fois. Les fichiers gardés d'O3 et d'O4 leur sont égaux, y compris `cle-publique.asc` ;
- l'empreinte v4 recalculée sans gpg est égale à `29BA1C48…BCF03A86` ;
- aucun en-tête de clé privée dans `o3/signer` ni `o4/signer`.

## Prédictions de `banc`

| N° | Prédiction | Confiance |
|---|---|---|
| G1 | `generate-key-pair` crée les clés `lien` et `autre` sans réseau : code 0 | moyenne-haute : jamais lancé hors ligne dans ce dépôt |
| G2 | La clé privée cosign porte une ligne « BEGIN ENCRYPTED SIGSTORE PRIVATE KEY », et 0 ligne du motif de `garde-cle-privee.sh` (bloc OpenPGP privé seulement). La garde ne couvre donc pas une clé cosign. Écart confirmé, s'il se mesure | haute |
| A1 | `attest-blob` des quatre énoncés, sans réseau, avec `--use-signing-config=false --tlog-upload=false` : code 0 | moyenne : drapeaux dépréciés ; `attest-blob` jamais lancé hors ligne dans ce dépôt (la 08 lançait `attest` vers Zot) |
| V1 | `verify-blob-attestation --key --insecure-ignore-tlog` accepte les quatre bundles sans réseau : « Verified OK » | moyenne : cosign pourrait chercher une racine TUF même avec une clé |
| C1 | Le contrôle indépendant accepte les quatre énoncés | haute pour le rpm et le deb ; moyenne-haute pour les dépôts (lecture de `repomd.xml` et de `Release` jamais faite par ce code) |
| C2 | B1 recalculé sans rpm : en-tête principal à l'octet 4504 dans les deux rpm (8 et 7 entrées de signature), lead égal, octets égaux ensuite | haute : mêmes valeurs qu'O3, par un autre code |
| C3 | Chaînes des dépôts : `repomd.xml` → toutes les entrées sha256 de repodata → `primary.xml.gz` → rpm `9f71d578…` ; `Release` → 2 index (`Packages`, `Packages.gz`) → `Packages` → deb `f66bbeb2…` | moyenne-haute |
| F1 | Bundle au format v0.3 (`application/vnd.dev.sigstore.bundle.v0.3+json`), avec `dsseEnvelope` et `verificationMaterial` | moyenne : version du format non lue |
| T1 | **Clé étrangère** (énoncé du rpm signé par `autre`) : cosign refuse avec `lien.pub`, code non nul, motif contenant « signature » ou « verif » ; un refus réseau ou TUF compte KO | haute pour le refus ; moyenne pour le libellé |
| T2 | **Lien vers un autre digest** (énoncé signé par `lien`, prédicat faux : manifeste ou fichier du deb à la place de ceux du rpm) : cosign **accepte**, car il ne lit pas le prédicat ; le contrôle refuse, motifs « lien : manifeste non signé » et « lien : fichier non signé » | haute |
| T3 | **rpm à charge altérée** (dernier octet inversé, énoncé valide signé par `lien`, sujet = rpm altéré) : cosign **accepte** ; seul le contrôle refuse, motif « B1 : octets différents » | haute |
| T4 | Énoncé du rpm signé présenté avec le rpm altéré : cosign refuse, motif contenant « digest », « subject » ou « match » ; le contrôle refuse, motif « sujet » | moyenne-haute pour cosign ; haute pour le contrôle |
| K | Aucun en-tête de clé privée dans les bundles, les prédicats ni `resultats/` ; aucune ligne de bloc armuré dans le journal ; aucune ligne KO ; code 0 | haute |

**Lecture attendue.** cosign seul ne suffit pas à vérifier un lien : il prouve qui a signé l'énoncé et sur quel fichier, pas que le prédicat dit vrai (T2, T3). Le contrôle indépendant, lui, ne vérifie pas la signature (T1). O5 réel doit donc faire les deux, comme le protocole l'écrit (« vérification par cosign et par un contrôle indépendant de B1 »).

**Suite pour O5 réel**, non mesurée ici : cosign recommande un fichier `--signing-config` sans journal de transparence plutôt que les drapeaux dépréciés. À relire avant O5 réel.

## Note datée du 19/11/2026, 18:54:55 UTC : premier passage de `banc` (18:54:24 à 18:54:27 UTC, code 1), correction avant relance

Le journal est gardé : [o5-banc-premier-passage.log](o5-banc-premier-passage.log).

**Une seule cause pour les 8 KO.** Le contrôle indépendant exigeait `_type` = `https://in-toto.io/Statement/v1`, mais `attest-blob` de cosign 3.1.4 écrit `https://in-toto.io/Statement/v0.1`. Je n'avais pas lu cette valeur, et aucune prédiction ne la portait. Le contrôle s'arrête à la forme : C1, C2, C3 et le volet « contrôle » de T2, T3 et T4 **ne sont pas mesurés** par ce passage.

**Mesuré et tenu dans ce passage :**
- **G1** : les deux clés sont créées sans réseau.
- **G2** : chaque clé privée porte 1 ligne « ENCRYPTED SIGSTORE PRIVATE KEY » et 0 ligne du motif de `garde-cle-privee.sh`. L'écart est confirmé : la garde ne voit pas une clé cosign.
- **A1** : les quatre `attest-blob` rendent le code 0.
- **V1** : les quatre bundles donnent « Verified OK ».
- **F1** : le bundle est `application/vnd.dev.sigstore.bundle.v0.3+json`, et `verificationMaterial` ne porte que `publicKey`.
- **T1** : cosign refuse, code 1, avec « accepted signatures do not match threshold, Found: 0, Expected 1 ».
- **T2 et T3, côté cosign** : « Verified OK », comme prédit.
- **T4, côté cosign** : refus, code 1, avec « provided artifact digests do not match digests in statement ».
- **K** est tenu.

**Correction.** `o5-lien.py` accepte exactement `Statement/v0.1`, la valeur mesurée ; tout autre `_type` reste refusé. Les prédictions ne changent pas. Le dossier du banc, avec les clés jetables de ce passage, est effacé avant la relance, puisque `banc` refuse un dossier existant.

## Note datée du 19/11/2026, 18:56:05 UTC : `banc` relancé (18:55:07 à 18:55:10 UTC, code 0), toutes les prédictions tenues

Journal : [o5-banc.log](o5-banc.log), avec `o5-lien.py` corrigé (`3230ff72…`) et de nouvelles clés jetables.

**Tenues :**
- **G1, G2, A1 et V1**, comme au premier passage. La garde ne voit pas une clé cosign, et `tools/secrets-depot.sh` n'a aucun motif `PRIVATE` (lu au dépôt) : aucun des deux contrôles d'avant commit ne refuserait une clé privée cosign.
- **F1** : le bundle est en v0.3, avec `dsseEnvelope`, `mediaType` et `verificationMaterial` (`publicKey` seule).
- **C1** : le contrôle indépendant accepte les quatre énoncés.
- **C2** : B1 est recalculé sans rpm. L'en-tête principal est à l'octet 4504 dans les deux rpm (8 et 7 entrées de signature), le lead est égal, et les 2 168 872 octets qui suivent sont égaux.
- **C3** :
  - côté rpm, `repomd.xml` → 6 fichiers de repodata → `primary.xml.gz` → rpm `9f71d578…`, avec 8 fichiers couverts ;
  - côté apt, `Release` → 2 index → `Packages` → deb `f66bbeb2…`, avec 5 fichiers couverts.
- **T1** : refus de cosign, motif « accepted signatures do not match threshold, Found: 0, Expected 1 ».
- **T2** : cosign accepte les deux prédicats faux ; le contrôle les refuse, sur « lien : manifeste non signé » puis « lien : fichier non signé ».
- **T3** : cosign accepte l'énoncé du rpm altéré ; le contrôle le refuse sur « B1 : octets différents », avec un premier écart à 2 168 871 octets du début de l'en-tête principal, soit le dernier octet.
- **T4** : cosign refuse (« provided artifact digests do not match digests in statement »), et le contrôle refuse sur « sujet ».
- **K** : aucun en-tête de clé privée hors de `cles/`, aucune ligne de bloc armuré dans le journal, aucune ligne KO.

**Constats.**
- **cosign et le contrôle sont tous deux nécessaires.** cosign ne lit pas le prédicat : T2 et T3 passent chez lui. Le contrôle, lui, ne vérifie pas la signature : T1 passerait chez lui.
- **Le nom du sujet est seulement le nom de base du fichier** (`repomd.xml`, `InRelease`, `rpm-altere.rpm`) : il ne porte ni chemin ni dépôt. Seul le sha256 lie le sujet.
- **Les énoncés écrits par `attest-blob` sont `in-toto.io/Statement/v0.1`**, pas v1.

**Archivés :**
- les quatre énoncés, sans signature ni clé : [rpm](o5-enonce-rpm.json), [deb](o5-enonce-deb.json), [dépôt rpm](o5-enonce-depot-rpm.json) et [dépôt apt](o5-enonce-depot-apt.json) ;
- le prédicat du rpm : [o5-predicat-rpm.json](o5-predicat-rpm.json).

Le dossier `~/.cache/supply-chain-poc/09/o5/banc`, clés jetables comprises, est effacé après le commit de cette note.

**Portée.** Ce banc tient la forme du prédicat, la double vérification et les trois refus du protocole, sur l'hôte et avec des clés jetables. Il ne tient pas O5 : il manque la signature par la clé Transit `lien`, le referrer dans Zot, le sujet de type manifeste et la vérification préalable de la provenance de Chains.

## Correction datée du 19/11/2026, 18:58:46 UTC, après relecture du conseiller : trois réserves sur la note précédente

1. **Les motifs de T1 et de T4 ne discriminent pas.**
   - Les deux refus de cosign commencent par « failed to verify signature » : le motif de T1 (`signature|verif`) attraperait aussi T4.
   - « do not match threshold » contient « match » : le motif de T4 (`digest|subject|match`) attraperait aussi T1.
   - Les deux refus restent établis par les messages cités dans le journal : seuil de signatures (0 sur 1) pour T1, digest du sujet pour T4. Les motifs, eux, ne les distinguent pas. C'est un écart de même nature que le motif SHA1 d'O4.
2. **« cosign est nécessaire » vaut par construction, pas par mesure.** Le contrôle indépendant n'a jamais tourné sur le bundle de T1. Qu'il l'aurait accepté se déduit de son code, qui ne lit pas la signature ; ce n'est pas mesuré. Seul l'autre sens est mesuré : le contrôle est nécessaire, par T2 et T3.
3. **Le lien manifeste ↔ fichier est relu, pas recalculé.**
   - Le prédicat et le contrôle lisent `07b7bd6f…` / `864d55f4…` et `60f25f5c…` / `f66bbeb2…` dans les mêmes journaux archivés (`m4c-comparaison.log`, `s4d-pipeline.log`), par la même fonction.
   - « Égal à la valeur archivée » prouve que l'énoncé dit ce que les journaux disent. Il ne prouve pas que le manifeste contient ce fichier : le banc ne lit aucune couche OCI. Cette preuve reste à O5 réel, avec la lecture de Zot. Elle s'ajoute à la portée écrite plus haut.
