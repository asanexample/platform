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
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	activationv1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
	"github.com/asanexample/platform/operators/activation/internal/catalog"
	"github.com/asanexample/platform/operators/activation/internal/plane"
	"github.com/asanexample/platform/operators/activation/internal/telemetry"
)

const (
	// finalizerName guards teardown: the native grant is revoked before the CR is removed.
	finalizerName = "platform.refplat.org/activation-teardown"
	// teardownStartedAtAnnotation stamps when teardown began, for the revoke-duration metric.
	teardownStartedAtAnnotation = "platform.refplat.org/teardown-started-at"
	// pollBackoff is the requeue delay while an async AWS operation is in flight.
	pollBackoff = 10 * time.Second

	conditionReady = "Ready"
)

// ActivationReconciler reconciles an Activation: it mints the borrowed power across the
// projection planes, holds it until expiry, and revokes it on expiry or deletion. Mint and
// revoke are asynchronous (see the awsidc plane), so a single Reconcile advances the state
// machine one step and requeues; status.expiresAt is the crash-safe expiry clock.
type ActivationReconciler struct {
	client.Client
	Scheme    *runtime.Scheme
	Plane     plane.Plane
	Catalog   catalog.Catalog
	Telemetry *telemetry.Telemetry
	Recorder  record.EventRecorder
	// Clock is injected for deterministic tests; defaults to time.Now.
	Clock func() time.Time
}

func (r *ActivationReconciler) now() time.Time {
	if r.Clock != nil {
		return r.Clock()
	}
	return time.Now()
}

// +kubebuilder:rbac:groups=platform.refplat.org,resources=workforceroles,verbs=get;list;watch
// +kubebuilder:rbac:groups=platform.refplat.org,resources=activations,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=platform.refplat.org,resources=activations/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=platform.refplat.org,resources=activations/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch

// Reconcile advances one Activation one step toward its declared lifecycle.
func (r *ActivationReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	ctx, span := r.Telemetry.Tracer.Start(ctx, "Reconcile")
	defer span.End()

	var act activationv1alpha1.Activation
	if err := r.Get(ctx, req.NamespacedName, &act); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	span.SetAttributes(
		attribute.String("activation.principal", act.Spec.Principal),
		attribute.String("activation.role", act.Spec.Role),
	)

	// Teardown path: the CR is being deleted, or its window has expired.
	if !act.DeletionTimestamp.IsZero() {
		return r.reconcileTeardown(ctx, &act, true)
	}
	if r.expired(&act) {
		return r.reconcileTeardown(ctx, &act, false)
	}

	// Ensure the finalizer is present before minting anything (so teardown can never be skipped).
	if controllerutil.AddFinalizer(&act, finalizerName) {
		if err := r.Update(ctx, &act); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true}, nil
	}

	// Nothing to do once it's reached a terminal/active rest state (expiry is handled above).
	if act.Status.Phase == activationv1alpha1.PhaseFailed {
		return ctrl.Result{}, nil
	}
	if act.Status.Phase == activationv1alpha1.PhaseActive {
		// Hold until expiry; requeue with a bounded delay so a dropped timer self-heals.
		return ctrl.Result{RequeueAfter: r.untilExpiry(&act)}, nil
	}

	return r.reconcileMint(ctx, &act)
}

// reconcileMint advances minting and sets grantedAt/expiresAt on the first granted account.
func (r *ActivationReconciler) reconcileMint(ctx context.Context, act *activationv1alpha1.Activation) (ctrl.Result, error) {
	ctx, span := r.Telemetry.Tracer.Start(ctx, "Mint")
	defer span.End()
	log := logf.FromContext(ctx)

	// Resolve the role from the catalog (fail CLOSED): an unknown role cannot be granted — we
	// can't bound its duration (the cap) or target its permission set.
	info, err := r.Catalog.Lookup(ctx, act.Spec.Role)
	if err != nil {
		act.Status.Phase = activationv1alpha1.PhaseFailed
		meta.SetStatusCondition(&act.Status.Conditions, metav1.Condition{
			Type: conditionReady, Status: metav1.ConditionFalse, Reason: "RoleNotResolved", Message: err.Error(),
		})
		span.SetStatus(codes.Error, err.Error())
		r.Recorder.Event(act, "Warning", "RoleNotResolved", err.Error())
		log.Error(err, "role not resolvable from the WorkforceRole catalog")
		return ctrl.Result{}, r.Status().Update(ctx, act)
	}

	ps := planeStatus(act, r.Plane.Name())
	done, mintErr := r.Plane.Mint(ctx, act, ps)
	setPlaneStatus(act, ps)

	// Stamp the crash-safe clock once, on the first confirmed-granted account — capping the
	// borrow to the role's sessionDuration ceiling (the blast-radius bound).
	if act.Status.GrantedAt == nil && anyGranted(ps) {
		now := r.now()
		d := act.Spec.Duration.Duration
		if info.Cap > 0 && d > info.Cap {
			d = info.Cap
		}
		act.Status.GrantedAt = &metav1.Time{Time: now}
		act.Status.ExpiresAt = &metav1.Time{Time: now.Add(d)}
	}

	switch {
	case mintErr != nil && plane.IsTerminal(mintErr):
		act.Status.Phase = activationv1alpha1.PhaseFailed
		meta.SetStatusCondition(&act.Status.Conditions, metav1.Condition{
			Type: conditionReady, Status: metav1.ConditionFalse, Reason: "MintFailed", Message: mintErr.Error(),
		})
		span.SetStatus(codes.Error, mintErr.Error())
		r.Telemetry.Metrics.MintFailures.Add(ctx, 1, attrs(act, r.Plane.Name()))
		r.Recorder.Event(act, "Warning", "MintFailed", mintErr.Error())
		log.Error(mintErr, "minting failed terminally")
		return ctrl.Result{}, r.Status().Update(ctx, act)
	case mintErr != nil:
		act.Status.Phase = activationv1alpha1.PhaseProvisioning
		if err := r.Status().Update(ctx, act); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{}, mintErr // retryable → requeue with backoff
	case !done:
		act.Status.Phase = activationv1alpha1.PhaseProvisioning
		if err := r.Status().Update(ctx, act); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{RequeueAfter: pollBackoff}, nil
	}

	act.Status.Phase = activationv1alpha1.PhaseActive
	meta.SetStatusCondition(&act.Status.Conditions, metav1.Condition{
		Type: conditionReady, Status: metav1.ConditionTrue, Reason: "Granted", Message: "borrowed power is active",
	})
	r.Telemetry.Metrics.MintDuration.Record(ctx, r.now().Sub(act.CreationTimestamp.Time).Seconds(), attrs(act, r.Plane.Name()))
	r.Recorder.Eventf(act, "Normal", "Granted", "borrowed %s until %s", act.Spec.Role, act.Status.ExpiresAt)
	if err := r.Status().Update(ctx, act); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: r.untilExpiry(act)}, nil
}

