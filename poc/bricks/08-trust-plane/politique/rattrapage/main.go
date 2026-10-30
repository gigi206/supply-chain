// Brique 08, J6 : rattrapage des pushs dont le webhook est perdu (politique.sh rattrapage, CronJob rattrapage de
// l'espace declencheurs). Lu dans le code de Forgejo v15.0.11 : une livraison est marquée livrée avant l'envoi
// (services/webhook/deliver.go, MarkTaskDelivered) ; un échec n'est jamais retenté, et le démarrage ne remet en file que
// les tâches jamais tentées ; le « replay » n'existe que dans l'interface web (session, UUID de la tâche absent de l'API).
//
// Chaque passage lit la tête de la branche dans Forgejo (lecture anonyme, CA du PoC) et, si le PipelineRun de ce commit
// n'existe pas dans builds, le crée à partir de la TriggerTemplate en service, comme Triggers v0.37.2 : remplacement
// textuel de $(tt.params.<nom>) dans le gabarit brut, « $( » doublé (pkg/template/resource.go), $(uid) remplacé. Ni
// secret HMAC, ni jeton Forgejo : le seul identifiant est le jeton projeté du compte rattrapage, envoyé à l'API seulement.
// Contrôles repris du filtre CEL de l'EventListener (que ce chemin contourne) : dépôt, branche, commit de 40 caractères
// hexadécimaux ; puis gabarit : un seul PipelineRun tekton.dev/v1, dans builds, nommé <gabarit>-<commit> (anti-rejeu de
// J4), aucune variable restante. Label poc.test/declencheur=rattrapage au lieu des labels de Triggers.
// Sorties : JOINT, TETE, puis PRESENT, CREE ou DEJA (créé entre-temps, 409) ; toute autre issue : KO et code 1.
package main

import (
	"bytes"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"regexp"
	"slices"
	"strings"
	"time"
)

const (
	sa      = "/var/run/secrets/kubernetes.io/serviceaccount/"
	label   = "poc.test/declencheur"
	tekton  = "/apis/tekton.dev/v1/namespaces/"
	ancien  = "triggers.tekton.dev/old-escape-quotes" // OldEscapeAnnotation de Triggers
	essais  = 30                                      // kube-router rejette le trafic d'un pod neuf quelques secondes (J3, J5)
	plafond = 1 << 20
)

var (
	reCommit = regexp.MustCompile(`^[0-9a-f]{40}$`)
	reURL    = regexp.MustCompile(`^https://[A-Za-z0-9.:/_-]+\.git$`)
)

func ko(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "KO   "+format+"\n", a...)
	os.Exit(1)
}

func env(nom string) string {
	v := os.Getenv(nom)
	if v == "" {
		ko("variable %s absente", nom)
	}
	return v
}

// Un client par destination : chacun n'accepte que sa CA, ne suit aucune redirection et ignore les proxys.
func client(ca string) *http.Client {
	pem, err := os.ReadFile(ca)
	if err != nil {
		ko("CA %s : %v", ca, err)
	}
	racines := x509.NewCertPool()
	if !racines.AppendCertsFromPEM(pem) {
		ko("CA %s illisible", ca)
	}
	return &http.Client{
		Timeout:       10 * time.Second,
		Transport:     &http.Transport{TLSClientConfig: &tls.Config{RootCAs: racines, MinVersion: tls.VersionTLS12}},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
}

type serveur struct {
	c     *http.Client
	base  string
	jeton string // vide pour Forgejo
}

func (s serveur) appel(methode, chemin string, corps []byte) (int, []byte, error) {
	req, err := http.NewRequest(methode, s.base+chemin, bytes.NewReader(corps))
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Accept", "application/json")
	if corps != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if s.jeton != "" {
		req.Header.Set("Authorization", "Bearer "+s.jeton)
	}
	rep, err := s.c.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer rep.Body.Close()
	b, err := io.ReadAll(io.LimitReader(rep.Body, plafond))
	return rep.StatusCode, b, err
}

func lire(s serveur, chemin string, v any) {
	code, b, err := s.appel(http.MethodGet, chemin, nil)
	if err != nil || code != http.StatusOK {
		ko("GET %s : %d %v %.160s", chemin, code, err, b)
	}
	if err := json.Unmarshal(b, v); err != nil {
		ko("GET %s : %v", chemin, err)
	}
}

func uuid() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		ko("uuid : %v", err)
	}
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

// Remplacement de Triggers v0.37.2 (applyParamToResourceTemplate) : textuel, sur le JSON brut du gabarit.
func appliquer(rt []byte, nom, valeur string, guillemets bool) []byte {
	if guillemets {
		valeur = strings.ReplaceAll(valeur, `"`, `\"`)
	}
	valeur = strings.ReplaceAll(valeur, "$(", "$$(")
	return bytes.ReplaceAll(rt, []byte("$(tt.params."+nom+")"), []byte(valeur))
}

