package cli

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/asanexample/platform/cmd/platctl/internal/config"
	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// NewDownCmd parks an environment by scaling its managed node groups to zero. The EKS control plane and all EBS
// volumes survive, so it is non-destructive and reversible with `platctl up`. See the cost-optimization plan.
func NewDownCmd() *cobra.Command {
	var envName string
	var yes bool

	cmd := &cobra.Command{
		Use:   "down --env <env>",
		Short: "Park an environment: scale its node groups to zero (keeps the cluster + data)",
		Long: `Scales every managed node group in the environment's cluster to desiredSize=0, minSize=0 via the
EKS API, and stops the env's SSM bastion (a standing EC2 instance outside the node groups) for a truly cost-zero
park. The control plane and all EBS volumes (e.g. CNPG databases) are preserved, and pods reschedule when you run
'platctl up --env <env>' (which also restarts the bastion). Non-destructive and reversible — for parking an idle
environment overnight. To release all cost (~$0), use 'platctl teardown --env <env>' instead.`,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if envName == "" {
				return fmt.Errorf("--env is required (e.g. --env preprod)")
			}
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}
			cfg, err := config.Load(resolveConfig(cmd, repoRoot))
			if err != nil {
				return fmt.Errorf("loading config: %w", err)
			}
			kc, err := kubeconfigForEnv(cfg, envName)
			if err != nil {
				return err
			}
			// Fail fast on a stale/expired AWS session BEFORE the confirmation prompt or any mutation — see
			// checkAWSCredentials for why this matters (2026-07-02 incident).
			if err := checkAWSCredentialsForEnv(cfg, envName, kc, false); err != nil {
				return err
			}
			if !yes && !confirmDown(envName, kc.Cluster) {
				fmt.Println("Aborted.")
				return nil
			}
			// Drain Karpenter-managed nodes BEFORE the managed groups scale to zero — otherwise the controller
			// (on the system group) dies mid-park and leaves orphaned EC2 instances. No-op without Karpenter.
			// A failed drain is FATAL (not a warning) — see drainKarpenterOrFail.
			if err := drainKarpenterOrFail(context.Background(), kc); err != nil {
				return err
			}
			if err := scaleNodeGroupsToZero(kc); err != nil {
				return err
			}
			// True cost-zero: the node groups are the big spend, but the SSM bastion is a standing EC2 instance
			// outside their scope — stop it too (started again by 'up'). Best-effort; no-op when there's no bastion.
			if err := setBastionPowerFn(kc, false); err != nil {
				fmt.Printf("  warning: stopping SSM bastion: %v\n", err)
			}
			return nil
		},
	}

	cmd.Flags().StringVar(&envName, "env", "", "Environment to park (required)")
	cmd.Flags().BoolVar(&yes, "yes", false, "Skip the confirmation prompt")
	return cmd
}

// NewUpCmd restores a parked environment's node groups to their configured sizes by re-applying the node-groups
// unit (the HCL is the source of truth, so the API-induced scaling drift self-heals).
func NewUpCmd() *cobra.Command {
	var envName string

	cmd := &cobra.Command{
		Use:   "up --env <env>",
		Short: "Restore a parked environment's node groups to their configured sizes",
		Long: `Re-applies the environment's node-groups unit (terragrunt apply), restoring the desired/min sizes
from the HCL — the inverse of 'platctl down'. Takes ~1-2 minutes.`,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if envName == "" {
				return fmt.Errorf("--env is required (e.g. --env preprod)")
			}
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}
			cfg, err := config.Load(resolveConfig(cmd, repoRoot))
			if err != nil {
				return fmt.Errorf("loading config: %w", err)
			}
			env, ok := cfg.Environments[envName]
			if !ok {
				return fmt.Errorf("environment %q is not defined in the config", envName)
			}
			// Resolve the kubeconfig entry once up front (used by the credential preflight below and every
			// kubectl-touching step later) instead of the several best-effort re-resolutions this used to have —
			// a missing kubeconfig entry for the env is a real config error, not something to silently skip past.
			kc, err := kubeconfigForEnv(cfg, envName)
			if err != nil {
				return err
			}
			// Fail fast on a stale/expired AWS session BEFORE any mutation. 'up' uses TWO distinct profiles — the
			// terragrunt auth profile (e.g. "management", for the node-groups/karpenter applies below) and kc.Profile
			// (for the AWS CLI/kubectl calls in waitForClusterAPI/assertKarpenterReady/recoverKyverno) — so check
			// both. See checkAWSCredentials for why this matters (2026-07-02 incident).
			if err := checkAWSCredentialsForEnv(cfg, envName, kc, true); err != nil {
				return err
			}
			unit := &engine.Unit{
				Name:     envName + "/node-groups",
				Path:     filepath.Join(repoRoot, env.Path, "node-groups"),
				Provider: env.Provider,
				Auth:     cfg.AuthForUnit(envName, "node-groups"),
			}
			fmt.Printf("Restoring %s node groups (terragrunt apply, ~1-2 min)...\n", envName)
			runner := &engine.TerragruntRunner{
				LogWriter: func(_ string, data []byte) { fmt.Print(string(data)) },
			}
			ctx := context.Background()
			if err := runner.Run(ctx, unit, engine.Apply); err != nil {
				return err
			}
			// Start the SSM bastion that 'down' stopped (outside the node-group scope, so the apply above doesn't
			// touch it). Best-effort + early, so SSM access is available while the rest of the cluster comes back.
			if err := setBastionPowerFn(kc, true); err != nil {
				fmt.Printf("  warning: starting SSM bastion: %v\n", err)
			}
			// Restore the Karpenter NodePool that 'platctl down' deletes to drain Karpenter's nodes (so the
			// cluster regains node autoscaling). No-op if this env has no karpenter unit.
			kpPath := filepath.Join(repoRoot, env.Path, "karpenter")
			if _, statErr := os.Stat(kpPath); statErr == nil {
				// The karpenter apply uses the helm/kubernetes providers, so it needs the cluster API — which,
				// for a private cluster, is fronted by the in-cluster Tailscale subnet router that only comes
				// back once the restored system nodes are Ready. Applying before then fails AND leaves karpenter's
				// helm releases orphaned from TF state (a "cannot re-use a name" trap needing manual import, #660).
				// Gate the apply on API readiness; on timeout we skip it (node groups are already restored) and
				// tell the operator to re-run, rather than apply into an unreachable API and corrupt state.
				if err := waitForClusterAPI(ctx, kc); err != nil {
					return err
				}
				kpUnit := &engine.Unit{
					Name:     envName + "/karpenter",
					Path:     kpPath,
					Provider: env.Provider,
					Auth:     cfg.AuthForUnit(envName, "karpenter"),
				}
				fmt.Printf("Restoring %s Karpenter NodePool (terragrunt apply)...\n", envName)
				// 'down' deletes the NodePool CR via kubectl to drain Karpenter's nodes, but leaves the helm
				// release that renders it untouched in TF state — so a plain apply sees no release change and does
				// NOT recreate the deleted NodePool (an apply reports "0 changed" and the cluster comes back with
				// no autoscaling). Force-replace the nodepool release so the NodePool always returns. The address
				// is the karpenter module's resource (count-indexed); keep in sync if the module is restructured.
				if err := runner.Run(ctx, kpUnit, engine.Apply, "-replace=helm_release.nodepool[0]"); err != nil {
					return err
				}
				// Health gate: a Ready=False NodePool — e.g. its EC2NodeClass missing — provisions NOTHING and
				// silently strands every workload pod. (2026-06-27: 'down' deleted only the NodePool, leaving the
				// EC2NodeClass for this force-replace to lose to a finalizer race → NodeClassReady=False. 'down'
				// now deletes both for a clean recreate, but assert it actually took before declaring restored.)
				// assertKarpenterReady attempts automated recovery itself before giving up (2026-07-02 incident);
				// this only warns if THAT also failed.
				if err := assertKarpenterReadyFn(ctx, kc); err != nil {
					fmt.Printf("  ⚠️ %v\n", err)
				}
			}
			// Post-unpark workload recovery: the fail-closed Kyverno image-verification webhook can cache a
			// failed sigstore TUF init while the network is still settling, blocking every policed workload pod
			// (0 pods created) until Kyverno is restarted (#665). Best-effort — workloads otherwise recover only
			// after the ReplicaSet backoff.
			if err := recoverKyverno(ctx, kc); err != nil {
				fmt.Printf("  warning: post-unpark Kyverno recovery: %v\n", err)
			}
			// Repair the cross-environment path a park/restore can leave stale (e.g. platform→preprod cross-VPC
			// DNS + the ArgoCD controller's cached connection). Idempotent; no-op when not configured.
			if env.Reconnect != nil {
				return runReconnect(ctx, cfg, repoRoot, envName, env.Reconnect, runner)
			}
			return nil
		},
	}

	cmd.Flags().StringVar(&envName, "env", "", "Environment to restore (required)")
	return cmd
}

