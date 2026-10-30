# Brique 08, J6 : règles de la porte ajoutées à la bibliothèque Conforma (politique.sh porte).
# Paquet de premier niveau : la bibliothèque n'utilise pas le paquet release, et include le désigne par son nom.
package porte

import rego.v1

import data.lib

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
