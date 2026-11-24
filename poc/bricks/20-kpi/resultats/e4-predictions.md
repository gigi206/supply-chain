# Brique 20, étape 4 : préparation de la pose de l'exportateur, prédictions

## Versions sur sc-stockage, prédiction (2026-11-24T20:07:20Z)

Commitée avant le lancement. Accord du propriétaire du 24/11, verbatim « Oui, lecture seule (Recommandé) », à la question « Vérifier maintenant sur sc-stockage, en lecture seule par ssh et sans sudo, la présence et la version de /usr/bin/openssl et de python3 ? ». [`stockage-versions.sh`](../stockage-versions.sh) lance deux commandes de version, rien d'autre.

Attendu, **2 cas, 0 écart** : `OpenSSL 3.5.x` et `Python 3.13.5` (Debian 13 ; versions de trixie lues dans `03-deps-closure/resultats/banc-debian-simulation.log` et `sante-openssl.log`). Le moins sûr : la présence d'openssl.

### Résultat (note de 2026-11-24T20:07:37Z)

[Journal](e4-stockage-versions.log), 2026-11-24 à 20:07:20 UTC, dépôt `f0e1f122` : **2 cas, 0 écart**. `/usr/bin/openssl` est présent sur `sc-stockage` : **OpenSSL 3.5.9** (3.5.5 sur l'hôte où l'essai a tourné) ; `/usr/bin/python3` : **3.13.5** (3.14.4 sur l'hôte). Rien à installer.

La vérification elle-même n'a pas tourné sur `sc-stockage`, ni sous Python 3.13, ni sous une unité durcie. Les deux options d'openssl employées (`pkey -text`, `dgst -verify`) n'y ont pas été exécutées.

**Heures** : de 20:07:03 à 20:07:37 UTC, 0 min 34 s, attente du propriétaire non comptée. Total de la brique : 41 min 49 s.

## Étape 4 à sec, prédiction (2026-11-24T20:28:58Z)

Commitée avant tout passage. Plan relu par le conseiller. Sans accord : banc jetable sans réseau, lectures anonymes de Zot, Grafana par l'auditeur depuis l'hôte, git. Rien n'est posé ; ni ssh, ni sudo. Seules exécutions avant cette prédiction : le vecteur publié contrôlé par openssl et cosign, une unité utilisateur vide (`true`, code 0), `systemd-analyze security` sur `entrees-scan.service` (note 2,9).

Écrit, avec le sha256 (16 caractères) au moment de la prédiction :

- [`metrics_exporter.py`](../../../../tools/metrics-exporter/metrics_exporter.py) (`377132fccf3fc2eb`) : vecteur de test RFC 6979 A.2.5 (P-256, SHA-256, « sample », 72 octets, accepté et refusé à un octet près par openssl et par cosign), vérifié avant toute lecture de Zot ; dates des clés (liées à l'empreinte du fichier) et des pins (liées au digest) depuis un relevé versionné ; heure du dernier passage réussi ; valeurs d'étiquettes venues des énoncés ou du journal filtrées ; docstring à jour ;
- [`lecteur_loki.py`](../../../../tools/metrics-exporter/lecteur_loki.py) (`2a37871827f96592`) : lecteur séparé, pour que l'exportateur ne porte aucun secret. Son accès en service reste un choix du propriétaire ;
- [`releve-dates.py`](../releve-dates.py) (`1fa65c413130483f`) : écrit `releve/dates-git.tsv`, sous `poc/bricks/20-kpi/` parce que `HORS_CONF` l'exclut de la recherche des pins ;
- [`kpi.service`](../systemd/kpi.service), [`kpi.timer`](../systemd/kpi.timer), [`unite-hote.sh`](../unite-hote.sh) (`f19c0e365f2dcfe3`) ;
- banc : `banc.sh` (`569d1fde9ff8001b`), `banc_temoins.py` (`111e4b3f37b2a059`), `banc_comparer.py` (`7eb1bdb14136c02f`), `lecteur_banc.py` (`62ce34e45650db11`) ; vrai Zot : `exportateur-zot.sh` (`3f0f8cf219d4f08d`), `comparer_zot.py` (`fe68bd134a7a6cb8`).

### Attendus

1. **Relevé** (`releve-dates.py ecrire`, puis commit, puis `verifier`) : 5 clés et **27 pins** (digests distincts des 42 lignes `pin_date` de `e3b-exportateur-zot.log`, dont 3 non épinglés et 0 retiré), puis « identique à git ». Le relevé commité ne doit changer aucune date (piège `HORS_CONF`).
2. **Banc** (`e4-banc.log`), **59 cas, 0 écart** : recalcul 5, comparaison 24, contrôles de l'étape 4 : 4, lecteur 11, arrêts 15. 40 écarts prédits en mode compté (39 avant, plus `banc-pins`), aucun en mode vérifié. 27 attestations vérifiées et 13 refusées, 10 signatures d'image vérifiées et 4 refusées.
   - `banc-pins` a quatre provenances : seule compte la plus récente des PipelineRun vérifiées. Une TaskRun et une provenance à clé étrangère, toutes deux plus récentes, sont ignorées en mode vérifié ; la fausse gagne en mode compté.
3. **Vrai Zot** (`e4-exportateur-zot.log`), **10 cas, 0 écart** : 105 valeurs (56, plus 42 pins, 5 clés, 2 délais de KEV), 0 sans date, 0 série de KEV, 41 signatures vérifiées. Les délais de KEV sont égaux **parce qu'aucune KEV n'est vue** : seule l'absence est prouvée. Le journal lu doit contenir des résumés (sinon le zéro serait vide) et 0 entrée KEV.
4. **Unité sur l'hôte** (`e4-unite-hote.log`), **23 cas, 0 écart**. Le moins sûr : les sondes de l'unité utilisateur (certaines protections peuvent y être sans effet), puis `/proc/self/fd` sous le durcissement et le Python 3.13 de mise monté sur `/mnt`.

### Limites connues d'avance

`IPAddressDeny`, l'utilisateur dédié, le noyau, systemd et Python de `sc-stockage` ne sont pas exercés. Le lecteur est essayé contre un serveur factice puis contre le vrai Grafana par le compte de l'auditeur, pas sous une unité. Témoins, attendus et outils sont écrits dans la même session.

### Premier passage du banc raté, correction (2026-11-24T20:29:41Z)

[`e4-banc.log`](e4-banc.log) (20:29:15 UTC) : 5 écarts, une seule cause, dans le témoin et non dans l'exportateur. `banc-pins` avait été inséré juste avant l'écriture de `SCANS`, qui désignait donc son digest : `entrees-scan.py` n'a vu aucun scan de `banc-kev`, et les délais de KEV manquaient partout, recalcul compris. Les 15 arrêts, les 11 cas du lecteur et les dates de pins étaient déjà conformes. `banc-kev` est remis en dernier ; attendu inchangé, **59 cas, 0 écart**, journal `e4-banc-2.log`.

Relevé écrit à 20:29:09 UTC : 5 clés, 27 pins, conforme ; `verifier` sera lancé après son commit.
