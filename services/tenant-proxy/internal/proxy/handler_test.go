package proxy

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/asanexample/platform/services/tenant-proxy/internal/auth"
	"github.com/asanexample/platform/services/tenant-proxy/internal/tenant"
)

// fakeVerifier returns canned results so the handler's branches are tested without real JWTs.
type fakeVerifier struct {
	claims *auth.Claims
	err    error
}

func (f fakeVerifier) Verify(context.Context, string) (*auth.Claims, error) {
	return f.claims, f.err
}

// recordingUpstream captures whether it was called and with what headers.
type recordingUpstream struct {
	called     bool
	gotScope   string
	gotIDToken string
}

func (u *recordingUpstream) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	u.called = true
	u.gotScope = r.Header.Get(ScopeHeader)
	u.gotIDToken = r.Header.Get(IDTokenHeader)
	w.WriteHeader(http.StatusOK)
}

func newHandler(t *testing.T, v auth.Verifier, up http.Handler) *Handler {
	t.Helper()
	r, err := tenant.NewResolver([]string{"alpha", "bravo", "platform"}, "platform-admins")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	return New(v, r, up, NopMetrics(), nil)
}

// TestServeHTTP_denyDoesNotReachUpstream is the property that matters most: a rejected request must
// never be proxied to the store.
func TestServeHTTP_denyDoesNotReachUpstream(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		idToken  string
		verifier auth.Verifier
		wantCode int
	}{
		{"no token", "", fakeVerifier{}, http.StatusUnauthorized},
		{"bad token", "tok", fakeVerifier{err: errors.New("bad sig")}, http.StatusUnauthorized},
		{"no tenant", "tok", fakeVerifier{claims: &auth.Claims{Groups: []string{"offline_access"}}}, http.StatusForbidden},
		{"unknown team", "tok", fakeVerifier{claims: &auth.Claims{Groups: []string{"gamma"}}}, http.StatusForbidden},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			up := &recordingUpstream{}
			h := newHandler(t, tc.verifier, up)
			req := httptest.NewRequest(http.MethodGet, "/api/v1/query?query=up", nil)
			if tc.idToken != "" {
				req.Header.Set(IDTokenHeader, tc.idToken)
			}
			rr := httptest.NewRecorder()
			h.ServeHTTP(rr, req)

			if rr.Code != tc.wantCode {
				t.Errorf("status = %d; want %d", rr.Code, tc.wantCode)
			}
			if up.called {
				t.Errorf("upstream was called on a denied request (%s)", tc.name)
			}
		})
	}
}

func TestServeHTTP_allowStampsScopeAndStripsToken(t *testing.T) {
	t.Parallel()
	up := &recordingUpstream{}
	h := newHandler(t, fakeVerifier{claims: &auth.Claims{Subject: "u1", Groups: []string{"alpha"}}}, up)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/query?query=up", nil)
	req.Header.Set(IDTokenHeader, "valid-token")
	// A spoofed inbound scope must be overwritten, not honored.
	req.Header.Set(ScopeHeader, "platform|bravo")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d; want 200", rr.Code)
	}
	if !up.called {
		t.Fatal("upstream was not called on an allowed request")
	}
	if up.gotScope != "alpha" {
		t.Errorf("upstream X-Scope-OrgID = %q; want alpha (spoofed inbound scope must be overwritten)", up.gotScope)
	}
	if up.gotIDToken != "" {
		t.Errorf("X-Id-Token was forwarded upstream (%q); it must be stripped", up.gotIDToken)
	}
}

func TestServeHTTP_adminGetsFederatedScope(t *testing.T) {
	t.Parallel()
	up := &recordingUpstream{}
	h := newHandler(t, fakeVerifier{claims: &auth.Claims{Groups: []string{"platform-admins"}}}, up)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/query?query=up", nil)
	req.Header.Set(IDTokenHeader, "valid-token")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)

	if up.gotScope != "alpha|bravo|platform" {
		t.Errorf("admin scope = %q; want alpha|bravo|platform", up.gotScope)
	}
}

func TestServeHTTP_healthBypassesAuth(t *testing.T) {
	t.Parallel()
	up := &recordingUpstream{}
	h := newHandler(t, fakeVerifier{err: errors.New("should not be called")}, up)
	req := httptest.NewRequest(http.MethodGet, healthPath, nil)
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("healthz status = %d; want 200", rr.Code)
	}
	if up.called {
		t.Error("healthz was proxied upstream; it must be handled locally")
	}
}
