package validate

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// TenantCheck validates that tenant namespaces exist and have expected resources.
type TenantCheck struct {
	Name        string
	KubeContext string
	Run         CommandRunner
}

// CheckName returns the check name for skip messages.
func (t *TenantCheck) CheckName() string { return t.Name }

// Check verifies tenant namespaces (team-* and vc-*) have expected resources.
func (t *TenantCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	out, err := t.Run(ctx, "kubectl", "--context", t.KubeContext,
		"get", "namespaces", "-o", "json")
	elapsed := time.Since(start)
	if err != nil {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "cannot list namespaces",
			Details: []string{strings.TrimSpace(string(out))},
			Elapsed: elapsed,
		}
	}

	type nsMeta struct {
		Name   string            `json:"name"`
		Labels map[string]string `json:"labels"`
	}
	type nsItem struct {
		Metadata nsMeta `json:"metadata"`
	}
	type nsList struct {
		Items []nsItem `json:"items"`
	}

	var namespaces nsList
	if err := json.Unmarshal(out, &namespaces); err != nil {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "namespace JSON parse failed",
			Details: []string{err.Error()},
			Elapsed: elapsed,
		}
	}

	var nsMode, vcMode int
	var details []string

	for _, ns := range namespaces.Items {
		name := ns.Metadata.Name
		if strings.HasPrefix(name, "team-") {
			nsMode++
			if err := t.checkNamespaceResources(ctx, name); err != nil {
				details = append(details, fmt.Sprintf("%s: %s", name, err))
			}
		} else if strings.HasPrefix(name, "vc-") {
			vcMode++
			if err := t.checkVClusterPods(ctx, name); err != nil {
				details = append(details, fmt.Sprintf("%s: %s", name, err))
			}
		}
	}

	if nsMode == 0 && vcMode == 0 {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "no tenant namespaces found (team-* or vc-*)",
			Elapsed: time.Since(start),
		}
	}

	if len(details) > 0 {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d namespace-mode + %d vcluster-mode tenants (issues found)", nsMode, vcMode),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	return CheckResult{
		Name:    t.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d namespace-mode + %d vcluster-mode tenants healthy", nsMode, vcMode),
		Elapsed: time.Since(start),
	}
}

func (t *TenantCheck) checkNamespaceResources(ctx context.Context, namespace string) error {
	out, err := t.Run(ctx, "kubectl", "--context", t.KubeContext,
		"get", "resourcequota,networkpolicy", "-n", namespace, "-o", "name")
	if err != nil {
		return fmt.Errorf("cannot list resources")
	}

	output := strings.TrimSpace(string(out))
	hasQuota := strings.Contains(output, "resourcequota/")
	hasNetpol := strings.Contains(output, "networkpolicy/")

	if !hasQuota || !hasNetpol {
		var missing []string
		if !hasQuota {
			missing = append(missing, "ResourceQuota")
		}
		if !hasNetpol {
			missing = append(missing, "NetworkPolicy")
		}
		return fmt.Errorf("missing %s", strings.Join(missing, ", "))
	}
	return nil
}

func (t *TenantCheck) checkVClusterPods(ctx context.Context, namespace string) error {
	out, err := t.Run(ctx, "kubectl", "--context", t.KubeContext,
		"get", "pods", "-n", namespace, "-o", "json")
	if err != nil {
		return fmt.Errorf("cannot list pods")
	}

	type containerStatus struct {
		Ready bool `json:"ready"`
	}
	type podStatusField struct {
		Phase             string            `json:"phase"`
		ContainerStatuses []containerStatus `json:"containerStatuses"`
	}
	type podItem struct {
		Status podStatusField `json:"status"`
	}
	type podList struct {
		Items []podItem `json:"items"`
	}

	var pods podList
	if err := json.Unmarshal(out, &pods); err != nil {
		return fmt.Errorf("pod JSON parse failed")
	}

	if len(pods.Items) == 0 {
		return fmt.Errorf("no pods found")
	}

	for _, p := range pods.Items {
		if p.Status.Phase != "Running" {
			return fmt.Errorf("pod not running (phase: %s)", p.Status.Phase)
		}
		for _, cs := range p.Status.ContainerStatuses {
			if !cs.Ready {
				return fmt.Errorf("container not ready")
			}
		}
	}
	return nil
}
