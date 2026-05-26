package cli

import (
	"fmt"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/gangster/platform/cmd/platctl/internal/cloud"
	"github.com/gangster/platform/cmd/platctl/internal/config"
	"github.com/gangster/platform/cmd/platctl/internal/engine"
)

// NewTeardownCmd creates the teardown subcommand.
func NewTeardownCmd() *cobra.Command {
	var (
		envFilter string
		dryRun    bool
		resume    bool
		yes       bool
	)

	cmd := &cobra.Command{
		Use:   "teardown",
		Short: "Destroy infrastructure in reverse dependency order",
		Long: `Teardown destroys all Terragrunt units in reverse topological order,
ensuring dependents are destroyed before their dependencies. Use --env
to target a single environment.`,
		RunE: func(cmd *cobra.Command, args []string) error {
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

			if dryRun {
				return printTeardownPlan(g)
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
			logger, err := engine.NewLogger(logDir, "teardown", envFilterPtr, resume, unitNames)
			if err != nil {
				return fmt.Errorf("setting up logging: %w", err)
			}
			fmt.Printf("Logs: %s\n", logger.Dir())

			runner := &engine.TerragruntRunner{
				LogWriter: func(unit string, data []byte) {
					_ = logger.Append(unit, data)
				},
			}

			awsClient := &cloud.AWS{}
			hooks := make(map[string]engine.Hook)
			for name, override := range cfg.Overrides {
				if override.Hook == "" {
					continue
				}
				if g.Unit(name) == nil {
					continue
				}
				h := config.ResolveHook(override, awsClient, !yes)
				if h != nil {
					hooks[name] = h
				}
			}

			eng := engine.NewEngine(runner, store, g, statePath)
			eng.Hooks = hooks
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
			}

			_ = yes // will be used for interactive prompts in Phase 3

			if err := eng.Run(cmd.Context(), engine.Destroy, nil); err != nil {
				fmt.Println("\nTo resume after fixing: platctl teardown --resume")
				return err
			}

			fmt.Println("\nTeardown complete.")
			return nil
		},
	}

	cmd.Flags().StringVar(&envFilter, "env", "", "Target a single environment")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "Preview the teardown plan")
	cmd.Flags().BoolVar(&resume, "resume", false, "Resume from a previous incomplete run")
	cmd.Flags().BoolVar(&yes, "yes", false, "Skip confirmation prompts")

	return cmd
}

func printTeardownPlan(g *engine.Graph) error {
	rev, err := g.Reverse()
	if err != nil {
		return fmt.Errorf("reversing graph: %w", err)
	}

	waves, err := rev.Waves()
	if err != nil {
		return err
	}

	fmt.Printf("Teardown plan: %d units in %d waves (reverse order)\n\n", g.Len(), len(waves))

	for i, wave := range waves {
		fmt.Printf("Wave %d", i+1)
		if len(wave) > 1 {
			fmt.Printf(" (%d units in parallel)", len(wave))
		}
		fmt.Println()
		for _, u := range wave {
			fmt.Printf("  %-35s destroy\n", u.Name)
		}
		fmt.Println()
	}
	return nil
}
