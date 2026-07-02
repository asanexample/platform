// Package hooks implements the pre/post-apply hook execution and manual-step checks that platctl runs around
// Terragrunt units. The declarative shape (which unit gets which hook) is parsed by the config package; this
// package owns the side-effecting execution (AWS CLI / kubectl / terragrunt subprocess calls). Hooks satisfy
// engine.Hook so the engine can invoke them uniformly.
package hooks

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/asanexample/platform/cmd/platctl/internal/cloud"
	"github.com/asanexample/platform/cmd/platctl/internal/config"
	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// CRDTwoStageHook deploys a Helm release in two stages: first the operator
// (to register CRDs), then the full apply. This avoids the chicken-and-egg
// problem where custom resources reference CRDs that don't exist yet.
type CRDTwoStageHook struct {
	Target string // e.g., "helm_release.tailscale_operator[0]"
}

// Execute runs the two-stage CRD bootstrap on apply, or a straight destroy with args.
func (h *CRDTwoStageHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action, args...)
	}

	// Stage 1: deploy only the operator to register CRDs
	stage1Args := append([]string{fmt.Sprintf("-target=%s", h.Target)}, args...)
	if err := runner.Run(ctx, unit, action, stage1Args...); err != nil {
		return fmt.Errorf("CRD stage 1 (operator): %w", err)
	}

	// Stage 2: full apply with bootstrap args (CRDs now exist)
	if err := runner.Run(ctx, unit, action, args...); err != nil {
		return fmt.Errorf("CRD stage 2 (full): %w", err)
	}

	return nil
}

// SecretEntry is a secret name and the auth credentials needed to access it.
type SecretEntry struct {
	ID   string
	Auth map[string]string
}

// SecretCleanupHook force-deletes Secrets Manager secrets that may be left over
// from a previous deployment (pending deletion or orphaned). Runs before apply
// so the module can recreate them cleanly.
type SecretCleanupHook struct {
	Secrets []SecretEntry
	Client  cloud.AWSClient
}

// Execute checks for and force-deletes any existing secrets, then runs the apply.
func (h *SecretCleanupHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action, args...)
	}

	if h.Client == nil {
		return runner.Run(ctx, unit, action, args...)
	}

	for _, secret := range h.Secrets {
		exists, _ := h.Client.SecretExists(ctx, secret.ID, secret.Auth)
		if !exists {
			continue
		}
		fmt.Printf("Cleaning up existing secret %s...\n", secret.ID)
		if err := h.Client.ForceDeleteSecret(ctx, secret.ID, secret.Auth); err != nil {
			return fmt.Errorf("cleaning up secret %s: %w", secret.ID, err)
		}
	}

	return runner.Run(ctx, unit, action, args...)
}

// StatePurgeHook removes resources whose address contains any of the given substrings from the unit's
// Terraform state BEFORE a destroy, then runs the destroy. Used for keycloak-config: the keycloak_* realm /
// client / protocol-mapper / group resources are deleted one-by-one over a port-forward against a Keycloak
// that is itself destroyed wholesale (CNPG database and all) in the very next wave — so the hundreds of
// per-object DELETE calls only serve to time out ("context deadline exceeded" / "Plugin did not respond")
// and fail the teardown. Dropping them from state lets the unit destroy cleanly; the realm content vanishes
// with the database. Apply is a straight pass-through (no purge).
type StatePurgeHook struct {
	Patterns []string // address substrings; any state address containing one is removed before destroy
	Binary   string   // terragrunt binary (defaults to "terragrunt")
}

