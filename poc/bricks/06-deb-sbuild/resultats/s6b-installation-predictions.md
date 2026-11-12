# Brique 06, S6b : témoin `sqv` et installation dans `sc-replay`, prédictions (12/11/2026, rédigées à partir de 09:51:20 UTC, avant toute mesure)

Préparées après « Oui, prépare-les ». L'heure est celle de `date -u` au début de la rédaction ; l'heure du commit fait foi.

**Rien n'est lancé.** Les deux étapes nouvelles de [`s6b.sh`](../s6b.sh) attendent chacune un **accord nommé** :

```
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh sqv
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh installer
```

Journaux : `s6b-sqv.log` et `s6b-installer.log`. L'ordre proposé est `sqv`, puis `installer`.

## Étape `sqv` : témoin de signature

- **Pourquoi** : V4c n'a rien vérifié, faute de `gpgv`. apt de la VM utilise `sqv` 1.3.0. C'est lui qui vérifiera l'instantané pendant mmdebstrap (décision 2).
- **Ce qu'elle fait** : VM seule, sans sudo, rien d'installé ; seule écriture, un dossier temporaire supprimé à la fin.
- **Syntaxe** : tirée de la page `sqv(1)` de trixie (manpages.debian.org) : `--cleartext` pour un message signé en clair, `--output` obligatoire, `-n` pour le nombre de certificats distincts exigés. La page ne dit pas ce que `sqv` affiche en cas de succès : l'étape juge par le code de sortie, et journalise la sortie et `sqv --help`.
- **Contrôles sur l'hôte, hors réseau** : la modification du témoin négatif, appliquée à la copie de S1 de l'InRelease (sha256 `0584fba3…`), change une seule ligne (`Date: Sat, 22 Sep 2026…`). `gpgv` et les clés de S1 acceptent l'original (code 0) et refusent la copie (code 1). Le motif `awk` de Packages.xz retrouve `7778d3e3…` dans l'original.

