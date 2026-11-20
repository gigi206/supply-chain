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

## Note datée du 18/11/2026, écrite à 2026-11-18T21:44:13Z UTC : banc du bootstrap, résultat

- **Passages** : le premier (21:41:38 UTC) s'est arrêté sur un défaut du script, avant toute installation ([`m1b-boot-1.log`](m1b-boot-1.log)). Le second a duré de 21:42:26 à 21:42:48 UTC, code 0.
- **Résultat** : BT1 à BT8 tenues. Avec les exclusions du banc de l'outillage, deux installations donnent la même archive, `28634a12…`, référence du 18/11 pour le bootstrap. Les langues et la liste `rpm -qa` sont celles de S1.
- **Écart non prévu** (BT9 en partie) : le mode de la racine de l'archive, 0775 sur le banc (`mkdir` de l'hôte) et 0555 dans S1. C'est une valeur de plus à choisir dans la carte.
- **Autre jour** : relancer `m1b-boot.sh` inchangé et comparer `x1` à `28634a12…`.
- **Détail** : [résultat](m1b-predictions.md), [journal](m1b-boot.log).

## Note datée du 18/11/2026, écrite à 2026-11-18T21:46:32Z UTC : banc du bootstrap, corrections

- **Mesure archivée** : les modes de la racine et la composition de la couche sont relevés dans [`m1b-boot-modes.log`](m1b-boot-modes.log).
- **Portée** : `SOURCE_DATE_EPOCH`, la borne S et les exclusions suffisent sur le banc. Seules 8 exclusions sont montrées nécessaires (journaux de dnf, `history.sqlite*`, `aux-cache`). `etc/machine-id` et `var/cache/dnf` viennent de la base et sont exclus par choix. La référence `28634a12…` vaut pour la liste large.
- **Origine du 0555 de S1** : c'est une hypothèse (lecture de `s1.sh`), non mesurée.

## Note datée du 18/11/2026, écrite à 2026-11-18T21:54:22Z UTC : relances d'un autre jour, plan et prédictions

- **Plan** : à partir du 19/11, relancer sans modification `m1b-outil-amorce.sh`, `m1b-boot.sh`, `m1b-outil.sh` et `m1b-repro3.sh`, chacun vers un journal neuf (`-j2.log`). Comparer ensuite aux quatre références du 18/11 avec [`m1b-autre-jour.sh`](m1b-autre-jour.sh).
- **Écart de méthode** : `m1b-sans-machine-id.sh` fixe en dur les arbres du 18/11. La référence `05d35d64…` se compare donc par un ré-archivage dans `m1b-autre-jour.sh`, avec la même fonction et les mêmes exclusions.
- **Prédictions** : AJ0 (banc du script, ce soir) et AJ1 à AJ7 ([détail](m1b-predictions.md)). Le point 1 A reste non établi.

## Note datée du 18/11/2026, écrite à 2026-11-18T21:55:08Z UTC : banc du script de comparaison

- **AJ0 tenue** : sur les dossiers du 18/11, `m1b-autre-jour.sh` retrouve les quatre références (8 OK). La branche « écart » n'est pas exercée. Les relances restent à faire à partir du 19/11 ([détail](m1b-predictions.md), [journal](m1b-autre-jour-banc.log)).

## Note datée du 19/11/2026, écrite à 2026-11-19T00:07:51Z UTC : relances d'un autre jour

- **AJ1 à AJ7 tenues** : les quatre bancs relancés le 19/11 UTC (00:00:38 à 00:06:05) redonnent les quatre références du 18/11 (`05d35d64…`, `06c289ad…`, `0c00666a…`, `28634a12…`), 8 OK sur 8 ([détail](m1b-predictions.md), [journal](m1b-autre-jour.log)).
- **Intervalle réel** : 140 à 229 min, un autre jour UTC et non 24 h.
- **Le point 1 A reste non établi** (ni pod Kata, ni autre hôte). Suite : les valeurs de la carte, à décider avec le propriétaire.

## Note datée du 19/11/2026, écrite à 2026-11-19T08:33:55Z UTC : valeurs de S1 relevées avant la question

- **Relevé** (08:33:20 à 08:33:25 UTC, lecture seule) : [`m1b-valeurs-s1.sh`](m1b-valeurs-s1.sh), [journal](m1b-valeurs-s1.log). Les deux faits d'archive ont d'abord été vus par un `tar -tvf` non archivé, juste avant l'écriture du script.
- **machine-id dans S1** : `racine.tar` a un `etc/machine-id` rempli (33 octets, mode 0444), écrit à l'installation. `boot-racine.tar` a un fichier vide (0 octet, mode 0644), qui vient de la base. Les quatre références du banc l'excluent : aucune ne contient de fichier vide.
- **Mode de la racine** : `.` vaut 0555 dans les deux archives de S1 et dans les couches des deux registres de banc. La couche faite par `crane append` garde donc le membre `.` et son mode : ce mode entre dans le digest de l'image. Les références du banc ont 0775 (`mkdir` de l'hôte) ; aucune n'a le mode de S1.
- **Précision** : la remarque « la couche n'a pas de membre `.` » de [`m1b-boot-modes.log`](m1b-boot-modes.log) porte sur la couche amont de Rocky (`812c4412`), pas sur une couche faite par la brique.
- **umask** : celui du pod n'est pas relevé. Ce qui est mesuré : sous 022, le banc redonne le mode de `var/lib/dnf` de `racine.tar`.

## Correction datée du 19/11/2026, écrite à 2026-11-19T08:36:06Z UTC : second relevé des valeurs

- **Relevé** (début 08:35:39 UTC, lecture seule) : [`m1b-valeurs-s1-2.sh`](m1b-valeurs-s1-2.sh), [journal](m1b-valeurs-s1-2.log). Il s'est arrêté avec le code 127 dans sa dernière section : `rpm` n'est pas sur l'hôte. Le mode que le paquet `filesystem` donne à `/` n'est donc pas lu. Les sections précédentes sont complètes.
- **Correction** : la note de 08:33:55 UTC dit « Les références du banc ont 0775 ; aucune n'a le mode de S1 ». C'est faux pour trois des quatre. `.` vaut 0555 dans `a8` (`06c289ad…`), `b5` (`05d35d64…`) et `a3` (`0c00666a…`), comme dans S1. Seule `x1` (`28634a12…`, bootstrap) a 0775.
- **Précision** : « qui vient de la base » est désormais mesuré. La couche amont `812c4412` a un `etc/machine-id` vide (0 octet, mode 0644). « Écrit à l'installation », pour `racine.tar`, reste seulement cohérent avec le `%post` de systemd lu sur le banc.
- **machine-id** : il est absent des quatre références (`a8`, `b5`, `a3`, `x1`).

## Décision du 19/11/2026, consignée à 2026-11-19T08:39:00Z UTC : machine-id absent

**Décision du propriétaire** (réponse reçue avant 2026-11-19T08:39:00Z UTC, heure exacte non relevée) : « Absent ». La question était : « Pour etc/machine-id dans les images de M1b : absent ou vide ? ».

- **Recommandation présentée** (passée par le conseiller) : « absent », seule valeur appuyée par une mesure archivée, sur les quatre références et deux jours UTC.
- **Valeurs annoncées comme fixées dans la tâche, sans question** : `%_install_langs` à `en_US`, umask 022, racine de l'archive en 0555.
- **Conséquence** : la référence du bootstrap `28634a12…` a sa racine en 0775. Elle est à refaire avec la racine en 0555, par ré-archivage des arbres existants, sans nouvelle installation. Les trois autres références ont déjà 0555 et machine-id absent.
- **Portée** : rien n'est mesuré dans le pod Kata ; le point 1 A reste non établi. Ce n'est un accord pour aucune écriture dans le cluster ni dans Zot.

## Note datée du 19/11/2026, écrite à 2026-11-19T08:41:01Z UTC : référence du bootstrap en 0555

- **BR0 à BR6 tenues** (08:40:18 à 08:40:23 UTC) : la copie des arbres du 18/11, racine passée en 0555, donne deux fois la même archive, `f2652169…`. Elle ne diffère de `28634a12…` que par le mode de `.` ([résultat](m1b-predictions.md), [journal](m1b-boot-0555.log)).
- **Références pour les valeurs fixées le 19/11** : `05d35d64…` (outils de `99790c13`), `06c289ad…` (outils de l'amorce), `0c00666a…` (racine), `f2652169…` (bootstrap). Toutes ont la racine en 0555 et machine-id absent.
- **Le point 1 A reste non établi** (ni pod Kata, ni autre hôte).

## Correction datée du 19/11/2026, écrite à 2026-11-19T08:46:59Z UTC : rôle des quatre références

- **Ce qui est faux** : la note de 08:41:01 UTC range les quatre archives sous « Références pour les valeurs fixées le 19/11 ». Seules deux correspondent à ces valeurs.
- **Ce qui est mesuré pour les quatre** : la racine est en 0555 et `etc/machine-id` est absent ([`m1b-valeurs-s1-2.log`](m1b-valeurs-s1-2.log), [`m1b-boot-0555.log`](m1b-boot-0555.log)).
- **Cibles** :
  - `06c289ad…` pour l'outillage (outils de l'amorce, `en_US`, umask 022) ;
  - `f2652169…` pour le bootstrap.
- **Témoins seulement** :
  - `05d35d64…` : outils de `99790c13`, langues `all`, umask 0002 ;
  - `0c00666a…` : troisième banc, 26 533 membres contre 13 332 pour `a8` ; ses langues et son umask ne sont pas établis dans cette carte.
- **Archives écrites par le `tar` de l'hôte** : les quatre références viennent de la fonction `archive()` des bancs (`ns tar`). La tâche archivera avec le `tar` de l'amorce : ce point est à mesurer avant le pod.

## Note datée du 19/11/2026, écrite à 2026-11-19T08:49:18Z UTC : tar de l'amorce

- **Mesure** (08:47:46 UTC) : réarchivé par le `tar` 1.34 de l'amorce, l'arbre `i8` donne `7c07083c…`, contre `06c289ad…` avec le `tar` 1.35 de l'hôte. Les membres, les en-têtes pax et les contenus sont égaux. Seuls `devmajor` et `devminor` diffèrent, vides contre `0000000`, ainsi que la somme de chaque en-tête ([résultat](m1b-predictions.md), [journal](m1b-tar-amorce.log), [écarts](m1b-tar-amorce-ecart.log)).
- **Cibles mises à jour** :
  - outillage : `7c07083c…`, avec le `tar` de l'amorce, pour le pod et la tâche ;
  - bootstrap : `f2652169…` reste une archive du `tar` de l'hôte ; elle est à refaire avec le `tar` de l'image qui l'archivera.
- **Ce n'est un accord** pour aucune écriture dans le cluster ni dans Zot.

## Note datée du 19/11/2026, écrite à 2026-11-19T10:46:01Z UTC : pods d'essai Kata, et lenteur de dnf

