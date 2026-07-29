# syntax=docker/dockerfile:1.24

FROM golang:1.26.5 AS builder

# Deterministic timestamps for anything the build writes
ARG SOURCE_DATE_EPOCH=0
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}

WORKDIR /src

# Cache module downloads separately from source changes
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
# -trimpath + CGO_ENABLED=0 + -buildvcs=false + stripped build IDs => bit-identical binary
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOFLAGS=-mod=readonly \
    go build -trimpath -buildvcs=false -ldflags="-s -w -buildid=" \
      -o /uwsgi_exporter ./cmd/uwsgi_exporter \
 && (cd / && sha256sum uwsgi_exporter > /uwsgi_exporter.sha256)

# Artifact stage: `docker build --target artifact --output dist .`
FROM scratch AS artifact
COPY --from=builder /uwsgi_exporter /uwsgi_exporter.sha256 /

FROM scratch AS final

COPY --from=builder /uwsgi_exporter /bin/uwsgi_exporter

# scratch has no /etc/passwd; use numeric uid:gid (nobody)
USER        65534:65534
EXPOSE      9117
ENTRYPOINT  [ "/bin/uwsgi_exporter" ]
