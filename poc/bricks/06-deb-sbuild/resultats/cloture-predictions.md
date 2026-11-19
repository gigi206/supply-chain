# Brique 06 : relevé de clôture, prédictions (écrites le 19/11/2026 à 14:53:32 UTC, avant tout lancement)

Demande du propriétaire, le 19/11/2026 : « on peut commencer la clôture de la 06 ? ». Seuil de la brique (README racine) : **bit-identique ; 0 pod privilégié sur l'hôte**.

Script : [`cloture-releve.sh`](cloture-releve.sh) (sha256 `ab6876f0b379fa2c…`), en lecture seule. Journal à venir : `cloture-releve.log`.

## Ce que le relevé doit établir

La clause « 0 pod privilégié sur l'hôte » ne se prouve pas par un relevé des pods d'aujourd'hui : les pods de build de la 06 n'existent plus. Les preuves sont des mesures datées, déjà archivées : N7 (S5, rejoué le 16/11 sur 1.0.0-2, refus de Pod Security), U12 (règle Kata de la porte jugée sur la provenance réelle), A12 de S4a, et les contrôles `runtimeClassName` de S4d. Le relevé ajoute :
- un contrôle statique des scripts et des tâches de la 06, pods d'essai de S1 à S3 compris ;
- une relecture des en-têtes de pod des journaux archivés ;
- l'état de l'admission à l'heure du relevé (il ne dit rien du passé) ;
- les heures de commit de la 06 depuis la note du 14/11 (21:40:25Z), sans conversion en pw.

Portée de la lecture « privilégié dans Kata n'est pas privilégié sur l'hôte » : décision D1 (a) du 10/11/2026 (pod Kata privilégié, voie A). Les espaces `kube-system` et `kyverno` sont exclus de `pods-isolation` par la configuration de Kyverno (`08-trust-plane/politique/admission.yaml`, ligne 2) : ils sont hors de la clause.

## Prédictions

- **CL1** (haute) : les 11 usages de `$PRIVILEGIE` dans `s1.sh`, `s2.sh`, `s3.sh` et `diag-exec-kata.sh` (définitions exclues) sont tous sur une ligne qui nomme `kata`. Aucun KO en A.
- **CL2** (haute) : le pod d'essai privilégié de `s4d.sh` porte `runtimeClassName: "kata"` dans le même objet ; celui de `s5.sh` n'est privilégié que si `$k == "kata"`, et porte alors Kata. Les quatre fichiers de tâches privilégiées (`construire-builder`, `construire-deb`, formes non signée et signée) ne posent pas de `runtimeClassName` eux-mêmes ; les gabarits de `s4a.sh`, `s4d.sh`, `s5.sh` et `deb/declencheur.yaml` la posent pour la tâche `construire`.
- **CL3** (haute) : dans les en-têtes de pod des journaux de S1 à S3 et du diagnostic, chaque contexte privilégié affiché est sous `kata` ; les pods sans RuntimeClass sont `s1-runc-restreint`, `s3-sonde-runc` et `diag-exec-kata` (cas croisés), tous lancés avec le contexte `RESTREINT` d'après les scripts.
- **CL4** (haute) : `pods-isolation` est déployée avec les actions `["Deny"]`, et sa règle « privilégié hors Kata » est égale à celle d'`admission.yaml`. L'espace `builds` porte `pod-security enforce` « restricted ».
- **CL5** (moyenne) : à l'heure du relevé, 0 pod privilégié hors Kata en dehors de `kube-system` et `kyverno`. Moins sûre : d'autres composants de la plateforme (agents de journalisation, stockage) n'ont pas été relus pour ce point.
- **CL6** (pas de prédiction de valeur) : les heures de commit sont mesurées, pas prédites. Les commits partagés avec d'autres briques (13a, 08, 10, docs) seront nommés ; leur part n'est pas séparée.

## Ce que le relevé ne prouve pas

- Qu'aucun pod privilégié hors Kata n'a existé entre deux mesures : l'admission est la seule barrière, et l'état de C ne vaut qu'à l'heure du relevé.
- La clause « bit-identique », déjà mesurée : 1.0.0-2 (`f66bbeb2`, `60f25f5c`) en S3 deux fois, en S4d deux fois sous Kata, et reconstruit hors ligne dans `sc-replay` (M5 de la ligne 11). Le rejeu de zéro (S5b) porte sur 1.0.0-1 ; aucun rejeu de zéro n'a eu lieu depuis la cascade.
