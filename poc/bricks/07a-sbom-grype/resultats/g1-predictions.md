# G1 : prédictions (écrites le 04/11/2026 à 18:46 UTC, avant toute exécution)

G1 met en place la base Grype et les droits de Zot (D2, D3 a). Ordre prévu, chaque passage soumis à l'accord du propriétaire :

1. `mise run confiance:stockage -- zot` (brique 08) : nouveaux `zot.json` et htpasswd, avec les comptes `poc-vulndb` et `poc-scan`, dont les mots de passe sont générés dans `…/08/secrets`. **Zot redémarre.**
2. `plateforme.sh g1_oras g1_droits g1_base g1_essai` (journaux `resultats/<étape>.log`).

## Relevés préalables (lecture seule, 04/11/2026 vers 18:40 UTC)

- `sc-stockage` a `curl`, `python3` et `zstd`, mais **pas `oras`**.
- `/` a 9,7 Go libres sur 20 Go.
- grype.anchore.io répond 200 depuis la VM.
- Zot tourne avec `gc: false` : rien n'est jamais supprimé.

## Prédictions

**zot**
- Les htpasswd ont 10 comptes : les 8 actuels plus `poc-vulndb` et `poc-scan`. Zot est actif et `/v2/` répond 401 avec la CA du PoC.

**g1_oras**
- La signature GPG de `oras_1.3.6_checksums.txt` est faite par `C6FC42F0…`. L'empreinte de l'archive est celle de `mise.lock`.
- Le binaire extrait est identique à celui de mise (`2be7e2b6…`), installé dans `/usr/local/bin/oras` et revérifié dans la VM.

**g1_droits** (dépôts jetables `builds/scan/essai-07a`, `builds/essai-07a` et `vulndb/essai-07a`, qui resteront dans Zot faute de droit de suppression)

| Essai | Résultat attendu |
|---|---|
| `poc-scan`, par digest dans `builds/scan/` | accepté |
| `poc-scan`, par tag dans `builds/scan/` | refusé |
| `poc-scan`, hors de `builds/scan/` | refusé |
| `poc-images`, dans `builds/scan/` | refusé (le motif `builds/scan/**`, plus long, remplace `builds/**`) |
| `poc-images`, dans `builds/essai-07a` (témoin) | accepté |
| `poc-vulndb`, nouveau tag | accepté |
| `poc-vulndb`, même tag repoussé | refusé, faute du droit `update` (**incertain** : Zot pourrait accepter un manifeste identique sans exiger `update`) |
| `poc-vulndb`, dans `builds/` | refusé |
| `poc-replay`, dans `builds/scan/` | refusé |

**g1_base**
- L'utilisateur `base-grype` est créé. Le mot de passe est en 0600, root. Les deux scripts sont installés identiques au dépôt.
- Exposition de `systemd-analyze security` du même ordre que pour `synchro@` (S3 de la 01).

**g1_essai**
- Premier run réussi : `vulndb/grype:2026-11-04` est créé et relu en lecture anonyme. `artifactType` vaut `application/vnd.supply-chain.grype-db.v6`. Annotations et couche portent l'empreinte de `latest.json` (`sha256:ed08c5e3…` si la base n'a pas changé depuis 06:20 UTC).
- Second run : « déjà archivée », code 0.
- Contre-épreuve : archive tronquée à 1 Mio, « empreinte invalide », code non nul, aucun nouveau tag.
- Mot de passe absent du journal. Timer actif, prochain déclenchement le 05/11/2026 vers 08:00 UTC.
- Le journal de l'unité est consultable dans Grafana, si la 19b collecte le journal de `sc-stockage` (**à vérifier**, pas supposé).

**Correction avant exécution (04/11/2026, 18:46 UTC)** : il y a aujourd'hui 7 comptes, et non 8 (les six de la boucle de `stockage.sh` plus `poc-replay`). Le htpasswd en attend donc **9**, pas 10.

## Résultat (04/11/2026, 19:26 à 19:28 UTC, accord du propriétaire : « Oui ») : conforme, avec un écart de prédiction

Journaux : `../../08-trust-plane/resultats/stockage-zot.log` (l'ancien est gardé sous `stockage-zot-avant-07a.log`), [`g1_oras.log`](g1_oras.log), [`g1_droits.log`](g1_droits.log), [`g1_base.log`](g1_base.log), [`g1_essai.log`](g1_essai.log) et [`g1_grafana.log`](g1_grafana.log).

**zot (19:26 UTC)**
- Le htpasswd compte **9 comptes**, comme prédit après correction. Zot est actif.
- **Écart de prédiction** : `/v2/` répond **200**, pas 401. La lecture anonyme y est permise, ce que montrait déjà le journal précédent. L'erreur vient de la prédiction, pas de Zot.

**g1_oras**
- La signature GPG est faite par `C6FC42F0…`. L'empreinte de l'archive est conforme.
- Le binaire est `2be7e2b6…`, identique à celui de mise. Il est installé et revérifié dans la VM (`oras` 1.3.6).

**g1_droits** : 9 essais sur 9 conformes.
- `poc-scan` ne crée que par digest dans `builds/scan/`.
- `poc-images` et `poc-replay` sont refusés dans `builds/scan/` : le motif le plus long remplace bien `builds/**`. Le témoin `poc-images` reste accepté dans `builds/`.
- `poc-vulndb` crée un tag, puis **ne peut pas le repousser** : le cas incertain est tranché, Zot exige `update` même pour un manifeste identique.
- Résidus jetables : `builds/scan/essai-07a`, `builds/essai-07a` et `vulndb/essai-07a:v1`.

**g1_base**
- Les deux scripts sont installés identiques au dépôt. Le mot de passe est en 0600, root.
- Exposition « 3.0 OK », comme Zot.

**g1_essai**
- Premier run en quelques secondes (pic mémoire de 207,5 Mo) : `vulndb/grype:2026-11-04` → `sha256:13729131…`, relu en lecture anonyme. `artifactType`, empreinte annoncée (`ed08c5e3…`), date de construction et couche sont conformes.
- Second run : « déjà archivée ».
- Contre-épreuve : « empreinte invalide », code 1, aucun nouveau tag.
- Le mot de passe est absent du journal. Le timer est actif ; prochain run le 05/11/2026 à 08:01:55 UTC.

**g1_grafana** : le journal de `base-grype.service` sur `sc-stockage` est lu par l'auditeur à travers Grafana (HTTP 200, deux lignes : archivage et « déjà archivée »), et la réponse ne contient pas le mot de passe. Le point « à vérifier » est donc vérifié.
