# Brique 03, F3 : tests de la règle porte.fermeture_plateforme (D6), lancés sur l'hôte par ec opa test avec la bibliothèque
# conforma/policy v1.0.28 et la liste revue (politique/porte/taches.yml) : bascule.sh regle (brique 03), puis s4d2.sh regle
# (brique 06, S4d2a : voie deb, tests en fin de fichier). Hors de la ConfigMap
# porte (cm_porte n'en monte que porte.rego). ec.sigstore.verify_attestation est remplacé par with : l'hôte ne résout pas
# sc-stockage.poc.test. Les fixtures reprennent la forme des provenances réelles de Chains (prov.json de construction.sh
# provenance et de prefetch.sh provenance) : TaskRuns en contenu base64 des entrées pipelineTask, résultats dans status.results.
package porte_test

import rego.v1

import data.porte

_reg := "sc-stockage.poc.test:5000"

_git := "https://sc-stockage.poc.test:3000/workspace/sample-app.git"

_f_plateforme := "sha256:74c265e703fb1ab823b64ac7d62c31c73b5e426895a15d54c57670bdfbffbcdd"

_f_hote := "sha256:0ab5a50767bee2e430cdd2db6b4d61580629f89fd48fb352cd1a2a545ee56048"

# Digests de la liste revue (taches.yml)
_prefetch := "sha256:5e7e5662e6e9bdc306e30b41300f1253e52c3cc5f5323d61380d4d265111cd0c"

_publier_f := "sha256:7fa92ad3e4adb0d4b9bc4209ee04096d476dee5ffa173fc08b9cac0614e2b135"

_preparer := "sha256:2070d601ae3c8df5f96500a3b05b1bdd8fb4441134cca31d20982a3fa098ebe4"

_construire := "sha256:403ccbd82c534e5611a8fcabf01d4fcd93731e945d50345d94f1fe6d58392d63"

_publier_i := "sha256:d21931f3807b4306a55a20488c9c6db1ef33613fa3143207f95fd7428c16b36b"

_essai := "sha256:836cd080991d54ef49c86f5ae8c61421c4fddf615e2e981049c4febb6cea5849"

_autre := "sha256:1111111111111111111111111111111111111111111111111111111111111111"

_opts := {"public_key": "-----BEGIN PUBLIC KEY-----\n(clé de Chains)\n-----END PUBLIC KEY-----\n", "ignore_rekor": true}

_tr(tache, digest, resultats) := {
	"metadata": {"labels": {"tekton.dev/task": tache}},
	"spec": {"taskRef": {"resolver": "bundles", "params": [
		{"name": "bundle", "value": sprintf("%s/tekton/tasks/%s@%s", [_reg, tache, digest])},
		{"name": "name", "value": tache},
		{"name": "kind", "value": "task"},
	]}},
	"status": {"results": resultats},
}

_dep(tr) := {
	"name": "pipelineTask",
	"uri": split(tr.spec.taskRef.params[0].value, "@")[0],
	"digest": {"sha256": substring(split(tr.spec.taskRef.params[0].value, "@")[1], 7, -1)},
	"content": base64.encode(json.marshal(tr)),
}

_prov(sujet, digest, deps, fin) := {"statement": {
	"_type": "https://in-toto.io/Statement/v1",
	"subject": [{"name": sujet, "digest": {"sha256": substring(digest, 7, -1)}}],
	"predicateType": "https://slsa.dev/provenance/v1",
	"predicate": {
		"buildDefinition": {
			"buildType": "https://tekton.dev/chains/v2/slsa-tekton",
			"externalParameters": {"runSpec": {"pipelineRef": {"resolver": "bundles"}}},
			"resolvedDependencies": deps,
		},
		"runDetails": {
			"builder": {"id": "https://supply-chain.example/builders/tekton-chains@v1"},
			"metadata": {"finishedOn": fin},
		},
	},
}}

_r(nom, valeur) := {"name": nom, "type": "string", "value": valeur}

