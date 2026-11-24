"""Brique 20 : calculs purs des KPI (aucune lecture de réseau, de fichier ni de git). Importés par recalcul.py (étape 2) et par
essais_kpi.py (jeu synthétique). Une valeur sans dénominateur rend None (« absent » ou « sans objet »), jamais 0 ni 1."""


def rapport(numerateur, denominateur):
    """« n/d », ou None si le dénominateur est nul (0/0 : sans objet)."""
    return f"{numerateur}/{denominateur}" if denominateur else None


def comptes_scan(predicat):
    """Comptes du prédicat de scan, mêmes définitions que entrees-scan.py (07b) : une entrée = un couple (identifiant, PURL)."""
    v = predicat.get("vulnerabilities") or []
    return {"entrees": len(v), "ecartees": sum(1 for e in v if e.get("vex")), "kev": sum(1 for e in v if e.get("kev")),
            "kev_ecartees": sum(1 for e in v if e.get("kev") and e.get("vex"))}


def delais_kev(scans):
    """Délai de correction des KEV d'un dépôt. scans : liste de (instant, [(clé, écartée)]), une par scan, l'entrée étant une KEV ;
    une KEV absente de la liste, ou écartée par un VEX, est corrigée à ce scan. Un scan sans entrée compte (liste vide).
    Rend [(clé, ouverture, fermeture ou None)], une ligne par ouverture : une KEV qui revient rouvre une ligne."""
    ouvertes, lignes = {}, []
    for instant, entrees in sorted(scans):
        # une même clé peut toucher plusieurs paquets : elle reste ouverte tant qu'une de ses entrées n'est pas écartée
        reelles = {cle for cle, ecartee in entrees if not ecartee}
        for cle in sorted(set(ouvertes) - reelles):
            lignes.append((cle, ouvertes.pop(cle), instant))
        for cle in reelles - set(ouvertes):
            ouvertes[cle] = instant
    return sorted(lignes + [(cle, debut, None) for cle, debut in ouvertes.items()], key=lambda x: (x[1], x[0]))
