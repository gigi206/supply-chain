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

**Additif du 06/11/2026, 18:48 UTC, construction de preuve de S1 : K1 à K5 tenues.** Webhook de 18:41:29 UTC ([construction](../08-trust-plane/resultats/preuves-construction_s1.log), [porte](../08-trust-plane/resultats/preuves-reelle-s1.log), [audit de Zot](resultats/secrets-s1-zot.log), [flux](resultats/durcissement-flux-s1.log)).

- **K1 tenue** : HMAC accepté après la copie, PipelineRun créé par `el-forgejo`, réussi en 54 s, spec identique à J7, image `3a7ca1b1` ;
- **K2 tenue** : 3 TaskRun et le PipelineRun signés, 10 → 12 enveloppes, aucune anomalie. L'audit de Zot attribue à `poc-build` 2 `.att` et leurs blobs, en HTTP 201. La forme est la même, ligne pour ligne, que celle de la construction d'avant S1 ;
- **K3 tenue** : livraison non signée refusée, rejeu `already exists`, aucun PipelineRun du commit non signé ;
- **K4 tenue** : porte `true`, contrôle 9 à 12/12 avec 43 bundles, VSA 1/1, aucune VSA poussée ;
- **K5 tenue** : 0 refus sur `sc-build` et `sc-stockage`. Sur `sc-confiance`, 36 refus vers `34.117.62.14:443`, tous des Jobs `porte-ba-webhook` et `porte-reelle-apres` (identités lues dans Cilium), même nombre et même forme que W4, verdict inchangé.

**Correction de ma prédiction du 05/11** (« écrit `.sig` et `.att` ») : seuls les `.att` sont écrits. L'audit ne montre qu'une écriture de `.sig` sur `builds/sample-app`, à 14:24:34 UTC. Ni la construction témoin de 18:26 ni celle-ci n'en écrivent : l'image garde le même digest. **L'écriture d'un `.sig` avec les identifiants injectés reste donc non prouvée**, elle demanderait une image de digest nouveau. Le compte et le chemin sont ceux des `.att`.

**S1 est prouvé pour une construction par le webhook.** Non prouvé : tests 1 à 4, 7 et 8 sous H1 à H4 et S1, signature fausse et corps modifié du test 5, redémarrage des VM. W4 reste ouvert : la porte tente le TUF public de Sigstore, et l'outil à l'origine n'est toujours pas identifié.

**Additif du 06/11/2026, 18:55 UTC, préparation de H5, rien appliqué.** Relevé en lecture seule : `essais-h5-releve.sh`, journal `resultats/durcissement-h5-releve.log`.

- **W4, outil identifié** : c'est `ec validate image`, conteneur `porte`. Dans les deux Jobs de la preuve, il dure 61 s, les quatre autres conteneurs 0 s. Le code de `ec` v0.10.42 (`internal/policy/policy.go`, `checkOpts`) appelle `cosign.TrustedRoot()` même avec une clé publique, sauf si une variable `SIGSTORE_*` est définie, et poursuit sans erreur si l'appel échoue. Refus : deux connexions par pod, 9 SYN chacune, soit les 36 relevés. Le lien entre les 61 s et ces refus vient du code et de cette isolation, pas d'une mesure : Hubble n'a plus ces flux en mémoire et le moniteur ne les horodate pas. À mesurer en retirant l'appel.
- **`limites-obligatoires`** : 16 échecs dans les rapports. La règle ne lit que `spec.containers`. Tâches Tekton : `preparer` et `publier` sans limite ; `step-construire` a 2 CPU et 6 Gi, qui ne changeraient pas. `config-defaults` a la clé `default-container-resource-requirements`, appliquée seulement aux conteneurs sans ressources, donc sans toucher aux bundles ; non essayée. Charges à régler : `el-forgejo`, `rattrapage`, `horodatage`, `tekton-chains`, les contrôleurs de `tekton-pipelines`, `timestamp-authority`, et le CPU seul pour `openbao` et la porte. Le pod `j5-temoin` est un reste de J5.
- **Consommation** : 15 à 88 Mi à l'instant du relevé, cluster au repos. Ce n'est pas un pic : aucune limite ne peut en être tirée.
- **Droits, `auth can-i` sur tous les comptes de service** : lisent les Secrets à l'échelle du cluster `cilium-operator`, `generic-garbage-collector`, `namespace-controller`, `resourcequota-controller` (`list` seul) et `tekton-triggers-core-interceptors`. Aucun compte de service ne peut créer de `HelmChart` ; utilisateurs et groupes non balayés par ce relevé. Reste à vérifier que ces cinq comptes sont bien ceux que l'ADR 0000 vise.

**Additif du 06/11/2026, 18:57 UTC, prédictions des deux mesures avant H5, sur accord du propriétaire, avant exécution.** Effet : `SIGSTORE_REKOR_PUBLIC_KEY` ajoutée au conteneur `porte` de `porte-job.yaml`, relue à chaque Job. Base : le champ 6 du verdict, durée de ce conteneur, vaut 30, 31, 60 ou 61 s sur les 132 verdicts des journaux, jamais moins.

| Prédiction | Attendu | Confiance |
|---|---|---|
| M1 | Conteneur `porte` à moins de 10 s sur l'image réelle (61 s avant) | Moyenne : l'attribution vient du code, pas d'une mesure |
| M2 | Verdict inchangé sur l'image réelle : `success` vrai, 0 violation, contrôle 9 à 12/12, VSA 1/1 | Élevée : sans TUF joignable, `TrustedMaterial` restait déjà vide |
| M3 | 0 SYN vers `34.117.62.14:443` sur toute la fenêtre, réelle et construction comprises | Moyenne |
| M4 | Construction par le webhook : spec identique à J7, image `3a7ca1b1`, enveloppes 12 → 14, porte `true`, contrôle 14/14, non signée et rejeu refusés, aucune VSA poussée | Élevée |
| M5 | 0 refus de politique sur `sc-build` et `sc-stockage` ; sur `sc-confiance`, aucun refus de pod | Moyenne : conclusion des 36 refus |
| M6 | Pics relevés pour `preparer`, `publier`, `horodatage`, la porte et les contrôleurs. `kubectl top` ne verra pas les conteneurs brefs, d'où `memory.peak` des cgroups, en lecture par SSH. Sous Kata, le cgroup du pod est celui de la VM : il ne dira rien de la tâche | Élevée |

Retour si M1 ou M2 échoue : retirer la variable de `porte-job.yaml`, aucun état du cluster à défaire. Ni `Deny`, ni limite, ni rôle changé par ces mesures.

**Additif du 06/11/2026, 19:07 UTC, résultats des deux mesures, fenêtre 18:57:57 à 19:05:58 UTC.** Journaux : `durcissement-flux-h5.log`, `durcissement-h5-pics.log`, `08-trust-plane/resultats/preuves-reelle-h5.log`, `preuves-construction_h5.log`.

| Prédiction | Résultat |
|---|---|
| M1 | **Tenue** : conteneur `porte` à 1 s sur l'image réelle et sur `porte-ba-webhook`, contre 61 s. L'attribution de W4 à l'appel de `ec` est mesurée |
| M2 | **Tenue** : ligne `VERDICT` de `reelle-apres` identique à celle de S1 sauf la durée, `true`, aucune violation, 12/12, 43 bundles, VSA 1/1 |
| M3 | **Tenue** : 0 ligne vers `34.117.62.14` sur les trois nœuds. Témoin : le relevé des refus a vu 959 autres rejets, de protocole, et 17 773 verdicts |
| M4 | **Tenue** : spec identique à J7, image `3a7ca1b1`, 53 s, 12 → 14 enveloppes, 45 bundles, porte `true`, contrôle 14/14, VSA 1/1, non signée et rejeu refusés, aucune anomalie. Aucune VSA poussée |
| M5 | **Tenue, au-delà de l'attendu** : 0 refus de politique sur les trois nœuds, `sc-confiance` compris. W4 est fermé pour ces deux Jobs |
| M6 | **Tenue** : pics relevés (cgroups, 2 s). `kubectl top` ne voit rien de la porte, 8 lignes sur la construction |

**Pics, une construction de `sample-app`, sans concurrence** : `preparer` 165 Mi et 292 m ; `publier` 88 Mi et 19 m ; `construire` 2 134 Mi et 2 282 m, cgroup de la VM ; porte 107 Mi et 485 m. Contrôleurs : Chains 43 Mi et 11 m, Pipelines 45 Mi et 51 m, Triggers 24 à 29 Mi, `el-forgejo` 19 Mi, TSA 35 Mi, OpenBao 115 Mi et 77 m. Jobs d'horodatage nommés : 22 Mi et 968 m au plus. Ce sont des pics de cette fenêtre, pas des maxima : le Job `horodatage-29899860`, qui a traité les deux enveloppes, était purgé avant la lecture des noms, et le contrôleur Pipelines n'a vu qu'une exécution. Rien n'est décidé sur les limites.

**Additif du 06/11/2026, 19:13 UTC, H5 préparée à sec, rien appliqué, prédictions avant exécution.** Table : `politiques/limites.tsv` ; défaut de Tekton : `politiques/tekton-defauts.yaml` ; étapes `h5_sec`, `h5_limites`, `h5_deny` de `durcissement.sh`. Journal à sec : `resultats/durcissement-h5_sec.log`, conforme.

Ce que la préparation a changé par rapport à la proposition :

- **Requêtes explicites** : sans elles, l'API les égale aux limites. La porte demanderait 3 CPU sur `sc-confiance`, qui en a 2 125 m de libres, et resterait `Pending`. La table ajoute 290 m, la porte 150 m.
- **`scan-sample-app`** : CronJob absent du relevé de 18:55, car aucun pod n'existe. Son conteneur `revocation` serait refusé sous `Deny`. Valeurs non mesurées : jamais exécuté sur ce cluster.
- **Témoins** : `sonde_kyverno`, `pod_outils` et `pod_essai` créent des pods sans limite, que les témoins de `h5_limites` et `h5_deny` utilisent. Limites ajoutées.
- **Essais d'admission** : les pods de `essais/` visent le CLI (compte `app` absent) et ne peuvent pas servir à l'admission. `h5_sec` part du pod réel de `rattrapage`, admis, puis applique une entorse par règle : sous les règles en service, toutes sont admises, donc chacune ne heurte que l'une des quatre règles.

| Prédiction | Attendu | Confiance |
|---|---|---|
| L1 | `h5_limites` : rollouts prêts, OpenBao scellé puis descellé, clé Transit identique, jeton TSA, Kyverno répond | Moyenne : premier redémarrage d'OpenBao sous RKE2 durci |
| L2 | Construction sous limites : spec identique à J7, image `3a7ca1b1`, 14 → 16 enveloppes, 53 s à 15 s près, porte `true`, contrôle 16/16, VSA 1/1, aucun `OOMKilled` ni redémarrage | Moyenne : pics pris sur une seule construction |
| L3 | Pods créés après `h5_limites` : 0 échec de `limites-obligatoires` ; `preparer` et `publier` portent le défaut de Tekton, `step-construire` garde 2 CPU et 6 Gi | Élevée pour les limites ; moyenne pour le défaut, jamais essayé |
| L4 | 0 refus de politique Cilium pendant la construction | Élevée |
| D1 | `h5_deny` : `temoin` admis, quatre entorses refusées par un message `durcissement :`. `espace-default-interdit` exercée à l'admission pour la première fois | Élevée |
| D2 | Construction sous `Deny` : mêmes attendus que L2, 16 → 18 enveloppes, contrôle 18/18, 0 `FailedCreate` sur les Jobs | Élevée si L2 tenue |

**Non couvert** : `scan-sample-app` tournera le 07/11 à 09:30 UTC sous les valeurs non mesurées. Tests 1 à 4, 7 et 8 non rejoués par ces étapes. Après `h5_deny`, ne passent plus sans limites : `essai-reseau-rattrapage`, les pods de `j2-essais`, ceux de `plateforme.sh` (07a) et les cas d'admission de `politique.sh`. Les témoins admis de `preuves.sh` (`hc-pod`, `ct-pod-essai`) restent à relire avant tout rejeu. Un `tekton.sh` ou `politique.sh` rejoué effacerait les correctifs : `h5_limites` se relance ensuite. Retour : `h2_kyverno` pour l'Audit, `kubectl rollout undo` pour les limites, OpenBao à desceller.

**Additif du 06/11/2026, 19:18 UTC, corrections de la préparation de H5 après relecture, rien appliqué.** Il complète l'additif précédent, dont les chiffres et l'ordre ci-dessous changent.

- **Ordre et CronJobs** : `horodatage` et `rattrapage` tournent chaque minute, et le premier lit OpenBao. `h5_limites` les suspend, redémarre et descelle OpenBao d'abord, puis Tekton, Chains, TSA et l'EventListener, qui démarrent face à un OpenBao sain, puis reprend les CronJobs. L1 inclut donc cette reprise. État d'avant sauvegardé dans `$T/h5-avant`, car `rollout undo` ne couvre ni les CronJobs, ni l'EventListener, ni `config-defaults` : le retour se fait depuis ces fichiers.
- **Autres règles** : `h5_sec` juge aussi 16 pods tirés des gabarits réels, `scan-sample-app` compris, avec les quatre règles en `Deny` par le CLI : 0 échec. Témoin du CLI : pod sans limite, `fail`. `espace-default-interdit` ne s'applique à aucun d'eux.
- **`horodater`** : limite portée à 2 CPU, marge d'environ 2 et non 3, le CPU du pod n'étant pas attribué entre ses conteneurs. `identifiants` et `connexion` ne sont pas plafonnés : la règle ne les lit pas. Table : 270 m ajoutés au lieu de 290.
- **`h5_deny`** : attend le webhook par une boucle, et vérifie le message exact de chaque entorse. `rattrapage` ne monte pas de jeton : le refus d'`espace-default` ne peut pas venir de `jeton-compte-default`.
- **Passages de `h5_sec`, journal écrasé à chaque passage** : le premier concluait « conforme » alors que les neuf pods de `essais/` étaient refusés pour un compte absent, le contrôle ne portant pas dessus ; le deuxième a échoué sur le script, `kubectl` lisant `/dev/null`. Le journal archivé est celui de la version finale.
- **Temps** : environ 10 h par les écarts entre commits depuis le 05/11, briques 08b et 08c confondues, sans chrono propre à la 08c. Borne de décision : 20 h.

**Additif du 06/11/2026, 19:25 UTC, `h5_limites` appliquée sur accord du propriétaire, 19:19:17 à 19:20:23 UTC, et construction de contrôle, règles en Audit.** Journaux : `durcissement-h5_limites.log`, `durcissement-flux-limites.log`, `durcissement-h5-pics-limites.log`, et dans `08-trust-plane/resultats/` : `preuves-construction_limites.log`, `openbao-controle-h5.log`, `openbao-deverrouiller-h5.log`, `tsa-temoin-h5.log`.

| Prédiction | Résultat |
|---|---|
| L1 | **Tenue** : OpenBao redémarré puis descellé en quelques secondes, premier redémarrage sous RKE2 durci. Clé Transit identique, signature témoin vérifiée, jeton TSA vérifié, Kyverno répond, Chains relit ses identifiants dans OpenBao. CronJobs repris, dernier passage à 19:20:00 UTC |
| L2 | **Tenue** : spec identique à J7, image `3a7ca1b1`, 14 → 16 enveloppes, 47 bundles, 61 s contre 53 s, dans la marge, porte `true`, contrôle 16/16, VSA 1/1, non signée et rejeu refusés, aucune anomalie, aucun `OOMKilled` ni redémarrage. Une seule mesure : les 8 s ne sont pas attribuées |
| L3 | **Tenue** : aucun pod créé depuis 19:20 UTC sans limite. `preparer` et `publier` portent le défaut de Tekton, `prepare` et `place-scripts` aussi, `step-construire` garde 2 CPU et 6 Gi. Spec inchangée : le défaut n'atteint pas les bundles |
| L4 | **Tenue** : 0 refus de politique sur les trois nœuds, 9 423 verdicts relevés |

**Pics sous limites** : `preparer` 162 Mi et 217 m, `publier` 86 Mi et 38 m, VM de `construire` 2 127 Mi et 2 226 m, porte 109 Mi et 200 m. Job `horodatage-29899883`, celui qui a traité les deux enveloppes : 21 Mi et 745 m. Passages sans enveloppe : jusqu'à 971 m. Cette fois, le pod nommé donne le pic du passage utile que la mesure de 19:07 n'avait pas. Le CPU reste non attribué entre ses conteneurs.

**Encore ouvert** : `scan-sample-app` non exécuté, passage prévu le 07/11 à 09:30 UTC. Les règles restent en Audit : `h5_deny` demande un accord séparé.

**Additif du 06/11/2026, 19:31 UTC, `h5_deny` appliquée sur accord du propriétaire, 19:26 UTC, et construction de contrôle.** Journaux : `durcissement-h5_deny.log`, `durcissement-h5_deny-premier-passage.log`, `durcissement-flux-deny.log`, et dans `08-trust-plane/resultats/` : `preuves-construction_deny.log`, `openbao-controle-deny.log`, `tsa-temoin-deny.log`.

| Prédiction | Résultat |
|---|---|
| D1 | **Tenue au second passage** : `temoin` admis, quatre entorses refusées avec leur message exact, Kyverno, OpenBao et TSA conformes. `espace-default-interdit` a refusé à l'admission pour la première fois. Premier passage à 19:26:05 en KO sur le script seul : `read` retirait l'espace final de la ligne `temoin`, comparée avec cet espace ; verdicts identiques, construction non lancée |
| D2 | **Tenue** : spec identique à J7, image `3a7ca1b1`, 55 s, 16 → 18 enveloppes, 49 bundles, porte `true`, contrôle 18/18, VSA 1/1, non signée et rejeu refusés, aucune anomalie, aucun `OOMKilled`. 0 `FailedCreate`, 0 refus de politique sur les trois nœuds, 9 493 verdicts relevés. `rattrapage` et `horodatage` réussissent sous `Deny` |

**Correction d'une erreur de cette préparation** : `scan-sample-app` n'a pas « jamais tourné sur ce cluster », comme l'écrivent l'additif de 19:13 UTC et l'additif des corrections. Seul son `lastScheduleTime` était vide : `lastSuccessfulTime` vaut 15:40:59 UTC ce jour, avant H1. Il reste vrai que ses valeurs ne sont pas mesurées et qu'il n'a pas tourné sous H1 à H5.

**H5 n'est pas close** : les quatre règles sont en `Deny` et la construction passe, mais la prédiction de l'étape comprend les tests, et les tests 1 à 4, 7 et 8 n'ont pas été rejoués sous H1 à H5. Les rôles (lecteurs de Secrets, droits des comptes de RKE2, `HelmChart` côté utilisateurs et groupes) restent à traiter. À relire : le passage de `scan-sample-app` du 07/11 à 09:30 UTC, premier sous `Deny`.

**Additif du 06/11/2026, 20:03 UTC, rejeu des tests sous H1 à H5, préparé à sec, rien exécuté, prédictions avant passage.** Demande : « Continue » après la clôture de `Deny`, pris pour la préparation seule. `h5_tests_sec` n'a rien créé (`durcissement-h5_tests_sec.log`, `preuves-h5-sec_h5.log`).

Sans retouche, ces tests n'auraient pas tourné :

| Test | Obstacle relevé | Retouche |
|---|---|---|
| 3 et 7 (D2) | `gabarit_essai` les refuse depuis la bascule ; le gabarit en service construit la vraie image | `PIPE_ESSAI` rend sur l'hôte le gabarit d'essai de `declencheurs.yaml` ; `pr_gabarit` réutilise `pipelinerun`. Gabarit en service inchangé. Le PipelineRun du test 3 est créé par l'administrateur, plus par une livraison : cela ne touche ni les droits sur les TaskRuns ni Chains, seuls jugés ici |
| 4 | Pods sans limites : les témoins seraient refusés, et `limites-obligatoires` se mêlerait aux refus mesurés | Limites sur les pods de `pod_builds` |
| 8 | Le script exigeait 2 enveloppes ; l'image réelle en a 18 | `n` relevé. `copie`, `melange`, `illisible` portent les `n` bundles réels. Les cas falsifiés gardent 2 bundles : un bundle accepté à tort ferait passer le décompte de `0/n` à `k/n`, donc la mesure discrimine encore |
| Journaux | `resultats/preuves-<test>.log` sont cités et seraient écrasés | `JOURNAL=preuves-h5` : `preuves-h5-<test>.log`, sans toucher aux anciens |

