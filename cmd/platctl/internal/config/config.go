// Package config handles .platctl.yaml parsing and Terragrunt unit auto-discovery.
package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Config represents the parsed .platctl.yaml file.
type Config struct {
	Environments map[string]EnvConfig    `yaml:"environments"`
	Overrides    map[string]UnitOverride `yaml:"overrides"`
	ManualSteps  []ManualStep            `yaml:"manual_steps"`
	Lockdown     []LockdownStep          `yaml:"lockdown"`
	Kubeconfig   []KubeconfigEntry       `yaml:"kubeconfig"`
}

// KubeconfigEntry defines how to configure kubectl access for a cluster.
type KubeconfigEntry struct {
	Alias          string `yaml:"alias"`
	Cluster        string `yaml:"cluster"`
	Region         string `yaml:"region"`
	Profile        string `yaml:"profile"`
	KubectlRoleARN string `yaml:"kubectl_role_arn"`
}

// EnvConfig defines a deployment environment.
type EnvConfig struct {
	Path     string            `yaml:"path"`     // Relative path from repo root to unit directory
	Provider string            `yaml:"provider"` // Cloud provider: "aws", "azure", etc.
	Auth     map[string]string `yaml:"auth"`     // Provider-specific credentials
}

// UnitOverride provides per-unit configuration that can't be auto-discovered.
type UnitOverride struct {
	Auth          map[string]string `yaml:"auth,omitempty"`
	BootstrapArgs []string          `yaml:"bootstrap_args,omitempty"`
	TeardownArgs  []string          `yaml:"teardown_args,omitempty"`
	Hook          string            `yaml:"hook,omitempty"`
	HookTarget    string            `yaml:"hook_target,omitempty"`
	HookConfig    map[string]string `yaml:"hook_config,omitempty"`
	ImplicitDeps  []string          `yaml:"implicit_deps,omitempty"`
}

// ManualStep defines a prerequisite that requires user action before a unit can be applied.
type ManualStep struct {
	Name         string      `yaml:"name"`
	Before       string      `yaml:"before"`       // Unit name this step must complete before
	Instructions string      `yaml:"instructions"` // Human-readable instructions
	Check        StepCheck   `yaml:"check"`        // Automated check for whether the step is done
}

// StepCheck defines how to verify a manual step has been completed.
type StepCheck struct {
	Type     string `yaml:"type"`      // "secret_exists" or "file_contains"
	SecretID string `yaml:"secret_id,omitempty"`
	Profile  string `yaml:"profile,omitempty"`
	File     string `yaml:"file,omitempty"`
	Pattern  string `yaml:"pattern,omitempty"`
}

// LockdownStep defines a post-bootstrap operation to harden infrastructure.
type LockdownStep struct {
	Unit        string `yaml:"unit"`
	Description string `yaml:"description"`
}

// Load reads and parses a .platctl.yaml file.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config %s: %w", path, err)
	}
	return Parse(data)
}

// Parse decodes YAML data into a Config.
func Parse(data []byte) (*Config, error) {
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config: %w", err)
	}
	if err := cfg.validate(); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func (c *Config) validate() error {
	if len(c.Environments) == 0 {
		return fmt.Errorf("config must define at least one environment")
	}
	for name, env := range c.Environments {
		if env.Path == "" {
			return fmt.Errorf("environment %q: path is required", name)
		}
		if env.Provider == "" {
			return fmt.Errorf("environment %q: provider is required", name)
		}
	}
	for name, override := range c.Overrides {
		if override.Hook != "" {
			valid := map[string]bool{"crd_two_stage": true, "eni_ip_validation": true, "secret_cleanup": true}
			if !valid[override.Hook] {
				return fmt.Errorf("override %q: unknown hook %q", name, override.Hook)
			}
		}
	}
	for _, step := range c.ManualSteps {
		if step.Name == "" {
			return fmt.Errorf("manual step: name is required")
		}
		if step.Before == "" {
			return fmt.Errorf("manual step %q: before is required", step.Name)
		}
		valid := map[string]bool{"secret_exists": true, "file_contains": true}
		if !valid[step.Check.Type] {
			return fmt.Errorf("manual step %q: unknown check type %q", step.Name, step.Check.Type)
		}
	}
	return nil
}

// AuthForUnit returns the effective auth config for a unit, merging env defaults with overrides.
func (c *Config) AuthForUnit(envName, unitName string) map[string]string {
	env, ok := c.Environments[envName]
	if !ok {
		return nil
	}

	// Start with env-level auth
	auth := make(map[string]string, len(env.Auth))
	for k, v := range env.Auth {
		auth[k] = v
	}

	// Override with unit-level auth if present
	qualifiedName := envName + "/" + unitName
	if override, ok := c.Overrides[qualifiedName]; ok && override.Auth != nil {
		for k, v := range override.Auth {
			auth[k] = v
		}
	}

	return auth
}
