# Brique 05, M5a (carte de M5 et décision « Ok » du 18/11/2026) : copies altérées de l'arbre entrees/ de construire-rpm.
# Même fichier pour le banc de l'hôte (python3 -I) et pour le pod runc (image outils-prefetch). Aucune dépendance hors de la
# bibliothèque standard.
#   faire SOURCE DEST : DEST/<cas>/entrees pour chaque cas, par liens durs depuis SOURCE (arbre entrees/ rempli par preparer-rpm),
#                       puis une altération par cas. Toute altération écrit un fichier neuf, puis le renomme sur le nom visé :
#                       le lien dur est rompu et SOURCE n'est jamais modifié. DEST ne doit pas exister.
#   comparer SOURCE DEST : sha256 de chaque fichier de SOURCE et de chaque copie ; imprime, par cas, les chemins qui diffèrent de
#                       SOURCE (contenu, absence, présence en plus). Code 1 si une copie diffère autrement que prévu.
#   empreinte SOURCE  : sha256 de la liste triée « sha256 chemin » de SOURCE (preuve que SOURCE est inchangé).
import hashlib, json, os, sys

CAS = ('intacte', 'r1', 'r2', 'r3', 'r4', 'r5', 'r6')
CIBLE = 'zlib-1.2.11-40.el9.x86_64.rpm'   # rpm de la mesure hors ligne (m5-sigmd5.sh) ; R1, R3 et R4
EN_TROP = 'm5-en-trop.rpm'                # R2 : fichier en trop à la racine de depot/, hors du verrou


def dossier_dir(entrees):
    j = json.load(open(os.path.join(entrees, 'verrou-rpm.json'), encoding='utf-8'))
    return j['config']['bootstrap_image'].split(':', 1)[0] + '@' + j['bootstrap']['pull_digest'], sorted(
        p['url'].rsplit('/', 1)[-1] for p in j['buildroot']['rpms'])


def gros_blob(entrees):
    dos, _ = dossier_dir(entrees)
    d = os.path.join(entrees, 'fermeture', 'depot', dos)
    f = [x for x in os.listdir(d) if x != 'manifest.json' and os.path.isfile(os.path.join(d, x))]
    return os.path.join('fermeture', 'depot', dos, max(sorted(f), key=lambda x: os.path.getsize(os.path.join(d, x))))


def attendus(entrees):
    """Chemins (relatifs à entrees/) qui diffèrent de SOURCE, par cas, et nature de l'écart."""
    dos, noms = dossier_dir(entrees)
    depot = os.path.join('fermeture', 'depot')
    assert CIBLE in noms, CIBLE
    return {'intacte': {}, 'r1': {os.path.join(depot, CIBLE): 'contenu'},
            'r2': {os.path.join(depot, EN_TROP): 'en plus'}, 'r3': {os.path.join(depot, CIBLE): 'absent'},
            'r4': {os.path.join(depot, CIBLE): 'contenu'}, 'r5': {os.path.join(depot, dos, 'manifest.json'): 'contenu'},
            'r6': {gros_blob(entrees): 'contenu'}}


def remplacer(chemin, octets):
    t = chemin + '.m5-neuf'
    with open(t, 'xb') as h:
        h.write(octets)
    os.chmod(t, os.stat(chemin).st_mode & 0o7777)
    os.rename(t, chemin)   # le nom pointe sur un inode neuf ; l'inode partagé n'est pas touché


def lier(src, dst):
    os.mkdir(dst, os.stat(src).st_mode & 0o7777)
    for racine, dirs, fichiers in os.walk(src):
        rel = os.path.relpath(racine, src)
        for x in sorted(dirs):
            s = os.path.join(racine, x)
            assert not os.path.islink(s), s
            os.mkdir(os.path.join(dst, rel, x), os.stat(s).st_mode & 0o7777)
        for x in sorted(fichiers):
            s = os.path.join(racine, x)
            assert os.path.isfile(s) and not os.path.islink(s), s
            os.link(s, os.path.join(dst, rel, x))


