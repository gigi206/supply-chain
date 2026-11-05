# Brique 08d : cert-manager, relevés avant décision

Origine : besoin signalé par le propriétaire le 05/11/2026 (« on aura surement besoin également de cert-manager »), puis D6 (a) de la [08b](../08b-rke2/README.md) : jalon distinct après le rejeu, v1.21.3, émetteur sur la PKI d'OpenBao, droits sur les Secrets mesurés.

## État

**Relevés à sec du 05/11/2026, 20:49 UTC : rien installé.** [`analyse.sh`](analyse.sh) ne fait que lire l'API et rendre le chart localement. Ces relevés remettent en cause l'intérêt du jalon : la décision D7 ci-dessous est à prendre avant d'écrire le déploiement.

**Non vérifié** : cert-manager n'a jamais tourné ici. L'authentification et le chemin Kyverno viennent de la lecture du code, pas d'un essai. Le moteur PKI d'OpenBao n'est pas activé.

## Constats

| Sujet | Mesure | Conséquence |
|---|---|---|
| Chart | Digest `e482675a` signé, vérifié avec la clé publiée par le projet, autre clé refusée ([journal](resultats/analyse-telecharger.log)) | Épinglable. Pas de journal de transparence, comme pour les images |
| Certificats du cluster | 11 Secrets relevés ([journal](resultats/analyse-consommateurs.log)) | Voir le tableau suivant |
| CA du PoC | `pathlen:0` ; noms permis : `poc.test`, `svc.cluster.local`, le réseau des nœuds, celui des Services | Elle ne peut signer ni une intermédiaire, ni le nom de Hubble, `*.default.hubble-grpc.cilium.io`. OpenBao devrait porter une **racine séparée** |
| Droits ([journal](resultats/analyse-droits.log)) | Contrôleur : `create`, `update`, `delete`, `patch` sur **tous les Secrets du cluster**. cainjector : `get`, `list`, `watch` sur tous | Deux comptes de plus. Il y en a cinq, que H5 de la 08c doit réduire. L'un pourrait écrire `signing-secrets` ou les identifiants de Zot |
| Contenu du chart | 3 Deployments, 1 Job, 6 CRD, 2 webhooks en `failurePolicy=Fail` | Contextes compatibles avec `restricted` sur les champs relevés. Aucune limite : valeurs à fournir pour `limites-obligatoires` |
| Authentification | Au tag v1.21.3, `serviceAccountRef` poste `role` et `jwt` sur `<path>/login`, avec `tokenAudiences` en plus des audiences par défaut | Le montage `auth/jwt` existant conviendrait, sans moteur Kubernetes. Le chart n'accorde pas `serviceaccounts/token` : Role à ajouter |
| Restriction | `--namespace` limite le contrôleur à un espace et coupe les ClusterIssuer ; `global.rbac.create=false` retire les rôles du chart | Rôles à écrire et à mesurer. cainjector à traiter à part |

| Consommateur | Secrets | Possible avec cert-manager ? |
|---|---|---|
| Hubble | `hubble-server-certs` | **Oui**, option `hubble.tls.auto.method=certmanager` du chart 1.20.4. Mais le port 4244 n'a aucun client : Relay et UI sont désactivés, et `hubble observe` passe par le socket local de l'agent. Fin de validité : 03/11/2027 |
| Kyverno | 4 Secrets `*-tls-ca` et `*-tls-pair` | Lu dans le code v1.19.2, pas essayé : un Secret sans le label de Kyverno est lu, plus renouvelé. La CA se pose à la main |
| Tekton | 3 Secrets, clés `ca-cert.pem`, `server-cert.pem`, `server-key.pem` | **Non** tel quel : ce ne sont pas les clés `tls.crt` et `tls.key` |
| Distribution | `k3s-serving` | Non : géré par la distribution |
| OpenBao | `openbao-tls` | Non : amorçage, il ne peut pas se servir lui-même au démarrage |
| Cilium | `cilium-ca` | CA générée par le chart, pas un consommateur |

Hors cluster, D6 exclut déjà Zot, Forgejo, Loki et Grafana.

## Décision D7

**Recommandé (a) : ne pas installer pour l'instant.** Le seul usage direct est un certificat que personne ne présente à un client. Le coût serait réel : deux comptes de plus sur tous les Secrets, dont un en écriture, alors que la 08c cherche à les réduire. Le chart et son audit restent prêts. À rouvrir au premier service du cluster qui exposera du TLS sans gérer lui-même ses certificats, par exemple une Gateway. La 08c n'en dépend pas.

**(b) Installer pour Hubble seul**, pour prouver la chaîne OpenBao vers cert-manager avant la plateforme finale. Racine séparée dans OpenBao, `pki/` non exportable, ajoutée à `openbao.sh`. Estimation : 8 h. Une décision s'impose à partir de 16 h.

**(c) Hubble et Kyverno : déconseillé.** Kyverno est la porte d'admission. Il dépendrait de cert-manager, qui dépend d'OpenBao, scellé après chaque redémarrage des VM ([`redemarrer.sh`](../08-trust-plane/redemarrer.sh)). Aujourd'hui, Kyverno renouvelle seul ses certificats.

**Additif du 05/11/2026, 21:02 UTC, réponse du propriétaire** : « on en aura besoin pour exposer des services ensuite ». cert-manager reste donc prévu, **lié à l'exposition de services**, et non abandonné. Pas d'installation dans le rejeu RKE2 ni dans la 08c, sauf demande contraire.

À trancher au moment de ce jalon, rien de mesuré ici :
- quels services sont exposés, et avec quels noms ;
- quelle Gateway : aucune n'est retenue au PoC, et celle de Cilium reste exclue tant que `l7Proxy` vaut `false` ;
- quel émetteur, et qui fait confiance à sa racine. Zot, Forgejo, Loki et Grafana restent hors de portée tant qu'ils ne passent pas par cette Gateway ;
- les droits relevés ci-dessus restent à réduire avant l'installation.

## Prédictions sous (b)

Écrites le 05/11/2026 à 20:50 UTC, avant toute exécution. Elles ne valent que sous D7 (b), après le rejeu RKE2 et hors des étapes de la 08c en cours.

1. **Espace** : `cert-manager` admis sous `restricted`, label posé, sans exemption.
2. **Images** : miroirées dans Zot, par digest, signatures vérifiées avant. Sans cela, `images-zot-par-digest` les relève.
3. **Réseau** : l'espace doit entrer dans la liste fermée de la 08c, avec l'entrée du serveur d'API vers le webhook, la sortie vers l'API et vers OpenBao sur 8200. Refus attendu tant que cette politique manque.
4. **OpenBao** : connexion par `auth/jwt` avec l'audience `openbao`, sujet lié au seul compte de l'émetteur ; rôle PKI limité au nom `*.default.hubble-grpc.cilium.io`. Tout autre nom refusé.
5. **Hubble** : `hubble-server-certs` réémis et renouvelé, agents redémarrés, `hubble observe` inchangé. Le CronJob de scan et les tests négatifs passent toujours.
6. **Droits** : avec les rôles du chart, le relevé `kubectl auth can-i` montre sept comptes lecteurs. Avec `--namespace` et des rôles propres, je prédis que le contrôleur ne lit plus les Secrets hors de `kube-system`. Non essayé.
7. **Scellement** : OpenBao scellé, l'émission échoue sans effet sur le certificat en service, puis reprend après le descellement.
