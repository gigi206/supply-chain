# Brique 20, étape 4 : préparation de la pose de l'exportateur, prédictions

## Versions sur sc-stockage, prédiction (2026-11-24T20:07:20Z)

Commitée avant le lancement. Accord du propriétaire du 24/11, verbatim « Oui, lecture seule (Recommandé) », à la question « Vérifier maintenant sur sc-stockage, en lecture seule par ssh et sans sudo, la présence et la version de /usr/bin/openssl et de python3 ? ». [`stockage-versions.sh`](../stockage-versions.sh) lance deux commandes de version, rien d'autre.

Attendu, **2 cas, 0 écart** : `OpenSSL 3.5.x` et `Python 3.13.5` (Debian 13 ; versions de trixie lues dans `03-deps-closure/resultats/banc-debian-simulation.log` et `sante-openssl.log`). Le moins sûr : la présence d'openssl.

### Résultat (note de 2026-11-24T20:07:37Z)

[Journal](e4-stockage-versions.log), 2026-11-24 à 20:07:20 UTC, dépôt `f0e1f122` : **2 cas, 0 écart**. `/usr/bin/openssl` est présent sur `sc-stockage` : **OpenSSL 3.5.9** (3.5.5 sur l'hôte où l'essai a tourné) ; `/usr/bin/python3` : **3.13.5** (3.14.4 sur l'hôte). Rien à installer.

La vérification elle-même n'a pas tourné sur `sc-stockage`, ni sous Python 3.13, ni sous une unité durcie. Les deux options d'openssl employées (`pkey -text`, `dgst -verify`) n'y ont pas été exécutées.

**Heures** : de 20:07:03 à 20:07:37 UTC, 0 min 34 s, attente du propriétaire non comptée. Total de la brique : 41 min 49 s.
