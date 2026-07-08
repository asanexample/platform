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
	// grants maps a grantee group (a team group, e.g. "bravo") → the owner tenants that group may
	// ADDITIONALLY read on top of its own (cross-team read grants, ADR-068 AccessGrant). Only owner
	// tenants that are themselves known tenants are retained — a grant can never widen access to a
	// tenant that does not exist. Derived from admission-validated AccessGrants; empty by default.
	grants map[string][]string
}

// NewResolver builds a Resolver from the known team tenants, the admin group name, and the set of
// cross-team read grants (grantee group → owner tenants it may additionally read; nil for none).
// It errors on an empty tenant set or empty admin group — a misconfigured resolver must fail to
// start rather than silently deny (or worse, silently allow) at runtime.
func NewResolver(tenants []string, adminGroup string, grants map[string][]string) (*Resolver, error) {
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

	// Normalise grants: trim, drop empty grantees, and keep only owner tenants that are KNOWN
	// tenants (a grant must never invent a scope). Deterministic order per grantee.
	normGrants := make(map[string][]string, len(grants))
	for grantee, owners := range grants {
		grantee = strings.TrimSpace(grantee)
		if grantee == "" {
			continue
		}
		seen := make(map[string]struct{}, len(owners))
		kept := make([]string, 0, len(owners))
		for _, o := range owners {
			o = strings.TrimSpace(o)
			if _, known := set[o]; !known {
				continue // can't grant read of a tenant that does not exist
			}
			if _, dup := seen[o]; dup {
				continue
			}
			seen[o] = struct{}{}
			kept = append(kept, o)
		}
		if len(kept) > 0 {
			sort.Strings(kept)
			normGrants[grantee] = kept
		}
	}

	return &Resolver{tenants: set, ordered: ordered, adminGroup: adminGroup, grants: normGrants}, nil
}

// Scope returns the X-Scope-OrgID value the given groups are permitted to read.
//
//   - If the admin group is present → the federated scope over ALL known tenants
//     (Mimir reads `a|b|c` as a multi-tenant query).
//   - Otherwise → the union of (a) the intersection of the user's groups with the known tenants —
//     their OWN tenants — and (b) any owner tenants GRANTED to a group the user holds (cross-team
//     read grants). `|`-joined in a stable order; deterministic regardless of input group order.
//   - If the union is empty → ErrNoTenant (deny). An admin with the admin group set always wins
//     even if they hold no team groups.
//
// The returned scope is always non-empty on a nil error.
func (r *Resolver) Scope(groups []string) (string, error) {
	isAdmin := false
	matched := make(map[string]struct{}, len(groups))
	for _, g := range groups {
		if g == r.adminGroup {
			isAdmin = true
			continue
		}
		if _, ok := r.tenants[g]; ok {
			matched[g] = struct{}{} // the user's own team tenant
		}
		// Cross-team grants: any owner tenant this group has been granted read on. Owners were
		// already validated ⊆ known tenants at construction, so this can never widen to a non-tenant.
		for _, owner := range r.grants[g] {
			matched[owner] = struct{}{}
		}
	}

	if isAdmin {
		// Federated read over every tenant. Uses the stable, pre-sorted order.
		return strings.Join(r.ordered, "|"), nil
	}
	if len(matched) == 0 {
		return "", ErrNoTenant
	}
	out := make([]string, 0, len(matched))
	for t := range matched {
		out = append(out, t)
	}
	sort.Strings(out)
	return strings.Join(out, "|"), nil
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
