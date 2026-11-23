// Brique 07a, G2 (D8) : sbom_merge.py et scan_predicate.py réécrits en Go, sans dépendance, pour l'image d'outils du
// scanner (pas de python dans l'image). Même logique, même sortie JSON (comparée aux scripts Python sur les fichiers de G0) jusqu'à
// la tranche 3 de la 07b, qui ajoute le composant container, le filtre des VEX et les entrées écartées par un VEX :
//
//	scan-outil fusion <a.json> <b.json> <libellé-a> <libellé-b> <image@sha256:…> > fusion.json   (CycloneDX 1.6)
//	scan-outil vex <sha256-du-sujet> <dossier> [énoncé.json…] > vex-retenus.json
//	scan-outil predicat <grype.json> <ref-de-la-base> <vex-retenus.json> > scan.json          (https://supply-chain.example/scan/v1)
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

var purlRe = regexp.MustCompile(`^pkg:([^/]+)/([^@?#]+)@([^?#]+)(?:\?[^#]*)?(?:#(.*))?$`)
var majeur = regexp.MustCompile(`^v\d+$`)

type cle struct{ typ, nom, version string }

// cleDe : (type, nom complet, version) d'un PURL ; faux s'il n'a pas de version. Module Go majeur ≥ 2 (Syft : …/chi@v5.2.3#v5) :
// nom …/chi/v5, comme chez Hermeto.
func cleDe(purl string) (cle, bool) {
	m := purlRe.FindStringSubmatch(purl)
	if m == nil {
		return cle{}, false
	}
	nom, err1 := url.PathUnescape(m[2])
	version, err2 := url.PathUnescape(m[3])
	if err1 != nil || err2 != nil {
		return cle{}, false
	}
	if m[1] == "golang" && m[4] != "" && majeur.MatchString(m[4]) {
		nom = nom + "/" + m[4]
	}
	return cle{m[1], nom, version}, true
}

type propriete struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type composant struct {
	Type       string          `json:"type"`
	Name       string          `json:"name"`
	Version    string          `json:"version"`
	Purl       string          `json:"purl"`
	Properties []propriete     `json:"properties"`
	Licenses   json.RawMessage `json:"licenses,omitempty"`
}

type entree struct {
	Type     string          `json:"type"`
	Name     string          `json:"name"`
	Purl     string          `json:"purl"`
	Licenses json.RawMessage `json:"licenses"`
}

var imageRe = regexp.MustCompile(`^(?:[^/]+/)*([^/@:]+)(?::[^/@]*)?@(sha256:[0-9a-f]{64})$`)

// conteneur : metadata.component de type container (07b, mesure 0 : sans --vex, mêmes correspondances que sans composant, image et
// deb). Sans lui, Grype refuse --vex sur un SBOM CycloneDX (tranche 2, constat 1). Nom : dernier élément du dépôt, comme au banc.
func conteneur(image string) (map[string]string, error) {
	m := imageRe.FindStringSubmatch(image)
	if m == nil {
		return nil, fmt.Errorf("image attendue sous la forme <dépôt>@sha256:<64 hex> : %q", image)
	}
	p := "pkg:oci/" + m[1] + "@" + m[2]
	return map[string]string{"type": "container", "name": m[1], "version": m[2], "bom-ref": p, "purl": p}, nil
}

