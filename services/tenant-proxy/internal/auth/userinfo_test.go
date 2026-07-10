package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// newUserInfoServer returns a test userinfo endpoint that asserts the bearer token and replies with
// the given status/body. It counts requests so caching can be verified.
func newUserInfoServer(t *testing.T, status int, body string, hits *int32) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(hits, 1)
		if got := r.Header.Get("Authorization"); got == "" {
			t.Errorf("userinfo request missing Authorization header")
		}
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
}

func mustResolver(t *testing.T, cfg UserInfoConfig) UserInfoResolver {
	t.Helper()
	r, err := NewUserInfoResolver(cfg)
	if err != nil {
		t.Fatalf("NewUserInfoResolver: %v", err)
	}
	return r
}

func TestUserInfo_Resolve_success(t *testing.T) {
	t.Parallel()
	var hits int32
	srv := newUserInfoServer(t, http.StatusOK, `{"sub":"user-1","groups":["alpha","bravo"]}`, &hits)
	defer srv.Close()

	r := mustResolver(t, UserInfoConfig{URL: srv.URL})
	claims, err := r.Resolve(context.Background(), "tok")
	if err != nil {
		t.Fatalf("Resolve: %v", err)
	}
	if claims.Subject != "user-1" {
		t.Errorf("subject = %q; want user-1", claims.Subject)
	}
	if len(claims.Groups) != 2 || claims.Groups[0] != "alpha" || claims.Groups[1] != "bravo" {
		t.Errorf("groups = %v; want [alpha bravo]", claims.Groups)
	}
}

func TestUserInfo_Resolve_failClosed(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		status int
		body   string
	}{
		{"401 rejects the token", http.StatusUnauthorized, `{"error":"invalid_token"}`},
		{"403 forbidden", http.StatusForbidden, ``},
		{"500 server error", http.StatusInternalServerError, `oops`},
		{"200 but malformed json", http.StatusOK, `{not-json`},
		{"200 but missing sub", http.StatusOK, `{"groups":["alpha"]}`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var hits int32
			srv := newUserInfoServer(t, tc.status, tc.body, &hits)
			defer srv.Close()
			r := mustResolver(t, UserInfoConfig{URL: srv.URL})

			claims, err := r.Resolve(context.Background(), "tok")
			if err == nil {
				t.Fatal("want error (fail closed), got nil")
			}
			if claims != nil {
				t.Errorf("want nil claims on error, got %+v", claims)
			}
		})
	}
}

func TestUserInfo_Resolve_emptyToken(t *testing.T) {
	t.Parallel()
	var hits int32
	srv := newUserInfoServer(t, http.StatusOK, `{"sub":"u"}`, &hits)
	defer srv.Close()
	r := mustResolver(t, UserInfoConfig{URL: srv.URL})

	if _, err := r.Resolve(context.Background(), ""); err == nil {
		t.Fatal("want error for empty token")
	}
	if hits != 0 {
		t.Errorf("empty token should not reach the server; hits = %d", hits)
	}
}

func TestUserInfo_Resolve_caches(t *testing.T) {
	t.Parallel()
	var hits int32
	srv := newUserInfoServer(t, http.StatusOK, `{"sub":"u","groups":["alpha"]}`, &hits)
	defer srv.Close()
	r := mustResolver(t, UserInfoConfig{URL: srv.URL, CacheTTL: time.Minute})

	for i := range 3 {
		if _, err := r.Resolve(context.Background(), "same-tok"); err != nil {
			t.Fatalf("Resolve %d: %v", i, err)
		}
	}
	if hits != 1 {
		t.Errorf("server hit %d times; want 1 (cached)", hits)
	}
	// A different token is a cache miss.
	if _, err := r.Resolve(context.Background(), "other-tok"); err != nil {
		t.Fatalf("Resolve other: %v", err)
	}
	if hits != 2 {
		t.Errorf("server hit %d times; want 2 (distinct token)", hits)
	}
}

func TestUserInfo_Resolve_cacheExpires(t *testing.T) {
	t.Parallel()
	var hits int32
	srv := newUserInfoServer(t, http.StatusOK, `{"sub":"u"}`, &hits)
	defer srv.Close()

	// Inject a controllable clock so expiry is deterministic (no sleeps).
	now := time.Unix(1_700_000_000, 0)
	clock := &now
	r := mustResolver(t, UserInfoConfig{
		URL:      srv.URL,
		CacheTTL: 30 * time.Second,
		now:      func() time.Time { return *clock },
	})

	if _, err := r.Resolve(context.Background(), "tok"); err != nil {
		t.Fatalf("Resolve: %v", err)
	}
	// Within TTL → cache hit.
	*clock = now.Add(29 * time.Second)
	if _, err := r.Resolve(context.Background(), "tok"); err != nil {
		t.Fatalf("Resolve within ttl: %v", err)
	}
	if hits != 1 {
		t.Fatalf("hits = %d; want 1 within ttl", hits)
	}
	// Past TTL → re-fetch.
	*clock = now.Add(31 * time.Second)
	if _, err := r.Resolve(context.Background(), "tok"); err != nil {
		t.Fatalf("Resolve after ttl: %v", err)
	}
	if hits != 2 {
		t.Errorf("hits = %d; want 2 after expiry", hits)
	}
}

func TestUserInfo_Resolve_errorsNotCached(t *testing.T) {
	t.Parallel()
	// First response is a 500, subsequent are 200 — an error must not be cached, so the second call
	// re-fetches and succeeds.
	var hits int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if atomic.AddInt32(&hits, 1) == 1 {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"sub":"u","groups":["alpha"]}`))
	}))
	defer srv.Close()
	r := mustResolver(t, UserInfoConfig{URL: srv.URL, CacheTTL: time.Minute})

	if _, err := r.Resolve(context.Background(), "tok"); err == nil {
		t.Fatal("want error on first (500) call")
	}
	claims, err := r.Resolve(context.Background(), "tok")
	if err != nil {
		t.Fatalf("second call should re-fetch and succeed: %v", err)
	}
	if claims.Subject != "u" {
		t.Errorf("subject = %q; want u", claims.Subject)
	}
}

func TestNewUserInfoResolver_requiresURL(t *testing.T) {
	t.Parallel()
	if _, err := NewUserInfoResolver(UserInfoConfig{}); err == nil {
		t.Fatal("want error for empty URL")
	}
}

func TestUserInfo_Resolve_contextCancelled(t *testing.T) {
	t.Parallel()
	var hits int32
	srv := newUserInfoServer(t, http.StatusOK, `{"sub":"u"}`, &hits)
	defer srv.Close()
	r := mustResolver(t, UserInfoConfig{URL: srv.URL})

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := r.Resolve(ctx, "tok"); err == nil {
		t.Fatal("want error for a cancelled context")
	}
}
