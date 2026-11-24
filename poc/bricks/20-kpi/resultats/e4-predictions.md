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

### Deuxième passage du banc, vrai Zot, premier passage de l'unité (2026-11-24T20:30:47Z)

- [`e4-banc-2.log`](e4-banc-2.log) : **59 cas, 0 écart**. `releve-dates.py verifier` après le commit du relevé : identique à git, 0 ligne différente (le piège `HORS_CONF` est évité).
- [`e4-exportateur-zot.log`](e4-exportateur-zot.log) (20:30:01 UTC) : **10 cas, 0 écart**, 105 valeurs, 41 signatures vérifiées. Journal lu par `lecteur_loki.py` dans le vrai Loki : 5 résumés, 0 entrée KEV. **La durée écrite (« -231 ms ») est fausse** : le `date` de l'hôte (uutils 0.10.0) rend `%3N` sans zéro de tête (mesuré à 20:30:37 UTC). Remplacé par `/proc/uptime` ; le passage `-2` donnera la durée.
- [`e4-unite-hote.log`](e4-unite-hote.log) (20:30:13 UTC) : **23 cas, 3 écarts**, une seule cause. `systemd-run` cherche l'exécutable hors de l'unité, où `/mnt/bin/python3` n'existe pas : Python 3.13 n'a pas été lancé. Le reste est conforme : sous le durcissement, openssl par `/proc/self/fd` vérifie les 41 signatures, la sortie est la même, et les 6 sondes sont permises sans l'unité et refusées dedans. La durée de ce journal (« 505 ms ») n'est pas fiable non plus.

Corrigé : Python 3.13 lancé par `/usr/bin/env`. Attendu du second passage : unité **23 cas, 0 écart** (`-2`) ; vrai Zot **10 cas, 0 écart** (`-2`).

### Résultat (note de 2026-11-24T20:31:26Z)

- [Unité, second passage](e4-unite-hote-2.log) : **23 cas, 0 écart**. Même sortie sans durcissement, durcie avec Python 3.14.4 et durcie avec Python 3.13.12 (132 séries) ; 41 signatures vérifiées, 0 refusée ; note hors ligne 2.9, celle de `entrees-scan.service`.
- [Vrai Zot, second passage](e4-exportateur-zot-2.log) : **10 cas, 0 écart** ; 440 ms pour l'exportateur (`/proc/uptime`).
- [Banc, second passage](e4-banc-2.log) : **59 cas, 0 écart**.

Dans chaque cas, le premier passage est gardé : banc (5 écarts, témoin mal placé) et unité (3 écarts, Python 3.13 non lancé). Les deux fautes étaient dans le banc et dans le script, pas dans l'exportateur ni dans l'unité.

**Ce que cela prouve** : un openssl qui accepte tout ou refuse tout arrête l'exportateur avant toute lecture de Zot ; les dates des clés et des pins sont celles du recalcul, et un fichier ou un digest inconnu du relevé est compté au lieu d'être daté ; la vérification par `/proc/self/fd` survit au durcissement de l'unité, sous Python 3.14 et 3.13.

**Ce que cela ne prouve pas** :
- rien n'a tourné sur `sc-stockage` : ni son noyau, ni son systemd, ni son OpenSSL 3.5.9, ni `IPAddressDeny`, ni l'utilisateur `kpi`. Prometheus et Grafana n'ont pas lu ces séries ;
- les délais des KEV restent prouvés au banc seulement : 0 KEV dans le vrai Loki ; et les lignes de `entrees-scan` ne sont pas vérifiées ;
- `lecteur_loki.py` n'a pas tourné sous une unité, et son accès en service n'est pas choisi ;
- le relevé des dates périme après chaque rejeu, reconstruction ou re-signature (R5 compris si une provenance ou une clé change) : `verifier` est à relancer avant chaque pose ;
- témoins, attendus et outils sont de la même session.

**Heures** : de 20:18:37 UTC à cette note, 12 min 49 s. Total de la brique : 54 min 38 s.

