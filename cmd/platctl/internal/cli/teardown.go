package cli

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/spf13/cobra"

	"github.com/gangster/platform/cmd/platctl/internal/cloud"
	"github.com/gangster/platform/cmd/platctl/internal/config"
	"github.com/gangster/platform/cmd/platctl/internal/engine"
)

// NewTeardownCmd creates the teardown subcommand.
func NewTeardownCmd() *cobra.Command {
	var (
		envFilter   string
		dryRun      bool
		resume      bool
		yes         bool
		concurrency int
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

			if dryRun {
				return printTeardownPlan(g, cfg)
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

			// Initialize + persist a fresh teardown state up-front (all units Pending) so `platctl status`
			// and `status --watch` reflect THIS run immediately. The Unlock and Pre-destroy-apply phases
			// below run before the destroy-wave engine that owns the state file, and they take minutes; without
			// this, the on-disk .platctl-state.json still describes the PREVIOUS (completed) operation, so
			// `status --watch` reads IsComplete()==true and exits at once — looking like the teardown already
			// finished. A non-resume run owns the state file outright; --resume keeps the prior run's state.
			if !resume {
				if err := store.Save(statePath, engine.NewState("teardown", g.Units())); err != nil {
					return fmt.Errorf("initializing teardown state: %w", err)
				}
			}

			// Unlock phase: reverse lockdown before destroying.
			// Re-apply lockdown units with bootstrap_args to restore access.
			// Only runs if the unit has resources in state (avoids recreating destroyed infra).
			if !resume {
				for i := len(cfg.Lockdown) - 1; i >= 0; i-- {
					lock := cfg.Lockdown[i]
					unit := g.Unit(lock.Unit)
					if unit == nil {
						continue
					}
					override, ok := cfg.Overrides[lock.Unit]
					if !ok || len(override.BootstrapArgs) == 0 {
						continue
					}
					if !unitHasState(unit, runner.Binary) {
						fmt.Printf("Unlock: %s — skipped (no resources in state)\n", lock.Unit)
						continue
					}
					fmt.Printf("Unlock: %s (%s)\n", lock.Unit, lock.Description)
					if err := runner.Run(cmd.Context(), unit, engine.Apply, override.BootstrapArgs...); err != nil {
						fmt.Printf("  Warning: unlock failed: %v\n", err)
					}
				}
				fmt.Println()
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

			eng := engine.NewEngine(runner, store, g, statePath, engine.WithConcurrency(concurrency))
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

			// teardown_skip units (e.g. iam-roles) are kept out of teardown — collect them once so the
			// pre-destroy / empty-state / run phases all leave them untouched. They stay in the graph so
			// dependents still order correctly; they're simply never destroyed.
			teardownSkip := make(map[string]bool)
			for name, override := range cfg.Overrides {
				if override.TeardownSkip && g.Unit(name) != nil {
					teardownSkip[name] = true
				}
			}

			// Pre-destroy: apply teardown_args to update resource attributes in state.
			// Passing -var force_destroy=true during destroy doesn't work because
			// providers read the attribute from state, not the plan config.
			if !resume {
				teardownArgs := make(map[string][]string)
				for name, override := range cfg.Overrides {
					if len(override.TeardownArgs) > 0 && g.Unit(name) != nil {
						teardownArgs[name] = override.TeardownArgs
					}
				}
				for name, args := range teardownArgs {
					if teardownSkip[name] {
						continue
					}
					unit := g.Unit(name)
					if unit == nil {
						continue
					}
					if !unitHasState(unit, runner.Binary) {
						continue
					}
					fmt.Printf("Pre-destroy apply: %s (%v)\n", name, args)
					if err := runner.Run(cmd.Context(), unit, engine.Apply, args...); err != nil {
						fmt.Printf("  Warning: pre-destroy apply failed: %v\n", err)
					}
				}
			}

			// Skip units with empty state — nothing to destroy.
			// Checks run in parallel to avoid sequential ~30s per unit.
			if !resume {
				units := g.Units()
				state := engine.NewState("teardown", units)
				type stateResult struct {
					name     string
					hasState bool
				}
				results := make(chan stateResult, len(units))
				sem := make(chan struct{}, concurrency)
				for _, u := range units {
					go func(u *engine.Unit) {
						sem <- struct{}{}
						defer func() { <-sem }()
						results <- stateResult{name: u.Name, hasState: unitHasState(u, runner.Binary)}
					}(u)
				}
				skipped := 0
				for range units {
					r := <-results
					if !r.hasState {
						state.MarkCompleted(r.name)
						skipped++
					}
				}
				if skipped > 0 {
					fmt.Printf("Skipping %d units with empty state\n", skipped)
				}
				eng.State = state
			}

			// Keep teardown_skip units alive: mark them completed so the engine never destroys them. Done
			// here (not via graph removal) so dependents still resolve their dependency edges for ordering.
			// Applies to both fresh and --resume runs.
			if len(teardownSkip) > 0 && eng.State != nil {
				names := make([]string, 0, len(teardownSkip))
				for name := range teardownSkip {
					eng.State.MarkCompleted(name)
					names = append(names, name)
				}
				sort.Strings(names)
				fmt.Printf("Keeping %d unit(s) (teardown_skip, will NOT be destroyed): %s\n", len(names), strings.Join(names, ", "))
			}

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
	cmd.Flags().IntVar(&concurrency, "concurrency", 4, "Maximum number of parallel unit executions")

	return cmd
}

// unitHasState checks if a unit has any resources in Terraform state.
// Returns false if the state is empty (unit already destroyed or never deployed).
func unitHasState(unit *engine.Unit, binary string) bool {
	if binary == "" {
		binary = "terragrunt"
	}
	cmd := exec.CommandContext(context.Background(), binary, "state", "list")
	cmd.Dir = unit.Path
	env := os.Environ()
	if profile, ok := unit.Auth["profile"]; ok {
		found := false
		prefix := "AWS_PROFILE="
		for i, e := range env {
			if len(e) > len(prefix) && e[:len(prefix)] == prefix {
				env[i] = prefix + profile
				found = true
				break
			}
		}
		if !found {
			env = append(env, prefix+profile)
		}
	}
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	return len(strings.TrimSpace(string(out))) > 0
}

func printTeardownPlan(g *engine.Graph, cfg *config.Config) error {
	rev, err := g.Reverse()
	if err != nil {
		return fmt.Errorf("reversing graph: %w", err)
	}

	waves, err := rev.Waves()
	if err != nil {
		return err
	}

	skip := make(map[string]bool)
	for name, override := range cfg.Overrides {
		if override.TeardownSkip {
			skip[name] = true
		}
	}

	destroyCount := g.Len() - len(skip)
	fmt.Printf("Teardown plan: %d units to destroy in %d waves (reverse order)", destroyCount, len(waves))
	if len(skip) > 0 {
		fmt.Printf("; %d kept (teardown_skip)", len(skip))
	}
	fmt.Print("\n\n")

	for i, wave := range waves {
		fmt.Printf("Wave %d", i+1)
		if len(wave) > 1 {
			fmt.Printf(" (%d units in parallel)", len(wave))
		}
		fmt.Println()
		for _, u := range wave {
			action := "destroy"
			if skip[u.Name] {
				action = "KEEP (teardown_skip)"
			}
			fmt.Printf("  %-35s %s\n", u.Name, action)
		}
		fmt.Println()
	}
	return nil
}
