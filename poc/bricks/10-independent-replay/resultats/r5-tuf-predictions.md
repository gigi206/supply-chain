# R5, mesure préalable : cosign contacte-t-il le TUF public en vérifiant avec une clé ? (prédictions écrites le 03/11/2026 à 13:20 UTC)

Accord du propriétaire : « Oui, mesurer ». Mesure sur l'hôte seul, comme R1 : espace de noms réseau vide (`unshare -rn`, boucle locale seule), Zot, image et clés jetables, aucune connexion extérieure possible. Les **tentatives** sont relevées par `strace` (`connect`, `sendto`, `sendmsg`, `write`) : une résolution vers 127.0.0.53:53 ou une adresse hors de la boucle locale, ou le nom `tuf-repo-cdn.sigstore.dev`, vaut tentative. Chaque vérification est faite deux fois : `HOME` vide (aucun cache TUF) et `HOME` muni d'une copie du cache `~/.sigstore` de l'hôte (le vrai cache n'est pas touché).

Commandes mesurées, celles des étapes de R5 sur l'hôte :

- **V1** `cosign verify-blob-attestation --bundle … --new-bundle-format --key … --insecure-ignore-tlog --type <VSA> --digest … --digestAlg sha256` (`pousser_vsa`) ;
- **V2** `COSIGN_REPOSITORY=<dépôt séparé> cosign verify-attestation --key … --insecure-ignore-tlog --type <VSA> <image>` (`lire_vsa`, VSA en referrer fait main) ;
- **V3** `cosign verify --key … --insecure-ignore-tlog <image>` et **V4** `cosign verify-attestation --key … --insecure-ignore-tlog --type slsaprovenance1 <image>`, sur une image signée au format ancien (`.sig`, `.att`), comme l'image réelle (témoins de `lire_vsa`).
- **Témoin** : `cosign attest --key` sans configuration de signature. R1 l'a vu exiger le TUF ; la sonde doit y relever la résolution de `tuf-repo-cdn.sigstore.dev`.

Prédictions :

1. Le témoin montre une tentative vers 127.0.0.53:53 et le nom `tuf-repo-cdn.sigstore.dev` : la sonde voit ce qu'elle cherche.
2. V2, V3 et V4 (`--key`, `--insecure-ignore-tlog`, vérification par le registre) : **aucune** tentative hors de Zot, avec ou sans cache. R1 a vu `verify-attestation --key` réussir hors réseau ; cela ne prouve pas l'absence de tentative, d'où cette mesure.
3. V1 (`--new-bundle-format`, sans `--trusted-root`) : attente **incertaine**. cosign pourrait charger la racine de confiance du TUF pour un bundle v0.3. Si une tentative apparaît, les étapes de R5 sur l'hôte la portent sous `unshare -rn` ou avec `--trusted-root` local.
4. Toutes les vérifications réussissent hors réseau avec la bonne clé.

## Résultat du premier passage (03/11/2026, 13:21 UTC) : [`r5-tuf-premier-passage.log`](r5-tuf-premier-passage.log) (script : [`essais/tuf-verification-cle.sh`](../essais/tuf-verification-cle.sh)), extrait des traces [`r5-tuf-strace-premier-passage.txt`](r5-tuf-strace-premier-passage.txt)

| Commande | HOME vide | HOME avec copie du cache | Connexions à Zot vues |
|---|---|---|---|
| Témoin : `cosign attest` sans configuration | refus, **8** résolutions vers 127.0.0.53:53, `tuf-repo-cdn` dans les requêtes | idem | 0 |
| V1 `verify-blob-attestation --new-bundle-format` | réussi, **aucune** tentative | idem | 0 (aucun registre) |
| V2 `verify-attestation` par `COSIGN_REPOSITORY` | réussi, **aucune** tentative | idem | 3 |
| V3 `verify` (`.sig`) | réussi, **aucune** tentative | idem | 2 |
| V4 `verify-attestation` (`.att`) | réussi, **aucune** tentative | idem | 2 |

