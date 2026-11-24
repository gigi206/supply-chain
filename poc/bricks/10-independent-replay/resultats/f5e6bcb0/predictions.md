# Brique 10 : VSA de `f5e6bcb0` (brique 07c), prédictions

Prédiction écrite le 2026-11-24T15:04:01Z, avant tout lancement. Heures comptées dans la 07c.

## Cible

- **Image** : `builds/sample-app@sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7`.
- **Provenance rejouée** : PipelineRun `j7-sample-app` du passage 2 de la 07c, `INVOCATION=9539952b-07a7-4a0b-a6e1-084304d0e8af`.
  - Il a tourné de 13:26:44 à 13:27:42 UTC le 24/11/2026.
  - Ces valeurs ont été lues le 24/11 vers 15:00 UTC dans l'énoncé du tag `.att`, en lecture anonyme et sans vérifier la signature. R3 la revérifie.
  - L'image porte 3 autres provenances de PipelineRun :
    - `84b0b219`, passage 1 de J7 ;
    - `caa325eb` et `464e58b9`, chemins 1 et 2 de la bascule.
- **Ce qui a déjà été vérifié sur l'hôte** :
  - `cosign verify-attestation` accepte les enveloppes de `f5e6bcb0` avec la clé de Chains versionnée (`08-trust-plane/resultats/chains-cle-publique.pem`, commit du 23/11) ;
  - 8 bundles horodatés de `f5e6bcb0` existent dans `horodatage/bundles`.
- **Toolchain du domaine** : `go1.26.11.linux-amd64.tar.gz`. go.dev publie le sha256 `9849f4e04ee35303714e34fbc3ac8ab44ea3e448a95aa182f91e3b9b79c710ec` et une taille de 66 999 944 octets (JSON lu le 24/11).
- **24 h** : R4 (`replay.sh` le refuse avant) pas avant le **2026-11-25T13:27:42Z**.
- **Politique** : `politique-replay.md` et `outils/` sont inchangés depuis `6c44219` (`git log 6c44219..HEAD` est vide), donc `POLITIQUE_COMMIT=6c44219`.

## Lancement

Toutes les étapes s'appellent ainsi, depuis la racine du dépôt (les défauts de `replay.sh` restent ceux de `3a7ca1b1`) :

```
RESULTATS=poc/bricks/10-independent-replay/resultats/f5e6bcb0 \
IMAGE=builds/sample-app@sha256:f5e6bcb0e0fb4c88608f5d6148b2825c970184537b2a0f622fead335cfe7e7c7 \
INVOCATION=9539952b-07a7-4a0b-a6e1-084304d0e8af FIN_BUILD=2026-11-24T13:27:42Z \
GO_ARCHIVE=go1.26.11.linux-amd64.tar.gz GO_SHA256=9849f4e04ee35303714e34fbc3ac8ab44ea3e448a95aa182f91e3b9b79c710ec \
DISTRO=rke2 RESEAU=cilium JALON=<jalon> mise run replay -- <étape>
```

## Prédictions par étape

| Étape | Accord | Prédiction |
|---|---|---|
| R1 `version_go` (hôte, lecture anonyme) | aucun | Entrée `plateforme/builder-go-voie-d@sha256:8c11e856…`, manifeste OCI, 1 couche, `usr/local/go/VERSION` = `go1.26.11`, version retenue `go1.26.11` |
| `go-domaine.sh` de la 07c (hôte, téléchargement) | **téléchargement** | 13 cas, 0 écart : sha256 et taille de go.dev égaux aux valeurs ci-dessus, et identiques sur l'archive téléchargée ; ziphash du module = `h1:KyINmJ/…` ; 0 fichier commun de contenu différent ; `bin/go`, `gofmt`, `compile`, `link` et `VERSION` identiques ; archive gardée. Comme pour 1.26.10 : seuls des `_go.mod` restent propres au module (0 hors `_go.mod`), l'archive a en plus surtout `test/` |
| R2 `outils` (VM `sc-replay`) | **action sur la VM** | 5 empreintes `OK` dans la VM, `go version go1.26.11 linux/amd64`, autres outils aux versions du 03/11 |
| R3 `transporter` (hôte, puis VM) | **action sur la VM** | sujet et `.att` copiés, **8 bundles horodatés**, 6 entrées copiées, bundle git de `main` |
| R3 `verifier_entrees` (VM) | (même accord) | 8 bundles vérifiés sur 8 ; provenance `9539952b` extraite d'un bundle vérifié ; entrées `construire-image` `4dcbc4b7…`, fermeture `74c265e7…`, web-dist `47f72275…`, `builder-go-voie-d` `8c11e856…`, commit `6391fd43…` ; digests recalculés égaux ; `go1.26.11 ; toolchain du domaine : go1.26.11` ; `finishedOn` à 13:27:42Z et jeton de la TSA quelques secondes plus tard ; 0 KO |
| R4 `rebuild` (VM, hors ligne, ≥ 2026-11-25T13:27:42Z) | **action sur la VM** | lien coupé 1 200 s, sortie de la VM inchangée, **`PASSED`**, image `f5e6bcb0…`, binaire du `go build` `56f3cd7d…` |
| R5 `vsa` (VM) | (accord de R4) | VSA `PASSED`, sujet `f5e6bcb0`, `inputAttestations` = bundle horodaté de `9539952b`, signée par la clé du domaine (inchangée) et revérifiée |
| R5 `porte_avant`, `pousser_vsa`, `porte_apres`, `lire_vsa` | **push de VSA (accord nommé)** | porte inchangée avant et après le push ; manifeste poussé par digest dans `builds/vsa/sample-app` (compte `poc-replay`) ; clés croisées refusées. Le contrôle 6 ne lie la VSA qu'au digest (additif du 03/11, 22:45), donc la même VSA vaut après un rejeu de zéro, qui reconstruit `f5e6bcb0` |

Les journaux vont dans ce dossier. `replay.sh` y refuse un journal existant ; un passage raté sera renommé en `-1`. Les valeurs par défaut de `replay.sh` (`3a7ca1b1`, `c4242a11`, Go 1.26.10) ne changeront que dans le commit qui archive la VSA de `f5e6bcb0`.

## Défaut relevé à sec, sans effet sur cette suite

`replay.sh` définit deux fonctions `etape_outils` : celle de R1 (téléchargement sur l'hôte, l. 191) et celle de R2 (installation dans la VM, l. 281). Bash garde la seconde, donc l'étape de R1 n'est plus appelable depuis l'ajout de R2. Son journal (`r1-outils.log`, 03/11, 09:52 UTC) est antérieur à ce code. L'archive de Go 1.26.11 passe donc par `go-domaine.sh` de la 07c, pas par cette étape.
