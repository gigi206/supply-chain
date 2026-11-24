# Brique 20, étape 3, complément : signatures vérifiées par openssl dans l'exportateur, prédiction

Prédiction écrite le 2026-11-24T20:01:05Z (`date -u`), commitée avant tout lancement : seuls un contrôle de syntaxe et le calcul de la table des attendus ont tourné. Sans accord : banc jetable, puis lecture anonyme de Zot et lectures habituelles du recalcul ; rien n'est posé, rien n'est téléchargé. Plan relu par le conseiller.

**Ce que cet essai ne tranche pas** : le choix du propriétaire « signatures par l'exportateur ». Le mode est obligatoire et explicite (`SIGNATURES=comptees` ou `verifiees`), sans valeur par défaut.

## Orientation, faite avant (2026-11-24 à 19:58:30 UTC, non archivée)

`/usr/bin/openssl` 3.5.5 de l'hôte (celui du PATH est le 4.1.0 de linuxbrew ; l'exportateur appelle le chemin absolu). Sur un message signé par une clé P-256 jetable, `dgst -sha256 -verify` rend 0 pour la bonne signature, lue dans un fichier ou dans un tube, et **1 dans tous les autres cas** : mauvaise clé, signature vide, pas du DER, octets en plus, clé illisible, clé absente, clé P-384. Une clé absente passerait donc pour une signature fausse : les clés sont contrôlées une fois au départ.

## Ce qui est écrit

- [`metrics_exporter.py`](../../../../tools/metrics-exporter/metrics_exporter.py) (`e8fd0f6e06193de0`, contre `b22c696cb22a9948` à l'étape 3) :
  - PAE DSSE calculé sur les octets décodés du `payload` et le `payloadType` de l'enveloppe ; une seule signature par enveloppe ;
  - signature d'image (`.sig`) : annotation vérifiée sur les octets de la couche ;
  - une clé par famille ; une signature fausse, vide ou illisible est comptée dans `kpi_signatures_refusees` (par famille) et n'arrête rien ; `kpi_enonces_refuses` reste le compte des refus de forme ;
  - clé absente, illisible ou pas P-256, openssl inutilisable, mode absent : code 2, fichier inchangé.
- [`banc.sh`](../banc.sh), [`banc_temoins.py`](../banc_temoins.py), [`banc_comparer.py`](../banc_comparer.py) (avec `recalcul.py`, `kpi.py` et l'exportateur : `9c57c96a39830053`) : 5 sujets témoins de plus, soit 14.
- [`exportateur-zot.sh`](../exportateur-zot.sh), [`comparer_zot.py`](../comparer_zot.py) : deux passages sur le vrai Zot, avec les clés du dépôt puis avec la clé étrangère `g6-temoin` à la place des quatre.

| Témoin ajouté | Contenu | Attendu, vérifié |
|---|---|---|
| `banc-mauvais-role` | provenance bonne ; scan signé par la clé de la VSA, VSA et VEX par celle du scanner | provenance 1 ; ni scan, ni VSA, ni VEX |
| `banc-role-prov` | `.att` et `.sig` signés par la clé des VEX | provenance 0, PipelineRun 0 |
| `banc-sig-forgee` | `.att` bon, `.sig` signé par une clé étrangère | provenance 0, PipelineRun 1 |
| `banc-illisible` | scan bon (1 KEV), puis scan plus récent à signature vide, VSA non DER, VEX non base64 | KEV ouverte 1, L3 0, VEX 0 |
| `banc-att-illisible` | `.att` : une couche bonne, une à signature vide ; `.sig` à annotation vide | provenance 0, PipelineRun 1 |

## Passage 1 : banc (journal `e3b-banc.log`)

Attendu, **26 cas, 0 écart** :

- **recalcul, 5 cas** : 14 sujets, 24 attestations vérifiées sur 36, 0 par la clé témoin, Loki cohérent ;
- **comparaison, 12 cas**, sur 187 valeurs écrites à la main : recalcul et exportateur vérifiant, 0 écart chacun avec les attendus et 0 entre eux ; exportateur qui compte, **39 écarts**, tous sur les 7 témoins à signature fausse et les 3 taux ; signatures d'attestations 24 vérifiées et 12 refusées, identiques au recalcul par sujet et famille ; signatures d'image 9 vérifiées et 4 refusées ; 0 refus de forme ; aucune série `kpi_signatures_*` en mode compté ;
- **arrêts, 9 cas** : code 2, motif attendu, fichier inchangé.

**Le moins sûr** : le recalcul. `cosign` n'a jamais vu ces signatures illisibles ; s'il rend un motif que `recalcul.py` ne connaît pas, il s'arrête (c'est voulu), et le passage est raté. Ce serait un constat sur le recalcul : un compte qui écrit dans `builds/vsa/**` pourrait l'arrêter. Le montage de `/dev/null` sur openssl dans l'espace de noms est aussi incertain.

## Passage 2 : vrai Zot, depuis l'hôte (journal `e3b-exportateur-zot.log`)

Les signatures du banc au format de Chains sont faites par openssl : les revérifier par openssl ne dit rien de celles de Chains (Transit). C'est ce passage qui tranche. Attendu, **8 cas, 0 écart** : 4 sujets, 56 valeurs égales au recalcul, 0 refus de forme ; comptes par sujet et famille égaux aux lignes `DETAIL` du même recalcul (pas de littéral : les scans tournent ; 37 attestations et 4 signatures d'image à 19:42:45 UTC) ; 0 signature refusée avec les clés du dépôt ; avec la clé étrangère, tout est refusé, toutes les séries restantes sont à 0 et les séries de scan absentes. Le recalcul du même passage : 10 cas, 0 écart.

Moins sûr : le nombre de signatures d'image. Le recalcul compte ce que `cosign verify` rend, l'exportateur les couches.

## Ce que cela ne montrera pas

- L'unité durcie de `sc-stockage` et son openssl (présence et version non vérifiées) : réserve du choix, elle bloque la pose, pas l'essai.
- Les délais des KEV : ils viennent des lignes de `entrees-scan`, qui ne vérifie pas les signatures, dans les deux modes.
- Le TSA : l'exportateur ne vérifie pas l'horodatage.
- Une attestation authentique retirée de Zot ou rejouée : la signature n'y change rien.
- Témoins, attendus et outils sont de la même session.

Heures : essai compté depuis 19:55:31 UTC.