1. **Conforme.** La sonde voit ce qu'elle cherche : le témoin tente 8 résolutions de `tuf-repo-cdn.sigstore.dev`, puis échoue (`tuf refresh failed`), comme en R1.
2. **Conforme.** V2, V3 et V4 ne tentent aucune connexion hors de Zot, avec ou sans cache. Les connexions à Zot sont bien relevées (2 ou 3 par commande), ce qui montre que l'absence d'autres connexions n'est pas un défaut de la sonde.
3. **Levée, sans tentative.** V1, avec `--new-bundle-format` et sans `--trusted-root`, ne tente rien non plus : ni registre, ni TUF.
4. **Conforme.** Les huit vérifications réussissent hors réseau avec la bonne clé.

**Constat annexe** : après les sondes, `.sigstore/root/tuf-repo-cdn.sigstore.dev/root.json` est écrit dans le `HOME` vide et réécrit dans la copie du cache. C'est une écriture locale, sans connexion ; la commande qui l'écrit n'est pas isolée par cette mesure (le témoin passe en premier). C'est le même phénomène que l'écriture de `root.json` relevée pendant R1.

**Conséquence pour R5** : les étapes sur l'hôte (`pousser_vsa`, `lire_vsa`) peuvent garder le réseau, puisque ces vérifications par clé ne contactent pas le TUF public. Dans la VM, `unshare -rn` reste une précaution, et son fonctionnement pour l'utilisateur `replay` n'est toujours pas mesuré.

**Défaut du premier passage du script**, corrigé avant tout commit : l'extrait des traces s'arrêtait au premier fichier sans connexion (V1, `grep` sans résultat sous `set -e`), et le dossier jetable n'était pas supprimé. Le journal était complet. L'extrait a été refait à partir des mêmes traces brutes, puis le dossier jetable a été supprimé à la main. Le script s'appelait alors `mesure-tuf.sh`, à la racine de la brique (nom cité par le journal) ; il a ensuite été rangé dans `essais/` avec les autres essais de R5.

## Additif du 03/11/2026 à 13:23 UTC, avant le second passage : les refus aussi

Le premier passage ne mesure que des vérifications **réussies**. Or `lire_vsa` vérifie aussi des refus : N3, la VSA avec la clé de Chains et la provenance avec la clé de VSA. Une vérification qui échoue pourrait tenter autre chose, par exemple le TUF ou un repli. Le second passage ajoute une seconde paire de clés jetable (`autre`) et des sondes avec cette clé : V1, V2, V3 et V4, sous les deux `HOME`. Il est fait avec le script archivé, corrigé, dont le journal remplace le premier comme journal de référence.

Prédictions :

5. Avec la clé `autre`, V1 à V4 sont **refusées**, et ne tentent **aucune** connexion hors de Zot, avec ou sans cache.
6. Les résultats du premier passage se reproduisent : témoin à 8 résolutions, V1 à V4 réussies sans tentative avec la bonne clé.

## Résultat du second passage (03/11/2026, 13:24 UTC) : [`r5-tuf.log`](r5-tuf.log), extrait des traces [`r5-tuf-strace.txt`](r5-tuf-strace.txt)

Le passage a été fait avec le script archivé : le journal provient bien de ce script. Le dossier jetable a été supprimé par le script.

5. **Conforme.** Avec la clé `autre`, V1 à V4 sont refusées sous les deux `HOME`, sans aucune tentative hors de Zot. Les connexions à Zot sont relevées comme avec la bonne clé : 0 pour V1, 3 pour V2, 2 pour V3 et V4. Les motifs de refus sont ceux d'une clé qui ne correspond pas :
   - V1 et V2 : `accepted signatures do not match threshold, Found: 0, Expected 1` ;
   - V3, code 12 : `invalid signature when validating ASN.1 encoded signature` ;
   - V4 : `no matching attestations … Found: 0, Expected 1`.
6. **Conforme.** Le témoin donne 8 résolutions de `tuf-repo-cdn.sigstore.dev` sous les deux `HOME`. V1 à V4 réussissent avec la bonne clé, sans tentative. `root.json` est écrit comme au premier passage.

**Conséquence pour R5, confirmée** : sur l'hôte, `pousser_vsa` et `lire_vsa`, refus de N3 compris, ne contactent pas le TUF public. Le banc diffère toutefois de R5 : HTTP sur 127.0.0.1 avec une copie de `HOME`, alors que R5 passera en TLS vers 192.168.161.13 avec le vrai `~/.sigstore`. Le relevé des `connect()` par `strace` prévu dans l'additif de 13:13 est donc maintenu pendant R5.
