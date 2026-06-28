/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package awsidc

import (
	"context"
	"errors"
	"fmt"
	"sort"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/identitystore"
	idstypes "github.com/aws/aws-sdk-go-v2/service/identitystore/types"
	"github.com/aws/aws-sdk-go-v2/service/ssoadmin"
	ssotypes "github.com/aws/aws-sdk-go-v2/service/ssoadmin/types"
	"go.opentelemetry.io/contrib/instrumentation/github.com/aws/aws-sdk-go-v2/otelaws"

	"github.com/asanexample/platform/operators/activation/internal/plane"
)

// Client is the live AWS Identity Center API, backed by AWS SDK Go v2. It satisfies API.
// AWS faults are translated into the package sentinels so the adapter stays cloud-agnostic.
type Client struct {
	sso *ssoadmin.Client
	ids *identitystore.Client
}

// NewClient builds a Client from the default AWS config (EKS Pod Identity in cluster), with
// otelaws tracing middleware so every AWS call is a child span.
func NewClient(ctx context.Context, region string) (*Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("loading AWS config: %w", err)
	}
	otelaws.AppendMiddlewares(&cfg.APIOptions)
	return &Client{sso: ssoadmin.NewFromConfig(cfg), ids: identitystore.NewFromConfig(cfg)}, nil
}

// translate maps AWS faults to the adapter's retryable sentinels; other errors pass through.
func translate(err error) error {
	if err == nil {
		return nil
	}
	var conflict *ssotypes.ConflictException
	if errors.As(err, &conflict) {
		return fmt.Errorf("%w: %v", ErrConflict, err)
	}
	var throttle *ssotypes.ThrottlingException
	if errors.As(err, &throttle) {
		return fmt.Errorf("%w: %v", ErrThrottled, err)
	}
	return err
}

func mapStatus(s ssotypes.StatusValues) Status {
	switch s {
	case ssotypes.StatusValuesSucceeded:
		return StatusSucceeded
	case ssotypes.StatusValuesFailed:
		return StatusFailed
	default:
		return StatusInProgress
	}
}

// Instance implements API.
func (c *Client) Instance(ctx context.Context) (string, string, error) {
	out, err := c.sso.ListInstances(ctx, &ssoadmin.ListInstancesInput{})
	if err != nil {
		return "", "", fmt.Errorf("list-instances: %w", err)
	}
	if len(out.Instances) == 0 {
		return "", "", plane.Terminalf("no Identity Center instance found")
	}
	return aws.ToString(out.Instances[0].InstanceArn), aws.ToString(out.Instances[0].IdentityStoreId), nil
}

// UserID implements API.
func (c *Client) UserID(ctx context.Context, identityStoreID, username string) (string, error) {
	out, err := c.ids.ListUsers(ctx, &identitystore.ListUsersInput{
		IdentityStoreId: aws.String(identityStoreID),
		Filters:         []idstypes.Filter{{AttributePath: aws.String("UserName"), AttributeValue: aws.String(username)}},
	})
	if err != nil {
		return "", fmt.Errorf("list-users: %w", err)
	}
	if len(out.Users) == 0 {
		return "", plane.Terminalf("no Identity Center user named %q", username)
	}
	return aws.ToString(out.Users[0].UserId), nil
}

// PermissionSetARN implements API (no get-by-name API → list + describe).
func (c *Client) PermissionSetARN(ctx context.Context, instanceArn, name string) (string, error) {
	p := ssoadmin.NewListPermissionSetsPaginator(c.sso, &ssoadmin.ListPermissionSetsInput{InstanceArn: aws.String(instanceArn)})
	for p.HasMorePages() {
		page, err := p.NextPage(ctx)
		if err != nil {
			return "", fmt.Errorf("list-permission-sets: %w", err)
		}
		for _, psArn := range page.PermissionSets {
			d, err := c.sso.DescribePermissionSet(ctx, &ssoadmin.DescribePermissionSetInput{
				InstanceArn: aws.String(instanceArn), PermissionSetArn: aws.String(psArn),
			})
			if err != nil {
				return "", fmt.Errorf("describe-permission-set: %w", err)
			}
			if aws.ToString(d.PermissionSet.Name) == name {
				return psArn, nil
			}
		}
	}
	return "", plane.Terminalf("permission set %q is not provisioned in this Identity Center instance", name)
}

// ProvisionedAccounts implements API.
func (c *Client) ProvisionedAccounts(ctx context.Context, instanceArn, psArn string) ([]string, error) {
	p := ssoadmin.NewListAccountsForProvisionedPermissionSetPaginator(c.sso, &ssoadmin.ListAccountsForProvisionedPermissionSetInput{
		InstanceArn: aws.String(instanceArn), PermissionSetArn: aws.String(psArn),
	})
	var accounts []string
	for p.HasMorePages() {
		page, err := p.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("list-accounts-for-provisioned-permission-set: %w", err)
		}
		accounts = append(accounts, page.AccountIds...)
	}
	sort.Strings(accounts)
	return accounts, nil
}

