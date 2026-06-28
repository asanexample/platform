package cloud

// identitycenter.go is the live AWS Identity Center plane for ADR-088 temporary-power
// activation (`platctl access grant`/`revoke`). Like the rest of platctl it shells out to
// the AWS CLI rather than pulling in the AWS SDK — these are infrequent break-glass
// operations. A grant is a direct USER account-assignment to the role's permission set on
// the accounts where that permission set already lives; revoke deletes it.

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
	"strings"
)

// IdentityCenter targets one AWS Identity Center instance via an AWS CLI profile + region.
type IdentityCenter struct {
	Profile string // AWS CLI profile (Identity Center lives in the management account → "management")
	Region  string // the Identity Center region
}

// run executes `aws sso-admin|identitystore <args…>` with the profile/region appended and
// returns stdout. Stderr is folded into the error so AWS's message survives.
func (ic IdentityCenter) run(ctx context.Context, args ...string) ([]byte, error) {
	full := append([]string{}, args...)
	full = append(full, "--output", "json", "--region", ic.Region)
	if ic.Profile != "" {
		full = append(full, "--profile", ic.Profile)
	}
	cmd := exec.CommandContext(ctx, "aws", full...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		return nil, fmt.Errorf("aws %s: %s", strings.Join(args, " "), msg)
	}
	return []byte(stdout.String()), nil
}

// Instance resolves the (single) Identity Center instance ARN + identity-store ID.
func (ic IdentityCenter) Instance(ctx context.Context) (instanceARN, identityStoreID string, err error) {
	out, err := ic.run(ctx, "sso-admin", "list-instances")
	if err != nil {
		return "", "", err
	}
	var resp struct {
		Instances []struct {
			InstanceArn     string `json:"InstanceArn"`
			IdentityStoreId string `json:"IdentityStoreId"`
		} `json:"Instances"`
	}
	if err := json.Unmarshal(out, &resp); err != nil {
		return "", "", fmt.Errorf("parsing list-instances: %w", err)
	}
	if len(resp.Instances) == 0 {
		return "", "", fmt.Errorf("no Identity Center instance found (wrong profile/region, or IC not enabled?)")
	}
	return resp.Instances[0].InstanceArn, resp.Instances[0].IdentityStoreId, nil
}

// UserID resolves an Identity Store user ID by username (the IC user_name = Person.Name).
func (ic IdentityCenter) UserID(ctx context.Context, identityStoreID, username string) (string, error) {
	out, err := ic.run(ctx, "identitystore", "list-users",
		"--identity-store-id", identityStoreID,
		"--filters", "AttributePath=UserName,AttributeValue="+username)
	if err != nil {
		return "", err
	}
	var resp struct {
		Users []struct {
			UserId string `json:"UserId"`
		} `json:"Users"`
	}
	if err := json.Unmarshal(out, &resp); err != nil {
		return "", fmt.Errorf("parsing list-users: %w", err)
	}
	if len(resp.Users) == 0 {
		return "", fmt.Errorf("no Identity Center user named %q (is the roster applied? — the generator creates it)", username)
	}
	return resp.Users[0].UserId, nil
}

// PermissionSetARN finds a permission set's ARN by its name (no get-by-name API → list +
// describe). Errors clearly if the named set isn't provisioned (e.g. an on-demand role with
// no standing holder has no permission set yet — that's the controller's to create).
func (ic IdentityCenter) PermissionSetARN(ctx context.Context, instanceARN, name string) (string, error) {
	out, err := ic.run(ctx, "sso-admin", "list-permission-sets", "--instance-arn", instanceARN)
	if err != nil {
		return "", err
	}
	var list struct {
		PermissionSets []string `json:"PermissionSets"`
	}
	if err := json.Unmarshal(out, &list); err != nil {
		return "", fmt.Errorf("parsing list-permission-sets: %w", err)
	}
	for _, psARN := range list.PermissionSets {
		dOut, err := ic.run(ctx, "sso-admin", "describe-permission-set",
			"--instance-arn", instanceARN, "--permission-set-arn", psARN)
		if err != nil {
			return "", err
		}
		var d struct {
			PermissionSet struct {
				Name string `json:"Name"`
			} `json:"PermissionSet"`
		}
		if err := json.Unmarshal(dOut, &d); err != nil {
			return "", fmt.Errorf("parsing describe-permission-set: %w", err)
		}
		if d.PermissionSet.Name == name {
			return psARN, nil
		}
	}
	return "", fmt.Errorf("permission set %q is not provisioned in this Identity Center instance — there is no standing assignment to attach a temporary grant to (the activation controller would create it; platctl cannot)", name)
}

