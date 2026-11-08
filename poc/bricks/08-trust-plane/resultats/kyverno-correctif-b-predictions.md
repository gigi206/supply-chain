# Correctif Kyverno, étape B : prédictions

Écrites le 08/11/2026 à 16:03 UTC, avant tout passage de l'étape `cli` de [`kyverno-correctif.sh`](../kyverno-correctif.sh). Préparation à sec sur accord du propriétaire (« Oui » à « Je prépare l'étape B maintenant (préparation à sec seulement), ou on attend la fin de W8 ? »). Le passage de `cli` lit Zot et demande un accord à part.

## Ce que B mesure

Les tests unitaires de l'étape A utilisent une TSA virtuelle dont la réponse n'embarque pas son certificat. Notre TSA réelle l'embarque. B fait juger les vrais bundles de J5 par trois CLI :
- le CLI officiel 1.19.2, comme témoin du jour ;
- le CLI construit depuis main `2be1bc3fe3b4` avec le correctif v2 ;
- le CLI construit depuis v1.19.2 `e63308f1e16c` avec le correctif v2.

Les cas, la politique (`ivpol` de `commun.sh`) et le pod sont ceux de J6 (`politique.sh`, cas `j5-*`).

## Préalables

- Lecture anonyme des referrers de l'image d'essai dans `horodatage/bundles` et `essais-j5/{sans-jeton,jeton-altere,autre-signature,tsa-etrangere}` : au moins un bundle dans chacun. `essais-j5/aucun` : affiché seulement.
- Si un dépôt est vide ou illisible (rétention de Zot, rejeu), l'étape s'arrête en **NON JUGÉ** (code 3), sans rien réécrire dans Zot.

## Prédictions

| Cas | CLI officiel 1.19.2 | CLI corrigés (main et v1.19.2) | Motif attendu des CLI corrigés (affiché, non jugé) |
|---|---|---|---|
| `j5-temoin` (bundle valide, sans `tsaCertChain`) | PASS | PASS | — |
| `j5-jeton-valide` | ERREUR (nil pointer, comme en J5 et J6) | **PASS** | — |
| `j5-sans-jeton` | FAIL | FAIL | aucun jeton vérifié (`threshold not met`, 0 < 1) |
| `j5-aucun-bundle` | FAIL | FAIL | aucun bundle |
| `j5-jeton-altere` | ERREUR | **FAIL** | `x509: ECDSA verification failure` (comme cosign en J5) |
| `j5-autre-signature` | ERREUR | **FAIL** | `hashed messages don't match` (comme cosign en J5) |
| `j5-tsa-etrangere` | ERREUR | **FAIL** | certificat embarqué différent de celui de la TSA configurée (cosign en J5 : « certificate embedded in the TSR does not match the provided TSA certificate ») |
| `j5-att-historique` (`.att`, sans `tsaCertChain`) | FAIL | FAIL | inchangé, défaut #17109 que le correctif ne touche pas |

- **Sortie verbeuse** : aucune occurrence de « nil pointer » avec les CLI corrigés. Avec le CLI officiel, une par cas ERREUR.
- **Jugement** : OK ou KO sur la décision seule (PASS, FAIL ou ERREUR) ; les motifs sont affichés.

## Confiance

- **Haute** pour le CLI officiel : ce sont les résultats de J5 et J6, à condition que les bundles n'aient pas changé.
- **Haute** pour `j5-jeton-valide` corrigé : même chemin que le test unitaire, sur le dépôt séparé (test `SeparateRepository`).
- **Moyenne** pour `j5-tsa-etrangere` corrigé. La décision FAIL est attendue (autre racine), mais le motif dépend de la vérification du certificat embarqué par sigstore-go, non lue.
- **Moyenne** pour le CLI main. La politique est en `policies.kyverno.io/v1` ; un changement d'API ou de CLI entre v1.19.2 et main donnerait un autre résultat sans rapport avec le correctif. Ce serait un CONSTAT à lire, pas un échec du correctif.

## Effets du passage de `cli` et pire cas

- **Effets** : lectures anonymes de Zot depuis l'hôte (referrers, manifestes, bundles) ; des lignes dans le journal d'audit de Zot. Rien n'est écrit dans Zot, le cluster ou les VM. Les fichiers temporaires vont sous `~/.cache/supply-chain-poc/08/travail/kyverno-correctif/`.
- **Pire cas** : dépôts absents ou Zot injoignable, donc NON JUGÉ, sans écriture.
- **Non couvert** : l'admission, prévue pour l'étape C, après W8.

## Additif du 08/11/2026, 16:09 UTC, avant tout passage de `cli` (relecture du conseiller)

> Heure du titre corrigée à 16:09 UTC, avant tout push : 16:12 avait été écrite par anticipation, l'heure relevée juste avant l'écriture était 16:09:33.

- **Témoins bloquants ajoutés** :
  - la chaîne `tsa-chaine.pem` du cache doit être identique à [`tsa-chaine.pem`](tsa-chaine.pem) ; c'est le cas en local, sha256 `e18e1214…`, archivée par `1f66a3c` le 06/11/2026 ;
  - cosign v3.1.4 doit accepter le bundle valide de `horodatage/bundles` avec son jeton (référence de J5, `verif_cosign` de `tsa.sh`) ;
  - le CLI officiel doit donner PASS sur `j5-temoin`.
  - Sinon, l'étape s'arrête en **NON JUGÉ** (code 3) avant tout jugement. Un KO des CLI corrigés reste ainsi imputable au correctif.
- **Prédiction ajoutée** : les trois témoins tiennent.
- **Sortie non reconnue** (`INDÉTERMINÉ`) : classée en CONSTAT, pas en KO, comme annoncé au § Confiance.
  - Vérifié en local, sans Zot : les trois CLI acceptent `--policy-report` et `--output-format json` et rendent le même `summary` sur une ValidatingPolicy triviale (pass 1, code 0 ; fail 1, code 1).
- **Garde** : entrée standard fermée sur chaque `kyverno apply`.
- **Compilation** : l'étape `construire` a été lancée à 16:03 UTC. Elle est locale et n'a rien lu dans Zot ([journal](kyverno-correctif-construire.log)). L'avoir rangée dans la « préparation à sec » accordée est une **interprétation**.
- **Volume du passage** : environ 3 × 8 × 2 appels du CLI, une vérification cosign et 6 lectures de referrers, en lectures anonymes. Cela fait quelques centaines de lignes d'audit dans le journal de sc-stockage (environ 15 Mo/h d'après P1), sans effet attendu sur W8 ni sur P3.

## Résultat (additif du 08/11/2026, 16:38 UTC)

Passage du 08/11/2026 à 16:38:13 UTC ([journal](kyverno-correctif-cli.log)) : les trois témoins bloquants tiennent ; **24 cas sur 24 conformes**, 0 KO, 0 CONSTAT ; les motifs des CLI corrigés sont ceux annoncés, y compris pour `j5-tsa-etrangere` (« certificate embedded in the TSR does not match »). Prédictions tenues.
