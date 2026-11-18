# Brique 05, M5a, test R7 (carte de M5, décision « Ok » du 18/11/2026) : paquet minimal dont %build imprime ses interfaces et
# tente une connexion TCP à Zot (192.168.161.13:5000, première cible des témoins de construire-rpm), sans jamais échouer. Les
# lignes « M5-SONDE » de build.log disent si %build a tourné et ce que la connexion a donné ; sans elles, R7 n'est pas mesuré.
Name:           m5-reseau
Version:        1.0
Release:        1
Summary:        Sonde réseau de M5a, pendant %%build
License:        MIT
BuildArch:      noarch

%description
Sonde réseau de M5a : interfaces vues et connexion TCP à Zot pendant %%build.

%prep

%build
echo "M5-SONDE début de %%build"
echo "M5-SONDE interfaces : $(sed -n '3,$ s/:.*//p' /proc/net/dev | tr -d ' ' | tr '\n' ' ')"
r=0; timeout 10 bash -c 'exec 3<>/dev/tcp/192.168.161.13/5000' 2> /dev/null || r=$?
echo "M5-SONDE tcp 192.168.161.13/5000 code $r"
echo "M5-SONDE fin de %%build"

%install
mkdir -p %{buildroot}/usr/share/m5-reseau
echo m5 > %{buildroot}/usr/share/m5-reseau/sonde

%files
/usr/share/m5-reseau/sonde
