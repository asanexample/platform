package audit

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"

	v1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
)

func sampleActivation() *v1alpha1.Activation {
	granted := metav1.NewTime(time.Date(2026, 6, 30, 2, 16, 45, 0, time.UTC))
	expires := metav1.NewTime(time.Date(2026, 6, 30, 3, 16, 45, 0, time.UTC))
	authTime := metav1.NewTime(time.Date(2026, 6, 30, 2, 16, 40, 0, time.UTC))
	return &v1alpha1.Activation{
		ObjectMeta: metav1.ObjectMeta{
			Name: "josh-break-glass-platform",
			UID:  types.UID("be599259-uid"),
		},
		Spec: v1alpha1.ActivationSpec{
			Principal:   "josh",
			Role:        "break-glass",
			Reach:       v1alpha1.Reach{Scope: "platform"},
			Reason:      "prod incident",
			RequestedBy: "josh",
			StepUp:      &v1alpha1.StepUp{AuthTime: authTime, ACR: "silver"},
		},
		Status: v1alpha1.ActivationStatus{GrantedAt: &granted, ExpiresAt: &expires},
	}
}

type fakeExec struct {
	calls int
	sql   string
	args  []any
	err   error
}

func (f *fakeExec) Exec(_ context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	f.calls++
	f.sql, f.args = sql, args
	return pgconn.CommandTag{}, f.err
}

func TestEntryFor_Grant(t *testing.T) {
	e := entryFor(sampleActivation(), EventGranted, time.Now())
	if e.activationUID != "be599259-uid" || e.event != "granted" {
		t.Fatalf("uid/event: %+v", e)
	}
	if e.principal != "josh" || e.role != "break-glass" || e.reachScope != "platform" {
		t.Fatalf("identity fields: %+v", e)
	}
	if e.stepUpACR != "silver" || e.stepUpAuthTime == nil {
		t.Fatalf("step-up not captured: %+v", e)
	}
	if e.grantedAt == nil || e.expiresAt == nil {
		t.Fatalf("window not captured: %+v", e)
	}
	if e.revokedAt != nil {
		t.Fatalf("grant must not stamp revokedAt")
	}
}

func TestEntryFor_RevokeStampsRevokedAt(t *testing.T) {
	now := time.Date(2026, 6, 30, 2, 41, 52, 0, time.UTC)
	e := entryFor(sampleActivation(), EventRevoked, now)
	if e.event != "revoked" {
		t.Fatalf("event: %s", e.event)
	}
	if e.revokedAt == nil || !e.revokedAt.Equal(now) {
		t.Fatalf("revokedAt = %v, want %v", e.revokedAt, now)
	}
}

func TestRecord_InsertIsIdempotentAndBound(t *testing.T) {
	fx := &fakeExec{}
	r := &pgRecorder{db: fx, now: func() time.Time { return time.Unix(0, 0).UTC() }}

	if err := r.RecordGrant(context.Background(), sampleActivation()); err != nil {
		t.Fatalf("RecordGrant: %v", err)
	}
	if fx.calls != 1 {
		t.Fatalf("calls = %d", fx.calls)
	}
	// Idempotency is enforced in SQL, not Go — assert the ON CONFLICT guard is present.
	if !contains(fx.sql, "ON CONFLICT (activation_uid, event) DO NOTHING") {
		t.Fatalf("insert missing idempotency guard:\n%s", fx.sql)
	}
	if len(fx.args) != 13 {
		t.Fatalf("args = %d, want 13", len(fx.args))
	}
	if fx.args[2] != "josh" || fx.args[3] != "break-glass" {
		t.Fatalf("bound identity wrong: %v", fx.args[2:4])
	}
}

func TestRecord_EmptyOptionalsAreNull(t *testing.T) {
	fx := &fakeExec{}
	r := &pgRecorder{db: fx, now: time.Now}
	act := sampleActivation()
	act.Spec.Reach = v1alpha1.Reach{Scope: "platform"} // team empty → NULL
	if err := r.RecordGrant(context.Background(), act); err != nil {
		t.Fatal(err)
	}
	// reach_team is arg #5 (index 4); empty string must be bound as nil, not "".
	if fx.args[4] != nil {
		t.Fatalf("empty reach_team must be NULL, got %#v", fx.args[4])
	}
}

func TestRecord_PropagatesDBError(t *testing.T) {
	fx := &fakeExec{err: errors.New("db down")}
	r := &pgRecorder{db: fx, now: time.Now}
	if err := r.RecordRevoke(context.Background(), sampleActivation()); err == nil {
		t.Fatal("expected error to propagate (so the finalizer is held)")
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
