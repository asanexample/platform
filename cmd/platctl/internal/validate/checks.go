package validate

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/asanexample/platform/cmd/platctl/internal/cloud"
	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// ---------------------------------------------------------------------------
// StateCheck — verifies a Terragrunt unit has resources in state
// ---------------------------------------------------------------------------

// StateCheck verifies that a Terragrunt unit has resources in its state file.
// Uses os/exec directly (like unitHasState in teardown.go) because the command
// requires Dir to be set to the unit's path.
type StateCheck struct {
	Name   string
	Unit   *engine.Unit
	Binary string // "terragrunt" or "tofu"
	// EmptyOK marks units whose empty state is intentional (e.g. mimir under the cost profile, a
	// gateway-config with no per-app routes on that cluster) — configured via validate.expected_empty_units.
	EmptyOK bool
}

// CheckName returns the check name for skip messages.
func (s *StateCheck) CheckName() string { return s.Name }

// Check runs `terragrunt state list` in the unit directory.
func (s *StateCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	binary := s.Binary
	if binary == "" {
		binary = "terragrunt"
	}

	cmd := exec.CommandContext(ctx, binary, "state", "list")
	cmd.Dir = s.Unit.Path
	cmd.Env = engine.EnvWithAWSProfile(os.Environ(), s.Unit.Auth)

	out, err := cmd.Output()
	elapsed := time.Since(start)

	if err != nil {
		return CheckResult{
			Name:    s.Name,
			Status:  "failed",
			Message: "could not read state",
			Details: []string{err.Error()},
			Elapsed: elapsed,
		}
	}

	lines := strings.TrimSpace(string(out))
	if lines == "" {
		if s.EmptyOK {
			return CheckResult{
				Name:    s.Name,
				Status:  "ok",
				Message: "state empty as expected (unit disabled in this profile)",
				Elapsed: elapsed,
			}
		}
		return CheckResult{
			Name:    s.Name,
			Status:  "failed",
			Message: "state is empty (no resources deployed)",
			Elapsed: elapsed,
		}
	}

	count := len(strings.Split(lines, "\n"))
	return CheckResult{
		Name:    s.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d resources in state", count),
		Elapsed: elapsed,
	}
}

// ---------------------------------------------------------------------------
// EKSClusterCheck — EKS cluster status and node readiness
// ---------------------------------------------------------------------------

// EKSClusterCheck validates that an EKS cluster is ACTIVE and its nodes are Ready.
type EKSClusterCheck struct {
	Name        string
	ClusterName string
	KubeContext string
	Auth        map[string]string
	Run         CommandRunner
}

// CheckName returns the check name for skip messages.
func (e *EKSClusterCheck) CheckName() string { return e.Name }

