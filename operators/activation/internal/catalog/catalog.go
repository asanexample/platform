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

// Package catalog resolves a WorkforceRole's activation-relevant facts — the AWS permission
// set and the borrow-duration CAP — from the in-cluster role catalog (the git-projected
// WorkforceRole CRs). It replaces the operator's bootstrap --role-permission-sets flag with
// the real registry, and shares pkg/access for ISO-8601 cap parsing so the cap logic stays in
// lockstep with the platctl break-glass CLI.
package catalog

import (
	"context"
	"errors"
	"fmt"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/asanexample/platform/operators/activation/api/v1beta1"
	"github.com/asanexample/platform/pkg/access"
)

// ErrNotInCatalog means a role has no WorkforceRole CR — the operator FAILS CLOSED (it cannot
// determine the cap or the AWS target, so it must not grant).
var ErrNotInCatalog = errors.New("role is not in the WorkforceRole catalog")

// RoleInfo is the activation-relevant projection of a WorkforceRole.
type RoleInfo struct {
	PermissionSet string        // AWS permission set name; "" if the role has no AWS plane
	Cap           time.Duration // borrow-duration ceiling; 0 = uncapped
	Mode          string        // standing | on-demand
	RiskTier      string        // standard | elevated | apex
}

// Catalog resolves a role name to its activation-relevant facts.
type Catalog interface {
	Lookup(ctx context.Context, role string) (RoleInfo, error)
}

// clientCatalog reads WorkforceRole CRs through a (cached) controller-runtime client.
type clientCatalog struct{ c client.Reader }

// New builds a Catalog backed by the given reader (the manager's cached client in prod).
func New(c client.Reader) Catalog { return &clientCatalog{c: c} }

// Lookup implements Catalog. A missing role returns ErrNotInCatalog (fail closed); an
// unparseable sessionDuration is a hard error (don't silently treat a bad cap as uncapped).
func (cc *clientCatalog) Lookup(ctx context.Context, role string) (RoleInfo, error) {
	var wf v1beta1.WorkforceRole
	if err := cc.c.Get(ctx, client.ObjectKey{Name: role}, &wf); err != nil {
		if apierrors.IsNotFound(err) {
			return RoleInfo{}, fmt.Errorf("%w: %q", ErrNotInCatalog, role)
		}
		return RoleInfo{}, fmt.Errorf("reading WorkforceRole %q: %w", role, err)
	}
	info := RoleInfo{Mode: wf.Spec.Mode, RiskTier: wf.Spec.RiskTier}
	if ic := wf.Spec.IdentityCenter; ic != nil {
		info.PermissionSet = ic.PermissionSet
		cap, err := access.ParseSessionDuration(ic.SessionDuration)
		if err != nil {
			return RoleInfo{}, fmt.Errorf("role %q: %w", role, err)
		}
		info.Cap = cap
	}
	return info, nil
}
