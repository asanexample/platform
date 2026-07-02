package validate

import (
	"strings"

	"github.com/asanexample/platform/cmd/platctl/internal/config"
	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// ResolveCheckers maps discovered engine units to health-check implementations based on the unit's short
// name (the part after the "/"). Every unit gets a StateCheck; unit types with extra k8s/AWS checks add them
// via the extraCheckers registry (see below), so adding a check type is a data change, not a new switch case.
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
		env := parts[0]
		shortName := parts[1]

		// Every unit gets a Terragrunt state check.
		checks = append(checks, &StateCheck{Name: u.Name + "/state", Unit: u, Binary: "terragrunt"})

		// Unit types with extra checks contribute them through the registry; unknown/state-only types have
		// no entry and get just the StateCheck above (the old switch's default case).
		if build, ok := extraCheckers[shortName]; ok {
			checks = append(checks, build(checkerCtx{
				unit:                u,
				env:                 env,
				kubeCtx:             kubeContextByEnv[env],
				clusterNameByEnv:    clusterNameByEnv,
				clusterProfileByEnv: clusterProfileByEnv,
				cfg:                 cfg,
				run:                 run,
			})...)
		}
	}

	// Units whose empty state is intentional (validate.expected_empty_units — e.g. mimir under the cost
	// profile) pass their state check instead of false-failing.
	if cfg != nil && len(cfg.ExpectedEmptyUnits) > 0 {
		expected := make(map[string]bool, len(cfg.ExpectedEmptyUnits))
		for _, name := range cfg.ExpectedEmptyUnits {
			expected[name] = true
		}
		for _, c := range checks {
			if sc, ok := c.(*StateCheck); ok && expected[sc.Unit.Name] {
				sc.EmptyOK = true
			}
		}
	}

	return checks
}

// checkerCtx bundles everything an extra-check builder needs to construct its checks for one unit.
type checkerCtx struct {
	unit                *engine.Unit
	env                 string
	kubeCtx             string
	clusterNameByEnv    map[string]string
	clusterProfileByEnv map[string]string
	cfg                 *config.ValidateConfig
	run                 CommandRunner
}

// authWithClusterProfile copies base but overrides "profile" with the cluster's own profile when set —
// e.g. an EKS/NLB/TGW lookup must run as the CLUSTER's account, not the deploy (management) account. An
// empty profile leaves base untouched.
func authWithClusterProfile(base map[string]string, profile string) map[string]string {
	if profile == "" {
		return base
	}
	out := map[string]string{"profile": profile}
	for k, v := range base {
		if k != "profile" {
			out[k] = v
		}
	}
	return out
}

