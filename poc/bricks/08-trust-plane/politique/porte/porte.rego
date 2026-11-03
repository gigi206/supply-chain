# Brique 08, J6 : règles de la porte ajoutées à la bibliothèque Conforma (politique.sh porte).
# Paquet de premier niveau : la bibliothèque n'utilise pas le paquet release, et include le désigne par son nom.
package porte

import rego.v1

import data.lib
import data.lib.rule_data
import data.lib.sigstore
import data.lib.tekton

# METADATA
# title: Tâches vues par la bibliothèque
# description: >-
#   Témoin : la bibliothèque ne lit les tâches d'une provenance SLSA v1 que dans le contenu des entrées pipelineTask
#   de resolvedDependencies (buildType slsa-tekton de Chains). Sans tâche vue, trusted_task n'a rien à refuser.
# custom:
#   short_name: taches_vues
deny contains {"code": "porte.taches_vues", "msg": msg} if {
	count(lib.tasks_from_pipelinerun) == 0
	msg := sprintf("aucune tâche vue dans %d provenance(s) de PipelineRun", [count(lib.pipelinerun_attestations)])
}

# METADATA
# title: Signature d'image explicite
# description: >-
#   Repris du banc C : Conforma v0.10.42 annonce « Image signature check passed » avec 0 signature quand une
#   attestation signée par la clé suffit ; on exige une vraie signature de l'image.
# custom:
#   short_name: image_signature
deny contains {"code": "porte.image_signature", "msg": "aucune signature d'image (seulement des attestations)"} if {
	count(object.get(input.image, "signatures", [])) == 0
}

# METADATA
# title: Construction sous Kata, lue dans le TaskRun signé
# description: >-
#   Option (c) des internalParameters (décision du propriétaire du 30/10/2026) : la porte juge un fait du TaskRun exécuté,
#   pas une déclaration. Chaque TaskRun de construire-image (nom de la tâche ou dépôt de son bundle) en contenu de
#   resolvedDependencies doit porter spec.podTemplate.runtimeClassName kata. Les taskRunSpecs des paramètres externes,
#   déclaration du créateur du PipelineRun, ne comptent pas. Un runtimeClassName venu d'un default-pod-template ou d'une
#   mutation n'est pas dans la spec : refusé. Sans TaskRun de construire-image, la règle ne refuse rien (succès à vide).
# custom:
#   short_name: construction_kata
deny contains {"code": "porte.construction_kata", "msg": msg} if {
	some task in lib.tasks_from_pipelinerun
	_construction(task)
	rc := object.get(task, ["spec", "podTemplate", "runtimeClassName"], "")
	rc != "kata"
	msg := sprintf("TaskRun %s de construire-image : runtimeClassName %q dans la spec signée, kata exigé",
		[object.get(task, ["metadata", "name"], "?"), rc])
}

_construction(task) if tekton.task_ref(task).name == "construire-image"

_construction(task) if {
	b := object.get(tekton.task_ref(task), "bundle", "")
	split(b, "@")[0] == "sc-stockage.poc.test:5000/tekton/tasks/construire-image"
}

# METADATA
# title: Fermeture produite par la plateforme
# description: >-
#   Brique 03, D6 (décision du propriétaire du 03/11/2026) : la fermeture de dépendances d'une construction doit venir de la
#   pipeline de prefetch de la plateforme. Elle est lue dans le résultat FERMETURE_ARTIFACT_INPUTS du TaskRun preparer-entrees
#   (contenu signé de la provenance de PipelineRun jugée, la plus récente, comme pour trusted_task), jamais par un motif de
#   dépôt. Sa provenance est vérifiée avec la clé et les options de ec (--public-key, --ignore-rekor). Il en faut une qui soit
#   celle d'un PipelineRun : slsa-tekton, builder.id autorisé, sujet égal à la fermeture sous builds/fermetures/, tâches
#   exactement prefetch-gomod et publier-fermeture, toutes deux dans la liste revue, digest publié par publier-fermeture, même
#   dépôt Forgejo que la construction. Une attestation de TaskRun seule (publier-fermeture lancée hors de la pipeline) ne
#   suffit pas. La règle ne s'applique qu'aux provenances qui contiennent preparer-entrees ou construire-image.
# custom:
#   short_name: fermeture_plateforme
deny contains {"code": "porte.fermeture_plateforme", "msg": msg} if {
	some task in lib.tasks_from_pipelinerun
	_construction_ou_preparation(task)
	count(_fermetures) == 0
	msg := "construction sans fermeture lisible dans le résultat FERMETURE_ARTIFACT_INPUTS de preparer-entrees"
}

deny contains {"code": "porte.fermeture_plateforme", "msg": msg} if {
	some f in _fermetures
	not _fermeture_prouvee(f)
	msg := sprintf("fermeture %s : aucune provenance de la pipeline de prefetch de la plateforme (%s)", [f.ref, _motif(f)])
}

_construction_ou_preparation(task) if _construction(task)

_construction_ou_preparation(task) if _preparation(task)

_preparation(task) if tekton.task_ref(task).name == "preparer-entrees"

_preparation(task) if {
	b := object.get(tekton.task_ref(task), "bundle", "")
	split(b, "@")[0] == "sc-stockage.poc.test:5000/tekton/tasks/preparer-entrees"
}

_fermetures contains f if {
	some task in lib.tasks_from_pipelinerun
	_preparation(task)
	r := tekton.task_result(task, "FERMETURE_ARTIFACT_INPUTS")
	startswith(r.uri, "oci://")
	regex.match(`^sha256:[0-9a-f]{64}$`, r.digest)
	depot := substring(r.uri, 6, -1)
	f := {
		"ref": sprintf("%s@%s", [depot, r.digest]),
		"depot": depot,
		"digest": r.digest,
		"git": tekton.task_result(task, "CHAINS-GIT_URL"),
	}
}

_verification(ref) := ec.sigstore.verify_attestation(ref, sigstore.opts)

_fermeture_prouvee(f) if {
	some att in object.get(_verification(f.ref), "attestations", [])
	_prefetch(att.statement, f)
}

_prefetch(st, f) if {
	st.predicateType == lib.slsa_provenance_predicate_type_v1
	st.predicate.buildDefinition.buildType == lib.tekton_slsav1_pipeline_run
	st.predicate.runDetails.builder.id in rule_data.get("allowed_builder_ids")
	regex.match(`^[^/]+/builds/fermetures/`, f.depot)
	some s in st.subject
	s.name == f.depot
	sprintf("sha256:%s", [s.digest.sha256]) == f.digest
	taches := tekton.tasks({"statement": st})
	count(taches) == 2
	count(tekton.untrusted_task_refs(taches, {})) == 0
	some p in taches
	tekton.task_ref(p).name == "publier-fermeture"
	tekton.task_result(p, "IMAGE_URL") == f.depot
	tekton.task_result(p, "IMAGE_DIGEST") == f.digest
	some q in taches
	tekton.task_ref(q).name == "prefetch-gomod"
	tekton.task_result(q, "CHAINS-GIT_URL") == f.git
}

_motif(f) := m if {
	v := _verification(f.ref)
	n := count(object.get(v, "attestations", []))
	e := concat(" ; ", object.get(v, "errors", []))
	m := substring(sprintf("%d provenance(s) vérifiée(s) par la clé de Chains, aucune conforme ; erreurs : %s", [n, e]), 0, 400)
} else := "vérification sans résultat"
