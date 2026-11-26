# Chains v0.30.0 : banc de signature et de stockage, prédiction

Note de 2026-11-26T08:24:53Z, écrite avant le premier lancement. Suite du [banc à sec du format](chains-v0300-predictions.md), qui laissait non mesurés la signature et le stockage. Choix de l'étape : réponse du propriétaire « Comme tu veux mais avance » (26/11), puis « Continue ». Le banc ne télécharge rien, ne touche ni au cluster, ni aux VM, ni au vrai Zot, et ne signe qu'avec une clé jetable qu'il crée lui-même : aucun accord nommé n'est engagé.

## Montage

- Programme [`main.go`](../essais/chains-v0300-signature/main.go), copié tel quel dans les sources en cache de v0.29.9 (`89219ea5`, témoin) et de v0.30.0 (`b59bced2`), puis compilé hors réseau (Go 1.27.3, `-mod=vendor`, `GOPROXY=off`).
- Il appelle `ObjectSigner.Sign`, c'est-à-dire le chemin qu'emprunte le contrôleur, sans le contrôleur lui-même. Les objets sont les vrais PipelineRun et TaskRuns de `j7-sample-app` capturés pour le banc à sec (`preparer`, `construire`, `publier`).
- Configuration : celle de [`chains-config.yaml`](../tekton/chains/chains-config.yaml) (slsa/v2alpha4, stockage oci en dsse, simplesigning, recherche approfondie, sans transparence). Seul changement : le signataire `x509` avec une clé cosign jetable remplace `kms`.
- Registre en mémoire (`go-containerregistry/pkg/registry`) sur 127.0.0.1. L'hôte et le digest d'origine sont remplacés dans les objets par ceux d'une image aléatoire poussée par le banc. Les clients Kubernetes et Tekton sont des faux en mémoire.
- [`banc.sh`](../essais/chains-v0300-signature/banc.sh) vérifie ce qui est stocké avec cosign 3.1.4 (mise) : signature simplesigning, attestations `slsaprovenance1`, noms des dépendances `pipeline*`. Il rejoue ensuite le même appel avec un dossier de clé vide (cas « aucun signataire »).
- Empreintes au moment de la note : `main.go` `8c0e51f0b2f8837e`, `banc.sh` `d4d525d7fc66af10`. Journal : `chains-v0300-signature.log`.

## Prédictions

