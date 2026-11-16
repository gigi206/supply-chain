# Brique 06, révision 1.0.0-2 : étape lintian, prédictions (écrites à 2026-11-16T16:58:08Z, préparées à sec, « Oui, prépare-le ») : NON LANCÉ

Script : [`../lintian.sh`](../lintian.sh), nouveau. Cinq étapes, une par appel, **chacune sur accord nommé**, code relevé juste
après. Rien n'a été lancé, rien n'a été téléchargé, rien n'est installé au niveau système.

## Origine et décisions
- **Étape 6 de la séquence d'après S5b** : le tag lintian `missing-static-built-using-field-for-golang-package` doit disparaître
  avec la révision 1.0.0-2 (`Static-Built-Using: ${misc:Static-Built-Using}` dans `debian/control`). Décision des axes 1 et 2 de
  la 13a, du 12/11/2026.
- **Ébauche reprise** : constats et brouillon du 12/11/2026 (à partir de 22:07:30 UTC), écrits hors dépôt dans
  `~/.cache/supply-chain-poc/13a-axes12-esquisse/esquisse/lintian-predictions.md` ; ils sont repris ici. Lus alors dans lintian
  2.122.0 sur salsa, et relus par `juger` dans le paquet installé :
  - la règle (`Lintian/Check/Languages/Golang/BuiltUsing.pm`) juge la **source** : elle n'agit que si `Build-Depends` satisfait
    `golang-go | golang-any`, et sort le tag pour chaque paquet binaire d'architecture autre que `all` dont `Static-Built-Using`
    ne contient pas le littéral `${misc:Static-Built-Using}` ; l'entrée est donc le `.dsc`, pas le `.deb` ;
  - le tag est de sévérité `info`, masquée par défaut (il faut `-I`) ;
  - le code de sortie vaut 2 dès qu'un tag `E:` sort, 1 pour une erreur d'exécution : le jugement porte sur la ligne du tag.
- **Décision du propriétaire du 12/11/2026 (22:14:45 UTC), « Chroot à part »** : le chroot de build et `verrou-deb.txt` ne changent
  pas ; lintian tourne dans un chroot à part, même suite, même instantané `20261105T000000Z`, avec sa propre fermeture verrouillée.
  Inscrite hors dépôt, dans la même ébauche, et reprise ici.
- **Décisions du propriétaire du 16/11/2026** :
  - base du chroot : **racine de S1** (« Racine de S1 (Recommandé) ») ;
  - lintian n'a aucun verdict dans `docs/04-sante-projets.md` : **relevé de santé d'abord** (« Relevé de santé d'abord
    (Recommandé) »), à préparer sur accord et à faire **avant tout lancement** de ce script.

## Mesures à sec qui fondent le choix de la base (16/11/2026)
- **Racine de S1** `~/.cache/supply-chain-poc/08/travail/s1-06/racine.tar` : sha256 `f8f221ca…`, égal à
  [`s1b-racine.log`](s1b-racine.log) l. 139 (mmdebstrap sur l'instantané, 10/11/2026). 166 paquets installés, **tous égaux à
  l'index** (nom, version, architecture) ; lintian absent ; 8 nœuds de périphérique sous `./dev` (non extraits : `mknod` est
  refusé dans l'espace de noms, `/dev` de l'hôte est lié). Ses listes d'apt sont celles de l'index vérifié : InRelease
  `0584fba3…` ([`s1-prealables.log`](s1-prealables.log)), Packages `4f2c68d6…`, listé dans cet InRelease et égal à
  `Packages.xz` (`7778d3e3…`) décompressé. `sources.list` : l'instantané seul.
- **Amorce écartée** `debian:trixie-20261104-slim` (`7378260c…`, en cache) : 78 paquets, dont 7 hors de l'index, plus récents
  (`apt` et `libapt-pkg7.0` 3.0.4, `liblzma5`, `libpcre2-8-0`, `libssl3t64`, `openssl-provider-legacy`, `tzdata`).