// Execute purges matching state addresses before destroy; best-effort (never blocks the destroy).
func (h *StatePurgeHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error {
	if action != engine.Destroy || len(h.Patterns) == 0 {
		return runner.Run(ctx, unit, action, args...)
	}

	addrs, err := h.matchingAddrs(ctx, unit)
	if err != nil {
		fmt.Printf("state purge: could not list state for %s (%v) — proceeding with destroy\n", unit.Name, err)
		return runner.Run(ctx, unit, action, args...)
	}
	if len(addrs) > 0 {
		fmt.Printf("state purge: removing %d resource(s) from %s state before destroy (patterns: %s)\n",
			len(addrs), unit.Name, strings.Join(h.Patterns, ","))
		rmArgs := append([]string{"state", "rm"}, addrs...)
		if out, err := h.terragrunt(ctx, unit, rmArgs...); err != nil {
			fmt.Printf("  warning: state rm failed (%v): %s — proceeding with destroy\n", err, strings.TrimSpace(out))
		}
	}
	return runner.Run(ctx, unit, action, args...)
}

func (h *StatePurgeHook) matchingAddrs(ctx context.Context, unit *engine.Unit) ([]string, error) {
	out, err := h.terragrunt(ctx, unit, "state", "list")
	if err != nil {
		return nil, fmt.Errorf("%w: %s", err, strings.TrimSpace(out))
	}
	var addrs []string
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		for _, p := range h.Patterns {
			if strings.Contains(line, p) {
				addrs = append(addrs, line)
				break
			}
		}
	}
	return addrs, nil
}

func (h *StatePurgeHook) terragrunt(ctx context.Context, unit *engine.Unit, args ...string) (string, error) {
	bin := h.Binary
	if bin == "" {
		bin = "terragrunt"
	}
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Dir = unit.Path
	cmd.Env = engine.EnvWithAWSProfile(os.Environ(), unit.Auth)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// ENIIPValidationHook queries EKS ENI IPs and compares them to the values
// in the cross-vpc-dns live unit. Alerts the user if they're stale.
type ENIIPValidationHook struct {
	ClusterName string
	Auth        map[string]string
	Client      cloud.AWSClient
	Interactive bool
}

// Execute validates ENI IPs before applying cross-vpc-dns.
func (h *ENIIPValidationHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action, args...)
	}

	if h.Client == nil {
		return runner.Run(ctx, unit, action, args...)
	}

	ips, err := h.Client.DescribeEKSENIs(ctx, h.ClusterName, h.Auth)
	if err != nil {
		fmt.Printf("Warning: could not query ENI IPs for %s: %v\n", h.ClusterName, err)
		fmt.Println("Proceeding with apply — verify IPs manually if this is a fresh cluster.")
		return runner.Run(ctx, unit, action)
	}

	if len(ips) > 0 {
		fmt.Printf("Discovered ENI IPs for %s: %v\n", h.ClusterName, ips)
		fmt.Println("Verify these match the phz_records IPs in the cross-vpc-dns live unit.")

		if h.Interactive {
			fmt.Print("Continue with apply? [y/N]: ")
			reader := bufio.NewReader(os.Stdin)
			answer, _ := reader.ReadString('\n')
			answer = strings.TrimSpace(answer)
			if answer != "y" && answer != "Y" {
				return fmt.Errorf("aborted: update IPs in cross-vpc-dns terragrunt.hcl first")
			}
		}
	}

	return runner.Run(ctx, unit, action, args...)
}

// ArgoTokenHook re-mints the read-only ArgoCD account token that Backstage's ArgoCD plugin authenticates with,
// after the argocd unit applies. A from-scratch rebuild regenerates the ArgoCD server's signing key, which
// silently invalidates the token sitting in Secrets Manager (minted out-of-band) — so every Backstage ArgoCD
// card goes blank until someone re-mints it. Running this as a post-apply hook on the argocd unit (an EARLY
// wave, before backstage) means the SM secret already holds a valid token by the time backstage's ExternalSecret
// does its first sync — no restart, no ESO force-refresh (which the operate-only PlatformAdmin can't do anyway).
//
// Idempotent: it validates the current SM token first and re-mints only when missing/invalid, so repeated
// applies don't accumulate dead tokens on the account. Best-effort — a failure warns but never fails bootstrap
// (a blank developer-portal card must not block the platform coming up).
type ArgoTokenHook struct {
	Cluster      string // EKS cluster the argocd server runs on (for the temp kubeconfig)
	Region       string
	Profile      string // AWS profile for cluster access + (default) the SM write
	RoleARN      string // kubectl role (PlatformAdmin) — read+exec is sufficient
	Namespace    string // argocd namespace (default "argocd")
	ServerDeploy string // argocd-server deployment (default "argocd-server")
	Account      string // ArgoCD local account (default "backstage")
	SecretID     string // Secrets Manager secret holding the token
	SecretKey    string // JSON key within the secret (default "token")
	SMProfile    string // AWS profile for the SM write (default = Profile)
	SMRegion     string // SM region (default = Region)
}

