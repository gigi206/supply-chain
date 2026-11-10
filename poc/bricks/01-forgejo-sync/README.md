# Brique 01 : synchronisation des miroirs

**Statut (02/11/2026)** : partie locale validée ; **seuil atteint sur l'infra du PoC** (S2 à S5 : branche custom construite par la plateforme, force-push amont détecté et archivé dans `mirror/`, bundles exportés et restauration identique) ; mesure sur Traefik faite (S6). Périodicité horaire des deux timers observée à 16:17 et 16:25 UTC ([relevé](resultats/s6-periodicite-timers.log)). Restent ouverts : les incréments quotidiens de Traefik, la signature des rapports et des bundles et l'archivage WORM (briques 09 et 15). **Temps** : environ 2 h 15 le 02/11/2026 (13:10 à 15:23 UTC, protocole et préparation compris, pendant et après le rejeu `enchainement` de la 08 ; [`chrono.tsv`](resultats/chrono.tsv) et heures des commits), pour une estimation de 1 pw (décision à 2 pw) ; le temps de la partie locale, antérieure, n'a pas été relevé.

Seuil (README, brique 01) : branche custom buildée ; force-push amont détecté et archivé ; `git bundle` exporté.

## Ce que fait `sync.py`

Un run synchronise **un** dépôt amont vers son miroir (dépôt nu) **sans jamais rien perdre** :

| Refs du miroir | Contenu |
|---|---|
| `refs/upstream/heads/*`, `refs/upstream/tags/*` | Vue courante de l'amont |
| `refs/archive/<horodatage>/{heads,tags}/*` | Valeurs écrasées (force-push, tag déplacé) ou supprimées amont |
| `refs/sync/incoming/*` | Zone de transit du `fetch`, vidée à chaque run |
| `refs/sync/bundled/<ref>` | Valeur de `<ref>` déjà sauvegardée dans un bundle |
| Toute autre ref (`refs/heads/custom/*`…) | **Jamais touchée** |

Chaque changement de ref est classé :

