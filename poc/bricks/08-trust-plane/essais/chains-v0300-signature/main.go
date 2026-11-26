// Banc de signature de Chains : appelle ObjectSigner.Sign (le chemin du contrôleur, sans contrôleur) sur de vrais objets Tekton
// capturés, avec la configuration en service (slsa/v2alpha4, stockage oci en dsse, simplesigning), un signataire x509 à clé jetable
// au lieu du KMS, un registre en mémoire sur 127.0.0.1 et de faux clients Kubernetes et Tekton. Compilé dans src29 (v0.29.9) et
// src30 (v0.30.0), même source. Modes :
//
//	banc-signature cle <dossier>                        clé cosign jetable (cosign.key, cosign.password, cosign.pub)
//	banc-signature serve <fichier-port>                 registre en mémoire, écrit son port, bloque
//	banc-signature image <registre> <depot>             pousse une image aléatoire, écrit son digest
//	banc-signature signer <registre> <cle> <ancien-hote> <ancien-digest> <digest> pr.json tr.json...
//
// signer remplace l'hôte et le digest d'origine par ceux du banc dans les objets, signe le PipelineRun (avec ses TaskRuns)
// puis chaque TaskRun, et écrit sur la sortie un JSON : erreur de Sign par objet, compteurs du Recorder, annotations chains.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/google/go-containerregistry/pkg/name"
	"github.com/google/go-containerregistry/pkg/registry"
	"github.com/google/go-containerregistry/pkg/v1/random"
	"github.com/google/go-containerregistry/pkg/v1/remote"
	"github.com/sigstore/cosign/v2/pkg/cosign"
	"github.com/tektoncd/chains/pkg/chains"
	"github.com/tektoncd/chains/pkg/chains/objects"
	"github.com/tektoncd/chains/pkg/chains/storage"
	"github.com/tektoncd/chains/pkg/config"
	"github.com/tektoncd/chains/pkg/metrics"
	v1 "github.com/tektoncd/pipeline/pkg/apis/pipeline/v1"
	pipelinefake "github.com/tektoncd/pipeline/pkg/client/clientset/versioned/fake"
	"go.uber.org/zap"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	kubefake "k8s.io/client-go/kubernetes/fake"
	"knative.dev/pkg/logging"
)

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERREUR", err)
		os.Exit(1)
	}
}

// compteur : Recorder qui compte, pour voir ce que recordError et measureMetrics enregistrent.
type compteur struct {
	mu sync.Mutex
	n  map[string]int
}

func (c *compteur) RecordCountMetrics(_ context.Context, m metrics.Metric) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.n["compte:"+fmt.Sprint(m)]++
}

func (c *compteur) RecordErrorMetric(_ context.Context, e metrics.MetricErrorType) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.n["erreur:"+fmt.Sprint(e)]++
}

// La configuration en service (tekton/chains/chains-config.yaml), signataire x509 au lieu de kms.
var donnees = map[string]string{
	"artifacts.taskrun.format":                     "slsa/v2alpha4",
	"artifacts.taskrun.storage":                    "oci",
	"artifacts.taskrun.signer":                     "x509",
	"artifacts.pipelinerun.format":                 "slsa/v2alpha4",
	"artifacts.pipelinerun.storage":                "oci",
	"artifacts.pipelinerun.signer":                 "x509",
	"artifacts.pipelinerun.enable-deep-inspection": "true",
	"artifacts.oci.format":                         "simplesigning",
	"artifacts.oci.storage":                        "oci",
	"artifacts.oci.signer":                         "x509",
	"storage.oci.encoding-format":                  "dsse",
	"transparency.enabled":                         "false",
	"builder.id":                                   "https://supply-chain.example/builders/tekton-chains@v1",
	"builddefinition.buildtype":                    "https://tekton.dev/chains/v2/slsa-tekton",
}

func lire(f string, remplace *strings.Replacer, v any) {
	b, err := os.ReadFile(f)
	must(err)
	must(json.Unmarshal([]byte(remplace.Replace(string(b))), v))
}

func annotationsChains(m metav1.ObjectMeta) map[string]string {
	r := map[string]string{}
	for k, v := range m.Annotations {
		if strings.HasPrefix(k, "chains.tekton.dev/") {
			r[k] = v
		}
	}
	return r
}

