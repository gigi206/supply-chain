#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ghislain LE MEUR
# SPDX-License-Identifier: Apache-2.0
#
# Brique 05, M1b, pod_d (19/11/2026) : compare les journaux de dnf rapatriés de pod_a (limite par défaut, sans /proc) et de
# pod_d (limite par défaut, /proc monté dans la racine). Les lignes sont débarrassées de leur horodatage avant le diff, pour
# ne garder que les écarts de contenu. Lecture seule, hors cluster ; adresses e-mail retirées.
set -euo pipefail
T=$HOME/.cache/supply-chain-poc/08/travail/m1b-05
echo "# m1b-pod_d-journaux.sh, début $(date -u +%FT%TZ)"
n() { sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})? //' \
             -e 's/<[^>]*@[^>]*>/<adresse retirée>/g' "$1"; }
for x in a d; do echo "pod-$x-dnf.log : $(wc -l < "$T/pod-$x-dnf.log") lignes"; done
echo "## lignes « scriptlet », « warning », « error », « tmpfiles » (casse ignorée), pod_a puis pod_d"
for x in a d; do echo "--- pod_$x"; n "$T/pod-$x-dnf.log" | grep -iE 'scriptlet|warning|error|tmpfiles' | sed 's/^/   /' || true; done
echo "## diff des journaux sans horodatage (pod_a -> pod_d)"
diff <(n "$T/pod-a-dnf.log") <(n "$T/pod-d-dnf.log") | sed 's/^/   /' || true
echo "# fin $(date -u +%FT%TZ)"