// CreateAssignment implements API.
func (c *Client) CreateAssignment(ctx context.Context, in AssignmentInput) (string, Status, string, error) {
	out, err := c.sso.CreateAccountAssignment(ctx, &ssoadmin.CreateAccountAssignmentInput{
		InstanceArn:      aws.String(in.InstanceArn),
		TargetId:         aws.String(in.AccountID),
		TargetType:       ssotypes.TargetTypeAwsAccount,
		PermissionSetArn: aws.String(in.PermissionSetArn),
		PrincipalType:    ssotypes.PrincipalTypeUser,
		PrincipalId:      aws.String(in.PrincipalID),
	})
	if err != nil {
		return "", "", "", translate(err)
	}
	s := out.AccountAssignmentCreationStatus
	return aws.ToString(s.RequestId), mapStatus(s.Status), aws.ToString(s.FailureReason), nil
}

// DescribeCreateStatus implements API.
func (c *Client) DescribeCreateStatus(ctx context.Context, instanceArn, requestID string) (Status, string, error) {
	out, err := c.sso.DescribeAccountAssignmentCreationStatus(ctx, &ssoadmin.DescribeAccountAssignmentCreationStatusInput{
		InstanceArn: aws.String(instanceArn), AccountAssignmentCreationRequestId: aws.String(requestID),
	})
	if err != nil {
		return "", "", translate(err)
	}
	s := out.AccountAssignmentCreationStatus
	return mapStatus(s.Status), aws.ToString(s.FailureReason), nil
}

// DeleteAssignment implements API. A delete of an already-absent assignment is success.
func (c *Client) DeleteAssignment(ctx context.Context, in AssignmentInput) (string, Status, string, error) {
	out, err := c.sso.DeleteAccountAssignment(ctx, &ssoadmin.DeleteAccountAssignmentInput{
		InstanceArn:      aws.String(in.InstanceArn),
		TargetId:         aws.String(in.AccountID),
		TargetType:       ssotypes.TargetTypeAwsAccount,
		PermissionSetArn: aws.String(in.PermissionSetArn),
		PrincipalType:    ssotypes.PrincipalTypeUser,
		PrincipalId:      aws.String(in.PrincipalID),
	})
	if err != nil {
		var notFound *ssotypes.ResourceNotFoundException
		if errors.As(err, &notFound) {
			return "", StatusSucceeded, "", nil // idempotent: already gone
		}
		return "", "", "", translate(err)
	}
	s := out.AccountAssignmentDeletionStatus
	return aws.ToString(s.RequestId), mapStatus(s.Status), aws.ToString(s.FailureReason), nil
}

// DescribeDeleteStatus implements API.
func (c *Client) DescribeDeleteStatus(ctx context.Context, instanceArn, requestID string) (Status, string, error) {
	out, err := c.sso.DescribeAccountAssignmentDeletionStatus(ctx, &ssoadmin.DescribeAccountAssignmentDeletionStatusInput{
		InstanceArn: aws.String(instanceArn), AccountAssignmentDeletionRequestId: aws.String(requestID),
	})
	if err != nil {
		var notFound *ssotypes.ResourceNotFoundException
		if errors.As(err, &notFound) {
			return StatusSucceeded, "", nil
		}
		return "", "", translate(err)
	}
	s := out.AccountAssignmentDeletionStatus
	return mapStatus(s.Status), aws.ToString(s.FailureReason), nil
}

// HasUserAssignment implements API — the live source of truth for revoke. Filters by USER
// principal so it can never see (or target) the standing GROUP assignment.
func (c *Client) HasUserAssignment(ctx context.Context, in AssignmentInput) (bool, error) {
	p := ssoadmin.NewListAccountAssignmentsPaginator(c.sso, &ssoadmin.ListAccountAssignmentsInput{
		InstanceArn: aws.String(in.InstanceArn), AccountId: aws.String(in.AccountID), PermissionSetArn: aws.String(in.PermissionSetArn),
	})
	for p.HasMorePages() {
		page, err := p.NextPage(ctx)
		if err != nil {
			return false, fmt.Errorf("list-account-assignments: %w", err)
		}
		for _, asg := range page.AccountAssignments {
			if asg.PrincipalType == ssotypes.PrincipalTypeUser && aws.ToString(asg.PrincipalId) == in.PrincipalID {
				return true, nil
			}
		}
	}
	return false, nil
}
