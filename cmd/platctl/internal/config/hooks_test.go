package config

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

type mockRunner struct {
	calls []mockCall
}

type mockCall struct {
	Unit   string
	Action engine.Action
	Args   []string
}

func (m *mockRunner) Run(_ context.Context, unit *engine.Unit, action engine.Action, args ...string) error {
	m.calls = append(m.calls, mockCall{Unit: unit.Name, Action: action, Args: args})
	return nil
}

func TestCRDTwoStageHook_Apply(t *testing.T) {
	hook := &CRDTwoStageHook{Target: "helm_release.tailscale_operator[0]"}
	runner := &mockRunner{}
	unit := &engine.Unit{Name: "platform/tailscale", Path: "/tmp/test"}

	if err := hook.Execute(context.Background(), runner, unit, engine.Apply); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(runner.calls) != 2 {
		t.Fatalf("expected 2 calls, got %d", len(runner.calls))
	}

	// Stage 1: targeted apply
	if len(runner.calls[0].Args) != 1 || runner.calls[0].Args[0] != "-target=helm_release.tailscale_operator[0]" {
		t.Fatalf("stage 1 expected target arg, got %v", runner.calls[0].Args)
	}

	// Stage 2: full apply (no extra args)
	if len(runner.calls[1].Args) != 0 {
		t.Fatalf("stage 2 expected no args, got %v", runner.calls[1].Args)
	}
}

func TestCRDTwoStageHook_ApplyWithBootstrapArgs(t *testing.T) {
	hook := &CRDTwoStageHook{Target: "helm_release.tailscale_operator[0]"}
	runner := &mockRunner{}
	unit := &engine.Unit{Name: "platform/tailscale", Path: "/tmp/test"}

	if err := hook.Execute(context.Background(), runner, unit, engine.Apply, "-var", "split_dns={}"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(runner.calls) != 2 {
		t.Fatalf("expected 2 calls, got %d", len(runner.calls))
	}

	// Stage 1: target arg + bootstrap args
	expect1 := []string{"-target=helm_release.tailscale_operator[0]", "-var", "split_dns={}"}
	if len(runner.calls[0].Args) != len(expect1) {
		t.Fatalf("stage 1 expected %v, got %v", expect1, runner.calls[0].Args)
	}
	for i, arg := range expect1 {
		if runner.calls[0].Args[i] != arg {
			t.Fatalf("stage 1 arg %d: expected %q, got %q", i, arg, runner.calls[0].Args[i])
		}
	}

	// Stage 2: only bootstrap args (no target)
	expect2 := []string{"-var", "split_dns={}"}
	if len(runner.calls[1].Args) != len(expect2) {
		t.Fatalf("stage 2 expected %v, got %v", expect2, runner.calls[1].Args)
	}
	for i, arg := range expect2 {
		if runner.calls[1].Args[i] != arg {
			t.Fatalf("stage 2 arg %d: expected %q, got %q", i, arg, runner.calls[1].Args[i])
		}
	}
}

func TestCRDTwoStageHook_Destroy(t *testing.T) {
	hook := &CRDTwoStageHook{Target: "helm_release.tailscale_operator[0]"}
	runner := &mockRunner{}
	unit := &engine.Unit{Name: "platform/tailscale", Path: "/tmp/test"}

	if err := hook.Execute(context.Background(), runner, unit, engine.Destroy); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Destroy is a single call, no two-stage
	if len(runner.calls) != 1 {
		t.Fatalf("expected 1 call for destroy, got %d", len(runner.calls))
	}
	if runner.calls[0].Action != engine.Destroy {
		t.Fatalf("expected destroy action, got %v", runner.calls[0].Action)
	}
}

type mockAWSClient struct {
	secretExists   bool
	eniIPs         []string
	deletedSecrets []string
}

func (m *mockAWSClient) SecretExists(_ context.Context, _ string, _ map[string]string) (bool, error) {
	return m.secretExists, nil
}

func (m *mockAWSClient) DescribeEKSENIs(_ context.Context, _ string, _ map[string]string) ([]string, error) {
	return m.eniIPs, nil
}

func (m *mockAWSClient) ForceDeleteSecret(_ context.Context, secretID string, _ map[string]string) error {
	m.deletedSecrets = append(m.deletedSecrets, secretID)
	return nil
}

func TestManualStepChecker_SecretExists(t *testing.T) {
	client := &mockAWSClient{secretExists: true}
	checker := &ManualStepChecker{Client: client}

	step := ManualStep{
		Name: "test-secret",
		Check: StepCheck{
			Type:     "secret_exists",
			SecretID: "my/secret",
			Profile:  "test",
		},
	}

	ok, err := checker.Check(context.Background(), step)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Fatal("expected secret to exist")
	}
}

