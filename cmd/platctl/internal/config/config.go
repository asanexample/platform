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
	Validate     ValidateConfig          `yaml:"validate"`
}

// ValidateConfig holds configuration for the validate command's health checks.
type ValidateConfig struct {
	DNS            DNSValidation         `yaml:"dns"`
	PreprodDNS     DNSValidation         `yaml:"preprod_dns"`
	TransitGateway TGWValidation         `yaml:"transit_gateway"`
	CrossVPCDNS    CrossVPCDNSValidation `yaml:"cross_vpc_dns"`
	Tailscale      TailscaleValidation   `yaml:"tailscale"`
	Gateway        GatewayValidation     `yaml:"gateway"`
	PreprodGateway GatewayValidation     `yaml:"preprod_gateway"`
	Endpoints      []EndpointValidation  `yaml:"endpoints"`
	IAM            IAMValidation         `yaml:"iam"`
	// ExpectedEmptyUnits lists units whose EMPTY Terragrunt state is intentional (e.g. mimir under the
	// cost profile, a gateway-config with no per-app routes on that cluster); their state check passes
	// instead of false-failing. Full unit names ("platform/mimir").
	ExpectedEmptyUnits []string `yaml:"expected_empty_units"`
}

// DNSValidation configures the DNS delegation check. ExpectedNS is an optional override — when empty the
// check discovers the expected nameservers from the Route53 hosted zone (they churn when the zone is
// recreated). Profile is the AWS profile owning the zone (for discovery).
type DNSValidation struct {
	Zone       string   `yaml:"zone"`
	ExpectedNS []string `yaml:"expected_ns"`
	Profile    string   `yaml:"profile"`
}

// TGWValidation configures the Transit Gateway attachment check.
type TGWValidation struct {
	ID string `yaml:"id"`
}

// CrossVPCDNSValidation configures the cross-VPC DNS resolution check.
type CrossVPCDNSValidation struct {
	Endpoint string `yaml:"endpoint"`
}

// TailscaleValidation configures the Tailscale connectivity check.
type TailscaleValidation struct {
	VPCCIDRs map[string]string `yaml:"vpc_cidrs"`
}

// GatewayValidation configures the Gateway health check.
type GatewayValidation struct {
	Name      string `yaml:"name"`
	Namespace string `yaml:"namespace"`
	CertName  string `yaml:"cert_name"`
}

// EndpointValidation configures an HTTP endpoint reachability check.
type EndpointValidation struct {
	Name string `yaml:"name"`
	URL  string `yaml:"url"`
	Env  string `yaml:"env"`
}

// IAMValidation configures the IAM and access checks.
type IAMValidation struct {
	StateBucket string                      `yaml:"state_bucket"`
	Accounts    map[string]IAMAccountConfig `yaml:"accounts"`
}

// IAMAccountConfig holds IAM configuration for a single AWS account.
type IAMAccountConfig struct {
	ID              string `yaml:"id"`
	DeployerRoleARN string `yaml:"deployer_role_arn"`
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
	// TeardownSkip keeps a unit out of teardown — it stays in the graph (so its dependents still order
	// correctly) but is never destroyed. Used for bootstrap-tier infra that must survive a rebuild, like
	// iam-roles (the PlatformDeployer role the next bootstrap assumes) — analogous to the state backend,
	// which teardown already leaves alone. Without it, recreating the role needs the break-glass
	// OrganizationAccountAccessRole path (scripts/bootstrap-iam-roles.sh).
	TeardownSkip bool `yaml:"teardown_skip,omitempty"`
}

// ManualStep defines a prerequisite that requires user action before a unit can be applied.
type ManualStep struct {
	Name         string    `yaml:"name"`
	Before       string    `yaml:"before"`       // Unit name this step must complete before
	Instructions string    `yaml:"instructions"` // Human-readable instructions
	Check        StepCheck `yaml:"check"`        // Automated check for whether the step is done
}

// StepCheck defines how to verify a manual step has been completed.
type StepCheck struct {
	Type     string `yaml:"type"` // "secret_exists" or "file_contains"
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
			valid := map[string]bool{"crd_two_stage": true, "eni_ip_validation": true, "secret_cleanup": true, "state_purge": true, "argocd_account_token": true}
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
