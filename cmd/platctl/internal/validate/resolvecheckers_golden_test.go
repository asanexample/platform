package validate

import (
	"fmt"
	"sort"
	"testing"

	"github.com/asanexample/platform/cmd/platctl/internal/config"
	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// allUnitShortNames is every unit short-name ResolveCheckers has a case for, plus one unknown
// ("mystery") to exercise the default (state-only) path.
var allUnitShortNames = []string{
	"eks", "cilium", "node-groups", "networking", "iam-roles", "ssm-bastion", "eks-addons",
	"cert-manager", "external-dns", "external-secrets", "secret-stores", "karpenter", "policy",
	"argocd", "argocd-clusters", "tailscale", "tailscale-admin", "transit-gateway", "cross-vpc-dns",
	"gateway-config", "route53", "route53-delegation", "ecr", "github-oidc", "crossplane",
	"argocd-apps", "cloudtrail", "mystery",
}

// resolveGoldenFor builds a comprehensive input covering every unit type and returns the resulting
// checks as sorted "name -> type" strings — a stable signature of ResolveCheckers' wiring. cross-vpc-dns
// needs a second env with a cluster to emit its per-remote checks, so preprod is present in the cluster maps.
func resolveGoldenFor(t *testing.T) []string {
	t.Helper()
	var units []*engine.Unit
	for _, sn := range allUnitShortNames {
		units = append(units, &engine.Unit{
			Name: "platform/" + sn, Path: "/tmp/" + sn, Env: "platform",
			Auth: map[string]string{"profile": "management"},
		})
	}
	kubeCtx := map[string]string{"platform": "platform", "preprod": "preprod"}
	clusterName := map[string]string{"platform": "platform-use1-eks", "preprod": "preprod-use1-eks"}
	clusterProfile := map[string]string{"platform": "platform", "preprod": "preprod"}
	cfg := &config.ValidateConfig{
		Tailscale:      config.TailscaleValidation{VPCCIDRs: map[string]string{"platform": "10.100.0.0/16"}},
		TransitGateway: config.TGWValidation{ID: "tgw-123"},
	}
	checks := ResolveCheckers(units, kubeCtx, clusterName, clusterProfile, cfg, newMockRunner())

	var sig []string
	for _, c := range checks {
		name := ""
		if nc, ok := c.(interface{ CheckName() string }); ok {
			name = nc.CheckName()
		}
		sig = append(sig, fmt.Sprintf("%s -> %T", name, c))
	}
	sort.Strings(sig)
	return sig
}

// TestResolveCheckers_Golden pins the exact set of checks ResolveCheckers produces for every unit type.
// It guards the switch→registry refactor: any drift in which checks a unit type gets fails here.
func TestResolveCheckers_Golden(t *testing.T) {
	got := resolveGoldenFor(t)
	want := goldenResolveCheckers
	if len(got) != len(want) {
		t.Errorf("check count: got %d, want %d", len(got), len(want))
	}
	max := len(got)
	if len(want) > max {
		max = len(want)
	}
	for i := 0; i < max; i++ {
		g, w := "", ""
		if i < len(got) {
			g = got[i]
		}
		if i < len(want) {
			w = want[i]
		}
		if g != w {
			t.Errorf("line %d:\n  got:  %s\n  want: %s", i, g, w)
		}
	}
	if t.Failed() {
		t.Log("full got list (paste into goldenResolveCheckers if this is the intended baseline):")
		for _, s := range got {
			t.Logf("\t%q,", s)
		}
	}
}
