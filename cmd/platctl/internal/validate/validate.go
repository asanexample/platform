// Package validate provides health-check types and parallel execution for platctl validate.
package validate

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"sync"
	"time"
)

// CheckResult holds the outcome of a single health check.
type CheckResult struct {
	Name    string
	Status  string // "ok", "failed", "skipped"
	Message string
	Details []string
	Elapsed time.Duration
}

// Checker runs a single health check and returns the result. CheckName is the check's stable display name
// (used for --check prefix filtering and skip messages); every concrete check already exposes it.
type Checker interface {
	Check(ctx context.Context) CheckResult
	CheckName() string
}

// CommandRunner executes an external command and returns its combined output.
type CommandRunner func(ctx context.Context, name string, args ...string) ([]byte, error)

// ExecRunner is the production CommandRunner that delegates to os/exec.
func ExecRunner(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	return cmd.CombinedOutput()
}

// RunChecks executes checks in parallel, bounded by concurrency, preserving input order.
func RunChecks(ctx context.Context, checks []Checker, concurrency int) []CheckResult {
	if concurrency < 1 {
		concurrency = 4
	}

	results := make([]CheckResult, len(checks))

	type indexed struct {
		idx    int
		result CheckResult
	}
	ch := make(chan indexed, len(checks))
	sem := make(chan struct{}, concurrency)
	var wg sync.WaitGroup

	for i, c := range checks {
		wg.Add(1)
		go func(idx int, checker Checker) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			ch <- indexed{idx: idx, result: checker.Check(ctx)}
		}(i, c)
	}

	go func() {
		wg.Wait()
		close(ch)
	}()

	for ir := range ch {
		results[ir.idx] = ir.result
	}
	return results
}

// ExpiredProfilesFn returns a list of AWS profiles whose SSO sessions have expired.
type ExpiredProfilesFn func(ctx context.Context) []string

// RunValidation executes checks in two phases: IAM checks first, then everything else.
// If any IAM check fails, remaining checks are skipped with a message indicating
// that credentials must be fixed first.
func RunValidation(ctx context.Context, iamChecks []Checker, otherChecks []Checker, concurrency int, expiredFn ExpiredProfilesFn) []CheckResult {
	// Phase 1: IAM checks
	iamResults := RunChecks(ctx, iamChecks, concurrency)

	iamFailed := false
	for _, r := range iamResults {
		if r.Status == "failed" {
			iamFailed = true
			break
		}
	}

	if iamFailed {
		// Skip all remaining checks
		skipped := make([]CheckResult, len(otherChecks))
		for i, c := range otherChecks {
			skipped[i] = CheckResult{
				Name:    c.CheckName(),
				Status:  "skipped",
				Message: "skipped (fix IAM/credentials first)",
			}
		}
		return append(iamResults, skipped...)
	}

	// Phase 2: everything else
	otherResults := RunChecks(ctx, otherChecks, concurrency)
	return append(iamResults, otherResults...)
}

// FilterCheckers returns only the checkers whose name starts with any of the
// given prefixes. If prefixes is empty, all checkers are returned.
func FilterCheckers(checks []Checker, prefixes []string) []Checker {
	if len(prefixes) == 0 {
		return checks
	}
	var filtered []Checker
	for _, c := range checks {
		name := c.CheckName()
		for _, p := range prefixes {
			if strings.HasPrefix(name, p) {
				filtered = append(filtered, c)
				break
			}
		}
	}
	return filtered
}

// PrintResults formats check results to stdout and returns counts.
func PrintResults(results []CheckResult) (passed, failed, skipped int) {
	for _, r := range results {
		switch r.Status {
		case "ok":
			passed++
			fmt.Printf("  ok %-35s %s\n", r.Name, r.Message)
		case "failed":
			failed++
			fmt.Printf("  !! %-35s %s\n", r.Name, r.Message)
			for _, d := range r.Details {
				fmt.Printf("     → %s\n", d)
			}
		case "skipped":
			skipped++
			fmt.Printf("  -- %-35s %s\n", r.Name, r.Message)
		}
	}
	return passed, failed, skipped
}