- **Sources jugées** :
  - 1.0.0-1, témoin : `.dsc` `9050679e…` (copie hors dépôt du 12/11 ; même sha256 que
    `poc/benchmarks/obs/resultats/build-4/debian_13/sha256.txt` l. 2) ;
  - 1.0.0-2 : `.dsc` `ee2a6b8e…`, celui de `sources.sh` ([`revision-sha256sums-s1-option1.log`](revision-sha256sums-s1-option1.log)
    l. 16). **Ce n'est pas le `.dsc` de D** (`b284bd60…`, produit dans la pipeline, absent de l'hôte) : les deux ont le même orig
    (`1591a05b…`) ; leurs `.debian.tar.xz` ont « mêmes membres, tailles et dates », le groupe sans écriture dans la pipeline
    (`s4d-prealables.log` l. 55 à 58). Le tag ne lit que `debian/control` : `juger` le compare au blob de HEAD de
    `poc/packaging/debian/control`. Ce fichier n'a pas changé depuis `593cee4` (2026-11-14T21:55:57Z), avant S4c (22:18:38Z,
    [`s4c-verrou.log`](s4c-verrou.log)), qui a produit l'artefact de packaging `f0ed7a71…` dont D est construit : c'est ce lien
    qui rattache le jugement à D. Mesuré à sec : `debian/control` de 1.0.0-2 égal à
    `poc/packaging/debian/control` (`cmp`), littéral `Static-Built-Using: ${misc:Static-Built-Using}` à la l. 13 ; aucun
    `Static-Built-Using` dans celui de 1.0.0-1 ; `Build-Depends` contient `golang-go (>= 2:1.24~)` ; `Architecture: amd64`.
  - L'orig a changé entre les deux révisions (`07521c1e…` puis `1591a05b…`), déjà consigné (`revision-predictions.md`, note de
    l'option 1) : sans effet sur ce tag.
- **Fermeture estimée** (outil `lintian_fermeture.py` de l'ébauche, base = les 166 paquets de la racine, résolution simplifiée,
  première alternative) : **168 paquets, 25 695 012 octets**. Ordre de grandeur seulement : le verrou vient d'apt (`resoudre`).
  Aucun de ces 168 paquets n'a de `Pre-Depends` (lu dans Packages) : `dpkg -i` du lot entier ne bute pas sur un `Pre-Depends`
  interne non configuré.

## Commandes (racine du dépôt), dans l'ordre, chacune sur accord nommé
0. Avant tout : relevé de santé de lintian pour `docs/04`, sur accord (décision du 16/11).
1. `poc/bricks/06-deb-sbuild/lintian.sh prealables` (hors réseau).
2. `poc/bricks/06-deb-sbuild/lintian.sh resoudre` (hors réseau) ; puis **commit du verrou** `lintian/verrou-lintian.txt` et du
   journal.
3. `poc/bricks/06-deb-sbuild/lintian.sh telecharger` (réseau : snapshot.debian.org en https ; refusé si le verrou n'est pas
   commité ou a changé).
4. `poc/bricks/06-deb-sbuild/lintian.sh installer` (hors réseau).
5. `poc/bricks/06-deb-sbuild/lintian.sh juger` (hors réseau).

