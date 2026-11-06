# Brique 08c : durcissement du cluster RKE2 et plan des secrets

Origine : exigence du propriétaire du 05/11/2026, « configurer kyverno, psa, pss, vérifier les roles, network policies (celle de cilium sont plus puissantes), activer l'audit, etc pour obtenir la meilleur sécurité possible au niveau du cluster kubernetes », et « on met les secrets dans openbao ? ». Intégration des idées de son dépôt [`gigi206/k8s`](https://github.com/gigi206/k8s) décidée le même jour (« Oui, intègre »).

Seuil : **les 8 tests négatifs, la porte et les contrôles 6 et 7 repassent, cluster durci ; tous les ports d'hôte non listés sont refusés ; aucune règle Kyverno n'est en Audit à la fin.**

Rien n'est appliqué tant que la brique 08b n'a pas passé son seuil. Une étape à la fois, pour qu'un échec soit attribuable.

## État

**Préparation à sec du 05/11/2026, 20:39 UTC : rien appliqué.** `durcissement.sh verifier` est conforme ([journal](resultats/durcissement-verifier.log)) :
- politique d'audit : 18 cas simulés conformes, aucun corps de requête pour les Secrets, les ConfigMaps et les jetons ;
- règles Kyverno : 9 pods d'essai jugés comme prévu par le CLI 1.19.2 ;
- 4 politiques Cilium et 4 règles Kyverno acceptées par l'API en dry-run, sur le cluster k3s ;
- valeurs de Cilium rendues sans cluster.

**Non vérifié** : aucune de ces règles n'a tourné. Le dry-run valide le schéma, pas l'effet. Les ports viennent d'un relevé `ss` sous k3s, pas sous RKE2. `kube-apiserver` n'a pas lu la politique d'audit, et la clé `kubelet-arg+` n'a pas été essayée sous RKE2.

**Additif du 06/11/2026, 16:33 UTC, préparation de H1 sous RKE2, rien appliqué.** `durcissement.sh verifier` repasse, conforme, sur le cluster RKE2 ([journal](resultats/durcissement-verifier.log), version k3s du 05/11 dans [`durcissement-verifier-k3s.log`](resultats/durcissement-verifier-k3s.log)). Les ports restent ceux du relevé k3s : à relever avant H3.

**H1, tel qu'écrit le 05/11, aurait arrêté l'API. Lu dans les sources, pas exécuté** :
- `config.yaml.d/pod-security.yaml`, posé par `kata.sh exemption`, et `durcissement.yaml` réglaient tous deux `pod-security-admission-config-file`. `readConfigFile` (k3s `58877f27435f`) lit les appoints par nom et la dernière valeur gagne : `admission.yaml` n'aurait jamais été lu ;
- `EventRateLimit` activé sans configuration reçoit une liste `limits` vide, que `ValidateConfiguration` (Kubernetes `v1.35.9`) refuse : `kube-apiserver` ne démarre pas ;
- `verifier` disait conforme sans voir cette fusion. Il la contrôle désormais, avec [un témoin](resultats/verif-appoints.log) qui retrouve la clé en double sur l'ancienne version.

**Correctif, à valider avec H1** : `h1_api` pose `config/admission.yaml` sur `/etc/rancher/rke2/pod-security.yaml`, le fichier déjà lu, et `durcissement.yaml` ne règle plus la clé. L'argument ne change pas : `kata.sh essais`, `kata.sh temoin` et `redemarrer.sh` voient toujours l'exemption, sans modification de `kata.sh`.

**`h1_api` corrigé** : le CronJob `rattrapage` est suspendu pendant les redémarrages ; `systemctl restart --no-block`, car l'unité est en `Type=notify` sans délai (`TimeoutStartUSec=infinity`, lu sur le nœud) et une API tombée bloquerait la commande ; un `startedAt` différent est exigé, comme `/readyz`, sinon arrêt sans toucher aux agents ; arguments et `configz` des kubelets en `attendu` ; témoins Kyverno, OpenBao et TSA avant et après ; `kata.sh temoin` à la fin.

**Prédictions de H1 ajoutées, 06/11/2026, 16:33 UTC, avant toute application** :

| # | Prédiction | Confiance |
|---|---|---|
| H1a | `kube-apiserver` relancé en moins de 300 s, arguments attendus lus dans le manifeste | Haute |
| H1b | `configz` rend `[4096,true,5]` sur les trois nœuds, aujourd'hui `[-1,false,50]` : la clé `kubelet-arg+` a été lue dans le code, jamais essayée | Moyenne |
| H1c | Au moins un 429 sur une rafale de 200 Events réels, de 16 clients : limites chargées. Dépend du débit de `kubectl` sur l'hôte : sans refus, le résultat est indéterminé, et non une preuve d'absence | Moyenne |
| H1d | OpenBao descellé, Kyverno et TSA répondent, comme à `kata.sh exemption` | Haute |
| H1e | Pod Kata lancé après H1 : `seccomp-default` sans effet dans l'invité (`disable_guest_seccomp`, mesuré en J7) | Moyenne |

**Additif du 06/11/2026, 16:45 UTC, H1 appliqué sur accord du propriétaire (« Oui, lance H1 »).** Lancé à 16:40:46 UTC, API prête 22 s après le redémarrage, trois nœuds `Ready`, CronJob `rattrapage` rétabli. Le [premier passage](resultats/durcissement-h1_api-premier-passage.log) finit en KO, sur **deux attendus faux** et non sur le cluster ; les contrôles repassent sans redémarrage, conformes ([journal](resultats/durcissement-h1_controle.log)) :
- `--enable-admission-plugins` figure deux fois dans le manifeste, la valeur du profil cis puis la nôtre. Le journal de `kube-apiserver` charge `NodeRestriction` et `EventRateLimit`, et un Service à `externalIPs` est refusé à sec. Le commentaire de `durcissement.yaml`, « ne garde que la dernière valeur », n'est ni confirmé ni infirmé par cette mesure ;
- `seccompDefault` reste `false` dans `configz`, car `--seccomp-default` est un drapeau de `KubeletFlags`, combiné à la configuration seulement au lancement (`server.go:1312`, Kubernetes `v1.35.9`). L'effet est mesuré : un pod runc de `sc-build` sans profil déclaré a `Seccomp: 2`, le témoin `Unconfined` a `Seccomp: 0`.

