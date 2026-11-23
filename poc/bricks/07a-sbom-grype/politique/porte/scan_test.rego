# Brique 07a, G5 : tests de politique/porte/scan.rego, lancés sur l'hôte par ec opa test (plateforme.sh g5_regles), comme ceux de
# porte_test.rego ; hors de la ConfigMap porte. Heure simulée par with : un test ne doit pas dépendre de la date du jour. Fixture de
# la forme du prédicat réel (resultats/g4-scan-predicat.json).
package scan_test

import rego.v1

import data.scan

_digest := "3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5"

_autre := "1111111111111111111111111111111111111111111111111111111111111111"

_type := "https://supply-chain.example/scan/v1"

# vex_age_max_jours : valeur de test seulement (la politique attend le choix du propriétaire)
_seuils := {"scan_age_max_jours": 7, "base_age_max_jours": 3, "vex_statuts_acceptes": ["not_affected"], "vex_age_max_jours": 30}

_maintenant := time.parse_rfc3339_ns("2026-11-10T12:00:00Z")

_vulns := [{"id": "GHSA-j6qf-3m9c-vwj3", "kev": false, "kevCves": []}]

_kev := [{"id": "GHSA-jfh8-c2jp-5v3q", "kev": true, "kevCves": ["CVE-2021-44228"]}]

_predicat(date, base, vulns, mal) := {
	"malicious": mal,
	"scannedAt": date,
	"scanner": {"db": {"built": base, "schema": "v6.1.10"}, "id": "grype", "version": "0.104.1"},
	"vulnerabilities": vulns,
}

_enonce(digest, p) := {
	"_type": "https://in-toto.io/Statement/v0.1",
	"subject": [{"name": "sample-app", "digest": {"sha256": digest}}],
	"predicateType": _type,
	"predicate": p,
}

_entree(enonces) := {"digest": _digest, "statements": enonces}

_propre := _enonce(_digest, _predicat("2026-11-09T20:40:09.254165787Z", "2026-11-09T06:20:59Z", _vulns, []))

_codes(entree) := {d.code |
	some d in scan.deny with input as entree
		with time.now_ns as _maintenant
		with data.rule_data__configuration__ as _seuils
}

test_scan_reel_admis if {
	_codes(_entree([_propre])) == set()
}

test_aucun_enonce if {
	_codes(_entree([])) == {"scan.scan_present"}
}

test_autre_digest if {
	_codes(_entree([_enonce(_autre, _propre.predicate)])) == {"scan.scan_present"}
}

test_autre_type if {
	_codes(_entree([object.union(_propre, {"predicateType": "https://slsa.dev/provenance/v1"})])) == {"scan.scan_present"}
}

test_date_illisible if {
	_codes(_entree([_enonce(_digest, object.union(_propre.predicate, {"scannedAt": "hier"}))])) == {"scan.scan_present"}
}

test_kev if {
	_codes(_entree([_enonce(_digest, _predicat("2026-11-09T20:40:09Z", "2026-11-09T06:20:59Z", _kev, []))])) == {"scan.kev_without_vex"}
}

# 07b, tranche 3 : vex = {status, timestamp}, écrit par le scanner ; scan à 2026-11-09T20:40:09Z, heure simulée 2026-11-10T12:00:00Z,
# validité de test 30 jours.
_avec(vulns) := _entree([_enonce(_digest, _predicat("2026-11-09T20:40:09Z", "2026-11-09T06:20:59Z", vulns, []))])

_kev_vex(vex) := [object.union(_kev[0], {"vex": vex})]

_avec_vex(statut, date) := _avec(_kev_vex({"status": statut, "timestamp": date}))

test_vex_valide if {
	_codes(_avec_vex("not_affected", "2026-11-01T00:00:00Z")) == set()
}

test_vex_de_30_jours_admis if {
	_codes(_avec_vex("not_affected", "2026-10-11T12:00:00Z")) == set()
}

