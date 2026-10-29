#!/usr/bin/env python3
"""Brique 08, J6 : cas d'essai des règles d'admission (politique.sh admission).

Usage : cas-admission.py <répertoire> <bundle de tâche signé> <image busybox>
Écrit un fichier JSON par cas et cas.tsv (cas, attendu, évalué à l'admission : oui|non, description).
"""
import copy
import json
import pathlib
import sys

out, bundle, busybox = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
out.mkdir(parents=True, exist_ok=True)
lignes = []

GABARIT = {
    "nodeSelector": {"zone": "build"},
    "tolerations": [{"key": "zone", "operator": "Equal", "value": "build", "effect": "NoSchedule"}],
    "securityContext": {"runAsNonRoot": True, "runAsUser": 65532, "seccompProfile": {"type": "RuntimeDefault"}},
}
TR = {
    "apiVersion": "tekton.dev/v1", "kind": "TaskRun",
    "metadata": {"name": "cas", "namespace": "builds"},
    "spec": {"serviceAccountName": "build", "podTemplate": GABARIT,
             "taskRef": {"resolver": "bundles", "params": [
                 {"name": "bundle", "value": bundle}, {"name": "name", "value": "essai-confiance"},
                 {"name": "kind", "value": "task"}]}},
}
PIPE = bundle.replace("/tekton/tasks/essai-confiance@", "/tekton/pipelines/essai@")
PR = {
    "apiVersion": "tekton.dev/v1", "kind": "PipelineRun",
    "metadata": {"name": "cas", "namespace": "builds"},
    "spec": {"taskRunTemplate": {"serviceAccountName": "build", "podTemplate": GABARIT},
             "pipelineRef": {"resolver": "bundles", "params": [
                 {"name": "bundle", "value": PIPE}, {"name": "name", "value": "essai"},
                 {"name": "kind", "value": "pipeline"}]}},
}
RESTREINT = {"allowPrivilegeEscalation": False, "runAsNonRoot": True, "runAsUser": 65532,
             "capabilities": {"drop": ["ALL"]}, "seccompProfile": {"type": "RuntimeDefault"}}
POD = {
    "apiVersion": "v1", "kind": "Pod", "metadata": {"name": "cas", "namespace": "bancc"},
    "spec": {"containers": [{"name": "app", "image": busybox, "securityContext": RESTREINT}]},
}


def cas(nom, attendu, base, description, modif=None, admission="oui"):
    o = copy.deepcopy(base)
    o["metadata"]["name"] = nom
    if modif:
        modif(o)
    (out / f"{nom}.json").write_text(json.dumps(o, ensure_ascii=False, indent=1))
    lignes.append(f"{nom}\t{attendu}\t{admission}\t{description}")


def sc(**kw):
    def f(o):
        o["spec"]["containers"][0]["securityContext"] = dict(RESTREINT, **kw)
    return f


# Test 2
cas("tr-bundle-signe", "PASS", TR, "bundle signé de tekton/tasks, épinglé par digest")
cas("tr-en-ligne", "FAIL", TR, "taskSpec en ligne",
    lambda o: (o["spec"].pop("taskRef"), o["spec"].update(taskSpec={"steps": [{"name": "s", "image": busybox, "script": "true"}]})))
cas("tr-locale", "FAIL", TR, "référence locale (Task de l'espace)", lambda o: o["spec"].update(taskRef={"name": "essai-confiance"}))
cas("tr-resolveur-git", "FAIL", TR, "résolveur git",
    lambda o: o["spec"].update(taskRef={"resolver": "git", "params": [{"name": "url", "value": "https://exemple.org/t.git"}]}))
cas("tr-bundle-etiquette", "FAIL", TR, "bundle désigné par une étiquette, sans digest",
    lambda o: o["spec"]["taskRef"]["params"][0].update(value=bundle.split("@")[0] + ":essai"))
cas("tr-bundle-hors-tekton", "FAIL", TR, "bundle hors de tekton/tasks (essais-j6/)",
    lambda o: o["spec"]["taskRef"]["params"][0].update(value=bundle.replace("/tekton/tasks/", "/essais-j6/tasks/")))
cas("tr-espace-default", "FAIL", TR, "TaskRun hors de l'espace builds", lambda o: o["metadata"].update(namespace="default"))
cas("tr-compte-default", "FAIL", TR, "compte de service autre que build", lambda o: o["spec"].update(serviceAccountName="default"))
cas("tr-gabarit-volume-secret", "FAIL", TR, "podTemplate avec un volume secret",
    lambda o: o["spec"]["podTemplate"].update(volumes=[{"name": "s", "secret": {"secretName": "forgejo-webhook"}}]))