// Check queries EKS API for cluster status and kubectl for node readiness.
func (e *EKSClusterCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	region := cloud.RegionFromAuth(e.Auth)

	// Check cluster status via AWS CLI
	args := []string{
		"eks", "describe-cluster",
		"--name", e.ClusterName,
		"--region", region,
		"--query", "cluster.status",
		"--output", "text",
	}
	if profile, ok := e.Auth["profile"]; ok {
		args = append(args, "--profile", profile)
	}

	out, err := e.Run(ctx, "aws", args...)
	elapsed := time.Since(start)
	if err != nil {
		return CheckResult{
			Name:    e.Name,
			Status:  "failed",
			Message: "cannot reach EKS API",
			Details: []string{strings.TrimSpace(string(out))},
			Elapsed: elapsed,
		}
	}

	status := strings.TrimSpace(string(out))
	if status != "ACTIVE" {
		return CheckResult{
			Name:    e.Name,
			Status:  "failed",
			Message: fmt.Sprintf("cluster status: %s", status),
			Elapsed: elapsed,
		}
	}

	// Check node readiness via kubectl
	if e.KubeContext == "" {
		return CheckResult{
			Name:    e.Name,
			Status:  "ok",
			Message: fmt.Sprintf("ACTIVE (node check skipped — no kubecontext)"),
			Elapsed: time.Since(start),
		}
	}

	nodeOut, err := e.Run(ctx, "kubectl", "--context", e.KubeContext, "get", "nodes", "-o", "json")
	elapsed = time.Since(start)
	if err != nil {
		return CheckResult{
			Name:    e.Name,
			Status:  "failed",
			Message: "cluster ACTIVE but cannot list nodes",
			Details: []string{strings.TrimSpace(string(nodeOut)), "try: kubectl --context " + e.KubeContext + " get nodes"},
			Elapsed: elapsed,
		}
	}

	type nodeCondition struct {
		Type   string `json:"type"`
		Status string `json:"status"`
	}
	type nodeStatus struct {
		Conditions []nodeCondition `json:"conditions"`
	}
	type nodeMeta struct {
		Name string `json:"name"`
	}
	type nodeItem struct {
		Metadata nodeMeta   `json:"metadata"`
		Status   nodeStatus `json:"status"`
	}
	type nodeList struct {
		Items []nodeItem `json:"items"`
	}

	var nodes nodeList
	if err := json.Unmarshal(nodeOut, &nodes); err != nil {
		return CheckResult{
			Name:    e.Name,
			Status:  "failed",
			Message: "cluster ACTIVE but node JSON parse failed",
			Details: []string{err.Error()},
			Elapsed: elapsed,
		}
	}

	ready := 0
	var unhealthy []string
	for _, n := range nodes.Items {
		isReady := false
		for _, c := range n.Status.Conditions {
			if c.Type == "Ready" && c.Status == "True" {
				isReady = true
				break
			}
		}
		if isReady {
			ready++
		} else {
			unhealthy = append(unhealthy, n.Metadata.Name)
		}
	}

	if len(unhealthy) > 0 {
		details := make([]string, 0, len(unhealthy)+1)
		for _, name := range unhealthy {
			details = append(details, fmt.Sprintf("node %s not Ready", name))
		}
		details = append(details, "try: kubectl --context "+e.KubeContext+" describe node <name>")
		return CheckResult{
			Name:    e.Name,
			Status:  "failed",
			Message: fmt.Sprintf("ACTIVE, %d/%d nodes ready", ready, len(nodes.Items)),
			Details: details,
			Elapsed: elapsed,
		}
	}

	return CheckResult{
		Name:    e.Name,
		Status:  "ok",
		Message: fmt.Sprintf("ACTIVE, %d/%d nodes ready", ready, len(nodes.Items)),
		Elapsed: elapsed,
	}
}

// ---------------------------------------------------------------------------
// K8sWorkloadCheck — pod readiness for a namespace/label selector
// ---------------------------------------------------------------------------

// K8sWorkloadCheck validates that pods matching a namespace and optional label
// selector are Running and Ready.
type K8sWorkloadCheck struct {
	Name          string
	KubeContext   string
	Namespace     string
	LabelSelector string
	Run           CommandRunner
}

// CheckName returns the check name for skip messages.
func (k *K8sWorkloadCheck) CheckName() string { return k.Name }

// Check queries kubectl for pod status.
func (k *K8sWorkloadCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	args := []string{"--context", k.KubeContext, "get", "pods", "-n", k.Namespace, "-o", "json"}
	if k.LabelSelector != "" {
		args = append(args, "-l", k.LabelSelector)
	}

	out, err := k.Run(ctx, "kubectl", args...)
	elapsed := time.Since(start)
	if err != nil {
		return CheckResult{
			Name:    k.Name,
			Status:  "failed",
			Message: "cannot list pods",
			Details: []string{strings.TrimSpace(string(out))},
			Elapsed: elapsed,
		}
	}

	type containerStatus struct {
		Ready bool `json:"ready"`
	}
	type podCondition struct {
		Type   string `json:"type"`
		Status string `json:"status"`
	}
	type podStatusField struct {
		Phase             string            `json:"phase"`
		Reason            string            `json:"reason"`
		ContainerStatuses []containerStatus `json:"containerStatuses"`
		Conditions        []podCondition    `json:"conditions"`
	}
	type podMeta struct {
		Name string `json:"name"`
	}
	type podItem struct {
		Metadata podMeta        `json:"metadata"`
		Status   podStatusField `json:"status"`
	}
	type podList struct {
		Items []podItem `json:"items"`
	}

	var pods podList
	if err := json.Unmarshal(out, &pods); err != nil {
		return CheckResult{
			Name:    k.Name,
			Status:  "failed",
			Message: "pod JSON parse failed",
			Details: []string{err.Error()},
			Elapsed: elapsed,
		}
	}

	if len(pods.Items) == 0 {
		return CheckResult{
			Name:    k.Name,
			Status:  "failed",
			Message: "no pods found",
			Elapsed: elapsed,
		}
	}

	healthy := 0
	var unhealthy []string
	for _, p := range pods.Items {
		if p.Status.Phase == "Running" {
			allReady := true
			for _, cs := range p.Status.ContainerStatuses {
				if !cs.Ready {
					allReady = false
					break
				}
			}
			if allReady {
				healthy++
				continue
			}
		}
		reason := p.Status.Phase
		if p.Status.Reason != "" {
			reason = p.Status.Reason
		}
		unhealthy = append(unhealthy, fmt.Sprintf("%s (%s)", p.Metadata.Name, reason))
	}

	if len(unhealthy) > 0 {
		details := make([]string, 0, len(unhealthy)+1)
		details = append(details, unhealthy...)
		details = append(details, fmt.Sprintf("try: kubectl --context %s logs -n %s <pod>", k.KubeContext, k.Namespace))
		return CheckResult{
			Name:    k.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d/%d pods healthy", healthy, len(pods.Items)),
			Details: details,
			Elapsed: elapsed,
		}
	}

	return CheckResult{
		Name:    k.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d/%d pods healthy", healthy, len(pods.Items)),
		Elapsed: elapsed,
	}
}