## Journal malformé, prédiction (2026-11-24T20:35:07Z)

Relecture du conseiller : dans la version mesurée ci-dessus, une seule ligne malformée du journal (non signé ; tout porteur d'un certificat de la CA écrit dans Loki, limite de D16) donne le code 2 et fige toutes les séries vérifiées. Lu dans le code, non mesuré. Corrigé : les séries de KEV disparaissent et `kpi_exportateur_journal_illisible` passe à 1, le reste est écrit. Commentaire de `kpi.service` corrigé (chemin de `tsa.pem`), aucune directive changée. Exportateur `98f917abe061b8b1`, `banc.sh` `1912e1a8028c0583`.

Attendu, journaux `-3` : banc **62 cas, 0 écart** (59, plus 3 journaux malformés : JSON coupé, dépôt absent, date illisible) ; vrai Zot **10 cas, 0 écart** ; unité **23 cas, 0 écart**.

Écarts « comptées » comptés dans `e4-banc-2.log` : 40 lignes `ECART|comptées`, le nombre prédit.

### Résultat (note de 2026-11-24T20:35:53Z)

Journaux [banc](e4-banc-3.log) (20:35:07 UTC), [vrai Zot](e4-exportateur-zot-3.log) (20:35:22 UTC), [unité](e4-unite-hote-3.log) (20:35:32 UTC), dépôt `c34d91e1` : **62, 10 et 23 cas, 0 écart**, au premier passage de cette version. Un journal malformé laisse les séries vérifiées intactes (0 différence), retire les séries de KEV et met `kpi_exportateur_journal_illisible` à 1.

Limites ajoutées :
- une ligne **bien formée** mais fausse dans Loki fausse les délais de KEV sans être vue : le journal n'est pas signé ;
- `unite-hote.sh` reprend le durcissement de `kpi.service`, mais passe ses propres variables et chemins : les `Environment` et `ReadWritePaths` de l'unité n'ont pas tourné.

**Heures** : de 20:18:37 UTC à cette note, 17 min 16 s (remplace le compte de la note précédente). Total de la brique : 59 min 05 s.

## Compte Grafana Viewer et Loki : prémisse à vérifier, prédiction (2026-11-24T20:47:50Z)

Commitée avant le lancement, sur relecture du conseiller. La décision « Compte Grafana Viewer (Recommandé) » a été prise sur une phrase **non mesurée** du README : « n'écrit pas dans Loki ». Les routes de la source Loki (`plugin.json` 13.2.2, lu dans l'archive de Grafana 13.3.0) ne listent pas `/loki/api/v1/push` et ne disent pas ce que le proxy fait d'un chemin absent.

[`banc-grafana.sh`](../banc-grafana.sh) : Grafana 13.3.0 et Loki 3.7.9 jetables, mTLS, sans réseau, archives en cache. Attendu : **16 cas**, dont deux sont des paris sur le proxy, pas des lectures :
- écriture par le proxy de la source avec le compte Viewer : **204, 1 ligne** (elle passe). C'est le moins sûr, et c'est la mesure qui compte ; si elle passe, la prémisse de la décision est fausse et `auditeur` a le même pouvoir ;
- écriture par les ressources de la source : **404, 0 ligne**.

Le reste : témoins directs (3), compte créé, rôle Viewer, lecture (3), écriture de l'administrateur par le proxy (204, 1), lecteur et délais (7). Les autres chemins (`/config`, `/metrics`, `log_level`, `flush`, suppression, `/ingester/shutdown`) sont mesurés sans attendu.

### Premier passage, 5 écarts ; second passage, prédiction (2026-11-24T20:48:55Z)