| Prédiction | Résultat |
|---|---|
| H1, 05/11 : arguments lus, trois nœuds `Ready` | **Tenue.** `pod-max-pids` et `seccomp-default` n'ont gêné aucun témoin, mais **aucune construction n'a tourné** : le point à mesurer reste ouvert |
| H1a : relance en moins de 300 s | **Tenue**, 22 s |
| H1b : `configz` à `[4096,true,5]` | **Non tenue sur la forme** : `[4096,false,5]`. `pod-max-pids`, `event-qps` et le drapeau sont appliqués sur les trois nœuds, l'effet de seccomp mesuré sur `sc-build` seulement |
| H1c : au moins un 429 | **Tenue**, 126 puis 125 refus sur 200 |
| H1d : OpenBao, Kyverno, TSA | **Tenue**, avant et après |
| H1e : pod Kata sans effet de `seccomp-default` dans l'invité | **Tenue** : `Seccomp: 0`, noyau 6.18.56 |

**Non prouvé par H1** : construction, porte et 8 tests sous ces réglages ; contrôles qui lisent des événements ; conteneurs inchangés sur `sc-confiance`, non comparés ; plafond d'audit. `h1_controle` crée deux pods dans `kube-system` et une rafale d'Events, retirés ensuite : 0 restant vérifié.

**Additif du 06/11/2026, 16:54 UTC, H2 appliqué sur accord du propriétaire (« Oui, lance H2 »).** Les 4 règles sont en Audit depuis 16:49:02 UTC ([application](resultats/durcissement-h2_kyverno.log), [relevé](resultats/durcissement-h2_releve.log)). Elles n'ont pas de balayage de fond : les pods en service sont joués par le CLI, les pods nouveaux lus dans les rapports.

| Règle | Pods en service (61, dont 5 hors du champ de deux règles) | Depuis H2, rapports de Kyverno |
|---|---|---|
| `limites-obligatoires` | **52 échecs**, 4 réussis ; le décompte direct donne aussi 52 | 12 échecs |
| `images-zot-par-digest` | 56 réussis, 0 échec | 12 réussis |
| `jeton-compte-default` | 61 réussis, 0 échec | 12 réussis |
| `espace-default-interdit` | Aucun pod dans `default` | Aucun résultat : **jamais exercée sur le cluster**, seulement par le CLI |

**Prédiction de H2** : **tenue sur « rien de refusé »** : 6 Jobs créés depuis H2, 6 réussis, 0 `FailedCreate`. **Tenue pour `limites-obligatoires`, non tenue pour `images-zot-par-digest`**, qui ne relève aucun écart, sens favorable.

**Écarts de `limites-obligatoires`, par espace** : `builds` 26, `porte` 8, `horodatage` 6, `tekton-pipelines` 5, `declencheurs` 4, et un chacun pour `openbao`, `tekton-chains`, `tsa`. Le nombre varie avec les pods terminés encore présents : 58 quatre minutes plus tôt. Rien n'est corrigé : ces limites sont à décider et à mesurer avant H5, en particulier pour la construction, qui n'a pas tourné sous ces règles.

**Effet relevé** : 32 événements `PolicyViolation` en 4 minutes 20 sur les seuls CronJobs, soit environ 7 par minute, tant que l'écart reste ouvert.

**Additif du 06/11/2026, 16:56 UTC, préparation de H3 sous RKE2, rien appliqué.** Relevé `ss` refait sur les trois nœuds, politiques relues.

- **Ports** : tous les ports ouverts vers l'extérieur sous RKE2 sont ceux du relevé k3s. Sous RKE2, 6443 et 6444 n'écoutent qu'en local sur les agents (`rke2`), 2382 aussi sur `sc-confiance`. `routing-mode=native` : pas de VXLAN à ouvrir.
- **Mode audit global** : `policy-audit-mode` est une option de l'agent, « non-drop ». Pendant H3, **aucune politique réseau du cluster ne refuse plus rien**, `construction-sans-sortie` comprise. Aucun build ne doit tourner entre H3 et H4 ; `preuves.sh test6`, en H4, doit prouver leur retour.
- **DHCP** : les nœuds gardent leur adresse par un bail d'une heure de `192.168.161.1`, T1 à 27 min, avec un socket UDP 68. `hote-commun` ne l'ouvre pas : en H4, le renouvellement serait refusé. D'où une fenêtre d'audit de 40 min (`h3_releve`), et l'ouverture à ajouter avant H4 si le verdict le confirme.
- **`sc-replay`** tourne (`virsh list`), mais sans trafic elle ne produit aucun verdict : une lecture de Zot depuis cette VM est à faire pendant la fenêtre, pour connaître son adresse source.

**Prédictions de H3 ajoutées, 06/11/2026, 16:56 UTC, avant toute application** :

