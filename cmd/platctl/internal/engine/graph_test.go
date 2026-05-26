package engine

import (
	"testing"
)

func TestNewGraph_DuplicateUnit(t *testing.T) {
	units := []*Unit{
		{Name: "platform/eks", Env: "platform"},
		{Name: "platform/eks", Env: "platform"},
	}
	_, err := NewGraph(units)
	if err == nil {
		t.Fatal("expected error for duplicate unit")
	}
}

func TestNewGraph_MissingDependency(t *testing.T) {
	units := []*Unit{
		{Name: "platform/cilium", Env: "platform", DependsOn: []string{"platform/eks"}},
	}
	_, err := NewGraph(units)
	if err == nil {
		t.Fatal("expected error for missing dependency")
	}
}

func TestNewGraph_Valid(t *testing.T) {
	units := []*Unit{
		{Name: "platform/eks", Env: "platform"},
		{Name: "platform/cilium", Env: "platform", DependsOn: []string{"platform/eks"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if g.Len() != 2 {
		t.Fatalf("expected 2 units, got %d", g.Len())
	}
}

func TestTopoSort_LinearChain(t *testing.T) {
	units := []*Unit{
		{Name: "platform/networking", Env: "platform"},
		{Name: "platform/eks", Env: "platform", DependsOn: []string{"platform/networking"}},
		{Name: "platform/cilium", Env: "platform", DependsOn: []string{"platform/eks"}},
		{Name: "platform/node-groups", Env: "platform", DependsOn: []string{"platform/cilium"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	order, err := g.TopoSort()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	assertOrder(t, order, "platform/networking", "platform/eks")
	assertOrder(t, order, "platform/eks", "platform/cilium")
	assertOrder(t, order, "platform/cilium", "platform/node-groups")
}

func TestTopoSort_CycleDetected(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", DependsOn: []string{"b"}},
		{Name: "b", Env: "test", DependsOn: []string{"c"}},
		{Name: "c", Env: "test", DependsOn: []string{"a"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_, err = g.TopoSort()
	if err == nil {
		t.Fatal("expected cycle error")
	}
}

func TestTopoSort_DiamondDependency(t *testing.T) {
	// A → B, A → C, B → D, C → D
	units := []*Unit{
		{Name: "d", Env: "test"},
		{Name: "b", Env: "test", DependsOn: []string{"d"}},
		{Name: "c", Env: "test", DependsOn: []string{"d"}},
		{Name: "a", Env: "test", DependsOn: []string{"b", "c"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	order, err := g.TopoSort()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	assertOrder(t, order, "d", "b")
	assertOrder(t, order, "d", "c")
	assertOrder(t, order, "b", "a")
	assertOrder(t, order, "c", "a")
}

func TestTopoSort_CrossEnvDependencies(t *testing.T) {
	units := []*Unit{
		{Name: "preprod/iam-roles", Env: "preprod"},
		{Name: "preprod/networking", Env: "preprod"},
		{Name: "preprod/eks", Env: "preprod", DependsOn: []string{"preprod/networking", "preprod/iam-roles"}},
		{Name: "platform/networking", Env: "platform"},
		{Name: "platform/cross-vpc-dns", Env: "platform", DependsOn: []string{"platform/networking", "preprod/eks"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	order, err := g.TopoSort()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// preprod/eks must be before platform/cross-vpc-dns (cross-env dep)
	assertOrder(t, order, "preprod/eks", "platform/cross-vpc-dns")
	// platform/networking must be before platform/cross-vpc-dns
	assertOrder(t, order, "platform/networking", "platform/cross-vpc-dns")
}

func TestTopoSort_Deterministic(t *testing.T) {
	units := []*Unit{
		{Name: "c", Env: "test"},
		{Name: "a", Env: "test"},
		{Name: "b", Env: "test"},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Run multiple times to verify determinism
	first, _ := g.TopoSort()
	for i := 0; i < 10; i++ {
		order, _ := g.TopoSort()
		for j, u := range order {
			if u.Name != first[j].Name {
				t.Fatalf("non-deterministic order on iteration %d: got %s at position %d, expected %s",
					i, u.Name, j, first[j].Name)
			}
		}
	}
}

func TestWaves_ParallelBatching(t *testing.T) {
	units := []*Unit{
		{Name: "platform/iam-roles", Env: "platform"},
		{Name: "platform/networking", Env: "platform"},
		{Name: "platform/route53", Env: "platform"},
		{Name: "platform/eks", Env: "platform", DependsOn: []string{"platform/iam-roles", "platform/networking"}},
		{Name: "platform/cilium", Env: "platform", DependsOn: []string{"platform/eks"}},
		{Name: "platform/cert-manager", Env: "platform", DependsOn: []string{"platform/eks", "platform/route53"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	waves, err := g.Waves()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Wave 0: iam-roles, networking, route53 (no deps)
	assertWaveContains(t, waves[0], "platform/iam-roles", "platform/networking", "platform/route53")

	// Wave 1: eks (depends on wave 0 units)
	assertWaveContains(t, waves[1], "platform/eks")

	// Wave 2: cilium and cert-manager (both depend only on wave 0+1 units)
	assertWaveContains(t, waves[2], "platform/cilium", "platform/cert-manager")
}

func TestWaves_CycleDetected(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", DependsOn: []string{"b"}},
		{Name: "b", Env: "test", DependsOn: []string{"a"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_, err = g.Waves()
	if err == nil {
		t.Fatal("expected cycle error")
	}
}

func TestFilterByEnv(t *testing.T) {
	units := []*Unit{
		{Name: "platform/networking", Env: "platform"},
		{Name: "platform/eks", Env: "platform", DependsOn: []string{"platform/networking"}},
		{Name: "platform/cross-vpc-dns", Env: "platform", DependsOn: []string{"platform/networking", "preprod/eks"}},
		{Name: "preprod/networking", Env: "preprod"},
		{Name: "preprod/eks", Env: "preprod", DependsOn: []string{"preprod/networking"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	filtered, err := g.FilterByEnv("platform")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if filtered.Len() != 3 {
		t.Fatalf("expected 3 units, got %d", filtered.Len())
	}

	// cross-vpc-dns should have its preprod/eks dep removed
	dns := filtered.Unit("platform/cross-vpc-dns")
	if dns == nil {
		t.Fatal("expected platform/cross-vpc-dns in filtered graph")
	}
	if len(dns.DependsOn) != 1 || dns.DependsOn[0] != "platform/networking" {
		t.Fatalf("expected cross-vpc-dns deps to be [platform/networking], got %v", dns.DependsOn)
	}
}

func TestReverse(t *testing.T) {
	units := []*Unit{
		{Name: "platform/networking", Env: "platform"},
		{Name: "platform/eks", Env: "platform", DependsOn: []string{"platform/networking"}},
		{Name: "platform/cilium", Env: "platform", DependsOn: []string{"platform/eks"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	rev, err := g.Reverse()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// In reverse: networking depends on eks, eks depends on cilium
	order, err := rev.TopoSort()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	assertOrder(t, order, "platform/cilium", "platform/eks")
	assertOrder(t, order, "platform/eks", "platform/networking")
}

func TestDependents(t *testing.T) {
	units := []*Unit{
		{Name: "platform/networking", Env: "platform"},
		{Name: "platform/eks", Env: "platform", DependsOn: []string{"platform/networking"}},
		{Name: "platform/cilium", Env: "platform", DependsOn: []string{"platform/eks"}},
		{Name: "platform/node-groups", Env: "platform", DependsOn: []string{"platform/eks", "platform/cilium"}},
		{Name: "platform/route53", Env: "platform"},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	deps := g.Dependents("platform/eks")
	expected := []string{"platform/cilium", "platform/node-groups"}
	if len(deps) != len(expected) {
		t.Fatalf("expected %v, got %v", expected, deps)
	}
	for i, name := range expected {
		if deps[i] != name {
			t.Fatalf("expected %s at position %d, got %s", name, i, deps[i])
		}
	}

	// route53 has no dependents
	deps = g.Dependents("platform/route53")
	if len(deps) != 0 {
		t.Fatalf("expected no dependents for route53, got %v", deps)
	}
}

func TestWaves_FullPlatformGraph(t *testing.T) {
	// Verify the full 33-unit graph produces valid waves with no cycles
	units := buildFullGraph()
	g, err := NewGraph(units)
	if err != nil {
		t.Fatalf("unexpected error building graph: %v", err)
	}

	waves, err := g.Waves()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	total := 0
	for _, w := range waves {
		total += len(w)
	}
	if total != 33 {
		t.Fatalf("expected 33 units across all waves, got %d", total)
	}

	// Verify ordering constraints
	order, _ := g.TopoSort()
	assertOrder(t, order, "platform/eks", "platform/cilium")
	assertOrder(t, order, "platform/cilium", "platform/node-groups")
	assertOrder(t, order, "preprod/eks", "platform/cross-vpc-dns")
	assertOrder(t, order, "preprod/eks", "platform/argocd-clusters")
	assertOrder(t, order, "platform/transit-gateway", "preprod/transit-gateway")
}

// buildFullGraph creates the complete 33-unit graph from the plan.
func buildFullGraph() []*Unit {
	return []*Unit{
		// Platform (21 units)
		{Name: "platform/iam-roles", Env: "platform", Provider: "aws"},
		{Name: "platform/networking", Env: "platform", Provider: "aws"},
		{Name: "platform/route53", Env: "platform", Provider: "aws"},
		{Name: "platform/cloudtrail", Env: "platform", Provider: "aws"},
		{Name: "platform/cloudflare-dns", Env: "platform", Provider: "aws", DependsOn: []string{"platform/route53"}},
		{Name: "platform/eks", Env: "platform", Provider: "aws", DependsOn: []string{"platform/iam-roles", "platform/networking"}},
		{Name: "platform/cilium", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks"}},
		{Name: "platform/node-groups", Env: "platform", Provider: "aws", DependsOn: []string{"platform/networking", "platform/eks", "platform/cilium"}},
		{Name: "platform/eks-addons", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/cilium", "platform/node-groups"}},
		{Name: "platform/ssm-bastion", Env: "platform", Provider: "aws", DependsOn: []string{"platform/networking", "platform/eks"}},
		{Name: "platform/cert-manager", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/node-groups", "platform/route53"}},
		{Name: "platform/external-dns", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/node-groups", "platform/route53"}},
		{Name: "platform/external-secrets", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/node-groups"}},
		{Name: "platform/secret-stores", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/external-secrets", "platform/node-groups"}},
		{Name: "platform/tailscale-admin", Env: "platform", Provider: "aws", DependsOn: []string{"preprod/iam-roles"}},
		{Name: "platform/tailscale", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/node-groups", "platform/external-secrets"}},
		{Name: "platform/transit-gateway", Env: "platform", Provider: "aws", DependsOn: []string{"platform/networking"}},
		{Name: "platform/cross-vpc-dns", Env: "platform", Provider: "aws", DependsOn: []string{"platform/networking", "preprod/eks"}},
		{Name: "platform/argocd", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/node-groups", "preprod/iam-roles"}},
		{Name: "platform/argocd-clusters", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/argocd", "platform/node-groups", "preprod/eks", "preprod/iam-roles"}},
		{Name: "platform/gateway-config", Env: "platform", Provider: "aws", DependsOn: []string{"platform/eks", "platform/cilium", "platform/cert-manager", "platform/external-dns", "platform/argocd", "platform/route53"}},

		// Preprod (12 units)
		{Name: "preprod/iam-roles", Env: "preprod", Provider: "aws"},
		{Name: "preprod/networking", Env: "preprod", Provider: "aws"},
		{Name: "preprod/cloudtrail", Env: "preprod", Provider: "aws"},
		{Name: "preprod/eks", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/networking", "preprod/iam-roles"}},
		{Name: "preprod/cilium", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/eks"}},
		{Name: "preprod/node-groups", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/networking", "preprod/eks", "preprod/cilium"}},
		{Name: "preprod/eks-addons", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/eks", "preprod/cilium", "preprod/node-groups"}},
		{Name: "preprod/ssm-bastion", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/networking", "preprod/eks"}},
		{Name: "preprod/external-secrets", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/eks", "preprod/node-groups"}},
		{Name: "preprod/secret-stores", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/eks", "preprod/external-secrets", "preprod/node-groups"}},
		{Name: "preprod/tailscale", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/eks", "preprod/node-groups", "preprod/external-secrets", "platform/tailscale-admin"}},
		{Name: "preprod/transit-gateway", Env: "preprod", Provider: "aws", DependsOn: []string{"preprod/networking", "preprod/eks", "platform/transit-gateway"}},
	}
}

// assertOrder verifies that unit 'before' appears before 'after' in the ordering.
func assertOrder(t *testing.T, order []*Unit, before, after string) {
	t.Helper()
	beforeIdx, afterIdx := -1, -1
	for i, u := range order {
		if u.Name == before {
			beforeIdx = i
		}
		if u.Name == after {
			afterIdx = i
		}
	}
	if beforeIdx == -1 {
		t.Fatalf("%q not found in order", before)
	}
	if afterIdx == -1 {
		t.Fatalf("%q not found in order", after)
	}
	if beforeIdx >= afterIdx {
		t.Errorf("expected %q (pos %d) before %q (pos %d)", before, beforeIdx, after, afterIdx)
	}
}

// assertWaveContains verifies that all expected units are in the wave.
func assertWaveContains(t *testing.T, wave []*Unit, names ...string) {
	t.Helper()
	have := make(map[string]bool, len(wave))
	for _, u := range wave {
		have[u.Name] = true
	}
	for _, name := range names {
		if !have[name] {
			t.Errorf("expected %q in wave, got %v", name, waveNames(wave))
		}
	}
}

func waveNames(wave []*Unit) []string {
	names := make([]string, len(wave))
	for i, u := range wave {
		names[i] = u.Name
	}
	return names
}
