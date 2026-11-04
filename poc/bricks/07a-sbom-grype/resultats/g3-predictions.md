# G3 : prédictions (écrites le 04/11/2026 à 20:00 UTC, avant toute exécution)

Clé et identité du scanner, calquées sur J5 (clé `tsa`) et J8 (identifiants Zot du job d'horodatage dans OpenBao) de la 08. Préparé à sec : rien n'est appliqué à OpenBao ni au cluster.

## Décision ajoutée : D9, identifiants Zot du job et découpage des rôles

**Constat**
- G4 pousse le bundle avec le compte `poc-scan`. Le job doit donc lire son mot de passe.
- J8 (décision du propriétaire du 01/11/2026) a placé les identifiants du job d'horodatage dans OpenBao, sans Secret Kubernetes.
- Le README annonçait une seule politique, limitée aux trois chemins du client hashivault. Elle ne couvre pas ces identifiants.

**Options**
- (a) **deux rôles JWT liés au même compte `scan:scanner`** :
  - `scan-zot` : lecture de `kv/scan/zot` et révocation, jeton de 1 min, calque exact de J8 ;
  - `scanner` : les trois chemins du client hashivault plus la révocation, jeton de 5 min, pris juste avant la signature (en G4).
- (b) un seul rôle `scanner` avec les deux politiques, et un jeton d'environ 30 min pris au démarrage du pod (l'import de la base prend déjà 74 s).
- (c) un Secret Kubernetes pour `poc-scan`, contraire à J8.

**Recommandation : (a).** Le jeton qui signe ne vit que pendant la signature, et celui qui lit Zot est révoqué juste après la lecture.

**Écart au README** : `scanner-signature` a quatre chemins, pas trois. `auth/token/revoke-self` permet de révoquer le jeton après la signature. Il n'a ni renouvellement ni politique par défaut.

## Mesuré à sec (04/11/2026, entre 19:49 et 20:00 UTC, sur l'hôte, sans le cluster)

- **cosign v3.1.4 de mise**, avec une clé jetable :
  - `sign-blob --key … --signing-config` vide, hors réseau (`unshare -rn`) et avec un HOME vide : bundle `v0.3`, matériel `publicKey` ;
  - le bundle est vérifié par `verify-blob --insecure-ignore-tlog=true` ; un contenu modifié est refusé ;
  - rien n'est écrit dans HOME.
- **Image `outils-scan`** : `nc`, `wget`, `timeout` et `ssl_client` de busybox sont présents. Entrée `cosign`, utilisateur 65532.
- **Pods de `g3_cosign`** (bouchon à la place de `kubectl`) : YAML validé par `kubectl apply --dry-run=client`, et les quatre scripts de conteneur passent `sh -n`.
- **`conforme`** : testé sur un cas conforme, un cas non conforme et un cas tronqué (les deux derniers en KO).
- **Objets du cluster** :
  - `zone-confiance` a été appliquée côté client (`kubectl-client-side-apply`, comme `charger`) : on la réapplique de la même façon ;
  - la NetworkPolicy d'OpenBao l'a été côté serveur (`kubectl`, comme `tsa.sh`).

## Étapes et prédictions (accord du propriétaire avant `g3_cluster`)

Ordre : `g3_cluster g3_openbao g3_essais g3_cosign`.

**g3_cluster**
- Espace `scan` en Pod Security `restricted`, compte `scanner` sans jeton monté d'office.
- Sorties de l'espace : `UDP/53,TCP/53,TCP/8200,TCP/5000,TCP/3000`.
- NetworkPolicy d'OpenBao avec quatre sources : `tekton-chains`, `tsa` (`app=timestamp-authority`), `horodatage`, et `scan` (`app=scan`).
- `openbao-0` n'est ni recréé ni redémarré (uid et nombre de redémarrages inchangés), et reste descellé.
- `zone-confiance` contient `scan`.
- Un pod de `scan` sans nodeSelector est refusé avec le message « zone confiance : nodeSelector zone=confiance obligatoire », après quelques essais : le temps que Kyverno publie la règle. Le même pod avec `zone=confiance` est accepté en dry run.

**g3_openbao**
- Compte `poc-scan`, registre `sc-stockage.poc.test:5000`.
- Clé `scanner` : `ecdsa-p256,false,false,false` (exportable, sauvegarde en clair et suppression refusées), `latest_version` 1.
- Rôles :
  - `scanner` : `…:scan:scanner,openbao,scanner-signature,true,service,300,300,0` ;
  - `scan-zot` : `…,scan-zot,true,service,60,60,0`.
