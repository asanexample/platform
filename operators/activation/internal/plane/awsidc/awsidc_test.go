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
	"testing"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
	"github.com/asanexample/platform/operators/activation/internal/plane"
)

// fakeAPI models AWS Identity Center's ASYNC, per-permission-set-serialized behavior so the
// adapter's state machine is tested against reality, not a synchronous stub.
type fakeAPI struct {
	accounts       []string
	pollsToSucceed int             // DescribeCreateStatus returns IN_PROGRESS this many times first
	failAccount    string          // this account's create resolves to FAILED
	conflictOnce   map[string]bool // create returns ErrConflict once per listed account
	live           map[string]bool // account -> live USER assignment
	createPolls    map[string]int  // account -> polls remaining before SUCCEEDED
	reqToAccount   map[string]string
}

func newFakeAPI(accounts ...string) *fakeAPI {
	return &fakeAPI{
		accounts:     accounts,
		live:         map[string]bool{},
		createPolls:  map[string]int{},
		reqToAccount: map[string]string{},
		conflictOnce: map[string]bool{},
	}
}

func (f *fakeAPI) Instance(context.Context) (string, string, error) {
	return "arn:inst", "d-store", nil
}
func (f *fakeAPI) UserID(context.Context, string, string) (string, error) {
	return "user-123", nil
}
func (f *fakeAPI) PermissionSetARN(_ context.Context, _, name string) (string, error) {
	if name == "" {
		return "", plane.Terminalf("no permission set")
	}
	return "arn:ps/" + name, nil
}
func (f *fakeAPI) ProvisionedAccounts(context.Context, string, string) ([]string, error) {
	return append([]string(nil), f.accounts...), nil
}
func (f *fakeAPI) CreateAssignment(_ context.Context, in AssignmentInput) (string, Status, string, error) {
	if f.conflictOnce[in.AccountID] {
		f.conflictOnce[in.AccountID] = false
		return "", "", "", ErrConflict
	}
	req := "req-" + in.AccountID
	f.reqToAccount[req] = in.AccountID
	if f.pollsToSucceed == 0 {
		if in.AccountID == f.failAccount {
			return req, StatusFailed, "fake failure", nil
		}
		f.live[in.AccountID] = true
		return req, StatusSucceeded, "", nil
	}
	f.createPolls[in.AccountID] = f.pollsToSucceed
	return req, StatusInProgress, "", nil
}
func (f *fakeAPI) DescribeCreateStatus(_ context.Context, _, requestID string) (Status, string, error) {
	acct := f.reqToAccount[requestID]
	if acct == f.failAccount {
		return StatusFailed, "fake failure", nil
	}
	f.createPolls[acct]--
	if f.createPolls[acct] <= 0 {
		f.live[acct] = true
		return StatusSucceeded, "", nil
	}
	return StatusInProgress, "", nil
}
func (f *fakeAPI) DeleteAssignment(_ context.Context, in AssignmentInput) (string, Status, string, error) {
	if !f.live[in.AccountID] {
		return "", StatusSucceeded, "", nil // mimic the client's ResourceNotFound → success mapping
	}
	f.live[in.AccountID] = false
	return "req-del-" + in.AccountID, StatusSucceeded, "", nil
}
func (f *fakeAPI) DescribeDeleteStatus(context.Context, string, string) (Status, string, error) {
	return StatusSucceeded, "", nil
}
func (f *fakeAPI) HasUserAssignment(_ context.Context, in AssignmentInput) (bool, error) {
	return f.live[in.AccountID], nil
}

const roleBG = "break-glass"

func bgActivation() *activationv1alpha1.Activation {
	return &activationv1alpha1.Activation{Spec: activationv1alpha1.ActivationSpec{Principal: "josh", Role: roleBG}}
}

// driveMint calls Mint until done or error, bounded so a stuck machine fails loudly.
func driveMint(t *testing.T, a *Adapter, act *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) error {
	t.Helper()
	for range 50 {
		done, err := a.Mint(context.Background(), act, ps)
		if err != nil {
			return err
		}
		if done {
			return nil
		}
	}
	t.Fatalf("Mint did not converge in 50 calls")
	return nil
}

func TestMintAsyncSerialHappyPath(t *testing.T) {
	api := newFakeAPI("111", "222", "333")
	api.pollsToSucceed = 2 // each account needs two polls → exercises the async loop
	a := New(api, map[string]string{roleBG: "AdministratorAccess"})
	ps := &activationv1alpha1.PlaneStatus{Name: PlaneName}

	err := driveMint(t, a, bgActivation(), ps)
	if err != nil {
		t.Fatalf("Mint: %v", err)
	}
	if ps.State != activationv1alpha1.AssignmentGranted {
		t.Errorf("plane state = %v, want Granted", ps.State)
	}
	if len(ps.Accounts) != 3 {
		t.Fatalf("want 3 accounts, got %d", len(ps.Accounts))
	}
	for _, acct := range ps.Accounts {
		if acct.State != activationv1alpha1.AssignmentGranted {
			t.Errorf("account %s = %v, want Granted", acct.AccountID, acct.State)
		}
		if !api.live[acct.AccountID] {
			t.Errorf("account %s should be live in AWS", acct.AccountID)
		}
	}
}

