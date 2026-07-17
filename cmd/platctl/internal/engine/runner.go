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
	"sync"
	"sync/atomic"
	"syscall"
	"time"
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

// TimeoutError wraps a RunError when a unit produced NO output for the inactivity
// window and was killed as hung. A healthy long-running apply/destroy streams
// progress (OpenTofu emits "Still destroying... Xm elapsed" every ~10s), so silence
// past the window means the process is wedged — classically a black-holed AWS SDK
// connection with no effective read timeout, which never self-recovers. It is
// retryable: a fresh attempt gets a fresh process and fresh connections.
type TimeoutError struct {
	RunError
	Inactivity time.Duration
}

func (e *TimeoutError) Error() string {
	return fmt.Sprintf("%s %s: no output for %s — killed as hung", e.Action, e.Unit, e.Inactivity)
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
	// InactivityTimeout kills the subprocess if it produces no output for this long
	// (0 = disabled, the default). A healthy apply/destroy streams progress every few
	// seconds, so silence past this window means the unit is hung (e.g. a black-holed
	// connection). The kill surfaces as a retryable TimeoutError.
	InactivityTimeout time.Duration
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

	// A derived context lets the inactivity watchdog kill the subprocess without
	// disturbing the caller's ctx.
	runCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	secretEnv, err := r.resolveSecretEnv(runCtx, unit)
	if err != nil {
		return err
	}

	cmd := exec.CommandContext(runCtx, r.binary(), cmdArgs...)
	cmd.Dir = unit.Path
	cmd.Env = append(r.buildEnv(unit), secretEnv...)
	// Run the unit in its own process group so a cancel reaches the whole tree
	// (terragrunt → OpenTofu → provider plugins), not just the wrapper — a wedged
	// child otherwise outlives the parent (e.g. a plugin blocked on a black-holed
	// connection).
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	// On cancel (watchdog kill or caller Ctrl-C), SIGTERM the group first so OpenTofu
	// shuts down gracefully — releasing its state lock and saving state — rather than the
	// default SIGKILL, which would strand the lock and fail the retry. WaitDelay force-kills
	// only if the tree hasn't exited after the grace period.
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		}
		return nil
	}
	cmd.WaitDelay = 15 * time.Second

	// activityWriter accumulates output AND signals each write to the watchdog, so
	// "no output for InactivityTimeout" can be distinguished from a slow-but-alive run.
	w := &activityWriter{activity: make(chan struct{}, 1)}
	cmd.Stdout = w
	cmd.Stderr = w

	var hung atomic.Bool
	var watchdog sync.WaitGroup
	if r.InactivityTimeout > 0 {
		watchdog.Add(1)
		go func() {
			defer watchdog.Done()
			t := time.NewTimer(r.InactivityTimeout)
			defer t.Stop()
			for {
				select {
				case <-w.activity:
					if !t.Stop() {
						<-t.C
					}
					t.Reset(r.InactivityTimeout)
				case <-t.C:
					hung.Store(true)
					cancel() // kill the wedged subprocess
					return
				case <-runCtx.Done():
					return
				}
			}
		}()
	}

	err = cmd.Run()
	cancel()        // stop the watchdog if the command finished on its own
	watchdog.Wait() // ensure the watchdog goroutine has exited before reading state
	output := w.String()

	if r.LogWriter != nil {
		r.LogWriter(unit.Name, []byte(output))
	}

	if err == nil {
		return nil
	}

	exitCode := 1
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		exitCode = exitErr.ExitCode()
	}

	runErr := RunError{
		Unit:     unit.Name,
		Action:   action,
		ExitCode: exitCode,
		Output:   output,
	}

	// A watchdog kill (no output for the window) is distinct from a real exit error:
	// surface it as a retryable TimeoutError. Guard on ctx.Err() so a caller-initiated
	// cancel (Ctrl-C) isn't mislabelled as a hang.
	if hung.Load() && ctx.Err() == nil {
		return &TimeoutError{RunError: runErr, Inactivity: r.InactivityTimeout}
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

// parseSecretSpec splits an env_from_secret value "<secret-id>[@<profile>]" into the secret
// id and the AWS profile to read it with. An absent @profile falls back to defaultProfile
// (the unit's own). Split on the LAST '@' so secret ids containing '@' are tolerated.
func parseSecretSpec(spec, defaultProfile string) (secretID, profile string) {
	secretID, profile = spec, defaultProfile
	if i := strings.LastIndex(spec, "@"); i >= 0 {
		secretID, profile = spec[:i], spec[i+1:]
	}
	return secretID, profile
}

// resolveSecretEnv fetches each of unit.EnvFromSecret from Secrets Manager and returns
// KEY=VALUE env entries for the subprocess. The secret VALUE is never logged; a fetch failure
// aborts the unit (it can't run without its credential). us-east-1 matches every secret here.
func (r *TerragruntRunner) resolveSecretEnv(ctx context.Context, unit *Unit) ([]string, error) {
	if len(unit.EnvFromSecret) == 0 {
		return nil, nil
	}
	out := make([]string, 0, len(unit.EnvFromSecret))
	for envVar, spec := range unit.EnvFromSecret {
		secretID, profile := parseSecretSpec(spec, unit.Auth["profile"])
		args := []string{"secretsmanager", "get-secret-value", "--secret-id", secretID,
			"--query", "SecretString", "--output", "text", "--region", "us-east-1"}
		if profile != "" {
			args = append(args, "--profile", profile)
		}
		cmd := exec.CommandContext(ctx, "aws", args...)
		cmd.Env = os.Environ()
		val, err := cmd.Output()
		if err != nil {
			return nil, fmt.Errorf("resolving env_from_secret %s for %s from %q: %w", envVar, unit.Name, secretID, err)
		}
		out = append(out, envVar+"="+strings.TrimRight(string(val), "\n"))
	}
	return out, nil
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

// activityWriter accumulates subprocess output and signals each write on the activity
// channel, so an inactivity watchdog can distinguish a wedged process from a slow one.
// It is safe for concurrent use: exec pumps stdout and stderr from separate goroutines.
type activityWriter struct {
	mu       sync.Mutex
	buf      bytes.Buffer
	activity chan struct{} // buffered (cap 1); nil disables signalling
}

func (w *activityWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	n, err := w.buf.Write(p)
	w.mu.Unlock()
	if w.activity != nil {
		select {
		case w.activity <- struct{}{}:
		default: // a pending tick is enough; never block the subprocess pump
		}
	}
	return n, err
}

func (w *activityWriter) String() string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.String()
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
