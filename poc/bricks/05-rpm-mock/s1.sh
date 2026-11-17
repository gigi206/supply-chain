#!/usr/bin/env bash
# Brique 05, jalon S1 (M1 du README) : mock dans un pod Kata privilégié (D1 a). Risque principal : podman imbriqué (image de
# bootstrap de mock), puis l'isolation nspawn contre simple (prédictions 3 et 4 du README). Verrou et --hermetic-build : M2.
# Prédictions : resultats/s1-predictions.md, écrites et commitées avant toute exécution. Préparé à sec le 12/11/2026 à partir de
# 14:12:09 UTC, NON LANCÉ. À lancer après S5b (Zot est remis à zéro par le rejeu), chaque étape sur accord nommé.
#   hote        hôte seul, ni cluster ni Zot (peut tourner avant S5b ; à rejouer avant racine, pub/9.8 et EPEL bougent) : sources
#               de sample-app ; clés de Rocky et d'EPEL comparées aux empreintes publiées ; repomd.xml de Rocky 9.8 (BaseOS,
#               AppStream) et 9.7 (BaseOS, AppStream, CRB) vérifiés par gpgv ; repomd d'EPEL 9 (signature relevée) ; primary
#               contrôlé par repomd ; NEVRA et sha256 des quatre paquets épinglés
#   prealables  cluster et Zot, lecture seule et dry-run : politique de sortie rpm en place (prefetch-rpm-sortie, et prefetch-rpm
#               dans le NotIn de builds-sans-internet : décision du propriétaire, appliquée hors de ce script) ; exemption Pod
#               Security de kata ; spec admise en dry-run serveur ; sc-build ; place libre de Zot
#   amorce      copie par digest de rockylinux 9.8 (outillage, D4 a) et 9.7 (bootstrap de mock, D2 a), amd64, dans Zot,
#               amont/rockylinux/rockylinux
#   racine      pod Kata privilégié, root, label prefetch-rpm, image 9.8 : dnf --installroot des quatre paquets épinglés avec les
#               clés vérifiées sur l'hôte, dépendances selon les candidats ; repomd lus par dnf comparés à ceux de l'hôte ; sha256
#               de chaque rpm comparé sur l'hôte au primary vérifié ; rpm -K ; archive rapatriée, sha256 comparé
#   image       image d'essai assemblée sans rien exécuter (crane append) : racine, puis une couche de configuration (mock :
#               vault 9.7 en baseurl fixes, bootstrap par digest dans Zot, macros d'OBS ; stockage de podman sous /w) ;
#               poussée dans Zot sous essais-05/mock-rocky9:s1
#               Ajout extras (../s1-extras.patch, préparé à sec le 16/11/2026, NON APPLIQUÉ ; décision du propriétaire
#               « Extras sur vault ») : le dépôt extras du modèle rocky-9 passe lui aussi du mirrorlist (9.8, mouvant) à la
#               baseurl fixe de vault 9.7 ; hote vérifie aussi son repomd.xml par gpgv ; la sonde d'essais s'arrête avant mock
#               s'il reste un mirrorlist pour BaseOS, AppStream, CRB ou extras
#               Ajout appliqué au dépôt le 16/11/2026 à 23:28:10 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (ad9febc5…) ; non lancé.
#   essais      pod Kata privilégié, root, label prefetch-rpm, image d'essai : sonde (capacités, montages, versions, clés,
#               dépôts actifs de mock) ; podman pull de l'image de bootstrap par digest et image mount ; puis, pour nspawn puis
#               simple : mock --buildsrpm et --rebuild de sample-app, sha256 du src.rpm et du rpm, place de /w, scrub
#               Ajout N3 et N4 (../s1-n34.patch, préparé à sec le 16/11/2026, NON APPLIQUÉ ; prédictions :
#               resultats/s1-predictions.md, section « Ajout N3 et N4 ») : après les journaux de mock, pod encore en vie, rpm
#               binaire de sample-app rapatrié sous $T/rpm-<isolation> (sha256 comparé à la sonde) ; puis SONDE_N34 dans le pod :
#               fichiers de licence de l'en-tête (drapeaux, bit 128, empreintes), BUILDTIME, CHANGELOGTIME et mtime (N5),
#               binaire usr/bin/sample-app isolé par rpm2cpio et n34-binaire.py (N4) ; sorties brutes, rien n'arrête l'étape
#               Ajout appliqué au dépôt le 16/11/2026 à 23:06:52 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (7a5ec25f…) ; non lancé.
#   verrou      (ajoutée le 12/11/2026 après le relevé de M2) pod Kata privilégié, root, label prefetch-rpm, image d'essai :
#               configuration jumelle avec bootstrap_image_ready=True ; mock --buildsrpm puis --calculate-build-dependencies,
#               isolation ISOLATION (simple par défaut) ; verrou archivé (resultats/s1-verrou.json) et résumé ; rien poussé
#               Corrigé à sec le 12/11/2026 à partir de 15:18:25 UTC, NON LANCÉ (relevé releve3 de M2) : le résumé affiche pull_digest et
#               architecture en plus d'image_digest, qui est un sha256 de RootFS et Config et ne peut valoir le digest du registre.
#   pods        Durée de vie et place (../s1-duree.patch, préparé à sec le 17/11/2026, NON APPLIQUÉ ; décisions du propriétaire
#               « Oui, 12 h » et « Oui, ajoute df ») : le conteneur des pods de racine, essais et verrou attend sleep 43200
#               au lieu de 10800 (racine a duré 5818 s ; un pod arrêté en plein travail perd /w, restartPolicy Never) ; SONDE
#               lit la capacité de /w par df -k, car sous Kata les options de montage de /w ne portent pas de size=
#               Correctif appliqué au dépôt le 17/11/2026 à 11:04:44 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (a61fa50e…) ; non lancé.
#   verrou_brut (../s1-verrou-brut-2.patch, préparé à sec le 17/11/2026 à partir de 13:09:43 UTC, 2e version, NON APPLIQUÉ ; décision du
#               propriétaire « Mesurer d'abord ») : comme verrou, mais configuration $CFG (bootstrap_image_ready=False) ;
#               verrou archivé pour lecture seulement (resultats/s1-verrou_brut.json), puis paquets du bootstrap préparé par
#               mock comparés à ceux de l'image brute (SONDE_BOOT) ; rien poussé
#               Correctif appliqué au dépôt le 17/11/2026 à 13:23:39 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (b7db829c…) ; non lancé.
#   hote97      (../s1-derivee.patch, préparé à sec le 17/11/2026, NON APPLIQUÉ ; décision du propriétaire « Dix lignes ») : hôte
#               seul, ni cluster ni Zot ; primary de vault 9.7 (BaseOS, AppStream, CRB, extras : dépôts actifs du modèle rocky-9)
#               contrôlés par leur repomd.xml vérifié par gpgv ; dépôt et sha256 de chacun des dix paquets de l'image dérivée
#               (arrêt si l'un manque) ; Requires de python3-dnf-plugins-core lus dans le primary
#   boot_racine pod Kata privilégié, root, label prefetch-rpm, image d'essai : racine de rockylinux:9.7 copiée (podman image
#               mount), dnf --installroot des dix NEVRA exacts depuis vault 9.7, clé vérifiée sur l'hôte ; transaction affichée ;
#               rpm -K ; rpm téléchargés comparés aux dix de hote97, ni plus ni moins ; listes rpm -qa complètes avant et après ;
#               archive rapatriée, sha256 comparé ; rien poussé
#   boot_image  image de bootstrap dérivée assemblée sans rien exécuter (crane append d'une couche pleine), annotations de la
#               base, poussée dans Zot sous essais-05/rocky9-bootstrap:<PREFIXE> (dépôt définitif)
#               Correctif appliqué au dépôt le 17/11/2026 à 14:19:43 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (ee611aac…) ; non lancé.
#   verrou_derivee (../s1-verrou-derivee.patch, préparé à sec le 17/11/2026 à partir de 15:03:48 UTC, NON APPLIQUÉ ; image de
#               bootstrap dérivée de boot_image) : comme verrou_brut, mais configuration $CFG_DERIVE générée sur l'hôte à partir
#               de MOCK_CFG et livrée dans le pod (bootstrap_image = essais-05/rocky9-bootstrap@<digest de boot_image>,
#               bootstrap_image_ready=True) ; podman pull de l'image dérivée par le pod avant mock ; lignes de repli sans image
#               comptées ; bootstrap de mock comparé à l'image dérivée (SONDE_BOOT) ; verrou archivé
#               (resultats/s1-verrou_derivee.json), comparé à celui de verrou_brut ; rien poussé
#               Correctif appliqué au dépôt le 17/11/2026 à 15:18:00 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (199b4ff2…) ; non lancé.
#   voie2       (../s1-m2.patch, préparé à sec le 17/11/2026 à partir de 15:40:59 UTC, NON APPLIQUÉ ; première partie de M2,
#               voie 2 décidée le 12/11) : verrou de verrou_derivee (resultats/s1-verrou_derivee.json, sha256 épinglé) mis à plat
#               sur l'hôte ; attendus tirés des mesures de S1 (boot-image.digest, DEPOT_DERIVE), jamais du verrou ; pod s1-05-m2
#               (image d'essai, pod_spec inchangé) : rpm du verrou téléchargés, rpm -K avec la seule clé de Rocky (empreinte
#               FP_ROCKY contrôlée sur l'hôte), en-têtes égaux au verrou, createrepo_c --compatibility, skopeo copy
#               --preserve-digests de l'image dérivée vers le dossier dir: de config.py:844-847 ; pod laissé pour hermetique si
#               la dernière ligne (manifeste copié) passe, retiré sinon. Cœur recopié de celui de m2.sh (NON BRANCHÉ, 12/11),
#               qui reste tel quel ; écarts : attendus, verrou épinglé et relu dans le pod, df de /w ; m2.sh ne fait plus foi
#               pour ces étapes
#   hermetique  (même correctif) : dans le pod laissé par voie2, jamais recréé ; verrou, repomd.xml et dossier dir: relus et
#               comparés à voie2 ; mock --hermetic-build sur ce verrou et ce dépôt, --isolation=$ISOLATION, basedir et
#               cache_topdir sous /w par --config-opts (config.py:468-499), src.rpm construit par --spec et --sources
#               (mock.py:994-1003), buildroot gardé par --no-cleanup-after pour que le df final mesure le pic ; lignes de
#               podman.py et de buildroot.py comptées, et --installroot=/w/mock-h/ ; rpm produits (sha256, BUILDHOST,
#               BUILDTIME) ; RÉSEAU PRÉSENT (label prefetch-rpm) : mécanisme mesuré, pas une preuve d'hermétisme (M3) ; rien
#               poussé ; pod retiré
#               Correctif appliqué au dépôt le 17/11/2026 à 16:02:02 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (8c60bca2…) ; non lancé.
#   collecte    (../s1-fermeture.patch, préparé à sec le 17/11/2026, NON APPLIQUÉ ; fermeture de M2) : pod s1-05-mf (image
#               d'essai, pod_spec inchangé) ; VOIE2_M2 rejoué tel quel (dossier $T/mf, journal mf-voie2) ; puis rpm de mock
#               6.9-1 téléchargé d'EPEL, sha256 épinglé (relevé à racine), rpm -K avec la seule clé d'EPEL dans une rpmdb à
#               part ; fermeture assemblée sous /w/fermeture (depot/ : rpm du verrou, repodata et dossier dir: de l'image ;
#               verrou.json ; outils/ : rpm de mock), listée avec ses sha256, rapatriée sur l'hôte par tar ; sur l'hôte : liste
#               exacte des fichiers, sha256 de chaque rpm égal au primary de vault 9.7 vérifié par hote97, repodata égal à
#               repomd.xml, blobs du dossier dir: égaux à leur nom, manifeste égal au digest de boot_image, verrou épinglé,
#               liste du pod égale à celle de l'hôte ; pod retiré ; rien écrit dans Zot
#   fermeture   écriture dans Zot (compte poc-ecriture), définitive : catalogue de Zot lu, puis tags du dépôt
#               deps/sample-app/mock-buildroot-lock s'il y figure ; tags $PREFIXE et $PREFIXE-bis absents, sinon rien n'est
#               envoyé ; fermeture recontrôlée ; closure.sh de la brique 03 (un fichier par couche), poussée deux fois : même
#               digest attendu, écrit dès le premier envoi ; couches comparées à la liste (titre, digest, taille) ; config et
#               couches de l'image relevées sous essais-05/rocky9-bootstrap ; place utilisée de /var/lib/zot (df en octets sur
#               sc-stockage, deux lectures avant, une après chaque envoi), sans seuil, « illisible » sans arrêt après l'envoi
#               (d'autres écritures ne sont pas exclues) ; inode et liens des blobs de l'image sous les deux dépôts (stat sans
#               sudo, « illisible » si refusé), sans pari
#   restauration lecture dans Zot : pull par digest dans un dossier vide, liste, taille et sha256 de chaque fichier comparés à
#               la liste de collecte ; inode et liens des blobs de l'image relus (relevé rejouable)
#               Correctif appliqué au dépôt le 17/11/2026 à 17:08:38 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (7cd2edd0…) ; non lancé.
#   m3_reseau   (../s1-m3-2.patch, préparé à sec le 17/11/2026, NON APPLIQUÉ ; jalon M3 ; décision du propriétaire « Tout
#               couper ») : écriture dans le cluster, sur accord : NetworkPolicy politiques/construction-rpm-sans-sortie.yaml
#               (aucune règle : ni entrée ni sortie pour le label tekton.dev/task=construire-rpm), admise en dry-run serveur,
#               posée, relue ; aucune politique de builds ne doit autoriser de trafic à ce label (selecteurs.jq de la 08). Elle
#               reste posée ensuite, comme celle de la 06
#   m3_temoin   témoin positif, lecture seule : pod s1-05-m3-temoin au label prefetch-rpm (sortie dédiée : DNS, 443 public,
#               Zot) ; les témoins de M3 (DNS sous timeout, TCP par adresse IP vers l'adresse publique des dépôts de Rocky,
#               résolue sur l'hôte, vers Zot et vers l'API du cluster) doivent répondre pour le DNS, l'adresse publique et Zot ;
#               le code de l'API est relevé ; pod retiré ; cibles écrites dans $T/m3-cibles après la porte seulement
#   m3_restauration lecture dans Zot : deux pulls par digest de la fermeture de M2 (FERMETURE_DIGEST, égal à
#               $T/mf/fermeture.digest), chacun dans un dossier neuf ($T/m3/restauree-1 et -2), chacun comparé à la liste de
#               collecte ; $T/mf n'est pas touché
#   m3_build1, m3_build2  un pod Kata privilégié, root, par build (s1-05-m3-1, s1-05-m3-2), image d'essai, label
#               tekton.dev/task=construire-rpm ; avant toute création : construction-rpm-sans-sortie relue dans le cluster et
#               invariant contrôlé, sinon aucun pod ; cibles validées par m3_temoin relues, sinon aucun pod ; spec admise en
#               dry-run serveur, label relu dans le cluster ; témoins de m3_temoin : les quatre doivent échouer, avec le code 1,
#               2 ou 124 (tout autre code arrête), sinon pod retiré et mock non lancé ; fermeture restaurée n copiée par tar
#               en morceaux de 64 Mio (copier, repris de la 06, s3.sh), sha256 comparé dans le pod, puis revérifiée fichier par
#               fichier dans le pod ; sources livrées (hors fermeture) ; mock --hermetic-build sur le verrou et le dépôt de la
#               fermeture, chemins distincts par build (/w/b1, /w/b2 : fermeture, basedir, cache_topdir, resultdir),
#               --no-cleanup-after ; paquets du buildroot relus par rpm --root ; rpm et src.rpm (NEVRA, sha256, BUILDHOST,
#               BUILDTIME) ; root.log, build.log, installed_pkgs.log et sortie de mock archivés en entier ; rpm rapatriés sur
#               l'hôte, sha256 comparés ; pod retiré ; rien écrit dans Zot
#   m3_comparaison hôte seul, sans réseau : nombre de rpm et de NEVRA lus, NEVRA et sha256 du rpm et du src.rpm, build 1
#               contre build 2 (critère de M3, seul compté en écarts) ; relevés à part, sans effet sur le code : témoins,
#               paquets du buildroot de chaque build contre les 222 du verrou, lignes http(s):// des journaux de mock
#               (affichées), mock de la fermeture contre celui de l'image, égalité avec le rpm et le src.rpm d'hermetique ;
#               diffoscope hors du script (installation à demander au propriétaire en cas d'écart)
#               Correctif appliqué au dépôt le 17/11/2026 à 19:53:32 UTC (« Oui, applique-le »), sha256 égal à la copie bancée
#               (18c9d4ce…) ; non lancé ; politique construction-rpm-sans-sortie NON POSÉE (m3_reseau, accord à part).
# Les replis (stockage vfs, mock non root, bootstrap sans image) ne sont pas lancés ici : chacun demande sa prédiction et un accord.
# Retrait : Zot n'autorise pas la suppression ; dépôts amont/rockylinux/rockylinux et essais-05/mock-rocky9 définitifs.
#
# Usage (racine du dépôt) : DISTRO=rke2 mise exec -- poc/bricks/05-rpm-mock/s1.sh <étape>…   (journal : resultats/s1-<étape>.log)
set -euo pipefail
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../08-trust-plane/commun.sh"
ROCKY98=https://dl.rockylinux.org/pub/rocky/9.8
VAULT97=https://dl.rockylinux.org/vault/rocky/9.7
EPEL9=https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64
CLE_ROCKY=https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9
FP_ROCKY=21CB256AE16FC54C6E652949702D426D350D275D            # publiée sur rockylinux.org/resources/gpg-key-info (audit du 05/11)
CLE_EPEL=https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
PAGE_EPEL=https://fedoraproject.org/security/                 # empreinte comparée à la page publiée, jamais écrite de mémoire
# nom version-release dépôt (relevé amont du 05/11 et audit de podman : mock et mock-core-configs dans EPEL 9 ; podman et skopeo de 9.8)
EPINGLES=("mock 6.9-1.el9 epel9" "mock-core-configs 45.2-1.el9 epel9" "podman 5.8.2-8.el9_8 appstream98" "skopeo 1.22.2-9.el9_8 appstream98")
AMORCE_DIGEST=sha256:ed654c694190a670bb5c33f68995b862214fc96ffbdca95e07a8935ba0a3717d   # rockylinux:9.8, amd64 (audit du 05/11)
BOOT_DIGEST=sha256:ee90dc0e23c2f59af63886aed78c495fc847c8f0af7e825f48746547ddb7fbe2     # rockylinux:9.7, amd64 (audit du 05/11)
DEPOT_AMONT=amont/rockylinux/rockylinux
AMORCE=$REG/$DEPOT_AMONT@$AMORCE_DIGEST
BOOT=$REG/$DEPOT_AMONT@$BOOT_DIGEST
DEPOT_ESSAI=essais-05/mock-rocky9
PREFIXE=${PREFIXE:-s1}
PKG=${PACKAGING_DIR:-$HOME/.cache/supply-chain-poc/packaging}
LABEL=prefetch-rpm
LIMITES='{"cpu": "2", "memory": "6Gi"}'      # demandes = limites ; tmpfs /w compté dans la mémoire du pod
TMPFS=4Gi
PRIVILEGIE='{"privileged": true, "allowPrivilegeEscalation": true}'
CFG=poc-rocky-9.7-x86_64
CFG_PRET=poc-rocky-9.7-pret-x86_64   # étape verrou : même configuration, bootstrap_image_ready=True
DEPOT_DERIVE=essais-05/rocky9-bootstrap   # image de bootstrap dérivée (décision « Dix lignes ») ; Zot : dépôt définitif
# nom epoch:version-release arch : les dix lignes de verrou_brut (six ajouts, quatre montées de version de la famille dnf)
DERIVEE=("dbus-libs 1:1.12.20-8.el9 x86_64" "python3-dateutil 1:2.9.0.post0-1.el9_7 noarch" "python3-dbus 0:1.2.18-2.el9.0.1 x86_64"
  "python3-dnf-plugins-core 0:4.3.0-24.el9_7 noarch" "python3-six 0:1.15.0-9.el9 noarch" "python3-systemd 0:234-19.el9 x86_64"
  "dnf 0:4.14.0-31.el9.rocky.0.1 noarch" "dnf-data 0:4.14.0-31.el9.rocky.0.1 noarch" "python3-dnf 0:4.14.0-31.el9.rocky.0.1 noarch"
  "yum 0:4.14.0-31.el9.rocky.0.1 noarch")
DEPOTS97=(BaseOS AppStream CRB extras)   # dépôts actifs du modèle rocky-9 de mock-core-configs 45.2 (enabled=1)
T=$W/s1-05
mkdir -p "$T"
umask 022

