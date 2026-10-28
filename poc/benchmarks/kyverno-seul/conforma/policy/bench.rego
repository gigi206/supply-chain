# Contrôles de release du banc « Kyverno seul » (ADR 0000 §4), version Conforma.
# Les attestations de input.attestations ont déjà été vérifiées avec la clé
# de provenance passée à `ec validate image --public-key`.
package release

import rego.v1

_prov_t := "https://slsa.dev/provenance/v1"
_vsa_t := "https://slsa.dev/verification_summary/v1"
_scan_t := "https://supply-chain.example/scan/v1"
_lic_t := "https://supply-chain.example/licences/v1"

_predicates(t) := [a.statement.predicate | some a in input.attestations; a.statement.predicateType == t]

_prov := _predicates(_prov_t)

_deps := [d | some p in _prov; some d in p.buildDefinition.resolvedDependencies]

_result(name, msg) := {"code": sprintf("bench.%s", [name]), "msg": msg}

# METADATA
# title: Signature d'image explicite
# description: >-
#   Avec les bundles cosign v3, une attestation signée par la clé suffit à faire
#   passer la vérification de signature d'image ; on exige une vraie signature
#   (prédicat https://sigstore.dev/cosign/sign/v1), exposée dans input.image.signatures.
# custom:
#   short_name: image_signature
deny contains _result("image_signature", "aucune signature d'image (seulement des attestations)") if {
	count(object.get(input.image, "signatures", [])) == 0
}

# METADATA
# title: Provenance SLSA v1 présente
# custom:
#   short_name: provenance_present
deny contains _result("provenance_present", "aucune provenance SLSA v1 signée par la clé attendue") if {
	count(_prov) == 0
}

# METADATA
# title: Builder attendu
# custom:
#   short_name: builder_id
deny contains _result("builder_id", sprintf("builder.id inattendu : %s", [p.runDetails.builder.id])) if {
	some p in _prov
	p.runDetails.builder.id != data.bench.expected_builder_id
}

# METADATA
# title: Source autorisée
# custom:
#   short_name: source
deny contains _result("source", sprintf("source non autorisée : %s", [url])) if {
	some p in _prov
	url := p.buildDefinition.externalParameters.git.url
	not startswith(url, data.bench.allowed_source_prefix)
}

# METADATA
# title: Dépendances épinglées par digest
# custom:
#   short_name: pinned_dependencies
deny contains _result("pinned_dependencies", sprintf("dépendance sans digest : %s", [d.uri])) if {
	some d in _deps
	count(object.get(d, "digest", {})) == 0
}

# METADATA
# title: Dépendances d'origine autorisée
# custom:
#   short_name: dependency_origin
deny contains _result("dependency_origin", sprintf("origine non autorisée : %s", [d.uri])) if {
	some d in _deps
	not _allowed_origin(d.uri)
}

_allowed_origin(uri) if {
	some prefix in data.bench.allowed_dependency_prefixes
	startswith(uri, prefix)
}

# METADATA
# title: Tâches de confiance
# custom:
#   short_name: trusted_task
deny contains _result("trusted_task", sprintf("tâche non autorisée : %s", [d.uri])) if {
	some d in _deps
	startswith(d.uri, data.bench.trusted_task_prefix)
	not d.digest.sha256 in data.bench.trusted_task_digests
}

# METADATA
# title: VSA de replay valide (clé du domaine de replay)
# custom:
#   short_name: replay_vsa
deny contains _result("replay_vsa", "aucune VSA PASSED signée par la clé du domaine de replay") if {
	not _vsa_passed
}

_vsa_passed if {
	res := ec.sigstore.verify_attestation(input.image.ref, {"public_key": data.bench_keys.vsa_public_key, "ignore_rekor": true})
	res.success
	some a in res.attestations
	a.statement.predicateType == _vsa_t
	a.statement.predicate.verificationResult == "PASSED"
	a.statement.predicate.verifier.id == data.bench.vsa_verifier_id
}

# METADATA
# title: Pas de KEV sans VEX valide (exceptions datées)
# custom:
#   short_name: kev_without_vex
deny contains _result("kev_without_vex", sprintf("KEV sans VEX valide : %s", [v.id])) if {
	some s in _predicates(_scan_t)
	some v in s.vulnerabilities
	v.kev
	not _vex_valid(v)
}

_vex_valid(v) if {
	v.vex.status in data.bench.vex_accepted_status
	time.parse_rfc3339_ns(v.vex.expires) > time.now_ns()
}

# METADATA
# title: Pas de paquet malveillant
# custom:
#   short_name: malicious
deny contains _result("malicious", sprintf("paquet malveillant : %s", [m])) if {
	some s in _predicates(_scan_t)
	some m in s.malicious
}

# METADATA
# title: Résultat de scan présent
# custom:
#   short_name: scan_present
deny contains _result("scan_present", "aucune attestation de scan") if {
	count(_predicates(_scan_t)) == 0
}

# METADATA
# title: Pas de violation de licence ERROR
# custom:
#   short_name: licences
deny contains _result("licences", sprintf("%d violation(s) de licence ERROR", [l.violations.error])) if {
	some l in _predicates(_lic_t)
	l.violations.error > 0
}

# METADATA
# title: Verdict de licences présent
# custom:
#   short_name: licences_present
deny contains _result("licences_present", "aucun verdict de licences") if {
	count(_predicates(_lic_t)) == 0
}