_preparation(uri, digest) := _tr("preparer-entrees", _preparer, [
	_r("CHAINS-GIT_URL", _git),
	{"name": "FERMETURE_ARTIFACT_INPUTS", "type": "object", "value": {"uri": uri, "digest": digest}},
])

# Provenance de construction de sample-app (dernière provenance de PipelineRun jugée)
_construction(uri, digest, fin) := _prov(sprintf("%s/builds/sample-app", [_reg]), _f_hote, [
	_dep(_preparation(uri, digest)),
	_dep(_tr("construire-image", _construire, [_r("DIGEST_CONSTRUIT", "sha256:3a7c")])),
	_dep(_tr("publier-image", _publier_i, [_r("IMAGE_URL", "x"), _r("IMAGE_DIGEST", "y")])),
], fin)

_uri_plateforme := sprintf("oci://%s/builds/fermetures/sample-app", [_reg])

_depot_plateforme := sprintf("%s/builds/fermetures/sample-app", [_reg])

# Provenance de la pipeline de prefetch (prefetch.sh provenance)
_prefetch_prov(depot, digest, taches) := _prov(depot, digest, [_dep(t) | some t in taches], "2026-11-03T18:24:53Z")

_taches_prefetch(depot, digest, git) := [
	_tr("prefetch-gomod", _prefetch, [_r("CHAINS-GIT_URL", git), _r("CHAINS-GIT_COMMIT", "6391fd437f26696847041be3226bbbf633f55a2f")]),
	_tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", depot), _r("IMAGE_DIGEST", digest)]),
]

_bonne := _prefetch_prov(_depot_plateforme, _f_plateforme, _taches_prefetch(_depot_plateforme, _f_plateforme, _git))

_regles := {"allowed_builder_ids": ["https://supply-chain.example/builders/tekton-chains@v1"]}

# Simulations de ec.sigstore.verify_attestation. Par fonction : n'accepte que la clé et les options transmises par ec, et la seule
# fermeture de la plateforme. Par valeur : même réponse quelle que soit la référence.
_verif_bonne(ref, opts) := _ok([_bonne]) if {
	opts.public_key != ""
	opts.ignore_rekor == true
	ref == sprintf("%s@%s", [_depot_plateforme, _f_plateforme])
} else := {"success": false, "errors": ["no matching attestations"], "attestations": []}

_ok(statements) := {"success": true, "errors": [], "attestations": statements}

_avec_fonction(attestations, opts) := {d |
	some d in porte.deny with input.attestations as attestations
		with data.rule_data__configuration__ as _regles
		with data.config.default_sigstore_opts as opts
		with ec.sigstore.verify_attestation as _verif_bonne
}

_avec_valeur(attestations, valeur) := {d |
	some d in porte.deny with input.attestations as attestations
		with data.rule_data__configuration__ as _regles
		with data.config.default_sigstore_opts as _opts
		with ec.sigstore.verify_attestation as valeur
}

_refus(verdicts) if {
	some d in verdicts
	d.code == "porte.fermeture_plateforme"
}

_message(verdicts, motif) if {
	some d in verdicts
	d.code == "porte.fermeture_plateforme"
	contains(d.msg, motif)
}

_nouvelle := _construction(_uri_plateforme, _f_plateforme, "2026-11-04T10:00:00Z")

_uri_hote := sprintf("oci://%s/entrees/sample-app/fermeture", [_reg])

test_fermeture_de_la_plateforme_acceptee if {
	not _refus(_avec_fonction([_nouvelle], _opts))
}

test_fermeture_de_l_hote_refusee if {
	v := _avec_fonction([_construction(_uri_hote, _f_hote, "2026-11-02T13:59:30Z")], _opts)
	_message(v, "no matching attestations")
}

test_cle_absente_refusee if {
	_refus(_avec_fonction([_nouvelle], {"public_key": "", "ignore_rekor": true}))
}

