# Brique 09, O5 réel, deuxième accord du propriétaire (« Oui », 19/11/2026) : politique du seul jeton lien-signature, détenu
# par l'hôte d'administration (D3 a). Calque de scanner-signature (07a) et tsa-signature (08) : les appels du client hashivault
# de cosign (lecture de la clé publique, signature), plus la révocation de son propre jeton. Ni les clés chains, tsa et
# scanner, ni export, ni sauvegarde, ni configuration de la clé, ni renouvellement, ni secrets kv.
path "transit/keys/lien" {
  capabilities = ["read"]
}
path "transit/sign/lien" {
  capabilities = ["update"]
}
path "transit/sign/lien/*" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
