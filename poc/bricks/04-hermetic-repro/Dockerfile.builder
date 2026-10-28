# Image de build Go minimale, construite par la plateforme à partir d'entrées
# épinglées (toolchain Go officielle, busybox statique) : brique 11 en réduit.
FROM scratch
COPY busybox /bin/busybox
RUN ["/bin/busybox", "--install", "-s", "/bin"]
COPY go /usr/local/go
ENV PATH=/usr/local/go/bin:/bin \
    HOME=/tmp \
    CGO_ENABLED=0 \
    GOTOOLCHAIN=local \
    GOFLAGS=-mod=readonly \
    GOSUMDB=off
