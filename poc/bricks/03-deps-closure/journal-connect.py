#!/usr/bin/env python3
# Brique 03, F1 : proxy HTTPS (méthode CONNECT seulement) qui journalise chaque destination demandée, pour relever les noms
# contactés par un prefetch (règle toFQDNs de D2). Toute autre méthode est refusée (405) et journalisée : une requête en clair
# ou une connexion qui contourne le proxy se voit donc, la seconde par la trace strace des connect().
# Usage : python3 -I journal-connect.py <port> <journal>   (écoute sur 127.0.0.1 seulement)
import socket
import sys
import threading
import time


def journal(f, verrou, texte):
    with verrou:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {texte}\n")
        f.flush()


def relayer(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d:
                break
            b.sendall(d)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def servir(c, f, verrou):
    try:
        tete = b""
        while b"\r\n\r\n" not in tete and len(tete) < 65536:
            d = c.recv(4096)
            if not d:
                return
            tete += d
        ligne = tete.split(b"\r\n", 1)[0].decode("latin-1")
        morceaux = ligne.split()
        if len(morceaux) != 3 or morceaux[0] != "CONNECT":
            journal(f, verrou, f"REFUS {ligne[:200]}")
            c.sendall(b"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n")
            return
        hote, _, port = morceaux[1].rpartition(":")
        try:
            s = socket.create_connection((hote, int(port)), timeout=30)
        except (OSError, ValueError) as e:
            journal(f, verrou, f"ECHEC {morceaux[1]} {e}")
            c.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            return
        journal(f, verrou, f"CONNECT {morceaux[1]}")
        c.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
        s.settimeout(None)
        c.settimeout(None)
        t = threading.Thread(target=relayer, args=(s, c), daemon=True)
        t.start()
        relayer(c, s)
        t.join()
    except OSError as e:
        journal(f, verrou, f"ERREUR {e}")
    finally:
        c.close()


def main():
    port, chemin = int(sys.argv[1]), sys.argv[2]
    verrou = threading.Lock()
    with open(chemin, "a", encoding="utf-8") as f:
        l = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        l.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        l.bind(("127.0.0.1", port))
        l.listen(128)
        journal(f, verrou, f"ECOUTE 127.0.0.1:{port}")
        while True:
            c, _ = l.accept()
            c.settimeout(60)
            threading.Thread(target=servir, args=(c, f, verrou), daemon=True).start()


if __name__ == "__main__":
    main()