test_sans_resultat_fermeture_refusee if {
	p := _tr("preparer-entrees", _preparer, [_r("CHAINS-GIT_URL", _git)])
	a := [_prov(sprintf("%s/builds/sample-app", [_reg]), _f_hote, [_dep(p)], "2026-11-04T10:00:00Z")]
	_message(_avec_fonction(a, _opts), "sans fermeture")
}

test_fermeture_sans_digest_refusee if {
	_message(_avec_fonction([_construction(_uri_plateforme, "latest", "2026-11-04T10:00:00Z")], _opts), "sans fermeture")
}

test_attestation_de_taskrun_seule_refusee if {
	tr := _tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", _depot_plateforme), _r("IMAGE_DIGEST", _f_plateforme)])
	seule := _prov(_depot_plateforme, _f_plateforme, [{"name": "task", "uri": "x", "content": base64.encode(json.marshal(tr))}], "2026-11-03T18:24:53Z")
	_message(_avec_valeur([_nouvelle], _ok([seule])), "1 provenance(s) vérifiée(s)")
}

test_tache_en_trop_refusee if {
	t := array.concat(_taches_prefetch(_depot_plateforme, _f_plateforme, _git), [_tr("publier-essai", _essai, [_r("X", "y")])])
	_refus(_avec_valeur([_nouvelle], _ok([_prefetch_prov(_depot_plateforme, _f_plateforme, t)])))
}

test_tache_hors_liste_revue_refusee if {
	t := [
		_tr("prefetch-gomod", _autre, [_r("CHAINS-GIT_URL", _git)]),
		_tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", _depot_plateforme), _r("IMAGE_DIGEST", _f_plateforme)]),
	]
	_refus(_avec_valeur([_nouvelle], _ok([_prefetch_prov(_depot_plateforme, _f_plateforme, t)])))
}

test_digest_publie_different_refuse if {
	t := _taches_prefetch(_depot_plateforme, _autre, _git)
	_refus(_avec_valeur([_nouvelle], _ok([_prefetch_prov(_depot_plateforme, _f_plateforme, t)])))
}

test_autre_depot_forgejo_refuse if {
	t := _taches_prefetch(_depot_plateforme, _f_plateforme, "https://sc-stockage.poc.test:3000/workspace/autre.git")
	_refus(_avec_valeur([_nouvelle], _ok([_prefetch_prov(_depot_plateforme, _f_plateforme, t)])))
}

test_builder_inconnu_refuse if {
	p := json.patch(_bonne, [{"op": "replace", "path": "/statement/predicate/runDetails/builder/id", "value": "https://tekton.dev/chains/v2"}])
	_refus(_avec_valeur([_nouvelle], _ok([p])))
}

test_sujet_autre_nom_refuse if {
	p := json.patch(_bonne, [{"op": "replace", "path": "/statement/subject/0/name", "value": sprintf("%s/builds/fermetures/autre", [_reg])}])
	_refus(_avec_valeur([_nouvelle], _ok([p])))
}

test_sujet_autre_digest_refuse if {
	p := json.patch(_bonne, [{"op": "replace", "path": "/statement/subject/0/digest/sha256", "value": substring(_autre, 7, -1)}])
	_refus(_avec_valeur([_nouvelle], _ok([p])))
}

test_image_url_autre_refuse if {
	t := [
		_tr("prefetch-gomod", _prefetch, [_r("CHAINS-GIT_URL", _git)]),
		_tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", sprintf("%s/builds/fermetures/autre", [_reg])), _r("IMAGE_DIGEST", _f_plateforme)]),
	]
	_refus(_avec_valeur([_nouvelle], _ok([_prefetch_prov(_depot_plateforme, _f_plateforme, t)])))
}

test_tache_en_double_refusee if {
	t := array.concat(_taches_prefetch(_depot_plateforme, _f_plateforme, _git), [_tr("prefetch-gomod", _prefetch, [_r("CHAINS-GIT_URL", "autre")])])
	_refus(_avec_valeur([_nouvelle], _ok([_prefetch_prov(_depot_plateforme, _f_plateforme, t)])))
}

