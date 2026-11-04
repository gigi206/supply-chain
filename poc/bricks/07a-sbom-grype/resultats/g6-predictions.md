# G6 : prédictions (écrites le 04/11/2026 à 22:43 UTC, avant toute écriture dans Zot)

Les témoins signés du contrôle 7. **Rien n'est appliqué** : Zot, la porte et le cluster sont inchangés. `g6_temoins` attend l'accord du propriétaire.

## Conception

- **Images** : une image à digest propre par cas, `builds/essai-scan:<cas>`, tirée de l'image réelle par `crane mutate`, poussée par `poc-ecriture`, comme les témoins du test 8.
- **Scans** : `scanner.sh` lui-même, modes `attester` et `publier`, avec une clé jetable ; referrers dans `builds/scan/essai-scan`, poussés par `poc-scan`.
- **Clé jetable** : créée au passage, privée effacée ensuite, même en cas d'échec ; sa clé publique est versionnée dans `g6-temoin-cle-publique.pem` et posée dans `porte-temoin`.
- **Prédicats** : ceux du scan réel de G4 et du cas log4j de G0 ([`g6-predicat-kev.json`](g6-predicat-kev.json) : 13 vulnérabilités, 2 KEV, passé par `scan-outil`), datés du passage.
- **Jugement** : `preuves.sh temoins_scan`, un Job de la porte par cas. Seuls les champs 11 et 12 comptent : ces images n'ont ni signature ni provenance, donc ec et les contrôles 6 et 9 les refusent de toute façon.

**Écarts au README** : le KEV est bien le cas log4j, et j'ajoute quatre cas : `futur`, `base-vieille`, `incomplet` et `illisible`. `recent-propre` et `recent-kev` remplacent le « plusieurs scans » laissé non joué en G5.

## Prédictions de `g6_temoins`

Tableau écrit dans `g6-temoins.tsv` par l'étape, avec les digests du passage :

| Cas | ConfigMap | Énoncés | Contrôle 7 | Règle |
|---|---|---|---|---|
| `propre` | `porte-temoin` | 1 | ok | |
| `cle-etrangere` (image de `propre`) | `porte` | 0 | refus | `scan.scan_present`, motif `threshold` |
| `absent` | `porte-temoin` | 0 | refus | `scan.scan_present` |
| `kev` | `porte-temoin` | 1 | refus | `scan.kev_without_vex` |
| `mal` | `porte-temoin` | 1 | refus | `scan.malicious` |
| `vex-expire` | `porte-temoin` | 1 | refus | `scan.kev_without_vex` |
| `vex-valide` | `porte-temoin` | 1 | ok | |
| `vieux` (8 jours) | `porte-temoin` | 1 | refus | `scan.scan_recent` |
| `futur` (1 h) | `porte-temoin` | 1 | refus | `scan.scan_recent` |
| `base-vieille` (4 jours) | `porte-temoin` | 1 | refus | `scan.base_recente` |
| `incomplet` | `porte-temoin` | 1 | refus | `scan.forme` |
| `autre-digest` | `porte-temoin` | 0 | refus | `scan.scan_present` |
| `recent-propre` (hier KEV, aujourd'hui propre) | `porte-temoin` | 2 | ok | |
| `recent-kev` (hier propre, aujourd'hui KEV) | `porte-temoin` | 2 | refus | `scan.kev_without_vex` |
| `illisible` (propre et un referrer qui n'est pas du JSON) | `porte-temoin` | 1 | ok | |

Puis l'image réelle sous `porte` : admise par ec et les contrôles 9, 6 et 7. `porte-temoin` est retirée, 0 écart.

**Autres prédictions :**
- CronJob d'horodatage : bilan inchangé, `12 image(s), 56 enveloppe(s), 2 refusée(s), 1 anomalie(s)`, car `builds/essai-scan` n'a pas de tag `.att`. Relu dans Grafana après coup ;
- `poc-scan` écrit par digest seulement, comme en G4 ;
- environ 8 min pour 16 Jobs.

## Mesuré à sec (04/11/2026, 22:42:51 à 22:43:08 UTC, sur l'hôte) : [journal](g6_sec.log)

Parcours complet dans un espace de noms réseau vide, sur un Zot jetable en TLS : images, signatures et referrers créés par les mêmes fonctions que `g6_temoins`, puis lecture par le cosign de `outils-horodatage@c7bebae2` et jugement par le ec de `porte@e77994c2`, en chroot.

**Les 15 cas sont conformes au tableau.** Mesures utiles :
- `autre-digest` : c'est cosign qui refuse (`provided artifact digest does not match any digest in statement`), avant même `scan.rego` ;
- `illisible` : cosign écarte le referrer illisible et garde le bundle valide ;
- `recent-propre` et `recent-kev` : deux énoncés lus, le plus récent retenu.

**Premier passage** ([archivé](g6_sec-premier-passage.log)) : Zot jetable a refusé le manifeste Docker d'une archive `crane pull` ; la base passe désormais par un layout OCI. Défaut de l'essai seul.

**`temoins_scan`** essayée avec des bouchons à la place de `kubectl` et `juger` : tableau lu, porte-temoin posée et retirée, écart volontaire détecté, code 1.

## Effets à connaître

- Quatorze tags dans `builds/essai-scan` et seize manifestes dans `builds/scan/essai-scan`, sans suppression possible par `poc-scan`. Taille négligeable : même couche que l'image réelle.
- `g5-predictions.md` signale un bundle invalide et plusieurs scans comme non joués : G6 les couvre.
- Les Jobs de la porte restent 1 h, puis sont purgés.

## Non joué à sec

- Les droits réels de Zot : `poc-ecriture` sur `builds/essai-scan` et `poc-scan` sur `builds/scan/essai-scan`. Précédents : le test 8 et G4.
- Les 16 Jobs réels et le passage du CronJob.
