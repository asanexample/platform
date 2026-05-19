package eks_test

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials/stscreds"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/eks"
	"github.com/aws/aws-sdk-go/service/iam"
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
	if r, ok := os.LookupEnv("TEST_ROLE_ARN"); ok {
		return r
	}
	return "arn:aws:iam::157263244316:role/OrganizationAccountAccessRole"
}

func copyFixtureToTemp(t *testing.T) string {
	t.Helper()

	fixtureDir, err := filepath.Abs("fixtures")
	require.NoError(t, err)

	modulesBase, err := filepath.Abs(filepath.Join("..", "..", "..", "modules"))
	require.NoError(t, err)

	tmpDir := t.TempDir()

	entries, err := os.ReadDir(fixtureDir)
	require.NoError(t, err)
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".tf" {
			continue
		}

		data, err := os.ReadFile(filepath.Join(fixtureDir, entry.Name()))
		require.NoError(t, err)

		content := string(data)
		content = strings.ReplaceAll(content, "../../../../modules/aws/networking", filepath.Join(modulesBase, "aws", "networking"))
		content = strings.ReplaceAll(content, "../../../../modules/aws/eks", filepath.Join(modulesBase, "aws", "eks"))

		err = os.WriteFile(filepath.Join(tmpDir, entry.Name()), []byte(content), 0644)
		require.NoError(t, err)
	}

	lockFile := filepath.Join(fixtureDir, ".terraform.lock.hcl")
	if _, err := os.Stat(lockFile); err == nil {
		src, err := os.Open(lockFile)
		require.NoError(t, err)
		defer src.Close()
		dst, err := os.Create(filepath.Join(tmpDir, ".terraform.lock.hcl"))
		require.NoError(t, err)
		defer dst.Close()
		_, err = io.Copy(dst, src)
		require.NoError(t, err)
	}

	return tmpDir
}

func newSession(t *testing.T) *session.Session {
	t.Helper()
	region := testRegion()
	sess, err := session.NewSession(&aws.Config{Region: aws.String(region)})
	require.NoError(t, err)

	roleARN := testRoleARN()
	if roleARN != "" {
		creds := stscreds.NewCredentials(sess, roleARN)
		sess, err = session.NewSession(&aws.Config{
			Region:      aws.String(region),
			Credentials: creds,
		})
		require.NoError(t, err)
	}
	return sess
}

func newEKSClient(t *testing.T) *eks.EKS {
	t.Helper()
	return eks.New(newSession(t))
}

func newIAMClient(t *testing.T) *iam.IAM {
	t.Helper()
	return iam.New(newSession(t))
}

func newTerraformOptions(t *testing.T, fixtureDir string, vars map[string]interface{}) *terraform.Options {
	t.Helper()

	region := testRegion()
	roleARN := testRoleARN()

	vars["test_region"] = region
	if roleARN != "" {
		vars["test_role_arn"] = roleARN
	}

	return &terraform.Options{
		TerraformDir:    fixtureDir,
		TerraformBinary: "tofu",
		Vars:            vars,
		NoColor:         true,
	}
}

func assertClusterActive(t *testing.T, client *eks.EKS, clusterName string) {
	t.Helper()

	out, err := client.DescribeCluster(&eks.DescribeClusterInput{
		Name: aws.String(clusterName),
	})
	require.NoError(t, err)
	assert.Equal(t, "ACTIVE", aws.StringValue(out.Cluster.Status),
		"cluster %s should be ACTIVE", clusterName)
}

func assertClusterVersion(t *testing.T, client *eks.EKS, clusterName string, expectedVersion string) {
	t.Helper()

	out, err := client.DescribeCluster(&eks.DescribeClusterInput{
		Name: aws.String(clusterName),
	})
	require.NoError(t, err)
	assert.Equal(t, expectedVersion, aws.StringValue(out.Cluster.Version),
		"cluster %s should be version %s", clusterName, expectedVersion)
}

func assertOIDCProviderExists(t *testing.T, client *iam.IAM, providerARN string) {
	t.Helper()

	_, err := client.GetOpenIDConnectProvider(&iam.GetOpenIDConnectProviderInput{
		OpenIDConnectProviderArn: aws.String(providerARN),
	})
	require.NoError(t, err, "OIDC provider %s should exist", providerARN)
}

func assertNodeGroupActive(t *testing.T, client *eks.EKS, clusterName string, nodeGroupName string) {
	t.Helper()

	out, err := client.DescribeNodegroup(&eks.DescribeNodegroupInput{
		ClusterName:   aws.String(clusterName),
		NodegroupName: aws.String(nodeGroupName),
	})
	require.NoError(t, err)
	assert.Equal(t, "ACTIVE", aws.StringValue(out.Nodegroup.Status),
		"node group %s should be ACTIVE", nodeGroupName)
}

func outputOrEmpty(t *testing.T, opts *terraform.Options, name string) string {
	t.Helper()
	out, err := terraform.OutputE(t, opts, name)
	if err != nil {
		return ""
	}
	return out
}

func copyVars(src map[string]interface{}) map[string]interface{} {
	dst := make(map[string]interface{}, len(src))
	for k, v := range src {
		dst[k] = v
	}
	return dst
}

func testVPCCIDR(index int) string {
	return fmt.Sprintf("10.201.%d.0/24", index)
}

func subnetCIDR(vpcIndex int, bits string) string {
	return fmt.Sprintf("10.201.%d.%s", vpcIndex, bits)
}
