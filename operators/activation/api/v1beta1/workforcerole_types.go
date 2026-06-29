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

// WorkforceRole is a READ-ONLY registry type — the role catalog (identity strategy §2.2 /
// #887): the reach×power grid that says what each workforce role IS. It is git-sourced
// (gitops/roles) and projected onto the hub as a read-only mirror; the activation operator
// reads spec.identityCenter.sessionDuration (the borrow CAP) and spec.identityCenter.permissionSet
// (the AWS target). The operator does NOT own or write WorkforceRole — it only consumes it.
// (The CRD currently ships with the operator's hub delivery; it relocates to a dedicated hub
// governance-registry alongside Team/People later.)

// IdentityCenterProjection is the AWS Identity Center mapping the operator consumes.
type IdentityCenterProjection struct {
	// +optional
	PerTeam bool `json:"perTeam,omitempty"`
	// permissionSet is the AWS permission set name (e.g. AdministratorAccess) — the activation target.
	// +optional
	PermissionSet string `json:"permissionSet,omitempty"`
	// sessionDuration is an ISO-8601 duration (e.g. PT1H) — the borrow-duration ceiling (the cap).
	// +optional
	SessionDuration string `json:"sessionDuration,omitempty"`
	// +optional
	ManagedPolicies []string `json:"managedPolicies,omitempty"`
	// +optional
	Note string `json:"note,omitempty"`
}

// KeycloakProjection is the Keycloak (app-access) mapping (not consumed by the operator yet).
type KeycloakProjection struct {
	// +optional
	RealmRole string `json:"realmRole,omitempty"`
	// +optional
	PerTeamGroup bool `json:"perTeamGroup,omitempty"`
	// +optional
	Group string `json:"group,omitempty"`
}

// WorkforceRoleSpec is the role catalog entry (mirrors gitops/roles/*.yaml).
type WorkforceRoleSpec struct {
	// reach is the breadth a grant of this role targets.
	// +kubebuilder:validation:Enum=team;platform;any
	// +required
	Reach string `json:"reach"`
	// power is what the role can do, weakest→strongest.
	// +kubebuilder:validation:Enum=look;operate;change;manage-access
	// +required
	Power string `json:"power"`
	// mode: standing = held all the time; on-demand = borrowed via activation (ADR-088).
	// +kubebuilder:validation:Enum=standing;on-demand
	// +required
	Mode string `json:"mode"`
	// riskTier is the insider-risk weight — drives step-up strength + review bar.
	// +kubebuilder:validation:Enum=standard;elevated;apex
	// +required
	RiskTier string `json:"riskTier"`
	// +optional
	Description string `json:"description,omitempty"`
	// identityCenter is the AWS projection — the permission set + the session-duration cap.
	// +optional
	IdentityCenter *IdentityCenterProjection `json:"identityCenter,omitempty"`
	// +optional
	Keycloak *KeycloakProjection `json:"keycloak,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:scope=Cluster,shortName=wfrole
// +kubebuilder:printcolumn:name="Power",type=string,JSONPath=`.spec.power`
// +kubebuilder:printcolumn:name="Mode",type=string,JSONPath=`.spec.mode`
// +kubebuilder:printcolumn:name="Risk",type=string,JSONPath=`.spec.riskTier`
// +kubebuilder:printcolumn:name="Cap",type=string,JSONPath=`.spec.identityCenter.sessionDuration`

// WorkforceRole is the Schema for the workforceroles API (read-only registry projection).
type WorkforceRole struct {
	metav1.TypeMeta `json:",inline"`
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// +required
	Spec WorkforceRoleSpec `json:"spec"`
}

// +kubebuilder:object:root=true

// WorkforceRoleList contains a list of WorkforceRole.
type WorkforceRoleList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []WorkforceRole `json:"items"`
}

func init() {
	SchemeBuilder.Register(&WorkforceRole{}, &WorkforceRoleList{})
}
