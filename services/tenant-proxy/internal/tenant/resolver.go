// Package tenant resolves an authenticated user's OIDC group memberships into the set of
// Mimir/Loki/Tempo tenants (the X-Scope-OrgID value) they are permitted to read.
//
// This is the security-critical core of the P13 per-team read isolation (ADR-043/044, #590):
// a user may read ONLY the tenants that correspond to teams they belong to. The mapping is
// deliberately fail-closed — anything not explicitly permitted resolves to an error (deny), never
// to "all" or "empty-means-everything".
package tenant

import (
	"errors"
	"fmt"
	"sort"
	"strings"
)

// ErrNoTenant is returned when an authenticated user maps to zero readable tenants. Callers MUST
// treat this as deny (HTTP 403) — never as "unscoped" (which some stores read as all-tenants).
var ErrNoTenant = errors.New("tenant: user has no readable tenants")

// Resolver maps OIDC groups → the permitted tenant scope. It holds no per-request state and is
// safe for concurrent use.
type Resolver struct {
	// tenants is the set of known team tenants (e.g. alpha, bravo, platform). A user's groups are
	// intersected with this set — a group that is not a known tenant (offline_access, uma_authorization,
	// …) can never widen access.
	tenants map[string]struct{}
	// ordered is `tenants` in a stable, sorted order, used to build deterministic scope strings.
	ordered []string
	// adminGroup, when present in a user's groups, grants the federated all-tenants scope.
	adminGroup string
}

// NewResolver builds a Resolver from the known team tenants and the admin group name.
// It errors on an empty tenant set or empty admin group — a misconfigured resolver must fail to
// start rather than silently deny (or worse, silently allow) at runtime.
func NewResolver(tenants []string, adminGroup string) (*Resolver, error) {
	if adminGroup == "" {
		return nil, errors.New("tenant: admin group must not be empty")
	}
	set := make(map[string]struct{}, len(tenants))
	for _, t := range tenants {
		t = strings.TrimSpace(t)
		if t == "" {
			continue
		}
		set[t] = struct{}{}
	}
	if len(set) == 0 {
		return nil, errors.New("tenant: at least one tenant must be configured")
	}
	ordered := make([]string, 0, len(set))
	for t := range set {
		ordered = append(ordered, t)
	}
	sort.Strings(ordered)
	return &Resolver{tenants: set, ordered: ordered, adminGroup: adminGroup}, nil
}

// Scope returns the X-Scope-OrgID value the given groups are permitted to read.
//
//   - If the admin group is present → the federated scope over ALL known tenants
//     (Mimir reads `a|b|c` as a multi-tenant query).
//   - Otherwise → the intersection of the user's groups with the known tenants, `|`-joined in a
//     stable order. The result is deterministic regardless of input group order.
//   - If the intersection is empty → ErrNoTenant (deny). An admin with the admin group set always
//     wins even if they hold no team groups.
//
// The returned scope is always non-empty on a nil error.
func (r *Resolver) Scope(groups []string) (string, error) {
	isAdmin := false
	matched := make([]string, 0, len(groups))
	seen := make(map[string]struct{}, len(groups))
	for _, g := range groups {
		if g == r.adminGroup {
			isAdmin = true
			continue
		}
		if _, ok := r.tenants[g]; !ok {
			continue // group is not a known tenant — cannot widen access
		}
		if _, dup := seen[g]; dup {
			continue
		}
		seen[g] = struct{}{}
		matched = append(matched, g)
	}

	if isAdmin {
		// Federated read over every tenant. Uses the stable, pre-sorted order.
		return strings.Join(r.ordered, "|"), nil
	}
	if len(matched) == 0 {
		return "", ErrNoTenant
	}
	sort.Strings(matched)
	return strings.Join(matched, "|"), nil
}

// Tenants returns the configured tenants (sorted). Exposed for logging/health only.
func (r *Resolver) Tenants() []string {
	out := make([]string, len(r.ordered))
	copy(out, r.ordered)
	return out
}

// String renders the resolver config for logs (no secrets).
func (r *Resolver) String() string {
	return fmt.Sprintf("tenant.Resolver{tenants=%v, adminGroup=%q}", r.ordered, r.adminGroup)
}
