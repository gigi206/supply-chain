# Sortie dédiée de la brique 06 : prédictions (écrites le 10/11/2026 à 14:22 UTC, avant toute exécution)

## Origine

Le propriétaire a répondu « celui que tu veux » à la liste des suites possibles. Je consigne cette réponse comme **délégation du choix de la suite**. Elle ne vaut pas accord pour toucher au cluster, à Zot ou aux VM. J'ai écarté l'intégration au rejeu de zéro : le reste de la 08c (H1 à H5, `secrets.sh`) n'y est pas non plus, et le README de la 08c (additif de H5) réserve cette intégration au propriétaire une fois le jalon prouvé. J'ai retenu la sortie dédiée de la brique 06, et non celle de la 05 : M1 de la 05 n'a pas encore de script, ses besoins de sortie ne sont donc pas connus.

## Constat qui motive la sortie

- `06/s1.sh racine` crée un pod Kata privilégié dans `builds`, **sans label**. Ce pod lance `apt-get` et `mmdebstrap` sur l'instantané `http://snapshot.debian.org/…`. Les étapes `essais` et `relance` ne sortent pas : le chroot est déjà construit.
- Depuis 13:55:03 UTC, `builds-sans-internet` refuse les adresses publiques à ce pod. Le témoin sans label de `sortie-builds.sh apres` a mesuré ce refus vers `snapshot.debian.org` en 80. **L'étape `racine` est donc cassée.** C'est déduit, pas mesuré sur `racine` elle-même. S2 de la 06 a le même besoin.

## Choix de la forme

**Pourquoi pas `toFQDNs`** : la règle demande `l7Proxy`, qui démarre l'Envoy embarqué, et le propriétaire a écarté ce mode le 03/11/2026.

**Pourquoi pas une adresse /32** : relevé depuis l'hôte à 14:19 UTC, non archivé ailleurs que dans ce paragraphe :
- `snapshot.debian.org` passe par le CNAME `debian.map.fastlydns.net.`, puis vers 199.232.170.132 ;
- `dl.rockylinux.org` passe par le CNAME `rockylinux.map.fastlydns.net.`, puis vers **la même adresse** ;
- `dl.fedoraproject.org` est résolu vers 38.145.32.22 à .24.

Une /32 ne désignerait donc pas l'hôte. Elle désignerait un nœud de Fastly partagé, qui dépend en plus du résolveur.

**Forme retenue** : celle de `prefetch-sortie`, réduite au port 80.
- Nouvelle politique `prefetch-deb-sortie`, qui ne laisse sortir que vers le DNS de kube-dns et vers les adresses publiques en TCP 80.
- Le refus par défaut est actif en entrée et en sortie.
- Le label est `tekton.dev/task=prefetch-deb`. Sa limite est celle de `prefetch-gomod` : seuls l'administrateur et une tâche signée de ce nom portent ce label, puisque Tekton le réécrit (mesuré en J7).
- `builds-sans-internet` ajoute `prefetch-deb` à son `NotIn`, puisqu'un refus l'emporterait sur l'autorisation.

**Limite** : un pod compromis au label `prefetch-deb` pourrait envoyer des données vers une adresse publique en 80.

## Prédictions

