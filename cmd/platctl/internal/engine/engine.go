package engine

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"sync"
)

// Engine orchestrates the execution of Terragrunt units in dependency order.
type Engine struct {
	Runner      Runner
	Store       Store
	Graph       *Graph
	State       *State
	StatePath   string
	Concurrency int
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

	g := e.Graph
	if action == Destroy {
		var err error
		g, err = g.Reverse()
		if err != nil {
			return fmt.Errorf("reversing graph for teardown: %w", err)
		}
	}

	// Build dependency tracking
	inDegree := make(map[string]int)
	dependents := make(map[string][]string)
	for _, u := range g.Units() {
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

	// Execution loop: dispatch ready units, wait for completions, enqueue newly ready
	sem := make(chan struct{}, e.Concurrency)
	results := make(chan unitResult, len(g.Units()))
	var wg sync.WaitGroup
	running := 0
	failed := false

	// startUnit launches a unit in a goroutine, respecting the concurrency semaphore.
	startUnit := func(name string) {
		unit := g.Unit(name)
		if unit == nil {
			return
		}
		var args []string
		if unitArgs != nil {
			args = unitArgs[name]
		}

		e.State.MarkRunning(name)
		e.saveState()

		wg.Add(1)
		running++
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			err := e.Runner.Run(ctx, unit, action, args...)
			results <- unitResult{Name: name, Err: err}
		}()
	}

	// Seed initial ready units
	for _, name := range ready {
		if failed {
			break
		}
		startUnit(name)
	}

	// Process results until nothing is running and nothing is ready
	for running > 0 {
		res := <-results
		running--

		if res.Err != nil {
			e.State.MarkFailed(res.Name, res.Err.Error())
			e.saveState()
			failed = true

			// Mark all transitive dependents as skipped
			for _, s := range e.Graph.Dependents(res.Name) {
				e.State.MarkSkipped(s)
			}
			e.saveState()
			continue
		}

		e.State.MarkCompleted(res.Name)
		e.saveState()

		if failed {
			continue
		}

		// Enqueue newly ready dependents
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
		for _, name := range newReady {
			startUnit(name)
		}
	}

	// Wait for any stragglers (shouldn't be any, but be safe)
	wg.Wait()

	if failed {
		return e.buildFailureError()
	}
	return nil
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
