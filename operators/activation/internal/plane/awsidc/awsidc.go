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

// Package awsidc is the AWS Identity Center projection plane. It mints/revokes a temporary
// USER account-assignment to a role's permission set across the accounts that permission set
// is provisioned to. AWS provisions these assignments ASYNCHRONOUSLY and serializes them per
// permission set (concurrent ops on one permission set race — the #888 incident), so the
// adapter drives a per-account state machine that issues one create/delete at a time, polls
// it to terminal, and only then advances — across as many reconciles as it takes.
package awsidc

import (
	"context"
	"errors"
	"fmt"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
	"github.com/asanexample/platform/operators/activation/internal/plane"
)

// PlaneName is the stable identifier recorded in PlaneStatus.Name.
const PlaneName = "aws-identity-center"

// Status is the lifecycle of an async account-assignment create/delete request.
type Status string

const (
	StatusInProgress Status = "IN_PROGRESS"
	StatusSucceeded  Status = "SUCCEEDED"
	StatusFailed     Status = "FAILED"
)

// Sentinel errors let the adapter stay AWS-agnostic: the API implementation translates AWS
// faults into these so the adapter (and its tests) don't import smithy error types.
var (
	// ErrConflict means another operation on this permission set is in flight — the
	// serialization signal. Retryable: the controller requeues and tries again.
	ErrConflict = errors.New("identity center: operation conflicts with an in-flight op on this permission set")
	// ErrThrottled means AWS throttled the request. Retryable.
	ErrThrottled = errors.New("identity center: throttled")
)

// AssignmentInput identifies one permission-set assignment on one account for one principal.
type AssignmentInput struct {
	InstanceArn      string
	AccountID        string
	PermissionSetArn string
	PrincipalID      string // Identity Store user id (USER principal)
}

// API is the subset of the AWS SSO Admin + Identity Store API the adapter needs. Methods
// translate AWS faults into the sentinels above (ErrConflict/ErrThrottled) and treat a delete
// of an already-absent assignment as success, so the adapter logic is cloud-fault-agnostic.
type API interface {
	// Instance resolves the single Identity Center instance ARN + identity store id.
	Instance(ctx context.Context) (instanceArn, identityStoreID string, err error)
	// UserID resolves an Identity Store user id by username.
	UserID(ctx context.Context, identityStoreID, username string) (string, error)
	// PermissionSetARN resolves a permission set ARN by name (terminal error if absent).
	PermissionSetARN(ctx context.Context, instanceArn, name string) (string, error)
	// ProvisionedAccounts lists the accounts a permission set is provisioned to (the footprint).
	ProvisionedAccounts(ctx context.Context, instanceArn, psArn string) ([]string, error)
	// CreateAssignment issues an async create; returns the request id and its initial status.
	CreateAssignment(ctx context.Context, in AssignmentInput) (requestID string, status Status, failureReason string, err error)
	// DescribeCreateStatus polls a create request to terminal.
	DescribeCreateStatus(ctx context.Context, instanceArn, requestID string) (status Status, failureReason string, err error)
	// DeleteAssignment issues an async delete (ResourceNotFound is mapped to SUCCEEDED).
	DeleteAssignment(ctx context.Context, in AssignmentInput) (requestID string, status Status, failureReason string, err error)
	// DescribeDeleteStatus polls a delete request to terminal.
	DescribeDeleteStatus(ctx context.Context, instanceArn, requestID string) (status Status, failureReason string, err error)
	// HasUserAssignment reports whether a live USER assignment exists — revoke's source of truth.
	HasUserAssignment(ctx context.Context, in AssignmentInput) (bool, error)
}

// PermissionSetResolver maps a WorkforceRole name to its AWS permission set name, from the
// in-cluster role catalog. A missing role / unresolvable name returns an error (the adapter
// fails closed). Decouples the adapter from the catalog implementation.
type PermissionSetResolver func(ctx context.Context, role string) (string, error)

// Adapter implements plane.Plane for AWS Identity Center.
type Adapter struct {
	api API
	// resolvePS resolves a role to its permission-set name (the role catalog, replacing the
	// former bootstrap --role-permission-sets flag).
	resolvePS PermissionSetResolver
}

// New builds the adapter from an API implementation and the role→permission-set resolver.
func New(api API, resolvePS PermissionSetResolver) *Adapter {
	return &Adapter{api: api, resolvePS: resolvePS}
}

// Name implements plane.Plane.
func (a *Adapter) Name() string { return PlaneName }

// resolve fills in the plane's permission set ARN and the per-account assignment list (once),
// and returns the instance ARN + principal id needed for the per-account operations.
func (a *Adapter) resolve(ctx context.Context, act *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) (instanceArn, principalID string, err error) {
	psName, err := a.resolvePS(ctx, act.Spec.Role)
	if err != nil {
		return "", "", err
	}
	if psName == "" {
		return "", "", plane.Terminalf("role %q has no AWS Identity Center permission set", act.Spec.Role)
	}
	instanceArn, identityStoreID, err := a.api.Instance(ctx)
	if err != nil {
		return "", "", err
	}
	principalID, err = a.api.UserID(ctx, identityStoreID, act.Spec.Principal)
	if err != nil {
		return "", "", err
	}
	if ps.PermissionSetArn == "" {
		psArn, err := a.api.PermissionSetARN(ctx, instanceArn, psName)
		if err != nil {
			return "", "", err
		}
		ps.PermissionSetArn = psArn
	}
	if len(ps.Accounts) == 0 {
		accounts, err := a.api.ProvisionedAccounts(ctx, instanceArn, ps.PermissionSetArn)
		if err != nil {
			return "", "", err
		}
		if len(accounts) == 0 {
			return "", "", plane.Terminalf("permission set %q is provisioned to no accounts", psName)
		}
		ps.Accounts = make([]activationv1alpha1.AccountAssignment, 0, len(accounts))
		for _, acct := range accounts {
			ps.Accounts = append(ps.Accounts, activationv1alpha1.AccountAssignment{
				AccountID: acct, State: activationv1alpha1.AssignmentPending,
			})
		}
	}
	return instanceArn, principalID, nil
}