| # | Étape | Prédit | Confiance |
|---|---|---|---|
| E0 | `deb_sec`, hôte seul | 4 politiques lues dans le dépôt par `helm template`, sans aucune requête au cluster. Invariants OK : `prefetch-gomod` est sélectionné par `prefetch-sortie` seule, et aucune politique n'autorise de trafic à `construire-image`. Aucune politique à sortie CIDR n'est sous un refus. `prefetch-deb` est sélectionné par `prefetch-deb-sortie` seule, et un pod sans label par `builds-sans-internet` seule. Contre-épreuve : avec le `NotIn` d'origine, l'invariant signale `CiliumNetworkPolicy prefetch-deb-sortie`. Code 0 | haute : mêmes filtres que ceux mesurés à 13:55 UTC |
| E1 | `deb_appliquer`, sur accord | État de départ : `NotIn` à `["prefetch-gomod"]`, `prefetch-deb-sortie` absente. Les deux politiques valides pour Cilium. `NotIn` à `["prefetch-gomod","prefetch-deb"]`. Invariants du cluster identiques à E0 | haute |
| E2 | `deb_temoins`, sur le même accord | Les trois témoins existants comme à 13:55 UTC (`sortie-apres.log`). Témoin `prefetch-deb` : DNS résolu pour les deux noms, `snapshot.debian.org` en 80 joint, et 4 accès refusés : `proxy.golang.org` en 443, API de RKE2, Zot et Forgejo | moyenne : pour Zot, Forgejo et l'API, le refus attendu est un dépassement de délai. Le libellé exact de l'exception n'est pas prédit |
| E3 | `PREFIXE=s1c 06/s1.sh racine` avec le label, accord distinct. Journaux à part, iproute2 inclus comme en s1b, chroot reconstruit | `apt-get update` à rc 0, InRelease identique à celui de l'hôte, `mmdebstrap` racine et chroot à rc 0, archives rapatriées | moyenne : le pod est Kata, alors que le témoin est runc. La politique s'applique aussi aux pods Kata (mesuré en test 6 sur `construire-image`) |
| E3b | Même passage | Archive `racine` de même sha256 que celle de s1b (même instantané, même `SOURCE_DATE_EPOCH`) | faible : la reproductibilité de `mmdebstrap` n'est pas mesurée ici, c'est l'objet de S2 |
| E4 | `deb_retirer`, si demandé | `NotIn` revient à `["prefetch-gomod"]` avant la suppression de `prefetch-deb-sortie`. Invariants d'origine OK | haute |

**Durée estimée**
- E1 et E2 : 15 min.
- E3 : 20 min, l'ordre de grandeur du passage `racine` de S1.

Le fichier du dépôt garde `prefetch-deb` dans le `NotIn` même après E4. Un `sortie-builds.sh appliquer` relancé poserait donc cette version.

**Critère de retrait** : si le témoin `prefetch-deb` joint Zot, Forgejo, l'API ou `proxy.golang.org` en 443, ou si l'un des trois témoins existants change, je lance `deb_retirer` et je consigne.

## Résultat de E0 (14:23:47 UTC, journal [`sortie-deb_sec.log`](sortie-deb_sec.log))

Lancé sous `unshare -rn`, dans un espace réseau vide : aucune requête au cluster n'était possible. Code 0. **E0 tenue.**

| # | Mesuré | Verdict |
|---|---|---|
| E0 | 4 politiques lues dans le dépôt. `prefetch-gomod` est sélectionné par `prefetch-sortie` seule, `prefetch-deb` par `prefetch-deb-sortie` seule, et un pod sans label par `builds-sans-internet` seule. Aucune politique n'autorise de trafic à `construire-image`, et aucune politique à sortie CIDR n'est sous un refus. Contre-épreuve : avec le `NotIn` d'origine, l'invariant signale `CiliumNetworkPolicy prefetch-deb-sortie` | tenue |

**Portée** : ce passage ne lit que le dépôt. Il ne prouve ni l'état du cluster, ni le comportement de Cilium ; c'est l'objet de E1 et E2. **E1 à E4 ne sont pas lancées.**

**Push précédent**, consigné ici : le 10/11/2026 à 14:08:34 UTC, `bc0f352..145f67a`, contrôle des secrets OK sur 22 fichiers.

## Additif du 10/11/2026, 14:27 UTC : invariant des labels exclus ; prédiction E0 bis, écrite avant exécution

**Trou relevé par le conseiller, sur relecture.**
- Dans le dépôt, `builds-sans-internet` exclut désormais `prefetch-deb`. L'étape `appliquer` ne pose que ce fichier.
- Si on la relance, ou si un rejeu pose cette règle sans `prefetch-deb-sortie`, un pod `prefetch-deb` n'est sélectionné par aucune politique. Il a alors tout Internet, tous ports compris, et les invariants passent quand même.
- Le pod `racine` de `06/s1.sh` porte ce label : il serait le premier exposé.
- Le même cas se produit après `deb_retirer` suivi d'`appliquer`.

**Correctif**
- `invariants()` vérifie désormais chaque label exclu d'un refus (`NotIn` d'une politique à `egressDeny`). Ce label doit être sélectionné par au moins une politique qui a des règles `egress`, avec `enableDefaultDeny.egress` différent de `false`.
- `deb_sec` ajoute une seconde contre-épreuve.