| # | Prédiction | Confiance |
|---|---|---|
| H3a | `cilium.sh appliquer`, jamais lancé sous RKE2, passe : 3 agents prêts, aucun nœud perdu, SSH joignable | Moyenne |
| H3b | Verdict d'audit UDP 68 depuis `192.168.161.1` sur chaque nœud, dans les 40 min | Moyenne : dépend du format du relevé et du moment du renouvellement |
| H3c | Verdicts d'audit ICMP entre nœuds, pour `cilium-health` : la politique n'ouvre que 4240 | Moyenne |
| H3d | Aucun verdict d'audit sur 9345 ni 2379 hors des nœuds, puisque rien ne les sollicite au repos : le refus se prouve en H4, pas ici | Haute |
| H3e | Le format du relevé `verdicts` lit bien les lignes réelles : il n'a été essayé sur aucune sortie de `cilium-dbg monitor` | Moyenne |

**Additif du 06/11/2026, 17:46 UTC, H3 appliqué sur accord du propriétaire (« Oui »).** `cilium.sh appliquer` a tourné pour la première fois sous RKE2 : 3 agents recréés en 11 s, 4 politiques actives, SSH joignable sur les trois nœuds ([application](resultats/durcissement-h3_audit.log)). Audit de 40 minutes au repos, de 17:04:09 à 17:44:09 UTC, sur 78 502 verdicts ([relevé](resultats/durcissement-h3_releve.log), [détail](resultats/durcissement-h3_resume.log)).

**Seul flux qui aurait été refusé** : 124 requêtes ICMP entre les nœuds, sondes de `cilium-health`. Le filtre du relevé ne lisait pas les lignes sans port, d'où un journal de `h3_releve` sans détail : `verdicts` est corrigé, `h3_resume` relit les mêmes données brutes.

| Prédiction | Résultat |
|---|---|
| H3, 05/11 : aucun blocage | **Tenue** |
| H3, 05/11 : verdicts sur `sc-replay` | **Non tenue** : la VM n'a aucune route vers ce réseau. Échec de connexion mesuré à 17:05 UTC, conforme à l'isolement voulu par la brique 10 |
| H3a : `cilium.sh appliquer` passe | **Tenue** |
| H3b : verdict UDP 68 | **Non tenue, sens favorable** : les trois baux ont été renouvelés dans la fenêtre (fichiers datés de 17:36 à 17:39 UTC, `valid_lft` à 3 120 s et plus), sans aucun verdict |
| H3c : verdicts ICMP | **Tenue**, 124 |
| H3d : rien sur 9345 ni 2379 hors des nœuds | **Tenue** |
| H3e : le relevé lit les lignes réelles | **En partie** : oui avec port, non sans port, corrigé |

**Limites de la fenêtre** : au repos, sans build. Le webhook, les relais d'Alloy et Grafana n'ont ouvert aucune connexion observée : leurs règles n'ont pas été exercées. L'absence de verdict DHCP vaut en audit, pas sous blocage.

**Corrigé avant H4, à valider avec H4** :
- `hote-commun` ouvre ICMP echo entre nœuds ;
- `hote-stockage` retire `192.168.162.0/24`, inutile ;
- `h4_bloque` réapplique les politiques, contrôle SSH, API, Zot et les témoins avant le test 6 ;
- `preuves.sh` : le test 6 exigeait que sa contre-épreuve joigne 9345 et 2379, ce que H4 doit fermer. `T6_FERMES` fixe cet attendu pour H4 seulement, sans changer le rejeu.

**Prédictions de H4 ajoutées, 06/11/2026, 17:46 UTC, avant toute application** :

| # | Prédiction | Confiance |
|---|---|---|
| H4a | SSH, API, Zot, témoins conformes après la fin de l'audit | Moyenne |
| H4b | Test 6 conforme : `construire-image` refusée partout, contre-épreuve refusée sur 9345 et 2379, Zot et Forgejo joints | Moyenne : `T6_FERMES` n'a jamais tourné |
| H4c | Baux DHCP renouvelés sous blocage : `valid_lft` remonte dans les 30 min suivantes | Moyenne |
| H4d | Journaux de `sc-build` toujours dans Loki, après 30 min de blocage | Haute |
| H4e | `cilium-health` sans nœud injoignable : la règle ICMP vise bien les sondes | Moyenne |

**Additif du 06/11/2026, 18:12 UTC, H4 appliqué sur accord du propriétaire (« Oui, lance H4 »).** Fin du mode audit à 17:48 UTC, le pare-feu d'hôte bloque ([journal](resultats/durcissement-h4_bloque.log), [relecture à 21 min](resultats/durcissement-h4-relecture.log)). Politiques réseau des pods de nouveau appliquées : `construire-image` y est refusée partout.

| Prédiction | Résultat |
|---|---|
| H4, 05/11 : SSH, API et Zot joignables ; 9345 et 2379 fermés aux tâches signées ; Zot et Forgejo protégés | **Tenue**. La contre-épreuve, une tâche signée sans la politique de sortie, n'atteint plus 9345 ni 2379 : la limite relevée au test 6 de la 08b est fermée |
| H4a : SSH, API, Zot, témoins | **Tenue**, Zot en HTTP 200 |
| H4b : test 6 conforme | **Tenue** : 7 destinations refusées à `construire-image`, usurpation refusée, image `3a7ca1b1` inchangée. `T6_FERMES` a fonctionné |
| H4c : baux renouvelés sous blocage | **Tenue** : fichiers de bail datés de 18:03 à 18:05 UTC, `valid_lft` à 3 260 s et plus |
| H4d : journaux de `sc-build` dans Loki | **Tenue** : 72 lignes de `sc-build` en 5 minutes, 4 396 de `sc-confiance`, 1 413 de `sc-stockage`, relues à 18:12 UTC. Le premier relevé groupait sur une étiquette absente, d'où le complément |
| H4e : `cilium-health` | **Tenue**, 3/3 et 1/1 partout. Le `0/1 (1 unknown)` lu sur `sc-confiance` à 17:48:23 était une sonde prise au redémarrage de l'agent |

