# Brique 05, S1 : sortie réseau des pods rpm, prédictions (écrites le 12/11/2026 à partir de 14:27:07 UTC, avant toute exécution)

Décision du propriétaire, le 12/11/2026 : « Oui, prépare-la », en réponse à la question « Je retiens la sortie rpm en 443 avec Zot et je prépare son intégration à sortie-builds.sh à sec ? ». **Rien n'est appliqué ni lancé.** Le correctif n'est pas appliqué au dépôt.

## Ce qui est préparé

- **Politique** : [`politiques/prefetch-rpm-sortie.yaml`](../politiques/prefetch-rpm-sortie.yaml), déjà commitée. Elle s'applique aux pods `tekton.dev/task=prefetch-rpm` et leur permet le DNS, les adresses publiques en 443 et Zot (`192.168.161.13:5000`). Le refus par défaut vaut pour le reste.
- **Correctif** : [`s1-sortie-rpm.patch`](../s1-sortie-rpm.patch), non appliqué. Il porte sur deux fichiers de la 08c que S5b rejoue, d'où l'application après S5b.
  - `politiques/cilium-sortie/builds-sans-internet.yaml` : `prefetch-rpm` ajouté au `NotIn`, description et en-tête mis à jour.
  - `sortie-builds.sh` :
    - `REGLE_RPM`, qui pointe vers la politique de la 05, et cinq politiques dans `DEPOT_POL` ;
    - un invariant `invariants_rpm` : les pods `prefetch-rpm` ne sont sélectionnés que par `prefetch-rpm-sortie` ;
    - quatre étapes : `rpm_sec`, `rpm_appliquer`, `rpm_temoins` et `rpm_retirer` ;
    - deux destinations ajoutées aux témoins : `dl.rockylinux.org` en 443 et en 80 ;
    - `rejeu` pose aussi `prefetch-rpm-sortie`, avant `builds-sans-internet`, et attend les trois labels ;
    - la contre-épreuve de `deb_sec` retire seulement `prefetch-deb` du `NotIn`, au lieu de revenir à `[prefetch-gomod]`. Sans cela, elle signalerait aussi `prefetch-rpm-sortie`.
  - `deb_appliquer` et `deb_retirer` sont marqués comme historiques : ils supposent un `NotIn` sans `prefetch-rpm`.
- `rejeu.sh` n'a pas à changer : il appelle déjà `sortie-builds.sh rejeu`.

## Vérifié à sec

Sur une copie détachée de `e1d5dbc`, retirée ensuite :
- `bash -n` passe ;
- shellcheck 0.11.0 ne relève aucun avertissement ;
- `git apply --check` passe sur l'arbre de travail ;
- l'opérateur jq `-=` donne `["prefetch-gomod","prefetch-deb"]` sur un JSON factice.

Ni `rpm_sec` ni aucune autre étape n'a tourné.

## Ordre, après S5b, chaque point sur accord nommé

1. Appliquer le correctif, le commiter et le pousser.
2. `sortie-builds.sh rpm_sec` : hôte seul, sans cluster.
3. `sortie-builds.sh rpm_appliquer` : écrit dans le cluster.
4. `sortie-builds.sh rpm_temoins` : cinq pods runc éphémères dans `builds`.
5. Rejouer `s1.sh hote` (pub/9.8 et EPEL bougent), puis `prealables` et la suite de S1 de la 05.

## Prédictions

| # | Prédiction | Confiance |
|---|---|---|
| R1 | `rpm_sec` : 0 KO. Les invariants passent avec les cinq politiques du dépôt. Retirer `prefetch-rpm` du `NotIn` fait signaler exactement `CiliumNetworkPolicy prefetch-rpm-sortie`, et retirer la politique fait signaler `tekton.dev/task=prefetch-rpm` | Moyenne-haute : même construction que `deb_sec`, qui a tenu le 10/11 |
| R2 | `deb_sec` avec le correctif : 0 KO, contre-épreuves comprises | Moyenne : la contre-épreuve modifiée n'a pas tourné |
| R3 | `rpm_appliquer` : `prefetch-rpm-sortie` puis `builds-sans-internet` valides pour Cilium en moins de 60 s, `NotIn` à `["prefetch-gomod","prefetch-deb","prefetch-rpm"]`, invariants OK | Moyenne-haute |
| R4 | `rpm_temoins`, pod `prefetch-rpm` : trois noms résolus ; snapshot.debian.org en 80 refusé ; proxy.golang.org et dl.rockylinux.org en 443 joints ; dl.rockylinux.org en 80 refusé ; API de RKE2 refusée ; Zot joint ; Forgejo refusé | Moyenne : la règle `toCIDR` de Zot n'a pas encore été mesurée |
| R5 | Mêmes témoins pour les autres labels :<br>- `prefetch-gomod` : comme avant, dl.rockylinux.org joint en 443 et refusé en 80 ;<br>- `prefetch-deb` : dl.rockylinux.org refusé en 443 et joint en 80 (HTTP 200, ou une redirection qui peut finir en refus) ;<br>- sans label : dl.rockylinux.org refusé dans les deux cas ;<br>- `construire-image` : tout refusé, comme avant | Moyenne ; faible pour le cas de `prefetch-deb` en 80 (redirection éventuelle de Rocky vers https) |
| R6 | Un rejeu de zéro postérieur au correctif pose la sortie rpm sans autre changement | Moyenne : non rejoué |

