package validate

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/asanexample/platform/cmd/platctl/internal/config"
	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// mockRunner returns a CommandRunner that matches commands and returns canned output.
type mockCall struct {
	prefix string // matched against "name arg1 arg2 ..."
	out    []byte
	err    error
}

func newMockRunner(calls ...mockCall) CommandRunner {
	return func(_ context.Context, name string, args ...string) ([]byte, error) {
		cmd := name + " " + strings.Join(args, " ")
		for _, c := range calls {
			if strings.HasPrefix(cmd, c.prefix) {
				return c.out, c.err
			}
		}
		return nil, fmt.Errorf("unmocked command: %s", cmd)
	}
}

// --- RunChecks tests ---

func TestRunChecks_Parallel_PreservesOrder(t *testing.T) {
	checks := make([]Checker, 5)
	for i := range checks {
		name := fmt.Sprintf("check-%d", i)
		checks[i] = &stubChecker{name: name}
	}

	results := RunChecks(context.Background(), checks, 4)
	if len(results) != 5 {
		t.Fatalf("expected 5 results, got %d", len(results))
	}
	for i, r := range results {
		expected := fmt.Sprintf("check-%d", i)
		if r.Name != expected {
			t.Errorf("result[%d]: expected name %q, got %q", i, expected, r.Name)
		}
	}
}

type stubChecker struct {
	name   string
	status string
}

func (s *stubChecker) CheckName() string { return s.name }
func (s *stubChecker) Check(_ context.Context) CheckResult {
	st := s.status
	if st == "" {
		st = "ok"
	}
	return CheckResult{Name: s.name, Status: st, Message: "stub"}
}

// --- RunValidation tests ---

func TestRunValidation_IAMFail_SkipsOtherChecks(t *testing.T) {
	iamChecks := []Checker{
		&stubChecker{name: "iam", status: "failed"},
	}
	otherChecks := []Checker{
		&stubChecker{name: "eks"},
		&stubChecker{name: "dns"},
	}

	results := RunValidation(context.Background(), iamChecks, otherChecks, 4, nil)
	if len(results) != 3 {
		t.Fatalf("expected 3 results, got %d", len(results))
	}
	if results[0].Status != "failed" {
		t.Errorf("IAM check should be failed, got %s", results[0].Status)
	}
	for i := 1; i < len(results); i++ {
		if results[i].Status != "skipped" {
			t.Errorf("result[%d] should be skipped, got %s", i, results[i].Status)
		}
	}
}

func TestRunValidation_IAMPass_RunsOtherChecks(t *testing.T) {
	iamChecks := []Checker{
		&stubChecker{name: "iam", status: "ok"},
	}
	otherChecks := []Checker{
		&stubChecker{name: "eks"},
		&stubChecker{name: "dns"},
	}

	results := RunValidation(context.Background(), iamChecks, otherChecks, 4, nil)
	if len(results) != 3 {
		t.Fatalf("expected 3 results, got %d", len(results))
	}
	for _, r := range results {
		if r.Status != "ok" {
			t.Errorf("%s should be ok, got %s", r.Name, r.Status)
		}
	}
}

// --- EKSClusterCheck tests ---

func TestEKSClusterCheck_ActiveWithHealthyNodes(t *testing.T) {
	nodes := map[string]interface{}{
		"items": []map[string]interface{}{
			{
				"metadata": map[string]string{"name": "node-1"},
				"status": map[string]interface{}{
					"conditions": []map[string]string{
						{"type": "Ready", "status": "True"},
					},
				},
			},
			{
				"metadata": map[string]string{"name": "node-2"},
				"status": map[string]interface{}{
					"conditions": []map[string]string{
						{"type": "Ready", "status": "True"},
					},
				},
			},
		},
	}
	nodesJSON, _ := json.Marshal(nodes)

	run := newMockRunner(
		mockCall{prefix: "aws eks describe-cluster", out: []byte("ACTIVE\n")},
		mockCall{prefix: "kubectl --context test get nodes", out: nodesJSON},
	)

	check := &EKSClusterCheck{
		Name:        "test/eks",
		ClusterName: "test-cluster",
		KubeContext: "test",
		Auth:        map[string]string{"profile": "test"},
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "ok" {
		t.Errorf("expected ok, got %s: %s", result.Status, result.Message)
	}
	if !strings.Contains(result.Message, "2/2 nodes ready") {
		t.Errorf("expected '2/2 nodes ready' in message, got %q", result.Message)
	}
}

func TestEKSClusterCheck_ClusterNotActive(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "aws eks describe-cluster", out: []byte("CREATING\n")},
	)

	check := &EKSClusterCheck{
		Name:        "test/eks",
		ClusterName: "test-cluster",
		KubeContext: "test",
		Auth:        map[string]string{"profile": "test"},
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "failed" {
		t.Errorf("expected failed, got %s", result.Status)
	}
	if !strings.Contains(result.Message, "CREATING") {
		t.Errorf("expected CREATING in message, got %q", result.Message)
	}
}

