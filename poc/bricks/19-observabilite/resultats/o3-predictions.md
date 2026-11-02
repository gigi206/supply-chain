# O3, prédictions écrites avant toute exécution (2026-11-02T17:54:34Z)

Règles et tests écrits à sec : rien n'est exécuté sur `sc-stockage` ni déployé dans Prometheus avant l'accord du propriétaire.
Règles : [`config/regles/alertes.yml`](../config/regles/alertes.yml) ; tests : [`config/regles/alertes-tests.yml`](../config/regles/alertes-tests.yml).

1. **`promtool check rules`** (promtool 3.13.5 déjà installé sur `sc-stockage` en O2, lancé dans un répertoire temporaire) : `SUCCESS`, 7 règles (A1 à A6 et `CollecteEnPanne`).
2. **`promtool test rules`** : tous les cas réussissent au premier passage (cas positifs, négatifs et bornes de `for:` ; série de Chains créée à 1 ; proxy de l'API en panne sans A1 ; A4 sans série ; A6 juste au-dessus et au-dessous de 30 jours).
3. **Évaluation des expressions sur le Prometheus réel** (requêtes en lecture, sans déployer les règles) : aucun résultat pour les 7 expressions. A3 sans résultat (aucune série `replay_dernier_resultat`, pas d'`absent()` pour A3) ; A6 sans résultat (première échéance le 27/04/2027, 176 jours) ; A4 sans résultat (derniers runs de la 01 à moins de 2 h).
4. **Mesure de référence de A5** (Kyverno, refus d'admission, depuis le début des données de Prometheus vers 16:59 UTC) : aucun refus, maximum sur 5 minutes = 0 (aucun essai de la 08 ni du banc depuis l'installation).
5. **Référence de A2** (Chains) : aucune hausse des compteurs d'échec de signature depuis le début des données.