test_vex_trop_vieux if {
	_codes(_avec_vex("not_affected", "2026-10-11T11:59:59Z")) == {"scan.kev_without_vex"}
}

test_vex_ecart_horloge_tolere if {
	_codes(_avec_vex("not_affected", "2026-11-09T20:45:09Z")) == set()
}

test_vex_posterieur_au_scan if {
	_codes(_avec_vex("not_affected", "2026-11-09T20:45:10Z")) == {"scan.kev_without_vex"}
}

test_vex_fixed_refuse if {
	_codes(_avec_vex("fixed", "2026-11-01T00:00:00Z")) == {"scan.kev_without_vex"}
}

test_vex_statut_refuse if {
	_codes(_avec_vex("under_investigation", "2026-11-01T00:00:00Z")) == {"scan.kev_without_vex"}
}

test_vex_sans_date if {
	_codes(_avec(_kev_vex({"status": "not_affected"}))) == {"scan.forme", "scan.kev_without_vex"}
}

test_vex_date_illisible if {
	_codes(_avec_vex("not_affected", "hier")) == {"scan.forme", "scan.kev_without_vex"}
}

test_vex_sans_statut if {
	_codes(_avec(_kev_vex({"timestamp": "2026-11-01T00:00:00Z"}))) == {"scan.forme", "scan.kev_without_vex"}
}

test_vex_ancienne_forme_expires_refusee if {
	_codes(_avec(_kev_vex({"status": "not_affected", "expires": "2099-01-01T00:00:00Z"}))) == {"scan.forme", "scan.kev_without_vex"}
}

test_vex_illisible_hors_kev if {
	v := [object.union(_vulns[0], {"vex": {"status": "not_affected", "timestamp": "hier"}})]
	_codes(_avec(v)) == {"scan.forme"}
}

test_vex_hors_kev_sans_effet if {
	v := [object.union(_vulns[0], {"vex": {"status": "not_affected", "timestamp": "2026-11-01T00:00:00Z"}})]
	_codes(_avec(v)) == set()
}

test_bloc_vex_du_predicat_admis if {
	p := object.union(_propre.predicate, {"vex": {"documents": [{"sha256": _autre, "timestamp": "2026-11-01T00:00:00Z"}], "rejetes": 1}})
	_codes(_entree([_enonce(_digest, p)])) == set()
}

test_seuil_vex_absent_refus if {
	c := {d.code |
		some d in scan.deny with input as _avec_vex("not_affected", "2026-11-01T00:00:00Z")
			with time.now_ns as _maintenant
			with data.rule_data__configuration__ as object.remove(_seuils, ["vex_age_max_jours"])
	}
	c == {"scan.kev_without_vex"}
}

test_seuil_vex_null_refus if {
	c := {d.code |
		some d in scan.deny with input as _avec_vex("not_affected", "2026-11-01T00:00:00Z")
			with time.now_ns as _maintenant
			with data.rule_data__configuration__ as object.union(_seuils, {"vex_age_max_jours": null})
	}
	c == {"scan.kev_without_vex"}
}

test_malveillant if {
	_codes(_entree([_enonce(_digest, _predicat("2026-11-09T20:40:09Z", "2026-11-09T06:20:59Z", _vulns, ["MAL-2026-1"]))])) == {"scan.malicious"}
}

test_scan_de_7_jours_admis if {
	_codes(_entree([_enonce(_digest, _predicat("2026-11-03T12:00:00Z", "2026-11-03T06:00:00Z", _vulns, []))])) == set()
}

test_scan_trop_vieux if {
	_codes(_entree([_enonce(_digest, _predicat("2026-11-03T11:59:59Z", "2026-11-03T06:00:00Z", _vulns, []))])) == {"scan.scan_recent"}
}

test_scan_du_futur if {
	_codes(_entree([_enonce(_digest, _predicat("2026-11-10T12:05:01Z", "2026-11-10T06:00:00Z", _vulns, []))])) == {"scan.scan_recent"}
}