zot() { DOCKER_CONFIG=$T/docker SSL_CERT_FILE=$P/ca-poc.crt "$@"; }
attendu() { [ "$2" = "$3" ] && echo "OK   $1 : $2" || { echo "KO   $1 : $2 (attendu : $3)" >&2; exit 1; }; }
champ() { sed -n "s/^$2[[:space:]]*:[[:space:]]*//p" "$T/$1.log" | head -1; }   # journal libellé : valeur

pod_spec() { # nom image : pod de builds Kata privilégié, root, label prefetch-rpm, qui attend ; tmpfs /w, limites, zone build
  jq -n --arg n "$1" --arg i "$2" --argjson l "$LIMITES" --arg t "$TMPFS" --arg lb "$LABEL" --argjson sc "$PRIVILEGIE" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $n, namespace: "builds", labels: {"tekton.dev/task": $lb}},
    spec: {restartPolicy: "Never", serviceAccountName: "build", automountServiceAccountToken: false, nodeSelector: {zone: "build"},
      runtimeClassName: "kata",
      tolerations: [{key: "zone", operator: "Equal", value: "build", effect: "NoSchedule"}],
      securityContext: {runAsNonRoot: false, runAsUser: 0, runAsGroup: 0, seccompProfile: {type: "RuntimeDefault"}},
      volumes: [{name: "w", emptyDir: {medium: "Memory", sizeLimit: $t}}],
      containers: [{name: "s1", image: $i, command: ["sleep", "43200"], securityContext: $sc,
        resources: {requests: $l, limits: $l}, volumeMounts: [{name: "w", mountPath: "/w"}]}]}}' > "$T/$1.json"
}

pod_demarrer() { # nom : pod de $T/<nom>.json créé et prêt
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true </dev/null >/dev/null
  kubectl create -f "$T/$1.json" </dev/null >/dev/null
  kubectl wait -n builds "pod/$1" --for=condition=Ready --timeout=300s </dev/null >/dev/null \
    || { kubectl get pod -n builds "$1" -o json </dev/null | jq -r '"phase \(.status.phase) ; \([.status.containerStatuses[]?.state
           | to_entries[0] | "\(.key) \(.value.reason // "")"] | join(", "))"' >&2; echo "KO   pod $1 non prêt" >&2; exit 1; }   # raisons, jamais les messages
  echo "### $1 (kata, uid 0, privilégié, label tekton.dev/task=$LABEL) : prêt"
}

dans() { # nom libellé : script sh sur l'entrée standard, exécuté dans le pod ; sortie dans $T/<libellé>.log, puis affichée
  local rc=0
  kubectl exec -i -n builds "$1" -- sh -s > "$T/$2.log" 2>&1 || rc=$?
  sed 's/^/     /' "$T/$2.log"
  echo "     (code de l'exec : $rc)"
}

livrer() { # nom chemin-dans-le-pod fichier-local : petit fichier copié par l'entrée standard (aucun gros transfert entrant)
  kubectl exec -i -n builds "$1" -- sh -c "mkdir -p \"\$(dirname '$2')\" && cat > '$2'" < "$3"
}

pod_retirer() { kubectl delete pod -n builds "$1" --wait=false </dev/null >/dev/null; echo "pod $1 supprimé"; }

decompresser() { # fichier : contenu décompressé sur la sortie standard, d'après l'extension
  case $1 in
    *.gz) gzip -dc "$1" ;; *.xz) xz -dc "$1" ;; *.bz2) bzip2 -dc "$1" ;; *.zst) zstd -qdc "$1" ;;
    *) echo "KO   compression inconnue : $1" >&2; exit 1 ;;
  esac
}

depot_hote() { # nom url signé(1|0) : repomd.xml vérifié (gpgv, si signé), primary contrôlé par repomd et décompressé dans $T/<nom>.primary.xml
  local d=$T/hote h p s
  curl -fsSL --max-time 60 -o "$d/$1.repomd.xml" "$2/repodata/repomd.xml"
  if curl -fsSL --max-time 60 -o "$d/$1.repomd.xml.asc" "$2/repodata/repomd.xml.asc" 2>/dev/null; then
    s=$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/$1.repomd.xml.asc" "$d/$1.repomd.xml" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}')
    echo "$1 : repomd.xml signé, signataire ${s:-aucun valide}"
    [ "$3" = 0 ] || attendu "$1 : signataire de repomd.xml (clé primaire)" "$s" "$4"
  else
    echo "$1 : repomd.xml.asc absent"
    [ "$3" = 0 ] || { echo "KO   $1 : repomd.xml non signé" >&2; exit 1; }
  fi
  h=$(sha256sum < "$d/$1.repomd.xml" | cut -c1-64); echo "$h" > "$T/$1.repomd.sha256"
  echo "$1 : repomd.xml sha256 $h"
  read -r p s < <(python3 -I - "$d/$1.repomd.xml" <<'PY'
import sys, xml.etree.ElementTree as E
n = {'r': 'http://linux.duke.edu/metadata/repo'}
for d in E.parse(sys.argv[1]).getroot().findall('r:data', n):
    if d.get('type') == 'primary':
        c = d.find('r:checksum', n)
        print(d.find('r:location', n).get('href'), c.text if c.get('type') == 'sha256' else 'type-' + c.get('type'))
PY
  )
  curl -fsSL --max-time 300 -o "$d/$1.${p##*/}" "$2/$p"
  attendu "$1 : ${p##*/} contrôlé par repomd.xml" "$(sha256sum < "$d/$1.${p##*/}" | cut -c1-64)" "$s"
  decompresser "$d/$1.${p##*/}" > "$T/$1.primary.xml"
}

etape_prealables() { # cluster et Zot, en lecture seule et dry-run
  echo "## politique de sortie rpm (décision du propriétaire, appliquée hors de ce script)"
  kubectl get cnp -n builds prefetch-rpm-sortie </dev/null >/dev/null 2>&1 \
    && echo "OK   CiliumNetworkPolicy prefetch-rpm-sortie présente" \
    || { echo "KO   prefetch-rpm-sortie absente : proposition dans politiques/prefetch-rpm-sortie.yaml, à décider" >&2; exit 1; }
  attendu "NotIn de builds-sans-internet" \
    "$(kubectl get cnp -n builds builds-sans-internet -o json </dev/null | jq -r '.spec.endpointSelector.matchExpressions[0].values | sort | join(",")')" \
    "prefetch-deb,prefetch-gomod,prefetch-rpm"
  echo "## exemption Pod Security de la RuntimeClass kata"
  args_apiserver | grep -x -- "--admission-control-config-file=$D_CONF/pod-security.yaml" >/dev/null \
    && echo "OK   kube-apiserver lit $D_CONF/pod-security.yaml" || { echo "KO   exemption de kata absente" >&2; exit 1; }
  echo "## admission en dry-run serveur (image d'amorce : les règles ne lisent que la forme de la référence)"
  pod_spec s1-05-racine "$AMORCE"
  if kubectl create --dry-run=server -f "$T/s1-05-racine.json" </dev/null > "$T/admis.out" 2>&1; then echo "OK   s1-05-racine : admis"
  else echo "KO   s1-05-racine : refusé à l'admission" >&2; cat "$T/admis.out" >&2; exit 1; fi
  echo "## sc-build"
  kubectl get node sc-build -o json </dev/null | jq -r '"allouable : \(.status.allocatable.cpu) CPU, \(.status.allocatable.memory)"'
  kubectl get pods -A --field-selector spec.nodeName=sc-build,status.phase=Running -o json </dev/null \
    | jq -r '[.items[].spec.containers[].resources.requests.memory // empty] | "demandes de mémoire en cours : \(length) conteneur(s) : \(join(" "))"'
  echo "## place libre pour Zot"
  sur sc-stockage 'df -B1M --output=avail,target /var/lib/zot | tail -n 1' </dev/null | awk '{print "libre sous " $2 " : " $1 " Mo"}'
}

etape_hote() { # hôte seul, ni cluster ni Zot : peut tourner avant S5b ; à rejouer avant racine (pub/9.8 et EPEL bougent)
  local d n fp e
  echo "## sources de sample-app"
  (cd "$PKG" && grep -E '  (sample-app-1\.0\.0\.tar\.gz|sample-app\.spec)$' SHA256SUMS | sha256sum -c -)
  echo "## clés, vérifiées sur l'hôte"
  d=$T/hote; rm -rf -- "${d:?}"; mkdir -p "$d"
  curl -fsSL --max-time 60 -o "$d/RPM-GPG-KEY-Rocky-9" "$CLE_ROCKY"
  curl -fsSL --max-time 60 -o "$d/RPM-GPG-KEY-EPEL-9" "$CLE_EPEL"
  for n in RPM-GPG-KEY-Rocky-9 RPM-GPG-KEY-EPEL-9; do
    gpg --no-default-keyring --keyring "$d/cles.gpg" --batch --quiet --import "$d/$n" 2>/dev/null
    echo "$n : sha256 $(sha256sum < "$d/$n" | cut -c1-64)"
  done
  fp=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  attendu "empreinte de la clé de Rocky" "$fp" "$FP_ROCKY"
  e=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-EPEL-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  echo "empreinte de la clé d'EPEL 9 : $e"
  curl -fsSL --max-time 60 "$PAGE_EPEL" | tr -d ' \n' | tr 'a-f' 'A-F' > "$d/page-epel.txt"
  grep -q -- "$e" "$d/page-epel.txt" && echo "OK   empreinte d'EPEL 9 présente sur $PAGE_EPEL" \
    || { echo "KO   empreinte d'EPEL 9 absente de $PAGE_EPEL" >&2; exit 1; }
  echo "$e" > "$T/fp-epel"
  echo "## dépôts, vérifiés sur l'hôte"
  depot_hote baseos98 "$ROCKY98/BaseOS/x86_64/os" 1 "$FP_ROCKY"
  depot_hote appstream98 "$ROCKY98/AppStream/x86_64/os" 1 "$FP_ROCKY"
  depot_hote epel9 "$EPEL9" 0 "$e"
  for n in BaseOS AppStream CRB extras; do
    curl -fsSL --max-time 60 -o "$d/v97-$n.repomd.xml" "$VAULT97/$n/x86_64/os/repodata/repomd.xml"
    curl -fsSL --max-time 60 -o "$d/v97-$n.repomd.xml.asc" "$VAULT97/$n/x86_64/os/repodata/repomd.xml.asc"
    attendu "vault 9.7 $n : signataire de repomd.xml" \
      "$(gpgv --keyring "$d/cles.gpg" --status-fd 1 "$d/v97-$n.repomd.xml.asc" "$d/v97-$n.repomd.xml" 2>/dev/null | awk '$2 == "VALIDSIG" {print $NF}')" "$FP_ROCKY"
    echo "vault 9.7 $n : repomd.xml sha256 $(sha256sum < "$d/v97-$n.repomd.xml" | cut -c1-64)"
  done
  echo "## paquets épinglés"
  python3 -I - "$T" "${EPINGLES[@]}" <<'PY'
import sys, xml.etree.ElementTree as E
t = sys.argv[1]; ko = 0
n = {'c': 'http://linux.duke.edu/metadata/common'}
idx = {}
for depot in ('baseos98', 'appstream98', 'epel9'):   # lecture en flux : le primary d'AppStream est gros
    for _, p in E.iterparse(f'{t}/{depot}.primary.xml'):
        if p.tag != '{http://linux.duke.edu/metadata/common}package': continue
        v = p.find('c:version', n)
        idx.setdefault((depot, p.find('c:name', n).text, f"{v.get('ver')}-{v.get('rel')}"), []).append(
            (p.find('c:arch', n).text, v.get('epoch'), p.find('c:checksum', n).text, p.find('c:location', n).get('href')))
        p.clear()
for e in sys.argv[2:]:
    nom, vr, depot = e.split()
    c = [x for x in idx.get((depot, nom, vr), []) if x[0] in ('x86_64', 'noarch')]
    if len(c) == 1:
        a, ep, h, href = c[0]
        print(f'OK   {nom}-{ep}:{vr}.{a} dans {depot} : sha256 {h} ({href})')
    else:
        ko = 1; print(f'KO   {nom}-{vr} dans {depot} : {len(c)} candidat(s) x86_64 ou noarch')
sys.exit(ko)
PY
}

etape_amorce() {
  auth_zot "$T/zot.json"
  mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"
  miroir "quay.io/rockylinux/rockylinux@$AMORCE_DIGEST" "$DEPOT_AMONT" "$T/zot.json"
  miroir "quay.io/rockylinux/rockylinux@$BOOT_DIGEST" "$DEPOT_AMONT" "$T/zot.json"
  attendu "digest de l'amorce 9.8 dans Zot" "$(zot crane digest "$REG_HOTE/$DEPOT_AMONT@$AMORCE_DIGEST")" "$AMORCE_DIGEST"
  attendu "digest du bootstrap 9.7 dans Zot" "$(zot crane digest "$REG_HOTE/$DEPOT_AMONT@$BOOT_DIGEST")" "$BOOT_DIGEST"
}

# Script de la racine (root, image 9.8). dnf ne lit que /w/dnf.conf (reposdir vide) ; les clés viennent de l'hôte.
RACINE='set -u
echo "invité : $(uname -r), $(nproc) vCPU, $(awk "/MemTotal/ {print \$2}" /proc/meminfo) kB ; /w : $(awk "\$2 == \"/w\" {print \$3}" /proc/mounts)"
echo "dnf : $(dnf --version 2>/dev/null | head -1) ; rpm : $(rpm --version)"
mkdir -p /w/aucun /w/racine /w/cache
t=$(date +%s)
dnf -y -q -c /w/dnf.conf --setopt=reposdir=/w/aucun --installroot=/w/racine --releasever=9 makecache > /w/makecache.log 2>&1
echo "makecache : rc $? en $(($(date +%s) - t)) s"
C="/w/cache /w/racine/w/cache"   # dnf peut placer cachedir dans la racine (--installroot) : les deux sont lus
echo "caches : $(for c in $C; do [ -d $c ] && printf "%s " $c; done)"
for r in baseos98 appstream98 epel9; do f=$(find $C -path "*/$r-*/repodata/repomd.xml" 2>/dev/null | head -1); echo "repomd $r : sha256 $(sha256sum < "$f" | cut -c1-64)"; done
t=$(date +%s)
dnf -y -c /w/dnf.conf --setopt=reposdir=/w/aucun --installroot=/w/racine --releasever=9 install @PAQUETS@ rocky-release shadow-utils > /w/install.log 2>&1
r=$?; echo "installation : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || { tail -n 25 /w/install.log; exit 0; }
for f in $(find $C -name "*.rpm" 2>/dev/null | sort); do d=$(basename "$(dirname "$(dirname "$f")")"); echo "rpm ${d%-*} ${f##*/} $(sha256sum < $f | cut -c1-64)"; done
rpm --root /w/racine -K $(find $C -name "*.rpm" 2>/dev/null) > /w/k.log 2>&1
echo "rpm -K : $(grep -c -E "digests signatures OK$" /w/k.log) OK sur $(find $C -name "*.rpm" 2>/dev/null | wc -l)"
grep -v -E "digests signatures OK$" /w/k.log | head -n 5
rpm --root /w/racine -qa --qf "%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort > /w/nevra.txt
echo "paquets installés : $(wc -l < /w/nevra.txt)"
for p in mock mock-core-configs podman skopeo systemd-container; do echo "installé : $(grep -E "^$p-[0-9]+:" /w/nevra.txt || echo "$p absent")"; done
rm -rf /w/racine/var/cache/dnf /w/racine/w
tar --sort=name --format=posix --xattrs --xattrs-include="*" --numeric-owner -C /w/racine -cf /w/racine.tar .
echo "archive racine : $(stat -c %s /w/racine.tar) octets, sha256 $(sha256sum < /w/racine.tar | cut -c1-64)"
'

dnf_conf() { # configuration de dnf de l'étape racine
  cat <<EOF
[main]
gpgcheck=1
install_weak_deps=0
keepcache=1
cachedir=/w/cache
reposdir=/w/aucun
tsflags=nodocs
[baseos98]
name=Rocky 9.8 BaseOS
baseurl=$ROCKY98/BaseOS/x86_64/os/
repo_gpgcheck=1
gpgkey=file:///w/cles/RPM-GPG-KEY-Rocky-9
[appstream98]
name=Rocky 9.8 AppStream
baseurl=$ROCKY98/AppStream/x86_64/os/
repo_gpgcheck=1
gpgkey=file:///w/cles/RPM-GPG-KEY-Rocky-9
[epel9]
name=EPEL 9
baseurl=$EPEL9/
repo_gpgcheck=0
gpgkey=file:///w/cles/RPM-GPG-KEY-EPEL-9
EOF
}

controle_rpms() { # journal : chaque « rpm <dépôt> <fichier> <sha256> » comparé au primary vérifié sur l'hôte
  python3 -I - "$T" "$1" <<'PY'
import sys, xml.etree.ElementTree as E
t = sys.argv[1]; n = {'c': 'http://linux.duke.edu/metadata/common'}; pk = {}
for depot in ('baseos98', 'appstream98', 'epel9'):   # lecture en flux
    for _, p in E.iterparse(f'{t}/{depot}.primary.xml'):
        if p.tag != '{http://linux.duke.edu/metadata/common}package': continue
        pk[(depot, p.find('c:location', n).get('href').rsplit('/', 1)[1])] = p.find('c:checksum', n).text
        p.clear()
c = {}; ko = []
for l in open(sys.argv[2], encoding='utf-8'):
    x = l.split()
    if len(x) == 4 and x[0] == 'rpm':
        c[x[1]] = c.get(x[1], 0) + 1
        if pk.get((x[1], x[2])) != x[3]: ko.append(x[1] + ' ' + x[2])
print('paquets contrôlés : ' + ', '.join(f'{k} {v}' for k, v in sorted(c.items())))
print(('OK   ' if not ko and c else 'KO   ') + f'sha256 des rpm conformes aux primary vérifiés : {sum(c.values()) - len(ko)} sur {sum(c.values())}')
for k in ko[:10]: print('     écart : ' + k)
sys.exit(1 if ko or not c else 0)
PY
}

etape_racine() {
  local s r p=""
  for r in baseos98 appstream98 epel9; do [ -s "$T/$r.repomd.sha256" ] && [ -s "$T/$r.primary.xml" ] || { echo "KO   lancer d'abord l'étape hote" >&2; exit 1; }; done
  for r in "${EPINGLES[@]}"; do set -- $r; p="$p $1-$2"; done
  pod_spec s1-05-racine "$AMORCE"
  pod_demarrer s1-05-racine
  livrer s1-05-racine /w/cles/RPM-GPG-KEY-Rocky-9 "$T/hote/RPM-GPG-KEY-Rocky-9"
  livrer s1-05-racine /w/cles/RPM-GPG-KEY-EPEL-9 "$T/hote/RPM-GPG-KEY-EPEL-9"
  dnf_conf > "$T/dnf.conf" && livrer s1-05-racine /w/dnf.conf "$T/dnf.conf"
  sed -e "s|@PAQUETS@|${p# }|g" <<<"$RACINE" | dans s1-05-racine racine
  for r in baseos98 appstream98 epel9; do
    attendu "repomd $r lu par dnf dans le pod = repomd vérifié sur l'hôte" "$(champ racine "repomd $r" | sed 's/^sha256 //')" "$(cat "$T/$r.repomd.sha256")"
  done
  controle_rpms "$T/racine.log" || echo "ÉCART empreintes des rpm : voir ci-dessus (dnf les a déjà contrôlées contre ses métadonnées)"
  s=$(sed -n 's/^archive racine : .*sha256 \([0-9a-f]\{64\}\)$/\1/p' "$T/racine.log")
  [ -n "$s" ] || { pod_retirer s1-05-racine; echo "KO   archive racine absente" >&2; exit 1; }
  kubectl exec -n builds s1-05-racine -- cat /w/racine.tar </dev/null > "$T/racine.tar"
  attendu "archive racine rapatriée" "$(sha256sum < "$T/racine.tar" | cut -c1-64)" "$s"
  pod_retirer s1-05-racine
}

