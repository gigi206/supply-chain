# Brique 06, S6b, relevé 1 : prédictions (12/11/2026, rédigées à partir de 09:13:30 UTC, avant toute mesure)

Préparées sur « continue » (cadre : à sec, rien lancé). L'heure est celle de `date -u` au début de la rédaction ; l'heure du commit fait foi.

Décision du propriétaire (12/11/2026, 08:50:32 UTC), point 3 : le chroot est reconstruit dans `sc-replay`, avec mmdebstrap et sbuild installés par apt, versions épinglées, sans recommandés, comme `busybox-static` en R2. **L'installation aura son propre accord nommé.** Ce relevé ne l'est pas : il prépare l'épinglage.

**Rien n'est lancé.** Le relevé attend un **accord nommé**. Commande, depuis la racine du dépôt :

```
mise exec -- poc/bricks/06-deb-sbuild/s6b.sh releve
```

Script : [`s6b.sh`](../s6b.sh). Journal : `s6b-releve.log`.

## Ce que le relevé touche

- **Hôte** : lecture anonyme de Zot (manifestes, tag `.att` du deb) ; écritures sous `~/.cache/supply-chain-poc/06/s6b` et dans `resultats/` seulement. La reconstruction du layout (H2) tourne hors réseau (`unshare -rn`).
- **`sc-replay`** : SSH avec les clés du domaine de la 10, comme `replay.sh`. La seule écriture est **`apt-get update`**, qui met à jour les listes d'apt sans installer aucun paquet. `apt-get install --assume-no` calcule ce qu'apt installerait et répond non. Le nombre de paquets installés est relevé avant et après.
- Rien dans le cluster, rien d'écrit dans Zot.
- Les signatures des provenances ne sont **pas** vérifiées ici : elles le seront dans le domaine, comme en R3 de la 10.

## Prédictions

- **H1, provenances du deb.** Le tag `sha256-039949f9….att` existe dans `builds/sample-app-deb`, avec au moins une couche, chacune de type `https://slsa.dev/provenance/v1` et de sujet `039949f9`. Le nombre de couches n'est pas prédit : le deb a pu être produit à nouveau par S4d3. `finishedOn` tombe le 11/11/2026, entre 19:28 et 21:05 UTC (`chrono.tsv` : pipeline de S4d1 lancée à 19:28:08, porte de S4d3 finie à 21:04:32). Le délai de 24 h de `vsa.py` est donc dépassé depuis le 12/11 à 21:05 UTC au plus tard. Les entrées résolues comprennent :
  - l'image de build `749d746c` ;
  - la fermeture deb `bb7599a2`, la fermeture des sources `50dc73f7` et le packaging `c1719b13` ;
  - le bundle de tâche `construire-deb` `3726ff0b`.

  Confiance moyenne, pour la liste exacte et la forme des URI.
- **H2, layout reconstruit à partir des seuls octets du deb.** Le manifeste reconstruit est identique, octet à octet, à celui de Zot, de digest `039949f9`. C'est la condition de `PASSED` (`politique-replay.md` §3) si le deb lui-même se reproduit. Confiance haute :
  - le tar de l'hôte (GNU tar 1.35) a la même version amont que celui de l'image de build (`tar 1.35+dfsg-3.1`, `builder/paquets.txt`) ;
  - toutes les options qui fixent le contenu sont explicites (`--sort`, `--format=posix`, `--pax-option`, `--mtime=@0`, propriétaire, mode 0644).

  Si H2 échoue, la reconstruction du layout devra se faire avec le tar du chroot, pas celui de la VM.
- **H3, entrées à transporter.** Les trois manifestes se lisent en anonyme. La fermeture deb est la plus lourde, avec la chaîne Go `golang-1.24` : entre 30 et 300 Mo. Le total reste sous 1 Go. Confiance moyenne : je n'ai pas relevé les tailles.
- **V1, ressources.**
  - 4 vCPU, environ 5,7 Gio de mémoire, 20 Go de disque, Debian 13 ;
  - au moins 10 Go libres sur `/` ;
  - ni mmdebstrap ni sbuild installés.

  Confiance moyenne pour la place libre, qui n'a pas été relevée depuis R4.
- **V2, espaces de noms sans privilège.** `max_user_namespaces` est non nul et `unprivileged_userns_clone` vaut 1 (noyau Debian). Aucune restriction AppArmor des espaces de noms : le fichier est absent ou vaut 0. Confiance moyenne. Pour `/etc/subuid` et `/etc/subgid` du compte `replay`, je prédis une ligne chacun, avec une confiance faible : le compte vient de cloud-init, et je n'ai pas vérifié s'il passe par `useradd`, qui ajoute ces lignes.
- **V3, apt.**
  - `apt-get update` réussit, sans avertissement de signature ;
  - candidats : mmdebstrap `1.5.7-1+deb13u1` et sbuild et `libsbuild-perl` `0.89.3+deb13u4`, les versions de l'instantané du 05/11/2026 (`builder/paquets.txt`), ou des versions plus récentes de `trixie-updates` ou `trixie-security` ;
  - uidmap `1:4.17.4-2` ;
  - `apt-get install --assume-no` répond non, code 1, et annonce entre 5 et 40 paquets nouveaux ;
  - le nombre de paquets installés est le même avant et après.

  Confiance moyenne pour les versions, faible pour le nombre de paquets.
- **V4, instantané depuis la VM.** `http://snapshot.debian.org/archive/debian/20261105T000000Z/dists/trixie/InRelease` répond 200 depuis la VM, et son sha256 est `0584fba3…`, celui de S1, puisqu'un instantané ne change pas. Confiance moyenne : la VM joint l'extérieur (R2 : `deb.debian.org`, HTTP 200), mais snapshot.debian.org limite parfois son débit.

## Ce que le relevé ne tranche pas

Ce sont des questions pour la suite, après le relevé.

1. **Source des paquets du chroot dans le domaine.**
   - La VM peut les tirer elle-même de snapshot.debian.org, en vérifiant la signature de l'archive avec le trousseau Debian de la VM et l'InRelease `0584fba3`. Le domaine ne dépendrait alors pas du miroir partiel de la plateforme : c'est plus indépendant.
   - Ou bien le miroir de la plateforme est transporté et revérifié dans la VM.

   La création du chroot se ferait lien établi ; le rebuild, lien coupé, comme en R4.
2. **Fermeture deb et sources.** Elles sont transportées comme en R3, sur un transport non fiable, puis revérifiées dans la VM contre la provenance vérifiée.
3. **Comparaison du chroot.** L'archive du chroot reconstruit pourrait être comparée, par son sha256, à la couche `opt/sbuild/trixie-amd64.tar` de `749d746c`. Ce serait une mesure de plus, que le contrôle 6 n'exige pas.
