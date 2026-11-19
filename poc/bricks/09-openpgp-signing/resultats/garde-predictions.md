# Brique 09 : prédictions du banc de la garde locale

Décision du propriétaire du 19/11/2026 : « Garde locale d'abord ». La garde `garde-cle-privee.sh` refuse toute ligne qui est l'en-tête de bloc de clé privée OpenPGP seul sur sa ligne (espaces et retour chariot tolérés autour), dans l'index et dans l'arbre de travail (fichiers suivis et non suivis non ignorés). Elle se lance avant chaque commit de la branche, en plus de `mise exec -- make reuse` et de `tools/secrets-depot.sh`. Elle ne touche aucun fichier partagé ; le §4 quater d'`A-REPORTER.md` (corrigé le 19/11/2026 à 16:48:49 UTC) reste à intégrer par la session principale.

Mise au point avant écriture : trois essais sur l'hôte, non archivés. Ils ne sont pas cités comme mesures et le banc refait ce qui compte (GB6, GB7). Ils ont orienté l'écriture : ancres `^…$` avec `-E`, faute d'option `-x` dans l'usage affiché par `git grep` ; pas de témoin interne, `git grep --no-index` ayant refusé `/dev/stdin`. Un code de `git grep` autre que 0 ou 1 donne donc KO (« contrôle impossible »).

Banc : `garde-banc.sh`, sur l'hôte, sans réseau ni installation. Clé jetable ed25519 du gpg de l'hôte (2.4.8), identité fictive sans adresse, sans phrase de passe, 1 jour, dans un GNUPGHOME sur tmpfs (`$XDG_RUNTIME_DIR/o9-garde-gnupg`) ; copie superficielle de la branche par `git clone file://` dans `~/.cache/supply-chain-poc/09/garde-banc`, effacée à la fin.

| N° | Prédiction | Confiance |
|---|---|---|
| GB0 | `$XDG_RUNTIME_DIR` est un tmpfs | haute |
| GB1 | Arbre réel de la branche : code 0. `A-REPORTER.md` (l.148) et `o2-interne.sh` (l.58) citent l'en-tête au milieu d'une ligne et ne sont pas refusés | haute |
| GB2 | Copie propre : code 0 | haute |
| GB3 | Clé privée en fichier non suivi : code 1, KO en `--untracked` seulement, le fichier nommé | haute |
| GB4 | Même fichier ajouté à l'index : code 1, KO en `--cached` et en `--untracked` | haute |
| GB5 | Fichier dans l'index seulement, retiré de l'arbre de travail : code 1, KO en `--cached` seulement | haute |
| GB6 | Clé indentée de quatre espaces à la fin d'un fichier suivi (`README.md` de la brique) : code 1 | haute |
| GB7 | Clé avec fins de ligne CRLF : code 1 | moyenne (`git grep` sur un fichier suivi, non mesuré avec CR hors `--no-index`) |
| GB8 | Clé publique seule : code 0 | haute |
| GB9 | Clé privée dans `__pycache__/` (ignoré par le `.gitignore` racine) : code 0. C'est une limite : un fichier ignoré n'est pas lu, il ne part pas non plus dans un commit sans `git add -f` | haute |
| GB10 | Dossier qui n'est pas un dépôt git : code 1 (« contrôle impossible ») | haute |
| GB11 | Aucun « BEGIN PGP » dans le journal (K3) | haute |
| GB11b | Aucune ligne de la clé privée jetable (16 caractères ou plus) dans le journal | haute |
| GB12 | GNUPGHOME et copie effacés à la fin | haute |

Limites connues, non testées comme refus : un export binaire (non armuré) n'est pas lu (`-I`) ; une clé recopiée sans sa ligne d'en-tête n'est pas vue ; la garde ne lit pas l'historique déjà commité.

## Résultat (note du 19/11/2026, 17:09:54 UTC)

Banc passé du 19/11/2026 à 17:09:24 au 19/11/2026 à 17:09:27 UTC, code 0 ([journal](garde-banc.log)) : **GB0 à GB12 tenues, GB11b comprise**. Garde de sha256 `3a83f89d35c4ea48…`, banc de sha256 `55efc5fb234f8e2d…`, sur le commit `36dbe85` des prédictions.
- GB1 : l'arbre réel passe. Le fichier non suivi compté est le journal du banc, en cours d'écriture.
- GB3 à GB7 sont refusés et la garde nomme le bon fichier. GB5 montre que la lecture de l'index compte : la clé n'y est que dans l'index, et `--untracked` ne la voit pas.
- GB7 (confiance moyenne) est tenue : la clé à fins de ligne CRLF est refusée.
- GB9 : la limite attendue est confirmée. Un fichier ignoré n'est pas lu.
- Pour une clé ed25519 jetable, l'export privé fait 11 lignes, dont 6 de 16 caractères ou plus, en-têtes exclus. Cette mesure ne vaut pas pour la clé RSA 4096 de `cle`. Elle confirme seulement qu'un export armuré compte des lignes courtes (§4 quater d'`A-REPORTER.md`).

Désormais, la garde se lance avant chaque commit de la branche, après `mise exec -- make reuse` et `tools/secrets-depot.sh`.
