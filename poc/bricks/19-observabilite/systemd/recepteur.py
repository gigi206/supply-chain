#!/usr/bin/python3 -I
"""Brique 19, O2 (D4 du propriétaire, 02/11/2026) : récepteur webhook local d'Alertmanager sur 127.0.0.1:9095/alerte.
Journalise une ligne JSON par alerte reçue (statut, nom, début, fin) dans le journal de l'unité ; aucune autre action."""
import http.server
import json
import sys


class Gestionnaire(http.server.BaseHTTPRequestHandler):
    server_version = "recepteur-alertes"
    sys_version = ""

    def do_POST(self):
        if self.path != "/alerte":
            self.send_error(404)
            return
        n = int(self.headers.get("Content-Length", "0"))
        if n > 1 << 20:
            self.send_error(413)
            return
        try:
            charge = json.loads(self.rfile.read(n))
        except ValueError:
            self.send_error(400)
            return
        for a in charge.get("alerts", []):
            print(json.dumps({"recu": True, "statut": a.get("status"), "alerte": a.get("labels", {}).get("alertname"),
                              "etiquettes": a.get("labels", {}), "debut": a.get("startsAt"), "fin": a.get("endsAt")},
                             ensure_ascii=False, sort_keys=True), flush=True)
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


sys.stdout.reconfigure(line_buffering=True)
http.server.HTTPServer(("127.0.0.1", 9095), Gestionnaire).serve_forever()
