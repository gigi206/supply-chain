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
