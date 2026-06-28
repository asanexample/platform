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

// Package fake provides a controllable, async-modeling implementation of plane.Plane for
// controller tests. It deliberately mimics the real AWS plane's shape: minting is multi-step
// (StepsToGrant reconciles per account, serialized), can fail terminally on a chosen account,
// and revoke can be made to fail (to exercise leak-safety). A fake that granted synchronously
// would hide exactly the bugs these tests must catch.
package fake

import (
	"context"
	"sync"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
	"github.com/asanexample/platform/operators/activation/internal/plane"
)

// Plane is a fake projection plane with knobs for tests.
type Plane struct {
	// Accounts is the per-account footprint to mint across.
	Accounts []string
	// StepsToGrant is how many Mint calls each account needs before it is Granted (>=1) —
	// models AWS's asynchronous IN_PROGRESS → SUCCEEDED.
	StepsToGrant int
	// FailOn, if set, makes that account fail terminally during mint.
	FailOn string
	// RevokeError, if set, is returned by Revoke (to test leak-safe teardown).
	RevokeError error

	mu       sync.Mutex
	progress map[string]int  // account -> mint steps taken
	live     map[string]bool // account -> has a live assignment
}

// NewPlane builds a fake plane over the given accounts, granting in one step each.
func NewPlane(accounts ...string) *Plane {
	return &Plane{Accounts: accounts, StepsToGrant: 1}
}

// Name implements plane.Plane.
func (p *Plane) Name() string { return "fake" }

func (p *Plane) ensure(ps *activationv1alpha1.PlaneStatus) {
	if p.progress == nil {
		p.progress = map[string]int{}
	}
	if p.live == nil {
		p.live = map[string]bool{}
	}
	if len(ps.Accounts) == 0 {
		for _, a := range p.Accounts {
			ps.Accounts = append(ps.Accounts, activationv1alpha1.AccountAssignment{AccountID: a, State: activationv1alpha1.AssignmentPending})
		}
	}
}

// Mint advances minting one step, serialized across accounts. Implements plane.Plane.
func (p *Plane) Mint(_ context.Context, _ *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.ensure(ps)
	defer func() { ps.State = plane.AggregateState(ps.Accounts) }()

	for i := range ps.Accounts {
		acct := &ps.Accounts[i]
		if acct.State == activationv1alpha1.AssignmentGranted {
			continue
		}
		if acct.AccountID == p.FailOn {
			acct.State = activationv1alpha1.AssignmentFailed
			acct.Message = "fake terminal failure"
			return false, plane.Terminalf("account %s failed", acct.AccountID)
		}
		p.progress[acct.AccountID]++
		if p.progress[acct.AccountID] >= p.StepsToGrant {
			acct.State = activationv1alpha1.AssignmentGranted
			p.live[acct.AccountID] = true
		} else {
			acct.State = activationv1alpha1.AssignmentInProgress
			return false, nil // still provisioning this account → requeue
		}
		if acct.State != activationv1alpha1.AssignmentGranted {
			return false, nil
		}
	}
	return true, nil
}

// Revoke advances teardown one step. Implements plane.Plane.
func (p *Plane) Revoke(_ context.Context, _ *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.RevokeError != nil {
		return false, p.RevokeError
	}
	p.ensure(ps)
	defer func() { ps.State = plane.AggregateState(ps.Accounts) }()

	for i := range ps.Accounts {
		acct := &ps.Accounts[i]
		if !p.live[acct.AccountID] {
			acct.State = activationv1alpha1.AssignmentRevoked
			continue
		}
		p.live[acct.AccountID] = false
		acct.State = activationv1alpha1.AssignmentRevoked
		return false, nil // serialize; requeue
	}
	return true, nil
}

// LiveCount returns how many accounts still have a live assignment (test assertion helper).
func (p *Plane) LiveCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	n := 0
	for _, v := range p.live {
		if v {
			n++
		}
	}
	return n
}