## Limites

- **Comme pour `prefetch-gomod`**, un pod `prefetch-rpm` joint toute adresse publique en 443, pas seulement les dépôts de Rocky et d'EPEL. Il faudrait `toFQDNs` pour se limiter aux noms, et ce choix reste à faire avec `l7Proxy=false` (besoins à définir, Cilium).
- **L'intégrité ne repose pas sur la règle réseau** : elle vient des repomd signés de Rocky et des rpm signés. EPEL ne signe pas ses repomd (étape `hote`, P3).
- **Zot est joint en 5000** pour tirer l'image de bootstrap. Les écritures dépendent des droits de Zot, pas de la politique.

## Note du 12/11/2026, à partir de 14:30:11 UTC (relecture du conseiller, avant tout lancement)

- **Autres lecteurs du `NotIn` et des politiques de sortie** : recherche de `prefetch-deb`, `builds-sans-internet` et `ciliumnetworkpolicy` dans les `*.sh`, `*.yaml`, `*.jq`, `*.py` et `*.rego` du dépôt, journaux exclus.
  - Seul `sortie-builds.sh` lit le `NotIn` ou exige la liste des politiques de sortie.
  - Les autres contrôles ne portent que sur d'autres labels. `03/prefetch.sh` veut `prefetch-sortie` seule sur `prefetch-gomod`. `08/construction.sh`, `06/s4a.sh` et `06/s4d.sh` exigent qu'aucune politique n'autorise de trafic vers `construire-image`, `construire-builder` ou `construire-deb`. `prefetch-rpm-sortie` ne sélectionne aucun de ces labels.
  - `08/preuves.sh` ne fait qu'afficher les politiques au lancement, et `08c/durcissement.sh` cherche les politiques qui citent un Secret ou du TLS.
  - Le correctif n'a donc pas à s'étendre. « `rejeu.sh` n'a pas à changer » tient : il appelle `sortie-builds.sh rejeu`, que le correctif modifie.
- **Ordre, contrainte ajoutée** : le correctif met la sortie rpm dans l'étape `rejeu`, donc sur le chemin du rejeu de zéro, avant toute mesure. Pour le deb, `rejeu` n'avait été modifié qu'après le passage réel de `deb_appliquer` et de ses témoins. Ici, **aucun rejeu de zéro ne doit tourner entre l'application du correctif (point 1) et `rpm_temoins` (point 4)**. S5b vient avant le correctif, il n'est donc pas concerné.
  - Le scinder n'aiderait pas. Le `NotIn` de `builds-sans-internet.yaml` est lu par `rejeu`, et un correctif sans l'étape `rejeu` ferait échouer le rejeu suivant sur le `NotIn` attendu : un échec franc, pas silencieux.
- **R5, « comme avant »**, s'appuie sur le journal archivé [`08c/resultats/sortie-deb_temoins.log`](../../08c-durcissement/resultats/sortie-deb_temoins.log) du 10/11 :
  - sans label : public refusé, API de RKE2, Zot et Forgejo joints ;
  - `prefetch-gomod` : proxy.golang.org joint en 443, Zot refusé, Forgejo joint ;
  - `construire-image` : tout refusé, DNS compris ;
  - `prefetch-deb` : snapshot.debian.org joint en 80, le reste refusé.
- **Textes périmés** : l'en-tête de `politiques/prefetch-rpm-sortie.yaml` reçoit une ligne datée. Le message KO de `s1.sh prealables` (« à décider ») n'est pas modifié : ce serait une modification de script. Il ne gêne rien, puisque l'étape s'arrête au même endroit.
