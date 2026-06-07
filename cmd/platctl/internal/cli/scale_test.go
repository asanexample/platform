package cli

import (
	"testing"

	"github.com/gangster/platform/cmd/platctl/internal/config"
)

func TestKubeconfigForEnv(t *testing.T) {
	cfg := &config.Config{
		Kubeconfig: []config.KubeconfigEntry{
			{Alias: "platform", Cluster: "platform-use1-eks", Region: "us-east-1", Profile: "platform"},
			{Alias: "preprod", Cluster: "preprod-use1-eks", Region: "us-east-1", Profile: "preprod"},
		},
	}

	got, err := kubeconfigForEnv(cfg, "preprod")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Cluster != "preprod-use1-eks" || got.Profile != "preprod" {
		t.Errorf("got %+v, want preprod-use1-eks/preprod", got)
	}

	if _, err := kubeconfigForEnv(cfg, "does-not-exist"); err == nil {
		t.Error("expected an error for an unknown env, got nil")
	}
}
