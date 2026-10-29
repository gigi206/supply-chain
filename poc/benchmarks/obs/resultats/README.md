# Résultats du banc A2 : Open Build Service (master, appliance Build53.24) en VM KVM (29/10/2026)

**42/100 contre 55 pour la référence restreinte : OBS n'est pas adopté pour le packaging.** Les critères éliminatoires 1 à 4 sont démontrés. Le critère 5 ne l'est que partiellement : seules rocky-9 et debian-13 ont été construites. Lu à la lettre (« éliminé si un point n'est pas démontré »), il éliminerait OBS ; c'est **au propriétaire de trancher**. La non-adoption ne dépend pas de ce choix.

Le score tient à A-1 : sur les 4 besoins de la grille restreinte, un seul est couvert nativement. Sur le reste, OBS fait mieux que prévu :
- **rpm et deb sont bit-identiques sur 2 builds** (seuil du banc atteint), et le restent hors ligne ;
- sa **provenance**, générée hors de la VM de build et signée en DSSE, a résisté aux 3 tentatives de falsification, et la VM de build a passé les 3 contrôles d'isolement ;
- **chaque dépendance de build est conservée et récupérable par son digest**.

## Environnement

| Élément | Valeur |
|---|---|
| Hôte | Laptop bare metal (ADR 0001), libvirt 12 / QEMU 10.2.1, `kvm_intel.nested=Y` |
| VM `sc-obs` | 6 vCPU Haswell-v4 avec `vmx` (x86-64-v3 supporté, v4 non), 8 Gi, qcow2 plafonné à 40 Go, NAT 192.168.161.0/24 |
| Appliance | `obs-server.x86_64-2.10.51-oem-Build53.24.raw.xz` (sha256 `bbc26ff8…`, signature de la clé `660F…19E7` vérifiée sur 3 canaux) ; openSUSE Leap 16.0 |
| OBS | `2.11~alpha.20261029T112345.58021baee2` (commit `58021baee2`, master), obs-signd 2.8.5, build 20261014 |
| Worker | 1 instance, 4 jobs, 3 Gi, type `kvm` ; VM de build : `qemu-kvm -cpu host -net none -sandbox on -run-with user=qemu`, noyau de l'appliance, initrd `/boot/initrd.obs.guest` |
| Dépôts | Rocky 9.7 (vault, `repomd.xml.asc` vérifié) ; Debian 13 (`deb.debian.org`, `InRelease` identique à l'instantané `20261029T000000Z`, vérifié au début et à la fin du banc : [`inrelease-fin.log`](inrelease-fin.log)) |
| Paquet | `poc/packaging` : sample-app 1.0.0 (Go vendoré, marked vérifié), spec et paquet source Debian |

## Chronomètre ([`chrono.tsv`](chrono.tsv))

| Étape | Depuis l'accord |
|---|---|
| Appliance installée et configurée | **9 min 25 s** |
| Premier build signé avec provenance (rpm et deb) | **51 min 50 s** (dont environ 15 min perdues sur l'initrd et 10 min de téléchargement à la demande) |
| Rebuilds suivants | 2 à 3 min chacun (rpm 51 s et deb 41 s de build) |

Les deux seuils pratiques sont atteints : installation ≤ 1 jour, premier build signé ≤ 2 jours. Le banc a duré moins de 2 heures sur les 3 jours autorisés.

## Reproductibilité (A-3, seuil du banc)

Méthode fixée avant la mesure (voir [`../README.md`](../README.md)) :
1. comparer d'abord les NEVRA ;
2. puis les rpm **hors signature** (en-tête principal et charge utile, sans l'en-tête de signature signd), et les deb entiers ;
3. vérifier que le type de VM est `kvm` dans chaque journal.

| Comparaison | rpm Rocky 9 | deb Debian 13 |
|---|---|---|
| build-1 / build-2, réglages par défaut ([`comparaison-build-1-build-2.txt`](comparaison-build-1-build-2.txt)) | **NEVRA différents** : release `1.1`, puis `1.2` | identiques (`0b489d43…`) |
| build-3 / build-4, `Release: <CI_CNT>` ([`comparaison-build-3-build-4.txt`](comparaison-build-3-build-4.txt)) | **identiques hors signature** (`57343ca6…`, src.rpm `e5cbf401…`) | identiques |
| build-3 / build-5, hors ligne ([`comparaison-build-3-build-5.txt`](comparaison-build-3-build-5.txt)) | identiques hors signature | identiques |
| build-3 / build-v1, provenance SLSA v1 ([`comparaison-build-3-build-v1.txt`](comparaison-build-3-build-v1.txt)) | identiques hors signature | identiques |

Lecture des résultats :
- **Release** : par défaut, OBS remplace la release du spec par `<CI_CNT>.<B_CNT>`. Le compteur de builds change à chaque rebuild : il faut donc `Release: <CI_CNT>` dans le prjconf ([`../projets/poc.prjconf`](../projets/poc.prjconf)). Ce réglage écrase aussi `%{?dist}`.
- **Signature** : les sha256 complets des rpm diffèrent seulement par la signature signd, horodatée à chaque signature. B1 l'exclut de la comparaison.
- **En-têtes rpm** : `BUILDTIME` = date du changelog, `BUILDHOST` = `reproducible`, `DISTURL` = srcmd5 des sources, grâce aux macros du prjconf.
- **Deb** : le paquet est identique d'emblée. `.buildinfo` et `.changes` diffèrent (date de build), mais ce ne sont pas des paquets.

**Résultat : 2/2 (rpm et deb) bit-identiques sur 2 builds.**

## Provenance et critère 1 ([`tests-hostile.log`](tests-hostile.log), [`tests-hostile2.log`](tests-hostile2.log), [`build-1/dsse.log`](build-1/dsse.log))

Fonctionnement de la provenance (vérifié dans le code de `bs_worker` et `bs_signer`, puis par les tests) :
- **Génération** : elle est générée par le **worker**, hors de la VM de build, à partir des fichiers produits et de la liste des dépendances. Elle n'existe que sur master et s'active projet par projet avec `$slsaprovenance`. Le format par défaut est SLSA v0.2, ou SLSA v1 avec `BuildFlags: slsaversion:v1`.
- **Filtrage** : avant d'ajouter la sienne, le worker **écarte tout fichier `*slsa_provenance.json|config` produit par le build**.
- **Signature** : `bs_signer` épingle chaque matériau par son digest (`addrefs`), recalcule le digest des rpm après leur signature, puis **signe l'énoncé en DSSE** avec la clé du projet, via signd.

| Test | Résultat |
|---|---|
| T-res : sortie réseau depuis le build | **Bloquée** : la VM de build n'a que `lo` |
| T-sig : signd (5167), repserver (5252), srcserver (5352), API (443) | **Injoignables** |
| T-cle : clé de signature | **Absente** de la VM de build ; le build tourne sous l'uid 399 (`abuild`) |
| T-prov : fausses provenances déposées par le build dans `OTHER/` et à côté du rpm | **Écartées** : la provenance publiée est celle du worker (builder `obs://private`, sujet = vrai sha256 du rpm), en DSSE valide |
| T-src : fausse provenance en clair commitée dans les sources du paquet | **Ignorée** |
| T-suivi : job de suivi (`followupfile`) déclenché par un `*.followup.spec` produit par le build | Le suivi a lieu (2 builds KVM). Il réutilise la provenance du worker de la 1re étape, **pas** la fausse |
| Signature DSSE des provenances de sample-app (build-1, build-v1) | **Valide** sous la clé du projet `poc` (`E8B4…FC39`), vérifiée hors d'OBS (PAE DSSEv1, gpg) ; chaque sujet correspond au sha256 du fichier publié |

Les 3 premiers tests contrôlent l'isolement de la VM de build ; T-prov, T-src et T-suivi sont les 3 tentatives de falsification de la provenance. Pour les paquets hostiles, seuls les résumés (`tests-hostile*.log`) et les journaux de build sont archivés : les énoncés complets ont disparu avec la VM au démontage. Ceux de sample-app sont archivés (`build-*/<dépôt>/_slsa_provenance.statement.json`), et les `_buildenv` le sont sans le prjconf de build.opensuse.org, remplacé par son sha256 (`retirer-config.py`).

Réserves, qui ne sont pas éliminatoires :
- la **même clé** signe les rpm et la provenance, alors que le banc C recommande des clés séparées par usage ;
- pas d'horodatage TSA ;
- builder `obs://private` (sans `api_url`) et `metadata.reproducible: false`, alors que les paquets sont identiques ;
- en **SLSA v1**, OBS écrit `runDetails.id` au lieu du champ obligatoire `runDetails.builder.id`, et garde `_type` en `Statement/v0.1`. Une politique Conforma ou Kyverno qui contrôle `builder.id` refusera cette provenance telle quelle. Il faut une conversion, donc une re-signature par notre plateforme après vérification de la DSSE d'OBS (étape 5 du protocole).

## Hors ligne (critère 2, B5 ; [`build-5/horsligne.log`](build-5/horsligne.log))

Toute sortie de l'appliance est bloquée et journalisée par nftables. Restent permis : `lo`, l'appliance elle-même, les réponses SSH vers l'hôte et le DNS local, compté à part (le backend résout son propre nom par ce DNS). Le rebuild **réussit, avec des paquets identiques** à build-3.

Le build en lui-même n'a jamais d'accès réseau : sa VM est lancée avec `-net none`. Les 36 paquets bloqués pendant le banc venaient de l'appliance :
- `bs_dodup` rafraîchit les métadonnées de `deb.debian.org` (Fastly) ;
- un service de l'appliance tente une connexion sur le port 80 d'un serveur openSUSE ;
- le `curl` de contrôle du test.

## Dépendances archivées (B4 ; [`build-1/materiau.log`](build-1/materiau.log))

Avec la provenance activée, chaque binaire utilisé par un build est conservé dans `/srv/obs/slsa/<projet>/<dépôt>/<arch>/`, **adressé par son sha256**. L'URI de chaque matériau de la provenance renvoie le fichier, avec un digest vérifié :
- paquets Rocky (AppStream, BaseOS) ;
- paquets Debian ;
- `_config` du build.

Les sources sont citées avec leur révision et leur sha256.

Après 6 builds de sample-app et 2 builds hostiles, le magasin ne contient qu'**un exemplaire par binaire distinct** : 203 deb et 468 rpm, plus 4 `_config` par dépôt (un par configuration de build). 668 des 679 fichiers sont des liens physiques vers le cache, donc sans espace disque en plus ([`slsa-magasin.log`](slsa-magasin.log)).

## Poids opérationnel (A-5, [`etat-repos.log`](etat-repos.log), [`composants-repos.txt`](composants-repos.txt))

| Mesure | Valeur |
|---|---|
| RAM au repos, dans la VM | **3,6 Gi** utilisés (+ 2,5 Gi de cache) |
| RAM vue de l'hôte | 7,9 Gi (RSS de qemu : la VM ne rend pas la mémoire touchée pendant les builds) |
| Composants | **28** services systemd de longue durée, soit l'équivalent des Deployments du banc A1 (un gabarit compte une fois). Ils comprennent les **9 files delayed-job** de Rails, `obs-gitea-bridge` et `obs-sphinx` ; 100 processus |
| Disque | 17,5 Gio alloués dans le qcow2, `/` de la VM rempli à 83 % (racine de build de 16 Gio) |

## Santé (A-6, [`preuves.log`](preuves.log))

- **Licence et état** : GPL-2.0 pour `open-build-service`, `obs-build` et `obs-sign`, aucun archivé. Verdict « Sain » dans le doc 04.
- **Contributions sur 90 jours** :
  - `open-build-service` : 638 commits, 21 auteurs ;
  - `obs-build` : 92 commits, 5 auteurs, presque tous en `suse.de` ;
  - `obs-sign` : 10 commits, **1 auteur**.
- **Employeur** : les adresses personnelles appartiennent surtout à des employés de SUSE. **Un éditeur unique de fait.**
- **Releases** : les versions 2.10.x sortent tous les 1 à 3 mois, mais depuis la branche `2.10`, **séparée de master le 14/06/2019**. Master, la seule version qui produit la provenance, **n'a jamais été publié en release depuis 7 ans** : build.opensuse.org le déploie en continu.

## signd face au service OpenPGP (brique 09)

- **Clés de projet** : générées par signd et **stockées chiffrées dans le backend** (`/srv/obs/projects/<projet>.pkg/_signkey`), puis déchiffrées par signd au moment de signer.
- **Clé maîtresse** : dans le `gpg-agent` de l'hôte signd. Une carte OpenPGP est possible via scdaemon, **pas de PKCS#11 direct**.
- **Isolement** : signd peut tourner sur un hôte séparé (`server:`, `proto: ssl`, mTLS par `allow_subject`).
- **Signatures** : signd signe les rpm et les dépôts publiés (`repomd.xml.asc`, `Release.gpg`, `InRelease`), mais pas les `.deb`, ce qui est l'usage Debian.
- **Attestation de lien** : il n'y en a pas entre le paquet non signé et le paquet signé. La provenance désigne directement le rpm signé.

## Notation (grille A restreinte)

Ont été validés **avant** les mesures : l'échelle de A-1 (4/4 → 5, 3/4 → 4, 2/4 → 2, ≤ 1 → 0), A-3 sur rpm et deb, et la référence restreinte. **Ne l'a pas été** le classement de B1, B4, B5 et B8 en « couvert » ou « partiel » : il est proposé ci-dessous et soumis au propriétaire.

Les règles d'interpolation et d'arrondi sont celles du banc A1. **Pour A-1, un besoin partiel ne compte pas**, comme au banc A1 ; le texte de chaque besoin est celui du doc 01.

| Besoin (A-1) | Lecture | Justification |
|---|---|---|
| B1 bit à bit et replay | **Partiel** | Bit à bit hors signature : oui, mais seulement avec `Release: <CI_CNT>`. Pas de replay dans un domaine indépendant, pas de VSA |
| B4 archive de toutes les dépendances | **Partiel** | Paquets OS épinglés par digest, restaurables, stockés une seule fois. Mais la fermeture Go et npm vient de `poc/packaging/sources.sh`, pas d'OBS : les services `go_modules` et `node_modules` existent mais n'ont pas été testés. La déduplication n'a été mesurée qu'entre builds identiques, pas entre deux versions proches |
| B5 rebuild hors ligne | **Couvert** | Le texte de B5 n'exige pas de domaine indépendant. La VM de build n'a aucune interface réseau par construction ; le rebuild depuis les entrées archivées réussit avec un résultat identique, toute sortie de l'appliance étant bloquée et journalisée. Au banc A1, B5 était partiel, faute de rebuild hors ligne démontré (prefetch en ligne) |
| B8 rpm et deb multi-distro | **Partiel** | rocky-9 et debian-13 bit-identiques, paquets et dépôts signés en OpenPGP. Pas d'attestation de lien ; debian-12, ubuntu-24.04, alma-9 et centos-stream-10 non construits |

| Critère | Poids | Note | Justification |
|---|---|---|---|
| A-1 couverture (B1, B4, B5, B8) | 25 | **0** | **1/4** (B5), donc ≤ 1 → 0 |
| A-3 reproductibilité (rpm et deb) | 15 | **5** | 2/2 |
| A-5 poids opérationnel | 10 | **2** | RAM au repos 3,6 Gi (≤ 8 Gi : 5) ; **28 composants** : 2,0 ; la dimension la plus défavorable l'emporte |
| A-6 santé et pérennité | 10 | **3** | Sain (doc 04), sans bus factor de 1 sur le cœur. Mais un éditeur unique de fait, `obs-sign` maintenu par une personne, et une provenance qui n'existe que sur un master jamais publié |
| **Total** | 60 | | **(0×25 + 5×15 + 2×10 + 3×10) / 3 = 42/100** |

**Référence restreinte : 55** (§2.3 : A-1 = 2, A-3 = 3, A-5 = 4, A-6 = 3). **Seuil d'adoption : 65. OBS n'est pas adopté.**

**Sensibilité** : la lecture de A-1 n'a pas été validée avant la mesure ; elle est soumise au propriétaire. Variantes :

| Variante | Score |
|---|---|
| B4 compté (2/4 → A-1 = 2) | 58 |
| B4 compté, files delayed-job en un seul composant (A-5 = 3) et A-6 = 4 | 65 : **adopté**, juste au seuil (« au moins 10 points » au-dessus de 55) |
| B4 et B8 comptés (3/4 → A-1 = 4) | 75 |

**Ce qui ferait basculer le résultat : compter B4 et B8 comme couverts.** La décision « non adopté » tient pour toute lecture qui applique la règle de A1 (un besoin partiel ne compte pas).

## Critères éliminatoires (§1)

| Critère | Résultat |
|---|---|
| 1. Provenance non falsifiable | **Démontré** : générée par le worker hors de la VM de build, signée en DSSE par le signer ; les 3 tentatives de falsification ont échoué et les 3 contrôles d'isolement sont passés (voir plus haut). Réserves : même clé que pour les rpm, pas de TSA |
| 2. Fonctionnement hors ligne | **Démontré** (build-5) |
| 3. Licence open source, auto-hébergement | **Démontré** : GPL-2.0, tout dans la VM, aucun SaaS. Mais la provenance exige master, jamais publié en release |
| 4. Santé | **Sain** (doc 04) |
| 5. amd64 et distributions cibles | **Partiellement démontré, à trancher par le propriétaire** : rocky-9 et debian-13 seulement. Les autres reposent sur le même mécanisme de DoD (build.opensuse.org les construit), mais n'ont pas été mesurées. Lu à la lettre, le §1 éliminerait OBS |

## Constats

1. **La provenance SLSA n'existe que sur master**, et **master n'a pas de release depuis 2019**. Aucune version publiée d'OBS ne produit de provenance.
2. **Bug d'OBS : snapshot.debian.org inutilisable en DoD.** Le téléchargement asynchrone du repserver (`BSWatcher::rpc_redirect`) ne résout pas les redirections relatives (« bad uri »). `BSRPC`, que `bs_dodup` utilise pour les métadonnées, les résout bien. Contournement : `deb.debian.org`, épinglé par l'`InRelease` de l'instantané. Le bug n'a pas été signalé en amont, ce qui demande l'accord du propriétaire.
3. **L'appliance ne construit pas telle quelle pour des cibles non SUSE.** L'initrd de kiwi n'a ni pilote de disque ni ext4 : la VM de build s'arrête, puis le dispatcher marque le worker « bad ». Il faut un `/boot/initrd.obs.guest` dédié, puis `bs_admin --drop-badhosts`.
4. **Release** : par défaut `<CI_CNT>.<B_CNT>`, donc changeante à chaque rebuild ; il faut `Release: <CI_CNT>` pour comparer.
5. **`gpgv` exige toutes les signatures** du `Release.gpg` de Debian : la clé d'archive de Debian 12 est donc nécessaire pour trixie.
6. **Clé OBS expirée (2015) dans la base rpm** de l'appliance (copie embarquée dans `config.sh`).
7. Par défaut, **une instance de worker par vCPU** : il faut la régler pour tenir dans 8 Gi.

## Ce que la plateforme peut reprendre d'OBS

- **Le modèle de provenance** : générée par le constructeur hors de l'environnement de build, sorties du build filtrées, signature par un service séparé après épinglage des matériaux. C'est le rôle que tiennent Chains et la brique 08.
- **Le magasin adressé par contenu des dépendances réellement utilisées**, rempli au moment de la signature : un modèle pour B4 et la brique 03, pour les paquets OS.
- **La VM de build sans interface réseau** (KVM, `-net none`) : une isolation simple, à comparer à Kata et à gVisor (brique 05).
- **Les réglages de reproductibilité rpm** (prjconf) et **le piège de la release**, à reporter dans mock (brique 05).
- **signd** : un candidat sérieux pour la brique 09 (mTLS, clés de projet chiffrées, déport sur un hôte isolé). Il lui manque un HSM PKCS#11 et une attestation de lien.
