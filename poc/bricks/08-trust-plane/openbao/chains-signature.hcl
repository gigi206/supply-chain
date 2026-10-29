# Brique 08, jalon J3 : politique du seul rôle JWT tekton-chains. Exactement les appels du client hashivault
# de sigstore v1.10.9 qu'utilise Chains : lecture de la clé publique et signature. Ni export, ni sauvegarde,
# ni configuration de la clé, ni politique par défaut (token_no_default_policy).
path "transit/keys/chains" {
  capabilities = ["read"]
}
path "transit/sign/chains" {
  capabilities = ["update"]
}
path "transit/sign/chains/*" {
  capabilities = ["update"]
}