# Configuration de mock : modèle rocky-9 de mock-core-configs 45.2-1, mirrorlist de BaseOS, AppStream, CRB et extras remplacés par les
# baseurl fixes de vault 9.7 (D2 a) ; image de bootstrap par digest dans Zot, non « prête » (mock y installe dnf : M2 exigera
# une image prête) ; macros d'OBS (poc.prjconf) ; racines de mock sous /w (tmpfs).
MOCK_CFG="include('templates/rocky-9.tpl')
config_opts['root'] = '$CFG'
config_opts['target_arch'] = 'x86_64'
config_opts['legal_host_arches'] = ('x86_64',)
config_opts['basedir'] = '/w/mock'
config_opts['cache_topdir'] = '/w/mock-cache'
config_opts['use_bootstrap_image'] = True
config_opts['bootstrap_image'] = '$BOOT'
config_opts['bootstrap_image_ready'] = False
config_opts['macros']['%_buildhost'] = 'reproducible'
config_opts['macros']['%source_date_epoch_from_changelog'] = '1'
config_opts['macros']['%use_source_date_epoch_as_buildtime'] = '1'
config_opts['macros']['%clamp_mtime_to_source_date_epoch'] = '1'
for r in ('BaseOS', 'AppStream', 'CRB', 'extras'):
    config_opts['dnf.conf'] = config_opts['dnf.conf'].replace(
        'mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=\$basearch&repo=%s-\$releasever\n' % r,
        'baseurl=$VAULT97/%s/x86_64/os/\n' % r)
"

STOCKAGE='[storage]
driver = "overlay"
graphroot = "/w/containers"
runroot = "/w/run-containers"
'

etape_image() {
  local d c=$T/couche-config
  [ -s "$T/racine.tar" ] || { echo "KO   lancer d'abord l'étape racine" >&2; exit 1; }
  rm -rf -- "${c:?}" && mkdir -p "$c/etc/mock" "$c/etc/containers"
  printf '%s' "$MOCK_CFG" > "$c/etc/mock/$CFG.cfg"
  printf '%s' "$MOCK_CFG" | sed -e "s|'root'\] = '$CFG'|'root'] = '$CFG_PRET'|" \
    -e "s|'bootstrap_image_ready'\] = False|'bootstrap_image_ready'] = True|" > "$c/etc/mock/$CFG_PRET.cfg"
  attendu "configuration prête : racine et bootstrap_image_ready changés, rien d'autre" \
    "$(diff "$c/etc/mock/$CFG.cfg" "$c/etc/mock/$CFG_PRET.cfg" | grep -c '^[<>]')" 4
  printf '%s' "$STOCKAGE" > "$c/etc/containers/storage.conf"
  echo "configuration de mock : sha256 $(sha256sum < "$c/etc/mock/$CFG.cfg" | cut -c1-64)"
  tar --sort=name --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --mtime=@0 \
    --owner=0 --group=0 --numeric-owner -C "$c" -cf "$T/couche-config.tar" etc
  [ -s "$T/docker/config.json" ] || { auth_zot "$T/zot.json"; mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"; }
  zot crane append --oci-empty-base -f "$T/racine.tar" -f "$T/couche-config.tar" -t "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" >/dev/null 2>"$T/crane.err" \
    || { cat "$T/crane.err" >&2; exit 1; }
  zot crane mutate "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" --set-platform linux/amd64 -t "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE" \
    -e PATH=/usr/sbin:/usr/bin:/sbin:/bin -e HOME=/root >/dev/null 2>"$T/crane.err" || { cat "$T/crane.err" >&2; exit 1; }
  d=$(zot crane digest "$REG_HOTE/$DEPOT_ESSAI:$PREFIXE")
  echo "$d" > "$T/image.digest"
  zot crane manifest "$REG_HOTE/$DEPOT_ESSAI@$d" | jq -r '.layers[] | "couche \(.digest) \(.size) octets"'
  echo "image d'essai : $REG/$DEPOT_ESSAI@$d"
}

SONDE='set -u
echo "uid : $(id -u)"
grep -E "^(CapEff|CapBnd|NoNewPrivs|Seccomp):" /proc/self/status
awk "\$2 == \"/\" || \$2 == \"/w\" {print \"montage \" \$2 \" : \" \$3 \" \" \$4}" /proc/mounts
df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
rpm -q mock mock-core-configs podman skopeo systemd-container distribution-gpg-keys 2>&1 | sed "s/^/version : /"
grep -h -E "gpgkey" /etc/mock/templates/rocky-9.tpl | sort -u | head -n 5 | sed "s/^/gpgkey du modèle : /"
for k in /usr/share/distribution-gpg-keys/rocky/*; do
  echo "clé ${k##*/} : $(gpg --batch --with-colons --show-keys "$k" 2>/dev/null | awk -F: "\$1 == \"fpr\" {print \$10; exit}")"
done
mock -r @CFG@ --debug-config > /w/debug-config.log 2>&1; echo "mock --debug-config : rc $?"
grep -o -E "(baseurl|mirrorlist|metalink)=[^[:space:]\\\\]+" /w/debug-config.log | sort | uniq -c | sed "s/^/dépôt de mock : /"
n=$(grep -o -E "mirrorlist=[^[:space:]\\\\]*repo=(BaseOS|AppStream|CRB|extras)-[$]releasever([^-]|$)" /w/debug-config.log | wc -l)
echo "mirrorlist restants pour BaseOS, AppStream, CRB et extras : $n"
[ "$n" = 0 ] || { echo "KO   remplacement des mirrorlist par vault 9.7 incomplet : mock non lancé"; exit 0; }
echo "## podman imbriqué"
podman info --format "stockage : {{.Store.GraphDriverName}} sous {{.Store.GraphRoot}}" 2>&1 | tail -n 1
t=$(date +%s); podman pull @BOOT@ > /w/pull.log 2>&1
r=$?; echo "podman pull du bootstrap : rc $r en $(($(date +%s) - t)) s"; [ $r = 0 ] || tail -n 5 /w/pull.log
m=$(podman image mount @BOOT@ 2>/w/mount.err); r=$?
echo "podman image mount : rc $r ; os-release : $(grep -h ^VERSION_ID= "$m/etc/os-release" 2>/dev/null)"; [ $r = 0 ] || tail -n 3 /w/mount.err
podman image umount @BOOT@ >/dev/null 2>&1
echo "## mock"
cd /w/src && sha256sum -c SHA256SUMS.s1 > /w/c.log 2>&1; echo "sources livrées : rc $? $(paste -sd " " /w/c.log)"
for iso in nspawn simple; do
  mkdir -p /w/res-$iso
  t=$(date +%s)
  mock -r @CFG@ --isolation=$iso --uniqueext=$iso --resultdir=/w/res-$iso --buildsrpm --spec /w/src/sample-app.spec \
    --sources /w/src > /w/mock-$iso-srpm.log 2>&1
  r=$?; echo "mock $iso --buildsrpm : rc $r en $(($(date +%s) - t)) s"
  [ $r = 0 ] || { tail -n 25 /w/mock-$iso-srpm.log; tail -n 25 /w/res-$iso/root.log 2>/dev/null; mock -r @CFG@ --uniqueext=$iso --scrub=all >/dev/null 2>&1; continue; }
  s=$(ls /w/res-$iso/*.src.rpm | head -1); echo "src.rpm $iso : ${s##*/} $(sha256sum < $s | cut -c1-64)"
  t=$(date +%s)
  mock -r @CFG@ --isolation=$iso --uniqueext=$iso --resultdir=/w/res-$iso --no-clean --rebuild "$s" > /w/mock-$iso-rebuild.log 2>&1
  r=$?; echo "mock $iso --rebuild : rc $r en $(($(date +%s) - t)) s"
  [ $r = 0 ] || { tail -n 25 /w/mock-$iso-rebuild.log; tail -n 25 /w/res-$iso/build.log 2>/dev/null; }
  for f in /w/res-$iso/*.rpm; do case $f in *.src.rpm) ;; *) [ -e "$f" ] && echo "rpm $iso : ${f##*/} $(sha256sum < $f | cut -c1-64)" ;; esac; done
  echo "place de /w après $iso : $(du -sm /w 2>/dev/null | cut -f1) Mo"
  mock -r @CFG@ --uniqueext=$iso --scrub=all > /w/scrub-$iso.log 2>&1; echo "scrub $iso : rc $?"
done
true'

# Ajout N3 et N4 (../s1-n34.patch, préparé à sec le 16/11/2026, NON APPLIQUÉ). SONDE reste inchangée : P9 à P11 et les durées
# gardent leur sens. En-tête lu par rpm -qp dans le pod (l'hôte n'a pas rpm) ; sorties brutes, contrôlées dans les notes contre les
# prédictions. golang-NOTICES contient la chaîne runtime/memmove_amd64.s : N4 ne lit que le binaire isolé (n34-binaire.py).
SONDE_N34='set -u
for iso in nspawn simple; do
  echo "## $iso"
  set -- /w/res-$iso/sample-app-[0-9]*.x86_64.rpm
  [ -e "$1" ] || { echo "rpm binaire de sample-app ($iso) : aucun"; continue; }
  echo "rpm binaire de sample-app ($iso) : $# fichier(s)"
  [ $# = 1 ] || { echo "plusieurs rpm binaires : lecture non faite"; continue; }
  f=$1
  echo "algorithme des empreintes de fichiers : $(rpm -qp --qf "%{FILEDIGESTALGO}" "$f" 2>&1)"
  rpm -qp --qf "[%{FILEFLAGS} %{FILENAMES} %{FILEDIGESTS}\n]" "$f" > /w/n34/fichiers-$iso.txt 2>&1
  echo "rpm -qp, fichiers : rc $?, $(wc -l < /w/n34/fichiers-$iso.txt) ligne(s)"
  grep " /usr/share/licenses/" /w/n34/fichiers-$iso.txt | while read -r fl nm dg; do
    case $fl in ""|*[!0-9]*) echo "licence, ligne illisible : $fl $nm $dg"; continue ;; esac
    echo "licence : $nm ; drapeaux $fl ; bit 128 : $((fl / 128 % 2)) ; empreinte ${dg:-aucune}"
  done
  echo "dates : $(rpm -qp --qf "buildtime %{BUILDTIME} ; changelogtime %{CHANGELOGTIME}" "$f" 2>&1)"
  rpm -qp --qf "[%{FILEMTIMES}\n]" "$f" 2>&1 | sort -u > /w/n34/mtimes-$iso.txt
  echo "mtime des fichiers : $(wc -l < /w/n34/mtimes-$iso.txt) valeur(s) distincte(s), min $(sort -n /w/n34/mtimes-$iso.txt | head -n 1), max $(sort -n /w/n34/mtimes-$iso.txt | tail -n 1)"
  rpm2cpio "$f" > /w/n34/charge-$iso.cpio 2> /w/n34/rpm2cpio-$iso.err
  echo "rpm2cpio : rc $?, $(wc -c < /w/n34/charge-$iso.cpio) octets"
  python3 -I /w/n34/n34-binaire.py /w/n34/charge-$iso.cpio 2>&1; echo "n34-binaire.py : rc $?"
  rm -f /w/n34/charge-$iso.cpio
done
true'

rapatrier_rpms() { # nom : rpm binaires de sample-app copiés du pod sous $T/rpm-<isolation>, sha256 comparé à la sonde ; n'arrête rien
  local iso f s a
  for iso in nspawn simple; do
    rm -rf "$T/rpm-$iso"; mkdir -p "$T/rpm-$iso"
    for f in $(kubectl exec -n builds "$1" -- sh -c "cd /w/res-$iso 2>/dev/null && ls sample-app-[0-9]*.x86_64.rpm 2>/dev/null; true" </dev/null); do
      if kubectl exec -n builds "$1" -- cat "/w/res-$iso/$f" </dev/null > "$T/rpm-$iso/$f"; then
        s=$(sha256sum < "$T/rpm-$iso/$f" | cut -c1-64)
        a=$(sed -n "s/^rpm $iso : $f \([0-9a-f]\{64\}\)$/\1/p" "$T/essais.log")
        if [ "$s" = "$a" ]; then echo "OK   rpm $iso rapatrié : $f $s"; else echo "ÉCART rpm $iso rapatrié : $f $s (sonde : ${a:-absente})"; fi
      else echo "ÉCART rpm $iso : copie de $f en échec"; fi
    done
  done
}

etape_essais() {
  local d img n=s1-05-essais
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  img=$REG/$DEPOT_ESSAI@$d
  echo "image : $img"
  (cd "$PKG" && grep -E '  (sample-app-1\.0\.0\.tar\.gz|sample-app\.spec)$' SHA256SUMS) > "$T/SHA256SUMS.s1"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$n" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$n" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  sed -e "s|@CFG@|$CFG|g" -e "s|@BOOT@|$BOOT|g" <<<"$SONDE" | dans "$n" essais
  kubectl exec -n builds "$n" -- sh -c 'for f in /w/res-*/build.log /w/res-*/root.log; do [ -e "$f" ] && { echo "### $f"; tail -n 200 "$f"; }; done' \
    </dev/null 2>&1 | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-essais-mock.log" || true
  echo "journaux de mock : $(wc -l < "$R/$PREFIXE-essais-mock.log") lignes, resultats/$PREFIXE-essais-mock.log"
  echo "## N3 et N4 : rpm binaire de sample-app (ajout ../s1-n34.patch)"
  rapatrier_rpms "$n"
  livrer "$n" /w/n34/n34-binaire.py "$here/n34-binaire.py"
  dans "$n" essais-n34 <<<"$SONDE_N34"
  pod_retirer "$n"
}

# Étape verrou (ajoutée à sec le 12/11/2026 à partir de 14:43:15 UTC, après le relevé de M2, NON LANCÉE) : --hermetic-build refuse
# un verrou calculé sans bootstrap_image_ready=True (mock 6.9, config.py:824). Même configuration que $CFG, sauf la racine et
# bootstrap_image_ready=True : rockylinux:9.7 brut est-il une image « prête » ? Isolation : celle que essais aura vue passer
# (ISOLATION, simple par défaut, d'après P9). Le verrou produit est archivé (resultats/s1-verrou.json) ; rien n'est poussé.
# Corrigée à sec le 12/11/2026 à partir de 15:23:35 UTC, NON LANCÉE, sur accord à venir : --debug-config écrit
# « config_opts['clé'] = valeur », et seulement les clés qui diffèrent du défaut (mock.py:605 à :619) ; l'ancien motif
# « bootstrap_image_ready.: » n'aurait rien trouvé, sans le signaler. Ajout proposé après releve2 : les quatre options bootstrap_*
# qui annulent « prête » (buildroot.py:1182 à :1185) et les messages de bootstrap_image_is_ready relevés dans tout root.log
# après chaque appel de mock (root.log est ouvert en ajout, buildroot.py:699 : les nombres sont cumulés).
ISOLATION=${ISOLATION:-simple}
SONDE_VERROU='set -u
echo "isolation : @ISO@ ; configuration : @CFG_PRET@"
cd /w/src && sha256sum -c SHA256SUMS.s1 > /w/c.log 2>&1; echo "sources livrées : rc $? $(paste -sd " " /w/c.log)"
mock -r @CFG_PRET@ --debug-config > /w/verrou-debug-config.log 2>&1; rd=$?; echo "mock --debug-config : rc $rd"
if [ $rd != 0 ]; then echo "configuration : illisible, --debug-config en échec"; tail -n 5 /w/verrou-debug-config.log
else
  P="^config_opts\[.bootstrap_image_ready.\]"
  if grep -q -E "$P" /w/verrou-debug-config.log; then grep -E "$P" /w/verrou-debug-config.log | sed "s/^/configuration : /"
  else echo "configuration : bootstrap_image_ready absent de --debug-config, donc valeur par défaut (False)"; fi
  O="^config_opts\[.bootstrap_(module_enable|module_install|module_setup_commands|chroot_additional_packages).\]"
  echo "options bootstrap_* qui annulent « prête », posées : $(grep -c -E "$O" /w/verrou-debug-config.log) (absente = valeur par défaut, vide)"
  grep -E "$O" /w/verrou-debug-config.log | sed "s/^/option posée : /"
fi
M="Not updating bootstrap chroot|Package management in bootstrap|Bootstrap image not marked ready"
etat() { c=$(grep -c -E "$M" /w/res-verrou/root.log 2>/dev/null); echo "root.log, $1 : ${c:-root.log absent} ligne(s) sur le bootstrap prêt ou non, cumulées"
  grep -E "$M" /w/res-verrou/root.log 2>/dev/null | sed "s/^/root.log, $1 : /"; }
mkdir -p /w/res-verrou
t=$(date +%s)
mock -r @CFG_PRET@ --isolation=@ISO@ --resultdir=/w/res-verrou --buildsrpm --spec /w/src/sample-app.spec --sources /w/src > /w/verrou-srpm.log 2>&1
r=$?; echo "mock --buildsrpm (image prête) : rc $r en $(($(date +%s) - t)) s"
etat "après --buildsrpm"
[ $r = 0 ] || { tail -n 25 /w/verrou-srpm.log; tail -n 25 /w/res-verrou/root.log 2>/dev/null; exit 0; }
s=$(ls /w/res-verrou/*.src.rpm | head -1); echo "src.rpm : ${s##*/} $(sha256sum < $s | cut -c1-64)"
t=$(date +%s)
mock -r @CFG_PRET@ --isolation=@ISO@ --resultdir=/w/res-verrou --calculate-build-dependencies "$s" > /w/verrou-calc.log 2>&1
r=$?; echo "mock --calculate-build-dependencies : rc $r en $(($(date +%s) - t)) s"
etat "après --calculate-build-dependencies"
[ $r = 0 ] || { tail -n 25 /w/verrou-calc.log; tail -n 25 /w/res-verrou/root.log 2>/dev/null; }
ls -l /w/res-verrou | sed "s/^/résultat : /"
for f in /w/res-verrou/*.json; do [ -e "$f" ] && echo "verrou : ${f##*/} $(stat -c %s "$f") octets, sha256 $(sha256sum < "$f" | cut -c1-64)"; done
true'

etape_verrou() {
  local d img n=s1-05-verrou f
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  img=$REG/$DEPOT_ESSAI@$d
  echo "image : $img ; isolation : $ISOLATION"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$n" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$n" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  sed -e "s|@CFG_PRET@|$CFG_PRET|g" -e "s|@ISO@|$ISOLATION|g" <<<"$SONDE_VERROU" | dans "$n" verrou
  f=$(kubectl exec -n builds "$n" -- sh -c 'ls /w/res-verrou/*.json 2>/dev/null | head -1' </dev/null || true)
  if [ -n "$f" ]; then
    kubectl exec -n builds "$n" -- cat "$f" </dev/null | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-verrou.json"
    python3 -I - "$R/$PREFIXE-verrou.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
c = d.get('config', {})
print('version du verrou :', d.get('version'))
print('options de configuration recopiées :', ', '.join(sorted(c)))
print('bootstrap_image_ready enregistré :', c.get('bootstrap_image_ready'))
print('macros recopiées :', 'oui' if any('macro' in k for k in c) else 'non')
bs = d.get('bootstrap', {})
print('bootstrap, pull_digest (digest du manifeste tiré) :', bs.get('pull_digest'))
print('bootstrap, image_digest (sha256 de RootFS et Config, podman.py:21) :', bs.get('image_digest'))
print('bootstrap, architecture :', bs.get('architecture'))
b = d.get('buildroot', {}).get('rpms', [])
print('rpm du buildroot :', len(b), '; champs :', ', '.join(sorted(b[0])) if b else '-')
PY
  else echo "aucun verrou produit"; fi
  kubectl exec -n builds "$n" -- sh -c 'for f in /w/res-verrou/root.log /w/res-verrou/build.log; do [ -e "$f" ] && { echo "### $f"; tail -n 200 "$f"; }; done' \
    </dev/null 2>&1 | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-verrou-mock.log" || true
  pod_retirer "$n"
}