func TestEKSClusterCheck_UnhealthyNode(t *testing.T) {
	nodes := map[string]interface{}{
		"items": []map[string]interface{}{
			{
				"metadata": map[string]string{"name": "node-1"},
				"status": map[string]interface{}{
					"conditions": []map[string]string{
						{"type": "Ready", "status": "True"},
					},
				},
			},
			{
				"metadata": map[string]string{"name": "node-2"},
				"status": map[string]interface{}{
					"conditions": []map[string]string{
						{"type": "Ready", "status": "False"},
					},
				},
			},
		},
	}
	nodesJSON, _ := json.Marshal(nodes)

	run := newMockRunner(
		mockCall{prefix: "aws eks describe-cluster", out: []byte("ACTIVE\n")},
		mockCall{prefix: "kubectl --context test get nodes", out: nodesJSON},
	)

	check := &EKSClusterCheck{
		Name:        "test/eks",
		ClusterName: "test-cluster",
		KubeContext: "test",
		Auth:        map[string]string{"profile": "test"},
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "failed" {
		t.Errorf("expected failed, got %s", result.Status)
	}
	if !strings.Contains(result.Message, "1/2 nodes ready") {
		t.Errorf("expected '1/2 nodes ready' in message, got %q", result.Message)
	}
}

// --- K8sWorkloadCheck tests ---

func TestK8sWorkloadCheck_AllHealthy(t *testing.T) {
	pods := map[string]interface{}{
		"items": []map[string]interface{}{
			{
				"metadata": map[string]string{"name": "pod-1"},
				"status": map[string]interface{}{
					"phase":             "Running",
					"containerStatuses": []map[string]interface{}{{"ready": true}},
				},
			},
		},
	}
	podsJSON, _ := json.Marshal(pods)

	run := newMockRunner(
		mockCall{prefix: "kubectl", out: podsJSON},
	)

	check := &K8sWorkloadCheck{
		Name:        "test/cilium",
		KubeContext: "test",
		Namespace:   "kube-system",
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "ok" {
		t.Errorf("expected ok, got %s: %s", result.Status, result.Message)
	}
}

func TestK8sWorkloadCheck_NoPods(t *testing.T) {
	podsJSON, _ := json.Marshal(map[string]interface{}{"items": []interface{}{}})

	run := newMockRunner(
		mockCall{prefix: "kubectl", out: podsJSON},
	)

	check := &K8sWorkloadCheck{
		Name:        "test/addon",
		KubeContext: "test",
		Namespace:   "kube-system",
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "failed" {
		t.Errorf("expected failed, got %s", result.Status)
	}
	if !strings.Contains(result.Message, "no pods found") {
		t.Errorf("expected 'no pods found', got %q", result.Message)
	}
}

// --- KarpenterReadyCheck tests ---

func TestKarpenterReadyCheck_Healthy(t *testing.T) {
	ncJSON, _ := json.Marshal(map[string]interface{}{"items": []map[string]interface{}{{"metadata": map[string]string{"name": "default"}}}})
	npJSON, _ := json.Marshal(map[string]interface{}{"items": []map[string]interface{}{
		{"metadata": map[string]string{"name": "default"}, "status": map[string]interface{}{"conditions": []map[string]string{{"type": "Ready", "status": "True"}}}},
	}})
	run := newMockRunner(
		mockCall{prefix: "kubectl --context test get ec2nodeclass", out: ncJSON},
		mockCall{prefix: "kubectl --context test get nodepool", out: npJSON},
	)
	check := &KarpenterReadyCheck{Name: "preprod/karpenter/ready", KubeContext: "test", Run: run}
	if r := check.Check(context.Background()); r.Status != "ok" {
		t.Errorf("expected ok, got %s: %s", r.Status, r.Message)
	}
}

func TestKarpenterReadyCheck_NoNodeClass(t *testing.T) {
	ncJSON, _ := json.Marshal(map[string]interface{}{"items": []interface{}{}})
	run := newMockRunner(mockCall{prefix: "kubectl --context test get ec2nodeclass", out: ncJSON})
	check := &KarpenterReadyCheck{Name: "preprod/karpenter/ready", KubeContext: "test", Run: run}
	r := check.Check(context.Background())
	if r.Status != "failed" || !strings.Contains(r.Message, "no EC2NodeClass") {
		t.Errorf("expected failed/no EC2NodeClass, got %s: %s", r.Status, r.Message)
	}
}

func TestKarpenterReadyCheck_NodePoolNotReady(t *testing.T) {
	ncJSON, _ := json.Marshal(map[string]interface{}{"items": []map[string]interface{}{{"metadata": map[string]string{"name": "default"}}}})
	npJSON, _ := json.Marshal(map[string]interface{}{"items": []map[string]interface{}{
		{"metadata": map[string]string{"name": "default"}, "status": map[string]interface{}{"conditions": []map[string]string{{"type": "Ready", "status": "False", "reason": "NodeClassNotReady"}}}},
	}})
	run := newMockRunner(
		mockCall{prefix: "kubectl --context test get ec2nodeclass", out: ncJSON},
		mockCall{prefix: "kubectl --context test get nodepool", out: npJSON},
	)
	check := &KarpenterReadyCheck{Name: "preprod/karpenter/ready", KubeContext: "test", Run: run}
	r := check.Check(context.Background())
	if r.Status != "failed" || !strings.Contains(r.Message, "not Ready") {
		t.Errorf("expected failed/not Ready, got %s: %s", r.Status, r.Message)
	}
}

// --- AdmissionBlockedCheck tests ---

func TestAdmissionBlockedCheck_Healthy(t *testing.T) {
	depsJSON, _ := json.Marshal(map[string]interface{}{"items": []map[string]interface{}{
		{"metadata": map[string]string{"name": "app", "namespace": "ns"}, "spec": map[string]interface{}{"replicas": 2}, "status": map[string]interface{}{"replicas": 2}},
	}})
	run := newMockRunner(mockCall{prefix: "kubectl --context test get deploy", out: depsJSON})
	check := &AdmissionBlockedCheck{Name: "preprod/policy/admission", KubeContext: "test", Run: run}
	if r := check.Check(context.Background()); r.Status != "ok" {
		t.Errorf("expected ok, got %s: %s", r.Status, r.Message)
	}
}

func TestAdmissionBlockedCheck_Blocked(t *testing.T) {
	depsJSON, _ := json.Marshal(map[string]interface{}{"items": []map[string]interface{}{
		{"metadata": map[string]string{"name": "app", "namespace": "alpha-shop-prod"}, "spec": map[string]interface{}{"replicas": 2}, "status": map[string]interface{}{}},
	}})
	run := newMockRunner(
		mockCall{prefix: "kubectl --context test get deploy", out: depsJSON},
		mockCall{prefix: "kubectl --context test get events", out: []byte(`admission webhook "mutate.kyverno.svc-fail" denied: ecr BatchGetImage denied`)},
	)
	check := &AdmissionBlockedCheck{Name: "preprod/policy/admission", KubeContext: "test", Run: run}
	r := check.Check(context.Background())
	if r.Status != "failed" {
		t.Fatalf("expected failed, got %s: %s", r.Status, r.Message)
	}
	joined := strings.Join(r.Details, " | ")
	if !strings.Contains(joined, "alpha-shop-prod/app") || !strings.Contains(joined, "BatchGetImage denied") {
		t.Errorf("expected blocked workload + admission error in details, got: %s", joined)
	}
}

// --- IAMCheck tests ---

func TestIAMCheck_AllValid(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "aws sts get-caller-identity", out: []byte(`{"Account":"123456"}`)},
		mockCall{prefix: "aws sts assume-role", out: []byte(`{"Credentials":{}}`)},
		mockCall{prefix: "aws s3api head-bucket", out: []byte("{}")},
	)

	check := &IAMCheck{
		Name:           "iam",
		Profiles:       []string{"management"},
		DefaultProfile: "management",
		Accounts: map[string]config.IAMAccountConfig{
			"platform": {ID: "123", DeployerRoleARN: "arn:aws:iam::123:role/PlatformDeployer"},
		},
		StateBucket: "my-bucket",
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "ok" {
		t.Errorf("expected ok, got %s: %s\nDetails: %v", result.Status, result.Message, result.Details)
	}
	if len(check.ExpiredProfiles) != 0 {
		t.Errorf("expected no expired profiles, got %v", check.ExpiredProfiles)
	}
}

func TestIAMCheck_ExpiredSession(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "aws sts get-caller-identity", out: []byte("token expired"), err: fmt.Errorf("exit 255")},
		mockCall{prefix: "aws sts assume-role", out: []byte(`{"Credentials":{}}`)},
		mockCall{prefix: "aws s3api head-bucket", out: []byte("{}")},
	)

	check := &IAMCheck{
		Name:           "iam",
		Profiles:       []string{"management"},
		DefaultProfile: "management",
		Accounts:       map[string]config.IAMAccountConfig{},
		StateBucket:    "my-bucket",
		Run:            run,
	}

	result := check.Check(context.Background())
	if result.Status != "failed" {
		t.Errorf("expected failed, got %s", result.Status)
	}
	if len(check.ExpiredProfiles) != 1 || check.ExpiredProfiles[0] != "management" {
		t.Errorf("expected expired profile 'management', got %v", check.ExpiredProfiles)
	}
}