func fusion(chemins, libelles []string, image string) (any, error) {
	comp, err := conteneur(image)
	if err != nil {
		return nil, err
	}
	var sortie []*composant
	vus := map[cle]*composant{}
	for i, chemin := range chemins {
		var doc struct {
			Components []entree `json:"components"`
		}
		if err := lire(chemin, &doc); err != nil {
			return nil, err
		}
		for _, c := range doc.Components {
			k, ok := cleDe(c.Purl)
			if !ok {
				continue
			}
			if x, deja := vus[k]; deja {
				x.Properties = append(x.Properties, propriete{"supply-chain:source", libelles[i]})
				continue
			}
			t, n := c.Type, c.Name
			if t == "" {
				t = "library"
			}
			if n == "" {
				n = k.nom
			}
			x := &composant{Type: t, Name: n, Version: k.version, Purl: c.Purl,
				Properties: []propriete{{"supply-chain:source", libelles[i]}}}
			if l := bytes.TrimSpace(c.Licenses); len(l) > 0 && !bytes.Equal(l, []byte("null")) && !bytes.Equal(l, []byte("[]")) {
				x.Licenses = c.Licenses
			}
			vus[k] = x
			sortie = append(sortie, x)
		}
	}
	sort.SliceStable(sortie, func(i, j int) bool { return sortie[i].Purl < sortie[j].Purl })
	if sortie == nil {
		sortie = []*composant{}
	}
	return map[string]any{
		"bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
		"metadata": map[string]any{"tools": map[string]any{"components": []map[string]string{{"type": "application", "name": "sbom_merge"}}},
			"component": comp},
		"components": sortie,
	}, nil
}

type vexEntree struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
}

type vulnerabilite struct {
	ID       string     `json:"id"`
	Aliases  []string   `json:"aliases"`
	Severity string     `json:"severity"`
	Kev      bool       `json:"kev"`
	KevCves  []string   `json:"kevCves"`
	Epss     *float64   `json:"epss"`
	Package  string     `json:"package"`
	FixedIn  []string   `json:"fixedIn"`
	Vex      *vexEntree `json:"vex,omitempty"`
}

type correspondance struct {
	Vulnerability struct {
		ID             string `json:"id"`
		Severity       string `json:"severity"`
		KnownExploited []struct {
			Cve string `json:"cve"`
		} `json:"knownExploited"`
		Epss []struct {
			Epss float64 `json:"epss"`
		} `json:"epss"`
		Fix *struct {
			Versions []string `json:"versions"`
		} `json:"fix"`
	} `json:"vulnerability"`
	Related []struct {
		ID string `json:"id"`
	} `json:"relatedVulnerabilities"`
	Artifact struct {
		Purl string `json:"purl"`
	} `json:"artifact"`
	AppliedIgnoreRules []map[string]any `json:"appliedIgnoreRules"`
}

func entreeDe(m correspondance) vulnerabilite {
	v := m.Vulnerability
	kev := map[string]bool{}
	for _, k := range v.KnownExploited {
		kev[k.Cve] = true
	}
	alias := map[string]bool{}
	for _, x := range m.Related {
		alias[x.ID] = true
	}
	delete(alias, v.ID)
	var epss *float64
	for _, e := range v.Epss {
		if epss == nil || e.Epss > *epss {
			e := e.Epss
			epss = &e
		}
	}
	sev := v.Severity
	if sev == "" {
		sev = "Unknown"
	}
	fix := []string{}
	if v.Fix != nil && len(v.Fix.Versions) > 0 {
		fix = v.Fix.Versions
	}
	return vulnerabilite{ID: v.ID, Aliases: trie(alias), Severity: sev, Kev: len(kev) > 0, KevCves: trie(kev), Epss: epss,
		Package: m.Artifact.Purl, FixedIn: fix}
}

// statutVex : statut de la règle d'exclusion de namespace « vex » (Grype 0.104.1 : {"namespace":"vex","vex-status":…}, tranche 2).
func statutVex(m correspondance) (string, bool) {
	for _, r := range m.AppliedIgnoreRules {
		if r["namespace"] == "vex" {
			s, _ := r["vex-status"].(string)
			return s, true
		}
	}
	return "", false
}

type docRetenu struct {
	Sha256     string `json:"sha256"`
	Timestamp  string `json:"timestamp"`
	Statements int    `json:"statements"`
	Fichier    string `json:"fichier"`
}

// enonce : énoncé d'un document lisible, recevable ou non (remplacement, choix du 21/11/2026). Noms : vulnerability.@id, name et
// aliases ; horodatage de l'énoncé, à défaut du document ; exemptant : document recevable et un produit cite le digest scanné ;
// sousComposants : ceux des produits qui citent le digest, absent si l'un d'eux n'en a aucun (énoncé large, couvre tout paquet).
type enonce struct {
	Noms           []string `json:"noms"`
	Horodatage     string   `json:"horodatage"`
	Statut         string   `json:"statut"`
	Exemptant      bool     `json:"exemptant"`
	SousComposants []string `json:"sousComposants,omitempty"`
	Document       string   `json:"document"`
}

