# Build the manager binary.
# NOTE: build context is the REPO ROOT (not operators/activation), because the module consumes the
# shared github.com/asanexample/platform/pkg via a local `replace => ../../pkg` that points outside the
# module dir. Build with: docker build -f operators/activation/Dockerfile <repo-root>  (the Makefile does this).
FROM golang:1.25 AS builder
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace
# Module manifests + the replace target, copied first for dependency-download layer caching.
COPY operators/activation/go.mod operators/activation/go.mod
COPY operators/activation/go.sum operators/activation/go.sum
COPY pkg/ pkg/
WORKDIR /workspace/operators/activation
RUN go mod download

# The operator source.
WORKDIR /workspace
COPY operators/activation/ operators/activation/
WORKDIR /workspace/operators/activation

# Build. GOARCH is left to the host/buildx platform so the binary matches the runtime image platform.
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -a -o manager cmd/main.go

# Use distroless as a minimal base image to package the manager binary.
FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder /workspace/operators/activation/manager .
USER 65532:65532

ENTRYPOINT ["/manager"]