func TestManualStepChecker_SecretMissing(t *testing.T) {
	client := &mockAWSClient{secretExists: false}
	checker := &ManualStepChecker{Client: client}

	step := ManualStep{
		Name: "test-secret",
		Check: StepCheck{
			Type:     "secret_exists",
			SecretID: "my/secret",
			Profile:  "test",
		},
	}

	ok, err := checker.Check(context.Background(), step)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Fatal("expected secret to not exist")
	}
}

func TestManualStepChecker_FileContains(t *testing.T) {
	dir := t.TempDir()
	filePath := filepath.Join(dir, "common.hcl")
	os.WriteFile(filePath, []byte(`argocd_sso_url = "https://example.com"`), 0o644)

	checker := &ManualStepChecker{RepoRoot: dir}

	step := ManualStep{
		Name: "argocd-saml",
		Check: StepCheck{
			Type:    "file_contains",
			File:    "common.hcl",
			Pattern: "argocd_sso_url",
		},
	}

	ok, err := checker.Check(context.Background(), step)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Fatal("expected file to contain pattern")
	}
}

func TestManualStepChecker_FileNotContains(t *testing.T) {
	dir := t.TempDir()
	filePath := filepath.Join(dir, "common.hcl")
	os.WriteFile(filePath, []byte(`some_other_setting = "value"`), 0o644)

	checker := &ManualStepChecker{RepoRoot: dir}

	step := ManualStep{
		Name: "argocd-saml",
		Check: StepCheck{
			Type:    "file_contains",
			File:    "common.hcl",
			Pattern: "argocd_sso_url",
		},
	}

	ok, err := checker.Check(context.Background(), step)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Fatal("expected file to not contain pattern")
	}
}

func TestResolveHook_CRDTwoStage(t *testing.T) {
	override := UnitOverride{
		Hook:       "crd_two_stage",
		HookTarget: "helm_release.operator[0]",
	}
	hook := ResolveHook(override, nil, false)
	if hook == nil {
		t.Fatal("expected non-nil hook")
	}
	if _, ok := hook.(*CRDTwoStageHook); !ok {
		t.Fatalf("expected CRDTwoStageHook, got %T", hook)
	}
}

func TestResolveHook_ENIValidation(t *testing.T) {
	override := UnitOverride{
		Hook: "eni_ip_validation",
		HookConfig: map[string]string{
			"cluster_name": "test-cluster",
			"profile":      "management",
		},
	}
	hook := ResolveHook(override, &mockAWSClient{}, true)
	if hook == nil {
		t.Fatal("expected non-nil hook")
	}
	eni, ok := hook.(*ENIIPValidationHook)
	if !ok {
		t.Fatalf("expected ENIIPValidationHook, got %T", hook)
	}
	if eni.ClusterName != "test-cluster" {
		t.Fatalf("expected cluster name test-cluster, got %s", eni.ClusterName)
	}
}

func TestResolveHook_StatePurge(t *testing.T) {
	override := UnitOverride{
		Hook:       "state_purge",
		HookConfig: map[string]string{"patterns": "keycloak_, foo_bar ,"},
	}
	hook := ResolveHook(override, nil, false)
	sp, ok := hook.(*StatePurgeHook)
	if !ok {
		t.Fatalf("expected StatePurgeHook, got %T", hook)
	}
	// Comma-split, trimmed, empty entries dropped.
	if len(sp.Patterns) != 2 || sp.Patterns[0] != "keycloak_" || sp.Patterns[1] != "foo_bar" {
		t.Fatalf("expected [keycloak_ foo_bar], got %v", sp.Patterns)
	}
}

func TestStatePurgeHook_ApplyPassthrough(t *testing.T) {
	hook := &StatePurgeHook{Patterns: []string{"keycloak_"}}
	runner := &mockRunner{}
	unit := &engine.Unit{Name: "platform/keycloak-config", Path: "/tmp/test"}

	// Apply must never purge — single straight-through Run with the action preserved.
	if err := hook.Execute(context.Background(), runner, unit, engine.Apply, "-var", "x=1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) != 1 || runner.calls[0].Action != engine.Apply {
		t.Fatalf("expected 1 apply call, got %v", runner.calls)
	}
	if len(runner.calls[0].Args) != 2 || runner.calls[0].Args[0] != "-var" {
		t.Fatalf("expected args forwarded, got %v", runner.calls[0].Args)
	}
}