type vexRetenus struct {
	Retenus []docRetenu         `json:"retenus"`
	Rejetes []map[string]string `json:"rejetes"`
	Enonces []enonce            `json:"enonces,omitempty"`
}

// predicat : correspondances de Grype (matches) et correspondances écartées par un VEX (ignoredMatches dont une règle est de namespace
// « vex »). Remplacement (choix du propriétaire du 21/11/2026) : pour une correspondance écartée, les énoncés candidats sont ceux
// dont un nom croise son identifiant ou ses alias, quel que soit le produit ; le plus récent l'emporte, quel que soit son statut.
// L'entrée garde alors tous ses champs, plus vex (statut donné par Grype, horodatage du gagnant), seulement si tous les énoncés à cet
// horodatage sont exemptants ; un énoncé exemptant qui ne couvre pas son paquet sort de son classement ; sinon elle reste ordinaire et compte dans vex.ecarteesSansExemption (échec fermé, indépendant de
// l'ordre des fichiers). Une correspondance écartée par une autre règle que « vex » reste une entrée ordinaire : seul un VEX exempte.
// Si une même clé (id, PURL) est à la fois trouvée et écartée, l'entrée trouvée l'emporte.
// Repli (limite 4, passage 18) : Grype a échoué avec les VEX et le scan a été relancé sans eux. Aucun document n'est appliqué :
// documents est vide, aucune correspondance ne peut être écartée par un VEX (sinon erreur), et vex.repli compte les documents
// retenus non appliqués. Hors repli, le champ est absent : les prédicats ordinaires ne changent pas.
func predicat(chemin, refBase, cheminVex string, repli bool) (any, error) {
	var r struct {
		Descriptor struct {
			Version   string `json:"version"`
			Timestamp string `json:"timestamp"`
			DB        struct {
				Status struct {
					Built         string `json:"built"`
					SchemaVersion string `json:"schemaVersion"`
				} `json:"status"`
			} `json:"db"`
		} `json:"descriptor"`
		Matches        []correspondance `json:"matches"`
		IgnoredMatches []correspondance `json:"ignoredMatches"`
	}
	if err := lire(chemin, &r); err != nil {
		return nil, err
	}
	var vr vexRetenus
	if err := lire(cheminVex, &vr); err != nil {
		return nil, err
	}
	nRepli := len(vr.Retenus)
	if repli {
		if nRepli == 0 {
			return nil, fmt.Errorf("repli sans document retenu dans %s", cheminVex)
		}
		vr.Retenus, vr.Enonces = nil, nil
	}
	plusAncien := ""
	var tMin time.Time
	documents := make([]map[string]string, 0, len(vr.Retenus))
	for _, d := range vr.Retenus {
		t, err := time.Parse(time.RFC3339Nano, d.Timestamp)
		if err != nil {
			return nil, fmt.Errorf("horodatage illisible dans %s : %q", cheminVex, d.Timestamp)
		}
		if plusAncien == "" || t.Before(tMin) {
			tMin, plusAncien = t, t.UTC().Format(time.RFC3339Nano)
		}
		documents = append(documents, map[string]string{"sha256": d.Sha256, "timestamp": d.Timestamp})
	}
	type candidat struct {
		noms      map[string]bool
		t         time.Time
		exemptant bool
		sous      map[string]bool // vide : énoncé large
	}
	enonces := make([]candidat, 0, len(vr.Enonces))
	for _, x := range vr.Enonces {
		t, err := time.Parse(time.RFC3339Nano, x.Horodatage)
		if err != nil {
			return nil, fmt.Errorf("horodatage d'énoncé illisible dans %s : %q", cheminVex, x.Horodatage)
		}
		n, sc := map[string]bool{}, map[string]bool{}
		for _, k := range x.Noms {
			n[k] = true
		}
		for _, k := range x.SousComposants {
			sc[k] = true
		}
		enonces = append(enonces, candidat{n, t, x.Exemptant, sc})
	}
	// gagnant : horodatage de l'énoncé le plus récent qui nomme la correspondance ; vrai seulement si tous les énoncés à cet horodatage
	// sont exemptants. Un énoncé exemptant qui ne couvre pas son paquet (sous-composants sans le PURL de l'entrée, égalité exacte)
	// sort du classement de cette entrée ; tous les autres y restent (affected, non recevable, autre produit, énoncé large) : une
	// rétractation garde sa portée large.
	gagnant := func(e vulnerabilite) (string, bool) {
		noms := append([]string{e.ID}, e.Aliases...)
		var tMax time.Time
		trouve, exempte := false, false
		for _, c := range enonces {
			vise := false
			for _, k := range noms {
				vise = vise || c.noms[k]
			}
			if c.exemptant && len(c.sous) > 0 && !c.sous[e.Package] {
				vise = false
			}
			switch {
			case !vise:
			case !trouve || c.t.After(tMax):
				trouve, tMax, exempte = true, c.t, c.exemptant && (len(c.sous) == 0 || c.sous[e.Package])
			case c.t.Equal(tMax):
				exempte = exempte && c.exemptant && (len(c.sous) == 0 || c.sous[e.Package])
			}
		}
		if !trouve || !exempte {
			return "", false
		}
		return tMax.UTC().Format(time.RFC3339Nano), true
	}
	sansExemption := 0
	type id struct{ id, purl string }
	vulns := map[id]vulnerabilite{}
	for _, m := range r.IgnoredMatches {
		e := entreeDe(m)
		if s, ok := statutVex(m); ok {
			if repli {
				return nil, fmt.Errorf("correspondance %s écartée par un VEX alors que le scan est un repli sans VEX", e.ID)
			}
			if plusAncien == "" {
				return nil, fmt.Errorf("correspondance %s écartée par un VEX alors qu'aucun document n'est retenu", e.ID)
			}
			if t, ok := gagnant(e); ok {
				e.Vex = &vexEntree{Status: s, Timestamp: t}
			} else {
				sansExemption++
			}
		}
		vulns[id{e.ID, e.Package}] = e
	}
	for _, m := range r.Matches {
		e := entreeDe(m)
		vulns[id{e.ID, e.Package}] = e
	}
	liste := make([]vulnerabilite, 0, len(vulns))
	for _, v := range vulns {
		liste = append(liste, v)
	}
	sort.Slice(liste, func(i, j int) bool {
		if liste[i].Package != liste[j].Package {
			return liste[i].Package < liste[j].Package
		}
		return liste[i].ID < liste[j].ID
	})
	d := r.Descriptor
	blocVex := map[string]any{"documents": documents, "rejetes": len(vr.Rejetes), "ecarteesSansExemption": sansExemption}
	if repli {
		blocVex["repli"] = nRepli
	}
	return map[string]any{
		"scanner": map[string]any{"id": "grype", "version": d.Version,
			"db": map[string]any{"built": d.DB.Status.Built, "schema": d.DB.Status.SchemaVersion, "ref": refBase}},
		"scannedAt":       d.Timestamp,
		"vulnerabilities": liste,
		// Paquets malveillants (OSV MAL-) : contrôle de la brique 07b (2c).
		"malicious": []string{},
		// Documents VEX passés à Grype (empreinte de l'énoncé signé décodé, comme scan-verifier.sh) et nombre de documents écartés.
		// ecarteesSansExemption : correspondances écartées par Grype que le remplacement n'exempte pas (rétractation, égalité, autre
		// produit, aucun énoncé nommé).
		// repli : documents retenus non appliqués (Grype en échec avec les VEX), seulement en repli.
		"vex": blocVex,
	}, nil
}

