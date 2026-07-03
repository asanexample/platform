package cli

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

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

func TestNodePoolsAllReady(t *testing.T) {
	cases := []struct {
		name     string
		statuses []string
		want     bool
	}{
		{"single true", []string{"True"}, true},
		{"all true", []string{"True", "True"}, true},
		{"one false", []string{"True", "False"}, false},
		{"unknown", []string{"Unknown"}, false},
		{"none (no nodepools)", nil, false},
	}
	for _, c := range cases {
		if got := nodePoolsAllReady(c.statuses); got != c.want {
			t.Errorf("%s: nodePoolsAllReady(%v) = %t, want %t", c.name, c.statuses, got, c.want)
		}
	}
}

func TestCheckAWSCredentialsForEnv(t *testing.T) {
	cfg := &config.Config{
		Environments: map[string]config.EnvConfig{
			"platform": {Auth: map[string]string{"profile": "management"}},
			"preprod":  {Auth: map[string]string{"profile": "preprod"}},
		},
	}
	kcPlatform := config.KubeconfigEntry{Profile: "platform", Region: "us-east-1"}
	kcPreprod := config.KubeconfigEntry{Profile: "preprod", Region: "us-east-1"}

	stub := func(t *testing.T, fn func(profile, region string) error) {
		t.Helper()
		orig := checkAWSCredentialsFn
		checkAWSCredentialsFn = fn
		t.Cleanup(func() { checkAWSCredentialsFn = orig })
	}

	t.Run("down: checks only the kubeconfig profile", func(t *testing.T) {
		var checked []string
		stub(t, func(profile, _ string) error { checked = append(checked, profile); return nil })

		if err := checkAWSCredentialsForEnv(cfg, "platform", kcPlatform, false); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(checked) != 1 || checked[0] != "platform" {
			t.Errorf("checked = %v, want [platform]", checked)
		}
	})

	t.Run("up: also checks the distinct terragrunt auth profile", func(t *testing.T) {
		var checked []string
		stub(t, func(profile, _ string) error { checked = append(checked, profile); return nil })

		if err := checkAWSCredentialsForEnv(cfg, "platform", kcPlatform, true); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(checked) != 2 || checked[0] != "platform" || checked[1] != "management" {
			t.Errorf("checked = %v, want [platform management]", checked)
		}
	})

	t.Run("up: dedupes when the kubeconfig and terragrunt profiles are the same", func(t *testing.T) {
		var checked []string
		stub(t, func(profile, _ string) error { checked = append(checked, profile); return nil })

		if err := checkAWSCredentialsForEnv(cfg, "preprod", kcPreprod, true); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(checked) != 1 || checked[0] != "preprod" {
			t.Errorf("checked = %v, want [preprod] (deduped)", checked)
		}
	})

	t.Run("propagates the first failing profile's error", func(t *testing.T) {
		stub(t, func(profile, _ string) error {
			if profile == "platform" {
				return fmt.Errorf("boom")
			}
			return nil
		})

		err := checkAWSCredentialsForEnv(cfg, "platform", kcPlatform, true)
		if err == nil || !strings.Contains(err.Error(), "boom") {
			t.Errorf("expected the platform-profile error to propagate, got %v", err)
		}
	})
}

func TestDrainKarpenterOrFail(t *testing.T) {
	kc := config.KubeconfigEntry{Alias: "platform", Cluster: "platform-use1-eks", Profile: "platform"}

	t.Run("propagates a real drain failure as a fatal, actionable error", func(t *testing.T) {
		orig := drainKarpenterNodesFn
		drainKarpenterNodesFn = func(context.Context, config.KubeconfigEntry) error {
			return fmt.Errorf("kubectl delete nodepool: exit status 1: ExpiredToken")
		}
		defer func() { drainKarpenterNodesFn = orig }()

		err := drainKarpenterOrFail(context.Background(), kc)
		if err == nil {
			t.Fatal("expected an error")
		}
		if !strings.Contains(err.Error(), "ExpiredToken") {
			t.Errorf("error should wrap the underlying cause, got %q", err.Error())
		}
		if !strings.Contains(err.Error(), "platform-use1-eks") || !strings.Contains(err.Error(), "platctl down") {
			t.Errorf("error should name the cluster and the re-run command, got %q", err.Error())
		}
	})

	t.Run("nil on success", func(t *testing.T) {
		orig := drainKarpenterNodesFn
		drainKarpenterNodesFn = func(context.Context, config.KubeconfigEntry) error { return nil }
		defer func() { drainKarpenterNodesFn = orig }()

		if err := drainKarpenterOrFail(context.Background(), kc); err != nil {
			t.Errorf("expected nil, got %v", err)
		}
	})
}

