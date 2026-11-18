# Brique 05, carte de M1b (images rpm construites par la plateforme), préparée à sec (18/11/2026, écrite à 19:38:39 UTC)

**Interprétation** : la décision « C » (carte de M5b, note de 19:33:32 UTC) appelle « un jalon à part, avec sa propre carte ». Je la prépare à sec sous l'accord permanent du 18/11. Rien n'a été lancé ni écrit dans Zot, le cluster ou les VM, et rien n'a été mesuré. Aucune tâche, aucun script, aucune prédiction : c'est la même règle que la carte de S4a de la 06.

**Nom** : « M1b » est mon choix. Le texte de M1 au tableau des jalons du README demande une « image `builders/mock-rocky9` construite par notre chaîne, base Rocky par digest, mock 6.9 épinglé ». S1 a construit les images d'essai hors de la plateforme (« Option 1 »). M1b fait ce que M1 demandait, et y ajoute l'image de bootstrap.

**Objet** : la plateforme construit sans réseau les deux images, outillage et bootstrap. Elle les publie et les fait signer par Chains, avec une provenance. Les tâches rpm passent ensuite sur ces images, puis le rejeu de M5b les refait. Docs/04 prévoit déjà ce remède pour les images de base Rocky : « Bases reconstruites depuis les dépôts signés (dnf `--installroot`, mmdebstrap), à mesurer » (l. 192).

## 1. Le point qui commande le reste : refaire la même image sans rien lire dans Zot

Les tâches signées épinglent l'image d'outillage par digest : `prefetch-rpm`, l. 44, et `construire-rpm`, l. 18. Le verrou et la fermeture épinglent le bootstrap. Le rejeu vide Zot. M1b ne tient donc que si le rejeu reconstruit chaque image **au même digest**. Sinon, chaque rejeu demande de nouvelles signatures et une nouvelle revue de `taches.yml`. La voie deb y arrive : `749d746c` a été retrouvé au bit près en S5b. Pour le rpm, deux points ne sont pas établis.

**A. La racine n'est pas reproductible.**
- `s1.sh`, l. 793, l'écrit en commentaire, sans mesure : « pas reproductible au bit près (base rpm : INSTALLTIME ; journaux de dnf sous var/log) ».
- mmdebstrap a `SOURCE_DATE_EPOCH`, que le manuel lu en S4a documente. Pour rpm 4.16.1.3 et dnf de Rocky 9, je n'ai rien lu qui fixe l'heure d'installation, la base rpm ou l'historique de dnf.
- **À mesurer en premier**, par un banc hors ligne sur l'hôte, comme `m5-sigmd5.sh` :
  - deux `dnf --installroot` des mêmes rpm locaux dans deux dossiers, sous `unshare -rn` et dans la racine de l'image d'outillage (rpm 4.16.1.3 et dnf) ;
  - puis comparer les deux archives fichier par fichier, pour nommer chaque écart : base rpm, journaux, historique de dnf, `machine-id`, caches.
  
  C'est une préparation, puis une mesure sur l'hôte : elle se fait sous l'accord permanent, sans cluster ni Zot.
- **Si un écart ne peut pas être neutralisé**, sans retirer ce dont mock a besoin, le jalon change de nature : l'image a un nouveau digest à chaque rejeu. Le choix te reviendrait alors : accepter une signature et une revue par rejeu, ou épingler autrement.

**B. Les sources de l'outillage bougent.**
- D4 (a) prend l'outillage sur Rocky 9.8 (pub) et EPEL 9 (`s1.sh`, l. 160 à 168). Les quatre paquets épinglés sont mock 6.9-1.el9 et mock-core-configs 45.2-1.el9 (EPEL 9), podman 5.8.2-8.el9_8 et skopeo 1.22.2-9.el9_8 (AppStream 9.8). Ils tirent 199 rpm téléchargés (`s1-racine.log`, l. 223).
- `s1.sh`, l. 6, le dit déjà : « pub/9.8 et EPEL bougent ».
- **À relever** (lecture publique, à faire avant toute préparation) :
  - si les 199 rpm restent téléchargeables à une adresse figée, par exemple vault pour 9.8 et les archives de construction de Fedora pour EPEL ;
  - et si leurs métadonnées signées s'y trouvent aussi.
  
  Je ne l'ai pas vérifié.
