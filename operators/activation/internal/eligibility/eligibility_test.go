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

package eligibility

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
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

func person(name, anchor string, grants ...v1beta1.PersonGrant) *v1beta1.Person {
	return &v1beta1.Person{ObjectMeta: metav1.ObjectMeta{Name: name}, Spec: v1beta1.PersonSpec{Person: anchor, Grants: grants}}
}

func role(name, mode string) *v1beta1.WorkforceRole {
	return &v1beta1.WorkforceRole{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Spec:       v1beta1.WorkforceRoleSpec{Reach: "platform", Power: "manage-access", Mode: mode, RiskTier: "apex"},
	}
}

func checker(t *testing.T, objs ...client.Object) Checker {
	return New(fake.NewClientBuilder().WithScheme(scheme(t)).WithObjects(objs...).Build())
}

func TestEligibleBorrowable(t *testing.T) {
	chk := checker(t,
		person("josh", "admin", v1beta1.PersonGrant{Role: "break-glass", Scope: "platform", Activation: "on-demand"}),
		role("break-glass", "on-demand"),
	)
	d, err := chk.Eligible(context.Background(), "josh", "break-glass", "", "platform")
	if err != nil {
		t.Fatal(err)
	}
	if !d.Allowed {
		t.Errorf("josh should be eligible to borrow break-glass on platform: %s", d.Reason)
	}
}

func TestNotEligibleNoGrant(t *testing.T) {
	chk := checker(t,
		person("alpha-dev", "dev-alpha", v1beta1.PersonGrant{Role: "developer", Team: "alpha"}),
		role("break-glass", "on-demand"),
		role("developer", "standing"),
	)
	d, err := chk.Eligible(context.Background(), "alpha-dev", "break-glass", "", "platform")
	if err != nil {
		t.Fatal(err)
	}
	if d.Allowed {
		t.Error("alpha-dev has no break-glass grant — must not be eligible")
	}
}

func TestNotEligibleUnknownPrincipal(t *testing.T) {
	chk := checker(t, role("break-glass", "on-demand"))
	d, _ := chk.Eligible(context.Background(), "nobody", "break-glass", "", "platform")
	if d.Allowed {
		t.Error("an unknown principal must not be eligible")
	}
}

func TestStandingGrantIsNotBorrowable(t *testing.T) {
	// A standing grant is held, not borrowed — activation should be refused (no borrow needed).
	chk := checker(t,
		person("josh", "admin", v1beta1.PersonGrant{Role: "access-admin", Scope: "platform"}),
		role("access-admin", "standing"),
	)
	d, _ := chk.Eligible(context.Background(), "josh", "access-admin", "", "platform")
	if d.Allowed {
		t.Error("a standing grant is not borrowable via activation")
	}
}
