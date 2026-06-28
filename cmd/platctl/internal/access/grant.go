package access

// grant.go is the ACTIVATION side of the ADR-088 temporary-power model — the pure
// (no-AWS) half of `platctl access grant`/`revoke`. It turns an eligibility decision +
// a requested window into a concrete Activation (principal, AWS permission set, capped
// TTL) and persists outstanding activations to a local ledger. The live AWS Identity
// Center mutation lives in the cloud package; the CLI wires the two together.
//
// platctl is the CONTROLLER-DOWN break-glass fallback (ADR-088 "Why not platctl as the
// controller"): it cannot run a TTL timer, so it mints + records but cannot auto-expire.
// Expiry is a deliberate `revoke` (or the standing drift-detector backstop). The
// always-on controller — with timers, the Backstage front door, step-up, and the
// Keycloak/cluster planes — is deferred.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// DefaultDuration is used when neither a --duration nor a role sessionDuration cap is set.
const DefaultDuration = time.Hour

// Activation is one borrowed-power window — the record `grant` mints and `revoke` clears.
// It is platctl's lightweight stand-in for the controller's durable Postgres store
// (ADR-088): enough to drive revoke and leave a local audit trail, explicitly NOT the
// system of record.
type Activation struct {
	Principal     string    `json:"principal"`     // AWS Identity Center username = Person.Name
	Anchor        string    `json:"anchor"`        // Keycloak anchor (audit only)
	Role          string    `json:"role"`          // WorkforceRole name
	Reach         string    `json:"reach"`         // rendered reach, e.g. "team:alpha" or "platform"
	Team          string    `json:"team"`          // raw reach inputs (so revoke can recompute targets)
	Scope         string    `json:"scope"`         //
	PermissionSet string    `json:"permissionSet"` // AWS IC permission set name (the grant target)
	Reason        string    `json:"reason"`        // required justification (audit)
	Operator      string    `json:"operator"`      // who ran the command (audit)
	GrantedAt     time.Time `json:"grantedAt"`
	ExpiresAt     time.Time `json:"expiresAt"`
	Accounts      []string  `json:"accounts,omitempty"` // accounts the assignment was minted on (filled at apply)
}

// Key identifies an activation for ledger matching — a principal can hold at most one
// active grant of a given role at a given reach.
func (a Activation) Key() string { return a.Principal + "|" + a.Role + "|" + a.Reach }

// Window renders the granted TTL (capped) as a friendly string.
func (a Activation) Window() string { return a.ExpiresAt.Sub(a.GrantedAt).String() }

// ParseSessionDuration parses an ISO-8601 time-only duration as used by the role catalog's
// identityCenter.sessionDuration ("PT1H", "PT4H", "PT30M", "PT1H30M"). The date part is not
// used by the catalog and is rejected. Returns 0 for an empty string (no cap).
func ParseSessionDuration(s string) (time.Duration, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, nil
	}
	rest, ok := strings.CutPrefix(strings.ToUpper(s), "PT")
	if !ok || rest == "" {
		return 0, fmt.Errorf("not an ISO-8601 time duration (want e.g. PT1H): %q", s)
	}
	var total time.Duration
	num := ""
	for _, r := range rest {
		switch {
		case r >= '0' && r <= '9':
			num += string(r)
		case r == 'H' || r == 'M' || r == 'S':
			if num == "" {
				return 0, fmt.Errorf("malformed duration %q", s)
			}
			n, err := strconv.Atoi(num)
			if err != nil {
				return 0, fmt.Errorf("malformed duration %q: %w", s, err)
			}
			switch r {
			case 'H':
				total += time.Duration(n) * time.Hour
			case 'M':
				total += time.Duration(n) * time.Minute
			case 'S':
				total += time.Duration(n) * time.Second
			}
			num = ""
		default:
			return 0, fmt.Errorf("unexpected %q in duration %q", string(r), s)
		}
	}
	if num != "" {
		return 0, fmt.Errorf("trailing number without unit in duration %q", s)
	}
	return total, nil
}

// PlanResult is the outcome of PlanActivation — the activation to mint, plus whether the
// requested window was capped down to the role's sessionDuration ceiling.
type PlanResult struct {
	Activation Activation
	Capped     bool          // the requested window exceeded the role cap and was reduced
	Cap        time.Duration // the role's sessionDuration cap (0 = none)
}

