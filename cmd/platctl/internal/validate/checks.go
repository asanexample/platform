package validate

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/gangster/platform/cmd/platctl/internal/cloud"
	"github.com/gangster/platform/cmd/platctl/internal/config"
	"github.com/gangster/platform/cmd/platctl/internal/engine"
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

	env := os.Environ()
	if profile, ok := s.Unit.Auth["profile"]; ok {
		found := false
		prefix := "AWS_PROFILE="
		for i, e := range env {
			if strings.HasPrefix(e, prefix) {
				env[i] = prefix + profile
				found = true
				break
			}
		}
		if !found {
			env = append(env, prefix+profile)
		}
	}
	cmd.Env = env

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

// TGWAttachmentCheck validates that all Transit Gateway attachments are available.
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
		"--filters", fmt.Sprintf("Name=transit-gateway-id,Values=%s", t.TGWID),
		"--region", region,
		"--output", "json",
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
		State                     string `json:"State"`
		ResourceID                string `json:"ResourceId"`
		ResourceType              string `json:"ResourceType"`
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

	if len(resp.Attachments) == 0 {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "no TGW attachments found",
			Elapsed: elapsed,
		}
	}

	available := 0
	var notAvailable []string
	for _, att := range resp.Attachments {
		if att.State == "available" {
			available++
		} else {
			notAvailable = append(notAvailable,
				fmt.Sprintf("%s state=%s resource=%s (%s)",
					att.TransitGatewayAttachmentID, att.State, att.ResourceID, att.ResourceType))
		}
	}

	if len(notAvailable) > 0 {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d/%d attachments available", available, len(resp.Attachments)),
			Details: notAvailable,
			Elapsed: elapsed,
		}
	}

	return CheckResult{
		Name:    t.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d/%d attachments available", available, len(resp.Attachments)),
		Elapsed: elapsed,
	}
}

// ---------------------------------------------------------------------------
// CrossVPCDNSCheck — DNS resolution via VPC resolver
// ---------------------------------------------------------------------------

// CrossVPCDNSCheck validates that a DNS endpoint resolves via a specific resolver IP.
// The resolver IP is typically the VPC DNS resolver (VPC CIDR base + 2), reachable
// through Tailscale's subnet router.
type CrossVPCDNSCheck struct {
	Name       string
	Endpoint   string
	ResolverIP string
	Run        CommandRunner
}

// CheckName returns the check name for skip messages.
func (d *CrossVPCDNSCheck) CheckName() string { return d.Name }