test_build_type_autre_refuse if {
	p := json.patch(_bonne, [{"op": "replace", "path": "/statement/predicate/buildDefinition/buildType", "value": "https://tekton.dev/chains/v2/slsa"}])
	_refus(_avec_valeur([_nouvelle], _ok([p])))
}

test_predicate_type_autre_refuse if {
	p := json.patch(_bonne, [{"op": "replace", "path": "/statement/predicateType", "value": "https://slsa.dev/provenance/v0.2"}])
	_refus(_avec_valeur([_nouvelle], _ok([p])))
}

test_depot_hors_builds_fermetures_refuse if {
	d := sprintf("%s/entrees/sample-app/fermeture", [_reg])
	p := _prefetch_prov(d, _f_plateforme, _taches_prefetch(d, _f_plateforme, _git))
	_refus(_avec_valeur([_construction(sprintf("oci://%s", [d]), _f_plateforme, "2026-11-04T10:00:00Z")], _ok([p])))
}

test_une_bonne_parmi_plusieurs_acceptee if {
	t := array.concat(_taches_prefetch(_depot_plateforme, _f_plateforme, _git), [_tr("publier-essai", _essai, [_r("X", "y")])])
	not _refus(_avec_valeur([_nouvelle], _ok([_prefetch_prov(_depot_plateforme, _f_plateforme, t), _bonne])))
}

test_seule_la_derniere_provenance_jugee if {
	ancienne := _construction(_uri_hote, _f_hote, "2026-11-02T13:59:30Z")
	not _refus(_avec_fonction([ancienne, _nouvelle], _opts))
	retour := _construction(_uri_hote, _f_hote, "2026-11-05T10:00:00Z")
	_refus(_avec_fonction([_nouvelle, retour], _opts))
}

test_image_d_essai_hors_regle if {
	a := [_prov(sprintf("%s/builds/essai-porte", [_reg]), _f_hote, [_dep(_tr("publier-essai", _essai, [_r("IMAGE_URL", "x")]))], "2026-11-04T10:00:00Z")]
	not _refus(_avec_fonction(a, _opts))
}

# Brique 06, S4d2a (décision du propriétaire du 11/11/2026, 20:08:42 UTC) : voie deb. Digests et noms des résultats repris des
# provenances réelles de S4d1 (PipelineRun s4d-deb-1) et de S4b (fermetures deb et applicative) ; s4d2.sh reel évalue les mêmes
# règles sur ces provenances elles-mêmes.
_preparer_deb := "sha256:588617b8382513c3aa5b2d79de8f45324ab6cfdc2b6009664ab0a50e1123c492"

_construire_deb := "sha256:3726ff0b116cb6f4e13a44de69ca7a9be84061f4f70585783932f2685c79d10a"

_prefetch_deb := "sha256:4dac0609a5d1d980501f4f08cdeb0916912b4f3accd9cf56fea456a399e793a5"

_prefetch_v2 := "sha256:170bef538a89e585326a64618a443460e88d663b2d3a761b535daf531bafa00f"

_fd := "sha256:bb7599a2e1cde30770fdb4405a5f9cce94de5ea5b12c358e512dfbe7d5b9f290"

_fs := "sha256:50dc73f72d04be852a04f5de86683f4afee9ffdc78144124cbfbb7dbf454bd21"

_depot_fd := sprintf("%s/builds/fermetures/sample-app-deb", [_reg])

_depot_fs := sprintf("%s/builds/fermetures/sample-app-sources", [_reg])

_o(nom, uri, digest) := {"name": nom, "type": "object", "value": {"uri": uri, "digest": digest}}