cas("tr-gabarit-hostnetwork", "FAIL", TR, "podTemplate en hostNetwork", lambda o: o["spec"]["podTemplate"].update(hostNetwork=True))
cas("tr-workspace-secret", "FAIL", TR, "workspace lié à un secret",
    lambda o: o["spec"].update(workspaces=[{"name": "w", "secret": {"secretName": "forgejo-webhook"}}]))
cas("pr-bundle-signe", "PASS", PR, "bundle de tekton/pipelines, épinglé par digest")
cas("pr-en-ligne", "FAIL", PR, "pipelineSpec en ligne",
    lambda o: (o["spec"].pop("pipelineRef"), o["spec"].update(pipelineSpec={"tasks": [{"name": "t", "taskRef": TR["spec"]["taskRef"]}]})))
cas("pr-locale", "FAIL", PR, "référence locale (Pipeline de l'espace)", lambda o: o["spec"].update(pipelineRef={"name": "sample-app-essai"}))
cas("pr-taskrunspecs-compte", "FAIL", PR, "taskRunSpecs : autre compte de service pour une tâche",
    lambda o: o["spec"].update(taskRunSpecs=[{"pipelineTaskName": "t", "serviceAccountName": "default"}]))
# Test 4
cas("pod-restreint", "PASS", POD, "pod restreint (Pod Security restricted)")
cas("pod-privilegie", "FAIL", POD, "conteneur privilégié hors Kata", sc(privileged=True, allowPrivilegeEscalation=True))
cas("pod-privilegie-kata", "PASS", POD, "conteneur privilégié sous Kata (RuntimeClass de J7, absente : CLI seul)",
    lambda o: (sc(privileged=True, allowPrivilegeEscalation=True)(o), o["spec"].update(runtimeClassName="kata-qemu")), admission="non")
cas("pod-init-privilegie", "FAIL", POD, "conteneur d'initialisation privilégié",
    lambda o: o["spec"].update(initContainers=[{"name": "i", "image": busybox, "securityContext": dict(RESTREINT, privileged=True, allowPrivilegeEscalation=True)}]))
cas("pod-hostpath", "FAIL", POD, "volume hostPath",
    lambda o: o["spec"].update(volumes=[{"name": "h", "hostPath": {"path": "/var/lib/rancher"}}]))
cas("pod-hostnetwork", "FAIL", POD, "hostNetwork", lambda o: o["spec"].update(hostNetwork=True))
cas("pod-hostpid", "FAIL", POD, "hostPID", lambda o: o["spec"].update(hostPID=True))
cas("pod-cap-sys-admin", "FAIL", POD, "capacité SYS_ADMIN ajoutée", sc(capabilities={"add": ["SYS_ADMIN"]}))
cas("pod-cap-net-bind", "PASS", POD, "capacité NET_BIND_SERVICE ajoutée", sc(capabilities={"drop": ["ALL"], "add": ["NET_BIND_SERVICE"]}))
# Zone confiance
ZONE = copy.deepcopy(POD)
ZONE["metadata"]["namespace"] = "tekton-chains"
ZONE["spec"]["nodeSelector"] = {"zone": "confiance"}
cas("zone-confiance", "PASS", ZONE, "pod de tekton-chains sur le nœud de confiance")
cas("zone-sans-nodeselector", "FAIL", ZONE, "pod de tekton-chains sans nodeSelector", lambda o: o["spec"].pop("nodeSelector"))
cas("zone-build", "FAIL", ZONE, "pod de tekton-chains en zone build, taint toléré",
    lambda o: o["spec"].update(nodeSelector={"zone": "build"}, tolerations=GABARIT["tolerations"]))
cas("zone-tolerance-universelle", "FAIL", ZONE, "pod de tekton-chains qui tolère tout taint",
    lambda o: o["spec"].update(tolerations=[{"operator": "Exists"}]))
cas("zone-nodename-build", "FAIL", ZONE, "pod d'openbao placé directement sur sc-build (nodeName)",
    lambda o: (o["metadata"].update(namespace="openbao"), o["spec"].update(nodeName="sc-build")))
# StepAction
cas("stepaction", "FAIL", {"apiVersion": "tekton.dev/v1beta1", "kind": "StepAction", "metadata": {"name": "x", "namespace": "builds"},
                           "spec": {"image": busybox, "script": "true"}}, "création d'une StepAction")

(out / "cas.tsv").write_text("\n".join(lignes) + "\n")
