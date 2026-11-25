// Banc Chains : appelle le format slsa/v2alpha4 sur un objet Tekton lu dans un fichier. Usage : banc pr.json [tr.json ...] | banc -tr tr.json
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	intoto "github.com/in-toto/attestation/go/v1"
	"github.com/tektoncd/chains/pkg/chains/formats/slsa/v2alpha4"
	"github.com/tektoncd/chains/pkg/chains/objects"
	"github.com/tektoncd/chains/pkg/config"
	v1 "github.com/tektoncd/pipeline/pkg/apis/pipeline/v1"
	"google.golang.org/protobuf/encoding/protojson"
)

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERREUR", err)
		os.Exit(1)
	}
}

func lire(f string, v any) {
	b, err := os.ReadFile(f)
	must(err)
	must(json.Unmarshal(b, v))
}

func main() {
	c := config.Config{}
	c.Builder.ID = "https://supply-chain.example/builders/tekton-chains@v1"
	c.BuildDefinition.BuildType = "https://tekton.dev/chains/v2/slsa-tekton"
	c.Artifacts.PipelineRuns.DeepInspectionEnabled = true
	p, err := v2alpha4.NewFormatter(c)
	must(err)
	var obj any
	if os.Args[1] == "-tr" {
		tr := &v1.TaskRun{}
		lire(os.Args[2], tr)
		obj = objects.NewTaskRunObjectV1(tr)
	} else {
		pr := &v1.PipelineRun{}
		lire(os.Args[1], pr)
		o := objects.NewPipelineRunObjectV1(pr)
		for _, f := range os.Args[2:] {
			tr := &v1.TaskRun{}
			lire(f, tr)
			o.AppendTaskRun(tr)
		}
		obj = o
	}
	out, err := p.CreatePayload(context.Background(), obj)
	must(err)
	var b []byte
	switch v := out.(type) { // comme getRawPayload (pkg/chains/signing.go)
	case intoto.Statement: //nolint:govet
		b, err = protojson.Marshal(&v)
	case *intoto.Statement:
		b, err = protojson.Marshal(v)
	default:
		err = fmt.Errorf("type %T", out)
	}
	must(err)
	fmt.Println(string(b))
}