// --- DNSDelegationCheck tests ---

func TestDNSDelegationCheck_AllMatch(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "dig", out: []byte("ns-1.awsdns.com.\nns-2.awsdns.net.\n")},
	)

	check := &DNSDelegationCheck{
		Name:       "dns",
		Zone:       "example.org",
		ExpectedNS: []string{"ns-1.awsdns.com.", "ns-2.awsdns.net."},
		Run:        run,
	}

	result := check.Check(context.Background())
	if result.Status != "ok" {
		t.Errorf("expected ok, got %s: %s\nDetails: %v", result.Status, result.Message, result.Details)
	}
}

func TestDNSDelegationCheck_MissingNS(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "dig", out: []byte("ns-1.awsdns.com.\n")},
	)

	check := &DNSDelegationCheck{
		Name:       "dns",
		Zone:       "example.org",
		ExpectedNS: []string{"ns-1.awsdns.com.", "ns-2.awsdns.net."},
		Run:        run,
	}

	result := check.Check(context.Background())
	if result.Status != "failed" {
		t.Errorf("expected failed, got %s", result.Status)
	}
	if !strings.Contains(result.Message, "1/2") {
		t.Errorf("expected '1/2' in message, got %q", result.Message)
	}
}

// --- EndpointCheck tests ---

