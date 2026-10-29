# Brique 08, jalon J3 : OpenBao 2.7.2, un seul nœud sur sc-confiance (raft, TLS de la CA du PoC).
# Audit déclaré ici (strophe audit) : actif dès le démarrage, avant toute configuration.
ui = false
log_level = "info"
api_addr = "https://openbao.openbao.svc.cluster.local:8200"
cluster_addr = "https://127.0.0.1:8201"

listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "127.0.0.1:8201"
  tls_cert_file = "/openbao/tls/tls.crt"
  tls_key_file = "/openbao/tls/tls.key"
  tls_min_version = "tls13"
}

storage "raft" {
  path = "/openbao/data"
  node_id = "openbao-0"
}

audit "file" "fichier" {
  description = "Journal d'audit sur le volume persistant (valeurs sensibles en HMAC)"
  options {
    file_path = "/openbao/data/audit.log"
  }
}
