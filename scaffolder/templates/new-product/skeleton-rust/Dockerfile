# Multi-stage: build a static musl binary, run on distroless/static (no shell, non-root uid 65532). Builds
# NATIVELY per arch (buildx emulates the non-host arch) so no cross-linker setup — musl-tools' native musl-gcc
# suffices. Static like the Go starter → the smallest possible image.
FROM rust:1-slim AS build

WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends musl-tools && rm -rf /var/lib/apt/lists/* && \
    rustup target add "$(uname -m)-unknown-linux-musl"

# Copy manifests + lock first so the dependency build caches across source-only changes.
COPY Cargo.toml Cargo.lock ./
COPY src/ src/
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    cargo build --release --locked --target "$(uname -m)-unknown-linux-musl" && \
    cp "target/$(uname -m)-unknown-linux-musl/release/app" /app/app-bin

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /app/app-bin /app
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/app"]
