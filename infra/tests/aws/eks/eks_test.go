package eks_test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestEKS_BasicCluster(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	clusterName := "test-" + uniqueID + "-eks"
	tmpDir := copyFixtureToTemp(t)

	vpcCIDR := testVPCCIDR(0)

	subnets := map[string]interface{}{
		"az1-public": map[string]interface{}{
			"address_prefixes":  []string{subnetCIDR(0, "224/28")},
			"availability_zone": testRegion() + "a",
			"public":            true,
		},
		"az1-kubernetes": map[string]interface{}{
			"address_prefixes":  []string{subnetCIDR(0, "0/26")},
			"availability_zone": testRegion() + "a",
			"public":            false,
		},
		"az2-kubernetes": map[string]interface{}{
			"address_prefixes":  []string{subnetCIDR(0, "64/26")},
			"availability_zone": testRegion() + "b",
			"public":            false,
		},
	}

	baseVars := map[string]interface{}{
		"create":                    true,
		"vpc_name":                  "test-" + uniqueID + "-vpc",
		"cluster_name":              clusterName,
		"address_space":             []string{vpcCIDR},
		"subnets":                   subnets,
		"kubernetes_version":        "1.35",
		"enable_secrets_encryption": true,
		"create_node_group":         false,
		"access_entries": map[string]interface{}{
			"admin": map[string]interface{}{
				"principal_arn": testRoleARN(),
				"policy_arn":    "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy",
			},
		},
		"tags": map[string]string{"TestRun": uniqueID},
	}

	// Phase 1: create cluster + install Cilium (no node groups)
	opts := newTerraformOptions(t, tmpDir, baseVars)
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	eksClient := newEKSClient(t)
	iamClient := newIAMClient(t)

	assertClusterActive(t, eksClient, clusterName)
	assertClusterVersion(t, eksClient, clusterName, "1.35")

	assert.NotEmpty(t, terraform.Output(t, opts, "cluster_id"))
	assert.NotEmpty(t, terraform.Output(t, opts, "cluster_arn"))
	assert.NotEmpty(t, terraform.Output(t, opts, "cluster_endpoint"))
	assert.NotEmpty(t, terraform.Output(t, opts, "cluster_certificate_authority"))
	assert.NotEmpty(t, terraform.Output(t, opts, "cluster_security_group_id"))

	oidcARN := terraform.Output(t, opts, "oidc_provider_arn")
	assert.NotEmpty(t, oidcARN)
	assertOIDCProviderExists(t, iamClient, oidcARN)

	oidcURL := terraform.Output(t, opts, "oidc_provider_url")
	assert.NotEmpty(t, oidcURL)
	assert.NotContains(t, oidcURL, "https://")

	assert.NotEmpty(t, terraform.Output(t, opts, "kms_key_arn"))

	// Phase 2: add node group (Cilium CNI is already running)
	withNodeVars := copyVars(baseVars)
	withNodeVars["create_node_group"] = true
	opts2 := newTerraformOptions(t, tmpDir, withNodeVars)
	terraform.Apply(t, opts2)

	assertNodeGroupActive(t, eksClient, clusterName, "system")
	assert.NotEmpty(t, terraform.Output(t, opts2, "node_role_arn"))

	nodeGroups := terraform.OutputMap(t, opts2, "node_group_names")
	assert.Contains(t, nodeGroups, "system")

	assert.NotEmpty(t, terraform.Output(t, opts2, "vpc_id"))
}

func TestEKS_AddonsInPlan(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	tmpDir := copyFixtureToTemp(t)

	vpcCIDR := testVPCCIDR(0)

	subnets := map[string]interface{}{
		"az1-kubernetes": map[string]interface{}{
			"address_prefixes":  []string{subnetCIDR(0, "0/26")},
			"availability_zone": testRegion() + "a",
			"public":            false,
		},
	}

	vars := map[string]interface{}{
		"create":        true,
		"vpc_name":      "test-" + uniqueID + "-vpc",
		"cluster_name":  "test-" + uniqueID + "-eks",
		"address_space": []string{vpcCIDR},
		"subnets":       subnets,
		"eks_addons": map[string]interface{}{
			"coredns": map[string]interface{}{},
		},
		"tags": map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	addonKey := "module.eks.aws_eks_addon.this[\"coredns\"]"
	assert.Contains(t, planStruct.ResourcePlannedValuesMap, addonKey,
		"plan should include aws_eks_addon for coredns")

	addonResource := planStruct.ResourcePlannedValuesMap[addonKey]
	assert.Equal(t, "coredns", addonResource.AttributeValues["addon_name"])
}

func TestEKS_Disabled(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":        false,
		"vpc_name":      "test-" + uniqueID + "-vpc",
		"cluster_name":  "test-" + uniqueID + "-eks",
		"address_space": []string{"10.201.99.0/24"},
		"subnets":       map[string]interface{}{},
		"tags":          map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	assert.Empty(t, planStruct.ResourcePlannedValuesMap,
		"create=false should produce zero resources")
}
