#!/usr/bin/env bash
# Essai hors réseau de m2.sh releve4 (12/11/2026, avant tout accord) : curl simulé (honore -o et -w), commun.sh remplacé par un
# lancer() minimal, HOME isolé. Cas : 1. options trouvées ; 2. option absente, témoin présent ; 3. HTTP 404 sur copy.go ;
# 4. témoin absent (mauvais fichier).
# Corrigé le 12/11/2026 à partir de 16:20:56 UTC, après le premier passage : options de skopeo lues dans utils.go (sharedCopyFlags) ;
# cas 3 : HTTP 404 sur utils.go ; cas 4 : témoin absent de utils.go ; cas 5 : copy.go sans appel à sharedCopyFlags().
# Non couvert : réponses réelles de raw.githubusercontent.com (redirections, délais, DNS), contenu réel des fichiers amont.
set -u
D=$1; H=$2   # D : racine du dépôt ; H : dossier d'essai (vidé)
rm -rf -- "${H:?}"; mkdir -p "$H/bin" "$H/home" "$H/b/resultats"
cat > "$H/bin/curl" <<'EOF2'
#!/usr/bin/env bash
o=/dev/stdout; w=; u=${*: -1}
while [ $# -gt 0 ]; do case $1 in -o) o=$2; shift ;; -w) w=$2; shift ;; esac; shift; done
c=200
case "$CAS:$u" in
  *:*/cmd_parser.c)
    b='  { "checksum", '"'s'"', 0, G_OPTION_ARG_STRING, &(_cmd_options.checksum), "Choose the checksum type", "CHECKSUM_TYPE" },'
    [ "$CAS" = absente ] || b="$b"$'\n''  { "compatibility", 0, 0, G_OPTION_ARG_NONE, &(_cmd_options.compatibility), "Faux texte d essai", NULL },' ;;
  *:*/createrepo_c.c) b='    if (cmd_options->compatibility) { /* faux */ }' ;;
  appel:*/copy.go) b='	copyFlags, copyOpts := autreChose()' ;;
  *:*/copy.go) b='	copyFlags, copyOpts := sharedCopyFlags()' ;;
  404:*/utils.go) c=404; b='404: Not Found "preserve-digests" "remove-signatures" func sharedCopyFlags(' ;;
  temoin:*/utils.go) b='func sharedCopyFlags() {'$'\n''fs.BoolVar(&opts.preserveDigests, "preserve-digests", false, "faux")' ;;
  *:*/utils.go) b='func sharedCopyFlags() {'$'\n''fs.BoolVar(&opts.removeSignatures, "remove-signatures", false, "faux")'$'\n''fs.BoolVar(&opts.preserveDigests, "preserve-digests", false, "faux")' ;;
  *) c=500; b=inattendu ;;
esac
printf '%s\n' "$b" > "$o"
[ -n "$w" ] && printf '%s' "$c"
echo "FAUX curl $u" >&2
EOF2
chmod +x "$H/bin/curl"
printf 'R=%s\nlancer() { etape_$3; }\n' "$H/b/resultats" > "$H/commun.sh"
sed -e "s#^\. \"\$here/../08-trust-plane/commun.sh\"\$#. $H/commun.sh#" "$D/poc/bricks/05-rpm-mock/m2.sh" > "$H/b/m2.sh"
grep -c "^\. $H/commun.sh\$" "$H/b/m2.sh" | sed 's/^/source remplacée : /'
for c in trouve absente 404 temoin appel; do
  echo "== cas $c"
  CAS=$c HOME=$H/home PATH=$H/bin:$PATH bash "$H/b/m2.sh" releve4 2>&1; echo "code $?"
  test -e "$H/home/.cache/supply-chain-poc/05/m2/releve4" && echo "dossier releve4 resté (attendu après un KO)" || echo "dossier releve4 effacé"
done
rm -rf -- "${H:?}"