Relevé à sec : motifs exacts de `pods-isolation` et de Pod Security sur les pods du test 4, sans `limites-obligatoires` ; témoins Kata et runc admis ; PipelineRun d'essai admis en dry-run ; 18 enveloppes, 49 bundles du digest, 15 provenances de PipelineRun sur `builds/essai-webhook` ; 14 clés sur 14 de la ConfigMap `porte` identiques aux fichiers, `cm_porte` ne change donc rien.

Commande, ordre du rejeu, chaque KO arrêtant la suite : `DISTRO=rke2 mise exec -- poc/bricks/08c-durcissement/durcissement.sh h5_tests`.

| Prédiction | Attendu | Risque |
|---|---|---|
| T2 | Refus par le webhook de Tekton et `tekton-references`, refus RBAC pour le TaskRun d'`el-forgejo`, deux témoins admis | Faible, aucune de ces barrières n'a changé depuis le passage d'aujourd'hui sur RKE2 |
| T4 | Pod runc refusé par Pod Security, pods Kata refusés par `pods-isolation`, témoins admis | Faible, vu à sec ; les codes 403 et 400 de l'audit restent à mesurer |
| T3 | 8 écritures refusées par RBAC, écriture de l'administrateur acceptée, 3 signatures avant, aucune après, sujet d'origine conservé, exécution purgée | Moyenne : premier passage de `pipelinerun` hors de J6 |
| T1 | Ni jeton ni variable de secret, OpenBao injoignable par le service et par l'IP, SYN en `POLICY_DENIED` à l'entrée de sc-confiance, aucune ligne dans l'audit d'OpenBao ; Zot et Forgejo joints | Faible. La prédiction imprimée par le script date de J8 : la NetworkPolicy admet aussi `horodatage` et `scan` depuis, ce qui ne change rien pour `builds` |
| T7 | A, B, C et D1 identiques au passage d'aujourd'hui, durée de `ec` autour de 1 s au lieu de 61 ; D2 : `trusted_task.trusted` en violation sur la tâche hors liste, puis en succès | Moyenne pour D2 : `preuve-test7-en-service` n'est plus sur la pipeline en service, le script le dit dans son journal |
| T8 | `reel`, `copie`, `melange`, `illisible` à 18/18 ; `aucun`, falsifiés, `webhook-seul` et `autre-digest` à 0/18 ; `partiel` à 1/18 ; `poc-images` refusée ; v3 comme au premier passage | **Moyenne** : premier passage à 18 bundles par dépôt d'essai ; premier passage des témoins v3 avec `SIGSTORE_REKOR_PUBLIC_KEY`, dont l'effet sur le format bundle n'a pas été mesuré |

**Effets à connaître.** Écritures dans Zot : `tekton/tasks/preuve-test1`, `tekton/tasks/preuve-test7`, `tekton/pipelines/preuve-test7`, témoins de `essais-j8/test7` et `essais-j8/test8`, onze dépôts sous `horodatage/essais-test8`, six enveloppes de plus sur `builds/essai-webhook`. Rien n'y est supprimé. Dans le cluster : `preuve-test7-hors-liste`, `preuve-test7-en-service` et `preuve-test1` remplacés, Jobs de la porte, ConfigMap `porte-temoin` posée puis retirée. `builds/sample-app` ne doit pas bouger : `garder` le vérifie à chaque test. Le gabarit, les règles et les limites ne sont pas touchés. Durée estimée, non mesurée : environ 20 minutes.

**Hors de ce rejeu** : signature fausse et corps modifié du test 5, test 6 sous limites, rôles (lecteurs de Secrets, comptes de RKE2, `HelmChart` côté utilisateurs et groupes), passage de `scan-sample-app` du 07/11 à 09:30 UTC. H5 reste ouverte.

**Additif du 06/11/2026, 20:07 UTC, canaux de trace et pods réels, relevés après relecture, rien exécuté.** Le dry-run de `h5_tests_sec` ne disait rien des traces que T2 et T4 exigent, ni des pods créés par Tekton. Relevés en lecture seule ou en dry-run :

- **Événements** : `PolicyViolation` de `pods-isolation` présents à 20:02:38 et 20:03:04, malgré `EventRateLimit` de H1. Un dry-run en émet donc : `t0` des tests les ignore, mais deux dry-run proches ajoutent des lignes. L'événement de `tekton-references` n'est pas relevé sous H1, seul le même canal l'est.
- **Audit de l'API** : refus et emprunts d'identité lus sur les requêtes de 20:02:38 : pod runc 403, `restricted:latest` ; pods Kata 400, `exempt runtimeClass` ; témoins 201. Le risque laissé à T4 sur ces codes est levé, en dry-run.
- **Pods de Tekton** : pods réels `sample-app-e537a1db…-publier-pod` (`publier-essai`) et `preuve-test1-pod` représentés à l'API sous `Deny`, au nom du contrôleur, limites posées comme le fait `config-defaults`. Les deux sont admis, le pod de `publier-essai` servant aussi à `preuve-test7`, tâche au même gabarit. `j6-signee-pod`, d'une ancienne tâche, est refusé par Pod Security sur `prepare` et `place-scripts` : cause non recherchée, aucun test de ce rejeu ne s'en sert.

Trace : `durcissement-h5_tests_sec-relecture.log`.

**Additif du 06/11/2026, 20:21 UTC, rejeu des tests sous H1 à H5, accord du propriétaire (« Oui, lance les tests »).** `h5_tests`, 20:09:59 à 20:20:47 UTC, soit moins de 11 minutes pour environ 20 estimées. Code 0, un seul passage, gabarit en service inchangé.

| Prédiction | Résultat | Trace |
|---|---|---|
| T2 | **Tenue** : 11 OK, 0 KO ; refus de Tekton et de `tekton-references`, RBAC pour `el-forgejo`, témoins admis. L'événement de `tekton-references`, non relevé à sec, est bien émis | `preuves-h5-test2.log` |
| T4 | **Tenue** : 13 OK, 0 KO ; 403 et 400 mesurés sur des créations réelles, plus en dry-run | `preuves-h5-test4.log` |
| T3 | **Tenue** : 22 OK, 0 KO ; 8 écritures refusées et lues dans l'audit, 3 signatures avant, aucune après, 32 enveloppes avant et après, sujet d'origine, exécution purgée | `preuves-h5-test3.log` |
| T1 | **Tenue** : 13 OK, 0 KO ; OpenBao fermé en 5 s par le service et par l'IP, SYN jetés à sc-confiance, 0 flux refusé à sc-build, aucune requête du pod dans l'audit d'OpenBao, Zot et Forgejo joints | `preuves-h5-test1.log` |
| T7 | **Tenue** : 20 OK, 0 KO, 3 CONSTAT déjà connus ; `ec` en 0 à 2 s contre 61 ; D1 identique ; D2 tenue, sur la pipeline d'essai | `preuves-h5-test7.log` |
| T8 | **Tenue** : 24 OK, 0 KO, 2 CONSTAT déjà connus ; 18/18 pour `reel`, `copie`, `melange`, `illisible`, 0/18 pour les sept cas de refus dont `aucun`, 1/18 pour `partiel`. Les deux risques moyens ne se sont pas réalisés : les témoins v3 rendent le verdict du premier passage avec `SIGSTORE_REKOR_PUBLIC_KEY` | `preuves-h5-test8.log` |

`builds/sample-app` reste à 18 enveloppes, provenance `5a832738`, relevé par `garder` avant et après chaque test. Après coup, 20:21 UTC : trois nœuds `Ready`, neuf règles en `Deny`, gabarit `sample-app`, `porte-temoin` retirée, 0 `FailedCreate`, 0 `OOMKilled`, aucune exécution en cours, `horodatage` et `rattrapage` réussis. Les pods en `Error` de l'espace `porte` sont les refus attendus de la porte.

Le **plafond** de ce résultat : T1 et T4 restent des barrières vues depuis un pod d'essai ; un seul passage ; les refus de politique sur les trois nœuds n'ont pas été relevés dans cette fenêtre.

**Reste pour clore H5** : rôles (lecteurs de Secrets, comptes de RKE2, `HelmChart` côté utilisateurs et groupes), passage de `scan-sample-app` du 07/11 à 09:30 UTC. Toujours hors de ce rejeu : signature fausse et corps modifié du test 5, test 6 sous limites.

**Additif du 06/11/2026, 20:29 UTC, rôles de H5, préparés à sec sur demande du propriétaire (« Oui, prépare à sec »), rien appliqué, prédictions avant passage.** Relevé en lecture seule ([`essais-h5-droits.sh`](essais-h5-droits.sh), [journal](resultats/durcissement-h5-droits.log)), élargi aux utilisateurs et aux groupes, aux droits qui mènent aux Secrets sans les lire, et aux droits donnés par espace. Les cinq lecteurs à l'échelle du cluster sont recoupés par `auth can-i`, le reste vient du calcul sur les objets RBAC. [`h5_roles_sec`](resultats/durcissement-h5_roles_sec.log) : règles de `politiques/roles/` admises en dry-run serveur, chart de Cilium rendu sur l'hôte.

**Découverte : le compte de RKE2 peut demander le jeton de n'importe quel compte de service.** `system:rke2-controller` a `create` sur `serviceaccounts/token` sans borne, `can-i` à `yes` dans cinq espaces essayés, dont `tekton-chains` et `openbao`. Son certificat est sur les trois nœuds, `sc-build` compris, en root seul. Root sur `sc-build`, après une sortie de Kata, permettrait donc d'obtenir par exemple le jeton de `generic-garbage-collector`, lecteur de tous les Secrets, sans passer par `NodeRestriction`. Chaîne lue dans les droits, pas exercée. Une demande pour `builds/build`, au nom de ce compte et en `dryRun=All`, a rendu un jeton de 870 caractères : **le dry-run en émet un vrai**. Il valait 10 minutes pour l'audience `essai`, n'a été ni affiché ni gardé, et `jeton_essai` ne le lit jamais. Le chemin vers OpenBao resterait fermé par sa NetworkPolicy, non essayé depuis un hôte. Usage réel : 82 requêtes de ce compte dans l'audit conservé depuis 13:29:16 UTC, redémarrages de H1 compris, **0 sur les comptes de service**. Cause de ce droit dans RKE2 non trouvée : la règle est dans `clusterrole_bootstrap.go`, son appelant reste à chercher.

| Sujet | Droit relevé | Proposition | Raison |
|---|---|---|---|
| `cilium-operator` | Lit tous les Secrets | **Retirer** : `tls.secretSync.enabled: false` | Le chart ne donne ce droit que pour la synchronisation TLS, et `ingressController`, `gatewayAPI`, `bgpControlPlane` n'en ont pas besoin ici. `l7Proxy=false`, `cilium-secrets` vide. Rendu : le droit de l'opérateur et son rôle disparaissent, il reste le Role de l'agent, borné à `cilium-secrets` |
| `system:rke2-controller` | Jeton de tout compte, sur chaque nœud | **Borner** : règle `jetons-rke2-controller` | RKE2 recrée son ClusterRole au démarrage, une règle d'admission dure, et 0 usage relevé |
| `tekton-triggers-controller`, `-webhook` | Écrivent toutes les configurations de webhooks, Kyverno compris | **Borner** : règle `webhooks-triggers` | Nouveau au relevé. Pipelines est déjà borné par `resourceNames` |
| `tekton-triggers-core-interceptors` | Lit tous les Secrets | **Garder, justifié** | Mesuré le 02/11 : sans ce droit le pod n'est jamais prêt, l'informer n'a pas de portée. Sortie seulement en modifiant Triggers |
| `generic-garbage-collector`, `namespace-controller`, `resourcequota-controller` | Lisent tous les Secrets, `list` et `watch` seuls pour le dernier | **Garder, justifié** | Contrôleurs de `kube-controller-manager`, identifiants sur `sc-confiance` seul. Leur rôle l'exige. La découverte ci-dessus est ce qui les rend atteignables depuis `sc-build` |
| `rke2-cloud-controller-manager` | `nodes` et `daemonsets` en `*` | **Garder, justifié** | `cloud-controller.kubeconfig` absent de `sc-build`, relevé ; `sc-stockage` non relevé |
| `HelmChart` | `create` : `system:masters` seul. `patch` et `update` : aussi `generic-garbage-collector`. Lecture : `system:rke2-controller` | **Clos** | 0 `HelmChart` dans le cluster, aucun autre compte, utilisateur ou groupe. `operateurs` refusé. Le contrôleur reste actif : RKE2 ne permet pas de le couper (08b) |
| `kyverno-background-controller` | `roles` et `rolebindings` dans tous les espaces | **Garder, à revoir** | Limité par la prévention d'escalade, 0 règle de génération en service. Le retirer toucherait au chart de Kyverno, sans gain mesuré |

`system:masters` reste le seul à détenir `impersonate`, `bind` et la liaison de cluster-admin. Lecture résiduelle, 26 Secrets, valeurs non lues. Les droits par espace ne révèlent aucun lecteur hors de ses propres espaces, à part les contrôleurs de Tekton dans `builds`, déjà bornés. Le résultat serait de **quatre lecteurs à l'échelle du cluster au lieu de cinq**, tous justifiés.

| Prédiction | Attendu | Risque |
|---|---|---|
| R1, `h5_roles` | Jeton refusé à `system:rke2-controller` avec le message exact, témoin `system:kube-controller-manager` admis ; webhook de Kyverno refusé à Triggers, le sien admis | Moyenne : première règle sur `serviceaccounts/token` |
| R2, redémarrages | Contrôleurs de Triggers et agent de `sc-build` repartent, `sc-build` `Ready`, 0 requête refusée de `system:rke2-controller`, 0 refus de webhook | **Moyenne** : usage du droit inconnu, 0 usage observé n'est pas une preuve. Un redémarrage complet des VM n'est pas couvert |
| R3, Cilium | Après `helm upgrade` et redémarrage : `can-i` à `no` pour l'opérateur, 0 erreur de Secrets à son journal, politiques de H4 intactes, test 6 conforme | **Moyenne à haute** : `cilium.sh appliquer` jamais rejoué sous H4, et il redémarre les agents. Étape non écrite, valeurs non modifiées : à préparer après accord |
| R4, construction | Après R1 à R3 : chaîne complète, image `3a7ca1b1`, 18 → 20 enveloppes, porte `true`, 0 refus | Moyenne |

**Effets à connaître** : `h5_roles` pose deux règles natives, redémarre deux Deployments de Triggers et l'agent RKE2 de `sc-build`, sans construction en cours ; `h5_roles` rend aussi un jeton en dry-run pour `builds/build` avant la règle, et un pour le témoin après. Retour : `kubectl delete -f politiques/roles/roles.yaml`. Limite d'une règle : elle ne protège pas de root sur `sc-confiance`, où sont les identifiants d'administration, ni des certificats de `kubelet`, bornés par `NodeRestriction`.

Après décision : additif à l'ADR 0000, qui compte encore cinq lecteurs à ce jour.

**Additif du 06/11/2026, 20:34 UTC, rôles de H5, relecture avant accord, rien appliqué.** Trois points de l'additif de 20:29 sont précisés.