func TestStatePurgeHook_DestroyNoPatterns(t *testing.T) {
	hook := &StatePurgeHook{Patterns: nil}
	runner := &mockRunner{}
	unit := &engine.Unit{Name: "platform/keycloak-config", Path: "/tmp/test"}

	// No patterns -> straight destroy, no terragrunt state calls.
	if err := hook.Execute(context.Background(), runner, unit, engine.Destroy); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) != 1 || runner.calls[0].Action != engine.Destroy {
		t.Fatalf("expected 1 destroy call, got %v", runner.calls)
	}
}

func TestSecretCleanupHook_DeletesExisting(t *testing.T) {
	client := &mockAWSClient{secretExists: true}
	hook := &SecretCleanupHook{
		Secrets: []SecretEntry{
			{ID: "my/secret-1", Auth: map[string]string{"profile": "test"}},
			{ID: "my/secret-2", Auth: map[string]string{"profile": "test"}},
		},
		Client: client,
	}
	runner := &mockRunner{}
	unit := &engine.Unit{Name: "platform/tailscale-admin", Path: "/tmp/test"}

	if err := hook.Execute(context.Background(), runner, unit, engine.Apply); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(client.deletedSecrets) != 2 {
		t.Fatalf("expected 2 deletions, got %d: %v", len(client.deletedSecrets), client.deletedSecrets)
	}
	if len(runner.calls) != 1 || runner.calls[0].Action != engine.Apply {
		t.Fatalf("expected 1 apply call, got %d", len(runner.calls))
	}
}

func TestSecretCleanupHook_SkipsNonExistent(t *testing.T) {
	client := &mockAWSClient{secretExists: false}
	hook := &SecretCleanupHook{
		Secrets: []SecretEntry{
			{ID: "my/secret-1", Auth: map[string]string{"profile": "test"}},
		},
		Client: client,
	}
	runner := &mockRunner{}
	unit := &engine.Unit{Name: "platform/tailscale-admin", Path: "/tmp/test"}

	if err := hook.Execute(context.Background(), runner, unit, engine.Apply); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(client.deletedSecrets) != 0 {
		t.Fatalf("expected no deletions, got %v", client.deletedSecrets)
	}
	if len(runner.calls) != 1 {
		t.Fatalf("expected 1 apply call, got %d", len(runner.calls))
	}
}

func TestSecretCleanupHook_Destroy(t *testing.T) {
	client := &mockAWSClient{secretExists: true}
	hook := &SecretCleanupHook{
		Secrets: []SecretEntry{
			{ID: "my/secret-1", Auth: map[string]string{}},
		},
		Client: client,
	}
	runner := &mockRunner{}
	unit := &engine.Unit{Name: "platform/tailscale-admin", Path: "/tmp/test"}

	if err := hook.Execute(context.Background(), runner, unit, engine.Destroy); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(client.deletedSecrets) != 0 {
		t.Fatalf("expected no cleanup on destroy, got %v", client.deletedSecrets)
	}
}

func TestResolveHook_SecretCleanup(t *testing.T) {
	override := UnitOverride{
		Hook: "secret_cleanup",
		HookConfig: map[string]string{
			"profile": "platform",
			"secrets": "my/secret@platform,other/secret@preprod",
		},
	}
	hook := ResolveHook(override, &mockAWSClient{}, false)
	if hook == nil {
		t.Fatal("expected non-nil hook")
	}
	sc, ok := hook.(*SecretCleanupHook)
	if !ok {
		t.Fatalf("expected SecretCleanupHook, got %T", hook)
	}
	if len(sc.Secrets) != 2 {
		t.Fatalf("expected 2 secrets, got %d", len(sc.Secrets))
	}
	if sc.Secrets[0].ID != "my/secret" || sc.Secrets[0].Auth["profile"] != "platform" {
		t.Fatalf("expected my/secret@platform, got %s@%s", sc.Secrets[0].ID, sc.Secrets[0].Auth["profile"])
	}
	if sc.Secrets[1].ID != "other/secret" || sc.Secrets[1].Auth["profile"] != "preprod" {
		t.Fatalf("expected other/secret@preprod, got %s@%s", sc.Secrets[1].ID, sc.Secrets[1].Auth["profile"])
	}
}

