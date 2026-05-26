package config

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/gangster/platform/cmd/platctl/internal/engine"
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
	secretExists bool
	eniIPs       []string
}

func (m *mockAWSClient) SecretExists(_ context.Context, _ string, _ map[string]string) (bool, error) {
	return m.secretExists, nil
}

func (m *mockAWSClient) DescribeEKSENIs(_ context.Context, _ string, _ map[string]string) ([]string, error) {
	return m.eniIPs, nil
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

func TestResolveHook_Unknown(t *testing.T) {
	override := UnitOverride{Hook: "nonexistent"}
	hook := ResolveHook(override, nil, false)
	if hook != nil {
		t.Fatal("expected nil hook for unknown type")
	}
}