# Étape verrou_brut (ajoutée à sec le 17/11/2026 à partir de 13:09:43 UTC, NON LANCÉE ; décision du propriétaire « Mesurer
# d'abord ») : la sonde de verrou, avec la configuration $CFG (bootstrap_image_ready=False) au lieu de $CFG_PRET. mock installe
# alors lui-même dnf et builddep dans le bootstrap tiré de rockylinux:9.7 brut, comme à essais, puis calcule. D'après le code
# (buildroot_lock.py:28 à :117, lecture), le greffon écrit le verrou quel que soit bootstrap_image_ready ; --hermetic-build le
# refusera (config.py:824) : il est archivé pour lecture, sans suite. Mesure ce qu'une image dérivée ne corrigerait pas (adresse
# de chaque paquet, podman image inspect après rmi) et, par SONDE_BOOT, les paquets que mock ajoute à l'image brute (base de
# l'épinglage de l'image dérivée). --no-cleanup-after garde le bootstrap pour SONDE_BOOT (cleanup_on_success, rebuild.py:32).
# Étiquettes de signature : celle du champ signature du verrou (sigpgp:pgpsig, installed_packages.py:62 à :64) et rsaheader.
# Ordre : SONDE_BOOT et journaux avant le résumé du verrou, qui ne peut pas arrêter l'étape (branche jamais jouée en vrai).
# SONDE_BOOT lit chaque base rpm sur une copie de var/lib/rpm (--dbpath) : le montage de podman image mount n'est jamais écrit ;
# chaque liste et le df valent seuls, même si l'autre lecture échoue ; stderr de rpm compté à part, jamais dans les listes.
# SONDE_VERROU et etape_verrou ne changent pas ; journaux distincts : s1-verrou_brut*.
SONDE_BOOT='set -u
export LC_ALL=C
Q="%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE} sigpgp=%{SIGPGP:pgpsig} rsaheader=%{RSAHEADER:pgpsig}\n"
liste() { # racine nom libellé : var/lib/rpm de la racine copié sous /w, lu par --dbpath ; liste triée, stderr à part
  rm -rf "/w/rpmdb-$2"
  cp -a "$1/var/lib/rpm" "/w/rpmdb-$2" 2> "/w/$2.cp.err" || { echo "$3 : copie de var/lib/rpm en échec"; tail -n 3 "/w/$2.cp.err"; return 1; }
  rpm --dbpath "/w/rpmdb-$2" -qa --qf "$Q" > "/w/$2.brut" 2> "/w/$2.err"; r=$?
  sort "/w/$2.brut" > "/w/$2.txt"
  echo "$3 : rpm -qa rc $r, $(wc -l < "/w/$2.txt") ligne(s), stderr $(wc -l < "/w/$2.err") ligne(s)"
  head -n 3 "/w/$2.err" | sed "s/^/$3, stderr : /"
}
set -- /w/mock/@CFG@-bootstrap*/root
echo "bootstrap préparé par mock : $# chemin(s) pour /w/mock/@CFG@-bootstrap*/root ; retenu : $1"
a=0
if [ -d "$1" ]; then liste "$1" boot-mock "bootstrap de mock" && a=1
else echo "bootstrap préparé par mock : $1 absent"; ls -d /w/mock/* 2>&1 | sed "s/^/dossier de mock : /"; fi
i=0
t=$(date +%s); podman pull @BOOT@ > /w/pull-brut.log 2>&1; r=$?
echo "podman pull de rockylinux:9.7 brut : rc $r en $(($(date +%s) - t)) s"
if [ $r = 0 ]; then
  m=$(podman image mount @BOOT@ 2>/w/mount-brut.err); r=$?; echo "podman image mount : rc $r"
  if [ $r = 0 ]; then liste "$m" boot-image "rockylinux:9.7 brut" && i=1; podman image umount @BOOT@ >/dev/null 2>&1
  else tail -n 3 /w/mount-brut.err; fi
else tail -n 5 /w/pull-brut.log; fi
if [ $a = 1 ] && [ $i = 1 ]; then
  comm -13 /w/boot-image.txt /w/boot-mock.txt | sed "s/^/seulement dans le bootstrap de mock : /"
  comm -23 /w/boot-image.txt /w/boot-mock.txt | sed "s/^/seulement dans rockylinux:9.7 brut : /"
  echo "lignes communes : $(comm -12 /w/boot-image.txt /w/boot-mock.txt | wc -l)"
else
  echo "comparaison non faite (bootstrap de mock lu : $a ; rockylinux:9.7 brut lu : $i)"
  [ $a = 0 ] || sed "s/^/bootstrap de mock, liste : /" /w/boot-mock.txt
  [ $i = 0 ] || sed "s/^/rockylinux:9.7 brut, liste : /" /w/boot-image.txt
fi
df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
true'

etape_verrou_brut() {
  local d img n=s1-05-verrou-brut f
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  img=$REG/$DEPOT_ESSAI@$d
  echo "image : $img ; isolation : $ISOLATION ; configuration : $CFG (bootstrap_image_ready=False)"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$n" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$n" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  sed -e "s|@CFG_PRET@|$CFG|g" -e "s|@ISO@|$ISOLATION|g" -e "s|(image prête)|(image brute)|" \
    -e "s|--resultdir=/w/res-verrou --calculate-build-dependencies |--resultdir=/w/res-verrou --calculate-build-dependencies --no-cleanup-after |" \
    <<<"$SONDE_VERROU" | dans "$n" verrou-brut
  sed -e "s|@CFG@|$CFG|g" -e "s|@BOOT@|$BOOT|g" <<<"$SONDE_BOOT" | dans "$n" verrou-brut-boot
  kubectl exec -n builds "$n" -- sh -c 'for f in /w/res-verrou/root.log /w/res-verrou/build.log; do [ -e "$f" ] && { echo "### $f"; tail -n 400 "$f"; }; done
    [ -e /w/verrou-calc.log ] && { echo "### /w/verrou-calc.log"; tail -n 60 /w/verrou-calc.log; }; true' \
    </dev/null 2>&1 | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-verrou_brut-mock.log" || true
  echo "journaux de mock : $(wc -l < "$R/$PREFIXE-verrou_brut-mock.log") lignes, resultats/$PREFIXE-verrou_brut-mock.log"
  f=$(kubectl exec -n builds "$n" -- sh -c 'ls /w/res-verrou/*.json 2>/dev/null | head -1' </dev/null || true)
  if [ -n "$f" ]; then
    kubectl exec -n builds "$n" -- cat "$f" </dev/null | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-verrou_brut.json" \
      || echo "copie du verrou : code non nul"
    python3 -I - "$R/$PREFIXE-verrou_brut.json" <<'PY' || echo "résumé du verrou en échec : rc $?"
import json, sys
from urllib.parse import urlsplit
d = json.load(open(sys.argv[1], encoding='utf-8'))
c = d.get('config', {})
print('version du verrou :', d.get('version'))
print('options de configuration recopiées :', ', '.join(sorted(c)))
print('bootstrap_image enregistré :', c.get('bootstrap_image'))
print('bootstrap_image_ready enregistré :', c.get('bootstrap_image_ready'))
print('macros recopiées :', 'oui' if any('macro' in k for k in c) else 'non')
bs = d.get('bootstrap', {})
print('bootstrap, champs :', ', '.join(sorted(bs)) if bs else 'aucun (PodmanError attrapée, ou use_bootstrap_image faux)')
print('bootstrap, pull_digest (digest du manifeste tiré) :', bs.get('pull_digest'))
print('bootstrap, image_digest (sha256 de RootFS et Config, podman.py:21) :', bs.get('image_digest'))
print('bootstrap, architecture :', bs.get('architecture'))
b = d.get('buildroot', {}).get('rpms', [])
print('rpm du buildroot :', len(b), '; champs :', ', '.join(sorted(b[0])) if b else '-')
u = [r.get('url') for r in b]
print('rpm avec url :', sum(1 for x in u if x), 'sur', len(b))
print('préfixes des url :', ', '.join(sorted({urlsplit(x).netloc + urlsplit(x).path.rsplit('/', 1)[0] for x in u if x})) or '-')
g = sorted({str(r.get('signature')) for r in b})
print('valeurs distinctes de signature :', len(g), ';', ', '.join(g[:5]))
PY
  else echo "aucun verrou produit"; fi
  pod_retirer "$n"
}

# Image de bootstrap dérivée (décision du propriétaire « Dix lignes », 17/11/2026) : rockylinux:9.7 plus les six paquets que
# mock ajoute et les quatre montées de version de dnf qu'il fait (mesure de verrou_brut). Avec cette image marquée prête, mock
# n'installerait plus rien dans le bootstrap (buildroot.py:590, lecture). Trois étapes, trois accords : hote97 (hôte seul),
# boot_racine (pod, rien poussé), boot_image (écriture dans Zot).
# Non lus, à mesurer : qu'un dnf install d'un NEVRA exact fasse la montée de version d'un paquet présent ; qu'un dnf de 9.8 en
# --installroot donne le même état que le dnf du bootstrap dans le chroot ; si dnf importe la clé (gpg-pubkey) dans la racine.
# La racine n'est pas vide : ses .repo (mirrorlist) sont écartés par --setopt=reposdir=/w/aucun en ligne de commande, comme à
# racine. L'archive n'est pas reproductible au bit près (base rpm : INSTALLTIME ; journaux de dnf sous var/log).

etape_hote97() { # hôte seul, ni cluster ni Zot : primary de vault 9.7 (figé) vérifiés ; dépôt et sha256 des dix paquets
  local d=$T/hote fp n x
  [ -s "$d/RPM-GPG-KEY-Rocky-9" ] && [ -s "$d/cles.gpg" ] || { echo "KO   lancer d'abord l'étape hote" >&2; exit 1; }
  fp=$(gpg --batch --with-colons --show-keys "$d/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  attendu "empreinte de la clé de Rocky (relevée par hote)" "$fp" "$FP_ROCKY"
  echo "## dépôts de vault 9.7, vérifiés sur l'hôte"
  for n in "${DEPOTS97[@]}"; do
    x=${n,,}97
    depot_hote "$x" "$VAULT97/$n/x86_64/os" 1 "$FP_ROCKY"
    if [ -s "$d/v97-$n.repomd.xml" ]; then
      echo "$x : repomd.xml égal au relevé de hote : $(cmp -s "$d/v97-$n.repomd.xml" "$d/$x.repomd.xml" && echo oui || echo non)"
    else echo "$x : relevé de hote absent"; fi
  done
  echo "## les dix paquets de l'image dérivée"
  python3 -I - "$T" "${DERIVEE[@]}" <<'PY'
import os, sys, xml.etree.ElementTree as E
t = sys.argv[1]; ko = 0
C = '{http://linux.duke.edu/metadata/common}'; RP = '{http://linux.duke.edu/metadata/rpm}'
voulu = {}
for e in sys.argv[2:]:
    nom, evr, arch = e.split(); ep, vr = evr.split(':', 1); v, r = vr.rsplit('-', 1)
    voulu[(nom, ep, v, r, arch)] = []
req = []
for depot in ('baseos97', 'appstream97', 'crb97', 'extras97'):   # lecture en flux : le primary d'AppStream est gros
    for _, p in E.iterparse(f'{t}/{depot}.primary.xml'):
        if p.tag != C + 'package': continue
        x = p.find(C + 'version')
        k = (p.find(C + 'name').text, x.get('epoch'), x.get('ver'), x.get('rel'), p.find(C + 'arch').text)
        if k in voulu:
            voulu[k].append((depot, p.find(C + 'checksum').text, p.find(C + 'location').get('href')))
            if k[0] == 'python3-dnf-plugins-core':
                f = p.find(C + 'format'); q = f.find(RP + 'requires') if f is not None else None
                for y in (q if q is not None else []):
                    w = (y.get('epoch') + ':' if y.get('epoch') else '') + (y.get('ver') or '') + ('-' + y.get('rel') if y.get('rel') else '')
                    req.append(f"{depot} : {y.get('name')} {y.get('flags') or ''} {w}".rstrip())
        p.clear()
lignes = []
for k, c in voulu.items():
    nevra = f'{k[0]}-{k[1]}:{k[2]}-{k[3]}.{k[4]}'
    s = {h for _, h, _ in c}
    if c and len(s) == 1:
        print(f'OK   {nevra} dans {", ".join(d for d, _, _ in c)} : sha256 {c[0][1]} ({c[0][2]})')
        lignes.append(f'{c[0][2].rsplit("/", 1)[1]} {c[0][1]} {c[0][0]}')
    else:
        ko = 1; print(f'KO   {nevra} : {len(c)} candidat(s), {len(s)} empreinte(s) distincte(s)')
print(f'requires de python3-dnf-plugins-core : {len(req)} entrée(s)')
for y in req: print('requires de python3-dnf-plugins-core, ' + y)
if os.path.exists(f'{t}/derivee.sha256'): os.remove(f'{t}/derivee.sha256')
if ko == 0: open(f'{t}/derivee.sha256', 'w', encoding='utf-8').write('\n'.join(lignes) + '\n')
sys.exit(ko)
PY
}

dnf97_conf() { # configuration de dnf de boot_racine : options du modèle rocky-9 (best, weak deps), vault 9.7 en baseurl fixes
  local n
  cat <<EOF
[main]
gpgcheck=1
install_weak_deps=0
best=1
keepcache=1
cachedir=/w/cache97
reposdir=/w/aucun
EOF
  for n in "${DEPOTS97[@]}"; do
    printf '[%s97]\nname=Rocky 9.7 %s (vault)\nbaseurl=%s/%s/x86_64/os/\nrepo_gpgcheck=1\ngpgkey=file:///w/cles/RPM-GPG-KEY-Rocky-9\n' \
      "${n,,}" "$n" "$VAULT97" "$n"
  done
}

# Script de boot_racine (root, image d'essai). L'image d'essai porte /usr/bin/dnf-3 (python3-dnf 4.14.0-34.el9_8) mais pas
# /usr/bin/dnf (paquet dnf absent de racine.tar) : dnf-3 est appelé, comme le fait mock. dnf ne lit que /w/dnf97.conf ; la clé
# vient de l'hôte. Rien n'est écrit dans le
# montage de podman image mount : la racine est copiée sous /w. Sorties brutes ; l'hôte décide (repomd, rpm, rpm -K, archive).
SONDE_DERIVEE='set -u
export LC_ALL=C
Q="%{NAME}.%{ARCH} %{EPOCHNUM}:%{VERSION}-%{RELEASE} sigpgp=%{SIGPGP:pgpsig} rsaheader=%{RSAHEADER:pgpsig}\n"
R=/w/boot-racine
C="/w/cache97 $R/w/cache97"   # dnf peut placer cachedir dans la racine (--installroot) : les deux sont lus
DNF="dnf-3 -y -c /w/dnf97.conf --setopt=reposdir=/w/aucun --installroot=$R --releasever=9"
echo "dnf-3 : $(dnf-3 --version 2>/dev/null | head -1) ; rpm : $(rpm --version)"
mkdir -p /w/aucun /w/cache97
t=$(date +%s); podman pull @BOOT@ > /w/pull.log 2>&1; r=$?
echo "podman pull de rockylinux:9.7 : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || { tail -n 5 /w/pull.log; exit 0; }
m=$(podman image mount @BOOT@ 2>/w/mount.err); r=$?; echo "podman image mount : rc $r"
[ $r = 0 ] || { tail -n 3 /w/mount.err; exit 0; }
rm -rf "$R"; mkdir -p "$R"; cp -a "$m/." "$R/" 2>/w/cp.err; r=$?
podman image umount @BOOT@ >/dev/null 2>&1
echo "copie de la racine de rockylinux:9.7 : rc $r, $(du -sk "$R" | cut -f1) kB"
[ $r = 0 ] || { tail -n 3 /w/cp.err; exit 0; }
echo "dépôts de la racine, écartés (reposdir=/w/aucun) : $(ls "$R/etc/yum.repos.d" 2>/dev/null | tr "\n" " ")"
rpm --root "$R" -qa --qf "$Q" 2>/w/avant.err | sort > /w/avant.txt
echo "racine avant : rpm -qa $(wc -l < /w/avant.txt) ligne(s), stderr $(wc -l < /w/avant.err) ligne(s)"
echo "gpg-pubkey avant : $(rpm --root "$R" -qa "gpg-pubkey*" 2>/dev/null | tr "\n" " ")"
t=$(date +%s); $DNF makecache > /w/makecache.log 2>&1; r=$?
echo "makecache : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || { tail -n 15 /w/makecache.log; exit 0; }
echo "caches : $(for c in $C; do [ -d $c ] && printf "%s " $c; done)"
for d in baseos97 appstream97 crb97 extras97; do f=$(find $C -path "*/$d-*/repodata/repomd.xml" 2>/dev/null | head -1)
  echo "repomd $d : sha256 $([ -n "$f" ] && sha256sum < "$f" | cut -c1-64)"; done
t=$(date +%s); $DNF install @PAQUETS@ > /w/install.log 2>&1; r=$?
echo "installation : rc $r en $(($(date +%s) - t)) s"
sed -n "/^Transaction Summary/q; /^=\{10,\}/,\$p" /w/install.log | grep -v -e "^=" -e "^\$" | sed "s/^/transaction : /"
grep -E "^(Install|Upgrade|Remove|Downgrade|Reinstall|Skip) +[0-9]+ Package" /w/install.log | sed "s/^/résumé de la transaction : /"
[ $r = 0 ] || { tail -n 25 /w/install.log; exit 0; }
for f in $(find $C -name "*.rpm" 2>/dev/null | sort); do echo "rpm ${f##*/} $(sha256sum < $f | cut -c1-64)"; done
rpm --root "$R" -K $(find $C -name "*.rpm" 2>/dev/null) > /w/k.log 2>&1
echo "rpm -K : $(grep -c -E "digests signatures OK$" /w/k.log) OK sur $(find $C -name "*.rpm" 2>/dev/null | wc -l)"
grep -v -E "digests signatures OK$" /w/k.log | head -n 5
echo "gpg-pubkey après : $(rpm --root "$R" -qa "gpg-pubkey*" 2>/dev/null | tr "\n" " ")"
rpm --root "$R" -qa --qf "$Q" 2>/w/apres.err | sort > /w/apres.txt
echo "racine dérivée : rpm -qa $(wc -l < /w/apres.txt) ligne(s), stderr $(wc -l < /w/apres.err) ligne(s)"
comm -13 /w/avant.txt /w/apres.txt | sed "s/^/seulement dans la racine dérivée : /"
comm -23 /w/avant.txt /w/apres.txt | sed "s/^/seulement dans rockylinux:9.7 brut : /"
echo "lignes communes : $(comm -12 /w/avant.txt /w/apres.txt | wc -l)"
sed "s/^/racine dérivée, liste : /" /w/apres.txt
rpm --root "$R" -q --requires python3-dnf-plugins-core 2>&1 | sed "s/^/requires du greffon installé : /"
rm -rf "$R/w"   # seul dossier ajouté par la sonde ; var/cache/dnf de la base est gardé (base plus dix paquets)
echo "restes de /w dans la racine : $(ls -d "$R/w" 2>/dev/null | wc -l)"
echo "var/cache/dnf de la racine : $(find "$R/var/cache/dnf" -mindepth 1 2>/dev/null | wc -l) entrée(s), gardées"
tar --sort=name --format=posix --xattrs --xattrs-include="*" --numeric-owner -C "$R" -cf /w/boot-racine.tar .; r=$?
echo "archive racine dérivée : rc $r, $(stat -c %s /w/boot-racine.tar) octets, sha256 $(sha256sum < /w/boot-racine.tar | cut -c1-64)"
df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
true'

controle_derivee() { # journal : rpm téléchargés comparés aux dix fichiers et sha256 de hote97, ni plus ni moins
  python3 -I - "$T/derivee.sha256" "$1" <<'PY'
import sys
att = {}
for l in open(sys.argv[1], encoding='utf-8'):
    x = l.split()
    if len(x) == 3: att[x[0]] = x[1]
vu = {}
for l in open(sys.argv[2], encoding='utf-8'):
    x = l.split()
    if len(x) == 3 and x[0] == 'rpm' and x[1].endswith('.rpm'): vu[x[1]] = x[2]
ko = [f'non épinglé : {f}' for f in sorted(set(vu) - set(att))] + [f'absent : {f}' for f in sorted(set(att) - set(vu))] \
    + [f'sha256 différent : {f}' for f in sorted(set(vu) & set(att)) if vu[f] != att[f]]
bons = sum(1 for f in set(vu) & set(att) if vu[f] == att[f])
print(('OK   ' if not ko and len(att) == 10 else 'KO   ') + f'rpm téléchargés conformes aux dix de hote97 : {bons} sur {len(att)}, {len(vu)} téléchargé(s)')
for k in ko: print('     écart : ' + k)
sys.exit(1 if ko or len(att) != 10 else 0)
PY
}

