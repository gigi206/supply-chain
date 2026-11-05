# G7 de la brique 07a : prédictions de g7_sec

Écrites le 04/11/2026, 23:50 UTC, avant le passage formel. **Aveugles en partie seulement :** un passage exploratoire a eu lieu le 04/11/2026 à partir de 23:33 UTC, sur une copie du stockage réel, sans `http.compat`, sans données vieillies et sans mener le balayage à son terme ; il a été arrêté pour ces raisons. Il a montré, avec `gc: true` sans règle ou avec une règle sur `vulndb/grype` seule : 51 et 52 manifestes sans tag de `amont/**` effacés, et 2 Go libérés. Avec une règle fourre-tout sur `**` : 0 effacé sur les dépôts atteints, `builds/` compris à peine. Le code de Zot v2.1.22 (`pkg/storage/gc/gc.go`, `pkg/retention/retention.go`) a aussi été lu avant d'écrire ces lignes. Rien dans la suite n'est donc une découverte : ce sont les valeurs exactes qui sont mises à l'épreuve.

**Décision à l'origine (propriétaire, 04/11/2026, « 2 b ») : D7 (b), une rétention réelle, à concevoir.**

## Ce que dit le code (déduit, pas mesuré)

- `gc: true` sans règle applicable : `deleteUntagged` vaut vrai par défaut. Or `builds/**` et `amont/**` sont poussés par digest, sans tag.
- La première règle dont le motif correspond l'emporte. Une règle fourre-tout `**` sans `keepTags` n'évalue aucun tag.
- `keepUntagged` et `deleteUntagged` ne touchent pas un manifeste portant un `subject` : il est marqué « référencé ». La seule voie est `deleteReferrers`, qui compare le sujet à l'`index.json` **du même dépôt**.
- Dans `builds/scan/*`, le sujet n'est jamais dans le dépôt (R5 l'impose). `deleteReferrers: true` efface donc chaque scan dès qu'il dépasse `retention.delay`, au vu de la date du blob du manifeste : c'est une rétention par âge, pas par nombre.
- `retention.delay` est unique pour tout le store. Il ne joue que là où une règle demande une suppression.
- Un tag retiré laisse une entrée sans tag, retirée à son tour après `retention.delay`.

## Règles proposées (`storage` de `08-trust-plane/stockage/zot.json`)

| Dépôts | Règle | Pourquoi |
|---|---|---|
| `vulndb/grype` | 11 tags les plus récemment poussés | D4 : un scan admis a 7 jours au plus, sa base 3 de plus. Une base citée par un scan encore admis reste lisible. Un timer en panne n'efface rien : le compte ne baisse pas |
| `builds/scan/**` | `deleteReferrers: true`, `retention.delay` de 14 jours | Le double des 7 jours de D4 : aucun scan encore admissible n'est touché |
| `**`, en dernier | Aucune suppression | Images sans tag, signatures, provenances, VSA, images amont |

`gcDelay` 1 h (défaut), pour qu'un blob poussé avant son manifeste ne soit pas pris pour un orphelin ; `gcInterval` 24 h.

## Banc

Copie du stockage réel, en lecture seule ; **tous les blobs vieillis de 30 jours**, sinon le délai de 14 jours masquerait les suppressions à venir sur un store de deux jours. Ajouts synthétiques : 12 bases datées du 05/11 au 16/11, trois referrers de l'image dans `builds/scan/sample-app` (15, 13 et 0 jours), un de 15 jours dans `builds/vsa/sample-app`. Configuration dérivée de `zot.json` : seuls la racine, l'écoute, TLS, l'authentification et les journaux changent, `compat` et `extensions` restent. Le store contient 39 manifestes Docker : sans `compat`, ils seraient d'un type inconnu.

Trois Zot, chacun sur sa copie, jusqu'à la fin d'un balayage complet : sans règle, à blanc (`dryRun`), règles proposées.

## Prédictions

**Règles proposées**

