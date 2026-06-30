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
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
	platformv1beta1 "github.com/asanexample/platform/operators/activation/api/v1beta1"
	"github.com/asanexample/platform/operators/activation/internal/catalog"
	"github.com/asanexample/platform/operators/activation/internal/eligibility"
	"github.com/asanexample/platform/operators/activation/internal/plane"
	planefake "github.com/asanexample/platform/operators/activation/internal/plane/fake"
	"github.com/asanexample/platform/operators/activation/internal/telemetry"
	"github.com/asanexample/platform/pkg/access"
)

// fakeEligibility is a controllable eligibility checker for the reconciler tests.
type fakeEligibility struct {
	allowed bool
	reason  string
}

func (f fakeEligibility) Eligible(_ context.Context, _, _, _, _ string) (access.Decision, error) {
	return access.Decision{Allowed: f.allowed, Reason: f.reason}, nil
}

// fakeCatalog is a controllable role catalog for the reconciler tests.
type fakeCatalog struct{ roles map[string]catalog.RoleInfo }

func (f fakeCatalog) Lookup(_ context.Context, role string) (catalog.RoleInfo, error) {
	if info, ok := f.roles[role]; ok {
		return info, nil
	}
	return catalog.RoleInfo{}, catalog.ErrNotInCatalog
}

// defaultCatalog knows break-glass with a cap (2h) larger than the tests' 1h borrow, so the
// existing lifecycle tests aren't capped; the cap test overrides r.Catalog with a tighter cap.
func defaultCatalog() fakeCatalog {
	return fakeCatalog{roles: map[string]catalog.RoleInfo{
		"break-glass": {PermissionSet: "AdministratorAccess", Cap: 2 * time.Hour, Mode: "on-demand", RiskTier: "apex"},
	}}
}

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
		Client:      k8sClient,
		Scheme:      k8sClient.Scheme(),
		Plane:       p,
		Catalog:     defaultCatalog(),
		Eligibility: fakeEligibility{allowed: true},
		Telemetry:   telem,
		Recorder:    record.NewFakeRecorder(256),
		Clock:       clk.now,
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

// mustCreateObj creates any object, tolerating AlreadyExists (envtest is shared across tests, so a
// registry fixture like a WorkforceRole may already be present from an earlier test).
func mustCreateObj(t *testing.T, obj client.Object) {
	t.Helper()
	if err := k8sClient.Create(context.Background(), obj); err != nil && !apierrors.IsAlreadyExists(err) {
		t.Fatalf("create %T: %v", obj, err)
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

func TestControllerCapEnforced(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)
	// The role's catalog cap is 1h; the borrow requests 4h — it must be capped to 1h.
	r.Catalog = fakeCatalog{roles: map[string]catalog.RoleInfo{
		"break-glass": {PermissionSet: "AdministratorAccess", Cap: time.Hour},
	}}
	act := newActivation("capped")
	act.Spec.Duration = metav1.Duration{Duration: 4 * time.Hour}
	mustCreate(t, act)

	got := pump(t, r, "capped", phaseIs(activationv1alpha1.PhaseActive))
	exp, granted := got.Status.ExpiresAt.Time, got.Status.GrantedAt.Time
	if exp.Sub(granted) != time.Hour {
		t.Errorf("borrow must be capped to the role's 1h ceiling, got %v", exp.Sub(granted))
	}
}

// TestControllerCapViaRealCatalog exercises the whole chain end-to-end: a real WorkforceRole CR
// projected into envtest, read by the real clientCatalog, capping a 4h borrow to the role's 1h.
func TestControllerCapViaRealCatalog(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)
	r.Catalog = catalog.New(k8sClient)

	wf := &platformv1beta1.WorkforceRole{
		ObjectMeta: metav1.ObjectMeta{Name: "break-glass"},
		Spec: platformv1beta1.WorkforceRoleSpec{
			Reach: "platform", Power: "manage-access", Mode: "on-demand", RiskTier: "apex",
			IdentityCenter: &platformv1beta1.IdentityCenterProjection{PermissionSet: "AdministratorAccess", SessionDuration: "PT1H"},
		},
	}
	if err := k8sClient.Create(context.Background(), wf); err != nil {
		t.Fatalf("create WorkforceRole: %v", err)
	}

	act := newActivation("realcap")
	act.Spec.Duration = metav1.Duration{Duration: 4 * time.Hour}
	mustCreate(t, act)

	got := pump(t, r, "realcap", phaseIs(activationv1alpha1.PhaseActive))
	exp, granted := got.Status.ExpiresAt.Time, got.Status.GrantedAt.Time
	if exp.Sub(granted) != time.Hour {
		t.Errorf("real-catalog borrow must be capped to the role's 1h, got %v", exp.Sub(granted))
	}
}

func TestControllerRoleNotInCatalogFailsClosed(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)
	r.Catalog = fakeCatalog{roles: map[string]catalog.RoleInfo{}} // break-glass absent
	mustCreate(t, newActivation("uncataloged"))

	pump(t, r, "uncataloged", phaseIs(activationv1alpha1.PhaseFailed))
	if p.LiveCount() != 0 {
		t.Error("an uncataloged role must fail closed — nothing minted")
	}
}

