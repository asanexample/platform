package engine

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

// writeScript writes an executable shell script and returns its path. The
// TerragruntRunner invokes it as `<script> <action> -auto-approve -input=false`;
// the scripts here ignore those args.
func writeScript(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "fake.sh")
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestInactivityTimeoutKillsHungUnit(t *testing.T) {
	// No output, sleeps well past the inactivity window — the wedged-process case.
	script := writeScript(t, "#!/bin/sh\nsleep 30\n")
	r := &TerragruntRunner{Binary: script, InactivityTimeout: 150 * time.Millisecond}
	unit := &Unit{Name: "hang", Path: filepath.Dir(script)}

	start := time.Now()
	err := r.Run(context.Background(), unit, Destroy)
	elapsed := time.Since(start)

	var to *TimeoutError
	if !errors.As(err, &to) {
		t.Fatalf("expected TimeoutError for a silent hung unit, got %v", err)
	}
	if elapsed > 5*time.Second {
		t.Fatalf("watchdog was too slow to kill the hung unit: %s", elapsed)
	}
	if !isRetryable(err) {
		t.Fatal("a TimeoutError must be retryable")
	}
}

func TestInactivityTimeoutAllowsActiveUnit(t *testing.T) {
	// Emits output every ~100ms for ~500ms then exits 0. The 3s window gives a wide
	// margin (~30× the output interval) so the watchdog never trips even when the -race
	// detector saturates the CPU and the shell's sleep/echo stalls.
	script := writeScript(t, "#!/bin/sh\ni=0\nwhile [ $i -lt 5 ]; do echo tick; sleep 0.1; i=$((i+1)); done\n")
	r := &TerragruntRunner{Binary: script, InactivityTimeout: 3 * time.Second}
	unit := &Unit{Name: "active", Path: filepath.Dir(script)}

	if err := r.Run(context.Background(), unit, Apply); err != nil {
		t.Fatalf("a unit that streams output should succeed, got %v", err)
	}
}

func TestIsRetryable(t *testing.T) {
	runErr := func(out string) error { return &RunError{Unit: "u", Action: Destroy, Output: out} }
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"inactivity timeout", &TimeoutError{RunError: RunError{Unit: "u"}}, true},
		{"state lock", &LockError{RunError: RunError{Unit: "u"}, LockID: "abc"}, true},
		{"scp protected — never retry", &SCPError{RunError: RunError{Unit: "u"}}, false},
		{"plugin client glitch", runErr("Error: Cannot obtain plugin client"), true},
		{"codeartifact upstream race", runErr("ConflictException: being used as an upstream repository"), true},
		{"vpc dependency violation", runErr("DependencyViolation: resource has a dependent object"), true},
		{"throttling", runErr("ThrottlingException: Rate exceeded"), true},
		{"bucket not empty — deterministic", runErr("BucketNotEmpty: The bucket you tried to delete is not empty"), false},
		{"plain permanent error", runErr("Error: invalid value for some argument"), false},
	}
	for _, c := range cases {
		if got := isRetryable(c.err); got != c.want {
			t.Errorf("%s: isRetryable = %v, want %v", c.name, got, c.want)
		}
	}
}

// flakyRunner fails its first failUntil calls with err, then succeeds.
type flakyRunner struct {
	mu        sync.Mutex
	calls     int
	failUntil int
	err       error
}

func (r *flakyRunner) Run(_ context.Context, _ *Unit, _ Action, _ ...string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls++
	if r.calls <= r.failUntil {
		return r.err
	}
	return nil
}

func (r *flakyRunner) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.calls
}

func TestRunUnitRetriesTransientThenSucceeds(t *testing.T) {
	fr := &flakyRunner{failUntil: 2, err: &TimeoutError{RunError: RunError{Unit: "u"}}}
	e := &Engine{Runner: fr, MaxRetries: 2, RetryBackoff: time.Millisecond}

	if err := e.runUnit(context.Background(), &Unit{Name: "u"}, Destroy); err != nil {
		t.Fatalf("expected success after retries, got %v", err)
	}
	if got := fr.count(); got != 3 {
		t.Fatalf("expected 3 attempts (2 fail + 1 success), got %d", got)
	}
}

func TestRunUnitExhaustsRetries(t *testing.T) {
	fr := &flakyRunner{failUntil: 99, err: &TimeoutError{RunError: RunError{Unit: "u"}}}
	e := &Engine{Runner: fr, MaxRetries: 2, RetryBackoff: time.Millisecond}

	if err := e.runUnit(context.Background(), &Unit{Name: "u"}, Destroy); err == nil {
		t.Fatal("expected failure after exhausting retries")
	}
	if got := fr.count(); got != 3 {
		t.Fatalf("expected 3 attempts (1 + 2 retries), got %d", got)
	}
}

func TestRunUnitDoesNotRetryDeterministic(t *testing.T) {
	fr := &flakyRunner{failUntil: 99, err: &RunError{Unit: "u", Output: "BucketNotEmpty"}}
	e := &Engine{Runner: fr, MaxRetries: 3, RetryBackoff: time.Millisecond}

	if err := e.runUnit(context.Background(), &Unit{Name: "u"}, Destroy); err == nil {
		t.Fatal("expected failure")
	}
	if got := fr.count(); got != 1 {
		t.Fatalf("a deterministic error must not be retried, got %d attempts", got)
	}
}

func TestRunUnitStopsRetryingOnContextCancel(t *testing.T) {
	fr := &flakyRunner{failUntil: 99, err: &TimeoutError{RunError: RunError{Unit: "u"}}}
	e := &Engine{Runner: fr, MaxRetries: 5, RetryBackoff: time.Hour} // long backoff we must not wait on

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // already cancelled

	if err := e.runUnit(ctx, &Unit{Name: "u"}, Destroy); err == nil {
		t.Fatal("expected failure")
	}
	if got := fr.count(); got != 1 {
		t.Fatalf("a cancelled context must stop retries after the first attempt, got %d", got)
	}
}
