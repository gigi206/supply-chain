# Brique 08, jalon J5 : politique du seul rôle JWT tsa. Les appels du client hashivault de sigstore v1.11.1 qu'utilise
# timestamp-authority v2.2.0 (lecture de la clé publique, signature), plus le renouvellement de son propre jeton
# périodique (sans politique par défaut, renew-self n'est pas accordé). Ni la clé chains, ni export, ni sauvegarde.
path "transit/keys/tsa" {
  capabilities = ["read"]
}
path "transit/sign/tsa" {
  capabilities = ["update"]
}
path "transit/sign/tsa/*" {
  capabilities = ["update"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
