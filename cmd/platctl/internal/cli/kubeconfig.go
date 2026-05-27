package cli

import (
	"fmt"
	"os/exec"

	"github.com/spf13/cobra"

	"github.com/gangster/platform/cmd/platctl/internal/config"
)

// NewKubeconfigCmd creates the kubeconfig subcommand.
func NewKubeconfigCmd() *cobra.Command {
	var envFilter string

	cmd := &cobra.Command{
		Use:   "kubeconfig",
		Short: "Configure kubectl contexts for deployed clusters",
		Long: `Sets up kubectl contexts for all clusters defined in .platctl.yaml.
Uses 'aws eks update-kubeconfig' with the configured admin role for each cluster.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			repoRoot, err := findRepoRoot()
			if err != nil {
				return err
			}

			cfgPath := findConfig(repoRoot)
			cfg, err := config.Load(cfgPath)
			if err != nil {
				return fmt.Errorf("loading config: %w", err)
			}

			return configureKubeconfig(cfg.Kubeconfig, envFilter)
		},
	}

	cmd.Flags().StringVar(&envFilter, "env", "", "Configure only a single environment's cluster")

	return cmd
}

func configureKubeconfig(entries []config.KubeconfigEntry, envFilter string) error {
	if len(entries) == 0 {
		fmt.Println("No kubeconfig entries defined in .platctl.yaml")
		return nil
	}

	for _, entry := range entries {
		if envFilter != "" && entry.Alias != envFilter {
			continue
		}

		fmt.Printf("Configuring kubectl context %q (%s)...\n", entry.Alias, entry.Cluster)

		args := []string{
			"eks", "update-kubeconfig",
			"--name", entry.Cluster,
			"--region", entry.Region,
			"--profile", entry.Profile,
			"--alias", entry.Alias,
		}
		if entry.KubectlRoleARN != "" {
			args = append(args, "--role-arn", entry.KubectlRoleARN)
		}

		out, err := exec.Command("aws", args...).CombinedOutput()
		if err != nil {
			return fmt.Errorf("configuring %s: %s\n%s", entry.Alias, err, out)
		}
		fmt.Printf("  %s\n", string(out))
	}

	return nil
}
