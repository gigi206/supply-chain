# Brique 07a, jalon G3 : politique du seul rôle JWT scanner (calque de tsa-signature de la 08). Les appels du client
# hashivault de cosign (lecture de la clé publique, signature), plus la révocation de son propre jeton. Ni les clés chains
# et tsa, ni export, ni sauvegarde, ni renouvellement ; pas les identifiants Zot (rôle scan-zot).
path "transit/keys/scanner" {
  capabilities = ["read"]
}
path "transit/sign/scanner" {
  capabilities = ["update"]
}
path "transit/sign/scanner/*" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