// reconcileTeardown revokes the borrowed power. It is leak-safe: it stays Expiring and keeps
// retrying until the plane reports zero live assignments. deleting selects the finalizer path.
func (r *ActivationReconciler) reconcileTeardown(ctx context.Context, act *activationv1alpha1.Activation, deleting bool) (ctrl.Result, error) {
	ctx, span := r.Telemetry.Tracer.Start(ctx, "Teardown")
	defer span.End()

	if !controllerutil.ContainsFinalizer(act, finalizerName) {
		return ctrl.Result{}, nil // nothing we own
	}
	r.stampTeardownStart(ctx, act)

	ps := planeStatus(act, r.Plane.Name())
	done, revErr := r.Plane.Revoke(ctx, act, ps)
	setPlaneStatus(act, ps)
	act.Status.Phase = activationv1alpha1.PhaseExpiring

	if revErr != nil {
		r.Telemetry.Metrics.RevokeFailures.Add(ctx, 1, attrs(act, r.Plane.Name()))
		r.Recorder.Event(act, "Warning", "RevokeRetrying", revErr.Error())
		_ = r.Status().Update(ctx, act)
		return ctrl.Result{}, revErr // retryable → requeue+backoff; never give up with a live grant
	}
	if !done {
		_ = r.Status().Update(ctx, act)
		return ctrl.Result{RequeueAfter: pollBackoff}, nil
	}

	r.recordRevokeDuration(ctx, act)
	r.Recorder.Event(act, "Normal", "Revoked", "borrowed power revoked")

	if deleting {
		controllerutil.RemoveFinalizer(act, finalizerName)
		return ctrl.Result{}, r.Update(ctx, act)
	}
	// Expiry path: mark Expired, then delete the CR so its (deterministic) name frees up. The
	// deletion reconcile re-verifies zero live assignments and removes the finalizer.
	act.Status.Phase = activationv1alpha1.PhaseExpired
	if err := r.Status().Update(ctx, act); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{}, client.IgnoreNotFound(r.Delete(ctx, act))
}

func (r *ActivationReconciler) expired(act *activationv1alpha1.Activation) bool {
	return act.Status.ExpiresAt != nil && !r.now().Before(act.Status.ExpiresAt.Time)
}

// untilExpiry returns the delay until expiry, clamped to a bounded max so a missed timer
// self-heals quickly (the drift backstop is deferred) and to immediate if already past.
func (r *ActivationReconciler) untilExpiry(act *activationv1alpha1.Activation) time.Duration {
	const maxResync = time.Minute
	if act.Status.ExpiresAt == nil {
		return maxResync
	}
	d := act.Status.ExpiresAt.Sub(r.now())
	switch {
	case d <= 0:
		return time.Millisecond // expired → reconcile immediately
	case d > maxResync:
		return maxResync
	default:
		return d
	}
}

func (r *ActivationReconciler) stampTeardownStart(ctx context.Context, act *activationv1alpha1.Activation) {
	if _, ok := act.Annotations[teardownStartedAtAnnotation]; ok {
		return
	}
	patch := client.MergeFrom(act.DeepCopy())
	if act.Annotations == nil {
		act.Annotations = map[string]string{}
	}
	act.Annotations[teardownStartedAtAnnotation] = r.now().UTC().Format(time.RFC3339)
	_ = r.Patch(ctx, act, patch)
}

func (r *ActivationReconciler) recordRevokeDuration(ctx context.Context, act *activationv1alpha1.Activation) {
	stamp, ok := act.Annotations[teardownStartedAtAnnotation]
	if !ok {
		return
	}
	started, err := time.Parse(time.RFC3339, stamp)
	if err != nil {
		return
	}
	r.Telemetry.Metrics.RevokeDuration.Record(ctx, r.now().Sub(started).Seconds(), attrs(act, r.Plane.Name()))
}

// SetupWithManager sets up the controller with the Manager.
func (r *ActivationReconciler) SetupWithManager(mgr ctrl.Manager) error {
	if r.Recorder == nil {
		//nolint:staticcheck // record.EventRecorder is the widely-used API; the replacement has a different signature.
		r.Recorder = mgr.GetEventRecorderFor("activation-controller")
	}
	return ctrl.NewControllerManagedBy(mgr).
		For(&activationv1alpha1.Activation{}).
		Named("activation").
		Complete(r)
}