// ---------------------------------------------------------------------------
// SecretStoreCheck — ExternalSecrets SecretStore readiness
// ---------------------------------------------------------------------------

// SecretStoreCheck validates that SecretStore or ClusterSecretStore resources are Ready.
type SecretStoreCheck struct {
	Name        string
	KubeContext string
	Namespace   string
	ClusterWide bool
	Run         CommandRunner
}

// CheckName returns the check name for skip messages.
func (s *SecretStoreCheck) CheckName() string { return s.Name }

// Check queries kubectl for SecretStore status.
func (s *SecretStoreCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	resource := "secretstore"
	args := []string{"--context", s.KubeContext, "get"}
	if s.ClusterWide {
		resource = "clustersecretstore"
		args = append(args, resource, "-o", "json")
	} else {
		args = append(args, resource, "-n", s.Namespace, "-o", "json")
	}
	out, err := s.Run(ctx, "kubectl", args...)
	elapsed := time.Since(start)
	if err != nil {
		return CheckResult{
			Name:    s.Name,
			Status:  "failed",
			Message: fmt.Sprintf("cannot list %s", resource),
			Details: []string{strings.TrimSpace(string(out))},
			Elapsed: elapsed,
		}
	}

	type storeCondition struct {
		Type    string `json:"type"`
		Status  string `json:"status"`
		Message string `json:"message"`
	}
	type storeStatus struct {
		Conditions []storeCondition `json:"conditions"`
	}
	type storeMeta struct {
		Name string `json:"name"`
	}
	type storeItem struct {
		Metadata storeMeta   `json:"metadata"`
		Status   storeStatus `json:"status"`
	}
	type storeList struct {
		Items []storeItem `json:"items"`
	}

	var stores storeList
	if err := json.Unmarshal(out, &stores); err != nil {
		return CheckResult{
			Name:    s.Name,
			Status:  "failed",
			Message: "SecretStore JSON parse failed",
			Details: []string{err.Error()},
			Elapsed: elapsed,
		}
	}

	if len(stores.Items) == 0 {
		return CheckResult{
			Name:    s.Name,
			Status:  "failed",
			Message: "no SecretStores found",
			Elapsed: elapsed,
		}
	}

	ready := 0
	var notReady []string
	for _, st := range stores.Items {
		isReady := false
		var msg string
		for _, c := range st.Status.Conditions {
			if c.Type == "Ready" {
				if c.Status == "True" {
					isReady = true
				}
				msg = c.Message
				break
			}
		}
		if isReady {
			ready++
		} else {
			detail := st.Metadata.Name
			if msg != "" {
				detail += ": " + msg
			}
			notReady = append(notReady, detail)
		}
	}

	if len(notReady) > 0 {
		return CheckResult{
			Name:    s.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d/%d SecretStores ready", ready, len(stores.Items)),
			Details: notReady,
			Elapsed: elapsed,
		}
	}

	return CheckResult{
		Name:    s.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d/%d SecretStores ready", ready, len(stores.Items)),
		Elapsed: elapsed,
	}
}

// ---------------------------------------------------------------------------
// ArgoCDAppCheck — ArgoCD application sync and health
// ---------------------------------------------------------------------------

