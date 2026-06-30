package cost_export_test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// Plan-only: the CUR + Glue + Athena pipeline is payer-account billing infra
// that can't be safely apply/destroyed in CI. Requires AWS credentials (the
// module reads aws_caller_identity), like the other AWS module tests here.

func TestCostExport_Disabled(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create": false,
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	assert.Empty(t, planStruct.ResourcePlannedValuesMap,
		"create=false should produce zero resources")
}

func TestCostExport_Plan(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":                        true,
		"reader_trusted_principal_arns": []string{"arn:aws:iam::111122223333:root"},
		"tags":                          map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	expectedResources := []string{
		"module.cost_export.aws_s3_bucket.cur[0]",
		"module.cost_export.aws_s3_bucket_policy.cur[0]",
		"module.cost_export.aws_s3_bucket_server_side_encryption_configuration.cur[0]",
		"module.cost_export.aws_cur_report_definition.this[0]",
		"module.cost_export.aws_glue_catalog_database.cur[0]",
		"module.cost_export.aws_glue_crawler.cur[0]",
		"module.cost_export.aws_athena_workgroup.cur[0]",
		"module.cost_export.aws_iam_role.cost_reader[0]",
		"module.cost_export.aws_iam_role_policy.cost_reader[0]",
	}
	for _, resource := range expectedResources {
		assert.Contains(t, planStruct.ResourcePlannedValuesMap, resource,
			"plan should include %s", resource)
	}
}

func TestCostExport_NoReaderRole(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	// No trust principals → the cross-account reader role is not created, but the
	// rest of the AWS pipeline still is.
	vars := map[string]interface{}{
		"create": true,
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	assert.NotContains(t, planStruct.ResourcePlannedValuesMap,
		"module.cost_export.aws_iam_role.cost_reader[0]",
		"cost_reader role should be absent without trust principals")
	assert.Contains(t, planStruct.ResourcePlannedValuesMap,
		"module.cost_export.aws_cur_report_definition.this[0]",
		"the CUR pipeline should still be created")
}
