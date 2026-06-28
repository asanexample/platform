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
	"context"
	"errors"
	"slices"
	"sync"
	"testing"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
	"github.com/asanexample/platform/operators/activation/internal/plane"
	planefake "github.com/asanexample/platform/operators/activation/internal/plane/fake"
	"github.com/asanexample/platform/operators/activation/internal/telemetry"
)

// fakeClock is a controllable clock for deterministic expiry tests.
type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *fakeClock) now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *fakeClock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

func newReconciler(t *testing.T, p plane.Plane, clk *fakeClock) *ActivationReconciler {
	t.Helper()
	telem, err := telemetry.Setup(context.Background(), "test", "0")
	if err != nil {
		t.Fatalf("telemetry setup: %v", err)
	}
	return &ActivationReconciler{
		Client:    k8sClient,
		Scheme:    k8sClient.Scheme(),
		Plane:     p,
		Telemetry: telem,
		Recorder:  record.NewFakeRecorder(256),
		Clock:     clk.now,
	}
}

func newActivation(name string) *activationv1alpha1.Activation {
	return &activationv1alpha1.Activation{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Spec: activationv1alpha1.ActivationSpec{
			Principal:   "josh",
			Role:        "break-glass",
			Reach:       activationv1alpha1.Reach{Scope: "platform"},
			Duration:    metav1.Duration{Duration: time.Hour},
			Reason:      "test",
			RequestedBy: "josh",
		},
	}
}

func req(name string) ctrl.Request {
	return ctrl.Request{NamespacedName: types.NamespacedName{Name: name}}
}

// pump calls Reconcile until cond is satisfied (or the bound is hit). A gone object is passed
// to cond as nil. Retryable errors are expected (the controller would requeue) and don't stop it.
func pump(t *testing.T, r *ActivationReconciler, name string, cond func(*activationv1alpha1.Activation) bool) *activationv1alpha1.Activation {
	t.Helper()
	ctx := context.Background()
	for range 60 {
		_, _ = r.Reconcile(ctx, req(name))
		var act activationv1alpha1.Activation
		err := k8sClient.Get(ctx, types.NamespacedName{Name: name}, &act)
		if apierrors.IsNotFound(err) {
			if cond(nil) {
				return nil
			}
			continue
		}
		if err != nil {
			t.Fatalf("get: %v", err)
		}
		if cond(&act) {
			return &act
		}
	}
	t.Fatalf("activation %q did not reach the expected state in time", name)
	return nil
}

func phaseIs(p activationv1alpha1.ActivationPhase) func(*activationv1alpha1.Activation) bool {
	return func(a *activationv1alpha1.Activation) bool { return a != nil && a.Status.Phase == p }
}

func isGone(a *activationv1alpha1.Activation) bool { return a == nil }

func mustCreate(t *testing.T, act *activationv1alpha1.Activation) {
	t.Helper()
	if err := k8sClient.Create(context.Background(), act); err != nil {
		t.Fatalf("create: %v", err)
	}
}

func TestControllerMintToActive(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111", "222")
	p.StepsToGrant = 2 // force the async multi-reconcile path
	r := newReconciler(t, p, clk)
	mustCreate(t, newActivation("mint-active"))

	act := pump(t, r, "mint-active", phaseIs(activationv1alpha1.PhaseActive))
	if act.Status.GrantedAt == nil || act.Status.ExpiresAt == nil {
		t.Fatal("grantedAt/expiresAt must be set when Active")
	}
	granted, expires := act.Status.GrantedAt.Time, act.Status.ExpiresAt.Time
	if expires.Sub(granted) != time.Hour {
		t.Errorf("expiresAt should be grantedAt + duration, got %v", expires.Sub(granted))
	}
	if !containsFinalizer(act) {
		t.Error("finalizer must be present")
	}
}

