// platctl orchestrates multi-environment Terragrunt deployments with
// dependency-aware ordering, parallel execution, and resumability.
package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/asanexample/platform/cmd/platctl/internal/cli"
)

func main() {
	root := &cobra.Command{
		Use:   "platctl",
		Short: "Platform orchestration CLI",
		Long: `platctl orchestrates multi-environment Terragrunt deployments.

It auto-discovers units from terragrunt.hcl files, builds a dependency
graph, and executes operations in topological order with parallel
execution of independent units.`,
		SilenceUsage: true,
	}

	root.PersistentFlags().String("config", "", "Path to config file (default: <repo-root>/.platctl.yaml)")

	root.AddCommand(cli.NewBootstrapCmd())
	root.AddCommand(cli.NewTeardownCmd())
	root.AddCommand(cli.NewStatusCmd())
	root.AddCommand(cli.NewValidateCmd())
	root.AddCommand(cli.NewKubeconfigCmd())
	root.AddCommand(cli.NewDownCmd())
	root.AddCommand(cli.NewUpCmd())
	root.AddCommand(cli.NewAccessCmd())

	if err := root.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