// checkAWSCredentialsFn is indirected so tests can stub the aws CLI boundary.
var checkAWSCredentialsFn = checkAWSCredentials

// checkAWSCredentials verifies the given AWS profile has a live, non-expired session by making one cheap,
// read-only STS call, so down/up can fail fast BEFORE running any mutating step.
//
// A stale static credential env var (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN) shadows
// --profile in the AWS CLI/SDK's credential chain and SURVIVES a fresh `aws sso login` (the login refreshes the
// SSO cache, not the already-exported env vars) — so without this check, a stale session degrades into a
// mid-run ExpiredToken on whichever step happens to call `aws`/`kubectl` first. On 2026-07-02 this hit 'down'
// mid-Karpenter-drain; the failure was swallowed as a printed warning and 'down' still reported the park as
// successful, leaving a half-deleted EC2NodeClass that corrupted the next 'up' (see the cluster-parking skill's
// Learnings log). Failing fast here, before any mutation, stops that class of incident at the source.
func checkAWSCredentials(profile, region string) error {
	out, err := exec.Command("aws", "sts", "get-caller-identity",
		"--region", region, "--profile", profile, "--query", "Account", "--output", "text").CombinedOutput()
	if err != nil {
		return fmt.Errorf("AWS credentials for profile %q are not valid: %v\n%s\n"+
			"Run `aws sso login --profile %s` and retry. If that doesn't fix it, a stale "+
			"AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN in the shell environment is shadowing "+
			"--profile and surviving the sso login refresh — `unset` those three and retry",
			profile, err, strings.TrimSpace(string(out)), profile)
	}
	return nil
}

// checkAWSCredentialsForEnv validates every distinct AWS profile a down/up run for this environment will use:
// always kc.Profile (the per-account profile behind every AWS CLI/kubectl call in this file), and — for 'up',
// via includeTerragruntProfile — also the separate terragrunt auth profile (e.g. "management", which assumes
// PlatformDeployer for the node-groups/karpenter applies; see .platctl.yaml.example). These commonly differ, and
// a stale session on EITHER one degrades into a mid-run ExpiredToken, so both need checking. Deduplicates when
// they're the same profile.
func checkAWSCredentialsForEnv(cfg *config.Config, envName string, kc config.KubeconfigEntry, includeTerragruntProfile bool) error {
	profiles := []string{kc.Profile}
	if includeTerragruntProfile {
		if p := cfg.AuthForUnit(envName, "node-groups")["profile"]; p != "" && p != kc.Profile {
			profiles = append(profiles, p)
		}
	}
	for _, p := range profiles {
		if err := checkAWSCredentialsFn(p, kc.Region); err != nil {
			return err
		}
	}
	return nil
}

