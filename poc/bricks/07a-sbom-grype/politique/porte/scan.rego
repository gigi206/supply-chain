# Brique 07a, G5 : seconde moitié du contrôle 7 (ec validate input, conteneur scan du Job de la porte). L'entrée est écrite par
# politique/porte/scan-verifier.sh : {"digest":…,"statements":[…]}, énoncés dont cosign a vérifié la signature par la clé du scanner.
# Règles kev_without_vex, malicious et scan_present reprises de poc/benchmarks/kyverno-seul/conforma/policy/bench.rego (D6 a), à une
# différence près : elles jugent le scan retenu (D4), pas tous les scans ; un scan ancien ne compte plus dès qu'un autre lui succède.
package scan

import rego.v1

_type := "https://supply-chain.example/scan/v1"

_heure := 3600000000000

_jour := 24 * _heure

_derive := 300000000000 # écart d'horloge toléré entre le scanner et la porte : 5 min

_seuil(nom) := data.rule_data__configuration__[nom]

# Scans recevables : énoncé du bon type, sujet égal au digest jugé, date lisible. Ni le dépôt ni l'énoncé ne sont fournis par
# l'appelant ; le sujet est revérifié ici, comme dans vsa.sh.
_scans contains {"t": t, "p": e.predicate} if {
	some e in input.statements
	e.predicateType == _type
	some s in e.subject
	s.digest.sha256 == input.digest
	t := time.parse_rfc3339_ns(e.predicate.scannedAt)
}

# Scan retenu (D4) : le plus récent. Deux scans à la même date sont jugés tous les deux.
_retenus contains s if {
	some s in _scans
	s.t == max({a.t | some a in _scans})
}

# METADATA
# title: Résultat de scan présent
# description: >-
#   Au moins un énoncé vérifié par la clé du scanner, de type scan/v1, dont le sujet est le digest jugé.
# custom:
#   short_name: scan_present
deny contains {"code": "scan.scan_present", "msg": msg} if {
	count(_scans) == 0
	msg := sprintf("aucun scan recevable parmi %d énoncé(s) vérifié(s)", [count(input.statements)])
}

# METADATA
# title: Prédicat complet
# description: >-
#   Échec fermé : un champ absent ou d'un autre type ne doit pas faire passer les règles suivantes à vide.
# custom:
#   short_name: forme
deny contains {"code": "scan.forme", "msg": sprintf("prédicat incomplet : %s", [m])} if {
	some s in _retenus
	some m in _defauts(s.p)
}

_defauts(p) := {m |
	some m, ok in {
		"vulnerabilities": is_array(object.get(p, "vulnerabilities", null)),
		"malicious": is_array(object.get(p, "malicious", null)),
		"scanner.db.built": _date(object.get(p, ["scanner", "db", "built"], "")),
		"kev": _kev_lisibles(p),
	}
	not ok
}

_date(d) := true if {
	time.parse_rfc3339_ns(d)
} else := false

_kev_lisibles(p) := true if {
	every v in p.vulnerabilities {
		is_boolean(v.kev)
	}
} else := false

# METADATA
# title: Scan récent
# description: >-
#   D4 : le scan retenu date de 7 jours au plus (scan_age_max_jours). Un scan daté du futur, au-delà de l'écart d'horloge toléré,
#   resterait retenu indéfiniment : refusé aussi.
# custom:
#   short_name: scan_recent
deny contains {"code": "scan.scan_recent", "msg": msg} if {
	some s in _retenus
	age := time.now_ns() - s.t
	not _age_admis(age)
	msg := sprintf("scan retenu d'il y a %d h", [ceil(age / _heure)])
}

_age_admis(age) if {
	age >= 0 - _derive
	age <= _seuil("scan_age_max_jours") * _jour
}

# METADATA
# title: Base du scan récente
# description: >-
#   D4 : la base de vulnérabilités a été construite 3 jours au plus avant le scan retenu (base_age_max_jours).
# custom:
#   short_name: base_recente
deny contains {"code": "scan.base_recente", "msg": msg} if {
	some s in _retenus
	ecart := s.t - time.parse_rfc3339_ns(s.p.scanner.db.built)
	not _ecart_admis(ecart)
	msg := sprintf("base construite %d h avant le scan", [ceil(ecart / _heure)])
}

_ecart_admis(ecart) if ecart <= _seuil("base_age_max_jours") * _jour

# METADATA
# title: Pas de KEV sans VEX valide (exceptions datées)
# custom:
#   short_name: kev_without_vex
deny contains {"code": "scan.kev_without_vex", "msg": sprintf("KEV sans VEX valide : %s", [v.id])} if {
	some s in _retenus
	some v in s.p.vulnerabilities
	v.kev == true
	not _vex_valide(v)
}

_vex_valide(v) if {
	v.vex.status in _seuil("vex_statuts_acceptes")
	time.parse_rfc3339_ns(v.vex.expires) > time.now_ns()
}

# METADATA
# title: Pas de paquet malveillant
# custom:
#   short_name: malicious
deny contains {"code": "scan.malicious", "msg": sprintf("paquet malveillant : %s", [m])} if {
	some s in _retenus
	some m in s.p.malicious
}
