# Brique 08c, S1 (« Oui, valide S1 », 05/11/2026) : politique du seul rôle JWT chains-zot, distinct de tekton-chains (Transit).
# Identifiants Zot de Chains (compte poc-build) lus au démarrage du pod ; le jeton se révoque lui-même après la lecture.
path "kv/tekton-chains/zot" {
  capabilities = ["read"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
