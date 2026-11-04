// Brique 07a, G2 (D8) : sbom_merge.py et scan_predicate.py réécrits en Go, sans dépendance, pour l'image d'outils du
// scanner (pas de python dans l'image). Même logique, même sortie JSON (comparée aux scripts Python sur les fichiers de G0) :
//
//	scan-outil fusion <a.json> <b.json> [libellé-a libellé-b] > fusion.json   (CycloneDX 1.6)
//	scan-outil predicat <grype.json> <ref-de-la-base> > scan.json             (https://supply-chain.example/scan/v1)
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"regexp"
	"sort"
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

func fusion(chemins, libelles []string) (any, error) {
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
		"metadata":   map[string]any{"tools": map[string]any{"components": []map[string]string{{"type": "application", "name": "sbom_merge"}}}},
		"components": sortie,
	}, nil
}

type vulnerabilite struct {
	ID       string   `json:"id"`
	Aliases  []string `json:"aliases"`
	Severity string   `json:"severity"`
	Kev      bool     `json:"kev"`
	KevCves  []string `json:"kevCves"`
	Epss     *float64 `json:"epss"`
	Package  string   `json:"package"`
	FixedIn  []string `json:"fixedIn"`
}

func predicat(chemin, refBase string) (any, error) {
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
		Matches []struct {
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
		} `json:"matches"`
	}
	if err := lire(chemin, &r); err != nil {
		return nil, err
	}
	type id struct{ id, purl string }
	vulns := map[id]vulnerabilite{}
	for _, m := range r.Matches {
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
		vulns[id{v.ID, m.Artifact.Purl}] = vulnerabilite{ID: v.ID, Aliases: trie(alias), Severity: sev, Kev: len(kev) > 0,
			KevCves: trie(kev), Epss: epss, Package: m.Artifact.Purl, FixedIn: fix}
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
	return map[string]any{
		"scanner": map[string]any{"id": "grype", "version": d.Version,
			"db": map[string]any{"built": d.DB.Status.Built, "schema": d.DB.Status.SchemaVersion, "ref": refBase}},
		"scannedAt":       d.Timestamp,
		"vulnerabilities": liste,
		// Paquets malveillants (OSV MAL-) : contrôle de la brique 07b (2c).
		"malicious": []string{},
	}, nil
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
	case len(a) == 3 && a[0] == "fusion":
		res, err = fusion(a[1:3], []string{"hermeto", "syft"})
	case len(a) == 5 && a[0] == "fusion":
		res, err = fusion(a[1:3], a[3:5])
	case len(a) == 3 && a[0] == "predicat":
		res, err = predicat(a[1], a[2])
	default:
		fmt.Fprintln(os.Stderr, "usage : scan-outil fusion <a.json> <b.json> [libellé-a libellé-b] | predicat <grype.json> <ref-de-la-base>")
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
