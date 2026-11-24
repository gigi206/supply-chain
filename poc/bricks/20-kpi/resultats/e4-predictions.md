# Brique 20, étape 4 : préparation de la pose de l'exportateur, prédictions

## Versions sur sc-stockage, prédiction (2026-11-24T20:07:20Z)

Commitée avant le lancement. Accord du propriétaire du 24/11, verbatim « Oui, lecture seule (Recommandé) », à la question « Vérifier maintenant sur sc-stockage, en lecture seule par ssh et sans sudo, la présence et la version de /usr/bin/openssl et de python3 ? ». [`stockage-versions.sh`](../stockage-versions.sh) lance deux commandes de version, rien d'autre.

Attendu, **2 cas, 0 écart** : `OpenSSL 3.5.x` et `Python 3.13.5` (Debian 13 ; versions de trixie lues dans `03-deps-closure/resultats/banc-debian-simulation.log` et `sante-openssl.log`). Le moins sûr : la présence d'openssl.
