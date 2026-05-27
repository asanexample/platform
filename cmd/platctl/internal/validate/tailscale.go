package validate

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

// TailscaleMacOSPath is the default location for the Tailscale binary on macOS.
// Exported for testing.
var TailscaleMacOSPath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

// TailscaleCheck verifies Tailscale subnet router connectivity, route
// advertisement, split DNS configuration, and private EKS API reachability.
type TailscaleCheck struct {
	Name         string
	Env          string
	KubeContext  string
	ExpectedCIDR string
	Run          CommandRunner
}

// CheckName returns the display name for skip messages.
func (t *TailscaleCheck) CheckName() string { return t.Name }

// --- JSON structs for tailscale status output ---

type tailscaleStatus struct {
	Peer map[string]tailscalePeer `json:"Peer"`
}

type tailscalePeer struct {
	HostName      string   `json:"HostName"`
	Online        bool     `json:"Online"`
	LastSeen      string   `json:"LastSeen"`
	PrimaryRoutes []string `json:"PrimaryRoutes"`
}

// Check performs sequential sub-checks for Tailscale connectivity.
func (t *TailscaleCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	var details []string

	// 1. Find the tailscale binary (PATH or macOS app bundle)
	tsBinary := "tailscale"
	_, err := t.Run(ctx, "which", "tailscale")
	if err != nil {
		if _, statErr := os.Stat(TailscaleMacOSPath); statErr == nil {
			tsBinary = TailscaleMacOSPath
		} else {
			return CheckResult{
				Name:    t.Name,
				Status:  "skipped",
				Message: "tailscale CLI not installed",
				Elapsed: time.Since(start),
			}
		}
	}

	// 2. Get tailscale status and find the subnet router peer
	out, err := t.Run(ctx, tsBinary, "status", "--json")
	if err != nil {
		details = append(details,
			fmt.Sprintf("Failed to get tailscale status: %s", strings.TrimSpace(string(out))),
			fmt.Sprintf("Error: %v", err),
			"Tailscale may not be running or not authenticated.",
			"Run: tailscale status",
			"Run: tailscale up",
		)
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "tailscale status failed",
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	var status tailscaleStatus
	if err := json.Unmarshal(out, &status); err != nil {
		details = append(details,
			fmt.Sprintf("Failed to parse tailscale status JSON: %v", err),
			fmt.Sprintf("Raw output: %s", truncate(string(out), 500)),
		)
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "tailscale status JSON parse error",
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	// Find the subnet router peer matching the environment.
	// Prefer online peers when multiple match (e.g., after pod recreation).
	var routerPeer *tailscalePeer
	var routerPeerName string
	for key, peer := range status.Peer {
		if strings.Contains(strings.ToLower(peer.HostName), strings.ToLower(t.Env)) {
			p := peer
			if routerPeer == nil || (!routerPeer.Online && p.Online) {
				routerPeer = &p
				routerPeerName = key
			}
		}
	}

	if routerPeer == nil {
		details = append(details,
			fmt.Sprintf("No peer found matching environment '%s'", t.Env),
			"Available peers:",
		)
		for _, peer := range status.Peer {
			details = append(details, fmt.Sprintf("  - %s (online=%t)", peer.HostName, peer.Online))
		}
		details = append(details,
			fmt.Sprintf("Run: kubectl --context %s get pods -n tailscale-system", t.KubeContext),
			"Check: https://login.tailscale.com/admin/machines",
		)
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: fmt.Sprintf("subnet router peer for '%s' not found", t.Env),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	details = append(details, fmt.Sprintf("Found peer: %s (key=%s)", routerPeer.HostName, truncate(routerPeerName, 16)))

	// Check if the subnet router is online
	if !routerPeer.Online {
		details = append(details,
			fmt.Sprintf("Subnet router '%s' is OFFLINE", routerPeer.HostName),
			fmt.Sprintf("Last seen: %s", routerPeer.LastSeen),
			"The Tailscale operator pod may have been evicted or the node is down.",
			fmt.Sprintf("Run: kubectl --context %s get pods -n tailscale-system", t.KubeContext),
			"Check: https://login.tailscale.com/admin/machines",
		)
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: fmt.Sprintf("subnet router '%s' is offline (last seen: %s)", routerPeer.HostName, routerPeer.LastSeen),
			Details: details,
			Elapsed: time.Since(start),
		}
	}
	details = append(details, fmt.Sprintf("Subnet router '%s': Online=true", routerPeer.HostName))

	// 3. Check that the expected CIDR is in PrimaryRoutes
	if t.ExpectedCIDR != "" {
		found := false
		for _, route := range routerPeer.PrimaryRoutes {
			if route == t.ExpectedCIDR {
				found = true
				break
			}
		}

		if !found {
			details = append(details,
				fmt.Sprintf("Expected CIDR '%s' not in advertised routes", t.ExpectedCIDR),
				fmt.Sprintf("Actual PrimaryRoutes: %v", routerPeer.PrimaryRoutes),
				"The subnet router may not be advertising the VPC CIDR, or routes may not be approved.",
				"Check: https://login.tailscale.com/admin/machines — approve subnet routes",
				fmt.Sprintf("Run: kubectl --context %s get connector -n tailscale-system -o yaml", t.KubeContext),
			)
			return CheckResult{
				Name:    t.Name,
				Status:  "failed",
				Message: fmt.Sprintf("CIDR '%s' not in advertised routes", t.ExpectedCIDR),
				Details: details,
				Elapsed: time.Since(start),
			}
		}
		details = append(details, fmt.Sprintf("Route '%s': advertised and approved", t.ExpectedCIDR))
	}

	// 4. Check split DNS for EKS
	dnsOut, err := t.Run(ctx, tsBinary, "dns", "status")
	if err != nil {
		details = append(details,
			fmt.Sprintf("Failed to get tailscale DNS status: %s", strings.TrimSpace(string(dnsOut))),
			fmt.Sprintf("Error: %v", err),
			"Run: tailscale dns status",
		)
		// DNS check is non-fatal — continue
	} else {
		dnsText := string(dnsOut)
		if !strings.Contains(dnsText, "eks.amazonaws.com") {
			details = append(details,
				"Split DNS for *.eks.amazonaws.com not found in tailscale DNS config",
				fmt.Sprintf("Actual DNS config:\n%s", truncate(strings.TrimSpace(dnsText), 500)),
				"Split DNS should route EKS API queries through the tailnet for private endpoint resolution.",
				fmt.Sprintf("Run: kubectl --context %s get dnsconfig -n tailscale-system -o yaml", t.KubeContext),
			)
			return CheckResult{
				Name:    t.Name,
				Status:  "failed",
				Message: "split DNS for *.eks.amazonaws.com not configured",
				Details: details,
				Elapsed: time.Since(start),
			}
		}
		details = append(details, "Split DNS: *.eks.amazonaws.com route present")
	}

	// 5. Verify private EKS API is reachable through Tailscale
	out, err = t.Run(ctx, "kubectl", "--context", t.KubeContext, "cluster-info")
	if err != nil {
		details = append(details,
			fmt.Sprintf("kubectl cluster-info failed: %s", strings.TrimSpace(string(out))),
			fmt.Sprintf("Error: %v", err),
			"The private EKS API is not reachable through the Tailscale tunnel.",
			"Check that Tailscale is connected and the subnet router is forwarding traffic.",
			fmt.Sprintf("Run: kubectl --context %s cluster-info", t.KubeContext),
			"Run: tailscale ping <eks-api-ip>",
		)
		return CheckResult{
			Name:    t.Name,
			Status:  "failed",
			Message: "private EKS API unreachable through Tailscale",
			Details: details,
			Elapsed: time.Since(start),
		}
	}
	details = append(details, "Private EKS API: reachable through Tailscale")

	return CheckResult{
		Name:    t.Name,
		Status:  "ok",
		Message: fmt.Sprintf("subnet router online, CIDR %s advertised, API reachable", t.ExpectedCIDR),
		Details: details,
		Elapsed: time.Since(start),
	}
}
