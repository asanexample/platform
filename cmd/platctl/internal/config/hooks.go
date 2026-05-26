package config

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/gangster/platform/cmd/platctl/internal/cloud"
	"github.com/gangster/platform/cmd/platctl/internal/engine"
)

// Hook defines a pre-apply or multi-stage operation for a unit.
type Hook interface {
	Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action) error
}

// CRDTwoStageHook deploys a Helm release in two stages: first the operator
// (to register CRDs), then the full apply. This avoids the chicken-and-egg
// problem where custom resources reference CRDs that don't exist yet.
type CRDTwoStageHook struct {
	Target string // e.g., "helm_release.tailscale_operator[0]"
}

// Execute runs the two-stage CRD bootstrap.
func (h *CRDTwoStageHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action)
	}

	// Stage 1: deploy only the operator to register CRDs
	targetArg := fmt.Sprintf("-target=%s", h.Target)
	if err := runner.Run(ctx, unit, action, targetArg); err != nil {
		return fmt.Errorf("CRD stage 1 (operator): %w", err)
	}

	// Stage 2: full apply (CRDs now exist, custom resources can be created)
	if err := runner.Run(ctx, unit, action); err != nil {
		return fmt.Errorf("CRD stage 2 (full): %w", err)
	}

	return nil
}

// ENIIPValidationHook queries EKS ENI IPs and compares them to the values
// in the cross-vpc-dns live unit. Alerts the user if they're stale.
type ENIIPValidationHook struct {
	ClusterName string
	Auth        map[string]string
	Client      cloud.AWSClient
	Interactive bool
}

// Execute validates ENI IPs before applying cross-vpc-dns.
func (h *ENIIPValidationHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action)
	}

	if h.Client == nil {
		// No AWS client available — skip validation, proceed with apply
		return runner.Run(ctx, unit, action)
	}

	ips, err := h.Client.DescribeEKSENIs(ctx, h.ClusterName, h.Auth)
	if err != nil {
		fmt.Printf("Warning: could not query ENI IPs for %s: %v\n", h.ClusterName, err)
		fmt.Println("Proceeding with apply — verify IPs manually if this is a fresh cluster.")
		return runner.Run(ctx, unit, action)
	}

	if len(ips) > 0 {
		fmt.Printf("Discovered ENI IPs for %s: %v\n", h.ClusterName, ips)
		fmt.Println("Verify these match the phz_records IPs in the cross-vpc-dns live unit.")

		if h.Interactive {
			fmt.Print("Continue with apply? [y/N]: ")
			reader := bufio.NewReader(os.Stdin)
			answer, _ := reader.ReadString('\n')
			answer = strings.TrimSpace(answer)
			if answer != "y" && answer != "Y" {
				return fmt.Errorf("aborted: update IPs in cross-vpc-dns terragrunt.hcl first")
			}
		}
	}

	return runner.Run(ctx, unit, action)
}

// ManualStepChecker verifies that manual prerequisites have been completed.
type ManualStepChecker struct {
	Client   cloud.Client
	RepoRoot string
}

// Check evaluates a manual step's check condition.
// Returns true if the prerequisite is satisfied.
func (c *ManualStepChecker) Check(ctx context.Context, step ManualStep) (bool, error) {
	switch step.Check.Type {
	case "secret_exists":
		if c.Client == nil {
			return false, nil
		}
		return c.Client.SecretExists(ctx, step.Check.SecretID, map[string]string{
			"profile": step.Check.Profile,
		})

	case "file_contains":
		filePath := step.Check.File
		if c.RepoRoot != "" && !strings.HasPrefix(filePath, "/") {
			filePath = c.RepoRoot + "/" + filePath
		}
		data, err := os.ReadFile(filePath)
		if err != nil {
			return false, nil
		}
		return strings.Contains(string(data), step.Check.Pattern), nil

	default:
		return false, fmt.Errorf("unknown check type: %s", step.Check.Type)
	}
}

// ResolveHook creates a Hook implementation from config override settings.
func ResolveHook(override UnitOverride, awsClient cloud.AWSClient, interactive bool) Hook {
	switch override.Hook {
	case "crd_two_stage":
		return &CRDTwoStageHook{Target: override.HookTarget}

	case "eni_ip_validation":
		auth := make(map[string]string)
		for k, v := range override.HookConfig {
			auth[k] = v
		}
		return &ENIIPValidationHook{
			ClusterName: override.HookConfig["cluster_name"],
			Auth:        auth,
			Client:      awsClient,
			Interactive: interactive,
		}

	default:
		return nil
	}
}