| # | Prédit | Confiance |
|---|---|---|
| E0 bis | `deb_sec` sous `unshare -rn` : les mêmes lignes qu'en E0, plus « labels exclus d'un refus sans politique de sortie dédiée » vide. La seconde contre-épreuve, sans `prefetch-deb-sortie`, signale `tekton.dev/task=prefetch-deb`. Code 0 | haute |

**Dans le cluster, non lancé** :
- avant `deb_appliquer`, le nouvel invariant devrait être vide, puisque `prefetch-gomod` est couvert par `prefetch-sortie` ;
- `prealables`, sans aucun refus, donne aussi un résultat vide.

**shellcheck** : une remarque `SC2016` de plus, de niveau info, sur la nouvelle variable jq. Les guillemets simples y sont voulus.

*Corrigé à 14:29 UTC, avant tout push* : le message du commit c980b47 donne « 14:20 à 14:25 UTC ».
- **Préparation** : de 14:19 UTC (relevé DNS) à 14:23:36 UTC (commit).
- **14:25** n'a jamais été relevé.
- **E0** : partie à 14:23:47 UTC, après ce commit.

*Corrigé à 14:28 UTC, avant tout push* : le titre de l'additif ci-dessus portait 14:29 UTC. Il a été écrit à 14:27:54 UTC et commité à 14:27:55 UTC (f16a88b), d'où le titre corrigé. Le commentaire de `sortie-builds.sh` portait 14:28 ; il est corrigé de même. La mention « Corrigé à 14:29 UTC » sur l'heure de c980b47, plus haut, est fausse de même : cette correction a été écrite à 14:27 UTC. Elle est laissée telle quelle, car elle est déjà commitée.

### Résultat de E0 bis (14:28:02 UTC, journal [`sortie-deb_sec.log`](sortie-deb_sec.log))

Lancé sous `unshare -rn`. Code 0. **E0 bis tenue.**
- Les lignes d'E0 sont identiques.
- La ligne « labels exclus d'un refus sans politique de sortie dédiée » est vide.
- Seconde contre-épreuve : sans `prefetch-deb-sortie`, l'invariant signale `tekton.dev/task=prefetch-deb`.

Ce passage a réécrit le journal d'E0. Celui-ci est remis sous [`sortie-deb_sec-e0.log`](sortie-deb_sec-e0.log), à partir d'une copie prise avant le passage. Le lien du résultat d'E0 mène donc désormais au journal d'E0 bis.

### Relevé DNS archivé (14:28:10 UTC, [`sortie-deb-dns.log`](sortie-deb-dns.log))

- `snapshot.debian.org` et `dl.rockylinux.org` sont résolus vers **151.101.122.132**, toujours par les CNAME de Fastly. À 14:19 UTC, c'était 199.232.170.132.
- L'adresse est donc **partagée entre les deux hôtes, et elle change en quelques minutes**. Une /32 aurait été à la fois trop large et instable.
- `dl.fedoraproject.org` reste résolu vers 38.145.32.22 à .24.

## Résultat de E1 et E2 (accord du propriétaire : « Oui, lance E1-E2 »)

Script à la version `17b4287`. Journaux : [`sortie-deb_appliquer.log`](sortie-deb_appliquer.log) et [`sortie-deb_temoins.log`](sortie-deb_temoins.log).
- **E1** : de 14:29:39 UTC, code 0.
- **E2** : de 14:29:45 à 14:33:34 UTC, **code 1**.

| # | Mesuré | Verdict |
|---|---|---|
| E1 | État de départ conforme : `NotIn` à `["prefetch-gomod"]`, `prefetch-deb-sortie` absente. Les deux politiques sont valides pour Cilium, et le `NotIn` passe à `["prefetch-gomod","prefetch-deb"]`. Les invariants du cluster sont tous OK : celui des labels exclus est vide, `prefetch-deb` est sélectionné par `prefetch-deb-sortie` seule, et un pod sans label par `builds-sans-internet` seule | tenue |
| E2, trois témoins existants | Identiques à `sortie-apres.log` de 13:55 UTC, hors adresses résolues par le DNS | tenue |
| E2, témoin `prefetch-deb` | DNS résolu pour les deux noms. `snapshot.debian.org` en 80 : **joint (HTTP 200)**. `proxy.golang.org` en 443, API de RKE2 et Zot : refusés (`URLError`). Forgejo : `git ls-remote` a dépassé son délai de 30 s, **sans connexion établie** | tenue sur le fond, voir l'écart |

