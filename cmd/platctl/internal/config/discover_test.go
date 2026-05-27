package config

import (
	"os"
	"path/filepath"
	"sort"
	"testing"
)

func TestDiscover_BasicUnits(t *testing.T) {
	root := t.TempDir()
	setupFixture(t, root, "env-a", "networking", "")
	setupFixture(t, root, "env-a", "eks", `
dependency "networking" {
  config_path = "../networking"
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init"]
}
`)

	cfg := &Config{
		Environments: map[string]EnvConfig{
			"env-a": {Path: "env-a", Provider: "aws", Auth: map[string]string{"profile": "test"}},
		},
	}

	g, err := Discover(cfg, root)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if g.Len() != 2 {
		t.Fatalf("expected 2 units, got %d", g.Len())
	}

	eks := g.Unit("env-a/eks")
	if eks == nil {
		t.Fatal("expected env-a/eks unit")
	}
	if len(eks.DependsOn) != 1 || eks.DependsOn[0] != "env-a/networking" {
		t.Fatalf("expected eks deps [env-a/networking], got %v", eks.DependsOn)
	}
	if eks.Provider != "aws" {
		t.Fatalf("expected provider aws, got %s", eks.Provider)
	}
	if eks.Auth["profile"] != "test" {
		t.Fatalf("expected auth profile test, got %v", eks.Auth)
	}
}

func TestDiscover_CrossEnvDependency(t *testing.T) {
	root := t.TempDir()
	setupFixture(t, root, "envs/platform/us-east-1/units", "networking", "")
	setupFixture(t, root, "envs/preprod/us-east-1/units", "networking", "")
	setupFixture(t, root, "envs/preprod/us-east-1/units", "eks", `
dependency "networking" {
  config_path = "../networking"
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init"]
}
`)
	// 4 levels up from cross-vpc-dns: units/ → us-east-1/ → platform/ → envs/ → then preprod path
	setupFixture(t, root, "envs/platform/us-east-1/units", "cross-vpc-dns", `
dependency "networking" {
  config_path = "../networking"
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init"]
}

dependency "preprod_eks" {
  config_path = "../../../../preprod/us-east-1/units/eks"
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init"]
}
`)

	cfg := &Config{
		Environments: map[string]EnvConfig{
			"platform": {Path: "envs/platform/us-east-1/units", Provider: "aws", Auth: map[string]string{"profile": "mgmt"}},
			"preprod":  {Path: "envs/preprod/us-east-1/units", Provider: "aws", Auth: map[string]string{"profile": "mgmt"}},
		},
	}

	g, err := Discover(cfg, root)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	dns := g.Unit("platform/cross-vpc-dns")
	if dns == nil {
		t.Fatal("expected platform/cross-vpc-dns unit")
	}

	expectedDeps := []string{"platform/networking", "preprod/eks"}
	if !sliceEqual(dns.DependsOn, expectedDeps) {
		t.Fatalf("expected deps %v, got %v", expectedDeps, dns.DependsOn)
	}
}

func TestDiscover_ImplicitDeps(t *testing.T) {
	root := t.TempDir()
	setupFixture(t, root, "env-a", "eks", "")
	setupFixture(t, root, "env-a", "tailscale", `
dependency "eks" {
  config_path = "../eks"
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init"]
}
`)
	setupFixture(t, root, "env-b", "tailscale-admin", "")

	cfg := &Config{
		Environments: map[string]EnvConfig{
			"env-a": {Path: "env-a", Provider: "aws", Auth: map[string]string{"profile": "mgmt"}},
			"env-b": {Path: "env-b", Provider: "aws", Auth: map[string]string{"profile": "mgmt"}},
		},
		Overrides: map[string]UnitOverride{
			"env-a/tailscale": {ImplicitDeps: []string{"env-b/tailscale-admin"}},
		},
	}

	g, err := Discover(cfg, root)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	ts := g.Unit("env-a/tailscale")
	if ts == nil {
		t.Fatal("expected env-a/tailscale unit")
	}

	expectedDeps := []string{"env-a/eks", "env-b/tailscale-admin"}
	if !sliceEqual(ts.DependsOn, expectedDeps) {
		t.Fatalf("expected deps %v, got %v", expectedDeps, ts.DependsOn)
	}
}