// waitForClusterAPI polls the cluster API until it answers, so 'up' doesn't apply the API-dependent karpenter
// unit before the restored nodes (and the in-cluster Tailscale subnet router fronting the private endpoint) are
// back — which fails the apply and orphans karpenter's helm releases from TF state (#660). Returns an error on
// timeout so the caller skips the karpenter apply rather than applying into an unreachable API and corrupting
// state. Indirected through waitForClusterAPIFn so tests can stub the kubectl boundary.
var waitForClusterAPIFn = doWaitForClusterAPI

func waitForClusterAPI(ctx context.Context, kc config.KubeconfigEntry) error {
	return waitForClusterAPIFn(ctx, kc)
}

func doWaitForClusterAPI(ctx context.Context, kc config.KubeconfigEntry) error {
	path, cleanup, err := tempKubeconfig(ctx, kc, "platctl-ready")
	if err != nil {
		return err
	}
	defer cleanup()

	fmt.Println("  waiting for the cluster API to become reachable (restored nodes + Tailscale router)...")
	for i := 0; i < 90; i++ { // up to ~15 min — exits as soon as the API answers
		out, qErr := exec.CommandContext(ctx, "kubectl", "--kubeconfig", path,
			"get", "ns", "--request-timeout=10s", "-o", "name").CombinedOutput()
		if qErr == nil && strings.Contains(string(out), "namespace/") {
			fmt.Println("  cluster API reachable.")
			return nil
		}
		time.Sleep(10 * time.Second)
	}
	return fmt.Errorf("cluster API for %s not reachable after ~15m; node groups are restored but the karpenter "+
		"apply was skipped to avoid orphaning its helm releases — re-run 'platctl up' once nodes/Tailscale are up",
		kc.Cluster)
}

// assertKarpenterReadyFn is indirected so tests can stub the kubectl boundary.
var assertKarpenterReadyFn = assertKarpenterReady

// assertKarpenterReady polls until the EC2NodeClass exists AND every NodePool reports Ready=True — i.e. workload
// scheduling is genuinely restored. A Ready=False NodePool (e.g. a missing EC2NodeClass) provisions nothing and
// silently strands every workload pod, so this is the post-unpark gate.
//
// If it's not ready after the initial ~3m poll, it attempts the automated recovery proven live on 2026-07-02
// before giving up: Karpenter's own termination reconciler can deadlock on a stuck NodeClaim (observed live: no
// termination-controller activity for 10+ minutes even after the backing EC2 instance was confirmed terminated
// in AWS) — restarting the controller pod unstuck it in under 30s. And a helm destroy+recreate race (the
// NodePool release momentarily vanishing while a NodeClaim already existed under the old EC2NodeClass) can leave
// the EC2NodeClass fully deleted with nothing recreating it — recreating it from the karpenter-nodepool release's
// own rendered manifest (`helm get manifest | kubectl apply -f -`) fixes that, mirroring the 2026-06-27 manual
// recovery. Only returns an error — with the same manual commands, for a human to run — if both attempts fail.
func assertKarpenterReady(ctx context.Context, kc config.KubeconfigEntry) error {
	path, cleanup, err := tempKubeconfig(ctx, kc, "platctl-karpenter")
	if err != nil {
		return err
	}
	defer cleanup()
	fmt.Println("  verifying Karpenter is ready (EC2NodeClass present + NodePool(s) Ready)...")

	check := func() (string, []string) {
		nc, _ := exec.CommandContext(ctx, "kubectl", "--kubeconfig", path, "get", "ec2nodeclass", "-o", "name").CombinedOutput()
		np, _ := exec.CommandContext(ctx, "kubectl", "--kubeconfig", path, "get", "nodepool",
			"-o", `jsonpath={range .items[*]}{.status.conditions[?(@.type=="Ready")].status} {end}`).CombinedOutput()
		return strings.TrimSpace(string(nc)), strings.Fields(string(np))
	}
	sleep := func() { time.Sleep(10 * time.Second) }

	if ready, _, _ := pollKarpenterReady(check, 18, sleep); ready { // up to ~3 min for Karpenter to reconcile the recreated CRs
		fmt.Println("  Karpenter ready: EC2NodeClass present, NodePool(s) Ready=True.")
		return nil
	}

	fmt.Println("  ⚠️ Karpenter not ready after ~3m — attempting automated recovery " +
		"(restart the controller, reconcile the EC2NodeClass)...")
	if rErr := restartKarpenterControllerFn(ctx, path); rErr != nil {
		fmt.Printf("    warning: restarting the Karpenter controller: %v\n", rErr)
	}
	ready, nodeClasses, statuses := pollKarpenterReady(check, 12, sleep) // ~2 min for the fresh controller to reconcile
	if ready {
		fmt.Println("  Karpenter recovered after restarting its controller.")
		return nil
	}
	if nodeClasses == "" { // the EC2NodeClass is fully gone (the 2026-07-02 asymmetry) — recreate it from the release
		if mErr := reapplyKarpenterNodepoolManifestFn(ctx, path); mErr != nil {
			fmt.Printf("    warning: reapplying the karpenter-nodepool manifest: %v\n", mErr)
		} else if ready, nodeClasses, statuses = pollKarpenterReady(check, 12, sleep); ready {
			fmt.Println("  Karpenter recovered after recreating its EC2NodeClass.")
			return nil
		}
	}

	return fmt.Errorf("Karpenter NOT ready after automated recovery attempts — workload pods will be stranded "+
		"Pending (ec2nodeclass present=%t, nodepool Ready=%v). Manual recovery:\n"+
		"     kubectl delete pod -n karpenter -l app.kubernetes.io/name=karpenter   # restart the controller\n"+
		"     helm get manifest karpenter-nodepool -n karpenter | kubectl apply -f -   # recreate the EC2NodeClass\n"+
		"     (or `terragrunt apply -replace=helm_release.nodepool[0]` on the %s karpenter unit), then re-check",
		nodeClasses != "", statuses, kc.Alias)
}