**0 refus de politique** en 2 minutes sur les trois agents, au repos, à 18:09 UTC.

**Non prouvé** : une construction complète, le webhook par NodePort, la porte et les 8 tests sous pare-feu bloquant, un redémarrage des VM. Le filtre de la contre-épreuve retire les flux vers 9345 et 2379 sans vérifier leur motif de refus : la fermeture se lit à la connexion refusée. `espaces-sans-politique` reste un seul bloc, joignable de l'intérieur.

**Additif du 06/11/2026, 18:14 UTC, construction de contrôle sous H1 à H4, décidée par le propriétaire (« Oui, construction »), prédictions avant toute exécution.** Vraie livraison du webhook de Forgejo, chemin 1 de la bascule. `sample-app-<tête>` est purgé puis recréé : Zot garde les preuves, et 2 enveloppes s'ajoutent à l'image. Flux relevés en même temps, pour une future politique par espace.

| # | Prédiction | Confiance |
|---|---|---|
| C1 | Webhook à travers le pare-feu d'hôte : `HTTP 204`, PipelineRun créé par `el-forgejo`, réussi, 3 TaskRuns vérifiés | Moyenne : règle NodePort jamais exercée |
| C2 | Même image `3a7ca1b1`, pod `construire` sous Kata sur `sc-build`, spec identique à J7 | Haute |
| C3 | Durée proche de la référence, 55 s du dernier PipelineRun ; `pod-max-pids=4096` et `seccomp-default` ne gênent aucun pod | Moyenne |
| C4 | 2 enveloppes de plus, aucune anomalie exécutions/enveloppes, porte `true`, contrôle 9 `ok` | Moyenne |
| C5 | `PASSAGE=apres preuves.sh reelle` : `ec` admet, contrôle 9 `ok`, VSA encore retenue pour ce digest | Moyenne : nouvelle provenance, VSA plus ancienne |
| C6 | 0 refus du pare-feu d'hôte pendant la construction ; refus seulement si `construire-image` tente une sortie, ce qu'elle ne fait pas | Moyenne |

**Additif du 06/11/2026, 18:23 UTC, construction de contrôle : le webhook ne fonctionne plus depuis H4, la construction et la porte passent.** Webhook de 18:14:50 UTC ([journal de la construction](resultats/preuves-construction_durcie.log), [flux](resultats/durcissement-flux_resume.log), [porte](resultats/preuves-reelle.log)).

**Défaut de H4** : `espaces-sans-politique` isole `tekton-pipelines`, et `declencheurs` n'est pas dans sa liste. `el-forgejo` n'atteint plus `tekton-triggers-core-interceptors:8443` : 9 refus, `i/o timeout` dans son journal, aucun PipelineRun. Forgejo répond pourtant `HTTP 204`. L'audit de H3, au repos, sans webhook, ne pouvait pas le voir. Le CronJob `rattrapage`, repris à la fin du script, a créé le PipelineRun à 18:18:58 UTC : c'est lui qui a construit. L'attente de `ba_chemin` a échoué avant : l'étape `construction_durcie` finit en KO, et ses contrôles de fin n'ont pas tourné.

| Prédiction | Résultat |
|---|---|
| C1 : webhook à travers le pare-feu d'hôte | **Non tenue.** Forgejo et le NodePort passent, l'échec est après, entre l'EventListener et les intercepteurs |
| C2 : même image, Kata, spec identique | **En partie** : `3a7ca1b1`, `construire` sous Kata sur `sc-build`, 3 TaskRuns vérifiés et signés. Spec non comparée, par le chemin du rattrapage |
| C3 : durée, `pod-max-pids`, `seccomp-default` | **Tenue** : 58 s pour 55 s de référence, aucun pod gêné |
| C4 : 2 enveloppes, porte | **En partie** : 6 puis 8 enveloppes, porte `true`, contrôle 9 `ok`, 8/8 couvertes. Contrôle exécutions/enveloppes de fin non passé |
| C5 : `reelle`, VSA retenue | **Tenue** : `ec` admet, 1/1 VSA retenue |
| C6 : 0 refus du pare-feu d'hôte | **Tenue** : le seul refus du relevé vient d'une politique de pod |

**Correctif préparé, non appliqué** : `politiques/cilium/intercepteurs.yaml`, accepté à sec par l'API. Règle séparée, bornée à l'EventListener et au port 8443. Ajouter `declencheurs` à `espaces-sans-politique` lui aurait ouvert toute la plateforme.

**Reste faux tant qu'il n'est pas appliqué** : un commit n'est construit qu'au passage suivant du rattrapage. **Non rejoué sous H4** : les 8 tests négatifs, dont le test 5, sauf le test 6. Le relevé `flux` s'est arrêté sur un `grep` sans résultat : `flux_resume` relit les mêmes données brutes.

**Additif du 06/11/2026, 18:25 UTC, correctif du webhook, accord du propriétaire (« Oui, corrige »), prédictions avant application.** `preuves.sh test5` refuse de tourner après la bascule (garde `gabarit_essai`) : `construction_durcie` reprend ses refus principaux.

| # | Prédiction | Confiance |
|---|---|---|
| W1 | Webhook de Forgejo : PipelineRun créé par `el-forgejo`, réussi, spec identique à J7, image `3a7ca1b1` | Haute |
| W2 | 2 enveloppes de plus, 10 en tout, aucune anomalie exécutions/enveloppes, porte `true` | Moyenne |
| W3 | Livraison non signée refusée par l'intercepteur, rejeu de Forgejo refusé (`already exists`), aucun PipelineRun du commit non signé | Moyenne |
| W4 | 0 refus de politique pendant le passage | Moyenne |