etape_boot_racine() {
  local d img n=s1-05-boot-racine p="" r s x
  rm -f "$T/boot-racine.tar" "$T/boot-racine.sha256"   # aucune archive d'un passage précédent ne survit à un échec
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  [ -s "$T/derivee.sha256" ] && [ -s "$T/hote/RPM-GPG-KEY-Rocky-9" ] || { echo "KO   lancer d'abord l'étape hote97" >&2; exit 1; }
  for r in baseos97 appstream97 crb97 extras97; do [ -s "$T/$r.repomd.sha256" ] || { echo "KO   lancer d'abord l'étape hote97" >&2; exit 1; }; done
  for x in "${DERIVEE[@]}"; do set -- $x; p="$p $1-${2#0:}.$3"; done
  img=$REG/$DEPOT_ESSAI@$d
  echo "image du pod : $img ; base : $BOOT"
  echo "paquets demandés :$p"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/cles/RPM-GPG-KEY-Rocky-9 "$T/hote/RPM-GPG-KEY-Rocky-9"
  dnf97_conf > "$T/dnf97.conf" && livrer "$n" /w/dnf97.conf "$T/dnf97.conf"
  sed -e "s|@BOOT@|$BOOT|g" -e "s|@PAQUETS@|${p# }|g" <<<"$SONDE_DERIVEE" | dans "$n" boot-racine
  for r in baseos97 appstream97 crb97 extras97; do
    ( attendu "repomd $r lu par dnf dans le pod = repomd vérifié sur l'hôte" "$(champ boot-racine "repomd $r" | sed 's/^sha256 //')" \
      "$(cat "$T/$r.repomd.sha256")" ) || { pod_retirer "$n"; exit 1; }
  done
  ( attendu "rpm -K" "$(champ boot-racine 'rpm -K')" "10 OK sur 10" ) || { pod_retirer "$n"; exit 1; }
  controle_derivee "$T/boot-racine.log" || { pod_retirer "$n"; echo "KO   rpm téléchargés différents des dix épinglés : archive non rapatriée" >&2; exit 1; }
  s=$(sed -n 's/^archive racine dérivée : rc 0, .*sha256 \([0-9a-f]\{64\}\)$/\1/p' "$T/boot-racine.log")
  [ -n "$s" ] || { pod_retirer "$n"; echo "KO   archive racine dérivée absente" >&2; exit 1; }
  kubectl exec -n builds "$n" -- cat /w/boot-racine.tar </dev/null > "$T/boot-racine.tar" \
    || { rm -f "$T/boot-racine.tar"; pod_retirer "$n"; echo "KO   rapatriement" >&2; exit 1; }
  ( attendu "archive racine dérivée rapatriée" "$(sha256sum < "$T/boot-racine.tar" | cut -c1-64)" "$s" ) \
    || { rm -f "$T/boot-racine.tar"; pod_retirer "$n"; exit 1; }
  echo "$s" > "$T/boot-racine.sha256"
  pod_retirer "$n"
}

etape_boot_image() {
  local d
  [ -s "$T/boot-racine.tar" ] && [ -s "$T/boot-racine.sha256" ] || { echo "KO   lancer d'abord l'étape boot_racine" >&2; exit 1; }
  attendu "archive racine dérivée, sha256 égal à celui de boot_racine" "$(sha256sum < "$T/boot-racine.tar" | cut -c1-64)" "$(cat "$T/boot-racine.sha256")"
  echo "archive racine dérivée : $(stat -c %s "$T/boot-racine.tar") octets"
  [ -s "$T/docker/config.json" ] || { auth_zot "$T/zot.json"; mkdir -p "$T/docker" && cp "$T/zot.json" "$T/docker/config.json"; }
  zot crane append --oci-empty-base -f "$T/boot-racine.tar" -t "$REG_HOTE/$DEPOT_DERIVE:$PREFIXE" >/dev/null 2>"$T/crane.err" \
    || { cat "$T/crane.err" >&2; exit 1; }
  zot crane mutate "$REG_HOTE/$DEPOT_DERIVE:$PREFIXE" --set-platform linux/amd64 -t "$REG_HOTE/$DEPOT_DERIVE:$PREFIXE" \
    -a "org.opencontainers.image.base.name=$REG/$DEPOT_AMONT" -a "org.opencontainers.image.base.digest=$BOOT_DIGEST" \
    >/dev/null 2>"$T/crane.err" || { cat "$T/crane.err" >&2; exit 1; }
  d=$(zot crane digest "$REG_HOTE/$DEPOT_DERIVE:$PREFIXE")
  echo "$d" > "$T/boot-image.digest"
  zot crane manifest "$REG_HOTE/$DEPOT_DERIVE@$d" | jq -r '.layers[] | "couche \(.digest) \(.size) octets"'
  zot crane manifest "$REG_HOTE/$DEPOT_DERIVE@$d" | jq -r '(.annotations // {}) | to_entries[] | "annotation \(.key) = \(.value)"'
  zot crane config "$REG_HOTE/$DEPOT_DERIVE@$d" | jq -r '"config : os \(.os) ; architecture \(.architecture)"'
  echo "image de bootstrap dérivée : $REG/$DEPOT_DERIVE@$d"
}

# Étape verrou_derivee (ajoutée à sec le 17/11/2026 à partir de 15:03:48 UTC, NON LANCÉE) : la sonde de verrou avec l'image de
# bootstrap dérivée (décision « Dix lignes », poussée par boot_image) marquée prête. L'image d'essai ne porte que $CFG et $CFG_PRET,
# tous deux sur rockylinux:9.7 brut : une troisième configuration, $CFG_DERIVE, est générée sur l'hôte à partir de MOCK_CFG
# (racine, bootstrap_image et bootstrap_image_ready changés, rien d'autre : six lignes de diff) et livrée sous /etc/mock ; le pod
# vérifie que sa configuration de base est bien MOCK_CFG, par sha256 (diff n'est pas dans l'image d'essai : tar -tf de racine.tar).
# Avec une image prête, mock ne doit rien installer dans le bootstrap (buildroot.py:590, lecture) : mesuré par SONDE_BOOT,
# bootstrap de mock (--no-cleanup-after) contre image dérivée montée. Avant mock, le pod tire lui-même l'image dérivée (lecture
# anonyme de essais-05/ jamais mesurée) : un échec arrête l'étape, car mock, bootstrap_image_fallback à True par défaut
# (config.py:110), installerait sinon le bootstrap sans image, et le calcul ne mesurerait plus l'image dérivée. Le repli est
# signalé par un avertissement (buildroot.py:307) du logger mockbuild.buildroot, enfant de mockbuild qui porte root.log
# (trace_decorator.py:18 à :29, buildroot.py:125 et :692, lecture) : SONDE_REPLI le cherche dans root.log et dans les deux
# sorties de mock. Le verrou est comparé à celui de verrou_brut (rpm du buildroot).
# Non mesuré ici : --hermetic-build (M2) ; config.py:844 coupe bootstrap_image au premier « : », à lire avant M2.
# SONDE_VERROU, SONDE_BOOT et les étapes existantes ne changent pas ; journaux distincts : s1-verrou_derivee*.
CFG_DERIVE=poc-rocky-9.7-derivee-x86_64   # étape verrou_derivee : livrée dans le pod, bootstrap = image dérivée, prête
SONDE_CFG_DERIVEE='set -u
echo "configuration de base, image du pod : sha256 $(sha256sum < /etc/mock/@CFG@.cfg | cut -c1-64)"
echo "configuration dérivée livrée : sha256 $(sha256sum < /etc/mock/@CFG_DERIVE@.cfg | cut -c1-64)"
mock -r @CFG_DERIVE@ --debug-config > /w/derivee-debug-config.log 2>&1; echo "mock --debug-config : rc $?"
grep -E "^config_opts\[.(root|bootstrap_image|bootstrap_image_ready|bootstrap_image_fallback|bootstrap_image_assert_digest).\]" \
  /w/derivee-debug-config.log | sed "s/^/configuration lue par mock : /"
t=$(date +%s); podman pull @DERIVEE@ > /w/pull-derivee.log 2>&1; r=$?
echo "podman pull, image dérivée : rc $r en $(($(date +%s) - t)) s"
[ $r = 0 ] || tail -n 5 /w/pull-derivee.log
podman image inspect --format "image dérivée, inspect : {{.Digest}} {{.Os}}/{{.Architecture}}" @DERIVEE@ 2>&1 | tail -n 1
true'
SONDE_REPLI='for f in /w/res-verrou/root.log /w/verrou-srpm.log /w/verrou-calc.log; do
  c=$(grep -c "falling back to chroot installation" "$f" 2>/dev/null); echo "${f#/w/} : ${c:-fichier absent} ligne(s) de repli sans image"
done
true'

