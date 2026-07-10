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

// fakeUserInfo is a stand-in access-token resolver: it records the token it was asked to resolve and
// returns canned claims/err, so the handler's fallback branch is tested without a real userinfo server.
type fakeUserInfo struct {
	claims    *auth.Claims
	err       error
	gotToken  string
	callCount int
}

func (f *fakeUserInfo) Resolve(_ context.Context, accessToken string) (*auth.Claims, error) {
	f.gotToken = accessToken
	f.callCount++
	return f.claims, f.err
}

// recordingUpstream captures whether it was called and with what headers.
type recordingUpstream struct {
	called     bool
	gotScope   string
	gotIDToken string
	gotAuthz   string
}

func (u *recordingUpstream) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	u.called = true
	u.gotScope = r.Header.Get(ScopeHeader)
	u.gotIDToken = r.Header.Get(IDTokenHeader)
	u.gotAuthz = r.Header.Get(AuthzHeader)
	w.WriteHeader(http.StatusOK)
}

func newHandler(t *testing.T, v auth.Verifier, up http.Handler) *Handler {
	t.Helper()
	return newHandlerUI(t, v, nil, up)
}

func newHandlerUI(t *testing.T, v auth.Verifier, ui auth.UserInfoResolver, up http.Handler) *Handler {
	t.Helper()
	r, err := tenant.NewResolver([]string{"alpha", "bravo", "platform"}, "platform-admins", nil)
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	return New(v, ui, r, up, NopMetrics(), nil)
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

// TestServeHTTP_userInfoFallback covers the robustness path: when the id_token is missing or invalid,
// the handler authenticates from the Authorization Bearer access token via the userinfo resolver.
func TestServeHTTP_userInfoFallback(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		idToken    string
		verifier   auth.Verifier
		authz      string
		userinfo   *fakeUserInfo
		wantCode   int
		wantScope  string
		wantUICall bool
	}{
		{
			name:       "no id_token, valid access token resolves via userinfo",
			verifier:   fakeVerifier{},
			authz:      "Bearer access-tok",
			userinfo:   &fakeUserInfo{claims: &auth.Claims{Subject: "u1", Groups: []string{"alpha"}}},
			wantCode:   http.StatusOK,
			wantScope:  "alpha",
			wantUICall: true,
		},
		{
			name:       "invalid id_token falls through to a valid access token",
			idToken:    "stale",
			verifier:   fakeVerifier{err: errors.New("expired")},
			authz:      "Bearer access-tok",
			userinfo:   &fakeUserInfo{claims: &auth.Claims{Groups: []string{"bravo"}}},
			wantCode:   http.StatusOK,
			wantScope:  "bravo",
			wantUICall: true,
		},
		{
			name:       "valid id_token wins; userinfo is not consulted",
			idToken:    "good",
			verifier:   fakeVerifier{claims: &auth.Claims{Groups: []string{"alpha"}}},
			authz:      "Bearer access-tok",
			userinfo:   &fakeUserInfo{claims: &auth.Claims{Groups: []string{"bravo"}}},
			wantCode:   http.StatusOK,
			wantScope:  "alpha",
			wantUICall: false,
		},
		{
			name:       "no id_token and userinfo rejects the access token → deny",
			verifier:   fakeVerifier{},
			authz:      "Bearer bad-tok",
			userinfo:   &fakeUserInfo{err: errors.New("401 from userinfo")},
			wantCode:   http.StatusUnauthorized,
			wantUICall: true,
		},
		{
			name:       "userinfo resolves but caller has no tenant → forbidden",
			verifier:   fakeVerifier{},
			authz:      "Bearer access-tok",
			userinfo:   &fakeUserInfo{claims: &auth.Claims{Groups: []string{"gamma"}}},
			wantCode:   http.StatusForbidden,
			wantUICall: true,
		},
		{
			name:       "non-bearer Authorization is ignored → deny, userinfo untouched",
			verifier:   fakeVerifier{},
			authz:      "Basic dXNlcjpwYXNz",
			userinfo:   &fakeUserInfo{claims: &auth.Claims{Groups: []string{"alpha"}}},
			wantCode:   http.StatusUnauthorized,
			wantUICall: false,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			up := &recordingUpstream{}
			h := newHandlerUI(t, tc.verifier, tc.userinfo, up)
			req := httptest.NewRequest(http.MethodGet, "/api/v1/query?query=up", nil)
			if tc.idToken != "" {
				req.Header.Set(IDTokenHeader, tc.idToken)
			}
			if tc.authz != "" {
				req.Header.Set(AuthzHeader, tc.authz)
			}
			rr := httptest.NewRecorder()
			h.ServeHTTP(rr, req)

			if rr.Code != tc.wantCode {
				t.Fatalf("status = %d; want %d", rr.Code, tc.wantCode)
			}
			if tc.wantScope != "" {
				if !up.called {
					t.Fatal("upstream not called on an allowed request")
				}
				if up.gotScope != tc.wantScope {
					t.Errorf("scope = %q; want %q", up.gotScope, tc.wantScope)
				}
				if up.gotAuthz != "" {
					t.Errorf("Authorization was forwarded upstream (%q); the access token must be stripped", up.gotAuthz)
				}
			} else if up.called {
				t.Error("upstream was called on a denied request")
			}
			if got := tc.userinfo.callCount > 0; got != tc.wantUICall {
				t.Errorf("userinfo consulted = %v; want %v", got, tc.wantUICall)
			}
			if tc.wantUICall && tc.userinfo.gotToken != "access-tok" && tc.userinfo.gotToken != "bad-tok" {
				t.Errorf("userinfo got token %q; want the extracted bearer token", tc.userinfo.gotToken)
			}
		})
	}
}

// TestServeHTTP_noUserInfoResolver confirms that without a configured resolver the proxy stays
// id_token-only — a valid access token alone does NOT authenticate (the fallback is off).
func TestServeHTTP_noUserInfoResolver(t *testing.T) {
	t.Parallel()
	up := &recordingUpstream{}
	h := newHandler(t, fakeVerifier{}, up) // nil userinfo
	req := httptest.NewRequest(http.MethodGet, "/api/v1/query?query=up", nil)
	req.Header.Set(AuthzHeader, "Bearer access-tok")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Errorf("status = %d; want 401 (fallback disabled)", rr.Code)
	}
	if up.called {
		t.Error("upstream was called with the fallback disabled")
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
