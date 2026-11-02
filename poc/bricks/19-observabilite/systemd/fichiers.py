#!/usr/bin/python3 -I
"""Brique 19, O2 (décisions 2 et 6 du propriétaire, 02/11/2026) : sert en lecture, sur 127.0.0.1:9101/metrics, la seule
concaténation des fichiers de métriques au format texte de Prometheus :
  /var/lib/synchro/<projet>/<projet>.prom   (brique 01, sync.py --metriques)
  /etc/fichiers-metriques/*.prom            (certificats.prom : dates d'expiration des certificats du PoC, écrit par
                                            observabilite.sh ; séries de test d'O4, retirées après chaque incident)
Aucun autre chemin n'est lu ; GET /metrics seulement ; bibliothèque standard seulement."""
import glob
import http.server

SOURCES = ["/var/lib/synchro/*/*.prom", "/etc/fichiers-metriques/*.prom"]


class Gestionnaire(http.server.BaseHTTPRequestHandler):
    server_version = "fichiers-metriques"
    sys_version = ""

    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        corps = []
        for motif in SOURCES:
            for chemin in sorted(glob.glob(motif)):
                try:
                    with open(chemin, "rb") as f:
                        corps.append(f.read())
                except OSError:
                    continue
        donnees = b"".join(c if c.endswith(b"\n") else c + b"\n" for c in corps)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(donnees)))
        self.end_headers()
        self.wfile.write(donnees)

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", 9101), Gestionnaire).serve_forever()
