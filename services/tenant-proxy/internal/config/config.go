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
	ListenAddr      string
	MetricsAddr     string
	UpstreamURL     *url.URL
	JWKSURL         string
	Issuer          string
	Audience        string
	Tenants         []string
	AdminGroup      string
	UpstreamTimeout time.Duration
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
//	UPSTREAM_TIMEOUT   (default 30s)    — upstream request timeout
func Load() (*Config, error) {
	c := &Config{
		ListenAddr:      envOr("LISTEN_ADDR", ":8080"),
		MetricsAddr:     envOr("METRICS_ADDR", ":9090"),
		JWKSURL:         os.Getenv("JWKS_URL"),
		Issuer:          os.Getenv("OIDC_ISSUER"),
		Audience:        os.Getenv("OIDC_AUDIENCE"),
		AdminGroup:      os.Getenv("ADMIN_GROUP"),
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

	if d := os.Getenv("UPSTREAM_TIMEOUT"); d != "" {
		parsed, err := time.ParseDuration(d)
		if err != nil {
			return nil, fmt.Errorf("config: UPSTREAM_TIMEOUT: %w", err)
		}
		c.UpstreamTimeout = parsed
	}

	return c, nil
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
