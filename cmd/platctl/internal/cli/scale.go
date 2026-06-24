package cli

import (
	"bufio"
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
EKS API. The control plane and all EBS volumes (e.g. CNPG databases) are preserved, and pods reschedule when you
run 'platctl up --env <env>'. Non-destructive and reversible — for parking an idle environment overnight. To
release all cost (~$0), use 'platctl teardown --env <env>' instead.`,
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
			if !yes && !confirmDown(envName, kc.Cluster) {
				fmt.Println("Aborted.")
				return nil
			}
			// Drain Karpenter-managed nodes BEFORE the managed groups scale to zero — otherwise the controller
			// (on the system group) dies mid-park and leaves orphaned EC2 instances. No-op without Karpenter.
			fmt.Printf("Draining Karpenter-managed nodes on %s (delete NodePool; drains gracefully)...\n", kc.Cluster)
			if err := drainKarpenterNodesFn(context.Background(), kc); err != nil {
				fmt.Printf("  warning: %v (continuing — check for orphaned Karpenter instances)\n", err)
			}
			return scaleNodeGroupsToZero(kc)
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
			// Restore the Karpenter NodePool that 'platctl down' deletes to drain Karpenter's nodes (so the
			// cluster regains node autoscaling). No-op if this env has no karpenter unit.
			kpPath := filepath.Join(repoRoot, env.Path, "karpenter")
			if _, statErr := os.Stat(kpPath); statErr == nil {
				kpUnit := &engine.Unit{
					Name:     envName + "/karpenter",
					Path:     kpPath,
					Provider: env.Provider,
					Auth:     cfg.AuthForUnit(envName, "karpenter"),
				}
				fmt.Printf("Restoring %s Karpenter NodePool (terragrunt apply)...\n", envName)
				if err := runner.Run(ctx, kpUnit, engine.Apply); err != nil {
					return err
				}
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
	for i := 0; i < 36; i++ { // up to ~6 min
		nc, _ := exec.CommandContext(ctx, "kubectl", "--kubeconfig", path, "get", "nodeclaims", "-o", "name").CombinedOutput()
		if strings.TrimSpace(string(nc)) == "" {
			fmt.Println("  Karpenter nodes drained and terminated.")
			return nil
		}
		time.Sleep(10 * time.Second)
	}
	fmt.Println("  warning: Karpenter NodeClaims still present after 6m — check for orphaned instances before scaling the system group")
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
	fmt.Printf("Parked %s. Nodes drain over a few minutes; control plane + EBS data are preserved. Restore with 'platctl up --env %s'.\n", kc.Cluster, kc.Alias)
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

func confirmDown(env, cluster string) bool {
	fmt.Printf("Scale down %s (%s) node groups to zero? Services stop; EBS data is preserved; reversible with 'platctl up --env %s'. [y/N] ", env, cluster, env)
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return false
	}
	resp := strings.ToLower(strings.TrimSpace(scanner.Text()))
	return resp == "y" || resp == "yes"
}