def faire(src, dest):
    _, noms = dossier_dir(src)
    att = attendus(src)
    dos, _ = dossier_dir(src)
    depot = os.path.join('fermeture', 'depot')
    os.mkdir(dest)
    for c in CAS:
        os.mkdir(os.path.join(dest, c))
        e = os.path.join(dest, c, 'entrees')
        lier(src, e)
        cible = os.path.join(e, depot, CIBLE)
        if c == 'r1':   # contenu d'un autre rpm réel du verrou, sous le nom de la cible
            autre = [n for n in noms if n != CIBLE][0]
            remplacer(cible, open(os.path.join(e, depot, autre), 'rb').read())
            print(f'r1 : {CIBLE} remplacé par le contenu de {autre}')
        elif c == 'r2':
            with open(os.path.join(e, depot, EN_TROP), 'xb') as h:
                h.write(b'M5a : fichier en trop dans la fermeture\n')
            print(f'r2 : {EN_TROP} ajouté à la racine de depot/')
        elif c == 'r3':
            os.unlink(cible)   # retire le nom de la copie seulement
            print(f'r3 : {CIBLE} retiré')
        elif c == 'r4':   # un octet du payload inversé, en-tête intact (même décalage que m5-sigmd5.sh)
            b = bytearray(open(cible, 'rb').read()); o = len(b) - 4096; b[o] ^= 0xff
            remplacer(cible, bytes(b))
            print(f'r4 : {CIBLE}, octet {o} inversé, taille inchangée ({len(b)} octets)')
        elif c == 'r5':   # manifest.json du dossier dir: suivi d'un saut de ligne (JSON toujours valide)
            m = os.path.join(e, depot, dos, 'manifest.json')
            remplacer(m, open(m, 'rb').read() + b'\n')
            print('r5 : manifest.json du dossier dir: suivi d\'un saut de ligne')
        elif c == 'r6':   # un octet inversé au milieu du plus gros blob du dossier dir:, manifest.json intact
            f = os.path.join(e, att['r6'].popitem()[0])
            b = bytearray(open(f, 'rb').read()); o = len(b) // 2; b[o] ^= 0xff
            remplacer(f, bytes(b))
            print(f'r6 : {os.path.relpath(f, e)}, octet {o} inversé, taille inchangée ({len(b)} octets)')


def empreintes(racine):
    r = {}
    for d, _, fichiers in os.walk(racine):
        for x in fichiers:
            f = os.path.join(d, x)
            h = hashlib.sha256()
            with open(f, 'rb') as g:
                for b in iter(lambda: g.read(1 << 20), b''):
                    h.update(b)
            r[os.path.relpath(f, racine)] = h.hexdigest()
    return r


def comparer(src, dest):
    s = empreintes(src)
    att = attendus(src)
    ko = 0
    print(f'source : {len(s)} fichiers, empreinte {empreinte(s)}')
    for c in CAS:
        e = empreintes(os.path.join(dest, c, 'entrees'))
        ecarts = {}
        for p in sorted(set(s) | set(e)):
            if p not in e:
                ecarts[p] = 'absent'
            elif p not in s:
                ecarts[p] = 'en plus'
            elif e[p] != s[p]:
                ecarts[p] = 'contenu'
        ok = ecarts == att[c]
        ko += not ok
        print(f'{"OK  " if ok else "KO  "} {c} : {len(e)} fichiers ; écarts à la source : '
              + (', '.join(f'{p} ({n})' for p, n in ecarts.items()) or 'aucun'))
    return ko


def empreinte(d):
    return hashlib.sha256(''.join(f'{v} {k}\n' for k, v in sorted(d.items())).encode()).hexdigest()


if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'faire':
        assert not os.path.exists(sys.argv[3]), sys.argv[3]
        faire(sys.argv[2], sys.argv[3])
    elif mode == 'comparer':
        sys.exit(1 if comparer(sys.argv[2], sys.argv[3]) else 0)
    elif mode == 'empreinte':
        print(empreinte(empreintes(sys.argv[2])))
    else:
        sys.exit(f'mode inconnu : {mode}')