_prep_deb(resultats) := _tr("preparer-deb", _preparer_deb, array.concat([
	_r("CHAINS-GIT_COMMIT", "6391fd437f26696847041be3226bbbf633f55a2f"),
	_r("CHAINS-GIT_URL", _git),
	_o("PACKAGING_ARTIFACT_INPUTS", sprintf("oci://%s/entrees/sample-app/packaging-deb", [_reg]),
		"sha256:c1719b133236f49c7e2492f4b608a8dc421bf812d7f7e438d879a871f61c2e51"),
], resultats))

_resultats_deb := [
	_o("FERMETURE_DEB_ARTIFACT_INPUTS", sprintf("oci://%s", [_depot_fd]), _fd),
	_o("FERMETURE_SOURCES_ARTIFACT_INPUTS", sprintf("oci://%s", [_depot_fs]), _fs),
]

# TaskRun de construction avec le runtimeClassName de sa spec signée ("" : absent)
_constr(tache, digest, rc) := object.union(_tr(tache, digest, [_r("DIGEST_CONSTRUIT", "sha256:0399")]),
	{"spec": {"podTemplate": {"runtimeClassName": rc}}})

_deb(taches) := _prov(sprintf("%s/builds/sample-app-deb", [_reg]),
	"sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e", [_dep(t) | some t in taches],
	"2026-11-11T19:53:56Z")

_publier_deb := _tr("publier-image", _publier_i, [
	_r("IMAGE_DIGEST", "sha256:039949f947f218b115829aad487da7fa62a9b5c0a4c7410d107dc5d2a698492e"),
	_r("IMAGE_URL", sprintf("%s/builds/sample-app-deb", [_reg])),
])

_deb_bon := _deb([_prep_deb(_resultats_deb), _constr("construire-deb", _construire_deb, "kata"), _publier_deb])

# Provenances des deux pipelines de fermeture de S4b
_prov_fd := _prefetch_prov(_depot_fd, _fd, [
	_tr("prefetch-deb", _prefetch_deb, [_o("INSTANTANE_ARTIFACT_INPUTS",
		"http://snapshot.debian.org/archive/debian/20261104T000000Z/dists/trixie/InRelease",
		"sha256:0584fba32e13e0ab8285fb16c27adea1ec03a73669c18702821094fd6ca86675")]),
	_tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", _depot_fd), _r("IMAGE_DIGEST", _fd)]),
])

_prov_fs := _prefetch_prov(_depot_fs, _fs, [
	_tr("prefetch-gomod", _prefetch_v2, [_r("CHAINS-GIT_URL", _git), _r("CHAINS-GIT_COMMIT", "6391fd437f26696847041be3226bbbf633f55a2f")]),
	_tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", _depot_fs), _r("IMAGE_DIGEST", _fs)]),
])

_ref_fd := sprintf("%s@%s", [_depot_fd, _fd])

_ref_fs := sprintf("%s@%s", [_depot_fs, _fs])

# verify_attestation simulée : provenance de chaque fermeture lue dans data.essai_s4d2.fermetures (posée par with), clé et
# options de ec exigées
_fermetures_bonnes := {_ref_fd: _prov_fd, _ref_fs: _prov_fs}

_verif_deb(ref, opts) := _ok([data.essai_s4d2.fermetures[ref]]) if {
	opts.public_key != ""
	opts.ignore_rekor == true
	data.essai_s4d2.fermetures[ref]
} else := {"success": false, "errors": ["no matching attestations"], "attestations": []}

_juge(attestations, fermetures, opts) := {d |
	some d in porte.deny with input.attestations as attestations
		with data.rule_data__configuration__ as _regles
		with data.config.default_sigstore_opts as opts
		with data.essai_s4d2.fermetures as fermetures
		with ec.sigstore.verify_attestation as _verif_deb
}

_juge_deb(attestations) := _juge(attestations, _fermetures_bonnes, _opts)

_codes(verdicts) := {d.code | some d in verdicts}

_msg(verdicts, code, motif) if {
	some d in verdicts
	d.code == code
	contains(d.msg, motif)
}