// Execute applies the unit, then reconciles the ArgoCD token (apply only; destroy is a pass-through).
func (h *ArgoTokenHook) Execute(ctx context.Context, runner engine.Runner, unit *engine.Unit, action engine.Action, args ...string) error {
	if action == engine.Destroy {
		return runner.Run(ctx, unit, action, args...)
	}
	if err := runner.Run(ctx, unit, action, args...); err != nil {
		return err
	}
	if err := h.reconcile(ctx); err != nil {
		fmt.Printf("Warning: ArgoCD %q token reconcile failed: %v\n", h.account(), err)
		fmt.Println("  Backstage ArgoCD cards may stay blank until it's re-minted — see docs/runbooks/backstage-argocd.md")
	}
	return nil
}

func (h *ArgoTokenHook) account() string {
	if h.Account != "" {
		return h.Account
	}
	return "backstage"
}

func (h *ArgoTokenHook) namespace() string {
	if h.Namespace != "" {
		return h.Namespace
	}
	return "argocd"
}

func (h *ArgoTokenHook) serverDeploy() string {
	if h.ServerDeploy != "" {
		return h.ServerDeploy
	}
	return "argocd-server"
}

func (h *ArgoTokenHook) secretKey() string {
	if h.SecretKey != "" {
		return h.SecretKey
	}
	return "token"
}

// reconcile validates the current token and re-mints only if missing/invalid.
func (h *ArgoTokenHook) reconcile(ctx context.Context) error {
	if h.SecretID == "" || h.Cluster == "" {
		return fmt.Errorf("misconfigured: secret_id and cluster are required")
	}
	if !isSafeAccountName(h.account()) {
		return fmt.Errorf("unsafe account name %q", h.account())
	}

	kubeconfig, cleanup, err := h.writeKubeconfig(ctx)
	if err != nil {
		return fmt.Errorf("cluster access: %w", err)
	}
	defer cleanup()

	cur, exists := h.currentToken(ctx)
	if cur != "" && h.tokenValid(ctx, kubeconfig, cur) {
		fmt.Printf("ArgoCD %q token still valid — leaving it in place.\n", h.account())
		return nil
	}

	token, err := h.mint(ctx, kubeconfig)
	if err != nil {
		return fmt.Errorf("minting token: %w", err)
	}
	if err := h.putToken(ctx, token, exists); err != nil {
		return fmt.Errorf("writing %s: %w", h.SecretID, err)
	}
	fmt.Printf("Re-minted ArgoCD %q token -> %s (Backstage picks it up on first sync).\n", h.account(), h.SecretID)
	return nil
}

// writeKubeconfig builds a throwaway kubeconfig for the argocd cluster (bootstrap runs before the persistent
// kubectl contexts are configured, so we can't assume one exists).
func (h *ArgoTokenHook) writeKubeconfig(ctx context.Context) (string, func(), error) {
	tmp, err := os.CreateTemp("", "platctl-argo-kubeconfig-*.yaml")
	if err != nil {
		return "", func() {}, err
	}
	path := tmp.Name()
	_ = tmp.Close()
	cleanup := func() { _ = os.Remove(path) }

	args := []string{"eks", "update-kubeconfig", "--name", h.Cluster, "--region", h.Region,
		"--kubeconfig", path, "--alias", "platctl-argo"}
	if h.RoleARN != "" {
		args = append(args, "--role-arn", h.RoleARN)
	}
	if h.Profile != "" {
		args = append(args, "--profile", h.Profile)
	}
	if out, err := runCmd(ctx, nil, "aws", args...); err != nil {
		cleanup()
		return "", func() {}, fmt.Errorf("%w: %s", err, strings.TrimSpace(out))
	}
	return path, cleanup, nil
}

