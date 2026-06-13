package cli

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"syscall"
	"time"

	"github.com/spf13/cobra"

	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// NewStatusCmd creates the status subcommand.
func NewStatusCmd() *cobra.Command {
	var (
		watch    bool
		interval int
	)

	cmd := &cobra.Command{
		Use:   "status",
		Short: "Show the state of the last operation",
		Long: `Status reads the .platctl-state.json file and displays the current state of each unit.

With --watch, the display refreshes on an interval and exits automatically once the
operation reaches a terminal state (nothing left running or pending), or on Ctrl-C.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}

			statePath := filepath.Join(repoRoot, ".platctl-state.json")
			store := engine.NewFileStore()

			if watch {
				return watchState(statePath, store, interval)
			}

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

	cmd.Flags().BoolVarP(&watch, "watch", "w", false, "Refresh the status on an interval until the operation finishes (Ctrl-C to stop)")
	cmd.Flags().IntVar(&interval, "interval", 5, "Refresh interval in seconds (with --watch)")

	return cmd
}

// watchState re-renders the state on an interval until the operation is complete or the user interrupts.
func watchState(statePath string, store engine.Store, interval int) error {
	if interval < 1 {
		interval = 1
	}
	tick := time.NewTicker(time.Duration(interval) * time.Second)
	defer tick.Stop()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(sigCh)

	for {
		// Reload from disk each tick — the running bootstrap/teardown rewrites the state file.
		state, err := store.Load(statePath)
		fmt.Print("\033[H\033[2J") // cursor home + clear screen
		if err != nil {
			return fmt.Errorf("loading state: %w", err)
		}
		if state == nil {
			fmt.Println("Waiting for a state file (.platctl-state.json) — start a bootstrap or teardown…")
		} else {
			printState(state)
			fmt.Printf("\nwatching every %ds — updated %s — Ctrl-C to stop\n", interval, time.Now().Format("15:04:05"))
			if state.IsComplete() {
				fmt.Println("\nOperation finished — exiting watch.")
				return nil
			}
		}

		select {
		case <-sigCh:
			fmt.Println()
			return nil
		case <-tick.C:
		}
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