- **Cause du droit sur les jetons, trouvée.** Ajouté par le commit `562228ec09` de RKE2, « change windows calico setup to generate a sa token » (#2940). Les deux appelants de `pkg/windows`, `calico.go` et `flannel.go`, sont réservés à Windows (`//go:build windows`) ; aucun appel dans les six fichiers lus de `pkg/rke2` à v1.35.9+rke2r1. Ils ne tournent donc pas sur nos nœuds Linux. La règle est absente de `manifests/rolebindings.yaml` de k3s, branche par défaut. Non balayé : le code de k3s embarqué, recherche GitHub sans résultat, donc sans valeur.
- **Usage réel, chiffre corrigé.** Les 82 requêtes de l'additif de 20:29 comptaient mes propres essais par emprunt d'identité. Requêtes réelles du compte, depuis 13:29:16 UTC, à la création du cluster : **54 `get nodes`, 14 `selfsubjectaccessreviews`, rien d'autre.** Cela couvre les jonctions des agents et les redémarrages de H1 sur les trois nœuds. Le risque de R2 tombe à **faible à moyen**.
- **`rke2-cloud-controller-manager`** : `cloud-controller.kubeconfig` absent de `sc-stockage` aussi, relevé. Il n'est que sur `sc-confiance`.

`h5_roles` est renforcée avant tout accord : plus de jeton émis avant la règle, `auth can-i` suffit, le témoin d'après en émet seul un ; redémarrage de l'agent prouvé par `ActiveEnterTimestamp` ; contrôles de refus précédés d'un témoin d'activité, sinon ils passeraient à vide : au moins une requête acceptée de `system:rke2-controller` après le redémarrage, et une mise à jour de ses webhooks par Triggers, deux comportements relevés dans l'audit à 16:41 et 19:20 UTC. Les 409, conflits normaux de Triggers au démarrage, ne comptent pas pour des refus.

R3, à vérifier avant d'écrire son étape : `hubble-server-certs` et `cilium-ca` existent, et deux rendus locaux du chart ont produit des certificats différents, sans le cluster. Un `helm upgrade` pourrait donc en faire tourner. Non vérifié.

ADR 0000 et 0001 complétés sur le droit de `system:rke2-controller`, limite résiduelle jusqu'à décision.

**Additif du 06/11/2026, 20:38 UTC, `h5_roles` appliquée sur accord du propriétaire (« Oui, lance h5_roles »), règles en service depuis 20:36:06 UTC.** Deux passages, tous deux rendus en échec par le script, jamais par les règles.

| Passage | Fin | Cause |
|---|---|---|
| [Premier](resultats/durcissement-h5_roles-premier-passage.log), 20:36:06 à 20:36:12 | KO, arrêté avant les redémarrages, règles déjà posées | Message de refus coupé à 200 caractères, puis `kubectl` refusé qui arrête le script sous `pipefail` |
| [Deuxième](resultats/durcissement-h5_roles.log), 20:36:37 à 20:37:31 | **« KO h5_roles » sur un seul témoin**, tout le reste OK | `kubectl patch --dry-run=server` écrit « patched », pas « server dry run ». Texte attendu faux, corrigé, étape non rejouée pour ne pas redémarrer une troisième fois |

Le témoin est tranché par [l'audit](resultats/durcissement-h5_roles-temoin.log) : `tekton-triggers-webhook`, 200 en dry-run sur son webhook, aucune étiquette `essai` écrite.

| Prédiction | Résultat |
|---|---|
| R1 | **Tenue** : jeton refusé à `system:rke2-controller` avec le message exact, témoin `system:kube-controller-manager` admis ; webhook de Kyverno refusé à Triggers, code 422, le sien admis. `auth can-i` reste à `yes` : le refus vient de l'admission, RBAC ne change pas |
| R2 | **Tenue** : Triggers redémarré, agent de `sc-build` redémarré à 20:37:05 UTC, `Ready` ; 2 requêtes acceptées de `system:rke2-controller`, 0 refusée ; 2 mises à jour de ses webhooks par Triggers, 0 refusée ; 0 erreur aux journaux de Triggers, caBundle présents, `horodatage` et `rattrapage` réussis |
| R3 | Non lancée : Cilium inchangé, `cilium-operator` reste lecteur, cinq lecteurs à ce stade |
| R4 | Non lancée : aucune construction sous ces deux règles |

**Effets réels** : deux jetons témoins de plus pour `builds/build`, un par passage, 10 minutes, jamais lus. **Non prouvé** : redémarrage complet des VM et jonction d'un nouveau nœud sous la règle ; webhook réel de Forgejo sous les deux règles, `construction_durcie` non rejouée ; agents de `sc-confiance` et `sc-stockage` non redémarrés. Retour : `kubectl delete -f politiques/roles/roles.yaml`.

**Additif du 06/11/2026, 20:51 UTC, R3 préparée à sec, rien appliqué.** Étapes `h5_cilium_sec` et `h5_cilium`, journal [resultats/durcissement-h5_cilium_sec.log](resultats/durcissement-h5_cilium_sec.log) ; le premier passage, archivé dans `durcissement-h5_cilium_sec-premier-passage.log`, finit en KO sur deux contrôles mal écrits, ni sur Cilium ni sur le cluster : `- key: tls.key` des volumes projetés pris pour une clé, et deux espaces après `tofqdns-preallocate-identities:` ignorés par mon `sed`. **Mesuré.** Le rendu, documents Secret retirés, diffère de quatre choses : la clé `enable-policy-secrets-sync`, la ligne `secrets` du ClusterRole de l'opérateur, le Role et le RoleBinding `cilium-operator-tlsinterception-secrets` (qui donnaient `create`, `delete`, `update`, `patch` sur les Secrets de `cilium-secrets`). `cilium-config` en service égale le rendu des valeurs en service, 164 clés de chaque côté, donc pas de dérive. Aucune politique de Cilium ne cite de Secret ni de TLS. Les pods de l'opérateur et de l'agent passent l'admission en dry-run serveur, Kyverno en `Deny` compris. **Lu au tag v1.20.4.** `registerCNPSecretSync` et `registerCCNPSecretSync` (`operator/pkg/networkpolicy/secretsync/secretsync.go`) n'enregistrent rien sans la clé, et `operator/pkg/secretsync/cell.go` saute alors le réconciliateur. L'agent garde sa surveillance de `cilium-secrets` par `policy-secrets-only-from-secrets-namespace`, d'où son Role conservé, sur un espace qui compte 0 Secret. **Rotation écartée.** Le chart relit `cilium-ca` et `hubble-server-certs` par `lookup` quand Helm joint le cluster, et les montées de 17:03 et 17:47 n'ont pas touché ces objets (dernière écriture 13:29:31 UTC). Le script compare leurs versions d'objet, 422 et 423, sans afficher de valeur. **Prédictions de `h5_cilium`, avant passage.** C1 : opérateur `cluster=no cilium-secrets=no`, agent inchangé `cluster=no cilium-secrets=yes`. C2 : `cilium-ca` à 422, `hubble-server-certs` à 423. C3 : pare-feu depuis `sc-build` inchangé, `6443=ouvert 2379=ferme`. C4 : trois agents prêts, état `OK`, Hubble `Ok`, 0 redémarrage de conteneur, 0 ligne `forbidden` dans le journal de l'opérateur. C5 : au moins une requête de l'opérateur dans l'audit après le passage, 0 sur des Secrets. C6 : quatre comptes de service lecteurs à l'échelle du cluster au lieu de cinq, recoupé par `essais-h5-droits.sh` avec un journal à part pour ne pas écraser celui de 20:25. **Effets à connaître.** `cilium.sh appliquer` passe la révision 4 de la release et redémarre les trois agents et l'opérateur ; `rattrapage` est suspendu pendant ce temps, pas `horodatage`, dont un passage peut échouer. C'est le chemin de 17:03 et 17:47, jamais rejoué sous les règles de H5 : le dry-run couvre l'admission, pas le redémarrage. Retour : retirer la clé de `config/valeurs-cilium.yaml`, puis `VALEURS_08C=config/valeurs-cilium.yaml cilium.sh appliquer`. **Limite vue au passage.** `config/valeurs-cilium-wireguard.yaml` ne porte ni `hostFirewall` ni cette clé, et `VALEURS_08C` ne prend qu'un fichier : H6 passée seule couperait le pare-feu d'hôte et redonnerait le droit à l'opérateur. Aucune étape H6 n'existe à ce jour, ce point est à traiter en l'écrivant. `config/valeurs-cilium-audit.yaml` ne porte pas non plus la clé : rejouer `h3_audit` la retire jusqu'à `h4_bloque`. La construction de contrôle R4 reste à lancer, H5 reste ouverte.

**Additif du 06/11/2026, 20:55 UTC, `h5_cilium` appliquée sur accord du propriétaire (« Oui, lance h5_cilium »), de 20:52:46 à 20:54:22 UTC, passage unique.** Journal [resultats/durcissement-h5_cilium.log](resultats/durcissement-h5_cilium.log), relecture [resultats/durcissement-h5_cilium-relecture.log](resultats/durcissement-h5_cilium-relecture.log), droits après passage [resultats/durcissement-h5-droits-apres-cilium.log](resultats/durcissement-h5-droits-apres-cilium.log). Révision 4 de la release, trois agents et opérateur recréés entre 20:52:52 et 20:53:03 UTC. **C1 à C6 tenues.** C1 : opérateur `cluster=no cilium-secrets=no`, agent `cluster=no cilium-secrets=yes`. C2 : `cilium-ca` 422, `hubble-server-certs` 423. C3 : `6443=ouvert 2379=ferme`. C4 : état `OK` et Hubble `Ok` sur les trois agents, 0 redémarrage de conteneur, 0 ligne `forbidden`. C6 : quatre comptes de service lecteurs à l'échelle du cluster, `generic-garbage-collector`, `namespace-controller`, `resourcequota-controller`, `tekton-triggers-core-interceptors`, recoupés par `auth can-i`. **C5, contrôle du script trop faible, refait.** La fenêtre du script ouvrait à 20:53:14, après le démarrage de l'opérateur, et ne voyait qu'une requête : les lectures d'un démarrage lui échappaient, son `OK` ne prouvait donc pas C5. Relu depuis la création du pod (20:52:52), tous stades : 20 lignes d'audit de l'opérateur, dont une ligne `watch secrets` en `ResponseComplete` à 20:52:52 qui est la fermeture de celle de l'ancien pod ; aucune requête sur des Secrets signée du pod `cilium-operator-5bd56746bc-r8ptc`. C5 tenue sur cette relecture. Le script filtre désormais sur le nouveau pod depuis sa création, correction non rejouée pour éviter un redémarrage de plus. **À côté des prédictions.** `horodatage` n'a raté aucun passage : 20:53 et 20:54 réussis, celui de 20:53 après deux `FailedScheduling`, et l'opérateur après un `FailedScheduling`, motifs non relevés. `rattrapage` est revenu à `suspend=false`, passage de 20:53 sauté comme prévu, celui de 20:54:22 réussi. L'unique `PolicyViolation` vient de la sonde `sonde_kyverno`. 0 pod en `CrashLoopBackOff`. **Sous réserve.** `cilium-secrets` reste lisible par les agents, à 0 Secret. Les relais Hubble restent absents, donc ce redémarrage ne dit rien d'un flux Hubble consommé à distance. Aucune construction n'a tourné sous cette configuration : R4 reste à lancer, H5 reste ouverte. Le passage du scan du 07/11 à 09:30 UTC reste à relire.

**Additif du 06/11/2026, 20:59 UTC, R4 lancée sur accord du propriétaire (« Oui, lance R4 »), de 20:56:40 à 20:58:26 UTC, sous H1 à H5, `h5_roles` et `tls.secretSync.enabled=false`.** Journal [preuves-h5-r4-construction_durcie.log](../08-trust-plane/resultats/preuves-h5-r4-construction_durcie.log), relevé [resultats/durcissement-h5_r4-releve.log](resultats/durcissement-h5_r4-releve.log). **R4 tenue.** Chaîne complète depuis le webhook, PipelineRun en 57 s, pod `construire` en Kata sur `sc-build`, trois TaskRuns signés, image inchangée `3a7ca1b1`, enveloppes 18 → 20, nouvelle provenance `720c3670`, porte `true`, 20/20 enveloppes couvertes, 57 bundles vérifiés, aucune anomalie de départ ni de fin ; le rejeu et la livraison non signée restent refusés. **Le « 0 refus » est relevé dans l'audit, le journal de construction ne le couvre pas.** Sur 1292 requêtes de la fenêtre : aucune de `system:rke2-controller`, aucune écriture de webhook par Triggers, aucune requête de `cilium-operator` sur des Secrets, 12 réponses 409, 45 réponses 404, et un seul 403 : `system:node:sc-build` sur `get` du pod `helper-pod-delete-pvc-a6a65ad6` de `local-path-storage`. Ce 403 n'est pas une nouveauté : 33 dans l'audit conservé, sur les pods `helper-pod` de local-path, dont celui de 18:41, antérieur aux règles de H5 ; refus de l'autorisation de nœud, sans lien avec les règles d'admission ni avec Cilium, cause exacte non établie, aucun effet relevé. Aucun événement d'alerte depuis 20:56, 0 `OOMKilled`. **Restent ouverts pour H5** : relire le passage de `scan-sample-app` du 07/11 à 09:30 UTC, premier sous `Deny`. Toujours non prouvés : redémarrage complet des VM et jonction d'un nœud sous `jetons-rke2-controller`, agents de `sc-confiance` et `sc-stockage` non redémarrés sous cette règle.

**Additif du 06/11/2026, 21:16 UTC, H6 préparée à sec, rien appliqué.** Étapes `h6_sec`, `h6`, `h6_mesure` et `h6_retrait`, journal [resultats/durcissement-h6_sec.log](resultats/durcissement-h6_sec.log) ; le premier passage, KO sur un contrôle qui ne prévoyait pas `wireguard-persistent-keepalive`, est archivé dans [resultats/durcissement-h6_sec-premier-passage.log](resultats/durcissement-h6_sec-premier-passage.log). Le rendu se limite à six clés de `cilium-config`, sans dérive des 163 clés en service. H6 reste une mesure : sans décision, `h6_retrait` suit `h6_mesure`.

Quatre constats tirés des sources de Cilium v1.20.4, non mesurés à ce stade, changent le plan de la table :
- le pare-feu d'hôte s'applique au port UDP 51871 : `ctx_is_wireguard` ne sert qu'à la trace. `hote-commun` ne l'ouvrant pas, le mode strict aurait jeté le trafic entre pods de nœuds différents. D'où `politiques/cilium-h6/hote-wireguard.yaml`, hors du répertoire appliqué en bloc par `h3_audit` et `h4_bloque` ;
- `sc-confiance` porte `node-role.kubernetes.io/control-plane` et sort du chiffrement de nœud à nœud (`node-encryption-opt-out-labels`). Forcer son entrée n'est pas recommandé par la documentation : le réglage par défaut est gardé, et le contrôle `pare_feu`, qui vise ce nœud, ne traverse pas le tunnel. D'où `temoins_h6`, vers `sc-stockage`, depuis l'hôte et depuis l'endpoint de santé ;
- le surcoût est de 95 octets dans `pkg/mtu/mtu.go`, pas les 80 de la documentation, et Kata ignore le MTU de route. Les deux contournements du guide, MTU global abaissé ou initContainer `NET_ADMIN`, sont des décisions, et aucun n'est préparé ;
- `VALEURS_08C` ne prend qu'un fichier, et le fichier WireGuard seul couperait le pare-feu d'hôte : `h6` le concatène à `config/valeurs-cilium.yaml`. `allowRemoteNodeIdentities` est retiré : `pkg/datapath/linux/config/config.go` ne s'en sert que si le CIDR strict contient l'adresse du nœud, ce qui n'est pas le cas ici.

Prédictions, avant tout passage de `h6` :

| # | Prédiction |
|---|---|
| W1 | Trois agents `OK`, deux pairs chacun, `NodeEncryption: Enabled` sur `sc-build` et `sc-stockage`, `OptedOut` sur `sc-confiance` |
| W2 | Coupure de la bascule : au plus 60 s par cible depuis `sc-build`, à l'aller comme au retour (`maxUnavailable: 2`, agents dans deux états), SSH et API joignables après coup, aucun redémarrage de conteneur en plus |
| W3 | Le pare-feu tient sur le trafic déchiffré : `cil_to_host` applique la politique d'hôte après le tunnel, donc 3100 et 3001 de `sc-stockage` restent fermés et 5000 et 3501 ouverts, depuis l'hôte comme depuis l'endpoint de santé |
| W4 | MTU de route 1405 sur l'endpoint de santé recréé. Celui de `coredns`, resté en service, n'est pas prédit : le travail `job-endpoint-mtu-updater` existe, son effet n'a pas été lu |
| W5 | Construction : image `3a7ca1b1` identique, enveloppes 20 → 22, porte `true`, durée inférieure à deux fois 57 s. Sur `enp1s0` de `sc-build`, 0 paquet de pod en clair, 0 paquet en clair avec `sc-stockage`, au moins un paquet du tunnel |
| W6 | Risque principal : le pod Kata garde un MTU de 1500. Fragments possibles sur `sc-build` (`IpFragCreates` au-dessus de 0), ou blocage du push vers Zot. `h6_mesure` s'arrête alors à 840 s, KO, sans contournement |
| W7 | Limite attendue, pas un échec : du trafic en clair reste entre `sc-build` et `sc-confiance`, en TLS (API, supervisor) |
| W8 | Retour : plus aucune clé de chiffrement dans `cilium-config`, `Encryption: Disabled`, aucune interface WireGuard, `hote-wireguard` retirée. Le module reste chargé jusqu'au redémarrage des nœuds |

**Effet de bord de cette préparation.** `cilium-dbg encrypt status`, lancé à sec sur l'agent de `sc-build`, a très probablement chargé le module `wireguard` de ce nœud : `dmesg` l'y date de 21:06:40, dans la fenêtre de cet appel, entre 21:03:57 et 21:10:12, et il n'est chargé sur aucun des deux autres, où la commande n'a pas été lancée. Le lien de cause n'est pas prouvé. Aucune interface n'a été créée et `Encryption: Disabled` reste vrai. Le module n'a pas été retiré, et les étapes lisent désormais `cilium-dbg status` à la place.

**Non couvert par ces étapes** : aucune requête d'un vrai pod applicatif ne sert de témoin de pare-feu, seul l'endpoint de santé ; le mode strict en entrée reste coupé ; la rotation des clés et le redémarrage d'un nœud sous WireGuard ne sont pas mesurés. `h6` ne lance pas `temoins`, qui écraserait des journaux cités.

**Additif du 06/11/2026, 21:28 UTC, prédictions du scan manuel, accord du propriétaire (« Oui, lance le scan »), avant passage.** Le dernier succès de `scan-sample-app` date de 15:40:59 UTC, avant H1 : il n'a jamais tourné sous H1 à H5, et `h5_sec` n'a jugé que son gabarit. [essais-h5-scan.sh](essais-h5-scan.sh) crée le job `scan-sample-app-h5-manuel` depuis le CronJob, une seule fois, journal `resultats/durcissement-h5_scan.log`. État de départ relevé : 2 referrers sur l'image `3a7ca1b1`, 13642 Mo libres sur sc-confiance, aucun job dans l'espace.

| Prédiction | Attendu | Risque |
|---|---|---|
| N1 | Job et pod admis, aucun refus d'admission dans l'audit, aucun `FailedCreate` | Faible : `h5_sec`, 0 échec sur le gabarit |
| N2 | Six conteneurs à 0, job réussi en 300 s au plus (109 et 126 s les 05 et 06/11) | Moyen : première fois sous le pare-feu d'hôte et les politiques de H3 et H4 |
| N3 | `revocation` sans OOM ni redémarrage sous 500m et 256Mi, valeurs non mesurées | Moyen |
| N4 | Referrers 2 → 3 sur l'image | Lié à N2 |
| N5 | `lastSuccessfulTime` à jour, `lastScheduleTime` vide, aucun job actif : le passage de 09:30 UTC reste libre | Faible |
| N6 | Marqueurs SOURCE, SCAN, PUBLIE et révocation lus dans Grafana par l'auditeur, relais d'Alloy exercé | Faible |

En cas d'échec, le passage est archivé tel quel et rien n'est relancé sans nouvel accord. Ce job ne prouve pas le déclenchement par le planificateur : le passage du 07/11 à 09:30 UTC reste à relire.

**Additif du 06/11/2026, 21:31 UTC, scan manuel passé de 21:28:51 à 21:30:53 UTC, H5 close sur l'admission et l'exécution, sous réserve du planificateur.** Journal [resultats/durcissement-h5_scan.log](resultats/durcissement-h5_scan.log), passage unique, bilan du script KO sur N6 seul ; relecture [resultats/durcissement-h5_scan-relecture.log](resultats/durcissement-h5_scan-relecture.log).

| Prédiction | Résultat | Mesure |
|---|---|---|
| N1 | Tenue | Job et pod admis, aucun `FailedCreate`, aucun 403 ni 422 dans l'audit de l'espace ; cinq 404 de lecture par `cilium` et `kyverno-reports-controller`, aucun d'admission ; trois rapports de Kyverno, 0 échec |
| N2 | Tenue | Six conteneurs à 0, job réussi, 126 s à 5 s près, sous les politiques de H3 et H4 et le pare-feu d'hôte |
| N3 | Tenue | `revocation` à 500m et 256Mi, ni OOM ni redémarrage ; consommation réelle non mesurée, le conteneur vit moins de 2 s |
| N4 | Tenue | Referrers 2 → 3, sujet `3a7ca1b1`, 5 vulnérabilités, 0 KEV |
| N5 | Tenue | `lastSuccessfulTime` à 21:30:53 UTC, `lastScheduleTime` vide, aucun job actif |
| N6 | Tenue à la relecture | Le script affiche KO, `5, attendu 4` : mon contrôle comptait une seule révocation, or `jetons` écrit aussi `révoqué`. Les cinq lignes attendues sont lues dans Grafana par l'auditeur. Contrôle corrigé, non rejoué : le job existe et le script refuse de le recréer |

Point bas sur sc-confiance : 10217 Mo pour 13641 Mo au départ, soit 3424 Mo, dans la lignée de 3413 et 3441 Mo. Effet attendu d'un job manuel : avertissement `UnexpectedJob` sur le CronJob. Le job et son pod restent dans l'espace, sous la limite d'historique du CronJob.

**Reste de H5** : relire le passage du 07/11 à 09:30 UTC, seule preuve du déclenchement par le planificateur. Non couvert, inchangé : signature fausse et corps modifié du test 5, test 6 sous limites.

**Additif du 06/11/2026, 21:41 UTC, `h6` appliquée sur accord du propriétaire (« Oui, lance h6 »), à partir de 21:34:52 UTC, passage unique, OK.** Journal [resultats/durcissement-h6.log](resultats/durcissement-h6.log), relecture [resultats/durcissement-h6-relecture.log](resultats/durcissement-h6-relecture.log). Révision 5 de la release cilium. WireGuard reste actif en attendant `h6_mesure` et `h6_retrait`, chacun avec son accord.

| Prédiction | Résultat | Mesure |
|---|---|---|
| W1 | Tenue | Trois agents `OK`, 2 pairs chacun, `Enabled` sur sc-build et sc-stockage, `OptedOut` sur sc-confiance, interface `cilium_wg0` à 1405 sur les trois |
| W2, aller | Tenue, mieux que prédit | 240 mesures à la seconde depuis sc-build, 0 échec vers Zot et les deux coredns, pour 60 s au plus prédites. Nouvelles connexions seulement : une connexion établie coupée ne se verrait pas. 17 redémarrages de conteneurs, inchangé |
| W3 | Tenue sur ces témoins | Témoins vers sc-stockage inchangés par le tunnel, depuis l'hôte et l'endpoint de santé ; pas de vrai pod applicatif |
| W4 | Tenue | Route à 1405 sur les endpoints de santé. Non prédit : coredns est aussi à 1405 sur sc-confiance et sc-stockage, alors qu'il n'a pas redémarré |

Certificats 422 et 423, pare-feu, Kyverno, SSH, API et Zot inchangés. `rattrapage` a repris et réussi à 21:40:36 UTC, `horodatage` à 21:40:17 UTC.

**Non prédit, cause non établie** : `Invalid source ip` à 57 en sortie sur l'agent de sc-build, recréé à 21:35:11 UTC, 0 sur les deux autres. Le compteur n'a pas bougé entre la fin de `h6` et 21:41:07 UTC, et aucun refus de ce motif n'apparaît sur 20 s de `cilium-dbg monitor`. Hubble n'en garde pas trace. Aucune valeur de référence : `refus_agent` n'existait pas avant H6.

W5 à W8 restent à mesurer, le risque MTU sous Kata compris.

**Additif du 06/11/2026, 21:48 UTC, `h6_mesure` lancée sur accord du propriétaire (« Oui, lance h6_mesure »), de 21:42:22 à 21:45 UTC, passage unique, KO sur W5.** Journaux [resultats/durcissement-h6_mesure.log](resultats/durcissement-h6_mesure.log) et [../08-trust-plane/resultats/preuves-h6-construction_durcie.log](../08-trust-plane/resultats/preuves-h6-construction_durcie.log). La construction a réussi ; le KO vient de la prédiction « 0 paquet de pod en clair », qui ne tient pas. Passage conservé tel quel, seuil non modifié.

| Prédiction | Résultat | Mesure |
|---|---|---|
| W5 | **Non tenue sur un point** | Tenu : image `3a7ca1b1`, enveloppes 20 → 22, porte `true`, 95 s pour moins de 114 s, 0 paquet en clair avec sc-stockage, 62637 paquets de tunnel avec sc-stockage. Non tenu : **62 paquets d'adresses de pods en clair**, pour 0 prédit |
| W6 | Réalisée sous sa forme bénigne | Pas de blocage. Fragments du tunnel : `IpFragCreates` de 6 à 146 sur sc-build, `IpReasmOKs` de 4 à 74 sur sc-stockage, 70 fragments vus dans la capture, sur 62637 paquets. Effet sur la durée non isolé |
| W7 | Tenue, à préciser | 2582 paquets en clair avec sc-confiance. Tout n'y est pas en TLS : voir ci-dessous |

**Nature des 62 paquets.** La capture de la construction est effacée par l'étape, il n'en reste que les classes : trois adresses, `10.42.0.179` (28), `10.42.0.221` (19), `10.42.1.177` (15). Une capture de 90 s prise ensuite, hors construction, en-têtes seuls, retrouve ces trois mêmes sources ([resultats/durcissement-h6-clair.log](resultats/durcissement-h6-clair.log)) :

| Source | Destination | Nature |
|---|---|---|
| `rke2-metrics-server`, sur sc-confiance | kubelet de sc-build, 10250 | TLS |
| Endpoint de santé de sc-confiance, 4240 et ICMP | Hôte de sc-build | Sondes de santé de Cilium, HTTP en clair |
| Endpoint de santé de sc-build, 4240 | Hôte de sc-confiance | Réponses aux sondes, HTTP en clair |

Chaque flux va d'un pod vers un nœud, et chacun touche sc-confiance, hors du chiffrement de nœud à nœud. Aucun flux de pod à pod en clair n'apparaît dans les 90 s. Ce rapprochement repose sur les adresses : la capture de 90 s n'est pas celle de la construction. Ma prédiction confondait « adresse de pod » et « pod à pod », et n'avait pas vu que W7 s'étend aux sondes de santé.

**Durée.** 95 s contre 57 s pour R4 et 55 s pour la construction de 19:26 UTC : un seul passage, cause non isolée. `Invalid source ip` reste à 57, `Policy denied` à 246 avant et après : aucun nouveau refus.

**Non couvert** : retour W2 et W8, passage de `h6_retrait` non lancé. Rotation des clés, redémarrage d'un nœud sous WireGuard et mode strict en entrée restent non essayés.

**Additif du 06/11/2026, 21:55 UTC, `h6_retrait` lancée sur accord du propriétaire (« Oui, lance h6_retrait »), de 21:49:40 à 21:54 UTC, passage unique, OK. H6 est mesurée et retirée, comme prévu sans décision préalable.** Journal [resultats/durcissement-h6_retrait.log](resultats/durcissement-h6_retrait.log). Révision 6 de la release cilium.

| Prédiction | Résultat | Mesure |
|---|---|---|
| W2, retour | Tenue | 240 mesures : 2 échecs vers Zot et le coredns de sc-stockage, de 21:50:10 à 21:50:14 UTC, 1 vers celui de sc-confiance à 21:50:10 UTC, pour 60 s au plus prédites. 17 redémarrages de conteneurs, inchangé |
| W8 | Tenue | Aucune clé de chiffrement dans `cilium-config`, `Encryption: Disabled` et 0 interface WireGuard sur les trois nœuds, `hote-wireguard` retirée, module chargé sur les trois, route à 1500 |

Certificats 422 et 423, pare-feu, témoins vers sc-stockage, API, SSH et Kyverno inchangés. `rattrapage` et `horodatage` tournent et réussissent. Le retour coupe un peu plus que l'aller, 0 échec contre 2 au plus sur une fenêtre de 5 s, sans cause établie.

**Bilan de H6** : WireGuard fonctionne sous ce pare-feu, avec Kata et sans changement de l'image, et le retour est propre. Sept prédictions sur huit tiennent. W5 ne tient pas sur les paquets de pods en clair : sc-confiance reste en dehors pour les flux de pod vers nœud, dont les sondes de santé de Cilium en HTTP. Décision du propriétaire à prendre : l'activer pour de bon ou non. Forcer sc-confiance dans le chiffrement reste une question à part, déconseillée par la documentation de Cilium.

**Reste de H5** : passage du 07/11 à 09:30 UTC, à relire, sur un Cilium sans WireGuard.

### Additif du 06/11/2026, 22:02 UTC : relecture du passage planifié, prédictions P1 à P6, avant le passage

`essais-h5-planifie.sh` relit le premier passage de `scan-sample-app` déclenché par le planificateur, attendu le 07/11 à 09:30:00 UTC. Il est en lecture seule, refuse de partir avant cette heure et refuse si son journal existe. Rien n'a été changé dans le cluster. Essai à blanc sur le job manuel à 22:01 UTC : tous les contrôles s'exécutent, et les deux seuls KO sont ceux attendus d'un job manuel (aucun passage planifié, job créé par `system:admin`). Cet essai n'est pas archivé comme preuve.

| Prédiction | Attendu |
|---|---|
| P1, planificateur | `lastScheduleTime` à 2026-11-07T09:30:00Z, un seul job neuf rattaché au CronJob, créé dans la minute, par `system:serviceaccount:kube-system:cronjob-controller` en 201. Ce nom de compte est déduit de `job-controller`, vu dans l'audit, et n'a pas été observé |
| P2, admission | Pod créé par `job-controller` en 201, aucun 403 ni 422 dans l'espace `scan` |
| P3, conteneurs | Six conteneurs à 0, sans redémarrage ni OOM, pod en moins de 300 s (118 s pour le job manuel) |
| P4, Zot | Referrers 3 → 4 sur `3a7ca1b1`. Base `2026-11-07` lue, le timer `base-grype` étant prévu le 07/11 à 08:12:33 UTC. Le nombre de vulnérabilités n'est pas prédit : il dépend de la base du jour |
| P5, historique | Le job manuel reste listé à côté du neuf, sous la limite de 3 |
| P6, Grafana | Cinq marqueurs lus par l'auditeur : `SOURCE`, `SCAN`, `PUBLIE` et les deux révocations |

Bornes de cette relecture, relevées avant le passage :

- Le CronJob a `startingDeadlineSeconds: 3600` : si les VM sont arrêtées ou suspendues au-delà de 10:30 UTC, le passage est sauté et rien n'est prouvé.
- Si `base-grype` échoue, le scan prend la base du 06/11 : P4 ne tient pas sur ce point, sans bloquer le scan. La porte refuse une base de plus de 3 jours.
- La différence avec le job manuel se réduit au créateur du job : le pod passe par le même contrôleur et les mêmes règles.
- L'audit de sc-confiance garde 11 fichiers de 100 Mo (`--audit-log-maxbackup=10`), soit environ 16 h au rythme relevé de 88 minutes par fichier : à relire avant environ 01:30 UTC le 08/11.

**Additif du 06/11/2026, 22:10 UTC : redémarrage des VM préparé à sec sous H1 à H5, non lancé.** Il demande son propre accord : il arrête les trois VM et relance OpenBao scellé. Contrôle : [durcissement-redemarrage-sec.log](resultats/durcissement-redemarrage-sec.log), syntaxe et dry-run serveur, rien écrit dans le cluster.

Deux blocages de [`redemarrer.sh`](../08-trust-plane/redemarrer.sh) sont levés dans le code :
- **Chains** : annoncé à S1. Si le contrôleur a le conteneur `identifiants`, son pod est recréé après le descellement, comme celui du TSA ;
- **`kata.sh temoin` et `reseau`** : le gabarit `pod_spec` n'a pas de limites, donc `limites-obligatoires` le refuse. Mesuré en dry-run serveur : refusé sans limites, admis avec, sous Kata comme sous runc. Les limites sont posées par `local LIMITES_MESURE=1` dans ces deux étapes seulement, et le contrôle montre qu'elles n'en sortent pas. `kata.sh essais` les garde hors de ses pods, car il attend 1 vCPU et moins de 2048 Mio, et une limite Kata en ajoute à l'invité : il reste refusé sous `Deny`, et il n'a sa place qu'avant H5.

| Prédiction pour le jour du redémarrage | Attendu | Confiance |
|---|---|---|
| V1, nœuds | Trois nouveaux `bootID`, `Ready`, sous `jetons-rke2-controller` et le pare-feu d'hôte | **Moyenne** : jamais mesuré sous ces règles |
| V2, confiance | Kyverno répond, OpenBao scellé puis descellé, même clé Transit, TSA relancé | Haute : `deverrouiller` et le TSA ont tourné sous H1 à H5 |
| V3, Chains | Pod recréé, `identifiants` finit par « jeton révoqué », `prets tekton-chains` OK | Haute : même chemin que `s1_chains` |
| V4, Kata | Pod témoin admis, noyau de l'invité `6.18.56` | Haute : admission mesurée à sec |
| V5, réseau | Pods admis, aucune fenêtre, usurpations refusées | **Moyenne** : `kata.sh reseau` n'a jamais tourné sous H3, H4 ni avec des limites, qui ajoutent du CPU et de la mémoire à l'invité |

Bornes :
- Sous RKE2, passer `DISTRO=rke2`.
- Le script écrase `redemarrage-vm.log`, `kata-reseau.log`, `openbao-deverrouiller.log`, `openbao-controle.log` et `tsa-temoin.log` : à sauvegarder avant.
- Le redémarrage décharge `wireguard` des trois nœuds. S'il tombe pendant le créneau du 07/11, de 09:30 à 10:30 UTC, il peut faire sauter le passage planifié : à lancer après la relecture de P1 à P6.
- `rejeu.sh` n'est pas modifié : H1 à H5 et `secrets.sh` n'y sont toujours pas intégrés, et cette intégration ne sera proposée qu'une fois le jalon prouvé. `kata.sh reseau` y passera désormais avec des limites, sans mesure de comparaison.

**Additif du 06/11/2026, 22:22 UTC : témoin de l'étape `controleurs` corrigé à sec, valeurs figées de `redemarrer.sh` relues.** Contrôle : [durcissement-temoins-sec.log](resultats/durcissement-temoins-sec.log), dry-run serveur et lectures, rien écrit dans le cluster.

- **Blocage trouvé :** l'étape `controleurs` de [`preuves.sh`](../08-trust-plane/preuves.sh) a tourné pour la dernière fois à 15:25 UTC, avant `h5_deny`. Son pod témoin, `ct-pod-essai`, est refusé sous `Deny` même au nom de l'administrateur : le témoin finirait KO.
- **Refus instable :** ce pod a reçu deux réponses sur deux essais, `jeton-compte-default` seule au premier, non archivé, puis `limites-obligatoires` et `images-zot-par-digest`. Cause non établie. Le motif attendu de `ct_refus`, la règle native `tekton-controleurs-builds`, aurait pu être masqué de la même façon.
- **Correction :** le pod passe sans jeton, avec l'image de Zot par digest et des limites. `hc-pod-default` reste inchangé, `kube-system` étant exclu de ces règles.
- **Mesuré :** l'ancien pod est refusé, le nouveau admis en dry-run, et `bash -n` passe.
- **Valeurs de `redemarrer.sh` :** sonde Kyverno refusée par `zone-confiance` avec le message attendu, manifeste Zot en HTTP 200, `main` de Forgejo à `6391fd43…`, aucun pod hors jobs non `Ready` dans les six espaces de `prets()`.

Bornes :
- Le dry-run a été fait dans `bancc`, car `preuve-controleurs` n'existe qu'au passage de l'étape, qui ne l'a pas créé. Rien ne prouve encore le comportement dans cet espace.
- `preuves.sh controleurs` n'a pas été rejouée : les refus au nom des contrôleurs restent à mesurer sous `Deny`.
- Les étapes de `preuves.sh` n'ont pas toutes été passées en revue, seuls les pods écrits en dur ont été relus. Les témoins passant par des TaskRun ou des fichiers de politique ne sont pas couverts.
- Ces contrôles n'annoncent pas la réussite du redémarrage : V1 à V5 restent à mesurer.

### Additif du 06/11/2026, 22:33 UTC : étape `controleurs` relevée à sec sous H1 à H5

`essais-h5-controleurs.sh` reprend les contrôles de `preuves.sh controleurs` sans rien créer : lectures, `can-i` et dry-run serveur, y compris pour les essais que l'étape lance pour de bon. Passage de 22:32:13 à 22:32:26, 0 écart, journal `resultats/durcissement-h5_controleurs_sec.log`.

Mesuré :
- Règle `tekton-controleurs-builds` en `Fail` et `Deny`, droits de locataire bornés à `builds`, `--namespace=builds` inchangé après S1.
- Dix essais par contrôleur refusés par les droits, dont les lectures de Secrets hors de `builds`.
- Seconde barrière : pod refusé par la règle au nom des deux contrôleurs dans `bancc`, droits contournés par `--as-group system:masters`, car la règle juge le nom du compte ; même pod admis pour l'administrateur.
- Six créateurs de pods de `kube-system`, chacun admis, valeur attendue sous RKE2 inchangée après `h5_roles`.
- Audit : 0 refus dans `builds`, 73 pods créés dans `builds` depuis la pose de la règle, lectures de Secrets des deux contrôleurs dans `builds` seulement.
- Aucun redémarrage, aucun refus des droits dans leurs journaux depuis leur démarrage. Les quatre écarts redoutés dans la prédiction ne se sont pas produits.

Bornes :
- Ce relevé ne remplace pas un passage de l'étape. L'espace `preuve-controleurs` et ses liaisons temporaires n'ont pas été créés ; seule la création de l'espace a été admise en dry-run.
- Le contournement par groupe n'est pas la liaison de locataire de l'étape : le refus de la règle est mesuré, pas le chemin exact.
- Le passage laisse deux refus de plus dans l'audit de l'API, un par contrôleur, dans `bancc`. Rien n'a été écrit dans le cluster.
- Les autres étapes de `preuves.sh` restent non relues sous H5, et ce relevé n'annonce rien sur le redémarrage : V1 à V5 restent à mesurer.

**Additif du 06/11/2026, 22:43 UTC, étapes `resolveurs` et `helm_cilium` sous H1 à H5, prédictions avant passage, rien écrit dans le cluster.** Demande : « continue ». Le passage planifié du scan n'étant que demain à 09:30 UTC, le travail reste à sec. `intercepteurs` est écartée : elle retire une liaison et redémarre un déploiement. `reelle` a déjà son passage de 19:06 UTC. `helm_cilium` ne contient que des lectures, des `can-i` et des dry-run serveur : elle peut donc être lancée telle quelle, avec `JOURNAL=preuves-h5`, sans écraser `preuves-helm_cilium.log`. `resolveurs` crée un espace et des ResolutionRequests : seul un relevé à sec est fait, par [essais-h5-resolveurs.sh](essais-h5-resolveurs.sh), référence [preuves-resolveurs.log](../08-trust-plane/resultats/preuves-resolveurs.log) de 15:25 UTC, avant H1.

| Prédiction | Attendu |
|---|---|
| A1, `resolveurs`, droits | Mêmes constats qu'à 15:25 : Role de `builds` en `get` seul, `can-i` à `no,yes,no,yes,no,yes,yes`, lectures refusées par les droits |
| A2, `resolveurs`, cibles | `rke2-serving` et `signing-secrets` présents, lecture de `signing-secrets` refusée (ajoutée au relevé). `zot-chains` absent depuis S1 : son refus reste mesuré, sur un objet absent |
| A3, `resolveurs`, admission | Espace `preuve-resolveurs` et deux ResolutionRequests de `builds` admis en dry-run serveur |
| A4, `resolveurs`, pod | Prêt, 0 redémarrage, 0 refus des droits dans son journal |
| A5, `resolveurs`, audit | Aucune lecture hors de `builds` sauf les deux 403 de 15:25. `get secrets builds 200` toujours à 1 : le chemin du Secret n'a aucun passage sous H5. Au moins un `get serviceaccounts builds 200` depuis `h5_deny`, peu sûr : le résolveur peut servir un bundle par digest depuis son cache, non lu |
| A6, `resolveurs`, lecteurs | 4 lecteurs, sans `cilium-operator`, retiré par `h5_cilium`. **Écart attendu** : la valeur figée de `preuves.sh` en attend 5, l'étape finirait KO si elle était rejouée. Correction après ce relevé |
| A7, `helm_cilium` | Passage complet sans KO, sous sa prédiction propre : 6 créateurs de pods dans `kube-system`, aucune liaison de compte de service vers `cluster-admin`, release `deployed cilium-1.20.4`, refus par les droits des deux contrôleurs, témoin administrateur admis |

**Additif du 06/11/2026, 22:45 UTC, résultat des prédictions A1 à A7, six tenues sur sept, rien écrit dans le cluster.** Relevé `resolveurs` de 22:43:47 à 22:43:53 UTC, journal [resultats/durcissement-h5_resolveurs_sec.log](resultats/durcissement-h5_resolveurs_sec.log) ; complément de 22:44:27 ajouté à la suite, sans réécrire le relevé. `helm_cilium` de 22:44:28 à 22:44:54 UTC, journal [preuves-h5-helm_cilium.log](../08-trust-plane/resultats/preuves-h5-helm_cilium.log), 20 lignes OK, 0 KO.

| Prédiction | Résultat |
|---|---|
| A1 | Tenue : mêmes constats qu'à 15:25 |
| A2 | Tenue : `signing-secrets` refusé par les droits ; `zot-chains` absent, refus mesuré sur un objet absent |
| A3 | Tenue : espace et deux ResolutionRequests admis en dry-run serveur |
| A4 | **Fausse** : 2 refus pour 0 prédit. Le pod date de 13:38 UTC et n'a jamais redémarré ; les 2 lignes sont celles de l'essai de 15:25:36 et 15:25:37, horodatées dans le complément. Aucun refus nouveau. J'avais supposé le pod recréé par H5 sans le vérifier |
| A5 | Tenue : 85 `get serviceaccounts builds 200` contre 46 à 15:25, `get secrets builds 200` toujours à 1 (15:25:36), aucune lecture hors de `builds` sauf les deux 403. Entrées d'audit gardées depuis 13:48 UTC |
| A6 | Tenue : 4 lecteurs, sans `cilium-operator` ; la valeur figée en attendait 5 |
| A7 | Tenue : passage complet, 6 créateurs, 0 liaison, `deployed cilium-1.20.4` |

**Corrigé à sec dans `preuves.sh`, étapes non rejouées.** Liste des lecteurs à 4 et lecture de `signing-secrets` ajoutée ; prédiction ajoutée marquée non aveugle.

**Non prédit, relevé par A4.** Le pod des résolveurs n'est jamais repassé par l'admission sous H1 à H5. Un pod bâti sur le gabarit de son déploiement est admis en dry-run serveur : un redéploiement ne serait pas refusé à l'admission. Le démarrage réel d'un nouveau pod n'est pas mesuré.

Bornes :
- Aucune résolution réelle sous H1 à H5 par le chemin du Secret `zot-images` ; le chemin par compte de service tourne, d'après l'audit. Les refus dans `preuve-resolveurs` ne sont pas rejoués.
- Les refus de `zot-chains` de l'étape `controleurs`, cités à 22:33, portent eux aussi sur un objet absent. `signing-secrets` est refusé par les droits aux deux contrôleurs (complément de 22:45:43) : Chains le reçoit par un volume, pas par l'API. La même lecture est donc ajoutée à `controleurs`, étape non rejouée.
- `helm_cilium` a laissé des dry-run dans l'audit et deux lignes dans `chrono.tsv`, rien d'autre.
- Restent non relues sous H5 : `reglec`, `attseule`, `enveloppes`, `reserve_c`, `decision3`, `bascule`, `controle6`, `controle7`, `temoins_scan`, et les tests 5 et 6, sans passage sous H5. `controleurs` et `resolveurs` restent à rejouer pour de bon.

## Additif du 06/11/2026, 22:56 UTC : étapes sans passage sous H5, relecture à sec

Rien écrit dans le cluster ni dans Zot, aucune de ces étapes rejouée. Prédictions C1 à C9 committées avant le relevé (`27834ee`), prédiction D aussi (`10be4a5`). Journal : `resultats/durcissement-h5_figees_sec.log`, complément compris.

**Résultat.** H5 ne bloque aucune de ces étapes d'après la lecture et les mesures. Deux blocages existent, sans lien avec H5 : la bascule pour trois étapes, le rejeu de zéro pour `reserve_c`. Le chemin 2 de la bascule reste sans passage réel.

| Étapes | Constat | Preuve | Reste à mesurer |
|---|---|---|---|
| `reglec`, `attseule`, `controle6`, `controle7`, `temoins_scan` | Même Job : `juger` (`politique.sh:1299`) rend toujours `politique/porte-job.yaml` | Sous `Deny`, 0 KO dans `preuves-h5-test7.log` (13 VERDICT, ConfigMap `porte-temoin` comprise) ; 15 VERDICT dans `preuves-h5-test8.log` ; contrôles 9, 6 et 7 à ok dans `preuves-h5-r4-construction_durcie.log` | Verdicts propres à ces étapes, dont `porte.fermeture_plateforme` de `reglec`, jamais mesuré |
| `enveloppes`, `decision3` | Bloquées par la garde `gabarit_essai`, levée par `PIPE_ESSAI` | `pr_gabarit` déjà passé sous `Deny` par le test 7 avec `PIPE_ESSAI` ; gabarit en service `sample-app` (C7) | Les deux étapes. `decision3` modifie et redémarre Zot : accord propre |
| test 5 | KO immédiat : `gabarit_essai` sans condition (`preuves.sh:342`) | C7 | Autre secret et corps modifié |
| `bascule` | Chemin 1 équivalent à `construction_durcie`, passée sous H5 | R4 et H6 ; PipelineRun du gabarit admis en dry-run serveur pour `el-forgejo` et `rattrapage` (D) | Chemin 2 : **0 création réelle** par `rattrapage` depuis `h5_deny` (C8) |
| `reserve_c` | Non rejouable, déjà hors du rejeu : 5 dépôts d'essai du 01/11 en 404 (C6) | Son pod ne va qu'au CLI Kyverno local, jamais à l'API | Rien : mesure du 01/11 gardée |
| test 6 | Dernier passage sous H4, à 17:48 UTC, avant H5 | Pod Kata privilégié admis (`preuves-h5-sec_h5.log`) ; TaskRun réel sous H5 (`preuves-h5-test1.log`) ; construction sous Kata (R4) | Le test lui-même sous limites |

**Prédictions.** C1, C3, C4, C7, C8 et D tenues. Six KO au journal, quatre causes, toutes les miennes, aucune due à H5 :

| Prédiction | Mesuré | Cause |
|---|---|---|
| C2, clé du scanner `8cbcbb4e` | `1656a3fa` | Texte figé, affiché par `controle7`, jamais comparé. Clé refaite par le rejeu RKE2 (`1f66a3c`), identique dans la ConfigMap, contrôle 7 ok. Libellé corrigé dans `preuves.sh` |
| C5, `.att` par `poc-build` seul | 12 `poc-build`, 6 `poc-ecriture` | Les 6 sont dans `essais-j8/test7`, témoins du test 7 ; dans `builds/`, `poc-build` seul : le filtre de `decision3` reste valable après S1 |
| C6, referrers de `builds/sample-app` | 0 | Chains écrit en mode dsse, par tags : `.sig` et `.att` à 200. Aucune étape n'attend le contraire |
| C9, Jobs de la porte (3 KO) | 0 Job | `ttlSecondsAfterFinished: 3600` : plus aucun Job à lire. Mesure mal choisie, remplacée par les VERDICT archivés ci-dessus |

**Corrigé à sec.** Libellé de la clé du scanner dans `preuves.sh`, étape non rejouée.

Bornes :
- « Couvert » vaut pour l'admission et l'exécution du Job de la porte ou du TaskRun, pas pour le verdict de chaque étape.
- Le dry-run D prouve l'admission, pas la création par le binaire `rattrapage` sous H5. Son passage de chaque minute s'arrête à `PRESENT`.
- `essais-h5-figees.sh` n'est pas à relancer tel quel : ses valeurs fausses restent telles qu'elles ont été prédites.

## Additif du 07/11/2026, 08:48 UTC : mesures réelles restantes, préparées à sec

Rien lancé, rien écrit dans le cluster ni dans Zot. Prédictions K, L, T, B et X, effets à connaître et commandes : `resultats/mesures-reelles-predictions.md`, committés avant tout passage. Chaque mesure demande son accord, après la relecture du scan de 09:30 UTC.

Ajouté à `08-trust-plane/preuves.sh`, jamais lancé : étapes `test5_refus` (livraisons refusées du test 5, rien de construit) et `rattrapage_durci` (chemin 2 de la bascule seul, 2 enveloppes de plus sur l'image réelle). `controleurs` et `resolveurs` retirent maintenant leur espace d'essai après un KO.

## Additif du 07/11/2026, 09:50 UTC : passage planifié du scan relu, P1 à P6 tenues, réserve du planificateur levée

La relecture programmée a lancé une fois `essais-h5-planifie.sh`, de 09:35:17 à 09:35:19 UTC, en lecture seule. Journal : [resultats/durcissement-h5_planifie.log](resultats/durcissement-h5_planifie.log), avec un complément à la main de 09:49 UTC, lui aussi en lecture seule. Rien n'a été écrit dans le cluster ni dans Zot.

**Résultat.** Le planificateur a déclenché `scan-sample-app` sous H1 à H5. H5 est close sur l'admission et l'exécution, planificateur compris. Restent non couverts, inchangés : signature fausse et corps modifié du test 5, test 6 sous limites.

| Prédiction | Mesuré | Verdict |
|---|---|---|
| P1, planificateur | `lastScheduleTime` à 2026-11-07T09:30:00Z, un seul job neuf, `scan-sample-app-29900730`, créé 0 s après l'heure, par `system:serviceaccount:kube-system:cronjob-controller` en 201 (complément). Le nom de compte, déduit avant le passage, est maintenant observé | Tenue |
| P2, admission | Pod créé par `job-controller` en 201 à 09:30:00.17 (complément), 0 refus 403 ou 422 dans `scan` | Tenue |
| P3, conteneurs | Six conteneurs à 0, aucun redémarrage ni OOM, pod en 110 s, borne 300 s | Tenue |
| P4, Zot | Referrers 3 → 4 sur `3a7ca1b1`, base `2026-11-07` lue, 5 vulnérabilités, 0 KEV | Tenue |
| P5, historique | Job manuel `scan-sample-app-h5-manuel` toujours listé à côté du neuf | Tenue |
| P6, Grafana | Cinq marqueurs lus par l'auditeur | Tenue |

**Bilan du script KO, sur deux contrôles mal écrits.** Les créations du job et du pod portent un horodatage dans la seconde 09:30:00. Le script compare la borne comme une chaîne, et `"…09:30:00.104974Z" >= "…09:30:00Z"` est faux, `.` précédant `Z` en ASCII. Le complément reprend le même extrait d'audit avec une borne à 09:29:00Z : deux créations en 201, aucun refus. Le script n'est pas corrigé : il refuse de repartir dès que son journal existe, et ne sert qu'une fois.

Seul autre écart à l'audit : quatre 404 de `kyverno-reports-controller` sur ses propres rapports, sans lien avec l'admission.

Ce passage ne prouve pas le saut d'un passage manqué (`startingDeadlineSeconds`), ni le scan après un redémarrage des VM.

## Additif du 07/11/2026, 10:22 UTC : étape `controleurs` passée sous H1 à H5, K1 à K7 tenues

Passage lancé sur accord du propriétaire (« Oui »), de 10:21:24 à 10:21:46 UTC, avec `JOURNAL=preuves-h5`. Journal : [preuves-h5-controleurs.log](../08-trust-plane/resultats/preuves-h5-controleurs.log), 63 OK et 0 KO, code 0.

| Prédiction | Mesuré |
|---|---|
| K1 | 0 KO, code 0 |
| K2 | 22 essais refusés par les droits ; 0 objet créé, 0 annotation posée |
| K3 | 2 refus par `ValidatingAdmissionPolicy 'tekton-controleurs-builds'` dans `preuve-controleurs`, un au nom de chaque contrôleur ; témoin administrateur admis. C'est le premier refus réel par ce chemin sous H5 |
| K4 | 6 comptes de service peuvent créer des pods dans `kube-system` ; le pod `default` est admis pour chacun |
| K5 | 0 refus de la règle dans `builds` ; 28 pods créés dans `builds` par le contrôleur depuis la pose de la règle |
| K6 | 0 lecture de Secret hors de `builds`, 0 réponse 403, 0 redémarrage, 0 refus des droits dans les deux journaux |
| K7 | Espace d'essai introuvable ensuite, `can-i create pods` à `no` pour les deux contrôleurs |

Les sept prédictions sont tenues. L'espace d'essai et ses liaisons temporaires sont supprimés, et le cluster est revenu à son état d'avant. Les lecteurs de Secrets de `kube-system` sont inchangés depuis `h5_cilium` : cinq comptes, dont quatre lisent tout le cluster. X1 sera relevée après les quatre mesures.

## Additif du 07/11/2026, 10:30 UTC : étape `resolveurs` passée sous H1 à H5, L1 à L8 tenues

Passage lancé sur accord du propriétaire (« Oui, resolveurs »), de 10:29:36 à 10:29:47 UTC, avec `JOURNAL=preuves-h5`. Journal : [preuves-h5-resolveurs.log](../08-trust-plane/resultats/preuves-h5-resolveurs.log), 18 OK, 0 KO, code 0. Un complément à la main, en lecture seule, y est ajouté à 10:30 UTC pour L8.

| Prédiction | Mesuré |
|---|---|
| L1 | 0 KO, code 0 |
| L2 | 5 lectures refusées par les droits |
| L3 | Résolution du bundle en service réussie dans `builds`, une fois par le compte `default`, une fois par le Secret `zot-images`. C'est le premier passage réel sous H5 du chemin du Secret |
| L4 | 2 résolutions échouées dans `preuve-resolveurs` : refus sur le compte de service, puis sur le Secret |
| L5 | 2 refus des droits au journal des résolveurs, 0 hors de `preuve-resolveurs` |
| L6 | `get secrets builds 200` : 1 ; hors de `builds`, seulement les 2 refus 403 de `preuve-resolveurs` |
| L7 | 4 lecteurs des Secrets de tout le cluster, liste inchangée |
| L8 | Pod des résolveurs créé le 06/11 à 13:38:02 UTC, 0 redémarrage (complément) |

Les huit prédictions sont tenues. L'espace d'essai est supprimé et il ne reste aucune ResolutionRequest d'essai dans `builds`. Le redémarrage du pod des résolveurs sous H5 n'est toujours pas mesuré.

## Additif du 07/11/2026, 10:41 UTC : étape `test5_refus` passée sous H1 à H5, T1 à T6 tenues

Passage lancé sur accord du propriétaire (« Ok » à « Je lance test5_refus ? »), de 10:40:57 à 10:40:59 UTC, avec `JOURNAL=preuves-h5`. C'est le premier passage de cette étape. Journal : [preuves-h5-test5_refus.log](../08-trust-plane/resultats/preuves-h5-test5_refus.log), 10 OK, 0 KO, code 0.

| Prédiction | Mesuré |
|---|---|
| T1 | Gabarit `sample-app` ; PipelineRun de la tête à `Succeeded` |
| T2 | HTTP 202 aux 4 livraisons |
| T3 | 1 refus `no X-Hub-Signature-256 header set`, 2 refus `payload signature check failed`, 3 refus des intercepteurs au total |
| T4 | Témoin accepté par les intercepteurs, puis écarté à la création avec `already exists`, même `eventID` |
| T5 | 0 PipelineRun pour le commit `1111…` et pour le commit jamais livré ; UID de la tête inchangé, `d1860207` |
| T6 | Image réelle inchangée, 22 enveloppes |

Les six prédictions sont tenues. Le test 5 est donc couvert sous H1 à H5 pour une livraison signée avec un autre secret et pour un corps modifié, refus qui n'avaient jamais été mesurés. La livraison non signée l'avait déjà été. Aucun fichier `autre.secret` ne reste sur disque.

## Additif du 07/11/2026, 10:51 UTC : étape `rattrapage_durci` passée sous H1 à H5, B1 à B7 et X1 tenues

Passage lancé sur accord du propriétaire (« Oui »), de 10:47:42 à 10:50:22 UTC, avec `JOURNAL=preuves-h5`. C'est le premier passage de cette étape. Journal : [preuves-h5-rattrapage_durci.log](../08-trust-plane/resultats/preuves-h5-rattrapage_durci.log), 18 OK, 0 KO, code 0. Un complément à la main, en lecture seule, y est ajouté pour B7. X1 a son propre relevé, [resultats/mesures-reelles-x1.log](resultats/mesures-reelles-x1.log).

| Prédiction | Mesuré |
|---|---|
| B1 | PipelineRun de la tête créé par `declencheurs:rattrapage` : une création, en 201, label d'origine `rattrapage`. C'est la première création réelle par le rattrapage depuis `h5_deny` |
| B2 | `Succeeded` en 59 s ; `construire` sous Kata sur sc-build ; digest `3a7ca1b1…` ; spec identique à `j7-sample-app`, bundle masqué ; trois TaskRuns `TrustedResourcesVerified=True` |
| B3 | Une seule ligne `CREE` dans les passages depuis la reprise |
| B4 | Chains signe les trois TaskRuns ; enveloppes 22 → 24 |
| B5 | Porte `true`, aucune violation, contrôle 9 à 24/24, VSA 1/1 ; provenance la plus récente : ce PipelineRun (`474b3f60`) |
| B6 | Aucune anomalie entre exécutions et enveloppes, au départ comme à la fin |
| B7 | CronJob repris (`suspend=false`) ; les passages de 10:49 et 10:50 UTC s'arrêtent à `PRESENT` (complément) |
| X1 | `KyvernoRefusAnormaux` inactive dans Prometheus et absente d'Alertmanager ; aucune série `ALERTS` sur 35 min ; 0 refus Kyverno à l'admission sur la fenêtre, avec 55 séries du compteur collectées |

Les huit prédictions sont tenues. Le chemin 2 de la bascule, la création par le rattrapage, est maintenant mesuré sous H1 à H5. Un seul `CONSTAT` au journal, hors prédictions B : `poc-images` a réécrit une fois le manifeste de l'image, qui existait déjà. Le même compte, 1, apparaît à R4 ([preuves-h5-r4-construction_durcie.log](../08-trust-plane/resultats/preuves-h5-r4-construction_durcie.log)) et à la construction de S1. Le verdict porte l'avertissement `trusted_task.tagged` (1), comme à R4.

Les quatre mesures réelles de `mesures-reelles-predictions.md` sont passées : 109 OK, 0 KO, 29 prédictions sur 29 tenues. Toujours non couverts : le redémarrage des VM et celui du pod des résolveurs, `decision3`, `enveloppes`, `reglec`, `attseule`, `controle6`, `controle7`, `temoins_scan`, le test 6 sous limites et `intercepteurs`. L'étape `test5` elle-même reste arrêtée par `gabarit_essai`. Les deux refus qui lui manquaient, l'autre secret et le corps modifié, sont couverts par `test5_refus`.

## Additif du 07/11/2026, 11:34 UTC : redémarrage des trois VM sous H1 à H5, V1 à V5 tenues

Passage lancé sur accord du propriétaire (« Oui les 2 »), de 11:20:38 à 11:32:38 UTC, avec `DISTRO=rke2`. Les journaux que le script écrase ont d'abord été archivés tels qu'au commit 8c98313 (`*-avant-redemarrage-h5.log`, commit d834c13, `kata-temoin` ajouté ensuite). Journaux : [redemarrage-vm.log](../08-trust-plane/resultats/redemarrage-vm.log), 51 OK, 0 KO, code 0, avec un complément à la main en lecture seule ; [kata-reseau.log](../08-trust-plane/resultats/kata-reseau.log), 25 OK, 0 KO.

| Prédiction | Mesuré |
|---|---|
| V1, nœuds | Arrêt en 112 s, démarrage en 9 s, trois nouveaux `bootID` et `Ready` en 77 s. Aucun refus de `system:rke2-controller` dans l'audit depuis le démarrage |
| V2, confiance | Kyverno prêt et refusant à la sonde dès le premier essai ; OpenBao scellé, puis descellé ; même clé Transit, signature d'avant vérifiée ; TSA relancé, jeton OpenBao au 4e essai, jeton témoin vérifié et refusé sur un autre contenu et sur une autre CA |
| V3, Chains | Pod recréé et prêt ; `identifiants` lit les identifiants Zot au 1er essai et finit par « jeton révoqué » |
| V4, Kata | Runtime rechargé par containerd sur sc-build, pod témoin admis, noyau de l'invité `6.18.56` |
| V5, réseau | 25 OK, mêmes constats qu'avant, adresses mises à part : aucune fenêtre en 3 essais runc et Kata, 15 flux `INVALID_SOURCE_IP` pour l'adresse usurpée, trois autres sources refusées, aucun paquet de `203.0.113.10` sur `enp1s0` |

Les cinq prédictions sont tenues, V1 et V5 comprises, qui étaient de confiance moyenne. Les CronJobs `horodatage` et `rattrapage` réussissent un passage après le retour du TSA.

**Non prédit, relevé en complément.** Le passage `horodatage-29900844`, créé à 11:24:04 UTC avant le descellement, échoue : son conteneur `identifiants` sort en erreur à 11:24:37, OpenBao étant encore scellé. Les passages suivants réussissent. Je n'ai pas vérifié s'il avait des enveloppes à traiter. Seuls refus de l'audit depuis le démarrage : 13 `get pods` de `system:node:sc-build` en 403, sur les pods de mesure de `kata.sh` dans `builds`. C'est la même forme que les 403 de nœud déjà relevés à R4 sur `helper-pod`, et la cause exacte n'est toujours pas établie. Aucun 422, aucun refus de `ValidatingAdmissionPolicy`. `KyvernoRefusAnormaux` reste inactive. Prometheus compte 1 refus Kyverno sur 15 min, que j'attribue à la sonde du script sans l'avoir apparié.

**Complément du 07/11/2026, 11:39 UTC.** Vérifié depuis dans [redemarrage-vm.log](../08-trust-plane/resultats/redemarrage-vm.log) : le passage en échec s'est arrêté à la connexion à OpenBao, `horodater` n'a jamais démarré. Le dernier passage relu, `horodatage-29900859`, compte 79 enveloppes : 0 à horodater, 77 déjà horodatées, et les 2 refus et l'anomalie des témoins de J6 (`essai-j6-autre-cle`, `essai-j6-autre-sujet`, `essai-j6-att-illisible`). Aucune enveloppe n'est restée sans horodatage, celles de `enveloppes` et `decision3` comprises.

**Pod des résolveurs.** Il n'a pas été recréé : même pod, créé le 06/11 à 13:38 UTC, conteneur relancé à 11:23:33 UTC (1 redémarrage). Le démarrage réel d'un nouveau pod des résolveurs reste non mesuré. La jonction d'un nouveau nœud aussi.

## Additif du 07/11/2026, 11:36 UTC : étapes `enveloppes` et `decision3` passées sous H1 à H5, E1 à E5, D1 à D5 et X2 tenues

Passages lancés sur accord du propriétaire (« Oui les 2 »), après le redémarrage des VM, avec `JOURNAL=preuves-h5` et `PIPE_ESSAI` (bundle `sample-app-essai@sha256:c5194859…`, lu sur `j6-porte-en-service`). Prédictions committées avant, au commit d834c13. Journaux : [preuves-h5-enveloppes.log](../08-trust-plane/resultats/preuves-h5-enveloppes.log), 11:34:51 à 11:35:21 UTC, 12 OK, 0 KO ; [preuves-h5-decision3.log](../08-trust-plane/resultats/preuves-h5-decision3.log), 11:35:33 à 11:36:22 UTC, 15 OK, 0 KO ; relevé [resultats/mesures-reelles-x2.log](resultats/mesures-reelles-x2.log).

| Prédiction | Mesuré |
|---|---|
| E1 | Code 0, 30 s |
| E2 | Départ sans anomalie : 31 couvertes, 8 en échec de signature, 20 sans sujet |
| E3 | `ABSENTE` puis `SUJET_NON_SIGNE`, chacune seule anomalie |
| E4 | Témoin signé par Chains avec les identifiants injectés : TaskRun et PipelineRun couverts ; tag réécrit : `ABSENTE`, puis `DOUBLE`, puis tag remis sans anomalie |
| E5 | Fin sans anomalie, 31 couvertes ; image réelle inchangée, 24 enveloppes, provenance `474b3f60` |
| D1 | Configuration en service identique au dépôt (`5806ba5c…`) |
| D2 | Tag neuf créé par `poc-build`, déplacement refusé en 403 (journal de Zot), `poc-ecriture` le déplace, `poc-build` le déplace de nouveau après remise |
| D3 | TaskRun `signed=true` ; PipelineRun `signed=failed`, `retries=3` ; 5 PUT `.att` refusés en 403 ; une enveloppe dans `.att`, celle du TaskRun ; 7 signatures Transit (2 + 5). Mêmes chiffres que le 06/11 |
| D4 | PipelineRun en échec `SUJET_NON_SIGNE`, seule anomalie ; configuration d'origine remise et vérifiée ; CronJobs repris ; exécutions purgées ; fin sans anomalie |
| D5 | Image réelle inchangée, 24 enveloppes ; 49 s |
| X2 | `KyvernoRefusAnormaux` inactive dans Prometheus et absente d'Alertmanager, aucune série `ALERTS` ni refus Kyverno sur 10 min ; Zot `active`, `suspend=false` pour les deux CronJobs, aucun PipelineRun en cours |

Les onze prédictions sont tenues. C'est le premier passage de ces deux étapes après la bascule, S1 et H1 à H5. Le refus du droit `update` par Zot tient toujours avec les identifiants de Chains lus dans OpenBao. Bornes de X2 : le relevé est pris 16 s après la fin de `decision3`, un refus des toutes dernières secondes pourrait ne pas encore être collecté ; et le compteur ne présente plus que 17 séries contre 55 à X1, les pods de Kyverno ayant redémarré avec les VM.

Toujours non couverts sous H1 à H5 : `reglec`, `attseule`, `controle6`, `controle7`, `temoins_scan`, le test 6 sous limites, `intercepteurs`, l'étape `test5` complète, le démarrage d'un nouveau pod des résolveurs, la jonction d'un nœud et le saut d'un passage manqué du scan.

## Additif du 07/11/2026, 12:35 UTC : étapes de la porte passées sous H1 à H5, sauf `attseule` en attente de confirmation

Passages lancés sur accord du propriétaire (« Les 5 »), avec `JOURNAL=preuves-h5`, sans `PIPE_ESSAI`. Prédictions committées avant, au commit 3478505. Elles corrigent le tableau soumis au propriétaire : `attseule` écrit un témoin permanent dans `essais-j8/test7`, et attend donc une confirmation. Elle n'a pas été passée.

Journaux :
- [preuves-h5-controle6.log](../08-trust-plane/resultats/preuves-h5-controle6.log), 12:30:38 à 12:31:04 UTC, 9 OK, 0 KO ;
- [preuves-h5-controle7.log](../08-trust-plane/resultats/preuves-h5-controle7.log), 12:31:04 à 12:31:31 UTC, 12 OK, 0 KO ;
- [preuves-h5-reglec.log](../08-trust-plane/resultats/preuves-h5-reglec.log), 12:31:31 à 12:32:40 UTC, 6 OK, 0 KO ;
- [preuves-h5-temoins_scan.log](../08-trust-plane/resultats/preuves-h5-temoins_scan.log), 12:32:53 à 12:34:40 UTC, 16 OK, 1 KO prédit, code 1 ;
- relevé [resultats/mesures-reelles-x3.log](resultats/mesures-reelles-x3.log).

| Prédiction | Mesuré |
|---|---|
| C6-1 | ConfigMap `porte` réappliquée, identique aux fichiers versionnés, clé de VSA `578dd771…` |
| C6-2 | C1 `true\|\|trusted_task.tagged`, contrôle 9 `ok` (24/24, 61 bundles), contrôle 6 `ok\|1/1` |
| C6-3 | C2 en refus, `0/0 VSA` ; C3 : ec et contrôle 9 inchangés, contrôle 6 en refus pour le seuil de signatures |
| C6-4 | 0 KO, 26 s |
| C7-1 | ConfigMap identique, clé du scanner `1656a3fa…` |
| C7-2 | C1 admise, contrôle 7 `ok\|4 énoncé(s)`, Job réussi ; C2 en refus par `scan.scan_present`, Job en échec ; C3 en refus pour le seuil de signatures |
| C7-3 | 0 KO, code 0, 27 s |
| R1 | Provenance `474b3f60` reprise (48 818 octets) ; trois témoins neufs, vérifiés avec la clé jetable et refusés avec celle de Chains |
| R2 | Image réelle sans source : `source_code_reference_provided` seule, `porte.construction_kata` parmi les succès |
| R3 | `intacte` : R2 plus `subject_build_task_matches` et `porte.fermeture_plateforme` ; `sans-kata` et `runc` : `intacte` plus `porte.construction_kata` seule. Mêmes motifs que le 06/11, mais le TaskRun nommé est maintenant `sample-app-6391fd43…-construire` (provenance du rattrapage) et non plus `j7-sample-app-construire` |
| R4 | Ligne CONSTAT du succès à vide |
| R5 | 0 KO, code 0, 69 s ; image réelle inchangée (24 enveloppes, `474b3f60`) ; 15 tags dans `essais-j8/regle-c` |
| T1 | 14 cas sur 15 comme `g6-temoins.tsv` |
| T2 | `futur` admis, 1 énoncé ; le script compte 1 écart et sort en code 1, comme prédit |
| T3 | `g6-reelle` à `true\|\|ok\|ok\|ok`, `porte-temoin` retirée, 107 s |
| X3 | `KyvernoRefusAnormaux` inactive dans Prometheus et absente d'Alertmanager ; aucune série `ALERTS` ni refus Kyverno sur 10 min ; configuration de Zot `5806ba5c…` identique au dépôt ; `suspend=false` pour les trois CronJobs ; aucun PipelineRun en cours ; `porte-temoin` absente |

15 prédictions sur 16 sont tenues. R3 l'est sur les violations, mais pas sur le libellé du motif : la prédiction disait « mêmes motifs que le 06/11 » sans tenir compte du TaskRun nommé, qui suit la provenance reprise en R1. C'est le premier passage de ces quatre étapes après H1 à H5. Les Jobs de la porte, la ConfigMap `porte-temoin` et les écritures de `poc-ecriture` dans Zot sont admis. Leurs verdicts (succès, violations, contrôles 6, 7 et 9) sont ceux du 06/11, avant H1.

Constats :
- Les durées tombent à 26 à 107 s, contre 3 à 10 min le 06/11. Le champ 6 de `VERDICT`, durée du conteneur `ec` (`politique.sh:1325`), passe de 61 s (31 s sans source) à 1 ou 2 s : c'est lui qui fait l'écart. La cause de cette baisse n'a pas été relue.
- `chrono.tsv` n'a pas de ligne « `temoins_scan` fait » : `lancer` s'arrête sur le code 1, comme prédit.
- `etape_controle6` ne finit pas par `[ "$ko" = 0 ]` : un écart n'y changerait pas le code de sortie. Ses KO se comptent dans le journal. Le script n'est pas modifié.

Bornes :
- La branche « scan daté du futur » de `scan.rego` n'est plus couverte par les témoins de G6. Le témoin `futur` du 06/11 est daté une heure après sa pose : depuis, il est devenu un scan récent. La couvrir de nouveau demande `plateforme.sh g6_temoins`, qui écrit dans Zot et réécrit `g6-temoins.tsv` et `g6-temoin-cle-publique.pem` ; il faut l'accord du propriétaire.
- X3 est relevé 8 s après la fin : un refus des toutes dernières secondes pourrait ne pas encore être collecté. Le compteur présente 21 séries (17 à X2).

Toujours non couverts sous H1 à H5 : `attseule` (en attente de confirmation), le test 6 sous limites, `intercepteurs`, l'étape `test5` complète, le démarrage d'un nouveau pod des résolveurs, la jonction d'un nœud et le saut d'un passage manqué du scan.

## Additif du 07/11/2026, 12:46 UTC : étape `attseule` passée sous H1 à H5, A1 à A3 tenues

Passage lancé sur confirmation du propriétaire (« attseule, puis push si tout tient »), avec `JOURNAL=preuves-h5`. Prédictions committées avant, au commit 3478505. Journal : [preuves-h5-attseule.log](../08-trust-plane/resultats/preuves-h5-attseule.log), 12:45:34 à 12:45:47 UTC, 3 OK, 0 KO ; relevé en complément de [resultats/mesures-reelles-x3.log](resultats/mesures-reelles-x3.log), à 12:45:58 UTC.

| Prédiction | Mesuré |
|---|---|
| A1 | Témoin neuf `essais-j8/test7@sha256:c115f910…`, sans tag `.sig` ; 33 tags contre 32 avant, le tag `.att` seul en plus |
| A2 | Refusé : `builtin.image.signature_check`, `porte.fermeture_plateforme`, `porte.image_signature` et `subject_build_task_matches`, comme le 06/11 ; `builtin.attestation.signature_check` absent |
| A3 | 0 KO, code 0, 13 s ; image réelle inchangée (24 enveloppes, `474b3f60`) |
| X3, complément | `KyvernoRefusAnormaux` inactive et absente d'Alertmanager, aucun refus Kyverno sur 5 min, Zot `5806ba5c…` inchangé, CronJobs actifs, aucun PipelineRun en cours, `porte-temoin` absente |

Les cinq étapes de la porte sont passées sous H1 à H5, avec 18 prédictions tenues sur 19 (R3 tenue sur les violations, pas sur le libellé du motif). Durée du conteneur `ec` : 1 s, comme dans les quatre autres étapes.

Toujours non couverts sous H1 à H5 : le test 6 sous limites, `intercepteurs`, l'étape `test5` complète, le démarrage d'un nouveau pod des résolveurs, la jonction d'un nœud, le saut d'un passage manqué du scan, et la branche « scan daté du futur » de `scan.rego` (témoins de G6 à refaire).

## Additif du 07/11/2026, 12:55 UTC : cause de la baisse de durée de `ec`, déjà mesurée le 06/11

Correction de l'additif de 12:35, sans réécriture : la phrase « La cause de cette baisse n'a pas été relue » est fausse. La cause est mesurée dans ce README (additif du 06/11/2026, 19:07 UTC, M1) : depuis le commit c299ce8, `SIGSTORE_REKOR_PUBLIC_KEY` est définie dans le conteneur `porte` de `porte-job.yaml`. Elle évite à `ec` v0.10.42 l'appel à `cosign.TrustedRoot()` vers le TUF public, injoignable depuis la porte. Sur l'image réelle, ce conteneur est passé de 61 s à 1 s.

Relecture des journaux archivés (champ 6 de `VERDICT`), sans action sur le cluster :

| Journaux | Champ 6 |
|---|---|
| `preuves-reglec-premier-passage.log` (31/10), `preuves-test8-premier-passage.log` et `-deuxieme-passage.log` (01/11) | 30 ou 31 s |
| `preuves-reglec.log`, `preuves-attseule.log`, `preuves-test8.log`, `preuves-controle6.log`, `preuves-controle7.log`, `preuves-temoins_scan.log` (06/11, 15:40 à 16:58, heure locale des fichiers) | 61 s, 31 s pour `reglec-en-service`, `c6-sans-vsa` et `c7-sans-scan` |
| `preuves-h5-test8.log` (06/11, après c299ce8) et les cinq journaux `preuves-h5-*` des étapes de la porte (07/11) | 1 ou 2 s |

L'écart entre 31 et 61 s avant c299ce8 n'est pas expliqué ici et ne change aucun verdict. Le point est retiré de la liste des points non couverts.

## Additif du 07/11/2026, 14:07 UTC : test 6 et `intercepteurs` passés sous H1 à H5, N1 à N7 et I1 à I6 tenues ; noyau des hôtes mis à jour par `unattended-upgrades`

Accord du propriétaire : « 3 », pour les deux étapes. Prédictions committées avant, au commit a0a44bc ([mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 13:37 UTC). Lancées avec `JOURNAL=preuves-h5`, `T6_FERMES="Supervisor Etcd"` pour le test 6.

Journaux :
- [preuves-h5-test6.log](../08-trust-plane/resultats/preuves-h5-test6.log) : de 14:03:10 à 14:04:43 UTC, 0 KO, code 0 ;
- [preuves-h5-intercepteurs.log](../08-trust-plane/resultats/preuves-h5-intercepteurs.log) : de 14:04:52 à 14:06:35 UTC, 0 KO, code 0 ;
- [noyau-hotes-releve.log](resultats/noyau-hotes-releve.log), à 14:07:28 UTC.

`preuves-test6.log` (06/11, cité par H4b) et `preuves-intercepteurs.log` (02/11) ne sont pas écrasés.

| Prédiction | Mesuré |
|---|---|
| N1, admission | Les deux TaskRuns sont admis sous `Deny`, pods Kata privilégiés compris. Aucun événement `PolicyViolation` depuis 14:03 UTC |
| N2, bundles | `preuve-test6-contre@sha256:6c39ea60…` et `preuve-test6-test@sha256:48115c5c…`, neufs. `TrustedResourcesVerified=True` pour les deux |
| N3, adresse usurpée | `10.42.1.250`, contrôlée inutilisée avant chaque passage |
| N4, garde-fous | Labels attendus, pods sous Kata (invité 6.18.56), eth0 à l'IP du pod, adresse ajoutée puis retirée |
| N5, contre-épreuve | Comme le 06/11 : Zot, Forgejo et les deux voies de l'API joignables ; Supervisor et Etcd refusés par le pare-feu d'hôte ; `nc -s` joint Zot ; 3 SYN sortis par `192.168.161.12` ; 3 flux `INVALID_SOURCE_IP` pour Zot et 3 pour Forgejo |
| N6, `construire-image` | 7 destinations refusées, 6 flux `POLICY_DENIED EGRESS` chacune, l'API par le service sous `192.168.161.11:6443`. `nc -s` refusé. 3 flux `INVALID_SOURCE_IP` pour Zot et 3 pour Forgejo. 0 paquet sur `enp1s0` |
| N7 | 0 KO en 93 s. Image réelle inchangée : 24 enveloppes, `474b3f60`. Aucune alerte dans Alertmanager ni dans `ALERTS` de Prometheus à 14:06:50 UTC |
| I1, liaison | Conforme à l'attendu |
| I2, liaison retirée | `can-i` à `no`. Nouveau pod `…-5fccdd7c6c-q49tj` non prêt après 90 s. Refus « at the cluster scope » dans son journal |
| I3, admission | Les deux pods neufs sont admis sous `Deny`. C'est la première admission d'un pod de ce déploiement sous `Deny`. Pod final `…-6894848d5c-xh998`, sur `sc-confiance` |
| I4, ancien pod | Trois lignes « 1 old replicas are pending termination » au second redémarrage, comme le 02/11. Aucune livraison pendant la fenêtre : la continuité du service n'est pas mesurée |
| I5, liaison remise | `can-i` à `yes`, pod prêt, 0 refus dans son journal. `caBundle` des cinq ClusterInterceptors inchangé pendant l'étape, de longueur 1448 (1456 sous k3s le 02/11) |
| I6 | 0 KO en 103 s. Conclusion inchangée : la limite des intercepteurs est gardée |

13 prédictions tenues sur 13.

**Additif du 07/11/2026, 17:07 UTC : source de « Aucun événement `PolicyViolation` depuis 14:03 UTC » (N1) remplacée, N1 toujours tenue.** Revue des comptes archivés de `PolicyViolation` et de `FailedCreate`, proposée au propriétaire après le constat sur la durée de vie d'une heure des Events (additif de 16:53 UTC aux prédictions), puis menée sur « continue » sans qu'il l'ait validée : aucune fenêtre ne dépasse une heure, de quelques secondes à 52 minutes, dont les 32 événements de H2 en 4 minutes 20 ; seule exception, l'essai à sec de 16:53 UTC, qui se déclare lui-même non probant. Les autres lecteurs d'Events (`cilium.sh`, `stockage.sh`) ne sont pas revus. Deux défauts touchent la phrase de N1, et non l'admission des deux TaskRuns, prouvée par [preuves-h5-test6.log](../08-trust-plane/resultats/preuves-h5-test6.log) :
- le compte de 14:06:50 UTC n'a jamais été archivé, il n'existe que dans la session ;
- son filtre portait sur `.lastTimestamp` seul. Kyverno 1.19.2, la version du contrôleur en service, crée ses Events par `events.k8s.io/v1` et ne remplit que `eventTime` (source `pkg/event/controller.go` lu) ; Kubernetes recopie `deprecatedLastTimestamp`, vide, dans `lastTimestamp` (source `pkg/apis/events/v1/conversion.go` lu). Un tel Event a donc `lastTimestamp` nul, et jq rend 0 pour `null >= "…"` (essayé). Le compte valait 0 quoi qu'il arrive. Ce point repose sur le source : aucun Event de Kyverno n'existait à 17:02 UTC pour l'observer.

Les autres filtres archivés lisent `(.lastTimestamp // .eventTime)` ou `.metadata.creationTimestamp` et ne sont pas touchés, W7 et le contre-relevé du 08/11 compris.

Remplacement, en lecture seule, journal [resultats/n1-refus-audit.log](resultats/n1-refus-audit.log) (deux passages précédents avec un compte des refus de Kyverno mal filtré : celui de 17:05:40 UTC, affiché en partie et jamais archivé, et celui de 17:05:51 UTC, archivé dans `n1-refus-audit-premier-passage.log`) :
- audit de l'API, de 14:03:00 à 14:07:00 UTC : 1990 requêtes, aucune 400 ni 422, aucun message « denied the request ». Les 16 réponses 403 sont des refus de droits : le nœud `sc-build` sur les pods de test 6, et le compte des intercepteurs pendant I2. Témoin : le refus en dry-run de `sonde-kyverno` à 11:24:46 UTC est bien à l'audit, en 400, avec « denied the request » ;
- métrique `kyverno_admission_requests_total{request_allowed="false"}` : après le redémarrage des VM, une seule série, celle de la sonde, à 1 de 11:25:15 à 14:10 UTC, aucune autre série à 14:03 ni à 14:07 UTC.

Aucun refus d'admission de Kyverno dans la fenêtre de N1. Ne couvre pas les violations du scan d'arrière-plan, que ni l'audit (Events en `level: None`) ni cette métrique ne comptent. « Aucune alerte […] à 14:06:50 UTC » de N7, non archivée non plus, est relue dans Prometheus : 0 série `ALERTS` de 14:03 à 14:07 UTC, données présentes à 14:06:50 UTC (9 séries `up` à 1), historique d'alertes lisible (`ChainsEchecSignature`, `KyvernoRefusAnormaux` et d'autres le 06/11, `OpenBaoScelle` et `CollecteEnPanne` en pending à 11:25 UTC le 07/11, une série `ChainsEchecSignature` en firing avec des points jusqu'au 07/11 à 11:46 UTC). L'état d'Alertmanager à cette heure n'est plus relisible.

**Additif du 07/11/2026, 17:16 UTC : autres lecteurs d'Events revus, aucun défaut.** L'additif de 17:07 UTC ne nommait que `cilium.sh` et `stockage.sh` parmi les autres lecteurs. Les scripts en contiennent sept qui passent par kubectl. Ils ont été revus en statique sur « continue », sans validation du propriétaire. Rien n'a été lancé. Le collecteur d'Events de la 19b (Alloy) n'est pas revu :
- `cilium.sh:173` à 0 Pulling, tenu : chacun des quinze journaux archivés affiche juste avant « Pulled : 22 », donc des Events vivants à la lecture ;
- `stockage.sh:234`, `preuves.sh:3147` et `essais-h5-scan.sh:47` : affichages sans `attendu` ;
- `journalisation.sh:70-71` : compte instantané, prédit comme tel en L1 ;
- `preuves.sh:3294` (W6 du 08/11) : un CronJob suspendu sort de `syncCronJob` avant le calcul du planning (source de `v1.35.9`, ligne 514). Un `MissSchedule` ne peut donc naître qu'à la reprise, dans la fenêtre de 30 s. Le nettoyage des Jobs (`cleanupFinishedJobs`) tourne lui sans garde et peut émettre `SuccessfulDelete`. Mais l'état relevé à 16:28 UTC (deux Jobs réussis pour une limite de 3, aucun actif) exclut toute suppression à la reprise. Ce point a été corrigé à 17:19 UTC, avant tout push ;
- `scan-saut-reprise-verif.sh:41` : se déclare déjà non probant.

Détail dans [resultats/mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md). La limite de débit des Events, question posée par l'additif H1 du 06/11, n'est pas traitée ici.

**Additif du 07/11/2026, 17:32 UTC : `ChainsEchecSignature` du 06 au 07/11, deux épisodes, tous deux dus aux essais négatifs voulus de la 08.** Relevé en lecture seule sur accord du propriétaire (« Oui, examine »), dans [resultats/chains-echec-signature.log](resultats/chains-echec-signature.log). Sources : Prometheus, récepteur local, journaux du contrôleur Chains (pod en service ; ancien pod par Loki), annotations des exécutions. Deux points de la première rédaction ont été corrigés à 17:39 UTC, avant tout push, après relecture du conseiller : l'attribution du 06/11 et « aucun autre échec ».
- Il n'y a pas eu d'épisode de 20 h, mais deux épisodes de 8 et 10 points. Ma lecture du 07/11 (« active du 06/11 15:34 au 07/11 11:46 UTC ») était fausse ; l'additif de 17:07 UTC, lui, était exact.
- **06/11, de 15:34 à 15:41 UTC.** La collecte de Chains reprend à 15:32, avec des compteurs déjà à 24 et 23 (`payload_creation`) et à 5 (`storage`), constants jusqu'à 18:39. L'alerte vient du seul volet « série apparue ». Loki retrouve les 52 échecs du contrôleur démarré à 13:48:49 :
  - 47 en `payload_creation` (« expected imageID to be separable by @ »), sur 8 exécutions jamais lancées des essais négatifs voulus : `j6-sans-drapeau` et `j6-sans-restriction-enforce`, refusés par PodSecurity, `j7-sample-app-etiquette`, annulé, `j7-sample-app-sans-kata`, refusé, et leurs TaskRuns ;
  - 5 en `storage` : les PUT `.att` refusés de decision3 à 15:14 UTC.
- **07/11, de 11:37 à 11:46 UTC** (récepteur : firing à 11:36:07, resolved à 11:46:07). Il s'agit des 5 PUT `.att` refusés de `preuve-decision3`, entre 11:36:01 et 11:36:14 : l'effet voulu de decision3 (D3 tenue). **Constat non prédit : l'alerte elle-même.** X2 ne portait que sur `KyvernoRefusAnormaux`.
- Les compteurs d'échec ne montent pas en dehors de ces deux épisodes. L'échec en mode ouvert n'est pas compté. `ChainsMarqueSansSignature` n'a qu'un point pending, le 06/11 à 18:30, et c'est un artefact de collecte : +2 marqués et +2 signatures créées aux mêmes minutes. Elle n'est jamais passée en firing.
- Le 06/11, le récepteur a bien reçu les notifications (firing à 15:32:47, resolved à 15:41:47, d'après Loki). Ces lignes manquent dans le journal local de `sc-stockage`, qui ne remonte qu'au 06/11 à 17:03 ; le mécanisme de cette perte n'est pas établi. **Risque pour W8 (09/11)** : `scan-saut-resolution.sh` lit ce journal local, donc des firing du 08/11 pourraient manquer. Ce serait un CONSTAT, pas un KO.
- Aucune affirmation archivée n'est prise dans les deux fenêtres.
- C'est la limite déjà écrite dans `alertes.yml` : les compteurs de Chains n'ont pas d'étiquette d'exécution, et chaque passage de decision3, de j6 ou de j7 déclenche A2. Toute suite (prédire A2 à chaque essai négatif, ou autre) relève du propriétaire.

**Additif du 07/11/2026, 17:59 UTC : W8 lit aussi le récepteur dans Loki.** Sur accord du propriétaire (« Oui, prépare-le »), `scan-saut-resolution.sh` compare les notifications de `ScanEnRetard` du journal local de `sc-stockage` à celles de Loki, lues par l'auditeur à travers Grafana. Les OK et KO prédits sont inchangés, et un écart entre les deux sources est un CONSTAT. Essai à sec sur `ChainsEchecSignature` : les lignes du 06/11 perdues localement sont retrouvées dans Loki ([resultats/scan-saut-w8-loki-sec.log](resultats/scan-saut-w8-loki-sec.log)).

**Additif du 07/11/2026, 18:04 UTC : A2 prédite dans les étapes qui font échouer Chains.** `ChainsEchecSignature` (A2) est désormais annoncée dans les prédictions affichées par les trois étapes où ces échecs voulus ont été constatés le 06 et le 07/11, sur accord du propriétaire (« Oui, ajoute-la ») :
- `preuves.sh decision3` : `storage`, une hausse par PUT `.att` refusé ;
- `politique.sh restreint` (J6) : `payload_creation` sur `j6-sans-restriction-enforce` et `j6-sans-drapeau`, jamais lancés ;
- `construction.sh construire` (J7) : `payload_creation` sur les PipelineRuns sans Kata et à étiquette, et sur leurs TaskRuns `construire`.

La prédiction : firing jusqu'à environ 10 min après le dernier échec, puis firing et resolved au récepteur local. Dans un rejeu complet, si Prometheus ne collecte pas encore Chains, l'alerte part à la première collecte, comme le 06/11 à 15:32 UTC. La brique 19 annonçait déjà, dans son README, que chaque rejeu de la 08 déclencherait A2. Il manquait la prédiction dans les étapes elles-mêmes : c'est ce qui a manqué à X2 le 07/11. Seuls des `echo` sont ajoutés, aucun contrôle ne change. Rien n'a été lancé. Base : [chains-echec-signature.log](resultats/chains-echec-signature.log) de la 08c.

**Cas non déterminé, et limite d'A2 (corrigé à 18:07 UTC, avant tout push, après relecture du conseiller).**
- **Les quatre TaskRuns de l'étape `taches` de J6** : `j6-non-signee`, `j6-modifiee`, `j6-autre-cle` et `j6-hors-politique`, tous en `signed=failed` avec `retries=3`.
  - Ils ont été créés de 13:47:48 à 13:48:18 UTC le 06/11. L'étape `chains` de J6 a ensuite redémarré le contrôleur (patch du déploiement, de 13:48:48 à 13:48:50 UTC), avant toute collecte.
  - Loki n'a aucune ligne de l'ancien pod, donc le type de leur échec est inconnu.
- **Ce que dit le source de Chains v0.29.9** (`pkg/chains/signing.go`, `recordError`) : seuls les échecs sur les artefacts TaskRun et PipelineRun font monter les compteurs. Un échec limité aux artefacts OCI (signature d'image) mène à `signed=failed` (`HandleRetry`, puis `MarkFailed`) sans hausse d'aucun compteur.
- **Conséquences :**
  - lancée seule, l'étape `taches` peut déclencher A2 ou non : ce n'est pas prédit ;
  - dans un rejeu complet, le redémarrage de l'étape `chains` l'efface ;
  - plus largement, d'après le source et sans l'avoir observé, A2 ne voit pas un échec de signature limité à l'image, et `ChainsMarqueSansSignature` non plus, puisque l'objet n'est pas marqué signé.

**Additif du 07/11/2026, 18:18 UTC : collecteur d'Events de la 19b (Alloy) revu, aucun défaut.** Revue statique menée sur « continue », sans validation du propriétaire, rien lu dans le cluster, Zot ou les VM ; c'était le lecteur laissé de côté à 17:16 UTC. Source d'Alloy v1.21.3 (f2108cd, version installée sur `sc-stockage` au dernier rejeu, `rejeu-rke2.log` du 06/11 à 15:31 UTC ; `constat-grpc-relais.log` du 03/11 cité d'abord, corrigé à 18:20 UTC, avant tout push) :
- les Events de Kyverno, datés par `eventTime` seul, sont collectés : Alloy se rabat sur `EventTime` quand `lastTimestamp` est nul ;
- la durée de vie d'une heure ne touche pas ce qu'Alloy a déjà écrit dans Loki ;
- le témoin sans horodatage du deuxième passage L4 est ignoré par le source, ce qui explique le « jamais collecté » archivé ;
- le témoin J4 lit de `now-15m` à `now` : sa date tronquée à la seconde ne le fait pas sortir de la fenêtre.

Limites lues dans le source, non observées : après un redémarrage d'Alloy, des Events peuvent être perdus ou doublés (position figée au démarrage) ; un arrêt plus long qu'une heure perd les Events expirés. Lire les Events dans Loki plutôt que par kubectl éviterait la TTL : possible, à décider avec le propriétaire. Détail : [revue-alloy-evenements.log](../19b-journalisation/resultats/revue-alloy-evenements.log).

**Additif du 07/11/2026, 19:56 UTC : perte du journal local de `sc-stockage`, mécanisme probable lu dans le source de journald.** Revue statique menée sur « continue », sans validation du propriétaire. Rien n'a été lu ni écrit dans le cluster, Zot ou les VM. Sources : les journaux archivés, l'image Debian en cache et systemd v257.13, la version de l'image.

Selon le mécanisme le plus probable, la perte était **glissante sous le plafond du premier démarrage** (fenêtre d'environ 18 h), puis **arrêtée** au plus tard au redémarrage du 07/11 à 11:22 UTC (corrigé à 19:59 UTC, avant tout push : « ponctuelle, pas glissante » contredisait le mécanisme) :
- journald fixe son plafond une fois, au démarrage du processus, à 10 % du système de fichiers ;
- au premier démarrage des VM, la racine de l'image n'était pas encore agrandie (2,874 GiB) : plafond d'environ 290 Mo, d'où la suppression des archives antérieures au 06/11 à 17:03 UTC ;
- le redémarrage du 07/11 à 11:22 UTC a levé ce plafond au plus tard, vers 10 % de 20 Go. Les 386,1 M occupés à 17:39 UTC dépassent ce que l'ancien plafond permettait (367,9 Mio au plus).

C'est lu dans le source et compatible avec les archives, sans être observé. Restent non relus : la version installée, les correctifs Debian, et l'ordre de growpart et du transfert du journal.

Prédictions écrites avant tout relevé :
- relecture du 08/11 : la tête du journal reste au 06/11 à 17:03:02 UTC ;
- W8b : « mêmes lignes », confiance haute si la tête ne bouge pas ;
- la lecture qui tranche (message de démarrage de journald, `dpkg-query`) demande l'accord du propriétaire.

Conséquences, sans action :
- un rejeu sur des VM neuves reproduit le plafond d'environ 290 Mo jusqu'au premier redémarrage ;
- depuis le 07/11, journald peut occuper jusqu'à environ 2,5 Go sur `sc-confiance`, sous réserve de garder 5 % de place libre, et non plus 282 Mo comme le supposait G7 de la 07a ;
- fixer `SystemMaxUse` toucherait les VM, à décider avec le propriétaire.

Détail : [revue-journald-stockage.log](resultats/revue-journald-stockage.log).

**Additif du 07/11/2026, 20:20 UTC : P1 et P2 lues sur `sc-stockage`, sur accord du propriétaire (« traite tout »).** Une session ssh en lecture seule, rien d'écrit sur la VM.
- P2 tenue : au redémarrage du 07/11 à 11:22:36 UTC, journald annonce un max de 1.9G (prédit : 1,8 à 2,0 G) pour 271.2M occupés. La version installée est `257.13-1~deb13u1`.
- P1, point intermédiaire : la plus vieille archive système n'a pas bougé (06/11 à 17:03:02 UTC) et l'occupation vaut 418.1M. P1 se juge le 08/11.
- Pour `journalctl`, l'entrée la plus ancienne date du 06/11 à 13:28:37 UTC. Par élimination d'après les noms des fichiers, elle est dans `user-1000.journal`, que journald ne supprime jamais (déduit, non lu). Cela expliquerait les lignes de 13 h à 16 h du démarrage -1.

Détail : [journald-stockage-p1p2.log](resultats/journald-stockage-p1p2.log).

**Décisions du propriétaire, 07/11/2026, écrites à 20:45 UTC.** La réponse « garde tes recommandations », reçue peu avant 20:44:42 UTC, retient les trois recommandations du message qui suivait le commit 2ed0290 :
- **`SystemMaxUse` : aucun changement avant le relevé W8 du 09/11.** Une limite vers 500 M nettoierait dès maintenant le journal de `sc-stockage` (418 M, environ 16 M/h) et emporterait les lignes que W8b relit. Après le 09/11, la seule raison de la reconsidérer est la marge disque de `sc-confiance` pour G7 : Loki reste la référence d'audit. Deux points restent non vérifiés : l'effet d'un redémarrage de journald sur les VM en service, et la levée du plafond du premier démarrage par une configuration posée par cloud-init.
- **A2 : limite acceptée.** Les compteurs d'échec de Chains v0.29.9 n'ont pas d'étiquette : les échecs voulus des essais négatifs ne se filtrent pas. Cette limite est écrite dans le commentaire de la règle et annoncée dans les prédictions des étapes depuis 0f5b964. Rien n'est changé dans Prometheus ni dans Alertmanager.
- **Events dans Loki : une passe dédiée après le 09/11, avec ses propres prédictions.** Ce n'est pas un simple remplacement : Loki garde une ligne par mise à jour d'Event (`journalisation.sh:391`), donc les comptes changent. Six lectures fondent un verdict sur des Events : `preuves.sh:3184`, `3238`, `3298` et `3304`, `durcissement.sh:270`, `cilium.sh:173`. Les lignes 3298 et 3304 tournent le 08/11 pendant la reprise : aucun script n'est touché avant la fin de W8.
- La relecture P1 du 08/11 n'a pas d'accord à ce stade : sans accord, P1 sera écrite « non relue ».

**Effet à connaître.** Le déploiement `tekton-triggers-core-interceptors` est à sa révision 4. `kubectl rollout undo` ne rend plus son état d'avant H5. Le retour de `h5_limites` passe par `--to-revision=1` ou par l'état sauvé dans `~/.cache/supply-chain-poc/08/travail/durcissement/h5-avant/`.

**Constat non prédit : le noyau des trois VM a changé sans décision.** `sc-build` était en `6.12.113+deb13-amd64` le 06/11 à 17:48 UTC (`preuves-test6.log`). Le relevé de 14:07 UTC donne `6.12.115+deb13.1-amd64` sur les trois VM. `unattended-upgrades` est actif sur les trois. Le 07/11, de 06:15 à 06:36 UTC, il a installé ce noyau, `apt` 3.0.4 et `vim`, sans redémarrer. Le redémarrage des VM de 11:20 UTC l'a chargé.

Conséquences :
- V1 à V5, le test 6 et les étapes passées depuis 11:22 UTC ont tourné sous ce noyau. Leurs résultats restent valables, mais ils ne comparent pas un même noyau avant et après H5.
- La règle « Épingle les versions » n'est pas tenue pour les paquets Debian des VM. Rien n'est changé ici : couper `unattended-upgrades` ou épingler le noyau est une action au niveau système des VM, qui demande l'accord du propriétaire.
- Le noyau de l'invité Kata reste `6.18.56`.

Toujours non couverts sous H1 à H5 : l'étape `test5` complète, arrêtée par `gabarit_essai` (ses refus sont couverts par `test5_refus`), le démarrage d'un nouveau pod des résolveurs, la jonction d'un nœud, le saut d'un passage manqué du scan et la branche « scan daté du futur » de `scan.rego`.

## Additif du 07/11/2026, 14:55 UTC : `test5_refus` étendue passée sous H1 à H5, T1 à T9 tenues

Passage lancé sur accord du propriétaire (« Oui » à « Je lance test5_refus étendue ? »), de 14:54:53 à 14:54:55 UTC, avec `JOURNAL=preuves-h5`. Extension choisie par le propriétaire (« B ») et prédictions committées avant, au commit `74c97e7` ([mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 14:43 UTC). Journal : [preuves-h5-test5_refus.log](../08-trust-plane/resultats/preuves-h5-test5_refus.log), 13 OK, 0 KO, code 0. Contrôles hors étape : [test5-refus-extension-hors-etape.log](resultats/test5-refus-extension-hors-etape.log).

**Journal écrasé.** Le passage de 10:40 UTC, cité par l'additif de 10:41 UTC et par la relecture de 14:29 UTC sous le nom `preuves-h5-test5_refus.log`, est maintenant dans [preuves-h5-test5_refus-premier-passage.log](../08-trust-plane/resultats/preuves-h5-test5_refus-premier-passage.log), copié avant le passage.

| Prédiction | Mesuré |
|---|---|
| T1 | Gabarit `sample-app` ; PipelineRun de la tête à `Succeeded`, UID `474b3f60` |
| T2 | HTTP 202 aux 5 livraisons |
| T3 | 1 refus `no X-Hub-Signature-256 header set`, 2 refus `payload signature check failed`, 3 au total |
| T4 | Témoin accepté par les intercepteurs, écarté à la création avec `already exists`, même `eventID` |
| T5 | 0 PipelineRun pour le commit `1111…` et pour le commit jamais livré ; UID de la tête inchangé |
| T6 | Image réelle inchangée, 24 enveloppes, provenance `474b3f60` |
| T7 | Rejeu à l'identique (même corps, même signature) : HTTP 202, accepté par les intercepteurs, écarté à la création sous son propre `eventID` ; 2 erreurs `already exists` au total |
| T8 | 0 ligne « interceptor stopped trigger processing » au journal de l'EventListener |
| T9 | Les 3 refus sont au journal du pod `…-6894848d5c-xh998`, seule réplique, 0 redémarrage ; témoin et rejeu atteignent la création. Au journal de l'EventListener, 4 lignes hors niveau `info`, toutes `already exists` (deux par livraison), 0 ligne `tls`, `x509` ou `certificate` |

Les neuf prédictions sont tenues. Hors étape : 0 événement `PolicyViolation` depuis 14:54 UTC, 0 alerte active dans Alertmanager. Aucun fichier `autre.secret` ne reste sur disque.

**Effet.** Le lien de l'EventListener vers les intercepteurs est mesuré après le redémarrage des VM et après l'étape `intercepteurs`. Le rejeu à l'identique et l'absence de la ligne de niveau debug sont mesurés sous H1 à H5.

**`test5` complète.** Toutes ses assertions ont maintenant une mesure sous H1 à H5 : le tableau de la relecture de 14:29 UTC ([mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md)), plus ce passage. Une seule différence reste : la création par une livraison valide est mesurée avec une livraison de Forgejo (R4), pas avec une livraison signée par le script. Le secret et l'intercepteur sont les mêmes. L'étape elle-même reste arrêtée par `gabarit_essai`. La retirer des non couverts est une décision du propriétaire, non prise.

Toujours non couverts sous H1 à H5 : l'étape `test5` complète (voir ci-dessus), le démarrage d'un nouveau pod des résolveurs, la jonction d'un nœud, le saut d'un passage manqué du scan et la branche « scan daté du futur » de `scan.rego`.

## Additif du 07/11/2026, 15:26 UTC : `test5` complète passée sous H1 à H5 par `test5_essai`, U1 à U7 tenues

Passage lancé sur accord du propriétaire (« Oui » à « Je lance test5_essai avec ces effets ? »), de 15:24:48 à 15:25:22 UTC, avec `JOURNAL=preuves-h5` et `PIPE_ESSAI` (`sample-app-essai@sha256:c5194859…`). Étape, effets et prédictions committés avant, au commit `0d8b112` ([mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 15:20 UTC ; vérification à sec : [test5-essai-sec.log](resultats/test5-essai-sec.log)). Journal : [preuves-h5-test5_essai.log](../08-trust-plane/resultats/preuves-h5-test5_essai.log), 20 OK, 0 KO, code 0. Contrôles hors étape : [test5-essai-hors-etape.log](resultats/test5-essai-hors-etape.log).

| Prédiction | Mesuré |
|---|---|
| U1 | Gabarit en service identique au rendu de `gabarit-sample-app.yaml` ; gabarit d'essai appliqué à 15:24:48 UTC |
| U2 | Toutes les assertions de `test5` tenues. 3 refus de l'intercepteur github. Témoin `sample-app-5d81df78…` créé par l'EventListener sur la pipeline d'essai, `Succeeded`, TaskRun `publier` à lui, TaskRun et PipelineRun signés par Chains. Rejeu à l'identique et nouvelle livraison de Forgejo écartés (`already exists`, chacun sous son `eventID`). Un seul PipelineRun par commit ; aucune ligne de niveau debug |
| U3 | Un seul PipelineRun créé pendant la fenêtre : le témoin, `sample-app-essai`, `Succeeded` |
| U4 | Gabarit de la bascule remis à 15:25:22 UTC, spec identique à l'objet sauvé ; rattrapage repris ; UID de la tête inchangé (`474b3f60`) |
| U5 | Image réelle inchangée, 24 enveloppes, provenance `474b3f60` |
| U6 | `builds/essai-webhook` : 36 → 38 enveloppes |
| U7 | 0 événement `PolicyViolation`, 0 alerte active ; au journal de l'EventListener, 4 lignes hors niveau `info`, toutes `already exists`, et 0 ligne `tls`, `x509` ou `certificate` |

Les sept prédictions sont tenues. L'attente de 10 s a suffi au cache de l'EventListener : le témoin a été rendu avec la pipeline d'essai. La durée de propagation elle-même n'est pas mesurée.

**Écarts aux effets annoncés.**
- Fenêtre sous la pipeline d'essai : 34 s, contre « 40 s à 1 min 30 environ ».
- Non prédit : le passage du rattrapage planifié à 15:25:00 UTC, manqué pendant la suspension, a été lancé à la reprise (`rattrapage-29901085`, créé à 15:25:22 UTC, `startingDeadlineSeconds` 120). Il s'est arrêté à `PRESENT`, sans création. Il est créé dans la même seconde que la remise du gabarit : leur ordre n'est pas établi.

**Reste après le passage.** Le témoin `sample-app-5d81df78…`, son TaskRun et son pod restent dans `builds`. Ses deux enveloppes restent dans `builds/essai-webhook`, dont la provenance de PipelineRun la plus récente est désormais la sienne.

**Effet sur la couverture.** L'étape `test5` complète est passée sous H1 à H5 : elle sort des non couverts.

Toujours non couverts sous H1 à H5 : le démarrage d'un nouveau pod des résolveurs, la jonction d'un nœud, le saut d'un passage manqué du scan et la branche « scan daté du futur » de `scan.rego`.

## Additif du 07/11/2026, 16:01 UTC : nouveau pod des résolveurs passé sous H1 à H5 par `resolveurs_pod`, V1 à V7 tenues

Passage lancé sur accord du propriétaire (« Oui, lance » à « Je lance resolveurs_pod avec ces effets, pire cas compris ? »), de 16:00:55 à 16:01:11 UTC, avec `JOURNAL=preuves-h5`. Étape, effets et prédictions committés avant, au commit `e6eb730` ([mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 15:49 UTC). Journal : [preuves-h5-resolveurs_pod.log](../08-trust-plane/resultats/preuves-h5-resolveurs_pod.log), 33 OK, 0 KO, code 0. Contrôles hors étape : [resolveurs-pod-hors-etape.log](resultats/resolveurs-pod-hors-etape.log), à 16:01:20 UTC, comparés au relevé d'avant ([resolveurs-pod-avant.log](resultats/resolveurs-pod-avant.log)).

| Prédiction | Mesuré |
|---|---|
| V1, avant | Un pod, `…-xsv5n`. Révision 1. Cinq baux tenus par lui, transitions 1. Pod du gabarit admis en dry-run au nom de `replicaset-controller` |
| V2, admission | Suppression demandée à 16:00:56 UTC, ancien pod disparu à 16:00:57 UTC. Un seul nouveau pod, `…-jgbqh`, du même ReplicaSet `…-56c4c4d957`, sur `sc-confiance`, créé à 16:00:56 UTC. À l'audit, une seule création, par `replicaset-controller`, en 201. 0 `PolicyViolation` |
| V3, démarrage | Conteneur démarré à 16:00:56 UTC, prêt 1 s après la création, 0 redémarrage. Nouveau CiliumEndpoint, identité 11808 inchangée, IP `10.42.0.116` (`10.42.0.81` avant) |
| V4, baux | Les cinq passent au nouveau pod, transitions 2. Pris de 16:00:57.0958 à 16:00:57.0963 UTC, au plus 1 s après le démarrage du conteneur et 1 s après la suppression demandée. La remise à l'arrêt (`ReleaseOnCancel`) est mesurée pour la première fois |
| V5, journal | Cinq « Successfully acquired lease », 0 `is forbidden` avant le témoin |
| V6, témoin | Étape `resolveurs` comme à 10:29 UTC, 0 KO. Les deux résolutions réussissent dans `builds`, les deux échouent dans `preuve-resolveurs` sur les droits. 2 refus au journal, tous dans `preuve-resolveurs`. Audit : 0 lecture hors de `builds`, refus de `preuve-resolveurs` exceptés. Quatre lecteurs des Secrets, liste inchangée |
| V7, hors étape | 0 PipelineRun créé. Premier passage du rattrapage après la reprise (`rattrapage-29901121`, 16:01:00 UTC) arrêté à `PRESENT`. Image réelle inchangée, 24 enveloppes, `474b3f60`. 0 alerte. Sur `sc-confiance`, un seul bac à sable des résolveurs, neuf : ceux du 06/11 et de 11:23 UTC ont disparu |

Les sept prédictions sont tenues.

**Écart aux effets annoncés.** Aucun passage du rattrapage n'a été manqué. La suspension a duré quelques secondes, posée après 16:00:55 UTC (début de l'étape) et levée avant 16:00:58 UTC (début du témoin). Elle n'a franchi aucune minute pleine. Le passage annoncé « lancé à la reprise » n'a donc pas eu lieu : le suivant, à 16:01:00 UTC, est un passage ordinaire.

**Ce que la mesure établit.** La passation dure environ 1 s quand l'ancien pod est arrêté proprement. Elle durait 62 à 78 s quand il mourait avec sa VM, comme à 11:23 UTC. Le trou de résolution d'un redéploiement est donc négligeable. Celui d'une panne de nœud ne l'est pas.

**Effet à connaître.** Le pod des résolveurs est désormais `…-jgbqh`. Le déploiement reste à la révision 1 : `kubectl rollout undo` n'est pas concerné.

**Effet sur la couverture.** Le démarrage d'un nouveau pod des résolveurs sort des non couverts.

Toujours non couverts sous H1 à H5 : la jonction d'un nœud, le saut d'un passage manqué du scan (échéance : accord avant le 08/11 à 09:30 UTC) et la branche « scan daté du futur » de `scan.rego`.

## Additif du 07/11/2026, 16:22 UTC : saut d'un passage du scan, première moitié passée (`scan_saut_suspendre`), W1 et W2 tenues

Passage lancé sur accord du propriétaire (« ok » à « suspendre ce soir, puis réveil à 11:40 UTC le 08/11 pour la reprise »), à 16:21:58 UTC, avec `JOURNAL=preuves-h5`. Étapes, effets et prédictions W1 à W8 committés avant, au commit `dbbbd9f` ([mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 16:15 UTC). Journal : [preuves-h5-scan_saut_suspendre.log](../08-trust-plane/resultats/preuves-h5-scan_saut_suspendre.log).

- W1 et W2 tenues : CronJob `scan-sample-app` suspendu, admis par l'API sous Kyverno en `Deny`. À l'audit, `system:admin` en 200. 0 `PolicyViolation`.
- Correction de la relecture de 15:38 UTC : à la reprise, aucun événement `MissSchedule` n'est attendu. Le contrôleur v1.35.9 ne l'émet jamais quand une échéance est posée (source lu, [scan-saut-sec.log](resultats/scan-saut-sec.log)). La preuve du saut tient à l'absence de Job et à `lastScheduleTime` inchangé.
- Passage sauté attendu : le 08/11 à 09:30 UTC. `ScanEnRetard` en firing vers 11:37 UTC, notifiée au seul récepteur local.
- Reprise par la tâche planifiée `supply-chain-scan-saut-reprise`, le 08/11 à 11:40 UTC. Seule l'étape `scan_saut_reprendre` lui est permise. Passé sa garde horaire, un KO reprend le CronJob par un trap.

**Effet à connaître.** Le CronJob du scan est suspendu jusqu'à la reprise. Si elle n'a pas lieu, la porte refuse `sample-app` le 14/11 vers 09:31 UTC. Retour : `kubectl patch cronjob -n scan scan-sample-app --type merge -p '{"spec":{"suspend":false}}'`.

Toujours non couverts sous H1 à H5 : la jonction d'un nœud, la seconde moitié du saut d'un passage du scan (reprise et alerte, programmées) et la branche « scan daté du futur » de `scan.rego`.

## Additif du 07/11/2026, 16:34 UTC : `essais-h5-planifie.sh` corrigé, relecture du 07/11 rejouée OK

L'additif de 09:50 UTC disait le script non corrigé. Il l'est désormais, pour le relevé du 09/11 (W8, préparé à sec, non lancé) :
- la borne de l'audit est comparée en secondes, ce qui lève les deux KO du 07/11 ;
- seuls les Jobs créés depuis `PLAN` sont retenus, puisque le CronJob en garde trois.

Rejeu en lecture seule à 16:29:45 UTC sur le passage du 07/11 : `bilan : OK`. Le Job et le pod sont créés en 201, sans aucun refus. Journal : [resultats/scan-saut-w8-sec.log](resultats/scan-saut-w8-sec.log). Prédictions W8a et W8b, avec le nouveau `scan-saut-resolution.sh` : [resultats/mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 16:31 UTC.

## Additif du 08/11/2026, 12:05 UTC : saut d'un passage du scan, seconde moitié passée (`scan_saut_reprendre`), W3 à W7 tenues

L'étape a été passée par la tâche planifiée `supply-chain-scan-saut-reprise` à 11:40:43 UTC : 14 OK, 0 KO. Le contre-relevé en lecture seule de 12:04:29 UTC, fait sur accord du propriétaire, confirme ses faits. Détail : [mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 12:05 UTC.
- Le passage du 08/11 à 09:30 UTC a bien été sauté : aucun Job, aucune création à l'audit. `ScanEnRetard` a été notifiée au récepteur local avec un début 319 s après les 26 h (prédit : 300 à 360 s).
- La reprise est admise en 200 au nom de `system:admin`, et `suspend` vaut `false`. Elle n'a lancé aucun Job et produit aucun événement de CronJob ni aucune `PolicyViolation`.
- Les referrers de l'image sont toujours 4 : `AVANT=4` du relevé du 09/11 est confirmé. P1, relue sur le même accord, tient : la plus vieille archive système de `sc-stockage` n'a pas bougé, avec 650.1M occupés.

**Effet à connaître.** `ScanEnRetard` reste en firing jusqu'au referrer du passage du 09/11 à 09:30 UTC ; elle est répétée toutes les 4 h au récepteur local.

Toujours non couverts sous H1 à H5 : la jonction d'un nœud, la résolution de l'alerte après le passage du 09/11 (W8, relevé à prévoir avec l'accord du propriétaire) et la branche « scan daté du futur » de `scan.rego`.

## Additif du 09/11/2026, 10:51 UTC : saut d'un passage du scan, W8 tenue, essai complet

La tâche planifiée `supply-chain-scan-saut-releve-0911`, accordée le 08/11 par le propriétaire, a relu en lecture seule le passage du 09/11 à 09:30 UTC et la fin de l'alerte, à 10:40:42 et 10:40:50 UTC. Les deux journaux concluent `bilan : OK` : [durcissement-h5_planifie-0911.log](resultats/durcissement-h5_planifie-0911.log), [scan-saut-w8_resolution.log](resultats/scan-saut-w8_resolution.log). Détail et comparaison aux prédictions : [mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 10:51 UTC.
- W8a : le premier passage après la reprise a lieu à l'heure (Job créé 0 s après 09:30 UTC, pod de 114 s, 6 conteneurs en code 0). L'attestation de scan est publiée, l'image a 5 referrers, l'audit montre 0 refus 403 ou 422.
- W8b : `ScanEnRetard` s'est résolue 555 s après le nouveau referrer (prédit : 0 à 1200 s). Le récepteur local a reçu 6 firing puis 1 resolved, et Loki a les mêmes lignes (P3 tenue).

**Effet à connaître.** `ScanEnRetard` n'est plus active ; le CronJob du scan tourne normalement.

Toujours non couverts sous H1 à H5 : la jonction d'un nœud et la branche « scan daté du futur » de `scan.rego`.

## Additif du 09/11/2026, 11:05 UTC : Events dans Loki, analyse à sec et décisions à prendre

Sur « traite tout, non ? », compris comme les trois travaux proposés, à sec ; rien n'est lu ni écrit dans le cluster, Loki, Zot ou les VM, et aucun script n'est modifié. Les six contrôles qui jugent sur des Events attendent tous 0. Pour deux d'entre eux, `preuves.sh:3298` et `08-trust-plane/cilium.sh:173`, la lecture n'a aucune borne de temps (corrigé à 11:10 UTC, avant tout push : la phrase disait que les deux rendent 0 dès que les Events ont expiré). `cilium.sh:173` rend 0 dès que les Events ont expiré. `preuves.sh:3298`, lancé 30 s après la reprise, compte aussi la dernière heure d'avant, d'où un risque de faux KO. Quatre décisions sont à prendre (E1 à E4) : rôle de Loki, unité de compte, témoin de vie de la collecte, ordre. Viennent ensuite huit prédictions d'un relevé en lecture seule sur les fenêtres archivées. Détail : [mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 11:05 UTC.

## Additif du 09/11/2026, 13:11 UTC : clôture de la brique, décision du propriétaire

**Décision.** Le propriétaire a répondu « 1 ok » à la question « Je clos la 08c par un additif dans son README et dans le doc 03, documentation seulement, et je commite en local ? ». Cette question suivait l'avis du conseiller : décider tout de suite, sans attendre la borne des 20 h, que rien ne signalerait. Rien n'est lu ni écrit dans le cluster, Zot ou les VM.

**Temps passé.** Estimation : 10 h, hors plan des secrets. Le temps est mesuré par les écarts d'au plus 1 h entre commits successifs qui touchent la brique, depuis le premier commit du 05/11 à 20:39:41 UTC ([`temps-08c-0911.log`](resultats/temps-08c-0911.log), relevé à 13:11:03 UTC) :
- 17,3 h sur 88 commits ;
- 17,0 h sur 79 commits sans S1, en retirant les sujets qui citent S1.

Ce n'est ni une borne basse ni une borne haute. Le compte ignore le travail fait entre deux commits espacés de plus d'1 h, et il compte les attentes entre commits rapprochés. Le dépassement de l'estimation est d'au moins 1,7×, et la règle des 2× ne se juge pas plus finement avec cette mesure. La clôture la rend sans objet.

**Seuil, critère par critère.**

| Critère | État | Preuve |
|---|---|---|
| Les 8 tests négatifs repassent, cluster durci | **Tenu** | `h5_tests`, 06/11, 20:09:59 à 20:20:47 UTC, code 0 (additif de 20:21 UTC) ; test 6 et `intercepteurs` (07/11, 14:07 UTC) ; `test5_refus` étendue (14:55 UTC) ; `test5` complète par `test5_essai` (15:26 UTC) |
| La porte et les contrôles 6 et 7 repassent | **Tenu** | Étapes de la porte, dont `controle6` et `controle7` (07/11, 12:35 UTC) ; `attseule` (12:46 UTC) |
| Tous les ports d'hôte non listés sont refusés | **Tenu sur les ports essayés seulement** | H4 (06/11, 17:48 UTC, [`durcissement-h4_bloque.log`](resultats/durcissement-h4_bloque.log)) : Supervisor 9345 et etcd 2379 refusés par le pare-feu d'hôte à une tâche signée ; test 6 sous H1 à H5 (07/11, 14:07 UTC) : 7 destinations refusées à `construire-image`. Aucun balayage des ports non listés : le critère n'est pas prouvé à la lettre |
| Aucune règle Kyverno en Audit à la fin | **Tenu au 06/11, non relu au 09/11** | Neuf règles en `Deny` relevées le 06/11 à 20:21 UTC, après `h5_tests`. Une relecture serait une mesure, à accorder ; elle n'est pas faite |

**Non couverts à la clôture**, écrits pour ne pas être perdus :
- la jonction d'un nœud ;
- la branche « scan daté du futur » de `scan.rego` ;
- le balayage des ports d'hôte non listés ;
- les contrôles sur Events : `preuves.sh:3298` peut rendre un faux KO (il compte l'heure d'avant la reprise) ; `08-trust-plane/cilium.sh:173` rend 0 dès que les Events ont expiré, une réussite vide. Ils partent dans le chantier des Events ci-dessous ;
- S1 : OIDC de Zot reporté ; secrets restants à rouvrir, avec l'Agent Injector d'OpenBao comme candidat, sans passage au doc 04 pour l'instant ;
- H6 (WireGuard) : mesurée puis retirée ; rotation des clés et mode strict en entrée jamais essayés.

**Chantier des Events dans Loki, ouvert à part.** C'est la « passe dédiée après le 09/11 » décidée le 07/11 ([mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), additif de 20:45 UTC). Le propriétaire a répondu « 2 ok » à « Les Events deviennent un chantier à part, avec E1 à E4 tels que je les recommande et E3 obligatoire ? ». Décisions et précondition : même fichier, additif de 13:11 UTC. Aucune estimation n'est fixée : elle sera proposée au propriétaire avant tout passage. Le relevé R1 à R8 des Events demande son propre accord.

- **Additif du 09/11/2026, 14:46 UTC** : le relevé R1 à R8 est préparé à sec, non lancé. Le script est `evenements.sh releve`, et son essai hors cluster `resultats/evenements-releve-essai.log`. Fenêtres, verdicts et limite de E3 (R2 et R8 prédits non jugés si Alloy a démarré le 07/11) : additif de 14:46 UTC de [mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md). Le chantier a commencé entre 14:38:26 et 14:42:02 UTC ; il est compté depuis 14:38:26 (corrigé à 14:49 UTC, avant tout push). L'estimation proposée, 4 h, n'est pas validée.
- **Additif du 09/11/2026, 15:46 UTC** : le propriétaire a retenu la lecture (a) des témoins positifs R1 et R6. Un compte atteint suffit ; E3 est affiché sans effet sur le verdict. Le script est inchangé. L'estimation, l'accord pour le relevé et le push restent sans réponse.
- **Additif du 09/11/2026, 16:22 UTC, résultat du relevé** (accord : « Oui, lance le relevé ») : R1 OK, avec 32 lignes, autant que kubectl. R6 est KO : aucune ligne. La précondition n'est pas remplie, donc R2 à R5, R7 et R8 sont non jugés. **Constat** : aucune ligne `evenements-k8s` dans les quatre fenêtres postérieures au démarrage d'Alloy du 07/11, alors que le Job du scan a été créé le 09/11 à 09:30:00. Borne mesurée : des lignes jusqu'au 06/11 à 16:53:29, aucune à partir du 07/11 à 16:00:56. La cause n'est pas départagée : soit la collecte par Alloy, soit l'enregistrement par l'API (corrigé à 16:24 UTC, avant tout push). Détail : additif de 16:22 UTC de [mesures-reelles-predictions.md](resultats/mesures-reelles-predictions.md), journal `resultats/evenements-releve.log`.
- **Additif du 09/11/2026, 16:33 UTC, diagnostic** (accord : « Oui, (a) à (d) ») : la cause est mesurée. Au démarrage d'Alloy du 07/11 à 11:22, l'observateur d'Events a échoué une fois sur la découverte des groupes de l'API (`failed to get server groups`), puis s'est arrêté. Dernière ligne dans Loki : 07/11 à 11:20:08, égale à la position enregistrée par Alloy. Le composant reste `healthy`. D'après le source v1.21.3, rien ne relance l'observateur avant un rechargement ou un redémarrage d'Alloy : la panne est silencieuse. Elle se reproduirait à chaque redémarrage qui précède la disponibilité de l'API, si cette explication se confirme. La classe de l'erreur n'a pas été lue, à cause d'une extraction arrêtée au premier guillemet échappé. Aucune alerte ne couvre les Events, car `SourceMuette` ne les surveille pas (corrigé et complété à 17:00 UTC, avant tout push). **Classe lue à 17:01 UTC** (accord : « Oui, relis la classe ») : `connection refused` sur `192.168.161.11:6443`. L'API n'écoutait pas encore au démarrage d'Alloy ; ce n'est pas une erreur de jeton (`resultats/evenements-classe.log`).
- **Additif du 09/11/2026, 17:08 UTC, réparation** (accord : « Oui, redémarre Alloy ») : Alloy de `sc-stockage` a été redémarré à 17:05:19. À 17:08:44, l'observateur avait démarré sans erreur, et Loki contenait 948 lignes d'Events entre 16:05:07 et 17:08:07, dont 45 postérieures au redémarrage. **La collecte des Events est rétablie.** Les Events du 07/11 à 11:20 au 09/11 vers 16:05 sont perdus. Le remède durable reste à décider : sans lui, la panne reviendra au prochain démarrage d'Alloy antérieur à l'API. Détail : additif de 17:08 UTC des prédictions.
- **Additif du 09/11/2026, 17:29 UTC, remède durable (a)** (« Oui, prépare (a) ») : préparé à sec, ni essayé ni appliqué. Il comprend le compteur `loki_process_custom_evenements_lignes_total` dans `evenements.alloy` (19b), l'alerte `EvenementsMuets` (aucune ligne depuis 15 min, ou compteur absent alors qu'Alloy répond) et quatre cas `promtool` (19). L'essai `evenements.sh essai_alerte` sur `sc-stockage` et l'application attendent l'accord du propriétaire. Détail : additif de 17:29 UTC des prédictions. Détail : additif de 16:33 UTC des prédictions, journal `resultats/evenements-diagnostic.log`.

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
