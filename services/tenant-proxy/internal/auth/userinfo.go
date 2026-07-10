// userinfo.go adds a second identity source: the access token Grafana forwards in the Authorization
// header (its primary, reliable oauthPassThru header), resolved to groups via the OIDC provider's
// /userinfo endpoint. This is the robustness fallback for the fragile X-Id-Token path — Grafana 13's
// oauthPassThru intermittently drops the id_token (grafana/grafana#65380/#58598 and observed after a
// park), but keeps forwarding the access token. /userinfo is authoritative: the provider validates the
// bearer token (401 on expired/invalid) and returns the caller's claims, so we don't re-verify the
// signature ourselves — a non-2xx is a hard deny.
//
// Requires the provider's group mapper to include groups in the userinfo response (Keycloak: the
// grafana client's "groups" mapper must have "Add to userinfo" enabled — the same groups the id_token
// carries).
package auth

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

// UserInfoResolver resolves verified Claims from a raw OAuth access token. Fail-closed: any error
// (network, non-2xx, malformed body) returns a non-nil error and no claims.
type UserInfoResolver interface {
	Resolve(ctx context.Context, accessToken string) (*Claims, error)
}

// UserInfoConfig configures the /userinfo-backed resolver.
type UserInfoConfig struct {
	// URL is the provider's userinfo endpoint (…/protocol/openid-connect/userinfo).
	URL string
	// HTTPClient is used for the userinfo call; nil → a client with a 5s timeout.
	HTTPClient *http.Client
	// CacheTTL bounds how long a resolved result is reused for the same access token. Keep short so a
	// revoked token stops working quickly; 0 → 30s.
	CacheTTL time.Duration
	// now is injected in tests; nil → time.Now.
	now func() time.Time
}

type keycloakUserInfo struct {
	url    string
	client *http.Client
	ttl    time.Duration
	now    func() time.Time

	mu    sync.Mutex
	cache map[string]cacheEntry // key: sha256(token); value: claims + expiry
}

type cacheEntry struct {
	claims  *Claims
	expires time.Time
}

// NewUserInfoResolver builds a /userinfo-backed resolver. It caches successful lookups (keyed by a
// SHA-256 of the token, never the raw token) for CacheTTL to avoid a provider round-trip on every
// dashboard refresh. Errors are never cached.
func NewUserInfoResolver(cfg UserInfoConfig) (UserInfoResolver, error) {
	if cfg.URL == "" {
		return nil, errors.New("auth: userinfo URL must not be empty")
	}
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	ttl := cfg.CacheTTL
	if ttl <= 0 {
		ttl = 30 * time.Second
	}
	nowFn := cfg.now
	if nowFn == nil {
		nowFn = time.Now
	}
	return &keycloakUserInfo{
		url:    cfg.URL,
		client: client,
		ttl:    ttl,
		now:    nowFn,
		cache:  make(map[string]cacheEntry),
	}, nil
}

func (k *keycloakUserInfo) Resolve(ctx context.Context, accessToken string) (*Claims, error) {
	if accessToken == "" {
		return nil, errors.New("auth: empty access token")
	}
	key := tokenKey(accessToken)
	if c := k.cached(key); c != nil {
		return c, nil
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, k.url, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: building userinfo request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")

	resp, err := k.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: userinfo request: %w", err)
	}
	defer resp.Body.Close()

	// Read a bounded body — a compromised/misbehaving endpoint must not exhaust memory.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("auth: reading userinfo body: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		// The provider rejected the token (401 for expired/invalid) or errored — fail closed.
		return nil, fmt.Errorf("auth: userinfo returned status %d", resp.StatusCode)
	}

	var raw struct {
		Subject string   `json:"sub"`
		Groups  []string `json:"groups"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, fmt.Errorf("auth: decoding userinfo: %w", err)
	}
	if raw.Subject == "" {
		return nil, errors.New("auth: userinfo response missing sub")
	}
	claims := &Claims{Subject: raw.Subject, Groups: raw.Groups}
	k.store(key, claims)
	return claims, nil
}

func (k *keycloakUserInfo) cached(key string) *Claims {
	k.mu.Lock()
	defer k.mu.Unlock()
	e, ok := k.cache[key]
	if !ok || !k.now().Before(e.expires) {
		if ok {
			delete(k.cache, key) // opportunistic eviction of the expired entry
		}
		return nil
	}
	return e.claims
}

func (k *keycloakUserInfo) store(key string, claims *Claims) {
	k.mu.Lock()
	defer k.mu.Unlock()
	k.cache[key] = cacheEntry{claims: claims, expires: k.now().Add(k.ttl)}
}

// tokenKey hashes the token so raw bearer tokens are never used as map keys / retained in memory.
func tokenKey(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
