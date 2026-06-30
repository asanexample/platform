package cost_export_test

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

func testRegion() string {
	if r := os.Getenv("TEST_AWS_REGION"); r != "" {
		return r
	}
	return "us-east-1"
}

func testRoleARN() string {
	return os.Getenv("TEST_ROLE_ARN")
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
		content = strings.ReplaceAll(content, "../../../../modules/aws/cost-export", filepath.Join(modulesBase, "aws", "cost-export"))

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