etape_verrou_derivee() {
  local d bd img n=s1-05-verrou-derivee f c=$T/$CFG_DERIVE.cfg
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  bd=$(cat "$T/boot-image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape boot_image" >&2; exit 1; }
  [[ $bd =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "KO   digest de boot_image illisible : $bd" >&2; exit 1; }
  [ -s "$R/s1-verrou_brut.json" ] || { echo "KO   verrou de référence absent : resultats/s1-verrou_brut.json" >&2; exit 1; }
  img=$REG/$DEPOT_ESSAI@$d
  printf '%s' "$MOCK_CFG" > "$T/$CFG.cfg"
  printf '%s' "$MOCK_CFG" | sed -e "s|'root'\] = '$CFG'|'root'] = '$CFG_DERIVE'|" \
    -e "s|'bootstrap_image'\] = '$BOOT'|'bootstrap_image'] = '$REG/$DEPOT_DERIVE@$bd'|" \
    -e "s|'bootstrap_image_ready'\] = False|'bootstrap_image_ready'] = True|" > "$c"
  attendu "configuration dérivée : racine, bootstrap_image et bootstrap_image_ready changés, rien d'autre" \
    "$(diff "$T/$CFG.cfg" "$c" | grep -c '^[<>]')" 6
  { diff "$T/$CFG.cfg" "$c" || true; } | grep '^[<>]' | sed 's/^/écart prévu : /'
  echo "configuration dérivée : sha256 $(sha256sum < "$c" | cut -c1-64)"
  echo "image : $img ; isolation : $ISOLATION ; configuration : $CFG_DERIVE (bootstrap_image_ready=True)"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$n" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$n" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  livrer "$n" "/etc/mock/$CFG_DERIVE.cfg" "$c"
  sed -e "s|@CFG@|$CFG|g" -e "s|@CFG_DERIVE@|$CFG_DERIVE|g" -e "s|@DERIVEE@|$REG/$DEPOT_DERIVE@$bd|g" <<<"$SONDE_CFG_DERIVEE" \
    | dans "$n" verrou-derivee-cfg
  ( attendu "configuration de base du pod égale à MOCK_CFG de s1.sh" "$(champ verrou-derivee-cfg 'configuration de base, image du pod')" \
      "sha256 $(sha256sum < "$T/$CFG.cfg" | cut -c1-64)"
    attendu "configuration dérivée livrée dans le pod" "$(champ verrou-derivee-cfg 'configuration dérivée livrée')" \
      "sha256 $(sha256sum < "$c" | cut -c1-64)"
    attendu "podman pull de l'image dérivée par le pod" "$(champ verrou-derivee-cfg 'podman pull, image dérivée' | cut -d' ' -f1-2)" "rc 0" ) \
    || { pod_retirer "$n"; exit 1; }
  sed -e "s|@CFG_PRET@|$CFG_DERIVE|g" -e "s|@ISO@|$ISOLATION|g" -e "s|(image prête)|(image dérivée)|" \
    -e "s|--resultdir=/w/res-verrou --calculate-build-dependencies |--resultdir=/w/res-verrou --calculate-build-dependencies --no-cleanup-after |" \
    <<<"$SONDE_VERROU" | dans "$n" verrou-derivee
  dans "$n" verrou-derivee-repli <<<"$SONDE_REPLI"
  sed -e "s|@CFG@|$CFG_DERIVE|g" -e "s|@BOOT@|$REG/$DEPOT_DERIVE@$bd|g" -e "s|de rockylinux:9\.7 brut|de l'image dérivée|g" \
    -e "s|dans rockylinux:9\.7 brut|dans l'image dérivée|g" -e "s|rockylinux:9\.7 brut lu|image dérivée lue|g" \
    -e "s|rockylinux:9\.7 brut|image dérivée|g" -e "s|-brut\.|-derivee.|g" <<<"$SONDE_BOOT" | dans "$n" verrou-derivee-boot
  kubectl exec -n builds "$n" -- sh -c 'for f in /w/res-verrou/root.log /w/res-verrou/build.log; do [ -e "$f" ] && { echo "### $f"; tail -n 400 "$f"; }; done
    for f in /w/verrou-srpm.log /w/verrou-calc.log; do [ -e "$f" ] && { echo "### $f"; tail -n 60 "$f"; }; done; true' \
    </dev/null 2>&1 | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-verrou_derivee-mock.log" || true
  echo "journaux de mock : $(wc -l < "$R/$PREFIXE-verrou_derivee-mock.log") lignes, resultats/$PREFIXE-verrou_derivee-mock.log"
  f=$(kubectl exec -n builds "$n" -- sh -c 'ls /w/res-verrou/*.json 2>/dev/null | head -1' </dev/null || true)
  if [ -n "$f" ]; then
    kubectl exec -n builds "$n" -- cat "$f" </dev/null | grep -i -v -E 'jeton|token' > "$R/$PREFIXE-verrou_derivee.json" \
      || echo "copie du verrou : code non nul"
    python3 -I - "$R/$PREFIXE-verrou_derivee.json" <<'PY' || echo "résumé du verrou en échec : rc $?"
import json, sys
from urllib.parse import urlsplit
d = json.load(open(sys.argv[1], encoding='utf-8'))
c = d.get('config', {})
print('version du verrou :', d.get('version'))
print('options de configuration recopiées :', ', '.join(sorted(c)))
print('bootstrap_image enregistré :', c.get('bootstrap_image'))
print('bootstrap_image_ready enregistré :', c.get('bootstrap_image_ready'))
print('macros recopiées :', 'oui' if any('macro' in k for k in c) else 'non')
bs = d.get('bootstrap', {})
print('bootstrap, champs :', ', '.join(sorted(bs)) if bs else 'aucun (PodmanError attrapée, ou use_bootstrap_image faux)')
print('bootstrap, pull_digest (digest du manifeste tiré) :', bs.get('pull_digest'))
print('bootstrap, image_digest (sha256 de RootFS et Config, podman.py:21) :', bs.get('image_digest'))
print('bootstrap, architecture :', bs.get('architecture'))
b = d.get('buildroot', {}).get('rpms', [])
print('rpm du buildroot :', len(b), '; champs :', ', '.join(sorted(b[0])) if b else '-')
u = [r.get('url') for r in b]
print('rpm avec url :', sum(1 for x in u if x), 'sur', len(b))
print('préfixes des url :', ', '.join(sorted({urlsplit(x).netloc + urlsplit(x).path.rsplit('/', 1)[0] for x in u if x})) or '-')
g = sorted({str(r.get('signature')) for r in b})
print('valeurs distinctes de signature :', len(g), ';', ', '.join(g[:5]))
PY
    python3 -I - "$R/$PREFIXE-verrou_derivee.json" "$R/s1-verrou_brut.json" "$bd" <<'PY' || echo "comparaison avec verrou_brut en échec : rc $?"
import json, sys
a, b = (json.load(open(f, encoding='utf-8')) for f in sys.argv[1:3])
p = a.get('bootstrap', {}).get('pull_digest')
print('bootstrap, pull_digest égal au digest de boot_image :', 'oui' if p == sys.argv[3] else 'non (%s)' % p)
ca, cb = a.get('config', {}), b.get('config', {})
print('options de configuration différentes de verrou_brut :', ', '.join(sorted(k for k in set(ca) | set(cb) if ca.get(k) != cb.get(k))) or 'aucune')
k = lambda r: (r.get('name'), r.get('epoch'), r.get('version'), r.get('release'), r.get('arch'), r.get('sigmd5'), r.get('url'))
la, lb = a.get('buildroot', {}).get('rpms', []), b.get('buildroot', {}).get('rpms', [])
ra, rb = {k(r) for r in la}, {k(r) for r in lb}
print(f'rpm du buildroot (nom, epoch, version, release, arch, sigmd5, url) : ici {len(la)}, verrou_brut {len(lb)} ; communs {len(ra & rb)} ;'
      f' seulement ici {len(ra - rb)} ; seulement dans verrou_brut {len(rb - ra)}')
for x in sorted(ra - rb, key=str)[:10]: print('seulement ici :', x)
for x in sorted(rb - ra, key=str)[:10]: print('seulement dans verrou_brut :', x)
PY
  else echo "aucun verrou produit"; fi
  pod_retirer "$n"
}

# Étapes voie2 et hermetique (s1-m2.patch, préparées à sec le 17/11/2026 à partir de 15:40:59 UTC, NON APPLIQUÉES) : voir
# l'en-tête. m2_preparer et VOIE2_M2 recopient voie2_preparer et VOIE2 de m2.sh ; écarts déclarés : attendus tirés de
# boot-image.digest et de DEPOT_DERIVE (au lieu de BOOT_DIGEST et DEPOT_AMONT), bootstrap_image_ready et image_digest exigés,
# baseurl de vault 9.7 prises dans VAULT97 de ce fichier, verrou relu dans le pod, df de /w en fin de script.
VERROU_DERIVEE_SHA=b6d0f8f15c33c8de68d034dae0525febaefd60143f1d8bc436e5a469f9e8af6f   # resultats/s1-verrou_derivee.json (303b428)
POD_M2=s1-05-m2
m2_preparer() { # verrou dossier digest-de-boot_image : liste.tsv et voie2.sh écrits dans dossier ; KO sur tout écart du verrou
  local v=$1 o=$2 b=$3 p=$VAULT97 src dos x
  mkdir -p "$o"
  attendu "version du verrou" "$(jq -r '.version' "$v")" 1.1.0
  attendu "bootstrap_image_ready du verrou" "$(jq -r '.config.bootstrap_image_ready' "$v")" true
  attendu "pull_digest du verrou (digest de boot_image)" "$(jq -r '.bootstrap.pull_digest // "absent"' "$v")" "$b"
  src=$(jq -r '.config.bootstrap_image // "absent"' "$v")
  attendu "bootstrap_image du verrou" "$src" "$REG/$DEPOT_DERIVE@$b"
  attendu "image_digest du verrou, 64 hexadécimaux" "$(jq -r '.bootstrap.image_digest // "" | test("^[0-9a-f]{64}$")' "$v")" true
  dos=${src%%:*}@$b   # split(':')[0] de mock, puis @pull_digest (config.py:844-846)
  jq -r '.buildroot.rpms[] | [.name, .version, .release, .arch, .sigmd5, .url] | map(if type == "string" then . else "" end) | @tsv' \
    "$v" > "$o/liste.tsv"
  awk -F '\t' -v p="$p" '
    function ko(m) { print "KO   ligne " NR " du verrou : " m > "/dev/stderr"; e = 1 }
    { n++; f = $6; sub(/.*\//, "", f) }
    NF != 6 || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" { ko("champ manquant"); next }
    length($5) != 32 || $5 ~ /[^0-9a-f]/ { ko("sigmd5 inattendu : " $5) }
    index($6, p "/BaseOS/x86_64/os/") != 1 && index($6, p "/AppStream/x86_64/os/") != 1 && index($6, p "/CRB/x86_64/os/") != 1 {
      ko("URL hors des dépôts épinglés : " $6) }
    $6 ~ /[^A-Za-z0-9:\/._+-]/ || index($6, "/../") || index($6, "/./") { ko("URL refusée (caractère ou segment . ou ..) : " $6) }
    f !~ /^[A-Za-z0-9._+-]+\.rpm$/ { ko("nom de fichier refusé : " f) }
    vu[f]++ { ko("nom de fichier en double : " f) }
    END { if (!n) { print "KO   aucun paquet dans le verrou" > "/dev/stderr"; e = 1 }; exit e }' "$o/liste.tsv" \
    || { echo "KO   verrou refusé (motifs ci-dessus)" >&2; exit 1; }
  echo "OK   verrou : $(wc -l < "$o/liste.tsv") paquets, tous sous $p (BaseOS, AppStream, CRB)"
  x=${VOIE2_M2//@SOURCE@/$src}; x=${x//@DOSSIER@/$dos}; printf '%s\n' "${x//@DIGEST@/$b}" > "$o/voie2.sh"
  echo "bootstrap : docker://$src vers dir:<dépôt>/$dos"
}

VOIE2_M2='set -u
export LC_ALL=C
R=${VOIE2_RACINE:-/w}; D=$R/voie2/depot; B=$R/voie2/rpmdb; L=$R/voie2/liste.tsv; T=$(printf "\t")
ko() { echo "KO   $*"; exit 1; }
echo "verrou livré : sha256 $(sha256sum < "$R/verrou.json" | cut -c1-64)"
for o in curl rpm createrepo_c skopeo sha256sum; do command -v $o >/dev/null 2>&1 || ko "$o absent de l image"; done
rm -rf "${D:?}" "${B:?}"; mkdir -p "$D" "$B"
n=$(wc -l < "$L"); echo "paquets du verrou : $n"
t=$(date +%s)
while IFS="$T" read -r nom ver rel arch md5 url; do
  h=$(curl -sS --proto =https --max-time 120 -o "$D/${url##*/}" -w "%{http_code}" "$(printf %s "$url" | sed "s/+/%2B/g")") || ko "curl en échec : $url"
  [ "$h" = 200 ] || ko "HTTP $h : $url"
done < "$L"
c=$(find "$D" -maxdepth 1 -type f -name "*.rpm" | wc -l)
[ "$c" = "$n" ] || ko "$c fichiers téléchargés pour $n paquets"
echo "téléchargement : $c fichiers en $(($(date +%s) - t)) s"
rpm --dbpath "$B" --initdb </dev/null || ko "rpmdb vide non créée"
rpm --dbpath "$B" --import "$R/cles/RPM-GPG-KEY-Rocky-9" </dev/null || ko "clé de Rocky non importée"
rpm --dbpath "$B" -K "$D"/*.rpm > "$R/voie2/k.log" 2>&1 </dev/null; r=$?
k=$(grep -c -E "digests signatures OK$" "$R/voie2/k.log")
echo "rpm -K : rc $r, $k OK sur $n"
grep -v -E "digests signatures OK$" "$R/voie2/k.log" | head -n 5
[ "$r" = 0 ] && [ "$k" = "$n" ] || ko "signatures des rpm"
while IFS="$T" read -r nom ver rel arch md5 url; do
  q=$(rpm --dbpath "$B" -qp --qf "%{NAME}$T%{VERSION}$T%{RELEASE}$T%{ARCH}$T%{SIGMD5}" "$D/${url##*/}" 2>/dev/null </dev/null)
  [ "$q" = "$nom$T$ver$T$rel$T$arch$T$md5" ] || ko "en-tête de ${url##*/} différent du verrou"
done < "$L"
echo "OK   nom, version, release, arch et sigmd5 des $n rpm égaux au verrou"
t=$(date +%s); createrepo_c --compatibility "$D" > "$R/voie2/createrepo.log" 2>&1 </dev/null; r=$?
echo "createrepo_c --compatibility : rc $r en $(($(date +%s) - t)) s"
[ "$r" = 0 ] || { tail -n 5 "$R/voie2/createrepo.log"; ko "createrepo_c"; }
[ -s "$D/repodata/repomd.xml" ] || ko "repodata/repomd.xml absent"
echo "repomd.xml : sha256 $(sha256sum < "$D/repodata/repomd.xml" | cut -c1-64)"
t=$(date +%s); skopeo copy --preserve-digests "docker://@SOURCE@" "dir:$D/@DOSSIER@" > "$R/voie2/skopeo.log" 2>&1 </dev/null; r=$?
echo "skopeo copy --preserve-digests : rc $r en $(($(date +%s) - t)) s"
[ "$r" = 0 ] || { tail -n 5 "$R/voie2/skopeo.log"; ko "skopeo copy"; }
m=sha256:$(sha256sum < "$D/@DOSSIER@/manifest.json" | cut -c1-64)
[ "$m" = "@DIGEST@" ] || ko "manifeste copié $m, attendu @DIGEST@"
echo "OK   manifeste copié : $m"
df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
'

etape_voie2() {
  local d bd img n=$POD_M2 o=$T/m2 fp
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  bd=$(cat "$T/boot-image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape boot_image" >&2; exit 1; }
  [[ $bd =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "KO   digest de boot_image illisible : $bd" >&2; exit 1; }
  attendu "verrou d'entrée resultats/s1-verrou_derivee.json, sha256" "$(sha256sum < "$R/s1-verrou_derivee.json" | cut -c1-64)" \
    "$VERROU_DERIVEE_SHA"
  [ -s "$T/hote/RPM-GPG-KEY-Rocky-9" ] || { echo "KO   clé de Rocky absente : lancer d'abord l'étape hote" >&2; exit 1; }
  fp=$(gpg --batch --with-colons --show-keys "$T/hote/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  attendu "empreinte de la clé de Rocky livrée" "$fp" "$FP_ROCKY"
  rm -rf -- "${o:?}"
  m2_preparer "$R/s1-verrou_derivee.json" "$o" "$bd"
  img=$REG/$DEPOT_ESSAI@$d
  echo "image : $img ; pod : $n"
  pod_spec "$n" "$img"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/cles/RPM-GPG-KEY-Rocky-9 "$T/hote/RPM-GPG-KEY-Rocky-9"
  livrer "$n" /w/voie2/liste.tsv "$o/liste.tsv"
  livrer "$n" /w/verrou.json "$R/s1-verrou_derivee.json"
  livrer "$n" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$n" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$n" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  dans "$n" m2-voie2 < "$o/voie2.sh"
  ( attendu "verrou relu dans le pod" "$(champ m2-voie2 'verrou livré')" "sha256 $VERROU_DERIVEE_SHA"
    attendu "manifeste copié (dernière porte de voie2)" "$(champ m2-voie2 'OK   manifeste copié')" "$bd" ) \
    || { pod_retirer "$n"; exit 1; }
  echo "pod $n laissé pour l'étape hermetique (sleep 43200) ; à retirer à la main si hermetique n'est pas lancée"
}

SONDE_HERMETIQUE_PRE='set -u
D=/w/voie2/depot
echo "verrou : sha256 $(sha256sum < /w/verrou.json | cut -c1-64)"
echo "repomd.xml : sha256 $(sha256sum < $D/repodata/repomd.xml | cut -c1-64)"
echo "manifeste du dossier dir: : sha256:$(sha256sum < "$D/@DOSSIER@/manifest.json" | cut -c1-64)"
true'

SONDE_HERMETIQUE='set -u
D=/w/voie2/depot
compte() { c=$(grep -c -E -e "$1" "$2" 2>/dev/null); echo "${c:-absent}"; }
cd /w/src && sha256sum -c SHA256SUMS.s1 > /w/c.log 2>&1; echo "sources livrées : rc $? $(paste -sd " " /w/c.log)"
df -k /w | awk "NR == 2 {print \"avant mock, capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
mkdir -p /w/res-h
t=$(date +%s)
mock --hermetic-build /w/verrou.json "$D" --isolation=@ISO@ --no-cleanup-after --config-opts=basedir=/w/mock-h --config-opts=cache_topdir=/w/mock-h-cache \
  --resultdir=/w/res-h --spec /w/src/sample-app.spec --sources /w/src > /w/hermetique.log 2>&1
r=$?; echo "mock --hermetic-build : rc $r en $(($(date +%s) - t)) s"
for m in "Using container image: dir:" "Pulling image: dir:" "Tagging container image as mock-bootstrap-" \
  "Checking image digest: @IMAGE_DIGEST@" "Calculating .* image OCI digest" "matches host.s architecture" \
  "falling back to chroot installation" "Expected digest for image" "Not updating bootstrap chroot" \
  "--installroot=/w/mock-h/" "No space left on device"; do
  echo "lignes « $m » : sortie $(compte "$m" /w/hermetique.log) ; root.log $(compte "$m" /w/res-h/root.log)"
done
echo "/var/lib/mock : $(ls -A /var/lib/mock 2>/dev/null | wc -l) entrée(s)"
ls -l /w/res-h | sed "s/^/résultat : /"
for f in /w/res-h/*.rpm; do [ -e "$f" ] || continue
  echo "rpm : ${f##*/} sha256 $(sha256sum < "$f" | cut -c1-64) ; $(rpm -qp --qf "BUILDHOST %{BUILDHOST} ; BUILDTIME %{BUILDTIME}" "$f" 2>/dev/null)"
done
df -k /w | awk "NR == 2 {print \"après mock (buildroot gardé, --no-cleanup-after), capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
[ $r = 0 ] || { tail -n 25 /w/hermetique.log; tail -n 25 /w/res-h/root.log 2>/dev/null; }
true'

etape_hermetique() {
  local bd n=$POD_M2 src dos ph id
  bd=$(cat "$T/boot-image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape boot_image" >&2; exit 1; }
  [[ $bd =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "KO   digest de boot_image illisible : $bd" >&2; exit 1; }
  [ -s "$T/m2-voie2.log" ] || { echo "KO   lancer d'abord l'étape voie2" >&2; exit 1; }
  attendu "dernière porte de voie2 (manifeste copié)" "$(champ m2-voie2 'OK   manifeste copié')" "$bd"
  ph=$(kubectl get pod -n builds "$n" -o jsonpath='{.status.phase}' </dev/null 2>/dev/null || true)
  attendu "pod $n laissé par voie2" "${ph:-absent}" Running
  src=$(jq -r '.config.bootstrap_image' "$R/s1-verrou_derivee.json"); dos=${src%%:*}@$bd
  id=$(jq -r '.bootstrap.image_digest' "$R/s1-verrou_derivee.json")
  sed -e "s|@DOSSIER@|$dos|g" <<<"$SONDE_HERMETIQUE_PRE" | dans "$n" m2-hermetique-pre
  ( attendu "verrou relu dans le pod" "$(champ m2-hermetique-pre 'verrou')" "sha256 $VERROU_DERIVEE_SHA"
    attendu "repomd.xml égal à celui de voie2" "$(champ m2-hermetique-pre 'repomd.xml')" "$(champ m2-voie2 'repomd.xml')"
    attendu "manifeste du dossier dir: (pull_digest)" "$(champ m2-hermetique-pre 'manifeste du dossier dir:')" "$bd" ) \
    || { pod_retirer "$n"; exit 1; }
  echo "mock --hermetic-build, isolation $ISOLATION ; RÉSEAU PRÉSENT (label $LABEL) : mécanisme mesuré, pas une preuve d'hermétisme"
  sed -e "s|@ISO@|$ISOLATION|g" -e "s|@IMAGE_DIGEST@|$id|g" <<<"$SONDE_HERMETIQUE" | dans "$n" m2-hermetique
  kubectl exec -n builds "$n" -- sh -c 'for f in /w/res-h/root.log /w/res-h/build.log; do [ -e "$f" ] && { echo "### $f"; tail -n 400 "$f"; }; done
    for f in /w/hermetique.log; do [ -e "$f" ] && { echo "### $f"; tail -n 80 "$f"; }; done; true' </dev/null \
    | sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' > "$R/$PREFIXE-hermetique-mock.log" || echo "journaux de mock : code non nul"
  echo "journaux de mock : $(wc -l < "$R/$PREFIXE-hermetique-mock.log") lignes, resultats/$PREFIXE-hermetique-mock.log"
  pod_retirer "$n"
}

# Étapes collecte, fermeture et restauration (s1-fermeture.patch, préparées à sec le 17/11/2026, NON APPLIQUÉES) : voir
# l'en-tête. collecte rejoue VOIE2_M2 tel quel dans un autre pod et un autre dossier ($T/mf, journal mf-voie2) : m2-voie2.log
# et $T/m2 ne sont pas touchés. fermeture et restauration reprennent etape_fermeture et etape_restauration de la 06 (s2.sh) ;
# écarts : fermeture recontrôlée avant l'envoi, tags relevés avant, couches comparées avec leur taille, df de Zot.
POD_MF=s1-05-mf
DEPOT_FERMETURE=deps/sample-app/mock-buildroot-lock   # nom du jalon M2 (README) et du doc 02
CLOSURE=$here/../03-deps-closure/closure.sh
MOCK_CHEMIN=Packages/m/mock-6.9-1.el9.noarch.rpm                                   # sous EPEL9 ; s1-racine.log, « rpm epel9 »
MOCK_SHA=a5043350d6d3efd92340f6d6fb221d720f6029ee8a9a8d09210d58f17752ba1e

primary_somme() { # primary.xml href : « type valeur » de la somme du paquet à cet emplacement, ou « absent »
  python3 -I - "$1" "$2" <<'PY'
import sys, xml.etree.ElementTree as E
C = '{http://linux.duke.edu/metadata/common}'; r = 'absent'
for _, e in E.iterparse(sys.argv[1]):
    if e.tag == C + 'package':
        if e.find(C + 'location').get('href') == sys.argv[2]:
            c = e.find(C + 'checksum'); r = f"{c.get('type')} {c.text}"
        e.clear()
print(r)
PY
}

fermeture_controle() { # construire <arbre> <liste.tsv> <T> <vault> <dossier dir:> <digest> <sha du verrou> <rpm de mock> <sha>
  # <liste du pod> <liste attendue à écrire> | comparer <arbre> <liste attendue> : KO sur tout écart, code 1
  python3 -I - "$@" <<'PY'
import hashlib, json, os, re, sys, xml.etree.ElementTree as E
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()
def arbre(d):  # fichiers réguliers, et toute autre entrée (lien, fichier spécial), en chemins relatifs
    fic, autres = [], []
    for r, ds, fs in os.walk(d):
        autres += [os.path.relpath(os.path.join(r, x), d) for x in ds if os.path.islink(os.path.join(r, x))]
        for x in fs:
            p = os.path.join(r, x)
            (fic if os.path.isfile(p) and not os.path.islink(p) else autres).append(os.path.relpath(p, d))
    return sorted(fic), sorted(autres)
def fin(ko, ok):
    for m in ko[:20]: print('KO  ', m)
    if ko: print(f'KO   {len(ko)} écart(s)'); sys.exit(1)
    print(ok)
def reel(d, fic): return {x: (sha(os.path.join(d, x)), os.path.getsize(os.path.join(d, x))) for x in fic}
mode = sys.argv[1]
if mode == 'comparer':
    d, att = sys.argv[2:4]; a = {}
    for l in open(att, encoding='utf-8'):
        p, h, s = l.rstrip('\n').rsplit(' ', 2); a[p] = (h, int(s))
    fic, autres = arbre(d)
    ko = [f"entrée qui n'est pas un fichier régulier : {x}" for x in autres]
    ko += [f'fichier en trop : {x}' for x in sorted(set(fic) - set(a))] + [f'fichier manquant : {x}' for x in sorted(set(a) - set(fic))]
    v = reel(d, sorted(set(fic) & set(a)))
    ko += [f'{x} : sha256 {v[x][0][:16]}…, {v[x][1]} octets (attendu {a[x][0][:16]}…, {a[x][1]} octets)' for x in v if v[x] != a[x]]
    fin(ko, f'OK   arbre égal à la liste : {len(a)} fichiers, {sum(s for _, s in a.values())} octets')
    sys.exit(0)
assert mode == 'construire', mode
d, tsv, prim, vault, dos, bd, vsha, mnom, msha, lpod, sortie = sys.argv[2:13]
ko, att, cl = [], {}, {}   # chemin : (sha256 attendu ou None, taille attendue ou None) ; chemin : classe
C = '{http://linux.duke.edu/metadata/common}'; RM = '{http://linux.duke.edu/metadata/repo}'
P = {}
for n in ('baseos97', 'appstream97', 'crb97'):
    for _, e in E.iterparse(f'{prim}/{n}.primary.xml'):
        if e.tag == C + 'package':
            c = e.find(C + 'checksum'); P[(n, e.find(C + 'location').get('href'))] = (c.get('type'), c.text, int(e.find(C + 'size').get('package')))
            e.clear()
DEP = {'BaseOS': 'baseos97', 'AppStream': 'appstream97', 'CRB': 'crb97'}
L = [l.rstrip('\n').split('\t') for l in open(tsv, encoding='utf-8')]
t = 0
for c in L:
    u = c[5]; f = 'depot/' + u.rsplit('/', 1)[1]; cl[f] = 'rpm'; att[f] = (None, None)
    dep, _, href = u[len(vault) + 1:].partition('/x86_64/os/')
    k = (DEP.get(dep), href)
    if not u.startswith(vault + '/') or k not in P: ko.append(f'{f} : absent des primary de vault 9.7'); continue
    if P[k][0] != 'sha256': ko.append(f'{f} : somme {P[k][0]} dans le primary'); continue
    att[f] = (P[k][1], P[k][2]); t += 1
print(f'rpm du verrou trouvés dans les primary de vault 9.7 vérifiés par hote97 : {t} sur {len(L)}')
rp = os.path.join(d, 'depot/repodata/repomd.xml'); att['depot/repodata/repomd.xml'] = (None, None); cl['depot/repodata/repomd.xml'] = 'repodata'
if os.path.isfile(rp) and not os.path.islink(rp):
    for x in E.parse(rp).getroot().findall(RM + 'data'):
        c = x.find(RM + 'checksum'); h = x.find(RM + 'location').get('href'); s = x.find(RM + 'size')
        if not re.fullmatch(r'repodata/[A-Za-z0-9._-]+', h or ''): ko.append(f'repomd.xml : emplacement refusé {h!r}'); continue
        if c.get('type') != 'sha256': ko.append(f'repomd.xml : somme {c.get("type")} pour {h}')
        att['depot/' + h] = (c.text if c.get('type') == 'sha256' else None, int(s.text) if s is not None else None); cl['depot/' + h] = 'repodata'
else: ko.append('depot/repodata/repomd.xml absent')
if not re.fullmatch(r'sha256:[0-9a-f]{64}', bd) or dos != 'sc-stockage.poc.test@' + bd: ko.append(f'dossier dir: refusé : {dos}')
mp = os.path.join(d, 'depot', dos, 'manifest.json')
for x in ('manifest.json', 'version'): att[f'depot/{dos}/{x}'] = (bd[7:] if x == 'manifest.json' else None, None); cl[f'depot/{dos}/{x}'] = 'image'
if os.path.isfile(mp) and not os.path.islink(mp) and 'sha256:' + sha(mp) == bd:
    m = json.load(open(mp, encoding='utf-8'))
    for b in [m['config']] + m['layers']:
        g = b['digest']
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', g): ko.append(f'manifeste : digest refusé {g!r}'); continue
        att[f'depot/{dos}/{g[7:]}'] = (g[7:], b['size']); cl[f'depot/{dos}/{g[7:]}'] = 'image'
    print(f'dossier dir: : manifeste {bd} ; config et {len(m["layers"])} couche(s)')
else: ko.append(f'manifeste du dossier dir: absent ou différent de {bd}')
att['verrou.json'] = (vsha, None); cl['verrou.json'] = 'verrou'
att[f'outils/{mnom}'] = (msha, None); cl[f'outils/{mnom}'] = 'outils'
fic, autres = arbre(d)
ko += [f"entrée qui n'est pas un fichier régulier : {x}" for x in autres]
ko += [f'fichier en trop : {x}' for x in sorted(set(fic) - set(att))] + [f'fichier manquant : {x}' for x in sorted(set(att) - set(fic))]
v = reel(d, fic)
for x in sorted(set(fic) & set(att)):
    h, s = att[x]
    if (h is not None and v[x][0] != h) or (s is not None and v[x][1] != s):
        ko.append(f'{x} : sha256 {v[x][0][:16]}…, {v[x][1]} octets (attendu {(h or "-")[:16]}…, {s} octets)')
pod = {}
for l in open(lpod, encoding='utf-8'):
    z = l.rstrip('\n').split(' ')
    if len(z) != 4 or z[0] != 'fichier': ko.append(f'liste du pod : ligne illisible {l.strip()[:60]!r}'); continue
    pod[z[1]] = (z[2], int(z[3]))
if pod != v: ko.append(f'liste du pod différente de l\'arbre rapatrié ({len(pod)} et {len(v)} fichiers, {len(set(pod.items()) ^ set(v.items()))} écart(s))')
fin(ko, f'OK   fermeture conforme : {len(v)} fichiers, {sum(s for _, s in v.values())} octets ; sha256 des rpm égaux aux primary, '
        'repodata égal à repomd.xml, blobs égaux à leur nom, manifeste, verrou et rpm de mock épinglés ; liste du pod égale')
for k in ('rpm', 'repodata', 'image', 'verrou', 'outils'):
    z = [x for x in v if cl[x] == k]; print(f'classe {k} : {len(z)} fichier(s), {sum(v[x][1] for x in z)} octets')
print(f'version du dossier dir: : sha256 {v["depot/" + dos + "/version"][0]}')
with open(sortie, 'w', encoding='utf-8') as o:
    for x in sorted(v): o.write(f'{x} {v[x][0]} {v[x][1]}\n')
PY
}

SONDE_COLLECTE='set -u
export LC_ALL=C
F=/w/fermeture; E=/w/rpmdb-epel
ko() { echo "KO   $*"; exit 1; }
for o in curl rpm tar find stat sort sha256sum; do command -v $o >/dev/null 2>&1 || ko "$o absent de l image"; done
[ -d /w/voie2/depot ] || ko "dépôt de voie2 absent"
rm -rf "$F" "$E"; mkdir -p "$F/outils" "$E"
h=$(curl -sS --proto =https --max-time 300 -o "$F/outils/@MOCK_NOM@" -w "%{http_code}" "@MOCK_URL@") || ko "curl en échec : @MOCK_URL@"
[ "$h" = 200 ] || ko "HTTP $h : @MOCK_URL@"
s=$(sha256sum < "$F/outils/@MOCK_NOM@" | cut -c1-64)
[ "$s" = "@MOCK_SHA@" ] || ko "rpm de mock : sha256 $s, attendu @MOCK_SHA@"
rpm --dbpath "$E" --initdb </dev/null || ko "rpmdb à part non créée"
rpm --dbpath "$E" --import /w/cles/RPM-GPG-KEY-EPEL-9 </dev/null || ko "clé d EPEL non importée"
k=$(rpm --dbpath "$E" -K "$F/outils/@MOCK_NOM@" 2>&1 </dev/null); r=$?
echo "rpm -K du rpm de mock (seule clé d EPEL) : rc $r ; ${k##*: }"
[ "$r" = 0 ] && [ "${k##*: }" = "digests signatures OK" ] || ko "signature du rpm de mock"
echo "OK   rpm de mock : @MOCK_NOM@ sha256 $s"
mv /w/voie2/depot "$F/depot" || ko "dépôt de voie2 non déplacé"
cp /w/verrou.json "$F/verrou.json" || ko "verrou non copié"
(cd "$F" && find . -type f -printf "%P\n" | sort | while IFS= read -r f; do echo "fichier $f $(sha256sum < "$f" | cut -c1-64) $(stat -c %s "$f")"; done) > /w/fermeture.liste
cat /w/fermeture.liste
echo "autres entrées que fichiers et dossiers : $(find "$F" ! -type f ! -type d | wc -l)"
echo "fichiers de la fermeture : $(wc -l < /w/fermeture.liste) ; octets : $(awk "{s += \$4} END {print s}" /w/fermeture.liste)"
df -k /w | awk "NR == 2 {print \"capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
'

etape_collecte() {
  local d bd n=$POD_MF o=$T/mf fp fe src dos
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  bd=$(cat "$T/boot-image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape boot_image" >&2; exit 1; }
  [[ $bd =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "KO   digest de boot_image illisible : $bd" >&2; exit 1; }
  attendu "verrou d'entrée resultats/s1-verrou_derivee.json, sha256" "$(sha256sum < "$R/s1-verrou_derivee.json" | cut -c1-64)" \
    "$VERROU_DERIVEE_SHA"
  [ -s "$T/hote/RPM-GPG-KEY-Rocky-9" ] && [ -s "$T/hote/RPM-GPG-KEY-EPEL-9" ] && [ -s "$T/fp-epel" ] \
    || { echo "KO   clés absentes : lancer d'abord l'étape hote" >&2; exit 1; }
  fp=$(gpg --batch --with-colons --show-keys "$T/hote/RPM-GPG-KEY-Rocky-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  attendu "empreinte de la clé de Rocky livrée" "$fp" "$FP_ROCKY"
  fe=$(gpg --batch --with-colons --show-keys "$T/hote/RPM-GPG-KEY-EPEL-9" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  attendu "empreinte de la clé d'EPEL livrée (comparée par hote à la page publiée)" "$fe" "$(cat "$T/fp-epel")"
  attendu "rpm de mock dans le primary d'EPEL du dernier passage de hote" "$(primary_somme "$T/epel9.primary.xml" "$MOCK_CHEMIN")" \
    "sha256 $MOCK_SHA"
  rm -rf -- "${o:?}"
  m2_preparer "$R/s1-verrou_derivee.json" "$o" "$bd"
  src=$(jq -r '.config.bootstrap_image' "$R/s1-verrou_derivee.json"); dos=${src%%:*}@$bd
  echo "image : $REG/$DEPOT_ESSAI@$d ; pod : $n"
  pod_spec "$n" "$REG/$DEPOT_ESSAI@$d"
  pod_demarrer "$n"
  livrer "$n" "/etc/containers/certs.d/$REG/ca.crt" "$P/ca-poc.crt"
  livrer "$n" /w/cles/RPM-GPG-KEY-Rocky-9 "$T/hote/RPM-GPG-KEY-Rocky-9"
  livrer "$n" /w/cles/RPM-GPG-KEY-EPEL-9 "$T/hote/RPM-GPG-KEY-EPEL-9"
  livrer "$n" /w/voie2/liste.tsv "$o/liste.tsv"
  livrer "$n" /w/verrou.json "$R/s1-verrou_derivee.json"
  dans "$n" mf-voie2 < "$o/voie2.sh"
  ( attendu "verrou relu dans le pod" "$(champ mf-voie2 'verrou livré')" "sha256 $VERROU_DERIVEE_SHA"
    attendu "manifeste copié (dernière porte de voie2)" "$(champ mf-voie2 'OK   manifeste copié')" "$bd" ) \
    || { pod_retirer "$n"; exit 1; }
  sed -e "s|@MOCK_URL@|$EPEL9/$MOCK_CHEMIN|g" -e "s|@MOCK_NOM@|${MOCK_CHEMIN##*/}|g" -e "s|@MOCK_SHA@|$MOCK_SHA|g" \
    <<<"$SONDE_COLLECTE" | dans "$n" mf-collecte
  ( attendu "rpm de mock (porte de collecte)" "$(champ mf-collecte 'OK   rpm de mock')" "${MOCK_CHEMIN##*/} sha256 $MOCK_SHA"
    [ -n "$(champ mf-collecte 'fichiers de la fermeture')" ] || { echo "KO   liste de la fermeture absente" >&2; exit 1; } ) \
    || { pod_retirer "$n"; exit 1; }
  mkdir -p "$o/fermeture"
  kubectl exec -n builds "$n" -- tar -C /w/fermeture -cf - . </dev/null | tar -xf - -C "$o/fermeture" \
    || { pod_retirer "$n"; echo "KO   rapatriement de la fermeture" >&2; exit 1; }
  pod_retirer "$n"
  sed -n 's/^fichier /fichier /p' "$T/mf-collecte.log" > "$o/liste-pod.txt"
  fermeture_controle construire "$o/fermeture" "$o/liste.tsv" "$T" "$VAULT97" "$dos" "$bd" "$VERROU_DERIVEE_SHA" \
    "${MOCK_CHEMIN##*/}" "$MOCK_SHA" "$o/liste-pod.txt" "$o/fermeture.attendue" || { echo "KO   fermeture non conforme" >&2; exit 1; }
  echo "liste attendue : $(wc -l < "$o/fermeture.attendue") lignes, sha256 $(sha256sum < "$o/fermeture.attendue" | cut -c1-64)"
}

oras_zot() { echo "--registry-config $T/zot.json --ca-file $P/ca-poc.crt"; }   # comme la 06 ; chemins sans espace (contrôlé)
zot_place() { # utilisés et libres, en octets, du système de fichiers de /var/lib/zot (sans sudo) ; « illisible illisible » sinon
  local u a
  read -r u a < <(sur sc-stockage 'df -B1 --output=used,avail /var/lib/zot | tail -n 1' </dev/null 2>/dev/null) || true
  if [[ ${u:-} =~ ^[0-9]+$ && ${a:-} =~ ^[0-9]+$ ]]; then echo "$u $a"; else echo "illisible illisible"; fi
}
de_plus() { if [[ $1 =~ ^[0-9]+$ && $2 =~ ^[0-9]+$ ]]; then echo "$(($2 - $1)) octets de plus"; else echo "illisible"; fi; }
zot_liens() { # dossier-dir: liste-attendue : inode et nombre de liens de la config et des couches de l'image sous $DEPOT_DERIVE
  # puis sous $DEPOT_FERMETURE (stat sans sudo sur sc-stockage, rejouable ; « illisible » si refusé) ; n'arrête rien, aucun pari
  local h c
  for h in $(awk -v p="depot/$1/" 'index($1, p) == 1 { f = substr($1, length(p) + 1); if (f ~ /^[0-9a-f]+$/ && length(f) == 64) print f }' "$2" | sort); do
    # shellcheck disable=SC2029  # $h et les dépôts sont développés ici, à dessein ; \$d l'est sur sc-stockage
    c=$(sur sc-stockage "for d in $DEPOT_DERIVE $DEPOT_FERMETURE; do stat -c '%i %h' /var/lib/zot/\$d/blobs/sha256/$h 2>/dev/null || echo illisible; done | paste -sd ' '" </dev/null 2>/dev/null) || c=
    echo "blob ${h:0:12}… : inode et liens sous $DEPOT_DERIVE puis $DEPOT_FERMETURE : ${c:-illisible}"
  done
  true
}

etape_fermeture() {
  local o=$T/mf bd dos cat tags img tot im mi u0 a0 v0 u1 u2 r1 r2 d t
  [ -s "$o/fermeture.attendue" ] && [ -d "$o/fermeture" ] || { echo "KO   lancer d'abord l'étape collecte" >&2; exit 1; }
  case "$T$P" in *' '*) echo "KO   chemin avec espace" >&2; exit 1 ;; esac
  bd=$(cat "$T/boot-image.digest"); dos=sc-stockage.poc.test@$bd
  fermeture_controle comparer "$o/fermeture" "$o/fermeture.attendue" || { echo "KO   fermeture changée depuis collecte" >&2; exit 1; }
  auth_zot "$T/zot.json"
  # Garde des tags : une liste vide doit venir d'une lecture réussie (catalogue lu ; tags lus si le dépôt y figure)
  # shellcheck disable=SC2046
  cat=$(oras repo ls $(oras_zot) "$REG_HOTE") || { echo "KO   catalogue de Zot illisible : rien n'est envoyé" >&2; exit 1; }
  if grep -q -x -F -e "$DEPOT_FERMETURE" <<<"$cat"; then
    # shellcheck disable=SC2046
    tags=$(oras repo tags $(oras_zot) "$REG_HOTE/$DEPOT_FERMETURE") || { echo "KO   tags de $DEPOT_FERMETURE illisibles : rien n'est envoyé" >&2; exit 1; }
    echo "catalogue de Zot : $(grep -c . <<<"$cat" || true) dépôts ; $DEPOT_FERMETURE présent, $(grep -c . <<<"$tags" || true) tag(s)"
  else
    tags=; echo "catalogue de Zot : $(grep -c . <<<"$cat" || true) dépôts ; $DEPOT_FERMETURE absent"
  fi
  ! grep -q -x -e "$PREFIXE" -e "$PREFIXE-bis" <<<"$tags" || { echo "KO   tag $PREFIXE ou $PREFIXE-bis déjà présent" >&2; exit 1; }
  img=$(zot crane manifest "$REG_HOTE/$DEPOT_DERIVE@$bd" | jq -r '[.config.digest, .layers[].digest | ltrimstr("sha256:")] | sort | join(" ")')
  attendu "blobs de l'image sous $DEPOT_DERIVE = blobs du dossier dir:" "$img" "$(awk -v p="depot/$dos/" \
    'index($1, p) == 1 { f = substr($1, length(p) + 1); if (f ~ /^[0-9a-f]+$/ && length(f) == 64) print f }' "$o/fermeture.attendue" | sort | paste -sd ' ')"
  tot=$(awk '{s += $3} END {print s}' "$o/fermeture.attendue")
  im=$(awk -v p="depot/$dos/" 'index($1, p) == 1 { f = substr($1, length(p) + 1); if (f ~ /^[0-9a-f]+$/ && length(f) == 64) s += $3 } END {print s + 0}' "$o/fermeture.attendue")
  mi=$(awk -v p="depot/$dos/manifest.json" '$1 == p {print $3}' "$o/fermeture.attendue")
  echo "fermeture : $(wc -l < "$o/fermeture.attendue") fichiers, $tot octets ; dont config et couches de l'image, relevées sous $DEPOT_DERIVE : $im octets ; manifeste de l'image : ${mi:-?} octets"
  read -r u0 a0 < <(zot_place); read -r v0 _ < <(zot_place)
  [[ $u0 =~ ^[0-9]+$ && $a0 =~ ^[0-9]+$ ]] || { echo "KO   place de Zot illisible : rien n'est envoyé" >&2; exit 1; }
  echo "/var/lib/zot avant l'envoi : utilisés $u0 octets, puis $v0 à une seconde lecture ($(de_plus "$u0" "$v0")) ; libres $a0 octets"
  [ "$a0" -gt $((2 * tot)) ] || { echo "KO   place libre de Zot sous le double de la fermeture : rien n'est envoyé" >&2; exit 1; }
  t=$(date +%s); r1=$(ORAS_OPTS=$(oras_zot) "$CLOSURE" push "$o/fermeture" "$REG_HOTE/$DEPOT_FERMETURE:$PREFIXE")
  echo "envoi 1 (tag $PREFIXE) : $(($(date +%s) - t)) s"
  d=${r1#*@}; [[ $d =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "KO   digest de la fermeture illisible : $d" >&2; exit 1; }
  echo "$d" > "$o/fermeture.digest"; echo "fermeture : ${r1/$REG_HOTE/$REG}"
  read -r u1 _ < <(zot_place)
  t=$(date +%s); r2=$(ORAS_OPTS=$(oras_zot) "$CLOSURE" push "$o/fermeture" "$REG_HOTE/$DEPOT_FERMETURE:$PREFIXE-bis")
  echo "envoi 2 (tag $PREFIXE-bis) : $(($(date +%s) - t)) s"; read -r u2 _ < <(zot_place)
  echo "/var/lib/zot, utilisés : envoi 1 : $(de_plus "$v0" "$u1") ; envoi 2 : $(de_plus "$u1" "$u2")"
  attendu "digest du second envoi" "${r2#*@}" "$d"
  # shellcheck disable=SC2046
  oras manifest fetch $(oras_zot) "$REG_HOTE/$DEPOT_FERMETURE@$d" > "$o/manifest.json"
  attendu "digest du manifeste relu" "sha256:$(sha256sum < "$o/manifest.json" | cut -c1-64)" "$d"
  attendu "couches du manifeste" "$(jq '.layers | length' "$o/manifest.json")" "$(wc -l < "$o/fermeture.attendue")"
  attendu "couches (titre, digest, taille) = liste de collecte" \
    "$(jq -r '.layers[] | "\(.annotations["org.opencontainers.image.title"]) \(.digest | ltrimstr("sha256:")) \(.size)"' "$o/manifest.json" \
      | sort | sha256sum | cut -c1-64)" "$(sort "$o/fermeture.attendue" | sha256sum | cut -c1-64)"
  zot_liens "$dos" "$o/fermeture.attendue"
}

etape_restauration() {
  local o=$T/mf d bd
  d=$(cat "$o/fermeture.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape fermeture" >&2; exit 1; }
  [[ $d =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "KO   digest de la fermeture illisible : $d" >&2; exit 1; }
  case "$T$P" in *' '*) echo "KO   chemin avec espace" >&2; exit 1 ;; esac
  bd=$(cat "$T/boot-image.digest")
  auth_zot "$T/zot.json"
  rm -rf -- "${o:?}/restauree"
  ORAS_OPTS=$(oras_zot) "$CLOSURE" pull "$REG_HOTE/$DEPOT_FERMETURE@$d" "$o/restauree"
  echo "restaurée depuis $REG/$DEPOT_FERMETURE@$d, dans un dossier vide"
  fermeture_controle comparer "$o/restauree" "$o/fermeture.attendue" || { echo "KO   fermeture restaurée différente" >&2; exit 1; }
  zot_liens "sc-stockage.poc.test@$bd" "$o/fermeture.attendue"
}

# Étapes m3_reseau, m3_temoin, m3_restauration, m3_build1, m3_build2 et m3_comparaison (s1-m3-2.patch, préparées à sec le
# 17/11/2026, NON APPLIQUÉES ; jalon M3 ; remplace s1-m3.patch, gardé) : voir l'en-tête. Tout ce qui entre dans mock vient de la fermeture restaurée ($T/m3/restauree-<n>) ;
# $T/mf/fermeture.attendue et VERROU_DERIVEE_SHA ne servent que d'attendus. Sources de sample-app et image d'essai hors fermeture.
# « Sans réseau » (décision « Tout couper ») : ni entrée ni sortie pour le label construire-rpm ; les témoins doivent tous échouer.
POD_M3=s1-05-m3
FERMETURE_DIGEST=sha256:f235a98b46d82b2d295cd39e869eb07344938e8896fc4f7465171687e9c48417   # fermeture de M2 (s1-fermeture.log)
RPM_HERMETIQUE=864d55f486f423cec854cdeecd3458b13e83a5e4f4d70f77345b7e99b808c68f    # rpm binaire d'hermetique (s1-hermetique.log)
SRPM_HERMETIQUE=c802e60a511c140e3a6761752b0c9966b2d8959a909d2a3b73d85f9b4bfd1128   # src.rpm d'hermetique (même journal)
TEMOIN_HOTE=dl.rockylinux.org   # adresse publique des dépôts de Rocky : résolue sur l'hôte, témoin TCP sur 443
MORCEAU_MIO=64
LABEL_M3=construire-rpm   # nom de la tâche de M4 ; sélectionné par construction-rpm-sans-sortie
POLITIQUE_M3=$here/politiques/construction-rpm-sans-sortie.yaml
POD_M3T=s1-05-m3-temoin

politique_m3_relue() { # politiques de builds relues dans le cluster ; KO si le label $LABEL_M3 n'est pas coupé
  local t=$T/m3-politiques.json
  { kubectl get networkpolicy -n builds -o json </dev/null | jq '.items[] | .kind = "NetworkPolicy"'
    kubectl get ciliumnetworkpolicy -n builds -o json </dev/null | jq '.items[] | .kind = "CiliumNetworkPolicy"'; } | jq -s '{items: .}' > "$t"
  echo "politiques de builds : $(jq -r '[.items[] | "\(.kind) \(.metadata.name)"] | join(", ")' "$t")"
  attendu "construction-rpm-sans-sortie : sélecteur, types, règles d'entrée et de sortie" \
    "$(jq -c '[.items[] | select(.kind == "NetworkPolicy" and .metadata.name == "construction-rpm-sans-sortie")
      | [.spec.podSelector, (.spec.policyTypes | sort), (.spec.ingress // []), (.spec.egress // [])]]' "$t")" \
    "[[{\"matchLabels\":{\"tekton.dev/task\":\"$LABEL_M3\"}},[\"Egress\",\"Ingress\"],[],[]]]"
  attendu "politiques de builds qui sélectionnent $LABEL_M3 et autorisent du trafic" "$(jq -r -L "$here/../08-trust-plane" --arg l "$LABEL_M3" \
    'include "selecteurs"; [.items[] | select(selectionne({"tekton.dev/task": $l}) and autorise) | nom] | join(", ")' "$t")" ""
}

etape_m3_reseau() { # écriture dans le cluster : pose de construction-rpm-sans-sortie
  attendu "politique du dépôt : nom, sélecteur, types, règles" "$(kubectl create --dry-run=client -o json -f "$POLITIQUE_M3" </dev/null \
    | jq -c '[.metadata.namespace, .metadata.name, .spec.podSelector, (.spec.policyTypes | sort), (.spec.ingress // []), (.spec.egress // [])]')" \
    "[\"builds\",\"construction-rpm-sans-sortie\",{\"matchLabels\":{\"tekton.dev/task\":\"$LABEL_M3\"}},[\"Egress\",\"Ingress\"],[],[]]"
  kubectl apply --dry-run=server -f "$POLITIQUE_M3" </dev/null >/dev/null || { echo "KO   politique refusée en dry-run serveur" >&2; exit 1; }
  echo "OK   politique admise en dry-run serveur"
  kubectl apply -f "$POLITIQUE_M3" </dev/null
  politique_m3_relue
}

resoudre() { getent ahostsv4 "$1" 2>/dev/null | awk 'NR == 1 {print $1}'; }   # sur l'hôte : première adresse IPv4
temoins_cibles() { # « adresse-publique adresse-de-Zot adresse-de-l'API », lues sur l'hôte ; code 1 si l'une est illisible
  local x pub api
  pub=$(resoudre "$TEMOIN_HOTE"); api=$(kubectl get svc -n default kubernetes -o jsonpath='{.spec.clusterIP}' </dev/null)
  for x in "$pub" "${REG_HOTE%:*}" "$api"; do
    [[ $x =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "KO   adresse de témoin illisible : « $x »" >&2; return 1; }; done
  echo "$pub ${REG_HOTE%:*} $api"
}
SONDE_TEMOINS='set -u
for o in bash getent timeout head tr; do command -v $o >/dev/null 2>&1 || { echo "KO   $o absent de l image"; exit 1; }; done
timeout 10 getent hosts @HOTE@ > /w/t-dns.log 2>&1; echo "témoin DNS @HOTE@ (10 s) : rc $?"
for c in "public @PUB@ 443" "Zot @ZOT@ @ZOT_PORT@" "API @API@ 443"; do
  set -- $c
  timeout 10 bash -c "exec 3<>/dev/tcp/$2/$3" > /w/t-tcp.log 2>&1; echo "témoin TCP $1 $2:$3 (10 s) : rc $? $(head -c 120 /w/t-tcp.log | tr "\n" " ")"
done
true'
temoins() { # pod « cibles » libellé : SONDE_TEMOINS dans le pod, journal $T/<libellé>.log
  local pub zot api; read -r pub zot api <<<"$2"
  sed -e "s|@HOTE@|$TEMOIN_HOTE|g" -e "s|@PUB@|$pub|g" -e "s|@ZOT@|$zot|g" -e "s|@ZOT_PORT@|${REG_HOTE##*:}|g" -e "s|@API@|$api|g" \
    <<<"$SONDE_TEMOINS" | dans "$1" "$3"
}
temoins_rc() { # libellé : codes « DNS public Zot API » relus dans le journal
  local l; for l in 'témoin DNS [^ ]*' 'témoin TCP public [^ ]*' 'témoin TCP Zot [^ ]*' 'témoin TCP API [^ ]*'; do
    champ "$1" "$l (10 s)" | awk '{print $2}'; done | paste -sd ' '
}

etape_m3_temoin() { # témoin positif, lecture seule : pod au label $LABEL (prefetch-rpm-sortie : DNS, 443 public, Zot)
  local d n=$POD_M3T c r
  rm -f -- "$T/m3-cibles"
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  c=$(temoins_cibles) || exit 1
  echo "cibles des témoins (lues sur l'hôte) : public $TEMOIN_HOTE ${c%% *} ; Zot et API ${c#* }"
  pod_spec "$n" "$REG/$DEPOT_ESSAI@$d"
  pod_demarrer "$n"
  temoins "$n" "$c" m3-temoin
  pod_retirer "$n"
  r=$(temoins_rc m3-temoin)
  attendu "témoin positif (label $LABEL), codes DNS, public, Zot" "$(cut -d ' ' -f1-3 <<<"$r")" "0 0 0"
  echo "témoin positif, code API (non autorisée par prefetch-rpm-sortie ; relevé, sans pari) : $(cut -d ' ' -f4 <<<"$r")"
  echo "$c" > "$T/m3-cibles"; echo "cibles écrites pour m3_build1 et m3_build2 : $c"
}

etape_m3_restauration() {
  local o=$T/m3 n
  [ -s "$T/mf/fermeture.attendue" ] || { echo "KO   liste de collecte absente : lancer d'abord l'étape collecte" >&2; exit 1; }
  attendu "digest écrit par l'étape fermeture" "$(cat "$T/mf/fermeture.digest" 2>/dev/null || echo absent)" "$FERMETURE_DIGEST"
  case "$T$P" in *' '*) echo "KO   chemin avec espace" >&2; exit 1 ;; esac
  auth_zot "$T/zot.json"
  mkdir -p "$o"
  for n in 1 2; do
    rm -rf -- "${o:?}/restauree-$n"
    ORAS_OPTS=$(oras_zot) "$CLOSURE" pull "$REG_HOTE/$DEPOT_FERMETURE@$FERMETURE_DIGEST" "$o/restauree-$n"
    echo "restauration $n depuis $REG/$DEPOT_FERMETURE@$FERMETURE_DIGEST, dans un dossier vide"
    fermeture_controle comparer "$o/restauree-$n" "$T/mf/fermeture.attendue" || { echo "KO   fermeture restaurée $n différente" >&2; exit 1; }
  done
}

copier() { # pod fichier-hôte chemin-pod : repris de la 06 (s3.sh, après sa sonde du 10/11 : l'exec sous Kata bloque à 512 Mio)
  local n i k e m=$((MORCEAU_MIO * 1048576)) nb
  n=$(stat -c %s "$2"); nb=$(( (n + m - 1) / m )); [ "$nb" -gt 0 ] || nb=1
  kubectl exec -n builds "$1" -- sh -c ": > $3" </dev/null
  for ((i = 0; i < nb; i++)); do
    k=$(( n - i * m < m ? n - i * m : m ))
    dd if="$2" bs=1M skip=$((i * MORCEAU_MIO)) count=$MORCEAU_MIO status=none \
      | timeout 120 kubectl exec -i -n builds "$1" -- sh -c "head -c $k >> $3" \
      || { pod_retirer "$1"; echo "KO   copie de ${2##*/}, morceau $((i + 1)) sur $nb" >&2; exit 1; }
    e=$(kubectl exec -n builds "$1" -- stat -c %s "$3" </dev/null)
    [ "$e" = "$(( i * m + k ))" ] \
      || { pod_retirer "$1"; echo "KO   copie de ${2##*/} : $e octets après le morceau $((i + 1)) (attendu : $(( i * m + k )))" >&2; exit 1; }
  done
  e=$(kubectl exec -n builds "$1" -- sha256sum "$3" </dev/null | cut -c1-64)
  [ "$e" = "$(sha256sum < "$2" | cut -c1-64)" ] && echo "OK   copie de ${2##*/} dans le pod : $n octets en $nb morceau(x), sha256 conforme" \
    || { pod_retirer "$1"; echo "KO   copie de ${2##*/} : sha256 dans le pod $e" >&2; exit 1; }
}

m3_pod() { # nom image : pod de pod_spec au label $LABEL_M3 ; spec admise en dry-run serveur ; label relu dans le cluster
  local LABEL=$LABEL_M3
  pod_spec "$1" "$2"
  attendu "label tekton.dev/task de la spec $1" "$(jq -r '.metadata.labels["tekton.dev/task"] // "absent"' "$T/$1.json")" "$LABEL_M3"
  kubectl delete pod -n builds "$1" --ignore-not-found --wait=true </dev/null >/dev/null
  kubectl create --dry-run=server -f "$T/$1.json" </dev/null >/dev/null || { echo "KO   spec $1 refusée en dry-run serveur" >&2; exit 1; }
  echo "OK   spec $1 admise en dry-run serveur"
  pod_demarrer "$1"
  ( attendu "label tekton.dev/task du pod $1, relu dans le cluster" \
      "$(kubectl get pod -n builds "$1" -o json </dev/null | jq -r '.metadata.labels["tekton.dev/task"] // "absent"')" "$LABEL_M3" ) \
    || { pod_retirer "$1"; exit 1; }
}

SONDE_M3='set -u
export LC_ALL=C
B=@B@; F=@B@/fermeture; D=@B@/fermeture/depot
compte() { c=$(grep -c -E -e "$1" "$2" 2>/dev/null); echo "${c:-absent}"; }
ko() { echo "KO   $*"; exit 1; }
for o in rpm mock sha256sum find df tar; do command -v $o >/dev/null 2>&1 || ko "$o absent de l image"; done
echo "invité : $(uname -r), $(nproc) vCPU ; uid $(id -u)"
(cd "$F" && sha256sum -c --quiet /w/fermeture.sha256) > /w/f.log 2>&1; r=$?
echo "fermeture revérifiée dans le pod : rc $r ; fichiers $(find "$F" -type f | wc -l) ; lignes de la liste $(wc -l < /w/fermeture.sha256)"
[ $r = 0 ] || { head -c 600 /w/f.log; ko "fermeture différente de la liste de collecte"; }
[ "$(find "$F" -type f | wc -l)" = "$(wc -l < /w/fermeture.sha256)" ] || ko "fichiers en trop dans la fermeture"
echo "verrou de la fermeture : sha256 $(sha256sum < "$F/verrou.json" | cut -c1-64)"
echo "manifeste du dossier dir: : sha256:$(sha256sum < "$D/@DOSSIER@/manifest.json" | cut -c1-64)"
(cd /w/src && sha256sum -c SHA256SUMS.s1) > /w/c.log 2>&1; r=$?; echo "sources livrées : rc $r $(paste -sd " " /w/c.log)"
[ $r = 0 ] || ko "sources de sample-app"
echo "mock de la fermeture : $(rpm -qp --qf "%{NEVRA} %{SHA256HEADER}" "$F/outils/@MOCK_NOM@" 2>/dev/null)"
echo "mock de l image : $(rpm -q --qf "%{NEVRA} %{SHA256HEADER}" mock 2>/dev/null)"
df -k /w | awk "NR == 2 {print \"avant mock, capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
mkdir -p "$B/res"
t=$(date +%s)
mock --hermetic-build "$F/verrou.json" "$D" --isolation=@ISO@ --no-cleanup-after --config-opts=basedir=$B/mock-h \
  --config-opts=cache_topdir=$B/mock-h-cache --resultdir=$B/res --spec /w/src/sample-app.spec --sources /w/src > "$B/mock.out" 2>&1
r=$?; echo "mock --hermetic-build : rc $r en $(($(date +%s) - t)) s"
for m in "Using container image: dir:" "Checking image digest: @IMAGE_DIGEST@" "falling back to chroot installation" \
  "Expected digest for image" "Not updating bootstrap chroot" "installroot.{1,4}$B/mock-h/" "No space left on device"; do
  echo "lignes « $m » : sortie $(compte "$m" "$B/mock.out") ; root.log $(compte "$m" "$B/res/root.log")"
done
for f in "$B/mock.out" "$B/res/root.log" "$B/res/build.log"; do echo "lignes http ou https de ${f##*/} : $(compte "https?://" "$f")"; done
echo "installed_pkgs.log : $(wc -l < "$B/res/installed_pkgs.log" 2>/dev/null || echo absent) ligne(s)"
rpm -qa --root "$B/mock-h/hermetic-build/root" --qf "paquet %{NAME} %{VERSION} %{RELEASE} %{ARCH} %{SIGMD5}\n" 2>/dev/null | sort
echo "paquets du buildroot (rpm --root) : $(rpm -qa --root "$B/mock-h/hermetic-build/root" 2>/dev/null | wc -l)"
ls -l "$B/res" | sed "s/^/résultat : /"
for f in "$B/res"/*.rpm; do [ -e "$f" ] || continue
  echo "rpm : ${f##*/} sha256 $(sha256sum < "$f" | cut -c1-64) ; NEVRA $(rpm -qp --qf "%{NEVRA} ; BUILDHOST %{BUILDHOST} ; BUILDTIME %{BUILDTIME}" "$f" 2>/dev/null)"
done
df -k /w | awk "NR == 2 {print \"après mock (buildroot gardé), capacité de /w : \" \$2 \" kB ; utilisés : \" \$3 \" kB\"}"
true'

m3_build() { # n : build n dans le pod $POD_M3-n, depuis $T/m3/restauree-n, chemins sous /w/bn
  local n=$1 p=$POD_M3-$1 o=$T/m3 b=/w/b$1 d bd v src dos id f x c r z=0
  d=$(cat "$T/image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape image" >&2; exit 1; }
  bd=$(cat "$T/boot-image.digest" 2>/dev/null) || { echo "KO   lancer d'abord l'étape boot_image" >&2; exit 1; }
  [[ $bd =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "KO   digest de boot_image illisible : $bd" >&2; exit 1; }
  [ -d "$o/restauree-$n" ] && [ -s "$T/mf/fermeture.attendue" ] || { echo "KO   lancer d'abord l'étape m3_restauration" >&2; exit 1; }
  fermeture_controle comparer "$o/restauree-$n" "$T/mf/fermeture.attendue" || { echo "KO   fermeture restaurée $n changée" >&2; exit 1; }
  v=$o/restauree-$n/verrou.json
  attendu "verrou de la fermeture restaurée $n, sha256" "$(sha256sum < "$v" | cut -c1-64)" "$VERROU_DERIVEE_SHA"
  src=$(jq -r '.config.bootstrap_image' "$v"); dos=${src%%:*}@$bd; id=$(jq -r '.bootstrap.image_digest' "$v")
  [[ $id =~ ^[0-9a-f]{64}$ ]] || { echo "KO   image_digest du verrou illisible : $id" >&2; exit 1; }
  attendu "manifeste du dossier dir: de la fermeture restaurée $n" \
    "sha256:$(sha256sum < "$o/restauree-$n/depot/$dos/manifest.json" | cut -c1-64)" "$bd"
  (cd "$PKG" && sha256sum -c --quiet "$T/SHA256SUMS.s1") || { echo "KO   sources de sample-app" >&2; exit 1; }
  awk '{print $2 "  " $1}' "$T/mf/fermeture.attendue" > "$o/fermeture.sha256"
  tar -C "$o/restauree-$n" -cf "$o/fermeture-$n.tar" .
  politique_m3_relue
  c=$(cat "$T/m3-cibles" 2>/dev/null) || { echo "KO   cibles absentes : lancer d'abord l'étape m3_temoin" >&2; exit 1; }
  [[ $c =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}\ [0-9]{1,3}(\.[0-9]{1,3}){3}\ [0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "KO   cibles illisibles : $c" >&2; exit 1; }
  echo "image : $REG/$DEPOT_ESSAI@$d ; pod : $p ; chemins sous $b ; cibles des témoins : $c"
  m3_pod "$p" "$REG/$DEPOT_ESSAI@$d"
  temoins "$p" "$c" "m3-temoins$n"
  r=$(temoins_rc "m3-temoins$n"); echo "témoins, codes DNS, public, Zot, API : $r"
  awk 'function f(x) {return x == 1 || x == 2 || x == 124}   # refus, nom introuvable, délai ; tout autre code arrête
    NF == 4 && f($1) && f($2) && f($3) && f($4) {t = 1} END {exit !t}' <<<"$r" \
    || { pod_retirer "$p"; echo "KO   réseau joignable ou témoin illisible (codes : $r) : mock non lancé" >&2; exit 1; }
  echo "OK   témoins : DNS, adresse publique, Zot et API injoignables"
  copier "$p" "$o/fermeture-$n.tar" /w/fermeture.tar
  copier "$p" "$o/fermeture.sha256" /w/fermeture.sha256
  kubectl exec -n builds "$p" -- sh -c "mkdir -p $b/fermeture && tar --no-same-owner -xf /w/fermeture.tar -C $b/fermeture && rm /w/fermeture.tar" \
    </dev/null || { pod_retirer "$p"; echo "KO   déballage de la fermeture dans $p" >&2; exit 1; }
  livrer "$p" /w/src/sample-app-1.0.0.tar.gz "$PKG/sample-app-1.0.0.tar.gz"
  livrer "$p" /w/src/sample-app.spec "$PKG/sample-app.spec"
  livrer "$p" /w/src/SHA256SUMS.s1 "$T/SHA256SUMS.s1"
  sed -e "s|@B@|$b|g" -e "s|@DOSSIER@|$dos|g" -e "s|@MOCK_NOM@|${MOCK_CHEMIN##*/}|g" -e "s|@ISO@|$ISOLATION|g" -e "s|@IMAGE_DIGEST@|$id|g" \
    <<<"$SONDE_M3" | dans "$p" "m3-build$n"
  kubectl exec -n builds "$p" -- sh -c "for f in $b/mock.out $b/res/root.log $b/res/build.log $b/res/installed_pkgs.log; do
      [ -e \"\$f\" ] && { echo \"### \$f\"; cat \"\$f\"; }; done; true" </dev/null \
    | sed '/jeton\|token/I c\[ligne masquée : motif jeton|token]' > "$R/$PREFIXE-m3_build$n-mock.log" || echo "journaux de mock : code non nul"
  echo "journaux de mock : $(wc -l < "$R/$PREFIXE-m3_build$n-mock.log") lignes, resultats/$PREFIXE-m3_build$n-mock.log"
  rm -rf -- "${o:?}/build-$n" && mkdir -p "$o/build-$n"
  kubectl exec -n builds "$p" -- sh -c "cd $b/res && tar -cf - ./*.rpm" </dev/null | tar -xf - -C "$o/build-$n" || echo "rapatriement des rpm : code non nul"
  pod_retirer "$p"
  attendu "code de mock --hermetic-build" "$(champ "m3-build$n" 'mock --hermetic-build' | cut -d ' ' -f1-2)" "rc 0"
  for f in "$o/build-$n"/*.rpm; do [ -e "$f" ] || continue; z=$((z + 1)); x=$(sha256sum < "$f" | cut -c1-64)
    attendu "rpm rapatrié ${f##*/}, sha256 $x, lignes égales dans la sonde" "$(grep -c -F "rpm : ${f##*/} sha256 $x ;" "$T/m3-build$n.log")" 1
  done
  attendu "rpm rapatriés (src.rpm et binaire)" "$z" 2
}
etape_m3_build1() { m3_build 1; }
etape_m3_build2() { m3_build 2; }

ECARTS_M3=0
mesure_m3() { if [ "$2" = "$3" ]; then echo "OK   $1 : $2"; else echo "ÉCART $1 : $2 (attendu : $3)"; ECARTS_M3=$((ECARTS_M3 + 1)); fi; }

etape_m3_comparaison() { # hôte seul, sans réseau ; critère de M3 compté en écarts (code 1 s'il y en a un) ; provenance relevée à part
  local o=$T/m3 n v f
  for n in 1 2; do [ -s "$T/m3-build$n.log" ] && [ -s "$T/m3-temoins$n.log" ] && [ -d "$o/build-$n" ] || { echo "KO   lancer d'abord l'étape m3_build$n" >&2; exit 1; }; done
  v=$o/restauree-1/verrou.json
  attendu "verrou de référence (fermeture restaurée 1), sha256" "$(sha256sum < "$v" | cut -c1-64)" "$VERROU_DERIVEE_SHA"
  jq -r '.buildroot.rpms[] | "paquet \(.name) \(.version) \(.release) \(.arch) \(.sigmd5)"' "$v" | sort > "$o/verrou.paquets"
  for n in 1 2; do
    (cd "$o/build-$n" && for f in *.rpm; do [ -e "$f" ] || continue; echo "$f $(sha256sum < "$f" | cut -c1-64)"; done) > "$o/rpm-$n.txt"
    sed "s/^/build $n : /" "$o/rpm-$n.txt"
    sed -n 's/^rpm : \([^ ]*\) sha256 [0-9a-f]* ; NEVRA \([^ ]*\) ;.*/\1 \2/p' "$T/m3-build$n.log" > "$o/nevra-$n.txt"
    grep '^paquet ' "$T/m3-build$n.log" | sort > "$o/paquets-$n.txt" || true
  done
  echo "## critère de M3 (build 1 contre build 2)"
  mesure_m3 "fichiers rpm par build" "$(wc -l < "$o/rpm-1.txt") $(wc -l < "$o/rpm-2.txt")" "2 2"
  mesure_m3 "lignes NEVRA lues par build" "$(wc -l < "$o/nevra-1.txt") $(wc -l < "$o/nevra-2.txt")" "2 2"
  mesure_m3 "rpm et src.rpm (nom et sha256), build 2 contre build 1" "$(paste -sd ' ' "$o/rpm-2.txt")" "$(paste -sd ' ' "$o/rpm-1.txt")"
  mesure_m3 "NEVRA, build 2 contre build 1" "$(paste -sd ' ' "$o/nevra-2.txt")" "$(paste -sd ' ' "$o/nevra-1.txt")"
  if [ "$(paste -sd ' ' "$o/rpm-1.txt")" != "$(paste -sd ' ' "$o/rpm-2.txt")" ]; then
    echo "     diffoscope à demander au propriétaire (installation) ; rpm gardés sous \$T/m3/build-1 et \$T/m3/build-2"; fi
  echo "## relevés à part (sans effet sur le code)"
  for f in "$RPM_HERMETIQUE" "$SRPM_HERMETIQUE"; do
    echo "relevé : sha256 ${f:0:12}… d'hermetique (17/11, 16:20 UTC) retrouvé dans le build 1 : $(grep -c -F " $f" "$o/rpm-1.txt" || true) fois ; build 2 : $(grep -c -F " $f" "$o/rpm-2.txt" || true) fois"
  done
  for n in 1 2; do
    echo "relevé, build $n : paquets du buildroot (rpm --root) $(wc -l < "$o/paquets-$n.txt"), verrou $(wc -l < "$o/verrou.paquets") ; lignes d'écart (nom, version, release, arch, sigmd5) : $(diff "$o/paquets-$n.txt" "$o/verrou.paquets" | grep -c '^[<>]' || true)"
    diff "$o/paquets-$n.txt" "$o/verrou.paquets" | grep '^[<>]' | head -n 10 | sed 's/^/     /' || true
    echo "relevé, build $n : lignes http(s):// (sortie, root.log, build.log) : $(for f in mock.out root.log build.log; do champ "m3-build$n" "lignes http ou https de $f"; done | paste -sd ' ')"
    grep -E 'https?://' "$R/$PREFIXE-m3_build$n-mock.log" | head -n 10 | cut -c1-200 | sed 's/^/     /' || true
    echo "relevé, build $n : mock de la fermeture : $(champ "m3-build$n" "mock de la fermeture") ; mock de l'image : $(champ "m3-build$n" "mock de l image") ; $([ -n "$(champ "m3-build$n" "mock de la fermeture")" ] && [ "$(champ "m3-build$n" "mock de la fermeture")" = "$(champ "m3-build$n" "mock de l image")" ] && echo égaux || echo 'différents ou illisibles')"
    grep -E '^témoin ' "$T/m3-temoins$n.log" | sed 's/^/     /' || true
    grep -E '^(installed_pkgs.log|mock --hermetic-build|lignes « )' "$T/m3-build$n.log" | sed 's/^/     /'
  done
  echo "écarts du critère : $ECARTS_M3"
  [ "$ECARTS_M3" = 0 ]
}

lancer "$PREFIXE" "05 S1" "$@"
