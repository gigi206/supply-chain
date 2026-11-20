# ADR 0003 : clés, signature (OpenBao, OpenPGP), horodatage, TUF

- **Statut** : **À rédiger**. Seules les deux sections ci-dessous sont écrites, reprises de la brique 09 (décisions du propriétaire du 19/11/2026). Restent la séparation des clés par usage, l'horodatage, TUF, la rotation, la révocation et la cérémonie.
- **Date** : 2026-11-20 (sections de la brique 09, écrites à 2026-11-20T00:14:01Z UTC)
- **Décideurs** : propriétaire du projet

Source : [`A-REPORTER.md` de la brique 09](../../poc/bricks/09-openpgp-signing/A-REPORTER.md), §4 bis et §4 ter, repris mot pour mot ; seule la mention « proposée, à confirmer » de la phrase de passe est remplacée par la décision du propriétaire (note du 19/11/2026 à 17:18:33 UTC).

### Clé OpenPGP des rpm, des deb et des dépôts : écart du PoC et recherche pour la production

Décision du propriétaire du 19/11/2026 (brique 09, D2) :

Pour le PoC, la clé OpenPGP des rpm, des deb et des dépôts est un fichier de clé (0600)
sur l'hôte d'administration, hors du cluster, comme la clé des tâches de J6. Le cluster
ne voit jamais la clé privée. OpenBao sert seulement à l'attestation de lien (clé Transit
« lien », D3), parce que Transit ne fait pas d'OpenPGP.

Ce choix ne vaut que pour le PoC. Il n'est pas acceptable en production :
- la clé est copiable : root sur l'hôte ou une sauvegarde suffit pour la récupérer ;
- l'hôte d'administration porte déjà d'autres secrets (clé des tâches, accès au cluster) ;
- aucun journal de signature ne vit à l'abri du signataire, et il n'y a ni quorum
  ni limite d'usage ;
- c'est un écart avec le doc 02, qui place le service de signature dans la zone Confiance.

Pour la production, une vraie solution reste à trouver. Elle doit garder la clé dans un
matériel dont elle ne sort pas, et passer par un service de signature isolé et journalisé.
Aucune voie actuelle n'est à la fois maintenue et compatible avec notre chaîne :
- un jeton matériel OpenPGP (YubiKey, Nitrokey) sur un hôte dédié marche avec gpg et
  rpmsign, mais il n'a pas été mesuré ;
- un HSM réseau en PKCS#11 n'a aucun pont maintenu vers gpg ;
- les services tout faits (sigul, debusine) sont écartés aujourd'hui.

Cet écart et cette recherche sont à reprendre avant toute mise en production.

Mesures d'appui (brique 09, relevé du 19/11/2026) : gnupg-pkcs11-scd 0.11.0 du 27/10/2024,
« Risqué » à la lettre ; moteurs signd_pkcs11 et signd_tpm d'obs-sign présents sur master
seulement, absents du tag 2.8.5 ; sigul sans tag après v1.4 (au plus tard le 22/04/2025) ;
debusine : clés OpenPGP sur HSM non faites (ticket 1099 ouvert) ; jeton matériel non mesuré.

### Racines de signature et phrase de passe (O2 de la brique 09)

Racines de signature (décision du propriétaire du 19/11/2026, « racines (a) », pour le PoC) :
l'outillage OpenPGP (gpg, rpm-sign, createrepo_c, apt-ftparchive, sqv) tourne sur l'hôte
d'administration, dans deux racines neuves construites depuis les dépôts signés figés
(vault/rocky/9.8 ; instantané Debian 20261105T000000Z), chaque image d'amorce ne servant
qu'une fois. Cible de production : racines produites par la plateforme, sans réseau, avec
leur provenance (même voie que la décision « C » de la brique 05, M1b).

Phrase de passe de la clé du PoC (décision du propriétaire du 19/11/2026, « Sans phrase de passe ») :
aucune. Compromis : une sauvegarde de l'hôte emporte une clé utilisable ; une phrase gardée
hors de l'hôte couvrirait ce cas, mais chaque signature la demanderait, et root sur l'hôte
pendant une signature la lirait quand même.
