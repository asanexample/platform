package engine

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

// Runner executes infrastructure commands for a single unit.
// Implementations set provider-specific env vars based on unit.Provider and unit.Auth.
type Runner interface {
	Run(ctx context.Context, unit *Unit, action Action, args ...string) error
}

// RunError is returned when a terragrunt command fails.
type RunError struct {
	Unit     string
	Action   Action
	ExitCode int
	LogPath  string
	Output   string
}

func (e *RunError) Error() string {
	return fmt.Sprintf("%s %s: exit code %d", e.Action, e.Unit, e.ExitCode)
}

// SCPError wraps a RunError when a Service Control Policy blocks a destroy operation.
type SCPError struct {
	RunError
	ProtectedResources []string
}

func (e *SCPError) Error() string {
	return fmt.Sprintf("%s %s: blocked by SCP (protected: %v)", e.Action, e.Unit, e.ProtectedResources)
}

// LockError wraps a RunError when DynamoDB state lock is held by another process.
type LockError struct {
	RunError
	LockID string
}

func (e *LockError) Error() string {
	return fmt.Sprintf("%s %s: state lock held (lock ID: %s)", e.Action, e.Unit, e.LockID)
}

var (
	scpPattern  = regexp.MustCompile(`(?i)service.control.policy|service_control_policy`)
	lockPattern = regexp.MustCompile(`Lock Info:\s*ID:\s*([a-f0-9-]+)`)
)

// TerragruntRunner executes terragrunt commands as subprocesses.
type TerragruntRunner struct {
	// LogWriter receives unit output for logging. If nil, output is discarded.
	LogWriter func(unit string, data []byte)
}

// Run executes a terragrunt action (apply/destroy) for the given unit.
func (r *TerragruntRunner) Run(ctx context.Context, unit *Unit, action Action, args ...string) error {
	cmdArgs := []string{action.String(), "-auto-approve", "-input=false"}
	cmdArgs = append(cmdArgs, args...)

	cmd := exec.CommandContext(ctx, "terragrunt", cmdArgs...)
	cmd.Dir = unit.Path
	cmd.Env = r.buildEnv(unit)

	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf

	err := cmd.Run()
	output := buf.String()

	if r.LogWriter != nil {
		r.LogWriter(unit.Name, buf.Bytes())
	}

	if err == nil {
		return nil
	}

	exitCode := 1
	if exitErr, ok := err.(*exec.ExitError); ok {
		exitCode = exitErr.ExitCode()
	}

	runErr := RunError{
		Unit:     unit.Name,
		Action:   action,
		ExitCode: exitCode,
		Output:   output,
	}

	return classifyError(runErr, output)
}

// classifyError inspects terragrunt output to return a specific error type.
func classifyError(runErr RunError, output string) error {
	if scpPattern.MatchString(output) {
		resources := detectProtectedResources(output)
		return &SCPError{RunError: runErr, ProtectedResources: resources}
	}

	if matches := lockPattern.FindStringSubmatch(output); len(matches) > 1 {
		return &LockError{RunError: runErr, LockID: matches[1]}
	}

	return &runErr
}

func detectProtectedResources(output string) []string {
	protectedTypes := []string{"aws_kms_key", "aws_kms_alias", "aws_flow_log"}
	var found []string
	for _, t := range protectedTypes {
		if strings.Contains(output, t) {
			found = append(found, t)
		}
	}
	return found
}

// buildEnv constructs the environment variable list for a unit's subprocess.
func (r *TerragruntRunner) buildEnv(unit *Unit) []string {
	env := os.Environ()

	switch unit.Provider {
	case "aws":
		if profile, ok := unit.Auth["profile"]; ok {
			env = setEnv(env, "AWS_PROFILE", profile)
		}
	case "azure":
		if sub, ok := unit.Auth["subscription"]; ok {
			env = setEnv(env, "ARM_SUBSCRIPTION_ID", sub)
		}
	}

	return env
}

// setEnv replaces or appends an environment variable.
func setEnv(env []string, key, value string) []string {
	prefix := key + "="
	for i, e := range env {
		if strings.HasPrefix(e, prefix) {
			env[i] = prefix + value
			return env
		}
	}
	return append(env, prefix+value)
}

// DryRunner implements Runner but only prints what would be executed.
type DryRunner struct{}

// Run prints the command that would be executed without running it.
func (r *DryRunner) Run(_ context.Context, unit *Unit, action Action, args ...string) error {
	cmdArgs := append([]string{action.String(), "-auto-approve"}, args...)
	fmt.Printf("[dry-run] %s: terragrunt %s\n", unit.Name, strings.Join(cmdArgs, " "))
	return nil
}
