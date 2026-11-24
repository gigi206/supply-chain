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

## Résultat (note de 2026-11-24T20:02:05Z)

Les deux passages sont conformes du premier coup, dépôt `623a477c`.

**Passage 1, banc** ([journal](e3b-banc.log), 2026-11-24 à 20:01:07 UTC) : **26 cas, 0 écart**.

- L'exportateur qui vérifie donne les 187 valeurs attendues, les mêmes que le recalcul signé par cosign. Attestations : 24 vérifiées et 12 refusées, sujet par sujet et famille par famille comme cosign ; signatures d'image : 9 et 4.
- L'exportateur qui compte s'écarte sur **39 valeurs**, exactement celles prédites : taux L3 4/14 au lieu de 1/14, provenance 12/14 au lieu de 8/14.
- Une bonne clé dans le mauvais rôle est refusée ; une signature illisible est comptée et n'arrête ni l'exportateur, ni le recalcul : cosign a rendu des motifs que `recalcul.py` connaît, l'incertitude de la prédiction est levée pour ces trois formes.
- 9 arrêts sur 9 : code 2, motif attendu, fichier inchangé (openssl inutilisable compris).

**Passage 2, vrai Zot** ([journal](e3b-exportateur-zot.log), 20:01:21 UTC, depuis l'hôte) : **8 cas, 0 écart** ; recalcul du même passage : 10 cas, 0 écart.

- Clés du dépôt : **41 signatures vérifiées, 0 refusée** (37 attestations et 4 signatures d'image). Les signatures réelles de Chains, du scanner, des VEX et des VSA se vérifient par openssl seul.
- Clé étrangère : **0 vérifiée, 41 refusées** ; provenance, L3, replay et VEX à 0, séries de scan absentes.
- 56 valeurs comparées au recalcul signé : 0 écart.

**Ce que cela établit** : vérifier ne demande pas cosign. `/usr/bin/openssl` et les quatre clés publiques suffisent, sur l'hôte (OpenSSL 3.5.5, Python 3.14.4).

**Ce que cela n'établit pas** : voir « Ce que cela ne montrera pas ». En particulier, `openssl` sur `sc-stockage` n'est pas vérifié (image `debian-13-generic`, lu ; contenu non lu), l'unité durcie n'est pas exercée, et les délais des KEV restent non vérifiés dans les deux modes. L'ordre de grandeur du coût (41 appels d'openssl par passage) n'a pas été mesuré séparément.

Une correction de vocabulaire : en mode compté, les séries gardent les noms `…_verifie`. Si le choix est de ne pas vérifier, il faudra les renommer.

**Heures de l'essai** : de 19:55:31 à 20:02:05 UTC, 6 min 34 s. Total de la brique : 38 min 09 s.

## Relevé de santé d'OpenSSL, prédiction (2026-11-24T20:04:24Z)

Sur relecture du conseiller : openssl deviendrait une dépendance d'exécution de l'exportateur, et docs/04 n'a pas de verdict pour lui. [`sante-openssl.sh`](../sante-openssl.sh), lecture publique seule, commité avant le lancement. Attendu selon les critères de docs/04 : release de moins de 6 mois, au moins 3 auteurs de 2 domaines d'employeurs en 90 jours, SECURITY.md ou politique publiée, releases signées (fichiers `.asc`), Scorecard ≥ 6, corrections de sécurité suivies dans trixie. Verdict attendu : **Sain**. Le moins sûr : le score Scorecard (le plus ancien relevé possible de l'API) et la signature du tag.

### Résultat du relevé et corrections sur relecture (note de 2026-11-24T20:05:11Z)

[Journal](sante-openssl.log), 2026-11-24 à 20:04:25 UTC. Verdict attendu confirmé, avec deux points que la prédiction ne disait pas :

| Critère | Relevé |
|---|---|
| Release | 4.1.0 le 23/10/2026 ; 3.5.9 (série de Debian 13) le 29/09/2026 |
| Activité, 90 jours | 981 commits, 157 adresses d'auteurs ; openssl.org 12 auteurs, openssl.foundation 7, oracle.com 2, redhat.com 5, linux.ibm.com 2 ; premier auteur : 104 commits |
| Scorecard | 6,3 (relevé du 09/11/2026), Maintained 10, Signed-Releases 8, **Code-Review 0** |
| Releases signées | `.asc` et `.sha256` présents, signature non vérifiée ici ; tag annoté, clé inconnue de GitHub |
| Sécurité | **pas de SECURITY.md**, politique publiée sur le site du projet (HTTP 200) |
| Licence, CLA | Apache-2.0 ; CLA mentionné dans CONTRIBUTING.md |
| Debian 13 | trixie 3.5.9-1~deb13u1 ; **14 CVE ouvertes dans trixie** au security-tracker, non corrigées non plus dans forky ni sid |

Verdict proposé : **Sain**. Les titres des 14 CVE (tronqués, lus) parlent de QUIC, DTLS, CMS, DANE, AES-GCM-SIV, Suite B, `EVP_EncodeBlock` et `PEM_X509_INFO_read` ; aucun ne nomme la vérification ECDSA de `dgst -verify`. Les avis complets n'ont pas été lus.

**Corrections sur relecture du conseiller** :

1. **La réserve `sc-stockage` manquait dans l'ADR 0004** : ajoutée. Indices, lus, aucun n'est une mesure : `vm.sh` fait sortir `sc-stockage` et `sc-confiance` de la même image `debian-13-generic` ; `openbao.sh` l. 147 lance `sudo openssl` sur `sc-confiance` ; `ca-certificates` dépend d'`openssl` dans trixie (`03-deps-closure/resultats/banc-debian-simulation.log`). La mesure sera la première étape de la pose.
2. **Version non épinglée** : ce serait l'openssl du paquet Debian de la VM, hors `mise`, comme le Python de `entrees-scan`.
3. **Prix du mode vérifié : les clés.** Un rejeu recrée des clés. Des clés posées puis périmées donnent tout refusé et des KPI à 0, sans arrêt de l'exportateur (`kpi_signatures_refusees` le montre, aucune alerte ne le dit). La pose devra copier les 4 clés publiques, et l'étape 7 les reposer après chaque rejeu ou re-signature.
4. **Le code 1 d'openssl reste ambigu à un endroit** : le contrôle de départ exerce `openssl pkey`, pas `dgst -verify` par `/proc/self/fd`. Si ce chemin échouait sous l'unité durcie, tout serait refusé en silence. Réserve d'étape 4 : un vecteur de test embarqué (message, signature, clé), vérifié au départ, code 2 sinon.

**Heures** : de 20:02:05 à 20:05:11 UTC, 3 min 06 s. Total de la brique : 41 min 15 s.