func TestMintConflictIsRetryableNotTerminal(t *testing.T) {
	api := newFakeAPI("111")
	api.conflictOnce["111"] = true // first create conflicts (serialization signal)
	a := New(api, map[string]string{roleBG: "AdministratorAccess"})
	ps := &activationv1alpha1.PlaneStatus{Name: PlaneName}
	act := bgActivation()

	// First call hits the conflict.
	done, err := a.Mint(context.Background(), act, ps)
	if err == nil {
		t.Fatal("expected a conflict error on the first mint")
	}
	if plane.IsTerminal(err) {
		t.Error("a conflict must be retryable, not terminal")
	}
	if !errors.Is(err, ErrConflict) {
		t.Errorf("want ErrConflict, got %v", err)
	}
	if done {
		t.Error("done should be false on conflict")
	}
	// Retrying converges.
	if err := driveMint(t, a, act, ps); err != nil {
		t.Fatalf("retry after conflict: %v", err)
	}
	if ps.State != activationv1alpha1.AssignmentGranted {
		t.Errorf("plane state = %v, want Granted after retry", ps.State)
	}
}

func TestMintTerminalFailure(t *testing.T) {
	api := newFakeAPI("111", "222")
	api.failAccount = "222"
	a := New(api, map[string]string{roleBG: "AdministratorAccess"})
	ps := &activationv1alpha1.PlaneStatus{Name: PlaneName}

	err := driveMint(t, a, bgActivation(), ps)
	if err == nil || !plane.IsTerminal(err) {
		t.Fatalf("want terminal error, got %v", err)
	}
}

func TestMintUnknownRoleIsTerminal(t *testing.T) {
	a := New(newFakeAPI("111"), map[string]string{}) // no mapping for break-glass
	ps := &activationv1alpha1.PlaneStatus{Name: PlaneName}
	_, err := a.Mint(context.Background(), bgActivation(), ps)
	if err == nil || !plane.IsTerminal(err) {
		t.Fatalf("unmapped role should be terminal, got %v", err)
	}
}

func TestRevokeDrainsLiveAssignments(t *testing.T) {
	api := newFakeAPI("111", "222")
	a := New(api, map[string]string{roleBG: "AdministratorAccess"})
	ps := &activationv1alpha1.PlaneStatus{Name: PlaneName}
	act := bgActivation()
	if err := driveMint(t, a, act, ps); err != nil {
		t.Fatalf("mint: %v", err)
	}

	for range 50 {
		done, err := a.Revoke(context.Background(), act, ps)
		if err != nil {
			t.Fatalf("revoke: %v", err)
		}
		if done {
			break
		}
	}
	for acctID, live := range api.live {
		if live {
			t.Errorf("account %s still live after revoke", acctID)
		}
	}
	if ps.State != activationv1alpha1.AssignmentRevoked {
		t.Errorf("plane state = %v, want Revoked", ps.State)
	}
}

func TestRevokeIsSourceOfTruthWhenStatusLost(t *testing.T) {
	// Simulate a lost status write: the assignment is live in AWS but ps has no accounts.
	api := newFakeAPI("111", "222")
	api.live["111"] = true
	api.live["222"] = true
	a := New(api, map[string]string{roleBG: "AdministratorAccess"})
	ps := &activationv1alpha1.PlaneStatus{Name: PlaneName} // empty — no recorded accounts

	for range 50 {
		done, err := a.Revoke(context.Background(), bgActivation(), ps)
		if err != nil {
			t.Fatalf("revoke: %v", err)
		}
		if done {
			break
		}
	}
	if api.live["111"] || api.live["222"] {
		t.Error("revoke must drain the live footprint even with no status — else a grant leaks")
	}
}

func TestRevokeNoopWhenNothingLive(t *testing.T) {
	api := newFakeAPI("111")
	a := New(api, map[string]string{roleBG: "AdministratorAccess"})
	ps := &activationv1alpha1.PlaneStatus{Name: PlaneName}
	done, err := a.Revoke(context.Background(), bgActivation(), ps)
	if err != nil {
		t.Fatalf("revoke: %v", err)
	}
	if !done {
		t.Error("revoke with nothing live should be done immediately")
	}
}
