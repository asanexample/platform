// Package access resolves workforce access eligibility from the git-native registries
// (gitops/people × gitops/roles). It is the read + planning side of the ADR-088
// temporary-power model: it answers "who holds what, and what is borrowable (on-demand)
// vs standing", caps a borrow to its role's session-duration, and parses the catalog's
// ISO-8601 durations.
//
// It is the SHARED module both the `platctl access` break-glass CLI and the activation
// operator build on, so the eligibility/cap logic stays in lockstep (one decision, two
// callers — never two copies). Pure (stdlib + yaml); the file-ledger helpers are
// platctl's break-glass record and unused by the operator.
package access

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// Grant is one (role × reach) entry on a Person — reach is exactly one of Team or Scope.
type Grant struct {
	Role       string `yaml:"role"`
	Team       string `yaml:"team"`
	Scope      string `yaml:"scope"`
	Activation string `yaml:"activation"`
}

// Reach renders the target the grant applies to (e.g. "team:alpha" or "platform").
func (g Grant) Reach() string {
	if g.Team != "" {
		return "team:" + g.Team
	}
	if g.Scope != "" {
		return g.Scope
	}
	return "?"
}

// Person is a workforce roster entry (access facts only — no PII).
type Person struct {
	Name   string // metadata.name (the file name)
	Anchor string // spec.person (the Keycloak anchor)
	GitHub string // spec.handles.github (optional)
	Grants []Grant
}

// Role is a WorkforceRole from the catalog (the fields eligibility + activation need).
type Role struct {
	Name     string
	Reach    string // team | platform | any
	Power    string // look | operate | change | manage-access
	Mode     string // standing | on-demand
	RiskTier string // standard | elevated | apex
	// AWS Identity Center projection — the activation target for the AWS plane (ADR-088).
	PermissionSet   string // identityCenter.permissionSet, e.g. "AdministratorAccess" (empty = no AWS console projection)
	SessionDuration string // identityCenter.sessionDuration, ISO-8601 e.g. "PT1H" — the per-role TTL cap
}

// Borrowable reports whether a grant is temporary-power (on-demand), not standing: the
// grant explicitly sets activation: on-demand, OR the role's catalog mode is on-demand.
func (g Grant) Borrowable(roles map[string]Role) bool {
	if g.Activation == "on-demand" {
		return true
	}
	if r, ok := roles[g.Role]; ok && r.Mode == "on-demand" {
		return true
	}
	return false
}

type personDoc struct {
	Kind     string `yaml:"kind"`
	Metadata struct {
		Name string `yaml:"name"`
	} `yaml:"metadata"`
	Spec struct {
		Person  string `yaml:"person"`
		Handles struct {
			GitHub string `yaml:"github"`
		} `yaml:"handles"`
		Grants []Grant `yaml:"grants"`
	} `yaml:"spec"`
}

type roleDoc struct {
	Kind     string `yaml:"kind"`
	Metadata struct {
		Name string `yaml:"name"`
	} `yaml:"metadata"`
	Spec struct {
		Reach          string `yaml:"reach"`
		Power          string `yaml:"power"`
		Mode           string `yaml:"mode"`
		RiskTier       string `yaml:"riskTier"`
		IdentityCenter struct {
			PermissionSet   string `yaml:"permissionSet"`
			SessionDuration string `yaml:"sessionDuration"`
		} `yaml:"identityCenter"`
	} `yaml:"spec"`
}

// yamlFiles lists *.yaml / *.yml under dir, skipping README.* (the human docs).
func yamlFiles(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		n := e.Name()
		if strings.HasPrefix(strings.ToLower(n), "readme") {
			continue
		}
		if strings.HasSuffix(n, ".yaml") || strings.HasSuffix(n, ".yml") {
			out = append(out, filepath.Join(dir, n))
		}
	}
	sort.Strings(out)
	return out, nil
}

// LoadPeople reads the gitops/people registry under repoRoot.
func LoadPeople(repoRoot string) ([]Person, error) {
	dir := filepath.Join(repoRoot, "gitops", "people")
	files, err := yamlFiles(dir)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", dir, err)
	}
	var people []Person
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			return nil, fmt.Errorf("reading %s: %w", f, err)
		}
		var doc personDoc
		if err := yaml.Unmarshal(b, &doc); err != nil {
			return nil, fmt.Errorf("parsing %s: %w", f, err)
		}
		if doc.Kind != "Person" {
			continue
		}
		people = append(people, Person{
			Name:   doc.Metadata.Name,
			Anchor: doc.Spec.Person,
			GitHub: doc.Spec.Handles.GitHub,
			Grants: doc.Spec.Grants,
		})
	}
	return people, nil
}

