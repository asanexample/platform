package access

import (
	"os"
	"path/filepath"
	"testing"
)

// writeFixtures builds a throwaway repo root with gitops/people + gitops/roles.
func writeFixtures(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	mk := func(rel, body string) {
		p := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	mk("gitops/roles/developer.yaml", `apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: developer }
spec: { reach: team, power: change, mode: standing, riskTier: standard }
`)
	mk("gitops/roles/platform-operator.yaml", `apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: platform-operator }
spec: { reach: platform, power: operate, mode: on-demand, riskTier: elevated }
`)
	mk("gitops/roles/access-admin.yaml", `apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: access-admin }
spec: { reach: platform, power: manage-access, mode: standing, riskTier: apex }
`)
	mk("gitops/roles/README.md", "not a role")

	// dev-a: a standing team grant + an on-demand platform-operator (role-mode on-demand).
	mk("gitops/people/dev-a.yaml", `apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: dev-a }
spec:
  person: anchor-a
  handles: { github: deva }
  grants:
    - { role: developer, team: alpha }
    - { role: platform-operator, scope: platform }
`)
	// owner: standing access-admin + an explicitly on-demand break-glass-style grant
	// (activation overrides a standing role's mode).
	mk("gitops/people/owner.yaml", `apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: owner }
spec:
  person: admin
  grants:
    - { role: access-admin, scope: platform }
    - { role: access-admin, scope: platform, activation: on-demand }
`)
	mk("gitops/people/README.md", "not a person")
	return root
}

func TestLoadAndResolve(t *testing.T) {
	root := writeFixtures(t)

	people, err := LoadPeople(root)
	if err != nil {
		t.Fatalf("LoadPeople: %v", err)
	}
	if len(people) != 2 {
		t.Fatalf("want 2 people (README skipped), got %d", len(people))
	}

	roles, err := LoadRoles(root)
	if err != nil {
		t.Fatalf("LoadRoles: %v", err)
	}
	if len(roles) != 3 {
		t.Fatalf("want 3 roles (README skipped), got %d", len(roles))
	}

	// All grants.
	all := Resolve(people, roles, false)
	if len(all) != 4 {
		t.Fatalf("want 4 grant entries, got %d", len(all))
	}

	// Borrowable only: platform-operator (role mode on-demand) + the activation:on-demand access-admin.
	borrow := Resolve(people, roles, true)
	if len(borrow) != 2 {
		t.Fatalf("want 2 borrowable entries, got %d: %+v", len(borrow), borrow)
	}
	for _, e := range borrow {
		if !e.Borrowable {
			t.Errorf("entry %+v in borrowable set is not Borrowable", e)
		}
	}

	// Spot-check classification: developer is standing; platform-operator is borrowable.
	got := map[string]bool{} // role -> borrowable (for dev-a)
	for _, e := range all {
		if e.Person == "dev-a" {
			got[e.Role] = e.Borrowable
		}
	}
	if got["developer"] {
		t.Error("developer (role mode standing, no activation) should be standing")
	}
	if !got["platform-operator"] {
		t.Error("platform-operator (role mode on-demand) should be borrowable")
	}

	// Reach + risk surfaced correctly.
	for _, e := range all {
		if e.Role == "developer" && e.Reach != "team:alpha" {
			t.Errorf("developer reach = %q, want team:alpha", e.Reach)
		}
		if e.Role == "access-admin" && e.RiskTier != "apex" {
			t.Errorf("access-admin risk = %q, want apex", e.RiskTier)
		}
	}
}

func TestLoadPeopleMissingDir(t *testing.T) {
	if _, err := LoadPeople(t.TempDir()); err == nil {
		t.Error("expected an error when gitops/people is absent")
	}
}

func TestEligible(t *testing.T) {
	root := writeFixtures(t)
	people, _ := LoadPeople(root)
	roles, _ := LoadRoles(root)

	cases := []struct {
		name           string
		who, role      string
		team, scope    string
		wantAllowed    bool
		reasonContains string
	}{
		{"borrowable platform-operator", "dev-a", "platform-operator", "", "platform", true, "eligible to borrow"},
		{"by anchor too", "anchor-a", "platform-operator", "", "platform", true, "eligible to borrow"},
		{"owner on-demand access-admin", "owner", "access-admin", "", "platform", true, "eligible to borrow"},
		{"standing developer = no borrow", "dev-a", "developer", "alpha", "", false, "STANDING"},
		{"wrong reach (no grant)", "dev-a", "developer", "", "platform", false, "not eligible"},
		{"unknown principal", "nobody", "developer", "alpha", "", false, "unknown principal"},
		{"role not in catalog", "dev-a", "ghost-role", "alpha", "", false, "not in the catalog"},
		{"no reach", "dev-a", "developer", "", "", false, "exactly one reach"},
		{"both reaches", "dev-a", "developer", "alpha", "platform", false, "exactly one reach"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d := Eligible(people, roles, c.who, c.role, c.team, c.scope)
			if d.Allowed != c.wantAllowed {
				t.Fatalf("Allowed = %v, want %v (reason: %s)", d.Allowed, c.wantAllowed, d.Reason)
			}
			if !contains(d.Reason, c.reasonContains) {
				t.Errorf("reason %q does not contain %q", d.Reason, c.reasonContains)
			}
		})
	}
}

func contains(s, sub string) bool {
	return sub == "" || (len(s) >= len(sub) && indexOf(s, sub) >= 0)
}
func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
