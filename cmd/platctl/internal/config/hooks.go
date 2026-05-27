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
// The args parameter carries bootstrap_args from the config so hooks can forward them.
type Hook interface {
	Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error
}

// CRDTwoStageHook deploys a Helm release in two stages: first the operator
// (to register CRDs), then the full apply. This avoids the chicken-and-egg
// problem where custom resources reference CRDs that don't exist yet.
type CRDTwoStageHook struct {
	Target string // e.g., "helm_release.tailscale_operator[0]"
}

// Execute runs the two-stage CRD bootstrap on apply, or a straight destroy with args.
func (h *CRDTwoStageHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action, args...)
	}

	// Stage 1: deploy only the operator to register CRDs
	stage1Args := append([]string{fmt.Sprintf("-target=%s", h.Target)}, args...)
	if err := runner.Run(ctx, unit, action, stage1Args...); err != nil {
		return fmt.Errorf("CRD stage 1 (operator): %w", err)
	}

	// Stage 2: full apply with bootstrap args (CRDs now exist)
	if err := runner.Run(ctx, unit, action, args...); err != nil {
		return fmt.Errorf("CRD stage 2 (full): %w", err)
	}

	return nil
}

// SecretEntry is a secret name and the auth credentials needed to access it.
type SecretEntry struct {
	ID   string
	Auth map[string]string
}

// SecretCleanupHook force-deletes Secrets Manager secrets that may be left over
// from a previous deployment (pending deletion or orphaned). Runs before apply
// so the module can recreate them cleanly.
type SecretCleanupHook struct {
	Secrets []SecretEntry
	Client  cloud.AWSClient
}

// Execute checks for and force-deletes any existing secrets, then runs the apply.
func (h *SecretCleanupHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action, args...)
	}

	if h.Client == nil {
		return runner.Run(ctx, unit, action, args...)
	}

	for _, secret := range h.Secrets {
		exists, _ := h.Client.SecretExists(ctx, secret.ID, secret.Auth)
		if !exists {
			continue
		}
		fmt.Printf("Cleaning up existing secret %s...\n", secret.ID)
		if err := h.Client.ForceDeleteSecret(ctx, secret.ID, secret.Auth); err != nil {
			return fmt.Errorf("cleaning up secret %s: %w", secret.ID, err)
		}
	}

	return runner.Run(ctx, unit, action, args...)
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
func (h *ENIIPValidationHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action, args...)
	}

	if h.Client == nil {
		return runner.Run(ctx, unit, action, args...)
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

	return runner.Run(ctx, unit, action, args...)
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

	case "secret_cleanup":
		defaultProfile := override.HookConfig["profile"]
		var secrets []SecretEntry
		if raw, ok := override.HookConfig["secrets"]; ok {
			for _, s := range strings.Split(raw, ",") {
				s = strings.TrimSpace(s)
				if s == "" {
					continue
				}
				// Format: "secret_id" or "secret_id@profile"
				entry := SecretEntry{Auth: map[string]string{}}
				if idx := strings.LastIndex(s, "@"); idx > 0 {
					entry.ID = s[:idx]
					entry.Auth["profile"] = s[idx+1:]
				} else {
					entry.ID = s
					if defaultProfile != "" {
						entry.Auth["profile"] = defaultProfile
					}
				}
				secrets = append(secrets, entry)
			}
		}
		return &SecretCleanupHook{
			Secrets: secrets,
			Client:  awsClient,
		}

	default:
		return nil
	}
}