- **Sinon**, le rejeu dépend d'un cache de l'hôte, et c'est la dette de l'option A qui revient : deux fichiers hors de toute sauvegarde. C'est en conflit avec D4 (a), que je ne tranche pas : D2 (a) avait choisi vault 9.7 précisément parce qu'il est figé.
- **Le bootstrap n'a pas ce problème** : sa base, `rockylinux:9.7` par digest (`ee90dc0e`), et ses dix NEVRA viennent de vault 9.7, qui est figé (D2 a).
- **Listes** : `s1-racine.log` donne, pour chaque rpm, le dépôt, le nom de fichier et le sha256, et « 199 sur 199 » ont été contrôlés contre les primary vérifiés. `boot_racine` a été comparé aux dix NEVRA épinglés, ni plus ni moins. Leçon de la correction 1 de S4a, où les listes des journaux étaient incomplètes : la liste complète à installer devra être retirée de la base rpm des racines archivées (201 paquets installés pour l'outillage, l. 211), et non des seules lignes « rpm ».

## 2. Transposition de S4a (décision « Oui, retiens-les » du 10/11, README de la 06, additif de 22:54 UTC)

| Choix de S4a (deb) | Transposition proposée (rpm) | Neuf ou repris |
|---|---|---|
| 1. Publication dans `builds/builders/sbuild-debian13` par `publier-image` inchangée | `builds/builders/mock-rocky9` et `builds/builders/rocky9-bootstrap`, par `publier-image` (`d21931f3`). Zot et Chains restent inchangés, comme en S4a | Repris |
| 2. `prefetch-deb` en runc sans root, puis une tâche Kata privilégiée sans aucune sortie | Une tâche runc sans root qui télécharge les rpm, vérifie le `repomd.xml` par gpgv et le sha256 de chaque rpm contre `primary`, puis reconstitue un miroir partiel avec les métadonnées amont. Ensuite une tâche Kata privilégiée, sans aucune sortie, qui lance `dnf --installroot` sur ce miroir | Repris dans la forme ; outils neufs (point 3) |
| 3. mmdebstrap installé par `dpkg -i` dans l'amorce `debian:trixie-…` par digest | dnf est déjà dans l'amorce `rockylinux:9.8` (`ed654c69`), copiée par `s1.sh amorce` ; aucun outil n'est à installer avant `--installroot` | Mesuré en S1 : `racine` a lancé `dnf --installroot` depuis l'image 9.8, mais avec réseau. Hors ligne, sur un miroir partiel : à mesurer |
| 4. Layout OCI écrit à la main, couches non compressées | Même chose. La couche de la racine, puis la couche de configuration de mock (`MOCK_CFG` et `STOCKAGE`, `s1.sh`, l. 454 à 477) pour l'outillage ; la couche pleine de `boot_image` pour le bootstrap | Repris |

## 3. Circularité et outils

- **`prefetch-rpm` tourne sur `99790c13`**, l'image à remplacer (l. 44). Le prefetch de l'outillage ne peut donc pas la prendre. Les candidats sont l'amorce `rockylinux:9.8` par digest, qui a dnf, rpm et python3, ou `plateforme/outils-prefetch` (`68e0ae70`), qui n'a pas d'outil rpm (lecture des tâches, à vérifier).
- **Outils nécessaires et image qui les fournit** (à vérifier dans les images, rien n'est mesuré) :
  - gpgv et sha256 pour le prefetch, et un téléchargeur. Une tâche runc en python3 sur l'amorce suffirait, comme `n34-binaire.py` en S1 ;
  - dnf et rpm pour la tâche Kata (amorce) ;
  - tar, sha256sum et JSON pour le layout (amorce : tar et coreutils ; JSON à la main, comme `construire-deb`).
- **Verdicts de docs/04** :
  - rpm : Scorecard 3,8 ; createrepo_c : Scorecard non mesurée (l. 191) ;
  - mock : 4,9 (l. 45) ; podman et skopeo (l. 76 et 77) ;
  - images Rocky (l. 166) ;
  - **dnf n'a pas de ligne propre**. Je ne l'utiliserai pas avant d'avoir vérifié son verdict, conformément à la règle « rien de Risqué ».
- **Configuration de mock** : elle porte `$BOOT`, la base brute 9.7 copiée par l'amorce. Ce n'est pas le bootstrap dérivé. Dans la voie signée, `construire-rpm` lance `mock --hermetic-build /w/verrou.json` (`construire-rpm.signee.yaml`, l. 122), et le bootstrap vient alors du verrou (`config.bootstrap_image`, lu par `m5-alterer.py`). Les deux images se construisent donc indépendamment. Seul le verrou les relie.

## 4. Changements du cluster, chacun avec son accord

- **Sortie** pour le label de la tâche de prefetch neuve (DNS, adresses publiques en 443), et son ajout au `NotIn` de `builds-sans-internet` (`sortie-builds.sh`, à transposer de `rpm_appliquer`).
- **Politique sans sortie** pour la tâche Kata neuve. `construction-rpm-sans-sortie` ne sélectionne que `construire-rpm`, et `builder-sans-sortie` de la 06 que `construire-builder`.
- **Zot** : aucun changement attendu (choix 1, comme S4a).
- **Liste revue** : deux tâches neuves, et de nouveaux bundles de `prefetch-rpm` et de `construire-rpm`, qui citent la nouvelle image d'outillage. Chacun demande sa revue de `taches.yml`.
- **Pod d'essai avant toute signature** (processus allégé), pour chaque tâche neuve.

## 5. Cascade et frontière du jalon

- **Dans M1b** :
  - les deux tâches neuves ;
  - la pipeline `builders` ;
  - les deux images, avec deux passages au même digest et leur provenance ;
  - le banc de reproductibilité (point 1 A) ;
  - le relevé des sources (point 1 B).
- **Après M1b, avant M5b** :
  - verrou refait hors de la plateforme, avec le nouveau bootstrap (décision « Hors plateforme » ; résolution par mock, sur l'image d'outillage neuve) ;
  - artefact de packaging de M4a republié ;
  - nouveaux bundles de `prefetch-rpm` et de `construire-rpm`, et revue ;
  - fermeture rpm (M4b) ;
  - pipeline et rpm (M4c), rpm à recomparer à celui de M3 ;
  - provenances.
- **Refus de M5a** : ils ont été mesurés sur le bundle actuel de `construire-rpm`. Le code de la confrontation ne change pas, mais le bundle change. Je propose de rejouer R1 à R8 sur le nouveau bundle : `m5.sh` a duré environ 21 min d'exécution, de 18:42:14 à 19:03:47 UTC.
- **Ordre par rapport au 28/11** : tout ce qui est écrit dans Zot avant le rejeu sera effacé et refait par lui. M1b peut se mesurer avant le 28/11. Ses étapes durables entrent dans `rejeu.sh`, dans le bloc de la 05, à la place des images d'essai.
- **Disque** : 4,49 Go libres pour Zot le 18/11 (PT7 non tenue) et `/` de sc-stockage qui grossit d'environ 1,19 Go par jour ; c'est un préalable à relever. L'outillage pèse environ 362 Mo non compressé (archive de `racine`) et le bootstrap environ 258 Mo (archive de `boot_racine`), chacun deux fois s'il est poussé à deux tags.

## 6. Effort et estimation

- **Comparables mesurés** :
  - option 2 de la carte de M4, image d'outillage par une pipeline `builders` : « option 1 et S4a, 4,14 h » (cité tel quel) ;
  - brique 05, de `boot_racine` à M3, 8,93 h (carte de M4) ;
  - M4c, 4,29 h de bout en bout, pour refaire une pipeline et ses preuves ;
  - M5a, environ 21 min d'exécution, plus sa préparation.
- **Estimation de M1b et de sa cascade** : **3 jours**, en supposant le point 1 A neutralisable et le point 1 B résolu par une adresse figée. Les comparables additionnés font environ 17 h. Le bootstrap et le relevé des sources n'ont pas de comparable.
- **Règle des 2×** : décision avec toi à 6 jours, ou plus tôt si le point 1 A ou le point 1 B échoue.
- **Brique 05** : 24,89 h à `c2c5809`, avant M5a. Avec M1b et M5b, la projection est de 24,89 h, plus M5a, plus 3 jours pour M1b, plus 1 jour de rejeu pour M5b. L'estimation de 1,5 jour de M5b valait pour l'option A ; la préparation de son rejeu reste à refaire. Le seuil de 5 pw demande une conversion entre heures et pw que je n'ai jamais faite (« les heures ne sont pas converties en pw », carte de M5). Je ne la fais pas ici : ce point est mis de côté pour plus tard, il n'est pas posé.

## Question posée

**Transposition de S4a** : retiens-tu les quatre transpositions du point 2 (destination `builds/builders/`, prefetch runc et constructeur Kata sans sortie, dnf de l'amorce, layout OCI à la main) ?

**Ordonnées pour plus tard, non posées** :
1. Résultat du banc de reproductibilité (point 1 A) ;
2. Relevé des sources figées de 9.8 et d'EPEL, et conflit éventuel avec D4 (a) (point 1 B) ;
3. Verdict de dnf dans docs/04 ;
4. Rejeu de R1 à R8 sur le nouveau bundle ;
5. Lecture du seuil de 5 pw.

Suite sans attendre la réponse, sous l'accord permanent : le banc de reproductibilité du point 1 A, hors ligne sur l'hôte.

## Note datée du 18/11/2026, écrite à 19:39:49 UTC : décision « Oui »

**Décision du propriétaire** (réponse reçue avant 19:39:49 UTC, heure exacte non relevée) : « Oui », sur la question « retiens-tu les quatre transpositions du point 2 ». Ce n'est un accord pour aucune écriture dans le cluster ni dans Zot. Chaque changement du point 4 garde son accord.
- **Retenues** :
  1. Publication dans `builds/builders/mock-rocky9` et `builds/builders/rocky9-bootstrap` par `publier-image` inchangée.
  2. Une tâche runc sans root qui télécharge et vérifie (gpgv sur `repomd.xml`, sha256 contre `primary`) et reconstitue un miroir partiel avec les métadonnées amont, puis une tâche Kata privilégiée, sans aucune sortie, qui lance `dnf --installroot` sur ce miroir.
  3. Le dnf de l'amorce `rockylinux:9.8` (`ed654c69`).
  4. Un layout OCI écrit à la main, avec des couches non compressées.
- **Inchangé** : les points 1 A et 1 B restent à mesurer et à relever avant toute tâche ; le verdict de dnf dans docs/04 reste à vérifier.
- **Suite**, sous l'accord permanent : le banc de reproductibilité du point 1 A, hors ligne sur l'hôte.

## Note datée du 18/11/2026, écrite à 2026-11-18T20:23:29Z UTC : décision « Oui 9.8 »

**Décision du propriétaire** (réponse reçue avant 2026-11-18T20:23:29Z UTC, heure exacte non relevée) : « Oui 9.8 ». La question était : « Pour l'outillage de M1b, rester sur Rocky 9.8 figée, ou suivre 9.9 ? ».
- **Retenu** : l'outillage de M1b reste sur Rocky 9.8 figée.
  - Les 190 rpm de Rocky viennent de `vault/rocky/9.8`, aux repomd signés, identiques à ceux du 17/11 ([relevé](m1b-sources.log)).
  - Les 9 rpm d'EPEL viennent de `pub/archive/epel/9.8` (révision du 10/11/2026), qui n'a pas de métadonnées signées.
- **Inchangé** :
  - le verdict de dnf dans docs/04 reste à établir avant toute tâche ;
  - l'instantané `archive/epel/9.8` reste à relire avant d'épingler ;
  - la liste complète à installer reste à retirer de la base rpm de la racine archivée ;
  - les quatre angles morts du troisième banc restent à mesurer.
- **Ce n'est pas un accord** pour une écriture dans le cluster ni dans Zot.

## Note datée du 18/11/2026, écrite à 2026-11-18T20:43:19Z UTC : décision « À surveiller » pour dnf 4 et libsolv

**Décision du propriétaire** (réponse reçue avant 2026-11-18T20:43:19Z UTC, heure exacte non relevée) : « À surveiller ». La question portait sur dnf 4 et libsolv : « « À surveiller » par pondération, ou « Risqué » ? ».
- **Contexte** : elle suit la recommandation du conseiller, rapportée à la demande du propriétaire, et la mesure de sa condition (correctifs de la distribution en 12 mois).
- **Consigné** : ligne au §3 de docs/04 et plan de sortie au §6, ce dernier marqué « non mesuré ».
- **Conséquence** : dnf n'est plus suspendu dans M1b. La relance du troisième banc, à partir du 19/11, et le banc du bootstrap reprennent.
- **Ce n'est pas un accord** pour une écriture dans le cluster ni dans Zot.

## Note datée du 18/11/2026, écrite à 2026-11-18T20:50:47Z UTC : listes complètes retirées des deux racines archivées

- **Outillage** : 199 rpm et 2 gpg-pubkey (Rocky 9 et EPEL 9). La liste est épinglée par dépôt, fichier et sha256 dans [`m1b-listes-outillage.txt`](m1b-listes-outillage.txt). Son S vaut 1793914619 (5/11/2026).
- **Bootstrap** : 153 entrées. 143 viennent de l'image `rockylinux:9.7` (23/11/2025) et 10 de la transaction des dix lignes (17/11/2026). Son S vaut 1766985142 (29/12/2025).
- **Détail** : [prédictions et résultat](m1b-predictions.md), [journal](m1b-listes.log).
- **Reste** : relire l'instantané `archive/epel/9.8`, puis faire le banc de l'outillage, qui demande de télécharger les 199 rpm.

## Note datée du 18/11/2026, écrite à 2026-11-18T21:01:09Z UTC : banc de l'outillage

- **Relecture d'EPEL** : l'instantané `archive/epel/9.8` n'a pas bougé depuis le relevé du 18/11 (`repomd.xml` `e86fdcd8…`).
- **Miroir partiel** : il est vérifié (199 rpm, sha256 et `rpm -K`), et il résout les 199 paquets de S1.
- **Reproductibilité** : deux installations sous SOURCE_DATE_EPOCH ne diffèrent que par `etc/machine-id`, aléatoire.
- **Écart avec S1** : le banc garde toutes les langues, contre très peu dans S1, et `var/lib/dnf` y a le mode 0775 au lieu de 0755. Les outils de l'amorce comptent donc.
- **Détail** : [prédictions et résultat](m1b-predictions.md), [journal](m1b-outil.log), [analyse](m1b-outil-analyse.log).
- **Ce n'est pas un accord** pour une écriture dans le cluster ni dans Zot.

## Correction à la note du banc de l'outillage (écrite à 2026-11-18T21:03:44Z UTC)

« Les outils de l'amorce comptent donc » dépasse la mesure. Le banc mesure des écarts de langues et de mode avec S1, mais il n'a lu ni l'amorce, ni le umask. La cause reste une hypothèse ([corrections](m1b-predictions.md)).

## Note datée du 18/11/2026, écrite à 2026-11-18T21:09:22Z UTC : outillage sans machine-id

- **Qui l'écrit** : le `%post` de systemd lance `systemd-machine-id-setup`. Le fichier est déclaré `%ghost` (taille 0) : rpm ne livre pas son contenu.
- **Mesure** : sans ce membre, deux installations de l'outillage faites le même jour donnent la même archive, `05d35d64…`. C'est la référence du 18/11 pour la relance d'un autre jour.
- **À trancher dans la carte** : faut-il un fichier vide ou un fichier absent ? Ce banc n'a mesuré que l'exclusion.
- **Détail** : [prédictions et résultat](m1b-predictions.md), [lecture](m1b-machine-id.log), [journal](m1b-sans-machine-id.log).

## Note datée du 18/11/2026, écrite à 2026-11-18T21:11:17Z UTC : lecture de l'amorce

- **Correction** : l'amorce `ed654c69`, comme l'image du bootstrap `ee90dc0e`, est en local, dans le cache OCI de `s1.sh amorce`. Les notes qui disent le contraire sont fausses.
- **Langues** : `%_install_langs` vaut `en_US` dans l'amorce (`macros.image-language-conf`) et `all` dans la racine d'outils de `99790c13`.
- **Suite** : refaire le banc de l'outillage avec la racine de l'amorce, sous `umask 022`.
- **Détail** : [lecture](m1b-predictions.md), [journal](m1b-amorce-lecture.log).

## Note datée du 18/11/2026, écrite à 2026-11-18T21:13:18Z UTC : portée de la référence 05d35d64

- **Portée** : `05d35d64…` ne vaut que pour les outils de `99790c13`, sous le umask de l'hôte (0002). Elle ne sert pas de référence à un banc fait avec les outils de l'amorce, qui en aura une à lui, faite le même jour.
- **ee90dc0e** : sa présence en local est désormais archivée ([journal](m1b-images-locales.log)).

## Note datée du 18/11/2026, écrite à 2026-11-18T21:28:20Z UTC : outils de l'amorce, résultat

- **Étape racine de S1** : le pod a tourné sur l'amorce `ed654c69` nue (`s1.sh` du passage, `ad16fc99`) ; son umask n'est pas relevé.
- **Banc** (21:25:17 à 21:27:20 UTC, AO1 à AO9 tenues) : avec les outils de l'amorce sous `umask 022`, deux installations donnent la même archive `06c289ad…`, nouvelle référence du 18/11. Elle a les 34 membres de langues de `racine.tar` et le même mode de `var/lib/dnf`.
- **Témoins** : macro de langue masquée → 2 567 membres de langues ; umask 0002 → `var/lib/dnf` en 0775, rien d'autre.
- **Reste** : un autre jour, machine-id (vide ou absent), bootstrap, pod Kata. Point 1 A non établi.
- **Détail** : [résultat](m1b-predictions.md), [journal](m1b-outil-amorce.log).

## Note datée du 18/11/2026, écrite à 2026-11-18T21:30:46Z UTC : a10 contre b5, et corrections

- **a10 contre b5** (AB1 tenue) : macro de langue masquée et umask mis à part, les outils de l'amorce et ceux de `99790c13` donnent, sur le banc, le même contenu ; seul le mode de `var/lib/dnf` diffère.
- **Valeurs à retenir** : `en_US` et umask 022 sont les valeurs de S1 ; les garder pour la tâche est un choix de la carte, non mesuré dans le pod Kata.
- **Autre jour** : relancer `m1b-outil-amorce.sh` (référence `06c289ad…`) et les scripts de `05d35d64…`, inchangés.

## Note datée du 18/11/2026, écrite à 2026-11-18T21:41:32Z UTC : banc du bootstrap, prédictions

- **Banc** : [`m1b-boot.sh`](m1b-boot.sh). La base `ee90dc0e` et les dix lignes sont installées deux fois, hors réseau, avec les outils de `a8` (`dnf-3`, comme S1). Les dix rpm et les métadonnées de BaseOS sont d'abord téléchargés depuis vault 9.7, puis vérifiés.
- **Prédictions** : BT1 à BT10 ([détail](m1b-predictions.md)), écrites avant le lancement.
- **Ce n'est pas un accord** pour une écriture dans le cluster ni dans Zot.