test_ecart_horloge_tolere if {
	_codes(_entree([_enonce(_digest, _predicat("2026-11-10T12:05:00Z", "2026-11-10T06:00:00Z", _vulns, []))])) == set()
}

test_base_de_3_jours_admise if {
	_codes(_entree([_enonce(_digest, _predicat("2026-11-09T12:00:00Z", "2026-11-06T12:00:00Z", _vulns, []))])) == set()
}

test_base_trop_vieille if {
	_codes(_entree([_enonce(_digest, _predicat("2026-11-09T12:00:00Z", "2026-11-06T11:59:59Z", _vulns, []))])) == {"scan.base_recente"}
}

test_plus_recent_propre_masque_ancien_kev if {
	ancien := _enonce(_digest, _predicat("2026-11-08T12:00:00Z", "2026-11-08T06:00:00Z", _kev, []))
	_codes(_entree([ancien, _propre])) == set()
}

test_plus_recent_kev_refuse_malgre_ancien_propre if {
	recent := _enonce(_digest, _predicat("2026-11-10T06:00:00Z", "2026-11-10T01:00:00Z", _kev, []))
	_codes(_entree([_propre, recent])) == {"scan.kev_without_vex"}
}

test_memes_dates_toutes_jugees if {
	double := _enonce(_digest, _predicat(_propre.predicate.scannedAt, "2026-11-09T06:20:59Z", _kev, []))
	_codes(_entree([_propre, double])) == {"scan.kev_without_vex"}
}

test_enonce_d_un_autre_digest_ne_masque_pas if {
	recent := _enonce(_autre, _predicat("2026-11-10T06:00:00Z", "2026-11-10T01:00:00Z", _vulns, []))
	ancien := _enonce(_digest, _predicat("2026-11-09T06:00:00Z", "2026-11-09T01:00:00Z", _kev, []))
	_codes(_entree([recent, ancien])) == {"scan.kev_without_vex"}
}

_sans(champ) := _enonce(_digest, object.remove(_propre.predicate, [champ]))

test_sans_vulnerabilites if {
	_codes(_entree([_sans("vulnerabilities")])) == {"scan.forme"}
}

test_vulnerabilites_hors_tableau if {
	p := object.union(_propre.predicate, {"vulnerabilities": {"a": {"id": "CVE-X", "kev": false}}})
	_codes(_entree([_enonce(_digest, p)])) == {"scan.forme"}
}

test_sans_malicious if {
	_codes(_entree([_sans("malicious")])) == {"scan.forme"}
}

test_sans_scanner if {
	_codes(_entree([_sans("scanner")])) == {"scan.forme"}
}

test_kev_absent if {
	v := [{"id": "CVE-X"}]
	_codes(_entree([_enonce(_digest, _predicat("2026-11-09T20:40:09Z", "2026-11-09T06:20:59Z", v, []))])) == {"scan.forme"}
}

test_seuils_absents_refus if {
	c := {d.code | some d in scan.deny with input as _entree([_propre]) with time.now_ns as _maintenant}
	c == {"scan.scan_recent", "scan.base_recente"}
}

# 07b, limite 4 (passage 18) : repli sans --vex, aucun VEX appliqué ; le champ repli du bloc vex ne change rien à la porte.
_bloc_repli := {"vex": {"documents": [], "rejetes": 0, "ecarteesSansExemption": 0, "repli": 1}}

test_repli_admis if {
	_codes(_entree([_enonce(_digest, object.union(_propre.predicate, _bloc_repli))])) == set()
}

test_repli_kev_refuse if {
	p := object.union(_predicat("2026-11-09T20:40:09Z", "2026-11-09T06:20:59Z", _kev, []), _bloc_repli)
	_codes(_entree([_enonce(_digest, p)])) == {"scan.kev_without_vex"}
}
