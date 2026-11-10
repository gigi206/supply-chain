#!/usr/bin/env python3
"""Exec direct sur l'API de kubelet (sans apiserver), par WebSocket, protocole v5.channel.k8s.io, bibliothèque standard seule.

Diagnostic de la brique 06 (diag-exec-kata.sh, étape kubelet). Lancé sur sc-confiance par « sudo python3 -I - <arguments> », script
sur l'entrée standard. Le certificat et la clé client de l'apiserver vers kubelet sont utilisés pour le TLS, jamais affichés.
Le certificat de kubelet n'est pas vérifié, comme par l'apiserver (CIS 1.2.5 en échec : --kubelet-certificate-authority absent).

Arguments : hôte port espace pod conteneur mode(lent|rapide) octets certificat clé délai
Sortie : une ligne « code … en … ms ; statut … ; octets envoyés … ».
"""
import base64
import json
import os
import socket
import ssl
import struct
import sys
import time
import urllib.parse

LENT = ('for i in $(seq 1 128); do dd bs=1M count=1 iflag=fullblock status=none || exit 1; sleep 0.1; done > /w/k')


def trame(opcode, donnees):
    """Trame WebSocket client (masquée), FIN posé."""
    entete = bytes([0x80 | opcode])
    n = len(donnees)
    if n < 126:
        entete += bytes([0x80 | n])
    elif n < 65536:
        entete += bytes([0x80 | 126]) + struct.pack('!H', n)
    else:
        entete += bytes([0x80 | 127]) + struct.pack('!Q', n)
    masque = os.urandom(4)
    if not n:
        return entete + masque
    # XOR par entier (rapide) : l'envoi doit rester plus rapide que la lecture lente du pod (environ 10 Mio/s)
    m = (masque * (n // 4 + 1))[:n]
    return entete + masque + (int.from_bytes(donnees, 'big') ^ int.from_bytes(m, 'big')).to_bytes(n, 'big')


def lire_exact(s, n):
    b = b''
    while len(b) < n:
        x = s.recv(n - len(b))
        if not x:
            raise EOFError('connexion fermée')
        b += x
    return b


def lire_trame(s):
    """Trame du serveur (non masquée) : (opcode, données)."""
    a, b = lire_exact(s, 2)
    n = b & 0x7F
    if n == 126:
        n = struct.unpack('!H', lire_exact(s, 2))[0]
    elif n == 127:
        n = struct.unpack('!Q', lire_exact(s, 8))[0]
    if b & 0x80:
        m = lire_exact(s, 4)
        d = bytes(x ^ m[i % 4] for i, x in enumerate(lire_exact(s, n)))
    else:
        d = lire_exact(s, n)
    return a & 0x0F, d


def principal(hote, port, espace, pod, conteneur, mode, octets, cert, cle, delai):
    octets, delai = int(octets), float(delai)
    commande = LENT if mode == 'lent' else f'head -c {octets} > /w/k'
    q = urllib.parse.urlencode([('command', 'sh'), ('command', '-c'), ('command', commande),
                                ('input', '1'), ('output', '1'), ('error', '1')])
    chemin = f'/exec/{espace}/{pod}/{conteneur}?{q}'
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    ctx.load_cert_chain(cert, cle)
    t0 = time.monotonic()
    brut = socket.create_connection((hote, int(port)), timeout=delai)
    s = ctx.wrap_socket(brut, server_hostname=hote)
    s.settimeout(delai)
    cle_ws = base64.b64encode(os.urandom(16)).decode()
    s.sendall((f'GET {chemin} HTTP/1.1\r\nHost: {hote}:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
               f'Sec-WebSocket-Key: {cle_ws}\r\nSec-WebSocket-Version: 13\r\n'
               f'Sec-WebSocket-Protocol: v5.channel.k8s.io\r\n\r\n').encode())
    rep = b''
    while b'\r\n\r\n' not in rep:
        rep += lire_exact(s, 1)
    ligne = rep.split(b'\r\n', 1)[0].decode(errors='replace')
    if ' 101 ' not in ligne:
        # Corrigé à 19:59 UTC, NON REJOUÉ : corps de la réponse ajouté (300 caractères au plus), pour lire le motif d'un refus
        s.settimeout(5)
        try:
            corps = s.recv(4096).decode(errors='replace').replace('\r', ' ').replace('\n', ' ')[:300]
        except (socket.timeout, OSError):
            corps = ''
        # Corrigé à 20:01 UTC, NON REJOUÉ : en-têtes de la réponse ajoutés (corps vide au rejeu de 20:00 UTC)
        entetes = ' | '.join(x.decode(errors='replace') for x in rep.split(b'\r\n')[1:] if x)[:300]
        print(f'code 1 en {int((time.monotonic() - t0) * 1000)} ms ; réponse : {ligne} ; en-têtes : {entetes} ; corps : {corps}')
        return 1
    envoyes, morceau = 0, 65536
    try:
        while envoyes < octets:
            k = min(morceau, octets - envoyes)
            s.sendall(trame(2, b'\x00' + os.urandom(k)))       # canal 0 : stdin
            envoyes += k
            if time.monotonic() - t0 > delai:
                raise TimeoutError('délai dépassé pendant l\'envoi')
        s.sendall(trame(2, b'\xff\x00'))                       # canal 255 (v5) : fermeture de stdin
        statut = None
        while True:
            if time.monotonic() - t0 > delai:
                raise TimeoutError('délai dépassé en attente de la fin')
            op, d = lire_trame(s)
            if op == 8:                                         # fermeture
                break
            if op == 9:                                         # ping
                s.sendall(trame(10, d))
                continue
            if op in (1, 2) and d[:1] == b'\x03' and len(d) > 1:   # canal 3 : statut
                statut = json.loads(d[1:].decode(errors='replace'))
        code = 0
        resume = (statut or {}).get('status', 'absent')
    except (TimeoutError, socket.timeout) as e:
        code, resume = 124, f'délai ({e})'
    except EOFError:
        code, resume = 0, 'connexion fermée par kubelet'
    print(f'code {code} en {int((time.monotonic() - t0) * 1000)} ms ; statut {resume} ; octets envoyés {envoyes} sur {octets}')
    return code


if __name__ == '__main__':
    sys.exit(principal(*sys.argv[1:]))
