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

Le script a été exécuté le 10/11/2026 à 12:33:01 UTC, en moins d'une minute. Code 0. **R1 à R6 sont tenues.** Journaux : [`rpm-deb-hors-ligne.log`](rpm-deb-hors-ligne.log) et [`rpm-deb-hors-ligne-complement.log`](rpm-deb-hors-ligne-complement.log).

| # | Mesuré | Verdict |
|---|---|---|
| R1 | 48 correspondances, CVE-2026-9076 présente. Toutes viennent de l'espace `redhat:distro:redhat:9`, en `exact-direct-match`, avec la distribution cherchée `rockylinux 9.7` | tenue |
| R2 | 20 correspondances, CVE-2026-9076 et CVE-2026-84782 absentes. Restent 19 `not-fixed` (dont CVE-2026-84784) et 1 `wont-fix` | tenue |
| R3 | 48 correspondances, les mêmes identifiants que R1 ; aucun identifiant ALSA. La distribution cherchée est `redhat 9.7`, et non `almalinux` | tenue |
| R4 | 38 correspondances, toutes de l'espace `debian:distro:debian:13`, CVE-2026-9076 présente | tenue |
| R5 | 0 correspondance sans `distro=` | tenue |
| R6 | L'entrée `purl:` est acceptée, code 0 sur les 5 cas | tenue |

**Lecture**
- Un rpm de Rocky ou d'AlmaLinux est jugé sur les données de Red Hat. Debian 13 est jugé sur ses propres données.
- Les rpm de Rocky ne sont **pas** comparés aux errata de Rocky : la base n'en contient pas.
- Le rôle des entrées non affectées d'Alma n'est pas mesuré. Il faudrait une version qu'Alma a corrigée avant Red Hat ; aucune n'a été cherchée.
- **Sans `distro=` dans le PURL, aucune vulnérabilité n'est trouvée. L'échec est silencieux.** Les SBOM des rpm et des deb devront donc porter ce qualificatif, et la porte devra refuser un SBOM de paquet qui ne le porte pas.
