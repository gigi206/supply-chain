#!/busybox/sh
set -eu
for r in "$FERMETURE_RPM" "$FERMETURE_SOURCES" "$PACKAGING"; do
  case $r in sc-stockage.poc.test:5000/*@sha256:*) ;; *) echo "référence hors de Zot ou sans digest : $r" >&2; exit 1 ;; esac
done
export HOME=/tmp
e=/workspace/sortie/entrees
oras pull --no-tty --ca-file /etc/ca-poc/ca.crt -o "$e/fermeture" "$FERMETURE_RPM" > /dev/null
oras pull --no-tty --ca-file /etc/ca-poc/ca.crt -o "$e/sources" "$FERMETURE_SOURCES" > /dev/null
oras pull --no-tty --ca-file /etc/ca-poc/ca.crt -o "$e/packaging" "$PACKAGING" > /dev/null
echo "fermeture rpm : $(find "$e/fermeture" -type f | wc -l) fichiers ; fermeture applicative : $(find "$e/sources" -type f | wc -l) fichiers ; packaging : $(find "$e/packaging" -type f | wc -l) fichiers"
[ -s "$e/packaging/sample-app.spec" ] && [ -s "$e/packaging/verrou-rpm.json" ] || { echo "spec ou verrou absent de l'artefact de packaging" >&2; exit 1; }
[ "$(find "$e/packaging" -type f | wc -l)" = 2 ] || { echo "artefact de packaging : fichiers en trop" >&2; exit 1; }
[ -d "$e/fermeture/depot/repodata" ] || { echo "fermeture rpm sans depot/repodata" >&2; exit 1; }
[ -z "$(find "$e/fermeture" -mindepth 1 -maxdepth 1 ! -name depot)" ] || { echo "fermeture rpm : autre chose que depot/ à la racine" >&2; exit 1; }
printf '{"uri":"oci://%s","digest":"%s"}' "${FERMETURE_RPM%@*}" "${FERMETURE_RPM#*@}" > /resultats/FERMETURE_RPM_ARTIFACT_INPUTS
printf '{"uri":"oci://%s","digest":"%s"}' "${FERMETURE_SOURCES%@*}" "${FERMETURE_SOURCES#*@}" > /resultats/FERMETURE_SOURCES_ARTIFACT_INPUTS
printf '{"uri":"oci://%s","digest":"%s"}' "${PACKAGING%@*}" "${PACKAGING#*@}" > /resultats/PACKAGING_ARTIFACT_INPUTS