const typeOpenVEX = "https://openvex.dev/ns/v0.2.0"

// Justifications de not_affected listées par la spécification OpenVEX v0.2.0.
var justifications = map[string]bool{"component_not_present": true, "vulnerable_code_not_present": true,
	"vulnerable_code_not_in_execute_path": true, "vulnerable_code_cannot_be_controlled_by_adversary": true,
	"inline_mitigations_already_exist": true}

// lireVex : prédicat OpenVEX d'un énoncé in-toto vérifié par cosign, s'il est recevable ; sinon la raison du rejet. Le document
// entier est rejeté dès qu'un énoncé ne l'est pas (choix 5 du 21/11/2026) : seul not_affected, avec une justification de la
// spécification et un impact_statement non vide ; horodatage de l'énoncé, ou à défaut du document, lisible.
func lireVex(b []byte, sujet string) ([]byte, string, int, string) {
	doc, t, n, raison, _ := lireVexEnonces(b, sujet, "")
	return doc, t, n, raison
}

// lireVexEnonces : comme lireVex, plus les énoncés d'un document lisible (type, sujet, contexte, au moins un énoncé et tous les
// horodatages lisibles), recevable ou non, pour le remplacement. Un énoncé sans vulnérabilité nommée n'est pas listé.
func lireVexEnonces(b []byte, sujet, empreinte string) ([]byte, string, int, string, []enonce) {
	var st struct {
		Type          string `json:"_type"`
		PredicateType string `json:"predicateType"`
		Subject       []struct {
			Digest map[string]string `json:"digest"`
		} `json:"subject"`
		Predicate json.RawMessage `json:"predicate"`
	}
	if err := json.Unmarshal(b, &st); err != nil {
		return nil, "", 0, "énoncé illisible", nil
	}
	if st.Type != "https://in-toto.io/Statement/v0.1" && st.Type != "https://in-toto.io/Statement/v1" {
		return nil, "", 0, "type d'énoncé inattendu : " + st.Type, nil
	}
	if st.PredicateType != typeOpenVEX {
		return nil, "", 0, "type de prédicat inattendu : " + st.PredicateType, nil
	}
	vu := false
	for _, s := range st.Subject {
		vu = vu || s.Digest["sha256"] == sujet
	}
	if !vu {
		return nil, "", 0, "sujet différent du digest scanné", nil
	}
	var d struct {
		Context    string `json:"@context"`
		Timestamp  string `json:"timestamp"`
		Statements []struct {
			Status        string `json:"status"`
			Justification string `json:"justification"`
			Impact        string `json:"impact_statement"`
			Timestamp     string `json:"timestamp"`
			Vulnerability struct {
				ID      string   `json:"@id"`
				Name    string   `json:"name"`
				Aliases []string `json:"aliases"`
			} `json:"vulnerability"`
			Products []struct {
				ID            string `json:"@id"`
				Subcomponents []struct {
					ID string `json:"@id"`
				} `json:"subcomponents"`
			} `json:"products"`
		} `json:"statements"`
	}
	if err := json.Unmarshal(st.Predicate, &d); err != nil {
		return nil, "", 0, "prédicat OpenVEX illisible", nil
	}
	if d.Context != typeOpenVEX {
		return nil, "", 0, "@context inattendu : " + d.Context, nil
	}
	if len(d.Statements) == 0 {
		return nil, "", 0, "aucun énoncé VEX", nil
	}
	// énoncés pour le remplacement, si tous les horodatages sont lisibles ; exemptant décidé plus bas (document recevable)
	var liste []enonce
	for _, s := range d.Statements {
		h := s.Timestamp
		if h == "" {
			h = d.Timestamp
		}
		t, err := time.Parse(time.RFC3339Nano, h)
		if err != nil {
			liste = nil
			break
		}
		noms := map[string]bool{}
		for _, a := range []string{s.Vulnerability.ID, s.Vulnerability.Name} {
			if a != "" {
				noms[a] = true
			}
		}
		for _, a := range s.Vulnerability.Aliases {
			if a != "" {
				noms[a] = true
			}
		}
		if len(noms) == 0 {
			continue
		}
		cite, large, sous := false, false, map[string]bool{}
		for _, p := range s.Products {
			if sujet == "" || !strings.Contains(p.ID, sujet) {
				continue
			}
			cite = true
			large = large || len(p.Subcomponents) == 0
			for _, c := range p.Subcomponents {
				sous[c.ID] = true
			}
		}
		var sc []string
		if cite && !large {
			sc = trie(sous)
		}
		liste = append(liste, enonce{Noms: trie(noms), Horodatage: t.UTC().Format(time.RFC3339Nano), Statut: s.Status, Exemptant: cite,
			SousComposants: sc, Document: empreinte})
	}
	recevable := func(raison string) []enonce {
		for i := range liste {
			liste[i].Exemptant = liste[i].Exemptant && raison == ""
		}
		return liste
	}
	var tMin time.Time
	for i, s := range d.Statements {
		switch {
		case s.Status != "not_affected":
			r := fmt.Sprintf("énoncé %d : statut « %s », seul not_affected est passé", i, s.Status)
			return nil, "", 0, r, recevable(r)
		case !justifications[s.Justification]:
			r := fmt.Sprintf("énoncé %d : justification absente ou hors spécification", i)
			return nil, "", 0, r, recevable(r)
		case strings.TrimSpace(s.Impact) == "":
			r := fmt.Sprintf("énoncé %d : impact_statement absent", i)
			return nil, "", 0, r, recevable(r)
		}
		h := s.Timestamp
		if h == "" {
			h = d.Timestamp
		}
		t, err := time.Parse(time.RFC3339Nano, h)
		if err != nil {
			return nil, "", 0, fmt.Sprintf("énoncé %d : horodatage illisible", i), nil
		}
		if i == 0 || t.Before(tMin) {
			tMin = t
		}
	}
	return st.Predicate, tMin.UTC().Format(time.RFC3339Nano), len(d.Statements), "", recevable("")
}

