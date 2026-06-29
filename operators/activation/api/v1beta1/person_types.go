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

package v1beta1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Person is a READ-ONLY registry type — the workforce roster (gitops/people; ADR-084/088).
// It holds ACCESS FACTS ONLY (no PII): a Keycloak anchor + the role×reach grants a person
// holds. The activation operator reads it to re-check eligibility ("may this principal borrow
// this role?") at mint — defense-in-depth alongside create-RBAC (and the future intake API).
// The operator does NOT own or write Person; like WorkforceRole, it is git-sourced and projected.

// PersonHandles are the (declared, non-PII) external handles for a person.
type PersonHandles struct {
	// +optional
	GitHub string `json:"github,omitempty"`
}

// PersonGrant is one (role × reach) entry on a Person — reach is exactly one of team or scope.
type PersonGrant struct {
	// role is the WorkforceRole this person may hold/borrow.
	// +required
	Role string `json:"role"`
	// team scopes the grant to a single team (mutually exclusive with scope).
	// +optional
	Team string `json:"team,omitempty"`
	// scope is a platform-wide reach (mutually exclusive with team).
	// +optional
	Scope string `json:"scope,omitempty"`
	// activation marks a grant as borrowed-not-held; "on-demand" means eligible-to-activate.
	// +optional
	Activation string `json:"activation,omitempty"`
}

// PersonSpec is the roster entry (mirrors gitops/people/*.yaml).
type PersonSpec struct {
	// person is the Keycloak anchor (the identity this roster entry maps to).
	// +required
	Person string `json:"person"`
	// handles are declared external handles (no PII).
	// +optional
	Handles *PersonHandles `json:"handles,omitempty"`
	// grants are the role×reach entries this person holds.
	// +optional
	Grants []PersonGrant `json:"grants,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:scope=Cluster
// +kubebuilder:printcolumn:name="Anchor",type=string,JSONPath=`.spec.person`

// Person is the Schema for the people API (read-only registry projection).
type Person struct {
	metav1.TypeMeta `json:",inline"`
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// +required
	Spec PersonSpec `json:"spec"`
}

// +kubebuilder:object:root=true

// PersonList contains a list of Person.
type PersonList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Person `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Person{}, &PersonList{})
}