func TestPollKarpenterReady(t *testing.T) {
	t.Run("ready immediately — does not sleep", func(t *testing.T) {
		sleeps := 0
		ready, nc, st := pollKarpenterReady(func() (string, []string) {
			return "ec2nodeclass.karpenter.k8s.aws/default", []string{"True"}
		}, 5, func() { sleeps++ })
		if !ready || nc == "" || len(st) != 1 || st[0] != "True" {
			t.Fatalf("ready=%v nc=%q st=%v", ready, nc, st)
		}
		if sleeps != 0 {
			t.Errorf("sleeps = %d, want 0", sleeps)
		}
	})

	t.Run("never ready — exhausts attempts and reports the last state", func(t *testing.T) {
		sleeps := 0
		ready, nc, st := pollKarpenterReady(func() (string, []string) {
			return "", nil
		}, 3, func() { sleeps++ })
		if ready {
			t.Fatal("expected ready=false")
		}
		if nc != "" || st != nil {
			t.Errorf("nc=%q st=%v, want empty (NodeClassNotFound)", nc, st)
		}
		if sleeps != 2 {
			t.Errorf("sleeps = %d, want 2 (sleep between attempts, not after the last)", sleeps)
		}
	})

	t.Run("becomes ready on a later attempt", func(t *testing.T) {
		calls := 0
		ready, _, _ := pollKarpenterReady(func() (string, []string) {
			calls++
			if calls < 3 {
				return "ec2nodeclass.karpenter.k8s.aws/default", []string{"False"}
			}
			return "ec2nodeclass.karpenter.k8s.aws/default", []string{"True"}
		}, 5, func() {})
		if !ready || calls != 3 {
			t.Errorf("ready=%v calls=%d, want ready=true calls=3", ready, calls)
		}
	})

	t.Run("EC2NodeClass present but NodePool not Ready never reports ready", func(t *testing.T) {
		ready, nc, st := pollKarpenterReady(func() (string, []string) {
			return "ec2nodeclass.karpenter.k8s.aws/default", []string{"False"}
		}, 2, func() {})
		if ready {
			t.Fatal("expected ready=false when the NodePool condition is False")
		}
		if nc == "" {
			t.Error("expected the EC2NodeClass name to still be reported")
		}
		if len(st) != 1 || st[0] != "False" {
			t.Errorf("statuses = %v, want [False]", st)
		}
	})
}

// --- post-unpark DB-client recovery (startup-ordering) ---

func TestStuckDBClients(t *testing.T) {
	t0 := time.Date(2026, 7, 2, 9, 0, 0, 0, time.UTC)   // app start (early)
	dbReady := t0.Add(10 * time.Minute)                 // DB became Ready later
	afterDB := dbReady.Add(5 * time.Minute)             // started after the DB
	ready := map[string]time.Time{"backstage": dbReady} // backstage ns has a Ready DB

	pods := []podInfo{
		// the victim: started before its DB was Ready, not Ready, scheduled, a normal client
		{Namespace: "backstage", Name: "backstage-victim", Scheduled: true, StartTime: t0},
		// started AFTER the DB was Ready — healthy ordering, leave it
		{Namespace: "backstage", Name: "started-after", Scheduled: true, StartTime: afterDB},
		// already Ready — leave it
		{Namespace: "backstage", Name: "already-ready", Ready: true, Scheduled: true, StartTime: t0},
		// Pending (unscheduled) — a restart won't help
		{Namespace: "backstage", Name: "pending", Scheduled: false, StartTime: t0},
		// the CNPG database pod itself — never restart
		{Namespace: "backstage", Name: "backstage-db-1", IsCNPGDB: true, Scheduled: true, StartTime: t0},
		// a Job/CronJob pod — not meant to be Ready
		{Namespace: "backstage", Name: "cron-xyz", IsJob: true, Scheduled: true, StartTime: t0},
		// no CNPG DB in this namespace (e.g. checkout↔payments-db that doesn't exist) — out of scope
		{Namespace: "triage-demo", Name: "checkout", Scheduled: true, StartTime: t0},
		// unknown start time — can't prove it predates the DB, so leave it
		{Namespace: "backstage", Name: "no-starttime", Scheduled: true},
	}

	got := stuckDBClients(ready, pods)
	if len(got) != 1 || got[0].Name != "backstage-victim" {
		names := make([]string, len(got))
		for i, p := range got {
			names[i] = p.Name
		}
		t.Fatalf("stuckDBClients = %v, want [backstage-victim]", names)
	}
}

