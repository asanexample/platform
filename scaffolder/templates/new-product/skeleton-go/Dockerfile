FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS build

WORKDIR /src
# Stdlib-only: go.mod has no requires, so there is no go.sum to copy. `go mod download` is a no-op but
# kept so the layer caches dependency resolution once this app grows deps (add go.sum to the COPY then).
COPY go.mod ./
RUN go mod download
COPY cmd/ cmd/

# Cross-compile to the target arch (buildx sets TARGETOS/TARGETARCH) so multi-arch builds run on the native
# (amd64) toolchain with no QEMU emulation — Go cross-compiles for free.
ARG TARGETOS TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o /app ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /app /app

EXPOSE 8080

# Run as the distroless nonroot user explicitly (uid:gid 65532). The base already defaults to nonroot,
# but an explicit USER makes it auditable and satisfies the image-runs-as-root scanners
# (Trivy DS-0002 / Semgrep missing-user-entrypoint).
USER 65532:65532

ENTRYPOINT ["/app"]