// ProvisionedAccounts lists the account IDs where a permission set is already provisioned —
// the live targets for the temporary assignment (so the borrow matches the role's real
// footprint, no SOPS/account-ID knowledge needed). Sorted for stable output.
func (ic IdentityCenter) ProvisionedAccounts(ctx context.Context, instanceARN, psARN string) ([]string, error) {
	out, err := ic.run(ctx, "sso-admin", "list-accounts-for-provisioned-permission-set",
		"--instance-arn", instanceARN, "--permission-set-arn", psARN)
	if err != nil {
		return nil, err
	}
	var resp struct {
		AccountIds []string `json:"AccountIds"`
	}
	if err := json.Unmarshal(out, &resp); err != nil {
		return nil, fmt.Errorf("parsing list-accounts-for-provisioned-permission-set: %w", err)
	}
	sort.Strings(resp.AccountIds)
	return resp.AccountIds, nil
}

// assignmentStatus is the shared shape of create/delete-account-assignment responses.
type assignmentStatus struct {
	Status        string `json:"Status"`        // IN_PROGRESS | SUCCEEDED | FAILED
	FailureReason string `json:"FailureReason"` //
}

// assignArgs builds the common create/delete-account-assignment argument list.
func assignArgs(verb, instanceARN, account, psARN, userID string) []string {
	return []string{
		"sso-admin", verb,
		"--instance-arn", instanceARN,
		"--target-id", account, "--target-type", "AWS_ACCOUNT",
		"--permission-set-arn", psARN,
		"--principal-type", "USER", "--principal-id", userID,
	}
}

// CreateAssignment mints a USER account-assignment (permission set → account). AWS
// provisions assignments serially per permission set (the race that bit the #888 cutover),
// so callers MUST invoke this one account at a time. Returns AWS's status verbatim.
func (ic IdentityCenter) CreateAssignment(ctx context.Context, instanceARN, account, psARN, userID string) (string, error) {
	out, err := ic.run(ctx, assignArgs("create-account-assignment", instanceARN, account, psARN, userID)...)
	if err != nil {
		return "", err
	}
	var resp struct {
		AccountAssignmentCreationStatus assignmentStatus `json:"AccountAssignmentCreationStatus"`
	}
	if err := json.Unmarshal(out, &resp); err != nil {
		return "", fmt.Errorf("parsing create-account-assignment: %w", err)
	}
	s := resp.AccountAssignmentCreationStatus
	if s.Status == "FAILED" {
		return s.Status, fmt.Errorf("assignment on %s FAILED: %s", account, s.FailureReason)
	}
	return s.Status, nil
}

// DeleteAssignment removes a USER account-assignment. Returns AWS's status verbatim.
func (ic IdentityCenter) DeleteAssignment(ctx context.Context, instanceARN, account, psARN, userID string) (string, error) {
	out, err := ic.run(ctx, assignArgs("delete-account-assignment", instanceARN, account, psARN, userID)...)
	if err != nil {
		return "", err
	}
	var resp struct {
		AccountAssignmentDeletionStatus assignmentStatus `json:"AccountAssignmentDeletionStatus"`
	}
	if err := json.Unmarshal(out, &resp); err != nil {
		return "", fmt.Errorf("parsing delete-account-assignment: %w", err)
	}
	s := resp.AccountAssignmentDeletionStatus
	if s.Status == "FAILED" {
		return s.Status, fmt.Errorf("assignment deletion on %s FAILED: %s", account, s.FailureReason)
	}
	return s.Status, nil
}