**Additif du 06/11/2026, 18:31 UTC, webhook corrigé.** `intercepteurs-declencheurs` appliquée à 18:25 UTC, sans redémarrage ; `construction_durcie` et `reelle` conformes de 18:26 à 18:30 UTC ([construction](resultats/preuves-construction_durcie.log), [porte](resultats/preuves-reelle.log), [flux](resultats/durcissement-flux.log)).

| Prédiction | Résultat |
|---|---|
| W1 : webhook, spec, image | **Tenue** : créé par `el-forgejo`, une création dans l'audit, spec identique à J7, `3a7ca1b1`, 56 s |
| W2 : enveloppes, anomalies, porte | **Tenue** : 8 puis 10, aucune anomalie, porte `true`, contrôle 9 `ok`, 10/10 couvertes, VSA 1/1 |
| W3 : refus | **Tenue** : non signée refusée, rejeu `already exists`, aucun PipelineRun du commit non signé |
| W4 : 0 refus de politique | **Non tenue, sans effet** : 36 refus, tous en sortie vers `34.117.62.14:443`, depuis les deux pods de la porte, 18 chacun. Ils viennent de la politique `porte`, antérieure au durcissement ; aucun refus du pare-feu d'hôte. La porte conclut quand même `true`. Cette adresse est celle de `tuf-repo-cdn.sigstore.dev`, résolue à 18:31 UTC : un outil de la porte tente de joindre le TUF public de Sigstore et n'y parvient pas. Aucune sortie ; l'outil à l'origine n'est pas identifié |

**Non rejoué sous H1 à H4** : tests 1 à 4, 7 et 8 ; la signature fausse et le corps modifié du test 5, que `construction_durcie` ne reprend pas ; un redémarrage des VM. `h4_bloque` réapplique tout le répertoire de politiques, donc `intercepteurs-declencheurs` comprise.

## Repris de `gigi206/k8s` (non remesuré dans ce PoC)

| Idée | Où | Adaptation |
|---|---|---|
| Politique d'audit par niveaux | `config/audit-policy.yaml` de la 08b | Règles Tekton, Kyverno et Cilium ajoutées, jetons en Metadata |
| Journaux kubelet et containerd en fichiers | `config/alloy/journaux-rke2.alloy` de la 08b | Absents de la conversion, correctif ; aussi lus par `fuites.sh` |
| `NodeRestriction` à garder dans la liste, `EventRateLimit`, réglages du kubelet | `config/` | Repris, seuils à relever |
| Structure des `default-deny` | `politiques/cilium/` | Fortement resserrée, voir ci-dessous |
| WireGuard strict | `config/valeurs-cilium-wireguard.yaml` | Mesure seulement. Format du chart 1.20.4 différent |
| Automount et espace `default` | `politiques/kyverno/` | Validation, pas mutation |

**Deux différences voulues avec ce dépôt** :
- la politique d'hôte y accepte tout le trafic de `cluster`, donc les pods. Ici, 9345 n'accepte que les nœuds, et etcd n'est pas ouvert ;
- `endpointSelector: {}` serait dangereux ici : les autorisations s'additionnent, et rouvriraient la sortie de `construire-image`. La liste d'espaces est donc fermée.

## Étapes et prédictions

Écrites le 05/11/2026 à 20:39 UTC, avant toute application. Chaque étape demande un accord, et la suivante n'est lancée qu'après la précédente.

| # | Étape | Prédiction |
|---|---|---|
| H1 | `h1_api` : plugins d'admission, `EventRateLimit`, kubelet | Arguments lus dans le pod statique. Trois nœuds `Ready`. Si `pod-max-pids=4096` ou `seccomp-default` gêne, le premier symptôme sera dans les pods runc, pas dans la construction Kata |
| H2 | `h2_kyverno` : 4 règles en Audit | Rien de refusé. `limites-obligatoires` et `images-zot-par-digest` relèvent des écarts, liste relevée puis corrigée |
| H3 | `h3_audit` : pare-feu d'hôte en audit | Aucun blocage. Des verdicts `audit` pour des flux non prévus, au moins sur sc-replay, dont l'adresse source n'est pas connue. Le redémarrage d'un agent applique les politiques d'hôte : console `virsh` prête |
| H4 | `h4_bloque` : fin du mode audit, test 6 | SSH, API et Zot restent joignables. Une tâche signée autre que `construire-image` n'atteint plus 9345 ni 2379 : la limite relevée au test 6 est fermée. Zot et Forgejo sont protégés pour la première fois |
| H5 | Règles Kyverno en `Deny` | Après correction des écarts de H2, la porte et les tests repassent |
| H6 | WireGuard, mesure | L'image `3a7ca1b1` reste identique. Le MTU sous Kata est le risque principal. Sans décision préalable, retiré après la mesure |

## Rôles

À traiter en H5, sans nouveau composant : ramener ou justifier les cinq lecteurs de Secrets à l'échelle du cluster (ADR 0000, limites résiduelles), revoir le droit des comptes de RKE2 absents sous k3s, et mesurer qui peut créer un `HelmChart`, puisque le contrôleur Helm reste actif.

## Plan des secrets (décision S1 ouverte)

Relevé du cluster le 05/11/2026, 23 Secrets, valeurs non lues :

| Catégorie | Secrets | Sort proposé |
|---|---|---|
| Identifiants Zot et webhook | `zot-images`, `zot-fermetures`, `zot-chains`, `forgejo-webhook` | OpenBao |
| À relever | `signing-secrets` | Contenu à vérifier avant décision |
| Jetons de service | `prometheus-lecture-jeton`, `alloy-evenements-jeton` | Durée et usage à revoir |
| Certificats internes | Kyverno, Tekton, Hubble, Cilium | Restent, ou cert-manager |
| Amorçage | `openbao-tls` | Reste : OpenBao ne peut pas fournir son propre certificat au démarrage |