**Écart, dû au script des témoins.**
- Le `TimeoutExpired` de `git` n'était pas rattrapé dans `DESTINATIONS` : Python a fini en erreur, puis l'étape s'est arrêtée en code 1.
- Le pod de test `sortie-deb` est donc resté en place. Je l'ai supprimé à 14:34 UTC ; aucun pod `sortie-` ne reste dans `builds`.
- Les trois témoins précédents n'avaient pas rencontré ce cas : Forgejo leur répondait, ou les refusait sans délai.
- Corrigé à sec à 14:35 UTC : un délai dépassé s'affiche désormais « refusé (TimeoutExpired) ». **Cette correction n'est pas rejouée.**
- Pendant la vérification de syntaxe, mon contrôle a chargé tout le script hors de son répertoire. `commun.sh` n'a pas été trouvé, et rien n'a été créé ni lancé.

**Critère de retrait non rempli.**
- Le témoin `prefetch-deb` ne joint ni Zot, ni Forgejo, ni l'API, ni le 443 public.
- Les trois témoins existants sont inchangés.
- **Les deux politiques restent en place.**

**Constat sur le DNS** : `snapshot.debian.org` a été résolu en trois adresses de Fastly selon le pod, en quelques minutes : 151.101.122.132, 199.232.82.132 et 199.232.170.132. Cela confirme qu'une /32 ne pouvait pas convenir.

**Durée** :
- de 14:29:39 à 14:34:24 UTC (suppression du pod), soit 5 min ;
- 15 min étaient estimées pour E1 et E2.

**Reste** :
- E3 (`PREFIXE=s1c s1.sh racine`), qui demande un accord distinct ;
- la question du rejeu.

**Correction** : le message du commit `f16a88b` dit aussi « ajouté à 14:29 UTC », alors que le commit est de 14:27:55 UTC. Je le note ici, car ce message ne sera pas réécrit.

## Résultat de E3 (14:36:07 à 14:41:05 UTC, accord du propriétaire : « Oui, lance E3 »)

Passage `PREFIXE=s1c 06/s1.sh racine`. Journal : [`s1c-racine.log`](../../06-deb-sbuild/resultats/s1c-racine.log).
- Le pod portait bien `tekton.dev/task=prefetch-deb`, d'après sa spec relue.
- Le journal ne contient aucun KO, et le pod a été supprimé par l'étape.
- **Code de sortie non relevé** : mon shell est zsh, où `PIPESTATUS` est vide. Le code 0 est déduit de la ligne « 06 S1 racine fait » de `chrono.tsv`, que `lancer` n'écrit qu'après une étape réussie.

| # | Mesuré | Verdict |
|---|---|---|
| E3 | Pod Kata privilégié, root. `apt-get update` à rc 0 en 4 s, InRelease identique à celui de l'hôte (`0584fba3…`). `mmdebstrap` racine et chroot à rc 0, en 62 s et 77 s. 238 `.deb` conformes au Packages vérifié. Archives rapatriées | tenue |
| E3b | Archive `racine` : `f8f221ca…`, **identique à celle de s1b**, octet pour octet (344 634 880 octets) | tenue |

**Non prédit** : le chroot reconstruit (`440ba93b…`, 920 000 000 octets) est identique à celui de s1, construit de 13:04:51 à 13:09:34 UTC (chrono.tsv de la 06). Deux `mmdebstrap` du même instantané, avec le même `SOURCE_DATE_EPOCH`, donnent donc la même archive, pour la racine comme pour le chroot. C'est un premier indice pour S2, mais pas la preuve de S2 : S2 demande deux constructions comparées dans son propre protocole.

**Bilan**
- `racine` repasse sous `builds-sans-internet`, grâce à la sortie dédiée. La déduction « cassée sans le label » n'a pas été mesurée, et je ne l'ai pas cherché.
- **Durée** : 5 min pour E3, contre 20 min estimées.
- **Reste** : la question du rejeu, et le push de `145f67a..HEAD`.
