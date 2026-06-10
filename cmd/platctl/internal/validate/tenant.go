package validate

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// TenantCheck validates the v2 Tenant API control plane (ADR-049): every XTenant claim is Synced+Ready, its
// namespace (<team>-<name>-<env>, Composition v2) exists with the tenant baseline (quota, NetworkPolicy,
// CiliumNetworkPolicy), and its owning Team CR is projected. Skips gracefully on clusters without the tenant
// API (the XTenant CRD is Crossplane-generated and only exists where enable_tenant_api is on), so it can be
// wired for every crossplane unit without per-env special-casing.
type TenantCheck struct {
	Name        string
	KubeContext string
	Run         CommandRunner
}

// CheckName returns the check name for skip messages.
func (t *TenantCheck) CheckName() string { return t.Name }

type xtenantCondition struct {
	Type   string `json:"type"`
	Status string `json:"status"`
	Reason string `json:"reason"`
}

type xtenantItem struct {
	Metadata struct {
		Name string `json:"name"`
	} `json:"metadata"`
	Spec struct {
		Team        string `json:"team"`
		Name        string `json:"name"`
		Environment string `json:"environment"`
	} `json:"spec"`
	Status struct {
		Conditions []xtenantCondition `json:"conditions"`
	} `json:"status"`
}

// Check lists the XTenant claims and verifies each is fully reconciled and its footprint exists.
func (t *TenantCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()

	out, err := t.Run(ctx, "kubectl", "--context", t.KubeContext,
		"get", "xtenants.platform.refplat.org", "-o", "json")
	if err != nil {
		msg := strings.TrimSpace(string(out))
		// No XTenant CRD => no tenant control plane on this cluster (e.g. the platform cluster). Not a failure.
		if strings.Contains(msg, "doesn't have a resource type") || strings.Contains(msg, "the server could not find the requested resource") {
			return CheckResult{
				Name:    t.Name,
				Status:  "ok",
				Message: "no tenant API on this cluster (skipped)",
				Elapsed: time.Since(start),
			}
		}
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "cannot list XTenants",
			Details: []string{msg},
			Elapsed: time.Since(start),
		}
	}

	var tenants struct {
		Items []xtenantItem `json:"items"`
	}
	if err := json.Unmarshal(out, &tenants); err != nil {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "XTenant JSON parse failed",
			Details: []string{err.Error()},
			Elapsed: time.Since(start),
		}
	}

	if len(tenants.Items) == 0 {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "tenant API present but no XTenant claims — tenant-claims sync missing?",
			Elapsed: time.Since(start),
		}
	}

	teams, teamsErr := t.projectedTeams(ctx)

	var details []string
	ready := 0
	for _, x := range tenants.Items {
		name := x.Metadata.Name
		if c := findCondition(x.Status.Conditions, "Synced"); c == nil || c.Status != "True" {
			details = append(details, fmt.Sprintf("%s: not Synced (%s)", name, xtenantConditionReason(x.Status.Conditions, "Synced")))
			continue
		}
		if c := findCondition(x.Status.Conditions, "Ready"); c == nil || c.Status != "True" {
			details = append(details, fmt.Sprintf("%s: not Ready (%s)", name, xtenantConditionReason(x.Status.Conditions, "Ready")))
			continue
		}
		ready++

		// Composition v2 namespace: <team>-<name>-<env>.
		ns := fmt.Sprintf("%s-%s-%s", x.Spec.Team, x.Spec.Name, x.Spec.Environment)
		if err := t.checkNamespaceResources(ctx, ns); err != nil {
			details = append(details, fmt.Sprintf("%s: namespace %s: %s", name, ns, err))
		}

		if teamsErr == nil {
			if _, ok := teams[x.Spec.Team]; !ok {
				details = append(details, fmt.Sprintf("%s: Team CR %q not projected (envelope unknown to Kyverno)", name, x.Spec.Team))
			}
		}
	}
	if teamsErr != nil {
		details = append(details, fmt.Sprintf("cannot list Team CRs: %v", teamsErr))
	}

	if len(details) > 0 {
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d/%d tenants Ready (issues found)", ready, len(tenants.Items)),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	return CheckResult{
		Name:    t.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d/%d tenants Synced+Ready (namespaces, baseline policies, Team CRs)", ready, len(tenants.Items)),
		Elapsed: time.Since(start),
	}
}

// projectedTeams returns the set of Team CR names on the cluster (the envelope admission inputs).
func (t *TenantCheck) projectedTeams(ctx context.Context) (map[string]bool, error) {
	out, err := t.Run(ctx, "kubectl", "--context", t.KubeContext,
		"get", "teams.platform.refplat.org", "-o", "name")
	if err != nil {
		return nil, fmt.Errorf("%s", strings.TrimSpace(string(out)))
	}
	teams := make(map[string]bool)
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if name := strings.TrimPrefix(line, "team.platform.refplat.org/"); name != "" && name != line {
			teams[name] = true
		}
	}
	return teams, nil
}

// anyLineHasKind reports whether any `-o name` output line is of the given kind — matching either the bare
// core form ("resourcequota/x") or the group-qualified form ("networkpolicy.networking.k8s.io/x").
func anyLineHasKind(output, kind string) bool {
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, kind+"/") || strings.HasPrefix(line, kind+".") {
			return true
		}
	}
	return false
}

func findCondition(conds []xtenantCondition, typ string) *xtenantCondition {
	for i := range conds {
		if conds[i].Type == typ {
			return &conds[i]
		}
	}
	return nil
}

func xtenantConditionReason(conds []xtenantCondition, typ string) string {
	if c := findCondition(conds, typ); c != nil && c.Reason != "" {
		return c.Reason
	}
	return "no condition"
}

func (t *TenantCheck) checkNamespaceResources(ctx context.Context, namespace string) error {
	out, err := t.Run(ctx, "kubectl", "--context", t.KubeContext,
		"get", "resourcequota,networkpolicy", "-n", namespace, "-o", "name")
	if err != nil {
		return fmt.Errorf("cannot list resources (namespace missing?)")
	}

	// `kubectl get -o name` prints group-qualified names for non-core kinds (networkpolicy.networking.k8s.io/x,
	// ciliumnetworkpolicy.cilium.io/y), so match on the kind PREFIX per line, not "kind/".
	hasQuota := anyLineHasKind(string(out), "resourcequota")
	hasNetpol := anyLineHasKind(string(out), "networkpolicy")

	cnpOut, cnpErr := t.Run(ctx, "kubectl", "--context", t.KubeContext,
		"get", "ciliumnetworkpolicy", "-n", namespace, "-o", "name")
	hasCNP := cnpErr == nil && anyLineHasKind(string(cnpOut), "ciliumnetworkpolicy")

	if !hasQuota || !hasNetpol || !hasCNP {
		var missing []string
		if !hasQuota {
			missing = append(missing, "ResourceQuota")
		}
		if !hasNetpol {
			missing = append(missing, "NetworkPolicy")
		}
		if !hasCNP {
			missing = append(missing, "CiliumNetworkPolicy (allow-gateway-envoy)")
		}
		return fmt.Errorf("missing %s", strings.Join(missing, ", "))
	}
	return nil
}
