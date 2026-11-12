#!/usr/bin/env bash
# Essai hors réseau de sante.sh (12/11/2026, avant tout accord) : gh, curl et tools/health/scorecard.sh simulés, HOME isolé.
# 1. releves, avant (HEAD) et après la mise en fonction de releve_depot : sorties comparées, en-tête daté exclu.
# 2. voie2 : commandes émises (dépôts, dates de début, URL de pub/rocky/9.8), filtrage des listes de fichiers, liste vide
#    signalée (AppStream, Packages/r/ simulé vide).
# Non couvert : réponses réelles de GitHub, de Scorecard et de dl.rockylinux.org (format, pagination, erreurs réseau).
set -u
D=$1; H=$2; AVANT=$3   # D : racine du dépôt ; H : dossier d'essai (vidé) ; AVANT : sante.sh de HEAD
rm -rf -- "${H:?}"; mkdir -p "$H/bin"
cat > "$H/bin/gh" <<'EOF2'
#!/usr/bin/env bash
case "$*" in
  *"/commits?"*) printf 'alice\texemple.org\tUser\nrobot\texemple.org\tBot\n' ;;
  *) echo "FAUX gh $*" ;;
esac
EOF2
cat > "$H/bin/curl" <<'EOF2'
#!/usr/bin/env bash
u=${*: -1}
case "$u" in
  */Packages/c/) printf '<a href="createrepo_c-9.9.8-1.faux.x86_64.rpm">x</a> "createrepo_c-9.9.9-1.faux.x86_64.rpm" "createrepo_c-libs-9.9.9-1.faux.x86_64.rpm" "createrepo_c-devel-9.9.9-1.faux.x86_64.rpm"\n' ;;
  */AppStream/*/Packages/r/) printf '<html>vide</html>\n' ;;
  */Packages/r/) printf '"rpm-9.9.9-1.faux.x86_64.rpm" "rpm-libs-9.9.9-1.faux.x86_64.rpm" "rpm-sign-libs-9.9.9-1.faux.x86_64.rpm" "rpmlint-9.9.9-1.faux.noarch.rpm"\n' ;;
  *commits*) printf '[{"commit":{"author":{"date":"2026-10-30T00:00:00Z","name":"Faux"}}}]\n' ;;
  *) echo '{"archived":false,"default_branch":"r9","updated_at":"2026-10-30T00:00:00Z"}' ;;
esac
echo "FAUX curl $u" >&2
EOF2
chmod +x "$H/bin/gh" "$H/bin/curl"
for v in avant apres; do
  mkdir -p "$H/$v/poc/bricks/05-rpm-mock" "$H/$v/tools/health" "$H/$v/home"
  printf '#!/usr/bin/env bash\necho "FAUX scorecard"; cut -f2 "$1"\n' > "$H/$v/tools/health/scorecard.sh"
  chmod +x "$H/$v/tools/health/scorecard.sh"
done
cp "$AVANT" "$H/avant/poc/bricks/05-rpm-mock/sante.sh"
cp "$D/poc/bricks/05-rpm-mock/sante.sh" "$H/apres/poc/bricks/05-rpm-mock/sante.sh"
echo "== essai 1 : releves avant et après"
for v in avant apres; do
  HOME=$H/$v/home PATH=$H/bin:$PATH bash "$H/$v/poc/bricks/05-rpm-mock/sante.sh" releves >/dev/null 2>&1
  tail -n +2 "$H/$v/poc/bricks/05-rpm-mock/resultats/sante-releves.log" > "$H/$v.log"
done
echo "lignes : $(wc -l < "$H/avant.log") avant, $(wc -l < "$H/apres.log") après"
cmp "$H/avant.log" "$H/apres.log" && echo "OK   releves : sortie identique avant et après"
grep -c 'select(.published_at > "2025-11-05")' "$H/apres.log" | sed 's/^/filtre des avis au 2025-11-05, occurrences : /'
echo "== essai 2 : voie2"
HOME=$H/apres/home PATH=$H/bin:$PATH bash "$H/apres/poc/bricks/05-rpm-mock/sante.sh" voie2 >/dev/null 2>&1
tail -n +2 "$H/apres/poc/bricks/05-rpm-mock/resultats/sante-voie2.log"
rm -rf -- "${H:?}"