**S1, recommandé (a)** : lecture directe d'OpenBao par jeton court, comme pour l'horodatage et le scan. Le secret n'existe alors pas dans Kubernetes. External Secrets seulement si un outil exige un vrai Secret. **(b)** : External Secrets partout : plus simple, mais le secret reste dans etcd, et le fournisseur OpenBao est listé en alpha.

### Relevé pour S1 (05/11/2026, 21:39 UTC, lecture seule)

Demande du propriétaire : ne pas trancher S1, et confirmer à sec l'hypothèse « supprimer d'abord, injecter ensuite, copier en dernier recours ». Rien n'a été modifié. [`releve-secrets.sh`](releve-secrets.sh), journaux `resultats/releve-secrets-<étape>.log`. Ce relevé ne note aucune grille de l'ADR 0000.

| Secret | Consommateur et usage | Ce qu'il exige | Sort proposé |
|---|---|---|---|
| `zot-chains` | Contrôleur Chains, volume, fichier lu par `DOCKER_CONFIG` | Un fichier `config.json`, relu à chaque résolution. Pas de Secret : le trousseau Kubernetes ne lit que ce que le compte référence, et `build` ne référence rien ([journal](resultats/releve-secrets-chains.log)) | **Injecté** |
| `zot-images` | Tâche signée `publier-image`, compte `build`, volume, `oras --to-registry-config` | Un fichier `config.json` dans le pod. Aucun jeton n'y est permis pour aller le chercher ailleurs | **Copié**, sauf choix contraire |
| `zot-fermetures` | Tâche signée `publier-fermeture`, même compte, même usage | Idem | **Copié**, sauf choix contraire |
| `forgejo-webhook` | Intercepteur `core-interceptors`, via `secretRef` de l'EventListener | Un vrai Secret : `Secrets(triggerNS).Get` ([journal](resultats/releve-secrets-webhook.log)) | **Copié** |

**Aucun des quatre n'est utilisé en `imagePullSecrets`.** Les nœuds tirent de Zot en anonyme : `registries.yaml` ne porte que la CA, aucune ligne d'authentification dans containerd, lecture HTTP 200 depuis les trois nœuds ([journal](resultats/releve-secrets-noeuds.log)). BuildKit n'a pas d'identifiant : sortie `type=oci` dans le workspace, entrées locales, aucune sortie réseau ([journal](resultats/releve-secrets-buildkit.log)).

**« Supprimer » est bloqué pour l'instant**, malgré `bearer.oidc` présent dans Zot v2.1.22 ([journal](resultats/releve-secrets-zot.log)) :
- **Zone build** : `zone-build`, en `Deny`, refuse tout jeton de compte projeté dans `builds`. L'OIDC de Zot comme OpenBao en ont besoin. La NetworkPolicy d'OpenBao n'admet pas non plus `builds`. Cette règle bloque aussi l'injection pour `zot-images` et `zot-fermetures` ;
- **Émetteur** : Zot tourne sur l'hôte `sc-stockage`, où `kubernetes.default.svc.cluster.local` ne se résout pas. La découverte et le JWKS y répondent 401. Le code ne prévoit ni clé statique ni en-tête d'authentification vers l'émetteur ;
- **htpasswd** : la combinaison avec `bearer.oidc` n'est pas listée dans la documentation au tag. Dès que `realm` et `service` sont posés, Zot annonce un défi Bearer, et l'échange de jeton ne reconnaît que l'OIDC et les clés d'API. Lu, pas essayé. Il y a 9 comptes htpasswd ;
- **Chains** : il lui faudrait de toute façon un `config.json` réécrit à chaque jeton, le trousseau ne lisant pas un jeton projeté.

**Injection sans nouveau composant, prédiction** : le motif du job d'horodatage (conteneur d'initialisation, `auth/jwt`, `kv/`, volume vide, révocation du jeton) est déjà en service et mesuré. `tekton-chains` remplit ses conditions : jeton d'audience `openbao` projeté, espace admis par OpenBao. Il reste un rôle et une politique `kv` distincts de ceux de Transit. L'Agent Injector n'apporterait rien ici, et il n'a pas été audité au doc 04. Un OpenBao scellé bloquerait le redémarrage de Chains, qui ne peut de toute façon pas signer dans cet état.

**Mention « listé en alpha » : exacte.** La page publiée et sa source au tag v2.14.0 listent OpenBao en alpha, mainteneur @phil9909 ([journal](resultats/releve-secrets-stabilite.log)). Nuance : la page du fournisseur renvoie au fournisseur Vault, listé stable, et indique un essai avec External Secrets v0.16.1 et OpenBao v2.2.0, loin de v2.14.0 et v2.7.2. Le texte de S1 ci-dessus reste valable.

**Autres constats** :
- `signing-secrets` n'a aucune clé. Il reste monté par Chains ;
- `zot-build` n'existe plus. `tekton/builds.yaml` le cite encore, et `politique.sh chains` retire la référence. Deux pods terminés le gardent ;
- sur `sc-stockage`, `/etc/hosts` résout le nom de Zot en 127.0.1.1, où il n'écoute pas. Sans effet aujourd'hui : aucun pod de ce nœud ne tire de Zot. À revoir si cela change. Premier passage archivé ;
- `kv/` est actif dans OpenBao depuis J8 (`tsa.sh`).

### Décision S1 (05/11/2026, 21:56 UTC) : « Oui, valide S1 »