test_deb_accepte if {
	v := _juge_deb([_deb_bon])
	not "porte.fermeture_plateforme" in _codes(v)
	not "porte.construction_kata" in _codes(v)
	not "porte.preparation_appariee" in _codes(v)
}

test_deb_hors_kata_refuse if {
	a := [_deb([_prep_deb(_resultats_deb), _constr("construire-deb", _construire_deb, ""), _publier_deb])]
	_msg(_juge_deb(a), "porte.construction_kata", "kata exigé")
}

test_deb_runc_refuse if {
	a := [_deb([_prep_deb(_resultats_deb), _constr("construire-deb", _construire_deb, "runc"), _publier_deb])]
	"porte.construction_kata" in _codes(_juge_deb(a))
}

# Bundle de construire-deb chargé sous un autre nom : reste une construction
test_deb_bundle_sous_autre_nom_hors_kata_refuse if {
	c := json.patch(_constr("construire-deb", _construire_deb, ""), [{"op": "replace", "path": "/spec/taskRef/params/1/value", "value": "autre"}])
	"porte.construction_kata" in _codes(_juge_deb([_deb([_prep_deb(_resultats_deb), c, _publier_deb])]))
}

# Tâche nommée construire-deb, bundle d'un autre dépôt : reste une construction
test_deb_nom_seul_hors_kata_refuse if {
	c := json.patch(_constr("construire-deb", _construire_deb, ""), [{"op": "replace", "path": "/spec/taskRef/params/0/value",
		"value": sprintf("%s/tekton/tasks/autre@%s", [_reg, _construire_deb])}])
	"porte.construction_kata" in _codes(_juge_deb([_deb([_prep_deb(_resultats_deb), c, _publier_deb])]))
}

# Voie image : ni appariement (hors périmètre de S4d2a) ni refus de Kata quand construire-image tourne sous Kata
test_image_hors_appariement if {
	a := [_prov(sprintf("%s/builds/sample-app", [_reg]), _f_hote, [
		_dep(_preparation(_uri_plateforme, _f_plateforme)),
		_dep(_constr("construire-image", _construire, "kata")),
	], "2026-11-04T10:00:00Z")]
	v := _avec_fonction(a, _opts)
	not "porte.preparation_appariee" in _codes(v)
	not "porte.construction_kata" in _codes(v)
	not "porte.fermeture_plateforme" in _codes(v)
}

test_image_hors_kata_refusee if {
	a := [_prov(sprintf("%s/builds/sample-app", [_reg]), _f_hote, [
		_dep(_preparation(_uri_plateforme, _f_plateforme)),
		_dep(_constr("construire-image", _construire, "")),
	], "2026-11-04T10:00:00Z")]
	"porte.construction_kata" in _codes(_avec_fonction(a, _opts))
}

test_deb_sans_fermeture_deb_refuse if {
	a := [_deb([_prep_deb([_resultats_deb[1]]), _constr("construire-deb", _construire_deb, "kata"), _publier_deb])]
	_msg(_juge_deb(a), "porte.fermeture_plateforme", "FERMETURE_DEB_ARTIFACT_INPUTS")
}

test_deb_sans_fermeture_sources_refuse if {
	a := [_deb([_prep_deb([_resultats_deb[0]]), _constr("construire-deb", _construire_deb, "kata"), _publier_deb])]
	_msg(_juge_deb(a), "porte.fermeture_plateforme", "FERMETURE_SOURCES_ARTIFACT_INPUTS")
}

test_deb_fermeture_deb_sans_digest_refusee if {
	r := [_o("FERMETURE_DEB_ARTIFACT_INPUTS", sprintf("oci://%s", [_depot_fd]), "latest"), _resultats_deb[1]]
	a := [_deb([_prep_deb(r), _constr("construire-deb", _construire_deb, "kata"), _publier_deb])]
	_msg(_juge_deb(a), "porte.fermeture_plateforme", "FERMETURE_DEB_ARTIFACT_INPUTS")
}

