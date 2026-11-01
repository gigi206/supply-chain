# Brique 08, J8 (réserve C) : politique/reserve-c/ivpol.tmpl.yaml rendue pour un cas. Lancé par preuves.sh (etape_reserve_c), python3 -I.
# Arguments : gabarit clé-publique taches.yml policy.yaml nom glob dépôt-des-bundles url-source révision mode (decision|diagnostic).
# Liste revue (ancien format trusted_tasks) et allowed_builder_ids lus dans les fichiers de la porte ; sortie sur stdout.
import sys, json, re
tmpl, pub, taches, pol, nom, glob, bundles, url, rev, mode = sys.argv[1:11]
t = open(tmpl).read()
k = ''.join('            ' + l + '\n' for l in open(pub).read().strip().splitlines())
# liste revue (ancien format trusted_tasks) : clé -> [ref]
cur = None; tt = {}
for l in open(taches):
    m = re.match(r'^  (oci://\S+):\s*$', l)
    if m: cur = m.group(1); tt[cur] = []; continue
    m = re.match(r'^\s+- ref: (\S+)', l)
    if m and cur: tt[cur].append(m.group(1))
b = []; inb = False
for l in open(pol):
    if re.match(r'^\s+allowed_builder_ids:', l): inb = True; continue
    if inb:
        m = re.match(r'^\s+- (\S+)', l)
        if m: b.append(m.group(1))
        elif l.strip() and not l.strip().startswith('#'): inb = False
cel = lambda v: json.dumps(v).replace('"', "'")
val = {'decision': '''    - expression: "variables.regles.all(c, variables.regles[c])"
      messageExpression: "'reserve-c : ' + variables.lignes.filter(r, r.endsWith('=ko')).join(' ')"''',
       'diagnostic': '''    - expression: "false"
      messageExpression: "'DIAG ' + variables.st.predicate.?runDetails.?metadata.?invocationId.orValue('-') + ' ' + variables.lignes.join(' ')"'''}[mode]
for a, v in [('__CHAINS_PUB__\n', k), ('__NOM__', nom), ('__GLOB__', glob), ('__BUNDLES__', bundles), ('__BUILDERS__', cel(b)),
             ('__TACHES__', cel(tt)), ('__SOURCE_URL__', url), ('__SOURCE_REV__', rev), ('__VALIDATION__', val)]:
    t = t.replace(a, v)
assert '__' not in re.sub(r'#.*', '', t), 'marqueur restant'
print(t, end='')