// ArgoCDAppCheck validates that ArgoCD applications are synced and healthy.
type ArgoCDAppCheck struct {
	Name        string
	KubeContext string
	Namespace   string
	Run         CommandRunner
}

// CheckName returns the check name for skip messages.
func (a *ArgoCDAppCheck) CheckName() string { return a.Name }

// Check queries kubectl for ArgoCD Application resources.
func (a *ArgoCDAppCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	ns := a.Namespace
	if ns == "" {
		ns = "argocd"
	}
	out, err := a.Run(ctx, "kubectl", "--context", a.KubeContext,
		"get", "applications.argoproj.io", "-n", ns, "-o", "json")
	elapsed := time.Since(start)
	if err != nil {
		return CheckResult{
			Name:    a.Name,
			Status:  "failed",
			Message: "cannot list ArgoCD applications",
			Details: []string{strings.TrimSpace(string(out))},
			Elapsed: elapsed,
		}
	}

	type appSyncStatus struct {
		Status string `json:"status"`
	}
	type appHealthStatus struct {
		Status string `json:"status"`
	}
	type appOpStatus struct {
		Sync   appSyncStatus   `json:"sync"`
		Health appHealthStatus `json:"health"`
	}
	type appMeta struct {
		Name string `json:"name"`
	}
	type appItem struct {
		Metadata appMeta     `json:"metadata"`
		Status   appOpStatus `json:"status"`
	}
	type appList struct {
		Items []appItem `json:"items"`
	}

	var apps appList
	if err := json.Unmarshal(out, &apps); err != nil {
		return CheckResult{
			Name:    a.Name,
			Status:  "failed",
			Message: "ArgoCD application JSON parse failed",
			Details: []string{err.Error()},
			Elapsed: elapsed,
		}
	}

	if len(apps.Items) == 0 {
		return CheckResult{
			Name:    a.Name,
			Status:  "ok",
			Message: "no applications deployed",
			Elapsed: elapsed,
		}
	}

	healthy := 0
	var unhealthy []string
	for _, app := range apps.Items {
		synced := app.Status.Sync.Status == "Synced"
		healthOK := app.Status.Health.Status == "Healthy"
		if synced && healthOK {
			healthy++
		} else {
			unhealthy = append(unhealthy,
				fmt.Sprintf("%s (sync=%s, health=%s)",
					app.Metadata.Name, app.Status.Sync.Status, app.Status.Health.Status))
		}
	}

	if len(unhealthy) > 0 {
		return CheckResult{
			Name:    a.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d/%d apps synced+healthy", healthy, len(apps.Items)),
			Details: unhealthy,
			Elapsed: elapsed,
		}
	}

	return CheckResult{
		Name:    a.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d/%d apps synced+healthy", healthy, len(apps.Items)),
		Elapsed: elapsed,
	}
}

// ---------------------------------------------------------------------------
// TGWAttachmentCheck — Transit Gateway attachment state
// ---------------------------------------------------------------------------

// TGWAttachmentCheck validates that all Transit Gateway attachments are available. The TGW ID is DISCOVERED
// when not configured (the ID churns on every rebuild, so hardcoding it in .platctl.yaml yields a check that
// silently goes stale — the placeholder-config failure mode); validate.transit_gateway.id remains an optional
// override for accounts with multiple TGWs.
type TGWAttachmentCheck struct {
	Name  string
	Auth  map[string]string
	TGWID string
	Run   CommandRunner
}

// CheckName returns the check name for skip messages.
func (t *TGWAttachmentCheck) CheckName() string { return t.Name }

