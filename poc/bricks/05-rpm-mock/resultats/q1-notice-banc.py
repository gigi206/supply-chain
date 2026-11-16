"""Banc hors réseau du brouillon de spec (Q1 de la brique 05). Prouve le contenu, PAS la lecture du spec par rpm
(rpmbuild et rpmspec absents de l'hôte) : forme non éprouvée avant le premier build.
Usage : python3 -I banc.py <spec actuel> <brouillon> <goroot> <debian/copyright> <dossier de travail vide>"""
import difflib
import hashlib
import os
import subprocess
import sys

actuel, brouillon, goroot, copyright_deb, w = sys.argv[1:6]
ko = 0


def tenue(nom, ok, detail=''):
    global ko
    ko += not ok
    print(f"{'tenue    ' if ok else 'NON TENUE'} {nom}{' : ' + detail if detail else ''}")


def h(b):
    return hashlib.sha256(b).hexdigest()


A = open(actuel, encoding='utf-8', newline='').read().split('\n')
B = open(brouillon, encoding='utf-8', newline='').read().split('\n')
SHA = {'golang-LICENSE': '911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad',
       'golang-PATENTS': '96f408bfae65bf137fc2525d3ecb030271c50c1e90799f87abf8846d8dd505cc'}

# Q1 : seules différences : Release, %prep (après %autosetup), ligne %license, entrée de changelog
d = [s for s in difflib.unified_diff(A, B, lineterm='', n=0) if s[:1] in '+-' and not s.startswith(('+++', '---'))]
moins = [s[1:] for s in d if s[0] == '-']
tenue('Q1 lignes retirées : Release 1 et ligne %license seulement', moins == [
    'Release:        1%{?dist}',
    '%license LICENSES/Apache-2.0.txt vendor/github.com/go-chi/chi/v5/LICENSE web/node_modules/marked/LICENSE.md'], repr(moins))
i, j = B.index('%autosetup'), B.index('%build')
plus_hors_prep = [s[1:] for s in d if s[0] == '+' and s[1:] not in B[i + 1:j] and s[1:] != '']
c = B.index('%changelog')
tenue('Q1 entrée de changelog suivie d\'une ligne vide puis de l\'entrée 1.0.0-1', B[c + 4] == '' and B[c + 5].endswith(' - 1.0.0-1'), repr(B[c + 4:c + 6]))
tenue('Q1 lignes ajoutées hors %prep : Release 2, %license, changelog', len(plus_hors_prep) == 5
      and plus_hors_prep[0] == 'Release:        2%{?dist}' and plus_hors_prep[1].endswith(' golang-LICENSE golang-PATENTS golang-NOTICES')
      and plus_hors_prep[2].startswith('* ') and plus_hors_prep[2].endswith(' - 1.0.0-2'), repr(plus_hors_prep))

# Q2 : % dans les ajouts seulement là où attendu
pct = [s[1:] for s in d if s[0] == '+' and '%' in s]
tenue('Q2 « % » ajouté seulement dans Release et %license', len(pct) == 2, repr(pct))

# Q3 : noms de base distincts dans %license (rpm copie par cp -pr dans le dossier de licences : build.log d'OBS l. 924-926)
lic = [s for s in B if s.startswith('%license ')]
noms = [os.path.basename(p) for p in lic[0].split()[1:]] if len(lic) == 1 else []
tenue('Q3 une ligne %license, noms de base distincts', len(lic) == 1 and len(noms) == len(set(noms)) == 6, repr(noms))

# Q4 : here-docs entre apostrophes, corps sans % ni CR ni espace final ni ligne « # » ou « % », délimiteur absent du corps
prep = B[i + 1:j]
blocs, k = {}, 0
while k < len(prep):
    s = prep[k]
    if s.startswith('cat > '):
        nom, fin = s.split()[2], s.split("<<'")[1].rstrip("'")
        tenue(f'Q4 {nom} : délimiteur entre apostrophes', s == f"cat > {nom} <<'{fin}'", s)
        e = prep.index(fin, k + 1)
        corps = prep[k + 1:e]
        tenue(f'Q4 {nom} : corps propre ({len(corps)} lignes)', all('%' not in c and '\r' not in c and c == c.rstrip()
              and c != fin and not c.startswith(('#', '%')) for c in corps))
        blocs[nom] = corps
        k = e + 1
    else:
        tenue('Q4 ligne hors here-doc : commentaire sans %, ou ligne vide d\'origine avant %build', (s.startswith('# ') and '%' not in s) or (s == '' and k == len(prep) - 1), repr(s))
        k += 1
tenue('Q4 trois here-docs', sorted(blocs) == ['golang-LICENSE', 'golang-NOTICES', 'golang-PATENTS'], repr(sorted(blocs)))

# Q5 : le shell du %prep, exécuté par bash dans un dossier vide, produit les fichiers attendus
assert os.path.isdir(w) and not os.listdir(w), w
r = subprocess.run(['bash', '-e', '-u', '-o', 'pipefail', '-c', '\n'.join(prep) + '\n'], cwd=w, capture_output=True)
tenue('Q5 bash du %prep : code 0, aucune sortie', r.returncode == 0 and not r.stdout and not r.stderr, repr((r.returncode, r.stderr[:200])))
for nom, attendu in SHA.items():
    b = open(f'{w}/{nom}', 'rb').read()
    tenue(f'Q5 {nom} : sha256 attendu', h(b) == attendu, h(b))
    tenue(f'Q5 {nom} : égal au fichier de Go', b == open(f"{goroot}/{nom.split('-')[1]}", 'rb').read())
n = open(f'{w}/golang-NOTICES', 'rb').read()
print(f'         golang-NOTICES : {len(n)} octets, sha256 {h(n)}')

# Q6 : NOTICES : attributions = lignes du Comment: du deb (paragraphes 8 et 9), X11 = en-tête de memmove_amd64.s
t = n.decode('utf-8').split('\n')
cop = [s[1:] for s in open(copyright_deb, encoding='utf-8').read().split('\n') if s.startswith(' ')]
for p in (8, 9):
    ti = f'Paragraphe {p} du copyright de golang-1.24-src (License: Go) :'
    a = cop[cop.index(ti) + 1:cop.index(ti) + 3]
    tenue(f'Q6 paragraphe {p} du deb présent tel quel', any(t[x:x + 2] == a for x in range(len(t))), repr(a))
mm = open(f'{goroot}/src/runtime/memmove_amd64.s', encoding='utf-8').read().split('\n')[:24]
x = [s[3:] if s.startswith('// ') else '' for s in mm]
tenue('Q6 notice X11 = lignes 1 à 24 de memmove_amd64.s sans « // »', t[-25:-1] == x and t[-1] == '', repr(t[-3:]))
tenue('Q6 notice X11 : permission et garantie présentes',
      'Permission is hereby granted, free of charge, to any person obtaining a copy' in t and 'THE SOFTWARE.' in t)
print(f"# {'code 0' if not ko else f'{ko} NON TENUE(S)'}")
sys.exit(1 if ko else 0)