func TestControllerExpiryRevokesAndDeletes(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111", "222")
	r := newReconciler(t, p, clk)
	mustCreate(t, newActivation("expiry"))

	pump(t, r, "expiry", phaseIs(activationv1alpha1.PhaseActive))
	if p.LiveCount() != 2 {
		t.Fatalf("expected 2 live assignments, got %d", p.LiveCount())
	}
	clk.advance(2 * time.Hour) // past expiry

	pump(t, r, "expiry", isGone)
	if p.LiveCount() != 0 {
		t.Errorf("expiry must drain all assignments, %d still live", p.LiveCount())
	}
}

func TestControllerDeletionRevokes(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)
	mustCreate(t, newActivation("deletion"))
	pump(t, r, "deletion", phaseIs(activationv1alpha1.PhaseActive))

	var act activationv1alpha1.Activation
	if err := k8sClient.Get(context.Background(), types.NamespacedName{Name: "deletion"}, &act); err != nil {
		t.Fatal(err)
	}
	if err := k8sClient.Delete(context.Background(), &act); err != nil {
		t.Fatal(err)
	}
	pump(t, r, "deletion", isGone)
	if p.LiveCount() != 0 {
		t.Errorf("deletion must revoke; %d still live", p.LiveCount())
	}
}

func TestControllerTerminalFailure(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111", "222")
	p.FailOn = "222"
	r := newReconciler(t, p, clk)
	mustCreate(t, newActivation("failure"))

	act := pump(t, r, "failure", phaseIs(activationv1alpha1.PhaseFailed))
	if act.Status.Phase != activationv1alpha1.PhaseFailed {
		t.Errorf("phase = %v, want Failed", act.Status.Phase)
	}
}

func TestControllerLeakSafeTeardown(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111", "222")
	r := newReconciler(t, p, clk)
	mustCreate(t, newActivation("leak"))
	pump(t, r, "leak", phaseIs(activationv1alpha1.PhaseActive))

	// AWS is "down": revoke keeps failing. Expiry must NOT delete the CR or drop the grant.
	p.RevokeError = errors.New("aws unavailable")
	clk.advance(2 * time.Hour)
	ctx := context.Background()
	for range 10 {
		_, _ = r.Reconcile(ctx, req("leak"))
	}
	var act activationv1alpha1.Activation
	if err := k8sClient.Get(ctx, types.NamespacedName{Name: "leak"}, &act); err != nil {
		t.Fatalf("CR must NOT be deleted while a grant is still live: %v", err)
	}
	if act.Status.Phase != activationv1alpha1.PhaseExpiring {
		t.Errorf("phase = %v, want Expiring while revoke is failing", act.Status.Phase)
	}
	if p.LiveCount() == 0 {
		t.Error("grant should still be live (revoke is failing) — must not report drained")
	}

	// AWS recovers: teardown completes.
	p.RevokeError = nil
	pump(t, r, "leak", isGone)
	if p.LiveCount() != 0 {
		t.Errorf("after recovery, all assignments must be drained; %d live", p.LiveCount())
	}
}

func TestActivationSpecImmutable(t *testing.T) {
	mustCreate(t, newActivation("immutable"))
	var act activationv1alpha1.Activation
	if err := k8sClient.Get(context.Background(), types.NamespacedName{Name: "immutable"}, &act); err != nil {
		t.Fatal(err)
	}
	act.Spec.Reason = "changed"
	if err := k8sClient.Update(context.Background(), &act); err == nil {
		t.Error("expected the immutable-spec CEL rule to reject a spec edit")
	}
}

func TestActivationReachOneOf(t *testing.T) {
	bad := newActivation("bad-reach")
	bad.Spec.Reach.Team = "alpha" // both team and scope set → must be rejected
	if err := k8sClient.Create(context.Background(), bad); err == nil {
		t.Error("expected the reach one-of CEL rule to reject team+scope")
	}
}

func containsFinalizer(act *activationv1alpha1.Activation) bool {
	return slices.Contains(act.Finalizers, finalizerName)
}
