// Package cli implements the cobra commands for platctl.
package cli

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/asanexample/platform/cmd/platctl/internal/cloud"
	"github.com/asanexample/platform/cmd/platctl/internal/config"
	"github.com/asanexample/platform/cmd/platctl/internal/engine"
	"github.com/asanexample/platform/cmd/platctl/internal/hooks"
)

// NewBootstrapCmd creates the bootstrap subcommand.
func NewBootstrapCmd() *cobra.Command {
	var (
		envFilter   string
		dryRun      bool
		resume      bool
		yes         bool
		concurrency int
	)

	cmd := &cobra.Command{
		Use:   "bootstrap",
		Short: "Deploy infrastructure in dependency order",
		Long: `Bootstrap deploys all Terragrunt units in topological order,
running independent units in parallel. Use --env to target a single
environment, --dry-run to preview the execution plan, or --resume
to continue after a failure.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			if dryRun {
				return runDryRun(cmd, envFilter)
			}
			return runBootstrap(cmd, envFilter, resume, yes, concurrency)
		},
	}

	cmd.Flags().StringVar(&envFilter, "env", "", "Target a single environment (e.g., platform, preprod)")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "Preview the execution plan without running terragrunt")
	cmd.Flags().BoolVar(&resume, "resume", false, "Resume from a previous incomplete run")
	cmd.Flags().BoolVar(&yes, "yes", false, "Skip manual step prompts (assume prerequisites are met)")
	cmd.Flags().IntVar(&concurrency, "concurrency", 4, "Maximum number of parallel unit executions")

	return cmd
}

func runDryRun(cmd *cobra.Command, envFilter string) error {
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

	waves, err := g.Waves()
	if err != nil {
		return err
	}

	fmt.Printf("Execution plan: %d units in %d waves\n", g.Len(), len(waves))
	if envFilter != "" {
		fmt.Printf("Environment filter: %s\n", envFilter)
	}
	fmt.Println()

	for i, wave := range waves {
		fmt.Printf("Wave %d", i+1)
		if len(wave) > 1 {
			fmt.Printf(" (%d units in parallel)", len(wave))
		}
		fmt.Println()

		for _, u := range wave {
			deps := ""
			if len(u.DependsOn) > 0 {
				deps = fmt.Sprintf("  deps: [%s]", strings.Join(u.DependsOn, ", "))
			}

			authInfo := ""
			if profile, ok := u.Auth["profile"]; ok {
				authInfo = fmt.Sprintf("  profile: %s", profile)
			}

			fmt.Printf("  %-35s %s%s%s\n", u.Name, u.Provider, authInfo, deps)
		}
		fmt.Println()
	}

	// Show overrides that will be applied
	for _, unit := range g.Units() {
		if override, ok := cfg.Overrides[unit.Name]; ok {
			if override.Hook != "" {
				fmt.Printf("Hook: %s -> %s", unit.Name, override.Hook)
				if override.HookTarget != "" {
					fmt.Printf(" (target: %s)", override.HookTarget)
				}
				fmt.Println()
			}
			if len(override.BootstrapArgs) > 0 {
				fmt.Printf("Args: %s -> %v\n", unit.Name, override.BootstrapArgs)
			}
		}
	}

	// Show manual steps (only for units in the current graph)
	for _, step := range cfg.ManualSteps {
		if g.Unit(step.Before) != nil {
			fmt.Printf("Manual step before %s: %s\n", step.Before, step.Name)
		}
	}

	// Show lockdown steps (only for units in the current graph)
	for _, lock := range cfg.Lockdown {
		if g.Unit(lock.Unit) != nil {
			fmt.Printf("Lockdown: %s (%s)\n", lock.Unit, lock.Description)
		}
	}

	return nil
}

func runBootstrap(cmd *cobra.Command, envFilter string, resume, yes bool, concurrency int) error {
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

	statePath := filepath.Join(repoRoot, ".platctl-state.json")
	store := engine.NewFileStore()

	// Set up logging
	logDir := filepath.Join(repoRoot, ".platctl-logs")
	var envFilterPtr *string
	if envFilter != "" {
		envFilterPtr = &envFilter
	}
	unitNames := make([]string, 0, g.Len())
	for _, u := range g.Units() {
		unitNames = append(unitNames, u.Name)
	}
	logger, err := engine.NewLogger(logDir, "bootstrap", envFilterPtr, resume, unitNames)
	if err != nil {
		return fmt.Errorf("setting up logging: %w", err)
	}
	fmt.Printf("Logs: %s\n", logger.Dir())

	runner := &engine.TerragruntRunner{
		LogWriter: func(unit string, data []byte) {
			_ = logger.Append(unit, data)
		},
		// Kill a unit that goes silent for this long — a wedged apply never self-recovers
		// and otherwise stalls the whole bootstrap; the engine's retry re-attempts it fresh.
		InactivityTimeout: engine.DefaultInactivityTimeout,
	}

	// Resolve hooks from config overrides
	awsClient := &cloud.AWS{}
	hookMap := make(map[string]engine.Hook)
	for name, override := range cfg.Overrides {
		if override.Hook == "" {
			continue
		}
		if g.Unit(name) == nil {
			continue
		}
		h := hooks.ResolveHook(override, awsClient, !yes)
		if h != nil {
			hookMap[name] = h
		}
	}

	eng := engine.NewEngine(runner, store, g, statePath,
		engine.WithConcurrency(concurrency),
		engine.WithRetry(engine.DefaultMaxRetries, engine.DefaultRetryBackoff))
	eng.Hooks = hookMap
	eng.Logger = logger

	if resume {
		existing, err := store.Load(statePath)
		if err != nil {
			return fmt.Errorf("loading state for resume: %w", err)
		}
		if existing == nil {
			return fmt.Errorf("no state file found; nothing to resume")
		}
		existing.PrepareForResume()
		eng.State = existing
	} else {
		// Check for stale state file
		existing, _ := store.Load(statePath)
		if existing != nil && !existing.IsComplete() {
			fmt.Printf("Incomplete state found from %s.\n", existing.StartedAt.Format("2006-01-02 15:04:05"))
			fmt.Println("Use --resume to continue, or proceed to start fresh.")
			if !yes {
				fmt.Print("Start fresh? [y/N]: ")
				var answer string
				fmt.Scanln(&answer)
				if answer != "y" && answer != "Y" {
					return fmt.Errorf("aborted; use --resume to continue the previous run")
				}
			}
		}
	}

	// Build unit args from config overrides
	unitArgs := make(map[string][]string)
	for name, override := range cfg.Overrides {
		if len(override.BootstrapArgs) > 0 {
			unitArgs[name] = override.BootstrapArgs
		}
	}

	// Pre-flight: check manual step prerequisites
	if len(cfg.ManualSteps) > 0 && !resume {
		checker := &hooks.ManualStepChecker{Client: awsClient, RepoRoot: repoRoot}
		for _, step := range cfg.ManualSteps {
			if g.Unit(step.Before) == nil {
				continue
			}
			ok, err := checker.Check(cmd.Context(), step)
			if err != nil {
				fmt.Printf("Warning: could not verify %q: %v\n", step.Name, err)
			}
			if ok {
				fmt.Printf("Prerequisite %q: satisfied\n", step.Name)
				continue
			}
			fmt.Printf("\nPrerequisite %q not met (required before %s):\n", step.Name, step.Before)
			fmt.Println(step.Instructions)
			if yes {
				return fmt.Errorf("prerequisite %q not met; complete it and retry", step.Name)
			}
			fmt.Print("Continue anyway? [y/N]: ")
			var answer string
			fmt.Scanln(&answer)
			if answer != "y" && answer != "Y" {
				return fmt.Errorf("aborted; complete prerequisite %q and retry", step.Name)
			}
		}
		fmt.Println()
	}

	fmt.Printf("Bootstrapping %d units...\n\n", g.Len())
	if err := eng.Run(cmd.Context(), engine.Apply, unitArgs); err != nil {
		fmt.Println("\nTo resume after fixing: platctl bootstrap --resume")
		return err
	}

	// Lockdown phase: re-apply units without bootstrap overrides. The EKS endpoint-access toggle serializes
	// against any other in-flight cluster update (addons, version), so it can race one and get a transient
	// ResourceInUseException — retry with backoff so lockdown completes without a manual re-run.
	for _, lock := range cfg.Lockdown {
		unit := g.Unit(lock.Unit)
		if unit == nil {
			continue
		}
		fmt.Printf("\nLockdown: %s (%s)\n", lock.Unit, lock.Description)
		if err := applyLockdownWithRetry(cmd.Context(), runner, unit); err != nil {
			return fmt.Errorf("lockdown %s: %w", lock.Unit, err)
		}
	}

	// Configure kubectl contexts
	if len(cfg.Kubeconfig) > 0 {
		fmt.Println("\nConfiguring kubectl contexts...")
		if err := configureKubeconfig(cfg.Kubeconfig, envFilter); err != nil {
			fmt.Printf("Warning: kubeconfig setup failed: %v\n", err)
			fmt.Println("Run 'platctl kubeconfig' to retry.")
		}
	}

	fmt.Println("\nBootstrap complete.")
	return nil
}

const (
	lockdownMaxAttempts = 8
	lockdownBackoff     = 45 * time.Second
)

// applyLockdownWithRetry applies a lockdown unit, retrying the transient EKS "update in progress" conflict
// (the endpoint-access change serializes against any other in-flight cluster update) with a fixed backoff —
// up to ~6 minutes, which covers a typical EKS config update. Non-transient errors return immediately.
func applyLockdownWithRetry(ctx context.Context, runner engine.Runner, unit *engine.Unit) error {
	var err error
	for attempt := 1; attempt <= lockdownMaxAttempts; attempt++ {
		err = runner.Run(ctx, unit, engine.Apply)
		if err == nil || !engine.IsTransientEKSUpdate(err) {
			return err
		}
		if attempt < lockdownMaxAttempts {
			fmt.Printf("  EKS update in progress — retrying lockdown in %s (attempt %d/%d)\n",
				lockdownBackoff, attempt, lockdownMaxAttempts)
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(lockdownBackoff):
			}
		}
	}
	return err
}

// findRepoRoot walks up from cwd looking for a .git directory.
func findRepoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("getting working directory: %w", err)
	}

	for {
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("could not find git repository root from %s", dir)
		}
		dir = parent
	}
}

// resolveConfig returns the config file path. If --config was passed, uses that;
// otherwise defaults to .platctl.yaml in the repo root.
func resolveConfig(cmd *cobra.Command, repoRoot string) string {
	if cfg, _ := cmd.Flags().GetString("config"); cfg != "" {
		return cfg
	}
	return filepath.Join(repoRoot, ".platctl.yaml")
}
