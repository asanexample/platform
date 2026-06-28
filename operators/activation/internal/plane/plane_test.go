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

package plane

import (
	"errors"
	"fmt"
	"testing"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
)

func acc(state activationv1alpha1.AssignmentState) activationv1alpha1.AccountAssignment {
	return activationv1alpha1.AccountAssignment{State: state}
}

func TestAggregateState(t *testing.T) {
	cases := []struct {
		name string
		in   []activationv1alpha1.AccountAssignment
		want activationv1alpha1.AssignmentState
	}{
		{"empty", nil, activationv1alpha1.AssignmentPending},
		{"any failed wins", []activationv1alpha1.AccountAssignment{acc(activationv1alpha1.AssignmentGranted), acc(activationv1alpha1.AssignmentFailed)}, activationv1alpha1.AssignmentFailed},
		{"all granted", []activationv1alpha1.AccountAssignment{acc(activationv1alpha1.AssignmentGranted), acc(activationv1alpha1.AssignmentGranted)}, activationv1alpha1.AssignmentGranted},
		{"all revoked", []activationv1alpha1.AccountAssignment{acc(activationv1alpha1.AssignmentRevoked), acc(activationv1alpha1.AssignmentRevoked)}, activationv1alpha1.AssignmentRevoked},
		{"mixed in progress", []activationv1alpha1.AccountAssignment{acc(activationv1alpha1.AssignmentGranted), acc(activationv1alpha1.AssignmentInProgress)}, activationv1alpha1.AssignmentInProgress},
		{"partial granted partial pending", []activationv1alpha1.AccountAssignment{acc(activationv1alpha1.AssignmentGranted), acc(activationv1alpha1.AssignmentPending)}, activationv1alpha1.AssignmentInProgress},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := AggregateState(c.in); got != c.want {
				t.Errorf("AggregateState = %v, want %v", got, c.want)
			}
		})
	}
}

func TestTerminalError(t *testing.T) {
	base := errors.New("boom")
	term := Terminalf("wrapping %w", base)
	if !IsTerminal(term) {
		t.Error("Terminalf should be terminal")
	}
	if !IsTerminal(fmt.Errorf("outer: %w", term)) {
		t.Error("a wrapped TerminalError should still be terminal")
	}
	if IsTerminal(base) {
		t.Error("a plain error is not terminal")
	}
	if !errors.Is(term, base) {
		t.Error("Terminalf should preserve the wrapped error chain")
	}
}
