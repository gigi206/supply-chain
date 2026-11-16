# Paquet rpm de sample-app (banc A2 dans OBS, brique 05 dans mock) : build hors ligne depuis
# l'archive de sources.sh, qui contient déjà les modules Go (vendor/) et « marked » (web/node_modules).
# Les macros de reproductibilité (SOURCE_DATE_EPOCH, %_buildhost) viennent de la configuration
# du constructeur : prjconf OBS ou configuration mock.
%global debug_package %{nil}

Name:           sample-app
Version:        1.0.0
Release:        2%{?dist}
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
# Notices de Go portées par le packaging (décision Q1 de la brique 05, 16/11/2026) : textes écrits ici, non copiés
# du buildroot ; golang-LICENSE et golang-PATENTS sont la LICENSE et le PATENTS de Go à l'octet près.
cat > golang-LICENSE <<'FIN_GOLANG_LICENSE'
Copyright 2009 The Go Authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
FIN_GOLANG_LICENSE
cat > golang-PATENTS <<'FIN_GOLANG_PATENTS'
Additional IP Rights Grant (Patents)

"This implementation" means the copyrightable works distributed by
Google as part of the Go project.

Google hereby grants to You a perpetual, worldwide, non-exclusive,
no-charge, royalty-free, irrevocable (except as stated in this section)
patent license to make, have made, use, offer to sell, sell, import,
transfer and otherwise run, modify and propagate the contents of this
implementation of Go, where such license applies only to those patent
claims, both currently owned or controlled by Google and acquired in
the future, licensable by Google that are necessarily infringed by this
implementation of Go.  This grant does not include claims that would be
infringed only as a consequence of further modification of this
implementation.  If you or your agent or exclusive licensee institute or
order or agree to the institution of patent litigation against any
entity (including a cross-claim or counterclaim in a lawsuit) alleging
that this implementation of Go or any code incorporated within this
implementation of Go constitutes direct or contributory patent
infringement, or inducement of patent infringement, then any patent
rights granted to you under this License for this implementation of Go
shall terminate as of the date such litigation is filed.
FIN_GOLANG_PATENTS
cat > golang-NOTICES <<'FIN_GOLANG_NOTICES'
Notices de la bibliothèque standard de Go, liée statiquement dans /usr/bin/sample-app.
Elle vient du paquet golang installé dans le buildroot de construction.
Texte de la licence de Go : golang-LICENSE ; licence de brevets de Go : golang-PATENTS.

Attributions reprises du copyright Debian de golang-1.24-src 1.24.4-1 (paragraphes 8 et 9, License: Go),
comme dans le debian/copyright du paquet deb de sample-app :
Copyright: © 2009, 2011 The Go Authors. All rights reserved.
Based on code © 1984, 1987, 1989, 1992, 2000 by Stephen L. Moshier

Copyright: © 2010 The Go Authors. All rights reserved.
Based on code © 1993 by Sun Microsystems, Inc. All rights reserved.

Notice X11 de runtime/memmove_amd64.s (en-tête du fichier dans Go 1.24.7) :

Derived from Inferno's libkern/memmove-386.s (adapted for amd64)
https://bitbucket.org/inferno-os/inferno-os/src/master/libkern/memmove-386.s

        Copyright © 1994-1999 Lucent Technologies Inc. All rights reserved.
        Revisions Copyright © 2000-2007 Vita Nuova Holdings Limited (www.vitanuova.com).  All rights reserved.
        Portions Copyright 2009 The Go Authors. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
FIN_GOLANG_NOTICES

%build
export GOTOOLCHAIN=local GOPROXY=off CGO_ENABLED=0
export GOFLAGS="-mod=vendor -buildvcs=false -trimpath"
export GOCACHE=$PWD/.gocache GOPATH=$PWD/.gopath
(cd web && node build.mjs)
go build -ldflags "-s -w -buildid= -X main.Version=%{version}" -o %{name} .

%install
install -Dpm 0755 %{name} %{buildroot}%{_bindir}/%{name}

%files
%license LICENSES/Apache-2.0.txt vendor/github.com/go-chi/chi/v5/LICENSE web/node_modules/marked/LICENSE.md golang-LICENSE golang-PATENTS golang-NOTICES
%{_bindir}/%{name}

%changelog
* Mon Nov 16 2026 Contributeurs de gigi206/supply-chain <poc@supply-chain.invalid> - 1.0.0-2
- Notices de la bibliothèque standard de Go portées dans le paquet : golang-LICENSE, golang-PATENTS,
  golang-NOTICES (attributions des paragraphes 8 et 9 du deb, notice X11 de runtime/memmove_amd64.s)

* Wed Oct 28 2026 Contributeurs de gigi206/supply-chain <poc@supply-chain.invalid> - 1.0.0-1
- Paquet du banc A2 (OBS) et des briques 05 et 06
