package config

import (
	"maps"
	"slices"
	"testing"
)

func TestLoad(t *testing.T) {
	base := map[string]string{
		"UPSTREAM_URL":  "http://mimir-gateway.observability.svc/prometheus",
		"JWKS_URL":      "https://kc.test/realms/platform/protocol/openid-connect/certs",
		"OIDC_ISSUER":   "https://kc.test/realms/platform",
		"OIDC_AUDIENCE": "grafana",
		"TENANTS":       "alpha, bravo ,platform",
		"ADMIN_GROUP":   "platform-admins",
	}

	t.Run("valid config parses", func(t *testing.T) {
		setEnv(t, base)
		c, err := Load()
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if got := len(c.Tenants); got != 3 {
			t.Errorf("tenants = %v; want 3 (trimmed)", c.Tenants)
		}
		if c.UpstreamURL.Host != "mimir-gateway.observability.svc" {
			t.Errorf("host = %q", c.UpstreamURL.Host)
		}
		if c.ListenAddr != ":8080" || c.MetricsAddr != ":9090" {
			t.Errorf("defaults not applied: %q %q", c.ListenAddr, c.MetricsAddr)
		}
	})

	t.Run("each required var is enforced", func(t *testing.T) {
		for k := range base {
			m := clone(base)
			delete(m, k)
			setEnv(t, m)
			if _, err := Load(); err == nil {
				t.Errorf("Load succeeded with %s missing; want error", k)
			}
		}
	})

	t.Run("relative upstream url rejected", func(t *testing.T) {
		m := clone(base)
		m["UPSTREAM_URL"] = "mimir-gateway/prometheus"
		setEnv(t, m)
		if _, err := Load(); err == nil {
			t.Error("Load accepted a relative UPSTREAM_URL; want error")
		}
	})

	t.Run("userinfo fallback is optional and defaults off", func(t *testing.T) {
		setEnv(t, base)
		c, err := Load()
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if c.UserInfoURL != "" {
			t.Errorf("UserInfoURL = %q; want empty (fallback off by default)", c.UserInfoURL)
		}
		if c.UserInfoCacheTTL <= 0 {
			t.Errorf("UserInfoCacheTTL = %s; want a positive default", c.UserInfoCacheTTL)
		}
	})

	t.Run("valid userinfo url + ttl parse", func(t *testing.T) {
		m := clone(base)
		m["USERINFO_URL"] = "https://kc.test/realms/platform/protocol/openid-connect/userinfo"
		m["USERINFO_CACHE_TTL"] = "45s"
		setEnv(t, m)
		c, err := Load()
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if c.UserInfoURL != m["USERINFO_URL"] {
			t.Errorf("UserInfoURL = %q; want %q", c.UserInfoURL, m["USERINFO_URL"])
		}
		if c.UserInfoCacheTTL.String() != "45s" {
			t.Errorf("UserInfoCacheTTL = %s; want 45s", c.UserInfoCacheTTL)
		}
	})

	t.Run("malformed userinfo config rejected", func(t *testing.T) {
		for name, mut := range map[string]func(m map[string]string){
			"relative url": func(m map[string]string) { m["USERINFO_URL"] = "kc.test/userinfo" },
			"bad ttl":      func(m map[string]string) { m["USERINFO_URL"] = "https://kc/u"; m["USERINFO_CACHE_TTL"] = "soon" },
			"negative ttl": func(m map[string]string) { m["USERINFO_URL"] = "https://kc/u"; m["USERINFO_CACHE_TTL"] = "-5s" },
		} {
			m := clone(base)
			mut(m)
			setEnv(t, m)
			if _, err := Load(); err == nil {
				t.Errorf("Load accepted %s; want error", name)
			}
		}
	})
}

func TestParseGrants(t *testing.T) {
	t.Parallel()
	t.Run("valid + empty", func(t *testing.T) {
		t.Parallel()
		cases := map[string]map[string][]string{
			"":                          {},
			"  ":                        {},
			"bravo:alpha":               {"bravo": {"alpha"}},
			"bravo:alpha,platform":      {"bravo": {"alpha", "platform"}},
			"bravo:alpha; charlie:beta": {"bravo": {"alpha"}, "charlie": {"beta"}},
			"bravo:alpha;;":             {"bravo": {"alpha"}}, // empty trailing entries ignored
			" bravo : alpha , beta ":    {"bravo": {"alpha", "beta"}},
		}
		for in, want := range cases {
			got, err := parseGrants(in)
			if err != nil {
				t.Errorf("parseGrants(%q) unexpected error: %v", in, err)
				continue
			}
			if !maps.EqualFunc(got, want, slices.Equal) {
				t.Errorf("parseGrants(%q) = %v; want %v", in, got, want)
			}
		}
	})

	t.Run("malformed is a hard error (fail-closed)", func(t *testing.T) {
		t.Parallel()
		for _, in := range []string{
			"bravo",         // no colon
			"bravo:",        // no owners
			":alpha",        // no grantee
			"bravo:alpha;x", // second entry malformed
		} {
			if _, err := parseGrants(in); err == nil {
				t.Errorf("parseGrants(%q) succeeded; want error", in)
			}
		}
	})
}

func setEnv(t *testing.T, m map[string]string) {
	t.Helper()
	// Clear everything this package reads, then set the provided subset.
	for _, k := range []string{"UPSTREAM_URL", "JWKS_URL", "OIDC_ISSUER", "OIDC_AUDIENCE", "TENANTS", "ADMIN_GROUP", "GRANTS", "LISTEN_ADDR", "METRICS_ADDR", "UPSTREAM_TIMEOUT", "USERINFO_URL", "USERINFO_CACHE_TTL"} {
		t.Setenv(k, "")
	}
	for k, v := range m {
		t.Setenv(k, v)
	}
}

func clone(m map[string]string) map[string]string {
	out := make(map[string]string, len(m))
	maps.Copy(out, m)
	return out
}
