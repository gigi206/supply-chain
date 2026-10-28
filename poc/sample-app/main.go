// sample-app : application de démonstration de la plateforme supply-chain.
// Un binaire Go qui sert une interface web construite par npm et embarquée
// à la compilation (web/dist), afin d'exercer les deux écosystèmes.
package main

import (
	"embed"
	"io/fs"
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
)

// Version est fixée au build (-ldflags "-X main.Version=…").
var Version = "dev"

//go:embed all:web/dist
var webDist embed.FS

func main() {
	static, err := fs.Sub(webDist, "web/dist")
	if err != nil {
		log.Fatal(err)
	}

	r := chi.NewRouter()
	r.Get("/version", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte(Version + "\n"))
	})
	r.Handle("/*", http.FileServer(http.FS(static)))

	addr := os.Getenv("ADDR")
	if addr == "" {
		addr = ":8080"
	}
	log.Printf("sample-app %s écoute sur %s", Version, addr)
	log.Fatal(http.ListenAndServe(addr, r))
}
