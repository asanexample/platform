package engine

import (
	"bytes"
	"context"
	"errors"
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
	// eksUpdatePattern matches EKS's "another config update in progress" conflict. EKS serializes
	// cluster-config updates (endpoint-access toggles, addon/version updates), so a concurrent update returns
	// ResourceInUseException instead of waiting — transient: the in-flight update finishes in a few minutes.
	eksUpdatePattern = regexp.MustCompile(`(?i)resourceinuseexception|currently has an update in progress`)
)

// IsTransientEKSUpdate reports whether err is the transient EKS "update in progress" conflict, which a caller
// should retry after a short backoff (e.g. the lockdown's endpoint-access change racing another cluster update).
func IsTransientEKSUpdate(err error) bool {
	var re *RunError
	if errors.As(err, &re) {
		return eksUpdatePattern.MatchString(re.Output)
	}
	return false
}

// DefaultSCPProtectedTypes are AWS resource types commonly blocked by Service Control Policies.
var DefaultSCPProtectedTypes = []string{"aws_kms_key", "aws_kms_alias", "aws_flow_log"}

// TerragruntRunner executes terragrunt commands as subprocesses.
type TerragruntRunner struct {
	// LogWriter receives unit output for logging. If nil, output is discarded.
	LogWriter func(unit string, data []byte)
	// Binary is the terragrunt executable name or path. Defaults to "terragrunt".
	Binary string
	// SCPProtectedTypes are resource types to detect in SCP errors. Defaults to DefaultSCPProtectedTypes.
	SCPProtectedTypes []string
}

func (r *TerragruntRunner) binary() string {
	if r.Binary != "" {
		return r.Binary
	}
	return "terragrunt"
}

func (r *TerragruntRunner) scpProtectedTypes() []string {
	if len(r.SCPProtectedTypes) > 0 {
		return r.SCPProtectedTypes
	}
	return DefaultSCPProtectedTypes
}

// Run executes a terragrunt action (apply/destroy) for the given unit.
func (r *TerragruntRunner) Run(ctx context.Context, unit *Unit, action Action, args ...string) error {
	cmdArgs := []string{action.String(), "-auto-approve", "-input=false"}
	cmdArgs = append(cmdArgs, args...)

	cmd := exec.CommandContext(ctx, r.binary(), cmdArgs...)
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

	return classifyError(runErr, output, r.scpProtectedTypes())
}

// classifyError inspects terragrunt output to return a specific error type.
func classifyError(runErr RunError, output string, scpTypes []string) error {
	if scpPattern.MatchString(output) {
		resources := detectProtectedResources(output, scpTypes)
		return &SCPError{RunError: runErr, ProtectedResources: resources}
	}

	if matches := lockPattern.FindStringSubmatch(output); len(matches) > 1 {
		return &LockError{RunError: runErr, LockID: matches[1]}
	}

	return &runErr
}

func detectProtectedResources(output string, protectedTypes []string) []string {
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

// EnvWithAWSProfile returns env with AWS_PROFILE set from auth["profile"] when present (replacing an
// existing entry, else appending); env is returned unchanged when no profile is set. It is the shared
// primitive for the subprocess call sites that need a unit's AWS profile applied to os.Environ(). This is
// the narrow, provider-UNGATED form — unlike buildEnv, which sets AWS_PROFILE only for Provider=="aws";
// the call sites that use this always operate on AWS units and must set the profile regardless of provider.
func EnvWithAWSProfile(env []string, auth map[string]string) []string {
	if profile, ok := auth["profile"]; ok {
		return setEnv(env, "AWS_PROFILE", profile)
	}
	return env
}

// DryRunner implements Runner but only prints what would be executed.
type DryRunner struct {
	Binary string
}

// Run prints the command that would be executed without running it.
func (r *DryRunner) Run(_ context.Context, unit *Unit, action Action, args ...string) error {
	binary := r.Binary
	if binary == "" {
		binary = "terragrunt"
	}
	cmdArgs := append([]string{action.String(), "-auto-approve"}, args...)
	fmt.Printf("[dry-run] %s: %s %s\n", unit.Name, binary, strings.Join(cmdArgs, " "))
	return nil
}
