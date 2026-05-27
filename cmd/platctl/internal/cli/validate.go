package cli

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"

	"github.com/gangster/platform/cmd/platctl/internal/config"
	"github.com/gangster/platform/cmd/platctl/internal/validate"
)

// NewValidateCmd creates the validate subcommand.
func NewValidateCmd() *cobra.Command {
	var (
		envFilter   string
		concurrency int
	)

	cmd := &cobra.Command{
		Use:   "validate",
		Short: "Check deployed infrastructure health",
		Long: `Validate runs health checks against deployed infrastructure.

Checks are organized in two phases:
  Phase 1: IAM & credential checks (SSO sessions, role assumptions, state backend)
  Phase 2: Per-unit checks, cross-cutting checks (gateway, DNS, Tailscale, endpoints)

If Phase 1 fails, Phase 2 is skipped to avoid cascading failures from expired credentials.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runValidate(cmd, envFilter, concurrency)
		},
	}

	cmd.Flags().StringVar(&envFilter, "env", "", "Target a single environment (e.g., platform, preprod)")
	cmd.Flags().IntVar(&concurrency, "concurrency", 8, "Maximum parallel checks")

	return cmd
}

func runValidate(cmd *cobra.Command, envFilter string, concurrency int) error {
	repoRoot, err := findRepoRoot()
	if err != nil {
		return err
	}

	cfgPath := resolveConfig(cmd, repoRoot)
	cfg, err := config.Load(cfgPath)
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	g, err := config.Discover(cfg, repoRoot)
	if err != nil {
		return fmt.Errorf("discovering units: %w", err)
	}

	if envFilter != "" {
		g, err = g.FilterByEnv(envFilter)
		if err != nil {
			return fmt.Errorf("filtering by env %q: %w", envFilter, err)
		}
	}

	units := g.Units()
	fmt.Printf("Validating %d units", len(units))
	if envFilter != "" {
		fmt.Printf(" (env: %s)", envFilter)
	}
	fmt.Println("...")
	fmt.Println()

	// Build kubecontext and cluster name maps from kubeconfig entries.
	// platctl kubeconfig uses --alias, so context name = alias (e.g., "platform").
	kubeContextByEnv := make(map[string]string)
	clusterNameByEnv := make(map[string]string)
	clusterProfileByEnv := make(map[string]string)
	for _, entry := range cfg.Kubeconfig {
		kubeContextByEnv[entry.Alias] = entry.Alias
		clusterNameByEnv[entry.Alias] = entry.Cluster
		clusterProfileByEnv[entry.Alias] = entry.Profile
	}

	run := validate.ExecRunner
	ctx := context.Background()

	// Collect unique profiles for IAM checks
	profileSet := make(map[string]bool)
	for _, env := range cfg.Environments {
		if p, ok := env.Auth["profile"]; ok {
			profileSet[p] = true
		}
	}
	for _, entry := range cfg.Kubeconfig {
		if entry.Profile != "" {
			profileSet[entry.Profile] = true
		}
	}
	var profiles []string
	for p := range profileSet {
		profiles = append(profiles, p)
	}

	// Determine default profile (the management/env-level profile used for cross-account access)
	defaultProfile := "management"
	for _, env := range cfg.Environments {
		if p, ok := env.Auth["profile"]; ok {
			defaultProfile = p
			break
		}
	}

	// --- Phase 1: IAM checks ---
	var iamChecks []validate.Checker
	iamCheck := &validate.IAMCheck{
		Name:              "iam",
		Profiles:          profiles,
		DefaultProfile:    defaultProfile,
		Accounts:          cfg.Validate.IAM.Accounts,
		KubeconfigEntries: cfg.Kubeconfig,
		StateBucket:       cfg.Validate.IAM.StateBucket,
		Run:               run,
	}
	iamChecks = append(iamChecks, iamCheck)

	// --- Phase 2: per-unit + cross-cutting checks ---
	var otherChecks []validate.Checker

	// Per-unit checks
	unitChecks := validate.ResolveCheckers(units, kubeContextByEnv, clusterNameByEnv, clusterProfileByEnv, &cfg.Validate, run)
	otherChecks = append(otherChecks, unitChecks...)

	// Cross-cutting: Gateway health
	if cfg.Validate.Gateway.Name != "" {
		platformCtx := kubeContextByEnv["platform"]
		if envFilter != "" {
			if kc, ok := kubeContextByEnv[envFilter]; ok {
				platformCtx = kc
			}
		}
		if platformCtx != "" {
			gwAuth := cfg.AuthForUnit("platform", "gateway-config")
			otherChecks = append(otherChecks, &validate.GatewayHealthCheck{
				Name:             "gateway",
				KubeContext:      platformCtx,
				GatewayName:      cfg.Validate.Gateway.Name,
				GatewayNamespace: cfg.Validate.Gateway.Namespace,
				CertName:         cfg.Validate.Gateway.CertName,
				Auth:             gwAuth,
				Run:              run,
			})
		}
	}

	// Cross-cutting: DNS delegation
	if cfg.Validate.DNS.Zone != "" && len(cfg.Validate.DNS.ExpectedNS) > 0 {
		otherChecks = append(otherChecks, &validate.DNSDelegationCheck{
			Name:       "dns/" + cfg.Validate.DNS.Zone,
			Zone:       cfg.Validate.DNS.Zone,
			ExpectedNS: cfg.Validate.DNS.ExpectedNS,
			Run:        run,
		})
	}

	// Cross-cutting: Tailscale (per env)
	for envName, cidr := range cfg.Validate.Tailscale.VPCCIDRs {
		if envFilter != "" && envName != envFilter {
			continue
		}
		kubeCtx := kubeContextByEnv[envName]
		if kubeCtx == "" {
			continue
		}
		otherChecks = append(otherChecks, &validate.TailscaleCheck{
			Name:         "tailscale/" + envName,
			Env:          envName,
			KubeContext:  kubeCtx,
			ExpectedCIDR: cidr,
			Run:          run,
		})
	}

	// Cross-cutting: Endpoints
	for _, ep := range cfg.Validate.Endpoints {
		if envFilter != "" && ep.Env != "" && ep.Env != envFilter {
			continue
		}
		otherChecks = append(otherChecks, &validate.EndpointCheck{
			Name: "endpoint/" + ep.Name,
			URL:  ep.URL,
			Run:  run,
		})
	}

	// Build the expired-profiles callback
	expiredFn := func(_ context.Context) []string {
		return iamCheck.ExpiredProfiles
	}

	// Run two-phase validation
	start := time.Now()
	results := validate.RunValidation(ctx, iamChecks, otherChecks, concurrency, expiredFn)

	// Print results
	fmt.Println()
	passed, failed, skipped := validate.PrintResults(results)
	fmt.Printf("\nPassed: %d  Failed: %d  Skipped: %d  (%s)\n", passed, failed, skipped, time.Since(start).Round(time.Millisecond))

	if failed > 0 {
		os.Exit(1)
	}
	return nil
}
