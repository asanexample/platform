package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/golang-jwt/jwt/v5"
)

const (
	testIssuer   = "https://keycloak.example.test/realms/platform"
	testAudience = "grafana"
	testKID      = "test-key-1"
)

func TestConfig_validate(t *testing.T) {
	t.Parallel()
	bad := []Config{
		{JWKSURL: "", Issuer: "i", Audience: "a"},
		{JWKSURL: "u", Issuer: "", Audience: "a"},
		{JWKSURL: "u", Issuer: "i", Audience: ""},
	}
	for _, c := range bad {
		if err := c.validate(); err == nil {
			t.Errorf("validate(%+v) = nil; want error", c)
		}
	}
}

// TestVerify covers the real go-oidc verification path against an in-memory JWKS. The failure
// cases (expired / wrong iss / wrong aud / bad signature) are the point: a read-authorization
// front door must reject them, not merely "usually" accept good ones.
func TestVerify(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	tests := []struct {
		name    string
		token   string
		wantErr bool
		groups  []string
	}{
		{
			name:   "valid token yields groups",
			token:  h.sign(t, jwt.MapClaims{"iss": testIssuer, "aud": testAudience, "exp": future(), "sub": "u1", "groups": []string{"alpha", "platform"}}),
			groups: []string{"alpha", "platform"},
		},
		{
			name:  "valid token with no groups claim",
			token: h.sign(t, jwt.MapClaims{"iss": testIssuer, "aud": testAudience, "exp": future(), "sub": "u2"}),
		},
		{
			name:    "expired token rejected",
			token:   h.sign(t, jwt.MapClaims{"iss": testIssuer, "aud": testAudience, "exp": past()}),
			wantErr: true,
		},
		{
			name:    "wrong issuer rejected",
			token:   h.sign(t, jwt.MapClaims{"iss": "https://evil.test/realms/platform", "aud": testAudience, "exp": future()}),
			wantErr: true,
		},
		{
			name:    "wrong audience rejected",
			token:   h.sign(t, jwt.MapClaims{"iss": testIssuer, "aud": "prometheus", "exp": future()}),
			wantErr: true,
		},
		{
			name:    "token signed by a different key rejected",
			token:   h.signWithForeignKey(t, jwt.MapClaims{"iss": testIssuer, "aud": testAudience, "exp": future()}),
			wantErr: true,
		},
		{
			name:    "empty token rejected",
			token:   "",
			wantErr: true,
		},
		{
			name:    "garbage token rejected",
			token:   "not.a.jwt",
			wantErr: true,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			claims, err := h.verifier.Verify(context.Background(), tc.token)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("Verify(%s) = %+v, nil; want error", tc.name, claims)
				}
				if claims != nil {
					t.Fatalf("Verify returned claims %+v on error (must be nil — fail closed)", claims)
				}
				return
			}
			if err != nil {
				t.Fatalf("Verify(%s) unexpected error: %v", tc.name, err)
			}
			if !equalStrings(claims.Groups, tc.groups) {
				t.Errorf("groups = %v; want %v", claims.Groups, tc.groups)
			}
		})
	}
}

// harness serves a JWKS for one RSA key and signs tokens with it.
type harness struct {
	key      *rsa.PrivateKey
	foreign  *rsa.PrivateKey
	verifier Verifier
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	foreign, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate foreign key: %v", err)
	}

	jwks := jwksJSON(t, key, testKID)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(jwks)
	}))
	t.Cleanup(srv.Close)

	keySet := oidc.NewRemoteKeySet(context.Background(), srv.URL)
	v := newFromKeySet(keySet, Config{JWKSURL: srv.URL, Issuer: testIssuer, Audience: testAudience})
	return &harness{key: key, foreign: foreign, verifier: v}
}

func (h *harness) sign(t *testing.T, claims jwt.MapClaims) string {
	return signRS256(t, h.key, testKID, claims)
}

func (h *harness) signWithForeignKey(t *testing.T, claims jwt.MapClaims) string {
	// Signed with a key whose public half is NOT in the served JWKS, but tagged with the served kid
	// so the verifier selects the (wrong) real key and the signature check fails.
	return signRS256(t, h.foreign, testKID, claims)
}

func signRS256(t *testing.T, key *rsa.PrivateKey, kid string, claims jwt.MapClaims) string {
	t.Helper()
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tok.Header["kid"] = kid
	s, err := tok.SignedString(key)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return s
}

func jwksJSON(t *testing.T, key *rsa.PrivateKey, kid string) []byte {
	t.Helper()
	pub := key.Public().(*rsa.PublicKey)
	n := base64.RawURLEncoding.EncodeToString(pub.N.Bytes())
	e := base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes())
	doc := map[string]any{
		"keys": []map[string]any{{
			"kty": "RSA", "use": "sig", "alg": "RS256", "kid": kid, "n": n, "e": e,
		}},
	}
	b, err := json.Marshal(doc)
	if err != nil {
		t.Fatalf("marshal jwks: %v", err)
	}
	return b
}

func future() int64 { return time.Now().Add(time.Hour).Unix() }
func past() int64   { return time.Now().Add(-time.Hour).Unix() }

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
