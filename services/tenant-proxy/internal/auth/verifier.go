// Package auth verifies the Keycloak-issued OIDC token that Grafana forwards to a datasource via
// its oauthPassThru mechanism (the X-Id-Token header — confirmed live in the P13 spike, #590).
//
// Verification is delegated to coreos/go-oidc, which fetches + caches the realm JWKS and checks the
// signature, issuer, audience, and expiry. This package narrows that to the one claim the proxy
// needs (groups) behind a small interface so the request path can be tested without minting real
// tokens, while the real verification path keeps its own end-to-end test.
package auth

import (
	"context"
	"errors"
	"fmt"

	"github.com/coreos/go-oidc/v3/oidc"
)

// Claims is the narrow view of a verified token the proxy acts on.
type Claims struct {
	Subject string
	Groups  []string
}

// Verifier verifies a raw JWT and returns its claims, or an error if the token is missing a valid
// signature / issuer / audience / expiry. Implementations MUST NOT return claims on any verification
// failure — the caller fails closed on a non-nil error.
type Verifier interface {
	Verify(ctx context.Context, rawToken string) (*Claims, error)
}

// oidcVerifier is the production Verifier backed by go-oidc.
type oidcVerifier struct {
	inner *oidc.IDTokenVerifier
}

// Config configures the OIDC verifier.
type Config struct {
	// JWKSURL is the realm's JWKS endpoint (…/protocol/openid-connect/certs).
	JWKSURL string
	// Issuer is the exact `iss` the token must carry (…/realms/<realm>).
	Issuer string
	// Audience is the `aud` the token must contain (the Grafana OIDC client id).
	Audience string
}

func (c Config) validate() error {
	if c.JWKSURL == "" {
		return errors.New("auth: JWKS URL must not be empty")
	}
	if c.Issuer == "" {
		return errors.New("auth: issuer must not be empty")
	}
	if c.Audience == "" {
		return errors.New("auth: audience must not be empty")
	}
	return nil
}

// NewOIDCVerifier builds a Verifier that fetches the JWKS from cfg.JWKSURL (cached + auto-refreshed
// on key rotation by go-oidc's RemoteKeySet) and enforces issuer, audience, expiry, and signature.
func NewOIDCVerifier(ctx context.Context, cfg Config) (Verifier, error) {
	if err := cfg.validate(); err != nil {
		return nil, err
	}
	keySet := oidc.NewRemoteKeySet(ctx, cfg.JWKSURL)
	return newFromKeySet(keySet, cfg), nil
}

// newFromKeySet wires a verifier from an already-constructed key set. Split out so tests can inject
// a key set backed by an in-memory JWKS server.
func newFromKeySet(keySet oidc.KeySet, cfg Config) Verifier {
	inner := oidc.NewVerifier(cfg.Issuer, keySet, &oidc.Config{
		ClientID:             cfg.Audience,
		SupportedSigningAlgs: []string{oidc.RS256},
	})
	return &oidcVerifier{inner: inner}
}

func (v *oidcVerifier) Verify(ctx context.Context, rawToken string) (*Claims, error) {
	if rawToken == "" {
		return nil, errors.New("auth: empty token")
	}
	idToken, err := v.inner.Verify(ctx, rawToken)
	if err != nil {
		return nil, fmt.Errorf("auth: token verification failed: %w", err)
	}
	var raw struct {
		Groups []string `json:"groups"`
	}
	if err := idToken.Claims(&raw); err != nil {
		return nil, fmt.Errorf("auth: reading claims: %w", err)
	}
	return &Claims{Subject: idToken.Subject, Groups: raw.Groups}, nil
}
