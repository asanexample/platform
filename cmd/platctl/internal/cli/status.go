package cli

import (
	"fmt"
	"path/filepath"
	"sort"

	"github.com/spf13/cobra"

	"github.com/gangster/platform/cmd/platctl/internal/engine"
)

// NewStatusCmd creates the status subcommand.
func NewStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show the state of the last operation",
		Long:  `Status reads the .platctl-state.json file and displays the current state of each unit.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}

			statePath := filepath.Join(repoRoot, ".platctl-state.json")
			store := engine.NewFileStore()
			state, err := store.Load(statePath)
			if err != nil {
				return fmt.Errorf("loading state: %w", err)
			}
			if state == nil {
				fmt.Println("No state file found. Run `platctl bootstrap` or `platctl teardown` first.")
				return nil
			}

			printState(state)
			return nil
		},
	}
}

func printState(state *engine.State) {
	fmt.Printf("Operation: %s\n", state.Operation)
	fmt.Printf("Started:   %s\n\n", state.StartedAt.Format("2006-01-02 15:04:05"))

	var (
		completed int
		failed    int
		skipped   int
		pending   int
		running   int
	)

	names := make([]string, 0, len(state.Units))
	for name := range state.Units {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, name := range names {
		us := state.Units[name]
		symbol := statusSymbol(us.Status)
		duration := ""
		if us.StartedAt != nil && us.FinishedAt != nil {
			d := us.FinishedAt.Sub(*us.StartedAt)
			duration = fmt.Sprintf("  (%s)", d.Round(100*1e6))
		}
		errMsg := ""
		if us.Error != "" {
			errMsg = fmt.Sprintf("  %s", us.Error)
		}
		fmt.Printf("  %s %-35s%s%s\n", symbol, name, duration, errMsg)

		switch us.Status {
		case engine.StatusCompleted:
			completed++
		case engine.StatusFailed:
			failed++
		case engine.StatusSkipped:
			skipped++
		case engine.StatusPending:
			pending++
		case engine.StatusRunning:
			running++
		}
	}

	fmt.Printf("\nCompleted: %d  Failed: %d  Skipped: %d  Pending: %d  Running: %d\n",
		completed, failed, skipped, pending, running)
}

func statusSymbol(s engine.Status) string {
	switch s {
	case engine.StatusCompleted:
		return "ok"
	case engine.StatusFailed:
		return "!!"
	case engine.StatusSkipped:
		return "--"
	case engine.StatusRunning:
		return ">>"
	default:
		return "  "
	}
}
