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
  # Brique 19, O2 (décisions du propriétaire du 02/11/2026) : /v1/sys/metrics lisible sans jeton (aucun jeton OpenBao
  # sur sc-stockage) ; la NetworkPolicy et le droit services/proxy borné restent les seules barrières.
  telemetry {
    unauthenticated_metrics_access = true
  }
}

# Brique 19, O2 : métriques au format Prometheus (/v1/sys/metrics?format=prometheus), sans nom d'hôte dans les noms.
telemetry {
  prometheus_retention_time = "24h"
  disable_hostname = true
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

# Brique 19b, D15 (a) du propriétaire (02/11/2026) : second device vers la sortie standard du conteneur, collecté par Alloy avec
# les journaux du pod. OpenBao ne refuse une requête que si aucun device ne peut l'écrire : le fichier sans rotation ne bloque
# plus seul les signatures quand son volume est plein (comportement documenté, non mesuré dans le PoC).
audit "file" "sortie" {
  description = "Journal d'audit sur la sortie standard (valeurs sensibles en HMAC), collecté par Alloy (brique 19b)"
  options {
    file_path = "stdout"
  }
}