// extraCheckers maps a unit short-name to a builder of the checks it gets BEYOND the universal StateCheck.
// A short-name with no entry gets only the StateCheck (the old default). k8s-dependent builders return nil
// when there's no kubecontext for the env.
var extraCheckers = map[string]func(c checkerCtx) []Checker{
	"eks": func(c checkerCtx) []Checker {
		clusterName, ok := c.clusterNameByEnv[c.env]
		if !ok || clusterName == "" {
			return nil
		}
		return []Checker{&EKSClusterCheck{
			Name:        c.unit.Name + "/cluster",
			ClusterName: clusterName,
			KubeContext: c.kubeCtx,
			Auth:        authWithClusterProfile(c.unit.Auth, c.clusterProfileByEnv[c.env]),
			Run:         c.run,
		}}
	},

	"cilium": k8sPods("kube-system", "k8s-app=cilium", "/pods"),

	"eks-addons": k8sPods("kube-system", "k8s-app=kube-dns", "/coredns"),

	"cert-manager": k8sPods("cert-manager", "", "/pods"),

	"external-dns": k8sPods("external-dns", "", "/pods"),

	"external-secrets": k8sPods("external-secrets", "", "/pods"),

	"secret-stores": func(c checkerCtx) []Checker {
		if c.kubeCtx == "" {
			return nil
		}
		return []Checker{&SecretStoreCheck{
			Name:        c.unit.Name + "/status",
			KubeContext: c.kubeCtx,
			ClusterWide: true,
			Run:         c.run,
		}}
	},

	"karpenter": func(c checkerCtx) []Checker {
		if c.kubeCtx == "" {
			return nil
		}
		return []Checker{&KarpenterReadyCheck{
			Name:        c.unit.Name + "/ready",
			KubeContext: c.kubeCtx,
			Run:         c.run,
		}}
	},

	"policy": func(c checkerCtx) []Checker {
		if c.kubeCtx == "" {
			return nil
		}
		// Kyverno is the admission engine — flag any workload its (or any) fail-closed webhook blocks.
		return []Checker{&AdmissionBlockedCheck{
			Name:        c.unit.Name + "/admission",
			KubeContext: c.kubeCtx,
			Run:         c.run,
		}}
	},

	"argocd": func(c checkerCtx) []Checker {
		if c.kubeCtx == "" {
			return nil
		}
		return []Checker{
			&K8sWorkloadCheck{Name: c.unit.Name + "/pods", KubeContext: c.kubeCtx, Namespace: "argocd", Run: c.run},
			&ArgoCDAppCheck{Name: c.unit.Name + "/apps", KubeContext: c.kubeCtx, Run: c.run},
		}
	},

	"tailscale": k8sPods("tailscale-system", "app=operator", "/operator"),

	"transit-gateway": func(c checkerCtx) []Checker {
		// The TGW ID is discovered when not configured (it churns every rebuild).
		tgwID := ""
		if c.cfg != nil {
			tgwID = c.cfg.TransitGateway.ID
		}
		return []Checker{&TGWAttachmentCheck{
			Name:  c.unit.Name + "/attachments",
			Auth:  authWithClusterProfile(c.unit.Auth, c.clusterProfileByEnv[c.env]),
			TGWID: tgwID,
			Run:   c.run,
		}}
	},

	"cross-vpc-dns": func(c checkerCtx) []Checker {
		// VPC DNS resolver: CIDR base + 2. The PHZ lives in THIS unit's VPC and must resolve the REMOTE
		// cluster's API endpoint; the endpoint hostname is discovered from each remote env's EKS cluster
		// (it churns every rebuild — a configured validate.cross_vpc_dns.endpoint remains an optional override).
		resolverIP := vpcResolverIP(c.cfg, c.env)
		if resolverIP == "" {
			return nil
		}
		override := ""
		if c.cfg != nil {
			override = c.cfg.CrossVPCDNS.Endpoint
		}
		var out []Checker
		for remoteEnv, clusterName := range c.clusterNameByEnv {
			if remoteEnv == c.env || clusterName == "" {
				continue
			}
			out = append(out, &CrossVPCDNSCheck{
				Name:        c.unit.Name + "/dns/" + remoteEnv,
				Endpoint:    override,
				ResolverIP:  resolverIP,
				ClusterName: clusterName,
				Auth:        authWithClusterProfile(c.unit.Auth, c.clusterProfileByEnv[remoteEnv]),
				Run:         c.run,
			})
		}
		return out
	},
}

// k8sPods builds a K8sWorkloadCheck for a namespace/selector, returning nil when there's no kubecontext.
// nameSuffix is appended to the unit name for the check's display name (e.g. "/pods", "/coredns").
func k8sPods(namespace, labelSelector, nameSuffix string) func(c checkerCtx) []Checker {
	return func(c checkerCtx) []Checker {
		if c.kubeCtx == "" {
			return nil
		}
		return []Checker{&K8sWorkloadCheck{
			Name:          c.unit.Name + nameSuffix,
			KubeContext:   c.kubeCtx,
			Namespace:     namespace,
			LabelSelector: labelSelector,
			Run:           c.run,
		}}
	}
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
