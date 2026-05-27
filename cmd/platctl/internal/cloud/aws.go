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

// RegionFromAuth extracts the AWS region from an auth map, defaulting to us-east-1.
func RegionFromAuth(auth map[string]string) string {
	if region, ok := auth["region"]; ok && region != "" {
		return region
	}
	return "us-east-1"
}

// SecretExists checks whether a Secrets Manager secret exists.
func (a *AWS) SecretExists(ctx context.Context, secretID string, auth map[string]string) (bool, error) {
	args := []string{
		"secretsmanager", "describe-secret",
		"--secret-id", secretID,
		"--region", RegionFromAuth(auth),
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

// ForceDeleteSecret immediately deletes a Secrets Manager secret with no recovery window.
// Used to clean up leftover secrets (pending deletion or orphaned) before a fresh deploy.
func (a *AWS) ForceDeleteSecret(ctx context.Context, secretID string, auth map[string]string) error {
	args := []string{
		"secretsmanager", "delete-secret",
		"--secret-id", secretID,
		"--force-delete-without-recovery",
		"--region", RegionFromAuth(auth),
	}
	if profile, ok := auth["profile"]; ok {
		args = append(args, "--profile", profile)
	}

	cmd := exec.CommandContext(ctx, "aws", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("force-deleting secret %s: %s", secretID, strings.TrimSpace(string(out)))
	}
	return nil
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
		"--region", RegionFromAuth(auth),
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
