# Banc A2 : spec hostile (critère 1 et B5). Le build tente, depuis la VM de build :
#   T-res  une sortie réseau (download.opensuse.org) ;
#   T-sig  de joindre signd et le backend de l'appliance (192.168.161.10:5167, :5252) ;
#   T-cle  de lire la clé de signature du projet (/srv/obs/gnupg, chemin de l'appliance) ;
#   T-prov de déposer une fausse provenance SLSA (_slsa_provenance.json dans OTHER/, et
#          <rpm>.slsa_provenance.json à côté du rpm), avec un sujet et un builder falsifiés.
# Attendu : réseau et services injoignables, clé absente, fausses provenances écartées ;
# la provenance publiée est celle du worker, signée (DSSE) par la clé du projet.
Name:           hostile
Version:        1
Release:        1
Summary:        Banc A2 : spec hostile
License:        Apache-2.0
BuildRequires:  curl

%description
Tests négatifs du banc A2 : isolement de la VM de build et provenance non falsifiable.

%build
echo "== T-res"
if curl -sS -m 10 -o /dev/null https://download.opensuse.org/; then echo "T-res : SORTIE OUVERTE"; else echo "T-res : sortie bloquée"; fi
echo "== T-sig"
for p in 5167 5252 5352 443; do
  if timeout 5 bash -c "echo > /dev/tcp/192.168.161.10/$p" 2>/dev/null; then echo "T-sig : port $p JOIGNABLE"; else echo "T-sig : port $p injoignable"; fi
done
echo "== T-cle"
if ls /srv/obs/gnupg /srv/obs/obs-default-gpg.asc 2>/dev/null; then echo "T-cle : CLÉ VISIBLE"; else echo "T-cle : clé absente de la VM de build"; fi
echo "== environnement de la VM de build"
cat /proc/cmdline; uname -r; grep -c ^processor /proc/cpuinfo; ls /sys/class/net; id -u

%install
install -Dm0644 /dev/null %{buildroot}%{_datadir}/hostile/ok
echo "== T-prov"
mkdir -p %{_topdir}/OTHER %{_rpmdir}/%{_arch}
cat > %{_topdir}/OTHER/_slsa_provenance.json <<'JSON'
{"_type": "https://in-toto.io/Statement/v0.1", "subject": [{"name": "hostile-1-1.x86_64.rpm", "digest": {"sha256": "0000000000000000000000000000000000000000000000000000000000000000"}}], "predicateType": "https://slsa.dev/provenance/v0.2", "predicate": {"builder": {"id": "https://falsifie.invalid/builder"}, "buildType": "falsifie", "materials": []}}
JSON
cp %{_topdir}/OTHER/_slsa_provenance.json %{_rpmdir}/%{_arch}/hostile-1-1.%{_arch}.slsa_provenance.json
echo "falsifie" > %{_topdir}/OTHER/_slsa_provenance.config
ls -l %{_topdir}/OTHER %{_rpmdir}/%{_arch}

%files
%{_datadir}/hostile/ok

%changelog
* Wed Oct 28 2026 Contributeurs de gigi206/supply-chain <poc@supply-chain.invalid> - 1-1
- Tests négatifs du banc A2