func main() {
	switch os.Args[1] {
	case "cle":
		k, err := cosign.GenerateKeyPair(func(bool) ([]byte, error) { return []byte("banc"), nil })
		must(err)
		must(os.WriteFile(filepath.Join(os.Args[2], "cosign.key"), k.PrivateBytes, 0o600))
		must(os.WriteFile(filepath.Join(os.Args[2], "cosign.password"), []byte("banc"), 0o600))
		must(os.WriteFile(filepath.Join(os.Args[2], "cosign.pub"), k.PublicBytes, 0o644))
	case "serve":
		l, err := net.Listen("tcp", "127.0.0.1:0")
		must(err)
		must(os.WriteFile(os.Args[2], []byte(fmt.Sprint(l.Addr().(*net.TCPAddr).Port)), 0o644))
		must(http.Serve(l, registry.New()))
	case "image":
		img, err := random.Image(512, 1)
		must(err)
		ref, err := name.ParseReference(os.Args[2] + "/" + os.Args[3] + ":banc")
		must(err)
		must(remote.Write(ref, img))
		d, err := img.Digest()
		must(err)
		fmt.Println(d.String())
	case "signer":
		signer(os.Args[2], os.Args[3], os.Args[4], os.Args[5], os.Args[6], os.Args[7], os.Args[8:])
	default:
		must(fmt.Errorf("mode inconnu %q", os.Args[1]))
	}
}

func signer(reg, cle, ancienHote, ancienDigest, digest, fpr string, ftrs []string) {
	remplace := strings.NewReplacer(ancienHote, reg, ancienDigest, digest)
	pr := &v1.PipelineRun{}
	lire(fpr, remplace, pr)
	var trs []*v1.TaskRun
	for _, f := range ftrs {
		tr := &v1.TaskRun{}
		lire(f, remplace, tr)
		trs = append(trs, tr)
	}
	ps := pipelinefake.NewSimpleClientset()
	_, err := ps.TektonV1().PipelineRuns(pr.Namespace).Create(context.Background(), pr.DeepCopy(), metav1.CreateOptions{})
	must(err)
	for _, tr := range trs {
		_, err := ps.TektonV1().TaskRuns(tr.Namespace).Create(context.Background(), tr.DeepCopy(), metav1.CreateOptions{})
		must(err)
	}
	cfg, err := config.NewConfigFromMap(donnees)
	must(err)
	zl, err := zap.NewDevelopment()
	must(err)
	ctx := logging.WithLogger(config.ToContext(context.Background(), cfg), zl.Sugar())
	backends, err := storage.InitializeBackends(ctx, ps, kubefake.NewSimpleClientset(), *cfg)
	must(err)
	rec := &compteur{n: map[string]int{}}
	osg := &chains.ObjectSigner{Backends: backends, SecretPath: cle, Pipelineclientset: ps, Recorder: rec}
	res := map[string]any{}
	po := objects.NewPipelineRunObjectV1(pr)
	for _, tr := range trs {
		po.AppendTaskRun(tr)
	}
	enErreur := func(err error) string {
		if err == nil {
			return ""
		}
		return err.Error()
	}
	res["pipelinerun/"+pr.Name] = enErreur(osg.Sign(ctx, po))
	for _, tr := range trs {
		res["taskrun/"+tr.Name] = enErreur(osg.Sign(ctx, objects.NewTaskRunObjectV1(tr)))
	}
	ann := map[string]any{}
	p2, err := ps.TektonV1().PipelineRuns(pr.Namespace).Get(ctx, pr.Name, metav1.GetOptions{})
	must(err)
	ann["pipelinerun/"+pr.Name] = annotationsChains(p2.ObjectMeta)
	for _, tr := range trs {
		t2, err := ps.TektonV1().TaskRuns(tr.Namespace).Get(ctx, tr.Name, metav1.GetOptions{})
		must(err)
		ann["taskrun/"+tr.Name] = annotationsChains(t2.ObjectMeta)
	}
	cles := []string{}
	for k := range rec.n {
		cles = append(cles, k)
	}
	sort.Strings(cles)
	compte := map[string]int{}
	for _, k := range cles {
		compte[k] = rec.n[k]
	}
	b, err := json.MarshalIndent(map[string]any{"sign": res, "recorder": compte, "annotations": ann}, "", "  ")
	must(err)
	fmt.Println(string(b))
}