func TestEndpointCheck_HTTP200(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "curl", out: []byte("HTTP/2 200 \r\ncontent-type: text/html\r\n")},
	)

	check := &EndpointCheck{
		Name: "argocd",
		URL:  "https://argocd.example.com/",
		Run:  run,
	}

	result := check.Check(context.Background())
	if result.Status != "ok" {
		t.Errorf("expected ok, got %s: %s", result.Status, result.Message)
	}
}

func TestEndpointCheck_HTTP500(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "curl", out: []byte("HTTP/1.1 500 Internal Server Error\r\n")},
	)

	check := &EndpointCheck{
		Name: "argocd",
		URL:  "https://argocd.example.com/",
		Run:  run,
	}

	result := check.Check(context.Background())
	if result.Status != "failed" {
		t.Errorf("expected failed, got %s", result.Status)
	}
	if !strings.Contains(result.Message, "500") {
		t.Errorf("expected '500' in message, got %q", result.Message)
	}
}

// --- TailscaleCheck tests ---

func TestTailscaleCheck_CliNotInstalled(t *testing.T) {
	origPath := TailscaleMacOSPath
	TailscaleMacOSPath = "/nonexistent/tailscale"
	t.Cleanup(func() { TailscaleMacOSPath = origPath })

	run := newMockRunner(
		mockCall{prefix: "which tailscale", err: fmt.Errorf("not found")},
	)

	check := &TailscaleCheck{
		Name:         "tailscale/platform",
		Env:          "platform",
		KubeContext:  "platform",
		ExpectedCIDR: "10.100.0.0/16",
		Run:          run,
	}

	result := check.Check(context.Background())
	if result.Status != "skipped" {
		t.Errorf("expected skipped, got %s: %s", result.Status, result.Message)
	}
}