| Événement | Critique (code de sortie 2) | Archivé |
|---|---|---|
| `branch-created`, `tag-created`, `fast-forward` | Non | Non (rien n'est écrasé) |
| `branch-deleted` | Non (routine) | Oui |
| `force-push-unprotected` (branche hors `--protected`) | Non | Oui |
| `force-push` (branche protégée : `main`, `master`, `release*`, `v*` par défaut) | **Oui** | Oui |
| `tag-moved`, `tag-deleted` | **Oui** | Oui |

Sorties de chaque run :
- un **rapport JSON** (`<horodatage>.json`, schéma `https://supply-chain.example/sync-report/v1`) : événements et **état complet** des refs `upstream` et `archive` ;
- un **bundle git incrémental** (`<horodatage>.bundle`) des refs `upstream` et `archive` qui ont changé depuis le dernier bundle réussi, avec son sha256 et ses prérequis. **Un bundle raté est rattrapé au run suivant** (le rapport du run raté garde ses événements) ;
- en option (`--push`), la publication dans le dépôt miroir Forgejo : `refs/upstream/heads/*` → `refs/heads/*`, `refs/upstream/tags/*` → `refs/tags/*`, `refs/archive/*` tel quel.

Codes de sortie : `0` = rien d'anormal ; `2` = réécriture amont détectée (alerte) ; `1` = erreur (rapport `status: error`).

```bash
./sync.py --mirror /srv/miroirs/traefik.git --upstream https://github.com/traefik/traefik.git \
  --report-dir /srv/sync/traefik/rapports --bundle-dir /srv/sync/traefik/bundles \
  --push https://forgejo.example/mirror/traefik.git
```

Restauration (bundles rejoués dans l'ordre, puis refs du dernier rapport valide, puis `git fsck`) :

```bash
./sync.py --mirror /srv/miroirs/traefik.git --report-dir /srv/sync/traefik/rapports \
  --bundle-dir /srv/sync/traefik/bundles --restore /srv/restauration/traefik.git
```

## Choix de sécurité

- **Protocoles limités** par `GIT_ALLOW_PROTOCOL` : `https` seul en production (pas de transport `ext::` ni de chemin local) ; `file` seulement avec `--allow-file` (tests) ou pour lire les bundles en restauration.
- **Objets vérifiés à la réception** (`transfer.fsckObjects=true`), **hooks désactivés** (`core.hooksPath=/dev/null`), journal de toutes les mises à jour de refs (`core.logAllRefUpdates=always`).
- **Transaction atomique** (`git update-ref --stdin`) avec la **valeur attendue** de chaque ref : un run concurrent fait échouer la transaction au lieu d'écraser une ref.
- `--prune` ne s'applique qu'à la zone de transit ; toute valeur écrasée ou supprimée est d'abord copiée sous `refs/archive`.
- Le dépôt miroir Forgejo appartient au **seul compte de synchronisation** (pushs refusés aux autres) : le `--force` y est sans risque puisque l'historique est déjà archivé. Les branches custom vivent dans le fork `workspace/<projet>`, jamais dans le miroir.

**Limite à connaître** : git **omet d'un bundle** les refs dont l'objet est exclu (archives, retour d'une branche en arrière). C'est donc le **rapport** qui fait foi pour l'état des refs : bundles et rapports doivent être archivés ensemble, signés et en WORM (briques 09 et 15).

## Tests

```bash
python3 -m unittest -v test_sync
```

10 tests sur des dépôts git locaux, tous réussis (14 depuis S1, voir plus bas) (git 2.43, Python 3.13 ; puis sur le laptop : git 2.53, Python 3.15, locale `fr_FR.UTF-8`).

Sur le laptop, 3 tests ont d'abord échoué : `sync.py` reconnaît le refus d'un bundle vide au message de git (« empty bundle »), que git traduisait en français. Le run finissait donc en erreur au lieu de constater qu'il n'y avait rien à sauvegarder. Correctif : git est lancé avec `LC_ALL=C`. Les 10 tests passent sous `fr_FR.UTF-8` comme sous `C`.

| Test | Vérifie |
|---|---|
| `test_premier_run_puis_avance_rapide` | Création puis avance rapide sans archive ; bundle incrémental avec prérequis ; zone de transit vidée |
| `test_force_push_protege_detecte_et_archive` | **Force-push sur `main` : code 2, ancienne tête archivée et toujours présente** |
| `test_force_push_branche_non_protegee` | Force-push sur `feature/x` : archivé, code 0 |
| `test_tag_deplace_tag_supprime_branche_supprimee` | Tag déplacé et tag supprimé : code 2 et archive ; branche supprimée : archivée, code 0 |
| `test_refs_custom_jamais_touchees` | `refs/heads/custom/*` et `refs/notes/*` intacts, même si l'amont crée une branche du même nom |
| `test_rien_de_change` | Run sans changement : aucun événement, aucun bundle |
| `test_restauration_depuis_bundles_et_rapport` | Après avance rapide, force-push, tag déplacé et suppression : **miroir restauré identique** (refs `upstream` et `archive`), `fsck` propre |
| `test_bundle_rate_rattrape_au_run_suivant` | Bundle en échec (code 1, événements conservés), puis force-push : le commit qui n'existe plus qu'en archive entre dans le bundle suivant, et la restauration le retrouve |
| `test_publication_vers_forgejo` | Refs publiées (`heads`, `tags`, `archive`) ; branche supprimée amont retirée de `heads` mais conservée sous `archive` |
| `test_protocole_file_refuse_sans_option` | Transport `file` refusé hors tests ; rapport d'erreur, code 1 |

## Reste à faire sur le laptop (liste d'origine, avant le protocole ; état au 02/11/2026 entre crochets)

- [Fait en S2 et S5] Vrai Forgejo : dépôt `mirror/<projet>` réservé au compte de synchronisation, jeton en secret Kubernetes, fork `workspace/<projet>` pour les branches custom ; **build d'une branche custom** par le pipeline (brique 08).
- [Fait en S1 et S2, sauf la protection à plusieurs niveaux côté Forgejo] **Refs protégées configurables** (exigence du propriétaire du 30/10/2026, B7) : les branches et tags propres, absents de l'amont, ne sont jamais perdus par une synchro ; les refs à préserver se configurent globalement et par dépôt git, le motif n'est pas imposé (par exemple `custom-*`). Proposé, à valider avec le propriétaire : configuration par dépôt qui complète ou remplace la globale, portée miroir et fork, traitement des collisions ci-dessous. État vérifié dans le code le 30/10/2026 :
  - miroir local : seules `refs/upstream/*`, `refs/archive/*` et `refs/sync/*` sont écrites, toute autre ref est préservée. Le test ne couvre que `refs/heads/custom/*` et `refs/notes/*` : ni tag, ni autre motif, ni configuration. Les bundles et la restauration ne portent que `upstream` et `archive` : une ref propre du miroir local ne serait pas restaurée ;
  - publication vers `mirror/<projet>` : `git push --force --prune` des branches et des tags (`push()`) supprimerait toute branche ou tout tag absent de l'amont. Une ref propre ne doit donc pas y vivre, ou doit être exclue du prune par un refspec négatif ;
  - mise à jour du fork `workspace/<projet>` depuis le miroir : pas encore conçue. Elle ne doit ni supprimer ni écraser une ref protégée (pas de `--prune`, refspec qui exclut les motifs protégés) ;
  - collision : une branche ou un tag amont qui correspond à un motif protégé est aujourd'hui publié tel quel dans `mirror/`. Proposé : événement critique dans le rapport, aucune propagation vers le fork ;
  - tests à ajouter : tag protégé, motif `custom-*` et autre motif configuré, configuration par dépôt, collision amont sur une branche et sur un tag, mise à jour du fork sans perte.
- [Fait en S3, par un timer systemd (D1) au lieu d'un CronJob ; période horaire observée le 02/11/2026, [relevé](resultats/s6-periodicite-timers.log)] CronJob Kubernetes, métrique « dernière synchronisation réussie » pour l'alerte « miroir en retard de plus de 24 h » (brique 19).
- [Fait en S6, sauf les incréments quotidiens] Mesure sur **Traefik** (durée, taille du premier bundle et des bundles incrémentaux).
- [Ouvert] Signature des rapports et des bundles, puis archivage WORM (briques 09 et 15).

## Protocole sur le laptop (proposé le 02/11/2026 ; D1 et D2 tranchées par le propriétaire le même jour)

Brique choisie par le propriétaire le 02/11/2026, après la clôture de la brique 08, dont elle réutilise le cluster (Forgejo 15.0.11 sur `sc-stockage`, CA du PoC, Tekton, Chains, porte). Rien n'est implémenté avant l'accord sur ce protocole ; chaque jalon est ensuite soumis à accord, comme en 08.

**Effort** : 1 pw pour toute la brique (README racine) ; le temps de la partie locale n'a pas été relevé. Décision avec le propriétaire à 2 pw. Le temps est relevé jalon par jalon dans `resultats/chrono.tsv`, ouvert à l'accord.

### Décisions du propriétaire (02/11/2026)

- **Refs propres (B7) : la configuration d'un dépôt complète la configuration globale.** Les motifs du dépôt s'ajoutent aux motifs globaux ; aucun dépôt ne peut retirer une protection globale.
- **Collision** (une branche ou un tag amont correspond à un motif de ref propre) : **événement critique** (code 2), ref amont publiée dans `mirror/<projet>` comme les autres, **jamais propagée** vers le fork `workspace/<projet>`, où la ref propre reste intacte.
- **D1 (a) : synchro par un timer systemd sur `sc-stockage`** (voir plus bas).
- **D2 (b) : branche custom buildée par un déclencheur et un gabarit séparés pour `workspace/sample-app-sync`**, chemin de `sample-app` inchangé (voir plus bas).

### Deux notions à ne pas confondre

| Notion | Rôle | Aujourd'hui |
|---|---|---|
| **Branches sensibles** | Un force-push amont sur elles est critique (code 2) | Option `--protected` (`main`, `master`, `release*`, `v*`) |
| **Refs propres (B7)** | Branches et tags créés chez nous, absents de l'amont, jamais perdus par une synchro | Rien : à concevoir (jalon S1) |

L'option `--protected` sera renommée (`--sensibles`, par exemple) pour lever l'ambiguïté ; le schéma du rapport passe en `v2` si un champ change.

### Contrainte : ne pas toucher à `workspace/sample-app`

`workspace/sample-app` est l'ancre des rejeux de la 08 : commit fixe `6391fd43…` recréé à chaque rejeu, `TETE_J2`, tests 3, 5 et 7, rattrapage (tête de `main`), filtre CEL du déclencheur (`refs/heads/main` et `workspace/sample-app` en dur, [`webhook.yaml`](../08-trust-plane/tekton/webhook.yaml), [`declencheurs.yaml`](../08-trust-plane/politique/declencheurs.yaml)) et source attendue par la porte. En faire un fork d'un miroir casserait les invariants de rejeu d'une brique close. La synchro travaille donc sur des **projets distincts** :

- **`sample-app-sync`** (nom proposé) : amont simulé `amont-essai/sample-app` sur le même Forgejo (mêmes sources que `poc/sample-app`), miroir `mirror/sample-app`, fork `workspace/sample-app-sync`. Il sert aux tests négatifs (force-push, tag déplacé, collision) et à la branche custom buildée ;
- **Traefik** : amont `https://github.com/traefik/traefik.git`, miroir `mirror/traefik`, fork `workspace/traefik`. Il sert à la mesure ; il n'est pas construit (phase 4).

**Limite du PoC** : l'amont simulé vit sur le Forgejo de la zone Sources, alors qu'un vrai amont est extérieur. On ne peut pas force-pousser sur GitHub, et c'est le seul moyen de rejouer une réécriture amont. L'organisation `amont-essai` a son propre compte d'écriture, distinct du compte de synchro.

### Décisions à prendre avant les jalons concernés

**D1. Où tourne la synchro.** **(a) retenue par le propriétaire le 02/11/2026** : timer systemd sur `sc-stockage`.

| Option | Pour | Contre |
|---|---|---|
| **(a) Timer systemd sur `sc-stockage`** (comme Forgejo et Zot) | git 2.47.3 déjà installé par apt (versions épinglées) ; python3 de Debian 13 (présent pour cloud-init, à vérifier en S3) ; aucune image à construire ou à faire confiance ; jeton en fichier 0600 dans la VM ; sortie NAT existante ; unité durcie (`systemd-analyze security`, comme Forgejo) | Pas de CronJob Kubernetes, contrairement à ce qu'annonçait cette brique ; la métrique passe par un fichier, pas par kube-state-metrics ; le code amont non fiable (objets git) est traité sur la VM de Forgejo et de Zot (atténué par `transfer.fsckObjects`, hooks désactivés, compte système dédié) |
| **(b) CronJob dans un espace `sources`**, `nodeSelector zone=stockage` | Conforme à l'annonce ; `kube_cronjob_status_last_successful_time` gratuit pour la 19 | Il faut une image python3 + git **épinglée et vérifiable** : signature amont non vérifiée à ce jour ; à défaut, image construite par la plateforme (nouvelle pipeline, hors estimation) ; jeton en Secret Kubernetes (lisible par les cinq lecteurs de tout le cluster, mesurés en 08) ; sortie vers GitHub sous Cilium : `toFQDNs` est impossible (L7 coupé, [`valeurs.yaml`](../08-trust-plane/cilium/valeurs.yaml)), il faudrait des `ipBlock` sur les plages publiées par GitHub, qui changent |

Vérifié pour (b) : seule la règle Kyverno `pods-isolation` (pas de privilège, de `hostPath`, de `hostNetwork`) s'appliquerait à un nouvel espace ; `zone-confiance` et `zone-build` visent des espaces nommés, et Pod Security est en `privileged` par défaut, chaque espace gardant ses labels.

**D2. Branche custom buildée.** **(b) retenue par le propriétaire le 02/11/2026.**

| Option | Contenu | Coût |
|---|---|---|
| **(a) Élargir le chemin de `sample-app`** | Filtre CEL, rattrapage et source de la porte étendus aux branches custom des forks | Rouvre la 08 : nouveau rejeu de J1 à J8, ADR 0000 et 0001 et doc 03 à reprendre. Hors de 1 pw |
| **(b) Déclencheur et gabarit séparés pour `workspace/sample-app-sync`** (retenue) | Même pipeline signée `sample-app` ; nouveau Trigger dans l'EventListener (filtre : dépôt `workspace/sample-app-sync`, `refs/heads/custom/*`), même anti-rejeu, porte avec la source attendue de ce dépôt ; chemin de `sample-app` inchangé | Le paramètre `depot` du gabarit existe déjà (`$(tt.params.depot)`), à vérifier dans la pipeline ; rattrapage : à étendre ou à exclure explicitement, à décider en S5 |

**D3. Contrat de la métrique (S3).** Un run qui détecte une réécriture (code 2) **est une synchro réussie** : sinon l'alerte « miroir en retard » se confondrait avec l'alerte de réécriture. Proposé : un fichier au format texte de Prometheus, `sync.prom`, réécrit atomiquement à chaque run, sans dépendre de Prometheus (la 19 choisira comment le lire, par exemple le collecteur textfile de node_exporter) :

| Métrique | Sens |
|---|---|
| `sync_derniere_reussite_timestamp_seconds{projet}` | Début (horodatage) du dernier run de statut `ok` ou `rewrite-detected` |
| `sync_derniere_reecriture_timestamp_seconds{projet}` | Dernier run de statut `rewrite-detected` |
| `sync_dernier_run_statut{projet,statut}` | 1 pour le statut du dernier run, 0 pour les autres |

### Jalons

| # | Jalon | Contenu | Contrôle de fin |
|---|---|---|---|
| **S1** | B7 hors cluster | `sync.py` : configuration globale et par dépôt (fichier versionné, motifs `fnmatch` sur les branches et sur les tags), mise à jour du fork sans `--prune` qui n'écrit aucune ref propre (refspecs négatifs abandonnés : voir le jalon S1), collision ; renommage de `--protected` | Nouveaux tests `test_sync.py`, tous réussis avec les 10 anciens, sous `C` et `fr_FR.UTF-8` (liste ci-dessous) |
| **S2** | Forgejo | Organisations `mirror`, `workspace` (existe), `amont-essai` ; compte `poc-sync` (jeton limité à `write:repository`), seul à écrire dans `mirror/*` (équipe de l'organisation) ; protection de branches et de tags de Forgejo sur les motifs de refs propres du fork, sans `poc-sync` dans la liste blanche (défense en profondeur) ; fork `workspace/sample-app-sync` par l'API | Push d'un autre compte non administrateur vers `mirror/` refusé (journal de Forgejo) ; `poc-sync` refusé sur une ref propre du fork ; comportement de `poc-admin` face à une branche protégée **mesuré**, pas supposé |
| **S3** | Exécution | Selon D1 ; métrique de D3 ; jeton jamais en argument ; contrôle `fuites.sh` | Deux runs planifiés successifs sans intervention ; `sync.prom` cohérent avec les rapports ; aucun secret dans les journaux des trois VM |
| **S4** | Tests négatifs sur le vrai Forgejo | Sur `amont-essai/sample-app` : force-push de `main`, tag déplacé, tag supprimé, branche supprimée, collision sur une branche et sur un tag ; ref propre créée dans le fork | Codes et événements attendus ; archives présentes dans `mirror/` ; refs propres du fork intactes après chaque run ; restauration identique depuis bundles et rapports |
| **S5** | Branche custom buildée | Selon D2 : push sur `custom/<nom>` de `workspace/sample-app-sync` → PipelineRun → image, provenance signée, porte | Provenance dont la source est `workspace/sample-app-sync` au commit de la branche custom ; admise par la porte ; même commit sur `main` du fork non construit par ce chemin |
| **S6** | Mesure sur Traefik | Premier run et runs incrémentaux depuis GitHub | Durée, taille du premier bundle et des incréments, espace disque de `sc-stockage` avant et après |

**Tests à ajouter en S1** : tag propre ; motif `custom-*` et un autre motif configuré ; configuration par dépôt qui s'ajoute à la globale (un motif global ne peut pas être retiré) ; collision amont sur une branche et sur un tag (code 2, pas de propagation au fork) ; mise à jour du fork sans perte (ref propre intacte, branches amont mises à jour) ; push vers `mirror/` qui ne supprime pas une ref absente de l'amont désignée par un motif ; restauration d'un miroir local qui porte une ref propre (aujourd'hui non restaurée : à corriger ou à documenter).

### Points à vérifier en cours de brique (non supposés)

- Refspecs négatifs combinés à `--prune` sur le push de git 2.47.3 (côté `sc-stockage`) et 2.53 (hôte) : une ref exclue n'est-elle vraiment pas supprimée ?
- Protection des tags et des branches par motif dans Forgejo 15.0.11, et son effet sur un push `--force` de l'administrateur.
- Fork dans la même instance : objets partagés ou copiés, et effet sur l'espace disque.
- **Espace de `sc-stockage`** (20 Go, Zot en `gc: false`) : à mesurer avant S6 ; taille de Traefik à relever avant le premier run, pas à supposer. Si l'espace manque : miroir local et bundles sur l'hôte, ou disque agrandi (accord du propriétaire).
- Sortie vers `github.com` depuis `sc-stockage` (D1 a) : NAT existant ; filtrage de la sortie par nftables dans la VM à décider en S3.

### Hors périmètre

Signature des rapports et des bundles (brique 09) et archivage WORM (brique 15) ; build de Traefik (phase 4) ; observabilité (brique 19, qui lira la métrique de D3).

### Prédictions (écrites le 02/11/2026, avant toute mesure)

- S1 : les refspecs négatifs suffisent pour que `push --prune` épargne les refs propres de `mirror/` ; aucun changement de format des bundles.
- S2 : Forgejo refuse le push d'un compte hors de l'équipe de `mirror` (HTTP 403 dans le journal) ; l'administrateur passe outre la protection de branche (à mesurer).
- S4 : mêmes événements et codes que les 10 tests locaux, sur le vrai Forgejo.
- S6 : premier run de Traefik en minutes, pas en heures ; incréments de quelques Mo par jour (ordre de grandeur, à mesurer).

## Jalon S1 : refs propres (B7) hors cluster (accord du propriétaire du 02/11/2026)

**Conception retenue avant le code** (02/11/2026, 13:53 UTC) :
- configuration en JSON versionné, `{"global": {"branches": [...], "tags": [...]}, "depots": {"<projet>": {...}}}`, choisie par `--refs-propres <fichier> --projet <nom>` ; motifs du dépôt **ajoutés** aux globaux ; motifs limités à la syntaxe commune à `fnmatch` et aux refspecs de git (au plus un `*`, ni `?` ni `[`), sinon erreur ;
- `--protected` renommé `--sensibles` ; schéma du rapport `v2` (champ `refs_propres` : motifs appliqués ; événement `collision`) ;
- **collision** : une ref amont créée ou modifiée qui correspond à un motif donne un événement `collision`, critique (code 2), en plus de son événement ordinaire ;
- **publication vers `mirror/` inchangée** (`--force --prune`) : un refspec négatif exclurait aussi la ref amont en collision, que la décision du propriétaire publie dans `mirror/`. Le protocole prévoyait des refspecs négatifs à cet endroit : écart assumé, `mirror/` reste la copie exacte de l'amont plus les archives, et aucune ref propre n'y vit (droits de Forgejo, S2) ;
- **mise à jour du fork** (`--fork <url>`) : `--force` sans `--prune`, avec un refspec négatif par motif (`^refs/upstream/heads/<motif>`, `^refs/upstream/tags/<motif>`) : refs propres jamais écrites, branches supprimées amont jamais supprimées du fork. **Remplacé après le premier passage** (voir les résultats) par un espace de transit `refs/sync/fork/`, qui ne porte que la vue amont sans les refs propres ;
- refs propres du miroir local : préservées (déjà testé) mais non restaurées ; elles vivent dans le fork, couvert par la sauvegarde (brique 12). Documenté, pas corrigé.

**Prédictions** (écrites à 13:53 UTC, avant le premier passage ; git 2.53.0, Python 3.13.12 sur l'hôte) :
- les 10 tests existants passent après le renommage, sans autre modification que `--protected` ;
- un refspec négatif à glob exclut bien les refs sources de `git push` (git ≥ 2.29), et un `push --force` sans `--prune` laisse intactes les refs du fork absentes de la source ;
- un motif à deux `*` est refusé par le script avant tout appel à git ;
- tous les nouveaux tests passent au premier passage, sous `C` comme sous `fr_FR.UTF-8`.

**Résultats** (02/11/2026, 13:54 à 13:56 UTC).

- **Premier passage** ([`s1-tests-premier-passage.log`](resultats/s1-tests-premier-passage.log)) : 13 tests sur 14 réussis, sous `C` comme sous `fr_FR.UTF-8`. `test_collision_branche_et_tag` échoue : la mise à jour du fork **écrase les refs propres** `custom-1` et `paquet/deb` avec la valeur amont en collision. Contraire à la prédiction sur ce point.
- **Cause, mesurée** ([`essai-refspec-negatif.sh`](essai-refspec-negatif.sh), [`s1-refspec-negatif.log`](resultats/s1-refspec-negatif.log)) : avec git 2.53.0, au push, un refspec négatif écrit sur le nom **source** (`^refs/upstream/heads/custom-*`, à glob ou exact) n'exclut rien ; écrit sur le nom **de destination** (`^refs/heads/custom-*`), il exclut. La prédiction supposait la source.
- **Correctif** : plus de refspec négatif. `update_fork` tient à jour `refs/sync/fork/{heads,tags}/*`, copie de la vue amont **sans les refs propres** (transaction `update-ref --stdin`), et pousse ce seul espace (`--force`, sans `--prune`). Le comportement ne dépend plus de la façon dont une version de git interprète un refspec négatif ; le git 2.47.3 de `sc-stockage` sera mesuré par le même script en S3.
- **Second passage** ([`s1-tests.log`](resultats/s1-tests.log)) : **14 tests sur 14 réussis**, sous `C` et sous `fr_FR.UTF-8` (git 2.53.0, Python 3.13.12). Les 10 anciens passent sans autre modification que le renommage de l'option.
- Autres prédictions confirmées : motifs invalides (`a*b*`, `v?`, `[ab]`, `^x`, vide) refusés avant tout appel à git (aucun miroir créé) ; fork sans `--prune` : branche supprimée amont gardée.

| Nouveau test | Vérifie |
|---|---|
| `test_config_globale_completee_par_depot` | Motifs du projet ajoutés aux globaux ; projet absent ou inconnu : globaux seuls ; sans fichier : aucun motif |
| `test_motif_invalide_refuse_avant_git` | Code 1, rapport d'erreur, aucun appel à git |
| `test_fork_mis_a_jour_sans_perte` | `main` du fork avancé ; branche supprimée amont gardée ; branches et tag propres intacts ; motifs appliqués dans le rapport |
| `test_collision_branche_et_tag` | Collisions sur `custom-1`, `paquet/deb` (motif du projet) et le tag `custom-2` : code 2, publiées dans le miroir, refs propres du fork intactes, tag absent du fork ; `autre-1` (motif d'un autre projet) propagée ; avance rapide amont d'une ref en collision : de nouveau code 2, fork inchangé |

**Temps** : relevé dans [`chrono.tsv`](resultats/chrono.tsv), ouvert avec S1 (le temps de la partie locale, antérieure, n'y figure pas).

## Jalon S2 : Forgejo (préparé le 02/11/2026 pendant le rejeu `enchainement` de la 08, exécution après lui)

Script : [`forgejo.sh`](forgejo.sh), étapes `comptes organisations amont miroir fork protections refus bout_en_bout` (journaux `resultats/forgejo-<étape>.log`). Il charge `commun.sh` de la brique 08 (même cluster, mêmes secrets) ; ses jetons vont dans `…/08/secrets`, donc dans le contrôle `fuites.sh` de la 08. Configuration des refs propres : [`refs-propres.json`](refs-propres.json) (global : branches `custom/*`, tags `custom-*` ; projet `sample-app-sync` : branches `paquet/*`).

**Vérifié avant l'écriture** (02/11/2026, lecture anonyme de `swagger.v1.json` du Forgejo en service, version `15.0.11+gitea-1.22.0`) : API des équipes (`permission`, `includes_all_repositories`, `units`), des forks (`organization`, `name`), des protections de branches (`rule_name`, liste blanche de push, **`apply_to_admins`**) et de tags (`name_pattern`, liste blanche) ; aucune option de force-push dans la protection de branche de cette version.

**Jeton limité à la cible** : l'en-tête `Authorization` de `poc-sync` est passé à git par `http.<url>.extraHeader`, pour `mirror/sample-app.git` et `workspace/sample-app-sync.git` seulement. Vérifié sans réseau par `git config --get-urlmatch` ([`s2-portee-entete.log`](resultats/s2-portee-entete.log), git 2.53.0) : aucun en-tête vers l'amont, vers GitHub, vers `workspace/sample-app` ni vers un dépôt au nom voisin (`mirror/sample-app-autre.git`). En production, le jeton ne doit jamais partir vers l'amont : c'est une exigence de S3.

**Prédictions** (écrites le 02/11/2026 à 14:05 UTC, avant toute exécution ; complétées à 14:15 UTC après relecture, toujours avant exécution) :
- `comptes` : trois comptes ordinaires (non administrateurs), un jeton `write:repository` chacun ; aucun mot de passe conservé ;
- `miroir` : premier run de `sync.py` à code 0, `main` de `mirror/sample-app` = `main` de l'amont ; dans le journal de Forgejo, des pushes vers `mirror/` seulement ;
- `archives` (sonde ajoutée à 14:15) : Forgejo accepte `refs/archive/*` ; force-push d'une branche non sensible de l'amont : code 0, `force-push-unprotected`, ancienne valeur lisible sous l'archive dans `mirror/` ;
- `fork` : `workspace/sample-app-sync` marqué fork de `mirror/sample-app`, même `main` ; équipes de `workspace` limitées à ce dépôt ;
- `refus` : chaque refus exige son motif (droits : `403` ou `permission denied` ; `protected branch` ; `protected tag`), un échec pour une autre raison est un KO ; refusés : push de `poc-dev` et de `poc-amont` vers `mirror/`, push de `poc-sync` vers `workspace/sample-app`, création, réécriture et suppression de refs propres du fork par `poc-sync` ; acceptés : refs propres du fork par `poc-dev`, branche ordinaire du fork par `poc-sync` ;
- mesures sans attendu ferme : création de `custom/a/b` par `poc-sync` (**acceptée**, prédiction faible : le `*` des règles de Forgejo ne traverserait pas les `/`, contrairement à celui de `sync.py` ; si c'est le cas, la défense en profondeur de Forgejo est plus étroite que la protection de `sync.py` : motif `custom/**` ou limite consignée) ; réécriture forcée de `custom/essai` par `poc-dev` (liste blanche ; **acceptée**, prédiction faible : aucune option de force-push) ; par `poc-admin` avec `apply_to_admins` (**refusée**) ; tag propre par `poc-admin` (**refusé**, prédiction faible : la protection de tag n'a pas d'option pour les administrateurs) ; push de `poc-admin` vers `mirror/` (**accepté** : l'administrateur passe outre les équipes, limite à consigner) ;
- `bout_en_bout` : code 2 (collision sur `custom/essai`), collision publiée dans `mirror/`, `custom/essai` du fork inchangée, `main` du fork avancée, tag `custom-1` intact.

**Avant l'exécution** : tâche `synchro:forgejo` à déclarer dans `mise.toml`, après le rejeu, car celui-ci lit `mise.toml` à chaque étape.

**Garde-fous ajoutés après relecture** (14:15 UTC) : `distant` lit `git ls-remote --refs` avec le nom exact (sans les lignes `^{}` des tags annotés, qui faisaient tenir les comparaisons par coïncidence) ; `synchro()` (hôte) refuse de tourner une fois l'état passé à la VM (un miroir neuf élaguerait les archives de `mirror/`).

**Après un rejeu de la 08**, tout l'état de S2 à S6 disparaît avec les VM : S2 est à rejouer avant S3 (l'installation de S3 reprend le miroir de l'hôte).

**Résultats** (02/11/2026, 14:42 à 14:43 UTC, après le rejeu `enchainement` de la 08 ; journaux `resultats/forgejo-<étape>.log`) :

- **Passages archivés** (règle : tout passage modifié ensuite est gardé) :
  - [`forgejo-amont-premier-passage.log`](resultats/forgejo-amont-premier-passage.log) : push de l'amont sans en-tête. Défaut du script : l'en-tête était déclaré pour `…/sample-app` et le push visait `…/sample-app.git` ; git compare les chemins composant par composant, l'en-tête n'est donc pas envoyé. La vérification à sec (`s2-portee-entete.log`) ne testait que des URL en `.git`. Corrigé : préfixe = URL exacte du dépôt ;
  - [`forgejo-refus-premier-passage.log`](resultats/forgejo-refus-premier-passage.log) : refus réel de `poc-dev` vers `mirror/`, mais motif inattendu, donc KO (garde-fou de la relecture) : Forgejo 15.0.11 refuse un compte sans droit d'écriture par son hook pre-receive, **« User 'poc-dev' is not allowed to push to branch … »**, pas par un 403. Motif ajouté après mesure ;
  - [`forgejo-refus-deuxieme-passage.log`](resultats/forgejo-refus-deuxieme-passage.log) : réécriture forcée refusée avec **« branch custom/essai is protected from force push »**, motif ajouté de même. Les refs créées par ce passage empêchant de le rejouer tel quel, le fork d'essai a été supprimé (HTTP 204) puis recréé par `fork`.
- `comptes` : trois comptes ordinaires, non administrateurs, un jeton `write:repository` chacun ; aucun mot de passe conservé. `organisations` : équipes `mirror/synchro` (`poc-sync`, écriture, tous les dépôts) et `amont-essai/ecriture` (`poc-amont`). Les « 404 » du journal sont les tests d'existence (rendus silencieux ensuite).
- `amont`, `miroir` : premier run de `sync.py` à code 0, `main` de `mirror/sample-app` = `main` de l'amont.
- `archives` : **Forgejo accepte `refs/archive/*`** ; force-push d'une branche non sensible : code 0, `force-push-unprotected`, ancienne valeur lisible sous `refs/archive/20261102T144237Z/heads/essai/archive` dans `mirror/`. Conforme.
- `fork` : `workspace/sample-app-sync`, fork de `mirror/sample-app`, même `main` ; équipes `workspace/synchro` et `workspace/dev-sample-app-sync` limitées à ce seul dépôt. `protections` : `custom/*` et `paquet/*` (liste blanche `poc-dev`, `apply_to_admins`), tag `custom-*` (liste blanche `poc-dev`).
- `refus` ([`forgejo-refus.log`](resultats/forgejo-refus.log)), conformes : refus de `poc-dev` et `poc-amont` vers `mirror/`, de `poc-sync` vers `workspace/sample-app` de la 08 (dont `main` reste `6391fd43`, seule ref, vérifié après coup ; le journal de Forgejo note ce POST en 200, le refus passant par le protocole git), de `poc-sync` sur la création, la réécriture forcée et la suppression de refs propres ; acceptés : refs propres par `poc-dev`, branche ordinaire du fork par `poc-sync`.
- Mesures :
  - **`custom/a/b` créée par `poc-sync` : acceptée**, comme prédit (prédiction faible). Le `*` des règles de Forgejo ne traverse pas les `/`, contrairement à celui de `sync.py` : la défense en profondeur de Forgejo est plus étroite que la protection de `sync.py` pour les branches à plusieurs niveaux. À traiter (motif `custom/**` côté Forgejo, à mesurer) ou à consigner ; `sync.py` reste protégé ;
  - **réécriture forcée de `custom/essai` par `poc-dev` : refusée**, contrairement à la prédiction (acceptée, prédiction faible) : la protection interdit le force-push à tous, liste blanche comprise ;
  - par `poc-admin` (`apply_to_admins`) : refusée ; tag propre `custom-2` par `poc-admin` : refusé ; conformes ;
  - **push de `poc-admin` vers `mirror/` : accepté**, comme prédit : l'administrateur passe outre les équipes. Limite consignée ; la branche `essai-s2-admin` ainsi créée sera élaguée par le prochain push de la synchro (`--prune`).
- Fuites ([`fuites-synchro-s2.log`](resultats/fuites-synchro-s2.log), `fuites.sh` de la 08) : aucun des trois nouveaux jetons dans les journaux des trois VM, témoin retrouvé.
- `bout_en_bout` : conforme. Collision sur `custom/essai` : code 2 (`branch-created`, `collision`, `fast-forward` de `main`), collision publiée dans `mirror/`, `custom/essai` du fork intacte (valeur de `poc-dev`), `main` du fork avancée, tag `custom-1` intact.

## Jalon S3, partie hors cluster : métrique (D3)

**Prédictions** (écrites le 02/11/2026 vers 14:05 UTC, juste avant le code ; heure d'abord mal notée, 14:07) : `--metriques <fichier>` écrit, après chaque run, un fichier au format texte de Prometheus **déduit des rapports** (qui font foi), réécrit atomiquement (fichier temporaire puis `os.replace`) ; un run `rewrite-detected` compte comme une réussite ; un run en erreur ne fait pas avancer la dernière réussite ; les 14 tests existants passent toujours.

**Résultat** ([`s3-tests-metriques.log`](resultats/s3-tests-metriques.log)) : **16 tests sur 16 réussis**, sous `C` et sous `fr_FR.UTF-8`, conformes aux prédictions. Un premier passage, également à 16 sur 16, a précédé un allègement du test (import de `datetime`, assertion inutile retirée) ; son journal a été écrasé par le second, faute d'avoir été renommé.

| Nouveau test | Vérifie |
|---|---|
| `test_metriques_deduites_des_rapports` | Après un run `ok`, un run à code 2 et un run en erreur : dernière réussite = run à code 2, dernière réécriture = même run, statut `error` à 1 ; aucun fichier temporaire laissé |
| `test_metriques_sans_reussite` | Tant qu'aucun run n'a réussi, la métrique de dernière réussite est absente (l'alerte de la 19 devra traiter l'absence) |

## Jalon S3, partie sur `sc-stockage` (préparée le 02/11/2026, exécution après S2)

Script : [`executeur.sh`](executeur.sh), étapes `installer essai planifie refspec` ; unités et lanceur dans [`systemd/`](systemd/).

- **Unité modèle `synchro@<projet>.service`** (oneshot, compte système `synchro`) : durcissement repris de l'unité Forgejo de la 08 ; configuration sans secret dans `/etc/synchro/<projet>.env` ; jeton de `poc-sync` en root 0600 (`/etc/synchro/secrets/poc-sync.token`), remis au seul service par **`LoadCredential`** ; **`SuccessExitStatus=2`** : une réécriture détectée n'est pas un échec de l'unité (contrat D3) ; état dans `StateDirectory` (`/var/lib/synchro/<projet>` : miroir local, rapports, bundles, métrique `<projet>.prom`).
- **Timer `synchro@<projet>.timer`** : toutes les heures après le run précédent (`OnUnitActiveSec=1h`, `RandomizedDelaySec=5min`, `Persistent`) ; l'étape `planifie` ramène la période à 2 min par un drop-in, le temps de la mesure, puis le retire.
- **Lanceur [`synchro.sh`](systemd/synchro.sh)** : en-tête du jeton limité à `MIROIR` et `FORK` (`http.<url>.extraHeader`, comme en S2), jamais à l'amont ; `python3 -I`.
- **Continuité de l'état** (risque relevé à l'écriture) : en S2, le miroir local vit sur l'hôte. Un miroir neuf dans la VM pousserait `refs/archive/*` avec `--prune` et **retirerait de `mirror/` les archives de S2**. L'étape `installer` copie donc le miroir, les rapports et les bundles de l'hôte dans la VM, qui en devient le seul propriétaire ; la copie de l'hôte est renommée.

**Prédictions** (écrites le 02/11/2026 vers 14:07 UTC, avant toute exécution) :
- `installer` : python3 (3.13, Debian 13) et git 2.47.3 présents, aucun paquet ajouté ; `sc-stockage.poc.test` résolu dans la VM ; score de `systemd-analyze security` proche de celui de Forgejo (3.0, « OK ») ;
- `essai` : run réussi pour systemd ; rapport de statut `ok` (l'état de S2 est repris : aucun événement nouveau) ; métrique cohérente ; jeton absent du journal de l'unité ;
- `planifie` : deux runs planifiés en moins de 5 min, sans intervention ; période d'une heure rétablie après la mesure ;
- `refspec` : avec git 2.47.3, même comportement qu'avec 2.53.0 (négatif comparé à la destination), prédiction faible ; sans effet sur `sync.py`, qui n'en dépend plus.

**Résultats** (02/11/2026, 14:46 à 15:09 UTC, accord du propriétaire ; journaux `resultats/executeur-<étape>.log`) :

- **Passages archivés** :
  - [`executeur-installer-premier-passage.log`](resultats/executeur-installer-premier-passage.log) et [`executeur-essai-premier-passage.log`](resultats/executeur-essai-premier-passage.log) : dans la VM, **`sc-stockage.poc.test` pointe vers `127.0.1.1`** (`/etc/hosts`), où Forgejo n'écoute pas ; le run échoue (« Failed to connect »), rapport d'erreur gardé dans la VM. Le contrôle « résolu dans la VM » était trop faible (adresse non vérifiée), contrairement à la prédiction. Corrigé : URL par l'adresse `192.168.161.13` (dans le certificat de Forgejo), et contrôle d'installation par une vraie connexion à l'URL configurée ;
  - [`executeur-planifie-premier-passage.log`](resultats/executeur-planifie-premier-passage.log) : un seul run planifié en 10 min. Cause mesurée (`TimersMonotonic`) : **une affectation vide de n'importe quelle option `On…Sec` vide la liste de tous les déclencheurs** ; le drop-in faisait deux remises à zéro, la seconde (`OnBootSec=`) retirait `OnUnitActiveSec=2min`. Corrigé : une seule remise à zéro, en premier ;
  - [`executeur-planifie-deuxieme-passage.log`](resultats/executeur-planifie-deuxieme-passage.log) : aucun run. **`systemctl enable --now` ne redémarre pas un timer déjà actif** : resté `elapsed`, il ignorait le drop-in corrigé (`NextElapseUSecMonotonic=infinity`). Corrigé : `restart` explicite.
- `installer` : Python 3.13.5 et git 2.47.3 de la VM, aucun paquet ajouté ; `sync.py` installé identique ; état de S2 repris de l'hôte ; `systemd-analyze security` : **3.0 « OK »**, comme Forgejo. Conforme sauf la résolution (ci-dessus).
- `essai` : run réussi pour systemd, statut `ok` sans événement (état de S2 repris), métrique cohérente (dernière réécriture = bout en bout de S2, 14:43:25 UTC) ; jeton absent du journal de l'unité. Conforme.
- **Continuité vérifiée** : après les runs de la VM, `mirror/sample-app` garde l'archive de S2 (`refs/archive/20261102T144237Z/heads/essai/archive`), et la branche `essai-s2-admin` créée par l'administrateur en S2 a été élaguée, comme prédit.
- `planifie` ([`executeur-planifie.log`](resultats/executeur-planifie.log)) : deux runs déclenchés par le timer sans intervention (15:08:27, au redémarrage, la période étant déjà écoulée ; 15:08:37, `OnActiveSec`). **Mesure plus faible que prévu** : la période de 2 min elle-même n'est pas observée. Période d'une heure rétablie : prochain run annoncé à 16:13:08 UTC (1 h après le dernier, plus le délai aléatoire), à vérifier dans le journal de l'unité.
- `refspec` ([`executeur-refspec.log`](resultats/executeur-refspec.log)) : avec git 2.47.3, même comportement qu'avec 2.53.0 (négatif comparé au nom de destination) ; conforme à la prédiction faible ; sans effet sur `sync.py`.
- `fuites` ([`fuites-synchro-s3.log`](resultats/fuites-synchro-s3.log)) : aucun secret dans les journaux des trois VM, jeton de `poc-sync` compris.

## Jalon S4 : tests négatifs sur le vrai Forgejo (préparé le 02/11/2026, exécution après S3)

Étape `negatifs` de [`forgejo.sh`](forgejo.sh) : `poc-amont` réécrit l'amont d'essai, puis chaque fois un run du service `synchro@sample-app-sync` de la VM (S3) ; contrôle du code (`ExecMainStatus`), du rapport, de l'archive publiée dans `mirror/`, du fork, puis restauration dans la VM.

**Prédictions** (écrites le 02/11/2026 à 14:08 UTC, avant toute exécution ; heure d'abord mal notée, 14:10) :
- force-push de `main` : code 2, événement `force-push`, ancienne tête sous `refs/archive/<horodatage>/heads/main` dans `mirror/`, `main` du fork alignée sur l'amont ;
- tag `v1.0.0` créé (code 0), déplacé (code 2, `tag-moved`, archive publiée), supprimé (code 2, `tag-deleted`, archive publiée, retiré de la vue amont de `mirror/`) ; dans le fork, le tag garde sa dernière valeur (pas de `--prune`) ;
- branche `feature/x` créée puis supprimée : code 0 les deux fois, archive publiée, branche gardée dans le fork ;
- refs propres du fork (`custom/essai`, `paquet/deb`, `custom-1`) intactes après toutes les réécritures ;
- restauration depuis les bundles et les rapports de la VM : refs `upstream` et `archive` identiques au miroir local.

**Résultats** (02/11/2026, 15:12 à 15:13 UTC, accord du propriétaire ; [`forgejo-negatifs.log`](resultats/forgejo-negatifs.log)) : **conformes à toutes les prédictions**.

- **Passage archivé** ([`forgejo-negatifs-premier-passage.log`](resultats/forgejo-negatifs-premier-passage.log)) : conforme jusqu'au 6e run, refusé par systemd (« start of the service was attempted too often ») : **une unité ne démarre pas plus de 5 fois en 10 s** (`StartLimitBurst` par défaut). Limite gardée pour le service ; les runs du test sont espacés de 3 s ; état d'échec de l'unité levé (`reset-failed`) avant le second passage.
- Force-push de `main` : code 2, `force-push`, ancienne tête sous `refs/archive/20261102T151246Z/heads/main` dans `mirror/`, `main` du fork alignée sur l'amont. Le même run a rattrapé la suppression de `feature/x` laissée en suspens par le passage interrompu (`branch-deleted`, archivée) : rattrapage conforme à la conception.
- Tag `v1.0.0` : créé (code 0), déplacé (code 2, `tag-moved`, archive publiée), supprimé (code 2, `tag-deleted`, archive publiée, retiré de la vue amont de `mirror/`) ; gardé dans le fork, à sa dernière valeur.
- Branche `feature/x` créée puis supprimée : code 0 les deux fois, archive publiée, branche gardée dans le fork.
- Refs propres du fork (`custom/essai`, `paquet/deb`, `custom-1`) intactes.
- Restauration dans la VM depuis 10 bundles et le dernier rapport : 12 refs `upstream` et `archive`, identiques au miroir local.

## Jalon S5 : branche custom buildée (étude du 02/11/2026, lecture seule de la brique 08 ; option (ii) retenue par le propriétaire le même jour)

**Ce que D2 (b) ne change pas** (lu dans [`declencheurs.yaml`](../08-trust-plane/politique/declencheurs.yaml) et [`gabarit-sample-app.yaml`](../08-trust-plane/politique/gabarit-sample-app.yaml)) : un **EventListener séparé** `forgejo-sync` dans `declencheurs` (même compte `el-forgejo`, même intercepteur HMAC, avec un secret de webhook propre ; filtre CEL : `workspace/sample-app-sync` et `refs/heads/custom/*`) et une TriggerTemplate `sample-app-sync` **dérivée à l'exécution de celle en service** (même pipeline signée, même anti-rejeu par le nom, préfixe `sample-app-sync-`) laissent intacts l'EventListener `forgejo` et le gabarit de la 08. La porte reçoit la source attendue à chaque jugement (`juger … [source attendue]`) : aucune modification de la porte. Le rattrapage ne lit qu'une branche (`DEPOT`, `BRANCHE`) : un webhook perdu sur une branche custom n'est pas rattrapé, limite à consigner ou à traiter.

**Constat qui touche la brique 08** : la pipeline signée [`sample-app`](../08-trust-plane/politique/taches/sample-app.yaml) fixe, sous sa signature, le dépôt Zot de l'image (`@IMAGE@` = `builds/sample-app`), la fermeture des dépendances et `web/dist`. Une branche custom construite par elle :
- publie dans **le même dépôt** que l'image réelle de la 08 ;
- si son arbre ne change rien à la construction (sources Go identiques), donne **le même digest `3a7ca1b1`** (construction reproductible). Sa provenance, de source `workspace/sample-app-sync`, devient alors la plus récente de l'image réelle ; or la porte ne juge que la plus récente (test 7) : l'image réelle, jugée avec la source `workspace/sample-app`, serait **refusée** ;
- ne peut changer ni les dépendances ni l'interface web : la fermeture et `web/dist` sont épinglés.

| Option | Contenu | Coût |
|---|---|---|
| **(i)** même pipeline, branche custom qui change le code Go | Digest différent, donc aucune provenance ajoutée à l'image réelle | Repose sur le contenu de la branche : la première branche custom sans changement de code casse la porte de l'image réelle. Fragile |
| **(ii)** seconde pipeline signée `sample-app-sync`, recommandée | Mêmes tâches signées (liste revue des tâches inchangée), `@IMAGE@` = `builds/sample-app-sync` ; bundle produit et signé comme celui de `construction.sh taches`, sans modifier la 08 | Une pipeline de plus à signer et à épingler ; mêmes fermeture et `web/dist` (limite inchangée) |

**Coût de (ii), vérifié dans la 08** (14:14 UTC) : la règle Kyverno `tekton-references` accepte tout bundle `tekton/pipelines/[a-z0-9-]+` épinglé par digest ; la VerificationPolicy de Trusted Resources, tout `tekton/(tasks|pipelines)/[a-z0-9-]+` signé par la clé des tâches ; la liste revue de la porte ne porte que sur les tâches, inchangées. (ii) ne demande donc aucune modification de la 08.

En production, chaque projet aura sa pipeline et son dépôt d'images : (ii) en est la forme réduite.

**Option (ii) retenue par le propriétaire** (02/11/2026). Script : [`declencheur.sh`](declencheur.sh), étapes `pipeline installer construire porte` ; aucun fichier de la 08 n'est modifié, tout dérive de ce qui est en service :
- `pipeline` : la pipeline `sample-app` du gabarit en service est lue dans Zot (`tkn bundle list`), renommée `sample-app-sync`, son paramètre `image` passé à `builds/sample-app-sync`, re-signée par la clé des tâches et publiée dans `tekton/pipelines/sample-app-sync`. Un contrôle vérifie que l'écart se limite à ces deux champs (essayé hors cluster le 02/11/2026 sur le gabarit versionné de la 08, rendu avec des valeurs factices : écart = nom, image et signature) ;
- `installer` : secret HMAC propre, TriggerTemplate et EventListener dérivés de ceux en service, webhook du fork limité à `custom/*` ;
- `construire` : commit sur `custom/s5` par `poc-dev`, PipelineRun créé par le webhook ;
- `porte` : la fonction `juger` de `politique.sh` est réutilisée telle quelle (extraite, pas copiée).

**Prédictions** (écrites le 02/11/2026 à 14:21 UTC, avant toute exécution) :
- `pipeline` : un seul paramètre `image` à changer ; écart limité au nom et au dépôt ; bundle publié ;
- `installer` : EventListener `forgejo-sync` disponible et joignable depuis `sc-stockage` ; EventListener `forgejo` et gabarit `sample-app` de la 08 inchangés ;
- `construire` : PipelineRun `sample-app-sync-<commit>` créé par le webhook, réussi, signé par Chains ; image dans `builds/sample-app-sync` ; **digest `3a7ca1b1`**, celui de l'image réelle de la 08 (arbre identique, construction reproductible), mais dans un autre dépôt ;
- `porte` : image de la branche custom admise avec la source `workspace/sample-app-sync@<commit>` (horodatage compris, après au plus quelques minutes du CronJob) ; refusée avec la source `workspace/sample-app` ; **image réelle de la 08 toujours admise** avec sa source (la provenance de la branche custom est attachée à un autre dépôt).

**Résultats** (02/11/2026, 15:13 à 15:19 UTC, accord du propriétaire ; journaux `resultats/declencheur-<étape>.log`) : **conformes à toutes les prédictions**.

- **Passages archivés** :
  - [`declencheur-pipeline-premier-passage.log`](resultats/declencheur-pipeline-premier-passage.log) : bundle lu sous le nom vu des pods (`sc-stockage.poc.test`), qui ne se résout pas sur l'hôte ; corrigé : lecture par `REG_HOTE` (adresse IP), comme le prévoit `commun.sh` ;
  - [`declencheur-installer-premier-passage.log`](resultats/declencheur-installer-premier-passage.log) et [`declencheur-construire-premier-passage.log`](resultats/declencheur-construire-premier-passage.log) : aucun PipelineRun ; l'intercepteur refuse la livraison (« payload signature check failed »). Cause : **secret HMAC avec un saut de ligne final** (`openssl rand -hex 32` sans `tr -d '\n'`, contrairement à la 08) : Forgejo signait avec la valeur sans saut de ligne, le Secret la gardait avec. Corrigé (génération et normalisation comme en 08) ; le second push part de `custom/s5`, protégée contre le force-push.
- `pipeline` : un seul paramètre `image` changé ; écart avec la pipeline en service limité au nom et au dépôt ; `tekton/pipelines/sample-app-sync@sha256:a4d543e2…` ; tâches `preparer-entrees@2070d601`, `construire-image@403ccbd8`, `publier-image@d21931f3`, celles de la liste revue de la porte.
- `installer` : EventListener `forgejo-sync` joignable depuis `sc-stockage` ; webhook du fork limité à `custom/*` ; EventListener `forgejo` et gabarit `sample-app` de la 08 inchangés.
- `construire` : commit `1599e311` sur `custom/s5` par `poc-dev` (arbre `30e808ff`, celui de `poc/sample-app` en J2 de la 08) ; PipelineRun `sample-app-sync-1599e311…` créé par le webhook, réussi, signé par Chains ; image `builds/sample-app-sync@sha256:3a7ca1b1…`, **le digest de l'image réelle de la 08, dans un autre dépôt**, comme prédit.
- `porte` ([`declencheur-porte.log`](resultats/declencheur-porte.log)) : image de la branche custom **admise** avec la source `workspace/sample-app-sync@1599e311`, horodatage compris au premier essai (2 enveloppes couvertes) ; **refusée** avec la source `workspace/sample-app` (`slsa_source_correlated.expected_source_code_reference` seule) ; **image réelle de la 08 toujours admise** avec sa source (6 enveloppes couvertes) : non-interférence mesurée, malgré le digest commun. Avertissement `trusted_task.tagged` dans les trois verdicts, déjà présent en 08 (test 7).
- Fuites ([`fuites-synchro-s5.log`](resultats/fuites-synchro-s5.log)) : le secret du webhook du fork est absent des journaux des trois VM (0 sur chacune) ; aucun secret.
- **Seuil de la brique 01** (README racine : branche custom buildée ; force-push amont détecté et archivé ; `git bundle` exporté) : atteint sur l'infra du PoC (S2 à S5). Reste la mesure sur Traefik (S6).

## Jalon S6 : mesure sur Traefik (préparée le 02/11/2026, exécution après S3)

Étape `traefik` de [`forgejo.sh`](forgejo.sh) : `mirror/traefik` alimenté depuis GitHub par le service de la VM ([`traefik.env`](systemd/traefik.env)) ; premier run sans fork (le lanceur accepte `FORK` vide), puis fork `workspace/traefik` et second run ; durées lues dans les horodatages de systemd, taille des bundles, espace disque avant et après ; timer horaire activé ensuite.

**Dimensionnement relevé avant** ([`s6-dimensionnement.log`](resultats/s6-dimensionnement.log), 14:08 UTC, pendant le rejeu de la 08) : Traefik pèse 163 561 Ko selon l'API de GitHub, branche par défaut `master` ; 30 branches et 593 tags, seuls lus par `sync.py` (les 7 704 `refs/pull` et 6 553 `refs/semaphoreci` ne sont pas synchronisés) ; `sc-stockage` : 14 Go libres sur 20 (Forgejo 6,7 Mo, Zot 2,4 Go).

**Prédictions** (écrites le 02/11/2026 à 14:10 UTC, avant toute exécution ; recompte à 14:15 UTC) :
- premier run : quelques minutes (fetch complet avec `transfer.fsckObjects`, push vers `mirror/`), code 0 ; bundle complet de l'ordre de la taille annoncée par GitHub (100 à 250 Mo) ; **620 événements de création** (30 branches, 590 tags, comptés par `git ls-remote --refs` ; le premier décompte, 593, incluait des lignes `^{}` de tags annotés) ;
- risque connu : avec `transfer.fsckObjects=true`, un fetch complet peut s'arrêter sur un défaut fsck d'un objet ancien de l'amont ; ce serait un constat sur l'amont, pas un bogue de `sync.py` ;
- second run : sans événement (ou quelques-uns si l'amont a avancé), aucun bundle ou un bundle de quelques Ko à quelques Mo ;
- espace consommé : moins de 1 Go au total (miroir local, bundles, `mirror/traefik` et fork dans Forgejo) ; l'espace pris par le fork est mesuré, pas supposé (objets partagés ou copiés).

**Résultats** (02/11/2026, 15:22 à 15:23 UTC, accord du propriétaire ; [`forgejo-traefik.log`](resultats/forgejo-traefik.log), [`s6-journal-traefik.log`](resultats/s6-journal-traefik.log)) :

- **Passage archivé** ([`forgejo-traefik-premier-passage.log`](resultats/forgejo-traefik-premier-passage.log)) : arrêt muet après le relevé d'espace, `du` sortant en erreur sur des chemins absents avant le premier run (`set -e`). Rien d'autre n'avait été fait. Corrigé.
- **Premier run** (sans fork) : code 0, **620 événements de création** (30 branches, 590 tags), conforme au recompte ; **bundle complet de 115 428 062 octets** (115 Mo, dans la fourchette prédite de 100 à 250 Mo) ; `master` de `mirror/traefik` = `master` de GitHub. **Durée : 52,1 s** (journal de systemd : 15:22:05,5 à 15:22:57,6), 9,5 s de CPU, pic mémoire de 358 Mo ; plus rapide que prédit (« quelques minutes »). La durée calculée par le script (« 0 s ») est fausse : le journal fait foi.
- **Second run** (avec le fork `workspace/traefik`) : code 0, aucun événement, aucun bundle ; 0,9 s.
- **Espace** (`sc-stockage`) : miroir local 119 Mo, bundles 115 Mo, `mirror/` de Forgejo +119 Mo, **fork +0,1 Mo** (Forgejo partage les objets du fork avec son parent : mesuré) ; disque : +375 Mo, 13,6 Go libres. Conforme (moins de 1 Go).
- **Timer** `synchro@traefik.timer` activé : il a déclenché un troisième run aussitôt (15:23:24, 0,8 s), `OnBootSec=5min` étant dépassé depuis le démarrage de la VM ; prochain run annoncé à 16:25:00 UTC. Celui de `sample-app-sync` est annoncé à 16:16:56 UTC (le délai aléatoire a été retiré de nouveau depuis l'annonce de 16:13:08).
- **Périodicité** (relevé en lecture seule du 02/11/2026 à 16:29 UTC, [`s6-periodicite-timers.log`](resultats/s6-periodicite-timers.log)) : premiers runs planifiés à 16:17:12 (`sample-app-sync`, 1 h 04 min 04 s après le début du dernier run manuel de S4) et 16:25:12 (`traefik`, 1 h 01 min 48 s après le run d'activation), soit `OnUnitActiveSec=1h` plus un délai aléatoire sous les 5 min de `RandomizedDelaySec` : conforme. Runs sans événement ni bundle (amont inchangé), code 0. Écart avec les heures annoncées (16:16:56 et 16:25:00) : 16 s et 12 s, dans la fenêtre de `AccuracySec` (1 min par défaut, valeur non surchargée dans l'unité) ; la cause n'a pas été mesurée.
- Le fsck des objets de l'amont (`transfer.fsckObjects=true`) n'a rien refusé sur l'historique complet de Traefik.
- **Non mesuré** : la taille des incréments quotidiens, qui demande des jours de synchro ; à relever plus tard dans les rapports (`bundle.file`) et dans `bundles/`.

### Refs propres à plusieurs niveaux côté Forgejo (décision (a) du propriétaire, 02/11/2026, 18:38 à 18:39 UTC)

Constat de S2 : le `*` des règles de protection de Forgejo s'arrête aux `/`, celui de `sync.py` non ; `custom/a/b` était créée par `poc-sync`. Décision (a) : motif `**` côté Forgejo, mesuré. Prédictions : [`niveaux-predictions.md`](resultats/niveaux-predictions.md) (18:38:26Z).

- **`protections`** ([`forgejo-protections.log`](resultats/forgejo-protections.log) ; état de S2 : [`forgejo-protections-s2.log`](resultats/forgejo-protections-s2.log)) : chaque `*` d'un motif de branche devient `**` ; `custom/**` et `paquet/**` posées, puis `custom/*` et `paquet/*` retirées par l'API (nom encodé, `%2F` accepté : la prédiction faible d'un 404 est fausse). Tag `custom-*` inchangé.
- **`niveaux`** ([`forgejo-niveaux.log`](resultats/forgejo-niveaux.log)) : création **refusée** à `poc-sync` pour `custom/<n>/b`, `custom/<n>-3/b/c`, `paquet/<n>/deb` et `custom/<n>` (un niveau) ; branche hors motif `essais/<n>/b` acceptée puis supprimée ; `custom/essai` inchangée. **Tag `custom-<n>/x` refusé** avec le seul motif `custom-*` : conforme à la prédiction faible (le motif des tags traverse déjà les `/`).
- **Premier passage, archivé** ([`forgejo-niveaux-premier-passage.log`](resultats/forgejo-niveaux-premier-passage.log)) : tous les refus conformes, mais l'étape créait aussi `custom/<n>/b` par `poc-dev` (liste blanche), puis échouait à la supprimer : **une branche protégée ne peut être supprimée par personne, liste blanche comprise** (« protected from deletion »). Deux conséquences :
  - `custom/n20261102T183831Z/b` restait dans le fork, avec `custom/a/b` de S2 : retirées depuis (étape `retrait`, ci-dessous) ;
  - **ce push a déclenché un vrai build** (webhook du fork, D2 b) : PipelineRun `sample-app-sync-e209907f…` créé à 18:38:36 UTC, pendant O4 de la brique 19 (étape A4, sans lien avec ce build). Build réussi à 18:39:31 UTC, PipelineRun et ses trois TaskRuns signés par Chains (`signed=true`, relevé à 18:39:40 UTC) : aucun échec de signature, donc pas d'effet attendu sur A2. Image au **même digest** que celle de S5 (`3a7ca1b1…`, construction reproductible, relevé à 19:03 UTC) : pas d'image de plus, mais de nouvelles enveloppes signées dans son tag `.att`. Erreur de ma part : l'étape n'aurait pas dû pousser sur `custom/`. Corrigé : `niveaux` ne crée plus aucune branche `custom/`.
- Limite inchangée : `sync.py` protège par `fnmatch`, Forgejo par ses propres globs ; la traduction `*` → `**` vaut pour les motifs à `*` seulement (`?` et `[…]` non traduits, aucun dans `refs-propres.json`).
- **`retrait`** (décision du propriétaire « 3 i », 20:19:33 à 20:20:34 UTC, [`forgejo-retrait.log`](resultats/forgejo-retrait.log), prédictions au bas de [`niveaux-predictions.md`](resultats/niveaux-predictions.md), 20:18:58Z) : branches visées lues dans le fork, `custom/a/b` et `custom/n20261102T183831Z/b`. Suppression par l'API de `poc-admin` **refusée (403) avec la règle**, **acceptée (204) sans elle** ; règle `custom/**` retirée puis remise dans la même seconde (20:19:33), par `protections` (et par un `trap` en cas d'échec). Ensuite : `custom/**`, `paquet/**` et le tag `custom-*` en place, création de `custom/<n>/b` par `poc-sync` de nouveau refusée, `custom/s5` et `custom/essai` inchangées, **plus aucune ref à plusieurs niveaux**. **Aucun build** : 2 PipelineRuns `sample-app-sync-*` avant et 60 s après, aucune ligne de l'EventListener `forgejo-sync` (prédiction faible conforme ; l'absence de ligne ne prouve rien seule, le compte des PipelineRuns est la mesure).

### Porte revérifiée après les builds imprévus (accord du propriétaire « 1 oui », 02/11/2026, 20:15 à 20:18 UTC)

Depuis S5, trois builds de `custom/*` du fork ont produit la même image `builds/sample-app-sync@3a7ca1b1…` : 18:38 (`e209907f`, étape `niveaux`, signé), puis 19:40 (`902ce252`) et 20:00 (`019e0777`), pendant le scellement d'OpenBao (brique 19, A2 : échec en ouvert de Chains, aucune enveloppe). Nouvelle étape `reverification` de [`declencheur.sh`](declencheur.sh) : l'étape `porte` et son journal de 15:18 sont gardés. Prédictions : [`reverification-predictions.md`](resultats/reverification-predictions.md) (20:15:21Z) ; journal : [`declencheur-reverification.log`](resultats/declencheur-reverification.log).

| Source attendue (`workspace/sample-app-sync@…`) | Prédit | Mesuré |
|---|---|---|
| `1599e311` (S5) | refusée : la porte ne jugerait que la provenance la plus récente | **admise** (prédiction fausse) |
| `e209907f` (provenance la plus récente) | admise | admise, 4/4 enveloppes couvertes |
| `019e0777` (tête de `custom/s5`, build en échec ouvert) | refusée | refusée, `slsa_source_correlated.expected_source_code_reference` seule |
| image réelle de la 08, source `workspace/sample-app` | admise, 6/6 | admise, 6/6 |

- Tag `.att` : 4 enveloppes, provenances de PipelineRun de `1599e311` (15:18:26) et `e209907f` (18:39:31) seulement : aucune trace des deux builds en échec ouvert (conforme).
- **Cause de la prédiction fausse, lue dans la bibliothèque épinglée** (conforma/policy v1.0.28, [`reverification-conforma-code.log`](resultats/reverification-conforma-code.log)) : `slsa_source_correlated` prend ses références de source dans `slsa_provenance_attestations`, **toutes** les provenances SLSA de l'image (PipelineRuns et TaskRuns), et ne refuse que si la source attendue n'en cite aucune. Toutes les autres règles chargées par la porte (7 paquets et `porte.rego`) ne lisent que la plus récente (`pipelinerun_attestations`) ; `attestation_type` parcourt aussi toutes les enveloppes, pour le seul contrôle de format (relevé par paquet au même journal). Mon « seule la plus récente est jugée » (08, test 7) valait pour les tâches, pas pour la source.
- Conséquences :
  - le verdict de S5 reste reproductible, et l'image est admise pour la source de **n'importe lequel** de ses builds signés ;
  - une image construite pendant l'échec en ouvert n'est pas admise avec sa vraie source (`019e0777`), mais le même digest l'est avec la source d'un build antérieur : la porte juge un digest, pas un build ;
  - la source et les tâches peuvent venir de deux provenances différentes du même digest : une source admise par une provenance ancienne, des tâches jugées sur la plus récente. Sans effet ici (toutes les provenances citent les tâches de la liste revue), à garder en tête pour la 08.

### Accords et ordre d'exécution

Le rejeu `enchainement` de la 08 est analysé et commité avant toute action sur Forgejo. Accords : **S2** (préparation et exécution après le rejeu) accordé le 02/11/2026 ; **S3** installe un compte système et des unités sur `sc-stockage` : accord à demander ; **S4** suit S3 ; **S5** attend le choix entre (i) et (ii) ; **S6** attend son accord. Les jalons ne s'enchaînent pas d'un seul tenant.

### Rejouer la brique 01 après un rejeu de la 08

Un rejeu de la 08 recrée les VM : Forgejo, Zot, le cluster et l'état de la synchro dans `sc-stockage` repartent de zéro, alors que l'hôte garde `~/.cache/supply-chain-poc/01` et les jetons de `…/08/secrets`. Séquence (lue dans le code le 02/11/2026, pas encore rejouée) :

1. `mise run synchro:forgejo -- comptes organisations amont miroir archives fork protections refus bout_en_bout` : `comptes` recrée les comptes absents et leurs jetons ; `miroir` voit une VM sans état, met de côté l'ancien état de l'hôte (`…/01/anciens/<horodatage>`) et repart d'un miroir neuf ; `refus` trouve un fork neuf ;
2. `mise run synchro:executeur -- installer essai planifie refspec fuites` : reprise du nouvel état de l'hôte dans la VM ;
3. `mise run synchro:forgejo -- negatifs` ;
4. `mise run synchro:declencheur -- pipeline installer construire porte` (après la bascule de la 08 ; `custom/s5` part de `main` sur un fork neuf) ;
5. `mise run synchro:forgejo -- traefik`.

Garde-fou : la synchro depuis l'hôte (`miroir`, `archives`, `bout_en_bout`) est refusée tant que la VM a un état pour le projet (S3 installé).

## Additif du 03/11/2026, 22:43 UTC : rejouée de zéro dans le rejeu `complet` de la 08

S2 à S4 et S6 ont été rejouées sur une plateforme neuve, sans KO :
[`rejeu-complet.log`](../08-trust-plane/resultats/rejeu-complet.log) de la 08.
- Les journaux d'étapes de `resultats/` sont ceux de ce rejeu.
- S5 a été sautée, ainsi que `reverification`, `retrait`, `refspec` et `niveaux`.
- **Raison de S5 (déduite du code, non mesurée)** : la règle D6 de la 03 refuserait l'image du fork, qui n'a pas de fermeture
  propre. Son étape `porte` est de plus écrite en dur sur `3a7ca1b1`.

## Additif du 10/11/2026, 11:03 UTC : la « brique `-custom` » est B7, donc cette brique (S5)

**Accord du propriétaire** : « Oui, consigne », en réponse à « Je consigne ces constats dans le brouillon et les prédictions ? ». **Interprétation** : « ces constats » comprenait ceux sur `-custom`, consignés ici. Rien n'a été lu ni écrit dans Forgejo, le cluster, Zot ou les VM : relecture du dépôt seulement.

**Définition du propriétaire, verbatim** : « -custom, c'est une branche ou un tag pour rebuild un custom patch et ainsi pouvoir le publier ».

*Corrigé à 11:07 UTC, avant tout push, sur relecture du conseiller* : le texte disait que le libellé venait de ma propre liste. C'est faux. Le terme vient du propriétaire, le 09/11/2026 à 13:33 UTC, à propos du binaire corrigé de Kyverno (go1.26.9) : « maintenir une branche -custom qu'on build ». Je l'avais alors repris comme une brique à ouvrir ou non, « composant amont patché, reconstruit par la chaîne ». Le texte disait aussi que ce besoin n'était pas une brique à part. C'est une interprétation, pas un fait.

Ce que le dépôt couvre déjà : l'exigence B7 (doc 01), avec S5 : une branche custom construite et admise par la porte le 02/11/2026. Cette mécanique ne porte que sur `sample-app`. Le cas d'école du propriétaire est un composant amont, Kyverno corrigé, reconstruit par notre chaîne puis publié. Ce cas n'est pas couvert : l'image corrigée de l'étape C (09/11) a été construite sur l'hôte, hors de la chaîne. Ouvrir ou non une brique reste à décider.

**Écarts relevés dans le dépôt, à décider.**
- **Un tag ne déclenche aucun build.** Le filtre du déclencheur ne prend que `refs/heads/custom/` ([`declencheur.sh:89`](declencheur.sh)). Or B7 n'impose pas de motif et cite `custom-*` en exemple.
- **S5 est sautée au rejeu depuis le 03/11.** La règle D6 de la 03 refuserait l'image du fork, qui n'a pas de fermeture propre. C'est déduit du code, pas mesuré (additif du 03/11, 22:43 UTC).
- **L'étape `porte` de S5 est écrite en dur** sur l'image `3a7ca1b1`.

**Questions au propriétaire** :
- que veut dire « publier » : image poussée dans Zot et admise par la porte, ou publication ailleurs ?
- faut-il ouvrir un chantier, avec une estimation ?

Aucune décision n'est prise.