// vex : documents recevables écrits dans <dossier>/vex-<n>.json (prédicat tel que signé), à passer à grype --vex ; résumé sur la sortie.
func vex(sujet, dossier string, fichiers []string) (any, error) {
	res := vexRetenus{Retenus: []docRetenu{}, Rejetes: []map[string]string{}}
	for i, f := range fichiers {
		b, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		s := sha256.Sum256(b)
		e := hex.EncodeToString(s[:])
		doc, t, n, raison, en := lireVexEnonces(b, sujet, e)
		res.Enonces = append(res.Enonces, en...)
		if raison != "" {
			res.Rejetes = append(res.Rejetes, map[string]string{"sha256": e, "raison": raison})
			continue
		}
		sortie := filepath.Join(dossier, fmt.Sprintf("vex-%d.json", i))
		if err := os.WriteFile(sortie, doc, 0o600); err != nil {
			return nil, err
		}
		res.Retenus = append(res.Retenus, docRetenu{Sha256: e, Timestamp: t, Statements: n, Fichier: sortie})
	}
	return res, nil
}

func trie(e map[string]bool) []string {
	l := make([]string, 0, len(e))
	for k := range e {
		l = append(l, k)
	}
	sort.Strings(l)
	return l
}

func lire(chemin string, v any) error {
	b, err := os.ReadFile(chemin)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

func main() {
	a := os.Args[1:]
	var res any
	var err error
	switch {
	case len(a) == 6 && a[0] == "fusion":
		res, err = fusion(a[1:3], a[3:5], a[5])
	case len(a) >= 3 && a[0] == "vex":
		res, err = vex(a[1], a[2], a[3:])
	case len(a) == 4 && a[0] == "predicat":
		res, err = predicat(a[1], a[2], a[3], false)
	case len(a) == 5 && a[0] == "predicat" && a[4] == "repli":
		res, err = predicat(a[1], a[2], a[3], true)
	default:
		fmt.Fprintln(os.Stderr, "usage : scan-outil fusion <a.json> <b.json> <libellé-a> <libellé-b> <image@sha256:…> | vex <sha256> <dossier> [énoncé…] | predicat <grype.json> <ref-de-la-base> <vex-retenus.json> [repli]")
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	e := json.NewEncoder(os.Stdout)
	e.SetEscapeHTML(false)
	e.SetIndent("", "  ")
	if err := e.Encode(res); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