func TestCNPGDBReadyTimes(t *testing.T) {
	base := time.Date(2026, 7, 2, 9, 0, 0, 0, time.UTC)
	pods := []podInfo{
		{Namespace: "backstage", Name: "db-1", IsCNPGDB: true, Ready: true, ReadyTime: base.Add(2 * time.Minute)},
		{Namespace: "keycloak", Name: "db-a", IsCNPGDB: true, Ready: true, ReadyTime: base.Add(1 * time.Minute)},
		{Namespace: "keycloak", Name: "db-b", IsCNPGDB: true, Ready: true, ReadyTime: base.Add(3 * time.Minute)},  // later replica → ns Ready time = max
		{Namespace: "keycloak", Name: "db-c", IsCNPGDB: true, Ready: false, ReadyTime: base.Add(9 * time.Minute)}, // not Ready → ignored
		{Namespace: "app", Name: "web", Ready: true, ReadyTime: base},                                             // not a CNPG pod → ignored
	}
	got := cnpgDBReadyTimes(pods)
	if len(got) != 2 {
		t.Fatalf("expected 2 namespaces with Ready DBs, got %v", got)
	}
	if !got["backstage"].Equal(base.Add(2 * time.Minute)) {
		t.Errorf("backstage ready time = %v", got["backstage"])
	}
	if !got["keycloak"].Equal(base.Add(3 * time.Minute)) {
		t.Errorf("keycloak ready time = %v, want the max (3m)", got["keycloak"])
	}
	if _, ok := got["app"]; ok {
		t.Error("non-CNPG namespace must not appear")
	}
}

func TestWaitingOnDB(t *testing.T) {
	base := time.Date(2026, 7, 2, 9, 0, 0, 0, time.UTC)

	t.Run("candidate waiting on a not-yet-Ready DB → true", func(t *testing.T) {
		pods := []podInfo{
			{Namespace: "backstage", Name: "db-1", IsCNPGDB: true, Ready: false}, // DB present, not Ready
			{Namespace: "backstage", Name: "backstage", Scheduled: true},         // candidate, not Ready
		}
		if !waitingOnDB(pods, cnpgDBReadyTimes(pods)) {
			t.Error("expected waitingOnDB=true (DB exists but not Ready yet)")
		}
	})

	t.Run("DB already Ready → false", func(t *testing.T) {
		pods := []podInfo{
			{Namespace: "backstage", Name: "db-1", IsCNPGDB: true, Ready: true, ReadyTime: base},
			{Namespace: "backstage", Name: "backstage", Scheduled: true},
		}
		if waitingOnDB(pods, cnpgDBReadyTimes(pods)) {
			t.Error("expected waitingOnDB=false (DB is Ready)")
		}
	})

	t.Run("candidate in a namespace with no CNPG DB → false", func(t *testing.T) {
		pods := []podInfo{
			{Namespace: "triage-demo", Name: "checkout", Scheduled: true}, // no CNPG DB here
		}
		if waitingOnDB(pods, cnpgDBReadyTimes(pods)) {
			t.Error("expected waitingOnDB=false (nothing to wait for)")
		}
	})
}
