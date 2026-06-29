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

package catalog

import (
	"context"
	"errors"
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/asanexample/platform/operators/activation/api/v1beta1"
)

func scheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	s := runtime.NewScheme()
	if err := v1beta1.AddToScheme(s); err != nil {
		t.Fatal(err)
	}
	return s
}

func wfrole(name, ps, dur string) *v1beta1.WorkforceRole {
	return &v1beta1.WorkforceRole{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Spec: v1beta1.WorkforceRoleSpec{
			Reach: "platform", Power: "manage-access", Mode: "on-demand", RiskTier: "apex",
			IdentityCenter: &v1beta1.IdentityCenterProjection{PermissionSet: ps, SessionDuration: dur},
		},
	}
}

func TestLookupFound(t *testing.T) {
	c := fake.NewClientBuilder().WithScheme(scheme(t)).
		WithObjects(wfrole("break-glass", "AdministratorAccess", "PT1H")).Build()

	info, err := New(c).Lookup(context.Background(), "break-glass")
	if err != nil {
		t.Fatalf("Lookup: %v", err)
	}
	if info.PermissionSet != "AdministratorAccess" {
		t.Errorf("permissionSet = %q, want AdministratorAccess", info.PermissionSet)
	}
	if info.Cap != time.Hour {
		t.Errorf("cap = %v, want 1h", info.Cap)
	}
	if info.Mode != "on-demand" || info.RiskTier != "apex" {
		t.Errorf("mode/risk = %q/%q", info.Mode, info.RiskTier)
	}
}

func TestLookupNotFoundFailsClosed(t *testing.T) {
	c := fake.NewClientBuilder().WithScheme(scheme(t)).Build()
	if _, err := New(c).Lookup(context.Background(), "ghost"); !errors.Is(err, ErrNotInCatalog) {
		t.Errorf("want ErrNotInCatalog, got %v", err)
	}
}

func TestLookupBadDurationErrors(t *testing.T) {
	c := fake.NewClientBuilder().WithScheme(scheme(t)).
		WithObjects(wfrole("bad", "X", "NOT-A-DURATION")).Build()
	if _, err := New(c).Lookup(context.Background(), "bad"); err == nil {
		t.Error("a malformed sessionDuration must error, not be silently treated as uncapped")
	}
}

func TestLookupNoIdentityCenter(t *testing.T) {
	role := &v1beta1.WorkforceRole{
		ObjectMeta: metav1.ObjectMeta{Name: "viewer"},
		Spec:       v1beta1.WorkforceRoleSpec{Reach: "any", Power: "look", Mode: "standing", RiskTier: "standard"},
	}
	c := fake.NewClientBuilder().WithScheme(scheme(t)).WithObjects(role).Build()
	info, err := New(c).Lookup(context.Background(), "viewer")
	if err != nil {
		t.Fatal(err)
	}
	if info.PermissionSet != "" || info.Cap != 0 {
		t.Errorf("role without identityCenter should have empty PS + 0 cap, got %+v", info)
	}
}
