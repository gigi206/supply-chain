# Brique 01 : synchronisation des miroirs (partie locale)

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

## Reste à faire sur le laptop (infra du PoC ; protocole plus bas)

- Vrai Forgejo : dépôt `mirror/<projet>` réservé au compte de synchronisation, jeton en secret Kubernetes, fork `workspace/<projet>` pour les branches custom ; **build d'une branche custom** par le pipeline (brique 08).
- **Refs protégées configurables** (exigence du propriétaire du 30/10/2026, B7) : les branches et tags propres, absents de l'amont, ne sont jamais perdus par une synchro ; les refs à préserver se configurent globalement et par dépôt git, le motif n'est pas imposé (par exemple `custom-*`). Proposé, à valider avec le propriétaire : configuration par dépôt qui complète ou remplace la globale, portée miroir et fork, traitement des collisions ci-dessous. État vérifié dans le code le 30/10/2026 :
  - miroir local : seules `refs/upstream/*`, `refs/archive/*` et `refs/sync/*` sont écrites, toute autre ref est préservée. Le test ne couvre que `refs/heads/custom/*` et `refs/notes/*` : ni tag, ni autre motif, ni configuration. Les bundles et la restauration ne portent que `upstream` et `archive` : une ref propre du miroir local ne serait pas restaurée ;
  - publication vers `mirror/<projet>` : `git push --force --prune` des branches et des tags (`push()`) supprimerait toute branche ou tout tag absent de l'amont. Une ref propre ne doit donc pas y vivre, ou doit être exclue du prune par un refspec négatif ;
  - mise à jour du fork `workspace/<projet>` depuis le miroir : pas encore conçue. Elle ne doit ni supprimer ni écraser une ref protégée (pas de `--prune`, refspec qui exclut les motifs protégés) ;
  - collision : une branche ou un tag amont qui correspond à un motif protégé est aujourd'hui publié tel quel dans `mirror/`. Proposé : événement critique dans le rapport, aucune propagation vers le fork ;
  - tests à ajouter : tag protégé, motif `custom-*` et autre motif configuré, configuration par dépôt, collision amont sur une branche et sur un tag, mise à jour du fork sans perte.
- CronJob Kubernetes, métrique « dernière synchronisation réussie » pour l'alerte « miroir en retard de plus de 24 h » (brique 19).
- Mesure sur **Traefik** (durée, taille du premier bundle et des bundles incrémentaux).
- Signature des rapports et des bundles, puis archivage WORM (briques 09 et 15).

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
| `sync_derniere_reussite_timestamp_seconds{projet}` | Fin du dernier run de statut `ok` ou `rewrite-detected` |
| `sync_derniere_reecriture_timestamp_seconds{projet}` | Dernier run de statut `rewrite-detected` |
| `sync_dernier_run_statut{projet,statut}` | 1 pour le statut du dernier run, 0 pour les autres |

### Jalons

| # | Jalon | Contenu | Contrôle de fin |
|---|---|---|---|
| **S1** | B7 hors cluster | `sync.py` : configuration globale et par dépôt (fichier versionné, motifs `fnmatch` sur les branches et sur les tags), refspecs négatifs au push vers `mirror/` (`^refs/heads/<motif>`, git ≥ 2.29), mise à jour du fork sans `--prune` qui exclut les motifs de refs propres, collision ; renommage de `--protected` | Nouveaux tests `test_sync.py`, tous réussis avec les 10 anciens, sous `C` et `fr_FR.UTF-8` (liste ci-dessous) |
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

**Prédictions** (écrites le 02/11/2026 à 14:05 UTC, avant toute exécution) :
- `comptes` : trois comptes ordinaires (non administrateurs), un jeton `write:repository` chacun ; aucun mot de passe conservé ;
- `miroir` : premier run de `sync.py` à code 0, `main` de `mirror/sample-app` = `main` de l'amont ; dans le journal de Forgejo, des pushes vers `mirror/` seulement ;
- `fork` : `workspace/sample-app-sync` marqué fork de `mirror/sample-app`, même `main` ; équipes de `workspace` limitées à ce dépôt ;
- `refus` : refusés (HTTP 403 ou refus de branche ou de tag protégé) : push de `poc-dev` et de `poc-amont` vers `mirror/`, push de `poc-sync` vers `workspace/sample-app`, création, réécriture et suppression de refs propres du fork par `poc-sync` ; acceptés : refs propres du fork par `poc-dev`, branche ordinaire du fork par `poc-sync` ;
- mesures sans attendu ferme : réécriture forcée de `custom/essai` par `poc-dev` (liste blanche ; **acceptée**, prédiction faible : aucune option de force-push) ; par `poc-admin` avec `apply_to_admins` (**refusée**) ; tag propre par `poc-admin` (**refusé**, prédiction faible : la protection de tag n'a pas d'option pour les administrateurs) ; push de `poc-admin` vers `mirror/` (**accepté** : l'administrateur passe outre les équipes, limite à consigner) ;
- `bout_en_bout` : code 2 (collision sur `custom/essai`), collision publiée dans `mirror/`, `custom/essai` du fork inchangée, `main` du fork avancée, tag `custom-1` intact.

**Avant l'exécution** : tâche `synchro:forgejo` à déclarer dans `mise.toml`, après le rejeu, car celui-ci lit `mise.toml` à chaque étape.

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

## Jalon S4 : tests négatifs sur le vrai Forgejo (préparé le 02/11/2026, exécution après S3)

Étape `negatifs` de [`forgejo.sh`](forgejo.sh) : `poc-amont` réécrit l'amont d'essai, puis chaque fois un run du service `synchro@sample-app-sync` de la VM (S3) ; contrôle du code (`ExecMainStatus`), du rapport, de l'archive publiée dans `mirror/`, du fork, puis restauration dans la VM.

**Prédictions** (écrites le 02/11/2026 à 14:08 UTC, avant toute exécution ; heure d'abord mal notée, 14:10) :
- force-push de `main` : code 2, événement `force-push`, ancienne tête sous `refs/archive/<horodatage>/heads/main` dans `mirror/`, `main` du fork alignée sur l'amont ;
- tag `v1.0.0` créé (code 0), déplacé (code 2, `tag-moved`, archive publiée), supprimé (code 2, `tag-deleted`, archive publiée, retiré de la vue amont de `mirror/`) ; dans le fork, le tag garde sa dernière valeur (pas de `--prune`) ;
- branche `feature/x` créée puis supprimée : code 0 les deux fois, archive publiée, branche gardée dans le fork ;
- refs propres du fork (`custom/essai`, `paquet/deb`, `custom-1`) intactes après toutes les réécritures ;
- restauration depuis les bundles et les rapports de la VM : refs `upstream` et `archive` identiques au miroir local.
