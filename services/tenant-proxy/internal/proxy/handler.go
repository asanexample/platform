// Package proxy is the request path of the P13 read-tenant proxy: it authenticates the Grafana-
// forwarded OIDC token, resolves the caller's readable tenant scope, stamps X-Scope-OrgID, and
// reverse-proxies to the upstream Mimir/Loki/Tempo query API.
//
// It is fail-closed by construction: any request that is not positively authenticated AND resolved
// to a non-empty tenant scope is rejected before it reaches the upstream. An inbound X-Scope-OrgID
// (a spoof attempt) is always discarded and replaced with the resolved value.
package proxy

import (
	"context"
	"log/slog"
	"net/http"
	"strings"

	"github.com/asanexample/platform/services/tenant-proxy/internal/auth"
	"github.com/asanexample/platform/services/tenant-proxy/internal/tenant"
)

// Default header names. IDTokenHeader is the header Grafana's oauthPassThru populates with the
// upstream OIDC token (confirmed as X-Id-Token in the P13 spike, #590). Grafana forwards the access
// token in AuthzHeader, which is the more reliable of the two (oauthPassThru intermittently drops the
// id_token) — the userinfo fallback uses it. ScopeHeader is what the stores read for tenant selection.
const (
	IDTokenHeader = "X-Id-Token"
	AuthzHeader   = "Authorization"
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
	userinfo auth.UserInfoResolver // optional access-token fallback; nil → id_token-only
	resolver *tenant.Resolver
	upstream http.Handler
	metrics  Metrics
	log      *slog.Logger
}

// New builds a Handler. upstream is the reverse proxy to the store; it is invoked only after a
// request is authenticated and scoped. userinfo may be nil, in which case the proxy authenticates
// from the X-Id-Token header only; when non-nil it is the fallback for requests whose id_token is
// missing or unusable (resolving the caller's groups from their Authorization Bearer access token).
func New(v auth.Verifier, userinfo auth.UserInfoResolver, r *tenant.Resolver, upstream http.Handler, m Metrics, log *slog.Logger) *Handler {
	if log == nil {
		log = slog.Default()
	}
	return &Handler{verifier: v, userinfo: userinfo, resolver: r, upstream: upstream, metrics: m, log: log}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	// Liveness/readiness must never require a token.
	if req.URL.Path == healthPath {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
		return
	}

	claims, reason, detail := h.authenticate(req.Context(), req)
	if claims == nil {
		h.deny(w, req, http.StatusUnauthorized, reason, detail)
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

	// Anti-spoof / no-leak: never trust an inbound scope; overwrite with the resolved scope, and drop
	// both identity headers so neither the id_token nor the access token reaches the upstream store.
	req.Header.Set(ScopeHeader, scope)
	req.Header.Del(IDTokenHeader)
	req.Header.Del(AuthzHeader)

	h.metrics.Allowed()
	h.log.LogAttrs(req.Context(), slog.LevelDebug, "allow",
		slog.String("sub", claims.Subject), slog.String("scope", scope), slog.String("path", req.URL.Path))
	h.upstream.ServeHTTP(w, req)
}

// authenticate resolves verified Claims from the request's identity headers, trying each source in
// fail-closed order: the Grafana-forwarded X-Id-Token first, then — if a userinfo resolver is
// configured — the Authorization Bearer access token resolved to groups via userinfo. The access-token
// path is the robustness fallback for Grafana's intermittently-dropped id_token: a present-but-invalid
// id_token does not short-circuit, it falls through to the access token. Returns nil claims plus a deny
// reason/detail when no source produced a verified identity.
func (h *Handler) authenticate(ctx context.Context, req *http.Request) (*auth.Claims, string, string) {
	var lastErr string
	presented := false

	if raw := req.Header.Get(IDTokenHeader); raw != "" {
		presented = true
		if claims, err := h.verifier.Verify(ctx, raw); err == nil {
			return claims, "", ""
		} else {
			lastErr = err.Error()
			h.log.LogAttrs(ctx, slog.LevelDebug, "id_token verify failed; trying access-token fallback",
				slog.String("detail", lastErr))
		}
	}

	if h.userinfo != nil {
		if bearer := bearerToken(req); bearer != "" {
			presented = true
			if claims, err := h.userinfo.Resolve(ctx, bearer); err == nil {
				return claims, "", ""
			} else {
				lastErr = err.Error()
			}
		}
	}

	if !presented {
		return nil, reasonNoToken, "no identity presented (X-Id-Token or Authorization bearer)"
	}
	return nil, reasonBadToken, lastErr
}

// bearerToken extracts the token from an `Authorization: Bearer <token>` header (scheme match is
// case-insensitive per RFC 6750). Returns "" when the header is absent or not a bearer credential.
func bearerToken(req *http.Request) string {
	const prefix = "Bearer "
	v := req.Header.Get(AuthzHeader)
	if len(v) <= len(prefix) || !strings.EqualFold(v[:len(prefix)], prefix) {
		return ""
	}
	return strings.TrimSpace(v[len(prefix):])
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
