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

package controller

import (
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
)

// planeStatus returns a mutable copy of the named plane's status (or a fresh one). The
// caller mutates it via the Plane and writes it back with setPlaneStatus. The Accounts
// slice is copied so mutation can't alias the live object before the status write.
func planeStatus(act *activationv1alpha1.Activation, name string) *activationv1alpha1.PlaneStatus {
	for i := range act.Status.Planes {
		if act.Status.Planes[i].Name == name {
			ps := act.Status.Planes[i]
			ps.Accounts = append([]activationv1alpha1.AccountAssignment(nil), ps.Accounts...)
			return &ps
		}
	}
	return &activationv1alpha1.PlaneStatus{Name: name, State: activationv1alpha1.AssignmentPending}
}

// setPlaneStatus writes ps back into the Activation's plane list.
func setPlaneStatus(act *activationv1alpha1.Activation, ps *activationv1alpha1.PlaneStatus) {
	for i := range act.Status.Planes {
		if act.Status.Planes[i].Name == ps.Name {
			act.Status.Planes[i] = *ps
			return
		}
	}
	act.Status.Planes = append(act.Status.Planes, *ps)
}

// anyGranted reports whether at least one account assignment is confirmed granted (the
// trigger for stamping the crash-safe grantedAt clock).
func anyGranted(ps *activationv1alpha1.PlaneStatus) bool {
	for _, a := range ps.Accounts {
		if a.State == activationv1alpha1.AssignmentGranted {
			return true
		}
	}
	return false
}

// attrs is the common metric/span attribute set for an activation operation.
func attrs(act *activationv1alpha1.Activation, planeName string) metric.MeasurementOption {
	return metric.WithAttributes(
		attribute.String("role", act.Spec.Role),
		attribute.String("plane", planeName),
	)
}