// pollKarpenterReady polls `check` up to `attempts` times (calling `sleep` between attempts, not after the
// last) until it reports the EC2NodeClass present and every NodePool Ready=True, or the attempts are exhausted.
// Returns the last-observed state either way, so the caller can decide what to try next. `check` and `sleep` are
// injected so this retry/give-up logic is unit-testable without a real cluster.
func pollKarpenterReady(check func() (nodeClasses string, readyStatuses []string), attempts int, sleep func()) (ready bool, nodeClasses string, statuses []string) {
	for i := 0; i < attempts; i++ {
		nodeClasses, statuses = check()
		if nodeClasses != "" && nodePoolsAllReady(statuses) {
			return true, nodeClasses, statuses
		}
		if i < attempts-1 {
			sleep()
		}
	}
	return false, nodeClasses, statuses
}

// restartKarpenterControllerFn is indirected so tests can stub the kubectl boundary.
var restartKarpenterControllerFn = restartKarpenterController

// restartKarpenterController deletes the Karpenter controller pod (its Deployment recreates it) and waits for
// the replacement to become Ready. Unsticks a deadlocked reconciler — observed live on 2026-07-02, where the
// termination controller stopped processing a NodeClaim/Node pair for 10+ minutes even after the backing EC2
// instance was confirmed terminated in AWS; only the pods were live-touched, not any AWS/Terraform state, so
// this is safe to attempt unconditionally as a first recovery step.
func restartKarpenterController(ctx context.Context, kubeconfigPath string) error {
	if out, err := exec.CommandContext(ctx, "kubectl", "--kubeconfig", kubeconfigPath,
		"delete", "pod", "-n", "karpenter", "-l", "app.kubernetes.io/name=karpenter",
		"--ignore-not-found").CombinedOutput(); err != nil {
		return fmt.Errorf("kubectl delete pod -n karpenter: %v: %s", err, strings.TrimSpace(string(out)))
	}
	// Best-effort: give the replacement a moment to become Ready before the caller re-polls NodePool status.
	// Not fatal on timeout — the caller's own poll loop will just see the not-yet-ready state and continue.
	_, _ = exec.CommandContext(ctx, "kubectl", "--kubeconfig", kubeconfigPath,
		"wait", "--for=condition=Ready", "pod", "-n", "karpenter", "-l", "app.kubernetes.io/name=karpenter",
		"--timeout=60s").CombinedOutput()
	return nil
}

// reapplyKarpenterNodepoolManifestFn is indirected so tests can stub the helm/kubectl boundary.
var reapplyKarpenterNodepoolManifestFn = reapplyKarpenterNodepoolManifest

