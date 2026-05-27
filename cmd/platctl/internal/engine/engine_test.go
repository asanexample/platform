package engine

import (
	"context"
	"sync"
	"testing"
	"time"
)

// mockRunner records which units were executed and in what order.
type mockRunner struct {
	mu       sync.Mutex
	executed []string
	failOn   map[string]error
	delay    time.Duration
}

func newMockRunner() *mockRunner {
	return &mockRunner{failOn: make(map[string]error)}
}

func (m *mockRunner) Run(_ context.Context, unit *Unit, action Action, args ...string) error {
	if m.delay > 0 {
		time.Sleep(m.delay)
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.executed = append(m.executed, unit.Name)
	if err, ok := m.failOn[unit.Name]; ok {
		return err
	}
	return nil
}

func (m *mockRunner) executedNames() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	result := make([]string, len(m.executed))
	copy(result, m.executed)
	return result
}

// mockStore records saves without touching disk.
type mockStore struct {
	mu    sync.Mutex
	saved []*State
}

func (m *mockStore) Load(_ string) (*State, error) {
	return nil, nil
}

func (m *mockStore) Save(_ string, state *State) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.saved = append(m.saved, state)
	return nil
}

func TestEngine_LinearChain(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", Path: "/tmp/a"},
		{Name: "b", Env: "test", Path: "/tmp/b", DependsOn: []string{"a"}},
		{Name: "c", Env: "test", Path: "/tmp/c", DependsOn: []string{"b"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatal(err)
	}

	runner := newMockRunner()
	store := &mockStore{}
	eng := NewEngine(runner, store, g, "state.json", WithConcurrency(1))

	if err := eng.Run(context.Background(), Apply, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	executed := runner.executedNames()
	if len(executed) != 3 {
		t.Fatalf("expected 3 executions, got %d: %v", len(executed), executed)
	}

	// Verify strict ordering
	assertExecutionOrder(t, executed, "a", "b")
	assertExecutionOrder(t, executed, "b", "c")
}

func TestEngine_ParallelExecution(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", Path: "/tmp/a"},
		{Name: "b", Env: "test", Path: "/tmp/b"},
		{Name: "c", Env: "test", Path: "/tmp/c", DependsOn: []string{"a", "b"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatal(err)
	}

	runner := newMockRunner()
	runner.delay = 10 * time.Millisecond
	store := &mockStore{}
	eng := NewEngine(runner, store, g, "state.json", WithConcurrency(4))

	start := time.Now()
	if err := eng.Run(context.Background(), Apply, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	elapsed := time.Since(start)

	executed := runner.executedNames()
	if len(executed) != 3 {
		t.Fatalf("expected 3 executions, got %d", len(executed))
	}

	// a and b should run in parallel (~10ms), then c (~10ms) = ~20ms total
	// If sequential, it would be ~30ms
	if elapsed > 50*time.Millisecond {
		t.Logf("warning: execution took %v (expected ~20ms for parallel)", elapsed)
	}
}

func TestEngine_FailureSkipsDependents(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", Path: "/tmp/a"},
		{Name: "b", Env: "test", Path: "/tmp/b", DependsOn: []string{"a"}},
		{Name: "c", Env: "test", Path: "/tmp/c", DependsOn: []string{"b"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatal(err)
	}

	runner := newMockRunner()
	runner.failOn["a"] = &RunError{Unit: "a", Action: Apply, ExitCode: 1}
	store := &mockStore{}
	eng := NewEngine(runner, store, g, "state.json")

	err = eng.Run(context.Background(), Apply, nil)
	if err == nil {
		t.Fatal("expected error")
	}

	if eng.State.Units["a"].Status != StatusFailed {
		t.Fatalf("expected a to be failed, got %s", eng.State.Units["a"].Status)
	}
	if eng.State.Units["b"].Status != StatusSkipped {
		t.Fatalf("expected b to be skipped, got %s", eng.State.Units["b"].Status)
	}
	if eng.State.Units["c"].Status != StatusSkipped {
		t.Fatalf("expected c to be skipped, got %s", eng.State.Units["c"].Status)
	}
}

func TestEngine_FailureContinuesIndependentWork(t *testing.T) {
	// a fails, but d is independent and should still run; b/c depend on a and should be skipped
	units := []*Unit{
		{Name: "a", Env: "test", Path: "/tmp/a"},
		{Name: "b", Env: "test", Path: "/tmp/b", DependsOn: []string{"a"}},
		{Name: "c", Env: "test", Path: "/tmp/c", DependsOn: []string{"b"}},
		{Name: "d", Env: "test", Path: "/tmp/d"},
		{Name: "e", Env: "test", Path: "/tmp/e", DependsOn: []string{"d"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatal(err)
	}

	runner := newMockRunner()
	runner.failOn["a"] = &RunError{Unit: "a", Action: Apply, ExitCode: 1}
	store := &mockStore{}
	eng := NewEngine(runner, store, g, "state.json")

	err = eng.Run(context.Background(), Apply, nil)
	if err == nil {
		t.Fatal("expected error")
	}

	if eng.State.Units["a"].Status != StatusFailed {
		t.Fatalf("expected a=failed, got %s", eng.State.Units["a"].Status)
	}
	if eng.State.Units["b"].Status != StatusSkipped {
		t.Fatalf("expected b=skipped, got %s", eng.State.Units["b"].Status)
	}
	if eng.State.Units["c"].Status != StatusSkipped {
		t.Fatalf("expected c=skipped, got %s", eng.State.Units["c"].Status)
	}
	if eng.State.Units["d"].Status != StatusCompleted {
		t.Fatalf("expected d=completed, got %s", eng.State.Units["d"].Status)
	}
	if eng.State.Units["e"].Status != StatusCompleted {
		t.Fatalf("expected e=completed, got %s", eng.State.Units["e"].Status)
	}
}

func TestEngine_Resume(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", Path: "/tmp/a"},
		{Name: "b", Env: "test", Path: "/tmp/b", DependsOn: []string{"a"}},
		{Name: "c", Env: "test", Path: "/tmp/c", DependsOn: []string{"b"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatal(err)
	}

	// Simulate: a completed, b and c pending (resume scenario)
	state := NewState("bootstrap", units)
	state.MarkCompleted("a")

	runner := newMockRunner()
	store := &mockStore{}
	eng := NewEngine(runner, store, g, "state.json")
	eng.State = state

	if err := eng.Run(context.Background(), Apply, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	executed := runner.executedNames()
	// a should NOT be re-executed
	for _, name := range executed {
		if name == "a" {
			t.Fatal("completed unit 'a' should not be re-executed")
		}
	}
	if len(executed) != 2 {
		t.Fatalf("expected 2 executions (b, c), got %d: %v", len(executed), executed)
	}
}

func TestEngine_UnitArgs(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", Path: "/tmp/a"},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatal(err)
	}

	// Use a runner that captures args
	var capturedArgs []string
	runner := &argCaptureRunner{onRun: func(_ *Unit, _ Action, args ...string) {
		capturedArgs = args
	}}
	store := &mockStore{}
	eng := NewEngine(runner, store, g, "state.json")

	unitArgs := map[string][]string{
		"a": {"-var", "endpoint_public_access=true"},
	}
	if err := eng.Run(context.Background(), Apply, unitArgs); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(capturedArgs) != 2 || capturedArgs[0] != "-var" {
		t.Fatalf("expected args [-var endpoint_public_access=true], got %v", capturedArgs)
	}
}

func TestEngine_DestroyReversesGraph(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", Path: "/tmp/a"},
		{Name: "b", Env: "test", Path: "/tmp/b", DependsOn: []string{"a"}},
		{Name: "c", Env: "test", Path: "/tmp/c", DependsOn: []string{"b"}},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatal(err)
	}

	runner := newMockRunner()
	store := &mockStore{}
	eng := NewEngine(runner, store, g, "state.json", WithConcurrency(1))

	if err := eng.Run(context.Background(), Destroy, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	executed := runner.executedNames()
	// Destroy order should be reversed: c, b, a
	assertExecutionOrder(t, executed, "c", "b")
	assertExecutionOrder(t, executed, "b", "a")
}

func TestEngine_AllCompleted(t *testing.T) {
	units := []*Unit{
		{Name: "a", Env: "test", Path: "/tmp/a"},
	}
	g, err := NewGraph(units)
	if err != nil {
		t.Fatal(err)
	}

	state := NewState("bootstrap", units)
	state.MarkCompleted("a")

	runner := newMockRunner()
	store := &mockStore{}
	eng := NewEngine(runner, store, g, "state.json")
	eng.State = state

	if err := eng.Run(context.Background(), Apply, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(runner.executedNames()) != 0 {
		t.Fatal("no units should be executed when all are complete")
	}
}

type argCaptureRunner struct {
	onRun func(*Unit, Action, ...string)
}

func (r *argCaptureRunner) Run(_ context.Context, unit *Unit, action Action, args ...string) error {
	if r.onRun != nil {
		r.onRun(unit, action, args...)
	}
	return nil
}

func assertExecutionOrder(t *testing.T, executed []string, before, after string) {
	t.Helper()
	beforeIdx, afterIdx := -1, -1
	for i, name := range executed {
		if name == before {
			beforeIdx = i
		}
		if name == after {
			afterIdx = i
		}
	}
	if beforeIdx == -1 {
		t.Fatalf("%q not found in execution list: %v", before, executed)
	}
	if afterIdx == -1 {
		t.Fatalf("%q not found in execution list: %v", after, executed)
	}
	if beforeIdx >= afterIdx {
		t.Errorf("expected %q before %q in execution list: %v", before, after, executed)
	}
}

