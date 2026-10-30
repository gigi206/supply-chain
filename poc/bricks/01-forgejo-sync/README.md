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

10 tests sur des dépôts git locaux, tous réussis (git 2.43, Python 3.13 ; puis sur le laptop : git 2.53, Python 3.15, locale `fr_FR.UTF-8`).

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

## Reste à faire sur le laptop (infra du PoC)

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