Le propriétaire valide les trois choix recommandés, après la question « n est ce trop compliqué sans ESO ? » :
1. `zone-build` reste telle quelle. `zot-images` et `zot-fermetures` restent des Secrets, copiés depuis OpenBao ;
2. `forgejo-webhook` : copie scriptée depuis OpenBao, sans External Secrets ;
3. OIDC de Zot : reporté.

`zot-chains` est injecté par le motif du job d'horodatage. Aucun nouveau composant, donc pas de passage au doc 04. External Secrets et l'Agent Injector restent non audités et non essayés. À rouvrir pour la plateforme finale si une rotation automatique est exigée, si le nombre de Secrets obligatoires augmente, ou avec plusieurs clusters.

**Jalon préparé à sec, rien appliqué.** [`secrets.sh`](secrets.sh) `verifier` est conforme, 20 contrôles ([journal](resultats/secrets-verifier.log)) : correctif de Chains joué en local, aller et retour, puis admis en dry-run serveur, comme un pod complet. Le chemin `kv/`, les témoins et le conteneur d'initialisation n'ont jamais tourné.

| Étape | Effet | Prédiction, écrite avant toute exécution |
|---|---|---|
| `s1_source` | 4 chemins `kv/`, politique et rôle `chains-zot` | Relecture identique aux sources, le webhook octet pour octet. Le jeton de la politique lit `kv/tekton-chains/zot`, et rien d'autre : ni `kv/horodatage/zot`, ni `kv/builds/`, ni `transit/`, ni écriture. Compte `horodatage` refusé à la connexion |
| `s1_chains` | Conteneur d'initialisation, volume en mémoire, Secret supprimé | Déploiement prêt en moins de 180 s, journal « jeton révoqué ». Seul `signing-secrets` reste monté comme Secret. Le prochain passage écrit `.sig` et `.att` avec `poc-build`, sans autre changement du contrôleur |
| `s1_copies` | 3 Secrets recréés depuis OpenBao | Contenu inchangé : publication et test 5 (HMAC) identiques |

**Place dans la brique** : après H4, avant H5, pour que le passage en `Deny` juge l'état final. Après H4, le chemin vers OpenBao reste celui de Transit : `tekton-chains` est dans la liste fermée, et la NetworkPolicy d'OpenBao l'admet.

**Ce que S1 n'apporte pas** :
- **OpenBao n'est pas l'origine des valeurs.** `stockage.sh` tourne avant OpenBao et bâtit le htpasswd de Zot depuis les mots de passe de l'hôte. `secrets.sh` les recopie, et ils restent sur l'hôte. Le gain des copies est une source unique pour les consommateurs, pas une rotation ;
- **Le rejeu recrée les Secrets.** `politique.sh chains`, `construction.sh`, `prefetch.sh` et `tekton.sh` ne sont pas modifiés. Il faut relancer `secrets.sh` après chaque rejeu, jusqu'à une intégration que je ne propose qu'une fois le jalon prouvé ;
- **`politique.sh chains` rejoué sur Chains injecté échoue** : volume à deux sources, refus de l'API mesuré en dry-run. `s1_retrait` est le chemin de retour ;
- **Redémarrage des VM** : OpenBao scellé, le conteneur d'initialisation échoue et kubelet espace ses relances, jusqu'à 5 min. [`redemarrer.sh`](../08-trust-plane/redemarrer.sh) recrée le pod TSA pour cette raison, pas celui de Chains. Avant tout redémarrage après `s1_chains`, il faudra y ajouter le même traitement. Je prédis un contrôle `prets tekton-chains` en échec ou retardé sans cela.

Estimation : 4 h. Une décision s'impose à partir de 8 h.

**Additif du 06/11/2026, 18:38 UTC, prédictions de S1 sous H1 à H4, avant exécution** (accord du propriétaire : « Lance S1 ») :

`secrets.sh verifier` rejoué sous H1 à H4 : conforme ([journal](resultats/secrets-verifier.log), celui du 05/11 gardé dans [`secrets-verifier-05-11.log`](resultats/secrets-verifier-05-11.log)). Contrôle ajouté, absent du 05/11 : les quatre Secrets en service sont identiques aux sources de l'hôte, comparés sans affichage. Sans lui, `copie` aurait comparé OpenBao à l'hôte, jamais au cluster.

