package engine

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"sync"
	"time"
)

// DefaultRetryBackoff is the base delay before retrying a transiently-failed unit;
// it scales linearly with the attempt number.
const DefaultRetryBackoff = 15 * time.Second

// DefaultInactivityTimeout is how long a unit may produce NO output before the runner's
// watchdog kills it as hung. A healthy apply/destroy streams progress every few seconds
// (OpenTofu prints "Still destroying... Xm elapsed" every ~10s), so this generous window
// only trips on a genuinely wedged process, never a slow-but-alive one.
const DefaultInactivityTimeout = 8 * time.Minute

// DefaultMaxRetries is how many times a transiently-failed unit is retried by default.
const DefaultMaxRetries = 2

// retryablePattern matches transient apply/destroy failures that a fresh attempt
// typically clears: provider-plugin startup glitches, dropped connections, throttling,
// deletion-ordering races (a resource momentarily still referenced by a dependent another
// wave is concurrently removing — e.g. CodeArtifact "being used as an upstream", or a VPC
// DependencyViolation while an ENI finishes detaching), and Kyverno-webhook races during
// teardown (a failurePolicy:Fail webhook whose pods are already gone blocks admission-gated
// deletes and helm uninstalls until its config is removed a moment later — this hit karpenter,
// kube-bench, and cilium). Deterministic failures (BucketNotEmpty, SCP-protected) are
// deliberately absent — retrying them wastes time.
var retryablePattern = regexp.MustCompile(`(?i)cannot obtain plugin client|plugin.*(crashed|exited|did not respond)|connection reset|connection refused|broken pipe|i/o timeout|no such host|unexpected EOF|TLS handshake timeout|throttl|TooManyRequests|RequestLimitExceeded|ConflictException|being used as an upstream|DependencyViolation|ResourceInUseException|no endpoints available for service|failed calling webhook|error uninstalling release|failed to delete release`)

// Hook defines a pre-apply or multi-stage operation for a unit.
// Hooks are responsible for calling the runner — the engine delegates entirely to them.
// The args parameter carries bootstrap_args from the config so hooks can forward them.
type Hook interface {
	Execute(ctx context.Context, runner Runner, unit *Unit, action Action, args ...string) error
}

// Engine orchestrates the execution of Terragrunt units in dependency order.
type Engine struct {
	Runner      Runner
	Store       Store
	Graph       *Graph
	State       *State
	StatePath   string
	Concurrency int
	Hooks       map[string]Hook // unit name → hook (optional)
	Logger      *Logger         // disk logger (optional)

	// MaxRetries is how many times a transiently-failed unit is retried before it is
	// marked failed (0 = no retries). RetryBackoff is the base inter-attempt delay,
	// scaled by attempt number.
	MaxRetries   int
	RetryBackoff time.Duration
}

// EngineOption configures the engine.
type EngineOption func(*Engine)

// WithConcurrency sets the maximum number of parallel unit executions.
func WithConcurrency(n int) EngineOption {
	return func(e *Engine) {
		if n > 0 {
			e.Concurrency = n
		}
	}
}

// WithRetry enables retrying transiently-failed units up to maxRetries times with the
// given base backoff (linear in the attempt number). A non-positive backoff falls back
// to DefaultRetryBackoff.
func WithRetry(maxRetries int, backoff time.Duration) EngineOption {
	return func(e *Engine) {
		if maxRetries > 0 {
			e.MaxRetries = maxRetries
		}
		if backoff > 0 {
			e.RetryBackoff = backoff
		}
	}
}

// NewEngine creates a configured engine.
func NewEngine(runner Runner, store Store, graph *Graph, statePath string, opts ...EngineOption) *Engine {
	e := &Engine{
		Runner:      runner,
		Store:       store,
		Graph:       graph,
		StatePath:   statePath,
		Concurrency: 4,
	}
	for _, opt := range opts {
		opt(e)
	}
	return e
}

// unitResult carries the outcome of a unit execution back to the main loop.
type unitResult struct {
	Name string
	Err  error
}

