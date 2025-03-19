package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestIdentitiesModule(t *testing.T) {
	// Create a basic test for a minimal identities setup
	t.Run("BasicIdentitiesTest", func(t *testing.T) {
		terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
			TerraformDir: "../examples/basic",
			NoColor:      true,
		})

		defer terraform.Destroy(t, terraformOptions)
		terraform.InitAndPlan(t, terraformOptions)
	})

	// Create a test for workload identities
	t.Run("WorkloadIdentitiesTest", func(t *testing.T) {
		terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
			TerraformDir: "../examples/workload_identities",
			NoColor:      true,
		})

		defer terraform.Destroy(t, terraformOptions)
		terraform.InitAndPlan(t, terraformOptions)
	})
}
