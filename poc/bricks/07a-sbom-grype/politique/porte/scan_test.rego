# Brique 07a, G5 : tests de politique/porte/scan.rego, lancés sur l'hôte par ec opa test (plateforme.sh g5_regles), comme ceux de
# porte_test.rego ; hors de la ConfigMap porte. Heure simulée par with : un test ne doit pas dépendre de la date du jour. Fixture de
# la forme du prédicat réel (resultats/g4-scan-predicat.json).
package scan_test

import rego.v1

import data.scan

_digest := "3a7ca1b14dbf13c6655c500fee01460937c2bee4473e32073459e713707923b5"

_autre := "1111111111111111111111111111111111111111111111111111111111111111"

_type := "https://supply-chain.example/scan/v1"

_seuils := {"scan_age_max_jours": 7, "base_age_max_jours": 3, "vex_statuts_acceptes": ["not_affected", "fixed"]}

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

_kev_vex(statut, expire) := [object.union(_kev[0], {"vex": {"status": statut, "expires": expire}})]

_avec_vex(statut, expire) := _entree([_enonce(_digest, _predicat("2026-11-09T20:40:09Z", "2026-11-09T06:20:59Z", _kev_vex(statut, expire), []))])

test_vex_valide if {
	_codes(_avec_vex("not_affected", "2026-12-01T00:00:00Z")) == set()
}

test_vex_expire if {
	_codes(_avec_vex("not_affected", "2026-11-01T00:00:00Z")) == {"scan.kev_without_vex"}
}

test_vex_statut_refuse if {
	_codes(_avec_vex("under_investigation", "2026-12-01T00:00:00Z")) == {"scan.kev_without_vex"}
}

test_vex_sans_date if {
	v := [object.union(_kev[0], {"vex": {"status": "fixed"}})]
	_codes(_entree([_enonce(_digest, _predicat("2026-11-09T20:40:09Z", "2026-11-09T06:20:59Z", v, []))])) == {"scan.kev_without_vex"}
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
