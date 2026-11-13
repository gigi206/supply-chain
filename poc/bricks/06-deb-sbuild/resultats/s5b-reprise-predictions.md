# Reprise du bloc 06 de S5b : carte et prédictions (13/11/2026, préparées à sec, avant toute exécution)

Décisions du propriétaire : « Oui, arrête-le » (banc Debian arrêté, priorité à la reprise du bloc 06) puis « Oui, prépare-la ».
Plateforme rebâtie le 13/11 jusqu'à « J8 (résolveurs) », `fuites` et CIS passés (README de la 08). Le bloc 06 n'est pas jouable
tel quel : `vm.sh detruire` a effacé `$W` (`~/.cache/supply-chain-poc/08/travail`) au lancement de S5b, et Zot est neuf.

## Ce que le bloc 06 lit et qui manque
- `$W/s1-06` : `Packages`, `hote/` (S1 prealables), `racine.tar` (S1 racine) ; lus par S4a (l. 46-48, 89) et S4c (l. 30-31).
- `$W/s2-06/chroot.tar` et la fermeture (S2 racine) ; lus par S4a (l. 48) et S3.
- Dans Zot : l'image d'essai `essais-06/sbuild-debian13@d8041f9c` (S1 image, passage s1b), lue par S3 builds (`s3.sh` l. 39-40) ;
  la fermeture de S2 `deps/sample-app/deb-buildinfo@3a0e54ae`, lue par S3 restauration.
- `$W/s3-06/build-1/sample-app_1.0.0-1_amd64.deb` (S3 builds), lu par `s4d.sh prealables` (l. 239).
- `$W/s4d-06/digest-attendu` (`s4d.sh prealables`, l. 257), exigé par S4d (l. 327) ; `prealables` lit aussi les copies de S4b
  (`entrees_hote`), donc vient après S4b.

## Séquence (chaque ligne : un accord nommé ; journaux sous un nouveau libellé quand le script le permet)
1. `DISTRO=rke2 PREFIXE=s1r mise exec -- poc/bricks/06-deb-sbuild/s1.sh prealables amorce racine image` : `PREFIXE` autre que
   `s1` ajoute iproute2, comme s1b et s1c ; `GARDER_CHROOT=0` (défaut) reconstruit aussi le chroot de S1. Pods `racine` sous le
   label `prefetch-deb` (`s1.sh` l. 60-62, 98, 198), seule sortie permise par la 08c vers l'instantané (port 80).
