#!/usr/bin/env python3
"""Banc A2 : pilote la console série d'une VM libvirt (virsh console dans un pty, bibliothèque standard).

Usage : console.py <domaine> <fichier de commandes>
Le fichier de commandes contient une commande shell par ligne, exécutée en root après connexion.
Variables d'environnement :
  CONSOLE_MDP     mot de passe de connexion root (lu dans l'environnement, jamais affiché) ;
  CONSOLE_DELAI   attente maximale de l'invite de connexion, en secondes (1800 par défaut).
Le journal (stdout) ne contient ni le mot de passe ni les commandes marquées « # secret ».
"""
import codecs
import os
import pty
import re
import select
import sys
import time

dom, fichier = sys.argv[1], sys.argv[2]
mdp = os.environ["CONSOLE_MDP"]
delai = int(os.environ.get("CONSOLE_DELAI", "1800"))
commandes = [l.rstrip("\n") for l in open(fichier, encoding="utf-8") if l.strip() and not l.startswith("#")]

pid, fd = pty.fork()
if pid == 0:
    os.execvp("virsh", ["virsh", "-c", "qemu:///system", "console", "--force", dom])

tampon = ""
decodeur = codecs.getincrementaldecoder("utf-8")("replace")   # caractères coupés entre deux lectures
ANSI = re.compile(r"\x1b(\[[0-9;?]*[A-Za-z]|\([0-9A-Za-z])")   # couleurs de l'invite, jeux de caractères


def lire(motif, attente):
    """Lit la console jusqu'au motif (expression régulière) ; renvoie le texte lu."""
    global tampon
    fin = time.monotonic() + attente
    while time.monotonic() < fin:
        m = re.search(motif, tampon)
        if m:
            lu, tampon = tampon[: m.end()], tampon[m.end():]
            return lu
        r, _, _ = select.select([fd], [], [], 5)
        if r:
            try:
                tampon += ANSI.sub("", decodeur.decode(os.read(fd, 65536)))
            except OSError:
                break
    raise TimeoutError(f"motif {motif!r} non vu en {attente} s ; fin du tampon : {tampon[-400:]!r}")


def envoyer(texte):
    os.write(fd, texte.encode())


def afficher(texte):
    sys.stdout.write(texte.replace("\r", ""))
    sys.stdout.flush()


debut = time.monotonic()
fin = debut + delai
while True:
    envoyer("\r")
    try:
        invite = lire(r"(login: ?|# ?)$", 15)
        break
    except TimeoutError:
        if time.monotonic() > fin:
            raise
if invite.rstrip().endswith("#"):
    print(f"[console] session root déjà ouverte (après {time.monotonic() - debut:.0f} s)")
else:
    print(f"[console] invite de connexion après {time.monotonic() - debut:.0f} s")
    envoyer("root\r")
    lire(r"[Pp]assword: ?$", 30)
    envoyer(mdp + "\r")
    lire(r"# ?$", 60)
envoyer("export PS1='# ' TERM=dumb; stty -echo\r")
lire(r"# ?$", 30)
for c in commandes:
    secret = c.endswith("# secret")
    if secret:
        c = c[: -len("# secret")].rstrip()
    print(f"[console] $ {'(commande masquée)' if secret else c}")
    envoyer(f"{c}; echo __code=$?__\r")
    sortie = lire(r"__code=\d+__", 600)
    code = re.search(r"__code=(\d+)__", sortie).group(1)
    if not secret:
        afficher(sortie[: sortie.rfind("__code=")])
    print(f"[console] code {code}")
    lire(r"# ?$", 30)
    if code != "0":
        envoyer("exit\r")
        sys.exit(f"échec de la commande (code {code})")
envoyer("exit\r")
time.sleep(1)
os.kill(pid, 15)
