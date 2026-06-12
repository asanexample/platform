# Multi-stage: install prod deps on node:22-slim, run on distroless/nodejs (no shell, non-root uid 65532).
# Express is pure JS, so npm ci works on both amd64 and arm64 with no native build tooling.
FROM node:22-slim AS build

WORKDIR /app
# Copy the manifests first so the dependency layer caches across source-only changes.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY src/ src/

FROM gcr.io/distroless/nodejs22-debian12:nonroot

WORKDIR /app
COPY --from=build /app/node_modules node_modules
COPY --from=build /app/src src
COPY package.json ./

EXPOSE 8080

# The distroless nodejs image's entrypoint is `node`; pass the script. Runs as the non-root user (65532).
CMD ["src/server.js"]
