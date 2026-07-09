package codeartifact_test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// Plan-only tests: creating a CodeArtifact domain + repositories is safe to apply/destroy, but the
// module reads aws_caller_identity for the KMS key policy, so these tests require AWS credentials
// like the other AWS module tests here. Plan-only keeps CI fast and side-effect-free.

func TestCodeArtifact_Disabled(t *testing.T) {
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

func TestCodeArtifact_Plan(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":      true,
		"domain_name": "test-refplat",
		"store_repositories": map[string]interface{}{
			"npm-store":  map[string]interface{}{"external_connection": "public:npmjs"},
			"pypi-store": map[string]interface{}{"external_connection": "public:pypi"},
		},
		"repositories": map[string]interface{}{
			"alpha-shop": map[string]interface{}{
				"upstreams": []string{"npm-store", "pypi-store"},
				"tags":      map[string]string{"Team": "alpha", "Product": "shop"},
			},
		},
		"read_account_ids": []string{"111122223333", "444455556666"},
		"tags":             map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	expectedResources := []string{
		"module.codeartifact.aws_codeartifact_domain.this[0]",
		"module.codeartifact.aws_kms_key.domain[0]",
		"module.codeartifact.aws_kms_alias.domain[0]",
		"module.codeartifact.aws_codeartifact_domain_permissions_policy.cross_account[0]",
		`module.codeartifact.aws_codeartifact_repository.store["npm-store"]`,
		`module.codeartifact.aws_codeartifact_repository.store["pypi-store"]`,
		`module.codeartifact.aws_codeartifact_repository.this["alpha-shop"]`,
		`module.codeartifact.aws_codeartifact_repository_permissions_policy.cross_account_read["alpha-shop"]`,
	}
	for _, resource := range expectedResources {
		assert.Contains(t, planStruct.ResourcePlannedValuesMap, resource,
			"plan should include %s", resource)
	}
}

// With no read_account_ids, all cross-account policies (domain, per-repo, KMS cross-account statement)
// are gated off — the registry stays single-account.
func TestCodeArtifact_NoCrossAccount(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":      true,
		"domain_name": "test-refplat",
		"store_repositories": map[string]interface{}{
			"npm-store": map[string]interface{}{"external_connection": "public:npmjs"},
		},
		"repositories": map[string]interface{}{
			"alpha-shop": map[string]interface{}{"upstreams": []string{"npm-store"}},
		},
		// read_account_ids intentionally omitted.
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	// Domain + repos still planned.
	assert.Contains(t, planStruct.ResourcePlannedValuesMap,
		"module.codeartifact.aws_codeartifact_domain.this[0]")
	assert.Contains(t, planStruct.ResourcePlannedValuesMap,
		`module.codeartifact.aws_codeartifact_repository.this["alpha-shop"]`)

	// Cross-account policies absent.
	assert.NotContains(t, planStruct.ResourcePlannedValuesMap,
		"module.codeartifact.aws_codeartifact_domain_permissions_policy.cross_account[0]",
		"domain permissions policy should be absent without read_account_ids")
	assert.NotContains(t, planStruct.ResourcePlannedValuesMap,
		`module.codeartifact.aws_codeartifact_repository_permissions_policy.cross_account_read["alpha-shop"]`,
		"repo read policy should be absent without read_account_ids")
}