// Mint advances minting by one step, serially across accounts. Implements plane.Plane.
func (a *Adapter) Mint(ctx context.Context, act *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) (bool, error) {
	instanceArn, principalID, err := a.resolve(ctx, act, ps)
	if err != nil {
		return false, err
	}
	defer func() { ps.State = plane.AggregateState(ps.Accounts) }()

	for i := range ps.Accounts {
		acct := &ps.Accounts[i]
		in := AssignmentInput{InstanceArn: instanceArn, AccountID: acct.AccountID, PermissionSetArn: ps.PermissionSetArn, PrincipalID: principalID}
		switch acct.State {
		case activationv1alpha1.AssignmentGranted:
			continue // done; move to the next account
		case activationv1alpha1.AssignmentPending:
			reqID, status, failure, err := a.api.CreateAssignment(ctx, in)
			if err != nil {
				return false, err // retryable (incl. ErrConflict/ErrThrottled) → requeue
			}
			acct.RequestID = reqID
			a.applyStatus(acct, status, failure)
		case activationv1alpha1.AssignmentInProgress:
			status, failure, err := a.api.DescribeCreateStatus(ctx, instanceArn, acct.RequestID)
			if err != nil {
				return false, err
			}
			a.applyStatus(acct, status, failure)
		}
		// Serialize per permission set: only one account is worked at a time. Whatever this
		// account's resulting state, return and requeue unless it is now Granted.
		if acct.State == activationv1alpha1.AssignmentFailed {
			return false, plane.Terminalf("account %s assignment failed: %s", acct.AccountID, acct.Message)
		}
		if acct.State != activationv1alpha1.AssignmentGranted {
			return false, nil // still provisioning → requeue
		}
	}
	return true, nil // every account Granted
}

// Revoke advances teardown by one step, reading AWS as the source of truth. Implements plane.Plane.
func (a *Adapter) Revoke(ctx context.Context, act *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) (bool, error) {
	instanceArn, identityStoreID, err := a.api.Instance(ctx)
	if err != nil {
		return false, err
	}
	principalID, err := a.api.UserID(ctx, identityStoreID, act.Spec.Principal)
	if err != nil {
		return false, err
	}
	// Prefer the permission-set ARN recorded at mint (so revoke survives the role leaving the
	// catalog); only fall back to the catalog when nothing was recorded.
	psArn := ps.PermissionSetArn
	if psArn == "" {
		psName, err := a.resolvePS(ctx, act.Spec.Role)
		if err != nil || psName == "" {
			// Nothing recorded and the role no longer resolves → nothing this adapter can target.
			return true, nil
		}
		if psArn, err = a.api.PermissionSetARN(ctx, instanceArn, psName); err != nil {
			return false, err
		}
		ps.PermissionSetArn = psArn
	}
	// Determine the account set ONCE and record the full footprint in status, so a lost status
	// write (empty ps.Accounts) cannot strand an assignment and the set never shrinks mid-teardown.
	if len(ps.Accounts) == 0 {
		accounts, err := a.api.ProvisionedAccounts(ctx, instanceArn, psArn)
		if err != nil {
			return false, err
		}
		for _, acct := range accounts {
			ps.Accounts = append(ps.Accounts, activationv1alpha1.AccountAssignment{AccountID: acct, State: activationv1alpha1.AssignmentInProgress})
		}
	}
	defer func() { ps.State = plane.AggregateState(ps.Accounts) }()

	for i := range ps.Accounts {
		acctID := ps.Accounts[i].AccountID
		in := AssignmentInput{InstanceArn: instanceArn, AccountID: acctID, PermissionSetArn: psArn, PrincipalID: principalID}
		live, err := a.api.HasUserAssignment(ctx, in)
		if err != nil {
			return false, err
		}
		if !live {
			setAccountState(ps, acctID, activationv1alpha1.AssignmentRevoked, "")
			continue
		}
		// Live assignment remains → issue (or re-issue, idempotent) the async delete and requeue.
		if _, status, failure, err := a.api.DeleteAssignment(ctx, in); err != nil {
			return false, err
		} else if status == StatusFailed {
			return false, fmt.Errorf("delete of %s on %s failed: %s", psArn, acctID, failure)
		}
		setAccountState(ps, acctID, activationv1alpha1.AssignmentInProgress, "")
		return false, nil // serialize per permission set; requeue
	}
	return true, nil // no account has a live assignment
}

func (a *Adapter) applyStatus(acct *activationv1alpha1.AccountAssignment, status Status, failure string) {
	switch status {
	case StatusSucceeded:
		acct.State = activationv1alpha1.AssignmentGranted
		acct.Message = ""
	case StatusFailed:
		acct.State = activationv1alpha1.AssignmentFailed
		acct.Message = failure
	default:
		acct.State = activationv1alpha1.AssignmentInProgress
	}
}

func setAccountState(ps *activationv1alpha1.PlaneStatus, accountID string, state activationv1alpha1.AssignmentState, msg string) {
	for i := range ps.Accounts {
		if ps.Accounts[i].AccountID == accountID {
			ps.Accounts[i].State = state
			ps.Accounts[i].Message = msg
			return
		}
	}
	ps.Accounts = append(ps.Accounts, activationv1alpha1.AccountAssignment{AccountID: accountID, State: state, Message: msg})
}
