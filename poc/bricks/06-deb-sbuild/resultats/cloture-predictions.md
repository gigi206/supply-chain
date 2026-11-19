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

## Note datée du 19/11/2026, écrite à 14:54:09 UTC : premier passage arrêté sur un défaut du script

- Passage de 14:53:45 UTC, gardé dans [`cloture-releve-1.log`](cloture-releve-1.log) : arrêt en A, au contrôle de `deb/declencheur.yaml`. Ce fichier est un gabarit à variables `@NOM@` ; yq refuse de le lire. Défaut du script, pas de la plateforme.
- Avant l'arrêt, A avait relevé les 11 usages de `$PRIVILEGIE`, tous sur une ligne qui nomme `kata`, et les gabarits de `s4a.sh`, `s4d.sh` et `s5.sh`. Ces lignes ne comptent pas comme mesure : seul le passage suivant compte.
- Correctif : les variables `@NOM@` sont remplacées par un littéral avant la lecture par yq. Le script passe à `49afd5020dccbf97…`. Les prédictions CL1 à CL6 ne changent pas.

## Résultat (note écrite le 19/11/2026 à 14:54:48 UTC)

Journal : [`cloture-releve.log`](cloture-releve.log), de 14:54:13 à 14:54:14 UTC, à HEAD `ac133de`, code 0, 0 KO.

**CL1 à CL5 tenues.**
- **CL1** : les 11 usages de `$PRIVILEGIE` sont sur une ligne qui nomme `kata`.
- **CL2** : le pod d'essai de `s4d.sh` (ligne 345) porte Kata dans le même objet ; celui de `s5.sh` n'est privilégié que sous Kata. Les quatre fichiers de tâches privilégiées ne posent pas de RuntimeClass ; les gabarits de `s4a.sh`, `s4d.sh`, `s5.sh` et `deb/declencheur.yaml` la posent pour `construire`.
- **CL3** : 31 en-têtes de pod relus, 17 sous Kata et 14 sans RuntimeClass (`diag-exec-kata` 11 fois, `s1-runc-restreint` une fois, `s3-sonde-runc` deux fois). Les 7 contextes privilégiés affichés sont tous sous Kata. Le seul pod sans Kata dont le contexte est affiché est restreint ; pour les autres, le contexte vient des scripts (CL1).
- **CL4** : `pods-isolation` en `["Deny"]`, 4 validations, règle « privilégié hors Kata » égale à `admission.yaml` ; espace `builds` en `restricted`.
- **CL5** : à 14:54:14 UTC, 3 pods privilégiés hors Kata, tous dans `kube-system`, et 0 ailleurs.

**Limite de CL3** : grep a traité `diag-exec-releve.log` comme un fichier binaire et n'en a pas rendu les en-têtes. Ce journal vient du même script de diagnostic, couvert par CL1 ; ses en-têtes ne sont pas comptés.

**CL6, heures de commit** (UTC, blocs séparés par plus de 45 min, borne basse) : 72 commits qui touchent la 06 depuis le 14/11 à 21:40:25Z, en 5 blocs, **6:34:16**.

| Bloc | Commits | Durée | Autres chemins touchés |
|---|---|---|---|
| 14/11, 21:40:34 à 23:15:33 | 24 | 1:34:59 | 07a, 13a, docs |
| 15/11, 20:40:06 à 20:45:28 | 3 | 0:05:22 | — |
| 16/11, 15:08:13 à 19:33:52 | 36 | 4:25:39 | 05, docs, tools |
| 16/11, 20:47:33 à 21:15:19 | 7 | 0:27:46 | docs |
| 19/11, 14:53:40 à 14:54:10 | 2 | 0:00:30 | — |

La part des autres briques dans ces blocs n'est pas séparée : le bloc du 16/11 après-midi contient du travail de la 05. Aucune conversion en pw n'est faite ici.