- Politiques identiques aux fichiers versionnés.
- `kv/scan/zot` a la même empreinte que les identifiants écrits ; la valeur n'est jamais affichée.
- Clé publique P-256 exportée dans `resultats/scanner-cle-publique.pem`.

**g3_essais**
- Rôle `scanner` : 15 lignes conformes, soit 2 acceptations (lecture de la clé publique, révocation), une signature `vault:v1:` et 11 refus :
  - signer avec les clés `chains` et `tsa` ;
  - lire `transit/keys/chains` ;
  - exporter la clé, la rendre exportable, la sauvegarder en clair ;
  - lire `kv/scan/zot` et `kv/horodatage/zot` ;
  - consulter puis renouveler son jeton ;
  - signer après la révocation.
- Rôle `scan-zot` : 8 lignes conformes, soit 2 acceptations (lecture de `kv/scan/zot`, révocation) et 5 refus :
  - signer avec la clé `scanner` ;
  - lire la clé `scanner` ;
  - écrire `kv/scan/zot` ;
  - lire `kv/horodatage/zot` ;
  - relire après la révocation.
- 8 connexions croisées refusées sur 8 :
  - `scan:default` vers `scanner` et vers `scan-zot` ;
  - le TSA et Chains vers `scanner` ;
  - `horodatage` vers `scan-zot` ;
  - `scan:scanner` vers `tsa`, `tekton-chains` et `horodatage`.
- La signature Transit est vérifiée par openssl avec la clé exportée, et refusée avec la clé publique de Chains.
- Audit : connexions des deux rôles, signatures acceptées, refus en 403 (« permission denied »).

**g3_cosign**
- Pod `scan-cosign` en `Succeeded`. Jeton du rôle `scanner` obtenu en un essai, ou en quelques-uns : le réseau d'un pod neuf (constat de J3).
- Sondes : Zot et Forgejo joints ; Grafana et Internet (base Grype) injoignables.
- `cosign sign-blob --key hashivault://scanner` écrit `temoin.bundle.json`.
- La clé lue par `cosign public-key` est la clé exportée.
- Jeton révoqué par le conteneur `revocation`.
- Sur l'hôte : bundle vérifié par `cosign verify-blob` avec la clé exportée ; un contenu modifié est refusé, la clé de Chains aussi.
- Pod sans l'étiquette `app=scan` : Zot joint, OpenBao injoignable (NetworkPolicy d'OpenBao).
- Audit : connexion du rôle `scanner`, lecture de `transit/keys/scanner`, `transit/sign/scanner/sha2-256` et `auth/token/revoke-self`, sans aucune erreur.

**Incertain**
- **Chemins appelés par le client hashivault de cosign v3.1.4-dev.** J5 a mesuré ceux de sigstore v1.11.1 (TSA), pas ceux de cosign. Si un chemin manque à la politique, la signature échoue en 403 et l'audit le nomme. La correction se fera en additif, sans élargir au-delà du chemin nommé.
- **Classement des sondes.** Cilium abandonne les paquets refusés, ce qui donne un délai, classé « injoignable ». Un refus de connexion serait classé « joint ».
- **Premier tirage** de `outils-scan` sur `sc-confiance` (environ 165 Mo) dans la fenêtre de 180 s du pod.

## Effets à connaître

- **OpenBao** :
  - une clé Transit `scanner`, non supprimable (`deletion_allowed` à false, comme `tsa`) ;
  - deux politiques, une entrée `kv/scan/zot` et deux rôles ;
  - ni redémarrage, ni descellement.
- **Cluster** :
  - espace `scan`, ConfigMap `scan-config` (CA du PoC) ;
  - NetworkPolicy d'OpenBao réappliquée, avec une source de plus ;
  - `zone-confiance` réappliquée, avec un espace de plus. Kyverno republie son webhook en quelques secondes.
- **Fichiers de la 08** : `openbao/openbao.yaml` et `politique/admission.yaml` sont modifiés (additif au README de la 08).
- **R4 et R5 de la 10** : aucune interaction. La porte, `sc-replay` et la VSA ne sont pas touchés. G3 dure quelques minutes.
- **Rejeu de zéro de la 08** : il effacera la clé, les rôles et l'espace. À intégrer en G7, dans `rejeu.sh`.
- **Bundle témoin** archivé dans `resultats/g3-temoin.bundle.json` : c'est la signature d'un texte d'essai, pas d'une image.

## Corrections avant exécution (04/11/2026, 20:05 UTC, rien appliqué)

**Sonde Internet.** Le texte plus haut cite « Internet (base Grype) ». Un nom non résolu serait tombé dans la branche « joint », et le DNS aurait répondu à la place de la NetworkPolicy. Deux corrections :
- la sonde vise maintenant une adresse littérale, `https://1.1.1.1/`, attendue injoignable ;
- un nom non résolu est classé `NON_RESOLU`, ce qui fait échouer la comparaison.

