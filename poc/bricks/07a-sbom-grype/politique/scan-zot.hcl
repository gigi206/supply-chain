# Brique 07a, jalon G3 (calque de horodatage-zot de la 08, J8) : identifiants Zot du job de scan (compte poc-scan) lus dans
# OpenBao au démarrage du pod, sans Secret Kubernetes ; le jeton se révoque lui-même après la lecture.
path "kv/scan/zot" {
  capabilities = ["read"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
