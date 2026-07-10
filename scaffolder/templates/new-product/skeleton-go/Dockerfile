FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS build

WORKDIR /src
# go.mod + go.sum first so the module-download layer caches independently of source changes. go.sum is
# required because the starter ships with the OpenTelemetry SDK (observability by construction).
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY cmd/ cmd/

# Cross-compile to the target arch (buildx sets TARGETOS/TARGETARCH). The build runs natively on the arm64
# runner — no QEMU. Cache mounts persist the module + Go build/compile cache across builds so a small code
# change recompiles incrementally in seconds (trusted-ci#22).
ARG TARGETOS TARGETARCH
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o /app ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /app /app

EXPOSE 8080

# Run as the distroless nonroot user explicitly (uid:gid 65532). The base already defaults to nonroot,
# but an explicit USER makes it auditable and satisfies the image-runs-as-root scanners
# (Trivy DS-0002 / Semgrep missing-user-entrypoint).
USER 65532:65532

ENTRYPOINT ["/app"]