2. `DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s2.sh buildinfo racine fermeture restauration` (journaux `s2-*` réécrits :
   le script n'a pas de préfixe ; les versions archivées restent dans git).
3. `DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s3.sh restauration builds comparaison` (journaux `s3-*` réécrits).
4. `DISTRO=rke2 DEPUIS='06 (S1, amorce)' JUSQUA='06 (S4b)' mise run confiance:rejeu -- s5b-06-a` (rien n'y pousse de VSA).
5. `DISTRO=rke2 mise exec -- poc/bricks/06-deb-sbuild/s4d.sh prealables` (hôte seul).
6. `DISTRO=rke2 POUSSER_VSA=1 DEPUIS='06 (S4d)' mise run confiance:rejeu -- s5b-06-b` : S4d, S4d3 avec la porte, puis `fuites` et
   CIS.

## Après la reprise (hors de cette carte, chacun sur accord)
- `pousser_vsa` et `lire_vsa` de la 06 (S6b), qui exigent `builds/sample-app-deb@039949f9` dans Zot (`apres-s5b`, étape 2).
- **Option E** (brique 03, jalon à écrire) : `outils-prefetch` construite dans la chaîne sur le modèle de S4a. Placée après la
  reprise, pour ne pas changer `68e0ae70` pendant que C3 et C6 (mêmes bundles, même deb) se jugent ; son nouveau digest entrera
  avec la cascade 1.0.0-2, qui re-signe déjà preparer-deb.

## Prédictions de la reprise

| # | Prédiction | Confiance |
|---|---|---|
| P1 | S1 prealables : InRelease `0584fba3…` (égal au banc Debian du jour et à S1), versions épinglées présentes | Haute |
| P2 | S1 racine : racine `f8f221ca…` et chroot de S1 `440ba93b…` | Moyenne : s1 et s1c égaux à 1 h 30 d'écart, jamais à 3 jours sur un cluster neuf |
| P3 | S1 image : `essais-06/sbuild-debian13@d8041f9c…` | Moyenne : P2 et assemblage par crane, non rejoué |
| P4 | S2 racine : chroot `e0b1f37c…` deux fois ; fermeture de 162 debs aux sha256 du verrou | Moyenne : même pod coup sur coup le 10/11 seulement |
| P5 | S2 fermeture : `deps/sample-app/deb-buildinfo@3a0e54ae…` | Moyenne : dépend de P4 et du manifeste déterministe de closure.sh |
| P6 | S3 : deb `0b489d43` deux fois | Moyenne |
| P7 | `s4d.sh prealables` : même `digest-attendu` qu'au 11/11 (`039949f9`, manifeste) | Moyenne : dépend de P6 |
| P8 | Bloc 06 : C1 à C9 de `s5b-predictions.md` (08), telles qu'écrites le 11/11 | (celles de C1 à C9) |
| P9 | `fuites` : aucun secret ; CIS sans attendu | Haute |

## Limites
- Les journaux archivés de S2 et S3 seront réécrits (pas de préfixe dans ces scripts) ; ceux de S1 passent sous `s1r-*`.
- Le temps réseau dépend de snapshot.debian.org (lent par moments) ; aucune durée n'est prédite.
- Règle des 2× : README de la 06, note du 13/11 (projection de 1,13 à 2,02 pw, seuil de 4 pw non atteint).

## Résultat de l'étape 1 (note de 2026-11-13T14:22:31Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance l'étape 1 : PREFIXE=s1r s1.sh prealables amorce racine image ? ». De 14:17:00 à 14:22:09 UTC,
code 0, 16 OK, 0 KO (journaux `s1r-*`).
- **P1 tenue** : InRelease `0584fba3…` sur l'hôte et lu par apt dans le pod.
- **P2 tenue** : racine `f8f221ca…` et chroot de S1 `440ba93b…` (mmdebstrap : 66 s, 920 000 000 octets) ; 238 .deb sur 238
  conformes au Packages vérifié (amorce 20, racine 107, chroot 111). Mêmes empreintes qu'au 10/11, trois jours plus tard, sur un
  cluster neuf.
- **P3 tenue** : `essais-06/sbuild-debian13@d8041f9c…`.

## Résultat de l'étape 2 (note de 2026-11-13T14:28:59Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance l'étape 2 : s2.sh buildinfo racine fermeture restauration ? ». De 14:23:57 à 14:28:33 UTC, code 0,
15 OK, 0 KO (journaux `s2-*` réécrits ; versions du 10/11 dans git).
- **P4 tenue** : chroot-a et chroot-b `e0b1f37c…` (508 546 560 octets ; chroot-b en 50 s), rapatrié à l'identique ; fermeture de
  162 fichiers aux empreintes de la liste attendue ; paquets contrôlés : amorce 20, chroot-a 63, chroot-b 63, fermeture 162.
- **P5 tenue** : `deps/sample-app/deb-buildinfo@3a0e54ae…`, même digest au second envoi ; 162 couches, chacune égale au SHA256 de
  Packages ; restauration par digest : 162 fichiers conformes.

## Résultat de l'étape 3 (note de 2026-11-13T14:33:28Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance l'étape 3 : s3.sh restauration builds comparaison ? ». De 14:32:46 à 14:32:47 UTC, **code 1**.
- `restauration` passée : deux restaurations par digest de `3a0e54ae`, 162 fichiers conformes chacune.
- `builds` arrêtée avant tout pod : `KO   sources de sample-app` ; `s3.sh` l. 208 lit `$W/s1-06/SHA256SUMS.s1`, absent. Ce fichier
  est écrit au début de `s1.sh essais` (l. 261 : trois lignes extraites de `~/.cache/supply-chain-poc/packaging/SHA256SUMS`), étape
  que la carte n'avait pas listée : **oubli de la carte**, qui ne relevait que les lectures du bloc 06 et de S3 restauration.
- P6 et la suite : non jugées. Rien d'autre n'est lancé.

## Résultat de l'étape 3, suite (note de 2026-11-13T14:51:53Z ; rien n'est réécrit)
- **Action manuelle** (« Ligne 261 seule » à « Comment produire SHA256SUMS.s1 avant de relancer S3 ? ») : à 14:38:07 UTC, la seule
  ligne 261 de `s1.sh` rejouée sur l'hôte (`SHA256SUMS` de packaging contrôlé d'abord) : `$W/s1-06/SHA256SUMS.s1`, 3 lignes, chacune
  vérifiée (`orig.tar.gz`, `.dsc`, `debian.tar.xz` : OK), sha256 du fichier `3acfed27…` ; aucun pod lancé.
- `s3.sh builds comparaison` de 14:38:15 à 14:51:07 UTC, code 0, 24 OK, 0 KO.
- **P6 tenue** : deb `0b489d43…` sur les deux builds ; Installed-Build-Depends des deux égal à celui de S2 ; aucune ligne apt en
  http(s) ; neutralisation des sources de l'instantané faite ; installés par sbuild = simulés, 0 écart.

## Résultat de l'étape 4 (note de 2026-11-13T15:03:01Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance l'étape 4 : rejeu de « 06 (S1, amorce) » à « 06 (S4b) » ? ». De 14:52:30 à 15:02:27 UTC, arrêt voulu après « 06 (S4b) » (JUSQUA), code 0, 126 OK, 0 KO ([journal](../../08-trust-plane/resultats/rejeu-s5b-06-a.log)).
- **C1 tenue** : amorce `7378260c`. **C2 tenue** : `packaging-deb@c1719b13`, deux poussées au même digest.
- **C3 tenue pour les tâches de ce passage** : prefetch-deb `4dac0609`, construire-builder `746c2e11`, prefetch-gomod `170bef53`,
  dans la liste revue ; aucune ligne de nouvelle signature ; preparer-deb et construire-deb viendront avec S4d.
- **C4 tenue** : `builds/builders/sbuild-debian13@749d746c`, deux fois.
- **C5 tenue** : fermetures `sample-app-deb@bb7599a2` et `sample-app-sources@50dc73f7`, deux fois chacune ; fichiers gomod égaux à
  ceux de F2 ; archive npm conforme à l'integrity du lockfile.

## Résultat de l'étape 5 (note de 2026-11-13T15:05:24Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance l'étape 5 : s4d.sh prealables (hôte seul) ? ». De 15:05:01 à 15:05:10 UTC, code 0, 46 OK, 0 KO.
**P7 tenue** : `digest-attendu` = `sha256:039949f9…` (deb `0b489d43`, entrées fixées par digest, dont la fermeture `bb7599a2`) ;
`entrees.tar` de 227 266 560 octets écrit pour le pod d'essai.

## Résultat de l'étape 6 (note de 2026-11-13T15:33:05Z ; rien n'est réécrit)
« Oui, lance-la » à « Je lance l'étape 6 : rejeu depuis « 06 (S4d) » avec POUSSER_VSA=1 ? ». De 15:06:53 à 15:32:11 UTC, **code 1**,
107 OK, 1 KO ([journal](../../08-trust-plane/resultats/rejeu-s5b-06-b.log)).
- **S4d** (778 s) : artefact `039949f9` sur les deux exécutions, égal à `digest-attendu` (**C6 tenue**) ; preparer-deb `588617b8` et
  construire-deb `3726ff0b` dans la liste revue (**C3 tenue** pour ces tâches).
- **S4d3 chemins** : webhook et rattrapage rendent tous deux `039949f9`, TaskRuns 3/3 réussis et signés, PipelineRun signé par
  Chains, même spec par les deux chemins, rejeu de la livraison sans double création. **Un écart** : au rattrapage, les pods portant
  le label du PipelineRun sont quatre : `construire|sc-build|kata`, `preparer`, `publier` et un pod **sans label de tâche**
  (`null|sc-build|-`) ; au webhook, les trois attendus. Nature du pod non lue (lecture du cluster par script seulement).
- Non lancés : la porte de S4d3 (C9), `fuites` et CIS. C7 (bundle de pipeline) et C8 : à relever dans le journal avec le relevé.

## Note de 2026-11-13T15:36:09Z : pod sans label de tâche relevé (rien n'est réécrit)
Relevé en lecture seule (« Oui, lance-le »), 15:35:05 UTC, code 0 ([relevé](s5b-releve-pod-null.log)) : il ne reste que les trois pods
attendus (construire sous Kata, preparer, publier), chacun possédé par son TaskRun, 0 nouvel essai ; le quatrième pod a disparu.
Lecture : c'est l'**assistant d'affinité de Tekton**, déjà décrit au README de la 08 (l. 650 : « pod null », StatefulSet qui porte
les labels du PipelineRun sans label de tâche ; le pipeline a un workspace en `volumeClaimTemplate`) ; il est effacé à la fin du
PipelineRun et n'était pas encore parti au contrôle du rattrapage (publier fini à 15:31:55 UTC). **Défaut du contrôle**, dépendant
du moment, pas de la plateforme ; non vérifié sur le pod lui-même (il n'existait plus au relevé).
Correctif préparé à sec, NON APPLIQUÉ : `s4d3.sh` l. 146, sélecteur `app.kubernetes.io/component!=affinity-assistant` en plus
(label utilisé par `construction.sh` l. 364 pour trouver ce pod) ; shellcheck 3 avant comme après ; `bash -n` tenu.

| # | Prédiction pour la reprise à « 06 (S4d3) » | Confiance |
|---|---|---|
| P10 | Avec le correctif, « pods (tâche\|nœud\|runtime) » rend les trois attendus sur les deux chemins ; C8 et C9 tenues ; `fuites` et CIS comme au passage de 13:00 | Moyenne : C9 dépend de l'âge de la base de grype |