// currentToken reads the token currently in Secrets Manager. The bool reports whether the secret exists at all
// (drives create-secret vs put-secret-value).
func (h *ArgoTokenHook) currentToken(ctx context.Context) (string, bool) {
	args := []string{"secretsmanager", "get-secret-value", "--secret-id", h.SecretID,
		"--query", "SecretString", "--output", "text", "--region", h.smRegion()}
	if p := h.smProfile(); p != "" {
		args = append(args, "--profile", p)
	}
	out, err := runCmd(ctx, nil, "aws", args...)
	if err != nil {
		return "", false // not found (or unreadable) — treat as absent
	}
	return parseTokenJSON(out, h.secretKey()), true
}

// tokenValid asks the argocd server (via the CLI baked into argocd-server, over localhost) whether the token
// authenticates. Matches the live `Logged In: true` line from `argocd account get-user-info`.
func (h *ArgoTokenHook) tokenValid(ctx context.Context, kubeconfig, token string) bool {
	out, err := runCmd(ctx, nil, "kubectl", "--kubeconfig", kubeconfig, "exec",
		"-n", h.namespace(), "deploy/"+h.serverDeploy(), "--",
		"argocd", "account", "get-user-info", "--auth-token", token,
		"--server", "localhost:8080", "--plaintext")
	if err != nil {
		return false
	}
	return userInfoLoggedIn(out)
}

// mint logs in as admin inside the argocd-server pod and generates a fresh token for the account. The admin
// password is piped over stdin (never placed in argv) so it can't leak via the process table or shell quoting.
func (h *ArgoTokenHook) mint(ctx context.Context, kubeconfig string) (string, error) {
	pwB64, err := runCmd(ctx, nil, "kubectl", "--kubeconfig", kubeconfig, "get", "secret",
		"argocd-initial-admin-secret", "-n", h.namespace(), "-o", "jsonpath={.data.password}")
	if err != nil {
		return "", fmt.Errorf("reading admin secret: %w: %s", err, strings.TrimSpace(pwB64))
	}
	pw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(pwB64))
	if err != nil {
		return "", fmt.Errorf("decoding admin password: %w", err)
	}
	script := "IFS= read -r PW; argocd login localhost:8080 --username admin --password \"$PW\" " +
		"--plaintext --insecure >/dev/null 2>&1 && argocd account generate-token --account " + h.account()
	out, err := runCmd(ctx, strings.NewReader(string(pw)+"\n"), "kubectl", "--kubeconfig", kubeconfig,
		"exec", "-i", "-n", h.namespace(), "deploy/"+h.serverDeploy(), "--", "sh", "-c", script)
	if err != nil {
		return "", fmt.Errorf("%w: %s", err, strings.TrimSpace(out))
	}
	token := strings.TrimSpace(out)
	if !strings.HasPrefix(token, "eyJ") {
		return "", fmt.Errorf("unexpected token output (not a JWT): %s", firstLine(token))
	}
	return token, nil
}

// putToken upserts the token into Secrets Manager as {"<key>": "<token>"}.
func (h *ArgoTokenHook) putToken(ctx context.Context, token string, exists bool) error {
	payload, err := json.Marshal(map[string]string{h.secretKey(): token})
	if err != nil {
		return err
	}
	var args []string
	if exists {
		args = []string{"secretsmanager", "put-secret-value", "--secret-id", h.SecretID,
			"--secret-string", string(payload), "--region", h.smRegion()}
	} else {
		args = []string{"secretsmanager", "create-secret", "--name", h.SecretID,
			"--secret-string", string(payload), "--region", h.smRegion()}
	}
	if p := h.smProfile(); p != "" {
		args = append(args, "--profile", p)
	}
	if out, err := runCmd(ctx, nil, "aws", args...); err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(out))
	}
	return nil
}

func (h *ArgoTokenHook) smProfile() string {
	if h.SMProfile != "" {
		return h.SMProfile
	}
	return h.Profile
}

func (h *ArgoTokenHook) smRegion() string {
	if h.SMRegion != "" {
		return h.SMRegion
	}
	return h.Region
}

// parseTokenJSON extracts a single key from a Secrets Manager JSON string. Returns "" if absent/unparseable.
func parseTokenJSON(secretString, key string) string {
	var m map[string]string
	if err := json.Unmarshal([]byte(strings.TrimSpace(secretString)), &m); err != nil {
		return ""
	}
	return m[key]
}