- **S1a, `s1_source`** : quatre relectures identiques, 9 témoins sur 9 conformes, connexion refusée au compte `horodatage`. Le chemin `kv/` et les témoins n'ont jamais tourné : c'est le premier risque de ce jalon ;
- **S1b, `s1_chains`** : déploiement prêt en moins de 180 s, journal « jeton révoqué » dès le premier essai ou presque, `signing-secrets` seul monté comme Secret, `zot-chains` absent ;
- **S1c, `s1_copies`** : trois Secrets recréés, contenu vérifié, aucun conflit d'`apply --server-side` puisque les valeurs sont inchangées ;
- **S1d, juste après** : contrôleur `1/1`, 0 redémarrage, aucun refus de politique Cilium depuis `tekton-chains`, `limites-obligatoires` toujours à 1 échec dans cet espace (le conteneur d'initialisation a des limites).

**Hors de cet accord** : `.sig` et `.att` écrits avec `poc-build`, et le HMAC après la copie de `forgejo-webhook`, ne se prouvent que par une construction. Elle écrit dans Zot : elle attend son propre accord. Tant qu'elle n'a pas tourné, S1 n'est pas prouvé de bout en bout. `preuves.sh` (lignes 2512 et 2651) lit `zot-chains` par `--as` : le refus attendu doit rester un `Forbidden`, l'autorisation passant avant l'existence du Secret ; prédit, non mesuré.

**Additif du 06/11/2026, 18:40 UTC, S1 appliqué** (accord du propriétaire : « Lance S1 ») : les quatre prédictions sont tenues. [`s1_source`](resultats/secrets-s1_source.log), [`s1_chains`](resultats/secrets-s1_chains.log), [`s1_copies`](resultats/secrets-s1_copies.log), [relecture](resultats/secrets-s1-relecture.log).

- **S1a tenue** : quatre relectures identiques, 9 témoins sur 9. Le compte `horodatage` est refusé pour la bonne raison : `invalid subject (sub) claim`, relevé après coup, le premier passage n'affichant qu'un code de sortie ;
- **S1b tenue** : déploiement prêt en 4 s, « essai 1 ; jeton révoqué », `signing-secrets` seul monté comme Secret, `zot-chains` absent. **Premier passage en échec, par erreur de mon script** ([journal](resultats/secrets-s1_chains-premier-passage.log)) : `kubectl logs deploy/…` a choisi l'ancien pod en `Terminating`, sans ce conteneur. L'étape s'est arrêtée avant la suppression du Secret. Sélection du pod corrigée, étape rejouée ;
- **S1c tenue** : trois Secrets recréés, contenu vérifié, aucun conflit ;
- **S1d tenue** : contrôleur `1/1`, 0 redémarrage, conteneur d'initialisation `Completed` sans relance, 0 ligne d'erreur au journal. Hubble : 156 flux de `tekton-chains` en 5 min, 27 vers `openbao`, 0 refus, témoin relevé pour ne pas prendre une commande en échec pour un zéro. Kyverno : 1 échec sur le pod neuf, comme avant. La lecture de `zot-chains` au nom des résolveurs reste un `Forbidden` : `preuves.sh` lignes 2512 et 2651 ne changent pas de sens.

**Non prouvé** : `.sig` et `.att` écrits avec les identifiants injectés, et le HMAC après la copie : aucune construction n'a tourné depuis. Les valeurs étant identiques, je m'attends à une construction conforme ; ce n'est pas une mesure. Le redémarrage des VM reste à traiter : OpenBao scellé, le conteneur d'initialisation attend, et `redemarrer.sh` ne recrée pas ce pod. `politique.sh chains` ne doit plus être rejoué sans `s1_retrait`.

**Additif du 06/11/2026, 18:41 UTC, construction de preuve de S1, accord du propriétaire (« Oui, construction »), prédictions avant exécution.** `construction_durcie` par le webhook de Forgejo, `reelle` en lecture (`PASSAGE=apres`, aucune VSA poussée), `flux` pendant 7 min. Une seule construction : les 8 tests ne sont pas rejoués.

| # | Prédiction | Confiance |
|---|---|---|
| K1 | HMAC après la copie : webhook accepté, PipelineRun créé par `el-forgejo`, réussi en environ 1 min, spec identique à J7, image `3a7ca1b1` | Haute |
| K2 | Identifiants injectés : tous les TaskRun et le PipelineRun signés, 10 → 12 enveloppes, aucune anomalie. L'audit de Zot attribue à `poc-build` des écritures sur `builds/sample-app` depuis le départ | Haute |
| K3 | Livraison non signée refusée, rejeu refusé (`already exists`), aucun PipelineRun du commit non signé | Haute |
| K4 | Porte `true`, contrôle 9 à 12/12, VSA 1/1 | Haute |
| K5 | 0 refus de la politique pour `tekton-chains`, `el-forgejo`, `construire` et `publier`. La porte retentera `34.117.62.14:443` (W4 non résolu), sans effet sur le verdict | Moyenne |

Le contrôle du sujet `poc-build` est ajouté parce que K2 sans lui ne distingue pas un compte d'un autre : `ba_chemin` ne relève que `poc-images`.

## À auditer avant toute décision

Kubescape, NeuVector, Tetragon (brique 17), et l'essai du runtime en bloc de Kata, qui pourrait contourner le blocage virtio-fs. Aucun n'entre dans cette brique sans passage au doc 04.

## Effets à connaître

- **H1 et H3 redémarrent** RKE2 et les agents de Cilium.
- **H3 et H4 peuvent couper l'accès aux nœuds.** Secours : console `virsh`, suppression de la politique. Comme le cluster est reconstructible par `rejeu.sh`, le pire cas est un rejeu.
- **Audit** : plus de volume, lu sur `sc-confiance` puis envoyé à Loki. Mesuré au rejeu de la 08b, jamais prédit en chiffre.
- **Retrait** : supprimer les fichiers d'appoint et les politiques, puis relancer `cilium.sh appliquer`.

- **Additif du 06/11/2026, 16:33 UTC, H1** :
  - **Après H1, ne pas relancer `kata.sh exemption`** : il reposerait le fichier de la 08b, sans `EventRateLimit`, et `kube-apiserver` ne démarrerait plus. `rejeu.sh` n'est pas concerné : il part de zéro, et H1 n'en fait pas partie.
  - **Retrait de H1** : reposer `08b-rke2/config/pod-security.yaml`, retirer `durcissement.yaml` et `kubelet.yaml` de `config.yaml.d`, puis redémarrer le server et les agents. Le retrait de la ligne précédente ne suffit pas.
  - **Événements** : la limite `User` (10 par seconde, rafale 50) et `event-qps=5` peuvent perdre des événements. Contrôles qui les lisent : `cilium.sh:171` et `:173` (Pulling, avec un `attendu`), `preuves.sh:215` et `:253`, `politique.sh:451`, `stockage.sh:234`. Effet à relever au prochain passage complet : H1 ne rejoue pas ces contrôles.
  - **Zot** n'est pas redémarré par H1 : service systemd de `sc-stockage`, hors de `rke2-agent`. La tâche du 21/11 ne bouge pas.

Estimation : 10 h, hors plan des secrets. Une décision s'impose à partir de 20 h.
