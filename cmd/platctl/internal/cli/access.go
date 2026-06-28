package cli

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/spf13/cobra"

	"github.com/asanexample/platform/cmd/platctl/internal/access"
)

// NewAccessCmd creates the `access` command group — read-only inspection of workforce
// access from the git registries (the read side of the ADR-088 temporary-power model;
// grant/revoke land here later as the controller-down break-glass).
func NewAccessCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "access",
		Short: "Inspect workforce access from the git registries (ADR-088)",
		Long: `Inspect who holds — or can borrow — what, resolved from gitops/people
(the roster) joined with gitops/roles (the catalog). Read-only.

"standing" access is held all the time; "borrowable" access is on-demand
(eligible, not standing — activated for a bounded window, ADR-088).`,
	}
	cmd.AddCommand(newAccessListCmd())
	cmd.AddCommand(newAccessCheckCmd())
	return cmd
}

func newAccessListCmd() *cobra.Command {
	var borrowableOnly bool

	cmd := &cobra.Command{
		Use:   "list",
		Short: "List who holds (or can borrow) what, from gitops/people × gitops/roles",
		RunE: func(_ *cobra.Command, _ []string) error {
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}
			people, err := access.LoadPeople(repoRoot)
			if err != nil {
				return err
			}
			roles, err := access.LoadRoles(repoRoot)
			if err != nil {
				return err
			}

			entries := access.Resolve(people, roles, borrowableOnly)
			w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
			fmt.Fprintln(w, "PERSON\tANCHOR\tROLE\tREACH\tKIND\tRISK")
			for _, e := range entries {
				kind := "standing"
				if e.Borrowable {
					kind = "borrowable"
				}
				fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n", e.Person, e.Anchor, e.Role, e.Reach, kind, e.RiskTier)
			}
			if err := w.Flush(); err != nil {
				return err
			}
			if len(entries) == 0 {
				fmt.Println("(no matching grants)")
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&borrowableOnly, "borrowable", false, "Only show on-demand (borrowable) grants — i.e. what's eligible to activate")
	return cmd
}

func newAccessCheckCmd() *cobra.Command {
	var team, scope string

	cmd := &cobra.Command{
		Use:   "check <person-or-anchor> <role>",
		Short: "Check whether a principal may BORROW a role (the activation eligibility decision)",
		Long: `Decide whether a principal (by Person name or Keycloak anchor) is eligible to
borrow a role at a given reach — the authorization the activation controller
makes before minting temporary access (ADR-088). Exits non-zero when denied.

  platctl access check dev-a platform-operator --scope platform
  platctl access check alpha-dev developer --team alpha`,
		Args:          cobra.ExactArgs(2),
		SilenceErrors: true, // we print "DENIED: …" via the returned error in main; don't let cobra double-print
		RunE: func(_ *cobra.Command, args []string) error {
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}
			people, err := access.LoadPeople(repoRoot)
			if err != nil {
				return err
			}
			roles, err := access.LoadRoles(repoRoot)
			if err != nil {
				return err
			}

			d := access.Eligible(people, roles, args[0], args[1], team, scope)
			if d.Allowed {
				fmt.Printf("ALLOWED: %s\n", d.Reason)
				return nil
			}
			// Denied — print and exit non-zero (scriptable) without a usage dump.
			return &silentExitError{msg: "DENIED: " + d.Reason}
		},
	}
	cmd.Flags().StringVar(&team, "team", "", "Team-scoped reach (mutually exclusive with --scope)")
	cmd.Flags().StringVar(&scope, "scope", "", "Platform-scoped reach, e.g. 'platform' (mutually exclusive with --team)")
	return cmd
}

// silentExitError carries a message and exits non-zero without cobra printing usage.
type silentExitError struct{ msg string }

func (e *silentExitError) Error() string { return e.msg }