- **Outillage dans Kata** : `pod_a` (limite par défaut) et `pod_c` (limite de fichiers ouverts à 1 024) donnent l'archive `7c07083c…` au bit près, hors réseau ([`m1b-pod_a.log`](m1b-pod_a.log), [`m1b-pod_c.log`](m1b-pod_c.log)). La portée est étroite : l'outillage seul, deux pods du même nœud, le même jour, des entrées livrées par copie, la racine seule (ni couche de configuration, ni layout). Le point 1 A n'est donc pas établi au sens de la carte : il manque le bootstrap, un autre jour et la tâche elle-même. `pod_b` est en cours.
- **Lenteur** : dnf met 5 811 s dans `pod_a` et 40 s dans `pod_c`. La cause est mesurée : avant chaque scriptlet, rpm 4.16 ne peut pas ouvrir `/proc/self/fd` dans la racine installée. Il appelle alors `fcntl` sur chaque descripteur jusqu'à la limite dure, qui vaut 2³⁰ dans le pod ([banc de l'hôte](m1b-cloexec-banc.log), [lecture du source](m1b-rpm-cloexec.log)).
- **Remède retenu pour la tâche, révisable à la revue de `taches.yml`** : abaisser la limite souple, puis la limite dure, à 1 024, dans un sous-shell qui n'entoure que dnf. Seule la valeur 1 024 est mesurée.
- **Autres voies, non retenues** : monter `/proc` dans la racine installée (non mesuré, cela touche l'arbre et l'archivage) ; changer la limite par défaut du runtime de Kata (changement du cluster, à soumettre au propriétaire).
- **mock n'est pas concerné en pratique** : `mock --hermetic-build` dure de 46 à 54 s dans Kata dans les journaux archivés ([`m4c-essai.log`](m4c-essai.log) par exemple). Pourquoi la boucle ne le ralentit pas n'est pas mesuré.
- **Non remesuré** : les 5 694 s de l'étape `racine` et les 761 s de `boot_racine` de S1. La même cause y est probable.
- **Point ouvert, distinct de la vitesse** : `var/lib/rpm/rpmdb.sqlite-shm` a varié entre deux installations de l'hôte avec `keepcache=0` ([comparaison](m1b-cloexec-comparaison.log)). Il n'a pas varié entre le banc des sondes, `pod_a` et `pod_c`. C'est un risque pour la reproductibilité ; l'exclure n'est pas décidé.

## Décision du 19/11/2026, consignée à 2026-11-19T10:51:48Z UTC : « Mesurer aussi /proc »

**Décision du propriétaire** (réponse reçue avant 2026-11-19T10:51:48Z UTC, heure exacte non relevée) : « Mesurer aussi /proc ». La question était : « Pour la tâche : limite seule, ou mesurer aussi /proc ? ». Ma recommandation, passée par le conseiller, était la limite seule.
- **Conséquence** : la voie « `/proc` monté dans la racine installée », notée « non retenue » dans la note précédente, est mesurée par un pod à part, `pod_d`, après `pod_b`. Le remède de la tâche sera choisi ensuite, sur les deux mesures.
- **Ce n'est un accord** pour aucune écriture dans Zot ni pour aucun changement du cluster. Le pod d'essai est lancé sous l'accord permanent du 18/11.

## Note datée du 19/11/2026, écrite à 2026-11-19T12:25:00Z UTC : les deux mesures sont faites

Cette note complète, sans la réécrire, la note « pods d'essai Kata, et lenteur de dnf ». Celle-ci disait de `/proc` dans la racine « non mesuré », et de la limite « remède retenu ». Le choix reste au propriétaire, sur les deux mesures.

- **`pod_b`** redonne `7c07083c…` au bit près (dnf 5 724 s), et `p-a.tar` = `p-b.tar` ([`m1b-comparer.log`](m1b-comparer.log)). Trois pods Kata (a, b, c) donnent donc la même archive de l'outillage. La portée reste celle des prédictions : même nœud, même jour, racine seule.
- **Limite de fichiers ouverts à 1 024** (`pod_c`) : 40 s, même archive `7c07083c…`.
- **`/proc` monté dans la racine installée** (`pod_d`) : 40 s aussi, mais une autre archive (`fb33228f…`, un seul passage) :
  - 20 chemins déclarés dans `tmpfiles.d` (dossiers vides, `btmp`, `wtmp`, `lastlog`, lien `/var/log/README`) ;
  - `./proc` en 755 ;
  - deux mtimes ([écarts](m1b-pod_d-ecarts.log), [tmpfiles.d](m1b-pod_d-tmpfiles.log)).
- **Le vrai constat** : le contenu de l'image ne dépend pas de la limite de fichiers ouverts, mais de la présence de `/proc` dans la racine installée. C'est une entrée implicite de la construction, désormais mesurée.
- **S1** : aucun des 20 chemins n'est dans `racine.tar` ni dans `boot-racine.tar` ([`m1b-pod_d-s1.log`](m1b-pod_d-s1.log)). Les images de M2 à M4c avaient donc le contenu « sans `/proc` ».
- **Le revers de « sans `/proc` »** : la création des chemins de `tmpfiles.d` y échoue en silence, et la limite seule fige ce contenu-là. Pour une racine de construction où systemd ne démarre pas, l'effet n'est pas mesuré.
- **mock** : `pod_d` rend cohérente l'hypothèse que mock ne boucle pas parce qu'il monte `/proc` dans son chroot. C'est cohérent, non mesuré pour mock.
- **Recommandation** (passée par le conseiller) : la limite seule. Elle garde les références et le contenu des images déjà éprouvées, sans montage dans l'arbre. `/proc` monté demanderait de refaire les références, et un second `pod_d` pour établir sa reproductibilité. Ce n'est pas une décision.

## Décision du 19/11/2026, consignée à 2026-11-19T12:27:41Z UTC : « Limite seule »

**Décision du propriétaire** (réponse reçue avant 2026-11-19T12:27:41Z UTC, heure exacte non relevée) : « Limite seule ». La question était : « Quel remède pour la tâche ? », entre la limite de fichiers ouverts et `/proc` monté dans la racine installée. Ma recommandation, passée par le conseiller, était la limite seule.

- **Conséquence pour la tâche à venir** :
  - la tâche abaisse la limite de fichiers ouverts à 1 024, la souple puis la dure, dans un sous-shell qui n'entoure que dnf ;
  - elle n'y monte pas `/proc` ;
  - elle affiche la limite et la durée de dnf, et refuse de continuer si la limite dure dépasse le seuil ;
  - seule la valeur 1 024 est mesurée (`pod_c`).
- **Les références ne changent pas** : la cible de l'outillage reste `7c07083c…`. Le contenu « sans `/proc` » est celui des racines de S1.
- **Reste ouvert** :
  - le patch à part de `s1.sh`, la même limite autour de dnf aux étapes `racine` et `boot_racine` ;
  - l'exclusion éventuelle de `var/lib/rpm/rpmdb.sqlite-shm` ;
  - la référence du bootstrap, à refaire avec le tar de l'image qui archivera.
- **Révisable** à la revue de `taches.yml`, qui reste soumise au propriétaire. Ce n'est un accord pour aucune écriture dans Zot ni pour aucun changement du cluster.

## Note datée du 19/11/2026, écrite à 2026-11-19T12:37:39Z UTC : validation du conseiller sur « Limite seule », et corrections

À la demande du propriétaire (« fait valider par l'advisor »), le conseiller a relu la décision. **Il la confirme** : aucune mesure ne plaide pour `/proc`. Il demande trois corrections des deux notes précédentes, faites ici sans les réécrire.

**Corrections.**
- **« Le contenu sans `/proc` est celui des racines de S1 »**, et « les images de M2 à M4c avaient le contenu sans `/proc` » : c'est trop fort. La mesure dit seulement que les 20 chemins sont absents des racines de S1. Le reste n'est pas comparé : `racine.tar` de S1 a 13 341 membres et 361 758 720 octets, la cible `7c07083c…` 13 332 membres et 343 930 880 octets. Il faut lire « sur ces 20 chemins seulement ».
- **« Refaire les références »** : c'est trop large. La référence du bootstrap est à refaire de toute façon (tar de l'image qui archivera). Le coût propre à `/proc` est :
  - la cible de l'outillage ;
  - les relances « autre jour » déjà préparées ;
  - un second `pod_d` pour la reproductibilité.
- **« La création des chemins de `tmpfiles.d` échoue en silence »** : il faut lire « n'a pas lieu ; le mécanisme n'est pas lu ».

**Arguments ajoutés.**
- **Privilège** ([`m1b-pod_d-amont.log`](m1b-pod_d-amont.log), [script](m1b-pod_d-amont.sh)) : le montage de `/proc` a été permis par le `securityContext` du pas `construire` de la tâche signée, que reprend le pod d'essai (`privileged: true`). Baisser une limite ne demande aucun droit ; `mount -t proc` en demande un.
  - Dans le gabarit actuel, le pas est déjà privilégié pour mock, donc l'argument ne vaut que pour une tâche d'installation moins privilégiée.
  - Que dnf passe sans ce droit n'est pas mesuré.
- **Entrée implicite** : un `/proc` réel expose aux scriptlets le noyau, les CPU et la mémoire du nœud. C'est une source d'écart possible entre nœuds, au sens de l'ADR 0007. C'est structurel, non mesuré.
- **Le revers est borné** : la comparaison membre à membre est exhaustive. L'écart entre `pod_d` et `a8` se limite à 20 chemins et 3 champs. Les racines de S1, sans ces 20 chemins, ont servi aux constructions de M2 à M4c. C'est une mesure d'usage, limitée à ces constructions. Elle remplace « je n'attends pas d'effet ».

**Lecture de l'image amont, non probante** : la couche `812c4412…` (11 170 membres) n'a aucun des 20 chemins. Mais elle ne contient ni `usr/lib/tmpfiles.d/systemd.conf` ni systemd. Elle ne dit donc pas ce que Rocky publie quand systemd est installé.

**La décision « Limite seule » ne change pas.**

## Note datée du 19/11/2026, écrite à 2026-11-19T12:43:34Z UTC : patch de `s1.sh` reclassé

La note « Limite seule » rangeait sous « Reste ouvert » un patch à part de `s1.sh` : la même limite autour de dnf aux étapes `racine` et `boot_racine`. Le propriétaire a répondu « continue » à la proposition de le préparer, puis de refaire la référence du bootstrap. **Le patch n'est pas préparé.** Il est reclassé : utile seulement si S1 est relancé.

- **Aucun appelant** : `rejeu.sh` de la 08 ne lance que `s1.sh amorce` de la 06, et rien de la 05. Le `Makefile` ne cite pas la 05. Relevé par `git grep` à 2026-11-19T12:43:34Z UTC.
- **Ce qui remplace ces étapes** : M1b construit l'outillage et le bootstrap par deux tâches neuves de la plateforme. Leurs étapes durables entreront dans `rejeu.sh` à la place des images d'essai (point 5 de cette carte). La limite y sera posée par la tâche (décision « Limite seule »).
- **`s1.sh` n'est pas touché** : son empreinte, `362af7ef…`, est citée par les bancs archivés.
- **Non remesuré** : les 5 694 s de `racine` et les 761 s de `boot_racine` de S1. La même cause y reste probable, sans mesure.
- **Suite** : la référence du bootstrap avec le tar de l'amorce, puis un pod d'essai du bootstrap dans Kata, sous la limite posée autour de dnf seul.

## Note datée du 19/11/2026, écrite à 2026-11-19T12:46:03Z UTC : cible du bootstrap avec le tar de l'amorce

- **Nouvelle cible du bootstrap** : `b063feb3…`. Elle remplace `f2652169…`, écrite par le `tar` de l'hôte. Le contenu est le même (0 écart membre à membre) ; seuls les champs `devmajor` et `devminor` changent ([résultat](m1b-predictions.md), [journal](m1b-boot-amorce.log)).
- **Cibles pour le pod et la tâche** : `7c07083c…` pour l'outillage, `b063feb3…` pour le bootstrap.
- **Suite** : le pod d'essai du bootstrap dans Kata, sous la limite de fichiers ouverts posée autour de dnf seul.

