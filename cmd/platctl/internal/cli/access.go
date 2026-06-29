package cli

import (
	"context"
	"fmt"
	"os"
	"os/user"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"

	"github.com/asanexample/platform/cmd/platctl/internal/cloud"
	"github.com/asanexample/platform/pkg/access"
)

// NewAccessCmd creates the `access` command group — inspect, and (as the controller-down
// break-glass fallback, ADR-088) ACTIVATE temporary power. `list`/`check` are read-only;
// `grant`/`revoke` mint/clear a temporary AWS Identity Center assignment and DEFAULT to
// --dry-run. The always-on activation controller (timers, the Backstage front door, the
// Keycloak/cluster planes) is deferred — platctl is the manual fallback for when it's down.
func NewAccessCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "access",
		Short: "Inspect and activate workforce access (ADR-088 temporary power)",
		Long: `Inspect who holds — or can borrow — what (resolved from gitops/people joined
with gitops/roles), and activate a borrowable power for a bounded window.

"standing" access is held all the time; "borrowable" access is on-demand
(eligible, not standing — activated for a bounded window, ADR-088).

  list / check     read-only eligibility inspection
  grant / revoke   the controller-down break-glass fallback: mint/clear a
                   temporary AWS Identity Center assignment (DEFAULT --dry-run)
  active           the local ledger of grants platctl has minted`,
	}
	cmd.AddCommand(newAccessListCmd())
	cmd.AddCommand(newAccessCheckCmd())
	cmd.AddCommand(newAccessGrantCmd())
	cmd.AddCommand(newAccessRevokeCmd())
	cmd.AddCommand(newAccessActiveCmd())
	return cmd
}

// operatorName returns the local username for the audit record, best-effort.
func operatorName() string {
	if u, err := user.Current(); err == nil && u.Username != "" {
		return u.Username
	}
	if n := os.Getenv("USER"); n != "" {
		return n
	}
	return "unknown"
}

