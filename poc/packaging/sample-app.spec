# Paquet rpm de sample-app (banc A2 dans OBS, brique 05 dans mock) : build hors ligne depuis
# l'archive de sources.sh, qui contient déjà les modules Go (vendor/) et « marked » (web/node_modules).
# Les macros de reproductibilité (SOURCE_DATE_EPOCH, %_buildhost) viennent de la configuration
# du constructeur : prjconf OBS ou configuration mock.
%global debug_package %{nil}

Name:           sample-app
Version:        1.0.0
Release:        1%{?dist}
Summary:        Application de démonstration de la plateforme supply-chain
License:        Apache-2.0 AND MIT AND BSD-3-Clause
URL:            https://github.com/gigi206/supply-chain
Source0:        %{name}-%{version}.tar.gz
ExclusiveArch:  x86_64
BuildRequires:  golang >= 1.24
BuildRequires:  nodejs

%description
Binaire Go qui sert une interface web construite avec npm et embarquée à la compilation.

%prep
%autosetup

%build
export GOTOOLCHAIN=local GOPROXY=off CGO_ENABLED=0
export GOFLAGS="-mod=vendor -buildvcs=false -trimpath"
export GOCACHE=$PWD/.gocache GOPATH=$PWD/.gopath
(cd web && node build.mjs)
go build -ldflags "-s -w -buildid= -X main.Version=%{version}" -o %{name} .

%install
install -Dpm 0755 %{name} %{buildroot}%{_bindir}/%{name}

%files
%license LICENSES/Apache-2.0.txt vendor/github.com/go-chi/chi/v5/LICENSE web/node_modules/marked/LICENSE.md
%{_bindir}/%{name}

%changelog
* Wed Oct 28 2026 Contributeurs de gigi206/supply-chain <poc@supply-chain.invalid> - 1.0.0-1
- Paquet du banc A2 (OBS) et des briques 05 et 06