**Étape ajoutée : `g3_grafana`**, après `g3_cosign`. Ordre : `g3_cluster g3_openbao g3_essais g3_cosign g3_grafana`. G3 n'avait aucune preuve lue dans Grafana, alors que tout doit y être consultable.
- Le collecteur lit `/var/log/pods/*/*/*.log` : l'espace `scan` est collecté sans modification de la 19b.
- L'audit d'OpenBao arrive par la sortie du pod : 941 requêtes dans les 2 189 dernières lignes, relevé à 20:05 UTC.
- Aucune signature `transit/sign` dans cette fenêtre, ce qui est normal : il n'y a pas eu de nouvelle enveloppe. La requête de Grafana n'a donc rien rendu sur 2 h.

Prédictions, lues par l'auditeur :
- les lignes `jeton du rôle scanner obtenu` et `jeton du rôle scanner révoqué` du pod `scan-cosign` ;
- au moins une ligne d'audit citant `transit/sign/scanner` ;
- ni le mot de passe de `poc-scan`, ni son encodage docker dans les réponses.

Les pods d'essai sont supprimés par `g3_grafana`, et non plus par `g3_cosign` : leurs journaux doivent d'abord être collectés.

**Clé de Chains de la contre-épreuve** : `resultats/chains-cle-publique.pem` de la 08 est bien la clé en service (SPKI `d8c637ab3f7ddb2c`, égale à `chains.pub` de la ConfigMap `horodatage`, relevé entre 20:01 et 20:05 UTC).

## Résultat (04/11/2026, de 20:21:26 à 20:22:08 UTC)

Accord du propriétaire : D9 (a), appliquer G3, pousser les deux commits (« 1 a, 2 oui, 3 oui »). Cinq étapes, code 0 du premier coup, sans passage raté à archiver.

**Conforme à toutes les prédictions de fond :**
- `g3_cluster` : espace `scan`, quatre sources dans la NetworkPolicy d'OpenBao, `openbao-0` ni recréé ni redémarré (uid `73d86162…`, 0 redémarrage), OpenBao descellé, pod sans nodeSelector refusé, contre-épreuve acceptée ;
- `g3_openbao` : clé `ecdsa-p256,false,false,false`, deux rôles à 300 s et 60 s, politiques égales aux fichiers, `kv/scan/zot` de même empreinte, clé publique SPKI `8cbcbb4e…` ;
- `g3_essais` : rôle `scanner` 15 lignes (2 acceptations, 11 refus), rôle `scan-zot` 8 lignes (2 acceptations, 5 refus), 8 connexions croisées refusées sur 8 ; signature vérifiée par openssl, refusée avec la clé de Chains ;
- `g3_cosign` : pod `Succeeded`, Zot et Forgejo joints, Grafana et 1.1.1.1 injoignables, `sign-blob` réussi, clé lue par cosign égale à la clé exportée, bundle vérifié, contenu modifié et clé de Chains refusés ; pod sans `app=scan` : Zot joint, OpenBao injoignable ;
- `g3_grafana` : connexion et révocation visibles, 8 lignes d'audit citant `transit/sign/scanner`, identifiants de `poc-scan` absents des réponses.

**Point incertain levé.** Chemins appelés par le client hashivault de cosign v3.1.4-dev, relevés dans l'audit :
- `auth/jwt/login` (par le conteneur `jeton`) ;
- `transit/keys/scanner`, en lecture, 2 fois (signature et `public-key`) ;
- `transit/sign/scanner/sha2-256` ;
- `auth/token/revoke-self` (par le conteneur `revocation`).

Aucune erreur. `transit/sign/scanner` sans algorithme n'a pas été appelé : ce troisième chemin de la politique, repris de J5, n'a pas servi ici. Il reste en place, comme dans la politique `tsa-signature`.

**Écarts mineurs de prédiction :**
- pod sans nodeSelector refusé dès le premier essai, et non « après quelques essais » : la règle était déjà publiée ;
- jeton obtenu au premier essai, et le premier tirage de `outils-scan` tient dans la fenêtre : le pod avait fini moins de 21 s après sa création (son âge relevé en fin d'étape).

**Limites.** Le jeton du rôle `scanner` reste valable le temps entre le conteneur `jeton` et le conteneur `revocation`. Si le pod échoue avant la révocation, il expire seul après 5 min au plus. Le témoin signe un texte d'essai, pas une image : le prédicat de scan et le push viennent en G4.