# Fermetures permutées : chaque digest présenté sous le résultat de l'autre forme
test_deb_fermetures_permutees_refusees if {
	r := [
		_o("FERMETURE_DEB_ARTIFACT_INPUTS", sprintf("oci://%s", [_depot_fs]), _fs),
		_o("FERMETURE_SOURCES_ARTIFACT_INPUTS", sprintf("oci://%s", [_depot_fd]), _fd),
	]
	v := _juge_deb([_deb([_prep_deb(r), _constr("construire-deb", _construire_deb, "kata"), _publier_deb])])
	_msg(v, "porte.fermeture_plateforme", "pipeline de prefetch deb")
	_msg(v, "porte.fermeture_plateforme", "pipeline de prefetch gomod")
}

# Fermeture applicative présentée comme fermeture deb (même digest sous les deux résultats)
test_deb_fermeture_gomod_comme_deb_refusee if {
	r := [_o("FERMETURE_DEB_ARTIFACT_INPUTS", sprintf("oci://%s", [_depot_fs]), _fs), _resultats_deb[1]]
	v := _juge_deb([_deb([_prep_deb(r), _constr("construire-deb", _construire_deb, "kata"), _publier_deb])])
	_msg(v, "porte.fermeture_plateforme", "pipeline de prefetch deb")
}

test_deb_sans_preparer_deb_refuse if {
	v := _juge_deb([_deb([_constr("construire-deb", _construire_deb, "kata"), _publier_deb])])
	_msg(v, "porte.preparation_appariee", "construire-deb sans preparer-deb")
	"porte.fermeture_plateforme" in _codes(v)
}

# construire-deb préparée par preparer-entrees (fermeture gomod prouvée) : refusée par l'appariement seul
test_deb_prepare_par_preparer_entrees_refuse if {
	a := [_deb([_preparation(_uri_plateforme, _f_plateforme), _constr("construire-deb", _construire_deb, "kata"), _publier_deb])]
	v := _avec_fonction(a, _opts)
	"porte.preparation_appariee" in _codes(v)
	not "porte.fermeture_plateforme" in _codes(v)
}

test_deb_prefetch_deb_hors_liste_refuse if {
	p := _prefetch_prov(_depot_fd, _fd, [
		_tr("prefetch-deb", _autre, []),
		_tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", _depot_fd), _r("IMAGE_DIGEST", _fd)]),
	])
	v := _juge([_deb_bon], object.union(_fermetures_bonnes, {_ref_fd: p}), _opts)
	_msg(v, "porte.fermeture_plateforme", "pipeline de prefetch deb")
}

test_deb_digest_publie_different_refuse if {
	p := _prefetch_prov(_depot_fd, _fd, [
		_tr("prefetch-deb", _prefetch_deb, []),
		_tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", _depot_fd), _r("IMAGE_DIGEST", _autre)]),
	])
	v := _juge([_deb_bon], object.union(_fermetures_bonnes, {_ref_fd: p}), _opts)
	_msg(v, "porte.fermeture_plateforme", "pipeline de prefetch deb")
}

test_deb_fermeture_sources_autre_depot_forgejo_refusee if {
	p := _prefetch_prov(_depot_fs, _fs, [
		_tr("prefetch-gomod", _prefetch_v2, [_r("CHAINS-GIT_URL", "https://sc-stockage.poc.test:3000/workspace/autre.git")]),
		_tr("publier-fermeture", _publier_f, [_r("IMAGE_URL", _depot_fs), _r("IMAGE_DIGEST", _fs)]),
	])
	v := _juge([_deb_bon], object.union(_fermetures_bonnes, {_ref_fs: p}), _opts)
	_msg(v, "porte.fermeture_plateforme", "pipeline de prefetch gomod")
}

test_deb_cle_absente_refusee if {
	v := _juge([_deb_bon], _fermetures_bonnes, {"public_key": "", "ignore_rekor": true})
	"porte.fermeture_plateforme" in _codes(v)
}
