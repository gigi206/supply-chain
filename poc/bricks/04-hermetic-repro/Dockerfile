# sample-app : binaire compilé sans réseau dans l'image de build (contexte nommé
# « builder », épinglé par digest), fermeture Hermeto montée en lecture seule
# (contexte nommé « deps »), image finale minimale.
FROM builder AS build
WORKDIR /src
COPY . .
RUN --network=none --mount=type=bind,from=deps,target=/deps \
    GOPROXY=file:///deps/deps/gomod/pkg/mod/cache/download GOMODCACHE=/tmp/mod GOCACHE=/tmp/cache \
    go build -trimpath -buildvcs=false -ldflags "-s -w -buildid= -X main.Version=1.0.0" -o /out/sample-app .

FROM scratch
COPY --from=build /out/sample-app /sample-app
USER 65532:65532
ENTRYPOINT ["/sample-app"]