## Prédictions
| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| Y1 | `prealables` | Signataires d'InRelease : les trois clés épinglées ; InRelease `0584fba3…` ; Packages `4f2c68d6…` listé et égal à `Packages.xz` décompressé ; lintian `2.122.0` dans l'index ; racine `f8f221ca…`, listes et `sources.list` égaux ; 166 paquets, 0 hors index, lintian absent ; 8 nœuds de périphérique ; `.dsc` `9050679e…` et `ee2a6b8e…`, chaque fichier de leurs `Checksums-Sha256` égal ; `bilan : tout OK`, code 0 | Haute : chaque valeur mesurée à sec le 16/11, sauf gpgv (S1, 10/11) |
| Y2 | `resoudre` | `apt-get -s` code 0, aucune ligne `Remv`, aucune mise à jour ; lintian `2.122.0 all` dans le verrou ; chaque paquet du verrou dans l'index ; nombre de paquets entre 130 et 200, environ 26 Mo | Moyenne : premier apt dans la racine en espace de noms ; le nombre vient d'une résolution simplifiée |
| Y3 | `telecharger` | Chaque `.deb` égal au verrou (sha256 et taille) ; autant de fichiers que de lignes du verrou ; code 0 | Moyenne : disponibilité de snapshot.debian.org |
| Y4 | `installer` | `dpkg -i` code 0 ; tous les paquets `ii` ; installés = racine + verrou ; lintian `2.122.0` ; `dpkg --audit` vide | Moyenne : scripts de maintenance dans l'espace de noms, sans systemd, et `chroot` de l'hôte (uutils) jamais employé ici ; aucun `Pre-Depends` dans la fermeture estimée |
| Y5 | `juger` | `lintian -I` sur le `.dsc` 1.0.0-1 (témoin) : **une** ligne `I: sample-app source: missing-static-built-using-field-for-golang-package` (suite de la ligne non prédite) ; condition de validité de Y6 | Haute : règle lue, un seul paquet binaire `amd64` |
| Y6 | `juger` | `lintian -I` sur le `.dsc` 1.0.0-2 : **aucune** ligne de ce tag ; n'a de valeur que si Y5 tient | Haute : littéral mesuré dans `debian/control` |
| Y7 | `juger` | `lintian` sans `-I` sur les deux `.dsc` : aucune ligne de ce tag (témoin de la sévérité) | Haute |
| Y8 | `juger` | Règle et fichier de tag trouvés dans le lintian installé, sévérité `info` (champ `Visibility` ou `Severity`, nom non relu pour 2.122.0) ; `debian/control` de 1.0.0-2 égal au blob de HEAD ; codes de lintian 0 ou 2 ; aucune autre forme de ligne qui nomme le tag ; `bilan : tout OK` | Haute pour `debian/control` (mesuré) ; moyenne pour les codes |

Les autres tags (E, W, I) ne sont pas prédits un par un : ils sont relevés tels quels dans le journal, et chacun sera décidé à
part. Les sorties d'erreur de lintian (root projeté) sont relevées, pas prédites.

