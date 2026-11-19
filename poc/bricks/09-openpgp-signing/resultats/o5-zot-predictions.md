# Brique 09, O5 réel, troisième accord : lecture de Zot, prédictions

Écrites le 19/11/2026 à 19:57:51 UTC, avant tout lancement de `lecture`.

**Accord.** Question posée : « Accordez-vous le troisième point : un accès en lecture à Zot, pour lire les manifestes non signés et leur provenance de Chains avant de signer les attestations de lien ? ». Réponse du propriétaire, reçue avant l'heure ci-dessus : « Oui, prépare-le ».

**Aucun compte n'est nécessaire.** Les briques 05 (étapes comparaison et provenance de M4c) et 06 lisent déjà Zot en anonyme depuis l'hôte, avec `oras` 1.3.6 et `cosign` 3.1.4 de mise et la CA du PoC. [`o5-zot.sh`](../o5-zot.sh) fait de même, avec un `DOCKER_CONFIG` vide, ce qui prouve la lecture anonyme. **Rien n'est écrit dans Zot.** Écrire les attestations comme referrers demandera un accord à part : c'est le point 4 de la liste « Accords » du README.

**Ce que la lecture lève.** C'est la réserve 3 de la correction de 18:58:46 UTC ([o5-predictions.md](o5-predictions.md)) : le lien manifeste → fichier, jusqu'ici relu dans les journaux, est **recalculé** depuis les octets tirés de Zot. Ces octets sont contrôlés hors réseau par [`o5-zot-controle.py`](../o5-zot-controle.py), qui n'extrait rien sur le disque. La provenance de Chains, vérifiée par cosign avec la clé publique archivée, est ce que le service vérifiera avant de signer (D3 a).

**Ce qu'elle ne couvre pas** :
- les jetons d'horodatage (TSA) des enveloppes, que contrôle la porte ;
- la route de l'hôte vers OpenBao pour cosign `hashivault://`.

cosign tourne avec le réseau, puisqu'il doit joindre Zot. Qu'il contacte ou non un service public (TUF) avec `--key` et `--insecure-ignore-tlog` n'est pas mesuré ; la 05 a lancé la même commande.

**Banc hors réseau du contrôle** ([o5-zot-banc.sh](../o5-zot-banc.sh)) :
- **Premier passage**, à 19:57:17 UTC : 13 OK, 1 KO ([journal](o5-zot-banc-premier-passage.log)). Le défaut était dans le banc : le témoin « manifeste altéré » remplaçait `amd64`, absent du manifeste, et n'altérait donc rien.
- **Second passage**, à 19:57:26 UTC : 14 OK, 0 KO ([journal](o5-zot-banc.log)).
- **Cas couverts** : nominal ; contenu, nom ou nombre de membres faux ; couche gzip ; `diff_ids` faux ; manifeste altéré ; lien symbolique ; autre digest ; enveloppes d'un autre sujet ou en SLSA v0.2 ; aucune enveloppe.
- Le banc ne couvre ni `oras` ni `cosign`.

| N° | Prédiction | Confiance |
|---|---|---|
| G | Valeurs archivées relues ; clé publique de Chains (08) de sha256 `1e7b2a03…`, égal à `m4c-provenance.log` (05) ; CA présente | haute |
| Z1 | rpm : `oras cp` anonyme de `builds/sample-app-rpm@sha256:07b7bd6f…`, code 0. Layout : manifeste de ce digest, une couche tar non compressée égale aux `diff_ids`, un seul membre `sample-app-1.0.0-2.el9.x86_64.rpm`, de sha256 `864d55f4…` | haute : mesuré par la 05 le 18/11 (`m4c-comparaison.log`) |
| Z2 | deb : `oras cp` anonyme de `builds/sample-app-deb@sha256:60f25f5c…`, code 0. Même forme, un seul membre `sample-app_1.0.0-2_amd64.deb`, de sha256 `f66bbeb2…` | moyenne-haute : lecture anonyme du manifeste relevée par la 06 ; nom du membre jamais listé dans les journaux, la taille de couche (1 955 840 octets) étant cohérente avec un seul membre |
| P1 | rpm : `cosign verify-attestation` (clé de Chains, `slsaprovenance1`) : code 0, **4** enveloppes, toutes SLSA v1, sujet = `07b7bd6f…` | haute pour la validité ; moyenne pour le nombre (4 le 18/11 ; d'autres passages sur le même digest ont pu en ajouter) |
| P2 | deb : code 0, **8** enveloppes, toutes SLSA v1, sujet = `60f25f5c…` | haute pour la validité ; moyenne pour le nombre (`s4d3-chemins.log` : « 4 → 8 ») |
| T | Même vérification avec une clé jetable : refusée, motif « no matching attestations » | haute : mesuré par la 05 |
| K | Aucune ligne de bloc armuré dans le journal, aucune ligne KO, code 0 | haute |