// userInfoLoggedIn reports whether `argocd account get-user-info` shows an authenticated session.
func userInfoLoggedIn(out string) bool {
	for _, line := range strings.Split(out, "\n") {
		if strings.EqualFold(strings.TrimSpace(line), "Logged In: true") {
			return true
		}
	}
	return false
}

// isSafeAccountName guards the account name interpolated into the in-pod shell command.
func isSafeAccountName(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_') {
			return false
		}
	}
	return true
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

// runCmd runs a command with optional stdin and returns combined output. Indirected through a var so tests can
// stub the process boundary.
var runCmd = func(ctx context.Context, stdin io.Reader, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	if stdin != nil {
		cmd.Stdin = stdin
	}
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// ManualStepChecker verifies that manual prerequisites have been completed.
type ManualStepChecker struct {
	Client   cloud.Client
	RepoRoot string
}

// Check evaluates a manual step's check condition.
// Returns true if the prerequisite is satisfied.
func (c *ManualStepChecker) Check(ctx context.Context, step config.ManualStep) (bool, error) {
	switch step.Check.Type {
	case "secret_exists":
		if c.Client == nil {
			return false, nil
		}
		return c.Client.SecretExists(ctx, step.Check.SecretID, map[string]string{
			"profile": step.Check.Profile,
		})

	case "file_contains":
		filePath := step.Check.File
		if c.RepoRoot != "" && !strings.HasPrefix(filePath, "/") {
			filePath = c.RepoRoot + "/" + filePath
		}
		data, err := os.ReadFile(filePath)
		if err != nil {
			return false, nil
		}
		return strings.Contains(string(data), step.Check.Pattern), nil

	default:
		return false, fmt.Errorf("unknown check type: %s", step.Check.Type)
	}
}

// ResolveHook creates an engine.Hook implementation from a unit's config override settings.
func ResolveHook(override config.UnitOverride, awsClient cloud.AWSClient, interactive bool) engine.Hook {
	switch override.Hook {
	case "crd_two_stage":
		return &CRDTwoStageHook{Target: override.HookTarget}

	case "eni_ip_validation":
		auth := make(map[string]string)
		for k, v := range override.HookConfig {
			auth[k] = v
		}
		return &ENIIPValidationHook{
			ClusterName: override.HookConfig["cluster_name"],
			Auth:        auth,
			Client:      awsClient,
			Interactive: interactive,
		}

	case "state_purge":
		var patterns []string
		if raw, ok := override.HookConfig["patterns"]; ok {
			for _, p := range strings.Split(raw, ",") {
				if p = strings.TrimSpace(p); p != "" {
					patterns = append(patterns, p)
				}
			}
		}
		return &StatePurgeHook{Patterns: patterns}

	case "secret_cleanup":
		defaultProfile := override.HookConfig["profile"]
		var secrets []SecretEntry
		if raw, ok := override.HookConfig["secrets"]; ok {
			for _, s := range strings.Split(raw, ",") {
				s = strings.TrimSpace(s)
				if s == "" {
					continue
				}
				// Format: "secret_id" or "secret_id@profile"
				entry := SecretEntry{Auth: map[string]string{}}
				if idx := strings.LastIndex(s, "@"); idx > 0 {
					entry.ID = s[:idx]
					entry.Auth["profile"] = s[idx+1:]
				} else {
					entry.ID = s
					if defaultProfile != "" {
						entry.Auth["profile"] = defaultProfile
					}
				}
				secrets = append(secrets, entry)
			}
		}
		return &SecretCleanupHook{
			Secrets: secrets,
			Client:  awsClient,
		}

	case "argocd_account_token":
		c := override.HookConfig
		return &ArgoTokenHook{
			Cluster:      c["cluster"],
			Region:       c["region"],
			Profile:      c["profile"],
			RoleARN:      c["role_arn"],
			Namespace:    c["namespace"],
			ServerDeploy: c["server_deploy"],
			Account:      c["account"],
			SecretID:     c["secret_id"],
			SecretKey:    c["secret_key"],
			SMProfile:    c["sm_profile"],
			SMRegion:     c["sm_region"],
		}

	default:
		return nil
	}
}
