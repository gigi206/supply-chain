# Banc A2 : spec hostile n° 2 (critère 1). Deux voies d'injection d'une provenance :
#   T-src  une fausse provenance en clair (_slsa_provenance.json, builder falsifie.invalid) est
#          commitée dans les sources du paquet, à côté de ce spec ;
#   T-suivi le build produit OTHER/hostile2.followup.spec, ce qui fait créer par bs_signer un job
#          de suivi (followupfile) ; ce job relit _slsa_provenance.json dans les données du job.
# Attendu : la provenance publiée reste celle du worker (DSSE, builder obs://…, vrais digests).
Name:           hostile2
Version:        1
Release:        1
Summary:        Banc A2 : spec hostile n° 2
License:        Apache-2.0
Source0:        _slsa_provenance.json
Source1:        _slsa_provenance.config

%description
Tests négatifs du banc A2 : provenance injectée par les sources et par un job de suivi.

%install
install -Dm0644 /dev/null %{buildroot}%{_datadir}/hostile2/ok
mkdir -p %{_topdir}/OTHER
ls -l %{_sourcedir}/
# SUIVI-DEBUT
# Le job de suivi reconstruit à partir de ce spec privé de ce bloc : il ne recrée pas de suivi.
sed '/^# SUIVI-DEBUT/,/^# SUIVI-FIN/d' %{_sourcedir}/hostile2.spec > %{_topdir}/OTHER/hostile2.followup.spec
cp %{_sourcedir}/_slsa_provenance.json %{_topdir}/OTHER/_slsa_provenance.json
# SUIVI-FIN
ls -l %{_topdir}/OTHER

%files
%{_datadir}/hostile2/ok

%changelog
* Wed Oct 28 2026 Contributeurs de gigi206/supply-chain <poc@supply-chain.invalid> - 1-1
- Tests négatifs du banc A2
