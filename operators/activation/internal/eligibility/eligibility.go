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

// Package eligibility re-checks "may this principal borrow this role at this reach?" against the
// in-cluster registries (Person × WorkforceRole CRs), at activation time. It is defense-in-depth:
// create-RBAC bounds WHO can request, the future intake API will check eligibility up front, and
// this is the operator's own backstop. It converts the CRs to the shared pkg/access types and
// reuses access.Eligible — the SAME decision the platctl break-glass CLI makes — so the two never
// diverge.
package eligibility

import (
	"context"

	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/asanexample/platform/operators/activation/api/v1beta1"
	"github.com/asanexample/platform/pkg/access"
)

// Checker decides whether a principal may borrow a role at a reach (exactly one of team/scope).
type Checker interface {
	Eligible(ctx context.Context, principal, role, team, scope string) (access.Decision, error)
}

// clientChecker reads the Person + WorkforceRole registries through a (cached) reader.
type clientChecker struct{ c client.Reader }

// New builds a Checker backed by the given reader (the manager's cached client in prod).
func New(c client.Reader) Checker { return &clientChecker{c: c} }

// Eligible implements Checker by projecting the live registries into the shared access model and
// running the canonical access.Eligible decision.
func (cc *clientChecker) Eligible(ctx context.Context, principal, role, team, scope string) (access.Decision, error) {
	var people v1beta1.PersonList
	if err := cc.c.List(ctx, &people); err != nil {
		return access.Decision{}, err
	}
	var roles v1beta1.WorkforceRoleList
	if err := cc.c.List(ctx, &roles); err != nil {
		return access.Decision{}, err
	}
	return access.Eligible(toPeople(people.Items), toRoles(roles.Items), principal, role, team, scope), nil
}

func toPeople(items []v1beta1.Person) []access.Person {
	out := make([]access.Person, 0, len(items))
	for i := range items {
		p := &items[i]
		ap := access.Person{Name: p.Name, Anchor: p.Spec.Person}
		if p.Spec.Handles != nil {
			ap.GitHub = p.Spec.Handles.GitHub
		}
		for _, g := range p.Spec.Grants {
			ap.Grants = append(ap.Grants, access.Grant{Role: g.Role, Team: g.Team, Scope: g.Scope, Activation: g.Activation})
		}
		out = append(out, ap)
	}
	return out
}

func toRoles(items []v1beta1.WorkforceRole) map[string]access.Role {
	out := make(map[string]access.Role, len(items))
	for i := range items {
		r := &items[i]
		ar := access.Role{Name: r.Name, Reach: r.Spec.Reach, Power: r.Spec.Power, Mode: r.Spec.Mode, RiskTier: r.Spec.RiskTier}
		if ic := r.Spec.IdentityCenter; ic != nil {
			ar.PermissionSet = ic.PermissionSet
			ar.SessionDuration = ic.SessionDuration
		}
		out[r.Name] = ar
	}
	return out
}
