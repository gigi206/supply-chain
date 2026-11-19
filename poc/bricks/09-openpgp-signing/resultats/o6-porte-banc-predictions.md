# Brique 09, O6-M0 : la porte actuelle sur des copies de `signes/**` (prédictions écrites le 19/11/2026, avant tout lancement)

Script : [`o6-porte-banc.sh`](../o6-porte-banc.sh). Carte : [`o6-carte.md`](o6-carte.md).

## Banc

- **Objets** : les quatre objets définitifs d'O5, tirés en lecture anonyme du Zot du PoC avec leurs referrers (`oras cp -r`) :
  - `signes/sample-app-rpm@fa5b1757…` ;
  - `signes/sample-app-deb@60f25f5c…` ;
  - `signes/depot-rpm@ed666ab8…` ;
  - `signes/depot-apt@90909a86…`.
- **Lieu** : un Zot jetable (127.0.0.1:15000), dans un espace de noms réseau vide (`unshare -rn`), comme la mesure R5 de la brique 10.
- **ec** : celui de l'hôte, d'empreinte égale à celle de l'image de la porte (`895c6f7e…`). La politique de la porte de la 08 est réécrite en chemins locaux : bibliothèque `conforma/policy` au commit `ebd3fbd2`, plus `porte.rego` et `taches.yml` du dépôt. ec est lancé par `--image`, comme en J6, sans source attendue.
- **Clés** : publiques, archivées. Clé de Chains : `08/resultats/chains-cle-publique.pem`. Clé `lien` : `resultats/lien-cle-publique.pem`.
- **Ce qui n'est jamais fait** : écrire dans le Zot du PoC ou dans le cluster, lire le secret `lien`, ouvrir une redirection de port.

## Prédictions

| # | Prédiction | Confiance |
|---|---|---|
| M0-1 | **Copie fidèle.** Pour chaque objet, le digest servi par le Zot jetable est égal à celui du Zot du PoC. Chaque objet a exactement un referrer, de type `application/vnd.dev.sigstore.bundle.v0.3+json`, dans les deux Zot. | Haute : objets poussés par digest en O5 ; un referrer par objet, vu par `verifier` |
| M0-2 | **ec, clé de Chains.** Pour les quatre objets : `success` faux, 0 signature d'image, 0 attestation, et des violations comprenant `builtin.image.signature_check` et `builtin.attestation.signature_check`. | Haute : aucune signature de Chains dans `signes/**` ; même mécanisme qu'en R5 (bundle en referrer, autre clé) |
| M0-3 | **ec, clé `lien`.** Pour les quatre objets, `success` faux. | Haute : aucune provenance SLSA, et la collection `@slsa3` en exige une |
| M0-4 | **Détail de M0-3, lu sans pari ferme.** Je relève si `builtin.image.signature_check` passe avec la clé `lien`, si l'attestation de lien est comptée parmi les attestations, et quelles violations restent. | Faible : R5 suggère que la vérification de signature d'image cherche dans le bundle, mais ce cas n'a jamais été mesuré avec la bonne clé |
| M0-5 | **cosign, clé `lien`.** `cosign verify-attestation --new-bundle-format --key lien --type https://supply-chain.example/lien-openpgp/v1` accepte chaque objet, avec exactement une enveloppe. | Haute : déjà mesuré en O5 (`verifier`) sur le Zot du PoC |
| M0-6 | **cosign, clé de Chains.** La même commande avec la clé de Chains refuse les quatre objets. | Haute |
| M0-7 | ec rend le code 0 à chaque passage (`--strict=false`), et sa sortie JSON est lisible. | Moyenne-haute : vrai en R5 ; jamais mesuré sur un artefact qui n'est pas une image et n'a aucune provenance |

## Suites selon le résultat

- **M0-3 tenue, et ec ne voit pas l'attestation de lien comme une attestation vérifiée** : la voie P de la carte passe par un conteneur `sh`, sur le modèle de `vsa.sh`.
- **ec voit l'attestation de lien avec la clé `lien`** : une seconde politique ec, qui n'inclurait que des règles du lien, devient possible. Je l'écris comme variante de P dans la carte, sans la retenir.
- **M0-1 non tenue** : le banc n'est pas valable, et rien d'autre n'est lu.

## Résultat (passage du 19/11/2026, 21:09:53 à 21:10:00 UTC, code 0) : [`o6-porte-banc.log`](o6-porte-banc.log)

*Note datée du 19/11/2026, 21:10:29 UTC.* Un seul passage, toutes les prédictions sont tenues.

- **M0-1, tenue.**
  - Chaque objet a été copié par son digest (`oras cp -r`). Le Zot jetable sert le même digest.
  - Chaque objet a un seul referrer `application/vnd.dev.sigstore.bundle.v0.3+json`, au même digest dans les deux Zot (`92f57eb4…`, `65f79e14…`, `a79de57b…`, `6a0263b0…`).
  - Le banc est valable, dans un espace de noms où seul `lo` existe et sans aucune route.
- **M0-2, tenue.** Avec la clé de Chains et pour les quatre objets, ec rend `success` faux, 0 signature et 0 attestation. Il signale deux violations, `builtin.attestation.signature_check` et `builtin.image.signature_check`, et aucun succès.
- **M0-3, tenue.** Avec la clé `lien`, ec rend `success` faux pour les quatre objets.
- **M0-4, lecture.** Avec la clé `lien`, pour les quatre objets :
  - ec compte **1 attestation**, de type `https://in-toto.io/Statement/v0.1`, au prédicat `https://supply-chain.example/lien-openpgp/v1`, avec une signature ;
  - `builtin.image.signature_check`, `builtin.attestation.signature_check` et `builtin.attestation.syntax_check` réussissent, alors qu'ec compte **0 signature d'image**. C'est le comportement que la règle `porte.image_signature` de la 08 refuse déjà (banc C). Il se reproduit ici avec un bundle v0.3 ;
  - il reste cinq violations, toutes dues à l'absence de provenance de Chains et de signature d'image : `attestation_type.pipelinerun_attestation_found`, `porte.image_signature`, `porte.taches_vues`, `slsa_source_correlated.attested_source_code_reference` et `slsa_source_correlated.source_code_reference_provided` ;
  - 30 succès.
- **M0-5, tenue.** `cosign verify-attestation --new-bundle-format`, avec la clé `lien` et le type lien, rend le code 0 et une enveloppe pour chaque objet.
- **M0-6, tenue.** Avec la clé de Chains, la même commande rend le code 1 (« Found: 0, Expected 1 »).
- **M0-7, tenue.** ec rend le code 0 aux huit passages, et son JSON est lisible. Aucune récupération d'image n'échoue : il n'y a pas de provenance, donc aucun bundle de tâches à tirer.

**Suite** : on est dans le second cas de la section « Suites ». ec voit l'attestation de lien comme une attestation vérifiée quand on lui donne la clé `lien`. La voie P a donc deux formes possibles :
- un conteneur `sh` sur le modèle de `vsa.sh` ;
- un passage de plus d'ec, avec une politique qui n'inclut que des règles du lien, écrites en rego sur `input.attestations`.

Je les écris dans la carte sans en retenir aucune. Ce banc n'a rien mesuré au-delà : ni règle rego du lien, ni Job réel.