func main() {
	depot, branche, builds := env("DEPOT"), env("BRANCHE"), env("ESPACE")
	espaceTT, nomTT, ok := strings.Cut(env("GABARIT"), "/")
	if !ok {
		ko("GABARIT : <espace>/<nom> attendu")
	}
	jeton, err := os.ReadFile(sa + "token")
	if err != nil {
		ko("jeton du compte de service : %v", err)
	}
	forgejo := serveur{client(env("CA_FORGEJO")), env("FORGEJO"), ""}
	api := serveur{client(sa + "ca.crt"), "https://" + net.JoinHostPort(env("KUBERNETES_SERVICE_HOST"), env("KUBERNETES_SERVICE_PORT")),
		strings.TrimSpace(string(jeton))}

	for n := 1; ; n++ {
		a, _, e1 := forgejo.appel(http.MethodGet, "/api/v1/version", nil)
		b, _, e2 := api.appel(http.MethodGet, "/version", nil)
		if e1 == nil && e2 == nil && a == http.StatusOK && b == http.StatusOK {
			fmt.Printf("JOINT|Forgejo et API, essai %d\n", n)
			break
		}
		if n == essais {
			ko("Forgejo (%d %v) ou API (%d %v) injoignable", a, e1, b, e2)
		}
		time.Sleep(time.Second)
	}

	var d struct {
		FullName string `json:"full_name"`
		CloneURL string `json:"clone_url"`
	}
	lire(forgejo, "/api/v1/repos/"+depot, &d)
	if d.FullName != depot || !reURL.MatchString(d.CloneURL) {
		ko("dépôt %q, clone_url %q", d.FullName, d.CloneURL)
	}
	var br struct {
		Name   string `json:"name"`
		Commit struct {
			ID string `json:"id"`
		} `json:"commit"`
	}
	lire(forgejo, "/api/v1/repos/"+depot+"/branches/"+branche, &br)
	commit := br.Commit.ID
	if br.Name != branche || !reCommit.MatchString(commit) {
		ko("branche %q, commit %q", br.Name, commit)
	}
	fmt.Printf("TETE|%s|%s|%s\n", depot, branche, commit)

	var tt struct {
		Metadata struct {
			Annotations map[string]string `json:"annotations"`
		} `json:"metadata"`
		Spec struct {
			Params []struct {
				Name string `json:"name"`
			} `json:"params"`
			ResourceTemplates []json.RawMessage `json:"resourcetemplates"`
		} `json:"spec"`
	}
	lire(api, "/apis/triggers.tekton.dev/v1beta1/namespaces/"+espaceTT+"/triggertemplates/"+nomTT, &tt)
	var params []string
	for _, p := range tt.Spec.Params {
		params = append(params, p.Name)
	}
	slices.Sort(params)
	if !slices.Equal(params, []string{"commit", "depot"}) || len(tt.Spec.ResourceTemplates) != 1 {
		ko("gabarit %s/%s : paramètres %v, %d ressource(s)", espaceTT, nomTT, params, len(tt.Spec.ResourceTemplates))
	}
	_, guillemets := tt.Metadata.Annotations[ancien]
	rt := appliquer(tt.Spec.ResourceTemplates[0], "commit", commit, guillemets)
	rt = appliquer(rt, "depot", d.CloneURL, guillemets)
	rt = bytes.ReplaceAll(rt, []byte("$(uid)"), []byte(uuid()))
	if bytes.Contains(rt, []byte("$(tt.")) {
		ko("variable du gabarit non remplacée")
	}
	var pr map[string]any
	if err := json.Unmarshal(rt, &pr); err != nil {
		ko("gabarit rendu : %v", err)
	}
	md, _ := pr["metadata"].(map[string]any)
	nom, _ := md["name"].(string)
	if pr["apiVersion"] != "tekton.dev/v1" || pr["kind"] != "PipelineRun" || md["namespace"] != builds ||
		nom != nomTT+"-"+commit || md["generateName"] != nil {
		ko("gabarit rendu : %v %v %v/%v", pr["apiVersion"], pr["kind"], md["namespace"], md["name"])
	}

	code, b, err := api.appel(http.MethodGet, tekton+builds+"/pipelineruns/"+nom, nil)
	switch {
	case err == nil && code == http.StatusOK:
		fmt.Printf("PRESENT|%s/%s\n", builds, nom)
		return
	case err != nil || code != http.StatusNotFound:
		ko("GET pipelinerun %s : %d %v %.160s", nom, code, err, b)
	}
	labels, _ := md["labels"].(map[string]any)
	if labels == nil {
		labels = map[string]any{}
	}
	labels[label] = "rattrapage"
	md["labels"] = labels
	corps, err := json.Marshal(pr)
	if err != nil {
		ko("PipelineRun : %v", err)
	}
	code, b, err = api.appel(http.MethodPost, tekton+builds+"/pipelineruns", corps)
	switch {
	case err == nil && code == http.StatusCreated:
		fmt.Printf("CREE|%s/%s|commit %s|depot %s\n", builds, nom, commit, d.CloneURL)
	case err == nil && code == http.StatusConflict:
		fmt.Printf("DEJA|%s/%s|créé entre-temps (409)\n", builds, nom)
	default:
		ko("création de %s : %d %v %.300s", nom, code, err, b)
	}
}