// --- SecretStoreCheck tests ---

func TestSecretStoreCheck_AllReady(t *testing.T) {
	stores := map[string]interface{}{
		"items": []map[string]interface{}{
			{
				"metadata": map[string]string{"name": "aws-store"},
				"status": map[string]interface{}{
					"conditions": []map[string]string{
						{"type": "Ready", "status": "True"},
					},
				},
			},
		},
	}
	storesJSON, _ := json.Marshal(stores)

	run := newMockRunner(
		mockCall{prefix: "kubectl", out: storesJSON},
	)

	check := &SecretStoreCheck{
		Name:        "test/secret-stores",
		KubeContext: "test",
		Namespace:   "external-secrets",
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "ok" {
		t.Errorf("expected ok, got %s: %s", result.Status, result.Message)
	}
}

// --- ArgoCDAppCheck tests ---

func TestArgoCDAppCheck_AllSyncedHealthy(t *testing.T) {
	apps := map[string]interface{}{
		"items": []map[string]interface{}{
			{
				"metadata": map[string]string{"name": "preprod"},
				"status": map[string]interface{}{
					"sync":   map[string]string{"status": "Synced"},
					"health": map[string]string{"status": "Healthy"},
				},
			},
		},
	}
	appsJSON, _ := json.Marshal(apps)

	run := newMockRunner(
		mockCall{prefix: "kubectl", out: appsJSON},
	)

	check := &ArgoCDAppCheck{
		Name:        "test/argocd-apps",
		KubeContext: "test",
		Namespace:   "argocd",
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "ok" {
		t.Errorf("expected ok, got %s: %s", result.Status, result.Message)
	}
}

func TestArgoCDAppCheck_OutOfSync(t *testing.T) {
	apps := map[string]interface{}{
		"items": []map[string]interface{}{
			{
				"metadata": map[string]string{"name": "preprod"},
				"status": map[string]interface{}{
					"sync":   map[string]string{"status": "OutOfSync"},
					"health": map[string]string{"status": "Degraded"},
				},
			},
		},
	}
	appsJSON, _ := json.Marshal(apps)

	run := newMockRunner(
		mockCall{prefix: "kubectl", out: appsJSON},
	)

	check := &ArgoCDAppCheck{
		Name:        "test/argocd-apps",
		KubeContext: "test",
		Namespace:   "argocd",
		Run:         run,
	}

	result := check.Check(context.Background())
	if result.Status != "failed" {
		t.Errorf("expected failed, got %s", result.Status)
	}
}

// --- ResolveCheckers tests ---

func TestResolveCheckers_MapsUnitToCheckType(t *testing.T) {
	units := []*engine.Unit{
		{Name: "platform/eks", Path: "/tmp/eks", Auth: map[string]string{"profile": "management"}},
		{Name: "platform/cilium", Path: "/tmp/cilium", Auth: map[string]string{"profile": "management"}},
		{Name: "platform/cert-manager", Path: "/tmp/cert-manager", Auth: map[string]string{"profile": "management"}},
		{Name: "platform/argocd", Path: "/tmp/argocd", Auth: map[string]string{"profile": "management"}},
	}

	kubeCtx := map[string]string{"platform": "platform"}
	clusterName := map[string]string{"platform": "platform-use1-eks"}
	cfg := &config.ValidateConfig{}
	run := newMockRunner()

	checks := ResolveCheckers(units, kubeCtx, clusterName, map[string]string{"platform": "platform"}, cfg, run)

	// eks: StateCheck + EKSClusterCheck = 2
	// cilium: StateCheck + K8sWorkloadCheck = 2
	// cert-manager: StateCheck + K8sWorkloadCheck = 2
	// argocd: StateCheck + K8sWorkloadCheck + ArgoCDAppCheck = 3
	expected := 9
	if len(checks) != expected {
		t.Errorf("expected %d checks, got %d", expected, len(checks))
		for _, c := range checks {
			if nc, ok := c.(interface{ CheckName() string }); ok {
				t.Logf("  %s (%T)", nc.CheckName(), c)
			} else {
				t.Logf("  (%T)", c)
			}
		}
	}
}

func TestResolveCheckers_NoKubeContext_SkipsK8sChecks(t *testing.T) {
	units := []*engine.Unit{
		{Name: "platform/cilium", Path: "/tmp/cilium", Auth: map[string]string{"profile": "management"}},
	}

	// No kubecontext for platform
	kubeCtx := map[string]string{}
	clusterName := map[string]string{}
	cfg := &config.ValidateConfig{}
	run := newMockRunner()

	checks := ResolveCheckers(units, kubeCtx, clusterName, map[string]string{"platform": "platform"}, cfg, run)

	// cilium without kubecontext: only StateCheck
	if len(checks) != 1 {
		t.Errorf("expected 1 check (StateCheck only), got %d", len(checks))
		for _, c := range checks {
			if nc, ok := c.(interface{ CheckName() string }); ok {
				t.Logf("  %s (%T)", nc.CheckName(), c)
			} else {
				t.Logf("  (%T)", c)
			}
		}
	}
}

// --- vpcResolverIP tests ---

func TestVpcResolverIP(t *testing.T) {
	tests := []struct {
		cidr string
		env  string
		want string
	}{
		{"10.100.0.0/16", "platform", "10.100.0.2"},
		{"10.101.0.0/16", "preprod", "10.101.0.2"},
		{"172.16.0.0/12", "test", "172.16.0.2"},
	}

	for _, tt := range tests {
		cfg := &config.ValidateConfig{
			Tailscale: config.TailscaleValidation{
				VPCCIDRs: map[string]string{tt.env: tt.cidr},
			},
		}
		got := vpcResolverIP(cfg, tt.env)
		if got != tt.want {
			t.Errorf("vpcResolverIP(%s, %s) = %q, want %q", tt.cidr, tt.env, got, tt.want)
		}
	}
}

func TestVpcResolverIP_MissingEnv(t *testing.T) {
	cfg := &config.ValidateConfig{
		Tailscale: config.TailscaleValidation{
			VPCCIDRs: map[string]string{"platform": "10.100.0.0/16"},
		},
	}
	got := vpcResolverIP(cfg, "missing")
	if got != "" {
		t.Errorf("expected empty for missing env, got %q", got)
	}
}

// --- helper tests ---

func TestParseHTTPStatus(t *testing.T) {
	tests := []struct {
		input string
		want  int
	}{
		{"HTTP/2 200 \r\ncontent-type: text/html\r\n", 200},
		{"HTTP/1.1 302 Found\r\n", 302},
		{"HTTP/1.1 500 Internal Server Error\r\n", 500},
		{"garbage", 0},
	}

	for _, tt := range tests {
		got := parseHTTPStatus(tt.input)
		if got != tt.want {
			t.Errorf("parseHTTPStatus(%q) = %d, want %d", tt.input[:min(len(tt.input), 40)], got, tt.want)
		}
	}
}

func TestHostFromURL(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"https://argocd.aws.refplat.org/", "argocd.aws.refplat.org"},
		{"http://example.com:8080/path", "example.com"},
		{"example.com/path", "example.com"},
	}

	for _, tt := range tests {
		got := hostFromURL(tt.input)
		if got != tt.want {
			t.Errorf("hostFromURL(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestRoleNameFromARN(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"arn:aws:iam::123456789012:role/PlatformDeployer", "PlatformDeployer"},
		{"arn:aws:iam::123456789012:role/path/NestedRole", "NestedRole"},
		{"JustAName", "JustAName"},
	}

	for _, tt := range tests {
		got := roleNameFromARN(tt.input)
		if got != tt.want {
			t.Errorf("roleNameFromARN(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
