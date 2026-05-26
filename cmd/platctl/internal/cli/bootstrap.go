// Package cli implements the cobra commands for platctl.
package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/gangster/platform/cmd/platctl/internal/config"
	"github.com/gangster/platform/cmd/platctl/internal/engine"
)

// NewBootstrapCmd creates the bootstrap subcommand.
func NewBootstrapCmd() *cobra.Command {
	var (
		envFilter string
		dryRun    bool
		resume    bool
		yes       bool
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
				return runDryRun(envFilter)
			}
			return runBootstrap(cmd, envFilter, resume, yes)
		},
	}

	cmd.Flags().StringVar(&envFilter, "env", "", "Target a single environment (e.g., platform, preprod)")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "Preview the execution plan without running terragrunt")
	cmd.Flags().BoolVar(&resume, "resume", false, "Resume from a previous incomplete run")
	cmd.Flags().BoolVar(&yes, "yes", false, "Skip manual step prompts (assume prerequisites are met)")

	return cmd
}

func runDryRun(envFilter string) error {
	repoRoot, err := findRepoRoot()
	if err != nil {
		return err
	}

	cfgPath := findConfig(repoRoot)
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

	// Show manual steps
	for _, step := range cfg.ManualSteps {
		fmt.Printf("Manual step before %s: %s\n", step.Before, step.Name)
	}

	// Show lockdown steps
	for _, lock := range cfg.Lockdown {
		fmt.Printf("Lockdown: %s (%s)\n", lock.Unit, lock.Description)
	}

	return nil
}

func runBootstrap(cmd *cobra.Command, envFilter string, resume, yes bool) error {
	repoRoot, err := findRepoRoot()
	if err != nil {
		return err
	}

	cfgPath := findConfig(repoRoot)
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

	runner := &engine.TerragruntRunner{}
	eng := engine.NewEngine(runner, store, g, statePath)

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

	_ = yes // will be used for manual step prompts in Phase 3

	fmt.Printf("Bootstrapping %d units...\n\n", g.Len())
	if err := eng.Run(cmd.Context(), engine.Apply, unitArgs); err != nil {
		fmt.Println("\nTo resume after fixing: platctl bootstrap --resume")
		return err
	}

	// Lockdown phase: re-apply units without bootstrap overrides
	for _, lock := range cfg.Lockdown {
		unit := g.Unit(lock.Unit)
		if unit == nil {
			continue
		}
		fmt.Printf("\nLockdown: %s (%s)\n", lock.Unit, lock.Description)
		if err := runner.Run(cmd.Context(), unit, engine.Apply); err != nil {
			return fmt.Errorf("lockdown %s: %w", lock.Unit, err)
		}
	}

	fmt.Println("\nBootstrap complete.")
	return nil
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

// findConfig looks for .platctl.yaml in the repo root.
func findConfig(repoRoot string) string {
	return repoRoot + "/.platctl.yaml"
}
