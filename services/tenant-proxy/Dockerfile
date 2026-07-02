# Build the tenant-proxy binary. Self-contained module (no shared pkg replace), so the build
# context is this directory. Build with: docker build services/tenant-proxy
FROM golang:1.25 AS builder
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace
# Manifests first for dependency-download layer caching.
COPY go.mod go.mod
COPY go.sum go.sum
RUN go mod download

COPY cmd/ cmd/
COPY internal/ internal/

# Static build so it runs on distroless. GOARCH follows the buildx platform.
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o tenant-proxy ./cmd/tenant-proxy

# Minimal, non-root runtime.
FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder /workspace/tenant-proxy /tenant-proxy
USER 65532:65532
EXPOSE 8080 9090
ENTRYPOINT ["/tenant-proxy"]