// Check queries the AWS API for TGW attachment states.
func (t *TGWAttachmentCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	region := cloud.RegionFromAuth(t.Auth)

	args := []string{
		"ec2", "describe-transit-gateway-attachments",
		"--region", region,
		"--output", "json",
	}
	// Scope to a specific TGW only when configured; otherwise validate every attachment visible in the
	// account/region (the hub account has exactly the platform TGW; spokes see the RAM share).
	if t.TGWID != "" {
		args = append(args, "--filters", fmt.Sprintf("Name=transit-gateway-id,Values=%s", t.TGWID))
	}
	if profile, ok := t.Auth["profile"]; ok {
		args = append(args, "--profile", profile)
	}

	out, err := t.Run(ctx, "aws", args...)
	elapsed := time.Since(start)
	if err != nil {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "cannot describe TGW attachments",
			Details: []string{strings.TrimSpace(string(out))},
			Elapsed: elapsed,
		}
	}

	type tgwAttachment struct {
		TransitGatewayAttachmentID string `json:"TransitGatewayAttachmentId"`
		State                      string `json:"State"`
		ResourceID                 string `json:"ResourceId"`
		ResourceType               string `json:"ResourceType"`
	}
	type tgwResponse struct {
		Attachments []tgwAttachment `json:"TransitGatewayAttachments"`
	}

	var resp tgwResponse
	if err := json.Unmarshal(out, &resp); err != nil {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "TGW attachment JSON parse failed",
			Details: []string{err.Error()},
			Elapsed: elapsed,
		}
	}

	// Skip tombstones: recently-deleted attachments linger in the API with State=deleted/deleting (e.g. from
	// the previous teardown) and are not a health signal for the current build.
	available := 0
	total := 0
	var notAvailable []string
	for _, att := range resp.Attachments {
		if att.State == "deleted" || att.State == "deleting" {
			continue
		}
		total++
		if att.State == "available" {
			available++
		} else {
			notAvailable = append(notAvailable,
				fmt.Sprintf("%s state=%s resource=%s (%s)",
					att.TransitGatewayAttachmentID, att.State, att.ResourceID, att.ResourceType))
		}
	}

	if total == 0 {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "no TGW attachments found",
			Elapsed: elapsed,
		}
	}

	if len(notAvailable) > 0 {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d/%d attachments available", available, total),
			Details: notAvailable,
			Elapsed: elapsed,
		}
	}

	return CheckResult{
		Name:    t.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d/%d attachments available", available, total),
		Elapsed: elapsed,
	}
}

// ---------------------------------------------------------------------------
// CrossVPCDNSCheck — DNS resolution via VPC resolver
// ---------------------------------------------------------------------------

// CrossVPCDNSCheck validates that a DNS endpoint resolves via a specific resolver IP.
// The resolver IP is typically the VPC DNS resolver (VPC CIDR base + 2), reachable
// through Tailscale's subnet router. The endpoint is DISCOVERED from the remote EKS cluster when not
// configured (the endpoint hostname churns on every rebuild — hardcoding it is the placeholder-config
// failure mode that neutered this check while the cross-vpc-dns PHZ was actually stale).
type CrossVPCDNSCheck struct {
	Name       string
	Endpoint   string // optional override; discovered from ClusterName when empty
	ResolverIP string
	// ClusterName + Auth locate the remote EKS cluster whose API endpoint the PHZ must resolve.
	ClusterName string
	Auth        map[string]string
	Run         CommandRunner
}

// CheckName returns the check name for skip messages.
func (d *CrossVPCDNSCheck) CheckName() string { return d.Name }

// Check resolves the endpoint (discovering it from EKS when unset) via the VPC resolver.
func (d *CrossVPCDNSCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	endpoint := d.Endpoint
	if endpoint == "" {
		args := []string{
			"eks", "describe-cluster",
			"--name", d.ClusterName,
			"--region", cloud.RegionFromAuth(d.Auth),
			"--query", "cluster.endpoint",
			"--output", "text",
		}
		if profile, ok := d.Auth["profile"]; ok {
			args = append(args, "--profile", profile)
		}
		out, err := d.Run(ctx, "aws", args...)
		if err != nil {
			return CheckResult{
				Name:    d.Name,
				Status:  "failed",
				Message: fmt.Sprintf("cannot discover EKS endpoint for %s", d.ClusterName),
				Details: []string{strings.TrimSpace(string(out))},
				Elapsed: time.Since(start),
			}
		}
		endpoint = strings.TrimPrefix(strings.TrimSpace(string(out)), "https://")
		if endpoint == "" {
			return CheckResult{
				Name:    d.Name,
				Status:  "failed",
				Message: fmt.Sprintf("empty EKS endpoint for %s", d.ClusterName),
				Elapsed: time.Since(start),
			}
		}
	}

	out, err := d.Run(ctx, "dig", endpoint, "@"+d.ResolverIP, "+short")
	elapsed := time.Since(start)

	output := strings.TrimSpace(string(out))
	if err != nil {
		return CheckResult{
			Name:    d.Name,
			Status:  "failed",
			Message: "dig command failed",
			Details: []string{output},
			Elapsed: elapsed,
		}
	}

	if output == "" {
		return CheckResult{
			Name:    d.Name,
			Status:  "failed",
			Message: "no DNS records returned",
			Details: []string{
				fmt.Sprintf("dig %s @%s +short returned empty", endpoint, d.ResolverIP),
				"check PHZ records and VPC association",
			},
			Elapsed: elapsed,
		}
	}

	ips := strings.Split(output, "\n")
	return CheckResult{
		Name:    d.Name,
		Status:  "ok",
		Message: fmt.Sprintf("resolves to %s", strings.Join(ips, ", ")),
		Elapsed: elapsed,
	}
}

