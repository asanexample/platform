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

// Package plane defines the projection-plane port the activation controller reconciles
// through. A plane (AWS Identity Center now; Keycloak / cluster later) mints and revokes a
// borrowed power on one target system. Because the native operations are ASYNCHRONOUS (AWS
// Identity Center provisions account-assignments serially per permission set and reports
// IN_PROGRESS → SUCCEEDED/FAILED), the contract is reconcile-shaped: each call advances the
// plane's per-account state machine by one step and reports whether more work remains. The
// reconciler keeps calling until Mint/Revoke report done, requeuing in between.
package plane

import (
	"context"
	"errors"
	"fmt"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
)

// Plane is one projection target. Implementations MUST be idempotent: a step may be retried
// any number of times (a status write can conflict and re-drive the same reconcile), and the
// controller may restart mid-operation, so re-issuing a mint or revoke must never corrupt
// state. Implementations MUST treat the native system — not the passed-in status — as the
// source of truth for what is actually live, so a lost status write cannot leak a grant.
type Plane interface {
	// Name identifies the plane, e.g. "aws-identity-center".
	Name() string

	// Mint advances minting by one step, mutating ps (accounts, requestIDs, states) in place.
	// It returns done=true only when every account is confirmed Granted. While AWS is still
	// provisioning (or an account is Pending), it returns done=false so the controller requeues.
	// A Terminal error means the borrow cannot be granted (set phase Failed); any other error
	// is retryable (the controller requeues with backoff).
	Mint(ctx context.Context, act *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) (done bool, err error)

	// Revoke advances teardown by one step. It is complete (done=true) only when the native
	// system reports zero live assignments for this principal — verified against the cloud, not
	// status. Idempotent: revoking an already-gone assignment is success.
	Revoke(ctx context.Context, act *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) (done bool, err error)
}

// TerminalError marks a failure that cannot be recovered by retrying (e.g. AWS returned a
// terminal FAILED, or the role/permission set does not resolve). The controller surfaces it
// as phase Failed rather than requeuing forever. Everything else is treated as retryable.
type TerminalError struct{ Err error }

func (e *TerminalError) Error() string { return e.Err.Error() }
func (e *TerminalError) Unwrap() error { return e.Err }

// Terminalf builds a TerminalError with a formatted message.
func Terminalf(format string, a ...any) *TerminalError {
	return &TerminalError{Err: fmt.Errorf(format, a...)}
}

// IsTerminal reports whether err (or anything it wraps) is a TerminalError.
func IsTerminal(err error) bool {
	var t *TerminalError
	return errors.As(err, &t)
}

// AggregateState folds per-account states into a single plane state: Failed if any failed,
// then InProgress if any is still provisioning/pending, then Granted only if all granted,
// then Revoked if all revoked, else InProgress. Used to keep PlaneStatus.State in sync.
func AggregateState(accounts []activationv1alpha1.AccountAssignment) activationv1alpha1.AssignmentState {
	if len(accounts) == 0 {
		return activationv1alpha1.AssignmentPending
	}
	var granted, revoked int
	for _, a := range accounts {
		switch a.State {
		case activationv1alpha1.AssignmentFailed:
			return activationv1alpha1.AssignmentFailed
		case activationv1alpha1.AssignmentGranted:
			granted++
		case activationv1alpha1.AssignmentRevoked:
			revoked++
		}
	}
	switch {
	case granted == len(accounts):
		return activationv1alpha1.AssignmentGranted
	case revoked == len(accounts):
		return activationv1alpha1.AssignmentRevoked
	default:
		return activationv1alpha1.AssignmentInProgress
	}
}