## Effets
- Écritures : `~/.cache/supply-chain-poc/06/lintian/` (racine extraite, environ 345 Mo, plus environ 26 Mo de `.deb` et
  l'installation), `lintian/verrou-lintian.txt` (par `resoudre`), journaux `resultats/lintian-<étape>.log`, `chrono.tsv`.
- Rien au niveau système, rien dans le cluster, dans Zot, ni sur `sc-stockage`. Une seule étape joint le réseau : `telecharger`.

## Cas d'échec
- Y5 non tenue (tag absent sur le témoin) : Y6 ne prouve rien ; arrêt et lecture de la règle installée.
- Y6 non tenue (tag présent sur 1.0.0-2) : écart sur l'objet de la révision ; arrêt et décision.
- Code 1 de lintian, ou KO d'une étape : arrêt au premier non nul, rien de rattrapé sans nouvel accord.

## Contrôles à sec faits (16/11/2026)
- `bash -n` et shellcheck (`-S warning`) de `lintian.sh`, sans avertissement. Relu par le conseiller : `curl -L` limité à https
  (comme `s1.sh` l. 120, 124), nom du champ de sévérité accepté sous ses deux formes, comparaison au blob de HEAD.
- Partie Python du script passée sur des copies de l'index et des statuts : `lintian` → `2.122.0` ; racine → `166 0 0` ;
  amorce → `78 7 0` ; simulation fabriquée à deux lignes `Inst` → verrou écrit, sha256 et chemins de l'index ; témoins négatifs
  refusés (code 1) : mise à jour `Inst apt [3.0.3] (3.0.4 …)`, paquet absent de l'index, ligne `Remv`.
- Analyse du statut de dpkg par `awk` (`installer`) : 166 lignes sur la racine, égal à Python.
- Espace de noms éprouvé sur un dossier vide du scratchpad : root projeté (UID 0), seule interface `lo`, `/dev` de l'hôte lié par
  `mount --rbind`.
- Non éprouvés : `chroot` dans la racine, apt et dpkg dans l'espace de noms, lintian.

## Additif : commande 0, relevé de santé de lintian (écrit à 2026-11-16T17:06:51Z, préparé à sec sans accord nommé) : NON LANCÉ

Préparé en suite de la décision « Relevé de santé d'abord (Recommandé) », après le message « Continue » du propriétaire, qui ne
répond pas à la question « Je prépare le relevé de santé de lintian pour docs/04 ? » ; rien n'est lancé.
Script : [`../sante-lintian.sh`](../sante-lintian.sh), nouveau. Une commande, **sur accord nommé**, code relevé juste après :
`mise exec -- poc/bricks/06-deb-sbuild/sante-lintian.sh salsa debian`. Lectures publiques et anonymes, en https seulement
(redirections https comprises) : salsa.debian.org (API GitLab v4, projet `lintian/lintian`), sources.debian.org,
security-tracker.debian.org. Journaux `resultats/sante-lintian-salsa.log` et `resultats/sante-lintian-debian.log` ; cache
`~/.cache/supply-chain-poc/06/sante-lintian/`. Toute lecture ou analyse en échec (erreur HTTP, forme de réponse inattendue,
changelog sans entrée lisible) écrit une ligne `KO` et arrête l'étape ; le code vaut 1 dès qu'une ligne `KO` sort. Rien
d'installé, rien dans le cluster ni dans Zot. Le verdict est écrit ensuite au doc 04 (§4, projets hors GitHub), avec le journal
pour preuve ; lintian est alors ajouté à `tools/health/projects.tsv` (§7, étape 1), comme sbuild et mmdebstrap.

| # | Étape | Prédiction | Confiance |
|---|---|---|---|
| Z1 | `salsa` | Projet `lintian/lintian` trouvé, non archivé ; tags lus ; dernier tag et sa date non prédits ; aucune ligne `KO` | Moyenne : API GitLab de salsa jamais lue par ce dépôt, forme des réponses prise de la documentation de GitLab |
| Z2 | `salsa` | Au moins un commit sur 90 jours ; nombre et auteurs non prédits ; employeurs **non établis** (adresses debian.org ou personnelles) | Haute pour « non établis » ; moyenne pour l'activité |
| Z3 | `salsa` | Fusionneurs de 100 MR fusionnées (les plus récemment mises à jour) et période couverte non prédits. Signature du dernier tag : relevée telle que l'API la rapporte ; un 404 ne prouve pas l'absence de signature GPG, et rien n'en sera déduit | Sans objet |
| Z4 | `salsa` | `SECURITY.md` : HTTP 404 (absent) ; non bloquant pour un outil de distro (§1 du doc 04) ; Scorecard n/d (hors GitHub) | Moyenne |
| Z5 | `debian` | `2.122.0` listée dans la suite `trixie` ; une version dans `sid`, égale ou plus récente ; date de l'entrée `2.122.0` du changelog relevée ; au moins une entrée sur 12 mois ; aucune entrée illisible ; Maintainer : l'équipe de lintian (liste debian.org) ; aucune ligne `KO` | Haute pour trixie (index de l'instantané, `lintian.sh`) ; moyenne pour le reste |
| Z6 | `debian` | Entrées CVE et TEMP du security tracker : nombre non prédit ; le compte ne distingue pas ouvert de résolu, seules les rubriques « Open issues » et « Resolved issues » sont relevées présentes ou non | Sans objet |
| Z7 | verdict | **Aucun critère « Risqué »** (release de moins de 12 mois, projet non archivé, plus d'un signataire d'upload sur 12 mois) ; verdict attendu **« À surveiller, hors chemin critique »** : Scorecard n/d et employeurs non établis. Hors chemin critique : lintian juge le paquet source, ne produit ni ne signe aucun artefact, et la porte ne le lit pas. Critère « releases signées » : jugé sur la version employée, comme les rpm signés de Rocky pour rpm et createrepo_c : `.deb` de l'instantané, sous l'InRelease vérifié par gpgv (Y1), puis sha256 du verrou (Y3) ; pas sur les tags de salsa | Moyenne |

**Cas d'échec.**
- Un critère « Risqué » mesuré : lintian est interdit (règle du propriétaire) ; l'étape lintian est suspendue, décision du
  propriétaire.
- Verdict limite (par exemple un seul signataire d'upload sur 12 mois, ou une seule personne pour presque toutes les fusions) :
  la décision revient au propriétaire, comme pour debuerreotype et OSS Rebuild ; aucun verdict écrit sans elle.
- Une ligne `KO` (réseau, HTTP, forme de réponse) : arrêt, rien relancé sans nouvel accord.

**Contrôles à sec faits (16/11/2026).** `bash -n` et shellcheck (`-S warning`), sans avertissement. Analyse du changelog
(Python) passée sur des copies fabriquées : dates, signataires, fenêtres de 6 et 12 mois, date de la version employée, lecture
arrêtée à la première entrée de plus de 12 mois après elle ; témoins négatifs : une date illisible et une date sans fuseau
(`-0000`) comptées illisibles, sans trace ; changelog vide : `KO`, code 1. `debian/control` (awk) : adresses réduites à leur
domaine. Expressions jq passées sur des JSON fabriqués (fusionneurs, période des MR, tags, suites) ; témoin négatif : JSON de forme
inattendue, `KO`, code 1. Aucune lecture réseau faite à sec : les URL et la forme des réponses ne sont pas éprouvées.

### Résultats de la commande 0 (écrits à 2026-11-16T17:08:23Z)

Lancée sur « Oui, lance-le » (réponse à « Je lance sante-lintian.sh salsa debian (lectures publiques) ? »), de
2026-11-16T17:07:31Z à 17:07:42Z, **code 0**, aucune ligne `KO` : [`sante-lintian-salsa.log`](sante-lintian-salsa.log),
[`sante-lintian-debian.log`](sante-lintian-debian.log). Fenêtre des commits : depuis 2026-08-18.

| # | Mesure | Verdict |
|---|---|---|
| Z1 | Projet `lintian/lintian` (créé le 10/04/2018), branche `master`, dernière activité le 14/11/2026 ; 8 tags lus, le plus récent `2.144.0` du 14/11/2026, tous annotés. **Champ `archived` : `null`** (absent de la réponse anonyme), donc « non archivé » n'est pas mesuré par ce champ ; indice seulement : un tag et des commits du 14/11/2026 | **Écart de forme** : prédiction tenue sauf la mesure directe de l'archivage |
| Z2 | 108 commits, du 22/08 au 14/11/2026 ; 14 auteurs, dont un à 58 commits ; adresses debian.org ou personnelles pour les 12 auteurs affichés : employeurs non établis | Tenue |
| Z3 | 100 MR fusionnées entre le 22/05 et le 14/11/2026, dont 52 dans la fenêtre ; fusionneurs : **nilesh 71, pollo 28, noahm 1** (deux comptes pour 99 fusions sur 100) ; signature du tag `2.144.0` : HTTP 404, aucune rapportée par l'API, rien n'en est déduit | Relevé (non prédit) |
| Z4 | `SECURITY.md` : HTTP 404 ; Scorecard n/d | Tenue |
| Z5 | `2.122.0` dans `trixie` ; `2.122.0+deb13u1` dans `trixie-proposed-updates` (non employée, contenu non lu) ; `2.143.0` dans `forky` ; `2.144.0` dans `sid`. Entrée `2.122.0` du changelog : 28/03/2025. 13 entrées sur 6 mois, 24 sur 12 mois, **2 signataires distincts** sur l'une et l'autre fenêtre ; 30 entrées lues, 0 illisible. Maintainer : « Debian Lintian Maintainers » (debian.org) ; 3 Uploaders | Tenue |
| Z6 | Security tracker : 6 entrées CVE (la plus récente CVE-2017-8829) et 2 TEMP ; rubrique « Open issues » absente, « Resolved issues » présente | Relevé |
| Z7 | Aucun critère « Risqué » : release du 14/11/2026, 13 releases en 6 mois, activité continue, 3 Uploaders déclarés et 2 signataires des entrées du changelog. Critères qui manquent : Scorecard n/d, employeurs non établis, **bus factor de 2** (2 signataires des entrées du changelog sur 12 mois, 2 comptes pour 99 des 100 MR fusionnées lues), SECURITY.md absent (non bloquant : outil de distro ; rubrique « Open issues » absente de la page du security tracker). Archivage déduit, non mesuré (Z1). Version visée 2.122.0 : contrôles Y1 et Y3 et verrou à venir, non lancés | **Tenue, sauf la mesure directe de l'archivage : « À surveiller, hors chemin critique »**, porté au doc 04 (§4) |

Bus factor de 2 : le §1 classe ce cas en « À surveiller », pas en verdict limite (le cas d'échec ci-dessus visait un seul
signataire ou une seule personne pour presque toutes les fusions). « Hors chemin critique » est mon classement (Z7), alors que
sbuild et mmdebstrap sont au chemin critique dans `projects.tsv` : à contredire par le propriétaire s'il le juge autrement. lintian est ajouté à `tools/health/projects.tsv`.
Prochaine commande de l'étape : `lintian.sh prealables` (commande 1), sur accord nommé.

### Résultat de la commande 1, `prealables` (écrit à 2026-11-16T17:12:56Z)

Lancée sur « Oui » (réponse à « Je lance lintian.sh prealables (hors réseau) ? »), de 2026-11-16T17:12:44Z à 17:12:47Z,
**code 0**, `bilan : tout OK` : [`lintian-prealables.log`](lintian-prealables.log). **Y1 tenue** : les trois clés épinglées
signent InRelease `0584fba3…` ; Packages `4f2c68d6…` listé et égal à `Packages.xz` décompressé ; lintian `2.122.0` dans l'index ;
racine `f8f221ca…`, ses listes et son `sources.list` égaux ; 166 paquets, 0 hors index, lintian absent ; 8 nœuds de périphérique ;
`.dsc` `9050679e…` et `ee2a6b8e…`, chaque fichier de leurs `Checksums-Sha256` égal. Place libre sous `~/.cache` : 65 517 Mo.
Prochaine commande : `lintian.sh resoudre` (hors réseau), sur accord nommé.

### Résultat de la commande 2, `resoudre` (écrit à 2026-11-16T17:14:43Z)

Lancée sur « Oui » (réponse à « Je lance lintian.sh resoudre (hors réseau) ? »), de 2026-11-16T17:14:21Z à 17:14:24Z,
**code 0**, `bilan : tout OK` : [`lintian-resoudre.log`](lintian-resoudre.log). Racine extraite (350 Mo). `apt-get -s` code 0 :
157 lignes `Inst`, 157 `Conf`, 0 `Remv`, « 0 upgraded » ; lintian `2.122.0 all` dans le verrou ; chaque paquet dans l'index (le mode
`verrou` refuse sinon). Verrou [`../lintian/verrou-lintian.txt`](../lintian/verrou-lintian.txt) : **157 paquets, 22 984 704
octets**, sha256 `06588f5e…`, recompté hors du script (157 lignes, même somme des tailles). **Y2 tenue** : nombre dans la plage
130 à 200. La taille, environ 23,0 Mo, est sous l'ordre de grandeur annoncé (environ 26 Mo, 168 paquets par la résolution
simplifiée) : écart d'estimation, sans critère attaché. Verrou commité avec ce résultat, avant `telecharger`.
Prochaine commande : `lintian.sh telecharger` (réseau : snapshot.debian.org en https), sur accord nommé.

### Résultat de la commande 3, `telecharger` (écrit à 2026-11-16T17:18:53Z)

Lancée sur « Lance le » (réponse à « Je lance lintian.sh telecharger (réseau, snapshot.debian.org) ? »), de 2026-11-16T17:18:19Z
à 17:18:40Z, **code 0**, `bilan : tout OK` : [`lintian-telecharger.log`](lintian-telecharger.log). Verrou commité et inchangé
(`06588f5e…`) ; 157 `.deb` téléchargés et contrôlés (sha256 et taille), 0 déjà présent ; 22 984 704 octets ; 157 fichiers `.deb`
dans le dossier. **Y3 tenue.** Prochaine commande : `lintian.sh installer` (hors réseau), sur accord nommé.

### Résultat de la commande 4, `installer` (écrit à 2026-11-16T17:19:46Z)

Lancée sur « Oui » (réponse à « Je lance lintian.sh installer (hors réseau) ? »), de 2026-11-16T17:19:27Z à 17:19:35Z,
**code 0**, `bilan : tout OK` : [`lintian-installer.log`](lintian-installer.log). Verrou inchangé ; racine réextraite
(`f8f221ca…`, 350 Mo) ; 157 `.deb` recontrôlés dans la racine ; `dpkg -i` code 0, 157 lignes « Setting up », 0 ligne d'erreur ;
0 paquet hors de l'état `ii` ; installés = racine + verrou (323 paquets = 166 + 157, liste `cc8c2995…`) ; lintian `2.122.0` ;
`dpkg --audit` vide. **Y4 tenue** : premier `chroot`, premier dpkg et scripts de maintenance dans l'espace de noms, sans incident
relevé. Prochaine commande : `lintian.sh juger` (hors réseau), sur accord nommé.

### Résultat de la commande 5, `juger` (écrit à 2026-11-16T17:20:49Z)

Lancée sur « Oui » (réponse à « Je lance lintian.sh juger (hors réseau) ? »), de 2026-11-16T17:20:10Z à 17:20:17Z, **code 0**,
`bilan : tout OK` : [`lintian-juger.log`](lintian-juger.log).

| # | Mesure | Verdict |
|---|---|---|
| Y5 | `lintian -I` sur 1.0.0-1 : code 0 ; **une** ligne `I: sample-app source: missing-static-built-using-field-for-golang-package (in section for sample-app) [debian/control:10]` | **Tenue** : le témoin porte le tag |
| Y6 | `lintian -I` sur 1.0.0-2 : code 0 ; **aucune** ligne du tag | **Tenue** : le tag disparaît avec `Static-Built-Using: ${misc:Static-Built-Using}` |
| Y7 | `lintian` sans `-I` sur les deux `.dsc` : code 0, aucune ligne de sortie, donc aucune du tag | Tenue |
| Y8 | Règle `BuiltUsing.pm` (sha256 `5070adf2…`) et fichier `.tag` (`fae231ae…`) trouvés, lignes relues (`satisfies('golang-go \| golang-any')`, littéral `${misc:Static-Built-Using}`) ; sévérité `info` ; `debian/control` de 1.0.0-2 égal au blob de HEAD (dernier commit `593cee4`) ; 0 `Static-Built-Using` dans celui de 1.0.0-1, 1 littéral dans celui de 1.0.0-2 ; quatre codes de lintian à 0 ; une seule ligne nomme le tag, celle de Y5 | Tenue |

Autres tags, relevés tels quels (aucun `E:` ni `W:`), présents sur les deux révisions, chacun à décider à part, aucune décision
prise : `debian-rules-parses-dpkg-parsechangelog [debian/rules:10]`, `debian-watch-file-is-missing`,
`missing-xs-go-import-path-for-golang-package` (tous `I:`). Sortie d'erreur de chaque appel : une ligne, « running with root
privileges is not recommended! » (root projeté dans l'espace de noms).

**Étape lintian (étape 6 de la séquence d'après S5b) faite : Y1 à Y8 tenues.** Le jugement porte sur le `.dsc` `ee2a6b8e…` de
`sources.sh`, rattaché à D par le `debian/control` inchangé depuis `593cee4`, pas sur le `.dsc` de D (`b284bd60…`, absent de
l'hôte). Le chroot est présent sous `~/.cache/supply-chain-poc/06/lintian/chroot` (`test -d`, 2026-11-16T17:22:27Z) ; rien au niveau système.

