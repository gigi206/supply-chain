#!/usr/bin/env python3
"""Brique 20, étape 4 : banc de lecteur_loki.py contre un serveur HTTPS factice (réponses à la forme de /api/ds/query). Grafana et Loki ne
sont pas exercés ici. Usage (banc.sh) : lecteur_banc.py <lecteur_loki.py>   (CA et T dans l'environnement ; certificat du Zot jetable)"""
import base64
import http.server
import json
import os
import ssl
import subprocess
import sys
import threading

T, CA = os.environ["T"], os.environ["CA"]
RESUME, KEV = "entrées builds/scan/x=1@2026-11-01T00:00:00Z (liste émise)", '{"depot":"builds/scan/x","kev":true}'
mode, vues = "", []


def cadre(lignes):
    return {"schema": {"fields": [{"name": "labels"}, {"name": "Time"}, {"name": "Line"}, {"name": "tsNs"}]},
            "data": {"values": [[{}] * len(lignes), [1] * len(lignes), lignes, ["1"] * len(lignes)]}}


class Factice(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        corps = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        q = corps["queries"][0]
        vues.append((self.headers["Authorization"], int(corps["to"]) - int(corps["from"]), q["expr"]))
        lignes = [RESUME] if "liste émise" in q["expr"] else [KEV]
        a = {"frames": [cadre(lignes), {"schema": {"fields": []}, "data": {"values": []}}]}
        if mode == "tronqué":
            a = {"frames": [cadre(lignes * 2500), cadre(lignes * 2500)]}
        if mode == "erreur":
            a = {"error": "x", "status": 500, "frames": []}
        if mode == "sans frames":
            a = {"status": 200}
        if mode == "saut de ligne":
            a = {"frames": [cadre(["a\nb"])]}
        corps = b"{" if mode == "JSON coupé" else b'{"results":{}}' if mode == "sans A" else json.dumps({"results": {"A": a}}).encode()
        self.send_response(401 if mode == "401" else 200)
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def log_message(self, *a):
        pass


serveur = http.server.HTTPServer(("127.0.0.1", 15021), Factice)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CA, f"{T}/cle/zot.key")
serveur.socket = ctx.wrap_socket(serveur.socket, server_side=True)
threading.Thread(target=serveur.serve_forever, daemon=True).start()
with open(f"{T}/mdp", "w", encoding="utf-8") as f:
    f.write("essai\n")
sortie, n, ko = f"{T}/lignes", 0, 0
for mode, code, attendu in (("bon", 0, f"{RESUME}\n{KEV}\n"), ("sans frames", 0, ""), ("tronqué", 2, "avant\n"), ("erreur", 2, "avant\n"),
                            ("saut de ligne", 2, "avant\n"), ("JSON coupé", 2, "avant\n"), ("sans A", 2, "avant\n"), ("401", 2, "avant\n"),
                            ("sans mot de passe", 2, "avant\n"), ("arrêté", 2, "avant\n")):
    if mode == "sans mot de passe":
        os.remove(f"{T}/mdp")
    if mode == "arrêté":
        with open(f"{T}/mdp", "w", encoding="utf-8") as f:
            f.write("essai\n")
        serveur.shutdown()
        serveur.server_close()
    with open(sortie, "w", encoding="utf-8") as f:
        f.write("avant\n")
    r = subprocess.run(["/usr/bin/python3", "-I", sys.argv[1]], capture_output=True, text=True, env={
        "GRAFANA": "https://127.0.0.1:15021", "CA": CA, "UTILISATEUR": "lecteur", "MDP": f"{T}/mdp", "SORTIE": sortie})
    with open(sortie, encoding="utf-8") as f:
        lu = f.read()
    bon = r.returncode == code and lu == attendu and "essai" not in r.stdout + r.stderr
    n, ko = n + 1, ko + (not bon)
    print(f"{'OK  ' if bon else 'KO  '} lecteur, réponse « {mode} » : code {r.returncode}, {(r.stdout + r.stderr).strip()}")
bon = vues[0][:2] == ("Basic " + base64.b64encode(b"lecteur:essai").decode(), 719 * 3600 * 1000) and vues[1][2].endswith('|= "\\"kev\\":true"')
n, ko = n + 1, ko + (not bon)
print(f"{'OK  ' if bon else 'KO  '} lecteur : authentification, fenêtre de 719 h et requête des KEV envoyées\n## bilan du lecteur : {n} cas, {ko} écart(s)")
sys.exit(1 if ko else 0)
