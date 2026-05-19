package ssm_bastion_test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestSSMBastion_Disabled(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create": false,
		"name":   "test-" + uniqueID + "-bastion",
		"tags":   map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	assert.Empty(t, planStruct.ResourcePlannedValuesMap,
		"create=false should produce zero resources")
}

func TestSSMBastion_Plan(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":    true,
		"name":      "test-" + uniqueID + "-bastion",
		"vpc_id":    "vpc-12345678",
		"subnet_id": "subnet-12345678",
		"tags":      map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	expectedResources := []string{
		"module.ssm_bastion.aws_iam_role.bastion[0]",
		"module.ssm_bastion.aws_iam_role_policy_attachment.ssm[0]",
		"module.ssm_bastion.aws_iam_instance_profile.bastion[0]",
		"module.ssm_bastion.aws_security_group.bastion[0]",
		"module.ssm_bastion.aws_vpc_security_group_egress_rule.https[0]",
		"module.ssm_bastion.aws_instance.bastion[0]",
	}

	for _, resource := range expectedResources {
		assert.Contains(t, planStruct.ResourcePlannedValuesMap, resource,
			"plan should include %s", resource)
	}
}