func TestResolveHook_SecretCleanupDefaultProfile(t *testing.T) {
	override := UnitOverride{
		Hook: "secret_cleanup",
		HookConfig: map[string]string{
			"profile": "default-profile",
			"secrets": "my/secret",
		},
	}
	hook := ResolveHook(override, &mockAWSClient{}, false)
	sc := hook.(*SecretCleanupHook)
	if sc.Secrets[0].Auth["profile"] != "default-profile" {
		t.Fatalf("expected default profile, got %s", sc.Secrets[0].Auth["profile"])
	}
}

func TestResolveHook_Unknown(t *testing.T) {
	override := UnitOverride{Hook: "nonexistent"}
	hook := ResolveHook(override, nil, false)
	if hook != nil {
		t.Fatal("expected nil hook for unknown type")
	}
}

func TestParseTokenJSON(t *testing.T) {
	cases := []struct {
		name, in, key, want string
	}{
		{"normal", `{"token":"eyJabc"}`, "token", "eyJabc"},
		{"whitespace", "  {\"token\":\"x\"}\n", "token", "x"},
		{"missing key", `{"other":"x"}`, "token", ""},
		{"not json", "eyJrawtoken", "token", ""},
		{"empty", "", "token", ""},
		{"custom key", `{"argocdToken":"y"}`, "argocdToken", "y"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := parseTokenJSON(c.in, c.key); got != c.want {
				t.Errorf("parseTokenJSON(%q,%q) = %q, want %q", c.in, c.key, got, c.want)
			}
		})
	}
}

func TestUserInfoLoggedIn(t *testing.T) {
	cases := []struct {
		name, in string
		want     bool
	}{
		{"valid", "Logged In: true\nUsername: backstage\nIssuer: argocd\n", true},
		{"invalid", "Logged In: false\n", false},
		{"indented", "  Logged In: true  \n", true},
		{"empty", "", false},
		{"error text", "FATA[0000] rpc error: unauthenticated", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := userInfoLoggedIn(c.in); got != c.want {
				t.Errorf("userInfoLoggedIn(%q) = %v, want %v", c.in, got, c.want)
			}
		})
	}
}

func TestIsSafeAccountName(t *testing.T) {
	safe := []string{"backstage", "ci-bot", "team_alpha", "abc123"}
	unsafe := []string{"", "back stage", "a;b", "x'y", "$(whoami)", "a&b"}
	for _, s := range safe {
		if !isSafeAccountName(s) {
			t.Errorf("isSafeAccountName(%q) = false, want true", s)
		}
	}
	for _, s := range unsafe {
		if isSafeAccountName(s) {
			t.Errorf("isSafeAccountName(%q) = true, want false", s)
		}
	}
}

func TestResolveArgoTokenHook(t *testing.T) {
	h := ResolveHook(UnitOverride{
		Hook: "argocd_account_token",
		HookConfig: map[string]string{
			"cluster": "platform-use1-eks", "region": "us-east-1", "profile": "platform",
			"role_arn": "arn:aws:iam::1:role/PlatformAdmin", "account": "backstage",
			"secret_id": "platform/argocd/backstage-token",
		},
	}, nil, false)
	ah, ok := h.(*ArgoTokenHook)
	if !ok {
		t.Fatalf("expected *ArgoTokenHook, got %T", h)
	}
	if ah.Cluster != "platform-use1-eks" || ah.SecretID != "platform/argocd/backstage-token" {
		t.Errorf("hook fields not wired: %+v", ah)
	}
	// defaults applied via accessors
	if ah.account() != "backstage" || ah.namespace() != "argocd" || ah.serverDeploy() != "argocd-server" || ah.secretKey() != "token" {
		t.Errorf("defaults wrong: account=%s ns=%s deploy=%s key=%s", ah.account(), ah.namespace(), ah.serverDeploy(), ah.secretKey())
	}
	if ah.smProfile() != "platform" || ah.smRegion() != "us-east-1" {
		t.Errorf("sm fallbacks wrong: profile=%s region=%s", ah.smProfile(), ah.smRegion())
	}
}

func TestArgoTokenReconcileMisconfigured(t *testing.T) {
	h := &ArgoTokenHook{} // no secret_id/cluster
	if err := h.reconcile(context.Background()); err == nil {
		t.Error("expected error for misconfigured hook")
	}
}
