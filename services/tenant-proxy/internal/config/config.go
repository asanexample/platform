// Package config loads the tenant-proxy configuration from the environment and validates it up
// front — a security front door must refuse to start on a bad config rather than fail open later.
package config

import (
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"
)

// Config is the fully-validated runtime configuration.
type Config struct {
	ListenAddr       string
	MetricsAddr      string
	UpstreamURL      *url.URL
	JWKSURL          string
	Issuer           string
	Audience         string
	Tenants          []string
	AdminGroup       string
	Grants           map[string][]string
	UpstreamTimeout  time.Duration
	UserInfoURL      string
	UserInfoCacheTTL time.Duration
}

// Load reads and validates configuration from the environment.
//
//	LISTEN_ADDR        (default :8080)  — proxy listen address
//	METRICS_ADDR       (default :9090)  — /metrics + /healthz listen address (separate port)
//	UPSTREAM_URL       (required)       — the store query API (e.g. http://mimir-gateway.observability.svc/prometheus)
//	JWKS_URL           (required)       — realm JWKS endpoint
//	OIDC_ISSUER        (required)       — expected token issuer
//	OIDC_AUDIENCE      (required)       — expected token audience (Grafana client id)
//	TENANTS            (required)       — comma-separated known team tenants (alpha,bravo,platform)
//	ADMIN_GROUP        (required)       — group granting federated all-tenant reads
//	GRANTS             (optional)       — cross-team read grants: `grantee:owner1,owner2;grantee2:owner3`
//	                                      (e.g. "bravo:alpha" = group bravo may also read alpha's tenant)
//	UPSTREAM_TIMEOUT   (default 30s)    — upstream request timeout
//	USERINFO_URL       (optional)       — OIDC userinfo endpoint (…/protocol/openid-connect/userinfo).
//	                                      When set, enables the robust fallback: a request without a
//	                                      usable X-Id-Token is authenticated via its Authorization
//	                                      Bearer access token, resolved to groups through userinfo.
//	                                      Unset → id_token-only (the fallback is disabled).
//	USERINFO_CACHE_TTL (default 30s)    — how long a userinfo result is reused per access token
func Load() (*Config, error) {
	c := &Config{
		ListenAddr:      envOr("LISTEN_ADDR", ":8080"),
		MetricsAddr:     envOr("METRICS_ADDR", ":9090"),
		JWKSURL:         os.Getenv("JWKS_URL"),
		Issuer:          os.Getenv("OIDC_ISSUER"),
		Audience:        os.Getenv("OIDC_AUDIENCE"),
		AdminGroup:      os.Getenv("ADMIN_GROUP"),
		UserInfoURL:     strings.TrimSpace(os.Getenv("USERINFO_URL")),
		UpstreamTimeout: 30 * time.Second,
	}

	var missing []string
	for k, v := range map[string]string{
		"UPSTREAM_URL":  os.Getenv("UPSTREAM_URL"),
		"JWKS_URL":      c.JWKSURL,
		"OIDC_ISSUER":   c.Issuer,
		"OIDC_AUDIENCE": c.Audience,
		"ADMIN_GROUP":   c.AdminGroup,
		"TENANTS":       os.Getenv("TENANTS"),
	} {
		if strings.TrimSpace(v) == "" {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("config: missing required env: %s", strings.Join(missing, ", "))
	}

	u, err := url.Parse(os.Getenv("UPSTREAM_URL"))
	if err != nil {
		return nil, fmt.Errorf("config: UPSTREAM_URL: %w", err)
	}
	if u.Scheme == "" || u.Host == "" {
		return nil, fmt.Errorf("config: UPSTREAM_URL must be absolute (scheme+host), got %q", u.String())
	}
	c.UpstreamURL = u

	for t := range strings.SplitSeq(os.Getenv("TENANTS"), ",") {
		if t = strings.TrimSpace(t); t != "" {
			c.Tenants = append(c.Tenants, t)
		}
	}
	if len(c.Tenants) == 0 {
		return nil, fmt.Errorf("config: TENANTS resolved to an empty list")
	}

	grants, err := parseGrants(os.Getenv("GRANTS"))
	if err != nil {
		return nil, err
	}
	c.Grants = grants

	if d := os.Getenv("UPSTREAM_TIMEOUT"); d != "" {
		parsed, err := time.ParseDuration(d)
		if err != nil {
			return nil, fmt.Errorf("config: UPSTREAM_TIMEOUT: %w", err)
		}
		c.UpstreamTimeout = parsed
	}

	// Optional userinfo fallback. If configured it must be an absolute URL — a half-set fallback would
	// silently disable the robustness path, so validate rather than ignore a malformed value.
	if c.UserInfoURL != "" {
		u, err := url.Parse(c.UserInfoURL)
		if err != nil {
			return nil, fmt.Errorf("config: USERINFO_URL: %w", err)
		}
		if u.Scheme == "" || u.Host == "" {
			return nil, fmt.Errorf("config: USERINFO_URL must be absolute (scheme+host), got %q", u.String())
		}
	}
	c.UserInfoCacheTTL = 30 * time.Second
	if d := os.Getenv("USERINFO_CACHE_TTL"); d != "" {
		parsed, err := time.ParseDuration(d)
		if err != nil {
			return nil, fmt.Errorf("config: USERINFO_CACHE_TTL: %w", err)
		}
		if parsed <= 0 {
			return nil, fmt.Errorf("config: USERINFO_CACHE_TTL must be positive, got %s", d)
		}
		c.UserInfoCacheTTL = parsed
	}

	return c, nil
}

// parseGrants parses the GRANTS env into a grantee→owners map. Format:
//
//	grantee:owner1,owner2;grantee2:owner3
//
// Empty input → empty map (no grants). Malformed input is a hard error — a read front door must
// refuse to start on a config it can't parse rather than silently drop grants (fail-closed on config).
func parseGrants(raw string) (map[string][]string, error) {
	out := map[string][]string{}
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return out, nil
	}
	for entry := range strings.SplitSeq(raw, ";") {
		if strings.TrimSpace(entry) == "" {
			continue
		}
		grantee, ownersRaw, ok := strings.Cut(entry, ":")
		grantee = strings.TrimSpace(grantee)
		if !ok || grantee == "" {
			return nil, fmt.Errorf("config: GRANTS entry %q must be `grantee:owner1,owner2`", entry)
		}
		var owners []string
		for o := range strings.SplitSeq(ownersRaw, ",") {
			if o = strings.TrimSpace(o); o != "" {
				owners = append(owners, o)
			}
		}
		if len(owners) == 0 {
			return nil, fmt.Errorf("config: GRANTS entry %q has no owner tenants", entry)
		}
		out[grantee] = append(out[grantee], owners...)
	}
	return out, nil
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