| | Prédiction | Confiance |
|---|---|---|
| S1 | Les deux versions : `Sign` sans erreur pour le PipelineRun et les trois TaskRuns | moyenne (les TaskRuns sans image sont signés en service, mais le faux client et le registre en mémoire ne sont pas éprouvés) |
| S2 | Les deux versions : `cosign verify` de la signature simplesigning réussit | moyenne (cosign 3 avec une signature à l'ancien format, sans journal de transparence) |
| S3 | Les deux versions : `cosign verify-attestation --type slsaprovenance1` réussit, avec le même nombre d'attestations vérifiées, au moins deux (PipelineRun et `publier`) | moyenne |
| S4 | Noms : v0.29.9 n'écrit que `pipelineTask` ; v0.30.0 écrit `pipelineTask/preparer`, `pipelineTask/construire` et `pipelineTask/publier`, comme au banc à sec. Le stockage ne change pas le contenu | bonne |
| S5 | Objets annotés `chains.tekton.dev/signed` dans les deux versions | bonne |
| S6 | Aucun signataire, dans les deux versions : `Sign` rend une erreur « no signer x509 configured » pour chaque objet ; le Recorder ne compte aucune erreur (`recordError` absent sur ce chemin, connu) ; pas d'annotation `signed` ; rien n'est attaché à l'image | moyenne |

Un KO de montage (code non nul hors des cas prédits, `main.go` différent de celui du dépôt) invalide le passage : il sera gardé, corrigé, puis relancé avec `SUFFIXE=-2`.

## Non couvert

- Le signataire KMS (Transit d'OpenBao) : la clé jetable le remplace.
- Le contrôleur réel (informateurs, réconciliation, nouvelles tentatives dans le temps).
- Zot : on utilise un registre en mémoire.
- La porte (`ec validate image`) et `ivpol` face à un énoncé réellement signé par v0.30.0 : c'est la mesure suivante, qui pourra partir de ce registre.
- La transparence (désactivée en service).

## Premier passage, non valable (note de 2026-11-26T08:26:08Z)

[Journal](chains-v0300-signature.log), lancé à 08:25:16Z : 2 KO, tous deux dus au montage, pas à Chains.

- Le programme n'importait pas `pkg/chains/formats/all`, que le contrôleur importe dans `pkg/reconciler/*/controller.go`. Aucun format n'était donc enregistré (« Format slsa/v2alpha4 … was not found ») et aucune attestation n'a été produite. Seule la signature simplesigning existait, et `cosign verify` l'a validée dans les deux versions.
- Les objets ont été capturés après leur signature en service : ils portaient déjà `chains.tekton.dev/signed` et les finaliseurs de Chains. Le cas « aucun signataire » ne pouvait donc rien montrer sur l'annotation.
- Une indication à confirmer au second passage : sans signataire, v0.29.9 ne rend aucune erreur pour l'image (simplesigning), tandis que v0.30.0 rend « no signer x509 configured for oci ». C'est le changement b1c0af9 (« échec ouvert »).

Corrections dans `main.go` (`76e03e674842ed47`) : import de `formats/all` ; retrait, à la lecture, des annotations `chains.tekton.dev/*` et des finaliseurs `chains.tekton.dev*` ; registre sans journal HTTP. Prédictions inchangées. Second passage : `SUFFIXE=-2`.

## Résultat (note de 2026-11-26T08:26:59Z)

[Journal du second passage](chains-v0300-signature-2.log), lancé à 08:26:20Z sur `1cb99f0a` : 0 KO. `main.go` est identique dans les deux sources ; cosign v3.1.4.

| Prédiction | Verdict |
|---|---|
| S1 | **Tenue** : les deux versions signent le PipelineRun et les trois TaskRuns sans erreur. Recorder : `mrcount` 4, `sgcount` 5, `stcount` 5 dans chaque version, aucun avertissement dans le journal de Chains |
| S2 | **Tenue** : `cosign verify` de la signature simplesigning réussit dans les deux versions |
| S3 | **Tenue** : deux attestations vérifiées dans chaque version, celle du PipelineRun et celle de `publier` (dépendance `task`). Les TaskRuns `preparer` et `construire` sont signés mais n'ont pas de sujet, et rien n'est attaché à l'image pour eux (5 stockages comptés, 2 attestations sur l'image) |
| S4 | **Tenue** : v0.29.9 écrit `pipeline`, `pipelineTask` ×3 ; v0.30.0 écrit `pipeline`, `pipelineTask/preparer`, `pipelineTask/construire`, `pipelineTask/publier`. Le reste des dépendances est identique (`inputs/result` ×4). Le renommage du banc à sec se retrouve donc dans l'énoncé **signé et stocké** |
| S5 | **Tenue** : les quatre objets sont annotés `chains.tekton.dev/signed` dans les deux versions |
| S6 | **Tenue pour v0.30.0, non tenue pour v0.29.9 (erreur de prédiction)**. v0.30.0 : `Sign` rend « no signer x509 configured » pour chacun des quatre objets ; seule l'annotation `chains.tekton.dev/retries: "0"` est posée, sans `signed` ; le Recorder ne compte rien, aucune erreur comprise ; rien n'est attaché à l'image. v0.29.9 : `Sign` ne rend **aucune** erreur, les quatre objets sont marqués `signed: "true"` (`mrcount` 4) et rien n'est attaché à l'image. C'est l'échec ouvert déjà mesuré en service en O4 de la 19 (02/11/2026, signataire KMS injoignable). La prédiction l'avait oublié |

**Ce que le banc établit.** Avec la configuration en service (hors signataire), v0.30.0 signe et stocke comme v0.29.9 : mêmes compteurs, mêmes attestations vérifiables par cosign. Seuls les noms `pipelineTask/<nom>` changent, cette fois dans l'énoncé signé. Le cas « aucun signataire » échoue **fermé** en v0.30.0 (`b1c0af9`, #1834) : c'est la **première mesure** de ce correctif, jusqu'ici lu à la source seulement. En revanche, aucune erreur n'est comptée par le Recorder : `recordError` reste absent sur ce chemin, comme la lecture du code l'annonçait. Le compteur `signing_failures` ne voit donc pas ce cas. Les objets n'ont que `retries`. C'est le contrôleur qui pose ensuite `signed=failed`, après ses tentatives ; le premier volet d'A2 (19) voit cette annotation, mais le banc n'exerce pas cette étape.

**Ce qui bloque toujours la montée** : la porte et `ivpol` ne connaissent que `pipelineTask` (banc à sec : la porte refuse l'énoncé neuf). Les patchs de `genre()` de la 20 ne sont pas appliqués.

Non couverts, inchangés : signataire KMS, contrôleur réel, Zot, `ec validate image` sur ces attestations signées, transparence.

Heures (2026-11-26, `date -u`) : de 08:15:55 (premier relevé, avant l'orientation) à 08:26:59 (cette note), soit 11 min 04 s. Ce temps couvre l'orientation, le programme, le script, la prédiction, les deux passages et les notes.

## Relecture du résultat et passage -3, prédiction (note de 2026-11-26T08:30:28Z)

Relecture par le conseiller : trois phrases du résultat disaient plus que le journal.

1. « Première mesure de `b1c0af9` » : faux. En O4 de la 19 (02/11/2026), une image d'essai v0.29.9 + #1834 + correctif maison, sous le vrai contrôleur, a fini avec quatre objets `signed=failed`. Le neuf ici est la mesure **sur la release v0.30.0**, au niveau d'`ObjectSigner.Sign`. Phrase corrigée dans docs/03, docs/04, l'ADR 0000 et le README de la 19 (textes de ce jour, non poussés).
2. « Seuls les noms `pipelineTask/<nom>` changent » : le second passage n'a relevé que les noms `pipeline*`, sans comparer les énoncés. Le banc à sec avait aussi trouvé les `byproducts` renommés. D'où le passage -3.
3. « `preparer` et `construire` n'ont pas de sujet » : c'était déduit. C'est désormais lu : `.subject | length` vaut 0 pour ces deux TaskRuns et 1 pour `publier`, dans les sorties à sec de v0.30.0.

Autres points :
- « 0 KO » ne couvrait que les codes de sortie, et S3 à S6 ont été lus à l'œil.
- La borne de 08:26:59 précède les notes des docs et le commit `1f24daf5`.
- `storage.oci.encoding-format` existe toujours sous ce nom dans v0.30.0 (`config.go`, l. 195).

**Passage -3** (`banc.sh` `0fbc5a6c67abe0f7`, `main.go` inchangé) : mêmes appels, plus 17 contrôles mécaniques.
- Les constats S3 à S6 deviennent des `attendu`. Pour v0.29.9 sans signataire, la valeur attendue est l'échec ouvert déjà mesuré.
- L'énoncé signé du PipelineRun et celui de `publier` sont comparés à la sortie du banc à sec de la même version (`sorties/j7-sample-app.<v>.json`, `sorties/tr-j7-sample-app-publier.<v>.json`).
- Normalisation des deux côtés : `content` décodé, annotations et finaliseurs `chains.tekton.dev*` retirés. Côté signé seulement, l'hôte et le digest du banc sont remis à ceux d'origine, après décodage.

| | Prédiction | Confiance |
|---|---|---|
| T1 | Tous les contrôles repris de S1 à S6 sont OK dans les deux versions | haute (même code, mêmes entrées) |
| T2 | Pour chaque version, l'énoncé signé du PipelineRun est égal à la sortie à sec. Si un écart apparaît, il se limite aux `digest` des trois dépendances `pipelineTask*`, au cas où ils seraient calculés sur le contenu, que le banc a nettoyé | moyenne |
| T3 | Pour chaque version, l'énoncé signé de `publier` est égal à la sortie à sec, avec la même réserve | moyenne |

Avec T2 tenue, le refus de la porte mesuré à sec sur la sortie de v0.30.0 vaut pour l'énoncé que v0.30.0 signe et stocke.

## Passage -3 (note de 2026-11-26T08:31:26Z)

[Journal](chains-v0300-signature-3.log), lancé sur `c0849369` : 25 OK, 4 KO.

**T1 : tenue.** Tous les contrôles repris de S1 à S6 sont OK, dans les deux versions. Cela comprend l'échec ouvert de v0.29.9 et l'échec fermé de v0.30.0 sans signataire, que le Recorder ne compte pas.

**T2 et T3 : non décidées.** Les 4 KO viennent de la normalisation du banc, pas de Chains :
- l'annotation `chains.tekton.dev/signed` est recopiée par Chains dans `internalParameters.annotations`, que le banc ne nettoyait pas ;
- le `content` des `byproducts` est lui aussi en base64 et contient l'hôte ;
- le digest du sujet est écrit sans le préfixe `sha256:`, alors que le remplacement exigeait ce préfixe.

Les écarts affichés touchent ces seuls chemins, dans les deux versions. Ils sont tronqués à 20 lignes : le reste n'est pas vu.

Correction : `banc.sh` `6f9c4e1ed98f2d08`. Il nettoie `internalParameters.annotations`, décode le `content` des `byproducts` en texte, remplace le digest sans son préfixe et affiche 40 lignes d'écart. Prédictions T2 et T3 inchangées. Passage -4.

## Passage -4, résultat (note de 2026-11-26T08:32:09Z)

[Journal](chains-v0300-signature-4.log), lancé sur `47ed100b` : 29 OK, 0 KO.

| Prédiction | Verdict |
|---|---|
| T1 | **Tenue**, comme au passage -3 |
| T2 | **Tenue** : dans chaque version, l'énoncé signé et stocké du PipelineRun est égal, après normalisation, à la sortie du banc à sec. La réserve sur les `digest` ne s'est pas présentée |
| T3 | **Tenue** : de même pour `publier` |

**Témoin de la comparaison**, relu à 08:31:54Z dans le dossier de travail du passage -4, hors journal. Écarts de chemins scalaires :
- énoncé signé de v0.29.9 contre sortie à sec de v0.30.0 : 18 ;
- énoncé signé de v0.30.0 contre sortie à sec de v0.29.9 : 18 ;
- énoncé signé de v0.30.0 contre sa propre sortie à sec : 0.

La normalisation laisse donc voir les écarts réels. Entre les deux énoncés signés, les 18 lignes portent uniquement sur des noms : ceux de 3 dépendances (`pipelineTask` devient `pipelineTask/<nom>`) et ceux de 6 `byproducts` (`taskRunResults/<TaskRun>/…` devient `taskRunResults/<tâche du pipeline>/…`).

**Bilan du banc.** Avec la configuration en service, et hors signataire KMS, contrôleur et Zot :
- v0.30.0 signe et stocke comme v0.29.9 ;
- son énoncé signé ne diffère de celui de v0.29.9 que par ces noms ;
- il est égal à la sortie du banc à sec. Le refus de la porte mesuré à sec vaut donc pour ce que v0.30.0 signerait réellement.

Sans signataire, v0.30.0 échoue fermé, et v0.29.9 échoue ouvert, comme en O4. Aucune des deux ne compte d'erreur dans le Recorder.

La montée reste bloquée par la porte, `ivpol`, les scripts et `genre()` de la 20 (patchs non appliqués).

Heures (2026-11-26, `date -u`) : de 08:15:55 (premier relevé, avant l'orientation) à 2026-11-26T08:32:09Z (cette note), soit 16 min 14 s. Ce temps couvre l'orientation, le programme, le script, les quatre passages, la relecture et les notes.
