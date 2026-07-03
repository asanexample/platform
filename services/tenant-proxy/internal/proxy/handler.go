// Package proxy is the request path of the P13 read-tenant proxy: it authenticates the Grafana-
// forwarded OIDC token, resolves the caller's readable tenant scope, stamps X-Scope-OrgID, and
// reverse-proxies to the upstream Mimir/Loki/Tempo query API.
//
// It is fail-closed by construction: any request that is not positively authenticated AND resolved
// to a non-empty tenant scope is rejected before it reaches the upstream. An inbound X-Scope-OrgID
// (a spoof attempt) is always discarded and replaced with the resolved value.
package proxy

import (
	"log/slog"
	"net/http"

	"github.com/asanexample/platform/services/tenant-proxy/internal/auth"
	"github.com/asanexample/platform/services/tenant-proxy/internal/tenant"
)

// Default header names. IDTokenHeader is the header Grafana's oauthPassThru populates with the
// upstream OIDC token (confirmed as X-Id-Token in the P13 spike, #590). ScopeHeader is what the
// stores read for tenant selection.
const (
	IDTokenHeader = "X-Id-Token"
	ScopeHeader   = "X-Scope-OrgID"
	healthPath    = "/healthz"
)

// Metrics records the outcome of each decision. Implemented by a Prometheus CounterVec in main; a
// no-op in tests. Kept as an interface so the handler has no hard Prometheus dependency.
type Metrics interface {
	Allowed()
	Denied(reason string)
}

// Deny reasons (also the metric label values). Stable — dashboards/alerts key off them.
const (
	reasonNoToken    = "no_token"
	reasonBadToken   = "bad_token"
	reasonNoTenant   = "no_tenant"
	reasonResolveErr = "resolve_error"
)

// Handler authenticates + scopes a request and proxies it upstream.
type Handler struct {
	verifier auth.Verifier
	resolver *tenant.Resolver
	upstream http.Handler
	metrics  Metrics
	log      *slog.Logger
}

// New builds a Handler. upstream is the reverse proxy to the store; it is invoked only after a
// request is authenticated and scoped.
func New(v auth.Verifier, r *tenant.Resolver, upstream http.Handler, m Metrics, log *slog.Logger) *Handler {
	if log == nil {
		log = slog.Default()
	}
	return &Handler{verifier: v, resolver: r, upstream: upstream, metrics: m, log: log}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	// Liveness/readiness must never require a token.
	if req.URL.Path == healthPath {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
		return
	}

	raw := req.Header.Get(IDTokenHeader)
	if raw == "" {
		h.deny(w, req, http.StatusUnauthorized, reasonNoToken, "missing "+IDTokenHeader)
		return
	}

	claims, err := h.verifier.Verify(req.Context(), raw)
	if err != nil {
		h.deny(w, req, http.StatusUnauthorized, reasonBadToken, err.Error())
		return
	}

	scope, err := h.resolver.Scope(claims.Groups)
	if err != nil {
		reason, code := reasonResolveErr, http.StatusForbidden
		if err == tenant.ErrNoTenant {
			reason = reasonNoTenant
		}
		h.deny(w, req, code, reason, err.Error())
		return
	}

	// Anti-spoof: never trust an inbound scope/token; overwrite with the resolved scope and drop the
	// user token so it is not leaked to the upstream store.
	req.Header.Set(ScopeHeader, scope)
	req.Header.Del(IDTokenHeader)

	h.metrics.Allowed()
	h.log.LogAttrs(req.Context(), slog.LevelDebug, "allow",
		slog.String("sub", claims.Subject), slog.String("scope", scope), slog.String("path", req.URL.Path))
	h.upstream.ServeHTTP(w, req)
}

func (h *Handler) deny(w http.ResponseWriter, req *http.Request, code int, reason, detail string) {
	h.metrics.Denied(reason)
	h.log.LogAttrs(req.Context(), slog.LevelInfo, "deny",
		slog.String("reason", reason), slog.String("detail", detail),
		slog.String("path", req.URL.Path), slog.Int("status", code))
	http.Error(w, reason, code)
}

// nopMetrics is a Metrics that does nothing (default / tests).
type nopMetrics struct{}

func (nopMetrics) Allowed()      {}
func (nopMetrics) Denied(string) {}

// NopMetrics returns a Metrics implementation that records nothing.
func NopMetrics() Metrics { return nopMetrics{} }
