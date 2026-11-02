# L5 (D18, battement de cœur), prédictions écrites avant toute exécution (2026-11-02T21:42:41Z)

Décision du propriétaire : « Oui, D18 ». Ordre proposé :
1. `JALON=l5 mise run journalisation -- battement` ;
2. au moins 12 min d'attente, puis `JALON=l5 mise run journalisation -- silences` ;
3. `JALON=l5 mise run journalisation -- muette` (nouvel essai, journal `l5-muette.log`).

1. **`battement`** : timer `active` sur les trois VM. Le service tourne sous un compte dynamique, sans réseau.
2. **`silences`** :
   - **plus long silence de 0 min** pour chaque nœud depuis l'installation (au moins une ligne par minute) ;
   - environ 10 battements par nœud sur les 10 dernières minutes (étiquette `unite="battement-19b.service"`) ;
   - minimum de l'expression de `SourceMuette` **strictement positif** pour `sc-build` et `sc-confiance` (au moins 5 lignes par fenêtre de 5 min) ;
   - `SourceMuette` `inactive`.
3. **`muette`** : Alloy de `sc-build` arrêté. Le relais ne reçoit plus rien, alors qu'un battement arrivait chaque minute.
   - **`firing` entre 6 et 8 min** : pendant les 5 premières minutes, la fenêtre contient encore des battements reçus, puis viennent les 2 min de `for` ;
   - les témoins écrits pendant l'arrêt arrivent après la reprise ;
   - résolution et notifications, comme en L4.
4. **Réserve de L4 levée** si 2 et 3 sont conformes.
