# Multi-stage: install deps on python:3.11-slim, run on distroless/python3 (no shell, non-root uid 65532).
# 3.11 matches the distroless/python3-debian12 runtime. Multi-arch: pip pulls amd64+arm64 wheels (fastapi/
# uvicorn are pure Python; pydantic-core ships abi3 wheels for both arches).
FROM python:3.11-slim AS build

WORKDIR /app
# Copy requirements first so the dependency layer caches across source-only changes.
COPY requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/pip pip install --target /deps -r requirements.txt

COPY app/ app/

FROM gcr.io/distroless/python3-debian12:nonroot

WORKDIR /app
ENV PYTHONPATH=/deps
COPY --from=build /deps /deps
COPY --from=build /app/app app

EXPOSE 8080

# Run as the distroless non-root user (uid 65532) explicitly — satisfies the image-runs-as-root scanners.
USER 65532:65532

# distroless/python3 entrypoint is `python3`; run uvicorn as a module (it shuts down gracefully on SIGTERM).
CMD ["-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
