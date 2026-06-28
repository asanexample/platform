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

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Reach is the target a borrowed power applies to — exactly one of Team or Scope
// (enforced by a CEL rule on the spec). It mirrors the gitops/people grant reach.
type Reach struct {
	// team scopes the borrow to a single team (e.g. "alpha").
	// +optional
	Team string `json:"team,omitempty"`
	// scope is a platform-wide reach (e.g. "platform").
	// +optional
	Scope string `json:"scope,omitempty"`
}

// StepUp records the RESULT of a fresh passkey step-up (never the token itself). The
// imperative intake API populates it when it creates the Activation; it is optional in
// this increment because that API is not yet built (see the operator design doc).
type StepUp struct {
	// authTime is the OIDC auth_time of the fresh re-authentication.
	// +required
	AuthTime metav1.Time `json:"authTime"`
	// acr is the authentication-context-class of the step-up (the passkey assurance level).
	// +required
	ACR string `json:"acr"`
}

// ActivationSpec is the immutable request to borrow a power for a bounded window. A borrow
// is never edited — let it expire or revoke it and request a new one (enforced immutable).
type ActivationSpec struct {
	// principal is the borrower — the Person.Name / Identity Center username.
	// +required
	// +kubebuilder:validation:MinLength=1
	Principal string `json:"principal"`

	// role is the WorkforceRole being borrowed (e.g. "break-glass").
	// +required
	// +kubebuilder:validation:MinLength=1
	Role string `json:"role"`

	// reach is the target of the borrow — exactly one of team or scope.
	// +required
	// +kubebuilder:validation:XValidation:rule="has(self.team) != has(self.scope)",message="exactly one of reach.team or reach.scope must be set"
	Reach Reach `json:"reach"`

	// duration is the requested borrow window (e.g. "1h", "30m"). The intake API caps it to
	// the role's sessionDuration ceiling (cap enforcement is deferred to that API).
	// +required
	Duration metav1.Duration `json:"duration"`

	// reason is the required justification, recorded for audit.
	// +required
	// +kubebuilder:validation:MinLength=1
	Reason string `json:"reason"`

	// requestedBy is the authenticated requester (audit; usually equal to principal).
	// +required
	// +kubebuilder:validation:MinLength=1
	RequestedBy string `json:"requestedBy"`

	// stepUp is the recorded result of the fresh passkey step-up (the API populates it).
	// +optional
	StepUp *StepUp `json:"stepUp,omitempty"`
}

// ActivationPhase is the high-level lifecycle position, derived from the per-plane,
// per-account states (mint/revoke are asynchronous and serialized per permission set).
// +kubebuilder:validation:Enum=Pending;Provisioning;Active;Expiring;Expired;Revoked;Failed
type ActivationPhase string

const (
	// PhasePending is set on admission, before any minting begins.
	PhasePending ActivationPhase = "Pending"
	// PhaseProvisioning means at least one account assignment is still being created.
	PhaseProvisioning ActivationPhase = "Provisioning"
	// PhaseActive means every account assignment is granted and the window is open.
	PhaseActive ActivationPhase = "Active"
	// PhaseExpiring means the window closed (or the CR is deleting) and revoke is underway.
	PhaseExpiring ActivationPhase = "Expiring"
	// PhaseExpired means the window closed and every assignment is confirmed gone.
	PhaseExpired ActivationPhase = "Expired"
	// PhaseRevoked means a deletion-triggered teardown completed.
	PhaseRevoked ActivationPhase = "Revoked"
	// PhaseFailed means a terminal error occurred minting; needs operator attention.
	PhaseFailed ActivationPhase = "Failed"
)

// AssignmentState is the state of a single native grant (one account on one plane, or a
// plane aggregate). Mint and revoke are asynchronous in AWS Identity Center.
// +kubebuilder:validation:Enum=Pending;InProgress;Granted;Revoked;Failed
type AssignmentState string

const (
	// AssignmentPending means the create has not been issued yet.
	AssignmentPending AssignmentState = "Pending"
	// AssignmentInProgress means AWS is provisioning (the create/delete request is in flight).
	AssignmentInProgress AssignmentState = "InProgress"
	// AssignmentGranted means the assignment is confirmed live.
	AssignmentGranted AssignmentState = "Granted"
	// AssignmentRevoked means the assignment is confirmed deleted.
	AssignmentRevoked AssignmentState = "Revoked"
	// AssignmentFailed means AWS returned a terminal FAILED for the request.
	AssignmentFailed AssignmentState = "Failed"
)

// AccountAssignment tracks one permission-set assignment on one AWS account, including the
// in-flight AWS request id used to poll the asynchronous create/delete to completion.
type AccountAssignment struct {
	// accountID is the AWS account the assignment targets.
	// +required
	AccountID string `json:"accountID"`
	// requestID is the AWS account-assignment creation/deletion request id, polled to terminal.
	// +optional
	RequestID string `json:"requestID,omitempty"`
	// state is the current state of this account's assignment.
	// +required
	State AssignmentState `json:"state"`
	// message carries an AWS failure reason when state is Failed.
	// +optional
	Message string `json:"message,omitempty"`
}

// PlaneStatus is the aggregate state of one projection plane (AWS Identity Center now;
// Keycloak / cluster later) plus its per-account detail.
type PlaneStatus struct {
	// name identifies the plane (e.g. "aws-identity-center").
	// +required
	Name string `json:"name"`
	// state is the aggregate state across accounts (Granted only when all accounts are Granted).
	// +required
	State AssignmentState `json:"state"`
	// permissionSetArn is the resolved AWS permission set the assignments target.
	// +optional
	PermissionSetArn string `json:"permissionSetArn,omitempty"`
	// accounts is the per-account assignment detail.
	// +optional
	// +listType=map
	// +listMapKey=accountID
	Accounts []AccountAssignment `json:"accounts,omitempty"`
}

// ActivationStatus is the observed state. status.expiresAt is the authoritative clock for
// expiry; the set of live assignments is authoritative in AWS, not here (status is a hint).
type ActivationStatus struct {
	// phase is the high-level lifecycle position.
	// +optional
	Phase ActivationPhase `json:"phase,omitempty"`

	// grantedAt is set once, on the first confirmed-granted account, and never recomputed
	// (the crash-safe basis for expiresAt).
	// +optional
	GrantedAt *metav1.Time `json:"grantedAt,omitempty"`

	// expiresAt = grantedAt + duration. The authoritative expiry clock; a restart re-derives
	// all timers from it, so a grant cannot leak past its TTL.
	// +optional
	ExpiresAt *metav1.Time `json:"expiresAt,omitempty"`

	// planes is the per-plane projection state.
	// +optional
	// +listType=map
	// +listMapKey=name
	Planes []PlaneStatus `json:"planes,omitempty"`

	// conditions represent the current state of the Activation resource.
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster,shortName=act
// +kubebuilder:printcolumn:name="Principal",type=string,JSONPath=`.spec.principal`
// +kubebuilder:printcolumn:name="Role",type=string,JSONPath=`.spec.role`
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Expires",type=date,JSONPath=`.status.expiresAt`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// Activation is one borrowed-power window — the imperative cousin of a standing grant.
// Cluster-scoped; minted/expired/revoked by the activation controller (ADR-088).
type Activation struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec is the immutable borrow request.
	// +required
	// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="Activation spec is immutable; let it expire or revoke and request a new borrow"
	Spec ActivationSpec `json:"spec"`

	// status defines the observed state of Activation
	// +optional
	Status ActivationStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// ActivationList contains a list of Activation
type ActivationList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Activation `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Activation{}, &ActivationList{})
}