[`e4-banc-grafana.log`](e4-banc-grafana.log) (20:47:52 UTC) : 15 cas (16 annoncés, faute de compte), 5 écarts.
- **Le pari était faux, la prémisse tient pour les POST** : écriture par le proxy **403, 0 ligne**, pour le Viewer (et pour l'administrateur) : « non allow-listed POSTs not allowed on proxied loki datasource ».
- Mais des GET non listés passent : `/config` et `/metrics` en 200. Or certains chemins de Loki agissent sur un simple GET (`/flush`, `/ingester/shutdown`) : non mesurés à ce passage, qui n'avait essayé que POST.
- 3 écarts du lecteur, même cause : Python refuse le certificat jetable (extensions manquantes en vérification stricte) ; les certificats de la plateforme passent (passages de 20:30 à 20:35 UTC).

Second passage (`-2`), attendu **16 cas, 0 écart** : écritures POST et PUT en 403, lecteur et délais conformes. Mesuré sans attendu chiffré, pari écrit : **GET `/ingester/shutdown` par le proxy arrête Loki**.

### Deuxième passage, et code de sortie de Loki, prédiction (2026-11-24T20:50:14Z)

[`e4-banc-grafana-2.log`](e4-banc-grafana-2.log) (20:48:55 UTC) : **16 cas, 0 écart**. Écritures POST et PUT refusées (403), administrateur compris. **Pari tenu : un compte Viewer arrête Loki par GET `/ingester/shutdown` à travers le proxy de la source** (HTTP 204, Loki arrêté). Passent aussi en GET : `/flush` (204), `/log_level` (200), `/config`, `/services`, `/metrics`, `/ingester/prepare_shutdown` (200). Lecteur et délais conformes ; réponse tronquée refusée, fichier inchangé.

Le compte `auditeur` de la plateforme a le même rôle Viewer : **défaut existant de la 19b**, indépendant de la 20. Non essayé sur la plateforme, et il ne doit pas l'être.

Troisième passage (`-3`) : `loki.service` a `Restart=on-failure` ; attendu, code de sortie **0** (systemd ne relancerait donc pas Loki). **17 cas, 0 écart**. Le moins sûr : ce code.

### Résultat du banc Grafana (note de 2026-11-24T20:54:14Z)

[Troisième passage](e4-banc-grafana-3.log) (20:50:15 UTC, dépôt `a50c31b9`) : **17 cas, 0 écart**. Loki arrêté par GET `/ingester/shutdown` à travers le proxy, compte Viewer, code de sortie **0**.

- **Mesuré, au banc seulement** : écriture POST et PUT par le proxy refusée (403, 0 ligne) ; par les ressources, POST 404. Loki s'arrête sur le GET, avec le code 0.
- **Codes seuls, effet non mesuré** : GET `/flush` 204, GET `/log_level` 200, `/ingester/prepare_shutdown` 200 ; GET `/config`, `/services`, `/metrics` 200.
- **Lu, non mesuré** : `loki.service` a `Restart=on-failure`, donc systemd ne le relancerait pas après une sortie 0. Prometheus ne collecte pas Loki, mais la règle `LokiInjoignable` (critique, aucun envoi réussi d'Alloy vers Loki depuis 5 min, puis `for: 2m`) est faite pour ce cas ; elle n'a pas été exercée sur cet arrêt.
- **Hors mesure** : la plateforme (rien n'y a été essayé), la source Prometheus, les autres rôles.

La phrase « n'écrit pas dans Loki » tient pour ces chemins ; « lecture seule » était **faux** : le prix posé au propriétaire était incomplet. L'unité du lecteur et le script de pose ne sont pas écrits : ils attendent sa réponse.

**Heures** : de 20:43:08 UTC à cette note, 11 min 06 s. Total de la brique : 1 h 10 min 11 s.

## Décisions du propriétaire et correction à chercher, prédiction (2026-11-24T20:56:06Z)

Réponses verbatim (avant 2026-11-24T20:55:04Z) : accès du lecteur, prix corrigé, **« Compte Grafana Viewer (Recommandé) »** (ne vaut pas accord de pose) ; défaut de la 19b, **« Chercher une correction à sec »** ; poussée, **« Oui, pousse »** (faite jusqu'à `32cad1c1`, 20:55:04 UTC).

Candidat lu dans `conf/defaults.ini` de l'archive de Grafana 13.3.0 : `data_source_proxy_whitelist` ([security]). Hypothèse à éprouver : la liste ne joue que sur `/api/datasources/proxy`, pas sur `/api/ds/query` ni sur les ressources. Mise à `127.0.0.1:9090`, elle ne laisserait au proxy que la source Prometheus, dont des relevés archivés se servent (07a, `base-grype-24.sh`, `tableau-pose.sh` lit la source sans proxy).

`VARIANTE=liste banc-grafana.sh` (journal `e4-banc-grafana-liste.log`). Attendu **40 cas, 0 écart** : les 16 de la configuration en service (écritures toujours 403, lecteur et délais conformes), puis 22 :
- marchent encore : requête, étiquettes de l'explorateur, santé, proxy vers Prometheus (502, rien n'écoute) ;
- 403 : `/config`, `/flush`, `/log_level`, `/loki/api/v1/labels` par le proxy, Viewer et administrateur ;
- Loki reste vivant après 5 formes d'arrêt par le proxy (identifiant numérique, double barre, `%2e%2e`, remontées) et 5 par les ressources ;

et 2 sur systemd : un programme qui sort avec le code 0 est relancé par `Restart=always`, pas par `Restart=on-failure`. Les moins sûrs : les remontées de chemin par les ressources, puis la portée de la liste.

### Résultat de la variante « liste », et pose préparée, prédiction (2026-11-24T20:59:41Z)

[`e4-banc-grafana-liste.log`](e4-banc-grafana-liste.log) (20:56:06 UTC, dépôt `ab327c34`) : **40 cas, 0 écart**, au premier passage. Avec `data_source_proxy_whitelist = 127.0.0.1:9090`, tout GET vers Loki par le proxy est refusé (403), administrateur compris ; Loki survit aux 10 formes d'arrêt essayées ; requêtes, étiquettes, santé et lecteur inchangés. `Restart=always` relance après une sortie 0, `on-failure` non.
Limites : banc ; le suivi en direct de l'explorateur (websocket par le proxy) n'est pas essayé et devrait être perdu ; les porteurs d'un certificat client de la CA gardent l'accès direct à Loki (D16) ; l'interface n'a pas été ouverte.

Écrits à sec : [`kpi-journal.service`](../systemd/kpi-journal.service) ; `kpi.service` (JOURNAL, Wants, groupe du journal) ; [`kpi-pose.sh`](../kpi-pose.sh), qui refuse la pose si le relevé est périmé ou si le proxy mène encore à Loki ; [`liste-proxy.sh`](../../19b-journalisation/liste-proxy.sh). `config/grafana.ini` n'est **pas** modifié : il le sera sur accord.

Attendu, lecture seule :
- `kpi-pose.sh sec` (`e4-kpi-pose-sec.log`) : 3 cas, 0 KO ; mot de passe absent ;
- `unite-hote.sh` (`e4-unite-hote-4.log`) : **27 cas, 0 écart** (23, plus le durcissement du lecteur et 3 sur le lecteur durci avec `LoadCredential`). Le moins sûr : `LoadCredential` sous le gestionnaire utilisateur ; s'il est refusé, c'est une réserve pour la pose ;
- `liste-proxy.sh avant` (19b, `resultats/liste-proxy-avant.log`), auditeur, seul chemin de Loki demandé : `/loki/api/v1/status/buildinfo` : **5 cas, 0 KO**, proxy vers Loki **200** (le défaut existe sur la plateforme pour les GET ; rien d'actif n'est essayé).

### Passages de 20:59, et dernier passage de l'unité, prédiction (2026-11-24T21:00:10Z)

- [`e4-kpi-pose-sec.log`](e4-kpi-pose-sec.log) (20:59:43 UTC) : 3 cas, 0 KO.
- [`liste-proxy-avant.log`](../../19b-journalisation/resultats/liste-proxy-avant.log) (20:59:52 UTC) : 5 cas, 0 KO. **Sur la plateforme, le proxy mène à Loki pour l'auditeur** (GET `buildinfo` : 200). Aucun chemin qui agit n'y a été demandé.
- [`e4-unite-hote-4.log`](e4-unite-hote-4.log) : 27 cas, **3 écarts**, deux causes : la note de `kpi.service` est 3.0 (2.9 attendu ; `SupplementaryGroups`, oublié dans la prédiction) ; le lecteur ne lit pas son mot de passe, car `ProtectHome=true` masque `/run/user`, où le gestionnaire utilisateur met les identifiants. La réserve annoncée vaut.

Dernier passage (`-5`), `ProtectHome` retiré pour le lecteur seulement, notes attendues « 2.9 3.0 2.9 » : **27 cas, 0 écart**. En cas d'écart, réserve, sans nouvel essai.

### Résultat (note de 2026-11-24T21:00:36Z)

[`e4-unite-hote-5.log`](e4-unite-hote-5.log) : **27 cas, 0 écart**. Le lecteur durci (sauf `ProtectHome`) lit son mot de passe par `LoadCredential` et 5 lignes dans le vrai Grafana ; `LoadCredential` avec `ProtectHome=true` reste à exercer sur la VM (`base-grype.service`, en service, a les deux).

Rien n'est posé : ni la liste, ni le compte, ni l'exportateur. `kpi-pose.sh` (compte, pose, verif, retrait) et `liste-proxy.sh` (pose, apres, retrait) n'ont pas été lancés.

**Heures** : de 20:55:04 UTC (réponses du propriétaire) à cette note, 5 min 32 s. Total de la brique : 1 h 15 min 43 s.

### Réserves et corrections sur relecture du conseiller (note de 2026-11-24T21:03:47Z)

- Les « 40 cas » de `e4-banc-grafana-liste.log` : 38 au bilan du journal, plus 2 cas systemd hors bilan. Le cas `proxy/2/…` (404) ne prouve rien : l'identifiant numérique de la source n'a pas été relu. Il reste 9 formes d'arrêt probantes.
- Le 200 de `buildinfo` sur la plateforme ne prouve pas qu'un GET non listé y passe : `buildinfo` est une route listée de la source. **La présence du défaut sur la plateforme est déduite du banc**, pas mesurée.
- `Restart=always` est mesuré sur un `sleep`, pas sur Loki : complément, pas correction.
- Non exercés : lecture de `lignes` par `kpi` à travers le groupe, `Wants` avec un lecteur en échec, `LoadCredential` avec `ProtectHome=true`, la forme de `IPAddressDeny` relue par la pose. Un journal absent ou illisible pour `kpi` donne le code 2 et fige tout ; la pose le verrait.
- `liste-proxy.sh` : si Grafana ne revient pas, la copie est remise et le script s'arrête. `kpi-pose.sh` : le dossier qui porte le mot de passe est effacé depuis l'hôte sur tout échec après la copie. Non lancés.
- Le refus de `kpi-pose.sh pose` tant que le proxy mène à Loki est un choix de session : à poser au propriétaire.

## Poses, accords et prédiction (2026-11-24T21:07:15Z)

Réponses verbatim du propriétaire (avant 2026-11-24T21:07:03Z) : **« Liste, compte, pose (Recommandé) »** (trois accords, dans cet ordre, arrêt au premier KO) ; **« Oui, pousse »** (faite jusqu'à `010bb6a9`, 21:07:03 UTC) ; Chains v0.30.0 : **« Banc à sec après R5 »**.

1. `liste-proxy.sh pose` (19b, `resultats/liste-proxy-pose.log`) : **10 cas, 0 KO** (ligne dans le dépôt, fichier en service égal au dépôt sans la ligne, pose, Grafana actif, fichier égal, 5 contrôles : proxy vers Loki 403). Le moins sûr : l'égalité du fichier en service, puis le contrôle juste après le redémarrage.
2. `kpi-pose.sh compte` (`e4-kpi-compte.log`) : **5 cas, 0 KO**, rôle Viewer.
3. `kpi-pose.sh pose` (`e4-kpi-pose.log`) : **20 cas, 0 KO** : 5 avant (dont le proxy à 403), 2 empreintes, dossier effacé, 2 passages `success`, timer, mot de passe refusé à `kpi`, filtre des deux unités (2), signatures refusées 0, vérifiées « oui », sans date 0. 134 séries environ, 41 signatures vérifiées. Les moins sûrs : `LoadCredential` avec `ProtectHome=true`, la lecture du journal par le groupe, la forme d'`IPAddressDeny`.
4. `kpi-pose.sh verif` (`e4-kpi-verif.log`), après une collecte de Prometheus : **4 cas, 0 KO**.

### Résultat des poses (note de 2026-11-24T21:09:31Z)

- [`liste-proxy-pose.log`](../../19b-journalisation/resultats/liste-proxy-pose.log) (21:07:17 UTC) : **10 cas, 0 KO**. Le proxy vers Loki répond 403, celui vers Prometheus 200 ; requêtes et étiquettes inchangées. `grafana.ini` en service était égal au dépôt sans la ligne.
- [`e4-kpi-compte.log`](e4-kpi-compte.log) (21:07:28 UTC) : **5 cas, 0 KO**, rôle Viewer, connexion vérifiée.
- [`e4-kpi-pose.log`](e4-kpi-pose.log) (21:07:28 UTC) : **16 cas, 0 KO** (20 annoncés : faute de compte, 5 + 11 = 16). 134 séries, 41 signatures vérifiées, 0 refusée, 0 clé ni pin sans date, journal lisible. Levées : `LoadCredential` avec `ProtectHome=true`, lecture du journal par le groupe, `/proc/self/fd` sous l'unité réelle, OpenSSL 3.5.9 et Python 3.13.5 de `sc-stockage`. Notes d'exposition : 3.0, 2.9, comme à sec.
- [`e4-kpi-verif.log`](e4-kpi-verif.log) (21:09:00 UTC) : **4 cas, 0 KO**, 134 séries dans Prometheus.

Non exercés encore : un passage du timer, `Wants` avec un lecteur en échec, les refus réseau des filtres (seule la propriété est relue).

## Étape 5, le seuil, prédiction (2026-11-24T21:09:31Z)

[`seuil.sh`](../seuil.sh) : séries de Prometheus lues par l'auditeur contre le recalcul signé (`comparer_zot.py` sans le passage à clé étrangère). Attendu : **8 cas, 0 écart**, 134 séries, 105 valeurs comparées. Mesure à relire après un nouveau passage du timer.

### Résultat de l'étape 5 et passage du timer, prédiction (2026-11-24T21:09:53Z)

[`e5-seuil.log`](e5-seuil.log) (21:09:33 UTC, dépôt `6ebc7eda`) : **8 cas, 0 écart**. 134 séries dans Prometheus, 105 valeurs comparées au recalcul signé, 41 signatures. **Seuil de docs/02 tenu à cet instant** (« 0 écart avec le recalcul »).

Passage du timer (`OnUnitActiveSec=15min`, premier passage à 21:07:38 UTC) : à partir de 21:24 UTC, `SUFFIXE=-2 seuil.sh` attendu **8 cas, 0 écart**, et âge du passage inférieur à 180 s, donc un passage de 21:22:38 à 21:23:38 environ (`AccuracySec` d'une minute par défaut).

### Correction du résultat de l'étape 5 (note de 2026-11-24T21:13:10Z, relecture du conseiller)

Des 105 valeurs comparées, **102 viennent des séries** ; 3 sont posées par `comparer_zot.py` (`violations_licences`, constante ; deux `kev_delais`, remplis quand aucune série de KEV n'existe). Elles sont égales par construction. À vérifier au passage du timer : à 21:09:33 l'âge de 113 s place un passage vers 21:07:40, la pose relevait 21:07:38 ; l'unité a peut-être tourné deux fois (timer activé juste après le premier passage).
