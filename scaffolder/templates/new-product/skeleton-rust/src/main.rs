//! Minimal Axum service for app-${{ values.team }}-${{ values.product }}. Exposes the liveness/readiness
//! endpoint the platform manifests probe (/healthz) and a JSON root. No cloud/AWS deps — a tenant's AWS access
//! (if any) is granted out-of-band via EKS Pod Identity to the named ServiceAccount.
use axum::{http::HeaderMap, routing::get, Json, Router};
use serde_json::{json, Value};
use std::env;

const APP: &str = "app-${{ values.team }}-${{ values.product }}";

async fn healthz() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

async fn root(headers: HeaderMap) -> Json<Value> {
    let host = headers.get("host").and_then(|v| v.to_str().ok()).unwrap_or("");
    Json(json!({
        "app": APP,
        "version": env::var("VERSION").unwrap_or_else(|_| "dev".into()),
        "namespace": env::var("NAMESPACE").unwrap_or_else(|_| "unknown".into()),
        "hostname": host,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }))
}

fn app() -> Router {
    Router::new().route("/healthz", get(healthz)).route("/", get(root))
}

#[tokio::main]
async fn main() {
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await.unwrap();
    println!("starting {APP} on :8080");
    axum::serve(listener, app())
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap();
}

// Drain in-flight requests on SIGTERM (k8s) or SIGINT.
async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut term = signal(SignalKind::terminate()).unwrap();
        let mut int = signal(SignalKind::interrupt()).unwrap();
        tokio::select! {
            _ = term.recv() => {},
            _ = int.recv() => {},
        }
    }
    #[cfg(not(unix))]
    {
        tokio::signal::ctrl_c().await.ok();
    }
    println!("shutting down (draining in-flight requests)…");
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt; // for `oneshot`

    // Asserts the liveness/readiness endpoint returns 200 {"status":"ok"}.
    #[tokio::test]
    async fn healthz_returns_ok() {
        let resp = app()
            .oneshot(Request::builder().uri("/healthz").body(axum::body::Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let bytes = to_bytes(resp.into_body(), usize::MAX).await.unwrap();
        let v: Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(v["status"], "ok");
    }
}
