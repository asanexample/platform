"""Minimal FastAPI service for app-${{ values.team }}-${{ values.product }}.

Exposes the liveness/readiness endpoint the platform manifests probe (/healthz) and a JSON root. No cloud/AWS
deps — an environment's AWS access (if any) is granted out-of-band via EKS Pod Identity to the named ServiceAccount.
Served by uvicorn, which shuts down gracefully on SIGTERM (k8s sends it on pod termination).
"""
import os
from datetime import datetime, timezone

from fastapi import FastAPI, Request

APP = "app-${{ values.team }}-${{ values.product }}"

app = FastAPI(title=APP)


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@app.get("/")
def root(request: Request) -> dict:
    return {
        "app": APP,
        "version": os.getenv("VERSION", "dev"),
        "namespace": os.getenv("NAMESPACE", "unknown"),
        "hostname": request.headers.get("host", ""),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
