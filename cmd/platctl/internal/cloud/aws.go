package cloud

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// AWS implements AWSClient using the AWS CLI.
// Avoids an AWS SDK dependency for operations that are infrequent (pre-apply checks).
type AWS struct{}

// SecretExists checks whether a Secrets Manager secret exists.
func (a *AWS) SecretExists(ctx context.Context, secretID string, auth map[string]string) (bool, error) {
	args := []string{
		"secretsmanager", "describe-secret",
		"--secret-id", secretID,
		"--region", "us-east-1",
	}
	if profile, ok := auth["profile"]; ok {
		args = append(args, "--profile", profile)
	}

	cmd := exec.CommandContext(ctx, "aws", args...)
	if err := cmd.Run(); err != nil {
		// Non-zero exit = secret doesn't exist (or access denied)
		return false, nil
	}
	return true, nil
}

// DescribeEKSENIs queries the ENI IPs attached to an EKS cluster's API server.
// Returns the private IPs of the cross-account ENIs.
func (a *AWS) DescribeEKSENIs(ctx context.Context, clusterName string, auth map[string]string) ([]string, error) {
	args := []string{
		"ec2", "describe-network-interfaces",
		"--filters",
		fmt.Sprintf("Name=tag:cluster.k8s.amazonaws.com/name,Values=%s", clusterName),
		"Name=interface-type,Values=vpc_endpoint",
		"--query", "NetworkInterfaces[].PrivateIpAddress",
		"--output", "text",
		"--region", "us-east-1",
	}
	if profile, ok := auth["profile"]; ok {
		args = append(args, "--profile", profile)
	}

	cmd := exec.CommandContext(ctx, "aws", args...)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("describing EKS ENIs for %s: %w", clusterName, err)
	}

	text := strings.TrimSpace(string(out))
	if text == "" || text == "None" {
		return nil, nil
	}
	return strings.Fields(text), nil
}
