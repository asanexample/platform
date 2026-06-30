// Package audit is the DURABLE governance trail for borrowed power (ADR-088 §3.6). The Activation CR is
// deleted when a borrow ends (its name is reused), Kubernetes Events GC within the hour, and Loki/Mimir keep
// only days — so none of them is the permanent record of "who held admin, when, why, how-proven, how-long".
// This writes an append-only row to the ADR-084 directory Postgres on every grant and revoke, so the audit
// outlives the CR and the telemetry retention.
//
// Idempotent by (activation_uid, event): a retried write is a no-op, so the grant write can be retried each
// reconcile and the revoke write can gate the finalizer (the CR is never deleted until its revoke is recorded).
package audit

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	v1alpha1 "github.com/asanexample/platform/operators/activation/api/v1alpha1"
)

// Event kinds. They are the unique key (with the activation UID), so a borrow has at most one of each —
// except renewals, which are "renewed-<seq>" so every extension is its own immutable row.
const (
	EventGranted = "granted"
	EventRevoked = "revoked"
	EventRenewed = "renewed"
)

// Recorder writes the durable audit trail. A nil/Nop recorder disables it (the operator still runs).
type Recorder interface {
	RecordGrant(ctx context.Context, act *v1alpha1.Activation) error
	RecordRevoke(ctx context.Context, act *v1alpha1.Activation) error
	// RecordRenew records one extension: event "renewed-<seq>", the renewal's own fresh step-up, and the
	// pushed-out expiry.
	RecordRenew(ctx context.Context, act *v1alpha1.Activation, seq int, renewal v1alpha1.Renewal, newExpiry time.Time) error
	Close()
}

// entry is one audit row — flattened, so it's a pure projection of the Activation (unit-tested).
type entry struct {
	activationUID  string
	event          string
	principal      string
	role           string
	reachTeam      string
	reachScope     string
	reason         string
	stepUpACR      string
	stepUpAuthTime *time.Time
	requestedBy    string
	grantedAt      *time.Time
	expiresAt      *time.Time
	revokedAt      *time.Time
}

func entryFor(act *v1alpha1.Activation, event string, now time.Time) entry {
	e := entry{
		activationUID: string(act.UID),
		event:         event,
		principal:     act.Spec.Principal,
		role:          act.Spec.Role,
		reachTeam:     act.Spec.Reach.Team,
		reachScope:    act.Spec.Reach.Scope,
		reason:        act.Spec.Reason,
		requestedBy:   act.Spec.RequestedBy,
	}
	if su := act.Spec.StepUp; su != nil {
		e.stepUpACR = su.ACR
		if !su.AuthTime.IsZero() {
			t := su.AuthTime.Time
			e.stepUpAuthTime = &t
		}
	}
	if act.Status.GrantedAt != nil {
		t := act.Status.GrantedAt.Time
		e.grantedAt = &t
	}
	if act.Status.ExpiresAt != nil {
		t := act.Status.ExpiresAt.Time
		e.expiresAt = &t
	}
	if event == EventRevoked {
		e.revokedAt = &now
	}
	return e
}

// execer is the slice of pgxpool we use — lets the insert path be unit-tested with a fake.
type execer interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

const schemaDDL = `
CREATE TABLE IF NOT EXISTS activation_audit (
    id                BIGSERIAL PRIMARY KEY,
    activation_uid    TEXT NOT NULL,
    event             TEXT NOT NULL,
    principal         TEXT NOT NULL,
    role              TEXT NOT NULL,
    reach_team        TEXT,
    reach_scope       TEXT,
    reason            TEXT,
    step_up_acr       TEXT,
    step_up_auth_time TIMESTAMPTZ,
    requested_by      TEXT,
    granted_at        TIMESTAMPTZ,
    expires_at        TIMESTAMPTZ,
    revoked_at        TIMESTAMPTZ,
    recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (activation_uid, event)
);`

const insertSQL = `
INSERT INTO activation_audit
    (activation_uid, event, principal, role, reach_team, reach_scope, reason,
     step_up_acr, step_up_auth_time, requested_by, granted_at, expires_at, revoked_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
ON CONFLICT (activation_uid, event) DO NOTHING;`

// pgRecorder writes to the directory Postgres.
type pgRecorder struct {
	db   execer
	pool *pgxpool.Pool // owned; nil when db was injected for tests
	now  func() time.Time
}

// New connects to the audit Postgres and ensures the schema. dsn is a libpq/pgx connection string.
func New(ctx context.Context, dsn string) (Recorder, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("audit: connect: %w", err)
	}
	if _, err := pool.Exec(ctx, schemaDDL); err != nil {
		pool.Close()
		return nil, fmt.Errorf("audit: ensure schema: %w", err)
	}
	return &pgRecorder{db: pool, pool: pool, now: time.Now}, nil
}

func (r *pgRecorder) insert(ctx context.Context, e entry) error {
	_, err := r.db.Exec(ctx, insertSQL,
		nullable(e.activationUID), e.event, e.principal, e.role,
		nullable(e.reachTeam), nullable(e.reachScope), nullable(e.reason),
		nullable(e.stepUpACR), e.stepUpAuthTime, nullable(e.requestedBy),
		e.grantedAt, e.expiresAt, e.revokedAt,
	)
	if err != nil {
		return fmt.Errorf("audit: write %s for %s: %w", e.event, e.activationUID, err)
	}
	return nil
}

func (r *pgRecorder) RecordGrant(ctx context.Context, act *v1alpha1.Activation) error {
	return r.insert(ctx, entryFor(act, EventGranted, r.now()))
}

func (r *pgRecorder) RecordRevoke(ctx context.Context, act *v1alpha1.Activation) error {
	return r.insert(ctx, entryFor(act, EventRevoked, r.now()))
}

func (r *pgRecorder) RecordRenew(ctx context.Context, act *v1alpha1.Activation, seq int, renewal v1alpha1.Renewal, newExpiry time.Time) error {
	e := entryFor(act, fmt.Sprintf("%s-%d", EventRenewed, seq), renewal.At.Time)
	// The renewal carries its OWN fresh step-up and the pushed-out expiry — override the originals.
	e.expiresAt = &newExpiry
	e.stepUpACR = renewal.ACR
	at := renewal.AuthTime.Time
	e.stepUpAuthTime = &at
	return r.insert(ctx, e)
}

func (r *pgRecorder) Close() {
	if r.pool != nil {
		r.pool.Close()
	}
}

// nullable turns "" into a NULL so empty optional columns aren't stored as empty strings.
func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// Nop is the disabled recorder — the operator runs without a durable audit (logged loudly at startup).
type Nop struct{}

func (Nop) RecordGrant(context.Context, *v1alpha1.Activation) error  { return nil }
func (Nop) RecordRevoke(context.Context, *v1alpha1.Activation) error { return nil }
func (Nop) RecordRenew(context.Context, *v1alpha1.Activation, int, v1alpha1.Renewal, time.Time) error {
	return nil
}
func (Nop) Close() {}