func TestDiscover_AuthOverride(t *testing.T) {
	root := t.TempDir()
	setupFixture(t, root, "env-a", "iam-roles", "")

	cfg := &Config{
		Environments: map[string]EnvConfig{
			"env-a": {Path: "env-a", Provider: "aws", Auth: map[string]string{"profile": "mgmt"}},
		},
		Overrides: map[string]UnitOverride{
			"env-a/iam-roles": {Auth: map[string]string{"profile": "preprod"}},
		},
	}

	g, err := Discover(cfg, root)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	iam := g.Unit("env-a/iam-roles")
	if iam == nil {
		t.Fatal("expected env-a/iam-roles unit")
	}
	if iam.Auth["profile"] != "preprod" {
		t.Fatalf("expected auth override to preprod, got %v", iam.Auth)
	}
}

func TestDiscover_SkipsNonUnitDirs(t *testing.T) {
	root := t.TempDir()
	setupFixture(t, root, "env-a", "networking", "")

	// Create a directory without terragrunt.hcl — should be ignored
	notUnit := filepath.Join(root, "env-a", "not-a-unit")
	if err := os.MkdirAll(notUnit, 0o755); err != nil {
		t.Fatal(err)
	}

	cfg := &Config{
		Environments: map[string]EnvConfig{
			"env-a": {Path: "env-a", Provider: "aws", Auth: map[string]string{"profile": "test"}},
		},
	}

	g, err := Discover(cfg, root)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if g.Len() != 1 {
		t.Fatalf("expected 1 unit, got %d", g.Len())
	}
}

func TestDiscover_NoDeps(t *testing.T) {
	root := t.TempDir()
	setupFixture(t, root, "env-a", "cloudtrail", "")
	setupFixture(t, root, "env-a", "iam-roles", "")

	cfg := &Config{
		Environments: map[string]EnvConfig{
			"env-a": {Path: "env-a", Provider: "aws", Auth: map[string]string{"profile": "test"}},
		},
	}

	g, err := Discover(cfg, root)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	ct := g.Unit("env-a/cloudtrail")
	if ct == nil {
		t.Fatal("expected env-a/cloudtrail unit")
	}
	if len(ct.DependsOn) != 0 {
		t.Fatalf("expected no deps for cloudtrail, got %v", ct.DependsOn)
	}
}

func TestDiscover_MultipleDeps(t *testing.T) {
	root := t.TempDir()
	setupFixture(t, root, "env-a", "networking", "")
	setupFixture(t, root, "env-a", "iam-roles", "")
	setupFixture(t, root, "env-a", "eks", `
dependency "networking" {
  config_path = "../networking"
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init"]
}

dependency "iam_roles" {
  config_path = "../iam-roles"
  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init"]
}
`)

	cfg := &Config{
		Environments: map[string]EnvConfig{
			"env-a": {Path: "env-a", Provider: "aws", Auth: map[string]string{"profile": "test"}},
		},
	}

	g, err := Discover(cfg, root)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	eks := g.Unit("env-a/eks")
	if eks == nil {
		t.Fatal("expected env-a/eks unit")
	}

	expectedDeps := []string{"env-a/iam-roles", "env-a/networking"}
	if !sliceEqual(eks.DependsOn, expectedDeps) {
		t.Fatalf("expected deps %v, got %v", expectedDeps, eks.DependsOn)
	}
}

// setupFixture creates a minimal terragrunt.hcl in a unit directory.
// If hclContent is empty, creates a bare-minimum file with no dependency blocks.
func setupFixture(t *testing.T, root, envPath, unitName, hclContent string) {
	t.Helper()
	dir := filepath.Join(root, envPath, unitName)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if hclContent == "" {
		hclContent = `
include "root" {
  path = "root.hcl"
}
`
	}
	if err := os.WriteFile(filepath.Join(dir, "terragrunt.hcl"), []byte(hclContent), 0o644); err != nil {
		t.Fatal(err)
	}
}

func sliceEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	aCopy := make([]string, len(a))
	bCopy := make([]string, len(b))
	copy(aCopy, a)
	copy(bCopy, b)
	sort.Strings(aCopy)
	sort.Strings(bCopy)
	for i := range aCopy {
		if aCopy[i] != bCopy[i] {
			return false
		}
	}
	return true
}
