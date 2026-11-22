# Brique 07b, pièce 2 de la pose : politique du seul jeton du propriétaire qui signe les VEX (calque de scanner-signature de la
# 07a). Les appels du client hashivault de cosign (lecture de la clé publique, signature), plus la révocation de son propre jeton.
# Ni les clés scanner, chains et tsa, ni export, ni sauvegarde, ni configuration de la clé, ni renouvellement. Le jeton est émis
# par la connexion userpass du propriétaire (décision du 22/11/2026), 15 min, posée par vex-openbao.sh acces_vex.
path "transit/keys/vex" {
  capabilities = ["read"]
}
path "transit/sign/vex" {
  capabilities = ["update"]
}
path "transit/sign/vex/*" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
