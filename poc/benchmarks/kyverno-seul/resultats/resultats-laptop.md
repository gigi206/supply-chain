| Cas | Attendu | Conforma | Kyverno | Conforma (ms) | Kyverno (ms) | Motif Conforma | Motif Kyverno |
|---|---|---|---|---|---|---|---|
| ok | PASS | PASS | PASS | 770 | 340 |  |  |
| c1-unsigned | FAIL | FAIL | FAIL | 700 | 320 | aucune signature d'image (seulement des attestations) | C1 : signature de l'image absente ou invalide |
| c1-rogue | FAIL | FAIL | FAIL | 400 | 340 | No image attestations found matching the given public key. Verify the correct public key was provided, and one or more a | C1 : signature de l'image absente ou invalide |
| c2-no-prov | FAIL | FAIL | FAIL | 700 | 320 | aucune provenance SLSA v1 signée par la clé attendue | C2 : provenance absente, mal signée ou builder inattendu |
| c2-bad-builder | FAIL | FAIL | FAIL | 1690 | 320 | builder.id inattendu : https://evil.example/builder | C2 : provenance absente, mal signée ou builder inattendu |
| c3-bad-source | FAIL | FAIL | FAIL | 950 | 320 | source non autorisée : github.com/evil/app | C3 : source non autorisée |
| c4-unpinned | FAIL | FAIL | FAIL | 1630 | 320 | dépendance sans digest : oci://zot.example/deps/app/hermeto | C4 : dépendance non épinglée ou d'origine non autorisée |
| c4-external-dep | FAIL | FAIL | FAIL | 790 | 330 | origine non autorisée : oci://docker.io/library/golang | C4 : dépendance non épinglée ou d'origine non autorisée |
| c5-untrusted-task | FAIL | FAIL | FAIL | 4350 | 320 | tâche non autorisée : oci://zot.example/tekton/tasks/build-go | C5 : tâche Tekton non autorisée |
| c6-no-vsa | FAIL | FAIL | FAIL | 1010 | 320 | aucune VSA PASSED signée par la clé du domaine de replay | C6 : VSA de replay absente, mal signée ou en échec |
| c6-vsa-failed | FAIL | FAIL | FAIL | 700 | 330 | aucune VSA PASSED signée par la clé du domaine de replay | C6 : VSA de replay absente, mal signée ou en échec |
| c6-vsa-wrong-key | FAIL | FAIL | FAIL | 750 | 330 | aucune VSA PASSED signée par la clé du domaine de replay | C6 : VSA de replay absente, mal signée ou en échec |
| c7-kev | FAIL | FAIL | FAIL | 720 | 330 | KEV sans VEX valide : CVE-2026-9999 | C7/C10 : KEV sans VEX valide, VEX expiré ou paquet malveillant |
| c7-kev-vex-ok | PASS | PASS | PASS | 740 | 370 |  |  |
| c7-mal | FAIL | FAIL | FAIL | 710 | 340 | paquet malveillant : MAL-2026-1234 | C7/C10 : KEV sans VEX valide, VEX expiré ou paquet malveillant |
| c8-licence | FAIL | FAIL | FAIL | 860 | 340 | 2 violation(s) de licence ERROR | C8 : violation de licence ERROR |
| c10-vex-expired | FAIL | FAIL | FAIL | 740 | 330 | KEV sans VEX valide : CVE-2026-9999 | C7/C10 : KEV sans VEX valide, VEX expiré ou paquet malveillant |