// reapplyKarpenterNodepoolManifest recreates the EC2NodeClass (and reconciles the NodePool) by re-applying the
// karpenter-nodepool helm release's OWN rendered manifest — no edits, just `helm get manifest | kubectl apply`.
// This is the documented recovery for the case where the EC2NodeClass has been fully deleted with nothing
// recreating it (a `terragrunt apply -replace=helm_release.nodepool[0]` destroy+recreate can lose a
// still-referenced EC2NodeClass to a finalizer race, or — as observed live on 2026-07-02 — a stale EC2NodeClass
// left over from an interrupted 'down' can fully terminate once its blocking NodeClaim clears, and nothing else
// recreates it since the chart install merged into the still-terminating object instead of creating a fresh one).
func reapplyKarpenterNodepoolManifest(ctx context.Context, kubeconfigPath string) error {
	getCmd := exec.CommandContext(ctx, "helm", "--kubeconfig", kubeconfigPath, "get", "manifest",
		"karpenter-nodepool", "-n", "karpenter")
	var stderr bytes.Buffer
	getCmd.Stderr = &stderr
	manifest, err := getCmd.Output()
	if err != nil {
		return fmt.Errorf("helm get manifest karpenter-nodepool: %v: %s", err, strings.TrimSpace(stderr.String()))
	}
	applyCmd := exec.CommandContext(ctx, "kubectl", "--kubeconfig", kubeconfigPath, "apply", "-f", "-")
	applyCmd.Stdin = bytes.NewReader(manifest)
	if out, err := applyCmd.CombinedOutput(); err != nil {
		return fmt.Errorf("kubectl apply (recreating the EC2NodeClass): %v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// nodePoolsAllReady reports whether every NodePool's Ready condition is True (and there is at least one NodePool).
func nodePoolsAllReady(readyStatuses []string) bool {
	if len(readyStatuses) == 0 {
		return false
	}
	for _, s := range readyStatuses {
		if s != "True" {
			return false
		}
	}
	return true
}

// recoverKyverno repairs the post-unpark Kyverno/sigstore trap (#665). Kyverno's cosign image-verification
// policies need outbound DNS+internet to sigstore's TUF CDN; right after an unpark the network is still settling,
// so the admission controller's TUF init fails AND caches the failure — fail-closed, it then denies EVERY policed
// workload pod (the Deployments sit at zero pods) until it is restarted. So: if any Deployment wants pods but has
// none, wait for CoreDNS, restart the Kyverno admission controller (fresh TUF init), then re-roll the blocked
// Deployments so they recreate now instead of waiting out the ReplicaSet backoff. Best-effort; no-op when nothing
// is blocked or Kyverno is absent. Runs as the env's kubectl (PlatformAdmin: get/patch deployments).
func recoverKyverno(ctx context.Context, kc config.KubeconfigEntry) error {
	path, cleanup, err := tempKubeconfig(ctx, kc, "platctl-kyverno")
	if err != nil {
		return err
	}
	defer cleanup()
	k := func(args ...string) ([]byte, error) {
		return exec.CommandContext(ctx, "kubectl", append([]string{"--kubeconfig", path}, args...)...).CombinedOutput()
	}

	blocked, err := findBlockedDeployments(k)
	if err != nil {
		return err
	}
	if len(blocked) == 0 {
		return nil // healthy unpark — nothing blocked
	}

	// Workloads are blocked. If Kyverno is present, its cached sigstore TUF init likely failed during the network
	// settle — let CoreDNS come up, then restart it to force a fresh init.
	kyvernoRestarted := false
	if _, kErr := k("get", "deploy", "kyverno-admission-controller", "-n", "kyverno"); kErr == nil {
		fmt.Printf("  %d workload(s) have no pods post-unpark — refreshing Kyverno (sigstore trust roots)...\n", len(blocked))
		_, _ = k("rollout", "status", "deploy/coredns", "-n", "kube-system", "--timeout=3m") // let DNS settle first
		if rOut, rErr := k("rollout", "restart", "deploy/kyverno-admission-controller", "-n", "kyverno"); rErr != nil {
			return fmt.Errorf("restarting kyverno: %s", strings.TrimSpace(string(rOut)))
		}
		_, _ = k("rollout", "status", "deploy/kyverno-admission-controller", "-n", "kyverno", "--timeout=2m")
		kyvernoRestarted = true
	}

	// Re-roll the blocked Deployments so they recreate immediately rather than waiting out the backoff.
	for _, b := range blocked {
		_, _ = k("rollout", "restart", "deploy/"+b[1], "-n", b[0])
	}
	fmt.Printf("  re-rolled %d blocked workload(s).\n", len(blocked))

	// Restarting Kyverno fixes a stale sigstore-TUF cache — but NOT a config/IAM gap (e.g. the kyverno-ecr role
	// lacking ECR read, so verify-images can't pull the signature; IAM is call-time-evaluated, so no restart helps).
	// Re-check; if workloads stay blocked, SURFACE the actual admission error so the operator knows it's a source
	// fix, not a transient. (Burned 2026-06-27: an account-less kyverno-ecr ARN blocked every product pod's admission
	// and the silent restart-and-reroll gave no signal of the real cause.)
	if !kyvernoRestarted {
		return nil
	}
	var still [][2]string
	for i := 0; i < 6; i++ { // ~1 min for the re-rolled ReplicaSets to re-attempt admission
		time.Sleep(10 * time.Second)
		if still, _ = findBlockedDeployments(k); len(still) == 0 {
			return nil
		}
	}
	ns, name := still[0][0], still[0][1]
	fmt.Printf("  ⚠️ %d workload(s) STILL blocked after the Kyverno restart — NOT a transient; likely a config/IAM\n"+
		"     gap to fix at the source (restarting won't help). First blocked: %s/%s — admission error:\n     %s\n",
		len(still), ns, name, latestFailedCreate(k, ns))
	return nil
}

// findBlockedDeployments returns [namespace, name] for Deployments that want pods (spec.replicas>0) but have none
// (status.replicas absent/0) — the symptom of a fail-closed admission webhook rejecting every pod.
func findBlockedDeployments(k func(...string) ([]byte, error)) ([][2]string, error) {
	out, err := k("get", "deploy", "--all-namespaces",
		"-o", `jsonpath={range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.replicas}{" "}{.status.replicas}{"\n"}{end}`)
	if err != nil {
		return nil, fmt.Errorf("listing deployments: %s", strings.TrimSpace(string(out)))
	}
	var blocked [][2]string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		f := strings.Fields(line)
		if len(f) < 3 { // ns name spec [status]
			continue
		}
		status := "0"
		if len(f) >= 4 {
			status = f[3]
		}
		if f[2] != "0" && f[2] != "" && status == "0" {
			blocked = append(blocked, [2]string{f[0], f[1]})
		}
	}
	return blocked, nil
}

// latestFailedCreate returns the most recent ReplicaSet FailedCreate event message in a namespace — the admission
// rejection explaining why a Deployment can't create pods. Falls back to a hint when none is found.
func latestFailedCreate(k func(...string) ([]byte, error), ns string) string {
	out, err := k("get", "events", "-n", ns, "--field-selector", "reason=FailedCreate",
		"--sort-by=.lastTimestamp", "-o", "jsonpath={.items[-1:].message}")
	if msg := strings.TrimSpace(string(out)); err == nil && msg != "" {
		return msg
	}
	return "(no FailedCreate event found — run `kubectl describe rs` in the namespace for the admission error)"
}

// runReconnect runs the post-restore repair steps for an environment (see config.EnvConfig.Reconnect):
// re-apply idempotent units (e.g. platform/cross-vpc-dns — refreshes the private hosted zone to the restored
// cluster's current API ENIs) and bounce stale cross-cluster connections (e.g. the platform ArgoCD controller).
// Best-effort: it attempts every step, then returns a combined error so a partial reconnect still repairs what
// it can and the operator sees what's left.
func runReconnect(ctx context.Context, cfg *config.Config, repoRoot, restoredEnv string, rc *config.Reconnect, runner engine.Runner) error {
	fmt.Printf("Reconnecting after restoring %s (refresh cross-VPC DNS + bounce dependents)...\n", restoredEnv)
	var issues []string

	for _, ru := range rc.Units {
		owner, ok := cfg.Environments[ru.Env]
		if !ok {
			issues = append(issues, fmt.Sprintf("unit %s/%s: environment %q not defined in config", ru.Env, ru.Unit, ru.Env))
			continue
		}
		u := &engine.Unit{
			Name:     ru.Env + "/" + ru.Unit,
			Path:     filepath.Join(repoRoot, owner.Path, ru.Unit),
			Provider: owner.Provider,
			Auth:     cfg.AuthForUnit(ru.Env, ru.Unit),
		}
		fmt.Printf("  re-applying %s (idempotent)...\n", u.Name)
		if err := runner.Run(ctx, u, engine.Apply); err != nil {
			issues = append(issues, fmt.Sprintf("re-applying %s: %v", u.Name, err))
		}
	}

	for _, rr := range rc.Restarts {
		fmt.Printf("  restarting %s in %s/%s ...\n", rr.Target, rr.Env, rr.Namespace)
		if err := rolloutRestart(ctx, cfg, rr); err != nil {
			issues = append(issues, fmt.Sprintf("restart %s (%s): %v", rr.Target, rr.Env, err))
		}
	}

	if len(issues) > 0 {
		for _, msg := range issues {
			fmt.Printf("  warning: %s\n", msg)
		}
		return fmt.Errorf("reconnect completed with %d issue(s); platform→%s may need manual repair "+
			"(re-apply cross-vpc-dns + restart the argocd controller — see reference_preprod_scaleup_recovery)",
			len(issues), restoredEnv)
	}
	fmt.Printf("Reconnect complete — platform can reach the restored %s cluster.\n", restoredEnv)
	return nil
}

// rolloutRestart resolves the target environment's cluster and bounces a workload. Indirected through
// rolloutRestartFn so tests can stub the kubectl boundary.
func rolloutRestart(ctx context.Context, cfg *config.Config, rr config.ReconnectRestart) error {
	kc, err := kubeconfigForEnv(cfg, rr.Env)
	if err != nil {
		return err
	}
	return rolloutRestartFn(ctx, kc, rr.Namespace, rr.Target)
}

var rolloutRestartFn = doRolloutRestart

// tempKubeconfig writes a throwaway kubeconfig for the cluster (independent of the operator's local contexts,
// matching the bootstrap hooks). The caller must invoke the returned cleanup.
func tempKubeconfig(ctx context.Context, kc config.KubeconfigEntry, alias string) (string, func(), error) {
	tmp, err := os.CreateTemp("", "platctl-kubeconfig-*.yaml")
	if err != nil {
		return "", func() {}, err
	}
	path := tmp.Name()
	_ = tmp.Close()
	cleanup := func() { _ = os.Remove(path) }

	kcArgs := []string{"eks", "update-kubeconfig", "--name", kc.Cluster, "--region", kc.Region,
		"--kubeconfig", path, "--alias", alias}
	if kc.KubectlRoleARN != "" {
		kcArgs = append(kcArgs, "--role-arn", kc.KubectlRoleARN)
	}
	if kc.Profile != "" {
		kcArgs = append(kcArgs, "--profile", kc.Profile)
	}
	if out, err := exec.CommandContext(ctx, "aws", kcArgs...).CombinedOutput(); err != nil {
		cleanup()
		return "", func() {}, fmt.Errorf("update-kubeconfig: %v: %s", err, strings.TrimSpace(string(out)))
	}
	return path, cleanup, nil
}

// doRolloutRestart runs `kubectl rollout restart` against a throwaway kubeconfig for the cluster.
func doRolloutRestart(ctx context.Context, kc config.KubeconfigEntry, namespace, target string) error {
	path, cleanup, err := tempKubeconfig(ctx, kc, "platctl-reconnect")
	if err != nil {
		return err
	}
	defer cleanup()

	rsArgs := []string{"--kubeconfig", path, "rollout", "restart", target}
	if namespace != "" {
		rsArgs = append(rsArgs, "-n", namespace)
	}
	if out, err := exec.CommandContext(ctx, "kubectl", rsArgs...).CombinedOutput(); err != nil {
		return fmt.Errorf("kubectl rollout restart: %v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// drainKarpenterNodesFn is indirected so tests can stub the kubectl boundary.
var drainKarpenterNodesFn = doDrainKarpenterNodes

// drainKarpenterOrFail runs the Karpenter drain and turns a genuine failure into a FATAL, actionable error
// instead of a printed warning. A failed drain must NOT be followed by scaling the managed node groups to zero —
// that kills the Karpenter controller (which runs on the system group) mid-drain and can leave its NodePool/
// EC2NodeClass half-deleted. That exact swallowed-warning path masked a mid-drain `ExpiredToken` on 2026-07-02:
// 'down' still scaled the node groups and reported "Parked ... " with exit 0, leaving a stale EC2NodeClass that
// corrupted the next 'up' (see the cluster-parking skill's Learnings log for the full incident and recovery).
func drainKarpenterOrFail(ctx context.Context, kc config.KubeconfigEntry) error {
	fmt.Printf("Draining Karpenter-managed nodes on %s (delete NodePool; drains gracefully)...\n", kc.Cluster)
	if err := drainKarpenterNodesFn(ctx, kc); err != nil {
		return fmt.Errorf("draining Karpenter nodes on %s: %w — the managed node groups were NOT scaled down "+
			"(doing so now would kill the Karpenter controller mid-drain and orphan EC2 instances); fix the "+
			"underlying issue (e.g. `aws sso login --profile %s` for an expired/stale credential — note a stale "+
			"AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN in the shell env shadows --profile and "+
			"survives a fresh sso login) and re-run 'platctl down --env %s'", kc.Cluster, err, kc.Profile, kc.Alias)
	}
	return nil
}

// doDrainKarpenterNodes drains and terminates the Karpenter-managed nodes before the managed node groups
// (incl. the system group the controller runs on) scale to zero, so the controller doesn't die mid-park and
// orphan EC2 instances.
//
// It FIRST clears the `karpenter.sh/do-not-disrupt` annotation from any pods carrying it. That annotation
// protects stateful pods (the CNPG DBs, the observability stores) from Karpenter's *voluntary* disruption
// (consolidation/drift/expiry) in steady state — but it ALSO blocks the termination drain, so without this the
// NodePool delete would HANG on those pods and the park would leave orphaned nodes. A park is an intentional
// full shutdown, so overriding the steady-state protection is correct; the drain stays graceful (we clear the
// annotation, we don't force-kill). 'platctl up' re-applies the karpenter unit and the workloads' pod templates
// re-add the annotation, restoring the protection.
//
// Then it deletes the NodePool(s) and POLLS until the NodeClaims are actually gone — `kubectl delete nodepool`
// cascades to NodeClaim deletion in the background and returns early, so without the explicit wait the caller
// would scale the controller's node group to zero mid-termination and orphan the instances (verified live).
// No-op on clusters without Karpenter (the CRD is absent).
func doDrainKarpenterNodes(ctx context.Context, kc config.KubeconfigEntry) error {
	path, cleanup, err := tempKubeconfig(ctx, kc, "platctl-drain")
	if err != nil {
		return err
	}
	defer cleanup()

	// Clear do-not-disrupt from the pods that carry it (best-effort; targeted so the drain stays graceful).
	findOut, _ := exec.CommandContext(ctx, "kubectl", "--kubeconfig", path, "get", "pods", "--all-namespaces",
		"-o", `jsonpath={range .items[?(@.metadata.annotations.karpenter\.sh/do-not-disrupt=="true")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}`).CombinedOutput()
	for _, line := range strings.Split(strings.TrimSpace(string(findOut)), "\n") {
		ns, name, ok := strings.Cut(line, "/")
		if !ok {
			continue
		}
		_ = exec.CommandContext(ctx, "kubectl", "--kubeconfig", path, "annotate", "pod",
			"-n", ns, name, "karpenter.sh/do-not-disrupt-").Run()
	}

	out, err := exec.CommandContext(ctx, "kubectl", "--kubeconfig", path,
		"delete", "nodepool", "--all", "--ignore-not-found", "--wait=false").CombinedOutput()
	if err != nil {
		// No Karpenter CRD on this cluster → nothing to drain.
		if strings.Contains(string(out), "the server doesn't have a resource type") {
			return nil
		}
		return fmt.Errorf("kubectl delete nodepool: %v: %s", err, strings.TrimSpace(string(out)))
	}

	// Deleting the NodePool cascades to NodeClaim deletion in the BACKGROUND — `kubectl delete nodepool` returns
	// before the instances actually terminate. We MUST wait for the NodeClaims to be gone (the controller drains
	// and terminates them) before returning, because the caller next scales the system group — where the
	// controller runs — to zero; returning early kills the controller mid-termination and orphans the instances.
	drained := false
	for i := 0; i < 36; i++ { // up to ~6 min
		nc, _ := exec.CommandContext(ctx, "kubectl", "--kubeconfig", path, "get", "nodeclaims", "-o", "name").CombinedOutput()
		if strings.TrimSpace(string(nc)) == "" {
			fmt.Println("  Karpenter nodes drained and terminated.")
			drained = true
			break
		}
		time.Sleep(10 * time.Second)
	}
	if !drained {
		fmt.Println("  warning: Karpenter NodeClaims still present after 6m — check for orphaned instances before scaling the system group")
	}
	return deleteEC2NodeClasses(ctx, path)
}

// deleteEC2NodeClasses deletes the EC2NodeClass(es) too — symmetric with the NodePool delete above. 'down'
// historically deleted ONLY the NodePool and LEFT the EC2NodeClass, so the next 'up' force-replace (helm
// uninstall→install) raced the leftover finalizer'd NodeClass into Terminating and lost it — leaving the recreated
// NodePool NodeClassReady=False with every workload pod stranded Pending (2026-06-27). With the NodeClaims now gone
// the NodeClass's karpenter finalizer clears, so deleting it here lets 'up' recreate BOTH from a clean slate. We
// wait for it to be GONE so the system group doesn't scale to zero mid-finalize (a stuck-Terminating NodeClass
// would re-trigger the same race on 'up'). Best-effort; no-op when the CRD is absent.
func deleteEC2NodeClasses(ctx context.Context, kubeconfigPath string) error {
	out, err := exec.CommandContext(ctx, "kubectl", "--kubeconfig", kubeconfigPath,
		"delete", "ec2nodeclass", "--all", "--ignore-not-found", "--wait=false").CombinedOutput()
	if err != nil {
		if strings.Contains(string(out), "the server doesn't have a resource type") {
			return nil // no EC2NodeClass CRD on this cluster
		}
		fmt.Printf("  warning: deleting EC2NodeClass: %s\n", strings.TrimSpace(string(out)))
		return nil
	}
	for i := 0; i < 18; i++ { // up to ~90s for the finalizer to clear
		ec, _ := exec.CommandContext(ctx, "kubectl", "--kubeconfig", kubeconfigPath, "get", "ec2nodeclass", "-o", "name").CombinedOutput()
		if strings.TrimSpace(string(ec)) == "" {
			fmt.Println("  EC2NodeClass deleted.")
			return nil
		}
		time.Sleep(5 * time.Second)
	}
	fmt.Println("  warning: EC2NodeClass still present after 90s (finalizer stuck?) — 'up' should reconcile it, but verify it isn't stuck Terminating")
	return nil
}

// kubeconfigForEnv finds the kubeconfig entry (cluster/region/profile) for an environment, keyed by its alias.
func kubeconfigForEnv(cfg *config.Config, env string) (config.KubeconfigEntry, error) {
	for _, e := range cfg.Kubeconfig {
		if e.Alias == env {
			return e, nil
		}
	}
	return config.KubeconfigEntry{}, fmt.Errorf("no kubeconfig entry for env %q in the config (need cluster/region/profile)", env)
}

// scaleNodeGroupsToZero scales every managed node group on the cluster to desiredSize=0, minSize=0 (maxSize is
// left unchanged). Uses the aws CLI like the other commands.
func scaleNodeGroupsToZero(kc config.KubeconfigEntry) error {
	names, err := listNodeGroups(kc)
	if err != nil {
		return err
	}
	if len(names) == 0 {
		fmt.Printf("No managed node groups on %s — nothing to scale.\n", kc.Cluster)
		return nil
	}
	for _, ng := range names {
		fmt.Printf("  scaling %s/%s -> min=0, desired=0 ...\n", kc.Cluster, ng)
		out, err := exec.Command("aws", "eks", "update-nodegroup-config",
			"--cluster-name", kc.Cluster,
			"--nodegroup-name", ng,
			"--region", kc.Region,
			"--profile", kc.Profile,
			"--scaling-config", "minSize=0,desiredSize=0",
		).CombinedOutput()
		if err != nil {
			return fmt.Errorf("scaling node group %s: %s\n%s", ng, err, out)
		}
	}
	// A managed group's scale-to-zero drains each node via an EKS lifecycle hook that respects PodDisruption
	// Budgets — so the stateful pods that landed on the system nodes during the Karpenter drain can stall the
	// node in Terminating:Wait until the hook times out (~15m), needlessly burning money. Reap them.
	if err := reapStuckNodeGroupInstances(kc); err != nil {
		fmt.Printf("  warning: %v (nodes will still terminate at the lifecycle-hook timeout)\n", err)
	}
	fmt.Printf("Parked %s. Control plane + EBS data are preserved. Restore with 'platctl up --env %s'.\n", kc.Cluster, kc.Alias)
	return nil
}

// reapStuckNodeGroupInstances is the managed-node-group analogue of the Karpenter do-not-disrupt fix: after a
// group scales to zero, give the graceful (PDB-respecting) lifecycle-hook drain a short window, then
// force-terminate any of the cluster's instances still running. A park is a full shutdown and EBS data persists
// (Postgres is crash-safe), so a PDB-blocked drain must not be allowed to keep nodes alive for the ~15m hook
// timeout (#661). Best-effort and ctx-free, matching scaleNodeGroupsToZero. By this point the Karpenter nodes are
// already gone (doDrainKarpenterNodes waited for them), so the only instances left are this group's.
func reapStuckNodeGroupInstances(kc config.KubeconfigEntry) error {
	alive := func() ([]string, error) {
		out, err := exec.Command("aws", "ec2", "describe-instances",
			"--region", kc.Region, "--profile", kc.Profile,
			"--filters", "Name=tag:kubernetes.io/cluster/"+kc.Cluster+",Values=owned",
			"Name=instance-state-name,Values=running,pending",
			"--query", "Reservations[].Instances[].InstanceId", "--output", "text").CombinedOutput()
		if err != nil {
			return nil, fmt.Errorf("describe-instances: %s\n%s", err, strings.TrimSpace(string(out)))
		}
		return strings.Fields(string(out)), nil
	}

	// Graceful window: a node with no PDB-blocked pods drains in ~1-2 min.
	for i := 0; i < 12; i++ {
		ids, err := alive()
		if err != nil {
			return err
		}
		if len(ids) == 0 {
			return nil // drained gracefully — nothing to reap
		}
		time.Sleep(10 * time.Second)
	}

	ids, err := alive()
	if err != nil {
		return err
	}
	if len(ids) == 0 {
		return nil
	}
	fmt.Printf("  %d node(s) still draining after 2m (PDB-blocked lifecycle hook); force-terminating "+
		"(park is a full shutdown — EBS data preserved)...\n", len(ids))
	args := append([]string{"ec2", "terminate-instances", "--region", kc.Region, "--profile", kc.Profile,
		"--instance-ids"}, ids...)
	if out, err := exec.Command("aws", args...).CombinedOutput(); err != nil {
		return fmt.Errorf("force-terminating stuck nodes %v: %s\n%s", ids, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func listNodeGroups(kc config.KubeconfigEntry) ([]string, error) {
	out, err := exec.Command("aws", "eks", "list-nodegroups",
		"--cluster-name", kc.Cluster,
		"--region", kc.Region,
		"--profile", kc.Profile,
		"--query", "nodegroups",
		"--output", "text",
	).CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("listing node groups on %s: %s\n%s", kc.Cluster, err, out)
	}
	return strings.Fields(string(out)), nil
}

// bastionName derives the SSM bastion's Name tag from the cluster name (platform-use1-eks → platform-use1-ssm-bastion).
func bastionName(cluster string) string {
	return strings.TrimSuffix(cluster, "-eks") + "-ssm-bastion"
}

// setBastionPowerFn is indirected so tests can stub the EC2 boundary.
var setBastionPowerFn = setBastionPower

// setBastionPower stops (on=false) or starts (on=true) the env's SSM bastion instance(s). 'platctl down' scales the
// node groups to zero but the bastion is a standing EC2 instance outside them, so a truly cost-zero park must stop
// it too; 'up' starts it back. Discovers by the derived Name tag, scoped to the env's account by the profile.
// Best-effort and a no-op when no bastion is in the relevant state (e.g. an env without the ssm-bastion module).
func setBastionPower(kc config.KubeconfigEntry, on bool) error {
	states, verb, label := "running,pending", "stop-instances", "Stopping"
	if on {
		states, verb, label = "stopped,stopping", "start-instances", "Starting"
	}
	name := bastionName(kc.Cluster)
	out, err := exec.Command("aws", "ec2", "describe-instances",
		"--region", kc.Region, "--profile", kc.Profile,
		"--filters", "Name=tag:Name,Values="+name, "Name=instance-state-name,Values="+states,
		"--query", "Reservations[].Instances[].InstanceId", "--output", "text").CombinedOutput()
	if err != nil {
		return fmt.Errorf("describe bastion %s: %s\n%s", name, err, strings.TrimSpace(string(out)))
	}
	ids := strings.Fields(string(out))
	if len(ids) == 0 {
		return nil // no bastion in that state — nothing to do
	}
	fmt.Printf("  %s SSM bastion(s) %v ...\n", label, ids)
	args := append([]string{"ec2", verb, "--region", kc.Region, "--profile", kc.Profile, "--instance-ids"}, ids...)
	if out, err := exec.Command("aws", args...).CombinedOutput(); err != nil {
		return fmt.Errorf("%s bastion %v: %s\n%s", verb, ids, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func confirmDown(env, cluster string) bool {
	fmt.Printf("Scale down %s (%s) node groups to zero? Services stop; EBS data is preserved; reversible with 'platctl up --env %s'. [y/N] ", env, cluster, env)
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return false
	}
	resp := strings.ToLower(strings.TrimSpace(scanner.Text()))
	return resp == "y" || resp == "yes"
}
