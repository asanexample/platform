package agent_eval_store_test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// Plan-only: the module reads aws_caller_identity, so it needs AWS credentials
// (like the other AWS module tests here). The corpus bucket + CMK are cheap and
// safe to apply/destroy in the Test sandbox, but presence-based plan assertions
// keep CI fast and credential-light; the hardening is encoded by the presence of
// the public-access-block, SSE (KMS), versioning, and bucket-policy resources.

func TestAgentEvalStore_Disabled(t *testing.T) {
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

func TestAgentEvalStore_Plan(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":      true,
		"bucket_name": "test-agent-eval-corpus",
		"tags":        map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	// The full hardened bucket + dedicated CMK.
	expectedResources := []string{
		"module.agent_eval_store.aws_kms_key.corpus[0]",
		"module.agent_eval_store.aws_kms_alias.corpus[0]",
		"module.agent_eval_store.aws_s3_bucket.corpus[0]",
		"module.agent_eval_store.aws_s3_bucket_ownership_controls.corpus[0]",
		"module.agent_eval_store.aws_s3_bucket_public_access_block.corpus[0]",
		"module.agent_eval_store.aws_s3_bucket_versioning.corpus[0]",
		"module.agent_eval_store.aws_s3_bucket_server_side_encryption_configuration.corpus[0]",
		"module.agent_eval_store.aws_s3_bucket_policy.corpus[0]",
	}
	for _, resource := range expectedResources {
		assert.Contains(t, planStruct.ResourcePlannedValuesMap, resource,
			"plan should include %s", resource)
	}

	// Optional tiering is off by default — no lifecycle rule.
	assert.NotContains(t, planStruct.ResourcePlannedValuesMap,
		"module.agent_eval_store.aws_s3_bucket_lifecycle_configuration.corpus[0]",
		"lifecycle tiering should be absent when transition_to_ia_days=0")
}

func TestAgentEvalStore_LifecycleTiering(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":                true,
		"bucket_name":           "test-agent-eval-corpus",
		"transition_to_ia_days": 30,
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	assert.Contains(t, planStruct.ResourcePlannedValuesMap,
		"module.agent_eval_store.aws_s3_bucket_lifecycle_configuration.corpus[0]",
		"lifecycle tiering should be present when transition_to_ia_days>0")
}