// PlanActivation gates a borrow request through the SAME eligibility decision the read
// side exposes (Eligible), then builds the Activation to mint. It is pure: no AWS, no
// clock of its own (now is injected). The live account targets are resolved later, from
// AWS, by the CLI/cloud layer.
//
// A request is refused unless the principal is eligible to BORROW the role at the reach
// (a standing holder needs no borrow), the role has an AWS Identity Center projection
// (the only plane platctl covers), and a reason is given. requested<=0 means "use the
// role's cap" (or DefaultDuration if the role sets none).
func PlanActivation(people []Person, roles map[string]Role, who, role, team, scope string, requested time.Duration, reason, operator string, now time.Time) (PlanResult, error) {
	if strings.TrimSpace(reason) == "" {
		return PlanResult{}, fmt.Errorf("a --reason is required (it is the audit record for a borrowed power)")
	}
	if d := Eligible(people, roles, who, role, team, scope); !d.Allowed {
		return PlanResult{}, fmt.Errorf("%s", d.Reason)
	}
	p, _ := find(people, who) // Eligible already validated existence
	r := roles[role]
	if r.PermissionSet == "" {
		return PlanResult{}, fmt.Errorf("role %q has no AWS Identity Center projection; platctl grant covers only the AWS plane (ADR-088) — the Keycloak/cluster planes are the activation controller's", role)
	}

	capDur, err := ParseSessionDuration(r.SessionDuration)
	if err != nil {
		return PlanResult{}, fmt.Errorf("role %q has an invalid sessionDuration: %w", role, err)
	}
	eff := requested
	if eff <= 0 {
		eff = capDur
	}
	if eff <= 0 {
		eff = DefaultDuration
	}
	capped := false
	if capDur > 0 && eff > capDur {
		eff = capDur
		capped = true
	}

	a := Activation{
		Principal:     p.Name,
		Anchor:        p.Anchor,
		Role:          role,
		Reach:         (Grant{Team: team, Scope: scope}).Reach(),
		Team:          team,
		Scope:         scope,
		PermissionSet: r.PermissionSet,
		Reason:        strings.TrimSpace(reason),
		Operator:      operator,
		GrantedAt:     now,
		ExpiresAt:     now.Add(eff),
	}
	return PlanResult{Activation: a, Capped: capped, Cap: capDur}, nil
}

// ---- the local ledger (platctl's lightweight active-grant store) --------------------

// LedgerPath returns the activations ledger path: $PLATCTL_STATE_DIR/activations.json,
// else ~/.platctl/activations.json.
func LedgerPath() (string, error) {
	dir := os.Getenv("PLATCTL_STATE_DIR")
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("locating home dir for the activation ledger: %w", err)
		}
		dir = filepath.Join(home, ".platctl")
	}
	return filepath.Join(dir, "activations.json"), nil
}

// LoadLedger reads the active-activation ledger; a missing file is an empty ledger.
func LoadLedger(path string) ([]Activation, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("reading ledger %s: %w", path, err)
	}
	var out []Activation
	if len(b) == 0 {
		return nil, nil
	}
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, fmt.Errorf("parsing ledger %s: %w", path, err)
	}
	return out, nil
}

// SaveLedger writes the ledger, creating the parent dir, sorted for a stable file.
func SaveLedger(path string, acts []Activation) error {
	sort.Slice(acts, func(i, j int) bool { return acts[i].Key() < acts[j].Key() })
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("creating ledger dir: %w", err)
	}
	b, err := json.MarshalIndent(acts, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o600)
}

// UpsertLedger adds (or replaces) an activation by Key.
func UpsertLedger(acts []Activation, a Activation) []Activation {
	out := make([]Activation, 0, len(acts)+1)
	for _, x := range acts {
		if x.Key() != a.Key() {
			out = append(out, x)
		}
	}
	return append(out, a)
}

// RemoveFromLedger drops the activation matching key, reporting whether one was present.
func RemoveFromLedger(acts []Activation, key string) ([]Activation, bool) {
	out := make([]Activation, 0, len(acts))
	found := false
	for _, x := range acts {
		if x.Key() == key {
			found = true
			continue
		}
		out = append(out, x)
	}
	return out, found
}
