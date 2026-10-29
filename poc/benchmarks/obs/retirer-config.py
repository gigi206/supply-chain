#!/usr/bin/env python3
# Banc A2 : utilisé par construire.sh avant d'archiver _buildenv dans resultats/.
# Remplace le texte de <config> (prjconf de build.opensuse.org, sans licence déclarée) par son sha256.
import hashlib, re, sys
for chemin in sys.argv[1:]:
    s = open(chemin, encoding="utf-8").read()
    def remplace(m):
        if m.group(1).startswith("retiré"):
            return m.group(0)
        h = hashlib.sha256(m.group(1).encode()).hexdigest()
        return f"<config>retiré : configuration de build (prjconf de build.opensuse.org, non versionné), sha256 {h}</config>"
    t = re.sub(r"<config>(.*?)</config>", remplace, s, flags=re.S)
    if t != s:
        open(chemin, "w", encoding="utf-8").write(t)
