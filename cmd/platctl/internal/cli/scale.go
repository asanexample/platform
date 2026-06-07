package cli

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/gangster/platform/cmd/platctl/internal/config"
	"github.com/gangster/platform/cmd/platctl/internal/engine"
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
			return runner.Run(context.Background(), unit, engine.Apply)
		},
	}

	cmd.Flags().StringVar(&envName, "env", "", "Environment to restore (required)")
	return cmd
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
