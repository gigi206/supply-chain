# Brique 08, J8 (décision du propriétaire du 01/11/2026) : identifiants Zot du job d'horodatage (compte poc-horodatage) lus
# dans OpenBao au démarrage du pod, sans Secret Kubernetes ; le jeton se révoque lui-même après la lecture.
path "kv/horodatage/zot" {
  capabilities = ["read"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
