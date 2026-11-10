# Évaluateur des sélecteurs de pods des politiques réseau (NetworkPolicy et CiliumNetworkPolicy), commun aux contrôles
# d'invariant de construction.sh (construire-image), prefetch.sh (prefetch-gomod) et 08c/sortie-builds.sh. Ajouté le 10/11/2026
# pour la règle builds-sans-internet (08c), qui sélectionne par matchExpressions (NotIn) : l'ancien contrôle de prefetch.sh
# tenait toute politique à matchLabels vide pour « sélectionne tout ». Sémantique des sélecteurs de Kubernetes : matchLabels et
# matchExpressions se cumulent ; NotIn et DoesNotExist retiennent aussi un pod sans la clé. Opérateur inconnu : erreur (échec fermé).
# Usage : jq -L <répertoire> 'include "selecteurs"; …'

def correspond($l): # sélecteur (objet) contre un objet de labels
  ((.matchLabels // {}) | to_entries | all(.value == $l[.key]))
  and ((.matchExpressions // []) | all(
    .key as $k | (.values // []) as $v | $l[$k] as $x |
    if .operator == "In" then $x != null and ($v | index($x)) != null
    elif .operator == "NotIn" then $x == null or ($v | index($x)) == null
    elif .operator == "Exists" then $x != null
    elif .operator == "DoesNotExist" then $x == null
    else error("opérateur de sélecteur inconnu : \(.operator)") end));

def selecteur: if .kind == "NetworkPolicy" then .spec.podSelector else .spec.endpointSelector end;

def selectionne($l): selecteur | correspond($l);

# Autorise du trafic : règles ingress ou egress (les règles ingressDeny et egressDeny n'autorisent rien)
def autorise: ((.spec.egress // []) | length) > 0 or ((.spec.ingress // []) | length) > 0;

# Autorise une sortie par CIDR (toCIDR, toCIDRSet, ipBlock) : ce qu'un refus des adresses publiques pourrait annuler sans bruit
def sortie_cidr: [(.spec.egress // [])[] | select(has("toCIDR") or has("toCIDRSet") or ((.to // []) | any(has("ipBlock"))))] | length > 0;

def nom: "\(.kind) \(.metadata.name)";
