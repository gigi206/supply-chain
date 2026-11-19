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