// ---------------------------------------------------------------------------
// KarpenterReadyCheck — EC2NodeClass present + every NodePool Ready=True
// ---------------------------------------------------------------------------

// KarpenterReadyCheck verifies Karpenter can actually provision capacity: at least one EC2NodeClass exists and
// every NodePool reports Ready=True. The node/pod checks MISS a broken NodePool — a NodeClassReady=False NodePool
// has no nodes to be unready and the system node is fine, yet every workload pod stays Pending. (2026-06-27 unpark:
// `down` deleted the NodePool but left the EC2NodeClass; `up`'s force-replace lost the leftover finalizer'd
// NodeClass → NodePool NodeClassReady=False, all workloads stranded.)
type KarpenterReadyCheck struct {
	Name        string
	KubeContext string
	Run         CommandRunner
}

// CheckName returns the check name for skip messages.
func (k *KarpenterReadyCheck) CheckName() string { return k.Name }

// Check asserts an EC2NodeClass exists and every NodePool is Ready=True.
func (k *KarpenterReadyCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	ncOut, err := k.Run(ctx, "kubectl", "--context", k.KubeContext, "get", "ec2nodeclass", "-o", "json")
	if err != nil {
		if strings.Contains(string(ncOut), "doesn't have a resource type") {
			return CheckResult{Name: k.Name, Status: "skipped", Message: "Karpenter not installed (no EC2NodeClass CRD)", Elapsed: time.Since(start)}
		}
		return CheckResult{Name: k.Name, Status: "failed", Message: "cannot list EC2NodeClass",
			Details: []string{strings.TrimSpace(string(ncOut)), "try: kubectl --context " + k.KubeContext + " get ec2nodeclass"}, Elapsed: time.Since(start)}
	}
	var nc struct {
		Items []json.RawMessage `json:"items"`
	}
	if err := json.Unmarshal(ncOut, &nc); err != nil {
		return CheckResult{Name: k.Name, Status: "failed", Message: "EC2NodeClass JSON parse failed", Details: []string{err.Error()}, Elapsed: time.Since(start)}
	}
	if len(nc.Items) == 0 {
		return CheckResult{Name: k.Name, Status: "failed", Message: "no EC2NodeClass — Karpenter cannot provision; workloads strand Pending",
			Details: []string{"recover: helm get manifest karpenter-nodepool -n karpenter | kubectl apply -f -"}, Elapsed: time.Since(start)}
	}

	npOut, err := k.Run(ctx, "kubectl", "--context", k.KubeContext, "get", "nodepool", "-o", "json")
	if err != nil {
		return CheckResult{Name: k.Name, Status: "failed", Message: "cannot list NodePool", Details: []string{strings.TrimSpace(string(npOut))}, Elapsed: time.Since(start)}
	}
	var np struct {
		Items []struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
			Status struct {
				Conditions []struct {
					Type   string `json:"type"`
					Status string `json:"status"`
					Reason string `json:"reason"`
				} `json:"conditions"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := json.Unmarshal(npOut, &np); err != nil {
		return CheckResult{Name: k.Name, Status: "failed", Message: "NodePool JSON parse failed", Details: []string{err.Error()}, Elapsed: time.Since(start)}
	}
	if len(np.Items) == 0 {
		return CheckResult{Name: k.Name, Status: "failed", Message: "no NodePool present — Karpenter cannot provision", Elapsed: time.Since(start)}
	}

	var notReady []string
	for _, p := range np.Items {
		status, reason := "", ""
		for _, c := range p.Status.Conditions {
			if c.Type == "Ready" {
				status, reason = c.Status, c.Reason
				break
			}
		}
		if status != "True" {
			notReady = append(notReady, fmt.Sprintf("NodePool %s Ready=%q (%s)", p.Metadata.Name, status, reason))
		}
	}
	if len(notReady) > 0 {
		details := append(notReady,
			"a NodeClassReady=False NodePool provisions nothing — every workload pod stays Pending",
			"recover: helm get manifest karpenter-nodepool -n karpenter | kubectl apply -f -")
		return CheckResult{Name: k.Name, Status: "failed", Message: fmt.Sprintf("%d/%d NodePool(s) not Ready", len(notReady), len(np.Items)), Details: details, Elapsed: time.Since(start)}
	}
	return CheckResult{Name: k.Name, Status: "ok", Message: fmt.Sprintf("%d EC2NodeClass, %d NodePool(s) Ready", len(nc.Items), len(np.Items)), Elapsed: time.Since(start)}
}

// ---------------------------------------------------------------------------
// AdmissionBlockedCheck — Deployments that want pods but have none (admission)
// ---------------------------------------------------------------------------

// AdmissionBlockedCheck flags Deployments that want pods (spec.replicas>0) but have NONE (status.replicas 0/absent)
// — the signature of a fail-closed admission webhook (e.g. Kyverno) rejecting every pod. The pod-health checks miss
// this: a Deployment with zero pods has nothing unhealthy to report. It surfaces the latest FailedCreate admission
// error so the cause is diagnosable. (2026-06-27: an account-less kyverno-ecr ARN failed verify-images closed,
// blocking every product workload's admission post-unpark — with no node/pod symptom to see.)
type AdmissionBlockedCheck struct {
	Name        string
	KubeContext string
	Run         CommandRunner
}

// CheckName returns the check name for skip messages.
func (a *AdmissionBlockedCheck) CheckName() string { return a.Name }

// Check flags Deployments that want pods but have none and surfaces the admission error.
func (a *AdmissionBlockedCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	out, err := a.Run(ctx, "kubectl", "--context", a.KubeContext, "get", "deploy", "--all-namespaces", "-o", "json")
	if err != nil {
		return CheckResult{Name: a.Name, Status: "failed", Message: "cannot list deployments", Details: []string{strings.TrimSpace(string(out))}, Elapsed: time.Since(start)}
	}
	var deps struct {
		Items []struct {
			Metadata struct {
				Name      string `json:"name"`
				Namespace string `json:"namespace"`
			} `json:"metadata"`
			Spec struct {
				Replicas *int `json:"replicas"`
			} `json:"spec"`
			Status struct {
				Replicas int `json:"replicas"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := json.Unmarshal(out, &deps); err != nil {
		return CheckResult{Name: a.Name, Status: "failed", Message: "deployment JSON parse failed", Details: []string{err.Error()}, Elapsed: time.Since(start)}
	}

	var blocked []string
	firstNS := ""
	for _, d := range deps.Items {
		want := 1
		if d.Spec.Replicas != nil {
			want = *d.Spec.Replicas
		}
		if want > 0 && d.Status.Replicas == 0 {
			blocked = append(blocked, d.Metadata.Namespace+"/"+d.Metadata.Name)
			if firstNS == "" {
				firstNS = d.Metadata.Namespace
			}
		}
	}
	if len(blocked) == 0 {
		return CheckResult{Name: a.Name, Status: "ok", Message: "no admission-blocked workloads", Elapsed: time.Since(start)}
	}

	details := make([]string, 0, len(blocked)+1)
	for _, b := range blocked {
		details = append(details, b+" wants pods but has none")
	}
	if msg := a.latestFailedCreate(ctx, firstNS); msg != "" {
		details = append(details, "admission error ("+firstNS+"): "+msg)
	}
	return CheckResult{Name: a.Name, Status: "failed",
		Message: fmt.Sprintf("%d workload(s) blocked from creating pods (fail-closed admission webhook?)", len(blocked)),
		Details: details, Elapsed: time.Since(start)}
}

// latestFailedCreate returns the most recent ReplicaSet FailedCreate event message in a namespace — the admission
// rejection explaining why a Deployment can't create pods.
func (a *AdmissionBlockedCheck) latestFailedCreate(ctx context.Context, ns string) string {
	out, err := a.Run(ctx, "kubectl", "--context", a.KubeContext, "get", "events", "-n", ns,
		"--field-selector", "reason=FailedCreate", "--sort-by=.lastTimestamp", "-o", "jsonpath={.items[-1:].message}")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
