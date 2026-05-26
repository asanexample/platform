package engine

import (
	"testing"
)

func TestClassifyError_SCP(t *testing.T) {
	runErr := RunError{Unit: "platform/networking", Action: Destroy, ExitCode: 1}
	output := `Error: deleting aws_flow_log (fl-abc123): operation error EC2: DeleteFlowLogs, https response error StatusCode: 403, api error AccessDeniedException: Service.control.policy blocked this action`

	err := classifyError(runErr, output)
	scpErr, ok := err.(*SCPError)
	if !ok {
		t.Fatalf("expected SCPError, got %T", err)
	}
	if len(scpErr.ProtectedResources) == 0 {
		t.Fatal("expected protected resources to be detected")
	}
	found := false
	for _, r := range scpErr.ProtectedResources {
		if r == "aws_flow_log" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected aws_flow_log in protected resources, got %v", scpErr.ProtectedResources)
	}
}

func TestClassifyError_Lock(t *testing.T) {
	runErr := RunError{Unit: "platform/eks", Action: Apply, ExitCode: 1}
	output := `Error acquiring the state lock

Lock Info:
  ID:        a1b2c3d4-e5f6-7890-abcd-ef1234567890
  Path:      terraform.tfstate
  Operation: OperationTypeApply`

	err := classifyError(runErr, output)
	lockErr, ok := err.(*LockError)
	if !ok {
		t.Fatalf("expected LockError, got %T", err)
	}
	if lockErr.LockID != "a1b2c3d4-e5f6-7890-abcd-ef1234567890" {
		t.Fatalf("expected lock ID extraction, got %q", lockErr.LockID)
	}
}

func TestClassifyError_Generic(t *testing.T) {
	runErr := RunError{Unit: "platform/eks", Action: Apply, ExitCode: 1}
	output := `Error: creating EKS Cluster: operation error EKS: CreateCluster, some random error`

	err := classifyError(runErr, output)
	_, ok := err.(*RunError)
	if !ok {
		t.Fatalf("expected RunError, got %T", err)
	}
}

func TestSetEnv_Replace(t *testing.T) {
	env := []string{"HOME=/home/user", "AWS_PROFILE=old", "PATH=/usr/bin"}
	result := setEnv(env, "AWS_PROFILE", "new")

	found := false
	for _, e := range result {
		if e == "AWS_PROFILE=new" {
			found = true
		}
		if e == "AWS_PROFILE=old" {
			t.Fatal("old value should be replaced")
		}
	}
	if !found {
		t.Fatal("AWS_PROFILE=new not found")
	}
}

func TestSetEnv_Append(t *testing.T) {
	env := []string{"HOME=/home/user"}
	result := setEnv(env, "AWS_PROFILE", "test")

	if len(result) != 2 {
		t.Fatalf("expected 2 env vars, got %d", len(result))
	}
	if result[1] != "AWS_PROFILE=test" {
		t.Fatalf("expected AWS_PROFILE=test, got %s", result[1])
	}
}

func TestBuildEnv_AWS(t *testing.T) {
	runner := &TerragruntRunner{}
	unit := &Unit{
		Name:     "platform/eks",
		Provider: "aws",
		Auth:     map[string]string{"profile": "management"},
	}

	env := runner.buildEnv(unit)
	found := false
	for _, e := range env {
		if e == "AWS_PROFILE=management" {
			found = true
		}
	}
	if !found {
		t.Fatal("expected AWS_PROFILE=management in env")
	}
}

func TestBuildEnv_Azure(t *testing.T) {
	runner := &TerragruntRunner{}
	unit := &Unit{
		Name:     "azure/networking",
		Provider: "azure",
		Auth:     map[string]string{"subscription": "abc-123"},
	}

	env := runner.buildEnv(unit)
	found := false
	for _, e := range env {
		if e == "ARM_SUBSCRIPTION_ID=abc-123" {
			found = true
		}
	}
	if !found {
		t.Fatal("expected ARM_SUBSCRIPTION_ID=abc-123 in env")
	}
}
