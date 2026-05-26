package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

// NewValidateCmd creates the validate subcommand skeleton.
// Cloud-specific health checks will be added in a follow-up.
func NewValidateCmd() *cobra.Command {
	var envFilter string

	cmd := &cobra.Command{
		Use:   "validate",
		Short: "Validate deployed infrastructure (extension point)",
		Long: `Validate checks that deployed units are healthy by running
provider-specific health checks. Currently a skeleton — cloud-specific
checks (EKS cluster status, node readiness, Helm releases) will be
added in a future release.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("validate is not yet implemented.")
			fmt.Println("This command will check deployed infrastructure health.")
			fmt.Println("See cmd/platctl/ARCHITECTURE.md for the Checker interface.")
			if envFilter != "" {
				fmt.Printf("Environment filter: %s\n", envFilter)
			}
			return nil
		},
	}

	cmd.Flags().StringVar(&envFilter, "env", "", "Target a single environment")

	return cmd
}
