set -euo pipefail
P=$1; shift
export RESEAU=cilium
eval "$(sed -n '/^adresse_libre() {/,/^}/p' "$P/commun.sh")"
kubectl() { case "$*" in *ciliumendpoints*) echo '{"items":[{"status":{"networking":{"addressing":[{"ipv4":"10.42.1.249"}]}}}]}' ;; *) echo 10.42.1.250 ;; esac; }
set -- "$@"
eval "$(python3 -I - "$P/kata.sh" <<'PY'
import sys
l = open(sys.argv[1]).read().split("\n")
d = next(i for i, x in enumerate(l) if x.startswith("USURPEE="))
f = next(i for i, x in enumerate(l) if i > d and x.startswith("TEMOIN_USURPATION=") )
print("\n".join(l[d:f + 3]))
PY
)"
echo "USURPEE=$USURPEE"
echo "USURPATION : .248 $(grep -c '10\.42\.1\.248' <<< "$USURPATION"), .250 $(grep -c '10\.42\.1\.250' <<< "$USURPATION")"
echo "TEMOIN : .248 $(grep -c '10\.42\.1\.248' <<< "$TEMOIN_USURPATION"), .250 $(grep -c '10\.42\.1\.250' <<< "$TEMOIN_USURPATION")"