// Run executes units in topological order with parallel execution of independent units.
// Uses an in-degree counting approach: when a unit completes, its dependents' in-degrees
// are decremented, and any that reach zero are started immediately (up to concurrency limit).
func (e *Engine) Run(ctx context.Context, action Action, unitArgs map[string][]string) error {
	if e.State == nil {
		units := e.Graph.Units()
		e.State = NewState(action.String(), units)
	}

	// walkGraph is the graph used for traversal: original for apply, reversed for destroy.
	// dependGraph is used to compute which units to skip on failure: it must match the walk
	// direction so that transitive dependents (in the walk's sense) are correctly identified.
	walkGraph := e.Graph
	if action == Destroy {
		var err error
		walkGraph, err = walkGraph.Reverse()
		if err != nil {
			return fmt.Errorf("reversing graph for teardown: %w", err)
		}
	}

	// Build dependency tracking from the walk graph
	inDegree := make(map[string]int)
	dependents := make(map[string][]string)
	for _, u := range walkGraph.Units() {
		inDegree[u.Name] = len(u.DependsOn)
		for _, dep := range u.DependsOn {
			dependents[dep] = append(dependents[dep], u.Name)
		}
	}

	// Adjust in-degrees for already-completed units (resume scenario)
	for name, us := range e.State.Units {
		if us.Status == StatusCompleted {
			for _, dep := range dependents[name] {
				inDegree[dep]--
			}
		}
	}

	// Find initially ready units
	var ready []string
	for name, deg := range inDegree {
		us := e.State.Units[name]
		if us != nil && us.Status != StatusCompleted && deg <= 0 {
			ready = append(ready, name)
		}
	}
	sort.Strings(ready)

	// Nothing to do?
	pendingCount := 0
	for _, us := range e.State.Units {
		if us.Status != StatusCompleted {
			pendingCount++
		}
	}
	if pendingCount == 0 {
		fmt.Println("Nothing to do — all units already completed.")
		return nil
	}

	// Execution loop: dispatch ready units, wait for completions, enqueue newly ready.
	// A failure in one unit only skips its transitive dependents — independent work continues.
	sem := make(chan struct{}, e.Concurrency)
	results := make(chan unitResult, len(walkGraph.Units()))
	var wg sync.WaitGroup
	running := 0

	startUnit := func(name string) {
		unit := walkGraph.Unit(name)
		if unit == nil {
			return
		}
		var args []string
		if unitArgs != nil {
			args = unitArgs[name]
		}

		if e.Logger != nil {
			e.Logger.IncrementWave(name)
			profile := ""
			if p, ok := unit.Auth["profile"]; ok {
				profile = p
			}
			_ = e.Logger.WriteHeader(name, "terragrunt "+action.String(), profile, unit.Path)
		}

		e.State.MarkRunning(name)
		e.saveState()

		wg.Add(1)
		running++
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			err := e.runUnit(ctx, unit, action, args...)
			results <- unitResult{Name: name, Err: err}
		}()
	}

	if e.Logger != nil && len(ready) > 0 {
		e.Logger.AssignWave(ready)
	}
	for _, name := range ready {
		startUnit(name)
	}

	for running > 0 {
		res := <-results
		running--

		if res.Err != nil {
			e.State.MarkFailed(res.Name, res.Err.Error())
			e.saveState()

			for _, s := range walkGraph.Dependents(res.Name) {
				us := e.State.Units[s]
				if us != nil && us.Status == StatusPending {
					e.State.MarkSkipped(s)
				}
			}
			e.saveState()
		} else {
			e.State.MarkCompleted(res.Name)
			e.saveState()
		}

		// Enqueue newly ready dependents (skipped units are filtered out by status check)
		var newReady []string
		for _, dep := range dependents[res.Name] {
			inDegree[dep]--
			if inDegree[dep] <= 0 {
				us := e.State.Units[dep]
				if us != nil && us.Status == StatusPending {
					newReady = append(newReady, dep)
				}
			}
		}
		sort.Strings(newReady)
		if e.Logger != nil && len(newReady) > 1 {
			e.Logger.AssignWave(newReady)
		}
		for _, name := range newReady {
			startUnit(name)
		}
	}

	wg.Wait()

	if e.State.HasFailures() {
		return e.buildFailureError()
	}
	return nil
}

// runUnit executes a unit (via its hook, or the runner directly) and retries on
// transient failure — a hang killed by the runner's inactivity watchdog, a held state
// lock, or a deletion-ordering race — up to MaxRetries times with a linear backoff.
// Deterministic failures (SCP-protected, BucketNotEmpty, etc.) are not retried, and a
// caller-cancelled context (Ctrl-C) stops retrying immediately.
func (e *Engine) runUnit(ctx context.Context, unit *Unit, action Action, args ...string) error {
	attempts := max(e.MaxRetries+1, 1)
	backoffBase := e.RetryBackoff
	if backoffBase <= 0 {
		backoffBase = DefaultRetryBackoff
	}

	run := func() error {
		if hook, ok := e.Hooks[unit.Name]; ok {
			return hook.Execute(ctx, e.Runner, unit, action, args...)
		}
		return e.Runner.Run(ctx, unit, action, args...)
	}

	var err error
	for attempt := 1; attempt <= attempts; attempt++ {
		err = run()
		if err == nil {
			return nil
		}
		if ctx.Err() != nil { // caller cancelled — do not retry
			return err
		}
		if attempt >= attempts || !isRetryable(err) {
			return err
		}
		backoff := backoffBase * time.Duration(attempt)
		msg := fmt.Sprintf("  retrying %s after transient failure (attempt %d/%d, backoff %s): %v",
			unit.Name, attempt+1, attempts, backoff, err)
		fmt.Println(msg)
		if e.Logger != nil {
			_ = e.Logger.Append(unit.Name, []byte("\n"+msg+"\n"))
		}
		select {
		case <-time.After(backoff):
		case <-ctx.Done():
			return err
		}
	}
	return err
}

// isRetryable reports whether a unit failure is worth another attempt. It retries a
// watchdog-killed hang (fresh process → fresh connections), a held state lock, the
// transient EKS "update in progress" conflict, and output matching retryablePattern.
// It never retries an SCP-protected block.
func isRetryable(err error) bool {
	if err == nil {
		return false
	}
	var scp *SCPError
	if errors.As(err, &scp) {
		return false
	}
	var to *TimeoutError
	if errors.As(err, &to) {
		return true
	}
	var le *LockError
	if errors.As(err, &le) {
		return true
	}
	if IsTransientEKSUpdate(err) {
		return true
	}
	var re *RunError
	if errors.As(err, &re) && retryablePattern.MatchString(re.Output) {
		return true
	}
	return false
}

func (e *Engine) saveState() {
	if e.Store != nil && e.StatePath != "" {
		_ = e.Store.Save(e.StatePath, e.State)
	}
}

func (e *Engine) buildFailureError() error {
	var failedUnits []string
	var skippedUnits []string
	for name, us := range e.State.Units {
		switch us.Status {
		case StatusFailed:
			failedUnits = append(failedUnits, name)
		case StatusSkipped:
			skippedUnits = append(skippedUnits, name)
		}
	}
	sort.Strings(failedUnits)
	sort.Strings(skippedUnits)

	msg := fmt.Sprintf("failed units: %v", failedUnits)
	if len(skippedUnits) > 0 {
		msg += fmt.Sprintf("; skipped dependents: %v", skippedUnits)
	}
	return errors.New(msg)
}