## Correction datée du 19/11/2026, écrite à 2026-11-19T12:49:53Z UTC : langue du bootstrap

- **Ce qui est faux** : la correction de 08:46:59 UTC range `f2652169…` parmi les cibles, et la note précédente donne `b063feb3…` comme cible du bootstrap pour le pod et la tâche. Or cet arbre a été installé avec les langues `all` (outils de `a8`, comme S1), et non `en_US`, valeur annoncée le 19/11 dans la décision « Absent » ([détail](m1b-predictions.md)).
- **Correction** : `b063feb3…` est la cible du bootstrap seulement si sa langue est `all`. Ce choix revient au propriétaire. L'outillage reste en `en_US` (`7c07083c…`).
- **Deux variables** : la langue (`all` contre `en_US`) et les outils (libsolv `0.7.24-6` dans `a8`, `0.7.24-4` dans l'amorce). La tâche peut poser la langue elle-même, quelle que soit l'image (ADR 0007). Un banc de l'hôte les sépare avant la question.
- **Le pod du bootstrap attend** ce banc et ce choix.

## Note datée du 19/11/2026, écrite à 2026-11-19T12:52:51Z UTC : langue du bootstrap, mesure

- **Avec `all` posée explicitement**, la racine d'outils de l'amorce (libsolv `-4`, `tar` 1.34, sonde du pod, limite autour de dnf seul) redonne la référence `b063feb3…` octet pour octet. Seule la langue distingue les deux outils pour le bootstrap ([résultat](m1b-predictions.md), [journal](m1b-boot-langue.log)).
- **Avec `en_US`** : `4171b0d3…`, avec 87 fichiers `.mo` de moins, dont 55 `dnf.mo` que la base nue avait, et un autre `rpmdb.sqlite` ([listes](m1b-boot-langue-listes.log)).
- **Les deux listes `rpm -qa`** sont celles de S1 (153 lignes).
- **Défaut du banc** : `cmp` est absent de l'amorce. La comparaison des listes a été faite ensuite sur l'hôte, et la sonde du pod ne doit pas compter sur `cmp`.
- **Question au propriétaire** : la langue du bootstrap, `all` comme S1, ou `en_US` comme annoncé le 19/11.

## Note datée du 19/11/2026, écrite à 2026-11-19T12:55:19Z UTC : règle des langues, avant la question

- **Correction** de la note de résultat LG : voir la correction datée dans les prédictions. « Le bootstrap que mock a utilisé » se limite aux langues et à la liste de paquets ; l'écart de `en_US` porte sur des fichiers, pas sur des paquets.
- **Ce que garde chaque image dans S1**, d'après les journaux archivés :
  - **outillage** : `en_US`, outils de l'amorce. `a8` a 34 membres sous `usr/share/locale`, comme `racine.tar` ([`m1b-outil-amorce.log`](m1b-outil-amorce.log)) ;
  - **bootstrap** : `all`, outils de `99790c13`. `b063feb3…` a 2 608 membres, comme `boot-racine.tar` ([`m1b-boot.log`](m1b-boot.log)).
- **Recommandation** (passée par le conseiller) : une règle, pas une exception. Chaque image garde la langue qu'elle avait dans S1, posée explicitement par la tâche (`.rpmmacros` sous `env -i`) : `en_US` pour l'outillage, `all` pour le bootstrap.
- **Le revers** : `all` pour le bootstrap contredit la valeur `en_US` annoncée le 19/11 dans la décision « Absent ».

## Décision du 19/11/2026, consignée à 2026-11-19T12:59:38Z UTC : « all, comme S1 »

**Décision du propriétaire** (réponse reçue avant 2026-11-19T12:59:38Z UTC, heure exacte non relevée) : « all, comme S1 ». La question était : « Quelle langue pour le bootstrap ? », entre `all` comme S1 et `en_US` comme annoncé le 19/11. Ma recommandation, passée par le conseiller, était `all`.

- **Règle** : chaque image garde la langue qu'elle avait dans S1, posée explicitement par la tâche (`.rpmmacros` dans un `HOME` à elle, sous `env -i`) :
  - `en_US` pour l'outillage, cible `7c07083c…` ;
  - `all` pour le bootstrap, cible `b063feb3…`.
- **La valeur `en_US` annoncée le 19/11** dans la décision « Absent » ne vaut donc que pour l'outillage.
- **Suite** : le pod d'essai du bootstrap dans Kata, avec la sonde du banc de la langue, sous la limite autour de dnf seul.
- **Ce n'est un accord** pour aucune écriture dans Zot ni pour aucun changement du cluster. Le pod d'essai est lancé sous l'accord permanent du 18/11.

## Note datée du 19/11/2026, écrite à 2026-11-19T13:03:47Z UTC : bootstrap dans Kata, résultat

- **`pod_e`** redonne `b063feb3…` octet pour octet, hors réseau, en 5 s de dnf sous la limite autour de dnf seul, avec la langue `all` posée par la tâche ([résultat](m1b-predictions.md), [journal](m1b-pod_e.log)).
- **Les deux racines de M1b sont reproduites dans Kata** : l'outillage `7c07083c…` (`pod_a`, `pod_b`, `pod_c`) et le bootstrap `b063feb3…` (`pod_e`). La portée reste étroite : même jour, même nœud, entrées par copie, racine seule.
- **Reste pour le point 1 A** : un autre jour dans Kata (après 00:00 UTC le 20/11), puis la tâche elle-même, avec couche de configuration et layout.
- **Ce qui suit** dans la carte : les deux tâches neuves (prefetch runc et constructeur Kata sans sortie), chacune avec son pod d'essai, puis leurs changements du cluster, chacun avec son accord (point 4).

## Note datée du 19/11/2026, écrite à 2026-11-19T13:44:07Z UTC : tâches neuves, préparation à sec

- **Écrites** : `prefetch-racine-rpm`, `construire-racine-rpm` et le gabarit `builder-rpm` (dossier [`builders/`](../builders/)), avec [`m1b-builders.sh`](../m1b-builders.sh). [Prédictions TQ, TC, EP et EC](m1b-predictions.md).
- **Forme mesurée d'abord sur l'hôte** :
  - outils et clés de l'amorce ([relevé](m1b-amorce-outils.log)) ;
  - outillage sous la forme de la tâche, `7c07083c…` retrouvé ([résultat](m1b-outil-forme.log)).
- **Deux choix sont à poser au propriétaire avant toute signature.** Les changer après coûterait une signature et une revue de plus.
  1. Le paramètre `racine` : la pipeline fixe le sha256 attendu de la racine, et la tâche s'arrête s'il diffère. Un rejeu qui ne reproduit pas échoue alors au lieu de publier un autre digest.
  2. Aucun résultat `*_ARTIFACT_INPUTS` dans le prefetch : les ancres (sha256 des `repomd.xml`, couche de base) ne sont que des paramètres de la pipeline signée. `prefetch-rpm` déclare au moins l'image de bootstrap. Ici, la base `ee90dc0e…` du bootstrap pourrait l'être de même.
- **Changements du cluster**, à soumettre un par un, chacun avec son accord :
  - sortie de `prefetch-racine-rpm` (DNS, adresses publiques en 443, Zot), et son ajout au `NotIn` de `builds-sans-internet` ;
  - politique sans sortie de `construire-racine-rpm`, posée avant son premier TaskRun.

  L'admission à blanc sous ces labels neufs est relevée par les essais.
- **Ensuite** : signature (`SIGNER=1`) et revue de `taches.yml` par le propriétaire, deux PipelineRuns par image (même digest), provenance.

## Note datée du 19/11/2026, écrite à 2026-11-19T13:56:06Z UTC : tâches neuves, essais

- **Tenus** ([résultat](m1b-predictions.md)) : le prefetch runc écrit, sur un PVC, des entrées égales à celles des bancs, fichier par fichier. Le constructeur Kata, sans réseau, les relit et retrouve les deux racines. Il donne les mêmes digests d'image que le banc de l'hôte : `70f8c412…` pour l'outillage et `6de899ac…` pour le bootstrap.
- **Un correctif en route** : `^` est admis dans les noms de rpm (`passt`), et la relance a eu lieu sous `m1bt2`.
- **Admission** : les deux pods seraient admis à blanc sous les labels neufs.
- **Reste avant signature** :
  - les deux choix de la note précédente (paramètre `racine`, résultat `*_ARTIFACT_INPUTS`) ;
  - les deux politiques réseau, avec le `NotIn` de `builds-sans-internet`, chacune sur accord ;
  - puis `SIGNER=1` et la revue de `taches.yml`.
- **Autre jour** : relance des pods de l'outillage et du bootstrap à partir de 00:00 UTC le 20/11, sous l'ancienne forme, à part de la forme de la tâche.

## Note datée du 19/11/2026, écrite à 2026-11-19T13:58:26Z UTC : avant signature, ordre et points ouverts

- **Portée des essais, précisée** : aucune des deux images n'a été poussée, tirée ni exécutée. Les essais établissent le digest et un layout valide, relu par python et oras, et rien de plus. Les images ne sont pas « prêtes ».
- **Ordre proposé** : aucune signature avant la mesure d'un autre jour. Les écritures dans Zot sont définitives, et le paramètre `racine` ferait échouer la tâche si l'autre jour ne reproduisait pas. À partir de 00:00 UTC le 20/11, deux relances sont prévues :
  - l'ancienne forme (pods de l'outillage et du bootstrap), comme témoin ;
  - `m1b-builders.sh`, sous un préfixe neuf, puisque c'est la forme de la tâche qui serait signée.
- **Points ouverts avant signature, aucun n'est mesuré** :
  - validation par Tekton : les deux tâches et les deux pipelines rendues, en `--dry-run=server`, comme `m4b-taches-admission`. Les noms de paramètres à tiret bas et le champ `resources` n'ont jamais été vus par le webhook ;
  - refus : aucun cas refusé n'est mesuré. À jouer au moins une `racine` fausse et un rpm altéré au banc, et un `repomd` faux dans un pod de prefetch, comme le cas refusé d'`essai_tache` de M4b ;
  - annotation de base du bootstrap : `base.digest ee90dc0e…` est écrite dans le manifeste, alors que seule la couche `812c4412…` est contrôlée. Un remède possible, non retenu : le prefetch lirait le manifeste `ee90dc0e…` dans Zot, contrôlerait son sha256 et en tirerait la couche. C'est lié au choix 2, à poser après lecture, dans la source de Tekton v1.15.5, du sort d'un résultat objet déclaré mais non écrit ;
  - docs/04 n'a de ligne ni pour curl ni pour GnuPG, que le prefetch utilise depuis l'amorce. `prefetch-rpm` les utilise déjà, depuis l'image de M3. À vérifier comme dnf l'a été.

## Note datée du 19/11/2026, écrite à 14:06:10 UTC : résultat objet déclaré mais non écrit, lecture de Tekton v1.15.5 et de Chains v0.29.9

Cette note prépare le choix 2 de la note « avant signature ». Elle ne change aucune tâche.

