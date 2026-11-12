#!/usr/bin/env bash
# Essai hors réseau des deux pièces neuves de releve6 (m2.sh), écrit le 12/11/2026 avant tout passage : le script Python qui
# rejoue le remplacement de s1.sh, sur un rocky-9.tpl synthétique, et la fonction awk « fonction », sur un fichier Python
# synthétique. Ni l'archive de mock ni le vrai rocky-9.tpl ne sont lus. Usage : m2-releve6-essai-local.sh <racine du dépôt> <dossier vidé>
set -u
D=$1; H=$2
rm -rf -- "${H:?}"; mkdir -p "$H"
sed -n "/^  python3 -I -u - .*<<'PY'/,/^PY\$/p" "$D/poc/bricks/05-rpm-mock/m2.sh" | sed '1d;$d' > "$H/releve6.py"
echo "script Python extrait de m2.sh : $(wc -l < "$H/releve6.py") lignes"
V=$(sed -n 's|^VAULT97=\(https://[A-Za-z0-9./-]*\)$|\1|p' "$D/poc/bricks/05-rpm-mock/s1.sh")
M='mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=$basearch&repo'
cat > "$H/rocky-9.tpl" <<TPL
config_opts['chroot_setup_cmd'] = 'install bash'
config_opts['dnf.conf'] = """
[main]
reposdir=/dev/null
gpgcheck=1

[baseos]
name=BaseOS
$M=BaseOS-\$releasever
enabled=1

[appstream]
$M=AppStream-\$releasever
enabled=1

[crb]
$M=CRB-\$releasever
enabled=0

[extras]
$M=extras-\$releasever
enabled=1

[plus]
$M=plus-\$releasever

[devel]
$M=devel-\$releasever
enabled=0
"""
TPL
echo "== cas nominal"; python3 -I -u "$H/releve6.py" "$H/rocky-9.tpl" "$D/poc/bricks/05-rpm-mock/s1.sh" "$V" 2>&1; echo "code $?"
sed "s/\\\\\$basearch/\\\\\$arch/" "$D/poc/bricks/05-rpm-mock/s1.sh" > "$H/s1-change.sh"
echo "== cas s1.sh changé"; python3 -I -u "$H/releve6.py" "$H/rocky-9.tpl" "$H/s1-change.sh" "$V" 2>&1; echo "code $?"
sed 's/^\[devel\]$/{% if devel %}\n[devel]/' "$H/rocky-9.tpl" > "$H/jinja.tpl"
echo "== cas ligne hors INI"; python3 -I -u "$H/releve6.py" "$H/jinja.tpl" "$D/poc/bricks/05-rpm-mock/s1.sh" "$V" 2>&1; echo "code $?"
printf "config_opts['dnf.conf'] = \"\"\"\n[main]\n\"\"\"\nconfig_opts['dnf.conf'] += \"\"\"\n[x]\n\"\"\"\n" > "$H/deux.tpl"
echo "== cas deux affectations"; python3 -I -u "$H/releve6.py" "$H/deux.tpl" "$D/poc/bricks/05-rpm-mock/s1.sh" "$V" 2>&1; echo "code $?"
sed -n '/^fonction() {/,/^}/p' "$D/poc/bricks/05-rpm-mock/m2.sh" > "$H/fonction.sh"
mkdir -p "$H/src"; cat > "$H/src/b.py" <<'PY'
class B:
    def autre(self):
        pass

    @traceLog()
    def doOutChroot(self, command, *args,
                    **kargs):
        """docstring"""

        if x:
            return 1
        return 2

    def suite(self):
        pass
PY
echo "== cas fonction"; ( T=$H; . "$H/fonction.sh"; mkdir -p "$T/mock-src"; cp "$H/src/b.py" "$T/mock-src/b.py"; fonction essai b.py doOutChroot; fonction essai b.py absente; fonction essai c.py x )
rm -rf -- "${H:?}"
