package tenant

import (
	"errors"
	"testing"
)

func TestNewResolver_rejectsBadConfig(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		tenants    []string
		adminGroup string
	}{
		{"empty admin group", []string{"alpha"}, ""},
		{"no tenants", nil, "platform-admins"},
		{"only blank tenants", []string{"", "  "}, "platform-admins"},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if _, err := NewResolver(tc.tenants, tc.adminGroup); err == nil {
				t.Fatalf("expected error for %s, got nil", tc.name)
			}
		})
	}
}

// TestScope_denyPaths comes first (fail-safe-deny is the property that matters most for a
// read-authorization component): every input that must NOT be granted a scope.
func TestScope_denyPaths(t *testing.T) {
	t.Parallel()
	r := mustResolver(t)
	deny := [][]string{
		nil,                                     // no groups at all
		{},                                      // empty groups
		{"offline_access", "uma_authorization"}, // only non-tenant groups
		{"gamma"},                               // a team that isn't a known tenant
		{"Alpha"},                               // case must match exactly — no fuzzy matching
		{"alpha "},                              // whitespace is not trimmed off group values
		{"platform-admin"},                      // near-miss on the admin group name must NOT grant admin
	}
	for _, groups := range deny {
		got, err := r.Scope(groups)
		if !errors.Is(err, ErrNoTenant) {
			t.Errorf("Scope(%v) = %q, %v; want ErrNoTenant", groups, got, err)
		}
		if got != "" {
			t.Errorf("Scope(%v) returned non-empty scope %q on deny", groups, got)
		}
	}
}

func TestScope_allowPaths(t *testing.T) {
	t.Parallel()
	r := mustResolver(t)
	tests := []struct {
		name   string
		groups []string
		want   string
	}{
		{"single team", []string{"alpha"}, "alpha"},
		{"team plus noise", []string{"alpha", "offline_access"}, "alpha"},
		{"two teams sorted deterministically", []string{"bravo", "alpha"}, "alpha|bravo"},
		{"duplicate groups collapse", []string{"alpha", "alpha"}, "alpha"},
		{"platform team member", []string{"platform"}, "platform"},
		{"admin sees all tenants federated", []string{"platform-admins"}, "alpha|bravo|platform"},
		{"admin wins even with a team group", []string{"platform-admins", "alpha"}, "alpha|bravo|platform"},
		{"admin wins even with no team group", []string{"platform-admins", "offline_access"}, "alpha|bravo|platform"},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := r.Scope(tc.groups)
			if err != nil {
				t.Fatalf("Scope(%v) unexpected error: %v", tc.groups, err)
			}
			if got != tc.want {
				t.Errorf("Scope(%v) = %q; want %q", tc.groups, got, tc.want)
			}
		})
	}
}

// TestScope_orderIndependent proves the scope is deterministic regardless of the order groups
// arrive in — a token must never yield two different X-Scope-OrgID values for the same user.
func TestScope_orderIndependent(t *testing.T) {
	t.Parallel()
	r := mustResolver(t)
	a, err1 := r.Scope([]string{"alpha", "bravo", "platform"})
	b, err2 := r.Scope([]string{"platform", "alpha", "bravo"})
	if err1 != nil || err2 != nil {
		t.Fatalf("unexpected errors: %v %v", err1, err2)
	}
	if a != b {
		t.Errorf("order changed scope: %q vs %q", a, b)
	}
	if a != "alpha|bravo|platform" {
		t.Errorf("scope = %q; want alpha|bravo|platform", a)
	}
}

func mustResolver(t *testing.T) *Resolver {
	t.Helper()
	r, err := NewResolver([]string{"alpha", "bravo", "platform"}, "platform-admins")
	if err != nil {
		t.Fatalf("NewResolver: %v", err)
	}
	return r
}