// LoadRoles reads the gitops/roles catalog under repoRoot, keyed by role name.
func LoadRoles(repoRoot string) (map[string]Role, error) {
	dir := filepath.Join(repoRoot, "gitops", "roles")
	files, err := yamlFiles(dir)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", dir, err)
	}
	roles := make(map[string]Role)
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			return nil, fmt.Errorf("reading %s: %w", f, err)
		}
		var doc roleDoc
		if err := yaml.Unmarshal(b, &doc); err != nil {
			return nil, fmt.Errorf("parsing %s: %w", f, err)
		}
		if doc.Kind != "WorkforceRole" {
			continue
		}
		roles[doc.Metadata.Name] = Role{
			Name:            doc.Metadata.Name,
			Reach:           doc.Spec.Reach,
			Power:           doc.Spec.Power,
			Mode:            doc.Spec.Mode,
			RiskTier:        doc.Spec.RiskTier,
			PermissionSet:   doc.Spec.IdentityCenter.PermissionSet,
			SessionDuration: doc.Spec.IdentityCenter.SessionDuration,
		}
	}
	return roles, nil
}

// Entry is a flattened (person, grant) row with its resolved role, for reporting.
type Entry struct {
	Person     string
	Anchor     string
	Role       string
	Reach      string
	Borrowable bool
	RiskTier   string
}

// Resolve flattens the roster into per-grant entries, resolving each grant against the
// catalog. With borrowableOnly, it returns only the on-demand (temporary-power) grants —
// i.e. exactly what is eligible to be activated.
func Resolve(people []Person, roles map[string]Role, borrowableOnly bool) []Entry {
	var out []Entry
	for _, p := range people {
		for _, g := range p.Grants {
			b := g.Borrowable(roles)
			if borrowableOnly && !b {
				continue
			}
			risk := ""
			if r, ok := roles[g.Role]; ok {
				risk = r.RiskTier
			}
			out = append(out, Entry{
				Person:     p.Name,
				Anchor:     p.Anchor,
				Role:       g.Role,
				Reach:      g.Reach(),
				Borrowable: b,
				RiskTier:   risk,
			})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Person != out[j].Person {
			return out[i].Person < out[j].Person
		}
		return out[i].Role < out[j].Role
	})
	return out
}

// Decision is the result of an eligibility check — the authorization the activation
// controller makes before minting temporary access.
type Decision struct {
	Allowed bool
	Reason  string
}

// find returns the person matching name-or-anchor (and whether found).
func find(people []Person, who string) (Person, bool) {
	for _, p := range people {
		if p.Name == who || p.Anchor == who {
			return p, true
		}
	}
	return Person{}, false
}

// Eligible decides whether `who` (a Person name or Keycloak anchor) may BORROW `role` at
// the given reach (exactly one of team / scope). Allowed only when a matching grant exists
// AND it is borrowable (on-demand). A matching standing grant is reported as already-held
// (no borrow needed); a missing grant, unknown principal, or unknown role is denied.
func Eligible(people []Person, roles map[string]Role, who, role, team, scope string) Decision {
	if (team == "") == (scope == "") {
		return Decision{false, "specify exactly one reach: --team <team> or --scope <scope>"}
	}
	reach := team
	if scope != "" {
		reach = scope
	}
	p, ok := find(people, who)
	if !ok {
		return Decision{false, fmt.Sprintf("unknown principal %q (not in gitops/people)", who)}
	}
	if _, ok := roles[role]; !ok {
		return Decision{false, fmt.Sprintf("role %q is not in the catalog (gitops/roles)", role)}
	}

	standing := false
	for _, g := range p.Grants {
		if g.Role != role {
			continue
		}
		if (team != "" && g.Team == team) || (scope != "" && g.Scope == scope) {
			if g.Borrowable(roles) {
				r := roles[role]
				return Decision{true, fmt.Sprintf("%s is eligible to borrow %s on %s (%s, %s)", p.Name, role, reach, r.Mode, r.RiskTier)}
			}
			standing = true
		}
	}
	if standing {
		return Decision{false, fmt.Sprintf("%s already holds %s on %s as STANDING access — no borrow needed", p.Name, role, reach)}
	}
	return Decision{false, fmt.Sprintf("%s has no %s grant on %s — not eligible", p.Name, role, reach)}
}