// Check runs `dig ENDPOINT @RESOLVER_IP +short` and expects IP addresses.
func (d *CrossVPCDNSCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	out, err := d.Run(ctx, "dig", d.Endpoint, "@"+d.ResolverIP, "+short")
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
				fmt.Sprintf("dig %s @%s +short returned empty", d.Endpoint, d.ResolverIP),
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
// ResolveCheckers — builds Checker slices from discovered units and config
// ---------------------------------------------------------------------------

// ResolveCheckers maps discovered engine units to health-check implementations
// based on the unit's short name (the part after the "/").
func ResolveCheckers(
	units []*engine.Unit,
	kubeContextByEnv map[string]string,
	clusterNameByEnv map[string]string,
	clusterProfileByEnv map[string]string,
	cfg *config.ValidateConfig,
	run CommandRunner,
) []Checker {
	var checks []Checker

	for _, u := range units {
		// Extract short name: "platform/eks" → "eks"
		parts := strings.SplitN(u.Name, "/", 2)
		if len(parts) != 2 {
			continue
		}
		shortName := parts[1]
		env := parts[0]
		kubeCtx := kubeContextByEnv[env]

		switch shortName {
		case "eks":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if clusterName, ok := clusterNameByEnv[env]; ok && clusterName != "" {
				eksAuth := u.Auth
				if p, ok := clusterProfileByEnv[env]; ok && p != "" {
					eksAuth = map[string]string{"profile": p}
					for k, v := range u.Auth {
						if k != "profile" {
							eksAuth[k] = v
						}
					}
				}
				checks = append(checks, &EKSClusterCheck{
					Name:        u.Name + "/cluster",
					ClusterName: clusterName,
					KubeContext: kubeCtx,
					Auth:        eksAuth,
					Run:         run,
				})
			}

		case "cilium":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &K8sWorkloadCheck{
					Name:          u.Name + "/pods",
					KubeContext:   kubeCtx,
					Namespace:     "kube-system",
					LabelSelector: "k8s-app=cilium",
					Run:           run,
				})
			}

		case "node-groups":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "networking":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "iam-roles":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "ssm-bastion":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "eks-addons":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &K8sWorkloadCheck{
					Name:          u.Name + "/coredns",
					KubeContext:   kubeCtx,
					Namespace:     "kube-system",
					LabelSelector: "k8s-app=kube-dns",
					Run:           run,
				})
			}

		case "cert-manager":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &K8sWorkloadCheck{
					Name:        u.Name + "/pods",
					KubeContext: kubeCtx,
					Namespace:   "cert-manager",
					Run:         run,
				})
			}

		case "external-dns":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &K8sWorkloadCheck{
					Name:        u.Name + "/pods",
					KubeContext: kubeCtx,
					Namespace:   "external-dns",
					Run:         run,
				})
			}

		case "external-secrets":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &K8sWorkloadCheck{
					Name:        u.Name + "/pods",
					KubeContext: kubeCtx,
					Namespace:   "external-secrets",
					Run:         run,
				})
			}

		case "secret-stores":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &SecretStoreCheck{
					Name:        u.Name + "/status",
					KubeContext: kubeCtx,
					ClusterWide: true,
					Run:         run,
				})
			}

		case "argocd":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &K8sWorkloadCheck{
					Name:        u.Name + "/pods",
					KubeContext: kubeCtx,
					Namespace:   "argocd",
					Run:         run,
				})
				checks = append(checks, &ArgoCDAppCheck{
					Name:        u.Name + "/apps",
					KubeContext: kubeCtx,
					Run:         run,
				})
			}

		case "argocd-clusters":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "tailscale":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &K8sWorkloadCheck{
					Name:          u.Name + "/operator",
					KubeContext:   kubeCtx,
					Namespace:     "tailscale-system",
					LabelSelector: "app=operator",
					Run:           run,
				})
			}

		case "tailscale-admin":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "transit-gateway":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if cfg != nil && cfg.TransitGateway.ID != "" {
				tgwAuth := u.Auth
				if p, ok := clusterProfileByEnv[env]; ok && p != "" {
					tgwAuth = map[string]string{"profile": p}
					for k, v := range u.Auth {
						if k != "profile" {
							tgwAuth[k] = v
						}
					}
				}
				checks = append(checks, &TGWAttachmentCheck{
					Name:  u.Name + "/attachments",
					Auth:  tgwAuth,
					TGWID: cfg.TransitGateway.ID,
					Run:   run,
				})
			}

		case "cross-vpc-dns":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if cfg != nil && cfg.CrossVPCDNS.Endpoint != "" && kubeCtx != "" {
				// VPC DNS resolver: CIDR base + 2 (e.g., 10.100.0.2 for 10.100.0.0/16)
				resolverIP := vpcResolverIP(cfg, env)
				if resolverIP != "" {
					checks = append(checks, &CrossVPCDNSCheck{
						Name:       u.Name + "/dns",
						Endpoint:   cfg.CrossVPCDNS.Endpoint,
						ResolverIP: resolverIP,
						Run:        run,
					})
				}
			}

		case "gateway-config":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "route53":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "route53-delegation":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "ecr":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "github-oidc":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "tenants":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
			if kubeCtx != "" {
				checks = append(checks, &TenantCheck{
					Name:        u.Name + "/namespaces",
					KubeContext: kubeCtx,
					Run:         run,
				})
			}

		case "argocd-apps":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		case "cloudtrail":
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})

		default:
			// Unknown unit type — fall back to state check only
			checks = append(checks, &StateCheck{
				Name:   u.Name + "/state",
				Unit:   u,
				Binary: "terragrunt",
			})
		}
	}

	return checks
}

// vpcResolverIP derives the VPC DNS resolver IP from the tailscale VPC CIDR config.
// AWS VPC DNS resolver is always at CIDR base + 2 (e.g., 10.100.0.0/16 → 10.100.0.2).
func vpcResolverIP(cfg *config.ValidateConfig, env string) string {
	if cfg == nil || cfg.Tailscale.VPCCIDRs == nil {
		return ""
	}
	cidr, ok := cfg.Tailscale.VPCCIDRs[env]
	if !ok || cidr == "" {
		return ""
	}
	// Parse CIDR base: "10.100.0.0/16" → "10.100.0.0"
	base := cidr
	if idx := strings.Index(cidr, "/"); idx >= 0 {
		base = cidr[:idx]
	}
	parts := strings.Split(base, ".")
	if len(parts) != 4 {
		return ""
	}
	// Replace last octet with "2"
	parts[3] = "2"
	return strings.Join(parts, ".")
}
