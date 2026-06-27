package cli

import (
	"context"
	"strings"
	"testing"

	"github.com/asanexample/platform/cmd/platctl/internal/config"
	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// fakeRunner records the units it is asked to run (no real terragrunt).
type fakeRunner struct{ applied []*engine.Unit }

func (f *fakeRunner) Run(_ context.Context, u *engine.Unit, _ engine.Action, _ ...string) error {
	f.applied = append(f.applied, u)
	return nil
}

func TestReconnectConfigParse(t *testing.T) {
	cfg, err := config.Parse([]byte(`
environments:
  platform:
    path: infra/live/aws/platform/us-east-1/platform
    provider: aws
  preprod:
    path: infra/live/aws/preprod/us-east-1/platform
    provider: aws
    reconnect:
      units:
        - { env: platform, unit: cross-vpc-dns }
      restarts:
        - { env: platform, namespace: argocd, target: statefulset/argocd-application-controller }
`))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	rc := cfg.Environments["preprod"].Reconnect
	if rc == nil {
		t.Fatal("preprod.reconnect not parsed")
	}
	if len(rc.Units) != 1 || rc.Units[0].Env != "platform" || rc.Units[0].Unit != "cross-vpc-dns" {
		t.Errorf("units = %+v", rc.Units)
	}
	if len(rc.Restarts) != 1 || rc.Restarts[0].Target != "statefulset/argocd-application-controller" {
		t.Errorf("restarts = %+v", rc.Restarts)
	}
	if cfg.Environments["platform"].Reconnect != nil {
		t.Error("platform should have no reconnect block")
	}
}

func TestReconnectConfigValidation(t *testing.T) {
	_, err := config.Parse([]byte(`
environments:
  preprod:
    path: p
    provider: aws
    reconnect:
      units:
        - { env: platform }
`))
	if err == nil {
		t.Fatal("expected validation error for a reconnect unit missing 'unit'")
	}
}

func TestRunReconnect(t *testing.T) {
	cfg := &config.Config{
		Environments: map[string]config.EnvConfig{
			"platform": {Path: "infra/live/aws/platform/us-east-1/platform", Provider: "aws", Auth: map[string]string{"profile": "management"}},
			"preprod":  {Path: "infra/live/aws/preprod/us-east-1/platform", Provider: "aws", Auth: map[string]string{"profile": "management"}},
		},
		Kubeconfig: []config.KubeconfigEntry{
			{Alias: "platform", Cluster: "platform-use1-eks", Region: "us-east-1", Profile: "platform", KubectlRoleARN: "arn:aws:iam::1:role/PlatformAdmin"},
		},
	}
	rc := &config.Reconnect{
		Units:    []config.ReconnectUnit{{Env: "platform", Unit: "cross-vpc-dns"}},
		Restarts: []config.ReconnectRestart{{Env: "platform", Namespace: "argocd", Target: "statefulset/argocd-application-controller"}},
	}

	var gotNS, gotTarget, gotCluster string
	orig := rolloutRestartFn
	rolloutRestartFn = func(_ context.Context, kc config.KubeconfigEntry, ns, target string) error {
		gotCluster, gotNS, gotTarget = kc.Cluster, ns, target
		return nil
	}
	defer func() { rolloutRestartFn = orig }()

	fr := &fakeRunner{}
	if err := runReconnect(context.Background(), cfg, "/repo", "preprod", rc, fr); err != nil {
		t.Fatalf("runReconnect: %v", err)
	}

	if len(fr.applied) != 1 || fr.applied[0].Name != "platform/cross-vpc-dns" {
		t.Fatalf("applied = %+v, want platform/cross-vpc-dns", fr.applied)
	}
	if fr.applied[0].Path != "/repo/infra/live/aws/platform/us-east-1/platform/cross-vpc-dns" {
		t.Errorf("unit path = %q", fr.applied[0].Path)
	}
	if fr.applied[0].Auth["profile"] != "management" {
		t.Errorf("unit auth = %+v, want profile=management", fr.applied[0].Auth)
	}
	if gotCluster != "platform-use1-eks" || gotNS != "argocd" || gotTarget != "statefulset/argocd-application-controller" {
		t.Errorf("restart = %s %s/%s", gotCluster, gotNS, gotTarget)
	}
}

func TestRunReconnectReportsBadUnitEnv(t *testing.T) {
	cfg := &config.Config{Environments: map[string]config.EnvConfig{
		"preprod": {Path: "p", Provider: "aws"},
	}}
	rc := &config.Reconnect{Units: []config.ReconnectUnit{{Env: "nope", Unit: "cross-vpc-dns"}}}
	fr := &fakeRunner{}
	if err := runReconnect(context.Background(), cfg, "/repo", "preprod", rc, fr); err == nil {
		t.Fatal("expected an error when a reconnect unit references an unknown env")
	}
	if len(fr.applied) != 0 {
		t.Errorf("nothing should have been applied, got %+v", fr.applied)
	}
}

func TestKubeconfigForEnv(t *testing.T) {
	cfg := &config.Config{
		Kubeconfig: []config.KubeconfigEntry{
			{Alias: "platform", Cluster: "platform-use1-eks", Region: "us-east-1", Profile: "platform"},
			{Alias: "preprod", Cluster: "preprod-use1-eks", Region: "us-east-1", Profile: "preprod"},
		},
	}

	got, err := kubeconfigForEnv(cfg, "preprod")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Cluster != "preprod-use1-eks" || got.Profile != "preprod" {
		t.Errorf("got %+v, want preprod-use1-eks/preprod", got)
	}

	if _, err := kubeconfigForEnv(cfg, "does-not-exist"); err == nil {
		t.Error("expected an error for an unknown env, got nil")
	}
}

func TestBastionName(t *testing.T) {
	cases := map[string]string{
		"platform-use1-eks": "platform-use1-ssm-bastion",
		"preprod-use1-eks":  "preprod-use1-ssm-bastion",
	}
	for cluster, want := range cases {
		if got := bastionName(cluster); got != want {
			t.Errorf("bastionName(%q) = %q, want %q", cluster, got, want)
		}
	}
}

func TestFindBlockedDeployments(t *testing.T) {
	// ns name spec status — app1 wants 2 has 0 (blocked); app2 1/1 (ok); app3 0/0 (not wanted); app4 wants 3, no
	// status field at all (blocked — the symptom when zero pods exist).
	k := func(_ ...string) ([]byte, error) {
		return []byte("a app1 2 0\nb app2 1 1\nc app3 0 0\nd app4 3\n"), nil
	}
	got, err := findBlockedDeployments(k)
	if err != nil {
		t.Fatalf("findBlockedDeployments: %v", err)
	}
	want := map[string]bool{"a/app1": true, "d/app4": true}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %d blocked", got, len(want))
	}
	for _, b := range got {
		if !want[b[0]+"/"+b[1]] {
			t.Errorf("unexpected blocked workload: %s/%s", b[0], b[1])
		}
	}
}

func TestLatestFailedCreate(t *testing.T) {
	msg := `admission webhook "mutate.kyverno.svc-fail" denied: ecr BatchGetImage denied`
	k := func(_ ...string) ([]byte, error) { return []byte(msg + "\n"), nil }
	if got := latestFailedCreate(k, "ns"); got != msg {
		t.Errorf("latestFailedCreate = %q, want %q", got, msg)
	}
	empty := func(_ ...string) ([]byte, error) { return []byte("   "), nil }
	if got := latestFailedCreate(empty, "ns"); !strings.Contains(got, "no FailedCreate event") {
		t.Errorf("expected fallback hint, got %q", got)
	}
}
