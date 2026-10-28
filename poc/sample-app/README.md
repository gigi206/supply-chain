# sample-app

Application de démonstration utilisée par les benchmarks et la tranche verticale :
- un binaire **Go** (dépendance `github.com/go-chi/chi/v5`) ;
- une interface web construite avec **npm** (dépendance `marked`), sans bundler natif, embarquée dans le binaire.

Elle exerce les deux écosystèmes (gomod, npm) sans être triviale à rendre hermétique.

## Build de référence (en ligne)

```bash
cd web && npm ci && npm run build && cd ..
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -buildid= -X main.Version=1.0.0" -o sample-app .
```

Les builds hermétiques et reproductibles sont décrits dans `poc/benchmarks/nix/`.