**Prédictions**
- **S0.** `sqv 1.3.0`. Je ne prédis ni le texte de `--help` ni le sha256 du trousseau.
- **S1.** sha256 de l'InRelease égal à celui de S1. Confiance haute (V4b).
- **S2.**
  - `sqv -n 1` : code 0. Confiance haute : apt de la VM a mis ses listes à jour avec `sqv` et ce trousseau.
  - `sqv -n 3` : code 0, les trois signataires de S1 étant dans le trousseau 2025.1 (clés d'archive 12 et 13, clé de publication 13). Confiance moyenne.
  - Message extrait sans ligne `BEGIN PGP`, et sa ligne Packages.xz porte `7778d3e3…`. Confiance moyenne : c'est ce que la page dit de `--output`, sans exemple qui le montre.
  - Je ne prédis pas la sortie.
- **S3.** Copie altérée refusée, code non nul. Confiance haute.

## Étape `installer` : installation système

C'est le point 3 de la décision du 12/11/2026, 08:50:32 UTC. apt installe mmdebstrap, sbuild, libsbuild-perl et uidmap, aux versions épinglées du relevé (V3), sans recommandés. Il n'y a **pas d'`apt-get update`** : les listes restent celles de 09:23:13 UTC, où les candidats étaient égaux à l'instantané.

- **I1** : `apt-get clean`, puis téléchargement seul (`--download-only`).
- **I2** : les sha256 des quatre `.deb` épinglés sont comparés à [`builder/paquets.txt`](../builder/paquets.txt), la liste de la plateforme, lue sur l'hôte. **La comparaison se fait avant toute installation** ; un écart arrête tout et vide le cache.
- **I3** : installation depuis le cache.
- **I4** :
  - versions installées ;
  - paquets nouveaux, avec leurs versions ;
  - nombre de paquets et services actifs, avant et après ;
  - `mmdebstrap --version` et `sbuild --version` ;
  - `newuidmap` et `newgidmap` ;
  - cache vidé.

Les épinglages ne portent que sur les quatre paquets demandés, comme en R2. Les 40 dépendances suivent les candidats de trixie, qui sont vérifiés par apt (`sqv`, puis le sha256 de Packages). Sur l'hôte, sous bash, j'ai vérifié trois points :
- l'extraction des sha256 attendus (64 caractères pour chacun des quatre) ;
- leur passage par ssh, joints par des virgules ;
- leur découpage côté VM, y compris pour la version à époque `1:4.17.4-2`.

`shellcheck -S warning` ne signale rien.

**Prédictions**
- **I0.** Avant : 339 paquets installés. Je ne prédis pas le nombre de services.
- **I1.** Code 0, « Need to get 13.8 MB », 44 `.deb` dans le cache. Confiance haute : les listes n'ont pas changé depuis V3.
- **I2.** Quatre `OK`, sha256 égaux à `builder/paquets.txt` :

  | Paquet | sha256 attendu |
  |---|---|
  | mmdebstrap | `df731ee9…` |
  | sbuild | `544ca6dc…` |
  | libsbuild-perl | `483c2ad6…` |
  | uidmap | `a017182d…` |

  Confiance haute : même version, et un fichier du pool Debian est le même sur le miroir et sur l'instantané.
- **I3.** Code 0, « Need to get 0 B », aucune ligne `W:` ni `E:`. Confiance moyenne pour l'absence d'avertissement.
- **I4.**
  - Quatre `OK` d'installation.
  - **383 paquets** : 44 nouveaux, 0 disparu ou changé ; le paquet « not upgraded » n'est pas touché.
  - Aucun service système nouveau. Confiance moyenne : gpg-agent et dirmngr sont des unités d'utilisateur, et sbuild n'a pas de démon.
  - `mmdebstrap 1.5.7`, sbuild 0.89.3 ; `newuidmap` et `newgidmap` présents.
  - Cache vidé : 0 `.deb`.
- **Effets.** Aucune écriture dans le cluster ni dans Zot ; moins de 3 min.

## Hors de ces étapes

- Le chroot par mmdebstrap depuis l'instantané, et sa comparaison à `builder/paquets.txt`.
- La fermeture deb `bb7599a2` transportée ; sbuild lien coupé ; la VSA sur `454728c5`.

Ces étapes viennent ensuite, avec leurs propres prédictions et accords.

## Note datée du 12/11/2026 (rédigée à partir de 09:54 UTC, après relecture du conseiller), avant tout lancement

Le commit des prédictions ci-dessus, `a530dcb`, est de 09:52:13 UTC. Trois défauts de `s6b.sh` sont corrigés avant tout lancement :
1. **`sqv` : le témoin négatif pouvait conclure à tort.** Si `--cleartext` était mal compris, `sqv` aurait tout refusé, et S3 aurait affiché « copie altérée refusée » sans rien prouver. S3 n'est désormais jugé que si `sqv -n 1` accepte l'original ; sinon il est déclaré « NON JUGÉ ». Deux autres changements :
   - le script journalise la présence de `--cleartext` dans `sqv --help` ;
   - si `-n 3` échoue alors que `-n 1` passe, Packages.xz est contrôlé sur le message extrait par `-n 1`.
2. **Codes de sortie** : un `KO` des étapes `sqv` et `installer` laissait le code 0. Chaque étape finit maintenant par un bilan, et par le code 1 au moindre `KO` (après le nettoyage, pour `installer`).
3. **`installer` : les `apt-get` lisent `/dev/null`.** `bash -s` lit le script sur l'entrée standard, dont dpkg et les scripts des paquets auraient hérité. Un script de paquet qui la lit aurait avalé la suite : I4 et le nettoyage auraient sauté, avec le code 0.

**Simulation sur l'hôte**, hors réseau, sur la copie de S1 de l'InRelease, avec un faux `sqv` :
- correct : tout `OK`, code 0 ;
- qui refuse tout : S3 « NON JUGÉ », code 1 ;
- qui accepte tout : « copie altérée ACCEPTÉE », code 1.

`bash -n` et `shellcheck -S warning` ne signalent rien.

**Deux précisions sur la portée**
- Que apt utilise `sqv` avec ce trousseau est **déduit, pas mesuré**. L'étape `sqv` journalise maintenant les sources d'apt (`Signed-By`) et les lignes `sqv` et `gpgv` de `apt-config dump`. Ces lignes ne sont pas prédites.
- apt peut appliquer à `sqv` sa propre politique cryptographique ; je ne l'ai pas vérifié. Le témoin vaut donc pour `sqv` seul. La vérification qui compte reste celle d'apt pendant mmdebstrap.

**Après `installer`**, les 44 lignes `+` d'I4 seront comparées sur l'hôte à `builder/paquets.txt`. Cela fera voir lesquelles des 40 dépendances s'écartent des versions de la plateforme, sans changer le script.

**Note datée du 12/11/2026 (heure de la note précédente)** : « 09:54 UTC » n'a pas été relevée. Le `date -u` lancé juste avant la rédaction de la note précédente donnait 09:55:38, et son commit `8d538af` est de 09:55:39 UTC. Ces heures font foi ; le titre du commit `8d538af` porte la même erreur.

