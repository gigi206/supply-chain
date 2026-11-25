#!/usr/bin/env bash
# P9 : codes de refus de toute la porte sur les entrées des cinq tests restés verts avec le nom neuf. Usage (racine du dépôt) : mise exec -- bash <ce fichier>
set -u
cd ~/.cache/supply-chain-poc/chains-v0300/regles
grep -n -A6 -E '^(_refus|_juge_deb|_avec_fonction|_avec_valeur)\(' t/porte_test.rego
for v in ancien neuf; do
  mkdir -p t5-$v
  S=~/Documents/git/github/gigi206/supply-chain/poc/bricks/08-trust-plane/politique/porte/porte_test.rego
  if [ $v = neuf ]; then sed 's|"name": "pipelineTask"|"name": "pipelineTask/x"|' $S > t5-$v/porte_test.rego; else cp $S t5-$v/porte_test.rego; fi
  cat >> t5-$v/porte_test.rego <<'R'

_sonde contains [n, c] if {
	some n, v in {
		"essai_hors_regle": _avec_fonction([_prov(sprintf("%s/builds/essai-porte", [_reg]), _f_hote, [_dep(_tr("publier-essai", _essai, [_r("IMAGE_URL", "x")]))], "2026-11-04T10:00:00Z")], _opts),
		"une_bonne": _avec_valeur([_nouvelle], _ok([_prefetch_prov(_depot_plateforme, _f_plateforme, array.concat(_taches_prefetch(_depot_plateforme, _f_plateforme, _git), [_tr("publier-essai", _essai, [_r("X", "y")])])), _bonne])),
		"hors_appariement": _avec_fonction([_prov(sprintf("%s/builds/sample-app", [_reg]), _f_hote, [_dep(_preparation(_uri_plateforme, _f_plateforme)), _dep(_constr("construire-image", _construire, "kata"))], "2026-11-04T10:00:00Z")], _opts),
		"deb": _juge_deb([_deb_bon]),
		"fermeture": _avec_fonction([_nouvelle], _opts),
	}
	c := _codes(v)
}
R
  echo "## $v"; ec opa eval -f json -d policy -d porte.rego -d taches.yml -d t5-$v/porte_test.rego 'data.porte_test._sonde' | jq -c 'if .errors then .errors else .result[0].expressions[0].value[] end'
done