// TestControllerNonCanonicalDurationApplies is the regression for the live-smoke bug: a human applying
// `duration: 30m` (non-canonical) must still reconcile. spec is immutable (CEL self == oldSelf), and a
// full Update round-trips metav1.Duration "30m" -> "30m0s", which the apiserver reads as a spec mutation
// and rejects — so the finalizer is added via Patch instead. Created as unstructured because the typed Go
// client always marshals the canonical form (which is why the original tests missed this).
func TestControllerNonCanonicalDurationApplies(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)

	u := &unstructured.Unstructured{}
	u.SetGroupVersionKind(activationv1alpha1.GroupVersion.WithKind("Activation"))
	u.SetName("noncanon")
	if err := unstructured.SetNestedField(u.Object, map[string]any{
		"principal":   "josh",
		"role":        "break-glass",
		"reach":       map[string]any{"scope": "platform"},
		"duration":    "30m", // non-canonical on purpose
		"reason":      "test",
		"requestedBy": "josh",
	}, "spec"); err != nil {
		t.Fatal(err)
	}
	if err := k8sClient.Create(context.Background(), u); err != nil {
		t.Fatalf("create: %v", err)
	}

	pump(t, r, "noncanon", phaseIs(activationv1alpha1.PhaseActive))
}

// TestControllerMintFailureRollsBackPartialGrants: minting is serial across accounts, so when a later
// account fails terminally the earlier ones are already granted — a Failed activation must NOT leave that
// dangling admin. The terminal-failure path revokes the partial footprint before settling into Failed.
func TestControllerMintFailureRollsBackPartialGrants(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111", "222", "333")
	p.FailOn = "333" // 111 + 222 grant, then 333 fails terminally
	r := newReconciler(t, p, clk)
	mustCreate(t, newActivation("rollback"))

	// Settles into Failed, then the Failed-phase cleanup revokes the partial grants over subsequent
	// reconciles — wait for both.
	pump(t, r, "rollback", func(a *activationv1alpha1.Activation) bool {
		return a != nil && a.Status.Phase == activationv1alpha1.PhaseFailed && p.LiveCount() == 0
	})
}

func TestControllerNotEligibleFailsClosed(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)
	r.Eligibility = fakeEligibility{allowed: false, reason: "no break-glass grant"}
	mustCreate(t, newActivation("ineligible"))

	pump(t, r, "ineligible", phaseIs(activationv1alpha1.PhaseFailed))
	if p.LiveCount() != 0 {
		t.Error("an ineligible borrow must fail closed — nothing minted")
	}
}

// TestControllerEligibilityViaRealRegistry exercises the real eligibility checker end-to-end:
// a Person + WorkforceRole projected into envtest, with the borrow allowed only for the holder.
func TestControllerEligibilityViaRealRegistry(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)
	r.Eligibility = eligibility.New(k8sClient)

	mustCreateObj(t, &platformv1beta1.WorkforceRole{
		ObjectMeta: metav1.ObjectMeta{Name: "break-glass"},
		Spec:       platformv1beta1.WorkforceRoleSpec{Reach: "platform", Power: "manage-access", Mode: "on-demand", RiskTier: "apex"},
	})
	mustCreateObj(t, &platformv1beta1.Person{
		ObjectMeta: metav1.ObjectMeta{Name: "josh"},
		Spec: platformv1beta1.PersonSpec{Person: "admin", Grants: []platformv1beta1.PersonGrant{
			{Role: "break-glass", Scope: "platform", Activation: "on-demand"},
		}},
	})

	// josh (eligible) proceeds; a principal with no grant fails closed.
	mustCreate(t, newActivation("elig-josh"))
	pump(t, r, "elig-josh", phaseIs(activationv1alpha1.PhaseActive))

	bad := newActivation("elig-nobody")
	bad.Spec.Principal = "nobody"
	mustCreate(t, bad)
	pump(t, r, "elig-nobody", phaseIs(activationv1alpha1.PhaseFailed))
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

// fakeAudit is an in-memory audit.Recorder for asserting the grant/revoke/renew audit wiring.
type fakeAudit struct {
	grants     int
	revokes    int
	renews     int
	failRevoke bool
}

func (f *fakeAudit) RecordGrant(context.Context, *activationv1alpha1.Activation) error {
	f.grants++
	return nil
}

func (f *fakeAudit) RecordRevoke(context.Context, *activationv1alpha1.Activation) error {
	f.revokes++
	if f.failRevoke {
		return errors.New("audit db down")
	}
	return nil
}

func (f *fakeAudit) RecordRenew(context.Context, *activationv1alpha1.Activation, int, activationv1alpha1.Renewal, time.Time) error {
	f.renews++
	return nil
}

func (f *fakeAudit) Close() {}

