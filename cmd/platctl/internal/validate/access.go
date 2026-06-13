package validate

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/asanexample/platform/cmd/platctl/internal/config"
)

// IAMCheck verifies AWS SSO sessions, cross-account role assumptions,
// kubeconfig role access, and S3 state backend connectivity.
// After Check completes, ExpiredProfiles contains any profiles whose SSO
// sessions could not be validated.
type IAMCheck struct {
	Name              string
	Profiles          []string
	DefaultProfile    string // profile used for cross-account role assumption (e.g., "management")
	Accounts          map[string]config.IAMAccountConfig
	KubeconfigEntries []config.KubeconfigEntry
	StateBucket       string
	Run               CommandRunner

	// ExpiredProfiles is populated after Check runs; callers can inspect it to
	// decide whether to prompt for re-authentication.
	ExpiredProfiles []string
}

// CheckName returns the display name for skip messages.
func (c *IAMCheck) CheckName() string { return c.Name }

// Check runs all IAM sub-checks, collecting every failure rather than
// failing fast. The result aggregates per-profile, per-role, and state-backend
// outcomes into a single CheckResult.
func (c *IAMCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	var details []string
	var failures []string
	var summaryParts []string

	c.ExpiredProfiles = nil

	// 1. SSO session check for each profile
	for _, profile := range c.Profiles {
		out, err := c.Run(ctx, "aws", "sts", "get-caller-identity", "--profile", profile)
		if err != nil {
			c.ExpiredProfiles = append(c.ExpiredProfiles, profile)
			outStr := strings.TrimSpace(string(out))
			details = append(details,
				fmt.Sprintf("SSO session expired for profile '%s'", profile),
				fmt.Sprintf("Error: %s", outStr),
				fmt.Sprintf("Run: aws sso login --profile %s", profile),
			)
			failures = append(failures, fmt.Sprintf("%s: session expired", profile))
			summaryParts = append(summaryParts, fmt.Sprintf("%s: EXPIRED", profile))
		} else {
			details = append(details, fmt.Sprintf("SSO session valid for profile '%s'", profile))
			summaryParts = append(summaryParts, fmt.Sprintf("%s: ok", profile))
		}
	}

	// 2. Role assumption check for each account
	for accountName, account := range c.Accounts {
		if account.DeployerRoleARN == "" {
			continue
		}

		out, err := c.Run(ctx, "aws", "sts", "assume-role",
			"--role-arn", account.DeployerRoleARN,
			"--role-session-name", "validate",
			"--duration-seconds", "900",
			"--profile", c.DefaultProfile,
		)
		if err != nil {
			outStr := strings.TrimSpace(string(out))
			details = append(details,
				fmt.Sprintf("Cannot assume role '%s' in account '%s'", account.DeployerRoleARN, accountName),
				fmt.Sprintf("Error: %s", outStr),
				"This may indicate the role does not exist, the trust policy is wrong, or the SSO session expired.",
				fmt.Sprintf("Run: aws iam get-role --role-name %s --profile %s",
					roleNameFromARN(account.DeployerRoleARN), accountName),
				fmt.Sprintf("Run: aws sso login --profile %s", c.DefaultProfile),
			)
			failures = append(failures, fmt.Sprintf("%s/%s: assume-role failed",
				accountName, roleNameFromARN(account.DeployerRoleARN)))
			summaryParts = append(summaryParts,
				fmt.Sprintf("%s: %s FAILED", accountName, roleNameFromARN(account.DeployerRoleARN)))
		} else {
			details = append(details,
				fmt.Sprintf("Role assumption OK: %s (%s)", roleNameFromARN(account.DeployerRoleARN), accountName))
			summaryParts = append(summaryParts,
				fmt.Sprintf("%s: %s ok", accountName, roleNameFromARN(account.DeployerRoleARN)))
		}
	}

	// 3. Kubeconfig role assumption check
	for _, entry := range c.KubeconfigEntries {
		if entry.KubectlRoleARN == "" {
			continue
		}

		// Determine which profile to use for the assume-role call
		assumeProfile := entry.Profile
		if assumeProfile == "" {
			assumeProfile = c.DefaultProfile
		}

		out, err := c.Run(ctx, "aws", "sts", "assume-role",
			"--role-arn", entry.KubectlRoleARN,
			"--role-session-name", "validate",
			"--duration-seconds", "900",
			"--profile", assumeProfile,
		)
		if err != nil {
			outStr := strings.TrimSpace(string(out))
			details = append(details,
				fmt.Sprintf("Cannot assume kubectl role '%s' for cluster '%s'", entry.KubectlRoleARN, entry.Cluster),
				fmt.Sprintf("Error: %s", outStr),
				fmt.Sprintf("Profile used: %s", assumeProfile),
				"This role is needed for kubectl access to the cluster.",
				fmt.Sprintf("Run: aws iam get-role --role-name %s --profile %s",
					roleNameFromARN(entry.KubectlRoleARN), assumeProfile),
				fmt.Sprintf("Run: aws sso login --profile %s", assumeProfile),
			)
			failures = append(failures, fmt.Sprintf("%s/%s: kubectl role failed",
				entry.Cluster, roleNameFromARN(entry.KubectlRoleARN)))
			summaryParts = append(summaryParts,
				fmt.Sprintf("%s: %s FAILED", entry.Alias, roleNameFromARN(entry.KubectlRoleARN)))
		} else {
			details = append(details,
				fmt.Sprintf("Kubectl role assumption OK: %s (%s)", roleNameFromARN(entry.KubectlRoleARN), entry.Alias))
			summaryParts = append(summaryParts,
				fmt.Sprintf("%s: %s ok", entry.Alias, roleNameFromARN(entry.KubectlRoleARN)))
		}
	}

	// 4. State bucket accessibility
	if c.StateBucket != "" {
		out, err := c.Run(ctx, "aws", "s3api", "head-bucket",
			"--bucket", c.StateBucket, "--profile", c.DefaultProfile)
		if err != nil {
			outStr := strings.TrimSpace(string(out))
			details = append(details,
				fmt.Sprintf("Cannot access state bucket '%s'", c.StateBucket),
				fmt.Sprintf("Error: %s", outStr),
				fmt.Sprintf("The '%s' profile may lack S3 permissions or the bucket may not exist.", c.DefaultProfile),
				fmt.Sprintf("Run: aws s3api head-bucket --bucket %s --profile %s", c.StateBucket, c.DefaultProfile),
			)
			failures = append(failures, "state-backend: access denied")
			summaryParts = append(summaryParts, "state-backend: FAILED")
		} else {
			details = append(details, fmt.Sprintf("State bucket '%s': accessible", c.StateBucket))
			summaryParts = append(summaryParts, "state-backend: ok")
		}
	}

	// Build result
	summary := strings.Join(summaryParts, ", ")
	if len(failures) > 0 {
		return CheckResult{
			Name:    c.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d sub-check(s) failed: %s", len(failures), strings.Join(failures, "; ")),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	return CheckResult{
		Name:    c.Name,
		Status:  "ok",
		Message: summary,
		Details: details,
		Elapsed: time.Since(start),
	}
}

// roleNameFromARN extracts the role name from an IAM role ARN.
// e.g., "arn:aws:iam::123456789012:role/PlatformDeployer" -> "PlatformDeployer"
func roleNameFromARN(arn string) string {
	parts := strings.Split(arn, "/")
	if len(parts) > 1 {
		return parts[len(parts)-1]
	}
	return arn
}
