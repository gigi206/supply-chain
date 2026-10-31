# Brique 08, J6 : règles de la porte ajoutées à la bibliothèque Conforma (politique.sh porte).
# Paquet de premier niveau : la bibliothèque n'utilise pas le paquet release, et include le désigne par son nom.
package porte

import rego.v1

import data.lib
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