// The end-of-borrow event must be durably recorded BEFORE the CR can vanish. So while the revoke audit
// fails, the finalizer is held (the CR is not collected) even though the grants are already revoked; once
// the audit succeeds, the finalizer drops.
func TestControllerRevokeAuditGatesFinalizer(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)
	fa := &fakeAudit{failRevoke: true}
	r.Audit = fa

	mustCreate(t, newActivation("auditgate"))
	pump(t, r, "auditgate", phaseIs(activationv1alpha1.PhaseActive))
	if fa.grants != 1 {
		t.Fatalf("grant audited %d times on the way to Active, want 1", fa.grants)
	}

	var act activationv1alpha1.Activation
	if err := k8sClient.Get(context.Background(), types.NamespacedName{Name: "auditgate"}, &act); err != nil {
		t.Fatal(err)
	}
	if err := k8sClient.Delete(context.Background(), &act); err != nil {
		t.Fatal(err)
	}

	// Revoke audit keeps failing → finalizer held → CR still present, but grants already pulled back.
	for range 8 {
		_, _ = r.Reconcile(context.Background(), req("auditgate"))
	}
	var held activationv1alpha1.Activation
	if err := k8sClient.Get(context.Background(), types.NamespacedName{Name: "auditgate"}, &held); err != nil {
		t.Fatalf("CR deleted while the revoke audit was failing — the audit did not gate the finalizer: %v", err)
	}
	if !containsFinalizer(&held) {
		t.Fatal("finalizer removed despite the revoke audit failing")
	}
	if p.LiveCount() != 0 {
		t.Errorf("grants should be revoked already (only the audit fails); %d still live", p.LiveCount())
	}

	// Audit recovers → the borrow's end is recorded → the finalizer drops → the CR is collected.
	fa.failRevoke = false
	pump(t, r, "auditgate", isGone)
	if fa.revokes == 0 {
		t.Fatal("revoke audit never attempted")
	}
}

// Extend pushes the window out on a fresh renew nonce, is idempotent per nonce, and never extends past the
// role's sessionDuration ceiling from grantedAt (the cap = 2h in the test catalog; 1h borrow window).
func TestControllerExtend(t *testing.T) {
	clk := &fakeClock{t: time.Now()}
	p := planefake.NewPlane("111")
	r := newReconciler(t, p, clk)
	fa := &fakeAudit{}
	r.Audit = fa

	mustCreate(t, newActivation("extend"))
	pump(t, r, "extend", phaseIs(activationv1alpha1.PhaseActive))

	get := func() *activationv1alpha1.Activation {
		var a activationv1alpha1.Activation
		if err := k8sClient.Get(context.Background(), types.NamespacedName{Name: "extend"}, &a); err != nil {
			t.Fatal(err)
		}
		return &a
	}
	renew := func(nonce string) {
		a := get()
		if a.Annotations == nil {
			a.Annotations = map[string]string{}
		}
		a.Annotations[renewAnnotation] = `{"nonce":"` + nonce + `","authTime":"` +
			clk.now().UTC().Format(time.RFC3339) + `","acr":"silver"}`
		if err := k8sClient.Update(context.Background(), a); err != nil {
			t.Fatal(err)
		}
		if _, err := r.Reconcile(context.Background(), req("extend")); err != nil {
			t.Fatal(err)
		}
	}

	start := get().Status.ExpiresAt.Time // grantedAt + 1h

	// r1 at +30m → extends to ~now+1h.
	clk.advance(30 * time.Minute)
	renew("r1")
	a := get()
	if !a.Status.ExpiresAt.After(start) {
		t.Fatalf("not extended: %v !> %v", a.Status.ExpiresAt.Time, start)
	}
	if len(a.Status.Renewals) != 1 || fa.renews != 1 || a.Status.LastRenewalNonce != "r1" {
		t.Fatalf("renewal not recorded/audited/acked: renewals=%d audited=%d nonce=%s",
			len(a.Status.Renewals), fa.renews, a.Status.LastRenewalNonce)
	}

	// Same nonce again → idempotent (no second renewal).
	if _, err := r.Reconcile(context.Background(), req("extend")); err != nil {
		t.Fatal(err)
	}
	if len(get().Status.Renewals) != 1 || fa.renews != 1 {
		t.Fatal("a repeated nonce must not re-process")
	}

	// r2 at +1h15m would reach now+1h = grantedAt+2h15m, but the cap clamps it to grantedAt+2h.
	clk.advance(45 * time.Minute)
	renew("r2")
	ceiling := get().Status.ExpiresAt.Time // grantedAt + 2h
	if len(get().Status.Renewals) != 2 {
		t.Fatalf("capped-to-ceiling extension should still record: %d", len(get().Status.Renewals))
	}

	// r3 when already at the ceiling → no gain: RenewCapped, no new renewal record, nonce acked.
	clk.advance(30 * time.Minute)
	renew("r3")
	a = get()
	if a.Status.ExpiresAt.After(ceiling) {
		t.Fatalf("extended past the cap: %v > %v", a.Status.ExpiresAt.Time, ceiling)
	}
	if len(a.Status.Renewals) != 2 {
		t.Fatalf("a no-gain renewal must not add a record: %d", len(a.Status.Renewals))
	}
	if a.Status.LastRenewalNonce != "r3" {
		t.Fatal("capped nonce not acked")
	}
}
