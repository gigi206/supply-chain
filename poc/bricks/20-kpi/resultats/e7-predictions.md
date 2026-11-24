# Brique 20, étape 7 : pose au rejeu, essai à sec, prédiction

Prédiction écrite le 2026-11-24T21:59:32Z (`date -u`), commitée avant le lancement. Décision : « Pose au rejeu, sans dates (Recommandé) ». Sans ssh, ni sudo, ni cluster : Zot en lecture anonyme, clones jetables.

Script [`essai-rejeu.sh`](../essai-rejeu.sh), journal `e7-essai-rejeu.log`. `kpi-pose.sh` gagne `pose_rejeu` (depuis `rejeu.sh` seulement) et `sec_rejeu` (les mêmes contrôles, exportateur lancé sur l'hôte, journal vide). Une « clé réécrite » est ici la vraie clé plus une ligne vide : même clé, autre empreinte. Cinq cas, dans un clone chacun :

1. **arbre propre**, `sec` : tenu, code 0 ;
2. **arbre propre**, `sec_rejeu` : tenu, code 0, 0 clé sans date, relevé inchangé (`git diff` vide) ;
3. **deux clés réécrites (Chains, VEX) et relevé périmé** (les 3 lignes `non-epingle` retirées, comme après un rejeu dont les pipelines sont neuves) : `sec` rend KO, code 1 (clés : 2 au lieu de 0 ; relevé périmé) ; puis `sec_rejeu` : tenu, code 0, `clés sans date : 2`, 0 pin sans date, relevé redevenu celui de HEAD ;
4. **clé de Chains étrangère** (témoin G6) : `sec_rejeu` rend KO, code 1 (signatures refusées) ;
5. **`pose_rejeu` sans `REJEU`** : code différent de 0, aucun ssh.

Témoin de la tolérance exacte : au cas 3, `sec_rejeu` refait avec `SANS_DATE` forcé à 1 par une copie modifiée du script doit rendre KO, code 1 (2 au lieu de 1). Bilan attendu : **11 contrôles, 0 écart**.

Non mesurable à sec : l'étape dans `rejeu.sh` (`bash -n` seulement), la pose sur une VM recréée, un Loki sans ligne de `entrees-scan`, la première création du compte dans un Grafana neuf.

## Résultat (note de 2026-11-24T22:01:36Z)

[Journal](e7-essai-rejeu.log), 21:59:41 UTC, dépôt `a1c4822c` : **11 cas, 0 écart**. Au cas 4, 28 signatures refusées et, en plus de ce qui était prédit, les séries de pins absentes (sans provenance vérifiée, `releve-dates.py` n'écrit aucun pin) : un second KO, attendu dans son principe mais pas écrit. Au cas 2, l'exportateur a tourné avec un relevé réécrit identique.

## Second passage (prédiction de 2026-11-24T22:05:39Z, après relecture du conseiller)

Défaut lu, non mesuré : `SANS_DATE` hérité de l'environnement sautait le contrôle des clés contre HEAD dans `pose`. `unset SANS_DATE` en tête du script ; un cas de plus (`sec` avec `SANS_DATE=2` et deux clés réécrites reste KO, code 1, 2 KO). `SUFFIXE=-2` : **12 cas, 0 écart**.

Résultat (note de 2026-11-24T22:06:48Z) : [journal](e7-essai-rejeu-2.log), **12 cas, 0 écart**. Conforme.
