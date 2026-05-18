package networking_test

import (
	"path/filepath"
	"testing"

	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNetworking_PrivateTopology(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	moduleDir := copyModuleToTemp(t)
	client := newEC2Client(t)
	azs := getAvailabilityZones(t, client)

	vpcCIDR := testVPCCIDR(0)
	eksClusterName := "test-" + uniqueID + "-eks"

	subnets := buildSubnets(azs[0], []subnetSpec{
		{name: "az1-public", cidr: subnetCIDR(0, 0, "224/28"), public: true},
		{name: "az1-kubernetes", cidr: subnetCIDR(0, 0, "0/26"), public: false},
	})

	vars := map[string]interface{}{
		"create":                  true,
		"vpc_name":                "test-" + uniqueID + "-vpc",
		"address_space":           []string{vpcCIDR},
		"subnets":                 subnets,
		"environment":             "test",
		"workload":                "terratest",
		"region_abbv":             "usw2",
		"create_internet_gateway": true,
		"create_nat_gateways":     true,
		"single_nat_gateway":      true,
		"enable_eks_networking":   true,
		"eks_cluster_name":        eksClusterName,
		"enable_flow_logs":        true,
		"flow_log_destination":    "cloud-watch-logs",
		"flow_log_retention_days": 30,
		"tags":                    map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, moduleDir, vars)
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// VPC
	vpcID := terraform.Output(t, opts, "vpc_id")
	assert.NotEmpty(t, vpcID)
	assert.Equal(t, vpcCIDR, terraform.Output(t, opts, "vpc_cidr_block"))

	// IGW
	igwID := terraform.Output(t, opts, "internet_gateway_id")
	assert.NotEmpty(t, igwID)

	// NAT gateway — single
	natMap := terraform.OutputMap(t, opts, "nat_gateway_ids")
	assert.Len(t, natMap, 1, "single_nat_gateway should create exactly 1 NAT")

	// Subnet IDs
	subnetMap := terraform.OutputMap(t, opts, "subnet_ids")
	assert.Len(t, subnetMap, 2)

	// Public subnet has public IP mapping
	assertSubnetPublicIP(t, client, subnetMap["az1-public"], true)
	assertSubnetPublicIP(t, client, subnetMap["az1-kubernetes"], false)

	// EKS tags on kubernetes subnet
	assertSubnetTag(t, client, subnetMap["az1-kubernetes"], "kubernetes.io/role/internal-elb", "1")
	assertSubnetTag(t, client, subnetMap["az1-kubernetes"], "kubernetes.io/cluster/"+eksClusterName, "shared")
	assertSubnetTag(t, client, subnetMap["az1-public"], "kubernetes.io/role/elb", "1")

	// Route tables
	publicRTID := terraform.Output(t, opts, "public_route_table_id")
	assert.NotEmpty(t, publicRTID)
	assertRouteExists(t, client, publicRTID, "0.0.0.0/0", false, true)

	privateRTMap := terraform.OutputMap(t, opts, "private_route_table_ids")
	assert.Contains(t, privateRTMap, "az1-kubernetes")
	assertRouteExists(t, client, privateRTMap["az1-kubernetes"], "0.0.0.0/0", true, false)

	// S3 endpoint
	assert.NotEmpty(t, terraform.Output(t, opts, "s3_endpoint_id"))

	// EKS security group
	assert.NotEmpty(t, terraform.Output(t, opts, "eks_security_group_id"))

	// Flow logs
	assert.NotEmpty(t, terraform.Output(t, opts, "flow_log_id"))
	flowLogGroup := terraform.Output(t, opts, "flow_log_group_name")
	assert.Contains(t, flowLogGroup, "test-"+uniqueID)

	// kubernetes_subnet_id
	k8sSubnetID := terraform.Output(t, opts, "kubernetes_subnet_id")
	assert.Equal(t, subnetMap["az1-kubernetes"], k8sSubnetID)
}

func TestNetworking_PublicTopology(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	moduleDir := copyModuleToTemp(t)
	client := newEC2Client(t)
	azs := getAvailabilityZones(t, client)

	vpcCIDR := testVPCCIDR(1)

	subnets := buildSubnets(azs[0], []subnetSpec{
		{name: "az1-public", cidr: subnetCIDR(1, 0, "224/28"), public: true},
		{name: "az1-services", cidr: subnetCIDR(1, 0, "192/27"), public: false},
	})

	vars := map[string]interface{}{
		"create":                  true,
		"vpc_name":                "test-" + uniqueID + "-vpc",
		"address_space":           []string{vpcCIDR},
		"subnets":                 subnets,
		"environment":             "test",
		"workload":                "terratest",
		"region_abbv":             "usw2",
		"create_internet_gateway": true,
		"create_nat_gateways":     false,
		"enable_eks_networking":   false,
		"enable_flow_logs":        true,
		"flow_log_destination":    "cloud-watch-logs",
		"flow_log_retention_days": 30,
		"tags":                    map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, moduleDir, vars)
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// VPC + IGW exist
	assert.NotEmpty(t, terraform.Output(t, opts, "vpc_id"))
	assert.NotEmpty(t, terraform.Output(t, opts, "internet_gateway_id"))

	// No NAT gateways
	natMap := terraform.OutputMap(t, opts, "nat_gateway_ids")
	assert.Empty(t, natMap)

	// Public subnet has public IP mapping
	subnetMap := terraform.OutputMap(t, opts, "subnet_ids")
	assertSubnetPublicIP(t, client, subnetMap["az1-public"], true)

	// Public route table has IGW route
	publicRTID := terraform.Output(t, opts, "public_route_table_id")
	assertRouteExists(t, client, publicRTID, "0.0.0.0/0", false, true)

	// Private route table has NO default route (no NAT)
	privateRTMap := terraform.OutputMap(t, opts, "private_route_table_ids")
	assertNoDefaultRoute(t, client, privateRTMap["az1-services"])

	// No EKS SG
	assert.Empty(t, outputOrEmpty(t, opts, "eks_security_group_id"))

	// S3 endpoint exists
	assert.NotEmpty(t, terraform.Output(t, opts, "s3_endpoint_id"))

	// Flow log exists
	assert.NotEmpty(t, terraform.Output(t, opts, "flow_log_id"))
}

func TestNetworking_AirgappedTopology(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	moduleDir := copyModuleToTemp(t)
	client := newEC2Client(t)
	azs := getAvailabilityZones(t, client)

	vpcCIDR := testVPCCIDR(2)

	subnets := buildSubnets(azs[0], []subnetSpec{
		{name: "az1-kubernetes", cidr: subnetCIDR(2, 0, "0/26"), public: false},
	})

	vars := map[string]interface{}{
		"create":                  true,
		"vpc_name":                "test-" + uniqueID + "-vpc",
		"address_space":           []string{vpcCIDR},
		"subnets":                 subnets,
		"environment":             "test",
		"workload":                "terratest",
		"region_abbv":             "usw2",
		"create_internet_gateway": false,
		"create_nat_gateways":     false,
		"enable_eks_networking":   false,
		"enable_flow_logs":        false,
		"tags":                    map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, moduleDir, vars)
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// VPC exists
	assert.NotEmpty(t, terraform.Output(t, opts, "vpc_id"))

	// No IGW
	assert.Empty(t, outputOrEmpty(t, opts, "internet_gateway_id"))

	// No NAT
	natMap := terraform.OutputMap(t, opts, "nat_gateway_ids")
	assert.Empty(t, natMap)

	// No public route table
	assert.Empty(t, outputOrEmpty(t, opts, "public_route_table_id"))

	// Private route table with no default route
	privateRTMap := terraform.OutputMap(t, opts, "private_route_table_ids")
	assert.Contains(t, privateRTMap, "az1-kubernetes")
	assertNoDefaultRoute(t, client, privateRTMap["az1-kubernetes"])

	// S3 endpoint still exists (free, always created)
	assert.NotEmpty(t, terraform.Output(t, opts, "s3_endpoint_id"))

	// No EKS SG, no flow log
	assert.Empty(t, outputOrEmpty(t, opts, "eks_security_group_id"))
	assert.Empty(t, outputOrEmpty(t, opts, "flow_log_id"))
	assert.Empty(t, outputOrEmpty(t, opts, "flow_log_group_name"))
}

func TestNetworking_Disabled(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	moduleDir := copyModuleToTemp(t)

	vars := map[string]interface{}{
		"create":        false,
		"vpc_name":      "test-" + uniqueID + "-vpc",
		"address_space": []string{"10.200.99.0/24"},
		"subnets":       map[string]interface{}{},
		"environment":   "test",
		"workload":      "terratest",
		"region_abbv":   "usw2",
		"tags":          map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, moduleDir, vars)
	opts.PlanFilePath = filepath.Join(moduleDir, "plan.out")
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	assert.Empty(t, planStruct.ResourcePlannedValuesMap,
		"create=false should produce zero resources")
}

func TestNetworking_MultiAZNAT(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	moduleDir := copyModuleToTemp(t)
	client := newEC2Client(t)
	azs := getAvailabilityZones(t, client)

	vpcCIDR := testVPCCIDR(3)

	subnets := buildMultiAZSubnets(azs[:2], [][]subnetSpec{
		{
			{name: "az1-public", cidr: subnetCIDR(3, 0, "224/28"), public: true},
			{name: "az1-kubernetes", cidr: subnetCIDR(3, 0, "0/26"), public: false},
		},
		{
			{name: "az2-public", cidr: subnetCIDR(3, 0, "240/28"), public: true},
			{name: "az2-kubernetes", cidr: subnetCIDR(3, 0, "64/26"), public: false},
		},
	})

	vars := map[string]interface{}{
		"create":                  true,
		"vpc_name":                "test-" + uniqueID + "-vpc",
		"address_space":           []string{vpcCIDR},
		"subnets":                 subnets,
		"environment":             "test",
		"workload":                "terratest",
		"region_abbv":             "usw2",
		"create_internet_gateway": true,
		"create_nat_gateways":     true,
		"single_nat_gateway":      false,
		"enable_eks_networking":   false,
		"enable_flow_logs":        false,
		"tags":                    map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, moduleDir, vars)
	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// 2 NAT gateways
	natMap := terraform.OutputMap(t, opts, "nat_gateway_ids")
	assert.Len(t, natMap, 2, "per-AZ NAT should create 2 gateways")
	assert.Contains(t, natMap, "az1-public")
	assert.Contains(t, natMap, "az2-public")

	// Each private subnet routes to its AZ-matching NAT
	privateRTMap := terraform.OutputMap(t, opts, "private_route_table_ids")
	assertRouteExists(t, client, privateRTMap["az1-kubernetes"], "0.0.0.0/0", true, false)
	assertRouteExists(t, client, privateRTMap["az2-kubernetes"], "0.0.0.0/0", true, false)

	// Verify each NAT is in the correct AZ's public subnet
	subnetMap := terraform.OutputMap(t, opts, "subnet_ids")

	natGWs, err := client.DescribeNatGateways(&ec2.DescribeNatGatewaysInput{
		NatGatewayIds: stringSliceToAWSSlice(valuesFromMap(natMap)),
	})
	require.NoError(t, err)

	for _, gw := range natGWs.NatGateways {
		subnetID := *gw.SubnetId
		if subnetID != subnetMap["az1-public"] && subnetID != subnetMap["az2-public"] {
			t.Errorf("NAT gateway %s is in unexpected subnet %s", *gw.NatGatewayId, subnetID)
		}
	}
}

func stringSliceToAWSSlice(s []string) []*string {
	out := make([]*string, len(s))
	for i := range s {
		out[i] = &s[i]
	}
	return out
}

func valuesFromMap(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for _, v := range m {
		out = append(out, v)
	}
	return out
}
