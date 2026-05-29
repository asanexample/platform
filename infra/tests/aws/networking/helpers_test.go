package networking_test

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials/stscreds"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testRegion() string {
	if r := os.Getenv("TEST_AWS_REGION"); r != "" {
		return r
	}
	return "us-west-2"
}

func testRoleARN() string {
	return os.Getenv("TEST_ROLE_ARN")
}

func copyModuleToTemp(t *testing.T) string {
	t.Helper()

	moduleDir, err := filepath.Abs(filepath.Join("..", "..", "..", "modules", "aws", "networking"))
	require.NoError(t, err)

	fixtureDir, err := filepath.Abs(filepath.Join("fixtures"))
	require.NoError(t, err)

	tmpDir := t.TempDir()

	for _, srcDir := range []string{moduleDir, fixtureDir} {
		entries, err := os.ReadDir(srcDir)
		require.NoError(t, err)
		for _, entry := range entries {
			if entry.IsDir() || filepath.Ext(entry.Name()) != ".tf" {
				continue
			}
			src, err := os.Open(filepath.Join(srcDir, entry.Name()))
			require.NoError(t, err)
			dst, err := os.Create(filepath.Join(tmpDir, entry.Name()))
			require.NoError(t, err)
			_, err = io.Copy(dst, src)
			require.NoError(t, err)
			src.Close()
			dst.Close()
		}
	}

	return tmpDir
}

func newTerraformOptions(t *testing.T, moduleDir string, vars map[string]interface{}) *terraform.Options {
	t.Helper()

	region := testRegion()
	roleARN := testRoleARN()

	vars["test_region"] = region
	if roleARN != "" {
		vars["test_role_arn"] = roleARN
	}

	return &terraform.Options{
		TerraformDir:    moduleDir,
		TerraformBinary: "tofu",
		Vars:            vars,
		NoColor:         true,
	}
}

func newEC2Client(t *testing.T) *ec2.EC2 {
	t.Helper()
	region := testRegion()
	sess, err := session.NewSession(&aws.Config{Region: aws.String(region)})
	require.NoError(t, err)

	roleARN := testRoleARN()
	if roleARN != "" {
		creds := stscreds.NewCredentials(sess, roleARN)
		return ec2.New(sess, &aws.Config{Credentials: creds})
	}
	return ec2.New(sess)
}

func assertRouteExists(t *testing.T, client *ec2.EC2, rtID string, destCIDR string, expectNAT bool, expectIGW bool) {
	t.Helper()

	out, err := client.DescribeRouteTables(&ec2.DescribeRouteTablesInput{
		RouteTableIds: []*string{aws.String(rtID)},
	})
	require.NoError(t, err)
	require.Len(t, out.RouteTables, 1)

	found := false
	for _, route := range out.RouteTables[0].Routes {
		if route.DestinationCidrBlock != nil && *route.DestinationCidrBlock == destCIDR {
			found = true
			if expectNAT {
				assert.NotNil(t, route.NatGatewayId, "route %s should target a NAT gateway", destCIDR)
			}
			if expectIGW {
				assert.NotNil(t, route.GatewayId, "route %s should target an IGW", destCIDR)
			}
			break
		}
	}
	assert.True(t, found, "route table %s should have route to %s", rtID, destCIDR)
}

func assertNoDefaultRoute(t *testing.T, client *ec2.EC2, rtID string) {
	t.Helper()

	out, err := client.DescribeRouteTables(&ec2.DescribeRouteTablesInput{
		RouteTableIds: []*string{aws.String(rtID)},
	})
	require.NoError(t, err)
	require.Len(t, out.RouteTables, 1)

	for _, route := range out.RouteTables[0].Routes {
		if route.DestinationCidrBlock != nil && *route.DestinationCidrBlock == "0.0.0.0/0" {
			t.Errorf("route table %s should NOT have a default route, but found one", rtID)
		}
	}
}

func assertSubnetPublicIP(t *testing.T, client *ec2.EC2, subnetID string, expectPublic bool) {
	t.Helper()

	out, err := client.DescribeSubnets(&ec2.DescribeSubnetsInput{
		SubnetIds: []*string{aws.String(subnetID)},
	})
	require.NoError(t, err)
	require.Len(t, out.Subnets, 1)

	actual := aws.BoolValue(out.Subnets[0].MapPublicIpOnLaunch)
	assert.Equal(t, expectPublic, actual,
		"subnet %s: expected MapPublicIpOnLaunch=%v, got %v", subnetID, expectPublic, actual)
}

func assertSubnetTag(t *testing.T, client *ec2.EC2, subnetID string, tagKey string, expectedValue string) {
	t.Helper()

	out, err := client.DescribeSubnets(&ec2.DescribeSubnetsInput{
		SubnetIds: []*string{aws.String(subnetID)},
	})
	require.NoError(t, err)
	require.Len(t, out.Subnets, 1)

	found := false
	for _, tag := range out.Subnets[0].Tags {
		if aws.StringValue(tag.Key) == tagKey {
			found = true
			assert.Equal(t, expectedValue, aws.StringValue(tag.Value),
				"subnet %s tag %s", subnetID, tagKey)
			break
		}
	}
	assert.True(t, found, "subnet %s should have tag %s", subnetID, tagKey)
}

func getAvailabilityZones(t *testing.T, client *ec2.EC2) []string {
	t.Helper()

	out, err := client.DescribeAvailabilityZones(&ec2.DescribeAvailabilityZonesInput{
		Filters: []*ec2.Filter{
			{Name: aws.String("state"), Values: []*string{aws.String("available")}},
		},
	})
	require.NoError(t, err)
	require.True(t, len(out.AvailabilityZones) >= 2, "need at least 2 AZs")

	azs := make([]string, len(out.AvailabilityZones))
	for i, az := range out.AvailabilityZones {
		azs[i] = aws.StringValue(az.ZoneName)
	}
	return azs
}

func buildSubnets(azName string, specs []subnetSpec) map[string]interface{} {
	subnets := map[string]interface{}{}
	for _, s := range specs {
		subnets[s.name] = map[string]interface{}{
			"address_prefixes":  []string{s.cidr},
			"availability_zone": azName,
			"public":            s.public,
		}
	}
	return subnets
}

func buildMultiAZSubnets(azNames []string, specs [][]subnetSpec) map[string]interface{} {
	subnets := map[string]interface{}{}
	for i, azSpecs := range specs {
		for _, s := range azSpecs {
			subnets[s.name] = map[string]interface{}{
				"address_prefixes":  []string{s.cidr},
				"availability_zone": azNames[i],
				"public":            s.public,
			}
		}
	}
	return subnets
}

type subnetSpec struct {
	name   string
	cidr   string
	public bool
}

func outputOrEmpty(t *testing.T, opts *terraform.Options, name string) string {
	t.Helper()
	out, err := terraform.OutputE(t, opts, name)
	if err != nil {
		return ""
	}
	return out
}

func testVPCCIDR(index int) string {
	return fmt.Sprintf("10.200.%d.0/24", index)
}

func subnetCIDR(vpcIndex int, subnetIndex int, bits string) string {
	return fmt.Sprintf("10.200.%d.%s", vpcIndex, bits)
}
