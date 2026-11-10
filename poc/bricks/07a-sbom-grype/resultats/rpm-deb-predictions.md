# rpm/deb hors ligne : prédictions (écrites le 10/11/2026 à 12:32 UTC, avant toute exécution)

Le script est [`rpm-deb-hors-ligne.sh`](../rpm-deb-hors-ligne.sh). Il tourne sur l'hôte seul, hors réseau (`unshare -rn`), avec Grype 0.104.1 de mise et la base du 04/11/2026 importée en G0. Il ne télécharge rien et n'écrit rien dans Zot, Forgejo, le cluster ou les VM. Le propriétaire a choisi « dans l'ordre que tu veux » pour a, b et c ; c passe en premier.

Les entrées sont des PURL synthétiques, avec le qualificatif `distro=`. Ce ne sont pas de vrais paquets. Les versions d'openssl sont choisies d'après la base, lues par une requête de préparation en lecture seule, non archivée (vers 12:30 UTC). Ce sont des entrées de la base, pas des mesures de Grype :
- Red Hat 9 : CVE-2026-9076 affecte les versions `< 1:3.5.5-4.el9_8`, et CVE-2026-84782 les versions `< 1:3.5.8-2.el9_8` ;
- AlmaLinux 9 : ALSA-2026:25239, ALSA-2026:67165 et ALSA-2026:77396 sont rangés comme non affectés à partir de leur version de correction ;
- Debian 13 : CVE-2026-9076 affecte les versions `< 3.5.6-1~deb13u2`.

## Prédictions

| # | Cas | Prédit | Confiance |
|---|---|---|---|
| R1 | `rocky-vieux` (1:3.5.5-3.el9, rocky 9.7) | CVE-2026-9076 présente, trouvée par la distribution, dans l'espace de Red Hat 9. La chaîne `rocky` → `rhel` → `redhat` fonctionne | moyenne : la chaîne n'est pas lue dans le source |
| R2 | `rocky-corrige` (1:3.5.8-2.el9_8) | CVE-2026-9076 et CVE-2026-84782 absentes ; il reste les vulnérabilités `not-fixed`, comme CVE-2026-84784 | moyenne |
| R3 | `alma-vieux` (1:3.5.5-3.el9, almalinux 9.7) | CVE-2026-9076 présente, comme R1, par les données de Red Hat. Les entrées d'Alma ne retirent rien, puisque cette version est antérieure à toutes leurs corrections | faible : le rôle des entrées non affectées n'est pas connu |
| R4 | `debian-vieux` (3.5.6-1~deb13u1, debian 13) | CVE-2026-9076 présente, dans l'espace de Debian 13 | haute |
| R5 | `rocky-sans-distro` (témoin) | CVE-2026-9076 absente : sans distribution, Grype ne trouve pas de données d'OS. Peu ou pas de correspondances | moyenne |
| R6 | Toutes | Code 0. L'entrée `purl:` est acceptée par Grype 0.104.1 | moyenne : non essayé avec cette version |

Si R1 échoue, la question « Grype comme scanner unique sur EL » reste ouverte pour Rocky. On lira alors le source de Grype 0.104.1, sans rien télécharger d'autre que son dépôt public.

## Résultat

(à écrire après l'exécution, sans réécrire ce qui précède)
