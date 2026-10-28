# A1 : Konflux

**But** : noter Konflux sur la grille A de l'ADR 0000, face à la référence « assemblage » (57/100).

**Prérequis** : infra du PoC (ADR 0001), Forgejo avec un dépôt de test, sample-app.

## Protocole (≤ 3 jours)

1. **Installation** (≤ 1 jour) : opérateur Konflux sur k3s ou Kind, version stable épinglée (pas de RC). Mesurer le temps, la RAM au repos et le nombre de pods et composants.
2. **Intégration Forgejo** : Pipelines-as-Code ou autre déclencheur. Vérifier que le webhook est **authentifié** : un webhook non signé doit être refusé.
3. **Premier build signé** (≤ 2 jours) : sample-app en image OCI (Buildah, mode hermétique, prefetch Hermeto), avec provenance Chains et vérification Conforma.
4. **Tests négatifs** : rejouer les 8 tests du doc 01 et compter ceux que Konflux bloque nativement (A-2).
5. **Reproductibilité** : 2 builds de l'image, comparaison des digests (A-3).
6. **deb** : évaluer l'ajout d'une tâche sbuild **sans forker** le cœur (custom pipeline). Sinon, estimer l'effort (A-4).
7. **rpm rocky-9** : pipeline mock de Konflux, puis 2 builds et comparaison.
8. Estimer les pw nécessaires pour couvrir B1 à B14 (A-4).

## Mesures à archiver dans `resultats/`

- Versions et digests ; `kubectl get pods -A` ; consommation mémoire.
- Journaux des tests négatifs, provenance obtenue, sortie Conforma.
- sha256 des artefacts des deux builds.
