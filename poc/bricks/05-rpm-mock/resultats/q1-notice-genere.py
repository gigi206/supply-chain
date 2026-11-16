"""Brouillon à sec du spec rpm (Q1 de la brique 05) : notices de Go écrites en %prep par here-doc, Release 2.
Lit le spec du dépôt, debian/copyright et les sources de Go ; n'écrit que <sortie>. Aucun fichier du dépôt n'est modifié.
Usage : python3 -I genere.py <racine> <goroot> <date du changelog, LC_ALL=C date -u '+%a %b %d %Y'> <sortie>"""
import re
import sys

racine, goroot, jour, sortie = sys.argv[1:5]
assert re.fullmatch(r'(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d\d 20\d\d', jour), jour


def lire(p):
    return open(p, encoding='utf-8', newline='').read()


spec = lire(f'{racine}/poc/packaging/sample-app.spec')
L = spec.split('\n')
assert spec.endswith('\n') and '\r' not in spec
assert L[8] == 'Release:        1%{?dist}', L[8]
assert L[21] == '%autosetup' and L[20] == '%prep' and L[22] == '' and L[23] == '%build', L[20:24]
LIC = '%license LICENSES/Apache-2.0.txt vendor/github.com/go-chi/chi/v5/LICENSE web/node_modules/marked/LICENSE.md'
assert L[34] == LIC and L[37] == '%changelog', (L[34], L[37])
assert spec.count('1.0.0-1') == 1 and 'golang-' not in spec

# 1. textes de Go à l'octet près
lic, pat = lire(f'{goroot}/LICENSE'), lire(f'{goroot}/PATENTS')
# 2. attributions des paragraphes 8 et 9 du Comment: de debian/copyright (lignes suivant leur titre, jusqu'à « . »)
cop = lire(f'{racine}/poc/packaging/debian/copyright').split('\n')


def paragraphe(n):
    t = f' Paragraphe {n} du copyright de golang-1.24-src (License: Go) :'
    assert cop.count(t) == 1, t
    i = cop.index(t) + 1
    out = []
    while cop[i] != ' .':
        assert cop[i].startswith(' ') and not cop[i].startswith('  '), cop[i]
        out.append(cop[i][1:])
        i += 1
    assert len(out) == 2, out
    return out


p8, p9 = paragraphe(8), paragraphe(9)
# 3. en-tête X11 de runtime/memmove_amd64.s : lignes 1 à 24, « // » et « // » retirés
mm = lire(f'{goroot}/src/runtime/memmove_amd64.s').split('\n')
assert mm[23] == '// THE SOFTWARE.' and mm[24] == '' and mm[25] == '//go:build !plan9', mm[23:26]
x11 = []
for s in mm[:24]:
    assert s == '//' or s.startswith('// '), s
    x11.append(s[3:] if s.startswith('// ') else '')

notices = '\n'.join([
    'Notices de la bibliothèque standard de Go, liée statiquement dans /usr/bin/sample-app.',
    'Elle vient du paquet golang installé dans le buildroot de construction.',
    'Texte de la licence de Go : golang-LICENSE ; licence de brevets de Go : golang-PATENTS.',
    '',
    'Attributions reprises du copyright Debian de golang-1.24-src 1.24.4-1 (paragraphes 8 et 9, License: Go),',
    'comme dans le debian/copyright du paquet deb de sample-app :',
    *p8, '', *p9,
    '',
    'Notice X11 de runtime/memmove_amd64.s (en-tête du fichier dans Go 1.24.7) :',
    '',
    *x11,
]) + '\n'

blocs = [('golang-LICENSE', 'FIN_GOLANG_LICENSE', lic), ('golang-PATENTS', 'FIN_GOLANG_PATENTS', pat),
         ('golang-NOTICES', 'FIN_GOLANG_NOTICES', notices)]
prep = ['# Notices de Go portées par le packaging (décision Q1 de la brique 05, 16/11/2026) : textes écrits ici, non copiés',
        '# du buildroot ; golang-LICENSE et golang-PATENTS sont la LICENSE et le PATENTS de Go à l\'octet près.']
for nom, fin, texte in blocs:
    corps = texte.split('\n')[:-1]
    for s in corps:
        assert '%' not in s and '\r' not in s and s == s.rstrip() and s != fin and not s.startswith(('#', '%')), (nom, s)
    prep += [f"cat > {nom} <<'{fin}'", *corps, fin]

N = L[:8] + ['Release:        2%{?dist}'] + L[9:22] + prep + L[22:34] + [LIC + ' golang-LICENSE golang-PATENTS golang-NOTICES'] \
    + L[35:38] + [f'* {jour} Contributeurs de gigi206/supply-chain <poc@supply-chain.invalid> - 1.0.0-2',
                  '- Notices de la bibliothèque standard de Go portées dans le paquet : golang-LICENSE, golang-PATENTS,',
                  '  golang-NOTICES (attributions des paragraphes 8 et 9 du deb, notice X11 de runtime/memmove_amd64.s)',
                  ''] + L[38:]
nouveau = '\n'.join(N)
ajouts = [s for s in N if s not in L]
for s in ajouts:
    assert '%' not in s or s in ('Release:        2%{?dist}', LIC + ' golang-LICENSE golang-PATENTS golang-NOTICES'), s
open(sortie, 'w', encoding='utf-8', newline='').write(nouveau)
print(f'écrit : {sortie} ({len(N)} lignes contre {len(L)})')