1. Image réelle sans tag, `.sig` et `.att` : lisibles.
2. `builds/vsa/sample-app` : 3 referrers, celui de 15 jours compris (même âge et même forme qu'un scan, autre règle).
3. `builds/scan/sample-app` : restent ceux de 13 et 0 jours ; le scan réel, vieilli à 30 jours, et celui de 15 jours partent.
4. `vulndb/grype` : 11 tags, du 06/11 au 16/11. Le tag du 05/11 est retiré mais la base reste lisible par digest (plus jeune que le délai). La base du 04/11 (30 jours) est effacée : environ 190 Mo libérés.
5. Différence ligne à ligne avec l'inventaire d'avant, prédiction calculée par `awk` : **0 écart**. Disparaissent seulement les entrées de `builds/scan/**` portant un sujet et plus vieilles que le délai, soit 18 (16 de `builds/scan/essai-scan`, le scan réel, celui de 15 jours), et l'entrée de la base du 04/11. `builds/scan/essai-07a`, sans sujet, reste.
6. **0 blob manquant** après le balayage, enfants des index compris.
7. Dépôts disparus : `builds/scan/essai-scan`, vidé, et le dépôt déjà vide `horodatage/essais`.
8. Le journal d'audit porte une décision de suppression pour chaque retrait (format à relever : la requête de `g7_grafana` en dépend).

**À blanc** : 0 entrée modifiée, décisions de suppression journalisées.

**Sans règle** : l'image réelle `3a7ca1b1` est effacée, comme les manifestes sans tag de `amont/**` et de `builds/**`. Effectifs relevés, non prédits.

**Durée** : 123 dépôts ou plus, 15 s par dépôt en moyenne (attente aléatoire de 0 à 30 s) : 30 à 40 min pour le balayage, 1 à 2 min de préparation.

## Résultat

Passage formel du 04/11/2026, 23:50:10 UTC, au 05/11/2026, 00:22:28 UTC, code 0, du premier coup : `g7_sec.log`, décisions de suppression dans `g7-sec-audit-prop.log`. Rien n'a touché le vrai Zot ni le cluster, et la copie de 2,9 Go est effacée.

| Prédiction | Mesure | Verdict |
|---|---|---|
| 1. Image, `.sig`, `.att` lisibles | 200, 200, 200 | Conforme |
| 2. 3 referrers dans `builds/vsa/sample-app` | 3 | Conforme |
| 3. Restent les scans de 13 et 0 jours | Ces deux digests seulement | Conforme |
| 4. 11 tags du 06/11 au 16/11 ; tag du 05/11 retiré, lisible par digest ; base du 04/11 effacée, environ 190 Mo | 11 tags ; 404 par tag, 200 par digest ; 404 ; 2 834 Mo puis 2 644 Mo | Conforme |
| 5. 0 écart ligne à ligne, 18 + 1 entrées retirées | 0 écart ; 483 entrées puis 464 | Conforme |
| 6. 0 blob manquant | 0 | Conforme |
| 7. Dépôts disparus : `builds/scan/essai-scan` et `horodatage/essais` | Ces deux-là, **et** `horodatage/essais-test8/aucun-20261103t215715z` | **Écart** |
| 8. Une décision de suppression au journal d'audit pour chaque retrait | 21 décisions | Conforme, détail ci-dessous |
| À blanc : 0 entrée modifiée, décisions journalisées | 0 modifiée, 21 décisions | Conforme |
| Sans règle : image réelle effacée | Effacée ; 483 entrées puis 364, dont 56 dans `amont`, 30 dans `builds/essai-webhook`, 10 dans `builds/sample-app` ; 0 blob manquant | Conforme |
| Durée : 30 à 40 min de balayage, 1 à 2 min de préparation | 1 896 s environ de balayage, soit 32 min ; 32 min 18 s au total, donc moins d'1 min pour le reste | Balayage conforme ; préparation surestimée |

**Écart de la prédiction 7.** L'inventaire d'avant annonçait 2 dépôts vides, et je n'en avais nommé qu'un. Le second est un dépôt d'essai du test 8 de `preuves.sh` (08), déjà vide. La disparition d'un dépôt vide n'efface aucune entrée et n'écrit aucune décision dans le journal d'audit : elle ne se voit que par comparaison des dépôts.

**Format relevé (prédiction 8), dont dépendent les étapes d'application.** Les 21 lignes portent `"decision":"delete"` et se répartissent ainsi :

- 18 `removed manifest without reference`, module `gc`, raison `deleteReferrers` : 16 dans `builds/scan/essai-scan`, 2 dans `builds/scan/sample-app` ;
- 2 `applied policy`, module `retention`, pour les tags du 04/11 et du 05/11 ;
- 1 `removed untagged manifest`, module `gc`, raison `deleteUntagged` : la base du 04/11. Celle du 05/11, plus jeune que le délai, reste.

Les 2 tags retirés comptent donc comme des décisions sans être des entrées retirées : 21 décisions pour 19 entrées.

**Non mesuré ici.** Le journal d'audit ne porte que les suppressions. Les décisions `keep` vont au journal principal d'après le code (`retention.go`, `logAction` avec `p.log`), et ce journal a été effacé avec la copie sans avoir été lu. `g7_retention` sera la première lecture.

**Message sans conséquence en fin de journal.** `cat: …/zot.pid: No such file or directory` vient du `trap`, qui s'exécute après l'effacement de la copie. Le `trap` est corrigé, pas rejoué.

**Portée.** Les blobs vieillis et les bases et scans synthétiques simulent l'état du store dans deux semaines ; ils ne prouvent rien sur la façon dont Zot se comportera avec un store réellement âgé, écrit jour après jour. La partie `vulndb/grype` repose sur la date de poussée de la base de données de Zot, et non sur celle des blobs : les tags synthétiques ont été poussés dans l'ordre pendant la préparation.