**Lecture** : [`m1b-tekton-resultat-absent.sh`](m1b-tekton-resultat-absent.sh), journal [`m1b-tekton-resultat-absent.log`](m1b-tekton-resultat-absent.log) (14:05:15 UTC, code 0).
- Trois fichiers ont été téléchargés au tag v1.15.5 depuis `raw.githubusercontent.com/tektoncd/pipeline`, à côté de `script.go`. Rien n'en est exécuté.

  | Fichier | Octets | sha256 |
  |---|---|---|
  | `pkg/reconciler/taskrun/validate_taskrun.go` | 13 462 | `ce6bbea0…` |
  | `pkg/entrypoint/entrypointer.go` | 29 618 | `9c4ad23f…` |
  | `pkg/pod/status.go` | 39 464 | `ecd337d0…` |

- Chains est lu dans la copie locale v0.29.9 (`signable.go`, `ec115244…`).
- Le premier passage, [`m1b-tekton-resultat-absent-1.log`](m1b-tekton-resultat-absent-1.log) (14:04:57 UTC), n'extrayait pas `findMissingKeys`. Le second l'ajoute, sans autre changement.

**Ce qui est lu** :
- **Entrypoint** (`readResultsFromDisk`, lignes 450 à 452) : un fichier de résultat absent est sauté (`os.IsNotExist`, puis `continue`).
- **Reconciler** (`validateTaskRunResults`) : il fait deux contrôles, et tous deux ne parcourent que `tr.Status.Results`, c'est-à-dire les résultats émis (lignes 305 et 332).
  - le contrôle du type ;
  - le contrôle des clés d'objet. `findMissingKeys` parcourt les clés fournies (ligne 150) : un résultat objet déclaré mais absent n'y est jamais signalé.
- **`status.go`** : aucune ligne ne parle de résultat manquant. C'est un grep, pas une lecture complète.
- **Chains** : il ne parcourt que les résultats émis, par suffixe `ARTIFACT_INPUTS`. Il ignore un résultat sans objet (`isStructuredResult`, ligne 346).

**Conclusion de lecture, non mesurée** : une tâche qui déclare `*_ARTIFACT_INPUTS` sans l'écrire (l'outillage, qui n'a pas de couche de base) ne devrait pas échouer pour cela. Chains n'inscrirait rien.

**Ce qui n'est pas lu ni mesuré** :
- la résolution des références de résultats côté PipelineRun. Aucune tâche de `builder-rpm` ne lirait ce résultat ;
- aucun TaskRun réel n'a déclaré un résultat sans l'écrire.

**Forme de `prefetch-rpm`, signée** : `BOOTSTRAP_ARTIFACT_INPUTS`, objet `uri` et `digest`, avec l'uri `oci://<référence sans digest>` et le digest du manifeste. Il est écrit après le contrôle « manifeste de l'image de bootstrap égal au digest de la source ».

**Portée de ce qui serait déclaré** : `porte.rego` ne juge que les résultats de `_attendues` (`preparer-entrees` et `preparer-deb`). Une entrée du prefetch rpm serait inscrite dans `resolvedDependencies`, mais aucune règle ne la jugerait.

**Le choix 2 a trois options** :
- **(a) Rien déclarer**, l'état actuel. Les ancres restent des paramètres de la pipeline signée. L'annotation `base.digest ee90dc0e…` reste non vérifiée.
- **(b) Déclarer ce qui est contrôlé aujourd'hui**, la couche `812c4412…`. Mais c'est un blob, pas une image : une uri `oci://` portant ce digest serait trompeuse.
- **(c) Faire comme `prefetch-rpm`** : le prefetch lit dans Zot le manifeste `ee90dc0e…`, contrôle son sha256, en tire la couche et déclare l'image.
  - Cela règle le point ouvert de l'annotation.
  - Forme lue dans le cache OCI de l'hôte ([`m1b-base-manifeste.log`](m1b-base-manifeste.log), 14:06:30 UTC) : `ee90dc0e…` est un manifeste d'image (`application/vnd.oci.image.manifest.v1+json`, 573 octets) à une couche, `812c4412…`. Pas d'index à résoudre. Le dépôt est celui de l'annotation, `amont/rockylinux/rockylinux`.
  - En revanche, la tâche change : `prealables`, `banc` et `essai_prefetch` sont à rejouer avant la mesure d'un autre jour.

## Note datée du 19/11/2026, écrite à 14:09:16 UTC : correction datée de la note de 14:06:10, et coût de la vérification du manifeste

**Corrections** de la note « résultat objet déclaré mais non écrit » :
- **Heure.** Son en-tête dit 14:06:10 UTC. La ligne qui cite [`m1b-base-manifeste.log`](m1b-base-manifeste.log) (14:06:30 UTC) a été écrite après, avant le commit.
- **Ligne d'abord tronquée.** La première écriture de cette ligne avait perdu ses termes cités, par une erreur de shell de ma part. Elle a été récrite avant le commit.
- **Chains.** La phrase « il ne parcourt que les résultats émis » ne s'appuyait, dans le journal archivé, que sur `isStructuredResult`. La boucle est maintenant archivée dans [`m1b-chains-entrees.log`](m1b-chains-entrees.log) (14:08:49 UTC) :
  - `ExtractStructuredTargetFromResults` parcourt `objResults` (ligne 292) et retient les noms à suffixe `ARTIFACT_INPUTS` (ligne 293) ;
  - `RetrieveMaterialsFromStructuredResults` (ligne 263) en fait les matériaux.

**`prefetch-rpm` signée** (même journal) : elle contrôle le manifeste par `skopeo copy --preserve-digests`, puis compare son digest à celui de la source (ligne 123). skopeo est absent de l'amorce `rockylinux:9.8`. Dans `prefetch-racine-rpm`, la lecture se ferait donc par curl : `/v2/<dépôt>/manifests/sha256:<h>`, puis sha256 des octets lus. La lecture anonyme d'un manifeste dans Zot n'est pas mesurée. Celle du blob de la couche l'est.

**Coût de la vérification, sans la déclaration** : le manifeste serait lu dans `/tmp` du prefetch, pas dans le workspace. Le prefetch contrôlerait que sa couche unique est la couche fixée.
- **Ce qui ne change pas** :
  - `construire-racine-rpm` ;
  - ses revérifications ;
  - les comptes de 224 et 20 entrées.
- **Ce qui change** :
  - le paramètre `couche` du prefetch, qui prend le digest du manifeste en plus ;
  - le rendu des deux pipelines.
- **À rejouer sous un préfixe neuf** :
  - `prealables` et `banc`. Le banc ne joue que la construction, mais il est enchaîné aux autres étapes ;
  - `essai_prefetch`, puis `essai_construire`, qui lit le PVC du préfixe.

**Avec la déclaration** : `BASE_ARTIFACT_INPUTS`, sur la forme de `BOOTSTRAP_ARTIFACT_INPUTS`. Il serait écrit pour le bootstrap seulement. Le cas de l'outillage, déclaré mais non écrit, est lu dans le code et non mesuré. Il ne le serait qu'au premier PipelineRun de l'outillage, après signature. Si la lecture est fausse, il faut une signature et une revue de plus.

**Calendrier** : la mesure d'un autre jour porte sur la section dnf et tar du constructeur, que ce changement ne touche pas. Elle reste valable sur la forme actuelle, quelle que soit la réponse.

## Note datée du 19/11/2026, écrite à 14:12:23 UTC : décisions du propriétaire sur les deux choix d'avant signature