// loadRegistries loads the people roster + role catalog from the repo root.
func loadRegistries() ([]access.Person, map[string]access.Role, error) {
	repoRoot, err := findRepoRoot()
	if err != nil {
		return nil, nil, err
	}
	people, err := access.LoadPeople(repoRoot)
	if err != nil {
		return nil, nil, err
	}
	roles, err := access.LoadRoles(repoRoot)
	if err != nil {
		return nil, nil, err
	}
	return people, roles, nil
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

// resolvedTargets is the live AWS Identity Center resolution for an activation.
type resolvedTargets struct {
	instanceARN string
	userID      string
	psARN       string
	accounts    []string
}

// resolveICTargets reads (no mutation) the live IC instance, the principal's user ID, the
// permission-set ARN, and the accounts that permission set is already provisioned to — the
// targets a grant/revoke will assign/unassign. Used by both dry-run and apply.
func resolveICTargets(ctx context.Context, ic cloud.IdentityCenter, principal, permissionSet string) (resolvedTargets, error) {
	var t resolvedTargets
	instanceARN, identityStore, err := ic.Instance(ctx)
	if err != nil {
		return t, err
	}
	userID, err := ic.UserID(ctx, identityStore, principal)
	if err != nil {
		return t, err
	}
	psARN, err := ic.PermissionSetARN(ctx, instanceARN, permissionSet)
	if err != nil {
		return t, err
	}
	accounts, err := ic.ProvisionedAccounts(ctx, instanceARN, psARN)
	if err != nil {
		return t, err
	}
	if len(accounts) == 0 {
		return t, fmt.Errorf("permission set %q is provisioned to no accounts — nothing to assign", permissionSet)
	}
	t = resolvedTargets{instanceARN: instanceARN, userID: userID, psARN: psARN, accounts: accounts}
	return t, nil
}

// apexBanner loudly flags an apex-risk borrow (break-glass / access-admin): ADR-088 makes
// these no-synchronous-approval but loud + reviewed-after.
func apexBanner(role string, risk string) {
	if risk != "apex" {
		return
	}
	fmt.Println("  ┌──────────────────────────────────────────────────────────────────────────┐")
	fmt.Printf("  │  ⚠  APEX BREAK-GLASS: %-52s│\n", role)
	fmt.Println("  │  This is a loudly-audited emergency power. ADR-088 requires a mandatory     │")
	fmt.Println("  │  after-action review. The always-on controller would also alert a security │")
	fmt.Println("  │  channel; from the CLI fallback, announce it yourself.                      │")
	fmt.Println("  └──────────────────────────────────────────────────────────────────────────┘")
}

func newAccessGrantCmd() *cobra.Command {
	var team, scope, durStr, reason, profile, region string
	var apply bool

	cmd := &cobra.Command{
		Use:   "grant <person-or-anchor> <role>",
		Short: "Activate (borrow) an eligible power for a bounded window — the controller-down break-glass fallback",
		Long: `Mint a TEMPORARY AWS Identity Center assignment for an eligible on-demand role
(ADR-088). Gated by the same eligibility decision as 'access check'. DEFAULT
--dry-run: it resolves and prints what it WOULD do (live reads, no mutation);
re-run with --apply to mint.

platctl is the controller-down fallback: it CANNOT auto-expire (no daemon). The
window is recorded in a local ledger; you must 'access revoke' at expiry (the
standing drift-detector is the backstop). The always-on controller owns timers,
the Backstage front door + step-up, and the Keycloak/cluster planes (deferred).

  platctl access grant josh break-glass --scope platform --reason "prod incident #123"
  platctl access grant josh break-glass --scope platform --reason "…" --duration 30m --apply`,
		Args:          cobra.ExactArgs(2),
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			who, role := args[0], args[1]
			people, roles, err := loadRegistries()
			if err != nil {
				return err
			}

			var requested time.Duration
			if durStr != "" {
				requested, err = time.ParseDuration(durStr)
				if err != nil {
					return &silentExitError{msg: fmt.Sprintf("invalid --duration %q: %v", durStr, err)}
				}
				if requested <= 0 {
					return &silentExitError{msg: "--duration must be positive"}
				}
			}

			plan, err := access.PlanActivation(people, roles, who, role, team, scope, requested, reason, operatorName(), time.Now())
			if err != nil {
				return &silentExitError{msg: "REFUSED: " + err.Error()}
			}
			a := plan.Activation
			risk := roles[role].RiskTier

			ctx := cmd.Context()
			ic := cloud.IdentityCenter{Profile: profile, Region: region}
			t, err := resolveICTargets(ctx, ic, a.Principal, a.PermissionSet)
			if err != nil {
				return &silentExitError{msg: "resolving AWS Identity Center targets: " + err.Error()}
			}
			a.Accounts = t.accounts

			fmt.Printf("Activation plan — %s borrows %s on %s\n", a.Principal, a.Role, a.Reach)
			apexBanner(role, risk)
			fmt.Printf("  permission set : %s  (%s)\n", a.PermissionSet, t.psARN)
			fmt.Printf("  accounts       : %s\n", joinAccounts(t.accounts))
			fmt.Printf("  window         : %s  (expires %s)\n", a.Window(), a.ExpiresAt.Format(time.RFC3339))
			if plan.Capped {
				fmt.Printf("  note           : requested window capped to the role's %s ceiling\n", a.Window())
			}
			fmt.Printf("  reason         : %s\n", a.Reason)
			fmt.Printf("  operator       : %s\n", a.Operator)

			if !apply {
				fmt.Println("\n(dry-run) no changes made. Re-run with --apply to mint the assignment.")
				return nil
			}

			fmt.Println("\nApplying (assignments are provisioned serially per permission set)…")
			for _, acct := range t.accounts {
				status, err := ic.CreateAssignment(ctx, t.instanceARN, acct, t.psARN, t.userID)
				if err != nil {
					return &silentExitError{msg: "create-account-assignment: " + err.Error()}
				}
				fmt.Printf("  %s → %s\n", acct, status)
			}

			if err := recordActivation(a); err != nil {
				fmt.Printf("⚠ assignment minted but recording to the ledger failed: %v\n", err)
			}
			fmt.Printf("\nGranted. Expires %s — platctl cannot auto-expire; revoke with:\n", a.ExpiresAt.Format(time.RFC3339))
			fmt.Printf("  platctl access revoke %s %s %s --apply\n", a.Principal, a.Role, reachFlag(team, scope))
			if risk == "apex" {
				fmt.Println("⚠ APEX: announce this break-glass now and schedule the after-action review (ADR-088).")
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&team, "team", "", "Team-scoped reach (mutually exclusive with --scope)")
	cmd.Flags().StringVar(&scope, "scope", "", "Platform-scoped reach, e.g. 'platform' (mutually exclusive with --team)")
	cmd.Flags().StringVar(&durStr, "duration", "", "Borrow window, e.g. 30m or 1h (default: the role's sessionDuration cap)")
	cmd.Flags().StringVar(&reason, "reason", "", "Required justification (recorded for audit)")
	cmd.Flags().BoolVar(&apply, "apply", false, "Actually mint the assignment (default: dry-run)")
	cmd.Flags().StringVar(&profile, "profile", "management", "AWS CLI profile (Identity Center is in the management account)")
	cmd.Flags().StringVar(&region, "region", "us-east-1", "Identity Center region")
	return cmd
}

func newAccessRevokeCmd() *cobra.Command {
	var team, scope, profile, region string
	var apply bool

	cmd := &cobra.Command{
		Use:   "revoke <person-or-anchor> <role>",
		Short: "Yank a borrowed power — the kill-switch half of the break-glass fallback",
		Long: `Delete the temporary AWS Identity Center assignment for a borrowed role
(ADR-088 emergency revocation). DEFAULT --dry-run; re-run with --apply.

Targets are taken from the local ledger if present (authoritative for what was
minted), else recomputed from the live permission-set footprint — so revoke
works as a kill-switch even if the ledger was lost. Deleting the assignment
stops NEW federation; invalidating already-issued sessions (the second act of
revocation) is the controller's job — from the CLI, also drop active console
sessions for the principal.

  platctl access revoke josh break-glass --scope platform --apply`,
		Args:          cobra.ExactArgs(2),
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			who, role := args[0], args[1]
			if (team == "") == (scope == "") {
				return &silentExitError{msg: "specify exactly one reach: --team <team> or --scope <scope>"}
			}
			people, roles, err := loadRegistries()
			if err != nil {
				return err
			}
			r, ok := roles[role]
			if !ok {
				return &silentExitError{msg: fmt.Sprintf("role %q is not in the catalog (gitops/roles)", role)}
			}
			if r.PermissionSet == "" {
				return &silentExitError{msg: fmt.Sprintf("role %q has no AWS Identity Center projection", role)}
			}
			// Resolve the principal's IC username from the roster (accept name or anchor).
			principal := who
			for _, p := range people {
				if p.Name == who || p.Anchor == who {
					principal = p.Name
					break
				}
			}
			reach := (access.Grant{Team: team, Scope: scope}).Reach()
			key := principal + "|" + role + "|" + reach

			ctx := cmd.Context()
			ic := cloud.IdentityCenter{Profile: profile, Region: region}
			instanceARN, identityStore, err := ic.Instance(ctx)
			if err != nil {
				return &silentExitError{msg: err.Error()}
			}
			userID, err := ic.UserID(ctx, identityStore, principal)
			if err != nil {
				return &silentExitError{msg: err.Error()}
			}
			psARN, err := ic.PermissionSetARN(ctx, instanceARN, r.PermissionSet)
			if err != nil {
				return &silentExitError{msg: err.Error()}
			}

			// Prefer the ledger's recorded accounts; else the live provisioned footprint.
			ledgerPath, _ := access.LedgerPath()
			ledger, _ := access.LoadLedger(ledgerPath)
			var accounts []string
			for _, x := range ledger {
				if x.Key() == key {
					accounts = x.Accounts
					break
				}
			}
			source := "ledger"
			if len(accounts) == 0 {
				accounts, err = ic.ProvisionedAccounts(ctx, instanceARN, psARN)
				if err != nil {
					return &silentExitError{msg: err.Error()}
				}
				source = "live permission-set footprint (no ledger entry)"
			}
			if len(accounts) == 0 {
				return &silentExitError{msg: "no accounts to revoke from"}
			}

			fmt.Printf("Revoke plan — %s loses %s on %s\n", principal, role, reach)
			fmt.Printf("  permission set : %s  (%s)\n", r.PermissionSet, psARN)
			fmt.Printf("  accounts       : %s  [from %s]\n", joinAccounts(accounts), source)

			if !apply {
				fmt.Println("\n(dry-run) no changes made. Re-run with --apply to delete the assignment.")
				return nil
			}

			fmt.Println("\nApplying…")
			for _, acct := range accounts {
				status, err := ic.DeleteAssignment(ctx, instanceARN, acct, psARN, userID)
				if err != nil {
					return &silentExitError{msg: "delete-account-assignment: " + err.Error()}
				}
				fmt.Printf("  %s → %s\n", acct, status)
			}
			if newLedger, found := access.RemoveFromLedger(ledger, key); found {
				if err := access.SaveLedger(ledgerPath, newLedger); err != nil {
					fmt.Printf("⚠ assignment deleted but updating the ledger failed: %v\n", err)
				}
			}
			fmt.Println("\nRevoked. Deleting the assignment stops new federation; for a full kill-switch")
			fmt.Println("also invalidate the principal's active console sessions (the controller's second act).")
			return nil
		},
	}
	cmd.Flags().StringVar(&team, "team", "", "Team-scoped reach (mutually exclusive with --scope)")
	cmd.Flags().StringVar(&scope, "scope", "", "Platform-scoped reach (mutually exclusive with --team)")
	cmd.Flags().BoolVar(&apply, "apply", false, "Actually delete the assignment (default: dry-run)")
	cmd.Flags().StringVar(&profile, "profile", "management", "AWS CLI profile (Identity Center is in the management account)")
	cmd.Flags().StringVar(&region, "region", "us-east-1", "Identity Center region")
	return cmd
}

func newAccessActiveCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "active",
		Short: "List the temporary grants platctl has minted (the local ledger)",
		Long: `Show the grants this platctl break-glass fallback has minted and not yet
revoked, flagging any past their window (platctl cannot auto-expire — revoke
them, or rely on the standing drift-detector backstop). This is platctl's local
ledger, NOT the controller's durable store.`,
		Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			ledgerPath, err := access.LedgerPath()
			if err != nil {
				return err
			}
			ledger, err := access.LoadLedger(ledgerPath)
			if err != nil {
				return err
			}
			if len(ledger) == 0 {
				fmt.Println("(no active grants in the local ledger)")
				return nil
			}
			now := time.Now()
			w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
			fmt.Fprintln(w, "PRINCIPAL\tROLE\tREACH\tEXPIRES\tSTATE\tREASON")
			for _, a := range ledger {
				state := "active"
				if now.After(a.ExpiresAt) {
					state = "EXPIRED — revoke"
				}
				fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n", a.Principal, a.Role, a.Reach, a.ExpiresAt.Format(time.RFC3339), state, a.Reason)
			}
			return w.Flush()
		},
	}
	return cmd
}

// recordActivation upserts an activation into the local ledger.
func recordActivation(a access.Activation) error {
	path, err := access.LedgerPath()
	if err != nil {
		return err
	}
	ledger, err := access.LoadLedger(path)
	if err != nil {
		return err
	}
	return access.SaveLedger(path, access.UpsertLedger(ledger, a))
}

// reachFlag renders the reach as the flag form for a copy-pasteable revoke hint.
func reachFlag(team, scope string) string {
	if team != "" {
		return "--team " + team
	}
	return "--scope " + scope
}

// joinAccounts renders account IDs compactly.
func joinAccounts(accts []string) string {
	if len(accts) == 0 {
		return "(none)"
	}
	out := accts[0]
	for _, a := range accts[1:] {
		out += ", " + a
	}
	return out
}
