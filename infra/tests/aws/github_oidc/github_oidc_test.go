package github_oidc_test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// A sub-scoped role and a job_workflow_ref-scoped role must each resolve ONLY their own
// trust claim: the sub role keys on `sub` (and has no job_workflow_ref claim), the reusable-
// workflow role keys on `job_workflow_ref` (and has no `sub` claim, since `sub` reflects the
// caller, not the signer). These claim maps drive the dynamic trust conditions in main.tf.
//
// We assert the claim maps (pure, known-at-plan) rather than the rendered assume-role JSON,
// which is only known post-apply because it embeds the to-be-created OIDC provider ARN.
func TestGithubOIDC_TrustClaimsByScope(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"github_org": "asanexample",
		"roles": map[string]interface{}{
			"sub-role": map[string]interface{}{
				"repos":    []string{"app-alpha"},
				"branches": []string{"main"},
				"events":   []string{"pull_request"},
			},
			"jwr-role": map[string]interface{}{
				"job_workflow_refs": []string{"trusted-ci/.github/workflows/slsa-provenance.yml@*"},
			},
		},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	subClaims := outputClaims(t, planStruct, "role_subject_claims")
	jwrClaims := outputClaims(t, planStruct, "role_job_workflow_ref_claims")

	// sub-scoped role: sub claim present (org-prefixed repo×ref), no job_workflow_ref claim.
	assert.Contains(t, subClaims["sub-role"], "repo:asanexample/app-alpha:ref:refs/heads/main",
		"sub-scoped role must match the repo×branch subject")
	assert.Empty(t, jwrClaims["sub-role"],
		"sub-scoped role must have NO job_workflow_ref claim")

	// reusable-workflow role: job_workflow_ref claim present (org-prefixed), no sub claim.
	assert.Contains(t, jwrClaims["jwr-role"], "asanexample/trusted-ci/.github/workflows/slsa-provenance.yml@*",
		"reusable-workflow role must match the org-prefixed workflow ref")
	assert.Empty(t, subClaims["jwr-role"],
		"reusable-workflow role must have NO sub claim (sub reflects the caller, not the signer)")
}

// A role scoped by NEITHER repos nor job_workflow_refs would trust every GitHub OIDC
// subject — the variable validation must reject it before plan.
func TestGithubOIDC_RejectsUnscopedRole(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"github_org": "asanexample",
		"roles": map[string]interface{}{
			"bad-role": map[string]interface{}{},
		},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	_, err := terraform.InitAndPlanE(t, opts)
	require.Error(t, err, "an unscoped role must fail validation")
	assert.Contains(t, err.Error(), "at least one of",
		"error should explain a role needs repos or job_workflow_refs")
}

// outputClaims reads a per-role claim map (output "role_*_claims") from the plan. New outputs
// land in OutputChanges (not planned_values) on a first plan; the values are known at plan.
func outputClaims(t *testing.T, plan *terraform.PlanStruct, name string) map[string][]interface{} {
	t.Helper()
	change, ok := plan.RawPlan.OutputChanges[name]
	require.True(t, ok, "plan should include output %q", name)
	after, ok := change.After.(map[string]interface{})
	require.True(t, ok, "output %q should be a map", name)

	claims := map[string][]interface{}{}
	for role, v := range after {
		list, _ := v.([]interface{})
		claims[role] = list
	}
	return claims
}