Réponses lues avant 14:12:23 UTC, aux deux questions posées après les notes précédentes :
- **Choix 1, « Garder l'arrêt »** : `construire-racine-rpm` garde le paramètre `racine`. La tâche s'arrête si la racine construite diffère du sha256 fixé par la pipeline (`7c07083c…` pour l'outillage, `b063feb3…` pour le bootstrap).
- **Choix 2, « Vérifier et déclarer »** : le prefetch lit dans Zot le manifeste de base du bootstrap (`amont/rockylinux/rockylinux@sha256:ee90dc0e…`) et en contrôle le sha256. Il contrôle aussi que sa couche unique est la couche fixée (`812c4412…`), puis écrit `BASE_ARTIFACT_INPUTS` sur la forme de `BOOTSTRAP_ARTIFACT_INPUTS` de `prefetch-rpm`.
  - L'outillage déclare ce résultat sans l'écrire. D'après le code lu, cela ne fait rien échouer, mais ce n'est pas mesuré avant la signature : c'est le reliquat accepté.
  - Aucune règle de la porte ne juge ce résultat.

**Suite** :
1. Changer `prefetch-racine-rpm` et le rendu des pipelines dans `m1b-builders.sh`. `construire-racine-rpm` ne change pas.
2. Écrire les prédictions et les commiter.
3. Rejouer `prealables`, `banc`, `essai_prefetch` et `essai_construire` sous un préfixe neuf.

La mesure d'un autre jour, à partir de 00:00 UTC le 20/11, reste prévue telle quelle.

## Note datée du 19/11/2026, écrite à 14:21:39 UTC : base vérifiée et déclarée, essais rejoués

- **Ce qui a été fait.** Le changement « Vérifier et déclarer » est fait, et `prealables`, `banc` et les deux essais sont rejoués sous `m1bt3`.
- **Résultat : BV1 à BV4 tenues.** Les détails sont dans [`m1b-predictions.md`](m1b-predictions.md).
- **Point ouvert fermé.** L'annotation `base.digest` est maintenant contrôlée.

**Restent avant signature** :
- la mesure d'un autre jour, à partir de 00:00 UTC le 20/11 ;
- le `--dry-run=server` par Tekton ;
- les cas refusés ;
- docs/04, pour curl et GnuPG ;
- les deux politiques de réseau, un accord pour chacune.

## Note datée du 19/11/2026, écrite à 14:24:33 UTC : correction de « point ouvert fermé »

La note précédente dépassait la mesure. Le prefetch contrôle le manifeste de son paramètre `couche`. L'annotation vient d'un autre paramètre, et rien ne reliait les deux. Le point ouvert reste donc ouvert jusqu'au contrôle de cohérence ajouté à `prealables`. La correction détaillée et la prédiction AN1 sont dans [`m1b-predictions.md`](m1b-predictions.md).

**Cas refusés à ajouter avant signature**, à jouer dans un pod de prefetch :
- un manifeste valide mais autre : celui de l'amorce `ed654c69…`, dont la couche est `99c753a8…`. Le prefetch doit s'arrêter sur « manifeste de base » ;
- le bon manifeste avec une couche fausse.

## Note datée du 19/11/2026, écrite à 15:33:13 UTC : mesure d'un autre jour, préparée

La mesure prévue à partir du 20/11 à 00:00 UTC tient en une commande : [`m1b-jour-kata.sh`](m1b-jour-kata.sh). Elle rejoue l'ancienne forme (`pod_c` et `pod_e`, sous `m1b-20`) et la forme de la tâche (`m1b-builders.sh`, sous `m1bt-20`), puis confronte 21 valeurs à celles du 19/11. Les scripts ne changent pas. Les prédictions JK1 à JK3 et JT1 à JT5, ainsi que la lecture d'un écart, sont dans [`m1b-predictions.md`](m1b-predictions.md). Aucune signature avant le résultat.

## Note datée du 19/11/2026, écrite à 15:47:22 UTC : cas refusés de la construction, et curl de l'amorce

- **Cas refusés de la construction, au banc : RZ1 à RZ8 tenues** ([`m1b-refus-banc.log`](m1b-refus-banc.log)). Une racine fixée fausse, et un rpm, une couche ou un `repomd.xml` altérés, sont refusés chacun par sa garde, sans sortie écrite. Restent les cas du prefetch, à jouer dans un pod : `repomd` faux, autre manifeste, bon manifeste avec une couche fausse.
- **curl** : ligne « À surveiller » ajoutée à docs/04. L'amorce exécute `curl-minimal-7.76.1-40.el9`, en retard de quatre révisions sur Rocky 9.8 : 9 corrections publiées par Rocky lui manquent, dont 4 de gravité « Medium » ([`m1b-curl-amorce.log`](m1b-curl-amorce.log)). **Nouveau point ouvert avant signature, à trancher par le propriétaire** : garder l'amorce figée avec ses contre-contrôles, ou rafraîchir le curl du prefetch.

**Restent avant signature** :
- la mesure d'un autre jour (à partir du 20/11 à 00:00 UTC) ;
- le `--dry-run=server` ;
- les trois cas refusés du prefetch ;
- le choix sur le curl de l'amorce ;
- la ligne GnuPG de docs/04 (session de la brique 09) ;
- les deux politiques de réseau, un accord pour chacune.

## Note datée du 19/11/2026, écrite à 15:54:36 UTC : cas refusés du prefetch joués

PX1 à PX5 tenues ([`m1b-refus-prefetch.log`](m1b-refus-prefetch.log)). Le point « les trois cas refusés du prefetch » de la note précédente est fait. Restent avant signature :
- la mesure d'un autre jour (à partir du 20/11 à 00:00 UTC) ;
- le `--dry-run=server` ;
- le choix sur le curl de l'amorce ;
- la ligne GnuPG de docs/04 (session de la brique 09) ;
- les deux politiques de réseau, un accord pour chacune.

## Note datée du 19/11/2026, écrite à 16:00:25 UTC : fraîcheur de l'amorce (D4 a)

Le point « choix sur le curl de l'amorce » devient « fraîcheur de l'amorce (D4 a) ». L'amorce `ed654c69…`, image du 25/05/2026, a 44 paquets sur 146 en retard sur Rocky 9.8, dont `ca-certificates` (un erratum « Critical »), `openssl-libs`, `glibc`, `python3` et curl. Au total, 54 errata de sécurité de Rocky sont plus récents qu'elle ([`m1b-amorce-fraicheur.log`](m1b-amorce-fraicheur.log)). `rpm`, `dnf` et `gnupg2` sont à jour. Les images construites ne sont pas touchées : elles sont installées depuis le miroir 9.8 fixé.

**Choix à poser au propriétaire avant `SIGNER=1`** :
- **(a)** amorce figée, en réserve mesurée ;
- **(b)** outillage des tâches rafraîchi, ce qui referait les références et la mesure d'un autre jour.

## Note datée du 19/11/2026, écrite à 16:11:17 UTC : validation par Tekton passée

TD1 à TD5 tenues ([`m1b-taches-admission.log`](m1b-taches-admission.log)) : les deux tâches et les deux pipelines rendues sous `m1bt3` sont admises en `--dry-run=server`, et deux témoins sont refusés par le décodage strict. Rien n'est créé. Le point « `--dry-run=server` » est fait. Restent avant signature :
- la mesure d'un autre jour (à partir du 20/11 à 00:00 UTC), où les sha256 des quatre rendus de `m1bt-20` seront à confronter à ceux de TD1 ;
- le choix sur la fraîcheur de l'amorce ;
- la ligne GnuPG de docs/04 (session de la brique 09) ;
- les deux politiques de réseau, un accord pour chacune.

## Note datée du 19/11/2026, écrite à 16:15:18 UTC : décision « (a) Figée » sur la fraîcheur de l'amorce

**Décision du propriétaire** (réponse « (a) Figée », lue le 19/11/2026 avant 16:15:18 UTC) : pour la première signature, les deux tâches gardent l'amorce `ed654c69…` figée par digest (D4 a). Son retard est une **réserve mesurée et acceptée** : 44 paquets sur 146 en retard sur Rocky 9.8, et 54 errata de sécurité plus récents ([`m1b-amorce-fraicheur.log`](m1b-amorce-fraicheur.log)). La mesure du 20/11, les références `7c07083c…` et `b063feb3…` et les prédictions JK et JT ne changent pas.

**Ce que couvre la réserve** :
- les altérations essayées sont refusées par leur garde : racine, rpm, couche, `repomd.xml` (RZ1 à RZ8) ; `repomd.xml`, manifeste et couche dans un pod de prefetch (PX1 à PX5) ;
- la construction tourne sans réseau, et toutes ses entrées sont fixées par sha256 ;
- le contenu construit vient du miroir 9.8 fixé, pas de l'amorce.

**Ce qu'elle ne couvre pas** :
- une exécution de code dans le pod de prefetch, par une réponse réseau hostile à curl ou openssl, n'est pas mesurée ;
- les pods signés portent le label `prefetch-racine-rpm`. Leur borne réseau dépend donc de la politique de sortie en attente d'accord (DNS, adresses publiques en 443, Zot), pas de `prefetch-rpm-sortie`, sous laquelle les pods d'essai ont tourné.

**Suite possible, non décidée et à mesurer** : une fois que M1b aura publié l'image d'outillage construite par la plateforme, une nouvelle version signée du prefetch pourrait tourner dessus. La construction resterait sur l'amorce. Rien ne montre encore que cette image fait tourner le prefetch en UID 65532 sous `restricted`, ni qu'elle donne une sortie égale à `attendu-*.sha256`.

**Restent avant signature** :
- la mesure d'un autre jour (à partir du 20/11 à 00:00 UTC), avec les sha256 des quatre rendus de `m1bt-20` à confronter à ceux de TD1 ;
- la ligne GnuPG de docs/04 (session de la brique 09) ;
- les deux politiques de réseau, un accord pour chacune.

## Note datée du 19/11/2026, écrite à 16:26:19 UTC : politiques réseau des tâches neuves, préparées

Les deux politiques sont écrites dans le dépôt, NON POSÉES :
- `prefetch-racine-rpm-sortie` (DNS, adresses publiques en 443, Zot), avec `prefetch-racine-rpm` ajouté au `NotIn` de `builds-sans-internet` ;
- `construction-racine-rpm-sans-sortie` (ni entrée ni sortie).

Elles se posent par `sortie-builds.sh` (08c), chacune par son étape et sur son accord : `m1b_sortie`, puis `m1b_sans_sortie`. Les témoins viennent ensuite, par `m1b_temoins`. Le contrôle sur le dépôt, `m1b_sec`, tient (NS1 et NS2, [`sortie-m1b_sec.log`](../../08c-durcissement/resultats/sortie-m1b_sec.log)).
- **Ordre** : après la mesure du 20/11, pour qu'elle tourne dans le même cluster que le 19/11.
- **Conséquence connue** : après `m1b_sortie`, `s1.sh prealables` attend toujours un `NotIn` à trois labels. Il sera à adapter avant le rejeu M5b.

**Restent avant signature** :
- la mesure d'un autre jour (à partir du 20/11 à 00:00 UTC, programmée à 00:01 UTC), avec les sha256 des rendus de `m1bt-20` à confronter à TD1 ;
- la ligne GnuPG de docs/04 (session de la brique 09) ;
- `m1b_sortie` et `m1b_sans_sortie`, un accord pour chacune, puis `m1b_temoins`.

## Note datée du 19/11/2026, écrite à 16:51:28 UTC : relevé avant la préparation de la signature

Le relevé [`m1b-avant-signature-releve.log`](m1b-avant-signature-releve.log) a été fait à 16:50:58 UTC, en lecture seule. Le premier passage, [`-1.log`](m1b-avant-signature-releve-1.log), est gardé : son motif ne lisait pas les références de la liste revue.

- **La ConfigMap `porte` du cluster est en retard sur le dépôt.**
  - `policy.yaml`, `policy-trusted-task.yaml` et `porte.rego` sont égaux.
  - `taches.yml` diffère : la ConfigMap a été écrite le 13/11 à 12:47:49 UTC (`managedFields`), et il lui manque les trois entrées ajoutées le 18/11 (`prefetch-rpm` `9afe09db…`, `preparer-rpm` `2f65f390…`, `construire-rpm` `d7f01398…`, commits `05e2fe8` et `1d5e27d`). Je l'ai vu en comparant la donnée déployée au dépôt, sans rien afficher d'autre.
  - Aucun journal de M4 ne l'avait relevé. La porte du cluster n'approuve donc encore aucune tâche rpm. Ce n'est pas un obstacle à la signature, mais à tout passage d'un artefact rpm par la porte.
  - La remettre à jour (`politique.sh`, étape de la porte) est un changement du cluster, qui te revient.
- **Zot**, sur `/` de sc-stockage (`/var/lib/zot` est sur le même système de fichiers) : 3 978 911 744 octets libres.
  - Le 18/11 à 09:23:32 UTC, il y en avait 4 476 362 752 (relevé avant `publier` de M4a), soit environ 497 Mo de moins en 31 h environ.
  - Les écritures de la brique depuis lors ne sont pas retranchées de ce chiffre. L'origine de la croissance de `/` reste non attribuée.
  - La garde des PipelineRuns de M4 vaut 1 Gio.
- **Liste revue** : `publier-fermeture` vaut `7fa92ad3…`, comme dans M4b. `prefetch-racine-rpm` et `construire-racine-rpm` n'y ont pas d'entrée, comme prévu avant la signature.

**Effort de M1b**, par les dates d'auteur des commits qui nomment M1b :
- 119 commits, du 18/11 à 19:38:40 UTC au 19/11 à 16:26:20 UTC, sur deux jours de commits ;
- somme des écarts entre commits consécutifs : 6,45 h pour les écarts de 30 min au plus, 7,57 h pour ceux de 60 min au plus.

L'estimation de la carte est « 3 j, décision à 6 ».

## Note datée du 19/11/2026, écrite à 18:00:37 UTC : ligne GnuPG de docs/04, écrite

À ta demande (« Oui, demande-lui »), la session de la brique 09 a fourni son verdict proposé : « À surveiller, chemin critique ». Je l'ai relu dans ses journaux, sur sa branche non fusionnée `claude/brique-09-sec-fdb4c6` : `releve-amont.log` (commit `74e7b94c`) et `releve-complements-3.log` (commit `96b7e6f7`). Les lignes citées sont conformes.
- `swdb.lst` est vérifié par gpgv avec la clé `6DAA6E64…`.
- Versions amont : 2.5.24 du 23/09/2026 et 2.4.9 du 30/12/2025.
- Le tableau de fin de vie n'a **aucune ligne 2.3**.
- Rocky 9.8 livre `gnupg2` 2.3.3-5.el9_7.

J'ai écrit à 18:00:17 UTC trois lignes dans docs/04, limitées à GnuPG : §3, §4 et §6. Les autres projets de la brique 09 (apt, devscripts, Sequoia) restent à sa session. J'y ajoute une mesure de la brique 05 : aucun erratum de sécurité de Rocky 9.8 ne porte un `gnupg2` plus récent ([`m1b-amorce-fraicheur.log`](m1b-amorce-fraicheur.log)). Les journaux de la brique 09 ne sont pas sur cette branche ; docs/04 les cite par branche et par commit, sans lien.
- **Réserve** : la série 2.3 n'a plus de maintenance amont, seulement celle de Rocky. Les avis de GnuPG qui touchent la 2.3.3 ne sont pas lus.
- **Contre-contrôle** : gpgv n'est pas la seule garde du contenu. Les clés, les `repomd.xml` et les rpm sont fixés par sha256 dans la pipeline (RZ, PX).

Le point « ligne GnuPG de docs/04 » est fait. **Restent avant signature** :
- la mesure d'un autre jour (00:01 UTC le 20/11) ;
- `m1b_sortie`, déjà accordée pour après la mesure, puis `m1b_sans_sortie` sur son propre accord, puis `m1b_temoins` ;
- puis le premier passage de `m1b-signature.sh` (`SIGNER=1`), sur ton accord pour les écritures dans Zot.

## Note datée du 19/11/2026, écrite à 18:42:00 UTC : étape des PipelineRuns préparée à sec

J'ai préparé à sec, pendant l'attente de la mesure, le point « deux PipelineRuns par image » : le script neuf [`m1b-pipeline.sh`](../m1b-pipeline.sh), étape `pipeline`, **non lancée**. Prédictions PN1 à PN7 dans [`m1b-predictions.md`](m1b-predictions.md). Banc à 96 OK, 0 KO ([`m1b-pipeline-banc.log`](m1b-pipeline-banc.log)). Rien n'a été créé dans le cluster ni écrit dans Zot.

**Constat du banc** : le masquage des journaux ne masquait rien.
- `MASQUE` est un motif sed en BRE (`jeton\|token`). Passé à `sed -E`, le `\|` devient un `|` littéral, et aucune ligne n'est masquée.
- Le premier passage du banc l'a trouvé dans mon script : [`m1b-pipeline-banc-1.log`](m1b-pipeline-banc-1.log), 13 KO. C'est corrigé, `MASQUE` passe maintenant par un `sed` à part.
- La même fonction `filtre` se trouve dans `m1b.sh` et `m1b-builders.sh`. Testée sur une ligne `jeton=x`, elle ne la masque pas non plus.
- **Portée relevée** : sur les 103 journaux `m1b*.log` archivés, une seule ligne contient « jeton » ou « token ». C'est un message d'erreur de yq (« next token »), dans `m1b-refus-prefetch-2.log`. Aucun secret n'est exposé : les pods de M1b n'en portent aucun.
- **Correction** : `m1b.sh` et `m1b-builders.sh` ne doivent pas changer avant la fin de la mesure de cette nuit. Je les corrigerai après, par un commit à part.

**Garde de place** : 1 Gio, comme en M4, plus la taille de l'`image.tar` de l'image à pousser, lue dans le journal d'essai de la mesure.

**ConfigMap `porte`** : elle n'est lue que par le Job de jugement de la porte (`politique/porte-job.yaml`, espace `porte`), pas à l'admission des PipelineRuns. M4b et M4c sont passés avec elle périmée. Elle comptera pour tout verdict de la porte sur ces images. Je la joindrai à la demande d'accord pour les écritures dans Zot.

**Restent avant les PipelineRuns** :
- la mesure d'un autre jour ;
- `m1b_sortie`, `m1b_sans_sortie` et `m1b_temoins` ;
- la signature, ta revue de `taches.yml` et le second passage ;
- ton accord pour les écritures dans Zot.

La provenance reste à préparer, sur le modèle de M4c. Sa forme dépend des résultats réels de PN2.

## Note datée du 19/11/2026, écrite à 18:47:43 UTC : gardes d'entrée et portée du masquage

- **Gardes d'entrée** : ce sont celles de la correction datée de [`m1b-predictions.md`](m1b-predictions.md).
  - Avant toute création, les deux dépôts d'images doivent être absents, et Zot doit avoir la place des deux images.
  - Une relance après une première publication n'est plus annoncée comme possible sous un autre préfixe. Accepter un dépôt déjà présent sera une décision du propriétaire.
  - Script `f1982fdd442427fc…`, banc v2 à 109 OK, 0 KO.
- **Portée du masquage inopérant, établie sur tout le dépôt** :
  - un `git grep` de `sed -E` suivi de `MASQUE` ne trouve que `m1b.sh` et `m1b-builders.sh` ;
  - les cinq scripts qui définissent `MASQUE` l'écrivent en BRE ; les trois autres (`m4c.sh`, `m5.sh`, `m1b-pipeline.sh`) le passent à un `sed` sans `-E` ;
  - les journaux de `m1b.sh` et de `m1b-builders.sh` sont tous des `m1b*.log`, déjà comptés : une seule ligne, de yq.
  - La note précédente vaut donc pour tout le dépôt.
- **Cette nuit** : les journaux de la mesure sortiront de ce `filtre`, donc non masqués. Avant toute lecture, je compterai leurs lignes jeton/token sans les afficher, et `secrets-depot.sh` tranchera avant le commit.
- **Correction des deux scripts** : dans un tour de jour, après `jk-verif.py` et le commit du résultat, avec leurs bancs. Elle n'est pas prévue cette nuit.

## Note datée du 19/11/2026, écrite à 2026-11-19T20:40:20Z UTC : correctif de `filtre` préparé à sec, banc passé

**Correctif** : [`m1b-filtre.patch`](../m1b-filtre.patch). Prédictions FL1 à FL3 commitées avant le banc (`c02b722`). Le banc a tourné à 20:39:44 UTC.
- **FL1, tenue** : [`m1b-filtre-banc-avant.log`](m1b-filtre-banc-avant.log), sur `m1b.sh` `373ae334…` et `m1b-builders.sh` `82004de2…` tels qu'ils sont dans le dépôt. Chaque script a 4 OK et 7 KO, soit 8 OK et 14 KO au total, code 1. Aucune ligne jeton/token n'est masquée, quelle que soit sa casse. Les adresses sont bien retirées.
- **FL2, tenue** : [`m1b-filtre-banc.log`](m1b-filtre-banc.log), sur les deux copies corrigées et sur `m1b-pipeline.sh` `f1982fdd…`. Résultat : 33 OK, 0 KO, code 0.
- **FL3** : c'est une portée, pas une mesure. Les journaux de la mesure de cette nuit sortiront encore du filtre inopérant ; la règle de nuit tient (compter les lignes jeton/token avant toute lecture).

**Pas appliqué**. L'application est un rejeu de `git apply` sur le dépôt, suivi du banc sur les scripts du dépôt (attendu : 22 OK). Elle viendra après la mesure de 00:01 UTC et le commit de son résultat ; ces deux scripts ne changent pas avant.

**Bancs complets des deux scripts** (étape `banc` de chacun, podman local) : ils ne sont pas rejoués pour ce correctif. Seule la ligne `filtre()` change, et elle n'agit que sur les journaux.

## Note datée du 20/11/2026, écrite à 2026-11-20T00:11:38Z UTC : mesure d'un autre jour, résultat

**Tout tient.** Lanceur [`m1b-jour-kata.sh`](m1b-jour-kata.sh) parti à 2026-11-20T00:01:43Z, fini à 2026-11-20T00:11:15Z, code 0 ; journal [`m1b-jour-kata.log`](m1b-jour-kata.log), bilan sans KO, 21 comparaisons OK sur 21.
- **NU1, tenue** : avant toute lecture, 0 ligne jeton/token dans chacun des 10 fichiers comptés ([`m1b-nuit-compte.log`](m1b-nuit-compte.log)).
- **JK1 à JK3, JT1 à JT5 et TD1, tenues** : `jk-verif.py` rend 44 OK, 0 KO ([`m1b-jour-kata-verif.log`](m1b-jour-kata-verif.log)). Préfixes `m1b-20` (ancienne forme) et `m1bt-20` (forme de la tâche).
- **Durées relues** : dnf de `pod_c` 39 s (40 s le 19/11), dnf-3 de `pod_e` 5 s.
- **Journaux** : `m1b-20-prealables.log`, `m1b-20-pod_c.log`, `m1b-20-prealables_boot.log`, `m1b-20-pod_e.log`, et les quatre `m1b-builders-m1bt-20-*.log`.

**Portée, celle prévue à 15:33:13 UTC le 19/11** : les deux racines et les deux images se reproduisent dans Kata sur deux jours (19 et 20/11), sur un seul nœud et un seul hôte. Le point 1 A est établi dans ce cadre, pas au-delà : ni pour un autre nœud, ni après une mise à jour du noyau ou de Kata.

**Suite** : `m1b_sortie` (accord déjà donné pour après la mesure). Ensuite, dans un tour de jour, le correctif de `filtre`, puis `m1b_sans_sortie` sur son propre accord.

## Note datée du 20/11/2026, écrite à 2026-11-20T00:12:41Z UTC : `m1b_sortie` posée

`sortie-builds.sh m1b_sortie` est passée à 2026-11-20T00:12:03Z, code 0, 14 OK et 0 KO ([`sortie-m1b_sortie.log`](../../08c-durcissement/resultats/sortie-m1b_sortie.log)). `prefetch-racine-rpm-sortie` est créée et valide pour Cilium. `builds-sans-internet` exclut désormais quatre labels (`prefetch-gomod`, `prefetch-deb`, `prefetch-rpm`, `prefetch-racine-rpm`). Comme prévu, `s1.sh prealables` attend toujours un `NotIn` à trois labels : à adapter avant le rejeu M5b.

**Suite** : dans un tour de jour, le correctif de `filtre`, puis `m1b_sans_sortie` sur son propre accord, puis `m1b_temoins`.

## Note datée du 20/11/2026, écrite à 2026-11-20T08:35:16Z UTC : correctif de `filtre` appliqué

[`m1b-filtre.patch`](../m1b-filtre.patch) est appliqué au dépôt par `git apply`, sans conflit. `m1b.sh` passe à `9f8851d6…` et `m1b-builders.sh` à `31e01ae0…`, les mêmes empreintes que les copies corrigées du banc du 19/11. `bash -n` passe sur les deux.

Le banc, rejoué sur les deux scripts du dépôt, a fini à 2026-11-20T08:34:54Z : 22 OK, 0 KO, code 0 ([`m1b-filtre-banc-applique.log`](m1b-filtre-banc-applique.log)). C'est le résultat annoncé à l'écriture du correctif (22 OK). Les témoins sont des mots inventés, comme au 19/11.

**Portée** : les journaux écrits par `m1b.sh` et `m1b-builders.sh` à partir de maintenant passent par le masquage. Ceux de la mesure de cette nuit n'y sont pas passés ; ils ont été comptés avant lecture et contrôlés par `secrets-depot.sh` avant leur commit. Comme prévu, les bancs complets des deux scripts (étape `banc`) ne sont pas rejoués : seule la ligne `filtre()` change.

**Suite** : `m1b_sans_sortie`, sur son propre accord, puis `m1b_temoins`.

## Note datée du 20/11/2026, écrite à 2026-11-20T08:41:58Z UTC : `m1b_sans_sortie` posée

Accord du propriétaire : « Oui, lance-la ». `sortie-builds.sh m1b_sans_sortie` est passée à 2026-11-20T08:41:35Z, code 0, 12 OK et 0 KO ([`sortie-m1b_sans_sortie.log`](../../08c-durcissement/resultats/sortie-m1b_sans_sortie.log)). La politique posée est `construction-racine-rpm-sans-sortie` (sha256 `bddeeedf…`, celui des prédictions). **NC1 tenue** : elle était absente au départ, a été admise en dry-run serveur, puis posée. Les invariants rpm et ceux de la construction de M1b tiennent dans le cluster.
- **Construction de M1b** : un pod `construire-racine-rpm` est sélectionné par `builds-sans-internet` et par `construction-racine-rpm-sans-sortie`. Aucune politique ne lui autorise de trafic, et la NetworkPolicy porte les types `Egress+Ingress`.
- **Cluster** : dix politiques dans `builds`, cinq NetworkPolicy et cinq CiliumNetworkPolicy.

**Portée** : seuls des invariants lus sur les objets ont été vérifiés. Le chemin réseau réel n'a pas encore été mesuré ; ce sera le rôle des témoins.

**Suite** : `m1b_temoins` (pods runc d'essai, accord permanent du 18/11), prédictions NT1 à NT4 déjà commitées.

## Note datée du 20/11/2026, écrite à 2026-11-20T08:54:54Z UTC : `m1b_temoins` passée

`sortie-builds.sh m1b_temoins` a tourné de 2026-11-20T08:42:17Z à 2026-11-20T08:54:16Z sous l'accord permanent du 18/11, avec code 0 et sans KO ([`sortie-m1b_temoins.log`](../../08c-durcissement/resultats/sortie-m1b_temoins.log)). Sept pods témoins runc, retirés par le script. [`m1b-temoins-verif.py`](m1b-temoins-verif.py) compare le journal à celui de `rpm_temoins` du 16/11 ; seules les adresses résolues sont normalisées. Résultat : 17 OK, 0 KO ([`m1b-temoins-verif.log`](m1b-temoins-verif.log)).
- **NT1, tenue** : les cinq témoins de `rpm_temoins` rendent les mêmes dix lignes que le 16/11, aux adresses près.
- **NT2, tenue** : le témoin `prefetch-racine-rpm` rend les lignes du témoin `prefetch-rpm`. DNS résolu, 443 public joint (proxy.golang.org et dl.rockylinux.org), 80 refusé, API refusée, Zot joint, Forgejo refusé.
- **NT3, tenue** : le témoin `construire-racine-rpm` rend les lignes du témoin `construire-image`. DNS en échec et les sept destinations refusées.
- **NT4, tenue** : le pod runc au label `construire-racine-rpm` est admis.

**Portée** : ce sont des témoins runc ; ils ne disent rien du chemin réseau propre à Kata. NT2 confirme la borne déjà écrite pour la réserve « (a) Figée » : le prefetch de M1b joint toute adresse publique en 443, pas seulement vault et EPEL.

Les trois étapes réseau de M1b (`m1b_sortie`, `m1b_sans_sortie`, `m1b_temoins`) sont faites. `s1.sh prealables` attend toujours un `NotIn` à trois labels : à adapter avant le rejeu M5b.

**Suite** : signature des tâches de M1b (`SIGNER=1`, écriture dans Zot, sur accord), puis revue de la liste `taches.yml`.

## Note datée du 20/11/2026, écrite à 2026-11-20T08:58:34Z UTC : premier passage de la signature

Accord du propriétaire pour les écritures dans Zot : « Oui, signe ». `SIGNER=1 m1b-signature.sh taches` (sha256 `abe1e507…`, celui des prédictions) est parti à 2026-11-20T08:57:02Z, avec code 0, 17 OK et 0 KO ([`m1b-signature-taches.log`](m1b-signature-taches.log)).
- **SG1, tenue** :
  - les quatre rendus de `m1bt-20` égalent ceux validés par Tekton (TD1), et les quatre objets sont admis en dry-run serveur ;
  - les deux tâches sont signées par la clé des tâches, puis relues : égales au rendu, signature exceptée, avec l'image de l'amorce `ed654c69…` ;
  - elles sont versionnées dans [`builders/prefetch-racine-rpm.signee.yaml`](../builders/prefetch-racine-rpm.signee.yaml) (`14e83b3d…`) et [`builders/construire-racine-rpm.signee.yaml`](../builders/construire-racine-rpm.signee.yaml) (`9069ad26…`) ;
  - leurs bundles sont poussés dans Zot au tag `m1b`, sous les digests relus par `crane` : `prefetch-racine-rpm@sha256:16a32993…` et `construire-racine-rpm@sha256:bdde08ed…`. **Ces écritures sont définitives** ;
  - les deux lignes « à ajouter » sont imprimées, et les pipelines ne sont pas signées ;
  - avant les poussées, 3 613 925 376 octets étaient libres sur `/` de sc-stockage (la garde exige 1 Gio).
- **SG4, tenue pour les tâches** ([`m1b-signature-sg4.log`](m1b-signature-sg4.log)) : `tkn task verify`, avec la vraie clé publique des tâches (`9e118e03…`), accepte les deux tâches versionnées et refuse une copie altérée de chacune. Pour les pipelines, la vérification attend le second passage.
- **SG2 et SG3** : ils seront jugés au second passage.

**Suite** :
1. ta revue des deux entrées proposées pour `politique/porte/taches.yml` ;
2. le second passage, qui signe les pipelines ;
3. les PipelineRuns, sur leur propre accord.

La ConfigMap `porte` du cluster est toujours en retard sur `taches.yml` (note de 16:51:28 UTC le 19/11). Elle ne joue pas à l'admission des PipelineRuns, seulement pour un verdict de la porte.

## Note datée du 20/11/2026, écrite à 2026-11-20T09:01:24Z UTC : liste revue acceptée, second passage de la signature

**Liste revue** : sur ta décision « Oui, ajoute-les », les deux entrées proposées sont ajoutées telles quelles à `08-trust-plane/politique/porte/taches.yml` (commit `54c4dc1c`).

**Second passage** : `m1b-signature.sh taches`, sans `SIGNER`, est parti à 2026-11-20T09:00:43Z, avec code 0, 31 OK et 0 KO ([`m1b-signature-taches-2.log`](m1b-signature-taches-2.log) ; le journal du premier passage reste [`m1b-signature-taches.log`](m1b-signature-taches.log)).
- **SG2, tenue** : les deux bundles de tâches, repoussés depuis les fichiers versionnés (inchangés : `14e83b3d…` et `9069ad26…`), ont les digests du premier passage (`16a32993…` et `bdde08ed…`). Le script les trouve tous deux dans la liste revue.
- **SG3, tenue** :
  - chaque pipeline ne diffère du rendu que par les trois références (`prefetch-racine-rpm`, `construire-racine-rpm`, `publier-image` `d21931f3…`) ;
  - elles sont admises, signées et relues, puis poussées au tag `m1b` ;
  - `builder-mock-rocky9@sha256:4b9daf42…` et `builder-rocky9-bootstrap@sha256:eb57d44c…`.
- **SG4, tenue pour les quatre objets** ([`m1b-signature-sg4.log`](m1b-signature-sg4.log)) : `tkn pipeline verify`, avec la clé publique des tâches, accepte les deux pipelines signées et refuse une copie altérée de chacune (un paramètre de `construire`).

**Portée** : les pipelines signées ne sont pas versionnées dans le dépôt (le script ne le fait pas) ; leur sha256 est au journal SG4, et la référence de vérité est le bundle dans Zot. La ConfigMap `porte` reste en retard sur `taches.yml`.

**Suite** : `m1b-pipeline.sh pipeline`, quatre PipelineRuns (PN1 à PN7), sur ton accord, car `publier-image` écrit dans Zot et ces écritures sont définitives.

## Note datée du 20/11/2026, écrite à 2026-11-20T09:12:42Z UTC : quatre PipelineRuns passés, images publiées dans Zot

Accord du propriétaire : « Oui, lance-les ». `m1b-pipeline.sh pipeline` (sha256 `f1982fdd…`, celui des prédictions corrigées) a tourné de 2026-11-20T09:02:23Z à 2026-11-20T09:11:45Z, avec code 0, 113 OK et 0 KO. Journaux : [`m1b-pipeline-pipeline.log`](m1b-pipeline-pipeline.log), plus un journal de pas par PipelineRun et par tâche (`m1b-pipeline-m1b-<o|b>-<1|2>-<prefetch|construire>.log`).
- **PN1, tenue** :
  - toutes les gardes d'entrée passent (mesure d'un autre jour, pipelines relues dans Zot au tag `m1b`, liste revue, politiques à quatre labels, noms et dépôts absents, place dans Zot) ;
  - `m1b-o-1`, `m1b-o-2`, `m1b-b-1` et `m1b-b-2` sont créés dans cet ordre, et chacun finit `True|Succeeded` ;
  - tous les pods tournent sur sc-build, sous Kata pour `construire` seule.
- **PN2, tenue** : le prefetch de l'outillage réussit sans écrire `BASE_ARTIFACT_INPUTS`, et le résultat est absent de ses deux TaskRuns. Le reliquat du choix 2 est désormais mesuré, et non plus seulement lu dans le code.
- **PN3, tenue** :
  - le prefetch du bootstrap écrit `BASE_ARTIFACT_INPUTS` = `oci://sc-stockage.poc.test:5000/amont/rockylinux/rockylinux`, digest `sha256:ee90dc0e…` ;
  - `rpm -K` vérifie 199 rpm sur 199 (outillage) et 10 sur 10 (bootstrap) ;
  - les listes de sha256 des entrées égalent celles des essais de `m1bt3`.
- **PN4, tenue** :
  - `construire` voit ses trois témoins réseau échouer et ses entrées en lecture seule ;
  - la racine est conforme à la valeur fixée (`7c07083c…`, `b063feb3…`) ;
  - le manifeste et `DIGEST_CONSTRUIT` égalent les digests de `m1bt3`.
- **PN5, tenue** : `publier-image` publie chaque image au digest construit. Zot la relit en lecture anonyme, avec deux couches pour l'outillage et une pour le bootstrap. C'est la première poussée d'une image de 344 Mo par cette tâche ; chaque `publier` a duré de 7 à 10 s.
- **PN6, tenue** : pour chaque image, les deux exécutions donnent le même digest, égal à celui de `m1bt3` et de la mesure d'un autre jour :
  - `builds/builders/mock-rocky9@sha256:70f8c412…` ;
  - `builds/builders/rocky9-bootstrap@sha256:6de899ac…`.
- **PN7, tenue** : Chains signe les quatre PipelineRuns (annotation `true`). Les signatures et attestations des images relèvent de l'étape de provenance, qui reste à préparer.

**Zot** : `/` de sc-stockage passe de 3 610 853 376 octets libres (09:02:24 UTC) à 3 043 340 288 (09:11:45 UTC).

**Portée** : les deux images d'outillage rpm sont construites par la plateforme, sans réseau à la construction, et reproduites deux fois chacune dans Kata, sur un nœud et un hôte. L'amorce reste figée (réserve « (a) Figée »). Le prefetch joint toute adresse publique en 443 (NT2). La porte ne connaît pas encore `construire-racine-rpm`, et sa ConfigMap reste en retard sur `taches.yml`.

**Suite** : préparer l'étape de provenance de M1b (attestations des deux images, sur le modèle de M4b et M4c), puis adapter `s1.sh prealables` aux quatre labels avant le rejeu M5b.

## Note datée du 20/11/2026, écrite à 2026-11-20T09:20:30Z UTC : provenance préparée à sec

Décision du propriétaire : « Oui, prépare-la ». Le script est neuf : [`m1b-provenance.sh`](../m1b-provenance.sh), en lecture seule. Banc : 96 OK, 0 KO ([`m1b-provenance-banc.log`](m1b-provenance-banc.log)). Prédictions PV1 à PV7 dans [`m1b-predictions.md`](m1b-predictions.md), commitées avant le lancement.
- **Relevé fait pour écrire le script** : les attestations des deux images se vérifient déjà par cosign avec la clé de Chains (quatre enveloppes chacune). Leur forme a été lue (dépendances et noms de paramètres, valeurs à saut de ligne réduites à leur nombre de lignes) avant d'écrire l'attendu.
- **L'attendu** se tire de deux sources :
  - les références épinglées, pour les dépendances ;
  - les pipelines signées, pour les paramètres.

  Le banc le recoupe par les objets Tekton.

**Suite** : le lancement de `m1b-provenance.sh provenance`, en lecture seule, puis l'adaptation de `s1.sh prealables` aux quatre labels avant le rejeu M5b.

## Note datée du 20/11/2026, écrite à 2026-11-20T09:23:54Z UTC : provenance passée, M1b tenu avec réserves

`m1b-provenance.sh provenance` a tourné de 2026-11-20T09:22:25Z à 2026-11-20T09:22:27Z, en lecture seule, avec code 0 et 43 OK. PV1 à PV7 tiennent ([résultat](m1b-predictions.md)). Les deux images ont chacune une provenance signée par Chains, une par PipelineRun. Elle nomme la pipeline signée, les trois tâches de la liste revue et l'amorce, plus la base `ee90dc0e…` pour le bootstrap.

**Frontière du §5, tout est fait** :
- les deux tâches neuves ;
- les pipelines `builders` ;
- les deux images, chacune passée deux fois au même digest, avec leur provenance ;
- le banc de reproductibilité (point 1 A, établi sur un nœud et un hôte) ;
- le relevé des sources (point 1 B, Rocky 9.8 figée).

**M1b tenu, avec réserves** :
- l'amorce est figée (décision « (a) Figée » : 44 paquets sur 146 en retard sur Rocky 9.8, 54 errata plus récents) ;
- la reproduction est établie sur un seul nœud et un seul hôte ;
- le prefetch joint toute adresse publique en 443 (NT2) ;
- l'outillage ne déclare pas sa base (reliquat du choix 2, mesuré par PN2) ;
- la porte ne juge pas ces images : elle ne connaît pas `construire-racine-rpm`, et sa ConfigMap est en retard sur `taches.yml` ;
- `s1.sh prealables` attend toujours un `NotIn` à trois labels.

Additifs écrits dans les ADR 0001 et 0007. La clôture de la brique 05 reste ta décision.

**Après M1b, avant M5b** (§5, rien n'est commencé) :
- le verrou refait avec le nouveau bootstrap ;
- l'artefact de M4a republié ;
- de nouveaux bundles pour `prefetch-rpm` et `construire-rpm`, avec leur revue ;
- M4b et M4c refaits, avec leurs provenances ;
- les refus de M5a rejoués sur le nouveau bundle ;
- l'adaptation de `s1.sh prealables` aux quatre labels.

Le rejeu M5b ne viendra pas avant le 28/11.

## Note datée du 20/11/2026, écrite à 2026-11-20T09:42:17Z UTC : verrou de la cascade préparé à sec

Premier point de la cascade avant M5b (§5) : le verrou refait hors de la plateforme (décision « Hors plateforme »), avec le bootstrap de M1b. Script neuf : [`m1b-verrou.sh`](../m1b-verrou.sh). Banc : 64 OK, 0 KO ([`m1b-verrou-banc.log`](m1b-verrou-banc.log)). Prédictions VR1 à VR7 dans [`m1b-predictions.md`](m1b-predictions.md), commitées avant le lancement.

**Effort**, relevé à 2026-11-20T09:40:47Z avec la méthode de [`temps-05-1211.log`](temps-05-1211.log) :
- **Brique 05** : 336 commits, 37,44 h à `636f6b83`. Contrôle : 185 commits et 24,89 h à `c2c5809`, égal au relevé archivé.
- **M1b et sa cascade**, depuis la carte (`1e25df14`) : 137 commits ; 11,00 h en écarts d'au plus 1 h ; 37,76 h de bout en bout, du 18/11 au soir au 20/11.
- **Estimation** : 3 jours, décision à 6. Je ne convertis pas les heures en jours.

**Suite** :
- le lancement de `m1b-verrou.sh verrou` (pod d'essai, accord permanent) ;
- puis l'artefact de M4a, qui demande une écriture dans Zot avec un tag neuf : question à poser ;
- les bundles neufs de `prefetch-rpm` et de `construire-rpm` ne dépendent que de l'outillage, et peuvent se préparer à sec en parallèle. Leur signature et la revue de `taches.yml` restent à demander ;
- le rejeu de R1 à R8 sur le nouveau bundle n'a jamais été posé en question. Il le sera à son tour.

## Note datée du 20/11/2026, écrite à 2026-11-20T09:44:51Z UTC : verrou de la cascade passé

`m1b-verrou.sh verrou` a tourné de 2026-11-20T09:42:35Z à 2026-11-20T09:44:05Z, avec code 0, 33 OK et 0 KO. VR1 à VR7 tiennent ([résultat](m1b-predictions.md)).
- **Verrou neuf** : [`m1b-verrou.json`](m1b-verrou.json) (`c544599a…`). Il ne diffère du verrou de M4a (`b6d0f8f1`) que par le bootstrap : `config.bootstrap_image`, `bootstrap.pull_digest` (`6de899ac…`), `bootstrap.id` (`ff96017c…`) et `bootstrap.image_digest` (`77cff176…`). Les 222 rpm sont identiques.
- **Premier usage des deux images de M1b** : l'outillage démarre sous Kata, le pod tire le bootstrap anonymement, et mock le prend comme prêt.

**Suite de la cascade** : l'artefact de M4a, republié avec ce verrou. Il demande trois choses :
- une écriture dans Zot ;
- de nouvelles constantes dans `m4a.sh` (`VERROU_SHA`, `PULL_DIGEST`, `IMAGE_DIGEST`, `BOOTSTRAP`, `OUTILLAGE`) ;
- le remplacement de `poc/packaging/verrou-rpm.json`.

Je pose la question du tag avant toute écriture.

## Note datée du 20/11/2026, écrite à 2026-11-20T09:48:29Z UTC : épinglages de la cascade, et correction de la note de 09:44:51

**Correction** : la note de 2026-11-20T09:44:51Z annonçait « de nouvelles constantes dans `m4a.sh` » et « le remplacement de `poc/packaging/verrou-rpm.json` ». Ce plan est retiré, pour trois raisons lues dans le dépôt :
- **Le banc commité les lit** : la section B de [`m1b-verrou-banc.sh`](m1b-verrou-banc.sh) prend `VERROU_SHA` et `PULL_DIGEST` de `m4a.sh` comme sources des anciennes valeurs. Les changer sur place ferait échouer ce banc au rejeu.
- **`etape_verrou` de `m4a.sh` ne remplace pas `verrou-rpm.json`** : elle le compare s'il existe.
- **Les rejeux écraseraient les journaux** : `m4a.sh`, `m4b.sh` et `m4c.sh` écrivent `resultats/m4x-<étape>.log` et `$W/m4x-05` sans `PREFIXE`. Les rejouer réécrirait leurs journaux archivés, comme pour le journal de signature le 20/11 au matin. `m5.sh` a un `PREFIXE`.

**Forme à choisir à la préparation de chaque point** : des constantes choisies par un préfixe, ou un script frère, comme `m1b-verrou.sh`. Dans les deux cas, les anciens journaux et les anciens épinglages restent lisibles, et le banc de `fe1b72cc` reste vert ou est remplacé explicitement.

**Épinglages des anciennes valeurs**, relevés par `grep` hors journaux (`resultats/` exclu) :

| Ancienne valeur | Où elle est épinglée |
|---|---|
| `b6d0f8f1…`, verrou de M4a | `m4a.sh`, `m4b.sh`, `m4c.sh`, `s1.sh` (et `s1-m2.patch`), `m1b-verrou.sh` (comme référence), README de la 05 |
| `f0ccf105…`, bootstrap d'essai | `poc/packaging/verrou-rpm.json`, `m4a.sh`, `m4c.sh`, `m1b-verrou.sh` (référence), README, docs/03, ADR 0001 |
| `18d64b03…`, `image_digest` du bootstrap d'essai | `poc/packaging/verrou-rpm.json`, `m4a.sh` |
| `99790c13…`, outillage d'essai | tâches signées `fermeture/prefetch-rpm.signee.yaml` et `construction/construire-rpm.signee.yaml`, liste revue `taches.yml` (08), `m4a.sh`, `m4b.sh`, `m4c.sh`, `m5.sh`, `m1b-builders.sh`, `m1b-verrou.sh`, `A-REPORTER.md` (09), README, docs/03, docs/04, ADR 0007 |
| `41c639b7…`, artefact de M4a dans Zot | `m4c.sh`, `m5.sh`, README, docs/03 |
| chemin `verrou-rpm.json` | `preparer-rpm` et `construire-rpm` (sources et signées), `m4a.sh`, `m4c.sh`, `m5.sh`, `m5-alterer.py`, `m1b-verrou.sh`, README, docs/03 |

`rejeu.sh` (08) n'a pas encore de bloc pour la 05.

**Points notés pour la suite** :
- **`image_digest` (`77cff176…`) n'a qu'une source**, le verrou lui-même. Le 17/11, `IMAGE_DIGEST` venait de la ligne « Checking image digest » de l'étape `hermetique`. Le contrôle de ce champ par M4a serait donc circulaire : la valeur sera une prédiction de M4b, lue dans la construction hermétique.
- **Tag de l'artefact** : un tag neuf dans le même dépôt `entrees/sample-app/packaging-rpm` (par exemple `m1b`). Le tag `m4a` reste alors sur son manifeste. L'artefact est consommé par digest. La question à poser est l'écriture dans Zot elle-même, une fois le digest calculé à sec par deux layouts locaux.
- **Place libre dans Zot** : elle ne limite pas l'artefact de M4a (le verrou fait 111 567 octets), mais elle limite la fermeture de M4b. Je la relirai avant la question d'écriture, pour que le chiffre y figure.
- **Le rejeu de R1 à R8** reste une vraie question, à poser quand la cascade y arrivera.

## Note datée du 20/11/2026, écrite à 2026-11-20T10:06:20Z UTC : artefact de la cascade préparé à sec

La forme retenue est un script frère, [`m1b-artefact.sh`](../m1b-artefact.sh), et une zone de préparation neuve. `m4a.sh` et `poc/packaging/verrou-rpm.json` ne changent pas. Le tag neuf est `m1b`, dans le même dépôt.

Le banc donne 46 OK, et les prédictions AR1 à AR6 et AP1 à AP3 sont écrites ([prédictions](m1b-predictions.md)). Ensuite :
- `local` et `releve` tournent sous l'accord permanent ;
- `publier` attend ton accord nommé.

**Reste ouvert** : `poc/packaging/verrou-rpm.json` n'est plus la source de l'artefact neuf. Celle-ci est [`m1b-verrou.json`](m1b-verrou.json), sous `resultats/`. Le fichier de `poc/packaging` sera à remplacer quand le banc de `fe1b72cc` et `m4a.sh` ne le liront plus.

## Note datée du 20/11/2026, écrite à 2026-11-20T10:07:46Z UTC : artefact de la cascade calculé hors ligne

`local` et `releve` ont tourné à 10:06:41Z, et AR1 à AR6 tiennent ([résultat](m1b-predictions.md)).
- Le digest neuf est `sha256:333b7322290ab5edd85989908fa2e181a48a72facfd4043e181a2962d2bcfe48`, sous le tag `m1b`, à pousser dans `entrees/sample-app/packaging-rpm`.
- Zot n'a reçu aucune écriture.
- `publier` attend ton accord nommé.
